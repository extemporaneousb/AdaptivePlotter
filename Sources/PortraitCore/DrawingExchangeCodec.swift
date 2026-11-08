import Foundation
import PlotterModel

public struct DrawingProducerContext: Sendable {
  public let program: DrawingProgram
  public let input: SourceLink<ImageInputRef>
  public let parent: SourceLink<DrawingRef>
  public let units: DrawingUnits
  public let artifacts: DrawingProducerArtifactReads
}
public typealias DrawingProducerValidator = @Sendable (DrawingProducerReceipt, DrawingProducerContext) throws -> Void

/// These callbacks are supplied by the trusted application composition, never decoded from a wire flag.
public struct DrawingProducerKey: Hashable, Sendable {
  public let id: String
  public let version: String
  public init(id: String, version: String) { self.id = id; self.version = version }
}
public struct DrawingProducerArtifactRequest: Sendable {
  public let object: ExchangeDigest
  public let maximumBytes: Int
  public init(object: ExchangeDigest, maximumBytes: Int = ExchangeJSON.maximumRecordBytes) {
    self.object = object; self.maximumBytes = maximumBytes
  }
}
public struct DrawingProducerArtifactReads: Sendable {
  private let values: [ExchangeDigest: Data]
  public static let empty = DrawingProducerArtifactReads(uncheckedEmpty: ())
  private init(uncheckedEmpty: Void) { values = [:] }
  public init(_ values: [ExchangeDigest: Data]) throws {
    guard values.count <= 10_000 else { throw DrawingExchangeError.limit("Producer artifact count") }
    var count = 0
    for (digest, data) in values {
      guard data.count <= 256 * 1024 * 1024 - count else { throw DrawingExchangeError.limit("Producer artifact bytes") }
      guard ExchangeDigest.hash(data) == digest else { throw DrawingExchangeError.digestMismatch("Producer artifact") }
      count += data.count
    }
    self.values = values
  }
  public func record(_ digest: ExchangeDigest) throws -> Data {
    guard let bytes = values[digest] else { throw DrawingExchangeError.missingAsset("Producer artifact " + digest.description) }
    return bytes
  }
}
public struct DrawingProducerRule: Sendable {
  public let dependencies: @Sendable (DrawingProducerReceipt) throws -> [DrawingProducerArtifactRequest]
  public let validator: DrawingProducerValidator
  public init(dependencies: @escaping @Sendable (DrawingProducerReceipt) throws -> [DrawingProducerArtifactRequest],
    validator: @escaping DrawingProducerValidator) {
    self.dependencies = dependencies; self.validator = validator
  }
}
public struct DrawingProducerValidators: Sendable {
  let validators: [DrawingProducerKey: DrawingProducerValidator]
  let rules: [DrawingProducerKey: DrawingProducerRule]
  public init(_ validators: [DrawingProducerKey: DrawingProducerValidator] = [:]) { self.validators = validators; rules = [:] }
  public init(rules: [DrawingProducerKey: DrawingProducerRule]) {
    self.rules = rules; validators = rules.mapValues(\.validator)
  }
}
public enum DrawingAdmission {
  public static func produced(program: DrawingProgram, input: SourceLink<ImageInputRef>, parent: SourceLink<DrawingRef>,
    producer: DrawingProducerReceipt, units: DrawingUnits, artifacts: DrawingProducerArtifactReads = .empty, validator: DrawingProducerValidator) throws -> Drawing {
    try validator(producer, .init(program: program, input: input, parent: parent, units: units, artifacts: artifacts))
    return try Drawing(program: program, input: input, parent: parent, producer: producer, units: units, reference: nil,
      capabilities: .init(supported: [.preview, .plot, .edit], unsupportedRequiredFeatures: [], producerVerified: true))
  }
}
/// Frozen drawing JSON and its original program asset survive re-export byte for byte.
public struct FrozenDrawingRecord: Sendable {
  public let originalJSON: Data
  public let originalProgramJSON: Data
  public let drawing: Drawing
  public var reference: DrawingRef { drawing.reference! }
}
public enum DrawingRecordAdmission: Sendable {
  case materialized(FrozenDrawingRecord)
  case opaque(originalJSON: Data, profile: String)
}
public enum DrawingExchangeCodec {
  public static let drawingProfile = "adaptiveplotter.drawing/1"
  public static let strokeProfile = "adaptiveplotter.stroke-program/1"
  struct ProducerWire: Codable { let id: String; let version: String; let record: ExchangeDigest }
  struct Representation: Codable {
    let kind: String
    let object: ExchangeDigest
    let programHash: ExchangeDigest?
    let nominalPenWidthMillimeters: Double?
    let intendedPhysicalFieldMillimeters: Size2<FieldSpace>?
    let historicalUnits: Historical?
  }
  struct Historical: Codable { let state: String; let units: String?; let producerReceipt: ExchangeDigest? }
  struct Wire: Codable {
    let profile: String
    let requiredFeatures: [String]
    let ref: ExchangeIdentity
    let createdAt: String
    let representation: Representation
    let input: SourceLink<ImageInputRef>
    let parent: SourceLink<DrawingRef>
    let producer: ProducerWire
  }
  public static func decode(_ record: Data, objects: [ExchangeDigest: Data], expected: DrawingRef? = nil,
    validators: DrawingProducerValidators = .init(), supportedFeatures: Set<String> = [], assetDescriptors: [ExchangeDigest: ExchangeAssetDescriptor] = [:]) throws -> DrawingRecordAdmission {
    try decodeRecord(record, objects: .dictionary(objects), expected: expected, validators: validators, supportedFeatures: supportedFeatures, assetDescriptors: assetDescriptors, depth: 0)
  }
  public static func decode(_ record: Data, files: VerifiedExchangeFiles, expected: DrawingRef? = nil,
    validators: DrawingProducerValidators = .init(), supportedFeatures: Set<String> = [], assetDescriptors: [ExchangeDigest: ExchangeAssetDescriptor] = [:]) throws -> DrawingRecordAdmission {
    try decodeRecord(record, objects: .files(files, budget: .init(maximum: files.limits.maximumMaterializedBytes)), expected: expected, validators: validators, supportedFeatures: supportedFeatures, assetDescriptors: assetDescriptors, depth: 0)
  }
  private static func decodeRecord(_ record: Data, objects: ExchangeObjectResolver, expected: DrawingRef?,
    validators: DrawingProducerValidators, supportedFeatures: Set<String>, assetDescriptors: [ExchangeDigest: ExchangeAssetDescriptor], depth: Int) throws -> DrawingRecordAdmission {
    guard depth <= 64 else { throw DrawingExchangeError.limit("Record depth") }
    if case .dictionary(let dictionary) = objects, dictionary.count > 10_000 { throw DrawingExchangeError.limit("Record closure") }
    guard record.count <= ExchangeJSON.maximumRecordBytes else { throw DrawingExchangeError.limit("Record bytes") }
    let recordDigest = ExchangeDigest.hash(record)
    if case .files(let files, _) = objects { files.counters.update { $0.semanticBytesHashed += UInt64(record.count) } }
    if let expected, expected.digest != recordDigest { throw DrawingExchangeError.digestMismatch("Drawing bytes") }
    let object = try ExchangeJSON.validate(record)
    guard let profile = object["profile"] as? String else { throw DrawingExchangeError.malformed("Missing profile") }
    guard profile == drawingProfile else { return .opaque(originalJSON: record, profile: profile) }
    if let representation = object["representation"] as? [String: Any] {
      for key in ["nominalPenWidthMillimeters", "intendedPhysicalFieldMillimeters", "historicalUnits"] where representation[key] is NSNull {
        throw DrawingExchangeError.malformed("Null optional representation field: \(key)")
      }
    }
    if let representation = object["representation"] as? [String: Any], let historical = representation["historicalUnits"] as? [String: Any] {
      for key in ["units", "producerReceipt"] where historical[key] is NSNull { throw DrawingExchangeError.malformed("Null historical unit claim") }
    }
    let wire = try JSONDecoder().decode(Wire.self, from: record)
    try validateClosedReferences(object)
    guard exchangeDate(wire.createdAt) != nil,
      Set(wire.requiredFeatures).count == wire.requiredFeatures.count,
      wire.requiredFeatures.allSatisfy(exchangeNamespacedID) else { throw DrawingExchangeError.malformed("Date/features") }
    let ref = DrawingRef(issuer: wire.ref.issuer, revision: wire.ref.revision, digest: recordDigest)
    if let expected, ref != expected { throw DrawingExchangeError.digestMismatch("Drawing reference") }
    guard wire.representation.kind == strokeProfile else { return .opaque(originalJSON: record, profile: wire.representation.kind) }
    let programBytes = try objects.bytes(wire.representation.object, maximum: DrawingExchangeLimits.maximumProgramBytes)
    guard programBytes.count <= DrawingExchangeLimits.maximumProgramBytes else { throw DrawingExchangeError.limit("Program bytes") }
    // Strict JSON preflight uses a separate program-size limit and rejects ambiguous duplicate keys.
    _ = try ExchangeJSON.validate(programBytes, maximumBytes: DrawingExchangeLimits.maximumProgramBytes)
    if case .files(let files, _) = objects { files.counters.update { $0.programJSONDecodeCalls += 1 } }
    let program = try JSONDecoder().decode(DrawingProgram.self, from: programBytes)
    guard wire.representation.programHash == ExchangeDigest(program.contentHash) else { throw DrawingExchangeError.digestMismatch("Program semantic hash") }
    let receiptBytes = try objects.bytes(wire.producer.record)
    if case .files(let files, _) = objects { files.counters.update { $0.semanticBytesHashed += UInt64(receiptBytes.count) } }
    let receipt = try DrawingProducerReceipt(id: wire.producer.id, version: wire.producer.version, recordJSON: receiptBytes)
    guard receipt.record == wire.producer.record else { throw DrawingExchangeError.digestMismatch("Producer record") }
    let validator = validators.validators[.init(id: receipt.id, version: receipt.version)] ?? builtinValidator(receipt.id, version: receipt.version)
    let historical = wire.representation.historicalUnits
    if let historical {
      guard ["known", "unknown"].contains(historical.state),
        historical.state == "known" ? historical.units != nil && historical.producerReceipt != nil : historical.units == nil && historical.producerReceipt == nil else {
        throw DrawingExchangeError.malformed("Historical units")
      }
      if let proof = historical.producerReceipt, proof != receipt.record,
        !(receipt.id == "adaptiveplotter.stroke-membership" && receipt.version == "1") {
        throw DrawingExchangeError.invalidProducer("Unit receipt is not the admitted producer")
      }
      // A recognized membership edit inherits units from its recursively admitted
      // exact parent; the completed validator below requires full unit equality.
      // Other producers must bind historical units to their own frozen receipt.
    }
    let units = try DrawingUnits(nominalPenWidthMM: wire.representation.nominalPenWidthMillimeters,
      intendedPhysicalFieldMM: wire.representation.intendedPhysicalFieldMillimeters,
      historical: historical?.units, historicalReceipt: historical?.producerReceipt)
    if let validator {
      var artifacts: [ExchangeDigest: Data] = [:]
      if let rule = validators.rules[.init(id: receipt.id, version: receipt.version)] {
        let requests = try rule.dependencies(receipt)
        guard requests.count <= 10_000 else { throw DrawingExchangeError.limit("Producer artifact requests") }
        for request in requests {
          guard request.maximumBytes > 0, request.maximumBytes <= DrawingExchangeLimits.maximumProgramBytes,
            let descriptor = assetDescriptors[request.object] else { throw DrawingExchangeError.missingAsset("Producer artifact descriptor " + request.object.description) }
          try objects.validate(descriptor.asset)
          if case .files(let files, _) = objects {
            let path = "data/objects/sha256/" + request.object.description
            guard files.entries[path]?.digest == request.object else { throw DrawingExchangeError.digestMismatch("Producer artifact canonical path") }
            try files.verify(request.object)
            _ = try files.validateAsset(descriptor)
          }
          if artifacts[request.object] == nil { artifacts[request.object] = try objects.bytes(request.object, maximum: request.maximumBytes) }
        }
      }
      if case .files(let files, _) = objects { files.counters.update { $0.producerValidatorEntries += 1 } }
      try validator(receipt, .init(program: program, input: wire.input, parent: wire.parent, units: units,
        artifacts: try DrawingProducerArtifactReads(artifacts)))
    }
    let unknown = wire.requiredFeatures.filter { !supportedFeatures.contains($0) }
    var sourceDependencies: [String] = []
    if case .present(let input) = wire.input {
      do {
        let admitted = try DrawingImageAdmission.input(input, objects: objects, supportedFeatures: supportedFeatures, assetDescriptors: assetDescriptors)
        if !admitted.supportedSemantics { sourceDependencies.append("adaptiveplotter.input-semantics") }
      } catch DrawingExchangeError.unsupportedProfile(let profile) {
        sourceDependencies.append("Unsupported source profile: " + profile)
      }
    }
    var parentDrawing: Drawing?
    if case .present(let parent) = wire.parent {
      let bytes = try DrawingImageAdmission.bytes(parent.digest, in: objects)
      let result = try decodeRecord(bytes, objects: objects, expected: parent, validators: validators,
        supportedFeatures: supportedFeatures, assetDescriptors: assetDescriptors, depth: depth + 1)
      switch result {
      case .opaque: sourceDependencies.append("adaptiveplotter.parent-semantics")
      case .materialized(let value):
        parentDrawing = value.drawing
        if !value.drawing.capabilities.sourceSemanticsSupported || !value.drawing.capabilities.unsupportedRequiredFeatures.isEmpty { sourceDependencies.append("adaptiveplotter.parent-semantics") }
      }
    }
    var editVerified = false
    if receipt.id == "adaptiveplotter.stroke-membership", receipt.version == "1" {
      let claim = try JSONDecoder().decode(DrawingMembershipReceipt.self, from: receipt.originalJSON)
      guard receipt.version == "1", claim.profile == "adaptiveplotter.stroke-membership/1",
        case .present(let parentRef) = wire.parent, claim.parent == parentRef,
        let parentDrawing, claim.before == ExchangeDigest(parentDrawing.programDigest),
        claim.after == ExchangeDigest(program.contentHash), wire.input == parentDrawing.input,
        units == parentDrawing.units else { throw DrawingExchangeError.invalidProducer("Membership receipt bindings") }
      guard Set(parentDrawing.requiredFeatures).isSubset(of: Set(wire.requiredFeatures)) else {
        throw DrawingExchangeError.invalidProducer("Membership child drops parent requirements")
      }
      let expectedUniverse: DrawingRef
      if parentDrawing.producer.id == "adaptiveplotter.stroke-membership", parentDrawing.producer.version == "1" {
        expectedUniverse = try JSONDecoder().decode(DrawingMembershipReceipt.self, from: parentDrawing.producer.originalJSON).universe
      } else { expectedUniverse = parentRef }
      guard claim.universe == expectedUniverse else { throw DrawingExchangeError.mismatchedParent }
      let universeBytes = try DrawingImageAdmission.bytes(claim.universe.digest, in: objects)
      let admitted = try decodeRecord(universeBytes, objects: objects, expected: claim.universe,
        validators: validators, supportedFeatures: supportedFeatures, assetDescriptors: assetDescriptors, depth: depth + 1)
      guard case .materialized(let universe) = admitted else { throw DrawingExchangeError.unsupportedProfile("Edit universe") }
      let edit: DrawingStrokeEdit
      switch claim.action {
      case "remove": edit = .remove(claim.strokeIDs)
      case "restore": edit = .restore(claim.strokeIDs)
      case "membership": edit = .membership(claim.strokeIDs)
      default: throw DrawingExchangeError.invalidProducer("Membership action")
      }
      let expectedStrokes = try DrawingStrokeMembership.apply(edit, to: parentDrawing.program, universe: universe.drawing.program)
      guard program.strokes == expectedStrokes, program.fieldExtent == parentDrawing.program.fieldExtent,
        program.source == parentDrawing.program.source else { throw DrawingExchangeError.invalidProducer("Membership geometry") }
      editVerified = true
    }
    // Features without an operation registry conservatively block all semantic operations, while preserving bytes.
    let caps = DrawingCapabilities(supported: unknown.isEmpty ? [.preview, .plot, .edit] : [],
      unsupportedRequiredFeatures: unknown, producerVerified: validator != nil || editVerified,
      unsupportedSourceDependencies: sourceDependencies)
    let drawing = try Drawing(program: program, input: wire.input, parent: wire.parent, producer: receipt,
      units: units, reference: ref, capabilities: caps, requiredFeatures: wire.requiredFeatures)
    return .materialized(.init(originalJSON: record, originalProgramJSON: programBytes, drawing: drawing))
  }
  public static func freeze(_ drawing: Drawing, identity: ExchangeIdentity, createdAt: Date,
    originalProgramJSON: Data? = nil) throws -> FrozenDrawingRecord {
    guard createdAt.timeIntervalSinceReferenceDate.isFinite else { throw DrawingExchangeError.malformed("New exports require a finite date") }
    let width = drawing.units.nominalPenWidthMM
    let programBytes = try originalProgramJSON ?? DrawingArtifactCoding.encoder().encode(drawing.program)
    _ = try ExchangeJSON.validate(programBytes, maximumBytes: DrawingExchangeLimits.maximumProgramBytes)
    guard (try JSONDecoder().decode(DrawingProgram.self, from: programBytes)) == drawing.program else { throw DrawingExchangeError.digestMismatch("Original program bytes") }
    let representation = Representation(kind: strokeProfile, object: .hash(programBytes), programHash: ExchangeDigest(drawing.programDigest),
      nominalPenWidthMillimeters: width, intendedPhysicalFieldMillimeters: drawing.units.intendedPhysicalFieldMM,
      historicalUnits: drawing.units.historical.map { .init(state: "known", units: $0, producerReceipt: drawing.units.historicalReceipt) })
    let timestamp = ISO8601DateFormatter().string(from: createdAt)
    guard exchangeDate(timestamp) != nil else { throw DrawingExchangeError.malformed("Creation time outside RFC3339 range") }
    let wire = Wire(profile: drawingProfile, requiredFeatures: drawing.requiredFeatures, ref: identity,
      createdAt: timestamp, representation: representation,
      input: drawing.input, parent: drawing.parent,
      producer: .init(id: drawing.producer.id, version: drawing.producer.version, record: drawing.producer.record))
    let bytes = try DrawingArtifactCoding.encoder().encode(wire)
    let ref = DrawingRef(issuer: identity.issuer, revision: identity.revision, digest: .hash(bytes))
    let bound = drawing.binding(reference: ref, capabilities: drawing.capabilities)
    return .init(originalJSON: bytes, originalProgramJSON: programBytes, drawing: bound)
  }
  public static func encode(_ record: FrozenDrawingRecord) -> Data { record.originalJSON }
  static func builtinValidator(_ id: String, version: String) -> DrawingProducerValidator? {
    guard id == "adaptiveplotter.catalog", ["1","2"].contains(version) else { return nil }
    return { receipt, context in
      let program = context.program
      let json = try ExchangeJSON.validate(receipt.originalJSON)
      guard context.input == .none, context.parent == .none else { throw DrawingExchangeError.invalidProducer("Catalog must affirmatively declare source-free origin") }
      if let historical = context.units.historical {
        guard json["historicalUnits"] as? String == historical,
          context.units.historicalReceipt == receipt.record else { throw DrawingExchangeError.invalidProducer("Unproven catalog units") }
      }
      guard let profile = json["profile"] as? String,
        (version == "2" ? ["adaptiveplotter.catalog-receipt/2"] : ["adaptiveplotter.catalog-receipt/1", "adaptiveplotter.example.catalog-receipt/1"]).contains(profile) else {
        throw DrawingExchangeError.invalidProducer("Catalog receipt profile")
      }
      let nominal: Double?
      if let raw = json["nominalPenWidthMillimeters"] {
        nominal = try DrawingImageAdmission.decode(raw, as: Double.self)
        guard let nominal, nominal.isFinite, nominal > 0 else { throw DrawingExchangeError.invalidProducer("Catalog nominal width") }
      } else { nominal = nil }
      guard context.units.nominalPenWidthMM == nominal else { throw DrawingExchangeError.invalidProducer("Catalog nominal width") }
      let physicalField: Size2<FieldSpace>?
      if let raw = json["intendedPhysicalFieldMillimeters"] {
        physicalField = try DrawingImageAdmission.decode(raw, as: Size2<FieldSpace>.self)
      } else { physicalField = nil }
      guard context.units.intendedPhysicalFieldMM == physicalField else { throw DrawingExchangeError.invalidProducer("Catalog intended physical field") }
      guard receipt.version == version, let entryName = json["entry"] as? String,
        let entry = DrawingCatalogEntryID(rawValue: entryName),
        json["sourceIdentifier"] as? String == program.source.sourceIdentifier,
        let first = program.strokes.first else { throw DrawingExchangeError.invalidProducer("Catalog receipt") }
      let tessellation: CurveTessellationPolicy
      if let raw = json["tessellation"] {
        tessellation = try JSONDecoder().decode(CurveTessellationPolicy.self, from: JSONSerialization.data(withJSONObject: raw))
      } else { tessellation = .catalogDefault }
      let expected = try DrawingProgramCatalog.program(for: entry, style: first.style, tessellation: tessellation)
      guard expected == program else { throw DrawingExchangeError.invalidProducer("Catalog geometry does not match its typed claim") }
    }
  }
  static func validateClosedReferences(_ object: [String: Any]) throws {
    func identity(_ value: Any?, digest: Bool) throws {
      guard let obj = value as? [String: Any], Set(obj.keys) == Set(digest ? ["issuer", "revision", "digest"] : ["issuer", "revision"]) else { throw DrawingExchangeError.malformed("Closed reference") }
    }
    try identity(object["ref"], digest: false)
    for key in ["input", "parent"] {
      guard let link = object[key] as? [String: Any], let state = link["state"] as? String else { throw DrawingExchangeError.malformed("Source declaration") }
      switch state {
      case "none": guard Set(link.keys) == ["state"] else { throw DrawingExchangeError.malformed("None declaration") }
      case "present":
        guard Set(link.keys) == ["state", "ref"] else { throw DrawingExchangeError.malformed("Present declaration") }; try identity(link["ref"], digest: true)
      case "unavailable":
        guard Set(link.keys).isSubset(of: ["state", "reason", "knownRef"]) else { throw DrawingExchangeError.malformed("Unavailable declaration") }
        if let known = link["knownRef"] { try identity(known, digest: true) }
      default: throw DrawingExchangeError.malformed("Unknown source state")
      }
    }
  }
}
