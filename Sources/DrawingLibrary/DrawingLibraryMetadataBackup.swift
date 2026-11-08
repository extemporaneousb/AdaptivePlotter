import Foundation
import CryptoKit
import Darwin
import PortraitCore

package struct LibraryExchangeBackupGeneration: Equatable, Sendable {
  package let generationID: UUID
  package let rootURL: URL
  package let databaseURL: URL
  package let objects: [LibraryExchangeStorageEntry]
}
package struct LibraryExchangeRestorePlan: Equatable, Sendable {
  package let generationID: UUID
  package let rootURL: URL
  package let databaseURL: URL
  package let objects: [LibraryExchangeStorageEntry]
}

/// An explicitly identified immutable SQL snapshot, never a claim of continuous backup.
/// SQL ownership, inventory derivation and active-database replacement belong to the catalog.
package final class LibraryExchangeMetadataBackup {
  let storage: LibraryExchangeStorage
  // Whole-library metadata has a separate policy from a single admitted carrier.
  // Arrays at the API remain O(N); inventory IO never materializes the complete JSON.
  package enum InventoryPolicy {
    package static let maximumEntries: UInt64 = 2_000_000
    package static let maximumBytes: UInt64 = 1024 * 1024 * 1024
    package static let maximumLineBytes = 1024
    package static let bufferBytes = 64 * 1024
  }
  package struct InventoryFacts: Codable, Equatable {
    package let digest: ExchangeDigest
    package let byteLength: UInt64
    package let entryCount: UInt64
  }
  private struct Manifest: Codable {
    let version: Int
    let generationID: UUID
    let databaseDigest: ExchangeDigest
    let databaseByteLength: UInt64
    let inventoryFormat: String
    let inventory: InventoryFacts
  }
  private static let inventoryFormat = "drawing-exchange-inventory-jsonl/1"
  package init(storage: LibraryExchangeStorage) { self.storage = storage }

  /// Emits bounded canonical lines, also usable for a metadata-only resource-policy proof.
  package static func encodeInventory(_ objects: [LibraryExchangeStorageEntry], write: (Data) throws -> Void) throws -> InventoryFacts {
    guard UInt64(objects.count) <= InventoryPolicy.maximumEntries else { throw LibraryExchangeStorageError.resourceLimit("backup inventory exceeds 2000000 entries") }
    let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    var previous: String?, hash = SHA256(), byteLength: UInt64 = 0
    for object in objects.sorted(by: { $0.path < $1.path }) {
      try validateObject(object)
      guard previous == nil || previous! < object.path else { throw LibraryExchangeStorageError.invalidInventory }
      var line = try encoder.encode(object); line.append(10)
      guard line.count <= InventoryPolicy.maximumLineBytes,
        UInt64(line.count) <= InventoryPolicy.maximumBytes - byteLength else { throw LibraryExchangeStorageError.resourceLimit("backup inventory exceeds byte/line policy") }
      byteLength += UInt64(line.count); hash.update(data: line)
      try write(line); previous = object.path
    }
    return .init(digest: try ExchangeDigest(hash.finalize().map { String(format: "%02x", $0) }.joined()),
      byteLength: byteLength, entryCount: UInt64(objects.count))
  }

  package func create(generationID: UUID = UUID(), objects: [LibraryExchangeStorageEntry],
    onlineBackup: (URL) throws -> Void, validate: (URL) throws -> Void) throws -> LibraryExchangeBackupGeneration {
    // Reject aggregate count before sorting or allocating filesystem output.
    guard UInt64(objects.count) <= InventoryPolicy.maximumEntries else { throw LibraryExchangeStorageError.resourceLimit("backup inventory exceeds 2000000 entries") }
    for object in objects { try Self.validateObject(object) }
    let parent = try storage.directory("metadata-backups"); defer { Darwin.close(parent) }
    let name = generationID.uuidString.lowercased()
    let partial = ".partial-" + name + "-" + UUID().uuidString.lowercased()
    guard mkdirat(parent, partial, 0o700) == 0 else { throw LibraryExchangeStorageError.io(partial, errno) }
    try storage.sync(parent, partial)
    let fd = try storage.directory("metadata-backups/" + partial); defer { Darwin.close(fd) }
    let databaseURL = try storage.currentURL(fd).appendingPathComponent("drawing-library.sqlite")
    try onlineBackup(databaseURL)
    try validate(databaseURL)
    let database = try fingerprint(directory: fd, path: "drawing-library.sqlite")
    let dbFD = try storage.openFile(directory: fd, path: "drawing-library.sqlite"); defer { Darwin.close(dbFD) }
    try storage.sync(dbFD, "drawing-library.sqlite")
    let inventory = try writeInventory(objects, directory: fd)
    for object in objects { try copy(object, from: storage.rootFD, to: fd, transaction: generationID) }
    let manifest = Manifest(version: 2, generationID: generationID, databaseDigest: database.digest,
      databaseByteLength: database.byteLength, inventoryFormat: Self.inventoryFormat, inventory: inventory)
    try storage.writeEnvelope(manifest, directory: fd, name: "manifest.json")
    // Existing DB.backup may leave the administrative writer lock. Keep its inode.
    try validateNamespace(fd, count: inventory.entryCount)
    try storage.sync(fd, partial)
    try storage.hit(.beforeBackupPublish, generationID, "metadata-backups/" + name)
    guard renameatx_np(parent, partial, parent, name, UInt32(RENAME_EXCL)) == 0 else { throw LibraryExchangeStorageError.io(name, errno) }
    try storage.sync(parent, name)
    try storage.hit(.afterBackupPublish, generationID, "metadata-backups/" + name)
    let root = try storage.currentURL(parent).appendingPathComponent(name)
    return .init(generationID: generationID, rootURL: root,
      databaseURL: root.appendingPathComponent("drawing-library.sqlite"), objects: objects.sorted { $0.path < $1.path })
  }

  package func prepareRestore(generationID: UUID, validate: (URL) throws -> Void) throws -> LibraryExchangeRestorePlan {
    let name = generationID.uuidString.lowercased()
    let source = try storage.directory("metadata-backups/" + name); defer { Darwin.close(source) }
    let manifest: Manifest = try storage.readEnvelope(directory: source, name: "manifest.json")
    try validateManifest(manifest, generationID: generationID)
    let objects = try readInventory(directory: source, expected: manifest.inventory)
    try validateNamespace(source, count: manifest.inventory.entryCount)
    let database = LibraryExchangeStorageEntry(path: "drawing-library.sqlite", digest: manifest.databaseDigest, byteLength: manifest.databaseByteLength)
    try storage.verifyFile(directory: source, path: database.path, digest: database.digest, size: database.byteLength)
    for object in objects { try storage.verifyFile(directory: source, path: object.path, digest: object.digest, size: object.byteLength) }
    let partial = "restore-" + name + "-" + UUID().uuidString.lowercased()
    let parent = try storage.directory("metadata-restores"); defer { Darwin.close(parent) }
    guard mkdirat(parent, partial, 0o700) == 0 else { throw LibraryExchangeStorageError.io(partial, errno) }
    try storage.sync(parent, partial)
    let target = try storage.directory("metadata-restores/" + partial); defer { Darwin.close(target) }
    try copy(database, from: source, to: target, transaction: generationID)
    try copy(.init(path: "inventory.jsonl", digest: manifest.inventory.digest, byteLength: manifest.inventory.byteLength),
      from: source, to: target, transaction: generationID)
    for object in objects { try copy(object, from: source, to: target, transaction: generationID) }
    try storage.writeEnvelope(manifest, directory: target, name: "manifest.json")
    let root = try storage.currentURL(target)
    try validate(root.appendingPathComponent("drawing-library.sqlite"))
    try storage.verifyFile(directory: target, path: database.path, digest: database.digest, size: database.byteLength)
    try storage.sync(target, partial)
    return .init(generationID: generationID, rootURL: root,
      databaseURL: root.appendingPathComponent("drawing-library.sqlite"), objects: objects)
  }

  package func installRestoredObjects(_ plan: LibraryExchangeRestorePlan) throws {
    let expectedParent = try storage.directory("metadata-restores"); defer { Darwin.close(expectedParent) }
    let name = plan.rootURL.lastPathComponent
    guard name.hasPrefix("restore-" + plan.generationID.uuidString.lowercased() + "-"), !name.contains("/") else { throw LibraryExchangeStorageError.invalidPath(name) }
    let source = openat(expectedParent, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
    guard source >= 0 else { throw LibraryExchangeStorageError.io(name, errno) }; defer { Darwin.close(source) }
    let manifest: Manifest = try storage.readEnvelope(directory: source, name: "manifest.json")
    try validateManifest(manifest, generationID: plan.generationID)
    let objects = try readInventory(directory: source, expected: manifest.inventory)
    guard objects == plan.objects else { throw LibraryExchangeStorageError.invalidJournal("restore identity") }
    try validateNamespace(source, count: manifest.inventory.entryCount)
    for object in objects { try copy(object, from: source, to: storage.rootFD, transaction: plan.generationID) }
  }

  private func validateManifest(_ manifest: Manifest, generationID: UUID) throws {
    guard manifest.version == 2, manifest.generationID == generationID,
      manifest.inventoryFormat == Self.inventoryFormat,
      manifest.inventory.entryCount <= InventoryPolicy.maximumEntries,
      manifest.inventory.byteLength <= InventoryPolicy.maximumBytes,
      manifest.databaseByteLength <= UInt64(Int64.max) else { throw LibraryExchangeStorageError.invalidJournal("backup identity/version/resource policy") }
  }
  private static func validateObject(_ object: LibraryExchangeStorageEntry) throws {
    // Exact lowercase namespaces and validated lowercase hex remove Unicode/case aliases.
    let parts = object.path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
    let valid = (parts.count == 3 && parts[0] == "objects" && parts[1] == "sha256")
      || (parts.count == 2 && ["assets", "records"].contains(parts[0]))
      || (parts.count == 3 && parts[0] == "review-v1" && parts[1] == "assets")
    guard valid, parts.last == object.digest.description, object.byteLength <= UInt64(Int64.max) else { throw LibraryExchangeStorageError.invalidPath(object.path) }
  }
  private func writeInventory(_ objects: [LibraryExchangeStorageEntry], directory: Int32) throws -> InventoryFacts {
    let fd = openat(directory, "inventory.jsonl", O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o400)
    guard fd >= 0 else { throw LibraryExchangeStorageError.io("inventory.jsonl", errno) }; defer { Darwin.close(fd) }
    var buffer = Data(); buffer.reserveCapacity(InventoryPolicy.bufferBytes)
    let facts = try Self.encodeInventory(objects) { line in
      if buffer.count + line.count > InventoryPolicy.bufferBytes {
        try storage.writeAll(fd, bytes: Array(buffer), count: buffer.count); buffer.removeAll(keepingCapacity: true)
      }
      buffer.append(line)
    }
    if !buffer.isEmpty { try storage.writeAll(fd, bytes: Array(buffer), count: buffer.count) }
    try storage.sync(fd, "inventory.jsonl"); try storage.sync(directory, "inventory.jsonl")
    return facts
  }
  private func readInventory(directory: Int32, expected: InventoryFacts) throws -> [LibraryExchangeStorageEntry] {
    guard expected.entryCount <= InventoryPolicy.maximumEntries, expected.byteLength <= InventoryPolicy.maximumBytes else { throw LibraryExchangeStorageError.invalidInventory }
    let fd = try storage.openFile(directory: directory, path: "inventory.jsonl"); defer { Darwin.close(fd) }
    var before = stat()
    guard fstat(fd, &before) == 0, UInt64(before.st_size) == expected.byteLength else { throw LibraryExchangeStorageError.invalidInventory }
    let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    var objects: [LibraryExchangeStorageEntry] = [], line = Data(), buffer = [UInt8](repeating: 0, count: InventoryPolicy.bufferBytes)
    var hash = SHA256(), bytes: UInt64 = 0, previous: String?
    while true {
      let n = Darwin.read(fd, &buffer, buffer.count)
      if n < 0 && errno == EINTR { continue }
      guard n >= 0 else { throw LibraryExchangeStorageError.io("inventory.jsonl", errno) }; if n == 0 { break }
      guard UInt64(n) <= expected.byteLength - bytes else { throw LibraryExchangeStorageError.invalidInventory }
      bytes += UInt64(n)
      buffer.withUnsafeBytes { hash.update(bufferPointer: UnsafeRawBufferPointer(rebasing: $0[..<n])) }
      for byte in buffer.prefix(n) {
        guard line.count < InventoryPolicy.maximumLineBytes else { throw LibraryExchangeStorageError.invalidInventory }
        if byte == 10 {
          guard UInt64(objects.count) < expected.entryCount else { throw LibraryExchangeStorageError.invalidInventory }
          let value = try ExchangeJSON.validate(line, maximumBytes: InventoryPolicy.maximumLineBytes)
          guard Set(value.keys) == ["path", "digest", "byteLength"] else { throw LibraryExchangeStorageError.invalidInventory }
          let object = try JSONDecoder().decode(LibraryExchangeStorageEntry.self, from: line)
          try Self.validateObject(object)
          guard previous == nil || previous! < object.path, try encoder.encode(object) == line else { throw LibraryExchangeStorageError.invalidInventory }
          objects.append(object); previous = object.path; line.removeAll(keepingCapacity: true)
        } else { line.append(byte) }
      }
    }
    var after = stat()
    let digest = try ExchangeDigest(hash.finalize().map { String(format: "%02x", $0) }.joined())
    guard line.isEmpty, bytes == expected.byteLength, UInt64(objects.count) == expected.entryCount, digest == expected.digest,
      fstat(fd, &after) == 0, before.st_size == after.st_size, after.st_nlink == 1,
      before.st_mtimespec.tv_sec == after.st_mtimespec.tv_sec, before.st_mtimespec.tv_nsec == after.st_mtimespec.tv_nsec,
      before.st_ctimespec.tv_sec == after.st_ctimespec.tv_sec, before.st_ctimespec.tv_nsec == after.st_ctimespec.tv_nsec else { throw LibraryExchangeStorageError.invalidInventory }
    return objects
  }
  private func validateNamespace(_ root: Int32, count: UInt64) throws {
    let required: Set<String> = ["drawing-library.sqlite", "manifest.json", "inventory.jsonl"]
    let directories: Set<String> = ["objects", "objects/sha256", "assets", "records", "review-v1", "review-v1/assets"]
    var actual = Set<String>(), objectCount: UInt64 = 0
    func walk(_ fd: Int32, prefix: String) throws {
      for name in try storage.names(fd) {
        let path = prefix + name
        var info = stat()
        guard fstatat(fd, name, &info, AT_SYMLINK_NOFOLLOW) == 0 else { throw LibraryExchangeStorageError.io(path, errno) }
        if info.st_mode & S_IFMT == S_IFDIR {
          guard directories.contains(path) else { throw LibraryExchangeStorageError.invalidInventory }
          let child = openat(fd, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
          guard child >= 0 else { throw LibraryExchangeStorageError.io(path, errno) }; defer { Darwin.close(child) }
          var opened = stat()
          guard fstat(child, &opened) == 0, opened.st_dev == info.st_dev, opened.st_ino == info.st_ino else { throw LibraryExchangeStorageError.corruptObject(path) }
          try walk(child, prefix: path + "/")
        } else {
          let input = try storage.openFile(directory: fd, path: name); Darwin.close(input)
          if required.contains(path) { actual.insert(path) }
          else if path != "library-writer.lock" {
            guard objectCount < count else { throw LibraryExchangeStorageError.invalidInventory }
            try Self.validateObject(.init(path: path, digest: try ExchangeDigest(name), byteLength: UInt64(info.st_size)))
            objectCount += 1
          }
        }
      }
    }
    try walk(root, prefix: "")
    guard actual == required, objectCount == count else { throw LibraryExchangeStorageError.invalidInventory }
  }
  private func parentDirectory(_ root: Int32, path: String) throws -> (Int32, String) {
    try LibraryExchangeStorage.validatePath(path)
    let parts = path.split(separator: "/").map(String.init)
    var fd = dup(root)
    guard fd >= 0 else { throw LibraryExchangeStorageError.io(path, errno) }
    do {
      for part in parts.dropLast() {
        if mkdirat(fd, part, 0o700) == 0 { try storage.sync(fd, part) }
        else if errno != EEXIST { throw LibraryExchangeStorageError.io(part, errno) }
        let next = openat(fd, part, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard next >= 0 else { throw LibraryExchangeStorageError.io(part, errno) }
        Darwin.close(fd); fd = next
      }
      return (fd, parts.last!)
    } catch { Darwin.close(fd); throw error }
  }
  private func copy(_ entry: LibraryExchangeStorageEntry, from source: Int32, to target: Int32, transaction: UUID) throws {
    let input = try storage.openFile(directory: source, path: entry.path); defer { Darwin.close(input) }
    let (parent, name) = try parentDirectory(target, path: entry.path); defer { Darwin.close(parent) }
    var existing = stat()
    if fstatat(parent, name, &existing, AT_SYMLINK_NOFOLLOW) == 0 {
      try storage.verifyFile(directory: parent, path: name, digest: entry.digest, size: entry.byteLength); return
    }
    guard errno == ENOENT else { throw LibraryExchangeStorageError.io(name, errno) }
    let temporary = ".backup-" + UUID().uuidString.lowercased()
    let output = openat(parent, temporary, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o400)
    guard output >= 0 else { throw LibraryExchangeStorageError.io(temporary, errno) }; defer { Darwin.close(output) }
    try storage.hit(.beforeBlobCopy, transaction, entry.path)
    try storage.stream(input: input, output: output, digest: entry.digest, size: entry.byteLength)
    try storage.hit(.afterBlobCopy, transaction, entry.path)
    try storage.hit(.beforeBlobFileSync, transaction, entry.path)
    try storage.sync(output, entry.path)
    try storage.hit(.afterBlobFileSync, transaction, entry.path)
    try storage.hit(.beforeBlobInstall, transaction, entry.path)
    guard renameatx_np(parent, temporary, parent, name, UInt32(RENAME_EXCL)) == 0 else { throw LibraryExchangeStorageError.io(name, errno) }
    try storage.hit(.afterBlobInstall, transaction, entry.path)
    try storage.hit(.beforeBlobDirectorySync, transaction, entry.path)
    try storage.sync(parent, entry.path)
    try storage.hit(.afterBlobDirectorySync, transaction, entry.path)
  }
  private func fingerprint(directory: Int32, path: String) throws -> LibraryExchangeStorageEntry {
    let fd = try storage.openFile(directory: directory, path: path); defer { Darwin.close(fd) }
    var info = stat()
    guard fstat(fd, &info) == 0 else { throw LibraryExchangeStorageError.io(path, errno) }
    var buffer = [UInt8](repeating: 0, count: 64 * 1024), hash = SHA256(), size: UInt64 = 0
    while true {
      let n = Darwin.read(fd, &buffer, buffer.count)
      if n < 0 && errno == EINTR { continue }
      guard n >= 0 else { throw LibraryExchangeStorageError.io(path, errno) }; if n == 0 { break }
      buffer.withUnsafeBytes { hash.update(bufferPointer: UnsafeRawBufferPointer(rebasing: $0[..<n])) }; size += UInt64(n)
    }
    guard size == UInt64(info.st_size) else { throw LibraryExchangeStorageError.corruptObject(path) }
    let entry = LibraryExchangeStorageEntry(path: path, digest: try ExchangeDigest(hash.finalize().map { String(format: "%02x", $0) }.joined()), byteLength: size)
    // Re-read with the normal identity/stability checks to refuse mutation during fingerprinting.
    try storage.verifyFile(directory: directory, path: path, digest: entry.digest, size: entry.byteLength)
    return entry
  }
}
