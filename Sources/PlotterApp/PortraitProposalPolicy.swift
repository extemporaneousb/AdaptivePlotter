import Foundation

/// A versioned prior over authored recipes. The declared weights put 90% of
/// broad exploration in contour, tonal contour and clean-line work. Explicit
/// hatch recipes remain available independently of these sampling weights.
enum PortraitProposalPolicy {
  static let revision = "portrait-proposal-v1"

  struct FamilyWeight: Equatable, Sendable {
    let family: PortraitExplorationFamily
    let weight: Int
  }

  static let familyWeights: [FamilyWeight] = [
    .init(family: .contour, weight: 30), .init(family: .tonalContour, weight: 30),
    .init(family: .cleanLine, weight: 30), .init(family: .hatch, weight: 4),
    .init(family: .crosshatch, weight: 3), .init(family: .sketchHatch, weight: 3),
  ]

  static func broad(seed: UInt64, penWidthMM: Double, bigHead: Bool = false) -> PortraitRecipeProposal {
    var random = PortraitRecipeRandom(seed: seed)
    var ticket = random.index(familyWeights.reduce(0) { $0 + $1.weight })
    var family = PortraitExplorationFamily.contour
    for entry in familyWeights {
      if ticket < entry.weight { family = entry.family; break }
      ticket -= entry.weight
    }
    var options = PortraitStyleRecipe.baseOptions(penWidthMM: penWidthMM)
    options.tonalStrength = random.value(0.7...1.4)
    options.smoothing = random.value(0.25...1.8)
    switch family {
    case .contour, .tonalContour:
      options.contourLevels = family == .contour ? 1 + random.index(3) : 4 + random.index(5)
      options.minimumContourLength *= random.value(0.55...1.6)
      options.simplificationTolerance *= random.value(0.55...1.65)
    case .cleanLine, .sketchHatch:
      options.sketchThreshold = random.value(0.004...0.022)
      options.minimumContourLength *= random.value(0.55...1.6)
      options.simplificationTolerance *= random.value(0.55...1.65)
    case .hatch, .crosshatch: break
    }
    if [.hatch, .crosshatch, .sketchHatch].contains(family) {
      options.hatchSpacing = min(16, options.hatchSpacing + random.index(6))
      options.hatchAngleDegrees = [-60.0, -40, -20, 0, 20, 40, 60][random.index(7)]
    }
    options.headScale = bigHead ? random.value(1.2...1.6) : 1
    let analysis = PortraitAnalysisOptions(cropToFace: true, removeBackground: true,
      faceCropMargin: bigHead ? random.value(0.55...0.8) : random.value(0.25...0.65))
    return proposal(seed: seed, kind: .broad, family: family, style: family.style,
      options: options.bounded, analysis: analysis,
      title: (bigHead ? "Festival " : "") + title(for: family))
  }

  /// Local proposals use exactly the parent's analysis options and head settings.
  /// The caller also reuses the parent's immutable analyzed raster; this policy
  /// neither reacquires a photo nor calls image analysis nor retains a candidate.
  static func local(parent: PortraitCandidate, seed: UInt64) -> PortraitRecipeProposal {
    let family = parent.proposal?.family ?? PortraitExplorationFamily.infer(from: parent.recipe)
    var random = PortraitRecipeRandom(seed: seed)
    var options = parent.recipe.vectorOptions
    for parameter in localParameters(family: family, headScale: options.headScale) {
      let delta = random.value(-localRadius(parameter: parameter)...localRadius(parameter: parameter))
      switch parameter {
      case .contourLevels:
        options.contourLevels = min(12, max(1, min(12, max(1, options.contourLevels)) + random.index(3) - 1))
      case .minimumContourLength: options.minimumContourLength = clamp(options.minimumContourLength + delta, 0...40)
      case .simplificationTolerance: options.simplificationTolerance = clamp(options.simplificationTolerance + delta, 0...3)
      case .hatchSpacing: options.hatchSpacing = min(16, max(1, min(16, max(1, options.hatchSpacing)) + random.index(3) - 1))
      case .tonalStrength: options.tonalStrength = clamp(options.tonalStrength + delta, 0.4...2)
      case .smoothing: options.smoothing = clamp(options.smoothing + delta, 0...4)
      case .sketchThreshold: options.sketchThreshold = clamp(options.sketchThreshold + delta, 0.002...0.08)
      case .hatchAngleDegrees: options.hatchAngleDegrees = clamp(options.hatchAngleDegrees + delta, -90...90)
      case .headScale, .foreheadWidth, .foreheadHeight, .eyeScale, .lateralScale: break
      }
    }
    return proposal(seed: seed, kind: .local, family: family, style: parent.recipe.style,
      options: options, analysis: parent.recipe.analysisOptions, title: "Like " + title(for: family))
  }

  /// Fixed additive neighborhoods avoid large changes near zero. Integer levels
  /// and spacing move by at most one. All candidates also obey renderer bounds.
  static func localRadius(parameter: PortraitTrainableParameter) -> Double {
    switch parameter {
    case .contourLevels, .hatchSpacing: 1
    case .minimumContourLength: 2
    case .simplificationTolerance: 0.2
    case .tonalStrength: 0.15
    case .smoothing: 0.3
    case .sketchThreshold: 0.003
    case .hatchAngleDegrees: 10
    case .headScale, .foreheadWidth, .foreheadHeight, .eyeScale, .lateralScale: 0
    }
  }

  static func localParameters(family: PortraitExplorationFamily,
    headScale: Double) -> [PortraitTrainableParameter] {
    var parameters: [PortraitTrainableParameter] = [.tonalStrength, .smoothing]
    switch family {
    case .contour, .tonalContour:
      parameters += [.contourLevels, .minimumContourLength, .simplificationTolerance]
    case .cleanLine:
      parameters += [.sketchThreshold, .minimumContourLength, .simplificationTolerance]
    case .hatch, .crosshatch:
      parameters += [.hatchSpacing, .hatchAngleDegrees]
      if headScale > 1 { parameters.append(.simplificationTolerance) }
    case .sketchHatch:
      parameters += [.sketchThreshold, .minimumContourLength, .simplificationTolerance,
        .hatchSpacing, .hatchAngleDegrees]
    }
    return parameters
  }

  private static func proposal(seed: UInt64, kind: PortraitProposalKind,
    family: PortraitExplorationFamily, style: PortraitStyle, options: PortraitVectorOptions,
    analysis: PortraitAnalysisOptions, title: String) -> PortraitRecipeProposal {
    let metadata = PortraitProposalMetadata(policyRevision: revision, kind: kind, seed: seed, family: family)
    let identity = "\(revision)|\(kind.rawValue)|\(family.rawValue)|\(seed)|\(style.rawValue)|\(options.provenance)"
      + "|face=\(analysis.cropToFace)|margin=\(analysis.faceCropMargin)|mask=\(analysis.removeBackground)"
    let recipe = PortraitStyleRecipe(id: PortraitVectorizer.stableID(identity).uuidString,
      title: "\(title) · \(seed % 10_000)", seed: seed, style: style,
      vectorOptions: options, analysisOptions: analysis)
    return PortraitRecipeProposal(recipe: recipe, metadata: metadata)
  }

  private static func title(for family: PortraitExplorationFamily) -> String {
    switch family {
    case .contour: "Contour"
    case .tonalContour: "Tonal contour"
    case .cleanLine: "Clean line"
    case .hatch: "Hatch"
    case .crosshatch: "Crosshatch"
    case .sketchHatch: "Sketch + hatch"
    }
  }

  private static func clamp(_ value: Double, _ bounds: ClosedRange<Double>) -> Double {
    min(bounds.upperBound, max(bounds.lowerBound, value))
  }
}
