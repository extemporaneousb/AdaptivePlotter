import Foundation
import PlotterModel

/// Historical archive receipts. Current authoring neither creates nor merges them.
struct PortraitExplorationRecord: Codable, Hashable, Sendable {
  static let maximumRecords = 64
  struct Offer: Codable, Hashable, Sendable {
    let index: Int
    let candidateID: String?
    let recipe: PortraitStyleRecipe?
    let programContentHash: String?
    let unavailableReason: String?
  }
  let traceSessionID: UUID
  let sequence: UInt64
  let roundID: UUID
  let policyRevision: String
  let seed: UInt64
  let variation: Double
  let centerID: String
  let sourceSHA256: String
  let offers: [Offer]
  let action: Action
  enum Action: Codable, Hashable, Sendable {
    case offered
    case selected(index: Int)
    case variation(Double)
    case back
  }

  static func validate(_ records: [Self]?, for candidate: PortraitCandidate) throws {
    guard let records else { return }
    guard !records.isEmpty, records.count <= Self.maximumRecords,
      records.contains(where: { $0.offers.contains(where: { $0.candidateID == candidate.id }) }) else {
      throw PortraitCandidateError.integrityMismatch
    }
    var lastSequence: [UUID: UInt64] = [:]
    for record in records {
      if let previous = lastSequence[record.traceSessionID], record.sequence <= previous {
        throw PortraitCandidateError.integrityMismatch
      }
      lastSequence[record.traceSessionID] = record.sequence
      let legacy = record.policyRevision == "portrait-neighborhood-v1"
      let slotCount = legacy ? 9 : 3
      let centerIndex = legacy ? 4 : 1
      guard legacy || record.policyRevision == "portrait-preference-v2"
        || record.policyRevision == "portrait-preference-v3"
        || record.policyRevision == "portrait-preference-v4" else {
        throw PortraitCandidateError.integrityMismatch
      }
      guard
        record.sourceSHA256 == candidate.sourceSHA256,
        record.variation.isFinite, (0...1).contains(record.variation),
        record.offers.map(\.index) == Array(0..<slotCount),
        record.offers[centerIndex].candidateID == record.centerID,
        let centerRecipe = record.offers[centerIndex].recipe else { throw PortraitCandidateError.integrityMismatch }
      for offer in record.offers {
        if offer.candidateID != nil {
          guard let recipe = offer.recipe, offer.programContentHash != nil,
            offer.unavailableReason == nil, recipe.style == centerRecipe.style,
            recipe.analysisOptions == centerRecipe.analysisOptions else {
            throw PortraitCandidateError.integrityMismatch
          }
        } else if offer.recipe != nil || offer.programContentHash != nil || offer.unavailableReason == nil {
          throw PortraitCandidateError.integrityMismatch
        }
      }
      switch record.action {
      case .selected(let index):
        guard (0..<slotCount).contains(index), record.offers[index].candidateID != nil else {
          throw PortraitCandidateError.integrityMismatch
        }
      case .variation(let value):
        guard value.isFinite, (0...1).contains(value) else { throw PortraitCandidateError.integrityMismatch }
      case .offered, .back: break
      }
    }
  }
}

enum PortraitExplorationPolicy {
  static let maximumAttemptsPerSlot = 2
  static let maximumHistoryRounds = 12
  static let maximumHistoryPoints = 400_000
  static let maximumRoundPoints = 200_000

  static func boundedVariation(_ value: Double) -> Double {
    value.isFinite ? min(1, max(0, value)) : 0.35
  }

  static func canonicalOptions(_ options: PortraitVectorOptions, style: PortraitStyle) -> PortraitVectorOptions {
    var result = options.bounded
    if style == .flowEdges {
      result.hatchSpacing = max(3, result.hatchSpacing)
      if (result.flowRectilinearity ?? 0) <= 0 { result.flowRectilinearity = nil }
    }
    return result
  }

  static func effectiveOptions(_ options: PortraitVectorOptions, center: PortraitCandidate) -> PortraitVectorOptions {
    let canonical = canonicalOptions(options, style: center.recipe.style)
    var effective = (try? canonical.materialContext?.adapting(canonical, raster: center.raster)) ?? canonical
    // Remember a disabled scale in the authored recipe, but do not spend render
    // attempts on it until either support layer can make it visible.
    if center.recipe.style == .flowEdges, !hasFlowSupport(effective) { effective.flowSupportScale = nil }
    return effective
  }

  enum Rejection: String, Sendable { case duplicateConfiguration, similarGeometry, noLines, detailBudget, renderFailure, rejectedAttempt }

  static func coordinates(_ options: PortraitVectorOptions) -> [Double] {
    let value = options.bounded
    return [(value.tonalStrength - 0.4) / 1.6, value.smoothing / 4,
      value.minimumContourLength / 40, value.simplificationTolerance / 3,
      Double(value.contourLevels - 1) / 11, Double(value.hatchSpacing - 1) / 15,
      (value.hatchAngleDegrees + 90) / 180, (value.sketchThreshold - 0.002) / 0.078,
      value.flowRectilinearity ?? 0, value.flowSupport ?? 0,
      value.flowStructureSupport ?? 0, hasFlowSupport(value) ? value.flowSupportScale ?? 0 : 0,
      value.flowSeedIrregularity ?? 0]
  }

  private static func hasFlowSupport(_ options: PortraitVectorOptions) -> Bool {
    (options.flowSupport ?? 0) > 0 || (options.flowStructureSupport ?? 0) > 0
  }

  private static func dimensions(for center: PortraitCandidate) -> [Dimension] {
    var dimensions: [Dimension] = [.tone, .smoothing]
    if center.recipe.style != .hatch && center.recipe.style != .crosshatch {
      dimensions += [.minimumLength]
      if center.recipe.style != .flowEdges { dimensions += [.simplification] }
    }
    if center.recipe.style == .contours { dimensions += [.levels] }
    if center.recipe.style == .flowEdges {
      dimensions += [.rectilinearity, .support, .structureSupport, .seedIrregularity]
      if hasFlowSupport(center.recipe.vectorOptions.bounded) { dimensions += [.supportScale] }
    }
    if [.hatch, .crosshatch, .sketchHatch, .flowEdges].contains(center.recipe.style) {
      dimensions += [.spacing]
      if center.recipe.style != .flowEdges { dimensions += [.angle] }
    }
    if [.sketch, .sketchHatch, .flowEdges].contains(center.recipe.style) { dimensions += [.threshold] }
    let effective = effectiveOptions(center.recipe.vectorOptions, center: center)
    if effective.minimumContourLength >= 40 { dimensions.removeAll { $0 == .minimumLength } }
    if effective.hatchSpacing >= 16 { dimensions.removeAll { $0 == .spacing } }
    return dimensions
  }

  /// One deterministic request. Failure recovery has its own bounded second attempt.
  static func recipe(around center: PortraitCandidate, seed: UInt64) -> PortraitStyleRecipe {
    let base = canonicalOptions(center.recipe.vectorOptions, style: center.recipe.style)
    var random = Generator(state: seed)
    let axes = dimensions(for: center)
    let forms: [Dimension] = [.rectilinearity, .support, .structureSupport, .seedIrregularity]
    let axis = center.recipe.style == .flowEdges && seed.isMultiple(of: 3)
      ? forms[Int((seed / 3) % UInt64(forms.count))] : axes[Int(random.next() % UInt64(axes.count))]
    let sign = random.next() & 1 == 0 ? -1.0 : 1.0
    var vectors = base
    move(axis, vectors: &vectors, delta: sign * 0.35, center: center)
    vectors = distinctOptions(preferred: vectors, base: base, center: center,
      axes: axes, radius: 0.35, random: &random, excluding: [effectiveOptions(base, center: center)])
    return PortraitStyleRecipe(id: "preference-\(seed)", title: center.recipe.title, seed: seed,
      style: center.recipe.style, vectorOptions: canonicalOptions(vectors, style: center.recipe.style),
      analysisOptions: center.recipe.analysisOptions)
  }

  /// Cross effective parameter buckets instead of spending render attempts below
  /// a material floor or on a value the renderer rounds straight back to center.
  private static func move(_ axis: Dimension, vectors: inout PortraitVectorOptions,
    delta: Double, center: PortraitCandidate) {
    guard delta != 0 else { return }
    let effective = effectiveOptions(vectors, center: center)
    let sign = delta < 0 ? -1.0 : 1.0
    if axis == .spacing {
      var floorOptions = vectors; floorOptions.hatchSpacing = 1; floorOptions.minimumContourLength = 0
      let floor = max(center.recipe.style == .flowEdges ? 3 : 1,
        effectiveOptions(floorOptions, center: center).hatchSpacing)
      guard floor < 16 else { return }
      let start = min(16, max(floor, effective.hatchSpacing))
      let jump = max(2, Int((abs(delta) * 8).rounded()))
      let proposed = start + Int(sign) * jump
      vectors.hatchSpacing = min(16, max(floor,
        (floor...16).contains(proposed) ? proposed : start - Int(sign) * jump))
    } else if axis == .minimumLength {
      vectors.minimumContourLength = min(40, effective.minimumContourLength)
      axis.move(&vectors, delta: sign * max(abs(delta), 0.3))
      if effectiveOptions(vectors, center: center).minimumContourLength == effective.minimumContourLength {
        vectors.minimumContourLength = min(40, effective.minimumContourLength + max(2, abs(delta) * 8))
      }
    } else if axis == .rectilinearity {
      let current = vectors.flowRectilinearity ?? 0
      let choices = sign > 0 ? [0.5, 1.0, 0.0] : [0.0, 0.5, 1.0]
      let next = choices.first { abs($0 - current) >= 0.4 } ?? 0
      vectors.flowRectilinearity = next == 0 ? nil : next
    } else if [.support, .structureSupport, .supportScale, .seedIrregularity].contains(axis) {
      if axis == .supportScale, !hasFlowSupport(vectors) { return }
      let floor = axis == .seedIrregularity ? 0.4 : axis == .structureSupport ? 0.3 : 0.35
      axis.move(&vectors, delta: sign * max(abs(delta), floor))
    } else {
      // Minimum perceptible probes remain independent of the hidden trust step.
      let floor = axis == .smoothing ? 0.34 : axis == .tone ? 0.25 : 0.12
      axis.move(&vectors, delta: sign * max(abs(delta), floor))
    }
  }

  static func recoveryRecipe(around center: PortraitCandidate, failed: PortraitStyleRecipe,
    rejection: Rejection, neighbor: Int, seed: UInt64, variation: Double,
    excluding: Set<PortraitVectorOptions> = []) -> PortraitStyleRecipe {
    let base = canonicalOptions(center.recipe.vectorOptions, style: center.recipe.style)
    let current = coordinates(base), failedCoordinates = coordinates(failed.vectorOptions)
    var state = seed ^ (UInt64(max(0, neighbor)) &* 0x9e3779b97f4a7c15)
    for coordinate in failedCoordinates { state = (state ^ coordinate.bitPattern) &* 1_099_511_628_211 }
    for byte in rejection.rawValue.utf8 { state = (state ^ UInt64(byte)) &* 1_099_511_628_211 }
    var random = Generator(state: state)
    let shuffled = Self.shuffled(dimensions(for: center), random: &random)
    // A failed axis gets lower priority than a different source of geometry.
    let unchanged = shuffled.filter { abs(current[$0.rawValue] - failedCoordinates[$0.rawValue]) < 1e-8 }
    let changed = shuffled.filter { abs(current[$0.rawValue] - failedCoordinates[$0.rawValue]) >= 1e-8 }
    let axes = (unchanged + changed).filter {
      rejection != .noLines || ($0 != .minimumLength && $0 != .threshold)
    }
    let amount = boundedVariation(variation)
    let radius = (0.35 + amount * 0.65) * (0.85 + Double(random.next() % 301) / 1000)
    let sign = random.next() & 1 == 0 ? -1.0 : 1.0
    var vectors = base
    if rejection == .noLines {
      // Recover toward more source evidence, never weaken the material floor.
      let reduction = 0.82 - amount * 0.3
      vectors.minimumContourLength *= reduction
      vectors.sketchThreshold = max(0.002, vectors.sketchThreshold * reduction)
      if center.recipe.style == .contours { move(.levels, vectors: &vectors, delta: sign * radius, center: center) }
    }
    if let axis = axes.first { move(axis, vectors: &vectors, delta: sign * radius, center: center) }
    var blocked = excluding
    blocked.insert(effectiveOptions(base, center: center))
    blocked.insert(effectiveOptions(failed.vectorOptions, center: center))
    vectors = distinctOptions(preferred: vectors, base: base, center: center,
      axes: axes, radius: radius, random: &random, excluding: blocked, preserveAxisOrder: true)
    return PortraitStyleRecipe(id: "recovery-\(seed)-\(neighbor)", title: center.recipe.title,
      seed: seed, style: center.recipe.style,
      vectorOptions: canonicalOptions(vectors, style: center.recipe.style), analysisOptions: center.recipe.analysisOptions)
  }

  /// Probe only parameter values, never a hidden image pool. The work is at most
  /// twice the active-axis count; the caller still permits two renders per slot.
  private static func distinctOptions(preferred: PortraitVectorOptions, base: PortraitVectorOptions,
    center: PortraitCandidate, axes: [Dimension], radius: Double, random: inout Generator,
    excluding: Set<PortraitVectorOptions>, preserveAxisOrder: Bool = false) -> PortraitVectorOptions {
    let canonical = canonicalOptions(preferred, style: center.recipe.style)
    if !excluding.contains(effectiveOptions(canonical, center: center)) { return canonical }
    let order = preserveAxisOrder ? axes : shuffled(axes, random: &random)
    for axis in order {
      let sign = random.next() & 1 == 0 ? -1.0 : 1.0
      let distance = radius * (0.85 + Double(random.next() % 301) / 1000)
      for direction in [sign, -sign] {
        var candidate = base
        move(axis, vectors: &candidate, delta: direction * distance, center: center)
        candidate = canonicalOptions(candidate, style: center.recipe.style)
        if !excluding.contains(effectiveOptions(candidate, center: center)) { return candidate }
      }
    }
    return canonical
  }

  private static func shuffled(_ axes: [Dimension], random: inout Generator) -> [Dimension] {
    var result = axes
    for index in stride(from: result.count - 1, through: 1, by: -1) {
      result.swapAt(index, Int(random.next() % UInt64(index + 1)))
    }
    return result
  }

  static func pointCount(_ candidate: PortraitCandidate) -> Int {
    candidate.program.strokes.reduce(0) { $0 + $1.path.points.count }
  }

  /// A bounded preview occupancy map makes subpixel path perturbations inert.
  /// Samples are capped per segment and pen width is represented at preview scale.
  struct VisibleGeometry: Sendable {
    let ink: [UInt64]
    let nearbyInk: [UInt64]
    let inkCount: Int
    static let side = 128

    init(_ program: DrawingProgram) {
      let scale = Double(Self.side - 1) / max(program.fieldExtent.width, program.fieldExtent.height)
      var ink = [UInt64](repeating: 0, count: Self.side * Self.side / 64)
      for stroke in program.strokes {
        let radius = min(3, max(0, Int((stroke.style.nominalLineWidth * scale / 2).rounded())))
        for (a, b) in zip(stroke.path.points, stroke.path.points.dropFirst()) {
          let ax = a.x * scale, ay = a.y * scale, bx = b.x * scale, by = b.y * scale
          let count = min(256, max(1, Int(ceil(max(abs(bx - ax), abs(by - ay))))))
          for step in 0...count {
            let t = Double(step) / Double(count)
            let x = Int((ax + (bx - ax) * t).rounded()), y = Int((ay + (by - ay) * t).rounded())
            for dy in -radius...radius { for dx in -radius...radius {
              let px = x + dx, py = y + dy
              if (0..<Self.side).contains(px), (0..<Self.side).contains(py) {
                let cell = py * Self.side + px
                ink[cell >> 6] |= UInt64(1) << (cell & 63)
              }
            } }
          }
        }
      }
      self.ink = ink
      inkCount = ink.reduce(0) { $0 + $1.nonzeroBitCount }
      var nearby = [UInt64](repeating: 0, count: ink.count)
      // Two words per row; explicit carries preserve x=63/64 and prevent a
      // horizontal shift from wrapping between image rows.
      for y in 0..<Self.side {
        let left = ink[y * 2], right = ink[y * 2 + 1]
        let a = left | (left << 1) | (left >> 1) | (right << 63)
        let b = right | (right << 1) | (right >> 1) | (left >> 63)
        for row in max(0, y - 1)...min(Self.side - 1, y + 1) {
          nearby[row * 2] |= a; nearby[row * 2 + 1] |= b
        }
      }
      nearbyInk = nearby
    }

    func isMeaningfullyDifferent(from other: Self) -> Bool {
      var changed = 0
      for i in ink.indices {
        changed += (ink[i] & ~other.nearbyInk[i]).nonzeroBitCount
          + (other.ink[i] & ~nearbyInk[i]).nonzeroBitCount
      }
      // Require at least six independently visible samples and three percent of
      // the total ink support. This is a visual-distance floor, not a quality score.
      return changed >= max(6, Int(ceil(Double(inkCount + other.inkCount) * 0.03)))
    }
  }

  private struct Generator {
    var state: UInt64
    mutating func next() -> UInt64 {
      state &+= 0x9e3779b97f4a7c15
      var z = state
      z = (z ^ (z >> 30)) &* 0xbf58476d1ce4e5b9
      z = (z ^ (z >> 27)) &* 0x94d049bb133111eb
      return z ^ (z >> 31)
    }
  }

  private enum Dimension: Int, CaseIterable {
    case tone, smoothing, minimumLength, simplification, levels, spacing, angle, threshold, rectilinearity
    case support, structureSupport, supportScale, seedIrregularity
    func move(_ value: inout PortraitVectorOptions, delta: Double) {
      switch self {
      case .tone: value.tonalStrength = reflect(value.tonalStrength + delta * 0.8, 0.4...2)
      case .smoothing: value.smoothing = reflect(value.smoothing + delta * 2, 0...4)
      case .minimumLength: value.minimumContourLength = reflect(value.minimumContourLength + delta * 8, 0...40)
      case .simplification: value.simplificationTolerance = reflect(value.simplificationTolerance + delta * 1.5, 0...3)
      case .levels: value.contourLevels = Int(reflect(Double(value.contourLevels) + delta * 6, 1...12).rounded())
      case .spacing: value.hatchSpacing = Int(reflect(Double(value.hatchSpacing) + delta * 8, 1...16).rounded())
      case .angle: value.hatchAngleDegrees = reflect(value.hatchAngleDegrees + delta * 90, -90...90)
      case .threshold: value.sketchThreshold = reflect(value.sketchThreshold + delta * 0.01, 0.002...0.08)
      case .rectilinearity: value.flowRectilinearity = reflect((value.flowRectilinearity ?? 0) + delta, 0...1)
      case .support: value.flowSupport = reflect((value.flowSupport ?? 0) + delta, 0...1)
      case .structureSupport: value.flowStructureSupport = reflect((value.flowStructureSupport ?? 0) + delta, 0...1)
      case .supportScale: value.flowSupportScale = reflect((value.flowSupportScale ?? 0) + delta, 0...1)
      case .seedIrregularity: value.flowSeedIrregularity = reflect((value.flowSeedIrregularity ?? 0) + delta, 0...1)
      }
    }
    private func reflect(_ value: Double, _ range: ClosedRange<Double>) -> Double {
      let width = range.upperBound - range.lowerBound
      var offset = (value - range.lowerBound).truncatingRemainder(dividingBy: width * 2)
      if offset < 0 { offset += width * 2 }
      return range.lowerBound + (offset <= width ? offset : width * 2 - offset)
    }
  }
}
