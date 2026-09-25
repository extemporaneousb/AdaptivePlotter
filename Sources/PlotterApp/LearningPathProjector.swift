import Foundation
import PlotterEpisodeModel
import PlotterEpisodeRuntime
import PlotterModel
import PlotterRuntime
import PlotterUI

enum ExactWorkflowVisionOwner: String, CaseIterable, Hashable, Sendable {
  case penCapAppearance
  case cameraCalibration
  case sparseTipCalibration
  case borderValidation
  case drawingStudio

  var capAcquisitionStatus: String? {
    switch self {
    case .cameraCalibration, .sparseTipCalibration:
      "Looking for pen cap… Clear its view. Stop cancels."
    case .penCapAppearance, .borderValidation, .drawingStudio:
      nil
    }
  }

  var operatorLabel: String {
    switch self {
    case .penCapAppearance: "pen cap"
    case .cameraCalibration: "camera calibration"
    case .sparseTipCalibration: "pen-tip calibration"
    case .borderValidation: "Drawing Border validation"
    case .drawingStudio: "Drawing Studio validation"
    }
  }
}

/// Immutable, values-only input to Learning Path presentation. Runtime owners,
/// persistence capabilities, tasks, closures, and authority-changing methods do
/// not cross this boundary.
struct PlotterLearningPresentationFacts: Sendable {
  struct ControllerFacts: Sendable {
    let sessionEstablished: Bool
    let motionAuthorized: Bool
    let cameraStateText: String
    let cameraDeliveryLimitOutcome: CameraDeliveryLimitOutcome
    let machineError: String?
    let controllerTravelUnavailableReason: String?

    init(
      sessionEstablished: Bool = false,
      motionAuthorized: Bool = false,
      cameraStateText: String = "not started",
      cameraDeliveryLimitOutcome: CameraDeliveryLimitOutcome = .notRequested,
      machineError: String? = nil,
      controllerTravelUnavailableReason: String? = nil
    ) {
      self.sessionEstablished = sessionEstablished
      self.motionAuthorized = sessionEstablished && motionAuthorized
      self.cameraStateText = cameraStateText
      self.cameraDeliveryLimitOutcome = cameraDeliveryLimitOutcome
      self.machineError = machineError
      self.controllerTravelUnavailableReason = controllerTravelUnavailableReason
    }
  }

  struct BoundaryFacts: Sendable {
    let projection: PlotterBoundaryProjection?
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

    init(
      projection: PlotterBoundaryProjection? = nil,
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
      boundaryTravelFeeds: [BoundaryDirection: TravelFeedSelection] = [:]
    ) {
      self.projection = projection
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
    let failure: PlotterCameraCalibrationFailure?
    let lastOutcome: PlotterCameraCalibrationSubmissionOutcome?

    init(
      accepted: MachineCameraRegistration? = nil,
      proposed: MachineCameraRegistration? = nil,
      acceptedIsCurrent: Bool? = nil,
      hasProposal: Bool? = nil,
      phase: CurrentCameraCalibrationPhase? = nil,
      failure: PlotterCameraCalibrationFailure? = nil,
      lastOutcome: PlotterCameraCalibrationSubmissionOutcome? = nil
    ) {
      self.accepted = accepted
      self.proposed = proposed
      self.acceptedIsCurrent = acceptedIsCurrent ?? (accepted != nil)
      self.hasProposal = hasProposal ?? (proposed != nil)
      self.phase = phase
      self.failure = failure
      self.lastOutcome = lastOutcome
    }
  }

  struct SparseCalibrationFacts: Sendable {
    let accepted: TipCameraRegistration?
    let proposed: TipCameraRegistration?
    let acceptedIsCurrent: Bool
    let phase: PlotterTipCalibrationPhase
    let acceptedObservationCount: Int
    let collectedClickCount: Int
    let blacklistedPositionCount: Int
    let savedCheckpointMatchesPaper: Bool

    init(
      accepted: TipCameraRegistration? = nil,
      proposed: TipCameraRegistration? = nil,
      acceptedIsCurrent: Bool? = nil,
      phase: PlotterTipCalibrationPhase = .idle,
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
    let currentStep: BorderValidationStep
    let phase: PlotterBorderValidationPhase
    let decisionIsInFlight: Bool
    let drawingBorderPath: [MachinePosition]
    let localBaselineFrameID: String?
    let drawingBorderSettled: Bool
    let inkStatus: String
    let assessment: BorderValidationAssessment?
    let lastTravelFeed: TravelFeedSelection?

    init(
      currentStep: BorderValidationStep = .chooseDrawingBorderPlan,
      phase: PlotterBorderValidationPhase = .idle,
      decisionIsInFlight: Bool = false,
      drawingBorderPath: [MachinePosition] = [],
      localBaselineFrameID: String? = nil,
      drawingBorderSettled: Bool = false,
      inkStatus: String = "no Drawing Border observation yet",
      assessment: BorderValidationAssessment? = nil,
      lastTravelFeed: TravelFeedSelection? = nil
    ) {
      self.currentStep = currentStep
      self.phase = phase
      self.decisionIsInFlight = decisionIsInFlight
      self.drawingBorderPath = drawingBorderPath
      self.localBaselineFrameID = localBaselineFrameID
      self.drawingBorderSettled = drawingBorderSettled
      self.inkStatus = inkStatus
      self.assessment = assessment
      self.lastTravelFeed = lastTravelFeed
    }
  }

  enum StopOwner: Hashable, Sendable {
    case manualJog(ContextualStopCapabilityID)
    case manualDrawing(ContextualStopCapabilityID)
    case exercise(ContextualStopCapabilityID, LearningMotionAction, boundaryOwner: Bool)
    case borderValidation(ContextualStopCapabilityID)
    case sparseTipBatch(ContextualStopCapabilityID)
    case positionRecovery(ContextualStopCapabilityID)

    var capabilityID: ContextualStopCapabilityID {
      switch self {
      case .exercise(let id, _, _): id
      case .manualJog(let id), .manualDrawing(let id), .borderValidation(let id),
        .sparseTipBatch(let id), .positionRecovery(let id): id
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
  let penInteraction: PlotterPenInteractionProjection?
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
  let capRecoveryDetail: String?
  let capRecoveryIsActive: Bool

  init(
    source: OperatorFrameMode = .live,
    learningEnabled: Bool = true,
    penInteractionCompleted: Bool = false,
    penInteraction: PlotterPenInteractionProjection? = nil,
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
    reset: ResetFacts = ResetFacts(),
    capRecoveryDetail: String? = nil,
    capRecoveryIsActive: Bool = false
  ) {
    self.source = source
    self.learningEnabled = learningEnabled
    self.penInteractionCompleted = penInteractionCompleted
    self.penInteraction = penInteraction
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
    self.capRecoveryDetail = capRecoveryDetail
    self.capRecoveryIsActive = capRecoveryIsActive
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
  let currentActionStrip: PlotterUILearningActionStripDecision?
  let contextualStop: ContextualStopPresentation?
  let resetSurface: LearningResetSurfacePresentation
  let menu: LearningPathMenuPresentation

  var capRecoveryDetail: String? = nil
  var capRecoveryIsActive = false
  var requiredExerciseActions: [PlotterUILearningActionStripDecision] = []
  var selectedExerciseActions: PlotterUILearningActionStripDecision? { selectedAction.actionStrip }
  var separateActiveExerciseActions: [PlotterUILearningActionStripDecision] {
    requiredExerciseActions.filter { $0.ownerID != selectedExerciseActions?.ownerID }
  }
  func activeExerciseHeading(for strip: PlotterUILearningActionStripDecision) -> String {
    guard let item = PlotterLearningActionabilityFactAdapter().itemID(strip.ownerID) else {
      return "Active exercise: \(strip.ownerID)"
    }
    return "Active exercise: \(item.number) \(item.title)"
  }
}

/// Copies retained runtime detail into PlotterUI facts and translates canonical
/// PlotterUI decisions back to existing App presentation values. It never
/// chooses current ownership, status, reachability, or available actions.
struct PlotterLearningActionabilityFactAdapter: Sendable {
  func ownerID(_ item: LearningPathItemID) -> String {
    "\(item.number)-\(item.title)"
  }

  func itemID(_ ownerID: String?) -> LearningPathItemID? {
    guard let ownerID else { return nil }
    return LearningPathItemID.navigationOrder.first { self.ownerID($0) == ownerID }
  }

  func compile(
    _ snapshot: PlotterLearningPresentationFacts,
    selectedItemID: LearningPathItemID
  ) -> PlotterUILearningActionabilityProjection {
    PlotterUILearningActionabilityCompiler().compile(facts(
      snapshot,
      selectedItemID: selectedItemID
    ))
  }

  func actionStrip(
    _ decision: PlotterUILearningActionStripDecision?
  ) -> PlotterUILearningActionStripDecision? {
    guard let decision, itemID(decision.ownerID) != nil else { return nil }
    return decision
  }

  private func facts(
    _ snapshot: PlotterLearningPresentationFacts,
    selectedItemID: LearningPathItemID
  ) -> PlotterUILearningActionabilityFacts {
    let itemFacts = LearningPathItemID.navigationOrder.map { item in
      PlotterUILearningItemFacts(
        ownerID: ownerID(item),
        kind: ownerKind(item),
        stageID: item.stage == .humanGuidedDiscovery ? "discovery" : "drawing",
        isStage: !item.isExercise,
        isExercise: item.isExercise,
        isComplete: isComplete(item, snapshot: snapshot),
        isRepeatable: isRepeatable(item)
      )
    }
    let activeTransaction = activeDiscoveryTransaction(snapshot)
    return PlotterUILearningActionabilityFacts(
      learning: PlotterUILearningFacts(
        isEnabled: snapshot.learningEnabled,
        activeOwnerID: snapshot.operations.activeAttemptOwner.map(ownerID),
        orderedMilestones: LearningPathItemID.learningExerciseOrder.map { item in
          PlotterUILearningMilestone(
            ownerID: ownerID(item),
            isComplete: isComplete(item, snapshot: snapshot)
          )
        }
      ),
      selectedOwnerID: ownerID(selectedItemID),
      items: itemFacts,
      savedTrainingCandidateIsPresent: snapshot.savedTrainingCandidate != nil,
      activeOwnerID: snapshot.operations.activeAttemptOwner.map(ownerID),
      restartableOwnerID: snapshot.operations.restartableItem.map(ownerID),
      stop: stopFacts(snapshot.operations.stopOwner),
      stopDispositionIsLatched: snapshot.operations.stopDispositionLatched,
      stickyAmbiguityReason: snapshot.operations.stickyAmbiguityReason,
      discoveryStageHasFailure: snapshot.operations.discoveryFailure != nil
        || snapshot.operations.explorationFailure != nil,
      drawingStageHasFailure: snapshot.operations.explorationFailure != nil,
      cameraState: cameraState(snapshot.cameraCalibration, boundary: snapshot.boundary),
      sparseState: sparseState(snapshot.sparseCalibration.phase),
      sparseCollectedClickCount: snapshot.sparseCalibration.collectedClickCount,
      sparseSavedCheckpointMatchesPaper: snapshot.sparseCalibration.savedCheckpointMatchesPaper,
      activePrompt: activePrompt(activeTransaction, profile: snapshot.penActuationProfile),
      penInteraction: snapshot.penInteraction,
      boundary: snapshot.boundary.projection,
      startUnavailableReasons: Dictionary(uniqueKeysWithValues:
        snapshot.startUnavailableReasons.map { (ownerID($0.key), $0.value) }
      ),
      boundaryIsComplete: snapshot.boundary.isComplete,
      boundaryHasCenterArrival: snapshot.boundary.centerArrival != nil,
      boundaryCenterArrivalRetryIsRequired: snapshot.boundary.centerArrivalRetryRequired,
      boundaryHasEstimatedCenter: snapshot.boundary.estimatedCenter != nil,
      acceptedBoundaryDirections: snapshot.boundary.acceptedDirections.map(uiDirection),
      allowedBoundaryDirections: snapshot.boundary.allowedDirections.map(uiDirection),
      selectedBoundaryDirection: uiDirection(snapshot.selectedBoundaryDirection),
      drawingState: drawingState(snapshot.drawing),
      selectedResetPlanIsPresent: snapshot.reset.plansByAnchor[selectedItemID] != nil,
      resetAllPlanIsPresent: snapshot.reset.resetAllPlan != nil,
      resetUnavailableReason: snapshot.reset.unavailableReason
    )
  }

  private func ownerKind(_ item: LearningPathItemID) -> PlotterUILearningOwnerKind {
    switch item {
    case .stage(.humanGuidedDiscovery): .discoveryStage
    case .stage(.borderValidations): .drawingStage
    case .humanGuidedDiscovery(.penInteraction): .penInteraction
    case .humanGuidedDiscovery(.pairedBoundaryDiscoveryAndCentering): .boundary
    case .humanGuidedDiscovery(.calibrateCameraAndVisibleCap): .cameraCalibration
    case .humanGuidedDiscovery(.calibratePenContactFromSparseMarks): .sparseTipCalibration
    case .borderValidation: .drawingValidation
    }
  }

  private func isComplete(
    _ item: LearningPathItemID,
    snapshot: PlotterLearningPresentationFacts
  ) -> Bool {
    let discoveryComplete = snapshot.penInteractionCompleted
      && snapshot.boundary.centerArrival != nil
      && snapshot.cameraCalibration.acceptedIsCurrent
      && snapshot.sparseCalibration.acceptedIsCurrent
    switch item {
    case .stage(.humanGuidedDiscovery): return discoveryComplete
    case .stage(.borderValidations): return snapshot.drawing.assessment != nil
    case .humanGuidedDiscovery(.penInteraction): return snapshot.penInteractionCompleted
    case .humanGuidedDiscovery(.pairedBoundaryDiscoveryAndCentering):
      return snapshot.boundary.centerArrival != nil
    case .humanGuidedDiscovery(.calibrateCameraAndVisibleCap):
      return snapshot.cameraCalibration.acceptedIsCurrent
    case .humanGuidedDiscovery(.calibratePenContactFromSparseMarks):
      return snapshot.sparseCalibration.acceptedIsCurrent
    case .borderValidation(let step):
      return step == .chooseDrawingBorderPlan && snapshot.drawing.assessment != nil
    }
  }

  private func isRepeatable(_ item: LearningPathItemID) -> Bool {
    switch item {
    case .humanGuidedDiscovery(.penInteraction),
      .humanGuidedDiscovery(.pairedBoundaryDiscoveryAndCentering): true
    default: false
    }
  }

  private func activeDiscoveryTransaction(
    _ snapshot: PlotterLearningPresentationFacts
  ) -> PlotterLearningPresentationFacts.DiscoveryFacts? {
    snapshot.discovery.values
      .filter { $0.state == .active || $0.state == .cancelling }
      .sorted { $0.sequenceID.rawValue < $1.sequenceID.rawValue }
      .first
  }

  private func activePrompt(
    _ transaction: PlotterLearningPresentationFacts.DiscoveryFacts?,
    profile: PenActuationProfile
  ) -> PlotterUILearningActivePrompt? {
    guard let step = transaction?.currentStep else { return nil }
    if transaction?.sequenceID == .penInteraction,
      case .awaitPhysicalPenConfirmation(let state, _) = step.action
    {
      let command: PenCommand = state == .down ? .lower : .raise
      return .penConfirmation(
        command: uiPenCommand(command),
        value: profile.value(for: command),
        minimumValue: 0,
        maximumValue: 1_000
      )
    }
    return step.question.map { question in
      .choices(question.choices.map(uiChoice))
    }
  }

  private func stopFacts(
    _ owner: PlotterLearningPresentationFacts.StopOwner?
  ) -> PlotterUILearningStopFacts? {
    guard let owner else { return nil }
    let kind: PlotterUILearningStopKind = switch owner {
    case .manualJog: .manualJog
    case .manualDrawing: .manualDrawing
    case .exercise(_, let action, let boundaryOwner):
      .exercise(title: action.title, boundaryOwner: boundaryOwner)
    case .borderValidation: .drawingValidation
    case .sparseTipBatch: .sparseTipBatch
    case .positionRecovery: .exercise(title: "Position Verification", boundaryOwner: false)
    }
    return PlotterUILearningStopFacts(capabilityID: owner.capabilityID.rawValue, kind: kind)
  }

  private func cameraState(
    _ facts: PlotterLearningPresentationFacts.CameraCalibrationFacts,
    boundary: PlotterLearningPresentationFacts.BoundaryFacts
  ) -> PlotterUILearningCameraState {
    if facts.phase != nil { return .active }
    if facts.hasProposal { return .readyWithProposal }
    if let center = boundary.centerArrival, let current = boundary.currentPosition,
      !MachinePositionAcceptancePolicy.accepts(current, target: center) {
      return .readyForCenterReturn
    }
    return .readyWithoutProposal
  }

  private func sparseState(_ phase: PlotterTipCalibrationPhase) -> PlotterUILearningSparseState {
    switch phase {
    case .idle: .idle
    case .marking: .drawingBatch
    case .capturingNewClickFrame: .capturingClickFrame
    case .awaitingCompletedPointSelection: .awaitingFrozenClicks
    case .fitting: .fittingModel
    case .reviewingProposal: .reviewingModel
    case .committing: .committingModel
    case .revalidating: .committingModel
    case .rejected: .awaitingFrozenClicks
    case .possibleInkBlacklisted: .possibleInkBlacklisted
    case .accepted: .accepted
    }
  }

  private func drawingState(
    _ facts: PlotterLearningPresentationFacts.DrawingFacts
  ) -> PlotterUILearningDrawingState {
    if case .reviewingComparison = facts.phase, !facts.decisionIsInFlight {
      return .reviewingComparison
    }
    return switch facts.currentStep {
    case .chooseDrawingBorderPlan: .choosePlan
    case .captureLocalPreFrameBaseline: .captureBaseline
    case .moveToDrawingBorderStart: .moveToStart
    case .drawDrawingBorder: .draw
    case .revealAndObserveNewInk: .revealAndObserve
    case .compareIntendedAndObservedGeometry: .compare
    }
  }

  private func uiDirection(_ direction: BoundaryDirection) -> PlotterUILearningBoundaryDirection {
    switch direction {
    case .negativeX: .negativeX
    case .positiveX: .positiveX
    case .negativeY: .negativeY
    case .positiveY: .positiveY
    }
  }

  func boundaryDirection(
    _ direction: PlotterUILearningBoundaryDirection
  ) -> BoundaryDirection {
    switch direction {
    case .negativeX: .negativeX
    case .positiveX: .positiveX
    case .negativeY: .negativeY
    case .positiveY: .positiveY
    }
  }

  private func uiChoice(_ choice: OperatorChoice) -> PlotterLearningChoice {
    choice == .yes ? .yes : .no
  }

  func operatorChoice(_ choice: PlotterLearningChoice) -> OperatorChoice {
    choice == .yes ? .yes : .no
  }

  private func uiPenCommand(_ command: PenCommand) -> PlotterLearningPenCommand {
    command == .raise ? .raise : .lower
  }

}

private extension PlotterUILearningItemStatus {
  var appPresentationStatus: LearningPathStageStatus {
    switch self {
    case .complete: .complete
    case .current: .current
    case .next: .next
    case .needsAttention: .needsAttention
    }
  }
}

/// Cosmetic Learning Path presentation over one canonical PlotterUI decision.
/// It has no reference to PlotterApplicationRuntime or any runtime/persistence owner.
struct PlotterLearningDetailedPresentationNormalizer: Sendable {
  func project(
    _ snapshot: PlotterLearningPresentationFacts,
    selectedItemID: LearningPathItemID,
    actionability: PlotterUILearningActionabilityProjection
  ) -> LearningPathProjection {
    let adapter = PlotterLearningActionabilityFactAdapter()
    let current = adapter.itemID(actionability.learning.currentOwnerID)
      ?? .humanGuidedDiscovery(.penInteraction)
    return LearningPathProjection(
      currentItemID: current,
      items: LearningPathItemID.navigationOrder.map {
        let decision = actionability.item(ownerID: adapter.ownerID($0))
        return LearningPathItemPresentation(
          id: $0,
          status: (decision?.status ?? .next).appPresentationStatus
        )
      },
      selectedAction: operatorAction(
        for: selectedItemID,
        snapshot: snapshot,
        actionability: actionability
      ),
      currentActionStrip: adapter.actionStrip(
        actionability.strip(ownerID: adapter.ownerID(current))
      ),
      contextualStop: contextualStop(actionability.contextualStop),
      resetSurface: LearningResetSurfacePresentation(
        selectedPlan: actionability.selectedResetPlanIsReachable
          ? snapshot.reset.plansByAnchor[selectedItemID] : nil,
        unavailableReason: actionability.resetUnavailableReason,
        authorityError: snapshot.reset.authorityError
      ),
      menu: LearningPathMenuPresentation(
        resetAllPlan: actionability.resetAllPlanIsReachable ? snapshot.reset.resetAllPlan : nil
      ),
      capRecoveryDetail: snapshot.capRecoveryDetail,
      capRecoveryIsActive: snapshot.capRecoveryIsActive,
      requiredExerciseActions: actionability.strips.filter(\.mustRemainVisible)
        .compactMap { adapter.actionStrip($0) }
    )
  }

  private func summary(
    for itemID: LearningPathItemID,
    snapshot: PlotterLearningPresentationFacts
  ) -> String {
    switch itemID {
    case .stage(.humanGuidedDiscovery):
      "Identify and calibrate the pen, measure all four drawing-boundary sides, move to the estimated center, calibrate the camera from five pen-cap positions, and calibrate the pen tip from four corner marks."
    case .humanGuidedDiscovery(.penInteraction):
      "Click the pen cap on one frozen frame, then set and confirm the physical Pen Up, Pen Down, and final Pen Up positions."
    case .humanGuidedDiscovery(.pairedBoundaryDiscoveryAndCentering):
      "Measure the X−, X+, Y−, and Y+ drawing-boundary sides with operator Stop, then move Pen Up to their estimated center."
    case .humanGuidedDiscovery(.calibrateCameraAndVisibleCap):
      "Run five Pen-Up pen-cap measurements at the center and four axis positions. Three measurements fit the camera calibration and two independently check it before review."
    case .humanGuidedDiscovery(.calibratePenContactFromSparseMarks):
      "Draw four 2 mm-radius calibration circles whose centers are 10 mm inside the accepted Drawing Boundary. After one final Pen-Up reveal, click the four circle centers on the unchanged frame and review the proposed pen-tip calibration."
    case .stage(.borderValidations):
      "Use the accepted pen-tip calibration to preview, draw, observe, and compare the Drawing Border through the four calibration-circle centers."
    case .borderValidation(.chooseDrawingBorderPlan):
      "Press Draw and Validate Drawing Border once. The app previews the Drawing Border, captures a baseline, draws the perimeter, returns Pen Up for a new image, compares the observation, and retains the result automatically."
    case .borderValidation(let step): drawingActionText(step)
    }
  }
}

extension PlotterLearningDetailedPresentationNormalizer {
  private func operatorAction(
    for itemID: LearningPathItemID,
    snapshot: PlotterLearningPresentationFacts,
    actionability: PlotterUILearningActionabilityProjection
  ) -> OperatorActionPresentation {
    let adapter = PlotterLearningActionabilityFactAdapter()
    let actionStrip = adapter.actionStrip(
      actionability.strip(ownerID: adapter.ownerID(itemID))
    )
    switch itemID {
    case .stage:
      return OperatorActionPresentation(
        itemID: itemID,
        instructions: [.text(summary(for: itemID, snapshot: snapshot))],
        actionStrip: actionStrip
      )
    case .humanGuidedDiscovery(let step):
      if step == .pairedBoundaryDiscoveryAndCentering, let boundary = snapshot.boundary.projection {
        let detail: String? = if case .needsAttention(let reason) = boundary.phase {
          reason
        } else if let refusal = boundary.lastRefusal {
          "Boundary refused: \(refusal.reason). Remedy: \(refusal.remedy)."
        } else { nil }
        if let detail {
          return OperatorActionPresentation(itemID: itemID,
            instructions: [.text("Previous Boundary attempt: \(detail)")]
              + discoveryReviewInstructions(step), actionStrip: actionStrip)
        }
      }
      if (step == .calibrateCameraAndVisibleCap || step == .calibratePenContactFromSparseMarks),
        let detail = snapshot.operations.exactWorkflowVisionOwner?.capAcquisitionStatus {
        return OperatorActionPresentation(
          itemID: itemID, instructions: [.text(detail)], actionStrip: actionStrip
        )
      }
      if step == .calibrateCameraAndVisibleCap {
        let camera = snapshot.cameraCalibration
        let detail: String? = if let phase = camera.phase {
          phase.description
        } else if let failure = camera.failure {
          "Camera calibration stopped: \(failure.detail) Accepted Boundary and Pen Learning are retained."
        } else if case .refused(let reason) = camera.lastOutcome {
          "Camera calibration refused: \(reason)"
        } else { nil }
        if let detail {
          return OperatorActionPresentation(
            itemID: itemID, instructions: [.text(detail)], actionStrip: actionStrip
          )
        }
      }
      if step == .calibratePenContactFromSparseMarks,
        case .possibleInkBlacklisted(_, let reason) = snapshot.sparseCalibration.phase {
        return OperatorActionPresentation(
          itemID: itemID,
          instructions: [.text("Calibration stopped: \(reason) Ink may already exist from this attempt. Resolve the cause, then replace the marked sheet and use Record Paper Replacement before starting a new batch.")],
          actionStrip: actionStrip
        )
      }
      let transaction = discoveryTransaction(for: step, snapshot: snapshot)
      let activeStep = transaction?.currentStep
      return OperatorActionPresentation(
        itemID: itemID,
        instructions: activeStep.map { discoveryInstruction($0.action) }
          ?? discoveryReviewInstructions(step),
        question: activeStep.flatMap { discoveryQuestion($0.action) },
        actionStrip: actionStrip
      )
    case .borderValidation(let step):
      let isVisibleTrial = step == .chooseDrawingBorderPlan
      return OperatorActionPresentation(
        itemID: itemID,
        instructions: [.text(isVisibleTrial
          ? drawingTrialInstruction(snapshot.drawing)
          : drawingActionText(step))],
        actionStrip: actionStrip
      )
    }
  }

  private func drawingTrialInstruction(_ drawing: PlotterLearningPresentationFacts.DrawingFacts) -> String {
    if let assessment = drawing.assessment {
      return "Learning complete. " + assessment.title + ". The result is retained automatically."
        + (assessment == .drawingCompleted ? " \(drawing.inkStatus)" : " Choose Portrait Studio or Active Learning from Panels to continue.")
    }
    switch drawing.phase {
    case .failed(let detail), .rejected(let detail), .possibleInk(let detail), .cancelled(let detail):
      return "\(drawing.currentStep.title): \(detail)"
    case .idle:
      return "Press Draw and Validate Drawing Border once. The app captures the baseline, draws, reveals the result, compares the ink, and retains the completed trial automatically."
    default:
      return drawingActionText(drawing.currentStep)
    }
  }

  private func contextualStop(
    _ stop: PlotterUILearningStopFacts?
  ) -> ContextualStopPresentation? {
    guard let stop else { return nil }
    let detail: String = switch stop.kind {
    case .boundary(let direction):
      "Stop the \(PlotterLearningActionabilityFactAdapter().boundaryDirection(direction).displayName) Drawing Boundary search. The app will wait for controller Idle and record the final position."
    case .manualJog:
      "Stop the active manual jog and wait for Idle."
    case .manualDrawing:
      "Stop the active manual drawing stroke, wait for Idle, and retain the controller's one Pen Up outcome."
    case .exercise(let title, _):
      "Stop \(title) and wait for the active operation to settle. No Learning Path result will be accepted."
    case .drawingValidation:
      "Stop Drawing Border validation. The active drawing operation will cancel once and settle Pen Up."
    case .sparseTipBatch:
      "Stop the four-circle calibration. Any location where ink may exist will be excluded from automatic redraw."
    }
    return ContextualStopPresentation(
      capabilityID: ContextualStopCapabilityID(rawValue: stop.capabilityID),
      title: "Stop",
      detail: detail
    )
  }
}

extension PlotterLearningDetailedPresentationNormalizer {
  private func discoveryTransaction(
    for step: HumanGuidedDiscoveryStep,
    snapshot: PlotterLearningPresentationFacts
  ) -> PlotterLearningPresentationFacts.DiscoveryFacts? {
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

  private func drawingActionText(_ step: BorderValidationStep) -> String {
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
      "Record the plan-to-ink comparison and retain the completed trial automatically."
    }
  }

}

extension PlotterLearningDetailedPresentationNormalizer {
  private func discoveryReviewInstructions(
    _ step: HumanGuidedDiscoveryStep
  ) -> [PresentationFragment] {
    switch step {
    case .penInteraction:
      [.text("Click the pen cap, then set and confirm"), .cue(.up), .text("then"), .cue(.down), .text("then confirm final"), .cue(.up)]
    case .pairedBoundaryDiscoveryAndCentering:
      [.text("Choose a direction, observe the side, then press"), .cue(.stop)]
    case .calibrateCameraAndVisibleCap:
      [.text("Run five exact pen-cap measurements at C, X−, Y+, X+, and Y−; fit the first three, check the final two independently, then accept or reject the camera calibration.")]
    case .calibratePenContactFromSparseMarks:
      [.text("The app raises the pen before moving, then draws four 2 mm-radius calibration circles with their centers 10 mm inside the accepted Drawing Boundary and Pen Up between circles. After the final Pen-Up reveal, click all four centers on the unchanged frame and review the proposed pen-tip calibration.")]
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

}
