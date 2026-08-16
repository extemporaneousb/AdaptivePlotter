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
    case .pairedBoundaryDiscoveryAndCentering: "Set X, Y Boundaries"
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
  var stepNumber: String { "4.\(rawValue)" }

  var title: String {
    switch self {
    case .chooseIsolatedLinePlan: "Choose Isolated Line Plan"
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
    case .observedDrawingTrial(let step): step.title
    }
  }

  var isExercise: Bool {
    switch self {
    case .humanGuidedDiscovery, .observedDrawingTrial: true
    case .stage: false
    }
  }
}

/// The sole hierarchy and ordering authority for the Learning Path.
///
/// Navigation, indentation, and subtree invalidation all consume this same
/// value. No parallel chronological exercise list or rewind anchor exists.
struct LearningPathTree: Hashable, Sendable {
  struct Node: Hashable, Sendable {
    let item: LearningPathItemID
    let children: [Node]

    init(_ item: LearningPathItemID, children: [Node] = []) {
      self.item = item
      self.children = children
    }
  }

  static let curriculum = LearningPathTree(roots: [
    Node(.stage(.connect)),
    Node(.stage(.enableMotion)),
    Node(.stage(.humanGuidedDiscovery), children: [
      Node(.humanGuidedDiscovery(.penInteraction)),
      Node(.humanGuidedDiscovery(.pairedBoundaryDiscoveryAndCentering)),
      Node(.humanGuidedDiscovery(.calibrateCameraAndVisibleCap)),
      Node(.humanGuidedDiscovery(.calibratePenContactFromSparseMarks)),
    ]),
    Node(.stage(.observedDrawingTrials), children: [
      Node(.observedDrawingTrial(.chooseIsolatedLinePlan)),
      Node(.observedDrawingTrial(.captureLocalPreLineBaseline)),
      Node(.observedDrawingTrial(.moveToLineStart)),
      Node(.observedDrawingTrial(.drawIsolatedLine)),
      Node(.observedDrawingTrial(.revealAndObserveNewInk)),
      Node(.observedDrawingTrial(.compareIntendedAndObservedGeometry)),
    ]),
  ])

  let roots: [Node]
  let flattenedItems: [LearningPathItemID]
  private let parentByItem: [LearningPathItemID: LearningPathItemID]
  private let childrenByItem: [LearningPathItemID: [LearningPathItemID]]
  private let depthByItem: [LearningPathItemID: Int]

  init(roots: [Node]) {
    var flattenedItems: [LearningPathItemID] = []
    var parentByItem: [LearningPathItemID: LearningPathItemID] = [:]
    var childrenByItem: [LearningPathItemID: [LearningPathItemID]] = [:]
    var depthByItem: [LearningPathItemID: Int] = [:]

    func visit(_ node: Node, parent: LearningPathItemID?, depth: Int) {
      precondition(depthByItem[node.item] == nil, "Learning Path items must be unique.")
      flattenedItems.append(node.item)
      depthByItem[node.item] = depth
      childrenByItem[node.item] = node.children.map(\.item)
      if let parent { parentByItem[node.item] = parent }
      for child in node.children {
        visit(child, parent: node.item, depth: depth + 1)
      }
    }

    for root in roots { visit(root, parent: nil, depth: 0) }
    precondition(Set(flattenedItems) == Set(LearningPathStage.allCases.map(LearningPathItemID.stage)
      + HumanGuidedDiscoveryStep.allCases.map(LearningPathItemID.humanGuidedDiscovery)
      + ObservedDrawingTrialStep.allCases.map(LearningPathItemID.observedDrawingTrial)))

    self.roots = roots
    self.flattenedItems = flattenedItems
    self.parentByItem = parentByItem
    self.childrenByItem = childrenByItem
    self.depthByItem = depthByItem
  }

  func parent(of item: LearningPathItemID) -> LearningPathItemID? {
    parentByItem[item]
  }

  func children(of item: LearningPathItemID) -> [LearningPathItemID] {
    childrenByItem[item] ?? []
  }

  func depth(of item: LearningPathItemID) -> Int? {
    depthByItem[item]
  }

  func descendants(
    of item: LearningPathItemID,
    includingRoot: Bool = false
  ) -> [LearningPathItemID] {
    guard depthByItem[item] != nil else { return [] }
    var result: [LearningPathItemID] = includingRoot ? [item] : []
    for child in children(of: item) {
      result.append(child)
      result.append(contentsOf: descendants(of: child))
    }
    return result
  }

  func descendantLeaves(
    of item: LearningPathItemID,
    includingRoot: Bool = false
  ) -> [LearningPathItemID] {
    descendants(of: item, includingRoot: includingRoot).filter(isActionableLeaf)
  }

  func isActionableLeaf(_ item: LearningPathItemID) -> Bool {
    depthByItem[item] != nil && children(of: item).isEmpty && item.isExercise
  }
}

enum LearningInvalidationSource: String, Hashable, Sendable {
  case live = "LIVE"
  case simulated = "SIMULATED"
}

enum LearningInvalidationScope: Hashable, Sendable {
  case leaf(root: LearningPathItemID)
  case subtree(root: LearningPathItemID)
  case all

  var root: LearningPathItemID? {
    switch self {
    case .leaf(let root), .subtree(let root): root
    case .all: nil
    }
  }
}

enum LearningInvalidationPlanContractVersion: Int, Hashable, Sendable {
  case v1 = 1
}

/// Immutable preview and stale-state guard for explicit learning invalidation.
/// The UI presents this plan before passing it back for mutation.
struct LearningInvalidationPlan: Hashable, Identifiable, Sendable {
  let contractVersion: LearningInvalidationPlanContractVersion
  let scope: LearningInvalidationScope
  let source: LearningInvalidationSource
  let affectedItemIDs: [LearningPathItemID]
  let expectedCurrentRevisionIDs: Set<LearningArtifactRevisionID>
  let expectedGraphRevision: UInt64
  let expectedAcceptedAttemptSequence: UInt64
  let expectedAuthorityManifestRevision: LearningAuthorityStoreRevision?
  let removesDurableMachineRegistration: Bool
  let removesDurableTipRegistration: Bool
  let physicalInkMayRemain: Bool

  init(
    contractVersion: LearningInvalidationPlanContractVersion = .v1,
    scope: LearningInvalidationScope,
    source: LearningInvalidationSource,
    affectedItemIDs: [LearningPathItemID],
    expectedCurrentRevisionIDs: Set<LearningArtifactRevisionID>,
    expectedGraphRevision: UInt64,
    expectedAcceptedAttemptSequence: UInt64,
    expectedAuthorityManifestRevision: LearningAuthorityStoreRevision?,
    removesDurableMachineRegistration: Bool,
    removesDurableTipRegistration: Bool,
    physicalInkMayRemain: Bool
  ) {
    let tree = LearningPathTree.curriculum
    let affectedSet = Set(affectedItemIDs)
    precondition(!affectedItemIDs.isEmpty)
    precondition(affectedSet.count == affectedItemIDs.count)
    precondition(affectedItemIDs.allSatisfy(tree.isActionableLeaf))
    precondition(
      affectedItemIDs == tree.flattenedItems.filter(affectedSet.contains),
      "Affected items must follow canonical tree order."
    )
    switch scope {
    case .leaf(let root):
      precondition(tree.isActionableLeaf(root))
      precondition(affectedSet.contains(root))
    case .subtree(let root):
      precondition(!tree.children(of: root).isEmpty)
      precondition(Set(tree.descendantLeaves(of: root)).isSubset(of: affectedSet))
    case .all:
      precondition(Set(tree.flattenedItems.filter(tree.isActionableLeaf)).isSubset(of: affectedSet))
    }
    self.contractVersion = contractVersion
    self.scope = scope
    self.source = source
    self.affectedItemIDs = affectedItemIDs
    self.expectedCurrentRevisionIDs = expectedCurrentRevisionIDs
    self.expectedGraphRevision = expectedGraphRevision
    self.expectedAcceptedAttemptSequence = expectedAcceptedAttemptSequence
    self.expectedAuthorityManifestRevision = expectedAuthorityManifestRevision
    self.removesDurableMachineRegistration = removesDurableMachineRegistration
    self.removesDurableTipRegistration = removesDurableTipRegistration
    self.physicalInkMayRemain = physicalInkMayRemain
  }

  var id: String {
    let scopeID: String = switch scope {
    case .leaf(let root): "leaf-\(root.number)"
    case .subtree(let root): "subtree-\(root.number)"
    case .all: "all"
    }
    return "v\(contractVersion.rawValue)-\(source.rawValue)-\(scopeID)"
  }

  var title: String {
    switch scope {
    case .leaf: "Invalidate This Step"
    case .subtree: "Invalidate This Branch"
    case .all: "Invalidate All Learning"
    }
  }

  var message: String {
    let count = affectedItemIDs.count
    let suffix = physicalInkMayRemain ? " Physical ink remains on the paper." : ""
    return "Delete collected data for \(count) learning \(count == 1 ? "step" : "steps").\(suffix)"
  }
}

struct LearningPathItemPresentation: Identifiable, Hashable, Sendable {
  let id: LearningPathItemID
  let status: LearningPathStageStatus

  init(
    id: LearningPathItemID,
    status: LearningPathStageStatus
  ) {
    self.id = id
    self.status = status
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
  case stopAndAcceptBoundary(ContextualStopCapabilityID)
  case stop(ContextualStopCapabilityID)
  case cancel(ContextualStopCapabilityID)
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
  case createNextSparseTipMark
  case reClickSparseTipFrame
  case acceptSparseTipMark
  case revalidateTipCalibrationCheckpoint
  case acceptTipCalibration
  case rejectTipCalibration
  case paperReplaced
  case chooseIsolatedLinePlan(BoundaryDirection)
  case captureLocalPreLineBaseline
  case moveToLineStart
  case drawIsolatedLine
  case revealAndObserveNewInk
  case recordDrawingTrialAssessment(DrawingTrialAssessment)
}

enum ExerciseActionEffect: Hashable, Sendable {
  case commit
  case interrupt
  case editValue
  case utility

  var buttonRole: OperatorButtonRole {
    switch self {
    case .commit: .commit
    case .interrupt: .interrupt
    case .editValue: .editValue
    case .utility: .utility
    }
  }
}

enum ExerciseActionKeyboardShortcut: Hashable, Sendable {
  case escape
}

extension ExerciseActionKind {
  /// The exhaustive semantic-to-visual mapping for every Exercise action.
  /// Views never choose colors or progression meaning manually.
  var effect: ExerciseActionEffect {
    switch self {
    case .start,
      .choice(.yes),
      .stopAndAcceptBoundary,
      .restart,
      .redoThisStep,
      .recordAnotherAttempt,
      .redoBoundary,
      .recordAnotherBoundaryAttempt,
      .moveToEstimatedCenter,
      .runCameraCalibrationAndBuildProposal,
      .acceptCameraCalibrationProposal,
      .createNextSparseTipMark,
      .acceptSparseTipMark,
      .revalidateTipCalibrationCheckpoint,
      .acceptTipCalibration,
      .chooseIsolatedLinePlan,
      .captureLocalPreLineBaseline,
      .moveToLineStart,
      .drawIsolatedLine,
      .revealAndObserveNewInk,
      .recordDrawingTrialAssessment:
      .commit
    case .choice(.no),
      .stop,
      .cancel,
      .rejectCameraCalibrationProposal,
      .rejectTipCalibration,
      .paperReplaced:
      .interrupt
    case .setPenSetpoint,
      .selectDirection,
      .reClickSparseTipFrame:
      .editValue
    }
  }

  var keyboardShortcut: ExerciseActionKeyboardShortcut? {
    if case .stop = self { return .escape }
    return nil
  }
}

struct ExerciseActionDescriptor: Identifiable, Hashable, Sendable {
  let kind: ExerciseActionKind
  let title: String
  let unavailableReason: String?

  var id: ExerciseActionKind { kind }
  var isEnabled: Bool { unavailableReason == nil }
  var effect: ExerciseActionEffect { kind.effect }
  var buttonRole: OperatorButtonRole { effect.buttonRole }
  var keyboardShortcut: ExerciseActionKeyboardShortcut? { kind.keyboardShortcut }
  var isDefaultAction: Bool { false }

  init(
    kind: ExerciseActionKind,
    title: String,
    unavailableReason: String? = nil
  ) {
    self.kind = kind
    self.title = title
    self.unavailableReason = unavailableReason
  }
}

enum ExerciseDirectionSelectionPurpose: String, Hashable, Sendable {
  case boundary = "Boundary direction"
  case linePlan = "Line direction"

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

  init(prompt: [PresentationFragment]) {
    precondition(!prompt.isEmpty)
    self.prompt = prompt
  }
}

enum ExerciseScriptSpeaker: String, Hashable, Sendable {
  case plotter = "Plotter"
  case you = "You"
}

struct ExerciseScriptLinePresentation: Hashable, Sendable {
  let speaker: ExerciseScriptSpeaker
  let fragments: [PresentationFragment]

  init(
    speaker: ExerciseScriptSpeaker,
    fragments: [PresentationFragment]
  ) {
    precondition(!fragments.isEmpty)
    self.speaker = speaker
    self.fragments = fragments
  }
}

struct LearningInvalidationPresentation: Hashable, Sendable {
  let selectedPlan: LearningInvalidationPlan?
  let invalidateAllPlan: LearningInvalidationPlan?
  let unavailableReason: String?
}

struct OperatorActionPresentation: Hashable, Sendable {
  let item: LearningPathItemPresentation
  let script: [ExerciseScriptLinePresentation]
  let question: ExerciseQuestionPresentation?
  let actionStrip: ExerciseActionStripPresentation?
  let invalidation: LearningInvalidationPresentation

  var heading: String { "\(item.id.number) - \(item.id.title)" }

  init(
    item: LearningPathItemPresentation,
    script: [ExerciseScriptLinePresentation],
    question: ExerciseQuestionPresentation? = nil,
    actionStrip: ExerciseActionStripPresentation? = nil,
    invalidation: LearningInvalidationPresentation
  ) {
    precondition(!script.isEmpty)
    self.item = item
    self.script = script
    self.question = question
    self.actionStrip = actionStrip
    self.invalidation = invalidation
  }
}
