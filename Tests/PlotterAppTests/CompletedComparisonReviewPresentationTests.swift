import Foundation
import PlotterEpisodeModel
import PlotterEpisodeRuntime
import PlotterModel
import PlotterRuntime
import Testing

@testable import PlotterApp

@Suite("Completed comparison review presentation")
struct CompletedComparisonReviewPresentationTests {
  @Test("available comparison offers explicit review without claiming display")
  func availableComparisonControl() throws {
    let frame = try comparisonTestFrame(sequence: 1)
    let presentation = CompletedComparisonReviewPresentation(
      state: .available(ExactFrameOverlayProvenance(frame)),
      drawingDraftProjection: nil
    )

    #expect(
      presentation.displayStatus(for: nil as DisplayedFrame?)
        == .availableForReview(frameSequence: frame.frame.sequence)
    )
    #expect(presentation.controls.map(\.action) == [.reviewComparison])
  }

  @Test("reviewing never substitutes another exact frame")
  func reviewRequiresExactDisplayedFrame() throws {
    let exact = try comparisonTestFrame(sequence: 1)
    let stale = try comparisonTestFrame(sequence: 2)
    let presentation = CompletedComparisonReviewPresentation(
      state: .reviewingExactFrame(ExactFrameOverlayProvenance(exact)),
      drawingDraftProjection: nil
    )

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
    #expect(presentation.controls.map(\.action) == [.resumeLivePreview])
  }

  @Test("Drawing Studio entry carries an immutable draft projection")
  func drawingStudioAdmissionIsProjected() throws {
    let exact = try comparisonTestFrame(sequence: 1)
    let projection = PlotterDrawingDraftSnapshot.initial(
      environment: .live,
      toolAssemblyRevision: ToolAssemblyRevision(),
      paper: PaperRevisionContext(
        instance: PaperInstanceRevision(),
        contactPlane: PaperContactPlaneRevision()
      )
    ).projection
    let presentation = CompletedComparisonReviewPresentation(
      state: .reviewingExactFrame(ExactFrameOverlayProvenance(exact)),
      drawingDraftProjection: projection
    )

    #expect(presentation.drawingDraftProjection == projection)
    #expect(presentation.controls.map(\.action) == [.resumeLivePreview])
  }
}

private func comparisonTestFrame(sequence: UInt64) throws -> DisplayedFrame {
  DisplayedFrame(
    source: .live(CameraDeviceID(rawValue: "comparison-presentation-camera")),
    frame: try StampedFrame(
      sequence: sequence,
      captureNanoseconds: sequence * 10,
      cameraConfigurationID: CameraConfigurationID(
        UUID(uuidString: "00000000-0000-0000-0000-000000000012")!
      ),
      width: 2,
      height: 2,
      rowBytes: 8,
      pixelFormat: .bgra8,
      bytes: OwnedFrameBytes(Array(repeating: UInt8(sequence), count: 16))
    )
  )
}
