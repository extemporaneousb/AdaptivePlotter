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

public struct PlotterUIActionID: RawRepresentable, Hashable, Sendable {
  public let rawValue: String

  public init(rawValue: String) { self.rawValue = rawValue }

  public init(learningRequest: PlotterLearningActionRequest) {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    rawValue = "learning.action.\((try! encoder.encode(learningRequest)).base64EncodedString())"
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

public enum PlotterUIPaperRequest: Hashable, Sendable {
  case newSheetOnCurrentPlane
  case contactPlaneChanged
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
  case boundary(PlotterBoundaryIntent)
  case learningAction(PlotterLearningActionRequest)
  case learningReset(PlotterLearningResetRequest)
  case retainedComparisonReview(PlotterUIRetainedComparisonIntent)
  case controller(PlotterControllerSessionRequest)
  case observation(PlotterObservationOperatorSubmission)
  case paper(PlotterUIPaperRequest)
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

public enum PlotterUILearningCameraState: Hashable, Sendable {
  case readyWithoutProposal
  case readyWithProposal
  case active
}

public enum PlotterUILearningSparseState: Hashable, Sendable {
  case idle
  case drawingBatch
  case revealingBatch
  case capturingClickFrame
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
  case reviewingComparison
}

public enum PlotterUILearningActivePrompt: Hashable, Sendable {
  case choices([PlotterLearningChoice])
  case penConfirmation(
    command: PlotterLearningPenCommand,
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
  public let boundary: PlotterBoundaryProjection?
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
    boundary: PlotterBoundaryProjection? = nil,
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
    self.boundary = boundary
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

public enum PlotterUILearningActionRole: Hashable, Sendable {
  case positive
  case destructive
  case standard
}

public struct PlotterUILearningActionDecision: Hashable, Sendable {
  public let request: PlotterLearningActionRequest
  public let title: String
  public let role: PlotterUILearningActionRole
  public let unavailableReason: String?
  public var action: PlotterLearningAction { request.action }

  public init(
    itemID: String,
    action: PlotterLearningAction,
    title: String? = nil,
    role: PlotterUILearningActionRole? = nil,
    unavailableReason: String? = nil
  ) {
    request = PlotterLearningActionRequest(
      item: PlotterLearningItemIdentity(rawValue: itemID), action: action
    )
    self.title = title ?? action.defaultTitle
    self.role = role ?? action.defaultRole
    self.unavailableReason = unavailableReason
  }

  public init(
    request: PlotterLearningActionRequest,
    title: String,
    role: PlotterUILearningActionRole,
    unavailableReason: String? = nil
  ) {
    self.request = request; self.title = title; self.role = role
    self.unavailableReason = unavailableReason
  }

  public func candidate() -> PlotterUIActionCandidate {
    let id = PlotterUIActionID(learningRequest: request)
    return PlotterUIActionCandidate(
      id: id,
      title: title,
      intent: .learningAction(request),
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
  static func learningReset(
    request: PlotterLearningResetRequest,
    title: String,
    unavailableReason: String?
  ) -> PlotterUIActionCandidate {
    let id = PlotterUIActionID(rawValue: request.identity)
    return PlotterUIActionCandidate(
      id: id,
      title: title,
      intent: .learningReset(request),
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

private extension PlotterLearningAction {
  var defaultTitle: String {
    switch self {
    case .applySavedLearning: "Use Saved Learning"
    case .startNewLearning: "Start New Learning"
    case .start: "Start"
    case .choice(.yes): "YES"
    case .choice(.no): "NO"
    case .setPenSetpoint(let command, let value):
      "Set Pen \(command == .raise ? "Up" : "Down") S\(value)"
    case .stopPenInteraction: "Stop Pen Interaction"
    case .boundary(let intent):
      switch intent {
      case .selectDirection(let direction): "Select \(direction.displayName)"
      case .acquire(let direction, let mode):
        switch mode {
        case .normal: "Move Toward \(direction.displayName)"
        case .replacement: "Redo \(direction.displayName) Boundary"
        case .additional: "Record Another \(direction.displayName) Attempt"
        }
      case .moveToEstimatedCenter(let retry): retry ? "Retry Center Arrival" : "Move to Estimated Center"
      case .stop: "Stop Boundary Search"
      case .cancel: "Cancel Boundary Attempt"
      case .recoverPublication: "Retry Boundary Save"
      case .reserveReset: "Reserve Boundary Reset"
      case .commitReset: "Commit Boundary Reset"
      case .abortReset: "Abort Boundary Reset"
      }
    case .cancel: "Cancel Attempt"
    case .stop: "Stop"
    case .restart: "Restart Attempt"
    case .redoThisStep: "Redo This Step"
    case .recordAnotherAttempt: "Record Another Attempt"
    case .reidentifyPenCap: "Reidentify Pen Cap"
    case .replacePenCapReference: "Replace Pen Cap Reference"
    case .cameraCalibration(.buildFivePositionProposal):
      "Run Five-Position Camera Calibration"
    case .cameraCalibration(.acceptProposal): "Accept Camera Calibration"
    case .cameraCalibration(.rejectProposal): "Reject Camera Calibration"
    case .tipCalibration(.beginFourMarkBatch): "Draw Four Calibration Circles"
    case .tipCalibration(.captureNewClickFrame): "Capture New Click Frame"
    case .pointSelectionCorrection(.undoLastPoint): "Undo Last Click"
    case .pointSelectionCorrection(.clearPoints): "Clear Clicks on This Frame"
    case .tipCalibration(.revalidateCheckpoint): "Re-establish Position from Camera"
    case .tipCalibration(.acceptProposal): "Accept Pen-Tip Calibration"
    case .tipCalibration(.rejectProposal): "Reject Pen-Tip Calibration"
    case .tipCalibration(.retryCommit): "Retry Pen-Tip Calibration Save"
    case .paperReplaced: "Record Paper Replacement"
    case .borderValidation(.acceptObservedPrediction): "Accept Observed Drawing Border"
    case .borderValidation(.reject): "Reject Observed Drawing Border"
    }
  }

  var defaultRole: PlotterUILearningActionRole {
    switch self {
    case .applySavedLearning, .start, .restart,
      .cameraCalibration(.buildFivePositionProposal), .cameraCalibration(.acceptProposal),
      .tipCalibration(.beginFourMarkBatch), .tipCalibration(.captureNewClickFrame),
      .tipCalibration(.revalidateCheckpoint), .tipCalibration(.acceptProposal),
      .tipCalibration(.retryCommit), .paperReplaced,
      .borderValidation(.acceptObservedPrediction):
      .positive
    case .cancel, .stop, .stopPenInteraction, .cameraCalibration(.rejectProposal),
      .tipCalibration(.rejectProposal), .borderValidation(.reject):
      .destructive
    case .choice(.yes): .positive
    case .startNewLearning, .choice(.no), .setPenSetpoint, .boundary,
      .redoThisStep, .recordAnotherAttempt, .reidentifyPenCap, .replacePenCapReference,
      .pointSelectionCorrection:
      .standard
    }
  }
}

public struct PlotterUILearningPenAdjustmentDecision: Hashable, Sendable {
  public struct Candidate: Hashable, Sendable {
    public let value: Int
    public let decision: PlotterUILearningActionDecision
  }
  public let command: PlotterLearningPenCommand
  public let value: Int
  public let candidates: [Candidate]

  public init(
    command: PlotterLearningPenCommand,
    value: Int,
    candidates: [Candidate] = []
  ) {
    self.command = command; self.value = value
    self.candidates = candidates
  }
}

public struct PlotterUILearningDirectionDecision: Hashable, Sendable {
  public struct Candidate: Hashable, Sendable {
    public let direction: PlotterUILearningBoundaryDirection
    public let decision: PlotterUILearningActionDecision
  }
  public let selected: PlotterUILearningBoundaryDirection
  public let candidates: [Candidate]
  public var options: [PlotterUILearningBoundaryDirection] { candidates.map(\.direction) }

  public init(
    selected: PlotterUILearningBoundaryDirection,
    candidates: [Candidate] = []
  ) {
    self.selected = selected; self.candidates = candidates
  }
}

public struct PlotterUILearningActionStripDecision: Hashable, Sendable {
  public let ownerID: String
  public let actions: [PlotterUILearningActionDecision]
  public let directionSelection: PlotterUILearningDirectionDecision?
  public let penAdjustment: PlotterUILearningPenAdjustmentDecision?
  public let mustRemainVisible: Bool

  public init(
    ownerID: String,
    actions: [PlotterUILearningActionDecision],
    directionSelection: PlotterUILearningDirectionDecision?,
    penAdjustment: PlotterUILearningPenAdjustmentDecision?,
    mustRemainVisible: Bool
  ) {
    self.ownerID = ownerID; self.actions = actions
    self.directionSelection = directionSelection; self.penAdjustment = penAdjustment
    self.mustRemainVisible = mustRemainVisible
  }

  /// Every semantic request rendered by this strip, including slider and
  /// direction-selector values that are not represented as buttons.
  public func requestDecisions() -> [PlotterUILearningActionDecision] {
    actions
      + (penAdjustment?.candidates.map(\.decision) ?? [])
      + (directionSelection?.candidates.map(\.decision) ?? [])
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
          directionSelection: strip.directionSelection,
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
    if item.kind == .boundary, let boundary = facts.boundary {
      if boundary.publicationRecoveryCapabilityID != nil { return .needsAttention }
      if case .needsAttention = boundary.phase { return .needsAttention }
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
          itemID: item.ownerID,
          action: .start,
          title: "Pen Interaction Stop unavailable",
          unavailableReason:
            "PlotterPenInteractionRuntime owns an active operation without its exact cancellation capability. Restart the application; no generic Stop was substituted."
        )], mustRemainVisible: true)
      }
      switch activePenInteraction.phase {
      case .settling, .cancelling, .awaitingCapSelection, .awaitingControllerCommand,
        .confirming:
        return strip(
          item.ownerID,
          [.init(itemID: item.ownerID, action: .stopPenInteraction(capability), title: "Stop Pen Interaction")],
          mustRemainVisible: true
        )
      case .drainingSetpoint:
        penSetpointDrainIsInProgress = true
      case .awaitingConfirmation, .refused, .possiblePhysicalChange:
        break
      case .idle, .succeeded:
        return strip(item.ownerID, [.init(
          itemID: item.ownerID,
          action: .start,
          title: "Pen Interaction state unavailable",
          unavailableReason: invariantReason
        )], mustRemainVisible: true)
      }
    }
    if item.kind == .boundary, let boundary = facts.boundary,
      boundary.resetCapabilityID != nil
    {
      return strip(item.ownerID, [.init(
        itemID: item.ownerID,
        action: .start,
        title: "Boundary reset in progress",
        unavailableReason: "The exact Boundary reset transaction is waiting for durable Learning-prefix settlement. No Boundary effect is available."
      )], mustRemainVisible: true)
    }
    if item.kind == .boundary, let boundary = facts.boundary,
      let recoveryCapability = boundary.publicationRecoveryCapabilityID
    {
      return strip(item.ownerID, [
        .init(
          itemID: item.ownerID,
          action: .boundary(.recoverPublication(recoveryCapability)),
          title: "Retry Boundary Publication"
        )
      ], mustRemainVisible: true)
    }
    if item.kind == .boundary, let boundary = facts.boundary,
      case .publicationIncomplete = boundary.phase
    {
      return strip(item.ownerID, [.init(
        itemID: item.ownerID,
        action: .start,
        title: "Boundary publication recovery unavailable",
        unavailableReason: "PlotterBoundaryRuntime retained unpublished authority without its exact recovery capability. Restart the application; no motion will be resent."
      )], mustRemainVisible: true)
    }
    if item.kind == .boundary, let boundary = facts.boundary,
      boundary.reference.operationID != nil
    {
      guard let capability = boundary.cancellationCapabilityID else {
        return strip(item.ownerID, [.init(
          itemID: item.ownerID,
          action: .start,
          title: "Boundary owner needs attention",
          unavailableReason: "PlotterBoundaryRuntime owns an operation without its exact cancellation capability."
        )], mustRemainVisible: true)
      }
      return strip(item.ownerID, [
        .init(itemID: item.ownerID, action: .boundary(.stop(capability)), title: "Stop Boundary Search")
      ], mustRemainVisible: true)
    }
    if item.kind == .boundary, let boundary = facts.boundary,
      case .needsAttention(let detail) = boundary.phase
    {
      let settledRetry: Bool = switch boundary.terminal?.disposition {
      case .cancelled, .refused: true
      case .ambiguous:
        boundary.terminal?.activity == .centerArrival
          && boundary.centerArrivalRetryRequired
          && facts.boundaryCenterArrivalRetryIsRequired
      default: false
      }
      if !settledRetry {
        return strip(item.ownerID, [.init(
          itemID: item.ownerID,
          action: .start,
          title: "Boundary needs attention",
          unavailableReason: "\(detail) Resolve the exact Boundary terminal truth; no acquisition or center motion will be resent automatically."
        )], mustRemainVisible: true)
      }
      // The owner may also retain a center-only retry after a settled position
      // miss. Current admission still blocks unknown pose or sticky ambiguity;
      // a side ambiguity or terminal shutdown never gains this exception.
    }
    if item.kind == .boundary, let boundary = facts.boundary,
      item.ownerID == current,
      facts.boundaryIsComplete,
      !facts.boundaryHasCenterArrival,
      facts.boundaryCenterArrivalRetryIsRequired,
      boundary.reference.operationID == nil,
      boundary.cancellationCapabilityID == nil
    {
      return strip(item.ownerID, [
        .init(
          itemID: item.ownerID,
          action: .boundary(.moveToEstimatedCenter(retry: true)),
          title: "Retry Center Arrival",
          unavailableReason: facts.startUnavailableReasons[item.ownerID]
        )
      ])
    }
    if facts.savedTrainingCandidateIsPresent {
      guard item.ownerID == current else { return nil }
      return strip(item.ownerID, [
        .init(itemID: item.ownerID, action: .applySavedLearning),
        .init(itemID: item.ownerID, action: .startNewLearning),
      ], mustRemainVisible: true)
    }
    if item.kind == .drawingValidation,
      facts.activeOwnerID == item.ownerID,
      facts.drawingState == .reviewingComparison
    {
      return strip(
        item.ownerID,
        [
          .init(itemID: item.ownerID, action: .borderValidation(.acceptObservedPrediction)),
          .init(itemID: item.ownerID, action: .borderValidation(.reject(
            "Operator rejected the observed Drawing Border comparison."
          ))),
        ],
        mustRemainVisible: true
      )
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
          [.init(
            itemID: item.ownerID,
            action: .stop(ContextualStopCapabilityID(rawValue: stop.capabilityID)),
            title: title
          )],
          mustRemainVisible: true
        )
      }
      if item.kind == .drawingValidation {
        return strip(
          item.ownerID,
          [.init(
            itemID: item.ownerID,
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
          itemID: item.ownerID,
          action: .start,
          title: "Pen Interaction needs attention",
          unavailableReason: penInteractionAttentionReason(penInteraction)
        )]
      } else if item.stageID == "discovery", let ambiguity = facts.stickyAmbiguityReason {
        actions = [.init(
          itemID: item.ownerID,
          action: .start,
          title: "Machine action unavailable",
          unavailableReason: ambiguity
        )]
      } else if item.kind == .cameraCalibration {
        switch facts.cameraState {
        case .active:
          actions = [.init(
            itemID: item.ownerID,
            action: .cameraCalibration(.buildFivePositionProposal),
            title: "Camera calibration is working…",
            unavailableReason: "Camera calibration is in progress."
          )]
        case .readyWithoutProposal:
          actions = [.init(itemID: item.ownerID, action: .cameraCalibration(.buildFivePositionProposal))]
        case .readyWithProposal:
          actions = [
            .init(itemID: item.ownerID, action: .cameraCalibration(.acceptProposal)),
            .init(itemID: item.ownerID, action: .cameraCalibration(.rejectProposal)),
          ]
        }
      } else if item.kind == .sparseTipCalibration {
        actions = sparseActions(facts, itemID: item.ownerID)
      } else if let prompt = facts.activePrompt {
        switch prompt {
        case .choices(let choices):
          actions = Array(choices.prefix(limits.maximumChoiceVisitCount)).map {
            .init(itemID: item.ownerID, action: .choice($0))
          }
        case .penConfirmation(let command, let value, let minimum, let maximum):
          let reason = facts.startUnavailableReasons[item.ownerID]
          actions = [.init(
              itemID: item.ownerID,
              action: .choice(.yes),
              title: command == .raise ? "Confirm Pen Up" : "Confirm Pen Down",
              unavailableReason: penSetpointDrainIsInProgress
                ? "Applying the selected servo setting…" : reason
            )]
          adjustment = PlotterUILearningPenAdjustmentDecision(
            command: command,
            value: value,
            candidates: (minimum...maximum).map { candidate in .init(
              value: candidate,
              decision: .init(
                itemID: item.ownerID,
                action: .setPenSetpoint(command, candidate),
                unavailableReason: reason
              )
            ) }
          )
        }
      }
      if let capability = activePenInteraction?.cancellationCapabilityID {
        actions.append(.init(
          itemID: item.ownerID,
          action: .stopPenInteraction(capability),
          title: "Stop Pen Interaction"
        ))
      } else if !facts.stopDispositionIsLatched, facts.cameraState != .active {
        actions.append(.init(itemID: item.ownerID, action: .cancel))
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
        itemID: item.ownerID,
        action: .restart,
        title: item.kind == .drawingValidation
          ? "Retry Drawing Border Validation" : "Restart Attempt"
      )])
    }
    if item.kind == .sparseTipCalibration, !item.isComplete, facts.sparseSavedCheckpointMatchesPaper {
      return strip(item.ownerID, [.init(
        itemID: item.ownerID,
        action: .tipCalibration(.revalidateCheckpoint),
        unavailableReason: facts.startUnavailableReasons[item.ownerID]
      )])
    }
    if item.isComplete {
      guard item.ownerID == facts.selectedOwnerID else { return nil }
      if item.kind == .drawingValidation { return nil }
      if item.kind == .boundary {
        return strip(item.ownerID, boundaryRepeatActions(facts.acceptedBoundaryDirections, itemID: item.ownerID))
      }
      var actions = [PlotterUILearningActionDecision(itemID: item.ownerID, action: .redoThisStep)]
      if item.isRepeatable { actions.append(.init(itemID: item.ownerID, action: .recordAnotherAttempt)) }
      return strip(item.ownerID, actions)
    }
    guard item.ownerID == current else { return nil }
    let reason = facts.startUnavailableReasons[item.ownerID]
    if item.kind == .boundary, facts.boundaryIsComplete, !facts.boundaryHasCenterArrival {
      let centerReason = facts.boundaryHasEstimatedCenter
        ? reason : "Accepted boundaries do not currently derive a valid center."
      return strip(
        item.ownerID,
        [.init(
          itemID: item.ownerID,
          action: .boundary(.moveToEstimatedCenter(retry: false)),
          unavailableReason: centerReason
        )] + boundaryRepeatActions(facts.acceptedBoundaryDirections, itemID: item.ownerID)
      )
    }
    if item.kind == .drawingValidation {
      let title: String = switch facts.drawingState {
      case .choosePlan: "Draw and Validate Drawing Border"
      case .revealAndObserve: "Resume Drawing Border Observation"
      case .compare: "Complete Drawing Border Comparison"
      case .reviewingComparison: "Review Drawing Border Comparison"
      case .captureBaseline, .moveToStart, .draw: "Resume Drawing Border Validation"
      }
      return strip(item.ownerID, [.init(
        itemID: item.ownerID,
        action: .start,
        title: title,
        unavailableReason: reason
      )])
    }
    if item.kind == .cameraCalibration {
      return strip(item.ownerID, [.init(
        itemID: item.ownerID,
        action: .cameraCalibration(.buildFivePositionProposal),
        unavailableReason: reason
      )])
    }
    if item.kind == .sparseTipCalibration {
      if facts.sparseState == .possibleInkBlacklisted {
        return strip(item.ownerID, [.init(itemID: item.ownerID, action: .paperReplaced)])
      }
      return strip(item.ownerID, [
        .init(
          itemID: item.ownerID,
          action: .tipCalibration(.beginFourMarkBatch),
          title: sparseBatchTitle(facts.sparseState),
          unavailableReason: reason
        )
      ])
    }
    let direction = item.kind == .boundary
      ? PlotterUILearningDirectionDecision(
        selected: facts.selectedBoundaryDirection,
        candidates: Array(facts.allowedBoundaryDirections.prefix(limits.maximumDirectionVisitCount)).map {
          .init(
            direction: $0,
            decision: .init(
              itemID: item.ownerID,
              action: .boundary(.selectDirection(PlotterBoundaryDirection($0)))
            )
          )
        }
      ) : nil
    return PlotterUILearningActionStripDecision(
      ownerID: item.ownerID,
      actions: [.init(
        itemID: item.ownerID,
        action: item.kind == .boundary
          ? .boundary(.acquire(
            direction: PlotterBoundaryDirection(facts.selectedBoundaryDirection),
            mode: .normal
          )) : .start,
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
    _ facts: PlotterUILearningActionabilityFacts,
    itemID: String
  ) -> [PlotterUILearningActionDecision] {
    switch facts.sparseState {
    case .idle, .drawingBatch, .revealingBatch:
      let reason: String? = switch facts.sparseState {
      case .drawingBatch: "The four-circle calibration is in progress."
      case .revealingBatch: "The final Pen-Up calibration reveal is in progress."
      default: nil
      }
      return [.init(
        itemID: itemID,
        action: .tipCalibration(.beginFourMarkBatch),
        title: sparseBatchTitle(facts.sparseState),
        unavailableReason: reason
      )]
    case .capturingClickFrame:
      return [.init(
        itemID: itemID,
        action: .tipCalibration(.captureNewClickFrame(retainedPointCount: 0)),
        title: "Capturing New Click Frame…",
        unavailableReason: "The strictly newer exact click frame is being captured and staged."
      )]
    case .awaitingFrozenClicks:
      let replacement = PlotterUILearningActionDecision(
        itemID: itemID,
        action: .tipCalibration(.captureNewClickFrame(
          retainedPointCount: facts.sparseCollectedClickCount
        )),
        unavailableReason: facts.sparseCollectedClickCount == 0
          ? nil
          : "Clear every retained click before capturing a new click frame."
      )
      return facts.sparseCollectedClickCount == 0 ? [replacement] : [
        replacement,
        .init(itemID: itemID, action: .pointSelectionCorrection(.undoLastPoint)),
        .init(itemID: itemID, action: .pointSelectionCorrection(.clearPoints)),
      ]
    case .fittingModel:
      return [.init(
        itemID: itemID,
        action: .tipCalibration(.acceptProposal),
        title: "Fitting Tip Calibration…",
        unavailableReason: "The four observations are being created and fitted."
      )]
    case .reviewingModel:
      return [
        .init(itemID: itemID, action: .tipCalibration(.acceptProposal)),
        .init(itemID: itemID, action: .pointSelectionCorrection(.undoLastPoint)),
        .init(itemID: itemID, action: .pointSelectionCorrection(.clearPoints)),
        .init(itemID: itemID, action: .tipCalibration(.rejectProposal)),
      ]
    case .committingModel:
      return [.init(
        itemID: itemID,
        action: .tipCalibration(.acceptProposal),
        title: "Saving or Revalidating Tip Calibration…",
        unavailableReason: "The calibration commit or revalidation is still in progress."
      )]
    case .possibleInkBlacklisted:
      return [.init(itemID: itemID, action: .paperReplaced)]
    case .accepted:
      return []
    }
  }

  private func sparseBatchTitle(_ state: PlotterUILearningSparseState) -> String {
    switch state {
    case .drawingBatch: "Drawing Four Calibration Circles…"
    case .revealingBatch: "Capturing Calibration Reveal…"
    default: "Draw Four Calibration Circles"
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
    _ directions: [PlotterUILearningBoundaryDirection],
    itemID: String
  ) -> [PlotterUILearningActionDecision] {
    Array(directions.prefix(limits.maximumDirectionVisitCount)).flatMap { direction in
      [
        .init(itemID: itemID, action: .boundary(.acquire(
          direction: PlotterBoundaryDirection(direction),
          mode: .replacement
        ))),
        .init(itemID: itemID, action: .boundary(.acquire(
          direction: PlotterBoundaryDirection(direction),
          mode: .additional
        ))),
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

private extension PlotterBoundaryDirection {
  init(_ direction: PlotterUILearningBoundaryDirection) {
    switch direction {
    case .negativeX: self = .negativeX
    case .positiveX: self = .positiveX
    case .negativeY: self = .negativeY
    case .positiveY: self = .positiveY
    }
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

extension PlotterUIIntentSink {
  /// Submits only an action compiled into the supplied immutable projection.
  /// A missing or unavailable action never reaches the application sink.
  @discardableResult
  public func submitProjectedAction(
    _ actionID: PlotterUIActionID,
    in projection: PlotterUIProjection
  ) async -> PlotterUIRequestDisposition? {
    guard let request = projection.request(for: actionID) else { return nil }
    return await submitPlotterUIRequest(request)
  }
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
