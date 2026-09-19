import Foundation
import PlotterModel

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
