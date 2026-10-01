import PlotterModel
import SwiftUI

/// An observable chooser can update while open; a native Menu snapshots its items.
struct PortraitSavedStylesView: View {
  let model: PortraitStudioModel
  let strokeStyle: PlotterModel.StrokeStyle
  @State private var isPresented = false

  var body: some View {
    Button { isPresented.toggle() } label: {
      HStack(spacing: 4) {
        Text("Saved styles")
        if model.sketches.savedStylesState == .loading {
          ProgressView().controlSize(.mini)
        } else if !model.sketches.savedStyles.isEmpty {
          Text("\(model.sketches.savedStyles.count)").foregroundStyle(.secondary)
        }
      }
    }
    .accessibilityIdentifier("portrait.savedStyles")
    .popover(isPresented: $isPresented) {
      VStack(alignment: .leading, spacing: 8) {
        Text("Saved styles").font(.headline)
        if !model.sketches.savedStyles.isEmpty {
          ScrollView {
            VStack(alignment: .leading, spacing: 4) {
              ForEach(model.sketches.savedStyles) { saved in
                Button {
                  model.applySavedStyle(saved, strokeStyle: strokeStyle)
                  isPresented = false
                } label: {
                  VStack(alignment: .leading) {
                    Text(saved.name)
                    Text(saved.recipe.style.rawValue).font(.caption).foregroundStyle(.secondary)
                  }.frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain).padding(4).disabled(model.isCapturing)
                .contextMenu {
                  Button("Delete saved style", role: .destructive) { model.sketches.removeStyle(saved.id) }
                }
              }
            }
          }.frame(maxHeight: 280)
        }
        switch model.sketches.savedStylesState {
        case .loading: Text("Loading saved styles…").foregroundStyle(.secondary)
        case .failed(let reason):
          Text("Saved styles couldn't load.").foregroundStyle(.orange)
          Text(reason).font(.caption).textSelection(.enabled)
          Button("Retry") { model.sketches.retryPersistence() }
        case .saved, .pending:
          if model.sketches.savedStyles.isEmpty { Text("No saved styles").foregroundStyle(.secondary) }
          if case .failed = model.sketches.persistenceState {
            Text("History is unavailable. Loaded recipes remain usable.").font(.caption).foregroundStyle(.orange)
            Button("Retry history load") { model.sketches.retryPersistence() }
          }
        }
      }.padding(12).frame(width: 260)
      .accessibilityIdentifier("portrait.savedStylesChooser")
    }
  }
}
