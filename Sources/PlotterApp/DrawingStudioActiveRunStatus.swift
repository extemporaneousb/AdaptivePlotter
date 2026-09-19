import SwiftUI

extension DrawingStudioRunState {
  /// Only unsettled work stays visible outside the scrollable Studio workflow.
  /// This semantic value contains no camera frames, timer, or action owner.
  var showsActiveRunStatus: Bool {
    switch self {
    case .running, .processing, .publicationFailed: true
    case .unavailable, .ready, .terminal, .reviewAvailable, .reviewing: false
    }
  }
}

/// Quiet status companion to the existing capability-owned Stop surface.
/// Equatable input keeps camera and preview traffic out of this presentation.
struct DrawingStudioActiveRunStatus: View, Equatable {
  let runState: DrawingStudioRunState

  var body: some View {
    if runState.showsActiveRunStatus {
      HStack(spacing: 6) {
        Text(runState.title).font(.headline)
        StudioHelpButton(runState.title, text: runState.detail)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.horizontal, 12).padding(.vertical, 6)
      .accessibilityElement(children: .contain)
      .accessibilityIdentifier("drawing.activeRunStatus")
    }
  }
}
