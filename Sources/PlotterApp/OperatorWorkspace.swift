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
  case moving(JogDirection)
  case cancelling(JogDirection)

  var direction: JogDirection? {
    switch self {
    case .idle: nil
    case .awaitingConfirmation(let direction), .moving(let direction), .cancelling(let direction):
      direction
    }
  }
}

enum ContextualStopTarget: Hashable, Sendable {
  case boundaryDiscovery(transactionID: UUID, direction: BoundaryDirection)
  case manualJog
  case observedJog
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
  private enum JogOwnerResult: Sendable {
    case manual(MotionOutcome)
    case observed(PhysicalJogObservationOutcome)
  }

  private enum MotionPriors {
    static let stepMM = "1.0"
    static let feedMMPerMinute = "100"
    static let boundarySearchXDistanceMM = 300.0
    static let boundarySearchYDistanceMM = 150.0
  }

  struct MachineActions: Sendable {
    let select: @Sendable (MachineLinkDescriptor) async throws -> RunInterpreterSnapshot
    let snapshot: @Sendable () async -> RunInterpreterSnapshot?
    let requestPassiveProbe: @Sendable () async throws -> PassiveProbeResult
    let activateMotionGuard: @Sendable () async -> MotionGuardActivationOutcome
    let deactivateMotionGuard: @Sendable () async -> Void
    let requestRelativeJog: @Sendable (RelativeJogRequest) async -> MotionOutcome
    let requestDrawingStroke: @Sendable (DrawingStrokeRequest) async -> DrawingStrokeOutcome
    let requestObservedJog: @Sendable (
      PhysicalJogObservationRequest,
      @Sendable (PhysicalObservationPhase, UInt64) async
        -> Result<VisibleToolFrameObservation, PhysicalJogObservationFailure>
    ) async -> PhysicalJogObservationOutcome
    let requestPenActuation: @Sendable (PenCommand) async -> PenOutcome
    let requestJogCancel: @Sendable () async -> JogCancelOutcome
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
    let observeVisibleTool: @Sendable (PhysicalObservationPhase, UInt64) async
      -> Result<VisibleToolFrameObservation, PhysicalJogObservationFailure>
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
  private(set) var recordJogObservations = false
  private(set) var selectedObservationSplit: ModelObservationSplit = .training

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
  private(set) var physicalJogObservations: [PhysicalJogObservation] = []
  private(set) var jogResponseDataset: OnlineJogResponseDataset?
  private(set) var jogResponseCandidate: JogResponseCandidate?
  private(set) var jogResponseLearnerError: String?

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
  private(set) var learningPathFlow = LearningPathFlowCoordinator()
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
  @ObservationIgnored private var manualJogTask: Task<JogOwnerResult, Never>?
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
    case .observedJog: "observed relative jog"
    case .drawingStroke: "isolated drawing stroke"
    case .penActuation(let command): "pen \(command.rawValue)"
    }
  }

  var physicalJogObservationCountText: String {
    "\(physicalJogObservations.count)"
  }

  var jogResponseDatasetCountText: String {
    guard let summary = jogResponseDataset?.summary else { return "training 0 · holdout 0" }
    return "training \(summary.trainingCount) · holdout \(summary.holdoutCount)"
  }

  var jogResponseMatrixText: String {
    guard let matrix = jogResponseCandidate?.matrix else { return "unavailable" }
    return String(
      format: "[%.4f  %.4f;  %.4f  %.4f] px/mm",
      matrix.cameraXPerMachineX,
      matrix.cameraXPerMachineY,
      matrix.cameraYPerMachineX,
      matrix.cameraYPerMachineY
    )
  }

  var jogResponseTrainingResidualText: String {
    guard let metrics = jogResponseCandidate?.trainingMetrics else { return "unavailable" }
    return String(
      format: "RMS %.3f px · max %.3f px · n %d",
      metrics.rootMeanSquarePixels,
      metrics.maximumPixels,
      metrics.episodeCount
    )
  }

  var jogResponseHoldoutResidualText: String {
    guard let metrics = jogResponseCandidate?.holdoutMetrics else { return "none" }
    return String(
      format: "RMS %.3f px · max %.3f px · n %d",
      metrics.rootMeanSquarePixels,
      metrics.maximumPixels,
      metrics.episodeCount
    )
  }

  var clearJogObservationSamplesUnavailableReason: String? {
    jogRequestInProgress ? "Wait for the current jog to finish before clearing samples." : nil
  }

  var lastPhysicalJogObservationResultText: String {
    guard let outcome = machineSnapshot?.lastPhysicalJogObservationOutcome else { return "none" }
    switch outcome {
    case .recorded(let observation):
      return "recorded · \(observation.request.split.rawValue)"
    case .notRecorded:
      return "not recorded"
    }
  }

  var lastPhysicalJogPositionsText: String {
    guard case .recorded(let observation) = machineSnapshot?.lastPhysicalJogObservationOutcome else {
      return "unknown"
    }
    return String(
      format: "X %.3f Y %.3f → X %.3f Y %.3f",
      observation.startPosition.point.x,
      observation.startPosition.point.y,
      observation.finalPosition.point.x,
      observation.finalPosition.point.y
    )
  }

  var lastPhysicalJogCameraDeltaText: String {
    guard case .recorded(let observation) = machineSnapshot?.lastPhysicalJogObservationOutcome else {
      return "unknown"
    }
    return String(
      format: "Δx %.2f px · Δy %.2f px",
      observation.cameraDelta.dx,
      observation.cameraDelta.dy
    )
  }

  var lastPhysicalJogConfidenceText: String {
    guard case .recorded(let observation) = machineSnapshot?.lastPhysicalJogObservationOutcome else {
      return "unknown"
    }
    return String(
      format: "before %.3f · after %.3f",
      observation.before.capConfidence,
      observation.after.capConfidence
    )
  }

  var lastPhysicalJogFailureText: String? {
    guard case .notRecorded(_, let failure) = machineSnapshot?.lastPhysicalJogObservationOutcome else {
      return nil
    }
    return failure.actionableDescription
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
      return "Finish \(DiscoverySequenceCatalog.definition(for: activeDiscoverySequenceID).title); use Stop while it is moving."
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

  var activeDiscoverySequenceID: DiscoverySequenceID? {
    discoveryTransactions.first { _, transaction in
      switch transaction.state {
      case .active, .cancelling: true
      case .notStarted, .succeeded, .failed, .cancelled: false
      }
    }?.key
  }

  var penInteractionCompleted: Bool {
    guard discoveryTransactions[.penInteraction]?.state == .succeeded else { return false }
    return frameMode == .simulated
      ? simulatorPenState == .up
      : machineSnapshot?.machine.penState == .up
  }

  var relevantBoundaryObservationCount: Int {
    discoveryTransactions.values.filter { transaction in
      transaction.state == .succeeded
        && boundaryDirection(for: transaction.definition.id) != nil
    }.count
  }

  var humanGuidedDiscoveryCurrentStep: HumanGuidedDiscoveryStep {
    if !penInteractionCompleted { return .penInteraction }
    if relevantBoundaryObservationCount == 0 { return .boundaryDiscovery }
    return .clearViewDiscovery
  }

  var learningPathStagePresentations: [LearningPathStagePresentation] {
    let connected = controllerIsConnected
    let enabled = connected && motionGuardIsActive
    let discoveryComplete = penInteractionCompleted
      && relevantBoundaryObservationCount > 0
      && clearViewPoseAccepted
    let trialsComplete = drawingTrialAssessment != nil
    return [
      LearningPathStagePresentation(
        stage: .connect,
        status: connected ? .complete : (machineError == nil ? .current : .needsAttention),
        summary: connected
          ? "The currently selected controller is responsive."
          : "Select and connect one responsive controller."
      ),
      LearningPathStagePresentation(
        stage: .enableMotion,
        status: enabled ? .complete : (connected ? .current : .next),
        summary: enabled
          ? "Motion is enabled for direct, typed operations."
          : "Enable Motion after the selected controller is responsive."
      ),
      LearningPathStagePresentation(
        stage: .humanGuidedDiscovery,
        status: discoveryComplete
          ? .complete
          : (enabled ? (discoveryError == nil ? .current : .needsAttention) : .next),
        summary: discoveryComplete
          ? "Pen Interaction, a relevant boundary, and a clear view were observed this session."
          : "Complete Pen Interaction, one relevant Boundary Discovery, then accept a Clear-View observation."
      ),
      LearningPathStagePresentation(
        stage: .observedDrawingTrials,
        status: trialsComplete
          ? .complete
          : (discoveryComplete ? (explorationError == nil ? .current : .needsAttention) : .next),
        summary: trialsComplete
          ? "The local isolated-line trial has an operator comparison."
          : "Create and observe one isolated mark, then compare intended and observed geometry."
      ),
      LearningPathStagePresentation(
        stage: .adaptiveDrawing,
        status: .future,
        summary: "Adaptive Drawing is unavailable in this prototype."
      ),
    ]
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
    case .observedJog:
      "Stop the active observed jog and wait for its original owner to settle."
    case .drawingTrial:
      "Stop the drawing trial; the controller owns its single Pen Up cancellation."
    }
    return ContextualStopPresentation(detail: detail)
  }

  var currentOperatorActionPresentation: OperatorActionPresentation? {
    if let sequenceID = activeDiscoverySequenceID,
      let transaction = discoveryTransactions[sequenceID],
      let step = transaction.currentStep
    {
      let feedSelection: TravelFeedSelection? = switch step.action {
      case .startBoundaryJog(let direction): travelFeedSelection(for: jogVector(direction))
      default: nil
      }
      return OperatorActionPresentation(
        stepNumber: humanGuidedDiscoveryCurrentStep.stepNumber,
        title: transaction.definition.title,
        participant: step.participant.displayName,
        action: discoveryActionText(step.action),
        expectedObservation: discoveryExpectationText(step.expectedEvent),
        choices: step.question?.choices ?? [],
        requestedFeedMMPerMinute: feedSelection?.requestedFeedMMPerMinute,
        feedSource: feedSelection?.source
      )
    }

    guard clearViewPoseAccepted, drawingTrialAssessment == nil else { return nil }
    return OperatorActionPresentation(
      stepNumber: observedDrawingTrialStep.stepNumber,
      title: observedDrawingTrialStep.title,
      participant: drawingTrialParticipant(for: observedDrawingTrialStep),
      action: drawingTrialActionText(for: observedDrawingTrialStep),
      expectedObservation: drawingTrialExpectationText(for: observedDrawingTrialStep),
      primaryActionTitle: observedDrawingTrialStep == .compareIntendedAndObservedGeometry
        ? nil : drawingTrialPrimaryTitle(for: observedDrawingTrialStep),
      primaryActionUnavailableReason: drawingTrialActionUnavailableReason(
        for: observedDrawingTrialStep
      ),
      requestedFeedMMPerMinute: lastTravelFeedSelection?.requestedFeedMMPerMinute,
      feedSource: lastTravelFeedSelection?.source
    )
  }

  func beginPenInteraction() async {
    await startDiscoverySequence(.penInteraction)
  }

  func beginBoundaryDiscovery(_ direction: BoundaryDirection) async {
    await startDiscoverySequence(sequenceID(for: direction))
  }

  func answerCurrentQuestion(_ choice: OperatorChoice) async {
    guard let sequenceID = activeDiscoverySequenceID else { return }
    await answerDiscoverySequence(choice, for: sequenceID)
  }

  func recordClearViewLabel(_ label: ArmatureVisibilityLabel) async {
    guard humanGuidedDiscoveryCurrentStep == .clearViewDiscovery else { return }
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
    } catch {
      explorationError = "Clear-View observation failed: \(error)"
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
      armatureGuidanceState = guidance
      clearViewPoseAccepted = true
      observedDrawingTrialStep = .captureCleanReference
      learningPathFlow.present(.observedDrawingTrials(.captureCleanReference))
    } catch {
      explorationError = "Clear-View acceptance failed: \(error)"
    }
  }

  func performCurrentLearningPathAction() async {
    guard clearViewPoseAccepted, !explorationOperationInProgress else { return }
    explorationOperationInProgress = true
    explorationError = nil
    defer { explorationOperationInProgress = false }
    do {
      switch observedDrawingTrialStep {
      case .captureCleanReference:
        try await captureDrawingTrialCleanReference()
        advanceDrawingTrial(to: .chooseLineStart)
      case .chooseLineStart:
        try recordDrawingTrialLineStart()
        advanceDrawingTrial(to: .createAnchorMark)
      case .createAnchorMark:
        try await createDrawingTrialAnchor()
        advanceDrawingTrial(to: .drawIsolatedLine)
      case .drawIsolatedLine:
        try await drawIsolatedTrialLine()
        if observedDrawingTrialStep == .drawIsolatedLine {
          advanceDrawingTrial(to: .clearToolAndObserveInk)
        }
      case .clearToolAndObserveInk:
        try await clearToolAndObserveTrialInk()
        if observedDrawingTrialStep == .clearToolAndObserveInk {
          advanceDrawingTrial(to: .compareIntendedAndObservedGeometry)
        }
      case .compareIntendedAndObservedGeometry:
        break
      }
    } catch {
      explorationError = "\(observedDrawingTrialStep.title) failed: \(error)"
    }
  }

  func recordDrawingTrialAssessment(_ assessment: DrawingTrialAssessment) async {
    guard observedDrawingTrialStep == .compareIntendedAndObservedGeometry else { return }
    drawingTrialAssessment = assessment
    learningPathFlow.present(.adaptiveDrawing)
    if var episode = currentExplorationEpisode {
      episode.humanAssessment = ExplorationAssessment(
        summary: assessment.title,
        provenance: "typed local operator comparison"
      )
      episode.termination = .completed
      currentExplorationEpisode = episode
      completedExplorationEpisodes.append(episode)
    }
  }

  var drawingFramePosteriorText: String {
    guard let posterior = drawingFramePosterior else { return "no boundary posterior yet" }
    let completion = posterior.estimate == nil ? "partial image-space sides" : "four-side intersections"
    return "\(posterior.observationCount) exact-frame observations · \(posterior.sidePosteriors.count) associated sides · \(completion)"
  }

  func discoveryStartUnavailableReason(for sequenceID: DiscoverySequenceID) -> String? {
    if let activeDiscoverySequenceID {
      return "Finish \(DiscoverySequenceCatalog.definition(for: activeDiscoverySequenceID).title); use Stop while it is moving."
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
      return motionUnavailableReason
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
      return "Motion enabled. Complete Pen Interaction and leave the pen Up before carriage travel."
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
    if recordJogObservations, let failure = lastPhysicalJogFailureText { return failure }
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
    if recordJogObservations {
      if frameMode != .live {
        return PhysicalJogObservationFailure.liveCameraRequired.actionableDescription
      }
      if cameraActions == nil {
        return "Native camera composition is unavailable; disable jog recording or restore the camera."
      }
      guard case .running = cameraSnapshot?.state else {
        return "Start the selected LIVE camera before recording a jog observation."
      }
      if let pinnedConfiguration = jogResponseDataset?.cameraConfigurationID,
        let displayedConfiguration = displayedFrame?.frame.cameraConfigurationID,
        displayedConfiguration != pinnedConfiguration
      {
        return "Displayed LIVE camera configuration differs from the recorded sample set. Clear Samples before recording another jog."
      }
    }
    guard let xStep = inputNumber(xStepText), let yStep = inputNumber(yStepText),
      inputNumber(feedText) != nil
    else { return "Enter numeric X step, Y step, and feed values." }
    guard xStep > 0, yStep > 0 else {
      return "X and Y step magnitudes must be greater than zero."
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

  func setRecordJogObservations(_ enabled: Bool) {
    guard !hasShutdown, !jogRequestInProgress else { return }
    recordJogObservations = enabled
  }

  func selectObservationSplit(_ split: ModelObservationSplit) {
    guard !hasShutdown, !jogRequestInProgress else { return }
    selectedObservationSplit = split
  }

  func clearJogObservationSamples() {
    guard !hasShutdown, clearJogObservationSamplesUnavailableReason == nil else { return }
    physicalJogObservations = []
    jogResponseDataset = nil
    jogResponseCandidate = nil
    jogResponseLearnerError = nil
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
      drawingFramePosterior = try drawingFramePosterior?.adding(observation)
        ?? DrawingFramePosterior(prior: observation)
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
      await requestSingleJogCancel(for: target)
      await owner?.value

    case .manualJog, .observedJog:
      let owner = manualJogTask
      await requestSingleJogCancel(for: target)
      _ = await owner?.value

    case .drawingTrial:
      let owner = drawingTrialTask
      await requestSingleJogCancel(for: target)
      _ = await owner?.value
    }
  }

  private func requestSingleJogCancel(for target: ContextualStopTarget) async {
    guard let generation = beginHardwareIntent(), let machineActions else { return }
    defer { endHardwareIntent() }
    guard !jogCancelRequestInProgress, stopRequestIssuedForTarget != target else { return }
    stopRequestIssuedForTarget = target
    jogCancelRequestInProgress = true
    defer { jogCancelRequestInProgress = false }
    _ = await machineActions.requestJogCancel()
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
      if activeStopTarget == .manualJog || activeStopTarget == .observedJog {
        activeStopTarget = nil
        stopRequestIssuedForTarget = nil
      }
    }
    let recordsObservation = recordJogObservations
    let observationSplit = selectedObservationSplit
    let operation = Task { () -> JogOwnerResult in
      if recordsObservation {
        guard let cameraActions else {
          return .observed(
            .notRecorded(
              motionOutcome: nil,
              failure: .liveCameraRequired
            )
          )
        }
        let observationRequest = PhysicalJogObservationRequest(
          motion: request,
          split: observationSplit
        )
        let outcome = await machineActions.requestObservedJog(
          observationRequest,
          cameraActions.observeVisibleTool
        )
        return .observed(outcome)
      }
      let outcome = await machineActions.requestRelativeJog(request)
      return .manual(outcome)
    }
    manualJogTask = operation
    activeStopTarget = recordsObservation ? .observedJog : .manualJog
    stopRequestIssuedForTarget = nil
    await Task.yield()
    let interimSnapshot = await machineActions.snapshot()
    if canCommit(generation) { machineSnapshot = interimSnapshot }
    let ownerResult = await operation.value
    let finalSnapshot = await machineActions.snapshot()
    guard canCommit(generation) else { return nil }
    machineSnapshot = finalSnapshot
    switch ownerResult {
    case .observed(let outcome):
      switch outcome {
      case .recorded(let observation):
        physicalJogObservations.append(observation)
        recordJogResponseEpisode(observation)
      case .notRecorded:
        break
      }
      return outcome.motionOutcome
    case .manual(let outcome):
      return outcome
    }
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
    guard let request = makeBoundaryJogRequest(direction),
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
    let controllerTask = Task { await machineActions.requestRelativeJog(request) }
    await Task.yield()
    for _ in 0..<200 {
      guard !Task.isCancelled else { break }
      let snapshot = await machineActions.snapshot()
      machineSnapshot = snapshot
      if snapshot?.machine.connection == .moving {
        boundaryTeachingState = .moving(direction)
        boundaryTeachingResultText =
          "Moving \(direction.shortLabel). Stop is available for this Boundary Discovery."
        guard recordDiscovery(
          .boundaryJogStarted(
            discoveryDirection,
            controllerSummary: "Closed jog accepted and controller reported moving."
          ),
          for: sequenceID
        ) else { return }
        await advanceDiscoverySequence(sequenceID)
        break
      }
      try? await Task.sleep(nanoseconds: 10_000_000)
    }

    let outcome = await controllerTask.value
    machineSnapshot = await machineActions.snapshot()
    guard !hasShutdown else { return }

    switch outcome {
    case .cancelled(let finalPosition):
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

    case .acceptedThenCompleted:
      await failDiscovery(
        sequenceID,
        reason: "The bounded jog completed before Stop. No boundary evidence was recorded."
      )
    case .refused(let refusal):
      await failDiscovery(sequenceID, reason: refusal.actionableDescription)
    case .ambiguous(let ambiguity):
      await failDiscovery(sequenceID, reason: ambiguity.actionableDescription)
    }
    boundaryTeachingState = .idle
    activeStopTarget = nil
    stopRequestIssuedForTarget = nil
  }

  private func makeBoundaryJogRequest(_ direction: JogDirection) -> RelativeJogRequest? {
    guard boundaryTeachingState == .awaitingConfirmation(direction),
      motionUnavailableReason == nil
    else {
      boundaryTeachingResultText =
        "Boundary motion cannot start: \(motionUnavailableReason ?? "current motion values are invalid")."
      return nil
    }
    let distance: Double
    switch direction {
    case .xNegative, .xPositive:
      distance = MotionPriors.boundarySearchXDistanceMM
    case .yNegative, .yPositive:
      distance = MotionPriors.boundarySearchYDistanceMM
    }
    do {
      let delta: Vector2<MachineSpace>
      switch direction {
      case .xNegative: delta = try Vector2(dx: -distance, dy: 0)
      case .xPositive: delta = try Vector2(dx: distance, dy: 0)
      case .yNegative: delta = try Vector2(dx: 0, dy: -distance)
      case .yPositive: delta = try Vector2(dx: 0, dy: distance)
      }
      let selection = travelFeedSelection(for: delta)
      lastTravelFeedSelection = selection
      return RelativeJogRequest(
        delta: delta,
        feedMMPerMinute: selection.requestedFeedMMPerMinute
      )
    } catch {
      boundaryTeachingResultText = "Boundary motion request is invalid; no motion was sent."
      return nil
    }
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
    recordJogObservations = false
    selectedObservationSplit = .training
    physicalJogObservations = []
    jogResponseDataset = nil
    jogResponseCandidate = nil
    jogResponseLearnerError = nil
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
    learningPathFlow.present(.connect)
  }

  private func cancelAndSettleDiscoveryMotionBeforeErasure() async {
    guard boundaryTeachingState != .idle || boundaryMotionTask != nil else { return }

    // Preserve the typed Stop step until the one cancel byte has been sent and
    // the original motion owner has settled. Cancelling the transaction first
    // would erase `currentStep` and strand the physical jog.
    if activeStopTarget != nil { await stopCurrentOperation() }
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
        case .awaitContextualStop(direction) = discoveryTransactions[sequenceID]?.currentStep?.action
      {
        _ = recordDiscovery(.operatorStopRequested(direction), for: sequenceID)
        boundaryTeachingState = .cancelling(jogDirection(from: direction))
        boundaryTeachingResultText =
          "Stop requested during shutdown. Waiting for the original motion owner to reach Idle."
      }
      owner = boundaryMotionTask
    case .manualJog, .observedJog:
      owner = manualJogTask.map { task in Task { _ = await task.value } }
    case .drawingTrial:
      owner = drawingTrialTask.map { task in Task { _ = await task.value } }
    }

    if stopRequestIssuedForTarget != target, let machineActions {
      stopRequestIssuedForTarget = target
      jogCancelRequestInProgress = true
      _ = await machineActions.requestJogCancel()
      jogCancelRequestInProgress = false
    }
    await owner?.value
    activeStopTarget = nil
    stopRequestIssuedForTarget = nil
    boundaryTeachingState = .idle
  }

  private func recordJogResponseEpisode(_ observation: PhysicalJogObservation) {
    if jogResponseDataset == nil {
      do {
        jogResponseDataset = try OnlineJogResponseDataset(
          cameraConfigurationID: observation.before.cameraConfigurationID,
          algorithmRevision: observation.before.algorithmRevision
        )
      } catch {
        jogResponseCandidate = nil
        jogResponseLearnerError = jogResponseErrorDescription(error)
        return
      }
    }
    guard var nextDataset = jogResponseDataset else { return }
    do {
      try nextDataset.record(observation)
      jogResponseDataset = nextDataset
      do {
        jogResponseCandidate = try nextDataset.proposeCandidate()
        jogResponseLearnerError = nil
      } catch {
        jogResponseCandidate = nil
        jogResponseLearnerError = jogResponseErrorDescription(error)
      }
    } catch {
      jogResponseCandidate = nil
      jogResponseLearnerError = jogResponseErrorDescription(error)
    }
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

  private func jogVector(_ direction: BoundaryDirection) -> Vector2<MachineSpace> {
    switch direction {
    case .negativeX: try! Vector2(dx: -MotionPriors.boundarySearchXDistanceMM, dy: 0)
    case .positiveX: try! Vector2(dx: MotionPriors.boundarySearchXDistanceMM, dy: 0)
    case .negativeY: try! Vector2(dx: 0, dy: -MotionPriors.boundarySearchYDistanceMM)
    case .positiveY: try! Vector2(dx: 0, dy: MotionPriors.boundarySearchYDistanceMM)
    }
  }

  private func discoveryActionText(_ action: DiscoveryAction) -> String {
    switch action {
    case .askQuestion(let question): question.prompt
    case .awaitOperatorChoice(let question): "Choose \(question.choiceLabel) for this question."
    case .announce(let message): "Announce: \(message)"
    case .startBoundaryJog(let direction): "Start the bounded \(direction.displayName) jog."
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
    case .boundaryJogStarted: "The controller reports the closed jog moving."
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

  private func drawingTrialPrimaryTitle(for step: ObservedDrawingTrialStep) -> String {
    switch step {
    case .captureCleanReference: "Capture Clean Reference"
    case .chooseLineStart: "Choose Current Line Start"
    case .createAnchorMark: "Create Anchor Mark"
    case .drawIsolatedLine: "Draw Isolated Line"
    case .clearToolAndObserveInk: "Clear Tool and Observe Ink"
    case .compareIntendedAndObservedGeometry: "Record Comparison"
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
    learningPathFlow.present(.observedDrawingTrials(step))
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

  private func jogResponseErrorDescription(_ error: any Error) -> String {
    guard let error = error as? OnlineJogResponseError else {
      return "Jog-response diagnostic failed: \(String(describing: error))"
    }
    return switch error {
    case .invalidAlgorithmRevision:
      "Jog-response diagnostic requires a nonempty vision revision."
    case .duplicateEpisodeID(let id):
      "Jog-response diagnostic rejected duplicate sample \(id)."
    case .cameraConfigurationMismatch:
      "Recorded camera configuration differs from this sample set. Clear Samples before recording again."
    case .algorithmRevisionMismatch:
      "Vision revision differs from this sample set. Clear Samples before recording again."
    case .episodeAlgorithmRevisionChanged:
      "Vision revision changed between the before and after frames."
    case .invalidCameraProvenance(let id):
      "Sample \(id) has invalid camera provenance."
    case .invalidActualControllerDelta(let id):
      "Sample \(id) has no valid observed controller delta."
    case .invalidCameraDelta(let id):
      "Sample \(id) has no valid camera delta."
    case .insufficientTrainingEpisodes(let required, let actual):
      "Need \(required) training samples spanning both machine axes; \(actual) recorded."
    case .rankDeficientTrainingGeometry:
      "Training samples do not span both machine axes; record an independent axis direction."
    case .nonFiniteCandidate:
      "Jog-response diagnostic produced non-finite values."
    }
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
