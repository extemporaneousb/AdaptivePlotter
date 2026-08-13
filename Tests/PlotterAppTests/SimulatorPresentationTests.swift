import PlotterRuntime
import Testing

@testable import PlotterApp

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
