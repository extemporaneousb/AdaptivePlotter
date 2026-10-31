import SwiftUI
import PortraitLibrary

package struct FlowDojoSidebar: View {
  @Bindable var model: FlowDojoModel
  @State private var expandedRounds = Set<UUID>()
  @State private var renaming: RenameTarget?

  package var body: some View {
    GeometryReader { geometry in
      sidebar(compact: geometry.size.height < 500)
    }
  }

  private func sidebar(compact: Bool) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      if let source = model.selectedSource {
        FlowDojoImage(data: model.sourceData).frame(maxWidth: .infinity).frame(height: compact ? 84 : 132)
          .accessibilityLabel("Selected photo: " + model.photoName(source))
        Text(model.photoName(source)).font(.headline).lineLimit(2).padding(.horizontal, 10)
        Text("Drawings and branches belong to this photo").font(.caption).foregroundStyle(.secondary).padding(.horizontal, 10)
      }
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 6) {
          Text("Photos").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
          ForEach(model.document?.sources ?? []) { source in
            Button { Task { await model.selectSource(source.id) } } label: {
              HStack(spacing: 8) {
                SourceThumbnail(model: model, source: source).frame(width: 46, height: 48)
                VStack(alignment: .leading, spacing: 3) {
                  Text(model.photoName(source)).lineLimit(2)
                  if let item = model.representative(for: source.id),
                    let drawing = model.document?.candidates.first(where: { $0.id == item.candidateID }) {
                    Text(model.drawingName(drawing)).font(.caption).foregroundStyle(.secondary)
                  } else { Text("No drawings yet").font(.caption).foregroundStyle(.secondary) }
                  if let feedback = model.trainingProgress?.photo(source.id) {
                    Text("\(feedback.candidateCount) drawings · \(feedback.rankingCount) comparisons · \(feedback.completedTargetCount) targets")
                      .font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                  }
                }
                Spacer(minLength: 0)
              }.padding(5).contentShape(Rectangle())
                .background(source.id == model.selectedSource?.id ? Color.accentColor.opacity(0.14) : .clear, in: RoundedRectangle(cornerRadius: 5))
            }.buttonStyle(.plain)
              .help("Representative drawing from a saved comparison or choice; otherwise the latest edit. Clicking opens the photo without a preference judgment.")
              .contextMenu { Button("Rename photo…") { renaming = .init(id: source.id, photo: true, name: model.photoName(source)) } }
          }
        }.padding(10)
      }.frame(height: min(compact ? 140 : 180, CGFloat(model.document?.sources.count ?? 0) * 80 + 30))
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
      .sheet(item: $renaming) { target in
        FlowDojoNameEditor(name: target.name, title: target.photo ? "Photo name" : "Drawing name", changed: { name in
          model.queueName(target.id, photo: target.photo, title: name)
        }, flush: { await model.flushMetadataEdits() }).disabled(false)
      }
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

private struct SourceThumbnail: View {
  let model: FlowDojoModel
  let source: FlowPortfolioSource
  @State private var data: Data?
  var body: some View { FlowDojoImage(data: data).task(id: model.representativeKey(source)) { data = await model.representativeThumbnail(source) } }
}
private struct CandidateThumbnail: View {
  let model: FlowDojoModel
  let candidate: FlowPortfolioCandidate
  @State private var data: Data?
  var body: some View {
    FlowDojoImage(data: data).task(id: model.document?.latestPrune(candidateID: candidate.id)?.id ?? candidate.id) {
      data = await model.thumbnail(candidate: candidate)
    }
  }
}

private struct FlowDojoNameEditor: View {
  @State var name: String
  let title: String
  let changed: (String) -> Void
  let flush: () async -> Void
  @Environment(\.dismiss) private var dismiss
  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(title).font(.headline)
      TextField(title, text: $name).onChange(of: name) { _, value in changed(value) }
      Text("Names are saved automatically. Original images and drawing identities stay unchanged.").font(.caption).foregroundStyle(.secondary)
      HStack { Spacer(); Button("Done") { Task { await flush(); dismiss() } }.keyboardShortcut(.defaultAction) }
    }.padding(20).frame(width: 400).onDisappear { Task { await flush() } }
  }
}
