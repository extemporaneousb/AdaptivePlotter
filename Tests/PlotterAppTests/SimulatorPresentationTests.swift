import PlotterRuntime
import Testing

@testable import PlotterApp

@Test("SIMULATED manual controls create causal drawing segments while Pen Down")
@MainActor
func simulatedManualPenDownDrawing() async throws {
  let harness = makeSimulatedHarness()
  let workspace = harness.workspace
  await workspace.switchFrameMode(.simulated)
  await workspace.performControllerConnectionAction()
  await workspace.activateMotionGuard()
  await workspace.requestPenActuation(.lower)

  #expect(workspace.motionUnavailableReason == nil)
  #expect(workspace.manualMotionModeText == "drawing — commanded Pen Down")
  await workspace.requestJog(.xPositive)

  let snapshot = await harness.runtime.snapshot()
  #expect(snapshot.mpos.xMM == 1)
  #expect(snapshot.mpos.yMM == 0)
  #expect(snapshot.penPose == .down)
  #expect(snapshot.persistentInkSegmentCount == 1)
  #expect(await harness.machineActionLog.values.isEmpty)
  await workspace.shutdown()
}

@Test("SIMULATED camera Refresh preserves causal MPos and persistent ink")
@MainActor
func simulatedCameraRefreshUsesLearningRuntime() async throws {
  let runtime = SimulatedLearningRuntime()
  _ = try await runtime.connect().result.get()
  _ = try await runtime.enableMotion().result.get()
  _ = try await runtime.setPenPose(.down).result.get()
  let drawing = try await runtime.beginDrawing(
    delta: SimulatedLearningMotionVector(dxMM: 2, dyMM: 0)
  ).result.get()
  _ = try await runtime.completeNaturally(drawing.id).result.get()
  _ = try await runtime.setPenPose(.up).result.get()

  let workspace = OperatorWorkspace(
    cameraActions: CameraComposition.makeIsolatedActionsForTesting(),
    simulatedLearningRuntime: runtime,
    serialDevices: [],
    serialDeviceDiscovery: { [] },
    loadSelectedSerialIdentifier: { nil },
    persistSelectedSerialIdentifier: { _ in }
  )
  await workspace.switchFrameMode(.simulated)
  let beforeFrame = try #require(workspace.displayedFrame?.frame)
  let beforeSnapshot = await runtime.snapshot()
  let beforeInk = await runtime.persistentInk()

  await workspace.refreshVideoSources()

  let afterFrame = try #require(workspace.displayedFrame?.frame)
  let afterSnapshot = await runtime.snapshot()
  #expect(afterFrame.id != beforeFrame.id)
  #expect(afterFrame.captureNanoseconds > beforeFrame.captureNanoseconds)
  #expect(afterSnapshot.mpos == beforeSnapshot.mpos)
  #expect(afterSnapshot.persistentInkSegmentCount == beforeSnapshot.persistentInkSegmentCount)
  #expect(await runtime.persistentInk() == beforeInk)
  #expect(workspace.displayedFrame?.source == .simulated)
}
