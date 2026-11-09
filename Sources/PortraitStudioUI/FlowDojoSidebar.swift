import SwiftUI
import PortraitLibrary
import PortraitCore
import DrawingLibrary

package struct FlowDojoSidebar: View {
  @Bindable var model: FlowDojoModel
  @State private var expandedRounds = Set<UUID>()
  @State private var renaming: RenameTarget?
  @State private var photos: [DrawingLibraryPhotoEntry] = []
  @State private var photoCursor: DrawingLibraryPhotoCursor?
  @State private var photoFailure: String?

  package var body: some View {
    GeometryReader { geometry in
      sidebar(compact: geometry.size.height < 500)
    }
  }

  private func sidebar(compact: Bool) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      if let source = model.selectedSource {
        FlowDojoImage(data: model.sourceData, identity: source.image.sha256, maximumDimension: 280).frame(maxWidth: .infinity).frame(height: compact ? 84 : 132)
          .accessibilityLabel("Selected photo: " + model.photoName(source))
        Text(model.photoName(source)).font(.headline).lineLimit(2).padding(.horizontal, 10)
        Text("Drawings and branches belong to this photo").font(.caption).foregroundStyle(.secondary).padding(.horizontal, 10)
      }
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 6) {
          Text("Photos").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
          ForEach(photos, id: \.reference) { photo in
            Button { Task { await model.selectPhoto(photo.reference) } } label: {
              HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                  Text(photo.metadata.title ?? "Photo").lineLimit(1)
                  Text(photo.sortDate?.formatted(date: .abbreviated, time: .omitted) ?? "Date unknown")
                    .font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
              }.padding(5).contentShape(Rectangle())
                .background(photo.reference == model.currentPhotoRef ? Color.accentColor.opacity(0.14) : .clear, in: RoundedRectangle(cornerRadius: 5))
            }.buttonStyle(.plain)
              .help("Open this exact Library Photo without recording preference.")
          }
          if photoCursor != nil { Button("More Photos") { Task { await loadPhotos(more: true) } } }
          if let photoFailure { Text(photoFailure).font(.caption).foregroundStyle(.orange) }
        }.padding(10)
      }.frame(height: compact ? 140 : 180)
      Divider()
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 6) {
          if let source = model.selectedSource {
            Text("Branches · " + model.photoName(source)).font(.caption.weight(.semibold)).lineLimit(1)
            ForEach(model.branches(for: source.id)) { round in
              branch(round)
            }
          }
        }.padding(10)
      }
    }.padding(.top, 8)
      .disabled(model.isBusy || model.needsRecovery)
      .onChange(of: model.round?.id, initial: true) { _, id in if let id { expandedRounds.insert(id) } }
      .task { await loadPhotos() }
      .onChange(of: model.document?.sources.count) { _, _ in Task { await loadPhotos() } }
      .overlay(alignment: .bottom) { if let target = renaming {
        FlowDojoNameEditor(name: target.name, title: target.photo ? "Photo name" : "Drawing name", changed: { name in
          model.queueName(target.id, photo: target.photo, title: name)
        }, flush: { await model.flushMetadataEdits() }, close: { renaming = nil }).disabled(false).background(.regularMaterial)
      } }
  }
  private func loadPhotos(more: Bool = false) async {
    do {
      guard let library = model.drawingLibrary else { return }
      let page = try await library.photos(after: more ? photoCursor : nil)
      guard !Task.isCancelled else { return }
      photos = more ? photos + page.entries : page.entries; photoCursor = page.next
    } catch { photoFailure = error.localizedDescription }
  }

  private func branch(_ round: FlowPortfolioRound) -> some View {
    VStack(alignment: .leading, spacing: 5) {
      HStack(spacing: 4) {
        Button { if !expandedRounds.insert(round.id).inserted { expandedRounds.remove(round.id) } } label: {
          Image(systemName: expandedRounds.contains(round.id) ? "chevron.down" : "chevron.right").frame(width: 14)
        }.buttonStyle(.plain).accessibilityLabel("Expand " + model.roundName(round))
        Button { Task { await model.selectRound(round.id) } } label: {
          VStack(alignment: .leading, spacing: 2) {
            Text(model.roundName(round) + (round.parentCandidateID == nil ? " · Broad" : " · Refinement")).fontWeight(model.round?.id == round.id ? .semibold : .regular)
            if let id = round.parentCandidateID, let parent = model.document?.candidates.first(where: { $0.id == id }) {
              Text("↳ " + model.drawingName(parent)).font(.caption).foregroundStyle(.secondary)
            }
          }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
        }.buttonStyle(.plain)
      }.padding(.leading, CGFloat(min(3, model.branchDepth(round))) * 7)
      if expandedRounds.contains(round.id) {
        ForEach(round.candidateIDs.compactMap { id in model.document?.candidates.first(where: { $0.id == id }) }) { candidate in
          Button { Task { await model.browseCandidate(candidate.id, prune: true) } } label: {
            HStack(spacing: 7) {
              CandidateThumbnail(model: model, candidate: candidate).frame(width: 42, height: 48)
              VStack(alignment: .leading, spacing: 2) {
                Text(model.drawingName(candidate)).lineLimit(1)
                if let edit = model.document?.latestPrune(candidateID: candidate.id) {
                  Text("\(edit.removedIndices.count) removed" + (edit.action == .completeTarget ? " · target" : ""))
                    .font(.caption).foregroundStyle(.secondary)
                } else { Text("Generated").font(.caption).foregroundStyle(.secondary) }
              }
              Spacer(minLength: 0)
            }.padding(4).contentShape(Rectangle())
              .background(model.candidate?.id == candidate.id ? Color.accentColor.opacity(0.14) : .clear, in: RoundedRectangle(cornerRadius: 4))
          }.buttonStyle(.plain).padding(.leading, 18)
            .help("Open this drawing without recording a preference")
            .contextMenu { Button("Rename drawing…") { renaming = .init(id: candidate.id, photo: false, name: model.drawingName(candidate)) } }
        }
      }
    }.padding(.vertical, 3)
  }
  private struct RenameTarget: Identifiable { let id: UUID; let photo: Bool; let name: String }
}

private struct CandidateThumbnail: View {
  let model: FlowDojoModel
  let candidate: FlowPortfolioCandidate
  @State private var data: Data?
  @State private var loadedKey: String?
  var body: some View {
    let key = model.previewIdentity(candidate: candidate)
    FlowDojoImage(data: loadedKey == key ? data : nil, identity: key, maximumDimension: 280).task(id: key) {
      data = nil; loadedKey = nil
      let pixels = await model.thumbnail(candidate: candidate)
      guard !Task.isCancelled, model.previewIdentity(candidate: candidate) == key else { return }
      data = pixels; loadedKey = key
    }
  }
}

private struct FlowDojoNameEditor: View {
  @State var name: String
  let title: String
  let changed: (String) -> Void
  let flush: () async -> Void
  let close: () -> Void
  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(title).font(.headline)
      TextField(title, text: $name).onChange(of: name) { _, value in changed(value) }
      Text("Names are saved automatically. Original images and drawing identities stay unchanged.").font(.caption).foregroundStyle(.secondary)
      HStack { Spacer(); Button("Done") { Task { await flush(); close() } }.keyboardShortcut(.defaultAction) }
    }.padding(20).frame(width: 400).onDisappear { Task { await flush() } }
  }
}
