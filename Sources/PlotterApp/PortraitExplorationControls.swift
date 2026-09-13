import PlotterRuntime
import SwiftUI

/// Candidate navigation restores completed drawings. It neither generates a
/// replacement nor qualifies an otherwise transient candidate for retention.
struct PortraitExplorationControls: View {
  let model: PortraitStudioModel

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Button("More Like This") {
        WorkbenchRequestTelemetry.nativeActionHandled("portrait.moreLikeThis")
        model.moreLikeThis()
      }
      .disabled(!model.canExploreSelection)
      .accessibilityIdentifier("portrait.moreLikeThis")
      .help("Create a nearby variation from the displayed drawing, including a retained drawing.")
      HStack {
        Button {
          WorkbenchRequestTelemetry.nativeActionHandled("portrait.historyBack")
          model.historyBack()
        } label: { Label("Back", systemImage: "arrow.backward") }
        .disabled(!model.history.canGoBack)
        .accessibilityIdentifier("portrait.historyBack")
        .help("Restore the previous completed drawing exactly.")
        Button {
          WorkbenchRequestTelemetry.nativeActionHandled("portrait.historyForward")
          model.historyForward()
        } label: { Label("Forward", systemImage: "arrow.forward") }
        .disabled(!model.history.canGoForward)
        .accessibilityIdentifier("portrait.historyForward")
        Button {
          WorkbenchRequestTelemetry.nativeActionHandled("portrait.historyParent")
          model.historyParent()
        } label: { Label("Parent", systemImage: "arrow.turn.up.left") }
        .disabled(model.explorationParent == nil)
        .accessibilityIdentifier("portrait.historyParent")
        .help("Restore the exact drawing used to create this variation.")
      }
      if !model.explorationBranches.isEmpty {
        Text("Variations of this drawing").font(.caption).foregroundStyle(.secondary)
        ScrollView(.horizontal) {
          LazyHStack(alignment: .top, spacing: 8) {
            ForEach(model.explorationBranches) { candidate in
              Button {
                WorkbenchRequestTelemetry.nativeActionHandled("portrait.historyChild")
                model.selectHistory(candidate.id)
              } label: {
                VStack(alignment: .leading, spacing: 4) {
                  PortraitProgramPreview(program: candidate.program)
                    .frame(width: 100, height: 110)
                  Text(candidate.recipe.title).font(.caption2).lineLimit(2)
                    .frame(width: 100, alignment: .leading)
                }
              }
              .buttonStyle(.plain)
              .accessibilityLabel("Restore variation \(candidate.recipe.title)")
              .accessibilityIdentifier("portrait.historyChild.\(candidate.id)")
            }
          }.padding(3)
        }
      }
      Text("More Like This varies the displayed recipe. Back, Forward, and Parent restore exact drawings. Exploration stays temporary until you Keep, rate, or accept on plotter video.")
        .font(.caption2).foregroundStyle(.secondary)
      Text("Drawing history: up to 24 candidates / 96 MiB this session.")
        .font(.caption2).foregroundStyle(.secondary)
      if let status = model.explorationStatus {
        Text(status).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
      }
      if let status = model.history.status {
        Text(status).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
      }
    }
  }
}
