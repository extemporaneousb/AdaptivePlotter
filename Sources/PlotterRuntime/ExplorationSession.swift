import Foundation

public enum ExplorationSessionInput: String, Hashable, Sendable {
  /// Own the native microphone and on-device recognizer for this session.
  case microphone
  /// Accept deterministic injected transcripts without touching TCC or audio.
  case injected
}

public enum ExplorationVoiceIntent: String, CaseIterable, Hashable, Sendable {
  case ready
  case stop
  case continueAction
  case keepGoing
  case reverse
  case xPositive
  case xNegative
  case yPositive
  case yNegative
  case penIsPhysicallyUp
  case penIsPhysicallyDown
  case accept
  case again
  case skip
  case endSession
}

public enum ExplorationTeachingLabelKind: String, CaseIterable, Hashable, Sendable {
  case visibility
  case shapeFeature
  case ranking
  case reward
}

public enum ExplorationVisibilityLabel: String, Hashable, Sendable {
  case clear
  case partial
  case blocked
}

public enum ExplorationRewardSentiment: String, Hashable, Sendable {
  case positive
  case neutral
  case negative
}

public enum ExplorationTeachingLabelClassification: Hashable, Sendable {
  case visibility(ExplorationVisibilityLabel, explanation: String?)
  case shapeFeature(description: String, features: [String])
  case ranking(statement: String)
  case reward(sentiment: ExplorationRewardSentiment, value: Double?, explanation: String)
}

public struct ExplorationTeachingLabel: Hashable, Sendable {
  public let rawTranscript: String
  public let classification: ExplorationTeachingLabelClassification

  public init(
    rawTranscript: String,
    classification: ExplorationTeachingLabelClassification
  ) {
    self.rawTranscript = rawTranscript
    self.classification = classification
  }
}

public enum ExplorationSpeechAcceptance: Hashable, Sendable {
  case intent(ExplorationVoiceIntent)
  case teachingLabel(ExplorationTeachingLabelClassification)
}

public struct ExplorationEpisodeVoiceContext: Hashable, Sendable {
  public let episodeID: ExplorationEpisodeID
  public let rung: ExplorationLearningRung
  public let source: ExplorationSource
  public let allowedIntents: Set<ExplorationVoiceIntent>
  public let teachingLabelKinds: Set<ExplorationTeachingLabelKind>
  public let stopIsCancellable: Bool

  public init(
    episodeID: ExplorationEpisodeID,
    rung: ExplorationLearningRung,
    source: ExplorationSource,
    allowedIntents: Set<ExplorationVoiceIntent>,
    teachingLabelKinds: Set<ExplorationTeachingLabelKind> = [],
    stopIsCancellable: Bool = false
  ) {
    self.episodeID = episodeID
    self.rung = rung
    self.source = source
    self.allowedIntents = allowedIntents
    self.teachingLabelKinds = teachingLabelKinds
    self.stopIsCancellable = stopIsCancellable
  }
}

public struct ExplorationVoiceTiming: Hashable, Sendable {
  public let hypothesisNanoseconds: UInt64
  public let acceptedNanoseconds: UInt64

  public init(hypothesisNanoseconds: UInt64, acceptedNanoseconds: UInt64) {
    self.hypothesisNanoseconds = hypothesisNanoseconds
    self.acceptedNanoseconds = acceptedNanoseconds
  }
}

public struct AcceptedExplorationIntent: Hashable, Sendable {
  public let context: ExplorationEpisodeVoiceContext
  public let intent: ExplorationVoiceIntent
  public let transcript: VoiceTranscript
  public let timing: ExplorationVoiceTiming

  public init(
    context: ExplorationEpisodeVoiceContext,
    intent: ExplorationVoiceIntent,
    transcript: VoiceTranscript,
    timing: ExplorationVoiceTiming
  ) {
    self.context = context
    self.intent = intent
    self.transcript = transcript
    self.timing = timing
  }
}

public struct AcceptedExplorationTeachingLabel: Hashable, Sendable {
  public let context: ExplorationEpisodeVoiceContext
  public let label: ExplorationTeachingLabel
  public let transcript: VoiceTranscript
  public let timing: ExplorationVoiceTiming

  public init(
    context: ExplorationEpisodeVoiceContext,
    label: ExplorationTeachingLabel,
    transcript: VoiceTranscript,
    timing: ExplorationVoiceTiming
  ) {
    self.context = context
    self.label = label
    self.transcript = transcript
    self.timing = timing
  }
}

public enum ExplorationVoiceRejection: String, Hashable, Sendable {
  case sessionNotListening
  case noActiveEpisode
  case unstableHypothesis
  case duplicateUtterance
  case outOfContext
}

public enum ExplorationVoiceRoutingResult: Hashable, Sendable {
  case acceptedIntent(AcceptedExplorationIntent)
  case acceptedTeachingLabel(AcceptedExplorationTeachingLabel)
  case rejected(ExplorationVoiceRejection)
}

public enum ExplorationSessionFailure: Error, Hashable, Sendable {
  case voice(VoiceInteractionError)
  case listeningDidNotStart(VoiceListeningState)
}

public enum ExplorationSessionState: Hashable, Sendable {
  case inactive
  case starting
  case listening
  case ending
  case failed(ExplorationSessionFailure)
}

public struct ExplorationFeedbackReceipt: Hashable, Sendable {
  public let text: String
  public let onsetNanoseconds: UInt64

  public init(text: String, onsetNanoseconds: UInt64) {
    self.text = text
    self.onsetNanoseconds = onsetNanoseconds
  }
}

public struct ExplorationSessionSnapshot: Hashable, Sendable {
  public let id: ExplorationSessionID?
  public let input: ExplorationSessionInput?
  public let state: ExplorationSessionState
  public let voice: VoiceInteractionSnapshot?
  public let activeEpisode: ExplorationEpisodeVoiceContext?
  public let latestTranscript: VoiceTranscript?
  public let latestRoutingResult: ExplorationVoiceRoutingResult?
  public let latestFeedback: ExplorationFeedbackReceipt?

  public init(
    id: ExplorationSessionID?,
    input: ExplorationSessionInput?,
    state: ExplorationSessionState,
    voice: VoiceInteractionSnapshot?,
    activeEpisode: ExplorationEpisodeVoiceContext?,
    latestTranscript: VoiceTranscript?,
    latestRoutingResult: ExplorationVoiceRoutingResult?,
    latestFeedback: ExplorationFeedbackReceipt?
  ) {
    self.id = id
    self.input = input
    self.state = state
    self.voice = voice
    self.activeEpisode = activeEpisode
    self.latestTranscript = latestTranscript
    self.latestRoutingResult = latestRoutingResult
    self.latestFeedback = latestFeedback
  }
}

public enum ExplorationSessionEvent: Hashable, Sendable {
  case stateChanged(ExplorationSessionState)
  case episodeActivated(ExplorationEpisodeVoiceContext)
  case episodeCompleted(ExplorationEpisodeID, ExplorationEpisodeTermination)
  case routed(ExplorationVoiceRoutingResult)
  case feedback(ExplorationFeedbackReceipt)
}

public enum ExplorationSessionError: Error, Hashable, Sendable {
  case notListening
  case episodeAlreadyActive(ExplorationEpisodeID)
  case wrongEpisode(expected: ExplorationEpisodeID, actual: ExplorationEpisodeID)
}

public struct ExplorationVoiceIntentParser: Sendable {
  public init() {}

  public func parse(_ transcript: String) -> ExplorationVoiceIntent? {
    let compact = transcript
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .lowercased()
      .replacingOccurrences(of: "−", with: "-")
    switch compact {
    case "x+": return .xPositive
    case "x-": return .xNegative
    case "y+": return .yPositive
    case "y-": return .yNegative
    default: break
    }

    switch Self.normalized(transcript) {
    case "ready": return .ready
    case "stop": return .stop
    case "continue": return .continueAction
    case "keep going": return .keepGoing
    case "reverse": return .reverse
    case "x plus", "x positive", "positive x": return .xPositive
    case "x minus", "x negative", "negative x": return .xNegative
    case "y plus", "y positive", "positive y": return .yPositive
    case "y minus", "y negative", "negative y": return .yNegative
    case "pen is physically up": return .penIsPhysicallyUp
    case "pen is physically down": return .penIsPhysicallyDown
    case "accept", "accept this pose": return .accept
    case "again": return .again
    case "skip": return .skip
    case "end session", "end exploration": return .endSession
    default: return nil
    }
  }

  static func normalized(_ transcript: String) -> String {
    let characters = transcript
      .lowercased()
      .unicodeScalars
      .map { CharacterSet.alphanumerics.contains($0) ? Character(String($0)) : " " }
    return String(characters)
      .split(whereSeparator: { $0.isWhitespace })
      .joined(separator: " ")
  }
}

public struct ExplorationTeachingLabelParser: Sendable {
  public init() {}

  public func parse(
    _ transcript: String,
    allowedKinds: Set<ExplorationTeachingLabelKind>
  ) -> ExplorationTeachingLabel? {
    let normalized = ExplorationVoiceIntentParser.normalized(transcript)
    guard !normalized.isEmpty else { return nil }
    let words = Set(normalized.split(separator: " ").map(String.init))

    if allowedKinds.contains(.ranking),
      words.contains("best") || words.contains("prefer") || words.contains("preferred")
        || words.contains("rank") || words.contains("ranking") || words.contains("over")
    {
      return ExplorationTeachingLabel(
        rawTranscript: transcript,
        classification: .ranking(statement: normalized)
      )
    }

    if allowedKinds.contains(.visibility),
      let visibility = visibilityClassification(normalized: normalized, words: words)
    {
      return ExplorationTeachingLabel(
        rawTranscript: transcript,
        classification: .visibility(visibility, explanation: normalized)
      )
    }

    let featureVocabulary: Set<String> = [
      "closed", "closure", "open", "wide", "width", "narrow", "symmetry", "symmetric",
      "asymmetric", "smooth", "rough", "straight", "curved", "sharp", "rounded", "tall",
      "short", "thin", "thick",
    ]
    let features = words.intersection(featureVocabulary).sorted()
    if allowedKinds.contains(.shapeFeature),
      !features.isEmpty || allowedKinds == [.shapeFeature]
    {
      return ExplorationTeachingLabel(
        rawTranscript: transcript,
        classification: .shapeFeature(description: normalized, features: features)
      )
    }

    if allowedKinds.contains(.reward),
      let sentiment = rewardSentiment(words: words)
    {
      return ExplorationTeachingLabel(
        rawTranscript: transcript,
        classification: .reward(
          sentiment: sentiment,
          value: firstNumericValue(in: normalized),
          explanation: normalized
        )
      )
    }

    return nil
  }

  private func visibilityClassification(
    normalized: String,
    words: Set<String>
  ) -> ExplorationVisibilityLabel? {
    if normalized.contains("not blocked") || words.contains("unblocked") {
      return .clear
    }
    if words.contains("partial") || words.contains("partially") {
      return .partial
    }
    if words.contains("blocked") || words.contains("occluded")
      || normalized.contains("cannot see") || normalized.contains("cant see")
      || normalized.contains("not visible")
    {
      return .blocked
    }
    if words.contains("clear") || words.contains("clearly")
      || normalized.contains("can see") || words.contains("visible")
    {
      return .clear
    }
    return nil
  }

  private func rewardSentiment(words: Set<String>) -> ExplorationRewardSentiment? {
    let positive: Set<String> = ["good", "great", "yes", "like", "better", "success", "reward"]
    let negative: Set<String> = ["bad", "no", "dislike", "worse", "wrong", "penalty", "failure"]
    if !words.isDisjoint(with: positive) { return .positive }
    if !words.isDisjoint(with: negative) { return .negative }
    if words.contains("neutral") || words.contains("okay") { return .neutral }
    return nil
  }

  private func firstNumericValue(in normalized: String) -> Double? {
    normalized.split(separator: " ").lazy.compactMap { Double($0) }.first
  }
}

actor ExplorationSessionEventBuffer {
  private var continuations: [UUID: AsyncStream<ExplorationSessionEvent>.Continuation] = [:]

  func stream() -> AsyncStream<ExplorationSessionEvent> {
    let id = UUID()
    return AsyncStream(bufferingPolicy: .bufferingNewest(32)) { continuation in
      continuations[id] = continuation
      continuation.onTermination = { [weak self] _ in
        Task { await self?.remove(id) }
      }
    }
  }

  func yield(_ event: ExplorationSessionEvent) {
    for continuation in continuations.values {
      continuation.yield(event)
    }
  }

  private func remove(_ id: UUID) {
    continuations.removeValue(forKey: id)
  }
}

/// Owns one microphone lifetime across multiple typed learning episodes.
/// Episode changes replace parser context only; only session end/failure tears
/// down recognition. Injected simulator input uses the same routing boundary
/// without acquiring microphone or speech permission.
public actor ExplorationSession {
  private let driver: any VoiceInteractionDriving
  private let speechOutput: any VoiceSpeechOutput
  private let clock: any RuntimeClock
  private let intentParser = ExplorationVoiceIntentParser()
  private let labelParser = ExplorationTeachingLabelParser()
  private let eventBuffer = ExplorationSessionEventBuffer()

  private var generation: UInt64 = 0
  private var transcriptTask: Task<Void, Never>?
  private var id: ExplorationSessionID?
  private var input: ExplorationSessionInput?
  private var state: ExplorationSessionState = .inactive
  private var voiceSnapshot: VoiceInteractionSnapshot?
  private var activeEpisode: ExplorationEpisodeVoiceContext?
  private var latestTranscript: VoiceTranscript?
  private var latestRoutingResult: ExplorationVoiceRoutingResult?
  private var latestFeedback: ExplorationFeedbackReceipt?
  private var acceptedUtteranceIDs: Set<UUID> = []
  private var lastTimelineNanoseconds: UInt64 = 0

  public init(
    driver: any VoiceInteractionDriving,
    speechOutput: any VoiceSpeechOutput,
    clock: any RuntimeClock = SystemRuntimeClock()
  ) {
    self.driver = driver
    self.speechOutput = speechOutput
    self.clock = clock
  }

  @discardableResult
  public func start(
    input requestedInput: ExplorationSessionInput,
    id requestedID: ExplorationSessionID = ExplorationSessionID()
  ) async -> ExplorationSessionSnapshot {
    switch state {
    case .starting, .listening, .ending:
      return makeSnapshot()
    case .inactive, .failed:
      break
    }

    generation &+= 1
    let startGeneration = generation
    transcriptTask?.cancel()
    transcriptTask = nil
    id = requestedID
    input = requestedInput
    activeEpisode = nil
    latestTranscript = nil
    latestRoutingResult = nil
    latestFeedback = nil
    acceptedUtteranceIDs = []
    lastTimelineNanoseconds = 0
    state = .starting
    await eventBuffer.yield(.stateChanged(.starting))

    guard requestedInput == .microphone else {
      guard generation == startGeneration, state == .starting else { return makeSnapshot() }
      voiceSnapshot = nil
      state = .listening
      await eventBuffer.yield(.stateChanged(.listening))
      return makeSnapshot()
    }

    let stream = await driver.transcripts()
    guard generation == startGeneration, state == .starting else {
      await driver.stopListening()
      return makeSnapshot()
    }
    transcriptTask = Task { [weak self] in
      for await transcript in stream {
        guard !Task.isCancelled else { return }
        await self?.receiveDriverTranscript(transcript, generation: startGeneration)
      }
    }

    await driver.startListening()
    guard generation == startGeneration, state == .starting else {
      transcriptTask?.cancel()
      transcriptTask = nil
      await driver.stopListening()
      return makeSnapshot()
    }

    let snapshot = await driver.snapshot()
    guard generation == startGeneration, state == .starting else {
      transcriptTask?.cancel()
      transcriptTask = nil
      await driver.stopListening()
      return makeSnapshot()
    }
    voiceSnapshot = snapshot
    switch snapshot.listeningState {
    case .listening:
      state = .listening
      await eventBuffer.yield(.stateChanged(.listening))
    case .failed(let error):
      await transitionToFailure(.voice(error), generation: startGeneration)
    case .stopped, .requestingPermission:
      await transitionToFailure(
        .listeningDidNotStart(snapshot.listeningState),
        generation: startGeneration
      )
    }
    return makeSnapshot()
  }

  public func activateEpisode(_ context: ExplorationEpisodeVoiceContext) async throws {
    guard state == .listening else { throw ExplorationSessionError.notListening }
    if let activeEpisode {
      throw ExplorationSessionError.episodeAlreadyActive(activeEpisode.episodeID)
    }
    activeEpisode = context
    await eventBuffer.yield(.episodeActivated(context))
  }

  @discardableResult
  public func completeEpisode(
    _ episodeID: ExplorationEpisodeID,
    termination: ExplorationEpisodeTermination
  ) async throws -> ExplorationEpisodeVoiceContext {
    guard state == .listening else { throw ExplorationSessionError.notListening }
    guard let context = activeEpisode else { throw ExplorationSessionError.notListening }
    guard context.episodeID == episodeID else {
      throw ExplorationSessionError.wrongEpisode(
        expected: context.episodeID,
        actual: episodeID
      )
    }
    activeEpisode = nil
    await eventBuffer.yield(.episodeCompleted(episodeID, termination))
    return context
  }

  /// Routes deterministic simulator transcripts through the same boundary used
  /// by the native microphone stream. Any nonempty operator transcript first
  /// interrupts application speech, including rejected and duplicate input.
  @discardableResult
  public func ingest(_ transcript: VoiceTranscript) async -> ExplorationVoiceRoutingResult {
    guard state == .listening else { return .rejected(.sessionNotListening) }

    latestTranscript = transcript
    let hypothesisNanoseconds = advanceTimeline(atLeast: transcript.monotonicNanoseconds)
    if !transcript.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      await speechOutput.stopSpeaking()
    }

    guard let context = activeEpisode else {
      return await publishRouting(.rejected(.noActiveEpisode))
    }

    if let intent = intentParser.parse(transcript.text) {
      guard context.allowedIntents.contains(intent),
        intent != .stop || context.stopIsCancellable
      else {
        return await publishRouting(.rejected(.outOfContext))
      }
      guard transcript.stability != .unstablePartial else {
        return await publishRouting(.rejected(.unstableHypothesis))
      }
      guard acceptedUtteranceIDs.insert(transcript.utteranceID).inserted else {
        return await publishRouting(.rejected(.duplicateUtterance))
      }
      let acceptedNanoseconds = advanceTimeline(atLeast: hypothesisNanoseconds)
      let receipt = AcceptedExplorationIntent(
        context: context,
        intent: intent,
        transcript: transcript,
        timing: ExplorationVoiceTiming(
          hypothesisNanoseconds: hypothesisNanoseconds,
          acceptedNanoseconds: acceptedNanoseconds
        )
      )
      return await publishRouting(.acceptedIntent(receipt))
    }

    guard transcript.stability != .unstablePartial else {
      return await publishRouting(.rejected(.unstableHypothesis))
    }
    guard let label = labelParser.parse(
      transcript.text,
      allowedKinds: context.teachingLabelKinds
    ) else {
      return await publishRouting(.rejected(.outOfContext))
    }
    guard acceptedUtteranceIDs.insert(transcript.utteranceID).inserted else {
      return await publishRouting(.rejected(.duplicateUtterance))
    }
    let acceptedNanoseconds = advanceTimeline(atLeast: hypothesisNanoseconds)
    let receipt = AcceptedExplorationTeachingLabel(
      context: context,
      label: label,
      transcript: transcript,
      timing: ExplorationVoiceTiming(
        hypothesisNanoseconds: hypothesisNanoseconds,
        acceptedNanoseconds: acceptedNanoseconds
      )
    )
    return await publishRouting(.acceptedTeachingLabel(receipt))
  }

  @discardableResult
  public func speakFeedback(_ text: String) async -> ExplorationFeedbackReceipt? {
    guard state == .listening else { return nil }
    let message = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !message.isEmpty else { return nil }
    let receipt = ExplorationFeedbackReceipt(
      text: message,
      onsetNanoseconds: advanceTimeline(atLeast: clock.nowNanoseconds())
    )
    latestFeedback = receipt
    await speechOutput.speak(message)
    await eventBuffer.yield(.feedback(receipt))
    return receipt
  }

  public func end() async {
    switch state {
    case .inactive, .ending:
      return
    case .starting, .listening, .failed:
      break
    }
    generation &+= 1
    let endGeneration = generation
    state = .ending
    activeEpisode = nil
    transcriptTask?.cancel()
    transcriptTask = nil
    await eventBuffer.yield(.stateChanged(.ending))
    await speechOutput.stopSpeaking()
    if input == .microphone {
      await driver.stopListening()
      voiceSnapshot = await driver.snapshot()
    }
    guard generation == endGeneration, state == .ending else { return }
    input = nil
    state = .inactive
    await eventBuffer.yield(.stateChanged(.inactive))
  }

  public func shutdown() async {
    await end()
  }

  public func snapshot() async -> ExplorationSessionSnapshot {
    guard state == .listening, input == .microphone else { return makeSnapshot() }
    let snapshotGeneration = generation
    let current = await driver.snapshot()
    guard generation == snapshotGeneration, state == .listening else { return makeSnapshot() }
    voiceSnapshot = current
    switch current.listeningState {
    case .listening:
      break
    case .failed(let error):
      await transitionToFailure(.voice(error), generation: snapshotGeneration)
    case .stopped, .requestingPermission:
      await transitionToFailure(
        .listeningDidNotStart(current.listeningState),
        generation: snapshotGeneration
      )
    }
    return makeSnapshot()
  }

  public func events() async -> AsyncStream<ExplorationSessionEvent> {
    await eventBuffer.stream()
  }

  private func receiveDriverTranscript(_ transcript: VoiceTranscript, generation: UInt64) async {
    guard self.generation == generation, state == .listening, input == .microphone else { return }
    _ = await ingest(transcript)
  }

  private func publishRouting(
    _ result: ExplorationVoiceRoutingResult
  ) async -> ExplorationVoiceRoutingResult {
    latestRoutingResult = result
    await eventBuffer.yield(.routed(result))
    return result
  }

  private func transitionToFailure(
    _ failure: ExplorationSessionFailure,
    generation expectedGeneration: UInt64
  ) async {
    guard generation == expectedGeneration else { return }
    generation &+= 1
    state = .failed(failure)
    activeEpisode = nil
    transcriptTask?.cancel()
    transcriptTask = nil
    await speechOutput.stopSpeaking()
    if input == .microphone {
      await driver.stopListening()
      voiceSnapshot = await driver.snapshot()
    }
    await eventBuffer.yield(.stateChanged(.failed(failure)))
  }

  private func advanceTimeline(atLeast lowerBound: UInt64) -> UInt64 {
    let afterLast = lastTimelineNanoseconds == UInt64.max
      ? UInt64.max
      : lastTimelineNanoseconds + 1
    let next = max(clock.nowNanoseconds(), lowerBound, afterLast)
    lastTimelineNanoseconds = next
    return next
  }

  private func makeSnapshot() -> ExplorationSessionSnapshot {
    ExplorationSessionSnapshot(
      id: id,
      input: input,
      state: state,
      voice: voiceSnapshot,
      activeEpisode: activeEpisode,
      latestTranscript: latestTranscript,
      latestRoutingResult: latestRoutingResult,
      latestFeedback: latestFeedback
    )
  }
}
