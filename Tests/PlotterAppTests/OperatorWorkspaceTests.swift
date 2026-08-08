import Foundation
import PlotterModel
import Testing

@testable import PlotterApp
@testable import PlotterRuntime

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

@Test("Motion defaults require no coordinate envelope or maximum-distance input")
@MainActor
func motionPriorsStayCenteredOnSessionStartZero() async throws {
  let position = try MachinePosition(x: 28.396, y: -10.002)
  let fixture = MachineFixture(snapshot: testRunSnapshot(position: position))
  let device = testDevice()
  let workspace = OperatorWorkspace(
    machineActions: machineActions(fixture),
    serialDevices: [device]
  )

  await workspace.establishMachineSession(device)

  #expect(workspace.xStepText == "1.0")
  #expect(workspace.yStepText == "1.0")
  #expect(workspace.feedText == "100")
  #expect(!workspace.motionGuardIsActive)
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
    await workspace.establishMachineSession(device)

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

  await workspace.establishMachineSession(device)

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
  await workspace.establishMachineSession(device)

  await workspace.requestPassiveProbe()
  await workspace.requestPassiveProbe()

  #expect(await fixture.probeCount == 2)
  #expect(workspace.passiveProbeResult?.blockers.isEmpty == true)
  #expect(workspace.passiveProbeUnavailableReason == nil)
}

@Test("Remembered serial choice selects a matching discovered device without opening it")
@MainActor
func rememberedSerialChoiceIsRestoredWithoutConnection() async {
  let machine = MachineFixture()
  let first = MachineLinkDescriptor(
    identifier: "/dev/cu.first",
    displayName: "First",
    bsdPath: "/dev/cu.first",
    transport: .bsdSerial
  )
  let remembered = MachineLinkDescriptor(
    identifier: "/dev/cu.remembered",
    displayName: "Remembered",
    bsdPath: "/dev/cu.remembered",
    transport: .bsdSerial
  )
  let workspace = OperatorWorkspace(
    machineActions: machineActions(machine),
    serialDeviceDiscovery: { [first, remembered] },
    loadSelectedSerialIdentifier: { remembered.identifier },
    persistSelectedSerialIdentifier: { _ in }
  )

  await workspace.refreshSerialDevices()

  #expect(workspace.selectedSerialDevice == remembered)
  #expect(await machine.selectCount == 0)
  #expect(await machine.probeCount == 0)
  #expect(!workspace.controllerIsConnected)
}

@Test("Choosing a serial device persists the choice without connecting")
@MainActor
func choosingSerialDeviceOnlyPersistsPreference() async {
  let machine = MachineFixture()
  let recorder = SynchronousStringRecorder()
  let device = testDevice()
  let workspace = OperatorWorkspace(
    machineActions: machineActions(machine),
    serialDevices: [device],
    loadSelectedSerialIdentifier: { nil },
    persistSelectedSerialIdentifier: { recorder.append($0) }
  )

  await workspace.selectSerialDevice(device)

  #expect(workspace.selectedSerialDevice == device)
  #expect(recorder.values == [device.identifier])
  #expect(await machine.selectCount == 0)
  #expect(await machine.probeCount == 0)
  #expect(!workspace.controllerIsConnected)
}

@Test("Connect selects the pending device and reports connected only after a clean probe")
@MainActor
func connectSelectedControllerRequiresSuccessfulProbe() async {
  let machine = MachineFixture()
  let device = testDevice()
  let workspace = OperatorWorkspace(
    machineActions: machineActions(machine),
    serialDevices: [device],
    loadSelectedSerialIdentifier: { nil },
    persistSelectedSerialIdentifier: { _ in }
  )
  await workspace.selectSerialDevice(device)

  #expect(!workspace.controllerIsConnected)
  await workspace.connectSelectedController()

  #expect(await machine.selectedDescriptors == [device])
  #expect(await machine.probeCount == 1)
  #expect(workspace.passiveProbeResult?.blockers.isEmpty == true)
  #expect(workspace.controllerIsConnected)
  #expect(workspace.controllerConnectionText == "connected")
}

@Test("A failed controller select or probe never reports connected")
@MainActor
func failedControllerConnectionStaysFalse() async {
  let device = testDevice()

  for failure in [FixtureMachineFailure.select, .probe] {
    let machine = MachineFixture(failure: failure)
    let workspace = OperatorWorkspace(
      machineActions: machineActions(machine),
      serialDevices: [device],
      loadSelectedSerialIdentifier: { nil },
      persistSelectedSerialIdentifier: { _ in }
    )
    await workspace.selectSerialDevice(device)

    await workspace.connectSelectedController()

    #expect(!workspace.controllerIsConnected)
    #expect(workspace.controllerConnectionText != "connected")
  }
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
  await workspace.establishMachineSession(device)
  await connectAndActivateMotion(workspace)
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
  #expect(await fixture.guardActivationCount == 1)
  #expect(workspace.cameraSnapshot == nil)
  #expect(!workspace.recordJogObservations)
  #expect(await fixture.observedJogRequests.isEmpty)
}

@Test("Simulator cannot record physical jog evidence or reach an observed-jog action")
@MainActor
func simulatorCannotRecordPhysicalJogEvidence() async throws {
  let liveFrame = try testDisplayedFrame()
  let camera = CameraFixture(
    snapshot: CameraCaptureSnapshot(
      devices: [CameraDevice(id: CameraDeviceID(rawValue: "camera"), name: "Camera")],
      selectedDeviceID: CameraDeviceID(rawValue: "camera"),
      state: .running,
      latestFrame: liveFrame,
      error: nil
    ),
    simulated: try testDisplayedFrame(source: .simulated)
  )
  let machine = MachineFixture()
  let device = testDevice()
  let workspace = OperatorWorkspace(
    machineActions: machineActions(machine),
    cameraActions: cameraActions(camera),
    serialDevices: [device]
  )
  await workspace.establishMachineSession(device)
  await connectAndActivateMotion(workspace)
  await workspace.requestPenActuation(.raise)
  await workspace.switchFrameMode(.simulated)
  workspace.setRecordJogObservations(true)

  #expect(
    workspace.motionUnavailableReason
      == "SIMULATED source cannot issue physical machine commands. Switch to LIVE first."
  )
  await workspace.requestJog(.xPositive)

  #expect(await machine.observedJogRequests.isEmpty)
  #expect(await machine.jogRequests.isEmpty)
  #expect(await camera.visibleToolObservationCount == 0)
  #expect(workspace.physicalJogObservations.isEmpty)
  #expect(workspace.physicalJogObservationCountText == "0")
  #expect(workspace.lastPhysicalJogObservationResultText == "none")
}

@Test("Simulator blocks ordinary jog and pen intents before MachineActions")
@MainActor
func simulatorBlocksEveryPhysicalCommandIntent() async throws {
  let machine = MachineFixture(snapshot: testRunSnapshot(pen: .up))
  let device = testDevice()
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
    cameraActions: cameraActions(camera),
    serialDevices: [device]
  )
  await workspace.establishMachineSession(device)
  await connectAndActivateMotion(workspace)
  await workspace.switchFrameMode(.simulated)
  workspace.setRecordJogObservations(false)

  let expected = "SIMULATED source cannot issue physical machine commands. Switch to LIVE first."
  #expect(workspace.motionUnavailableReason == expected)
  #expect(workspace.penUnavailableReason(for: .raise) == expected)
  #expect(workspace.penUnavailableReason(for: .lower) == expected)
  await workspace.requestJog(.xPositive)
  await workspace.requestPenActuation(.raise)
  await workspace.requestPenActuation(.lower)

  #expect(await machine.jogRequests.isEmpty)
  #expect(await machine.observedJogRequests.isEmpty)
  #expect(await machine.penRequests.isEmpty)
}

@Test("Switching to SIMULATED is refused while a live physical jog is active")
@MainActor
func simulatorSwitchCannotHideActiveJogCancel() async throws {
  let jogGate = AsyncGate()
  let machine = MachineFixture()
  let device = testDevice()
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
    machineActions: machineActions(machine, jogGate: jogGate),
    cameraActions: cameraActions(camera),
    serialDevices: [device]
  )
  await workspace.establishMachineSession(device)
  await connectAndActivateMotion(workspace)
  await workspace.requestPenActuation(.raise)
  let jogTask = Task { await workspace.requestJog(.xPositive) }
  while await jogGate.waiterCount == 0 { await Task.yield() }

  await workspace.switchFrameMode(.simulated)

  #expect(workspace.frameMode == .live)
  #expect(
    workspace.cameraError
      == "Wait for the current physical controller operation before switching frame source."
  )
  #expect(workspace.jogCancelUnavailableReason == nil)
  #expect(await camera.simulatorCount == 0)

  await jogGate.open()
  await jogTask.value
}

@Test("Switching to SIMULATED cannot hide an active physical preflight")
@MainActor
func simulatorSwitchCannotHidePhysicalPreflight() async throws {
  let cameraID = CameraDeviceID(rawValue: "camera")
  let displayedFrame = try testDisplayedFrame(source: .live(cameraID))
  let camera = CameraFixture(
    snapshot: CameraCaptureSnapshot(
      devices: [CameraDevice(id: cameraID, name: "Camera")],
      selectedDeviceID: cameraID,
      state: .running,
      latestFrame: displayedFrame,
      error: nil
    ),
    simulated: try testDisplayedFrame(source: .simulated)
  )
  let machine = MachineFixture()
  let voice = VoiceFixture()
  let device = testDevice()
  let workspace = OperatorWorkspace(
    machineActions: machineActions(machine),
    cameraActions: cameraActions(camera),
    voiceActions: voiceActions(voice),
    serialDevices: [device],
    nowNanoseconds: { 1 }
  )

  await workspace.selectSerialDevice(device)
  await workspace.connectSelectedController()
  await workspace.activateMotionGuard()
  await workspace.startCamera()
  await workspace.startPreflightSequence(.penUpConfirmation)
  while await voice.streamSubscriberCount == 0 { await Task.yield() }

  await workspace.switchFrameMode(.simulated)

  #expect(workspace.frameMode == .live)
  #expect(workspace.activePreflightSequenceID == .penUpConfirmation)
  #expect(workspace.voiceListening)
  #expect(
    workspace.cameraError
      == "Finish or cancel the active Motion Preflight before switching frame source."
  )
  #expect(await camera.simulatorCount == 0)

  await workspace.cancelPreflightSequence(.penUpConfirmation)
}

@Test("Observed jog projects one exact camera failure without moving or recording")
@MainActor
func observedJogFailureProjectsExactly() async throws {
  let liveFrame = try testDisplayedFrame()
  let camera = CameraFixture(
    snapshot: CameraCaptureSnapshot(
      devices: [CameraDevice(id: CameraDeviceID(rawValue: "camera"), name: "Camera")],
      selectedDeviceID: CameraDeviceID(rawValue: "camera"),
      state: .running,
      latestFrame: liveFrame,
      error: nil
    ),
    simulated: try testDisplayedFrame(source: .simulated)
  )
  let machine = MachineFixture()
  let device = testDevice()
  let workspace = OperatorWorkspace(
    machineActions: machineActions(machine),
    cameraActions: cameraActions(camera),
    serialDevices: [device]
  )
  await workspace.establishMachineSession(device)
  await connectAndActivateMotion(workspace)
  await workspace.requestPenActuation(.raise)
  await workspace.startCamera()
  workspace.selectObservationSplit(.holdout)
  workspace.setRecordJogObservations(true)

  #expect(workspace.motionUnavailableReason == nil)
  await workspace.requestJog(.xPositive)

  let request = try #require(await machine.observedJogRequests.only)
  let expected = PhysicalJogObservationFailure.frameUnavailable(.beforeMotion)
    .actionableDescription
  #expect(request.split == .holdout)
  #expect(await machine.jogRequests.isEmpty)
  #expect(await camera.visibleToolObservationCount == 1)
  #expect(workspace.physicalJogObservations.isEmpty)
  #expect(workspace.lastPhysicalJogObservationResultText == "not recorded")
  #expect(workspace.lastPhysicalJogPositionsText == "unknown")
  #expect(workspace.lastPhysicalJogCameraDeltaText == "unknown")
  #expect(workspace.lastPhysicalJogConfidenceText == "unknown")
  #expect(workspace.lastPhysicalJogFailureText == expected)
  #expect(workspace.actionableError == expected)
  #expect(workspace.lastMotionOutcomeText == "none")
}

@Test("Ambiguous observed jog records no physical sample and never requests an after frame")
@MainActor
func ambiguousObservedJogRecordsNothing() async throws {
  let before = try await testVisibleToolObservation(
    phase: .beforeMotion,
    captureNanoseconds: 100,
    capOriginX: 36,
    capOriginY: 30
  )
  let liveFrame = try testDisplayedFrame()
  let camera = CameraFixture(
    snapshot: CameraCaptureSnapshot(
      devices: [CameraDevice(id: CameraDeviceID(rawValue: "camera"), name: "Camera")],
      selectedDeviceID: CameraDeviceID(rawValue: "camera"),
      state: .running,
      latestFrame: liveFrame,
      error: nil
    ),
    simulated: try testDisplayedFrame(source: .simulated),
    visibleToolResults: [.success(before)]
  )
  let motionOutcome = MotionOutcome.ambiguous(.disconnected)
  let machine = MachineFixture(outcomes: [motionOutcome])
  let device = testDevice()
  let workspace = OperatorWorkspace(
    machineActions: machineActions(machine),
    cameraActions: cameraActions(camera),
    serialDevices: [device]
  )
  await workspace.establishMachineSession(device)
  await connectAndActivateMotion(workspace)
  await workspace.requestPenActuation(.raise)
  await workspace.startCamera()
  workspace.setRecordJogObservations(true)

  await workspace.requestJog(.xPositive)

  let expected = PhysicalJogObservationFailure.motionNotCompleted(motionOutcome)
    .actionableDescription
  #expect(await machine.observedJogRequests.count == 1)
  #expect(await camera.visibleToolObservationCount == 1)
  #expect(workspace.physicalJogObservations.isEmpty)
  #expect(workspace.physicalJogObservationCountText == "0")
  #expect(workspace.lastPhysicalJogObservationResultText == "not recorded")
  #expect(workspace.lastPhysicalJogFailureText == expected)
  #expect(workspace.actionableError == expected)
  #expect(workspace.lastMotionOutcomeText.contains("ambiguous"))
}

@Test("Recorded jog projects immutable split, machine positions, camera delta, and confidence")
@MainActor
func observedJogSuccessProjectsExactFacts() async throws {
  let before = try await testVisibleToolObservation(
    phase: .beforeMotion,
    captureNanoseconds: 100,
    capOriginX: 36,
    capOriginY: 30
  )
  let after = try await testVisibleToolObservation(
    phase: .afterMotion,
    captureNanoseconds: 201,
    capOriginX: 40,
    capOriginY: 28
  )
  let liveFrame = try testDisplayedFrame()
  let camera = CameraFixture(
    snapshot: CameraCaptureSnapshot(
      devices: [CameraDevice(id: CameraDeviceID(rawValue: "camera"), name: "Camera")],
      selectedDeviceID: CameraDeviceID(rawValue: "camera"),
      state: .running,
      latestFrame: liveFrame,
      error: nil
    ),
    simulated: try testDisplayedFrame(source: .simulated),
    visibleToolResults: [.success(before), .success(after)]
  )
  let machine = MachineFixture(
    outcomes: [.acceptedThenCompleted(finalPosition: try MachinePosition(x: 1, y: 0))]
  )
  let device = testDevice()
  let workspace = OperatorWorkspace(
    machineActions: machineActions(machine),
    cameraActions: cameraActions(camera),
    serialDevices: [device]
  )
  await workspace.establishMachineSession(device)
  await connectAndActivateMotion(workspace)
  await workspace.requestPenActuation(.raise)
  await workspace.startCamera()
  workspace.selectObservationSplit(.holdout)
  workspace.setRecordJogObservations(true)

  await workspace.requestJog(.xPositive)
  workspace.selectObservationSplit(.training)

  let recorded = try #require(workspace.physicalJogObservations.only)
  #expect(recorded.request.split == .holdout)
  #expect(workspace.selectedObservationSplit == .training)
  #expect(await camera.visibleToolObservationCount == 2)
  let observationBoundaries = await camera.visibleToolObservationBoundaries
  #expect(observationBoundaries.count == 2)
  #expect(observationBoundaries[0].0 == .beforeMotion)
  #expect(observationBoundaries[0].1 == 0)
  #expect(observationBoundaries[1].0 == .afterMotion)
  #expect(observationBoundaries[1].1 == recorded.finalControllerSampleNanoseconds)
  #expect(recorded.after.captureNanoseconds > observationBoundaries[1].1)
  #expect(workspace.physicalJogObservationCountText == "1")
  #expect(workspace.lastPhysicalJogObservationResultText == "recorded · holdout")
  #expect(workspace.lastPhysicalJogPositionsText == "X 0.000 Y 0.000 → X 1.000 Y 0.000")
  #expect(workspace.lastPhysicalJogCameraDeltaText == "Δx 4.00 px · Δy -2.00 px")
  #expect(workspace.lastPhysicalJogConfidenceText == "before 0.375 · after 0.375")
  #expect(workspace.lastPhysicalJogFailureText == nil)
  #expect(workspace.actionableError == nil)
}

@Test("Two-axis training samples project the diagnostic pixel response matrix")
@MainActor
func twoAxisTrainingProjectsJogResponseMatrix() async throws {
  let configuration = testCameraConfiguration(0x123)
  let observations = try await responseObservations(
    configuration: configuration,
    deltas: [(2, -1), (3, 4)]
  )
  let result = try await observationWorkspace(
    configuration: configuration,
    observations: observations,
    outcomes: [
      .acceptedThenCompleted(finalPosition: try MachinePosition(x: 1, y: 0)),
      .acceptedThenCompleted(finalPosition: try MachinePosition(x: 0, y: 1)),
    ]
  )

  await result.workspace.requestJog(.xPositive)
  await result.workspace.requestJog(.yPositive)

  let candidate = try #require(result.workspace.jogResponseCandidate)
  #expect(candidate.matrix.cameraXPerMachineX == 2)
  #expect(candidate.matrix.cameraXPerMachineY == 3)
  #expect(candidate.matrix.cameraYPerMachineX == -1)
  #expect(candidate.matrix.cameraYPerMachineY == 4)
  #expect(candidate.trainingMetrics.rootMeanSquarePixels == 0)
  #expect(result.workspace.jogResponseDataset?.summary.trainingCount == 2)
  #expect(result.workspace.jogResponseDataset?.summary.holdoutCount == 0)
  #expect(result.workspace.jogResponseDatasetCountText == "training 2 · holdout 0")
  #expect(result.workspace.jogResponseMatrixText == "[2.0000  3.0000;  -1.0000  4.0000] px/mm")
  #expect(result.workspace.jogResponseLearnerError == nil)
}

@Test("Holdout samples remain separate from the two-axis training fit")
@MainActor
func holdoutSamplesRemainSeparateFromFit() async throws {
  let configuration = testCameraConfiguration(0x124)
  let observations = try await responseObservations(
    configuration: configuration,
    deltas: [(2, -1), (3, 4), (6, 3)]
  )
  let result = try await observationWorkspace(
    configuration: configuration,
    observations: observations,
    outcomes: [
      .acceptedThenCompleted(finalPosition: try MachinePosition(x: 1, y: 0)),
      .acceptedThenCompleted(finalPosition: try MachinePosition(x: 0, y: 1)),
      .acceptedThenCompleted(finalPosition: try MachinePosition(x: 1, y: 1)),
    ]
  )

  await result.workspace.requestJog(.xPositive)
  await result.workspace.requestJog(.yPositive)
  result.workspace.selectObservationSplit(.holdout)
  await result.workspace.requestJog(.xPositive)

  let candidate = try #require(result.workspace.jogResponseCandidate)
  #expect(candidate.matrix.cameraXPerMachineX == 2)
  #expect(candidate.matrix.cameraXPerMachineY == 3)
  #expect(candidate.matrix.cameraYPerMachineX == -1)
  #expect(candidate.matrix.cameraYPerMachineY == 4)
  #expect(candidate.trainingMetrics.rootMeanSquarePixels == 0)
  #expect(candidate.holdoutMetrics?.episodeCount == 1)
  #expect(candidate.holdoutMetrics?.rootMeanSquarePixels == 1)
  #expect(result.workspace.jogResponseDataset?.summary.trainingCount == 2)
  #expect(result.workspace.jogResponseDataset?.summary.holdoutCount == 1)
  #expect(result.workspace.jogResponseDatasetCountText == "training 2 · holdout 1")
  #expect(result.workspace.jogResponseHoldoutResidualText == "RMS 1.000 px · max 1.000 px · n 1")
}

@Test("A live camera configuration change blocks an observed jog before motion")
@MainActor
func cameraConfigurationChangeBlocksObservedJogPrewrite() async throws {
  let pinnedConfiguration = testCameraConfiguration(0x125)
  let result = try await observationWorkspace(
    configuration: pinnedConfiguration,
    observations: try await responseObservations(
      configuration: pinnedConfiguration,
      deltas: [(2, -1)]
    ),
    outcomes: [
      .acceptedThenCompleted(finalPosition: try MachinePosition(x: 1, y: 0)),
    ]
  )
  await result.workspace.requestJog(.xPositive)
  await result.camera.setSnapshot(
    CameraCaptureSnapshot(
      devices: [CameraDevice(id: CameraDeviceID(rawValue: "camera"), name: "Camera")],
      selectedDeviceID: CameraDeviceID(rawValue: "camera"),
      state: .running,
      latestFrame: try testDisplayedFrame(configuration: testCameraConfiguration(0x126)),
      error: nil
    )
  )
  await result.workspace.startCamera()

  let expected = "Displayed LIVE camera configuration differs from the recorded sample set. Clear Samples before recording another jog."
  #expect(result.workspace.motionUnavailableReason == expected)
  await result.workspace.requestJog(.xPositive)
  #expect(await result.machine.observedJogRequests.count == 1)
  #expect(await result.camera.visibleToolObservationCount == 2)
  #expect(result.workspace.physicalJogObservations.count == 1)
}

@Test("Clear Samples resets current-session diagnostic data")
@MainActor
func clearJogObservationSamplesResetsDiagnosticData() async throws {
  let configuration = testCameraConfiguration(0x127)
  let result = try await observationWorkspace(
    configuration: configuration,
    observations: try await responseObservations(
      configuration: configuration,
      deltas: [(2, -1)]
    ),
    outcomes: [
      .acceptedThenCompleted(finalPosition: try MachinePosition(x: 1, y: 0)),
    ]
  )
  await result.workspace.requestJog(.xPositive)
  #expect(result.workspace.jogResponseLearnerError != nil)

  result.workspace.clearJogObservationSamples()

  #expect(result.workspace.physicalJogObservations.isEmpty)
  #expect(result.workspace.jogResponseDataset == nil)
  #expect(result.workspace.jogResponseCandidate == nil)
  #expect(result.workspace.jogResponseLearnerError == nil)
  #expect(result.workspace.jogResponseDatasetCountText == "training 0 · holdout 0")
  #expect(result.workspace.lastPhysicalJogObservationResultText == "recorded · training")
}

@Test("A diagnostic fit failure preserves the recorded motion and raw episode")
@MainActor
func jogResponseFailurePreservesRecordedTruth() async throws {
  let configuration = testCameraConfiguration(0x128)
  let result = try await observationWorkspace(
    configuration: configuration,
    observations: try await responseObservations(
      configuration: configuration,
      deltas: [(2, -1)]
    ),
    outcomes: [
      .acceptedThenCompleted(finalPosition: try MachinePosition(x: 1, y: 0)),
    ]
  )

  await result.workspace.requestJog(.xPositive)

  #expect(result.workspace.physicalJogObservations.count == 1)
  #expect(result.workspace.jogResponseDataset?.summary.episodeCount == 1)
  #expect(result.workspace.jogResponseCandidate == nil)
  #expect(
    result.workspace.jogResponseLearnerError
      == "Need 2 training samples spanning both machine axes; 1 recorded."
  )
  #expect(result.workspace.lastMotionOutcomeText == "completed at X 1.000 Y 0.000")
  #expect(result.workspace.lastPhysicalJogObservationResultText == "recorded · training")
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
  await workspace.establishMachineSession(device)
  await connectAndActivateMotion(workspace)
  await workspace.requestPenActuation(.raise)

  await workspace.requestJog(.xPositive)
  #expect(workspace.lastMotionOutcomeText.contains("refused"))
  #expect(workspace.motionUnavailableReason == nil)

  await workspace.requestJog(.xPositive)

  #expect(await fixture.jogRequests.count == 2)
  #expect(workspace.lastMotionOutcomeText.contains("completed at X 1.000 Y 0.000"))
}

@Test("Voice permission and listening state project the exact denied subsystem")
@MainActor
func voicePermissionProjectionIsTruthful() async {
  let voice = VoiceFixture(authorization: .microphoneDenied)
  let workspace = OperatorWorkspace(voiceActions: voiceActions(voice))

  await workspace.startVoiceListening()

  #expect(
    workspace.voicePermissionText
      == "microphone denied — allow it in System Settings"
  )
  #expect(workspace.voiceListeningText == "stopped")
  #expect(!workspace.voiceListening)
  #expect(await voice.startCount == 0)
}

@Test("Starting Pen Up preflight owns speech and pairs confirmation with the exact frame")
@MainActor
func penUpPreflightOwnsSpeechAndExactFrame() async throws {
  let configuration = testCameraConfiguration(0x201)
  let displayedFrame = try testDisplayedFrame(
    captureNanoseconds: 42,
    configuration: configuration
  )
  let inspectionFrame = try testDisplayedFrame(
    captureNanoseconds: 43,
    configuration: configuration
  )
  let inspection = LiveSceneInspection(
    displayedFrame: inspectionFrame,
    measurement: testSceneMeasurement(for: inspectionFrame)
  )
  let camera = CameraFixture(
    snapshot: CameraCaptureSnapshot(
      devices: [CameraDevice(id: CameraDeviceID(rawValue: "camera"), name: "Camera")],
      selectedDeviceID: CameraDeviceID(rawValue: "camera"),
      state: .running,
      latestFrame: displayedFrame,
      error: nil
    ),
    simulated: displayedFrame,
    sceneInspections: [inspection]
  )
  let machine = MachineFixture()
  let voice = VoiceFixture()
  let device = testDevice()
  let workspace = OperatorWorkspace(
    machineActions: machineActions(machine),
    cameraActions: cameraActions(camera),
    voiceActions: voiceActions(voice),
    serialDevices: [device],
    nowNanoseconds: { 42 }
  )

  await workspace.selectSerialDevice(device)
  await workspace.connectSelectedController()
  await workspace.activateMotionGuard()
  await workspace.startCamera()
  await workspace.startPreflightSequence(.penUpConfirmation)
  for _ in 0..<2_000 {
    if await voice.streamSubscriberCount > 0 { break }
    await Task.yield()
  }

  #expect(await voice.streamSubscriberCount == 1)
  #expect(await voice.startCount == 1)
  #expect(workspace.voiceListening)
  #expect(
    workspace.preflightTransactions[.penUpConfirmation]?.voiceContext?.expectedResponse
      == .penIsPhysicallyUp
  )

  await voice.yield(
    VoiceTranscript(
      utteranceID: UUID(),
      sequence: 1,
      text: PreflightVoiceResponse.penIsPhysicallyUp.exactPhrase,
      isFinal: true,
      monotonicNanoseconds: 1
    )
  )
  for _ in 0..<2_000 {
    if workspace.preflightTransactions[.penUpConfirmation]?.state == .succeeded { break }
    await Task.yield()
  }

  let transaction = try #require(workspace.preflightTransactions[.penUpConfirmation])
  #expect(transaction.state == .succeeded)
  #expect(await voice.stopCount == 1)
  #expect(!workspace.voiceListening)
  #expect(await machine.penRequests == [.raise])
  #expect(
    transaction.evidenceSummaries.contains {
      $0.kind == .camera
        && $0.frameID == inspectionFrame.frame.id
        && $0.cameraConfigurationID == inspectionFrame.frame.cameraConfigurationID
    }
  )
  #expect(await camera.sceneInspectionBoundaries == [42])
}

@Test("Changing camera authority tears down an awaiting preflight microphone")
@MainActor
func cameraAuthorityChangeStopsPreflightListening() async throws {
  let firstCamera = CameraDevice(id: CameraDeviceID(rawValue: "camera-a"), name: "Camera A")
  let secondCamera = CameraDevice(id: CameraDeviceID(rawValue: "camera-b"), name: "Camera B")
  let displayedFrame = try testDisplayedFrame(
    source: .live(firstCamera.id),
    captureNanoseconds: 126
  )
  let camera = CameraFixture(
    snapshot: CameraCaptureSnapshot(
      devices: [firstCamera, secondCamera],
      selectedDeviceID: firstCamera.id,
      state: .running,
      latestFrame: displayedFrame,
      error: nil
    ),
    simulated: displayedFrame
  )
  let machine = MachineFixture()
  let voice = VoiceFixture()
  let device = testDevice()
  let workspace = OperatorWorkspace(
    machineActions: machineActions(machine),
    cameraActions: cameraActions(camera),
    voiceActions: voiceActions(voice),
    serialDevices: [device],
    nowNanoseconds: { 126 }
  )

  await workspace.selectSerialDevice(device)
  await workspace.connectSelectedController()
  await workspace.activateMotionGuard()
  await workspace.startCamera()
  await workspace.startPreflightSequence(.penUpConfirmation)
  for _ in 0..<2_000 {
    if await voice.streamSubscriberCount > 0 { break }
    await Task.yield()
  }
  #expect(workspace.activePreflightSequenceID == .penUpConfirmation)
  #expect(workspace.voiceListening)

  await workspace.selectCamera(secondCamera.id)

  #expect(await voice.stopCount == 1)
  #expect(!workspace.voiceListening)
  #expect(workspace.activePreflightSequenceID == nil)
  #expect(workspace.preflightTransactions.isEmpty)
  #expect(workspace.selectedCameraID == secondCamera.id)
}

@Test("Camera restart cancels and settles boundary motion before erasing preflight authority")
@MainActor
func cameraRestartSettlesBoundaryMotionBeforeAuthorityErasure() async throws {
  let cameraID = CameraDeviceID(rawValue: "camera")
  let displayedFrame = try testDisplayedFrame(source: .live(cameraID))
  let camera = CameraFixture(
    snapshot: CameraCaptureSnapshot(
      devices: [CameraDevice(id: cameraID, name: "Camera")],
      selectedDeviceID: cameraID,
      state: .running,
      latestFrame: displayedFrame,
      error: nil
    ),
    simulated: displayedFrame
  )
  let finalPosition = try MachinePosition(x: 4, y: 0)
  let machine = MachineFixture(
    outcomes: [.cancelled(finalPosition: finalPosition)],
    cancelOutcomes: [.transmitted]
  )
  let voice = VoiceFixture()
  let jogGate = AsyncGate()
  let device = testDevice()
  let workspace = OperatorWorkspace(
    machineActions: machineActions(machine, jogGate: jogGate),
    cameraActions: cameraActions(camera),
    voiceActions: voiceActions(voice),
    serialDevices: [device],
    nowNanoseconds: { 2 }
  )

  await workspace.selectSerialDevice(device)
  await workspace.connectSelectedController()
  await workspace.activateMotionGuard()
  await workspace.requestPenActuation(.raise)
  await workspace.startCamera()
  await workspace.startPreflightSequence(.boundaryPositiveX)
  while await voice.streamSubscriberCount == 0 { await Task.yield() }
  await voice.yield(
    VoiceTranscript(
      utteranceID: UUID(),
      sequence: 1,
      text: "READY",
      isFinal: true,
      monotonicNanoseconds: 1
    )
  )
  while workspace.boundaryTeachingState != .moving(.xPositive) { await Task.yield() }

  let restartTask = Task { await workspace.restartCamera() }
  while await machine.cancelRequestCount == 0 { await Task.yield() }

  #expect(await camera.restartCount == 0)
  #expect(workspace.boundaryTeachingState == .cancelling(.xPositive))
  #expect(workspace.preflightTransactions[.boundaryPositiveX]?.state == .cancelling)

  await jogGate.open()
  await restartTask.value

  #expect(await machine.cancelRequestCount == 1)
  #expect(await camera.restartCount == 1)
  #expect(workspace.boundaryTeachingState == .idle)
  #expect(workspace.preflightTransactions.isEmpty)
  #expect(!workspace.voiceListening)
}

@Test("Camera authority change invalidates suspended preflight microphone authorization")
@MainActor
func cameraAuthorityChangeInvalidatesSuspendedAuthorization() async throws {
  let firstCamera = CameraDevice(id: CameraDeviceID(rawValue: "camera-a"), name: "Camera A")
  let secondCamera = CameraDevice(id: CameraDeviceID(rawValue: "camera-b"), name: "Camera B")
  let displayedFrame = try testDisplayedFrame(source: .live(firstCamera.id))
  let camera = CameraFixture(
    snapshot: CameraCaptureSnapshot(
      devices: [firstCamera, secondCamera],
      selectedDeviceID: firstCamera.id,
      state: .running,
      latestFrame: displayedFrame,
      error: nil
    ),
    simulated: displayedFrame
  )
  let authorizationGate = AsyncGate()
  let voice = VoiceFixture(authorizationGate: authorizationGate)
  let machine = MachineFixture()
  let device = testDevice()
  let workspace = OperatorWorkspace(
    machineActions: machineActions(machine),
    cameraActions: cameraActions(camera),
    voiceActions: voiceActions(voice),
    serialDevices: [device],
    nowNanoseconds: { 2 }
  )

  await workspace.selectSerialDevice(device)
  await workspace.connectSelectedController()
  await workspace.activateMotionGuard()
  await workspace.startCamera()
  let preflightTask = Task { await workspace.startPreflightSequence(.penUpConfirmation) }
  while await authorizationGate.waiterCount == 0 { await Task.yield() }

  await workspace.selectCamera(secondCamera.id)
  await authorizationGate.open()
  await preflightTask.value

  #expect(await voice.startCount == 0)
  #expect(!workspace.voiceListening)
  #expect(!(await voice.isCurrentlyListening))
  #expect(workspace.preflightTransactions.isEmpty)
  #expect(workspace.selectedCameraID == secondCamera.id)
}

@Test("Cancelling preflight invalidates and stops suspended microphone startup")
@MainActor
func preflightCancellationInvalidatesSuspendedMicrophoneStartup() async throws {
  let cameraID = CameraDeviceID(rawValue: "camera")
  let displayedFrame = try testDisplayedFrame(source: .live(cameraID))
  let camera = CameraFixture(
    snapshot: CameraCaptureSnapshot(
      devices: [CameraDevice(id: cameraID, name: "Camera")],
      selectedDeviceID: cameraID,
      state: .running,
      latestFrame: displayedFrame,
      error: nil
    ),
    simulated: displayedFrame
  )
  let startupGate = AsyncGate()
  let voice = VoiceFixture(startupGate: startupGate)
  let machine = MachineFixture()
  let device = testDevice()
  let workspace = OperatorWorkspace(
    machineActions: machineActions(machine),
    cameraActions: cameraActions(camera),
    voiceActions: voiceActions(voice),
    serialDevices: [device],
    nowNanoseconds: { 2 }
  )

  await workspace.selectSerialDevice(device)
  await workspace.connectSelectedController()
  await workspace.activateMotionGuard()
  await workspace.startCamera()
  let preflightTask = Task { await workspace.startPreflightSequence(.penUpConfirmation) }
  while await startupGate.waiterCount == 0 { await Task.yield() }
  #expect(await voice.isCurrentlyListening)

  await workspace.cancelPreflightSequence(.penUpConfirmation)
  #expect(
    workspace.preflightStartUnavailableReason(for: .penUpConfirmation)?
      .contains("previous Motion Preflight microphone request") == true
  )
  await startupGate.open()
  await preflightTask.value

  #expect(await voice.startCount == 1)
  #expect(await voice.stopCount >= 1)
  #expect(!(await voice.isCurrentlyListening))
  #expect(!workspace.voiceListening)
  #expect(workspace.preflightTransactions[.penUpConfirmation]?.state == .cancelled)
}

@Test("Boundary preflight updates the drawing-frame posterior from the exact inspected frame")
@MainActor
func boundaryPreflightUpdatesExactFramePosterior() async throws {
  let configuration = testCameraConfiguration(0x202)
  let displayedFrame = try testDisplayedFrame(
    captureNanoseconds: 84,
    configuration: configuration
  )
  let inspectionFrame = try testDisplayedFrame(
    captureNanoseconds: 85,
    configuration: configuration
  )
  let inspection = LiveSceneInspection(
    displayedFrame: inspectionFrame,
    measurement: testSceneMeasurement(
      for: inspectionFrame,
      cap: try testGreenCapMeasurement(),
      drawingFrame: try testDrawingFrameEstimate()
    )
  )
  let camera = CameraFixture(
    snapshot: CameraCaptureSnapshot(
      devices: [CameraDevice(id: CameraDeviceID(rawValue: "camera"), name: "Camera")],
      selectedDeviceID: CameraDeviceID(rawValue: "camera"),
      state: .running,
      latestFrame: displayedFrame,
      error: nil
    ),
    simulated: displayedFrame,
    sceneInspections: [inspection]
  )
  let jogGate = AsyncGate()
  let finalPosition = try MachinePosition(x: 12.5, y: 0)
  let machine = MachineFixture(
    outcomes: [.cancelled(finalPosition: finalPosition)],
    cancelOutcomes: [.transmitted]
  )
  let voice = VoiceFixture()
  let device = testDevice()
  let workspace = OperatorWorkspace(
    machineActions: machineActions(machine, jogGate: jogGate),
    cameraActions: cameraActions(camera),
    voiceActions: voiceActions(voice),
    serialDevices: [device],
    nowNanoseconds: { 84 }
  )

  await workspace.selectSerialDevice(device)
  await workspace.connectSelectedController()
  await workspace.activateMotionGuard()
  await workspace.requestPenActuation(.raise)
  await workspace.startCamera()
  await workspace.startPreflightSequence(.boundaryPositiveX)
  for _ in 0..<2_000 {
    if await voice.streamSubscriberCount > 0 { break }
    await Task.yield()
  }

  await voice.yield(
    VoiceTranscript(
      utteranceID: UUID(),
      sequence: 1,
      text: PreflightVoiceResponse.ready.exactPhrase,
      isFinal: true,
      monotonicNanoseconds: 1
    )
  )
  for _ in 0..<2_000 {
    if workspace.boundaryTeachingState == .moving(.xPositive) { break }
    await Task.yield()
  }
  #expect(workspace.boundaryTeachingState == .moving(.xPositive))

  await voice.yield(
    VoiceTranscript(
      utteranceID: UUID(),
      sequence: 2,
      text: PreflightVoiceResponse.stop.exactPhrase,
      isFinal: true,
      monotonicNanoseconds: 2
    )
  )
  for _ in 0..<2_000 {
    if await machine.cancelRequestCount > 0 { break }
    await Task.yield()
  }
  await jogGate.open()
  for _ in 0..<2_000 {
    if workspace.preflightTransactions[.boundaryPositiveX]?.state == .succeeded { break }
    await Task.yield()
  }

  let transaction = try #require(workspace.preflightTransactions[.boundaryPositiveX])
  let posterior = try #require(workspace.drawingFramePosterior)
  #expect(transaction.state == .succeeded)
  #expect(workspace.boundaryPositions[.xPositive] == finalPosition)
  #expect(posterior.observationCount == 1)
  #expect(posterior.observations[0].controllerPosition == finalPosition)
  #expect(posterior.estimate.geometry.points[0].y == -0.25)
  #expect(posterior.estimate.geometry.points[1].y == -0.25)
  #expect(posterior.latestObservationKey.frameID == inspectionFrame.frame.id)
  #expect(
    posterior.latestObservationKey.cameraConfigurationID
      == inspectionFrame.frame.cameraConfigurationID
  )
  #expect(
    workspace.cameraOverlays.contains {
      $0.frameID == inspectionFrame.frame.id
        && $0.provenance.algorithmRevision == "motion-preflight-posterior-v1"
    }
  )
  #expect(await voice.stopCount == 1)
  #expect(await camera.sceneInspectionBoundaries == [84])
}

@Test("Ambient speech cannot issue controller actions outside a boundary interaction")
@MainActor
func ambientSpeechIsInert() async {
  let machine = MachineFixture()
  let voice = VoiceFixture()
  let workspace = OperatorWorkspace(
    machineActions: machineActions(machine),
    voiceActions: voiceActions(voice)
  )
  await workspace.startVoiceListening()
  while await voice.streamSubscriberCount == 0 { await Task.yield() }
  let baseline = await machine.totalInvocationCount

  let phrases = ["stop", "x plus", "pen up", "status"]
  for (index, phrase) in phrases.enumerated() {
    await voice.yield(
      VoiceTranscript(
        utteranceID: UUID(),
        sequence: UInt64(index + 1),
        text: phrase,
        isFinal: true,
        monotonicNanoseconds: UInt64(index + 1)
      )
    )
    while workspace.voiceTranscriptText != phrase { await Task.yield() }
  }

  #expect(await machine.totalInvocationCount == baseline)
  #expect(await machine.jogRequests.isEmpty)
  #expect(await machine.penRequests.isEmpty)
  #expect(await machine.cancelRequestCount == 0)
  #expect(workspace.boundaryTeachingState == .idle)
  await workspace.stopVoiceListening()
}

@Test("READY starts one bounded boundary jog")
@MainActor
func boundaryReadyStartsOneBoundedJog() async throws {
  let jogGate = AsyncGate()
  let machine = MachineFixture(
    outcomes: [.acceptedThenCompleted(finalPosition: try MachinePosition(x: 5, y: 0))]
  )
  let voice = VoiceFixture()
  let workspace = await preparedBoundaryWorkspace(
    machine: machine,
    voice: voice,
    jogGate: jogGate
  )

  await workspace.beginBoundaryTeaching(.xPositive)
  #expect(workspace.boundaryTeachingState == .awaitingReady(.xPositive))
  #expect(await voice.signalCount == 1)

  await voice.yield(
    VoiceTranscript(
      utteranceID: UUID(),
      sequence: 1,
      text: "ready",
      isFinal: true,
      monotonicNanoseconds: 1
    )
  )
  while workspace.boundaryTeachingState != .moving(.xPositive) { await Task.yield() }
  #expect(await voice.signalCount == 2)
  await jogGate.open()
  while await machine.jogRequests.isEmpty { await Task.yield() }
  while workspace.boundaryTeachingState != .idle { await Task.yield() }

  let request = try #require(await machine.jogRequests.only)
  #expect(request.delta.dx == 300)
  #expect(request.delta.dy == 0)
  #expect(request.feedMMPerMinute == 100)
  #expect(workspace.boundaryPositions.isEmpty)
  await workspace.stopVoiceListening()
}

@Test("Partial STOP during boundary motion cancels once and records only its final side")
@MainActor
func boundaryStopIsDeduplicatedAndRecordsCancelledPosition() async throws {
  let jogGate = AsyncGate()
  let finalPosition = try MachinePosition(x: 3.25, y: 0)
  let machine = MachineFixture(
    outcomes: [.cancelled(finalPosition: finalPosition)],
    cancelOutcomes: [.transmitted]
  )
  let voice = VoiceFixture()
  let workspace = await preparedBoundaryWorkspace(
    machine: machine,
    voice: voice,
    jogGate: jogGate
  )
  await workspace.beginBoundaryTeaching(.xPositive)
  await voice.yield(
    VoiceTranscript(
      utteranceID: UUID(),
      sequence: 1,
      text: "ready",
      isFinal: true,
      monotonicNanoseconds: 1
    )
  )
  while workspace.boundaryTeachingState != .moving(.xPositive) { await Task.yield() }

  let stopUtterance = UUID()
  await voice.yield(
    VoiceTranscript(
      utteranceID: stopUtterance,
      sequence: 2,
      text: "stop",
      isFinal: false,
      monotonicNanoseconds: 2
    )
  )
  while await machine.cancelRequestCount == 0 { await Task.yield() }
  await voice.yield(
    VoiceTranscript(
      utteranceID: stopUtterance,
      sequence: 3,
      text: "stop",
      isFinal: true,
      monotonicNanoseconds: 3
    )
  )
  for _ in 0..<20 { await Task.yield() }
  #expect(await machine.cancelRequestCount == 1)

  await jogGate.open()
  while workspace.boundaryTeachingState != .idle { await Task.yield() }

  #expect(await machine.jogRequests.count == 1)
  #expect(workspace.boundaryPositions == [.xPositive: finalPosition])
  #expect(workspace.boundaryPositionText(for: .xPositive) == "X 3.250 Y 0.000")
  #expect(workspace.boundaryPositionText(for: .xNegative) == "not measured")
  await workspace.stopVoiceListening()
}

@Test("Natural boundary jog completion records no side")
@MainActor
func completedBoundaryJogDoesNotManufactureBoundary() async throws {
  let machine = MachineFixture(
    outcomes: [.acceptedThenCompleted(finalPosition: try MachinePosition(x: 5, y: 0))]
  )
  let voice = VoiceFixture()
  let workspace = await preparedBoundaryWorkspace(machine: machine, voice: voice)
  await workspace.beginBoundaryTeaching(.xPositive)

  await voice.yield(
    VoiceTranscript(
      utteranceID: UUID(),
      sequence: 1,
      text: "ready",
      isFinal: true,
      monotonicNanoseconds: 1
    )
  )
  while await machine.jogRequests.isEmpty { await Task.yield() }
  while workspace.boundaryTeachingState != .idle { await Task.yield() }

  #expect(workspace.boundaryPositions.isEmpty)
  #expect(workspace.boundaryTeachingResultText.contains("No boundary was recorded"))
  await workspace.stopVoiceListening()
}

@Test("Speech failure during boundary motion fails closed through Jog Cancel")
@MainActor
func boundarySpeechFailureRequestsJogCancel() async throws {
  let jogGate = AsyncGate()
  let finalPosition = try MachinePosition(x: 2, y: 0)
  let machine = MachineFixture(
    outcomes: [.cancelled(finalPosition: finalPosition)],
    cancelOutcomes: [.transmitted]
  )
  let voice = VoiceFixture()
  let workspace = await preparedBoundaryWorkspace(
    machine: machine,
    voice: voice,
    jogGate: jogGate
  )
  await workspace.beginBoundaryTeaching(.xPositive)
  await voice.yield(
    VoiceTranscript(
      utteranceID: UUID(),
      sequence: 1,
      text: "ready",
      isFinal: true,
      monotonicNanoseconds: 1
    )
  )
  while workspace.boundaryTeachingState != .moving(.xPositive) { await Task.yield() }

  await voice.failListening(.recognition("microphone input ended"))
  while await machine.cancelRequestCount == 0 { await Task.yield() }

  #expect(workspace.boundaryTeachingState == .cancelling(.xPositive))
  #expect(await machine.cancelRequestCount == 1)
  await jogGate.open()
  while workspace.boundaryTeachingState != .idle { await Task.yield() }
  #expect(workspace.boundaryPositions == [.xPositive: finalPosition])
  await workspace.stopVoiceListening()
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
  await workspace.establishMachineSession(device)

  #expect(
    workspace.penUnavailableReason(for: .raise)
      == PenRefusal.motionGuardInactive.actionableDescription
  )

  await connectAndActivateMotion(workspace)
  await workspace.requestPenActuation(.raise)
  #expect(await fixture.penRequests == [.raise])
  #expect(workspace.penStateText == "commanded up — not visually observed")
  #expect(workspace.lastPenOutcomeText.contains("acknowledged"))

  #expect(workspace.penUnavailableReason(for: .lower) == nil)
  await workspace.requestPenActuation(.lower)
  #expect(await fixture.penRequests == [.raise, .lower])
  #expect(workspace.penStateText == "commanded down — not visually observed")
}

@Test("Controller link, motor-power uncertainty, motion permission, and pen evidence stay distinct")
@MainActor
func truthfulControllerAndMotionProjection() async {
  let fixture = MachineFixture()
  let device = testDevice()
  let workspace = OperatorWorkspace(
    machineActions: machineActions(fixture),
    serialDevices: [device],
    loadSelectedSerialIdentifier: { nil },
    persistSelectedSerialIdentifier: { _ in }
  )

  #expect(workspace.controllerConnectionText == "not selected")
  #expect(workspace.motorPowerText == "unverified")
  #expect(workspace.motionPermissionText == "blocked")
  #expect(workspace.controllerConnectionActionTitle == "Connect")
  #expect(
    workspace.workbenchStatusText
      == "Select the remembered controller and press Connect."
  )
  #expect(!workspace.workbenchStatusNeedsAttention)
  #expect(workspace.penStateText == "unknown — no physical pose assumed")

  await workspace.selectSerialDevice(device)
  #expect(workspace.controllerConnectionText == "not connected")
  #expect(!workspace.controllerIsConnected)

  await workspace.connectSelectedController()
  #expect(workspace.controllerConnectionText == "connected")
  #expect(workspace.controllerIsConnected)
  #expect(workspace.controllerStateText == "idle")
  #expect(workspace.motorPowerText == "not reported by controller")
  #expect(workspace.motionPermissionText == "blocked")
  #expect(!workspace.motionGuardIsActive)
  #expect(workspace.controllerConnectionActionTitle == "Disconnect")

  await connectAndActivateMotion(workspace)
  #expect(workspace.motionGuardIsActive)
  #expect(!workspace.motionGuardAllowsCarriageMotion)
  await workspace.requestPenActuation(.raise)
  #expect(workspace.motionPermissionText == "request eligible")
  #expect(workspace.motionGuardAllowsCarriageMotion)
  #expect(
    workspace.workbenchStatusText
      == "Motion Guard active; carriage motion is available."
  )
  #expect(!workspace.workbenchStatusNeedsAttention)
  #expect(workspace.penStateText == "commanded up — not visually observed")
}

@Test("Controller connection action toggles between connect and disconnect")
@MainActor
func controllerConnectionActionToggles() async {
  let fixture = MachineFixture()
  let device = testDevice()
  let workspace = OperatorWorkspace(
    machineActions: machineActions(fixture),
    serialDevices: [device],
    loadSelectedSerialIdentifier: { nil },
    persistSelectedSerialIdentifier: { _ in }
  )
  await workspace.selectSerialDevice(device)

  #expect(workspace.controllerConnectionActionTitle == "Connect")
  #expect(workspace.controllerConnectionActionUnavailableReason == nil)

  await workspace.performControllerConnectionAction()

  #expect(workspace.controllerIsConnected)
  #expect(workspace.controllerConnectionActionTitle == "Disconnect")
  #expect(workspace.controllerConnectionActionUnavailableReason == nil)

  await workspace.performControllerConnectionAction()

  #expect(await fixture.disconnectCount == 1)
  #expect(workspace.selectedSerialDevice == device)
  #expect(!workspace.controllerIsConnected)
  #expect(workspace.controllerConnectionActionTitle == "Connect")
  #expect(workspace.controllerConnectionActionUnavailableReason == nil)
}

@Test("Motion panel control activates and deactivates the session guard")
@MainActor
func motionGuardControlToggles() async {
  let fixture = MachineFixture()
  let device = testDevice()
  let workspace = OperatorWorkspace(
    machineActions: machineActions(fixture),
    serialDevices: [device]
  )
  await workspace.establishMachineSession(device)
  await workspace.connectSelectedController()

  #expect(workspace.motionGuardControlTitle == "Activate Motion Guard")
  #expect(workspace.motionGuardControlUnavailableReason == nil)

  await workspace.performMotionGuardControlAction()

  #expect(workspace.motionGuardIsActive)
  #expect(workspace.motionGuardControlTitle == "Deactivate Motion Guard")
  #expect(workspace.motionGuardControlUnavailableReason == nil)

  await workspace.performMotionGuardControlAction()

  #expect(await fixture.guardDeactivationCount == 1)
  #expect(!workspace.motionGuardIsActive)
  #expect(workspace.motionGuardControlTitle == "Activate Motion Guard")
  #expect(
    workspace.motionUnavailableReason
      == MotionRefusal.motionGuardInactive.actionableDescription
  )
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
  await workspace.establishMachineSession(device)
  await connectAndActivateMotion(workspace)
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
    await workspace.establishMachineSession(device)
    await connectAndActivateMotion(workspace)
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
  await workspace.establishMachineSession(device)
  await workspace.requestPassiveProbe()
  await connectAndActivateMotion(workspace)
  await workspace.requestPenActuation(.raise)

  await workspace.refreshSerialDevices()

  #expect(await fixture.disconnectCount == 1)
  #expect(workspace.serialDevices.isEmpty)
  #expect(workspace.selectedSerialDevice == nil)
  #expect(workspace.machineSnapshot == nil)
  #expect(workspace.passiveProbeResult == nil)
  #expect(!workspace.motionGuardIsActive)
  #expect(workspace.penStateText == "unknown — no physical pose assumed")
}

@Test("Disconnect preserves the device choice but requires fresh guard and pen state")
@MainActor
func disconnectAndReselectRequireFreshAuthority() async {
  let fixture = MachineFixture()
  let device = testDevice()
  let workspace = OperatorWorkspace(
    machineActions: machineActions(fixture),
    serialDevices: [device]
  )
  await workspace.establishMachineSession(device)
  await connectAndActivateMotion(workspace)
  await workspace.requestPenActuation(.raise)
  #expect(workspace.motionUnavailableReason == nil)

  await workspace.disconnectMachineSession()

  #expect(await fixture.disconnectCount == 1)
  #expect(workspace.selectedSerialDevice == device)
  #expect(workspace.machineSnapshot == nil)
  #expect(workspace.passiveProbeResult == nil)
  #expect(!workspace.motionGuardIsActive)
  #expect(workspace.penStateText == "unknown — no physical pose assumed")

  await workspace.establishMachineSession(device)
  #expect(workspace.selectedSerialDevice?.identifier == device.identifier)
  #expect(workspace.passiveProbeResult == nil)
  #expect(!workspace.motionGuardIsActive)
  #expect(workspace.penStateText == "unknown — no physical pose assumed")
  #expect(workspace.motionUnavailableReason == MotionRefusal.notConnected.actionableDescription)
  await workspace.requestJog(.xPositive)
  #expect(await fixture.jogRequests.isEmpty)

  await workspace.requestPassiveProbe()
  #expect(
    workspace.motionUnavailableReason
      == MotionRefusal.motionGuardInactive.actionableDescription
  )

  await connectAndActivateMotion(workspace)
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
  await workspace.establishMachineSession(device)
  await workspace.requestPassiveProbe()
  await connectAndActivateMotion(workspace)
  await workspace.requestPenActuation(.raise)
  await workspace.startCamera()

  await workspace.shutdown()
  await workspace.shutdown()

  #expect(await camera.stopCount == 1)
  #expect(await machine.disconnectCount == 1)
  #expect(workspace.selectedSerialDevice == nil)
  #expect(workspace.machineSnapshot == nil)
  #expect(workspace.passiveProbeResult == nil)
  #expect(!workspace.motionGuardIsActive)
  #expect(workspace.penStateText == "unknown — no physical pose assumed")
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

  let selectTask = Task { await workspace.establishMachineSession(device) }
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
  await workspace.establishMachineSession(device)
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
  await workspace.establishMachineSession(device)

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

  await workspace.establishMachineSession(device)

  #expect(workspace.controllerStateText == "hold")
  #expect(workspace.machinePositionText == "X 12.500   Y -3.250")
  #expect(workspace.currentOperationText == "relative jog")
  #expect(workspace.lastMotionOutcomeText.contains("ambiguous"))
  #expect(workspace.actionableError?.contains("Hold") == true)
  #expect(workspace.workbenchStatusNeedsAttention)
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

@Test("Camera live status requires a running capture and a current live frame")
@MainActor
func cameraLiveStatusRequiresRunningLiveFrame() async throws {
  let cameraID = CameraDeviceID(rawValue: "camera")
  let liveFrame = try testDisplayedFrame(
    source: .live(cameraID),
    captureNanoseconds: 1_500_000_000
  )
  let camera = CameraFixture(
    snapshot: CameraCaptureSnapshot(
      devices: [CameraDevice(id: cameraID, name: "Camera")],
      selectedDeviceID: cameraID,
      state: .running,
      latestFrame: liveFrame,
      error: nil
    ),
    simulated: try testDisplayedFrame(source: .simulated)
  )
  let workspace = OperatorWorkspace(
    cameraActions: cameraActions(camera),
    nowNanoseconds: { 2_000_000_000 }
  )

  await workspace.startCamera()
  #expect(workspace.cameraIsLive)

  await camera.setSnapshot(
    CameraCaptureSnapshot(
      devices: [CameraDevice(id: cameraID, name: "Camera")],
      selectedDeviceID: cameraID,
      state: .ready,
      latestFrame: liveFrame,
      error: nil
    )
  )
  await workspace.discoverCameras()
  #expect(!workspace.cameraIsLive)

  workspace.stopObserving()

  let noFrameCamera = CameraFixture(
    snapshot: CameraCaptureSnapshot(
      devices: [CameraDevice(id: cameraID, name: "Camera")],
      selectedDeviceID: cameraID,
      state: .running,
      latestFrame: nil,
      error: nil
    ),
    simulated: try testDisplayedFrame(source: .simulated)
  )
  let noFrameWorkspace = OperatorWorkspace(
    cameraActions: cameraActions(noFrameCamera),
    nowNanoseconds: { 2_000_000_000 }
  )
  await noFrameWorkspace.startCamera()
  #expect(!noFrameWorkspace.cameraIsLive)
  noFrameWorkspace.stopObserving()
}

@Test("Automatic analysis does not age out a healthy live camera behind its displayed result")
@MainActor
func cameraLiveStatusUsesCaptureHeartbeatDuringAutomaticAnalysis() async throws {
  let cameraID = CameraDeviceID(rawValue: "camera")
  let analyzedFrame = try testDisplayedFrame(
    source: .live(cameraID),
    captureNanoseconds: 1_000_000_000
  )
  let camera = CameraFixture(
    snapshot: CameraCaptureSnapshot(
      devices: [CameraDevice(id: cameraID, name: "Camera")],
      selectedDeviceID: cameraID,
      state: .running,
      latestFrame: analyzedFrame,
      error: nil
    ),
    simulated: try testDisplayedFrame(source: .simulated)
  )
  let workspace = OperatorWorkspace(
    cameraActions: cameraActions(camera),
    nowNanoseconds: { 3_000_000_000 }
  )

  await workspace.startCamera()
  await workspace.setAutomaticVisionAnalysis(true)
  #expect(!workspace.cameraIsLive)

  let currentCapture = try testDisplayedFrame(
    source: .live(cameraID),
    captureNanoseconds: 2_500_000_000
  )
  await camera.setSnapshot(
    CameraCaptureSnapshot(
      devices: [CameraDevice(id: cameraID, name: "Camera")],
      selectedDeviceID: cameraID,
      state: .running,
      latestFrame: currentCapture,
      error: nil
    )
  )
  await workspace.refreshCurrentState()

  #expect(workspace.displayedFrame == analyzedFrame)
  #expect(workspace.latestLiveCameraFrame == currentCapture)
  #expect(workspace.cameraIsLive)
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

@Test("simulator preflight rehearsal completes without microphone controller or readiness authority")
@MainActor
func simulatorPreflightRehearsalIsPresentationOnly() async throws {
  let machine = MachineFixture()
  let voice = VoiceFixture()
  let simulatedFrame = try testDisplayedFrame(source: .simulated)
  let camera = CameraFixture(
    snapshot: CameraCaptureSnapshot(
      devices: [],
      selectedDeviceID: nil,
      state: .stopped,
      latestFrame: nil,
      error: nil
    ),
    simulated: simulatedFrame
  )
  let workspace = OperatorWorkspace(
    machineActions: machineActions(machine),
    cameraActions: cameraActions(camera),
    voiceActions: voiceActions(voice),
    preflightRehearsalStepDelayNanoseconds: 0
  )

  await workspace.switchFrameMode(.simulated)
  await workspace.startPreflightRehearsal(.boundaryNegativeX)
  for _ in 0..<2_000 {
    if workspace.preflightRehearsals[.boundaryNegativeX]?.state == .completed { break }
    await Task.yield()
  }

  let rehearsal = try #require(workspace.preflightRehearsals[.boundaryNegativeX])
  #expect(rehearsal.state == .completed)
  #expect(rehearsal.completedStepCount == rehearsal.definition.steps.count)
  #expect(workspace.preflightTransactions.isEmpty)
  #expect(!workspace.preflightTrainingReadiness.isReady)
  #expect(await voice.startCount == 0)
  #expect(await voice.authorizationRequestCount == 0)
  #expect(await machine.totalInvocationCount == 0)
  #expect(workspace.preflightRehearsalStatusText.contains("no physical evidence"))
}

@Test("simulator voice practice pauses for exact phrases without gaining physical authority")
@MainActor
func simulatorVoicePracticeUsesMicrophoneWithoutPhysicalAuthority() async throws {
  let machine = MachineFixture()
  let voice = VoiceFixture()
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
    cameraActions: cameraActions(camera),
    voiceActions: voiceActions(voice),
    preflightRehearsalStepDelayNanoseconds: 0
  )

  await workspace.switchFrameMode(.simulated)
  await workspace.setSimulatorVoicePracticeEnabled(true)
  await workspace.startPreflightRehearsal(.boundaryPositiveX)
  for _ in 0..<2_000 {
    if workspace.preflightRehearsals[.boundaryPositiveX]?.voiceContext?.expectedResponse
      == .ready
    { break }
    await Task.yield()
  }

  let awaitingReadyCount = try #require(
    workspace.preflightRehearsals[.boundaryPositiveX]?.completedStepCount
  )
  #expect(workspace.voiceListening)
  #expect(await voice.authorizationRequestCount == 1)
  #expect(await voice.startCount == 1)

  await voice.yield(
    VoiceTranscript(
      utteranceID: UUID(),
      sequence: 1,
      text: "READY AND STOP",
      isFinal: true,
      monotonicNanoseconds: 1
    )
  )
  for _ in 0..<20 { await Task.yield() }
  #expect(
    workspace.preflightRehearsals[.boundaryPositiveX]?.completedStepCount
      == awaitingReadyCount
  )

  await voice.yield(
    VoiceTranscript(
      utteranceID: UUID(),
      sequence: 2,
      text: "READY",
      isFinal: true,
      monotonicNanoseconds: 2
    )
  )
  for _ in 0..<2_000 {
    if workspace.preflightRehearsals[.boundaryPositiveX]?.voiceContext?.expectedResponse
      == .stop
    { break }
    await Task.yield()
  }
  #expect(
    workspace.preflightRehearsals[.boundaryPositiveX]?.voiceContext?.expectedResponse
      == .stop
  )

  await voice.yield(
    VoiceTranscript(
      utteranceID: UUID(),
      sequence: 3,
      text: "STOP",
      isFinal: false,
      monotonicNanoseconds: 3
    )
  )
  for _ in 0..<2_000 {
    if workspace.preflightRehearsals[.boundaryPositiveX]?.state == .completed { break }
    await Task.yield()
  }

  #expect(workspace.preflightRehearsals[.boundaryPositiveX]?.state == .completed)
  #expect(await voice.stopCount == 1)
  #expect(!workspace.voiceListening)
  #expect(workspace.preflightTransactions.isEmpty)
  #expect(workspace.drawingFramePosterior == nil)
  #expect(!workspace.preflightTrainingReadiness.isReady)
  #expect(await machine.totalInvocationCount == 0)
}

@Test("disabling simulator voice practice cancels listening and stale speech is inert")
@MainActor
func disablingSimulatorVoicePracticeTearsDownTransaction() async throws {
  let voice = VoiceFixture()
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
    cameraActions: cameraActions(camera),
    voiceActions: voiceActions(voice),
    preflightRehearsalStepDelayNanoseconds: 0
  )

  await workspace.switchFrameMode(.simulated)
  await workspace.setSimulatorVoicePracticeEnabled(true)
  await workspace.startPreflightRehearsal(.penUpConfirmation)
  for _ in 0..<2_000 {
    if workspace.preflightRehearsals[.penUpConfirmation]?.voiceContext != nil { break }
    await Task.yield()
  }
  #expect(workspace.voiceListening)

  await workspace.setSimulatorVoicePracticeEnabled(false)
  let cancelledCount = try #require(
    workspace.preflightRehearsals[.penUpConfirmation]?.completedStepCount
  )
  await voice.yield(
    VoiceTranscript(
      utteranceID: UUID(),
      sequence: 1,
      text: "PEN IS PHYSICALLY UP",
      isFinal: true,
      monotonicNanoseconds: 1
    )
  )
  for _ in 0..<20 { await Task.yield() }

  #expect(!workspace.simulatorVoicePracticeEnabled)
  #expect(!workspace.voiceListening)
  #expect(await voice.stopCount == 1)
  #expect(workspace.preflightRehearsals[.penUpConfirmation]?.state == .cancelled)
  #expect(
    workspace.preflightRehearsals[.penUpConfirmation]?.completedStepCount
      == cancelledCount
  )
  #expect(workspace.preflightTransactions.isEmpty)
}

@Test("failed simulator variant preserves the rendered simulator and selected model")
@MainActor
func simulatorVariantFailureIsAtomic() async throws {
  let simulatedFrame = try testDisplayedFrame(source: .simulated)
  let camera = CameraFixture(
    snapshot: CameraCaptureSnapshot(
      devices: [],
      selectedDeviceID: nil,
      state: .stopped,
      latestFrame: nil,
      error: nil
    ),
    simulated: simulatedFrame,
    failingSimulatorModes: [.trained]
  )
  let workspace = OperatorWorkspace(cameraActions: cameraActions(camera))

  await workspace.switchFrameMode(.simulated)
  let originalFrameID = workspace.displayedFrame?.frame.id
  await workspace.selectSimulatorModelMode(.trained)

  #expect(workspace.frameMode == .simulated)
  #expect(workspace.simulatorModelMode == .prior)
  #expect(workspace.displayedFrame?.frame.id == originalFrameID)
  #expect(workspace.cameraError?.contains("simulated content failed") == true)
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

@Test("Fresh-frame polling never substitutes the currently stale value")
func freshFramePollingWaitsForAValueNewerThanTheBoundary() async throws {
  let attempts = FreshValueFixture(values: [nil, nil, 41])

  let value = try await boundedlyAwaitNewestCameraValue(
    maximumAttempts: 3,
    pollIntervalNanoseconds: 0,
    load: { await attempts.next() }
  )

  #expect(value == 41)
  #expect(await attempts.loadCount == 3)
}

private enum FixtureMachineFailure: Error, Equatable, Sendable {
  case select
  case probe
}

private actor MachineFixture {
  private(set) var snapshot: RunInterpreterSnapshot
  private var outcomes: [MotionOutcome]
  private(set) var jogRequests: [RelativeJogRequest] = []
  private(set) var observedJogRequests: [PhysicalJogObservationRequest] = []
  private(set) var probeCount = 0
  private(set) var selectCount = 0
  private(set) var selectedDescriptors: [MachineLinkDescriptor] = []
  private(set) var penRequests: [PenCommand] = []
  private(set) var cancelRequestCount = 0
  private(set) var guardActivationCount = 0
  private(set) var guardDeactivationCount = 0
  private(set) var disconnectCount = 0
  private var cancelOutcomes: [JogCancelOutcome]
  private let failure: FixtureMachineFailure?

  init(
    snapshot: RunInterpreterSnapshot = testRunSnapshot(),
    outcomes: [MotionOutcome] = [],
    cancelOutcomes: [JogCancelOutcome] = [],
    failure: FixtureMachineFailure? = nil
  ) {
    self.snapshot = snapshot
    self.outcomes = outcomes
    self.cancelOutcomes = cancelOutcomes
    self.failure = failure
  }

  var totalInvocationCount: Int {
    selectCount + probeCount + guardActivationCount + guardDeactivationCount + disconnectCount
      + jogRequests.count
      + observedJogRequests.count
      + penRequests.count + cancelRequestCount
  }

  func select(_ descriptor: MachineLinkDescriptor) throws -> RunInterpreterSnapshot {
    selectCount += 1
    selectedDescriptors.append(descriptor)
    if failure == .select { throw FixtureMachineFailure.select }
    return snapshot
  }

  func probe() throws -> PassiveProbeResult {
    probeCount += 1
    if failure == .probe { throw FixtureMachineFailure.probe }
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

  func cancelJog() -> JogCancelOutcome {
    cancelRequestCount += 1
    let outcome = cancelOutcomes.isEmpty
      ? .refused(.noActiveJog)
      : cancelOutcomes.removeFirst()
    snapshot = RunInterpreterSnapshot(
      currentOperation: snapshot.currentOperation,
      machine: snapshot.machine,
      lastMotionOutcome: snapshot.lastMotionOutcome,
      lastPhysicalJogObservationOutcome: snapshot.lastPhysicalJogObservationOutcome,
      lastPenOutcome: snapshot.lastPenOutcome,
      lastProbe: snapshot.lastProbe,
      jogCancellationInFlight: false,
      lastJogCancelOutcome: outcome
    )
    return outcome
  }

  func activateMotionGuard() -> MotionGuardActivationOutcome {
    guardActivationCount += 1
    snapshot = RunInterpreterSnapshot(
      currentOperation: snapshot.currentOperation,
      machine: replacing(snapshot.machine, motionGuardState: .active),
      lastMotionOutcome: snapshot.lastMotionOutcome,
      lastPhysicalJogObservationOutcome: snapshot.lastPhysicalJogObservationOutcome,
      lastPenOutcome: snapshot.lastPenOutcome,
      lastProbe: snapshot.lastProbe
    )
    return .activated
  }

  func deactivateMotionGuard() {
    guardDeactivationCount += 1
    snapshot = RunInterpreterSnapshot(
      currentOperation: snapshot.currentOperation,
      machine: replacing(snapshot.machine, motionGuardState: .inactive),
      lastMotionOutcome: snapshot.lastMotionOutcome,
      lastPhysicalJogObservationOutcome: snapshot.lastPhysicalJogObservationOutcome,
      lastPenOutcome: snapshot.lastPenOutcome,
      lastProbe: snapshot.lastProbe
    )
  }

  func beginJog(_ request: RelativeJogRequest) {
    let machine = snapshot.machine
    snapshot = RunInterpreterSnapshot(
      currentOperation: .relativeJog(request),
      machine: MachineSnapshot(
        connection: .moving,
        link: machine.link,
        lastProbe: machine.lastProbe,
        blockers: machine.blockers,
        controllerState: machine.controllerState,
        position: machine.position,
        pins: machine.pins,
        penState: machine.penState,
        motionGuardState: machine.motionGuardState,
        stickyAmbiguity: machine.stickyAmbiguity,
        operationInFlight: true,
        lastMotionOutcome: machine.lastMotionOutcome,
        lastPenOutcome: machine.lastPenOutcome
      ),
      lastMotionOutcome: snapshot.lastMotionOutcome,
      lastPhysicalJogObservationOutcome: snapshot.lastPhysicalJogObservationOutcome,
      lastPenOutcome: snapshot.lastPenOutcome,
      lastProbe: snapshot.lastProbe
    )
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
      machine: replacing(
        snapshot.machine,
        connection: .connected,
        operationInFlight: false,
        outcome: outcome
      ),
      lastMotionOutcome: outcome,
      lastProbe: snapshot.lastProbe
    )
    return outcome
  }

  func observedJog(
    _ request: PhysicalJogObservationRequest,
    observe: @Sendable (PhysicalObservationPhase, UInt64) async
      -> Result<VisibleToolFrameObservation, PhysicalJogObservationFailure>
  ) async -> PhysicalJogObservationOutcome {
    observedJogRequests.append(request)
    let sampleIndex = observedJogRequests.count - 1
    let startControllerSampleNanoseconds = UInt64(sampleIndex * 200 + 100)
    let finalControllerSampleNanoseconds = UInt64(sampleIndex * 200 + 200)
    let before: VisibleToolFrameObservation
    switch await observe(.beforeMotion, 0) {
    case .success(let observation): before = observation
    case .failure(let failure):
      let outcome = PhysicalJogObservationOutcome.notRecorded(
        motionOutcome: nil,
        failure: failure
      )
      replaceObservationOutcome(outcome)
      return outcome
    }

    let startPosition = snapshot.machine.position ?? (try! MachinePosition(x: 0, y: 0))
    let motionOutcome = outcomes.isEmpty
      ? .acceptedThenCompleted(finalPosition: startPosition)
      : outcomes.removeFirst()
    snapshot = RunInterpreterSnapshot(
      currentOperation: .idle,
      machine: replacing(snapshot.machine, outcome: motionOutcome),
      lastMotionOutcome: motionOutcome,
      lastPhysicalJogObservationOutcome: snapshot.lastPhysicalJogObservationOutcome,
      lastPenOutcome: snapshot.lastPenOutcome,
      lastProbe: snapshot.lastProbe
    )
    guard case .acceptedThenCompleted(let finalPosition) = motionOutcome else {
      let outcome = PhysicalJogObservationOutcome.notRecorded(
        motionOutcome: motionOutcome,
        failure: .motionNotCompleted(motionOutcome)
      )
      replaceObservationOutcome(outcome)
      return outcome
    }

    let after: VisibleToolFrameObservation
    switch await observe(.afterMotion, finalControllerSampleNanoseconds) {
    case .success(let observation): after = observation
    case .failure(let failure):
      let outcome = PhysicalJogObservationOutcome.notRecorded(
        motionOutcome: motionOutcome,
        failure: failure
      )
      replaceObservationOutcome(outcome)
      return outcome
    }

    let outcome = PhysicalJogObservationOutcome.resolve(
      motionOutcome: motionOutcome,
      observation: try PhysicalJogObservation(
        observationID: "app-test-observation-\(observedJogRequests.count)",
        request: request,
        startPosition: startPosition,
        startControllerSampleNanoseconds: startControllerSampleNanoseconds,
        finalPosition: finalPosition,
        finalControllerSampleNanoseconds: finalControllerSampleNanoseconds,
        before: before,
        after: after
      )
    )
    replaceObservationOutcome(outcome)
    return outcome
  }

  private func replaceObservationOutcome(_ outcome: PhysicalJogObservationOutcome) {
    snapshot = RunInterpreterSnapshot(
      currentOperation: .idle,
      machine: snapshot.machine,
      lastMotionOutcome: snapshot.lastMotionOutcome,
      lastPhysicalJogObservationOutcome: outcome,
      lastPenOutcome: snapshot.lastPenOutcome,
      lastProbe: snapshot.lastProbe
    )
  }

  func disconnect() {
    disconnectCount += 1
    snapshot = testRunSnapshot(
      connection: .disconnected,
      state: nil,
      position: nil,
      pen: .unknown
    )
  }

  private func replaceMachine(pen: PenState? = nil) {
    snapshot = RunInterpreterSnapshot(
      currentOperation: snapshot.currentOperation,
      machine: replacing(
        snapshot.machine,
        pen: pen ?? snapshot.machine.penState
      ),
      lastMotionOutcome: snapshot.lastMotionOutcome,
      lastProbe: snapshot.lastProbe
    )
  }
}

private func machineActions(
  _ fixture: MachineFixture,
  selectGate: AsyncGate? = nil,
  probeGate: AsyncGate? = nil,
  jogGate: AsyncGate? = nil,
  cancelGate: AsyncGate? = nil
) -> OperatorWorkspace.MachineActions {
  OperatorWorkspace.MachineActions(
    select: { descriptor in
      await selectGate?.wait()
      return try await fixture.select(descriptor)
    },
    snapshot: { await fixture.snapshot },
    requestPassiveProbe: {
      await probeGate?.wait()
      return try await fixture.probe()
    },
    activateMotionGuard: { await fixture.activateMotionGuard() },
    deactivateMotionGuard: { await fixture.deactivateMotionGuard() },
    requestRelativeJog: { request in
      await fixture.beginJog(request)
      await jogGate?.wait()
      return await fixture.jog(request)
    },
    requestObservedJog: { request, observe in
      await fixture.observedJog(request, observe: observe)
    },
    requestPenActuation: { command in await fixture.actuatePen(command) },
    requestJogCancel: {
      await cancelGate?.wait()
      return await fixture.cancelJog()
    },
    disconnect: { await fixture.disconnect() }
  )
}

private actor VoiceFixture {
  private var continuation: AsyncStream<VoiceTranscript>.Continuation?
  private(set) var streamSubscriberCount = 0
  private(set) var authorizationRequestCount = 0
  private(set) var startCount = 0
  private(set) var stopCount = 0
  private(set) var spoken: [String] = []
  private(set) var signalCount = 0
  private let authorization: VoiceAuthorizationState
  private let authorizationGate: AsyncGate?
  private let startupGate: AsyncGate?
  private var isListening = false
  private var listeningError: VoiceInteractionError?

  init(
    authorization: VoiceAuthorizationState = .authorized,
    authorizationGate: AsyncGate? = nil,
    startupGate: AsyncGate? = nil
  ) {
    self.authorization = authorization
    self.authorizationGate = authorizationGate
    self.startupGate = startupGate
  }

  var isCurrentlyListening: Bool { isListening }

  func requestAuthorization() async -> VoiceAuthorizationState {
    authorizationRequestCount += 1
    await authorizationGate?.wait()
    return authorization
  }

  func startListening() async {
    startCount += 1
    isListening = authorization == .authorized
    await startupGate?.wait()
  }

  func stopListening() {
    stopCount += 1
    isListening = false
    continuation?.finish()
    continuation = nil
  }

  func failListening(_ error: VoiceInteractionError) {
    listeningError = error
    isListening = false
  }

  func transcripts() -> AsyncStream<VoiceTranscript> {
    let pair = AsyncStream.makeStream(
      of: VoiceTranscript.self,
      bufferingPolicy: .bufferingNewest(1)
    )
    continuation = pair.continuation
    streamSubscriberCount += 1
    return pair.stream
  }

  func yield(_ transcript: VoiceTranscript) {
    continuation?.yield(transcript)
  }

  func snapshot() -> VoiceInteractionSnapshot {
    let state: VoiceListeningState
    if let listeningError {
      state = .failed(listeningError)
    } else {
      state = isListening ? .listening : .stopped
    }
    return VoiceInteractionSnapshot(
      authorization: authorization,
      listeningState: state,
      recognitionPolicy: .onDeviceRequired,
      latestTranscript: nil
    )
  }

  func speak(_ text: String) {
    spoken.append(text)
  }

  func signal() {
    signalCount += 1
  }
}

private func voiceActions(_ fixture: VoiceFixture) -> OperatorWorkspace.VoiceActions {
  OperatorWorkspace.VoiceActions(
    requestAuthorization: { await fixture.requestAuthorization() },
    startListening: { await fixture.startListening() },
    stopListening: { await fixture.stopListening() },
    snapshot: { await fixture.snapshot() },
    transcripts: { await fixture.transcripts() },
    speak: { text in await fixture.speak(text) },
    stopSpeaking: {},
    signal: { await fixture.signal() }
  )
}

private enum CameraFixtureError: Error, LocalizedError {
  case simulatedContentFailed

  var errorDescription: String? { "simulated content failed" }
}

private actor CameraFixture {
  private var current: CameraCaptureSnapshot
  private let simulated: DisplayedFrame
  private let failingSimulatorModes: Set<SimulatorModelMode>
  private(set) var simulatorCount = 0
  private(set) var simulatorModes: [SimulatorModelMode] = []
  private(set) var startCount = 0
  private(set) var restartCount = 0
  private(set) var stopCount = 0
  private(set) var framesCount = 0
  private(set) var selectedIDs: [CameraDeviceID] = []
  private(set) var automaticCadences: [VisionAnalysisCadence?] = []
  private(set) var visibleToolObservationCount = 0
  private(set) var visibleToolObservationBoundaries: [(PhysicalObservationPhase, UInt64)] = []
  private(set) var sceneInspectionBoundaries: [UInt64] = []
  private var visibleToolResults:
    [Result<VisibleToolFrameObservation, PhysicalJogObservationFailure>]
  private var sceneInspections: [LiveSceneInspection?]

  init(
    snapshot: CameraCaptureSnapshot,
    simulated: DisplayedFrame,
    visibleToolResults: [Result<VisibleToolFrameObservation, PhysicalJogObservationFailure>] = [],
    sceneInspections: [LiveSceneInspection?] = [],
    failingSimulatorModes: Set<SimulatorModelMode> = []
  ) {
    current = snapshot
    self.simulated = simulated
    self.failingSimulatorModes = failingSimulatorModes
    self.visibleToolResults = visibleToolResults
    self.sceneInspections = sceneInspections
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
  func restart() -> CameraCaptureSnapshot {
    restartCount += 1
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
  func simulatedContent(_ mode: SimulatorModelMode) throws -> SimulatedActionSurfaceContent {
    simulatorCount += 1
    simulatorModes.append(mode)
    if failingSimulatorModes.contains(mode) {
      throw CameraFixtureError.simulatedContentFailed
    }
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
  func observeVisibleTool(
    phase: PhysicalObservationPhase,
    newerThanNanoseconds: UInt64
  ) -> Result<VisibleToolFrameObservation, PhysicalJogObservationFailure> {
    visibleToolObservationCount += 1
    visibleToolObservationBoundaries.append((phase, newerThanNanoseconds))
    if !visibleToolResults.isEmpty { return visibleToolResults.removeFirst() }
    return .failure(.frameUnavailable(phase))
  }
  func inspectScene(newerThanNanoseconds boundary: UInt64) -> LiveSceneInspection? {
    sceneInspectionBoundaries.append(boundary)
    guard !sceneInspections.isEmpty else { return nil }
    return sceneInspections.removeFirst()
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
    restart: { await fixture.restart() },
    snapshot: { await fixture.snapshot() },
    frames: { await fixture.frames() },
    inspectScene: { boundary in
      await fixture.inspectScene(newerThanNanoseconds: boundary)
    },
    captureSnapshot: { "/tmp/adaptiveplotter-test-snapshot" },
    setAutomaticInspection: { cadence in await fixture.setAutomaticInspection(cadence) },
    analysisUpdates: { AsyncStream { $0.finish() } },
    observeVisibleTool: { phase, boundary in
      await fixture.observeVisibleTool(
        phase: phase,
        newerThanNanoseconds: boundary
      )
    },
    simulatedContent: { mode in try await fixture.simulatedContent(mode) }
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

private actor FreshValueFixture<Value: Sendable> {
  private var values: [Value?]
  private(set) var loadCount = 0

  init(values: [Value?]) {
    self.values = values
  }

  func next() -> Value? {
    loadCount += 1
    guard !values.isEmpty else { return nil }
    return values.removeFirst()
  }
}

private final class SynchronousStringRecorder: @unchecked Sendable {
  private let lock = NSLock()
  private var storage: [String] = []

  var values: [String] {
    lock.withLock { storage }
  }

  func append(_ value: String) {
    lock.withLock { storage.append(value) }
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
  motionGuardState: MotionGuardState = .inactive,
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
      motionGuardState: motionGuardState,
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
  connection: MachineConnectionState? = nil,
  pen: PenState? = nil,
  motionGuardState: MotionGuardState? = nil,
  operationInFlight: Bool? = nil,
  outcome: MotionOutcome? = nil
) -> MachineSnapshot {
  MachineSnapshot(
    connection: connection ?? machine.connection,
    link: machine.link,
    lastProbe: machine.lastProbe,
    blockers: machine.blockers,
    controllerState: machine.controllerState,
    position: machine.position,
    pins: machine.pins,
    penState: pen ?? machine.penState,
    motionGuardState: motionGuardState ?? machine.motionGuardState,
    stickyAmbiguity: machine.stickyAmbiguity,
    operationInFlight: operationInFlight ?? machine.operationInFlight,
    lastMotionOutcome: outcome ?? machine.lastMotionOutcome
  )
}

@MainActor
private func connectAndActivateMotion(_ workspace: OperatorWorkspace) async {
  if !workspace.controllerIsConnected {
    await workspace.connectSelectedController()
  }
  await workspace.activateMotionGuard()
}

@MainActor
private func preparedBoundaryWorkspace(
  machine: MachineFixture,
  voice: VoiceFixture,
  jogGate: AsyncGate? = nil,
  cancelGate: AsyncGate? = nil
) async -> OperatorWorkspace {
  let device = testDevice()
  let workspace = OperatorWorkspace(
    machineActions: machineActions(
      machine,
      jogGate: jogGate,
      cancelGate: cancelGate
    ),
    voiceActions: voiceActions(voice),
    serialDevices: [device],
    loadSelectedSerialIdentifier: { nil },
    persistSelectedSerialIdentifier: { _ in }
  )
  await workspace.selectSerialDevice(device)
  await workspace.connectSelectedController()
  await connectAndActivateMotion(workspace)
  await workspace.requestPenActuation(.raise)
  await workspace.startVoiceListening()
  while await voice.streamSubscriberCount == 0 { await Task.yield() }
  return workspace
}

@MainActor
private func observationWorkspace(
  configuration: CameraConfigurationID,
  observations: [Result<VisibleToolFrameObservation, PhysicalJogObservationFailure>],
  outcomes: [MotionOutcome]
) async throws -> (
  workspace: OperatorWorkspace,
  machine: MachineFixture,
  camera: CameraFixture
) {
  let liveFrame = try testDisplayedFrame(configuration: configuration)
  let camera = CameraFixture(
    snapshot: CameraCaptureSnapshot(
      devices: [CameraDevice(id: CameraDeviceID(rawValue: "camera"), name: "Camera")],
      selectedDeviceID: CameraDeviceID(rawValue: "camera"),
      state: .running,
      latestFrame: liveFrame,
      error: nil
    ),
    simulated: try testDisplayedFrame(source: .simulated),
    visibleToolResults: observations
  )
  let machine = MachineFixture(outcomes: outcomes)
  let device = testDevice()
  let workspace = OperatorWorkspace(
    machineActions: machineActions(machine),
    cameraActions: cameraActions(camera),
    serialDevices: [device]
  )
  await workspace.establishMachineSession(device)
  await connectAndActivateMotion(workspace)
  await workspace.requestPenActuation(.raise)
  await workspace.startCamera()
  workspace.setRecordJogObservations(true)
  return (workspace, machine, camera)
}

private func responseObservations(
  configuration: CameraConfigurationID,
  deltas: [(x: Int, y: Int)]
) async throws -> [Result<VisibleToolFrameObservation, PhysicalJogObservationFailure>] {
  var results: [Result<VisibleToolFrameObservation, PhysicalJogObservationFailure>] = []
  for (index, delta) in deltas.enumerated() {
    let beforeTime = UInt64(index * 200 + 100)
    let afterTime = beforeTime + 101
    results.append(
      .success(
        try await testVisibleToolObservation(
          phase: .beforeMotion,
          captureNanoseconds: beforeTime,
          capOriginX: 36,
          capOriginY: 30,
          configuration: configuration
        )
      )
    )
    results.append(
      .success(
        try await testVisibleToolObservation(
          phase: .afterMotion,
          captureNanoseconds: afterTime,
          capOriginX: 36 + delta.x,
          capOriginY: 30 + delta.y,
          configuration: configuration
        )
      )
    )
  }
  return results
}

private func testCameraConfiguration(_ suffix: UInt64) -> CameraConfigurationID {
  CameraConfigurationID(
    UUID(
      uuidString: String(
        format: "00000000-0000-0000-0000-%012llx",
        suffix
      )
    )!
  )
}

private func testDisplayedFrame(
  source: FrameSourceIdentity = .live(CameraDeviceID(rawValue: "camera")),
  captureNanoseconds: UInt64 = 1,
  configuration: CameraConfigurationID = CameraConfigurationID()
) throws -> DisplayedFrame {
  DisplayedFrame(
    source: source,
    frame: try StampedFrame(
      sequence: 1,
      captureNanoseconds: captureNanoseconds,
      cameraConfigurationID: configuration,
      width: 2,
      height: 2,
      rowBytes: 8,
      pixelFormat: .bgra8,
      bytes: OwnedFrameBytes(Array(repeating: 255, count: 16))
    )
  )
}

private func testSceneMeasurement(
  for displayedFrame: DisplayedFrame,
  cap: GreenCapMeasurement? = nil,
  drawingFrame: DrawingFrameEstimate? = nil
) -> PlotterSceneMeasurement {
  let frame = displayedFrame.frame
  return PlotterSceneMeasurement(
    frameID: frame.id,
    frameSHA256: frame.contentSHA256,
    cameraConfigurationID: frame.cameraConfigurationID,
    greenComponentCount: 0,
    cap: cap,
    topFrameSide: nil,
    rightFrameSide: nil,
    drawingFrame: drawingFrame,
    armature: nil,
    overlays: [],
    algorithmRevision: "app-preflight-test-v1",
    diagnosticSHA256: frame.contentSHA256
  )
}

private func testGreenCapMeasurement() throws -> GreenCapMeasurement {
  GreenCapMeasurement(
    pixelCount: 4,
    boundingBox: PixelRect(x: 0, y: 0, width: 1, height: 1),
    centroid: try Point2(x: 0.5, y: -0.25),
    confidence: 0.9
  )
}

private func testDrawingFrameEstimate() throws -> DrawingFrameEstimate {
  let points: [Point2<CameraPixelSpace>] = [
    try Point2(x: 0, y: 0),
    try Point2(x: 1, y: 0),
    try Point2(x: 1, y: 1),
    try Point2(x: 0, y: 1),
    try Point2(x: 0, y: 0),
  ]
  return DrawingFrameEstimate(
    geometry: try Polyline(points: points),
    confidence: 0.8,
    basis: "exact-frame app integration fixture"
  )
}

private func testVisibleToolObservation(
  phase: PhysicalObservationPhase,
  captureNanoseconds: UInt64,
  capOriginX: Int,
  capOriginY: Int,
  configuration: CameraConfigurationID = CameraConfigurationID(
    UUID(uuidString: "00000000-0000-0000-0000-000000000123")!
  )
) async throws -> VisibleToolFrameObservation {
  let width = 100
  let height = 100
  let rowBytes = width * 4
  var bytes = [UInt8](repeating: 255, count: rowBytes * height)
  for y in capOriginY..<(capOriginY + 6) {
    for x in capOriginX..<(capOriginX + 6) {
      let offset = y * rowBytes + x * 4
      bytes[offset] = 0
      bytes[offset + 1] = 180
      bytes[offset + 2] = 0
      bytes[offset + 3] = 255
    }
  }
  let displayedFrame = DisplayedFrame(
    source: .live(CameraDeviceID(rawValue: "camera")),
    frame: try StampedFrame(
      sequence: captureNanoseconds,
      captureNanoseconds: captureNanoseconds,
      cameraConfigurationID: configuration,
      width: width,
      height: height,
      rowBytes: rowBytes,
      pixelFormat: .bgra8,
      bytes: OwnedFrameBytes(bytes)
    )
  )
  let measurement = try await VisionWorker().inspectPlotterScene(in: displayedFrame.frame)
  return try VisibleToolFrameObservation(
    phase: phase,
    displayedFrame: displayedFrame,
    measurement: measurement
  )
}

extension Array {
  fileprivate var only: Element? { count == 1 ? self[0] : nil }
}
