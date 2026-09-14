import Foundation
import PlotterRuntime

/// One application-level advisory speech request. The identity is supplied at
/// the typed effect seam; synthesis remains a lower `SpeechAnnouncing` owner.
public struct PlotterSpeechEffectRequest: Hashable, Sendable {
  public let id: UUID
  public let message: String

  public init(id: UUID = UUID(), message: String) {
    self.id = id
    self.message = message
  }
}

public enum PlotterSpeechEffectDisposition: Hashable, Sendable {
  case completed
  case failed(String)
  case timedOut
  case cancelled

  init(_ outcome: SpeechAnnouncementOutcome) {
    switch outcome {
    case .completed: self = .completed
    case .failed(let detail): self = .failed(detail)
    case .timedOut: self = .timedOut
    case .cancelled: self = .cancelled
    }
  }
}

public struct PlotterSpeechEffectTerminal: Hashable, Sendable {
  public let request: PlotterSpeechEffectRequest
  public let disposition: PlotterSpeechEffectDisposition

  public init(request: PlotterSpeechEffectRequest, disposition: PlotterSpeechEffectDisposition) {
    self.request = request
    self.disposition = disposition
  }
}

public enum PlotterSpeechEffectAdmission: Hashable, Sendable {
  case admitted(PlotterSpeechEffectRequest)
  case refused(String)
  case cancelled
}

public struct PlotterSpeechEffectRegistrySnapshot: Sendable {
  public let admissionClosed: Bool
  public let outputEnabled: Bool
  public let isDraining: Bool
  public let activeRequests: [PlotterSpeechEffectRequest]
  public let terminalRequests: [PlotterSpeechEffectTerminal]

  public init(
    admissionClosed: Bool,
    activeRequests: [PlotterSpeechEffectRequest],
    terminalRequests: [PlotterSpeechEffectTerminal],
    outputEnabled: Bool = false, isDraining: Bool = false
  ) {
    self.admissionClosed = admissionClosed
    self.outputEnabled = outputEnabled
    self.isDraining = isDraining
    self.activeRequests = activeRequests
    self.terminalRequests = terminalRequests
  }
}

/// The typed application effect lane for advisory speech. It owns admission,
/// identity bookkeeping, bounded terminal history, and the shutdown latch.
/// `NativeSpeechAnnouncer` remains the only queue, synthesis, timeout, and
/// AVFoundation owner. Speech outcomes are deliberately advisory: callers
/// receive them but no outcome grants physical permission.
public actor PlotterSpeechEffectRuntime {
  public static let maximumActiveRequests = 16
  public static let terminalHistoryLimit = 32

  private let announcer: any SpeechAnnouncing
  private var isShutdown = false
  private var outputEnabled: Bool
  private var admissionToken = SpeechAnnouncementAdmissionToken()
  private var drainTask: Task<Void, Never>?
  private var drainID: UUID?
  private var operatorInputHasPriority = false
  private var activeByID: [UUID: PlotterSpeechEffectRequest] = [:]
  private var terminalByID: [UUID: PlotterSpeechEffectTerminal] = [:]
  private var terminalOrder: [UUID] = []
  private var taskByID: [UUID: Task<SpeechAnnouncementOutcome, Never>] = [:]
  private var activityObservers: [UUID: AsyncStream<Bool>.Continuation] = [:]

  /// Playback activity for half-duplex operator input. This observes the
  /// existing speech lane; it does not own a second synthesis queue.
  public func activity() -> AsyncStream<Bool> {
    let id = UUID()
    let (stream, continuation) = AsyncStream<Bool>.makeStream(bufferingPolicy: .bufferingNewest(1))
    activityObservers[id] = continuation
    continuation.yield(!activeByID.isEmpty)
    continuation.onTermination = { [weak self] _ in
      Task { await self?.removeActivityObserver(id) }
    }
    if isShutdown { continuation.finish() }
    return stream
  }

  private func removeActivityObserver(_ id: UUID) { activityObservers[id] = nil }

  private func publishActivity() {
    for observer in activityObservers.values { observer.yield(!activeByID.isEmpty) }
  }

  public init(announcer: any SpeechAnnouncing = NativeSpeechAnnouncer(), outputEnabled: Bool = false) {
    self.announcer = announcer
    self.outputEnabled = outputEnabled
  }

  /// The latest requested setting owns admission. A later enable joins the
  /// prior drain before any new effect can enter the existing native queue.
  public func setOutputEnabled(_ enabled: Bool) async {
    guard !isShutdown else { return }
    outputEnabled = enabled
    if !enabled { beginDrain() }
    await joinDrain()
  }

  /// Starts one identity-bound advisory request. Concurrent requests proceed
  /// through the retained native FIFO queue; this lane never adds a second
  /// queue or task owner.
  public func perform(_ request: PlotterSpeechEffectRequest) async -> SpeechAnnouncementOutcome {
    switch admit(request) {
    case .admitted(let admitted):
      return await taskByID[admitted.id]?.value ?? terminalOutcome(for: admitted.id)
        ?? .cancelled
    case .refused(let detail):
      return .failed(detail)
    case .cancelled:
      return .cancelled
    }
  }

  /// Admits one advisory request and returns before synthesis completes. The
  /// retained task is the execution owner; `NativeSpeechAnnouncer` remains the
  /// sole FIFO/audio queue. This is used where speech must be dispatched before
  /// a semantic transition but its terminal playback cannot gate that transition.
  public func start(_ request: PlotterSpeechEffectRequest) -> PlotterSpeechEffectAdmission {
    admit(request)
  }

  /// Cancel one superseded spoken prompt while leaving workflow cues alone.
  public func cancel(_ requestID: UUID) {
    taskByID[requestID]?.cancel()
  }

  /// During a moving exercise the microphone must be available for Stop.
  /// Cancel advisory playback and suppress new cues until that phase ends;
  /// cancelling speech never cancels the operation that requested it.
  public func prioritizeOperatorInput(_ enabled: Bool) async {
    guard !isShutdown else { return }
    operatorInputHasPriority = enabled
    if enabled { beginDrain() }
    await joinDrain()
  }

  private func beginDrain(permanent: Bool = false) {
    if drainTask != nil, !permanent { return }
    admissionToken.invalidate()
    let previous = drainTask
    let tasks = Array(taskByID.values)
    let id = UUID()
    drainID = id
    drainTask = Task { [announcer] in
      if let previous { await previous.value }
      // Clear the FIFO before individual task cancellation can advance it.
      if permanent { await announcer.cancelForShutdown() }
      else { await announcer.cancelPendingAnnouncements() }
      for task in tasks { task.cancel() }
      for task in tasks { _ = await task.value }
    }
  }

  private func joinDrain() async {
    guard let task = drainTask else { return }
    let id = drainID
    await task.value
    if drainID == id {
      drainTask = nil
      drainID = nil
      admissionToken = SpeechAnnouncementAdmissionToken()
    }
  }

  /// Closes admission before the first suspension, then asks the retained
  /// native owner to cancel every queued or active utterance by its own queue
  /// identity. A suspended request cannot begin synthesis after this latch.
  public func shutdown() async {
    if !isShutdown {
      isShutdown = true
      outputEnabled = false
      beginDrain(permanent: true)
    }
    await joinDrain()
    for observer in activityObservers.values { observer.finish() }
    activityObservers.removeAll()
  }

  public func snapshot() -> PlotterSpeechEffectRegistrySnapshot {
    PlotterSpeechEffectRegistrySnapshot(
      admissionClosed: isShutdown,
      activeRequests: activeByID.values.sorted { $0.id.uuidString < $1.id.uuidString },
      terminalRequests: terminalOrder.compactMap { terminalByID[$0] },
      outputEnabled: outputEnabled, isDraining: drainTask != nil
    )
  }

  private func recordTerminal(
    request: PlotterSpeechEffectRequest,
    outcome: SpeechAnnouncementOutcome
  ) {
    terminalByID[request.id] = PlotterSpeechEffectTerminal(
      request: request,
      disposition: PlotterSpeechEffectDisposition(outcome)
    )
    terminalOrder.append(request.id)
    while terminalOrder.count > Self.terminalHistoryLimit {
      terminalByID[terminalOrder.removeFirst()] = nil
    }
  }

  private func admit(_ request: PlotterSpeechEffectRequest) -> PlotterSpeechEffectAdmission {
    let message = request.message.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !isShutdown, outputEnabled, !operatorInputHasPriority, drainTask == nil else { return .cancelled }
    guard activeByID[request.id] == nil, terminalByID[request.id] == nil else {
      return .refused("The advisory speech request identity has already been used.")
    }
    guard activeByID.count < Self.maximumActiveRequests else {
      return .refused("The advisory speech effect lane is at its bounded capacity.")
    }
    let admitted = PlotterSpeechEffectRequest(id: request.id, message: message)
    if message.isEmpty {
      recordTerminal(request: admitted, outcome: .completed)
      return .admitted(admitted)
    }
    activeByID[admitted.id] = admitted
    publishActivity()
    let token = admissionToken
    let task = Task { [weak self, announcer] in
      let result = await SpeechAnnouncementExecutionContext.$admissionToken.withValue(token) {
        guard token.isValid, !Task.isCancelled else { return SpeechAnnouncementOutcome.cancelled }
        return await announcer.announce(admitted.message)
      }
      let outcome = await self?.finish(admitted, outcome: result, token: token) ?? .cancelled
      return outcome
    }
    taskByID[admitted.id] = task
    return .admitted(admitted)
  }

  private func finish(
    _ request: PlotterSpeechEffectRequest,
    outcome: SpeechAnnouncementOutcome, token: SpeechAnnouncementAdmissionToken
  ) -> SpeechAnnouncementOutcome {
    guard activeByID.removeValue(forKey: request.id) != nil else { return terminalOutcome(for: request.id) ?? .cancelled }
    let outcome = token.isValid ? outcome : .cancelled
    taskByID[request.id] = nil
    recordTerminal(request: request, outcome: outcome)
    publishActivity()
    return outcome
  }

  private func terminalOutcome(for id: UUID) -> SpeechAnnouncementOutcome? {
    guard let disposition = terminalByID[id]?.disposition else { return nil }
    switch disposition {
    case .completed: return .completed
    case .failed(let detail): return .failed(detail)
    case .timedOut: return .timedOut
    case .cancelled: return .cancelled
    }
  }
}
