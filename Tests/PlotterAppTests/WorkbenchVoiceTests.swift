import Foundation
import PlotterEpisodeModel
import PlotterEpisodeRuntime
import PlotterRuntime
import PlotterUI
import Testing
@testable import PlotterApp

@Suite("Contextual workbench voice", .serialized)
@MainActor
struct WorkbenchVoiceTests {
  @Test("responses resolve only to the exact offered action")
  func contextualResponses() {
    let context = voiceContext()
    #expect(context.matching("Yes, it is.")?.title == "YES")
    #expect(context.matching("No, not yet")?.title == "NO")
    #expect(context.matching("yes, actually no") == nil)
    #expect(context.matching("yes, don't do that") == nil)
    #expect(context.matching("I did not say yes") == nil)
    #expect(context.matching("yesterday") == nil)
    #expect(context.matching("go ahead and draw") == nil)
    #expect(voiceContext(disableYes: true).matching("yes") == nil)
    #expect(voiceContext(actions: [.start]).matching("yes") == nil)
    #expect(voiceContext(actions: [.start]).matching("please start")?.title == "Start")
  }

  @Test("speech completion opens input and a spoken answer uses its captured projection")
  func responseUsesCapturedRequest() async throws {
    let speech = PlotterSpeechEffectRuntime(announcer: ImmediateVoiceAnnouncer())
    let listener = TestVoiceListener()
    var requests: [PlotterUIRequest] = []
    let controller = WorkbenchVoiceController(speech: speech, listener: listener) { request in
      requests.append(request)
      return .accepted(requestID: request.id)
    }
    let context = voiceContext(revision: 42)
    controller.update(context)
    controller.setEnabled(true)
    try await eventually { controller.isListening }
    listener.send(.transcript("yes it is", isFinal: true))
    try await eventually { requests.count == 1 }
    #expect(requests[0].uiRevision == context.projection.revision)
    #expect(requests[0].runtimeRevisions == context.projection.runtimeRevisions)
    #expect(requests[0].intent == context.matching("yes")?.intent)
    controller.stop()
    await speech.shutdown()
  }

  @Test("context replacement and Voice off release input and discard old callbacks")
  func oldInputCannotAnswerANewQuestion() async throws {
    let speech = PlotterSpeechEffectRuntime(announcer: ImmediateVoiceAnnouncer())
    let listener = TestVoiceListener()
    var requests: [PlotterUIRequest] = []
    let controller = WorkbenchVoiceController(speech: speech, listener: listener) { request in
      requests.append(request)
      return .accepted(requestID: request.id)
    }
    controller.update(voiceContext(revision: 1))
    controller.setEnabled(true)
    try await eventually { controller.isListening }
    let obsolete = listener.continuation
    controller.update(voiceContext(revision: 2))
    try await eventually { controller.isListening && listener.startCount == 2 }
    obsolete?.yield(.transcript("yes", isFinal: true))
    for _ in 0..<10 { await Task.yield() }
    #expect(requests.isEmpty)
    let latest = listener.continuation
    controller.stop()
    latest?.yield(.transcript("yes", isFinal: true))
    for _ in 0..<10 { await Task.yield() }
    #expect(requests.isEmpty)
    #expect(!controller.isListening)
    #expect(listener.continuation == nil)
    await speech.shutdown()
  }

  @Test("workflow speech suspends recognition and reopens it when playback settles")
  func halfDuplexPlayback() async throws {
    let announcer = HeldVoiceAnnouncer()
    let speech = PlotterSpeechEffectRuntime(announcer: announcer)
    let listener = TestVoiceListener()
    let controller = WorkbenchVoiceController(speech: speech, listener: listener) {
      .accepted(requestID: $0.id)
    }
    controller.update(voiceContext())
    controller.setEnabled(true)
    try await eventually { controller.status == "Speaking…" }
    #expect(!controller.isListening)
    await announcer.finish()
    try await eventually { controller.isListening }
    _ = await speech.start(.init(message: "Workflow cue"))
    try await eventually { !controller.isListening }
    await announcer.finish()
    try await eventually { controller.isListening }
    controller.stop()
    await speech.shutdown()
  }

  @Test("a partial reply endpoints without requiring Apple's final callback")
  func partialEndpoint() async throws {
    let speech = PlotterSpeechEffectRuntime(announcer: ImmediateVoiceAnnouncer())
    let listener = TestVoiceListener()
    var count = 0
    let controller = WorkbenchVoiceController(speech: speech, listener: listener) {
      count += 1
      return .accepted(requestID: $0.id)
    }
    controller.update(voiceContext())
    controller.setEnabled(true)
    try await eventually { controller.isListening }
    listener.send(.transcript("yes", isFinal: false))
    try await eventually { count == 1 }
    controller.stop()
    await speech.shutdown()
  }
}

@MainActor
private func voiceContext(
  revision: UInt64 = 1,
  actions: [PlotterLearningAction] = [.choice(.yes), .choice(.no)],
  disableYes: Bool = false
) -> WorkbenchVoiceContext {
  let decisions = actions.map {
    PlotterUILearningActionDecision(itemID: "pen", action: $0,
      unavailableReason: disableYes && $0 == .choice(.yes) ? "Busy" : nil)
  }
  let projection = PlotterUIProjection(
    revision: .init(rawValue: revision), runtimeRevisions: [.init(owner: "Pen", token: "\(revision)")],
    actions: decisions.map {
      .init(id: .init(learningRequest: $0.request), title: $0.title,
        intent: .learningAction($0.request), unavailableReason: $0.unavailableReason)
    }, learning: nil, incidentPackage: .unavailable(reason: "No archive"), diagnostics: [],
    visitedCandidateCount: decisions.count
  )
  return WorkbenchVoiceContext(
    presentation: OperatorActionPresentation(
      itemID: .humanGuidedDiscovery(.penInteraction), instructions: [.text("Is the pen up?")],
      actionStrip: .init(ownerID: "pen", actions: decisions,
        directionSelection: nil, penAdjustment: nil, mustRemainVisible: true)
    ), projection: projection
  )
}

@MainActor
private func eventually(_ condition: () -> Bool) async throws {
  let deadline = ContinuousClock.now.advanced(by: .seconds(3))
  while !condition(), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(5)) }
  #expect(condition())
  if !condition() { throw CancellationError() }
}

@MainActor
private final class TestVoiceListener: SpeechListening {
  var continuation: AsyncStream<SpeechInputEvent>.Continuation?
  var startCount = 0
  func start(contextualPhrases: [String]) async throws -> AsyncStream<SpeechInputEvent> {
    startCount += 1
    let (stream, continuation) = AsyncStream<SpeechInputEvent>.makeStream()
    self.continuation = continuation
    return stream
  }
  func send(_ event: SpeechInputEvent) { continuation?.yield(event) }
  func stop() { continuation?.finish(); continuation = nil }
}

private actor ImmediateVoiceAnnouncer: SpeechAnnouncing {
  func announce(_ text: String) async -> SpeechAnnouncementOutcome { .completed }
  func cancelForShutdown() async {}
}

private actor HeldVoiceAnnouncer: SpeechAnnouncing {
  private var continuation: CheckedContinuation<SpeechAnnouncementOutcome, Never>?
  func announce(_ text: String) async -> SpeechAnnouncementOutcome {
    await withCheckedContinuation { continuation = $0 }
  }
  func finish() { continuation?.resume(returning: .completed); continuation = nil }
  func cancelForShutdown() async { finish() }
}
