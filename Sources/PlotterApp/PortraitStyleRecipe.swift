import Foundation
import PlotterModel

/// A reproducible local rendering recipe. A seed varies the recipe parameters;
/// it is not a neural-model latent and does not synthesize a new face.
struct PortraitStyleRecipe: Identifiable, Codable, Hashable, Sendable {
  let id: String
  let title: String
  let seed: UInt64
  let style: PortraitStyle
  let vectorOptions: PortraitVectorOptions
  let analysisOptions: PortraitAnalysisOptions

  static func catalog(penWidthMM: Double = 0.8) -> [Self] {
    let base = baseOptions(penWidthMM: penWidthMM)
    func recipe(_ title: String, _ style: PortraitStyle,
                headScale: Double = 1, angle: Double = 0,
                change: (inout PortraitVectorOptions) -> Void = { _ in }) -> Self {
      var vectors = base
      vectors.headScale = headScale
      vectors.hatchAngleDegrees = angle
      change(&vectors)
      let analysis = PortraitAnalysisOptions(faceCropMargin: headScale > 1 ? 0.7 : 0.4)
      return make(title: title, seed: 0, style: style, vectors: vectors, analysis: analysis)
    }
    return [
      recipe("Clean ink", .sketch) { $0.sketchThreshold = 0.008; $0.smoothing = 0.5 },
      recipe("Pencil shading", .sketchHatch, angle: -35) {
        $0.sketchThreshold = 0.006; $0.tonalStrength = 0.85
        $0.hatchSpacing = max(5, $0.hatchSpacing); $0.smoothing = 0.7
      },
      recipe("Etched portrait", .crosshatch, angle: 35) { $0.tonalStrength = 1.15 },
      recipe("Tonal map", .contours) { $0.contourLevels = 4; $0.smoothing = 1 },
      recipe("Bold poster", .contours) {
        $0.contourLevels = 2; $0.tonalStrength = 1.3; $0.smoothing = 1.5
      },
      recipe("Festival head", .sketchHatch, headScale: 1.4, angle: -25) {
        $0.sketchThreshold = 0.008; $0.hatchSpacing = max(6, $0.hatchSpacing)
        $0.tonalStrength = 0.9
      },
    ]
  }

  static func random(seed: UInt64, penWidthMM: Double = 0.8, bigHead: Bool = false) -> Self {
    var random = PortraitRecipeRandom(seed: seed)
    let style = PortraitStyle.allCases[random.index(PortraitStyle.allCases.count)]
    var vectors = baseOptions(penWidthMM: penWidthMM)
    vectors.contourLevels = 2 + random.index(6)
    vectors.minimumContourLength *= random.value(0.55...1.6)
    vectors.simplificationTolerance *= random.value(0.55...1.65)
    vectors.hatchSpacing = min(16, vectors.hatchSpacing + random.index(6))
    vectors.tonalStrength = random.value(0.7...1.4)
    vectors.smoothing = random.value(0.25...1.8)
    vectors.sketchThreshold = random.value(0.004...0.022)
    vectors.hatchAngleDegrees = [-60.0, -40, -20, 0, 20, 40, 60][random.index(7)]
    vectors.headScale = bigHead ? random.value(1.2...1.6) : 1
    let analysis = PortraitAnalysisOptions(cropToFace: true, removeBackground: true,
      faceCropMargin: bigHead ? random.value(0.55...0.8) : random.value(0.25...0.65))
    let title = (bigHead ? "Festival " : "") + style.rawValue + " · " + String(seed % 10_000)
    return make(title: title, seed: seed, style: style, vectors: vectors, analysis: analysis)
  }

  static func seededVariants(seed: UInt64, count: Int = 6, penWidthMM: Double = 0.8) -> [Self] {
    var random = PortraitRecipeRandom(seed: seed)
    return (0..<min(24, max(0, count))).map { index in
      Self.random(seed: random.next(), penWidthMM: penWidthMM, bigHead: index % 4 == 3)
    }
  }

  private static func baseOptions(penWidthMM: Double) -> PortraitVectorOptions {
    let width = penWidthMM.isFinite ? min(5, max(0.1, penWidthMM)) : 0.8
    var options = width >= 1 ? PortraitVectorPreset.broadMarker.options : PortraitVectorPreset.balanced.options
    // The authored field is 100 mm high and analysis is at most 160 pixels.
    // These are starting recipes; actual placement/marker preview stay explicit.
    options.hatchSpacing = min(16, max(options.hatchSpacing, Int(ceil(width * 1.6 * 1.5))))
    return options
  }

  private static func make(title: String, seed: UInt64, style: PortraitStyle,
                           vectors: PortraitVectorOptions, analysis: PortraitAnalysisOptions) -> Self {
    let options = vectors.bounded
    let identity = "recipe-v1|\(title)|\(seed)|\(style.rawValue)|\(options.provenance)"
      + "|face=\(analysis.cropToFace)|margin=\(analysis.boundedFaceCropMargin)|mask=\(analysis.removeBackground)"
    return Self(id: PortraitVectorizer.stableID(identity).uuidString, title: title, seed: seed,
      style: style, vectorOptions: options, analysisOptions: analysis)
  }
}

/// SplitMix64 has a specified integer transition; sequences do not depend on
/// Swift's process-randomized Hasher or the system random-number generator.
private struct PortraitRecipeRandom {
  private var state: UInt64
  init(seed: UInt64) { state = seed }
  mutating func next() -> UInt64 {
    state &+= 0x9e3779b97f4a7c15
    var value = state
    value = (value ^ (value >> 30)) &* 0xbf58476d1ce4e5b9
    value = (value ^ (value >> 27)) &* 0x94d049bb133111eb
    return value ^ (value >> 31)
  }
  mutating func index(_ count: Int) -> Int { Int(next() % UInt64(count)) }
  mutating func value(_ range: ClosedRange<Double>) -> Double {
    let unit = Double(next() >> 11) / 9_007_199_254_740_992
    return range.lowerBound + unit * (range.upperBound-range.lowerBound)
  }
}

// Additive recipe fields decode with the original in-memory defaults, keeping
// saved recipe exports readable as the deterministic renderer gains controls.
extension PortraitVectorOptions {
  enum CodingKeys: String, CodingKey {
    case contourLevels, minimumContourLength, simplificationTolerance, hatchSpacing
    case tonalStrength, smoothing, sketchThreshold, hatchAngleDegrees, headScale
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
