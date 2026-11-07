import Foundation
import PlotterModel

public struct DrawingProducerReceipt: Hashable, Sendable {
  public let id: String
  public let version: String
  public let record: ExchangeDigest
  public let originalJSON: Data
  public init(id: String, version: String, recordJSON: Data) throws {
    guard exchangeNamespacedID(id), !version.isEmpty else { throw DrawingExchangeError.malformed("Invalid producer") }
    _ = try ExchangeJSON.validate(recordJSON)
    self.id = id; self.version = version; self.originalJSON = recordJSON; self.record = .hash(recordJSON)
  }
}
public struct DrawingUnits: Hashable, Sendable {
  public let nominalPenWidthMM: Double?
  public let intendedPhysicalFieldMM: Size2<FieldSpace>?
  public let historical: String?
  public let historicalReceipt: ExchangeDigest?
  public static let historicalUnknown = try! DrawingUnits()
  public init(nominalPenWidthMM: Double? = nil, intendedPhysicalFieldMM: Size2<FieldSpace>? = nil,
    historical: String? = nil, historicalReceipt: ExchangeDigest? = nil) throws {
    if let width = nominalPenWidthMM, !width.isFinite || width <= 0 { throw DrawingExchangeError.malformed("Invalid nominal pen width") }
    guard (historical == nil) == (historicalReceipt == nil), historical?.isEmpty != true else {
      throw DrawingExchangeError.malformed("Historical units require producer receipt")
    }
    if let size = intendedPhysicalFieldMM {
      guard size.width.isFinite, size.height.isFinite, size.width > 0, size.height > 0 else { throw DrawingExchangeError.malformed("Invalid physical field") }
    }
    self.nominalPenWidthMM = nominalPenWidthMM; self.intendedPhysicalFieldMM = intendedPhysicalFieldMM
    self.historical = historical; self.historicalReceipt = historicalReceipt
  }
}
public enum DrawingExchangeLimits {
  public static let maximumProgramBytes = 128 * 1024 * 1024
  public static let maximumStrokes = 100_000
  public static let maximumPoints = 2_000_000
}
/// Stroke extrema may have zero width or height; area-only planner bounds cannot represent a line.
public struct DrawingBounds: Hashable, Sendable {
  public let minX: Double
  public let minY: Double
  public let maxX: Double
  public let maxY: Double
}
public struct DrawingSummary: Hashable, Sendable {
  public let strokeCount: Int
  public let pointCount: Int
  public let bounds: DrawingBounds
}
/// Preview, plot and edit refer to authored stroke geometry. Source image overlays,
/// regeneration and training additionally need their source dependency semantics and
/// an owning capability; geometry support never proves an encoded image was decoded.
public enum DrawingOperation: String, Hashable, Sendable, CaseIterable { case preview, plot, edit, regenerate, train }
public struct DrawingCapabilities: Sendable {
  public let supported: Set<DrawingOperation>
  public let unsupportedRequiredFeatures: [String]
  public let producerVerified: Bool
  public let unsupportedSourceDependencies: [String]
  /// Dependency diagnostics are independent of geometry integrity and device readiness.
  /// This flag is necessary, not sufficient, for source-dependent operations.
  public var sourceSemanticsSupported: Bool { unsupportedSourceDependencies.isEmpty }
  init(supported: Set<DrawingOperation>, unsupportedRequiredFeatures: [String], producerVerified: Bool,
    unsupportedSourceDependencies: [String] = []) {
    self.supported = supported; self.unsupportedRequiredFeatures = unsupportedRequiredFeatures
    self.producerVerified = producerVerified; self.unsupportedSourceDependencies = unsupportedSourceDependencies
  }
  public func require(_ operation: DrawingOperation) throws {
    guard supported.contains(operation) else {
      throw DrawingExchangeError.unsupportedFeature(unsupportedRequiredFeatures.first ?? unsupportedSourceDependencies.first ?? operation.rawValue)
    }
  }
}
/// No filesystem, library, device or history owner is reachable through this value.
public struct Drawing: Sendable {
  public let program: DrawingProgram
  public let input: SourceLink<ImageInputRef>
  public let parent: SourceLink<DrawingRef>
  public let producer: DrawingProducerReceipt
  public let units: DrawingUnits
  public let reference: DrawingRef?
  public let programDigest: Digest
  public let cachedSummary: DrawingSummary
  public let capabilities: DrawingCapabilities
  public let requiredFeatures: [String]

  public init(program: DrawingProgram, input: SourceLink<ImageInputRef>,
    parent: SourceLink<DrawingRef>, producer: DrawingProducerReceipt,
    units: DrawingUnits = .historicalUnknown) throws {
    try self.init(program: program, input: input, parent: parent, producer: producer,
      units: units, reference: nil, capabilities: .init(supported: [.preview, .plot, .edit], unsupportedRequiredFeatures: [], producerVerified: false))
  }
  init(program: DrawingProgram, input: SourceLink<ImageInputRef>, parent: SourceLink<DrawingRef>,
    producer: DrawingProducerReceipt, units: DrawingUnits, reference: DrawingRef?, capabilities: DrawingCapabilities,
    requiredFeatures: [String] = []) throws {
    try input.validate(); try parent.validate()
    guard program.strokes.count <= DrawingExchangeLimits.maximumStrokes else { throw DrawingExchangeError.limit("Strokes") }
    var count = 0
    var minX = Double.infinity, minY = Double.infinity, maxX = -Double.infinity, maxY = -Double.infinity
    for stroke in program.strokes {
      guard count <= DrawingExchangeLimits.maximumPoints - stroke.path.points.count else { throw DrawingExchangeError.limit("Points") }
      count += stroke.path.points.count
      for p in stroke.path.points { minX = min(minX, p.x); minY = min(minY, p.y); maxX = max(maxX, p.x); maxY = max(maxY, p.y) }
    }
    self.program = program; self.input = input; self.parent = parent; self.producer = producer
    self.units = units; self.reference = reference; self.requiredFeatures = requiredFeatures; programDigest = program.contentHash
    var sourceDependencies = capabilities.unsupportedSourceDependencies
    if case .unavailable(let reason, _) = input { sourceDependencies.append("Input unavailable: " + reason) }
    if case .unavailable(let reason, _) = parent { sourceDependencies.append("Parent unavailable: " + reason) }
    self.capabilities = .init(supported: capabilities.supported, unsupportedRequiredFeatures: capabilities.unsupportedRequiredFeatures,
      producerVerified: capabilities.producerVerified, unsupportedSourceDependencies: sourceDependencies)
    cachedSummary = .init(strokeCount: program.strokes.count, pointCount: count,
      bounds: DrawingBounds(minX: minX, minY: minY, maxX: maxX, maxY: maxY))
  }
  private init(copying other: Drawing, reference: DrawingRef?, capabilities: DrawingCapabilities) {
    program = other.program; input = other.input; parent = other.parent; producer = other.producer
    units = other.units; programDigest = other.programDigest; cachedSummary = other.cachedSummary
    self.reference = reference; self.capabilities = capabilities; requiredFeatures = other.requiredFeatures
  }
  func binding(reference: DrawingRef?, capabilities: DrawingCapabilities) -> Drawing {
    Drawing(copying: self, reference: reference, capabilities: capabilities)
  }
  public func summary() -> DrawingSummary { cachedSummary }
  public func applying(_ edit: DrawingStrokeEdit, to parent: DrawingRef, universe: Drawing? = nil,
    programID: ProgramID) throws -> Drawing {
    try capabilities.require(.edit)
    guard reference == parent else { throw DrawingExchangeError.mismatchedParent }
    let currentIDs = Set(program.strokes.map(\.id))
    let priorEdit = producer.id == "adaptiveplotter.stroke-membership" && producer.version == "1"
      ? try JSONDecoder().decode(DrawingMembershipReceipt.self, from: producer.originalJSON) : nil
    let universeRef = priorEdit?.universe ?? parent
    let needsRestoration: Bool
    switch edit {
    case .restore: needsRestoration = true
    case .membership(let ids): needsRestoration = !Set(ids).isSubset(of: currentIDs)
    case .remove: needsRestoration = false
    }
    if needsRestoration {
      guard universe?.reference == universeRef else { throw DrawingExchangeError.mismatchedParent }
    }
    if let supplied = universe, supplied.reference != universeRef { throw DrawingExchangeError.mismatchedParent }
    let strokes = try DrawingStrokeMembership.apply(edit, to: program, universe: universe?.program ?? program)
    let child = try DrawingProgram(id: programID, fieldExtent: program.fieldExtent, strokes: strokes, source: program.source)
    let action: String, ids: [StrokeID]
    switch edit {
    case .remove(let value): action = "remove"; ids = value
    case .restore(let value): action = "restore"; ids = value
    case .membership(let value): action = "membership"; ids = value
    }
    let record = try DrawingPackageCodec.encoder().encode(DrawingMembershipReceipt(action: action, strokeIDs: ids,
      parent: parent, universe: universeRef, before: ExchangeDigest(programDigest), after: ExchangeDigest(child.contentHash)))
    let receipt = try DrawingProducerReceipt(id: "adaptiveplotter.stroke-membership", version: "1", recordJSON: record)
    return try Drawing(program: child, input: input, parent: .present(parent), producer: receipt, units: units,
      reference: nil, capabilities: .init(supported: [.preview, .plot, .edit], unsupportedRequiredFeatures: [],
        producerVerified: true, unsupportedSourceDependencies: capabilities.unsupportedSourceDependencies),
      requiredFeatures: requiredFeatures)
  }
}
public enum DrawingStrokeEdit: Sendable {
  case remove([StrokeID])
  case restore([StrokeID])
  case membership([StrokeID])
}
public enum DrawingStrokeMembership {
  public static func apply(_ edit: DrawingStrokeEdit, to program: DrawingProgram,
    universe: DrawingProgram) throws -> [LogicalStroke] {
    guard program.fieldExtent == universe.fieldExtent else { throw DrawingExchangeError.mismatchedParent }
    let all = Dictionary(uniqueKeysWithValues: universe.strokes.map { ($0.id, $0) })
    guard program.strokes.allSatisfy({ all[$0.id] == $0 }) else { throw DrawingExchangeError.mismatchedParent }
    let ids: [StrokeID]
    switch edit { case .remove(let value), .restore(let value), .membership(let value): ids = value }
    let selected = Set(ids)
    guard selected.count == ids.count else { throw DrawingExchangeError.duplicateStroke }
    guard selected.allSatisfy({ all[$0] != nil }) else { throw DrawingExchangeError.unknownStroke }
    let current = Set(program.strokes.map(\.id))
    let target: Set<StrokeID>
    switch edit {
    case .remove:
      guard !selected.isEmpty, selected.isSubset(of: current) else { throw DrawingExchangeError.noChange }
      target = current.subtracting(selected)
    case .restore:
      guard !selected.isEmpty, selected.isDisjoint(with: current) else { throw DrawingExchangeError.noChange }
      target = current.union(selected)
    case .membership: target = selected
    }
    guard !target.isEmpty else { throw DrawingExchangeError.allStrokesRemoved }
    guard target != current else { throw DrawingExchangeError.noChange }
    return universe.strokes.filter { target.contains($0.id) }
  }
}
public struct DrawingProduction<Artifacts: Sendable>: Sendable {
  public let drawing: Drawing
  public let artifacts: Artifacts
  public init(drawing: Drawing, artifacts: Artifacts) { self.drawing = drawing; self.artifacts = artifacts }
}
public protocol DrawingProducing: Sendable {
  associatedtype Input: Sendable
  associatedtype Settings: Sendable
  associatedtype Artifacts: Sendable
  func produce(input: Input, settings: Settings) async throws -> DrawingProduction<Artifacts>
}

struct DrawingMembershipReceipt: Codable {
  var profile = "adaptiveplotter.stroke-membership/1"
  let action: String
  let strokeIDs: [StrokeID]
  let parent: DrawingRef
  let universe: DrawingRef
  let before: ExchangeDigest
  let after: ExchangeDigest
}
