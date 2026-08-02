import CryptoKit
import Foundation

public enum CanonicalEncodingError: Error, Equatable, Sendable {
  case nonFiniteDouble
  case valueTooLarge
  case invalidDigestLength(Int)
}

public struct Digest: Hashable, Codable, Sendable, CustomStringConvertible {
  public static let byteCount = 32
  public let bytes: [UInt8]

  public init(bytes: [UInt8]) throws {
    guard bytes.count == Self.byteCount else {
      throw CanonicalEncodingError.invalidDigestLength(bytes.count)
    }
    self.bytes = bytes
  }

  public var description: String {
    bytes.map { String(format: "%02x", $0) }.joined()
  }

  private enum CodingKeys: String, CodingKey { case bytes }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    try self.init(bytes: container.decode([UInt8].self, forKey: .bytes))
  }
}

public protocol CanonicalEncodable {
  func encodeCanonical(to encoder: inout CanonicalEncoder) throws
}

/// A deliberately small, versioned, deterministic binary encoding used only
/// for identities and golden fixtures. Codable remains an interchange format.
public struct CanonicalEncoder: Sendable {
  public static let magic = Data([0x41, 0x50, 0x43, 0x42])  // "APCB"
  public private(set) var data: Data

  public init(schemaVersion: UInt16) {
    data = Self.magic
    appendUInt16(schemaVersion)
  }

  public mutating func appendUInt8(_ value: UInt8) {
    data.append(value)
  }

  public mutating func appendBool(_ value: Bool) {
    appendUInt8(value ? 1 : 0)
  }

  public mutating func appendUInt16(_ value: UInt16) {
    var bigEndian = value.bigEndian
    withUnsafeBytes(of: &bigEndian) { data.append(contentsOf: $0) }
  }

  public mutating func appendUInt32(_ value: UInt32) {
    var bigEndian = value.bigEndian
    withUnsafeBytes(of: &bigEndian) { data.append(contentsOf: $0) }
  }

  public mutating func appendUInt64(_ value: UInt64) {
    var bigEndian = value.bigEndian
    withUnsafeBytes(of: &bigEndian) { data.append(contentsOf: $0) }
  }

  public mutating func appendInt64(_ value: Int64) {
    appendUInt64(UInt64(bitPattern: value))
  }

  public mutating func appendDouble(_ value: Double) throws {
    guard value.isFinite else { throw CanonicalEncodingError.nonFiniteDouble }
    let normalized = value == 0 ? 0.0 : value
    appendUInt64(normalized.bitPattern)
  }

  public mutating func appendUUID(_ value: UUID) {
    var raw = value.uuid
    withUnsafeBytes(of: &raw) { data.append(contentsOf: $0) }
  }

  public mutating func appendString(_ value: String) throws {
    let normalized = value.precomposedStringWithCanonicalMapping
    let bytes = Data(normalized.utf8)
    guard bytes.count <= UInt32.max else { throw CanonicalEncodingError.valueTooLarge }
    appendUInt32(UInt32(bytes.count))
    data.append(bytes)
  }

  public mutating func appendData(_ value: Data) throws {
    appendUInt64(UInt64(value.count))
    data.append(value)
  }

  public mutating func appendCount(_ value: Int) throws {
    guard value >= 0, value <= UInt32.max else {
      throw CanonicalEncodingError.valueTooLarge
    }
    appendUInt32(UInt32(value))
  }

  public mutating func appendDigest(_ digest: Digest) {
    data.append(contentsOf: digest.bytes)
  }
}

public func canonicalBytes<T: CanonicalEncodable>(
  of value: T,
  schemaVersion: UInt16 = 1
) throws -> Data {
  var encoder = CanonicalEncoder(schemaVersion: schemaVersion)
  try value.encodeCanonical(to: &encoder)
  return encoder.data
}

public func canonicalDigest<T: CanonicalEncodable>(
  of value: T,
  schemaVersion: UInt16 = 1
) throws -> Digest {
  let hash = SHA256.hash(data: try canonicalBytes(of: value, schemaVersion: schemaVersion))
  return try Digest(bytes: Array(hash))
}

extension StrongID: CanonicalEncodable {
  public func encodeCanonical(to encoder: inout CanonicalEncoder) throws {
    encoder.appendUUID(rawValue)
  }
}
