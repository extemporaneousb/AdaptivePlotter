import Foundation
import PlotterModel
import PlotterRuntime

extension BoundaryActivityOperation {
  fileprivate var actionLabel: String {
    switch self {
    case .normal(let direction): "Record \(direction.displayName) boundary stop"
    case .replacement(let direction, _): "Redo \(direction.displayName) Boundary"
    case .additional(let direction, _): "Record Another \(direction.displayName) Attempt"
    }
  }
}

extension BoundaryActivityDisposition {
  fileprivate var presentationOutcome: OperationActivityOutcome {
    switch self {
    case .inProgress: .inProgress
    case .succeeded: .succeeded
    case .cancelled: .cancelled
    case .refused, .failed, .ambiguous: .needsAttention
    }
  }

  fileprivate var outcomeLabel: String {
    switch self {
    case .inProgress: "In progress"
    case .succeeded: "Succeeded"
    case .refused: "Refused"
    case .failed: "Failed"
    case .cancelled: "Cancelled"
    case .ambiguous: "Ambiguous"
    }
  }
}

extension BoundaryActivityDetail {
  fileprivate var text: String {
    switch self {
    case .message(let text): text
    case .atomicCommitRejected(let stage):
      "The staged Boundary commit was rejected at \(stage); no accepted model value changed."
    }
  }
}

extension BoundaryActivityRecovery {
  fileprivate var text: String {
    switch self {
    case .restartNormal(let direction):
      "Restart the \(direction.displayName) Boundary attempt after resolving the named fact."
    case .continueWithAcceptedFallback(let direction):
      "Continue with the accepted boundaries, or explicitly retry \(direction.displayName)."
    case .resolveStickyAmbiguity(let reason):
      "Resolve sticky ambiguity before any new physical motion: \(reason)"
    case .none: ""
    }
  }
}

/// Immutable, values-only input to Learning Path presentation. Runtime owners,
/// persistence capabilities, tasks, closures, and authority-changing methods do
/// not cross this boundary.
struct LearningPathProjectionSnapshot: Sendable {
  struct ControllerFacts: Sendable {
    let sessionEstablished: Bool
    let motionAuthorized: Bool
    let connectionText: String
    let cameraStateText: String
    let motionGuardStateText: String
    let connectionActionTitle: String
    let workbenchStatusText: String
    let machineError: String?
    let directMotionUnavailableReason: String?

    init(
      sessionEstablished: Bool = false,
      motionAuthorized: Bool = false,
      connectionText: String = "not connected",
      cameraStateText: String = "not started",
      motionGuardStateText: String = "inactive",
      connectionActionTitle: String = "Connect",
      workbenchStatusText: String = "Not connected",
      machineError: String? = nil,
      directMotionUnavailableReason: String? = nil
    ) {
      self.sessionEstablished = sessionEstablished
      self.motionAuthorized = motionAuthorized
      self.connectionText = connectionText
      self.cameraStateText = cameraStateText
      self.motionGuardStateText = motionGuardStateText
      self.connectionActionTitle = connectionActionTitle
      self.workbenchStatusText = workbenchStatusText
      self.machineError = machineError
      self.directMotionUnavailableReason = directMotionUnavailableReason
    }
  }

  struct BoundaryFacts: Sendable {
    let acceptedDirections: [BoundaryDirection]
    let allowedDirections: [BoundaryDirection]
    let isComplete: Bool
    let aggregates: [BoundaryDirection: BoundarySideAggregate]
    let attemptEvidence: [ExerciseAttemptID: BoundarySideAttemptEvidence]
    let estimatedCenter: EstimatedMachineCenter?
    let localFrame: LearnedLocalCoordinateFrame?
    let centerArrival: MachinePosition?
    let centerArrivalRetryRequired: Bool
    let currentPosition: MachinePosition?
    let centerTravelFeed: TravelFeedSelection?
    let boundaryTravelFeeds: [BoundaryDirection: TravelFeedSelection]
    let latestActivity: BoundaryActivityRecord?

    init(
      acceptedDirections: [BoundaryDirection] = [],
      allowedDirections: [BoundaryDirection] = BoundaryDirection.allCases,
      isComplete: Bool = false,
      aggregates: [BoundaryDirection: BoundarySideAggregate] = [:],
      attemptEvidence: [ExerciseAttemptID: BoundarySideAttemptEvidence] = [:],
      estimatedCenter: EstimatedMachineCenter? = nil,
      localFrame: LearnedLocalCoordinateFrame? = nil,
      centerArrival: MachinePosition? = nil,
      centerArrivalRetryRequired: Bool = false,
      currentPosition: MachinePosition? = nil,
      centerTravelFeed: TravelFeedSelection? = nil,
      boundaryTravelFeeds: [BoundaryDirection: TravelFeedSelection] = [:],
      latestActivity: BoundaryActivityRecord? = nil
    ) {
      self.acceptedDirections = acceptedDirections
      self.allowedDirections = allowedDirections
      self.isComplete = isComplete
      self.aggregates = aggregates
      self.attemptEvidence = attemptEvidence
      self.estimatedCenter = estimatedCenter
      self.localFrame = localFrame
      self.centerArrival = centerArrival
      self.centerArrivalRetryRequired = centerArrivalRetryRequired
      self.currentPosition = currentPosition
      self.centerTravelFeed = centerTravelFeed
      self.boundaryTravelFeeds = boundaryTravelFeeds
      self.latestActivity = latestActivity
    }
  }

  struct DiscoveryFacts: Sendable {
    let id: UUID
    let sequenceID: DiscoverySequenceID
    let title: String
    let state: DiscoveryTransactionState
    let currentStep: DiscoveryStep?
    let completedStepCount: Int
    let totalStepCount: Int
    let evidenceSummaries: [String]
  }

  struct CameraCalibrationFacts: Sendable {
    let accepted: MachineCameraRegistration?
    let proposed: MachineCameraRegistration?
    let acceptedIsCurrent: Bool
    let hasProposal: Bool
    let phase: CurrentCameraCalibrationPhase?
    let failureRecovery: WorkflowTelemetryRecovery?

    init(
      accepted: MachineCameraRegistration? = nil,
      proposed: MachineCameraRegistration? = nil,
      acceptedIsCurrent: Bool? = nil,
      hasProposal: Bool? = nil,
      phase: CurrentCameraCalibrationPhase? = nil,
      failureRecovery: WorkflowTelemetryRecovery? = nil
    ) {
      self.accepted = accepted
      self.proposed = proposed
      self.acceptedIsCurrent = acceptedIsCurrent ?? (accepted != nil)
      self.hasProposal = hasProposal ?? (proposed != nil)
      self.phase = phase
      self.failureRecovery = failureRecovery
    }
  }

  struct SparseCalibrationFacts: Sendable {
    let accepted: TipCameraRegistration?
    let proposed: TipCameraRegistration?
    let acceptedIsCurrent: Bool
    let phase: SparseTipCalibrationPhase
    let acceptedObservationCount: Int
    let blacklistedPositionCount: Int
    let savedCheckpointMatchesPaper: Bool

    init(
      accepted: TipCameraRegistration? = nil,
      proposed: TipCameraRegistration? = nil,
      acceptedIsCurrent: Bool? = nil,
      phase: SparseTipCalibrationPhase = .idle,
      acceptedObservationCount: Int = 0,
      blacklistedPositionCount: Int = 0,
      savedCheckpointMatchesPaper: Bool = false
    ) {
      self.accepted = accepted
      self.proposed = proposed
      self.acceptedIsCurrent = acceptedIsCurrent ?? (accepted != nil)
      self.phase = phase
      self.acceptedObservationCount = acceptedObservationCount
      self.blacklistedPositionCount = blacklistedPositionCount
      self.savedCheckpointMatchesPaper = savedCheckpointMatchesPaper
    }
  }

  struct DrawingFacts: Sendable {
    let currentStep: ObservedDrawingTrialStep
    let completedArtifactSteps: Set<ObservedDrawingTrialStep>
    let selectedDirection: BoundaryDirection
    let lineStart: MachinePosition?
    let localBaselineFrameID: String?
    let strokeSettled: Bool
    let inkStatus: String
    let assessment: DrawingTrialAssessment?
    let lastTravelFeed: TravelFeedSelection?

    init(
      currentStep: ObservedDrawingTrialStep = .chooseIsolatedLinePlan,
      completedArtifactSteps: Set<ObservedDrawingTrialStep> = [],
      selectedDirection: BoundaryDirection = .positiveX,
      lineStart: MachinePosition? = nil,
      localBaselineFrameID: String? = nil,
      strokeSettled: Bool = false,
      inkStatus: String = "no isolated-line observation yet",
      assessment: DrawingTrialAssessment? = nil,
      lastTravelFeed: TravelFeedSelection? = nil
    ) {
      self.currentStep = currentStep
      self.completedArtifactSteps = completedArtifactSteps
      self.selectedDirection = selectedDirection
      self.lineStart = lineStart
      self.localBaselineFrameID = localBaselineFrameID
      self.strokeSettled = strokeSettled
      self.inkStatus = inkStatus
      self.assessment = assessment
      self.lastTravelFeed = lastTravelFeed
    }
  }

  enum StopOwner: Hashable, Sendable {
    case pairedBoundary(ContextualStopCapabilityID, BoundaryDirection)
    case manualJog(ContextualStopCapabilityID)
    case manualDrawing(ContextualStopCapabilityID)
    case exercise(ContextualStopCapabilityID, LearningMotionAction, boundaryOwner: Bool)
    case drawingTrial(ContextualStopCapabilityID)
    case sparseTipMark(ContextualStopCapabilityID)

    var capabilityID: ContextualStopCapabilityID {
      switch self {
      case .pairedBoundary(let id, _), .exercise(let id, _, _): id
      case .manualJog(let id), .manualDrawing(let id), .drawingTrial(let id),
        .sparseTipMark(let id): id
      }
    }

    var isManual: Bool {
      switch self {
      case .manualJog, .manualDrawing: true
      default: false
      }
    }
  }

  struct OperationFacts: Sendable {
    let activeAttemptOwner: LearningPathItemID?
    let restartableItem: LearningPathItemID?
    let stopOwner: StopOwner?
    let stopDispositionLatched: Bool
    let stickyAmbiguityReason: String?
    let explorationFailure: WorkflowFailure?
    let discoveryFailure: WorkflowFailure?
    let lastStopAudit: ContextualStopAuditRecord?
    let scopedVisionActive: Bool
    let visionAnalysisActive: Bool
    let visionState: PlotterSceneAnalysisState

    init(
      activeAttemptOwner: LearningPathItemID? = nil,
      restartableItem: LearningPathItemID? = nil,
      stopOwner: StopOwner? = nil,
      stopDispositionLatched: Bool = false,
      stickyAmbiguityReason: String? = nil,
      explorationFailure: WorkflowFailure? = nil,
      discoveryFailure: WorkflowFailure? = nil,
      lastStopAudit: ContextualStopAuditRecord? = nil,
      scopedVisionActive: Bool = false,
      visionAnalysisActive: Bool = false,
      visionState: PlotterSceneAnalysisState = .stopped
    ) {
      self.activeAttemptOwner = activeAttemptOwner
      self.restartableItem = restartableItem
      self.stopOwner = stopOwner
      self.stopDispositionLatched = stopDispositionLatched
      self.stickyAmbiguityReason = stickyAmbiguityReason
      self.explorationFailure = explorationFailure
      self.discoveryFailure = discoveryFailure
      self.lastStopAudit = lastStopAudit
      self.scopedVisionActive = scopedVisionActive
      self.visionAnalysisActive = visionAnalysisActive
      self.visionState = visionState
    }
  }

  struct ResetFacts: Sendable {
    let plansByAnchor: [LearningPathItemID: LearningVacatePlan]
    let resetAllPlan: LearningVacatePlan?
    let unavailableReason: String?
    let authorityError: String?

    init(
      plansByAnchor: [LearningPathItemID: LearningVacatePlan] = [:],
      resetAllPlan: LearningVacatePlan? = nil,
      unavailableReason: String? = nil,
      authorityError: String? = nil
    ) {
      self.plansByAnchor = plansByAnchor
      self.resetAllPlan = resetAllPlan
      self.unavailableReason = unavailableReason
      self.authorityError = authorityError
    }
  }

  let source: OperatorFrameMode
  let learningEnabled: Bool
  let penInteractionCompleted: Bool
  let penActuationProfile: PenActuationProfile
  let selectedBoundaryDirection: BoundaryDirection
  let controller: ControllerFacts
  let boundary: BoundaryFacts
  let cameraCalibration: CameraCalibrationFacts
  let sparseCalibration: SparseCalibrationFacts
  let drawing: DrawingFacts
  let operations: OperationFacts
  let discovery: [DiscoverySequenceID: DiscoveryFacts]
  let startUnavailableReasons: [LearningPathItemID: String]
  let acceptedCheckpointStatus: AcceptedArtifactCheckpointStatus
  let reset: ResetFacts

  init(
    source: OperatorFrameMode = .live,
    learningEnabled: Bool = true,
    penInteractionCompleted: Bool = false,
    penActuationProfile: PenActuationProfile = .initialDefaults,
    selectedBoundaryDirection: BoundaryDirection = .positiveX,
    controller: ControllerFacts = ControllerFacts(),
    boundary: BoundaryFacts = BoundaryFacts(),
    cameraCalibration: CameraCalibrationFacts = CameraCalibrationFacts(),
    sparseCalibration: SparseCalibrationFacts = SparseCalibrationFacts(),
    drawing: DrawingFacts = DrawingFacts(),
    operations: OperationFacts = OperationFacts(),
    discovery: [DiscoverySequenceID: DiscoveryFacts] = [:],
    startUnavailableReasons: [LearningPathItemID: String] = [:],
    acceptedCheckpointStatus: AcceptedArtifactCheckpointStatus = .unavailable,
    reset: ResetFacts = ResetFacts()
  ) {
    self.source = source
    self.learningEnabled = learningEnabled
    self.penInteractionCompleted = penInteractionCompleted
    self.penActuationProfile = penActuationProfile
    self.selectedBoundaryDirection = selectedBoundaryDirection
    self.controller = controller
    self.boundary = boundary
    self.cameraCalibration = cameraCalibration
    self.sparseCalibration = sparseCalibration
    self.drawing = drawing
    self.operations = operations
    self.discovery = discovery
    self.startUnavailableReasons = startUnavailableReasons
    self.acceptedCheckpointStatus = acceptedCheckpointStatus
    self.reset = reset
  }
}

struct LearningResetSurfacePresentation: Hashable, Sendable {
  let selectedPlan: LearningVacatePlan?
  let resetAllPlan: LearningVacatePlan?
  let unavailableReason: String?
  let authorityError: String?
}

struct LearningPathProjection: Hashable, Sendable {
  let currentItemID: LearningPathItemID
  let items: [LearningPathItemPresentation]
  let selectedAction: OperatorActionPresentation
  let currentActionStrip: ExerciseActionStripPresentation?
  let contextualStop: ContextualStopPresentation?
  let resetSurface: LearningResetSurfacePresentation
}

/// Pure Learning Path presentation. It consumes one immutable snapshot and has
/// no reference to OperatorWorkspace or any runtime/persistence owner.
struct LearningPathProjector: Sendable {
  func project(
    _ snapshot: LearningPathProjectionSnapshot,
    selectedItemID: LearningPathItemID
  ) -> LearningPathProjection {
    let current = currentItemID(snapshot)
    return LearningPathProjection(
      currentItemID: current,
      items: LearningPathItemID.navigationOrder.map {
        LearningPathItemPresentation(
          id: $0,
          status: status(for: $0, current: current, snapshot: snapshot),
          summary: summary(for: $0, snapshot: snapshot),
          isRepeatable: isRepeatable($0)
        )
      },
      selectedAction: operatorAction(for: selectedItemID, current: current, snapshot: snapshot),
      currentActionStrip: actionStrip(for: current, current: current, snapshot: snapshot),
      contextualStop: contextualStop(snapshot),
      resetSurface: LearningResetSurfacePresentation(
        selectedPlan: snapshot.reset.plansByAnchor[selectedItemID],
        resetAllPlan: snapshot.reset.resetAllPlan,
        unavailableReason: snapshot.reset.unavailableReason,
        authorityError: snapshot.reset.authorityError
      )
    )
  }

  func currentItemID(_ snapshot: LearningPathProjectionSnapshot) -> LearningPathItemID {
    if let owner = snapshot.operations.activeAttemptOwner { return owner }
    if !snapshot.controller.sessionEstablished { return .stage(.connect) }
    if !snapshot.controller.motionAuthorized { return .stage(.enableMotion) }
    if !snapshot.penInteractionCompleted { return .humanGuidedDiscovery(.penInteraction) }
    if !snapshot.boundary.isComplete || snapshot.boundary.centerArrival == nil {
      return .humanGuidedDiscovery(.pairedBoundaryDiscoveryAndCentering)
    }
    if !snapshot.cameraCalibration.acceptedIsCurrent {
      return .humanGuidedDiscovery(.calibrateCameraAndVisibleCap)
    }
    if !snapshot.sparseCalibration.acceptedIsCurrent {
      return .humanGuidedDiscovery(.calibratePenContactFromSparseMarks)
    }
    if snapshot.drawing.assessment == nil {
      return .observedDrawingTrial(snapshot.drawing.currentStep)
    }
    return .observedDrawingTrial(.compareIntendedAndObservedGeometry)
  }

  private func status(
    for itemID: LearningPathItemID,
    current: LearningPathItemID,
    snapshot: LearningPathProjectionSnapshot
  ) -> LearningPathStageStatus {
    if snapshot.operations.restartableItem == itemID { return .needsAttention }
    if isComplete(itemID, snapshot: snapshot) { return .complete }
    let representsCurrentStage: Bool = if case .stage(let stage) = itemID {
      current.stage == stage
    } else { false }
    if itemID == current || representsCurrentStage {
      if itemID.stage == .humanGuidedDiscovery,
        snapshot.operations.discoveryFailure != nil || snapshot.operations.explorationFailure != nil
      { return .needsAttention }
      if itemID.stage == .observedDrawingTrials,
        snapshot.operations.explorationFailure != nil
      { return .needsAttention }
      if itemID == .stage(.connect), snapshot.controller.machineError != nil {
        return .needsAttention
      }
      return .current
    }
    return .next
  }

  private func isComplete(
    _ itemID: LearningPathItemID,
    snapshot: LearningPathProjectionSnapshot
  ) -> Bool {
    let discoveryComplete = snapshot.penInteractionCompleted
      && snapshot.boundary.centerArrival != nil
      && snapshot.cameraCalibration.acceptedIsCurrent
      && snapshot.sparseCalibration.acceptedIsCurrent
    return switch itemID {
    case .stage(.connect): snapshot.controller.sessionEstablished
    case .stage(.enableMotion):
      snapshot.controller.sessionEstablished && snapshot.controller.motionAuthorized
    case .stage(.humanGuidedDiscovery): discoveryComplete
    case .stage(.observedDrawingTrials): snapshot.drawing.assessment != nil
    case .humanGuidedDiscovery(.penInteraction): snapshot.penInteractionCompleted
    case .humanGuidedDiscovery(.pairedBoundaryDiscoveryAndCentering):
      snapshot.boundary.centerArrival != nil
    case .humanGuidedDiscovery(.calibrateCameraAndVisibleCap):
      snapshot.cameraCalibration.acceptedIsCurrent
    case .humanGuidedDiscovery(.calibratePenContactFromSparseMarks):
      snapshot.sparseCalibration.acceptedIsCurrent
    case .observedDrawingTrial(let step):
      snapshot.drawing.assessment != nil
        || (step.rawValue < snapshot.drawing.currentStep.rawValue
          && snapshot.drawing.completedArtifactSteps.contains(step))
    }
  }

  private func isRepeatable(_ itemID: LearningPathItemID) -> Bool {
    switch itemID {
    case .humanGuidedDiscovery(.penInteraction),
      .humanGuidedDiscovery(.pairedBoundaryDiscoveryAndCentering),
      .observedDrawingTrial(.compareIntendedAndObservedGeometry): true
    default: false
    }
  }

  private func summary(
    for itemID: LearningPathItemID,
    snapshot: LearningPathProjectionSnapshot
  ) -> String {
    switch itemID {
    case .stage(.connect):
      snapshot.controller.sessionEstablished
        ? (snapshot.source == .simulated
          ? "The nonphysical learning simulator session is connected."
          : "The selected controller is responsive.")
        : (snapshot.source == .simulated
          ? "Connect the nonphysical learning simulator."
          : "Select and connect one responsive controller.")
    case .stage(.enableMotion):
      snapshot.controller.motionAuthorized
        ? "Motion is enabled for typed operations."
        : "Enable Motion for this controller session."
    case .stage(.humanGuidedDiscovery):
      "Observe Pen Interaction, four paired boundaries, center arrival, camera/cap calibration, and sparse-mark pen-contact calibration."
    case .humanGuidedDiscovery(.penInteraction):
      "Identify the pen-cap color on one exact frame, then observe the physical pen UP, DOWN, then UP again."
    case .humanGuidedDiscovery(.pairedBoundaryDiscoveryAndCentering):
      "Observe both X sides and both Y sides in paired order, then move Pen Up to their estimated center."
    case .humanGuidedDiscovery(.calibrateCameraAndVisibleCap):
      "Capture five exact cap samples at normalized 10/50/90 cross positions, validate two independent holdouts, then explicitly accept or reject the all-five camera fit."
    case .humanGuidedDiscovery(.calibratePenContactFromSparseMarks):
      "Draw five centered 2 mm-radius circles with the full configured Pen Down, reveal each at safe X-max toward machine Y-zero, select its exact frozen-frame center, and accept only the smallest model that passes both holdouts."
    case .stage(.observedDrawingTrials):
      "Create one attributable line, observe actual ink, and compare geometry."
    case .observedDrawingTrial(let step): drawingActionText(step)
    }
  }
}

extension LearningPathProjector {
  private func operatorAction(
    for itemID: LearningPathItemID,
    current: LearningPathItemID,
    snapshot: LearningPathProjectionSnapshot
  ) -> OperatorActionPresentation {
    switch itemID {
    case .stage(let stage):
      return OperatorActionPresentation(
        itemID: itemID,
        stepNumber: stage.number,
        title: stage.title,
        status: status(for: itemID, current: current, snapshot: snapshot),
        instructions: [.text(summary(for: itemID, snapshot: snapshot))],
        expectedObservation: stageExpectedObservation(stage),
        evidence: stageEvidence(stage, snapshot: snapshot),
        activity: activity(for: itemID, transaction: nil, current: current, snapshot: snapshot),
        subsystemStatuses: subsystemStatuses(for: itemID, transaction: nil, snapshot: snapshot),
        actionStrip: actionStrip(for: itemID, current: current, snapshot: snapshot)
      )
    case .humanGuidedDiscovery(let step):
      let transaction = discoveryTransaction(for: step, snapshot: snapshot)
      let activeStep = transaction?.currentStep
      let feed = activeStep.flatMap { discoveryStep -> TravelFeedSelection? in
        guard case .startBoundaryJog(let direction) = discoveryStep.action else { return nil }
        return snapshot.boundary.boundaryTravelFeeds[direction]
      }
      return OperatorActionPresentation(
        itemID: itemID,
        stepNumber: step.stepNumber,
        title: step.title,
        status: status(for: itemID, current: current, snapshot: snapshot),
        participant: activeStep?.participant.displayName,
        instructions: activeStep.map { discoveryInstruction($0.action) }
          ?? discoveryReviewInstructions(step),
        expectedObservation: activeStep.map { discoveryExpectation($0.expectedEvent) }
          ?? discoveryReviewExpectation(step),
        question: activeStep.flatMap { discoveryQuestion($0.action) },
        timeline: transaction.flatMap { transaction in
          guard transaction.state == .active,
            transaction.completedStepCount < transaction.totalStepCount
          else { return nil }
          return ExerciseTimelinePresentation(
            position: transaction.completedStepCount + 1,
            total: transaction.totalStepCount,
            currentLabel: transaction.currentStep?.id ?? step.title
          )
        },
        evidence: discoveryEvidence(transaction) + protocolEvidence(step, snapshot: snapshot),
        activity: activity(for: itemID, transaction: transaction, current: current, snapshot: snapshot),
        subsystemStatuses: subsystemStatuses(
          for: itemID,
          transaction: transaction,
          snapshot: snapshot
        ),
        actionStrip: actionStrip(for: itemID, current: current, snapshot: snapshot),
        requestedFeedMMPerMinute: feed?.requestedFeedMMPerMinute,
        feedSource: feed?.source
      )
    case .observedDrawingTrial(let step):
      return OperatorActionPresentation(
        itemID: itemID,
        stepNumber: step.stepNumber,
        title: step.title,
        status: status(for: itemID, current: current, snapshot: snapshot),
        participant: drawingParticipant(step),
        instructions: [.text(drawingActionText(step))],
        expectedObservation: [.text(drawingExpectationText(step))],
        timeline: ExerciseTimelinePresentation(
          position: step.rawValue,
          total: ObservedDrawingTrialStep.allCases.count,
          currentLabel: snapshot.drawing.currentStep.title
        ),
        evidence: drawingEvidence(step, snapshot: snapshot),
        activity: activity(for: itemID, transaction: nil, current: current, snapshot: snapshot),
        subsystemStatuses: subsystemStatuses(for: itemID, transaction: nil, snapshot: snapshot),
        actionStrip: actionStrip(for: itemID, current: current, snapshot: snapshot),
        requestedFeedMMPerMinute: snapshot.drawing.lastTravelFeed?.requestedFeedMMPerMinute,
        feedSource: snapshot.drawing.lastTravelFeed?.source
      )
    }
  }

  private func contextualStop(
    _ snapshot: LearningPathProjectionSnapshot
  ) -> ContextualStopPresentation? {
    guard let owner = snapshot.operations.stopOwner,
      !snapshot.operations.stopDispositionLatched
    else { return nil }
    let detail: String = switch owner {
    case .pairedBoundary(_, let direction):
      "Stop \(direction.displayName) Boundary Discovery, wait for Idle, then commit its final controller position."
    case .manualJog:
      "Stop the active manual jog and wait for Idle."
    case .manualDrawing:
      "Stop the active manual drawing stroke, wait for Idle, and retain the controller's one Pen Up outcome."
    case .exercise(_, let action, _):
      "Stop \(action.title) and wait for the original owner to settle. No training artifact is accepted."
    case .drawingTrial:
      "Stop the drawing trial; the controller owns its single Pen Up cancellation."
    case .sparseTipMark:
      "Stop the active calibration circle. Possible ink will blacklist this physical location; it will not be redrawn automatically."
    }
    return ContextualStopPresentation(
      capabilityID: owner.capabilityID,
      title: "Stop",
      detail: detail
    )
  }

  private func actionStrip(
    for itemID: LearningPathItemID,
    current: LearningPathItemID,
    snapshot: LearningPathProjectionSnapshot
  ) -> ExerciseActionStripPresentation? {
    guard snapshot.learningEnabled else { return nil }
    let operations = snapshot.operations
    if operations.activeAttemptOwner == itemID {
      var actions: [ExerciseActionDescriptor] = []
      var penSetpointAdjustment: PenSetpointAdjustmentPresentation?
      if let stop = contextualStop(snapshot),
        let owner = operations.stopOwner,
        !owner.isManual
      {
        actions.append(
          ExerciseActionDescriptor(
            kind: .stop(stop.capabilityID),
            title: stopActionTitle(owner),
            role: .destructive
          )
        )
        return ExerciseActionStripPresentation(
          ownerID: itemID,
          actions: actions,
          mustRemainVisible: true
        )
      }
      if itemID.stage == .humanGuidedDiscovery,
        let ambiguity = operations.stickyAmbiguityReason
      {
        actions = [
          ExerciseActionDescriptor(
            kind: .start,
            title: "Machine action unavailable",
            unavailableReason: ambiguity
          )
        ]
      } else if itemID == .humanGuidedDiscovery(.calibrateCameraAndVisibleCap) {
        if snapshot.cameraCalibration.phase != nil {
          actions = [
            ExerciseActionDescriptor(
              kind: .runCameraCalibrationAndBuildProposal,
              title: "Capturing Five Cap Samples…",
              unavailableReason: "Current-camera calibration is in progress."
            )
          ]
        } else if !snapshot.cameraCalibration.hasProposal {
          actions = [
            ExerciseActionDescriptor(
              kind: .runCameraCalibrationAndBuildProposal,
              title: "Capture Five Cap Samples",
              role: .positive
            ),
            ExerciseActionDescriptor(
              kind: .rejectCameraCalibrationProposal,
              title: "Discard Cap Samples",
              role: .destructive
            ),
          ]
        } else {
          actions = [
            ExerciseActionDescriptor(
              kind: .acceptCameraCalibrationProposal,
              title: "Accept Camera and Visible-Cap Fit",
              role: .positive
            ),
            ExerciseActionDescriptor(
              kind: .rejectCameraCalibrationProposal,
              title: "Reject Camera Fit",
              role: .destructive
            ),
          ]
        }
      } else if itemID == .humanGuidedDiscovery(.calibratePenContactFromSparseMarks) {
        actions = activeSparseActions(snapshot.sparseCalibration.phase)
      } else if itemID == .observedDrawingTrial(.compareIntendedAndObservedGeometry) {
        actions = DrawingTrialAssessment.allCases.map { assessment in
          ExerciseActionDescriptor(
            kind: .recordDrawingTrialAssessment(assessment),
            title: assessment.title,
            role: assessment == .observedGeometryAccepted ? .positive : .standard
          )
        }
      } else if let transaction = snapshot.discovery.values.first(where: {
        $0.state == .active || $0.state == .cancelling
      }), let choices = transaction.currentStep?.question?.choices {
        if transaction.sequenceID == .penInteraction,
          case .awaitPhysicalPenConfirmation(let state, _) = transaction.currentStep?.action
        {
          let command: PenCommand = state == .down ? .lower : .raise
          penSetpointAdjustment = PenSetpointAdjustmentPresentation(
            command: command,
            value: snapshot.penActuationProfile.value(for: command)
          )
          actions = [
            ExerciseActionDescriptor(
              kind: .choice(.yes),
              title: "Next",
              role: .positive
            )
          ]
        } else {
          actions = choices.map { choice in
            ExerciseActionDescriptor(
              kind: .choice(choice),
              title: choice.exactPhrase,
              role: choice == .yes ? .positive : .standard
            )
          }
        }
      }
      if !operations.stopDispositionLatched && snapshot.cameraCalibration.phase == nil {
        actions.append(
          ExerciseActionDescriptor(kind: .cancel, title: "Cancel Attempt", role: .destructive)
        )
      }
      return ExerciseActionStripPresentation(
        ownerID: itemID,
        actions: actions,
        penSetpointAdjustment: penSetpointAdjustment,
        mustRemainVisible: operations.stopOwner != nil
      )
    }

    if operations.restartableItem == itemID {
      guard operations.stickyAmbiguityReason == nil else { return nil }
      return ExerciseActionStripPresentation(
        ownerID: itemID,
        actions: [ExerciseActionDescriptor(kind: .restart, title: "Restart", role: .positive)]
      )
    }

    if isComplete(itemID, snapshot: snapshot), itemID.isExercise {
      let actions: [ExerciseActionDescriptor]
      if itemID == .humanGuidedDiscovery(.pairedBoundaryDiscoveryAndCentering) {
        actions = snapshot.boundary.acceptedDirections.flatMap { direction in
          [
            ExerciseActionDescriptor(
              kind: .redoBoundary(direction),
              title: "Redo \(direction.displayName) Boundary"
            ),
            ExerciseActionDescriptor(
              kind: .recordAnotherBoundaryAttempt(direction),
              title: "Record Another \(direction.displayName) Attempt"
            ),
          ]
        }
      } else {
        actions = [ExerciseActionDescriptor(kind: .redoThisStep, title: "Redo This Step")]
          + (isRepeatable(itemID)
            ? [ExerciseActionDescriptor(kind: .recordAnotherAttempt, title: "Record Another Attempt")]
            : [])
      }
      return ExerciseActionStripPresentation(ownerID: itemID, actions: actions)
    }

    guard itemID == current else { return nil }
    let reason = snapshot.startUnavailableReasons[itemID]
    if itemID == .humanGuidedDiscovery(.pairedBoundaryDiscoveryAndCentering),
      snapshot.boundary.isComplete,
      snapshot.boundary.centerArrival == nil
    {
      if snapshot.boundary.centerArrivalRetryRequired {
        return ExerciseActionStripPresentation(
          ownerID: itemID,
          actions: [
            ExerciseActionDescriptor(
              kind: .moveToEstimatedCenter,
              title: "Retry Center Arrival",
              role: .positive,
              unavailableReason: reason
            )
          ]
        )
      }
      let centerReason = snapshot.boundary.estimatedCenter == nil
        ? (operations.discoveryFailure?.detail
          ?? "Accepted boundaries do not currently derive a valid center.")
        : reason
      return ExerciseActionStripPresentation(
        ownerID: itemID,
        actions: [
          ExerciseActionDescriptor(
            kind: .moveToEstimatedCenter,
            title: snapshot.boundary.estimatedCenter == nil
              ? "Center Derivation Needs Attention" : "Move to Estimated Center",
            role: .positive,
            unavailableReason: centerReason
          )
        ] + boundaryRepeatActions(snapshot.boundary.acceptedDirections)
      )
    }
    if case .observedDrawingTrial(let step) = itemID {
      let kind: ExerciseActionKind = switch step {
      case .chooseIsolatedLinePlan: .chooseIsolatedLinePlan(snapshot.drawing.selectedDirection)
      case .captureLocalPreLineBaseline: .captureLocalPreLineBaseline
      case .moveToLineStart: .moveToLineStart
      case .drawIsolatedLine: .drawIsolatedLine
      case .revealAndObserveNewInk: .revealAndObserveNewInk
      case .compareIntendedAndObservedGeometry: .start
      }
      return ExerciseActionStripPresentation(
        ownerID: itemID,
        actions: [
          ExerciseActionDescriptor(
            kind: kind,
            title: drawingActionTitle(step),
            role: .positive,
            unavailableReason: reason
          )
        ],
        directionSelection: step == .chooseIsolatedLinePlan
          ? ExerciseDirectionSelectionPresentation(
            purpose: .linePlan,
            selected: snapshot.drawing.selectedDirection
          ) : nil
      )
    }
    if itemID == .humanGuidedDiscovery(.calibrateCameraAndVisibleCap) {
      return ExerciseActionStripPresentation(
        ownerID: itemID,
        actions: [
          ExerciseActionDescriptor(
            kind: .runCameraCalibrationAndBuildProposal,
            title: "Capture Five Cap Samples",
            role: .positive,
            unavailableReason: reason
          )
        ]
      )
    }
    if itemID == .humanGuidedDiscovery(.calibratePenContactFromSparseMarks),
      snapshot.sparseCalibration.savedCheckpointMatchesPaper
    {
      return ExerciseActionStripPresentation(
        ownerID: itemID,
        actions: [
          ExerciseActionDescriptor(
            kind: .revalidateTipCalibrationCheckpoint,
            title: "Revalidate Saved Tip Calibration",
            role: .positive,
            unavailableReason: reason
          )
        ]
      )
    }
    if itemID == .humanGuidedDiscovery(.calibratePenContactFromSparseMarks) {
      switch snapshot.sparseCalibration.phase {
      case .possibleInkBlacklisted, .holdoutFailed, .rejected:
        return ExerciseActionStripPresentation(
          ownerID: itemID,
          actions: [
            ExerciseActionDescriptor(
              kind: .paperReplaced,
              title: "Record Paper Replacement",
              role: .positive,
              unavailableReason: reason
            )
          ]
        )
      default: break
      }
    }
    return ExerciseActionStripPresentation(
      ownerID: itemID,
      actions: [
        ExerciseActionDescriptor(
          kind: .start,
          title: itemID == .humanGuidedDiscovery(.penInteraction)
            ? "Identify Pen Cap" : "Start",
          role: .positive,
          unavailableReason: reason
        )
      ],
      directionSelection: itemID == .humanGuidedDiscovery(.pairedBoundaryDiscoveryAndCentering)
        ? ExerciseDirectionSelectionPresentation(
          purpose: .boundary,
          options: snapshot.boundary.allowedDirections,
          selected: snapshot.selectedBoundaryDirection
        ) : nil
    )
  }

  private func activeSparseActions(
    _ phase: SparseTipCalibrationPhase
  ) -> [ExerciseActionDescriptor] {
    switch phase {
    case .idle:
      [ExerciseActionDescriptor(
        kind: .createNextSparseTipMark,
        title: "Create Next 2 mm Circle",
        role: .positive
      )]
    case .preparingMark, .drawingMark, .revealing:
      [ExerciseActionDescriptor(
        kind: .createNextSparseTipMark,
        title: "Creating and Revealing Mark…",
        unavailableReason: "The supervised 2 mm calibration-circle operation is in progress."
      )]
    case .awaitingFrozenClick: []
    case .reviewingClick:
      [
        ExerciseActionDescriptor(kind: .reClickSparseTipFrame, title: "Re-click This Exact Frame"),
        ExerciseActionDescriptor(
          kind: .acceptSparseTipMark,
          title: "Accept Mark Center",
          role: .positive
        ),
      ]
    case .fittingCandidates:
      [ExerciseActionDescriptor(
        kind: .acceptTipCalibration,
        title: "Fitting Smallest Passing Model…",
        unavailableReason: "Candidate selection is in progress."
      )]
    case .reviewingFinalProposal:
      [
        ExerciseActionDescriptor(
          kind: .acceptTipCalibration,
          title: "Accept Tip Calibration",
          role: .positive
        ),
        ExerciseActionDescriptor(
          kind: .rejectTipCalibration,
          title: "Reject Tip Calibration",
          role: .destructive
        ),
      ]
    case .possibleInkBlacklisted(_, let reason), .holdoutFailed(let reason),
      .rejected(let reason):
      [
        ExerciseActionDescriptor(
          kind: .rejectTipCalibration,
          title: "No Automatic Redraw",
          unavailableReason: reason
        ),
        ExerciseActionDescriptor(
          kind: .paperReplaced,
          title: "Record Paper Replacement",
          role: .positive
        ),
      ]
    case .accepted: []
    }
  }

  private func stopActionTitle(
    _ owner: LearningPathProjectionSnapshot.StopOwner
  ) -> String {
    if case .pairedBoundary = owner { return "Stop Boundary" }
    return "Stop"
  }

  private func boundaryRepeatActions(
    _ directions: [BoundaryDirection]
  ) -> [ExerciseActionDescriptor] {
    directions.flatMap { direction in
      [
        ExerciseActionDescriptor(
          kind: .redoBoundary(direction),
          title: "Redo \(direction.displayName) Boundary"
        ),
        ExerciseActionDescriptor(
          kind: .recordAnotherBoundaryAttempt(direction),
          title: "Record Another \(direction.displayName) Attempt"
        ),
      ]
    }
  }
}

extension LearningPathProjector {
  private func activity(
    for itemID: LearningPathItemID,
    transaction: LearningPathProjectionSnapshot.DiscoveryFacts?,
    current: LearningPathItemID,
    snapshot: LearningPathProjectionSnapshot
  ) -> OperationActivityPresentation? {
    let operations = snapshot.operations
    if itemID == .humanGuidedDiscovery(.pairedBoundaryDiscoveryAndCentering),
      snapshot.boundary.centerArrivalRetryRequired,
      let failure = operations.explorationFailure
    {
      return OperationActivityPresentation(
        actor: "Controller",
        action: LearningMotionAction.moveToEstimatedCenter.title,
        outcome: .needsAttention,
        detail: [.text(failure.detail)],
        acceptedResult: [.text("All four accepted Boundary aggregates remain current.")],
        recovery: [.text("Use Retry Center Arrival; it requests only the remaining delta.")]
      )
    }
    if itemID == .humanGuidedDiscovery(.pairedBoundaryDiscoveryAndCentering),
      let activity = snapshot.boundary.latestActivity
    {
      let retained = activity.retainedRevisionIDs
        .map { $0.rawValue.uuidString.lowercased() }
        .sorted()
        .joined(separator: ", ")
      return OperationActivityPresentation(
        actor: activity.actor.rawValue,
        action: activity.operation.actionLabel,
        phase: activity.phase.rawValue,
        outcomeLabel: activity.disposition.outcomeLabel,
        outcome: activity.disposition.presentationOutcome,
        detail: [.text(activity.detail.text)],
        acceptedResult: activity.acceptedFallbackRemainsCurrent
          ? [.text("The previously accepted aggregate remains current at revision \(retained).")]
          : [],
        recovery: activity.recovery.text.isEmpty ? [] : [.text(activity.recovery.text)]
      )
    }
    if itemID == .humanGuidedDiscovery(.calibrateCameraAndVisibleCap),
      let phase = snapshot.cameraCalibration.phase
    {
      return OperationActivityPresentation(
        actor: operations.stopOwner == nil ? "Camera and learning runtime" : "Plotter controller",
        action: "Build Camera Calibration Proposal",
        phase: phase.description,
        outcome: .inProgress,
        detail: [.text("The app owns three exact non-collinear fit samples, two independent holdouts, and the all-five accepted camera/cap fit.")],
        recovery: operations.stopOwner == nil
          ? [.text("No operator calibration move or hand-drawn triangle is required.")]
          : [.text("Stop remains bound to the currently admitted Pen-Up move.")]
      )
    }
    if itemID.stage == .humanGuidedDiscovery,
      let failure = operations.explorationFailure
    {
      return OperationActivityPresentation(
        actor: operations.stopOwner == nil ? "Learning runtime" : "Plotter controller",
        action: current.title,
        outcome: .needsAttention,
        detail: [.text(failure.detail)],
        recovery: [.text(snapshot.cameraCalibration.failureRecovery.map(recoveryText)
          ?? "Resolve the named controller, camera, or exact-frame fact, then retry.")]
      )
    }
    if itemID.stage == .humanGuidedDiscovery,
      let failure = operations.discoveryFailure
    {
      return OperationActivityPresentation(
        actor: transaction?.currentStep?.participant.displayName ?? "Learning runtime",
        action: transaction?.currentStep.map { discoveryActionText($0.action) }
          ?? "Human-Guided Discovery",
        outcome: .needsAttention,
        detail: [.text(failure.detail)],
        recovery: operations.restartableItem == itemID
          ? [.text("Review the recorded outcome, then use Restart to create a new attempt.")]
          : [.text("Resolve the named controller, camera, or observation fact before continuing.")]
      )
    }
    if itemID.stage == .observedDrawingTrials,
      let failure = operations.explorationFailure
    {
      let recovery: [PresentationFragment]
      if snapshot.drawing.strokeSettled,
        snapshot.drawing.currentStep == .revealAndObserveNewInk
      {
        recovery = [.text("Ink may exist. Draw is unavailable; resolve Pen Up if needed, then return and observe the existing stroke.")]
      } else if operations.restartableItem == itemID {
        recovery = [.text("Use Restart only after the failed attempt has settled.")]
      } else {
        recovery = [.text("Resolve the named subsystem fact before continuing.")]
      }
      return OperationActivityPresentation(
        actor: drawingParticipant(snapshot.drawing.currentStep),
        action: drawingActionText(snapshot.drawing.currentStep),
        outcome: .needsAttention,
        detail: [.text(failure.detail)],
        recovery: recovery
      )
    }
    if itemID == .stage(.connect), let error = snapshot.controller.machineError {
      return OperationActivityPresentation(
        actor: "Controller session",
        action: snapshot.controller.connectionActionTitle,
        outcome: .needsAttention,
        detail: [.text(error)],
        recovery: [.text(snapshot.controller.workbenchStatusText)]
      )
    }
    if let transaction {
      switch transaction.state {
      case .active, .cancelling:
        if let step = transaction.currentStep {
          return OperationActivityPresentation(
            actor: step.participant.displayName,
            action: discoveryActionText(step.action),
            outcome: .inProgress,
            detail: operations.lastStopAudit.map {
              [.text("\($0.actor) · \($0.action) · \($0.outcome)")]
            } ?? []
          )
        }
      case .succeeded:
        return OperationActivityPresentation(
          actor: "Learning runtime",
          action: transaction.title,
          outcome: .succeeded,
          detail: transaction.evidenceSummaries.last.map { [.text($0)] } ?? []
        )
      case .cancelled:
        return OperationActivityPresentation(
          actor: operations.lastStopAudit?.actor ?? "Operator",
          action: operations.lastStopAudit?.action ?? "Cancel Attempt",
          outcome: .cancelled,
          detail: operations.lastStopAudit.map { [.text($0.outcome)] } ?? [],
          recovery: [.text("Use Restart to create a new attempt.")]
        )
      case .failed, .notStarted: break
      }
    }
    if itemID == .humanGuidedDiscovery(.pairedBoundaryDiscoveryAndCentering),
      let audit = operations.lastStopAudit
    {
      return OperationActivityPresentation(
        actor: audit.actor,
        action: audit.action,
        outcome: audit.disposition == .operatorStop ? .inProgress : .cancelled,
        detail: [.text(audit.outcome)],
        recovery: audit.disposition == .operatorStop
          ? [.text("The original owner must settle at Idle/final MPos before the controller-side commit continues.")]
          : [.text("Use Restart to create a new attempt.")]
      )
    }
    return nil
  }

  private func subsystemStatuses(
    for itemID: LearningPathItemID,
    transaction: LearningPathProjectionSnapshot.DiscoveryFacts?,
    snapshot: LearningPathProjectionSnapshot
  ) -> [SubsystemStatusPresentation] {
    let controller = snapshot.controller
    let operations = snapshot.operations
    let motionGateReason: String? = {
      if !controller.sessionEstablished {
        if let machineError = controller.machineError { return machineError }
        return snapshot.source == .simulated
          ? "Connect the learning simulator first."
          : "Select and connect one responsive controller."
      }
      if !controller.motionAuthorized { return "Enable Motion for this controller session." }
      if snapshot.cameraCalibration.phase != nil || operations.stopOwner != nil { return nil }
      return controller.directMotionUnavailableReason
    }()
    let controllerState: String
    if !controller.sessionEstablished { controllerState = "Disconnected" }
    else if !controller.motionAuthorized { controllerState = "Motion disabled" }
    else if operations.stopOwner != nil { controllerState = "Operation active" }
    else if snapshot.cameraCalibration.phase != nil {
      controllerState = "Calibration active / manual controls independent"
    }
    else if motionGateReason != nil { controllerState = "Admission blocked" }
    else { controllerState = "Idle / admissible" }

    let isBoundaryReview = itemID == .humanGuidedDiscovery(.pairedBoundaryDiscoveryAndCentering)
    let suffix = isBoundaryReview
      ? " Stage 3.2 boundary acceptance never calls Camera or Vision." : ""
    let vision: (String, Bool, SubsystemAuthorityRole, String)
    if let phase = snapshot.cameraCalibration.phase {
      vision = (
        phase.description,
        false,
        .operationOwner,
        "Current-camera calibration owns the Learning operation, but it does not gate direct manual controls. Any admitted manual move remains separately shown under its Motion owner."
      )
    } else if operations.scopedVisionActive {
      vision = operations.visionAnalysisActive
        ? ("Motion-scoped analysis · preview held", false, .advisoryEvidence,
          "One immutable frame is being analyzed off the main actor. Preview publication is held until it settles; raw camera delivery continues.")
        : ("Motion-scoped analysis · live recovery", false, .advisoryEvidence,
          "The owned movement is still active between computations. When it settles, the selected overlay settings determine whether background analysis continues.")
    } else if case .running(let cadence) = operations.visionState {
      vision = (
        "Overlay analysis · running",
        false,
        .advisoryEvidence,
        "Selected scene overlays keep newest-only analysis running at up to \(cadence.rawValue) frames per second without changing preview appearance or automatic preview publication."
      )
    } else {
      vision = ("Idle", false, .advisoryEvidence, "No foreground Vision operation is active.")
    }
    let commitActive: Bool = if case .commitBoundaryObservation = transaction?.currentStep?.action {
      true
    } else { false }
    let motionDetail = operations.stopOwner.map {
      "An admitted operation owns motion under Stop capability \($0.capabilityID.rawValue.uuidString.lowercased())."
    } ?? "No admitted operation currently owns controller motion."
    return [
      SubsystemStatusPresentation(
        id: "controller",
        subsystem: "Controller",
        state: controllerState,
        role: .motionGate,
        blocksNewMotion: motionGateReason != nil,
        detail: [.text(motionGateReason ?? "Controller facts currently admit a new direct carriage request.")]
      ),
      SubsystemStatusPresentation(
        id: "motion-owner",
        subsystem: "Motion owner",
        state: operations.stopOwner == nil ? "Unowned" : "Owned",
        role: .operationOwner,
        blocksNewMotion: operations.stopOwner != nil,
        detail: [.text(motionDetail)]
      ),
      SubsystemStatusPresentation(
        id: "camera",
        subsystem: "Camera",
        state: controller.cameraStateText,
        role: .advisoryEvidence,
        blocksNewMotion: false,
        detail: [.text("Camera state does not accept or reject a machine boundary.\(suffix)")]
      ),
      SubsystemStatusPresentation(
        id: "vision",
        subsystem: "Vision / processing",
        state: vision.0,
        role: vision.2,
        blocksNewMotion: vision.1,
        detail: [.text(vision.3 + suffix)]
      ),
      SubsystemStatusPresentation(
        id: "learning-commit",
        subsystem: "Learning commit",
        state: commitActive ? "Committing controller settlement" : "Idle",
        role: .evidenceCommit,
        blocksNewMotion: false,
        detail: [.text(isBoundaryReview
          ? "Boundary commit consumes typed direction + operator Stop + controller Idle/final MPos only."
          : "Learning commits record evidence after the owning operation settles.")]
      ),
    ]
  }
}

extension LearningPathProjector {
  private func discoveryTransaction(
    for step: HumanGuidedDiscoveryStep,
    snapshot: LearningPathProjectionSnapshot
  ) -> LearningPathProjectionSnapshot.DiscoveryFacts? {
    switch step {
    case .penInteraction: snapshot.discovery[.penInteraction]
    case .pairedBoundaryDiscoveryAndCentering:
      snapshot.discovery[sequenceID(snapshot.selectedBoundaryDirection)]
    case .calibrateCameraAndVisibleCap, .calibratePenContactFromSparseMarks: nil
    }
  }

  private func sequenceID(_ direction: BoundaryDirection) -> DiscoverySequenceID {
    switch direction {
    case .negativeX: .boundaryNegativeX
    case .positiveX: .boundaryPositiveX
    case .negativeY: .boundaryNegativeY
    case .positiveY: .boundaryPositiveY
    }
  }

  private func discoveryActionText(_ action: DiscoveryAction) -> String {
    switch action {
    case .askQuestion(let question): question.prompt
    case .awaitOperatorChoice(let question): "Choose \(question.choiceLabel) for this question."
    case .announce(let message): "Announce: \(message)"
    case .startBoundaryJog(let direction):
      "Start the logical \(direction.displayName) Boundary Discovery owner."
    case .awaitContextualStop: "Observe the boundary and use the contextual Stop."
    case .cancelBoundaryJogAndAwaitIdle:
      "Send one jog cancel and await the original motion owner."
    case .commitBoundaryObservation(let direction):
      "Commit \(direction.displayName) from typed direction + Stop + controller Idle/final MPos. Camera and Vision are not consulted."
    case .actuatePen(let command): "Command Pen \(command.commandedState.rawValue)."
    case .awaitPhysicalPenConfirmation(let state, _):
      "Confirm whether the pen is physically \(state.rawValue)."
    }
  }

  private func discoveryExpectationText(_ expectation: DiscoveryEventExpectation) -> String {
    switch expectation {
    case .questionPresented: "The contextual question is visible."
    case .operatorChoice: "One contextual YES or NO choice is recorded."
    case .announcementCompleted: "Speech output completes or reaches its advisory bound."
    case .boundaryJogStarted:
      "The logical boundary owner is active while direct controller admission remains runtime-owned."
    case .operatorStopRequested: "Stop is recorded before cancellation begins."
    case .boundaryJogCancelled: "The original motion owner reaches Idle with final MPos."
    case .boundaryObservationCommitted:
      "Controller settlement evidence and the current side aggregate commit together."
    case .penCommandSettled: "The typed pen command and dwell settle."
    case .physicalPenConfirmed: "The operator confirms the visible physical pen pose."
    }
  }

  private func drawingParticipant(_ step: ObservedDrawingTrialStep) -> String {
    switch step {
    case .chooseIsolatedLinePlan: "Operator"
    case .captureLocalPreLineBaseline, .revealAndObserveNewInk: "Camera and Vision"
    case .moveToLineStart, .drawIsolatedLine: "Plotter controller"
    case .compareIntendedAndObservedGeometry: "Operator"
    }
  }

  private func drawingActionTitle(_ step: ObservedDrawingTrialStep) -> String {
    switch step {
    case .chooseIsolatedLinePlan: "Choose Isolated Line Plan"
    case .captureLocalPreLineBaseline: "Capture Local Pre-Line Baseline"
    case .moveToLineStart: "Move to Line Start"
    case .drawIsolatedLine: "Draw Isolated Line"
    case .revealAndObserveNewInk: "Reveal and Observe New Ink"
    case .compareIntendedAndObservedGeometry: "Start"
    }
  }

  private func drawingActionText(_ step: ObservedDrawingTrialStep) -> String {
    switch step {
    case .chooseIsolatedLinePlan:
      "Choose a direction and project one local 5 mm path through the accepted tip model."
    case .captureLocalPreLineBaseline:
      "Capture one exact local baseline and record this Pen-Up reveal pose."
    case .moveToLineStart: "Move Pen Up to the recorded local line start."
    case .drawIsolatedLine: "Lower the pen, draw one 5 mm outward stroke, and raise."
    case .revealAndObserveNewInk:
      "Return Pen Up to the local reveal pose, settle, capture a newer frame, and extract new ink."
    case .compareIntendedAndObservedGeometry:
      "Record one typed comparison for this local trial; no redraw follows."
    }
  }

  private func drawingExpectationText(_ step: ObservedDrawingTrialStep) -> String {
    switch step {
    case .chooseIsolatedLinePlan:
      "One typed local line plan projected by an exact tip-model revision."
    case .captureLocalPreLineBaseline:
      "One exact pre-line frame and its Pen-Up reveal MPos."
    case .moveToLineStart: "Arrival at the local line start while Pen Up."
    case .drawIsolatedLine: "A closed controller stroke outcome; this is not yet ink proof."
    case .revealAndObserveNewInk:
      "Observed new line ink or a typed unclear/rejected observation, with no automatic redraw."
    case .compareIntendedAndObservedGeometry:
      "One typed operator assessment completes only this trial."
    }
  }

  private func recoveryText(_ recovery: WorkflowTelemetryRecovery) -> String {
    switch recovery {
    case .none: "No recovery action is required."
    case .retryCalibration:
      "Resolve the named fact, then retry the bounded five-position calibration."
    case .revalidateControllerContext:
      "Do not continue calibration. Reconnect and revalidate the named controller context fields and accepted machine artifacts first."
    case .resolveNamedFailure:
      "Resolve the named controller, camera, or exact-frame failure before retrying this action."
    }
  }

  private func checkpointText(_ status: AcceptedArtifactCheckpointStatus) -> String {
    switch status {
    case .unavailable: "No durable accepted-artifact checkpoint is available."
    case .cleared: "The durable accepted-artifact checkpoint was explicitly cleared."
    case .quarantined(let count):
      "A checkpoint containing \(count) accepted Boundary side(s) is parked until a fresh passive controller probe matches."
    case .saved(let count, let center):
      "Saved \(count) accepted Boundary side(s)\(center ? " plus center arrival" : "") atomically."
    case .restored(let count, let center, let residual):
      String(
        format: "Restored %d accepted Boundary side(s)%@ after controller-context revalidation (MPos residual %.3f mm).",
        count,
        center ? " plus center arrival" : "",
        residual
      )
    case .incompatible(let reason):
      "The accepted-artifact checkpoint remains quarantined: \(reason) No workflow or command was replayed."
    case .rejected(let reason):
      "The accepted-artifact checkpoint was rejected: \(reason) No workflow or command was replayed."
    }
  }
}

extension LearningPathProjector {
  private func stageExpectedObservation(_ stage: LearningPathStage) -> [PresentationFragment] {
    switch stage {
    case .connect: [.text("A responsive selected controller session.")]
    case .enableMotion: [.text("The current session reports Motion Enabled.")]
    case .humanGuidedDiscovery: [.cue(.up), .text("boundary, cap-map, and tip-map evidence.")]
    case .observedDrawingTrials: [.text("Observed ink and a typed geometry comparison.")]
    }
  }

  private func stageEvidence(
    _ stage: LearningPathStage,
    snapshot: LearningPathProjectionSnapshot
  ) -> [ExerciseEvidencePresentation] {
    switch stage {
    case .connect:
      [
        ExerciseEvidencePresentation(
          label: "Controller",
          fragments: [.text(snapshot.controller.connectionText)]
        ),
        ExerciseEvidencePresentation(
          label: "Accepted artifact checkpoint",
          fragments: [.text(checkpointText(snapshot.acceptedCheckpointStatus))]
        ),
      ]
    case .enableMotion:
      [ExerciseEvidencePresentation(
        label: "Motion",
        fragments: [.text(snapshot.controller.motionGuardStateText)]
      )]
    case .humanGuidedDiscovery:
      [ExerciseEvidencePresentation(
        label: "Boundary samples",
        fragments: [.text("N=\(snapshot.boundary.aggregates.count)")]
      )]
    case .observedDrawingTrials:
      [ExerciseEvidencePresentation(
        label: "Ink",
        fragments: [.text(snapshot.drawing.inkStatus)]
      )]
    }
  }

  private func discoveryReviewInstructions(
    _ step: HumanGuidedDiscoveryStep
  ) -> [PresentationFragment] {
    switch step {
    case .penInteraction:
      [.text("Identify Pen Cap, confirm"), .cue(.up), .text("then"), .cue(.down), .text("then finish"), .cue(.up)]
    case .pairedBoundaryDiscoveryAndCentering:
      [.text("Choose a direction, observe the side, then press"), .cue(.stop)]
    case .calibrateCameraAndVisibleCap:
      [.text("Capture five exact cap centers at C, X−, Y+, X+, and Y−; fit the first three, verify two holdouts, then explicitly accept or reject the all-five refit.")]
    case .calibratePenContactFromSparseMarks:
      [.text("Draw one centered 2 mm-radius circle at each cross position, reveal it Pen Up at safe X-max toward machine Y-zero, click its center on the frozen exact frame, and review the smallest passing model.")]
    }
  }

  private func discoveryReviewExpectation(
    _ step: HumanGuidedDiscoveryStep
  ) -> [PresentationFragment] {
    switch step {
    case .penInteraction: [.text("Latest accepted physical pose is"), .cue(.up)]
    case .pairedBoundaryDiscoveryAndCentering:
      [.text("Four accepted sides and one explicit arrival at the estimated machine center.")]
    case .calibrateCameraAndVisibleCap:
      [.text("Three fit samples, two independent holdouts, and one current all-five machine-camera revision.")]
    case .calibratePenContactFromSparseMarks:
      [.text("Five immutable click observations and one explicitly accepted tip-camera registration.")]
    }
  }

  private func discoveryInstruction(_ action: DiscoveryAction) -> [PresentationFragment] {
    switch action {
    case .startBoundaryJog(let direction):
      [.text("Start motion toward"), .cue(.direction(direction))]
    case .awaitContextualStop(let direction):
      [.text("Observe"), .cue(.direction(direction)), .text("and press"), .cue(.stop)]
    case .awaitPhysicalPenConfirmation(let state, _):
      [.text("Confirm the pen is physically"), .cue(state == .up ? .up : .down)]
    case .actuatePen(let command):
      [.text("Command pen"), .cue(command.commandedState == .up ? .up : .down)]
    default: [.text(discoveryActionText(action))]
    }
  }

  private func discoveryExpectation(
    _ expectation: DiscoveryEventExpectation
  ) -> [PresentationFragment] {
    switch expectation {
    case .operatorChoice:
      [.cue(.yes), .text("or"), .cue(.no), .text("is recorded for this question.")]
    case .operatorStopRequested: [.cue(.stop), .text("is latched before cancellation.")]
    case .physicalPenConfirmed(let state, _):
      [.text("The operator confirms"), .cue(state == .up ? .up : .down)]
    default: [.text(discoveryExpectationText(expectation))]
    }
  }

  private func discoveryQuestion(_ action: DiscoveryAction) -> ExerciseQuestionPresentation? {
    switch action {
    case .awaitOperatorChoice(let question):
      ExerciseQuestionPresentation(prompt: [.text(question.prompt)], choices: question.choices)
    case .awaitPhysicalPenConfirmation(let state, let question):
      ExerciseQuestionPresentation(
        prompt: [
          .text(question.prompt),
          .text("Required physical pose:"),
          .cue(state == .up ? .up : .down),
        ],
        choices: question.choices
      )
    default: nil
    }
  }

  private func discoveryEvidence(
    _ transaction: LearningPathProjectionSnapshot.DiscoveryFacts?
  ) -> [ExerciseEvidencePresentation] {
    transaction?.evidenceSummaries.enumerated().map { index, evidence in
      ExerciseEvidencePresentation(
        label: "Evidence \(index + 1)",
        fragments: [.text(evidence)]
      )
    } ?? []
  }

  private func protocolEvidence(
    _ step: HumanGuidedDiscoveryStep,
    snapshot: LearningPathProjectionSnapshot
  ) -> [ExerciseEvidencePresentation] {
    switch step {
    case .penInteraction: return []
    case .pairedBoundaryDiscoveryAndCentering:
      var evidence: [ExerciseEvidencePresentation] = []
      if let localFrame = snapshot.boundary.localFrame,
        let center = snapshot.boundary.estimatedCenter,
        let localCenter = try? localFrame.localPoint(fromRaw: center.point)
      {
        evidence.append(ExerciseEvidencePresentation(
          label: "Learned local coordinate frame (mm)",
          fragments: [.text(String(
            format: "origin at accepted X−/Y− · X 0 ... %.3f · Y 0 ... %.3f · center %.3f, %.4f",
            localFrame.xSpanMM,
            localFrame.ySpanMM,
            localCenter.x,
            localCenter.y
          ))]
        ))
      } else {
        evidence.append(ExerciseEvidencePresentation(
          label: "Controller coordinate frame",
          fragments: [.text("Raw Controller MPos is millimetre-valued relative to the controller's current origin; positive and negative signs are not paper-local coordinates. All four accepted side aggregates are required before a learned local frame exists.")]
        ))
      }
      evidence.append(contentsOf: BoundaryDirection.allCases.compactMap { direction in
        guard let aggregate = snapshot.boundary.aggregates[direction],
          let attemptID = aggregate.includedAttemptIDs.last,
          let attempt = snapshot.boundary.attemptEvidence[attemptID]
        else { return nil }
        return ExerciseEvidencePresentation(
          label: "Raw Controller MPos · \(direction.displayName)",
          fragments: [.text(String(
            format: "X %.3f Y %.3f · aggregate %.3f mm · N=%d · revision %@",
            attempt.finalPosition.point.x,
            attempt.finalPosition.point.y,
            aggregate.estimateMM,
            aggregate.validSampleCount,
            aggregate.revisionID.rawValue.uuidString.lowercased()
          ))]
        )
      })
      if let center = snapshot.boundary.estimatedCenter {
        evidence.append(ExerciseEvidencePresentation(
          label: snapshot.boundary.localFrame == nil
            ? "Estimated raw machine center" : "Raw Controller MPos center provenance",
          fragments: [.text(String(
            format: "X %.3f Y %.3f · spans X %.3f mm Y %.3f mm · %@",
            center.point.x,
            center.point.y,
            center.xSpanMM,
            center.ySpanMM,
            center.estimatorRevision
          ))]
        ))
        evidence.append(ExerciseEvidencePresentation(
          label: "Center travel",
          fragments: [.text(centerTravelDescription(center: center, snapshot: snapshot))]
        ))
      }
      return evidence
    case .calibrateCameraAndVisibleCap:
      let registration = snapshot.cameraCalibration.proposed ?? snapshot.cameraCalibration.accepted
      return [
        ExerciseEvidencePresentation(
          label: "Five-position cap calibration",
          fragments: [.text(registration.map {
            "\($0.fitCorrespondenceProvenance.count) fit samples · \($0.holdoutCorrespondenceProvenance.count) independent holdouts · \($0.correspondenceFrameIDs.count) exact frames"
          } ?? "not captured")]
        ),
        ExerciseEvidencePresentation(
          label: snapshot.cameraCalibration.proposed == nil
            ? "Accepted camera/cap fit" : "Staged camera/cap fit",
          fragments: [.text(registration.map {
            String(
              format: "holdouts %.3f / %.3f px · limit %.3f px · all-five uncertainty %.3f px",
              $0.holdoutResidualPixels[0],
              $0.holdoutResidualPixels[1],
              $0.maximumHoldoutResidualPixels,
              $0.uncertaintyPixels
            )
          } ?? "not fitted")]
        ),
      ]
    case .calibratePenContactFromSparseMarks:
      let proposal = snapshot.sparseCalibration.proposed ?? snapshot.sparseCalibration.accepted
      return [
        ExerciseEvidencePresentation(
          label: "Sparse 2 mm-radius circles",
          fragments: [.text(
            "\(snapshot.sparseCalibration.acceptedObservationCount)/5 accepted · \(snapshot.sparseCalibration.blacklistedPositionCount) blacklisted · \(String(describing: snapshot.sparseCalibration.phase))"
          )]
        ),
        ExerciseEvidencePresentation(
          label: "Smallest passing model",
          fragments: [.text(proposal.map { proposal in
            let holdouts = proposal.modelForm == .constantCameraPixelCorrection
              ? proposal.modelSelectionEvidence.constantHoldouts
              : proposal.modelSelectionEvidence.affineHoldouts
            return "\(proposal.modelForm.rawValue) · holdouts \(holdouts.map { String(format: "%.3f px", $0.residualPixels) }.joined(separator: ", ")) · uncertainty \(String(format: "%.3f px", proposal.uncertainty.maximumResidualPixels))"
          } ?? "Tip not calibrated")]
        ),
      ]
    }
  }

  private func centerTravelDescription(
    center: EstimatedMachineCenter,
    snapshot: LearningPathProjectionSnapshot
  ) -> String {
    guard let current = snapshot.boundary.currentPosition else {
      return "current MPos unavailable"
    }
    let feed = snapshot.boundary.centerTravelFeed
    let source = feed.map { selection in
      switch selection.source {
      case .controllerReportedCeiling: "Controller-reported ceiling"
      case .existingFallback: "Existing fallback"
      }
    } ?? "unavailable"
    return String(
      format: "current X %.3f Y %.3f · delta X %.3f Y %.3f · feed %@ · source %@",
      current.point.x,
      current.point.y,
      center.point.x - current.point.x,
      center.point.y - current.point.y,
      feed.map { String(format: "%.0f mm/min", $0.requestedFeedMMPerMinute) }
        ?? "not selected",
      source
    )
  }

  private func drawingEvidence(
    _ step: ObservedDrawingTrialStep,
    snapshot: LearningPathProjectionSnapshot
  ) -> [ExerciseEvidencePresentation] {
    switch step {
    case .chooseIsolatedLinePlan:
      [ExerciseEvidencePresentation(
        label: "Line plan",
        fragments: [.text(snapshot.drawing.lineStart.map {
          String(
            format: "%@ from X %.3f Y %.3f",
            snapshot.drawing.selectedDirection.displayName,
            $0.point.x,
            $0.point.y
          )
        } ?? "not chosen")]
      )]
    case .captureLocalPreLineBaseline:
      [ExerciseEvidencePresentation(
        label: "Local pre-line baseline",
        fragments: [.text(snapshot.drawing.localBaselineFrameID ?? "not captured")]
      )]
    case .moveToLineStart:
      [ExerciseEvidencePresentation(
        label: "Line start",
        fragments: [.text(snapshot.drawing.lineStart.map {
          String(format: "X %.3f Y %.3f", $0.point.x, $0.point.y)
        } ?? "not reached")]
      )]
    case .drawIsolatedLine:
      [ExerciseEvidencePresentation(
        label: "Controller",
        fragments: [.text(snapshot.drawing.strokeSettled ? "settled" : "not settled")]
      )]
    case .revealAndObserveNewInk:
      [ExerciseEvidencePresentation(
        label: "Ink",
        fragments: [.text(snapshot.drawing.inkStatus)]
      )]
    case .compareIntendedAndObservedGeometry:
      [ExerciseEvidencePresentation(
        label: "Comparison",
        fragments: [.text(snapshot.drawing.assessment?.title ?? "not recorded")]
      )]
    }
  }
}
