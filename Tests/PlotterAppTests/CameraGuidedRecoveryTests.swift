import Foundation
import PlotterEpisodeModel
import PlotterEpisodeRuntime
import PlotterRuntime
import PlotterUI
import Testing

@testable import PlotterApp

@MainActor
@Suite("Camera guided recovery through rendered requests")
struct CameraGuidedRecoveryTests {
  @Test("SIMULATED Camera return uses accepted Boundary authority without a LIVE checkpoint")
  func simulatedAcceptedCenterReturn() async throws {
    let harness = makeCausalSimulatorAppFixture()
    let workspace = harness.workspace
    try await completeSimulatedPenInteractionPrerequisite(workspace)
    try await installAcceptedBoundaryTestProjection(runtime: harness.boundaryRuntime,
      workspace: workspace, environment: .simulated)
    let prior = try #require((await harness.boundaryRuntime.snapshot(for: .simulated)).acceptedMachineArtifacts)
    let center = try #require(prior.centerArrivalPosition)
    let graph = workspace.learningArtifactGraph.revisions
    await workspace.submitManualMotionIntent(.jog(try PlotterJogRequest(
      direction: .negativeY, distanceMM: 24, feedMMPerMinute: 300, routing: .relativeTravel)))
    #expect((await harness.simulator.snapshot()).mpos.yMM == center.point.y - 24)
    let camera = LearningPathItemID.humanGuidedDiscovery(.calibrateCameraAndVisibleCap)
    try await send(.cameraCalibration(.returnToAcceptedCenter), owner: camera, workspace: workspace)
    let arrived = await harness.simulator.snapshot()
    #expect(arrived.mpos.xMM == center.point.x)
    #expect(arrived.mpos.yMM == center.point.y)
    #expect((await harness.boundaryRuntime.snapshot(for: .simulated)).acceptedMachineArtifacts == prior)
    #expect(workspace.learningArtifactGraph.revisions == graph)
    let marker = try #require(workspace.penCapAppearanceSelection?.markerReference)
    let capture = try await workspace.captureCameraCalibrationReferenceEffect()
    let binding = try #require(PenCapReferenceBinding(markerReference: marker, frame: capture.frame,
      opticalConfiguration: marker.opticalConfiguration))
    let measured = try await VisionWorker().inspectPlotterScene(in: capture.frame.frame,
      requestedFeatures: [.penCap], markerReference: marker, referenceBinding: binding)
    let detected = try #require(measured.penCap.measurement)
    #expect(capture.capAnchor.point == detected.centroid)
    #expect(capture.capAnchor.point.y != Double(detected.boundingBox.y + detected.boundingBox.height))
    #expect(capture.capAnchor.estimatorRevision == marker.estimatorRevision)
    try await send(.cameraCalibration(.buildFivePositionProposal), owner: camera, workspace: workspace)
    #expect(workspace.proposedMachineCameraRegistration?.correspondenceProvenance.count == 5)
    #expect(await harness.simulator.persistentInk().isEmpty)
    await workspace.shutdown()
  }

  @Test("Camera Redo preserves fallback until replacement acceptance and abandons cancelled proposals")
  func cameraReplacementLifecycle() async throws {
    let harness = makeCausalSimulatorAppFixture()
    let workspace = harness.workspace
    try await completeSimulatedPenInteractionPrerequisite(workspace)
    try await installAcceptedBoundaryTestProjection(
      runtime: harness.boundaryRuntime, workspace: workspace, environment: .simulated)
    try await completeSimulatedTipCalibration(workspace, simulator: harness.simulator)
    let drawing = LearningPathItemID.borderValidation(.chooseDrawingBorderPlan)
    try await send(.start, owner: drawing, workspace: workspace)
    try #require(workspace.borderValidationSnapshot.assessment == .predictionObserved)
    let oldMap = try #require(workspace.machineCameraRegistration)
    let oldMapRevision = try #require(workspace.learningArtifactGraph.currentRevision(for: .machineCameraRegistration))
    let oldTip = try #require(workspace.tipCameraRegistration)
    let oldTipRevision = try #require(workspace.learningArtifactGraph.currentRevision(for: .tipCameraRegistration))
    let oldPlan = try #require(workspace.learningArtifactGraph.revisions.first {
      guard $0.state == .current else { return false }
      if case .linePlan = $0.kind { return true }
      return false
    })
    let retainedInk = await harness.simulator.persistentInk()
    let camera = LearningPathItemID.humanGuidedDiscovery(.calibrateCameraAndVisibleCap)
    let beforeRedo = await harness.simulator.snapshot()
    try await send(.redoThisStep, owner: camera, workspace: workspace)
    #expect((await harness.simulator.snapshot()).mpos == beforeRedo.mpos)
    #expect(workspace.proposedMachineCameraRegistration == nil)
    #expect(workspace.machineCameraRegistration == oldMap)

    try await send(.cameraCalibration(.buildFivePositionProposal), owner: camera, workspace: workspace)
    try #require(workspace.proposedMachineCameraRegistration != nil)
    try await send(.cameraCalibration(.rejectProposal), owner: camera, workspace: workspace)
    #expect(workspace.machineCameraRegistration == oldMap)
    #expect(workspace.tipCameraRegistration == oldTip)
    #expect(workspace.learningArtifactGraph.currentRevision(for: oldPlan.kind)?.id == oldPlan.id)

    try await send(.cameraCalibration(.buildFivePositionProposal), owner: camera, workspace: workspace)
    try #require(workspace.proposedMachineCameraRegistration != nil)
    try await send(.cancel, owner: camera, workspace: workspace)
    #expect(workspace.proposedMachineCameraRegistration == nil)
    #expect(workspace.machineCameraRegistration == oldMap)
    #expect(workspace.tipCameraRegistration == oldTip)
    try await send(.restart, owner: camera, workspace: workspace)
    #expect(workspace.proposedMachineCameraRegistration == nil)
    #expect(workspace.testPlotterUIProjection(selectedItemID: camera, includesLearningPath: true)
      .semantic.request(for: learningActionID(.cameraCalibration(.acceptProposal), owner: camera)) == nil)

    await harness.simulator.injectFault(.refuseNextOperation)
    try await send(.cameraCalibration(.buildFivePositionProposal), owner: camera,
      workspace: workspace, expectAccepted: false)
    #expect(workspace.proposedMachineCameraRegistration == nil)
    #expect(workspace.machineCameraRegistration == oldMap)
    #expect(workspace.tipCameraRegistration == oldTip)
    #expect(workspace.learningArtifactGraph.currentRevision(for: oldPlan.kind)?.id == oldPlan.id)
    #expect(await harness.simulator.persistentInk() == retainedInk)

    try await send(.cameraCalibration(.buildFivePositionProposal), owner: camera, workspace: workspace)
    let proposed = try #require(workspace.proposedMachineCameraRegistration)
    try await send(.cameraCalibration(.acceptProposal), owner: camera, workspace: workspace)
    #expect(workspace.machineCameraRegistration == proposed)
    #expect(workspace.learningArtifactGraph.currentRevision(for: .machineCameraRegistration)?.id != oldMapRevision.id)
    #expect(workspace.tipCameraRegistration == nil)
    #expect(workspace.learningArtifactGraph.currentRevision(for: .tipCameraRegistration) == nil)
    #expect(workspace.learningArtifactGraph.currentRevision(for: oldPlan.kind) == nil)
    #expect(workspace.learningArtifactGraph.revisions.contains { $0.id == oldTipRevision.id && $0.state != .current })
    #expect(workspace.learningArtifactGraph.revisions.contains { $0.id == oldPlan.id && $0.state != .current })
    #expect(workspace.borderValidationSnapshot.assessment == nil)
    #expect(workspace.borderValidationSnapshot.drawingBorderPlan == nil)
    #expect(await harness.simulator.persistentInk() == retainedInk)
    await workspace.shutdown()
  }

  private func send(_ action: PlotterLearningAction, owner: LearningPathItemID,
    workspace: PlotterApplicationRuntime, expectAccepted: Bool = true) async throws {
    let request = try #require(workspace.testPlotterUIProjection(
      selectedItemID: owner, includesLearningPath: true).semantic.request(
        for: learningActionID(action, owner: owner)))
    let disposition = await workspace.submitPlotterUIRequest(request)
    if expectAccepted {
      #expect(disposition == .accepted(requestID: request.id))
    } else if case .refused = disposition {
      // The injected lower refusal must propagate through the rendered request.
    } else {
      Issue.record("Expected the injected camera operation refusal")
    }
  }
}
