import PlotterModel
import SwiftUI

struct PortraitStyleBrowser: View {
  let model: PortraitStudioModel
  let strokeStyle: PlotterModel.StrokeStyle

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Picker("Style recipe", selection: Binding(get: { model.currentRecipe.id }, set: { id in
        if let recipe = model.styleRecipes.first(where: { $0.id == id }) {
          model.applyRecipe(recipe, strokeStyle: strokeStyle)
        }
      })) {
        if model.currentRecipe.id == "custom" { Text("Custom").tag("custom") }
        ForEach(model.styleRecipes) { Text($0.title).tag($0.id) }
      }.accessibilityIdentifier("portrait.recipe")
      HStack {
        Button { model.moveStyle(by: -1, strokeStyle: strokeStyle) } label: {
          Image(systemName: "chevron.left").frame(minWidth: 24, minHeight: 24)
        }.accessibilityLabel("Previous style, same frame")
          .keyboardShortcut(.upArrow, modifiers: [.option])
        Button("Random Style") { model.randomStyle(strokeStyle: strokeStyle) }
          .accessibilityIdentifier("portrait.randomStyle")
        Button { model.moveStyle(by: 1, strokeStyle: strokeStyle) } label: {
          Image(systemName: "chevron.right").frame(minWidth: 24, minHeight: 24)
        }.accessibilityLabel("Next style, same frame")
          .keyboardShortcut(.downArrow, modifiers: [.option])
      }
      Button("New Big-head Candidate") { model.randomStyle(strokeStyle: strokeStyle, bigHead: true) }
        .accessibilityIdentifier("portrait.bigHeadCandidate")
      Text("Same frame · ⌥↑ / ⌥↓ to browse styles. Random choices remain in the picker, up to 24.")
        .font(.caption2).foregroundStyle(.secondary)
    }
  }
}
