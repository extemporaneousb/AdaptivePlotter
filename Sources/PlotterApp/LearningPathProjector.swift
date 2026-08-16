import Foundation
import PlotterModel
import PlotterRuntime

/// Immutable, values-only input to Learning Path presentation. Runtime owners,
/// persistence capabilities, tasks, closures, and authority-changing methods do
/// not cross this boundary.
struct LearningPathProjectionSnapshot: Sendable {
  struct ControllerFacts: Sendable {
    let sessionEstablished: Bool
    let motionAuthorized: Bool
    let machineError: String?

    init(
      sessionEstablished: Bool = false,
      motionAuthorized: Bool = false,
      machineError: String? = nil
    ) {
      self.sessionEstablished = sessionEstablished
      self.motionAuthorized = motionAuthorized
      self.machineError = machineError
    }
  }

  struct BoundaryFacts: Sendable {
    let acceptedDirections: [BoundaryDirection]
    let allowedDirections: [BoundaryDirection]
    let isComplete: Bool
    let estimatedCenter: EstimatedMachineCenter?
    let centerArrival: MachinePosition?
    let centerArrivalRetryRequired: Bool

    init(
      acceptedDirections: [BoundaryDirection] = [],
      allowedDirections: [BoundaryDirection] = BoundaryDirection.allCases,
      isComplete: Bool = false,
      estimatedCenter: EstimatedMachineCenter? = nil,
      centerArrival: MachinePosition? = nil,
      centerArrivalRetryRequired: Bool = false
    ) {
      self.acceptedDirections = acceptedDirections
      self.allowedDirections = allowedDirections
      self.isComplete = isComplete
      self.estimatedCenter = estimatedCenter
      self.centerArrival = centerArrival
      self.centerArrivalRetryRequired = centerArrivalRetryRequired
    }
  }

  struct DiscoveryFacts: Sendable {
    let state: DiscoveryTransactionState
    let currentStep: DiscoveryStep?
  }

  struct CameraCalibrationFacts: Sendable {
    let acceptedIsCurrent: Bool
    let hasProposal: Bool
    let phase: CurrentCameraCalibrationPhase?

    init(
      acceptedIsCurrent: Bool = false,
      hasProposal: Bool = false,
      phase: CurrentCameraCalibrationPhase? = nil
    ) {
      self.acceptedIsCurrent = acceptedIsCurrent
      self.hasProposal = hasProposal
      self.phase = phase
    }
  }

  struct SparseCalibrationFacts: Sendable {
    let acceptedIsCurrent: Bool
    let phase: SparseTipCalibrationPhase
    let savedCheckpointMatchesPaper: Bool
    let requiresPaperReplacement: Bool
    let paperReplacementUnavailableReason: String?

    init(
      acceptedIsCurrent: Bool = false,
      phase: SparseTipCalibrationPhase = .idle,
      savedCheckpointMatchesPaper: Bool = false,
      requiresPaperReplacement: Bool = false,
      paperReplacementUnavailableReason: String? = nil
    ) {
      self.acceptedIsCurrent = acceptedIsCurrent
      self.phase = phase
      self.savedCheckpointMatchesPaper = savedCheckpointMatchesPaper
      self.requiresPaperReplacement = requiresPaperReplacement
      self.paperReplacementUnavailableReason = paperReplacementUnavailableReason
    }
  }

  struct DrawingFacts: Sendable {
    let currentStep: ObservedDrawingTrialStep
    let completedArtifactSteps: Set<ObservedDrawingTrialStep>
    let selectedDirection: BoundaryDirection
    let assessment: DrawingTrialAssessment?
    let currentGroupHasExposure: Bool

    init(
      currentStep: ObservedDrawingTrialStep = .chooseIsolatedLinePlan,
      completedArtifactSteps: Set<ObservedDrawingTrialStep> = [],
      selectedDirection: BoundaryDirection = .positiveX,
      assessment: DrawingTrialAssessment? = nil,
      currentGroupHasExposure: Bool = false
    ) {
      self.currentStep = currentStep
      self.completedArtifactSteps = completedArtifactSteps
      self.selectedDirection = selectedDirection
      self.assessment = assessment
      self.currentGroupHasExposure = currentGroupHasExposure
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

    init(
      activeAttemptOwner: LearningPathItemID? = nil,
      restartableItem: LearningPathItemID? = nil,
      stopOwner: StopOwner? = nil,
      stopDispositionLatched: Bool = false,
      stickyAmbiguityReason: String? = nil,
      explorationFailure: WorkflowFailure? = nil,
      discoveryFailure: WorkflowFailure? = nil
    ) {
      self.activeAttemptOwner = activeAttemptOwner
      self.restartableItem = restartableItem
      self.stopOwner = stopOwner
      self.stopDispositionLatched = stopDispositionLatched
      self.stickyAmbiguityReason = stickyAmbiguityReason
      self.explorationFailure = explorationFailure
      self.discoveryFailure = discoveryFailure
    }
  }

  struct InvalidationFacts: Sendable {
    let plansByRoot: [LearningPathItemID: LearningInvalidationPlan]
    let invalidateAllPlan: LearningInvalidationPlan?
    let unavailableReason: String?

    init(
      plansByRoot: [LearningPathItemID: LearningInvalidationPlan] = [:],
      invalidateAllPlan: LearningInvalidationPlan? = nil,
      unavailableReason: String? = nil
    ) {
      self.plansByRoot = plansByRoot
      self.invalidateAllPlan = invalidateAllPlan
      self.unavailableReason = unavailableReason
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
  let invalidation: InvalidationFacts

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
    invalidation: InvalidationFacts = InvalidationFacts()
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
    self.invalidation = invalidation
  }
}

struct LearningPathProjection: Hashable, Sendable {
  let currentItemID: LearningPathItemID
  let items: [LearningPathItemPresentation]
  let selectedAction: OperatorActionPresentation
  let contextualStop: ContextualStopPresentation?
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
      items: LearningPathTree.curriculum.flattenedItems.map {
        itemPresentation(for: $0, current: current, snapshot: snapshot)
      },
      selectedAction: operatorAction(for: selectedItemID, current: current, snapshot: snapshot),
      contextualStop: contextualStop(snapshot)
    )
  }

  private func itemPresentation(
    for itemID: LearningPathItemID,
    current: LearningPathItemID,
    snapshot: LearningPathProjectionSnapshot
  ) -> LearningPathItemPresentation {
    LearningPathItemPresentation(
      id: itemID,
      status: status(for: itemID, current: current, snapshot: snapshot)
    )
  }

  func currentItemID(_ snapshot: LearningPathProjectionSnapshot) -> LearningPathItemID {
    if let owner = snapshot.operations.activeAttemptOwner { return owner }
    if snapshot.sparseCalibration.requiresPaperReplacement {
      return .humanGuidedDiscovery(.calibratePenContactFromSparseMarks)
    }
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
          ? "Use toolbar Connect for the nonphysical learning simulator."
          : "Use the toolbar to select and connect one responsive controller.")
    case .stage(.enableMotion):
      snapshot.controller.motionAuthorized
        ? "Motion is enabled for typed operations."
        : "Use toolbar Enable Motion for this controller session."
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
    let item = itemPresentation(for: itemID, current: current, snapshot: snapshot)
    let invalidation = LearningInvalidationPresentation(
      selectedPlan: snapshot.invalidation.plansByRoot[itemID],
      invalidateAllPlan: snapshot.invalidation.invalidateAllPlan,
      unavailableReason: snapshot.invalidation.unavailableReason
    )
    switch itemID {
    case .stage:
      return OperatorActionPresentation(
        item: item,
        script: [ExerciseScriptLinePresentation(
          speaker: .you,
          fragments: [.text(summary(for: itemID, snapshot: snapshot))]
        )],
        actionStrip: actionStrip(for: itemID, current: current, snapshot: snapshot),
        invalidation: invalidation
      )
    case .humanGuidedDiscovery(let step):
      let transaction = discoveryTransaction(for: step, snapshot: snapshot)
      let activeStep = transaction?.currentStep
      let actions = actionStrip(for: itemID, current: current, snapshot: snapshot)
      return OperatorActionPresentation(
        item: item,
        script: [ExerciseScriptLinePresentation(
          speaker: activeStep.map { scriptSpeaker(for: $0.participant) }
            ?? reviewScriptSpeaker(for: step),
          fragments: activeStep.map { discoveryInstruction($0.action) }
            ?? discoveryReviewInstructions(step)
        )],
        question: activeStep.flatMap { discoveryQuestion($0.action) }
          ?? (actions == nil ? nil : decisionQuestion(for: itemID, snapshot: snapshot)),
        actionStrip: actions,
        invalidation: invalidation
      )
    case .observedDrawingTrial(let step):
      let actions = actionStrip(for: itemID, current: current, snapshot: snapshot)
      return OperatorActionPresentation(
        item: item,
        script: [ExerciseScriptLinePresentation(
          speaker: drawingScriptSpeaker(step),
          fragments: [.text(drawingActionText(step))]
        )],
        question: actions == nil ? nil : decisionQuestion(for: itemID, snapshot: snapshot),
        actionStrip: actions,
        invalidation: invalidation
      )
    }
  }

  private func decisionQuestion(
    for itemID: LearningPathItemID,
    snapshot: LearningPathProjectionSnapshot
  ) -> ExerciseQuestionPresentation? {
    if itemID == .humanGuidedDiscovery(.pairedBoundaryDiscoveryAndCentering),
      let stopOwner = snapshot.operations.stopOwner,
      case .pairedBoundary = stopOwner
    {
      return ExerciseQuestionPresentation(
        prompt: [.text("How should this Boundary motion end?")]
      )
    }
    switch itemID {
    case .humanGuidedDiscovery(.calibrateCameraAndVisibleCap)
      where snapshot.cameraCalibration.hasProposal:
      return ExerciseQuestionPresentation(
        prompt: [.text("Should this camera and visible-cap fit become current?")]
      )
    case .humanGuidedDiscovery(.calibratePenContactFromSparseMarks):
      return switch snapshot.sparseCalibration.phase {
      case .reviewingClick:
        ExerciseQuestionPresentation(
          prompt: [.text("Is the selected center of the new mark correct?")]
        )
      case .reviewingFinalProposal:
        ExerciseQuestionPresentation(
          prompt: [.text("Should this tip calibration become current?")]
        )
      case .possibleInkExposureRetained, .holdoutFailed, .rejected:
        ExerciseQuestionPresentation(
          prompt: [.text("Has the paper been physically replaced?")]
        )
      default: nil
      }
    case .observedDrawingTrial(.compareIntendedAndObservedGeometry)
      where snapshot.drawing.assessment == nil:
      return ExerciseQuestionPresentation(
        prompt: [.text("Does the observed ink geometry match the intended line?")]
      )
    default:
      return nil
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
      "\(direction.displayName) Boundary is moving. Stop & Accept may commit only after fresh Idle and final MPos; Stop and Cancel accept no artifact."
    case .manualJog:
      "Stop the active manual jog and wait for Idle."
    case .manualDrawing:
      "Stop the active manual drawing stroke, wait for Idle, and retain the controller's one Pen Up outcome."
    case .exercise(_, let action, _):
      "Stop \(action.title) and wait for the original owner to settle. No training artifact is accepted."
    case .drawingTrial:
      "Stop the drawing trial; the controller owns its single Pen Up cancellation."
    case .sparseTipMark:
      "Stop the active calibration circle. Its possible-ink exposure will be retained and will not be redrawn automatically."
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
        if case .pairedBoundary = owner {
          actions = [
            ExerciseActionDescriptor(
              kind: .stopAndAcceptBoundary(stop.capabilityID),
              title: "Stop & Accept"
            ),
            ExerciseActionDescriptor(
              kind: .stop(stop.capabilityID),
              title: "Stop"
            ),
            ExerciseActionDescriptor(
              kind: .cancel(stop.capabilityID),
              title: "Cancel"
            ),
          ]
        } else {
          actions = [ExerciseActionDescriptor(
            kind: .stop(stop.capabilityID),
            title: "Stop"
          )]
        }
        return ExerciseActionStripPresentation(
          ownerID: itemID,
          actions: actions,
          mustRemainVisible: true
        )
      }
      if itemID == .humanGuidedDiscovery(.calibratePenContactFromSparseMarks),
        snapshot.sparseCalibration.requiresPaperReplacement
      {
        return ExerciseActionStripPresentation(
          ownerID: itemID,
          actions: [ExerciseActionDescriptor(
            kind: .paperReplaced,
            title: "Record Paper Replacement",
            unavailableReason: snapshot.sparseCalibration.paperReplacementUnavailableReason
          )]
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
              title: "Capture Five Cap Samples"
            ),
            ExerciseActionDescriptor(
              kind: .rejectCameraCalibrationProposal,
              title: "Discard Cap Samples"
            ),
          ]
        } else {
          actions = [
            ExerciseActionDescriptor(
              kind: .acceptCameraCalibrationProposal,
              title: "Accept Camera and Visible-Cap Fit"
            ),
            ExerciseActionDescriptor(
              kind: .rejectCameraCalibrationProposal,
              title: "Reject Camera Fit"
            ),
          ]
        }
      } else if itemID == .humanGuidedDiscovery(.calibratePenContactFromSparseMarks) {
        actions = activeSparseActions(snapshot.sparseCalibration.phase)
      } else if itemID == .observedDrawingTrial(.compareIntendedAndObservedGeometry) {
        actions = DrawingTrialAssessment.allCases.map { assessment in
          ExerciseActionDescriptor(
            kind: .recordDrawingTrialAssessment(assessment),
            title: assessment.title
          )
        }
      } else if let activeDiscovery = snapshot.discovery.first(where: {
        $0.value.state == .active || $0.value.state == .cancelling
      }), let choices = activeDiscovery.value.currentStep?.question?.choices {
        let transaction = activeDiscovery.value
        if activeDiscovery.key == .penInteraction,
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
              title: "Next"
            )
          ]
        } else {
          actions = choices.map { choice in
            ExerciseActionDescriptor(
              kind: .choice(choice),
              title: choice.exactPhrase
            )
          }
        }
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
        actions: [ExerciseActionDescriptor(kind: .restart, title: "Restart")]
      )
    }

    if isComplete(itemID, snapshot: snapshot), itemID.isExercise {
      let repeatUnavailableReason = snapshot.startUnavailableReasons[itemID]
      if itemID == .humanGuidedDiscovery(.calibratePenContactFromSparseMarks),
        snapshot.sparseCalibration.acceptedIsCurrent
      {
        return ExerciseActionStripPresentation(
          ownerID: itemID,
          actions: [ExerciseActionDescriptor(
            kind: .paperReplaced,
            title: "Record Paper Replacement",
            unavailableReason: snapshot.sparseCalibration.paperReplacementUnavailableReason
          )]
        )
      }
      if case .observedDrawingTrial(let step) = itemID,
        snapshot.drawing.currentGroupHasExposure,
        step.rawValue <= ObservedDrawingTrialStep.drawIsolatedLine.rawValue
      {
        return nil
      }
      let actions: [ExerciseActionDescriptor]
      if itemID == .humanGuidedDiscovery(.pairedBoundaryDiscoveryAndCentering) {
        actions = snapshot.boundary.acceptedDirections.flatMap { direction in
          [
            ExerciseActionDescriptor(
              kind: .redoBoundary(direction),
              title: "Redo \(direction.displayName) Boundary",
              unavailableReason: repeatUnavailableReason
            ),
            ExerciseActionDescriptor(
              kind: .recordAnotherBoundaryAttempt(direction),
              title: "Record Another \(direction.displayName) Attempt",
              unavailableReason: repeatUnavailableReason
            ),
          ]
        }
      } else {
        actions = [ExerciseActionDescriptor(
          kind: .redoThisStep,
          title: "Redo This Step",
          unavailableReason: repeatUnavailableReason
        )]
          + (isRepeatable(itemID)
            ? [ExerciseActionDescriptor(
              kind: .recordAnotherAttempt,
              title: "Record Another Attempt",
              unavailableReason: repeatUnavailableReason
            )]
            : [])
      }
      return ExerciseActionStripPresentation(ownerID: itemID, actions: actions)
    }

    guard itemID == current, itemID.isExercise else { return nil }
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
            unavailableReason: centerReason
          )
        ] + boundaryRepeatActions(
          snapshot.boundary.acceptedDirections,
          unavailableReason: reason
        )
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
            unavailableReason: reason
          )
        ]
      )
    }
    if itemID == .humanGuidedDiscovery(.calibratePenContactFromSparseMarks),
      snapshot.sparseCalibration.requiresPaperReplacement
    {
      return ExerciseActionStripPresentation(
        ownerID: itemID,
        actions: [ExerciseActionDescriptor(
          kind: .paperReplaced,
          title: "Record Paper Replacement",
          unavailableReason: snapshot.sparseCalibration.paperReplacementUnavailableReason
        )]
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
            unavailableReason: reason
          )
        ]
      )
    }
    if itemID == .humanGuidedDiscovery(.calibratePenContactFromSparseMarks) {
      switch snapshot.sparseCalibration.phase {
      case .possibleInkExposureRetained, .holdoutFailed, .rejected:
        return ExerciseActionStripPresentation(
          ownerID: itemID,
          actions: [
            ExerciseActionDescriptor(
              kind: .paperReplaced,
              title: "Record Paper Replacement",
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
        title: "Create Next 2 mm Circle"
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
          title: "Accept Mark Center"
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
          title: "Accept Tip Calibration"
        ),
        ExerciseActionDescriptor(
          kind: .rejectTipCalibration,
          title: "Reject Tip Calibration"
        ),
      ]
    case .possibleInkExposureRetained(_, let reason), .holdoutFailed(let reason),
      .rejected(let reason):
      [
        ExerciseActionDescriptor(
          kind: .rejectTipCalibration,
          title: "No Automatic Redraw",
          unavailableReason: reason
        ),
        ExerciseActionDescriptor(
          kind: .paperReplaced,
          title: "Record Paper Replacement"
        ),
      ]
    case .accepted: []
    }
  }

  private func boundaryRepeatActions(
    _ directions: [BoundaryDirection],
    unavailableReason: String?
  ) -> [ExerciseActionDescriptor] {
    directions.flatMap { direction in
      [
        ExerciseActionDescriptor(
          kind: .redoBoundary(direction),
          title: "Redo \(direction.displayName) Boundary",
          unavailableReason: unavailableReason
        ),
        ExerciseActionDescriptor(
          kind: .recordAnotherBoundaryAttempt(direction),
          title: "Record Another \(direction.displayName) Attempt",
          unavailableReason: unavailableReason
        ),
      ]
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
      "Start the logical \(direction.displayName) Boundary Discovery owner."
    case .awaitContextualStop:
      "Observe the boundary, then choose Stop & Accept, Stop, or Cancel."
    case .cancelBoundaryJogAndAwaitIdle:
      "Send one jog cancel and await the original motion owner."
    case .commitBoundaryObservation(let direction):
      "Commit \(direction.displayName) from typed direction + Stop + controller Idle/final MPos. Camera and Vision are not consulted."
    case .actuatePen(let command): "Command Pen \(command.commandedState.rawValue)."
    case .awaitPhysicalPenConfirmation(let state, _):
      "Confirm whether the pen is physically \(state.rawValue)."
    }
  }

  private func scriptSpeaker(for participant: DiscoveryParticipant) -> ExerciseScriptSpeaker {
    participant == .operatorChoice ? .you : .plotter
  }

  private func reviewScriptSpeaker(
    for step: HumanGuidedDiscoveryStep
  ) -> ExerciseScriptSpeaker {
    switch step {
    case .penInteraction, .pairedBoundaryDiscoveryAndCentering: .you
    case .calibrateCameraAndVisibleCap, .calibratePenContactFromSparseMarks: .plotter
    }
  }

  private func drawingScriptSpeaker(
    _ step: ObservedDrawingTrialStep
  ) -> ExerciseScriptSpeaker {
    switch step {
    case .chooseIsolatedLinePlan, .compareIntendedAndObservedGeometry: .you
    case .captureLocalPreLineBaseline, .moveToLineStart, .drawIsolatedLine,
      .revealAndObserveNewInk: .plotter
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

}

extension LearningPathProjector {
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

  private func discoveryInstruction(_ action: DiscoveryAction) -> [PresentationFragment] {
    switch action {
    case .startBoundaryJog(let direction):
      [.text("Start motion toward"), .cue(.direction(direction))]
    case .awaitContextualStop(let direction):
      [.text("Observe"), .cue(.direction(direction)), .text("and choose how to end this attempt.")]
    case .awaitPhysicalPenConfirmation(let state, _):
      [.text("Confirm the pen is physically"), .cue(state == .up ? .up : .down)]
    case .actuatePen(let command):
      [.text("Command pen"), .cue(command.commandedState == .up ? .up : .down)]
    default: [.text(discoveryActionText(action))]
    }
  }

  private func discoveryQuestion(_ action: DiscoveryAction) -> ExerciseQuestionPresentation? {
    switch action {
    case .awaitContextualStop:
      ExerciseQuestionPresentation(prompt: [.text("How should this Boundary attempt end?")])
    case .awaitOperatorChoice(let question):
      ExerciseQuestionPresentation(prompt: [.text(question.prompt)])
    case .awaitPhysicalPenConfirmation(let state, let question):
      ExerciseQuestionPresentation(
        prompt: [
          .text(question.prompt),
          .text("Required physical pose:"),
          .cue(state == .up ? .up : .down),
        ]
      )
    default: nil
    }
  }

}
