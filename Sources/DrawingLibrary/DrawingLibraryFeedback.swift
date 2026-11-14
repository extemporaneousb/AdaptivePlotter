import Foundation
import PortraitCore

/// Exact publication context, independent of any mutable Domain navigation key.
public struct DrawingLibraryFeedbackRef: Hashable, Codable, Sendable {
  public let indexDigest: ExchangeDigest
  public let packageDigest: ExchangeDigest
  public init(publication: ValidatedExchangePackage) {
    indexDigest = .hash(publication.index.originalJSON)
    packageDigest = LibraryExchangeCatalog.inventoryDigest(publication.files.entries.values.map { .init(path: $0.path, digest: $0.digest, byteLength: $0.byteLength) })
  }
  public init(indexDigest: ExchangeDigest, packageDigest: ExchangeDigest) {
    self.indexDigest = indexDigest; self.packageDigest = packageDigest
  }
}
extension DrawingLibrary {
  /// Canonical feedback and its navigation commit through the existing journal.
  /// The Library preserves answers without granting their task-specific meaning.
  public func commitFeedback(_ publication: ValidatedExchangePackage,
    records: [DrawingLibraryRecord] = [], intent: DrawingLibraryCommitIntent = .init(),
    photoMetadata: [DrawingLibraryPhotoMetadataUpdate] = []) throws -> DrawingLibraryFeedbackRef {
    let admitted = try ExchangeAdmission.validate(files: publication.files,
      producerValidators: producerValidators, payloadValidators: payloadValidators)
    guard admitted.index.known?.kind == "feedback" else { throw DrawingLibraryError.unsupportedFeature("Feedback index required") }
    let inventory = admitted.files.entries.values.map { LibraryExchangeStorageEntry(path: $0.path, digest: $0.digest, byteLength: $0.byteLength) }
    let reference = DrawingLibraryFeedbackRef(indexDigest: .hash(admitted.index.originalJSON), packageDigest: LibraryExchangeCatalog.inventoryDigest(inventory))
    let batch = DrawingLibraryRecordBatch(records: records, removing: [], photoMetadata: photoMetadata)
    let batchDigest = try domainRequest(batch, assets: [])
    let request = ExchangeDigest.hash(Data((batchDigest.description + ":" + reference.indexDigest.description + ":" + reference.packageDigest.description).utf8))
    let catalog = try commonCatalog()
    defer { refreshOwnership() }
    for update in photoMetadata { try catalog.validatePhotoPatch(update.patch) }
    let commit = DrawingLibraryDomainCommit(intent: intent.id, request: request, batch: batch, retained: [])
    do { _ = try catalog.publish(admitted, domainCommit: commit) }
    catch LibraryExchangeCatalogError.preservedConflict(let location) { throw DrawingLibraryError.quarantinedConflict(location) }
    return reference
  }

  public func mountFeedback(from source: URL, records: [DrawingLibraryRecord] = [],
    intent: DrawingLibraryCommitIntent = .init(), photoMetadata: [DrawingLibraryPhotoMetadataUpdate] = []) throws -> DrawingLibraryFeedbackRef {
    let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("feedback-mount-" + UUID().uuidString.lowercased(), isDirectory: true)
    try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
    defer { try? FileManager.default.removeItem(at: temporary) }
    var directory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: source.path, isDirectory: &directory) else { throw DrawingLibraryError.unavailable("Feedback source unavailable") }
    let staged = try directory.boolValue ? DrawingExchangeCarrier.stageDirectory(source, stagingParent: temporary) : DrawingExchangeCarrier.stageZIP(source, stagingParent: temporary)
    let admitted = try ExchangeAdmission.validate(staged, producerValidators: producerValidators, payloadValidators: payloadValidators)
    return try commitFeedback(admitted, records: records, intent: intent, photoMetadata: photoMetadata)
  }

  /// Read-only: no root creation, writer acquisition or recovery side effects.
  public func feedback(_ reference: DrawingLibraryFeedbackRef) throws -> ValidatedExchangePackage {
    guard let db = try commonReadDatabase() else { throw DrawingLibraryError.unavailable("Feedback publication unavailable") }
    return try autoreleasepool { try db.readSnapshot { db in
      guard let transaction = try db.scalar("SELECT id FROM dx_transaction WHERE index_digest=? AND package_digest=? ORDER BY id LIMIT 1", [reference.indexDigest.description, reference.packageDigest.description]) else { throw DrawingLibraryError.unavailable("Feedback publication unavailable") }
      let inventory = try db.rows("SELECT f.path,f.digest,o.byte_length FROM dx_tx_file f JOIN dx_object o ON o.digest=f.digest WHERE f.transaction_id=? ORDER BY f.path", [transaction]).map { row -> LibraryExchangeStorageEntry in
        guard let path = row[0], let digest = row[1], let length = row[2].flatMap(UInt64.init) else { throw DrawingLibraryError.invalidIdentity }
        return .init(path: path, digest: try ExchangeDigest(digest), byteLength: length)
      }
      guard LibraryExchangeCatalog.inventoryDigest(inventory) == reference.packageDigest,
        inventory.first(where: { $0.path == "data/exchange.json" })?.digest == reference.indexDigest else { throw DrawingLibraryError.invalidIdentity }
      let files = try VerifiedExchangeFiles(catalogRoot: directoryURL, inventory: inventory.map {
        .init(path: $0.path, storagePath: "objects/sha256/" + $0.digest.description, digest: $0.digest, byteLength: $0.byteLength)
      })
      let admitted = try ExchangeAdmission.validate(files: files, producerValidators: producerValidators, payloadValidators: payloadValidators)
      guard admitted.index.known?.kind == "feedback", ExchangeDigest.hash(admitted.index.originalJSON) == reference.indexDigest else { throw DrawingLibraryError.invalidIdentity }
      return admitted
    } }
  }
  public func exportFeedback(_ reference: DrawingLibraryFeedbackRef, to destination: URL) throws {
    let selected = try feedback(reference)
    if destination.pathExtension.lowercased() == "zip" { try DrawingExchangeCarrier.preserveZIP(selected.files, to: destination) }
    else { try DrawingExchangeCarrier.preserveDirectory(selected.files, to: destination) }
  }
}
