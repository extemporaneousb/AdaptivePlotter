import Darwin
import Foundation
import PlotterModel
import PortraitArtists
import PortraitCore
import DrawingLibrary

/// Authoring session and typed domain graph; the common Library owns persistence.
package actor FlowPortfolioStore {
  package nonisolated let library: DrawingLibrary
  let storage: FlowAuthoringArtifacts
  let history: FlowAuthoringHistory
  var historyFault: (@Sendable (FlowAuthoringHistoryBoundary) throws -> Void)?
  var state: FlowPortfolioSnapshot
  var committedRecords = Set<DrawingLibraryRecordKey>()
  var inFlightCandidates: [UUID: Int] = [:]
  var recentTransientRoundIDs: [UUID] = []
  var observedTransientRoundID: UUID?
  var observedTransientSourceID: UUID?
  var observedTransientOptions: PortraitAnalysisOptions?
  var temporaryDrawings: [UUID: Drawing] = [:]
  var drawingInputs: [UUID: FrozenImageInputRecord] = [:]
  var sourcePhotoRecords: [UUID: FrozenPhotoRecord] = [:]
  var publishedPhotoIDs = Set<UUID>()
  var newPhotoMetadataSources = Set<UUID>()
  var photoMetadataProjectionRevision: Int64?
  var photoMetadataProjectionRefs = Set<PhotoRef>()
  var photoMetadataProjectionValues: [PhotoRef: DrawingLibraryPhotoMetadata] = [:]
  var selectionOwner = UUID()
  package var sourceAdoptionDidPersist: (@Sendable () async -> Void)?
  var writeAdmissionActive = false
  var pendingGraphWrite: FlowPendingGraphWrite?
  var pendingRetainedWrite: FlowPendingRetainedWrite?
  var previewArtifacts: [UUID: FlowPortfolioPreviewArtifact] = [:]
  var frozenTrainingViews: [UUID: Data] = [:]
  var featureSupportingAssets: [ExchangeDigest: Data] = [:]
  var featureCapsules: [UUID: FlowPortfolioFeatureCapsule] = [:]
  package var lastFeedbackReadStatistics = FlowFeatureReadStatistics()
  let requestedPurpose: FlowPortfolioPurpose?
  package nonisolated let directory: URL

  package init(directory: URL, purpose: FlowPortfolioPurpose? = nil, library: DrawingLibrary? = nil, historyPolicy: FlowAuthoringHistoryPolicy = .init()) {
    let owner = library ?? DrawingLibrary(directoryURL: directory)
    self.library = owner
    storage = FlowAuthoringArtifacts(library: owner)
    history = FlowAuthoringHistory(directory: owner.directoryURL, policy: historyPolicy)
    self.directory = owner.directoryURL; requestedPurpose = purpose
    state = .empty(purpose: purpose ?? .artist)
  }
  package func snapshot() -> FlowPortfolioSnapshot { state }
  package func reloadCommittedState() async throws {
    try await finishPendingGraphWrite(); try await finishPendingRetainedWrite(); try await loadRecords()
    trimTransientCaches()
  }
  func commit(_ next: FlowPortfolioSnapshot, operation: String, subjectID: UUID? = nil, photoMetadata: [DrawingLibraryPhotoMetadataUpdate] = [], feedback: FlowPreparedFeedback? = nil, selectionOwner: UUID? = nil, additionalAssets: [DrawingLibraryClosureAsset] = []) async throws {
    guard next.revision == state.revision else { throw FlowPortfolioError.conflict("The authoring session changed while this action was being prepared.") }
    guard !writeAdmissionActive, pendingGraphWrite == nil, pendingRetainedWrite == nil else {
      throw FlowPortfolioError.conflict("Recover the pending Library action before accepting another action.")
    }
    let priorOwner = self.selectionOwner
    let priorSelection = FlowPortfolioSelection(state)
    let admittedOwner = (priorSelection != FlowPortfolioSelection(next) || selectionOwner != nil)
      ? (selectionOwner ?? UUID()) : priorOwner
    self.selectionOwner = admittedOwner
    do {
      var next = next; next.revision = state.revision + 1
      try FlowPortfolioValidation.validate(next)
      state = try await publishRecords(next, photoMetadata: photoMetadata, feedbackOverride: feedback, additionalAssets: additionalAssets)
      trimTransientCaches()
    } catch {
      // An exact pending publication owns this token through reconciliation.
      // A failure before admission has no such owner and must remain retryable.
      if pendingGraphWrite == nil, pendingRetainedWrite == nil,
        self.selectionOwner == admittedOwner, FlowPortfolioSelection(state) == priorSelection {
        self.selectionOwner = priorOwner
      }
      throw error
    }
  }

  static func validatedSourceAsset(_ bytes: Data) throws -> PortraitDrawingImages.Encoded {
    do { return try PortraitDrawingImages.sourceAsset(bytes) }
    catch let error as DrawingExchangeError {
      switch error {
      case .malformed(let reason), .limit(let reason): throw FlowPortfolioError.invalid(reason)
      default: throw FlowPortfolioError.invalid("The PNG or JPEG source metadata is invalid.")
      }
    }
  }

  @discardableResult package func addSource(data: Data, title: String, mediaType: String = "image/png", selecting: Bool = true) async throws -> FlowPortfolioSource {
    try requireArtifactMutationAdmission()
    defer { trimTransientCaches() }
    let asset = try Self.validatedSourceAsset(data)
    guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, title.utf8.count <= 1024 else {
      throw FlowPortfolioError.invalid("Name the imported photograph.")
    }
    let blob = try storage.retain(data, mediaType: asset.mediaType)
    var source = FlowPortfolioSource(id: UUID(), createdAt: Date(), title: title,
      image: blob, subjectID: nil, sessionID: nil)
    try attachPhoto(to: &source, data: data)
    var next = state; next.sources.append(source)
    if selecting { next.selectedSourceID = source.id
      next.currentRoundID = nil; next.currentCandidateID = nil; next.currentPruneRevisionID = nil
    }
    try await commit(next, operation: "sourceImported", subjectID: source.id)
    return source
  }

  /// Adopt the existing occurrence; publication and live Photo metadata retain
  /// their original authority. This is not an import or a new Photo revision.
  @discardableResult package func adoptExistingPhoto(_ reference: PhotoRef, selecting: Bool = true) async throws -> FlowPortfolioSource {
    if selecting { selectionOwner = UUID() }
    try requireArtifactMutationAdmission()
    if let existing = state.sources.first(where: { $0.photo == reference }) {
      if selecting { try await selectSource(existing.id) }
      return existing
    }
    let photo = try await storage.library.photo(reference)
    guard ["image/png", "image/jpeg"].contains(photo.record.original.mediaType),
      let original = photo.assets.first(where: { $0.descriptor.asset == photo.record.original }) else {
      throw FlowPortfolioError.invalid("This source can be inspected and exported, but authoring requires a supported PNG or JPEG photograph.")
    }
    let encoded = try Self.validatedSourceAsset(original.bytes)
    guard encoded.asset.descriptor.asset == photo.record.original,
      encoded.width == photo.record.width,
      encoded.height == photo.record.height else { throw DrawingExchangeError.mismatchedParent }
    let metadata = try await storage.library.photoMetadata(reference)
    // Actor reentrancy during exact loading must not create a second navigation
    // occurrence for an already-adopted Photo.
    if let existing = state.sources.first(where: { $0.photo == reference }) {
      if selecting { try await selectSource(existing.id) }
      return existing
    }
    let blob = FlowPortfolioBlob(sha256: photo.record.original.object.description,
      byteCount: original.bytes.count, mediaType: photo.record.original.mediaType)
    let createdAt: Date
    switch photo.acquired ?? photo.imported {
    case .known(let timestamp, _):
      let formatter = ISO8601DateFormatter()
      formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
      let fractional = timestamp.wallTime.flatMap { formatter.date(from: $0) }
      formatter.formatOptions = [.withInternetDateTime]
      createdAt = fractional ?? timestamp.wallTime.flatMap { formatter.date(from: $0) } ?? Date()
    default: createdAt = Date()
    }
    var source = FlowPortfolioSource(id: UUID(), createdAt: createdAt, title: metadata.title ?? "Photo",
      image: blob, subjectID: metadata.subjectID, sessionID: metadata.sessionID)
    source.photo = reference; source.excluded = metadata.excluded
    sourcePhotoRecords[source.id] = photo; publishedPhotoIDs.insert(source.id)
    storage.markPublished([blob])
    var next = state; next.sources.append(source)
    if selecting { next.selectedSourceID = source.id
      next.currentRoundID = nil; next.currentCandidateID = nil; next.currentPruneRevisionID = nil
    }
    try await commit(next, operation: "existingPhotoAdopted", subjectID: source.id)
    return source
  }

  package func selectSource(_ id: UUID) async throws {
    selectionOwner = UUID()
    _ = try source(id)
    var next = state; next.selectedSourceID = id
    let options = next.sources.first(where: { $0.id == id })?.authoringOptions
    next.currentRoundID = next.rounds.last(where: { $0.sourceID == id && (options == nil || $0.analysisOptions == options) })?.id
    next.currentCandidateID = next.choices.last(where: { $0.roundID == next.currentRoundID })?.candidateID
    next.currentPruneRevisionID = next.currentCandidateID.flatMap { next.latestPrune(candidateID: $0)?.id }
    try await commit(next, operation: "sourceSelected", subjectID: id)
  }

  /// Browsing a historical round supplies no preference judgment.
  package func selectRound(_ id: UUID) async throws {
    selectionOwner = UUID()
    let value = try round(id)
    var next = state; next.selectedSourceID = value.sourceID; next.currentRoundID = id
    next.currentCandidateID = next.choices.last(where: { $0.roundID == id })?.candidateID
    next.currentPruneRevisionID = next.currentCandidateID.flatMap { next.latestPrune(candidateID: $0)?.id }
    try await commit(next, operation: "roundSelected", subjectID: id)
  }

  package func setSourceGroups(sourceID: UUID, subjectID: String?, sessionID: String?, excluded: Bool? = nil) async throws {
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
    guard let ref = next.sources[index].photo else { throw FlowPortfolioError.unavailable("Photo reference is unavailable.") }
    try await commit(next, operation: "sourceGroupsDeclared", subjectID: sourceID, photoMetadata: [.init(reference: ref, patch: .init(subjectID: .set(subject), sessionID: .set(session), excluded: excluded))])
  }

  package func setSourceExcluded(sourceID: UUID, excluded: Bool) async throws {
    _ = try source(sourceID); var next = state
    next.sources[next.sources.firstIndex { $0.id == sourceID }!].excluded = excluded
    guard let ref = next.sources.first(where: { $0.id == sourceID })?.photo else { throw FlowPortfolioError.unavailable("Photo reference is unavailable.") }
    try await commit(next, operation: "sourceCurationChanged", subjectID: sourceID, photoMetadata: [.init(reference: ref, patch: .init(excluded: excluded))])
  }

  package func setAuthoringOptions(sourceID: UUID, options: PortraitAnalysisOptions) async throws {
    selectionOwner = UUID()
    _ = try source(sourceID)
    var next = state
    next.sources[next.sources.firstIndex { $0.id == sourceID }!].authoringOptions = options
    // A changed region is a new input, never an implicit refinement of old pixels.
    next.currentRoundID = nil; next.currentCandidateID = nil; next.currentPruneRevisionID = nil
    try await commit(next, operation: "sourceRegionSelected", subjectID: sourceID)
  }

  @discardableResult package func beginRound(sourceID: UUID, recipes: [FlowArtistRecipe],
    parentCandidateID: UUID? = nil, modelID: String? = nil, seed: UInt64 = 0,
    analysisOptions: PortraitAnalysisOptions = .init(), explorationDepth: Int? = nil,
    refinementRadius: Double? = nil, explorationPolicy: String? = nil) async throws -> FlowPortfolioRound {
    _ = try source(sourceID)
    guard (1...24).contains(recipes.count), recipes.allSatisfy({ $0.values.allSatisfy { $0.isFinite && (0...1).contains($0) } }) else {
      throw FlowPortfolioError.invalid("A round requires one to twenty-four bounded Flow Edge recipes.")
    }
    if let parentCandidateID, try candidate(parentCandidateID).sourceID != sourceID {
      throw FlowPortfolioError.invalid("A refinement must retain its parent's source photograph.")
    }
    if explorationPolicy != nil, let parentCandidateID {
      let parent = try candidate(parentCandidateID)
      guard try self.round(parent.roundID).analysisOptions == analysisOptions else {
        throw FlowPortfolioError.invalid("The refinement parent belongs to a different source region.")
      }
    }
    let round = FlowPortfolioRound(id: UUID(), createdAt: Date(), sourceID: sourceID,
      parentCandidateID: parentCandidateID, recipes: recipes, analysisOptions: analysisOptions, seed: seed, modelID: modelID,
      status: .generating, candidateIDs: [], displayedCandidateIDs: [], recommendedCandidateID: nil, failures: [], explorationDepth: explorationDepth,
      refinementRadius: refinementRadius, explorationPolicy: explorationPolicy)
    var next = state; next.rounds.append(round); next.selectedSourceID = sourceID
    next.currentRoundID = round.id; next.currentCandidateID = parentCandidateID
    next.currentPruneRevisionID = parentCandidateID.flatMap { next.latestPrune(candidateID: $0)?.id }
    try await commit(next, operation: "roundRequested", subjectID: round.id)
    return round
  }

  @discardableResult package func completeCandidate(roundID: UUID, slot: Int,
    production: DrawingProduction<PortraitRenderResult>, previewPNG: Data) async throws -> FlowPortfolioCandidate {
    try requireArtifactMutationAdmission()
    defer { trimTransientCaches() }
    try admitTemporaryDrawing(production.drawing, input: production.artifacts.drawingInput)
    let program = production.drawing.program, raster = production.artifacts.raster
    let round = try round(roundID); try checkSlot(round, slot)
    guard program.source.kind == "portrait", !program.strokes.isEmpty,
      program.strokes.count <= DrawingArtifactLimits.maximumStrokes else {
      throw FlowPortfolioError.invalid("A candidate must be a bounded nonempty portrait drawing.")
    }
    let previewAsset = try Self.validatedSourceAsset(previewPNG)
    guard previewAsset.mediaType == "image/png" else { throw FlowPortfolioError.invalid("Candidate preview must be PNG.") }
    let rasterBytes = try encode(raster)
    try admitTemporaryArtifacts([rasterBytes, previewPNG])
    var result = FlowPortfolioCandidate(id: UUID(), createdAt: Date(), sourceID: round.sourceID,
      roundID: roundID, slot: slot, parentCandidateID: round.parentCandidateID, recipe: round.recipes[slot],
      modelID: round.modelID,
      raster: try storage.retain(rasterBytes, mediaType: "application/json"),
      preview: try storage.retain(previewPNG, mediaType: "image/png"),
      programHash: program.contentHash.description, strokeCount: program.strokes.count)
    try historyFault?(.beforeWrite)
    let preparedHistory = try history.prepare(candidate: result, source: source(round.sourceID), round: round,
      drawing: production.drawing, input: production.artifacts.drawingInput, raster: rasterBytes, preview: previewPNG, issuer: state.id)
    try historyFault?(.afterParts); try historyFault?(.beforePublish)
    result.authoringClosure = preparedHistory.reference; result.authoringClosureLocation = preparedHistory.location
    temporaryDrawings[result.id] = production.drawing
    if let input = production.artifacts.drawingInput { drawingInputs[result.id] = input }
    var next = state; next.candidates.append(result)
    next.rounds[next.rounds.firstIndex { $0.id == roundID }!].candidateIDs.append(result.id)
    try await commit(next, operation: "candidateCompleted", subjectID: result.id, additionalAssets: preparedHistory.assets)
    return result
  }

  package func failCandidate(roundID: UUID, slot: Int, message: String) async throws {
    let round = try round(roundID); try checkSlot(round, slot)
    guard !message.isEmpty, message.utf8.count <= 8192 else { throw FlowPortfolioError.invalid("Generation failure needs a bounded explanation.") }
    var next = state
    next.rounds[next.rounds.firstIndex { $0.id == roundID }!].failures.append(
      .init(slot: slot, message: message, recordedAt: Date()))
    try await commit(next, operation: "candidateFailed", subjectID: roundID)
  }

  package func finishRound(_ id: UUID, cancelled: Bool = false, displayOrder: [UUID]? = nil,
    recommendedCandidateID: UUID? = nil, recommendedRemovedIndices: [Int]? = nil) async throws {
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
    next.rounds[index].recommendedRemovedIndices = recommendedRemovedIndices
    try await commit(next, operation: cancelled ? "roundCancelled" : "roundCompleted", subjectID: id)
  }

  package func markInterruptedRounds() async throws {
    guard state.rounds.contains(where: { $0.status == .generating }) else { return }
    var next = state
    for index in next.rounds.indices where next.rounds[index].status == .generating { next.rounds[index].status = .interrupted }
    try await commit(next, operation: "pendingRoundsRecovered")
  }

  package func chooseCandidate(_ id: UUID, offeredItems frozenItems: [FlowPortfolioPresentationItem]? = nil) async throws {
    selectionOwner = UUID()
    let value = try candidate(id), round = try round(value.roundID)
    let declared = round.displayedCandidateIDs.isEmpty ? round.candidateIDs : round.displayedCandidateIDs
    let pinned = frozenItems?.map(\.candidateID) ?? declared
    for candidateID in pinned { pinCandidate(candidateID) }
    defer { for candidateID in pinned { unpinCandidate(candidateID) } }
    if let reason = try await candidateUnavailableReason(id) { throw FlowPortfolioError.invalid(reason) }
    var offered: [UUID] = []
    if let frozenItems {
      offered = frozenItems.map(\.candidateID)
      for item in frozenItems {
        let candidate = try candidate(item.candidateID)
        guard item.removedIndices.count < candidate.strokeCount else {
          throw FlowPortfolioError.invalid("An empty drawing was not an enabled exploration choice.")
        }
        if let reason = try await candidateUnavailableReason(item.candidateID) { throw FlowPortfolioError.invalid(reason) }
      }
    } else {
      for candidateID in declared {
        let candidate = try candidate(candidateID)
        if (state.latestPrune(candidateID: candidateID)?.removedIndices.count ?? 0) < candidate.strokeCount,
          try await candidateUnavailableReason(candidateID) == nil { offered.append(candidateID) }
      }
    }
    guard Set(offered).isSubset(of: Set(round.candidateIDs)), Set(offered).count == offered.count,
      offered.contains(id) else {
      throw FlowPortfolioError.invalid("The offered drawings must be enabled members of the selected round.")
    }
    let currentItems = try offered.map { offeredID -> FlowPortfolioPresentationItem in
      let value = try candidate(offeredID), edit = state.latestPrune(candidateID: offeredID)
      return .init(id: edit?.id ?? offeredID, candidateID: offeredID, revisionID: edit?.id,
        sourceID: value.sourceID, removedIndices: edit?.removedIndices ?? [])
    }
    let items = frozenItems ?? currentItems
    guard items.map(\.candidateID) == offered, items.contains(where: { $0.candidateID == id }) else {
      throw FlowPortfolioError.invalid("The exploration choice differs from the exact offered set.")
    }
    // Validation below verifies every frozen revision and its original mask.
    let selectedItem = items.first(where: { $0.candidateID == id })!.id
    let alreadyRecorded = state.choices.contains {
      $0.roundID == round.id && $0.selectedItemID == selectedItem && $0.offeredItems == items
        && $0.purpose == "refine-or-prune"
    }
    var next = state
    if !alreadyRecorded {
      next.choices.append(.init(id: UUID(), createdAt: Date(), roundID: round.id, candidateID: id,
        offeredCandidateIDs: offered, selectedItemID: selectedItem, offeredItems: items, purpose: "refine-or-prune"))
    }
    next.selectedSourceID = value.sourceID
    next.currentRoundID = value.roundID; next.currentCandidateID = id
    next.currentPruneRevisionID = next.latestPrune(candidateID: id)?.id
    if !alreadyRecorded {
      for item in items {
        _ = try await featureCapsule(candidateID: item.candidateID)
        if let revision = item.revisionID { _ = try await featureCapsule(candidateID: item.candidateID, revisionID: revision) }
      }
    }
    let prepared = try await prepareDrawing(candidateID: id, revision: next.latestPrune(candidateID: id), next: &next)
    try await commitPrepared(prepared, next: next)
  }

  @discardableResult package func applyPrune(candidateID: UUID, action: FlowPruneAction,
    indices: [Int] = [], modelID: String? = nil, inheritedFromRevisionID: UUID? = nil,
    probabilities: [Double]? = nil, threshold: Double? = nil, policy: String? = nil) async throws -> FlowPortfolioPruneRevision {
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
    if action != .modelProposal && action != .inheritedSelection {
      _ = try await featureCapsule(candidateID: candidateID)
      _ = try await captureFeatures(candidateID: candidateID, id: revision.id, removedIndices: revision.removedIndices)
    }
    var next = state; next.pruneRevisions.append(revision)
    if action != .modelProposal && action != .inheritedSelection {
      next.currentCandidateID = candidateID; next.selectedSourceID = value.sourceID
      next.currentRoundID = value.roundID; next.currentPruneRevisionID = id
    }
    if action != .modelProposal && action != .inheritedSelection && removed.count < value.strokeCount {
      let prepared = try await prepareDrawing(candidateID: candidateID, revision: revision, next: &next)
      try await commitPrepared(prepared, next: next)
    } else { try await commit(next, operation: "prune." + action.rawValue, subjectID: revision.id) }
    return revision
  }

  @discardableResult package func presentRanking(scope: FlowRankingScope, count: Int = 6,
    seed: UInt64) async throws -> FlowPortfolioPresentation {
    guard (2...24).contains(count) else { throw FlowPortfolioError.invalid("Ranking sets contain two to twenty-four drawings.") }
    let permitted: [FlowPortfolioCandidate]
    switch scope {
    case .portfolio: permitted = state.candidates
    case .candidate(let id): permitted = [try candidate(id)]
    case .source(let id):
      _ = try source(id)
      let aliases = state.photoSourceIDs(for: id)
      permitted = state.candidates.filter { aliases.contains($0.sourceID) }
    case .round(let id): _ = try round(id); permitted = state.candidates.filter { $0.roundID == id }
    }
    var items: [FlowPortfolioPresentationItem] = []
    let sourceIDs = Set(state.sources.filter { !$0.excluded }.map(\.id))
    let revisions = Dictionary(grouping: state.pruneRevisions, by: \.candidateID)
    for candidate in permitted where !candidate.excluded && sourceIDs.contains(candidate.sourceID) {
      do {
        items.append(.init(id: candidate.id, candidateID: candidate.id, revisionID: nil, sourceID: candidate.sourceID, removedIndices: []))
      }
      for edit in revisions[candidate.id] ?? [] {
        do {
          items.append(.init(id: edit.id, candidateID: candidate.id, revisionID: edit.id, sourceID: candidate.sourceID, removedIndices: edit.removedIndices))
        }
      }
    }
    guard items.count >= 2 else { throw FlowPortfolioError.unavailable("Create at least two distinct drawing versions before ranking.") }
    var random = FlowPortfolioRandom(state: seed)
    for index in stride(from: items.count - 1, through: 1, by: -1) {
      items.swapAt(index, Int(random.next() % UInt64(index + 1)))
    }
    if count == 2 {
      func pairKey(_ a: String, _ b: String) -> String { [a, b].sorted().joined(separator: "::") }
      let presentations = Dictionary(uniqueKeysWithValues: state.presentations.map { ($0.id, $0) })
      var reviewed = Set<String>()
      for rank in state.latestRankings {
        guard let shown = presentations[rank.presentationID] else { continue }
        let ranked = rank.skipped || rank.neither ? Set(shown.items.map(\.id)) : Set(rank.orderedGroups.flatMap { $0 })
        let versions = shown.items.filter { ranked.contains($0.id) }.map { $0.id.uuidString }
        for a in versions.indices { for b in versions.indices where b > a { reviewed.insert(pairKey(versions[a], versions[b])) } }
      }
      var pair: [FlowPortfolioPresentationItem]?
      search: for a in items.indices { for b in items.indices where b > a {
        if !reviewed.contains(pairKey(items[a].id.uuidString, items[b].id.uuidString)) {
          pair = [items[a], items[b]]; break search
        }
      } }
      guard let pair else { throw FlowPortfolioError.unavailable("Every available pair here has a current ranking. Reopen a previous comparison to revise it, or create another drawing version.") }
      items = pair
    }
    let presentation = FlowPortfolioPresentation(id: UUID(), createdAt: Date(), scope: scope,
      seed: seed, items: Array(items.prefix(count)))
    var next = state; next.presentations.append(presentation); next.currentPresentationID = presentation.id
    try await commit(next, operation: "rankingPresented", subjectID: presentation.id)
    return presentation
  }

  /// Freeze the actual current panel: one latest displayed version per included
  /// candidate. Historical intermediate masks belong to the random version flow.
  @discardableResult package func presentRoundRanking(_ roundID: UUID, seed: UInt64) async throws -> FlowPortfolioPresentation {
    let round = try round(roundID)
    let order = round.displayedCandidateIDs.isEmpty ? round.candidateIDs : round.displayedCandidateIDs
    let values = Dictionary(uniqueKeysWithValues: state.candidates.map { ($0.id, $0) })
    let includedSources = Set(state.sources.filter { !$0.excluded }.map(\.id))
    var items: [FlowPortfolioPresentationItem] = order.compactMap { id in
      guard let candidate = values[id], !candidate.excluded, includedSources.contains(candidate.sourceID) else { return nil }
      let revision = state.latestPrune(candidateID: id)
      return .init(id: revision?.id ?? id, candidateID: id, revisionID: revision?.id,
        sourceID: candidate.sourceID, removedIndices: revision?.removedIndices ?? [])
    }
    guard items.count >= 2 else { throw FlowPortfolioError.unavailable("The current panel needs at least two included drawings to compare.") }
    var random = FlowPortfolioRandom(state: seed)
    for index in stride(from: items.count - 1, through: 1, by: -1) { items.swapAt(index, Int(random.next() % UInt64(index + 1))) }
    let presentation = FlowPortfolioPresentation(id: UUID(), createdAt: Date(), scope: .round(roundID), seed: seed, items: items)
    var next = state; next.presentations.append(presentation); next.currentPresentationID = presentation.id
    try await commit(next, operation: "currentPanelPresented", subjectID: presentation.id)
    return presentation
  }

  package func selectPresentation(_ id: UUID) async throws {
    guard state.presentations.contains(where: { $0.id == id }) else { throw FlowPortfolioError.unavailable("Ranking presentation is unavailable.") }
    var next = state; next.currentPresentationID = id
    try await commit(next, operation: "rankingSelected", subjectID: id)
  }

  @discardableResult package func recordRanking(presentationID: UUID, orderedGroups: [[UUID]],
    skipped: Bool = false, neither: Bool = false) async throws -> FlowPortfolioRanking {
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
    for item in presentation.items {
      _ = try await featureCapsule(candidateID: item.candidateID)
      if let revision = item.revisionID { _ = try await featureCapsule(candidateID: item.candidateID, revisionID: revision) }
    }
    var next = state; next.rankings.append(ranking); next.currentPresentationID = presentationID
    try await commit(next, operation: "rankingRevised", subjectID: ranking.id)
    return ranking
  }

  package func setExcluded(candidateID: UUID, excluded: Bool) async throws {
    _ = try candidate(candidateID); var next = state
    next.candidates[next.candidates.firstIndex { $0.id == candidateID }!].excluded = excluded
    try await commit(next, operation: "candidateCurationChanged", subjectID: candidateID)
  }

  @discardableResult package func installFit(checkpoint: Data?, report: Data, snapshotID: UUID) async throws -> FlowPortfolioFit {
    _ = try await trainingDocument(snapshotID: snapshotID)
    let frozenInputs = try await trainingInputs(snapshotID: snapshotID)
    if let existing = state.fits.first(where: { $0.snapshotID == snapshotID }) {
      guard existing.report.sha256 == DrawingArtifactCoding.sha256(report),
        existing.checkpoint?.sha256 == checkpoint.map(DrawingArtifactCoding.sha256) else {
        throw FlowPortfolioError.conflict("This frozen fit request already has a different result; create a new training snapshot for another fit.")
      }
      return existing
    }
    let decodedReport = try JSONDecoder().decode(FlowArtistFitReport.self, from: report)
    if let checkpoint {
      let decoded = try JSONDecoder().decode(FlowArtistCheckpoint.self, from: checkpoint)
      try decoded.validateArchive()
      guard Set(decoded.exampleIDs) == Set(frozenInputs.examples.map(\.id)),
        Set(decoded.rankingIDs) == Set(frozenInputs.rankings.map(\.id)), !decoded.exampleIDs.isEmpty,
        decoded.seed == frozenInputs.seed, decoded.fitConfiguration == frozenInputs.configuration,
        decoded.holdoutGroupIDs == frozenInputs.holdoutGroupIDs,
        decoded.sourceGroupIDs == Set(frozenInputs.examples.map(\.sourceGroupID)).sorted() else {
        throw FlowPortfolioError.invalid("Checkpoint inputs/configuration differ from the exact frozen task.")
      }
      guard decodedReport.checkpoint == decoded else { throw FlowPortfolioError.invalid("Checkpoint differs from its fit report.") }
    } else {
      guard decodedReport.checkpoint == nil else { throw FlowPortfolioError.invalid("Fit report has a checkpoint that was not retained.") }
    }
    let fit = FlowPortfolioFit(id: UUID(), createdAt: Date(), snapshotID: snapshotID,
      checkpoint: try checkpoint.map { try storage.retain($0, mediaType: "application/json") },
      report: try storage.retain(report, mediaType: "application/json"))
    var next = state; next.fits.append(fit)
    try await commit(next, operation: "fitInstalled", subjectID: fit.id)
    return fit
  }

  package func activateModel(_ fitID: UUID?) async throws {
    if let fitID {
      let checkpoint = try JSONDecoder().decode(FlowArtistCheckpoint.self, from: await checkpointData(fitID: fitID))
      try checkpoint.validateForInference()
    }
    var next = state
    next.activations.append(.init(id: UUID(), createdAt: Date(), previousFitID: state.activeFitID, fitID: fitID))
    next.activeFitID = fitID
    try await commit(next, operation: fitID == nil ? "modelDeactivated" : "modelActivated", subjectID: fitID)
  }

  package func checkpointData(fitID: UUID) async throws -> Data {
    guard let fit = state.fits.first(where: { $0.id == fitID }) else { throw FlowPortfolioError.unavailable("Model checkpoint is unavailable.") }
    guard let checkpoint = fit.checkpoint else { throw FlowPortfolioError.unavailable("This fit produced no deployable checkpoint; inspect its retained report.") }
    return try await storage.read(checkpoint)
  }
  package func fitReportData(fitID: UUID) async throws -> Data {
    guard let fit = state.fits.first(where: { $0.id == fitID }) else { throw FlowPortfolioError.unavailable("Fit report is unavailable.") }
    return try await storage.read(fit.report)
  }
  package func sourceData(_ id: UUID) async throws -> Data { try await storage.read(source(id).image) }
  package func candidateProgram(_ id: UUID) async throws -> DrawingProgram { try await candidateDrawing(id).program }
  /// Exact read only: a private history closure is not promoted into the gallery.
  package func candidateDrawing(_ id: UUID) async throws -> Drawing {
    let value = try candidate(id)
    if let reference = value.drawing { return try await storage.library.drawing(reference) }
    pinCandidate(id); defer { unpinCandidate(id) }
    try await restoreHistoryCandidate(id)
    if let drawing = temporaryDrawings[id] { return drawing }
    if let drawing = try await historicalDrawing(id) { return drawing }
    throw FlowPortfolioError.unavailable("This legacy drawing has no retained geometry or authoring history closure.")
  }
  package func candidateInput(_ id: UUID) async throws -> FrozenImageInputRecord? {
    pinCandidate(id); defer { unpinCandidate(id) }
    let drawing = try await candidateDrawing(id)
    if let input = drawingInputs[id] { return input }
    if case .present(let reference) = drawing.input { return try await library.input(reference) }
    return nil
  }
  package func candidateRaster(_ id: UUID) async throws -> PortraitRaster {
    if let historical = try await historicalCandidate(id) {
      return try JSONDecoder().decode(PortraitRaster.self, from: await historicalBytes(historical.raster))
    }
    let value = try candidate(id)
    if !storage.isAvailable(value.raster), value.authoringClosure != nil {
      return try JSONDecoder().decode(PortraitRaster.self, from: await history.bytes(candidate: value, source: source(value.sourceID), round: round(value.roundID), preview: false, library: library))
    }
    return try JSONDecoder().decode(PortraitRaster.self, from: await storage.read(value.raster))
  }
  package func candidatePreview(_ id: UUID) async throws -> Data {
    if let historical = try await historicalCandidate(id) { return try await historicalBytes(historical.preview) }
    let value = try candidate(id)
    if !storage.isAvailable(value.preview), value.authoringClosure != nil {
      return try await history.bytes(candidate: value, source: source(value.sourceID), round: round(value.roundID), preview: true, library: library)
    }
    return try await storage.read(value.preview)
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
  private func encode<T: Encodable>(_ value: T) throws -> Data { try DrawingArtifactCoding.encoder().encode(value) }
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
