import Foundation
import PlotterModel

struct PortraitExplorationSlot: Identifiable, Sendable {
  let index: Int
  let candidate: PortraitCandidate?
  let unavailableReason: String?
  var id: Int { index }
}

/// A settled offer is immutable. Back owns these actual candidates, independent
/// of the render cache; a new round cannot replace an active tile in place.
struct PortraitExplorationRound: Identifiable, Sendable {
  let id: UUID
  let seed: UInt64
  let variation: Double
  let center: PortraitCandidate
  let slots: [PortraitExplorationSlot]
}

/// Small recipe/choice receipts live with explicitly retained candidates. They
/// are investigation evidence, not labels, a trained model, or a second store.
struct PortraitExplorationRecord: Codable, Hashable, Sendable {
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
    guard !records.isEmpty, records.count <= PortraitExplorationPolicy.maximumRecords,
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
      let slotCount = legacy ? 9 : PortraitExplorationPolicy.slotCount
      let centerIndex = legacy ? 4 : PortraitExplorationPolicy.centerIndex
      guard legacy || record.policyRevision == PortraitExplorationPolicy.revision else {
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

  /// Same-session sequence order survives an asynchronous older handoff save.
  /// Suffix truncation happens after ordering, so dropped older receipts cannot
  /// be appended after newer ones or evict them from the bounded record.
  static func merging(_ existing: [Self]?, with incoming: [Self]) -> [Self] {
    var sessions: [UUID] = []
    var records: [UUID: [UInt64: Self]] = [:]
    for record in (existing ?? []) + incoming {
      if records[record.traceSessionID] == nil {
        sessions.append(record.traceSessionID)
        records[record.traceSessionID] = [:]
      }
      if records[record.traceSessionID]?[record.sequence] == nil {
        records[record.traceSessionID]?[record.sequence] = record
      }
    }
    let ordered = sessions.flatMap { session in
      (records[session] ?? [:]).sorted { $0.key < $1.key }.map(\.value)
    }
    return Array(ordered.suffix(PortraitExplorationPolicy.maximumRecords))
  }

  init(round: PortraitExplorationRound, action: Action, traceSessionID: UUID, sequence: UInt64) {
    self.traceSessionID = traceSessionID; self.sequence = sequence
    roundID = round.id; policyRevision = PortraitExplorationPolicy.revision
    seed = round.seed; variation = round.variation; centerID = round.center.id
    sourceSHA256 = round.center.sourceSHA256; self.action = action
    offers = round.slots.map { .init(index: $0.index, candidateID: $0.candidate?.id,
      recipe: $0.candidate?.recipe, programContentHash: $0.candidate?.program.contentHash.description,
      unavailableReason: $0.unavailableReason) }
  }
}

/// Session-local ordinal preference search. The step is internal; a choice is
/// directional evidence, not a measured utility gradient or a trained model.
struct PortraitExplorationSearchState: Equatable, Sendable {
  var step = 0.35
  var direction: [Double]?

  mutating func prefer(_ selected: PortraitVectorOptions, over current: PortraitVectorOptions) {
    let delta = zip(PortraitExplorationPolicy.coordinates(selected),
      PortraitExplorationPolicy.coordinates(current)).map { $0.0 - $0.1 }
    let length = sqrt(delta.reduce(0) { $0 + $1 * $1 })
    guard length > 1e-8 else {
      step = max(0.12, step * 0.7)
      direction = nil
      return
    }
    let next = delta.map { $0 / length }
    if let direction {
      let alignment = zip(direction, next).reduce(0) { $0 + $1.0 * $1.1 }
      if alignment > 0.65 { step = min(0.75, step * 1.3) }
      else if alignment < 0 { step = max(0.12, step * 0.7) }
    }
    direction = next
  }
}

enum PortraitExplorationPolicy {
  static let revision = "portrait-preference-v2"
  static let slotCount = 3
  static let centerIndex = 1
  static let neighborIndices = [0, 2]
  static let maximumAttemptsPerSlot = 2
  static let maximumHistoryRounds = 12
  static let maximumHistoryPoints = 400_000
  static let maximumRoundPoints = 200_000
  static let maximumRecords = 64

  static func boundedVariation(_ value: Double) -> Double {
    value.isFinite ? min(1, max(0, value)) : 0.35
  }

  static func canonicalOptions(_ options: PortraitVectorOptions, style: PortraitStyle) -> PortraitVectorOptions {
    var result = options.bounded
    if style == .flowEdges { result.hatchSpacing = max(3, result.hatchSpacing) }
    return result
  }

  static func coordinates(_ options: PortraitVectorOptions) -> [Double] {
    let value = options.bounded
    return [(value.tonalStrength - 0.4) / 1.6, value.smoothing / 4,
      value.minimumContourLength / 40, value.simplificationTolerance / 3,
      Double(value.contourLevels - 1) / 11, Double(value.hatchSpacing - 1) / 15,
      (value.hatchAngleDegrees + 90) / 180, (value.sketchThreshold - 0.002) / 0.078]
  }

  /// Two purposeful directions, each with one bounded retry. A successful
  /// direction continues; the other probes a complementary axis. No hidden pool.
  static func recipes(around center: PortraitCandidate, variation: Double,
    seed: UInt64, direction: [Double]? = nil) -> [[PortraitStyleRecipe]] {
    let base = canonicalOptions(center.recipe.vectorOptions, style: center.recipe.style)
    var random = Generator(state: seed)
    let amount = boundedVariation(variation)
    var dimensions: [Dimension] = [.tone, .smoothing]
    if center.recipe.style != .hatch && center.recipe.style != .crosshatch {
      dimensions += [.minimumLength]
      if center.recipe.style != .flowEdges { dimensions += [.simplification] }
    }
    if center.recipe.style == .contours { dimensions += [.levels] }
    if [.hatch, .crosshatch, .sketchHatch, .flowEdges].contains(center.recipe.style) {
      dimensions += [.spacing]
      if center.recipe.style != .flowEdges { dimensions += [.angle] }
    }
    if [.sketch, .sketchHatch, .flowEdges].contains(center.recipe.style) { dimensions += [.threshold] }
    let effective = (try? base.materialContext?.adapting(base, raster: center.raster)) ?? base
    if effective.minimumContourLength >= 40 { dimensions.removeAll { $0 == .minimumLength } }
    if effective.hatchSpacing >= 16 { dimensions.removeAll { $0 == .spacing } }
    let phase = Int(random.next() % UInt64(dimensions.count))
    let primary = dimensions[phase]
    let complementary: Dimension
    if let direction, direction.count == Dimension.allCases.count {
      let rotated = (0..<dimensions.count).map { dimensions[(phase + $0) % dimensions.count] }
      complementary = rotated.min { abs(direction[$0.rawValue]) < abs(direction[$1.rawValue]) }!
    } else { complementary = dimensions[(phase + 1) % dimensions.count] }
    let sign = random.next() & 1 == 0 ? -1.0 : 1.0
    return (0..<2).map { neighbor in
      (0..<maximumAttemptsPerSlot).map { attempt in
        var vectors = base
        let radius = amount * (attempt == 0 ? 1 : 1.65)
        if neighbor == 0, let direction, direction.count == Dimension.allCases.count {
          for axis in dimensions { axis.move(&vectors, delta: direction[axis.rawValue] * radius) }
        } else {
          let axis = neighbor == 0 ? primary : complementary
          axis.move(&vectors, delta: sign * (neighbor == 0 ? 1 : -1) * radius)
        }
        // If a single axis is visually inert, the retry changes an additional
        // image-relevant control without multiplying the number of evaluations.
        if attempt > 0 {
          let axis = dimensions[(phase + neighbor + 2) % dimensions.count]
          axis.move(&vectors, delta: -sign * radius * 0.6)
        }
        return PortraitStyleRecipe(id: "preference-\(seed)-\(neighbor)-\(attempt)",
          title: center.recipe.title, seed: seed, style: center.recipe.style,
          vectorOptions: canonicalOptions(vectors, style: center.recipe.style), analysisOptions: center.recipe.analysisOptions)
      }
    }
  }

  static func pointCount(_ candidate: PortraitCandidate) -> Int {
    candidate.program.strokes.reduce(0) { $0 + $1.path.points.count }
  }

  /// A bounded preview occupancy map makes subpixel path perturbations inert.
  /// Samples are capped per segment and pen width is represented at preview scale.
  struct VisibleGeometry: Sendable {
    let ink: Set<Int>
    let nearbyInk: Set<Int>
    static let side = 128

    init(_ program: DrawingProgram) {
      let scale = Double(Self.side - 1) / max(program.fieldExtent.width, program.fieldExtent.height)
      var ink = Set<Int>()
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
                ink.insert(py * Self.side + px)
              }
            } }
          }
        }
      }
      self.ink = ink
      var nearby = ink
      for cell in ink {
        let x = cell % Self.side, y = cell / Self.side
        for dy in -1...1 { for dx in -1...1 {
          let px = x + dx, py = y + dy
          if (0..<Self.side).contains(px), (0..<Self.side).contains(py) {
            nearby.insert(py * Self.side + px)
          }
        } }
      }
      nearbyInk = nearby
    }

    func isMeaningfullyDifferent(from other: Self) -> Bool {
      let changed = ink.subtracting(other.nearbyInk).count + other.ink.subtracting(nearbyInk).count
      // Require at least six independently visible samples and three percent of
      // the total ink support. This is a visual-distance floor, not a quality score.
      return changed >= max(6, Int(ceil(Double(ink.count + other.ink.count) * 0.03)))
    }
  }

  /// Exact path identity remains useful for archive/tests, independent of IDs.
  static func geometryIdentity(_ program: DrawingProgram) -> String {
    let scale = 10_000 / program.fieldExtent.height
    let paths = program.strokes.map { stroke -> String in
      let points = stroke.path.points.map { "\(Int64(($0.x * scale).rounded())),\(Int64(($0.y * scale).rounded()))" }
      let forward = points.joined(separator: ";"), reverse = points.reversed().joined(separator: ";")
      return min(forward, reverse)
    }.sorted().joined(separator: "|")
    return PortraitCandidateCoding.digest(Data(paths.utf8))
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
    case tone, smoothing, minimumLength, simplification, levels, spacing, angle, threshold
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
