import Foundation

/// Unsupported major indexes are preserved without inventing v1 roots, dates or scope.
public enum ExchangeIndexAdmission: Sendable {
  case known(ExchangeIndex)
  case opaque(originalJSON: Data, profile: String)
  public var originalJSON: Data {
    switch self { case .known(let index): return index.originalJSON; case .opaque(let bytes, _): return bytes }
  }
  public var known: ExchangeIndex? { if case .known(let index) = self { return index }; return nil }
}

/// Immutable wire bytes are the export representation. Typed fields are inspection views only.
public struct ExchangeIndex: Sendable {
  public let originalJSON: Data
  public let profile: String
  public let requiredFeatures: [String]
  public let kind: String
  public let roots: [DrawingRef]
  public let includedAsOf: String
  public let assets: [ExchangeAssetDescriptor]
  public let attempts: [SnapshotRef]
  public let assessments: [AssessmentRef]
  public let photos: [PhotoRef]
  public let inputs: [ImageInputRef]
  public let jobs: [JobReceiptRef]
  public let rankingCapsules: [RankingCapsuleRef]
  public let scope: ExchangeAsset?
  public init(originalJSON: Data) throws {
    let j = try ExchangeJSON.validate(originalJSON)
    self.originalJSON = originalJSON
    profile = try envelopeValue(j, "profile")
    guard exchangeNamespacedID(profile) else { throw DrawingExchangeError.malformed("Index profile") }
    guard profile == "adaptiveplotter.exchange/1" else { throw DrawingExchangeError.unsupportedProfile(profile) }
    requiredFeatures = try envelopeFeatures(j, optional: true)
    kind = try envelopeValue(j, "kind")
    roots = try envelopeValue(j, "roots")
    includedAsOf = try envelopeValue(j, "includedAsOf")
    guard exchangeDate(includedAsOf) != nil else { throw DrawingExchangeError.malformed("Index includedAsOf") }
    assets = try envelopeValue(j, "assets")
    attempts = try envelopeValue(j, "attempts")
    assessments = try envelopeValue(j, "assessments")
    photos = try envelopeOptional(j, "photos") ?? []
    inputs = try envelopeOptional(j, "inputs") ?? []
    jobs = try envelopeOptional(j, "jobs") ?? []
    rankingCapsules = try envelopeOptional(j, "rankingCapsules") ?? []
    scope = try envelopeOptional(j, "scope")
    if ["drawing", "result"].contains(kind), roots.isEmpty { throw DrawingExchangeError.malformed("Missing drawing roots") }
    if kind == "result", jobs.isEmpty { throw DrawingExchangeError.malformed("Result needs receipt roots") }
  }
}
public struct ExchangeJobClient: Codable, Hashable, Sendable {
  public let namespace: UUID
  public let request: UUID
  public let requestDigest: ExchangeDigest
  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: Keys.self)
    namespace = try exchangeUUID(c.decode(String.self, forKey: .namespace))
    request = try exchangeUUID(c.decode(String.self, forKey: .request))
    requestDigest = try c.decode(ExchangeDigest.self, forKey: .requestDigest)
  }
  enum Keys: String, CodingKey { case namespace, request, requestDigest }
  public func encode(to encoder: Encoder) throws {
    var c = encoder.container(keyedBy: Keys.self)
    try c.encode(namespace.uuidString.lowercased(), forKey: .namespace)
    try c.encode(request.uuidString.lowercased(), forKey: .request)
    try c.encode(requestDigest, forKey: .requestDigest)
  }
}
public struct ExchangeJobReceipt: Sendable {
  public let originalJSON: Data
  public let requiredFeatures: [String]
  public let handle: JobRef
  public let client: ExchangeJobClient
  public let drawing: DrawingRef
  public let preparedPlan: ExchangeAsset
  public let requestedMediumOptions: ExchangeAsset
  public let issuedAt: ExchangeTimestamp
  public let disposition: String
  public let reason: String
  public let issuance: UUID?
  public init(originalJSON: Data) throws {
    let j = try envelopeObject(originalJSON, profile: "adaptiveplotter.plot-job-receipt/1")
    self.originalJSON = originalJSON; requiredFeatures = try envelopeFeatures(j)
    handle = try envelopeValue(j, "handle"); client = try envelopeValue(j, "client")
    drawing = try envelopeValue(j, "drawing"); preparedPlan = try envelopeValue(j, "preparedPlan")
    requestedMediumOptions = try envelopeValue(j, "requestedMediumOptions")
    issuedAt = try envelopeValue(j, "issuedAt"); disposition = try envelopeValue(j, "disposition")
    reason = try envelopeValue(j, "reason")
    guard !reason.isEmpty else { throw DrawingExchangeError.malformed("Receipt reason") }
    if let value: String = try envelopeOptional(j, "issuance") { issuance = try exchangeUUID(value) } else { issuance = nil }
    if disposition == "accepted", issuance == nil { throw DrawingExchangeError.malformed("Accepted receipt has no issuance") }
    if disposition == "refused", issuance != nil { throw DrawingExchangeError.malformed("Refusal has issuance") }
  }
}
public struct ExchangeAttemptSnapshot: Sendable {
  public let originalJSON: Data
  public let requiredFeatures: [String]
  public let issuerArchive: UUID
  public let run: UUID
  public let sequence: UInt64
  public let previous: ExchangeDigest?
  public let sealed: Bool
  public let drawing: DrawingRef
  public let job: JobReceiptRef
  public let environment: String
  public let intent: ExchangeDigest
  public let coverage: ExchangeDigest
  public let state: String
  public let dispatch: String
  public let observation: String
  public let terminalRecord: ExchangeDigest?
  public let assessments: [AssessmentRef]
  public let plan: ExchangeAsset?
  public init(originalJSON: Data) throws {
    let j = try envelopeObject(originalJSON, profile: "adaptiveplotter.plot-attempt/1")
    self.originalJSON = originalJSON; requiredFeatures = try envelopeFeatures(j)
    issuerArchive = try exchangeUUID(envelopeValue(j, "issuerArchive")); run = try exchangeUUID(envelopeValue(j, "run"))
    sequence = try envelopeValue(j, "sequence")
    guard sequence > 0, sequence <= 9_007_199_254_740_991 else { throw DrawingExchangeError.malformed("Snapshot sequence") }
    previous = try envelopeNullable(j, "previous"); sealed = try envelopeValue(j, "sealed")
    drawing = try envelopeValue(j, "drawing"); job = try envelopeValue(j, "job")
    environment = try envelopeValue(j, "environment"); intent = try envelopeValue(j, "intent")
    coverage = try envelopeValue(j, "coverage"); state = try envelopeValue(j, "state")
    dispatch = try envelopeValue(j, "dispatch"); observation = try envelopeValue(j, "observation")
    terminalRecord = try envelopeNullable(j, "terminalRecord"); assessments = try envelopeValue(j, "assessments")
    plan = try envelopeOptional(j, "plan")
    guard (sequence == 1) == (previous == nil) else { throw DrawingExchangeError.malformed("Snapshot predecessor") }
    if let clocks = j["clockSynchronizations"] {
      guard let list = clocks as? [[String: Any]] else { throw DrawingExchangeError.malformed("Clock synchronizations") }
      for clock in list {
        for key in ["fromClock", "toClock"] {
          let value: String = try envelopeValue(clock, key)
          guard !value.isEmpty else { throw DrawingExchangeError.malformed("Clock identity") }
        }
        for key in ["fromBootSession", "toBootSession"] { _ = try exchangeUUID(envelopeValue(clock, key)) }
        for key in ["fromTicks", "toTicks"] {
          let ticks: String = try envelopeValue(clock, key)
          guard !ticks.isEmpty, ticks.utf8.allSatisfy({ (48...57).contains($0) }), ticks == "0" || !ticks.hasPrefix("0") else { throw DrawingExchangeError.malformed("Clock ticks") }
        }
        let error: Double = try envelopeValue(clock, "errorBoundSeconds")
        guard error >= 0 else { throw DrawingExchangeError.malformed("Clock error bound") }
      }
    }
  }
}
public enum ExchangeAssessmentTarget: Sendable {
  case drawing(DrawingRef), attempt(SnapshotRef), rankingCapsule(RankingCapsuleRef), asset(ExchangeAsset)
  case opaque(kind: String)
}
public struct ExchangeAssessment: Sendable {
  public let originalJSON: Data
  public let requiredFeatures: [String]
  public let identity: ExchangeIdentity
  public let targets: [ExchangeAssessmentTarget]
  public let supportingAssets: [ExchangeAsset]
  public let supersedes: [AssessmentRef]
  public let answerType: String
  public let unsupportedReasons: [String]
  public init(originalJSON: Data) throws {
    let j = try envelopeObject(originalJSON, profile: "adaptiveplotter.assessment/1")
    self.originalJSON = originalJSON; requiredFeatures = try envelopeFeatures(j); identity = try envelopeValue(j, "ref")
    var reasons: [String] = []
    guard let rawTargets = j["targets"] as? [[String: Any]], !rawTargets.isEmpty else { throw DrawingExchangeError.malformed("Assessment targets") }
    targets = try rawTargets.map { target in
      let kind: String = try envelopeValue(target, "kind")
      if ["drawing", "attempt", "ranking-capsule", "asset"].contains(kind),
        Set(target.keys) != Set(["kind", kind == "asset" ? "asset" : "ref"]) { throw DrawingExchangeError.malformed("Assessment target shape") }
      switch kind {
      case "drawing": return .drawing(try envelopeValue(target, "ref"))
      case "attempt": return .attempt(try envelopeValue(target, "ref"))
      case "ranking-capsule": return .rankingCapsule(try envelopeValue(target, "ref"))
      case "asset": return .asset(try envelopeValue(target, "asset"))
      default:
        reasons.append("Unsupported assessment target: " + kind)
        return .opaque(kind: kind)
      }
    }
    if let reason = try envelopeReviewer(j["reviewer"]) { reasons.append(reason) }
    try envelopeQuestion(j["question"])
    let _: ExchangeAsset? = try envelopeOptional(j, "regionOrStrokes")
    let _: ExchangeTimestamp = try envelopeValue(j, "time")
    guard let answer = j["answer"] as? [String: Any], answer["value"] != nil else { throw DrawingExchangeError.malformed("Typed answer") }
    let _: ExchangeAsset? = try envelopeOptional(answer, "schema")
    answerType = try envelopeValue(answer, "type")
    guard exchangeNamespacedID(answerType) else { throw DrawingExchangeError.malformed("Answer type") }
    supportingAssets = try envelopeValue(j, "supportingAssets"); supersedes = try envelopeOptional(j, "supersedes") ?? []
    unsupportedReasons = reasons
  }
}
public struct ExchangeRankingCapsule: Sendable {
  public static let partialRankingFeature = "adaptiveplotter.feature-ranking.partial-ranking/1"
  public static let neitherFeature = "adaptiveplotter.feature-ranking.neither/1"
  static let localFeatures: Set<String> = [partialRankingFeature, neitherFeature]
  public let originalJSON: Data
  public let requiredFeatures: [String]
  public let identity: ExchangeIdentity
  public let presentationIDs: [UUID]
  public let responseKind: String
  public let unsupportedReasons: [String]
  public init(originalJSON: Data) throws {
    let j = try envelopeObject(originalJSON, profile: "adaptiveplotter.feature-ranking/1")
    self.originalJSON = originalJSON; requiredFeatures = try envelopeFeatures(j); identity = try envelopeValue(j, "ref")
    let geometry: String = try envelopeValue(j, "geometry"), limitations: String = try envelopeValue(j, "limitations")
    guard geometry == "omitted", limitations == "Features only; no geometry re-extraction or arbitrary future image labels." else { throw DrawingExchangeError.malformed("Ranking limitations") }
    let _: ExchangeTimestamp = try envelopeValue(j, "createdAt")
    var reasons: [String] = []
    if let reason = try envelopeReviewer(j["reviewer"]) { reasons.append(reason) }
    try envelopeQuestion(j["question"])
    guard let presentations = j["presentations"] as? [[String: Any]], presentations.count >= 2 else { throw DrawingExchangeError.malformed("Ranking presentations") }
    for presentation in presentations {
      let _: ExchangeAsset = try envelopeValue(presentation, "features")
      for key in ["producer", "extractor"] {
        guard let producer = presentation[key] as? [String: Any] else { throw DrawingExchangeError.malformed("Ranking producer") }
        let id: String = try envelopeValue(producer, "id"), version: String = try envelopeValue(producer, "version")
        let _: ExchangeDigest = try envelopeValue(producer, "record")
        guard exchangeNamespacedID(id), !version.isEmpty else { throw DrawingExchangeError.malformed("Ranking producer identity") }
      }
    }
    presentationIDs = try presentations.map { try exchangeUUID(envelopeValue($0, "id")) }
    guard Set(presentationIDs).count == presentationIDs.count else { throw DrawingExchangeError.malformed("Duplicate ranking presentation") }
    guard let response = j["response"] as? [String: Any] else { throw DrawingExchangeError.malformed("Ranking response") }
    responseKind = try envelopeValue(response, "kind")
    switch responseKind {
    case "ranking":
      let groups: [[String]] = try envelopeValue(response, "groups")
      guard Set(response.keys) == ["kind", "groups"], !groups.isEmpty, groups.allSatisfy({ !$0.isEmpty }) else { throw DrawingExchangeError.malformed("Ranking groups") }
      let ids = try groups.flatMap { try $0.map(exchangeUUID) }
      guard ids.count == presentationIDs.count, Set(ids) == Set(presentationIDs), Set(ids).count == ids.count else { throw DrawingExchangeError.malformed("Ranking membership") }
    case "skip":
      let reason: String = try envelopeValue(response, "reason")
      guard Set(response.keys) == ["kind", "reason"], !reason.isEmpty else { throw DrawingExchangeError.malformed("Ranking skip") }
    case "partial-ranking":
      let groups: [[String]] = try envelopeValue(response, "groups")
      let unranked: [String] = try envelopeValue(response, "unranked")
      guard requiredFeatures.contains(Self.partialRankingFeature),
        Set(response.keys) == ["kind", "groups", "unranked"], groups.allSatisfy({ !$0.isEmpty }) else {
        throw DrawingExchangeError.malformed("Partial ranking response or required feature")
      }
      let ids = try (groups.flatMap { $0 } + unranked).map(exchangeUUID)
      guard ids.count == presentationIDs.count, Set(ids) == Set(presentationIDs), Set(ids).count == ids.count else {
        throw DrawingExchangeError.malformed("Partial ranking membership")
      }
    case "neither":
      guard requiredFeatures.contains(Self.neitherFeature), Set(response.keys) == ["kind"] else {
        throw DrawingExchangeError.malformed("Neither response or required feature")
      }
    default: reasons.append("Unsupported ranking response: " + responseKind)
    }
    unsupportedReasons = reasons
  }
}
func envelopeValue<T: Decodable>(_ j: [String: Any], _ key: String) throws -> T {
  guard let value = j[key], !(value is NSNull) else { throw DrawingExchangeError.malformed("Missing or null " + key) }
  return try DrawingImageAdmission.decode(value, as: T.self)
}
func envelopeOptional<T: Decodable>(_ j: [String: Any], _ key: String) throws -> T? {
  guard j[key] != nil else { return nil }; return try envelopeValue(j, key)
}
func envelopeNullable<T: Decodable>(_ j: [String: Any], _ key: String) throws -> T? {
  guard let value = j[key] else { throw DrawingExchangeError.malformed("Missing " + key) }
  return value is NSNull ? nil : try envelopeValue(j, key)
}
func envelopeFeatures(_ j: [String: Any], optional: Bool = false) throws -> [String] {
  if optional, j["requiredFeatures"] == nil { return [] }
  let features: [String] = try envelopeValue(j, "requiredFeatures")
  guard Set(features).count == features.count, features.allSatisfy(exchangeNamespacedID) else { throw DrawingExchangeError.malformed("Required features") }
  return features
}
func envelopeObject(_ bytes: Data, profile: String) throws -> [String: Any] {
  let j = try ExchangeJSON.validate(bytes); let actual: String = try envelopeValue(j, "profile")
  guard actual == profile else { throw DrawingExchangeError.unsupportedProfile(actual) }; return j
}
func envelopeReviewer(_ value: Any?) throws -> String? {
  guard let j = value as? [String: Any] else { throw DrawingExchangeError.malformed("Reviewer") }
  let kind: String = try envelopeValue(j, "kind"), id: String = try envelopeValue(j, "id")
  guard !id.isEmpty else { throw DrawingExchangeError.malformed("Reviewer ID") }
  if let version: String = try envelopeOptional(j, "version"), version.isEmpty { throw DrawingExchangeError.malformed("Reviewer version") }
  if kind == "algorithm", j["version"] == nil { throw DrawingExchangeError.malformed("Algorithm reviewer requires version") }
  if kind != "algorithm" && kind != "human" { return "Unsupported reviewer kind: " + kind }
  return nil
}
func envelopeQuestion(_ value: Any?) throws {
  guard let j = value as? [String: Any] else { throw DrawingExchangeError.malformed("Question") }
  let id: String = try envelopeValue(j, "id"), version: String = try envelopeValue(j, "version"), text: String = try envelopeValue(j, "text")
  guard exchangeNamespacedID(id), !version.isEmpty, !text.isEmpty else { throw DrawingExchangeError.malformed("Question fields") }
}
