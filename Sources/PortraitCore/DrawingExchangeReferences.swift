import Foundation
import PlotterModel

public enum DrawingExchangeError: Error, Equatable, Sendable {
  case malformed(String), limit(String), digestMismatch(String), missingAsset(String)
  case invalidProducer(String), unsupportedFeature(String), unsupportedProfile(String)
  case mismatchedParent, unknownStroke, duplicateStroke, noChange, allStrokesRemoved
}

/// Wire digests deliberately encode as lowercase hex, unlike the legacy Digest payload.
public struct ExchangeDigest: Hashable, Codable, Sendable, CustomStringConvertible {
  public let description: String
  public init(_ hex: String) throws {
    guard hex.utf8.count == 64, hex.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else {
      throw DrawingExchangeError.malformed("SHA-256 must be 64 lowercase hex digits")
    }
    description = hex
  }
  public init(_ digest: Digest) { description = digest.description }
  public static func hash(_ bytes: Data) -> Self { try! Self(DrawingPackageCodec.sha256(bytes)) }
  public init(from decoder: Decoder) throws { try self.init(decoder.singleValueContainer().decode(String.self)) }
  public func encode(to encoder: Encoder) throws { var c = encoder.singleValueContainer(); try c.encode(description) }
}

public struct ExchangeIdentity: Hashable, Codable, Sendable {
  public let issuer: UUID
  public let revision: UUID
  public init(issuer: UUID, revision: UUID = UUID()) { self.issuer = issuer; self.revision = revision }
  enum CodingKeys: String, CodingKey { case issuer, revision }
  public init(from decoder: Decoder) throws {
    try exchangeClosedKeys(decoder, allowed: ["issuer", "revision"])
    let c = try decoder.container(keyedBy: CodingKeys.self)
    issuer = try exchangeUUID(c.decode(String.self, forKey: .issuer))
    revision = try exchangeUUID(c.decode(String.self, forKey: .revision))
  }
  public func encode(to encoder: Encoder) throws {
    var c = encoder.container(keyedBy: CodingKeys.self)
    try c.encode(issuer.uuidString.lowercased(), forKey: .issuer)
    try c.encode(revision.uuidString.lowercased(), forKey: .revision)
  }
}
func exchangeUUID(_ value: String) throws -> UUID {
  guard let id = UUID(uuidString: value), id.uuidString.lowercased() == value else {
    throw DrawingExchangeError.malformed("UUID must have lowercase canonical spelling")
  }
  return id
}
public enum DrawingReferenceTag: Sendable {}
public enum PhotoReferenceTag: Sendable {}
public enum ImageInputReferenceTag: Sendable {}
public enum AssessmentReferenceTag: Sendable {}
public enum RankingCapsuleReferenceTag: Sendable {}
public struct ExchangeRef<Tag: Sendable>: Hashable, Codable, Sendable {
  public let issuer: UUID
  public let revision: UUID
  public let digest: ExchangeDigest
  public var identity: ExchangeIdentity { .init(issuer: issuer, revision: revision) }
  public init(issuer: UUID, revision: UUID, digest: ExchangeDigest) {
    self.issuer = issuer; self.revision = revision; self.digest = digest
  }
  enum CodingKeys: String, CodingKey { case issuer, revision, digest }
  public init(from decoder: Decoder) throws {
    try exchangeClosedKeys(decoder, allowed: ["issuer", "revision", "digest"])
    let c = try decoder.container(keyedBy: CodingKeys.self)
    issuer = try exchangeUUID(c.decode(String.self, forKey: .issuer))
    revision = try exchangeUUID(c.decode(String.self, forKey: .revision))
    digest = try c.decode(ExchangeDigest.self, forKey: .digest)
  }
  public func encode(to encoder: Encoder) throws {
    var c = encoder.container(keyedBy: CodingKeys.self)
    try c.encode(issuer.uuidString.lowercased(), forKey: .issuer)
    try c.encode(revision.uuidString.lowercased(), forKey: .revision)
    try c.encode(digest, forKey: .digest)
  }
}
public typealias DrawingRef = ExchangeRef<DrawingReferenceTag>
public typealias PhotoRef = ExchangeRef<PhotoReferenceTag>
public typealias ImageInputRef = ExchangeRef<ImageInputReferenceTag>
public typealias AssessmentRef = ExchangeRef<AssessmentReferenceTag>
public typealias RankingCapsuleRef = ExchangeRef<RankingCapsuleReferenceTag>

public enum SourceLink<Reference: Codable & Hashable & Sendable>: Hashable, Codable, Sendable {
  case none
  case present(Reference)
  case unavailable(reason: String, knownRef: Reference?)
  enum CodingKeys: String, CodingKey { case state, ref, reason, knownRef }
  public func validate() throws {
    if case .unavailable(let reason, _) = self, reason.isEmpty { throw DrawingExchangeError.malformed("Unavailable link needs a reason") }
  }
  public init(from decoder: Decoder) throws {
    try exchangeClosedKeys(decoder, allowed: ["state", "ref", "reason", "knownRef"])
    let c = try decoder.container(keyedBy: CodingKeys.self)
    switch try c.decode(String.self, forKey: .state) {
    case "none":
      guard !c.contains(.ref), !c.contains(.reason), !c.contains(.knownRef) else { throw DrawingExchangeError.malformed("Contradictory none link") }
      self = .none
    case "present":
      guard !c.contains(.reason), !c.contains(.knownRef) else { throw DrawingExchangeError.malformed("Contradictory present link") }
      self = .present(try c.decode(Reference.self, forKey: .ref))
    case "unavailable":
      guard !c.contains(.ref), try (!c.contains(.knownRef) || !c.decodeNil(forKey: .knownRef)) else { throw DrawingExchangeError.malformed("Contradictory unavailable link") }
      let reason = try c.decode(String.self, forKey: .reason)
      guard !reason.isEmpty else { throw DrawingExchangeError.malformed("Unavailable link needs a reason") }
      self = .unavailable(reason: reason, knownRef: try c.decodeIfPresent(Reference.self, forKey: .knownRef))
    default: throw DrawingExchangeError.malformed("Unknown source declaration")
    }
  }
  public func encode(to encoder: Encoder) throws {
    var c = encoder.container(keyedBy: CodingKeys.self)
    switch self {
    case .none: try c.encode("none", forKey: .state)
    case .present(let ref): try c.encode("present", forKey: .state); try c.encode(ref, forKey: .ref)
    case .unavailable(let reason, let knownRef):
      guard !reason.isEmpty else { throw DrawingExchangeError.malformed("Unavailable link needs a reason") }
      try c.encode("unavailable", forKey: .state); try c.encode(reason, forKey: .reason)
      try c.encodeIfPresent(knownRef, forKey: .knownRef)
    }
  }
}
public struct JobRef: Hashable, Codable, Sendable {
  public let engine: UUID
  public let job: UUID
  public init(engine: UUID, job: UUID) { self.engine = engine; self.job = job }
  enum CodingKeys: String, CodingKey { case engine, job }
  public init(from decoder: Decoder) throws {
    try exchangeClosedKeys(decoder, allowed: ["engine", "job"])
    let c = try decoder.container(keyedBy: CodingKeys.self)
    engine = try exchangeUUID(c.decode(String.self, forKey: .engine)); job = try exchangeUUID(c.decode(String.self, forKey: .job))
  }
  public func encode(to encoder: Encoder) throws {
    var c = encoder.container(keyedBy: CodingKeys.self)
    try c.encode(engine.uuidString.lowercased(), forKey: .engine); try c.encode(job.uuidString.lowercased(), forKey: .job)
  }
}
public struct SnapshotRef: Hashable, Codable, Sendable {
  public let archive: UUID
  public let run: UUID
  public let sequence: UInt64
  public let digest: ExchangeDigest
  public init(archive: UUID, run: UUID, sequence: UInt64, digest: ExchangeDigest) throws {
    guard sequence > 0, sequence <= 9_007_199_254_740_991 else { throw DrawingExchangeError.malformed("Invalid snapshot sequence") }
    self.archive = archive; self.run = run; self.sequence = sequence; self.digest = digest
  }
  enum CodingKeys: String, CodingKey { case archive, run, sequence, digest }
  public init(from decoder: Decoder) throws {
    try exchangeClosedKeys(decoder, allowed: ["archive", "run", "sequence", "digest"])
    let c = try decoder.container(keyedBy: CodingKeys.self)
    try self.init(archive: exchangeUUID(c.decode(String.self, forKey: .archive)), run: exchangeUUID(c.decode(String.self, forKey: .run)), sequence: c.decode(UInt64.self, forKey: .sequence), digest: c.decode(ExchangeDigest.self, forKey: .digest))
  }
  public func encode(to encoder: Encoder) throws {
    var c = encoder.container(keyedBy: CodingKeys.self)
    try c.encode(archive.uuidString.lowercased(), forKey: .archive); try c.encode(run.uuidString.lowercased(), forKey: .run)
    try c.encode(sequence, forKey: .sequence); try c.encode(digest, forKey: .digest)
  }
}

/// Immutable submission receipt pin; a JobRef alone cannot identify portable result facts.
public struct JobReceiptRef: Hashable, Codable, Sendable {
  public let engine: UUID
  public let job: UUID
  public let receiptDigest: ExchangeDigest
  public var handle: JobRef { .init(engine: engine, job: job) }
  public init(handle: JobRef, receiptDigest: ExchangeDigest) {
    engine = handle.engine; job = handle.job; self.receiptDigest = receiptDigest
  }
  enum CodingKeys: String, CodingKey { case engine, job, receiptDigest }
  public init(from decoder: Decoder) throws {
    try exchangeClosedKeys(decoder, allowed: ["engine", "job", "receiptDigest"])
    let c = try decoder.container(keyedBy: CodingKeys.self)
    let handle = try JobRef(engine: exchangeUUID(c.decode(String.self, forKey: .engine)), job: exchangeUUID(c.decode(String.self, forKey: .job)))
    self.init(handle: handle, receiptDigest: try c.decode(ExchangeDigest.self, forKey: .receiptDigest))
  }
  public func encode(to encoder: Encoder) throws {
    var c = encoder.container(keyedBy: CodingKeys.self)
    try c.encode(engine.uuidString.lowercased(), forKey: .engine); try c.encode(job.uuidString.lowercased(), forKey: .job)
    try c.encode(receiptDigest, forKey: .receiptDigest)
  }
}
public struct SnapshotKey: Hashable, Sendable {
  public let archive: UUID
  public let run: UUID
  public let sequence: UInt64
  public init(_ reference: SnapshotRef) { archive = reference.archive; run = reference.run; sequence = reference.sequence }
}

private struct ExchangeAnyKey: CodingKey {
  let stringValue: String
  var intValue: Int? { nil }
  init?(stringValue: String) { self.stringValue = stringValue }
  init?(intValue: Int) { nil }
}
func exchangeClosedKeys(_ decoder: Decoder, allowed: Set<String>) throws {
  let keys = try decoder.container(keyedBy: ExchangeAnyKey.self).allKeys.map(\.stringValue)
  guard Set(keys).isSubset(of: allowed) else { throw DrawingExchangeError.malformed("Unknown field in closed wire declaration") }
}
