import Foundation
import PlotterRuntime

enum LearningPathStage: Int, CaseIterable, Hashable, Identifiable, Sendable {
  case connect = 1
  case enableMotion
  case humanGuidedDiscovery
  case observedDrawingTrials

  var id: Self { self }
  var number: String { String(rawValue) }

  var title: String {
    switch self {
    case .connect: "Connect"
    case .enableMotion: "Enable Motion"
    case .humanGuidedDiscovery: "Human-Guided Discovery"
    case .observedDrawingTrials: "Observed Drawing Trials"
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
  var stepNumber: String { "3.\(rawValue)" }

  var title: String {
    switch self {
    case .penInteraction: "Pen Interaction"
    case .pairedBoundaryDiscoveryAndCentering: "Paired Boundary Discovery and Centering"
    case .calibrateCameraAndVisibleCap: "Calibrate Camera and Visible Cap"
    case .calibratePenContactFromSparseMarks: "Calibrate Pen Contact from Sparse Marks"
    }
  }
}

enum ObservedDrawingTrialStep: Int, CaseIterable, Hashable, Identifiable, Sendable {
  case chooseIsolatedLinePlan = 1
  case captureLocalPreLineBaseline
  case moveToLineStart
  case drawIsolatedLine
  case revealAndObserveNewInk
  case compareIntendedAndObservedGeometry

  var id: Self { self }
  /// All cases are internal runtime phases of the single visible 4.1 exercise.
  /// Later 4.x numbers are reserved for actual future curriculum items.
  var stepNumber: String { "4.1" }

  var title: String {
    switch self {
    case .chooseIsolatedLinePlan: "Plan Predicted Isolated Line"
    case .captureLocalPreLineBaseline: "Capture Local Pre-Line Baseline"
    case .moveToLineStart: "Move to Line Start"
    case .drawIsolatedLine: "Draw Isolated Line"
    case .revealAndObserveNewInk: "Reveal and Observe New Ink"
    case .compareIntendedAndObservedGeometry: "Compare Intended and Observed Geometry"
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
    .stage(.connect),
    .stage(.enableMotion),
    .stage(.humanGuidedDiscovery),
    .humanGuidedDiscovery(.penInteraction),
    .humanGuidedDiscovery(.pairedBoundaryDiscoveryAndCentering),
    .humanGuidedDiscovery(.calibrateCameraAndVisibleCap),
    .humanGuidedDiscovery(.calibratePenContactFromSparseMarks),
    .stage(.observedDrawingTrials),
    .observedDrawingTrial(.chooseIsolatedLinePlan),
  ]

  static let learningExerciseOrder: [Self] = [
    .humanGuidedDiscovery(.penInteraction),
    .humanGuidedDiscovery(.pairedBoundaryDiscoveryAndCentering),
    .humanGuidedDiscovery(.calibrateCameraAndVisibleCap),
    .humanGuidedDiscovery(.calibratePenContactFromSparseMarks),
    .observedDrawingTrial(.chooseIsolatedLinePlan),
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
    case .observedDrawingTrial(.chooseIsolatedLinePlan):
      "Run Predicted Isolated Line Trial"
    case .observedDrawingTrial(let step): step.title
    }
  }

  var isExercise: Bool {
    switch self {
    case .humanGuidedDiscovery, .observedDrawingTrial: true
    case .stage(.connect), .stage(.enableMotion): true
    case .stage(.humanGuidedDiscovery), .stage(.observedDrawingTrials):
      false
    }
  }

  var learningRewindAnchor: Self? {
    switch self {
    case .stage(.humanGuidedDiscovery):
      .humanGuidedDiscovery(.penInteraction)
    case .stage(.observedDrawingTrials):
      .observedDrawingTrial(.chooseIsolatedLinePlan)
    case .humanGuidedDiscovery, .observedDrawingTrial:
      self
    case .stage(.connect), .stage(.enableMotion):
      nil
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

struct ManualMotionPresentation: Hashable, Sendable {
  static let xDistanceLabel = "X distance (mm)"
  static let yDistanceLabel = "Y distance (mm)"
  static let feedLabel = "Feed (mm/min)"

  let stopAction: ContextualStopActionPresentation?
  let jogUnavailableReason: String?

  var isStoppable: Bool { stopAction != nil }
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
  case start
  case choice(OperatorChoice)
  case setPenSetpoint(PenCommand, Int)
  case cancel
  case stop(ContextualStopCapabilityID)
  case restart
  case redoThisStep
  case recordAnotherAttempt
  case redoBoundary(BoundaryDirection)
  case recordAnotherBoundaryAttempt(BoundaryDirection)
  case selectDirection(ExerciseDirectionSelectionPurpose, BoundaryDirection)
  case moveToEstimatedCenter
  case runCameraCalibrationAndBuildProposal
  case acceptCameraCalibrationProposal
  case rejectCameraCalibrationProposal
  case drawFiveSparseTipCircles
  case undoLastSparseTipClick
  case clearSparseTipClicks
  case revalidateTipCalibrationCheckpoint
  case acceptTipCalibrationProposal
  case rejectTipCalibrationProposal
  case retryTipCalibrationCommit
  case paperReplaced
}

enum SubsystemAuthorityRole: String, Hashable, Sendable {
  case motionGate = "Motion gate"
  case operationOwner = "Operation owner"
  case advisoryEvidence = "Advisory evidence"
  case evidenceCommit = "Evidence commit"
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

  var title: String { command == .raise ? "Pen Up servo" : "Pen Down servo" }

  init(
    command: PenCommand,
    value: Int,
    minimumValue: Int = 0,
    maximumValue: Int = 1000
  ) {
    precondition(minimumValue <= value && value <= maximumValue)
    self.command = command
    self.value = value
    self.minimumValue = minimumValue
    self.maximumValue = maximumValue
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
