import Foundation
import Observation
import PlotterModel
import PlotterRuntime

enum CanvasLayer: String, CaseIterable, Identifiable {
  case intendedPath = "Intended path"
  case modelPrediction = "Plotter estimate"
  case observedInk = "Observed ink"
  case residuals = "Residuals"
  case penCap = "Pen cap"
  case measuredFrameSides = "Measured frame sides"
  case drawingFrameEstimate = "Drawing frame estimate"
  case armatureEstimate = "Armature"

  var id: Self { self }

  var overlayKind: CameraOverlayKind {
    switch self {
    case .intendedPath: .intendedPath
    case .modelPrediction: .modelPrediction
    case .observedInk: .observedInk
    case .residuals: .residual
    case .penCap: .penCap
    case .measuredFrameSides: .measuredFrameSide
    case .drawingFrameEstimate: .drawingFrameEstimate
    case .armatureEstimate: .armatureEstimate
    }
  }
}

enum OperatorFrameMode: String, CaseIterable, Identifiable, Sendable {
  case live = "LIVE"
  case simulated = "SIMULATED"

  var id: Self { self }
}

enum SimulatorModelMode: String, CaseIterable, Identifiable, Sendable {
  case prior = "PRIOR MISMATCH"
  case trained = "ACCEPTED MODEL"

  var id: Self { self }
}

enum JogDirection: String, CaseIterable, Identifiable, Sendable {
  case xNegative
  case xPositive
  case yNegative
  case yPositive

  var id: Self { self }

  var shortLabel: String {
    switch self {
    case .xNegative: "X−"
    case .xPositive: "X+"
    case .yNegative: "Y−"
    case .yPositive: "Y+"
    }
  }
}

enum BoundaryTeachingState: Equatable, Sendable {
  case idle
  case awaitingConfirmation(JogDirection)
  case ownerActive(JogDirection)
  case cancelling(JogDirection)

  var direction: JogDirection? {
    switch self {
    case .idle: nil
    case .awaitingConfirmation(let direction), .ownerActive(let direction),
      .cancelling(let direction):
      direction
    }
  }
}

enum ContextualStopTarget: Hashable, Sendable {
  case boundaryDiscovery(transactionID: UUID, direction: BoundaryDirection)
  case manualJog
  case drawingTrial
}

struct ContextualStopPresentation: Hashable, Sendable {
  let title = "Stop"
  let detail: String
}

enum DrawingTrialAssessment: String, CaseIterable, Identifiable, Hashable, Sendable {
  case observedGeometryAccepted
  case inkOrGeometryUnclear

  var id: Self { self }

  var title: String {
    switch self {
    case .observedGeometryAccepted: "Observed geometry accepted"
    case .inkOrGeometryUnclear: "Ink or geometry unclear"
    }
  }
}

private enum LearningPathOperationError: Error, Sendable {
  case freshFrameUnavailable
  case controllerOutcome(String)
  case anchorRejected(String)
  case inkRejected(String)
  case requiredState(String)
}

struct SimulatedActionSurfaceContent: Sendable {
  let displayedFrame: DisplayedFrame
  let overlays: [CameraOverlayMeasurement]
  let evidenceLabel: String
  let commandedPenState: PenState
  let learningSummary: String

  init(
    displayedFrame: DisplayedFrame,
    overlays: [CameraOverlayMeasurement],
    evidenceLabel: String = SimulatedOverlaySceneContent.evidenceLabel,
    commandedPenState: PenState = .unknown,
    learningSummary: String = "deterministic simulator"
  ) {
    self.displayedFrame = displayedFrame
    self.overlays = overlays
    self.evidenceLabel = evidenceLabel
    self.commandedPenState = commandedPenState
    self.learningSummary = learningSummary
  }
}

struct LiveSceneInspection: Sendable {
  let displayedFrame: DisplayedFrame
  let measurement: PlotterSceneMeasurement
}

@MainActor
@Observable
final class OperatorWorkspace {
  private enum ExerciseAttemptMode: Sendable {
    case normal
    case replacement
    case additional
  }

  private struct DrawingTrialPayloadSnapshot {
    let step: ObservedDrawingTrialStep
    let cleanReference: DisplayedFrame?
    let anchoredBaseline: DisplayedFrame?
    let postLineFrame: DisplayedFrame?
    let lineStart: MachinePosition?
    let strokeEvidence: DrawingStrokeEvidence?
    let anchorObservation: AnchorDotObservation?
    let inkObservation: IsolatedInkObservation?
    let inkStatus: String
    let assessment: DrawingTrialAssessment?
    let episode: ExplorationEpisode?
    let completedEpisodes: [ExplorationEpisode]
  }

  private struct BoundaryDerivedValueSnapshot {
    let posterior: DrawingFramePosterior?
    let observationsByAttemptID: [ExerciseAttemptID: DrawingFrameBoundaryObservation]
    let overlays: [CameraOverlayMeasurement]
  }

  private enum MotionPriors {
    static let stepMM = "1.0"
    static let feedMMPerMinute = "100"
    /// Finite GRBL wire segment used only for renewal under one logical owner.
    /// Reaching this distance is never a Boundary Discovery result.
    static let boundaryWireSegmentMM = 10.0
  }

  struct MachineActions: Sendable {
    let select: @Sendable (MachineLinkDescriptor) async throws -> RunInterpreterSnapshot
    let snapshot: @Sendable () async -> RunInterpreterSnapshot?
    let requestPassiveProbe: @Sendable () async throws -> PassiveProbeResult
    let activateMotionGuard: @Sendable () async -> MotionGuardActivationOutcome
    let deactivateMotionGuard: @Sendable () async -> Void
    let requestRelativeJog: @Sendable (RelativeJogRequest) async -> MotionOutcome
    let requestDrawingStroke: @Sendable (DrawingStrokeRequest) async -> DrawingStrokeOutcome
    let requestPenActuation: @Sendable (PenCommand) async -> PenOutcome
    let requestBoundaryMotion: @Sendable (BoundaryMotionRequest) async -> BoundaryMotionOutcome
    let requestJogCancel: @Sendable (JogCancelIntent) async -> JogCancelOutcome
    let disconnect: @Sendable () async -> Void
  }

  struct AnnouncementActions: Sendable {
    let announce: @Sendable (String) async -> SpeechAnnouncementOutcome
    let cancelForShutdown: @Sendable () async -> Void
  }

  struct CameraActions: Sendable {
    let discover: @Sendable () async -> CameraCaptureSnapshot
    let select: @Sendable (CameraDeviceID) async throws -> CameraCaptureSnapshot
    let start: @Sendable () async -> CameraCaptureSnapshot
    let stop: @Sendable () async -> CameraCaptureSnapshot
    let restart: @Sendable () async -> CameraCaptureSnapshot
    let snapshot: @Sendable () async -> CameraCaptureSnapshot
    let frames: @Sendable () async -> AsyncStream<DisplayedFrame>
    let inspectScene: @Sendable (UInt64) async throws -> LiveSceneInspection?
    let captureFrame: @Sendable (UInt64) async throws -> DisplayedFrame?
    let captureSnapshot: @Sendable () async throws -> String
    let setAutomaticInspection: @Sendable (VisionAnalysisCadence?) async
      -> PlotterSceneAnalysisSnapshot
    let analysisUpdates: @Sendable () async -> AsyncStream<PlotterSceneAnalysisSnapshot>
    let simulatedContent: @Sendable (SimulatorModelMode) async throws
      -> SimulatedActionSurfaceContent
    let simulatedExplorationFrames: @Sendable () async throws
      -> SimulatedExplorationCameraFrames
    let observeAnchorDot: @Sendable (AnchorDotObservationRequest) async
      -> AnchorDotObservationOutcome
    let observeIsolatedInk: @Sendable (IsolatedInkObservationRequest) async
      -> IsolatedInkObservationOutcome
    let exportLearningEpisode: @Sendable (
      [StartupFrameRecorder.LearningFrame], String
    ) async throws -> String
  }

  var visibleLayers = Set(CanvasLayer.allCases)
  var frameMode: OperatorFrameMode = .live
  var simulatorModelMode: SimulatorModelMode = .prior

  // String-backed numeric inputs preserve partially typed values and keep X/Y
  // independent. Runtime value constructors and MachineController own validity.
  var xStepText = MotionPriors.stepMM
  var yStepText = MotionPriors.stepMM
  var feedText = MotionPriors.feedMMPerMinute

  private(set) var serialDevices: [MachineLinkDescriptor] = []
  private(set) var selectedSerialDevice: MachineLinkDescriptor?
  private(set) var passiveProbeResult: PassiveProbeResult?
  private(set) var machineSnapshot: RunInterpreterSnapshot?
  private(set) var machineError: String?
  private(set) var controllerConnectionActionInProgress = false
  private(set) var passiveProbeInProgress = false
  private(set) var jogRequestInProgress = false
  private(set) var penRequestInProgress = false
  private(set) var jogCancelRequestInProgress = false
  private(set) var frameModeSwitchInProgress = false
  private(set) var motionGuardActivationInProgress = false
  private(set) var lastMotionGuardActivationText = "not activated"

  private(set) var cameraSnapshot: CameraCaptureSnapshot?
  private(set) var displayedFrame: DisplayedFrame?
  private(set) var latestLiveCameraFrame: DisplayedFrame?
  private(set) var cameraOverlays: [CameraOverlayMeasurement] = []
  private(set) var cameraError: String?
  private(set) var visionError: String?
  private(set) var sceneInspectionInProgress = false
  private(set) var analysisFrameHeld = false
  var visionAnalysisCadence: VisionAnalysisCadence = .fiveFPS
  private(set) var automaticVisionEnabled = false
  private(set) var visionAnalysisSnapshot: PlotterSceneAnalysisSnapshot = .stopped
  private(set) var lastSceneMeasurement: PlotterSceneMeasurement?
  private(set) var lastCameraSnapshotPath: String?
  private(set) var simulatorEvidenceLabel = SimulatedOverlaySceneContent.evidenceLabel
  private(set) var simulatorPenState: PenState = .unknown
  private(set) var simulatorLearningSummary = "Switch to SIMULATED to inspect model behavior."
  private(set) var boundaryTeachingState: BoundaryTeachingState = .idle
  private(set) var boundaryTeachingResultText = "Choose one side to begin."
  private(set) var boundaryPositions: [JogDirection: MachinePosition] = [:]
  var selectedDiscoverySequenceID: DiscoverySequenceID = .penInteraction
  private(set) var discoveryTransactions: [DiscoverySequenceID: DiscoveryTransaction] = [:]
  private(set) var discoveryError: String?
  private(set) var drawingFramePosterior: DrawingFramePosterior?
  private(set) var boundaryFrameObservationsByAttemptID: [
    ExerciseAttemptID: DrawingFrameBoundaryObservation
  ] = [:]
  private(set) var explorationError: String?
  private(set) var currentExplorationEpisode: ExplorationEpisode?
  private(set) var completedExplorationEpisodes: [ExplorationEpisode] = []
  private(set) var armatureGuidanceState: ArmatureGuidanceState?
  private(set) var lastArmatureObservation: ArmaturePoseObservation?
  private(set) var explorationCleanReference: DisplayedFrame?
  private(set) var explorationAnchoredBaseline: DisplayedFrame?
  private(set) var explorationPostLineFrame: DisplayedFrame?
  private(set) var drawingTrialLineStart: MachinePosition?
  private(set) var drawingTrialStrokeEvidence: DrawingStrokeEvidence?
  private(set) var lastAnchorObservation: AnchorDotObservation?
  private(set) var lastInkObservation: IsolatedInkObservation?
  private(set) var explorationInkStatus = "no isolated-line observation yet"
  private(set) var explorationExportPath: String?
  private(set) var explorationOperationInProgress = false
  private(set) var lastAnnouncementResultText = "No announcement has run."
  private(set) var lastTravelFeedSelection: TravelFeedSelection?
  private(set) var drawingTrialAssessment: DrawingTrialAssessment?
  private(set) var clearViewPoseAccepted = false
  private(set) var learningArtifactGraph = LearningDependencyGraph()
  private(set) var penAttemptHistory: ExerciseAttemptHistory<PenState>
  private(set) var boundaryAttemptHistories: [
    BoundaryDirection: [AttemptCompatibility: ExerciseAttemptHistory<Double>]
  ] = [:]
  private(set) var clearViewAttemptHistories: [
    AttemptCompatibility: ExerciseAttemptHistory<ArmatureVisibilityLabel>
  ] = [:]
  private(set) var comparisonAttemptHistories: [
    AttemptCompatibility: ExerciseAttemptHistory<DrawingTrialAssessment>
  ] = [:]
  private(set) var activeExerciseAttemptID: ExerciseAttemptID?
  private(set) var activeExerciseAttemptOwnerID: LearningPathItemID?
  private(set) var restartableExerciseItemID: LearningPathItemID?

  @ObservationIgnored private let machineActions: MachineActions?
  @ObservationIgnored private let cameraActions: CameraActions?
  @ObservationIgnored private let announcementActions: AnnouncementActions?
  @ObservationIgnored private let serialDeviceDiscovery: @Sendable () -> [MachineLinkDescriptor]
  @ObservationIgnored private let persistSelectedSerialIdentifier: @Sendable (String) -> Void
  @ObservationIgnored private let nowNanoseconds: @Sendable () -> UInt64
  @ObservationIgnored private var frameTask: Task<Void, Never>?
  @ObservationIgnored private var visionUpdateTask: Task<Void, Never>?
  @ObservationIgnored private let learningEvidenceSessionID = LearningEvidenceSessionID()
  @ObservationIgnored private var controllerSessionID = UUID()
  @ObservationIgnored private var explorationCoordinateRevision: UInt64 = 0
  @ObservationIgnored private var explorationToolPaperRevision = UUID()
  @ObservationIgnored private var boundaryMotionTask: Task<Void, Never>?
  @ObservationIgnored private var manualJogTask: Task<MotionOutcome, Never>?
  @ObservationIgnored private var drawingTrialTask: Task<DrawingStrokeOutcome, Never>?
  @ObservationIgnored private var activeStopTarget: ContextualStopTarget?
  @ObservationIgnored private var stopRequestIssuedForTarget: ContextualStopTarget?
  @ObservationIgnored private var pendingDiscoveryInspection: LiveSceneInspection?
  @ObservationIgnored private var pendingDiscoveryCaptureBoundaryNanoseconds: UInt64?
  @ObservationIgnored private var rememberedSerialDeviceIdentifier: String?
  @ObservationIgnored private var hasShutdown = false
  @ObservationIgnored private var lifetimeGeneration: UInt64 = 0
  @ObservationIgnored private var activeHardwareIntentCount = 0
  @ObservationIgnored private var intentDrainWaiters: [CheckedContinuation<Void, Never>] = []
  @ObservationIgnored private var activeExerciseAttemptMode: ExerciseAttemptMode?
  @ObservationIgnored private var boundaryDerivedValueSnapshot: BoundaryDerivedValueSnapshot?
  @ObservationIgnored private var acceptedAttemptSequence: UInt64 = 0
  @ObservationIgnored private var currentDrawingTrialGroup = AttemptGroupIdentity(
    rawValue: UUID().uuidString.lowercased()
  )

  init(
    machineActions: MachineActions? = nil,
    cameraActions: CameraActions? = nil,
    announcementActions: AnnouncementActions? = nil,
    serialDevices: [MachineLinkDescriptor] = [],
    serialDeviceDiscovery: @escaping @Sendable () -> [MachineLinkDescriptor] = {
      SerialPortDiscovery.discover()
    },
    loadSelectedSerialIdentifier: @escaping @Sendable () -> String? = {
      UserDefaults.standard.string(forKey: "AdaptivePlotter.selectedSerialDeviceIdentifier")
    },
    persistSelectedSerialIdentifier: @escaping @Sendable (String) -> Void = { identifier in
      UserDefaults.standard.set(identifier, forKey: "AdaptivePlotter.selectedSerialDeviceIdentifier")
    },
    nowNanoseconds: @escaping @Sendable () -> UInt64 = {
      UInt64(ProcessInfo.processInfo.systemUptime * 1_000_000_000)
    }
  ) {
    penAttemptHistory = try! ExerciseAttemptHistory(
      compatibility: AttemptCompatibility(
        cameraConfigurationID: nil,
        coordinateSpace: .currentState,
        units: .state,
        group: AttemptGroupIdentity(rawValue: "pen-interaction"),
        algorithmRevision: "typed-operator-pen-observation-v1"
      )
    )
    self.machineActions = machineActions
    self.cameraActions = cameraActions
    self.announcementActions = announcementActions
    self.serialDevices = serialDevices
    self.serialDeviceDiscovery = serialDeviceDiscovery
    self.persistSelectedSerialIdentifier = persistSelectedSerialIdentifier
    rememberedSerialDeviceIdentifier = loadSelectedSerialIdentifier()
    self.nowNanoseconds = nowNanoseconds
    if let rememberedSerialDeviceIdentifier {
      selectedSerialDevice = serialDevices.first {
        $0.identifier == rememberedSerialDeviceIdentifier
      }
    }
  }

  var actionSurfacePresentation: ActionSurfacePresentation {
    let visibleKinds = Set(visibleLayers.map(\.overlayKind))
    return ActionSurfacePresentation(
      displayedFrame: displayedFrame,
      overlays: cameraOverlays.filter { visibleKinds.contains($0.provenance.kind) }
    )
  }

  var cameraDevices: [CameraDevice] { cameraSnapshot?.devices ?? [] }
  var selectedCameraID: CameraDeviceID? { cameraSnapshot?.selectedDeviceID }
  var isShutdown: Bool { hasShutdown }

  var cameraIsLive: Bool {
    guard frameMode == .live, case .running = cameraSnapshot?.state,
      let latestLiveCameraFrame, case .live(let deviceID) = latestLiveCameraFrame.source,
      deviceID == selectedCameraID
    else { return false }
    let now = nowNanoseconds()
    guard now >= latestLiveCameraFrame.frame.captureNanoseconds else { return false }
    return now - latestLiveCameraFrame.frame.captureNanoseconds <= 1_000_000_000
  }

  var controllerIsConnected: Bool {
    guard passiveProbeResult?.blockers.isEmpty == true,
      let machine = machineSnapshot?.machine,
      machine.connection == .connected,
      machine.controllerState?.isRecognized == true,
      machine.stickyAmbiguity == nil
    else { return false }
    return true
  }

  var cameraStateText: String {
    guard frameMode == .live else { return simulatorModelMode.rawValue.lowercased() }
    guard let state = cameraSnapshot?.state else { return "not started" }
    return switch state {
    case .stopped: "stopped"
    case .discovering: "discovering"
    case .ready: "ready"
    case .starting: "starting"
    case .running: "running"
    case .interrupted(let reason): "interrupted: \(reason)"
    case .failed(let error): "failed: \(error.actionableDescription)"
    }
  }

  var frameAgeText: String {
    guard let frame = displayedFrame?.frame else { return "no frame" }
    let now = nowNanoseconds()
    guard now >= frame.captureNanoseconds else { return "clock mismatch" }
    return String(format: "%.2f s", Double(now - frame.captureNanoseconds) / 1_000_000_000)
  }

  var sceneMeasurementText: String {
    guard let measurement = lastSceneMeasurement else { return "not measured" }
    let cap = measurement.cap.map {
      String(format: "cap %.0f px · %.2f", Double($0.pixelCount), $0.confidence)
    } ?? "cap not found"
    let top = measurement.topFrameSide.map {
      String(format: "top %.1f px · %.2f", $0.rmsResidualPixels, $0.confidence)
    } ?? "top not found"
    let right = measurement.rightFrameSide.map {
      String(format: "right %.1f px · %.2f", $0.rmsResidualPixels, $0.confidence)
    } ?? "right not found"
    let frame = measurement.drawingFrame.map {
      String(format: "frame inferred · %.2f", $0.confidence)
    } ?? "frame unavailable"
    let armature = measurement.armature.map {
      String(format: "armature inferred · %.2f", $0.confidence)
    } ?? "armature unavailable"
    return "\(cap) · \(top) · \(right) · \(frame) · \(armature)"
  }

  var captureThroughputText: String {
    let diagnostics = cameraSnapshot?.diagnostics ?? .zero
    return "received \(diagnostics.receivedFrameCount) · preview \(diagnostics.previewMaterializedFrameCount) · exact \(diagnostics.exactMaterializedFrameCount)"
  }

  var visionThroughputText: String {
    let snapshot = visionAnalysisSnapshot
    let cadence: String
    switch snapshot.state {
    case .stopped: cadence = "stopped"
    case .running(let value): cadence = "target \(value.rawValue) Hz"
    }
    let duration = snapshot.latestResult.map {
      String(format: "%.1f ms", Double($0.analysisDurationNanoseconds) / 1_000_000)
    } ?? "no timing"
    return "\(cadence) · analyzed \(snapshot.analyzedFrameCount) · superseded \(snapshot.supersededFrameCount) · \(duration)"
  }

  func overlaySummary(for layer: CanvasLayer) -> String {
    let matching = cameraOverlays.filter { $0.provenance.kind == layer.overlayKind }
    guard !matching.isEmpty else { return "not present on current frame" }
    let sources = Set(matching.map(\.provenance.source.rawValue)).sorted().joined(separator: ", ")
    return "\(matching.count) · \(sources)"
  }

  var currentOperationText: String {
    guard let operation = machineSnapshot?.currentOperation else { return "none" }
    return switch operation {
    case .idle: "idle"
    case .passiveProbe: "controller inspection"
    case .relativeJog: "relative jog"
    case .boundaryMotion: "Boundary Discovery motion"
    case .drawingStroke: "isolated drawing stroke"
    case .penActuation(let command): "pen \(command.rawValue)"
    }
  }

  var controllerStateText: String {
    machineSnapshot?.machine.controllerState?.rawValue ?? "unknown"
  }

  var controllerConnectionText: String {
    guard selectedSerialDevice != nil else { return "not selected" }
    if controllerIsConnected { return "connected" }
    guard let machine = machineSnapshot?.machine else { return "not connected" }
    switch machine.connection {
    case .connected:
      return passiveProbeInProgress ? "connecting" : "not connected"
    case .disconnected:
      return "disconnected"
    case .connecting:
      return "connecting"
    case .probing:
      return "probing"
    case .moving:
      return "command in flight"
    case .actuatingPen:
      return "pen command in flight"
    case .blocked:
      return "blocked"
    }
  }

  /// grblHAL status proves that its USB-side controller is responsive. The
  /// BlackBox does not report whether motor supply current is present, so the
  /// UI must not turn a responsive serial link into a powered-motors claim.
  var motorPowerText: String {
    guard machineSnapshot?.machine.connection == .connected else { return "unverified" }
    return "not reported by controller"
  }

  var motionPermissionText: String {
    motionUnavailableReason == nil ? "request eligible" : "blocked"
  }

  var motionGuardIsActive: Bool {
    controllerIsConnected && machineSnapshot?.machine.motionGuardState == .active
  }

  /// Drives the green top-bar badge. Session activation alone is not enough:
  /// green means an ordinary carriage request is eligible right now.
  var motionGuardAllowsCarriageMotion: Bool {
    motionGuardIsActive && motionUnavailableReason == nil
  }

  var motionGuardStateText: String {
    motionGuardIsActive ? "active" : "inactive"
  }

  var controllerSelectionUnavailableReason: String? {
    if serialDevices.isEmpty { return "No serial controllers are available." }
    if let activeDiscoverySequenceID {
      return "Finish \(DiscoverySequenceCatalog.definition(for: activeDiscoverySequenceID).title); use Stop while its logical owner is active."
    }
    if passiveProbeInProgress || jogRequestInProgress || penRequestInProgress
      || motionGuardActivationInProgress
    {
      return "Wait for the current controller operation."
    }
    return nil
  }

  var motionGuardActivationUnavailableReason: String? {
    if motionGuardActivationInProgress { return "Enable Motion is in progress." }
    if motionGuardIsActive { return "Motion is already enabled." }
    if !controllerIsConnected { return "Connect the selected plotter first." }
    guard let snapshot = machineSnapshot else {
      return MotionRefusal.notConnected.actionableDescription
    }
    let machine = snapshot.machine
    if let ambiguity = machine.stickyAmbiguity {
      return MotionRefusal.stickyAmbiguity(ambiguity).actionableDescription
    }
    if machine.operationInFlight || snapshot.currentOperation != .idle {
      return MotionRefusal.operationInFlight.actionableDescription
    }
    guard let controllerState = machine.controllerState, controllerState.isRecognized else {
      return MotionRefusal.controllerStateUnknown.actionableDescription
    }
    if controllerState.isAlarm {
      return MotionRefusal.controllerAlarm("controller is in Alarm").actionableDescription
    }
    if controllerState != .idle {
      return MotionRefusal.controllerNotIdle(controllerState).actionableDescription
    }
    if machine.pins.hasRelevantLimitAsserted {
      return MotionRefusal.relevantLimitAsserted(machine.pins.rawValue).actionableDescription
    }
    if machine.position == nil {
      return MotionRefusal.machinePositionUnknown.actionableDescription
    }
    return nil
  }

  var controllerConnectionActionTitle: String {
    controllerLinkIsOpen ? "Disconnect" : "Connect"
  }

  var controllerConnectionActionUnavailableReason: String? {
    if controllerConnectionActionInProgress {
      return "The controller connection action is already in progress."
    }
    if let activeDiscoverySequenceID {
      return "Finish \(DiscoverySequenceCatalog.definition(for: activeDiscoverySequenceID).title) first."
    }
    if passiveProbeInProgress || jogRequestInProgress || penRequestInProgress
      || jogCancelRequestInProgress || motionGuardActivationInProgress
      || explorationOperationInProgress
    {
      return "Wait for the current operation."
    }
    if controllerLinkIsOpen { return nil }
    return passiveProbeUnavailableReason
  }

  var frameModeSwitchUnavailableReason: String? {
    if frameModeSwitchInProgress { return "A frame source switch is already in progress." }
    if activeDiscoverySequenceID != nil {
      return "Finish the active Human-Guided Discovery transaction first."
    }
    if explorationOperationInProgress {
      return "Wait for the current learning action before changing frame source."
    }
    if passiveProbeInProgress || jogRequestInProgress || penRequestInProgress
      || jogCancelRequestInProgress || machineSnapshot?.machine.operationInFlight == true
    {
      return "Wait for the current controller operation before changing frame source."
    }
    return nil
  }

  private(set) var observedDrawingTrialStep: ObservedDrawingTrialStep = .captureCleanReference
  private(set) var pendingClearViewLabel: ArmatureVisibilityLabel?
  private(set) var selectedBoundaryDirection: BoundaryDirection = .positiveX

  var activeDiscoverySequenceID: DiscoverySequenceID? {
    discoveryTransactions.first { _, transaction in
      switch transaction.state {
      case .active, .cancelling: true
      case .notStarted, .succeeded, .failed, .cancelled: false
      }
    }?.key
  }

  var penInteractionCompleted: Bool {
    guard learningArtifactGraph.currentRevision(for: .penInteraction) != nil else { return false }
    return frameMode == .simulated
      ? simulatorPenState == .up
      : machineSnapshot?.machine.penState == .up
  }

  var relevantBoundaryObservationCount: Int {
    BoundaryDirection.allCases.filter {
      learningArtifactGraph.currentRevision(for: .boundaryObservation($0)) != nil
    }.count
  }

  var humanGuidedDiscoveryCurrentStep: HumanGuidedDiscoveryStep {
    if !penInteractionCompleted { return .penInteraction }
    if relevantBoundaryObservationCount == 0 { return .boundaryDiscovery }
    return .clearViewDiscovery
  }

  var currentLearningPathItemID: LearningPathItemID {
    if let activeExerciseAttemptOwnerID { return activeExerciseAttemptOwnerID }
    if let restartableExerciseItemID { return restartableExerciseItemID }
    if !controllerIsConnected { return .stage(.connect) }
    if !motionGuardIsActive { return .stage(.enableMotion) }
    if !penInteractionCompleted { return .humanGuidedDiscovery(.penInteraction) }
    if relevantBoundaryObservationCount == 0 {
      return .humanGuidedDiscovery(.boundaryDiscovery)
    }
    if !clearViewPoseAccepted { return .humanGuidedDiscovery(.clearViewDiscovery) }
    if drawingTrialAssessment == nil {
      return .observedDrawingTrial(observedDrawingTrialStep)
    }
    return .stage(.adaptiveDrawing)
  }

  var learningPathItemPresentations: [LearningPathItemPresentation] {
    LearningPathItemID.navigationOrder.map { itemID in
      LearningPathItemPresentation(
        id: itemID,
        status: learningPathStatus(for: itemID),
        summary: learningPathSummary(for: itemID),
        isRepeatable: itemIsRepeatable(itemID)
      )
    }
  }

  var contextualStopPresentation: ContextualStopPresentation? {
    guard let activeStopTarget else { return nil }
    if case .boundaryDiscovery(let transactionID, let direction) = activeStopTarget {
      let sequenceID = sequenceID(for: direction)
      guard discoveryTransactions[sequenceID]?.id == transactionID,
        case .awaitContextualStop(direction) = discoveryTransactions[sequenceID]?.currentStep?.action
      else { return nil }
    }
    let detail = switch activeStopTarget {
    case .boundaryDiscovery(_, let direction):
      "Stop \(direction.displayName) Boundary Discovery, wait for Idle, then observe its final position and a fresh frame."
    case .manualJog:
      "Stop the active manual jog and wait for Idle."
    case .drawingTrial:
      "Stop the drawing trial; the controller owns its single Pen Up cancellation."
    }
    return ContextualStopPresentation(detail: detail)
  }

  var currentExerciseActionStripPresentation: ExerciseActionStripPresentation? {
    exerciseActionStrip(for: currentLearningPathItemID)
  }

  func selectedOperatorActionPresentation(
    for itemID: LearningPathItemID
  ) -> OperatorActionPresentation {
    switch itemID {
    case .stage(let stage):
      return OperatorActionPresentation(
        itemID: itemID,
        stepNumber: stage.number,
        title: stage.title,
        status: learningPathStatus(for: itemID),
        instructions: [.text(learningPathSummary(for: itemID))],
        expectedObservation: stageExpectedObservation(stage),
        evidence: stageEvidence(stage),
        actionStrip: exerciseActionStrip(for: itemID)
      )

    case .humanGuidedDiscovery(let discoveryStep):
      let sequenceID = discoverySequenceID(for: discoveryStep)
      let transaction = sequenceID.flatMap { discoveryTransactions[$0] }
      let activeStep = transaction?.currentStep
      let feedSelection: TravelFeedSelection? = switch activeStep?.action {
      case .startBoundaryJog(let direction): travelFeedSelection(
        for: boundaryFeedVector(direction)
      )
      default: nil
      }
      return OperatorActionPresentation(
        itemID: itemID,
        stepNumber: discoveryStep.stepNumber,
        title: discoveryStep.title,
        status: learningPathStatus(for: itemID),
        participant: activeStep?.participant.displayName,
        instructions: activeStep.map { discoveryInstructionFragments($0.action) }
          ?? discoveryReviewInstructions(discoveryStep),
        expectedObservation: activeStep.map {
          discoveryExpectationFragments($0.expectedEvent)
        } ?? discoveryReviewExpectation(discoveryStep),
        question: activeStep.map { discoveryQuestionFragments($0.action) } ?? [],
        timeline: transaction.flatMap { transaction in
          guard transaction.state == .active, transaction.completedStepCount < transaction.definition.steps.count
          else { return nil }
          return ExerciseTimelinePresentation(
            position: transaction.completedStepCount + 1,
            total: transaction.definition.steps.count,
            currentLabel: transaction.currentStep?.id ?? discoveryStep.title
          )
        },
        evidence: discoveryEvidence(transaction),
        actionStrip: exerciseActionStrip(for: itemID),
        requestedFeedMMPerMinute: feedSelection?.requestedFeedMMPerMinute,
        feedSource: feedSelection?.source
      )

    case .observedDrawingTrial(let trialStep):
      return OperatorActionPresentation(
        itemID: itemID,
        stepNumber: trialStep.stepNumber,
        title: trialStep.title,
        status: learningPathStatus(for: itemID),
        participant: drawingTrialParticipant(for: trialStep),
        instructions: drawingTrialInstructionFragments(for: trialStep),
        expectedObservation: drawingTrialExpectationFragments(for: trialStep),
        timeline: ExerciseTimelinePresentation(
          position: trialStep.rawValue,
          total: ObservedDrawingTrialStep.allCases.count,
          currentLabel: observedDrawingTrialStep.title
        ),
        evidence: drawingTrialEvidence(for: trialStep),
        actionStrip: exerciseActionStrip(for: itemID),
        requestedFeedMMPerMinute: lastTravelFeedSelection?.requestedFeedMMPerMinute,
        feedSource: lastTravelFeedSelection?.source
      )
    }
  }

  func selectBoundaryDirection(_ direction: BoundaryDirection) {
    guard !hasShutdown, activeDiscoverySequenceID == nil else { return }
    selectedBoundaryDirection = direction
  }

  func performExerciseAction(
    _ kind: ExerciseActionKind,
    for ownerID: LearningPathItemID
  ) async {
    guard !hasShutdown,
      let strip = exerciseActionStrip(for: ownerID),
      strip.ownerID == ownerID,
      let action = strip.actions.first(where: { $0.kind == kind }),
      action.isEnabled
    else { return }

    switch kind {
    case .start:
      await startExercise(ownerID, mode: .normal)
    case .choice(let choice):
      guard ownerID == activeExerciseAttemptOwnerID else { return }
      await answerCurrentQuestion(choice)
    case .cancel:
      await cancelExerciseAttempt(ownerID)
    case .stop:
      guard ownerID == activeExerciseAttemptOwnerID else { return }
      await stopCurrentOperation()
    case .restart:
      guard restartableExerciseItemID == ownerID else { return }
      restartableExerciseItemID = nil
      await startExercise(ownerID, mode: .normal)
    case .redoThisStep:
      await startExercise(ownerID, mode: .replacement)
    case .recordAnotherAttempt:
      await startExercise(ownerID, mode: .additional)
    case .recordClearViewLabel(let label):
      guard ownerID == .humanGuidedDiscovery(.clearViewDiscovery) else { return }
      await recordClearViewLabel(label)
    case .acceptCurrentClearView:
      guard ownerID == .humanGuidedDiscovery(.clearViewDiscovery) else { return }
      await acceptCurrentClearViewPose()
    case .recordDrawingTrialAssessment(let assessment):
      guard ownerID == .observedDrawingTrial(.compareIntendedAndObservedGeometry) else { return }
      await recordDrawingTrialAssessment(assessment)
    }
  }

  func beginPenInteraction() async {
    guard discoveryStartUnavailableReason(for: .penInteraction) == nil else { return }
    beginExerciseAttempt(
      ownerID: .humanGuidedDiscovery(.penInteraction),
      mode: activeExerciseAttemptMode ?? .normal
    )
    await startDiscoverySequence(.penInteraction)
  }

  func beginBoundaryDiscovery(_ direction: BoundaryDirection) async {
    let sequenceID = sequenceID(for: direction)
    guard discoveryStartUnavailableReason(for: sequenceID) == nil else { return }
    selectedBoundaryDirection = direction
    beginExerciseAttempt(
      ownerID: .humanGuidedDiscovery(.boundaryDiscovery),
      mode: activeExerciseAttemptMode ?? .normal
    )
    await startDiscoverySequence(sequenceID)
  }

  func answerCurrentQuestion(_ choice: OperatorChoice) async {
    guard let sequenceID = activeDiscoverySequenceID else { return }
    await answerDiscoverySequence(choice, for: sequenceID)
  }

  func recordClearViewLabel(_ label: ArmatureVisibilityLabel) async {
    guard humanGuidedDiscoveryCurrentStep == .clearViewDiscovery else { return }
    if activeExerciseAttemptOwnerID == nil {
      beginExerciseAttempt(
        ownerID: .humanGuidedDiscovery(.clearViewDiscovery),
        mode: activeExerciseAttemptMode ?? .normal
      )
    }
    explorationError = nil
    do {
      let frame: DisplayedFrame
      let position: MachinePosition
      let armatureBounds: AxisAlignedBounds<CameraPixelSpace>?
      if frameMode == .simulated {
        guard let displayedFrame else { throw LearningPathOperationError.freshFrameUnavailable }
        frame = displayedFrame
        if let currentPosition = machineSnapshot?.machine.position {
          position = currentPosition
        } else {
          position = try MachinePosition(x: 0, y: 0)
        }
        armatureBounds = nil
      } else {
        guard let cameraActions, let currentPosition = machineSnapshot?.machine.position else {
          throw LearningPathOperationError.freshFrameUnavailable
        }
        guard let inspection = try await cameraActions.inspectScene(
          displayedFrame?.frame.captureNanoseconds ?? 0
        ) else { throw LearningPathOperationError.freshFrameUnavailable }
        frame = inspection.displayedFrame
        position = currentPosition
        armatureBounds = inspection.measurement.armature?.bounds
        displayedFrame = inspection.displayedFrame
        cameraOverlays = inspection.measurement.overlays
      }
      let context = armatureContext(
        frame: frame.frame,
        region: defaultInkRegion(for: frame.frame)
      )
      var guidance = armatureGuidanceState ?? ArmatureGuidanceState(context: context)
      guidance.updateContext(context)
      let observation = try guidance.record(
        frame: frame.frame,
        controllerPosition: position,
        armatureBounds: armatureBounds,
        humanLabel: label,
        outcome: .stopped
      )
      armatureGuidanceState = guidance
      lastArmatureObservation = observation
      pendingClearViewLabel = label
      if label != .clear {
        recordClearViewAttempt(
          label: nil,
          disposition: .unclear("Operator labelled the exact frame \(label.rawValue).")
        )
        finishActiveExerciseAttempt(
          disposition: .unclear("Operator labelled the exact frame \(label.rawValue).")
        )
      }
    } catch {
      explorationError = "Clear-View observation failed: \(error)"
      finishActiveExerciseAttempt(disposition: .failed(String(describing: error)))
    }
  }

  func acceptCurrentClearViewPose() async {
    guard pendingClearViewLabel == .clear,
      let observation = lastArmatureObservation,
      var guidance = armatureGuidanceState
    else { return }
    do {
      try guidance.acceptClearPose(
        observationID: observation.id,
        returnFeedMMPerMinute: positiveFallbackTravelFeed()
      )
      try commitClearViewAttemptAndArtifact(guidance: guidance)
      finishActiveExerciseAttempt(disposition: .succeeded)
    } catch {
      explorationError = "Clear-View acceptance failed: \(error)"
      recordClearViewAttempt(
        label: nil,
        disposition: .failed("Atomic accepted-artifact commit failed: \(error)")
      )
      finishActiveExerciseAttempt(disposition: .failed(String(describing: error)))
      restartableExerciseItemID = .humanGuidedDiscovery(.clearViewDiscovery)
    }
  }

  func performCurrentLearningPathAction() async {
    guard clearViewPoseAccepted, !explorationOperationInProgress else { return }
    let attemptedStep = observedDrawingTrialStep
    if activeExerciseAttemptOwnerID == nil {
      beginExerciseAttempt(
        ownerID: .observedDrawingTrial(attemptedStep),
        mode: activeExerciseAttemptMode ?? .normal
      )
    }
    let payloadSnapshot = drawingTrialPayloadSnapshot()
    explorationOperationInProgress = true
    explorationError = nil
    defer { explorationOperationInProgress = false }
    do {
      switch observedDrawingTrialStep {
      case .captureCleanReference:
        try await captureDrawingTrialCleanReference()
      case .chooseLineStart:
        try recordDrawingTrialLineStart()
      case .createAnchorMark:
        try await createDrawingTrialAnchor()
      case .drawIsolatedLine:
        try await drawIsolatedTrialLine()
      case .clearToolAndObserveInk:
        try await clearToolAndObserveTrialInk()
      case .compareIntendedAndObservedGeometry:
        break
      }
      if attemptedStep != .compareIntendedAndObservedGeometry {
        try commitDrawingArtifact(for: attemptedStep)
        advanceDrawingTrialAfterSuccess(attemptedStep)
        finishActiveExerciseAttempt(disposition: .succeeded)
      }
    } catch {
      restoreDrawingTrialPayload(payloadSnapshot)
      explorationError = "\(attemptedStep.title) failed: \(error)"
      let disposition = attemptDisposition(for: String(describing: error))
      finishActiveExerciseAttempt(disposition: disposition)
      restartableExerciseItemID = .observedDrawingTrial(attemptedStep)
    }
  }

  func recordDrawingTrialAssessment(_ assessment: DrawingTrialAssessment) async {
    guard observedDrawingTrialStep == .compareIntendedAndObservedGeometry else { return }
    if activeExerciseAttemptOwnerID == nil {
      beginExerciseAttempt(
        ownerID: .observedDrawingTrial(.compareIntendedAndObservedGeometry),
        mode: activeExerciseAttemptMode ?? .normal
      )
    }
    let payloadSnapshot = drawingTrialPayloadSnapshot()
    do {
      var episode = currentExplorationEpisode
      episode?.humanAssessment = ExplorationAssessment(
        summary: assessment.title,
        provenance: "typed local operator comparison"
      )
      episode?.termination = .completed
      try commitComparisonAttemptAndArtifact(assessment)
      drawingTrialAssessment = assessment
      currentExplorationEpisode = episode
      if let episode { completedExplorationEpisodes.append(episode) }
      finishActiveExerciseAttempt(disposition: .succeeded)
    } catch {
      restoreDrawingTrialPayload(payloadSnapshot)
      explorationError = "Comparison failed: \(error)"
      recordComparisonAttempt(
        assessment: nil,
        disposition: .failed("Atomic accepted-artifact commit failed: \(error)")
      )
      finishActiveExerciseAttempt(disposition: .failed(String(describing: error)))
      restartableExerciseItemID = .observedDrawingTrial(.compareIntendedAndObservedGeometry)
    }
  }

  var drawingFramePosteriorText: String {
    guard let posterior = drawingFramePosterior else { return "no boundary posterior yet" }
    let completion = posterior.estimate == nil ? "partial image-space sides" : "four-side intersections"
    return "\(posterior.observationCount) exact-frame observations · \(posterior.sidePosteriors.count) associated sides · \(completion)"
  }

  func discoveryStartUnavailableReason(for sequenceID: DiscoverySequenceID) -> String? {
    if let activeDiscoverySequenceID {
      return "Finish \(DiscoverySequenceCatalog.definition(for: activeDiscoverySequenceID).title); use Stop while its logical owner is active."
    }
    if frameMode == .simulated {
      return displayedFrame?.source == .simulated
        ? nil : "The simulator has no rendered frame."
    }
    if !motionGuardIsActive { return "Connect the plotter and Enable Motion first." }
    if frameMode != .live || !cameraIsLive {
      return "A current LIVE camera frame is required for Human-Guided Discovery."
    }
    switch sequenceID {
    case .boundaryNegativeX, .boundaryPositiveX, .boundaryNegativeY, .boundaryPositiveY:
      return directCarriageMotionUnavailableReason
    case .penInteraction:
      return penUnavailableReason(for: .lower)
    }
  }

  func boundaryPositionText(for direction: JogDirection) -> String {
    guard let position = boundaryPositions[direction] else { return "not measured" }
    return String(format: "X %.3f Y %.3f", position.point.x, position.point.y)
  }

  var workbenchStatusText: String {
    if let actionableError { return actionableError }
    if !controllerIsConnected { return "Select the remembered controller and press Connect." }
    if !motionGuardIsActive {
      return "Plotter connected. Enable Motion before this action."
    }
    if machineSnapshot?.machine.penState != .up {
      return "Motion enabled. Raise the pen so the commanded state is Up before carriage travel."
    }
    return "Motion enabled; carriage motion is available."
  }

  var workbenchStatusNeedsAttention: Bool {
    actionableError != nil
  }

  var machinePositionText: String {
    guard let point = machineSnapshot?.machine.position?.point else { return "unknown" }
    return String(format: "X %.3f   Y %.3f", point.x, point.y)
  }

  var penStateText: String {
    switch machineSnapshot?.machine.penState ?? .unknown {
    case .unknown:
      "unknown — no physical pose assumed"
    case .up:
      "commanded up — not visually observed"
    case .down:
      "commanded down — not visually observed"
    }
  }

  var lastMotionOutcomeText: String {
    guard let outcome = machineSnapshot?.lastMotionOutcome else { return "none" }
    switch outcome {
    case .refused(let reason):
      return "refused: \(reason.actionableDescription)"
    case .acceptedThenCompleted(let finalPosition):
      return String(
        format: "completed at X %.3f Y %.3f",
        finalPosition.point.x,
        finalPosition.point.y
      )
    case .cancelled(let finalPosition):
      return String(
        format: "cancelled at X %.3f Y %.3f",
        finalPosition.point.x,
        finalPosition.point.y
      )
    case .ambiguous(let ambiguity):
      return "ambiguous: \(ambiguity.actionableDescription)"
    }
  }

  var lastPenOutcomeText: String {
    guard let outcome = machineSnapshot?.lastPenOutcome else { return "none" }
    switch outcome {
    case .refused(let reason):
      return "refused: \(reason.actionableDescription)"
    case .commandedAndSettled(let command, let commandedState):
      return "\(command.rawValue) acknowledged; commanded \(commandedState.rawValue)"
    case .ambiguous(let ambiguity):
      return "ambiguous: \(ambiguity.actionableDescription)"
    }
  }

  var actionableError: String? {
    if let cameraError { return cameraError }
    if let visionError { return visionError }
    if let machineError { return machineError }
    if let blocker = machineSnapshot?.machine.blockers.first {
      return machineBlockerLabel(blocker)
    }
    if case .refused(let refusal) = machineSnapshot?.lastMotionOutcome {
      return refusal.actionableDescription
    }
    if case .ambiguous(let ambiguity) = machineSnapshot?.lastMotionOutcome {
      return ambiguity.actionableDescription
    }
    if case .refused(let refusal) = machineSnapshot?.lastPenOutcome {
      return refusal.actionableDescription
    }
    if case .ambiguous(let ambiguity) = machineSnapshot?.lastPenOutcome {
      return ambiguity.actionableDescription
    }
    return nil
  }

  var passiveProbeUnavailableReason: String? {
    if passiveProbeInProgress { return "Controller connection inspection is already in progress." }
    if frameModeSwitchInProgress { return "Wait for the frame source switch to finish." }
    if machineActions == nil { return "Native machine composition is unavailable." }
    if selectedSerialDevice == nil { return "Select one serial device first." }
    return nil
  }

  /// Presentation availability only. MachineController repeats every physical
  /// safety check when it receives the typed request.
  var motionUnavailableReason: String? {
    if let reason = directCarriageMotionUnavailableReason { return reason }
    guard let xStep = inputNumber(xStepText), let yStep = inputNumber(yStepText),
      let feed = inputNumber(feedText)
    else { return "Enter numeric X step, Y step, and feed values." }
    guard xStep > 0, yStep > 0 else {
      return "X and Y step magnitudes must be greater than zero."
    }
    guard feed > 0 else { return "Feed must be greater than zero." }
    return nil
  }

  private var directCarriageMotionUnavailableReason: String? {
    if jogRequestInProgress { return "A relative jog is already in progress." }
    if frameModeSwitchInProgress { return "Wait for the frame source switch to finish." }
    if frameMode == .simulated {
      return "SIMULATED source cannot issue physical machine commands. Switch to LIVE first."
    }
    if machineActions == nil { return "Native machine composition is unavailable." }
    if selectedSerialDevice == nil { return "Select and connect one serial device." }
    guard let snapshot = machineSnapshot else {
      return MotionRefusal.notConnected.actionableDescription
    }
    let machine = snapshot.machine
    if let ambiguity = machine.stickyAmbiguity {
      return MotionRefusal.stickyAmbiguity(ambiguity).actionableDescription
    }
    if machine.operationInFlight || snapshot.currentOperation != .idle {
      return MotionRefusal.operationInFlight.actionableDescription
    }
    if machine.connection != .connected {
      return MotionRefusal.notConnected.actionableDescription
    }
    guard let controllerState = machine.controllerState, controllerState.isRecognized else {
      return MotionRefusal.controllerStateUnknown.actionableDescription
    }
    if controllerState.isAlarm {
      return MotionRefusal.controllerAlarm("controller is in Alarm").actionableDescription
    }
    if controllerState != .idle {
      return MotionRefusal.controllerNotIdle(controllerState).actionableDescription
    }
    if machine.pins.hasRelevantLimitAsserted {
      return MotionRefusal.relevantLimitAsserted(machine.pins.rawValue).actionableDescription
    }
    if machine.position == nil {
      return MotionRefusal.machinePositionUnknown.actionableDescription
    }
    if machine.motionGuardState != .active {
      return MotionRefusal.motionGuardInactive.actionableDescription
    }
    if machine.penState != .up {
      return MotionRefusal.penNotUp(machine.penState).actionableDescription
    }
    return nil
  }

  func penUnavailableReason(for command: PenCommand) -> String? {
    if penRequestInProgress { return "A pen command is already in progress." }
    if frameModeSwitchInProgress { return "Wait for the frame source switch to finish." }
    if frameMode == .simulated {
      return "SIMULATED source cannot issue physical machine commands. Switch to LIVE first."
    }
    if machineActions == nil { return "Native machine composition is unavailable." }
    if selectedSerialDevice == nil { return "Select and connect one serial device." }
    guard let snapshot = machineSnapshot else {
      return PenRefusal.notConnected.actionableDescription
    }
    let machine = snapshot.machine
    if let ambiguity = machine.stickyAmbiguity {
      return PenRefusal.stickyAmbiguity(ambiguity).actionableDescription
    }
    if machine.operationInFlight || snapshot.currentOperation != .idle {
      return PenRefusal.operationInFlight.actionableDescription
    }
    if machine.connection != .connected {
      return PenRefusal.notConnected.actionableDescription
    }
    if machine.motionGuardState != .active {
      return PenRefusal.motionGuardInactive.actionableDescription
    }
    guard let controllerState = machine.controllerState, controllerState.isRecognized else {
      return PenRefusal.controllerStateUnknown.actionableDescription
    }
    if controllerState.isAlarm {
      return PenRefusal.controllerAlarm("controller is in Alarm").actionableDescription
    }
    if controllerState != .idle {
      return PenRefusal.controllerNotIdle(controllerState).actionableDescription
    }
    guard command == .lower else { return nil }
    if machine.pins.hasRelevantLimitAsserted {
      return PenRefusal.relevantLimitAsserted(machine.pins.rawValue).actionableDescription
    }
    guard machine.position != nil else {
      return PenRefusal.machinePositionUnknown.actionableDescription
    }
    return nil
  }

  func setLayer(_ layer: CanvasLayer, visible: Bool) {
    guard !hasShutdown else { return }
    if visible {
      visibleLayers.insert(layer)
    } else {
      visibleLayers.remove(layer)
    }
  }

  func refreshSerialDevices() async {
    guard let generation = beginHardwareIntent() else { return }
    defer { endHardwareIntent() }
    guard !passiveProbeInProgress && !jogRequestInProgress && !penRequestInProgress else { return }
    let discovered = serialDeviceDiscovery()
    if let selectedSerialDevice,
      !discovered.contains(where: { $0.identifier == selectedSerialDevice.identifier })
    {
      await machineActions?.disconnect()
      guard canCommit(generation) else { return }
      await clearMachineAuthority(clearSelection: true)
    }
    guard canCommit(generation) else { return }
    serialDevices = discovered
    if selectedSerialDevice == nil, let rememberedSerialDeviceIdentifier {
      selectedSerialDevice = discovered.first {
        $0.identifier == rememberedSerialDeviceIdentifier
      }
    }
  }

  func disconnectMachineSession() async {
    guard let generation = beginHardwareIntent() else { return }
    defer { endHardwareIntent() }
    guard selectedSerialDevice != nil, !passiveProbeInProgress, !jogRequestInProgress,
      !penRequestInProgress
    else { return }
    await machineActions?.disconnect()
    guard canCommit(generation) else { return }
    await clearMachineAuthority(clearSelection: false)
  }

  func performControllerConnectionAction() async {
    guard controllerConnectionActionUnavailableReason == nil else { return }
    controllerConnectionActionInProgress = true
    defer { controllerConnectionActionInProgress = false }
    if controllerLinkIsOpen {
      await disconnectMachineSession()
    } else {
      await connectSelectedController()
    }
  }

  /// Updates only the operator's pending device choice. A picker change is not
  /// a successful connection and cannot turn the status indicator green.
  func selectSerialDevice(_ descriptor: MachineLinkDescriptor) async {
    guard let generation = beginHardwareIntent() else { return }
    defer { endHardwareIntent() }
    guard activeDiscoverySequenceID == nil, !explorationOperationInProgress else { return }
    guard !passiveProbeInProgress && !jogRequestInProgress && !penRequestInProgress else { return }
    guard serialDevices.contains(where: { $0.identifier == descriptor.identifier }) else { return }
    if selectedSerialDevice?.identifier != descriptor.identifier, machineSnapshot != nil {
      await machineActions?.disconnect()
      guard canCommit(generation) else { return }
      await clearMachineAuthority(clearSelection: false)
    }
    guard canCommit(generation) else { return }
    selectedSerialDevice = descriptor
    rememberedSerialDeviceIdentifier = descriptor.identifier
    persistSelectedSerialIdentifier(descriptor.identifier)
  }

  /// Test/support entrypoint for establishing the same selected-device session
  /// without asserting that its passive inspection succeeded.
  func establishMachineSession(_ descriptor: MachineLinkDescriptor) async {
    await selectSerialDevice(descriptor)
    await openSelectedMachineSession()
  }

  func connectSelectedController() async {
    guard selectedSerialDevice != nil else { return }
    await openSelectedMachineSession()
    guard machineError == nil, machineSnapshot != nil else { return }
    await requestPassiveProbe()
  }

  private func openSelectedMachineSession() async {
    guard let descriptor = selectedSerialDevice else { return }
    guard let generation = beginHardwareIntent() else { return }
    defer { endHardwareIntent() }
    guard !passiveProbeInProgress && !jogRequestInProgress && !penRequestInProgress else { return }
    guard let machineActions else {
      machineError = "Native machine composition is unavailable."
      return
    }
    machineError = nil
    do {
      let snapshot = try await machineActions.select(descriptor)
      guard canCommit(generation) else { return }
      machineSnapshot = snapshot
      passiveProbeResult = nil
      lastMotionGuardActivationText = "not activated"
    } catch {
      guard canCommit(generation) else { return }
      machineError = actionableDescription(error)
      machineSnapshot = nil
      passiveProbeResult = nil
    }
  }

  func requestPassiveProbe() async {
    guard let generation = beginHardwareIntent() else { return }
    defer { endHardwareIntent() }
    guard passiveProbeUnavailableReason == nil, let machineActions else { return }
    passiveProbeInProgress = true
    machineError = nil
    passiveProbeResult = nil
    defer { passiveProbeInProgress = false }
    let operation = Task { try await machineActions.requestPassiveProbe() }
    await Task.yield()
    let interimSnapshot = await machineActions.snapshot()
    if canCommit(generation) { machineSnapshot = interimSnapshot }
    do {
      let result = try await operation.value
      let finalSnapshot = await machineActions.snapshot()
      guard canCommit(generation) else { return }
      passiveProbeResult = result
      machineSnapshot = finalSnapshot
    } catch {
      let finalSnapshot = await machineActions.snapshot()
      guard canCommit(generation) else { return }
      machineError = actionableDescription(error)
      machineSnapshot = finalSnapshot
    }
  }

  func requestPenActuation(_ command: PenCommand) async {
    guard let generation = beginHardwareIntent() else { return }
    defer { endHardwareIntent() }
    guard penUnavailableReason(for: command) == nil, let machineActions else { return }
    penRequestInProgress = true
    machineError = nil
    defer { penRequestInProgress = false }
    let operation = Task { await machineActions.requestPenActuation(command) }
    await Task.yield()
    let interimSnapshot = await machineActions.snapshot()
    if canCommit(generation) { machineSnapshot = interimSnapshot }
    _ = await operation.value
    let snapshot = await machineActions.snapshot()
    guard canCommit(generation) else { return }
    machineSnapshot = snapshot
  }

  func startDiscoverySequence(_ sequenceID: DiscoverySequenceID) async {
    guard discoveryStartUnavailableReason(for: sequenceID) == nil else { return }
    if activeExerciseAttemptOwnerID == nil {
      beginExerciseAttempt(
        ownerID: learningPathItemID(for: sequenceID),
        mode: .normal
      )
    }
    selectedDiscoverySequenceID = sequenceID
    discoveryError = nil
    pendingDiscoveryInspection = nil
    pendingDiscoveryCaptureBoundaryNanoseconds = nil
    var transaction = DiscoveryTransaction(sequenceID: sequenceID)
    do {
      try transaction.begin()
      discoveryTransactions[sequenceID] = transaction
      await advanceDiscoverySequence(sequenceID)
    } catch {
      discoveryError = "Human-Guided Discovery could not start: \(error)"
      recordDiscoveryAttempt(
        sequenceID: sequenceID,
        disposition: .failed(String(describing: error))
      )
      finishActiveExerciseAttempt(disposition: .failed(String(describing: error)))
      restartableExerciseItemID = learningPathItemID(for: sequenceID)
    }
  }

  private func advanceDiscoverySequence(_ sequenceID: DiscoverySequenceID) async {
    while !hasShutdown, activeDiscoverySequenceID == sequenceID,
      let step = discoveryTransactions[sequenceID]?.currentStep
    {
      switch step.action {
      case .askQuestion:
        guard recordDiscovery(.questionPresented, for: sequenceID) else { return }

      case .awaitOperatorChoice:
        if let direction = jogDirection(for: sequenceID), case .idle = boundaryTeachingState {
          boundaryTeachingState = .awaitingConfirmation(direction)
          boundaryTeachingResultText =
            "\(direction.shortLabel) armed. Answer YES to start; answer NO to wait."
        }
        return

      case .awaitPhysicalPenConfirmation:
        return

      case .announce(let message):
        _ = await announceAdvisory(message)
        guard activeDiscoverySequenceID == sequenceID,
          discoveryTransactions[sequenceID]?.currentStep?.id == step.id
        else { return }
        guard recordDiscovery(.announcementCompleted, for: sequenceID) else { return }

      case .startBoundaryJog(let direction):
        guard boundaryMotionTask == nil else { return }
        let jogDirection = jogDirection(from: direction)
        boundaryMotionTask = Task { [weak self] in
          guard let self else { return }
          await self.executeBoundaryMotion(jogDirection)
          self.boundaryMotionTask = nil
        }
        return

      case .awaitContextualStop:
        return

      case .cancelBoundaryJogAndAwaitIdle:
        // `stopCurrentOperation()` owns the one cancel byte and then awaits the
        // original boundary-motion task. The motion owner records final MPos.
        return

      case .actuatePen(let command):
        await requestPenActuation(command)
        guard case .commandedAndSettled = machineSnapshot?.lastPenOutcome else {
          await failDiscovery(sequenceID, reason: lastPenOutcomeText)
          return
        }
        guard recordDiscovery(
          .penCommandSettled(command, controllerSummary: lastPenOutcomeText),
          for: sequenceID
        ) else { return }
        pendingDiscoveryCaptureBoundaryNanoseconds = nowNanoseconds()

      case .captureFreshCameraFrame:
        guard await captureDiscoveryInspection(sequenceID) else { return }

      case .measureBoundary(let direction):
        guard let inspection = pendingDiscoveryInspection,
          let estimate = inspection.measurement.drawingFrame,
          let controllerPosition = boundaryPositions[jogDirection(from: direction)],
          let observedToolCentroid = inspection.measurement.cap?.centroid
        else {
          await failDiscovery(
            sequenceID,
            reason:
              "Boundary Discovery requires final controller MPos, the observed tool centroid, and a drawing-frame estimate on the exact fresh frame."
          )
          return
        }
        let measurement = inspection.measurement
        let summary =
          "controller boundary paired with the observed tool centroid and visible frame sides; unobserved sides remain inferred"
        guard recordDiscovery(
          .boundaryMeasured(
            direction,
            controllerPosition: controllerPosition,
            observedToolCentroid: observedToolCentroid,
            frameID: measurement.frameID,
            cameraConfigurationID: measurement.cameraConfigurationID,
            confidence: estimate.confidence,
            summary: summary
          ),
          for: sequenceID
        ) else { return }

      case .adjustDrawingFramePosterior(let direction):
        guard updateDrawingFramePosterior(direction: direction, sequenceID: sequenceID) else {
          return
        }
      }
    }
  }

  private func captureDiscoveryInspection(_ sequenceID: DiscoverySequenceID) async -> Bool {
    guard let cameraActions else {
      await failDiscovery(sequenceID, reason: "Native camera composition is unavailable.")
      return false
    }
    guard let captureBoundary = pendingDiscoveryCaptureBoundaryNanoseconds else {
      await failDiscovery(
        sequenceID,
        reason: "No controller or operator event boundary is available for a fresh frame."
      )
      return false
    }
    do {
      guard let inspection = try await cameraActions.inspectScene(captureBoundary) else {
        await failDiscovery(
          sequenceID,
          reason: "No live frame newer than the completed discovery event is available."
        )
        return false
      }
      guard inspection.displayedFrame.frame.captureNanoseconds > captureBoundary else {
        await failDiscovery(
          sequenceID,
          reason: "Camera returned a frame that predates the completed discovery event."
        )
        return false
      }
      pendingDiscoveryInspection = inspection
      pendingDiscoveryCaptureBoundaryNanoseconds = nil
      displayedFrame = inspection.displayedFrame
      latestLiveCameraFrame = inspection.displayedFrame
      lastSceneMeasurement = inspection.measurement
      cameraOverlays = inspection.measurement.overlays
      return recordDiscovery(
        .freshFrameCaptured(
          inspection.measurement.frameID,
          inspection.measurement.cameraConfigurationID
        ),
        for: sequenceID
      )
    } catch {
      await failDiscovery(sequenceID, reason: actionableDescription(error))
      return false
    }
  }

  private func updateDrawingFramePosterior(
    direction: BoundaryDirection,
    sequenceID: DiscoverySequenceID
  ) -> Bool {
    guard let inspection = pendingDiscoveryInspection,
      let estimate = inspection.measurement.drawingFrame,
      let controllerPosition = boundaryPositions[jogDirection(from: direction)],
      let observedToolCentroid = inspection.measurement.cap?.centroid
    else {
      discoveryError =
        "Posterior adjustment requires final controller MPos, exact-frame tool centroid, and drawing-frame geometry."
      return false
    }
    do {
      let measurement = inspection.measurement
      let observation = try DrawingFrameBoundaryObservation(
        frameID: measurement.frameID,
        frameSHA256: measurement.frameSHA256,
        captureNanoseconds: inspection.displayedFrame.frame.captureNanoseconds,
        cameraConfigurationID: measurement.cameraConfigurationID,
        direction: direction,
        controllerPosition: controllerPosition,
        observedToolCentroid: observedToolCentroid,
        estimate: estimate,
        observationVariance: max(1, (1 - estimate.confidence) * 100),
        associationDistanceMargin: 8,
        broadPriorVariance: 400
      )
      guard let attemptID = activeExerciseAttemptID else {
        throw LearningPathOperationError.requiredState("No active typed boundary attempt.")
      }
      var stagedObservations = boundaryFrameObservationsByAttemptID
      stagedObservations[attemptID] = observation
      var includedAttemptIDs = Set(
        boundaryAttemptHistories.values.flatMap { histories in
          histories.values
            .filter {
              $0.compatibility.cameraConfigurationID == measurement.cameraConfigurationID
                && $0.compatibility.coordinateSpace == .machine
                && $0.compatibility.units == .millimeters
                && $0.compatibility.algorithmRevision == "boundary-side-posterior-v1"
            }
            .flatMap(\.includedSuccessfulAttempts)
            .map(\.id)
        }
      )
      if activeExerciseAttemptMode == .replacement,
        let replacedAttemptID = learningArtifactGraph.currentRevision(
          for: .boundaryObservation(direction)
        )?.attemptID
      {
        includedAttemptIDs.remove(replacedAttemptID)
      }
      includedAttemptIDs.insert(attemptID)
      let includedObservations: [DrawingFrameBoundaryObservation] = stagedObservations.compactMap {
        entry in
        let (id, candidate) = entry
        guard includedAttemptIDs.contains(id),
          candidate.key.cameraConfigurationID == measurement.cameraConfigurationID
        else { return nil }
        return candidate
      }
      guard let first = includedObservations.first else {
        throw LearningPathOperationError.requiredState(
          "No compatible accepted boundary observation is available for the posterior."
        )
      }
      var stagedPosterior = try DrawingFramePosterior(prior: first)
      for candidate in includedObservations where candidate.key != first.key
        && candidate.key != observation.key
      {
        stagedPosterior = try stagedPosterior.adding(candidate)
      }
      stagedPosterior = try stagedPosterior.adding(observation)
      boundaryFrameObservationsByAttemptID = stagedObservations
      drawingFramePosterior = stagedPosterior
      guard let drawingFramePosterior else { return false }
      cameraOverlays.removeAll { $0.provenance.kind == .drawingFrameEstimate }
      let posteriorGeometries: [Polyline<CameraPixelSpace>] =
        if let closedEstimate = drawingFramePosterior.estimate {
          [closedEstimate.geometry]
        } else {
          drawingFramePosterior.sidePosteriors
            .sorted { $0.key.rawValue < $1.key.rawValue }
            .map(\.value.geometry)
        }
      cameraOverlays.append(contentsOf: posteriorGeometries.map { geometry in
        CameraOverlayMeasurement(
          frameID: measurement.frameID,
          cameraConfigurationID: measurement.cameraConfigurationID,
          geometry: .polyline(geometry),
          provenance: CameraMeasurementProvenance(
            kind: .drawingFrameEstimate,
            source: .inferred,
            algorithmRevision: "human-guided-discovery-posterior-v1"
          )
        )
      })
      return recordDiscovery(
        .drawingFramePosteriorAdjusted(
          direction,
          frameID: measurement.frameID,
          cameraConfigurationID: measurement.cameraConfigurationID,
          observationCount: drawingFramePosterior.observationCount
        ),
        for: sequenceID
      )
    } catch {
      discoveryError = "Drawing-frame posterior update failed: \(error)"
      if var transaction = discoveryTransactions[sequenceID] {
        transaction.fail(discoveryError ?? "Drawing-frame posterior update failed.")
        discoveryTransactions[sequenceID] = transaction
      }
      return false
    }
  }

  private func recordDiscovery(_ event: DiscoveryEvent, for sequenceID: DiscoverySequenceID) -> Bool {
    guard var transaction = discoveryTransactions[sequenceID] else { return false }
    do {
      try transaction.record(event)
      discoveryTransactions[sequenceID] = transaction
      if transaction.state == .succeeded {
        commitSuccessfulDiscoveryAttempt(sequenceID)
      }
      return true
    } catch {
      transaction.fail("Unexpected discovery event: \(error)")
      discoveryTransactions[sequenceID] = transaction
      discoveryError = "Unexpected Human-Guided Discovery event: \(error)"
      return false
    }
  }

  private func failDiscovery(_ sequenceID: DiscoverySequenceID, reason: String) async {
    if var transaction = discoveryTransactions[sequenceID] {
      transaction.fail(reason)
      discoveryTransactions[sequenceID] = transaction
    }
    discoveryError = reason
    let disposition = attemptDisposition(for: reason)
    recordDiscoveryAttempt(sequenceID: sequenceID, disposition: disposition)
    finishActiveExerciseAttempt(disposition: disposition)
    restartableExerciseItemID = learningPathItemID(for: sequenceID)
    boundaryTeachingState = .idle
    pendingDiscoveryInspection = nil
    pendingDiscoveryCaptureBoundaryNanoseconds = nil
    activeStopTarget = nil
    stopRequestIssuedForTarget = nil
    boundaryTeachingResultText = "Discovery stopped: \(reason)"
  }

  func stopCurrentOperation() async {
    guard !jogCancelRequestInProgress, let target = activeStopTarget else { return }
    switch target {
    case .boundaryDiscovery(let transactionID, let direction):
      let sequenceID = sequenceID(for: direction)
      guard discoveryTransactions[sequenceID]?.id == transactionID,
        case .awaitContextualStop(direction) = discoveryTransactions[sequenceID]?.currentStep?.action
      else { return }
      guard recordDiscovery(.operatorStopRequested(direction), for: sequenceID) else { return }
      boundaryTeachingState = .cancelling(jogDirection(from: direction))
      boundaryTeachingResultText = "Stop requested. Waiting for the original motion owner to reach Idle."
      let owner = boundaryMotionTask
      await requestSingleJogCancel(for: target, intent: .operatorStop)
      await owner?.value

    case .manualJog:
      let owner = manualJogTask
      await requestSingleJogCancel(for: target, intent: .operatorStop)
      _ = await owner?.value

    case .drawingTrial:
      let owner = drawingTrialTask
      await requestSingleJogCancel(for: target, intent: .operatorStop)
      _ = await owner?.value
      finishActiveExerciseAttempt(disposition: .cancelled)
      restartableExerciseItemID = .observedDrawingTrial(.drawIsolatedLine)
    }
  }

  private func requestSingleJogCancel(
    for target: ContextualStopTarget,
    intent: JogCancelIntent
  ) async {
    guard let generation = beginHardwareIntent(), let machineActions else { return }
    defer { endHardwareIntent() }
    guard !jogCancelRequestInProgress, stopRequestIssuedForTarget != target else { return }
    stopRequestIssuedForTarget = target
    jogCancelRequestInProgress = true
    defer { jogCancelRequestInProgress = false }
    _ = await machineActions.requestJogCancel(intent)
    let snapshot = await machineActions.snapshot()
    guard canCommit(generation) else { return }
    machineSnapshot = snapshot
  }

  func activateMotionGuard() async {
    guard let generation = beginHardwareIntent() else { return }
    defer { endHardwareIntent() }
    guard motionGuardActivationUnavailableReason == nil, let machineActions else { return }
    motionGuardActivationInProgress = true
    machineError = nil
    defer { motionGuardActivationInProgress = false }
    let outcome = await machineActions.activateMotionGuard()
    let snapshot = await machineActions.snapshot()
    guard canCommit(generation) else { return }
    machineSnapshot = snapshot
    switch outcome {
    case .activated:
      lastMotionGuardActivationText = "activated for this controller session"
    case .refused(let refusal):
      lastMotionGuardActivationText = "refused: \(refusal.actionableDescription)"
      machineError = refusal.actionableDescription
    }
  }

  func requestJog(_ direction: JogDirection) async {
    guard motionUnavailableReason == nil,
      let xStep = inputNumber(xStepText),
      let yStep = inputNumber(yStepText),
      let feed = inputNumber(feedText),
      xStep > 0,
      yStep > 0
    else { return }

    do {
      let delta: Vector2<MachineSpace>
      switch direction {
      case .xNegative: delta = try Vector2(dx: -xStep, dy: 0)
      case .xPositive: delta = try Vector2(dx: xStep, dy: 0)
      case .yNegative: delta = try Vector2(dx: 0, dy: -yStep)
      case .yPositive: delta = try Vector2(dx: 0, dy: yStep)
      }
      let request = RelativeJogRequest(delta: delta, feedMMPerMinute: feed)
      await requestRelativeJog(request)
    } catch {
      machineError = actionableDescription(error)
    }
  }

  /// Routes an already typed relative-jog intent through the same presentation
  /// and runtime boundary as a button press. Callers cannot supply controller
  /// commands or bypass MachineController validation.
  @discardableResult
  func requestRelativeJog(_ request: RelativeJogRequest) async -> MotionOutcome? {
    guard let generation = beginHardwareIntent() else { return nil }
    defer { endHardwareIntent() }
    guard motionUnavailableReason == nil, !jogRequestInProgress, let machineActions else {
      return nil
    }

    jogRequestInProgress = true
    machineError = nil
    defer {
      jogRequestInProgress = false
      manualJogTask = nil
      if activeStopTarget == .manualJog {
        activeStopTarget = nil
        stopRequestIssuedForTarget = nil
      }
    }
    let operation = Task {
      await machineActions.requestRelativeJog(request)
    }
    manualJogTask = operation
    activeStopTarget = .manualJog
    stopRequestIssuedForTarget = nil
    await Task.yield()
    let interimSnapshot = await machineActions.snapshot()
    if canCommit(generation) { machineSnapshot = interimSnapshot }
    let outcome = await operation.value
    let finalSnapshot = await machineActions.snapshot()
    guard canCommit(generation) else { return nil }
    machineSnapshot = finalSnapshot
    return outcome
  }

  func discoverCameras() async {
    guard let generation = beginHardwareIntent() else { return }
    defer { endHardwareIntent() }
    guard let cameraActions else {
      cameraError = "Native camera composition is unavailable."
      return
    }
    let snapshot = await cameraActions.discover()
    guard canCommit(generation) else { return }
    cameraSnapshot = snapshot
    updateCameraError()
  }

  func startPreferredCameraAtStartup() async {
    await discoverCameras()
    guard !hasShutdown, cameraError == nil else { return }
    let preferred =
      cameraDevices.first(where: {
        $0.name.localizedCaseInsensitiveContains("C920")
          || $0.name.localizedCaseInsensitiveContains("HD Pro Webcam")
      })
      ?? cameraDevices.onlyElement
    guard let preferred else { return }
    if selectedCameraID != preferred.id {
      await selectCamera(preferred.id)
    }
    guard !hasShutdown, cameraError == nil, selectedCameraID == preferred.id else { return }
    await startCamera()
  }

  func selectCamera(_ id: CameraDeviceID) async {
    guard let generation = beginHardwareIntent() else { return }
    defer { endHardwareIntent() }
    guard let cameraActions, activeDiscoverySequenceID == nil,
      !explorationOperationInProgress
    else {
      cameraError = "Finish the current discovery or learning action before changing camera configuration."
      return
    }
    clearAutomaticVisionPresentation()
    await clearDiscoveryAuthority()
    cameraError = nil
    do {
      let snapshot = try await cameraActions.select(id)
      guard canCommit(generation) else { return }
      cameraSnapshot = snapshot
      displayedFrame = nil
      latestLiveCameraFrame = nil
      cameraOverlays = []
    } catch {
      let snapshot = await cameraActions.snapshot()
      guard canCommit(generation) else { return }
      cameraError = actionableDescription(error)
      cameraSnapshot = snapshot
    }
  }

  func startCamera() async {
    guard let generation = beginHardwareIntent() else { return }
    defer { endHardwareIntent() }
    guard let cameraActions else { return }
    let snapshot = await cameraActions.start()
    guard canCommit(generation) else { return }
    frameMode = .live
    cameraSnapshot = snapshot
    displayedFrame = cameraSnapshot?.latestFrame
    latestLiveCameraFrame = validatedLiveCameraFrame(in: snapshot)
    updateCameraError()
    beginFrameUpdates(generation: generation)
  }

  func stopCamera() async {
    guard let generation = beginHardwareIntent() else { return }
    defer { endHardwareIntent() }
    frameTask?.cancel()
    frameTask = nil
    clearAutomaticVisionPresentation()
    guard let cameraActions else { return }
    let snapshot = await cameraActions.stop()
    guard canCommit(generation) else { return }
    cameraSnapshot = snapshot
    latestLiveCameraFrame = nil
    updateCameraError()
  }

  func restartCamera() async {
    guard let generation = beginHardwareIntent() else { return }
    defer { endHardwareIntent() }
    guard activeDiscoverySequenceID == nil, !explorationOperationInProgress else {
      cameraError = "Finish the current discovery or learning action before restarting the camera."
      return
    }
    frameTask?.cancel()
    frameTask = nil
    clearAutomaticVisionPresentation()
    await clearDiscoveryAuthority()
    guard let cameraActions else { return }
    let snapshot = await cameraActions.restart()
    guard canCommit(generation) else { return }
    frameMode = .live
    cameraSnapshot = snapshot
    displayedFrame = cameraSnapshot?.latestFrame
    latestLiveCameraFrame = validatedLiveCameraFrame(in: snapshot)
    cameraOverlays = []
    analysisFrameHeld = false
    lastSceneMeasurement = nil
    updateCameraError()
    beginFrameUpdates(generation: generation)
  }

  func inspectLatestScene() async {
    guard let generation = beginHardwareIntent() else { return }
    defer { endHardwareIntent() }
    guard frameMode == .live, !automaticVisionEnabled,
      !sceneInspectionInProgress, let cameraActions
    else { return }
    sceneInspectionInProgress = true
    cameraError = nil
    defer { sceneInspectionInProgress = false }
    do {
      guard let inspection = try await cameraActions.inspectScene(0) else {
        guard canCommit(generation) else { return }
        cameraError = "No newer camera frame is available for analysis."
        return
      }
      guard canCommit(generation) else { return }
      analysisFrameHeld = true
      displayedFrame = inspection.displayedFrame
      lastSceneMeasurement = inspection.measurement
      cameraOverlays = inspection.measurement.overlays
    } catch {
      guard canCommit(generation) else { return }
      cameraError = actionableDescription(error)
    }
  }

  func resumeLivePreview() async {
    guard frameMode == .live, let cameraActions else { return }
    analysisFrameHeld = false
    lastSceneMeasurement = nil
    cameraOverlays = []
    let snapshot = await cameraActions.snapshot()
    cameraSnapshot = snapshot
    if let latest = snapshot.latestFrame { displayedFrame = latest }
  }

  func setAutomaticVisionAnalysis(_ enabled: Bool) async {
    guard let generation = beginHardwareIntent() else { return }
    defer { endHardwareIntent() }
    guard frameMode == .live, let cameraActions else { return }
    visionUpdateTask?.cancel()
    visionUpdateTask = nil
    let snapshot = await cameraActions.setAutomaticInspection(
      enabled ? visionAnalysisCadence : nil
    )
    guard canCommit(generation) else { return }
    automaticVisionEnabled = enabled
    visionError = snapshot.lastError
    analysisFrameHeld = false
    visionAnalysisSnapshot = snapshot
    if enabled {
      beginVisionUpdates(generation: generation)
      if let result = snapshot.latestResult { receiveVision(result) }
    } else {
      lastSceneMeasurement = nil
      cameraOverlays = []
      let cameraSnapshot = await cameraActions.snapshot()
      guard canCommit(generation) else { return }
      self.cameraSnapshot = cameraSnapshot
      if let latest = cameraSnapshot.latestFrame { displayedFrame = latest }
    }
  }

  func updateVisionAnalysisCadence(_ cadence: VisionAnalysisCadence) async {
    visionAnalysisCadence = cadence
    guard automaticVisionEnabled else { return }
    await setAutomaticVisionAnalysis(true)
  }

  func captureCameraSnapshot() async {
    guard let generation = beginHardwareIntent() else { return }
    defer { endHardwareIntent() }
    guard frameMode == .live, let cameraActions else { return }
    cameraError = nil
    do {
      let path = try await cameraActions.captureSnapshot()
      guard canCommit(generation) else { return }
      lastCameraSnapshotPath = path
    } catch {
      guard canCommit(generation) else { return }
      cameraError = actionableDescription(error)
    }
  }

  func switchFrameMode(_ mode: OperatorFrameMode) async {
    guard let generation = beginHardwareIntent() else { return }
    defer { endHardwareIntent() }
    guard mode != frameMode || displayedFrame == nil else { return }
    if let reason = frameModeSwitchUnavailableReason {
      cameraError = reason
      return
    }
    guard let cameraActions else { return }
    frameModeSwitchInProgress = true
    defer { frameModeSwitchInProgress = false }
    frameTask?.cancel()
    frameTask = nil
    clearAutomaticVisionPresentation()
    cameraOverlays = []
    cameraError = nil
    switch mode {
    case .live:
      let snapshot = await cameraActions.start()
      guard canCommit(generation) else { return }
      frameMode = .live
      cameraSnapshot = snapshot
      displayedFrame = cameraSnapshot?.latestFrame
      latestLiveCameraFrame = validatedLiveCameraFrame(in: snapshot)
      updateCameraError()
      beginFrameUpdates(generation: generation)
    case .simulated:
      let snapshot = await cameraActions.stop()
      guard canCommit(generation) else { return }
      cameraSnapshot = snapshot
      latestLiveCameraFrame = nil
      do {
        let content = try await cameraActions.simulatedContent(simulatorModelMode)
        guard canCommit(generation) else { return }
        frameMode = .simulated
        applySimulatedContent(content)
      } catch {
        guard canCommit(generation) else { return }
        displayedFrame = nil
        cameraError = actionableDescription(error)
      }
    }
  }

  func selectSimulatorModelMode(_ mode: SimulatorModelMode) async {
    guard let generation = beginHardwareIntent() else { return }
    defer { endHardwareIntent() }
    guard mode != simulatorModelMode else { return }
    guard frameMode == .simulated else {
      simulatorModelMode = mode
      return
    }
    guard let cameraActions else { return }
    do {
      let content = try await cameraActions.simulatedContent(mode)
      guard canCommit(generation), frameMode == .simulated else { return }
      simulatorModelMode = mode
      cameraError = nil
      applySimulatedContent(content)
    } catch {
      guard canCommit(generation) else { return }
      cameraError = actionableDescription(error)
    }
  }

  private func applySimulatedContent(_ content: SimulatedActionSurfaceContent) {
    displayedFrame = content.displayedFrame
    cameraOverlays = content.overlays
    simulatorEvidenceLabel = content.evidenceLabel
    simulatorPenState = content.commandedPenState
    simulatorLearningSummary = content.learningSummary
  }

  func refreshCurrentState() async {
    guard let generation = beginHardwareIntent() else { return }
    defer { endHardwareIntent() }
    if let machineActions {
      let snapshot = await machineActions.snapshot()
      guard canCommit(generation) else { return }
      machineSnapshot = snapshot
    }
    if frameMode == .live, let cameraActions {
      let snapshot = await cameraActions.snapshot()
      guard canCommit(generation) else { return }
      cameraSnapshot = snapshot
      if let latest = cameraSnapshot?.latestFrame { receive(latest, generation: generation) }
      updateCameraError()
    }
  }

  func stopObserving() {
    frameTask?.cancel()
    frameTask = nil
    visionUpdateTask?.cancel()
    visionUpdateTask = nil
  }

  func shutdown() async {
    guard !hasShutdown else { return }
    hasShutdown = true
    lifetimeGeneration &+= 1
    stopObserving()
    await announcementActions?.cancelForShutdown()
    await stopAndSettleActiveMotionForShutdown()
    await waitForHardwareIntentsToDrain()
    _ = await cameraActions?.stop()
    await machineActions?.disconnect()
    await clearCameraAuthority()
    await clearMachineAuthority(clearSelection: true)
  }

  private func beginFrameUpdates(generation: UInt64) {
    frameTask?.cancel()
    guard canCommit(generation), let cameraActions, frameMode == .live else { return }
    frameTask = Task { [weak self] in
      let stream = await cameraActions.frames()
      for await frame in stream {
        guard !Task.isCancelled, let self else { return }
        self.receive(frame, generation: generation)
      }
    }
  }

  private func receive(_ frame: DisplayedFrame, generation: UInt64? = nil) {
    guard !hasShutdown, frameMode == .live else { return }
    if let generation, !canCommit(generation) { return }
    guard case .live(let deviceID) = frame.source, deviceID == selectedCameraID else { return }
    latestLiveCameraFrame = frame
    guard !analysisFrameHeld, !automaticVisionEnabled else { return }
    displayedFrame = frame
  }

  private func beginVisionUpdates(generation: UInt64) {
    guard canCommit(generation), let cameraActions, automaticVisionEnabled else { return }
    visionUpdateTask = Task { [weak self] in
      let stream = await cameraActions.analysisUpdates()
      for await snapshot in stream {
        guard !Task.isCancelled, let self,
          self.canCommit(generation), self.automaticVisionEnabled
        else { return }
        self.visionAnalysisSnapshot = snapshot
        self.visionError = snapshot.lastError
        self.cameraSnapshot = await cameraActions.snapshot()
        if let result = snapshot.latestResult { self.receiveVision(result) }
      }
    }
  }

  private func defaultInkRegion(for frame: StampedFrame) -> PixelRect {
    let width = max(1, min(180, frame.width / 3))
    let height = max(1, min(120, frame.height / 3))
    return PixelRect(
      x: max(0, (frame.width - width) / 2),
      y: max(0, (frame.height - height) / 2),
      width: width,
      height: height
    )
  }

  private func armatureContext(
    frame: StampedFrame,
    region: PixelRect
  ) -> ArmatureGuidanceContext {
    ArmatureGuidanceContext(
      controllerSessionID: controllerSessionID,
      coordinateRevision: explorationCoordinateRevision,
      cameraConfigurationID: frame.cameraConfigurationID,
      observationRegion: region,
      toolPaperRevision: explorationToolPaperRevision
    )
  }

  private func observationRegionOverlay(
    frame: StampedFrame,
    region: PixelRect,
    source: CameraOverlaySource
  ) -> CameraOverlayMeasurement {
    let bounds = try! AxisAlignedBounds<CameraPixelSpace>(
      minX: Double(region.x),
      minY: Double(region.y),
      maxX: Double(region.x + region.width),
      maxY: Double(region.y + region.height)
    )
    return CameraOverlayMeasurement(
      frameID: frame.id,
      cameraConfigurationID: frame.cameraConfigurationID,
      geometry: .bounds(bounds),
      provenance: CameraMeasurementProvenance(
        kind: .armatureEstimate,
        source: source,
        algorithmRevision: "exploration-fixed-ink-region-v1"
      )
    )
  }

  private func appendFrameEvidence(
    _ role: ExplorationFrameRole,
    frame: StampedFrame,
    algorithmRevision: String = "camera-selected-frame-v1"
  ) {
    guard var episode = currentExplorationEpisode else { return }
    episode.frames.removeAll { $0.role == role }
    episode.frames.append(ExplorationFrameEvidence(
      role: role,
      frameID: frame.id,
      contentSHA256: frame.contentSHA256,
      captureNanoseconds: frame.captureNanoseconds,
      cameraConfigurationID: frame.cameraConfigurationID,
      algorithmRevision: algorithmRevision
    ))
    currentExplorationEpisode = episode
  }

  private func recordStrokeEvidence(
    _ evidence: DrawingStrokeEvidence,
    outcome: ExplorationControllerOutcome,
    summary: String
  ) {
    guard var episode = currentExplorationEpisode else { return }
    episode.controllerEvidence = ExplorationControllerEvidence(
      startPosition: evidence.startPosition,
      finalPosition: evidence.finalPosition,
      startSampleNanoseconds: evidence.startSampleNanoseconds,
      settlementNanoseconds: evidence.finalSampleNanoseconds,
      outcome: outcome,
      summary: summary
    )
    currentExplorationEpisode = episode
  }

  private func acceptInkObservation(
    _ observation: IsolatedInkObservation
  ) {
    lastInkObservation = observation
    cameraOverlays = observation.overlays
    explorationInkStatus = observation.residual == nil
      ? "new ink observed; absolute residual unavailable without a current-session projection"
      : "new ink observed with anchor-relative projected residual"
    if var episode = currentExplorationEpisode {
      episode.anchorDotCentroid = observation.anchorCentroid
      episode.visionEstimate = ExplorationAssessment(
        summary: "\(observation.observedPixelCount) new line pixels",
        provenance: "\(observation.algorithmRevision) exact three-frame subtraction"
      )
      if let residual = observation.residual {
        episode.residual = ExplorationResidual(
          rmsPixels: residual.rootMeanSquareEndpointPixels,
          maximumPixels: residual.maximumEndpointPixels,
          crossTrackPixels: residual.rootMeanSquareCrossTrackPixels,
          summary: "camera-space anchor-relative residual",
          provenance: observation.algorithmRevision
        )
      } else {
        episode.residual = ExplorationResidual(
          summary: "absolute camera-space residual unavailable; relative displacement/orientation only",
          provenance: observation.algorithmRevision
        )
      }
      currentExplorationEpisode = episode
    }
  }

  private func returnToAcceptedClearPose() async throws {
    guard let guidance = armatureGuidanceState,
      let current = machineSnapshot?.machine.position,
      let machineActions
    else { throw LearningPathOperationError.controllerOutcome("clear-pose state unavailable") }
    if guidance.acceptedClearPose?.position == current { return }
    guard let destination = guidance.acceptedClearPose?.position else {
      throw LearningPathOperationError.controllerOutcome("clear-pose state unavailable")
    }
    let delta = try Vector2<MachineSpace>(
      dx: destination.point.x - current.point.x,
      dy: destination.point.y - current.point.y
    )
    let selection = travelFeedSelection(for: delta)
    lastTravelFeedSelection = selection
    _ = await announceAdvisory("Moving the raised pen to the accepted clear view.")
    let request = RelativeJogRequest(
      delta: delta,
      feedMMPerMinute: selection.requestedFeedMMPerMinute
    )
    let outcome = await machineActions.requestRelativeJog(request)
    machineSnapshot = await machineActions.snapshot()
    guard case .acceptedThenCompleted(let final) = outcome,
      final == guidance.acceptedClearPose?.position
    else {
      throw LearningPathOperationError.controllerOutcome(String(describing: outcome))
    }
  }

  private func answerDiscoverySequence(
    _ choice: OperatorChoice,
    for sequenceID: DiscoverySequenceID
  ) async {
    guard let transaction = discoveryTransactions[sequenceID],
      transaction.state == .active,
      let step = transaction.currentStep,
      let question = step.question,
      question.choices.contains(choice)
    else { return }

    guard question.advancingChoices.contains(choice) else {
      boundaryTeachingResultText = question.negativeAcknowledgement
      _ = await announceAdvisory(question.negativeAcknowledgement)
      if case .awaitPhysicalPenConfirmation(.down, _) = step.action {
        _ = await announceAdvisory("Raising the pen.")
        if frameMode == .simulated {
          simulatorPenState = .up
        } else {
          await requestPenActuation(.raise)
        }
        await failDiscovery(sequenceID, reason: question.negativeAcknowledgement)
      }
      return
    }

    switch step.action {
    case .awaitOperatorChoice:
      guard recordDiscovery(.operatorChoiceAccepted(choice), for: sequenceID) else { return }
    case .awaitPhysicalPenConfirmation(let state, _):
      guard recordDiscovery(
        .physicalPenConfirmed(
          state,
          response: choice,
          operatorSummary: "Operator selected \(choice.exactPhrase) for the current pen question."
        ),
        for: sequenceID
      ) else { return }
      pendingDiscoveryCaptureBoundaryNanoseconds = nowNanoseconds()
    default:
      return
    }
    await advanceDiscoverySequence(sequenceID)
  }

  private func executeBoundaryMotion(_ direction: JogDirection) async {
    guard let request = makeBoundaryMotionRequest(direction),
      let machineActions,
      let sequenceID = activeDiscoverySequenceID,
      let transactionID = discoveryTransactions[sequenceID]?.id
    else {
      boundaryTeachingState = .idle
      return
    }

    let discoveryDirection = boundaryDirection(from: direction)
    let stopTarget = ContextualStopTarget.boundaryDiscovery(
      transactionID: transactionID,
      direction: discoveryDirection
    )
    activeStopTarget = stopTarget
    stopRequestIssuedForTarget = nil
    let controllerTask = Task { await machineActions.requestBoundaryMotion(request) }
    await Task.yield()
    machineSnapshot = await machineActions.snapshot()
    boundaryTeachingState = .ownerActive(direction)
    boundaryTeachingResultText =
      "Boundary owner active toward \(direction.shortLabel). Stop is available during admission and motion."
    guard recordDiscovery(
      .boundaryJogStarted(
        discoveryDirection,
        controllerSummary:
          "Logical Boundary Discovery owner started; direct controller admission remains runtime-owned."
      ),
      for: sequenceID
    ) else { return }
    await advanceDiscoverySequence(sequenceID)

    let outcome = await controllerTask.value
    machineSnapshot = await machineActions.snapshot()
    guard !hasShutdown else { return }

    switch outcome {
    case .settled(let settlement) where settlement.intent == .operatorStop:
      let finalPosition = settlement.finalPosition
      pendingDiscoveryCaptureBoundaryNanoseconds = nowNanoseconds()
      boundaryPositions[direction] = finalPosition
      boundaryTeachingResultText = String(
        format: "%@ observed at final X %.3f Y %.3f after Stop and Idle.",
        direction.shortLabel,
        finalPosition.point.x,
        finalPosition.point.y
      )
      guard recordDiscovery(
        .boundaryJogCancelled(
          boundaryDirection(from: direction),
          finalPosition: finalPosition,
          controllerSummary: boundaryTeachingResultText
        ),
        for: sequenceID
      ) else { return }
      await advanceDiscoverySequence(sequenceID)

    case .settled(let settlement):
      if var transaction = discoveryTransactions[sequenceID] {
        transaction.cancel()
        discoveryTransactions[sequenceID] = transaction
      }
      boundaryTeachingResultText =
        settlement.intent == .shutdown
        ? "Boundary Discovery settled during shutdown; no boundary evidence was recorded."
        : "Boundary Discovery was cancelled; no boundary evidence was recorded."
      pendingDiscoveryInspection = nil
      pendingDiscoveryCaptureBoundaryNanoseconds = nil
      recordDiscoveryAttempt(sequenceID: sequenceID, disposition: .cancelled)
      finishActiveExerciseAttempt(disposition: .cancelled)
      if settlement.intent == .cancelAttempt {
        restartableExerciseItemID = .humanGuidedDiscovery(.boundaryDiscovery)
      }

    case .needsAttention(_, let terminal):
      await failDiscovery(sequenceID, reason: boundaryTerminalDescription(terminal))
    }
    boundaryTeachingState = .idle
    activeStopTarget = nil
    stopRequestIssuedForTarget = nil
  }

  private func makeBoundaryMotionRequest(_ direction: JogDirection) -> BoundaryMotionRequest? {
    guard boundaryTeachingState == .awaitingConfirmation(direction),
      directCarriageMotionUnavailableReason == nil
    else {
      boundaryTeachingResultText =
        "Boundary motion cannot start: \(directCarriageMotionUnavailableReason ?? "current direct controller facts are unavailable")."
      return nil
    }
    do {
      let delta: Vector2<MachineSpace>
      switch direction {
      case .xNegative: delta = try Vector2(dx: -MotionPriors.boundaryWireSegmentMM, dy: 0)
      case .xPositive: delta = try Vector2(dx: MotionPriors.boundaryWireSegmentMM, dy: 0)
      case .yNegative: delta = try Vector2(dx: 0, dy: -MotionPriors.boundaryWireSegmentMM)
      case .yPositive: delta = try Vector2(dx: 0, dy: MotionPriors.boundaryWireSegmentMM)
      }
      let selection = travelFeedSelection(for: delta)
      lastTravelFeedSelection = selection
      return BoundaryMotionRequest(
        direction: boundaryDirection(from: direction),
        segment: RelativeJogRequest(
          delta: delta,
          feedMMPerMinute: selection.requestedFeedMMPerMinute
        )
      )
    } catch {
      boundaryTeachingResultText = "Boundary motion request is invalid; no motion was sent."
      return nil
    }
  }

  private func startExercise(
    _ ownerID: LearningPathItemID,
    mode: ExerciseAttemptMode
  ) async {
    guard activeExerciseAttemptOwnerID == nil else { return }
    activeExerciseAttemptMode = mode
    restartableExerciseItemID = nil
    switch ownerID {
    case .humanGuidedDiscovery(.penInteraction):
      await beginPenInteraction()
    case .humanGuidedDiscovery(.boundaryDiscovery):
      await beginBoundaryDiscovery(selectedBoundaryDirection)
    case .humanGuidedDiscovery(.clearViewDiscovery):
      beginExerciseAttempt(ownerID: ownerID, mode: mode)
      pendingClearViewLabel = nil
    case .observedDrawingTrial(let step):
      observedDrawingTrialStep = step
      beginExerciseAttempt(ownerID: ownerID, mode: mode)
      if step != .compareIntendedAndObservedGeometry {
        await performCurrentLearningPathAction()
      }
    case .stage:
      activeExerciseAttemptMode = nil
    }
  }

  private func cancelExerciseAttempt(_ ownerID: LearningPathItemID) async {
    guard activeExerciseAttemptOwnerID == ownerID else { return }
    if let sequenceID = activeDiscoverySequenceID,
      var transaction = discoveryTransactions[sequenceID]
    {
      transaction.cancel()
      discoveryTransactions[sequenceID] = transaction
      if let target = activeStopTarget {
        boundaryTeachingState = .cancelling(
          jogDirection(for: sequenceID) ?? jogDirection(from: selectedBoundaryDirection)
        )
        let owner = boundaryMotionTask
        await requestSingleJogCancel(for: target, intent: .cancelAttempt)
        await owner?.value
      }
      recordDiscoveryAttempt(sequenceID: sequenceID, disposition: .cancelled)
    } else if let target = activeStopTarget, target == .drawingTrial {
      let owner = drawingTrialTask
      await requestSingleJogCancel(for: target, intent: .cancelAttempt)
      _ = await owner?.value
    }
    if ownerID == .humanGuidedDiscovery(.clearViewDiscovery) {
      recordClearViewAttempt(label: nil, disposition: .cancelled)
    } else if ownerID == .observedDrawingTrial(.compareIntendedAndObservedGeometry) {
      recordComparisonAttempt(assessment: nil, disposition: .cancelled)
    }
    pendingClearViewLabel = nil
    finishActiveExerciseAttempt(disposition: .cancelled)
    restartableExerciseItemID = ownerID
  }

  private func beginExerciseAttempt(
    ownerID: LearningPathItemID,
    mode: ExerciseAttemptMode
  ) {
    guard activeExerciseAttemptID == nil else { return }
    activeExerciseAttemptID = ExerciseAttemptID()
    activeExerciseAttemptOwnerID = ownerID
    activeExerciseAttemptMode = mode
    if ownerID == .humanGuidedDiscovery(.boundaryDiscovery) {
      boundaryDerivedValueSnapshot = BoundaryDerivedValueSnapshot(
        posterior: drawingFramePosterior,
        observationsByAttemptID: boundaryFrameObservationsByAttemptID,
        overlays: cameraOverlays
      )
    }
  }

  private func finishActiveExerciseAttempt(disposition: ExerciseAttemptDisposition) {
    if activeExerciseAttemptOwnerID == .humanGuidedDiscovery(.boundaryDiscovery) {
      if disposition != .succeeded, let snapshot = boundaryDerivedValueSnapshot {
        drawingFramePosterior = snapshot.posterior
        boundaryFrameObservationsByAttemptID = snapshot.observationsByAttemptID
        cameraOverlays = snapshot.overlays
      }
      boundaryDerivedValueSnapshot = nil
    }
    activeExerciseAttemptID = nil
    activeExerciseAttemptOwnerID = nil
    activeExerciseAttemptMode = nil
  }

  private func recordAttempt<Value: Hashable & Sendable>(
    _ attempt: ExerciseAttempt<Value>,
    in history: inout ExerciseAttemptHistory<Value>,
    replacingAttemptID: ExerciseAttemptID?
  ) throws {
    if activeExerciseAttemptMode == .replacement {
      guard let replacingAttemptID else {
        throw LearningPathOperationError.requiredState(
          "The accepted attempt selected for replacement is unavailable."
        )
      }
      try history.recordReplacement(attempt, replacing: replacingAttemptID)
    } else {
      try history.record(attempt)
    }
  }

  /// Stages replacement across compatibility-bound histories without pooling.
  /// An incompatible successful Redo supersedes the accepted source sample and
  /// records the new value in its own history; an unsuccessful Redo records only
  /// excluded provenance and leaves the old accepted sample included.
  private func recordAttempt<Value: Hashable & Sendable>(
    _ attempt: ExerciseAttempt<Value>,
    in histories: inout [AttemptCompatibility: ExerciseAttemptHistory<Value>],
    replacingAttemptID: ExerciseAttemptID?
  ) throws {
    var targetHistory = try histories[attempt.compatibility]
      ?? ExerciseAttemptHistory(compatibility: attempt.compatibility)
    guard activeExerciseAttemptMode == .replacement else {
      try targetHistory.record(attempt)
      histories[attempt.compatibility] = targetHistory
      return
    }
    guard let replacingAttemptID else {
      throw LearningPathOperationError.requiredState(
        "The accepted attempt selected for replacement is unavailable."
      )
    }

    if targetHistory.records.contains(where: { $0.attempt.id == replacingAttemptID }) {
      try targetHistory.recordReplacement(attempt, replacing: replacingAttemptID)
      histories[attempt.compatibility] = targetHistory
      return
    }

    guard let sourceCompatibility = histories.first(where: { _, history in
      history.records.contains(where: { $0.attempt.id == replacingAttemptID })
    })?.key else {
      throw ExerciseAttemptError.replacementTargetNotFound(replacingAttemptID)
    }
    try targetHistory.record(attempt)
    if attempt.disposition.contributesSuccessfulValue {
      var sourceHistory = histories[sourceCompatibility]!
      try sourceHistory.supersedeIncludedAttempt(replacingAttemptID, by: attempt.id)
      histories[sourceCompatibility] = sourceHistory
    }
    histories[attempt.compatibility] = targetHistory
  }

  private func commitSuccessfulDiscoveryAttempt(_ sequenceID: DiscoverySequenceID) {
    guard let attemptID = activeExerciseAttemptID else { return }
    do {
      switch sequenceID {
      case .penInteraction:
        let sequence = acceptedAttemptSequence &+ 1
        var history = penAttemptHistory
        let replacingAttemptID = learningArtifactGraph.currentRevision(for: .penInteraction)?
          .attemptID
        try recordAttempt(
          ExerciseAttempt(
            id: attemptID,
            disposition: .succeeded,
            compatibility: history.compatibility,
            acceptedSequence: sequence,
            value: .up
          ),
          in: &history,
          replacingAttemptID: replacingAttemptID
        )
        var graph = learningArtifactGraph
        let commit = try graph.commitReplacement(
          LearningArtifactRevision(
            kind: .penInteraction,
            attemptID: attemptID,
            disposition: .succeeded
          )
        )
        penAttemptHistory = history
        acceptedAttemptSequence = sequence
        learningArtifactGraph = graph
        applyArtifactInvalidations(commit.invalidatedRevisionIDs)

      case .boundaryNegativeX, .boundaryPositiveX, .boundaryNegativeY, .boundaryPositiveY:
        guard let direction = boundaryDirection(for: sequenceID),
          let position = boundaryPositions[jogDirection(from: direction)]
        else { return }
        let compatibility = boundaryCompatibility(direction)
        var histories = boundaryAttemptHistories[direction] ?? [:]
        let value = switch direction {
        case .negativeX, .positiveX: position.point.x
        case .negativeY, .positiveY: position.point.y
        }
        let sequence = acceptedAttemptSequence &+ 1
        let observationKind = LearningArtifactKind.boundaryObservation(direction)
        let replacingAttemptID = learningArtifactGraph.currentRevision(for: observationKind)?
          .attemptID
        try recordAttempt(
          ExerciseAttempt(
            id: attemptID,
            disposition: .succeeded,
            compatibility: compatibility,
            acceptedSequence: sequence,
            value: value
          ),
          in: &histories,
          replacingAttemptID: replacingAttemptID
        )

        var graph = learningArtifactGraph
        let observation = try graph.commitReplacement(
          LearningArtifactRevision(
            kind: observationKind,
            attemptID: attemptID,
            disposition: .succeeded
          )
        )
        let posterior = try graph.commitReplacement(
          LearningArtifactRevision(
            kind: .boundaryPosterior(direction),
            attemptID: attemptID,
            disposition: .succeeded,
            consumedRevisionIDs: [observation.currentRevision.id]
          )
        )
        let association = try graph.commitReplacement(
          LearningArtifactRevision(
            kind: .boundaryAssociation(direction),
            attemptID: attemptID,
            disposition: .succeeded,
            consumedRevisionIDs: [observation.currentRevision.id]
          )
        )
        boundaryAttemptHistories[direction] = histories
        acceptedAttemptSequence = sequence
        learningArtifactGraph = graph
        applyArtifactInvalidations(
          observation.invalidatedRevisionIDs
            .union(posterior.invalidatedRevisionIDs)
            .union(association.invalidatedRevisionIDs)
        )
      }
      discoveryError = nil
      restartableExerciseItemID = nil
      finishActiveExerciseAttempt(disposition: .succeeded)
    } catch {
      recordDiscoveryAttempt(
        sequenceID: sequenceID,
        disposition: .failed("Atomic accepted-artifact commit failed: \(error)")
      )
      discoveryError = "Accepted discovery artifact could not commit: \(error)"
      restartableExerciseItemID = learningPathItemID(for: sequenceID)
      finishActiveExerciseAttempt(disposition: .failed(String(describing: error)))
    }
  }

  private func recordDiscoveryAttempt(
    sequenceID: DiscoverySequenceID,
    disposition: ExerciseAttemptDisposition
  ) {
    guard let attemptID = activeExerciseAttemptID else { return }
    do {
      if sequenceID == .penInteraction {
        let sequence = acceptedAttemptSequence &+ 1
        var history = penAttemptHistory
        let replacingAttemptID = learningArtifactGraph.currentRevision(for: .penInteraction)?
          .attemptID
        try recordAttempt(
          ExerciseAttempt(
            id: attemptID,
            disposition: disposition,
            compatibility: history.compatibility,
            acceptedSequence: sequence,
            value: nil
          ),
          in: &history,
          replacingAttemptID: replacingAttemptID
        )
        penAttemptHistory = history
        acceptedAttemptSequence = sequence
      } else if let direction = boundaryDirection(for: sequenceID) {
        let compatibility = boundaryCompatibility(direction)
        var histories = boundaryAttemptHistories[direction] ?? [:]
        let sequence = acceptedAttemptSequence &+ 1
        let replacingAttemptID = learningArtifactGraph.currentRevision(
          for: .boundaryObservation(direction)
        )?.attemptID
        try recordAttempt(
          ExerciseAttempt(
            id: attemptID,
            disposition: disposition,
            compatibility: compatibility,
            acceptedSequence: sequence,
            value: nil
          ),
          in: &histories,
          replacingAttemptID: replacingAttemptID
        )
        boundaryAttemptHistories[direction] = histories
        acceptedAttemptSequence = sequence
      }
    } catch {
      discoveryError = "Attempt provenance could not be recorded: \(error)"
    }
  }

  private func boundaryCompatibility(_ direction: BoundaryDirection) -> AttemptCompatibility {
    AttemptCompatibility(
      cameraConfigurationID: displayedFrame?.frame.cameraConfigurationID,
      coordinateSpace: .machine,
      units: .millimeters,
      group: AttemptGroupIdentity(rawValue: "boundary-\(direction.rawValue)"),
      algorithmRevision: "boundary-side-posterior-v1"
    )
  }

  func boundaryAggregate(
    for direction: BoundaryDirection,
    compatibility: AttemptCompatibility
  ) -> NumericAttemptAggregate? {
    guard let history = boundaryAttemptHistories[direction]?[compatibility] else { return nil }
    return try? NumericAttemptAggregate(history: history)
  }

  var currentPenStateAggregate: LatestStateAggregate<PenState>? {
    try? LatestStateAggregate(history: penAttemptHistory)
  }

  func clearViewAggregate(
    compatibility: AttemptCompatibility
  ) -> CategoricalAttemptAggregate<ArmatureVisibilityLabel>? {
    guard let history = clearViewAttemptHistories[compatibility] else { return nil }
    return try? CategoricalAttemptAggregate(history: history)
  }

  func comparisonAggregate(
    compatibility: AttemptCompatibility
  ) -> CategoricalAttemptAggregate<DrawingTrialAssessment>? {
    guard let history = comparisonAttemptHistories[compatibility] else { return nil }
    return try? CategoricalAttemptAggregate(history: history)
  }

  private func recordClearViewAttempt(
    label: ArmatureVisibilityLabel?,
    disposition: ExerciseAttemptDisposition
  ) {
    guard let attemptID = activeExerciseAttemptID else { return }
    let compatibility = AttemptCompatibility(
      cameraConfigurationID: lastArmatureObservation?.cameraConfigurationID,
      coordinateSpace: .categorical,
      units: .categorical,
      group: AttemptGroupIdentity(rawValue: "clear-view"),
      algorithmRevision: "armature-guidance-v1"
    )
    do {
      var histories = clearViewAttemptHistories
      let sequence = acceptedAttemptSequence &+ 1
      let replacingAttemptID = learningArtifactGraph.currentRevision(for: .clearPose)?.attemptID
      try recordAttempt(
        ExerciseAttempt(
          id: attemptID,
          disposition: disposition,
          compatibility: compatibility,
          acceptedSequence: sequence,
          value: label
        ),
        in: &histories,
        replacingAttemptID: replacingAttemptID
      )
      clearViewAttemptHistories = histories
      acceptedAttemptSequence = sequence
    } catch {
      explorationError = "Clear-View attempt provenance could not be recorded: \(error)"
    }
  }

  private func commitClearViewAttemptAndArtifact(
    guidance: ArmatureGuidanceState
  ) throws {
    guard let attemptID = activeExerciseAttemptID else {
      throw LearningPathOperationError.requiredState("No active typed exercise attempt.")
    }
    let compatibility = AttemptCompatibility(
      cameraConfigurationID: lastArmatureObservation?.cameraConfigurationID,
      coordinateSpace: .categorical,
      units: .categorical,
      group: AttemptGroupIdentity(rawValue: "clear-view"),
      algorithmRevision: "armature-guidance-v1"
    )
    var histories = clearViewAttemptHistories
    let sequence = acceptedAttemptSequence &+ 1
    let replacingAttemptID = learningArtifactGraph.currentRevision(for: .clearPose)?.attemptID
    try recordAttempt(
      ExerciseAttempt(
        id: attemptID,
        disposition: .succeeded,
        compatibility: compatibility,
        acceptedSequence: sequence,
        value: .clear
      ),
      in: &histories,
      replacingAttemptID: replacingAttemptID
    )
    var graph = learningArtifactGraph
    let commit = try graph.commitReplacement(
      LearningArtifactRevision(
        kind: .clearPose,
        attemptID: attemptID,
        disposition: .succeeded
      )
    )

    clearViewAttemptHistories = histories
    acceptedAttemptSequence = sequence
    learningArtifactGraph = graph
    armatureGuidanceState = guidance
    clearViewPoseAccepted = true
    observedDrawingTrialStep = .captureCleanReference
    applyArtifactInvalidations(commit.invalidatedRevisionIDs)
  }

  private func recordComparisonAttempt(
    assessment: DrawingTrialAssessment?,
    disposition: ExerciseAttemptDisposition
  ) {
    guard let attemptID = activeExerciseAttemptID else { return }
    let compatibility = AttemptCompatibility(
      cameraConfigurationID: explorationPostLineFrame?.frame.cameraConfigurationID,
      coordinateSpace: .categorical,
      units: .categorical,
      group: currentDrawingTrialGroup,
      algorithmRevision: "typed-trial-comparison-v1"
    )
    do {
      var histories = comparisonAttemptHistories
      let sequence = acceptedAttemptSequence &+ 1
      let replacingAttemptID = learningArtifactGraph.currentRevision(
        for: .comparison(currentDrawingTrialGroup)
      )?.attemptID
      try recordAttempt(
        ExerciseAttempt(
          id: attemptID,
          disposition: disposition,
          compatibility: compatibility,
          acceptedSequence: sequence,
          value: assessment
        ),
        in: &histories,
        replacingAttemptID: replacingAttemptID
      )
      comparisonAttemptHistories = histories
      acceptedAttemptSequence = sequence
    } catch {
      explorationError = "Comparison attempt provenance could not be recorded: \(error)"
    }
  }

  private func commitDrawingArtifact(for step: ObservedDrawingTrialStep) throws {
    guard let attemptID = activeExerciseAttemptID else {
      throw LearningPathOperationError.requiredState("No active typed exercise attempt.")
    }
    let group = currentDrawingTrialGroup
    var graph = learningArtifactGraph
    func required(_ kind: LearningArtifactKind) throws -> LearningArtifactRevisionID {
      guard let id = graph.currentRevision(for: kind)?.id else {
        throw LearningPathOperationError.requiredState("Required artifact \(kind) is unavailable.")
      }
      return id
    }
    let kind: LearningArtifactKind
    let dependencies: Set<LearningArtifactRevisionID>
    switch step {
    case .captureCleanReference:
      kind = .cleanReference(group)
      dependencies = [try required(.clearPose)]
    case .chooseLineStart:
      kind = .lineStart(group)
      dependencies = []
    case .createAnchorMark:
      kind = .anchorMark(group)
      dependencies = [
        try required(.cleanReference(group)),
        try required(.lineStart(group)),
        try required(.clearPose),
      ]
    case .drawIsolatedLine:
      kind = .isolatedLine(group)
      dependencies = [try required(.lineStart(group)), try required(.anchorMark(group))]
    case .clearToolAndObserveInk:
      kind = .postFrame(group)
      dependencies = [try required(.isolatedLine(group)), try required(.clearPose)]
    case .compareIntendedAndObservedGeometry:
      kind = .comparison(group)
      dependencies = [
        try required(.inkObservation(group)), try required(.residual(group)),
      ]
    }
    let primary = try graph.commitReplacement(
      LearningArtifactRevision(
        kind: kind,
        attemptID: attemptID,
        disposition: .succeeded,
        consumedRevisionIDs: dependencies
      )
    )
    var invalidated = primary.invalidatedRevisionIDs

    if step == .clearToolAndObserveInk {
      let clean = try required(.cleanReference(group))
      let anchor = try required(.anchorMark(group))
      let post = try required(.postFrame(group))
      let ink = try graph.commitReplacement(
          LearningArtifactRevision(
            kind: .inkObservation(group),
            attemptID: attemptID,
            disposition: .succeeded,
            consumedRevisionIDs: [clean, anchor, post]
          )
        )
      let residual = try graph.commitReplacement(
          LearningArtifactRevision(
            kind: .residual(group),
            attemptID: attemptID,
            disposition: .succeeded,
            consumedRevisionIDs: [ink.currentRevision.id]
          )
        )
      invalidated.formUnion(ink.invalidatedRevisionIDs)
      invalidated.formUnion(residual.invalidatedRevisionIDs)
    }
    learningArtifactGraph = graph
    applyArtifactInvalidations(invalidated)
  }

  private func drawingTrialPayloadSnapshot() -> DrawingTrialPayloadSnapshot {
    DrawingTrialPayloadSnapshot(
      step: observedDrawingTrialStep,
      cleanReference: explorationCleanReference,
      anchoredBaseline: explorationAnchoredBaseline,
      postLineFrame: explorationPostLineFrame,
      lineStart: drawingTrialLineStart,
      strokeEvidence: drawingTrialStrokeEvidence,
      anchorObservation: lastAnchorObservation,
      inkObservation: lastInkObservation,
      inkStatus: explorationInkStatus,
      assessment: drawingTrialAssessment,
      episode: currentExplorationEpisode,
      completedEpisodes: completedExplorationEpisodes
    )
  }

  private func restoreDrawingTrialPayload(_ snapshot: DrawingTrialPayloadSnapshot) {
    observedDrawingTrialStep = snapshot.step
    explorationCleanReference = snapshot.cleanReference
    explorationAnchoredBaseline = snapshot.anchoredBaseline
    explorationPostLineFrame = snapshot.postLineFrame
    drawingTrialLineStart = snapshot.lineStart
    drawingTrialStrokeEvidence = snapshot.strokeEvidence
    lastAnchorObservation = snapshot.anchorObservation
    lastInkObservation = snapshot.inkObservation
    explorationInkStatus = snapshot.inkStatus
    drawingTrialAssessment = snapshot.assessment
    currentExplorationEpisode = snapshot.episode
    completedExplorationEpisodes = snapshot.completedEpisodes
  }

  private func advanceDrawingTrialAfterSuccess(_ step: ObservedDrawingTrialStep) {
    switch step {
    case .captureCleanReference: advanceDrawingTrial(to: .chooseLineStart)
    case .chooseLineStart: advanceDrawingTrial(to: .createAnchorMark)
    case .createAnchorMark: advanceDrawingTrial(to: .drawIsolatedLine)
    case .drawIsolatedLine: advanceDrawingTrial(to: .clearToolAndObserveInk)
    case .clearToolAndObserveInk:
      advanceDrawingTrial(to: .compareIntendedAndObservedGeometry)
    case .compareIntendedAndObservedGeometry:
      break
    }
  }

  private func commitComparisonAttemptAndArtifact(
    _ assessment: DrawingTrialAssessment
  ) throws {
    guard let attemptID = activeExerciseAttemptID else {
      throw LearningPathOperationError.requiredState("No active typed exercise attempt.")
    }
    let compatibility = AttemptCompatibility(
      cameraConfigurationID: explorationPostLineFrame?.frame.cameraConfigurationID,
      coordinateSpace: .categorical,
      units: .categorical,
      group: currentDrawingTrialGroup,
      algorithmRevision: "typed-trial-comparison-v1"
    )
    var histories = comparisonAttemptHistories
    let sequence = acceptedAttemptSequence &+ 1
    let comparisonKind = LearningArtifactKind.comparison(currentDrawingTrialGroup)
    let replacingAttemptID = learningArtifactGraph.currentRevision(for: comparisonKind)?.attemptID
    try recordAttempt(
      ExerciseAttempt(
        id: attemptID,
        disposition: .succeeded,
        compatibility: compatibility,
        acceptedSequence: sequence,
        value: assessment
      ),
      in: &histories,
      replacingAttemptID: replacingAttemptID
    )

    var graph = learningArtifactGraph
    guard let ink = graph.currentRevision(for: .inkObservation(currentDrawingTrialGroup))?.id,
      let residual = graph.currentRevision(for: .residual(currentDrawingTrialGroup))?.id
    else {
      throw LearningPathOperationError.requiredState("Observed ink and residual artifacts are required.")
    }
    let commit = try graph.commitReplacement(
      LearningArtifactRevision(
        kind: comparisonKind,
        attemptID: attemptID,
        disposition: .succeeded,
        consumedRevisionIDs: [ink, residual]
      )
    )
    comparisonAttemptHistories = histories
    acceptedAttemptSequence = sequence
    learningArtifactGraph = graph
    applyArtifactInvalidations(commit.invalidatedRevisionIDs)
  }

  private func applyArtifactInvalidations(_ revisionIDs: Set<LearningArtifactRevisionID>) {
    for revisionID in revisionIDs {
      guard let revision = learningArtifactGraph.revision(id: revisionID) else { continue }
      switch revision.kind {
      case .penInteraction, .boundaryObservation, .boundaryPosterior, .boundaryAssociation:
        break
      case .clearPose:
        clearViewPoseAccepted = false
      case .cleanReference:
        explorationCleanReference = nil
        observedDrawingTrialStep = .captureCleanReference
      case .lineStart:
        drawingTrialLineStart = nil
        setObservedDrawingTrialStepEarlier(ifNeeded: .chooseLineStart)
      case .anchorMark:
        explorationAnchoredBaseline = nil
        lastAnchorObservation = nil
        setObservedDrawingTrialStepEarlier(ifNeeded: .createAnchorMark)
      case .isolatedLine:
        drawingTrialStrokeEvidence = nil
        setObservedDrawingTrialStepEarlier(ifNeeded: .drawIsolatedLine)
      case .postFrame:
        explorationPostLineFrame = nil
        setObservedDrawingTrialStepEarlier(ifNeeded: .clearToolAndObserveInk)
      case .inkObservation, .residual:
        lastInkObservation = nil
        drawingTrialAssessment = nil
        setObservedDrawingTrialStepEarlier(ifNeeded: .clearToolAndObserveInk)
      case .comparison:
        drawingTrialAssessment = nil
        setObservedDrawingTrialStepEarlier(ifNeeded: .compareIntendedAndObservedGeometry)
      }
    }
  }

  private func setObservedDrawingTrialStepEarlier(ifNeeded step: ObservedDrawingTrialStep) {
    if observedDrawingTrialStep.rawValue > step.rawValue {
      observedDrawingTrialStep = step
    }
  }

  private func attemptDisposition(for reason: String) -> ExerciseAttemptDisposition {
    let lowered = reason.lowercased()
    if lowered.contains("unclear") { return .unclear(reason) }
    if lowered.contains("ambiguous") || lowered.contains("unknown post-write") {
      return .ambiguous(reason)
    }
    if lowered.contains("refus") || lowered.contains("alarm") || lowered.contains("limit")
      || lowered.contains("disconnect")
    {
      return .refused(reason)
    }
    return .failed(reason)
  }

  private func boundaryTerminalDescription(_ terminal: BoundaryMotionTerminal) -> String {
    switch terminal {
    case .limitAsserted(let pins, _): "Controller limit asserted (\(pins)); no boundary evidence was recorded."
    case .alarm(let alarm): "Controller alarm: \(alarm); no boundary evidence was recorded."
    case .refusal(let refusal): refusal.actionableDescription
    case .disconnected: "Controller disconnected; no boundary evidence was recorded."
    case .fault(let ambiguity): ambiguity.actionableDescription
    }
  }

  private func learningPathItemID(for sequenceID: DiscoverySequenceID) -> LearningPathItemID {
    sequenceID == .penInteraction
      ? .humanGuidedDiscovery(.penInteraction)
      : .humanGuidedDiscovery(.boundaryDiscovery)
  }

  private func discoverySequenceID(
    for step: HumanGuidedDiscoveryStep
  ) -> DiscoverySequenceID? {
    switch step {
    case .penInteraction: .penInteraction
    case .boundaryDiscovery: sequenceID(for: selectedBoundaryDirection)
    case .clearViewDiscovery: nil
    }
  }

  private func learningPathStatus(for itemID: LearningPathItemID) -> LearningPathStageStatus {
    if itemID == .stage(.adaptiveDrawing) { return .future }
    if itemIsComplete(itemID) { return .complete }
    let representsCurrentStage: Bool = if case .stage(let stage) = itemID {
      currentLearningPathItemID.stage == stage
    } else {
      false
    }
    if itemID == currentLearningPathItemID || representsCurrentStage {
      if itemID.stage == .humanGuidedDiscovery, discoveryError != nil { return .needsAttention }
      if itemID.stage == .observedDrawingTrials, explorationError != nil {
        return .needsAttention
      }
      if itemID == .stage(.connect), machineError != nil { return .needsAttention }
      return .current
    }
    return .next
  }

  private func itemIsComplete(_ itemID: LearningPathItemID) -> Bool {
    let discoveryComplete = penInteractionCompleted
      && relevantBoundaryObservationCount > 0 && clearViewPoseAccepted
    return switch itemID {
    case .stage(.connect): controllerIsConnected
    case .stage(.enableMotion): controllerIsConnected && motionGuardIsActive
    case .stage(.humanGuidedDiscovery): discoveryComplete
    case .stage(.observedDrawingTrials): drawingTrialAssessment != nil
    case .stage(.adaptiveDrawing): false
    case .humanGuidedDiscovery(.penInteraction): penInteractionCompleted
    case .humanGuidedDiscovery(.boundaryDiscovery): relevantBoundaryObservationCount > 0
    case .humanGuidedDiscovery(.clearViewDiscovery): clearViewPoseAccepted
    case .observedDrawingTrial(let step):
      drawingTrialAssessment != nil
        || (step.rawValue < observedDrawingTrialStep.rawValue
          && drawingArtifactRevision(for: step) != nil)
    }
  }

  private func itemIsRepeatable(_ itemID: LearningPathItemID) -> Bool {
    switch itemID {
    case .humanGuidedDiscovery(.penInteraction),
      .humanGuidedDiscovery(.boundaryDiscovery),
      .humanGuidedDiscovery(.clearViewDiscovery),
      .observedDrawingTrial(.compareIntendedAndObservedGeometry):
      true
    default:
      false
    }
  }

  private func learningPathSummary(for itemID: LearningPathItemID) -> String {
    switch itemID {
    case .stage(.connect):
      controllerIsConnected ? "The selected controller is responsive." : "Select and connect one responsive controller."
    case .stage(.enableMotion):
      motionGuardIsActive ? "Motion is enabled for typed operations." : "Enable Motion for this controller session."
    case .stage(.humanGuidedDiscovery):
      "Observe Pen Interaction, at least one Boundary, and a Clear view."
    case .humanGuidedDiscovery(.penInteraction):
      "Observe the physical pen UP, DOWN, then UP again."
    case .humanGuidedDiscovery(.boundaryDiscovery):
      "Move under one logical owner until the operator presses STOP."
    case .humanGuidedDiscovery(.clearViewDiscovery):
      "Label an exact view Blocked, Partial, or Clear and accept a Clear pose."
    case .stage(.observedDrawingTrials):
      "Create one attributable line, observe actual ink, and compare geometry."
    case .observedDrawingTrial(let step): drawingTrialActionText(for: step)
    case .stage(.adaptiveDrawing):
      "Adaptive Drawing remains Future until multi-stroke checkpoint learning is implemented."
    }
  }

  private func exerciseActionStrip(
    for itemID: LearningPathItemID
  ) -> ExerciseActionStripPresentation? {
    if activeExerciseAttemptOwnerID == itemID {
      var actions: [ExerciseActionDescriptor] = []
      if case .humanGuidedDiscovery(.clearViewDiscovery) = itemID {
        actions.append(contentsOf: ArmatureVisibilityLabel.allCases.map { label in
          ExerciseActionDescriptor(
            kind: .recordClearViewLabel(label),
            title: label.rawValue.capitalized
          )
        })
        actions.append(
          ExerciseActionDescriptor(
            kind: .acceptCurrentClearView,
            title: "Accept Clear Pose",
            role: .positive,
            unavailableReason: pendingClearViewLabel == .clear
              ? nil : "Record a Clear exact-frame observation first."
          )
        )
      } else if case .observedDrawingTrial(.compareIntendedAndObservedGeometry) = itemID {
        actions.append(contentsOf: DrawingTrialAssessment.allCases.map { assessment in
          ExerciseActionDescriptor(
            kind: .recordDrawingTrialAssessment(assessment),
            title: assessment.title,
            role: assessment == .observedGeometryAccepted ? .positive : .standard
          )
        })
      } else if let sequenceID = activeDiscoverySequenceID,
        let choices = discoveryTransactions[sequenceID]?.currentStep?.question?.choices
      {
        actions.append(contentsOf: choices.map { choice in
          ExerciseActionDescriptor(
            kind: .choice(choice),
            title: choice.exactPhrase,
            role: choice == .yes ? .positive : .standard
          )
        })
      }
      actions.append(
        ExerciseActionDescriptor(kind: .cancel, title: "Cancel", role: .destructive)
      )
      if contextualStopPresentation != nil {
        actions.append(
          ExerciseActionDescriptor(kind: .stop, title: "Stop", role: .destructive)
        )
      }
      return ExerciseActionStripPresentation(
        ownerID: itemID,
        actions: actions,
        directionSelection: itemID == .humanGuidedDiscovery(.boundaryDiscovery)
          ? ExerciseDirectionSelectionPresentation(selected: selectedBoundaryDirection) : nil
      )
    }

    if restartableExerciseItemID == itemID {
      guard machineSnapshot?.machine.stickyAmbiguity == nil else { return nil }
      return ExerciseActionStripPresentation(
        ownerID: itemID,
        actions: [
          ExerciseActionDescriptor(
            kind: .restart,
            title: "Restart",
            role: .positive
          )
        ]
      )
    }

    if itemIsComplete(itemID), itemID.isExercise {
      var actions = [
        ExerciseActionDescriptor(kind: .redoThisStep, title: "Redo This Step")
      ]
      if itemIsRepeatable(itemID) {
        actions.append(
          ExerciseActionDescriptor(
            kind: .recordAnotherAttempt,
            title: "Record Another Attempt"
          )
        )
      }
      return ExerciseActionStripPresentation(
        ownerID: itemID,
        actions: actions,
        directionSelection: itemID == .humanGuidedDiscovery(.boundaryDiscovery)
          ? ExerciseDirectionSelectionPresentation(selected: selectedBoundaryDirection) : nil
      )
    }

    guard itemID == currentLearningPathItemID else { return nil }
    let reason: String?
    switch itemID {
    case .humanGuidedDiscovery(.penInteraction):
      reason = discoveryStartUnavailableReason(for: .penInteraction)
    case .humanGuidedDiscovery(.boundaryDiscovery):
      reason = discoveryStartUnavailableReason(for: sequenceID(for: selectedBoundaryDirection))
    case .humanGuidedDiscovery(.clearViewDiscovery):
      reason = frameMode == .simulated || cameraIsLive
        ? nil : "A current LIVE camera frame is required."
    case .observedDrawingTrial(let step):
      reason = drawingTrialActionUnavailableReason(for: step)
    case .stage:
      return nil
    }
    return ExerciseActionStripPresentation(
      ownerID: itemID,
      actions: [
        ExerciseActionDescriptor(
          kind: .start,
          title: "Start",
          role: .positive,
          unavailableReason: reason
        )
      ],
      directionSelection: itemID == .humanGuidedDiscovery(.boundaryDiscovery)
        ? ExerciseDirectionSelectionPresentation(selected: selectedBoundaryDirection) : nil
    )
  }

  private func stageExpectedObservation(_ stage: LearningPathStage) -> [PresentationFragment] {
    switch stage {
    case .connect: [.text("A responsive selected controller session.")]
    case .enableMotion: [.text("The current session reports Motion Enabled.")]
    case .humanGuidedDiscovery: [.cue(.up), .text("boundary evidence, and a Clear view.")]
    case .observedDrawingTrials: [.text("Observed ink and a typed geometry comparison.")]
    case .adaptiveDrawing: [.text("Future multi-stroke observed adaptation.")]
    }
  }

  private func stageEvidence(_ stage: LearningPathStage) -> [ExerciseEvidencePresentation] {
    switch stage {
    case .connect:
      [ExerciseEvidencePresentation(label: "Controller", fragments: [.text(controllerConnectionText)])]
    case .enableMotion:
      [ExerciseEvidencePresentation(label: "Motion", fragments: [.text(motionGuardStateText)])]
    case .humanGuidedDiscovery:
      [ExerciseEvidencePresentation(label: "Boundary samples", fragments: [.text("N=\(relevantBoundaryObservationCount)")])]
    case .observedDrawingTrials:
      [ExerciseEvidencePresentation(label: "Ink", fragments: [.text(explorationInkStatus)])]
    case .adaptiveDrawing:
      []
    }
  }

  private func discoveryReviewInstructions(
    _ step: HumanGuidedDiscoveryStep
  ) -> [PresentationFragment] {
    switch step {
    case .penInteraction:
      [.text("Confirm"), .cue(.up), .text("then"), .cue(.down), .text("then finish"), .cue(.up)]
    case .boundaryDiscovery:
      [.text("Choose a direction, observe the side, then press"), .cue(.stop)]
    case .clearViewDiscovery:
      [.text("Record an exact Clear-view observation.")]
    }
  }

  private func discoveryReviewExpectation(
    _ step: HumanGuidedDiscoveryStep
  ) -> [PresentationFragment] {
    switch step {
    case .penInteraction: [.text("Latest accepted physical pose is"), .cue(.up)]
    case .boundaryDiscovery: [.text("Idle/final MPos followed by one strictly newer exact frame.")]
    case .clearViewDiscovery: [.text("One accepted Clear pose with exact frame provenance.")]
    }
  }

  private func discoveryInstructionFragments(
    _ action: DiscoveryAction
  ) -> [PresentationFragment] {
    switch action {
    case .startBoundaryJog(let direction): [.text("Start motion toward"), .cue(.direction(direction))]
    case .awaitContextualStop(let direction): [.text("Observe"), .cue(.direction(direction)), .text("and press"), .cue(.stop)]
    case .awaitPhysicalPenConfirmation(let state, _): [.text("Confirm the pen is physically"), .cue(state == .up ? .up : .down)]
    case .actuatePen(let command): [.text("Command pen"), .cue(command.commandedState == .up ? .up : .down)]
    default: [.text(discoveryActionText(action))]
    }
  }

  private func discoveryExpectationFragments(
    _ expectation: DiscoveryEventExpectation
  ) -> [PresentationFragment] {
    switch expectation {
    case .operatorChoice: [.cue(.yes), .text("or"), .cue(.no), .text("is recorded for this question.")]
    case .operatorStopRequested: [.cue(.stop), .text("is latched before cancellation.")]
    case .physicalPenConfirmed(let state, _): [.text("The operator confirms"), .cue(state == .up ? .up : .down)]
    default: [.text(discoveryExpectationText(expectation))]
    }
  }

  private func discoveryQuestionFragments(_ action: DiscoveryAction) -> [PresentationFragment] {
    switch action {
    case .awaitOperatorChoice:
      [.text("Choose"), .cue(.yes), .text("or"), .cue(.no)]
    case .awaitPhysicalPenConfirmation(let state, _):
      [.text("Is the pen physically"), .cue(state == .up ? .up : .down), .text("?")]
    default:
      []
    }
  }

  private func discoveryEvidence(
    _ transaction: DiscoveryTransaction?
  ) -> [ExerciseEvidencePresentation] {
    transaction?.evidenceSummaries.enumerated().map { index, evidence in
      ExerciseEvidencePresentation(
        label: "Evidence \(index + 1)",
        fragments: [.text(evidence.summary)]
      )
    } ?? []
  }

  private func drawingTrialInstructionFragments(
    for step: ObservedDrawingTrialStep
  ) -> [PresentationFragment] {
    [.text(drawingTrialActionText(for: step))]
  }

  private func drawingTrialExpectationFragments(
    for step: ObservedDrawingTrialStep
  ) -> [PresentationFragment] {
    [.text(drawingTrialExpectationText(for: step))]
  }

  private func drawingTrialEvidence(
    for step: ObservedDrawingTrialStep
  ) -> [ExerciseEvidencePresentation] {
    switch step {
    case .captureCleanReference:
      [ExerciseEvidencePresentation(label: "Reference", fragments: [.text(explorationCleanReference?.frame.id.rawValue ?? "not captured")])]
    case .chooseLineStart:
      [ExerciseEvidencePresentation(label: "Line start", fragments: [.text(drawingTrialLineStart.map { String(format: "X %.3f Y %.3f", $0.point.x, $0.point.y) } ?? "not chosen")])]
    case .createAnchorMark:
      [ExerciseEvidencePresentation(label: "Anchor", fragments: [.text(lastAnchorObservation == nil ? "not observed" : "observed")])]
    case .drawIsolatedLine:
      [ExerciseEvidencePresentation(label: "Controller", fragments: [.text(drawingTrialStrokeEvidence == nil ? "not settled" : "settled")])]
    case .clearToolAndObserveInk:
      [ExerciseEvidencePresentation(label: "Ink", fragments: [.text(explorationInkStatus)])]
    case .compareIntendedAndObservedGeometry:
      [ExerciseEvidencePresentation(label: "Comparison", fragments: [.text(drawingTrialAssessment?.title ?? "not recorded")])]
    }
  }

  private func drawingArtifactRevision(
    for step: ObservedDrawingTrialStep
  ) -> LearningArtifactRevision? {
    let kind: LearningArtifactKind = switch step {
    case .captureCleanReference: .cleanReference(currentDrawingTrialGroup)
    case .chooseLineStart: .lineStart(currentDrawingTrialGroup)
    case .createAnchorMark: .anchorMark(currentDrawingTrialGroup)
    case .drawIsolatedLine: .isolatedLine(currentDrawingTrialGroup)
    case .clearToolAndObserveInk: .postFrame(currentDrawingTrialGroup)
    case .compareIntendedAndObservedGeometry: .comparison(currentDrawingTrialGroup)
    }
    return learningArtifactGraph.currentRevision(for: kind)
  }

  private func jogDirection(for sequenceID: DiscoverySequenceID) -> JogDirection? {
    switch sequenceID {
    case .boundaryNegativeX: .xNegative
    case .boundaryPositiveX: .xPositive
    case .boundaryNegativeY: .yNegative
    case .boundaryPositiveY: .yPositive
    case .penInteraction: nil
    }
  }

  private func jogDirection(from direction: BoundaryDirection) -> JogDirection {
    switch direction {
    case .negativeX: .xNegative
    case .positiveX: .xPositive
    case .negativeY: .yNegative
    case .positiveY: .yPositive
    }
  }

  private func boundaryDirection(from direction: JogDirection)
    -> BoundaryDirection
  {
    switch direction {
    case .xNegative: .negativeX
    case .xPositive: .positiveX
    case .yNegative: .negativeY
    case .yPositive: .positiveY
    }
  }

  private func receiveVision(_ result: PlotterSceneAnalysisResult) {
    guard frameMode == .live, automaticVisionEnabled else { return }
    displayedFrame = result.displayedFrame
    lastSceneMeasurement = result.measurement
    cameraOverlays = result.measurement.overlays
  }

  private func updateCameraError() {
    cameraError = cameraSnapshot?.error?.actionableDescription
  }

  private func validatedLiveCameraFrame(in snapshot: CameraCaptureSnapshot) -> DisplayedFrame? {
    guard let frame = snapshot.latestFrame,
      case .live(let deviceID) = frame.source,
      deviceID == snapshot.selectedDeviceID
    else { return nil }
    return frame
  }

  private func clearMachineAuthority(clearSelection: Bool) async {
    if clearSelection { selectedSerialDevice = nil }
    passiveProbeResult = nil
    machineSnapshot = nil
    machineError = nil
    passiveProbeInProgress = false
    jogRequestInProgress = false
    penRequestInProgress = false
    jogCancelRequestInProgress = false
    motionGuardActivationInProgress = false
    lastMotionGuardActivationText = "not activated"
    boundaryTeachingState = .idle
    boundaryTeachingResultText = "Choose one side to begin."
    boundaryPositions = [:]
    await clearDiscoveryAuthority()
  }

  private var controllerLinkIsOpen: Bool {
    guard let connection = machineSnapshot?.machine.connection else { return false }
    switch connection {
    case .connecting, .connected, .probing, .moving, .actuatingPen:
      return true
    case .disconnected, .blocked:
      return false
    }
  }

  private func clearDiscoveryAuthority() async {
    await cancelAndSettleDiscoveryMotionBeforeErasure()
    selectedDiscoverySequenceID = .penInteraction
    discoveryTransactions = [:]
    discoveryError = nil
    drawingFramePosterior = nil
    boundaryFrameObservationsByAttemptID = [:]
    boundaryDerivedValueSnapshot = nil
    pendingDiscoveryInspection = nil
    pendingDiscoveryCaptureBoundaryNanoseconds = nil
    clearViewPoseAccepted = false
    pendingClearViewLabel = nil
    armatureGuidanceState = nil
    lastArmatureObservation = nil
    observedDrawingTrialStep = .captureCleanReference
    drawingTrialAssessment = nil
    drawingTrialLineStart = nil
    drawingTrialStrokeEvidence = nil
    explorationCleanReference = nil
    explorationAnchoredBaseline = nil
    explorationPostLineFrame = nil
    lastAnchorObservation = nil
    lastInkObservation = nil
    currentExplorationEpisode = nil
    learningArtifactGraph = LearningDependencyGraph()
    penAttemptHistory = try! ExerciseAttemptHistory(
      compatibility: penAttemptHistory.compatibility
    )
    boundaryAttemptHistories = [:]
    clearViewAttemptHistories = [:]
    comparisonAttemptHistories = [:]
    activeExerciseAttemptID = nil
    activeExerciseAttemptOwnerID = nil
    activeExerciseAttemptMode = nil
    restartableExerciseItemID = nil
    currentDrawingTrialGroup = AttemptGroupIdentity(
      rawValue: UUID().uuidString.lowercased()
    )
  }

  private func cancelAndSettleDiscoveryMotionBeforeErasure() async {
    guard boundaryTeachingState != .idle || boundaryMotionTask != nil else { return }

    if let target = activeStopTarget {
      if let sequenceID = activeDiscoverySequenceID,
        var transaction = discoveryTransactions[sequenceID]
      {
        transaction.cancel()
        discoveryTransactions[sequenceID] = transaction
      }
      await requestSingleJogCancel(for: target, intent: .cancelAttempt)
    }
    let motionTask = boundaryMotionTask
    await motionTask?.value
    if let sequenceID = activeDiscoverySequenceID,
      var transaction = discoveryTransactions[sequenceID]
    {
      transaction.cancel()
      discoveryTransactions[sequenceID] = transaction
    }
  }

  /// Shutdown first closes the admission boundary, then settles the already
  /// latched motion owner. This bypasses normal intent admission without
  /// exposing a second cancellation route to the UI.
  private func stopAndSettleActiveMotionForShutdown() async {
    guard let target = activeStopTarget else { return }

    let owner: Task<Void, Never>?
    switch target {
    case .boundaryDiscovery(let transactionID, let direction):
      let sequenceID = sequenceID(for: direction)
      if discoveryTransactions[sequenceID]?.id == transactionID,
        var transaction = discoveryTransactions[sequenceID]
      {
        transaction.cancel()
        discoveryTransactions[sequenceID] = transaction
        boundaryTeachingState = .cancelling(jogDirection(from: direction))
        boundaryTeachingResultText =
          "Shutdown requested. Waiting for the original motion owner to reach Idle."
      }
      owner = boundaryMotionTask
    case .manualJog:
      owner = manualJogTask.map { task in Task { _ = await task.value } }
    case .drawingTrial:
      owner = drawingTrialTask.map { task in Task { _ = await task.value } }
    }

    if stopRequestIssuedForTarget != target, let machineActions {
      stopRequestIssuedForTarget = target
      jogCancelRequestInProgress = true
      _ = await machineActions.requestJogCancel(.shutdown)
      jogCancelRequestInProgress = false
    }
    await owner?.value
    activeStopTarget = nil
    stopRequestIssuedForTarget = nil
    boundaryTeachingState = .idle
  }

  private func clearCameraAuthority() async {
    frameMode = .live
    cameraSnapshot = nil
    displayedFrame = nil
    latestLiveCameraFrame = nil
    cameraOverlays = []
    await clearDiscoveryAuthority()
    cameraError = nil
    visionError = nil
    analysisFrameHeld = false
    automaticVisionEnabled = false
    visionAnalysisSnapshot = .stopped
    lastSceneMeasurement = nil
    lastCameraSnapshotPath = nil
    simulatorPenState = .unknown
    simulatorLearningSummary = "Switch to SIMULATED to inspect model behavior."
  }

  private func announceAdvisory(_ message: String) async -> SpeechAnnouncementOutcome {
    guard let announcementActions else {
      lastAnnouncementResultText = "Announcement unavailable; continuing with the visible action."
      return .failed("Native speech output is unavailable.")
    }
    let outcome = await announcementActions.announce(message)
    lastAnnouncementResultText = switch outcome {
    case .completed: "Announcement completed."
    case .failed(let reason): "Announcement failed: \(reason). Continuing."
    case .timedOut: "Announcement timed out. Continuing."
    case .cancelled: "Announcement cancelled during shutdown."
    }
    return outcome
  }

  private func positiveFallbackTravelFeed() -> Double {
    guard let feed = inputNumber(feedText), feed > 0 else { return 100 }
    return feed
  }

  private func travelFeedSelection(
    for delta: Vector2<MachineSpace>
  ) -> TravelFeedSelection {
    if let ceiling = machineSnapshot?.machine.controllerAxisFeedLimits?
      .applicableFeedCeiling(for: delta)
    {
      return TravelFeedSelection(
        requestedFeedMMPerMinute: ceiling,
        source: .controllerReportedCeiling
      )
    }
    return TravelFeedSelection(
      requestedFeedMMPerMinute: positiveFallbackTravelFeed(),
      source: .existingFallback
    )
  }

  private func sequenceID(for direction: BoundaryDirection) -> DiscoverySequenceID {
    switch direction {
    case .negativeX: .boundaryNegativeX
    case .positiveX: .boundaryPositiveX
    case .negativeY: .boundaryNegativeY
    case .positiveY: .boundaryPositiveY
    }
  }

  private func boundaryDirection(for sequenceID: DiscoverySequenceID) -> BoundaryDirection? {
    switch sequenceID {
    case .boundaryNegativeX: .negativeX
    case .boundaryPositiveX: .positiveX
    case .boundaryNegativeY: .negativeY
    case .boundaryPositiveY: .positiveY
    case .penInteraction: nil
    }
  }

  private func boundaryFeedVector(_ direction: BoundaryDirection) -> Vector2<MachineSpace> {
    switch direction {
    case .negativeX: try! Vector2(dx: -1, dy: 0)
    case .positiveX: try! Vector2(dx: 1, dy: 0)
    case .negativeY: try! Vector2(dx: 0, dy: -1)
    case .positiveY: try! Vector2(dx: 0, dy: 1)
    }
  }

  private func discoveryActionText(_ action: DiscoveryAction) -> String {
    switch action {
    case .askQuestion(let question): question.prompt
    case .awaitOperatorChoice(let question): "Choose \(question.choiceLabel) for this question."
    case .announce(let message): "Announce: \(message)"
    case .startBoundaryJog(let direction):
      "Start the logical \(direction.displayName) Boundary Discovery owner."
    case .awaitContextualStop: "Observe the boundary and use the contextual Stop."
    case .cancelBoundaryJogAndAwaitIdle: "Send one jog cancel and await the original motion owner."
    case .captureFreshCameraFrame: "Capture an exact frame newer than the settled operation."
    case .measureBoundary(let direction): "Measure the \(direction.displayName) boundary on that frame."
    case .adjustDrawingFramePosterior(let direction):
      "Update the \(direction.displayName) drawing-frame side posterior."
    case .actuatePen(let command): "Command Pen \(command.commandedState.rawValue)."
    case .awaitPhysicalPenConfirmation(let state, _):
      "Confirm whether the pen is physically \(state.rawValue)."
    }
  }

  private func discoveryExpectationText(_ expectation: DiscoveryEventExpectation) -> String {
    switch expectation {
    case .questionPresented: "The contextual question is visible."
    case .operatorChoice: "One contextual YES or NO choice is recorded."
    case .announcementCompleted: "Speech output completes or reaches its advisory bound."
    case .boundaryJogStarted:
      "The logical boundary owner is active while direct controller admission remains runtime-owned."
    case .operatorStopRequested: "Stop is recorded before cancellation begins."
    case .boundaryJogCancelled: "The original motion owner reaches Idle with final MPos."
    case .freshFrameCaptured: "The exact captured frame is strictly newer."
    case .boundaryMeasured: "The boundary observation pairs exact image and controller evidence."
    case .drawingFramePosteriorAdjusted: "One side posterior is updated from that evidence."
    case .penCommandSettled: "The typed pen command and dwell settle."
    case .physicalPenConfirmed: "The operator confirms the visible physical pen pose."
    }
  }

  private func drawingTrialParticipant(for step: ObservedDrawingTrialStep) -> String {
    switch step {
    case .captureCleanReference, .clearToolAndObserveInk: "Camera and Vision"
    case .chooseLineStart: "Operator"
    case .createAnchorMark, .drawIsolatedLine: "Plotter controller"
    case .compareIntendedAndObservedGeometry: "Operator"
    }
  }

  private func drawingTrialActionText(for step: ObservedDrawingTrialStep) -> String {
    switch step {
    case .captureCleanReference: "Capture one exact clean reference at the accepted clear view."
    case .chooseLineStart: "Record the current Pen Up MPos as the isolated-line start."
    case .createAnchorMark:
      "Perform one closed Pen Down/Up interaction, return clear, and observe the anchor."
    case .drawIsolatedLine:
      "Return Pen Up to the start, lower, draw one fixed short stroke, and raise."
    case .clearToolAndObserveInk:
      "Return clear, settle, capture a strictly newer frame, and extract new ink."
    case .compareIntendedAndObservedGeometry:
      "Record one typed comparison for this local trial; no redraw follows."
    }
  }

  private func drawingTrialExpectationText(for step: ObservedDrawingTrialStep) -> String {
    switch step {
    case .captureCleanReference: "An exact clean frame with retained configuration provenance."
    case .chooseLineStart: "One current controller MPos while Pen Up."
    case .createAnchorMark: "Observed anchor ink on a newer exact frame; controller completion alone is not a mark."
    case .drawIsolatedLine: "A closed controller stroke outcome; this is not yet ink proof."
    case .clearToolAndObserveInk: "Observed new ink or a typed unclear/rejected observation, with no automatic redraw."
    case .compareIntendedAndObservedGeometry: "One typed operator assessment completes only this trial."
    }
  }

  private func drawingTrialActionUnavailableReason(
    for step: ObservedDrawingTrialStep
  ) -> String? {
    if explorationOperationInProgress { return "The current learning action is still in progress." }
    if frameMode == .simulated {
      return cameraActions == nil ? "The simulator camera composition is unavailable." : nil
    }
    guard controllerIsConnected else { return "Connect the selected controller first." }
    guard motionGuardIsActive else { return "Enable Motion first." }
    if step != .compareIntendedAndObservedGeometry,
      machineSnapshot?.machine.penState != .up
    {
      return "The current commanded pen state must be Up."
    }
    switch step {
    case .captureCleanReference, .createAnchorMark, .clearToolAndObserveInk:
      if !cameraIsLive { return "A current LIVE camera frame is required." }
    case .chooseLineStart, .drawIsolatedLine, .compareIntendedAndObservedGeometry:
      break
    }
    if step == .chooseLineStart || step == .createAnchorMark || step == .drawIsolatedLine,
      machineSnapshot?.machine.position == nil
    {
      return "A current controller MPos is required."
    }
    return nil
  }

  private func advanceDrawingTrial(to step: ObservedDrawingTrialStep) {
    observedDrawingTrialStep = step
  }

  private func captureDrawingTrialCleanReference() async throws {
    guard let cameraActions else { throw LearningPathOperationError.freshFrameUnavailable }
    let frame: DisplayedFrame
    if frameMode == .simulated {
      frame = try await cameraActions.simulatedExplorationFrames().cleanReference
    } else {
      guard machineSnapshot?.machine.penState == .up,
        let captured = try await cameraActions.captureFrame(
          displayedFrame?.frame.captureNanoseconds ?? 0
        )
      else { throw LearningPathOperationError.freshFrameUnavailable }
      frame = captured
    }
    explorationCleanReference = frame
    displayedFrame = frame
    currentExplorationEpisode = ExplorationEpisode(
      sessionID: learningEvidenceSessionID,
      rung: .observedDrawingTrial,
      source: frameMode == .simulated ? .simulated : .live,
      split: .training,
      startedNanoseconds: nowNanoseconds()
    )
    appendFrameEvidence(.cleanReference, frame: frame.frame)
  }

  private func recordDrawingTrialLineStart() throws {
    let position: MachinePosition?
    if frameMode == .simulated {
      position = if let currentPosition = machineSnapshot?.machine.position {
        currentPosition
      } else {
        try MachinePosition(x: 0, y: 0)
      }
    } else {
      position = machineSnapshot?.machine.position
    }
    guard let position else {
      throw LearningPathOperationError.requiredState("Current controller MPos is unavailable.")
    }
    drawingTrialLineStart = position
    currentExplorationEpisode?.lineStartPosition = position
  }

  private func createDrawingTrialAnchor() async throws {
    guard let cameraActions, let clean = explorationCleanReference else {
      throw LearningPathOperationError.requiredState("Clean reference is unavailable.")
    }
    let anchored: DisplayedFrame
    if frameMode == .simulated {
      anchored = try await cameraActions.simulatedExplorationFrames().anchoredBaseline
    } else {
      guard let machineActions else {
        throw LearningPathOperationError.requiredState("Machine composition is unavailable.")
      }
      _ = await announceAdvisory("Lowering the pen to create one anchor mark.")
      let lower = await machineActions.requestPenActuation(.lower)
      machineSnapshot = await machineActions.snapshot()
      guard case .commandedAndSettled = lower else {
        throw LearningPathOperationError.controllerOutcome(String(describing: lower))
      }
      _ = await announceAdvisory("Raising the pen after the anchor mark.")
      let raise = await machineActions.requestPenActuation(.raise)
      machineSnapshot = await machineActions.snapshot()
      guard case .commandedAndSettled = raise else {
        throw LearningPathOperationError.controllerOutcome(String(describing: raise))
      }
      try await returnToAcceptedClearPose()
      guard let captured = try await cameraActions.captureFrame(clean.frame.captureNanoseconds),
        captured.frame.captureNanoseconds > clean.frame.captureNanoseconds
      else { throw LearningPathOperationError.freshFrameUnavailable }
      anchored = captured
    }
    let region = armatureGuidanceState?.context.observationRegion
      ?? defaultInkRegion(for: clean.frame)
    let outcome = await cameraActions.observeAnchorDot(
      AnchorDotObservationRequest(
        cleanReference: clean.frame,
        anchoredBaseline: anchored.frame,
        region: region,
        thresholds: GreenPixelThresholds(minimumGreen: 75, minimumGreenExcess: 20),
        algorithmRevision: "isolated-ink-v1"
      )
    )
    guard case .observed(let observation) = outcome else {
      if case .rejected(let rejection) = outcome {
        throw LearningPathOperationError.anchorRejected(String(describing: rejection.reason))
      }
      throw LearningPathOperationError.anchorRejected("No anchor observation.")
    }
    explorationAnchoredBaseline = anchored
    lastAnchorObservation = observation
    displayedFrame = anchored
    cameraOverlays = [observation.overlay]
    appendFrameEvidence(.anchoredBaseline, frame: anchored.frame)
    currentExplorationEpisode?.anchorDotCentroid = observation.centroid
  }

  private func movePenUp(to destination: MachinePosition, announcement: String) async throws {
    guard let machineActions, let current = machineSnapshot?.machine.position else {
      throw LearningPathOperationError.requiredState("Current controller MPos is unavailable.")
    }
    if current == destination { return }
    let delta = try Vector2<MachineSpace>(
      dx: destination.point.x - current.point.x,
      dy: destination.point.y - current.point.y
    )
    let selection = travelFeedSelection(for: delta)
    lastTravelFeedSelection = selection
    _ = await announceAdvisory(announcement)
    let outcome = await machineActions.requestRelativeJog(
      RelativeJogRequest(delta: delta, feedMMPerMinute: selection.requestedFeedMMPerMinute)
    )
    machineSnapshot = await machineActions.snapshot()
    guard case .acceptedThenCompleted(let final) = outcome, final == destination else {
      throw LearningPathOperationError.controllerOutcome(String(describing: outcome))
    }
  }

  private func drawIsolatedTrialLine() async throws {
    if frameMode == .simulated { return }
    guard let machineActions, let start = drawingTrialLineStart else {
      throw LearningPathOperationError.requiredState("Recorded line start is unavailable.")
    }
    try await movePenUp(to: start, announcement: "Moving the raised pen to the selected line start.")
    _ = await announceAdvisory("Lowering the pen for the isolated line.")
    let lower = await machineActions.requestPenActuation(.lower)
    machineSnapshot = await machineActions.snapshot()
    guard case .commandedAndSettled = lower else {
      throw LearningPathOperationError.controllerOutcome(String(describing: lower))
    }

    let request = DrawingStrokeRequest(
      delta: try Vector2(dx: 5, dy: 0),
      feedMMPerMinute: positiveFallbackTravelFeed()
    )
    _ = await announceAdvisory("Drawing one isolated line.")
    let owner = Task { await machineActions.requestDrawingStroke(request) }
    drawingTrialTask = owner
    activeStopTarget = .drawingTrial
    stopRequestIssuedForTarget = nil
    let outcome = await owner.value
    drawingTrialTask = nil
    activeStopTarget = nil
    stopRequestIssuedForTarget = nil
    machineSnapshot = await machineActions.snapshot()
    switch outcome {
    case .completed(let evidence):
      drawingTrialStrokeEvidence = evidence
      recordStrokeEvidence(evidence, outcome: .completed, summary: "Idle with final MPos")
      _ = await announceAdvisory("Raising the pen after the isolated line.")
      let raise = await machineActions.requestPenActuation(.raise)
      machineSnapshot = await machineActions.snapshot()
      guard case .commandedAndSettled = raise else {
        throw LearningPathOperationError.controllerOutcome(String(describing: raise))
      }
    case .cancelled(let evidence, let penRaiseOutcome):
      drawingTrialStrokeEvidence = evidence
      recordStrokeEvidence(evidence, outcome: .cancelled, summary: "Stop settled in place")
      throw LearningPathOperationError.controllerOutcome(
        "Drawing stopped; controller Pen Up outcome: \(penRaiseOutcome)"
      )
    case .ambiguous(let ambiguity):
      throw LearningPathOperationError.controllerOutcome(ambiguity.actionableDescription)
    case .refused(let refusal):
      throw LearningPathOperationError.controllerOutcome(String(describing: refusal))
    }
  }

  private func clearToolAndObserveTrialInk() async throws {
    guard let cameraActions, let clean = explorationCleanReference,
      let anchored = explorationAnchoredBaseline
    else { throw LearningPathOperationError.requiredState("Trial frame pair is unavailable.") }
    let post: DisplayedFrame
    if frameMode == .simulated {
      post = try await cameraActions.simulatedExplorationFrames().postLine
    } else {
      try await returnToAcceptedClearPose()
      let boundary = max(
        anchored.frame.captureNanoseconds,
        drawingTrialStrokeEvidence?.finalSampleNanoseconds ?? 0
      )
      guard let captured = try await cameraActions.captureFrame(boundary),
        captured.frame.captureNanoseconds > boundary
      else { throw LearningPathOperationError.freshFrameUnavailable }
      post = captured
    }
    explorationPostLineFrame = post
    displayedFrame = post
    appendFrameEvidence(.postLine, frame: post.frame)
    let outcome = await cameraActions.observeIsolatedInk(
      IsolatedInkObservationRequest(
        cleanReference: clean.frame,
        anchoredBaseline: anchored.frame,
        postLine: post.frame,
        region: armatureGuidanceState?.context.observationRegion
          ?? defaultInkRegion(for: post.frame),
        thresholds: GreenPixelThresholds(minimumGreen: 75, minimumGreenExcess: 20),
        projectedActualStrokeDelta: nil,
        algorithmRevision: "isolated-ink-v1"
      )
    )
    switch outcome {
    case .observed(let observation):
      acceptInkObservation(observation)
    case .rejected(let rejection):
      lastInkObservation = nil
      explorationInkStatus = "ink or geometry unclear: \(rejection.reason); no redraw requested"
      cameraOverlays = []
      throw LearningPathOperationError.inkRejected(String(describing: rejection.reason))
    }
  }

  private func clearAutomaticVisionPresentation() {
    visionUpdateTask?.cancel()
    visionUpdateTask = nil
    automaticVisionEnabled = false
    visionAnalysisSnapshot = .stopped
    visionError = nil
    analysisFrameHeld = false
    lastSceneMeasurement = nil
    cameraOverlays = []
  }

  private func beginHardwareIntent() -> UInt64? {
    guard !hasShutdown else { return nil }
    activeHardwareIntentCount += 1
    return lifetimeGeneration
  }

  private func endHardwareIntent() {
    precondition(activeHardwareIntentCount > 0)
    activeHardwareIntentCount -= 1
    guard activeHardwareIntentCount == 0 else { return }
    let waiters = intentDrainWaiters
    intentDrainWaiters.removeAll(keepingCapacity: false)
    for waiter in waiters { waiter.resume() }
  }

  private func canCommit(_ generation: UInt64) -> Bool {
    !hasShutdown && lifetimeGeneration == generation
  }

  private func waitForHardwareIntentsToDrain() async {
    guard activeHardwareIntentCount > 0 else { return }
    await withCheckedContinuation { continuation in
      intentDrainWaiters.append(continuation)
    }
  }

  private func inputNumber(_ text: String) -> Double? {
    guard let value = Double(text.trimmingCharacters(in: .whitespacesAndNewlines)),
      value.isFinite
    else { return nil }
    return value
  }

  private func actionableDescription(_ error: any Error) -> String {
    if let cameraError = error as? CameraCaptureError {
      return cameraError.actionableDescription
    }
    if let localized = error as? LocalizedError,
      let description = localized.errorDescription
    {
      return description
    }
    return String(describing: error)
  }

}

private extension Array {
  var onlyElement: Element? { count == 1 ? self[0] : nil }
}

func machineBlockerLabel(_ blocker: MachineBlocker) -> String {
  switch blocker {
  case .noSerialDevice: "No serial device is selected."
  case let .multipleSerialDevices(devices): "Select one of \(devices.count) serial devices."
  case let .transport(reason): "Controller transport: \(reason)"
  case let .timeout(query): "Controller timed out during \(query.rawValue)."
  case let .invalidReply(query, reason): "Invalid \(query.rawValue) reply: \(reason)"
  case let .responseLimitExceeded(query, maximumBytes, maximumChunks):
    "\(query.rawValue) exceeded \(maximumBytes) bytes or \(maximumChunks) chunks."
  case let .controllerAlarm(code): "Controller alarm: \(code)"
  case let .controllerError(code): "Controller error: \(code)"
  }
}
