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

public struct PlotterSpeechEffectRegistrySnapshot: Sendable {
  public let admissionClosed: Bool
  public let activeRequests: [PlotterSpeechEffectRequest]
  public let terminalRequests: [PlotterSpeechEffectTerminal]

  public init(
    admissionClosed: Bool,
    activeRequests: [PlotterSpeechEffectRequest],
    terminalRequests: [PlotterSpeechEffectTerminal]
  ) {
    self.admissionClosed = admissionClosed
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
  private var activeByID: [UUID: PlotterSpeechEffectRequest] = [:]
  private var terminalByID: [UUID: PlotterSpeechEffectTerminal] = [:]
  private var terminalOrder: [UUID] = []

  public init(announcer: any SpeechAnnouncing = NativeSpeechAnnouncer()) {
    self.announcer = announcer
  }

  /// Starts one identity-bound advisory request. Concurrent requests proceed
  /// through the retained native FIFO queue; this lane never adds a second
  /// queue or task owner.
  public func perform(_ request: PlotterSpeechEffectRequest) async -> SpeechAnnouncementOutcome {
    let message = request.message.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !message.isEmpty else { return .completed }
    guard !isShutdown else { return .cancelled }
    guard activeByID[request.id] == nil, terminalByID[request.id] == nil else {
      return .failed("The advisory speech request identity has already been used.")
    }
    guard activeByID.count < Self.maximumActiveRequests else {
      return .failed("The advisory speech effect lane is at its bounded capacity.")
    }

    let admitted = PlotterSpeechEffectRequest(id: request.id, message: message)
    activeByID[admitted.id] = admitted
    let outcome = await announcer.announce(admitted.message)
    activeByID[admitted.id] = nil
    recordTerminal(request: admitted, outcome: outcome)
    return outcome
  }

  /// Closes admission before the first suspension, then asks the retained
  /// native owner to cancel every queued or active utterance by its own queue
  /// identity. A suspended request cannot begin synthesis after this latch.
  public func shutdown() async {
    guard !isShutdown else { return }
    isShutdown = true
    await announcer.cancelForShutdown()
  }

  public func snapshot() -> PlotterSpeechEffectRegistrySnapshot {
    PlotterSpeechEffectRegistrySnapshot(
      admissionClosed: isShutdown,
      activeRequests: activeByID.values.sorted { $0.id.uuidString < $1.id.uuidString },
      terminalRequests: terminalOrder.compactMap { terminalByID[$0] }
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
}
