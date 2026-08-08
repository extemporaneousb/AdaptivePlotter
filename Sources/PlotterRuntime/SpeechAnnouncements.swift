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
  func cancelForShutdown() async
}

/// Pure ordering state shared by the native queue and deterministic tests.
/// Resolution is identity-bound, so a delayed callback for an older request
/// cannot advance or complete the request that followed it.
struct SpeechAnnouncementQueueState: Sendable {
  private(set) var activeID: UUID?
  private(set) var pendingIDs: [UUID] = []

  mutating func enqueue(_ id: UUID) -> UUID? {
    pendingIDs.append(id)
    return startNextIfNeeded()
  }

  mutating func resolve(_ id: UUID) -> UUID? {
    guard activeID == id else { return nil }
    activeID = nil
    return startNextIfNeeded()
  }

  mutating func cancelAll() -> [UUID] {
    let cancelled = activeID.map { [$0] } ?? []
    activeID = nil
    let result = cancelled + pendingIDs
    pendingIDs.removeAll(keepingCapacity: false)
    return result
  }

  private mutating func startNextIfNeeded() -> UUID? {
    guard activeID == nil, !pendingIDs.isEmpty else { return nil }
    let id = pendingIDs.removeFirst()
    activeID = id
    return id
  }
}

@MainActor
private final class SpeechSynthesisQueue: NSObject, AVSpeechSynthesizerDelegate {
  private final class Request {
    let id = UUID()
    let message: String
    let continuation: CheckedContinuation<SpeechAnnouncementOutcome, Never>
    var timeoutTask: Task<Void, Never>?
    var utteranceIdentity: ObjectIdentifier?

    init(
      message: String,
      continuation: CheckedContinuation<SpeechAnnouncementOutcome, Never>
    ) {
      self.message = message
      self.continuation = continuation
    }
  }

  private let synthesizer = AVSpeechSynthesizer()
  private let voiceLanguage: String?
  private let timeoutNanoseconds: UInt64
  private var requests: [UUID: Request] = [:]
  private var order = SpeechAnnouncementQueueState()

  init(voiceLanguage: String?, timeoutNanoseconds: UInt64) {
    self.voiceLanguage = voiceLanguage
    self.timeoutNanoseconds = max(1, timeoutNanoseconds)
    super.init()
    synthesizer.delegate = self
  }

  func enqueue(_ message: String) async -> SpeechAnnouncementOutcome {
    await withCheckedContinuation { continuation in
      let request = Request(message: message, continuation: continuation)
      requests[request.id] = request
      if let nextID = order.enqueue(request.id) { start(nextID) }
    }
  }

  func cancelAll() {
    let cancelledIDs = order.cancelAll()
    for id in cancelledIDs {
      guard let request = requests.removeValue(forKey: id) else { continue }
      request.timeoutTask?.cancel()
      request.continuation.resume(returning: .cancelled)
    }
    synthesizer.stopSpeaking(at: .immediate)
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
    synthesizer.speak(utterance)
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
      synthesizer.stopSpeaking(at: .immediate)
    }
    if let nextID { start(nextID) }
  }
}

/// Output-only advisory speech. Requests are serialized and each caller waits
/// for synthesis completion or a bounded result; ordinary announcements never
/// interrupt one another.
public actor NativeSpeechAnnouncer: SpeechAnnouncing {
  public static let defaultTimeoutNanoseconds: UInt64 = 10_000_000_000

  private let voiceLanguage: String?
  private let timeoutNanoseconds: UInt64
  private var queue: SpeechSynthesisQueue?

  public init(
    voiceLanguage: String? = nil,
    timeoutNanoseconds: UInt64 = defaultTimeoutNanoseconds
  ) {
    self.voiceLanguage = voiceLanguage
    self.timeoutNanoseconds = max(1, timeoutNanoseconds)
  }

  public func announce(_ text: String) async -> SpeechAnnouncementOutcome {
    let message = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !message.isEmpty else { return .completed }
    let queue = await synthesisQueue()
    return await queue.enqueue(message)
  }

  public func cancelForShutdown() async {
    guard let queue else { return }
    await queue.cancelAll()
  }

  private func synthesisQueue() async -> SpeechSynthesisQueue {
    if let queue { return queue }
    let created = await SpeechSynthesisQueue(
      voiceLanguage: voiceLanguage,
      timeoutNanoseconds: timeoutNanoseconds
    )
    queue = created
    return created
  }
}
