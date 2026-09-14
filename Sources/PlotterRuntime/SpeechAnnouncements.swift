@preconcurrency import AVFoundation
import Foundation

public enum SpeechAnnouncementOutcome: Hashable, Sendable {
  case completed
  case failed(String)
  case timedOut
  case cancelled
}

public protocol SpeechAnnouncing: Sendable {
  func announce(_ text: String) async -> SpeechAnnouncementOutcome
  func cancelPendingAnnouncements() async
  func cancelForShutdown() async
}

/// Execution cancellation shared by an already admitted effect and its lower
/// queue admission. It carries no setting, queue, or physical authority.
package final class SpeechAnnouncementAdmissionToken: @unchecked Sendable {
  private let lock = NSLock()
  private var valid = true
  package init() {}
  package var isValid: Bool { lock.withLock { valid } }
  package func invalidate() { lock.withLock { valid = false } }
}

package enum SpeechAnnouncementExecutionContext {
  @TaskLocal package static var admissionToken: SpeechAnnouncementAdmissionToken?
}

/// Pure ordering state shared by the native queue and deterministic tests.
/// Resolution is identity-bound, so a delayed callback for an older request
/// cannot advance or complete the request that followed it.
struct SpeechAnnouncementQueueState: Sendable {
  private(set) var generation: UInt64
  init(generation: UInt64 = 0) { self.generation = generation }
  private(set) var activeID: UUID?
  private(set) var pendingIDs: [UUID] = []

  mutating func enqueue(_ id: UUID, generation: UInt64? = nil) -> UUID? {
    guard generation == nil || generation == self.generation else { return nil }
    pendingIDs.append(id)
    return startNextIfNeeded()
  }

  mutating func resolve(_ id: UUID) -> UUID? {
    guard activeID == id else { return nil }
    activeID = nil
    return startNextIfNeeded()
  }

  mutating func cancelAll(advancingTo generation: UInt64? = nil) -> [UUID] {
    if let generation {
      guard generation >= self.generation else { return [] }
      self.generation = generation
    }
    let cancelled = activeID.map { [$0] } ?? []
    activeID = nil
    let result = cancelled + pendingIDs
    pendingIDs.removeAll(keepingCapacity: false)
    return result
  }

  mutating func cancel(_ id: UUID) -> UUID? {
    if activeID == id { return resolve(id) }
    pendingIDs.removeAll { $0 == id }
    return nil
  }

  private mutating func startNextIfNeeded() -> UUID? {
    guard activeID == nil, !pendingIDs.isEmpty else { return nil }
    let id = pendingIDs.removeFirst()
    activeID = id
    return id
  }
}

@MainActor
final class SpeechSynthesisQueue: NSObject, AVSpeechSynthesizerDelegate {
  private final class Request {
    let id: UUID
    let message: String
    let continuation: CheckedContinuation<SpeechAnnouncementOutcome, Never>
    let admissionToken: SpeechAnnouncementAdmissionToken?
    var timeoutTask: Task<Void, Never>?
    var utteranceIdentity: ObjectIdentifier?

    init(
      id: UUID,
      message: String,
      continuation: CheckedContinuation<SpeechAnnouncementOutcome, Never>,
      admissionToken: SpeechAnnouncementAdmissionToken?
    ) {
      self.id = id
      self.message = message
      self.continuation = continuation
      self.admissionToken = admissionToken
    }
  }

  private let synthesizer: AVSpeechSynthesizer?
  private let voiceLanguage: String?
  private let timeoutNanoseconds: UInt64
  private var requests: [UUID: Request] = [:]
  private var order: SpeechAnnouncementQueueState
  var requestCount: Int { requests.count }
  var activeRequestID: UUID? { order.activeID }

  init(voiceLanguage: String?, timeoutNanoseconds: UInt64, generation: UInt64 = 0,
    synthesizer: AVSpeechSynthesizer? = AVSpeechSynthesizer()) {
    self.synthesizer = synthesizer
    self.order = SpeechAnnouncementQueueState(generation: generation)
    self.voiceLanguage = voiceLanguage
    self.timeoutNanoseconds = max(1, timeoutNanoseconds)
    super.init()
    synthesizer?.delegate = self
  }

  func enqueue(_ message: String, generation: UInt64,
    admissionToken: SpeechAnnouncementAdmissionToken?) async -> SpeechAnnouncementOutcome {
    let id = UUID()
    return await withTaskCancellationHandler {
      guard !Task.isCancelled, order.generation == generation,
        admissionToken?.isValid != false else { return .cancelled }
      return await withCheckedContinuation { continuation in
        let request = Request(id: id, message: message, continuation: continuation, admissionToken: admissionToken)
        requests[id] = request
        if let nextID = order.enqueue(id, generation: generation) { start(nextID) }
      }
    } onCancel: {
      Task { @MainActor [weak self] in self?.cancel(id) }
    }
  }

  private func cancel(_ id: UUID) {
    guard let request = requests.removeValue(forKey: id) else { return }
    let wasActive = order.activeID == id
    let nextID = order.cancel(id)
    request.timeoutTask?.cancel()
    request.continuation.resume(returning: .cancelled)
    if wasActive { synthesizer?.stopSpeaking(at: .immediate) }
    if let nextID { start(nextID) }
  }

  func cancelAll(advancingTo generation: UInt64) {
    guard generation >= order.generation else { return }
    let cancelledIDs = order.cancelAll(advancingTo: generation)
    for id in cancelledIDs {
      guard let request = requests.removeValue(forKey: id) else { continue }
      request.timeoutTask?.cancel()
      request.continuation.resume(returning: .cancelled)
    }
    synthesizer?.stopSpeaking(at: .immediate)
  }

  nonisolated func speechSynthesizer(
    _: AVSpeechSynthesizer,
    didFinish utterance: AVSpeechUtterance
  ) {
    let identity = ObjectIdentifier(utterance)
    Task { @MainActor [weak self] in
      self?.finishActive(for: identity, with: .completed)
    }
  }

  nonisolated func speechSynthesizer(
    _: AVSpeechSynthesizer,
    didCancel utterance: AVSpeechUtterance
  ) {
    let identity = ObjectIdentifier(utterance)
    Task { @MainActor [weak self] in
      self?.finishActive(for: identity, with: .cancelled)
    }
  }

  private func start(_ id: UUID) {
    guard order.activeID == id, let request = requests[id] else { return }
    // An old completion can advance the FIFO while bulk cancellation crosses
    // MainActor. A retired successor must never reach synthesis in that gap.
    guard request.admissionToken?.isValid != false else {
      finishActive(id: id, with: .cancelled)
      return
    }
    let utterance = AVSpeechUtterance(string: request.message)
    request.utteranceIdentity = ObjectIdentifier(utterance)
    if let voiceLanguage, let voice = AVSpeechSynthesisVoice(language: voiceLanguage) {
      utterance.voice = voice
    }
    let id = request.id
    let timeout = timeoutNanoseconds
    request.timeoutTask = Task { [weak self] in
      do {
        try await Task.sleep(nanoseconds: timeout)
      } catch {
        return
      }
      guard !Task.isCancelled else { return }
      self?.timeOut(id)
    }
    synthesizer?.speak(utterance)
  }

  private func timeOut(_ id: UUID) {
    finishActive(id: id, with: .timedOut, stopSynthesizer: true)
  }

  private func finishActive(
    for utteranceIdentity: ObjectIdentifier,
    with outcome: SpeechAnnouncementOutcome
  ) {
    guard let id = order.activeID,
      requests[id]?.utteranceIdentity == utteranceIdentity
    else { return }
    finishActive(id: id, with: outcome)
  }

  private func finishActive(
    id: UUID,
    with outcome: SpeechAnnouncementOutcome,
    stopSynthesizer: Bool = false
  ) {
    guard order.activeID == id, let request = requests.removeValue(forKey: id) else { return }
    let nextID = order.resolve(id)
    request.timeoutTask?.cancel()
    request.timeoutTask = nil
    request.utteranceIdentity = nil
    request.continuation.resume(returning: outcome)
    if stopSynthesizer {
      synthesizer?.stopSpeaking(at: .immediate)
    }
    if let nextID { start(nextID) }
  }
}

/// Output-only advisory speech. Requests are serialized and each caller waits
/// for synthesis completion or a bounded result; ordinary announcements never
/// interrupt one another.
public actor NativeSpeechAnnouncer: SpeechAnnouncing {
  public static let defaultTimeoutNanoseconds: UInt64 = 10_000_000_000

  private let queueFactory: @MainActor @Sendable (UInt64) async -> SpeechSynthesisQueue
  private var queue: SpeechSynthesisQueue?
  private var queueCreation: Task<SpeechSynthesisQueue, Never>?
  private var generation: UInt64 = 0
  private var cancellationTask: Task<Void, Never>?
  private var cancellationID: UUID?
  private var isShutdown = false
  var hasPendingCancellation: Bool { cancellationTask != nil }

  public init(
    voiceLanguage: String? = nil,
    timeoutNanoseconds: UInt64 = defaultTimeoutNanoseconds
  ) {
    queueFactory = { generation in
      SpeechSynthesisQueue(voiceLanguage: voiceLanguage,
        timeoutNanoseconds: timeoutNanoseconds, generation: generation)
    }
  }

  /// Internal factory seam exercises queue-creation suspension without audio.
  init(queueFactory: @escaping @MainActor @Sendable (UInt64) async -> SpeechSynthesisQueue) {
    self.queueFactory = queueFactory
  }

  public func announce(_ text: String) async -> SpeechAnnouncementOutcome {
    let token = SpeechAnnouncementExecutionContext.admissionToken
    guard !isShutdown, !Task.isCancelled, token?.isValid != false else { return .cancelled }
    let requestGeneration = generation
    let message = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !message.isEmpty else { return .completed }
    if let cancellationTask { await cancellationTask.value }
    guard !isShutdown, generation == requestGeneration, !Task.isCancelled,
      token?.isValid != false else { return .cancelled }
    let queue = await synthesisQueue()
    guard !isShutdown, generation == requestGeneration, !Task.isCancelled,
      token?.isValid != false else { return .cancelled }
    // MainActor admission rechecks both values; this actor check alone cannot
    // reject an enqueue already suspended on that actor when cancellation wins.
    return await queue.enqueue(message, generation: requestGeneration, admissionToken: token)
  }

  public func cancelPendingAnnouncements() async {
    generation &+= 1
    let nextGeneration = generation
    let previous = cancellationTask
    let retainedQueue = queue
    let creation = queueCreation
    let id = UUID()
    let task = Task {
      if let previous { await previous.value }
      if let retainedQueue {
        await retainedQueue.cancelAll(advancingTo: nextGeneration)
      } else if let creation {
        let created = await creation.value
        await created.cancelAll(advancingTo: nextGeneration)
      }
    }
    cancellationID = id
    cancellationTask = task
    await task.value
    if cancellationID == id { cancellationTask = nil; cancellationID = nil }
  }

  public func cancelForShutdown() async {
    isShutdown = true
    await cancelPendingAnnouncements()
  }

  private func synthesisQueue() async -> SpeechSynthesisQueue {
    if let queue { return queue }
    if let queueCreation { return await queueCreation.value }
    let factory = queueFactory, initialGeneration = generation
    let creation = Task { @MainActor in await factory(initialGeneration) }
    queueCreation = creation
    let created = await creation.value
    queue = created
    queueCreation = nil
    return created
  }
}
