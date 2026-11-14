import Foundation
import PortraitCore

/// Integrity is independent of the UI. Corrupt ancestry cannot become a new
/// writable empty portfolio or invented training supervision.
enum FlowPortfolioValidation {
  static func validHash(_ value: String) -> Bool { (try? ExchangeDigest(value)) != nil }
  static func validate(_ state: FlowPortfolioSnapshot) throws {
    func require(_ valid: Bool, _ message: String) throws {
      guard valid else { throw FlowPortfolioError.invalid(message) }
    }
    func unique<T: Identifiable>(_ values: [T]) -> Bool { Set(values.map(\.id)).count == values.count }
    try require(state.schemaVersion == 2 && state.revision >= 0 && state.createdAt.timeIntervalSince1970.isFinite,
      "Unsupported portfolio identity or schema.")
    try require(unique(state.sources) && unique(state.rounds) && unique(state.candidates)
      && unique(state.choices) && unique(state.pruneRevisions) && unique(state.presentations)
      && unique(state.rankings) && unique(state.trainingSnapshots) && unique(state.fits) && unique(state.activations),
      "Portfolio identities must be unique.")
    let sources = Dictionary(uniqueKeysWithValues: state.sources.map { ($0.id, $0) })
    let rounds = Dictionary(uniqueKeysWithValues: state.rounds.map { ($0.id, $0) })
    let candidates = Dictionary(uniqueKeysWithValues: state.candidates.map { ($0.id, $0) })
    let edits = Dictionary(uniqueKeysWithValues: state.pruneRevisions.map { ($0.id, $0) })
    let presentations = Dictionary(uniqueKeysWithValues: state.presentations.map { ($0.id, $0) })
    let captureIDs = state.sources.compactMap { $0.captureProvenance?.photoID }
    try require(Set(captureIDs).count == captureIDs.count, "Captured photo identities must be unique.")
    for source in state.sources {
      try require(!source.title.isEmpty && source.title.utf8.count <= 1024, "Portfolio source title is invalid.")
      try require(source.image.mediaType == "image/png" || source.image.mediaType == "image/jpeg", "Source encoding is unsupported.")
      if let capture = source.captureProvenance {
        try require(capture.imageSHA256 == source.image.sha256 && capture.capturedAt.timeIntervalSince1970.isFinite
          && capture.label.utf8.count <= 1024, "Captured photo provenance differs from its image or has invalid metadata.")
        let bytes = try DrawingArtifactCoding.encoder().encode(capture)
        try require(bytes.count <= 64 * 1024, "Captured photo provenance is too large.")
        if let selection = capture.selectionProvenance {
          try require(selection.capturedFrameCount >= 0 && selection.evaluatedFrameCount >= 0
            && selection.evaluatedFrameCount <= selection.capturedFrameCount
            && (selection.selectedSharpness.map { $0.isFinite && $0 >= 0 } ?? true)
            && (selection.selectedMeanLuminance.map { $0.isFinite && (0...1).contains($0) } ?? true)
            && (selection.selectedClippedFraction.map { $0.isFinite && (0...1).contains($0) } ?? true),
            "Captured frame selection measurements are invalid.")
        }
      }
      if let provenance = source.importProvenance {
        try require(!provenance.collectionID.isEmpty && provenance.collectionID.utf8.count <= 256
          && !provenance.entryID.isEmpty && provenance.entryID.utf8.count <= 256
          && provenance.manifest.mediaType == "application/json", "Photo import provenance is invalid.")
      }
    }
    for round in state.rounds {
      try require(sources[round.sourceID] != nil && (1...24).contains(round.recipes.count), "Round has a missing source or invalid recipes.")
      if let parent = round.parentCandidateID {
        try require(candidates[parent]?.sourceID == round.sourceID && (candidates[parent]?.createdAt ?? .distantFuture) <= round.createdAt,
          "Refinement parent must be an earlier candidate of the same source.")
      }
      if let depth = round.explorationDepth { try require(depth >= 0 && depth <= 10_000, "Exploration depth is invalid.") }
      if let radius = round.refinementRadius { try require(radius.isFinite && (0.015...1).contains(radius), "Refinement radius is invalid.") }
      if let policy = round.explorationPolicy {
        try require(policy == "contracting-neighborhood-v1" && round.explorationDepth != nil,
          "Exploration policy is unavailable.")
        if let parent = round.parentCandidateID.flatMap({ candidates[$0] }) {
          let parentRound = rounds[parent.roundID]
          try require(parentRound?.analysisOptions == round.analysisOptions,
            "Refinement parent belongs to a different source region.")
          let depth = min(10_000, (parentRound?.explorationDepth ?? 0) + 1)
          let radius = max(0.015, 0.06 * pow(0.85, Double(depth - 1)))
          try require(round.explorationDepth == depth && round.refinementRadius == radius,
            "Refinement differs from its frozen contracting neighborhood policy.")
        } else {
          try require(round.explorationDepth == 0 && round.refinementRadius == nil,
            "Broad exploration must reset its neighborhood.")
        }
      }
      let owned = state.candidates.filter { $0.roundID == round.id }
      try require(Set(round.candidateIDs) == Set(owned.map(\.id)) && round.candidateIDs.count == owned.count,
        "Round's candidate list differs from its committed results.")
      let slots = owned.map(\.slot) + round.failures.map(\.slot)
      try require(Set(slots).count == slots.count && slots.allSatisfy { round.recipes.indices.contains($0) },
        "Each requested candidate slot can settle exactly once.")
      if round.status == .completed { try require(slots.count == round.recipes.count, "Completed round has unsettled requests.") }
      if !round.displayedCandidateIDs.isEmpty {
        try require(Set(round.displayedCandidateIDs) == Set(round.candidateIDs)
          && round.displayedCandidateIDs.count == round.candidateIDs.count, "Round display order differs from its candidates.")
      }
      if let recommended = round.recommendedCandidateID {
        try require(round.displayedCandidateIDs.contains(recommended), "Recommended candidate was not in the displayed round.")
      }
      if let mask = round.recommendedRemovedIndices {
        guard let id = round.recommendedCandidateID, let candidate = candidates[id] else {
          throw FlowPortfolioError.invalid("A scored recommendation mask requires its exact candidate.")
        }
        try require(mask == Set(mask).sorted() && mask.allSatisfy { (0..<candidate.strokeCount).contains($0) }
          && mask.count < candidate.strokeCount, "Scored recommendation membership is invalid or empty.")
      }
    }
    for candidate in state.candidates {
      guard let round = rounds[candidate.roundID] else { throw FlowPortfolioError.invalid("Candidate round is missing.") }
      try require(candidate.sourceID == round.sourceID && candidate.parentCandidateID == round.parentCandidateID
        && round.recipes.indices.contains(candidate.slot) && candidate.recipe == round.recipes[candidate.slot]
        && candidate.modelID == round.modelID && (1...DrawingArtifactLimits.maximumStrokes).contains(candidate.strokeCount),
        "Candidate differs from its immutable generation request.")
      try require(FlowPortfolioValidation.validHash(candidate.programHash), "Candidate program identity is invalid.")
      if let closure = candidate.authoringClosure {
        try require(validHash(closure.sha256) && (1...128 * 1024).contains(closure.byteCount) && closure.mediaType == "application/json", "Authoring history manifest reference is invalid.")
      }
      if let title = candidate.title { try require(!title.isEmpty && title.utf8.count <= 1024, "Drawing name is invalid.") }
    }
    for choice in state.choices {
      try require(candidates[choice.candidateID]?.roundID == choice.roundID
        && Set(choice.offeredCandidateIDs).count == choice.offeredCandidateIDs.count
        && choice.offeredCandidateIDs.contains(choice.candidateID)
        && choice.offeredCandidateIDs.allSatisfy { candidates[$0]?.roundID == choice.roundID },
        "Choice must refer to the exact offered round.")
      try require(choice.offeredItems.map(\.candidateID) == choice.offeredCandidateIDs,
        "Choice must preserve its exact ordered presentation.")
      for item in choice.offeredItems {
        try require(candidates[item.candidateID]?.sourceID == item.sourceID,
          "Choice source is inconsistent.")
        if let revision = item.revisionID {
          try require(item.id == revision && edits[revision]?.candidateID == item.candidateID
            && edits[revision]?.removedIndices == item.removedIndices, "Choice differs from the shown pruning revision.")
        } else { try require(item.id == item.candidateID && item.removedIndices.isEmpty, "Choice base drawing is inconsistent.") }
      }
      try require(choice.offeredItems.contains { $0.id == choice.selectedItemID && $0.candidateID == choice.candidateID },
        "Selected item does not identify the chosen exact drawing version.")
    }
    var lastEdit: [UUID: FlowPortfolioPruneRevision] = [:]
    var applied: [UUID: FlowPortfolioPruneRevision] = [:]
    for edit in state.pruneRevisions {
      guard let candidate = candidates[edit.candidateID] else { throw FlowPortfolioError.invalid("Pruning candidate is missing.") }
      let prior = lastEdit[edit.candidateID]
      try require(edit.parentRevisionID == prior?.id, "Pruning must extend its exact current revision.")
      let affected = Set(edit.affectedIndices), removed = Set(edit.removedIndices)
      try require(edit.affectedIndices == affected.sorted() && edit.removedIndices == removed.sorted()
        && affected.union(removed).allSatisfy { (0..<candidate.strokeCount).contains($0) },
        "Pruning indices must identify original strokes in order.")
      var expected = Set(prior?.removedIndices ?? []), undo = prior?.undoOperationIDs ?? [], redo = prior?.redoOperationIDs ?? []
      switch edit.action {
      case .remove:
        try require(edit.modelID == nil && edit.operationID == nil && !affected.isEmpty && affected.isDisjoint(with: expected), "Invalid human removal.")
        expected.formUnion(affected); undo.append(edit.id); redo = []
      case .restore:
        try require(edit.modelID == nil && edit.operationID == nil && !affected.isEmpty && affected.isSubset(of: expected), "Invalid human restoration.")
        expected.subtract(affected); undo.append(edit.id); redo = []
      case .modelProposal:
        try require(prior == nil && edit.modelID?.isEmpty == false && edit.operationID == nil, "Generated pruning must remain an attributed initial proposal.")
        guard let probabilities = edit.probabilities, probabilities.count == candidate.strokeCount,
          probabilities.allSatisfy({ $0.isFinite && (0...1).contains($0) }), let threshold = edit.threshold,
          threshold.isFinite, (0.5...1).contains(threshold), edit.policy == "threshold-keep-one-v1" else {
          throw FlowPortfolioError.invalid("Generated pruning has no exact inference receipt.")
        }
        var proposed = Set(probabilities.indices.filter { probabilities[$0] >= threshold })
        if proposed.count == probabilities.count, let keep = probabilities.indices.min(by: { probabilities[$0] < probabilities[$1] }) { proposed.remove(keep) }
        try require(proposed == affected, "Generated mask differs from its retained probabilities.")
        expected = affected; undo = []; redo = []
      case .inheritedSelection:
        try require(prior == nil && edit.modelID == nil, "Inherited selection must be the initial attributed mask.")
        if let inheritedID = edit.inheritedFromRevisionID {
          guard let inherited = applied[inheritedID], let parent = candidates[inherited.candidateID] else {
            throw FlowPortfolioError.invalid("Inherited selection source is unavailable.")
          }
          try require(parent.programHash == candidate.programHash && parent.sourceID == candidate.sourceID
            && inherited.removedIndices == edit.removedIndices && edit.historicalRecord == nil,
            "Inherited mask differs from the exact earlier geometry.")
        } else { try require(edit.historicalRecord != nil, "Historical selection must retain its original provenance record.") }
        expected = affected; undo = []; redo = []
      case .completeTarget:
        try require(affected.isEmpty && edit.modelID == nil && edit.operationID == nil, "Target completion cannot change geometry or invent machine labels.")
      case .undo, .redo:
        let targetID = edit.action == .undo ? undo.popLast() : redo.popLast()
        guard let targetID, let target = applied[targetID] else { throw FlowPortfolioError.invalid("Undo or redo has no valid operation.") }
        try require(targetID == edit.operationID && target.candidateID == edit.candidateID
          && target.affectedIndices == edit.affectedIndices && edit.modelID == nil, "Undo or redo differs from its target operation.")
        let remove = (target.action == .remove) == (edit.action == .redo)
        if remove { expected.formUnion(affected) } else { expected.subtract(affected) }
        if edit.action == .undo { redo.append(targetID) } else { undo.append(targetID) }
      }
      if edit.action != .modelProposal {
        try require(edit.probabilities == nil && edit.threshold == nil && edit.policy == nil, "Human edits cannot impersonate a model inference receipt.")
      }
      if edit.action != .inheritedSelection {
        try require(edit.inheritedFromRevisionID == nil && edit.historicalRecord == nil, "Only an inherited selection can carry inherited provenance.")
      }
      try require(expected == removed && undo == edit.undoOperationIDs && redo == edit.redoOperationIDs, "Pruning mask or undo history differs from its operations.")
      lastEdit[edit.candidateID] = edit; applied[edit.id] = edit
    }
    for presentation in state.presentations {
      try require((2...24).contains(presentation.items.count) && unique(presentation.items), "Ranking presentation must contain distinct exact versions.")
      for item in presentation.items {
        guard let candidate = candidates[item.candidateID] else { throw FlowPortfolioError.invalid("Ranked drawing is missing.") }
        try require(item.sourceID == candidate.sourceID, "Ranked source does not match its drawing.")
        if let revision = item.revisionID {
          try require(item.id == revision && edits[revision]?.candidateID == candidate.id
            && edits[revision]?.removedIndices == item.removedIndices, "Ranked pruning revision differs from its frozen display.")
        } else { try require(item.id == candidate.id && item.removedIndices.isEmpty, "Unpruned ranking must preserve the full candidate.") }
        switch presentation.scope {
        case .portfolio: break
        case .candidate(let id): try require(id == candidate.id, "Ranked drawing scope is inconsistent.")
        case .source(let id): try require(state.photoSourceIDs(for: id).contains(candidate.sourceID), "Ranked photo scope is inconsistent.")
        case .round(let id): try require(id == candidate.roundID, "Ranked round scope is inconsistent.")
        }
      }
    }
    var lastRanking: [UUID: UUID] = [:]
    for ranking in state.rankings {
      guard let presentation = presentations[ranking.presentationID] else { throw FlowPortfolioError.invalid("Ranking presentation is missing.") }
      let flat = ranking.orderedGroups.flatMap { $0 }
      try require(ranking.orderedGroups.allSatisfy { !$0.isEmpty } && Set(flat).count == flat.count
        && Set(flat).isSubset(of: Set(presentation.items.map(\.id))) && !(ranking.skipped && ranking.neither)
        && (!(ranking.skipped || ranking.neither) || flat.isEmpty)
        && ranking.supersedesID == lastRanking[ranking.presentationID], "Ranking revision is invalid or loses prior judgments.")
      lastRanking[ranking.presentationID] = ranking.id
    }
    let snapshotIDs = Set(state.trainingSnapshots.map(\.id)), fitIDs = Set(state.fits.map(\.id))
    for snapshot in state.trainingSnapshots {
      try require(snapshot.portfolioID == state.id && snapshot.purpose == state.purpose && snapshot.portfolioRevision < state.revision
        && snapshot.document.sha256 == snapshot.contentSHA256
        && snapshot.manifest?.mediaType == "application/json" && snapshot.manifest?.encoding == "utf8-json"
        && snapshot.publication != nil, "Training snapshot identity is invalid.")
    }
    for fit in state.fits { try require(snapshotIDs.contains(fit.snapshotID), "Fit has no frozen training snapshot.") }
    var active: UUID?
    for activation in state.activations {
      try require(activation.previousFitID == active && (activation.fitID == nil || fitIDs.contains(activation.fitID!)), "Model activation history is inconsistent.")
      active = activation.fitID
    }
    try require(active == state.activeFitID, "Active model differs from its recorded activation.")
    if let id = state.currentPresentationID { try require(presentations[id] != nil, "Current ranking presentation is missing.") }
    if let id = state.selectedSourceID { try require(sources[id] != nil, "Selected source is missing.") }
    if let id = state.currentRoundID { try require(rounds[id] != nil, "Current round is missing.") }
    if let id = state.currentCandidateID { try require(candidates[id] != nil, "Current drawing is missing.") }
    if let id = state.currentPruneRevisionID { try require(edits[id]?.candidateID == state.currentCandidateID, "Current pruning revision is inconsistent.") }
    for blob in blobs(state) {
      try require(FlowPortfolioValidation.validHash(blob.sha256) && (1...128 * 1024 * 1024).contains(blob.byteCount)
        && !blob.mediaType.isEmpty, "Portfolio content reference is invalid.")
    }
  }

  static func blobs(_ state: FlowPortfolioSnapshot) -> [FlowPortfolioBlob] {
    var result: [FlowPortfolioBlob] = state.sources.map(\.image)
    result.append(contentsOf: state.sources.compactMap { $0.importProvenance?.manifest })
    for candidate in state.candidates { result.append(contentsOf: [candidate.raster, candidate.preview]) }
    result.append(contentsOf: state.pruneRevisions.compactMap(\.historicalRecord))
    result.append(contentsOf: state.trainingSnapshots.map(\.document))
    for fit in state.fits {
      if let checkpoint = fit.checkpoint { result.append(checkpoint) }
      result.append(fit.report)
    }
    return result
  }
}
