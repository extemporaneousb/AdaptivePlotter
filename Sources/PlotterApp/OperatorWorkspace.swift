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
    static let maximumDistanceMM = "5"
    static let maximumFeedMMPerMinute = "100"
  }

  struct MachineActions: Sendable {
    let select: @Sendable (MachineLinkDescriptor) async throws -> RunInterpreterSnapshot
    let snapshot: @Sendable () async -> RunInterpreterSnapshot?
    let requestPassiveProbe: @Sendable () async throws -> PassiveProbeResult
    let updateMotionLimits: @Sendable (MotionLimits) async -> Void
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
    let inspectScene: @Sendable () async throws -> LiveSceneInspection?
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
  var minimumXText = "-100"
  var maximumXText = "100"
  var minimumYText = "-40"
  var maximumYText = "40"
  var maximumDistanceText = MotionPriors.maximumDistanceMM
  var maximumFeedText = MotionPriors.maximumFeedMMPerMinute
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
  private(set) var limitsUpdateInProgress = false
  private(set) var limitsApplied = false
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
    }
  ) {
    self.machineActions = machineActions
    self.cameraActions = cameraActions
    self.voiceActions = voiceActions
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

  var boundaryTeachingUnavailableReason: String? {
    if boundaryTeachingState != .idle { return "Finish or cancel the current boundary interaction." }
    if !voiceListening { return "Turn Speech On in the Camera panel first." }
    return motionUnavailableReason
  }

  func boundaryPositionText(for direction: JogDirection) -> String {
    guard let position = boundaryPositions[direction] else { return "not measured" }
    return String(format: "X %.3f Y %.3f", position.point.x, position.point.y)
  }

  var workbenchStatusText: String {
    if let actionableError { return actionableError }
    if let reason = motionUnavailableReason { return "Movement test setup: \(reason)" }
    return "Motion request eligible; motor power is not reported by controller."
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
    if !limitsApplied || machine.motionLimits == nil {
      return MotionRefusal.motionLimitsMissing.actionableDescription
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

  var limitsUnavailableReason: String? {
    if limitsUpdateInProgress { return "Motion limits are being applied." }
    guard machineActions != nil, selectedSerialDevice != nil else {
      return "Select and connect one serial device first."
    }
    guard [
      minimumXText, maximumXText, minimumYText, maximumYText,
      maximumDistanceText, maximumFeedText,
    ].allSatisfy({ inputNumber($0) != nil })
    else { return "Enter all six numeric limit values." }
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
    guard let position = machine.position else {
      return PenRefusal.machinePositionUnknown.actionableDescription
    }
    guard let limits = machine.motionLimits, limitsApplied else {
      return PenRefusal.motionLimitsMissing.actionableDescription
    }
    if !limits.bounds.contains(position.point) {
      return PenRefusal.machinePositionOutsideBounds(position).actionableDescription
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
      clearMachineAuthority(clearSelection: true)
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
    clearMachineAuthority(clearSelection: false)
  }

  /// Updates only the operator's pending device choice. A picker change is not
  /// a successful connection and cannot turn the status indicator green.
  func selectSerialDevice(_ descriptor: MachineLinkDescriptor) async {
    guard let generation = beginHardwareIntent() else { return }
    defer { endHardwareIntent() }
    guard !passiveProbeInProgress && !jogRequestInProgress && !penRequestInProgress else { return }
    guard serialDevices.contains(where: { $0.identifier == descriptor.identifier }) else { return }
    if selectedSerialDevice?.identifier != descriptor.identifier, machineSnapshot != nil {
      await machineActions?.disconnect()
      guard canCommit(generation) else { return }
      clearMachineAuthority(clearSelection: false)
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
      limitsApplied = false
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
        "speech on; no words are actionable until a boundary side is armed"
      beginVoiceTranscriptUpdates(actions: voiceActions)
      beginVoiceStateUpdates(actions: voiceActions)
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
    voiceTranscriptTask?.cancel()
    voiceTranscriptTask = nil
    voiceStateTask?.cancel()
    voiceStateTask = nil
    lastBoundaryStopUtteranceID = nil
    await voiceActions.stopListening()
    voiceListening = false
    lastVoiceActionableResultText = "voice listening stopped"
  }

  func beginBoundaryTeaching(_ direction: JogDirection) async {
    guard boundaryTeachingUnavailableReason == nil, let voiceActions else { return }
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

  func applyMotionLimits() async {
    guard let generation = beginHardwareIntent() else { return }
    defer { endHardwareIntent() }
    guard limitsUnavailableReason == nil, let machineActions,
      let minimumX = inputNumber(minimumXText),
      let maximumX = inputNumber(maximumXText),
      let minimumY = inputNumber(minimumYText),
      let maximumY = inputNumber(maximumYText),
      let maximumDistance = inputNumber(maximumDistanceText),
      let maximumFeed = inputNumber(maximumFeedText)
    else { return }
    limitsUpdateInProgress = true
    machineError = nil
    defer { limitsUpdateInProgress = false }
    do {
      let limits = try MotionLimits(
        bounds: AxisAlignedBounds<MachineSpace>(
          minX: minimumX,
          minY: minimumY,
          maxX: maximumX,
          maxY: maximumY
        ),
        maximumDistanceMM: maximumDistance,
        maximumFeedMMPerMinute: maximumFeed
      )
      await machineActions.updateMotionLimits(limits)
      let snapshot = await machineActions.snapshot()
      guard canCommit(generation) else { return }
      machineSnapshot = snapshot
      limitsApplied = true
    } catch {
      guard canCommit(generation) else { return }
      limitsApplied = false
      machineError = actionableDescription(error)
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
      guard let inspection = try await cameraActions.inspectScene() else {
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
        displayedFrame = content.displayedFrame
        cameraOverlays = content.overlays
        simulatorEvidenceLabel = content.evidenceLabel
        simulatorPenState = content.commandedPenState
        simulatorLearningSummary = content.learningSummary
      } catch {
        guard canCommit(generation) else { return }
        displayedFrame = nil
        cameraError = actionableDescription(error)
      }
    }
  }

  func selectSimulatorModelMode(_ mode: SimulatorModelMode) async {
    guard !hasShutdown else { return }
    simulatorModelMode = mode
    guard frameMode == .simulated else { return }
    frameMode = .live
    await switchFrameMode(.simulated)
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
    voiceTranscriptTask?.cancel()
    voiceTranscriptTask = nil
    voiceStateTask?.cancel()
    voiceStateTask = nil
    lastBoundaryStopUtteranceID = nil
    await voiceActions?.stopListening()
    await voiceActions?.stopSpeaking()
    voiceListening = false
    await waitForHardwareIntentsToDrain()
    _ = await cameraActions?.stop()
    await machineActions?.disconnect()
    clearCameraAuthority()
    clearMachineAuthority(clearSelection: true)
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

  private func beginVoiceTranscriptUpdates(actions: VoiceActions) {
    voiceTranscriptTask?.cancel()
    voiceTranscriptTask = Task { [weak self] in
      let stream = await actions.transcripts()
      for await transcript in stream {
        guard !Task.isCancelled, let self else { return }
        await self.receiveVoiceTranscript(transcript)
      }
      guard !Task.isCancelled, let self, !self.hasShutdown else { return }
      let snapshot = await actions.snapshot()
      guard !Task.isCancelled, !self.hasShutdown else { return }
      self.receiveVoiceSnapshot(snapshot)
    }
  }

  private func beginVoiceStateUpdates(actions: VoiceActions) {
    voiceStateTask?.cancel()
    voiceStateTask = Task { [weak self] in
      while !Task.isCancelled {
        let snapshot = await actions.snapshot()
        guard !Task.isCancelled, let self, !self.hasShutdown else { return }
        self.receiveVoiceSnapshot(snapshot)
        guard case .listening = snapshot.listeningState else { return }
        try? await Task.sleep(nanoseconds: 250_000_000)
      }
    }
  }

  private func receiveVoiceSnapshot(_ snapshot: VoiceInteractionSnapshot) {
    voiceAuthorizationState = snapshot.authorization
    switch snapshot.listeningState {
    case .listening:
      voiceListening = true
    case .stopped, .requestingPermission:
      let lostActiveListener = voiceListening
      voiceListening = false
      if lostActiveListener {
        failClosedBoundaryAfterSpeechLoss("Speech listening stopped unexpectedly.")
      }
    case .failed(let error):
      voiceListening = false
      voiceError = error.actionableDescription
      lastVoiceActionableResultText = error.actionableDescription
      failClosedBoundaryAfterSpeechLoss(error.actionableDescription)
    }
  }

  private func failClosedBoundaryAfterSpeechLoss(_ reason: String) {
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

  private func receiveVoiceTranscript(_ transcript: VoiceTranscript) async {
    guard voiceListening, !hasShutdown else { return }
    voiceTranscriptText = transcript.text.isEmpty ? "none" : transcript.text
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
              "Moving \(direction.shortLabel) under the displayed limits. The active interaction now accepts STOP."
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
      await publishVoiceFeedback(
        result: boundaryTeachingResultText,
        spoken: "No motion outcome is available. No side position was recorded."
      )
      return
    }
    switch outcome {
    case .cancelled(let finalPosition):
      boundaryPositions[direction] = finalPosition
      boundaryTeachingResultText = String(
        format: "%@ recorded at X %.3f Y %.3f from cancelled jog final position.",
        direction.shortLabel,
        finalPosition.point.x,
        finalPosition.point.y
      )
      await publishVoiceFeedback(
        result: boundaryTeachingResultText,
        spoken: "Side position recorded from the interrupted movement."
      )
    case .acceptedThenCompleted:
      boundaryTeachingResultText =
        "The bounded jog reached its command cap. No boundary was recorded; arm the side again to continue."
      await publishVoiceFeedback(
        result: boundaryTeachingResultText,
        spoken: "The bounded movement completed. No side position was recorded."
      )
    case .refused(let refusal):
      boundaryTeachingResultText = "Motion refused: \(refusal.actionableDescription)"
      await publishVoiceFeedback(
        result: boundaryTeachingResultText,
        spoken: "Movement refused. Check the displayed reason."
      )
    case .ambiguous(let ambiguity):
      boundaryTeachingResultText = "Motion ambiguous: \(ambiguity.actionableDescription)"
      await publishVoiceFeedback(
        result: boundaryTeachingResultText,
        spoken: "Movement outcome is ambiguous. No side position was recorded."
      )
    }
  }

  private func makeBoundaryJogRequest(_ direction: JogDirection) -> RelativeJogRequest? {
    guard boundaryTeachingState == .awaitingReady(direction),
      motionUnavailableReason == nil,
      let machine = machineSnapshot?.machine,
      let position = machine.position,
      let limits = machine.motionLimits,
      let feed = inputNumber(feedText), feed > 0
    else {
      boundaryTeachingResultText =
        "Boundary motion cannot start: \(motionUnavailableReason ?? "current motion values are invalid")."
      return nil
    }
    let availableDistance: Double
    switch direction {
    case .xNegative: availableDistance = position.point.x - limits.bounds.minX
    case .xPositive: availableDistance = limits.bounds.maxX - position.point.x
    case .yNegative: availableDistance = position.point.y - limits.bounds.minY
    case .yPositive: availableDistance = limits.bounds.maxY - position.point.y
    }
    let distance = min(availableDistance, limits.maximumDistanceMM)
    guard distance.isFinite, distance > 0 else {
      boundaryTeachingResultText =
        "No positive bounded travel remains in \(direction.shortLabel); no motion was sent."
      return nil
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

  private func clearMachineAuthority(clearSelection: Bool) {
    if clearSelection { selectedSerialDevice = nil }
    passiveProbeResult = nil
    machineSnapshot = nil
    machineError = nil
    passiveProbeInProgress = false
    jogRequestInProgress = false
    penRequestInProgress = false
    jogCancelRequestInProgress = false
    limitsUpdateInProgress = false
    limitsApplied = false
    recordJogObservations = false
    selectedObservationSplit = .training
    physicalJogObservations = []
    jogResponseDataset = nil
    jogResponseCandidate = nil
    jogResponseLearnerError = nil
    boundaryTeachingState = .idle
    boundaryTeachingResultText = "Choose one side to begin."
    boundaryPositions = [:]
    minimumXText = "-100"
    maximumXText = "100"
    minimumYText = "-40"
    maximumYText = "40"
    maximumDistanceText = MotionPriors.maximumDistanceMM
    maximumFeedText = MotionPriors.maximumFeedMMPerMinute
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

  private func clearCameraAuthority() {
    frameMode = .live
    cameraSnapshot = nil
    displayedFrame = nil
    latestLiveCameraFrame = nil
    cameraOverlays = []
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
