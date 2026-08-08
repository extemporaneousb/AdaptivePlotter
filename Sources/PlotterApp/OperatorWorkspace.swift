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
  case trained = "ACCEPTED TRAINING"

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
  case awaitingReady(JogDirection)
  case moving(JogDirection)
  case cancelling(JogDirection)

  var direction: JogDirection? {
    switch self {
    case .idle: nil
    case .awaitingReady(let direction), .moving(let direction), .cancelling(let direction):
      direction
    }
  }
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

  struct VoiceActions: Sendable {
    let requestAuthorization: @Sendable () async -> VoiceAuthorizationState
    let startListening: @Sendable () async throws -> Void
    let stopListening: @Sendable () async -> Void
    let snapshot: @Sendable () async -> VoiceInteractionSnapshot
    let transcripts: @Sendable () async -> AsyncStream<VoiceTranscript>
    let speak: @Sendable (String) async -> Void
    let stopSpeaking: @Sendable () async -> Void
    let signal: @Sendable () async -> Void
  }

  struct ExplorationActions: Sendable {
    let start: @Sendable (ExplorationSessionInput, ExplorationSessionID) async
      -> ExplorationSessionSnapshot
    let activateEpisode: @Sendable (ExplorationEpisodeVoiceContext) async throws -> Void
    let completeEpisode: @Sendable (
      ExplorationEpisodeID,
      ExplorationEpisodeTermination
    ) async throws -> ExplorationEpisodeVoiceContext
    let ingest: @Sendable (VoiceTranscript) async -> ExplorationVoiceRoutingResult
    let speakFeedback: @Sendable (String) async -> ExplorationFeedbackReceipt?
    let end: @Sendable () async -> Void
    let snapshot: @Sendable () async -> ExplorationSessionSnapshot
    let events: @Sendable () async -> AsyncStream<ExplorationSessionEvent>
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
  private(set) var simulatorVoicePracticeEnabled = false
  private(set) var voiceAuthorizationState: VoiceAuthorizationState = .notDetermined
  private(set) var voiceListening = false
  private(set) var voiceTranscriptText = "none"
  private(set) var lastVoiceIntentText = "none"
  private(set) var lastVoiceActionableResultText = "none"
  private(set) var lastSpokenFeedbackText = "none"
  private(set) var voiceError: String?
  private(set) var boundaryTeachingState: BoundaryTeachingState = .idle
  private(set) var boundaryTeachingResultText = "Choose one side to begin."
  private(set) var boundaryPositions: [JogDirection: MachinePosition] = [:]
  var selectedPreflightSequenceID: PreflightSequenceID = .penUpConfirmation
  private(set) var preflightTransactions: [PreflightSequenceID: PreflightTransaction] = [:]
  private(set) var preflightRehearsals: [PreflightSequenceID: PreflightRehearsal] = [:]
  private(set) var preflightError: String?
  private(set) var drawingFramePosterior: DrawingFramePosterior?
  private(set) var explorationSessionSnapshot: ExplorationSessionSnapshot?
  private(set) var explorationFlow = ExplorationFlowCoordinator()
  private(set) var explorationTimeline: [ExplorationTimelineEntry] = []
  private(set) var explorationError: String?
  private(set) var currentExplorationEpisode: ExplorationEpisode?
  private(set) var completedExplorationEpisodes: [ExplorationEpisode] = []
  private(set) var armatureGuidanceState: ArmatureGuidanceState?
  private(set) var lastArmatureObservation: ArmaturePoseObservation?
  private(set) var explorationCleanReference: DisplayedFrame?
  private(set) var explorationAnchoredBaseline: DisplayedFrame?
  private(set) var explorationPostLineFrame: DisplayedFrame?
  private(set) var lastAnchorObservation: AnchorDotObservation?
  private(set) var lastInkObservation: IsolatedInkObservation?
  private(set) var explorationInkStatus = "no isolated-line observation yet"
  private(set) var explorationExportPath: String?
  private(set) var explorationOperationInProgress = false

  @ObservationIgnored private let machineActions: MachineActions?
  @ObservationIgnored private let cameraActions: CameraActions?
  @ObservationIgnored private let voiceActions: VoiceActions?
  @ObservationIgnored private let explorationActions: ExplorationActions?
  @ObservationIgnored private let serialDeviceDiscovery: @Sendable () -> [MachineLinkDescriptor]
  @ObservationIgnored private let persistSelectedSerialIdentifier: @Sendable (String) -> Void
  @ObservationIgnored private let nowNanoseconds: @Sendable () -> UInt64
  @ObservationIgnored private var frameTask: Task<Void, Never>?
  @ObservationIgnored private var visionUpdateTask: Task<Void, Never>?
  @ObservationIgnored private var voiceTranscriptTask: Task<Void, Never>?
  @ObservationIgnored private var voiceStateTask: Task<Void, Never>?
  @ObservationIgnored private var explorationEventTask: Task<Void, Never>?
  @ObservationIgnored private var explorationGeneration: UInt64 = 0
  @ObservationIgnored private var explorationControllerSessionID = UUID()
  @ObservationIgnored private var explorationCoordinateRevision: UInt64 = 0
  @ObservationIgnored private var explorationToolPaperRevision = UUID()
  @ObservationIgnored private var boundaryMotionTask: Task<Void, Never>?
  @ObservationIgnored private var boundaryCancelTask: Task<Void, Never>?
  @ObservationIgnored private var lastBoundaryStopUtteranceID: UUID?
  @ObservationIgnored private var pendingPreflightInspection: LiveSceneInspection?
  @ObservationIgnored private var pendingPreflightCaptureBoundaryNanoseconds: UInt64?
  @ObservationIgnored private var preflightAuthorityGeneration: UInt64 = 0
  @ObservationIgnored private var preflightRehearsalGeneration: UInt64 = 0
  @ObservationIgnored private var preflightRehearsalVoiceStartupGeneration: UInt64?
  @ObservationIgnored private var preflightRehearsalListeningID: PreflightSequenceID?
  @ObservationIgnored private var lastPreflightRehearsalUtteranceID: UUID?
  @ObservationIgnored private var voiceListenerGeneration: UInt64 = 0
  @ObservationIgnored private let preflightRehearsalStepDelayNanoseconds: UInt64
  @ObservationIgnored private var preflightRehearsalTask: Task<Void, Never>?
  @ObservationIgnored private var rememberedSerialDeviceIdentifier: String?
  @ObservationIgnored private var hasShutdown = false
  @ObservationIgnored private var lifetimeGeneration: UInt64 = 0
  @ObservationIgnored private var activeHardwareIntentCount = 0
  @ObservationIgnored private var intentDrainWaiters: [CheckedContinuation<Void, Never>] = []

  init(
    machineActions: MachineActions? = nil,
    cameraActions: CameraActions? = nil,
    voiceActions: VoiceActions? = nil,
    explorationActions: ExplorationActions? = nil,
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
    },
    preflightRehearsalStepDelayNanoseconds: UInt64 = 450_000_000
  ) {
    self.machineActions = machineActions
    self.cameraActions = cameraActions
    self.voiceActions = voiceActions
    self.explorationActions = explorationActions
    self.serialDevices = serialDevices
    self.serialDeviceDiscovery = serialDeviceDiscovery
    self.persistSelectedSerialIdentifier = persistSelectedSerialIdentifier
    rememberedSerialDeviceIdentifier = loadSelectedSerialIdentifier()
    self.nowNanoseconds = nowNanoseconds
    self.preflightRehearsalStepDelayNanoseconds = preflightRehearsalStepDelayNanoseconds
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
    if let activePreflightSequenceID {
      return "Finish or cancel \(PreflightSequenceCatalog.definition(for: activePreflightSequenceID).title)."
    }
    if passiveProbeInProgress || jogRequestInProgress || penRequestInProgress
      || motionGuardActivationInProgress
    {
      return "Wait for the current controller operation."
    }
    return nil
  }

  var motionGuardActivationUnavailableReason: String? {
    if motionGuardActivationInProgress { return "Motion Guard activation is in progress." }
    if motionGuardIsActive { return "Motion Guard is already active." }
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

  var motionGuardControlTitle: String {
    motionGuardIsActive ? "Deactivate Motion Guard" : "Activate Motion Guard"
  }

  var motionGuardControlUnavailableReason: String? {
    guard motionGuardIsActive else { return motionGuardActivationUnavailableReason }
    if motionGuardActivationInProgress { return "Motion Guard update is in progress." }
    if let activePreflightSequenceID {
      return "Finish or cancel \(PreflightSequenceCatalog.definition(for: activePreflightSequenceID).title)."
    }
    guard let snapshot = machineSnapshot else {
      return MotionRefusal.notConnected.actionableDescription
    }
    if snapshot.machine.operationInFlight || snapshot.currentOperation != .idle {
      return MotionRefusal.operationInFlight.actionableDescription
    }
    return nil
  }

  var voicePermissionText: String {
    switch voiceAuthorizationState {
    case .notDetermined: "not requested"
    case .authorized: "authorized"
    case .speechDenied: "speech recognition denied — allow it in System Settings"
    case .speechRestricted: "speech recognition restricted by system policy"
    case .microphoneDenied: "microphone denied — allow it in System Settings"
    case .microphoneRestricted: "microphone restricted by system policy"
    }
  }

  var voiceListeningText: String {
    if let voiceError { return "failed: \(voiceError)" }
    return voiceListening ? "listening" : "stopped"
  }

  var explorationIsActive: Bool {
    guard let snapshot = explorationSessionSnapshot else { return false }
    if case .listening = snapshot.state { return true }
    return false
  }

  private var explorationOwnsAuthority: Bool {
    guard let snapshot = explorationSessionSnapshot else { return false }
    return switch snapshot.state {
    case .inactive, .failed: false
    case .starting, .listening, .ending: true
    }
  }

  var explorationActionTitle: String {
    explorationIsActive ? "End Exploration" : "Start Exploration"
  }

  var explorationSessionText: String {
    guard let snapshot = explorationSessionSnapshot else { return "inactive" }
    return switch snapshot.state {
    case .inactive: "inactive"
    case .starting: "starting"
    case .listening:
      snapshot.input == .injected ? "listening · injected simulator input" : "listening · microphone"
    case .ending: "ending"
    case .failed(let failure): "failed: \(failure)"
    }
  }

  var explorationPhaseText: String { explorationFlow.phase.title }

  var explorationEvidenceText: String {
    if let observation = lastInkObservation {
      if let residual = observation.residual {
        return String(
          format: "observed %d new line pixels · endpoint RMS %.1f px · cross-track RMS %.1f px",
          observation.observedPixelCount,
          residual.rootMeanSquareEndpointPixels,
          residual.rootMeanSquareCrossTrackPixels
        )
      }
      return String(
        format: "observed %d new line pixels · relative %.1f px at %.1f° · absolute residual unavailable",
        observation.observedPixelCount,
        observation.displacementPixels.magnitude,
        observation.orientationRadians * 180 / .pi
      )
    }
    return explorationInkStatus
  }

  var armatureGuidanceText: String {
    guard let state = armatureGuidanceState else { return "no current-session observations" }
    let accepted = state.acceptedClearPose == nil ? "no clear pose accepted" : "clear pose accepted"
    return "\(state.observations.count) exact-frame labels · \(accepted)"
  }

  var explorationNextActionText: String {
    if explorationOperationInProgress { return "one closed learning action is in progress" }
    switch explorationFlow.phase {
    case .inactive: return "Start Exploration."
    case .motionPreflight: return frameMode == .simulated
      ? "Run the deterministic simulator episode."
      : "Complete Pen Up and one cancelled boundary observation, then continue."
    case .armatureGuidance: return "Use 1 mm pen-up moves, label visibility, then accept one clear pose."
    case .cleanReference: return "Capture the exact clean reference at the accepted clear pose."
    case .chooseLineStart: return "Jog pen-up to a harmless start and record the current MPos."
    case .anchorDot: return "Create one Pen Down/Up anchor, return clear, and capture the anchored baseline."
    case .anchoredBaseline: return "Return pen-up to the start and confirm Pen Down for the one stroke."
    case .isolatedStroke: return "Execute the one fixed short line. STOP cancels without clear-pose return."
    case .postLineObservation: return "Return clear and capture one strictly newer post-line frame."
    case .awaitingAssessment: return "Give one spoken shape or reward assessment."
    case .completed: return "Review this episode or end Exploration."
    case .stopped: return "Start a new Exploration session."
    }
  }

  var explorationStartUnavailableReason: String? {
    if hasShutdown { return "The operator workspace has shut down." }
    if explorationIsActive { return "The exploration session is already active." }
    if explorationActions == nil { return "Exploration voice composition is unavailable." }
    return nil
  }

  var voiceListeningUnavailableReason: String? {
    if hasShutdown { return "The operator workspace has shut down." }
    if voiceActions == nil { return "Native voice composition is unavailable." }
    if voiceListening { return "Voice listening is already active." }
    return nil
  }

  var jogCancelUnavailableReason: String? {
    if jogCancelRequestInProgress { return "A jog-cancel request is already in progress." }
    if frameMode == .simulated {
      return "SIMULATED source cannot issue physical machine commands. Switch to LIVE first."
    }
    if machineActions == nil { return "Native machine composition is unavailable." }
    if selectedSerialDevice == nil { return "Select and connect one serial device." }
    guard let machine = machineSnapshot?.machine else {
      return MotionRefusal.notConnected.actionableDescription
    }
    if let ambiguity = machine.stickyAmbiguity {
      return MotionRefusal.stickyAmbiguity(ambiguity).actionableDescription
    }
    if machine.connection == .disconnected || machine.connection == .blocked {
      return MotionRefusal.notConnected.actionableDescription
    }
    return nil
  }

  var frameModeSwitchUnavailableReason: String? {
    if frameModeSwitchInProgress { return "A frame source switch is already in progress." }
    if explorationOwnsAuthority {
      return "End Exploration before changing its live/simulated authority."
    }
    if activePreflightSequenceID != nil {
      return "Finish or cancel the active Motion Preflight before switching frame source."
    }
    if passiveProbeInProgress || jogRequestInProgress || penRequestInProgress
      || jogCancelRequestInProgress
    {
      return "Wait for the current physical controller operation before switching frame source."
    }
    if machineSnapshot?.machine.operationInFlight == true {
      return "Wait for the current physical controller operation before switching frame source."
    }
    if let operation = machineSnapshot?.currentOperation, operation != .idle {
      return "Wait for the current physical controller operation before switching frame source."
    }
    return nil
  }

  var controllerConnectionActionTitle: String {
    controllerLinkIsOpen ? "Disconnect" : "Connect"
  }

  var controllerConnectionActionUnavailableReason: String? {
    if controllerConnectionActionInProgress {
      return "Controller connection action is already in progress."
    }
    if controllerLinkIsOpen {
      if let activePreflightSequenceID {
        return "Finish or cancel \(PreflightSequenceCatalog.definition(for: activePreflightSequenceID).title)."
      }
      if passiveProbeInProgress || jogRequestInProgress || penRequestInProgress
        || jogCancelRequestInProgress || motionGuardActivationInProgress
      {
        return "Wait for the current controller operation."
      }
      if machineSnapshot?.machine.operationInFlight == true {
        return "Wait for the current controller operation."
      }
      if let operation = machineSnapshot?.currentOperation, operation != .idle {
        return "Wait for the current controller operation."
      }
      return nil
    }
    return passiveProbeUnavailableReason
  }

  var boundaryTeachingStateText: String {
    switch boundaryTeachingState {
    case .idle: return "idle"
    case .awaitingReady(let direction): return "\(direction.shortLabel) armed · say READY"
    case .moving(let direction): return "moving \(direction.shortLabel) · say STOP"
    case .cancelling(let direction): return "cancelling \(direction.shortLabel)"
    }
  }

  var preflightTrainingReadiness: PreflightTrainingReadiness {
    PreflightTrainingReadinessPolicy.supervisedTraining.evaluate(
      transactions: Array(preflightTransactions.values),
      currentPenState: machineSnapshot?.machine.penState ?? .unknown
    )
  }

  var activePreflightSequenceID: PreflightSequenceID? {
    preflightTransactions.first { _, transaction in
      switch transaction.state {
      case .active, .cancelling: true
      case .notStarted, .succeeded, .failed, .cancelled: false
      }
    }?.key
  }

  var activePreflightRehearsalID: PreflightSequenceID? {
    preflightRehearsals.first { _, rehearsal in rehearsal.state == .running }?.key
  }

  var preflightRehearsalStatusText: String {
    let sequenceID = activePreflightRehearsalID ?? selectedPreflightSequenceID
    guard let rehearsal = preflightRehearsals[sequenceID] else {
      return simulatorVoicePracticeEnabled
        ? "ready to rehearse with voice · controller remains off"
        : "ready to rehearse silently · microphone and controller remain off"
    }
    return switch rehearsal.state {
    case .notStarted:
      simulatorVoicePracticeEnabled
        ? "ready to rehearse with voice · controller remains off"
        : "ready to rehearse silently · microphone and controller remain off"
    case .running:
      simulatorVoicePracticeEnabled
        ? "voice rehearsal step \(rehearsal.completedStepCount + 1) of \(rehearsal.definition.steps.count)"
        : "silent rehearsal step \(rehearsal.completedStepCount + 1) of \(rehearsal.definition.steps.count)"
    case .completed: "rehearsal complete · no physical evidence recorded"
    case .cancelled: "rehearsal cancelled · no physical evidence recorded"
    }
  }

  var motionPreflightReadinessText: String {
    let readiness = preflightTrainingReadiness
    if readiness.isReady {
      return "ready to train · \(readiness.successfulSequenceIDs.count) sequences"
    }
    let missing = readiness.missingRequiredClasses
      .map(\.displayName)
      .sorted()
      .joined(separator: ", ")
    if !missing.isEmpty {
      return "preflight required · missing \(missing)"
    }
    if !readiness.hasSuccessfulPenUpConfirmation {
      return "preflight required · complete Pen Up confirmation"
    }
    return "preflight required · current pen state \(readiness.currentPenState.rawValue), Pen Up required"
  }

  var continueToArmatureUnavailableReason: String? {
    guard explorationIsActive, currentExplorationEpisode?.rung == .motionPreflight else {
      return "Start the Motion Preflight exploration episode."
    }
    if activePreflightSequenceID != nil { return "Finish the active Motion Preflight transaction." }
    if frameMode == .live {
      guard machineSnapshot?.machine.penState == .up else {
        return "Complete the physical Pen Up confirmation."
      }
      guard drawingFramePosterior?.sidePosteriors.isEmpty == false else {
        return "Record one unambiguous cancelled-boundary observation."
      }
    }
    return nil
  }

  func continueToArmatureGuidance() async {
    guard continueToArmatureUnavailableReason == nil else { return }
    do {
      try explorationFlow.completeMotionPreflight()
      await completeCurrentExplorationEpisode(termination: .completed)
      await activateExplorationEpisode(
        rung: .armatureGuidance,
        allowedIntents: [
          .stop, .continueAction, .keepGoing, .reverse,
          .xPositive, .xNegative, .yPositive, .yNegative,
          .accept, .skip, .endSession,
        ],
        teachingLabelKinds: [.visibility],
        stopIsCancellable: true
      )
      appendExplorationTimeline(
        participant: .vision,
        action: "advance learning rung",
        observation: "Armature Guidance active; manual motion remains independent"
      )
    } catch {
      explorationError = "Could not enter Armature Guidance: \(error)"
    }
  }

  /// Runs the same app-level ordering and worker-owned vision APIs as live
  /// exploration. It deliberately has no path to `MachineActions`.
  func runSimulatedExploration() async {
    guard frameMode == .simulated, explorationIsActive,
      explorationFlow.phase == .motionPreflight,
      let cameraActions
    else { return }
    explorationOperationInProgress = true
    defer { explorationOperationInProgress = false }
    explorationError = nil
    do {
      let frames = try await cameraActions.simulatedExplorationFrames()
      appendExplorationTimeline(
        participant: .simulator,
        action: "rehearse Pen Up and boundary STOP",
        observation: "typed simulated outcomes only; no controller adapter was called"
      )
      let simulatedFrameGeometry = DrawingFrameEstimate(
        geometry: try Polyline(points: [
          Point2<CameraPixelSpace>(x: 20, y: 20),
          Point2<CameraPixelSpace>(x: 620, y: 20),
          Point2<CameraPixelSpace>(x: 620, y: 460),
          Point2<CameraPixelSpace>(x: 20, y: 460),
          Point2<CameraPixelSpace>(x: 20, y: 20),
        ]),
        confidence: 0.95,
        basis: "deterministic simulator frame prior"
      )
      let boundaryObservation = try DrawingFrameBoundaryObservation(
        frameID: frames.cleanReference.frame.id,
        frameSHA256: frames.cleanReference.frame.contentSHA256,
        captureNanoseconds: frames.cleanReference.frame.captureNanoseconds,
        cameraConfigurationID: frames.cleanReference.frame.cameraConfigurationID,
        direction: .positiveY,
        controllerPosition: MachinePosition(x: 0, y: 0),
        observedToolCentroid: Point2<CameraPixelSpace>(x: 320, y: 5),
        estimate: simulatedFrameGeometry,
        observationVariance: 4,
        associationDistanceMargin: 8,
        broadPriorVariance: 400
      )
      drawingFramePosterior = try DrawingFramePosterior(prior: boundaryObservation)
      appendExplorationTimeline(
        participant: .vision,
        action: "adjust boundary side posterior",
        observation: "one exact simulated frame and final MPos; image geometry only"
      )
      try explorationFlow.completeMotionPreflight()
      await completeCurrentExplorationEpisode(termination: .completed)
      await activateExplorationEpisode(
        rung: .armatureGuidance,
        allowedIntents: [
          .stop, .continueAction, .keepGoing, .reverse,
          .xPositive, .xNegative, .yPositive, .yNegative,
          .accept, .skip, .endSession,
        ],
        teachingLabelKinds: [.visibility],
        stopIsCancellable: true
      )

      let context = ArmatureGuidanceContext(
        controllerSessionID: explorationControllerSessionID,
        coordinateRevision: explorationCoordinateRevision,
        cameraConfigurationID: frames.cleanReference.frame.cameraConfigurationID,
        observationRegion: frames.observationRegion,
        toolPaperRevision: explorationToolPaperRevision
      )
      var guidance = ArmatureGuidanceState(context: context)
      let blocked = try guidance.record(
        frame: frames.cleanReference.frame,
        controllerPosition: MachinePosition(x: 0, y: 0),
        armatureBounds: nil,
        humanLabel: .blocked,
        outcome: .continueInDirection(.positiveXOneMillimeter)
      )
      appendExplorationTimeline(
        participant: .simulator,
        action: "label blocked pose",
        observation: "exact frame \(blocked.frameID.rawValue) at simulated MPos (0, 0)"
      )
      let clearBounds = try AxisAlignedBounds<CameraPixelSpace>(
        minX: 0, minY: 0, maxX: 10, maxY: 10
      )
      let clear = try guidance.record(
        frame: frames.cleanReference.frame,
        controllerPosition: MachinePosition(x: 1, y: 0),
        armatureBounds: clearBounds,
        humanLabel: .clear,
        outcome: .acceptedPose
      )
      try guidance.acceptClearPose(
        observationID: clear.id,
        returnFeedMMPerMinute: 100
      )
      armatureGuidanceState = guidance
      lastArmatureObservation = clear
      try explorationFlow.acceptClearPose(id: clear.id.rawValue.uuidString.lowercased())
      appendExplorationTimeline(
        participant: .operatorHuman,
        action: "accept clear pose",
        observation: "simulated label only; human/physical visibility not claimed"
      )
      await completeCurrentExplorationEpisode(termination: .completed)
      await activateExplorationEpisode(
        rung: .isolatedInk,
        allowedIntents: [.stop, .accept, .again, .skip, .endSession],
        teachingLabelKinds: [.shapeFeature, .reward],
        stopIsCancellable: true
      )

      explorationCleanReference = frames.cleanReference
      displayedFrame = frames.cleanReference
      try explorationFlow.recordCleanReference(frames.cleanReference)
      appendFrameEvidence(.cleanReference, frame: frames.cleanReference.frame)
      let lineStart = try MachinePosition(x: 12, y: 8)
      try explorationFlow.recordLineStart(lineStart)
      if var episode = currentExplorationEpisode {
        episode.lineStartPosition = lineStart
        currentExplorationEpisode = episode
      }

      let anchorOutcome = await cameraActions.observeAnchorDot(
        AnchorDotObservationRequest(
          cleanReference: frames.cleanReference.frame,
          anchoredBaseline: frames.anchoredBaseline.frame,
          region: frames.observationRegion,
          thresholds: GreenPixelThresholds(minimumGreen: 75, minimumGreenExcess: 20),
          algorithmRevision: "isolated-ink-v1"
        )
      )
      let anchor: AnchorDotObservation
      switch anchorOutcome {
      case .observed(let observation): anchor = observation
      case .rejected(let rejection):
        throw ExplorationSimulationError.anchorRejected(String(describing: rejection.reason))
      }
      lastAnchorObservation = anchor
      explorationAnchoredBaseline = frames.anchoredBaseline
      displayedFrame = frames.anchoredBaseline
      cameraOverlays = [anchor.overlay]
      try explorationFlow.recordAnchoredBaseline(
        frames.anchoredBaseline,
        anchorCentroid: anchor.centroid
      )
      appendFrameEvidence(.anchoredBaseline, frame: frames.anchoredBaseline.frame)
      if var episode = currentExplorationEpisode {
        episode.anchorDotCentroid = anchor.centroid
        currentExplorationEpisode = episode
      }

      try explorationFlow.beginIsolatedStroke()
      if var episode = currentExplorationEpisode {
        episode.proposedAction = ExplorationActionSummary(
          kind: .drawingStroke,
          parameters: "simulated fixed +5 mm X"
        )
        episode.executedAction = episode.proposedAction
        episode.controllerEvidence = ExplorationControllerEvidence(
          startPosition: lineStart,
          finalPosition: try MachinePosition(x: 17, y: 8),
          startSampleNanoseconds: 10,
          settlementNanoseconds: 20,
          outcome: .completed,
          summary: "deterministic simulator outcome; not controller evidence"
        )
        currentExplorationEpisode = episode
      }
      try explorationFlow.settleForPostLineObservation()
      explorationPostLineFrame = frames.postLine
      displayedFrame = frames.postLine
      try explorationFlow.recordPostLineFrame(frames.postLine)
      appendFrameEvidence(.postLine, frame: frames.postLine.frame)

      let inkOutcome = await cameraActions.observeIsolatedInk(
        IsolatedInkObservationRequest(
          cleanReference: frames.cleanReference.frame,
          anchoredBaseline: frames.anchoredBaseline.frame,
          postLine: frames.postLine.frame,
          region: frames.observationRegion,
          thresholds: GreenPixelThresholds(minimumGreen: 75, minimumGreenExcess: 20),
          projectedActualStrokeDelta: frames.projectedStrokeDelta,
          algorithmRevision: "isolated-ink-v1"
        )
      )
      switch inkOutcome {
      case .observed(let observation):
        acceptInkObservation(observation, source: .simulator)
      case .rejected(let rejection):
        throw ExplorationSimulationError.inkRejected(String(describing: rejection.reason))
      }
      appendExplorationTimeline(
        participant: .simulator,
        action: "complete deterministic line",
        observation: "intended, observed, and residual overlays share the exact post-line frame"
      )

      guard let explorationActions else { return }
      let transcript = VoiceTranscript(
        utteranceID: UUID(),
        sequence: 1,
        text: "good straight line",
        isFinal: true,
        monotonicNanoseconds: nowNanoseconds()
      )
      _ = await explorationActions.ingest(transcript)
      for _ in 0..<200 {
        if explorationFlow.phase == .completed, currentExplorationEpisode == nil { break }
        await Task.yield()
      }
      guard explorationFlow.phase == .completed, currentExplorationEpisode == nil else {
        throw ExplorationSimulationError.assessmentNotAccepted
      }
    } catch {
      explorationError = "Simulator exploration stopped: \(error)"
      explorationInkStatus = "simulator episode stopped · \(error)"
      explorationFlow.stop()
      await completeCurrentExplorationEpisode(termination: .failed(String(describing: error)))
    }
  }

  func recordArmatureVisibility(_ label: ArmatureVisibilityLabel) async {
    guard frameMode == .live, explorationFlow.phase == .armatureGuidance,
      let cameraActions, let position = machineSnapshot?.machine.position
    else { return }
    explorationOperationInProgress = true
    defer { explorationOperationInProgress = false }
    do {
      let boundary = displayedFrame?.frame.captureNanoseconds ?? 0
      guard let inspection = try await cameraActions.inspectScene(boundary) else {
        throw ExplorationLiveError.freshFrameUnavailable
      }
      let context = armatureContext(
        frame: inspection.displayedFrame.frame,
        region: armatureGuidanceState?.context.observationRegion
          ?? defaultInkRegion(for: inspection.displayedFrame.frame)
      )
      var guidance = armatureGuidanceState ?? ArmatureGuidanceState(context: context)
      guidance.updateContext(context)
      let observation = try guidance.record(
        frame: inspection.displayedFrame.frame,
        controllerPosition: position,
        armatureBounds: inspection.measurement.armature?.bounds,
        humanLabel: label,
        outcome: .stopped
      )
      armatureGuidanceState = guidance
      lastArmatureObservation = observation
      displayedFrame = inspection.displayedFrame
      cameraOverlays = inspection.measurement.overlays + [observationRegionOverlay(
        frame: inspection.displayedFrame.frame,
        region: context.observationRegion,
        source: .planned
      )]
      appendFrameEvidence(.armatureObservation, frame: inspection.displayedFrame.frame)
      appendExplorationTimeline(
        participant: .operatorHuman,
        action: "label armature \(label.rawValue)",
        observation: observation.estimateAgreedWithHuman
          ? "vision estimate agreed on exact frame"
          : "vision disagreed; human label retained"
      )
    } catch {
      explorationError = "Armature observation failed: \(error)"
    }
  }

  func moveArmature(_ action: ArmatureGuidanceAction) async {
    guard frameMode == .live, explorationFlow.phase == .armatureGuidance,
      machineSnapshot?.machine.penState == .up,
      let machineActions, let position = machineSnapshot?.machine.position
    else { return }
    explorationOperationInProgress = true
    defer { explorationOperationInProgress = false }
    do {
      let context: ArmatureGuidanceContext
      if let existing = armatureGuidanceState?.context {
        context = existing
      } else if let frame = displayedFrame?.frame {
        context = armatureContext(frame: frame, region: defaultInkRegion(for: frame))
      } else {
        throw ExplorationLiveError.freshFrameUnavailable
      }
      var guidance = armatureGuidanceState ?? ArmatureGuidanceState(context: context)
      guard let proposal = try guidance.proposedActions(
        from: position,
        feedMMPerMinute: Double(feedText) ?? 100
      ).first(where: { $0.action == action }) else {
        throw ExplorationLiveError.armatureProposalUnavailable
      }
      let outcome = await machineActions.requestRelativeJog(proposal.request)
      machineSnapshot = await machineActions.snapshot()
      appendExplorationTimeline(
        participant: .controller,
        action: "armature \(action.rawValue)",
        observation: String(describing: outcome)
      )
      if case .ambiguous(let ambiguity) = outcome {
        guidance.invalidateAutomatedReturn(.explicitlyDiscarded)
        armatureGuidanceState = guidance
        explorationFlow.stop()
        await completeCurrentExplorationEpisode(
          termination: .ambiguous(ambiguity.actionableDescription)
        )
      } else {
        armatureGuidanceState = guidance
      }
    } catch {
      explorationError = "Armature move failed: \(error)"
    }
  }

  func acceptCurrentArmaturePose() async {
    guard explorationFlow.phase == .armatureGuidance,
      let observation = lastArmatureObservation,
      observation.humanLabel == .clear,
      var guidance = armatureGuidanceState
    else { return }
    do {
      try guidance.acceptClearPose(
        observationID: observation.id,
        returnFeedMMPerMinute: Double(feedText) ?? 100
      )
      armatureGuidanceState = guidance
      try explorationFlow.acceptClearPose(id: observation.id.rawValue.uuidString.lowercased())
      if var episode = currentExplorationEpisode {
        episode.executedAction = ExplorationActionSummary(
          kind: .acceptClearPose,
          parameters: "human-clear observation \(observation.id.rawValue.uuidString.lowercased())"
        )
        currentExplorationEpisode = episode
      }
      await completeCurrentExplorationEpisode(termination: .completed)
      await activateExplorationEpisode(
        rung: .isolatedInk,
        allowedIntents: [
          .ready, .stop, .penIsPhysicallyUp, .penIsPhysicallyDown,
          .accept, .again, .skip, .endSession,
        ],
        teachingLabelKinds: [.shapeFeature, .reward],
        stopIsCancellable: true
      )
    } catch {
      explorationError = "Clear-pose acceptance failed: \(error)"
    }
  }

  func captureExplorationCleanReference() async {
    guard frameMode == .live, explorationFlow.phase == .cleanReference,
      let clear = armatureGuidanceState?.acceptedClearPose,
      machineSnapshot?.machine.position == clear.position,
      machineSnapshot?.machine.penState == .up,
      let cameraActions
    else { return }
    explorationOperationInProgress = true
    defer { explorationOperationInProgress = false }
    do {
      guard let frame = try await cameraActions.captureFrame(
        displayedFrame?.frame.captureNanoseconds ?? 0
      ) else { throw ExplorationLiveError.freshFrameUnavailable }
      try explorationFlow.recordCleanReference(frame)
      explorationCleanReference = frame
      displayedFrame = frame
      cameraOverlays = [observationRegionOverlay(
        frame: frame.frame,
        region: armatureGuidanceState?.context.observationRegion
          ?? defaultInkRegion(for: frame.frame),
        source: .planned
      )]
      appendFrameEvidence(.cleanReference, frame: frame.frame)
      appendExplorationTimeline(
        participant: .camera,
        action: "capture clean reference",
        observation: "\(frame.frame.id.rawValue) · \(frame.frame.contentSHA256.prefix(12))"
      )
    } catch {
      explorationError = "Clean-reference capture failed: \(error)"
    }
  }

  func recordExplorationLineStart() {
    guard explorationFlow.phase == .chooseLineStart,
      machineSnapshot?.machine.penState == .up,
      let position = machineSnapshot?.machine.position
    else { return }
    do {
      try explorationFlow.recordLineStart(position)
      if var episode = currentExplorationEpisode {
        episode.lineStartPosition = position
        currentExplorationEpisode = episode
      }
      appendExplorationTimeline(
        participant: .controller,
        action: "record line start",
        observation: String(format: "MPos X %.3f Y %.3f", position.point.x, position.point.y)
      )
    } catch {
      explorationError = "Line-start recording failed: \(error)"
    }
  }

  /// Called after one physical Pen Down confirmation followed by Pen Up at the
  /// recorded start. It returns clear before admitting the anchored baseline.
  func captureExplorationAnchor() async {
    guard frameMode == .live, explorationFlow.phase == .anchorDot,
      machineSnapshot?.machine.penState == .up,
      preflightTransactions[.penDownConfirmation]?.state == .succeeded,
      preflightTransactions[.penUpConfirmation]?.state == .succeeded,
      let clean = explorationCleanReference,
      let cameraActions
    else { return }
    explorationOperationInProgress = true
    defer { explorationOperationInProgress = false }
    do {
      try await returnToAcceptedClearPose()
      guard let anchored = try await cameraActions.captureFrame(
        max(clean.frame.captureNanoseconds, nowNanoseconds() == 0 ? 0 : clean.frame.captureNanoseconds)
      ) else { throw ExplorationLiveError.freshFrameUnavailable }
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
      switch outcome {
      case .observed(let observation):
        try explorationFlow.recordAnchoredBaseline(
          anchored,
          anchorCentroid: observation.centroid
        )
        explorationAnchoredBaseline = anchored
        lastAnchorObservation = observation
        displayedFrame = anchored
        cameraOverlays = [observation.overlay]
        appendFrameEvidence(.anchoredBaseline, frame: anchored.frame)
        if var episode = currentExplorationEpisode {
          episode.anchorDotCentroid = observation.centroid
          episode.visionEstimate = ExplorationAssessment(
            summary: "one new anchor component · \(observation.pixelCount) pixels",
            provenance: "\(observation.algorithmRevision) on exact clean/anchored pair"
          )
          currentExplorationEpisode = episode
        }
        appendExplorationTimeline(
          participant: .vision,
          action: "detect anchor dot",
          observation: String(
            format: "centroid %.1f, %.1f · %d pixels",
            observation.centroid.x,
            observation.centroid.y,
            observation.pixelCount
          )
        )
      case .rejected(let rejection):
        explorationInkStatus = "anchor rejected · \(rejection.reason)"
        explorationFlow.stop()
        await completeCurrentExplorationEpisode(
          termination: .failed("anchor rejected: \(rejection.reason)")
        )
      }
    } catch {
      explorationError = "Anchor capture failed: \(error)"
      explorationFlow.stop()
      await completeCurrentExplorationEpisode(termination: .failed(String(describing: error)))
    }
  }

  func prepareExplorationStrokeStart() async {
    guard frameMode == .live, explorationFlow.phase == .anchoredBaseline,
      let start = explorationFlow.lineStartPosition,
      machineSnapshot?.machine.penState == .up,
      let machineActions, let current = machineSnapshot?.machine.position
    else { return }
    explorationOperationInProgress = true
    defer { explorationOperationInProgress = false }
    do {
      if current != start {
        let request = RelativeJogRequest(
          delta: try Vector2(
            dx: start.point.x - current.point.x,
            dy: start.point.y - current.point.y
          ),
          feedMMPerMinute: Double(feedText) ?? 100
        )
        let outcome = await machineActions.requestRelativeJog(request)
        machineSnapshot = await machineActions.snapshot()
        guard case .acceptedThenCompleted(let final) = outcome, final == start else {
          throw ExplorationLiveError.controllerOutcome(String(describing: outcome))
        }
      }
      try explorationFlow.beginIsolatedStroke()
      appendExplorationTimeline(
        participant: .controller,
        action: "return to recorded line start",
        observation: "Idle with exact final MPos; Pen Up remains required"
      )
    } catch {
      explorationError = "Could not prepare the stroke start: \(error)"
      if case ExplorationLiveError.controllerOutcome(let detail) = error {
        explorationFlow.stop()
        await completeCurrentExplorationEpisode(termination: .ambiguous(detail))
      }
    }
  }

  /// Executes exactly one closed 5 mm pen-down stroke. Completed strokes get
  /// one explicit raise and clear-pose return; clean cancellation has already
  /// raised once in the controller and stops in place; ambiguity sends nothing.
  func runExplorationStroke() async {
    guard frameMode == .live, explorationFlow.phase == .isolatedStroke,
      machineSnapshot?.machine.penState == .down,
      let machineActions, let cameraActions,
      let clean = explorationCleanReference,
      let anchored = explorationAnchoredBaseline
    else { return }
    explorationOperationInProgress = true
    defer { explorationOperationInProgress = false }
    let request = DrawingStrokeRequest(
      delta: try! Vector2(dx: 5, dy: 0),
      feedMMPerMinute: Double(feedText) ?? 100
    )
    if var episode = currentExplorationEpisode {
      episode.proposedAction = ExplorationActionSummary(
        kind: .drawingStroke,
        parameters: "+5.000 mm X at \(request.feedMMPerMinute) mm/min"
      )
      currentExplorationEpisode = episode
    }
    let outcome = await machineActions.requestDrawingStroke(request)
    machineSnapshot = await machineActions.snapshot()
    switch outcome {
    case .refused(let refusal):
      explorationInkStatus = "stroke refused · \(refusal)"
      explorationFlow.stop()
      await completeCurrentExplorationEpisode(
        termination: .failed("stroke refused: \(refusal)")
      )
      return
    case .ambiguous(let ambiguity):
      explorationInkStatus = "stroke ambiguous · no follow-on bytes sent"
      explorationFlow.stop()
      await completeCurrentExplorationEpisode(
        termination: .ambiguous(ambiguity.actionableDescription)
      )
      return
    case .cancelled(let evidence, let penRaiseOutcome):
      recordStrokeEvidence(evidence, outcome: .cancelled, summary: "STOP settled in place")
      explorationInkStatus = "stroke cancelled in place · \(penRaiseOutcome) · no clear return"
      explorationFlow.stop()
      await completeCurrentExplorationEpisode(termination: .cancelled(utteranceID: nil))
      return
    case .completed(let evidence):
      recordStrokeEvidence(evidence, outcome: .completed, summary: "Idle with final MPos")
      if var episode = currentExplorationEpisode {
        episode.executedAction = episode.proposedAction
        currentExplorationEpisode = episode
      }
      let raise = await machineActions.requestPenActuation(.raise)
      machineSnapshot = await machineActions.snapshot()
      guard case .commandedAndSettled = raise else {
        explorationInkStatus = "post-stroke Pen Up was not settled · no return or camera claim"
        explorationFlow.stop()
        let termination: ExplorationEpisodeTermination = switch raise {
        case .ambiguous(let ambiguity): .ambiguous(ambiguity.actionableDescription)
        case .refused(let refusal): .failed("Pen Up refused: \(refusal)")
        case .commandedAndSettled: .completed
        }
        await completeCurrentExplorationEpisode(termination: termination)
        return
      }
      do {
        try await returnToAcceptedClearPose()
        try explorationFlow.settleForPostLineObservation()
        guard let post = try await cameraActions.captureFrame(evidence.finalSampleNanoseconds) else {
          throw ExplorationLiveError.freshFrameUnavailable
        }
        try explorationFlow.recordPostLineFrame(post)
        explorationPostLineFrame = post
        displayedFrame = post
        appendFrameEvidence(.postLine, frame: post.frame)
        let actualDelta = try Vector2<MachineSpace>(
          dx: evidence.finalPosition.point.x - evidence.startPosition.point.x,
          dy: evidence.finalPosition.point.y - evidence.startPosition.point.y
        )
        let projected = try jogResponseCandidate?.matrix.cameraDelta(for: actualDelta)
        let inkOutcome = await cameraActions.observeIsolatedInk(
          IsolatedInkObservationRequest(
            cleanReference: clean.frame,
            anchoredBaseline: anchored.frame,
            postLine: post.frame,
            region: armatureGuidanceState?.context.observationRegion
              ?? defaultInkRegion(for: post.frame),
            thresholds: GreenPixelThresholds(minimumGreen: 75, minimumGreenExcess: 20),
            projectedActualStrokeDelta: projected,
            algorithmRevision: "isolated-ink-v1"
          )
        )
        switch inkOutcome {
        case .observed(let observation):
          acceptInkObservation(observation, source: .vision)
          do {
            explorationExportPath = try await cameraActions.exportLearningEpisode(
              [
                StartupFrameRecorder.LearningFrame(role: .cleanReference, displayedFrame: clean),
                StartupFrameRecorder.LearningFrame(role: .anchoredBaseline, displayedFrame: anchored),
                StartupFrameRecorder.LearningFrame(role: .postLine, displayedFrame: post),
              ],
              currentExplorationEpisode?.id.rawValue ?? UUID().uuidString.lowercased()
            )
          } catch {
            explorationError = "Frames remain available in memory, but learning export failed: \(error)"
          }
        case .rejected(let rejection):
          explorationInkStatus = "ink rejected on exact post frame · \(rejection.reason) · no redraw"
          cameraOverlays = []
          await completeCurrentExplorationEpisode(
            termination: .failed("ink rejected: \(rejection.reason)")
          )
          explorationFlow.stop()
        }
      } catch {
        explorationError = "Post-line observation failed: \(error)"
        explorationFlow.stop()
        await completeCurrentExplorationEpisode(termination: .failed(String(describing: error)))
      }
    }
  }

  var drawingFramePosteriorText: String {
    guard let posterior = drawingFramePosterior else { return "no boundary posterior yet" }
    let completion = posterior.estimate == nil ? "partial image-space sides" : "four-side intersections"
    return "\(posterior.observationCount) exact-frame observations · \(posterior.sidePosteriors.count) associated sides · \(completion)"
  }

  func preflightStartUnavailableReason(for sequenceID: PreflightSequenceID) -> String? {
    if let activePreflightSequenceID {
      return "Finish or cancel \(PreflightSequenceCatalog.definition(for: activePreflightSequenceID).title)."
    }
    guard explorationIsActive else { return "Start Exploration first; it owns speech listening." }
    guard currentExplorationEpisode?.rung == .motionPreflight else {
      return "The active exploration episode is not Motion Preflight."
    }
    if !motionGuardIsActive { return "Connect the plotter and activate Motion Guard first." }
    if frameMode != .live || !cameraIsLive {
      return "A current LIVE camera frame is required for Motion Preflight."
    }
    switch sequenceID {
    case .boundaryNegativeX, .boundaryPositiveX, .boundaryNegativeY, .boundaryPositiveY:
      return motionUnavailableReason
    case .penUpConfirmation:
      return penUnavailableReason(for: .raise)
    case .penDownConfirmation:
      return penUnavailableReason(for: .lower)
    }
  }

  func preflightRehearsalStartUnavailableReason(
    for sequenceID: PreflightSequenceID
  ) -> String? {
    if frameMode != .simulated { return "Switch the Camera panel to SIMULATED first." }
    if displayedFrame?.source != .simulated { return "The simulator has no rendered frame." }
    if let activePreflightRehearsalID {
      return "Finish or cancel \(PreflightSequenceCatalog.definition(for: activePreflightRehearsalID).title)."
    }
    if simulatorVoicePracticeEnabled {
      if voiceActions == nil { return "Native voice composition is unavailable." }
      if preflightRehearsalVoiceStartupGeneration != nil {
        return "Wait for the previous simulator microphone request to settle."
      }
      if voiceListening { return "Voice listening is already active." }
    }
    return nil
  }

  var boundaryTeachingUnavailableReason: String? {
    if boundaryTeachingState != .idle { return "Finish or cancel the current boundary interaction." }
    if voiceActions == nil { return "Native voice composition is unavailable." }
    return motionUnavailableReason
  }

  func boundaryPositionText(for direction: JogDirection) -> String {
    guard let position = boundaryPositions[direction] else { return "not measured" }
    return String(format: "X %.3f Y %.3f", position.point.x, position.point.y)
  }

  var workbenchStatusText: String {
    if let actionableError { return actionableError }
    if !controllerIsConnected { return "Select the remembered controller and press Connect." }
    if !motionGuardIsActive {
      return "Plotter connected. Activate Motion Guard to enable this preflight action."
    }
    if machineSnapshot?.machine.penState != .up {
      return "Motion Guard active. Run the Pen Up preflight before carriage travel."
    }
    return "Motion Guard active; carriage motion is available."
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

  var lastJogCancelOutcomeText: String {
    guard let outcome = machineSnapshot?.lastJogCancelOutcome else { return "none" }
    switch outcome {
    case .refused(let refusal):
      return "refused: \(refusal.actionableDescription)"
    case .transmitted:
      return "cancel byte sent; controller acknowledgement is not implied"
    case .completed(let finalPosition):
      return String(
        format: "cancelled and Idle at X %.3f Y %.3f",
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
    guard activePreflightSequenceID == nil, !explorationOwnsAuthority else { return }
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

  func startExploration() async {
    guard explorationStartUnavailableReason == nil, let explorationActions else { return }
    explorationGeneration &+= 1
    let generation = explorationGeneration
    explorationError = nil
    explorationTimeline = []
    completedExplorationEpisodes = []
    currentExplorationEpisode = nil
    armatureGuidanceState = nil
    lastArmatureObservation = nil
    explorationCleanReference = nil
    explorationAnchoredBaseline = nil
    explorationPostLineFrame = nil
    lastAnchorObservation = nil
    lastInkObservation = nil
    explorationInkStatus = "no isolated-line observation yet"
    explorationExportPath = nil
    explorationToolPaperRevision = UUID()
    let sessionID = ExplorationSessionID()
    let input: ExplorationSessionInput =
      frameMode == .simulated && !simulatorVoicePracticeEnabled ? .injected : .microphone
    explorationSessionSnapshot = ExplorationSessionSnapshot(
      id: sessionID,
      input: input,
      state: .starting,
      voice: nil,
      activeEpisode: nil,
      latestTranscript: nil,
      latestRoutingResult: nil,
      latestFeedback: nil
    )
    let snapshot = await explorationActions.start(input, sessionID)
    guard !hasShutdown, generation == explorationGeneration else {
      await explorationActions.end()
      return
    }
    explorationSessionSnapshot = snapshot
    switch snapshot.state {
    case .listening:
      voiceListening = true
      voiceAuthorizationState = snapshot.voice?.authorization
        ?? (input == .injected ? .notDetermined : voiceAuthorizationState)
      explorationFlow.start(authority: frameMode == .simulated ? .simulated : .live)
      appendExplorationTimeline(
        participant: frameMode == .simulated ? .simulator : .voice,
        action: "start exploration",
        observation: input == .injected
          ? "permission-free deterministic speech input is active"
          : "one persistent microphone session is active"
      )
      beginExplorationUpdates(actions: explorationActions, generation: generation)
      await activateExplorationEpisode(
        rung: .motionPreflight,
        allowedIntents: [.ready, .stop, .penIsPhysicallyUp, .penIsPhysicallyDown, .skip, .endSession],
        teachingLabelKinds: [],
        stopIsCancellable: true
      )
    case .failed(let failure):
      voiceListening = false
      explorationError = "Exploration could not start: \(failure)"
    case .inactive, .starting, .ending:
      voiceListening = false
      explorationError = "Exploration did not enter listening state."
    }
  }

  func endExploration() async {
    guard let explorationActions else { return }
    explorationGeneration &+= 1
    explorationEventTask?.cancel()
    explorationEventTask = nil
    if let episode = currentExplorationEpisode {
      do {
        _ = try await explorationActions.completeEpisode(
          episode.id,
          .endedSession(utteranceID: nil)
        )
        var completed = episode
        completed.termination = .endedSession(utteranceID: nil)
        completedExplorationEpisodes.append(completed)
      } catch {
        explorationError = "Could not close the active exploration episode: \(error)"
      }
      currentExplorationEpisode = nil
    }
    await explorationActions.end()
    explorationSessionSnapshot = await explorationActions.snapshot()
    voiceListening = false
    explorationFlow.stop()
    explorationOperationInProgress = false
    appendExplorationTimeline(
      participant: .operatorHuman,
      action: "end exploration",
      observation: "microphone and episode interpretation stopped"
    )
  }

  func injectExplorationTranscript(_ transcript: VoiceTranscript) async {
    guard explorationSessionSnapshot?.input == .injected, let explorationActions else { return }
    _ = await explorationActions.ingest(transcript)
  }

  private func activateExplorationEpisode(
    rung: ExplorationLearningRung,
    allowedIntents: Set<ExplorationVoiceIntent>,
    teachingLabelKinds: Set<ExplorationTeachingLabelKind>,
    stopIsCancellable: Bool
  ) async {
    guard currentExplorationEpisode == nil,
      let sessionID = explorationSessionSnapshot?.id,
      let explorationActions
    else { return }
    let source: ExplorationSource = frameMode == .simulated ? .simulated : .live
    let episode = ExplorationEpisode(
      sessionID: sessionID,
      rung: rung,
      source: source,
      split: completedExplorationEpisodes.count.isMultiple(of: 2) ? .training : .reserved,
      startedNanoseconds: nowNanoseconds()
    )
    let context = ExplorationEpisodeVoiceContext(
      episodeID: episode.id,
      rung: rung,
      source: source,
      allowedIntents: allowedIntents,
      teachingLabelKinds: teachingLabelKinds,
      stopIsCancellable: stopIsCancellable
    )
    do {
      try await explorationActions.activateEpisode(context)
      currentExplorationEpisode = episode
    } catch {
      explorationError = "Could not activate \(rung.rawValue): \(error)"
    }
  }

  private func completeCurrentExplorationEpisode(
    termination: ExplorationEpisodeTermination
  ) async {
    guard var episode = currentExplorationEpisode, let explorationActions else { return }
    do {
      _ = try await explorationActions.completeEpisode(episode.id, termination)
      episode.termination = termination
      completedExplorationEpisodes.append(episode)
      currentExplorationEpisode = nil
    } catch {
      explorationError = "Could not complete \(episode.rung.rawValue): \(error)"
    }
  }

  func startVoiceListening() async {
    guard voiceListeningUnavailableReason == nil, let voiceActions else { return }
    voiceError = nil
    let authorization = await voiceActions.requestAuthorization()
    voiceAuthorizationState = authorization
    guard authorization == .authorized else {
      lastVoiceActionableResultText = voicePermissionText
      return
    }
    do {
      try await voiceActions.startListening()
      guard !hasShutdown else {
        await voiceActions.stopListening()
        return
      }
      voiceListening = true
      lastVoiceActionableResultText =
        "speech listening active for the current Motion Preflight sequence"
      beginVoiceUpdates(actions: voiceActions)
    } catch {
      voiceListening = false
      voiceError = actionableDescription(error)
      lastVoiceActionableResultText = "Voice listening failed: \(voiceError ?? "unknown error")"
    }
  }

  func stopVoiceListening() async {
    guard let voiceActions else { return }
    switch boundaryTeachingState {
    case .moving, .cancelling:
      lastVoiceActionableResultText =
        "Speech stays on while boundary motion is active; use the visible Cancel Jog control."
      return
    case .awaitingReady:
      boundaryTeachingState = .idle
      boundaryTeachingResultText = "Boundary interaction cancelled before motion."
    case .idle:
      break
    }
    invalidateVoiceUpdates()
    lastBoundaryStopUtteranceID = nil
    await voiceActions.stopListening()
    voiceListening = false
    lastVoiceActionableResultText = "voice listening stopped"
  }

  func startPreflightSequence(_ sequenceID: PreflightSequenceID) async {
    guard preflightStartUnavailableReason(for: sequenceID) == nil else { return }
    preflightAuthorityGeneration &+= 1
    selectedPreflightSequenceID = sequenceID
    preflightError = nil
    pendingPreflightInspection = nil
    pendingPreflightCaptureBoundaryNanoseconds = nil
    var transaction = PreflightTransaction(sequenceID: sequenceID)
    do {
      try transaction.begin()
      preflightTransactions[sequenceID] = transaction
      await advancePreflightSequence(sequenceID)
    } catch {
      preflightError = "Motion Preflight could not start: \(error)"
    }
  }

  func cancelPreflightSequence(_ sequenceID: PreflightSequenceID) async {
    if penRequestInProgress {
      preflightError = "Wait for the current pen command to settle before cancelling."
      return
    }
    guard var transaction = preflightTransactions[sequenceID] else { return }
    preflightAuthorityGeneration &+= 1
    transaction.cancel()
    preflightTransactions[sequenceID] = transaction
    if boundaryTeachingState != .idle {
      await cancelBoundaryTeaching()
      if case .moving = boundaryTeachingState { return }
      if case .cancelling = boundaryTeachingState { return }
    }
    await finishCancelledPreflight(sequenceID)
  }

  func setSimulatorVoicePracticeEnabled(_ enabled: Bool) async {
    guard simulatorVoicePracticeEnabled != enabled else { return }
    if let activePreflightRehearsalID {
      await cancelPreflightRehearsal(activePreflightRehearsalID)
    }
    simulatorVoicePracticeEnabled = enabled
    preflightError = nil
  }

  func startPreflightRehearsal(_ sequenceID: PreflightSequenceID) async {
    guard preflightRehearsalStartUnavailableReason(for: sequenceID) == nil else { return }
    preflightRehearsalGeneration &+= 1
    let generation = preflightRehearsalGeneration
    selectedPreflightSequenceID = sequenceID
    preflightError = nil
    lastPreflightRehearsalUtteranceID = nil
    var rehearsal = PreflightRehearsal(sequenceID: sequenceID)
    do {
      try rehearsal.start()
    } catch {
      preflightError = "Simulator rehearsal could not start: \(error)"
      return
    }
    preflightRehearsals[sequenceID] = rehearsal
    continuePreflightRehearsal(sequenceID, generation: generation)
  }

  private func continuePreflightRehearsal(
    _ sequenceID: PreflightSequenceID,
    generation: UInt64
  ) {
    preflightRehearsalTask?.cancel()
    preflightRehearsalTask = Task { [weak self] in
      guard let self else { return }
      while !Task.isCancelled {
        do {
          try await Task.sleep(nanoseconds: self.preflightRehearsalStepDelayNanoseconds)
        } catch {
          return
        }
        guard self.preflightRehearsalIsCurrent(sequenceID, generation: generation),
          var current = self.preflightRehearsals[sequenceID],
          current.state == .running,
          let step = current.currentStep
        else { return }

        if self.simulatorVoicePracticeEnabled {
          switch step.action {
          case .startSpeechListening:
            let started = await self.startPreflightRehearsalVoiceListening(
              for: sequenceID,
              generation: generation
            )
            guard self.preflightRehearsalIsCurrent(sequenceID, generation: generation)
            else { return }
            guard started else {
              await self.failPreflightRehearsal(
                sequenceID,
                generation: generation,
                reason: self.voiceError ?? self.voicePermissionText
              )
              return
            }

          case .stopSpeechListening:
            await self.stopPreflightRehearsalVoiceListening(for: sequenceID)
            guard self.preflightRehearsalIsCurrent(sequenceID, generation: generation)
            else { return }

          case .speakPrompt(let prompt):
            await self.voiceActions?.speak(prompt)
            self.lastSpokenFeedbackText = prompt
            guard self.preflightRehearsalIsCurrent(sequenceID, generation: generation)
            else { return }

          case .awaitVoice, .awaitPhysicalPenConfirmation:
            self.preflightRehearsalTask = nil
            return

          default:
            break
          }
        }

        do {
          try current.advance()
          self.preflightRehearsals[sequenceID] = current
          if case .actuatePen(let command) = step.action {
            self.simulatorPenState = command.commandedState
          }
          if current.state == .completed {
            self.preflightRehearsalTask = nil
            return
          }
        } catch {
          self.preflightError = "Simulator rehearsal failed: \(error)"
          self.preflightRehearsalTask = nil
          return
        }
      }
    }
  }

  func cancelPreflightRehearsal(_ sequenceID: PreflightSequenceID) async {
    guard var rehearsal = preflightRehearsals[sequenceID] else { return }
    preflightRehearsalGeneration &+= 1
    preflightRehearsalTask?.cancel()
    preflightRehearsalTask = nil
    rehearsal.cancel()
    preflightRehearsals[sequenceID] = rehearsal
    await stopPreflightRehearsalVoiceListening(for: sequenceID)
  }

  private func cancelActivePreflightRehearsal() async {
    guard let activePreflightRehearsalID else { return }
    await cancelPreflightRehearsal(activePreflightRehearsalID)
  }

  private func preflightRehearsalIsCurrent(
    _ sequenceID: PreflightSequenceID,
    generation: UInt64
  ) -> Bool {
    !hasShutdown && frameMode == .simulated
      && preflightRehearsalGeneration == generation
      && activePreflightRehearsalID == sequenceID
  }

  private func startPreflightRehearsalVoiceListening(
    for sequenceID: PreflightSequenceID,
    generation: UInt64
  ) async -> Bool {
    guard preflightRehearsalIsCurrent(sequenceID, generation: generation),
      simulatorVoicePracticeEnabled,
      preflightRehearsalVoiceStartupGeneration == nil,
      !voiceListening,
      let voiceActions
    else { return false }

    preflightRehearsalVoiceStartupGeneration = generation
    defer {
      if preflightRehearsalVoiceStartupGeneration == generation {
        preflightRehearsalVoiceStartupGeneration = nil
      }
    }

    voiceError = nil
    let authorization = await voiceActions.requestAuthorization()
    guard !Task.isCancelled,
      preflightRehearsalIsCurrent(sequenceID, generation: generation),
      simulatorVoicePracticeEnabled
    else { return false }
    voiceAuthorizationState = authorization
    guard authorization == .authorized else {
      lastVoiceActionableResultText = voicePermissionText
      return false
    }

    do {
      try await voiceActions.startListening()
      guard !Task.isCancelled,
        preflightRehearsalIsCurrent(sequenceID, generation: generation),
        simulatorVoicePracticeEnabled
      else {
        await voiceActions.stopListening()
        return false
      }
      voiceListening = true
      preflightRehearsalListeningID = sequenceID
      lastVoiceActionableResultText =
        "speech listening active for simulator voice practice"
      beginVoiceUpdates(actions: voiceActions)
      return true
    } catch {
      guard preflightRehearsalIsCurrent(sequenceID, generation: generation) else {
        await voiceActions.stopListening()
        return false
      }
      voiceListening = false
      voiceError = actionableDescription(error)
      lastVoiceActionableResultText = "Voice rehearsal failed: \(voiceError ?? "unknown error")"
      return false
    }
  }

  private func stopPreflightRehearsalVoiceListening(
    for sequenceID: PreflightSequenceID
  ) async {
    guard preflightRehearsalListeningID == sequenceID
      || preflightRehearsalVoiceStartupGeneration != nil
    else { return }
    invalidateVoiceUpdates()
    await voiceActions?.stopListening()
    voiceListening = false
    preflightRehearsalListeningID = nil
    lastVoiceActionableResultText = "simulator voice practice stopped"
  }

  private func failPreflightRehearsal(
    _ sequenceID: PreflightSequenceID,
    generation: UInt64,
    reason: String
  ) async {
    guard preflightRehearsalIsCurrent(sequenceID, generation: generation) else { return }
    preflightError = "Simulator voice rehearsal failed: \(reason)"
    await cancelPreflightRehearsal(sequenceID)
  }

  private func advancePreflightSequence(_ sequenceID: PreflightSequenceID) async {
    while !hasShutdown, activePreflightSequenceID == sequenceID,
      let step = preflightTransactions[sequenceID]?.currentStep
    {
      switch step.action {
      case .startSpeechListening:
        guard explorationIsActive, currentExplorationEpisode?.rung == .motionPreflight else {
          await failPreflight(
            sequenceID,
            reason: "Start one Exploration session before Motion Preflight."
          )
          return
        }
        guard recordPreflight(.speechListeningStarted, for: sequenceID) else { return }

      case .stopSpeechListening:
        guard recordPreflight(.speechListeningStopped, for: sequenceID) else { return }

      case .speakPrompt(let prompt):
        lastVoiceActionableResultText = prompt
        let spoken = "Motion Preflight is ready. Follow the displayed instruction."
        _ = await explorationActions?.speakFeedback(spoken)
        guard recordPreflight(.promptSpoken, for: sequenceID) else { return }

      case .awaitVoice(.ready):
        guard let direction = jogDirection(for: sequenceID) else {
          await failPreflight(sequenceID, reason: "Boundary direction is unavailable.")
          return
        }
        boundaryTeachingState = .awaitingReady(direction)
        boundaryTeachingResultText =
          "\(direction.shortLabel) armed. Speech is listening; say READY, then STOP at the boundary."
        await voiceActions?.signal()
        return

      case .awaitVoice, .awaitPhysicalPenConfirmation:
        return

      case .startBoundaryJog(let direction):
        guard boundaryMotionTask == nil else { return }
        let jogDirection = jogDirection(from: direction)
        boundaryMotionTask = Task { [weak self] in
          guard let self else { return }
          await self.executeBoundaryMotion(jogDirection)
          self.boundaryMotionTask = nil
        }
        return

      case .cancelBoundaryJogAndAwaitIdle(let direction):
        guard boundaryCancelTask == nil else { return }
        boundaryTeachingState = .cancelling(jogDirection(from: direction))
        boundaryTeachingResultText = "Jog cancellation requested. Waiting for final controller position."
        boundaryCancelTask = Task { [weak self] in
          guard let self else { return }
          await self.requestJogCancel()
          self.boundaryCancelTask = nil
        }
        return

      case .actuatePen(let command):
        await requestPenActuation(command)
        guard case .commandedAndSettled = machineSnapshot?.lastPenOutcome else {
          await failPreflight(sequenceID, reason: lastPenOutcomeText)
          return
        }
        guard recordPreflight(
          .penCommandSettled(command, controllerSummary: lastPenOutcomeText),
          for: sequenceID
        ) else { return }

      case .captureFreshCameraFrame:
        guard await capturePreflightInspection(sequenceID) else { return }

      case .measureBoundary(let direction):
        guard let inspection = pendingPreflightInspection,
          let estimate = inspection.measurement.drawingFrame,
          let controllerPosition = boundaryPositions[jogDirection(from: direction)],
          let observedToolCentroid = inspection.measurement.cap?.centroid
        else {
          await failPreflight(
            sequenceID,
            reason:
              "Boundary preflight requires final controller MPos, the observed tool centroid, and a drawing-frame estimate on the exact fresh frame."
          )
          return
        }
        let measurement = inspection.measurement
        let summary =
          "controller boundary paired with the observed tool centroid and visible frame sides; unobserved sides remain inferred"
        guard recordPreflight(
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

  private func capturePreflightInspection(_ sequenceID: PreflightSequenceID) async -> Bool {
    guard let cameraActions else {
      await failPreflight(sequenceID, reason: "Native camera composition is unavailable.")
      return false
    }
    guard let captureBoundary = pendingPreflightCaptureBoundaryNanoseconds else {
      await failPreflight(
        sequenceID,
        reason: "No controller or operator event boundary is available for a fresh frame."
      )
      return false
    }
    do {
      guard let inspection = try await cameraActions.inspectScene(captureBoundary) else {
        await failPreflight(
          sequenceID,
          reason: "No live frame newer than the completed preflight event is available."
        )
        return false
      }
      guard inspection.displayedFrame.frame.captureNanoseconds > captureBoundary else {
        await failPreflight(
          sequenceID,
          reason: "Camera returned a frame that predates the completed preflight event."
        )
        return false
      }
      pendingPreflightInspection = inspection
      pendingPreflightCaptureBoundaryNanoseconds = nil
      displayedFrame = inspection.displayedFrame
      latestLiveCameraFrame = inspection.displayedFrame
      lastSceneMeasurement = inspection.measurement
      cameraOverlays = inspection.measurement.overlays
      return recordPreflight(
        .freshFrameCaptured(
          inspection.measurement.frameID,
          inspection.measurement.cameraConfigurationID
        ),
        for: sequenceID
      )
    } catch {
      await failPreflight(sequenceID, reason: actionableDescription(error))
      return false
    }
  }

  private func updateDrawingFramePosterior(
    direction: PreflightBoundaryDirection,
    sequenceID: PreflightSequenceID
  ) -> Bool {
    guard let inspection = pendingPreflightInspection,
      let estimate = inspection.measurement.drawingFrame,
      let controllerPosition = boundaryPositions[jogDirection(from: direction)],
      let observedToolCentroid = inspection.measurement.cap?.centroid
    else {
      preflightError =
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
            algorithmRevision: "motion-preflight-posterior-v2"
          )
        )
      })
      return recordPreflight(
        .drawingFramePosteriorAdjusted(
          direction,
          frameID: measurement.frameID,
          cameraConfigurationID: measurement.cameraConfigurationID,
          observationCount: drawingFramePosterior.observationCount
        ),
        for: sequenceID
      )
    } catch {
      preflightError = "Drawing-frame posterior update failed: \(error)"
      if var transaction = preflightTransactions[sequenceID] {
        transaction.fail(preflightError ?? "Drawing-frame posterior update failed.")
        preflightTransactions[sequenceID] = transaction
      }
      return false
    }
  }

  private func recordPreflight(_ event: PreflightEvent, for sequenceID: PreflightSequenceID) -> Bool {
    guard var transaction = preflightTransactions[sequenceID] else { return false }
    do {
      try transaction.record(event)
      preflightTransactions[sequenceID] = transaction
      return true
    } catch {
      transaction.fail("Unexpected preflight event: \(error)")
      preflightTransactions[sequenceID] = transaction
      preflightError = "Unexpected Motion Preflight event: \(error)"
      return false
    }
  }

  private func failPreflight(_ sequenceID: PreflightSequenceID, reason: String) async {
    if var transaction = preflightTransactions[sequenceID] {
      transaction.fail(reason)
      preflightTransactions[sequenceID] = transaction
    }
    preflightError = reason
    boundaryTeachingState = .idle
    pendingPreflightInspection = nil
    pendingPreflightCaptureBoundaryNanoseconds = nil
    lastVoiceActionableResultText = "Motion Preflight stopped: \(reason)"
  }

  private func finishCancelledPreflight(_ sequenceID: PreflightSequenceID) async {
    if preflightTransactions[sequenceID]?.currentStep?.action == .stopSpeechListening {
      _ = recordPreflight(.speechListeningStopped, for: sequenceID)
    }
    pendingPreflightInspection = nil
    pendingPreflightCaptureBoundaryNanoseconds = nil
    lastVoiceActionableResultText =
      "Motion Preflight transaction cancelled; Exploration listening remains active."
  }

  func beginBoundaryTeaching(_ direction: JogDirection) async {
    guard boundaryTeachingUnavailableReason == nil, let voiceActions else { return }
    if !voiceListening {
      await startVoiceListening()
    }
    guard voiceListening else { return }
    lastBoundaryStopUtteranceID = nil
    boundaryTeachingState = .awaitingReady(direction)
    boundaryTeachingResultText =
      "\(direction.shortLabel) armed. Confirm the pen is physically up and clear, then say READY."
    lastVoiceIntentText = "boundary \(direction.shortLabel) armed"
    lastVoiceActionableResultText = boundaryTeachingResultText
    await voiceActions.signal()
    await publishVoiceFeedback(
      result: boundaryTeachingResultText,
      spoken: "Boundary interaction armed. Confirm the tool is physically up and clear, then use the displayed confirmation."
    )
  }

  func cancelBoundaryTeaching() async {
    switch boundaryTeachingState {
    case .idle:
      return
    case .awaitingReady:
      boundaryTeachingState = .idle
      boundaryTeachingResultText = "Boundary interaction cancelled before motion."
    case .moving(let direction):
      boundaryTeachingState = .cancelling(direction)
      boundaryTeachingResultText = "Jog cancellation requested. Waiting for final controller position."
      await requestJogCancel()
    case .cancelling:
      return
    }
  }

  func requestJogCancel() async {
    guard let generation = beginHardwareIntent() else { return }
    defer { endHardwareIntent() }
    guard jogCancelUnavailableReason == nil, let machineActions else { return }
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

  func performMotionGuardControlAction() async {
    guard motionGuardControlUnavailableReason == nil else { return }
    if motionGuardIsActive {
      await deactivateMotionGuard()
    } else {
      await activateMotionGuard()
    }
  }

  private func deactivateMotionGuard() async {
    guard let generation = beginHardwareIntent() else { return }
    defer { endHardwareIntent() }
    guard motionGuardControlUnavailableReason == nil, motionGuardIsActive,
      let machineActions
    else { return }
    motionGuardActivationInProgress = true
    defer { motionGuardActivationInProgress = false }
    await machineActions.deactivateMotionGuard()
    let snapshot = await machineActions.snapshot()
    guard canCommit(generation) else { return }
    machineSnapshot = snapshot
    lastMotionGuardActivationText = "deactivated for this controller session"
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
    defer { jogRequestInProgress = false }
    let recordsObservation = recordJogObservations
    let observationSplit = selectedObservationSplit
    let operation = Task { () -> (PhysicalJogObservationOutcome?, MotionOutcome?) in
      if recordsObservation {
        guard let cameraActions else {
          return (
            .notRecorded(
              motionOutcome: nil,
              failure: .liveCameraRequired
            ),
            nil
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
        return (outcome, outcome.motionOutcome)
      }
      let outcome = await machineActions.requestRelativeJog(request)
      return (nil, outcome)
    }
    await Task.yield()
    let interimSnapshot = await machineActions.snapshot()
    if canCommit(generation) { machineSnapshot = interimSnapshot }
    let (observationOutcome, motionOutcome) = await operation.value
    let finalSnapshot = await machineActions.snapshot()
    guard canCommit(generation) else { return nil }
    machineSnapshot = finalSnapshot
    if recordsObservation, let outcome = observationOutcome {
      switch outcome {
      case .recorded(let observation):
        physicalJogObservations.append(observation)
        recordJogResponseEpisode(observation)
      case .notRecorded:
        break
      }
    }
    return motionOutcome
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
    guard let cameraActions, !explorationOwnsAuthority else {
      cameraError = "End Exploration before changing its camera configuration."
      return
    }
    clearAutomaticVisionPresentation()
    await clearPreflightAuthority()
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
    guard !explorationOwnsAuthority else {
      cameraError = "End Exploration before restarting its camera configuration."
      return
    }
    frameTask?.cancel()
    frameTask = nil
    clearAutomaticVisionPresentation()
    await clearPreflightAuthority()
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
    if mode == .live { await cancelActivePreflightRehearsal() }
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
    await cancelActivePreflightRehearsal()
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
    preflightRehearsalGeneration &+= 1
    preflightRehearsalTask?.cancel()
    preflightRehearsalTask = nil
    stopObserving()
    explorationGeneration &+= 1
    explorationEventTask?.cancel()
    explorationEventTask = nil
    invalidateVoiceUpdates()
    lastBoundaryStopUtteranceID = nil
    lastPreflightRehearsalUtteranceID = nil
    await voiceActions?.stopListening()
    await voiceActions?.stopSpeaking()
    await explorationActions?.end()
    voiceListening = false
    preflightRehearsalListeningID = nil
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

  private func beginExplorationUpdates(
    actions: ExplorationActions,
    generation: UInt64
  ) {
    explorationEventTask?.cancel()
    explorationEventTask = Task { [weak self] in
      let stream = await actions.events()
      for await event in stream {
        guard !Task.isCancelled, let self,
          !self.hasShutdown, self.explorationGeneration == generation
        else { return }
        await self.receiveExplorationEvent(event)
      }
    }
  }

  private func receiveExplorationEvent(_ event: ExplorationSessionEvent) async {
    switch event {
    case .stateChanged(let state):
      explorationSessionSnapshot = await explorationActions?.snapshot()
      switch state {
      case .listening:
        voiceListening = true
      case .inactive, .ending:
        voiceListening = false
      case .starting:
        break
      case .failed(let failure):
        voiceListening = false
        explorationError = "Exploration voice failed: \(failure)"
        explorationFlow.stop()
      }

    case .episodeActivated(let context):
      appendExplorationTimeline(
        participant: .voice,
        action: "activate \(context.rung.rawValue)",
        observation: "contextual intents only; microphone ownership unchanged"
      )

    case .episodeCompleted(_, let termination):
      appendExplorationTimeline(
        participant: .voice,
        action: "complete active episode",
        observation: "\(termination) · listening remains active"
      )

    case .feedback(let receipt):
      lastSpokenFeedbackText = receipt.text
      if var episode = currentExplorationEpisode, !episode.speech.isEmpty {
        episode.speech[episode.speech.count - 1].attachFeedback(receipt)
        currentExplorationEpisode = episode
      }

    case .routed(let routing):
      explorationSessionSnapshot = await explorationActions?.snapshot()
      switch routing {
      case .acceptedIntent(let receipt):
        voiceTranscriptText = receipt.transcript.text
        lastVoiceIntentText = receipt.intent.rawValue
        if var episode = currentExplorationEpisode {
          episode.speech.append(ExplorationSpeechRecord(receipt))
          currentExplorationEpisode = episode
        }
        appendExplorationTimeline(
          participant: .operatorHuman,
          action: "say \(receipt.transcript.text)",
          observation: "accepted as \(receipt.intent.rawValue)"
        )
        if receipt.intent == .endSession {
          await endExploration()
          return
        }
        if receipt.intent == .stop, explorationOperationInProgress, frameMode == .live {
          await requestJogCancel()
          return
        }
        if receipt.context.rung == .armatureGuidance {
          switch receipt.intent {
          case .xNegative: await moveArmature(.negativeXOneMillimeter)
          case .xPositive: await moveArmature(.positiveXOneMillimeter)
          case .yNegative: await moveArmature(.negativeYOneMillimeter)
          case .yPositive: await moveArmature(.positiveYOneMillimeter)
          case .accept: await acceptCurrentArmaturePose()
          default: break
          }
          return
        }
        await receiveVoiceTranscript(
          receipt.transcript,
          listenerGeneration: voiceListenerGeneration
        )

      case .acceptedTeachingLabel(let receipt):
        voiceTranscriptText = receipt.transcript.text
        lastVoiceIntentText = "teaching label"
        if var episode = currentExplorationEpisode {
          episode.speech.append(ExplorationSpeechRecord(receipt))
          episode.humanAssessment = ExplorationAssessment(
            summary: receipt.label.rawTranscript,
            provenance: "voice utterance \(receipt.transcript.utteranceID.uuidString.lowercased())"
          )
          currentExplorationEpisode = episode
        }
        appendExplorationTimeline(
          participant: .operatorHuman,
          action: "teach",
          observation: receipt.label.rawTranscript
        )
        await receiveExplorationTeachingLabel(receipt)

      case .rejected(let rejection):
        lastVoiceIntentText = "rejected · \(rejection.rawValue)"
      }
    }
  }

  private func receiveExplorationTeachingLabel(
    _ receipt: AcceptedExplorationTeachingLabel
  ) async {
    switch receipt.label.classification {
    case .visibility(let label, _):
      lastVoiceActionableResultText = "Armature visibility: \(label.rawValue)"
      let runtimeLabel: ArmatureVisibilityLabel = switch label {
      case .clear: .clear
      case .partial: .partial
      case .blocked: .blocked
      }
      await recordArmatureVisibility(runtimeLabel)
    case .shapeFeature, .ranking, .reward:
      lastVoiceActionableResultText = "Human assessment recorded."
      if explorationFlow.phase == .awaitingAssessment {
        do {
          try explorationFlow.acceptAssessment(receipt.label.rawTranscript)
          await completeCurrentExplorationEpisode(termination: .completed)
        } catch {
          explorationError = "Could not accept assessment: \(error)"
        }
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
      controllerSessionID: explorationControllerSessionID,
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
    _ observation: IsolatedInkObservation,
    source: ExplorationTimelineEntry.Participant
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
    appendExplorationTimeline(
      participant: source,
      action: "observe isolated ink",
      observation: explorationEvidenceText
    )
  }

  private func returnToAcceptedClearPose() async throws {
    guard let guidance = armatureGuidanceState,
      let current = machineSnapshot?.machine.position,
      let machineActions
    else { throw ExplorationLiveError.controllerOutcome("clear-pose state unavailable") }
    if guidance.acceptedClearPose?.position == current { return }
    let request = try guidance.penUpReturnRequest(
      from: current,
      currentContext: guidance.context
    )
    let outcome = await machineActions.requestRelativeJog(request)
    machineSnapshot = await machineActions.snapshot()
    guard case .acceptedThenCompleted(let final) = outcome,
      final == guidance.acceptedClearPose?.position
    else {
      throw ExplorationLiveError.controllerOutcome(String(describing: outcome))
    }
    appendExplorationTimeline(
      participant: .controller,
      action: "return to accepted clear pose",
      observation: "Idle with exact final MPos"
    )
  }

  private func appendExplorationTimeline(
    participant: ExplorationTimelineEntry.Participant,
    action: String,
    observation: String
  ) {
    explorationTimeline.append(
      ExplorationTimelineEntry(
        monotonicNanoseconds: nowNanoseconds(),
        participant: participant,
        action: action,
        observation: observation
      ))
    if explorationTimeline.count > 24 {
      explorationTimeline.removeFirst(explorationTimeline.count - 24)
    }
  }

  private func beginVoiceUpdates(actions: VoiceActions) {
    invalidateVoiceUpdates()
    let generation = voiceListenerGeneration
    beginVoiceTranscriptUpdates(actions: actions, generation: generation)
    beginVoiceStateUpdates(actions: actions, generation: generation)
  }

  private func invalidateVoiceUpdates() {
    voiceListenerGeneration &+= 1
    voiceTranscriptTask?.cancel()
    voiceTranscriptTask = nil
    voiceStateTask?.cancel()
    voiceStateTask = nil
  }

  private func beginVoiceTranscriptUpdates(actions: VoiceActions, generation: UInt64) {
    voiceTranscriptTask = Task { [weak self] in
      let stream = await actions.transcripts()
      for await transcript in stream {
        guard !Task.isCancelled, let self,
          self.voiceListenerGeneration == generation
        else { return }
        await self.receiveVoiceTranscript(transcript, listenerGeneration: generation)
      }
      guard !Task.isCancelled, let self, !self.hasShutdown,
        self.voiceListenerGeneration == generation
      else { return }
      let snapshot = await actions.snapshot()
      guard !Task.isCancelled, !self.hasShutdown,
        self.voiceListenerGeneration == generation
      else { return }
      self.receiveVoiceSnapshot(snapshot, listenerGeneration: generation)
    }
  }

  private func beginVoiceStateUpdates(actions: VoiceActions, generation: UInt64) {
    voiceStateTask = Task { [weak self] in
      while !Task.isCancelled {
        let snapshot = await actions.snapshot()
        guard !Task.isCancelled, let self, !self.hasShutdown,
          self.voiceListenerGeneration == generation
        else { return }
        self.receiveVoiceSnapshot(snapshot, listenerGeneration: generation)
        guard case .listening = snapshot.listeningState else { return }
        try? await Task.sleep(nanoseconds: 250_000_000)
      }
    }
  }

  private func receiveVoiceSnapshot(
    _ snapshot: VoiceInteractionSnapshot,
    listenerGeneration: UInt64
  ) {
    guard listenerGeneration == voiceListenerGeneration else { return }
    voiceAuthorizationState = snapshot.authorization
    switch snapshot.listeningState {
    case .listening:
      voiceListening = true
    case .stopped, .requestingPermission:
      let lostActiveListener = voiceListening
      voiceListening = false
      if lostActiveListener {
        failClosedPreflightRehearsalAfterSpeechLoss("Speech listening stopped unexpectedly.")
        failClosedBoundaryAfterSpeechLoss("Speech listening stopped unexpectedly.")
      }
    case .failed(let error):
      voiceListening = false
      voiceError = error.actionableDescription
      lastVoiceActionableResultText = error.actionableDescription
      failClosedPreflightRehearsalAfterSpeechLoss(error.actionableDescription)
      failClosedBoundaryAfterSpeechLoss(error.actionableDescription)
    }
  }

  private func failClosedPreflightRehearsalAfterSpeechLoss(_ reason: String) {
    guard let sequenceID = preflightRehearsalListeningID,
      var rehearsal = preflightRehearsals[sequenceID],
      rehearsal.state == .running
    else { return }
    preflightRehearsalGeneration &+= 1
    preflightRehearsalTask?.cancel()
    preflightRehearsalTask = nil
    rehearsal.cancel()
    preflightRehearsals[sequenceID] = rehearsal
    preflightRehearsalListeningID = nil
    preflightError = "Simulator voice rehearsal failed: \(reason)"
    invalidateVoiceUpdates()
  }

  private func failClosedBoundaryAfterSpeechLoss(_ reason: String) {
    if let sequenceID = activePreflightSequenceID,
      var transaction = preflightTransactions[sequenceID]
    {
      transaction.fail(reason)
      preflightTransactions[sequenceID] = transaction
      preflightError = reason
    }
    switch boundaryTeachingState {
    case .idle:
      return
    case .awaitingReady:
      boundaryTeachingState = .idle
      boundaryTeachingResultText = "Boundary interaction cancelled: \(reason)"
    case .moving(let direction):
      boundaryTeachingState = .cancelling(direction)
      boundaryTeachingResultText =
        "Speech failed during motion. Requesting Jog Cancel; use the visible cancel control if needed."
      guard boundaryCancelTask == nil else { return }
      boundaryCancelTask = Task { [weak self] in
        guard let self else { return }
        await self.requestJogCancel()
        self.boundaryCancelTask = nil
      }
    case .cancelling:
      return
    }
  }

  private func receiveVoiceTranscript(
    _ transcript: VoiceTranscript,
    listenerGeneration: UInt64
  ) async {
    guard voiceListening, !hasShutdown,
      listenerGeneration == voiceListenerGeneration
    else { return }
    voiceTranscriptText = transcript.text.isEmpty ? "none" : transcript.text

    if simulatorVoicePracticeEnabled,
      let sequenceID = activePreflightRehearsalID,
      preflightRehearsalListeningID == sequenceID,
      var rehearsal = preflightRehearsals[sequenceID],
      let context = rehearsal.voiceContext,
      let response = PreflightVoiceResponseParser().parse(transcript.text, in: context)
    {
      switch response {
      case .ready, .penIsPhysicallyUp, .penIsPhysicallyDown:
        guard transcript.isFinal else { return }
      case .stop:
        guard lastPreflightRehearsalUtteranceID != transcript.utteranceID else { return }
        lastPreflightRehearsalUtteranceID = transcript.utteranceID
      }
      let generation = preflightRehearsalGeneration
      do {
        try rehearsal.advance()
        preflightRehearsals[sequenceID] = rehearsal
        lastVoiceIntentText = "Simulator rehearsal accepted \(response.exactPhrase)"
        continuePreflightRehearsal(sequenceID, generation: generation)
      } catch {
        await failPreflightRehearsal(
          sequenceID,
          generation: generation,
          reason: actionableDescription(error)
        )
      }
      return
    }

    if let sequenceID = activePreflightSequenceID,
      let context = preflightTransactions[sequenceID]?.voiceContext
    {
      guard let response = PreflightVoiceResponseParser().parse(transcript.text, in: context)
      else { return }
      switch response {
      case .ready:
        guard transcript.isFinal, boundaryMotionTask == nil else { return }
        lastVoiceIntentText = "Motion Preflight accepted READY"
        guard recordPreflight(.exactVoiceResponseAccepted(.ready), for: sequenceID) else { return }
        await advancePreflightSequence(sequenceID)

      case .stop:
        guard lastBoundaryStopUtteranceID != transcript.utteranceID,
          boundaryCancelTask == nil
        else { return }
        lastBoundaryStopUtteranceID = transcript.utteranceID
        lastVoiceIntentText = "Motion Preflight accepted STOP"
        guard recordPreflight(.exactVoiceResponseAccepted(.stop), for: sequenceID) else { return }
        await advancePreflightSequence(sequenceID)

      case .penIsPhysicallyUp:
        guard transcript.isFinal else { return }
        lastVoiceIntentText = "operator confirmed pen physically up"
        pendingPreflightCaptureBoundaryNanoseconds = nowNanoseconds()
        guard recordPreflight(
          .physicalPenConfirmed(
            .up,
            response: .penIsPhysicallyUp,
            operatorSummary: "Exact voice confirmation accepted."
          ),
          for: sequenceID
        ) else { return }
        await advancePreflightSequence(sequenceID)

      case .penIsPhysicallyDown:
        guard transcript.isFinal else { return }
        lastVoiceIntentText = "operator confirmed pen physically down"
        pendingPreflightCaptureBoundaryNanoseconds = nowNanoseconds()
        guard recordPreflight(
          .physicalPenConfirmed(
            .down,
            response: .penIsPhysicallyDown,
            operatorSummary: "Exact voice confirmation accepted."
          ),
          for: sequenceID
        ) else { return }
        await advancePreflightSequence(sequenceID)
      }
      return
    }

    let parser = BoundaryVoiceCommandParser()
    switch boundaryTeachingState {
    case .idle:
      lastVoiceIntentText = "none · no boundary interaction armed"

    case .awaitingReady(let direction):
      guard transcript.isFinal,
        parser.parse(transcript.text, in: .awaitingReady) == .ready,
        boundaryMotionTask == nil
      else { return }
      lastVoiceIntentText = "boundary \(direction.shortLabel) ready"
      boundaryMotionTask = Task { [weak self] in
        guard let self else { return }
        await self.executeBoundaryMotion(direction)
        self.boundaryMotionTask = nil
      }

    case .moving(let direction):
      guard parser.parse(transcript.text, in: .moving) == .stop,
        lastBoundaryStopUtteranceID != transcript.utteranceID,
        boundaryCancelTask == nil
      else { return }
      lastBoundaryStopUtteranceID = transcript.utteranceID
      boundaryTeachingState = .cancelling(direction)
      boundaryTeachingResultText = "Jog cancellation requested. Waiting for final controller position."
      lastVoiceIntentText = "boundary \(direction.shortLabel) interruption"
      boundaryCancelTask = Task { [weak self] in
        guard let self else { return }
        await self.requestJogCancel()
        self.boundaryCancelTask = nil
      }

    case .cancelling:
      return
    }
  }

  private func executeBoundaryMotion(_ direction: JogDirection) async {
    guard let request = makeBoundaryJogRequest(direction) else {
      boundaryTeachingState = .idle
      return
    }
    let motionTask = Task { [weak self] in
      await self?.requestRelativeJog(request)
    }
    await Task.yield()
    if jogRequestInProgress {
      while jogRequestInProgress {
        if let snapshot = await machineActions?.snapshot() {
          machineSnapshot = snapshot
          if snapshot.machine.connection == .moving {
            boundaryTeachingState = .moving(direction)
            boundaryTeachingResultText =
              "Moving \(direction.shortLabel). The active Motion Preflight transaction now accepts STOP."
            if let sequenceID = activePreflightSequenceID {
              _ = recordPreflight(
                .boundaryJogStarted(
                  preflightBoundaryDirection(from: direction),
                  controllerSummary: "Closed jog accepted and controller reported moving."
                ),
                for: sequenceID
              )
            }
            await voiceActions?.signal()
            break
          }
        }
        try? await Task.sleep(nanoseconds: 10_000_000)
      }
    }
    let exactOutcome = await motionTask.value

    guard !hasShutdown else { return }
    boundaryTeachingState = .idle
    guard let outcome = exactOutcome else {
      boundaryTeachingResultText = "No motion outcome is available; no boundary was recorded."
      if let sequenceID = activePreflightSequenceID {
        await failPreflight(sequenceID, reason: boundaryTeachingResultText)
      }
      await publishVoiceFeedback(
        result: boundaryTeachingResultText,
        spoken: "No motion outcome is available. No side position was recorded."
      )
      return
    }
    switch outcome {
    case .cancelled(let finalPosition):
      pendingPreflightCaptureBoundaryNanoseconds = nowNanoseconds()
      boundaryPositions[direction] = finalPosition
      boundaryTeachingResultText = String(
        format: "%@ recorded at X %.3f Y %.3f from cancelled jog final position.",
        direction.shortLabel,
        finalPosition.point.x,
        finalPosition.point.y
      )
      if let sequenceID = activePreflightSequenceID {
        if case .cancelling = preflightTransactions[sequenceID]?.state {
          await finishCancelledPreflight(sequenceID)
          return
        }
        guard recordPreflight(
          .boundaryJogCancelled(
            preflightBoundaryDirection(from: direction),
            finalPosition: finalPosition,
            controllerSummary: boundaryTeachingResultText
          ),
          for: sequenceID
        ) else { return }
        await advancePreflightSequence(sequenceID)
      }
      await publishVoiceFeedback(
        result: boundaryTeachingResultText,
        spoken: "Side position recorded from the interrupted movement."
      )
    case .acceptedThenCompleted:
      boundaryTeachingResultText =
        "The boundary-search jog completed without a STOP event. No boundary was recorded."
      if let sequenceID = activePreflightSequenceID {
        await failPreflight(sequenceID, reason: boundaryTeachingResultText)
      }
      await publishVoiceFeedback(
        result: boundaryTeachingResultText,
        spoken: "The bounded movement completed. No side position was recorded."
      )
    case .refused(let refusal):
      boundaryTeachingResultText = "Motion refused: \(refusal.actionableDescription)"
      if let sequenceID = activePreflightSequenceID {
        await failPreflight(sequenceID, reason: boundaryTeachingResultText)
      }
      await publishVoiceFeedback(
        result: boundaryTeachingResultText,
        spoken: "Movement refused. Check the displayed reason."
      )
    case .ambiguous(let ambiguity):
      boundaryTeachingResultText = "Motion ambiguous: \(ambiguity.actionableDescription)"
      if let sequenceID = activePreflightSequenceID {
        await failPreflight(sequenceID, reason: boundaryTeachingResultText)
      }
      await publishVoiceFeedback(
        result: boundaryTeachingResultText,
        spoken: "Movement outcome is ambiguous. No side position was recorded."
      )
    }
  }

  private func makeBoundaryJogRequest(_ direction: JogDirection) -> RelativeJogRequest? {
    guard boundaryTeachingState == .awaitingReady(direction),
      motionUnavailableReason == nil,
      let feed = inputNumber(feedText), feed > 0
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
      return RelativeJogRequest(delta: delta, feedMMPerMinute: feed)
    } catch {
      boundaryTeachingResultText = "Boundary motion request is invalid; no motion was sent."
      return nil
    }
  }

  private func jogDirection(for sequenceID: PreflightSequenceID) -> JogDirection? {
    switch sequenceID {
    case .boundaryNegativeX: .xNegative
    case .boundaryPositiveX: .xPositive
    case .boundaryNegativeY: .yNegative
    case .boundaryPositiveY: .yPositive
    case .penUpConfirmation, .penDownConfirmation: nil
    }
  }

  private func jogDirection(from direction: PreflightBoundaryDirection) -> JogDirection {
    switch direction {
    case .negativeX: .xNegative
    case .positiveX: .xPositive
    case .negativeY: .yNegative
    case .positiveY: .yPositive
    }
  }

  private func preflightBoundaryDirection(from direction: JogDirection)
    -> PreflightBoundaryDirection
  {
    switch direction {
    case .xNegative: .negativeX
    case .xPositive: .positiveX
    case .yNegative: .negativeY
    case .yPositive: .positiveY
    }
  }

  private func publishVoiceFeedback(result: String, spoken: String) async {
    guard !hasShutdown else { return }
    let commandFreeSpoken = commandFreeSpokenFeedback(spoken)
    lastVoiceActionableResultText = result
    lastSpokenFeedbackText = commandFreeSpoken
    if explorationIsActive {
      _ = await explorationActions?.speakFeedback(commandFreeSpoken)
    } else {
      await voiceActions?.speak(commandFreeSpoken)
    }
  }

  private func commandFreeSpokenFeedback(_ candidate: String) -> String {
    let parser = BoundaryVoiceCommandParser()
    if parser.parse(candidate, in: .awaitingReady) != nil
      || parser.parse(candidate, in: .moving) != nil
    {
      return "Current result is shown in the voice panel."
    }
    return candidate
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
    await clearPreflightAuthority()
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

  private func clearPreflightAuthority() async {
    preflightAuthorityGeneration &+= 1
    await cancelAndSettleBoundaryMotionBeforePreflightErasure()
    invalidateVoiceUpdates()
    lastBoundaryStopUtteranceID = nil
    if voiceListening && !explorationIsActive {
      await voiceActions?.stopListening()
      voiceListening = false
      lastVoiceActionableResultText =
        "voice listening stopped because preflight authority changed"
    }
    selectedPreflightSequenceID = .penUpConfirmation
    preflightTransactions = [:]
    preflightError = nil
    drawingFramePosterior = nil
    pendingPreflightInspection = nil
    pendingPreflightCaptureBoundaryNanoseconds = nil
  }

  private func cancelAndSettleBoundaryMotionBeforePreflightErasure() async {
    guard boundaryTeachingState != .idle || boundaryMotionTask != nil
      || boundaryCancelTask != nil
    else { return }

    if let sequenceID = activePreflightSequenceID,
      var transaction = preflightTransactions[sequenceID]
    {
      transaction.cancel()
      preflightTransactions[sequenceID] = transaction
    }

    if case .awaitingReady(let direction) = boundaryTeachingState,
      boundaryMotionTask != nil
    {
      while boundaryMotionTask != nil,
        boundaryTeachingState == .awaitingReady(direction)
      {
        if let snapshot = await machineActions?.snapshot(),
          snapshot.machine.connection == .moving
        {
          machineSnapshot = snapshot
          boundaryTeachingState = .moving(direction)
          break
        }
        await Task.yield()
      }
    }

    await cancelBoundaryTeaching()
    let cancelTask = boundaryCancelTask
    await cancelTask?.value
    let motionTask = boundaryMotionTask
    await motionTask?.value
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
    await clearPreflightAuthority()
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
