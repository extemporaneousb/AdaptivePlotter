import EpisodeCore
import Foundation
import PlotterEpisodeModel
import PlotterModel
import PlotterRuntime

public struct PlotterDrawingRunPlan: Hashable, Sendable {
  public let identity: PlotterDrawingRunPlanIdentity
  public let program: DrawingProgram
  public let placementID: UUID
  public let plan: ExecutionPlanRevision
  public let evidenceRole: BorderValidationEvidenceRole
  public let paperCoverage: PaperCoverageObservation
  public let registration: TipCameraRegistration

  public init(
    draftRevision: PlotterDrawingDraftRevision,
    program: DrawingProgram,
    placementID: UUID,
    plan: ExecutionPlanRevision,
    evidenceRole: BorderValidationEvidenceRole,
    paperCoverage: PaperCoverageObservation,
    registration: TipCameraRegistration
  ) {
    precondition(plan.revisionID.rawValue == plan.contentHash)
    self.program = program
    self.placementID = placementID
    self.plan = plan
    self.evidenceRole = evidenceRole
    self.paperCoverage = paperCoverage
    self.registration = registration
    identity = PlotterDrawingRunPlanIdentity(
      draftRevision: draftRevision,
      programID: program.id,
      programContentHash: program.contentHash,
      placementID: placementID,
      planRevisionID: plan.revisionID,
      planContentHash: plan.contentHash,
      evidenceRole: evidenceRole,
      paperCoverageObservationID: paperCoverage.id.rawValue,
      tipRegistrationRevisionID: registration.acceptedRevisionID.rawValue
    )
  }
}

public struct PlotterDrawingRunExternalFacts: Hashable, Sendable {
  public let environment: PlotterEnvironment
  public let interactiveLearningIsComplete: Bool
  public let plan: PlotterDrawingRunPlan?
  public let paperCoverageIsCurrent: Bool
  public let displayedFrame: DisplayedFrame?
  public let interpreter: RunInterpreterSnapshot?
  public let penActuationProfile: PenActuationProfile

  public init(
    environment: PlotterEnvironment,
    interactiveLearningIsComplete: Bool,
    plan: PlotterDrawingRunPlan?,
    paperCoverageIsCurrent: Bool,
    displayedFrame: DisplayedFrame?,
    interpreter: RunInterpreterSnapshot?,
    penActuationProfile: PenActuationProfile
  ) {
    self.environment = environment
    self.interactiveLearningIsComplete = interactiveLearningIsComplete
    self.plan = plan
    self.paperCoverageIsCurrent = paperCoverageIsCurrent
    self.displayedFrame = displayedFrame
    self.interpreter = interpreter
    self.penActuationProfile = penActuationProfile
  }
}

/// Supplies current application facts only. It cannot mutate draft, controller,
/// camera, Vision, or evidence authority.
public protocol PlotterDrawingRunFactSource: Sendable {
  func drawingRunFacts(for environment: PlotterEnvironment) async
    -> PlotterDrawingRunExternalFacts
}

/// Nominal bridge to the retained RunInterpreter/MachineController stack.
public protocol PlotterDrawingRunInterpreterPort: Sendable {
  func snapshot() async -> RunInterpreterSnapshot?
  func normalizePenUp(profile: PenActuationProfile) async -> PenOutcome
  func travelToObservationPosition(_ request: RelativeJogRequest) async -> MotionOutcome
  func beginDrawingPlan(_ request: DrawingPlanRequest) async -> DrawingPlanAdmission
  func requestStop(_ intent: JogCancelIntent) async -> JogCancelOutcome
}

/// Nominal bridge to the retained CameraCapture owner.
public protocol PlotterDrawingRunCameraPort: Sendable {
  func captureFrame(newerThan captureNanoseconds: UInt64) async throws -> DisplayedFrame
}

/// Nominal bridge to the retained VisionWorker measurement owner.
public protocol PlotterDrawingRunVisionPort: Sendable {
  func observePlannedDrawingInk(
    _ request: PlannedDrawingObservationRequest
  ) async -> PlannedDrawingObservationOutcome
}

/// Nominal bridge to the retained checksummed append-only evidence store.
public protocol PlotterDrawingRunEvidencePort: Sendable {
  func append(_ record: DrawingRunEvidenceRecord) async throws
    -> DrawingRunEvidenceArchive
}

public enum PlotterDrawingRunPhase: Hashable, Sendable {
  case idle
  case validating
  case normalizingPenUp
  case positioningForBaseline
  case capturingBaseline
  case executingPlan
  case capturingPostFrame
  case observingInk
  case appendingEvidence
  case terminal
}

public enum PlotterDrawingRunNoRedrawState: Hashable, Sendable {
  case clear
  case archiveUnavailable(detail: String)
  case newPlanRequired(runID: RunID, planIdentity: PlotterDrawingRunPlanIdentity)
  case planMayContainInk(runID: RunID, planIdentity: PlotterDrawingRunPlanIdentity)
}

public enum PlotterDrawingRunEvidenceArchiveAvailability: Hashable, Sendable {
  case awaitingLoad
  case available(revision: UInt64)
  case rejected(detail: String)
}

public enum PlotterDrawingRunEvidenceArchiveRestoreDisposition: Hashable, Sendable {
  case available(DrawingRunEvidenceArchive)
  case rejected(detail: String)
}

public struct PlotterDrawingRunEvidenceArchiveRestoreResult: Hashable, Sendable {
  public let disposition: PlotterDrawingRunEvidenceArchiveRestoreDisposition
  public let snapshot: PlotterDrawingRunSnapshot
}

public enum PlotterDrawingRunReviewState: Hashable, Sendable {
  case livePreview
  case available(runID: RunID, frame: PlotterExactFrameReference)
  case pinned(runID: RunID, frame: PlotterExactFrameReference)
}

public enum PlotterDrawingRunEvidencePersistence: Hashable, Sendable {
  case none
  case appending(DrawingEvidenceRecordID)
  case persisted(recordID: DrawingEvidenceRecordID, archiveRevision: UInt64)
  case failed(
    recordID: DrawingEvidenceRecordID,
    recoveryCapabilityID: PlotterDrawingRunPublicationRecoveryCapabilityID,
    detail: String
  )
}

public enum PlotterDrawingRunTerminalDisposition: Hashable, Sendable {
  case refused
  case cancelled
  case ambiguous
  case possibleInk
  case nonAttributable
  case visionRejected
  case succeeded
  /// The proposed terminal fact is retained, but no successful result is
  /// published until its exact record is durably appended.
  case publicationIncomplete
}

public struct PlotterDrawingRunTerminal: Hashable, Sendable {
  public let runID: RunID
  public let planIdentity: PlotterDrawingRunPlanIdentity
  public let disposition: PlotterDrawingRunTerminalDisposition
  public let record: DrawingRunEvidenceRecord

  public init(
    runID: RunID,
    planIdentity: PlotterDrawingRunPlanIdentity,
    disposition: PlotterDrawingRunTerminalDisposition,
    record: DrawingRunEvidenceRecord
  ) {
    self.runID = runID
    self.planIdentity = planIdentity
    self.disposition = disposition
    self.record = record
  }
}

public struct PlotterDrawingRunSnapshot: Hashable, Sendable {
  public let projection: PlotterDrawingRunProjectionReference
  public let phase: PlotterDrawingRunPhase
  public let activeRunID: RunID?
  public let planIdentity: PlotterDrawingRunPlanIdentity?
  public let progress: DrawingPlanProgressSnapshot?
  public let stopCapabilityID: PlotterDrawingRunStopCapabilityID?
  public let terminal: PlotterDrawingRunTerminal?
  public let noRedraw: PlotterDrawingRunNoRedrawState
  public let baselineFrame: DisplayedFrame?
  public let postFrame: DisplayedFrame?
  public let observation: DrawingRunObservationOutcome?
  public let presentationObservation: PlannedDrawingObservation?
  public let evidencePersistence: PlotterDrawingRunEvidencePersistence
  public let evidenceArchiveAvailability: PlotterDrawingRunEvidenceArchiveAvailability
  public let review: PlotterDrawingRunReviewState
  public let lastRefusal: PlotterDrawingRunRefusal?
  public let physicalEvidenceClaimed: Bool
}

public enum PlotterDrawingRunSubmissionDisposition: Hashable, Sendable {
  case applied
  case refused(PlotterDrawingRunRefusal)
}

public struct PlotterDrawingRunSubmissionResult: Hashable, Sendable {
  public let disposition: PlotterDrawingRunSubmissionDisposition
  public let snapshot: PlotterDrawingRunSnapshot
}

@MainActor
public protocol PlotterDrawingRunIntentSink: AnyObject {
  func submitDrawingRun(_ submission: PlotterDrawingRunSubmission) async
}

public actor PlotterDrawingRunRuntime {
  private struct ActiveRun: Sendable {
    let runID: RunID
    let requestID: UUID
    let plan: PlotterDrawingRunPlan
    let capturedEffectFacts: CapturedEffectFacts
    let stopCapabilityID: PlotterDrawingRunStopCapabilityID
    var cancellationRequested = false
  }

  private struct CapturedEffectFacts: Hashable, Sendable {
    let environment: PlotterEnvironment
    let interactiveLearningIsComplete: Bool
    let plan: PlotterDrawingRunPlan?
    let paperCoverageIsCurrent: Bool
    let penActuationProfile: PenActuationProfile

    init(_ facts: PlotterDrawingRunExternalFacts) {
      environment = facts.environment
      interactiveLearningIsComplete = facts.interactiveLearningIsComplete
      plan = facts.plan
      paperCoverageIsCurrent = facts.paperCoverageIsCurrent
      penActuationProfile = facts.penActuationProfile
    }
  }

  private struct PublicationRecoveryOwner: Hashable, Sendable {
    let capabilityID: PlotterDrawingRunPublicationRecoveryCapabilityID
    let recordID: DrawingEvidenceRecordID
    let runID: RunID
  }

  private struct PreEffectRefusal: Sendable {
    let currentFacts: PlotterDrawingRunExternalFacts
    let owner: EpisodeAuthorityID
    let reason: PlotterDrawingRunRefusalReason
    let remedy: PlotterDrawingRunRemedy
  }

  private struct SourceState: Sendable {
    var revision = PlotterDrawingRunRevision(rawValue: 0)
    var phase = PlotterDrawingRunPhase.idle
    var active: ActiveRun?
    var progress: DrawingPlanProgressSnapshot?
    var terminal: PlotterDrawingRunTerminal?
    var noRedraw = PlotterDrawingRunNoRedrawState.archiveUnavailable(
      detail: "Drawing evidence archive has not been loaded."
    )
    var blockedPlanHashes = Set<Digest>()
    var baselineFrame: DisplayedFrame?
    var postFrame: DisplayedFrame?
    var observation: DrawingRunObservationOutcome?
    var presentationObservation: PlannedDrawingObservation?
    var evidencePersistence = PlotterDrawingRunEvidencePersistence.none
    var evidenceArchiveAvailability = PlotterDrawingRunEvidenceArchiveAvailability.awaitingLoad
    var pendingRecord: DrawingRunEvidenceRecord?
    var publicationRecoveryOwner: PublicationRecoveryOwner?
    var review = PlotterDrawingRunReviewState.livePreview
    var lastRefusal: PlotterDrawingRunRefusal?
    var currentPlanIdentity: PlotterDrawingRunPlanIdentity?
  }

  private enum Authority {
    static let run = EpisodeAuthorityID(rawValue: "PlotterDrawingRunRuntime")
    static let draft = EpisodeAuthorityID(rawValue: "PlotterDrawingDraftRuntime")
    static let learning = EpisodeAuthorityID(rawValue: "PlotterLearningAuthority")
    static let paper = EpisodeAuthorityID(rawValue: "PlotterPaperCoverageAuthority")
    static let interpreter = EpisodeAuthorityID(rawValue: "RunInterpreter")
    static let evidence = EpisodeAuthorityID(rawValue: "DrawingRunEvidenceStore")
  }

  private let facts: any PlotterDrawingRunFactSource
  private let interpreter: any PlotterDrawingRunInterpreterPort
  private let camera: any PlotterDrawingRunCameraPort
  private let vision: any PlotterDrawingRunVisionPort
  private let evidence: any PlotterDrawingRunEvidencePort
  private let clock: any RuntimeClock
  private var states: [PlotterEnvironment: SourceState] = [:]
  private var admissionClosed = false
  private var snapshotContinuations:
    [PlotterEnvironment: [UUID: AsyncStream<PlotterDrawingRunSnapshot>.Continuation]] = [:]
  private var quiescenceContinuations:
    [PlotterEnvironment: [UUID: CheckedContinuation<Void, Never>]] = [:]

  public init(
    facts: any PlotterDrawingRunFactSource,
    interpreter: any PlotterDrawingRunInterpreterPort,
    camera: any PlotterDrawingRunCameraPort,
    vision: any PlotterDrawingRunVisionPort,
    evidence: any PlotterDrawingRunEvidencePort,
    clock: any RuntimeClock = SystemRuntimeClock()
  ) {
    self.facts = facts
    self.interpreter = interpreter
    self.camera = camera
    self.vision = vision
    self.evidence = evidence
    self.clock = clock
  }

  public func synchronize(
    environment: PlotterEnvironment
  ) async -> PlotterDrawingRunSnapshot {
    let currentFacts = await facts.drawingRunFacts(for: environment)
    var state = states[environment] ?? SourceState()
    if case .appending = state.evidencePersistence {
      return snapshot(state, environment: environment)
    }
    state.currentPlanIdentity = currentFacts.plan?.identity
    if state.active == nil, state.terminal == nil { state.phase = .idle }
    states[environment] = state
    return publish(state, environment: environment)
  }

  public func restoreNoRedrawTruth(
    from archive: DrawingRunEvidenceArchive,
    paper: PaperRevisionContext,
    environment: PlotterEnvironment
  ) -> PlotterDrawingRunSnapshot {
    var state = states[environment] ?? SourceState()
    guard state.active == nil else {
      return snapshot(state, environment: environment)
    }
    if case .appending = state.evidencePersistence {
      return snapshot(state, environment: environment)
    }
    state.blockedPlanHashes = Set(
      archive.records.lazy
        .filter { $0.paper == paper && $0.executionFrontiers.commandedStrokeCount > 0 }
        .map(\.plan.contentHash)
    )
    state.evidenceArchiveAvailability = .available(revision: archive.revision)
    if case .archiveUnavailable = state.noRedraw {
      state.noRedraw = .clear
    }
    advance(&state)
    states[environment] = state
    return publish(state, environment: environment)
  }

  public func restoreNoRedrawTruth(
    from loadResult: DrawingRunEvidenceStoreLoadResult,
    paper: PaperRevisionContext,
    environment: PlotterEnvironment
  ) -> PlotterDrawingRunEvidenceArchiveRestoreResult {
    switch loadResult {
    case .absent:
      let archive = DrawingRunEvidenceArchive()
      return PlotterDrawingRunEvidenceArchiveRestoreResult(
        disposition: .available(archive),
        snapshot: restoreNoRedrawTruth(
          from: archive,
          paper: paper,
          environment: environment
        )
      )
    case .loaded(let archive):
      return PlotterDrawingRunEvidenceArchiveRestoreResult(
        disposition: .available(archive),
        snapshot: restoreNoRedrawTruth(
          from: archive,
          paper: paper,
          environment: environment
        )
      )
    case .rejected(let rejection):
      let detail = String(describing: rejection)
      var state = states[environment] ?? SourceState()
      if case .appending = state.evidencePersistence {
        return PlotterDrawingRunEvidenceArchiveRestoreResult(
          disposition: .rejected(detail: detail),
          snapshot: snapshot(state, environment: environment)
        )
      }
      state.evidenceArchiveAvailability = .rejected(detail: detail)
      state.noRedraw = .archiveUnavailable(detail: detail)
      state.lastRefusal = nil
      advance(&state)
      states[environment] = state
      let value = publish(state, environment: environment)
      return PlotterDrawingRunEvidenceArchiveRestoreResult(
        disposition: .rejected(detail: detail),
        snapshot: value
      )
    }
  }

  public func beginShutdown(
    environment: PlotterEnvironment
  ) async -> PlotterDrawingRunSnapshot {
    admissionClosed = true
    var state = states[environment] ?? SourceState()
    if var active = state.active {
      active.cancellationRequested = true
      state.active = active
      advance(&state)
      states[environment] = state
      _ = publish(state, environment: environment)
      if state.phase == .positioningForBaseline || state.phase == .executingPlan {
        _ = await interpreter.requestStop(.shutdown)
      }
    }
    await waitForQuiescence(environment: environment)
    return snapshot(states[environment] ?? state, environment: environment)
  }

  public func snapshots(
    environment: PlotterEnvironment
  ) -> AsyncStream<PlotterDrawingRunSnapshot> {
    let subscriptionID = UUID()
    let pair = AsyncStream<PlotterDrawingRunSnapshot>.makeStream()
    snapshotContinuations[environment, default: [:]][subscriptionID] = pair.continuation
    pair.continuation.yield(
      snapshot(states[environment] ?? SourceState(), environment: environment)
    )
    pair.continuation.onTermination = { [weak self] _ in
      Task { await self?.removeSnapshotContinuation(subscriptionID, environment: environment) }
    }
    return pair.stream
  }

  public func snapshot(
    environment: PlotterEnvironment
  ) async -> PlotterDrawingRunSnapshot {
    var state = states[environment] ?? SourceState()
    if state.phase == .executingPlan {
      state.progress = await interpreter.snapshot()?.drawingPlanProgress ?? state.progress
      states[environment] = state
      _ = publish(state, environment: environment)
    }
    return snapshot(state, environment: environment)
  }

  public func submit(
    _ submission: PlotterDrawingRunSubmission
  ) async -> PlotterDrawingRunSubmissionResult {
    let environment = submission.projection.environment
    let existingState = states[environment] ?? SourceState()
    guard !admissionClosed else {
      return refuse(
        submission,
        state: existingState,
        owner: Authority.run,
        reason: .admissionClosed,
        remedy: .restartApplication
      )
    }
    let currentFacts = await facts.drawingRunFacts(for: environment)
    guard !admissionClosed else {
      return refuse(
        submission,
        state: states[environment] ?? existingState,
        owner: Authority.run,
        reason: .admissionClosed,
        remedy: .restartApplication
      )
    }
    var state = states[environment] ?? SourceState()
    if case .appending = state.evidencePersistence {
      // Publication owns the exact projection until its result is committed.
    } else {
      state.currentPlanIdentity = currentFacts.plan?.identity
    }
    states[environment] = state
    _ = publish(state, environment: environment)
    guard submission.projection == projection(state, environment: environment) else {
      return refuse(
        submission,
        state: state,
        owner: Authority.run,
        reason: .staleProjection,
        remedy: .useCurrentProjection
      )
    }

    switch submission.intent {
    case .start:
      return await start(submission, currentFacts: currentFacts, state: state)
    case .stop(let capabilityID):
      return await stop(submission, capabilityID: capabilityID, state: state)
    case .pinReview(let runID):
      return changeReview(submission, runID: runID, pin: true, state: state)
    case .unpinReview(let runID):
      return changeReview(submission, runID: runID, pin: false, state: state)
    case .beginNewRun(let runID):
      return beginNewRun(submission, runID: runID, state: state)
    case .recoverPublication(let capabilityID):
      return await recoverPublication(
        submission,
        capabilityID: capabilityID,
        state: state
      )
    }
  }

  private func start(
    _ submission: PlotterDrawingRunSubmission,
    currentFacts: PlotterDrawingRunExternalFacts,
    state initialState: SourceState
  ) async -> PlotterDrawingRunSubmissionResult {
    let environment = currentFacts.environment
    guard environment == .live else {
      return refuse(
        submission,
        state: initialState,
        owner: Authority.run,
        reason: .simulatedRunIsNonphysical,
        remedy: .switchToLiveSource
      )
    }
    guard initialState.active == nil else {
      return refuse(
        submission,
        state: initialState,
        owner: Authority.run,
        reason: .activeRunOwnsWorkflow,
        remedy: .waitForActiveRun
      )
    }
    guard initialState.terminal == nil else {
      return refuse(
        submission,
        state: initialState,
        owner: Authority.run,
        reason: .terminalRequiresNewRunHandoff,
        remedy: .beginNewPlan
      )
    }
    guard case .available = initialState.evidenceArchiveAvailability else {
      return refuse(
        submission,
        state: initialState,
        owner: Authority.evidence,
        reason: .evidenceArchiveUnavailable,
        remedy: .restoreEvidenceArchive
      )
    }
    guard currentFacts.interactiveLearningIsComplete else {
      return refuse(
        submission,
        state: initialState,
        owner: Authority.learning,
        reason: .learningIncomplete,
        remedy: .restoreLearningAuthority
      )
    }
    guard let plan = currentFacts.plan,
      submission.projection.planIdentity == plan.identity
    else {
      return refuse(
        submission,
        state: initialState,
        owner: Authority.draft,
        reason: .exactPlanUnavailable,
        remedy: .reviewExactPlan
      )
    }
    guard currentFacts.paperCoverageIsCurrent else {
      return refuse(
        submission,
        state: initialState,
        owner: Authority.paper,
        reason: .paperCoverageNotCurrent,
        remedy: .assertCurrentPaperCoverage
      )
    }
    guard !initialState.blockedPlanHashes.contains(plan.plan.contentHash) else {
      return refuse(
        submission,
        state: initialState,
        owner: Authority.run,
        reason: .planMayAlreadyContainInk,
        remedy: .movePlanAwayFromPossibleInk
      )
    }
    guard Self.controllerIsReady(await interpreter.snapshot()), !admissionClosed else {
      return refuse(
        submission,
        state: initialState,
        owner: admissionClosed ? Authority.run : Authority.interpreter,
        reason: admissionClosed ? .admissionClosed : .controllerUnavailable,
        remedy: admissionClosed ? .restartApplication : .restoreControllerReadiness
      )
    }

    let runID = RunID()
    let active = ActiveRun(
      runID: runID,
      requestID: submission.requestID.rawValue,
      plan: plan,
      capturedEffectFacts: CapturedEffectFacts(currentFacts),
      stopCapabilityID: PlotterDrawingRunStopCapabilityID()
    )
    var state = initialState
    state.active = active
    state.phase = .validating
    state.lastRefusal = nil
    state.currentPlanIdentity = plan.identity
    state.baselineFrame = nil
    state.postFrame = nil
    state.observation = nil
    state.presentationObservation = nil
    state.progress = nil
    state.evidencePersistence = .none
    state.review = .livePreview
    advance(&state)
    states[environment] = state
    _ = publish(state, environment: environment)

    if let failure = await preEffectRefusal(for: active) {
      return refuseBeforeFirstEffect(
        submission,
        active: active,
        failure: failure
      )
    }
    await run(active, initialFacts: currentFacts)
    let settled = states[environment] ?? state
    return PlotterDrawingRunSubmissionResult(
      disposition: .applied,
      snapshot: snapshot(settled, environment: environment)
    )
  }

  private func run(
    _ owner: ActiveRun,
    initialFacts: PlotterDrawingRunExternalFacts
  ) async {
    let environment = initialFacts.environment
    setPhase(.normalizingPenUp, owner: owner, environment: environment)
    let penOutcome = await interpreter.normalizePenUp(
      profile: owner.capturedEffectFacts.penActuationProfile
    )
    guard isCurrent(owner, environment: environment) else { return }
    if admissionClosed || cancellationWasRequested(owner, environment: environment) {
      await finishBeforePlan(
        owner,
        execution: .cancelled(
          reason: admissionClosed ? "Application shutdown" : "Operator Stop"
        ),
        evidenceDisposition: .cancelled,
        observation: .notAttempted(.executionCancelledBeforeObservation)
      )
      return
    }
    guard case .commandedAndSettled(command: .raise, commandedState: .up) = penOutcome else {
      let disposition: DrawingRunExecutionDisposition
      let evidenceDisposition: BorderValidationEvidenceDisposition
      if case .ambiguous = penOutcome {
        disposition = .ambiguous(reason: String(describing: penOutcome))
        evidenceDisposition = .ambiguous
      } else {
        disposition = .refused(reason: String(describing: penOutcome))
        evidenceDisposition = .refused
      }
      await finishBeforePlan(
        owner,
        execution: disposition,
        evidenceDisposition: evidenceDisposition,
        observation: .notAttempted(.requestRefused)
      )
      return
    }

    guard await revalidate(owner, requiringControllerReady: true) else {
      await finishBeforePlan(
        owner,
        execution: .refused(reason: "Run facts changed after Pen Up normalization."),
        evidenceDisposition: .refused,
        observation: .notAttempted(.requestRefused)
      )
      return
    }
    guard let targetPoint = owner.plan.plan.strokes.last?.path.points.last else {
      await finishBeforePlan(
        owner,
        execution: .refused(reason: "The exact plan has no observation point."),
        evidenceDisposition: .refused,
        observation: .notAttempted(.requestRefused)
      )
      return
    }
    let target = MachinePosition(point: targetPoint)
    guard let interpreterSnapshot = await interpreter.snapshot(),
      let currentPosition = interpreterSnapshot.machine.position,
      !admissionClosed,
      isCurrent(owner, environment: environment)
    else {
      await finishBeforePlan(
        owner,
        execution: .refused(reason: "Current controller MPos is unavailable."),
        evidenceDisposition: .refused,
        observation: .notAttempted(.requestRefused)
      )
      return
    }
    var observationPosition = currentPosition
    if !MachinePositionAcceptancePolicy.accepts(currentPosition, target: target) {
      setPhase(.positioningForBaseline, owner: owner, environment: environment)
      do {
        let request = RelativeJogRequest(
          delta: try currentPosition.point.vector(to: targetPoint),
          feedMMPerMinute: PlotterMotionThroughput.applicationXYFeedMMPerMinute
        )
        guard await revalidate(owner, requiringControllerReady: true) else {
          await finishBeforePlan(
            owner,
            execution: .cancelled(reason: "Stop, shutdown, or stale facts before travel."),
            evidenceDisposition: .cancelled,
            observation: .notAttempted(.executionCancelledBeforeObservation)
          )
          return
        }
        let travel = await interpreter.travelToObservationPosition(request)
        guard isCurrent(owner, environment: environment) else { return }
        if admissionClosed || cancellationWasRequested(owner, environment: environment) {
          await finishBeforePlan(
            owner,
            execution: .cancelled(reason: "Stop or shutdown during observation travel."),
            evidenceDisposition: .cancelled,
            observation: .notAttempted(.executionCancelledBeforeObservation)
          )
          return
        }
        switch travel {
        case .acceptedThenCompleted(let finalPosition):
          guard MachinePositionAcceptancePolicy.accepts(finalPosition, target: target) else {
            await finishBeforePlan(
              owner,
              execution: .ambiguous(reason: "Observation travel settled outside target."),
              evidenceDisposition: .ambiguous,
              observation: .notAttempted(.executionFailedBeforeObservation)
            )
            return
          }
          observationPosition = finalPosition
        case .cancelled:
          await finishBeforePlan(
            owner,
            execution: .cancelled(reason: "Operator Stop"),
            evidenceDisposition: .cancelled,
            observation: .notAttempted(.executionCancelledBeforeObservation)
          )
          return
        case .refused(let reason):
          await finishBeforePlan(
            owner,
            execution: .refused(reason: String(describing: reason)),
            evidenceDisposition: .refused,
            observation: .notAttempted(.requestRefused)
          )
          return
        case .ambiguous(let reason):
          await finishBeforePlan(
            owner,
            execution: .ambiguous(reason: String(describing: reason)),
            evidenceDisposition: .ambiguous,
            observation: .notAttempted(.executionFailedBeforeObservation)
          )
          return
        }
      } catch {
        await finishBeforePlan(
          owner,
          execution: .refused(reason: String(describing: error)),
          evidenceDisposition: .refused,
          observation: .notAttempted(.requestRefused)
        )
        return
      }
    }

    guard await revalidate(owner, requiringControllerReady: true) else {
      await finishBeforePlan(
        owner,
        execution: .refused(reason: "Run facts changed before baseline capture."),
        evidenceDisposition: .refused,
        observation: .notAttempted(.frameEvidenceUnavailable)
      )
      return
    }
    setPhase(.capturingBaseline, owner: owner, environment: environment)
    let baseline: DisplayedFrame
    do {
      baseline = try await camera.captureFrame(
        newerThan: initialFacts.displayedFrame?.frame.captureNanoseconds ?? 0
      )
      guard !admissionClosed, isCurrent(owner, environment: environment) else {
        await finishBeforePlan(
          owner,
          execution: .cancelled(reason: "Application shutdown during baseline capture."),
          evidenceDisposition: .cancelled,
          observation: .notAttempted(.frameEvidenceUnavailable)
        )
        return
      }
    } catch {
      await finishBeforePlan(
        owner,
        execution: .refused(reason: "Baseline capture failed: \(error)"),
        evidenceDisposition: .refused,
        observation: .notAttempted(.frameEvidenceUnavailable)
      )
      return
    }
    update(owner, environment: environment) { state in
      state.baselineFrame = baseline
    }

    guard !cancellationWasRequested(owner, environment: environment),
      await revalidate(owner, requiringControllerReady: true)
    else {
      await finishBeforePlan(
        owner,
        execution: .cancelled(reason: "Operator Stop or stale facts before execution."),
        evidenceDisposition: .cancelled,
        observation: .notAttempted(.executionCancelledBeforeObservation)
      )
      return
    }

    let request: DrawingPlanRequest
    do {
      request = try DrawingPlanRequest(
        operationID: DrawingPlanOperationID(rawValue: owner.requestID),
        plan: owner.plan.plan,
        travelFeedMMPerMinute: PlotterMotionThroughput.applicationXYFeedMMPerMinute,
        drawingFeedMMPerMinute: PlotterMotionThroughput.applicationXYFeedMMPerMinute,
        penActuationProfile: owner.capturedEffectFacts.penActuationProfile
      )
    } catch {
      await finishBeforePlan(
        owner,
        execution: .refused(reason: String(describing: error)),
        evidenceDisposition: .refused,
        observation: .notAttempted(.requestRefused)
      )
      return
    }

    setPhase(.executingPlan, owner: owner, environment: environment)
    guard await revalidate(owner, requiringControllerReady: true) else {
      await finishBeforePlan(
        owner,
        execution: .cancelled(reason: "Stop, shutdown, or stale facts before plan admission."),
        evidenceDisposition: .cancelled,
        observation: .notAttempted(.executionCancelledBeforeObservation)
      )
      return
    }
    let admission = await interpreter.beginDrawingPlan(request)
    let outcome: DrawingPlanOutcome
    let frontier: DrawingRunRequestFrontier
    switch admission {
    case .admitted(let operation):
      frontier = .admitted
      outcome = await operation.outcome()
    case .rejected(let rejected):
      frontier = .validated
      outcome = rejected
    }
    guard isCurrent(owner, environment: environment) else { return }
    update(owner, environment: environment) { state in
      state.progress = outcome.progress
      state.active = state.active.map {
        var value = $0
        value.cancellationRequested = false
        return value
      }
      if outcome.progress.commandedStrokeCount > 0 {
        state.blockedPlanHashes.insert(owner.plan.plan.contentHash)
        state.noRedraw = .planMayContainInk(
          runID: owner.runID,
          planIdentity: owner.plan.identity
        )
      } else {
        state.noRedraw = .newPlanRequired(
          runID: owner.runID,
          planIdentity: owner.plan.identity
        )
      }
    }

    guard case .completed(_, let finalPosition) = outcome else {
      let mapped = Self.executionDisposition(for: outcome)
      await finish(
        owner,
        frontier: frontier,
        progress: outcome.progress,
        execution: mapped.execution,
        evidenceDisposition: mapped.evidence,
        observation: Self.notAttempted(for: outcome)
      )
      return
    }
    guard MachinePositionAcceptancePolicy.accepts(finalPosition, target: target) else {
      await finish(
        owner,
        frontier: frontier,
        progress: outcome.progress,
        execution: .ambiguous(reason: "Final MPos did not match the observation pose."),
        evidenceDisposition: .possibleInk,
        observation: .notAttempted(.executionFailedBeforeObservation)
      )
      return
    }

    guard await revalidate(owner, requiringControllerReady: false) else {
      await finish(
        owner,
        frontier: frontier,
        progress: outcome.progress,
        execution: .completed,
        evidenceDisposition: .visionUnclear,
        observation: .notAttempted(.frameEvidenceUnavailable)
      )
      return
    }

    setPhase(.capturingPostFrame, owner: owner, environment: environment)
    let post: DisplayedFrame
    do {
      post = try await camera.captureFrame(
        newerThan: baseline.frame.captureNanoseconds
      )
      guard !admissionClosed, isCurrent(owner, environment: environment) else {
        await finish(
          owner,
          frontier: frontier,
          progress: outcome.progress,
          execution: .completed,
          evidenceDisposition: .visionUnclear,
          observation: .notAttempted(.frameEvidenceUnavailable)
        )
        return
      }
      guard post.source == baseline.source,
        post.frame.captureNanoseconds > baseline.frame.captureNanoseconds
      else { throw DrawingRunEvidenceError.invalidFramePair }
    } catch {
      await finish(
        owner,
        frontier: frontier,
        progress: outcome.progress,
        execution: .completed,
        evidenceDisposition: .visionUnclear,
        observation: .notAttempted(.frameEvidenceUnavailable)
      )
      return
    }
    update(owner, environment: environment) { state in state.postFrame = post }

    let observation: DrawingRunObservationOutcome
    let evidenceDisposition: BorderValidationEvidenceDisposition
    do {
      let projection = try TipApplicabilityEvidencePolicy.project(
        paths: owner.plan.plan.strokes.map(\.path),
        using: owner.plan.registration
      )
      guard let intended = projection.attributableCameraPolylines else {
        await finish(
          owner,
          frontier: frontier,
          progress: outcome.progress,
          execution: .completed,
          evidenceDisposition: .nonAttributable,
          observation: .notAttempted(.projectionOutsideTipApplicability)
        )
        return
      }
      guard await revalidate(owner, requiringControllerReady: false) else {
        await finish(
          owner,
          frontier: frontier,
          progress: outcome.progress,
          execution: .completed,
          evidenceDisposition: .visionUnclear,
          observation: .notAttempted(.frameEvidenceUnavailable)
        )
        return
      }
      setPhase(.observingInk, owner: owner, environment: environment)
      let framePair = try DrawingObservationFramePair(
        source: post.source,
        baseline: ExactFrameProvenance(frame: baseline.frame),
        post: ExactFrameProvenance(frame: post.frame)
      )
      let result = await vision.observePlannedDrawingInk(
        PlannedDrawingObservationRequest(
          frames: framePair,
          localPreDrawingBaseline: SamePoseFrameSample(
            displayedFrame: baseline,
            controllerPosition: observationPosition
          ),
          postDrawing: SamePoseFrameSample(
            displayedFrame: post,
            controllerPosition: finalPosition
          ),
          region: Self.observationRegion(
            intended,
            frameWidth: post.frame.width,
            frameHeight: post.frame.height
          ),
          intendedCameraPolylines: intended,
          thresholds: InkPixelThresholds(minimumLuminanceDecrease: 20),
          controllerPositionToleranceMM: MachinePositionAcceptancePolicy.toleranceMM,
          alignmentSearchRadiusPixels: 8,
          maximumAlignmentShiftPixels: 4,
          maximumBackgroundMeanAbsoluteDifference: 12,
          observerRevision: try AlgorithmRevisionEvidence(
            component: "planned-drawing-observer",
            revision: VisionWorker.plannedDrawingObserverRevision
          ),
          additionalAlgorithmRevisions: [
            try AlgorithmRevisionEvidence(
              component: "drawing-plan-runner",
              revision: "checkpointed-multistroke-v1"
            )
          ]
        )
      )
      guard !admissionClosed, isCurrent(owner, environment: environment) else {
        await finish(
          owner,
          frontier: frontier,
          progress: outcome.progress,
          execution: .completed,
          evidenceDisposition: .visionUnclear,
          observation: .notAttempted(.frameEvidenceUnavailable)
        )
        return
      }
      switch result {
      case .observed(let value):
        update(owner, environment: environment) { state in
          state.presentationObservation = value
        }
        if owner.plan.evidenceRole != .ordinaryDrawing,
          value.evidence.residual == nil
        {
          observation = .rejected(try DrawingObservationRejection(
            frames: value.evidence.frames,
            reason: .correspondenceUnavailable,
            algorithmRevisions: value.evidence.algorithmRevisions
          ))
          evidenceDisposition = .visionUnclear
        } else {
          observation = .observed(value.evidence)
          evidenceDisposition = .attributable
        }
      case .rejected(let rejection):
        observation = .rejected(rejection)
        evidenceDisposition = .visionUnclear
      }
    } catch {
      observation = .notAttempted(.frameEvidenceUnavailable)
      evidenceDisposition = .visionUnclear
    }
    await finish(
      owner,
      frontier: frontier,
      progress: outcome.progress,
      execution: .completed,
      evidenceDisposition: evidenceDisposition,
      observation: observation
    )
  }

  private func finishBeforePlan(
    _ owner: ActiveRun,
    execution: DrawingRunExecutionDisposition,
    evidenceDisposition: BorderValidationEvidenceDisposition,
    observation: DrawingRunObservationOutcome
  ) async {
    await finish(
      owner,
      frontier: .validated,
      progress: nil,
      execution: execution,
      evidenceDisposition: evidenceDisposition,
      observation: observation
    )
  }

  private func finish(
    _ owner: ActiveRun,
    frontier: DrawingRunRequestFrontier,
    progress: DrawingPlanProgressSnapshot?,
    execution: DrawingRunExecutionDisposition,
    evidenceDisposition: BorderValidationEvidenceDisposition,
    observation: DrawingRunObservationOutcome
  ) async {
    let environment = PlotterEnvironment.live
    guard isCurrent(owner, environment: environment) else { return }
    do {
      let record = try makeRecord(
        owner: owner,
        frontier: frontier,
        progress: progress,
        execution: execution,
        evidenceDisposition: evidenceDisposition,
        observation: observation
      )
      if admissionClosed {
        retainPublicationIncomplete(
          record,
          owner: owner,
          detail: "Application shutdown closed drawing evidence publication."
        )
        return
      }
      update(owner, environment: environment) { state in
        state.phase = .appendingEvidence
        state.observation = observation
        state.pendingRecord = record
        state.evidencePersistence = .appending(record.recordID)
        state.noRedraw = progress?.commandedStrokeCount ?? 0 > 0
          ? .planMayContainInk(runID: owner.runID, planIdentity: owner.plan.identity)
          : .newPlanRequired(runID: owner.runID, planIdentity: owner.plan.identity)
      }
      await append(record, owner: owner, proposed: Self.terminalDisposition(
        execution: execution,
        evidence: evidenceDisposition
      ))
    } catch {
      // Record construction failure is itself terminal and non-retriable from
      // this API because no incomplete record is fabricated.
      update(owner, environment: environment) { state in
        state.phase = .terminal
        state.active = nil
        state.noRedraw = .newPlanRequired(
          runID: owner.runID,
          planIdentity: owner.plan.identity
        )
      }
    }
  }

  private func append(
    _ record: DrawingRunEvidenceRecord,
    owner: ActiveRun,
    proposed: PlotterDrawingRunTerminalDisposition
  ) async {
    let environment = PlotterEnvironment.live
    guard !admissionClosed else {
      retainPublicationIncomplete(
        record,
        owner: owner,
        detail: "Application shutdown closed drawing evidence publication."
      )
      return
    }
    do {
      let archive = try await evidence.append(record)
      guard isCurrent(owner, environment: environment) else { return }
      update(owner, environment: environment) { state in
        state.phase = .terminal
        state.active = nil
        state.pendingRecord = nil
        state.evidencePersistence = .persisted(
          recordID: record.recordID,
          archiveRevision: archive.revision
        )
        state.terminal = PlotterDrawingRunTerminal(
          runID: owner.runID,
          planIdentity: owner.plan.identity,
          disposition: proposed,
          record: record
        )
        if let post = state.postFrame {
          state.review = .available(
            runID: owner.runID,
            frame: post.plotterExactFrameReference
          )
        }
      }
    } catch {
      guard isCurrent(owner, environment: environment) else { return }
      let recoveryID = PlotterDrawingRunPublicationRecoveryCapabilityID()
      update(owner, environment: environment) { state in
        state.phase = .terminal
        state.active = nil
        state.pendingRecord = record
        state.evidencePersistence = .failed(
          recordID: record.recordID,
          recoveryCapabilityID: recoveryID,
          detail: String(describing: error)
        )
        state.terminal = PlotterDrawingRunTerminal(
          runID: owner.runID,
          planIdentity: owner.plan.identity,
          disposition: .publicationIncomplete,
          record: record
        )
        if let post = state.postFrame {
          state.review = .available(
            runID: owner.runID,
            frame: post.plotterExactFrameReference
          )
        }
      }
    }
  }

  private func stop(
    _ submission: PlotterDrawingRunSubmission,
    capabilityID: PlotterDrawingRunStopCapabilityID,
    state initialState: SourceState
  ) async -> PlotterDrawingRunSubmissionResult {
    let environment = submission.projection.environment
    guard var active = initialState.active,
      active.stopCapabilityID == capabilityID
    else {
      return refuse(
        submission,
        state: initialState,
        owner: Authority.run,
        reason: .stopCapabilityMismatch,
        remedy: .useExactStopCapability
      )
    }
    var state = initialState
    active.cancellationRequested = true
    state.active = active
    advance(&state)
    states[environment] = state
    _ = publish(state, environment: environment)
    if state.phase == .positioningForBaseline || state.phase == .executingPlan {
      _ = await interpreter.requestStop(.operatorStop)
    }
    return PlotterDrawingRunSubmissionResult(
      disposition: .applied,
      snapshot: snapshot(states[environment] ?? state, environment: environment)
    )
  }

  private func changeReview(
    _ submission: PlotterDrawingRunSubmission,
    runID: RunID,
    pin: Bool,
    state initialState: SourceState
  ) -> PlotterDrawingRunSubmissionResult {
    let environment = submission.projection.environment
    if case .appending = initialState.evidencePersistence {
      return refuse(
        submission,
        state: initialState,
        owner: Authority.evidence,
        reason: .evidencePublicationInProgress,
        remedy: .waitForEvidencePublication
      )
    }
    guard let terminal = initialState.terminal, terminal.runID == runID,
      let post = initialState.postFrame
    else {
      return refuse(
        submission,
        state: initialState,
        owner: Authority.run,
        reason: .reviewUnavailable,
        remedy: .retainExactPostFrame
      )
    }
    var state = initialState
    state.review = pin
      ? .pinned(runID: runID, frame: post.plotterExactFrameReference)
      : .available(runID: runID, frame: post.plotterExactFrameReference)
    advance(&state)
    states[environment] = state
    _ = publish(state, environment: environment)
    return PlotterDrawingRunSubmissionResult(
      disposition: .applied,
      snapshot: snapshot(state, environment: environment)
    )
  }

  private func beginNewRun(
    _ submission: PlotterDrawingRunSubmission,
    runID: RunID,
    state initialState: SourceState
  ) -> PlotterDrawingRunSubmissionResult {
    let environment = submission.projection.environment
    if case .appending = initialState.evidencePersistence {
      return refuse(
        submission,
        state: initialState,
        owner: Authority.evidence,
        reason: .evidencePublicationInProgress,
        remedy: .waitForEvidencePublication
      )
    }
    guard initialState.active == nil,
      let terminal = initialState.terminal,
      terminal.runID == runID
    else {
      return refuse(
        submission,
        state: initialState,
        owner: Authority.run,
        reason: .runIdentityMismatch,
        remedy: .useExactRunIdentity
      )
    }
    if case .failed = initialState.evidencePersistence {
      return refuse(
        submission,
        state: initialState,
        owner: Authority.evidence,
        reason: .terminalRequiresNewRunHandoff,
        remedy: .retryEvidencePublication
      )
    }
    var state = initialState
    state.phase = .idle
    state.terminal = nil
    state.baselineFrame = nil
    state.postFrame = nil
    state.observation = nil
    state.presentationObservation = nil
    state.progress = nil
    state.evidencePersistence = .none
    state.pendingRecord = nil
    state.review = .livePreview
    state.noRedraw = .clear
    advance(&state)
    states[environment] = state
    _ = publish(state, environment: environment)
    return PlotterDrawingRunSubmissionResult(
      disposition: .applied,
      snapshot: snapshot(state, environment: environment)
    )
  }

  private func recoverPublication(
    _ submission: PlotterDrawingRunSubmission,
    capabilityID: PlotterDrawingRunPublicationRecoveryCapabilityID,
    state initialState: SourceState
  ) async -> PlotterDrawingRunSubmissionResult {
    let environment = submission.projection.environment
    guard case .failed(_, let currentCapabilityID, _) = initialState.evidencePersistence,
      currentCapabilityID == capabilityID,
      let record = initialState.pendingRecord,
      let terminal = initialState.terminal,
      initialState.publicationRecoveryOwner == nil
    else {
      return refuse(
        submission,
        state: initialState,
        owner: Authority.evidence,
        reason: .publicationRecoveryMismatch,
        remedy: .retryEvidencePublication
      )
    }
    var state = initialState
    let recoveryOwner = PublicationRecoveryOwner(
      capabilityID: capabilityID,
      recordID: record.recordID,
      runID: terminal.runID
    )
    state.phase = .appendingEvidence
    state.evidencePersistence = .appending(record.recordID)
    state.publicationRecoveryOwner = recoveryOwner
    advance(&state)
    states[environment] = state
    _ = publish(state, environment: environment)
    do {
      guard !admissionClosed else {
        state.phase = .terminal
        state.evidencePersistence = .failed(
          recordID: record.recordID,
          recoveryCapabilityID: capabilityID,
          detail: "Application shutdown closed drawing evidence publication."
        )
        state.publicationRecoveryOwner = nil
        advance(&state)
        states[environment] = state
        _ = publish(state, environment: environment)
        return PlotterDrawingRunSubmissionResult(
          disposition: .applied,
          snapshot: snapshot(state, environment: environment)
        )
      }
      let archive = try await evidence.append(record)
      state = states[environment] ?? state
      guard publicationRecoveryIsCurrent(recoveryOwner, state: state) else {
        return refuse(
          submission,
          state: state,
          owner: Authority.evidence,
          reason: .publicationRecoveryMismatch,
          remedy: .retryEvidencePublication
        )
      }
      state.phase = .terminal
      state.pendingRecord = nil
      state.evidencePersistence = .persisted(
        recordID: record.recordID,
        archiveRevision: archive.revision
      )
      state.publicationRecoveryOwner = nil
      state.terminal = PlotterDrawingRunTerminal(
        runID: terminal.runID,
        planIdentity: terminal.planIdentity,
        disposition: Self.terminalDisposition(
          execution: record.executionDisposition,
          evidence: record.evidenceDisposition
        ),
        record: record
      )
      advance(&state)
      states[environment] = state
      _ = publish(state, environment: environment)
      return PlotterDrawingRunSubmissionResult(
        disposition: .applied,
        snapshot: snapshot(state, environment: environment)
      )
    } catch {
      state = states[environment] ?? state
      guard publicationRecoveryIsCurrent(recoveryOwner, state: state) else {
        return refuse(
          submission,
          state: state,
          owner: Authority.evidence,
          reason: .publicationRecoveryMismatch,
          remedy: .retryEvidencePublication
        )
      }
      state.phase = .terminal
      state.evidencePersistence = .failed(
        recordID: record.recordID,
        recoveryCapabilityID: capabilityID,
        detail: String(describing: error)
      )
      state.publicationRecoveryOwner = nil
      advance(&state)
      states[environment] = state
      _ = publish(state, environment: environment)
      return PlotterDrawingRunSubmissionResult(
        disposition: .applied,
        snapshot: snapshot(state, environment: environment)
      )
    }
  }

  private func publicationRecoveryIsCurrent(
    _ owner: PublicationRecoveryOwner,
    state: SourceState
  ) -> Bool {
    guard state.publicationRecoveryOwner == owner,
      state.pendingRecord?.recordID == owner.recordID,
      state.terminal?.runID == owner.runID,
      case .appending(let recordID) = state.evidencePersistence
    else { return false }
    return recordID == owner.recordID
  }

  private func retainPublicationIncomplete(
    _ record: DrawingRunEvidenceRecord,
    owner: ActiveRun,
    detail: String
  ) {
    let recoveryID = PlotterDrawingRunPublicationRecoveryCapabilityID()
    update(owner, environment: .live) { state in
      state.phase = .terminal
      state.active = nil
      state.pendingRecord = record
      state.evidencePersistence = .failed(
        recordID: record.recordID,
        recoveryCapabilityID: recoveryID,
        detail: detail
      )
      state.terminal = PlotterDrawingRunTerminal(
        runID: owner.runID,
        planIdentity: owner.plan.identity,
        disposition: .publicationIncomplete,
        record: record
      )
      if let post = state.postFrame {
        state.review = .available(
          runID: owner.runID,
          frame: post.plotterExactFrameReference
        )
      }
    }
  }

  private func preEffectRefusal(
    for owner: ActiveRun
  ) async -> PreEffectRefusal? {
    let firstFacts = await facts.drawingRunFacts(for: .live)
    if let refusal = effectFactRefusal(owner: owner, current: firstFacts) {
      return refusal
    }
    guard !admissionClosed,
      isCurrent(owner, environment: .live),
      !cancellationWasRequested(owner, environment: .live)
    else {
      return PreEffectRefusal(
        currentFacts: firstFacts,
        owner: Authority.run,
        reason: admissionClosed ? .admissionClosed : .activeRunOwnsWorkflow,
        remedy: admissionClosed ? .restartApplication : .waitForActiveRun
      )
    }

    let interpreterSnapshot = await interpreter.snapshot()
    let currentFacts = await facts.drawingRunFacts(for: .live)
    if let refusal = effectFactRefusal(owner: owner, current: currentFacts) {
      return refusal
    }
    guard !admissionClosed,
      isCurrent(owner, environment: .live),
      !cancellationWasRequested(owner, environment: .live)
    else {
      return PreEffectRefusal(
        currentFacts: currentFacts,
        owner: Authority.run,
        reason: admissionClosed ? .admissionClosed : .activeRunOwnsWorkflow,
        remedy: admissionClosed ? .restartApplication : .waitForActiveRun
      )
    }
    guard Self.controllerIsReady(interpreterSnapshot) else {
      return PreEffectRefusal(
        currentFacts: currentFacts,
        owner: Authority.interpreter,
        reason: .controllerUnavailable,
        remedy: .restoreControllerReadiness
      )
    }
    return nil
  }

  private func effectFactRefusal(
    owner: ActiveRun,
    current: PlotterDrawingRunExternalFacts
  ) -> PreEffectRefusal? {
    let captured = owner.capturedEffectFacts
    if current.environment != captured.environment {
      return PreEffectRefusal(
        currentFacts: current,
        owner: Authority.run,
        reason: .effectEnvironmentChanged,
        remedy: .useCurrentProjection
      )
    }
    if current.interactiveLearningIsComplete != captured.interactiveLearningIsComplete {
      return PreEffectRefusal(
        currentFacts: current,
        owner: Authority.learning,
        reason: .learningIncomplete,
        remedy: .restoreLearningAuthority
      )
    }
    if current.plan != captured.plan {
      return PreEffectRefusal(
        currentFacts: current,
        owner: Authority.draft,
        reason: .exactPlanChanged,
        remedy: .reviewExactPlan
      )
    }
    if current.paperCoverageIsCurrent != captured.paperCoverageIsCurrent {
      return PreEffectRefusal(
        currentFacts: current,
        owner: Authority.paper,
        reason: .paperCoverageNotCurrent,
        remedy: .assertCurrentPaperCoverage
      )
    }
    if current.penActuationProfile != captured.penActuationProfile {
      return PreEffectRefusal(
        currentFacts: current,
        owner: Authority.interpreter,
        reason: .penActuationProfileChanged,
        remedy: .reviewPenActuationProfile
      )
    }
    return nil
  }

  private func refuseBeforeFirstEffect(
    _ submission: PlotterDrawingRunSubmission,
    active: ActiveRun,
    failure: PreEffectRefusal
  ) -> PlotterDrawingRunSubmissionResult {
    let environment = submission.projection.environment
    guard var state = states[environment], state.active?.runID == active.runID else {
      return refuse(
        submission,
        state: states[environment] ?? SourceState(),
        owner: failure.owner,
        reason: failure.reason,
        remedy: failure.remedy
      )
    }
    state.active = nil
    state.phase = .idle
    state.currentPlanIdentity = failure.currentFacts.plan?.identity
    state.progress = nil
    state.baselineFrame = nil
    state.postFrame = nil
    state.observation = nil
    state.presentationObservation = nil
    state.evidencePersistence = .none
    state.pendingRecord = nil
    state.publicationRecoveryOwner = nil
    advance(&state)
    let refusal = PlotterDrawingRunRefusal(
      requestID: submission.requestID,
      projection: projection(state, environment: environment),
      owner: failure.owner,
      reason: failure.reason,
      remedy: failure.remedy
    )
    state.lastRefusal = refusal
    states[environment] = state
    _ = publish(state, environment: environment)
    return PlotterDrawingRunSubmissionResult(
      disposition: .refused(refusal),
      snapshot: snapshot(state, environment: environment)
    )
  }

  private func revalidate(
    _ owner: ActiveRun,
    requiringControllerReady: Bool
  ) async -> Bool {
    let current = await facts.drawingRunFacts(for: .live)
    guard !admissionClosed, isCurrent(owner, environment: .live) else { return false }
    let actualInterpreter = await interpreter.snapshot()
    guard !admissionClosed,
      CapturedEffectFacts(current) == owner.capturedEffectFacts,
      (!requiringControllerReady || Self.controllerIsReady(actualInterpreter))
    else { return false }
    return isCurrent(owner, environment: .live)
  }

  private func makeRecord(
    owner: ActiveRun,
    frontier: DrawingRunRequestFrontier,
    progress: DrawingPlanProgressSnapshot?,
    execution: DrawingRunExecutionDisposition,
    evidenceDisposition: BorderValidationEvidenceDisposition,
    observation: DrawingRunObservationOutcome
  ) throws -> DrawingRunEvidenceRecord {
    let planned = UInt32(owner.plan.plan.strokes.count)
    let commanded = UInt32(progress?.commandedStrokeCount ?? 0)
    let completed = UInt32(progress?.controllerCompletedStrokeCount ?? 0)
    let verified = evidenceDisposition == .attributable ? completed : 0
    let provenance = try PlotterDrawingPlanningAdapter.planningProvenance(
      for: owner.plan.registration
    )
    return try DrawingRunEvidenceRecord(
      runID: owner.runID,
      requestID: owner.requestID,
      role: owner.plan.evidenceRole,
      evidenceDisposition: evidenceDisposition,
      requestFrontier: frontier,
      executionFrontiers: DrawingRunExecutionFrontiers(
        plannedStrokeCount: planned,
        commandedStrokeCount: commanded,
        controllerCompletedStrokeCount: completed,
        inkVerifiedStrokeCount: verified
      ),
      executionDisposition: execution,
      program: DrawingProgramEvidenceReference(program: owner.plan.program),
      placement: DrawingPlacementEvidenceReference(
        placementID: owner.plan.placementID,
        placement: owner.plan.plan.placement
      ),
      plan: DrawingExecutionPlanEvidenceReference(plan: owner.plan.plan),
      planningProvenance: provenance,
      tipCalibration: DrawingTipCalibrationEvidenceReference(
        acceptedRevisionID: owner.plan.registration.acceptedRevisionID,
        registrationEvidenceSHA256: provenance.registrationContentHash.description,
        applicability: owner.plan.registration.applicability,
        estimatorRevision: owner.plan.registration.estimatorRevision
      ),
      paper: owner.plan.paperCoverage.paper,
      observation: observation,
      recordedAt: RuntimeTimestamp(monotonicNanoseconds: clock.nowNanoseconds())
    )
  }

  private func projection(
    _ state: SourceState,
    environment: PlotterEnvironment
  ) -> PlotterDrawingRunProjectionReference {
    PlotterDrawingRunProjectionReference(
      environment: environment,
      runRevision: state.revision,
      planIdentity: state.currentPlanIdentity
    )
  }

  private func snapshot(
    _ state: SourceState,
    environment: PlotterEnvironment
  ) -> PlotterDrawingRunSnapshot {
    PlotterDrawingRunSnapshot(
      projection: projection(state, environment: environment),
      phase: state.phase,
      activeRunID: state.active?.runID,
      planIdentity: state.active?.plan.identity ?? state.currentPlanIdentity,
      progress: state.progress,
      stopCapabilityID: state.active?.stopCapabilityID,
      terminal: state.terminal,
      noRedraw: state.noRedraw,
      baselineFrame: state.baselineFrame,
      postFrame: state.postFrame,
      observation: state.observation,
      presentationObservation: state.presentationObservation,
      evidencePersistence: state.evidencePersistence,
      evidenceArchiveAvailability: state.evidenceArchiveAvailability,
      review: state.review,
      lastRefusal: state.lastRefusal,
      physicalEvidenceClaimed: environment == .live
        && state.terminal?.disposition == .succeeded
    )
  }

  private func refuse(
    _ submission: PlotterDrawingRunSubmission,
    state initialState: SourceState,
    owner: EpisodeAuthorityID,
    reason: PlotterDrawingRunRefusalReason,
    remedy: PlotterDrawingRunRemedy
  ) -> PlotterDrawingRunSubmissionResult {
    let refusal = PlotterDrawingRunRefusal(
      requestID: submission.requestID,
      projection: projection(
        initialState,
        environment: submission.projection.environment
      ),
      owner: owner,
      reason: reason,
      remedy: remedy
    )
    var state = initialState
    state.lastRefusal = refusal
    states[submission.projection.environment] = state
    _ = publish(state, environment: submission.projection.environment)
    return PlotterDrawingRunSubmissionResult(
      disposition: .refused(refusal),
      snapshot: snapshot(state, environment: submission.projection.environment)
    )
  }

  private func update(
    _ owner: ActiveRun,
    environment: PlotterEnvironment,
    mutation: (inout SourceState) -> Void
  ) {
    guard var state = states[environment], state.active?.runID == owner.runID else { return }
    mutation(&state)
    advance(&state)
    states[environment] = state
    _ = publish(state, environment: environment)
  }

  private func publish(
    _ state: SourceState,
    environment: PlotterEnvironment
  ) -> PlotterDrawingRunSnapshot {
    let value = snapshot(state, environment: environment)
    if let continuations = snapshotContinuations[environment] {
      for continuation in continuations.values {
        continuation.yield(value)
      }
    }
    if state.active == nil,
      let continuations = quiescenceContinuations.removeValue(forKey: environment)
    {
      for continuation in continuations.values {
        continuation.resume()
      }
    }
    return value
  }

  private func waitForQuiescence(environment: PlotterEnvironment) async {
    guard states[environment]?.active != nil else { return }
    let continuationID = UUID()
    await withCheckedContinuation { continuation in
      guard states[environment]?.active != nil else {
        continuation.resume()
        return
      }
      quiescenceContinuations[environment, default: [:]][continuationID] = continuation
    }
  }

  private func removeSnapshotContinuation(
    _ subscriptionID: UUID,
    environment: PlotterEnvironment
  ) {
    snapshotContinuations[environment]?[subscriptionID] = nil
    if snapshotContinuations[environment]?.isEmpty == true {
      snapshotContinuations[environment] = nil
    }
  }

  private func setPhase(
    _ phase: PlotterDrawingRunPhase,
    owner: ActiveRun,
    environment: PlotterEnvironment
  ) {
    update(owner, environment: environment) { $0.phase = phase }
  }

  private func isCurrent(
    _ owner: ActiveRun,
    environment: PlotterEnvironment
  ) -> Bool {
    states[environment]?.active?.runID == owner.runID
  }

  private func cancellationWasRequested(
    _ owner: ActiveRun,
    environment: PlotterEnvironment
  ) -> Bool {
    guard let active = states[environment]?.active, active.runID == owner.runID else {
      return true
    }
    return active.cancellationRequested
  }

  private func advance(_ state: inout SourceState) {
    state.revision = PlotterDrawingRunRevision(rawValue: state.revision.rawValue &+ 1)
  }

  private static func controllerIsReady(_ snapshot: RunInterpreterSnapshot?) -> Bool {
    guard let snapshot else { return false }
    let machine = snapshot.machine
    return snapshot.currentOperation == .idle
      && machine.connection == .connected
      && machine.controllerState == .idle
      && machine.motionGuardState == .active
      && machine.penState == .up
      && machine.position != nil
      && !machine.operationInFlight
      && machine.stickyAmbiguity == nil
      && !machine.pins.hasRelevantLimitAsserted
  }

  private static func executionDisposition(
    for outcome: DrawingPlanOutcome
  ) -> (
    execution: DrawingRunExecutionDisposition,
    evidence: BorderValidationEvidenceDisposition
  ) {
    switch outcome {
    case .completed:
      (.completed, .visionUnclear)
    case .refused(_, let reason):
      (.refused(reason: String(describing: reason)), .refused)
    case .cancelled:
      (.cancelled(reason: "Operator Stop"), .cancelled)
    case .ambiguous(_, let reason):
      (.ambiguous(reason: String(describing: reason)), .ambiguous)
    case .possibleInk(_, let reason, _):
      (.ambiguous(reason: String(describing: reason)), .possibleInk)
    }
  }

  private static func notAttempted(
    for outcome: DrawingPlanOutcome
  ) -> DrawingRunObservationOutcome {
    switch outcome {
    case .refused:
      .notAttempted(.requestRefused)
    case .cancelled:
      .notAttempted(.executionCancelledBeforeObservation)
    case .ambiguous, .possibleInk:
      .notAttempted(.executionFailedBeforeObservation)
    case .completed:
      .notAttempted(.frameEvidenceUnavailable)
    }
  }

  private static func terminalDisposition(
    execution: DrawingRunExecutionDisposition,
    evidence: BorderValidationEvidenceDisposition
  ) -> PlotterDrawingRunTerminalDisposition {
    switch evidence {
    case .attributable: .succeeded
    case .nonAttributable: .nonAttributable
    case .visionUnclear: .visionRejected
    case .possibleInk: .possibleInk
    case .ambiguous: .ambiguous
    case .cancelled: .cancelled
    case .refused: .refused
    }
  }

  private static func observationRegion(
    _ intended: [Polyline<CameraPixelSpace>],
    frameWidth: Int,
    frameHeight: Int
  ) -> PixelRect {
    let points = intended.flatMap(\.points)
    let margin = 8
    let minX = max(0, Int(floor(points.map(\.x).min() ?? 0)) - margin)
    let minY = max(0, Int(floor(points.map(\.y).min() ?? 0)) - margin)
    let maxX = min(frameWidth - 1, Int(ceil(points.map(\.x).max() ?? 0)) + margin)
    let maxY = min(frameHeight - 1, Int(ceil(points.map(\.y).max() ?? 0)) + margin)
    return PixelRect(
      x: minX,
      y: minY,
      width: max(1, maxX - minX + 1),
      height: max(1, maxY - minY + 1)
    )
  }
}
