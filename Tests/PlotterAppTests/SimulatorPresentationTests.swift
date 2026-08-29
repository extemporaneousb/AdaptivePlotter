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
  let harness = makeCausalSimulatorAppFixture()
  let workspace = harness.workspace
  await workspace.switchFrameMode(.simulated)
  await workspace.performControllerConnectionAction()
  await workspace.activateMotionGuard()
  await workspace.submitManualPen(.lower)

  #expect(workspace.manualMotionEpisodePresentation.jogControlsUnavailableReason == nil)
  #expect(workspace.manualMotionEpisodePresentation.modeText
    == "drawing — commanded Pen Down")
  await workspace.submitManualJog(.xPositive)

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
    machineActions: nil,
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

  let workspace = OperatorWorkspace(
    cameraActions: CameraComposition.makeIsolatedActionsForTesting(),
    manualMotionComposition: composition,
    drawingDraftRuntime: nominalDrawingDraftRuntime(),
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
