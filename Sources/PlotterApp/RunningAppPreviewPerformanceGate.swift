import AppKit
import Foundation
import PlotterRuntime

struct RunningAppPreviewPerformanceConfiguration: Equatable, Sendable {
  static let enabledArgument = "-AdaptivePlotterPreviewPerformanceGate"
  static let reportArgument = "-AdaptivePlotterPreviewPerformanceReport"
  static let readyMarkerArgument = "-AdaptivePlotterPreviewPerformanceReadyMarker"
  static let drawingStudioArgument = "-AdaptivePlotterPreviewPerformanceDrawingStudio"

  let reportURL: URL
  let readyMarkerURL: URL
  let includesDrawingStudio: Bool

  init?(arguments: [String]) {
    guard Self.value(after: Self.enabledArgument, in: arguments)?
      .caseInsensitiveCompare("YES") == .orderedSame,
      let reportPath = Self.value(after: Self.reportArgument, in: arguments),
      let readyMarkerPath = Self.value(after: Self.readyMarkerArgument, in: arguments)
    else { return nil }
    reportURL = URL(fileURLWithPath: reportPath)
    readyMarkerURL = URL(fileURLWithPath: readyMarkerPath)
    includesDrawingStudio = Self.value(after: Self.drawingStudioArgument, in: arguments)?
      .caseInsensitiveCompare("YES") == .orderedSame
  }

  private static func value(after argument: String, in arguments: [String]) -> String? {
    guard let index = arguments.firstIndex(of: argument),
      arguments.indices.contains(index + 1)
    else { return nil }
    return arguments[index + 1]
  }
}

struct RunningAppPreviewPerformanceReport: Codable, Equatable, Sendable {
  static let schema = "adaptiveplotter.running-app-preview-runtime.v1"

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
  var drawingStudioWasOpen: Bool = false
  var drawingPlanWasAvailable: Bool = false
  var automaticAnalysisWasRunning: Bool = false
  let interactionLatencyMilliseconds: [Double]
}

/// Opt-in instrumentation for the repository's signed-app performance gate.
/// It can open the Studio panel, but never applies Saved Learning or submits
/// controller, motion, pen, or drawing execution intent.
@MainActor
enum RunningAppPreviewPerformanceGate {
  private static let previewStartupTimeout: Duration = .seconds(15)
  private static let warmupDuration: Duration = .seconds(3)
  private static let measurementDuration: Duration = .seconds(12)
  private static let interactionProbeInterval: Duration = .milliseconds(100)

  static func runIfRequested(
    application: PlotterApplicationRuntime,
    arguments: [String] = CommandLine.arguments
  ) async {
    guard let configuration = RunningAppPreviewPerformanceConfiguration(arguments: arguments)
    else { return }

    if configuration.includesDrawingStudio {
      let projection = application.plotterUIProjection(
        selectedItemID: .humanGuidedDiscovery(.penInteraction),
        manualDraft: ManualMotionDraft(), includesLearningPath: true)
      if let request = projection.semantic.request(for: PlotterAppUIActionID.drawingOpen) {
        _ = await application.submitPlotterUIRequest(request)
      }
    }

    let report = await measure(
      application: application,
      readyMarkerURL: configuration.readyMarkerURL
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
    readyMarkerURL: URL
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

    application.resetPreviewIsolationDiagnostics()
    let start = application.previewIsolationDiagnostics
    do {
      try Data("ready\n".utf8).write(to: readyMarkerURL, options: .atomic)
    } catch {
      FileHandle.standardError.write(Data(
        "Could not write preview performance ready marker: \(error)\n".utf8
      ))
    }

    let interactionProbe = Task.detached(priority: .userInitiated) {
      await interactionLatencySamples(
        duration: measurementDuration,
        interval: interactionProbeInterval
      )
    }
    try? await clock.sleep(for: measurementDuration)
    let end = application.previewIsolationDiagnostics
    let interactionLatencies = await interactionProbe.value

    let sourceWasLive = isLive(start.latestPreviewSource) && isLive(end.latestPreviewSource)
    let stableConfiguration = start.latestPreviewCameraConfigurationID != nil
      && start.latestPreviewCameraConfigurationID == end.latestPreviewCameraConfigurationID
    return RunningAppPreviewPerformanceReport(
      schema: RunningAppPreviewPerformanceReport.schema,
      measurementDurationSeconds: durationMilliseconds(measurementDuration) / 1_000,
      previewPublicationCount: end.previewPublicationCount,
      previewFramesAdvanced: subtract(end.previewPublicationCount, start.previewPublicationCount),
      previewStartSequence: start.latestPreviewSequence,
      previewEndSequence: end.latestPreviewSequence,
      previewSourceWasLive: sourceWasLive,
      previewConfigurationRemainedStable: stableConfiguration,
      semanticPresentationRevisionDelta: subtract(
        end.semanticPresentationRevision,
        start.semanticPresentationRevision
      ),
      rootProjectionBuildCountDelta:
        end.plotterUIProjectionBuildCount - start.plotterUIProjectionBuildCount,
      drawingDraftSynchronizationCountDelta:
        end.drawingDraftSynchronizationCount - start.drawingDraftSynchronizationCount,
      drawingStudioWasOpen: application.drawingStudioIsPresented,
      drawingPlanWasAvailable: application.drawingDraftSnapshot.plan != nil,
      automaticAnalysisWasRunning: application.videoAnalysisIsActive,
      interactionLatencyMilliseconds: interactionLatencies
    )
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
    var data = try encoder.encode(report)
    data.append(0x0A)
    try data.write(to: destination, options: .atomic)
  }
}
