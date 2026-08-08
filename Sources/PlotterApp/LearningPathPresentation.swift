import Foundation
import PlotterRuntime

enum LearningPathStage: Int, CaseIterable, Hashable, Identifiable, Sendable {
  case connect = 1
  case enableMotion
  case humanGuidedDiscovery
  case observedDrawingTrials
  case adaptiveDrawing

  var id: Self { self }

  var number: String { String(rawValue) }

  var title: String {
    switch self {
    case .connect: "Connect"
    case .enableMotion: "Enable Motion"
    case .humanGuidedDiscovery: "Human-Guided Discovery"
    case .observedDrawingTrials: "Observed Drawing Trials"
    case .adaptiveDrawing: "Adaptive Drawing"
    }
  }
}

enum LearningPathStageStatus: String, CaseIterable, Hashable, Sendable {
  case complete = "Complete"
  case current = "Current"
  case next = "Next"
  case future = "Future"
  case needsAttention = "Needs Attention"
}

enum HumanGuidedDiscoveryStep: Int, CaseIterable, Hashable, Identifiable, Sendable {
  case penInteraction = 1
  case boundaryDiscovery
  case clearViewDiscovery

  var id: Self { self }

  var stepNumber: String { "3.\(rawValue)" }

  var title: String {
    switch self {
    case .penInteraction: "Pen Interaction"
    case .boundaryDiscovery: "Boundary Discovery"
    case .clearViewDiscovery: "Clear-View Discovery"
    }
  }
}

enum ObservedDrawingTrialStep: Int, CaseIterable, Hashable, Identifiable, Sendable {
  case captureCleanReference = 1
  case chooseLineStart
  case createAnchorMark
  case drawIsolatedLine
  case clearToolAndObserveInk
  case compareIntendedAndObservedGeometry

  var id: Self { self }

  var stepNumber: String { "4.\(rawValue)" }

  var title: String {
    switch self {
    case .captureCleanReference: "Capture Clean Reference"
    case .chooseLineStart: "Choose Line Start"
    case .createAnchorMark: "Create Anchor Mark"
    case .drawIsolatedLine: "Draw Isolated Line"
    case .clearToolAndObserveInk: "Clear Tool and Observe Ink"
    case .compareIntendedAndObservedGeometry: "Compare Intended and Observed Geometry"
    }
  }
}

struct LearningPathStagePresentation: Identifiable, Hashable, Sendable {
  let stage: LearningPathStage
  let status: LearningPathStageStatus
  let summary: String

  var id: LearningPathStage { stage }

  init(
    stage: LearningPathStage,
    status: LearningPathStageStatus,
    summary: String
  ) {
    self.stage = stage
    self.status = status
    self.summary = summary
  }
}

struct OperatorActionPresentation {
  let stepNumber: String
  let title: String
  let participant: String
  let action: String
  let expectedObservation: String
  let primaryActionTitle: String?
  let primaryActionUnavailableReason: String?
  let choices: [OperatorChoice]
  let requestedFeedMMPerMinute: Double?
  let feedSource: FeedSelectionSource?

  init(
    stepNumber: String,
    title: String,
    participant: String,
    action: String,
    expectedObservation: String,
    primaryActionTitle: String? = nil,
    primaryActionUnavailableReason: String? = nil,
    choices: [OperatorChoice] = [],
    requestedFeedMMPerMinute: Double? = nil,
    feedSource: FeedSelectionSource? = nil
  ) {
    self.stepNumber = stepNumber
    self.title = title
    self.participant = participant
    self.action = action
    self.expectedObservation = expectedObservation
    self.primaryActionTitle = primaryActionTitle
    self.primaryActionUnavailableReason = primaryActionUnavailableReason
    self.choices = choices
    self.requestedFeedMMPerMinute = requestedFeedMMPerMinute
    self.feedSource = feedSource
  }
}

enum LearningPathFlowPhase: Hashable, Sendable {
  case connect
  case enableMotion
  case humanGuidedDiscovery(HumanGuidedDiscoveryStep)
  case observedDrawingTrials(ObservedDrawingTrialStep)
  case adaptiveDrawing
}

/// Presentation-only location within the Learning Path.
///
/// Runtime eligibility remains owned by the typed operation that consumes the
/// relevant controller, camera, pen, or observation facts. Changing this value
/// never grants motion authority and never makes a machine request eligible.
struct LearningPathFlowCoordinator: Hashable, Sendable {
  private(set) var phase: LearningPathFlowPhase = .connect

  mutating func present(_ phase: LearningPathFlowPhase) {
    self.phase = phase
  }
}
