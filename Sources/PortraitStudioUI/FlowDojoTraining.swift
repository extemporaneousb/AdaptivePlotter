import Foundation
import PlotterModel
import PortraitArtists
import PortraitLibrary

/// Training reads only a frozen portfolio revision. Human edits and model proposals
/// stay distinct; all variants of linked sources share one partition group.
package enum FlowDojoTraining {
  /// Enforce the trainer's declared limits before allocating expanded features.
  package struct Budget {
    private var examples = 0
    private var featureElements = 0
    private var labels = 0
    package init() {}
    package mutating func admit(strokeCount: Int, revisionCount: Int, labelCount: Int) throws {
      guard (0...10_000).contains(strokeCount), (0...5_000).contains(revisionCount),
        labelCount >= 0, labelCount <= strokeCount else {
        throw FlowPortfolioError.unavailable("A drawing exceeds the local fit limit of 10,000 strokes or has invalid training counts.")
      }
      let nextExamples = examples + 1 + revisionCount
      let nextElements = featureElements + (1 + revisionCount)
        * (FlowArtistFeatures.drawingCount + strokeCount * FlowArtistFeatures.strokeCount)
      let nextLabels = labels + labelCount
      guard nextExamples <= 5_000, nextElements <= 8_000_000, nextLabels <= 20_000 else {
        throw FlowPortfolioError.unavailable("This local fit exceeds 5,000 examples, 8 million feature values, or 20,000 explicit stroke labels. Exclude some drawings or sources from training; their portfolio records remain intact.")
      }
      examples = nextExamples; featureElements = nextElements; labels = nextLabels
    }
  }

  package static func dataset(store: FlowPortfolioStore, document: FlowPortfolioSnapshot) async throws
    -> (examples: [FlowArtistExample], rankings: [FlowArtistRanking]) {
    let sources = document.sources
    var groups = Dictionary(uniqueKeysWithValues: sources.map { ($0.id, Set($0.groupKeys)) })
    var changed = true
    while changed {
      changed = false
      for source in sources {
        var merged = groups[source.id] ?? []
        for other in sources where !(groups[other.id] ?? []).isDisjoint(with: merged) {
          merged.formUnion(groups[other.id] ?? [])
        }
        if merged != groups[source.id] { groups[source.id] = merged; changed = true }
      }
    }
    let includedSources = Set(sources.filter { !$0.excluded }.map(\.id))
    let candidates = document.candidates.filter { !$0.excluded && includedSources.contains($0.sourceID) }
    let rankedIDs = Set(document.latestRankings.flatMap { $0.orderedGroups.flatMap { $0 } } + document.choices.flatMap { $0.offeredItems.map(\.id) })
    var budget = Budget()
    var examples: [FlowArtistExample] = []
    var exampleIDs = Set<String>()
    for candidate in candidates {
      try Task.checkCancellation()
      let program = try await store.candidateProgram(candidate.id)
      guard program.strokes.count <= 10_000 else {
        throw FlowPortfolioError.unavailable("A drawing exceeds the local fit limit of 10,000 strokes.")
      }
      let revisions = document.pruneRevisions.filter { $0.candidateID == candidate.id }
      let rankedRevisions = revisions.filter { rankedIDs.contains($0.id) }
      let latest = revisions.last
      var labels: [FlowArtistStrokeLabel] = []
      if let target = latest, target.action.rawValue == "completeTarget" {
        let removed = Set(target.removedIndices)
        labels = program.strokes.indices.map { .init(index: $0, removed: removed.contains($0), provenance: .completedMask) }
      } else if let latest {
        var decisions: [Int: FlowArtistStrokeLabel] = [:]
        for operationID in latest.undoOperationIDs {
          guard let operation = revisions.first(where: { $0.id == operationID }),
            operation.action == .remove || operation.action == .restore else { continue }
          for index in operation.affectedIndices {
            decisions[index] = .init(index: index, removed: operation.action == .remove,
              provenance: operation.action == .remove ? .remove : .restore)
          }
        }
        labels = decisions.keys.sorted().compactMap { decisions[$0] }
      }
      try budget.admit(strokeCount: program.strokes.count, revisionCount: rankedRevisions.count, labelCount: labels.count)
      let raster = try await store.candidateRaster(candidate.id)
      let strokeFeatures = FlowArtistFeatures.strokes(recipe: candidate.recipe, program: program, raster: raster)
      let group = groups[candidate.sourceID]!.sorted().joined(separator: "|")
      let rootID = candidate.id.uuidString
      examples.append(.init(id: rootID, sourceGroupID: group, recipe: candidate.recipe,
        features: FlowArtistFeatures.drawing(recipe: candidate.recipe, program: program, raster: raster),
        strokeFeatures: strokeFeatures, strokeLabels: labels, baseDrawingID: rootID, removedIndices: []))
      exampleIDs.insert(rootID)
      for revision in rankedRevisions {
        let id = revision.id.uuidString
        examples.append(.init(id: id, sourceGroupID: group, recipe: candidate.recipe,
          features: FlowArtistFeatures.drawing(recipe: candidate.recipe, program: program, raster: raster,
            removedIndices: Set(revision.removedIndices)), strokeFeatures: strokeFeatures, strokeLabels: [],
          baseDrawingID: rootID, removedIndices: revision.removedIndices))
        exampleIDs.insert(id)
      }
    }
    var rankings: [FlowArtistRanking] = []
    for record in document.latestRankings where !record.skipped && !record.neither {
      guard let presentation = document.presentations.first(where: { $0.id == record.presentationID }) else { continue }
      let allowed = Set(presentation.items.map { $0.id.uuidString })
      let tiers = record.orderedGroups.map { $0.map(\.uuidString).filter { exampleIDs.contains($0) && allowed.contains($0) } }.filter { !$0.isEmpty }
      if tiers.reduce(0, { $0 + $1.count }) >= 2 {
        rankings.append(.init(id: record.id.uuidString, tiers: tiers, provenance: .ranking))
      }
    }
    var seenChoices = Set<String>()
    for choice in document.choices {
      let comparisonKey = ([choice.roundID.uuidString, choice.selectedItemID.uuidString]
        + choice.offeredItems.map { $0.id.uuidString }.sorted()).joined(separator: "|")
      guard seenChoices.insert(comparisonKey).inserted else { continue }
      let winner = choice.selectedItemID.uuidString
      let others = choice.offeredItems.filter { $0.id != choice.selectedItemID }.map { $0.id.uuidString }.filter { exampleIDs.contains($0) }
      if exampleIDs.contains(winner), !others.isEmpty {
        rankings.append(.init(id: choice.id.uuidString, tiers: [[winner], others], provenance: .choice))
      }
    }
    return (examples, rankings)
  }
}
