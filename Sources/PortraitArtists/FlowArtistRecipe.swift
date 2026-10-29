import Foundation

/// The artist's bounded native Flow Edge coordinates. No legacy shared controls,
/// alternate renderer, semantic warp, or physical placement enters this space.
package struct FlowArtistRecipe: Codable, Hashable, Sendable {
  package static let revision = "flow-artist-recipe-v1"
  package static let names = ["spacing", "minimumLength", "simplification", "tone",
    "coherence", "edgeThreshold", "rectilinearity", "toneSupport", "structureSupport",
    "evidenceScale", "seedIrregularity", "angularity"]
  package static let bounds: [ClosedRange<Double>] = [1...12, 0.5...18, 0.05...2.5,
    0...1.8, 0...4, 0.003...0.065, 0...1, 0...1, 0...1, 0...1, 0...1, 0...1]
  /// Fixed [0,1] coordinates are portable across fitting and rendering.
  package let values: [Double]

  package init(values: [Double]) {
    self.values = Self.names.indices.map { index in
      let value = index < values.count ? values[index] : 0.5
      return value.isFinite ? min(1, max(0, value)) : 0.5
    }
  }

  package static let standard = Self(nativeValues: [2, 3, 0.35, 0.7, 1, 0.012, 0, 0.4, 0, 0.5, 0, 0])

  private init(nativeValues: [Double]) {
    self.init(values: zip(nativeValues, Self.bounds).map { ($0 - $1.lowerBound) / ($1.upperBound - $1.lowerBound) })
  }

  package var vectorOptions: PortraitVectorOptions {
    let p = zip(values, Self.bounds).map { $1.lowerBound + $0 * ($1.upperBound - $1.lowerBound) }
    return PortraitVectorOptions(minimumContourLength: p[1], simplificationTolerance: p[2],
      hatchSpacing: Int(p[0].rounded()), tonalStrength: p[3], smoothing: p[4], sketchThreshold: p[5],
      flowRectilinearity: p[6], flowSupport: p[7], flowStructureSupport: p[8],
      flowSupportScale: p[9], flowSeedIrregularity: p[10],
      regionalTreatment: p[11] == 0 ? nil : .init(scope: .face, skinSuppression: 0,
        featureProtection: 0.7, angularity: p[11], shadowStrength: 0, contourEmphasis: 0))
  }

  /// A deterministic maximin panel includes recognizable endpoints, then fills
  /// uncovered native-coordinate space. Diversity is not an aesthetic score.
  package static func broad(count: Int, seed: UInt64) -> [Self] {
    let count = min(24, max(1, count))
    var random = FlowArtistRandom(seed: seed)
    var pool: [Self] = []
    for index in 0..<max(64, count * 16) {
      var values = names.map { _ in random.unit() }
      if index < 6 {
        values = standard.values
        values[6] = Double(index % 3) / 2
        values[11] = index < 3 ? 0 : 1
        values[3] = index.isMultiple(of: 2) ? 0.12 : 0.7
        values[2] = index < 3 ? 0.12 : 0.85
        values[4] = index < 3 ? 0.8 : 0.05
      }
      pool.append(Self(values: values))
    }
    var result = [standard]
    while result.count < count, !pool.isEmpty {
      let index = pool.indices.max { a, b in
        separation(pool[a], from: result) < separation(pool[b], from: result)
      }!
      let next = pool.remove(at: index)
      if !result.contains(next) { result.append(next) }
    }
    return result
  }

  /// The selected parent is always first and immutable. Reflection at bounds
  /// avoids collapsed clamp duplicates at the corners of the parameter space.
  package func refined(count: Int, seed: UInt64, radius: Double = 0.12) -> [Self] {
    let count = min(24, max(1, count)), radius = radius.isFinite ? min(0.35, max(0.005, radius)) : 0.12
    var random = FlowArtistRandom(seed: seed), result = [self]
    for _ in 0..<(count * 12) where result.count < count {
      let candidate = Self(values: values.map { value in
        let next = value + (random.unit() * 2 - 1) * radius
        return next < 0 ? -next : next > 1 ? 2 - next : next
      })
      if !result.contains(candidate) { result.append(candidate) }
    }
    return result
  }

  private static func separation(_ recipe: Self, from panel: [Self]) -> Double {
    panel.map { other in zip(recipe.values, other.values).enumerated().reduce(0.0) { sum, item in
      let weight = [2, 3, 4, 6, 11].contains(item.offset) ? 2.0 : 1.0
      return sum + weight * pow(item.element.0 - item.element.1, 2)
    } }.min() ?? 0
  }

  private enum CodingKeys: String, CodingKey { case values }
  package init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let values = try container.decode([Double].self, forKey: .values)
    guard values.count == Self.names.count, values.allSatisfy({ $0.isFinite && (0...1).contains($0) }) else {
      throw DecodingError.dataCorruptedError(forKey: .values, in: container, debugDescription: "Invalid Flow artist recipe coordinates")
    }
    self.values = values
  }
}

package struct FlowArtistRandom {
  private var state: UInt64
  package init(seed: UInt64) { state = seed }
  package mutating func next() -> UInt64 {
    state &+= 0x9e3779b97f4a7c15
    var value = state
    value = (value ^ (value >> 30)) &* 0xbf58476d1ce4e5b9
    value = (value ^ (value >> 27)) &* 0x94d049bb133111eb
    return value ^ (value >> 31)
  }
  package mutating func unit() -> Double { Double(next() >> 11) / 9_007_199_254_740_992 }
}
