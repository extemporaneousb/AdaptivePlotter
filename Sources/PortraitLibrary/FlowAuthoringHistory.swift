import Foundation
import DrawingLibrary
import PlotterModel
import PortraitArtists
import PortraitCore

/// Lifetime authored history is stored in Library CAS. Only one closure/read is
/// bounded here; durable history has no generation-count or aggregate-byte cap.
package struct FlowAuthoringHistoryPolicy: Sendable {
  package let maximumEntryBytes: Int
  package init(maximumEntryBytes: Int = 64 * 1024 * 1024) { self.maximumEntryBytes = maximumEntryBytes }
}
package struct FlowAuthoringHistoryStatistics: Sendable {
  package let entryCount: Int
  /// Unique committed CAS history bytes; selected legacy private bytes are not scanned.
  package let byteCount: Int
  package let libraryEntryCount: Int
  package let legacyEntryCount: Int
}

/// Explicit storage marker. Absence is the original private-v1 reader, never a
/// fallback from a corrupt Library-backed candidate.
package struct FlowPortfolioHistoryLocation: Codable, Equatable, Sendable {
  package let storage: String
  package let parts: [FlowPortfolioBlob]
  init(parts: [FlowPortfolioBlob]) { storage = "library-assets/1"; self.parts = parts }
}
struct FlowPreparedHistory: Sendable {
  let reference: FlowPortfolioBlob
  let location: FlowPortfolioHistoryLocation
  let assets: [DrawingLibraryClosureAsset]
}

package enum FlowAuthoringHistoryBoundary: Sendable, Equatable { case beforeWrite, afterParts, beforePublish }
package enum FlowAuthoringHistoryAdmissionError: Error, Sendable {
  case limit(String)
  package var reason: String { switch self { case .limit(let reason): return reason } }
}

private struct FlowHistoryIdentity: Codable, Equatable, Sendable {
  let id: UUID
  let createdAt: Date
  let sourceID: UUID
  let roundID: UUID
  let slot: Int
  let parent: UUID?
  let recipe: FlowArtistRecipe
  let model: String?
  let raster: FlowPortfolioBlob
  let preview: FlowPortfolioBlob
  let programHash: String
  let strokeCount: Int
  init(_ value: FlowPortfolioCandidate) {
    id = value.id; createdAt = value.createdAt; sourceID = value.sourceID
    roundID = value.roundID; slot = value.slot; parent = value.parentCandidateID
    recipe = value.recipe; model = value.modelID; raster = value.raster
    preview = value.preview; programHash = value.programHash; strokeCount = value.strokeCount
  }
}
private struct FlowHistoryPart: Codable, Sendable {
  let path: String
  let digest: ExchangeDigest
  let byteCount: Int
  var storagePath: String { digest.description + ".part" }
}
private struct FlowHistoryDrawingWire: Decodable, Sendable {
  struct Producer: Decodable, Sendable { let id: String; let version: String; let record: ExchangeDigest }
  struct Historical: Decodable, Sendable { let state: String; let units: String?; let producerReceipt: ExchangeDigest? }
  struct Representation: Decodable, Sendable {
    let kind: String; let object: ExchangeDigest; let programHash: ExchangeDigest?
    let nominalPenWidthMillimeters: Double?
    let intendedPhysicalFieldMillimeters: Size2<FieldSpace>?
    let historicalUnits: Historical?
  }
  let profile: String; let requiredFeatures: [String]; let ref: ExchangeIdentity
  let representation: Representation
  let input: SourceLink<ImageInputRef>; let parent: SourceLink<DrawingRef>
  let producer: Producer
}
private struct FlowHistoryUnits: Codable, Equatable, Sendable {
  let nominal: Double?
  let field: Size2<FieldSpace>?
  let historical: String?
  let historicalReceipt: ExchangeDigest?
  init(_ value: DrawingUnits) {
    nominal = value.nominalPenWidthMM; field = value.intendedPhysicalFieldMM
    historical = value.historical; historicalReceipt = value.historicalReceipt
  }
}
private struct FlowHistoryManifest: Codable, Sendable {
  let profile: String
  let identity: FlowHistoryIdentity
  let photo: PhotoRef?
  let sourceImage: FlowPortfolioBlob
  let options: PortraitAnalysisOptions
  let drawing: DrawingRef
  let originalReference: DrawingRef?
  let inputLink: SourceLink<ImageInputRef>
  let parentLink: SourceLink<DrawingRef>
  let units: FlowHistoryUnits
  let input: ImageInputRef?
  let producerID: String
  let producerVersion: String
  let producerObject: ExchangeDigest
  let producerVerified: Bool
  let parts: [FlowHistoryPart]
}
struct FlowHistoryMaterial: Sendable {
  let drawing: Drawing
  let input: FrozenImageInputRecord?
  let originalReference: DrawingRef?
  let rasterBytes: Data
  let preview: Data
}

/// Pure bounded preparation plus selected readers. New bytes use the common
/// Library transaction; the old directory is never scanned, grown or quota-gated.
final class FlowAuthoringHistory: Sendable {
  let root: URL
  let policy: FlowAuthoringHistoryPolicy
  init(directory: URL, policy: FlowAuthoringHistoryPolicy) {
    root = directory.appendingPathComponent("flow-authoring-history-v1", isDirectory: true)
    self.policy = policy
  }
  func open() throws {
    guard policy.maximumEntryBytes > 0, policy.maximumEntryBytes <= Self.maximumRehydrationBytes else {
      throw FlowPortfolioError.invalid("Invalid authoring history read policy.")
    }
  }
  static let maximumRehydrationBytes = 64 * 1024 * 1024

  func prepare(candidate: FlowPortfolioCandidate, source: FlowPortfolioSource, round: FlowPortfolioRound,
    drawing: Drawing, input: FrozenImageInputRecord?, raster: Data, preview: Data, issuer: UUID) throws -> FlowPreparedHistory {
    try open()
    guard drawing.requiredFeatures.isEmpty else { throw FlowPortfolioError.invalid("This drawing requires unsupported authoring history features.") }
    let frozen = try DrawingExchangeCodec.freeze(drawing, identity: .init(issuer: issuer, revision: candidate.id), createdAt: candidate.createdAt)
    guard let reference = frozen.drawing.reference else { throw DrawingExchangeError.mismatchedParent }
    var values: [String: DrawingLibraryClosureAsset] = [:]
    var descriptors: [ExchangeDigest: ExchangeAssetDescriptor] = [:]
    // Known digests below come only from immutable owner-admitted image assets
    // and frozen records. Their factories already verified the bytes. Rebuilding
    // the private inventory must not hash a 31MiB original for every candidate.
    func knownAsset(_ bytes: Data, digest: ExchangeDigest, opaque: Bool = false) throws -> ExchangeAssetDescriptor {
      let header: [String: Any] = ["object": digest.description, "byteLength": bytes.count,
        "mediaType": opaque ? "application/octet-stream" : "application/json", "encoding": opaque ? "opaque" : "utf8-json"]
      let asset = try JSONDecoder().decode(ExchangeAsset.self, from: JSONSerialization.data(withJSONObject: header))
      return .init(asset: asset)
    }
    func add(_ path: String, _ bytes: Data, descriptor supplied: ExchangeAssetDescriptor? = nil) throws {
      let descriptor: ExchangeAssetDescriptor
      if let supplied { descriptor = supplied }
      else { descriptor = .init(asset: try ExchangeAsset(bytes: bytes, mediaType: "application/json", encoding: "utf8-json")) }
      guard descriptor.asset.byteLength == UInt64(bytes.count), bytes.count <= Self.maximumRehydrationBytes else {
        throw FlowAuthoringHistoryAdmissionError.limit("This exact authoring closure exceeds its read limit.")
      }
      if let old = values[path], old.descriptor != descriptor { throw FlowPortfolioError.invalid("Conflicting authoring history content.") }
      values[path] = .init(descriptor: descriptor, bytes: bytes)
    }
    func asset(_ value: DrawingImageAsset) throws {
      if let old = descriptors[value.descriptor.asset.object], old != value.descriptor {
        throw FlowPortfolioError.invalid("Conflicting authoring history asset descriptors.")
      }
      descriptors[value.descriptor.asset.object] = value.descriptor
      try add("data/objects/sha256/" + value.descriptor.asset.object.description, value.bytes, descriptor: value.descriptor)
    }
    let programAsset = try ExchangeAsset(bytes: frozen.originalProgramJSON, mediaType: "application/json", encoding: "utf8-json")
    let producerAsset = try ExchangeAsset(bytes: drawing.producer.originalJSON, mediaType: "application/json", encoding: "utf8-json")
    try add("data/objects/sha256/" + programAsset.object.description, frozen.originalProgramJSON, descriptor: .init(asset: programAsset))
    try add("data/objects/sha256/" + producerAsset.object.description, drawing.producer.originalJSON, descriptor: .init(asset: producerAsset))
    descriptors[programAsset.object] = .init(asset: programAsset); descriptors[producerAsset.object] = .init(asset: producerAsset)
    try add(Self.drawingPath(reference), frozen.originalJSON, descriptor: knownAsset(frozen.originalJSON, digest: reference.digest))
    if let input {
      guard drawing.input == .present(input.reference), input.photo.reference == source.photo else { throw DrawingExchangeError.mismatchedParent }
      for value in input.assets + input.photo.assets { try asset(value) }
      try add(Self.photoPath(input.photo.reference), input.photo.record.originalJSON,
        descriptor: knownAsset(input.photo.record.originalJSON, digest: input.photo.reference.digest))
      try add(Self.inputPath(input.reference), input.record.originalJSON,
        descriptor: knownAsset(input.record.originalJSON, digest: input.reference.digest))
    } else if case .present = drawing.input {
      throw FlowPortfolioError.invalid("Authoring history requires the complete original image-input closure.")
    }
    let encoder = DrawingArtifactCoding.encoder()
    let index: [String: Any] = ["profile": "adaptiveplotter.exchange/1", "requiredFeatures": [String](),
      "kind": "drawing", "roots": try JSONSerialization.jsonObject(with: encoder.encode([reference])),
      "includedAsOf": ISO8601DateFormatter().string(from: candidate.createdAt),
      "assets": try JSONSerialization.jsonObject(with: encoder.encode(descriptors.values.sorted { $0.asset.object.description < $1.asset.object.description })),
      "attempts": [String](), "assessments": [String]()]
    try add("data/exchange.json", JSONSerialization.data(withJSONObject: index, options: [.sortedKeys, .withoutEscapingSlashes]))
    try add("history/raster.json", raster)
    try add("history/preview.png", preview, descriptor: .init(asset: ExchangeAsset(bytes: preview, mediaType: "image/png", encoding: "png")))
    let parts = values.keys.sorted().map { FlowHistoryPart(path: $0, digest: values[$0]!.descriptor.asset.object, byteCount: values[$0]!.bytes.count) }
    let manifest = FlowHistoryManifest(profile: "adaptiveplotter.flow-authoring-history/1", identity: .init(candidate),
      photo: source.photo, sourceImage: source.image, options: round.analysisOptions, drawing: reference,
      originalReference: drawing.reference, inputLink: drawing.input, parentLink: drawing.parent,
      units: .init(drawing.units), input: input?.reference, producerID: drawing.producer.id,
      producerVersion: drawing.producer.version, producerObject: drawing.producer.record,
      producerVerified: drawing.capabilities.producerVerified, parts: parts)
    let bytes = try encoder.encode(manifest)
    var unique: [ExchangeDigest: DrawingLibraryClosureAsset] = [:]
    for value in values.values {
      // Physical CAS parts are opaque. The exact typed descriptors remain in
      // the frozen virtual exchange index for input admission, not in browse roots.
      let descriptor = try knownAsset(value.bytes, digest: value.descriptor.asset.object, opaque: true)
      unique[value.descriptor.asset.object] = .init(descriptor: descriptor, bytes: value.bytes)
    }
    let size = try unique.values.reduce(bytes.count) { try adding($0, $1.bytes.count) }
    guard parts.count <= 32, bytes.count <= 128 * 1024, size <= policy.maximumEntryBytes else {
      throw FlowAuthoringHistoryAdmissionError.limit("This exact authoring closure exceeds its per-drawing read limit.")
    }
    let manifestAsset = try ExchangeAsset(bytes: bytes, mediaType: "application/json", encoding: "utf8-json")
    let manifestReference = FlowPortfolioBlob(sha256: manifestAsset.object.description, byteCount: bytes.count, mediaType: "application/json")
    let location = FlowPortfolioHistoryLocation(parts: unique.values.map {
      .init(sha256: $0.descriptor.asset.object.description, byteCount: $0.bytes.count, mediaType: $0.descriptor.asset.mediaType)
    }.sorted { $0.sha256 < $1.sha256 })
    let assets = unique.values.sorted { $0.descriptor.asset.object.description < $1.descriptor.asset.object.description }
      + [.init(descriptor: .init(asset: manifestAsset), bytes: bytes)]
    return .init(reference: manifestReference, location: location, assets: assets)
  }
  func availability(candidate: FlowPortfolioCandidate, source: FlowPortfolioSource, round: FlowPortfolioRound, library: DrawingLibrary) async throws {
    let (_, files) = try await verified(candidate: candidate, source: source, round: round, library: library)
    // Streaming hashes establish closure integrity without decoding/materializing geometry.
    try files.verifyInventory()
  }
  func read(candidate: FlowPortfolioCandidate, source: FlowPortfolioSource, round: FlowPortfolioRound,
    sourceBytes: Data, library: DrawingLibrary) async throws -> FlowHistoryMaterial {
    let (manifest, files) = try await verified(candidate: candidate, source: source, round: round, library: library)
    try files.verifyInventory()
    let rasterBytes = try files.record(at: "history/raster.json", maximumBytes: policy.maximumEntryBytes)
    let preview = try files.record(at: "history/preview.png", maximumBytes: policy.maximumEntryBytes)
    guard sourceBytes.count == source.image.byteCount, ExchangeDigest.hash(sourceBytes).description == source.image.sha256 else { throw DrawingExchangeError.mismatchedParent }
    let raster = try JSONDecoder().decode(PortraitRaster.self, from: rasterBytes)
    let input = try manifest.input.map { try DrawingImageRecords.admitInput($0, files: files) }
    if let input { guard input.photo.reference == source.photo,
      input.photo.record.original.object.description == source.image.sha256 else { throw DrawingExchangeError.mismatchedParent } }
    let drawingJSON = try files.record(at: Self.drawingPath(manifest.drawing))
    let receiptBytes = try files.record(manifest.producerObject, maximumBytes: policy.maximumEntryBytes)
    _ = try ExchangeJSON.validate(drawingJSON)
    let wire = try JSONDecoder().decode(FlowHistoryDrawingWire.self, from: drawingJSON)
    guard ExchangeDigest.hash(drawingJSON) == manifest.drawing.digest,
      wire.profile == DrawingExchangeCodec.drawingProfile, wire.requiredFeatures.isEmpty,
      wire.ref.issuer == manifest.drawing.issuer, wire.ref.revision == manifest.drawing.revision,
      wire.representation.kind == DrawingExchangeCodec.strokeProfile,
      wire.producer.id == manifest.producerID, wire.producer.version == manifest.producerVersion,
      wire.producer.record == manifest.producerObject, wire.input == manifest.inputLink,
      wire.parent == manifest.parentLink else { throw DrawingExchangeError.mismatchedParent }
    let program = try JSONDecoder().decode(DrawingProgram.self, from: files.record(wire.representation.object, maximumBytes: policy.maximumEntryBytes))
    guard wire.representation.programHash == ExchangeDigest(program.contentHash) else { throw DrawingExchangeError.digestMismatch("History program") }
    let historical = wire.representation.historicalUnits
    if let historical {
      guard ["known", "unknown"].contains(historical.state),
        historical.state == "known" ? historical.units != nil && historical.producerReceipt != nil : historical.units == nil && historical.producerReceipt == nil else { throw DrawingExchangeError.mismatchedParent }
    }
    let units = try DrawingUnits(nominalPenWidthMM: wire.representation.nominalPenWidthMillimeters,
      intendedPhysicalFieldMM: wire.representation.intendedPhysicalFieldMillimeters,
      historical: historical?.units, historicalReceipt: historical?.producerReceipt)
    guard FlowHistoryUnits(units) == manifest.units else { throw DrawingExchangeError.mismatchedParent }
    let receipt = try DrawingProducerReceipt(id: wire.producer.id, version: wire.producer.version, recordJSON: receiptBytes)
    var validator: DrawingProducerValidator?
    if manifest.producerID == PortraitFlowProducerClaim.producerID, manifest.producerVersion == PortraitFlowProducerClaim.version {
      let claim = try JSONDecoder().decode(PortraitFlowProducerClaim.self, from: receiptBytes)
      guard let origin = PortraitFlowDrawingProducer.ReceiptOrigin(rawValue: claim.origin),
        claim.settings.recipe == candidate.recipe, claim.settings.analysisOptions == round.analysisOptions else {
        throw FlowPortfolioError.invalid("Authoring history producer differs from its exact generation request.")
      }
      let result = PortraitRenderResult(raster: raster, program: program, warpManifest: claim.warpManifest)
      let original = PortraitFlowDrawingProducer.Input(data: sourceBytes, sourcePixelExtent: claim.sourcePixelExtent,
        input: claim.input, parent: claim.parent, photo: input?.photo)
      validator = try PortraitFlowDrawingProducer.validator(result: result, input: original, settings: claim.settings, expectedOrigin: origin)
    } else if manifest.producerVerified {
      throw FlowPortfolioError.unavailable("This authoring history producer requires its original semantic validator.")
    }
    if let reference = manifest.input {
      guard wire.input == .present(reference) else { throw DrawingExchangeError.mismatchedParent }
    } else if case .present = wire.input { throw DrawingExchangeError.mismatchedParent }
    guard program.contentHash.description == candidate.programHash, program.strokes.count == candidate.strokeCount,
      receipt.record == manifest.producerObject else { throw DrawingExchangeError.mismatchedParent }
    let drawing: Drawing
    if let validator {
      drawing = try DrawingAdmission.produced(program: program, input: wire.input, parent: wire.parent,
        producer: receipt, units: units, validator: validator)
    } else {
      drawing = try Drawing(program: program, input: wire.input, parent: wire.parent,
        producer: receipt, units: units)
    }
    guard drawing.capabilities.producerVerified == manifest.producerVerified else { throw DrawingExchangeError.mismatchedParent }
    return .init(drawing: drawing, input: input, originalReference: manifest.originalReference, rasterBytes: rasterBytes, preview: preview)
  }
  func bytes(candidate: FlowPortfolioCandidate, source: FlowPortfolioSource, round: FlowPortfolioRound, preview: Bool, library: DrawingLibrary) async throws -> Data {
    let (_, files) = try await verified(candidate: candidate, source: source, round: round, library: library)
    return try files.record(at: preview ? "history/preview.png" : "history/raster.json", maximumBytes: policy.maximumEntryBytes)
  }
  private func verified(candidate: FlowPortfolioCandidate, source: FlowPortfolioSource,
    round: FlowPortfolioRound, library: DrawingLibrary) async throws -> (FlowHistoryManifest, VerifiedExchangeFiles) {
    try open()
    guard let reference = candidate.authoringClosure, (1...128 * 1024).contains(reference.byteCount) else {
      throw FlowPortfolioError.unavailable("This legacy drawing has no durable authoring history closure.")
    }
    let bytes: Data
    if let location = candidate.authoringClosureLocation {
      guard location.storage == "library-assets/1" else { throw FlowPortfolioError.invalid("Unknown authoring history storage.") }
      // A marked Library closure never falls back to the old directory on error.
      bytes = try await library.asset(ExchangeDigest(reference.sha256), maximumBytes: 128 * 1024)
    } else {
      let folder = entry(candidate.id); try regularDirectory(folder)
      let url = folder.appendingPathComponent("manifest.json")
      let info = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
      guard info.isRegularFile == true, info.isSymbolicLink != true, info.fileSize == reference.byteCount else {
        throw FlowPortfolioError.invalid("Authoring history manifest is missing or has changed size.")
      }
      bytes = try Data(contentsOf: url)
    }
    guard bytes.count == reference.byteCount else { throw DrawingExchangeError.mismatchedParent }
    guard ExchangeDigest.hash(bytes).description == reference.sha256 else { throw FlowPortfolioError.invalid("Authoring history manifest digest differs from its candidate.") }
    let manifest = try JSONDecoder().decode(FlowHistoryManifest.self, from: bytes)
    guard manifest.profile == "adaptiveplotter.flow-authoring-history/1", manifest.identity == FlowHistoryIdentity(candidate),
      manifest.photo == source.photo, manifest.sourceImage == source.image, manifest.options == round.analysisOptions,
      (1...32).contains(manifest.parts.count), Set(manifest.parts.map(\.path)).count == manifest.parts.count,
      manifest.parts.allSatisfy({ $0.byteCount > 0 && $0.byteCount <= policy.maximumEntryBytes }) else {
      throw FlowPortfolioError.invalid("Authoring history identity, source or region differs from its candidate.")
    }
    guard manifest.parts.first(where: { $0.path == "history/raster.json" }).map({ $0.digest.description == candidate.raster.sha256 && $0.byteCount == candidate.raster.byteCount }) == true,
      manifest.parts.first(where: { $0.path == "history/preview.png" }).map({ $0.digest.description == candidate.preview.sha256 && $0.byteCount == candidate.preview.byteCount }) == true,
      manifest.parts.first(where: { $0.path == Self.drawingPath(manifest.drawing) })?.digest == manifest.drawing.digest else { throw DrawingExchangeError.mismatchedParent }
    let total = try Dictionary(grouping: manifest.parts, by: \.digest).values.reduce(reference.byteCount) { try adding($0, $1[0].byteCount) }
    guard total <= policy.maximumEntryBytes else { throw FlowPortfolioError.invalid("Authoring history closure exceeds its materialization bound.") }
    var limits = ExchangeCarrierLimits(); limits.maximumEntries = 32
    limits.maximumEntryBytes = UInt64(policy.maximumEntryBytes); limits.maximumExpandedBytes = UInt64(policy.maximumEntryBytes) * 2
    limits.maximumMaterializedBytes = UInt64(policy.maximumEntryBytes) * 4
    let inventory = manifest.parts.map {
      ExchangeCatalogFile(path: $0.path, storagePath: $0.storagePath, digest: $0.digest, byteLength: UInt64($0.byteCount))
    }
    let files: VerifiedExchangeFiles
    if let location = candidate.authoringClosureLocation {
      let expected = Dictionary(grouping: manifest.parts, by: \.digest).mapValues { $0[0].byteCount }
      var declared: [ExchangeDigest: Int] = [:]
      for part in location.parts {
        let digest = try ExchangeDigest(part.sha256)
        guard declared[digest] == nil else { throw FlowPortfolioError.invalid("Duplicate Library history part reference.") }
        declared[digest] = part.byteCount
      }
      guard declared == expected else { throw FlowPortfolioError.invalid("Library history part references differ from the manifest.") }
      files = try await library.assetFiles(inventory, limits: limits)
    } else {
      files = try VerifiedExchangeFiles(catalogRoot: entry(candidate.id), inventory: inventory, limits: limits)
    }
    return (manifest, files)
  }
  private func entry(_ id: UUID) -> URL { root.appendingPathComponent(id.uuidString.lowercased(), isDirectory: true) }
  private static func drawingPath(_ r: DrawingRef) -> String { "data/drawings/" + r.issuer.uuidString.lowercased() + "/" + r.revision.uuidString.lowercased() + "/drawing.json" }
  private static func photoPath(_ r: PhotoRef) -> String { "data/photos/" + r.issuer.uuidString.lowercased() + "/" + r.revision.uuidString.lowercased() + "/photo.json" }
  private static func inputPath(_ r: ImageInputRef) -> String { "data/inputs/" + r.issuer.uuidString.lowercased() + "/" + r.revision.uuidString.lowercased() + "/input.json" }
  private func adding(_ a: Int, _ b: Int) throws -> Int {
    guard b >= 0, a <= Int.max - b else { throw FlowPortfolioError.invalid("Authoring history byte count overflow.") }; return a + b
  }
  private func regularDirectory(_ url: URL) throws {
    let info = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
    guard info.isDirectory == true, info.isSymbolicLink != true else { throw FlowPortfolioError.unavailable("Authoring history directory is missing or unsafe.") }
  }
}
