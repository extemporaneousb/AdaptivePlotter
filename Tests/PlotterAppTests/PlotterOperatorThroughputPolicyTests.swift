import CoreGraphics
import PlotterEpisodeModel
import PlotterEpisodeRuntime
import PlotterModel
import PlotterRuntime
import PlotterUI
import Testing

@testable import PlotterApp

@Suite("Operator throughput policy", .serialized)
struct PlotterOperatorThroughputPolicyTests {
  @Test("Video Settings exposes exactly the requested analysis cadences")
  func exactAnalysisCadences() {
    #expect(VisionAnalysisCadence.allCases.map(\.rawValue) == [
      0.05, 1, 2, 2.58, 3, 4, 5,
    ])
    #expect(VisionAnalysisCadence.allCases.map(\.displayValue) == [
      "0.05", "1", "2", "2.58", "3", "4", "5",
    ])
    #expect(VisionAnalysisCadence.allCases.map(\.minimumIntervalNanoseconds) == [
      20_000_000_000,
      1_000_000_000,
      500_000_000,
      387_596_900,
      333_333_334,
      250_000_000,
      200_000_000,
    ])
    #expect(VisionAnalysisCadence.allCases.map {
      PlotterAppUIActionID.observationCadence($0).rawValue
    } == [
      "application.observation.cadence.0.05",
      "application.observation.cadence.1",
      "application.observation.cadence.2",
      "application.observation.cadence.2.58",
      "application.observation.cadence.3",
      "application.observation.cadence.4",
      "application.observation.cadence.5",
    ])
  }

  @MainActor
  @Test("Exact-frame camera click becomes a direct projection-bound submission")
  func exactFrameClickSubmitsWithoutConfirmation() async throws {
    let harness = makeCausalSimulatorAppFixture()
    let workspace = harness.workspace
    await submitObservationConfigurationForTest(workspace, .selectSource(.simulated, nil))
    let owner = LearningPathItemID.humanGuidedDiscovery(.penInteraction)
    let startProjection = workspace.testPlotterUIProjection(
      selectedItemID: owner,
      includesLearningPath: true
    ).semantic
    let start = try #require(startProjection.request(
      for: learningActionID(.start, owner: owner)
    ))
    let sink: any PlotterUIIntentSink = workspace
    #expect(await sink.submitPlotterUIRequest(start) == .accepted(requestID: start.id))

    let presentation = workspace.testActionSurfacePresentation
    let submission = try #require(ExactFramePointSubmissionBuilder.submission(
      presentation: presentation,
      viewport: ActionSurfaceViewportState(),
      at: CGPoint(x: 160, y: 120),
      viewSize: CGSize(width: 320, height: 240)
    ))
    let unbound = workspace.testPlotterUIProjection(
      selectedItemID: owner,
      includesLearningPath: true
    ).semantic
    #expect(ActionSurfacePointSubmissionPolicy.automaticSubmission(
      pending: submission,
      presentation: presentation,
      projection: unbound
    ) == nil)

    let bound = workspace.plotterUIProjection(
      selectedItemID: owner,
      manualDraft: ManualMotionDraft(),
      includesLearningPath: true,
      pendingPointSelection: submission
    ).semantic
    #expect(ActionSurfacePointSubmissionPolicy.automaticSubmission(
      pending: submission,
      presentation: presentation,
      projection: bound
    ) == submission)
    let request = try #require(bound.request(matching: .pointSelection(submission)))
    #expect(await sink.submitPlotterUIRequest(request) == .accepted(requestID: request.id))
    await workspace.shutdown()
  }

  @MainActor
  @Test("App-generated drawing and calibration geometry request 500 millimeters per minute")
  func appGeneratedXYFeed() async throws {
    #expect(PlotterMotionThroughput.applicationXYFeedMMPerMinute == 500)
    #expect(SparseTipCircularMarkPlan.maximumFeedMMPerMinute == 500)

    let fixture = try await DrawingRunEpisodeFixtureCache.load()
    let harness = await drawingRunHarness(fixture: fixture)
    let current = await harness.runtime.synchronize(environment: .live)
    _ = await harness.runtime.submit(PlotterDrawingRunSubmission(
      projection: current.projection,
      intent: .start
    ))
    let request = try #require(await harness.interpreter.planRequests.first)
    #expect(request.travelFeedMMPerMinute == 500)
    #expect(request.drawingFeedMMPerMinute == 500)
  }
}
