import PlotterModel
import SwiftUI

struct PortraitAttemptFeedbackButtons: View {
  let model: PortraitStudioModel
  let candidate: PortraitCandidate
  var body: some View {
    let feedback = model.feedback(for: candidate)
    HStack(spacing: 10) {
      Button { model.toggleFeedback(.promising, candidate: candidate) } label: {
        Image(systemName: feedback == .promising ? "plus.circle.fill" : "plus.circle")
      }
      .foregroundStyle(feedback == .promising ? Color.green : .secondary)
      .help("Promising: retain this exact attempt. Click again to clear feedback.")
      .accessibilityLabel("Mark promising")
      .accessibilityIdentifier("portrait.feedback.plus.\(candidate.id)")
      Button { model.toggleFeedback(.rejected, candidate: candidate) } label: {
        Image(systemName: feedback == .rejected ? "minus.circle.fill" : "minus.circle")
      }
      .foregroundStyle(feedback == .rejected ? Color.orange : .secondary)
      .help("Reject this exact treatment without deleting it. Click again to clear feedback.")
      .accessibilityLabel("Mark rejected")
      .accessibilityIdentifier("portrait.feedback.minus.\(candidate.id)")
    }.buttonStyle(.plain)
  }
}
