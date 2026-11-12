import Foundation
import PlotterModel
import PortraitArtists
import PortraitLibrary

/// Training reads only a frozen portfolio revision. Human edits and model proposals
/// stay distinct; all variants of linked sources share one partition group.
package enum FlowAuthoringTraining {
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
      guard nextExamples <= 5_000,
        FlowArtistTrainingLimits.accepts(featureValueCount: nextElements, explicitLabelCount: nextLabels) else {
        throw FlowPortfolioError.unavailable("This local fit exceeds 5,000 examples, 10 million feature values, or 20,000 explicit stroke labels. Exclude some drawings or sources from training; their portfolio records remain intact.")
      }
      examples = nextExamples; featureElements = nextElements; labels = nextLabels
    }
  }

  package static func dataset(store: FlowPortfolioStore, document: FlowPortfolioSnapshot) async throws -> FlowPortfolioTrainingInputs {
    guard let manifest = document.frozenManifest, let publication = document.frozenTrainingPublication else {
      throw FlowPortfolioError.unavailable("Training requires an exact frozen task manifest; a live portfolio is not a dataset.")
    }
    return try await store.trainingInputs(manifest: manifest, publication: publication)
  }
}
