import AppKit
import Foundation
import SwiftUI
import PlotterModel
import PlotterTestSupport
import Testing

@testable import PlotterApp
@testable import PlotterRuntime

@Suite("Camera composition Vision lifecycle")
struct CameraCompositionVisionLifecycleTests {
  @MainActor
  @Test("slow stable-cap analysis retains the live-source canvas and settles every lease outcome",
    arguments: CanvasLeaseOutcome.allCases)
  func slowCalibrationKeepsCameraCanvas(_ outcome: CanvasLeaseOutcome) async throws {
    let device = CameraDevice(id: .init(rawValue: "held-canvas-camera"), name: "Held Canvas Camera")
    let driver = VisionLifecycleCameraDriver(device: device)
    let capture = CameraCapture(driver: driver)
    let worker = VisionWorker()
    let pipeline = PlotterSceneAnalysisPipeline(worker: worker, clock: DeterministicRuntimeClock())
    let session = CameraSourceSession(live: capture, vision: worker,
      analysisPipeline: pipeline, plannedDrawingObserver: worker)
    let clock = CanvasFreshnessClock()
    let identities = TipCalibrationSemanticIdentityState.ephemeral()
    // Acquire a real reference from this camera fixture. Application-owned
    // reference reconciliation must not be bypassed by clearing the session.
    _ = await session.discover()
    _ = await session.start()
    await driver.emitCap(centroidXOffset: 0, captureNanoseconds: 50)
    try await waitUntilStableCap("reference image reached capture") {
      await capture.snapshot().latestFrame != nil
    }
    let preview = try #require(await capture.snapshot().latestFrame)
    let referenceFrame = DisplayedFrame(source: preview.source,
      frame: preview.frame.materializingContentHash(for: .exactEvidence))
    let optical = try CameraOpticalConfigurationIdentity(source: referenceFrame.source,
      sensorFormat: "runtime-bgra8", width: 20, height: 20, pixelFormat: .bgra8,
      orientation: .up, mirrored: false, digitalZoomFactor: 1,
      lensIdentity: "runtime-unreported-lens", focusConfiguration: "runtime-unreported-focus",
      mountRevision: identities.cameraMountRevision, reframingRevision: identities.cameraReframingRevision)
    let marker = try SampledColorMarkerReference.capture(frame: referenceFrame,
      point: Point2(x: 8, y: 7), opticalConfiguration: optical)
    let appearance = PenCapAppearanceSelection(markerReference: marker, color: marker.color,
      frameID: referenceFrame.frame.id, frameSHA256: referenceFrame.frame.contentSHA256,
      source: referenceFrame.source, cameraConfigurationID: referenceFrame.frame.cameraConfigurationID,
      width: 20, height: 20, pixelFormat: .bgra8, clickPoint: marker.selectionPoint,
      usableSampleCount: marker.componentPixelCount, totalSampleCount: marker.componentPixelCount,
      algorithmRevision: SampledColorMarkerReference.revision)
    // Saved-reference startup begins in a fresh capture generation with no
    // retained preview. Otherwise frame50 may legitimately configure optics
    // before the first-frame revision baseline is recorded below.
    let restartedCamera = await session.restart()
    #expect(restartedCamera.latestFrame == nil)
    let application = makeCausalSimulatorAppFixture(observationSession: session,
      loadPenCapAppearanceSelection: { appearance },
      residualEffectPort: TestApplicationResidualEffectPort(discoverDevices: { [] },
        readNanoseconds: { clock.now }), tipCalibrationSemanticIdentities: identities).workspace
    await submitObservationConfigurationForTest(application, .refresh)
    await submitObservationConfigurationForTest(application, .selectSource(.live, device.id))
    let configurationBeforeRawFrame = await pipeline.diagnostics().configurationRevision
    await driver.emitCap(centroidXOffset: 0, captureNanoseconds: 100)
    try await waitUntilStableCap("initial camera image reached the application") {
      await MainActor.run {
        application.actionSurfacePreview.displayedFrame?.frame.captureNanoseconds == 100
      }
    }
    try await waitUntilStableCap("first raw frame installs its optical configuration") {
      await pipeline.diagnostics().configurationRevision > configurationBeforeRawFrame
    }
    // A restored marker must start ambient analysis from raw camera admission,
    // without first needing a prior analyzed/semantic displayedFrame.
    try await waitUntilStableCap("saved marker starts ambient analysis from live raw frames") {
      await MainActor.run {
        guard let frame = application.latestLiveCameraFrame,
          let measurement = application.lastSceneMeasurement else { return false }
        return frame.frame.captureNanoseconds == 100
          && measurement.frameID == frame.frame.id
          && measurement.penCap.measurement != nil
      }
    }
    let initial = try #require(application.actionSurfacePreview.displayedFrame)
    let initialIdentity = ExactFrameProvenance(frame: initial.frame)
    #expect(initial.frame.cameraConfigurationID != referenceFrame.frame.cameraConfigurationID)
    #expect(application.livePenCapAppearanceSelection?.markerReference == marker)
    let opticalFrame = try #require(application.latestLiveCameraFrame,
      "Exact workflow optics requires an admitted live frame")
    #expect(try application.cameraOpticalConfiguration(for: opticalFrame) == marker.opticalConfiguration)
    let exactCaptureBaseline = await capture.diagnostics().returnOnlyExactRequestCount
    #expect(application.cameraIsLive)
    #expect(application.workbenchCanvasPresentation.content == .plotter)
    let captureTask = Task { @MainActor in
      try await application.captureStableWorkflowCap(newerThan: initial.frame.captureNanoseconds)
    }
    try await waitUntilStableCap("calibration holds preview") {
      await session.visionDiagnostics().activeExclusiveLeaseCount == 1
    }
    // The capture owner is paused, but the old application snapshot has not
    // received a diagnostics refresh. This is the reported simulation fallback.
    clock.set(2_000_000_100)
    #expect(await capture.diagnostics().previewPublicationPaused)
    #expect(application.cameraSnapshot?.diagnostics.previewPublicationPaused != true)
    #expect(!application.cameraIsLive)
    let held = application.workbenchCanvasPresentation
    #expect(held.content == .plotter)
    #expect(held.displayedFrame?.source == .live(device.id))
    #expect(held.displayedFrame.map { ExactFrameProvenance(frame: $0.frame) } == initialIdentity)
    #expect(held.plotterFrameStatus == "Camera frame held · Looking for pen cap… Clear its view. Stop cancels.")
    #expect(application.frameMode == .live)
    #expect(application.exactWorkflowVisionOwner == .cameraCalibration)

    if let snapshotPrefix = ProcessInfo.processInfo.environment["WORKBENCH_CANVAS_SNAPSHOT"] {
      try await renderHeldCameraCanvas(application, expectedFrame: initial.frame,
        path: snapshotPrefix + "-" + outcome.rawValue + ".png")
    }

    switch outcome {
    case .success:
      for (sample, timestamp) in [200, 300, 400].enumerated() {
        await driver.emitCap(centroidXOffset: sample, captureNanoseconds: UInt64(timestamp))
        try await waitUntilStableCap("stable sample \(sample + 1)") {
          let materialized = await capture.diagnostics().returnOnlyExactRequestCount
          let settled = await session.visionDiagnostics().activeExclusiveLeaseCount == 0
          return materialized >= exactCaptureBaseline + UInt64(sample + 1) || settled
        }
        if await session.visionDiagnostics().activeExclusiveLeaseCount == 0 {
          _ = try await captureTask.value
        }
      }
      let measured = try await captureTask.value
      #expect(measured.inspection.displayedFrame.frame.captureNanoseconds == 400)
      #expect(measured.inspection.displayedFrame.source == initial.source)
      #expect(measured.inspection.displayedFrame.frame.cameraConfigurationID
        == initial.frame.cameraConfigurationID)
    case .failure:
      await driver.emit(value: 128, captureNanoseconds: 200, width: 20, height: 20)
      do {
        _ = try await captureTask.value
        Issue.record("A stalled camera must fail without inventing cap evidence")
      } catch LearningPathOperationError.freshFrameUnavailable {}
    case .cancelled:
      captureTask.cancel()
      do {
        _ = try await captureTask.value
        Issue.record("Cancelled analysis must throw")
      } catch is CancellationError {}
    }
    let settled = await session.visionDiagnostics()
    #expect(settled.activeExclusiveLeaseCount == 0)
    #expect(settled.exclusiveLeaseBeginCount == 1)
    #expect(settled.exclusiveLeaseEndCount == 1)
    #expect(settled.capture.previewPauseAcquisitionCount == 1)
    #expect(settled.capture.previewPauseReleaseCount == 1)
    #expect(!settled.capture.previewPublicationPaused)
    #expect(application.exactWorkflowVisionOwner == nil)
    #expect(application.workbenchCanvasPresentation.content == .plotter)
    #expect(application.workbenchCanvasPresentation.displayedFrame?.source == initial.source)
    #expect(application.frameMode == .live)
    // A new raw frame resumes ordinary display without a source transition.
    clock.set(3_000_000_100)
    await driver.emitCap(centroidXOffset: 0, captureNanoseconds: clock.now)
    try await waitUntilStableCap("fresh preview resumes after calibration") {
      await MainActor.run {
        application.actionSurfacePreview.displayedFrame?.frame.captureNanoseconds == clock.now
      }
    }
    #expect(application.cameraIsLive)
    #expect(application.workbenchCanvasPresentation.plotterFrameStatus == nil)
    #expect(application.workbenchCanvasPresentation.content == .plotter)
    await application.shutdown()
  }

  @Test("automatic inspection reconciliation and exclusive leases avoid redundant work")
  func heldPlannedObservationLifecycle() async throws {
    let device = CameraDevice(
      id: CameraDeviceID(rawValue: "vision-lifecycle-camera"),
      name: "Vision Lifecycle Camera"
    )
    let driver = VisionLifecycleCameraDriver(device: device)
    let capture = CameraCapture(driver: driver)
    let worker = VisionWorker()
    let pipeline = PlotterSceneAnalysisPipeline(
      worker: worker,
      clock: DeterministicRuntimeClock()
    )
    let observationGate = HeldPlannedObservation()
    let session = CameraSourceSession(
      live: capture,
      vision: worker,
      analysisPipeline: pipeline,
      plannedDrawingObserver: observationGate
    )

    _ = await session.discover()
    _ = await session.start()
    await driver.emit(value: 1, captureNanoseconds: 100)
    try await waitUntil {
      let diagnostics = await capture.diagnostics()
      return diagnostics.receivedFrameCount == 1
        && diagnostics.previewMaterializedFrameCount == 1
    }

    _ = await session.setAutomaticInspection(.fiveFPS, requestedFeatures: [.penCap])
    try await waitUntil {
      let diagnostics = await pipeline.diagnostics()
      return diagnostics.analyzedFrameCount == 1
        && diagnostics.latestResult?.frameSequence == 1
    }
    await driver.emit(value: 2, captureNanoseconds: 200)
    try await waitUntil {
      let diagnostics = await pipeline.diagnostics()
      return diagnostics.analyzedFrameCount == 2
        && diagnostics.latestResult?.frameSequence == 2
    }
    let running = await session.visionDiagnostics()
    #expect(running.automaticInspectionConfigurationRevision == 1)
    #expect(running.automaticPipelineStartCallCount == 1)
    #expect(running.automaticFrameSubscriptionStartCount == 1)

    _ = await session.setAutomaticInspection(.fiveFPS, requestedFeatures: [.penCap])
    await session.setSceneAnalysisRegion(nil)
    await session.setPenCapColor(.green)
    let reconciled = await session.visionDiagnostics()
    #expect(reconciled.automaticInspectionConfigurationRevision == 1)
    #expect(reconciled.automaticPipelineStartCallCount == 1)
    #expect(reconciled.automaticFrameSubscriptionStartCount == 1)
    #expect(reconciled.automaticPauseCallCount == 0)
    #expect(reconciled.pipeline == running.pipeline)

    let request = try plannedObservationRequest()
    let observationTask = Task {
      await session.observePlannedDrawingInk(request)
    }
    try await waitUntil { await observationGate.startedCount == 1 }

    let held = await session.visionDiagnostics()
    #expect(held.activeExclusiveLeaseCount == 1)
    #expect(held.exclusiveLeaseBeginCount == 1)
    #expect(held.exclusiveLeaseEndCount == 0)
    #expect(held.capture.previewPublicationPaused)
    #expect(held.capture.previewPauseAcquisitionCount == 1)
    #expect(held.capture.previewPauseReleaseCount == 0)
    #expect(held.pipeline.phase.state == .stopped)
    #expect(held.automaticPauseCallCount == 1)
    #expect(held.automaticFrameSubscriptionCancellationCount == 1)

    _ = await session.setAutomaticInspection(
      .fiveFPS,
      requestedFeatures: [.armatureEnvelope]
    )
    let reconfiguredWhileHeld = await session.visionDiagnostics()
    #expect(reconfiguredWhileHeld.automaticInspectionConfigurationRevision == 2)
    #expect(reconfiguredWhileHeld.requestedCadence == .fiveFPS)
    #expect(reconfiguredWhileHeld.requestedFeatures == [.armatureEnvelope])
    #expect(reconfiguredWhileHeld.automaticPauseCallCount == 1)
    #expect(reconfiguredWhileHeld.automaticPipelineStartCallCount == 1)
    #expect(reconfiguredWhileHeld.automaticFrameSubscriptionStartCount == 1)

    _ = await session.setAutomaticInspection(
      .fiveFPS,
      requestedFeatures: [.armatureEnvelope]
    )
    await session.setSceneAnalysisRegion(nil)
    let repeatedHeldReconciliation = await session.visionDiagnostics()
    #expect(repeatedHeldReconciliation.automaticInspectionConfigurationRevision == 2)
    #expect(repeatedHeldReconciliation.automaticPauseCallCount == 1)
    #expect(repeatedHeldReconciliation.automaticPipelineStartCallCount == 1)
    #expect(repeatedHeldReconciliation.automaticFrameSubscriptionStartCount == 1)
    #expect(repeatedHeldReconciliation.pipeline == reconfiguredWhileHeld.pipeline)

    await driver.emit(value: 3, captureNanoseconds: 300)
    await driver.emit(value: 4, captureNanoseconds: 400)
    try await waitUntil { await capture.diagnostics().receivedFrameCount == 4 }
    let trafficWhileHeld = await session.visionDiagnostics()
    #expect(trafficWhileHeld.capture.previewMaterializedFrameCount == 2)
    #expect(trafficWhileHeld.capture.exactMaterializedFrameCount == 0)
    #expect(trafficWhileHeld.pipeline.analyzedFrameCount == 2)
    #expect(trafficWhileHeld.pipeline.latestResult == nil)

    await observationGate.release()
    _ = await observationTask.value
    try await waitUntil {
      let diagnostics = await session.visionDiagnostics()
      return diagnostics.activeExclusiveLeaseCount == 0
        && diagnostics.capture.previewMaterializedFrameCount == 3
        && diagnostics.pipeline.analyzedFrameCount == 3
        && diagnostics.pipeline.latestResult?.frameSequence == 4
    }

    let resumed = await session.visionDiagnostics()
    #expect(resumed.exclusiveLeaseEndCount == 1)
    #expect(resumed.exclusiveLeaseSuccessCount == 1)
    #expect(resumed.exclusiveLeaseFailureCount == 0)
    #expect(resumed.exclusiveLeaseCancellationCount == 0)
    #expect(resumed.automaticResumeAfterExclusiveCount == 1)
    #expect(resumed.automaticPipelineStartCallCount == 2)
    #expect(resumed.automaticFrameSubscriptionStartCount == 2)
    #expect(resumed.capture.exactMaterializedFrameCount == 0)
    #expect(resumed.capture.previewPauseAcquisitionCount == 1)
    #expect(resumed.capture.previewPauseReleaseCount == 1)
    #expect(resumed.pipeline.latestResult?.frameSequence == 4)
    #expect(await session.snapshot().latestFrame?.frame.sequence == 4)

    _ = await session.stop()
  }

  @Test("return-only batch samples stay off preview and analysis until one exact publish")
  func returnOnlyBatchPublicationPolicy() async throws {
    let device = CameraDevice(
      id: CameraDeviceID(rawValue: "exact-policy-camera"),
      name: "Exact Policy Camera"
    )
    let driver = VisionLifecycleCameraDriver(device: device)
    let capture = CameraCapture(driver: driver)
    let worker = VisionWorker()
    let pipeline = PlotterSceneAnalysisPipeline(
      worker: worker,
      clock: DeterministicRuntimeClock()
    )
    let session = CameraSourceSession(
      live: capture,
      vision: worker,
      analysisPipeline: pipeline,
      plannedDrawingObserver: worker
    )

    _ = await session.discover()
    _ = await session.start()
    await driver.emit(value: 1, captureNanoseconds: 100)
    try await waitUntil { await capture.diagnostics().receivedFrameCount == 1 }
    _ = await session.setAutomaticInspection(.fiveFPS, requestedFeatures: [.penCap])
    try await waitUntil { await pipeline.diagnostics().submittedFrameCount == 1 }
    let before = await session.visionDiagnostics()

    let (selected, expiredScope) = try await session.withExclusiveVisionLease(
      ReturnOnlyBatchLeaseOperation(
        driver: driver,
        capture: capture,
        session: session,
        before: before
      )
    )

    try await waitUntil {
      let diagnostics = await session.visionDiagnostics()
      return diagnostics.pipeline.submittedFrameCount == before.pipeline.submittedFrameCount + 1
        && diagnostics.pipeline.latestResult?.frameID == selected.frame.id
    }
    let settled = await session.visionDiagnostics()
    #expect(settled.capture.ordinaryPreviewPublicationCount == 1)
    #expect(settled.capture.explicitExactPublicationCount == 1)
    #expect(settled.capture.previewPauseAcquisitionCount == 1)
    #expect(settled.capture.previewPauseReleaseCount == 1)
    #expect(settled.exclusiveLeaseBeginCount == 1)
    #expect(settled.exclusiveLeaseEndCount == 1)
    #expect(settled.exclusiveLeaseSuccessCount == 1)
    #expect(settled.pipeline.latestResult?.frameID == selected.frame.id)

    do {
      _ = try await expiredScope.captureFrame()
      Issue.record("Expected an escaped exact-Vision scope to be inactive")
    } catch let error as CameraSourceSessionVisionLeaseError {
      #expect(error == .inactiveLease)
    }

    _ = await session.stop()
  }

  @Test("exclusive batch lease settles once on success, failure, and cancellation")
  func batchLeaseSettlementPaths() async throws {
    let device = CameraDevice(
      id: CameraDeviceID(rawValue: "lease-settlement-camera"),
      name: "Lease Settlement Camera"
    )
    let driver = VisionLifecycleCameraDriver(device: device)
    let capture = CameraCapture(driver: driver)
    let worker = VisionWorker()
    let pipeline = PlotterSceneAnalysisPipeline(
      worker: worker,
      clock: DeterministicRuntimeClock()
    )
    let session = CameraSourceSession(
      live: capture,
      vision: worker,
      analysisPipeline: pipeline,
      plannedDrawingObserver: worker
    )

    _ = await session.discover()
    _ = await session.start()
    _ = await session.setAutomaticInspection(.twoFPS, requestedFeatures: [.penCap])

    let value = try await session.withExclusiveVisionLease(
      ConstantBatchLeaseOperation(value: 17)
    )
    #expect(value == 17)
    var diagnostics = await session.visionDiagnostics()
    #expect(diagnostics.exclusiveLeaseBeginCount == 1)
    #expect(diagnostics.exclusiveLeaseEndCount == 1)
    #expect(diagnostics.exclusiveLeaseSuccessCount == 1)
    #expect(diagnostics.capture.previewPauseAcquisitionCount == 1)
    #expect(diagnostics.capture.previewPauseReleaseCount == 1)
    #expect(diagnostics.automaticResumeAfterExclusiveCount == 1)

    do {
      _ = try await session.withExclusiveVisionLease(FailingBatchLeaseOperation())
      Issue.record("Expected the batch body failure")
    } catch let error as BatchLeaseTestError {
      #expect(error == .expectedFailure)
    }
    diagnostics = await session.visionDiagnostics()
    #expect(diagnostics.exclusiveLeaseBeginCount == 2)
    #expect(diagnostics.exclusiveLeaseEndCount == 2)
    #expect(diagnostics.exclusiveLeaseFailureCount == 1)
    #expect(diagnostics.capture.previewPauseAcquisitionCount == 2)
    #expect(diagnostics.capture.previewPauseReleaseCount == 2)
    #expect(diagnostics.automaticResumeAfterExclusiveCount == 2)

    let cancellationProbe = BatchLeaseCancellationProbe()
    let cancelled = Task {
      try await session.withExclusiveVisionLease(
        CancellableBatchLeaseOperation(probe: cancellationProbe)
      )
    }
    try await waitUntil { await cancellationProbe.hasStarted }
    cancelled.cancel()
    if case .success = await cancelled.result {
      Issue.record("Expected cancellation to propagate from the batch body")
    }
    try await waitUntil {
      await session.visionDiagnostics().exclusiveLeaseCancellationCount == 1
    }
    diagnostics = await session.visionDiagnostics()
    #expect(diagnostics.exclusiveLeaseBeginCount == 3)
    #expect(diagnostics.exclusiveLeaseEndCount == 3)
    #expect(diagnostics.exclusiveLeaseCancellationCount == 1)
    #expect(diagnostics.activeExclusiveLeaseCount == 0)
    #expect(diagnostics.capture.previewPauseAcquisitionCount == 3)
    #expect(diagnostics.capture.previewPauseReleaseCount == 3)
    #expect(!diagnostics.capture.previewPublicationPaused)
    #expect(diagnostics.automaticResumeAfterExclusiveCount == 3)
    #expect(diagnostics.pipeline.phase.state == .running(.twoFPS))

    _ = await session.stop()
  }

  @Test("stable cap collects three private newer frames and publishes only the selected newest")
  func stableCapUsesOneExclusiveLifecycleAndOnePublication() async throws {
    let device = CameraDevice(
      id: CameraDeviceID(rawValue: "stable-cap-camera"),
      name: "Stable Cap Camera"
    )
    let driver = VisionLifecycleCameraDriver(device: device)
    let capture = CameraCapture(driver: driver)
    let worker = VisionWorker()
    let pipeline = PlotterSceneAnalysisPipeline(
      worker: worker,
      clock: DeterministicRuntimeClock()
    )
    let session = CameraSourceSession(
      live: capture,
      vision: worker,
      analysisPipeline: pipeline,
      plannedDrawingObserver: worker
    )

    _ = await session.discover()
    _ = await session.start()
    _ = await session.setAutomaticInspection(.twoFPS, requestedFeatures: [.penCap])
    let before = await session.visionDiagnostics()
    let captureTask = Task {
      try await session.captureStableWorkflowCap(
        StableWorkflowCapCaptureRequest(
          newerThanNanoseconds: 100, searchCenter: try Point2(x: 10_000, y: -10_000)
        )
      )
    }
    try await waitUntilStableCap("success lease became active") {
      await session.visionDiagnostics().activeExclusiveLeaseCount == 1
    }

    for (sample, captureNanoseconds) in [200, 300, 400].enumerated() {
      await driver.emitCap(
        centroidXOffset: sample,
        captureNanoseconds: UInt64(captureNanoseconds)
      )
      try await waitUntilStableCap("success sample \(sample + 1) materialized") {
        await capture.diagnostics().returnOnlyExactRequestCount == UInt64(sample + 1)
      }
      if sample < 2 {
        let collecting = await session.visionDiagnostics()
        #expect(collecting.capture.ordinaryPreviewPublicationCount == 0)
        #expect(collecting.capture.explicitExactPublicationCount == 0)
        #expect(collecting.pipeline.submittedFrameCount == before.pipeline.submittedFrameCount)
        #expect(collecting.activeExclusiveLeaseCount == 1)
      }
    }

    let selected = try await captureTask.value
    #expect(selected.inspection.displayedFrame.frame.captureNanoseconds == 400)
    #expect(selected.cap.centroid.x == 10)
    try await waitUntilStableCap("selected frame reached resumed automatic analysis") {
      let diagnostics = await session.visionDiagnostics().pipeline
      return diagnostics.submittedFrameCount == before.pipeline.submittedFrameCount + 1
        && diagnostics.latestResult?.frameID == selected.inspection.displayedFrame.frame.id
    }

    let settled = await session.visionDiagnostics()
    #expect(settled.capture.returnOnlyExactRequestCount == 3)
    #expect(settled.capture.ordinaryPreviewPublicationCount == 0)
    #expect(settled.capture.explicitExactPublicationCount == 1)
    #expect(
      settled.capture.lastExplicitlyPublishedExactFrameID
        == selected.inspection.displayedFrame.frame.id
    )
    #expect(settled.exclusiveLeaseBeginCount == 1)
    #expect(settled.exclusiveLeaseEndCount == 1)
    #expect(settled.exclusiveLeaseSuccessCount == 1)
    #expect(settled.capture.previewPauseAcquisitionCount == 1)
    #expect(settled.capture.previewPauseReleaseCount == 1)
    #expect(settled.automaticResumeAfterExclusiveCount == 1)
    #expect(settled.activeExclusiveLeaseCount == 0)
    #expect(settled.pipeline.latestResult?.frameID == selected.inspection.displayedFrame.frame.id)

    _ = await session.stop()
  }

  @Test("temporary cap occlusion keeps one lease and needs three new observations after the gap")
  func missingCapWaitsAndReacquires() async throws {
    let device = CameraDevice(id: CameraDeviceID(rawValue: "missing-cap-camera"), name: "Missing Cap")
    let driver = VisionLifecycleCameraDriver(device: device)
    let capture = CameraCapture(driver: driver)
    let worker = VisionWorker()
    let pipeline = PlotterSceneAnalysisPipeline(worker: worker, clock: DeterministicRuntimeClock())
    let session = CameraSourceSession(live: capture, vision: worker,
      analysisPipeline: pipeline, plannedDrawingObserver: worker)
    _ = await session.discover()
    _ = await session.start()
    let request = Task {
      try await session.captureStableWorkflowCap(StableWorkflowCapCaptureRequest(newerThanNanoseconds: 100))
    }
    defer { request.cancel() }
    try await waitUntilStableCap("missing cap lease") {
      await session.visionDiagnostics().activeExclusiveLeaseCount == 1
    }
    // Two good observations cannot bridge the missing cap and count toward
    // the final three. The prediction cannot fill the occluded frame either.
    for (index, visible) in [true, true, false, true, true, true].enumerated() {
      let timestamp = UInt64(200 + index * 100)
      if visible { await driver.emitCap(centroidXOffset: 0, captureNanoseconds: timestamp) }
      else { await driver.emit(value: 128, captureNanoseconds: timestamp, width: 20, height: 20) }
      try await waitUntilStableCap("occlusion sample \(index)") {
        await capture.diagnostics().returnOnlyExactRequestCount == UInt64(index + 1)
      }
      if index < 5 {
        #expect(await session.visionDiagnostics().activeExclusiveLeaseCount == 1)
        #expect(await capture.diagnostics().explicitExactPublicationCount == 0)
      }
    }
    let observed = try await request.value
    #expect(observed.inspection.displayedFrame.frame.captureNanoseconds == 700)
    #expect(observed.cap.centroid.x == 8)
    let diagnostics = await session.visionDiagnostics()
    #expect(diagnostics.activeExclusiveLeaseCount == 0)
    #expect(diagnostics.exclusiveLeaseBeginCount == 1)
    #expect(diagnostics.exclusiveLeaseSuccessCount == 1)
    #expect(diagnostics.capture.explicitExactPublicationCount == 1)
    #expect(diagnostics.capture.previewPauseReleaseCount == 1)
    _ = await session.stop()
  }

  @Test("changed frame geometry while the cap is hidden terminates acquisition and releases ownership")
  func geometryChangeWhileCapIsHidden() async throws {
    let device = CameraDevice(id: .init(rawValue: "occluded-cap-geometry"), name: "Occluded cap")
    let driver = VisionLifecycleCameraDriver(device: device)
    let capture = CameraCapture(driver: driver)
    let worker = VisionWorker()
    let session = CameraSourceSession(live: capture, vision: worker,
      analysisPipeline: PlotterSceneAnalysisPipeline(worker: worker), plannedDrawingObserver: worker)
    _ = await session.discover()
    _ = await session.start()
    let request = Task {
      try await session.captureStableWorkflowCap(.init(newerThanNanoseconds: 100))
    }
    defer { request.cancel() }
    try await waitUntilStableCap("geometry change lease") {
      await session.visionDiagnostics().activeExclusiveLeaseCount == 1
    }
    await driver.emit(value: 128, captureNanoseconds: 200, width: 20, height: 20)
    try await waitUntilStableCap("first occluded frame materialized") {
      await capture.diagnostics().returnOnlyExactRequestCount == 1
    }
    await driver.emit(value: 128, captureNanoseconds: 300, width: 21, height: 20)
    do {
      _ = try await request.value
      Issue.record("Changed geometry cannot continue the saved optical acquisition")
    } catch LearningPathOperationError.requiredState(let detail) {
      #expect(detail.contains("Camera source or configuration changed"))
    }
    #expect(await session.visionDiagnostics().activeExclusiveLeaseCount == 0)
    #expect(await capture.diagnostics().explicitExactPublicationCount == 0)
    _ = await session.stop()
  }

  @Test("Stop while the cap is hidden releases acquisition without accepting earlier observations")
  func stopWhileCapIsHidden() async throws {
    let device = CameraDevice(id: .init(rawValue: "occluded-cap-stop"), name: "Occluded cap")
    let driver = VisionLifecycleCameraDriver(device: device)
    let capture = CameraCapture(driver: driver)
    let worker = VisionWorker()
    let session = CameraSourceSession(live: capture, vision: worker,
      analysisPipeline: PlotterSceneAnalysisPipeline(worker: worker), plannedDrawingObserver: worker)
    _ = await session.discover()
    _ = await session.start()
    let request = Task {
      try await session.captureStableWorkflowCap(.init(newerThanNanoseconds: 100))
    }
    try await waitUntilStableCap("occluded cap lease") {
      await session.visionDiagnostics().activeExclusiveLeaseCount == 1
    }
    await driver.emit(value: 128, captureNanoseconds: 200, width: 20, height: 20)
    try await waitUntilStableCap("occluded frame materialized") {
      await capture.diagnostics().returnOnlyExactRequestCount == 1
    }
    request.cancel()
    do { _ = try await request.value; Issue.record("Stop must cancel cap reacquisition") }
    catch is CancellationError {}
    let diagnostics = await session.visionDiagnostics()
    #expect(diagnostics.activeExclusiveLeaseCount == 0)
    #expect(diagnostics.exclusiveLeaseCancellationCount == 1)
    #expect(diagnostics.capture.explicitExactPublicationCount == 0)
    #expect(diagnostics.capture.previewPauseReleaseCount == 1)
    _ = await session.stop()
  }

  @Test("cap variation is diagnostic and cancellation settles its exclusive lifecycle")
  func capVariationAndCancellationSettle() async throws {
    let device = CameraDevice(
      id: CameraDeviceID(rawValue: "stable-cap-settlement-camera"),
      name: "Stable Cap Settlement Camera"
    )
    let driver = VisionLifecycleCameraDriver(device: device)
    let capture = CameraCapture(driver: driver)
    let worker = VisionWorker()
    let pipeline = PlotterSceneAnalysisPipeline(
      worker: worker,
      clock: DeterministicRuntimeClock()
    )
    let session = CameraSourceSession(
      live: capture,
      vision: worker,
      analysisPipeline: pipeline,
      plannedDrawingObserver: worker
    )

    _ = await session.discover()
    _ = await session.start()
    _ = await session.setAutomaticInspection(.twoFPS, requestedFeatures: [.penCap])
    let unstable = Task {
      try await session.captureStableWorkflowCap(
        StableWorkflowCapCaptureRequest(newerThanNanoseconds: 100)
      )
    }
    try await waitUntilStableCap("failure lease became active") {
      await session.visionDiagnostics().activeExclusiveLeaseCount == 1
    }
    for (sample, offset) in [0, 3, 1].enumerated() {
      await driver.emitCap(
        centroidXOffset: offset,
        captureNanoseconds: UInt64(200 + sample * 100)
      )
      try await waitUntilStableCap("failure sample \(sample + 1) materialized") {
        await capture.diagnostics().returnOnlyExactRequestCount == UInt64(sample + 1)
      }
    }
    let observed = try await unstable.value
    #expect(observed.centroidSpreadPixels == 3)
    #expect(observed.cap.centroid.x == 9)
    #expect(observed.inspection.displayedFrame.frame.captureNanoseconds == 400)
    var diagnostics = await session.visionDiagnostics()
    #expect(diagnostics.exclusiveLeaseBeginCount == 1)
    #expect(diagnostics.exclusiveLeaseEndCount == 1)
    #expect(diagnostics.exclusiveLeaseSuccessCount == 1)
    #expect(diagnostics.capture.explicitExactPublicationCount == 1)
    #expect(diagnostics.capture.previewPauseAcquisitionCount == 1)
    #expect(diagnostics.capture.previewPauseReleaseCount == 1)
    #expect(diagnostics.automaticResumeAfterExclusiveCount == 1)
    #expect(diagnostics.activeExclusiveLeaseCount == 0)

    let cancelled = Task {
      try await session.captureStableWorkflowCap(
        StableWorkflowCapCaptureRequest(newerThanNanoseconds: 1_000)
      )
    }
    try await waitUntilStableCap("cancellation lease became active") {
      await session.visionDiagnostics().activeExclusiveLeaseCount == 1
    }
    cancelled.cancel()
    if case .success = await cancelled.result {
      Issue.record("Expected stable-cap cancellation to propagate")
    }
    diagnostics = await session.visionDiagnostics()
    #expect(diagnostics.exclusiveLeaseBeginCount == 2)
    #expect(diagnostics.exclusiveLeaseEndCount == 2)
    #expect(diagnostics.exclusiveLeaseCancellationCount == 1)
    #expect(diagnostics.capture.explicitExactPublicationCount == 1)
    #expect(diagnostics.capture.previewPauseAcquisitionCount == 2)
    #expect(diagnostics.capture.previewPauseReleaseCount == 2)
    #expect(diagnostics.automaticResumeAfterExclusiveCount == 2)
    #expect(diagnostics.activeExclusiveLeaseCount == 0)
    #expect(!diagnostics.capture.previewPublicationPaused)

    _ = await session.stop()
  }

  @Test("planned-observation cancellation returns its nonthrowing rejection and releases its one exclusive Vision lease")
  func plannedObservationCancellationReleasesExclusiveLease() async throws {
    let device = CameraDevice(
      id: CameraDeviceID(rawValue: "planned-cancellation-camera"),
      name: "Planned Cancellation Camera"
    )
    let driver = VisionLifecycleCameraDriver(device: device)
    let capture = CameraCapture(driver: driver)
    let worker = VisionWorker()
    let pipeline = PlotterSceneAnalysisPipeline(
      worker: worker,
      clock: DeterministicRuntimeClock()
    )
    let checkpointGate = PlannedObservationLifecycleCheckpointGate()
    let session = CameraSourceSession(
      live: capture,
      vision: worker,
      analysisPipeline: pipeline,
      plannedDrawingObserver: CheckpointedPlannedDrawingObserver(
        worker: worker,
        checkpointGate: checkpointGate
      )
    )

    _ = await session.discover()
    _ = await session.start()
    _ = await session.setAutomaticInspection(.twoFPS, requestedFeatures: [.penCap])
    let request = try plannedObservationRequest()
    let observationTask = Task {
      let outcome = await session.observePlannedDrawingInk(request)
      return (outcome, Task.isCancelled)
    }
    try await waitUntil { await checkpointGate.isHolding }
    var diagnostics = await session.visionDiagnostics()
    #expect(diagnostics.activeExclusiveLeaseCount == 1)
    #expect(diagnostics.exclusiveLeaseBeginCount == 1)
    #expect(diagnostics.exclusiveLeaseEndCount == 0)

    observationTask.cancel()
    await checkpointGate.release()
    let (outcome, wasCancelled) = await observationTask.value
    #expect(wasCancelled)
    guard case .rejected(let rejection) = outcome else {
      Issue.record("cancelled observation must not publish partial evidence: \(outcome)")
      return
    }
    #expect(rejection.reason == .computationCancelled)

    diagnostics = await session.visionDiagnostics()
    #expect(diagnostics.exclusiveLeaseBeginCount == 1)
    #expect(diagnostics.exclusiveLeaseEndCount == 1)
    #expect(diagnostics.exclusiveLeaseCancellationCount == 1)
    #expect(diagnostics.exclusiveLeaseSuccessCount == 0)
    #expect(diagnostics.exclusiveLeaseFailureCount == 0)
    #expect(diagnostics.activeExclusiveLeaseCount == 0)
    #expect(diagnostics.capture.previewPauseAcquisitionCount == 1)
    #expect(diagnostics.capture.previewPauseReleaseCount == 1)
    #expect(!diagnostics.capture.previewPublicationPaused)
    #expect(diagnostics.automaticResumeAfterExclusiveCount == 1)

    _ = await session.stop()
  }
}

private struct ReturnOnlyBatchLeaseOperation: CameraSourceSessionVisionLeaseOperation {
  let driver: VisionLifecycleCameraDriver
  let capture: CameraCapture
  let session: CameraSourceSession
  let before: CameraSourceSessionVisionDiagnostics

  func perform(
    in scope: CameraSourceSessionVisionLeaseScope
  ) async throws -> (DisplayedFrame, CameraSourceSessionVisionLeaseScope) {
    await driver.emit(value: 2, captureNanoseconds: 200)
    try await waitUntil { await capture.diagnostics().receivedFrameCount == 2 }
    let selected = try #require(
      try await scope.captureFrame(newerThanNanoseconds: 100)
    )

    let returnOnly = await session.visionDiagnostics()
    #expect(
      returnOnly.capture.ordinaryPreviewPublicationCount
        == before.capture.ordinaryPreviewPublicationCount
    )
    #expect(returnOnly.capture.explicitExactPublicationCount == 0)
    #expect(returnOnly.capture.returnOnlyExactRequestCount == 1)
    #expect(returnOnly.capture.lastReturnOnlyExactFrameID == selected.frame.id)
    #expect(
      returnOnly.pipeline.submittedFrameCount
        == before.pipeline.submittedFrameCount
    )

    #expect(try await scope.publishValidatedFrame(selected) == .published)
    #expect(try await scope.publishValidatedFrame(selected) == .alreadyPublished)
    let explicitlyPublished = await session.visionDiagnostics()
    #expect(
      explicitlyPublished.capture.ordinaryPreviewPublicationCount
        == before.capture.ordinaryPreviewPublicationCount
    )
    #expect(explicitlyPublished.capture.explicitExactPublicationCount == 1)
    #expect(
      explicitlyPublished.capture.lastExplicitlyPublishedExactFrameID
        == selected.frame.id
    )
    #expect(
      explicitlyPublished.pipeline.submittedFrameCount
        == before.pipeline.submittedFrameCount
    )
    return (selected, scope)
  }
}

private struct ConstantBatchLeaseOperation<Value: Sendable>:
  CameraSourceSessionVisionLeaseOperation
{
  let value: Value

  func perform(in _: CameraSourceSessionVisionLeaseScope) async throws -> Value {
    value
  }
}

private struct FailingBatchLeaseOperation: CameraSourceSessionVisionLeaseOperation {
  func perform(in _: CameraSourceSessionVisionLeaseScope) async throws -> Int {
    throw BatchLeaseTestError.expectedFailure
  }
}

private struct CancellableBatchLeaseOperation: CameraSourceSessionVisionLeaseOperation {
  let probe: BatchLeaseCancellationProbe

  func perform(in _: CameraSourceSessionVisionLeaseScope) async throws {
    await probe.markStarted()
    try await Task.sleep(nanoseconds: 60_000_000_000)
  }
}

private enum BatchLeaseTestError: Error, Equatable {
  case expectedFailure
}

private actor BatchLeaseCancellationProbe {
  private(set) var hasStarted = false

  func markStarted() {
    hasStarted = true
  }
}

private actor HeldPlannedObservation: CameraPlannedDrawingObserverPort {
  private(set) var startedCount = 0
  private var continuation: CheckedContinuation<Void, Never>?

  func observePlannedDrawingInk(
    _ request: PlannedDrawingObservationRequest
  ) async -> PlannedDrawingObservationOutcome {
    startedCount += 1
    await withCheckedContinuation { continuation in
      self.continuation = continuation
    }
    return .rejected(
      try! DrawingObservationRejection(
        frames: request.frames,
        reason: .algorithmFailure(code: "held-planned-observation-fixture"),
        algorithmRevisions: [request.observerRevision]
      )
    )
  }

  func release() {
    continuation?.resume()
    continuation = nil
  }
}

private struct CheckpointedPlannedDrawingObserver: CameraPlannedDrawingObserverPort {
  let worker: VisionWorker
  let checkpointGate: PlannedObservationLifecycleCheckpointGate

  func observePlannedDrawingInk(
    _ request: PlannedDrawingObservationRequest
  ) async -> PlannedDrawingObservationOutcome {
    await worker.observePlannedDrawingInk(
      request,
      checkpointHandler: { checkpoint in
        await checkpointGate.receive(checkpoint)
      }
    )
  }
}

private actor PlannedObservationLifecycleCheckpointGate {
  private var continuation: CheckedContinuation<Void, Never>?
  private var didHold = false

  var isHolding: Bool { continuation != nil }

  func receive(_ checkpoint: PlannedDrawingObservationCheckpoint) async {
    guard checkpoint.stage == .alignmentRow,
      checkpoint.computation.alignmentEvaluatedPixelCount > 0,
      !didHold
    else { return }
    didHold = true
    await withCheckedContinuation { continuation in
      self.continuation = continuation
    }
  }

  func release() {
    continuation?.resume()
    continuation = nil
  }
}

private actor VisionLifecycleCameraDriver: CameraCaptureDriver {
  let device: CameraDevice
  private var eventHandler: (@Sendable (CameraDriverEvent) -> Void)?

  init(device: CameraDevice) {
    self.device = device
  }

  func authorizationState() async -> CameraAuthorizationState { .authorized }

  func requestAccess() async -> Bool { true }

  func discoverDevices() async -> [CameraDevice] { [device] }

  func start(
    deviceID: CameraDeviceID,
    maximumFramesPerSecond _: Double?,
    eventHandler: @escaping @Sendable (CameraDriverEvent) -> Void
  ) async throws -> CameraCaptureDriverStartResult {
    precondition(deviceID == device.id)
    self.eventHandler = eventHandler
    return CameraCaptureDriverStartResult(appliedMaximumFramesPerSecond: nil)
  }

  func stop() async {
    eventHandler = nil
  }

  func emit(value: UInt8, captureNanoseconds: UInt64, width: Int = 2, height: Int = 2) {
    eventHandler?(
      .frame(
        CapturedBGRAFrame(
          width: width,
          height: height,
          rowBytes: width * 4,
          bytes: Data(repeating: value, count: width * height * 4),
          captureNanoseconds: captureNanoseconds
        )
      )
    )
  }

  func emitCap(centroidXOffset: Int, captureNanoseconds: UInt64) {
    let width = 20
    let height = 20
    let rowBytes = width * 4
    var bytes = Data(repeating: 0, count: rowBytes * height)
    for y in 5..<10 {
      for x in (6 + centroidXOffset)..<(11 + centroidXOffset) {
        let offset = y * rowBytes + x * 4
        bytes[offset] = PenCapColor.green.blue
        bytes[offset + 1] = PenCapColor.green.green
        bytes[offset + 2] = PenCapColor.green.red
        bytes[offset + 3] = 255
      }
    }
    eventHandler?(
      .frame(
        CapturedBGRAFrame(
          width: width,
          height: height,
          rowBytes: rowBytes,
          bytes: bytes,
          captureNanoseconds: captureNanoseconds
        )
      )
    )
  }
}

private func plannedObservationRequest() throws -> PlannedDrawingObservationRequest {
  let camera = CameraConfigurationID()
  let simulator = PaperSceneSimulator(width: 16, height: 16)
  let baseline = try simulator.render(
    strokes: [],
    sequence: 1,
    captureNanoseconds: 1,
    cameraConfigurationID: camera
  )
  let post = try simulator.render(
    strokes: [],
    sequence: 2,
    captureNanoseconds: 2,
    cameraConfigurationID: camera
  )
  let frames = try DrawingObservationFramePair(
    source: .simulated,
    baseline: ExactFrameProvenance(frame: baseline),
    post: ExactFrameProvenance(frame: post)
  )
  let intended = try Polyline<CameraPixelSpace>(points: [
    try Point2(x: 4, y: 4),
    try Point2(x: 10, y: 4),
  ])
  return PlannedDrawingObservationRequest(
    frames: frames,
    localPreDrawingBaseline: SamePoseFrameSample(
      source: .simulated,
      frame: baseline,
      controllerPosition: try MachinePosition(x: 0, y: 0)
    ),
    postDrawing: SamePoseFrameSample(
      source: .simulated,
      frame: post,
      controllerPosition: try MachinePosition(x: 0, y: 0)
    ),
    region: PixelRect(x: 2, y: 2, width: 10, height: 10),
    intendedCameraPolylines: [intended],
    thresholds: InkPixelThresholds(minimumLuminanceDecrease: 20),
    controllerPositionToleranceMM: MachinePositionAcceptancePolicy.toleranceMM,
    alignmentSearchRadiusPixels: 1,
    maximumAlignmentShiftPixels: 1,
    maximumBackgroundMeanAbsoluteDifference: 1,
    observerRevision: try AlgorithmRevisionEvidence(
      component: "planned-drawing-observer",
      revision: "camera-composition-test-v1"
    )
  )
}

private func waitUntil(
  attempts: Int = 4_000,
  condition: @escaping @Sendable () async -> Bool
) async throws {
  for _ in 0..<attempts {
    if await condition() { return }
    await Task.yield()
  }
  throw CameraCompositionVisionLifecycleTestError.timedOut
}

private func waitUntilStableCap(
  _ conditionDescription: String,
  attempts: Int = 4_000,
  condition: @escaping @Sendable () async -> Bool
) async throws {
  for _ in 0..<attempts {
    if await condition() { return }
    try await Task.sleep(nanoseconds: 1_000_000)
  }
  throw CameraCompositionVisionLifecycleTestError.stableCapTimedOut(conditionDescription)
}

private enum CameraCompositionVisionLifecycleTestError: Error {
  case timedOut
  case stableCapTimedOut(String)
}


enum CanvasLeaseOutcome: String, CaseIterable, Sendable {
  case success, failure, cancelled
}

private final class CanvasFreshnessClock: @unchecked Sendable {
  private let lock = NSLock()
  private var value: UInt64 = 100

  var now: UInt64 { lock.withLock { value } }
  func set(_ newValue: UInt64) { lock.withLock { value = newValue } }
}

@MainActor
private func renderHeldCameraCanvas(
  _ application: PlotterApplicationRuntime, expectedFrame: StampedFrame, path: String
) async throws {
  _ = NSApplication.shared
  let view = WorkbenchCameraCanvas(application: application,
    semantic: application.testPlotterUIProjection().semantic,
    viewport: .constant(ActionSurfaceViewportState()),
    pendingDrawingPlacement: .constant(nil), pendingPointSelection: .constant(nil))
  let host = NSHostingView(rootView: view)
  let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 480),
    styleMask: [.borderless], backing: .buffered, defer: false)
  window.isReleasedWhenClosed = false
  window.contentView = host
  defer { window.close() }
  host.frame = NSRect(x: 0, y: 0, width: 640, height: 480)
  host.layoutSubtreeIfNeeded()
  try await Task.sleep(for: .milliseconds(120))
  host.layoutSubtreeIfNeeded()
  window.display()
  host.display()
  func frameLayers(in view: NSView) -> [CameraFrameLayerHost] {
    (view as? CameraFrameLayerHost).map { [$0] } ?? view.subviews.flatMap(frameLayers)
  }
  let layers = frameLayers(in: host)
  try #require(layers.count == 1)
  let cameraLayer = try #require(layers.first)
  let contents = try #require(cameraLayer.layer?.sublayers?.first?.contents)
  let renderedImage = contents as! CGImage
  // The actual native camera layer must contain our captured frame's pixels,
  // not the simulation fallback, whose image has a different geometry.
  #expect(renderedImage.width == expectedFrame.width)
  #expect(renderedImage.height == expectedFrame.height)
  let renderedBytes = try #require(renderedImage.dataProvider?.data) as Data
  #expect(renderedBytes == expectedFrame.bytes.data)
  let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
  host.cacheDisplay(in: host.bounds, to: bitmap)
  let bytes = try #require(bitmap.representation(using: .png, properties: [:]))
  try bytes.write(to: URL(fileURLWithPath: path))
}
