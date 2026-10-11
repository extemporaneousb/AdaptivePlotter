import Foundation
import PlotterModel

extension PortraitStyle {
  /// Only these renderers are offered for new authoring. Legacy styles remain
  /// decodable so retained programs and their provenance are unchanged.
  package static let authoringCases: [Self] = [.flowEdges, .contours, .sketch]
  package static let legacyCases: [Self] = [.contours, .hatch, .crosshatch, .sketch, .sketchHatch]
}

/// Immutable renderer parameters, including backward-compatible archive provenance.
package struct PortraitStyleRecipe: Identifiable, Codable, Hashable, Sendable {
  package let id: String
  package let title: String
  package let seed: UInt64
  package let style: PortraitStyle
  package let vectorOptions: PortraitVectorOptions
  package let analysisOptions: PortraitAnalysisOptions


  package init(
    id: String,
    title: String,
    seed: UInt64,
    style: PortraitStyle,
    vectorOptions: PortraitVectorOptions,
    analysisOptions: PortraitAnalysisOptions
  ) {
    self.id = id
    self.title = title
    self.seed = seed
    self.style = style
    self.vectorOptions = vectorOptions
    self.analysisOptions = analysisOptions
  }
}

// Additive recipe fields decode with the original in-memory defaults, keeping
// saved recipe exports readable as the deterministic renderer gains controls.
extension PortraitVectorOptions {
  package enum CodingKeys: String, CodingKey {
    case drawingParameters
    case contourLevels, minimumContourLength, simplificationTolerance, hatchSpacing
    case tonalStrength, smoothing, sketchThreshold, hatchAngleDegrees, headScale, semanticHead, materialContext
    case flowRectilinearity
    case flowSupport, flowStructureSupport, flowSupportScale, flowSeedIrregularity
    case regionalTreatment, regionalAdjustments, eyeExaggeration
  }
  package init(from decoder: Decoder) throws {
    self.init()
    let values = try decoder.container(keyedBy: CodingKeys.self)
    drawingParameters = try values.decodeIfPresent(PortraitDrawingParameters.self, forKey: .drawingParameters)?.bounded
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
    flowRectilinearity = try values.decodeIfPresent(Double.self, forKey: .flowRectilinearity)
    flowSupport = Self.flowAmount(try values.decodeIfPresent(Double.self, forKey: .flowSupport))
    flowStructureSupport = Self.flowAmount(try values.decodeIfPresent(Double.self, forKey: .flowStructureSupport))
    flowSupportScale = Self.flowAmount(try values.decodeIfPresent(Double.self, forKey: .flowSupportScale))
    flowSeedIrregularity = Self.flowAmount(try values.decodeIfPresent(Double.self, forKey: .flowSeedIrregularity))
    regionalTreatment = try values.decodeIfPresent(PortraitRegionalParameters.self, forKey: .regionalTreatment)
    regionalAdjustments = try values.decodeIfPresent([PortraitRegionalParameters].self, forKey: .regionalAdjustments)
    eyeExaggeration = try values.decodeIfPresent(PortraitEyeExaggerationParameters.self, forKey: .eyeExaggeration)
  }

  package func encode(to encoder: Encoder) throws {
    var values = encoder.container(keyedBy: CodingKeys.self)
    try values.encodeIfPresent(drawingParameters?.bounded, forKey: .drawingParameters)
    try values.encode(contourLevels, forKey: .contourLevels)
    try values.encode(minimumContourLength, forKey: .minimumContourLength)
    try values.encode(simplificationTolerance, forKey: .simplificationTolerance)
    try values.encode(hatchSpacing, forKey: .hatchSpacing)
    try values.encode(tonalStrength, forKey: .tonalStrength)
    try values.encode(smoothing, forKey: .smoothing)
    try values.encode(sketchThreshold, forKey: .sketchThreshold)
    try values.encode(hatchAngleDegrees, forKey: .hatchAngleDegrees)
    try values.encode(headScale, forKey: .headScale)
    try values.encodeIfPresent(semanticHead, forKey: .semanticHead)
    try values.encodeIfPresent(materialContext, forKey: .materialContext)
    try values.encodeIfPresent(flowRectilinearity, forKey: .flowRectilinearity)
    try values.encodeIfPresent(Self.flowAmount(flowSupport), forKey: .flowSupport)
    try values.encodeIfPresent(Self.flowAmount(flowStructureSupport), forKey: .flowStructureSupport)
    try values.encodeIfPresent(Self.flowAmount(flowSupportScale), forKey: .flowSupportScale)
    try values.encodeIfPresent(Self.flowAmount(flowSeedIrregularity), forKey: .flowSeedIrregularity)
    try values.encodeIfPresent(regionalTreatment, forKey: .regionalTreatment)
    try values.encodeIfPresent(regionalAdjustments, forKey: .regionalAdjustments)
    try values.encodeIfPresent(eyeExaggeration, forKey: .eyeExaggeration)
  }
}

extension PortraitAnalysisOptions {
  package enum CodingKeys: String, CodingKey { case cropToFace, removeBackground, faceCropMargin }
  package init(from decoder: Decoder) throws {
    self.init()
    let values = try decoder.container(keyedBy: CodingKeys.self)
    cropToFace = try values.decodeIfPresent(Bool.self, forKey: .cropToFace) ?? cropToFace
    removeBackground = try values.decodeIfPresent(Bool.self, forKey: .removeBackground) ?? removeBackground
    faceCropMargin = try values.decodeIfPresent(Double.self, forKey: .faceCropMargin) ?? faceCropMargin
  }
}
