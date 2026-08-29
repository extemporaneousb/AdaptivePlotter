import Foundation
import PlotterModel
import PlotterRuntime

enum ExactWorkflowVisionOwner: String, CaseIterable, Hashable, Sendable {
  case penCapAppearance
  case cameraCalibration
  case sparseTipCalibration
  case observedDrawingTrial
  case drawingStudio

  var operatorLabel: String {
    switch self {
    case .penCapAppearance: "pen-cap identification"
    case .cameraCalibration: "camera calibration"
    case .sparseTipCalibration: "pen-tip calibration"
    case .observedDrawingTrial: "Drawing Border validation"
    case .drawingStudio: "Drawing Studio validation"
    }
  }
}

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
    let cameraStateText: String
    let machineError: String?
    let controllerTravelUnavailableReason: String?

    init(
      sessionEstablished: Bool = false,
      motionAuthorized: Bool = false,
      cameraStateText: String = "not started",
      machineError: String? = nil,
      controllerTravelUnavailableReason: String? = nil
    ) {
      self.sessionEstablished = sessionEstablished
      self.motionAuthorized = sessionEstablished && motionAuthorized
      self.cameraStateText = cameraStateText
      self.machineError = machineError
      self.controllerTravelUnavailableReason = controllerTravelUnavailableReason
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
    let collectedClickCount: Int
    let blacklistedPositionCount: Int
    let savedCheckpointMatchesPaper: Bool

    init(
      accepted: TipCameraRegistration? = nil,
      proposed: TipCameraRegistration? = nil,
      acceptedIsCurrent: Bool? = nil,
      phase: SparseTipCalibrationPhase = .idle,
      acceptedObservationCount: Int = 0,
      collectedClickCount: Int = 0,
      blacklistedPositionCount: Int = 0,
      savedCheckpointMatchesPaper: Bool = false
    ) {
      self.accepted = accepted
      self.proposed = proposed
      self.acceptedIsCurrent = acceptedIsCurrent ?? (accepted != nil)
      self.phase = phase
      self.acceptedObservationCount = acceptedObservationCount
      self.collectedClickCount = collectedClickCount
      self.blacklistedPositionCount = blacklistedPositionCount
      self.savedCheckpointMatchesPaper = savedCheckpointMatchesPaper
    }
  }

  struct DrawingFacts: Sendable {
    let currentStep: ObservedDrawingTrialStep
    let drawingBorderPath: [MachinePosition]
    let localBaselineFrameID: String?
    let drawingBorderSettled: Bool
    let inkStatus: String
    let assessment: DrawingTrialAssessment?
    let lastTravelFeed: TravelFeedSelection?

    init(
      currentStep: ObservedDrawingTrialStep = .chooseDrawingBorderPlan,
      drawingBorderPath: [MachinePosition] = [],
      localBaselineFrameID: String? = nil,
      drawingBorderSettled: Bool = false,
      inkStatus: String = "no Drawing Border observation yet",
      assessment: DrawingTrialAssessment? = nil,
      lastTravelFeed: TravelFeedSelection? = nil
    ) {
      self.currentStep = currentStep
      self.drawingBorderPath = drawingBorderPath
      self.localBaselineFrameID = localBaselineFrameID
      self.drawingBorderSettled = drawingBorderSettled
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
    case sparseTipBatch(ContextualStopCapabilityID)

    var capabilityID: ContextualStopCapabilityID {
      switch self {
      case .pairedBoundary(let id, _), .exercise(let id, _, _): id
      case .manualJog(let id), .manualDrawing(let id), .drawingTrial(let id),
        .sparseTipBatch(let id): id
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
    let exactWorkflowVisionOwner: ExactWorkflowVisionOwner?
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
      exactWorkflowVisionOwner: ExactWorkflowVisionOwner? = nil,
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
      self.exactWorkflowVisionOwner = exactWorkflowVisionOwner
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

  struct SavedTrainingFacts: Sendable {
    let checkpointID: UUID
    let artifactSummary: String
    let opticalComparison: String

    init(
      checkpointID: UUID,
      artifactSummary: String,
      opticalComparison: String
    ) {
      self.checkpointID = checkpointID
      self.artifactSummary = artifactSummary
      self.opticalComparison = opticalComparison
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
  let savedTrainingCandidate: SavedTrainingFacts?
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
    savedTrainingCandidate: SavedTrainingFacts? = nil,
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
    self.savedTrainingCandidate = savedTrainingCandidate
    self.reset = reset
  }
}

struct LearningResetSurfacePresentation: Hashable, Sendable {
  let selectedPlan: LearningVacatePlan?
  let unavailableReason: String?
  let authorityError: String?
}

struct LearningPathMenuPresentation: Hashable, Sendable {
  let resetAllPlan: LearningVacatePlan?
}

struct LearningPathProjection: Hashable, Sendable {
  let currentItemID: LearningPathItemID
  let items: [LearningPathItemPresentation]
  let selectedAction: OperatorActionPresentation
  let currentActionStrip: ExerciseActionStripPresentation?
  let contextualStop: ContextualStopPresentation?
  let resetSurface: LearningResetSurfacePresentation
  let menu: LearningPathMenuPresentation
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
        unavailableReason: snapshot.reset.unavailableReason,
        authorityError: snapshot.reset.authorityError
      ),
      menu: LearningPathMenuPresentation(resetAllPlan: snapshot.reset.resetAllPlan)
    )
  }

  func currentItemID(_ snapshot: LearningPathProjectionSnapshot) -> LearningPathItemID {
    if let owner = snapshot.operations.activeAttemptOwner { return owner }
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
    return .observedDrawingTrial(.chooseDrawingBorderPlan)
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
      step == .chooseDrawingBorderPlan && snapshot.drawing.assessment != nil
    }
  }

  private func isRepeatable(_ itemID: LearningPathItemID) -> Bool {
    switch itemID {
    case .humanGuidedDiscovery(.penInteraction),
      .humanGuidedDiscovery(.pairedBoundaryDiscoveryAndCentering): true
    default: false
    }
  }

  private func summary(
    for itemID: LearningPathItemID,
    snapshot: LearningPathProjectionSnapshot
  ) -> String {
    switch itemID {
    case .stage(.humanGuidedDiscovery):
      "Identify and calibrate the pen, measure all four drawing-boundary sides, move to the estimated center, calibrate the camera from five pen-cap positions, and calibrate the pen tip from four corner marks."
    case .humanGuidedDiscovery(.penInteraction):
      "Identify the pen cap on one frozen frame, then set and confirm the physical Pen Up, Pen Down, and final Pen Up positions."
    case .humanGuidedDiscovery(.pairedBoundaryDiscoveryAndCentering):
      "Measure the X−, X+, Y−, and Y+ drawing-boundary sides with operator Stop, then move Pen Up to their estimated center."
    case .humanGuidedDiscovery(.calibrateCameraAndVisibleCap):
      "Run five Pen-Up cap measurements at the center and four axis positions. Three measurements fit the camera calibration and two independently check it before review."
    case .humanGuidedDiscovery(.calibratePenContactFromSparseMarks):
      "Draw four 2 mm-radius calibration circles whose centers are 10 mm inside the accepted Drawing Boundary. After one final Pen-Up reveal, click the four circle centers on the unchanged frame and review the proposed pen-tip calibration."
    case .stage(.observedDrawingTrials):
      "Use the accepted pen-tip calibration to preview, draw, observe, and compare the Drawing Border through the four calibration-circle centers."
    case .observedDrawingTrial(.chooseDrawingBorderPlan):
      "Press Draw and Validate Drawing Border once. The app previews the Drawing Border, captures a baseline, draws the perimeter, returns Pen Up for a new image, and compares the observed ink with the plan."
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
      let isVisibleTrial = step == .chooseDrawingBorderPlan
      return OperatorActionPresentation(
        itemID: itemID,
        stepNumber: step.stepNumber,
        title: itemID.title,
        status: status(for: itemID, current: current, snapshot: snapshot),
        participant: isVisibleTrial ? "Application" : drawingParticipant(step),
        instructions: [.text(isVisibleTrial
          ? "Press Draw and Validate Drawing Border once for one closed Drawing Border. Keep Stop available during motion; planning, preview, baseline capture, drawing, reveal, Vision analysis, and comparison then continue without another approval."
          : drawingActionText(step))],
        expectedObservation: [.text(isVisibleTrial
          ? "The predicted cyan Drawing Border appears before motion, then observed white ink and orange residuals appear on the exact post-frame image."
          : drawingExpectationText(step))],
        timeline: ExerciseTimelinePresentation(
          position: snapshot.drawing.currentStep.rawValue,
          total: ObservedDrawingTrialStep.allCases.count,
          currentLabel: snapshot.drawing.currentStep.title
        ),
        evidence: isVisibleTrial
          ? drawingTrialEvidence(snapshot: snapshot)
          : drawingEvidence(step, snapshot: snapshot),
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
      "Stop the \(direction.displayName) Drawing Boundary search. The app will wait for controller Idle and record the final position."
    case .manualJog:
      "Stop the active manual jog and wait for Idle."
    case .manualDrawing:
      "Stop the active manual drawing stroke, wait for Idle, and retain the controller's one Pen Up outcome."
    case .exercise(_, let action, _):
      "Stop \(action.title) and wait for the active operation to settle. No Learning Path result will be accepted."
    case .drawingTrial:
      "Stop Drawing Border validation. The active drawing operation will cancel once and settle Pen Up."
    case .sparseTipBatch:
      "Stop the four-circle calibration. Any location where ink may exist will be excluded from automatic redraw."
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
    if snapshot.savedTrainingCandidate != nil {
      guard itemID == current else { return nil }
      return ExerciseActionStripPresentation(
        ownerID: itemID,
        actions: [
          ExerciseActionDescriptor(
            kind: .useSavedTraining,
            title: LearningPathTerminology.Action.useSavedLearning,
            role: .positive
          ),
          ExerciseActionDescriptor(
            kind: .startNewLearning,
            title: LearningPathTerminology.Action.startNewLearning,
            role: .standard
          ),
        ],
        mustRemainVisible: true
      )
    }
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
      if itemID == .observedDrawingTrial(.chooseDrawingBorderPlan) {
        return ExerciseActionStripPresentation(
          ownerID: itemID,
          actions: [
            ExerciseActionDescriptor(
              kind: .start,
              title: "\(LearningPathTerminology.Action.drawAndValidateDrawingBorder)…",
              unavailableReason: "Drawing Border validation is in progress."
            )
          ],
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
              title: "Running Five-Position Camera Calibration…",
              unavailableReason: "Camera calibration is in progress."
            )
          ]
        } else if !snapshot.cameraCalibration.hasProposal {
          actions = [
            ExerciseActionDescriptor(
              kind: .runCameraCalibrationAndBuildProposal,
              title: LearningPathTerminology.Action.runCameraCalibration,
              role: .positive
            ),
            ExerciseActionDescriptor(
              kind: .rejectCameraCalibrationProposal,
              title: LearningPathTerminology.Action.discardCameraSamples,
              role: .destructive
            ),
          ]
        } else {
          actions = [
            ExerciseActionDescriptor(
              kind: .acceptCameraCalibrationProposal,
              title: LearningPathTerminology.Action.acceptCameraCalibration,
              role: .positive
            ),
            ExerciseActionDescriptor(
              kind: .rejectCameraCalibrationProposal,
              title: LearningPathTerminology.Action.rejectCameraCalibration,
              role: .destructive
            ),
          ]
        }
      } else if itemID == .humanGuidedDiscovery(.calibratePenContactFromSparseMarks) {
        actions = activeSparseActions(
          snapshot.sparseCalibration.phase,
          collectedClickCount: snapshot.sparseCalibration.collectedClickCount
        )
      } else if let transaction = snapshot.discovery.values.first(where: {
        $0.state == .active || $0.state == .cancelling
      }), let choices = transaction.currentStep?.question?.choices {
        if transaction.sequenceID == .penInteraction,
          case .awaitPhysicalPenConfirmation(let state, _) = transaction.currentStep?.action
        {
          let command: PenCommand = state == .down ? .lower : .raise
          penSetpointAdjustment = PenSetpointAdjustmentPresentation(
            command: command,
            value: snapshot.penActuationProfile.value(for: command),
            unavailableReason: snapshot.startUnavailableReasons[itemID]
          )
          actions = [
            ExerciseActionDescriptor(
              kind: .choice(.yes),
              title: state == .up
                ? LearningPathTerminology.Action.confirmPenUp
                : LearningPathTerminology.Action.confirmPenDown,
              role: .positive,
              unavailableReason: snapshot.startUnavailableReasons[itemID]
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
        actions: [ExerciseActionDescriptor(
          kind: .restart,
          title: itemID == .observedDrawingTrial(.chooseDrawingBorderPlan)
            ? "Retry Drawing Border Validation" : "Restart Attempt",
          role: .positive
        )]
      )
    }

    if isComplete(itemID, snapshot: snapshot), itemID.isExercise {
      if itemID == .observedDrawingTrial(.chooseDrawingBorderPlan) { return nil }
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
    if itemID == .observedDrawingTrial(.chooseDrawingBorderPlan) {
      let title = switch snapshot.drawing.currentStep {
      case .chooseDrawingBorderPlan: LearningPathTerminology.Action.drawAndValidateDrawingBorder
      case .revealAndObserveNewInk: "Resume Drawing Border Observation"
      case .compareIntendedAndObservedGeometry: "Complete Drawing Border Comparison"
      case .captureLocalPreFrameBaseline, .moveToDrawingBorderStart, .drawDrawingBorder:
        "Resume Drawing Border Validation"
      }
      return ExerciseActionStripPresentation(
        ownerID: itemID,
        actions: [
          ExerciseActionDescriptor(
            kind: .start,
            title: title,
            role: .positive,
            unavailableReason: reason
          )
        ]
      )
    }
    if itemID == .humanGuidedDiscovery(.calibrateCameraAndVisibleCap) {
      return ExerciseActionStripPresentation(
        ownerID: itemID,
        actions: [
          ExerciseActionDescriptor(
            kind: .runCameraCalibrationAndBuildProposal,
            title: LearningPathTerminology.Action.runCameraCalibration,
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
            title: "Revalidate Saved Pen-Tip Calibration",
            role: .positive,
            unavailableReason: reason
          )
        ]
      )
    }
    if itemID == .humanGuidedDiscovery(.calibratePenContactFromSparseMarks) {
      switch snapshot.sparseCalibration.phase {
      case .possibleInkBlacklisted:
        return ExerciseActionStripPresentation(
          ownerID: itemID,
          actions: [
            ExerciseActionDescriptor(
              kind: .paperReplaced,
              title: "Record Paper Replacement",
              role: .positive
            )
          ]
        )
      default: break
      }
      return ExerciseActionStripPresentation(
        ownerID: itemID,
        actions: [
          ExerciseActionDescriptor(
            kind: .drawFourCornerTipCircles,
            title: LearningPathTerminology.Action.drawCalibrationCircles,
            role: .positive,
            unavailableReason: reason
          )
        ]
      )
    }
    return ExerciseActionStripPresentation(
      ownerID: itemID,
      actions: [
        ExerciseActionDescriptor(
          kind: .start,
          title: itemID == .humanGuidedDiscovery(.penInteraction)
            ? LearningPathTerminology.Action.identifyPenCap
            : "Move Toward \(snapshot.selectedBoundaryDirection.displayName)",
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
    _ phase: SparseTipCalibrationPhase,
    collectedClickCount: Int
  ) -> [ExerciseActionDescriptor] {
    switch phase {
    case .idle:
      [ExerciseActionDescriptor(
        kind: .drawFourCornerTipCircles,
        title: LearningPathTerminology.Action.drawCalibrationCircles,
        role: .positive
      )]
    case .drawingBatch:
      [ExerciseActionDescriptor(
        kind: .drawFourCornerTipCircles,
        title: "Drawing Four Calibration Circles…",
        unavailableReason: "The four-circle calibration is in progress."
      )]
    case .revealingBatch:
      [ExerciseActionDescriptor(
        kind: .drawFourCornerTipCircles,
        title: "Capturing Calibration Reveal…",
        unavailableReason: "The final Pen-Up calibration reveal is in progress."
      )]
    case .awaitingFrozenClicks:
      if collectedClickCount == 0 {
        []
      } else {
        [
          ExerciseActionDescriptor(
            kind: .undoLastSparseTipClick,
            title: "Undo Last Click"
          ),
          ExerciseActionDescriptor(
            kind: .clearSparseTipClicks,
            title: "Clear Clicks on This Frame"
          ),
        ]
      }
    case .fittingModel:
      [ExerciseActionDescriptor(
        kind: .retryTipCalibrationCommit,
        title: "Fitting Tip Calibration…",
        unavailableReason: "The four observations are being created and fitted."
      )]
    case .reviewingModel:
      [
        ExerciseActionDescriptor(
          kind: .acceptTipCalibrationProposal,
          title: LearningPathTerminology.Action.acceptPenTipCalibration,
          role: .positive
        ),
        ExerciseActionDescriptor(
          kind: .undoLastSparseTipClick,
          title: "Undo Last Click"
        ),
        ExerciseActionDescriptor(
          kind: .clearSparseTipClicks,
          title: "Clear Clicks on This Frame"
        ),
        ExerciseActionDescriptor(
          kind: .rejectTipCalibrationProposal,
          title: LearningPathTerminology.Action.rejectPenTipCalibration,
          role: .destructive
        ),
      ]
    case .committingModel:
      [ExerciseActionDescriptor(
        kind: .retryTipCalibrationCommit,
        title: "Retry Pen-Tip Calibration Save",
        role: .positive
      )]
    case .possibleInkBlacklisted:
      [
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
    if case .pairedBoundary = owner { return "Stop Boundary Search" }
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
        actor: operations.stopOwner == nil ? "Camera and application" : "Plotter controller",
        action: "Build Camera Calibration",
        phase: phase.description,
        outcome: .inProgress,
        detail: [.text("The app is collecting three exact fit measurements and two independent check measurements for one five-position camera calibration.")],
        recovery: operations.stopOwner == nil
          ? [.text("No operator calibration move or hand-drawn triangle is required.")]
          : [.text("Stop remains available for the active Pen-Up move.")]
      )
    }
    if itemID == .observedDrawingTrial(.chooseDrawingBorderPlan),
      operations.activeAttemptOwner == itemID
    {
      let phase = snapshot.drawing.currentStep
      return OperationActivityPresentation(
        actor: drawingParticipant(phase),
        action: drawingActionText(phase),
        phase: "Phase \(phase.rawValue) of \(ObservedDrawingTrialStep.allCases.count)",
        outcome: .inProgress,
        detail: [.text(phase == .revealAndObserveNewInk
          && operations.exactWorkflowVisionOwner == .observedDrawingTrial
          ? "Vision is comparing the validation baseline with the strictly newer post-drawing image now."
          : "Drawing Border validation is progressing automatically; no additional approval is waiting.")],
        recovery: operations.stopOwner == nil
          ? [] : [.text("Stop remains available for the active motion.")]
      )
    }
    if itemID.stage == .humanGuidedDiscovery,
      let failure = operations.explorationFailure
    {
      return OperationActivityPresentation(
        actor: operations.stopOwner == nil ? "Application" : "Plotter controller",
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
        actor: transaction?.currentStep?.participant.displayName ?? "Application",
        action: transaction?.currentStep.map { discoveryActionText($0.action) }
          ?? LearningPathTerminology.Stage.plotterCalibration,
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
      if snapshot.drawing.drawingBorderSettled,
        snapshot.drawing.currentStep == .revealAndObserveNewInk
      {
        recovery = [.text("Ink may exist. Draw is unavailable; resolve Pen Up if needed, then return and observe the existing frame.")]
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
          actor: "Application",
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
          ? [.text("The active motion must settle at Idle with final MPos before the Drawing Boundary result can be recorded.")]
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
      return controller.controllerTravelUnavailableReason
    }()
    let controllerState: String
    if !controller.sessionEstablished { controllerState = "Disconnected" }
    else if !controller.motionAuthorized { controllerState = "Motion disabled" }
    else if operations.stopOwner != nil { controllerState = "Operation active" }
    else if snapshot.cameraCalibration.phase != nil {
      controllerState = "Calibration active / manual controls independent"
    }
    else if motionGateReason != nil { controllerState = "Blocked" }
    else { controllerState = "Idle / ready" }

    let isBoundaryReview = itemID == .humanGuidedDiscovery(.pairedBoundaryDiscoveryAndCentering)
    let suffix = isBoundaryReview
      ? " Drawing Boundary measurements do not use Camera or Vision." : ""
    let vision: (String, Bool, SubsystemAuthorityRole, String)
    if let owner = operations.exactWorkflowVisionOwner {
      vision = exactWorkflowVisionStatus(owner)
    } else if let phase = snapshot.cameraCalibration.phase {
      vision = (
        phase.description,
        false,
        .operationOwner,
        "Camera calibration is using the Learning Path operation slot. Direct manual controls remain independent, and any active manual move is shown separately."
      )
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
    let motionDetail = operations.stopOwner.map { _ in
      "One active operation controls motion and exposes its matching Stop action."
    } ?? "No Learning Path operation is using controller motion."
    return [
      SubsystemStatusPresentation(
        id: "controller",
        subsystem: "Controller",
        state: controllerState,
        role: .motionGate,
        blocksNewMotion: motionGateReason != nil,
        detail: [.text(motionGateReason ?? "The controller is ready for a new direct carriage request.")]
      ),
      SubsystemStatusPresentation(
        id: "motion-owner",
        subsystem: "Active motion",
        state: operations.stopOwner == nil ? "None" : "In progress",
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
        subsystem: "Learning Path result",
        state: commitActive ? "Recording boundary result" : "Idle",
        role: .evidenceCommit,
        blocksNewMotion: false,
        detail: [.text(isBoundaryReview
          ? "The Drawing Boundary result uses the selected direction, operator Stop, controller Idle, and final MPos only."
          : "A Learning Path result is recorded only after its active operation settles.")]
      ),
    ]
  }

  private func exactWorkflowVisionStatus(
    _ owner: ExactWorkflowVisionOwner
  ) -> (String, Bool, SubsystemAuthorityRole, String) {
    switch owner {
    case .penCapAppearance:
      (
        "Pen-cap appearance Vision · active",
        false,
        .operationOwner,
        "Vision is inspecting the exact frozen frame used to identify the visible cap appearance."
      )
    case .cameraCalibration:
      (
        "Camera calibration Vision · active",
        false,
        .operationOwner,
        "Vision is inspecting exact current-camera cap frames for the active calibration sample."
      )
    case .sparseTipCalibration:
      (
        "Sparse-tip calibration Vision · active",
        false,
        .operationOwner,
        "Vision is inspecting exact sparse-tip calibration evidence without accepting a click or redrawing ink."
      )
    case .observedDrawingTrial:
      (
        "Trial ink analysis · active",
        false,
        .operationOwner,
        "Vision is comparing the validation baseline with the strictly newer post-drawing image. The preview remains visible and no redraw is requested."
      )
    case .drawingStudio:
      (
        "Drawing Studio ink analysis · active",
        false,
        .operationOwner,
        "Vision is comparing Drawing Studio's exact baseline and post-frame for the completed plan."
      )
    }
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
      "Move toward the \(direction.displayName) Drawing Boundary."
    case .awaitContextualStop: "Observe the boundary and use the contextual Stop."
    case .cancelBoundaryJogAndAwaitIdle:
      "Send one jog cancel and wait for controller Idle."
    case .commitBoundaryObservation(let direction):
      "Record the \(direction.displayName) Drawing Boundary from the selected direction, operator Stop, controller Idle, and final MPos. Camera and Vision are not used."
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
      "The controller is moving toward the selected Drawing Boundary and Stop is available."
    case .operatorStopRequested: "Stop is recorded before cancellation begins."
    case .boundaryJogCancelled: "The active motion reaches Idle with final MPos."
    case .boundaryObservationCommitted:
      "Controller settlement evidence and the current side aggregate commit together."
    case .penCommandSettled: "The requested pen command and dwell settle."
    case .physicalPenConfirmed: "The operator confirms the visible physical pen pose."
    }
  }

  private func drawingParticipant(_ step: ObservedDrawingTrialStep) -> String {
    switch step {
    case .chooseDrawingBorderPlan: "Application"
    case .captureLocalPreFrameBaseline, .revealAndObserveNewInk: "Camera and Vision"
    case .moveToDrawingBorderStart, .drawDrawingBorder: "Plotter controller"
    case .compareIntendedAndObservedGeometry: "Application"
    }
  }

  private func drawingActionText(_ step: ObservedDrawingTrialStep) -> String {
    switch step {
    case .chooseDrawingBorderPlan:
      "Build the closed Drawing Border through the four accepted calibration-circle centers and project it through the accepted pen-tip calibration."
    case .captureLocalPreFrameBaseline:
      "Capture one exact local baseline and record this Pen-Up reveal pose."
    case .moveToDrawingBorderStart: "Move Pen Up to the recorded lower-left Drawing Border corner."
    case .drawDrawingBorder: "Draw the closed Drawing Border as one stoppable controller operation."
    case .revealAndObserveNewInk:
      "Return Pen Up to the local reveal pose, settle, capture a newer frame, and extract new ink."
    case .compareIntendedAndObservedGeometry:
      "Record the plan-to-ink comparison automatically; unclear evidence stops for review and never redraws."
    }
  }

  private func drawingExpectationText(_ step: ObservedDrawingTrialStep) -> String {
    switch step {
    case .chooseDrawingBorderPlan:
      "One closed Drawing Border through the four accepted 10 mm-inset marks, projected by the exact accepted pen-tip calibration."
    case .captureLocalPreFrameBaseline:
      "One exact pre-frame image and its Pen-Up reveal MPos."
    case .moveToDrawingBorderStart: "Arrival at the lower-left Drawing Border corner while Pen Up."
    case .drawDrawingBorder: "A closed controller drawing-plan outcome for all four edges; this is not yet ink proof."
    case .revealAndObserveNewInk:
      "Observed new Drawing Border ink or an explicit unclear/rejected observation, with no automatic redraw."
    case .compareIntendedAndObservedGeometry:
      "One application-recorded comparison completes only this attributable validation."
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
    case .unavailable: "No Saved Learning is available."
    case .cleared: "Saved Learning was cleared."
    case .awaitingOperatorDecision(let count, let hasTip):
      "Saved Learning with \(count) Drawing Boundary side(s)\(hasTip ? " and a pen-tip calibration" : "") is loaded for preview only. Choose Use Saved Learning or Start New Learning."
    case .appliedByOperator(let count, let hasTip):
      "The operator applied Saved Learning with \(count) Drawing Boundary side(s)\(hasTip ? " and its exact pen-tip calibration" : ""). No motion was issued."
    case .retainedForLater(let count, let hasTip):
      "Saved Learning with \(count) Drawing Boundary side(s)\(hasTip ? " and a pen-tip calibration" : "") is retained while new Learning starts."
    case .quarantined(let count):
      "Saved Learning containing \(count) accepted Drawing Boundary side(s) is unavailable until the current controller setup matches."
    case .saved(let count, let center):
      "Saved Learning now contains \(count) accepted Drawing Boundary side(s)\(center ? " plus center arrival" : "")."
    case .restored(let count, let center, let reportedPositionDelta):
      String(
        format: "Restored Saved Learning with %d accepted Drawing Boundary side(s)%@ after checking the controller setup. Reported machine position changed %.3f mm; the physical pose still requires visual confirmation.",
        count,
        center ? " plus center arrival" : "",
        reportedPositionDelta
      )
    case .incompatible(let reason):
      "Saved Learning is unavailable: \(reason) No machine action was performed."
    case .rejected(let reason):
      "Saved Learning was rejected: \(reason) No machine action was performed."
    }
  }
}

extension LearningPathProjector {
  private func stageExpectedObservation(_ stage: LearningPathStage) -> [PresentationFragment] {
    switch stage {
    case .humanGuidedDiscovery:
      [.cue(.up), .text("Drawing Boundary, camera-calibration, and pen-tip-calibration evidence.")]
    case .observedDrawingTrials: [.text("Observed ink and a plan-to-ink geometry comparison.")]
    }
  }

  private func stageEvidence(
    _ stage: LearningPathStage,
    snapshot: LearningPathProjectionSnapshot
  ) -> [ExerciseEvidencePresentation] {
    switch stage {
    case .humanGuidedDiscovery:
      [ExerciseEvidencePresentation(
        label: "Boundary samples",
        fragments: [.text("N=\(snapshot.boundary.aggregates.count)")]
      )]
    case .observedDrawingTrials:
      [
        ExerciseEvidencePresentation(
          label: "Pen-tip calibration",
          fragments: [.text(snapshot.sparseCalibration.acceptedIsCurrent
            ? "Ready — current accepted pen-tip calibration"
            : "Unavailable — pen-tip calibration required")]
        ),
        ExerciseEvidencePresentation(
          label: "Drawing Border validation",
          fragments: [.text(snapshot.drawing.assessment == nil
            ? snapshot.drawing.inkStatus
            : "One attributable validation complete")]
        ),
        ExerciseEvidencePresentation(
          label: "Adaptive readiness",
          fragments: [.text("Not trained — coverage, reserved holdouts, candidate comparison, and shape readiness remain roadmap work")]
        ),
      ]
    }
  }

  private func discoveryReviewInstructions(
    _ step: HumanGuidedDiscoveryStep
  ) -> [PresentationFragment] {
    switch step {
    case .penInteraction:
      [.text("Identify Pen Cap, set and confirm"), .cue(.up), .text("then"), .cue(.down), .text("then confirm final"), .cue(.up)]
    case .pairedBoundaryDiscoveryAndCentering:
      [.text("Choose a direction, observe the side, then press"), .cue(.stop)]
    case .calibrateCameraAndVisibleCap:
      [.text("Run five exact cap measurements at C, X−, Y+, X+, and Y−; fit the first three, check the final two independently, then accept or reject the camera calibration.")]
    case .calibratePenContactFromSparseMarks:
      [.text("Draw four 2 mm-radius calibration circles with their centers 10 mm inside the accepted Drawing Boundary and Pen Up between circles. After the final Pen-Up reveal, click all four centers on the unchanged frame and review the proposed pen-tip calibration.")]
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
      [.text("Three fit measurements, two independent check measurements, and one current accepted camera calibration.")]
    case .calibratePenContactFromSparseMarks:
      [.text("Four immutable corner clicks and one accepted pen-tip calibration.")]
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
    case .penInteraction:
      return [
        ExerciseEvidencePresentation(
          label: "Saved Learning status",
          fragments: [.text(checkpointText(snapshot.acceptedCheckpointStatus))]
        )
      ] + (snapshot.savedTrainingCandidate.map { candidate in
        [
          ExerciseEvidencePresentation(
            label: "Saved Learning",
            fragments: [.text(candidate.artifactSummary)]
          ),
          ExerciseEvidencePresentation(
            label: "Optical sameness (advisory)",
            fragments: [.text(candidate.opticalComparison)]
          ),
        ]
      } ?? [])
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
            ? "Accepted camera calibration" : "Proposed camera calibration",
          fragments: [.text(registration.map {
            String(
              format: "check residuals %.3f / %.3f px · limit %.3f px · five-position uncertainty %.3f px",
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
          label: "2 mm-radius calibration circles",
          fragments: [.text(
            "\(snapshot.sparseCalibration.acceptedObservationCount)/4 accepted · \(snapshot.sparseCalibration.blacklistedPositionCount) excluded · \(String(describing: snapshot.sparseCalibration.phase))"
          )]
        ),
        ExerciseEvidencePresentation(
          label: "Pen-tip calibration diagnostics",
          fragments: [.text(proposal.map { proposal in
            let residuals = proposal.observationEvidence.map {
              String(format: "%.3f px", $0.residualPixels)
            }.joined(separator: ", ")
            return "\(proposal.modelForm.rawValue) · four-corner residuals \(residuals) · RMS \(String(format: "%.3f px", proposal.uncertainty.rootMeanSquareResidualPixels)) · max \(String(format: "%.3f px", proposal.uncertainty.maximumResidualPixels))"
          } ?? "Pen tip not calibrated")]
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
    case .chooseDrawingBorderPlan:
      [ExerciseEvidencePresentation(
        label: "Drawing Border plan",
        fragments: [.text(drawingBorderPlanDescription(snapshot.drawing.drawingBorderPath))]
      )]
    case .captureLocalPreFrameBaseline:
      [ExerciseEvidencePresentation(
        label: "Local pre-frame baseline",
        fragments: [.text(snapshot.drawing.localBaselineFrameID ?? "not captured")]
      )]
    case .moveToDrawingBorderStart:
      [ExerciseEvidencePresentation(
        label: "Drawing Border start",
        fragments: [.text(snapshot.drawing.drawingBorderPath.first.map {
          String(format: "X %.3f Y %.3f", $0.point.x, $0.point.y)
        } ?? "not reached")]
      )]
    case .drawDrawingBorder:
      [ExerciseEvidencePresentation(
        label: "Controller",
        fragments: [.text(snapshot.drawing.drawingBorderSettled ? "settled" : "not settled")]
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

  private func drawingTrialEvidence(
    snapshot: LearningPathProjectionSnapshot
  ) -> [ExerciseEvidencePresentation] {
    let plan = drawingBorderPlanDescription(snapshot.drawing.drawingBorderPath)
    return [
      ExerciseEvidencePresentation(label: "Predicted Drawing Border", fragments: [.text(plan)]),
      ExerciseEvidencePresentation(
        label: "Local baseline",
        fragments: [.text(snapshot.drawing.localBaselineFrameID ?? "not captured")]
      ),
      ExerciseEvidencePresentation(
        label: "Controller Drawing Border",
        fragments: [.text(snapshot.drawing.drawingBorderSettled ? "settled" : "not settled")]
      ),
      ExerciseEvidencePresentation(label: "Vision", fragments: [.text(snapshot.drawing.inkStatus)]),
      ExerciseEvidencePresentation(
        label: "Comparison",
        fragments: [.text(snapshot.drawing.assessment?.title ?? "pending automatic comparison")]
      ),
      ExerciseEvidencePresentation(
        label: "Validation scope",
        fragments: [.text(snapshot.drawing.assessment == nil
          ? "Pen-tip calibration ready; Drawing Border validation pending"
          : "One attributable Drawing Border validation is complete; adaptive readiness is not established")]
      ),
    ]
  }

  private func drawingBorderPlanDescription(_ path: [MachinePosition]) -> String {
    guard path.count == 5 else { return "not planned" }
    let points = path.map(\.point)
    return String(
      format: "closed right-angle perimeter · X %.3f…%.3f · Y %.3f…%.3f · projected through the accepted pen-tip calibration",
      points.map(\.x).min()!,
      points.map(\.x).max()!,
      points.map(\.y).min()!,
      points.map(\.y).max()!
    )
  }
}
