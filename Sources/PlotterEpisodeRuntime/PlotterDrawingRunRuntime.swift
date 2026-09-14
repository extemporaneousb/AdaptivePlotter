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
  public let candidate: DrawingRunCandidateReference?
  public let materialProfile: DrawingMaterialProfileRevision?
  public let materialApplicability: DrawingMaterialApplicability?
  public let paperStock: String?

  public init(
    draftRevision: PlotterDrawingDraftRevision,
    program: DrawingProgram,
    placementID: UUID,
    plan: ExecutionPlanRevision,
    evidenceRole: BorderValidationEvidenceRole,
    paperCoverage: PaperCoverageObservation,
    registration: TipCameraRegistration,
    candidate: DrawingRunCandidateReference? = nil,
    materialProfile: DrawingMaterialProfileRevision? = nil,
    materialApplicability: DrawingMaterialApplicability? = nil,
    paperStock: String? = nil
  ) {
    precondition(plan.revisionID.rawValue == plan.contentHash)
    self.program = program
    self.placementID = placementID
    self.plan = plan
    self.evidenceRole = evidenceRole
    self.paperCoverage = paperCoverage
    self.registration = registration
    self.candidate = candidate
    self.materialProfile = materialProfile
    self.materialApplicability = materialApplicability
    self.paperStock = paperStock
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
  public let physicalPositionUnavailableReason: String?
  public let acceptedMovementBounds: AxisAlignedBounds<MachineSpace>?

  public init(
    environment: PlotterEnvironment,
    interactiveLearningIsComplete: Bool,
    plan: PlotterDrawingRunPlan?,
    paperCoverageIsCurrent: Bool,
    displayedFrame: DisplayedFrame?,
    interpreter: RunInterpreterSnapshot?,
    penActuationProfile: PenActuationProfile,
    physicalPositionUnavailableReason: String? = nil,
    acceptedMovementBounds: AxisAlignedBounds<MachineSpace>? = nil
  ) {
    self.environment = environment
    self.interactiveLearningIsComplete = interactiveLearningIsComplete
    self.plan = plan
    self.paperCoverageIsCurrent = paperCoverageIsCurrent
    self.displayedFrame = displayedFrame
    self.interpreter = interpreter
    self.penActuationProfile = penActuationProfile
    self.physicalPositionUnavailableReason = physicalPositionUnavailableReason
    self.acceptedMovementBounds = acceptedMovementBounds
  }
}

/// Supplies current application facts only. It cannot mutate draft, controller,
/// camera, Vision, or evidence authority.
public protocol PlotterDrawingRunFactSource: Sendable {
  func drawingRunFacts(for environment: PlotterEnvironment) async
    -> PlotterDrawingRunExternalFacts
  func retainCandidateForAttempt(_ intent: DrawingRunIntent) async throws
}

extension PlotterDrawingRunFactSource {
  public func retainCandidateForAttempt(_ intent: DrawingRunIntent) async throws {
    guard intent.context.candidate == nil else { throw DrawingRunEvidenceError.invalidAttemptContext }
  }
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
  func stageIntent(_ intent: DrawingRunIntent) async throws -> DrawingRunEvidenceArchive
  func installMedia(frame: StampedFrame, source: FrameSourceIdentity) async throws -> DrawingRunMediaReference
  func stageBaseline(runID: RunID, media: DrawingRunMediaReference) async throws -> DrawingRunEvidenceArchive
  func markInkDispatchPossible(runID: RunID) async throws -> DrawingRunEvidenceArchive
  func append(_ record: DrawingRunEvidenceRecord) async throws
    -> DrawingRunEvidenceArchive
}

public enum PlotterDrawingRunPhase: Hashable, Sendable {
  case idle
  case validating
  case stagingIntent
  case normalizingPenUp
  case positioningForBaseline
  case capturingBaseline
  case stagingBaseline
  case markingInkDispatchPossible
  case executingPlan
  case positioningForPostObservation
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
  case intentPublicationIncomplete(runID: RunID, detail: String)
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
  public let readiness: PlotterDrawingRunReadiness
}

public enum PlotterDrawingRunSubmissionDisposition: Hashable, Sendable {
  case applied
  case refused(PlotterDrawingRunRefusal)
}

public struct PlotterDrawingRunSubmissionResult: Hashable, Sendable {
  public let disposition: PlotterDrawingRunSubmissionDisposition
  public let snapshot: PlotterDrawingRunSnapshot
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
    let acceptedMovementBounds: AxisAlignedBounds<MachineSpace>?

    init(_ facts: PlotterDrawingRunExternalFacts) {
      environment = facts.environment
      interactiveLearningIsComplete = facts.interactiveLearningIsComplete
      plan = facts.plan
      paperCoverageIsCurrent = facts.paperCoverageIsCurrent
      penActuationProfile = facts.penActuationProfile
      acceptedMovementBounds = facts.acceptedMovementBounds
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
    var readiness = PlotterDrawingRunReadiness.synchronizing
    var active: ActiveRun?
    var progress: DrawingPlanProgressSnapshot?
    var terminal: PlotterDrawingRunTerminal?
    var noRedraw = PlotterDrawingRunNoRedrawState.archiveUnavailable(
      detail: "Drawing evidence archive has not been loaded."
    )
    var blockedPlanHashes = Set<Digest>()
    // Immutable same-paper records back the existing no-redraw index. A known
    // coordinate rebase may change a plan hash without changing physical ink.
    var blockedPlanRecords: [DrawingRunEvidenceRecord] = []
    var blockedPlanIntents: [DrawingRunIntent] = []
    var baselineFrame: DisplayedFrame?
    var postFrame: DisplayedFrame?
    var observation: DrawingRunObservationOutcome?
    var presentationObservation: PlannedDrawingObservation?
    var evidencePersistence = PlotterDrawingRunEvidencePersistence.none
    var evidenceArchiveAvailability = PlotterDrawingRunEvidenceArchiveAvailability.awaitingLoad
    var pendingRecord: DrawingRunEvidenceRecord?
    var stagedIntent: DrawingRunIntent?
    var baselineMedia: [DrawingRunMediaReference] = []
    var terminalMedia: [DrawingRunMediaReference] = []
    // Available originals remain owned until their exact immutable terminal is
    // durable. Failed media installation uses the existing publication retry.
    var terminalMediaBytes: [DrawingRunMediaReference: DisplayedFrame] = [:]
    var mediaCoverage: DrawingRunMediaCoverage?
    var missingCoverageReason: String?
    var inkDispatchPossible = false
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
    let previous = snapshot(state, environment: environment)
    state.currentPlanIdentity = currentFacts.plan?.identity
    indexEquivalentPhysicalPlan(in: &state, facts: currentFacts)
    state.readiness = readiness(state: state, facts: currentFacts, controller: currentFacts.interpreter)
    if state.active == nil, state.terminal == nil { state.phase = .idle }
    guard snapshot(state, environment: environment) != previous else { return previous }
    advance(&state)
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
    let markedRuns = Set(archive.attempts.filter(\.inkDispatchPossible).map { $0.intent.runID })
    state.blockedPlanRecords = archive.records.filter {
      $0.paper == paper && ($0.executionFrontiers.commandedStrokeCount > 0 || markedRuns.contains($0.runID))
    }
    state.blockedPlanHashes = Set(state.blockedPlanRecords.map(\.plan.contentHash))
    state.blockedPlanIntents = archive.attempts.filter {
      $0.intent.context.paper == paper && $0.inkDispatchPossible
    }.map(\.intent)
    state.blockedPlanHashes.formUnion(state.blockedPlanIntents.map { $0.plan.contentHash })
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
      if state.phase == .positioningForBaseline || state.phase == .executingPlan
        || state.phase == .positioningForPostObservation {
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
    let polled = states[environment] ?? SourceState()
    guard polled.phase == .executingPlan else {
      return snapshot(polled, environment: environment)
    }
    let progress = await interpreter.snapshot()?.drawingPlanProgress
    // The lower poll can suspend across Stop, evidence settlement or a new-run
    // handoff. Merge progress only into the exact state that requested it.
    var current = states[environment] ?? SourceState()
    guard current.phase == .executingPlan,
      current.active?.runID == polled.active?.runID,
      current.revision == polled.revision
    else { return snapshot(current, environment: environment) }
    if let progress, let previous = current.progress,
      !progress.isExecutionFrontier(atLeastAsAdvancedAs: previous) {
      return snapshot(current, environment: environment)
    }
    current.progress = progress ?? current.progress
    states[environment] = current
    return publish(current, environment: environment)
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
    let controller = await interpreter.snapshot()
    var currentState = states[environment] ?? initialState
    indexEquivalentPhysicalPlan(in: &currentState, facts: currentFacts)
    let currentReadiness = readiness(state: currentState, facts: currentFacts, controller: controller)
    if case .unavailable(let issue) = currentReadiness {
      return refuse(submission, state: currentState, owner: issue.owner,
        reason: issue.reason, remedy: issue.remedy, detail: issue.detail)
    }
    guard let plan = currentFacts.plan,
      submission.projection.planIdentity == plan.identity else {
      return refuse(submission, state: currentState, owner: Authority.draft,
        reason: .exactPlanUnavailable, remedy: .reviewExactPlan,
        detail: "Review the current drawing target before drawing.")
    }

    let runID = RunID()
    let active = ActiveRun(
      runID: runID,
      requestID: submission.requestID.rawValue,
      plan: plan,
      capturedEffectFacts: CapturedEffectFacts(currentFacts),
      stopCapabilityID: PlotterDrawingRunStopCapabilityID()
    )
    var state = currentState
    state.readiness = currentReadiness
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
    state.stagedIntent = nil
    state.baselineMedia = []
    state.terminalMedia = []
    state.terminalMediaBytes = [:]
    state.mediaCoverage = nil
    state.missingCoverageReason = nil
    state.inkDispatchPossible = false
    state.review = .livePreview
    advance(&state)
    states[environment] = state
    _ = publish(state, environment: environment)

    if let failure = await preEffectRefusal(for: active, requiresPenUp: false) {
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

  private enum PreparationFailure: Error {
    case cancelled(String)
    case refused(String)
    case ambiguous(String)
  }

  private func run(_ owner: ActiveRun, initialFacts: PlotterDrawingRunExternalFacts) async {
    let environment = initialFacts.environment
    let observationPlan: DrawingRunObservationPlan
    do {
      guard let bounds = owner.capturedEffectFacts.acceptedMovementBounds,
        let position = initialFacts.interpreter?.machine.position else {
        throw PreparationFailure.refused("Accepted movement bounds or controller position are unavailable.")
      }
      observationPlan = try DrawingRunObservationPlan(
        executionPlan: owner.plan.plan, acceptedMovementBounds: bounds, currentPosition: position)
      let context = try DrawingRunAttemptContext(
        program: owner.plan.program, registration: owner.plan.registration,
        materialProfile: owner.plan.materialProfile, materialApplicability: owner.plan.materialApplicability,
        paperStock: owner.plan.paperStock,
        drawingFeedMMPerMinute: PlotterMotionThroughput.applicationXYFeedMMPerMinute,
        penActuationProfile: owner.capturedEffectFacts.penActuationProfile,
        paper: owner.plan.paperCoverage.paper, candidate: owner.plan.candidate)
      let intent = try DrawingRunIntent(
        runID: owner.runID, requestID: owner.requestID, plan: owner.plan.plan,
        placementID: owner.plan.placementID, role: owner.plan.evidenceRole,
        context: context, observationPlan: observationPlan,
        recordedAt: RuntimeTimestamp(monotonicNanoseconds: clock.nowNanoseconds()))
      update(owner, environment: environment) { $0.stagedIntent = intent; $0.phase = .stagingIntent }
      _ = try await evidence.stageIntent(intent)
      try await facts.retainCandidateForAttempt(intent)
      if let refusal = await preEffectRefusal(for: owner, requiresPenUp: false) {
        throw PreparationFailure.refused("Attempt facts changed before preparation: \(refusal.reason)")
      }
    } catch {
      await finishPreparationFailure(owner, error: error)
      return
    }

    setPhase(.normalizingPenUp, owner: owner, environment: environment)
    let penOutcome = await interpreter.normalizePenUp(profile: owner.capturedEffectFacts.penActuationProfile)
    guard isCurrent(owner, environment: environment) else { return }
    if admissionClosed || cancellationWasRequested(owner, environment: environment) {
      await finishPreparationFailure(owner, error: PreparationFailure.cancelled("Stop during Pen Up normalization."))
      return
    }
    guard case .commandedAndSettled(command: .raise, commandedState: .up) = penOutcome else {
      let failure: PreparationFailure
      if case .ambiguous = penOutcome { failure = .ambiguous(String(describing: penOutcome)) }
      else { failure = .refused(String(describing: penOutcome)) }
      await finishPreparationFailure(owner, error: failure)
      return
    }

    guard await revalidate(owner, requiringControllerReady: true) else {
      await finishPreparationFailure(owner,
        error: PreparationFailure.refused("Run facts changed after Pen Up normalization."))
      return
    }
    var baselines: [SamePoseFrameSample] = []
    var newestCapture = initialFacts.displayedFrame?.frame.captureNanoseconds ?? 0
    do {
      for pose in observationPlan.poses {
        let settled = try await reachObservationPose(pose.position, owner: owner, phase: .positioningForBaseline)
        guard await revalidate(owner, requiringControllerReady: true) else {
          throw PreparationFailure.cancelled("Stop or stale facts before baseline capture.")
        }
        let captureAfter = max(clock.nowNanoseconds(), newestCapture)
        setPhase(.capturingBaseline, owner: owner, environment: environment)
        let baseline = try await camera.captureFrame(newerThan: captureAfter)
        guard isCurrent(owner, environment: environment) else { return }
        update(owner, environment: environment) { $0.baselineFrame = baseline }
        guard baseline.frame.captureNanoseconds > captureAfter,
          baseline.source == initialFacts.displayedFrame?.source else {
          throw DrawingRunEvidenceError.invalidFramePair
        }
        newestCapture = baseline.frame.captureNanoseconds
        baselines.append(SamePoseFrameSample(displayedFrame: baseline, controllerPosition: settled))
        setPhase(.stagingBaseline, owner: owner, environment: environment)
        _ = try await evidence.installMedia(frame: baseline.frame, source: baseline.source)
        let media = DrawingRunMediaReference(frame: baseline.frame, source: baseline.source,
          controllerPosition: settled, captureAfterNanoseconds: captureAfter)
        update(owner, environment: environment) { $0.baselineMedia.append(media) }
        _ = try await evidence.stageBaseline(runID: owner.runID, media: media)
        guard await revalidate(owner, requiringControllerReady: true) else {
          throw PreparationFailure.cancelled("Stop or stale facts after baseline persistence.")
        }
      }
    } catch {
      await finishPreparationFailure(owner, error: error)
      return
    }

    let request: DrawingPlanRequest
    do {
      request = try DrawingPlanRequest(
        operationID: DrawingPlanOperationID(rawValue: owner.requestID), plan: owner.plan.plan,
        travelFeedMMPerMinute: PlotterMotionThroughput.applicationXYFeedMMPerMinute,
        drawingFeedMMPerMinute: PlotterMotionThroughput.applicationXYFeedMMPerMinute,
        penActuationProfile: owner.capturedEffectFacts.penActuationProfile)
      guard await revalidate(owner, requiringControllerReady: true) else {
        throw PreparationFailure.cancelled("Stop or stale facts before durable dispatch marker.")
      }
      update(owner, environment: environment) {
        $0.phase = .markingInkDispatchPossible
        // A failed save can be an uncertain acknowledgement of a durable marker.
        $0.inkDispatchPossible = true
        $0.blockedPlanHashes.insert(owner.plan.plan.contentHash)
      }
      _ = try await evidence.markInkDispatchPossible(runID: owner.runID)
      guard await revalidate(owner, requiringControllerReady: true) else {
        throw PreparationFailure.cancelled("Stop or stale facts before plan admission.")
      }
    } catch {
      await finishPreparationFailure(owner, error: error)
      return
    }

    setPhase(.executingPlan, owner: owner, environment: environment)
    let admission = await interpreter.beginDrawingPlan(request)
    let outcome: DrawingPlanOutcome
    let frontier: DrawingRunRequestFrontier
    switch admission {
    case .admitted(let operation): frontier = .admitted; outcome = await operation.outcome()
    case .rejected(let rejected): frontier = .validated; outcome = rejected
    }
    guard isCurrent(owner, environment: environment) else { return }
    update(owner, environment: environment) { $0.progress = outcome.progress }
    if admissionClosed || cancellationWasRequested(owner, environment: environment) {
      await preserveAvailableTerminalFrame(owner)
      await finish(owner, frontier: frontier, progress: outcome.progress,
        execution: .cancelled(reason: admissionClosed ? "Application shutdown" : "Operator Stop"),
        evidenceDisposition: .cancelled,
        observation: .notAttempted(.executionCancelledBeforeObservation))
      return
    }
    guard case .completed(_, let completedPosition) = outcome else {
      await preserveAvailableTerminalFrame(owner)
      let mapped = Self.executionDisposition(for: outcome)
      await finish(owner, frontier: frontier, progress: outcome.progress,
        execution: mapped.execution, evidenceDisposition: mapped.evidence,
        observation: Self.notAttempted(for: outcome))
      return
    }

    guard let endpoint = owner.plan.plan.strokes.last?.path.points.last,
      MachinePositionAcceptancePolicy.accepts(completedPosition, target: MachinePosition(point: endpoint)) else {
      await preserveAvailableTerminalFrame(owner)
      await finish(owner, frontier: frontier, progress: outcome.progress,
        execution: .ambiguous(reason: "Completed drawing reported an unexpected final position."),
        evidenceDisposition: .possibleInk, observation: .notAttempted(.executionFailedBeforeObservation))
      return
    }
    var results: [SamePoseFrameSample] = []
    do {
      for (index, pose) in observationPlan.poses.enumerated() {
        // This branch exists only after successful, uncancelled execution; every
        // suspension rechecks that the same run still owns safe pen-up travel.
        let settled = try await reachObservationPose(
          pose.position, owner: owner, phase: .positioningForPostObservation)
        guard await revalidate(owner, requiringControllerReady: true) else {
          throw PreparationFailure.cancelled("Stop or stale facts before result capture.")
        }
        let captureAfter = max(clock.nowNanoseconds(), newestCapture)
        setPhase(.capturingPostFrame, owner: owner, environment: environment)
        let post = try await camera.captureFrame(newerThan: captureAfter)
        guard isCurrent(owner, environment: environment) else { return }
        update(owner, environment: environment) { $0.postFrame = post }
        guard post.source == baselines[index].drawingRunDisplayedFrame.source,
          post.frame.captureNanoseconds > captureAfter else {
          // Keep stale available bytes, but never bind them to the settled pose.
          throw DrawingRunEvidenceError.invalidFramePair
        }
        let media = DrawingRunMediaReference(frame: post.frame, source: post.source,
          controllerPosition: settled, captureAfterNanoseconds: captureAfter)
        update(owner, environment: environment) {
          $0.terminalMedia.append(media)
          $0.terminalMediaBytes[media] = post
        }
        // Failure retains exact bytes and reference for publication-only retry.
        _ = try await evidence.installMedia(frame: post.frame, source: post.source)
        newestCapture = post.frame.captureNanoseconds
        results.append(SamePoseFrameSample(displayedFrame: post, controllerPosition: settled))
        guard await revalidate(owner, requiringControllerReady: true) else {
          throw PreparationFailure.cancelled("Stop or stale facts after result capture.")
        }
      }
    } catch {
      await preserveAvailableTerminalFrame(owner)
      update(owner, environment: environment) { $0.missingCoverageReason = String(describing: error) }
      await finish(owner, frontier: frontier, progress: outcome.progress,
        execution: .completed, evidenceDisposition: .visionUnclear,
        observation: .notAttempted(.frameEvidenceUnavailable))
      return
    }

    guard let baseline = baselines.first, let post = results.first else {
      await finish(owner, frontier: frontier, progress: outcome.progress,
        execution: .completed, evidenceDisposition: .visionUnclear,
        observation: .notAttempted(.frameEvidenceUnavailable))
      return
    }
    do {
      let views = try zip(baselines, results).enumerated().map { index, pair in
        try DrawingRunCoverageView(viewID: observationPlan.poses[index].id,
          baseline: pair.0, result: pair.1, registration: owner.plan.registration)
      }
      let intended = try TipApplicabilityEvidencePolicy.project(
        paths: owner.plan.plan.strokes.map(\.path), using: owner.plan.registration)
        .attributableCameraPolylines ?? []
      let coverage = try await DrawingRunMediaCoverage.compose(views: views,
        region: Self.observationRegion(intended, frameWidth: post.drawingRunDisplayedFrame.frame.width,
          frameHeight: post.drawingRunDisplayedFrame.frame.height))
      update(owner, environment: environment) {
        $0.mediaCoverage = coverage
        if coverage.uncoveredMask.contains(true) {
          $0.missingCoverageReason = "Exact armature/occlusion visibility is unavailable; uncovered pixels remain unknown."
        }
      }
    } catch {
      update(owner, environment: environment) { $0.missingCoverageReason = "Coverage comparison unavailable: \(error)" }
    }
    let (observation, disposition) = await observePrimaryView(owner,
      baseline: baseline.drawingRunDisplayedFrame, post: post.drawingRunDisplayedFrame,
      observationPosition: baseline.controllerPosition, finalPosition: post.controllerPosition)
    await finish(owner, frontier: frontier, progress: outcome.progress,
      execution: .completed, evidenceDisposition: disposition, observation: observation)
  }

  private func reachObservationPose(_ target: MachinePosition, owner: ActiveRun,
    phase: PlotterDrawingRunPhase) async throws -> MachinePosition {
    guard await revalidate(owner, requiringControllerReady: true),
      let current = await interpreter.snapshot()?.machine.position else {
      throw PreparationFailure.cancelled("Controller or run facts changed before observation travel.")
    }
    guard !admissionClosed, !cancellationWasRequested(owner, environment: .live) else {
      throw PreparationFailure.cancelled("Stop before observation travel.")
    }
    if MachinePositionAcceptancePolicy.accepts(current, target: target) { return current }
    let request = RelativeJogRequest(delta: try current.point.vector(to: target.point),
      feedMMPerMinute: PlotterMotionThroughput.applicationXYFeedMMPerMinute)
    setPhase(phase, owner: owner, environment: .live)
    guard await revalidate(owner, requiringControllerReady: true) else {
      throw PreparationFailure.cancelled("Stop or stale facts before observation travel.")
    }
    let travel = await interpreter.travelToObservationPosition(request)
    guard isCurrent(owner, environment: .live), !admissionClosed,
      !cancellationWasRequested(owner, environment: .live) else {
      throw PreparationFailure.cancelled("Stop during observation travel.")
    }
    switch travel {
    case .acceptedThenCompleted(let final):
      guard MachinePositionAcceptancePolicy.accepts(final, target: target) else {
        throw PreparationFailure.ambiguous("Observation travel settled outside the exact target.")
      }
      return final
    case .cancelled: throw PreparationFailure.cancelled("Observation travel cancelled.")
    case .refused(let reason): throw PreparationFailure.refused(String(describing: reason))
    case .ambiguous(let reason): throw PreparationFailure.ambiguous(String(describing: reason))
    }
  }

  private func finishPreparationFailure(_ owner: ActiveRun, error: any Error) async {
    if states[.live]?.inkDispatchPossible == true { await preserveAvailableTerminalFrame(owner) }
    update(owner, environment: .live) { $0.missingCoverageReason = String(describing: error) }
    let execution: DrawingRunExecutionDisposition
    let disposition: BorderValidationEvidenceDisposition
    switch error {
    case PreparationFailure.cancelled(let detail): execution = .cancelled(reason: detail); disposition = .cancelled
    case PreparationFailure.ambiguous(let detail): execution = .ambiguous(reason: detail); disposition = .ambiguous
    default: execution = .refused(reason: String(describing: error)); disposition = .refused
    }
    await finishBeforePlan(owner, execution: execution, evidenceDisposition: disposition,
      observation: disposition == .refused ? .notAttempted(.requestRefused) : .notAttempted(.frameEvidenceUnavailable))
  }

  private func observePrimaryView(
    _ owner: ActiveRun, baseline: DisplayedFrame, post: DisplayedFrame,
    observationPosition: MachinePosition, finalPosition: MachinePosition
  ) async -> (DrawingRunObservationOutcome, BorderValidationEvidenceDisposition) {
    let environment = PlotterEnvironment.live
    let observation: DrawingRunObservationOutcome
    let evidenceDisposition: BorderValidationEvidenceDisposition
    do {
      let projection = try TipApplicabilityEvidencePolicy.project(
        paths: owner.plan.plan.strokes.map(\.path),
        using: owner.plan.registration
      )
      guard let intended = projection.attributableCameraPolylines else {
        return (.notAttempted(.projectionOutsideTipApplicability), .nonAttributable)
      }
      guard await revalidate(owner, requiringControllerReady: false) else {
        return (.notAttempted(.frameEvidenceUnavailable), .visionUnclear)
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
        return (.notAttempted(.frameEvidenceUnavailable), .visionUnclear)
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
    return (observation, evidenceDisposition)
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
    if let post = states[environment]?.postFrame {
      let available = DrawingRunMediaReference(frame: post.frame, source: post.source)
      let reference = states[environment]?.terminalMedia.first(where: {
        $0.frame == available.frame && $0.source == available.source
      }) ?? available
      update(owner, environment: environment) {
        if !$0.terminalMedia.contains(reference) { $0.terminalMedia.append(reference) }
        $0.terminalMediaBytes[reference] = post
      }
    }
    let stopped = admissionClosed || cancellationWasRequested(owner, environment: environment)
    let execution = stopped
      ? DrawingRunExecutionDisposition.cancelled(reason: admissionClosed ? "Application shutdown" : "Operator Stop")
      : execution
    let evidenceDisposition = stopped ? BorderValidationEvidenceDisposition.cancelled : evidenceDisposition
    let observation = stopped
      ? DrawingRunObservationOutcome.notAttempted(.executionCancelledBeforeObservation) : observation
    do {
      let record = try makeRecord(
        owner: owner,
        frontier: frontier,
        progress: progress,
        execution: execution,
        evidenceDisposition: evidenceDisposition,
        observation: observation
      )
      update(owner, environment: environment) { state in
        state.phase = .appendingEvidence
        state.observation = observation
        state.pendingRecord = record
        state.evidencePersistence = .appending(record.recordID)
        state.noRedraw = (progress?.commandedStrokeCount ?? 0 > 0 || state.inkDispatchPossible)
          ? .planMayContainInk(runID: owner.runID, planIdentity: owner.plan.identity)
          : .newPlanRequired(runID: owner.runID, planIdentity: owner.plan.identity)
      }
      await append(record, owner: owner, proposed: Self.terminalDisposition(
        execution: execution,
        evidence: evidenceDisposition
      ))
    } catch {
      // Preserve the durable attempt and explicit diagnostic when a terminal
      // record cannot be constructed. There is no fabricated successful record
      // and no new-run admission from this incomplete publication state.
      update(owner, environment: environment) { state in
        state.phase = .terminal
        state.active = nil
        state.evidencePersistence = .intentPublicationIncomplete(runID: owner.runID,
          detail: "Terminal evidence construction failed; retained attempt requires recovery: \(error)")
        state.noRedraw = state.inkDispatchPossible || (progress?.commandedStrokeCount ?? 0) > 0
          ? .planMayContainInk(runID: owner.runID, planIdentity: owner.plan.identity)
          : .newPlanRequired(runID: owner.runID, planIdentity: owner.plan.identity)
      }
    }
  }

  private func append(
    _ record: DrawingRunEvidenceRecord,
    owner: ActiveRun,
    proposed: PlotterDrawingRunTerminalDisposition
  ) async {
    let environment = PlotterEnvironment.live
    // Closing admission cannot cancel publication owned by this exact run.
    // Shutdown joins its durable terminal append before quiescence is released.
    do {
      let archive = try await appendExactEvidence(record)
      guard isCurrent(owner, environment: environment) else { return }
      update(owner, environment: environment) { state in
        state.blockedPlanIntents = archive.attempts.filter {
          $0.intent.context.paper == record.paper && $0.inkDispatchPossible
        }.map(\.intent)
        let markedRuns = Set(state.blockedPlanIntents.map(\.runID))
        state.blockedPlanRecords = archive.records.filter {
          $0.paper == record.paper && ($0.executionFrontiers.commandedStrokeCount > 0 || markedRuns.contains($0.runID))
        }
        state.blockedPlanHashes.formUnion(state.blockedPlanRecords.map(\.plan.contentHash))
        state.phase = .terminal
        state.active = nil
        state.pendingRecord = nil
        state.terminalMediaBytes = [:]
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

  /// Replays only idempotent persistence, never controller or camera work.
  /// A save acknowledgement can fail after installation; retain and retry the
  /// exact intent/baseline identities before sealing the immutable terminal.
  private func appendExactEvidence(_ record: DrawingRunEvidenceRecord) async throws -> DrawingRunEvidenceArchive {
    if let attempt = record.attemptEvidence {
      // Raw bytes remain owned by this run even while active == nil during
      // publication recovery. Installation has no capture or motion authority.
      let retainedBytes = states[.live]?.terminalMediaBytes ?? [:]
      for reference in attempt.terminalFrames {
        if let frame = retainedBytes[reference] {
          _ = try await evidence.installMedia(frame: frame.frame, source: frame.source)
        }
      }
      _ = try await evidence.stageIntent(attempt.intent)
      for baseline in attempt.baselines {
        _ = try await evidence.stageBaseline(runID: record.runID, media: baseline)
      }
    }
    return try await evidence.append(record)
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
    if state.phase == .positioningForBaseline || state.phase == .executingPlan
        || state.phase == .positioningForPostObservation {
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
    state.readiness = .synchronizing
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
      let archive = try await appendExactEvidence(record)
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
      state.blockedPlanIntents = archive.attempts.filter {
        $0.intent.context.paper == record.paper && $0.inkDispatchPossible
      }.map(\.intent)
      let markedRuns = Set(state.blockedPlanIntents.map(\.runID))
      state.blockedPlanRecords = archive.records.filter {
        $0.paper == record.paper && ($0.executionFrontiers.commandedStrokeCount > 0 || markedRuns.contains($0.runID))
      }
      state.blockedPlanHashes.formUnion(state.blockedPlanRecords.map(\.plan.contentHash))
      state.phase = .terminal
      state.pendingRecord = nil
      state.terminalMediaBytes = [:]
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
    for owner: ActiveRun,
    requiresPenUp: Bool = true
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
    guard Self.controllerIsReady(interpreterSnapshot, requiresPenUp: requiresPenUp) else {
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
    if current.physicalPositionUnavailableReason != nil {
      return PreEffectRefusal(currentFacts: current, owner: Authority.learning,
        reason: .physicalPositionUnverified, remedy: .reestablishPositionFromCamera)
    }
    if current.interactiveLearningIsComplete != captured.interactiveLearningIsComplete {
      return PreEffectRefusal(
        currentFacts: current,
        owner: Authority.learning,
        reason: .learningIncomplete,
        remedy: .restoreLearningAuthority
      )
    }
    if current.plan != captured.plan || current.acceptedMovementBounds != captured.acceptedMovementBounds {
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
    state.readiness = readiness(state: state, facts: failure.currentFacts,
      controller: failure.currentFacts.interpreter)
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
    guard !admissionClosed, isCurrent(owner, environment: .live),
      !cancellationWasRequested(owner, environment: .live) else { return false }
    let actualInterpreter = await interpreter.snapshot()
    let settledFacts = await facts.drawingRunFacts(for: .live)
    guard !admissionClosed,
      CapturedEffectFacts(current) == owner.capturedEffectFacts,
      CapturedEffectFacts(settledFacts) == owner.capturedEffectFacts,
      settledFacts.physicalPositionUnavailableReason == nil,
      (!requiringControllerReady || Self.controllerIsReady(actualInterpreter))
    else { return false }
    return isCurrent(owner, environment: .live)
      && !cancellationWasRequested(owner, environment: .live)
  }

  /// Read-only retention of the available terminal view. Failure and Stop must
  /// never travel or initiate another camera acquisition to improve coverage.
  private func preserveAvailableTerminalFrame(_ owner: ActiveRun) async {
    let current = await facts.drawingRunFacts(for: .live)
    guard isCurrent(owner, environment: .live) else { return }
    update(owner, environment: .live) { state in
      if state.missingCoverageReason == nil {
        state.missingCoverageReason = "Matched result observation did not complete. No automatic photo repositioning was authorized; available images may predate completion and visibility remains unknown."
      }
      if let frame = current.displayedFrame,
        frame.frame.captureNanoseconds > (state.postFrame?.frame.captureNanoseconds ?? 0) {
        state.postFrame = frame
      }
    }
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
    let provenance = owner.plan.plan.provenance
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
      recordedAt: RuntimeTimestamp(monotonicNanoseconds: clock.nowNanoseconds()),
      attemptEvidence: states[.live]?.stagedIntent.map { intent in
        let state = states[.live] ?? SourceState()
        return DrawingRunAttemptEvidence(intent: intent, baselines: state.baselineMedia,
          terminalFrames: state.terminalMedia, mediaCoverage: state.mediaCoverage,
          missingCoverageReason: state.missingCoverageReason
            ?? (state.mediaCoverage == nil ? "Matched observation coverage was not completed." : nil))
      }
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
        && state.terminal?.disposition == .succeeded,
      readiness: lifecycleReadiness(state) ?? state.readiness
    )
  }

  private func refuse(
    _ submission: PlotterDrawingRunSubmission,
    state initialState: SourceState,
    owner: EpisodeAuthorityID,
    reason: PlotterDrawingRunRefusalReason,
    remedy: PlotterDrawingRunRemedy,
    detail: String? = nil
  ) -> PlotterDrawingRunSubmissionResult {
    let environment = submission.projection.environment
    var state = initialState
    let previousReadiness = snapshot(state, environment: environment).readiness
    if let detail {
      state.readiness = .unavailable(.init(owner: owner, reason: reason, remedy: remedy, detail: detail))
    }
    if snapshot(state, environment: environment).readiness != previousReadiness {
      advance(&state)
    }
    let refusal = PlotterDrawingRunRefusal(
      requestID: submission.requestID,
      projection: projection(
        state,
        environment: environment
      ),
      owner: owner,
      reason: reason,
      remedy: remedy,
      detail: detail
    )
    state.lastRefusal = refusal
    states[environment] = state
    _ = publish(state, environment: environment)
    return PlotterDrawingRunSubmissionResult(
      disposition: .refused(refusal),
      snapshot: snapshot(state, environment: environment)
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

  private func indexEquivalentPhysicalPlan(in state: inout SourceState, facts: PlotterDrawingRunExternalFacts) {
    guard facts.physicalPositionUnavailableReason == nil, let current = facts.plan,
      !state.blockedPlanHashes.contains(current.plan.contentHash) else { return }
    let epsilon = DrawingRegionContainmentPolicy.numericalEpsilonMM
    func close(_ left: Double, _ right: Double) -> Bool { abs(left - right) <= epsilon }
    let region = current.plan.drawableRegion.bounds
    let applicability = current.registration.applicability
    let source = current.program.source
    let sourceIdentity = source.sourceIdentifier.components(separatedBy: "|draw-border-v1").first
    let permitsCheckpointTranslation: Bool
    if case .checkpointRevalidated = current.registration.derivation { permitsCheckpointTranslation = true }
    else { permitsCheckpointTranslation = false }
    let candidates: [(ExecutionPlanRevision, DrawingSourceProvenance?, TipCalibrationApplicabilityContext)] =
      state.blockedPlanRecords.compactMap { record in
        guard let plan = record.plan.executionPlan else { return nil }
        return (plan, record.program.source, record.tipCalibration.applicability)
      } + state.blockedPlanIntents.map { ($0.plan, $0.context.program.source, $0.context.registration.applicability) }
    for (prior, priorSource, previous) in candidates {
      let old = prior.drawableRegion.bounds
      guard previous.machineGeometry == applicability.machineGeometry,
        prior.strokes.count == current.plan.strokes.count else { continue }
      let sameCoordinates = previous.machineCoordinateFrame == applicability.machineCoordinateFrame
      let samePaths = zip(prior.strokes, current.plan.strokes).allSatisfy { before, after in
        before.path.points.count == after.path.points.count
          && zip(before.path.points, after.path.points).allSatisfy { a, b in
            close(a.x, b.x) && close(a.y, b.y)
          }
      }
      // Ink location survives changes to generator IDs, pen/material styling,
      // optical provenance and registration revision within the same machine
      // coordinate frame. None of those changes establishes clean paper.
      if sameCoordinates && samePaths {
        state.blockedPlanHashes.insert(current.plan.contentHash)
        return
      }
      // Retain the existing stricter checkpoint-relative translation proof for
      // a changed coordinate frame; do not generalize arbitrary translations.
      guard permitsCheckpointTranslation, let priorSource,
        previous.toolAssembly == applicability.toolAssembly,
        previous.penContactProfile == applicability.penContactProfile,
        previous.paperContactPlane == applicability.paperContactPlane,
        previous.opticalConfiguration == applicability.opticalConfiguration,
        priorSource.kind == source.kind,
        priorSource.sourceIdentifier.components(separatedBy: "|draw-border-v1").first == sourceIdentity,
        close(old.maxX - old.minX, region.maxX - region.minX),
        close(old.maxY - old.minY, region.maxY - region.minY) else { continue }
      let checkpointTranslatedPaths = zip(prior.strokes, current.plan.strokes).allSatisfy { before, after in
        before.ordering == after.ordering && before.style == after.style
          && before.semanticRole == after.semanticRole && before.path.points.count == after.path.points.count
          && zip(before.path.points, after.path.points).allSatisfy { a, b in
            close(a.x - old.minX, b.x - region.minX) && close(a.y - old.minY, b.y - region.minY)
          }
      }
      if checkpointTranslatedPaths {
        state.blockedPlanHashes.insert(current.plan.contentHash)
        return
      }
    }
  }

  private func readiness(
    state: SourceState,
    facts: PlotterDrawingRunExternalFacts,
    controller: RunInterpreterSnapshot?
  ) -> PlotterDrawingRunReadiness {
    func unavailable(_ owner: EpisodeAuthorityID, _ reason: PlotterDrawingRunRefusalReason,
                     _ remedy: PlotterDrawingRunRemedy, _ detail: String) -> PlotterDrawingRunReadiness {
      .unavailable(.init(owner: owner, reason: reason, remedy: remedy, detail: detail))
    }
    if let lifecycle = lifecycleReadiness(state) { return lifecycle }
    if facts.environment != .live {
      return unavailable(Authority.run, .simulatedRunIsNonphysical, .switchToLiveSource, "Select the plotter camera and LIVE controller to draw.")
    }
    guard case .available = state.evidenceArchiveAvailability else {
      return unavailable(Authority.evidence, .evidenceArchiveUnavailable, .restoreEvidenceArchive, "The drawing archive could not be loaded. Open Diagnostics for the file error.")
    }
    if !facts.interactiveLearningIsComplete {
      return unavailable(Authority.learning, .learningIncomplete, .restoreLearningAuthority, "Use Saved Learning or complete Guided Learning/Setup before drawing.")
    }
    if let reason = facts.physicalPositionUnavailableReason {
      return unavailable(Authority.learning, .physicalPositionUnverified, .reestablishPositionFromCamera, reason)
    }
    if facts.acceptedMovementBounds == nil {
      return unavailable(Authority.learning, .physicalPositionUnverified, .reestablishPositionFromCamera,
        "Accepted machine movement bounds are unavailable for the observation plan.")
    }
    if !facts.paperCoverageIsCurrent {
      return unavailable(Authority.paper, .paperCoverageNotCurrent, .assertCurrentPaperCoverage, "Confirm that the current sheet covers the drawing area.")
    }
    guard let plan = facts.plan else {
      return unavailable(Authority.draft, .exactPlanUnavailable, .reviewExactPlan, "Show the portrait on the plotter video and fit its target inside the current drawing area.")
    }
    let geometry = plan.registration.applicability.machineGeometry
    let unmappedMarkedPaper = state.blockedPlanRecords.contains {
      $0.tipCalibration.applicability.machineGeometry != geometry
    } || state.blockedPlanIntents.contains {
      $0.context.registration.applicability.machineGeometry != geometry
    }
    if unmappedMarkedPaper {
      return unavailable(Authority.run, .planMayAlreadyContainInk, .replaceMarkedPaper,
        "This sheet has possible ink recorded under different machine geometry. Its location cannot be compared after axis calibration. Replace the marked sheet and record New Sheet before drawing; moving the target does not locate that old ink.")
    }
    if state.blockedPlanHashes.contains(plan.plan.contentHash) {
      return unavailable(Authority.run, .planMayAlreadyContainInk, .movePlanAwayFromPossibleInk, "This plan may already contain ink. Move the target or use a new sheet for the next drawing.")
    }
    if let detail = Self.controllerReadinessDetail(controller, requiresPenUp: false) {
      return unavailable(Authority.interpreter, .controllerUnavailable, .restoreControllerReadiness, detail)
    }
    return .ready
  }

  private func lifecycleReadiness(_ state: SourceState) -> PlotterDrawingRunReadiness? {
    if case .intentPublicationIncomplete(_, let detail) = state.evidencePersistence {
      return .unavailable(.init(owner: Authority.evidence, reason: .evidenceArchiveUnavailable,
        remedy: .restoreEvidenceArchive, detail: detail))
    }
    if admissionClosed {
      return .unavailable(.init(owner: Authority.run, reason: .admissionClosed,
        remedy: .restartApplication, detail: "The application is shutting down."))
    }
    if state.active != nil {
      return .unavailable(.init(owner: Authority.run, reason: .activeRunOwnsWorkflow,
        remedy: .waitForActiveRun, detail: "The current drawing is still running. Stop it or wait for completion."))
    }
    if state.terminal != nil {
      return .unavailable(.init(owner: Authority.run, reason: .terminalRequiresNewRunHandoff,
        remedy: .beginNewPlan, detail: "Choose New Drawing to prepare the next drawing."))
    }
    return nil
  }

  private static func controllerIsReady(
    _ snapshot: RunInterpreterSnapshot?, requiresPenUp: Bool = true
  ) -> Bool {
    controllerReadinessDetail(snapshot, requiresPenUp: requiresPenUp) == nil
  }

  private static func controllerReadinessDetail(
    _ snapshot: RunInterpreterSnapshot?, requiresPenUp: Bool
  ) -> String? {
    guard let snapshot else { return "Connect the plotter controller before drawing." }
    let machine = snapshot.machine
    if snapshot.currentOperation != .idle || machine.operationInFlight {
      return "The controller is busy. Stop or finish its current operation."
    }
    if machine.connection != .connected { return "Connect the plotter controller before drawing." }
    if machine.controllerState != .idle { return "The controller must report Idle before drawing." }
    if machine.motionGuardState != .active { return "Enable Motion before drawing." }
    if requiresPenUp && machine.penState != .up { return "Pen Up did not settle; inspect the pen before continuing." }
    if machine.position == nil { return "Refresh the controller position before drawing." }
    if machine.stickyAmbiguity != nil { return "Controller settlement is uncertain. Inspect the machine and reconnect." }
    if machine.pins.hasRelevantLimitAsserted { return "A controller limit input is asserted. Clear the limit before drawing." }
    return nil
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

private extension SamePoseFrameSample {
  var drawingRunDisplayedFrame: DisplayedFrame { DisplayedFrame(source: source, frame: frame) }
}
