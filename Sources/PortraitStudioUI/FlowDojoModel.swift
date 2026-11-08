import AppKit
import Foundation
import Observation
import PlotterModel
import PortraitArtists
import PortraitCore
import PortraitLibrary
import DrawingLibrary

/// A physical authoring declaration, independent of preview geometry units.
package struct FlowDojoAuthoringContext: Equatable, Sendable {
  package let strokeStyle: StrokeStyle
  package let nominalPenWidthMM: Double?
  package init(strokeStyle: StrokeStyle, nominalPenWidthMM: Double?) {
    self.strokeStyle = strokeStyle
    self.nominalPenWidthMM = nominalPenWidthMM
  }
}

@Observable @MainActor
package final class FlowDojoModel {
  package enum Stage: String, CaseIterable { case explore = "Explore", prune = "Prune", rank = "Rank", fit = "Fit & deploy" }
  package nonisolated static var defaultDirectory: URL {
    FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/AdaptivePlotter/DrawingLibrary", isDirectory: true)
  }
  package private(set) var directory: URL
  package private(set) var document: FlowPortfolioSnapshot?
  package private(set) var sourceData: Data?
  package private(set) var program: DrawingProgram?
  package private(set) var previews: [UUID: Data] = [:]
  package private(set) var rankingPreviews: [UUID: Data] = [:]
  package private(set) var isBusy = false
  package private(set) var progress = "Opening portfolio…"
  package private(set) var error: String?
  package private(set) var needsRecovery = false
  package private(set) var pendingMetadataCount = 0
  package var stage: Stage = .explore
  package var count = 6
  package var tool: PortraitLineEditModel.Tool = .erase
  package var selection: Set<StrokeID> = []
  package var zoom = 1.0
  package var showsOriginal = false
  package var showsPhoto = false
  package private(set) var presentation: FlowPortfolioPresentation?
  package private(set) var ranks: [UUID: Int] = [:]
  package private(set) var reportSummary: String?
  package private(set) var fitReport: FlowArtistFitReport?
  package private(set) var activeModelIssue: String?
  package private(set) var activeCheckpoint: FlowArtistCheckpoint?
  package private(set) var trainingProgress: FlowDojoTrainingProgress?
  @ObservationIgnored private let library: DrawingLibrary?
  @ObservationIgnored package private(set) var store: FlowPortfolioStore?
  @ObservationIgnored private let renderer = FlowDojoRenderer()
  @ObservationIgnored private var work: Task<Void, Never>?
  @ObservationIgnored private var recoveryWork: Task<Void, Never>?
  @ObservationIgnored private var rendering: Task<DrawingProduction<PortraitRenderResult>, Error>?
  @ObservationIgnored private var fitting: Task<FlowArtistFitReport, Error>?
  @ObservationIgnored private var lastWorkID: UUID?
  @ObservationIgnored private var cancelRequested = false
  @ObservationIgnored private var closed = false
  @ObservationIgnored private var closing = false
  @ObservationIgnored private var failedIntent: (status: String, baseline: Int, replayPartial: Bool, operation: @MainActor () async throws -> Void)?
  @ObservationIgnored private var blockedIntents: [(String, Bool, Bool, @MainActor () async throws -> Void)] = []
  @ObservationIgnored private var loadedSourceHash: String?
  @ObservationIgnored private var nameDebounce: Task<Void, Never>?
  @ObservationIgnored private var nameFlush: Task<Void, Never>?
  @ObservationIgnored private var nameFlushID: UUID?
  /// One-shot deterministic join seam for persistence tests; absent in the product.
  @ObservationIgnored private var metadataJoinHook: (@MainActor () async -> Void)?
  @ObservationIgnored private var pendingNames: [(id: UUID, photo: Bool, title: String, store: FlowPortfolioStore)] = []
  @ObservationIgnored private var pendingCurations: [(id: UUID, subject: String, session: String, excluded: Bool, store: FlowPortfolioStore)] = []
  @ObservationIgnored private var fittedDocument: FlowPortfolioSnapshot?
  @ObservationIgnored private var activeTrainingDocument: FlowPortfolioSnapshot?
  @ObservationIgnored private var fittedSnapshotID: UUID?
  @ObservationIgnored private var activeSnapshotID: UUID?
  @ObservationIgnored private var loadedProgramID: UUID?
  @ObservationIgnored private var previewKeys: [UUID: String] = [:]
  @ObservationIgnored private let purpose: FlowPortfolioPurpose?
  @ObservationIgnored private let renderOverride: (@Sendable (Data, FlowArtistRecipe, StrokeStyle) async throws -> PortraitRenderResult)?
  @ObservationIgnored private let fitOverride: (@Sendable ([FlowArtistExample], [FlowArtistRanking]) async throws -> FlowArtistFitReport)?
  package private(set) var strokeStyle: StrokeStyle
  package private(set) var nominalPenWidthMM: Double?

  package init(directory: URL = FlowDojoModel.defaultDirectory, library: DrawingLibrary? = nil,
    strokeStyle: StrokeStyle? = nil, nominalPenWidthMM: Double? = nil, purpose: FlowPortfolioPurpose? = nil,
    render: (@Sendable (Data, FlowArtistRecipe, StrokeStyle) async throws -> PortraitRenderResult)? = nil,
    fit: (@Sendable ([FlowArtistExample], [FlowArtistRanking]) async throws -> FlowArtistFitReport)? = nil,
    metadataJoinHook: (@MainActor () async -> Void)? = nil) {
    self.directory = library?.directoryURL ?? directory; self.library = library; self.purpose = purpose
    self.nominalPenWidthMM = nominalPenWidthMM
    self.strokeStyle = strokeStyle ?? (try! StrokeStyle(nominalLineWidth: 0.4,
      penProfileID: PenProfileID(UUID(uuidString: "00000000-0000-0000-0000-000000000001")!)))
    renderOverride = render; fitOverride = fit; self.metadataJoinHook = metadataJoinHook
  }
  package var selectedSource: FlowPortfolioSource? { document?.sources.first { $0.id == document?.selectedSourceID } }
  package var round: FlowPortfolioRound? { document?.rounds.first { $0.id == document?.currentRoundID } }
  package var candidate: FlowPortfolioCandidate? { document?.candidates.first { $0.id == document?.currentCandidateID } }
  package var prune: FlowPortfolioPruneRevision? { candidate.flatMap { document?.latestPrune(candidateID: $0.id) } }
  package var removedIndices: Set<Int> { Set(prune?.removedIndices ?? []) }
  package var removedIDs: Set<StrokeID> {
    guard let program else { return [] }
    return Set(program.strokes.enumerated().filter { removedIndices.contains($0.offset) }.map { $0.element.id })
  }
  package var roundCandidates: [FlowPortfolioCandidate] {
    guard let round, let document else { return [] }
    let ids = round.displayedCandidateIDs.isEmpty ? round.candidateIDs : round.displayedCandidateIDs
    return ids.compactMap { id in document.candidates.first { $0.id == id } }
  }
  package var autosaveStatus: String {
    if let error { return (needsRecovery ? "Not saved: " : "Action unavailable: ") + error }
    if isBusy { return progress }
    if pendingMetadataCount > 0 { return "Saving name and source edits…" }
    return "All changes saved · revision \(document?.revision ?? 0)"
  }

  package func open() async {
    guard store == nil, !isBusy, !closed else { return }
    await perform("Opening portfolio…", autosave: false) {
      let location = self.directory, purpose = self.purpose
      self.store = FlowPortfolioStore(directory: location, purpose: purpose, library: self.library)
      try await self.store?.loadRecords()
      try await self.store?.markInterruptedRounds()
      try await self.refresh()
      try await self.restoreRanking()
    }
  }

  package func addPhoto(data: Data, title: String, mediaType: String = "image/png") async {
    guard let store else { return }
    await perform("Retaining photo…") {
      _ = try await store.addSource(data: data, title: title, mediaType: mediaType)
      try await self.refresh(); self.stage = .explore
    }
  }
  package func addCapturedPhoto(_ photo: PortraitPhoto, title: String) async {
    guard let store else { return }
    await perform("Retaining captured photo…") {
      _ = try await store.addCapturedSource(photo: photo, title: title)
      try await self.refresh(); self.stage = .explore
    }
  }

  package func importPhotoCollection(_ directory: URL) async {
    guard let store else { return }
    await perform("Importing photo set…") {
      let collection: FlowPhotoCollection
      do {
        collection = try await Task.detached {
          let scoped = directory.startAccessingSecurityScopedResource()
          defer { if scoped { directory.stopAccessingSecurityScopedResource() } }
          return try FlowPhotoCollection.load(directory: directory)
        }.value
      } catch is CancellationError { throw CancellationError() }
      catch { throw FlowPortfolioError.invalid("The photo set could not be admitted: " + error.localizedDescription) }
      _ = try await store.importPhotoCollection(collection)
      try await self.refresh()
    }
  }

  package func selectSource(_ id: UUID) async {
    guard let store else { return }
    await perform("Opening photo…", autosave: false) { try await store.selectSource(id); try await self.refresh(); self.stage = .explore }
  }
  package func selectRound(_ id: UUID) async {
    guard let store else { return }
    await perform("Opening round…", autosave: false) {
      try await store.selectRound(id); try await self.refresh(); self.stage = .explore
    }
  }
  package func selectCandidate(_ id: UUID, prune: Bool = false) async {
    guard let store else { return }
    await perform("Retaining choice…") {
      try await store.chooseCandidate(id); try await self.refresh()
      self.stage = prune ? .prune : .explore
    }
  }

  /// Navigation supplies no judgment. Only Choose direction records a weak preference.
  package func browseCandidate(_ id: UUID, prune: Bool = false) async {
    guard let store else { return }
    await perform("Opening drawing…", autosave: false) {
      try await store.selectCandidate(id); try await self.refresh()
      self.stage = prune ? .prune : .explore
    }
  }

  package func renameSource(_ id: UUID, title: String) async {
    guard let store, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
    await perform("Saving photo name…") { try await store.renameSource(sourceID: id, title: title); try await self.refresh() }
  }

  package func renameCandidate(_ id: UUID, title: String) async {
    guard let store, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
    await perform("Saving drawing name…") { try await store.renameCandidate(candidateID: id, title: title); try await self.refresh() }
  }

  /// Valid name edits are admitted immediately, coalesced while typing, and
  /// drained on dismissal, portfolio switching and application shutdown.
  package func queueName(_ id: UUID, photo: Bool, title: String) {
    guard acceptsChanges, let store else { return }
    let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !name.isEmpty, name.utf8.count <= 1024 else { return }
    pendingNames.removeAll { $0.id == id && $0.photo == photo }
    pendingNames.append((id, photo, name, store))
    pendingMetadataCount = pendingNames.count + pendingCurations.count
    nameDebounce?.cancel()
    nameDebounce = Task {
      do { try await Task.sleep(for: .milliseconds(300)) } catch { return }
      await flushMetadataEdits()
    }
  }
  package func queueSourceCuration(_ id: UUID, subject: String, session: String, excluded: Bool) {
    guard acceptsChanges, let store, subject.utf8.count <= 256, session.utf8.count <= 256 else { return }
    pendingCurations.removeAll { $0.id == id }
    pendingCurations.append((id, subject, session, excluded, store))
    pendingMetadataCount = pendingNames.count + pendingCurations.count
    nameDebounce?.cancel()
    nameDebounce = Task {
      do { try await Task.sleep(for: .milliseconds(300)) } catch { return }
      await flushMetadataEdits()
    }
  }
  package func flushMetadataEdits() async {
    while true {
      nameDebounce?.cancel(); nameDebounce = nil
      if let running = nameFlush {
        await running.value
        await afterMetadataJoin()
        // Joining is not proof that a later admitted edit was included.
        continue
      }
      guard !pendingNames.isEmpty || !pendingCurations.isEmpty else { return }
      let id = UUID()
      let task = Task { @MainActor in
        defer {
          // Clear before completion, and only our handle. A late joiner must
          // never clear a newer worker or mistake this completed one for it.
          if self.nameFlushID == id { self.nameFlush = nil; self.nameFlushID = nil }
        }
        while !self.pendingNames.isEmpty || !self.pendingCurations.isEmpty {
          if !self.pendingNames.isEmpty {
            let edit = self.pendingNames.removeFirst()
            self.pendingMetadataCount = self.pendingNames.count + self.pendingCurations.count
            await self.perform("Saving name…", alreadyAdmitted: true) {
              if edit.photo { try await edit.store.renameSource(sourceID: edit.id, title: edit.title) }
              else { try await edit.store.renameCandidate(candidateID: edit.id, title: edit.title) }
              try await self.refresh()
            }
          } else {
            let edit = self.pendingCurations.removeFirst()
            self.pendingMetadataCount = self.pendingNames.count + self.pendingCurations.count
            await self.perform("Saving source curation…", alreadyAdmitted: true) {
              try await edit.store.setSourceGroups(sourceID: edit.id,
                subjectID: edit.subject.isEmpty ? nil : edit.subject,
                sessionID: edit.session.isEmpty ? nil : edit.session, excluded: edit.excluded)
              try await self.refresh()
            }
          }
        }
      }
      nameFlushID = id; nameFlush = task
      await task.value
      await afterMetadataJoin()
    }
  }
  private func afterMetadataJoin() async {
    let hook = metadataJoinHook; metadataJoinHook = nil
    await hook?()
  }

  package func updateStrokeStyle(_ style: StrokeStyle, nominalPenWidthMM: Double? = nil) {
    guard !closed, !closing else { return }
    strokeStyle = style
    self.nominalPenWidthMM = FlowDojoAuthoringContext(strokeStyle: style, nominalPenWidthMM: nominalPenWidthMM).nominalPenWidthMM
  }

  package func generate(refining: Bool) async {
    guard let store, let source = selectedSource else { return }
    let parent = refining ? candidate : nil
    let pen = strokeStyle, nominalWidth = nominalPenWidthMM, panelCount = min(9, max(3, count))
    if refining && parent == nil { return }
    await perform(refining ? "Preparing refinement…" : "Preparing broad exploration…") {
      self.cancelRequested = self.closing
      let data = try await store.sourceData(source.id)
      let seed = UInt64.random(in: 1...UInt64.max)
      let checkpoint = self.activeCheckpoint
      do { try checkpoint?.validateForInference() }
      catch { throw FlowPortfolioError.invalid(error.localizedDescription) }
      let recipes: [FlowArtistRecipe]
      if self.renderOverride != nil {
        recipes = parent?.recipe.refined(count: panelCount, seed: seed, radius: 0.12)
          ?? FlowArtistRecipe.broad(count: panelCount, seed: seed)
      } else {
        recipes = try await self.renderer.proposals(data: data, count: panelCount, seed: seed,
          parent: parent?.recipe, checkpoint: checkpoint)
      }
      let round = try await store.beginRound(sourceID: source.id, recipes: recipes,
        parentCandidateID: parent?.id, modelID: checkpoint?.id, seed: seed, analysisOptions: FlowDojoRenderer.analysisOptions)
      self.stage = .explore; try await self.refresh()
      var scores: [(UUID, Double)] = []
      var cancelled = false
      let inheritedRevision = parent.flatMap { self.document?.latestPrune(candidateID: $0.id) }
      for (slot, recipe) in recipes.enumerated() {
        if Task.isCancelled || self.cancelRequested { cancelled = true; break }
        self.progress = "Drawing \(slot + 1) of \(recipes.count)…"
        let production: DrawingProduction<PortraitRenderResult>
        let result: PortraitRenderResult
        let admittedProgram: DrawingProgram
        let preview: Data
        let removed: Set<Int>
        let probabilities: [Double]?
        let score: Double
        do {
          let renderer = self.renderer, override = self.renderOverride
          let parentLink: SourceLink<DrawingRef>
          if let parent { parentLink = .present(try await store.retainedDrawing(candidateID: parent.id).reference!) }
          else { parentLink = .none }
          let photo = try await store.sourcePhoto(source.id)
          let input = PortraitFlowDrawingProducer.Input(data: data, parent: parentLink, photo: photo)
          let settings = PortraitFlowDrawingProducer.Settings(recipe: recipe,
            analysisOptions: FlowDojoRenderer.analysisOptions, strokeStyle: pen, nominalPenWidthMM: nominalWidth)
          if slot == 0, let parent {
            let reused = PortraitRenderResult(raster: try await store.candidateRaster(parent.id),
              program: try await store.candidateProgram(parent.id))
            production = try PortraitFlowDrawingProducer.admit(result: reused, input: input,
              settings: settings, origin: .reusedArtifacts)
            result = production.artifacts
            admittedProgram = production.drawing.program
            preview = try await store.candidatePreview(parent.id)
            removed = Set(inheritedRevision?.removedIndices ?? [])
            probabilities = nil
          } else {
            let worker = Task.detached(priority: .userInitiated) {
              if let override {
                return try PortraitFlowDrawingProducer.admit(result: await override(data, recipe, pen),
                  input: input, settings: settings, origin: .providedArtifacts)
              }
              return try await renderer.produce(data: data, recipe: recipe, strokeStyle: pen,
                nominalPenWidthMM: nominalWidth, parent: parentLink, photo: photo)
            }
            self.rendering = worker
            production = try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
            self.rendering = nil
            result = production.artifacts
            admittedProgram = production.drawing.program
            try Task.checkCancellation()
            preview = try await Task.detached { try FlowDojoRenderer.preview(admittedProgram) }.value
            if let checkpoint {
              let inference = try await Task.detached {
                let features = FlowArtistFeatures.strokes(recipe: recipe, program: admittedProgram, raster: result.raster)
                return (try checkpoint.deletionProbabilities(strokeFeatures: features),
                  try checkpoint.removedIndices(strokeFeatures: features))
              }.value
              probabilities = inference.0; removed = inference.1
            } else { probabilities = nil; removed = [] }
          }
          let mask = removed
          score = try await Task.detached {
            try checkpoint?.score(features: FlowArtistFeatures.drawing(recipe: recipe,
              program: admittedProgram, raster: result.raster, removedIndices: mask)) ?? 0
          }.value
        } catch is CancellationError {
          self.rendering = nil; cancelled = true
          try await store.failCandidate(roundID: round.id, slot: slot, message: "Cancelled")
          break
        } catch {
          self.rendering = nil
          try await store.failCandidate(roundID: round.id, slot: slot, message: error.localizedDescription)
          continue
        }
        // Storage failures are not renderer failures. Stop without overwriting a
        // completed slot; recovery marks any unfinished round interrupted.
        let saved = try await store.completeCandidate(roundID: round.id, slot: slot,
          production: production, previewPNG: preview)
        if slot == 0, parent != nil, let inheritedRevision {
          _ = try await store.applyPrune(candidateID: saved.id, action: .inheritedSelection,
            indices: removed.sorted(), inheritedFromRevisionID: inheritedRevision.id)
        } else if let checkpoint, let probabilities {
          _ = try await store.applyPrune(candidateID: saved.id, action: .modelProposal,
            indices: removed.sorted(), modelID: checkpoint.id, probabilities: probabilities,
            threshold: 0.65, policy: "threshold-keep-one-v1")
        }
        scores.append((saved.id, score))
        try await self.refresh()
      }
      let ordered = checkpoint?.ranker == nil ? scores.map(\.0) : scores.sorted { $0.1 > $1.1 }.map(\.0)
      try await store.finishRound(round.id, cancelled: cancelled, displayOrder: ordered,
        recommendedCandidateID: checkpoint?.ranker == nil ? nil : ordered.first)
      try await self.refresh()
      self.progress = cancelled ? "Generation cancelled; completed previews remain in this session." : "Choose a drawing to retain and refine or prune."
    }
  }

  package func edit(_ action: FlowPruneAction, ids: Set<StrokeID> = []) async {
    guard let store, let candidate, let program else { return }
    let indices = program.strokes.enumerated().filter { ids.contains($0.element.id) }.map(\.offset)
    await perform("Saving line selection…") {
      _ = try await store.applyPrune(candidateID: candidate.id, action: action, indices: indices)
      self.selection = []; try await self.refresh()
    }
  }

  package func presentRanking(scope: FlowRankingScope, count: Int? = nil) async {
    guard let store else { return }
    await perform("Preparing comparison…", autosave: false) {
      self.presentation = try await store.presentRanking(scope: scope, count: count ?? self.count, seed: UInt64.random(in: 1...UInt64.max))
      self.ranks = [:]; self.rankingPreviews = [:]; self.stage = .rank
      try await self.loadRankingPreviews(); try await self.refresh()
    }
  }
  package func rankCurrentSet() async {
    guard let store, let round else { return }
    await perform("Preparing full-set ranking…", autosave: false) {
      self.presentation = try await store.presentRoundRanking(round.id, seed: UInt64.random(in: 1...UInt64.max))
      self.ranks = [:]; self.rankingPreviews = [:]; self.stage = .rank
      try await self.loadRankingPreviews(); try await self.refresh()
    }
  }
  package func selectPresentation(_ id: UUID) async {
    guard let store else { return }
    await perform("Opening comparison…", autosave: false) {
      try await store.selectPresentation(id)
      try await self.refresh(); try await self.restoreRanking()
      self.stage = .rank
    }
  }
  package func rank(item: UUID, position: Int) async {
    guard let store, let presentation else { return }
    await perform("Saving artistic ranking…") {
      var next = self.ranks
      if position <= 0 { next.removeValue(forKey: item) } else { next[item] = position }
      let tiers = Set(next.values).sorted().map { rank in presentation.items.filter { next[$0.id] == rank }.map(\.id) }
      _ = try await store.recordRanking(presentationID: presentation.id, orderedGroups: tiers)
      self.ranks = next; try await self.refresh()
    }
  }
  package func compare(preferred itemID: UUID?) async {
    guard let store, let presentation, presentation.items.count == 2 else { return }
    let ids = presentation.items.map(\.id)
    guard itemID == nil || ids.contains(itemID!) else { return }
    await perform("Saving artistic comparison…") {
      let tiers = itemID.map { chosen in [[chosen], ids.filter { $0 != chosen }] } ?? [ids]
      _ = try await store.recordRanking(presentationID: presentation.id, orderedGroups: tiers)
      self.ranks = [:]
      for (index, tier) in tiers.enumerated() { for id in tier { self.ranks[id] = index + 1 } }
      try await self.refresh()
      try await self.advanceComparison(after: presentation)
    }
  }

  package func declineRanking(neither: Bool) async {
    guard let store, let presentation else { return }
    await perform("Saving comparison outcome…") {
      _ = try await store.recordRanking(presentationID: presentation.id, orderedGroups: [], skipped: !neither, neither: neither)
      self.ranks = [:]; try await self.refresh()
      try await self.advanceComparison(after: presentation)
    }
  }
  private func advanceComparison(after previous: FlowPortfolioPresentation) async throws {
    guard let store, previous.items.count == 2 else { return }
    do {
      let next = try await store.presentRanking(scope: previous.scope, count: 2, seed: UInt64.random(in: 1...UInt64.max))
      presentation = next; ranks = [:]; rankingPreviews = [:]
      try await loadRankingPreviews(); try await refresh()
    } catch FlowPortfolioError.unavailable { progress = "Comparison saved. Every available pair has a current ranking." }
  }
  package func curateSource(sourceID: UUID? = nil, subject: String, session: String, excluded: Bool) async {
    guard let store, let id = sourceID ?? selectedSource?.id else { return }
    await perform("Saving source curation…") {
      try await store.setSourceGroups(sourceID: id, subjectID: subject.isEmpty ? nil : subject,
        sessionID: session.isEmpty ? nil : session, excluded: excluded)
      try await self.refresh()
    }
  }
  package func excludeCandidate(_ candidate: FlowPortfolioCandidate, excluded: Bool) async {
    guard let store else { return }
    await perform("Saving curation…") { try await store.setExcluded(candidateID: candidate.id, excluded: excluded); try await self.refresh() }
  }

  package func fit() async {
    guard let store else { return }
    await flushMetadataEdits()
    let requestID = UUID()
    var retainedReport: FlowArtistFitReport?
    await perform("Freezing training dataset…", replayAfterPartialCommit: true) {
      let frozen = try await store.freezeTrainingSnapshot(id: requestID)
      if retainedReport == nil {
        let snapshot = try await store.trainingDocument(snapshotID: frozen.id)
        self.progress = "Fitting parameter preference and line deletion…"
        let fitter = self.fitOverride
        let worker = Task.detached(priority: .userInitiated) {
          let dataset = try await FlowDojoTraining.dataset(store: store, document: snapshot)
          if let fitter { return try await fitter(dataset.examples, dataset.rankings) }
          return FlowArtistTraining.fit(examples: dataset.examples, rankings: dataset.rankings)
        }
        self.fitting = worker
        if self.closing { worker.cancel() }
        do {
          retainedReport = try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
        } catch is CancellationError {
          retainedReport = .unavailable("Training cancelled; the frozen dataset remains available.")
        } catch {
          retainedReport = .unavailable("Training failed: " + error.localizedDescription)
        }
        self.fitting = nil
      }
      guard let report = retainedReport else { return }
      self.reportSummary = report.summary; self.fitReport = report
      let encoder = DrawingArtifactCoding.encoder()
      _ = try await store.installFit(checkpoint: try report.checkpoint.map { try encoder.encode($0) },
        report: encoder.encode(report), snapshotID: frozen.id)
      try await self.refresh()
    }
  }
  package func activate(_ fitID: UUID?) async {
    guard let store else { return }
    await perform("Activating artist checkpoint…", autosave: false) {
      if let fitID {
        let bytes = try await store.checkpointData(fitID: fitID)
        let checkpoint = try JSONDecoder().decode(FlowArtistCheckpoint.self, from: bytes)
        try checkpoint.validateForInference()
      }
      try await store.activateModel(fitID); try await self.refresh()
    }
  }
  package func showReport(_ fitID: UUID) async {
    guard let store else { return }
    await perform("Loading fit report…", autosave: false) {
      let report = try JSONDecoder().decode(FlowArtistFitReport.self, from: await store.fitReportData(fitID: fitID))
      self.reportSummary = report.summary; self.fitReport = report
    }
  }
  package func retainedDrawing() async throws -> Drawing {
    guard let store, let candidate else { throw FlowPortfolioError.unavailable("Choose a drawing first.") }
    let drawing = try await store.retainedDrawing(candidateID: candidate.id, revisionID: prune?.id)
    try await refresh()
    return drawing
  }
  package func exportDrawing(to url: URL) async throws {
    guard let store else { throw FlowPortfolioError.unavailable("Library is unavailable.") }
    let drawing = try await retainedDrawing()
    try await store.exportDrawing(drawing, to: url)
  }

  package func cancel() { cancelRequested = true; rendering?.cancel(); fitting?.cancel() }
  package var acceptsChanges: Bool { !closed && !closing }
  package func closeMutationAdmission() { closing = true }

  package func prepareForShutdown() async -> Bool {
    if closed { return true }
    closing = true
    cancel()
    await flushMetadataEdits()
    await recoveryWork?.value; await work?.value
    if needsRecovery { closing = false; return false }
    return true
  }
  @discardableResult package func shutdown() async -> Bool {
    guard await prepareForShutdown() else { return false }
    if library == nil { await store?.closeLibrary() }
    closed = true; store = nil
    return true
  }
  package func clearError() { error = nil }

  private func perform(_ status: String, replayAfterPartialCommit: Bool = false, autosave: Bool = true, alreadyAdmitted: Bool = false, replayingRecovery: Bool = false, operation: @escaping @MainActor () async throws -> Void) async {
    guard !closed, !closing || alreadyAdmitted else { return }
    if recoveryWork != nil && !replayingRecovery {
      blockedIntents.append((status, replayAfterPartialCommit, autosave, operation))
      return
    }
    // Freeze input at admission and chain durable mutations in exact arrival order.
    // Cancellation stops expensive work, never drops an admitted autosave.
    let predecessor = work, id = UUID()
    isBusy = true; lastWorkID = id
    let task = Task { @MainActor in
      await predecessor?.value
      if self.needsRecovery {
        self.blockedIntents.append((status, replayAfterPartialCommit, autosave, operation)); return
      }
      self.progress = status; self.error = nil
      let baseline = self.document?.revision ?? -1
      do { try await operation() }
      catch is CancellationError { self.progress = "Cancelled; committed work is retained." }
      catch {
        self.error = error.localizedDescription
        var rejected = false
        if case FlowPortfolioError.invalid = error { rejected = true }
        // Raw command/image validation is classified by the domain before
        // mutation. Core admission failures can instead originate in storage.
        if autosave && !rejected {
          self.failedIntent = (status, baseline, replayAfterPartialCommit, operation); self.needsRecovery = true
        }
      }
    }
    work = task; await task.value
    if lastWorkID == id { work = nil; isBusy = recoveryWork != nil }
  }
  /// Reconcile the durable head before retrying. A commit which reached disk is
  /// never replayed as a second vote or edit. Later admitted inputs stay queued.
  package func recoverAutosave() async {
    guard !isBusy, !closed, !closing, let failure = failedIntent else { return }
    isBusy = true
    let task = Task { @MainActor in
      do {
        try await self.store?.reloadCommittedState()
        let durableRevision = await self.store?.snapshot().revision ?? -1
        if durableRevision == failure.baseline || failure.replayPartial { try await failure.operation() }
        else {
          try await self.store?.markInterruptedRounds()
          try await self.refresh()
          try await self.restoreRanking()
          self.progress = "Recovered committed work; an incomplete generation is retained as interrupted."
        }
        self.failedIntent = nil; self.needsRecovery = false; self.error = nil
        while !self.needsRecovery && !self.blockedIntents.isEmpty {
          let pending = self.blockedIntents; self.blockedIntents = []
          for (status, replay, autosave, operation) in pending {
            await self.perform(status, replayAfterPartialCommit: replay, autosave: autosave,
              alreadyAdmitted: true, replayingRecovery: true, operation: operation)
          }
        }
      } catch { self.error = error.localizedDescription }
    }
    recoveryWork = task
    await task.value
    recoveryWork = nil
    if work == nil { isBusy = false }
  }
  private func refresh() async throws {
    guard let store else { return }
    try await store.refreshPhotoMetadata()
    document = await store.snapshot()
    if let document {
      let last = document.fits.last(where: { $0.hasCheckpoint })
      if fittedSnapshotID != last?.snapshotID {
        if let last { fittedDocument = try await store.trainingDocument(snapshotID: last.snapshotID) }
        else { fittedDocument = nil }
        fittedSnapshotID = last?.snapshotID
      }
      let active = document.fits.first(where: { $0.id == document.activeFitID })
      if activeSnapshotID != active?.snapshotID {
        if let active { activeTrainingDocument = try await store.trainingDocument(snapshotID: active.snapshotID) }
        else { activeTrainingDocument = nil }
        activeSnapshotID = active?.snapshotID
      }
      trainingProgress = FlowDojoTrainingProgress(document: document, fittedDocument: fittedDocument, activeDocument: activeTrainingDocument)
    }
    if let source = selectedSource {
      if loadedSourceHash != source.image.sha256 {
        sourceData = try await store.sourceData(source.id); loadedSourceHash = source.image.sha256
      }
    } else { sourceData = nil; loadedSourceHash = nil }
    if let candidate {
      if loadedProgramID != candidate.id { program = try? await store.candidateProgram(candidate.id); loadedProgramID = candidate.id }
    } else { program = nil; loadedProgramID = nil }
    if let fitID = document?.activeFitID {
      activeCheckpoint = try JSONDecoder().decode(FlowArtistCheckpoint.self, from: await store.checkpointData(fitID: fitID))
      try activeCheckpoint?.validateArchive()
      do { try activeCheckpoint?.validateForInference(); activeModelIssue = nil }
      catch { activeModelIssue = error.localizedDescription }
    } else { activeCheckpoint = nil; activeModelIssue = nil }
    let visibleIDs = Set(roundCandidates.map(\.id))
    previews = previews.filter { visibleIDs.contains($0.key) }
    previewKeys = previewKeys.filter { visibleIDs.contains($0.key) }
    for candidate in roundCandidates {
      let revision = document?.latestPrune(candidateID: candidate.id)
      let key = revision?.id.uuidString ?? "original"
      guard previewKeys[candidate.id] != key else { continue }
      let item = FlowPortfolioPresentationItem(id: revision?.id ?? candidate.id, candidateID: candidate.id,
        revisionID: revision?.id, sourceID: candidate.sourceID, removedIndices: revision?.removedIndices ?? [])
      previews[candidate.id] = try? await store.presentationPreview(item)
      previewKeys[candidate.id] = key
    }
  }
  private func restoreRanking() async throws {
    guard let document, let latest = document.presentations.first(where: { $0.id == document.currentPresentationID }) ?? document.presentations.last else { return }
    presentation = latest
    ranks = [:]
    if let rank = document.latestRankings.last(where: { $0.presentationID == latest.id }) {
      for (index, tier) in rank.orderedGroups.enumerated() { for id in tier { ranks[id] = index + 1 } }
    }
    try await loadRankingPreviews()
  }
  private func loadRankingPreviews() async throws {
    guard let store, let presentation else { return }
    for item in presentation.items { rankingPreviews[item.id] = try? await store.presentationPreview(item) }
  }
}
