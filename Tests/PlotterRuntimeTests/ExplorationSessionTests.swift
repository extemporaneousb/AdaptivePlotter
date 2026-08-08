import Foundation
import Testing

@testable import PlotterRuntime

@Suite("Persistent ExplorationSession")
struct ExplorationSessionTests {
  @Test("one microphone lifetime survives multiple episode contexts")
  func microphoneLifetimeSurvivesEpisodes() async throws {
    let driver = ExplorationVoiceDriverFixture()
    let output = ExplorationSpeechOutputFixture()
    let session = ExplorationSession(driver: driver, speechOutput: output)
    let sessionID = ExplorationSessionID(UUID())

    let started = await session.start(input: .microphone, id: sessionID)
    #expect(started.state == .listening)
    #expect(started.id == sessionID)

    let preflight = context(
      rung: .motionPreflight,
      allowedIntents: [.ready, .stop],
      stopIsCancellable: true
    )
    try await session.activateEpisode(preflight)
    _ = try await session.completeEpisode(preflight.episodeID, termination: .completed)

    let armature = context(
      rung: .armatureGuidance,
      allowedIntents: [.keepGoing, .accept],
      teachingKinds: [.visibility]
    )
    try await session.activateEpisode(armature)

    #expect(await driver.startCount == 1)
    #expect(await driver.stopCount == 0)
    #expect((await session.snapshot()).activeEpisode == armature)

    await session.end()
    #expect((await session.snapshot()).state == .inactive)
    #expect(await driver.stopCount == 1)
  }

  @Test("microphone transcripts are subscribed and routed by the session")
  func microphoneTranscriptSubscription() async throws {
    let driver = ExplorationVoiceDriverFixture()
    let session = ExplorationSession(
      driver: driver,
      speechOutput: ExplorationSpeechOutputFixture()
    )
    _ = await session.start(input: .microphone)
    let episode = context(rung: .armatureGuidance, allowedIntents: [.accept])
    try await session.activateEpisode(episode)

    let transcript = makeTranscript("accept", isFinal: true, time: 10)
    await driver.emit(transcript)
    for _ in 0..<100 {
      if case .acceptedIntent(let receipt)? = (await session.snapshot()).latestRoutingResult {
        #expect(receipt.intent == .accept)
        #expect(receipt.transcript.utteranceID == transcript.utteranceID)
        return
      }
      await Task.yield()
    }
    Issue.record("session did not consume the driver transcript")
  }

  @Test("injected mode is permission free and still uses contextual routing")
  func injectedModeDoesNotTouchDriver() async throws {
    let driver = ExplorationVoiceDriverFixture()
    let session = ExplorationSession(
      driver: driver,
      speechOutput: ExplorationSpeechOutputFixture()
    )
    let snapshot = await session.start(input: .injected)
    #expect(snapshot.state == .listening)
    #expect(snapshot.voice == nil)
    #expect(await driver.authorizationRequestCount == 0)
    #expect(await driver.startCount == 0)
    #expect(await driver.transcriptStreamCount == 0)

    let episode = context(rung: .motionPreflight, allowedIntents: [.ready])
    try await session.activateEpisode(episode)
    let result = await session.ingest(makeTranscript("ready", isFinal: true, time: 1))
    guard case .acceptedIntent(let receipt) = result else {
      Issue.record("expected injected READY to route through the session")
      return
    }
    #expect(receipt.context.source == .simulated)
    #expect(receipt.intent == .ready)
  }

  @Test("every operator hypothesis barges in before contextual rejection")
  func operatorSpeechBargesIn() async throws {
    let output = ExplorationSpeechOutputFixture()
    let session = ExplorationSession(
      driver: ExplorationVoiceDriverFixture(),
      speechOutput: output
    )
    _ = await session.start(input: .injected)
    try await session.activateEpisode(
      context(rung: .isolatedInk, allowedIntents: [.accept])
    )
    _ = await session.speakFeedback("Line observed")

    let result = await session.ingest(
      makeTranscript("controller status", isFinal: true, time: 100)
    )
    #expect(result == .rejected(.outOfContext))
    #expect(await output.messages == ["Line observed"])
    #expect(await output.stopCount == 1)
  }

  @Test("stable partial STOP emits once for one utterance")
  func stablePartialStopIsDeduplicated() async throws {
    let output = ExplorationSpeechOutputFixture()
    let session = ExplorationSession(
      driver: ExplorationVoiceDriverFixture(),
      speechOutput: output,
      clock: FixedExplorationClock(now: 5)
    )
    _ = await session.start(input: .injected)
    try await session.activateEpisode(
      context(
        rung: .motionPreflight,
        allowedIntents: [.stop],
        stopIsCancellable: true
      )
    )

    let utteranceID = UUID()
    let partial = makeTranscript(
      "STOP!",
      utteranceID: utteranceID,
      isFinal: false,
      time: 20
    )
    #expect(partial.stability == .stablePartial)
    let first = await session.ingest(partial)
    guard case .acceptedIntent(let receipt) = first else {
      Issue.record("stable partial STOP should be accepted")
      return
    }
    #expect(receipt.intent == .stop)
    #expect(receipt.timing.hypothesisNanoseconds == 20)
    #expect(receipt.timing.acceptedNanoseconds > receipt.timing.hypothesisNanoseconds)

    let final = makeTranscript(
      "stop",
      utteranceID: utteranceID,
      sequence: 2,
      isFinal: true,
      time: 21
    )
    #expect(await session.ingest(final) == .rejected(.duplicateUtterance))
    #expect(await output.stopCount == 2)
  }

  @Test("STOP and motion-like words are inert outside their declared context")
  func contextualIntentRejection() async throws {
    let session = ExplorationSession(
      driver: ExplorationVoiceDriverFixture(),
      speechOutput: ExplorationSpeechOutputFixture()
    )
    _ = await session.start(input: .injected)
    try await session.activateEpisode(
      context(rung: .isolatedInk, allowedIntents: [.accept])
    )

    for phrase in ["stop", "continue", "keep going", "reverse", "x+", "x-", "y+", "y-"] {
      let result = await session.ingest(makeTranscript(phrase, isFinal: true, time: 1))
      #expect(result == .rejected(.outOfContext))
    }
    #expect(
      await session.ingest(makeTranscript("$J=G91 X5", isFinal: true, time: 1))
        == .rejected(.outOfContext)
    )
  }

  @Test("non-cancellation intents require a final or explicitly stable hypothesis")
  func finalOrStableIntentRequirement() async throws {
    let session = ExplorationSession(
      driver: ExplorationVoiceDriverFixture(),
      speechOutput: ExplorationSpeechOutputFixture()
    )
    _ = await session.start(input: .injected)
    try await session.activateEpisode(
      context(rung: .armatureGuidance, allowedIntents: [.keepGoing])
    )

    #expect(
      await session.ingest(makeTranscript("keep going", isFinal: false, time: 10))
        == .rejected(.unstableHypothesis)
    )
    let stable = makeTranscript(
      "keep going",
      isFinal: false,
      stability: .stablePartial,
      time: 11
    )
    guard case .acceptedIntent(let receipt) = await session.ingest(stable) else {
      Issue.record("explicit stable contextual intent should be accepted")
      return
    }
    #expect(receipt.intent == .keepGoing)
  }

  @Test("all declared reflex intents stay typed and exact")
  func declaredReflexGrammar() async throws {
    let expected: [(String, ExplorationVoiceIntent)] = [
      ("continue", .continueAction),
      ("keep going", .keepGoing),
      ("reverse", .reverse),
      ("x+", .xPositive),
      ("x minus", .xNegative),
      ("positive y", .yPositive),
      ("y-", .yNegative),
      ("accept this pose", .accept),
      ("again", .again),
      ("skip", .skip),
      ("end exploration", .endSession),
    ]
    let session = ExplorationSession(
      driver: ExplorationVoiceDriverFixture(),
      speechOutput: ExplorationSpeechOutputFixture()
    )
    _ = await session.start(input: .injected)
    try await session.activateEpisode(
      context(
        rung: .armatureGuidance,
        allowedIntents: Set(expected.map(\.1))
      )
    )

    for (index, pair) in expected.enumerated() {
      let result = await session.ingest(
        makeTranscript(pair.0, sequence: UInt64(index + 1), isFinal: true, time: UInt64(index))
      )
      guard case .acceptedIntent(let receipt) = result else {
        Issue.record("expected typed intent for \(pair.0)")
        continue
      }
      #expect(receipt.intent == pair.1)
    }
  }

  @Test("teaching labels remain separate from controller intents")
  func flexibleTeachingLabels() async throws {
    let session = ExplorationSession(
      driver: ExplorationVoiceDriverFixture(),
      speechOutput: ExplorationSpeechOutputFixture()
    )
    _ = await session.start(input: .injected)
    try await session.activateEpisode(
      context(
        rung: .strokeShapePreference,
        allowedIntents: [],
        teachingKinds: [.visibility, .shapeFeature, .ranking, .reward]
      )
    )

    let examples: [(String, ExplorationTeachingLabelKind)] = [
      ("I can see the last mark clearly now", .visibility),
      ("The left side is partially blocked by the holder", .visibility),
      ("B is too wide and rough", .shapeFeature),
      ("C is best over B", .ranking),
      ("That was good reward 0.8", .reward),
    ]

    for (index, example) in examples.enumerated() {
      let result = await session.ingest(
        makeTranscript(
          example.0,
          sequence: UInt64(index + 1),
          isFinal: true,
          time: UInt64(index + 1)
        )
      )
      guard case .acceptedTeachingLabel(let receipt) = result else {
        Issue.record("expected teaching label for \(example.0)")
        continue
      }
      #expect(kind(of: receipt.label.classification) == example.1)
    }
  }

  @Test("acceptance and feedback times remain monotonic across backward input clocks")
  func monotonicInteractionTiming() async throws {
    let session = ExplorationSession(
      driver: ExplorationVoiceDriverFixture(),
      speechOutput: ExplorationSpeechOutputFixture(),
      clock: FixedExplorationClock(now: 10)
    )
    _ = await session.start(input: .injected)
    try await session.activateEpisode(
      context(rung: .isolatedInk, allowedIntents: [.accept, .again])
    )

    guard case .acceptedIntent(let first) = await session.ingest(
      makeTranscript("accept", isFinal: true, time: 100)
    ) else {
      Issue.record("expected first intent")
      return
    }
    let feedback = try #require(await session.speakFeedback("Assessment recorded"))
    guard case .acceptedIntent(let second) = await session.ingest(
      makeTranscript("again", isFinal: true, time: 1)
    ) else {
      Issue.record("expected second intent")
      return
    }

    #expect(first.timing.hypothesisNanoseconds < first.timing.acceptedNanoseconds)
    #expect(first.timing.acceptedNanoseconds < feedback.onsetNanoseconds)
    #expect(feedback.onsetNanoseconds < second.timing.hypothesisNanoseconds)
    #expect(second.timing.hypothesisNanoseconds < second.timing.acceptedNanoseconds)
  }

  @Test("ending during stale start completion cannot revive listening")
  func generationSafeStartTeardown() async {
    let driver = ExplorationVoiceDriverFixture(blockStart: true)
    let output = ExplorationSpeechOutputFixture()
    let session = ExplorationSession(driver: driver, speechOutput: output)
    let startTask = Task { await session.start(input: .microphone) }

    for _ in 0..<100 {
      if await driver.startCount > 0 { break }
      await Task.yield()
    }
    #expect(await driver.startCount == 1)

    await session.end()
    #expect((await session.snapshot()).state == .inactive)
    await driver.resumeBlockedStart()
    _ = await startTask.value

    #expect((await session.snapshot()).state == .inactive)
    #expect((await driver.snapshot()).listeningState == .stopped)
    #expect(await driver.stopCount >= 2)
  }

  @Test("teardown cancels the listener and ignores later driver transcripts")
  func teardownIgnoresLateTranscript() async throws {
    let driver = ExplorationVoiceDriverFixture()
    let session = ExplorationSession(
      driver: driver,
      speechOutput: ExplorationSpeechOutputFixture()
    )
    _ = await session.start(input: .microphone)
    try await session.activateEpisode(
      context(rung: .isolatedInk, allowedIntents: [.accept])
    )
    await session.end()
    await driver.emit(makeTranscript("accept", isFinal: true, time: 100))
    for _ in 0..<10 { await Task.yield() }

    let snapshot = await session.snapshot()
    #expect(snapshot.state == .inactive)
    #expect(snapshot.latestTranscript == nil)
    #expect(snapshot.activeEpisode == nil)
  }

  @Test("episode record preserves one preassigned split and attributable speech timing")
  func episodeRecordCarriesAttribution() throws {
    let sessionID = ExplorationSessionID(UUID())
    let episodeID = ExplorationEpisodeID(UUID())
    var episode = ExplorationEpisode(
      sessionID: sessionID,
      id: episodeID,
      rung: .isolatedInk,
      source: .live,
      split: .reserved,
      startedNanoseconds: 1
    )
    episode.speech.append(
      ExplorationSpeechRecord(
        utteranceID: UUID(),
        transcriptSequence: 1,
        transcript: "accept",
        stability: .final,
        hypothesisNanoseconds: 2,
        acceptedNanoseconds: 3,
        feedbackNanoseconds: 4,
        acceptance: .intent(.accept)
      )
    )
    episode.termination = .completed

    #expect(episode.sessionID == sessionID)
    #expect(episode.id == episodeID)
    #expect(episode.split == .reserved)
    #expect(episode.speech.single?.hypothesisNanoseconds == 2)
    #expect(episode.speech.single?.feedbackNanoseconds == 4)
    #expect(episode.termination == .completed)
  }

  private func context(
    rung: ExplorationLearningRung,
    allowedIntents: Set<ExplorationVoiceIntent>,
    teachingKinds: Set<ExplorationTeachingLabelKind> = [],
    stopIsCancellable: Bool = false
  ) -> ExplorationEpisodeVoiceContext {
    ExplorationEpisodeVoiceContext(
      episodeID: ExplorationEpisodeID(UUID()),
      rung: rung,
      source: .simulated,
      allowedIntents: allowedIntents,
      teachingLabelKinds: teachingKinds,
      stopIsCancellable: stopIsCancellable
    )
  }

  private func makeTranscript(
    _ text: String,
    utteranceID: UUID = UUID(),
    sequence: UInt64 = 1,
    isFinal: Bool,
    stability: VoiceHypothesisStability? = nil,
    time: UInt64
  ) -> VoiceTranscript {
    VoiceTranscript(
      utteranceID: utteranceID,
      sequence: sequence,
      text: text,
      isFinal: isFinal,
      stability: stability,
      monotonicNanoseconds: time
    )
  }

  private func kind(
    of classification: ExplorationTeachingLabelClassification
  ) -> ExplorationTeachingLabelKind {
    switch classification {
    case .visibility: .visibility
    case .shapeFeature: .shapeFeature
    case .ranking: .ranking
    case .reward: .reward
    }
  }
}

private actor ExplorationVoiceDriverFixture: VoiceInteractionDriving {
  private let buffer = VoiceTranscriptBuffer()
  private let blockStart: Bool
  private var blockedStartContinuation: CheckedContinuation<Void, Never>?
  private(set) var authorizationRequestCount = 0
  private(set) var startCount = 0
  private(set) var stopCount = 0
  private(set) var transcriptStreamCount = 0
  private var state: VoiceListeningState = .stopped

  init(blockStart: Bool = false) {
    self.blockStart = blockStart
  }

  func snapshot() -> VoiceInteractionSnapshot {
    VoiceInteractionSnapshot(
      authorization: .authorized,
      listeningState: state,
      recognitionPolicy: .onDeviceRequired,
      latestTranscript: nil
    )
  }

  func requestAuthorization() -> VoiceAuthorizationState {
    authorizationRequestCount += 1
    return .authorized
  }

  func startListening() async {
    startCount += 1
    if blockStart {
      await withCheckedContinuation { continuation in
        blockedStartContinuation = continuation
      }
    }
    // Deliberately emulate a stale callback that claims listening even if stop
    // ran while the start continuation was suspended.
    state = .listening
  }

  func stopListening() {
    stopCount += 1
    state = .stopped
  }

  func transcripts() async -> AsyncStream<VoiceTranscript> {
    transcriptStreamCount += 1
    return await buffer.stream()
  }

  func emit(_ transcript: VoiceTranscript) async {
    await buffer.yield(transcript)
  }

  func resumeBlockedStart() {
    let continuation = blockedStartContinuation
    blockedStartContinuation = nil
    continuation?.resume()
  }
}

private actor ExplorationSpeechOutputFixture: VoiceSpeechOutput {
  private(set) var messages: [String] = []
  private(set) var stopCount = 0

  func speak(_ text: String) {
    messages.append(text)
  }

  func stopSpeaking() {
    stopCount += 1
  }
}

private struct FixedExplorationClock: RuntimeClock {
  let now: UInt64

  func nowNanoseconds() -> UInt64 { now }
  func sleep(nanoseconds: UInt64) async throws {}
}

private extension Array {
  var single: Element? { count == 1 ? self[0] : nil }
}
