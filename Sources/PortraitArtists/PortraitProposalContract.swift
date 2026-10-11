import Foundation

/// Exploration categories are distinct from the vectorizer implementation.
/// Two contour categories deliberately cover sparse and tonal contour recipes.
package enum PortraitExplorationFamily: String, Codable, CaseIterable, Hashable, Sendable {
  case contour, tonalContour, cleanLine, hatch, crosshatch, sketchHatch

  package var style: PortraitStyle {
    switch self {
    case .contour, .tonalContour: .contours
    case .cleanLine: .sketch
    case .hatch: .hatch
    case .crosshatch: .crosshatch
    case .sketchHatch: .sketchHatch
    }
  }

  package static func infer(from recipe: PortraitStyleRecipe) -> Self {
    switch recipe.style {
    case .contours: recipe.vectorOptions.contourLevels <= 3 ? .contour : .tonalContour
    case .sketch, .flowEdges: .cleanLine
    case .hatch: .hatch
    case .crosshatch: .crosshatch
    case .sketchHatch: .sketchHatch
    }
  }
}

package enum PortraitProposalKind: String, Codable, Hashable, Sendable { case broad, local, semanticTraining }

package struct PortraitProposalMetadata: Codable, Hashable, Sendable {
  package let policyRevision: String
  package let kind: PortraitProposalKind
  package let seed: UInt64
  package let family: PortraitExplorationFamily
  package var trainingSelection: PortraitTrainingSelection? = nil

  package init(
    policyRevision: String,
    kind: PortraitProposalKind,
    seed: UInt64,
    family: PortraitExplorationFamily,
    trainingSelection: PortraitTrainingSelection? = nil
  ) {
    self.policyRevision = policyRevision
    self.kind = kind
    self.seed = seed
    self.family = family
    self.trainingSelection = trainingSelection
  }
}

package struct PortraitRecipeProposal: Hashable, Sendable {
  package let recipe: PortraitStyleRecipe
  package let metadata: PortraitProposalMetadata

  package init(recipe: PortraitStyleRecipe, metadata: PortraitProposalMetadata) {
    self.recipe = recipe
    self.metadata = metadata
  }
}
