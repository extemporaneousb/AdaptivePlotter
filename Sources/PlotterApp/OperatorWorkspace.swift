import Foundation
import Observation
import PlotterModel
import PlotterRuntime

enum CanvasLayer: String, CaseIterable, Identifiable {
  case logical = "Logical"
  case predicted = "Predicted"
  case observed = "Observed"
  case residuals = "Residuals"
  case cap = "Cap"
  case frameSides = "Frame"

  var id: Self { self }

  var operationName: String {
    switch self {
    case .logical: "logical"
    case .predicted: "predicted"
    case .observed: "simulated-observed"
    case .residuals: "residual"
    case .cap: "cap"
    case .frameSides: "frame-side"
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

enum JogDirection: Sendable {
  case xNegative
  case xPositive
  case yNegative
  case yPositive
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
    let requestPenActuation: @Sendable (PenCommand) async -> PenOutcome
    let disconnect: @Sendable () async -> Void
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

  private(set) var serialDevices: [MachineLinkDescriptor] = []
  private(set) var selectedSerialDevice: MachineLinkDescriptor?
  private(set) var passiveProbeResult: PassiveProbeResult?
  private(set) var machineSnapshot: RunInterpreterSnapshot?
  private(set) var machineError: String?
  private(set) var passiveProbeInProgress = false
  private(set) var jogRequestInProgress = false
  private(set) var penRequestInProgress = false
  private(set) var limitsUpdateInProgress = false
  private(set) var limitsApplied = false

  private(set) var cameraSnapshot: CameraCaptureSnapshot?
  private(set) var displayedFrame: DisplayedFrame?
  private(set) var cameraOverlays: [CameraOverlayMeasurement] = []
  private(set) var cameraError: String?
  private(set) var sceneInspectionInProgress = false
  private(set) var analysisFrameHeld = false
  private(set) var lastSceneMeasurement: PlotterSceneMeasurement?
  private(set) var lastCameraSnapshotPath: String?
  private(set) var simulatorEvidenceLabel = SimulatedOverlaySceneContent.evidenceLabel
  private(set) var simulatorPenState: PenState = .unknown
  private(set) var simulatorLearningSummary = "Switch to SIMULATED to inspect model behavior."

  @ObservationIgnored private let machineActions: MachineActions?
  @ObservationIgnored private let cameraActions: CameraActions?
  @ObservationIgnored private let serialDeviceDiscovery: @Sendable () -> [MachineLinkDescriptor]
  @ObservationIgnored private let nowNanoseconds: @Sendable () -> UInt64
  @ObservationIgnored private var frameTask: Task<Void, Never>?
  @ObservationIgnored private var hasShutdown = false
  @ObservationIgnored private var lifetimeGeneration: UInt64 = 0
  @ObservationIgnored private var activeHardwareIntentCount = 0
  @ObservationIgnored private var intentDrainWaiters: [CheckedContinuation<Void, Never>] = []

  init(
    machineActions: MachineActions? = nil,
    cameraActions: CameraActions? = nil,
    serialDevices: [MachineLinkDescriptor] = [],
    serialDeviceDiscovery: @escaping @Sendable () -> [MachineLinkDescriptor] = {
      SerialPortDiscovery.discover()
    },
    nowNanoseconds: @escaping @Sendable () -> UInt64 = {
      UInt64(ProcessInfo.processInfo.systemUptime * 1_000_000_000)
    }
  ) {
    self.machineActions = machineActions
    self.cameraActions = cameraActions
    self.serialDevices = serialDevices
    self.serialDeviceDiscovery = serialDeviceDiscovery
    self.nowNanoseconds = nowNanoseconds
  }

  var actionSurfacePresentation: ActionSurfacePresentation {
    let visibleOperations = Set(visibleLayers.map(\.operationName))
    return ActionSurfacePresentation(
      displayedFrame: displayedFrame,
      overlays: cameraOverlays.filter {
        visibleOperations.contains($0.provenance.operation)
          || !CanvasLayer.allCases.map(\.operationName).contains($0.provenance.operation)
      }
    )
  }

  var cameraDevices: [CameraDevice] { cameraSnapshot?.devices ?? [] }
  var selectedCameraID: CameraDeviceID? { cameraSnapshot?.selectedDeviceID }
  var isShutdown: Bool { hasShutdown }

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
    return "\(cap) · \(top) · \(right)"
  }

  var currentOperationText: String {
    guard let operation = machineSnapshot?.currentOperation else { return "none" }
    return switch operation {
    case .idle: "idle"
    case .passiveProbe: "passive probe"
    case .relativeJog: "relative jog"
    case .penActuation(let command): "pen \(command.rawValue)"
    }
  }

  var controllerStateText: String {
    machineSnapshot?.machine.controllerState?.rawValue ?? "unknown"
  }

  var machinePositionText: String {
    guard let point = machineSnapshot?.machine.position?.point else { return "unknown" }
    return String(format: "X %.3f   Y %.3f", point.x, point.y)
  }

  var penStateText: String {
    machineSnapshot?.machine.penState.rawValue ?? PenState.unknown.rawValue
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
    if passiveProbeInProgress { return "A passive probe is already in progress." }
    if machineActions == nil { return "Native machine composition is unavailable." }
    if selectedSerialDevice == nil { return "Select one serial device first." }
    return nil
  }

  /// Presentation availability only. MachineController repeats every physical
  /// safety check when it receives the typed request.
  var motionUnavailableReason: String? {
    if jogRequestInProgress { return "A relative jog is already in progress." }
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
      clearMachineAuthority()
    }
    guard canCommit(generation) else { return }
    serialDevices = discovered
  }

  func disconnectMachineSession() async {
    guard let generation = beginHardwareIntent() else { return }
    defer { endHardwareIntent() }
    guard selectedSerialDevice != nil, !passiveProbeInProgress, !jogRequestInProgress,
      !penRequestInProgress
    else { return }
    await machineActions?.disconnect()
    guard canCommit(generation) else { return }
    clearMachineAuthority()
  }

  func selectSerialDevice(_ descriptor: MachineLinkDescriptor) async {
    guard let generation = beginHardwareIntent() else { return }
    defer { endHardwareIntent() }
    guard !passiveProbeInProgress && !jogRequestInProgress && !penRequestInProgress else { return }
    guard serialDevices.contains(where: { $0.identifier == descriptor.identifier }) else { return }
    guard let machineActions else {
      machineError = "Native machine composition is unavailable."
      return
    }
    machineError = nil
    do {
      let snapshot = try await machineActions.select(descriptor)
      guard canCommit(generation) else { return }
      machineSnapshot = snapshot
      selectedSerialDevice = descriptor
      passiveProbeResult = nil
      limitsApplied = false
    } catch {
      guard canCommit(generation) else { return }
      machineError = actionableDescription(error)
    }
  }

  func requestPassiveProbe() async {
    guard let generation = beginHardwareIntent() else { return }
    defer { endHardwareIntent() }
    guard passiveProbeUnavailableReason == nil, let machineActions else { return }
    passiveProbeInProgress = true
    machineError = nil
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
    guard let generation = beginHardwareIntent() else { return }
    defer { endHardwareIntent() }
    guard motionUnavailableReason == nil, !jogRequestInProgress, let machineActions,
      let xStep = inputNumber(xStepText),
      let yStep = inputNumber(yStepText),
      let feed = inputNumber(feedText),
      xStep > 0,
      yStep > 0
    else { return }

    jogRequestInProgress = true
    machineError = nil
    defer { jogRequestInProgress = false }
    do {
      let delta: Vector2<MachineSpace>
      switch direction {
      case .xNegative: delta = try Vector2(dx: -xStep, dy: 0)
      case .xPositive: delta = try Vector2(dx: xStep, dy: 0)
      case .yNegative: delta = try Vector2(dx: 0, dy: -yStep)
      case .yPositive: delta = try Vector2(dx: 0, dy: yStep)
      }
      let request = RelativeJogRequest(delta: delta, feedMMPerMinute: feed)
      let operation = Task { await machineActions.requestRelativeJog(request) }
      await Task.yield()
      let interimSnapshot = await machineActions.snapshot()
      if canCommit(generation) { machineSnapshot = interimSnapshot }
      _ = await operation.value
      let finalSnapshot = await machineActions.snapshot()
      guard canCommit(generation) else { return }
      machineSnapshot = finalSnapshot
    } catch {
      let finalSnapshot = await machineActions.snapshot()
      guard canCommit(generation) else { return }
      machineError = actionableDescription(error)
      machineSnapshot = finalSnapshot
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
    guard let cameraActions else { return }
    cameraError = nil
    do {
      let snapshot = try await cameraActions.select(id)
      guard canCommit(generation) else { return }
      cameraSnapshot = snapshot
      displayedFrame = nil
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
    updateCameraError()
    beginFrameUpdates(generation: generation)
  }

  func stopCamera() async {
    guard let generation = beginHardwareIntent() else { return }
    defer { endHardwareIntent() }
    frameTask?.cancel()
    frameTask = nil
    guard let cameraActions else { return }
    let snapshot = await cameraActions.stop()
    guard canCommit(generation) else { return }
    cameraSnapshot = snapshot
    updateCameraError()
  }

  func restartCamera() async {
    guard let generation = beginHardwareIntent() else { return }
    defer { endHardwareIntent() }
    frameTask?.cancel()
    frameTask = nil
    guard let cameraActions else { return }
    let snapshot = await cameraActions.restart()
    guard canCommit(generation) else { return }
    frameMode = .live
    cameraSnapshot = snapshot
    displayedFrame = cameraSnapshot?.latestFrame
    cameraOverlays = []
    analysisFrameHeld = false
    lastSceneMeasurement = nil
    updateCameraError()
    beginFrameUpdates(generation: generation)
  }

  func inspectLatestScene() async {
    guard let generation = beginHardwareIntent() else { return }
    defer { endHardwareIntent() }
    guard frameMode == .live, !sceneInspectionInProgress, let cameraActions else { return }
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
    guard let cameraActions else { return }
    frameTask?.cancel()
    frameTask = nil
    cameraOverlays = []
    cameraError = nil
    switch mode {
    case .live:
      let snapshot = await cameraActions.start()
      guard canCommit(generation) else { return }
      frameMode = .live
      cameraSnapshot = snapshot
      displayedFrame = cameraSnapshot?.latestFrame
      updateCameraError()
      beginFrameUpdates(generation: generation)
    case .simulated:
      let snapshot = await cameraActions.stop()
      guard canCommit(generation) else { return }
      cameraSnapshot = snapshot
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
  }

  func shutdown() async {
    guard !hasShutdown else { return }
    hasShutdown = true
    lifetimeGeneration &+= 1
    stopObserving()
    await waitForHardwareIntentsToDrain()
    _ = await cameraActions?.stop()
    await machineActions?.disconnect()
    clearCameraAuthority()
    clearMachineAuthority()
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
    guard !hasShutdown, frameMode == .live, !analysisFrameHeld else { return }
    if let generation, !canCommit(generation) { return }
    guard case .live = frame.source else { return }
    displayedFrame = frame
  }

  private func updateCameraError() {
    cameraError = cameraSnapshot?.error?.actionableDescription
  }

  private func clearMachineAuthority() {
    selectedSerialDevice = nil
    passiveProbeResult = nil
    machineSnapshot = nil
    machineError = nil
    passiveProbeInProgress = false
    jogRequestInProgress = false
    penRequestInProgress = false
    limitsUpdateInProgress = false
    limitsApplied = false
    minimumXText = "-100"
    maximumXText = "100"
    minimumYText = "-40"
    maximumYText = "40"
    maximumDistanceText = MotionPriors.maximumDistanceMM
    maximumFeedText = MotionPriors.maximumFeedMMPerMinute
  }

  private func clearCameraAuthority() {
    frameMode = .live
    cameraSnapshot = nil
    displayedFrame = nil
    cameraOverlays = []
    cameraError = nil
    analysisFrameHeld = false
    lastSceneMeasurement = nil
    lastCameraSnapshotPath = nil
    simulatorPenState = .unknown
    simulatorLearningSummary = "Switch to SIMULATED to inspect model behavior."
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
