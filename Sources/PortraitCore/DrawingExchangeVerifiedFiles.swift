import Foundation
import CryptoKit
import Darwin

public struct ExchangeCarrierLimits: Sendable {
  public var maximumEntries = 100_000
  public var maximumEntryBytes: UInt64 = 32 * 1024 * 1024 * 1024
  public var maximumExpandedBytes: UInt64 = 128 * 1024 * 1024 * 1024
  public var maximumMaterializedBytes: UInt64 = 512 * 1024 * 1024
  public var maximumRecordBytes = ExchangeJSON.maximumRecordBytes
  public var maximumCompressionRatio: UInt64 = 10_000
  public var maximumImagePixels: UInt64 = 100_000_000
  public var maximumEncodedImageBytes: UInt64 = 64 * 1024 * 1024
  public var maximumDecodedImageBytes: UInt64 = 400_000_000
  public var bufferBytes = 1024 * 1024
  public init() {}
  func validate() throws {
    guard maximumEntries > 0, maximumRecordBytes > 0, bufferBytes > 0, bufferBytes <= 16 * 1024 * 1024,
      maximumEntryBytes > 0, maximumExpandedBytes > 0, maximumCompressionRatio > 0, maximumMaterializedBytes > 0,
      maximumEncodedImageBytes <= UInt64(Int.max), maximumDecodedImageBytes <= UInt64(Int.max), maximumImagePixels > 0 else {
      throw DrawingExchangeError.limit("Carrier policy")
    }
  }
}
public struct ExchangeCarrierStatistics: Sendable, Codable {
  public var sourceBytesRead: UInt64 = 0
  public var stagedBytesWritten: UInt64 = 0
  public var verificationBytesRead: UInt64 = 0
  public var hashedBytes: UInt64 = 0
  public var crcBytes: UInt64 = 0
  public var materializedBytesRead: UInt64 = 0
  public var reexportBytesRead: UInt64 = 0
  public var reexportBytesWritten: UInt64 = 0
  public var semanticBytesHashed: UInt64 = 0
  public var programJSONDecodeCalls: UInt64 = 0
  public var producerValidatorEntries: UInt64 = 0
  public var materializationReadPassesByPath: [String: UInt64] = [:]
  public var materializedBytesByPath: [String: UInt64] = [:]
  public var imageHeaderReads: UInt64 = 0
  public var imageDecodeCount: UInt64 = 0
}
final class ExchangeCarrierCounters: @unchecked Sendable {
  private let lock = NSLock()
  private var value = ExchangeCarrierStatistics()
  func update(_ body: (inout ExchangeCarrierStatistics) -> Void) { lock.lock(); defer { lock.unlock() }; body(&value) }
  func materialized(path: String, bytes: Int) {
    update {
      $0.materializedBytesRead += UInt64(bytes)
      $0.materializationReadPassesByPath[path, default: 0] += 1
      $0.materializedBytesByPath[path, default: 0] += UInt64(bytes)
    }
  }
  var snapshot: ExchangeCarrierStatistics { lock.lock(); defer { lock.unlock() }; return value }
}
public struct VerifiedExchangeFile: Sendable {
  public let path: String
  public let digest: ExchangeDigest
  public let byteLength: UInt64
  let fingerprint: ExchangeFileFingerprint
}
/// Constructed only after descriptor-safe staging and manifest verification. Not a wire DTO.
public enum ExchangeAssetSupport: Sendable, Equatable {
  case supported
  case unsupported(reason: String)
  public var isSupported: Bool { if case .supported = self { return true }; return false }
}
public final class VerifiedExchangeFiles: @unchecked Sendable {
  public let entries: [String: VerifiedExchangeFile]
  public let stagingURL: URL
  let limits: ExchangeCarrierLimits
  let counters: ExchangeCarrierCounters
  private let handles: [String: ExchangeFileFingerprint]
  private let byDigest: [ExchangeDigest: String]
  private let materializationBudget: ExchangeReadBudget?
  init(entries: [String: VerifiedExchangeFile], stagingURL: URL, limits: ExchangeCarrierLimits,
    counters: ExchangeCarrierCounters) throws {
    self.entries = entries; self.stagingURL = stagingURL; self.limits = limits; self.counters = counters; materializationBudget = nil
    var handles: [String: ExchangeFileFingerprint] = [:], byDigest: [ExchangeDigest: String] = [:]
    for (path, entry) in entries {
      _ = try entry.fingerprint.open()
      handles[path] = entry.fingerprint
      byDigest[entry.digest] = path
    }
    self.handles = handles; self.byDigest = byDigest
  }
  private init(sharing files: VerifiedExchangeFiles, budget: ExchangeReadBudget) {
    entries = files.entries; stagingURL = files.stagingURL; limits = files.limits; counters = files.counters
    handles = files.handles; byDigest = files.byDigest; materializationBudget = budget
  }
  func scoped(maximumMaterializedBytes: UInt64) -> VerifiedExchangeFiles {
    .init(sharing: self, budget: .init(maximum: maximumMaterializedBytes))
  }
  public var statistics: ExchangeCarrierStatistics { counters.snapshot }
  public func contains(path: String) -> Bool { entries[path] != nil }
  public func byteLength(_ digest: ExchangeDigest) throws -> UInt64 {
    guard let path = byDigest[digest], let file = entries[path] else { throw DrawingExchangeError.missingAsset(digest.description) }
    return file.byteLength
  }
  public func record(_ digest: ExchangeDigest, maximumBytes: Int = ExchangeJSON.maximumRecordBytes) throws -> Data {
    guard let path = byDigest[digest] else { throw DrawingExchangeError.missingAsset(digest.description) }
    return try record(at: path, maximumBytes: maximumBytes)
  }
  public func record(at path: String, maximumBytes: Int = ExchangeJSON.maximumRecordBytes) throws -> Data {
    guard let entry = entries[path], let handle = handles[path] else { throw DrawingExchangeError.missingAsset(path) }
    guard maximumBytes >= 0, entry.byteLength <= UInt64(maximumBytes) else { throw DrawingExchangeError.limit("Materialization: " + path) }
    try materializationBudget?.reserve(entry.byteLength)
    let pinned = try handle.open()
    let bytes = try pinned.read(maximum: maximumBytes)
    counters.materialized(path: path, bytes: bytes.count)
    return bytes
  }
  func pinned(at path: String) throws -> ExchangePinnedFile {
    guard let handle = handles[path] else { throw DrawingExchangeError.missingAsset(path) }; return try handle.open()
  }
  public func validateAsset(_ descriptor: ExchangeAssetDescriptor) throws -> ExchangeAssetSupport {
    let asset = descriptor.asset
    guard try byteLength(asset.object) == asset.byteLength else { throw DrawingExchangeError.malformed("Asset length") }
    if let d = descriptor.dimensions {
      guard d.width > 0, d.height > 0, UInt64(d.width) <= limits.maximumImagePixels / UInt64(d.height) else { throw DrawingExchangeError.limit("Image dimensions") }
    }
    if asset.encoding.hasPrefix("raw-") {
      guard let layout = descriptor.pixelLayout, UInt64(try layout.requiredBytes()) == asset.byteLength else { throw DrawingExchangeError.malformed("Raw layout/length") }
      if let d = descriptor.dimensions, d.width != layout.width || d.height != layout.height { throw DrawingExchangeError.malformed("Raw dimensions") }
      let known: [String: (String, [String])] = ["raw-gray8":("gray", ["gray"]), "raw-rgb8":("rgb", ["red", "green", "blue"]),
        "raw-rgba8":("rgba", ["red", "green", "blue", "alpha"]), "raw-bgra8":("bgra", ["blue", "green", "red", "alpha"])]
      if let (format, channels) = known[asset.encoding], layout.pixelFormat != format || layout.channelOrder != channels || layout.componentType != "uint8" || layout.bitDepth != 8 { throw DrawingExchangeError.malformed("Raw encoding/layout") }
      return known[asset.encoding] != nil && layout.supportedSemantics ? .supported : .unsupported(reason: "Unsupported raw encoding/layout")
    }
    if asset.encoding.hasPrefix("array-") {
      guard let layout = descriptor.arrayLayout else { throw DrawingExchangeError.malformed("Array layout") }
      guard let length = try layout.requiredBytes() else { return .unsupported(reason: "Unsupported array dtype") }
      guard UInt64(length) == asset.byteLength else { throw DrawingExchangeError.malformed("Array length") }
      return .supported
    }
    return try ExchangeEncodedImageProof.validate(descriptor, files: self)
  }
}
final class ExchangePinnedFile: @unchecked Sendable {
  let fd: Int32
  private let initial: stat
  convenience init(_ url: URL) throws { try self.init(ownedDescriptor: Darwin.open(url.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)) }
  init(ownedDescriptor: Int32) throws {
    fd = ownedDescriptor
    guard fd >= 0 else { throw DrawingExchangeError.malformed("Cannot pin staged file") }
    var info = stat()
    guard fstat(fd, &info) == 0, info.st_mode & S_IFMT == S_IFREG, info.st_nlink == 1 else { Darwin.close(fd); throw DrawingExchangeError.malformed("Staged regular file") }
    initial = info
  }
  deinit { Darwin.close(fd) }
  func check() throws {
    var s = stat()
    guard fstat(fd, &s) == 0, s.st_dev == initial.st_dev, s.st_ino == initial.st_ino, s.st_size == initial.st_size,
      s.st_mtimespec.tv_sec == initial.st_mtimespec.tv_sec, s.st_mtimespec.tv_nsec == initial.st_mtimespec.tv_nsec,
      s.st_ctimespec.tv_sec == initial.st_ctimespec.tv_sec, s.st_ctimespec.tv_nsec == initial.st_ctimespec.tv_nsec else { throw DrawingExchangeError.digestMismatch("Verified file changed") }
  }
  func read(maximum: Int) throws -> Data {
    try check()
    guard initial.st_size >= 0, initial.st_size <= maximum else { throw DrawingExchangeError.limit("Pinned file size") }
    var result = Data(count: Int(initial.st_size))
    try result.withUnsafeMutableBytes { raw in
      var offset = 0
      while offset < raw.count {
        let n = pread(fd, raw.baseAddress!.advanced(by: offset), raw.count - offset, off_t(offset))
        guard n > 0 else { throw DrawingExchangeError.malformed("Staged read") }; offset += n
      }
    }
    try check(); return result
  }
}

/// A lazy descriptor lease keeps FD usage independent of carrier entry count.
final class ExchangePinnedDirectory: @unchecked Sendable {
  let fd: Int32
  init(_ url: URL) throws {
    fd = Darwin.open(url.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
    guard fd >= 0 else { throw DrawingExchangeError.malformed("Cannot pin staging root") }
  }
  deinit { Darwin.close(fd) }
  func open(_ path: String) throws -> ExchangePinnedFile {
    try DrawingExchangeCarrier.safePath(path)
    let components = path.split(separator: "/").map(String.init)
    var parent = dup(fd)
    guard parent >= 0 else { throw DrawingExchangeError.malformed("Root descriptor") }; defer { Darwin.close(parent) }
    for name in components.dropLast() {
      let next = openat(parent, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
      guard next >= 0 else { throw DrawingExchangeError.malformed("Staged parent link/change") }
      Darwin.close(parent); parent = next
    }
    return try ExchangePinnedFile(ownedDescriptor: openat(parent, components.last!, O_RDONLY | O_NOFOLLOW | O_CLOEXEC))
  }
}
final class ExchangeFileFingerprint: @unchecked Sendable {
  let root: ExchangePinnedDirectory
  let path: String
  let initial: stat
  init(root: ExchangePinnedDirectory, path: String) throws {
    self.root = root; self.path = path
    let pinned = try root.open(path)
    var info = stat(); guard fstat(pinned.fd, &info) == 0 else { throw DrawingExchangeError.malformed("Fingerprint") }; initial = info
  }
  init(root: ExchangePinnedDirectory, path: String, verifiedStat: stat) {
    self.root = root; self.path = path; initial = verifiedStat
  }
  func open() throws -> ExchangePinnedFile {
    let pinned = try root.open(path)
    var s = stat()
    guard fstat(pinned.fd, &s) == 0, s.st_dev == initial.st_dev, s.st_ino == initial.st_ino, s.st_size == initial.st_size,
      s.st_mtimespec.tv_sec == initial.st_mtimespec.tv_sec, s.st_mtimespec.tv_nsec == initial.st_mtimespec.tv_nsec,
      s.st_ctimespec.tv_sec == initial.st_ctimespec.tv_sec, s.st_ctimespec.tv_nsec == initial.st_ctimespec.tv_nsec else { throw DrawingExchangeError.digestMismatch("Verified file changed") }
    return pinned
  }
}

/// Dictionary compatibility retains its exact hash checks; sealed file resolution never
/// constructs a media dictionary and materializes only bounded semantic records.
enum ExchangeObjectResolver {
  case dictionary([ExchangeDigest: Data])
  case files(VerifiedExchangeFiles, budget: ExchangeReadBudget = .init())
  var count: Int { switch self { case .dictionary(let d): return d.count; case .files(let f, _): return f.entries.count } }
  func bytes(_ digest: ExchangeDigest, maximum: Int = ExchangeJSON.maximumRecordBytes) throws -> Data {
    switch self {
    case .dictionary(let d):
      guard let bytes = d[digest] else { throw DrawingExchangeError.missingAsset(digest.description) }
      guard bytes.count <= maximum else { throw DrawingExchangeError.limit("Object bytes") }
      guard ExchangeDigest.hash(bytes) == digest else { throw DrawingExchangeError.digestMismatch(digest.description) }; return bytes
    case .files(let f, let budget):
      try budget.reserve(f.byteLength(digest)); return try f.record(digest, maximumBytes: maximum)
    }
  }
  func validate(_ asset: ExchangeAsset) throws {
    switch self {
    case .dictionary(let d):
      guard let bytes = d[asset.object] else { throw DrawingExchangeError.missingAsset(asset.object.description) }
      try asset.validate(bytes)
    case .files(let f, _):
      guard try f.byteLength(asset.object) == asset.byteLength else { throw DrawingExchangeError.malformed("Asset length") }
    }
  }
}

/// One semantic traversal's work budget; statistics on the reusable file resolver remain cumulative.
final class ExchangeReadBudget: @unchecked Sendable {
  private let lock = NSLock()
  let maximum: UInt64
  var used: UInt64 = 0
  init(maximum: UInt64 = 512 * 1024 * 1024) { self.maximum = maximum }
  func reserve(_ bytes: UInt64) throws {
    lock.lock(); defer { lock.unlock() }
    guard bytes <= maximum - min(used, maximum) else { throw DrawingExchangeError.limit("Admission materialization work") }; used += bytes
  }
}
