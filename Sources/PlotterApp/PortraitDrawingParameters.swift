import Foundation

/// Renderer-independent authoring coordinates. Spatial controls are fractions of
/// raster height, so a style's analysis resolution does not redefine their scale.
struct PortraitDrawingParameters: Codable, Hashable, Sendable {
  var detail = 0.5
  var tone = 1.0
  var smoothness = 0.5
  var minimumLine = 0.0125

  var bounded: Self {
    var result = self
    result.detail = Self.clamp(detail, to: 0...1, fallback: 0.5)
    result.tone = Self.clamp(tone, to: 0.4...2, fallback: 1)
    result.smoothness = Self.clamp(smoothness, to: 0...1, fallback: 0.5)
    result.minimumLine = Self.clamp(minimumLine, to: 0...0.075, fallback: 0.0125)
    return result
  }

  static func preset(_ preset: PortraitVectorPreset) -> Self {
    switch preset {
    case .fine: Self(detail: 0.85, smoothness: 0.25, minimumLine: 0.008)
    case .balanced: Self()
    case .broadMarker: Self(detail: 0.15, tone: 0.85, smoothness: 0.8, minimumLine: 0.025)
    }
  }

  private static func clamp(_ value: Double, to range: ClosedRange<Double>, fallback: Double) -> Double {
    value.isFinite ? min(range.upperBound, max(range.lowerBound, value)) : fallback
  }
}

extension PortraitDrawingParameters {
  private enum CodingKeys: String, CodingKey { case revision, detail, tone, smoothness, minimumLine }

  init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    guard try values.decode(String.self, forKey: .revision) == "portrait-drawing-parameters-v1" else {
      throw PortraitCandidateError.integrityMismatch
    }
    self.init(detail: try values.decode(Double.self, forKey: .detail),
      tone: try values.decode(Double.self, forKey: .tone),
      smoothness: try values.decode(Double.self, forKey: .smoothness),
      minimumLine: try values.decode(Double.self, forKey: .minimumLine))
    self = bounded
  }

  func encode(to encoder: Encoder) throws {
    var values = encoder.container(keyedBy: CodingKeys.self)
    let value = bounded
    try values.encode("portrait-drawing-parameters-v1", forKey: .revision)
    try values.encode(value.detail, forKey: .detail)
    try values.encode(value.tone, forKey: .tone)
    try values.encode(value.smoothness, forKey: .smoothness)
    try values.encode(value.minimumLine, forKey: .minimumLine)
  }
}

extension PortraitVectorOptions {
  /// Resolve once at the kernel boundary, before material floors. The archived
  /// shared coordinates remain the authority; low-level fields serve legacy recipes.
  func resolved(rasterHeight: Int) -> Self {
    guard let parameters = drawingParameters?.bounded else { return bounded }
    var result = bounded
    let height = Double(rasterHeight)
    result.contourLevels = Int((3 + parameters.detail * 6).rounded())
    result.hatchSpacing = Int((13 - parameters.detail * 10).rounded())
    result.sketchThreshold = 0.022 - parameters.detail * 0.02
    result.tonalStrength = parameters.tone
    result.smoothing = height * 0.005 * parameters.smoothness
    result.minimumContourLength = height * parameters.minimumLine
    result.simplificationTolerance = height * (0.001 + (1 - parameters.detail) * 0.004)
    return result.bounded
  }

  /// This is an editable projection of a legacy recipe, never an archive migration.
  /// Its original independent algorithm knobs cannot all be inverted into Detail.
  func drawingParameters(for style: PortraitStyle, rasterHeight: Int) -> PortraitDrawingParameters {
    if let drawingParameters { return drawingParameters.bounded }
    let value = bounded
    let detail: Double
    switch style {
    case .contours: detail = (Double(value.contourLevels) - 3) / 6
    case .flowEdges, .hatch, .crosshatch: detail = (13 - Double(value.hatchSpacing)) / 10
    case .sketch, .sketchHatch: detail = (0.022 - value.sketchThreshold) / 0.02
    }
    let height = Double(max(2, rasterHeight))
    return PortraitDrawingParameters(detail: detail, tone: value.tonalStrength,
      smoothness: value.smoothing / (height * 0.005),
      minimumLine: value.minimumContourLength / height).bounded
  }
}
