import Foundation
import Testing

@testable import PlotterRuntime

@Suite("Speech announcements")
struct SpeechAnnouncementsTests {
  @Test("cancelling a queued prompt preserves active workflow speech and its successor")
  func cancelOnePrompt() {
    let cue = UUID(), prompt = UUID(), successor = UUID()
    var state = SpeechAnnouncementQueueState()
    _ = state.enqueue(cue)
    _ = state.enqueue(prompt)
    _ = state.enqueue(successor)
    #expect(state.cancel(prompt) == nil)
    #expect(state.activeID == cue)
    #expect(state.pendingIDs == [successor])
    #expect(state.cancel(cue) == successor)
    #expect(state.resolve(cue) == nil)
    #expect(state.activeID == successor)
  }
  @Test("empty announcement completes without starting speech")
  func emptyAnnouncement() async {
    let announcer = NativeSpeechAnnouncer(timeoutNanoseconds: 1_000_000)
    #expect(await announcer.announce("   ") == .completed)
  }

  @Test("queued announcements serialize and late completion cannot resolve the successor")
  func orderedIdentityBoundResolution() {
    let first = UUID()
    let second = UUID()
    var state = SpeechAnnouncementQueueState()

    #expect(state.enqueue(first) == first)
    #expect(state.activeID == first)
    #expect(state.enqueue(second) == nil)
    #expect(state.activeID == first)
    #expect(state.pendingIDs == [second])

    #expect(state.resolve(first) == second)
    #expect(state.activeID == second)
    #expect(state.resolve(first) == nil)
    #expect(state.activeID == second)
    #expect(state.resolve(second) == nil)
    #expect(state.activeID == nil)
  }

  @Test("cancelled queue returns active then pending identities exactly once")
  func cancellationOrdering() {
    let first = UUID()
    let second = UUID()
    var state = SpeechAnnouncementQueueState()
    _ = state.enqueue(first)
    _ = state.enqueue(second)
    #expect(state.cancelAll() == [first, second])
    #expect(state.cancelAll().isEmpty)
  }

  @Test("bulk cancellation advances queue generation and old callbacks cannot affect fresh work")
  func cancelledGenerationCannotReenter() {
    let first = UUID(), queued = UUID(), delayed = UUID(), fresh = UUID()
    var state = SpeechAnnouncementQueueState()
    _ = state.enqueue(first, generation: 0)
    _ = state.enqueue(queued, generation: 0)
    #expect(state.cancelAll(advancingTo: 1) == [first, queued])
    #expect(state.enqueue(delayed, generation: 0) == nil)
    #expect(state.pendingIDs.isEmpty)
    #expect(state.enqueue(fresh, generation: 1) == fresh)
    #expect(state.resolve(first) == nil)
    #expect(state.cancelAll(advancingTo: 0).isEmpty)
    #expect(state.activeID == fresh)
  }

  @Test("actual MainActor queue rejects a stale enqueue after bulk cancellation")
  @MainActor
  func delayedQueueAdmission() async {
    let queue = SpeechSynthesisQueue(voiceLanguage: nil, timeoutNanoseconds: 60_000_000_000,
      synthesizer: nil)
    let token = SpeechAnnouncementAdmissionToken()
    let delayed = Task.detached { await queue.enqueue("Delayed old cue", generation: 0, admissionToken: token) }
    // No suspension on MainActor precedes cancellation; the other task's
    // actor hop can be queued but cannot admit its old-generation request.
    queue.cancelAll(advancingTo: 1)
    #expect(await delayed.value == .cancelled)
    #expect(queue.requestCount == 0)
    token.invalidate()
    #expect(await queue.enqueue("Invalid execution", generation: 1, admissionToken: token) == .cancelled)
    #expect(queue.requestCount == 0)
  }

  @Test("native cancellation joins a suspended queue creation and permits only later generation")
  @MainActor
  func cancellationDuringQueueCreation() async throws {
    let gate = SpeechCreationGate()
    let probe = SilentSpeechQueueFactory()
    let announcer = NativeSpeechAnnouncer(queueFactory: { generation in
      await gate.wait()
      return probe.make(generation)
    })
    let old = Task { await announcer.announce("Before creation completed") }
    try await lowerSpeechEventually { await gate.isWaiting }
    let cancellation = Task { await announcer.cancelPendingAnnouncements() }
    try await lowerSpeechEventually { await announcer.hasPendingCancellation }
    await gate.release()
    await cancellation.value
    #expect(await old.value == .cancelled)
    #expect(probe.queue?.requestCount == 0)
    let fresh = Task { await announcer.announce("Fresh after cancellation") }
    try await lowerSpeechEventually { await MainActor.run { probe.queue?.requestCount == 1 } }
    await announcer.cancelPendingAnnouncements()
    #expect(await fresh.value == .cancelled)
    #expect(probe.queue?.requestCount == 0)
    await announcer.cancelForShutdown()
    #expect(await announcer.announce("After permanent shutdown") == .cancelled)
  }

  @Test("retired execution token prevents an old task entering Native after its cancellation completed")
  @MainActor
  func delayedNativeEntry() async throws {
    let gate = SpeechCreationGate()
    let probe = SilentSpeechQueueFactory()
    let announcer = NativeSpeechAnnouncer(queueFactory: { generation in probe.make(generation) })
    let token = SpeechAnnouncementAdmissionToken()
    let delayed = Task {
      await SpeechAnnouncementExecutionContext.$admissionToken.withValue(token) {
        await gate.wait()
        return await announcer.announce("Old task entered late")
      }
    }
    try await lowerSpeechEventually { await gate.isWaiting }
    token.invalidate()
    await announcer.cancelPendingAnnouncements()
    await gate.release()
    #expect(await delayed.value == .cancelled)
    #expect(probe.queue == nil)
    await announcer.cancelForShutdown()
  }

  @Test("bulk native drain settles active and queued requests without starting a successor")
  @MainActor
  func nativeBulkDrain() async throws {
    let queue = SpeechSynthesisQueue(voiceLanguage: nil, timeoutNanoseconds: 60_000_000_000,
      synthesizer: nil)
    let token = SpeechAnnouncementAdmissionToken()
    let first = Task { await queue.enqueue("Active", generation: 0, admissionToken: token) }
    try await lowerSpeechEventually { await MainActor.run { queue.requestCount == 1 } }
    let active = queue.activeRequestID
    let second = Task { await queue.enqueue("Queued", generation: 0, admissionToken: token) }
    try await lowerSpeechEventually { await MainActor.run { queue.requestCount == 2 } }
    #expect(queue.activeRequestID == active)
    token.invalidate()
    queue.cancelAll(advancingTo: 1)
    #expect(queue.requestCount == 0)
    #expect(queue.activeRequestID == nil)
    #expect(await first.value == .cancelled)
    #expect(await second.value == .cancelled)
  }

}


private enum LowerSpeechFixtureFailure: Error { case timeout }
@MainActor
private func lowerSpeechEventually(_ condition: () async -> Bool) async throws {
  let deadline = ContinuousClock.now.advanced(by: .seconds(3))
  while !(await condition()), ContinuousClock.now < deadline { await Task.yield() }
  guard await condition() else { throw LowerSpeechFixtureFailure.timeout }
}

private actor SpeechCreationGate {
  private var released = false
  private var continuation: CheckedContinuation<Void, Never>?
  var isWaiting: Bool { continuation != nil }
  func wait() async {
    if released { return }
    await withCheckedContinuation { continuation = $0 }
  }
  func release() { released = true; continuation?.resume(); continuation = nil }
}

@MainActor
private final class SilentSpeechQueueFactory {
  private(set) var queue: SpeechSynthesisQueue?
  func make(_ generation: UInt64) -> SpeechSynthesisQueue {
    let created = SpeechSynthesisQueue(voiceLanguage: nil, timeoutNanoseconds: 60_000_000_000,
      generation: generation, synthesizer: nil)
    queue = created
    return created
  }
}
