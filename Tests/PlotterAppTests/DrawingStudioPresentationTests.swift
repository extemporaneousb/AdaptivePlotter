import Foundation
import PlotterEpisodeModel
import PlotterEpisodeRuntime
import PlotterModel
import PlotterRuntime
import PlotterUI
import Testing
import SwiftUI

@testable import PlotterApp

@Suite("Drawing Studio presentation")
struct DrawingStudioPresentationTests {
  @MainActor
  @Test("Drawing Studio raises the pen beside camera recovery and clears the prerequisite after retry")
  func adjacentRaisePenResolvesRecoveryPrerequisite() async throws {
    let f = try await DrawingWorkbenchApplicationFixture.make(verifyPhysicalPose: false)
    defer { f.stores.remove() }
    let app = f.application
    func currentView() -> DrawingStudioView<EmptyView> {
      DrawingStudioView(presentation: app.drawingStudioPresentation,
        plotterUIProjection: app.testPlotterUIProjection().semantic, plotterUIIntentSink: app)
    }
    await submitControllerSession(app, .toggleMotionAuthorization)
    let disabled = currentView()
    let disabledRaise = try #require(disabled.positionRaisePenButton)
    #expect(disabledRaise.request == nil)
    #expect(disabledRaise.unavailableReason?.contains("Enable Motion") == true)
    #expect(disabled.positionRecoveryButton?.request == nil)
    // The Learning recovery strip and Drawing Studio render this same component.
    let sharedControls = PositionPenPreparationControls(
      plotterUIProjection: app.testPlotterUIProjection().semantic, plotterUIIntentSink: app)
    #expect(sharedControls.raisePenButton?.request == disabledRaise.request)
    #expect(sharedControls.prerequisiteText == disabled.positionRecoveryButton?.unavailableReason)
    await f.machine.enqueuePenOutcome(.refused(.controllerRejected("fixture preparation failed")))
    let enable = try #require(app.testPlotterUIProjection().semantic.request(for: PlotterAppUIActionID.controllerMotion))
    _ = await app.submitPlotterUIRequest(enable)
    #expect(app.machineSnapshot?.machine.penState == .unknown)
    let failed = currentView()
    #expect(failed.positionRecoveryButton?.request == nil)
    let raise = try #require(failed.positionRaisePenButton)
    #expect(raise.title == "Raise Pen")
    let request = try #require(raise.request)
    #expect(request.actionID == PlotterAppUIActionID.manualPenUp)
    #expect(raise.unavailableReason == nil)
    #expect(await app.submitPlotterUIRequest(request) == .accepted(requestID: request.id))
    #expect(app.machineSnapshot?.machine.penState == .up)
    let ready = currentView()
    let recovery = try #require(ready.positionRecoveryButton)
    #expect(recovery.request != nil)
    #expect(recovery.unavailableReason == nil)
    #expect(await f.machine.requestedPenCommands == [.raise, .raise])
    #expect(await f.machine.requestedFeeds.isEmpty)
    #expect(await f.camera.poseCaptureCount == 0)
    #expect(app.controllerPoseApplicability.requiresPhysicalPositionForTest)
    let recoveryRequest = try #require(recovery.request)
    #expect(await app.submitPlotterUIRequest(recoveryRequest) == .accepted(requestID: recoveryRequest.id))
    #expect(!app.controllerPoseApplicability.requiresPhysicalPositionForTest)
    #expect(app.interactiveLearningIsComplete)
    #expect(currentView().positionRecoveryButton == nil)
    #expect(currentView().positionRaisePenButton == nil)
    await app.shutdown()
  }

  @MainActor
  @Test("camera recovery button presents its current owner blocker and clears it after settlement")
  func recoveryButtonUsesCurrentOwnerReason() async throws {
    let f = try await DrawingWorkbenchApplicationFixture.make(verifyPhysicalPose: false)
    defer { f.stores.remove() }
    let app = f.application
    let owner = LearningPathItemID.humanGuidedDiscovery(.calibratePenContactFromSparseMarks)
    func currentButton(_ phase: String) throws -> (button: OperatorRequestButton, action: PlotterUIAction) {
      let projection = app.testPlotterUIProjection(selectedItemID: owner, includesLearningPath: true).semantic
      let candidate = projection.actions.first {
        if case .learningAction(let request) = $0.intent {
          return request.action == .tipCalibration(.revalidateCheckpoint)
        }
        return false
      }
      let action = try #require(candidate, "Expected current recovery action while \(phase)")
      let button = try #require(DrawingStudioView(presentation: app.drawingStudioPresentation,
        plotterUIProjection: projection, plotterUIIntentSink: app).positionRecoveryButton)
      return (button, action)
    }
    await f.machine.setPenState(.up)
    _ = await app.refreshControllerSessionSnapshot()
    await submitControllerSession(app, .toggleConnection)
    let disconnected = try currentButton("disconnected")
    #expect(disconnected.button.request == nil)
    #expect(disconnected.button.unavailableReason == disconnected.action.unavailableReason)
    #expect(disconnected.button.unavailableReason?.contains("Connect the controller") == true)

    await app.establishMachineSession(f.machine.descriptor)
    await submitControllerSession(app, .requestPassiveProbe)
    let gate = TestInspectionSuspension()
    await gate.arm()
    await f.camera.configurePoseCapture(gate: gate)
    await app.drawingDraftSynchronizationTask?.value
    // Bind the actual rendered request only after asynchronous fixture setup
    // and the reconnect publication tail have settled.
    let available = try currentButton("available before verification")
    #expect(available.button.unavailableReason == nil)
    let request = try #require(available.button.request)
    var recoveryResult: PlotterUIRequestDisposition?
    let recovery = Task {
      let result = await app.submitPlotterUIRequest(request)
      recoveryResult = result
      return result
    }
    do {
      try await waitUntilAsync {
        if await gate.isWaiting { return true }
        return recoveryResult != nil
      }
      let captureIsHeld = await gate.isWaiting
      try #require(captureIsHeld,
        "Recovery completed before the capture hold: \(String(describing: recoveryResult))")
      let inProgress = try currentButton("verification is in progress")
      #expect(inProgress.button.request == nil)
      #expect(inProgress.button.unavailableReason == inProgress.action.unavailableReason)
      #expect(inProgress.button.unavailableReason?.contains("Position verification is in progress") == true)
      #expect(inProgress.button.unavailableReason != disconnected.button.unavailableReason)
      await gate.release()
      #expect(await recovery.value == .accepted(requestID: request.id))
      // Successful recovery consumes its availability in the retained owner.
      // The resolved control disappears; its obsolete blocker must not remain.
      let settledProjection = app.testPlotterUIProjection(selectedItemID: owner,
        includesLearningPath: true).semantic
      let settledView = DrawingStudioView(presentation: app.drawingStudioPresentation,
        plotterUIProjection: settledProjection, plotterUIIntentSink: app)
      #expect(settledView.positionRecoveryButton == nil)
      #expect(!settledProjection.actions.contains {
        if case .learningAction(let request) = $0.intent {
          return request.action == .tipCalibration(.revalidateCheckpoint)
        }
        return false
      })
      #expect(!app.controllerPoseApplicability.requiresPhysicalPositionForTest)
      await app.shutdown()
    } catch {
      await gate.release()
      let result = await recovery.value
      if case .refused(let refusal) = result {
        Issue.record("Actual recovery request refused: \(refusal.reason); \(refusal.remedy)")
      }
      await app.shutdown()
      throw error
    }
  }

  @Test("a failed Fit warning retires after calibration recovery before sheet coverage is confirmed")
  @MainActor
  func fitFeedbackResolvesBeforeRunReady() async throws {
    let harness = makeCausalSimulatorAppFixture()
    let app = harness.workspace
    _ = await app.currentDrawingRunFacts(for: .simulated)
    let initial = app.testPlotterUIProjection()
    let fit = try #require(initial.semantic.request(matching: .drawingDraft(.fitInDrawableRegion)))
    let submittedPresentation = app.drawingStudioPresentation
    let result = await app.submitPlotterUIRequest(fit)
    guard case .refused(let refusal) = result else {
      Issue.record("Uncalibrated Fit must produce the actual production refusal.")
      await app.shutdown()
      return
    }
    let feedback = DrawingStudioRequestRefusal(refusal.remedy, presentation: submittedPresentation)
    #expect(feedback.currentMessage(in: submittedPresentation) == refusal.remedy)
    // A repeated projection without changed dependencies cannot dismiss a real failure.
    #expect(feedback.currentMessage(in: app.drawingStudioPresentation) == refusal.remedy)
    try await completeSimulatedPenInteractionPrerequisite(app)
    try await installAcceptedBoundaryTestProjection(runtime: harness.boundaryRuntime,
      workspace: app, environment: .simulated)
    try await completeSimulatedTipCalibration(app, simulator: harness.simulator)
    await app.performTestExerciseAction(.start, for: .borderValidation(.chooseDrawingBorderPlan))
    _ = await app.currentDrawingRunFacts(for: .simulated)
    #expect(app.tipCameraRegistration != nil)
    #expect(!app.drawingDraftSnapshot.paperCoverageIsCurrent)
    let recovered = app.drawingStudioPresentation
    if case .ready = recovered.runState { Issue.record("Coverage must still block Draw.") }
    #expect(feedback.currentMessage(in: recovered) == nil)
    // A response arriving after recovery is still attributed to the request's
    // original facts, so callback ordering cannot revive the resolved warning.
    let lateResponse = DrawingStudioRequestRefusal(refusal.remedy, presentation: submittedPresentation)
    #expect(lateResponse.currentMessage(in: recovered) == nil)
    #expect(!recovered.runState.detail.isEmpty)
    await app.shutdown()
  }

  @Test("drawing outcomes remain visible through review until the run handoff")
  func activeRunStatusVisibility() {
    let runID = RunID()
    let inactive: [DrawingStudioRunState] = [
      .unavailable(reason: "Confirm paper."), .ready(detail: "Ready.")
    ]
    #expect(inactive.allSatisfy { !$0.showsActiveRunStatus })
    let retained: [DrawingStudioRunState] = [
      .terminal(runID: runID, detail: "Ended."),
      .reviewAvailable(runID: runID, detail: "Review available."),
      .reviewing(runID: runID, detail: "Reviewing.")
    ]
    #expect(retained.allSatisfy { $0.showsActiveRunStatus })
    let active: [DrawingStudioRunState] = [
      .running(capabilityID: PlotterDrawingRunStopCapabilityID(), detail: "Drawing."),
      .processing(detail: "Saving evidence."),
      .publicationIncomplete(detail: "Attempt retained; terminal record construction failed."),
      .publicationFailed(
        recoveryCapabilityID: PlotterDrawingRunPublicationRecoveryCapabilityID(),
        detail: "Retry evidence publication.")
    ]
    #expect(active.allSatisfy { $0.showsActiveRunStatus })
  }

  @Test("an unresolved durable attempt stays visible without a fabricated recovery or handoff")
  func unresolvedPublicationStatus() throws {
    let state = DrawingStudioRunState.publicationIncomplete(detail: "Exact retained error")
    let presentation = try studioPresentation(runState: state, editingIsEnabled: false)
    #expect(state.showsActiveRunStatus)
    #expect(state.title == "Drawing evidence unresolved")
    #expect(state.detail == "Exact retained error")
    #expect(presentation.controls.isEmpty)
    #expect(!presentation.authoringIsEnabled)
  }

  @Test("run and Stop controls preserve the exact typed owner capability")
  func executionControls() throws {
    let ready = try studioPresentation(
      runState: .ready(detail: "Plan admitted."),
      editingIsEnabled: true
    )
    #expect(ready.controls.map(\.intent) == [.start])
    #expect(ready.controls.allSatisfy { $0.isEnabled })

    let capability = PlotterDrawingRunStopCapabilityID()
    let running = try studioPresentation(
      runState: .running(capabilityID: capability, detail: "Stroke 2 of 4.")
    )
    #expect(running.controls.map(\.intent) == [.stop(capability)])
    #expect(running.controls.first?.role == .negative)
  }

  @Test("processing has no Stop or other accepted action")
  func processingControls() throws {
    let presentation = try studioPresentation(
      runState: .processing(detail: "Observing the exact post-run frame."),
      editingIsEnabled: false
    )

    #expect(presentation.runState.title == "Processing drawing evidence")
    #expect(presentation.controls.isEmpty)
  }

  @Test("planned targets persist across compatible frames while changed cameras invalidate them")
  func previewCameraCompatibility() throws {
    let exact = try drawingStudioTestFrame(sequence: 1)
    let stale = try drawingStudioTestFrame(sequence: 2)
    let canvas = try studioCanvas(frame: exact)

    #expect(canvas.targetPreview(for: exact) != nil)
    #expect(canvas.targetPreview(for: stale) == canvas.targetPreview(for: exact))
    let otherCamera = DisplayedFrame(source: .live(CameraDeviceID(rawValue: "other-camera")), frame: stale.frame)
    #expect(canvas.targetPreview(for: otherCamera) == nil)
    let surface = ActionSurfacePresentation(displayedFrame: exact, overlays: [], drawingStudioCanvas: canvas)
    let exactContent = ActionSurfaceOverlayContent(presentation: surface)
    #expect(exactContent.targetPreview != nil)
    let advancedContent = ActionSurfaceOverlayContent(
      presentation: surface.resolvingAmbientPreviewFrame(stale))
    #expect(advancedContent.targetPreview == exactContent.targetPreview)
    #expect(advancedContent == exactContent)
    #expect(
      ActionSurfacePresentation(
        displayedFrame: exact,
        overlays: [],
        drawingStudioCanvas: canvas
      ).drawingStudioCanvas?.targetPreview(for: exact)?.programContentHash
        == "program-hash"
    )
  }

  @Test("review states expose only review exit and new-run actions")
  func reviewControls() throws {
    let availableRunID = RunID()
    let terminalRunID = RunID()
    let available = try studioPresentation(
      runState: .reviewAvailable(runID: availableRunID, detail: "Observed geometry retained.")
    )
    let reviewing = try studioPresentation(
      runState: .reviewing(runID: availableRunID, detail: "Exact post-run frame displayed.")
    )
    let terminal = try studioPresentation(
      runState: .terminal(runID: terminalRunID, detail: "No exact post-run frame.")
    )

    #expect(available.controls.map(\.intent) == [
      .pinReview(availableRunID), .beginNewRun(availableRunID),
    ])
    #expect(reviewing.controls.map(\.intent) == [
      .unpinReview(availableRunID), .beginNewRun(availableRunID),
    ])
    #expect(terminal.controls.map(\.intent) == [.beginNewRun(terminalRunID)])
    #expect(!available.controls.map(\.intent).contains(.start))
  }

  @Test("disabled editing disables placement and Run without changing values")
  func editingBoundary() throws {
    let presentation = try studioPresentation(
      runState: .ready(detail: "Plan admission retained."),
      editingIsEnabled: false
    )

    #expect(!presentation.editingIsEnabled)
    #expect(!presentation.canvas.placement.placementIsEnabled)
    #expect(presentation.controls == [
      DrawingStudioControl(
        intent: .start,
        title: "Run Drawing",
        systemImage: "play.fill",
        role: .affirmative,
        isEnabled: false
      )
    ])
  }

  private func studioPresentation(
    runState: DrawingStudioRunState,
    editingIsEnabled: Bool = false
  ) throws -> DrawingStudioPresentation {
    let frame = try drawingStudioTestFrame(sequence: 1)
    return DrawingStudioPresentation(
      canvas: try studioCanvas(frame: frame),
      editingIsEnabled: editingIsEnabled,
      runProjection: PlotterDrawingRunProjectionReference(
        environment: .live,
        runRevision: PlotterDrawingRunRevision(rawValue: 0),
        planIdentity: nil
      ),
      runState: runState
    )
  }

  private func studioCanvas(frame: DisplayedFrame) throws -> DrawingStudioCanvasPresentation {
    let initial = PlotterDrawingDraftSnapshot.initial(
      environment: .live,
      toolAssemblyRevision: ToolAssemblyRevision(),
      paper: PaperRevisionContext(
        instance: PaperInstanceRevision(),
        contactPlane: PaperContactPlaneRevision()
      )
    )
    return DrawingStudioCanvasPresentation(
      draftProjection: initial.projection,
      placement: DrawingStudioPlacementPresentation(
        centerCameraPixel: try Point2(x: 120, y: 120),
        uniformScale: 1,
        allowedScale: 0.1...5,
        rotationDegrees: 0,
        placementIsEnabled: true
      ),
      targetPreview: DrawingStudioTargetPreview(
        provenance: ExactFrameOverlayProvenance(frame),
        strokes: [try Polyline(points: [
          Point2<CameraPixelSpace>(x: 100, y: 100),
          Point2<CameraPixelSpace>(x: 140, y: 140),
        ])],
        bounds: try AxisAlignedBounds<CameraPixelSpace>(
          minX: 100, minY: 100, maxX: 140, maxY: 140
        ),
        programContentHash: "program-hash",
        executionPlanContentHash: "plan-hash",
        status: .ready
      )
    )
  }
}

private func drawingStudioTestFrame(sequence: UInt64) throws -> DisplayedFrame {
  DisplayedFrame(
    source: .live(CameraDeviceID(rawValue: "drawing-studio-presentation-camera")),
    frame: try StampedFrame(
      sequence: sequence,
      captureNanoseconds: sequence * 10,
      cameraConfigurationID: CameraConfigurationID(
        UUID(uuidString: "00000000-0000-0000-0000-000000000011")!
      ),
      width: 2,
      height: 2,
      rowBytes: 8,
      pixelFormat: .bgra8,
      bytes: OwnedFrameBytes(Array(repeating: UInt8(sequence), count: 16))
    )
  )
}
