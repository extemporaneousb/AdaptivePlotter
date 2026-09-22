import Foundation
import PlotterModel

extension PortraitStyle {
  /// Only these renderers are offered for new authoring. Legacy styles remain
  /// decodable so retained programs and their provenance are unchanged.
  static let authoringCases: [Self] = [.flowEdges, .contours, .sketch]
  static let legacyCases: [Self] = [.contours, .hatch, .crosshatch, .sketch, .sketchHatch]
}

extension PortraitVectorOptions {
  static var flowDefaults: Self {
    Self(minimumContourLength: 6, simplificationTolerance: 0.25,
      hatchSpacing: 8, tonalStrength: 1, smoothing: 1.5, sketchThreshold: 0.012)
  }
}

extension PortraitVectorPreset {
  func options(for style: PortraitStyle) -> PortraitVectorOptions {
    guard style == .flowEdges else { return options }
    switch self {
    case .fine:
      return PortraitVectorOptions(minimumContourLength: 4, simplificationTolerance: 0.2,
        hatchSpacing: 6, tonalStrength: 1, smoothing: 1, sketchThreshold: 0.008)
    case .balanced: return .flowDefaults
    case .broadMarker:
      return PortraitVectorOptions(minimumContourLength: 10, simplificationTolerance: 0.3,
        hatchSpacing: 12, tonalStrength: 0.8, smoothing: 2, sketchThreshold: 0.018)
    }
  }
}

/// Immutable renderer parameters, including backward-compatible archive provenance.
struct PortraitStyleRecipe: Identifiable, Codable, Hashable, Sendable {
  let id: String
  let title: String
  let seed: UInt64
  let style: PortraitStyle
  let vectorOptions: PortraitVectorOptions
  let analysisOptions: PortraitAnalysisOptions

}

// Additive recipe fields decode with the original in-memory defaults, keeping
// saved recipe exports readable as the deterministic renderer gains controls.
extension PortraitVectorOptions {
  enum CodingKeys: String, CodingKey {
    case contourLevels, minimumContourLength, simplificationTolerance, hatchSpacing
    case tonalStrength, smoothing, sketchThreshold, hatchAngleDegrees, headScale, semanticHead, materialContext
  }
  init(from decoder: Decoder) throws {
    self.init()
    let values = try decoder.container(keyedBy: CodingKeys.self)
    contourLevels = try values.decodeIfPresent(Int.self, forKey: .contourLevels) ?? contourLevels
    minimumContourLength = try values.decodeIfPresent(Double.self, forKey: .minimumContourLength) ?? minimumContourLength
    simplificationTolerance = try values.decodeIfPresent(Double.self, forKey: .simplificationTolerance) ?? simplificationTolerance
    hatchSpacing = try values.decodeIfPresent(Int.self, forKey: .hatchSpacing) ?? hatchSpacing
    tonalStrength = try values.decodeIfPresent(Double.self, forKey: .tonalStrength) ?? tonalStrength
    smoothing = try values.decodeIfPresent(Double.self, forKey: .smoothing) ?? smoothing
    sketchThreshold = try values.decodeIfPresent(Double.self, forKey: .sketchThreshold) ?? sketchThreshold
    hatchAngleDegrees = try values.decodeIfPresent(Double.self, forKey: .hatchAngleDegrees) ?? hatchAngleDegrees
    headScale = try values.decodeIfPresent(Double.self, forKey: .headScale) ?? headScale
    semanticHead = try values.decodeIfPresent(PortraitSemanticHeadParameters.self, forKey: .semanticHead)
    materialContext = try values.decodeIfPresent(PortraitMaterialContext.self, forKey: .materialContext)
  }
}

extension PortraitAnalysisOptions {
  enum CodingKeys: String, CodingKey { case cropToFace, removeBackground, faceCropMargin }
  init(from decoder: Decoder) throws {
    self.init()
    let values = try decoder.container(keyedBy: CodingKeys.self)
    cropToFace = try values.decodeIfPresent(Bool.self, forKey: .cropToFace) ?? cropToFace
    removeBackground = try values.decodeIfPresent(Bool.self, forKey: .removeBackground) ?? removeBackground
    faceCropMargin = try values.decodeIfPresent(Double.self, forKey: .faceCropMargin) ?? faceCropMargin
  }
}
