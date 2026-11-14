import Darwin
import Foundation
import DrawingLibrary
import PlotterModel
import PortraitArtists
import PortraitCore

/// Private authoring material, not a retained Drawing or a preference. Existing
/// entries are never evicted to admit new work: a full spool refuses admission.
package struct FlowAuthoringHistoryPolicy: Sendable {
  package let maximumEntries: Int
  package let maximumBytes: Int
  package let maximumEntryBytes: Int
  package init(maximumEntries: Int = 512, maximumBytes: Int = 2 * 1024 * 1024 * 1024,
    maximumEntryBytes: Int = 64 * 1024 * 1024) {
    self.maximumEntries = maximumEntries; self.maximumBytes = maximumBytes
    self.maximumEntryBytes = maximumEntryBytes
  }
}
package struct FlowAuthoringHistoryStatistics: Sendable {
  package let entryCount: Int
  package let byteCount: Int
}
package enum FlowAuthoringHistoryBoundary: Sendable, Equatable { case beforeWrite, afterParts, beforePublish }
package enum FlowAuthoringHistoryAdmissionError: Error, Sendable {
  case limit(String)
  package var reason: String { switch self { case .limit(let reason): return reason } }
}

private struct FlowHistoryIdentity: Codable, Equatable {
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
private struct FlowHistoryPart: Codable {
  let path: String
  let digest: ExchangeDigest
  let byteCount: Int
  var storagePath: String { digest.description + ".part" }
}
private struct FlowHistoryDrawingWire: Decodable {
  struct Producer: Decodable { let id: String; let version: String; let record: ExchangeDigest }
  struct Historical: Decodable { let state: String; let units: String?; let producerReceipt: ExchangeDigest? }
  struct Representation: Decodable {
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
private struct FlowHistoryUnits: Codable, Equatable {
  let nominal: Double?
  let field: Size2<FieldSpace>?
  let historical: String?
  let historicalReceipt: ExchangeDigest?
  init(_ value: DrawingUnits) {
    nominal = value.nominalPenWidthMM; field = value.intendedPhysicalFieldMM
    historical = value.historical; historicalReceipt = value.historicalReceipt
  }
}
private struct FlowHistoryManifest: Codable {
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
struct FlowHistoryMaterial {
  let drawing: Drawing
  let input: FrozenImageInputRecord?
  let originalReference: DrawingRef?
  let rasterBytes: Data
  let preview: Data
}

/// The actor owns this single writer after DrawingLibrary has acquired its lease.
/// Manifest hashes live in candidate graph records; files cannot relabel a candidate.
final class FlowAuthoringHistory {
  let root: URL
  let policy: FlowAuthoringHistoryPolicy
  var fault: (@Sendable (FlowAuthoringHistoryBoundary) throws -> Void)?
  private var opened = false
  private var accounted: FlowAuthoringHistoryStatistics?
  init(directory: URL, policy: FlowAuthoringHistoryPolicy) {
    root = directory.appendingPathComponent("flow-authoring-history-v1", isDirectory: true)
    self.policy = policy
  }
  func open() throws {
    guard !opened else { return }
    guard policy.maximumEntries > 0, policy.maximumBytes > 0,
      policy.maximumEntryBytes > 0, policy.maximumEntryBytes <= Self.maximumRehydrationBytes else {
      throw FlowPortfolioError.invalid("Invalid authoring history storage policy.")
    }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true,
      attributes: [.posixPermissions: 0o700])
    try regularDirectory(root)
    for item in try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey])
      where item.lastPathComponent.hasPrefix(".partial-") {
      // Only unpublished staging is disposable. Complete orphans stay counted.
      try regularDirectory(item); try FileManager.default.removeItem(at: item)
    }
    opened = true
    do { accounted = try scanStatistics() } catch { opened = false; throw error }
  }
  static let maximumRehydrationBytes = 64 * 1024 * 1024
  func statistics() throws -> FlowAuthoringHistoryStatistics {
    try open(); return accounted!
  }
  func auditStatistics() throws -> FlowAuthoringHistoryStatistics { try open(); return try scanStatistics() }
  private func scanStatistics() throws -> FlowAuthoringHistoryStatistics {
    let entries = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isSymbolicLinkKey])
    var total = 0
    for entry in entries {
      let values = try entry.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey, .isRegularFileKey, .fileSizeKey])
      guard values.isSymbolicLink != true else { throw FlowPortfolioError.invalid("Authoring history contains a symbolic link.") }
      if values.isRegularFile == true { total = try adding(total, values.fileSize ?? 0); continue }
      try regularDirectory(entry)
      guard let files = FileManager.default.enumerator(at: entry, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]) else {
        throw FlowPortfolioError.unavailable("Authoring history cannot be enumerated.")
      }
      for case let file as URL in files {
        let info = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .isDirectoryKey, .fileSizeKey])
        guard info.isSymbolicLink != true else { throw FlowPortfolioError.invalid("Authoring history contains a symbolic link.") }
        if info.isRegularFile == true { total = try adding(total, info.fileSize ?? 0) }
        else if info.isDirectory != true { throw FlowPortfolioError.invalid("Authoring history contains an unsupported file.") }
      }
    }
    return .init(entryCount: entries.count, byteCount: total)
  }
  func requireRoundCapacity(_ count: Int) throws {
    let usage = try statistics()
    guard count <= policy.maximumEntries - usage.entryCount, usage.byteCount < policy.maximumBytes else {
      throw FlowPortfolioError.invalid("Authoring history storage is full. Existing drawing branches are preserved; new generation was not admitted.")
    }
  }
  func write(candidate: FlowPortfolioCandidate, source: FlowPortfolioSource, round: FlowPortfolioRound,
    drawing: Drawing, input: FrozenImageInputRecord?, raster: Data, preview: Data, issuer: UUID) throws -> FlowPortfolioBlob {
    try open(); try fault?(.beforeWrite)
    guard drawing.requiredFeatures.isEmpty else { throw FlowPortfolioError.invalid("This drawing requires unsupported authoring history features.") }
    let frozen = try DrawingExchangeCodec.freeze(drawing, identity: .init(issuer: issuer, revision: candidate.id), createdAt: candidate.createdAt)
    guard let reference = frozen.drawing.reference else { throw DrawingExchangeError.mismatchedParent }
    var values: [String: Data] = [:]
    var descriptors: [ExchangeDigest: ExchangeAssetDescriptor] = [:]
    func add(_ path: String, _ bytes: Data) throws {
      if let old = values[path], old != bytes { throw FlowPortfolioError.invalid("Conflicting authoring history content.") }
      values[path] = bytes
    }
    func asset(_ value: DrawingLibraryClosureAsset) throws {
      try value.descriptor.asset.validate(value.bytes, maximumBytes: Self.maximumRehydrationBytes)
      if let old = descriptors[value.descriptor.asset.object], old != value.descriptor {
        throw FlowPortfolioError.invalid("Conflicting authoring history asset descriptors.")
      }
      descriptors[value.descriptor.asset.object] = value.descriptor
      try add("data/objects/sha256/" + value.descriptor.asset.object.description, value.bytes)
    }
    let programAsset = try ExchangeAsset(bytes: frozen.originalProgramJSON, mediaType: "application/json", encoding: "utf8-json")
    let producerAsset = try ExchangeAsset(bytes: drawing.producer.originalJSON, mediaType: "application/json", encoding: "utf8-json")
    try asset(.init(descriptor: .init(asset: programAsset), bytes: frozen.originalProgramJSON))
    try asset(.init(descriptor: .init(asset: producerAsset), bytes: drawing.producer.originalJSON))
    try add(Self.drawingPath(reference), frozen.originalJSON)
    if let input {
      guard drawing.input == .present(input.reference), input.photo.reference == source.photo else { throw DrawingExchangeError.mismatchedParent }
      let closure = DrawingLibraryRetainedClosure(input: input)
      for value in closure.assets { try asset(value) }
      for record in closure.records {
        switch record.reference {
        case .photo(let ref): try add(Self.photoPath(ref), record.originalJSON)
        case .input(let ref): try add(Self.inputPath(ref), record.originalJSON)
        case .drawing: throw FlowPortfolioError.invalid("Unexpected drawing in frozen input closure.")
        }
      }
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
    try add("history/raster.json", raster); try add("history/preview.png", preview)
    let parts = values.keys.sorted().map { FlowHistoryPart(path: $0, digest: .hash(values[$0]!), byteCount: values[$0]!.count) }
    let manifest = FlowHistoryManifest(profile: "adaptiveplotter.flow-authoring-history/1", identity: .init(candidate),
      photo: source.photo, sourceImage: source.image, options: round.analysisOptions, drawing: reference,
      originalReference: drawing.reference, inputLink: drawing.input, parentLink: drawing.parent,
      units: .init(drawing.units), input: input?.reference, producerID: drawing.producer.id,
      producerVersion: drawing.producer.version, producerObject: drawing.producer.record,
      producerVerified: drawing.capabilities.producerVerified, parts: parts)
    let bytes = try encoder.encode(manifest)
    let unique = Dictionary(grouping: parts, by: \.digest).values.map { $0[0] }
    let size = try unique.reduce(bytes.count) { try adding($0, $1.byteCount) }
    let usage = try statistics()
    guard parts.count <= 32, bytes.count <= 128 * 1024, size <= policy.maximumEntryBytes,
      usage.entryCount < policy.maximumEntries, size <= policy.maximumBytes - usage.byteCount else {
      throw FlowAuthoringHistoryAdmissionError.limit("Authoring history storage cannot fit this exact drawing closure. Existing branches are preserved.")
    }
    let target = entry(candidate.id)
    guard !FileManager.default.fileExists(atPath: target.path) else { throw FlowPortfolioError.conflict("Authoring history identity already exists.") }
    let stage = root.appendingPathComponent(".partial-" + UUID().uuidString.lowercased(), isDirectory: true)
    try FileManager.default.createDirectory(at: stage, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
    accounted = .init(entryCount: usage.entryCount + 1, byteCount: usage.byteCount + size)
    var published = false
    defer {
      if !published {
        do { try FileManager.default.removeItem(at: stage); accounted = usage }
        catch { /* The reserved upper bound includes incomplete staging until reopen. */ }
      }
    }
    for part in unique { try durableFile(values[part.path]!, at: stage.appendingPathComponent(part.storagePath)) }
    try fault?(.afterParts)
    try durableFile(bytes, at: stage.appendingPathComponent("manifest.json"))
    try syncDirectory(stage); try fault?(.beforePublish)
    try FileManager.default.moveItem(at: stage, to: target)
    published = true; try syncDirectory(root)
    return .init(sha256: ExchangeDigest.hash(bytes).description, byteCount: bytes.count, mediaType: "application/json")
  }
  func availability(candidate: FlowPortfolioCandidate, source: FlowPortfolioSource, round: FlowPortfolioRound) throws {
    let (_, files) = try verified(candidate: candidate, source: source, round: round)
    // Streaming hashes establish closure integrity without decoding/materializing geometry.
    try files.verifyInventory()
  }
  func read(candidate: FlowPortfolioCandidate, source: FlowPortfolioSource, round: FlowPortfolioRound,
    sourceBytes: Data) throws -> FlowHistoryMaterial {
    let (manifest, files) = try verified(candidate: candidate, source: source, round: round)
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
  func bytes(candidate: FlowPortfolioCandidate, source: FlowPortfolioSource, round: FlowPortfolioRound, preview: Bool) throws -> Data {
    let (_, files) = try verified(candidate: candidate, source: source, round: round)
    return try files.record(at: preview ? "history/preview.png" : "history/raster.json", maximumBytes: policy.maximumEntryBytes)
  }
  private func verified(candidate: FlowPortfolioCandidate, source: FlowPortfolioSource,
    round: FlowPortfolioRound) throws -> (FlowHistoryManifest, VerifiedExchangeFiles) {
    try open()
    guard let reference = candidate.authoringClosure else { throw FlowPortfolioError.unavailable("This legacy drawing has no durable authoring history closure.") }
    let folder = entry(candidate.id); try regularDirectory(folder)
    let url = folder.appendingPathComponent("manifest.json")
    let info = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
    guard info.isRegularFile == true, info.isSymbolicLink != true, info.fileSize == reference.byteCount,
      reference.byteCount <= 128 * 1024 else { throw FlowPortfolioError.invalid("Authoring history manifest is missing or has changed size.") }
    let bytes = try Data(contentsOf: url)
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
    let files = try VerifiedExchangeFiles(catalogRoot: folder, inventory: manifest.parts.map {
      .init(path: $0.path, storagePath: $0.storagePath, digest: $0.digest, byteLength: UInt64($0.byteCount))
    }, limits: limits)
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
  private func durableFile(_ bytes: Data, at url: URL) throws {
    let fd = Darwin.open(url.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
    guard fd >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
    defer { Darwin.close(fd) }
    try bytes.withUnsafeBytes { buffer in
      var offset = 0
      while offset < buffer.count {
        let count = Darwin.write(fd, buffer.baseAddress!.advanced(by: offset), buffer.count - offset)
        if count < 0 && errno == EINTR { continue }
        guard count > 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        offset += count
      }
    }
    guard fsync(fd) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
  }
  private func syncDirectory(_ url: URL) throws {
    let fd = Darwin.open(url.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
    guard fd >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
    defer { Darwin.close(fd) }
    guard fsync(fd) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
  }
}
