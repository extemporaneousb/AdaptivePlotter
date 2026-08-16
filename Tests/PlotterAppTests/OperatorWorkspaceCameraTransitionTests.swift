import Foundation
import PlotterModel
import PlotterRuntime
import Testing

@testable import PlotterApp

@MainActor
@Suite("Operator workspace camera transitions")
struct OperatorWorkspaceCameraTransitionTests {
  @Test("failed camera selection preserves viewport lock and current camera authority")
  func failedSelectionPreservesCommittedState() async throws {
    let log = EventLog()
    let machine = try MachineFixture(
      log: log,
      relativeJogSettlementOffset: Vector2(dx: 0, dy: 0)
    )
    let camera = try CameraFixture(frameWidth: 320, frameHeight: 240)
    let baseActions = cameraActions(camera, machinePositionFrom: machine)
    let actions = replacingCameraSelection(in: baseActions) { _ in
      throw CameraCaptureError.captureFailed("injected selection failure")
    }
    let workspace = workspace(
      machine: machine,
      cameraActionsOverride: actions,
      log: log
    )
    try await establishAcceptedLiveCameraAuthority(
      workspace: workspace,
      machine: machine
    )
    let accepted = try #require(workspace.machineCameraRegistration)
    let acceptedRevision = try #require(
      workspace.learningArtifactGraph.currentRevision(for: .machineCameraRegistration)
    )
    let displayed = try #require(workspace.displayedFrame)
    let viewport = try #require(workspace.actionSurfacePresentation.viewportContext)
    workspace.videoPresentationPreferences.synchronize(with: viewport)
    workspace.videoPresentationPreferences.setZoom(1)
    await workspace.lockVideoAnalysisToCurrentView(for: displayed)
    let lock = try #require(workspace.videoAnalysisRegionLock)
    let viewportBasis = workspace.videoPresentationPreferences.viewportBasis
    let zoom = workspace.videoPresentationPreferences.zoom
    let panOffsetX = workspace.videoPresentationPreferences.panOffsetX
    let panOffsetY = workspace.videoPresentationPreferences.panOffsetY
    let transformRevision = workspace.videoPresentationPreferences.presentationTransformRevision

    await workspace.selectCamera(CameraDeviceID(rawValue: "rejected-camera"))

    #expect(workspace.selectedCameraID == camera.device.id)
    #expect(workspace.displayedFrame == displayed)
    #expect(workspace.videoAnalysisRegionLock == lock)
    #expect(workspace.videoPresentationPreferences.viewportBasis == viewportBasis)
    #expect(workspace.videoPresentationPreferences.zoom == zoom)
    #expect(workspace.videoPresentationPreferences.panOffsetX == panOffsetX)
    #expect(workspace.videoPresentationPreferences.panOffsetY == panOffsetY)
    #expect(
      workspace.videoPresentationPreferences.presentationTransformRevision == transformRevision
    )
    #expect(workspace.machineCameraRegistration == accepted)
    #expect(
      workspace.learningArtifactGraph.currentRevision(for: .machineCameraRegistration)?.id
        == acceptedRevision.id
    )
    #expect(workspace.cameraError?.contains("injected selection failure") == true)
    await workspace.shutdown()
  }

  @Test("same-configuration restart preserves viewport but invalidates camera evidence")
  func sameConfigurationRestartSeparatesViewportFromAuthority() async throws {
    let log = EventLog()
    let machine = try MachineFixture(
      log: log,
      relativeJogSettlementOffset: Vector2(dx: 0, dy: 0)
    )
    let camera = try CameraFixture(frameWidth: 320, frameHeight: 240)
    let workspace = workspace(
      machine: machine,
      cameraActionsOverride: cameraActions(camera, machinePositionFrom: machine),
      log: log
    )
    try await establishAcceptedLiveCameraAuthority(
      workspace: workspace,
      machine: machine
    )
    #expect(workspace.machineCameraRegistration != nil)
    let displayed = try #require(workspace.displayedFrame)
    let viewport = try #require(workspace.actionSurfacePresentation.viewportContext)
    workspace.videoPresentationPreferences.synchronize(with: viewport)
    workspace.videoPresentationPreferences.setZoom(1)
    await workspace.lockVideoAnalysisToCurrentView(for: displayed)
    let lock = try #require(workspace.videoAnalysisRegionLock)
    let viewportBasis = workspace.videoPresentationPreferences.viewportBasis
    let zoom = workspace.videoPresentationPreferences.zoom
    let panOffsetX = workspace.videoPresentationPreferences.panOffsetX
    let panOffsetY = workspace.videoPresentationPreferences.panOffsetY
    let transformRevision = workspace.videoPresentationPreferences.presentationTransformRevision
    let boundaryRevision = workspace.learningArtifactGraph.currentRevision(
      for: .boundarySideAggregate(.negativeX)
    )?.id

    await workspace.restartCamera()

    #expect(workspace.videoAnalysisRegionLock == lock)
    #expect(workspace.videoPresentationPreferences.viewportBasis == viewportBasis)
    #expect(workspace.videoPresentationPreferences.zoom == zoom)
    #expect(workspace.videoPresentationPreferences.panOffsetX == panOffsetX)
    #expect(workspace.videoPresentationPreferences.panOffsetY == panOffsetY)
    #expect(
      workspace.videoPresentationPreferences.presentationTransformRevision == transformRevision
    )
    #expect(workspace.machineCameraRegistration == nil)
    #expect(
      workspace.learningArtifactGraph.currentRevision(for: .machineCameraRegistration) == nil
    )
    #expect(
      workspace.learningArtifactGraph.currentRevision(for: .boundarySideAggregate(.negativeX))?.id
        == boundaryRevision
    )
    await workspace.shutdown()
  }

  private func replacingCameraSelection(
    in actions: OperatorWorkspace.CameraActions,
    with select: @escaping @Sendable (CameraDeviceID) async throws -> CameraCaptureSnapshot
  ) -> OperatorWorkspace.CameraActions {
    OperatorWorkspace.CameraActions(
      discover: actions.discover,
      select: select,
      start: actions.start,
      stop: actions.stop,
      restart: actions.restart,
      snapshot: actions.snapshot,
      frames: actions.frames,
      inspectWorkflowScene: actions.inspectWorkflowScene,
      captureFrame: actions.captureFrame,
      setSceneAnalysisRegion: actions.setSceneAnalysisRegion,
      setPenCapColor: actions.setPenCapColor,
      setAutomaticInspection: actions.setAutomaticInspection,
      analysisUpdates: actions.analysisUpdates,
      observeIsolatedInk: actions.observeIsolatedInk
    )
  }

  private func establishAcceptedLiveCameraAuthority(
    workspace: OperatorWorkspace,
    machine: MachineFixture
  ) async throws {
    await workspace.establishMachineSession(machine.descriptor)
    await workspace.requestPassiveProbe()
    await workspace.startCamera()
    try await completePenInteraction(workspace)
    try await completeLiveBoundaries(workspace, machine: machine)
    let boundaryOwner = LearningPathItemID.humanGuidedDiscovery(
      .pairedBoundaryDiscoveryAndCentering
    )
    try await performPublicAction(
      .moveToEstimatedCenter,
      owner: boundaryOwner,
      workspace: workspace
    )
    let cameraOwner = LearningPathItemID.humanGuidedDiscovery(
      .calibrateCameraAndVisibleCap
    )
    try await performPublicAction(
      .runCameraCalibrationAndBuildProposal,
      owner: cameraOwner,
      workspace: workspace
    )
    try await performPublicAction(
      .acceptCameraCalibrationProposal,
      owner: cameraOwner,
      workspace: workspace
    )
  }
}
