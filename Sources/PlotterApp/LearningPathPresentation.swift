import Foundation
import PlotterEpisodeModel
import PlotterEpisodeRuntime
import PlotterRuntime
import PlotterUI

/// Raw numeric text belongs to one window. It is parsed into a typed manual
/// intent while compiling that window's immutable projection and never becomes
/// mutable workspace/runtime state.
struct ManualMotionDraft: Hashable, Sendable {
  var xDistanceMM = "50"
  var yDistanceMM = "50"
  var feedMMPerMinute = "500"
}

/// Exact inputs to the root projection. Native layout/focus updates can
/// reevaluate a view without changing any of these model or window values.
struct PlotterAppUIProjectionInputs: Equatable {
  let semanticRevision: UInt64
  let cameraIsLive: Bool
  var actionSurfaceRevision: UInt64
  let runtimeRevisions: [PlotterUIRuntimeRevision]
  let drawingDraftReference: PlotterDrawingDraftProjectionReference
  let selectedItemID: LearningPathItemID
  let manualDraft: ManualMotionDraft
  let includesLearningPath: Bool
  let pendingDrawingProgramHash: String?
  let pendingDrawingPlacement: PlotterDrawingDraftCameraPlacement?
  let pendingPointSelection: PlotterPointSelectionSubmission?
  let observationViewport: ActionSurfaceViewportState?
}

struct PlotterAppUIProjection: Sendable {
  let semantic: PlotterUIProjection
  var actionSurface: ActionSurfacePresentation
  let learningMode: LearningModePresentation
  let learningPath: LearningPathProjection?
  let currentLearningPathItemID: LearningPathItemID
  let learningIsEnabled: Bool
  let manualMotion: ManualMotionPresentation
  let drawingStudio: DrawingStudioPresentation
  let drawingTargetIsVisible: Bool
  let drawingDraftProjection: PlotterDrawingDraftProjectionReference
  let workbenchCapability: WorkbenchCapabilityPresentation
  let incidentPackage: PlotterUIIncidentPackageState
  let controllerSession: PlotterControllerSessionProjection
  let observationConfiguration: PlotterObservationConfigurationProjection
  let paperManagementUnavailableReason: String?
  let motionRequestStatus: MotionRequestStatusPresentation
}

enum PlotterAppUIActionID {
  static let reidentifyPenCapRequest = PlotterLearningActionRequest(
    item: .init(rawValue: "\(LearningPathItemID.humanGuidedDiscovery(.penInteraction).number)-\(LearningPathItemID.humanGuidedDiscovery(.penInteraction).title)"),
    action: .reidentifyPenCap
  )
  static let reidentifyPenCap = PlotterUIActionID(learningRequest: reidentifyPenCapRequest)
  static let replacePenCapReferenceRequest = PlotterLearningActionRequest(
    item: reidentifyPenCapRequest.item, action: .replacePenCapReference)
  static let replacePenCapReference = PlotterUIActionID(learningRequest: replacePenCapReferenceRequest)
  static let learningMode = PlotterUIActionID(rawValue: "learning.mode")
  static let manualXNegative = PlotterUIActionID(rawValue: "manual.jog.x-negative")
  static let manualXPositive = PlotterUIActionID(rawValue: "manual.jog.x-positive")
  static let manualYNegative = PlotterUIActionID(rawValue: "manual.jog.y-negative")
  static let manualYPositive = PlotterUIActionID(rawValue: "manual.jog.y-positive")
  static let manualPenUp = PlotterUIActionID(rawValue: "manual.pen.up")
  static let manualPenDown = PlotterUIActionID(rawValue: "manual.pen.down")
  static let manualStop = PlotterUIActionID(rawValue: "manual.stop")
  static let manualRecovery = PlotterUIActionID(rawValue: "manual.publication.recover")
  static let manualEvidence = PlotterUIActionID(rawValue: "manual.evidence.resolve")
  static let incidentPackage = PlotterUIActionID(rawValue: "incident.package.request")
  static let controllerRefresh = PlotterUIActionID(rawValue: "application.controller.refresh")
  static let controllerConnection = PlotterUIActionID(rawValue: "application.controller.connection")
  static let controllerMotion = PlotterUIActionID(rawValue: "application.controller.motion")
  static let controllerClearAlarm = PlotterUIActionID(rawValue: "application.controller.clear-alarm")
  static let observationRefresh = PlotterUIActionID(rawValue: "application.observation.refresh")
  static let observationSimulated = PlotterUIActionID(rawValue: "application.observation.simulated")
  static let observationDiagnostics = PlotterUIActionID(rawValue: "application.observation.diagnostics")
  static let observationRegion = PlotterUIActionID(rawValue: "application.observation.region")
  static let paperNewSheet = PlotterUIActionID(rawValue: "application.paper.new-sheet")
  static let paperContactPlane = PlotterUIActionID(rawValue: "application.paper.contact-plane")

  static func controllerDevice(_ identifier: String) -> PlotterUIActionID {
    PlotterUIActionID(rawValue: "application.controller.device.\(identifier)")
  }

  static func observationCamera(_ identifier: String) -> PlotterUIActionID {
    PlotterUIActionID(rawValue: "application.observation.camera.\(identifier)")
  }

  static func observationCameraRole(_ role: WorkbenchCameraRole) -> PlotterUIActionID {
    PlotterUIActionID(rawValue: "application.observation.camera-role.\(role.rawValue)")
  }

  static func observationCadence(_ cadence: VisionAnalysisCadence) -> PlotterUIActionID {
    PlotterUIActionID(rawValue: "application.observation.cadence.\(cadence.displayValue)")
  }

  static func observationOverlay(_ value: String, enabled: Bool) -> PlotterUIActionID {
    PlotterUIActionID(
      rawValue: "application.observation.overlay.\(value).\(enabled ? "on" : "off")"
    )
  }

  static func pointSelection(_ submission: PlotterPointSelectionSubmission) -> PlotterUIActionID {
    PlotterUIActionID(rawValue: "learning.point-selection.\(submission.selectionID.rawValue)")
  }

  static func drawingDraft(_ intent: PlotterDrawingDraftIntent) -> PlotterUIActionID {
    if case .selectProgram(let program) = intent {
      return PlotterUIActionID(rawValue: "drawing.draft.program.\(program.contentHash)")
    }
    if case .placeAtCameraPoint = intent {
      // One pending placement is projected at a time. The exact typed frame
      // and point remain in the intent and are checked by request ingress.
      return PlotterUIActionID(rawValue: "drawing.draft.place-at-camera-point")
    }
    return PlotterUIActionID(rawValue: "drawing.draft.\(String(describing: intent))")
  }

  static func drawingRun(_ intent: PlotterDrawingRunIntent) -> PlotterUIActionID {
    PlotterUIActionID(rawValue: "drawing.run.\(String(describing: intent))")
  }

  static func retainedComparison(_ intent: PlotterUIRetainedComparisonIntent)
    -> PlotterUIActionID
  {
    PlotterUIActionID(rawValue: "drawing-border.review.\(intent.rawValue)")
  }

}

enum LearningPathStage: Int, CaseIterable, Hashable, Identifiable, Sendable {
  case humanGuidedDiscovery = 1
  case borderValidations = 2

  var id: Self { self }
  var number: String { String(rawValue) }

  var title: String {
    switch self {
    case .humanGuidedDiscovery: LearningPathTerminology.Stage.plotterCalibration
    case .borderValidations: LearningPathTerminology.Stage.drawingValidation
    }
  }
}

enum LearningPathStageStatus: String, CaseIterable, Hashable, Sendable {
  case complete = "Complete"
  case current = "Current"
  case next = "Next"
  case needsAttention = "Needs Attention"
}

enum HumanGuidedDiscoveryStep: Int, CaseIterable, Hashable, Identifiable, Sendable {
  case penInteraction = 1
  case pairedBoundaryDiscoveryAndCentering = 2
  case calibrateCameraAndVisibleCap = 3
  case calibratePenContactFromSparseMarks = 4

  static let allCases: [Self] = [
    .penInteraction,
    .pairedBoundaryDiscoveryAndCentering,
    .calibrateCameraAndVisibleCap,
    .calibratePenContactFromSparseMarks,
  ]

  var id: Self { self }
  var stepNumber: String { "1.\(rawValue)" }

  var title: String {
    switch self {
    case .penInteraction: LearningPathTerminology.Exercise.identifyAndCalibratePen
    case .pairedBoundaryDiscoveryAndCentering:
      LearningPathTerminology.Exercise.measureAndCenterDrawingBoundary
    case .calibrateCameraAndVisibleCap:
      LearningPathTerminology.Exercise.calibrateCameraFromPenCap
    case .calibratePenContactFromSparseMarks:
      LearningPathTerminology.Exercise.calibratePenTipFromCornerMarks
    }
  }
}

/// Stable identity for every selectable row in the visible Learning Path.
///
/// Stage rows and their numbered exercises are separate presentation targets.
/// The runtime current item is carried independently by
/// ``LearningPathSelectionState`` so browsing never changes runtime authority.
enum LearningPathItemID: Hashable, Identifiable, Sendable {
  case stage(LearningPathStage)
  case humanGuidedDiscovery(HumanGuidedDiscoveryStep)
  case borderValidation(BorderValidationStep)

  var id: Self { self }

  static let navigationOrder: [Self] = [
    .stage(.humanGuidedDiscovery),
    .humanGuidedDiscovery(.penInteraction),
    .humanGuidedDiscovery(.pairedBoundaryDiscoveryAndCentering),
    .humanGuidedDiscovery(.calibrateCameraAndVisibleCap),
    .humanGuidedDiscovery(.calibratePenContactFromSparseMarks),
    .stage(.borderValidations),
    .borderValidation(.chooseDrawingBorderPlan),
  ]

  static let learningExerciseOrder: [Self] = [
    .humanGuidedDiscovery(.penInteraction),
    .humanGuidedDiscovery(.pairedBoundaryDiscoveryAndCentering),
    .humanGuidedDiscovery(.calibrateCameraAndVisibleCap),
    .humanGuidedDiscovery(.calibratePenContactFromSparseMarks),
    .borderValidation(.chooseDrawingBorderPlan),
  ]

  var stage: LearningPathStage {
    switch self {
    case .stage(let stage): stage
    case .humanGuidedDiscovery: .humanGuidedDiscovery
    case .borderValidation: .borderValidations
    }
  }

  var number: String {
    switch self {
    case .stage(let stage): stage.number
    case .humanGuidedDiscovery(let step): step.stepNumber
    case .borderValidation(let step): step.stepNumber
    }
  }

  var title: String {
    switch self {
    case .stage(let stage): stage.title
    case .humanGuidedDiscovery(let step): step.title
    case .borderValidation(.chooseDrawingBorderPlan):
      LearningPathTerminology.Exercise.drawAndValidateDrawingBorder
    case .borderValidation(let step): step.title
    }
  }

  var isExercise: Bool {
    switch self {
    case .humanGuidedDiscovery, .borderValidation: true
    case .stage: false
    }
  }

  var learningRewindAnchor: Self? {
    switch self {
    case .stage(.humanGuidedDiscovery):
      .humanGuidedDiscovery(.penInteraction)
    case .stage(.borderValidations):
      .borderValidation(.chooseDrawingBorderPlan)
    case .humanGuidedDiscovery, .borderValidation:
      self
    }
  }

  var navigationDepth: Int {
    switch self {
    case .humanGuidedDiscovery, .borderValidation: 1
    case .stage: 0
    }
  }
}

enum LearningVacateSource: String, Hashable, Sendable {
  case live = "LIVE"
  case simulated = "SIMULATED"
}

enum LearningVacateScope: Hashable, Sendable {
  case from(LearningPathItemID)
  case all
}

/// Immutable preview and stale-state guard for an explicit learning reset.
/// The UI presents this plan before passing it back for mutation.
struct LearningVacatePlan: Hashable, Identifiable, Sendable {
  let scope: LearningVacateScope
  let source: LearningVacateSource
  let anchor: LearningPathItemID
  let affectedItems: [LearningPathItemID]
  let expectedCurrentRevisionIDs: Set<LearningArtifactRevisionID>
  let expectedAcceptedAttemptSequence: UInt64
  let removesDurableMachineCheckpoint: Bool
  let removesDurableTipCheckpoint: Bool
  let physicalInkMayRemain: Bool

  var removesDurableCheckpoint: Bool {
    removesDurableMachineCheckpoint || removesDurableTipCheckpoint
  }

  var id: String {
    let scopeID =
      switch scope {
      case .from: "from-\(anchor.number)"
      case .all: "all"
      }
    return "\(source.rawValue)-\(scopeID)"
  }

  var title: String {
    switch scope {
    case .from: "Reset From This Step"
    case .all: "Reset All Learning"
    }
  }

  var modelRequest: PlotterLearningResetRequest {
    let identity: (LearningPathItemID) -> PlotterLearningItemIdentity = {
      PlotterLearningItemIdentity(rawValue: "\($0.number)-\($0.title)")
    }
    let modelScope: PlotterLearningResetScope
    switch scope {
    case .from(let item): modelScope = .from(identity(item))
    case .all: modelScope = .all
    }
    return PlotterLearningResetRequest(
      scope: modelScope,
      source: source == .live ? .live : .simulated,
      anchor: identity(anchor),
      affectedItems: affectedItems.map(identity),
      expectedCurrentRevisionIDs: Set(expectedCurrentRevisionIDs.map(\.rawValue.uuidString)),
      expectedAcceptedAttemptSequence: expectedAcceptedAttemptSequence,
      removesDurableMachineCheckpoint: removesDurableMachineCheckpoint,
      removesDurableTipCheckpoint: removesDurableTipCheckpoint,
      physicalInkMayRemain: physicalInkMayRemain
    )
  }
}

struct LearningPathItemPresentation: Identifiable, Hashable, Sendable {
  let id: LearningPathItemID
  let status: LearningPathStageStatus
}

/// Window-local selection. None of these operations has a callback or runtime
/// reference, which makes selection structurally incapable of starting work.
struct LearningPathSelectionState: Equatable, Sendable {
  private(set) var current: LearningPathItemID
  private(set) var selected: LearningPathItemID

  init(current: LearningPathItemID) {
    self.current = current
    selected = current
  }

  var isReviewingAnotherItem: Bool { selected != current }

  mutating func select(_ item: LearningPathItemID) {
    selected = item
  }

  mutating func returnToCurrent() {
    selected = current
  }

  /// Follows runtime progression only when the operator was still looking at
  /// the previous current row. An intentional review selection is preserved.
  mutating func updateCurrent(_ item: LearningPathItemID) {
    let followedCurrent = selected == current
    current = item
    if followedCurrent {
      selected = item
    }
  }
}

enum PresentationCue: Hashable, Sendable {
  case up
  case down
  case yes
  case no
  case stop
  case direction(BoundaryDirection)

  var visibleText: String {
    switch self {
    case .up: "UP"
    case .down: "DOWN"
    case .yes: "YES"
    case .no: "NO"
    case .stop: "STOP"
    case .direction(let direction): direction.displayName
    }
  }

  var accessibilityValue: String {
    switch self {
    case .up: "Pen up"
    case .down: "Pen down"
    case .yes: "Yes"
    case .no: "No"
    case .stop: "Stop"
    case .direction(.negativeX): "Move in the negative X direction"
    case .direction(.positiveX): "Move in the positive X direction"
    case .direction(.negativeY): "Move in the negative Y direction"
    case .direction(.positiveY): "Move in the positive Y direction"
    }
  }
}

enum PresentationFragment: Hashable, Sendable {
  case text(String)
  case cue(PresentationCue)

  var visibleText: String {
    switch self {
    case .text(let text): text
    case .cue(let cue): cue.visibleText
    }
  }

  var accessibilityValue: String {
    switch self {
    case .text(let text): text
    case .cue(let cue): cue.accessibilityValue
    }
  }
}

extension Collection where Element == PresentationFragment {
  var accessibilityText: String {
    map(\.accessibilityValue).joined(separator: " ")
  }
}

struct ManualMotionStopActionPresentation: Hashable, Sendable {
  let capabilityID: PlotterManualMotionStopCapabilityID
  let title: String
  let detail: String
}

struct ManualMotionPublicationRecoveryPresentation: Hashable, Sendable {
  let capabilityID: PlotterManualMotionPublicationRecoveryCapabilityID
  let title: String
  let remedy: String
}

struct ManualMotionEvidenceDispositionPresentation: Hashable, Sendable {
  let action: PlotterManualMotionEvidenceDispositionAction
  let title: String
  let remedy: String
}

struct ManualMotionPresentation: Hashable, Sendable {
  static let xDistanceLabel = "X distance (mm)"
  static let yDistanceLabel = "Y distance (mm)"
  static let feedLabel = "Feed (mm/min)"

  let stopAction: ManualMotionStopActionPresentation?
  let publicationRecovery: ManualMotionPublicationRecoveryPresentation?
  let evidenceDisposition: ManualMotionEvidenceDispositionPresentation?
  let jogUnavailableReason: String?
  let penUpUnavailableReason: String?
  let penDownUnavailableReason: String?
  let penStateText: String
  let modeText: String
  let recordingDiagnostic: String?

  var isStoppable: Bool { stopAction != nil }
  var publicationPendingReason: String? { publicationRecovery?.remedy }
  var evidencePendingReason: String? { evidenceDisposition?.remedy }
  var attentionReason: String? { publicationPendingReason ?? evidencePendingReason }

  func controllerAlertText(_ reportedAttention: String?) -> String? {
    guard let reportedAttention else { return "none reported" }
    guard reportedAttention != publicationPendingReason,
      reportedAttention != evidencePendingReason
    else { return nil }
    return reportedAttention
  }

  var jogControlsUnavailableReason: String? {
    if stopAction != nil {
      return jogUnavailableReason ?? "Stop the active manual jog before starting another."
    }
    return jogUnavailableReason
  }
}

enum MotionRequestStatusPresentation: Hashable, Sendable {
  case ready
  case busy(String)
  case unavailable(String)
  case needsAttention(String)

  var label: String {
    switch self {
    case .ready: "Ready"
    case .busy: "Busy"
    case .unavailable: "Unavailable"
    case .needsAttention: "Needs Attention"
    }
  }

  var detail: String? {
    switch self {
    case .ready: nil
    case .busy(let detail), .unavailable(let detail), .needsAttention(let detail): detail
    }
  }
}

extension PlotterUILearningActionDecision {
  var kind: PlotterLearningAction { action }
  var isEnabled: Bool { unavailableReason == nil }
  var buttonRole: OperatorButtonRole {
    if kind.isImmediateStop { return .stop }
    if case .choice(let choice) = kind {
      return choice == .yes ? .affirmative : .negative
    }
    switch role {
    case .positive: return .affirmative
    case .destructive: return .negative
    case .standard: return .neutral
    }
  }
}

struct ExerciseQuestionPresentation: Hashable, Sendable {
  let prompt: [PresentationFragment]
  let choices: [OperatorChoice]

  init(prompt: [PresentationFragment], choices: [OperatorChoice]) {
    precondition(!prompt.isEmpty)
    self.prompt = prompt
    self.choices = choices
  }
}

struct OperatorActionPresentation: Hashable, Sendable {
  let itemID: LearningPathItemID
  let instructions: [PresentationFragment]
  let question: ExerciseQuestionPresentation?
  let actionStrip: PlotterUILearningActionStripDecision?

  init(
    itemID: LearningPathItemID,
    instructions: [PresentationFragment],
    question: ExerciseQuestionPresentation? = nil,
    actionStrip: PlotterUILearningActionStripDecision? = nil
  ) {
    self.itemID = itemID
    self.instructions = instructions
    self.question = question
    self.actionStrip = actionStrip
  }
}
