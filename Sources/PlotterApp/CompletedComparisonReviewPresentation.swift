import PlotterRuntime
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

enum CompletedComparisonReviewAction: Hashable, Sendable {
  case reviewComparison
  case resumeLivePreview
  case openDrawingStudio
}

struct CompletedComparisonReviewControl: Hashable, Identifiable, Sendable {
  let action: CompletedComparisonReviewAction
  let title: String
  let systemImage: String
  let role: OperatorButtonRole

  var id: CompletedComparisonReviewAction { action }
}

/// Values-only review projection. The coordinator chooses whether the retained
/// exact frame or the live preview is displayed; this type never substitutes a
/// different frame for the completed result.
struct CompletedComparisonReviewPresentation: Hashable, Sendable {
  let state: CompletedComparisonReviewState
  let drawingStudioIsAvailable: Bool

  static let unavailable = Self(state: .unavailable, drawingStudioIsAvailable: false)

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
          action: .reviewComparison,
          title: "Review Comparison",
          systemImage: "square.stack.3d.up",
          role: .neutral
        )
      ]
    case .reviewingExactFrame:
      [
        CompletedComparisonReviewControl(
          action: .resumeLivePreview,
          title: "Resume Live Preview",
          systemImage: "video.fill",
          role: .neutral
        )
      ] + (drawingStudioIsAvailable
        ? [CompletedComparisonReviewControl(
          action: .openDrawingStudio,
          title: "Open Drawing Studio",
          systemImage: "scribble.variable",
          role: .affirmative
        )]
        : [])
    }
  }
}

struct CompletedComparisonReviewControls: View {
  let presentation: CompletedComparisonReviewPresentation
  let displayedFrame: DisplayedFrame?
  let perform: (CompletedComparisonReviewAction) -> Void

  var body: some View {
    let status = presentation.displayStatus(for: displayedFrame)
    VStack(alignment: .trailing, spacing: 7) {
      Text(status.message)
        .font(.caption.monospaced())
        .foregroundStyle(statusColor(status))
        .multilineTextAlignment(.trailing)
        .fixedSize(horizontal: false, vertical: true)
      HStack(spacing: 7) {
        ForEach(presentation.controls) { control in
          Button {
            perform(control.action)
          } label: {
            Label(control.title, systemImage: control.systemImage)
          }
          .operatorButton(control.role)
          .controlSize(.small)
        }
      }
    }
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
