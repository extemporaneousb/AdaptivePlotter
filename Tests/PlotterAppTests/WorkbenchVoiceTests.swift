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
  @Test("short replies preserve the distinct offered meanings and reject ambiguity")
  func shortReplies() {
    let question = voiceContext(actions: [.choice(.yes), .choice(.no), .cancel])
    #expect(question.replies == ["Confirmed", "No", "Cancel"])
    #expect(question.matching("Confirmed")?.intent == question.matching("yes")?.intent)
    #expect(question.matching("Cancel")?.intent != question.matching("No")?.intent)
    #expect(question.matching("Confirmed, no") == nil)
    #expect(question.matching("don't start") == nil)
    let move = voiceContext(actions: [.boundary(.acquire(direction: .positiveY, mode: .normal))])
    #expect(move.replies == ["Start"])
    #expect(move.spokenPrompt == "Move Toward positive Y? Say Start.")
    #expect(move.matching("Start")?.intent == move.commands.first?.intent)
    #expect(move.matching("Confirmed") == nil)
    #expect(voiceContext(actions: [.choice(.yes)], disableYes: true).matching("Confirmed") == nil)
    let ambiguous = voiceContext(actions: [.start, .boundary(.acquire(direction: .positiveY, mode: .normal))])
    #expect(ambiguous.matching("Start") == nil)
    #expect(ambiguous.matching("please Start") == nil)
    #expect(ambiguous.replies == ["Move Toward Y+"])
    for reply in question.replies + move.replies {
      #expect(question.matching(reply) != nil || move.matching(reply) != nil)
    }
    for action: PlotterLearningAction in [.cameraCalibration(.acceptProposal),
      .tipCalibration(.acceptProposal), .borderValidation(.acceptObservedPrediction)] {
      #expect(voiceContext(actions: [action]).matching("Confirmed") != nil)
    }
    #expect(voiceContext(actions: [.boundary(.cancel(.init()))]).matching("Cancel") != nil)
  }

  @Test("a changed Boundary direction speaks its new short question even with unchanged instructions")
  func changedChoicesSpeakAgain() async throws {
    let announcer = ImmediateVoiceAnnouncer()
    let speech = PlotterSpeechEffectRuntime(announcer: announcer)
    let listener = TestVoiceListener()
    let controller = WorkbenchVoiceController(speech: speech, listener: listener) {
      .accepted(requestID: $0.id)
    }
    controller.update(voiceContext(actions: [.boundary(.acquire(direction: .positiveY, mode: .normal))]))
    controller.setEnabled(true)
    try await eventually { controller.isListening }
    controller.update(voiceContext(revision: 2,
      actions: [.boundary(.acquire(direction: .negativeY, mode: .normal))]))
    try await eventually { controller.isListening && listener.startCount == 2 }
    #expect(await announcer.messages == [
      "Move Toward positive Y? Say Start.", "Move Toward negative Y? Say Start."
    ])
    controller.stop()
    await speech.shutdown()
  }

  @Test("queued background and Stop callbacks use recognition time without cycling the microphone")
  func movingDoesNotEndpointBackgroundSpeech() async throws {
    let speech = PlotterSpeechEffectRuntime(announcer: ImmediateVoiceAnnouncer())
    let listener = TestVoiceListener()
    var count = 0
    let controller = WorkbenchVoiceController(speech: speech, listener: listener) {
      count += 1
      return .accepted(requestID: $0.id)
    }
    controller.update(voiceContext(actions: [.boundary(.stop(.init()))]))
    controller.setEnabled(true)
    try await eventually { controller.isListening }
    let starts = listener.startCount
    // Both callbacks are queued before the consumer gets another actor turn.
    // A UI timer cannot establish the utterance boundary in this case.
    let captured = ContinuousClock.now - .seconds(2)
    listener.send(.transcript("background conversation", isFinal: false, observedAt: captured))
    listener.send(.transcript("background conversation Stop", isFinal: false,
      observedAt: captured + .seconds(1)))
    try await eventually { count == 1 }
    // The only restart is after cancellation returns, never before submission.
    #expect(listener.startCount <= starts + 1)
    controller.stop()
    await speech.shutdown()
  }

  @Test("Stop enters its sink before audio teardown, including a final and ended callback")
  func stopPrecedesAudioTeardown() async throws {
    let speech = PlotterSpeechEffectRuntime(announcer: ImmediateVoiceAnnouncer())
    let listener = TestVoiceListener()
    var stopsAtSubmission: Int?
    var release: CheckedContinuation<Void, Never>?
    var count = 0
    let controller = WorkbenchVoiceController(speech: speech, listener: listener) {
      count += 1
      stopsAtSubmission = listener.stopCount
      await withCheckedContinuation { release = $0 }
      return .accepted(requestID: $0.id)
    }
    controller.update(voiceContext(actions: [.boundary(.stop(.init()))]))
    controller.setEnabled(true)
    try await eventually { controller.isListening }
    let before = listener.stopCount
    listener.send(.transcript("Stop", isFinal: true))
    listener.send(.failed("Service failed alongside its last result"))
    listener.send(.ended)
    let deadline = ContinuousClock.now.advanced(by: .milliseconds(300))
    while release == nil, ContinuousClock.now < deadline { await Task.yield() }
    #expect(count == 1)
    #expect(stopsAtSubmission == before)
    listener.send(.transcript("Stop", isFinal: true))
    for _ in 0..<10 { await Task.yield() }
    #expect(count == 1)
    release?.resume()
    controller.stop()
    await speech.shutdown()
  }

  @Test("Start keeps input open and cumulative Stop interrupts its suspended submission")
  func startToStopWithoutMicrophoneGap() async throws {
    let speech = PlotterSpeechEffectRuntime(announcer: ImmediateVoiceAnnouncer())
    let listener = TestVoiceListener()
    var requests: [PlotterUIRequest] = []
    var releaseStart: CheckedContinuation<Void, Never>?
    let controller = WorkbenchVoiceController(speech: speech, listener: listener) {
      requests.append($0)
      if requests.count == 1 {
        // The real Boundary owner emits its advisory movement cue on admission.
        _ = await speech.start(.init(message: "Moving toward the drawing boundary."))
        await withCheckedContinuation { releaseStart = $0 }
      }
      return .accepted(requestID: $0.id)
    }
    controller.update(voiceContext(actions: [.boundary(.acquire(direction: .positiveY, mode: .normal))]))
    controller.setEnabled(true)
    try await eventually { controller.isListening }
    let starts = listener.startCount
    listener.send(.transcript("Start", isFinal: false))
    try await eventually { releaseStart != nil }
    let current = voiceContext(revision: 2, actions: [.boundary(.stop(.init()))])
    controller.update(current)
    #expect(controller.isListening)
    #expect(listener.startCount == starts)
    listener.send(.transcript("Start Stop", isFinal: false))
    let deadline = ContinuousClock.now.advanced(by: .milliseconds(300))
    while requests.count < 2, ContinuousClock.now < deadline { await Task.yield() }
    #expect(requests.count == 2)
    #expect(requests.last?.intent == current.matchingStop("Stop")?.intent)
    #expect(requests.last?.uiRevision == current.projection.revision)
    controller.update(voiceContext(revision: 3))
    releaseStart?.resume()
    try await eventually { controller.isListening }
    listener.send(.transcript("Confirmed", isFinal: true))
    try await eventually { requests.count == 3 }
    #expect(requests.last?.uiRevision.rawValue == 3)
    controller.stop()
    await speech.shutdown()
  }

  @Test("each boundary leg gives Stop priority over advisory playback")
  func stopWorksOnBothLegsDuringCues() async throws {
    let announcer = HeldVoiceAnnouncer()
    let speech = PlotterSpeechEffectRuntime(announcer: announcer)
    let listener = TestVoiceListener()
    var requests: [PlotterUIRequest] = []
    let controller = WorkbenchVoiceController(speech: speech, listener: listener) {
      requests.append($0)
      return .accepted(requestID: $0.id)
    }
    controller.setEnabled(true)
    for revision: UInt64 in [1, 2] {
      controller.update(voiceContext(revision: revision,
        actions: [.boundary(.acquire(direction: revision == 1 ? .positiveY : .negativeY, mode: .normal))]))
      try await eventually { controller.status == "Speaking…" || controller.isListening }
      if !controller.isListening {
        try await eventually { await announcer.pendingCount > 0 }
        await announcer.finish()
      }
      try await eventually { controller.isListening }
      _ = await speech.start(.init(message: "Moving to the next boundary; say Stop."))
      let stop = PlotterLearningAction.boundary(.stop(.init()))
      controller.update(voiceContext(revision: revision + 10, actions: [stop]))
      try await eventually { controller.isListening }
      let count = listener.startCount
      // A refreshed operation capability must not tear down recognition.
      let latest = voiceContext(revision: revision + 20, actions: [.boundary(.stop(.init()))])
      controller.update(latest)
      #expect(listener.startCount == count)
      listener.send(.transcript("stop", isFinal: false))
      try await eventually { requests.count == Int(revision) }
      #expect(requests.last?.uiRevision == latest.projection.revision)
      #expect(requests.last?.intent == latest.matchingStop("stop")?.intent)
    }
    controller.stop()
    await speech.shutdown()
  }

  @Test("recognition stream failure reconnects while Stop remains offered")
  func recognitionReconnects() async throws {
    let speech = PlotterSpeechEffectRuntime(announcer: ImmediateVoiceAnnouncer())
    let listener = TestVoiceListener()
    var count = 0
    let controller = WorkbenchVoiceController(speech: speech, listener: listener) {
      count += 1
      return .accepted(requestID: $0.id)
    }
    controller.update(voiceContext(actions: [.boundary(.stop(.init()))]))
    controller.setEnabled(true)
    try await eventually { controller.isListening }
    listener.send(.failed("Speech service ended the session"))
    try await eventually { controller.isListening && listener.startCount == 2 }
    listener.send(.transcript("stop", isFinal: false))
    try await eventually { count == 1 }
    controller.stop()
    await speech.shutdown()
  }

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

  @Test("Boundary movement accepts conversational and speech-recognizer variants")
  func naturalMovement() {
    let context = voiceContext(actions: [.boundary(.acquire(direction: .positiveY, mode: .normal))])
    for phrase in ["move", "go ahead", "move towards Y plus", "move toward why plus",
                   "please move in positive y", "can you move", "go to the boundary", "move y+"] {
      #expect(context.matching(phrase) != nil, "Unrecognized: \(phrase)")
    }
    for phrase in ["don't move", "move y minus", "move x plus", "move x and y"] {
      #expect(context.matching(phrase) == nil)
    }
    #expect(voiceContext().matching("it doesn't look right")?.title == "NO")
    #expect(voiceContext().matching("it does")?.title == "YES")
  }

  @Test("an explicit Stop survives a negated explanation and polite variations")
  func stopCommandPrecedesExplanation() {
    let context = voiceContext(actions: [.boundary(.stop(.init()))])
    for phrase in ["stop", "stop, that's not right", "stop, don't move any further",
                   "please stop, it isn't right", "could you please stop", "would you stop"] {
      #expect(context.matchingStop(phrase) != nil, "Unrecognized Stop: \(phrase)")
    }
    for phrase in ["don't stop", "please don't stop", "can you not stop", "I did not say stop"] {
      #expect(context.matchingStop(phrase) == nil)
    }
  }

  @Test("revision-only updates keep listening and Stop dispatches a partial immediately")
  func immediateStopUsesLatestRevision() async throws {
    let speech = PlotterSpeechEffectRuntime(announcer: ImmediateVoiceAnnouncer())
    let listener = TestVoiceListener()
    var requests: [PlotterUIRequest] = []
    let controller = WorkbenchVoiceController(speech: speech, listener: listener) {
      requests.append($0)
      return .accepted(requestID: $0.id)
    }
    let action = PlotterLearningAction.boundary(.stop(.init()))
    controller.update(voiceContext(revision: 1, actions: [action]))
    controller.setEnabled(true)
    try await eventually { controller.isListening }
    controller.update(voiceContext(revision: 2, actions: [action]))
    #expect(listener.startCount == 1)
    listener.send(.transcript("stop, that is not right", isFinal: false))
    let deadline = ContinuousClock.now.advanced(by: .milliseconds(300))
    while requests.isEmpty, ContinuousClock.now < deadline { await Task.yield() }
    #expect(requests.count == 1)
    #expect(requests.first?.uiRevision.rawValue == 2)
    controller.stop()
    await speech.shutdown()
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
    controller.update(voiceContext(revision: 2, actions: [.choice(.no)]))
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
    try await eventually { await announcer.pendingCount > 0 }
    await announcer.finish()
    try await eventually { controller.isListening }
    _ = await speech.start(.init(message: "Workflow cue"))
    try await eventually { !controller.isListening }
    try await eventually { await announcer.pendingCount > 0 }
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
private func eventually(_ condition: () async -> Bool) async throws {
  let deadline = ContinuousClock.now.advanced(by: .seconds(3))
  while !(await condition()), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(5)) }
  let passed = await condition()
  #expect(passed)
  if !passed { throw CancellationError() }
}

@MainActor
final class TestVoiceListener: SpeechListening {
  var continuation: AsyncStream<SpeechInputEvent>.Continuation?
  var startCount = 0
  var stopCount = 0
  func start(contextualPhrases: [String]) async throws -> AsyncStream<SpeechInputEvent> {
    startCount += 1
    let (stream, continuation) = AsyncStream<SpeechInputEvent>.makeStream()
    self.continuation = continuation
    return stream
  }
  func send(_ event: SpeechInputEvent) { continuation?.yield(event) }
  func stop() { stopCount += 1; continuation?.finish(); continuation = nil }
}

private actor ImmediateVoiceAnnouncer: SpeechAnnouncing {
  private(set) var messages: [String] = []
  func announce(_ text: String) async -> SpeechAnnouncementOutcome {
    messages.append(text)
    return .completed
  }
  func cancelForShutdown() async {}
}

private actor HeldVoiceAnnouncer: SpeechAnnouncing {
  private var continuations: [UUID: CheckedContinuation<SpeechAnnouncementOutcome, Never>] = [:]
  var pendingCount: Int { continuations.count }
  func announce(_ text: String) async -> SpeechAnnouncementOutcome {
    let id = UUID()
    return await withTaskCancellationHandler {
      guard !Task.isCancelled else { return .cancelled }
      return await withCheckedContinuation { continuations[id] = $0 }
    } onCancel: {
      Task { await self.finish(id) }
    }
  }
  private func finish(_ id: UUID) { continuations.removeValue(forKey: id)?.resume(returning: .completed) }
  func finish() { for id in Array(continuations.keys) { finish(id) } }
  func cancelForShutdown() async { finish() }
}
