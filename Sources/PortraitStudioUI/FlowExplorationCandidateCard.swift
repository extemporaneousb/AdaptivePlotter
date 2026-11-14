import SwiftUI
import PortraitLibrary

/// The primary image/title hit area chooses one direction; editing and training
/// exclusion remain separate secondary actions.
struct FlowExplorationCandidateCard: View {
  let model: FlowAuthoringModel
  let candidate: FlowPortfolioCandidate

  private var drawingTitle: String { model.drawingName(candidate) }
  private var refinementReason: String? { model.candidateRefinementUnavailableReason(candidate) }
  private var unavailableReason: String? { model.candidateUnavailableReason(candidate) }
  private var actionLabel: String {
    if let refinementReason { return drawingTitle + ": " + refinementReason }
    return "Choose and refine " + drawingTitle
  }
  private var actionHelp: String {
    refinementReason ?? "Choose this direction and generate closer variations. Records one weak preference against this offered set."
  }
  private var metadata: String {
    candidate.recipe.themeTitle + " · \(candidate.strokeCount) source lines" + (candidate.excluded ? " · excluded" : "")
  }
  private var availabilityCaption: String? {
    guard let refinementReason else { return nil }
    return unavailableReason == nil ? "Variations unavailable: " + refinementReason : refinementReason
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      imageButton
      HStack {
        Button("Choose and refine") { Task { await model.exploreCandidate(candidate.id) } }
          .buttonStyle(.borderedProminent)
          .accessibilityIdentifier("flowAuthoring.choose.\(candidate.slot)")
      }.disabled(!model.canRefineCandidate(candidate))
      if let availabilityCaption {
        Text(availabilityCaption).font(.caption).foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
      secondaryActions
    }.padding(10).background(.background, in: RoundedRectangle(cornerRadius: 8))
      .overlay {
        RoundedRectangle(cornerRadius: 8).stroke(model.candidate?.id == candidate.id
          ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: 1)
      }
  }

  private var imageButton: some View {
    Button { Task { await model.exploreCandidate(candidate.id) } } label: {
      VStack(alignment: .leading, spacing: 6) {
        FlowAuthoringImage(data: model.previews[candidate.id], identity: model.previewIdentity(candidate: candidate))
          .frame(maxWidth: .infinity).frame(height: 220)
        HStack {
          Text(drawingTitle).font(.headline)
          Spacer()
          if candidate.id == model.round?.recommendedCandidateID {
            Label(model.isPredictedFavorite(candidate) ? "Predicted favorite" : "Suggested", systemImage: "sparkle").font(.caption)
          }
        }
        Text(metadata).font(.caption).foregroundStyle(.secondary)
      }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
    }.buttonStyle(.plain).disabled(!model.canRefineCandidate(candidate))
      .accessibilityLabel(actionLabel)
      .accessibilityIdentifier("flowAuthoring.tile.\(candidate.slot)")
      .help(actionHelp)
  }

  private var secondaryActions: some View {
    HStack {
      Button("Edit drawing") { Task { await model.browseCandidate(candidate.id, prune: true) } }
        .disabled(unavailableReason != nil)
        .help(unavailableReason ?? "Remove or restore whole lines.")
      Spacer()
      Button { Task { await model.excludeCandidate(candidate, excluded: !candidate.excluded) } } label: {
        Image(systemName: candidate.excluded ? "eye.slash" : "eye")
      }.help(candidate.excluded ? "Include in training" : "Exclude from training")
    }.disabled(model.isBusy || model.needsRecovery)
  }
}
