import PlotterModel
import Testing

@testable import PlotterApp
@testable import PlotterRuntime

@Suite("Tip applicability evidence policy")
@MainActor
struct TipApplicabilityEvidencePolicyTests {
  @Test("Drawing Studio owner refuses Vision and emits typed non-attribution")
  func drawingStudioOwnerRefusesObserver() async throws {
    let bounds = try AxisAlignedBounds<MachineSpace>(
      minX: 10,
      minY: 10,
      maxX: 90,
      maxY: 90
    )
    let limitation = TipApplicabilityEvidenceLimitation(
      registrationRevisionID: LearningArtifactRevisionID(),
      recordedApplicabilityRectangle: bounds,
      firstOutsideMachinePoint: try Point2(x: 5, y: 50)
    )
    let projection = TipApplicabilityEvidenceProjection(
      diagnosticLimitation: limitation
    )
    let probe = DrawingStudioObserverProbe()

    let classification = await OperatorWorkspace.classifyDrawingStudioObservation(
      projection: projection
    ) { _ in
      await probe.recordInvocation()
      fatalError("outside-applicability projection must never invoke Vision")
    }

    let callCount = await probe.callCount
    #expect(callCount == 0)
    #expect(classification.presentationObservation == nil)
    #expect(classification.evidenceDisposition == .nonAttributable)
    #expect(
      classification.runObservation
        == .notAttempted(.projectionOutsideTipApplicability)
    )

    let withoutPostFrame = OperatorWorkspace.retainedDrawingStudioRunState(
      runID: "run-outside",
      observation: classification.runObservation,
      postFrameAvailable: false,
      reviewIsPinned: true,
      runDetail: nil
    )
    guard case .terminal(_, let unavailableDetail) = withoutPostFrame else {
      Issue.record("A retained record without a post frame must not offer frame review.")
      return
    }
    #expect(unavailableDetail.contains("no exact post-run frame"))

    let withPostFrame = OperatorWorkspace.retainedDrawingStudioRunState(
      runID: "run-outside",
      observation: classification.runObservation,
      postFrameAvailable: true,
      reviewIsPinned: true,
      runDetail: nil
    )
    guard case .reviewing(_, let diagnosticDetail) = withPostFrame else {
      Issue.record("A retained exact post frame must remain reviewable.")
      return
    }
    #expect(diagnosticDetail.contains("no camera/ink observation was attempted"))

    let otherTerminalOutcomes: [(DrawingRunObservationOutcome, String)] = [
      (.notAttempted(.requestRefused), "Drawing stopped without redraw: refused."),
      (
        .notAttempted(.executionCancelledBeforeObservation),
        "Drawing stopped without redraw: cancelled."
      ),
      (
        .notAttempted(.executionFailedBeforeObservation),
        "Drawing stopped without redraw: possible ink."
      ),
    ]
    for (observation, detail) in otherTerminalOutcomes {
      let terminal = OperatorWorkspace.retainedDrawingStudioRunState(
        runID: "run-terminal",
        observation: observation,
        postFrameAvailable: false,
        reviewIsPinned: false,
        runDetail: detail
      )
      guard case .terminal(_, let retainedDetail) = terminal else {
        Issue.record("A terminal record without a post frame must not offer frame review.")
        return
      }
      #expect(terminal.title == "Drawing run ended")
      #expect(retainedDetail == detail)
    }
  }
}

private actor DrawingStudioObserverProbe {
  private(set) var callCount = 0

  func recordInvocation() {
    callCount += 1
  }
}
