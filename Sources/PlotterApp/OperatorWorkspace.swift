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
    let requestRelativeJog: @Sendable (RelativeJogRequest) async -> MotionOutcome
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

  struct CameraActions: Sendable {
    let discover: @Sendable () async -> CameraCaptureSnapshot
    let select: @Sendable (CameraDeviceID) async throws -> CameraCaptureSnapshot
    let start: @Sendable () async -> CameraCaptureSnapshot
    let stop: @Sendable () async -> CameraCaptureSnapshot
    let restart: @Sendable () async -> CameraCaptureSnapshot
    let snapshot: @Sendable () async -> CameraCaptureSnapshot
    let frames: @Sendable () async -> AsyncStream<DisplayedFrame>
    let inspectScene: @Sendable (UInt64) async throws -> LiveSceneInspection?
    let captureSnapshot: @Sendable () async throws -> String
    let setAutomaticInspection: @Sendable (VisionAnalysisCadence?) async
      -> PlotterSceneAnalysisSnapshot
    let analysisUpdates: @Sendable () async -> AsyncStream<PlotterSceneAnalysisSnapshot>
    let observeVisibleTool: @Sendable (PhysicalObservationPhase, UInt64) async
      -> Result<VisibleToolFrameObservation, PhysicalJogObservationFailure>
    let simulatedContent: @Sendable (SimulatorModelMode) async throws
      -> SimulatedActionSurfaceContent
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

  @ObservationIgnored private let machineActions: MachineActions?
  @ObservationIgnored private let cameraActions: CameraActions?
  @ObservationIgnored private let voiceActions: VoiceActions?
  @ObservationIgnored private let serialDeviceDiscovery: @Sendable () -> [MachineLinkDescriptor]
  @ObservationIgnored private let persistSelectedSerialIdentifier: @Sendable (String) -> Void
  @ObservationIgnored private let nowNanoseconds: @Sendable () -> UInt64
  @ObservationIgnored private var frameTask: Task<Void, Never>?
  @ObservationIgnored private var visionUpdateTask: Task<Void, Never>?
  @ObservationIgnored private var voiceTranscriptTask: Task<Void, Never>?
  @ObservationIgnored private var voiceStateTask: Task<Void, Never>?
  @ObservationIgnored private var boundaryMotionTask: Task<Void, Never>?
  @ObservationIgnored private var boundaryCancelTask: Task<Void, Never>?
  @ObservationIgnored private var lastBoundaryStopUtteranceID: UUID?
  @ObservationIgnored private var pendingPreflightInspection: LiveSceneInspection?
  @ObservationIgnored private var pendingPreflightCaptureBoundaryNanoseconds: UInt64?
  @ObservationIgnored private var preflightAuthorityGeneration: UInt64 = 0
  @ObservationIgnored private var preflightVoiceStartupGeneration: UInt64?
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

  var voiceListeningUnavailableReason: String? {
    if hasShutdown { return "The operator workspace has shut down." }
    if voiceActions == nil { return "Native voice composition is unavailable." }
    if preflightVoiceStartupGeneration != nil {
      return "A Motion Preflight microphone request is still settling."
    }
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
    if activePreflightSequenceID != nil || preflightVoiceStartupGeneration != nil {
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
    "Connect"
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

  var drawingFramePosteriorText: String {
    guard let posterior = drawingFramePosterior else { return "no boundary posterior yet" }
    return String(
      format: "%d exact-frame observations · confidence %.2f",
      posterior.observationCount,
      posterior.estimate.confidence
    )
  }

  func preflightStartUnavailableReason(for sequenceID: PreflightSequenceID) -> String? {
    if let activePreflightSequenceID {
      return "Finish or cancel \(PreflightSequenceCatalog.definition(for: activePreflightSequenceID).title)."
    }
    if preflightVoiceStartupGeneration != nil {
      return "Wait for the previous Motion Preflight microphone request to settle."
    }
    if !motionGuardIsActive { return "Connect the plotter and activate Motion Guard first." }
    if voiceActions == nil { return "Native voice composition is unavailable." }
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
    if !motionGuardIsActive { return "Plotter connected. Activate Motion to enable calibration." }
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

  /// Updates only the operator's pending device choice. A picker change is not
  /// a successful connection and cannot turn the status indicator green.
  func selectSerialDevice(_ descriptor: MachineLinkDescriptor) async {
    guard let generation = beginHardwareIntent() else { return }
    defer { endHardwareIntent() }
    guard activePreflightSequenceID == nil else { return }
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
        if voiceListening { await stopVoiceListening() }
        let authorityGeneration = preflightAuthorityGeneration
        let started = await startPreflightVoiceListening(
          for: sequenceID,
          authorityGeneration: authorityGeneration
        )
        guard preflightAuthorityIsCurrent(
          sequenceID: sequenceID,
          generation: authorityGeneration
        ) else { return }
        guard started else {
          await failPreflight(sequenceID, reason: voiceError ?? voicePermissionText)
          return
        }
        guard recordPreflight(.speechListeningStarted, for: sequenceID) else { return }

      case .stopSpeechListening:
        await stopVoiceListening()
        guard recordPreflight(.speechListeningStopped, for: sequenceID) else { return }

      case .speakPrompt(let prompt):
        lastVoiceActionableResultText = prompt
        let spoken = "Motion Preflight is ready. Follow the displayed instruction."
        await voiceActions?.speak(spoken)
        lastSpokenFeedbackText = spoken
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
        cameraConfigurationID: measurement.cameraConfigurationID,
        direction: direction,
        controllerPosition: controllerPosition,
        observedToolCentroid: observedToolCentroid,
        estimate: estimate,
        confidence: max(0.01, estimate.confidence)
      )
      drawingFramePosterior = try drawingFramePosterior?.adding(observation)
        ?? DrawingFramePosterior(prior: observation)
      guard let drawingFramePosterior else { return false }
      let posteriorOverlay = CameraOverlayMeasurement(
        frameID: measurement.frameID,
        cameraConfigurationID: measurement.cameraConfigurationID,
        geometry: .polyline(drawingFramePosterior.estimate.geometry),
        provenance: CameraMeasurementProvenance(
          kind: .drawingFrameEstimate,
          source: .inferred,
          algorithmRevision: "motion-preflight-posterior-v1"
        )
      )
      cameraOverlays.removeAll { $0.provenance.kind == .drawingFrameEstimate }
      cameraOverlays.append(posteriorOverlay)
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
    await stopVoiceListening()
  }

  private func finishCancelledPreflight(_ sequenceID: PreflightSequenceID) async {
    await stopVoiceListening()
    if preflightTransactions[sequenceID]?.currentStep?.action == .stopSpeechListening {
      _ = recordPreflight(.speechListeningStopped, for: sequenceID)
    }
    pendingPreflightInspection = nil
    pendingPreflightCaptureBoundaryNanoseconds = nil
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
    guard let cameraActions else { return }
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
    invalidateVoiceUpdates()
    lastBoundaryStopUtteranceID = nil
    lastPreflightRehearsalUtteranceID = nil
    await voiceActions?.stopListening()
    await voiceActions?.stopSpeaking()
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
    await voiceActions?.speak(commandFreeSpoken)
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

  private func clearPreflightAuthority() async {
    preflightAuthorityGeneration &+= 1
    await cancelAndSettleBoundaryMotionBeforePreflightErasure()
    invalidateVoiceUpdates()
    lastBoundaryStopUtteranceID = nil
    if voiceListening {
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

  private func startPreflightVoiceListening(
    for sequenceID: PreflightSequenceID,
    authorityGeneration: UInt64
  ) async -> Bool {
    guard preflightAuthorityIsCurrent(
      sequenceID: sequenceID,
      generation: authorityGeneration
    ), preflightVoiceStartupGeneration == nil,
      voiceListeningUnavailableReason == nil,
      let voiceActions
    else { return false }

    preflightVoiceStartupGeneration = authorityGeneration
    defer {
      if preflightVoiceStartupGeneration == authorityGeneration {
        preflightVoiceStartupGeneration = nil
      }
    }

    voiceError = nil
    let authorization = await voiceActions.requestAuthorization()
    guard preflightAuthorityIsCurrent(
      sequenceID: sequenceID,
      generation: authorityGeneration
    ) else { return false }
    voiceAuthorizationState = authorization
    guard authorization == .authorized else {
      lastVoiceActionableResultText = voicePermissionText
      return false
    }

    do {
      try await voiceActions.startListening()
      guard preflightAuthorityIsCurrent(
        sequenceID: sequenceID,
        generation: authorityGeneration
      ) else {
        await voiceActions.stopListening()
        return false
      }
      voiceListening = true
      lastVoiceActionableResultText =
        "speech listening active for the current Motion Preflight sequence"
      beginVoiceUpdates(actions: voiceActions)
      return true
    } catch {
      guard preflightAuthorityIsCurrent(
        sequenceID: sequenceID,
        generation: authorityGeneration
      ) else {
        await voiceActions.stopListening()
        return false
      }
      voiceListening = false
      voiceError = actionableDescription(error)
      lastVoiceActionableResultText = "Voice listening failed: \(voiceError ?? "unknown error")"
      return false
    }
  }

  private func preflightAuthorityIsCurrent(
    sequenceID: PreflightSequenceID,
    generation: UInt64
  ) -> Bool {
    !hasShutdown && preflightAuthorityGeneration == generation
      && activePreflightSequenceID == sequenceID
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
