import Foundation
import PlotterModel
import PlotterRuntime

enum ExplorationFlowPhase: String, CaseIterable, Hashable, Sendable {
  case inactive
  case motionPreflight
  case armatureGuidance
  case cleanReference
  case chooseLineStart
  case anchorDot
  case anchoredBaseline
  case isolatedStroke
  case postLineObservation
  case awaitingAssessment
  case completed
  case stopped

  var title: String {
    switch self {
    case .inactive: "Not started"
    case .motionPreflight: "Motion Preflight"
    case .armatureGuidance: "Armature Guidance"
    case .cleanReference: "Clean reference"
    case .chooseLineStart: "Choose line start"
    case .anchorDot: "Anchor dot"
    case .anchoredBaseline: "Anchored baseline"
    case .isolatedStroke: "Isolated line"
    case .postLineObservation: "Post-line observation"
    case .awaitingAssessment: "Human assessment"
    case .completed: "Episode complete"
    case .stopped: "Stopped"
    }
  }
}

struct ExplorationTimelineEntry: Identifiable, Hashable, Sendable {
  enum Participant: String, Hashable, Sendable {
    case operatorHuman = "OPERATOR"
    case voice = "VOICE"
    case controller = "CONTROLLER"
    case camera = "CAMERA"
    case vision = "VISION"
    case simulator = "SIMULATOR"
  }

  let id: UUID
  let monotonicNanoseconds: UInt64
  let participant: Participant
  let action: String
  let observation: String

  init(
    id: UUID = UUID(),
    monotonicNanoseconds: UInt64,
    participant: Participant,
    action: String,
    observation: String
  ) {
    self.id = id
    self.monotonicNanoseconds = monotonicNanoseconds
    self.participant = participant
    self.action = action
    self.observation = observation
  }
}

enum ExplorationFlowError: Error, Equatable, Sendable {
  case notActive
  case unexpectedPhase(expected: ExplorationFlowPhase, actual: ExplorationFlowPhase)
  case frameSourceMismatch
  case cameraConfigurationChanged
  case frameNotStrictlyNewer
  case missingClearPose
  case missingLineStart
  case missingAnchor
  case emptyAssessment
}

enum ExplorationSimulationError: Error, Equatable, Sendable {
  case anchorRejected(String)
  case inkRejected(String)
  case assessmentNotAccepted
}

enum ExplorationLiveError: Error, Equatable, Sendable {
  case freshFrameUnavailable
  case armatureProposalUnavailable
  case missingLearningFrame(String)
  case controllerOutcome(String)
}

/// The single app-level ordering contract used by deterministic rehearsal and
/// the live machine. It owns no controller bytes, speech recognizer, camera, or
/// vision algorithm; those adapters supply typed outcomes to the same transitions.
struct ExplorationFlowCoordinator: Hashable, Sendable {
  enum Authority: String, Hashable, Sendable {
    case live
    case simulated
  }

  struct FrameReference: Hashable, Sendable {
    let frameID: FrameID
    let contentSHA256: String
    let captureNanoseconds: UInt64
    let cameraConfigurationID: CameraConfigurationID
    let width: Int
    let height: Int
    let rowBytes: Int
    let pixelFormat: FramePixelFormat

    init(_ frame: StampedFrame) {
      frameID = frame.id
      contentSHA256 = frame.contentSHA256
      captureNanoseconds = frame.captureNanoseconds
      cameraConfigurationID = frame.cameraConfigurationID
      width = frame.width
      height = frame.height
      rowBytes = frame.rowBytes
      pixelFormat = frame.pixelFormat
    }
  }

  private(set) var authority: Authority?
  private(set) var phase: ExplorationFlowPhase = .inactive
  private(set) var acceptedClearPoseID: String?
  private(set) var cleanReference: FrameReference?
  private(set) var lineStartPosition: MachinePosition?
  private(set) var anchoredBaseline: FrameReference?
  private(set) var anchorCentroid: Point2<CameraPixelSpace>?
  private(set) var postLineFrame: FrameReference?
  private(set) var humanAssessment: String?

  var isActive: Bool {
    authority != nil && phase != .inactive && phase != .completed && phase != .stopped
  }

  mutating func start(authority: Authority) {
    self = Self()
    self.authority = authority
    phase = .motionPreflight
  }

  mutating func completeMotionPreflight() throws {
    try require(.motionPreflight)
    phase = .armatureGuidance
  }

  mutating func acceptClearPose(id: String) throws {
    try require(.armatureGuidance)
    guard !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw ExplorationFlowError.missingClearPose
    }
    acceptedClearPoseID = id
    phase = .cleanReference
  }

  mutating func recordCleanReference(_ displayedFrame: DisplayedFrame) throws {
    try require(.cleanReference)
    try requireSource(displayedFrame)
    guard acceptedClearPoseID != nil else { throw ExplorationFlowError.missingClearPose }
    cleanReference = FrameReference(displayedFrame.frame)
    phase = .chooseLineStart
  }

  mutating func recordLineStart(_ position: MachinePosition) throws {
    try require(.chooseLineStart)
    lineStartPosition = position
    phase = .anchorDot
  }

  mutating func recordAnchoredBaseline(
    _ displayedFrame: DisplayedFrame,
    anchorCentroid: Point2<CameraPixelSpace>
  ) throws {
    try require(.anchorDot)
    try requireSource(displayedFrame)
    guard lineStartPosition != nil else { throw ExplorationFlowError.missingLineStart }
    guard let cleanReference else { throw ExplorationFlowError.missingAnchor }
    let incoming = FrameReference(displayedFrame.frame)
    guard incoming.cameraConfigurationID == cleanReference.cameraConfigurationID else {
      throw ExplorationFlowError.cameraConfigurationChanged
    }
    guard incoming.captureNanoseconds > cleanReference.captureNanoseconds else {
      throw ExplorationFlowError.frameNotStrictlyNewer
    }
    anchoredBaseline = incoming
    self.anchorCentroid = anchorCentroid
    phase = .anchoredBaseline
  }

  mutating func beginIsolatedStroke() throws {
    try require(.anchoredBaseline)
    guard lineStartPosition != nil else { throw ExplorationFlowError.missingLineStart }
    guard anchorCentroid != nil else { throw ExplorationFlowError.missingAnchor }
    phase = .isolatedStroke
  }

  mutating func settleForPostLineObservation() throws {
    try require(.isolatedStroke)
    guard acceptedClearPoseID != nil else { throw ExplorationFlowError.missingClearPose }
    phase = .postLineObservation
  }

  mutating func recordPostLineFrame(_ displayedFrame: DisplayedFrame) throws {
    try require(.postLineObservation)
    try requireSource(displayedFrame)
    guard let anchoredBaseline else { throw ExplorationFlowError.missingAnchor }
    let incoming = FrameReference(displayedFrame.frame)
    guard incoming.cameraConfigurationID == anchoredBaseline.cameraConfigurationID else {
      throw ExplorationFlowError.cameraConfigurationChanged
    }
    guard incoming.captureNanoseconds > anchoredBaseline.captureNanoseconds else {
      throw ExplorationFlowError.frameNotStrictlyNewer
    }
    postLineFrame = incoming
    phase = .awaitingAssessment
  }

  mutating func acceptAssessment(_ assessment: String) throws {
    try require(.awaitingAssessment)
    let normalized = assessment.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalized.isEmpty else { throw ExplorationFlowError.emptyAssessment }
    humanAssessment = normalized
    phase = .completed
  }

  mutating func stop() {
    phase = .stopped
  }

  private func require(_ expected: ExplorationFlowPhase) throws {
    guard authority != nil else { throw ExplorationFlowError.notActive }
    guard phase == expected else {
      throw ExplorationFlowError.unexpectedPhase(expected: expected, actual: phase)
    }
  }

  private func requireSource(_ displayedFrame: DisplayedFrame) throws {
    switch (authority, displayedFrame.source) {
    case (.live, .live), (.simulated, .simulated):
      return
    default:
      throw ExplorationFlowError.frameSourceMismatch
    }
  }
}
