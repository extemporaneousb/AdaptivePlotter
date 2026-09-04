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
      interactionLatencyMilliseconds: [0.2, 0.3, 0.4]
    )

    let decoded = try JSONDecoder().decode(
      RunningAppPreviewPerformanceReport.self,
      from: JSONEncoder().encode(report)
    )
    #expect(decoded == report)
  }
}
