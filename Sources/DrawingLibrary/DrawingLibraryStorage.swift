import Foundation
import CryptoKit
import Darwin
import PortraitCore

package enum LibraryExchangeStorageError: Error, Equatable {
  case io(String, Int32), invalidPath(String), invalidInventory, invalidJournal(String)
  case missingObject(String), corruptObject(String), conflict(String), resourceLimit(String)
}
package struct LibraryExchangeStorageEntry: Codable, Equatable, Sendable {
  package let path: String
  package let digest: ExchangeDigest
  package let byteLength: UInt64
  package init(path: String, digest: ExchangeDigest, byteLength: UInt64) {
    self.path = path; self.digest = digest; self.byteLength = byteLength
  }
}
package struct LibraryExchangeStaging: Codable, Equatable, Sendable {
  package let transactionID: UUID
  package let intent: Data
  package let entries: [LibraryExchangeStorageEntry]
  package init(transactionID: UUID, intent: Data, entries: [LibraryExchangeStorageEntry]) {
    self.transactionID = transactionID; self.intent = intent; self.entries = entries
  }
}
package struct LibraryExchangeStorageFault {
  package enum Boundary: String, CaseIterable, Sendable {
    case beforeJournalCreation, afterJournalCreation, beforeBagCopy, duringBagCopy, afterBagCopy
    case beforeStagingPublication, afterStagingPublication, duringCleanup
    case beforeBlobCopy, afterBlobCopy, beforeBlobFileSync, afterBlobFileSync
    case beforeBlobInstall, afterBlobInstall, beforeBlobDirectorySync, afterBlobDirectorySync
    case beforeJournalTransition, afterJournalTransition, beforeCleanup, afterCleanup
    case beforeBackupPublish, afterBackupPublish
  }
  package let boundary: Boundary
  package let transactionID: UUID?
  package let path: String
}

/// Filesystem half of publication. The caller owns SQL commit/reconciliation decisions.
/// No method opens a catalog or infers metadata from the carrier's records.
package final class LibraryExchangeStorage {
  let rootFD: Int32
  let lease: DrawingLibraryWriterLease
  let fault: (LibraryExchangeStorageFault) throws -> Void
  static let maximumMetadataBytes = 16 * 1024 * 1024
  // Library SQL publication is a separate bounded gate from Core carrier admission.
  package static let maximumPublicationIntentBytes = 32 * 1024 * 1024
  package static let maximumJournalBytes = 128 * 1024 * 1024
  private struct Journal: Codable {
    let version: Int
    let state: String
    let stage: LibraryExchangeStaging
  }
  package init(root: URL, lease: DrawingLibraryWriterLease,
    fault: @escaping (LibraryExchangeStorageFault) throws -> Void = { _ in }) throws {
    try lease.assertMatches(root: root)
    self.lease = lease; self.fault = fault
    rootFD = Darwin.open(lease.canonicalRootURL.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
    guard rootFD >= 0 else { throw LibraryExchangeStorageError.io("open library", errno) }
    do {
      try lease.assertMatches(root: currentURL(rootFD))
      for path in ["objects/sha256", "exchange-staging", "exchange-conflicts", "metadata-backups", "metadata-restores"] {
        let fd = try directory(path, create: true); Darwin.close(fd)
      }
    } catch { Darwin.close(rootFD); throw error }
  }
  deinit { Darwin.close(rootFD) }

  package func stage(files: VerifiedExchangeFiles, transactionID: UUID, intent: Data) throws -> LibraryExchangeStaging {
    guard intent.count <= Self.maximumPublicationIntentBytes else { throw LibraryExchangeStorageError.resourceLimit("publication intent exceeds 32MiB") }
    let entries = files.entries.values.map { LibraryExchangeStorageEntry(path: $0.path, digest: $0.digest, byteLength: $0.byteLength) }.sorted { $0.path < $1.path }
    try Self.validateInventory(entries)
    let stage = LibraryExchangeStaging(transactionID: transactionID, intent: intent, entries: entries)
    let publishedName = transactionID.uuidString.lowercased()
    let preparingName = ".preparing-" + publishedName + "-" + UUID().uuidString.lowercased()
    let path = "exchange-staging/" + preparingName
    let parent = try directory("exchange-staging"); defer { Darwin.close(parent) }
    guard mkdirat(parent, preparingName, 0o700) == 0 else { throw LibraryExchangeStorageError.io("create staging", errno) }
    try sync(parent, "staging parent")
    let fd = try directory(path); defer { Darwin.close(fd) }
    // Carrier preserves exact verified bytes, including index, tags and unsupported records.
    try hit(.beforeBagCopy, transactionID, path + "/bag")
    let progress = CopyProgress { try self.hit(.duringBagCopy, transactionID, path + "/bag") }
    do { try DrawingExchangeCarrier.preserveDirectory(files, to: currentURL(fd).appendingPathComponent("bag"), cancelled: { progress.cancelled() }) }
    catch { throw progress.failure ?? error }
    try hit(.afterBagCopy, transactionID, path + "/bag")
    let bag = try directory(path + "/bag"); defer { Darwin.close(bag) }
    try verifyBag(bag, entries: entries, syncFiles: true)
    try hit(.beforeJournalCreation, transactionID, path)
    try writeEnvelope(Journal(version: 1, state: "prepared", stage: stage), directory: fd, name: "journal.json", maximumBytes: Self.maximumJournalBytes)
    try hit(.afterJournalCreation, transactionID, path)
    try hit(.beforeStagingPublication, transactionID, path)
    guard renameatx_np(parent, preparingName, parent, publishedName, UInt32(RENAME_EXCL)) == 0 else { throw LibraryExchangeStorageError.io(publishedName, errno) }
    try sync(parent, publishedName)
    try hit(.afterStagingPublication, transactionID, stagingPath(transactionID))
    return stage
  }

  package func pendingTransactions() throws -> [LibraryExchangeStaging] {
    let fd = try directory("exchange-staging"); defer { Darwin.close(fd) }
    return try names(fd).sorted().filter { !Self.isPrivateStageName($0) }.map { name in
      guard let id = UUID(uuidString: name), name == id.uuidString.lowercased() else { throw LibraryExchangeStorageError.invalidJournal(name) }
      return try journal(id).stage
    }
  }

  package func installObjects(_ stage: LibraryExchangeStaging) throws {
    let durable = try journal(stage.transactionID)
    guard durable.stage == stage else { throw LibraryExchangeStorageError.invalidJournal("stage differs from durable intent") }
    let fd = try directory(stagingPath(stage.transactionID)); defer { Darwin.close(fd) }
    let bag = try directory(stagingPath(stage.transactionID) + "/bag"); defer { Darwin.close(bag) }
    try verifyBag(bag, entries: stage.entries, syncFiles: false)
    let objects = try directory("objects/sha256"); defer { Darwin.close(objects) }
    var installed = Set<ExchangeDigest>()
    for entry in stage.entries where installed.insert(entry.digest).inserted {
      let name = entry.digest.description
      var info = stat()
      if fstatat(objects, name, &info, AT_SYMLINK_NOFOLLOW) == 0 {
        try verifyFile(directory: objects, path: name, digest: entry.digest, size: entry.byteLength)
        continue
      }
      guard errno == ENOENT else { throw LibraryExchangeStorageError.io(name, errno) }
      let input = try openFile(directory: bag, path: entry.path); defer { Darwin.close(input) }
      let temporary = "." + stage.transactionID.uuidString.lowercased() + "-" + UUID().uuidString.lowercased()
      let output = openat(objects, temporary, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o400)
      guard output >= 0 else { throw LibraryExchangeStorageError.io(temporary, errno) }; defer { Darwin.close(output) }
      try hit(.beforeBlobCopy, stage.transactionID, name)
      try stream(input: input, output: output, digest: entry.digest, size: entry.byteLength)
      try hit(.afterBlobCopy, stage.transactionID, name)
      try hit(.beforeBlobFileSync, stage.transactionID, name)
      try sync(output, name)
      try hit(.afterBlobFileSync, stage.transactionID, name)
      try hit(.beforeBlobInstall, stage.transactionID, name)
      // Atomic exclusive rename avoids both overwrites and a crash-visible hard-link interval.
      if renameatx_np(objects, temporary, objects, name, UInt32(RENAME_EXCL)) != 0 {
        guard errno == EEXIST else { throw LibraryExchangeStorageError.io(name, errno) }
        try verifyFile(directory: objects, path: name, digest: entry.digest, size: entry.byteLength)
        guard unlinkat(objects, temporary, 0) == 0 else { throw LibraryExchangeStorageError.io(temporary, errno) }
      }
      try hit(.afterBlobInstall, stage.transactionID, name)
      try hit(.beforeBlobDirectorySync, stage.transactionID, name)
      try sync(objects, name)
      try hit(.afterBlobDirectorySync, stage.transactionID, name)
    }
    try hit(.beforeJournalTransition, stage.transactionID, stagingPath(stage.transactionID))
    try writeEnvelope(Journal(version: 1, state: "assetsInstalled", stage: stage), directory: fd, name: "journal.json", maximumBytes: Self.maximumJournalBytes)
    try hit(.afterJournalTransition, stage.transactionID, stagingPath(stage.transactionID))
  }

  package func verifyObject(digest: ExchangeDigest, byteLength: UInt64) throws {
    let fd = try directory("objects/sha256"); defer { Darwin.close(fd) }
    try verifyFile(directory: fd, path: digest.description, digest: digest, size: byteLength)
  }
  package func readObject(digest: ExchangeDigest, byteLength: UInt64, maximumBytes: Int) throws -> Data {
    DrawingLibraryDiagnostics.shared.record("storageObjectReads")
    guard maximumBytes > 0, byteLength <= UInt64(maximumBytes) else { throw LibraryExchangeStorageError.corruptObject("record exceeds materialization bound") }
    let parent = try directory("objects/sha256"); defer { Darwin.close(parent) }
    let input = try openFile(directory: parent, path: digest.description); defer { Darwin.close(input) }
    var result = Data()
    try stream(input: input, output: nil, digest: digest, size: byteLength) { bytes, count in result.append(contentsOf: bytes.prefix(count)) }
    return result
  }
  package func objectURL(digest: ExchangeDigest) -> URL {
    // F_GETPATH follows a retained directory when its caller legitimately promotes the library.
    (try? currentURL(rootFD))?.appendingPathComponent("objects/sha256/" + digest.description)
      ?? lease.canonicalRootURL.appendingPathComponent("objects/sha256/" + digest.description)
  }
  package func preserveConflict(transactionID: UUID) throws -> URL {
    _ = try journal(transactionID)
    let source = try directory("exchange-staging"), target = try directory("exchange-conflicts")
    defer { Darwin.close(source); Darwin.close(target) }
    let name = transactionID.uuidString.lowercased()
    var existing = stat()
    guard fstatat(target, name, &existing, AT_SYMLINK_NOFOLLOW) != 0, errno == ENOENT else { throw LibraryExchangeStorageError.conflict(name) }
    guard renameat(source, name, target, name) == 0 else { throw LibraryExchangeStorageError.io(name, errno) }
    try sync(source, name); try sync(target, name)
    return try currentURL(target).appendingPathComponent(name)
  }
  /// Caller must first prove no published SQL references belong to this transaction.
  package func collectStaging(transactionID: UUID) throws { try removeStage(transactionID) }
  /// Caller must first prove SQL committed the exact durable transaction identity.
  package func finish(transactionID: UUID) throws { try removeStage(transactionID) }

  /// A fixed, bounded authority-marker primitive; catalog policy remains with the SQL owner.
  package func durableMetadataWrite(_ data: Data, name: String = "drawing-authority.json") throws {
    guard name == "drawing-authority.json", data.count <= Self.maximumMetadataBytes else { throw LibraryExchangeStorageError.invalidPath(name) }
    // Never treat an unsafe/corrupt existing marker as absent.
    if let existing = try readMetadata(name: name) { _ = try ExchangeJSON.validate(existing, maximumBytes: Self.maximumMetadataBytes) }
    _ = try ExchangeJSON.validate(data, maximumBytes: Self.maximumMetadataBytes)
    try atomicWrite(data, directory: rootFD, name: name)
  }
  package func readMetadata(name: String = "drawing-authority.json") throws -> Data? {
    guard name == "drawing-authority.json" else { throw LibraryExchangeStorageError.invalidPath(name) }
    var info = stat()
    if fstatat(rootFD, name, &info, AT_SYMLINK_NOFOLLOW) != 0 {
      guard errno == ENOENT else { throw LibraryExchangeStorageError.io(name, errno) }; return nil
    }
    return try boundedRead(directory: rootFD, path: name)
  }

  private func journal(_ id: UUID) throws -> Journal {
    let fd = try directory(stagingPath(id)); defer { Darwin.close(fd) }
    let value: Journal = try readEnvelope(directory: fd, name: "journal.json", maximumBytes: Self.maximumJournalBytes)
    guard value.version == 1, ["prepared", "assetsInstalled"].contains(value.state), value.stage.transactionID == id,
      value.stage.intent.count <= Self.maximumPublicationIntentBytes else { throw LibraryExchangeStorageError.invalidJournal(id.uuidString) }
    try Self.validateInventory(value.stage.entries)
    return value
  }
  private func removeStage(_ id: UUID) throws {
    _ = try journal(id) // Refuse deletion of corrupt or unidentified intent.
    let parent = try directory("exchange-staging"); defer { Darwin.close(parent) }
    let name = id.uuidString.lowercased()
    try hit(.beforeCleanup, id, stagingPath(id))
    let cleanupName = ".cleanup-" + name + "-" + UUID().uuidString.lowercased()
    guard renameatx_np(parent, name, parent, cleanupName, UInt32(RENAME_EXCL)) == 0 else { throw LibraryExchangeStorageError.io(name, errno) }
    try sync(parent, cleanupName)
    try removeTree(parent: parent, name: cleanupName) { try self.hit(.duringCleanup, id, cleanupName) }
    try sync(parent, name)
    try hit(.afterCleanup, id, stagingPath(id))
  }
  // Preparing phases have not published SQL; cleanup phases have already been reconciled
  // by the SQL owner. Preserve interrupted private phases for inspection. Only the
  // caller's published UUID transactions are reconciled automatically.
  private static func isPrivateStageName(_ name: String) -> Bool {
    for prefix in [".preparing-", ".cleanup-"] where name.hasPrefix(prefix) {
      let rest = String(name.dropFirst(prefix.count))
      guard rest.count == 73 else { return false }
      let first = String(rest.prefix(36)), last = String(rest.suffix(36))
      return rest[rest.index(rest.startIndex, offsetBy: 36)] == "-"
        && UUID(uuidString: first)?.uuidString.lowercased() == first
        && UUID(uuidString: last)?.uuidString.lowercased() == last
    }
    return false
  }
  private final class CopyProgress: @unchecked Sendable {
    let callback: () throws -> Void
    var failure: Error?
    var checks = 0
    init(_ callback: @escaping () throws -> Void) { self.callback = callback }
    func cancelled() -> Bool {
      checks += 1
      // Carrier checks once per file and per buffer; the third check follows real IO.
      if checks >= 3 { do { try callback() } catch { failure = error; return true } }
      return false
    }
  }
  private func stagingPath(_ id: UUID) -> String { "exchange-staging/" + id.uuidString.lowercased() }
  func hit(_ boundary: LibraryExchangeStorageFault.Boundary, _ transaction: UUID?, _ path: String) throws {
    try fault(.init(boundary: boundary, transactionID: transaction, path: path))
  }

  static func validatePath(_ path: String) throws {
    let parts = path.split(separator: "/", omittingEmptySubsequences: false)
    guard !parts.isEmpty, path.utf8.count <= 4096, !path.contains("\\"), !path.contains(":"),
      !path.unicodeScalars.contains(where: { $0.value < 32 || $0.value == 127 }),
      parts.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." && $0.utf8.count <= 255 }) else { throw LibraryExchangeStorageError.invalidPath(path) }
  }
  static func validateInventory(_ entries: [LibraryExchangeStorageEntry]) throws {
    guard !entries.isEmpty, entries.count <= 100_000 else { throw LibraryExchangeStorageError.invalidInventory }
    var paths = Set<String>(), folded = Set<String>(), sizes: [ExchangeDigest: UInt64] = [:], components: [String: String] = [:]
    for entry in entries {
      try validatePath(entry.path)
      let key = entry.path.precomposedStringWithCanonicalMapping.folding(options: [.caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
      guard paths.insert(entry.path).inserted, folded.insert(key).inserted, entry.byteLength <= UInt64(Int64.max),
        sizes[entry.digest] == nil || sizes[entry.digest] == entry.byteLength else { throw LibraryExchangeStorageError.invalidInventory }
      sizes[entry.digest] = entry.byteLength
      let parts = entry.path.split(separator: "/")
      for count in 1...parts.count {
        let original = parts.prefix(count).joined(separator: "/")
        let key = original.precomposedStringWithCanonicalMapping.folding(options: [.caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        guard components[key] == nil || components[key] == original else { throw LibraryExchangeStorageError.invalidInventory }
        components[key] = original
      }
    }
    for path in paths {
      let parts = path.split(separator: "/")
      for count in 1..<parts.count where paths.contains(parts.prefix(count).joined(separator: "/")) { throw LibraryExchangeStorageError.invalidInventory }
    }
  }

  // Every descendant walk is relative to a retained directory and rejects symlinks.
  func directory(_ path: String, create: Bool = false) throws -> Int32 {
    try Self.validatePath(path)
    var fd = dup(rootFD)
    guard fd >= 0 else { throw LibraryExchangeStorageError.io(path, errno) }
    do {
      for component in path.split(separator: "/").map(String.init) {
        if create {
          if mkdirat(fd, component, 0o700) == 0 { try sync(fd, component) }
          else if errno != EEXIST { throw LibraryExchangeStorageError.io(component, errno) }
        }
        let next = openat(fd, component, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard next >= 0 else { throw LibraryExchangeStorageError.io(component, errno) }
        Darwin.close(fd); fd = next
      }
      return fd
    } catch { Darwin.close(fd); throw error }
  }
  func openFile(directory: Int32, path: String) throws -> Int32 {
    try Self.validatePath(path)
    var parent = dup(directory)
    guard parent >= 0 else { throw LibraryExchangeStorageError.io(path, errno) }; defer { Darwin.close(parent) }
    let parts = path.split(separator: "/").map(String.init)
    for part in parts.dropLast() {
      let next = openat(parent, part, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
      guard next >= 0 else { throw LibraryExchangeStorageError.io(path, errno) }; Darwin.close(parent); parent = next
    }
    let fd = openat(parent, parts.last!, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
    guard fd >= 0 else {
      if errno == ENOENT { throw LibraryExchangeStorageError.missingObject(path) }
      throw LibraryExchangeStorageError.io(path, errno)
    }
    var info = stat()
    guard fstat(fd, &info) == 0, info.st_mode & S_IFMT == S_IFREG, info.st_nlink == 1, info.st_size >= 0 else {
      Darwin.close(fd); throw LibraryExchangeStorageError.corruptObject(path)
    }
    return fd
  }
  func verifyFile(directory: Int32, path: String, digest: ExchangeDigest, size: UInt64) throws {
    DrawingLibraryDiagnostics.shared.record("storageFileVerifications")
    let input = try openFile(directory: directory, path: path); defer { Darwin.close(input) }
    try stream(input: input, output: nil, digest: digest, size: size)
  }
  func stream(input: Int32, output: Int32?, digest: ExchangeDigest, size: UInt64, consume: (([UInt8], Int) throws -> Void)? = nil) throws {
    var before = stat()
    guard fstat(input, &before) == 0, before.st_size >= 0, before.st_nlink == 1, UInt64(before.st_size) == size else { throw LibraryExchangeStorageError.corruptObject(digest.description) }
    var buffer = [UInt8](repeating: 0, count: 64 * 1024), count: UInt64 = 0, hash = SHA256()
    while true {
      let n = Darwin.read(input, &buffer, buffer.count)
      if n < 0 && errno == EINTR { continue }
      guard n >= 0 else { throw LibraryExchangeStorageError.io("read", errno) }; if n == 0 { break }
      guard count <= size, UInt64(n) <= size - count else { throw LibraryExchangeStorageError.corruptObject(digest.description) }
      buffer.withUnsafeBytes { hash.update(bufferPointer: UnsafeRawBufferPointer(rebasing: $0[..<n])) }
      if let output { try writeAll(output, bytes: buffer, count: n) }
      try consume?(buffer, n)
      count += UInt64(n)
    }
    DrawingLibraryDiagnostics.shared.record("storageStreamHashBytes", count: count)
    var after = stat()
    let actual = hash.finalize().map { String(format: "%02x", $0) }.joined()
    guard count == size, actual == digest.description, fstat(input, &after) == 0,
      before.st_dev == after.st_dev, before.st_ino == after.st_ino, before.st_size == after.st_size, after.st_nlink == 1,
      before.st_mtimespec.tv_sec == after.st_mtimespec.tv_sec, before.st_mtimespec.tv_nsec == after.st_mtimespec.tv_nsec,
      before.st_ctimespec.tv_sec == after.st_ctimespec.tv_sec, before.st_ctimespec.tv_nsec == after.st_ctimespec.tv_nsec else { throw LibraryExchangeStorageError.corruptObject(digest.description) }
  }
  func writeAll(_ fd: Int32, bytes: [UInt8], count: Int) throws {
    try bytes.withUnsafeBytes { raw in
      var offset = 0
      while offset < count {
        let n = Darwin.write(fd, raw.baseAddress!.advanced(by: offset), count - offset)
        if n < 0 && errno == EINTR { continue }
        guard n > 0 else { throw LibraryExchangeStorageError.io("write", errno) }; offset += n
      }
    }
  }
  func sync(_ fd: Int32, _ path: String) throws {
    guard fsync(fd) == 0 else { throw LibraryExchangeStorageError.io("fsync " + path, errno) }
  }
  func names(_ fd: Int32) throws -> [String] {
    let scan = openat(fd, ".", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
    guard scan >= 0, let dir = fdopendir(scan) else { if scan >= 0 { Darwin.close(scan) }; throw LibraryExchangeStorageError.io("enumerate", errno) }
    defer { closedir(dir) }
    var result: [String] = []
    errno = 0
    while let item = readdir(dir) {
      let name = withUnsafePointer(to: &item.pointee.d_name) { $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXNAMLEN) + 1) { String(cString: $0) } }
      if name != ".", name != ".." { result.append(name) }
      errno = 0
    }
    guard errno == 0 else { throw LibraryExchangeStorageError.io("enumerate", errno) }
    return result
  }
  private func verifyBag(_ fd: Int32, entries: [LibraryExchangeStorageEntry], syncFiles: Bool) throws {
    var actual = Set<String>(), folded = Set<String>()
    let expected = Dictionary(uniqueKeysWithValues: entries.map { ($0.path, $0) })
    var expectedDirectories = Set<String>()
    for entry in entries {
      let parts = entry.path.split(separator: "/")
      for count in 1..<parts.count { expectedDirectories.insert(parts.prefix(count).joined(separator: "/")) }
    }
    func walk(_ directory: Int32, prefix: String) throws {
      for name in try names(directory) {
        let path = prefix + name; try Self.validatePath(path)
        let key = path.precomposedStringWithCanonicalMapping.folding(options: [.caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        guard folded.insert(key).inserted else { throw LibraryExchangeStorageError.invalidInventory }
        var info = stat()
        guard fstatat(directory, name, &info, AT_SYMLINK_NOFOLLOW) == 0 else { throw LibraryExchangeStorageError.io(path, errno) }
        if info.st_mode & S_IFMT == S_IFDIR {
          guard expectedDirectories.contains(path) else { throw LibraryExchangeStorageError.invalidInventory }
          let child = openat(directory, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
          guard child >= 0 else { throw LibraryExchangeStorageError.io(path, errno) }; defer { Darwin.close(child) }
          var opened = stat()
          guard fstat(child, &opened) == 0, opened.st_dev == info.st_dev, opened.st_ino == info.st_ino else { throw LibraryExchangeStorageError.corruptObject(path) }
          try walk(child, prefix: path + "/")
        } else {
          guard actual.insert(path).inserted else { throw LibraryExchangeStorageError.invalidInventory }
          guard let entry = expected[path] else { throw LibraryExchangeStorageError.invalidInventory }
          let input = try openFile(directory: directory, path: name); defer { Darwin.close(input) }
          try stream(input: input, output: nil, digest: entry.digest, size: entry.byteLength)
          if syncFiles { try sync(input, path) }
        }
      }
      if syncFiles { try sync(directory, prefix) }
    }
    try walk(fd, prefix: "")
    guard actual == Set(entries.map(\.path)) else { throw LibraryExchangeStorageError.invalidInventory }
  }
  func currentURL(_ fd: Int32) throws -> URL {
    var path = [CChar](repeating: 0, count: Int(MAXPATHLEN))
    guard fcntl(fd, F_GETPATH, &path) == 0 else { throw LibraryExchangeStorageError.io("directory path", errno) }
    return URL(fileURLWithPath: String(cString: path), isDirectory: true)
  }
  private struct Envelope: Codable { let version: Int; let digest: ExchangeDigest; let payload: Data }
  func writeEnvelope<T: Encodable>(_ value: T, directory: Int32, name: String, maximumBytes: Int = LibraryExchangeStorage.maximumMetadataBytes) throws {
    let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    let payload = try encoder.encode(value)
    let envelope = try encoder.encode(Envelope(version: 1, digest: .hash(payload), payload: payload))
    guard envelope.count <= maximumBytes else { throw LibraryExchangeStorageError.resourceLimit("metadata envelope exceeds configured byte policy") }
    try atomicWrite(envelope, directory: directory, name: name)
  }
  func readEnvelope<T: Decodable>(directory: Int32, name: String, maximumBytes: Int = LibraryExchangeStorage.maximumMetadataBytes) throws -> T {
    let bytes = try boundedRead(directory: directory, path: name, maximumBytes: maximumBytes)
    let outer = try ExchangeJSON.validate(bytes, maximumBytes: maximumBytes)
    guard Set(outer.keys) == ["version", "digest", "payload"] else { throw LibraryExchangeStorageError.invalidJournal("envelope fields") }
    let envelope = try JSONDecoder().decode(Envelope.self, from: bytes)
    guard envelope.version == 1, envelope.digest == .hash(envelope.payload) else { throw LibraryExchangeStorageError.invalidJournal("checksum/version") }
    _ = try ExchangeJSON.validate(envelope.payload, maximumBytes: maximumBytes)
    return try JSONDecoder().decode(T.self, from: envelope.payload)
  }
  func boundedRead(directory: Int32, path: String, maximumBytes: Int = LibraryExchangeStorage.maximumMetadataBytes) throws -> Data {
    let fd = try openFile(directory: directory, path: path); defer { Darwin.close(fd) }
    var info = stat()
    guard fstat(fd, &info) == 0, info.st_size <= maximumBytes else { throw LibraryExchangeStorageError.resourceLimit("metadata exceeds configured byte policy") }
    var result = Data(), buffer = [UInt8](repeating: 0, count: 64 * 1024)
    while true {
      let n = Darwin.read(fd, &buffer, buffer.count)
      if n < 0 && errno == EINTR { continue }
      guard n >= 0 else { throw LibraryExchangeStorageError.io(path, errno) }; if n == 0 { break }
      guard result.count <= maximumBytes - n else { throw LibraryExchangeStorageError.resourceLimit("metadata grew beyond byte policy") }
      result.append(contentsOf: buffer.prefix(n))
    }
    var after = stat()
    guard result.count == Int(info.st_size), fstat(fd, &after) == 0, info.st_size == after.st_size, after.st_nlink == 1,
      info.st_mtimespec.tv_sec == after.st_mtimespec.tv_sec, info.st_mtimespec.tv_nsec == after.st_mtimespec.tv_nsec,
      info.st_ctimespec.tv_sec == after.st_ctimespec.tv_sec, info.st_ctimespec.tv_nsec == after.st_ctimespec.tv_nsec else { throw LibraryExchangeStorageError.invalidJournal("metadata changed during read") }
    return result
  }
  func atomicWrite(_ data: Data, directory: Int32, name: String) throws {
    try Self.validatePath(name)
    guard !name.contains("/") else { throw LibraryExchangeStorageError.invalidPath(name) }
    var info = stat()
    if fstatat(directory, name, &info, AT_SYMLINK_NOFOLLOW) == 0 {
      guard info.st_mode & S_IFMT == S_IFREG, info.st_nlink == 1 else { throw LibraryExchangeStorageError.corruptObject(name) }
    } else if errno != ENOENT { throw LibraryExchangeStorageError.io(name, errno) }
    let temporary = ".metadata-" + UUID().uuidString.lowercased()
    let fd = openat(directory, temporary, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
    guard fd >= 0 else { throw LibraryExchangeStorageError.io(temporary, errno) }; defer { Darwin.close(fd) }
    try writeAll(fd, bytes: Array(data), count: data.count); try sync(fd, name)
    guard renameat(directory, temporary, directory, name) == 0 else { throw LibraryExchangeStorageError.io(name, errno) }
    try sync(directory, name)
  }
  func removeTree(parent: Int32, name: String, progress: (() throws -> Void)? = nil) throws {
    try Self.validatePath(name)
    guard !name.contains("/") else { throw LibraryExchangeStorageError.invalidPath(name) }
    let fd = openat(parent, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
    guard fd >= 0 else { throw LibraryExchangeStorageError.io(name, errno) }; defer { Darwin.close(fd) }
    var original = stat(); guard fstat(fd, &original) == 0 else { throw LibraryExchangeStorageError.io(name, errno) }
    for child in try names(fd) {
      var info = stat()
      guard fstatat(fd, child, &info, AT_SYMLINK_NOFOLLOW) == 0 else { throw LibraryExchangeStorageError.io(child, errno) }
      if info.st_mode & S_IFMT == S_IFDIR { try removeTree(parent: fd, name: child, progress: progress) }
      else {
        guard info.st_mode & S_IFMT == S_IFREG, info.st_nlink == 1 else { throw LibraryExchangeStorageError.corruptObject(child) }
        guard unlinkat(fd, child, 0) == 0 else { throw LibraryExchangeStorageError.io(child, errno) }
        try progress?()
      }
    }
    var current = stat()
    guard fstatat(parent, name, &current, AT_SYMLINK_NOFOLLOW) == 0, current.st_ino == original.st_ino, current.st_dev == original.st_dev else { throw LibraryExchangeStorageError.conflict(name) }
    guard unlinkat(parent, name, AT_REMOVEDIR) == 0 else { throw LibraryExchangeStorageError.io(name, errno) }
  }
}
