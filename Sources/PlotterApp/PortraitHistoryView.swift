import ImageIO
import PlotterModel
import SwiftUI

struct PortraitHistoryView: View {
  let model: PortraitStudioModel
  let strokeStyle: PlotterModel.StrokeStyle
  @State private var onlyPromising = false

  private var entries: [PortraitRetainedCandidate] {
    model.sketches.attempts.filter { !onlyPromising || $0.attempt?.feedback == .promising || !$0.reasons.isEmpty }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack {
        Text("History · \(model.sketches.attempts.count)").font(.caption)
        Toggle("Kept", isOn: $onlyPromising).toggleStyle(.button).controlSize(.mini)
          .help("Show promising attempts and saved imaginations")
        Spacer()
        if model.sketches.persistenceState == .pending || model.sketches.persistenceState == .loading {
          ProgressView().controlSize(.mini).help("Saving attempt history")
        }
        Menu {
          Button("Clear unkept history") { model.clearUnkeptHistory() }
          Text("Keeps current, promising and saved imaginations")
        } label: { Image(systemName: "ellipsis") }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .accessibilityLabel("History actions")
      }
      ScrollView(.horizontal) {
        LazyHStack(spacing: 6) {
          ForEach(entries) { entry in
            Button { model.inspectAttempt(entry.id, strokeStyle: strokeStyle) } label: {
              VStack(spacing: 2) {
                PortraitAttemptThumbnailView(data: entry.attempt?.thumbnailPNG, identity: entry.id)
                  .frame(width: 40, height: 40)
                  .background(.white)
                  .overlay(alignment: .topTrailing) {
                    if entry.attempt?.feedback == .promising { Image(systemName: "plus.circle.fill").foregroundStyle(.green) }
                    else if entry.attempt?.feedback == .rejected { Image(systemName: "minus.circle.fill").foregroundStyle(.secondary) }
                  }
                  .overlay {
                    RoundedRectangle(cornerRadius: 4)
                      .stroke(model.selectedCandidate?.id == entry.id ? Color.accentColor : .clear, lineWidth: 2)
                  }
                Text(entry.attempt?.changeCue ?? entry.candidate.recipe.title)
                  .font(.caption2).lineLimit(1).frame(width: 60)
              }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Inspect \(entry.candidate.recipe.title), \(entry.attempt?.feedback.rawValue ?? "unknown")")
            .accessibilityIdentifier("portrait.history.\(entry.id)")
            .help("\(entry.candidate.recipe.title) · \(entry.candidate.program.strokes.count) strokes. Inspecting does not change feedback.")
            .contextMenu {
              Button("Mark promising") { model.sketches.setFeedback(.promising, for: entry.id) }
              Button("Mark rejected") { model.sketches.setFeedback(.rejected, for: entry.id) }
              Button("Clear feedback") { model.sketches.setFeedback(.unknown, for: entry.id) }
              Divider()
              Button("Delete Attempt", role: .destructive) { model.deleteAttempt(entry.id) }
            }
          }
        }.padding(2)
      }
      .scrollIndicators(.hidden)
      .frame(height: 58)
    }
    .accessibilityIdentifier("portrait.history")
  }
}

struct PortraitAttemptThumbnailView: View {
  let data: Data?
  let identity: String
  @State private var image: CGImage?
  var body: some View {
    Group {
      if let image { Image(decorative: image, scale: 1).resizable().scaledToFit() }
      else { Color.secondary.opacity(0.08) }
    }
    .task(id: identity) {
      let data = data
      let decoded = await Task.detached(priority: .utility) {
        guard let data, let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil as CGImage? }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
      }.value
      if !Task.isCancelled { image = decoded }
    }
  }
}
