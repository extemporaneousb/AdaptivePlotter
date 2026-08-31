import Foundation
import PlotterEpisodeRuntime
import PlotterRuntime
import Testing

@Suite("EA-10G advisory speech effect lane")
struct PlotterSpeechEffectEpisodeTests {
  @Test("identity-bound terminal results retain completion and failure without physical authority")
  func terminalResultsAreBoundedAndTyped() async {
    let announcer = ScriptedSpeechAnnouncer(outcomes: [.completed, .failed("output unavailable")])
    let runtime = PlotterSpeechEffectRuntime(announcer: announcer)
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
    let runtime = PlotterSpeechEffectRuntime(announcer: announcer)
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
}

private actor ScriptedSpeechAnnouncer: SpeechAnnouncing {
  private var outcomes: [SpeechAnnouncementOutcome]

  init(outcomes: [SpeechAnnouncementOutcome]) {
    self.outcomes = outcomes
  }

  func announce(_: String) async -> SpeechAnnouncementOutcome {
    outcomes.isEmpty ? .completed : outcomes.removeFirst()
  }

  func cancelForShutdown() async {}
}

private actor BlockingSpeechAnnouncer: SpeechAnnouncing {
  private var hasStarted = false
  private var startWaiters: [CheckedContinuation<Void, Never>] = []
  private var cancellation: CheckedContinuation<SpeechAnnouncementOutcome, Never>?
  private(set) var messages: [String] = []

  func announce(_ text: String) async -> SpeechAnnouncementOutcome {
    messages.append(text)
    hasStarted = true
    let waiters = startWaiters
    startWaiters = []
    waiters.forEach { $0.resume() }
    return await withCheckedContinuation { cancellation = $0 }
  }

  func cancelForShutdown() async {
    cancellation?.resume(returning: .cancelled)
    cancellation = nil
  }

  func waitUntilStarted() async {
    guard !hasStarted else { return }
    await withCheckedContinuation { startWaiters.append($0) }
  }
}
