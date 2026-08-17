import PlotterRuntime
import Testing

@testable import PlotterApp

@Suite("Completed comparison review presentation")
struct CompletedComparisonReviewPresentationTests {
  @Test("available comparison offers explicit review without claiming it is displayed")
  func availableComparisonControl() throws {
    let frame = try drawingPresentationTestFrame()
    let presentation = CompletedComparisonReviewPresentation(
      state: .available(ExactFrameOverlayProvenance(frame)),
      drawingStudioIsAvailable: true
    )

    #expect(
      presentation.displayStatus(for: nil as DisplayedFrame?)
        == .availableForReview(frameSequence: frame.frame.sequence)
    )
    let actions: [CompletedComparisonReviewAction] = [.reviewComparison]
    #expect(presentation.controls.map(\.action) == actions)
  }

  @Test("reviewing never accepts another frame or configuration")
  func reviewRequiresExactDisplayedFrame() throws {
    let exact = try drawingPresentationTestFrame()
    let presentation = CompletedComparisonReviewPresentation(
      state: .reviewingExactFrame(ExactFrameOverlayProvenance(exact)),
      drawingStudioIsAvailable: true
    )
    let stale = try drawingPresentationTestFrame()

    #expect(
      presentation.displayStatus(for: exact)
        == .exactFrameDisplayed(frameSequence: exact.frame.sequence)
    )
    #expect(
      presentation.displayStatus(for: stale)
        == .exactFrameNotDisplayed(
          expectedSequence: exact.frame.sequence,
          displayedSequence: stale.frame.sequence
        )
    )
    let actions: [CompletedComparisonReviewAction] = [
      .resumeLivePreview, .openDrawingStudio,
    ]
    #expect(presentation.controls.map(\.action) == actions)
  }

  @Test("drawing entry is independent from review availability")
  func drawingStudioAdmissionIsProjected() throws {
    let exact = try drawingPresentationTestFrame()
    let presentation = CompletedComparisonReviewPresentation(
      state: .reviewingExactFrame(ExactFrameOverlayProvenance(exact)),
      drawingStudioIsAvailable: false
    )

    let actions: [CompletedComparisonReviewAction] = [.resumeLivePreview]
    #expect(presentation.controls.map(\.action) == actions)
  }
}
