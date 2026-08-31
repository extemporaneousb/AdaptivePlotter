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

struct PlotterAppUIProjection: Sendable {
  let semantic: PlotterUIProjection
  let actionSurface: ActionSurfacePresentation
  let exercisePaneProtection: ExercisePaneProtectionPresentation
  let learningMode: LearningModePresentation
  let learningPath: LearningPathProjection?
  let currentLearningPathItemID: LearningPathItemID
  let learningIsEnabled: Bool
  let manualMotion: ManualMotionPresentation
  let drawingStudio: DrawingStudioPresentation
  let drawingStudioIsPresented: Bool
  let drawingStudioPanelChangeUnavailableReason: String?
  let drawingDraftProjection: PlotterDrawingDraftProjectionReference
  let workbenchCapability: WorkbenchCapabilityPresentation
  let incidentPackage: PlotterUIIncidentPackageState
}

enum PlotterAppUIActionID {
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
  static let drawingOpen = PlotterUIActionID(rawValue: "drawing.draft.open")
  static let drawingClose = PlotterUIActionID(rawValue: "drawing.draft.close")
  static let incidentPackage = PlotterUIActionID(rawValue: "incident.package.request")

  static func pointSelection(_ submission: PlotterPointSelectionSubmission) -> PlotterUIActionID {
    PlotterUIActionID(rawValue: "learning.point-selection.\(submission.selectionID.rawValue)")
  }

  static func drawingDraft(_ intent: PlotterDrawingDraftIntent) -> PlotterUIActionID {
    PlotterUIActionID(rawValue: "drawing.draft.\(String(describing: intent))")
  }

  static func drawingRun(_ intent: PlotterDrawingRunIntent) -> PlotterUIActionID {
    PlotterUIActionID(rawValue: "drawing.run.\(String(describing: intent))")
  }

  static func retainedComparison(_ intent: PlotterUIRetainedComparisonIntent)
    -> PlotterUIActionID
  {
    PlotterUIActionID(rawValue: "drawing-border.review.\(intent.rawValue)")
  }

  static func retainedLearning(_ kind: ExerciseActionKind, owner: LearningPathItemID)
    -> PlotterUIActionID
  {
    PlotterUIActionID(rawValue: "learning.retained.\(owner.id).\(String(describing: kind))")
  }

  static func penInteractionSetpoint(
    _ command: PenCommand,
    value: Int,
    owner: LearningPathItemID
  ) -> PlotterUIActionID {
    PlotterUIActionID(
      rawValue: "learning.pen-interaction.\(owner.id).\(command.rawValue).s\(value)"
    )
  }

  static func learningReset(_ plan: LearningVacatePlan) -> PlotterUIActionID {
    let revisions = plan.expectedCurrentRevisionIDs
      .map { String(describing: $0) }
      .sorted()
      .joined(separator: ",")
    return PlotterUIActionID(
      rawValue: "learning.reset.\(plan.id).\(plan.expectedAcceptedAttemptSequence).\(revisions)"
    )
  }
}

enum LearningPathStage: Int, CaseIterable, Hashable, Identifiable, Sendable {
  case humanGuidedDiscovery = 1
  case observedDrawingTrials = 2

  var id: Self { self }
  var number: String { String(rawValue) }

  var title: String {
    switch self {
    case .humanGuidedDiscovery: LearningPathTerminology.Stage.plotterCalibration
    case .observedDrawingTrials: LearningPathTerminology.Stage.drawingValidation
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

enum ObservedDrawingTrialStep: Int, CaseIterable, Hashable, Identifiable, Sendable {
  case chooseDrawingBorderPlan = 1
  case captureLocalPreFrameBaseline
  case moveToDrawingBorderStart
  case drawDrawingBorder
  case revealAndObserveNewInk
  case compareIntendedAndObservedGeometry

  var id: Self { self }
  /// All cases are internal runtime phases of the single visible 2.1 exercise.
  /// Later 2.x numbers are reserved for actual future curriculum items.
  var stepNumber: String { "2.1" }

  var title: String {
    switch self {
    case .chooseDrawingBorderPlan: "Plan Drawing Border"
    case .captureLocalPreFrameBaseline: "Capture Baseline Frame"
    case .moveToDrawingBorderStart: "Move to Drawing Border Start"
    case .drawDrawingBorder: "Draw Drawing Border"
    case .revealAndObserveNewInk: "Reveal Drawing"
    case .compareIntendedAndObservedGeometry: "Compare Plan with Observed Ink"
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
  case observedDrawingTrial(ObservedDrawingTrialStep)

  var id: Self { self }

  static let navigationOrder: [Self] = [
    .stage(.humanGuidedDiscovery),
    .humanGuidedDiscovery(.penInteraction),
    .humanGuidedDiscovery(.pairedBoundaryDiscoveryAndCentering),
    .humanGuidedDiscovery(.calibrateCameraAndVisibleCap),
    .humanGuidedDiscovery(.calibratePenContactFromSparseMarks),
    .stage(.observedDrawingTrials),
    .observedDrawingTrial(.chooseDrawingBorderPlan),
  ]

  static let learningExerciseOrder: [Self] = [
    .humanGuidedDiscovery(.penInteraction),
    .humanGuidedDiscovery(.pairedBoundaryDiscoveryAndCentering),
    .humanGuidedDiscovery(.calibrateCameraAndVisibleCap),
    .humanGuidedDiscovery(.calibratePenContactFromSparseMarks),
    .observedDrawingTrial(.chooseDrawingBorderPlan),
  ]

  var stage: LearningPathStage {
    switch self {
    case .stage(let stage): stage
    case .humanGuidedDiscovery: .humanGuidedDiscovery
    case .observedDrawingTrial: .observedDrawingTrials
    }
  }

  var number: String {
    switch self {
    case .stage(let stage): stage.number
    case .humanGuidedDiscovery(let step): step.stepNumber
    case .observedDrawingTrial(let step): step.stepNumber
    }
  }

  var title: String {
    switch self {
    case .stage(let stage): stage.title
    case .humanGuidedDiscovery(let step): step.title
    case .observedDrawingTrial(.chooseDrawingBorderPlan):
      LearningPathTerminology.Exercise.drawAndValidateDrawingBorder
    case .observedDrawingTrial(let step): step.title
    }
  }

  var isExercise: Bool {
    switch self {
    case .humanGuidedDiscovery, .observedDrawingTrial: true
    case .stage: false
    }
  }

  var learningRewindAnchor: Self? {
    switch self {
    case .stage(.humanGuidedDiscovery):
      .humanGuidedDiscovery(.penInteraction)
    case .stage(.observedDrawingTrials):
      .observedDrawingTrial(.chooseDrawingBorderPlan)
    case .humanGuidedDiscovery, .observedDrawingTrial:
      self
    }
  }

  var navigationDepth: Int {
    switch self {
    case .humanGuidedDiscovery, .observedDrawingTrial: 1
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
}

struct LearningPathItemPresentation: Identifiable, Hashable, Sendable {
  let id: LearningPathItemID
  let status: LearningPathStageStatus
  let summary: String
  let isRepeatable: Bool

  init(
    id: LearningPathItemID,
    status: LearningPathStageStatus,
    summary: String,
    isRepeatable: Bool = false
  ) {
    self.id = id
    self.status = status
    self.summary = summary
    self.isRepeatable = isRepeatable
  }
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

struct ExerciseTimelinePresentation: Hashable, Sendable {
  let position: Int
  let total: Int
  let currentLabel: String

  init(position: Int, total: Int, currentLabel: String) {
    precondition(total > 0)
    precondition((1...total).contains(position))
    self.position = position
    self.total = total
    self.currentLabel = currentLabel
  }

  var positionText: String { "Step \(position) of \(total)" }
}

struct ExerciseEvidencePresentation: Identifiable, Hashable, Sendable {
  let label: String
  let fragments: [PresentationFragment]

  var id: String { label }

  init(label: String, fragments: [PresentationFragment]) {
    self.label = label
    self.fragments = fragments
  }
}

/// Unforgeable presentation authority for one currently stoppable logical owner.
/// Views must return this exact value with Stop so a stale control cannot stop a
/// successor operation that happens to occupy the same visual location.
struct ContextualStopCapabilityID: RawRepresentable, Hashable, Sendable {
  let rawValue: UUID

  init(rawValue: UUID = UUID()) {
    self.rawValue = rawValue
  }
}

struct ContextualStopActionPresentation: Hashable, Sendable {
  let capabilityID: ContextualStopCapabilityID
  let title: String
  let detail: String
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

enum ExerciseActionKind: Hashable, Sendable {
  case useSavedTraining
  case startNewLearning
  case start
  case choice(OperatorChoice)
  case cancel
  case stop(ContextualStopCapabilityID)
  case restart
  case redoThisStep
  case recordAnotherAttempt
  case boundary(PlotterBoundaryIntent)
  case runCameraCalibrationAndBuildProposal
  case acceptCameraCalibrationProposal
  case rejectCameraCalibrationProposal
  case drawFourCornerTipCircles
  case undoLastSparseTipClick
  case clearSparseTipClicks
  case revalidateTipCalibrationCheckpoint
  case acceptTipCalibrationProposal
  case rejectTipCalibrationProposal
  case retryTipCalibrationCommit
  case paperReplaced
}

enum SubsystemAuthorityRole: String, Hashable, Sendable {
  case motionGate = "Motion prerequisite"
  case operationOwner = "Active operation"
  case advisoryEvidence = "Reference evidence"
  case evidenceCommit = "Accepted result"
}

struct SubsystemStatusPresentation: Identifiable, Hashable, Sendable {
  let id: String
  let subsystem: String
  let state: String
  let role: SubsystemAuthorityRole
  let blocksNewMotion: Bool
  let detail: [PresentationFragment]
}

enum ExerciseActionRole: Hashable, Sendable {
  case positive
  case destructive
  case standard
}

struct ExerciseActionDescriptor: Identifiable, Hashable, Sendable {
  let kind: ExerciseActionKind
  let title: String
  let role: ExerciseActionRole
  let unavailableReason: String?

  var id: ExerciseActionKind { kind }
  var isEnabled: Bool { unavailableReason == nil }
  var buttonRole: OperatorButtonRole {
    if case .choice(let choice) = kind {
      return choice == .yes ? .affirmative : .negative
    }
    switch role {
    case .positive: return .affirmative
    case .destructive: return .negative
    case .standard: return .neutral
    }
  }

  init(
    kind: ExerciseActionKind,
    title: String,
    role: ExerciseActionRole = .standard,
    unavailableReason: String? = nil
  ) {
    self.kind = kind
    self.title = title
    self.role = role
    self.unavailableReason = unavailableReason
  }
}

enum ExerciseDirectionSelectionPurpose: String, Hashable, Sendable {
  case boundary = "Boundary direction"

  var label: String { rawValue }
}

struct ExerciseDirectionSelectionPresentation: Hashable, Sendable {
  static let canonicalChoiceOrder: [BoundaryDirection] = [
    .positiveX, .negativeX, .positiveY, .negativeY,
  ]

  let purpose: ExerciseDirectionSelectionPurpose
  let options: [BoundaryDirection]
  let selected: BoundaryDirection

  var allowsSelection: Bool { options.count > 1 }

  init(
    purpose: ExerciseDirectionSelectionPurpose,
    options: [BoundaryDirection] = Self.canonicalChoiceOrder,
    selected: BoundaryDirection
  ) {
    precondition(!options.isEmpty)
    precondition(Set(options).count == options.count)
    precondition(options.contains(selected))
    self.purpose = purpose
    self.options = Self.canonicalChoiceOrder.filter(options.contains)
    self.selected = selected
  }
}

struct PenSetpointAdjustmentPresentation: Hashable, Sendable {
  let command: PenCommand
  let value: Int
  let minimumValue: Int
  let maximumValue: Int
  let unavailableReason: String?

  var title: String { command == .raise ? "Pen Up servo" : "Pen Down servo" }
  var isEnabled: Bool { unavailableReason == nil }

  init(
    command: PenCommand,
    value: Int,
    minimumValue: Int = 0,
    maximumValue: Int = 1000,
    unavailableReason: String? = nil
  ) {
    precondition(minimumValue <= value && value <= maximumValue)
    self.command = command
    self.value = value
    self.minimumValue = minimumValue
    self.maximumValue = maximumValue
    self.unavailableReason = unavailableReason
  }
}

struct ExerciseActionStripPresentation: Hashable, Sendable {
  let ownerID: LearningPathItemID
  let actions: [ExerciseActionDescriptor]
  let directionSelection: ExerciseDirectionSelectionPresentation?
  let penSetpointAdjustment: PenSetpointAdjustmentPresentation?
  let mustRemainVisible: Bool

  init(
    ownerID: LearningPathItemID,
    actions: [ExerciseActionDescriptor],
    directionSelection: ExerciseDirectionSelectionPresentation? = nil,
    penSetpointAdjustment: PenSetpointAdjustmentPresentation? = nil,
    mustRemainVisible: Bool = false
  ) {
    precondition(Set(actions.map(\.id)).count == actions.count)
    self.ownerID = ownerID
    self.actions = actions
    self.directionSelection = directionSelection
    self.penSetpointAdjustment = penSetpointAdjustment
    self.mustRemainVisible = mustRemainVisible
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

enum OperationActivityOutcome: String, Hashable, Sendable {
  case inProgress = "In Progress"
  case succeeded = "Succeeded"
  case cancelled = "Cancelled"
  case needsAttention = "Needs Attention"
}

struct OperationActivityPresentation: Hashable, Sendable {
  let actor: String
  let action: String
  let phase: String?
  let outcomeLabel: String
  let outcome: OperationActivityOutcome
  let detail: [PresentationFragment]
  let acceptedResult: [PresentationFragment]
  let recovery: [PresentationFragment]

  init(
    actor: String,
    action: String,
    phase: String? = nil,
    outcomeLabel: String? = nil,
    outcome: OperationActivityOutcome,
    detail: [PresentationFragment] = [],
    acceptedResult: [PresentationFragment] = [],
    recovery: [PresentationFragment] = []
  ) {
    self.actor = actor
    self.action = action
    self.phase = phase
    self.outcomeLabel = outcomeLabel ?? outcome.rawValue
    self.outcome = outcome
    self.detail = detail
    self.acceptedResult = acceptedResult
    self.recovery = recovery
  }
}

struct OperatorActionPresentation: Hashable, Sendable {
  let itemID: LearningPathItemID
  let stepNumber: String
  let title: String
  let status: LearningPathStageStatus
  let participant: String?
  let instructions: [PresentationFragment]
  let expectedObservation: [PresentationFragment]
  let question: ExerciseQuestionPresentation?
  let timeline: ExerciseTimelinePresentation?
  let evidence: [ExerciseEvidencePresentation]
  let activity: OperationActivityPresentation?
  let subsystemStatuses: [SubsystemStatusPresentation]
  let actionStrip: ExerciseActionStripPresentation?
  let requestedFeedMMPerMinute: Double?
  let feedSource: FeedSelectionSource?

  init(
    itemID: LearningPathItemID,
    stepNumber: String,
    title: String,
    status: LearningPathStageStatus,
    participant: String? = nil,
    instructions: [PresentationFragment],
    expectedObservation: [PresentationFragment] = [],
    question: ExerciseQuestionPresentation? = nil,
    timeline: ExerciseTimelinePresentation? = nil,
    evidence: [ExerciseEvidencePresentation] = [],
    activity: OperationActivityPresentation? = nil,
    subsystemStatuses: [SubsystemStatusPresentation] = [],
    actionStrip: ExerciseActionStripPresentation? = nil,
    requestedFeedMMPerMinute: Double? = nil,
    feedSource: FeedSelectionSource? = nil
  ) {
    self.itemID = itemID
    self.stepNumber = stepNumber
    self.title = title
    self.status = status
    self.participant = participant
    self.instructions = instructions
    self.expectedObservation = expectedObservation
    self.question = question
    self.timeline = timeline
    self.evidence = evidence
    self.activity = activity
    self.subsystemStatuses = subsystemStatuses
    self.actionStrip = actionStrip
    self.requestedFeedMMPerMinute = requestedFeedMMPerMinute
    self.feedSource = feedSource
  }
}
