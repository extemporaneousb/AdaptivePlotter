import Foundation
import PlotterEpisodeModel

public struct PlotterUIRevision: RawRepresentable, Codable, Hashable, Sendable {
  public let rawValue: UInt64

  public init(rawValue: UInt64) {
    self.rawValue = rawValue
  }
}

public struct PlotterUIRuntimeRevision: Codable, Hashable, Sendable {
  public let owner: String
  public let token: String

  public init(owner: String, token: String) {
    self.owner = owner
    self.token = token
  }
}

public struct PlotterUIActionID: RawRepresentable, Codable, Hashable, Sendable {
  public let rawValue: String

  public init(rawValue: String) {
    self.rawValue = rawValue
  }
}

public struct PlotterUIRequestID: RawRepresentable, Codable, Hashable, Sendable {
  public let rawValue: UUID

  public init(rawValue: UUID) {
    self.rawValue = rawValue
  }
}

public enum PlotterUIManualEvidenceDisposition: String, Codable, Hashable, Sendable {
  case acknowledgeAmbiguity
  case acknowledgePossibleInk
}

public enum PlotterUIRetainedComparisonIntent: String, Codable, Hashable, Sendable {
  case reviewExactFrame
  case resumeLivePreview
}

/// A bounded semantic request. These cases identify episode-owned intents or
/// opaque retained-workflow capabilities; they never carry effect closures or
/// lower controller, camera, Vision, or persistence ports.
public enum PlotterUIIntent: Hashable, Sendable {
  case learning(PlotterLearningIntent)
  case pointSelection(PlotterPointSelectionSubmission)
  case manualMotion(PlotterManualMotionIntent)
  case manualStop(capabilityID: UUID)
  case manualPublicationRecovery(capabilityID: UUID)
  case manualEvidenceDisposition(
    effectID: UUID,
    environment: PlotterEnvironment,
    observationID: UUID,
    disposition: PlotterUIManualEvidenceDisposition
  )
  case drawingDraft(PlotterDrawingDraftIntent)
  case drawingRun(PlotterDrawingRunIntent)
  case penInteraction(PlotterPenInteractionIntent)
  case retainedLearningAction(PlotterUIActionID)
  case retainedLearningReset(PlotterUIActionID)
  case retainedComparisonReview(PlotterUIRetainedComparisonIntent)
  case requestIncidentPackage
  /// A rendered control whose window-local draft cannot currently form a
  /// typed episode intent. The compiler publishes it only with an unsatisfied
  /// requirement, so the sink can never forward it to a lower runtime.
  case unavailableLocalInput(PlotterUIActionID)
}

public struct PlotterUIAction: Hashable, Sendable, Identifiable {
  public let id: PlotterUIActionID
  public let title: String
  public let intent: PlotterUIIntent
  public let unavailableReason: String?

  public init(
    id: PlotterUIActionID,
    title: String,
    intent: PlotterUIIntent,
    unavailableReason: String? = nil
  ) {
    self.id = id
    self.title = title
    self.intent = intent
    self.unavailableReason = unavailableReason
  }

  public var isAvailable: Bool { unavailableReason == nil }
}

public struct PlotterUIRequirement: Hashable, Sendable {
  public let id: String
  public let isSatisfied: Bool
  public let owner: String
  public let remedy: String

  public init(id: String, isSatisfied: Bool, owner: String, remedy: String) {
    self.id = id
    self.isSatisfied = isSatisfied
    self.owner = owner
    self.remedy = remedy
  }
}

public enum PlotterUIActionReachability: Hashable, Sendable {
  case global
  case learningOwner(String)
}

public struct PlotterUIActionCandidate: Hashable, Sendable {
  public let id: PlotterUIActionID
  public let title: String
  public let intent: PlotterUIIntent
  public let reachability: PlotterUIActionReachability
  public let requirements: [PlotterUIRequirement]

  public init(
    id: PlotterUIActionID,
    title: String,
    intent: PlotterUIIntent,
    reachability: PlotterUIActionReachability = .global,
    requirements: [PlotterUIRequirement] = []
  ) {
    self.id = id
    self.title = title
    self.intent = intent
    self.reachability = reachability
    self.requirements = requirements
  }
}

public struct PlotterUILearningMilestone: Hashable, Sendable {
  public let ownerID: String
  public let isComplete: Bool

  public init(ownerID: String, isComplete: Bool) {
    self.ownerID = ownerID
    self.isComplete = isComplete
  }
}

public struct PlotterUILearningFacts: Hashable, Sendable {
  public let isEnabled: Bool
  public let activeOwnerID: String?
  public let orderedMilestones: [PlotterUILearningMilestone]

  public init(
    isEnabled: Bool,
    activeOwnerID: String?,
    orderedMilestones: [PlotterUILearningMilestone]
  ) {
    self.isEnabled = isEnabled
    self.activeOwnerID = activeOwnerID
    self.orderedMilestones = orderedMilestones
  }
}

public struct PlotterUILearningProjection: Hashable, Sendable {
  public let isEnabled: Bool
  public let currentOwnerID: String?
  public let visitedMilestoneCount: Int
}

public enum PlotterUILearningOwnerKind: String, Hashable, Sendable {
  case discoveryStage
  case penInteraction
  case boundary
  case cameraCalibration
  case sparseTipCalibration
  case drawingStage
  case drawingValidation
}

public enum PlotterUILearningItemStatus: String, Hashable, Sendable {
  case complete
  case current
  case next
  case needsAttention
}

public enum PlotterUILearningBoundaryDirection: String, CaseIterable, Hashable, Sendable {
  case negativeX
  case positiveX
  case negativeY
  case positiveY
}

public enum PlotterUILearningChoice: String, CaseIterable, Hashable, Sendable {
  case yes
  case no
}

public enum PlotterUILearningPenCommand: String, Hashable, Sendable {
  case raise
  case lower
}

public enum PlotterUILearningCameraState: Hashable, Sendable {
  case readyWithoutProposal
  case readyWithProposal
  case active
}

public enum PlotterUILearningSparseState: Hashable, Sendable {
  case idle
  case drawingBatch
  case revealingBatch
  case awaitingFrozenClicks
  case fittingModel
  case reviewingModel
  case committingModel
  case possibleInkBlacklisted
  case accepted
}

public enum PlotterUILearningDrawingState: Hashable, Sendable {
  case choosePlan
  case captureBaseline
  case moveToStart
  case draw
  case revealAndObserve
  case compare
}

public enum PlotterUILearningActivePrompt: Hashable, Sendable {
  case choices([PlotterUILearningChoice])
  case penConfirmation(
    command: PlotterUILearningPenCommand,
    value: Int,
    minimumValue: Int,
    maximumValue: Int
  )
}

public enum PlotterUILearningStopKind: Hashable, Sendable {
  case boundary(direction: PlotterUILearningBoundaryDirection)
  case manualJog
  case manualDrawing
  case exercise(title: String, boundaryOwner: Bool)
  case drawingValidation
  case sparseTipBatch

  public var isManual: Bool {
    switch self {
    case .manualJog, .manualDrawing: true
    default: false
    }
  }
}

public struct PlotterUILearningStopFacts: Hashable, Sendable {
  public let capabilityID: UUID
  public let kind: PlotterUILearningStopKind

  public init(capabilityID: UUID, kind: PlotterUILearningStopKind) {
    self.capabilityID = capabilityID
    self.kind = kind
  }
}

public struct PlotterUILearningItemFacts: Hashable, Sendable {
  public let ownerID: String
  public let kind: PlotterUILearningOwnerKind
  public let stageID: String
  public let isStage: Bool
  public let isExercise: Bool
  public let isComplete: Bool
  public let isRepeatable: Bool

  public init(
    ownerID: String,
    kind: PlotterUILearningOwnerKind,
    stageID: String,
    isStage: Bool,
    isExercise: Bool,
    isComplete: Bool,
    isRepeatable: Bool
  ) {
    self.ownerID = ownerID
    self.kind = kind
    self.stageID = stageID
    self.isStage = isStage
    self.isExercise = isExercise
    self.isComplete = isComplete
    self.isRepeatable = isRepeatable
  }
}

public struct PlotterUILearningActionabilityFacts: Sendable {
  public let learning: PlotterUILearningFacts
  public let selectedOwnerID: String
  public let items: [PlotterUILearningItemFacts]
  public let savedTrainingCandidateIsPresent: Bool
  public let activeOwnerID: String?
  public let restartableOwnerID: String?
  public let stop: PlotterUILearningStopFacts?
  public let stopDispositionIsLatched: Bool
  public let stickyAmbiguityReason: String?
  public let discoveryStageHasFailure: Bool
  public let drawingStageHasFailure: Bool
  public let cameraState: PlotterUILearningCameraState
  public let sparseState: PlotterUILearningSparseState
  public let sparseCollectedClickCount: Int
  public let sparseSavedCheckpointMatchesPaper: Bool
  public let activePrompt: PlotterUILearningActivePrompt?
  public let penInteraction: PlotterPenInteractionProjection?
  public let startUnavailableReasons: [String: String]
  public let boundaryIsComplete: Bool
  public let boundaryHasCenterArrival: Bool
  public let boundaryCenterArrivalRetryIsRequired: Bool
  public let boundaryHasEstimatedCenter: Bool
  public let acceptedBoundaryDirections: [PlotterUILearningBoundaryDirection]
  public let allowedBoundaryDirections: [PlotterUILearningBoundaryDirection]
  public let selectedBoundaryDirection: PlotterUILearningBoundaryDirection
  public let drawingState: PlotterUILearningDrawingState
  public let selectedResetPlanIsPresent: Bool
  public let resetAllPlanIsPresent: Bool
  public let resetUnavailableReason: String?

  public init(
    learning: PlotterUILearningFacts,
    selectedOwnerID: String,
    items: [PlotterUILearningItemFacts],
    savedTrainingCandidateIsPresent: Bool = false,
    activeOwnerID: String? = nil,
    restartableOwnerID: String? = nil,
    stop: PlotterUILearningStopFacts? = nil,
    stopDispositionIsLatched: Bool = false,
    stickyAmbiguityReason: String? = nil,
    discoveryStageHasFailure: Bool = false,
    drawingStageHasFailure: Bool = false,
    cameraState: PlotterUILearningCameraState = .readyWithoutProposal,
    sparseState: PlotterUILearningSparseState = .idle,
    sparseCollectedClickCount: Int = 0,
    sparseSavedCheckpointMatchesPaper: Bool = false,
    activePrompt: PlotterUILearningActivePrompt? = nil,
    penInteraction: PlotterPenInteractionProjection? = nil,
    startUnavailableReasons: [String: String] = [:],
    boundaryIsComplete: Bool = false,
    boundaryHasCenterArrival: Bool = false,
    boundaryCenterArrivalRetryIsRequired: Bool = false,
    boundaryHasEstimatedCenter: Bool = false,
    acceptedBoundaryDirections: [PlotterUILearningBoundaryDirection] = [],
    allowedBoundaryDirections: [PlotterUILearningBoundaryDirection] = [],
    selectedBoundaryDirection: PlotterUILearningBoundaryDirection = .positiveX,
    drawingState: PlotterUILearningDrawingState = .choosePlan,
    selectedResetPlanIsPresent: Bool = false,
    resetAllPlanIsPresent: Bool = false,
    resetUnavailableReason: String? = nil
  ) {
    self.learning = learning
    self.selectedOwnerID = selectedOwnerID
    self.items = items
    self.savedTrainingCandidateIsPresent = savedTrainingCandidateIsPresent
    self.activeOwnerID = activeOwnerID
    self.restartableOwnerID = restartableOwnerID
    self.stop = stop
    self.stopDispositionIsLatched = stopDispositionIsLatched
    self.stickyAmbiguityReason = stickyAmbiguityReason
    self.discoveryStageHasFailure = discoveryStageHasFailure
    self.drawingStageHasFailure = drawingStageHasFailure
    self.cameraState = cameraState
    self.sparseState = sparseState
    self.sparseCollectedClickCount = sparseCollectedClickCount
    self.sparseSavedCheckpointMatchesPaper = sparseSavedCheckpointMatchesPaper
    self.activePrompt = activePrompt
    self.penInteraction = penInteraction
    self.startUnavailableReasons = startUnavailableReasons
    self.boundaryIsComplete = boundaryIsComplete
    self.boundaryHasCenterArrival = boundaryHasCenterArrival
    self.boundaryCenterArrivalRetryIsRequired = boundaryCenterArrivalRetryIsRequired
    self.boundaryHasEstimatedCenter = boundaryHasEstimatedCenter
    self.acceptedBoundaryDirections = acceptedBoundaryDirections
    self.allowedBoundaryDirections = allowedBoundaryDirections
    self.selectedBoundaryDirection = selectedBoundaryDirection
    self.drawingState = drawingState
    self.selectedResetPlanIsPresent = selectedResetPlanIsPresent
    self.resetAllPlanIsPresent = resetAllPlanIsPresent
    self.resetUnavailableReason = resetUnavailableReason
  }
}

public enum PlotterUILearningSemanticAction: Hashable, Sendable {
  case useSavedTraining
  case startNewLearning
  case start
  case choice(PlotterUILearningChoice)
  case setPenSetpoint(PlotterUILearningPenCommand, Int)
  case stopPenInteraction(PlotterPenInteractionCancellationCapabilityID)
  case selectDirection(PlotterUILearningBoundaryDirection)
  case cancel
  case stop(UUID)
  case restart
  case redoThisStep
  case recordAnotherAttempt
  case redoBoundary(PlotterUILearningBoundaryDirection)
  case recordAnotherBoundaryAttempt(PlotterUILearningBoundaryDirection)
  case moveToEstimatedCenter(retry: Bool, derivationUnavailable: Bool)
  case runCameraCalibration
  case acceptCameraCalibration
  case discardCameraSamples
  case rejectCameraCalibration
  case drawSparseTipCircles(PlotterUILearningSparseState)
  case undoSparseTipClick
  case clearSparseTipClicks
  case revalidateTipCalibration
  case acceptTipCalibration
  case rejectTipCalibration
  case retryTipCalibrationCommit
  case paperReplaced
}

public enum PlotterUILearningActionRole: Hashable, Sendable {
  case positive
  case destructive
  case standard
}

public struct PlotterUILearningActionDecision: Hashable, Sendable {
  public let action: PlotterUILearningSemanticAction
  public let title: String
  public let role: PlotterUILearningActionRole
  public let unavailableReason: String?

  public init(
    action: PlotterUILearningSemanticAction,
    title: String? = nil,
    role: PlotterUILearningActionRole? = nil,
    unavailableReason: String? = nil
  ) {
    self.action = action
    self.title = title ?? action.defaultTitle
    self.role = role ?? action.defaultRole
    self.unavailableReason = unavailableReason
  }

  public func actionID(ownerID: String) -> PlotterUIActionID {
    PlotterUIActionID(rawValue: "learning.retained.\(ownerID).\(String(describing: action))")
  }

  public func candidate(
    ownerID: String,
    id: PlotterUIActionID? = nil
  ) -> PlotterUIActionCandidate {
    let id = id ?? actionID(ownerID: ownerID)
    let intent: PlotterUIIntent = switch action {
    case .setPenSetpoint(let command, let value):
      .penInteraction(.setpoint(
        command: command == .raise ? .raise : .lower,
        value: value
      ))
    case .stopPenInteraction(let capability):
      .penInteraction(.stop(capability))
    default:
      .retainedLearningAction(id)
    }
    return PlotterUIActionCandidate(
      id: id,
      title: title,
      intent: intent,
      reachability: .global,
      requirements: unavailableReason.map {
        [PlotterUIRequirement(
          id: "\(id.rawValue).availability",
          isSatisfied: false,
          owner: "RetainedLearningWorkflow",
          remedy: $0
        )]
      } ?? []
    )
  }
}

public extension PlotterUIActionCandidate {
  static func retainedLearningReset(
    id: PlotterUIActionID,
    title: String,
    unavailableReason: String?
  ) -> PlotterUIActionCandidate {
    PlotterUIActionCandidate(
      id: id,
      title: title,
      intent: .retainedLearningReset(id),
      requirements: unavailableReason.map {
        [PlotterUIRequirement(
          id: "\(id.rawValue).availability",
          isSatisfied: false,
          owner: "RetainedLearningWorkflow",
          remedy: $0
        )]
      } ?? []
    )
  }
}

private extension PlotterUILearningBoundaryDirection {
  var displayName: String {
    switch self {
    case .negativeX: "X−"
    case .positiveX: "X+"
    case .negativeY: "Y−"
    case .positiveY: "Y+"
    }
  }
}

private extension PlotterUILearningSemanticAction {
  var defaultTitle: String {
    switch self {
    case .useSavedTraining: "Use Saved Learning"
    case .startNewLearning: "Start New Learning"
    case .start: "Start"
    case .choice(.yes): "YES"
    case .choice(.no): "NO"
    case .setPenSetpoint(let command, let value):
      "Set Pen \(command == .raise ? "Up" : "Down") S\(value)"
    case .stopPenInteraction: "Stop Pen Interaction"
    case .selectDirection(let direction): "Select \(direction.displayName)"
    case .cancel: "Cancel Attempt"
    case .stop: "Stop"
    case .restart: "Restart Attempt"
    case .redoThisStep: "Redo This Step"
    case .recordAnotherAttempt: "Record Another Attempt"
    case .redoBoundary(let direction): "Redo \(direction.displayName) Boundary"
    case .recordAnotherBoundaryAttempt(let direction):
      "Record Another \(direction.displayName) Attempt"
    case .moveToEstimatedCenter(let retry, let unavailable):
      retry ? "Retry Center Arrival"
        : (unavailable ? "Center Derivation Needs Attention" : "Move to Estimated Center")
    case .runCameraCalibration: "Run Five-Position Camera Calibration"
    case .acceptCameraCalibration: "Accept Camera Calibration"
    case .discardCameraSamples: "Discard Camera Samples"
    case .rejectCameraCalibration: "Reject Camera Calibration"
    case .drawSparseTipCircles(let state):
      switch state {
      case .drawingBatch: "Drawing Four Calibration Circles…"
      case .revealingBatch: "Capturing Calibration Reveal…"
      default: "Draw Four Calibration Circles"
      }
    case .undoSparseTipClick: "Undo Last Click"
    case .clearSparseTipClicks: "Clear Clicks on This Frame"
    case .revalidateTipCalibration: "Revalidate Saved Pen-Tip Calibration"
    case .acceptTipCalibration: "Accept Pen-Tip Calibration"
    case .rejectTipCalibration: "Reject Pen-Tip Calibration"
    case .retryTipCalibrationCommit: "Retry Pen-Tip Calibration Save"
    case .paperReplaced: "Record Paper Replacement"
    }
  }

  var defaultRole: PlotterUILearningActionRole {
    switch self {
    case .useSavedTraining, .start, .restart, .moveToEstimatedCenter,
      .runCameraCalibration, .acceptCameraCalibration, .drawSparseTipCircles,
      .revalidateTipCalibration, .acceptTipCalibration, .retryTipCalibrationCommit,
      .paperReplaced:
      .positive
    case .cancel, .stop, .stopPenInteraction, .discardCameraSamples, .rejectCameraCalibration,
      .rejectTipCalibration:
      .destructive
    case .choice(.yes): .positive
    case .startNewLearning, .choice(.no), .setPenSetpoint, .selectDirection,
      .redoThisStep, .recordAnotherAttempt,
      .redoBoundary, .recordAnotherBoundaryAttempt, .undoSparseTipClick,
      .clearSparseTipClicks:
      .standard
    }
  }
}

public struct PlotterUILearningPenAdjustmentDecision: Hashable, Sendable {
  public let command: PlotterUILearningPenCommand
  public let value: Int
  public let minimumValue: Int
  public let maximumValue: Int
  public let unavailableReason: String?
}

public struct PlotterUILearningDirectionDecision: Hashable, Sendable {
  public let options: [PlotterUILearningBoundaryDirection]
  public let selected: PlotterUILearningBoundaryDirection
}

public struct PlotterUILearningActionStripDecision: Hashable, Sendable {
  public let ownerID: String
  public let actions: [PlotterUILearningActionDecision]
  public let directionSelection: PlotterUILearningDirectionDecision?
  public let penAdjustment: PlotterUILearningPenAdjustmentDecision?
  public let mustRemainVisible: Bool

  /// Every semantic request rendered by this strip, including slider and
  /// direction-selector values that are not represented as buttons.
  public func actionDecisions() -> [PlotterUILearningActionDecision] {
    var result = actions
    if let penAdjustment {
      let range = penAdjustment.minimumValue...penAdjustment.maximumValue
      result.append(contentsOf: range.map { value in
        PlotterUILearningActionDecision(
          action: .setPenSetpoint(penAdjustment.command, value),
          unavailableReason: penAdjustment.unavailableReason
        )
      })
    }
    if let directionSelection {
      result.append(contentsOf: directionSelection.options.map { direction in
        PlotterUILearningActionDecision(
          action: .selectDirection(direction)
        )
      })
    }
    return result
  }

  public func candidates() -> [PlotterUIActionCandidate] {
    actionDecisions().map { $0.candidate(ownerID: ownerID) }
  }

  public func semanticAction(
    for actionID: PlotterUIActionID
  ) -> PlotterUILearningSemanticAction? {
    if let action = actionDecisions().first(where: {
      $0.actionID(ownerID: ownerID) == actionID
    }) {
      return action.action
    }
    return nil
  }
}

public struct PlotterUILearningItemDecision: Hashable, Sendable {
  public let ownerID: String
  public let status: PlotterUILearningItemStatus
  public let isRepeatable: Bool
}

public struct PlotterUILearningActionabilityProjection: Sendable {
  public let learning: PlotterUILearningProjection
  public let penInteraction: PlotterPenInteractionProjection?
  public let items: [PlotterUILearningItemDecision]
  public let strips: [PlotterUILearningActionStripDecision]
  public let contextualStop: PlotterUILearningStopFacts?
  public let selectedResetPlanIsReachable: Bool
  public let resetAllPlanIsReachable: Bool
  public let resetUnavailableReason: String?
  public let visitedItemCount: Int
  public let diagnostics: [PlotterUIDiagnostic]

  public func item(ownerID: String) -> PlotterUILearningItemDecision? {
    items.first { $0.ownerID == ownerID }
  }

  public func strip(ownerID: String) -> PlotterUILearningActionStripDecision? {
    strips.first { $0.ownerID == ownerID }
  }
}

/// Sole Learning actionability compiler. Inputs are copied primitive facts;
/// output contains no controller, camera, Vision, persistence, or effect port.
public struct PlotterUILearningActionabilityCompiler: Sendable {
  public struct Limits: Hashable, Sendable {
    public let maximumItemVisitCount: Int
    public let maximumActionCountPerStrip: Int
    public let maximumChoiceVisitCount: Int
    public let maximumDirectionVisitCount: Int
    public let maximumDiagnosticCount: Int

    public init(
      maximumItemVisitCount: Int = 64,
      maximumActionCountPerStrip: Int = 64,
      maximumChoiceVisitCount: Int = 8,
      maximumDirectionVisitCount: Int = 8,
      maximumDiagnosticCount: Int = 64
    ) {
      self.maximumItemVisitCount = max(1, maximumItemVisitCount)
      self.maximumActionCountPerStrip = max(1, maximumActionCountPerStrip)
      self.maximumChoiceVisitCount = max(1, maximumChoiceVisitCount)
      self.maximumDirectionVisitCount = max(1, maximumDirectionVisitCount)
      self.maximumDiagnosticCount = max(1, maximumDiagnosticCount)
    }
  }

  public let limits: Limits

  public init(limits: Limits = Limits()) {
    self.limits = limits
  }

  public func compile(
    _ facts: PlotterUILearningActionabilityFacts
  ) -> PlotterUILearningActionabilityProjection {
    var diagnostics: [PlotterUIDiagnostic] = []
    func diagnostic(_ summary: String) {
      guard diagnostics.count < limits.maximumDiagnosticCount else { return }
      diagnostics.append(PlotterUIDiagnostic(
        id: "learning-actionability-\(diagnostics.count)",
        kind: .projectionTruncated,
        summary: summary
      ))
    }
    let learning = PlotterUICompiler(limits: .init(
      maximumLearningMilestoneVisitCount: limits.maximumItemVisitCount,
      maximumDiagnosticCount: limits.maximumDiagnosticCount
    )).learningProjection(facts.learning)
    let visited = Array(facts.items.prefix(limits.maximumItemVisitCount))
    if facts.items.count > visited.count {
      diagnostic("Learning item visits exceeded bounded capacity.")
    }
    let currentStageID = visited.first {
      $0.ownerID == learning.currentOwnerID
    }?.stageID
    let items = visited.map { item in
      PlotterUILearningItemDecision(
        ownerID: item.ownerID,
        status: itemStatus(
          item,
          currentOwnerID: learning.currentOwnerID,
          currentStageID: currentStageID,
          facts: facts
        ),
        isRepeatable: item.isRepeatable
      )
    }
    var strips: [PlotterUILearningActionStripDecision] = []
    for item in visited {
      if let strip = actionStrip(for: item, learning: learning, facts: facts) {
        if strip.actions.count > limits.maximumActionCountPerStrip {
          diagnostic("Learning actions exceeded bounded capacity for \(item.ownerID).")
        }
        strips.append(PlotterUILearningActionStripDecision(
          ownerID: strip.ownerID,
          actions: Array(strip.actions.prefix(limits.maximumActionCountPerStrip)),
          directionSelection: strip.directionSelection.map {
            PlotterUILearningDirectionDecision(
              options: Array($0.options.prefix(limits.maximumDirectionVisitCount)),
              selected: $0.selected
            )
          },
          penAdjustment: strip.penAdjustment,
          mustRemainVisible: strip.mustRemainVisible
        ))
      }
    }
    return PlotterUILearningActionabilityProjection(
      learning: learning,
      penInteraction: facts.penInteraction,
      items: items,
      strips: strips,
      contextualStop: facts.stopDispositionIsLatched ? nil : facts.stop,
      selectedResetPlanIsReachable: facts.selectedResetPlanIsPresent,
      resetAllPlanIsReachable: facts.resetAllPlanIsPresent,
      resetUnavailableReason: facts.resetUnavailableReason,
      visitedItemCount: visited.count,
      diagnostics: diagnostics
    )
  }

  private func itemStatus(
    _ item: PlotterUILearningItemFacts,
    currentOwnerID: String?,
    currentStageID: String?,
    facts: PlotterUILearningActionabilityFacts
  ) -> PlotterUILearningItemStatus {
    if facts.restartableOwnerID == item.ownerID { return .needsAttention }
    if item.kind == .penInteraction,
      let penInteraction = facts.penInteraction,
      penInteractionNeedsAttention(penInteraction)
    {
      return .needsAttention
    }
    if item.isComplete { return .complete }
    guard item.ownerID == currentOwnerID || (item.isStage && item.stageID == currentStageID)
    else { return .next }
    if item.stageID == "discovery", facts.discoveryStageHasFailure {
      return .needsAttention
    }
    if item.stageID == "drawing", facts.drawingStageHasFailure {
      return .needsAttention
    }
    return .current
  }

  private func actionStrip(
    for item: PlotterUILearningItemFacts,
    learning: PlotterUILearningProjection,
    facts: PlotterUILearningActionabilityFacts
  ) -> PlotterUILearningActionStripDecision? {
    guard learning.isEnabled, item.isExercise else { return nil }
    let current = learning.currentOwnerID
    let activePenInteraction: PlotterPenInteractionProjection? =
      if item.kind == .penInteraction,
        let penInteraction = facts.penInteraction,
        penInteraction.reference.operationID != nil
      {
        penInteraction
      } else {
        nil
      }
    var penSetpointDrainIsInProgress = false
    if let activePenInteraction {
      let invariantReason =
        "PlotterPenInteractionRuntime owns an active operation without a valid cancellable phase. Restart the application; no generic Stop was substituted."
      guard let capability = activePenInteraction.cancellationCapabilityID else {
        return strip(item.ownerID, [.init(
          action: .start,
          title: "Pen Interaction Stop unavailable",
          unavailableReason:
            "PlotterPenInteractionRuntime owns an active operation without its exact cancellation capability. Restart the application; no generic Stop was substituted."
        )], mustRemainVisible: true)
      }
      switch activePenInteraction.phase {
      case .settling, .cancelling, .awaitingCapSelection, .awaitingControllerCommand:
        return strip(
          item.ownerID,
          [.init(action: .stopPenInteraction(capability), title: "Stop Pen Interaction")],
          mustRemainVisible: true
        )
      case .drainingSetpoint:
        penSetpointDrainIsInProgress = true
      case .awaitingConfirmation, .refused, .possiblePhysicalChange:
        break
      case .idle, .succeeded:
        return strip(item.ownerID, [.init(
          action: .start,
          title: "Pen Interaction state unavailable",
          unavailableReason: invariantReason
        )], mustRemainVisible: true)
      }
    }
    if facts.savedTrainingCandidateIsPresent {
      guard item.ownerID == current else { return nil }
      return strip(item.ownerID, [
        .init(action: .useSavedTraining),
        .init(action: .startNewLearning),
      ], mustRemainVisible: true)
    }
    if facts.activeOwnerID == item.ownerID || activePenInteraction != nil {
      if activePenInteraction == nil,
        let stop = facts.stop,
        !stop.kind.isManual,
        !facts.stopDispositionIsLatched
      {
        let title: String = if case .boundary = stop.kind { "Stop Boundary Search" } else { "Stop" }
        return strip(
          item.ownerID,
          [.init(action: .stop(stop.capabilityID), title: title)],
          mustRemainVisible: true
        )
      }
      if item.kind == .drawingValidation {
        return strip(
          item.ownerID,
          [.init(
            action: .start,
            title: "Draw and Validate Drawing Border…",
            unavailableReason: "Drawing Border validation is in progress."
          )],
          mustRemainVisible: true
        )
      }
      var actions: [PlotterUILearningActionDecision] = []
      var adjustment: PlotterUILearningPenAdjustmentDecision?
      if item.kind == .penInteraction,
        let penInteraction = facts.penInteraction,
        penInteractionNeedsAttention(penInteraction)
      {
        actions = [.init(
          action: .start,
          title: "Pen Interaction needs attention",
          unavailableReason: penInteractionAttentionReason(penInteraction)
        )]
      } else if item.stageID == "discovery", let ambiguity = facts.stickyAmbiguityReason {
        actions = [.init(
          action: .start,
          title: "Machine action unavailable",
          unavailableReason: ambiguity
        )]
      } else if item.kind == .cameraCalibration {
        switch facts.cameraState {
        case .active:
          actions = [.init(
            action: .runCameraCalibration,
            title: "Running Five-Position Camera Calibration…",
            unavailableReason: "Camera calibration is in progress."
          )]
        case .readyWithoutProposal:
          actions = [.init(action: .runCameraCalibration), .init(action: .discardCameraSamples)]
        case .readyWithProposal:
          actions = [.init(action: .acceptCameraCalibration), .init(action: .rejectCameraCalibration)]
        }
      } else if item.kind == .sparseTipCalibration {
        actions = sparseActions(facts)
      } else if let prompt = facts.activePrompt {
        switch prompt {
        case .choices(let choices):
          actions = Array(choices.prefix(limits.maximumChoiceVisitCount)).map {
            .init(action: .choice($0))
          }
        case .penConfirmation(let command, let value, let minimum, let maximum):
          let reason = facts.startUnavailableReasons[item.ownerID]
          actions = penSetpointDrainIsInProgress ? [] : [.init(
              action: .choice(.yes),
              title: command == .raise ? "Confirm Pen Up" : "Confirm Pen Down",
              unavailableReason: reason
            )]
          adjustment = PlotterUILearningPenAdjustmentDecision(
            command: command,
            value: value,
            minimumValue: minimum,
            maximumValue: maximum,
            unavailableReason: reason
          )
        }
      }
      if let capability = activePenInteraction?.cancellationCapabilityID {
        actions.append(.init(
          action: .stopPenInteraction(capability),
          title: "Stop Pen Interaction"
        ))
      } else if !facts.stopDispositionIsLatched, facts.cameraState != .active {
        actions.append(.init(action: .cancel))
      }
      return PlotterUILearningActionStripDecision(
        ownerID: item.ownerID,
        actions: actions,
        directionSelection: nil,
        penAdjustment: adjustment,
        mustRemainVisible: facts.stop != nil || activePenInteraction != nil
      )
    }
    if facts.restartableOwnerID == item.ownerID {
      guard facts.stickyAmbiguityReason == nil else { return nil }
      return strip(item.ownerID, [.init(
        action: .restart,
        title: item.kind == .drawingValidation
          ? "Retry Drawing Border Validation" : "Restart Attempt"
      )])
    }
    if item.isComplete {
      guard item.ownerID == facts.selectedOwnerID else { return nil }
      if item.kind == .drawingValidation { return nil }
      if item.kind == .boundary {
        return strip(item.ownerID, boundaryRepeatActions(facts.acceptedBoundaryDirections))
      }
      var actions = [PlotterUILearningActionDecision(action: .redoThisStep)]
      if item.isRepeatable { actions.append(.init(action: .recordAnotherAttempt)) }
      return strip(item.ownerID, actions)
    }
    guard item.ownerID == current else { return nil }
    let reason = facts.startUnavailableReasons[item.ownerID]
    if item.kind == .boundary, facts.boundaryIsComplete, !facts.boundaryHasCenterArrival {
      if facts.boundaryCenterArrivalRetryIsRequired {
        return strip(item.ownerID, [
          .init(
            action: .moveToEstimatedCenter(retry: true, derivationUnavailable: false),
            unavailableReason: reason
          )
        ])
      }
      let centerReason = facts.boundaryHasEstimatedCenter
        ? reason : "Accepted boundaries do not currently derive a valid center."
      return strip(
        item.ownerID,
        [.init(
          action: .moveToEstimatedCenter(
            retry: false,
            derivationUnavailable: !facts.boundaryHasEstimatedCenter
          ),
          unavailableReason: centerReason
        )] + boundaryRepeatActions(facts.acceptedBoundaryDirections)
      )
    }
    if item.kind == .drawingValidation {
      let title: String = switch facts.drawingState {
      case .choosePlan: "Draw and Validate Drawing Border"
      case .revealAndObserve: "Resume Drawing Border Observation"
      case .compare: "Complete Drawing Border Comparison"
      case .captureBaseline, .moveToStart, .draw: "Resume Drawing Border Validation"
      }
      return strip(item.ownerID, [.init(
        action: .start,
        title: title,
        unavailableReason: reason
      )])
    }
    if item.kind == .cameraCalibration {
      return strip(item.ownerID, [.init(action: .runCameraCalibration, unavailableReason: reason)])
    }
    if item.kind == .sparseTipCalibration, facts.sparseSavedCheckpointMatchesPaper {
      return strip(item.ownerID, [.init(action: .revalidateTipCalibration, unavailableReason: reason)])
    }
    if item.kind == .sparseTipCalibration {
      if facts.sparseState == .possibleInkBlacklisted {
        return strip(item.ownerID, [.init(action: .paperReplaced)])
      }
      return strip(item.ownerID, [
        .init(action: .drawSparseTipCircles(facts.sparseState), unavailableReason: reason)
      ])
    }
    let direction = item.kind == .boundary
      ? PlotterUILearningDirectionDecision(
        options: Array(facts.allowedBoundaryDirections.prefix(limits.maximumDirectionVisitCount)),
        selected: facts.selectedBoundaryDirection
      ) : nil
    return PlotterUILearningActionStripDecision(
      ownerID: item.ownerID,
      actions: [.init(
        action: .start,
        title: item.kind == .penInteraction
          ? "Identify Pen Cap" : "Move Toward \(facts.selectedBoundaryDirection.displayName)",
        unavailableReason: reason
      )],
      directionSelection: direction,
      penAdjustment: nil,
      mustRemainVisible: false
    )
  }

  private func sparseActions(
    _ facts: PlotterUILearningActionabilityFacts
  ) -> [PlotterUILearningActionDecision] {
    switch facts.sparseState {
    case .idle, .drawingBatch, .revealingBatch:
      let reason: String? = switch facts.sparseState {
      case .drawingBatch: "The four-circle calibration is in progress."
      case .revealingBatch: "The final Pen-Up calibration reveal is in progress."
      default: nil
      }
      return [.init(action: .drawSparseTipCircles(facts.sparseState), unavailableReason: reason)]
    case .awaitingFrozenClicks:
      return facts.sparseCollectedClickCount == 0 ? [] : [
        .init(action: .undoSparseTipClick), .init(action: .clearSparseTipClicks),
      ]
    case .fittingModel:
      return [.init(
        action: .retryTipCalibrationCommit,
        title: "Fitting Tip Calibration…",
        unavailableReason: "The four observations are being created and fitted."
      )]
    case .reviewingModel:
      return [
        .init(action: .acceptTipCalibration),
        .init(action: .undoSparseTipClick),
        .init(action: .clearSparseTipClicks),
        .init(action: .rejectTipCalibration),
      ]
    case .committingModel:
      return [.init(action: .retryTipCalibrationCommit)]
    case .possibleInkBlacklisted:
      return [.init(action: .paperReplaced)]
    case .accepted:
      return []
    }
  }

  private func penInteractionNeedsAttention(
    _ projection: PlotterPenInteractionProjection
  ) -> Bool {
    if projection.reference.operationID != nil,
      projection.cancellationCapabilityID == nil
    {
      return true
    }
    if projection.lastRefusal != nil { return true }
    return switch projection.phase {
    case .refused, .possiblePhysicalChange: true
    default: false
    }
  }

  private func penInteractionAttentionReason(
    _ projection: PlotterPenInteractionProjection
  ) -> String {
    if projection.reference.operationID != nil,
      projection.cancellationCapabilityID == nil
    {
      return "PlotterPenInteractionRuntime owns an active operation without its exact cancellation capability. Restart the application; no generic Stop was substituted."
    }
    if let refusal = projection.lastRefusal {
      return "Pen Interaction was refused by \(refusal.owner): \(refusal.reason). Remedy: \(refusal.remedy)."
    }
    switch projection.phase {
    case .refused(let reason):
      return "Pen Interaction lower execution was refused: \(reason). No command will be resent automatically."
    case .possiblePhysicalChange(let detail):
      return "\(detail) Inspect the pen and paper before deciding how to recover; no command will be resent automatically."
    default:
      return "Resolve the current Pen Interaction state before continuing."
    }
  }

  private func boundaryRepeatActions(
    _ directions: [PlotterUILearningBoundaryDirection]
  ) -> [PlotterUILearningActionDecision] {
    Array(directions.prefix(limits.maximumDirectionVisitCount)).flatMap { direction in
      [
        .init(action: .redoBoundary(direction)),
        .init(action: .recordAnotherBoundaryAttempt(direction)),
      ]
    }
  }

  private func strip(
    _ ownerID: String,
    _ actions: [PlotterUILearningActionDecision],
    mustRemainVisible: Bool = false
  ) -> PlotterUILearningActionStripDecision {
    PlotterUILearningActionStripDecision(
      ownerID: ownerID,
      actions: actions,
      directionSelection: nil,
      penAdjustment: nil,
      mustRemainVisible: mustRemainVisible
    )
  }
}

public struct PlotterUIIncidentPackageMetadata: Hashable, Sendable {
  public let formatVersion: UInt64
  public let encoding: String
  public let exactByteCount: Int
  public let payloadSHA256: String
  public let integrityScope: String
  public let physicalEvidenceClaimed: Bool

  public init(
    formatVersion: UInt64,
    encoding: String,
    exactByteCount: Int,
    payloadSHA256: String,
    integrityScope: String,
    physicalEvidenceClaimed: Bool
  ) {
    self.formatVersion = formatVersion
    self.encoding = encoding
    self.exactByteCount = exactByteCount
    self.payloadSHA256 = payloadSHA256
    self.integrityScope = integrityScope
    self.physicalEvidenceClaimed = physicalEvidenceClaimed
  }
}

public enum PlotterUIIncidentPackageState: Hashable, Sendable {
  case unavailable(reason: String)
  case available
  case loading(phase: String, completedUnitCount: UInt8, totalUnitCount: UInt8)
  case completed(PlotterUIIncidentPackageMetadata)
  case refused(reason: String, remedy: String)
}

public struct PlotterUIDiagnostic: Hashable, Sendable, Identifiable {
  public enum Kind: String, Codable, Hashable, Sendable {
    case invalidAction
    case duplicateAction
    case projectionTruncated
    case staleRequest
    case unavailableAction
  }

  public let id: String
  public let kind: Kind
  public let summary: String

  public init(id: String, kind: Kind, summary: String) {
    self.id = id
    self.kind = kind
    self.summary = summary
  }
}

public struct PlotterUICompilerInput: Sendable {
  public let revision: PlotterUIRevision
  public let runtimeRevisions: [PlotterUIRuntimeRevision]
  public let candidates: [PlotterUIActionCandidate]
  public let learning: PlotterUILearningFacts?
  public let incidentPackage: PlotterUIIncidentPackageState

  public init(
    revision: PlotterUIRevision,
    runtimeRevisions: [PlotterUIRuntimeRevision],
    candidates: [PlotterUIActionCandidate],
    learning: PlotterUILearningFacts? = nil,
    incidentPackage: PlotterUIIncidentPackageState = .unavailable(
      reason: "Incident-package source is unavailable."
    )
  ) {
    self.revision = revision
    self.runtimeRevisions = runtimeRevisions
    self.candidates = candidates
    self.learning = learning
    self.incidentPackage = incidentPackage
  }

  public init(
    revision: PlotterUIRevision,
    runtimeRevisions: [PlotterUIRuntimeRevision],
    actions: [PlotterUIAction],
    incidentPackage: PlotterUIIncidentPackageState = .unavailable(
      reason: "Incident-package source is unavailable."
    )
  ) {
    self.init(
      revision: revision,
      runtimeRevisions: runtimeRevisions,
      candidates: actions.map { action in
        PlotterUIActionCandidate(
          id: action.id,
          title: action.title,
          intent: action.intent,
          requirements: action.unavailableReason.map {
            [PlotterUIRequirement(
              id: "legacy-availability",
              isSatisfied: false,
              owner: "retained-owner",
              remedy: $0
            )]
          } ?? []
        )
      },
      incidentPackage: incidentPackage
    )
  }
}

public struct PlotterUIProjection: Sendable {
  public let revision: PlotterUIRevision
  public let runtimeRevisions: [PlotterUIRuntimeRevision]
  public let actions: [PlotterUIAction]
  public let learning: PlotterUILearningProjection?
  public let incidentPackage: PlotterUIIncidentPackageState
  public let diagnostics: [PlotterUIDiagnostic]
  public let visitedCandidateCount: Int

  public init(
    revision: PlotterUIRevision,
    runtimeRevisions: [PlotterUIRuntimeRevision],
    actions: [PlotterUIAction],
    learning: PlotterUILearningProjection?,
    incidentPackage: PlotterUIIncidentPackageState,
    diagnostics: [PlotterUIDiagnostic],
    visitedCandidateCount: Int
  ) {
    self.revision = revision
    self.runtimeRevisions = runtimeRevisions
    self.actions = actions
    self.learning = learning
    self.incidentPackage = incidentPackage
    self.diagnostics = diagnostics
    self.visitedCandidateCount = visitedCandidateCount
  }

  public func action(id: PlotterUIActionID) -> PlotterUIAction? {
    actions.first { $0.id == id }
  }

  public func request(
    id requestID: PlotterUIRequestID = PlotterUIRequestID(rawValue: UUID()),
    for actionID: PlotterUIActionID
  ) -> PlotterUIRequest? {
    guard let action = action(id: actionID), action.isAvailable else { return nil }
    return PlotterUIRequest(
      id: requestID,
      uiRevision: revision,
      runtimeRevisions: runtimeRevisions,
      actionID: action.id,
      intent: action.intent
    )
  }

  public func request(
    id requestID: PlotterUIRequestID = PlotterUIRequestID(rawValue: UUID()),
    matching intent: PlotterUIIntent
  ) -> PlotterUIRequest? {
    guard let action = actions.first(where: { $0.intent == intent && $0.isAvailable }) else {
      return nil
    }
    return request(id: requestID, for: action.id)
  }
}

public struct PlotterUIRequest: Hashable, Sendable, Identifiable {
  public let id: PlotterUIRequestID
  public let uiRevision: PlotterUIRevision
  public let runtimeRevisions: [PlotterUIRuntimeRevision]
  public let actionID: PlotterUIActionID
  public let intent: PlotterUIIntent

  public init(
    id: PlotterUIRequestID,
    uiRevision: PlotterUIRevision,
    runtimeRevisions: [PlotterUIRuntimeRevision],
    actionID: PlotterUIActionID,
    intent: PlotterUIIntent
  ) {
    self.id = id
    self.uiRevision = uiRevision
    self.runtimeRevisions = runtimeRevisions
    self.actionID = actionID
    self.intent = intent
  }
}

public enum PlotterUIRequestRefusalReason: String, Codable, Hashable, Sendable {
  case staleUIRevision
  case staleRuntimeRevision
  case unknownAction
  case mismatchedIntent
  case unavailableAction
  case unavailableIncidentSource
  case retainedOwnerRefused
}

public struct PlotterUIRequestRefusal: Hashable, Sendable {
  public let requestID: PlotterUIRequestID
  public let reason: PlotterUIRequestRefusalReason
  public let owner: String
  public let submittedUIRevision: PlotterUIRevision
  public let currentUIRevision: PlotterUIRevision
  public let submittedRuntimeRevisions: [PlotterUIRuntimeRevision]
  public let currentRuntimeRevisions: [PlotterUIRuntimeRevision]
  public let remedy: String

  public init(
    requestID: PlotterUIRequestID,
    reason: PlotterUIRequestRefusalReason,
    owner: String,
    submittedUIRevision: PlotterUIRevision,
    currentUIRevision: PlotterUIRevision,
    submittedRuntimeRevisions: [PlotterUIRuntimeRevision],
    currentRuntimeRevisions: [PlotterUIRuntimeRevision],
    remedy: String
  ) {
    self.requestID = requestID
    self.reason = reason
    self.owner = owner
    self.submittedUIRevision = submittedUIRevision
    self.currentUIRevision = currentUIRevision
    self.submittedRuntimeRevisions = submittedRuntimeRevisions
    self.currentRuntimeRevisions = currentRuntimeRevisions
    self.remedy = remedy
  }
}

public enum PlotterUIRequestDisposition: Hashable, Sendable {
  case accepted(requestID: PlotterUIRequestID)
  case refused(PlotterUIRequestRefusal)
}

@MainActor
public protocol PlotterUIIntentSink: AnyObject {
  func submitPlotterUIRequest(_ request: PlotterUIRequest) async -> PlotterUIRequestDisposition
}

/// Deterministic bounded compiler for semantic actions. Runtime revision order
/// is normalized, action identities are unique, and invalid input is surfaced
/// as diagnostics rather than silently becoming an inert control.
public struct PlotterUICompiler: Sendable {
  public struct Limits: Hashable, Sendable {
    public let maximumActionCount: Int
    public let maximumCandidateVisitCount: Int
    public let maximumRuntimeRevisionCount: Int
    public let maximumLearningMilestoneVisitCount: Int
    public let maximumDiagnosticCount: Int
    public let maximumTextLength: Int

    public init(
      maximumActionCount: Int = 4_096,
      maximumCandidateVisitCount: Int = 4_096,
      maximumRuntimeRevisionCount: Int = 32,
      maximumLearningMilestoneVisitCount: Int = 64,
      maximumDiagnosticCount: Int = 64,
      maximumTextLength: Int = 512
    ) {
      self.maximumActionCount = max(1, maximumActionCount)
      self.maximumCandidateVisitCount = max(1, maximumCandidateVisitCount)
      self.maximumRuntimeRevisionCount = max(1, maximumRuntimeRevisionCount)
      self.maximumLearningMilestoneVisitCount = max(1, maximumLearningMilestoneVisitCount)
      self.maximumDiagnosticCount = max(1, maximumDiagnosticCount)
      self.maximumTextLength = max(1, maximumTextLength)
    }
  }

  public let limits: Limits

  public init(limits: Limits = Limits()) {
    self.limits = limits
  }

  public func compile(_ input: PlotterUICompilerInput) -> PlotterUIProjection {
    var diagnostics: [PlotterUIDiagnostic] = []
    func appendDiagnostic(_ kind: PlotterUIDiagnostic.Kind, _ summary: String) {
      guard diagnostics.count < limits.maximumDiagnosticCount else { return }
      diagnostics.append(PlotterUIDiagnostic(
        id: "\(kind.rawValue)-\(diagnostics.count)",
        kind: kind,
        summary: bounded(summary)
      ))
    }
    let runtimeRevisions = normalizedRuntimeRevisions(
      Array(input.runtimeRevisions.prefix(limits.maximumRuntimeRevisionCount))
    )
    if input.runtimeRevisions.count > limits.maximumRuntimeRevisionCount {
      appendDiagnostic(
        .projectionTruncated,
        "Runtime-revision projection exceeded its bounded capacity."
      )
    }

    let learningProjection = compileLearning(input.learning, appendDiagnostic: appendDiagnostic)

    var seen: Set<PlotterUIActionID> = []
    var actions: [PlotterUIAction] = []
    let visitedCandidates = Array(input.candidates.prefix(limits.maximumCandidateVisitCount))
    if input.candidates.count > limits.maximumCandidateVisitCount {
      appendDiagnostic(.projectionTruncated, "UI candidate visits exceeded bounded capacity.")
    }
    for candidate in visitedCandidates {
      guard actions.count < limits.maximumActionCount else {
        appendDiagnostic(.projectionTruncated, "UI action projection exceeded bounded capacity.")
        break
      }
      guard isReachable(candidate.reachability, learning: learningProjection) else { continue }
      let trimmedID = candidate.id.rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !trimmedID.isEmpty else {
        appendDiagnostic(.invalidAction, "An action had no identity.")
        continue
      }
      let normalizedID = PlotterUIActionID(rawValue: bounded(trimmedID))
      guard seen.insert(normalizedID).inserted else {
        appendDiagnostic(.duplicateAction, "Duplicate action identity: \(normalizedID.rawValue).")
        continue
      }
      let firstUnsatisfied = candidate.requirements.first { !$0.isSatisfied }
      actions.append(
        PlotterUIAction(
          id: normalizedID,
          title: bounded(candidate.title),
          intent: candidate.intent,
          unavailableReason: firstUnsatisfied.map {
            bounded("\($0.owner): \($0.remedy)")
          }
        )
      )
    }

    return PlotterUIProjection(
      revision: input.revision,
      runtimeRevisions: runtimeRevisions,
      actions: actions,
      learning: learningProjection,
      incidentPackage: bounded(input.incidentPackage),
      diagnostics: diagnostics,
      visitedCandidateCount: visitedCandidates.count
    )
  }

  /// Projects Learning reachability from copied facts. App composition may
  /// normalize facts into this value, but it does not choose the current owner.
  public func learningProjection(
    _ facts: PlotterUILearningFacts
  ) -> PlotterUILearningProjection {
    compileLearning(facts) { _, _ in }
      ?? PlotterUILearningProjection(
        isEnabled: facts.isEnabled,
        currentOwnerID: nil,
        visitedMilestoneCount: 0
      )
  }

  private func compileLearning(
    _ facts: PlotterUILearningFacts?,
    appendDiagnostic: (PlotterUIDiagnostic.Kind, String) -> Void
  ) -> PlotterUILearningProjection? {
    guard let facts else { return nil }
    let milestones = Array(
      facts.orderedMilestones.prefix(limits.maximumLearningMilestoneVisitCount)
    )
    if facts.orderedMilestones.count > limits.maximumLearningMilestoneVisitCount {
      appendDiagnostic(.projectionTruncated, "Learning milestone visits exceeded bounded capacity.")
    }
    let current = facts.activeOwnerID
      ?? milestones.first(where: { !$0.isComplete })?.ownerID
      ?? milestones.last?.ownerID
    return PlotterUILearningProjection(
      isEnabled: facts.isEnabled,
      currentOwnerID: current.map(bounded),
      visitedMilestoneCount: milestones.count
    )
  }

  private func isReachable(
    _ reachability: PlotterUIActionReachability,
    learning: PlotterUILearningProjection?
  ) -> Bool {
    switch reachability {
    case .global: true
    case .learningOwner(let owner): learning?.isEnabled == true && learning?.currentOwnerID == owner
    }
  }

  private func normalizedRuntimeRevisions(
    _ revisions: [PlotterUIRuntimeRevision]
  ) -> [PlotterUIRuntimeRevision] {
    var byOwner: [String: PlotterUIRuntimeRevision] = [:]
    for revision in revisions {
      let owner = bounded(revision.owner.trimmingCharacters(in: .whitespacesAndNewlines))
      guard !owner.isEmpty else { continue }
      byOwner[owner] = PlotterUIRuntimeRevision(owner: owner, token: bounded(revision.token))
    }
    return byOwner.values.sorted { $0.owner < $1.owner }
  }

  private func bounded(_ text: String) -> String {
    String(text.prefix(limits.maximumTextLength))
  }

  private func bounded(_ state: PlotterUIIncidentPackageState) -> PlotterUIIncidentPackageState {
    switch state {
    case .unavailable(let reason): .unavailable(reason: bounded(reason))
    case .available: .available
    case .loading(let phase, let completed, let total):
      .loading(phase: bounded(phase), completedUnitCount: completed, totalUnitCount: total)
    case .completed(let metadata):
      .completed(PlotterUIIncidentPackageMetadata(
        formatVersion: metadata.formatVersion,
        encoding: bounded(metadata.encoding),
        exactByteCount: metadata.exactByteCount,
        payloadSHA256: bounded(metadata.payloadSHA256),
        integrityScope: bounded(metadata.integrityScope),
        physicalEvidenceClaimed: metadata.physicalEvidenceClaimed
      ))
    case .refused(let reason, let remedy):
      .refused(reason: bounded(reason), remedy: bounded(remedy))
    }
  }
}
