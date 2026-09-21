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
      guard record.policyRevision == PortraitExplorationPolicy.revision,
        record.sourceSHA256 == candidate.sourceSHA256,
        record.variation.isFinite, (0...1).contains(record.variation),
        record.offers.map(\.index) == Array(0..<9),
        record.offers[4].candidateID == record.centerID,
        let centerRecipe = record.offers[4].recipe else { throw PortraitCandidateError.integrityMismatch }
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
        guard (0..<9).contains(index), record.offers[index].candidateID != nil else {
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

enum PortraitExplorationPolicy {
  static let revision = "portrait-neighborhood-v1"
  static let neighborIndices = [0, 1, 2, 3, 5, 6, 7, 8]
  static let maximumAttemptsPerSlot = 3
  static let maximumHistoryRounds = 12
  static let maximumHistoryPoints = 400_000
  static let maximumRoundPoints = 200_000
  static let maximumRecords = 64

  static func boundedVariation(_ value: Double) -> Double {
    value.isFinite ? min(1, max(0, value)) : 0.35
  }

  /// Three fixed attempt recipes for each of eight slots. Nearby single-axis,
  /// coupled and broader moves all scale with the manual spread. Reflection
  /// keeps moves useful at bounds instead of piling them up on a clamp.
  static func recipes(around center: PortraitCandidate, variation: Double,
    seed: UInt64) -> [[PortraitStyleRecipe]] {
    let base = center.recipe.vectorOptions.bounded
    var random = Generator(state: seed)
    let amount = boundedVariation(variation)
    var dimensions: [Dimension] = [.tone, .smoothing]
    if center.recipe.style != .hatch && center.recipe.style != .crosshatch {
      dimensions += [.minimumLength, .simplification]
    }
    if center.recipe.style == .contours { dimensions += [.levels] }
    if [.hatch, .crosshatch, .sketchHatch].contains(center.recipe.style) {
      dimensions += [.spacing, .angle]
    }
    if [.sketch, .sketchHatch].contains(center.recipe.style) { dimensions += [.threshold] }
    // Preserve the material snapshot and exclude axes completely hidden by its
    // floor. Other floor collisions are caught by effective geometry comparison.
    let effective = (try? base.materialContext?.adapting(base, raster: center.raster)) ?? base
    if effective.minimumContourLength >= 40 { dimensions.removeAll { $0 == .minimumLength } }
    if effective.hatchSpacing >= 16 { dimensions.removeAll { $0 == .spacing } }
    let phase = Int(random.next() % UInt64(dimensions.count))
    var recipes = (0..<8).map { slot in
      (0..<maximumAttemptsPerSlot).map { attempt in
        var vectors = base
        let radius = slot < 3 ? 0.35 : slot < 6 ? 0.65 : 1.0
        let axes = slot < 3 && attempt == 0
          ? [dimensions[(phase + slot) % dimensions.count]] : dimensions
        for axis in axes {
          let delta = (random.unit() * 0.65 + 0.35) * (random.next() & 1 == 0 ? -1 : 1)
          axis.move(&vectors, delta: delta * amount * radius)
        }
        return PortraitStyleRecipe(id: "exploration-\(seed)-\(slot)-\(attempt)",
          title: center.recipe.title, seed: seed, style: center.recipe.style,
          vectorOptions: vectors.bounded, analysisOptions: center.recipe.analysisOptions)
      }
    }
    // The mix is stable, but its positions carry no persistent direction or
    // spread meaning. Shuffle whole retry lists with the same seeded generator.
    for index in stride(from: recipes.count - 1, through: 1, by: -1) {
      recipes.swapAt(index, Int(random.next() % UInt64(index + 1)))
    }
    return recipes
  }

  static func pointCount(_ candidate: PortraitCandidate) -> Int {
    candidate.program.strokes.reduce(0) { $0 + $1.path.points.count }
  }

  /// Compare visible paths, not producer IDs or parameter provenance. Quantize
  /// at 1/10000 of the drawing height; reverse/order-only changes are identical.
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
    mutating func unit() -> Double { Double(next() >> 11) / 9_007_199_254_740_992 }
  }

  private enum Dimension {
    case tone, smoothing, minimumLength, simplification, levels, spacing, angle, threshold
    func move(_ value: inout PortraitVectorOptions, delta: Double) {
      switch self {
      case .tone: value.tonalStrength = reflect(value.tonalStrength + delta * 0.8, 0.4...2)
      case .smoothing: value.smoothing = reflect(value.smoothing + delta * 2, 0...4)
      case .minimumLength: value.minimumContourLength = reflect(value.minimumContourLength + delta * 20, 0...40)
      case .simplification: value.simplificationTolerance = reflect(value.simplificationTolerance + delta * 1.5, 0...3)
      case .levels: value.contourLevels = Int(reflect(Double(value.contourLevels) + delta * 6, 1...12).rounded())
      case .spacing: value.hatchSpacing = Int(reflect(Double(value.hatchSpacing) + delta * 8, 1...16).rounded())
      case .angle: value.hatchAngleDegrees = reflect(value.hatchAngleDegrees + delta * 90, -90...90)
      case .threshold: value.sketchThreshold = reflect(value.sketchThreshold + delta * 0.039, 0.002...0.08)
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
