import Foundation

public struct ExchangeClosureLimits: Sendable {
  public var maximumRecords = 10_000
  public var maximumDepth = 64
  public var maximumRecordBytes = ExchangeJSON.maximumRecordBytes
  public var maximumMaterializedBytes: UInt64 = 256 * 1024 * 1024
  public init() {}
}
public enum ExchangeOperation: String, Hashable, Sendable { case preserve, inspect, drawing, interpretResults, train, physicalInterpretation }
public struct ExchangeCapabilities: Sendable {
  public let supported: Set<ExchangeOperation>
  public let unsupportedReasons: [String]
}
public struct ExchangePayloadKey: Hashable, Sendable {
  public let encoding: String
  public let version: String
  public init(encoding: String, version: String) { self.encoding = encoding; self.version = version }
}
/// These are assertions of a trusted owner codec, not fields trusted from exchange JSON.
/// Omitted historical facts remain unknown and never become zero frontiers.
public struct ExchangePayloadFacts: Sendable {
  public var run: UUID?
  public var job: JobRef?
  public var drawing: DrawingRef?
  public var clientRequestDigest: ExchangeDigest?
  public var clientNamespace: UUID?
  public var clientRequest: UUID?
  public var issuance: UUID?
  public var programSemanticHash: ExchangeDigest?
  public var programObjectDigest: ExchangeDigest?
  public var plan: ExchangeDigest?
  public var preMotion: ExchangeDigest?
  public var frontiers: [String: UInt64]
  public init(run: UUID? = nil, job: JobRef? = nil, drawing: DrawingRef? = nil,
    clientRequestDigest: ExchangeDigest? = nil, clientNamespace: UUID? = nil, clientRequest: UUID? = nil, issuance: UUID? = nil, programSemanticHash: ExchangeDigest? = nil, programObjectDigest: ExchangeDigest? = nil,
    plan: ExchangeDigest? = nil, preMotion: ExchangeDigest? = nil, frontiers: [String: UInt64] = [:]) {
    self.run = run; self.job = job; self.drawing = drawing; self.clientRequestDigest = clientRequestDigest; self.clientNamespace = clientNamespace; self.clientRequest = clientRequest
    self.issuance = issuance; self.programSemanticHash = programSemanticHash; self.programObjectDigest = programObjectDigest; self.plan = plan; self.preMotion = preMotion; self.frontiers = frontiers
  }
}
public enum ExchangePayloadValidation: Sendable { case verified(ExchangePayloadFacts), unsupported(reason: String) }
public struct ExchangePayloadContext: Sendable {
  public let current: ExchangeAttemptSnapshot?
  public let prior: ExchangeAttemptSnapshot?
  public let receipt: ExchangeJobReceipt?
  public let drawing: DrawingRef?
  public let descriptor: ExchangeAssetDescriptor
  public let resolver: ExchangePayloadResolver
}
/// Enforces a shared load budget and per-record bound, including inside owner callbacks.
public final class ExchangePayloadResolver: @unchecked Sendable {
  private let files: VerifiedExchangeFiles
  private let maximum: Int
  private let budget: UInt64
  private var used: UInt64 = 0
  private let lock = NSLock()
  fileprivate init(files: VerifiedExchangeFiles, limits: ExchangeClosureLimits) {
    self.files = files; maximum = limits.maximumRecordBytes; budget = limits.maximumMaterializedBytes
  }
  public func record(_ digest: ExchangeDigest, maximumBytes: Int = ExchangeJSON.maximumRecordBytes) throws -> Data {
    let size = try files.byteLength(digest)
    lock.lock(); defer { lock.unlock() }
    guard maximumBytes > 0, size <= UInt64(min(maximum, maximumBytes)), used <= budget, size <= budget - used else { throw DrawingExchangeError.limit("Closure materialization budget") }
    used += size
    return try files.record(digest, maximumBytes: min(maximum, maximumBytes))
  }
  public func byteLength(_ digest: ExchangeDigest) throws -> UInt64 { try files.byteLength(digest) }
}
public typealias ExchangePayloadValidator = @Sendable (ExchangePayloadContext) throws -> ExchangePayloadValidation
public struct ExchangePayloadValidators: Sendable {
  let validators: [ExchangePayloadKey: ExchangePayloadValidator]
  public init(_ validators: [ExchangePayloadKey: ExchangePayloadValidator] = [:]) { self.validators = validators }
}
/// Only semantic admission can construct this token. It grants no readiness or retry authority.
public struct ValidatedExchangePackage: Sendable {
  public let files: VerifiedExchangeFiles
  public let index: ExchangeIndexAdmission
  public let drawings: [DrawingRef: DrawingRecordAdmission]
  public let receipts: [JobReceiptRef: ExchangeJobReceipt]
  public let attempts: [SnapshotRef: ExchangeAttemptSnapshot]
  public let assessments: [AssessmentRef: ExchangeAssessment]
  public let rankingCapsules: [RankingCapsuleRef: ExchangeRankingCapsule]
  public let opaqueRecords: [String: Data]
  public let capabilities: ExchangeCapabilities
  public let assetSupport: [ExchangeDigest: ExchangeAssetSupport]
  public let integrityVerified: Bool
  public let knownClosureSemanticsSupported: Bool
  public var statistics: ExchangeCarrierStatistics { files.statistics }
  fileprivate init(_ v: ExchangeClosureValidator) {
    files = v.originalFiles; index = v.indexAdmission
    let unresolvedIndexFeatures = v.index?.requiredFeatures.filter { !v.features.contains($0) } ?? []
    // Index requirements are external context, not intrinsic Drawing requirements.
    // Withhold unrestricted values until that context is understood; a bare Drawing
    // could otherwise be edited or frozen into a new occurrence without the index.
    drawings = v.drawings.mapValues { admission in
      guard !unresolvedIndexFeatures.isEmpty, case .materialized(let frozen) = admission else { return admission }
      return .opaque(originalJSON: frozen.originalJSON, profile: DrawingExchangeCodec.drawingProfile)
    }
    receipts = v.receipts; attempts = v.attempts
    assessments = v.assessments; rankingCapsules = v.rankings; opaqueRecords = v.opaque
    assetSupport = v.assetSupport
    integrityVerified = true
    var supported: Set<ExchangeOperation> = [.preserve, .inspect]
    let envelopeReasons = v.reasons.filter {
      !$0.hasPrefix("Unsupported owner payload semantics:") && !$0.hasPrefix("Unsupported owner binding semantics:") && !$0.hasPrefix("Unsupported assessment answer semantics:")
    }
    knownClosureSemanticsSupported = envelopeReasons.isEmpty
    if knownClosureSemanticsSupported { supported.insert(.drawing) }
    if v.reasons.isEmpty { supported.insert(.interpretResults) }
    // Training and physical interpretation additionally require task-specific and native owner admission.
    capabilities = .init(supported: supported, unsupportedReasons: Array(v.reasons).sorted())
  }
}
/// Proof for one selected authored closure. It does not assert that unselected
/// publication assets, jobs, attempts, or transport manifests were revalidated.
public struct SelectedDrawingAdmission: Sendable {
  public let originalIndexJSON: Data
  public let indexDigest: ExchangeDigest
  public let reference: DrawingRef
  public let admission: DrawingRecordAdmission
  public let capabilities: ExchangeCapabilities
  public let files: VerifiedExchangeFiles
  public var statistics: ExchangeCarrierStatistics { files.statistics }
  fileprivate init(_ validator: ExchangeClosureValidator, selected: DrawingRef) throws {
    originalIndexJSON = validator.indexAdmission.originalJSON; indexDigest = .hash(originalIndexJSON)
    reference = selected; files = validator.originalFiles
    var selectedAdmission = validator.drawings[selected]
    let unsupportedContext = validator.index == nil || !(validator.index?.requiredFeatures.filter { !validator.features.contains($0) }.isEmpty ?? false)
      || !(validator.index.map { ["drawing", "result", "feedback"].contains($0.kind) } ?? false)
    if unsupportedContext, let value = selectedAdmission, case .materialized(let frozen) = value {
      selectedAdmission = .opaque(originalJSON: frozen.originalJSON, profile: DrawingExchangeCodec.drawingProfile)
    }
    guard let selectedAdmission else {
      throw DrawingExchangeError.unsupportedProfile("Selected drawing is unavailable under this exchange index")
    }
    admission = selectedAdmission
    var supported: Set<ExchangeOperation> = [.preserve, .inspect]
    if validator.reasons.isEmpty { supported.insert(.drawing) }
    capabilities = .init(supported: supported, unsupportedReasons: Array(validator.reasons).sorted())
  }
}

public enum ExchangeAdmission {
  /// Admits one exact catalog inventory without a transport restaging round trip.
  /// The resolver establishes every file's bytes before the existing full closure
  /// validator grants its proof. This is not selected-Drawing admission.
  public static func validate(files: VerifiedExchangeFiles,
    producerValidators: DrawingProducerValidators = .init(),
    payloadValidators: ExchangePayloadValidators = .init(), supportedFeatures: Set<String> = [],
    limits: ExchangeClosureLimits = .init()) throws -> ValidatedExchangePackage {
    try files.verifyInventory()
    let bounded = files.scoped(maximumMaterializedBytes: limits.maximumMaterializedBytes)
    guard try bounded.record(at: "bagit.txt", maximumBytes: limits.maximumRecordBytes) == DrawingExchangeCarrier.bagit else {
      throw DrawingExchangeError.malformed("Exact BagIt header")
    }
    let payload = try DrawingExchangeCarrier.manifest(bounded.record(at: "manifest-sha256.txt", maximumBytes: limits.maximumRecordBytes))
    let tags = try DrawingExchangeCarrier.manifest(bounded.record(at: "tagmanifest-sha256.txt", maximumBytes: limits.maximumRecordBytes))
    guard payload.keys.allSatisfy({ $0.hasPrefix("data/") }), !payload.isEmpty,
      !tags.keys.contains("tagmanifest-sha256.txt"), tags["bagit.txt"] != nil, tags["manifest-sha256.txt"] != nil,
      tags.keys.allSatisfy({ !$0.hasPrefix("data/") && $0 != "fetch.txt" && !$0.hasPrefix("manifest-") || $0 == "manifest-sha256.txt" }),
      files.entries["fetch.txt"] == nil,
      Set(files.entries.keys) == Set(payload.keys).union(tags.keys).union(["tagmanifest-sha256.txt"]) else {
      throw DrawingExchangeError.malformed("Exact manifest closure")
    }
    for (path, digest) in payload.merging(tags, uniquingKeysWith: { a, _ in a }) {
      guard files.entries[path]?.digest == digest else { throw DrawingExchangeError.digestMismatch(path) }
    }
    let index = try files.scoped(maximumMaterializedBytes: limits.maximumMaterializedBytes)
      .record(at: "data/exchange.json", maximumBytes: limits.maximumRecordBytes)
    let staged = StagedExchangePackage(files: files, indexJSON: index, stagingURL: files.stagingURL)
    return try validate(staged, producerValidators: producerValidators,
      payloadValidators: payloadValidators, supportedFeatures: supportedFeatures, limits: limits)
  }
  public static func selectDrawing(originalIndexJSON: Data, selected: DrawingRef,
    files: VerifiedExchangeFiles, producerValidators: DrawingProducerValidators = .init(),
    supportedFeatures: Set<String> = [], limits: ExchangeClosureLimits = .init()) throws -> SelectedDrawingAdmission {
    let sealedIndex = try files.scoped(maximumMaterializedBytes: limits.maximumMaterializedBytes)
      .record(at: "data/exchange.json", maximumBytes: limits.maximumRecordBytes)
    guard sealedIndex == originalIndexJSON else { throw DrawingExchangeError.digestMismatch("Selected exchange index context") }
    let staged = StagedExchangePackage(files: files, indexJSON: sealedIndex, stagingURL: files.stagingURL)
    let validator = try ExchangeClosureValidator(staged, producers: producerValidators, payloads: .init(),
      features: supportedFeatures, limits: limits)
    try validator.validateSelectedDrawing(selected)
    return try SelectedDrawingAdmission(validator, selected: selected)
  }
  public static func validate(_ staged: StagedExchangePackage, producerValidators: DrawingProducerValidators = .init(),
    payloadValidators: ExchangePayloadValidators = .init(), supportedFeatures: Set<String> = [],
    limits: ExchangeClosureLimits = .init()) throws -> ValidatedExchangePackage {
    let validator = try ExchangeClosureValidator(staged, producers: producerValidators, payloads: payloadValidators,
      features: supportedFeatures, limits: limits)
    try validator.validate()
    return ValidatedExchangePackage(validator)
  }
}
fileprivate final class ExchangeClosureValidator {
  let originalFiles: VerifiedExchangeFiles
  let files: VerifiedExchangeFiles
  let index: ExchangeIndex?
  let indexAdmission: ExchangeIndexAdmission
  let limits: ExchangeClosureLimits
  let producers: DrawingProducerValidators
  let payloads: ExchangePayloadValidators
  let features: Set<String>
  let resolver: ExchangePayloadResolver
  var selectedOnly = false
  var descriptors: [ExchangeDigest: ExchangeAssetDescriptor] = [:]
  var assetSupport: [ExchangeDigest: ExchangeAssetSupport] = [:]
  var drawings: [DrawingRef: DrawingRecordAdmission] = [:]
  var receipts: [JobReceiptRef: ExchangeJobReceipt] = [:]
  var attempts: [SnapshotRef: ExchangeAttemptSnapshot] = [:]
  var assessments: [AssessmentRef: ExchangeAssessment] = [:]
  var rankings: [RankingCapsuleRef: ExchangeRankingCapsule] = [:]
  var opaque: [String: Data] = [:]
  var reasons = Set<String>()
  var identities: [ExchangeIdentity: (String, ExchangeDigest)] = [:]
  var records: [String: Data] = [:]
  var active = Set<String>()
  var completed = Set<String>()
  var clientRequests: [String: (ExchangeDigest, JobRef)] = [:]
  var runForJob: [JobRef: String] = [:]
  var earliestPossibleInk: [String: UInt64] = [:]
  var latestNotDispatched: [String: UInt64] = [:]
  var runForIssuance: [UUID: String] = [:]
  var factsByRun: [String: ExchangePayloadFacts] = [:]
  init(_ staged: StagedExchangePackage, producers: DrawingProducerValidators, payloads: ExchangePayloadValidators,
    features: Set<String>, limits: ExchangeClosureLimits) throws {
    guard limits.maximumRecords > 0, limits.maximumDepth > 0, limits.maximumRecordBytes > 0,
      limits.maximumMaterializedBytes > 0 else { throw DrawingExchangeError.limit("Closure policy") }
    originalFiles = staged.files
    files = staged.files.scoped(maximumMaterializedBytes: limits.maximumMaterializedBytes)
    let json = try ExchangeJSON.validate(staged.indexJSON, maximumBytes: limits.maximumRecordBytes)
    let profile: String = try envelopeValue(json, "profile")
    guard exchangeNamespacedID(profile) else { throw DrawingExchangeError.malformed("Index profile") }
    if profile == "adaptiveplotter.exchange/1" {
      let value = try ExchangeIndex(originalJSON: staged.indexJSON)
      index = value; indexAdmission = .known(value)
    } else {
      guard !knownProfiles.contains(profile) else { throw DrawingExchangeError.malformed("Wrong index profile") }
      index = nil; indexAdmission = .opaque(originalJSON: staged.indexJSON, profile: profile)
    }
    self.producers = producers; self.payloads = payloads
    self.features = features.subtracting(ExchangeRankingCapsule.localFeatures); self.limits = limits
    resolver = .init(files: files, limits: limits)
  }
  func unsupported(_ features: [String]) { for feature in features where !self.features.contains(feature) { reasons.insert("Required feature: " + feature) } }
  func validateSelectedDrawing(_ selected: DrawingRef) throws {
    selectedOnly = true
    guard let index else { throw DrawingExchangeError.unsupportedProfile("Selected exchange index") }
    unsupported(index.requiredFeatures)
    if !["drawing", "result", "feedback"].contains(index.kind) { reasons.insert("Unsupported exchange kind: " + index.kind) }
    guard index.assets.count <= limits.maximumRecords else { throw DrawingExchangeError.limit("Asset descriptor count") }
    // Descriptor metadata may be inspected, but unrelated files remain unopened.
    for descriptor in index.assets {
      if let old = descriptors[descriptor.asset.object], old != descriptor { throw DrawingExchangeError.malformed("Conflicting asset descriptors") }
      descriptors[descriptor.asset.object] = descriptor
    }
    if let scope = index.scope { try asset(scope) }
    try drawing(selected, depth: 0)
  }
  func validate() throws {
    guard let index else {
      if case .opaque(let bytes, let profile) = indexAdmission {
        reasons.insert("Unsupported exchange profile: " + profile); opaque["data/exchange.json"] = bytes
      }
      return
    }
    unsupported(index.requiredFeatures)
    if !["drawing", "result", "feedback"].contains(index.kind) { reasons.insert("Unsupported exchange kind: " + index.kind) }
    guard index.assets.count <= limits.maximumRecords else { throw DrawingExchangeError.limit("Asset descriptor count") }
    for descriptor in index.assets {
      if let old = descriptors[descriptor.asset.object], old != descriptor { throw DrawingExchangeError.malformed("Conflicting asset descriptors") }
      descriptors[descriptor.asset.object] = descriptor
      let path = "data/objects/sha256/" + descriptor.asset.object.description
      guard let file = files.entries[path], file.digest == descriptor.asset.object, file.byteLength == descriptor.asset.byteLength else { throw DrawingExchangeError.digestMismatch("Canonical object descriptor: " + path) }
      assetSupport[descriptor.asset.object] = try files.validateAsset(descriptor)
    }
    if let scope = index.scope { try asset(scope) }
    for ref in index.roots { try drawing(ref, depth: 0) }
    for ref in index.photos { try identityRecord(ref, kind: "photos", depth: 0) }
    for ref in index.inputs { try identityRecord(ref, kind: "inputs", depth: 0) }
    for ref in index.jobs { try receipt(ref, depth: 0) }
    for ref in index.attempts { try attempt(ref, depth: 0) }
    for ref in index.assessments { try assessment(ref, depth: 0) }
    for ref in index.rankingCapsules { try ranking(ref, depth: 0) }
    // The v1 application payload is closed independently of the BagIt manifests.
    // Retained unselected typed records are valid; every object still needs its
    // canonical digest path and an index declaration, even for opaque encodings.
    for path in files.entries.keys.sorted() where path.hasPrefix("data/") && path != "data/exchange.json" {
      if path.hasPrefix("data/objects/") {
        guard let file = files.entries[path], path == "data/objects/sha256/" + file.digest.description,
          descriptors[file.digest] != nil else { throw DrawingExchangeError.malformed("Unindexed or noncanonical object payload: " + path) }
      } else { try discover(path) }
    }
    if index.kind == "result" {
      for ref in index.jobs {
        guard let receipt = receipts[ref] else { reasons.insert("Unsupported result receipt"); continue }
        guard index.roots.contains(receipt.drawing) else { throw DrawingExchangeError.malformed("Receipt drawing is not an exact included root") }
        let matching = attempts.values.filter { $0.job == ref }
        if receipt.disposition == "refused", !matching.isEmpty { throw DrawingExchangeError.malformed("Refused job has attempts") }
        if matching.isEmpty && receipt.disposition == "accepted" { throw DrawingExchangeError.malformed("Zero-attempt result is not refused") }
      }
      for value in attempts.values {
        guard index.jobs.contains(value.job), index.roots.contains(value.drawing) else { throw DrawingExchangeError.malformed("Attempt job/drawing not included in exact result roots") }
      }
    }
  }
  func load(_ path: String, digest: ExchangeDigest? = nil) throws -> Data {
    if let bytes = records[path] {
      if let digest, ExchangeDigest.hash(bytes) != digest { throw DrawingExchangeError.digestMismatch(path) }; return bytes
    }
    guard records.count < limits.maximumRecords, let file = files.entries[path] else { throw DrawingExchangeError.missingAsset(path) }
    if let digest, file.digest != digest { throw DrawingExchangeError.digestMismatch(path) }
    guard limits.maximumRecordBytes > 0, file.byteLength <= UInt64(limits.maximumRecordBytes) else {
      throw DrawingExchangeError.limit("Closure materialization budget")
    }
    _ = try files.pinned(at: path)
    let data = try resolver.record(file.digest, maximumBytes: limits.maximumRecordBytes)
    records[path] = data; return data
  }
  func enter(_ path: String, depth: Int) throws -> Bool {
    guard depth <= limits.maximumDepth else { throw DrawingExchangeError.limit("Closure depth") }
    if completed.contains(path) { return false }
    guard active.insert(path).inserted else { return false }; return true
  }
  func finish(_ path: String) { active.remove(path); completed.insert(path) }
  func profile(_ data: Data, path: String, expected: String, localFeatures: Set<String> = []) throws -> [String: Any]? {
    let j = try ExchangeJSON.validate(data); let p: String = try envelopeValue(j, "profile")
    guard exchangeNamespacedID(p) else { throw DrawingExchangeError.malformed("Record profile") }
    if p != expected {
      guard !knownProfiles.contains(p) else { throw DrawingExchangeError.malformed("Recognized record has wrong kind at " + path) }
      opaque[path] = data; reasons.insert("Unsupported profile: " + p); return nil
    }
    unsupported(try envelopeFeatures(j).filter { !localFeatures.contains($0) }); return j
  }
  func register(_ identity: ExchangeIdentity, kind: String, digest: ExchangeDigest) throws {
    if let old = identities[identity], old.0 != kind || old.1 != digest { throw DrawingExchangeError.malformed("Conflicting global record identity") }
    identities[identity] = (kind, digest)
  }
  func path<T>(_ ref: ExchangeRef<T>, kind: String) -> String {
    let suffix = ["drawings":"drawing.json", "photos":"photo.json", "inputs":"input.json"]
    let base = "data/\(kind)/\(ref.issuer.uuidString.lowercased())/\(ref.revision.uuidString.lowercased())"
    return suffix[kind].map { base + "/" + $0 } ?? base + ".json"
  }
  func asset(_ asset: ExchangeAsset) throws {
    guard let indexed = descriptors[asset.object], indexed.asset == asset else { throw DrawingExchangeError.malformed("Missing or conflicting indexed asset descriptor") }
    guard try files.byteLength(asset.object) == asset.byteLength else { throw DrawingExchangeError.malformed("Asset reference length") }
    if selectedOnly, assetSupport[asset.object] == nil {
      let canonical = "data/objects/sha256/" + asset.object.description
      guard let file = files.entries[canonical], file.digest == asset.object, file.byteLength == asset.byteLength else {
        throw DrawingExchangeError.digestMismatch("Selected canonical object descriptor")
      }
      try files.verify(asset.object)
      assetSupport[asset.object] = try files.validateAsset(indexed)
    }
  }
  func object(_ digest: ExchangeDigest) throws {
    guard let descriptor = descriptors[digest] else { throw DrawingExchangeError.missingAsset("Object descriptor " + digest.description) }; try asset(descriptor.asset)
  }
  func drawing(_ ref: DrawingRef, depth: Int) throws {
    let p = path(ref, kind: "drawings"); try register(ref.identity, kind: "drawing", digest: ref.digest)
    guard try enter(p, depth: depth) else { return }; defer { finish(p) }
    let data = try load(p, digest: ref.digest)
    guard let j = try profile(data, path: p, expected: "adaptiveplotter.drawing/1") else { return }
    let identity: ExchangeIdentity = try envelopeValue(j, "ref")
    guard identity == ref.identity else { throw DrawingExchangeError.digestMismatch("Drawing identity") }
    let input: SourceLink<ImageInputRef> = try envelopeValue(j, "input")
    let parent: SourceLink<DrawingRef> = try envelopeValue(j, "parent")
    if case .present(let value) = input { try identityRecord(value, kind: "inputs", depth: depth + 1) }
    if case .present(let value) = parent { guard !active.contains(path(value, kind: "drawings")) else { throw DrawingExchangeError.malformed("Cyclic drawing parent") }; try drawing(value, depth: depth + 1) }
    guard let representation = j["representation"] as? [String: Any], let producer = j["producer"] as? [String: Any] else { throw DrawingExchangeError.malformed("Drawing representation/producer") }
    try object(envelopeValue(representation, "object")); try producerRecord(producer)
    let admitted = try DrawingExchangeCodec.decode(data, files: files, expected: ref, validators: producers,
      supportedFeatures: features, assetDescriptors: descriptors)
    drawings[ref] = admitted
    if case .opaque = admitted { reasons.insert("Unsupported drawing representation") }
  }
  func identityRecord<T>(_ ref: ExchangeRef<T>, kind: String, depth: Int) throws {
    let p = path(ref, kind: kind); try register(ref.identity, kind: kind, digest: ref.digest)
    guard try enter(p, depth: depth) else { return }; defer { finish(p) }
    let data = try load(p, digest: ref.digest)
    let expected = kind == "photos" ? "adaptiveplotter.photo/1" : "adaptiveplotter.image-input/1"
    guard let j = try profile(data, path: p, expected: expected) else { return }
    let identity: ExchangeIdentity = try envelopeValue(j, "ref")
    guard identity == ref.identity else { throw DrawingExchangeError.digestMismatch("Source record identity") }
    if kind == "photos" {
      let original: ExchangeAsset = try envelopeValue(j, "original"); try asset(original)
      if let capture: ExchangeAsset = try envelopeOptional(j, "captureFacts") { try asset(capture) }
      let photo = PhotoRef(issuer: ref.issuer, revision: ref.revision, digest: ref.digest)
      let result = try DrawingImageAdmission.photo(photo, files: files, supportedFeatures: features, assetDescriptors: descriptors)
      if !result.supportedSemantics { reasons.insert("Unsupported photo semantics") }
    } else {
      let raster: ExchangeAsset = try envelopeValue(j, "raster"); try asset(raster)
      if let mask = j["mask"] as? [String: Any], mask["state"] as? String == "present" { let a: ExchangeAsset = try envelopeValue(mask, "asset"); try asset(a) }
      guard let operations = j["operations"] as? [[String: Any]], let preparation = j["preparation"] as? [String: Any] else { throw DrawingExchangeError.malformed("Input operations/preparation") }
      for operation in operations { let a: ExchangeAsset = try envelopeValue(operation, "parameters"); try asset(a) }
      try producerRecord(preparation)
      let photo: PhotoRef = try envelopeValue(j, "photo"); try identityRecord(photo, kind: "photos", depth: depth + 1)
      let input = ImageInputRef(issuer: ref.issuer, revision: ref.revision, digest: ref.digest)
      let result = try DrawingImageAdmission.input(input, files: files, supportedFeatures: features, assetDescriptors: descriptors)
      if !result.supportedSemantics { reasons.insert("Unsupported input semantics") }
    }
  }
  func producerRecord(_ j: [String: Any]) throws {
    let id: String = try envelopeValue(j, "id"), version: String = try envelopeValue(j, "version")
    guard exchangeNamespacedID(id), !version.isEmpty else { throw DrawingExchangeError.malformed("Producer") }
    let digest: ExchangeDigest = try envelopeValue(j, "record"); try object(digest)
    _ = try ExchangeJSON.validate(resolver.record(digest))
  }
  func receipt(_ ref: JobReceiptRef, depth: Int) throws {
    let p = "data/jobs/\(ref.engine.uuidString.lowercased())/\(ref.job.uuidString.lowercased())/receipt.json"
    guard try enter(p, depth: depth) else {
      if let old = receipts.keys.first(where: { $0.handle == ref.handle }), old != ref { throw DrawingExchangeError.malformed("Conflicting receipt pin") }; return
    }; defer { finish(p) }
    let data = try load(p, digest: ref.receiptDigest)
    guard try profile(data, path: p, expected: "adaptiveplotter.plot-job-receipt/1") != nil else { return }
    let r = try ExchangeJobReceipt(originalJSON: data)
    guard r.handle == ref.handle else { throw DrawingExchangeError.malformed("Receipt handle/path") }
    let requestKey = r.client.namespace.uuidString + "/" + r.client.request.uuidString
    if let old = clientRequests[requestKey], old.0 != r.client.requestDigest || old.1 != r.handle { throw DrawingExchangeError.malformed("Client request conflict") }
    clientRequests[requestKey] = (r.client.requestDigest, r.handle)
    receipts[ref] = r
    try drawing(r.drawing, depth: depth + 1); try asset(r.preparedPlan); try asset(r.requestedMediumOptions)
    if !["accepted", "refused"].contains(r.disposition) { reasons.insert("Unsupported job disposition: " + r.disposition) }
    _ = try payload(r.preparedPlan.object, current: nil, prior: nil, receipt: r)
    _ = try payload(r.requestedMediumOptions.object, current: nil, prior: nil, receipt: r)
  }
  func attemptPath(_ ref: SnapshotRef) -> String {
    "data/attempts/\(ref.archive.uuidString.lowercased())/\(ref.run.uuidString.lowercased())/\(ref.sequence)/attempt.json"
  }
  func attempt(_ ref: SnapshotRef, depth: Int) throws {
    let p = attemptPath(ref)
    guard try enter(p, depth: depth) else { _ = try load(p, digest: ref.digest); return }; defer { finish(p) }
    let data = try load(p, digest: ref.digest)
    guard try profile(data, path: p, expected: "adaptiveplotter.plot-attempt/1") != nil else { return }
    let a = try ExchangeAttemptSnapshot(originalJSON: data)
    guard a.issuerArchive == ref.archive, a.run == ref.run, a.sequence == ref.sequence else { throw DrawingExchangeError.malformed("Snapshot path/reference") }
    attempts[ref] = a
    let runKey = a.issuerArchive.uuidString + "/" + a.run.uuidString
    if let old = runForJob[a.job.handle], old != runKey { throw DrawingExchangeError.malformed("Multiple runs for job") }
    runForJob[a.job.handle] = runKey
    // Retain known testimony across unsupported string states and traversal order.
    // An unknown dispatch assertion never establishes clearance from possible ink.
    if a.dispatch == "possibleInk" { earliestPossibleInk[runKey] = min(earliestPossibleInk[runKey] ?? a.sequence, a.sequence) }
    if a.dispatch == "not-dispatched" { latestNotDispatched[runKey] = max(latestNotDispatched[runKey] ?? a.sequence, a.sequence) }
    if let ink = earliestPossibleInk[runKey], let clear = latestNotDispatched[runKey], clear > ink {
      throw DrawingExchangeError.malformed("Possible ink reversion")
    }
    for (value, allowed) in [(a.environment, ["live", "simulation"]), (a.state, ["staged", "running", "cancelling", "interrupted", "completed", "failed", "cancelled"]), (a.dispatch, ["not-dispatched", "possibleInk"]), (a.observation, ["accepted", "rejected", "unavailable"])] where !allowed.contains(value) { reasons.insert("Unsupported snapshot enum: " + value) }
    // Validate every independently recognizable claim in this known envelope before
    // unsupported dependencies can gate cross-record or native owner interpretation.
    try drawing(a.drawing, depth: depth + 1)
    if let plan = a.plan { try asset(plan) }
    try object(a.intent); try object(a.coverage)
    if let terminal = a.terminalRecord { try object(terminal) }
    try coverage(a.coverage, depth: depth + 1)
    for assessment in a.assessments { try self.assessment(assessment, depth: depth + 1) }
    try receipt(a.job, depth: depth + 1)
    var prior: ExchangeAttemptSnapshot?
    if let previous = a.previous {
      let previousRef = try SnapshotRef(archive: ref.archive, run: ref.run, sequence: ref.sequence - 1, digest: previous)
      try attempt(previousRef, depth: depth + 1)
      if let value = attempts[previousRef] {
        guard !value.sealed, value.drawing == a.drawing, value.job == a.job,
          value.environment == a.environment, value.intent == a.intent else { throw DrawingExchangeError.malformed("Snapshot chain changed binding or follows seal") }
        prior = value
      } else { reasons.insert("Unsupported predecessor semantics") }
    }
    guard let r = receipts[a.job] else { reasons.insert("Unsupported attempt receipt"); return }
    guard a.drawing == r.drawing, r.disposition != "refused" else { throw DrawingExchangeError.malformed("Snapshot job/drawing/refusal") }
    if let plan = a.plan, plan != r.preparedPlan { throw DrawingExchangeError.malformed("Snapshot prepared plan differs from receipt") }
    if let issuance = r.issuance {
      if let old = runForIssuance[issuance], old != runKey { throw DrawingExchangeError.malformed("Multiple runs for issuance") }
      runForIssuance[issuance] = runKey
    }
    guard a.previous == nil || prior != nil else { return }
    for digest in [a.intent, a.coverage] + (a.terminalRecord.map { [$0] } ?? []) + (a.plan.map { [$0.object] } ?? []) {
      if let facts = try payload(digest, current: a, prior: prior, receipt: r) {
        try checkFacts(facts, snapshot: a, receipt: r)
        let merged = try merge(factsByRun[runKey], facts)
        try checkFacts(merged, snapshot: a, receipt: r)
        factsByRun[runKey] = merged
      }
    }
    let facts = factsByRun[runKey]
    if facts?.run == nil || facts?.job == nil || facts?.drawing == nil || facts?.clientRequestDigest == nil || facts?.issuance == nil || facts?.plan == nil || facts?.preMotion == nil || facts?.programSemanticHash == nil {
      reasons.insert("Unsupported owner binding semantics: incomplete run/request/program/plan/pre-motion proof")
    }
  }
  func payload(_ digest: ExchangeDigest, current: ExchangeAttemptSnapshot?, prior: ExchangeAttemptSnapshot?, receipt: ExchangeJobReceipt?) throws -> ExchangePayloadFacts? {
    try object(digest)
    guard let descriptor = descriptors[digest] else { throw DrawingExchangeError.missingAsset(digest.description) }
    let encoding = descriptor.asset.encoding
    let version = encoding.split(separator: "/").last.map(String.init) ?? ""
    guard let validator = payloads.validators[.init(encoding: encoding, version: version)] else {
      reasons.insert("Unsupported owner payload semantics: " + encoding); return nil
    }
    let context = ExchangePayloadContext(current: current, prior: prior, receipt: receipt, drawing: current?.drawing ?? receipt?.drawing,
      descriptor: descriptor, resolver: resolver)
    switch try validator(context) {
    case .unsupported(let reason): reasons.insert(reason); return nil
    case .verified(let facts):
      if let receipt { try checkFacts(facts, snapshot: current, receipt: receipt) }
      return facts
    }
  }
  func checkFacts(_ f: ExchangePayloadFacts, snapshot: ExchangeAttemptSnapshot?, receipt: ExchangeJobReceipt) throws {
    if let drawing = f.drawing, drawing != receipt.drawing { throw DrawingExchangeError.malformed("Owner payload drawing") }
    if let job = f.job, job != receipt.handle { throw DrawingExchangeError.malformed("Owner payload job") }
    if let request = f.clientRequestDigest, request != receipt.client.requestDigest { throw DrawingExchangeError.malformed("Owner payload client request digest") }
    if let namespace = f.clientNamespace, namespace != receipt.client.namespace { throw DrawingExchangeError.malformed("Owner payload client namespace") }
    if let request = f.clientRequest, request != receipt.client.request { throw DrawingExchangeError.malformed("Owner payload client request identity") }
    if let issuance = f.issuance, issuance != receipt.issuance { throw DrawingExchangeError.malformed("Owner payload issuance") }
    if let run = f.run, let snapshot, run != snapshot.run { throw DrawingExchangeError.malformed("Owner payload run") }
    if let plan = f.plan, plan != receipt.preparedPlan.object { throw DrawingExchangeError.malformed("Owner payload prepared plan") }
    if f.programSemanticHash != nil || f.programObjectDigest != nil {
      let data = try load(path(receipt.drawing, kind: "drawings"), digest: receipt.drawing.digest)
      let json = try ExchangeJSON.validate(data)
      if let representation = json["representation"] as? [String: Any], representation["kind"] as? String == "adaptiveplotter.stroke-program/1" {
        let semantic: ExchangeDigest = try envelopeValue(representation, "programHash")
        let object: ExchangeDigest = try envelopeValue(representation, "object")
        if let value = f.programSemanticHash, value != semantic { throw DrawingExchangeError.malformed("Owner semantic program hash") }
        if let value = f.programObjectDigest, value != object { throw DrawingExchangeError.malformed("Owner exact program object digest") }
      } else { reasons.insert("Unsupported owner binding semantics: unfamiliar drawing representation") }
    }
    let order = ["planned", "commanded", "controllerCompleted", "inkVerified"]
    guard Set(f.frontiers.keys).isSubset(of: Set(order)) else { throw DrawingExchangeError.malformed("Unknown verified frontier") }
    for i in 0..<order.count { for k in (i + 1)..<order.count {
      if let upper = f.frontiers[order[i]], let lower = f.frontiers[order[k]], lower > upper { throw DrawingExchangeError.malformed("Owner frontier ordering") }
    } }
  }
  func merge(_ old: ExchangePayloadFacts?, _ new: ExchangePayloadFacts) throws -> ExchangePayloadFacts {
    guard let old else { return new }
    func stable<T: Equatable>(_ a: T?, _ b: T?) throws -> T? {
      if let a, let b, a != b { throw DrawingExchangeError.malformed("Owner facts changed immutable binding") }; return b ?? a
    }
    var result = ExchangePayloadFacts(run: try stable(old.run, new.run), job: try stable(old.job, new.job),
      drawing: try stable(old.drawing, new.drawing), clientRequestDigest: try stable(old.clientRequestDigest, new.clientRequestDigest),
      clientNamespace: try stable(old.clientNamespace, new.clientNamespace), clientRequest: try stable(old.clientRequest, new.clientRequest),
      issuance: try stable(old.issuance, new.issuance), programSemanticHash: try stable(old.programSemanticHash, new.programSemanticHash),
      programObjectDigest: try stable(old.programObjectDigest, new.programObjectDigest),
      plan: try stable(old.plan, new.plan), preMotion: try stable(old.preMotion, new.preMotion), frontiers: old.frontiers)
    for (key, value) in new.frontiers {
      if let previous = old.frontiers[key], value < previous { throw DrawingExchangeError.malformed("Owner frontier reversion") }; result.frontiers[key] = value
    }
    return result
  }
  func coverage(_ digest: ExchangeDigest, depth: Int) throws {
    let p = "data/objects/sha256/" + digest.description
    let bytes = try load(p, digest: digest)
    guard let j = try profile(bytes, path: p, expected: "adaptiveplotter.coverage/1") else { return }
    let _: ExchangeTimestamp = try envelopeValue(j, "includedAsOf")
    guard let entries = j["entries"] as? [[String: Any]], let frontiers = j["frontiers"] as? [String: Any] else { throw DrawingExchangeError.malformed("Coverage inventory") }
    for key in ["planned", "commanded", "controllerCompleted", "inkVerified"] where frontiers[key] == nil { throw DrawingExchangeError.malformed("Missing frontier status") }
    let knownFrontiers = try ["planned", "commanded", "controllerCompleted", "inkVerified"].map { key -> [String: Any] in
      guard let entry = frontiers[key] as? [String: Any] else { throw DrawingExchangeError.malformed("Frontier entry") }; return entry
    }
    for entry in entries + knownFrontiers {
      let kind: String = try envelopeValue(entry, "kind"), status: String = try envelopeValue(entry, "status")
      guard exchangeNamespacedID(kind) else { throw DrawingExchangeError.malformed("Evidence kind") }
      for key in ["source", "reason"] {
        if let value: String = try envelopeOptional(entry, key), value.isEmpty { throw DrawingExchangeError.malformed("Empty evidence " + key) }
      }
      // Unsupported status does not erase a recognizable asset claim beside it.
      if let claimed: ExchangeAsset = try envelopeOptional(entry, "asset") { try asset(claimed) }
      if status == "present" { let a: ExchangeAsset = try envelopeValue(entry, "asset"); try asset(a) }
      else if ["never-captured", "unavailable", "intentionally-withheld"].contains(status) {
        let reason: String = try envelopeValue(entry, "reason")
        guard !reason.isEmpty, entry["asset"] == nil else { throw DrawingExchangeError.malformed("Unavailable evidence") }
      } else { reasons.insert("Unsupported evidence status: " + status) }
      if let time: ExchangeTimestamp = try envelopeOptional(entry, "captureTime") { _ = time }
      if let a: AssessmentRef = try envelopeOptional(entry, "assessment") { try assessment(a, depth: depth + 1) }
      if let registration: ExchangeAsset = try envelopeOptional(entry, "registration") { try asset(registration) }
    }
  }
  func assessment(_ ref: AssessmentRef, depth: Int) throws {
    let p = path(ref, kind: "assessments"); try register(ref.identity, kind: "assessment", digest: ref.digest)
    guard try enter(p, depth: depth) else { _ = try load(p, digest: ref.digest); return }; defer { finish(p) }
    let data = try load(p, digest: ref.digest)
    guard let j = try profile(data, path: p, expected: "adaptiveplotter.assessment/1") else { return }
    let a = try ExchangeAssessment(originalJSON: data)
    guard a.identity == ref.identity else { throw DrawingExchangeError.malformed("Assessment identity") }
    assessments[ref] = a; reasons.formUnion(a.unsupportedReasons)
    for value in a.supportingAssets { try asset(value) }
    if let value: ExchangeAsset = try envelopeOptional(j, "regionOrStrokes") { try asset(value) }
    if let answer = j["answer"] as? [String: Any], let schema: ExchangeAsset = try envelopeOptional(answer, "schema") { try asset(schema) }
    for target in a.targets {
      switch target {
      case .drawing(let value): try drawing(value, depth: depth + 1)
      case .attempt(let value): try attempt(value, depth: depth + 1)
      case .rankingCapsule(let value): try ranking(value, depth: depth + 1)
      case .asset(let value): try asset(value)
      case .opaque: break
      }
    }
    for value in a.supersedes { try assessment(value, depth: depth + 1) }
    reasons.insert("Unsupported assessment answer semantics: " + a.answerType)
  }
  func ranking(_ ref: RankingCapsuleRef, depth: Int) throws {
    let p = path(ref, kind: "rankings"); try register(ref.identity, kind: "ranking", digest: ref.digest)
    guard try enter(p, depth: depth) else { _ = try load(p, digest: ref.digest); return }; defer { finish(p) }
    let data = try load(p, digest: ref.digest)
    guard let j = try profile(data, path: p, expected: "adaptiveplotter.feature-ranking/1", localFeatures: ExchangeRankingCapsule.localFeatures) else { return }
    let r = try ExchangeRankingCapsule(originalJSON: data)
    guard r.identity == ref.identity else { throw DrawingExchangeError.malformed("Ranking identity") }
    rankings[ref] = r; reasons.formUnion(r.unsupportedReasons)
    guard let presentations = j["presentations"] as? [[String: Any]] else { throw DrawingExchangeError.malformed("Ranking presentations") }
    for presentation in presentations {
      let features: ExchangeAsset = try envelopeValue(presentation, "features"); try asset(features)
      for key in ["producer", "extractor"] {
        guard let producer = presentation[key] as? [String: Any] else { throw DrawingExchangeError.malformed("Ranking producer") }
        try producerRecord(producer)
      }
    }
  }
  func discover(_ p: String) throws {
    let parts = p.split(separator: "/").map(String.init)
    guard parts.count >= 4 else { throw DrawingExchangeError.malformed("Typed record path") }
    let bytes = try load(p), digest = ExchangeDigest.hash(bytes)
    switch parts[1] {
    case "drawings", "photos", "inputs":
      guard parts.count == 5, parts[4] == ["drawings":"drawing.json", "photos":"photo.json", "inputs":"input.json"][parts[1]] else { throw DrawingExchangeError.malformed("Record path") }
      let issuer = try exchangeUUID(parts[2]), revision = try exchangeUUID(parts[3])
      if parts[1] == "drawings" { try drawing(.init(issuer: issuer, revision: revision, digest: digest), depth: 0) }
      else if parts[1] == "photos" { try identityRecord(PhotoRef(issuer: issuer, revision: revision, digest: digest), kind: "photos", depth: 0) }
      else { try identityRecord(ImageInputRef(issuer: issuer, revision: revision, digest: digest), kind: "inputs", depth: 0) }
    case "assessments", "rankings":
      guard parts.count == 4, parts[3].hasSuffix(".json") else { throw DrawingExchangeError.malformed("Feedback path") }
      let issuer = try exchangeUUID(parts[2]), revision = try exchangeUUID(String(parts[3].dropLast(5)))
      if parts[1] == "assessments" { try assessment(.init(issuer: issuer, revision: revision, digest: digest), depth: 0) }
      else { try ranking(.init(issuer: issuer, revision: revision, digest: digest), depth: 0) }
    case "jobs":
      guard parts.count == 5, parts[4] == "receipt.json" else { throw DrawingExchangeError.malformed("Job path") }
      try receipt(.init(handle: .init(engine: exchangeUUID(parts[2]), job: exchangeUUID(parts[3])), receiptDigest: digest), depth: 0)
    case "attempts":
      guard parts.count == 6, parts[5] == "attempt.json", let sequence = UInt64(parts[4]), String(sequence) == parts[4] else { throw DrawingExchangeError.malformed("Attempt path") }
      try attempt(.init(archive: exchangeUUID(parts[2]), run: exchangeUUID(parts[3]), sequence: sequence, digest: digest), depth: 0)
    default: throw DrawingExchangeError.malformed("Unknown typed payload path: " + p)
    }
  }
}
private let knownProfiles: Set<String> = ["adaptiveplotter.exchange/1", "adaptiveplotter.drawing/1", "adaptiveplotter.photo/1", "adaptiveplotter.image-input/1", "adaptiveplotter.plot-job-receipt/1", "adaptiveplotter.plot-attempt/1", "adaptiveplotter.assessment/1", "adaptiveplotter.feature-ranking/1", "adaptiveplotter.coverage/1"]
