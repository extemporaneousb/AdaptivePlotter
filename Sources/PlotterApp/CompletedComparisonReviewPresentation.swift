import PlotterEpisodeModel
import PlotterEpisodeRuntime
import PlotterRuntime
import PlotterUI
import SwiftUI

enum CompletedComparisonReviewState: Hashable, Sendable {
  case unavailable
  case available(ExactFrameOverlayProvenance)
  case reviewingExactFrame(ExactFrameOverlayProvenance)

  var provenance: ExactFrameOverlayProvenance? {
    switch self {
    case .unavailable: nil
    case .available(let provenance), .reviewingExactFrame(let provenance): provenance
    }
  }
}

enum CompletedComparisonReviewDisplayStatus: Hashable, Sendable {
  case unavailable
  case availableForReview(frameSequence: UInt64)
  case exactFrameDisplayed(frameSequence: UInt64)
  case exactFrameNotDisplayed(expectedSequence: UInt64, displayedSequence: UInt64?)

  var message: String {
    switch self {
    case .unavailable:
      return "No completed comparison is available."
    case .availableForReview(let frame):
      return "Comparison frame \(frame) is retained for exact-frame review."
    case .exactFrameDisplayed(let frame):
      return "Reviewing predicted cyan, observed white, and residual orange on exact frame \(frame)."
    case .exactFrameNotDisplayed(let expected, let displayed):
      if let displayed {
        return "Comparison withheld: exact frame \(expected) does not match displayed frame \(displayed)."
      }
      return "Comparison withheld: exact frame \(expected) is not displayed."
    }
  }
}

enum CompletedComparisonReviewIntent: Hashable, Sendable {
  case reviewComparison
  case resumeLivePreview
}

struct CompletedComparisonReviewControl: Hashable, Identifiable, Sendable {
  let intent: CompletedComparisonReviewIntent
  let title: String
  let systemImage: String
  let role: OperatorButtonRole

  var id: CompletedComparisonReviewIntent { intent }
}

/// Values-only review projection. The coordinator chooses whether the retained
/// exact frame or the live preview is displayed; this type never substitutes a
/// different frame for the completed result.
struct CompletedComparisonReviewPresentation: Hashable, Sendable {
  let state: CompletedComparisonReviewState
  let drawingDraftProjection: PlotterDrawingDraftProjectionReference?

  static let unavailable = Self(state: .unavailable, drawingDraftProjection: nil)

  var isPresentedOnCanvas: Bool {
    if case .reviewingExactFrame = state { return true }
    return false
  }

  func displayStatus(
    for displayedFrame: DisplayedFrame?
  ) -> CompletedComparisonReviewDisplayStatus {
    switch state {
    case .unavailable:
      return .unavailable
    case .available(let provenance):
      return .availableForReview(frameSequence: provenance.frameSequence)
    case .reviewingExactFrame(let provenance):
      guard let displayedFrame, provenance.matches(displayedFrame) else {
        return .exactFrameNotDisplayed(
          expectedSequence: provenance.frameSequence,
          displayedSequence: displayedFrame?.frame.sequence
        )
      }
      return .exactFrameDisplayed(frameSequence: provenance.frameSequence)
    }
  }

  var controls: [CompletedComparisonReviewControl] {
    switch state {
    case .unavailable:
      []
    case .available:
      [
        CompletedComparisonReviewControl(
          intent: .reviewComparison,
          title: "Review Comparison",
          systemImage: "square.stack.3d.up",
          role: .neutral
        )
      ]
    case .reviewingExactFrame:
      [
        CompletedComparisonReviewControl(
          intent: .resumeLivePreview,
          title: "Resume Live Preview",
          systemImage: "video.fill",
          role: .neutral
        )
      ]
    }
  }
}

struct CompletedComparisonReviewControls: View {
  let presentation: CompletedComparisonReviewPresentation
  let displayedFrame: DisplayedFrame?
  let plotterUIProjection: PlotterUIProjection
  let plotterUIIntentSink: any PlotterUIIntentSink

  var body: some View {
    let status = presentation.displayStatus(for: displayedFrame)
    VStack(alignment: .trailing, spacing: 7) {
      HStack(alignment: .top, spacing: 8) {
        Text(status.message)
          .font(.caption.monospaced())
          .foregroundStyle(statusColor(status))
          .multilineTextAlignment(.trailing)
          .fixedSize(horizontal: false, vertical: true)
        OperatorRequestButton(
          title: "×", request: plotterUIProjection.request(
            matching: .retainedComparisonReview(.resumeLivePreview)),
          unavailableReason: nil, sink: plotterUIIntentSink,
          nativeActionIdentifier: "comparison.close"
        )
        .controlSize(.small)
        .accessibilityLabel("Close comparison")
        .accessibilityIdentifier("comparison.close")
        .help("Close comparison and resume live preview")
      }
      if case .reviewingExactFrame = presentation.state,
        presentation.drawingDraftProjection != nil
      {
        OperatorRequestButton(
          title: "Show Drawing Target", role: .affirmative,
          request: plotterUIProjection.request(matching: .drawingDraft(.showTarget)),
          unavailableReason: nil, sink: plotterUIIntentSink
        )
        .controlSize(.small)
        .accessibilityIdentifier("drawing.showTarget")
      }
    }
    .frame(maxWidth: 380)
    .padding(8)
    .background(.black.opacity(0.78), in: RoundedRectangle(cornerRadius: 7))
    .accessibilityElement(children: .contain)
  }

  private func statusColor(_ status: CompletedComparisonReviewDisplayStatus) -> Color {
    switch status {
    case .exactFrameNotDisplayed: .orange
    case .unavailable: .secondary
    case .availableForReview, .exactFrameDisplayed: .white
    }
  }
}
