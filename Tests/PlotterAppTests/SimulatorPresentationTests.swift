import PlotterRuntime
import Testing

@testable import PlotterApp

@Test("SIMULATED overlay producer publishes exact typed causal status")
@MainActor
func simulatedOverlayStatusIsCausalAndExact() async throws {
  let harness = makeSimulatedHarness()
  let workspace = harness.workspace
  await workspace.switchFrameMode(.simulated)

  let frame = try #require(workspace.displayedFrame)
  let cap = workspace.overlayCardPresentation(for: .penCap)
  let armature = workspace.overlayCardPresentation(for: .armatureEnvelope)

  #expect(cap.isOn)
  #expect(cap.status.state == .available)
  #expect(
    cap.statusText
      == OverlayStatusGrammar.simulatedPenCapAvailable(frame: frame.frame.sequence)
  )
  #expect(cap.status.provenance?.matches(frame) == true)
  #expect(cap.accessibilityValue.contains(cap.statusText))
  #expect(cap.helpText.contains(cap.statusText))
  #expect(cap.statusText.contains("pixel count and confidence are not applicable"))
  #expect(!cap.statusText.contains("Found —"))

  #expect(armature.isOn)
  #expect(armature.status.state == .available)
  #expect(
    armature.statusText
      == OverlayStatusGrammar.simulatedArmatureAvailable(frame: frame.frame.sequence)
  )
  #expect(armature.status.provenance?.matches(frame) == true)
  #expect(armature.accessibilityValue.contains(armature.statusText))
  #expect(armature.helpText.contains(armature.statusText))
  #expect(!armature.statusText.contains("independently detected"))

  let surface = workspace.actionSurfacePresentation
  #expect(surface.analyzedOverlayFrame?.matches(frame) == true)
  #expect(surface.overlays.map(\.provenance.kind) == [.penCap, .armatureEstimate])

  workspace.setOverlay(.penCap, enabled: false)
  #expect(workspace.overlayCardPresentation(for: .penCap).status.state == .off)
  #expect(workspace.overlayCardPresentation(for: .armatureEnvelope).status == armature.status)
  #expect(workspace.actionSurfacePresentation.overlays.map(\.provenance.kind) == [.armatureEstimate])

  workspace.setOverlay(.penCap, enabled: true)
  #expect(workspace.overlayCardPresentation(for: .penCap).statusText == cap.statusText)
  #expect(workspace.actionSurfacePresentation.analyzedOverlayFrame?.matches(frame) == true)
  await workspace.shutdown()
}

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
  #expect(snapshot.mpos.xMM == 50)
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
