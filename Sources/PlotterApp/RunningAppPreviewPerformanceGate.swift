import AppKit
import Foundation
import PlotterEpisodeModel
import PlotterModel
import PlotterRuntime
import PlotterUI
import SwiftUI

struct RunningAppPreviewPerformanceConfiguration: Equatable, Sendable {
  static let enabledArgument = "-AdaptivePlotterPreviewPerformanceGate"
  static let reportArgument = "-AdaptivePlotterPreviewPerformanceReport"
  static let readyMarkerArgument = "-AdaptivePlotterPreviewPerformanceReadyMarker"
  static let scenarioArgument = "-AdaptivePlotterPreviewPerformanceScenario"
  static let durationArgument = "-AdaptivePlotterPreviewPerformanceDuration"
  static let photoArgument = "-AdaptivePlotterPreviewPerformancePortraitPhoto"
  static let controllerArgument = "-AdaptivePlotterPhysicalController"

  let reportURL: URL
  let readyMarkerURL: URL
  let scenario: String
  let durationSeconds: Double
  let portraitPhotoURL: URL?
  let physicalControllerIdentifier: String?

  init?(arguments: [String]) {
    guard Self.value(after: Self.enabledArgument, in: arguments)?
      .caseInsensitiveCompare("YES") == .orderedSame,
      let reportPath = Self.value(after: Self.reportArgument, in: arguments),
      let readyMarkerPath = Self.value(after: Self.readyMarkerArgument, in: arguments)
    else { return nil }
    reportURL = URL(fileURLWithPath: reportPath)
    readyMarkerURL = URL(fileURLWithPath: readyMarkerPath)
    scenario = Self.value(after: Self.scenarioArgument, in: arguments) ?? "preview"
    guard ["preview", "learned-portrait", "physical-portrait", "native-workbench"].contains(scenario) else { return nil }
    durationSeconds = Self.value(after: Self.durationArgument, in: arguments).flatMap(Double.init)
      ?? (scenario == "physical-portrait" ? 600 : scenario == "learned-portrait" ? 60 : scenario == "native-workbench" ? 180 : 12)
    guard durationSeconds.isFinite, durationSeconds >= 1, durationSeconds <= 600 else { return nil }
    portraitPhotoURL = Self.value(after: Self.photoArgument, in: arguments).map { URL(fileURLWithPath: $0) }
    physicalControllerIdentifier = Self.value(after: Self.controllerArgument, in: arguments)
    if scenario == "physical-portrait" {
      guard portraitPhotoURL != nil, let physicalControllerIdentifier, !physicalControllerIdentifier.isEmpty else { return nil }
    }
  }

  private static func value(after argument: String, in arguments: [String]) -> String? {
    guard let index = arguments.firstIndex(of: argument),
      arguments.indices.contains(index + 1)
    else { return nil }
    return arguments[index + 1]
  }
}

struct RunningAppPreviewPerformanceReport: Codable, Equatable, Sendable {
  static let schema = "adaptiveplotter.running-app-preview-runtime.v2"

  #if DEBUG
  var buildConfiguration = "debug"
  #else
  var buildConfiguration = "release"
  #endif
  let schema: String
  let measurementDurationSeconds: Double
  let previewPublicationCount: UInt64
  let previewFramesAdvanced: UInt64
  let previewStartSequence: UInt64?
  let previewEndSequence: UInt64?
  let previewSourceWasLive: Bool
  let previewConfigurationRemainedStable: Bool
  let semanticPresentationRevisionDelta: UInt64
  let rootProjectionBuildCountDelta: Int
  let drawingDraftSynchronizationCountDelta: Int
  var overlayPresentationRevisionDelta: UInt64 = 0
  var overlayCanvasDrawCountDelta: Int = 0
  var overlayCanvasBuildCountDelta: Int = 0
  var scenario = "preview"
  var targetWasVisible = false
  var drawingPlanWasAvailable: Bool = false
  var automaticAnalysisWasRunning: Bool = false
  var appliedCheckpointID: String?
  var completeAcceptedLearningWasRetained = false
  var acceptedBorderRecordID: String?
  var quietAnalysisWindows: [PlotterAnalysisPerformanceWindow] = []
  var nativeInputCounts: [String: WorkbenchNativeInputCounts] = [:]
  var retrospectiveRecordIDs: [String] = []
  var retrospectiveConstraintCount = 0
  var portraitMaximumConcurrentExpensiveJobs = 0
  var portraitProgramHash: String?
  var portraitStrokeCount = 0
  var portraitInputSource: String?
  var completedCameraSwitchCount = 0
  var cameraSwitchDurationsMilliseconds: [Double] = []
  var cameraSwitchReceipts: [WorkbenchCameraSwitchReceipt] = []
  var suspendedPlotterAnalyzedFrameDelta: UInt64 = 0
  var measuredAnalysisFrameDelta: UInt64 = 0
  var portraitMaximumConcurrentWorkers = 0
  var portraitSettledWorkers = 0
  var passivePanelTextChanged: [String] = []
  var passivePanelsObserved: [String] = []
  var stopWasPresent = false
  var failures: [String] = []
  var nativeInputProvenance = "Synthesized CGEvent mouse/menu-key input posted to this process; NSEvent dispatch-entry clock; existing typed control handler clock; unclipped native hit target and accessibility acknowledgment after display. Not attended human input."
  var passivePanelObservationProvenance = "Accessibility-tree static text sampled every 50 ms in initial and post-action quiet windows, retaining transient samples; monotonic semantic/root/draft/overlay counters cover changes between samples. Native hit tests establish control visibility separately."
  var nativeInputSamples: [WorkbenchNativeInputSample] = []
  var submittedNativeInputCount = 0
  var deliveredNativeInputCount = 0
  var acknowledgedNativeInputCount = 0
  let mainActorSchedulingLatencyMilliseconds: [Double]

  var workloadFailures: [String] {
    var reasons = failures
    if !passivePanelTextChanged.isEmpty { reasons.append("Passive video changed panel text: \(passivePanelTextChanged.joined(separator: ", ")).") }
    if Set(passivePanelsObserved) != Set(WorkbenchPanel.allCases.map(\.rawValue)) {
      reasons.append("The gate did not observe every dock control and the Portrait Studio workspace.")
    }
    if !stopWasPresent { reasons.append("The native workbench Stop control was not present.") }
    if nativeInputSamples.isEmpty { reasons.append("No native control input and visible acknowledgment was measured.") }
    if submittedNativeInputCount != deliveredNativeInputCount
      || deliveredNativeInputCount != acknowledgedNativeInputCount
      || acknowledgedNativeInputCount != nativeInputSamples.count
    { reasons.append("A submitted native input lacks delivery or visible acknowledgment.") }
    if nativeInputCounts.values.reduce(0, { $0 + $1.posted }) != submittedNativeInputCount
      || nativeInputCounts.values.reduce(0, { $0 + $1.acknowledged }) != nativeInputSamples.count {
      reasons.append("Per-control native counts do not reconcile with all submitted inputs and raw receipts.")
    }
    if nativeInputSamples.contains(where: {
      $0.dispatchEntryUptimeSeconds < $0.postedUptimeSeconds
        || $0.handlerUptimeSeconds < $0.dispatchEntryUptimeSeconds
    }) { reasons.append("Native input timestamps do not establish posting, dispatch entry, and handler ordering.") }
    if nativeInputSamples.contains(where: {
      let correlation = WorkbenchNativeEventCorrelation(expectedIdentity: $0.postedEventIdentity)
      return $0.eventUptimeSeconds == nil || !correlation.accepts($0.dispatchedEventIdentity)
        || !correlation.accepts($0.handledEventIdentity)
    }) { reasons.append("Native dispatch and handler receipts do not identify the posted event.") }
    for window in quietAnalysisWindows where window.hasChurn {
      reasons.append("Quiet analysis after \(window.context) changed semantic/root/draft/overlay state or panel text: \(window.changedPanels.joined(separator: ", ")).")
    }
    guard scenario == "learned-portrait" else { return reasons }
    if appliedCheckpointID == nil { reasons.append("Accepted saved training was not applied.") }
    if !completeAcceptedLearningWasRetained || acceptedBorderRecordID == nil {
      reasons.append("Complete accepted Learning including retained Border completion was not demonstrated.")
    }
    if portraitProgramHash == nil || portraitStrokeCount < 100 || !drawingPlanWasAvailable || !targetWasVisible {
      reasons.append("A dense portrait target and immutable drawing plan were not available.")
    }
    if !automaticAnalysisWasRunning || measuredAnalysisFrameDelta == 0
      || quietAnalysisWindows.filter({ $0.durationSeconds >= 1 && $0.completedFrames >= 1 }).count < 5
      || (quietAnalysisWindows.first?.completedFrames ?? 0) < 2 {
      reasons.append("Repeated real plotter analysis did not progress across five measured active-camera windows.")
    }
    if completedCameraSwitchCount < 20 { reasons.append("Fewer than twenty selected-camera switches completed.") }
    if cameraSwitchReceipts.count != completedCameraSwitchCount || cameraSwitchReceipts.contains(where: {
      !$0.configurationChanged || $0.lastSequence <= $0.firstSequence || $0.lastCaptureNanoseconds <= $0.firstCaptureNanoseconds
    }) { reasons.append("Completed camera switches lack new capture generations with advancing live frames.") }
    for role in WorkbenchCameraRole.allCases {
      if nativeInputCounts["workbench.camera.\(role.rawValue)"]?.acknowledged
        != cameraSwitchReceipts.filter({ $0.role == role }).count {
        reasons.append("Native \(role.rawValue) input receipts do not reconcile with settled capture generations.")
      }
    }
    if suspendedPlotterAnalyzedFrameDelta != 0 { reasons.append("Plotter analysis continued while portrait capture was selected.") }
    if portraitMaximumConcurrentWorkers != 1 || portraitSettledWorkers == 0 { reasons.append("Portrait worker settlement or bounded concurrency was not demonstrated.") }
    if portraitMaximumConcurrentExpensiveJobs != 1 { reasons.append("The total portrait acquisition/render concurrency bound was not demonstrated.") }
    for id in Self.requiredPortraitControls {
      guard let count = nativeInputCounts[id], count.posted > 0,
        count.posted == count.dispatched, count.posted == count.handled, count.posted == count.acknowledged else {
        reasons.append("Required native control \(id) was not posted, dispatched, handled, and visibly acknowledged.")
        continue
      }
    }
    if retrospectiveRecordIDs.isEmpty || retrospectiveConstraintCount == 0 {
      reasons.append("No existing ordinary drawing supplied reusable retrospective residuals; complete and observe an ordinary drawing under the current calibration, then rerun.")
    }
    if measurementDurationSeconds < 60 { reasons.append("The learned-portrait workload did not run for sixty seconds.") }
    return reasons
  }

  static let requiredPortraitControls = ["workbench.camera.portrait", "workbench.camera.plotter",
    "portrait.adjustment.Detail", "portrait.showOnPlotter", "drawing.scale", "drawing.rotation", "drawing.fit",
    "workbench.toggle.motion", "workbench.scroll", "workbench.resize", "learning.analyzeDrawings"]
      + [PortraitVectorPreset.fine, .balanced].map { "portrait.preset.\($0.rawValue)" }
}

struct PlotterAnalysisPerformanceWindow: Codable, Equatable, Sendable {
  let durationSeconds: Double
  let completedFrames: UInt64
  var context = "initial setup"
  var semanticRevisionDelta: UInt64 = 0
  var rootBuildCountDelta = 0
  var draftSynchronizationCountDelta = 0
  var overlayRevisionDelta: UInt64 = 0
  var overlayCanvasDrawCountDelta = 0
  var overlayCanvasBuildCountDelta = 0
  var changedPanels: [String] = []
  var panelSampleCount = 0
  var hasChurn: Bool {
    semanticRevisionDelta != 0 || rootBuildCountDelta != 0 || draftSynchronizationCountDelta != 0
      || overlayRevisionDelta != 0
      || overlayCanvasBuildCountDelta != 0 || !changedPanels.isEmpty
  }
}

struct WorkbenchQuietPanelObservation {
  private(set) var baseline: [String: [String]]?
  private(set) var changed = Set<String>()
  private(set) var sampleCount = 0
  mutating func observe(_ text: [String: [String]]) {
    sampleCount += 1
    guard let baseline else { self.baseline = text; return }
    for panel in Set(baseline.keys).union(text.keys) where baseline[panel] != text[panel] {
      changed.insert(panel)
    }
  }
}

struct WorkbenchCameraSwitchReceipt: Codable, Equatable, Sendable {
  let role: WorkbenchCameraRole
  let deviceID: String
  let configurationID: String
  let configurationChanged: Bool
  let firstSequence: UInt64
  let lastSequence: UInt64
  let firstCaptureNanoseconds: UInt64
  let lastCaptureNanoseconds: UInt64
}

/// Opt-in instrumentation for the repository's signed-app performance gate.
/// The learned-portrait scenario applies the existing saved package and builds
/// a real portrait target. It never submits controller, motion, Pen, or Draw.
@MainActor
enum RunningAppPreviewPerformanceGate {
  private static let previewStartupTimeout: Duration = .seconds(15)
  private static let warmupDuration: Duration = .seconds(3)
  private static let interactionProbeInterval: Duration = .milliseconds(100)

  static var isRequested: Bool {
    RunningAppPreviewPerformanceConfiguration(arguments: CommandLine.arguments) != nil
  }

  static var usesSimulatedWorkbench: Bool {
    RunningAppPreviewPerformanceConfiguration(arguments: CommandLine.arguments)?.scenario == "native-workbench"
  }

  static func runIfRequested(
    application: PlotterApplicationRuntime,
    revealPanel: @escaping @MainActor (WorkbenchPanel) -> Void,
    workbenchLayout: Binding<WorkbenchLayoutState>,
    arguments: [String] = CommandLine.arguments
  ) async {
    guard let configuration = RunningAppPreviewPerformanceConfiguration(arguments: arguments)
    else { return }

    if configuration.scenario == "native-workbench" {
      await runNativeWorkbench(application: application, configuration: configuration, layout: workbenchLayout)
      return
    }

    if configuration.scenario == "physical-portrait" {
      await runPhysicalPortrait(application: application, configuration: configuration, revealPanel: revealPanel)
      return
    }

    let report = await measure(
      application: application,
      configuration: configuration,
      revealPanel: revealPanel
    )
    do {
      try write(report, to: configuration.reportURL)
    } catch {
      FileHandle.standardError.write(Data(
        "Could not write preview performance report: \(error)\n".utf8
      ))
    }
    await application.shutdown()
    NSApplication.shared.terminate(nil)
  }

  private static func measure(
    application: PlotterApplicationRuntime,
    configuration: RunningAppPreviewPerformanceConfiguration,
    revealPanel: @escaping @MainActor (WorkbenchPanel) -> Void
  ) async -> RunningAppPreviewPerformanceReport {
    let clock = ContinuousClock()
    let startupDeadline = clock.now.advanced(by: previewStartupTimeout)
    while application.previewIsolationDiagnostics.latestPreviewSequence == nil,
      clock.now < startupDeadline
    {
      try? await clock.sleep(for: .milliseconds(100))
    }
    if application.previewIsolationDiagnostics.latestPreviewSequence != nil {
      try? await clock.sleep(for: warmupDuration)
    }
    var workload = PortraitPerformanceWorkload()
    let originalOverlays = application.observationConfigurationProjection.enabledOverlays
    if configuration.scenario == "learned-portrait" {
      do { try await preparePortraitWorkload(application, configuration: configuration, workload: &workload) }
      catch { workload.failures.append(error.localizedDescription) }
    }
    // The authoring workspace and dock controls occupy different screens.
    // Observe each real surface while it is visible, rather than claiming that
    // hidden or unmounted controls were included in one accessibility snapshot.
    var observedPanels = Set<String>()
    var passiveChanges = Set<String>()
    for panel in WorkbenchPanel.allCases {
      revealPanel(panel)
      await application.portraitStudio.awaitRendering()
      try? await clock.sleep(for: .milliseconds(150))
      var observation = WorkbenchQuietPanelObservation()
      for _ in 0..<6 {
        let text = RunningAppNativeInputProbe.panelText()
        observedPanels.formUnion(text.keys)
        observation.observe(text)
        try? await clock.sleep(for: .milliseconds(50))
      }
      passiveChanges.formUnion(observation.changed)
    }
    revealPanel(.guidedLearning)
    try? await clock.sleep(for: warmupDuration)
    let analysisStart = await analysisCount(application)

    // Snapshot deltas without clearing warmed presentation caches. The test
    // reset helper deliberately invalidates caches and would manufacture an
    // overlay rebuild on the first measured frame.
    let start = application.previewIsolationDiagnostics
    do {
      try Data("ready\n".utf8).write(to: configuration.readyMarkerURL, options: .atomic)
    } catch {
      FileHandle.standardError.write(Data(
        "Could not write preview performance ready marker: \(error)\n".utf8
      ))
    }

    let measurementDuration = Duration.seconds(configuration.durationSeconds)
    let interactionProbe = Task.detached(priority: .userInitiated) {
      await interactionLatencySamples(
        duration: measurementDuration,
        interval: interactionProbeInterval
      )
    }
    let panelsBefore = RunningAppNativeInputProbe.panelText()
    let measurementStarted = clock.now
    let initialQuiet = await observeQuietAnalysis(application, duration: min(6, configuration.durationSeconds / 3), context: "initial setup")
    let panelsAfter = RunningAppNativeInputProbe.panelText()
    let quietEnd = application.previewIsolationDiagnostics
    workload.analysisWindows.append(initialQuiet)
    let probe = RunningAppNativeInputProbe()
    probe.install()
    var nativeSamples: [WorkbenchNativeInputSample] = []
    let deadline = measurementStarted.advanced(by: measurementDuration)
    while clock.now < deadline {
      do {
        if configuration.scenario == "learned-portrait", workload.switchDurations.count < 20 {
          try await measureCameraSwitch(application, probe: probe, revealPanel: revealPanel,
            samples: &nativeSamples, workload: &workload)
        } else if configuration.scenario == "learned-portrait", !workload.editorControlsAttempted {
          workload.editorControlsAttempted = true
          revealPanel(.motion)
          try await measureEditorControls(application, probe: probe, revealPanel: revealPanel,
            samples: &nativeSamples, workload: &workload)
        } else {
          nativeSamples.append(try await probe.hideMotion(reveal: revealPanel))
        }
        let ordered = nativeSamples.map(\.visibleAcknowledgmentLatencyMilliseconds).sorted()
        let p95 = ordered[max(0, Int(ceil(Double(ordered.count) * 0.95)) - 1)]
        if ordered.last! > 250 || (ordered.count >= 10 && p95 > 100) {
          try? Data("Native input acknowledgment exceeded the gate threshold.\n".utf8).write(
            to: configuration.readyMarkerURL.appendingPathExtension("latency-failure"), options: .atomic)
        }
      }
      catch {
        workload.failures.append(error.localizedDescription)
        try? Data((error.localizedDescription + "\n").utf8).write(
          to: configuration.readyMarkerURL.appendingPathExtension("latency-failure"), options: .atomic)
        try? await clock.sleep(until: deadline)
        break
      }
      try? await clock.sleep(for: .milliseconds(500))
    }
    probe.uninstall()
    revealPanel(.motion)
    await application.portraitStudio.awaitRendering()
    let end = application.previewIsolationDiagnostics
    let interactionLatencies = await interactionProbe.value
    let analysisEnd = await analysisCount(application)

    let sourceWasLive = isLive(start.latestPreviewSource) && isLive(end.latestPreviewSource)
    let stableConfiguration = start.latestPreviewCameraConfigurationID != nil
      && start.latestPreviewCameraConfigurationID == quietEnd.latestPreviewCameraConfigurationID
    var report = RunningAppPreviewPerformanceReport(
      schema: RunningAppPreviewPerformanceReport.schema,
      measurementDurationSeconds: durationMilliseconds(measurementStarted.duration(to: clock.now)) / 1_000,
      previewPublicationCount: end.previewPublicationCount,
      previewFramesAdvanced: subtract(end.previewPublicationCount, start.previewPublicationCount),
      previewStartSequence: start.latestPreviewSequence,
      previewEndSequence: end.latestPreviewSequence,
      previewSourceWasLive: sourceWasLive,
      previewConfigurationRemainedStable: stableConfiguration,
      semanticPresentationRevisionDelta: subtract(
        quietEnd.semanticPresentationRevision,
        start.semanticPresentationRevision
      ),
      rootProjectionBuildCountDelta:
        quietEnd.plotterUIProjectionBuildCount - start.plotterUIProjectionBuildCount,
      drawingDraftSynchronizationCountDelta:
        quietEnd.drawingDraftSynchronizationCount - start.drawingDraftSynchronizationCount,
      overlayPresentationRevisionDelta: subtract(quietEnd.overlayPresentationRevision, start.overlayPresentationRevision),
      overlayCanvasDrawCountDelta: quietEnd.overlayCanvasDrawCount - start.overlayCanvasDrawCount,
      overlayCanvasBuildCountDelta: quietEnd.overlayCanvasBuildCount - start.overlayCanvasBuildCount,
      targetWasVisible: application.drawingTargetIsVisible,
      drawingPlanWasAvailable: application.drawingDraftSnapshot.plan != nil,
      automaticAnalysisWasRunning: application.videoAnalysisIsActive,
      mainActorSchedulingLatencyMilliseconds: interactionLatencies
    )
    report.scenario = configuration.scenario
    report.appliedCheckpointID = application.artifactResetEpisodeSnapshot.savedLearning.appliedCheckpoint?.checkpointID.uuidString
    report.completeAcceptedLearningWasRetained = application.interactiveLearningIsComplete
      && report.appliedCheckpointID == workload.checkpointID
    report.acceptedBorderRecordID = application.artifactResetEpisodeSnapshot.savedLearning.appliedCheckpoint?.stageFour?.recordID.rawValue.uuidString
    report.quietAnalysisWindows = workload.analysisWindows
    report.nativeInputCounts = probe.counts
    report.retrospectiveRecordIDs = workload.retrospectiveRecordIDs
    report.retrospectiveConstraintCount = application.drawingDraftSnapshot.residualAnalysis?.constraints.count ?? 0
    report.portraitMaximumConcurrentExpensiveJobs = application.portraitStudio.workDiagnostics.maximumConcurrentWorkerCount
    report.portraitProgramHash = workload.programHash
    report.portraitStrokeCount = workload.strokeCount
    report.portraitInputSource = workload.inputSource
    report.completedCameraSwitchCount = workload.switchDurations.count
    report.cameraSwitchDurationsMilliseconds = workload.switchDurations
    report.cameraSwitchReceipts = workload.switchReceipts
    report.suspendedPlotterAnalyzedFrameDelta = workload.suspendedAnalysisDelta
    report.measuredAnalysisFrameDelta = subtract(analysisEnd, analysisStart)
    report.portraitMaximumConcurrentWorkers = application.portraitStudio.renderDiagnostics.maximumConcurrentWorkerCount
    report.portraitSettledWorkers = application.portraitStudio.renderDiagnostics.settledWorkerCount
    report.passivePanelsObserved = observedPanels.union(panelsBefore.keys).sorted()
    report.passivePanelTextChanged = passiveChanges.union(Set(panelsBefore.keys).union(panelsAfter.keys).filter {
      panelsBefore[$0] != panelsAfter[$0]
    }).sorted()
    report.stopWasPresent = RunningAppNativeInputProbe.stopIsPresent
    report.nativeInputSamples = nativeSamples
    report.submittedNativeInputCount = probe.submittedInputCount
    report.deliveredNativeInputCount = probe.deliveredInputCount
    report.acknowledgedNativeInputCount = probe.acknowledgedInputCount
    report.failures = workload.failures
    for overlay in UserSceneOverlay.allCases where originalOverlays.contains(overlay)
      != application.observationConfigurationProjection.enabledOverlays.contains(overlay)
    {
      _ = await application.submitObservationConfiguration(application.observationConfigurationProjection.request(
        .setOverlay(identifier: overlay.rawValue, enabled: originalOverlays.contains(overlay))))
    }
    return report
  }

  private struct PortraitPerformanceWorkload {
    var failures: [String] = []
    var programHash: String?
    var strokeCount = 0
    var inputSource: String?
    var switchDurations: [Double] = []
    var suspendedAnalysisDelta: UInt64 = 0
    var checkpointID: String?
    var analysisWindows: [PlotterAnalysisPerformanceWindow] = []
    var retrospectiveRecordIDs: [String] = []
    var editorControlsAttempted = false
    var lastConfigurations: [WorkbenchCameraRole: CameraConfigurationID] = [:]
    var switchReceipts: [WorkbenchCameraSwitchReceipt] = []
  }

  private static func preparePortraitWorkload(
    _ application: PlotterApplicationRuntime,
    configuration: RunningAppPreviewPerformanceConfiguration,
    workload: inout PortraitPerformanceWorkload
  ) async throws {
    if application.artifactResetEpisodeSnapshot.savedLearning.appliedCheckpoint == nil {
      let projection = projection(application)
      guard let saved = projection.semantic.actions.first(where: {
        if case .learningAction(let request) = $0.intent { return request.action == .applySavedLearning }
        return false
      }) else { throw WorkbenchNativeInputError.unavailable("No saved Learning package is available to the production Use Saved Learning action.") }
      try await submit(saved.id, application: application, projection: projection)
    }
    guard let checkpoint = application.artifactResetEpisodeSnapshot.savedLearning.appliedCheckpoint else {
      throw WorkbenchNativeInputError.unavailable("Use Saved Learning did not restore an accepted package.")
    }
    guard checkpoint.penInteraction != nil, checkpoint.machineArtifacts != nil,
      checkpoint.machineCamera != nil, checkpoint.tipCalibration != nil, checkpoint.stageFour != nil,
      application.interactiveLearningIsComplete else {
      throw WorkbenchNativeInputError.unavailable("Saved Learning lacks the complete accepted Pen, Boundary, camera, tip, or Border completion required for the portrait workload.")
    }
    workload.checkpointID = checkpoint.checkpointID.uuidString
    let strokeStyle = application.drawingStrokeStyle
    try await selectCamera(.portrait, application: application)
    let model = application.portraitStudio
    model.style = .crosshatch
    model.renderIfNeeded(strokeStyle: strokeStyle)
    if let photo = configuration.portraitPhotoURL {
      workload.inputSource = "imported photo: \(photo.lastPathComponent)"
      await model.importPhoto(photo, strokeStyle: strokeStyle)
    } else {
      workload.inputSource = "deterministic tonal portrait image fixture v1"
      model.options = PortraitAnalysisOptions(cropToFace: false, removeBackground: false)
      model.setPhoto(try portraitFixtureImage(), for: .front, strokeStyle: strokeStyle)
    }
    await model.awaitRendering()
    guard let program = model.program, program.source.kind == "portrait", program.strokes.count >= 100 else {
      throw WorkbenchNativeInputError.unavailable("Portrait input did not produce at least 100 strokes: \(model.summary)")
    }
    workload.programHash = program.contentHash.description
    workload.strokeCount = program.strokes.count
    try await awaitWorkload("The portrait camera produced no live frame during workload preparation.") { model.preview.frame != nil }
    workload.lastConfigurations[.portrait] = model.preview.frame?.frame.cameraConfigurationID
    try await selectCamera(.plotter, application: application)
    try await submit(PlotterAppUIActionID.drawingDraft(.selectProgram(program)), application: application,
                     projection: projection(application, program: program))
    if !application.drawingTargetIsVisible {
      try await submit(PlotterAppUIActionID.drawingDraft(.showTarget), application: application)
    }
    try await submit(PlotterAppUIActionID.drawingDraft(.fitInDrawableRegion), application: application)
    if !application.observationConfigurationProjection.enabledOverlays.contains(.penCap) {
      try await submit(PlotterAppUIActionID.observationOverlay(UserSceneOverlay.penCap.rawValue, enabled: true),
                       application: application)
    }
    guard application.drawingDraftSnapshot.plan != nil else {
      throw WorkbenchNativeInputError.unavailable("The dense portrait has no immutable drawing plan after Fit Target.")
    }
    let firstAnalysisCount = await analysisCount(application)
    try await awaitWorkload("No plotter camera analysis completed after applying saved Learning.") {
      await analysisCount(application) > firstAnalysisCount
    }
    workload.lastConfigurations[.plotter] = application.actionSurfacePreview.displayedFrame?.frame.cameraConfigurationID
  }

  static func projection(_ application: PlotterApplicationRuntime, program: DrawingProgram? = nil)
    -> PlotterAppUIProjection
  {
    application.plotterUIProjection(selectedItemID: .humanGuidedDiscovery(.penInteraction),
      manualDraft: ManualMotionDraft(), includesLearningPath: true, pendingDrawingProgram: program)
  }

  private static func measureCameraSwitch(_ application: PlotterApplicationRuntime,
    probe: RunningAppNativeInputProbe, revealPanel: @escaping @MainActor (WorkbenchPanel) -> Void,
    samples: inout [WorkbenchNativeInputSample], workload: inout PortraitPerformanceWorkload) async throws {
    let role: WorkbenchCameraRole = workload.switchDurations.count.isMultiple(of: 2) ? .portrait : .plotter
    let started = ContinuousClock.now
    let id = "workbench.camera.\(role.rawValue)"
    revealPanel(.videoSettings)
    samples.append(try await probe.click("workbench.video.cameraRole", handlerIdentifier: id,
      menuKeyCodes: [115] + (role == .portrait ? [125] : []) + [36]) {
        application.workbenchCameraRole == role || application.cameraRoleIsTransitioning
      })
    // This second native event is delivered while the camera owner's async
    // stop/start may still be in flight. Switch duration is measured separately.
    samples.append(try await probe.hideMotion(reveal: revealPanel))
    try await awaitWorkload("Selected \(role.rawValue) camera did not settle: \(application.cameraRoleError ?? "no current source frame").") {
      application.workbenchCameraRole == role && !application.cameraRoleIsTransitioning
        && application.cameraRoleError == nil
        && (role == .portrait ? application.portraitStudio.preview.frame != nil :
          application.cameraIsLive && application.actionSurfacePreview.displayedFrame != nil)
    }
    guard application.interactiveLearningIsComplete,
      application.artifactResetEpisodeSnapshot.savedLearning.appliedCheckpoint?.checkpointID.uuidString == workload.checkpointID else {
      throw WorkbenchNativeInputError.unavailable("Selected camera switching lost complete accepted Learning or its checkpoint identity.")
    }
    let first = role == .portrait ? application.portraitStudio.preview.frame : application.actionSurfacePreview.displayedFrame
    let expectedDevice = role == .portrait ? application.portraitStudio.selectedDeviceID : application.cameraSnapshot?.selectedDeviceID
    guard let first, let expectedDevice, first.source == .live(expectedDevice),
      first.frame.cameraConfigurationID != workload.lastConfigurations[role] else {
      throw WorkbenchNativeInputError.unavailable("Selected \(role.rawValue) capture did not publish its own new live generation.")
    }
    try await awaitWorkload("Selected \(role.rawValue) live frames did not advance after capture startup.") {
      let next = role == .portrait ? application.portraitStudio.preview.frame : application.actionSurfacePreview.displayedFrame
      return next?.source == first.source && next?.frame.cameraConfigurationID == first.frame.cameraConfigurationID
        && (next?.frame.sequence ?? 0) > first.frame.sequence
        && (next?.frame.captureNanoseconds ?? 0) > first.frame.captureNanoseconds
    }
    let progressed = role == .portrait ? application.portraitStudio.preview.frame : application.actionSurfacePreview.displayedFrame
    guard let progressed else { throw WorkbenchNativeInputError.unavailable("Selected live frame disappeared during camera settlement.") }
    let analysisBefore = await analysisCount(application)
    if role == .portrait {
      let model = application.portraitStudio
      revealPanel(.portraitStudio)
      guard RunningAppNativeInputProbe.controlFrame("portrait.adjustmentScroll") != nil,
        model.explorationRegion == nil else {
        throw WorkbenchNativeInputError.unavailable("Choose Whole portrait in Parameters before measuring drawing controls.")
      }
      let detail = model.drawingParameters.detail
      samples.append(try await probe.click("portrait.adjustment.Detail", fractionX: detail < 0.5 ? 0.8 : 0.2) {
        model.drawingParameters.detail != detail
      })
      let preset: PortraitVectorPreset = model.drawingParameters == .preset(.fine) ? .balanced : .fine
      let before = model.renderConfiguration
      samples.append(try await probe.click("portrait.preset.\(preset.rawValue)") {
        model.renderConfiguration != before
      })
      samples.append(try await probe.hideMotion(reveal: revealPanel))
      await model.awaitRendering()
      try await Task.sleep(for: .milliseconds(250))
      workload.suspendedAnalysisDelta += subtract(await analysisCount(application), analysisBefore)
      guard application.cameraSnapshot?.state == .stopped,
        application.videoVisionDiagnostics?.pipeline.phase.state == .stopped,
        application.videoVisionDiagnostics?.pipeline.activeFrameSequence == nil else {
        throw WorkbenchNativeInputError.unavailable("Plotter capture or analysis remained active under the portrait camera.")
      }
    } else {
      workload.analysisWindows.append(await observeQuietAnalysis(application, duration: 1.5, context: "camera switch"))
    }
    workload.switchDurations.append(durationMilliseconds(started.duration(to: .now)))
    workload.lastConfigurations[role] = progressed.frame.cameraConfigurationID
    workload.switchReceipts.append(.init(role: role, deviceID: expectedDevice.rawValue,
      configurationID: progressed.frame.cameraConfigurationID.rawValue.uuidString, configurationChanged: true,
      firstSequence: first.frame.sequence, lastSequence: progressed.frame.sequence,
      firstCaptureNanoseconds: first.frame.captureNanoseconds, lastCaptureNanoseconds: progressed.frame.captureNanoseconds))
  }

  private static func measureEditorControls(_ application: PlotterApplicationRuntime,
    probe: RunningAppNativeInputProbe, revealPanel: @escaping @MainActor (WorkbenchPanel) -> Void,
    samples: inout [WorkbenchNativeInputSample], workload: inout PortraitPerformanceWorkload) async throws {
    revealPanel(.portraitStudio)
    await application.portraitStudio.awaitRendering()
    guard application.portraitStudio.program != nil else {
      throw WorkbenchNativeInputError.unavailable("The measured portrait style edits left no renderable portrait: \(application.portraitStudio.summary)")
    }
    let selectedHash = application.portraitStudio.selectedCandidate?.program.contentHash
    samples.append(try await probe.click("portrait.showOnPlotter") {
      // Re-showing the same drawing intentionally preserves placement. Its
      // acknowledgment is the actual Studio-to-plotter transition and exact
      // projected program, not a requirement to manufacture a different hash.
      application.drawingDraftSnapshot.program?.contentHash == selectedHash
        && RunningAppNativeInputProbe.controlFrame("workbench.panel.portraitStudio") == nil
        && RunningAppNativeInputProbe.controlFrame("workbench.panel.drawing") != nil
        && RunningAppNativeInputProbe.controlFrame("workbench.video.canvas") != nil
    })
    try await awaitWorkload("Send to Drawing did not expose the current portrait plan.") {
      application.drawingDraftSnapshot.program?.contentHash == application.portraitStudio.program?.contentHash
        && application.drawingTargetIsVisible && application.drawingDraftSnapshot.plan != nil
    }
    revealPanel(.drawing)
    for (id, fraction) in [("drawing.scale", 0.4), ("drawing.rotation", 0.65), ("drawing.fit", 0.5)] {
      let before = RunningAppNativeInputProbe.controlValue("drawing.placement")
      samples.append(try await probe.click(id, fractionX: fraction) {
        RunningAppNativeInputProbe.controlValue("drawing.placement") != before
      })
    }
    for _ in 0..<2 {
      let wasVisible = RunningAppNativeInputProbe.controlFrame("workbench.panel.motion") != nil
      samples.append(try await probe.togglePane(.motion) {
        (RunningAppNativeInputProbe.controlFrame("workbench.panel.motion") != nil) != wasVisible
      })
    }
    samples.append(try await probe.scrollWorkbench())
    samples.append(try await probe.resizeWorkbench())
    workload.analysisWindows.append(await observeQuietAnalysis(application, duration: 1.5, context: "portrait and placement edits"))
    revealPanel(.activeLearning)
    let records = application.drawingDraftSnapshot.residualRecords
    guard records.contains(where: { $0.role == .ordinaryDrawing }) else {
      throw WorkbenchNativeInputError.unavailable("The ordinary drawing archive is empty; retrospective selection requires an observed drawing under the accepted calibration.")
    }
    // Select existing immutable records through their real checkboxes. The
    // normal analysis owner diagnoses role/provenance exclusions; this gate
    // never manufactures, relabels or writes an archived drawing.
    for record in records where record.isSelected != (record.role == .ordinaryDrawing) {
      let id = "learning.record.\(record.recordID.rawValue.uuidString)"
      let before = RunningAppNativeInputProbe.controlValue(id)
      samples.append(try await probe.click(id) { RunningAppNativeInputProbe.controlValue(id) != before })
    }
    workload.retrospectiveRecordIDs = application.drawingDraftSnapshot.residualRecords.filter { $0.isSelected && $0.role == .ordinaryDrawing }.map { $0.recordID.rawValue.uuidString }
    let oldAnalysis = application.drawingDraftSnapshot.residualAnalysis
    samples.append(try await probe.click("learning.analyzeDrawings") {
      application.drawingDraftSnapshot.residualAnalysis != oldAnalysis
        && RunningAppNativeInputProbe.controlValue("learning.residualResult") != nil
    })
    workload.analysisWindows.append(await observeQuietAnalysis(application, duration: 1.5, context: "retrospective analysis"))
    guard let analysis = application.drawingDraftSnapshot.residualAnalysis, !analysis.constraints.isEmpty else {
      throw WorkbenchNativeInputError.unavailable("Existing archive records cannot supply the required ordinary-drawing residual workload: \(application.drawingDraftSnapshot.residualAnalysis?.summary ?? "no completed analysis").")
    }
  }

  private static func observeQuietAnalysis(_ application: PlotterApplicationRuntime,
    duration: Double, context: String) async -> PlotterAnalysisPerformanceWindow {
    let analysisBefore = await analysisCount(application)
    let before = application.previewIsolationDiagnostics
    let started = ContinuousClock.now
    let deadline = started.advanced(by: .seconds(duration))
    var panels = WorkbenchQuietPanelObservation()
    repeat {
      panels.observe(RunningAppNativeInputProbe.panelText())
      try? await Task.sleep(for: .milliseconds(50))
    } while ContinuousClock.now < deadline && !Task.isCancelled
    panels.observe(RunningAppNativeInputProbe.panelText())
    let after = application.previewIsolationDiagnostics
    return PlotterAnalysisPerformanceWindow(
      durationSeconds: durationMilliseconds(started.duration(to: .now)) / 1_000,
      completedFrames: subtract(await analysisCount(application), analysisBefore), context: context,
      semanticRevisionDelta: subtract(after.semanticPresentationRevision, before.semanticPresentationRevision),
      rootBuildCountDelta: after.plotterUIProjectionBuildCount - before.plotterUIProjectionBuildCount,
      draftSynchronizationCountDelta: after.drawingDraftSynchronizationCount - before.drawingDraftSynchronizationCount,
      overlayRevisionDelta: subtract(after.overlayPresentationRevision, before.overlayPresentationRevision),
      overlayCanvasDrawCountDelta: after.overlayCanvasDrawCount - before.overlayCanvasDrawCount,
      overlayCanvasBuildCountDelta: after.overlayCanvasBuildCount - before.overlayCanvasBuildCount,
      changedPanels: panels.changed.sorted(), panelSampleCount: panels.sampleCount)
  }

  static func submit(_ id: PlotterUIActionID, application: PlotterApplicationRuntime,
                             projection explicitProjection: PlotterAppUIProjection? = nil) async throws {
    let current = explicitProjection ?? projection(application)
    guard let request = current.semantic.request(for: id) else {
      let reason = current.semantic.actions.first(where: { $0.id == id })?.unavailableReason
      throw WorkbenchNativeInputError.unavailable(reason ?? "Required projected action \(id.rawValue) is unavailable.")
    }
    if case .refused(let refusal) = await application.submitPlotterUIRequest(request) {
      throw WorkbenchNativeInputError.unavailable("\(refusal.owner): \(refusal.remedy)")
    }
  }

  static func selectCamera(_ role: WorkbenchCameraRole, application: PlotterApplicationRuntime) async throws {
    try await submit(PlotterAppUIActionID.observationCameraRole(role), application: application)
    guard application.workbenchCameraRole == role, !application.cameraRoleIsTransitioning,
      application.cameraRoleError == nil else {
      throw WorkbenchNativeInputError.unavailable(application.cameraRoleError ?? "The selected camera did not settle.")
    }
  }

  private static func analysisCount(_ application: PlotterApplicationRuntime) async -> UInt64 {
    _ = await application.submitObservationConfiguration(application.observationConfigurationProjection.request(.requestDiagnostics))
    return application.videoVisionDiagnostics?.pipeline.analyzedFrameCount ?? 0
  }

  static func awaitWorkload(_ failure: String, condition: () async -> Bool) async throws {
    let deadline = ContinuousClock.now.advanced(by: .seconds(15))
    while !(await condition()) {
      guard ContinuousClock.now < deadline else { throw WorkbenchNativeInputError.unavailable(failure) }
      try await Task.sleep(for: .milliseconds(100))
    }
  }

  /// Real image decoding and vectorization are exercised; this fixture carries
  /// explicit synthetic provenance and never claims a captured human face.
  private static func portraitFixtureImage() throws -> Data {
    let width = 160, height = 200
    let bytes = Data((0..<(width * height)).map { index -> UInt8 in
      let x = Double(index % width - width / 2) / 64
      let y = Double(index / width - height / 2) / 92
      let radius = x * x + y * y
      if radius > 1 { return 255 }
      let eyes = abs(y + 0.22) < 0.04 && abs(abs(x) - 0.32) < 0.12
      let mouth = abs(y - 0.44) < 0.03 && abs(x) < 0.3
      return eyes || mouth ? 12 : UInt8(25 + min(180, radius * 140))
    })
    guard let provider = CGDataProvider(data: bytes as CFData),
      let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 8,
        bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: 0),
        provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    else { throw PortraitDrawingError.unreadableImage }
    return try PortraitImageAnalyzer.encodedImage(image)
  }

  private nonisolated static func interactionLatencySamples(
    duration: Duration,
    interval: Duration
  ) async -> [Double] {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: duration)
    var samples: [Double] = []
    while clock.now < deadline {
      try? await clock.sleep(for: interval)
      let requestedAt = clock.now
      let observedAt = await MainActor.run { clock.now }
      samples.append(durationMilliseconds(requestedAt.duration(to: observedAt)))
    }
    return samples
  }

  private nonisolated static func durationMilliseconds(_ duration: Duration) -> Double {
    let components = duration.components
    return (Double(components.seconds) * 1_000)
      + (Double(components.attoseconds) / 1_000_000_000_000_000)
  }

  private static func isLive(_ source: FrameSourceIdentity?) -> Bool {
    guard case .live = source else { return false }
    return true
  }

  private static func subtract(_ end: UInt64, _ start: UInt64) -> UInt64 {
    end >= start ? end - start : 0
  }

  private static func write(
    _ report: RunningAppPreviewPerformanceReport,
    to destination: URL
  ) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    var assessed = report
    assessed.failures = report.workloadFailures
    var data = try encoder.encode(assessed)
    data.append(0x0A)
    try data.write(to: destination, options: .atomic)
  }
}
