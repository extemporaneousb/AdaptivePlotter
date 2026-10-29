import Darwin
import Foundation
import PlotterModel
import PortraitArtists
import PortraitCore

/// One writer owns a portable portfolio. Immutable dependencies and operation
/// records become visible together through one atomic head replacement.
package actor FlowPortfolioStore {
  let storage: FlowPortfolioStorage
  var state: FlowPortfolioSnapshot
  private var head: FlowPortfolioHead
  package nonisolated let directory: URL

  package init(directory: URL, purpose: FlowPortfolioPurpose? = nil) throws {
    let storage = try FlowPortfolioStorage(directory: directory)
    let loaded = try storage.loadOrCreate(purpose: purpose)
    self.storage = storage; self.directory = storage.directory
    state = loaded.0; head = loaded.1
  }

  package func snapshot() -> FlowPortfolioSnapshot { state }

  /// Recover an uncertain durability outcome by reading the committed head,
  /// before a UI retries the still-pending user intent.
  package func reloadCommittedState() throws {
    let loaded = try storage.loadOrCreate(purpose: state.purpose)
    state = loaded.0; head = loaded.1
  }

  func commit(_ next: FlowPortfolioSnapshot, operation: String, subjectID: UUID? = nil) throws {
    var next = next; next.revision = state.revision + 1
    try FlowPortfolioValidation.validate(next)
    let record = FlowPortfolioRecord(schemaVersion: 1, sequence: next.revision, id: UUID(),
      createdAt: Date(), previousRecordSHA256: head.recordSHA256, operation: operation,
      subjectID: subjectID, portfolioID: next.id, portfolioCreatedAt: next.createdAt, portfolioPurpose: next.purpose,
      delta: FlowPortfolioDelta(previous: state, next: next))
    let newHead = try storage.commit(record, expecting: head)
    state = next; head = newHead
  }

  @discardableResult package func addSource(data: Data, title: String, mediaType: String = "image/png") throws -> FlowPortfolioSource {
    let asset = try DrawingPackageLibraryValidation.sourceAsset(data)
    guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, title.utf8.count <= 1024 else {
      throw FlowPortfolioError.invalid("Name the imported photograph.")
    }
    let blob = try storage.retain(data, mediaType: asset.mediaType)
    let source = FlowPortfolioSource(id: UUID(), createdAt: Date(), title: title,
      image: blob, subjectID: nil, sessionID: nil)
    var next = state; next.sources.append(source); next.selectedSourceID = source.id
    next.currentRoundID = nil; next.currentCandidateID = nil; next.currentPruneRevisionID = nil
    try commit(next, operation: "sourceImported", subjectID: source.id)
    return source
  }

  package func selectSource(_ id: UUID) throws {
    _ = try source(id)
    var next = state; next.selectedSourceID = id
    next.currentRoundID = next.rounds.last(where: { $0.sourceID == id })?.id
    next.currentCandidateID = next.choices.last(where: { $0.roundID == next.currentRoundID })?.candidateID
    next.currentPruneRevisionID = next.currentCandidateID.flatMap { next.latestPrune(candidateID: $0)?.id }
    try commit(next, operation: "sourceSelected", subjectID: id)
  }

  /// Browsing a historical round supplies no preference judgment.
  package func selectRound(_ id: UUID) throws {
    let value = try round(id)
    var next = state; next.selectedSourceID = value.sourceID; next.currentRoundID = id
    next.currentCandidateID = next.choices.last(where: { $0.roundID == id })?.candidateID
    next.currentPruneRevisionID = next.currentCandidateID.flatMap { next.latestPrune(candidateID: $0)?.id }
    try commit(next, operation: "roundSelected", subjectID: id)
  }

  package func setSourceGroups(sourceID: UUID, subjectID: String?, sessionID: String?, excluded: Bool? = nil) throws {
    _ = try source(sourceID)
    func normalized(_ value: String?) throws -> String? {
      guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
      guard value.utf8.count <= 256 else { throw FlowPortfolioError.invalid("Group identity is too long.") }
      return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    let subject = try normalized(subjectID), session = try normalized(sessionID)
    var next = state
    let index = next.sources.firstIndex { $0.id == sourceID }!
    next.sources[index].subjectID = subject; next.sources[index].sessionID = session
    if let excluded { next.sources[index].excluded = excluded }
    try commit(next, operation: "sourceGroupsDeclared", subjectID: sourceID)
  }

  package func setSourceExcluded(sourceID: UUID, excluded: Bool) throws {
    _ = try source(sourceID); var next = state
    next.sources[next.sources.firstIndex { $0.id == sourceID }!].excluded = excluded
    try commit(next, operation: "sourceCurationChanged", subjectID: sourceID)
  }

  @discardableResult package func beginRound(sourceID: UUID, recipes: [FlowArtistRecipe],
    parentCandidateID: UUID? = nil, modelID: String? = nil, seed: UInt64 = 0,
    analysisOptions: PortraitAnalysisOptions = .init()) throws -> FlowPortfolioRound {
    _ = try source(sourceID)
    guard (1...24).contains(recipes.count), recipes.allSatisfy({ $0.values.allSatisfy { $0.isFinite && (0...1).contains($0) } }) else {
      throw FlowPortfolioError.invalid("A round requires one to twenty-four bounded Flow Edge recipes.")
    }
    if let parentCandidateID, try candidate(parentCandidateID).sourceID != sourceID {
      throw FlowPortfolioError.invalid("A refinement must retain its parent's source photograph.")
    }
    let round = FlowPortfolioRound(id: UUID(), createdAt: Date(), sourceID: sourceID,
      parentCandidateID: parentCandidateID, recipes: recipes, analysisOptions: analysisOptions, seed: seed, modelID: modelID,
      status: .generating, candidateIDs: [], displayedCandidateIDs: [], recommendedCandidateID: nil, failures: [])
    var next = state; next.rounds.append(round); next.selectedSourceID = sourceID
    next.currentRoundID = round.id; next.currentCandidateID = parentCandidateID
    next.currentPruneRevisionID = parentCandidateID.flatMap { next.latestPrune(candidateID: $0)?.id }
    try commit(next, operation: "roundRequested", subjectID: round.id)
    return round
  }

  @discardableResult package func completeCandidate(roundID: UUID, slot: Int, program: DrawingProgram,
    raster: PortraitRaster, previewPNG: Data) throws -> FlowPortfolioCandidate {
    let round = try round(roundID); try checkSlot(round, slot)
    guard program.source.kind == "portrait", !program.strokes.isEmpty,
      program.strokes.count <= DrawingTransferLimits.maximumStrokes else {
      throw FlowPortfolioError.invalid("A candidate must be a bounded nonempty portrait drawing.")
    }
    let previewAsset = try DrawingPackageLibraryValidation.sourceAsset(previewPNG)
    guard previewAsset.mediaType == "image/png" else { throw FlowPortfolioError.invalid("Candidate preview must be PNG.") }
    let result = FlowPortfolioCandidate(id: UUID(), createdAt: Date(), sourceID: round.sourceID,
      roundID: roundID, slot: slot, parentCandidateID: round.parentCandidateID, recipe: round.recipes[slot],
      modelID: round.modelID,
      program: try storage.retain(encode(program), mediaType: "application/json"),
      raster: try storage.retain(encode(raster), mediaType: "application/json"),
      preview: try storage.retain(previewPNG, mediaType: "image/png"),
      programHash: program.contentHash.description, strokeCount: program.strokes.count)
    var next = state; next.candidates.append(result)
    next.rounds[next.rounds.firstIndex { $0.id == roundID }!].candidateIDs.append(result.id)
    try commit(next, operation: "candidateCompleted", subjectID: result.id)
    return result
  }

  package func failCandidate(roundID: UUID, slot: Int, message: String) throws {
    let round = try round(roundID); try checkSlot(round, slot)
    guard !message.isEmpty, message.utf8.count <= 8192 else { throw FlowPortfolioError.invalid("Generation failure needs a bounded explanation.") }
    var next = state
    next.rounds[next.rounds.firstIndex { $0.id == roundID }!].failures.append(
      .init(slot: slot, message: message, recordedAt: Date()))
    try commit(next, operation: "candidateFailed", subjectID: roundID)
  }

  package func finishRound(_ id: UUID, cancelled: Bool = false, displayOrder: [UUID]? = nil,
    recommendedCandidateID: UUID? = nil) throws {
    let round = try round(id)
    guard round.status == .generating else { throw FlowPortfolioError.conflict("This round has already settled.") }
    guard cancelled || round.candidateIDs.count + round.failures.count == round.recipes.count else {
      throw FlowPortfolioError.invalid("Every requested candidate must settle before the round completes.")
    }
    let order = displayOrder ?? round.candidateIDs
    guard Set(order) == Set(round.candidateIDs), order.count == round.candidateIDs.count,
      recommendedCandidateID == nil || order.contains(recommendedCandidateID!) else {
      throw FlowPortfolioError.invalid("Round presentation must contain every completed candidate exactly once.")
    }
    var next = state
    let index = next.rounds.firstIndex { $0.id == id }!
    next.rounds[index].status = cancelled ? .cancelled : .completed
    next.rounds[index].displayedCandidateIDs = order
    next.rounds[index].recommendedCandidateID = recommendedCandidateID
    try commit(next, operation: cancelled ? "roundCancelled" : "roundCompleted", subjectID: id)
  }

  package func markInterruptedRounds() throws {
    guard state.rounds.contains(where: { $0.status == .generating }) else { return }
    var next = state
    for index in next.rounds.indices where next.rounds[index].status == .generating { next.rounds[index].status = .interrupted }
    try commit(next, operation: "pendingRoundsRecovered")
  }

  package func chooseCandidate(_ id: UUID) throws {
    let value = try candidate(id), round = try round(value.roundID)
    let offered = round.displayedCandidateIDs.isEmpty ? round.candidateIDs : round.displayedCandidateIDs
    let items = try offered.map { offeredID -> FlowPortfolioPresentationItem in
      let value = try candidate(offeredID), edit = state.latestPrune(candidateID: offeredID)
      return .init(id: edit?.id ?? offeredID, candidateID: offeredID, revisionID: edit?.id,
        sourceID: value.sourceID, removedIndices: edit?.removedIndices ?? [])
    }
    let choice = FlowPortfolioChoice(id: UUID(), createdAt: Date(), roundID: round.id,
      candidateID: id, offeredCandidateIDs: offered,
      selectedItemID: items.first(where: { $0.candidateID == id })!.id,
      offeredItems: items, purpose: "refine-or-prune")
    var next = state; next.choices.append(choice); next.selectedSourceID = value.sourceID
    next.currentRoundID = value.roundID; next.currentCandidateID = id
    next.currentPruneRevisionID = next.latestPrune(candidateID: id)?.id
    try commit(next, operation: "candidateChosen", subjectID: id)
  }

  @discardableResult package func applyPrune(candidateID: UUID, action: FlowPruneAction,
    indices: [Int] = [], modelID: String? = nil, inheritedFromRevisionID: UUID? = nil,
    probabilities: [Double]? = nil, threshold: Double? = nil, policy: String? = nil) throws -> FlowPortfolioPruneRevision {
    let value = try candidate(candidateID), prior = state.latestPrune(candidateID: candidateID)
    guard Set(indices).count == indices.count, indices.allSatisfy({ (0..<value.strokeCount).contains($0) }) else {
      throw FlowPortfolioError.invalid("Pruning must name distinct original stroke indices.")
    }
    var removed = Set(prior?.removedIndices ?? []), affected = Set(indices)
    var undo = prior?.undoOperationIDs ?? [], redo = prior?.redoOperationIDs ?? []
    var operationID: UUID?
    let id = UUID()
    switch action {
    case .remove:
      guard modelID == nil, !affected.isEmpty, affected.isDisjoint(with: removed) else {
        throw FlowPortfolioError.invalid("Removal must name visible lines and be attributed to the human.")
      }
      removed.formUnion(affected); undo.append(id); redo = []
    case .restore:
      guard modelID == nil, !affected.isEmpty, affected.isSubset(of: removed) else {
        throw FlowPortfolioError.invalid("Restoration must name removed original lines.")
      }
      removed.subtract(affected); undo.append(id); redo = []
    case .modelProposal:
      guard prior == nil, let modelID, !modelID.isEmpty else {
        throw FlowPortfolioError.invalid("A learned mask is the initial proposal, before human pruning.")
      }
      guard let probabilities, probabilities.count == value.strokeCount,
        probabilities.allSatisfy({ $0.isFinite && (0...1).contains($0) }),
        let threshold, threshold.isFinite, (0.5...1).contains(threshold), policy == "threshold-keep-one-v1" else {
        throw FlowPortfolioError.invalid("Learned pruning requires its exact probabilities, threshold and policy.")
      }
      var proposed = Set(probabilities.indices.filter { probabilities[$0] >= threshold })
      if proposed.count == probabilities.count, let keep = probabilities.indices.min(by: { probabilities[$0] < probabilities[$1] }) { proposed.remove(keep) }
      guard proposed == affected else { throw FlowPortfolioError.invalid("Learned mask differs from its retained inference policy.") }
      removed = affected; undo = []; redo = []
    case .inheritedSelection:
      guard prior == nil, modelID == nil, let inheritedFromRevisionID,
        let inherited = state.pruneRevisions.first(where: { $0.id == inheritedFromRevisionID }),
        let parent = state.candidates.first(where: { $0.id == inherited.candidateID }),
        parent.programHash == value.programHash, parent.sourceID == value.sourceID,
        inherited.removedIndices == affected.sorted() else {
        throw FlowPortfolioError.invalid("An inherited selection requires the exact earlier drawing and mask.")
      }
      removed = affected; undo = []; redo = []
    case .completeTarget:
      guard indices.isEmpty, modelID == nil else { throw FlowPortfolioError.invalid("A completed target is an explicit human judgment of the current mask.") }
      affected = []
    case .undo, .redo:
      guard indices.isEmpty, modelID == nil else { throw FlowPortfolioError.invalid("Undo and redo select their recorded operation automatically.") }
      let targetID = action == .undo ? undo.popLast() : redo.popLast()
      guard let targetID, let target = state.pruneRevisions.first(where: { $0.id == targetID && $0.candidateID == candidateID }),
        target.action == .remove || target.action == .restore else { throw FlowPortfolioError.unavailable("There is no edit to undo or redo.") }
      operationID = targetID; affected = Set(target.affectedIndices)
      let shouldRemove = (target.action == .remove) == (action == .redo)
      if shouldRemove { removed.formUnion(affected) } else { removed.subtract(affected) }
      if action == .undo { redo.append(targetID) } else { undo.append(targetID) }
    }
    // An empty target is valid curation evidence; export refuses it as a plot.
    let revision = FlowPortfolioPruneRevision(id: id, createdAt: Date(), candidateID: candidateID,
      parentRevisionID: prior?.id, action: action, affectedIndices: affected.sorted(), removedIndices: removed.sorted(),
      modelID: modelID, operationID: operationID, inheritedFromRevisionID: inheritedFromRevisionID,
      historicalRecord: nil, probabilities: probabilities, threshold: threshold, policy: policy, undoOperationIDs: undo, redoOperationIDs: redo)
    var next = state; next.pruneRevisions.append(revision)
    if action != .modelProposal && action != .inheritedSelection {
      next.currentCandidateID = candidateID; next.selectedSourceID = value.sourceID
      next.currentRoundID = value.roundID; next.currentPruneRevisionID = id
    }
    try commit(next, operation: "prune." + action.rawValue, subjectID: revision.id)
    return revision
  }

  @discardableResult package func presentRanking(scope: FlowRankingScope, count: Int = 6,
    seed: UInt64) throws -> FlowPortfolioPresentation {
    guard (2...24).contains(count) else { throw FlowPortfolioError.invalid("Ranking sets contain two to twenty-four drawings.") }
    let permitted: [FlowPortfolioCandidate]
    switch scope {
    case .portfolio: permitted = state.candidates
    case .candidate(let id): permitted = [try candidate(id)]
    case .source(let id): _ = try source(id); permitted = state.candidates.filter { $0.sourceID == id }
    case .round(let id): _ = try round(id); permitted = state.candidates.filter { $0.roundID == id }
    }
    var items: [FlowPortfolioPresentationItem] = []
    for candidate in permitted where !candidate.excluded && state.sources.contains(where: { $0.id == candidate.sourceID && !$0.excluded }) {
      items.append(.init(id: candidate.id, candidateID: candidate.id, revisionID: nil, sourceID: candidate.sourceID, removedIndices: []))
      var masks = Set(["[]"])
      for edit in state.pruneRevisions where edit.candidateID == candidate.id {
        let key = edit.removedIndices.description
        if masks.insert(key).inserted {
          items.append(.init(id: edit.id, candidateID: candidate.id, revisionID: edit.id, sourceID: candidate.sourceID, removedIndices: edit.removedIndices))
        }
      }
    }
    guard items.count >= 2 else { throw FlowPortfolioError.unavailable("Create at least two drawing versions before ranking.") }
    var random = FlowPortfolioRandom(state: seed)
    for index in stride(from: items.count - 1, through: 1, by: -1) {
      items.swapAt(index, Int(random.next() % UInt64(index + 1)))
    }
    let presentation = FlowPortfolioPresentation(id: UUID(), createdAt: Date(), scope: scope,
      seed: seed, items: Array(items.prefix(count)))
    var next = state; next.presentations.append(presentation); next.currentPresentationID = presentation.id
    try commit(next, operation: "rankingPresented", subjectID: presentation.id)
    return presentation
  }

  package func selectPresentation(_ id: UUID) throws {
    guard state.presentations.contains(where: { $0.id == id }) else { throw FlowPortfolioError.unavailable("Ranking presentation is unavailable.") }
    var next = state; next.currentPresentationID = id
    try commit(next, operation: "rankingSelected", subjectID: id)
  }

  @discardableResult package func recordRanking(presentationID: UUID, orderedGroups: [[UUID]],
    skipped: Bool = false, neither: Bool = false) throws -> FlowPortfolioRanking {
    guard let presentation = state.presentations.first(where: { $0.id == presentationID }) else {
      throw FlowPortfolioError.invalid("The exact ranking presentation is unavailable.")
    }
    let flat = orderedGroups.flatMap { $0 }, available = Set(presentation.items.map(\.id))
    guard orderedGroups.allSatisfy({ !$0.isEmpty }), Set(flat).count == flat.count,
      Set(flat).isSubset(of: available), !(skipped && neither),
      (!(skipped || neither) || flat.isEmpty) else {
      throw FlowPortfolioError.invalid("Ranks must name each presented item at most once; unranked stays unknown.")
    }
    let ranking = FlowPortfolioRanking(id: UUID(), createdAt: Date(), presentationID: presentationID,
      orderedGroups: orderedGroups, skipped: skipped, neither: neither,
      supersedesID: state.rankings.last(where: { $0.presentationID == presentationID })?.id)
    var next = state; next.rankings.append(ranking); next.currentPresentationID = presentationID
    try commit(next, operation: "rankingRevised", subjectID: ranking.id)
    return ranking
  }

  package func setExcluded(candidateID: UUID, excluded: Bool) throws {
    _ = try candidate(candidateID); var next = state
    next.candidates[next.candidates.firstIndex { $0.id == candidateID }!].excluded = excluded
    try commit(next, operation: "candidateCurationChanged", subjectID: candidateID)
  }

  @discardableResult package func freezeTrainingSnapshot(id: UUID? = nil) throws -> FlowPortfolioTrainingSnapshot {
    if let id, let existing = state.trainingSnapshots.first(where: { $0.id == id }) { return existing }
    let bytes = try encode(state), document = try storage.retain(bytes, mediaType: "application/json")
    let snapshot = FlowPortfolioTrainingSnapshot(id: id ?? UUID(), createdAt: Date(), portfolioID: state.id,
      portfolioRevision: state.revision, purpose: state.purpose, document: document, contentSHA256: document.sha256)
    var next = state; next.trainingSnapshots.append(snapshot)
    try commit(next, operation: "trainingSnapshotFrozen", subjectID: snapshot.id)
    return snapshot
  }

  package func trainingDocument(snapshotID: UUID) throws -> FlowPortfolioSnapshot {
    guard let snapshot = state.trainingSnapshots.first(where: { $0.id == snapshotID }) else {
      throw FlowPortfolioError.unavailable("Training snapshot is unavailable.")
    }
    let document = try JSONDecoder().decode(FlowPortfolioSnapshot.self, from: storage.read(snapshot.document))
    try FlowPortfolioValidation.validate(document)
    guard document.id == snapshot.portfolioID, document.revision == snapshot.portfolioRevision else {
      throw FlowPortfolioError.invalid("Training snapshot identity differs from its retained content.")
    }
    return document
  }

  @discardableResult package func installFit(checkpoint: Data?, report: Data, snapshotID: UUID) throws -> FlowPortfolioFit {
    let frozen = try trainingDocument(snapshotID: snapshotID)
    if let existing = state.fits.first(where: { $0.snapshotID == snapshotID }) {
      guard existing.report.sha256 == DrawingPackageCodec.sha256(report),
        existing.checkpoint?.sha256 == checkpoint.map(DrawingPackageCodec.sha256) else {
        throw FlowPortfolioError.conflict("This frozen fit request already has a different result; create a new training snapshot for another fit.")
      }
      return existing
    }
    let decodedReport = try JSONDecoder().decode(FlowArtistFitReport.self, from: report)
    if let checkpoint {
      let decoded = try JSONDecoder().decode(FlowArtistCheckpoint.self, from: checkpoint)
      try decoded.validate()
      let includedSources = Set(frozen.sources.filter { !$0.excluded }.map(\.id))
      let includedCandidates = Set(frozen.candidates.filter { !$0.excluded && includedSources.contains($0.sourceID) }.map(\.id))
      let allowedExamples = Set(includedCandidates.map(\.uuidString)
        + frozen.pruneRevisions.filter { includedCandidates.contains($0.candidateID) }.map { $0.id.uuidString })
      let allowedRanks = Set(frozen.latestRankings.filter { !$0.skipped && !$0.neither }.map { $0.id.uuidString }
        + frozen.choices.filter { includedCandidates.contains($0.candidateID) }.map { $0.id.uuidString })
      guard Set(decoded.exampleIDs).isSubset(of: allowedExamples), Set(decoded.rankingIDs).isSubset(of: allowedRanks),
        !decoded.exampleIDs.isEmpty else { throw FlowPortfolioError.invalid("Checkpoint examples or judgments do not belong to this frozen included portfolio.") }
      guard decodedReport.checkpoint == decoded else { throw FlowPortfolioError.invalid("Checkpoint differs from its fit report.") }
    } else {
      guard decodedReport.checkpoint == nil else { throw FlowPortfolioError.invalid("Fit report has a checkpoint that was not retained.") }
    }
    let fit = FlowPortfolioFit(id: UUID(), createdAt: Date(), snapshotID: snapshotID,
      checkpoint: try checkpoint.map { try storage.retain($0, mediaType: "application/json") },
      report: try storage.retain(report, mediaType: "application/json"))
    var next = state; next.fits.append(fit)
    try commit(next, operation: "fitInstalled", subjectID: fit.id)
    return fit
  }

  package func activateModel(_ fitID: UUID?) throws {
    if let fitID {
      let checkpoint = try JSONDecoder().decode(FlowArtistCheckpoint.self, from: checkpointData(fitID: fitID))
      try checkpoint.validate()
    }
    var next = state
    next.activations.append(.init(id: UUID(), createdAt: Date(), previousFitID: state.activeFitID, fitID: fitID))
    next.activeFitID = fitID
    try commit(next, operation: fitID == nil ? "modelDeactivated" : "modelActivated", subjectID: fitID)
  }

  package func checkpointData(fitID: UUID) throws -> Data {
    guard let fit = state.fits.first(where: { $0.id == fitID }) else { throw FlowPortfolioError.unavailable("Model checkpoint is unavailable.") }
    guard let checkpoint = fit.checkpoint else { throw FlowPortfolioError.unavailable("This fit produced no deployable checkpoint; inspect its retained report.") }
    return try storage.read(checkpoint)
  }
  package func fitReportData(fitID: UUID) throws -> Data {
    guard let fit = state.fits.first(where: { $0.id == fitID }) else { throw FlowPortfolioError.unavailable("Fit report is unavailable.") }
    return try storage.read(fit.report)
  }
  package func sourceData(_ id: UUID) throws -> Data { try storage.read(source(id).image) }
  package func candidateProgram(_ id: UUID) throws -> DrawingProgram {
    let candidate = try candidate(id)
    let result = try JSONDecoder().decode(DrawingProgram.self, from: storage.read(candidate.program))
    guard result.contentHash.description == candidate.programHash, result.strokes.count == candidate.strokeCount else {
      throw FlowPortfolioError.invalid("Candidate geometry differs from its recorded identity.")
    }
    return result
  }
  package func candidateRaster(_ id: UUID) throws -> PortraitRaster {
    try JSONDecoder().decode(PortraitRaster.self, from: storage.read(candidate(id).raster))
  }
  package func candidatePreview(_ id: UUID) throws -> Data { try storage.read(candidate(id).preview) }

  package func exportPackage(candidateID: UUID, revisionID: UUID? = nil) throws -> Data {
    let candidate = try candidate(candidateID), source = try source(candidate.sourceID)
    let base = try candidateProgram(candidateID)
    let edit: FlowPortfolioPruneRevision?
    if let revisionID {
      guard let value = state.pruneRevisions.first(where: { $0.id == revisionID && $0.candidateID == candidateID }) else {
        throw FlowPortfolioError.invalid("The requested pruning revision does not belong to this drawing.")
      }
      edit = value
    } else { edit = nil }
    let removed = Set(edit?.removedIndices ?? [])
    guard removed.count < base.strokes.count else { throw FlowPortfolioError.invalid("An empty drawing remains portfolio evidence but cannot be exported for plotting.") }
    let resultID = edit?.id ?? candidateID
    let program = try DrawingProgram(id: ProgramID(resultID), fieldExtent: base.fieldExtent,
      strokes: base.strokes.enumerated().filter { !removed.contains($0.offset) }.map(\.element),
      source: DrawingSourceProvenance(kind: "portrait", sourceIdentifier: "flow-artist-v1|portfolio=\(state.id)|candidate=\(candidateID)|revision=\(resultID)"))
    struct Result: Codable { let portfolioID: UUID; let candidate: FlowPortfolioCandidate; let prune: FlowPortfolioPruneRevision?; let rootProgram: DrawingProgram }
    let result = try encode(Result(portfolioID: state.id, candidate: candidate, prune: edit, rootProgram: base))
    let input = try storage.read(candidate.raster), raster = try candidateRaster(candidateID)
    let package = try DrawingPackage(origin: .init(libraryID: state.id, captureID: source.id,
      resultID: resultID.uuidString.lowercased(), resultRecordSHA256: DrawingPackageCodec.sha256(result), programHash: program.contentHash),
      program: program, createdAt: edit?.createdAt ?? candidate.createdAt, title: source.title + " · Flow Edge",
      resultRecordJSON: result, source: DrawingPackageLibraryValidation.sourceAsset(storage.read(source.image)),
      artistInput: .init(mediaType: "application/json", bytes: input, pixelWidth: raster.width, pixelHeight: raster.height),
      artist: .init(identifier: "adaptiveplotter.flow-artist", revision: "flow-artist-v1", settingsJSON: encode(candidate.recipe)),
      preview: DrawingPackageLibraryValidation.preview(program))
    try DrawingPackageLibraryValidation.validate(package)
    return try DrawingPackageCodec.encode(package)
  }

  private func source(_ id: UUID) throws -> FlowPortfolioSource {
    guard let value = state.sources.first(where: { $0.id == id }) else { throw FlowPortfolioError.unavailable("Portfolio photograph is unavailable.") }
    return value
  }
  private func candidate(_ id: UUID) throws -> FlowPortfolioCandidate {
    guard let value = state.candidates.first(where: { $0.id == id }) else { throw FlowPortfolioError.unavailable("Portfolio drawing is unavailable.") }
    return value
  }
  private func round(_ id: UUID) throws -> FlowPortfolioRound {
    guard let value = state.rounds.first(where: { $0.id == id }) else { throw FlowPortfolioError.unavailable("Portfolio round is unavailable.") }
    return value
  }
  private func checkSlot(_ round: FlowPortfolioRound, _ slot: Int) throws {
    guard round.status == .generating, round.recipes.indices.contains(slot),
      !state.candidates.contains(where: { $0.roundID == round.id && $0.slot == slot }),
      !round.failures.contains(where: { $0.slot == slot }) else {
      throw FlowPortfolioError.conflict("This candidate slot is unavailable or already settled.")
    }
  }
  private func encode<T: Encodable>(_ value: T) throws -> Data { try DrawingPackageCodec.encoder().encode(value) }
}

private struct FlowPortfolioRandom {
  var state: UInt64
  mutating func next() -> UInt64 {
    state &+= 0x9e3779b97f4a7c15
    var value = state; value = (value ^ (value >> 30)) &* 0xbf58476d1ce4e5b9
    value = (value ^ (value >> 27)) &* 0x94d049bb133111eb
    return value ^ (value >> 31)
  }
}
