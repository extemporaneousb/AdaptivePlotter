import Foundation
import Darwin
import CryptoKit
import PortraitCore

public struct DrawingLibraryBackupReceipt: Sendable {
  public let generationID:UUID
  public let rootURL:URL
}
extension DrawingLibrary {
  public func createMetadataBackup(generationID:UUID=UUID())throws->DrawingLibraryBackupReceipt {
    let catalog=try commonCatalog(),db=catalog.database
    defer { refreshOwnership() }
    let inventory=try catalog.backupInventory()
    try LibraryExchangeCatalog.validateBackup(database:db,inventory:inventory,objectsRoot:directoryURL)
    let value=try LibraryExchangeMetadataBackup(storage:catalog.storage).create(generationID:generationID,objects:inventory,onlineBackup:{ try db.backup(to:$0) },validate:{ try DrawingLibraryDatabase(url:$0,readOnly:true).integrityCheck() })
    return .init(generationID:value.generationID,rootURL:value.rootURL)
  }
  /// Requires all existing owners to be drained and closed. The writer lease
  /// excludes replacement while another owner remains active.
  public nonisolated static func restoreMetadataBackup(directoryURL:URL,generationID:UUID)throws {
    try LibraryExchangeCatalog.restore(root:directoryURL,generationID:generationID)
  }
}
extension LibraryExchangeCatalog {
  package static func validateBackup(database db:DrawingLibraryDatabase,inventory:[LibraryExchangeStorageEntry],objectsRoot:URL)throws {
    try db.integrityCheck()
    guard UInt64(inventory.count)<=LibraryExchangeMetadataBackup.InventoryPolicy.maximumEntries else { throw DrawingExchangeError.limit("Backup inventory") }
    let objects=Dictionary(uniqueKeysWithValues:inventory.map{($0.digest.description,$0)})
    for row in try db.rows("SELECT digest,byte_length FROM dx_object") {
      guard let digest=row[0],let raw=row[1],let length=UInt64(raw),let object=objects[digest],object.path=="objects/sha256/"+digest,object.byteLength==length else { throw DrawingLibraryError.invalidIdentity }
    }
    for object in inventory {
      let files=try VerifiedExchangeFiles(catalogRoot:objectsRoot,inventory:[.init(path:object.path,storagePath:object.path,digest:object.digest,byteLength:object.byteLength)])
      try files.verifyInventory()
    }
  }
  package static func restore(root: URL, generationID: UUID, fault: (LibraryExchangeCatalogBoundary) throws -> Void = { _ in }) throws {
    let lease = try DrawingLibraryWriterLease(root: root)
    try LibraryExchangeCatalogSelection.validate(root: lease.canonicalRootURL, database: lease.canonicalRootURL.appendingPathComponent("drawing-library.sqlite"), requireDatabase: false)
    let storage = try LibraryExchangeStorage(root: root, lease: lease)
    let backups = LibraryExchangeMetadataBackup(storage: storage)
    let plan = try backups.prepareRestore(generationID: generationID) { try DrawingLibraryDatabase(url: $0, readOnly: true).integrityCheck() }
    let restored = try DrawingLibraryDatabase(url: plan.databaseURL, readOnly: true)
    try validateBackup(database:restored,inventory:plan.objects,objectsRoot:plan.rootURL)
    try storage.durableMetadataWrite(LibraryExchangeCatalogSelection.markerBytes, name: "drawing-authority.json")
    try backups.installRestoredObjects(plan)
    for stage in try storage.pendingTransactions() { _ = try storage.preserveConflict(transactionID: stage.transactionID) }
    let destination = lease.canonicalRootURL.appendingPathComponent("drawing-library.sqlite")
    try fault(.beforeRestorePreservation)
    var info = stat()
    if lstat(destination.path, &info) == 0 {
      guard info.st_mode & S_IFMT == S_IFREG else { throw DrawingLibraryError.ownership("Selected catalog is not a regular file") }
      try preserveCommonDatabase(destination, storage: storage)
    } else if errno != ENOENT { throw DrawingLibraryError.ownership("Selected catalog cannot be inspected") }
    try fault(.afterRestorePreservation)
    try validateBackup(database:restored,inventory:plan.objects,objectsRoot:plan.rootURL)
    try fault(.beforeRestoreSelection)
    guard Darwin.rename(plan.databaseURL.path, destination.path) == 0 else { throw DrawingLibraryError.ownership("Cannot select restored catalog; prior bytes retained") }
    try storage.sync(storage.rootFD, "select restored catalog")
    let parent = Darwin.open(plan.rootURL.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
    guard parent >= 0 else { throw DrawingLibraryError.ownership("Restore directory unavailable") }
    defer { Darwin.close(parent) }
    try storage.sync(parent, "restore source rename"); try fault(.afterRestoreSelection)
  }
  private static func preserveCommonDatabase(_ source: URL, storage: LibraryExchangeStorage) throws {
    let input = Darwin.open(source.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
    guard input >= 0 else { throw DrawingLibraryDatabaseError.database("Cannot open prior catalog") }
    defer { Darwin.close(input) }
    var before = stat()
    guard fstat(input, &before) == 0, before.st_mode & S_IFMT == S_IFREG, before.st_size >= 0 else { throw DrawingLibraryDatabaseError.database("Invalid prior catalog") }
    let name = "library-prior-" + UUID().uuidString.lowercased() + ".sqlite"
    let output = openat(storage.rootFD, name, O_CREAT | O_EXCL | O_WRONLY | O_NOFOLLOW | O_CLOEXEC, 0o600)
    guard output >= 0 else { throw DrawingLibraryDatabaseError.database("Cannot preserve prior catalog") }
    defer { Darwin.close(output) }
    var buffer = [UInt8](repeating: 0, count: 1024 * 1024), copied: Int64 = 0, hash = SHA256()
    while true {
      let count = Darwin.read(input, &buffer, buffer.count)
      guard count >= 0 else { throw DrawingLibraryDatabaseError.database("Prior catalog read failed") }
      if count == 0 { break }
      copied += Int64(count)
      guard copied <= before.st_size else { throw DrawingLibraryDatabaseError.database("Prior catalog changed") }
      hash.update(data: Data(buffer.prefix(count)))
      try buffer.withUnsafeBytes { bytes in
        var offset = 0
        while offset < count {
          let n = Darwin.write(output, bytes.baseAddress!.advanced(by: offset), count - offset)
          guard n > 0 else { throw DrawingLibraryDatabaseError.database("Prior catalog copy failed") }; offset += n
        }
      }
    }
    var after = stat()
    guard fstat(input, &after) == 0, copied == before.st_size, before.st_size == after.st_size,
      before.st_ino == after.st_ino, before.st_mtimespec.tv_sec == after.st_mtimespec.tv_sec,
      before.st_mtimespec.tv_nsec == after.st_mtimespec.tv_nsec,
      before.st_ctimespec.tv_sec == after.st_ctimespec.tv_sec, before.st_ctimespec.tv_nsec == after.st_ctimespec.tv_nsec else { throw DrawingLibraryDatabaseError.database("Prior catalog changed during preservation") }
    try storage.sync(output, name)
    let digest = try ExchangeDigest(hash.finalize().map { String(format: "%02x", $0) }.joined())
    try storage.verifyFile(directory: storage.rootFD, path: name, digest: digest, size: UInt64(copied))
    try storage.sync(storage.rootFD, name)
  }

}
