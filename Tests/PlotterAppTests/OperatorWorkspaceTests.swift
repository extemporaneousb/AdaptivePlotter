import Foundation
import PlotterModel
import PlotterRuntime
import Testing

@testable import PlotterApp

@Test("Preview layers remain ordinary presentation state")
@MainActor
func previewLayerVisibility() {
  let workspace = OperatorWorkspace()

  #expect(workspace.frameMode == .live)
  #expect(CanvasLayer.observedInk.rawValue == "Observed ink")
  workspace.setLayer(.observedInk, visible: false)

  #expect(!workspace.visibleLayers.contains(.observedInk))
  #expect(workspace.visibleLayers.contains(.intendedPath))
}

@Test("Camera discovery preserves the live default without starting or simulating")
@MainActor
func cameraDiscoveryPreservesLiveDefault() async throws {
  let frame = try testDisplayedFrame(source: .simulated)
  let camera = CameraFixture(
    snapshot: CameraCaptureSnapshot(
      devices: [
        CameraDevice(id: CameraDeviceID(rawValue: "one"), name: "One"),
        CameraDevice(id: CameraDeviceID(rawValue: "two"), name: "Two"),
      ],
      selectedDeviceID: nil,
      state: .ready,
      latestFrame: nil,
      error: nil
    ),
    simulated: frame
  )
  let workspace = OperatorWorkspace(cameraActions: cameraActions(camera))

  await workspace.discoverCameras()

  #expect(workspace.frameMode == .live)
  #expect(workspace.selectedCameraID == nil)
  #expect(workspace.displayedFrame == nil)
  #expect(await camera.simulatorCount == 0)
}

@Test("Startup camera choice prefers and starts the C920 without choosing between unrelated cameras")
@MainActor
func startupCameraPrefersC920() async throws {
  let c920 = CameraDevice(id: CameraDeviceID(rawValue: "c920"), name: "HD Pro Webcam C920")
  let builtIn = CameraDevice(
    id: CameraDeviceID(rawValue: "built-in"),
    name: "FaceTime HD Camera"
  )
  let camera = CameraFixture(
    snapshot: CameraCaptureSnapshot(
      devices: [builtIn, c920],
      selectedDeviceID: nil,
      state: .ready,
      latestFrame: nil,
      error: nil
    ),
    simulated: try testDisplayedFrame(source: .simulated)
  )
  let workspace = OperatorWorkspace(cameraActions: cameraActions(camera))

  await workspace.startPreferredCameraAtStartup()

  #expect(workspace.selectedCameraID == c920.id)
  #expect(await camera.selectedIDs == [c920.id])
  #expect(await camera.startCount == 1)
}

@Test("automatic vision cadence is explicit and can be stopped without changing frame source")
@MainActor
func automaticVisionCadenceIsExplicit() async throws {
  let camera = CameraFixture(
    snapshot: CameraCaptureSnapshot(
      devices: [],
      selectedDeviceID: nil,
      state: .running,
      latestFrame: try testDisplayedFrame(),
      error: nil
    ),
    simulated: try testDisplayedFrame(source: .simulated)
  )
  let workspace = OperatorWorkspace(cameraActions: cameraActions(camera))

  await workspace.startCamera()
  await workspace.updateVisionAnalysisCadence(.tenFPS)
  await workspace.setAutomaticVisionAnalysis(true)
  #expect(workspace.automaticVisionEnabled)
  #expect(workspace.frameMode == .live)
  #expect(workspace.visionThroughputText.contains("target 10 Hz"))

  await workspace.setAutomaticVisionAnalysis(false)
  #expect(!workspace.automaticVisionEnabled)
  #expect(workspace.frameMode == .live)
  #expect(await camera.automaticCadences == [.tenFPS, nil])
}

@Test("Motion priors keep one millimeter axis steps and a zero-centered 2.5 to 1 window")
@MainActor
func motionPriorsStayCenteredOnSessionStartZero() async throws {
  let position = try MachinePosition(x: 28.396, y: -10.002)
  let fixture = MachineFixture(snapshot: testRunSnapshot(position: position))
  let device = testDevice()
  let workspace = OperatorWorkspace(
    machineActions: machineActions(fixture),
    serialDevices: [device]
  )

  await workspace.selectSerialDevice(device)

  #expect(workspace.xStepText == "1.0")
  #expect(workspace.yStepText == "1.0")
  #expect(workspace.feedText == "100")
  #expect(workspace.minimumXText == "-100")
  #expect(workspace.maximumXText == "100")
  #expect(workspace.minimumYText == "-40")
  #expect(workspace.maximumYText == "40")
  #expect(workspace.maximumDistanceText == "5")
  #expect(workspace.maximumFeedText == "100")
  #expect(!workspace.limitsApplied)
}

@Test("Runtime motion facts project one exact disabled reason")
@MainActor
func runtimeMotionBlockersProjectExactly() async {
  let device = testDevice()

  let cases: [(RunInterpreterSnapshot, String)] = [
    (
      testRunSnapshot(connection: .disconnected),
      MotionRefusal.notConnected.actionableDescription
    ),
    (
      testRunSnapshot(state: nil),
      MotionRefusal.controllerStateUnknown.actionableDescription
    ),
    (
      testRunSnapshot(state: .hold),
      MotionRefusal.controllerNotIdle(.hold).actionableDescription
    ),
    (
      testRunSnapshot(pins: ControllerPins(rawValue: "X")),
      MotionRefusal.relevantLimitAsserted("X").actionableDescription
    ),
    (
      testRunSnapshot(position: nil),
      MotionRefusal.machinePositionUnknown.actionableDescription
    ),
  ]

  for (snapshot, expected) in cases {
    let fixture = MachineFixture(snapshot: snapshot)
    let workspace = OperatorWorkspace(
      machineActions: machineActions(fixture),
      serialDevices: [device]
    )
    await workspace.selectSerialDevice(device)

    #expect(workspace.motionUnavailableReason == expected)
  }
}

@Test("Sticky ambiguity is the first runtime motion blocker after selection")
@MainActor
func stickyAmbiguityPrecedesConnectionBlocker() async {
  let ambiguity = MotionAmbiguity.disconnected
  let device = testDevice()
  let fixture = MachineFixture(
    snapshot: testRunSnapshot(
      connection: .disconnected,
      stickyAmbiguity: ambiguity
    )
  )
  let workspace = OperatorWorkspace(
    machineActions: machineActions(fixture),
    serialDevices: [device]
  )

  await workspace.selectSerialDevice(device)

  #expect(
    workspace.motionUnavailableReason
      == MotionRefusal.stickyAmbiguity(ambiguity).actionableDescription
  )
}

@Test("Passive probe requires explicit device selection")
@MainActor
func passiveProbeRequiresSelection() async {
  let fixture = MachineFixture()
  let workspace = OperatorWorkspace(machineActions: machineActions(fixture))

  await workspace.requestPassiveProbe()

  #expect(await fixture.probeCount == 0)
  #expect(workspace.passiveProbeResult == nil)
  #expect(workspace.passiveProbeUnavailableReason == "Select one serial device first.")
}

@Test("A passive probe can be retried without restarting the app")
@MainActor
func passiveProbeCanRetry() async throws {
  let fixture = MachineFixture()
  let device = testDevice()
  let workspace = OperatorWorkspace(
    machineActions: machineActions(fixture),
    serialDevices: [device]
  )
  await workspace.selectSerialDevice(device)

  await workspace.requestPassiveProbe()
  await workspace.requestPassiveProbe()

  #expect(await fixture.probeCount == 2)
  #expect(workspace.passiveProbeResult?.blockers.isEmpty == true)
  #expect(workspace.passiveProbeUnavailableReason == nil)
}

@Test("Jog buttons send one typed request and do not depend on camera state")
@MainActor
func typedJogDoesNotRequireCamera() async throws {
  let fixture = MachineFixture()
  let device = testDevice()
  let workspace = OperatorWorkspace(
    machineActions: machineActions(fixture),
    cameraActions: nil,
    serialDevices: [device]
  )
  await workspace.selectSerialDevice(device)
  await applyTestLimits(workspace)
  await workspace.requestPenActuation(.raise)
  workspace.xStepText = "2.5"
  workspace.yStepText = "9.25"
  workspace.feedText = "75"

  #expect(workspace.motionUnavailableReason == nil)
  await workspace.requestJog(.xNegative)

  let requests = await fixture.jogRequests
  let request = try #require(requests.only)
  #expect(request.delta.dx == -2.5)
  #expect(request.delta.dy == 0)
  #expect(request.feedMMPerMinute == 75)
  let limits = try #require(await fixture.lastLimits)
  #expect(limits.bounds.minX == -10)
  #expect(limits.bounds.maxX == 10)
  #expect(limits.bounds.minY == -20)
  #expect(limits.bounds.maxY == 20)
  #expect(workspace.cameraSnapshot == nil)
}

@Test("A corrected runtime refusal is immediately retryable")
@MainActor
func refusalCanRetry() async throws {
  let completed = MotionOutcome.acceptedThenCompleted(
    finalPosition: try MachinePosition(x: 1, y: 0)
  )
  let fixture = MachineFixture(outcomes: [
    .refused(.feedExceedsMaximum(requested: 90, maximum: 80)),
    completed,
  ])
  let device = testDevice()
  let workspace = OperatorWorkspace(
    machineActions: machineActions(fixture),
    serialDevices: [device]
  )
  await workspace.selectSerialDevice(device)
  await applyTestLimits(workspace)
  await workspace.requestPenActuation(.raise)

  await workspace.requestJog(.xPositive)
  #expect(workspace.lastMotionOutcomeText.contains("refused"))
  #expect(workspace.motionUnavailableReason == nil)

  await workspace.requestJog(.xPositive)

  #expect(await fixture.jogRequests.count == 2)
  #expect(workspace.lastMotionOutcomeText.contains("completed at X 1.000 Y 0.000"))
}

@Test("Pen buttons issue typed controller commands and never manufacture an up state")
@MainActor
func typedPenControls() async throws {
  let fixture = MachineFixture()
  let device = testDevice()
  let workspace = OperatorWorkspace(
    machineActions: machineActions(fixture),
    serialDevices: [device]
  )
  await workspace.selectSerialDevice(device)

  #expect(workspace.penUnavailableReason(for: .raise) == nil)
  #expect(
    workspace.penUnavailableReason(for: .lower)
      == PenRefusal.motionLimitsMissing.actionableDescription
  )

  await workspace.requestPenActuation(.raise)
  #expect(await fixture.penRequests == [.raise])
  #expect(workspace.penStateText == "up")
  #expect(workspace.lastPenOutcomeText.contains("acknowledged"))

  await applyTestLimits(workspace)
  #expect(workspace.penUnavailableReason(for: .lower) == nil)
  await workspace.requestPenActuation(.lower)
  #expect(await fixture.penRequests == [.raise, .lower])
  #expect(workspace.penStateText == "down")
}

@Test("X and Y jog values remain independent")
@MainActor
func independentJogValues() async throws {
  let fixture = MachineFixture()
  let device = testDevice()
  let workspace = OperatorWorkspace(
    machineActions: machineActions(fixture),
    serialDevices: [device]
  )
  await workspace.selectSerialDevice(device)
  await applyTestLimits(workspace)
  await workspace.requestPenActuation(.raise)
  workspace.xStepText = "1.25"
  workspace.yStepText = "3.75"
  workspace.feedText = "60"

  await workspace.requestJog(.yPositive)

  let request = try #require(await fixture.jogRequests.only)
  #expect(request.delta.dx == 0)
  #expect(request.delta.dy == 3.75)
}

@Test("Zero and negative step magnitudes disable motion without issuing a request")
@MainActor
func nonPositiveStepMagnitudesAreDisabled() async {
  let device = testDevice()
  let cases: [(x: String, y: String, direction: JogDirection)] = [
    ("0", "1", .xPositive),
    ("-1", "1", .xNegative),
    ("1", "0", .yPositive),
    ("1", "-1", .yNegative),
  ]

  for input in cases {
    let fixture = MachineFixture()
    let workspace = OperatorWorkspace(
      machineActions: machineActions(fixture),
      serialDevices: [device]
    )
    await workspace.selectSerialDevice(device)
    await applyTestLimits(workspace)
    await workspace.requestPenActuation(.raise)
    workspace.xStepText = input.x
    workspace.yStepText = input.y

    #expect(
      workspace.motionUnavailableReason
        == "X and Y step magnitudes must be greater than zero."
    )
    await workspace.requestJog(input.direction)
    #expect(await fixture.jogRequests.isEmpty)
  }
}

@Test("Serial refresh disconnects before clearing a disappeared selection")
@MainActor
func serialRefreshDisconnectsDisappearedSelection() async {
  let fixture = MachineFixture()
  let device = testDevice()
  let workspace = OperatorWorkspace(
    machineActions: machineActions(fixture),
    serialDevices: [device],
    serialDeviceDiscovery: { [] }
  )
  await workspace.selectSerialDevice(device)
  await workspace.requestPassiveProbe()
  await applyTestLimits(workspace)
  await workspace.requestPenActuation(.raise)

  await workspace.refreshSerialDevices()

  #expect(await fixture.disconnectCount == 1)
  #expect(workspace.serialDevices.isEmpty)
  #expect(workspace.selectedSerialDevice == nil)
  #expect(workspace.machineSnapshot == nil)
  #expect(workspace.passiveProbeResult == nil)
  #expect(!workspace.limitsApplied)
  #expect(workspace.penStateText == PenState.unknown.rawValue)
}

@Test("Disconnect and same-path reselect require fresh facts, limits, and a new pen raise")
@MainActor
func disconnectAndReselectRequireFreshAuthority() async {
  let fixture = MachineFixture()
  let device = testDevice()
  let workspace = OperatorWorkspace(
    machineActions: machineActions(fixture),
    serialDevices: [device]
  )
  await workspace.selectSerialDevice(device)
  await applyTestLimits(workspace)
  await workspace.requestPenActuation(.raise)
  #expect(workspace.motionUnavailableReason == nil)

  await workspace.disconnectMachineSession()

  #expect(await fixture.disconnectCount == 1)
  #expect(workspace.selectedSerialDevice == nil)
  #expect(workspace.machineSnapshot == nil)
  #expect(workspace.passiveProbeResult == nil)
  #expect(!workspace.limitsApplied)
  #expect(workspace.penStateText == PenState.unknown.rawValue)
  #expect(workspace.minimumXText == "-100")

  await workspace.selectSerialDevice(device)
  #expect(workspace.selectedSerialDevice?.identifier == device.identifier)
  #expect(workspace.passiveProbeResult == nil)
  #expect(!workspace.limitsApplied)
  #expect(workspace.penStateText == PenState.unknown.rawValue)
  #expect(workspace.motionUnavailableReason == MotionRefusal.notConnected.actionableDescription)
  await workspace.requestJog(.xPositive)
  #expect(await fixture.jogRequests.isEmpty)

  await workspace.requestPassiveProbe()
  #expect(
    workspace.motionUnavailableReason
      == MotionRefusal.motionLimitsMissing.actionableDescription
  )

  await applyTestLimits(workspace)
  #expect(
    workspace.motionUnavailableReason
      == MotionRefusal.penNotUp(.unknown).actionableDescription
  )

  await workspace.requestPenActuation(.raise)
  #expect(workspace.motionUnavailableReason == nil)
}

@Test("Shutdown stops camera and controller once and clears visible authority")
@MainActor
func shutdownTearsDownExactlyOnce() async throws {
  let displayed = try testDisplayedFrame()
  let camera = CameraFixture(
    snapshot: CameraCaptureSnapshot(
      devices: [CameraDevice(id: CameraDeviceID(rawValue: "camera"), name: "Camera")],
      selectedDeviceID: CameraDeviceID(rawValue: "camera"),
      state: .running,
      latestFrame: displayed,
      error: nil
    ),
    simulated: displayed
  )
  let machine = MachineFixture()
  let device = testDevice()
  let workspace = OperatorWorkspace(
    machineActions: machineActions(machine),
    cameraActions: cameraActions(camera),
    serialDevices: [device]
  )
  await workspace.selectSerialDevice(device)
  await workspace.requestPassiveProbe()
  await applyTestLimits(workspace)
  await workspace.requestPenActuation(.raise)
  await workspace.startCamera()

  await workspace.shutdown()
  await workspace.shutdown()

  #expect(await camera.stopCount == 1)
  #expect(await machine.disconnectCount == 1)
  #expect(workspace.selectedSerialDevice == nil)
  #expect(workspace.machineSnapshot == nil)
  #expect(workspace.passiveProbeResult == nil)
  #expect(!workspace.limitsApplied)
  #expect(workspace.penStateText == PenState.unknown.rawValue)
  #expect(workspace.cameraSnapshot == nil)
  #expect(workspace.displayedFrame == nil)
  #expect(workspace.cameraOverlays.isEmpty)
  #expect(workspace.frameMode == .live)
}

@Test("Shutdown drains delayed camera start and serial selection before final teardown")
@MainActor
func shutdownWinsDelayedStartAndSelection() async throws {
  let displayed = try testDisplayedFrame()
  let camera = CameraFixture(
    snapshot: CameraCaptureSnapshot(
      devices: [CameraDevice(id: CameraDeviceID(rawValue: "camera"), name: "Camera")],
      selectedDeviceID: CameraDeviceID(rawValue: "camera"),
      state: .running,
      latestFrame: displayed,
      error: nil
    ),
    simulated: displayed
  )
  let machine = MachineFixture()
  let startGate = AsyncGate()
  let selectGate = AsyncGate()
  let device = testDevice()
  let workspace = OperatorWorkspace(
    machineActions: machineActions(machine, selectGate: selectGate),
    cameraActions: cameraActions(camera, startGate: startGate),
    serialDevices: [device]
  )

  let selectTask = Task { await workspace.selectSerialDevice(device) }
  let startTask = Task { await workspace.startCamera() }
  while true {
    let selectWaiters = await selectGate.waiterCount
    let startWaiters = await startGate.waiterCount
    if selectWaiters > 0, startWaiters > 0 { break }
    await Task.yield()
  }
  let shutdownTask = Task { await workspace.shutdown() }
  while !workspace.isShutdown { await Task.yield() }
  await selectGate.open()
  await startGate.open()

  await selectTask.value
  await startTask.value
  await shutdownTask.value

  #expect(await machine.selectCount == 1)
  #expect(await machine.disconnectCount == 1)
  #expect(await camera.startCount == 1)
  #expect(await camera.stopCount == 1)
  #expect(await camera.framesCount == 0)
  #expect(workspace.selectedSerialDevice == nil)
  #expect(workspace.machineSnapshot == nil)
  #expect(workspace.cameraSnapshot == nil)
  #expect(workspace.displayedFrame == nil)

  await workspace.startCamera()
  await workspace.selectSerialDevice(device)
  #expect(await camera.startCount == 1)
  #expect(await machine.selectCount == 1)
}

@Test("Shutdown drains a delayed passive probe without republishing its result")
@MainActor
func shutdownWinsDelayedProbe() async {
  let probeGate = AsyncGate()
  let machine = MachineFixture()
  let device = testDevice()
  let workspace = OperatorWorkspace(
    machineActions: machineActions(machine, probeGate: probeGate),
    serialDevices: [device]
  )
  await workspace.selectSerialDevice(device)

  let probeTask = Task { await workspace.requestPassiveProbe() }
  while await probeGate.waiterCount == 0 { await Task.yield() }
  let shutdownTask = Task { await workspace.shutdown() }
  while !workspace.isShutdown { await Task.yield() }
  await probeGate.open()

  await probeTask.value
  await shutdownTask.value

  #expect(await machine.probeCount == 1)
  #expect(await machine.disconnectCount == 1)
  #expect(workspace.selectedSerialDevice == nil)
  #expect(workspace.machineSnapshot == nil)
  #expect(workspace.passiveProbeResult == nil)
  #expect(!workspace.passiveProbeInProgress)
}

@Test("Machine position, controller state, operation, outcome, and blocker project exactly")
@MainActor
func machineStatusProjection() async throws {
  let finalPosition = try MachinePosition(x: 12.5, y: -3.25)
  let fixture = MachineFixture(
    snapshot: testRunSnapshot(
      operation: .relativeJog(
        RelativeJogRequest(delta: try Vector2(dx: 0.5, dy: 0), feedMMPerMinute: 40)
      ),
      state: .hold,
      position: finalPosition,
      pen: .up,
      outcome: .ambiguous(.controllerHold)
    )
  )
  let device = testDevice()
  let workspace = OperatorWorkspace(
    machineActions: machineActions(fixture),
    serialDevices: [device]
  )

  await workspace.selectSerialDevice(device)

  #expect(workspace.controllerStateText == "hold")
  #expect(workspace.machinePositionText == "X 12.500   Y -3.250")
  #expect(workspace.currentOperationText == "relative jog")
  #expect(workspace.lastMotionOutcomeText.contains("ambiguous"))
  #expect(workspace.actionableError?.contains("Hold") == true)
}

@Test("Camera snapshot updates state, frame age, pixels, and actionable error")
@MainActor
func cameraProjection() async throws {
  let displayed = try testDisplayedFrame(captureNanoseconds: 1_000_000_000)
  let running = CameraCaptureSnapshot(
    devices: [CameraDevice(id: CameraDeviceID(rawValue: "camera"), name: "Camera")],
    selectedDeviceID: CameraDeviceID(rawValue: "camera"),
    state: .running,
    latestFrame: displayed,
    error: nil
  )
  let fixture = CameraFixture(snapshot: running, simulated: displayed)
  let workspace = OperatorWorkspace(
    cameraActions: cameraActions(fixture),
    nowNanoseconds: { 2_000_000_000 }
  )

  await workspace.startCamera()

  #expect(workspace.cameraStateText == "running")
  #expect(workspace.frameAgeText == "1.00 s")
  #expect(workspace.displayedFrame == displayed)

  await fixture.setSnapshot(
    CameraCaptureSnapshot(
      devices: [],
      selectedDeviceID: nil,
      state: .failed(.permissionDenied),
      latestFrame: nil,
      error: .permissionDenied
    )
  )
  await workspace.discoverCameras()
  #expect(workspace.cameraError == CameraCaptureError.permissionDenied.actionableDescription)
  workspace.stopObserving()
}

@Test("Switching to simulator cannot invoke the machine session")
@MainActor
func simulatorCannotReachMachineSession() async throws {
  let machine = MachineFixture()
  let camera = CameraFixture(
    snapshot: CameraCaptureSnapshot(
      devices: [],
      selectedDeviceID: nil,
      state: .stopped,
      latestFrame: nil,
      error: nil
    ),
    simulated: try testDisplayedFrame(source: .simulated)
  )
  let workspace = OperatorWorkspace(
    machineActions: machineActions(machine),
    cameraActions: cameraActions(camera)
  )

  await workspace.switchFrameMode(.simulated)

  #expect(workspace.frameMode == .simulated)
  #expect(workspace.displayedFrame?.source == .simulated)
  #expect(await machine.totalInvocationCount == 0)
  #expect(await camera.simulatorCount == 1)

  await workspace.selectSimulatorModelMode(.trained)
  #expect(await camera.simulatorModes == [.prior, .trained])
  #expect(await machine.totalInvocationCount == 0)
}

@Test("Camera snapshot affordance reports the exact output directory")
@MainActor
func cameraSnapshotAffordance() async throws {
  let displayed = try testDisplayedFrame()
  let camera = CameraFixture(
    snapshot: CameraCaptureSnapshot(
      devices: [CameraDevice(id: CameraDeviceID(rawValue: "camera"), name: "Camera")],
      selectedDeviceID: CameraDeviceID(rawValue: "camera"),
      state: .running,
      latestFrame: displayed,
      error: nil
    ),
    simulated: displayed
  )
  let workspace = OperatorWorkspace(cameraActions: cameraActions(camera))

  await workspace.captureCameraSnapshot()

  #expect(workspace.lastCameraSnapshotPath == "/tmp/adaptiveplotter-test-snapshot")
}

private actor MachineFixture {
  private(set) var snapshot: RunInterpreterSnapshot
  private var outcomes: [MotionOutcome]
  private(set) var jogRequests: [RelativeJogRequest] = []
  private(set) var probeCount = 0
  private(set) var selectCount = 0
  private(set) var penRequests: [PenCommand] = []
  private(set) var limitCount = 0
  private(set) var disconnectCount = 0
  private(set) var lastLimits: MotionLimits?

  init(
    snapshot: RunInterpreterSnapshot = testRunSnapshot(),
    outcomes: [MotionOutcome] = []
  ) {
    self.snapshot = snapshot
    self.outcomes = outcomes
  }

  var totalInvocationCount: Int {
    selectCount + probeCount + limitCount + disconnectCount + jogRequests.count
      + penRequests.count
  }

  func select(_ descriptor: MachineLinkDescriptor) -> RunInterpreterSnapshot {
    selectCount += 1
    return snapshot
  }

  func probe() -> PassiveProbeResult {
    probeCount += 1
    let result = PassiveProbeResult(
      link: snapshot.machine.link,
      startedAt: RuntimeTimestamp(monotonicNanoseconds: UInt64(probeCount)),
      completedAt: RuntimeTimestamp(monotonicNanoseconds: UInt64(probeCount + 1)),
      exchanges: [],
      blockers: []
    )
    snapshot = RunInterpreterSnapshot(
      currentOperation: .idle,
      machine: MachineSnapshot(
        connection: .connected,
        link: snapshot.machine.link,
        lastProbe: result,
        blockers: [],
        controllerState: .idle,
        position: try! MachinePosition(x: 0, y: 0),
        penState: .unknown
      ),
      lastMotionOutcome: nil,
      lastProbe: result
    )
    return result
  }

  func actuatePen(_ command: PenCommand) -> PenOutcome {
    penRequests.append(command)
    let outcome = PenOutcome.commandedAndSettled(
      command: command,
      commandedState: command.commandedState
    )
    snapshot = RunInterpreterSnapshot(
      currentOperation: .idle,
      machine: replacing(snapshot.machine, pen: command.commandedState),
      lastMotionOutcome: snapshot.lastMotionOutcome,
      lastPenOutcome: outcome,
      lastProbe: snapshot.lastProbe
    )
    return outcome
  }

  func updateLimits(_ limits: MotionLimits) {
    limitCount += 1
    lastLimits = limits
    replaceMachine(limits: limits)
  }

  func jog(_ request: RelativeJogRequest) -> MotionOutcome {
    jogRequests.append(request)
    let outcome = outcomes.isEmpty
      ? .acceptedThenCompleted(
        finalPosition: snapshot.machine.position ?? (try! MachinePosition(x: 0, y: 0))
      )
      : outcomes.removeFirst()
    snapshot = RunInterpreterSnapshot(
      currentOperation: .idle,
      machine: replacing(snapshot.machine, outcome: outcome),
      lastMotionOutcome: outcome,
      lastProbe: snapshot.lastProbe
    )
    return outcome
  }

  func disconnect() {
    disconnectCount += 1
    snapshot = testRunSnapshot(
      connection: .disconnected,
      state: nil,
      position: nil,
      pen: .unknown
    )
    lastLimits = nil
  }

  private func replaceMachine(pen: PenState? = nil, limits: MotionLimits? = nil) {
    snapshot = RunInterpreterSnapshot(
      currentOperation: snapshot.currentOperation,
      machine: replacing(
        snapshot.machine,
        pen: pen ?? snapshot.machine.penState,
        limits: limits ?? snapshot.machine.motionLimits
      ),
      lastMotionOutcome: snapshot.lastMotionOutcome,
      lastProbe: snapshot.lastProbe
    )
  }
}

private func machineActions(
  _ fixture: MachineFixture,
  selectGate: AsyncGate? = nil,
  probeGate: AsyncGate? = nil
) -> OperatorWorkspace.MachineActions {
  OperatorWorkspace.MachineActions(
    select: { descriptor in
      await selectGate?.wait()
      return await fixture.select(descriptor)
    },
    snapshot: { await fixture.snapshot },
    requestPassiveProbe: {
      await probeGate?.wait()
      return await fixture.probe()
    },
    updateMotionLimits: { limits in await fixture.updateLimits(limits) },
    requestRelativeJog: { request in await fixture.jog(request) },
    requestPenActuation: { command in await fixture.actuatePen(command) },
    disconnect: { await fixture.disconnect() }
  )
}

private actor CameraFixture {
  private var current: CameraCaptureSnapshot
  private let simulated: DisplayedFrame
  private(set) var simulatorCount = 0
  private(set) var simulatorModes: [SimulatorModelMode] = []
  private(set) var startCount = 0
  private(set) var stopCount = 0
  private(set) var framesCount = 0
  private(set) var selectedIDs: [CameraDeviceID] = []
  private(set) var automaticCadences: [VisionAnalysisCadence?] = []

  init(snapshot: CameraCaptureSnapshot, simulated: DisplayedFrame) {
    current = snapshot
    self.simulated = simulated
  }

  func snapshot() -> CameraCaptureSnapshot { current }
  func setSnapshot(_ snapshot: CameraCaptureSnapshot) { current = snapshot }
  func select(_ id: CameraDeviceID) -> CameraCaptureSnapshot {
    selectedIDs.append(id)
    current = CameraCaptureSnapshot(
      devices: current.devices,
      selectedDeviceID: id,
      state: .ready,
      latestFrame: nil,
      error: nil
    )
    return current
  }
  func start() -> CameraCaptureSnapshot {
    startCount += 1
    return current
  }
  func stop() -> CameraCaptureSnapshot {
    stopCount += 1
    current = CameraCaptureSnapshot(
      devices: current.devices,
      selectedDeviceID: current.selectedDeviceID,
      state: .stopped,
      latestFrame: nil,
      error: nil
    )
    return current
  }
  func simulatedContent(_ mode: SimulatorModelMode) -> SimulatedActionSurfaceContent {
    simulatorCount += 1
    simulatorModes.append(mode)
    return SimulatedActionSurfaceContent(displayedFrame: simulated, overlays: [])
  }
  func frames() -> AsyncStream<DisplayedFrame> {
    framesCount += 1
    return AsyncStream { $0.finish() }
  }
  func setAutomaticInspection(_ cadence: VisionAnalysisCadence?)
    -> PlotterSceneAnalysisSnapshot
  {
    automaticCadences.append(cadence)
    return PlotterSceneAnalysisSnapshot(
      state: cadence.map(PlotterSceneAnalysisState.running) ?? .stopped,
      submittedFrameCount: 0,
      analyzedFrameCount: 0,
      supersededFrameCount: 0,
      failedFrameCount: 0,
      activeFrameSequence: nil,
      pendingFrameSequence: nil,
      latestResult: nil,
      lastError: nil
    )
  }
}

private func cameraActions(
  _ fixture: CameraFixture,
  startGate: AsyncGate? = nil
) -> OperatorWorkspace.CameraActions {
  OperatorWorkspace.CameraActions(
    discover: { await fixture.snapshot() },
    select: { id in await fixture.select(id) },
    start: {
      await startGate?.wait()
      return await fixture.start()
    },
    stop: { await fixture.stop() },
    restart: { await fixture.snapshot() },
    snapshot: { await fixture.snapshot() },
    frames: { await fixture.frames() },
    inspectScene: { nil },
    captureSnapshot: { "/tmp/adaptiveplotter-test-snapshot" },
    setAutomaticInspection: { cadence in await fixture.setAutomaticInspection(cadence) },
    analysisUpdates: { AsyncStream { $0.finish() } },
    simulatedContent: { mode in await fixture.simulatedContent(mode) }
  )
}

private actor AsyncGate {
  private var isOpen = false
  private var waiters: [CheckedContinuation<Void, Never>] = []

  var waiterCount: Int { waiters.count }

  func wait() async {
    guard !isOpen else { return }
    await withCheckedContinuation { continuation in
      waiters.append(continuation)
    }
  }

  func open() {
    isOpen = true
    let currentWaiters = waiters
    waiters.removeAll(keepingCapacity: false)
    for waiter in currentWaiters { waiter.resume() }
  }
}

private func testDevice() -> MachineLinkDescriptor {
  MachineLinkDescriptor(
    identifier: "test-serial",
    displayName: "Test serial",
    bsdPath: "/dev/cu.test",
    transport: .bsdSerial
  )
}

private func testRunSnapshot(
  operation: RunOperation = .idle,
  connection: MachineConnectionState = .connected,
  state: ControllerState? = .idle,
  position: MachinePosition? = try! MachinePosition(x: 0, y: 0),
  pins: ControllerPins = ControllerPins(rawValue: ""),
  pen: PenState = .unknown,
  stickyAmbiguity: MotionAmbiguity? = nil,
  outcome: MotionOutcome? = nil
) -> RunInterpreterSnapshot {
  RunInterpreterSnapshot(
    currentOperation: operation,
    machine: MachineSnapshot(
      connection: connection,
      link: testDevice(),
      lastProbe: nil,
      blockers: [],
      controllerState: state,
      position: position,
      pins: pins,
      penState: pen,
      stickyAmbiguity: {
        if let stickyAmbiguity { return stickyAmbiguity }
        guard case .ambiguous(let ambiguity) = outcome else { return nil }
        return ambiguity
      }(),
      lastMotionOutcome: outcome
    ),
    lastMotionOutcome: outcome,
    lastProbe: nil
  )
}

private func replacing(
  _ machine: MachineSnapshot,
  pen: PenState? = nil,
  limits: MotionLimits? = nil,
  outcome: MotionOutcome? = nil
) -> MachineSnapshot {
  MachineSnapshot(
    connection: machine.connection,
    link: machine.link,
    lastProbe: machine.lastProbe,
    blockers: machine.blockers,
    controllerState: machine.controllerState,
    position: machine.position,
    pins: machine.pins,
    penState: pen ?? machine.penState,
    stickyAmbiguity: machine.stickyAmbiguity,
    motionLimits: limits ?? machine.motionLimits,
    operationInFlight: machine.operationInFlight,
    lastMotionOutcome: outcome ?? machine.lastMotionOutcome
  )
}

@MainActor
private func applyTestLimits(_ workspace: OperatorWorkspace) async {
  workspace.minimumXText = "-10"
  workspace.maximumXText = "10"
  workspace.minimumYText = "-20"
  workspace.maximumYText = "20"
  workspace.maximumDistanceText = "5"
  workspace.maximumFeedText = "100"
  await workspace.applyMotionLimits()
}

private func testDisplayedFrame(
  source: FrameSourceIdentity = .live(CameraDeviceID(rawValue: "camera")),
  captureNanoseconds: UInt64 = 1
) throws -> DisplayedFrame {
  DisplayedFrame(
    source: source,
    frame: try StampedFrame(
      sequence: 1,
      captureNanoseconds: captureNanoseconds,
      cameraConfigurationID: CameraConfigurationID(),
      width: 2,
      height: 2,
      rowBytes: 8,
      pixelFormat: .bgra8,
      bytes: OwnedFrameBytes(Array(repeating: 255, count: 16))
    )
  )
}

extension Array {
  fileprivate var only: Element? { count == 1 ? self[0] : nil }
}
