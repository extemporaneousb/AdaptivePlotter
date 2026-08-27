import EpisodeCore
import Foundation
import PlotterEpisodeModel

public struct ControllerReplayScenarioID: RawRepresentable, Codable, Hashable, Sendable {
  public let rawValue: String

  public init(rawValue: String) {
    self.rawValue = rawValue
  }
}

/// The complete and deliberately closed set of controller-traffic changes
/// accepted by the replay service. There is no arbitrary callback or effect
/// runner at this boundary.
public enum ControllerReplayPerturbation: Codable, Hashable, Sendable {
  case legalReadFragmentation(maximumChunkByteCount: Int)
  case completionDelay(
    invocationID: ControllerInvocationID,
    additionalNanoseconds: UInt64
  )
  case timeout(
    invocationID: ControllerInvocationID,
    atNanosecondsAfterInvocation: UInt64
  )
  case cancellation(
    invocationID: ControllerInvocationID,
    atNanosecondsAfterInvocation: UInt64
  )
}

public struct ControllerReplayScenario: Codable, Hashable, Sendable {
  public let id: ControllerReplayScenarioID
  public let perturbations: [ControllerReplayPerturbation]

  public init(
    id: ControllerReplayScenarioID,
    perturbations: [ControllerReplayPerturbation]
  ) {
    self.id = id
    self.perturbations = perturbations
  }
}

public struct PlotterEpisodeReplayIntentCandidate: Codable, Hashable, Sendable {
  public let requestID: IntentRequestID
  public let intent: PlotterIntent

  public init(requestID: IntentRequestID, intent: PlotterIntent) {
    self.requestID = requestID
    self.intent = intent
  }
}

/// Caller-supplied deterministic inputs for one exact journal prefix. Replay
/// never substitutes current capability state for an absent recorded timeline.
public struct PlotterEpisodeReplayDecisionFrame: Codable, Hashable, Sendable {
  public let prefixEventCount: Int
  public let candidates: [PlotterEpisodeReplayIntentCandidate]
  public let capabilityFacts: [PlotterCapabilityFact]

  public init(
    prefixEventCount: Int,
    candidates: [PlotterEpisodeReplayIntentCandidate],
    capabilityFacts: [PlotterCapabilityFact]
  ) {
    self.prefixEventCount = prefixEventCount
    self.candidates = candidates
    self.capabilityFacts = capabilityFacts
  }
}

/// Recording-declared effect identity only. Replay never executes an effect
/// and therefore does not claim that the linked build supports its executor
/// revision.
public enum PlotterEpisodeRecordedEffectRevisionAuthority:
  String, Codable, Hashable, Sendable
{
  case recordedIdentityOnlyNoExecutorValidation
}

public struct PlotterEpisodeRecordedEffectRevision: Codable, Hashable, Sendable {
  public let effectID: EpisodeEffectID
  public let revision: EpisodeRevisionIdentifier
  public var authority: PlotterEpisodeRecordedEffectRevisionAuthority {
    .recordedIdentityOnlyNoExecutorValidation
  }

  public init(effectID: EpisodeEffectID, revision: EpisodeRevisionIdentifier) {
    self.effectID = effectID
    self.revision = revision
  }
}

/// Sealed facts owned by the concrete evaluator/reducer/digest adapter used by
/// `PlotterEpisodeReplayService`. No replay entry point accepts one from a
/// caller, so manifest agreement cannot be manufactured with supplied labels.
public enum PlotterEpisodeReplayExecutableDescriptor:
  String, Codable, Hashable, Sendable
{
  case plotterEpisodeReplayV1

  public var domainRevision: EpisodeRevisionIdentifier {
    EpisodeRevisionIdentifier(rawValue: "plotter-domain-v1")
  }

  public var evaluatorRevision: EpisodeRevisionIdentifier {
    EpisodeRevisionIdentifier(rawValue: "plotter-intent-evaluator-v1")
  }

  public var reducerRevision: EpisodeRevisionIdentifier {
    EpisodeRevisionIdentifier(rawValue: "plotter-episode-reducer-v1")
  }

  public var schemaRevisions: EpisodeSchemaRevisions {
    EpisodeSchemaRevisions(
      state: EpisodeRevisionIdentifier(rawValue: "plotter-episode-state-v1"),
      event: EpisodeRevisionIdentifier(rawValue: "plotter-episode-event-v1"),
      journal: EpisodeRevisionIdentifier(rawValue: "episode-journal-v1")
    )
  }

  public var buildRevision: EpisodeRevisionIdentifier {
    EpisodeRevisionIdentifier(rawValue: "adaptiveplotter-replay-build-v1")
  }

  public var canonicalDigestRevision: EpisodeRevisionIdentifier {
    // Keep this descriptor pin independent from the implementation constant.
    // `pinDisagreements` compares the two before accepting any prefix.
    EpisodeRevisionIdentifier(rawValue: "plotter-episode-canonical-state-digest-v1")
  }

  public var consumesDeterministicSeed: Bool { false }
}

public enum PlotterEpisodeReplayRevisionComponent: String, Codable, Hashable, Sendable {
  case domain
  case evaluator
  case reducer
  case stateSchema
  case eventSchema
  case journalSchema
  case build
  case canonicalDigest
}

/// Full operation identity used to attribute recording-side start evidence.
/// Intent and effect revision are retained even though the recording
/// provenance schema can carry only the remaining components.
public struct PlotterEpisodeReplayOperationBinding: Codable, Hashable, Sendable {
  public let episodeID: EpisodeID
  public let requestID: IntentRequestID
  public let intent: PlotterIntent
  public let effectID: EpisodeEffectID
  public let effectRevision: EpisodeRevisionIdentifier
  public let correlationID: EpisodeCorrelationID
  public let environment: PlotterEnvironment

  public init(
    episodeID: EpisodeID,
    requestID: IntentRequestID,
    intent: PlotterIntent,
    effectID: EpisodeEffectID,
    effectRevision: EpisodeRevisionIdentifier,
    correlationID: EpisodeCorrelationID,
    environment: PlotterEnvironment
  ) {
    self.episodeID = episodeID
    self.requestID = requestID
    self.intent = intent
    self.effectID = effectID
    self.effectRevision = effectRevision
    self.correlationID = correlationID
    self.environment = environment
  }
}

public struct ControllerReplayStep: Codable, Hashable, Sendable {
  public let sourceRecordingSequence: UInt64
  public let replayOffsetNanoseconds: UInt64
  public let provenance: EpisodeRecordingProvenance
  public let record: ControllerTranscriptRecord

  public init(
    sourceRecordingSequence: UInt64,
    replayOffsetNanoseconds: UInt64,
    provenance: EpisodeRecordingProvenance,
    record: ControllerTranscriptRecord
  ) {
    self.sourceRecordingSequence = sourceRecordingSequence
    self.replayOffsetNanoseconds = replayOffsetNanoseconds
    self.provenance = provenance
    self.record = record
  }
}

public enum ControllerReplayPerturbationRefusal: Codable, Hashable, Sendable {
  case controllerSourceAbsent
  case readTrafficAbsent
  case invalidMaximumChunkByteCount(Int)
  case unknownInvocation(ControllerInvocationID)
  case completionMissing(ControllerInvocationID)
  case conflictingTerminalPerturbations(ControllerInvocationID)
  case conflictingTimingPerturbations(ControllerInvocationID)
  case timestampOverflow(ControllerInvocationID)
  case timestampUnderflow(ControllerInvocationID)
  case operationIsNotTimedRead(ControllerInvocationID)
  case completionIsNotSuccessfulRead(ControllerInvocationID)
  case boundaryExceedsReadTimeout(ControllerInvocationID)
  case boundaryAfterCompletion(ControllerInvocationID)
  case delayedCompletionExceedsReadTimeout(ControllerInvocationID)
  case boundaryWouldReorderControllerTraffic(ControllerInvocationID)
  case invalidTransformedSchedule(ControllerReplayScheduleCausalityViolation)
}

/// A global causal-integrity failure in the complete transformed controller
/// schedule. Perturbations are refused rather than publishing any candidate
/// that is valid only for the directly targeted invocation.
public enum ControllerReplayScheduleCausalityViolation:
  Codable, Hashable, Sendable
{
  case sourceSequenceRegression(UInt64)
  case replayOffsetRegression(UInt64)
  case duplicateInvocation(ControllerInvocationID)
  case invalidInvocation(ControllerInvocationID)
  case completionWithoutInvocation(ControllerInvocationID)
  case completionPrecedesInvocation(ControllerInvocationID)
  case duplicateCompletion(ControllerInvocationID)
  case timedReadDeadlineOverflow(ControllerInvocationID)
  case timedReadDeadlineExceeded(ControllerInvocationID)
  case readChunkPrecedesInvocation(ControllerInvocationID)
  case readChunkAfterCompletion(ControllerInvocationID)
  case readChunkOffsetRegression(ControllerInvocationID)
  case emptyReadChunk(ControllerInvocationID)
  case maximumReadByteCountExceeded(ControllerInvocationID)
  case operationOutcomeMismatch(ControllerInvocationID)
  case invalidPartialResult(ControllerInvocationID)
}

public enum ControllerReplayScenarioDisposition: Codable, Hashable, Sendable {
  case applied
  case refused([ControllerReplayPerturbationRefusal])
}

public struct ControllerReplayScenarioResult: Codable, Hashable, Sendable {
  public let id: ControllerReplayScenarioID
  public let declaredPerturbations: [ControllerReplayPerturbation]
  public let disposition: ControllerReplayScenarioDisposition
  public let steps: [ControllerReplayStep]

  public init(
    id: ControllerReplayScenarioID,
    declaredPerturbations: [ControllerReplayPerturbation],
    disposition: ControllerReplayScenarioDisposition,
    steps: [ControllerReplayStep]
  ) {
    self.id = id
    self.declaredPerturbations = declaredPerturbations
    self.disposition = disposition
    self.steps = steps
  }
}

public enum PlotterEpisodeReplayDisagreement: Codable, Hashable, Sendable {
  case definitionID(expected: EpisodeDefinitionID, actual: EpisodeDefinitionID)
  case definitionRevision(
    expected: EpisodeRevisionIdentifier,
    actual: EpisodeRevisionIdentifier
  )
  case executableRevision(
    component: PlotterEpisodeReplayRevisionComponent,
    expected: EpisodeRevisionIdentifier,
    actual: EpisodeRevisionIdentifier
  )
  case missingRecordedEffectRevision(EpisodeEffectID)
  case duplicateRecordedEffectRevision(EpisodeEffectID)
  case definitionInitialContextDoesNotMatchDomainManifest
  case journalManifestID(expected: EpisodeManifestID, actual: EpisodeManifestID)
  case journalEpisodeID(expected: EpisodeID, actual: EpisodeID)
  case journalInitialRevision(
    expected: EpisodeStateRevision,
    actual: EpisodeStateRevision
  )
  case initialStateEpisodeID(expected: EpisodeID, actual: EpisodeID)
  case initialStateRevision(expected: EpisodeStateRevision, actual: EpisodeStateRevision)
  case initialStateRecordedDigest(expected: EpisodeStateDigest, actual: EpisodeStateDigest)
  case initialStateIntentGrammar
  case initialStatePlanRevision
  case initialStateDigest(expected: EpisodeStateDigest, actual: EpisodeStateDigest)
  case canonicalStateDigestUnavailable(index: Int?)
  case missingDecisionFrame(prefixEventCount: Int)
  case duplicateDecisionFrame(prefixEventCount: Int)
  case decisionFrameOutOfRange(prefixEventCount: Int)
  case duplicateIntentCandidate(prefixEventCount: Int, requestID: IntentRequestID)
  case committedIntentMissingCandidate(index: Int, requestID: IntentRequestID)
  case committedIntentDecisionMismatch(index: Int, requestID: IntentRequestID)
  case journalPrefixRejected(prefixEventCount: Int)
  case reducerInputEpisode(index: Int, expected: EpisodeID, actual: EpisodeID)
  case reducerInputRevision(
    index: Int,
    expected: EpisodeStateRevision,
    actual: EpisodeStateRevision
  )
  case reducerOutputEpisode(index: Int, expected: EpisodeID, actual: EpisodeID)
  case reducerOutputRevision(
    index: Int,
    expected: EpisodeStateRevision,
    actual: EpisodeStateRevision
  )
  case reducerOutputDigest(
    index: Int,
    expected: EpisodeStateDigest,
    actual: EpisodeStateDigest
  )
  case nondeterministicPrefix(prefixEventCount: Int)
  case duplicateEffectEmission(EpisodeEffectID)
  case effectProgressWithoutEmission(index: Int, effectID: EpisodeEffectID)
  case effectProgressIdentityMismatch(index: Int, effectID: EpisodeEffectID)
  case effectProgressAfterSettlement(
    index: Int,
    effectID: EpisodeEffectID,
    settledByEventID: EpisodeEventID
  )
  case effectResultWithoutEmission(index: Int, effectID: EpisodeEffectID)
  case effectResultIdentityMismatch(index: Int, effectID: EpisodeEffectID)
  case multipleEffectResults(
    index: Int,
    effectID: EpisodeEffectID,
    firstSettledByEventID: EpisodeEventID
  )
  case controllerCompletionProvenanceMismatch(
    invocationID: ControllerInvocationID,
    invocationSequence: UInt64,
    completionSequence: UInt64
  )
  case recordingOperationBindingMismatch(
    recordingSequence: UInt64,
    expected: PlotterEpisodeReplayOperationBinding,
    actual: EpisodeRecordingProvenance
  )
  case recordingStartUnattributed(recordingSequence: UInt64)
}

public struct PlotterEpisodeReplayEventVerification: Codable, Hashable, Sendable {
  public let eventID: EpisodeEventID
  public let index: Int
  public let expectedSequence: EpisodeEventSequence
  public let actualSequence: EpisodeEventSequence
  public let expectedPreStateRevision: EpisodeStateRevision
  public let actualPreStateRevision: EpisodeStateRevision
  public let expectedPostStateRevision: EpisodeStateRevision
  public let actualPostStateRevision: EpisodeStateRevision
  public let recordedPostStateDigest: EpisodeStateDigest
  public let reducerPostStateDigest: EpisodeStateDigest
  public let independentlyComputedPostStateDigest: EpisodeStateDigest

  public var isVerified: Bool {
    expectedSequence == actualSequence
      && expectedPreStateRevision == actualPreStateRevision
      && expectedPostStateRevision == actualPostStateRevision
      && recordedPostStateDigest == reducerPostStateDigest
      && recordedPostStateDigest == independentlyComputedPostStateDigest
  }

  public init(
    eventID: EpisodeEventID,
    index: Int,
    expectedSequence: EpisodeEventSequence,
    actualSequence: EpisodeEventSequence,
    expectedPreStateRevision: EpisodeStateRevision,
    actualPreStateRevision: EpisodeStateRevision,
    expectedPostStateRevision: EpisodeStateRevision,
    actualPostStateRevision: EpisodeStateRevision,
    recordedPostStateDigest: EpisodeStateDigest,
    reducerPostStateDigest: EpisodeStateDigest,
    independentlyComputedPostStateDigest: EpisodeStateDigest
  ) {
    self.eventID = eventID
    self.index = index
    self.expectedSequence = expectedSequence
    self.actualSequence = actualSequence
    self.expectedPreStateRevision = expectedPreStateRevision
    self.actualPreStateRevision = actualPreStateRevision
    self.expectedPostStateRevision = expectedPostStateRevision
    self.actualPostStateRevision = actualPostStateRevision
    self.recordedPostStateDigest = recordedPostStateDigest
    self.reducerPostStateDigest = reducerPostStateDigest
    self.independentlyComputedPostStateDigest = independentlyComputedPostStateDigest
  }
}

public enum PlotterEpisodeReplayEffectStartEvidence: Codable, Hashable, Sendable {
  case journalProgress(eventID: EpisodeEventID)
  case controllerInvocation(recordingSequence: UInt64)
  case cameraLifecycleRequest(recordingSequence: UInt64)
}

public struct PlotterEpisodeReplayEffect: Codable, Hashable, Sendable {
  public let effect: PlotterEffect
  public let intent: PlotterIntent
  public let operationBinding: PlotterEpisodeReplayOperationBinding
  public let emittedByEventID: EpisodeEventID
  public let emittedAtSequence: EpisodeEventSequence
  public let startEvidence: [PlotterEpisodeReplayEffectStartEvidence]
  public let settledByEventID: EpisodeEventID?

  public var wasStarted: Bool { !startEvidence.isEmpty }
  public var isSettled: Bool { settledByEventID != nil }

  public init(
    effect: PlotterEffect,
    intent: PlotterIntent,
    operationBinding: PlotterEpisodeReplayOperationBinding,
    emittedByEventID: EpisodeEventID,
    emittedAtSequence: EpisodeEventSequence,
    startEvidence: [PlotterEpisodeReplayEffectStartEvidence],
    settledByEventID: EpisodeEventID?
  ) {
    self.effect = effect
    self.intent = intent
    self.operationBinding = operationBinding
    self.emittedByEventID = emittedByEventID
    self.emittedAtSequence = emittedAtSequence
    self.startEvidence = startEvidence
    self.settledByEventID = settledByEventID
  }
}

public enum PlotterEpisodeReplayPhysicalEffectClassification: Codable, Hashable, Sendable {
  case noStartedUnsettledEffect
  case possiblePhysicalEffect([PlotterEpisodeReplayEffect])
}

public enum PlotterEpisodeReplayNoResumeReason: Codable, Hashable, Sendable {
  case unboundReplayNeverExecutesEffects
  case possiblePhysicalEffect([EpisodeEffectID])
}

public enum PlotterEpisodeReplayResumeDisposition: Codable, Hashable, Sendable {
  case neverResume(PlotterEpisodeReplayNoResumeReason)
}

public struct PlotterEpisodeReplayPrefix: Codable, Hashable, Sendable {
  public let eventCount: Int
  public let state: PlotterEpisodeState
  public let intentAvailabilities: [PlotterIntentAvailability]
  public let eventVerifications: [PlotterEpisodeReplayEventVerification]
  public let emittedEffects: [PlotterEpisodeReplayEffect]
  public let physicalEffectClassification: PlotterEpisodeReplayPhysicalEffectClassification
  public let resumeDisposition: PlotterEpisodeReplayResumeDisposition

  public init(
    eventCount: Int,
    state: PlotterEpisodeState,
    intentAvailabilities: [PlotterIntentAvailability],
    eventVerifications: [PlotterEpisodeReplayEventVerification],
    emittedEffects: [PlotterEpisodeReplayEffect],
    physicalEffectClassification: PlotterEpisodeReplayPhysicalEffectClassification,
    resumeDisposition: PlotterEpisodeReplayResumeDisposition
  ) {
    self.eventCount = eventCount
    self.state = state
    self.intentAvailabilities = intentAvailabilities
    self.eventVerifications = eventVerifications
    self.emittedEffects = emittedEffects
    self.physicalEffectClassification = physicalEffectClassification
    self.resumeDisposition = resumeDisposition
  }
}

public struct PlotterEpisodeReplayRecordingInspection: Codable, Hashable, Sendable {
  public let recordingID: EpisodeRecordingID
  public let schemaRevision: EpisodeRecordingSchemaRevision
  public let isClosed: Bool
  public let durability: EpisodeRecordingDurability
  public let completeness: PlotterEpisodeReplayRecordingCompleteness
  public let entries: [EpisodeRecordingEntry]

  public init(snapshot: EpisodeRecordingSnapshot) {
    recordingID = snapshot.recordingID
    schemaRevision = snapshot.schemaRevision
    isClosed = snapshot.isClosed
    durability = snapshot.durability
    completeness = PlotterEpisodeReplayRecordingCompleteness(snapshot.completenessIssues)
    entries = snapshot.entries
  }
}

public struct PlotterEpisodeReplayRecordingCompleteness: Codable, Hashable, Sendable {
  public let controller: [EpisodeRecordingCompletenessIssue]
  public let camera: [EpisodeRecordingCompletenessIssue]
  public let runLedger: [EpisodeRecordingCompletenessIssue]
  public let globalDiagnostics: [EpisodeRecordingCompletenessIssue]

  public var isComplete: Bool {
    controller.isEmpty && camera.isEmpty && runLedger.isEmpty && globalDiagnostics.isEmpty
  }

  public init(_ issues: [EpisodeRecordingCompletenessIssue]) {
    var controller: [EpisodeRecordingCompletenessIssue] = []
    var camera: [EpisodeRecordingCompletenessIssue] = []
    var runLedger: [EpisodeRecordingCompletenessIssue] = []
    var global: [EpisodeRecordingCompletenessIssue] = []
    for issue in issues {
      switch issue {
      case .controllerCompletionMissing:
        controller.append(issue)
      case .cameraStartIncomplete, .cameraReconfigurationIncomplete,
           .cameraStopIncomplete, .frameBytesMissing, .frameBytesTruncated,
           .frameByteCountMismatch, .frameHashMismatch, .frameArtifactUnreadable,
           .frameArtifactUnsafe, .unreferencedFrameArtifact,
           .unrecognizedFrameArtifact, .durableFrameArtifactUnreadable,
           .durableFrameArtifactUnsafe, .durableFrameArtifactHashMismatch:
        camera.append(issue)
      case .runLedgerIntegrityIncomplete, .runLedgerRangeIncomplete:
        runLedger.append(issue)
      case .frameRetentionAccountingOverflow:
        global.append(issue)
      }
    }
    self.controller = controller
    self.camera = camera
    self.runLedger = runLedger
    globalDiagnostics = global
  }
}

public struct PlotterEpisodeReplayReport: Codable, Hashable, Sendable {
  public let manifest: PlotterEpisodeManifest
  public let definition: PlotterEpisodeDefinition
  public let executableDescriptor: PlotterEpisodeReplayExecutableDescriptor
  public let recordedEffectRevisions: [PlotterEpisodeRecordedEffectRevision]
  public let prefixes: [PlotterEpisodeReplayPrefix]
  public let recording: PlotterEpisodeReplayRecordingInspection?
  public let controllerScenarios: [ControllerReplayScenarioResult]
  public let disagreements: [PlotterEpisodeReplayDisagreement]

  public var isInAgreement: Bool { disagreements.isEmpty }

  public init(
    manifest: PlotterEpisodeManifest,
    definition: PlotterEpisodeDefinition,
    executableDescriptor: PlotterEpisodeReplayExecutableDescriptor,
    recordedEffectRevisions: [PlotterEpisodeRecordedEffectRevision],
    prefixes: [PlotterEpisodeReplayPrefix],
    recording: PlotterEpisodeReplayRecordingInspection?,
    controllerScenarios: [ControllerReplayScenarioResult],
    disagreements: [PlotterEpisodeReplayDisagreement]
  ) {
    self.manifest = manifest
    self.definition = definition
    self.executableDescriptor = executableDescriptor
    self.recordedEffectRevisions = recordedEffectRevisions
    self.prefixes = prefixes
    self.recording = recording
    self.controllerScenarios = controllerScenarios
    self.disagreements = disagreements
  }
}

private struct PlotterEpisodeReplayExecutableAdapter: Sendable {
  let descriptor = PlotterEpisodeReplayExecutableDescriptor.plotterEpisodeReplayV1

  func reduce(
    state: PlotterEpisodeState,
    event: PlotterEpisodeEvent
  ) -> EpisodeReduction<PlotterEpisodeState, PlotterEffect> {
    PlotterEpisodeReducer().reduce(state: state, event: event)
  }

  func evaluate(
    requestID: IntentRequestID,
    intent: PlotterIntent,
    state: PlotterEpisodeState,
    capabilityFacts: [PlotterCapabilityFact]
  ) -> IntentDecision {
    PlotterIntentEvaluator().evaluate(
      requestID: requestID,
      intent: intent,
      state: state,
      capabilityFacts: capabilityFacts
    )
  }

  func canonicalDigest(_ state: PlotterEpisodeState) throws -> EpisodeStateDigest {
    try PlotterEpisodeCanonicalDigestV1.digest(state)
  }
}

/// Pure, unbound reconstruction over the production Plotter reducer. Reducer
/// outputs are retained as inert values for inspection; this service has no
/// effect executor, resume capability, store, registry, or device dependency.
public struct PlotterEpisodeReplayService: Sendable {
  private let executable: PlotterEpisodeReplayExecutableAdapter

  public static var executableDescriptor: PlotterEpisodeReplayExecutableDescriptor {
    PlotterEpisodeReplayExecutableAdapter().descriptor
  }

  public init() {
    executable = PlotterEpisodeReplayExecutableAdapter()
  }

  public func replay(
    definition: PlotterEpisodeDefinition,
    manifest: PlotterEpisodeManifest,
    recordedEffectRevisions: [PlotterEpisodeRecordedEffectRevision],
    initialState: PlotterEpisodeState,
    journal: EpisodeJournal<PlotterEpisodeEventPayload>,
    decisionTimeline: [PlotterEpisodeReplayDecisionFrame],
    recording: EpisodeRecordingSnapshot? = nil,
    controllerScenarios: [ControllerReplayScenario] = []
  ) -> PlotterEpisodeReplayReport {
    var disagreements = pinDisagreements(
      definition: definition,
      manifest: manifest,
      executableDescriptor: executable.descriptor,
      recordedEffectRevisions: recordedEffectRevisions,
      initialState: initialState,
      journal: journal
    )
    let bindings = operationBindings(
      journal: journal,
      recordedEffectRevisions: recordedEffectRevisions
    )
    let frames = decisionFrames(
      decisionTimeline,
      requiredPrefixCount: journal.events.count + 1,
      disagreements: &disagreements
    )
    let recordingInspection = recording.map(PlotterEpisodeReplayRecordingInspection.init)
    if let recording {
      disagreements.append(contentsOf: provenanceDisagreements(
        operationBindings: bindings,
        recording: recording
      ))
    }

    let controllerSteps = recording.map(controllerReplaySteps)
    let scenarioResults = controllerScenarios.map {
      apply($0, to: controllerSteps)
    }

    if let digest = try? executable.canonicalDigest(initialState) {
      if digest != initialState.canonicalDigest {
        disagreements.append(.initialStateDigest(
          expected: initialState.canonicalDigest,
          actual: digest
        ))
      }
    } else {
      disagreements.append(.canonicalStateDigestUnavailable(index: nil))
    }

    guard disagreements.filter({ $0.blocksPinnedReplay }).isEmpty else {
      return PlotterEpisodeReplayReport(
        manifest: manifest,
        definition: definition,
        executableDescriptor: executable.descriptor,
        recordedEffectRevisions: recordedEffectRevisions,
        prefixes: [],
        recording: recordingInspection,
        controllerScenarios: scenarioResults,
        disagreements: disagreements
      )
    }

    var prefixes: [PlotterEpisodeReplayPrefix] = []
    for eventCount in 0...journal.events.count {
      guard let decisionFrame = frames[eventCount] else {
        disagreements.append(.missingDecisionFrame(prefixEventCount: eventCount))
        continue
      }
      guard let first = reconstructPrefix(
        eventCount: eventCount,
        initialState: initialState,
        journal: journal,
        executable: executable,
        recordedEffectRevisions: recordedEffectRevisions,
        recording: recording,
        decisionFrame: decisionFrame,
        decisionTimeline: frames
      ) else {
        disagreements.append(.journalPrefixRejected(prefixEventCount: eventCount))
        continue
      }
      if let second = reconstructPrefix(
        eventCount: eventCount,
        initialState: initialState,
        journal: journal,
        executable: executable,
        recordedEffectRevisions: recordedEffectRevisions,
        recording: recording,
        decisionFrame: decisionFrame,
        decisionTimeline: frames
      ), second.prefix != first.prefix || second.disagreements != first.disagreements {
        disagreements.append(.nondeterministicPrefix(prefixEventCount: eventCount))
      }
      disagreements.append(contentsOf: first.disagreements)
      if first.disagreements.contains(where: { $0.blocksPrefixPublication }) {
        disagreements.append(.journalPrefixRejected(prefixEventCount: eventCount))
        continue
      }
      prefixes.append(first.prefix)
    }

    return PlotterEpisodeReplayReport(
      manifest: manifest,
      definition: definition,
      executableDescriptor: executable.descriptor,
      recordedEffectRevisions: recordedEffectRevisions,
      prefixes: prefixes,
      recording: recordingInspection,
      controllerScenarios: scenarioResults,
      disagreements: unique(disagreements)
    )
  }
}

private extension PlotterEpisodeReplayDisagreement {
  var blocksPinnedReplay: Bool {
    switch self {
    case .definitionID, .definitionRevision,
         .executableRevision,
         .missingRecordedEffectRevision, .duplicateRecordedEffectRevision,
         .definitionInitialContextDoesNotMatchDomainManifest,
         .journalManifestID, .journalEpisodeID, .journalInitialRevision,
         .initialStateEpisodeID, .initialStateRevision, .initialStateRecordedDigest,
         .initialStateIntentGrammar, .initialStatePlanRevision,
         .initialStateDigest, .canonicalStateDigestUnavailable,
         .missingDecisionFrame, .duplicateDecisionFrame, .decisionFrameOutOfRange,
         .duplicateIntentCandidate:
      return true
    case .journalPrefixRejected, .reducerInputEpisode, .reducerInputRevision,
         .reducerOutputEpisode, .reducerOutputRevision, .reducerOutputDigest,
         .nondeterministicPrefix, .duplicateEffectEmission,
         .effectProgressWithoutEmission, .effectProgressIdentityMismatch,
         .effectProgressAfterSettlement,
         .effectResultWithoutEmission, .effectResultIdentityMismatch,
         .multipleEffectResults,
         .controllerCompletionProvenanceMismatch, .recordingOperationBindingMismatch,
         .recordingStartUnattributed, .committedIntentMissingCandidate,
         .committedIntentDecisionMismatch:
      return false
    }
  }

  /// A production-reducer output remains useful diagnostic evidence, but a
  /// lifecycle-invalid event must never publish the state it influenced as an
  /// accepted replay prefix.
  var blocksPrefixPublication: Bool {
    switch self {
    case .duplicateEffectEmission,
         .effectProgressWithoutEmission, .effectProgressIdentityMismatch,
         .effectProgressAfterSettlement,
         .effectResultWithoutEmission, .effectResultIdentityMismatch,
         .multipleEffectResults:
      return true
    default:
      return false
    }
  }
}

private struct PrefixReconstruction: Equatable {
  let prefix: PlotterEpisodeReplayPrefix
  let disagreements: [PlotterEpisodeReplayDisagreement]
}

private struct MutableEffectReplay: Equatable {
  let effect: PlotterEffect
  let intent: PlotterIntent
  let operationBinding: PlotterEpisodeReplayOperationBinding
  let emittedByEventID: EpisodeEventID
  let emittedAtSequence: EpisodeEventSequence
  var startEvidence: [PlotterEpisodeReplayEffectStartEvidence]
  var settledByEventID: EpisodeEventID?

  var value: PlotterEpisodeReplayEffect {
    PlotterEpisodeReplayEffect(
      effect: effect,
      intent: intent,
      operationBinding: operationBinding,
      emittedByEventID: emittedByEventID,
      emittedAtSequence: emittedAtSequence,
      startEvidence: startEvidence,
      settledByEventID: settledByEventID
    )
  }
}

private func decisionFrames(
  _ timeline: [PlotterEpisodeReplayDecisionFrame],
  requiredPrefixCount: Int,
  disagreements: inout [PlotterEpisodeReplayDisagreement]
) -> [Int: PlotterEpisodeReplayDecisionFrame] {
  var frames: [Int: PlotterEpisodeReplayDecisionFrame] = [:]
  for frame in timeline {
    guard frame.prefixEventCount >= 0, frame.prefixEventCount < requiredPrefixCount else {
      disagreements.append(.decisionFrameOutOfRange(
        prefixEventCount: frame.prefixEventCount
      ))
      continue
    }
    guard frames[frame.prefixEventCount] == nil else {
      disagreements.append(.duplicateDecisionFrame(
        prefixEventCount: frame.prefixEventCount
      ))
      continue
    }
    var requestIDs = Set<IntentRequestID>()
    for candidate in frame.candidates where !requestIDs.insert(candidate.requestID).inserted {
      disagreements.append(.duplicateIntentCandidate(
        prefixEventCount: frame.prefixEventCount,
        requestID: candidate.requestID
      ))
    }
    frames[frame.prefixEventCount] = frame
  }
  for prefixEventCount in 0..<requiredPrefixCount where frames[prefixEventCount] == nil {
    disagreements.append(.missingDecisionFrame(prefixEventCount: prefixEventCount))
  }
  return frames
}

private func verifyCommittedDecision(
  event: PlotterEpisodeEvent,
  index: Int,
  state: PlotterEpisodeState,
  frame: PlotterEpisodeReplayDecisionFrame,
  executable: PlotterEpisodeReplayExecutableAdapter,
  disagreements: inout [PlotterEpisodeReplayDisagreement]
) {
  let requestID: IntentRequestID
  let intent: PlotterIntent
  switch event.payload {
  case let .intentAccepted(value):
    requestID = value.requestID
    intent = value.intent
  case let .intentRefused(value):
    requestID = value.requestID
    intent = value.intent
  case .effectProgressed, .effectResult, .observationRecorded, .measurementRecorded,
       .evidenceDecided, .outcomeRecorded, .assessmentRecorded:
    return
  }
  guard frame.candidates.contains(where: {
    $0.requestID == requestID && $0.intent == intent
  }) else {
    disagreements.append(.committedIntentMissingCandidate(index: index, requestID: requestID))
    return
  }

  let decision = executable.evaluate(
    requestID: requestID,
    intent: intent,
    state: state,
    capabilityFacts: frame.capabilityFacts
  )
  let matches: Bool
  switch (event.payload, decision) {
  case let (.intentAccepted(recorded), .admitted(context, requirements)):
    matches = context.requestID == recorded.requestID
      && context.comparedStateRevision == recorded.comparedStateRevision
      && context.comparedCapabilityFacts == recorded.comparedCapabilityFacts
      && requirements == recorded.satisfiedRequirements
  case let (.intentRefused(recorded), .refused(context, requirements)):
    matches = context.requestID == recorded.requestID
      && context.comparedStateRevision == recorded.comparedStateRevision
      && context.comparedCapabilityFacts == recorded.comparedCapabilityFacts
      && requirements == recorded.failedRequirements
  default:
    matches = false
  }
  if !matches {
    disagreements.append(.committedIntentDecisionMismatch(index: index, requestID: requestID))
  }
}

private func pinDisagreements(
  definition: PlotterEpisodeDefinition,
  manifest: PlotterEpisodeManifest,
  executableDescriptor: PlotterEpisodeReplayExecutableDescriptor,
  recordedEffectRevisions: [PlotterEpisodeRecordedEffectRevision],
  initialState: PlotterEpisodeState,
  journal: EpisodeJournal<PlotterEpisodeEventPayload>
) -> [PlotterEpisodeReplayDisagreement] {
  var disagreements: [PlotterEpisodeReplayDisagreement] = []
  if manifest.definitionID != definition.id {
    disagreements.append(.definitionID(expected: manifest.definitionID, actual: definition.id))
  }
  if manifest.definitionRevision != definition.revision {
    disagreements.append(.definitionRevision(
      expected: manifest.definitionRevision,
      actual: definition.revision
    ))
  }
  let revisionPins: [(
    PlotterEpisodeReplayRevisionComponent,
    EpisodeRevisionIdentifier,
    EpisodeRevisionIdentifier
  )] = [
    (.domain, manifest.domainRevision, executableDescriptor.domainRevision),
    (.evaluator, manifest.evaluatorRevision, executableDescriptor.evaluatorRevision),
    (.reducer, manifest.reducerRevision, executableDescriptor.reducerRevision),
    (
      .stateSchema,
      manifest.schemaRevisions.state,
      executableDescriptor.schemaRevisions.state
    ),
    (
      .eventSchema,
      manifest.schemaRevisions.event,
      executableDescriptor.schemaRevisions.event
    ),
    (
      .journalSchema,
      manifest.schemaRevisions.journal,
      executableDescriptor.schemaRevisions.journal
    ),
    (.build, manifest.buildRevision, executableDescriptor.buildRevision),
    (
      .canonicalDigest,
      executableDescriptor.canonicalDigestRevision,
      PlotterEpisodeCanonicalDigestV1.revision
    ),
  ]
  for (component, expected, actual) in revisionPins where expected != actual {
    disagreements.append(.executableRevision(
      component: component,
      expected: expected,
      actual: actual
    ))
  }

  var boundEffectIDs = Set<EpisodeEffectID>()
  for effectBinding in recordedEffectRevisions
  where !boundEffectIDs.insert(effectBinding.effectID).inserted {
    disagreements.append(.duplicateRecordedEffectRevision(effectBinding.effectID))
  }
  for event in journal.events {
    guard case let .intentAccepted(accepted) = event.payload,
          case let .externalEffect(effectID, _) = accepted.execution else { continue }
    if !boundEffectIDs.contains(effectID) {
      disagreements.append(.missingRecordedEffectRevision(effectID))
    }
  }
  let initial = definition.initialContext
  let domain = manifest.domainManifest
  if initial.drawing != domain.drawing
    || initial.executionPlan != domain.executionPlan
    || initial.calibration != domain.calibration
    || initial.paperRevision != domain.paperRevision
    || initial.environmentRevision != domain.environmentRevision {
    disagreements.append(.definitionInitialContextDoesNotMatchDomainManifest)
  }
  if journal.manifestID != manifest.id {
    disagreements.append(.journalManifestID(expected: manifest.id, actual: journal.manifestID))
  }
  if journal.episodeID != manifest.episodeID {
    disagreements.append(.journalEpisodeID(expected: manifest.episodeID, actual: journal.episodeID))
  }
  if journal.initialStateRevision != initial.initialStateRevision {
    disagreements.append(.journalInitialRevision(
      expected: initial.initialStateRevision,
      actual: journal.initialStateRevision
    ))
  }
  if initialState.episodeID != manifest.episodeID {
    disagreements.append(.initialStateEpisodeID(
      expected: manifest.episodeID,
      actual: initialState.episodeID
    ))
  }
  if initialState.revision != initial.initialStateRevision {
    disagreements.append(.initialStateRevision(
      expected: initial.initialStateRevision,
      actual: initialState.revision
    ))
  }
  if initialState.canonicalDigest != initial.initialStateDigest {
    disagreements.append(.initialStateRecordedDigest(
      expected: initial.initialStateDigest,
      actual: initialState.canonicalDigest
    ))
  }
  if initialState.permittedIntentFamilies != definition.permittedIntentGrammar.permittedFamilies {
    disagreements.append(.initialStateIntentGrammar)
  }
  if initialState.currentPlanRevisionID != manifest.domainManifest.executionPlan?.revisionID {
    disagreements.append(.initialStatePlanRevision)
  }
  return disagreements
}

private func reconstructPrefix(
  eventCount: Int,
  initialState: PlotterEpisodeState,
  journal: EpisodeJournal<PlotterEpisodeEventPayload>,
  executable: PlotterEpisodeReplayExecutableAdapter,
  recordedEffectRevisions: [PlotterEpisodeRecordedEffectRevision],
  recording: EpisodeRecordingSnapshot?,
  decisionFrame: PlotterEpisodeReplayDecisionFrame,
  decisionTimeline: [Int: PlotterEpisodeReplayDecisionFrame]
) -> PrefixReconstruction? {
  guard let prefixJournal = try? EpisodeJournal(
    manifestID: journal.manifestID,
    episodeID: journal.episodeID,
    initialStateRevision: journal.initialStateRevision,
    events: Array(journal.events.prefix(eventCount))
  ) else { return nil }

  var state = initialState
  var verifications: [PlotterEpisodeReplayEventVerification] = []
  var effects: [EpisodeEffectID: MutableEffectReplay] = [:]
  var effectOrder: [EpisodeEffectID] = []
  var disagreements: [PlotterEpisodeReplayDisagreement] = []

  for (index, event) in prefixJournal.events.enumerated() {
    if state.episodeID != event.episodeID {
      disagreements.append(.reducerInputEpisode(
        index: index,
        expected: event.episodeID,
        actual: state.episodeID
      ))
    }
    if state.revision != event.preStateRevision {
      disagreements.append(.reducerInputRevision(
        index: index,
        expected: event.preStateRevision,
        actual: state.revision
      ))
    }

    let reduction = executable.reduce(state: state, event: event)
    if reduction.state.episodeID != event.episodeID {
      disagreements.append(.reducerOutputEpisode(
        index: index,
        expected: event.episodeID,
        actual: reduction.state.episodeID
      ))
    }
    if reduction.state.revision != event.postStateRevision {
      disagreements.append(.reducerOutputRevision(
        index: index,
        expected: event.postStateRevision,
        actual: reduction.state.revision
      ))
    }
    if reduction.state.canonicalDigest != event.postStateDigest {
      disagreements.append(.reducerOutputDigest(
        index: index,
        expected: event.postStateDigest,
        actual: reduction.state.canonicalDigest
      ))
    }
    let independentDigest: EpisodeStateDigest
    if let digest = try? executable.canonicalDigest(reduction.state) {
      independentDigest = digest
      if digest != event.postStateDigest {
        disagreements.append(.reducerOutputDigest(
          index: index,
          expected: event.postStateDigest,
          actual: digest
        ))
      }
    } else {
      independentDigest = EpisodeStateDigest(rawValue: "unavailable")
      disagreements.append(.canonicalStateDigestUnavailable(index: index))
    }

    let expectedSequence = EpisodeEventSequence(rawValue: UInt64(index))
    let expectedPostRevision = EpisodeStateRevision(
      rawValue: event.preStateRevision.rawValue + 1
    )
    verifications.append(PlotterEpisodeReplayEventVerification(
      eventID: event.id,
      index: index,
      expectedSequence: expectedSequence,
      actualSequence: event.sequence,
      expectedPreStateRevision: state.revision,
      actualPreStateRevision: event.preStateRevision,
      expectedPostStateRevision: expectedPostRevision,
      actualPostStateRevision: event.postStateRevision,
      recordedPostStateDigest: event.postStateDigest,
      reducerPostStateDigest: reduction.state.canonicalDigest,
      independentlyComputedPostStateDigest: independentDigest
    ))

    if case let .intentAccepted(accepted) = event.payload {
      for effect in reduction.effects {
        let effectID = effect.context.effectID
        guard effects[effectID] == nil else {
          disagreements.append(.duplicateEffectEmission(effectID))
          continue
        }
        guard let effectRevision = recordedEffectRevisions.first(where: {
          $0.effectID == effectID
        })?.revision else {
          disagreements.append(.missingRecordedEffectRevision(effectID))
          continue
        }
        let operationBinding = PlotterEpisodeReplayOperationBinding(
          episodeID: effect.context.episodeID,
          requestID: effect.context.requestID,
          intent: accepted.intent,
          effectID: effectID,
          effectRevision: effectRevision,
          correlationID: event.correlationID,
          environment: effect.context.environment
        )
        effects[effectID] = MutableEffectReplay(
          effect: effect,
          intent: accepted.intent,
          operationBinding: operationBinding,
          emittedByEventID: event.id,
          emittedAtSequence: event.sequence,
          startEvidence: [],
          settledByEventID: nil
        )
        effectOrder.append(effectID)
      }
    }

    if let frame = decisionTimeline[index] {
      verifyCommittedDecision(
        event: event,
        index: index,
        state: state,
        frame: frame,
        executable: executable,
        disagreements: &disagreements
      )
    }

    switch event.payload {
    case let .effectProgressed(progress):
      if var effect = effects[progress.effectID] {
        if matches(progress: progress, effect: effect) {
          if let settledByEventID = effect.settledByEventID {
            disagreements.append(.effectProgressAfterSettlement(
              index: index,
              effectID: progress.effectID,
              settledByEventID: settledByEventID
            ))
          } else {
            let alreadyStartedByProgress = effect.startEvidence.contains { evidence in
              guard case .journalProgress = evidence else { return false }
              return true
            }
            if !alreadyStartedByProgress {
              effect.startEvidence.append(.journalProgress(eventID: event.id))
            }
            effects[progress.effectID] = effect
          }
        } else {
          disagreements.append(.effectProgressIdentityMismatch(
            index: index,
            effectID: progress.effectID
          ))
        }
      } else {
        disagreements.append(.effectProgressWithoutEmission(
          index: index,
          effectID: progress.effectID
        ))
      }
    case let .effectResult(result):
      let context = result.context
      if var effect = effects[context.effectID] {
        if matches(result: context, effect: effect) {
          if let firstSettledByEventID = effect.settledByEventID {
            disagreements.append(.multipleEffectResults(
              index: index,
              effectID: context.effectID,
              firstSettledByEventID: firstSettledByEventID
            ))
          } else {
            effect.settledByEventID = event.id
            effects[context.effectID] = effect
          }
        } else {
          disagreements.append(.effectResultIdentityMismatch(
            index: index,
            effectID: context.effectID
          ))
        }
      } else {
        disagreements.append(.effectResultWithoutEmission(
          index: index,
          effectID: context.effectID
        ))
      }
    case .intentAccepted, .intentRefused, .observationRecorded, .measurementRecorded,
         .evidenceDecided, .outcomeRecorded, .assessmentRecorded:
      break
    }
    state = reduction.state
  }

  if let recording {
    for entry in recording.entries {
      let exactMatches = effects.filter {
        $0.value.operationBinding.matches(entry.provenance)
      }
      guard exactMatches.count == 1,
            let effectID = exactMatches.first?.key,
            var effect = effects[effectID],
            let evidence = startEvidence(for: entry) else { continue }
      if !effect.startEvidence.contains(evidence) {
        effect.startEvidence.append(evidence)
        effects[effectID] = effect
      }
    }
  }

  let replayedEffects = effectOrder.compactMap { effects[$0]?.value }
  let possible = replayedEffects.filter { $0.wasStarted && !$0.isSettled }
  let classification: PlotterEpisodeReplayPhysicalEffectClassification = possible.isEmpty
    ? .noStartedUnsettledEffect
    : .possiblePhysicalEffect(possible)
  let resume: PlotterEpisodeReplayResumeDisposition = possible.isEmpty
    ? .neverResume(.unboundReplayNeverExecutesEffects)
    : .neverResume(.possiblePhysicalEffect(possible.map { $0.effect.context.effectID }))

  let availabilities = decisionFrame.candidates.map { candidate in
    PlotterIntentAvailability(
      intent: candidate.intent,
      decision: executable.evaluate(
        requestID: candidate.requestID,
        intent: candidate.intent,
        state: state,
        capabilityFacts: decisionFrame.capabilityFacts
      )
    )
  }

  return PrefixReconstruction(
    prefix: PlotterEpisodeReplayPrefix(
      eventCount: eventCount,
      state: state,
      intentAvailabilities: availabilities,
      eventVerifications: verifications,
      emittedEffects: replayedEffects,
      physicalEffectClassification: classification,
      resumeDisposition: resume
    ),
    disagreements: unique(disagreements)
  )
}

private func matches(
  progress: PlotterEffectProgress,
  effect: MutableEffectReplay
) -> Bool {
  let context = effect.effect.context
  return progress.episodeID == context.episodeID
    && progress.requestID == context.requestID
    && progress.intent == effect.intent
    && progress.effectID == context.effectID
    && progress.effectRevision == effect.operationBinding.effectRevision
    && progress.environment == context.environment
}

private func matches(
  result: PlotterEffectResultContext,
  effect: MutableEffectReplay
) -> Bool {
  let context = effect.effect.context
  return result.episodeID == context.episodeID
    && result.requestID == context.requestID
    && result.intent == effect.intent
    && result.effectID == context.effectID
    && result.effectRevision == effect.operationBinding.effectRevision
    && result.environment == context.environment
}

private func startEvidence(
  for entry: EpisodeRecordingEntry
) -> PlotterEpisodeReplayEffectStartEvidence? {
  switch entry.record {
  case .controller(.invocation):
    return .controllerInvocation(recordingSequence: entry.sequence)
  case let .camera(.lifecycle(lifecycle)):
    switch lifecycle {
    case .startRequested, .reconfigurationRequested, .stopRequested:
      return .cameraLifecycleRequest(recordingSequence: entry.sequence)
    case .started, .reconfigured, .stopped, .failed:
      return nil
    }
  case .controller(.completion), .camera(.frameReference), .runLedgerDiagnostic:
    return nil
  }
}

private extension PlotterEpisodeReplayOperationBinding {
  var recordingProvenance: EpisodeRecordingProvenance {
    EpisodeRecordingProvenance(
      episodeID: episodeID,
      intentRequestID: requestID,
      effectID: effectID,
      correlationID: correlationID,
      environment: environment
    )
  }

  func matches(_ provenance: EpisodeRecordingProvenance) -> Bool {
    provenance == recordingProvenance
  }
}

private func operationBindings(
  journal: EpisodeJournal<PlotterEpisodeEventPayload>,
  recordedEffectRevisions: [PlotterEpisodeRecordedEffectRevision]
) -> [PlotterEpisodeReplayOperationBinding] {
  journal.events.compactMap { event in
    guard case let .intentAccepted(accepted) = event.payload,
          case let .externalEffect(effectID, environment) = accepted.execution,
          let effectRevision = recordedEffectRevisions.first(where: {
            $0.effectID == effectID
          })?.revision else { return nil }
    return PlotterEpisodeReplayOperationBinding(
      episodeID: event.episodeID,
      requestID: accepted.requestID,
      intent: accepted.intent,
      effectID: effectID,
      effectRevision: effectRevision,
      correlationID: event.correlationID,
      environment: environment
    )
  }
}

private func provenanceDisagreements(
  operationBindings: [PlotterEpisodeReplayOperationBinding],
  recording: EpisodeRecordingSnapshot
) -> [PlotterEpisodeReplayDisagreement] {
  var disagreements: [PlotterEpisodeReplayDisagreement] = []
  var invocationProvenance: [ControllerInvocationID: (UInt64, EpisodeRecordingProvenance)] = [:]
  for entry in recording.entries {
    let provenance = entry.provenance
    let exactOperationMatches = operationBindings.filter { $0.matches(provenance) }
    if exactOperationMatches.isEmpty,
       let effectID = provenance.effectID,
       let expected = operationBindings.first(where: { $0.effectID == effectID }) {
      disagreements.append(.recordingOperationBindingMismatch(
        recordingSequence: entry.sequence,
        expected: expected,
        actual: provenance
      ))
    }
    if startEvidence(for: entry) != nil, exactOperationMatches.count != 1 {
      disagreements.append(.recordingStartUnattributed(recordingSequence: entry.sequence))
    }
    switch entry.record {
    case let .controller(.invocation(invocation)):
      invocationProvenance[invocation.id] = (entry.sequence, provenance)
    case let .controller(.completion(completion)):
      if let (sequence, invocation) = invocationProvenance[completion.invocationID],
         invocation != provenance {
        disagreements.append(.controllerCompletionProvenanceMismatch(
          invocationID: completion.invocationID,
          invocationSequence: sequence,
          completionSequence: entry.sequence
        ))
      }
    case .camera, .runLedgerDiagnostic:
      break
    }
  }
  return unique(disagreements)
}

private func controllerReplaySteps(
  _ recording: EpisodeRecordingSnapshot
) -> [ControllerReplayStep] {
  recording.entries.compactMap { entry in
    guard case let .controller(record) = entry.record else { return nil }
    return ControllerReplayStep(
      sourceRecordingSequence: entry.sequence,
      replayOffsetNanoseconds: entry.monotonicOffsetNanoseconds,
      provenance: entry.provenance,
      record: record
    )
  }
}

private func apply(
  _ scenario: ControllerReplayScenario,
  to source: [ControllerReplayStep]?
) -> ControllerReplayScenarioResult {
  guard let source, !source.isEmpty else {
    return refused(scenario, source: [], reason: .controllerSourceAbsent)
  }
  if let violation = controllerReplayScheduleViolation(in: source) {
    return refused(
      scenario,
      source: source,
      reason: .invalidTransformedSchedule(violation)
    )
  }
  var delayedInvocations = Set<ControllerInvocationID>()
  var terminalInvocationCounts: [ControllerInvocationID: Int] = [:]
  for perturbation in scenario.perturbations {
    switch perturbation {
    case let .completionDelay(invocationID, _):
      delayedInvocations.insert(invocationID)
    case let .timeout(invocationID, _), let .cancellation(invocationID, _):
      terminalInvocationCounts[invocationID, default: 0] += 1
    case .legalReadFragmentation:
      break
    }
  }
  if let invocationID = terminalInvocationCounts.keys.sorted(by: {
    $0.rawValue.uuidString < $1.rawValue.uuidString
  }).first(where: { terminalInvocationCounts[$0, default: 0] > 1 }) {
    return refused(
      scenario,
      source: source,
      reason: .conflictingTerminalPerturbations(invocationID)
    )
  }
  let terminalInvocations = Set(terminalInvocationCounts.keys)
  if let invocationID = delayedInvocations.intersection(terminalInvocations).sorted(by: {
    $0.rawValue.uuidString < $1.rawValue.uuidString
  }).first {
    return refused(
      scenario,
      source: source,
      reason: .conflictingTimingPerturbations(invocationID)
    )
  }
  var candidate = source
  var terminalOverrides = Set<ControllerInvocationID>()
  for perturbation in scenario.perturbations {
    let refusal: ControllerReplayPerturbationRefusal?
    switch perturbation {
    case let .legalReadFragmentation(maximumChunkByteCount):
      guard maximumChunkByteCount > 0 else {
        return refused(
          scenario,
          source: source,
          reason: .invalidMaximumChunkByteCount(maximumChunkByteCount)
        )
      }
      guard containsRecordedReadTraffic(in: source) else {
        return refused(scenario, source: source, reason: .readTrafficAbsent)
      }
      candidate = candidate.map {
        replacingReadChunks(in: $0, maximumByteCount: maximumChunkByteCount)
      }
      refusal = nil
    case let .completionDelay(invocationID, additionalNanoseconds):
      refusal = delay(
        invocationID: invocationID,
        additionalNanoseconds: additionalNanoseconds,
        steps: &candidate
      )
    case let .timeout(invocationID, boundary):
      if !terminalOverrides.insert(invocationID).inserted {
        refusal = .conflictingTerminalPerturbations(invocationID)
      } else {
        refusal = replaceReadCompletionAtBoundary(
          invocationID: invocationID,
          atNanosecondsAfterInvocation: boundary,
          kind: .timeout,
          steps: &candidate
        )
      }
    case let .cancellation(invocationID, boundary):
      if !terminalOverrides.insert(invocationID).inserted {
        refusal = .conflictingTerminalPerturbations(invocationID)
      } else {
        refusal = replaceReadCompletionAtBoundary(
          invocationID: invocationID,
          atNanosecondsAfterInvocation: boundary,
          kind: .cancelled,
          steps: &candidate
        )
      }
    }
    if let refusal { return refused(scenario, source: source, reason: refusal) }
  }
  if let violation = controllerReplayScheduleViolation(in: candidate) {
    return refused(
      scenario,
      source: source,
      reason: .invalidTransformedSchedule(violation)
    )
  }
  return ControllerReplayScenarioResult(
    id: scenario.id,
    declaredPerturbations: scenario.perturbations,
    disposition: .applied,
    steps: candidate
  )
}

private struct ControllerReplayInvocationSchedule {
  let index: Int
  let replayOffsetNanoseconds: UInt64
  let operation: ControllerOperationInvocation
}

private func controllerReplayScheduleViolation(
  in steps: [ControllerReplayStep]
) -> ControllerReplayScheduleCausalityViolation? {
  var previousSourceSequence: UInt64?
  var previousReplayOffset: UInt64?
  var invocations: [ControllerInvocationID: ControllerReplayInvocationSchedule] = [:]

  for (index, step) in steps.enumerated() {
    if let previousSourceSequence,
       step.sourceRecordingSequence <= previousSourceSequence {
      return .sourceSequenceRegression(step.sourceRecordingSequence)
    }
    if let previousReplayOffset,
       step.replayOffsetNanoseconds < previousReplayOffset {
      return .replayOffsetRegression(step.sourceRecordingSequence)
    }
    previousSourceSequence = step.sourceRecordingSequence
    previousReplayOffset = step.replayOffsetNanoseconds

    guard case let .invocation(invocation) = step.record else { continue }
    guard invocations[invocation.id] == nil else {
      return .duplicateInvocation(invocation.id)
    }
    guard controllerReplayInvocationIsValid(invocation) else {
      return .invalidInvocation(invocation.id)
    }
    invocations[invocation.id] = ControllerReplayInvocationSchedule(
      index: index,
      replayOffsetNanoseconds: step.replayOffsetNanoseconds,
      operation: invocation.operation
    )
  }

  var completions = Set<ControllerInvocationID>()
  for (index, step) in steps.enumerated() {
    guard case let .completion(completion) = step.record else { continue }
    guard let invocation = invocations[completion.invocationID] else {
      return .completionWithoutInvocation(completion.invocationID)
    }
    guard invocation.index < index,
          invocation.replayOffsetNanoseconds <= step.replayOffsetNanoseconds else {
      return .completionPrecedesInvocation(completion.invocationID)
    }
    guard completions.insert(completion.invocationID).inserted else {
      return .duplicateCompletion(completion.invocationID)
    }

    let deadline: UInt64?
    if case let .timedRead(parameters) = invocation.operation {
      let (value, overflow) = invocation.replayOffsetNanoseconds.addingReportingOverflow(
        parameters.timeoutNanoseconds
      )
      guard !overflow else {
        return .timedReadDeadlineOverflow(completion.invocationID)
      }
      guard step.replayOffsetNanoseconds <= value else {
        return .timedReadDeadlineExceeded(completion.invocationID)
      }
      deadline = value
    } else {
      deadline = nil
    }

    if let violation = controllerReplayCompletionViolation(
      completion,
      invocation: invocation,
      completionOffsetNanoseconds: step.replayOffsetNanoseconds,
      deadlineNanoseconds: deadline
    ) {
      return violation
    }
  }
  return nil
}

private func controllerReplayInvocationIsValid(_ invocation: ControllerInvocation) -> Bool {
  switch invocation.operation {
  case let .open(parameters):
    return !parameters.endpoint.isEmpty
      && parameters.baudRate > 0
      && parameters.dataBits > 0
      && parameters.stopBits > 0
  case let .timedRead(parameters):
    return parameters.maximumByteCount > 0
  case .close, .discardInput, .rawWrite:
    return true
  }
}

private func controllerReplayCompletionViolation(
  _ completion: ControllerCompletion,
  invocation: ControllerReplayInvocationSchedule,
  completionOffsetNanoseconds: UInt64,
  deadlineNanoseconds: UInt64?
) -> ControllerReplayScheduleCausalityViolation? {
  switch (invocation.operation, completion.outcome) {
  case (.open, .succeeded(.open)), (.close, .succeeded(.close)):
    return nil
  case let (.discardInput, .succeeded(.discardInput(discardedByteCount))):
    guard discardedByteCount >= 0 else {
      return .invalidPartialResult(completion.invocationID)
    }
    return nil
  case let (.rawWrite(parameters), .succeeded(.rawWrite(writtenByteCount))):
    guard writtenByteCount == parameters.bytes.count else {
      return .invalidPartialResult(completion.invocationID)
    }
    return nil
  case let (.timedRead(parameters), .succeeded(.timedRead(chunks, _))):
    guard let deadlineNanoseconds else {
      return .operationOutcomeMismatch(completion.invocationID)
    }
    return controllerReplayReadChunksViolation(
      chunks,
      invocationID: completion.invocationID,
      maximumByteCount: parameters.maximumByteCount,
      invocationOffsetNanoseconds: invocation.replayOffsetNanoseconds,
      completionOffsetNanoseconds: completionOffsetNanoseconds,
      deadlineNanoseconds: deadlineNanoseconds,
      expectedByteCount: nil
    )
  case let (_, .failed(failure)):
    guard failure.partialByteCount >= 0 else {
      return .invalidPartialResult(completion.invocationID)
    }
    switch invocation.operation {
    case .open, .close, .discardInput:
      guard failure.partialByteCount == 0, failure.partialReadChunks.isEmpty else {
        return .invalidPartialResult(completion.invocationID)
      }
      return nil
    case let .rawWrite(parameters):
      guard failure.partialByteCount <= parameters.bytes.count,
            failure.partialReadChunks.isEmpty else {
        return .invalidPartialResult(completion.invocationID)
      }
      return nil
    case let .timedRead(parameters):
      guard let deadlineNanoseconds else {
        return .operationOutcomeMismatch(completion.invocationID)
      }
      return controllerReplayReadChunksViolation(
        failure.partialReadChunks,
        invocationID: completion.invocationID,
        maximumByteCount: parameters.maximumByteCount,
        invocationOffsetNanoseconds: invocation.replayOffsetNanoseconds,
        completionOffsetNanoseconds: completionOffsetNanoseconds,
        deadlineNanoseconds: deadlineNanoseconds,
        expectedByteCount: failure.partialByteCount
      )
    }
  default:
    return .operationOutcomeMismatch(completion.invocationID)
  }
}

private func controllerReplayReadChunksViolation(
  _ chunks: [ControllerReadChunk],
  invocationID: ControllerInvocationID,
  maximumByteCount: Int,
  invocationOffsetNanoseconds: UInt64,
  completionOffsetNanoseconds: UInt64,
  deadlineNanoseconds: UInt64,
  expectedByteCount: Int?
) -> ControllerReplayScheduleCausalityViolation? {
  var previousOffset: UInt64?
  var byteCount = 0
  for chunk in chunks {
    guard !chunk.bytes.isEmpty else { return .emptyReadChunk(invocationID) }
    guard chunk.monotonicOffsetNanoseconds >= invocationOffsetNanoseconds else {
      return .readChunkPrecedesInvocation(invocationID)
    }
    guard chunk.monotonicOffsetNanoseconds <= completionOffsetNanoseconds else {
      return .readChunkAfterCompletion(invocationID)
    }
    guard chunk.monotonicOffsetNanoseconds <= deadlineNanoseconds else {
      return .timedReadDeadlineExceeded(invocationID)
    }
    if let previousOffset,
       chunk.monotonicOffsetNanoseconds < previousOffset {
      return .readChunkOffsetRegression(invocationID)
    }
    previousOffset = chunk.monotonicOffsetNanoseconds
    let (nextByteCount, overflow) = byteCount.addingReportingOverflow(chunk.bytes.count)
    guard !overflow, nextByteCount <= maximumByteCount else {
      return .maximumReadByteCountExceeded(invocationID)
    }
    byteCount = nextByteCount
  }
  if let expectedByteCount, byteCount != expectedByteCount {
    return .invalidPartialResult(invocationID)
  }
  return nil
}

private func refused(
  _ scenario: ControllerReplayScenario,
  source: [ControllerReplayStep],
  reason: ControllerReplayPerturbationRefusal
) -> ControllerReplayScenarioResult {
  ControllerReplayScenarioResult(
    id: scenario.id,
    declaredPerturbations: scenario.perturbations,
    disposition: .refused([reason]),
    steps: source
  )
}

private func delay(
  invocationID: ControllerInvocationID,
  additionalNanoseconds: UInt64,
  steps: inout [ControllerReplayStep]
) -> ControllerReplayPerturbationRefusal? {
  guard let invocationIndex = steps.firstIndex(where: { step in
    guard case let .invocation(invocation) = step.record else { return false }
    return invocation.id == invocationID
  }) else { return .unknownInvocation(invocationID) }
  guard let completionIndex = steps.firstIndex(where: { step in
    guard case let .completion(completion) = step.record else { return false }
    return completion.invocationID == invocationID
  }) else { return .completionMissing(invocationID) }
  let invocationStep = steps[invocationIndex]
  let completionStep = steps[completionIndex]
  guard case let .invocation(invocation) = invocationStep.record,
        case let .timedRead(parameters) = invocation.operation else {
    return .operationIsNotTimedRead(invocationID)
  }
  let (delayedCompletion, overflow) = completionStep.replayOffsetNanoseconds
    .addingReportingOverflow(additionalNanoseconds)
  guard !overflow else { return .timestampOverflow(invocationID) }
  let (deadline, deadlineOverflow) = invocationStep.replayOffsetNanoseconds
    .addingReportingOverflow(parameters.timeoutNanoseconds)
  guard !deadlineOverflow else { return .timestampOverflow(invocationID) }
  guard delayedCompletion <= deadline else {
    return .delayedCompletionExceedsReadTimeout(invocationID)
  }
  var adjusted = steps
  for index in completionIndex..<adjusted.count {
    let step = adjusted[index]
    let (offset, overflow) = step.replayOffsetNanoseconds.addingReportingOverflow(
      additionalNanoseconds
    )
    guard !overflow,
          let record = shiftingReadChunks(
            in: step.record,
            by: additionalNanoseconds
          ) else { return .timestampOverflow(invocationID) }
    adjusted[index] = ControllerReplayStep(
      sourceRecordingSequence: step.sourceRecordingSequence,
      replayOffsetNanoseconds: offset,
      provenance: step.provenance,
      record: record
    )
  }
  steps = adjusted
  return nil
}

private func replaceReadCompletionAtBoundary(
  invocationID: ControllerInvocationID,
  atNanosecondsAfterInvocation boundaryOffset: UInt64,
  kind: ControllerErrorKind,
  steps: inout [ControllerReplayStep]
) -> ControllerReplayPerturbationRefusal? {
  guard let invocationIndex = steps.firstIndex(where: { step in
    guard case let .invocation(invocation) = step.record else { return false }
    return invocation.id == invocationID
  }) else { return .unknownInvocation(invocationID) }
  let invocationStep = steps[invocationIndex]
  guard case let .invocation(invocation) = invocationStep.record,
        case let .timedRead(parameters) = invocation.operation else {
    return .operationIsNotTimedRead(invocationID)
  }
  guard boundaryOffset <= parameters.timeoutNanoseconds else {
    return .boundaryExceedsReadTimeout(invocationID)
  }
  let (boundary, overflow) = invocationStep.replayOffsetNanoseconds.addingReportingOverflow(
    boundaryOffset
  )
  guard !overflow else { return .timestampOverflow(invocationID) }
  guard let index = steps.firstIndex(where: { step in
    guard case let .completion(completion) = step.record else { return false }
    return completion.invocationID == invocationID
  }) else { return .completionMissing(invocationID) }
  guard index > invocationIndex else {
    return .boundaryWouldReorderControllerTraffic(invocationID)
  }
  let step = steps[index]
  guard boundary <= step.replayOffsetNanoseconds else {
    return .boundaryAfterCompletion(invocationID)
  }
  guard case let .completion(recordedCompletion) = step.record,
        case let .succeeded(.timedRead(chunks, _)) = recordedCompletion.outcome else {
    return .completionIsNotSuccessfulRead(invocationID)
  }
  if steps[(invocationIndex + 1)..<index].contains(where: {
    $0.replayOffsetNanoseconds > boundary
  }) {
    return .boundaryWouldReorderControllerTraffic(invocationID)
  }
  let retainedChunks = chunks.filter { $0.monotonicOffsetNanoseconds <= boundary }
  let completion = ControllerCompletion(
    invocationID: invocationID,
    outcome: .failed(ControllerOperationFailure(
      kind: kind,
      partialByteCount: retainedChunks.reduce(0) { $0 + $1.bytes.count },
      partialReadChunks: retainedChunks
    ))
  )
  var adjusted = steps
  adjusted[index] = ControllerReplayStep(
    sourceRecordingSequence: step.sourceRecordingSequence,
    replayOffsetNanoseconds: boundary,
    provenance: step.provenance,
    record: .completion(completion)
  )
  let shift = step.replayOffsetNanoseconds - boundary
  if shift > 0 {
    for downstreamIndex in adjusted.indices where downstreamIndex > index {
      let downstream = adjusted[downstreamIndex]
      guard downstream.replayOffsetNanoseconds >= shift,
            let record = subtractingReadChunks(in: downstream.record, by: shift) else {
        return .timestampUnderflow(invocationID)
      }
      adjusted[downstreamIndex] = ControllerReplayStep(
        sourceRecordingSequence: downstream.sourceRecordingSequence,
        replayOffsetNanoseconds: downstream.replayOffsetNanoseconds - shift,
        provenance: downstream.provenance,
        record: record
      )
    }
  }
  steps = adjusted
  return nil
}

private func containsRecordedReadTraffic(in steps: [ControllerReplayStep]) -> Bool {
  steps.contains { step in
    guard case let .completion(completion) = step.record else { return false }
    switch completion.outcome {
    case let .succeeded(.timedRead(chunks, _)):
      return !chunks.isEmpty
    case let .failed(failure):
      return !failure.partialReadChunks.isEmpty
    case .succeeded:
      return false
    }
  }
}

private func replacingReadChunks(
  in step: ControllerReplayStep,
  maximumByteCount: Int
) -> ControllerReplayStep {
  ControllerReplayStep(
    sourceRecordingSequence: step.sourceRecordingSequence,
    replayOffsetNanoseconds: step.replayOffsetNanoseconds,
    provenance: step.provenance,
    record: mapReadChunks(in: step.record) { chunks in
      chunks.flatMap { fragment($0, maximumByteCount: maximumByteCount) }
    }
  )
}

private func shiftingReadChunks(
  in record: ControllerTranscriptRecord,
  by delay: UInt64
) -> ControllerTranscriptRecord? {
  var overflow = false
  let shifted = mapReadChunks(in: record) { chunks in
    chunks.map { chunk in
      let (offset, didOverflow) = chunk.monotonicOffsetNanoseconds.addingReportingOverflow(delay)
      overflow = overflow || didOverflow
      return ControllerReadChunk(bytes: chunk.bytes, monotonicOffsetNanoseconds: offset)
    }
  }
  return overflow ? nil : shifted
}

private func subtractingReadChunks(
  in record: ControllerTranscriptRecord,
  by shift: UInt64
) -> ControllerTranscriptRecord? {
  var underflow = false
  let shifted = mapReadChunks(in: record) { chunks in
    chunks.map { chunk in
      guard chunk.monotonicOffsetNanoseconds >= shift else {
        underflow = true
        return chunk
      }
      return ControllerReadChunk(
        bytes: chunk.bytes,
        monotonicOffsetNanoseconds: chunk.monotonicOffsetNanoseconds - shift
      )
    }
  }
  return underflow ? nil : shifted
}

private func mapReadChunks(
  in record: ControllerTranscriptRecord,
  transform: ([ControllerReadChunk]) -> [ControllerReadChunk]
) -> ControllerTranscriptRecord {
  guard case let .completion(completion) = record else { return record }
  let outcome: ControllerOperationOutcome
  switch completion.outcome {
  case let .succeeded(.timedRead(chunks, timedOut)):
    outcome = .succeeded(.timedRead(chunks: transform(chunks), timedOut: timedOut))
  case let .failed(failure):
    let chunks = transform(failure.partialReadChunks)
    outcome = .failed(ControllerOperationFailure(
      kind: failure.kind,
      systemCode: failure.systemCode,
      diagnostic: failure.diagnostic,
      partialByteCount: chunks.reduce(0) { $0 + $1.bytes.count },
      partialReadChunks: chunks
    ))
  case .succeeded:
    outcome = completion.outcome
  }
  return .completion(ControllerCompletion(
    invocationID: completion.invocationID,
    outcome: outcome
  ))
}

private func fragment(
  _ chunk: ControllerReadChunk,
  maximumByteCount: Int
) -> [ControllerReadChunk] {
  guard chunk.bytes.count > maximumByteCount else { return [chunk] }
  var fragments: [ControllerReadChunk] = []
  var remaining = chunk.bytes
  while !remaining.isEmpty {
    let bytes = Data(remaining.prefix(maximumByteCount))
    fragments.append(ControllerReadChunk(
      bytes: bytes,
      monotonicOffsetNanoseconds: chunk.monotonicOffsetNanoseconds
    ))
    remaining.removeFirst(bytes.count)
  }
  return fragments
}

private func unique<Value: Hashable>(_ values: [Value]) -> [Value] {
  var seen = Set<Value>()
  return values.filter { seen.insert($0).inserted }
}
