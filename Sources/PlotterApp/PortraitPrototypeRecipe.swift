import Foundation

/// Starting points use different stroke decisions, not merely preview styling.
/// Saved recipes retain the complete parameter value, independent of these names.
enum PortraitPrototypeRecipe: String, CaseIterable, Identifiable, Sendable {
  case sparseStructure = "Sparse structure"
  case angularComic = "Angular comic"
  case landmarkExaggeration = "Measured eye exaggeration"
  var id: Self { self }
  var title: String { rawValue }
  var detail: String {
    switch self {
    case .sparseStructure: "Protected features, reduced skin texture and sparse tonal strokes"
    case .angularComic: "Angular contours, ordered shadow strokes and reinforced jaw contours"
    case .landmarkExaggeration: "Bounded 2D expansion around measured eye centers"
    }
  }
  var style: PortraitStyle { .flowEdges }

  func options(basedOn base: PortraitVectorOptions = .flowDefaults) -> PortraitVectorOptions {
    var result = base
    result.headScale = 1; result.semanticHead = nil; result.eyeExaggeration = nil
    result.regionalAdjustments = nil
    result.flowRectilinearity = nil; result.flowSupport = nil
    result.flowStructureSupport = nil; result.flowSupportScale = nil; result.flowSeedIrregularity = nil
    switch self {
    case .sparseStructure:
      result.minimumContourLength = 5; result.sketchThreshold = 0.010
      result.hatchSpacing = 15; result.tonalStrength = 0.4; result.smoothing = 1
      result.regionalTreatment = .init(skinSuppression: 0.9, featureProtection: 1)
    case .angularComic:
      result.minimumContourLength = 7; result.sketchThreshold = 0.016
      result.hatchSpacing = 16; result.tonalStrength = 0.4; result.smoothing = 0.5
      result.regionalTreatment = .init(skinSuppression: 0.5, featureProtection: 1,
        angularity: 1, shadowStrength: 1, contourEmphasis: 1)
    case .landmarkExaggeration:
      result.minimumContourLength = 5; result.sketchThreshold = 0.010
      result.hatchSpacing = 12; result.tonalStrength = 0.6; result.smoothing = 1.5
      result.regionalTreatment = .init(skinSuppression: 0.75, featureProtection: 1, angularity: 0.25)
      result.eyeExaggeration = .init(amount: 0.3)
    }
    return result.bounded
  }

  func recipe(analysisOptions: PortraitAnalysisOptions = .init(), seed: UInt64 = 0) -> PortraitStyleRecipe {
    PortraitStyleRecipe(id: "prototype-v1-\(String(describing: self))", title: title, seed: seed,
      style: style, vectorOptions: options(), analysisOptions: analysisOptions)
  }
}
