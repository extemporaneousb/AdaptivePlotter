import AppKit
import Foundation
import Observation
import PlotterModel
import PortraitArtists
import PortraitCore
import PortraitLibrary
import DrawingLibrary

/// A physical authoring declaration, independent of preview geometry units.
package struct FlowAuthoringContext: Equatable, Sendable {
  package let strokeStyle: StrokeStyle
  package let nominalPenWidthMM: Double?
  package init(strokeStyle: StrokeStyle, nominalPenWidthMM: Double?) {
    self.strokeStyle = strokeStyle
    self.nominalPenWidthMM = nominalPenWidthMM
  }
}

@Observable @MainActor
package final class FlowAuthoringModel {
  package enum Stage: String, CaseIterable { case explore = "Explore", prune = "Prune", rank = "Rank", fit = "Fit & deploy" }
  package nonisolated static var defaultDirectory: URL {
    FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/PortraitStudio/DrawingLibrary", isDirectory: true)
  }
  package private(set) var directory: URL
  package private(set) var document: FlowPortfolioSnapshot?
  package private(set) var sourceData: Data?
  package private(set) var program: DrawingProgram?
  package private(set) var candidateLoadError: String?
  package private(set) var candidateUnavailableReasons: [UUID: String] = [:]
  package private(set) var pendingExplorationParentID: UUID?
  package private(set) var pendingBroadAnchorID: UUID?
  package private(set) var pendingBroadAnchorPreview: Data?
  package private(set) var regionPreviewPending = false
  package var verifiedRecommendationIDs: Set<UUID> = []
  package var unavailableRecommendationIDs: Set<UUID> = []
  package private(set) var recommendationError: String?
  package var generationIntentRevision: UInt64 { generationRevision }
  package var isPreparingGeneration: Bool { proposing != nil }
  package var isRenderingGeneration: Bool { rendering != nil }
  package func reportRecommendationFailure(_ id: UUID, reason: String, excludeTemporary: Bool) {
    if excludeTemporary { unavailableRecommendationIDs.insert(id) }
    verifiedRecommendationIDs.remove(id); recommendationError = reason
  }
  package func clearRecommendationFailure() { recommendationError = nil }
  @ObservationIgnored private var generationRevision: UInt64 = 0
  @ObservationIgnored private var generationActive = false
  @ObservationIgnored private var explorationAdmission: String?
  package private(set) var previews: [UUID: Data] = [:]
  package private(set) var rankingPreviews: [UUID: Data] = [:]
  package private(set) var isBusy = false
  package private(set) var progress = "Opening portfolio…"
  package private(set) var error: String?
  package private(set) var needsRecovery = false
  package private(set) var pendingMetadataCount = 0
  package var stage: Stage = .explore { didSet { if stage == .prune { returnToEditing() } } }
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
  package private(set) var trainingProgress: FlowAuthoringTrainingProgress?
  /// Actual expensive refresh work; derived diagnostics, never persisted.
  package private(set) var checkpointDecodeCount = 0
  package private(set) var trainingSummaryBuildCount = 0
  @ObservationIgnored private let library: DrawingLibrary?
  @ObservationIgnored package private(set) var store: FlowPortfolioStore?
  @ObservationIgnored private let renderer = FlowAuthoringRenderer()
  @ObservationIgnored private var work: Task<Void, Never>?
  @ObservationIgnored private var recoveryWork: Task<Void, Never>?
  private struct GeneratedCandidate: Sendable {
    let production: DrawingProduction<PortraitRenderResult>
    let preview: Data
    let removed: Set<Int>
    let probabilities: [Double]?
    let score: Double
  }
  @ObservationIgnored private var rendering: Task<GeneratedCandidate, Error>?
  @ObservationIgnored private var proposing: Task<[FlowArtistRecipe], Error>?
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
  @ObservationIgnored private var fittedDocument: FlowPortfolioSnapshot?
  @ObservationIgnored private var activeTrainingDocument: FlowPortfolioSnapshot?
  @ObservationIgnored private var fittedSnapshot: FlowPortfolioTrainingSnapshot?
  @ObservationIgnored private var activeSnapshot: FlowPortfolioTrainingSnapshot?
  @ObservationIgnored private var trainingProgressKey: FlowAuthoringTrainingProgressKey?
  private struct CheckpointKey: Equatable {
    let portfolio: UUID
    let fit: FlowPortfolioFit
    let snapshot: FlowPortfolioTrainingSnapshot?
  }
  @ObservationIgnored private var checkpointKey: CheckpointKey?
  @ObservationIgnored private var loadedProgramID: UUID?
  @ObservationIgnored private var previewKeys: [UUID: String] = [:]
  @ObservationIgnored private let purpose: FlowPortfolioPurpose?
  @ObservationIgnored private let renderOverride: (@Sendable (Data, FlowArtistRecipe, StrokeStyle) async throws -> PortraitRenderResult)?
  @ObservationIgnored private let fitOverride: (@Sendable ([FlowArtistExample], [FlowArtistRanking]) async throws -> FlowArtistFitReport)?
  package private(set) var strokeStyle: StrokeStyle
  package private(set) var nominalPenWidthMM: Double?

  package init(directory: URL = FlowAuthoringModel.defaultDirectory, library: DrawingLibrary? = nil,
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
    if pendingMetadataCount > 0 { return "Saving names…" }
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
    invalidateGeneration(); regionPreviewPending = false; returnToEditing(); photoSelectionRevision &+= 1
    guard let store else { return }
    await perform("Retaining photo…") {
      _ = try await store.addSource(data: data, title: title, mediaType: mediaType)
      try await self.refresh(); self.stage = .explore
    }
  }
  package func addCapturedPhoto(_ photo: PortraitPhoto, title: String) async {
    invalidateGeneration(); regionPreviewPending = false; returnToEditing(); photoSelectionRevision &+= 1
    guard let store else { return }
    await perform("Retaining captured photo…") {
      _ = try await store.addCapturedSource(photo: photo, title: title)
      try await self.refresh(); self.stage = .explore
    }
  }

  package func importPhotoCollection(_ directory: URL) async {
    invalidateGeneration(); regionPreviewPending = false; returnToEditing(); photoSelectionRevision &+= 1
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

  @ObservationIgnored private var photoSelectionRevision: UInt64 = 0
  package var currentPhotoRef: PhotoRef? { selectedSource?.photo }
  package var drawingLibrary: DrawingLibrary? { library ?? store?.library }
  @discardableResult package func selectPhoto(_ reference: PhotoRef, isStillCurrent: @escaping @MainActor () -> Bool = { true }) async -> String? {
    guard let store, !closed, !closing, !needsRecovery else { return "Recover or reopen Flow Edge before opening this Photo." }
    invalidateGeneration(); regionPreviewPending = false; returnToEditing()
    photoSelectionRevision &+= 1; let revision = photoSelectionRevision
    await perform("Opening photo…", autosave: false) {
      guard revision == self.photoSelectionRevision, !self.closing, !self.closed, isStillCurrent() else { return }
      _ = try await store.adoptExistingPhoto(reference)
      guard revision == self.photoSelectionRevision, !self.closing, !self.closed, isStillCurrent() else { return }
      try await self.refresh(photoRevision: revision, isStillCurrent: isStillCurrent)
      guard revision == self.photoSelectionRevision, isStillCurrent() else { return }
      self.stage = .explore
    }
    guard revision == photoSelectionRevision, isStillCurrent(), !closed, !closing else { return "The Photo selection changed before opening completed." }
    if let error { return error }
    guard currentPhotoRef == reference, sourceData != nil else { return "The exact Photo could not be opened for authoring." }
    return nil
  }
  package func selectSource(_ id: UUID) async {
    invalidateGeneration(); regionPreviewPending = false; returnToEditing()
    photoSelectionRevision &+= 1
    guard let store else { return }
    await perform("Opening photo…", autosave: false) { try await store.selectSource(id); try await self.refresh(); self.stage = .explore }
  }
  package func selectRound(_ id: UUID) async {
    invalidateGeneration(); regionPreviewPending = false; returnToEditing(); photoSelectionRevision &+= 1
    guard let store else { return }
    await perform("Opening round…", autosave: false) {
      try await store.selectRound(id); try await self.refresh(); self.stage = .explore
    }
  }
  package func selectCandidate(_ id: UUID, prune: Bool = false) async {
    if let candidate = document?.candidates.first(where: { $0.id == id }),
      let reason = candidateUnavailableReason(candidate) { error = reason; return }
    invalidateGeneration(); regionPreviewPending = false; returnToEditing(); photoSelectionRevision &+= 1
    guard let store else { return }
    await perform("Retaining choice…") {
      try await store.chooseCandidate(id); try await self.refresh()
      self.stage = prune ? .prune : .explore
    }
  }

  /// Navigation supplies no judgment. Only Choose direction records a weak preference.
  package func browseCandidate(_ id: UUID, prune: Bool = false) async {
    invalidateGeneration(); regionPreviewPending = false; returnToEditing(); photoSelectionRevision &+= 1
    guard let store else { return }
    await perform("Opening drawing…", autosave: false) {
      try await store.selectCandidate(id); try await self.refresh()
      self.stage = prune ? .prune : .explore
    }
  }

  package func candidateUnavailableReason(_ candidate: FlowPortfolioCandidate) -> String? {
    if let reason = candidateUnavailableReasons[candidate.id] { return reason }
    if self.candidate?.id == candidate.id, let candidateLoadError { return candidateLoadError }
    return nil
  }
  package func candidateRefinementUnavailableReason(_ candidate: FlowPortfolioCandidate) -> String? {
    if let reason = candidateUnavailableReason(candidate) { return reason }
    guard candidate.sourceID == selectedSource?.id,
      document?.rounds.first(where: { $0.id == candidate.roundID })?.analysisOptions == committedAnalysisOptions else {
      return "Open this drawing's exact photo and region before refining."
    }
    if (document?.latestPrune(candidateID: candidate.id)?.removedIndices.count ?? 0) >= candidate.strokeCount {
      return "Restore at least one stroke before refining this drawing."
    }
    return nil
  }
  package func canRefineCandidate(_ candidate: FlowPortfolioCandidate) -> Bool {
    canNavigateExploration && candidateRefinementUnavailableReason(candidate) == nil
  }

  package var committedAnalysisOptions: PortraitAnalysisOptions { round?.analysisOptions ?? selectedSource?.authoringOptions ?? FlowAuthoringRenderer.analysisOptions }
  package var editingUnavailableReason: String? {
    if needsRecovery { return "Recover the unsaved local edit before editing." }
    if isBusy { return progress }
    if closed || closing { return "The authoring session is closing." }
    if let candidateLoadError { return candidateLoadError }
    if program == nil || candidate?.id != loadedProgramID { return "Choose an available drawing to edit." }
    if showsOriginal { return "Original is a read-only comparison. Return to editing to change lines." }
    if showsPhoto { return "Photo is a read-only comparison. Return to editing to change lines." }
    return nil
  }
  package var canEdit: Bool { editingUnavailableReason == nil }
  package func returnToEditing() { showsOriginal = false; showsPhoto = false; selection = [] }
  package func beginPruning() { returnToEditing(); stage = .prune }
  package func retryCandidateLoad() async {
    guard !isBusy, !needsRecovery else { return }
    loadedProgramID = nil
    await perform("Retrying drawing load…", autosave: false) { try await self.refresh() }
  }
  package var sendUnavailableReason: String? {
    if !acceptsChanges { return "The authoring session is closing." }
    if needsRecovery { return "Recover unsaved changes before sending." }
    if isBusy || generationActive || regionPreviewPending { return "Wait for the current drawing to finish." }
    guard let candidate, candidate.sourceID == selectedSource?.id, candidate.id == loadedProgramID,
      let sourceRound = document?.rounds.first(where: { $0.id == candidate.roundID }),
      sourceRound.analysisOptions == committedAnalysisOptions,
      let program else { return candidateLoadError ?? "Choose an available drawing for this photo and region." }
    if removedIndices.count >= program.strokes.count { return "Restore at least one stroke before sending." }
    return nil
  }
  package var canSendToPlotter: Bool { sendUnavailableReason == nil }
  /// Expensive generation can be replaced; durable edits/recovery must settle.
  package var canNavigateExploration: Bool {
    acceptsChanges && !needsRecovery && (!isBusy || generationActive || rendering != nil || proposing != nil)
  }
  package func invalidateRegionPreview() { invalidateGeneration(); regionPreviewPending = true }
  package func discardRegionPreview() { regionPreviewPending = false }
  package func commitRegion(_ region: PortraitNormalizedRegion?) async {
    guard let store, let source = selectedSource, acceptsChanges else { return }
    invalidateGeneration(); let request = generationRevision, navigation = photoSelectionRevision; returnToEditing()
    var options = committedAnalysisOptions; options.manualRegion = region?.bounded
    await perform("Saving photo region…") {
      try await store.setAuthoringOptions(sourceID: source.id, options: options)
      // A newer draft invalidates rendering, not the already committed source
      // preference. Publish that durable head for the same navigation epoch;
      // otherwise discarding the draft could resurrect the preceding round.
      if navigation == self.photoSelectionRevision { try await self.refresh() }
      if request == self.generationRevision { self.regionPreviewPending = false }
    }
  }

  /// A tile click is the existing weak, exact offered-set choice, once. History
  /// and automatic recommendations use neutral browsing instead.
  package func exploreCandidate(_ id: UUID) async {
    guard acceptsChanges, !needsRecovery, let selected = document?.candidates.first(where: { $0.id == id }),
      selected.sourceID == selectedSource?.id,
      document?.rounds.first(where: { $0.id == selected.roundID })?.analysisOptions == committedAnalysisOptions,
      let store else { return }
    if let reason = candidateRefinementUnavailableReason(selected) { error = reason; return }
    guard let offeredRound = document?.rounds.first(where: { $0.id == selected.roundID }), let document else { return }
    let offered = offeredRound.displayedCandidateIDs.isEmpty ? offeredRound.candidateIDs : offeredRound.displayedCandidateIDs
    let items = offered.compactMap { candidateID -> FlowPortfolioPresentationItem? in
      guard let value = document.candidates.first(where: { $0.id == candidateID }),
        candidateRefinementUnavailableReason(value) == nil else { return nil }
      let edit = document.latestPrune(candidateID: candidateID)
      return .init(id: edit?.id ?? candidateID, candidateID: candidateID, revisionID: edit?.id,
        sourceID: value.sourceID, removedIndices: edit?.removedIndices ?? [])
    }
    guard items.contains(where: { $0.candidateID == id }) else {
      error = "This drawing is unavailable for exploration."; return
    }
    let admission = id.uuidString + ":" + items.map { $0.id.uuidString }.joined(separator: ":")
    guard explorationAdmission != admission else { return }
    explorationAdmission = admission
    defer { if explorationAdmission == admission { explorationAdmission = nil } }
    invalidateGeneration(); let request = generationRevision
    pendingExplorationParentID = id; returnToEditing(); stage = .explore
    await perform("Retaining exploration choice…") {
      try await store.chooseCandidate(id, offeredItems: items)
      if request == self.generationRevision { try await self.refresh() }
    }
    guard request == generationRevision, !needsRecovery, !closing, error == nil else {
      if request == generationRevision { pendingExplorationParentID = nil }
      return
    }
    await generate(refining: true)
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
    pendingMetadataCount = pendingNames.count
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
      guard !pendingNames.isEmpty else { return }
      let id = UUID()
      let task = Task { @MainActor in
        defer {
          // Clear before completion, and only our handle. A late joiner must
          // never clear a newer worker or mistake this completed one for it.
          if self.nameFlushID == id { self.nameFlush = nil; self.nameFlushID = nil }
        }
        while !self.pendingNames.isEmpty {
          let edit = self.pendingNames.removeFirst()
          self.pendingMetadataCount = self.pendingNames.count
          await self.perform("Saving name…", alreadyAdmitted: true) {
            if edit.photo { try await edit.store.renameSource(sourceID: edit.id, title: edit.title) }
            else { try await edit.store.renameCandidate(candidateID: edit.id, title: edit.title) }
            try await self.refresh()
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
    self.nominalPenWidthMM = FlowAuthoringContext(strokeStyle: style, nominalPenWidthMM: nominalPenWidthMM).nominalPenWidthMM
  }

  package func generate(refining: Bool, recommendation: Bool = false, broadAnchor: UUID? = nil) async {
    guard let store, let source = selectedSource else { return }
    guard acceptsChanges, !needsRecovery else { return }
    let parent = refining ? candidate : nil
    if let parent, let reason = candidateRefinementUnavailableReason(parent) { error = reason; return }
    if let parent, (document?.latestPrune(candidateID: parent.id)?.removedIndices.count ?? 0) >= parent.strokeCount {
      error = "Restore at least one stroke before refining this drawing."; return
    }
    let options = committedAnalysisOptions, checkpoint = activeCheckpoint
    guard !refining || parent.flatMap({ value in document?.rounds.first { $0.id == value.roundID } })?.analysisOptions == options else {
      error = "Choose a drawing generated for the current source region before refining."; return
    }
    guard broadAnchor == nil || (!refining && broadAnchor == candidate?.id && program != nil
      && candidate?.sourceID == source.id
      && document?.rounds.first(where: { $0.id == candidate?.roundID })?.analysisOptions == options) else { return }
    let broadPreview = broadAnchor.flatMap { previews[$0] }
    invalidateGeneration()
    let request = generationRevision
    generationActive = true
    pendingBroadAnchorID = broadAnchor; pendingBroadAnchorPreview = broadPreview
    defer {
      if generationRevision == request {
        generationActive = false; pendingExplorationParentID = nil
        pendingBroadAnchorID = nil; pendingBroadAnchorPreview = nil
      }
    }
    let parentDepth = parent.flatMap { value in document?.rounds.first { $0.id == value.roundID }?.explorationDepth } ?? 0
    let depth = refining ? min(10_000, parentDepth + 1) : 0
    let radius: Double? = refining ? max(0.015, 0.06 * pow(0.85, Double(depth - 1))) : nil
    let inheritedRevision = parent.flatMap { self.document?.latestPrune(candidateID: $0.id) }
    pendingExplorationParentID = parent?.id
    returnToEditing()
    let pen = strokeStyle, nominalWidth = nominalPenWidthMM, panelCount = recommendation ? (checkpoint?.ranker == nil ? 1 : 3) : min(9, max(3, count))
    if refining && parent == nil { return }
    await perform(refining ? "Preparing refinement…" : "Preparing broad exploration…") {
      guard request == self.generationRevision, self.selectedSource?.id == source.id,
        self.committedAnalysisOptions == options, !self.closing else { throw CancellationError() }
      self.cancelRequested = false
      let data = try await store.sourceData(source.id)
      guard request == self.generationRevision, !self.closing else { throw CancellationError() }
      let seed = UInt64.random(in: 1...UInt64.max)
      do { try checkpoint?.validateForInference() }
      catch { throw FlowPortfolioError.invalid(error.localizedDescription) }
      let recipes: [FlowArtistRecipe]
      if self.renderOverride != nil {
        recipes = parent?.recipe.refined(count: panelCount, seed: seed, radius: radius ?? 0.06)
          ?? FlowArtistRecipe.broad(count: panelCount, seed: seed)
      } else {
        let renderer = self.renderer
        let worker = Task.detached(priority: .userInitiated) {
          try await renderer.proposals(data: data, count: panelCount, seed: seed,
            parent: parent?.recipe, checkpoint: checkpoint, analysisOptions: options,
            refinementRadius: radius ?? 0.06, photoReference: source.photo)
        }
        self.proposing = worker
        defer { self.proposing = nil }
        recipes = try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
      }
      guard request == self.generationRevision, !self.closing else { throw CancellationError() }
      let round = try await store.beginRound(sourceID: source.id, recipes: recipes,
        parentCandidateID: parent?.id, modelID: checkpoint?.id, seed: seed, analysisOptions: options,
        explorationDepth: depth, refinementRadius: radius, explorationPolicy: "contracting-neighborhood-v1")
      self.stage = .explore; try await self.refresh()
      var scores: [(UUID, Double, [Int])] = []
      var cancelled = false
      for (slot, recipe) in recipes.enumerated() {
        if Task.isCancelled || self.cancelRequested || request != self.generationRevision { cancelled = true; break }
        self.progress = "Drawing \(slot + 1) of \(recipes.count)…"
        let generated: GeneratedCandidate
        let isExactAnchor = slot == 0 && parent?.recipe == recipe
        do {
          let renderer = self.renderer, override = self.renderOverride
          let parentLink: SourceLink<DrawingRef>
          if let parent { parentLink = .present(try await store.retainedDrawing(candidateID: parent.id, revisionID: inheritedRevision?.id).reference!) }
          else { parentLink = .none }
          let photo = try await store.sourcePhoto(source.id)
          let input = PortraitFlowDrawingProducer.Input(data: data, parent: parentLink, photo: photo)
          let settings = PortraitFlowDrawingProducer.Settings(recipe: recipe,
            analysisOptions: options, strokeStyle: pen, nominalPenWidthMM: nominalWidth)
          var reused: PortraitRenderResult?, reusedPreview: Data?
          if isExactAnchor, let parent {
            reused = PortraitRenderResult(raster: try await store.candidateRaster(parent.id),
              program: try await store.candidateProgram(parent.id))
            reusedPreview = try await store.candidatePreview(parent.id)
          }
          guard request == self.generationRevision, !self.cancelRequested else { throw CancellationError() }
          let anchor = reused, anchorPreview = reusedPreview, inheritedMask = Set(inheritedRevision?.removedIndices ?? [])
          // Admission, image encoding, prediction and scoring share one tracked
          // worker. Replacing a generation cancels the next expensive stage,
          // including the exact-anchor path, without dropping durable feedback.
          let worker = Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            let production: DrawingProduction<PortraitRenderResult>
            if let anchor {
              production = try PortraitFlowDrawingProducer.admit(result: anchor, input: input,
                settings: settings, origin: .reusedArtifacts)
            } else if let override {
              production = try PortraitFlowDrawingProducer.admit(result: await override(data, recipe, pen),
                input: input, settings: settings, origin: .providedArtifacts)
            } else {
              production = try await renderer.produce(data: data, recipe: recipe, strokeStyle: pen,
                nominalPenWidthMM: nominalWidth, parent: parentLink, photo: photo, analysisOptions: options)
            }
            try Task.checkCancellation()
            let result = production.artifacts, program = production.drawing.program
            let preview = try anchorPreview ?? FlowAuthoringRenderer.preview(program)
            try Task.checkCancellation()
            let removed: Set<Int>, probabilities: [Double]?
            if anchor != nil { removed = inheritedMask; probabilities = nil }
            else if let checkpoint {
              let features = FlowArtistFeatures.strokes(recipe: recipe, program: program, raster: result.raster)
              try Task.checkCancellation()
              let values = try checkpoint.deletionProbabilities(strokeFeatures: features)
              probabilities = values; removed = try checkpoint.removedIndices(probabilities: values)
            } else { removed = []; probabilities = nil }
            try Task.checkCancellation()
            let score = try checkpoint?.score(features: FlowArtistFeatures.drawing(recipe: recipe,
              program: program, raster: result.raster, removedIndices: removed)) ?? 0
            try Task.checkCancellation()
            return GeneratedCandidate(production: production, preview: preview, removed: removed,
              probabilities: probabilities, score: score)
          }
          self.rendering = worker
          generated = try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
          self.rendering = nil
        } catch is CancellationError {
          self.rendering = nil; cancelled = true
          try await store.failCandidate(roundID: round.id, slot: slot, message: "Cancelled")
          break
        } catch {
          self.rendering = nil
          try await store.failCandidate(roundID: round.id, slot: slot, message: error.localizedDescription)
          continue
        }
        let production = generated.production, preview = generated.preview, removed = generated.removed
        let probabilities = generated.probabilities, score = generated.score
        // An obsolete renderer may finish after cancellation (e.g. Vision).
        // It has no authority to commit a candidate into the visible new input.
        if request != self.generationRevision || self.cancelRequested { cancelled = true; break }
        // Storage failures are not renderer failures. Stop without overwriting a
        // completed slot; recovery marks any unfinished round interrupted.
        let saved = try await store.completeCandidate(roundID: round.id, slot: slot,
          production: production, previewPNG: preview)
        if isExactAnchor, let inheritedRevision {
          _ = try await store.applyPrune(candidateID: saved.id, action: .inheritedSelection,
            indices: removed.sorted(), inheritedFromRevisionID: inheritedRevision.id)
        } else if let checkpoint, let probabilities {
          _ = try await store.applyPrune(candidateID: saved.id, action: .modelProposal,
            indices: removed.sorted(), modelID: checkpoint.id, probabilities: probabilities,
            threshold: 0.65, policy: "threshold-keep-one-v1")
        }
        scores.append((saved.id, score, removed.sorted()))
        if request == self.generationRevision { try await self.refresh() }
      }
      let ordered = checkpoint?.ranker == nil ? scores.map(\.0) : scores.sorted { $0.1 > $1.1 }.map(\.0)
      let winner = checkpoint?.ranker == nil ? nil : ordered.first
      let scoredMask = winner.flatMap { id in scores.first(where: { $0.0 == id })?.2 }
      try await store.finishRound(round.id, cancelled: cancelled, displayOrder: ordered,
        recommendedCandidateID: winner, recommendedRemovedIndices: scoredMask)
      if request == self.generationRevision { try await self.refresh() }
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
          let dataset = try await FlowAuthoringTraining.dataset(store: store, document: snapshot)
          if let fitter { return try await fitter(dataset.examples, dataset.rankings) }
          return FlowArtistTraining.fit(examples: dataset.examples, rankings: dataset.rankings, seed: dataset.seed,
            configuration: dataset.configuration, frozenHoldoutGroupIDs: dataset.holdoutGroupIDs)
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
    invalidateGeneration()
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
    if let reason = sendUnavailableReason { throw FlowPortfolioError.unavailable(reason) }
    guard let store, let candidate else { throw FlowPortfolioError.unavailable("Choose a drawing first.") }
    let navigation = photoSelectionRevision
    let drawing = try await store.retainedDrawing(candidateID: candidate.id, revisionID: prune?.id)
    // Retention is durable even if navigation changed while it settled. Only
    // the admitting navigation epoch may publish or return its drawing to Send.
    guard navigation == photoSelectionRevision, !closed, !closing else { throw CancellationError() }
    try await refresh(photoRevision: navigation)
    return drawing
  }
  package func exportDrawing(to url: URL) async throws {
    guard let store else { throw FlowPortfolioError.unavailable("Library is unavailable.") }
    let drawing = try await retainedDrawing()
    try await store.exportDrawing(drawing, to: url)
  }

  private func invalidateGeneration() {
    generationRevision &+= 1; cancelRequested = true; rendering?.cancel(); proposing?.cancel()
    generationActive = false; pendingExplorationParentID = nil
    pendingBroadAnchorID = nil; pendingBroadAnchorPreview = nil
  }
  package func cancel() { invalidateGeneration(); fitting?.cancel() }
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
        self.failedIntent = nil; self.needsRecovery = false; self.error = nil; self.regionPreviewPending = false
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
  private func refresh(photoRevision: UInt64? = nil, isStillCurrent: @MainActor () -> Bool = { true }) async throws {
    guard let store else { return }
    func assertCurrent() throws {
      guard !closed, isStillCurrent() else { throw CancellationError() }
      // Admitted recovery/edit work must finish while shutdown joins it. Only
      // navigation requests lose publication authority when closing begins.
      if let photoRevision {
        guard !closing, photoRevision == photoSelectionRevision else { throw CancellationError() }
      }
    }
    try await store.refreshPhotoMetadata(); try assertCurrent()
    let snapshot = await store.snapshot(); try assertCurrent()
    let source = snapshot.sources.first { $0.id == snapshot.selectedSourceID }
    let candidate = snapshot.candidates.first { $0.id == snapshot.currentCandidateID }
    if source?.image.sha256 != loadedSourceHash {
      // Preserve the DX10 failed-open contract: the admitted new identity may
      // remain unavailable, but it must never keep the preceding Photo's pixels
      // or program if its subsequent exact asset read fails.
      document = snapshot; sourceData = nil; loadedSourceHash = nil
      program = nil; loadedProgramID = nil
    }
    if candidate?.id != loadedProgramID {
      document = snapshot; program = nil; loadedProgramID = nil; candidateLoadError = nil
    }
    let lastFit = snapshot.fits.last(where: \.hasCheckpoint)
    let activeFit = snapshot.fits.first { $0.id == snapshot.activeFitID }
    let nextFittedSnapshot = snapshot.trainingSnapshots.first { $0.id == lastFit?.snapshotID }
    let nextActiveSnapshot = snapshot.trainingSnapshots.first { $0.id == activeFit?.snapshotID }
    guard lastFit == nil || nextFittedSnapshot != nil,
      activeFit == nil || nextActiveSnapshot != nil else {
      throw FlowPortfolioError.unavailable("The exact frozen training snapshot is unavailable.")
    }
    var fitted = fittedDocument, active = activeTrainingDocument
    if fittedSnapshot != nextFittedSnapshot {
      if let lastFit { fitted = try await store.trainingDocument(snapshotID: lastFit.snapshotID); try assertCurrent() }
      else { fitted = nil }
    }
    if activeSnapshot != nextActiveSnapshot {
      if nextActiveSnapshot == nextFittedSnapshot { active = fitted }
      else if let activeFit { active = try await store.trainingDocument(snapshotID: activeFit.snapshotID); try assertCurrent() }
      else { active = nil }
    }
    let summaryKey = FlowAuthoringTrainingProgressKey(snapshot)
    let summary: FlowAuthoringTrainingProgress
    if trainingProgressKey == summaryKey, let progress = trainingProgress { summary = progress.atRevision(snapshot.revision) }
    else {
      trainingSummaryBuildCount += 1
      summary = FlowAuthoringTrainingProgress(document: snapshot, fittedDocument: fitted, activeDocument: active)
    }
    var pixels = sourceData, sourceHash = loadedSourceHash
    if let source {
      if sourceHash != source.image.sha256 {
        pixels = try await store.sourceData(source.id); try assertCurrent(); sourceHash = source.image.sha256
      }
    } else { pixels = nil; sourceHash = nil }
    var selectedProgram = program, programID = loadedProgramID
    if let candidate {
      if programID != candidate.id {
        do {
          selectedProgram = try await store.candidateProgram(candidate.id); try assertCurrent()
          programID = candidate.id; candidateLoadError = nil
        } catch is CancellationError { throw CancellationError() }
        catch {
          try assertCurrent(); selectedProgram = nil; programID = nil
          candidateLoadError = "Drawing unavailable: " + error.localizedDescription
        }
      }
    } else { selectedProgram = nil; programID = nil }
    var checkpoint = activeCheckpoint, issue = activeModelIssue
    let nextCheckpointKey = activeFit.map { CheckpointKey(portfolio: snapshot.id, fit: $0, snapshot: nextActiveSnapshot) }
    if let fitID = snapshot.activeFitID {
      guard nextCheckpointKey != nil else { throw FlowPortfolioError.unavailable("Model checkpoint is unavailable.") }
      if checkpointKey != nextCheckpointKey {
        let bytes = try await store.checkpointData(fitID: fitID); try assertCurrent()
        checkpointDecodeCount += 1
        checkpoint = try JSONDecoder().decode(FlowArtistCheckpoint.self, from: bytes)
        try checkpoint?.validateArchive()
        do { try checkpoint?.validateForInference(); issue = nil }
        catch { issue = error.localizedDescription }
      }
    } else { checkpoint = nil; issue = nil }
    let round = snapshot.rounds.first { $0.id == snapshot.currentRoundID }
    let ids = round.map { $0.displayedCandidateIDs.isEmpty ? $0.candidateIDs : $0.displayedCandidateIDs } ?? []
    let visibleIDs = Set(ids)
    let availabilityIDs = visibleIDs.union(candidate.map { [$0.id] } ?? [])
    let unavailable = try await store.candidateUnavailableReasons(Array(availabilityIDs)); try assertCurrent()
    var nextPreviews = previews.filter { visibleIDs.contains($0.key) }
    var nextKeys = previewKeys.filter { visibleIDs.contains($0.key) }
    for candidate in snapshot.candidates where visibleIDs.contains(candidate.id) {
      let revision = snapshot.latestPrune(candidateID: candidate.id)
      let key = candidate.programHash + ":" + (revision?.id.uuidString ?? candidate.preview.sha256)
      guard nextKeys[candidate.id] != key else { continue }
      let item = FlowPortfolioPresentationItem(id: revision?.id ?? candidate.id, candidateID: candidate.id,
        revisionID: revision?.id, sourceID: candidate.sourceID, removedIndices: revision?.removedIndices ?? [])
      nextPreviews[candidate.id] = try? await store.presentationPreview(item); try assertCurrent()
      nextKeys[candidate.id] = key
    }
    // Publish prepared state only after every exact read has settled. A late
    // photo/close completion cannot pair old pixels, checkpoint or geometry with
    // a newer visible identity.
    try assertCurrent()
    document = snapshot; sourceData = pixels; loadedSourceHash = sourceHash
    program = selectedProgram; loadedProgramID = programID
    fittedDocument = fitted; activeTrainingDocument = active
    fittedSnapshot = nextFittedSnapshot; activeSnapshot = nextActiveSnapshot
    trainingProgress = summary; trainingProgressKey = summaryKey
    activeCheckpoint = checkpoint; activeModelIssue = issue; checkpointKey = nextCheckpointKey
    previews = nextPreviews; previewKeys = nextKeys; candidateUnavailableReasons = unavailable
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
    let visible = Set(presentation.items.map(\.id))
    var previews = rankingPreviews.filter { visible.contains($0.key) }
    for item in presentation.items where previews[item.id] == nil {
      let data = try? await store.presentationPreview(item)
      guard !closed, self.presentation?.id == presentation.id else { return }
      previews[item.id] = data
    }
    guard !closed, self.presentation?.id == presentation.id else { return }
    rankingPreviews = previews
  }
}
