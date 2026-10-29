import AppKit
import Foundation
import Observation
import PlotterModel
import PortraitArtists
import PortraitCore
import PortraitLibrary

@Observable @MainActor
package final class FlowDojoModel {
  package enum Stage: String, CaseIterable { case explore = "Explore", prune = "Prune", rank = "Rank", fit = "Fit & deploy" }
  package nonisolated static var defaultDirectory: URL {
    FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Documents/Flow Edge Portfolio.flowportfolio", isDirectory: true)
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
  package private(set) var activeCheckpoint: FlowArtistCheckpoint?
  @ObservationIgnored package private(set) var store: FlowPortfolioStore?
  @ObservationIgnored private let renderer = FlowDojoRenderer()
  @ObservationIgnored private var work: Task<Void, Never>?
  @ObservationIgnored private var recoveryWork: Task<Void, Never>?
  @ObservationIgnored private var rendering: Task<PortraitRenderResult, Error>?
  @ObservationIgnored private var fitting: Task<FlowArtistFitReport, Error>?
  @ObservationIgnored private var lastWorkID: UUID?
  @ObservationIgnored private var cancelRequested = false
  @ObservationIgnored private var closed = false
  @ObservationIgnored private var closing = false
  @ObservationIgnored private var failedIntent: (status: String, baseline: Int, replayPartial: Bool, operation: @MainActor () async throws -> Void)?
  @ObservationIgnored private var blockedIntents: [(String, Bool, Bool, @MainActor () async throws -> Void)] = []
  @ObservationIgnored private var loadedSourceHash: String?
  @ObservationIgnored private var loadedProgramID: UUID?
  @ObservationIgnored private var previewKeys: [UUID: String] = [:]
  @ObservationIgnored private let purpose: FlowPortfolioPurpose?
  @ObservationIgnored private let renderOverride: (@Sendable (Data, FlowArtistRecipe, StrokeStyle) async throws -> PortraitRenderResult)?
  @ObservationIgnored private let fitOverride: (@Sendable ([FlowArtistExample], [FlowArtistRanking]) async throws -> FlowArtistFitReport)?
  package private(set) var strokeStyle: StrokeStyle

  package init(directory: URL = FlowDojoModel.defaultDirectory,
    strokeStyle: StrokeStyle? = nil, purpose: FlowPortfolioPurpose? = nil,
    render: (@Sendable (Data, FlowArtistRecipe, StrokeStyle) async throws -> PortraitRenderResult)? = nil,
    fit: (@Sendable ([FlowArtistExample], [FlowArtistRanking]) async throws -> FlowArtistFitReport)? = nil) {
    self.directory = directory; self.purpose = purpose
    self.strokeStyle = strokeStyle ?? (try! StrokeStyle(nominalLineWidth: 0.4,
      penProfileID: PenProfileID(UUID(uuidString: "00000000-0000-0000-0000-000000000001")!)))
    renderOverride = render; fitOverride = fit
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
    if let error { return "Not saved: " + error }
    if isBusy { return progress }
    return "All changes saved · revision \(document?.revision ?? 0)"
  }

  package func open() async {
    guard store == nil, !isBusy, !closed else { return }
    await perform("Opening portfolio…", autosave: false) {
      let location = self.directory, purpose = self.purpose
      self.store = try await Task.detached { try FlowPortfolioStore(directory: location, purpose: purpose) }.value
      try await self.store?.markInterruptedRounds()
      try await self.refresh()
      try await self.restoreRanking()
    }
  }

  package func switchPortfolio(to url: URL) async {
    guard !isBusy, url.standardizedFileURL != directory.standardizedFileURL else { return }
    await perform("Opening portfolio…", autosave: false) {
      let next = try await Task.detached { try FlowPortfolioStore(directory: url) }.value
      self.store = next; self.directory = url; self.document = nil
      self.previews = [:]; self.previewKeys = [:]; self.loadedSourceHash = nil; self.loadedProgramID = nil
      self.rankingPreviews = [:]; self.presentation = nil; self.ranks = [:]
      self.reportSummary = nil; self.fitReport = nil; self.activeCheckpoint = nil; self.selection = []
      self.stage = .explore
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

  package func updateStrokeStyle(_ style: StrokeStyle) {
    guard !closed, !closing else { return }
    strokeStyle = style
  }

  package func generate(refining: Bool) async {
    guard let store, let source = selectedSource else { return }
    let parent = refining ? candidate : nil
    let pen = strokeStyle, panelCount = min(9, max(3, count))
    if refining && parent == nil { return }
    await perform(refining ? "Preparing refinement…" : "Preparing broad exploration…") {
      self.cancelRequested = self.closing
      let data = try await store.sourceData(source.id)
      let seed = UInt64.random(in: 1...UInt64.max)
      let recipes = parent?.recipe.refined(count: panelCount, seed: seed, radius: 0.12)
        ?? FlowArtistRecipe.broad(count: panelCount, seed: seed)
      let checkpoint = self.activeCheckpoint
      let round = try await store.beginRound(sourceID: source.id, recipes: recipes,
        parentCandidateID: parent?.id, modelID: checkpoint?.id, seed: seed, analysisOptions: FlowDojoRenderer.analysisOptions)
      self.stage = .explore; try await self.refresh()
      var scores: [(UUID, Double)] = []
      var seenPreviews = Set<String>()
      var cancelled = false
      let inheritedRevision = parent.flatMap { self.document?.latestPrune(candidateID: $0.id) }
      for (slot, recipe) in recipes.enumerated() {
        if Task.isCancelled || self.cancelRequested { cancelled = true; break }
        self.progress = "Drawing \(slot + 1) of \(recipes.count)…"
        let result: PortraitRenderResult
        let preview: Data
        let removed: Set<Int>
        let probabilities: [Double]?
        let score: Double
        do {
          let renderer = self.renderer, override = self.renderOverride
          if slot == 0, let parent {
            result = PortraitRenderResult(raster: try await store.candidateRaster(parent.id),
              program: try await store.candidateProgram(parent.id))
            preview = try await store.candidatePreview(parent.id)
            removed = Set(inheritedRevision?.removedIndices ?? [])
            probabilities = nil
          } else {
            let worker = Task.detached(priority: .userInitiated) {
              if let override { return try await override(data, recipe, pen) }
              return try await renderer.render(data: data, recipe: recipe, strokeStyle: pen)
            }
            self.rendering = worker
            result = try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
            self.rendering = nil
            try Task.checkCancellation()
            preview = try await Task.detached { try FlowDojoRenderer.preview(result.program) }.value
            if let checkpoint {
              let inference = try await Task.detached {
                let features = FlowArtistFeatures.strokes(recipe: recipe, program: result.program, raster: result.raster)
                return (try checkpoint.deletionProbabilities(strokeFeatures: features),
                  try checkpoint.removedIndices(strokeFeatures: features))
              }.value
              probabilities = inference.0; removed = inference.1
            } else { probabilities = nil; removed = [] }
          }
          let mask = removed
          score = try await Task.detached {
            try checkpoint?.score(features: FlowArtistFeatures.drawing(recipe: recipe,
              program: result.program, raster: result.raster, removedIndices: mask)) ?? 0
          }.value
          let fingerprint = DrawingPackageCodec.sha256(preview)
          guard seenPreviews.insert(fingerprint).inserted else {
            throw FlowPortfolioError.unavailable("This recipe reproduced an existing drawing in the round; duplicate omitted.")
          }
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
          program: result.program, raster: result.raster, previewPNG: preview)
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
      self.progress = cancelled ? "Generation cancelled; completed drawings retained." : "Round saved. Choose a drawing to refine or prune."
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

  package func presentRanking(scope: FlowRankingScope) async {
    guard let store else { return }
    await perform("Preparing comparison…", autosave: false) {
      self.presentation = try await store.presentRanking(scope: scope, count: self.count, seed: UInt64.random(in: 1...UInt64.max))
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
  package func declineRanking(neither: Bool) async {
    guard let store, let presentation else { return }
    await perform("Saving comparison outcome…") {
      _ = try await store.recordRanking(presentationID: presentation.id, orderedGroups: [], skipped: !neither, neither: neither)
      self.ranks = [:]; try await self.refresh()
    }
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
      let encoder = DrawingPackageCodec.encoder()
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
        try checkpoint.validate()
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
  package func exportPackage() async throws -> Data {
    guard let store, let candidate else { throw FlowPortfolioError.unavailable("Choose a drawing first.") }
    return try await store.exportPackage(candidateID: candidate.id, revisionID: prune?.id)
  }

  package func cancel() { cancelRequested = true; rendering?.cancel(); fitting?.cancel() }
  package var acceptsChanges: Bool { !closed && !closing }
  package func closeMutationAdmission() { closing = true }

  package func prepareForShutdown() async -> Bool {
    if closed { return true }
    closing = true
    cancel(); await recoveryWork?.value; await work?.value
    if needsRecovery { closing = false; return false }
    return true
  }
  @discardableResult package func shutdown() async -> Bool {
    guard await prepareForShutdown() else { return false }
    closed = true; store = nil
    return true
  }
  package func clearError() { error = nil }

  private func perform(_ status: String, replayAfterPartialCommit: Bool = false, autosave: Bool = true, alreadyAdmitted: Bool = false, operation: @escaping @MainActor () async throws -> Void) async {
    guard !closed, !closing || alreadyAdmitted else { return }
    if recoveryWork != nil && !alreadyAdmitted {
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
        if case DrawingTransferError.invalid = error { rejected = true }
        if case DrawingTransferError.limit = error { rejected = true }
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
              alreadyAdmitted: true, operation: operation)
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
    document = await store.snapshot()
    if let source = selectedSource {
      if loadedSourceHash != source.image.sha256 {
        sourceData = try await store.sourceData(source.id); loadedSourceHash = source.image.sha256
      }
    } else { sourceData = nil; loadedSourceHash = nil }
    if let candidate {
      if loadedProgramID != candidate.id { program = try await store.candidateProgram(candidate.id); loadedProgramID = candidate.id }
    } else { program = nil; loadedProgramID = nil }
    if let fitID = document?.activeFitID {
      activeCheckpoint = try JSONDecoder().decode(FlowArtistCheckpoint.self, from: await store.checkpointData(fitID: fitID))
      try activeCheckpoint?.validate()
    } else { activeCheckpoint = nil }
    let visibleIDs = Set(roundCandidates.map(\.id))
    previews = previews.filter { visibleIDs.contains($0.key) }
    previewKeys = previewKeys.filter { visibleIDs.contains($0.key) }
    for candidate in roundCandidates {
      let revision = document?.latestPrune(candidateID: candidate.id)
      let key = revision?.id.uuidString ?? "original"
      guard previewKeys[candidate.id] != key else { continue }
      if let revision {
        let program = try await store.candidateProgram(candidate.id), mask = Set(revision.removedIndices)
        previews[candidate.id] = try await Task.detached { try FlowDojoRenderer.preview(program, removed: mask) }.value
      } else { previews[candidate.id] = try await store.candidatePreview(candidate.id) }
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
    for item in presentation.items {
      let program = try await store.candidateProgram(item.candidateID), removed = Set(item.removedIndices)
      rankingPreviews[item.id] = try await Task.detached { try FlowDojoRenderer.preview(program, removed: removed) }.value
    }
  }
}
