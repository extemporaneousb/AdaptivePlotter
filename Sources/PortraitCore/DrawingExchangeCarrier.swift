import Foundation
import CryptoKit
import Darwin

public struct ExchangeCarrierFailure: Error {
  public let stagingURL: URL
  public let underlying: Error
}
public struct StagedExchangePackage: Sendable {
  public let files: VerifiedExchangeFiles
  public let indexJSON: Data
  public let stagingURL: URL
  public var statistics: ExchangeCarrierStatistics { files.statistics }
}
public enum DrawingExchangeCarrier {
  static let bagit = Data("BagIt-Version: 1.0\nTag-File-Character-Encoding: UTF-8\n".utf8)
  public static func stageDirectory(_ source: URL, stagingParent: URL, limits: ExchangeCarrierLimits = .init(),
    cancelled: @Sendable () -> Bool = { false }) throws -> StagedExchangePackage {
    try stage(stagingParent: stagingParent, limits: limits, cancelled: cancelled) { stage, counters in
      let sourcePath = source.resolvingSymlinksInPath().standardizedFileURL.path
      let destinationPath = stage.resolvingSymlinksInPath().standardizedFileURL.path
      guard !destinationPath.hasPrefix(sourcePath + "/") else { throw DrawingExchangeError.malformed("Staging inside source") }
      let root = Darwin.open(source.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
      guard root >= 0 else { throw DrawingExchangeError.malformed("Source directory") }; defer { Darwin.close(root) }
      var paths = Set<String>(), folded = Set<String>(), total: UInt64 = 0
      func visit(_ fd: Int32, prefix: String) throws {
        guard let dir = fdopendir(dup(fd)) else { throw DrawingExchangeError.malformed("Directory enumeration") }; defer { closedir(dir) }
        while let item = readdir(dir) {
          let name = withUnsafePointer(to: &item.pointee.d_name) { p in p.withMemoryRebound(to: CChar.self, capacity: Int(MAXNAMLEN) + 1) { String(cString: $0) } }
          if name == "." || name == ".." { continue }
          if cancelled() { throw CancellationError() }
          let path = prefix + name; try safePath(path)
          guard paths.insert(path).inserted, folded.insert(fold(path)).inserted, paths.count <= limits.maximumEntries else { throw DrawingExchangeError.limit("Entry count/collision") }
          var info = stat()
          guard fstatat(fd, name, &info, AT_SYMLINK_NOFOLLOW) == 0 else { throw DrawingExchangeError.malformed("Entry stat") }
          let kind = info.st_mode & S_IFMT
          guard kind == S_IFREG || kind == S_IFDIR else { throw DrawingExchangeError.malformed("Link/special entry") }
          let child = openat(fd, name, O_RDONLY | O_NOFOLLOW | O_CLOEXEC | (kind == S_IFDIR ? O_DIRECTORY : 0))
          guard child >= 0 else { throw DrawingExchangeError.malformed("Entry open") }; defer { Darwin.close(child) }
          var opened = stat()
          guard fstat(child, &opened) == 0, opened.st_ino == info.st_ino, opened.st_dev == info.st_dev, opened.st_mode & S_IFMT == kind else { throw DrawingExchangeError.malformed("Entry changed") }
          let target = stage.appendingPathComponent(path)
          if kind == S_IFDIR {
            try FileManager.default.createDirectory(at: target, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
            try visit(child, prefix: path + "/")
          } else {
            guard opened.st_nlink == 1, opened.st_size >= 0 else { throw DrawingExchangeError.malformed("Hard link/size") }
            let size = UInt64(opened.st_size); try addSize(size, total: &total, limits: limits)
            let output = Darwin.open(target.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o400)
            guard output >= 0 else { throw DrawingExchangeError.malformed("Stage output") }; defer { Darwin.close(output) }
            var buffer = [UInt8](repeating: 0, count: limits.bufferBytes), copied: UInt64 = 0
            while true {
              if cancelled() { throw CancellationError() }
              let count = Darwin.read(child, &buffer, buffer.count)
              guard count >= 0 else { throw DrawingExchangeError.malformed("Source read") }; if count == 0 { break }
              guard UInt64(count) <= size - min(size, copied) else { throw DrawingExchangeError.malformed("Source grew") }
              try writeAll(output, buffer, count: count); copied += UInt64(count)
              counters.update { $0.sourceBytesRead += UInt64(count); $0.stagedBytesWritten += UInt64(count) }
            }
            var after = stat()
            guard copied == size, fstat(child, &after) == 0, after.st_size == opened.st_size,
              after.st_mtimespec.tv_sec == opened.st_mtimespec.tv_sec, after.st_mtimespec.tv_nsec == opened.st_mtimespec.tv_nsec,
              after.st_ctimespec.tv_sec == opened.st_ctimespec.tv_sec, after.st_ctimespec.tv_nsec == opened.st_ctimespec.tv_nsec else { throw DrawingExchangeError.malformed("Source changed during copy") }
          }
        }
      }
      try visit(root, prefix: "")
    }
  }
  public static func stageZIP(_ source: URL, stagingParent: URL, limits: ExchangeCarrierLimits = .init(),
    cancelled: @Sendable () -> Bool = { false }) throws -> StagedExchangePackage {
    try stage(stagingParent: stagingParent, limits: limits, cancelled: cancelled) { stage, counters in
      let preserved = stage.deletingLastPathComponent().appendingPathComponent("incoming.zip")
      let input = try ExchangePinnedFile(source)
      var inputInfo = stat()
      guard fstat(input.fd, &inputInfo) == 0, inputInfo.st_size >= 0, UInt64(inputInfo.st_size) <= limits.maximumExpandedBytes else { throw DrawingExchangeError.limit("Incoming transport bytes") }
      let output = Darwin.open(preserved.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o400)
      guard output >= 0 else { throw DrawingExchangeError.malformed("Incoming ZIP copy") }; defer { Darwin.close(output) }
      var buffer = [UInt8](repeating: 0, count: limits.bufferBytes)
      var copied: UInt64 = 0
      while true {
        if cancelled() { throw CancellationError() }
        let n = Darwin.read(input.fd, &buffer, buffer.count)
        guard n >= 0 else { throw DrawingExchangeError.malformed("Incoming ZIP read") }; if n == 0 { break }
        guard UInt64(n) <= limits.maximumExpandedBytes - min(copied, limits.maximumExpandedBytes) else { throw DrawingExchangeError.limit("Incoming transport bytes") }
        try writeAll(output, buffer, count: n); copied += UInt64(n)
        counters.update { $0.sourceBytesRead += UInt64(n); $0.stagedBytesWritten += UInt64(n) }
      }
      try input.check()
      try ExchangeZIP.extract(preserved, to: stage, limits: limits, counters: counters, cancelled: cancelled)
    }
  }
  static func stage(stagingParent: URL, limits: ExchangeCarrierLimits, cancelled: @Sendable () -> Bool,
    copy: (URL, ExchangeCarrierCounters) throws -> Void) throws -> StagedExchangePackage {
    try limits.validate()
    let inspection = stagingParent.appendingPathComponent("exchange-incoming-" + UUID().uuidString.lowercased(), isDirectory: true)
    try FileManager.default.createDirectory(at: inspection, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
    let stage = inspection.appendingPathComponent("payload", isDirectory: true)
    try FileManager.default.createDirectory(at: stage, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
    do {
      let counters = ExchangeCarrierCounters(); try copy(stage, counters)
      let entries = try verify(stage, limits: limits, counters: counters, cancelled: cancelled)
      let files = try VerifiedExchangeFiles(entries: entries, stagingURL: stage, limits: limits, counters: counters)
      let index = try files.record(at: "data/exchange.json", maximumBytes: limits.maximumRecordBytes)
      _ = try ExchangeJSON.validate(index, maximumBytes: limits.maximumRecordBytes)
      return .init(files: files, indexJSON: index, stagingURL: stage)
    } catch { throw ExchangeCarrierFailure(stagingURL: inspection, underlying: error) }
  }
  static func verify(_ stage: URL, limits: ExchangeCarrierLimits, counters: ExchangeCarrierCounters, cancelled: @Sendable () -> Bool) throws -> [String: VerifiedExchangeFile] {
    let root = try ExchangePinnedDirectory(stage)
    var entries: [String: VerifiedExchangeFile] = [:], seen = Set<String>(), folded = Set<String>(), total: UInt64 = 0
    var collected: [String: stat] = [:]
    func collect(_ descriptor: Int32, prefix: String) throws {
      guard let directory = fdopendir(dup(descriptor)) else { throw DrawingExchangeError.malformed("Stage enumeration") }; defer { closedir(directory) }
      while let item = readdir(directory) {
        if cancelled() { throw CancellationError() }
        let name = withUnsafePointer(to: &item.pointee.d_name) { p in p.withMemoryRebound(to: CChar.self, capacity: Int(MAXNAMLEN) + 1) { String(cString: $0) } }
        if name == "." || name == ".." { continue }
        let path = prefix + name; try safePath(path)
        guard seen.insert(path).inserted, folded.insert(fold(path)).inserted, seen.count <= limits.maximumEntries else { throw DrawingExchangeError.limit("Staged count/collision") }
        var info = stat()
        guard fstatat(descriptor, name, &info, AT_SYMLINK_NOFOLLOW) == 0 else { throw DrawingExchangeError.malformed("Staged stat") }
        switch info.st_mode & S_IFMT {
        case S_IFDIR:
          let child = openat(descriptor, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
          guard child >= 0 else { throw DrawingExchangeError.malformed("Staged directory link/change") }; defer { Darwin.close(child) }
          var opened = stat()
          guard fstat(child, &opened) == 0, opened.st_dev == info.st_dev, opened.st_ino == info.st_ino else { throw DrawingExchangeError.malformed("Staged directory changed") }
          try collect(child, prefix: path + "/")
        case S_IFREG:
          guard info.st_nlink == 1, info.st_size >= 0 else { throw DrawingExchangeError.malformed("Staged hard link/size") }
          try addSize(UInt64(info.st_size), total: &total, limits: limits); collected[path] = info
        default: throw DrawingExchangeError.malformed("Staged link/special entry")
        }
      }
    }
    try collect(root.fd, prefix: "")
    for (path, initial) in collected {
      if cancelled() { throw CancellationError() }
      let fingerprint = ExchangeFileFingerprint(root: root, path: path, verifiedStat: initial)
      let pinned = try fingerprint.open()
      var hasher = SHA256(), size: UInt64 = 0, buffer = [UInt8](repeating: 0, count: limits.bufferBytes)
      while true {
        if cancelled() { throw CancellationError() }
        let n = Darwin.read(pinned.fd, &buffer, buffer.count)
        guard n >= 0 else { throw DrawingExchangeError.malformed("Verification read") }; if n == 0 { break }
        guard UInt64(n) <= UInt64(initial.st_size) - min(size, UInt64(initial.st_size)) else { throw DrawingExchangeError.limit("Staged file grew") }
        hasher.update(data: Data(buffer[0..<n])); size += UInt64(n)
        counters.update { $0.verificationBytesRead += UInt64(n); $0.hashedBytes += UInt64(n) }
      }
      try pinned.check()
      let digest = try ExchangeDigest(hasher.finalize().map { String(format: "%02x", $0) }.joined())
      entries[path] = .init(path: path, digest: digest, byteLength: size, fingerprint: fingerprint)
    }
    func bytes(_ path: String) throws -> Data {
      guard let entry = entries[path], entry.byteLength <= UInt64(limits.maximumRecordBytes) else { throw DrawingExchangeError.limit("Tag size/missing") }
      let data = try entry.fingerprint.open().read(maximum: limits.maximumRecordBytes)
      counters.materialized(path: path, bytes: data.count); return data
    }
    guard try bytes("bagit.txt") == bagit else { throw DrawingExchangeError.malformed("Exact BagIt header") }
    let payload = try manifest(bytes("manifest-sha256.txt")), tags = try manifest(bytes("tagmanifest-sha256.txt"))
    guard payload.keys.allSatisfy({ $0.hasPrefix("data/") }), !payload.isEmpty,
      !tags.keys.contains("tagmanifest-sha256.txt"), tags["bagit.txt"] != nil, tags["manifest-sha256.txt"] != nil,
      tags.keys.allSatisfy({ !$0.hasPrefix("data/") && $0 != "fetch.txt" && !$0.hasPrefix("manifest-") || $0 == "manifest-sha256.txt" }),
      entries["fetch.txt"] == nil,
      Set(entries.keys) == Set(payload.keys).union(tags.keys).union(["tagmanifest-sha256.txt"]) else { throw DrawingExchangeError.malformed("Exact manifest closure") }
    for (path, digest) in payload.merging(tags, uniquingKeysWith: { a, _ in a }) {
      guard entries[path]?.digest == digest else { throw DrawingExchangeError.digestMismatch(path) }
    }
    return entries
  }
  static func manifest(_ data: Data) throws -> [String: ExchangeDigest] {
    guard let text = String(data: data, encoding: .utf8), !text.hasPrefix("\u{feff}"), text.hasSuffix("\n") else { throw DrawingExchangeError.malformed("Manifest UTF-8/LF") }
    var result: [String: ExchangeDigest] = [:], folded = Set<String>()
    for line in text.dropLast().split(separator: "\n", omittingEmptySubsequences: false) {
      guard line.utf8.count > 66 else { throw DrawingExchangeError.malformed("Manifest line") }
      let digest = try ExchangeDigest(String(line.prefix(64)))
      guard line.dropFirst(64).hasPrefix("  ") else { throw DrawingExchangeError.malformed("Manifest delimiter") }
      let path = String(line.dropFirst(66)); try safePath(path)
      guard result.updateValue(digest, forKey: path) == nil, folded.insert(fold(path)).inserted else { throw DrawingExchangeError.malformed("Manifest duplicate") }
    }
    return result
  }
  static func safePath(_ path: String) throws {
    guard !path.isEmpty, path.utf8.count <= 4096, !path.hasPrefix("/"), !path.contains("\\"), !path.contains(":"),
      !path.unicodeScalars.contains(where: { $0.value < 32 || $0.value == 127 }),
      path.split(separator: "/", omittingEmptySubsequences: false).allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." && $0.utf8.count <= 255 }) else { throw DrawingExchangeError.malformed("Unsafe relative path") }
  }
  static func fold(_ path: String) -> String { path.precomposedStringWithCanonicalMapping.folding(options: [.caseInsensitive], locale: Locale(identifier: "en_US_POSIX")) }
  static func addSize(_ size: UInt64, total: inout UInt64, limits: ExchangeCarrierLimits) throws {
    guard size <= limits.maximumEntryBytes, size <= limits.maximumExpandedBytes - min(total, limits.maximumExpandedBytes) else { throw DrawingExchangeError.limit("Expanded bytes") }; total += size
  }
  static func writeAll(_ fd: Int32, _ bytes: [UInt8], count: Int) throws {
    try bytes.withUnsafeBytes { raw in
      var n = 0
      while n < count { let written = Darwin.write(fd, raw.baseAddress!.advanced(by: n), count - n); guard written > 0 else { throw DrawingExchangeError.malformed("Stage write") }; n += written }
    }
  }
}

extension DrawingExchangeCarrier {
  /// Preservation-only copy of verified bytes. Typed admission is a separate owner.
  /// Destination must not exist; partial output remains inspectable on cancellation/failure.
  public static func preserveDirectory(_ files: VerifiedExchangeFiles, to destination: URL,
    cancelled: @Sendable () -> Bool = { false }) throws {
    try preservationDestination(destination, files: files)
    try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
    for path in files.entries.keys.sorted() {
      if cancelled() { throw CancellationError() }
      let pinned = try files.pinned(at: path), target = destination.appendingPathComponent(path)
      try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
      let output = Darwin.open(target.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o400)
      guard output >= 0 else { throw DrawingExchangeError.malformed("Preservation output") }; defer { Darwin.close(output) }
      var buffer = [UInt8](repeating: 0, count: files.limits.bufferBytes)
      while true {
        if cancelled() { throw CancellationError() }
        let n = Darwin.read(pinned.fd, &buffer, buffer.count)
        guard n >= 0 else { throw DrawingExchangeError.malformed("Preservation read") }; if n == 0 { break }
        try writeAll(output, buffer, count: n)
        files.counters.update { $0.reexportBytesRead += UInt64(n); $0.reexportBytesWritten += UInt64(n) }
      }
      try pinned.check()
    }
  }
  public static func preserveZIP(_ files: VerifiedExchangeFiles, to destination: URL,
    cancelled: @Sendable () -> Bool = { false }) throws {
    try preservationDestination(destination, files: files)
    try ExchangeZIP.write(files, to: destination, cancelled: cancelled)
  }
  static func preservationDestination(_ destination: URL, files: VerifiedExchangeFiles) throws {
    let source = fold(files.stagingURL.resolvingSymlinksInPath().standardizedFileURL.path)
    let target = fold(destination.resolvingSymlinksInPath().standardizedFileURL.path)
    guard target != source, !target.hasPrefix(source + "/") else { throw DrawingExchangeError.malformed("Preservation destination is inside verified carrier") }
  }
}
