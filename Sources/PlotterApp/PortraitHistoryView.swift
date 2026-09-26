import PlotterModel
import SwiftUI

struct PortraitHistoryView: View {
  let model: PortraitStudioModel
  let strokeStyle: PlotterModel.StrokeStyle
  var didSelect: () -> Void = {}
  @State private var onlyPromising = false
  @State private var allPhotos = false

  var body: some View {
    let entries = model.sketches.attempts.filter { entry in
      (allPhotos || entry.candidate.photoID == model.selectedPhotoID)
        && (!onlyPromising || entry.attempt?.feedback == .promising || !entry.reasons.isEmpty)
    }
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Text("History · \(entries.count)").font(.headline)
        Spacer()
        Menu {
          Button("Clear unkept history") { model.clearUnkeptHistory() }
          Text("Keeps current, promising and saved imaginations")
        } label: { Image(systemName: "ellipsis") }
        .menuStyle(.borderlessButton).fixedSize().accessibilityLabel("History actions")
      }
      HStack {
        Toggle("All photos", isOn: $allPhotos)
        Toggle("Kept only", isOn: $onlyPromising)
      }.toggleStyle(.checkbox).controlSize(.small)
      List(entries) { entry in
        Button {
          model.inspectAttempt(entry.id, strokeStyle: strokeStyle)
          didSelect()
        } label: {
          HStack {
            Image(systemName: model.selectedCandidate?.id == entry.id ? "checkmark.circle.fill" : "circle")
              .foregroundStyle(model.selectedCandidate?.id == entry.id ? Color.accentColor : .secondary)
            VStack(alignment: .leading, spacing: 2) {
              Text(entry.attempt?.changeCue ?? entry.candidate.recipe.title).lineLimit(1)
              Text("\(entry.candidate.program.strokes.count) strokes · \(entry.candidate.createdAt.formatted(date: .abbreviated, time: .shortened))")
                .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if entry.attempt?.feedback == .promising { Image(systemName: "plus.circle.fill").foregroundStyle(.green) }
            if entry.attempt?.feedback == .rejected { Image(systemName: "minus.circle.fill").foregroundStyle(.orange) }
          }.contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("portrait.history.\(entry.id)")
        .contextMenu {
          Button("Mark promising") { model.sketches.setFeedback(.promising, for: entry.id) }
          Button("Mark rejected") { model.sketches.setFeedback(.rejected, for: entry.id) }
          Button("Clear feedback") { model.sketches.setFeedback(.unknown, for: entry.id) }
          Divider()
          Button("Delete Attempt", role: .destructive) { model.deleteAttempt(entry.id) }
        }
      }
      .overlay {
        if entries.isEmpty { Text("No attempts in this view").foregroundStyle(.secondary) }
      }
    }.accessibilityIdentifier("portrait.history")
  }
}
