import Foundation

/// Exploration categories are distinct from the vectorizer implementation.
/// Two contour categories deliberately cover sparse and tonal contour recipes.
enum PortraitExplorationFamily: String, Codable, CaseIterable, Hashable, Sendable {
  case contour, tonalContour, cleanLine, hatch, crosshatch, sketchHatch

  var style: PortraitStyle {
    switch self {
    case .contour, .tonalContour: .contours
    case .cleanLine: .sketch
    case .hatch: .hatch
    case .crosshatch: .crosshatch
    case .sketchHatch: .sketchHatch
    }
  }

  static func infer(from recipe: PortraitStyleRecipe) -> Self {
    switch recipe.style {
    case .contours: recipe.vectorOptions.contourLevels <= 3 ? .contour : .tonalContour
    case .sketch: .cleanLine
    case .hatch: .hatch
    case .crosshatch: .crosshatch
    case .sketchHatch: .sketchHatch
    }
  }
}

enum PortraitProposalKind: String, Codable, Hashable, Sendable { case broad, local }

struct PortraitProposalMetadata: Codable, Hashable, Sendable {
  let policyRevision: String
  let kind: PortraitProposalKind
  let seed: UInt64
  let family: PortraitExplorationFamily
}

struct PortraitRecipeProposal: Hashable, Sendable {
  let recipe: PortraitStyleRecipe
  let metadata: PortraitProposalMetadata
}
