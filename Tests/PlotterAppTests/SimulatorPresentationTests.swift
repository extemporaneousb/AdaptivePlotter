import EpisodeCore
import Foundation
import PlotterEpisodeRuntime
import PlotterRuntime
import Testing

@testable import PlotterApp

@Test("SIMULATED overlay producer publishes exact typed causal status")
@MainActor
func simulatedOverlayStatusIsCausalAndExact() async throws {
  let harness = makeCausalSimulatorAppFixture()
  let workspace = harness.workspace
  await submitObservationConfigurationForTest(workspace, .selectSource(.simulated, nil))

  let frame = try #require(workspace.displayedFrame)
  let cap = workspace.overlayStatus(for: .penCap)
  let armature = workspace.overlayStatus(for: .armatureEnvelope)

  #expect(workspace.overlayPreferenceState.enabled.contains(.penCap))
  #expect(cap.state == .available)
  #expect(
    cap.message
      == OverlayStatusGrammar.simulatedPenCapAvailable(frame: frame.frame.sequence)
  )
  #expect(cap.provenance?.matches(frame) == true)
  #expect(cap.message.contains("pixel count and confidence are not applicable"))
  #expect(!cap.message.contains("Found —"))

  #expect(workspace.overlayPreferenceState.enabled.contains(.armatureEnvelope))
  #expect(armature.state == .available)
  #expect(
    armature.message
      == OverlayStatusGrammar.simulatedArmatureAvailable(frame: frame.frame.sequence)
  )
  #expect(armature.provenance?.matches(frame) == true)
  #expect(!armature.message.contains("independently detected"))

  let surface = workspace.testActionSurfacePresentation
  #expect(surface.analyzedOverlayFrame?.matches(frame) == true)
  #expect(surface.overlays.map(\.provenance.kind) == [.penCap, .armatureEstimate])

  await submitObservationConfigurationForTest(workspace, .setOverlay(.penCap, enabled: false))
  #expect(workspace.overlayStatus(for: .penCap).state == .off)
  #expect(workspace.overlayStatus(for: .armatureEnvelope) == armature)
  #expect(workspace.testActionSurfacePresentation.overlays.map(\.provenance.kind) == [.armatureEstimate])

  await submitObservationConfigurationForTest(workspace, .setOverlay(.penCap, enabled: true))
  #expect(workspace.overlayStatus(for: .penCap).message == cap.message)
  #expect(workspace.testActionSurfacePresentation.analyzedOverlayFrame?.matches(frame) == true)
  await workspace.shutdown()
}

@Test("SIMULATED manual controls create causal drawing segments while Pen Down")
@MainActor
func simulatedManualPenDownDrawing() async throws {
  let harness = makeCausalSimulatorAppFixture()
  let workspace = harness.workspace
  await submitObservationConfigurationForTest(workspace, .selectSource(.simulated, nil))
  await submitControllerSession(workspace, .toggleConnection)
  await submitControllerSession(workspace, .toggleMotionAuthorization)
  await workspace.submitTestManualPen(.lower)

  #expect(workspace.testManualMotionEpisodePresentation.jogControlsUnavailableReason == nil)
  #expect(workspace.testManualMotionEpisodePresentation.modeText
    == "drawing — commanded Pen Down")
  await workspace.submitTestManualJog(.xPositive)

  let snapshot = await harness.simulator.snapshot()
  #expect(snapshot.mpos.xMM == 50)
  #expect(snapshot.mpos.yMM == 0)
  #expect(snapshot.penPose == .down)
  #expect(snapshot.persistentInkSegmentCount == 1)
  #expect(snapshot.currentOperation == nil)
  #expect(snapshot.evidenceNotice == .notPhysicalEvidence)
  await workspace.shutdown()
}

@Test("SIMULATED camera Refresh preserves causal MPos and persistent ink")
@MainActor
func simulatedCameraRefreshUsesLearningRuntime() async throws {
  let runtime = SimulatedLearningRuntime()
  _ = try await runtime.connect().result.get()
  _ = try await runtime.enableMotion().result.get()
  let composition = PlotterManualMotionComposition.makeRuntimeComposition(
    journalFileURL: FileManager.default.temporaryDirectory.appendingPathComponent(
      "simulated-camera-refresh-\(UUID().uuidString).json"
    ),
    machineSession: nil,
    simulatedRuntime: runtime,
    simulatedExecutionPacing: SimulatedLearningInteractivePacing(stepDelay: .zero)
  )
  let adapter = composition.causalSimulatorEffectAdapter
  let owner = EpisodeAuthorityID(rawValue: "SimulatorPresentationTests.cameraRefresh")
  let lowered = await adapter.executeRetainedWorkflowPen(.down, owner: owner)
  #expect(lowered.effectResult == nil)
  #expect(lowered.refusal == nil)
  let admission = await adapter.admitRetainedWorkflowDrawing(
    delta: try SimulatedLearningMotionVector(dxMM: 2, dyMM: 0),
    owner: owner
  )
  guard case let .admitted(drawing) = admission else {
    Issue.record("Expected causal drawing admission")
    return
  }
  #expect(drawing.attribution == .retainedWorkflow(owner: owner))
  let outcome = await adapter.executeNaturally(drawing)
  #expect(outcome.disposition == .naturallyCompleted)
  #expect(outcome.effectResult == nil)
  let raised = await adapter.executeRetainedWorkflowPen(.up, owner: owner)
  #expect(raised.effectResult == nil)
  #expect(raised.refusal == nil)

  let workspace = PlotterApplicationRuntime(
    observationSession: CameraComposition.makeIsolatedObservationSessionForTesting(),
    manualMotionComposition: composition,
    penInteractionRuntime: nominalPenInteractionRuntime(
      manualMotionComposition: composition
    ),
    boundaryRuntime: nominalBoundaryRuntime(),
    drawingDraftRuntime: nominalDrawingDraftRuntime(),
    drawingRunComposition: nominalDrawingRunComposition(),
    incidentPackageUIService: nominalIncidentPackageUIService(),
    residualEffectPort: SimulatorPresentationResidualEffectPort(),
    serialDevices: [],
  )
  await submitObservationConfigurationForTest(workspace, .selectSource(.simulated, nil))
  let beforeFrame = try #require(workspace.displayedFrame?.frame)
  let beforeSnapshot = await runtime.snapshot()
  let beforeInk = await runtime.persistentInk()

  await submitObservationConfigurationForTest(workspace, .refresh)

  let afterFrame = try #require(workspace.displayedFrame?.frame)
  let afterSnapshot = await runtime.snapshot()
  #expect(afterFrame.id != beforeFrame.id)
  #expect(afterFrame.captureNanoseconds > beforeFrame.captureNanoseconds)
  #expect(afterSnapshot.mpos == beforeSnapshot.mpos)
  #expect(afterSnapshot.persistentInkSegmentCount == beforeSnapshot.persistentInkSegmentCount)
  #expect(await runtime.persistentInk() == beforeInk)
  #expect(workspace.displayedFrame?.source == .simulated)
}

private struct SimulatorPresentationResidualEffectPort: PlotterApplicationResidualEffectPort {
  let discovery = PlotterFixedSerialDeviceDiscoveryAdapter(devices: [])

  func discoverSerialDevices() -> [MachineLinkDescriptor] {
    discovery.discoverSerialDevices()
  }
}
