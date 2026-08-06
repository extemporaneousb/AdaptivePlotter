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
  await workspace.selectSerialDevice(device)
  await applyTestLimits(workspace)
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
  await workspace.selectSerialDevice(device)
  await applyTestLimits(workspace)
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
  await workspace.selectSerialDevice(device)
  await applyTestLimits(workspace)
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
  await workspace.selectSerialDevice(device)
  await applyTestLimits(workspace)
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
  await workspace.selectSerialDevice(device)
  await applyTestLimits(workspace)
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
  await workspace.selectSerialDevice(device)
  await applyTestLimits(workspace)
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

@Test("Voice jog routes one typed request through the existing bounded motion path")
@MainActor
func voiceJogRoutesTypedIntent() async throws {
  let voice = VoiceFixture()
  let machine = MachineFixture()
  let device = testDevice()
  let workspace = OperatorWorkspace(
    machineActions: machineActions(machine),
    voiceActions: voiceActions(voice),
    serialDevices: [device]
  )
  await workspace.selectSerialDevice(device)
  await applyTestLimits(workspace)
  await workspace.requestPenActuation(.raise)
  let request = RelativeJogRequest(
    delta: try Vector2(dx: -2.5, dy: 0),
    feedMMPerMinute: 75
  )

  await workspace.handleVoiceIntent(.relativeJog(request))

  #expect(await machine.jogRequests == [request])
  #expect(workspace.lastVoiceIntentText == "relative X -2.500 Y 0.000 at 75.0 mm/min")
  #expect(workspace.lastVoiceActionableResultText == "completed at X 0.000 Y 0.000")
  #expect(workspace.lastSpokenFeedbackText.contains("Request completed."))
  #expect(await voice.spoken.count == 1)
}

@Test("Voice pen-down text has no accepted app intent or machine path")
@MainActor
func voiceCannotRoutePenDown() async throws {
  let defaults = try OperatorVoiceSessionDefaults(
    xStepMM: 1,
    yStepMM: 1,
    feedMMPerMinute: 50
  )
  let parsed = OperatorVoiceCommandParser.parse("pen down", defaults: defaults)
  let machine = MachineFixture()
  let workspace = OperatorWorkspace(machineActions: machineActions(machine))

  #expect(parsed == .rejected(.penDownNotAvailable))
  #expect(parsed.acceptedIntent == nil)
  #expect(await machine.penRequests.isEmpty)
  #expect(workspace.lastVoiceIntentText == "none")
}

@Test("Voice motion is blocked in simulator before reaching MachineActions")
@MainActor
func simulatorBlocksVoiceMotion() async throws {
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
  await workspace.selectSerialDevice(device)
  await applyTestLimits(workspace)
  await workspace.switchFrameMode(.simulated)
  let request = RelativeJogRequest(
    delta: try Vector2(dx: 1, dy: 0),
    feedMMPerMinute: 50
  )

  await workspace.handleVoiceIntent(.relativeJog(request))

  #expect(await machine.jogRequests.isEmpty)
  #expect(
    workspace.lastVoiceActionableResultText
      == "refused: SIMULATED source cannot issue physical machine commands. Switch to LIVE first."
  )
}

@Test("Voice status reports one exact current blocker without requiring a camera")
@MainActor
func voiceStatusProjectsExactBlocker() async {
  let workspace = OperatorWorkspace()

  await workspace.handleVoiceIntent(.requestStatus)

  #expect(
    workspace.lastVoiceActionableResultText
      == "controller unknown · MPos unknown · operation none · motion blocked · blocker: Native machine composition is unavailable."
  )
  #expect(workspace.cameraSnapshot == nil)
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

@Test("A corrected voice refusal is immediately retryable")
@MainActor
func voiceRefusalCanRetry() async throws {
  let completed = MotionOutcome.acceptedThenCompleted(
    finalPosition: try MachinePosition(x: 1, y: 0)
  )
  let machine = MachineFixture(outcomes: [
    .refused(.feedExceedsMaximum(requested: 90, maximum: 80)),
    completed,
  ])
  let device = testDevice()
  let workspace = OperatorWorkspace(
    machineActions: machineActions(machine),
    serialDevices: [device]
  )
  await workspace.selectSerialDevice(device)
  await applyTestLimits(workspace)
  await workspace.requestPenActuation(.raise)
  let request = RelativeJogRequest(
    delta: try Vector2(dx: 1, dy: 0),
    feedMMPerMinute: 75
  )

  await workspace.handleVoiceIntent(.relativeJog(request))
  #expect(workspace.lastVoiceActionableResultText.contains("refused"))
  #expect(workspace.motionUnavailableReason == nil)

  await workspace.handleVoiceIntent(.relativeJog(request))
  #expect(await machine.jogRequests.count == 2)
  #expect(workspace.lastVoiceActionableResultText == "completed at X 1.000 Y 0.000")
}

@Test("Partial and final STOP for one utterance send one priority cancel")
@MainActor
func voicePriorityCancelIsDeduplicated() async {
  let machine = MachineFixture(cancelOutcomes: [.transmitted])
  let voice = VoiceFixture()
  let device = testDevice()
  let workspace = OperatorWorkspace(
    machineActions: machineActions(machine),
    voiceActions: voiceActions(voice),
    serialDevices: [device]
  )
  await workspace.selectSerialDevice(device)
  workspace.xStepText = "not-a-number"
  workspace.yStepText = ""
  workspace.feedText = "invalid"
  await workspace.startVoiceListening()
  while await voice.streamSubscriberCount == 0 { await Task.yield() }
  let utteranceID = UUID()

  await voice.yield(
    VoiceTranscript(
      utteranceID: utteranceID,
      sequence: 1,
      text: "stop",
      isFinal: false,
      monotonicNanoseconds: 1
    )
  )
  while await machine.cancelRequestCount == 0 { await Task.yield() }
  await voice.yield(
    VoiceTranscript(
      utteranceID: utteranceID,
      sequence: 2,
      text: "stop",
      isFinal: true,
      monotonicNanoseconds: 2
    )
  )
  for _ in 0..<20 { await Task.yield() }
  await voice.yield(
    VoiceTranscript(
      utteranceID: utteranceID,
      sequence: 3,
      text: "stop",
      isFinal: true,
      monotonicNanoseconds: 3
    )
  )
  for _ in 0..<20 { await Task.yield() }

  #expect(await machine.cancelRequestCount == 1)
  #expect(workspace.lastJogCancelOutcomeText.contains("cancel byte sent"))
  #expect(workspace.lastSpokenFeedbackText.contains("Interruption signal sent"))
  await workspace.stopVoiceListening()
}

@Test("Priority STOP bypasses a blocked normal voice jog without queueing another jog")
@MainActor
func voicePriorityCancelBypassesBlockedJog() async throws {
  let jogGate = AsyncGate()
  let finalPosition = try MachinePosition(x: 0.2, y: 0)
  let machine = MachineFixture(
    outcomes: [.cancelled(finalPosition: finalPosition)],
    cancelOutcomes: [.transmitted]
  )
  let voice = VoiceFixture()
  let device = testDevice()
  let workspace = OperatorWorkspace(
    machineActions: machineActions(machine, jogGate: jogGate),
    voiceActions: voiceActions(voice),
    serialDevices: [device]
  )
  await workspace.selectSerialDevice(device)
  await applyTestLimits(workspace)
  await workspace.requestPenActuation(.raise)
  await workspace.startVoiceListening()
  while await voice.streamSubscriberCount == 0 { await Task.yield() }

  await voice.yield(
    VoiceTranscript(
      utteranceID: UUID(),
      sequence: 1,
      text: "x plus",
      isFinal: true,
      monotonicNanoseconds: 1
    )
  )
  while await jogGate.waiterCount == 0 { await Task.yield() }

  await voice.yield(
    VoiceTranscript(
      utteranceID: UUID(),
      sequence: 2,
      text: "y plus",
      isFinal: true,
      monotonicNanoseconds: 2
    )
  )
  for _ in 0..<20 { await Task.yield() }
  await voice.yield(
    VoiceTranscript(
      utteranceID: UUID(),
      sequence: 3,
      text: "stop",
      isFinal: false,
      monotonicNanoseconds: 3
    )
  )
  while await machine.cancelRequestCount == 0 { await Task.yield() }

  #expect(await machine.jogRequests.isEmpty)
  #expect(await machine.cancelRequestCount == 1)
  await jogGate.open()
  while await machine.jogRequests.isEmpty { await Task.yield() }
  while workspace.jogRequestInProgress { await Task.yield() }

  #expect(await machine.jogRequests.count == 1)
  #expect(workspace.lastMotionOutcomeText == "cancelled at X 0.200 Y 0.000")
  await workspace.stopVoiceListening()
}

@Test("A final jog heard during priority cancel is discarded instead of delayed")
@MainActor
func voiceCancelDiscardsLaterNormalIntent() async {
  let cancelGate = AsyncGate()
  let machine = MachineFixture(cancelOutcomes: [.transmitted])
  let voice = VoiceFixture()
  let device = testDevice()
  let workspace = OperatorWorkspace(
    machineActions: machineActions(machine, cancelGate: cancelGate),
    voiceActions: voiceActions(voice),
    serialDevices: [device]
  )
  await workspace.selectSerialDevice(device)
  await applyTestLimits(workspace)
  await workspace.requestPenActuation(.raise)
  await workspace.startVoiceListening()
  while await voice.streamSubscriberCount == 0 { await Task.yield() }

  await voice.yield(
    VoiceTranscript(
      utteranceID: UUID(),
      sequence: 1,
      text: "stop",
      isFinal: false,
      monotonicNanoseconds: 1
    )
  )
  while await cancelGate.waiterCount == 0 { await Task.yield() }
  await voice.yield(
    VoiceTranscript(
      utteranceID: UUID(),
      sequence: 2,
      text: "x plus",
      isFinal: true,
      monotonicNanoseconds: 2
    )
  )
  while workspace.lastVoiceIntentText != "relative X 1.000 Y 0.000 at 100.0 mm/min" {
    await Task.yield()
  }

  await cancelGate.open()
  while await machine.cancelRequestCount == 0 { await Task.yield() }
  for _ in 0..<20 { await Task.yield() }

  #expect(await machine.jogRequests.isEmpty)
  #expect(await machine.cancelRequestCount == 1)
  await workspace.stopVoiceListening()
}

@Test("Invalid jog fields do not block status or pen up and spoken feedback is command-free")
@MainActor
func nonmotionVoiceIntentsIgnoreJogDefaults() async throws {
  let machine = MachineFixture()
  let voice = VoiceFixture()
  let device = testDevice()
  let workspace = OperatorWorkspace(
    machineActions: machineActions(machine),
    voiceActions: voiceActions(voice),
    serialDevices: [device]
  )
  await workspace.selectSerialDevice(device)
  workspace.xStepText = "bad-x"
  workspace.yStepText = "bad-y"
  workspace.feedText = "bad-feed"
  await workspace.startVoiceListening()
  while await voice.streamSubscriberCount == 0 { await Task.yield() }

  await voice.yield(
    VoiceTranscript(
      utteranceID: UUID(),
      sequence: 1,
      text: "status",
      isFinal: true,
      monotonicNanoseconds: 1
    )
  )
  while workspace.lastVoiceIntentText != "report current facts" { await Task.yield() }
  for _ in 0..<20 { await Task.yield() }

  await voice.yield(
    VoiceTranscript(
      utteranceID: UUID(),
      sequence: 2,
      text: "pen up",
      isFinal: true,
      monotonicNanoseconds: 2
    )
  )
  while await machine.penRequests.isEmpty { await Task.yield() }
  for _ in 0..<20 { await Task.yield() }

  await voice.yield(
    VoiceTranscript(
      utteranceID: UUID(),
      sequence: 3,
      text: "x plus",
      isFinal: true,
      monotonicNanoseconds: 3
    )
  )
  while !workspace.lastVoiceActionableResultText.contains("Enter positive numeric") {
    await Task.yield()
  }
  await voice.yield(
    VoiceTranscript(
      utteranceID: UUID(),
      sequence: 4,
      text: "pen down",
      isFinal: true,
      monotonicNanoseconds: 4
    )
  )
  while await voice.spoken.count < 4 { await Task.yield() }

  #expect(await machine.penRequests == [.raise])
  #expect(await machine.jogRequests.isEmpty)
  let defaults = try OperatorVoiceSessionDefaults(
    xStepMM: 1,
    yStepMM: 1,
    feedMMPerMinute: 100
  )
  for spoken in await voice.spoken {
    #expect(OperatorVoiceCommandParser.parsePriority(spoken) == nil)
    #expect(OperatorVoiceCommandParser.parse(spoken, defaults: defaults).acceptedIntent == nil)
  }
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
  await workspace.selectSerialDevice(device)

  #expect(workspace.penUnavailableReason(for: .raise) == nil)
  #expect(
    workspace.penUnavailableReason(for: .lower)
      == PenRefusal.motionLimitsMissing.actionableDescription
  )

  await workspace.requestPenActuation(.raise)
  #expect(await fixture.penRequests == [.raise])
  #expect(workspace.penStateText == "commanded up — not visually observed")
  #expect(workspace.lastPenOutcomeText.contains("acknowledged"))

  await applyTestLimits(workspace)
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
    serialDevices: [device]
  )

  #expect(workspace.controllerConnectionText == "not selected")
  #expect(workspace.motorPowerText == "unverified")
  #expect(workspace.motionPermissionText == "blocked")
  #expect(workspace.controllerConnectionActionTitle == "Connect & Inspect Controller")
  #expect(
    workspace.workbenchStatusText
      == "Motion blocked: Select and connect one serial device."
  )
  #expect(workspace.workbenchStatusNeedsAttention)
  #expect(workspace.penStateText == "unknown — no physical pose assumed")

  await workspace.selectSerialDevice(device)
  #expect(workspace.controllerConnectionText == "last inspection responsive")
  #expect(workspace.controllerStateText == "idle")
  #expect(workspace.motorPowerText == "not reported by controller")
  #expect(workspace.motionPermissionText == "blocked")
  #expect(workspace.controllerConnectionActionTitle == "Refresh Controller State")

  await applyTestLimits(workspace)
  await workspace.requestPenActuation(.raise)
  #expect(workspace.motionPermissionText == "request eligible")
  #expect(
    workspace.workbenchStatusText
      == "Motion request eligible; motor power is not reported by controller."
  )
  #expect(!workspace.workbenchStatusNeedsAttention)
  #expect(workspace.penStateText == "commanded up — not visually observed")
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
  #expect(workspace.penStateText == "unknown — no physical pose assumed")
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
  #expect(workspace.penStateText == "unknown — no physical pose assumed")
  #expect(workspace.minimumXText == "-100")

  await workspace.selectSerialDevice(device)
  #expect(workspace.selectedSerialDevice?.identifier == device.identifier)
  #expect(workspace.passiveProbeResult == nil)
  #expect(!workspace.limitsApplied)
  #expect(workspace.penStateText == "unknown — no physical pose assumed")
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

private actor MachineFixture {
  private(set) var snapshot: RunInterpreterSnapshot
  private var outcomes: [MotionOutcome]
  private(set) var jogRequests: [RelativeJogRequest] = []
  private(set) var observedJogRequests: [PhysicalJogObservationRequest] = []
  private(set) var probeCount = 0
  private(set) var selectCount = 0
  private(set) var penRequests: [PenCommand] = []
  private(set) var cancelRequestCount = 0
  private(set) var limitCount = 0
  private(set) var disconnectCount = 0
  private(set) var lastLimits: MotionLimits?
  private var cancelOutcomes: [JogCancelOutcome]

  init(
    snapshot: RunInterpreterSnapshot = testRunSnapshot(),
    outcomes: [MotionOutcome] = [],
    cancelOutcomes: [JogCancelOutcome] = []
  ) {
    self.snapshot = snapshot
    self.outcomes = outcomes
    self.cancelOutcomes = cancelOutcomes
  }

  var totalInvocationCount: Int {
    selectCount + probeCount + limitCount + disconnectCount + jogRequests.count
      + observedJogRequests.count
      + penRequests.count + cancelRequestCount
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
  probeGate: AsyncGate? = nil,
  jogGate: AsyncGate? = nil,
  cancelGate: AsyncGate? = nil
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
    requestRelativeJog: { request in
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
  private(set) var startCount = 0
  private(set) var stopCount = 0
  private(set) var spoken: [String] = []
  private let authorization: VoiceAuthorizationState
  private var isListening = false

  init(authorization: VoiceAuthorizationState = .authorized) {
    self.authorization = authorization
  }

  func requestAuthorization() -> VoiceAuthorizationState { authorization }

  func startListening() {
    startCount += 1
    isListening = authorization == .authorized
  }

  func stopListening() {
    stopCount += 1
    isListening = false
    continuation?.finish()
    continuation = nil
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
    VoiceInteractionSnapshot(
      authorization: authorization,
      listeningState: isListening ? .listening : .stopped,
      recognitionPolicy: .onDeviceRequired,
      latestTranscript: nil
    )
  }

  func speak(_ text: String) {
    spoken.append(text)
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
    stopSpeaking: {}
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
  private(set) var visibleToolObservationCount = 0
  private(set) var visibleToolObservationBoundaries: [(PhysicalObservationPhase, UInt64)] = []
  private var visibleToolResults:
    [Result<VisibleToolFrameObservation, PhysicalJogObservationFailure>]

  init(
    snapshot: CameraCaptureSnapshot,
    simulated: DisplayedFrame,
    visibleToolResults: [Result<VisibleToolFrameObservation, PhysicalJogObservationFailure>] = []
  ) {
    current = snapshot
    self.simulated = simulated
    self.visibleToolResults = visibleToolResults
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
  func observeVisibleTool(
    phase: PhysicalObservationPhase,
    newerThanNanoseconds: UInt64
  ) -> Result<VisibleToolFrameObservation, PhysicalJogObservationFailure> {
    visibleToolObservationCount += 1
    visibleToolObservationBoundaries.append((phase, newerThanNanoseconds))
    if !visibleToolResults.isEmpty { return visibleToolResults.removeFirst() }
    return .failure(.frameUnavailable(phase))
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
    observeVisibleTool: { phase, boundary in
      await fixture.observeVisibleTool(
        phase: phase,
        newerThanNanoseconds: boundary
      )
    },
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
  await workspace.selectSerialDevice(device)
  await applyTestLimits(workspace)
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
