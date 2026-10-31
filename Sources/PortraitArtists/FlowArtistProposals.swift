import Foundation

/// Exactly N render proposals, selected from cheap recipe candidates. Themes
/// cover coordinated mechanisms; distance uses effective controls, not dead
/// simplification ranges. At most two slots use the learned recipe/photo terms.
package enum FlowArtistProposals {
  package static let revision = "flow-themed-proposals-v1"
  package static let themes: [FlowArtistRecipe] = [
    .init(nativeValues: [3, 4, 0.15, 0, 1, 0.018, 0, 0.3, 0.3, 0.5, 0.2, 0]),
    .init(nativeValues: [4, 5, 0.18, 1.15, 2.6, 0.014, 0, 0.25, 0.25, 0.45, 0.3, 0]),
    .init(nativeValues: [5, 6, 0.2, 1.1, 1.8, 0.015, 1, 0.3, 0.2, 0.5, 0.1, 0.2]),
    .init(nativeValues: [4, 4, 0.2, 1.25, 0.5, 0.016, 0.1, 0.2, 0.2, 0.5, 0.2, 0.95],
      marks: .init(polygon: 0.95, scale: 0.7)),
    .init(nativeValues: [4, 4, 0.15, 1.1, 1.4, 0.014, 0, 0.15, 0.15, 0.4, 0.4, 0.1],
      marks: .init(wave: 1, scale: 0.45)),
    .init(nativeValues: [5, 3, 0.15, 1.15, 1.5, 0.016, 0, 0.12, 0.2, 0.5, 0.4, 0],
      marks: .init(loop: 1, scale: 0.8)),
    .init(nativeValues: [5, 3, 0.18, 1.1, 1.5, 0.018, 0, 0.1, 0.2, 0.5, 0.3, 0.5],
      marks: .init(polygon: 0.7, loop: 1, scale: 0.8)),
    .init(nativeValues: [4, 5, 0.2, 1.1, 1.8, 0.016, 0.3, 0.2, 0.25, 0.5, 0.5, 0.4],
      marks: .init(wave: 0.35, polygon: 0.35, loop: 0.35, scale: 0.5))
  ]

  package static func broad(count: Int, seed: UInt64) -> [FlowArtistRecipe] {
    (try? propose(count: count, seed: seed, parent: nil, raster: nil, checkpoint: nil)) ?? [.standard]
  }

  package static func propose(count: Int, seed: UInt64, parent: FlowArtistRecipe?,
    raster: PortraitRaster?, checkpoint: FlowArtistCheckpoint?
  ) throws -> [FlowArtistRecipe] {
    let count = min(24, max(1, count))
    if let checkpoint { try checkpoint.validateForInference() }
    var random = FlowArtistRandom(seed: seed)
    var pool: [FlowArtistRecipe] = [], selected: [FlowArtistRecipe] = []
    let guidedCount = checkpoint?.ranker == nil || raster == nil ? 0 : min(2, max(1, count / 4))
    if let parent {
      selected = [parent]
      pool = Array(parent.refined(count: 24, seed: seed, radius: 0.12).dropFirst())
    } else {
      var order = Array(themes.indices)
      for index in order.indices.reversed() where index > 0 {
        order.swapAt(index, Int(random.next() % UInt64(index + 1)))
      }
      // Seed chooses the starting family, not a random cluster. Fill the theme
      // order by effective-control maximin so even a three-slot panel separates
      // mechanisms instead of showing three similar loop mixtures.
      var remaining = Array(order.dropFirst()), spread = [order[0]]
      while !remaining.isEmpty {
        let next = remaining.indices.max { a, b in
          separation(themes[remaining[a]], spread.map { themes[$0] })
            < separation(themes[remaining[b]], spread.map { themes[$0] })
        }!
        spread.append(remaining.remove(at: next))
      }
      order = spread
      let coverage = min(themes.count, max(1, count - guidedCount))
      for index in order.prefix(coverage) {
        // Retain the theme's identity while varying its effective controls.
        // Repeated eight-slot rounds must not merely reorder eight fixed images.
        var x = themes[index].coordinates
        let amplitudes = [0.08, 0.07, 0.02, 0.08, 0.10, 0.04, 0.08, 0.08,
          0.08, 0.10, 0.15, 0.08, 0.06, 0.06, 0.06, 0.12]
        for i in x.indices {
          if x[i] == 0 && [3, 6, 12, 13, 14].contains(i) { continue }
          x[i] = min(1, max(0, x[i] + (random.unit() * 2 - 1) * amplitudes[i]))
        }
        selected.append(adapt(recipe(x), raster: raster))
      }
      for index in 0..<128 {
        let a = themes[order[index % order.count]]
        let b = themes[Int(random.next() % UInt64(themes.count))]
        let mix = index.isMultiple(of: 3) ? 0.15 + random.unit() * 0.45 : 0
        var coordinates = zip(a.coordinates, b.coordinates).map { $0 * (1 - mix) + $1 * mix }
        for i in coordinates.indices {
          // Structural fairing has a 0.3px cap. Explore its effective range
          // instead of spending most proposals above the identical cap.
          let noise = (random.unit() * 2 - 1) * (i == 2 ? 0.025 : 0.065)
          coordinates[i] = min(1, max(0, coordinates[i] + noise))
        }
        if a.values[3] == 0 && mix == 0 { coordinates[3] = 0 }
        pool.append(adapt(recipe(coordinates), raster: raster))
      }
    }
    var guidedRemaining = guidedCount
    while selected.count < count, !pool.isEmpty {
      try Task.checkCancellation()
      pool.removeAll { selected.contains($0) }
      guard !pool.isEmpty else { break }
      let index: Int
      if guidedRemaining > 0, selected.count >= count - guidedCount,
        let checkpoint, let raster {
        let scores = try pool.map { try checkpoint.score(features: FlowArtistFeatures.proposal(recipe: $0, raster: raster)) }
        let eligible = pool.indices.filter { separation(pool[$0], selected) > 0.025 }
        index = (eligible.isEmpty ? Array(pool.indices) : eligible).max { scores[$0] < scores[$1] }!
        guidedRemaining -= 1
      } else {
        index = pool.indices.max { separation(pool[$0], selected) < separation(pool[$1], selected) }!
      }
      selected.append(pool.remove(at: index))
    }
    return selected
  }

  /// Mild image conditioning respects the source's contrast and dark-area load.
  /// These are bounded renderer heuristics, not inferred personal preferences.
  package static func adapt(_ recipe: FlowArtistRecipe, raster: PortraitRaster?) -> FlowArtistRecipe {
    guard let raster else { return recipe }
    let source = FlowArtistFeatures.source(raster: raster)
    var values = recipe.values
    let spacing = 1 + values[0] * 11
    values[0] = min(1, max(0, (spacing * (0.85 + source[3] * 0.55) - 1) / 11))
    let threshold = 0.003 + values[5] * 0.062
    let contrast = min(1.3, max(0.55, source[1] / 0.22))
    values[5] = min(1, max(0, (threshold * contrast - 0.003) / 0.062))
    return .init(values: values, marks: recipe.marks)
  }

  private static func recipe(_ coordinates: [Double]) -> FlowArtistRecipe {
    .init(values: Array(coordinates.prefix(12)),
      marks: .init(wave: coordinates[12], polygon: coordinates[13], loop: coordinates[14], scale: coordinates[15]))
  }
  private static func effective(_ recipe: FlowArtistRecipe) -> [Double] {
    var x = recipe.coordinates
    x[0] = (max(3, (1 + x[0] * 11).rounded()) - 3) / 9
    x[2] = min(1, x[2] * 2.45 / 0.25)
    if x[3] == 0 {
      for i in [0, 4, 6, 7, 10, 12, 13, 14, 15] { x[i] = 0 }
    }
    if x[7] == 0 && x[8] == 0 { x[9] = 0 }
    return x
  }
  private static func separation(_ recipe: FlowArtistRecipe, _ selected: [FlowArtistRecipe]) -> Double {
    let coordinates = effective(recipe)
    return selected.map { other in
      zip(coordinates, effective(other)).enumerated().reduce(0.0) {
        $0 + pow($1.element.0 - $1.element.1, 2) * ([3, 6, 11, 12, 13, 14].contains($1.offset) ? 2 : 1)
      }
    }.min() ?? 1
  }
}
