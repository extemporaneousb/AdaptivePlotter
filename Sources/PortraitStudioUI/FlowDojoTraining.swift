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
    package mutating func admit(strokeCount: Int, revisionCount: Int, labelCount: Int, includeRoot: Bool = true) throws {
      guard (0...10_000).contains(strokeCount), (0...5_000).contains(revisionCount),
        labelCount >= 0, labelCount <= strokeCount else {
        throw FlowPortfolioError.unavailable("A drawing exceeds the local fit limit of 10,000 strokes or has invalid training counts.")
      }
      let nextExamples = examples + (includeRoot ? 1 : 0) + revisionCount
      let nextElements = featureElements + ((includeRoot ? 1 : 0) + revisionCount)
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
    let plan = FlowDojoSupervision.plan(document)
    var budget = Budget()
    var examples: [FlowArtistExample] = []
    for entry in plan.entries {
      try Task.checkCancellation()
      let candidate = entry.candidate
      try budget.admit(strokeCount: candidate.strokeCount, revisionCount: entry.revisions.count,
        labelCount: entry.labels.count, includeRoot: entry.includeRoot)
      let root = try await store.featureCapsule(candidateID: candidate.id)
      let strokeFeatures = root.strokes
      let rootID = candidate.id.uuidString
      if entry.includeRoot {
        examples.append(.init(id: rootID, sourceGroupID: entry.group, recipe: candidate.recipe,
          features: root.drawing,
          strokeFeatures: strokeFeatures, strokeLabels: entry.labels.expanded(), baseDrawingID: rootID, removedIndices: []))
      }
      for revision in entry.revisions {
        let capsule = try await store.featureCapsule(candidateID: candidate.id, revisionID: revision.id)
        examples.append(.init(id: revision.id.uuidString, sourceGroupID: entry.group, recipe: candidate.recipe,
          features: capsule.drawing, strokeFeatures: strokeFeatures, strokeLabels: [],
          baseDrawingID: rootID, removedIndices: revision.removedIndices))
      }
    }
    return (examples, plan.rankings)
  }
}
