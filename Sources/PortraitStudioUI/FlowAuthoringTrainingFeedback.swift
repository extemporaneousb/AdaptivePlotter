import SwiftUI
import Foundation

/// Coverage is computed by the fitter's supervision plan. A saved decision is
/// not reported as a trained or active model.
package struct FlowAuthoringTrainingFeedback: View {
  @Bindable var model: FlowAuthoringModel
  package var body: some View {
    if let progress = model.trainingProgress {
      HStack(alignment: .top, spacing: 12) {
        VStack(alignment: .leading, spacing: 3) {
          Text(trainingState(progress)).font(.callout.weight(.medium))
          Text(stageHint(progress)).font(.caption).foregroundStyle(.secondary).lineLimit(2)
        }
        Spacer(minLength: 4)
        if model.stage != .fit {
          Button(progress.latestFitRevision == nil ? "Train artist…" : "Training results…") { model.stage = .fit }
        }
      }.padding(.horizontal, 10).padding(.vertical, 7)
        .background(.quaternary.opacity(0.28), in: RoundedRectangle(cornerRadius: 6))
        .accessibilityIdentifier("flowAuthoring.trainingFeedback")
    }
  }

  private func trainingState(_ progress: FlowAuthoringTrainingProgress) -> String {
    let saved = FlowAuthoringFeedbackText.coverage(progress, stage: model.stage,
      selectedSourceID: model.selectedSource?.id)
    let state: String
    if model.activeModelIssue != nil { state = "retained artist needs refitting for the current drawing model" }
    else if progress.latestFitRevision == nil { state = "artist not trained" }
    else if model.activeCheckpoint == nil { state = "no active artist" }
    else if progress.activeHasTrainingChanges == true { state = "artist active · new feedback available for training" }
    else if progress.activeHasTrainingChanges == nil { state = "artist active · checking training coverage" }
    else { state = "artist active · fitted feedback current" }
    return "Feedback saved · \(saved) · \(state)"
  }
  private func stageHint(_ progress: FlowAuthoringTrainingProgress) -> String {
    switch model.stage {
    case .explore:
      return "Opening drawings only navigates. Choose direction records a weak preference; Compare this set records an explicit artistic judgment."
    case .prune:
      let photo = model.selectedSource.map { progress.photo($0.id) }
      return "This photo: \(photo?.removeLabelCount ?? 0) remove and \(photo?.keepLabelCount ?? 0) keep labels. Finish pruning teaches the complete kept/removed target; edits are already saved."
    case .rank:
      return "Prefer a drawing, mark equal, or assign ranks. Neither and Skip preserve the review without inventing a preference."
    case .fit:
      return progress.readinessMessage
    }
  }
}

/// Fit summarizes the whole portfolio. Other stages describe only the selected
/// photo, including partial line judgments that have no completed target yet.
package enum FlowAuthoringFeedbackText {
  package static func coverage(_ progress: FlowAuthoringTrainingProgress,
    stage: FlowAuthoringModel.Stage, selectedSourceID: UUID?) -> String {
    guard stage != .fit, let selectedSourceID else {
      return "Portfolio: \(progress.feedbackPhotoCount) photos with feedback · \(progress.choiceCount) directions · \(progress.rankingCount) comparisons · \(progress.removeLabelCount) remove / \(progress.keepLabelCount) keep labels"
    }
    let photo = progress.photo(selectedSourceID)
    return "This photo: \(photo.choiceCount) directions · \(photo.rankingCount) comparisons · \(photo.removeLabelCount) remove / \(photo.keepLabelCount) keep labels · \(photo.completedTargetCount) targets"
  }
}
