import Foundation
import Testing

@testable import PlotterApp

@Suite("Running-app preview performance gate")
struct RunningAppPreviewPerformanceGateTests {
  @Test("diagnostic mode requires explicit enablement and both output paths")
  func configurationIsOptIn() throws {
    #expect(RunningAppPreviewPerformanceConfiguration(arguments: []) == nil)
    #expect(RunningAppPreviewPerformanceConfiguration(arguments: [
      RunningAppPreviewPerformanceConfiguration.enabledArgument, "YES",
    ]) == nil)

    let configuration = try #require(RunningAppPreviewPerformanceConfiguration(arguments: [
      "AdaptivePlotter",
      RunningAppPreviewPerformanceConfiguration.enabledArgument, "yes",
      RunningAppPreviewPerformanceConfiguration.reportArgument, "/tmp/report.json",
      RunningAppPreviewPerformanceConfiguration.readyMarkerArgument, "/tmp/ready",
    ]))
    #expect(configuration.reportURL.path == "/tmp/report.json")
    #expect(configuration.readyMarkerURL.path == "/tmp/ready")
    #expect(configuration.scenario == "preview")
    #expect(configuration.durationSeconds == 12)
    let portrait = RunningAppPreviewPerformanceConfiguration(arguments: [
      RunningAppPreviewPerformanceConfiguration.enabledArgument, "YES",
      RunningAppPreviewPerformanceConfiguration.reportArgument, "/tmp/studio.json",
      RunningAppPreviewPerformanceConfiguration.readyMarkerArgument, "/tmp/studio-ready",
      RunningAppPreviewPerformanceConfiguration.scenarioArgument, "learned-portrait",
      RunningAppPreviewPerformanceConfiguration.durationArgument, "90",
      RunningAppPreviewPerformanceConfiguration.photoArgument, "/tmp/face.png",
    ])
    #expect(portrait?.scenario == "learned-portrait")
    #expect(portrait?.durationSeconds == 90)
    #expect(portrait?.portraitPhotoURL?.path == "/tmp/face.png")
  }

  @Test("physical mode requires an explicit photo and exact controller; preview remains nonphysical")
  func physicalConfigurationRequiresExplicitInputs() throws {
    let base = [RunningAppPreviewPerformanceConfiguration.enabledArgument, "YES",
      RunningAppPreviewPerformanceConfiguration.reportArgument, "/tmp/physical.json",
      RunningAppPreviewPerformanceConfiguration.readyMarkerArgument, "/tmp/physical-ready",
      RunningAppPreviewPerformanceConfiguration.scenarioArgument, "physical-portrait"]
    #expect(RunningAppPreviewPerformanceConfiguration(arguments: base) == nil)
    #expect(RunningAppPreviewPerformanceConfiguration(arguments: base + [
      RunningAppPreviewPerformanceConfiguration.photoArgument, "/tmp/face.png"]) == nil)
    let config = try #require(RunningAppPreviewPerformanceConfiguration(arguments: base + [
      RunningAppPreviewPerformanceConfiguration.photoArgument, "/tmp/face.png",
      RunningAppPreviewPerformanceConfiguration.controllerArgument, "/dev/cu.exact-controller"]))
    #expect(config.durationSeconds == 600)
    #expect(config.physicalControllerIdentifier == "/dev/cu.exact-controller")
    #expect(config.portraitPhotoURL?.path == "/tmp/face.png")
  }

  @Test("native workbench is an explicit app-host scenario independent of physical prerequisites")
  func nativeWorkbenchConfiguration() throws {
    let arguments = [RunningAppPreviewPerformanceConfiguration.enabledArgument, "YES",
      RunningAppPreviewPerformanceConfiguration.reportArgument, "/tmp/native.json",
      RunningAppPreviewPerformanceConfiguration.readyMarkerArgument, "/tmp/native-ready",
      RunningAppPreviewPerformanceConfiguration.scenarioArgument, "native-workbench"]
    let config = try #require(RunningAppPreviewPerformanceConfiguration(arguments: arguments))
    #expect(config.scenario == "native-workbench")
    #expect(config.durationSeconds == 180)
    #expect(config.physicalControllerIdentifier == nil)
    #expect(config.portraitPhotoURL == nil)
  }

  @Test("native workbench cannot pass missing body-width coverage, duplicate captures or uncorrelated input")
  func nativeWorkbenchProofRequirements() throws {
    let complete = completeNativeWorkbenchReport()
    #expect(complete.verificationFailures.isEmpty)
    var missingWidth = complete
    missingWidth.placements.removeAll { $0.panel == .portraitStudio && $0.width == 1_000 }
    #expect(!missingWidth.verificationFailures.isEmpty)
    var headerOnly = complete
    let first = headerOnly.placements[0]
    headerOnly.placements[0] = .init(panel: first.panel, slot: first.slot, width: first.width,
      header: first.header, body: first.header)
    #expect(headerOnly.verificationFailures.contains { $0.contains("substitutes a header") })
    var noNestedScroll = complete
    // Programmatic body reveal and genuine outer-wheel receipts remain present.
    // Neither can replace movement of the named inner clip by its native event.
    noNestedScroll.inputs = complete.inputs.map { sample in
      var sample = sample
      if sample.targetIdentifier == "workbench.scroll.inner", let evidence = sample.scrollEvidence {
        sample.scrollEvidence = .init(context: evidence.context, controlIdentifier: evidence.controlIdentifier,
          clipIdentity: "", outerClipIdentities: [], beforeBounds: evidence.beforeBounds,
          afterBounds: evidence.afterBounds, documentBounds: evidence.documentBounds)
      }
      return sample
    }
    #expect(noNestedScroll.verificationFailures.contains { $0.contains("Control-body") })
    var unchangedInner = complete
    unchangedInner.inputs = complete.inputs.map { sample in
      var sample = sample
      if let evidence = sample.scrollEvidence {
        sample.scrollEvidence = .init(context: evidence.context, controlIdentifier: evidence.controlIdentifier,
          clipIdentity: evidence.clipIdentity, outerClipIdentities: evidence.outerClipIdentities,
          beforeBounds: evidence.beforeBounds, afterBounds: evidence.beforeBounds, documentBounds: evidence.documentBounds)
      }
      return sample
    }
    #expect(unchangedInner.verificationFailures.contains { $0.contains("Control-body") })
    let videoIndex = try #require(complete.placements.firstIndex { $0.panel == .videoSettings })
    let video = complete.placements[videoIndex]
    var settingsOnly = complete
    settingsOnly.placements[videoIndex] = .init(panel: .videoSettings, slot: video.slot, width: video.width,
      header: video.header, body: .init(identifier: "workbench.video.settings", frame: video.body.frame,
        containingClipCount: 1, scrolledClipCount: 0, panelIdentifier: "workbench.panel.videoSettings", fitsEveryContainingClip: true))
    #expect(settingsOnly.verificationFailures.contains { $0.contains("substitutes a header") })
    var clippedCanvas = complete
    var clippedBody = video.body
    clippedBody.fitsEveryContainingClip = false
    clippedCanvas.placements[videoIndex] = .init(panel: .videoSettings, slot: video.slot, width: video.width,
      header: video.header, body: clippedBody)
    #expect(clippedCanvas.verificationFailures.contains { $0.contains("substitutes a header") })
    var duplicateImages = complete
    duplicateImages.bitmaps = Array(repeating: "same.png", count: 8)
    #expect(!duplicateImages.verificationFailures.isEmpty)
    var wrongEvent = complete
    wrongEvent.inputs[0].handledEventIdentity = 9_999
    #expect(wrongEvent.verificationFailures.contains { $0.contains("event correlation") })
    var lostInput = complete
    lostInput.inputs.removeLast()
    #expect(lostInput.verificationFailures.contains { $0.contains("reconcile") })
    var changedArtifacts = complete
    changedArtifacts.acceptedArtifactsUnchanged = false
    #expect(!changedArtifacts.verificationFailures.isEmpty)
    var onlyOn = complete
    onlyOn.learningStates = [true, true]
    #expect(!onlyOn.verificationFailures.isEmpty)
    let json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(complete)) as? [String: Any])
    #expect(json["schema"] as? String == "adaptiveplotter.native-workbench.v2")
    #expect((json["provenance"] as? String)?.contains("simulated startup") == true)
  }

  @Test("native resize has an available direction at the production minimum and both tested widths")
  func nativeResizeRespectsMinimumAndScreen() {
    let minimum = CGSize(width: 1_000, height: 700)
    let screen = CGRect(x: 0, y: 0, width: 2_000, height: 1_200)
    #expect(WorkbenchNativeResizeGeometry.delta(content: minimum, minimum: minimum,
      window: CGRect(x: 100, y: 100, width: 1_000, height: 728), visibleScreen: screen)
      == CGSize(width: 45, height: 25))
    #expect(WorkbenchNativeResizeGeometry.delta(content: CGSize(width: 1_600, height: 700), minimum: minimum,
      window: CGRect(x: 100, y: 100, width: 1_600, height: 728), visibleScreen: screen)
      == CGSize(width: -45, height: 25))
    // At the lower screen edge only the outward horizontal component is feasible.
    #expect(WorkbenchNativeResizeGeometry.delta(content: minimum, minimum: minimum,
      window: CGRect(x: 0, y: 0, width: 1_000, height: 728), visibleScreen: screen)
      == CGSize(width: 45, height: 0))
    #expect(WorkbenchNativeResizeGeometry.delta(content: minimum, minimum: minimum,
      window: CGRect(x: 0, y: 0, width: 1_000, height: 728),
      visibleScreen: CGRect(x: 0, y: 0, width: 1_000, height: 728)) == nil)
  }

  @Test("native wheel chooses available movement after setup has revealed the bottom control")
  func nativeWheelDirectionUsesMeasuredBounds() {
    let document = CGRect(x: 0, y: 0, width: 300, height: 600)
    let top = CGRect(x: 0, y: 0, width: 300, height: 200)
    let bottom = CGRect(x: 0, y: 400, width: 300, height: 200)
    #expect(WorkbenchNativeScrollEvidence.wheelDelta(clip: top, document: document, documentIsFlipped: true) == -120)
    #expect(WorkbenchNativeScrollEvidence.wheelDelta(clip: bottom, document: document, documentIsFlipped: true) == 120)
    #expect(WorkbenchNativeScrollEvidence.wheelDelta(clip: top, document: document, documentIsFlipped: false) == 120)
    #expect(WorkbenchNativeScrollEvidence.wheelDelta(clip: bottom, document: document, documentIsFlipped: false) == -120)
    #expect(WorkbenchNativeScrollEvidence.wheelDelta(clip: document, document: document, documentIsFlipped: true) == nil)
  }

  private func completeNativeWorkbenchReport() -> NativeWorkbenchReport {
    var result = NativeWorkbenchReport()
    for panel in WorkbenchPanel.allCases {
      for slot in WorkbenchSlot.allCases {
        for width in [1_000, 1_600] {
          result.placements.append(.init(panel: panel, slot: slot, width: width,
            header: .init(identifier: "workbench.hide.\(panel.rawValue)",
              frame: CGRect(x: 20, y: 20, width: 30, height: 30), containingClipCount: 1, scrolledClipCount: 0,
              panelIdentifier: "workbench.panel.\(panel.rawValue)", fitsEveryContainingClip: true),
            body: .init(identifier: NativeWorkbenchReport.bodyControlIdentifier(for: panel),
              frame: CGRect(x: 20, y: 60, width: 150, height: 30), containingClipCount: 2, scrolledClipCount: 1,
              panelIdentifier: "workbench.panel.\(panel.rawValue)", fitsEveryContainingClip: true)))
        }
      }
    }
    result.bitmaps = (0..<8).map { "layout-\($0).png" }
    result.learningStates = [false, true]
    result.acceptedArtifactsUnchanged = true
    result.windowPreferencesUnchanged = true
    result.applicationWasActive = true
    result.stopWasVisible = true
    result.canvasOnlyWidths = [1_000, 1_600]
    result.viewMenuWasPresent = true
    for id in NativeWorkbenchReport.requiredControlIdentifiers {
      let count = id == "learning.mode" ? 2 : 8
      result.nativeCounts[id] = .init(posted: count, dispatched: count, handled: count, acknowledged: count)
      for index in 0..<count {
        let identity = Int64(result.inputs.count + 1)
        var sample = WorkbenchNativeInputSample(targetIdentifier: id, postedUptimeSeconds: 10,
          eventUptimeSeconds: 10, postedEventIdentity: identity, dispatchedEventIdentity: identity,
          handledEventIdentity: identity, dispatchEntryUptimeSeconds: 10.01, handlerUptimeSeconds: 10.02,
          handlerLatencyMilliseconds: 20, visibleAcknowledgmentLatencyMilliseconds: 30)
        if id == "workbench.scroll.inner" {
          let contexts = WorkbenchSlot.allCases.flatMap { slot in [1_000, 1_600].map { "\(slot.rawValue).\($0)" } }
          sample.scrollEvidence = .init(context: contexts[index], controlIdentifier: "drawing.draw",
            clipIdentity: "inner-\(index)", outerClipIdentities: ["outer-\(index)"],
            beforeBounds: CGRect(x: 0, y: 400, width: 300, height: 200),
            afterBounds: CGRect(x: 0, y: 280, width: 300, height: 200),
            documentBounds: CGRect(x: 0, y: 0, width: 300, height: 600))
        }
        result.inputs.append(sample)
      }
    }
    return result
  }

  @Test("continuation cannot be reused for another process, executable, stage, plan, or review")
  func physicalContinuationBindsReviewedCandidate() throws {
    let session = UUID(), nonce = UUID()
    let expected = PhysicalPortraitContinuation(sessionID: session, executableSHA256: "candidate-A",
      stage: "portrait-1", planSHA256: "plan-A", nonce: nonce)
    let decoded = try JSONDecoder().decode(PhysicalPortraitContinuation.self, from: JSONEncoder().encode(expected))
    #expect(decoded == expected)
    for alternative in [
      PhysicalPortraitContinuation(sessionID: UUID(), executableSHA256: "candidate-A", stage: "portrait-1", planSHA256: "plan-A", nonce: nonce),
      PhysicalPortraitContinuation(sessionID: session, executableSHA256: "candidate-B", stage: "portrait-1", planSHA256: "plan-A", nonce: nonce),
      PhysicalPortraitContinuation(sessionID: session, executableSHA256: "candidate-A", stage: "portrait-2", planSHA256: "plan-A", nonce: nonce),
      PhysicalPortraitContinuation(sessionID: session, executableSHA256: "candidate-A", stage: "portrait-1", planSHA256: "plan-B", nonce: nonce),
      PhysicalPortraitContinuation(sessionID: session, executableSHA256: "candidate-A", stage: "portrait-1", planSHA256: "plan-A", nonce: UUID()),
    ] { #expect(alternative != expected) }
  }

  @Test("a controller connection or duplicate record cannot stand in for two physical portrait trials")
  func physicalReportDoesNotPromoteIncompleteEvidence() throws {
    var report = PhysicalPortraitReport(sessionID: UUID(), executablePath: "/test/app",
      executableSHA256: "candidate", processID: 42, photoPath: "/test/face.png", photoSHA256: "photo")
    report.state = "completed"
    report.planHashes = ["one", "two"]
    report.recordIDs = ["same", "same"]
    report.manualStopCapabilityID = UUID()
    report.drawingStopCapabilities = [UUID(), UUID()]
    let failures = report.verificationFailures.joined(separator: " ")
    #expect(failures.contains("controller settlement"))
    #expect(failures.contains("Two distinct"))
    #expect(failures.contains("drawing.draw"))
    #expect(failures.contains("workbench.stop"))
    let encoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(report)) as? [String: Any]
    #expect(encoded?["schema"] as? String == "adaptiveplotter.physical-portrait.v1")
    #expect(encoded?["recordIDs"] as? [String] == report.recordIDs)
    #expect((encoded?["provenance"] as? String)?.contains("human attendance") == true)
  }

  @Test("runtime report retains the raw evidence consumed by the shell gate")
  func reportRoundTrips() throws {
    let report = RunningAppPreviewPerformanceReport(
      schema: RunningAppPreviewPerformanceReport.schema,
      measurementDurationSeconds: 12,
      previewPublicationCount: 121,
      previewFramesAdvanced: 120,
      previewStartSequence: 40,
      previewEndSequence: 160,
      previewSourceWasLive: true,
      previewConfigurationRemainedStable: true,
      semanticPresentationRevisionDelta: 0,
      rootProjectionBuildCountDelta: 0,
      drawingDraftSynchronizationCountDelta: 0,
      mainActorSchedulingLatencyMilliseconds: [0.2, 0.3, 0.4]
    )

    let decoded = try JSONDecoder().decode(
      RunningAppPreviewPerformanceReport.self,
      from: JSONEncoder().encode(report)
    )
    #expect(decoded == report)
  }

  @Test("an idle preview with excellent scheduling cannot pass the learned portrait workload")
  func idlePreviewIsNotPortraitProof() {
    var report = completePortraitReport()
    report.appliedCheckpointID = nil
    report.portraitProgramHash = nil
    report.drawingPlanWasAvailable = false
    report.measuredAnalysisFrameDelta = 0
    report.completedCameraSwitchCount = 0
    report.nativeInputSamples = []
    let failures = report.workloadFailures.joined(separator: " ")
    #expect(failures.contains("saved training"))
    #expect(failures.contains("dense portrait"))
    #expect(failures.contains("analysis"))
    #expect(failures.contains("twenty"))
    #expect(failures.contains("native"))
    #expect(report.mainActorSchedulingLatencyMilliseconds.allSatisfy { $0 < 1 })
  }

  @Test("dropped native clicks and hidden plotter work remain failures despite other passing evidence")
  func missingAcknowledgmentAndHiddenAnalysisFail() {
    var report = completePortraitReport()
    #expect(report.workloadFailures.isEmpty)
    report.submittedNativeInputCount += 1
    report.suspendedPlotterAnalyzedFrameDelta = 1
    report.passivePanelTextChanged = ["motion"]
    let failures = report.workloadFailures.joined(separator: " ")
    #expect(failures.contains("lacks delivery"))
    #expect(failures.contains("continued"))
    #expect(failures.contains("panel text"))
  }

  @Test("a partial saved prefix, one scan, or Motion-only input cannot satisfy the integrated workload")
  func integratedWorkloadRequiresIndependentReceipts() {
    var report = completePortraitReport()
    report.completeAcceptedLearningWasRetained = false
    report.acceptedBorderRecordID = nil
    report.quietAnalysisWindows = [.init(durationSeconds: 60, completedFrames: 1)]
    report.nativeInputCounts = ["workbench.hide.motion": .init(posted: 100, dispatched: 100, handled: 100, acknowledged: 100)]
    report.retrospectiveConstraintCount = 0
    let failures = report.workloadFailures.joined(separator: " ")
    #expect(failures.contains("Border completion"))
    #expect(failures.contains("five measured"))
    #expect(failures.contains("portrait.showOnPlotter"))
    #expect(failures.contains("ordinary drawing"))
  }

  @Test("source event time cannot substitute for dispatch-entry and control handler receipts")
  func dispatchTimeMustBeIndependentlySampled() {
    var report = completePortraitReport()
    report.nativeInputSamples[0].dispatchEntryUptimeSeconds = 0
    #expect(report.workloadFailures.contains { $0.contains("dispatch entry") })
    report = completePortraitReport()
    report.nativeInputCounts["drawing.scale"]?.handled = 0
    #expect(report.workloadFailures.contains { $0.contains("drawing.scale") })
  }

  private func completePortraitReport() -> RunningAppPreviewPerformanceReport {
    var report = RunningAppPreviewPerformanceReport(schema: RunningAppPreviewPerformanceReport.schema,
      measurementDurationSeconds: 60, previewPublicationCount: 601, previewFramesAdvanced: 600,
      previewStartSequence: 1, previewEndSequence: 601, previewSourceWasLive: true,
      previewConfigurationRemainedStable: true, semanticPresentationRevisionDelta: 0,
      rootProjectionBuildCountDelta: 0, drawingDraftSynchronizationCountDelta: 0,
      mainActorSchedulingLatencyMilliseconds: [0.1, 0.2])
    report.scenario = "learned-portrait"
    report.appliedCheckpointID = UUID().uuidString
    report.completeAcceptedLearningWasRetained = true
    report.acceptedBorderRecordID = UUID().uuidString
    report.quietAnalysisWindows = Array(repeating: .init(durationSeconds: 2, completedFrames: 3), count: 8)
    report.retrospectiveRecordIDs = [UUID().uuidString]
    report.retrospectiveConstraintCount = 200
    report.portraitMaximumConcurrentExpensiveJobs = 1
    report.nativeInputCounts = Dictionary(uniqueKeysWithValues: RunningAppPreviewPerformanceReport.requiredPortraitControls.map {
      let count = $0.hasPrefix("workbench.camera.") ? 10 : 1
      return ($0, WorkbenchNativeInputCounts(posted: count, dispatched: count, handled: count, acknowledged: count))
    })
    report.portraitProgramHash = "portrait-fixture-hash"
    report.portraitStrokeCount = 200
    report.drawingPlanWasAvailable = true
    report.targetWasVisible = true
    report.automaticAnalysisWasRunning = true
    report.measuredAnalysisFrameDelta = 40
    report.completedCameraSwitchCount = 20
    report.cameraSwitchReceipts = (0..<20).map { index in
      .init(role: index.isMultiple(of: 2) ? .portrait : .plotter, deviceID: "fixture-\(index % 2)",
        configurationID: UUID().uuidString, configurationChanged: true,
        firstSequence: 1, lastSequence: 2, firstCaptureNanoseconds: 10, lastCaptureNanoseconds: 20)
    }
    report.portraitMaximumConcurrentWorkers = 1
    report.portraitSettledWorkers = 2
    report.passivePanelsObserved = WorkbenchPanel.allCases.map(\.rawValue)
    report.stopWasPresent = true
    report.nativeInputSamples = RunningAppPreviewPerformanceReport.requiredPortraitControls.flatMap { identifier in
      Array<WorkbenchNativeInputSample>(repeating: .init(targetIdentifier: identifier,
      postedUptimeSeconds: 10, eventUptimeSeconds: 10,
      postedEventIdentity: 42, dispatchedEventIdentity: 42, handledEventIdentity: 42,
      dispatchEntryUptimeSeconds: 10.005, handlerUptimeSeconds: 10.01,
        handlerLatencyMilliseconds: 10, visibleAcknowledgmentLatencyMilliseconds: 20),
        count: identifier.hasPrefix("workbench.camera.") ? 10 : 1) }
    report.submittedNativeInputCount = report.nativeInputSamples.count
    report.deliveredNativeInputCount = report.nativeInputSamples.count
    report.acknowledgedNativeInputCount = report.nativeInputSamples.count
    return report
  }

  @Test("unrelated or delayed preceding events cannot identify a pending native control")
  func unrelatedEventsCannotSatisfyReceipt() {
    let correlation = WorkbenchNativeEventCorrelation(expectedIdentity: 42)
    #expect(!correlation.accepts(nil))
    #expect(!correlation.accepts(0))
    #expect(!correlation.accepts(41))
    #expect(correlation.accepts(42))
    var report = completePortraitReport()
    report.nativeInputSamples[0].dispatchedEventIdentity = 41
    #expect(report.workloadFailures.contains { $0.contains("identify the posted event") })
    report = completePortraitReport()
    report.nativeInputSamples[0].eventUptimeSeconds = nil
    #expect(report.workloadFailures.contains { $0.contains("identify the posted event") })
    report = completePortraitReport()
    report.nativeInputSamples[0].handledEventIdentity = 41
    #expect(report.workloadFailures.contains { $0.contains("identify the posted event") })
  }

  @Test("retained Canvas repainting is diagnostic while semantic, build and text churn still fail")
  func rawCanvasRepaintDoesNotFailQuietWindow() throws {
    var report = completePortraitReport()
    report.quietAnalysisWindows[0].overlayCanvasDrawCountDelta = 23
    #expect(!report.quietAnalysisWindows[0].hasChurn)
    #expect(report.workloadFailures.isEmpty)
    let copy = try JSONDecoder().decode(RunningAppPreviewPerformanceReport.self, from: JSONEncoder().encode(report))
    #expect(copy.quietAnalysisWindows[0].overlayCanvasDrawCountDelta == 23)
    report.quietAnalysisWindows[0].semanticRevisionDelta = 1
    #expect(!report.workloadFailures.isEmpty)
    report.quietAnalysisWindows[0].semanticRevisionDelta = 0
    report.quietAnalysisWindows[0].rootBuildCountDelta = 1
    #expect(!report.workloadFailures.isEmpty)
    report.quietAnalysisWindows[0].rootBuildCountDelta = 0
    report.quietAnalysisWindows[0].draftSynchronizationCountDelta = 1
    #expect(!report.workloadFailures.isEmpty)
    report.quietAnalysisWindows[0].draftSynchronizationCountDelta = 0
    report.quietAnalysisWindows[0].overlayCanvasBuildCountDelta = 1
    #expect(!report.workloadFailures.isEmpty)
    report.quietAnalysisWindows[0].overlayCanvasBuildCountDelta = 0
    report.quietAnalysisWindows[0].changedPanels = ["motion"]
    #expect(!report.workloadFailures.isEmpty)
  }

  @Test("later quiet windows retain transient sibling updates even when endpoint text agrees")
  func postSwitchTransientChurnFails() {
    var panels = WorkbenchQuietPanelObservation()
    panels.observe(["guidedLearning": ["Ready"]])
    panels.observe(["guidedLearning": ["Frame 12"]])
    panels.observe(["guidedLearning": ["Ready"]])
    #expect(panels.changed == ["guidedLearning"])
    var report = completePortraitReport()
    report.quietAnalysisWindows[1].context = "camera switch"
    report.quietAnalysisWindows[1].changedPanels = panels.changed.sorted()
    #expect(report.workloadFailures.contains { $0.contains("Quiet analysis after camera switch") })
    report = completePortraitReport()
    report.quietAnalysisWindows[5].context = "retrospective analysis"
    report.quietAnalysisWindows[5].semanticRevisionDelta = 2
    #expect(report.workloadFailures.contains { $0.contains("Quiet analysis after retrospective analysis") })
  }
}
