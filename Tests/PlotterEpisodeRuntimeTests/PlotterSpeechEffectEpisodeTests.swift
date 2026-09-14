import Foundation
import PlotterEpisodeRuntime
@testable import PlotterRuntime
import Testing

@Suite("EA-10G advisory speech effect lane")
struct PlotterSpeechEffectEpisodeTests {
  @Test("admission returns while advisory playback remains active")
  func startDoesNotAwaitTerminalPlayback() async {
    let announcer = BlockingSpeechAnnouncer()
    let runtime = PlotterSpeechEffectRuntime(announcer: announcer, outputEnabled: true)
    let request = PlotterSpeechEffectRequest(message: "Nonblocking advisory")

    #expect(await runtime.start(request) == .admitted(request))
    await announcer.waitUntilStarted()

    let active = await runtime.snapshot()
    #expect(active.activeRequests == [request])
    #expect(active.terminalRequests.isEmpty)

    await runtime.shutdown()
    let settled = await runtime.snapshot()
    #expect(settled.activeRequests.isEmpty)
    #expect(settled.terminalRequests == [.init(request: request, disposition: .cancelled)])
  }

  @Test("identity-bound terminal results retain completion and failure without physical authority")
  func terminalResultsAreBoundedAndTyped() async {
    let announcer = ScriptedSpeechAnnouncer(outcomes: [.completed, .failed("output unavailable")])
    let runtime = PlotterSpeechEffectRuntime(announcer: announcer, outputEnabled: true)
    let completed = PlotterSpeechEffectRequest(id: UUID(), message: "First advisory")
    let failed = PlotterSpeechEffectRequest(id: UUID(), message: "Second advisory")

    #expect(await runtime.perform(completed) == .completed)
    #expect(await runtime.perform(failed) == .failed("output unavailable"))

    let snapshot = await runtime.snapshot()
    #expect(!snapshot.admissionClosed)
    #expect(snapshot.activeRequests.isEmpty)
    #expect(snapshot.terminalRequests == [
      .init(request: completed, disposition: .completed),
      .init(request: failed, disposition: .failed("output unavailable")),
    ])
  }

  @Test("shutdown closes admission before cancelling the retained lower queue")
  func shutdownCancelsActiveSpeechAndCannotStartSuccessor() async {
    let announcer = BlockingSpeechAnnouncer()
    let runtime = PlotterSpeechEffectRuntime(announcer: announcer, outputEnabled: true)
    let active = PlotterSpeechEffectRequest(message: "Active advisory")
    let running = Task { await runtime.perform(active) }
    await announcer.waitUntilStarted()

    await runtime.shutdown()

    #expect(await running.value == .cancelled)
    #expect(
      await runtime.perform(.init(message: "Must not begin after shutdown")) == .cancelled
    )
    #expect(await announcer.messages == ["Active advisory"])
    let snapshot = await runtime.snapshot()
    #expect(snapshot.admissionClosed)
    #expect(snapshot.activeRequests.isEmpty)
    #expect(snapshot.terminalRequests == [.init(request: active, disposition: .cancelled)])
  }

  @Test("output starts off and disabled calls never reach the announcer")
  func defaultOff() async {
    let announcer = DrainControlledSpeechAnnouncer()
    let runtime = PlotterSpeechEffectRuntime(announcer: announcer)
    #expect(await runtime.start(.init(message: "No output")) == .cancelled)
    #expect(await runtime.perform(.init(message: "Still no output")) == .cancelled)
    #expect(await announcer.messages.isEmpty)
    #expect(await runtime.snapshot().terminalRequests.isEmpty)
    await runtime.shutdown()
  }

  @Test("off drains all admitted identities and does not alter a previously completed result")
  func offDrainsAndPreservesTerminals() async throws {
    let announcer = DrainControlledSpeechAnnouncer()
    let runtime = PlotterSpeechEffectRuntime(announcer: announcer, outputEnabled: true)
    let completed = PlotterSpeechEffectRequest(message: "Completed before off")
    let completedTask = Task { await runtime.perform(completed) }
    try await speechEventually { await announcer.pendingCount == 1 }
    await announcer.finishAll(.completed)
    #expect(await completedTask.value == .completed)
    let first = PlotterSpeechEffectRequest(message: "Active"), second = PlotterSpeechEffectRequest(message: "Queued")
    #expect(await runtime.start(first) == .admitted(first))
    #expect(await runtime.start(second) == .admitted(second))
    try await speechEventually { await announcer.pendingCount == 2 }
    await runtime.setOutputEnabled(false)
    let snapshot = await runtime.snapshot()
    #expect(snapshot.activeRequests.isEmpty)
    #expect(snapshot.terminalRequests.first { $0.request.id == completed.id }?.disposition == .completed)
    #expect(snapshot.terminalRequests.first { $0.request.id == first.id }?.disposition == .cancelled)
    #expect(snapshot.terminalRequests.first { $0.request.id == second.id }?.disposition == .cancelled)
    #expect(await runtime.perform(.init(message: "Subsequent")) == .cancelled)
    #expect(await announcer.messages.count == 3)
    await runtime.setOutputEnabled(true)
    #expect(await runtime.start(first) == .refused("The advisory speech request identity has already been used."))
    await runtime.shutdown()
  }

  @Test("latest off wins during a held drain; enabling later admits only a new request")
  func latestToggleWins() async throws {
    let announcer = DrainControlledSpeechAnnouncer(holdDrain: true)
    let runtime = PlotterSpeechEffectRuntime(announcer: announcer, outputEnabled: true)
    let old = PlotterSpeechEffectRequest(message: "Old cue")
    #expect(await runtime.start(old) == .admitted(old))
    try await speechEventually { await announcer.pendingCount == 1 }
    let firstOff = Task { await runtime.setOutputEnabled(false) }
    try await speechEventually { await announcer.cancelCount == 1 }
    let intermediateOn = Task { await runtime.setOutputEnabled(true) }
    try await speechEventually { await runtime.snapshot().outputEnabled }
    #expect(await runtime.start(.init(message: "During drain")) == .cancelled)
    let finalOff = Task { await runtime.setOutputEnabled(false) }
    try await speechEventually { await runtime.snapshot().outputEnabled == false }
    await announcer.releaseDrain()
    await firstOff.value; await intermediateOn.value; await finalOff.value
    #expect(await runtime.start(.init(message: "Still muted")) == .cancelled)
    #expect(await runtime.snapshot().terminalRequests == [.init(request: old, disposition: .cancelled)])
    await runtime.setOutputEnabled(true)
    let fresh = PlotterSpeechEffectRequest(message: "New cue")
    #expect(await runtime.start(fresh) == .admitted(fresh))
    try await speechEventually { await announcer.pendingCount == 1 }
    #expect(await announcer.messages == ["Old cue", "New cue"])
    await announcer.finishAll(.completed)
    try await speechEventually { await runtime.snapshot().activeRequests.isEmpty }
    #expect(await runtime.snapshot().terminalRequests.last?.disposition == .completed)
    await runtime.shutdown()
  }

  @Test("clearing input priority joins its old drain without cancelling a later cue")
  func priorityTransitionDrainsOnce() async throws {
    let announcer = DrainControlledSpeechAnnouncer(holdDrain: true)
    let runtime = PlotterSpeechEffectRuntime(announcer: announcer, outputEnabled: true)
    let old = PlotterSpeechEffectRequest(message: "Motion cue")
    _ = await runtime.start(old)
    try await speechEventually { await announcer.pendingCount == 1 }
    let suppress = Task { await runtime.prioritizeOperatorInput(true) }
    try await speechEventually { await announcer.cancelCount == 1 }
    let resume = Task { await runtime.prioritizeOperatorInput(false) }
    await announcer.releaseDrain()
    await suppress.value; await resume.value
    let fresh = PlotterSpeechEffectRequest(message: "Settled question")
    #expect(await runtime.start(fresh) == .admitted(fresh))
    try await speechEventually { await announcer.pendingCount == 1 }
    #expect(await announcer.cancelCount == 1)
    await announcer.finishAll(.completed)
    try await speechEventually { await runtime.snapshot().activeRequests.isEmpty }
    #expect(await runtime.snapshot().terminalRequests.last?.disposition == .completed)
    await runtime.shutdown()
  }


  @Test("an admitted effect delayed before Native cannot speak after the lower bulk clear")
  func effectDelayedBeforeNative() async throws {
    let native = NativeSpeechAnnouncer(queueFactory: { generation in
      SpeechSynthesisQueue(voiceLanguage: nil, timeoutNanoseconds: 60_000_000_000,
        generation: generation, synthesizer: nil)
    })
    let lower = DelayedNativeEntryAnnouncer(native: native)
    let runtime = PlotterSpeechEffectRuntime(announcer: lower, outputEnabled: true)
    let request = PlotterSpeechEffectRequest(message: "Admitted before off, Native entered afterward")
    #expect(await runtime.start(request) == .admitted(request))
    try await speechEventually { await lower.isWaiting }
    await runtime.setOutputEnabled(false)
    #expect(await lower.result == .cancelled)
    #expect(await runtime.snapshot().activeRequests.isEmpty)
    #expect(await runtime.snapshot().terminalRequests == [.init(request: request, disposition: .cancelled)])
    await runtime.shutdown()
  }

}

private actor ScriptedSpeechAnnouncer: SpeechAnnouncing {
  private var outcomes: [SpeechAnnouncementOutcome]

  init(outcomes: [SpeechAnnouncementOutcome]) {
    self.outcomes = outcomes
  }

  func announce(_: String) async -> SpeechAnnouncementOutcome {
    outcomes.isEmpty ? .completed : outcomes.removeFirst()
  }

  func cancelPendingAnnouncements() async {}
  func cancelForShutdown() async {}
}

private actor BlockingSpeechAnnouncer: SpeechAnnouncing {
  private var hasStarted = false
  private var startWaiters: [CheckedContinuation<Void, Never>] = []
  private var cancellation: CheckedContinuation<SpeechAnnouncementOutcome, Never>?
  private(set) var messages: [String] = []

  func announce(_ text: String) async -> SpeechAnnouncementOutcome {
    guard !Task.isCancelled, SpeechAnnouncementExecutionContext.admissionToken?.isValid != false else { return .cancelled }
    messages.append(text)
    hasStarted = true
    let waiters = startWaiters
    startWaiters = []
    waiters.forEach { $0.resume() }
    return await withCheckedContinuation { cancellation = $0 }
  }

  func cancelPendingAnnouncements() async {
    cancellation?.resume(returning: .cancelled)
    cancellation = nil
  }

  func cancelForShutdown() async { await cancelPendingAnnouncements() }

  func waitUntilStarted() async {
    guard !hasStarted else { return }
    await withCheckedContinuation { startWaiters.append($0) }
  }
}


private enum SpeechFixtureFailure: Error { case timeout }

private func speechEventually(_ condition: () async -> Bool) async throws {
  let deadline = ContinuousClock.now.advanced(by: .seconds(3))
  while !(await condition()), ContinuousClock.now < deadline { await Task.yield() }
  guard await condition() else { throw SpeechFixtureFailure.timeout }
}

/// Deliberately completes cancelled lower work as completed: the effect owner
/// must still publish cancelled for identities retired by the Voice transition.
private actor DrainControlledSpeechAnnouncer: SpeechAnnouncing {
  private var pending: [UUID: CheckedContinuation<SpeechAnnouncementOutcome, Never>] = [:]
  private var holdDrain: Bool
  private var drainWaiter: CheckedContinuation<Void, Never>?
  private(set) var cancelCount = 0
  private(set) var messages: [String] = []
  var pendingCount: Int { pending.count }
  init(holdDrain: Bool = false) { self.holdDrain = holdDrain }
  func announce(_ message: String) async -> SpeechAnnouncementOutcome {
    guard !Task.isCancelled, SpeechAnnouncementExecutionContext.admissionToken?.isValid != false else { return .cancelled }
    messages.append(message)
    return await withCheckedContinuation { pending[UUID()] = $0 }
  }
  func cancelPendingAnnouncements() async {
    cancelCount += 1
    if holdDrain { await withCheckedContinuation { drainWaiter = $0 } }
    finishAll(.completed)
  }
  func releaseDrain() { holdDrain = false; drainWaiter?.resume(); drainWaiter = nil }
  func finishAll(_ outcome: SpeechAnnouncementOutcome) {
    let continuations = Array(pending.values); pending.removeAll()
    for continuation in continuations { continuation.resume(returning: outcome) }
  }
  func cancelForShutdown() async { releaseDrain(); finishAll(.cancelled) }
}


private actor DelayedNativeEntryAnnouncer: SpeechAnnouncing {
  let native: NativeSpeechAnnouncer
  private var entry: CheckedContinuation<Void, Never>?
  private(set) var result: SpeechAnnouncementOutcome?
  var isWaiting: Bool { entry != nil }
  init(native: NativeSpeechAnnouncer) { self.native = native }
  func announce(_ message: String) async -> SpeechAnnouncementOutcome {
    await withCheckedContinuation { entry = $0 }
    let outcome = await native.announce(message)
    result = outcome
    return outcome
  }
  func cancelPendingAnnouncements() async {
    await native.cancelPendingAnnouncements()
    entry?.resume(); entry = nil
  }
  func cancelForShutdown() async {
    await native.cancelForShutdown()
    entry?.resume(); entry = nil
  }
}
