import SwiftUI
import PlotterEpisodeRuntime

extension DrawingStudioRunState {
  /// Active work and retained outcomes stay visible until the existing run handoff.
  /// This semantic value contains no camera frames, timer, or action owner.
  var showsActiveRunStatus: Bool {
    switch self {
    case .running, .processing, .publicationFailed, .publicationIncomplete, .terminal, .reviewAvailable, .reviewing: true
    case .unavailable, .ready: false
    }
  }
}

/// Quiet status companion to the existing capability-owned Stop surface.
/// Equatable input keeps camera and preview traffic out of this presentation.
struct DrawingStudioActiveRunStatus: View, Equatable {
  let runState: DrawingStudioRunState
  var terminalDisposition: PlotterDrawingRunTerminalDisposition? = nil

  var statusTitle: String {
    guard let terminalDisposition else { return runState.title }
    switch terminalDisposition {
    case .refused: return "Drawing refused"
    case .cancelled: return "Drawing stopped"
    case .ambiguous, .possibleInk: return "Drawing interrupted"
    case .publicationIncomplete: return "Drawing evidence not saved"
    case .nonAttributable, .visionRejected, .succeeded: return "Drawing finished"
    }
  }

  var body: some View {
    if runState.showsActiveRunStatus {
      HStack(spacing: 6) {
        Text(statusTitle).font(.headline)
        StudioHelpButton(statusTitle, text: runState.detail)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.horizontal, 12).padding(.vertical, 6)
      .accessibilityElement(children: .contain)
      .accessibilityIdentifier("drawing.activeRunStatus")
    }
  }
}
