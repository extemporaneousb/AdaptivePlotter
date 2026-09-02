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
  @State private var requestRefusal: String?

  var body: some View {
    let status = presentation.displayStatus(for: displayedFrame)
    VStack(alignment: .trailing, spacing: 7) {
      Text(status.message)
        .font(.caption.monospaced())
        .foregroundStyle(statusColor(status))
        .multilineTextAlignment(.trailing)
        .fixedSize(horizontal: false, vertical: true)
      if let requestRefusal {
        Text(requestRefusal)
          .font(.caption2)
          .foregroundStyle(.orange)
          .multilineTextAlignment(.trailing)
      }
      HStack(spacing: 7) {
        ForEach(presentation.controls) { control in
          let retainedIntent: PlotterUIRetainedComparisonIntent =
            control.intent == .reviewComparison ? .reviewExactFrame : .resumeLivePreview
          let intent = PlotterUIIntent.retainedComparisonReview(retainedIntent)
          let request = plotterUIProjection.request(matching: intent)
          Button {
            submit(intent)
          } label: {
            Label(control.title, systemImage: control.systemImage)
          }
          .operatorButton(control.role, isEnabled: request != nil)
          .controlSize(.small)
          .help(request == nil ? "Refresh the completed comparison before retrying." : control.title)
        }
        if case .reviewingExactFrame = presentation.state,
          presentation.drawingDraftProjection != nil
        {
          Button {
            submit(.drawingDraft(.open))
          } label: {
            Label("Open Drawing Studio", systemImage: "scribble.variable")
          }
          .operatorButton(
            .affirmative,
            isEnabled: plotterUIProjection.request(matching: .drawingDraft(.open)) != nil
          )
          .controlSize(.small)
        }
      }
    }
    .padding(8)
    .background(.black.opacity(0.78), in: RoundedRectangle(cornerRadius: 7))
    .accessibilityElement(children: .contain)
  }

  private func submit(_ intent: PlotterUIIntent) {
    guard let request = plotterUIProjection.request(matching: intent) else {
      requestRefusal = "Refresh the current comparison control before retrying."
      return
    }
    Task { @MainActor in
      let disposition = await plotterUIIntentSink.submitPlotterUIRequest(request)
      if case .refused(let refusal) = disposition {
        requestRefusal = refusal.remedy
      } else {
        requestRefusal = nil
      }
    }
  }

  private func statusColor(_ status: CompletedComparisonReviewDisplayStatus) -> Color {
    switch status {
    case .exactFrameNotDisplayed: .orange
    case .unavailable: .secondary
    case .availableForReview, .exactFrameDisplayed: .white
    }
  }
}
