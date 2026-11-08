import Darwin
import CryptoKit
import Foundation
import PortraitCore

/// A fixed marker distinguishes a lost selected catalog from a new legacy import.
/// It carries no reconstructible replacement for mutable metadata.
package enum PortraitExchangeCatalogSelection {
  private struct Marker: Codable, Equatable { let version: Int; let catalog: String }
  package static func markerPresent(root: URL) -> Bool {
    var info = stat()
    return lstat(root.path + "/exchange-authority.json", &info) == 0 || errno != ENOENT
  }
  package static let markerBytes = Data("{\"version\":1,\"catalog\":\"library-v1.sqlite\"}".utf8)
  @discardableResult
  package static func validate(root: URL, database: URL, requireDatabase: Bool = true) throws -> Bool {
    let markerPath = root.path + "/exchange-authority.json"
    var info = stat()
    if lstat(markerPath, &info) != 0 {
      guard errno == ENOENT else { throw PortraitLibraryError.database("Exchange authority marker is unavailable") }
      return false
    }
    guard info.st_mode & S_IFMT == S_IFREG, info.st_nlink == 1, info.st_size > 0, info.st_size <= 4096 else {
      throw PortraitLibraryError.database("Exchange authority marker is not a bounded private file")
    }
    let fd = Darwin.open(markerPath, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
    guard fd >= 0 else { throw PortraitLibraryError.database("Exchange authority marker cannot be opened") }
    defer { Darwin.close(fd) }
    var opened = stat()
    guard fstat(fd, &opened) == 0, opened.st_dev == info.st_dev, opened.st_ino == info.st_ino else {
      throw PortraitLibraryError.database("Exchange authority marker changed")
    }
    var bytes = [UInt8](repeating: 0, count: 4097)
    let count = Darwin.read(fd, &bytes, bytes.count)
    guard count > 0, count <= 4096,
      let object = try? ExchangeJSON.validate(Data(bytes.prefix(count)), maximumBytes: 4096),
      Set(object.keys) == Set(["version", "catalog"]),
      let value = try? JSONDecoder().decode(Marker.self, from: Data(bytes.prefix(count))),
      value == Marker(version: 1, catalog: "library-v1.sqlite"), database.lastPathComponent == value.catalog else {
      throw PortraitLibraryError.database("Unknown or corrupt exchange authority marker; explicit recovery required")
    }
    if !requireDatabase { return true }
    var catalog = stat()
    guard lstat(database.path, &catalog) == 0, catalog.st_mode & S_IFMT == S_IFREG else {
      throw PortraitLibraryError.database("Selected exchange catalog is missing; select a verified metadata backup generation")
    }
    return true
  }
}

package enum PortraitExchangeReference: Hashable, Codable, Sendable {
  case drawing(DrawingRef), photo(PhotoRef), input(ImageInputRef), assessment(AssessmentRef)
  case ranking(RankingCapsuleRef), receipt(JobReceiptRef), snapshot(SnapshotRef)
  package var digest: ExchangeDigest {
    switch self {
    case .drawing(let r): r.digest
    case .photo(let r): r.digest
    case .input(let r): r.digest
    case .assessment(let r): r.digest
    case .ranking(let r): r.digest
    case .receipt(let r): r.receiptDigest
    case .snapshot(let r): r.digest
    }
  }
  package var key: [String] {
    func identity<T>(_ kind: String, _ r: ExchangeRef<T>) -> [String] { [kind, r.issuer.uuidString.lowercased(), r.revision.uuidString.lowercased()] }
    switch self {
    case .drawing(let r): return identity("drawing", r)
    case .photo(let r): return identity("photo", r)
    case .input(let r): return identity("input", r)
    case .assessment(let r): return identity("assessment", r)
    case .ranking(let r): return identity("ranking", r)
    case .receipt(let r): return ["receipt", r.engine.uuidString.lowercased(), r.job.uuidString.lowercased()]
    case .snapshot(let r): return ["snapshot", r.archive.uuidString.lowercased(), r.run.uuidString.lowercased() + "/" + String(r.sequence)]
    }
  }
}
package struct PortraitExchangeMetadata: Codable, Equatable, Sendable {
  package let reference: PortraitExchangeReference
  package var title: String?
  package var retentionReasons: [String]
  package var tombstoned: Bool
  package init(reference: PortraitExchangeReference, title: String? = nil, retentionReasons: [String] = [], tombstoned: Bool = false) {
    self.reference = reference; self.title = title; self.retentionReasons = retentionReasons; self.tombstoned = tombstoned
  }
}
package struct PortraitExchangePublicationReceipt: Sendable {
  package let transactionID: UUID
  package let indexDigest: ExchangeDigest
  package let wasAlreadyPublished: Bool
}
package enum PortraitExchangeCatalogError: Error {
  case missing(PortraitExchangeReference), digestConflict(PortraitExchangeReference, existing: String)
  case preservedConflict(URL), invalidPublication(String)
  case unsupportedExternalOwner(String), missingExternalOwner(String)
}
package enum PortraitExchangeCatalogBoundary: String, CaseIterable {
  case beforeSQLPublication, beforeSQLCommit, afterSQLCommit, afterSQLPublication
  case beforeRestorePreservation, afterRestorePreservation, beforeRestoreSelection, afterRestoreSelection
}
struct PortraitExchangeLink: Codable {
  let source: PortraitExchangeReference
  let target: PortraitExchangeReference
  let relation: String
}
struct PortraitExchangePublication: Codable {
  let version: Int
  let transactionID: UUID
  let indexDigest: ExchangeDigest
  let packageDigest: ExchangeDigest
  let records: [PortraitExchangeReference]
  let links: [PortraitExchangeLink]
  let metadata: [PortraitExchangeMetadata]
}

/// Internal storage foundation. Common authoring/browsing API cutover belongs to DX-05.
/// A caller confines this synchronous facade and its connection to one actor.
package final class PortraitExchangeCatalog {
  package let database: PortraitLibraryDatabase
  package let storage: PortraitExchangeStorage
  package var injectFault: ((PortraitExchangeCatalogBoundary) throws -> Void)?
  package init(database: PortraitLibraryDatabase,
    storageFault: @escaping (PortraitExchangeStorageFault) throws -> Void = { _ in }) throws {
    guard let lease = database.writerLease else { throw PortraitLibraryError.database("Exchange publication requires the library writer") }
    try database.assertSelectedFile()
    self.database = database
    storage = try PortraitExchangeStorage(root: lease.canonicalRootURL, lease: lease, fault: storageFault)
    try database.integrityCheck()
    if try storage.readMetadata(name: "exchange-authority.json") == nil {
      try storage.durableMetadataWrite(PortraitExchangeCatalogSelection.markerBytes, name: "exchange-authority.json")
    }
    try database.execute(Self.schema)
    try recover()
  }

  package func publish(_ admitted: ValidatedExchangePackage, metadata: [PortraitExchangeMetadata] = [], transactionID: UUID = UUID()) throws -> PortraitExchangePublicationReceipt {
    try database.assertSelectedFile()
    guard admitted.integrityVerified else { throw PortraitExchangeCatalogError.invalidPublication("Unverified exchange") }
    let digest = ExchangeDigest.hash(admitted.index.originalJSON)
    // Exact retry returns the original publication identity, even after an uncertain COMMIT response.
    let packageDigest = Self.inventoryDigest(admitted.files.entries.values.map { .init(path: $0.path, digest: $0.digest, byteLength: $0.byteLength) })
    if let prior = try publishedTransaction(packageDigest) {
      try verifyPublished(prior)
      return .init(transactionID: prior, indexDigest: digest, wasAlreadyPublished: true)
    }
    let records = try references(admitted)
    guard Set(metadata.map(\.reference)).count == metadata.count,
      metadata.allSatisfy({ records.contains($0.reference) }) else {
      throw PortraitExchangeCatalogError.invalidPublication("Metadata must explicitly target unique included exact references")
    }
    let intent = PortraitExchangePublication(version: 1, transactionID: transactionID, indexDigest: digest,
      packageDigest: packageDigest, records: records, links: try links(admitted), metadata: metadata)
    let staging = try storage.stage(files: admitted.files, transactionID: transactionID, intent: JSONEncoder().encode(intent))
    do { try checkCollisions(intent) }
    catch is PortraitExchangeCatalogError { let preserved = try storage.preserveConflict(transactionID: transactionID); throw PortraitExchangeCatalogError.preservedConflict(preserved) }
    try installAndPublish(staging, intent: intent)
    return .init(transactionID: transactionID, indexDigest: digest, wasAlreadyPublished: false)
  }

  /// Recovery never guesses from geometry or filesystem names. A complete durable
  /// intent either has its exact SQL transaction, can finish, or remains inspectable.
  package func recover() throws {
    try database.assertSelectedFile()
    for staging in try storage.pendingTransactions() {
      let intent = try JSONDecoder().decode(PortraitExchangePublication.self, from: staging.intent)
      guard intent.version == 1, intent.transactionID == staging.transactionID else {
        throw PortraitExchangeCatalogError.invalidPublication("Journal transaction identity")
      }
      if let prior = try publishedTransaction(intent.packageDigest) {
        try verifyPublished(prior)
        try storage.finish(transactionID: staging.transactionID)
      } else {
        do { try checkCollisions(intent) }
        catch is PortraitExchangeCatalogError { _ = try storage.preserveConflict(transactionID: staging.transactionID); continue }
        try installAndPublish(staging, intent: intent)
      }
    }
  }

  package func record(_ reference: PortraitExchangeReference, maximumBytes: Int = ExchangeJSON.maximumRecordBytes) throws -> Data {
    let digest = try lookup(reference)
    guard let length = try database.scalar("SELECT byte_length FROM dx_object WHERE digest=?", [digest]),
      let size = UInt64(length), maximumBytes > 0, size <= UInt64(maximumBytes) else {
      throw PortraitExchangeCatalogError.invalidPublication("Record exceeds materialization bound")
    }
    return try storage.readObject(digest: reference.digest, byteLength: size, maximumBytes: maximumBytes)
  }
  @discardableResult
  package func lookup(_ reference: PortraitExchangeReference) throws -> String {
    guard let digest = try database.scalar("SELECT digest FROM dx_record WHERE kind=? AND namespace=? AND identity=?", reference.key.map(Optional.some)) else {
      throw PortraitExchangeCatalogError.missing(reference)
    }
    guard digest == reference.digest.description else { throw PortraitExchangeCatalogError.digestConflict(reference, existing: digest) }
    return digest
  }
  package func metadata(_ reference: PortraitExchangeReference) throws -> PortraitExchangeMetadata? {
    _ = try lookup(reference)
    guard let raw = try database.scalar("SELECT payload FROM dx_metadata WHERE kind=? AND namespace=? AND identity=?", reference.key.map(Optional.some)) else { return nil }
    let value = try JSONDecoder().decode(PortraitExchangeMetadata.self, from: Data(raw.utf8))
    guard value.reference == reference else { throw PortraitExchangeCatalogError.invalidPublication("Mutable metadata contradicts its exact selector") }
    return value
  }
  package func updateMetadata(_ metadata: PortraitExchangeMetadata) throws {
    try database.assertSelectedFile()
    _ = try lookup(metadata.reference)
    try database.transaction { try writeMetadata(metadata); try database.bumpRevision() }
  }
  package func rebuildDerivedRows() throws {
    try database.transaction { try rebuildDerivedRowsInsideTransaction() }
  }
  private func rebuildDerivedRowsInsideTransaction() throws {
    try database.execute("DELETE FROM dx_summary")
    try database.execute("INSERT INTO dx_summary(kind,namespace,identity,digest) SELECT kind,namespace,identity,digest FROM dx_record")
  }
  private func writeMetadata(_ value: PortraitExchangeMetadata) throws {
    let payload = String(decoding: try JSONEncoder().encode(value), as: UTF8.self)
    try database.execute("INSERT INTO dx_metadata(kind,namespace,identity,digest,payload) VALUES(?,?,?,?,?) ON CONFLICT(kind,namespace,identity) DO UPDATE SET payload=excluded.payload", value.reference.key.map(Optional.some) + [value.reference.digest.description, payload])
  }
  private func publishedTransaction(_ package: ExchangeDigest) throws -> UUID? {
    guard let value = try database.scalar("SELECT id FROM dx_transaction WHERE package_digest=?", [package.description]) else { return nil }
    guard let id = UUID(uuidString: value) else { throw PortraitExchangeCatalogError.invalidPublication("Stored transaction identity") }
    return id
  }
  /// Metadata-only exact path mapping; no blob probing or media materialization.
  package func publicationInventory(transactionID: UUID) throws -> [PortraitExchangeStorageEntry] {
    try verifyPublished(transactionID, verifyObjects: false)
  }
  @discardableResult
  private func verifyPublished(_ transaction: UUID, verifyObjects: Bool = true) throws -> [PortraitExchangeStorageEntry] {
    let id = transaction.uuidString.lowercased()
    guard let row = try database.rows("SELECT index_digest,package_digest,intent FROM dx_transaction WHERE id=?",[id]).first,
      let index = row[0],let package = row[1],let rawIntent = row[2],rawIntent.utf8.count <= PortraitExchangeStorage.maximumPublicationIntentBytes else {
      throw PortraitExchangeCatalogError.invalidPublication("Publication identity missing")
    }
    let intent = try JSONDecoder().decode(PortraitExchangePublication.self,from:Data(rawIntent.utf8))
    guard intent.version == 1,intent.transactionID == transaction,intent.indexDigest.description == index,intent.packageDigest.description == package else {
      throw PortraitExchangeCatalogError.invalidPublication("Publication identity contradicts frozen intent")
    }
    let entries = try database.rows("SELECT f.path,f.digest,o.byte_length FROM dx_tx_file f JOIN dx_object o ON o.digest=f.digest WHERE f.transaction_id=? ORDER BY f.path",[id]).map { row -> PortraitExchangeStorageEntry in
      guard let path = row[0],let hash = row[1],let raw = row[2],let length = UInt64(raw) else { throw PortraitExchangeCatalogError.invalidPublication("Publication file inventory invalid") }
      return .init(path:path,digest:try ExchangeDigest(hash),byteLength:length)
    }
    try PortraitExchangeStorage.validateInventory(entries)
    guard Self.inventoryDigest(entries) == intent.packageDigest,
      entries.first(where:{$0.path == "data/exchange.json"})?.digest == intent.indexDigest else {
      throw PortraitExchangeCatalogError.invalidPublication("Publication file inventory missing or divergent")
    }
    let digests = Set(entries.map { $0.digest.description })
    let selected = Set(try database.rows("SELECT digest FROM dx_tx_object WHERE transaction_id=?",[id]).compactMap{$0[0]})
    guard selected == digests else { throw PortraitExchangeCatalogError.invalidPublication("Publication object and path inventories differ") }
    let bindings = try database.rows("SELECT r.kind,r.namespace,r.identity,r.digest FROM dx_tx_record t JOIN dx_record r ON r.kind=t.kind AND r.namespace=t.namespace AND r.identity=t.identity WHERE t.transaction_id=?",[id])
    let actualBindings = Set(bindings.map { $0.map { $0 ?? "" }.joined(separator:"\0") })
    let expectedBindings = Set(intent.records.map { ($0.key + [$0.digest.description]).joined(separator:"\0") })
    guard actualBindings == expectedBindings else { throw PortraitExchangeCatalogError.invalidPublication("Publication exact-reference inventory differs") }
    if verifyObjects {
      var verified = Set<ExchangeDigest>()
      for entry in entries where verified.insert(entry.digest).inserted {
        try storage.verifyObject(digest:entry.digest,byteLength:entry.byteLength)
      }
    }
    return entries
  }
  private func checkCollisions(_ intent: PortraitExchangePublication) throws {
    for ref in intent.records {
      if ["drawing","photo","input","assessment","ranking"].contains(ref.key[0]),
        let existing = try database.rows("SELECT kind,digest FROM dx_record WHERE namespace=? AND identity=? AND kind IN ('drawing','photo','input','assessment','ranking')",[ref.key[1],ref.key[2]]).first,
        existing[0] != ref.key[0] || existing[1] != ref.digest.description {
        throw PortraitExchangeCatalogError.invalidPublication("Issuer/revision already identifies a different immutable record")
      }
      if let old = try database.scalar("SELECT digest FROM dx_record WHERE kind=? AND namespace=? AND identity=?", ref.key.map(Optional.some)), old != ref.digest.description {
        throw PortraitExchangeCatalogError.digestConflict(ref, existing: old)
      }
    }
    if let prior = try database.scalar("SELECT package_digest FROM dx_transaction WHERE id=?", [intent.transactionID.uuidString.lowercased()]), prior != intent.packageDigest.description {
      throw PortraitExchangeCatalogError.invalidPublication("Transaction ID already identifies different bytes")
    }
  }
  private func installAndPublish(_ staging: PortraitExchangeStaging, intent: PortraitExchangePublication) throws {
    let inventory = Dictionary(grouping: staging.entries, by: { $0.digest.description })
    guard Self.inventoryDigest(staging.entries) == intent.packageDigest, inventory[intent.indexDigest.description] != nil,
      intent.records.allSatisfy({ inventory[$0.digest.description] != nil }) else {
      throw PortraitExchangeCatalogError.invalidPublication("Journal reference outside immutable inventory")
    }
    try storage.installObjects(staging)
    try injectFault?(.beforeSQLPublication)
    try database.transaction {
      try checkCollisions(intent)
      let transaction = intent.transactionID.uuidString.lowercased()
      try database.execute("INSERT INTO dx_transaction(id,index_digest,package_digest,intent) VALUES(?,?,?,?)", [transaction,intent.indexDigest.description,intent.packageDigest.description,String(decoding:staging.intent,as:UTF8.self)])
      for entry in staging.entries {
        if let old = try database.scalar("SELECT byte_length FROM dx_object WHERE digest=?",[entry.digest.description]), old != String(entry.byteLength) { throw PortraitExchangeCatalogError.invalidPublication("Object size collision") }
        try database.execute("INSERT OR IGNORE INTO dx_object(digest,byte_length) VALUES(?,?)",[entry.digest.description,String(entry.byteLength)])
        try database.execute("INSERT OR IGNORE INTO dx_tx_object(transaction_id,digest) VALUES(?,?)",[transaction,entry.digest.description])
        try database.execute("INSERT INTO dx_tx_file(transaction_id,path,digest) VALUES(?,?,?)",[transaction,entry.path,entry.digest.description])
      }
      for ref in intent.records {
        try database.execute("INSERT OR IGNORE INTO dx_record(kind,namespace,identity,digest) VALUES(?,?,?,?)", ref.key.map(Optional.some) + [ref.digest.description])
        try database.execute("INSERT OR IGNORE INTO dx_tx_record(transaction_id,kind,namespace,identity) VALUES(?,?,?,?)",[transaction] + ref.key.map(Optional.some))
        try database.execute("INSERT OR IGNORE INTO dx_summary(kind,namespace,identity,digest) VALUES(?,?,?,?)",ref.key.map(Optional.some) + [ref.digest.description])
      }
      for link in intent.links {
        try database.execute("INSERT OR IGNORE INTO dx_link(source_kind,source_namespace,source_identity,target_kind,target_namespace,target_identity,relation) VALUES(?,?,?,?,?,?,?)",link.source.key.map(Optional.some) + link.target.key.map(Optional.some) + [link.relation])
      }
      for value in intent.metadata { try writeMetadata(value) }
      try database.bumpRevision()
      try injectFault?(.beforeSQLCommit)
    }
    try injectFault?(.afterSQLCommit)
    try injectFault?(.afterSQLPublication)
    try storage.finish(transactionID: staging.transactionID)
  }

  private static func inventoryDigest(_ entries: [PortraitExchangeStorageEntry]) -> ExchangeDigest {
    let bytes = entries.sorted { $0.path < $1.path }.map { $0.path + "\0" + $0.digest.description + "\0" + String($0.byteLength) + "\n" }.joined()
    return .hash(Data(bytes.utf8))
  }

  private func references(_ package: ValidatedExchangePackage) throws -> [PortraitExchangeReference] {
    // The admitted v1 closure has checked every canonical record path, including
    // unselected records. Unknown index majors grant preservation only.
    guard package.index.known != nil else { return [] }
    var result: [PortraitExchangeReference] = []
    for file in package.files.entries.values.sorted(by: { $0.path < $1.path }) {
      let parts = file.path.split(separator: "/").map(String.init)
      guard parts.first == "data", parts.count >= 4 else { continue }
      func uuid(_ text: String) throws -> UUID {
        guard let id = UUID(uuidString: text), id.uuidString.lowercased() == text else { throw PortraitExchangeCatalogError.invalidPublication("Noncanonical admitted identity") }; return id
      }
      switch parts[1] {
      case "drawings", "photos", "inputs":
        guard parts.count == 5 else { throw PortraitExchangeCatalogError.invalidPublication("Record path") }
        let issuer = try uuid(parts[2]), revision = try uuid(parts[3])
        switch parts[1] {
        case "drawings": result.append(.drawing(.init(issuer: issuer, revision: revision, digest: file.digest)))
        case "photos": result.append(.photo(.init(issuer: issuer, revision: revision, digest: file.digest)))
        default: result.append(.input(.init(issuer: issuer, revision: revision, digest: file.digest)))
        }
      case "assessments", "rankings":
        guard parts.count == 4, parts[3].hasSuffix(".json") else { throw PortraitExchangeCatalogError.invalidPublication("Record path") }
        let issuer = try uuid(parts[2]), revision = try uuid(String(parts[3].dropLast(5)))
        if parts[1] == "assessments" { result.append(.assessment(.init(issuer: issuer, revision: revision, digest: file.digest))) }
        else { result.append(.ranking(.init(issuer: issuer, revision: revision, digest: file.digest))) }
      case "jobs":
        guard parts.count == 5 else { throw PortraitExchangeCatalogError.invalidPublication("Receipt path") }
        result.append(.receipt(.init(handle: .init(engine: try uuid(parts[2]), job: try uuid(parts[3])), receiptDigest: file.digest)))
      case "attempts":
        guard parts.count == 6, let sequence = UInt64(parts[4]) else { throw PortraitExchangeCatalogError.invalidPublication("Snapshot path") }
        result.append(.snapshot(try .init(archive: uuid(parts[2]), run: uuid(parts[3]), sequence: sequence, digest: file.digest)))
      default: break
      }
    }
    return result
  }
  private func links(_ package: ValidatedExchangePackage) throws -> [PortraitExchangeLink] {
    var result: [PortraitExchangeLink] = []
    for (ref, value) in package.drawings {
      if case .materialized(let drawing) = value {
        if case .present(let parent) = drawing.drawing.parent { result.append(.init(source: .drawing(ref), target: .drawing(parent), relation: "parent")) }
        if case .present(let input) = drawing.drawing.input { result.append(.init(source: .drawing(ref), target: .input(input), relation: "input")) }
      }
    }
    let descriptors = Dictionary((package.index.known?.assets ?? []).map { ($0.asset.object, $0) }, uniquingKeysWith: { first, _ in first })
    for reference in try references(package) {
      if case .input(let ref) = reference {
        do {
          let input = try DrawingImageAdmission.input(ref, files: package.files, assetDescriptors: descriptors)
          result.append(.init(source: reference, target: .photo(input.photo), relation: "photo"))
        } catch DrawingExchangeError.unsupportedProfile { /* Inert original bytes remain preserved. */ }
      }
    }
    for (ref, value) in package.assessments {
      for target in value.targets {
        switch target {
        case .drawing(let drawing): result.append(.init(source: .assessment(ref), target: .drawing(drawing), relation: "target"))
        case .attempt(let attempt): result.append(.init(source: .assessment(ref), target: .snapshot(attempt), relation: "target"))
        case .rankingCapsule(let ranking): result.append(.init(source: .assessment(ref), target: .ranking(ranking), relation: "target"))
        case .asset, .opaque: break // Preserved in exact assessment bytes and transaction object inventory.
        }
      }
      for prior in value.supersedes { result.append(.init(source: .assessment(ref), target: .assessment(prior), relation: "supersedes")) }
    }
    for (ref, value) in package.receipts { result.append(.init(source: .receipt(ref), target: .drawing(value.drawing), relation: "drawing")) }
    for (ref, value) in package.attempts {
      result.append(.init(source: .snapshot(ref), target: .drawing(value.drawing), relation: "drawing"))
      result.append(.init(source: .snapshot(ref), target: .receipt(value.job), relation: "job"))
      if let previous = value.previous, ref.sequence > 1,
        let prior = try? SnapshotRef(archive: ref.archive, run: ref.run, sequence: ref.sequence - 1, digest: previous) {
        result.append(.init(source: .snapshot(ref), target: .snapshot(prior), relation: "previous"))
      }
    }
    return result
  }

  package func backupInventory() throws -> [PortraitExchangeStorageEntry] {
    var entries = try database.rows("SELECT digest,byte_length FROM dx_object ORDER BY digest").map { row -> PortraitExchangeStorageEntry in
      guard let digest = row[0], let rawLength = row[1], let length = UInt64(rawLength) else { throw PortraitExchangeCatalogError.invalidPublication("Object inventory") }
      return .init(path: "objects/sha256/" + digest, digest: try ExchangeDigest(digest), byteLength: length)
    }
    // The snapshot contains legacy metadata too. Preserve and verify its existing
    // immutable stores; never infer mutable retention from these files.
    for directory in ["assets", "records", "review-v1/assets"] {
      let root = storageRoot.appendingPathComponent(directory)
      var info = stat()
      if lstat(root.path, &info) != 0 { guard errno == ENOENT else { throw PortraitLibraryError.database("Legacy object directory unavailable") }; continue }
      guard info.st_mode & S_IFMT == S_IFDIR else { throw PortraitLibraryError.database("Legacy object directory is not a directory") }
      for file in try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.fileSizeKey]) {
        let digest = try ExchangeDigest(file.lastPathComponent)
        var statValue = stat()
        guard lstat(file.path, &statValue) == 0, statValue.st_mode & S_IFMT == S_IFREG, statValue.st_size >= 0 else { throw PortraitLibraryError.database("Invalid legacy immutable object") }
        entries.append(.init(path: directory + "/" + file.lastPathComponent, digest: digest, byteLength: UInt64(statValue.st_size)))
      }
    }
    return entries
  }
  private var storageRoot: URL { database.writerLease!.canonicalRootURL }
  private static let schema = """
  CREATE TABLE IF NOT EXISTS dx_object(digest TEXT PRIMARY KEY,byte_length TEXT NOT NULL);
  CREATE TABLE IF NOT EXISTS dx_record(kind TEXT NOT NULL,namespace TEXT NOT NULL,identity TEXT NOT NULL,digest TEXT NOT NULL REFERENCES dx_object(digest),PRIMARY KEY(kind,namespace,identity),UNIQUE(kind,namespace,identity,digest));
  CREATE UNIQUE INDEX IF NOT EXISTS dx_shared_identity ON dx_record(namespace,identity) WHERE kind IN ('drawing','photo','input','assessment','ranking');
  CREATE TABLE IF NOT EXISTS dx_transaction(id TEXT PRIMARY KEY,index_digest TEXT NOT NULL,package_digest TEXT NOT NULL UNIQUE,intent TEXT NOT NULL);
  CREATE TABLE IF NOT EXISTS dx_tx_object(transaction_id TEXT NOT NULL REFERENCES dx_transaction(id),digest TEXT NOT NULL REFERENCES dx_object(digest),PRIMARY KEY(transaction_id,digest));
  CREATE TABLE IF NOT EXISTS dx_tx_file(transaction_id TEXT NOT NULL,path TEXT NOT NULL,digest TEXT NOT NULL,PRIMARY KEY(transaction_id,path),FOREIGN KEY(transaction_id,digest) REFERENCES dx_tx_object(transaction_id,digest));
  CREATE TABLE IF NOT EXISTS dx_tx_record(transaction_id TEXT NOT NULL REFERENCES dx_transaction(id),kind TEXT NOT NULL,namespace TEXT NOT NULL,identity TEXT NOT NULL,PRIMARY KEY(transaction_id,kind,namespace,identity),FOREIGN KEY(kind,namespace,identity) REFERENCES dx_record(kind,namespace,identity));
  CREATE TABLE IF NOT EXISTS dx_link(source_kind TEXT NOT NULL,source_namespace TEXT NOT NULL,source_identity TEXT NOT NULL,target_kind TEXT NOT NULL,target_namespace TEXT NOT NULL,target_identity TEXT NOT NULL,relation TEXT NOT NULL,PRIMARY KEY(source_kind,source_namespace,source_identity,target_kind,target_namespace,target_identity,relation),FOREIGN KEY(source_kind,source_namespace,source_identity) REFERENCES dx_record(kind,namespace,identity),FOREIGN KEY(target_kind,target_namespace,target_identity) REFERENCES dx_record(kind,namespace,identity));
  CREATE TABLE IF NOT EXISTS dx_metadata(kind TEXT NOT NULL,namespace TEXT NOT NULL,identity TEXT NOT NULL,digest TEXT NOT NULL,payload TEXT NOT NULL,PRIMARY KEY(kind,namespace,identity),FOREIGN KEY(kind,namespace,identity,digest) REFERENCES dx_record(kind,namespace,identity,digest));
  CREATE TABLE IF NOT EXISTS dx_summary(kind TEXT NOT NULL,namespace TEXT NOT NULL,identity TEXT NOT NULL,digest TEXT NOT NULL,PRIMARY KEY(kind,namespace,identity));
  """
}

extension PortraitCandidateStore {
  package func exchangeCatalog() throws -> PortraitExchangeCatalog {
    let db = try libraryDatabase() // Always recheck root, selected SQL inode and marker.
    if let cachedExchangeCatalog {
      guard cachedExchangeCatalog.database === db else { throw PortraitExchangeCatalogError.invalidPublication("Cached catalog belongs to another connection") }
      return cachedExchangeCatalog
    }
    try validateExchangeCatalogInitialization(db)
    defer { refreshCommittedLibraryGeneration() }
    let catalog = try PortraitExchangeCatalog(database: db)
    cachedExchangeCatalog = catalog
    return catalog
  }
}

extension PortraitExchangeCatalog {
  /// Explicit restore owns the lease without opening the selected catalog. Existing
  /// writable connections must have ended; flock refuses otherwise. Old SQL bytes
  /// and uncertain incoming journals remain inspectable, never replayed by restore.
  package static func restore(root: URL, generationID: UUID, fault: (PortraitExchangeCatalogBoundary) throws -> Void = { _ in }) throws {
    let lease = try PortraitLibraryWriterLease(root: root)
    try PortraitExchangeCatalogSelection.validate(root:lease.canonicalRootURL,database:lease.canonicalRootURL.appendingPathComponent("library-v1.sqlite"),requireDatabase:false)
    let storage = try PortraitExchangeStorage(root: root, lease: lease)
    let backups = PortraitExchangeMetadataBackup(storage: storage)
    let plan = try backups.prepareRestore(generationID: generationID) { url in
      try PortraitLibraryDatabase(url: url, readOnly: true).integrityCheck()
    }
    // Persist selected recovery intent before installing or selecting any bytes,
    // including when restoring into a fresh root with no current SQL file.
    try storage.durableMetadataWrite(PortraitExchangeCatalogSelection.markerBytes,name:"exchange-authority.json")
    try backups.installRestoredObjects(plan)
    for stage in try storage.pendingTransactions() { _ = try storage.preserveConflict(transactionID: stage.transactionID) }
    let destination = lease.canonicalRootURL.appendingPathComponent("library-v1.sqlite")
    try fault(.beforeRestorePreservation)
    var info = stat()
    if lstat(destination.path, &info) == 0 {
      guard info.st_mode & S_IFMT == S_IFREG else { throw PortraitLibraryError.database("Selected catalog is not a regular file") }
      try preserveDatabase(destination, storage: storage)
    } else if errno != ENOENT { throw PortraitLibraryError.database("Selected catalog cannot be inspected") }
    try fault(.afterRestorePreservation)
    do {
      let restored = try PortraitLibraryDatabase(url:plan.databaseURL,readOnly:true)
      try validateSelectedBackupReferences(database:restored,storage:storage,inventory:plan.objects)
      try validateExternalQuarantine(database:restored,storage:storage,libraryRoot:lease.canonicalRootURL)
    }
    try fault(.beforeRestoreSelection)
    // One atomic replacement: an interruption before this point keeps the old
    // selected catalog, and an interruption after selects the verified generation.
    guard Darwin.rename(plan.databaseURL.path, destination.path) == 0 else {
      throw PortraitLibraryError.database("Cannot select restored catalog; prior selected bytes retained")
    }
    try storage.sync(storage.rootFD, "select restored catalog")
    let restoreParent = Darwin.open(plan.rootURL.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
    guard restoreParent >= 0 else { throw PortraitLibraryError.database("Restore directory unavailable") }
    defer { Darwin.close(restoreParent) }
    try storage.sync(restoreParent, "restore source rename")
    try fault(.afterRestoreSelection)
  }
  private static func preserveDatabase(_ source: URL, storage: PortraitExchangeStorage) throws {
    let input = Darwin.open(source.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
    guard input >= 0 else { throw PortraitLibraryError.database("Cannot open prior catalog") }
    defer { Darwin.close(input) }
    var before = stat()
    guard fstat(input, &before) == 0, before.st_mode & S_IFMT == S_IFREG, before.st_size >= 0 else { throw PortraitLibraryError.database("Invalid prior catalog") }
    let name = "library-prior-" + UUID().uuidString.lowercased() + ".sqlite"
    let output = openat(storage.rootFD, name, O_CREAT | O_EXCL | O_WRONLY | O_NOFOLLOW | O_CLOEXEC, 0o600)
    guard output >= 0 else { throw PortraitLibraryError.database("Cannot preserve prior catalog") }
    defer { Darwin.close(output) }
    var buffer = [UInt8](repeating: 0, count: 1024 * 1024), copied: Int64 = 0, hash = SHA256()
    while true {
      let count = Darwin.read(input, &buffer, buffer.count)
      guard count >= 0 else { throw PortraitLibraryError.database("Prior catalog read failed") }
      if count == 0 { break }
      copied += Int64(count)
      guard copied <= before.st_size else { throw PortraitLibraryError.database("Prior catalog changed") }
      hash.update(data: Data(buffer.prefix(count)))
      try buffer.withUnsafeBytes { bytes in
        var offset = 0
        while offset < count {
          let n = Darwin.write(output, bytes.baseAddress!.advanced(by: offset), count - offset)
          guard n > 0 else { throw PortraitLibraryError.database("Prior catalog copy failed") }; offset += n
        }
      }
    }
    var after = stat()
    guard fstat(input, &after) == 0, copied == before.st_size, before.st_size == after.st_size,
      before.st_ino == after.st_ino, before.st_mtimespec.tv_sec == after.st_mtimespec.tv_sec,
      before.st_mtimespec.tv_nsec == after.st_mtimespec.tv_nsec,
      before.st_ctimespec.tv_sec == after.st_ctimespec.tv_sec, before.st_ctimespec.tv_nsec == after.st_ctimespec.tv_nsec else { throw PortraitLibraryError.database("Prior catalog changed during preservation") }
    try storage.sync(output, name)
    let digest = try ExchangeDigest(hash.finalize().map { String(format: "%02x", $0) }.joined())
    try storage.verifyFile(directory: storage.rootFD, path: name, digest: digest, size: UInt64(copied))
    try storage.sync(storage.rootFD, name)
  }

}
extension PortraitCandidateStore {
  package func publishExchange(_ admitted: ValidatedExchangePackage, metadata: [PortraitExchangeMetadata] = []) throws -> PortraitExchangePublicationReceipt {
    defer { refreshCommittedLibraryGeneration() }
    return try exchangeCatalog().publish(admitted, metadata: metadata)
  }
  package func updateExchangeMetadata(_ metadata: PortraitExchangeMetadata) throws {
    defer { refreshCommittedLibraryGeneration() }
    try exchangeCatalog().updateMetadata(metadata)
  }
  package func createExchangeMetadataBackup(generationID: UUID = UUID()) throws -> PortraitExchangeBackupGeneration {
    let catalog = try exchangeCatalog(), db = catalog.database
    let inventory = try catalog.backupInventory()
    try PortraitExchangeCatalog.validateSelectedBackupReferences(database:db,storage:catalog.storage,inventory:inventory)
    try PortraitExchangeCatalog.validateExternalQuarantine(database:db,storage:catalog.storage,libraryRoot:catalog.storage.lease.canonicalRootURL)
    return try PortraitExchangeMetadataBackup(storage: catalog.storage).create(generationID: generationID,
      objects: inventory, onlineBackup: { try db.backup(to: $0) }, validate: { try PortraitLibraryDatabase(url: $0, readOnly: true).integrityCheck() })
  }
}

extension PortraitExchangeCatalog {
  /// Validate selected local references before the filesystem owner streams every
  /// inventoried byte. Only bounded review metadata is decoded, never full artwork,
  /// image packages or an external physical evidence archive.
  static func validateSelectedBackupReferences(database: PortraitLibraryDatabase, storage: PortraitExchangeStorage, inventory: [PortraitExchangeStorageEntry]) throws {
    let paths = Set(inventory.map(\.path))
    func require(_ folder: String, _ digest: String) throws {
      _ = try ExchangeDigest(digest)
      guard paths.contains(folder + "/" + digest) else { throw PortraitExchangeStorageError.missingObject(folder + "/" + digest) }
    }
    for row in try database.rows("SELECT source_hash FROM photo WHERE deleted=0") { if let hash = row[0] { try require("assets",hash) } }
    for row in try database.rows("SELECT candidate_record,metadata_record,historical_record,raster_hash FROM drawing WHERE deleted=0") {
      for index in [0,1,2] { if let hash = row[index] { try require("records",hash) } }
      if let hash = row[3] { try require("assets",hash) }
    }
    for row in try database.rows("SELECT record_hash FROM label UNION SELECT record_hash FROM withdrawn_label") { if let hash = row[0] { try require("records",hash) } }
    for row in try database.rows("SELECT reference FROM generic_drawing") {
      let ref = try database.decode(SavedDrawingRecordReference.self,row[0])
      guard let hash = ref.recordSHA256 else { throw PortraitExchangeCatalogError.invalidPublication("Generic drawing record missing") }
      try require("records",hash)
    }
    for row in try database.rows("SELECT digest FROM dx_object") { if let hash = row[0] { try require("objects/sha256",hash) } }
    for row in try database.rows("SELECT key,value FROM state WHERE key LIKE 'review.%'") {
      guard let key = row[0], let value = row[1] else { throw PortraitExchangeCatalogError.invalidPublication("Review selector missing") }
      if (try? ExchangeDigest(value)) != nil { try require("review-v1/assets",value) }
      if key.hasPrefix("review.package.") {
        let ref = try JSONDecoder().decode(PortraitReviewPackageReference.self,from:Data(value.utf8))
        try require("review-v1/assets",ref.packageSHA256)
      }
      if key.hasPrefix("review.comparison.") {
        try require("review-v1/assets",value)
        let bytes = try storage.boundedRead(directory:storage.rootFD,path:"review-v1/assets/" + value,maximumBytes:ExchangeJSON.maximumRecordBytes)
        guard ExchangeDigest.hash(bytes).description == value else { throw PortraitExchangeStorageError.corruptObject(value) }
        let comparison = try JSONDecoder().decode(PortraitReviewComparison.self,from:bytes)
        for ref in [comparison.a,comparison.b] {
          try require("review-v1/assets",ref.packageSHA256)
          try require("review-v1/assets",ref.displayPreviewSHA256)
        }
      }
    }
  }

  static func validateExternalQuarantine(database: PortraitLibraryDatabase, storage: PortraitExchangeStorage, libraryRoot: URL) throws {
    let rows = try database.rows("SELECT id,reason,manifest FROM quarantine")
    guard !rows.isEmpty else { return }
    guard let generation = try database.generation.evidenceSHA256 else { throw PortraitExchangeCatalogError.unsupportedExternalOwner("Quarantine lacks selected evidence generation") }
    let selectedGeneration = try ExchangeDigest(generation)
    let root = libraryRoot.deletingLastPathComponent().appendingPathComponent("PortraitQuarantine")
    let external = Darwin.open(root.path,O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
    guard external >= 0 else { throw PortraitExchangeCatalogError.missingExternalOwner(root.path) }
    defer { Darwin.close(external) }
    for row in rows {
      guard let id = row[0], !id.isEmpty, id.utf8.count <= 255, !id.contains("/"), id != ".", id != "..", let payload = row[2], payload.utf8.count <= ExchangeJSON.maximumRecordBytes else {
        throw PortraitExchangeCatalogError.unsupportedExternalOwner("Invalid or oversized selected quarantine identity")
      }
      let folder = openat(external,id,O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
      guard folder >= 0 else { throw PortraitExchangeCatalogError.missingExternalOwner(id) }
      defer { Darwin.close(folder) }
      let payloadBytes = Data(payload.utf8), payloadDigest = ExchangeDigest.hash(payloadBytes)
      try storage.verifyFile(directory:folder,path:payloadDigest.description + ".json",digest:payloadDigest,size:UInt64(payloadBytes.count))
      let manifests = try storage.names(folder).filter { $0.hasSuffix(".manifest.json") }
      guard manifests.count <= 100_000 else { throw PortraitExchangeStorageError.resourceLimit("External quarantine manifest count exceeds 100000") }
      var found = false
      for name in manifests {
        let bytes = try storage.boundedRead(directory:folder,path:name,maximumBytes:ExchangeJSON.maximumRecordBytes)
        let digest = try ExchangeDigest(String(name.prefix(64)))
        guard ExchangeDigest.hash(bytes) == digest else { throw PortraitExchangeStorageError.corruptObject(name) }
        let manifest = try ExchangeJSON.validate(bytes)
        guard manifest["id"] as? String == id, manifest["sourceGeneration"] as? String == generation,
          manifest["payloadSHA256"] as? String == payloadDigest.description, manifest["reason"] as? String == row[1] else { continue }
        guard let originals = manifest["originalFiles"] as? [[String:Any]] else { throw PortraitExchangeCatalogError.unsupportedExternalOwner("Quarantine original inventory unavailable") }
        guard originals.count <= 100_000 else { throw PortraitExchangeStorageError.resourceLimit("External original inventory exceeds 100000") }
        var includesSelectedManifest = false
        for original in originals {
          if original["availability"] as? String == "missing", original["file"] == nil { continue }
          guard let file = original["file"] as? String, !file.isEmpty, !file.contains("/"), file != ".", file != "..",
            let hash = original["sha256"] as? String, let count = original["byteCount"] as? Int, count >= 0 else {
            throw PortraitExchangeCatalogError.unsupportedExternalOwner("Unknown quarantine original reference")
          }
          let expected = try ExchangeDigest(hash)
          // 1MiB streaming buffers, exact length/hash/fingerprint on one nofollow
          // descriptor; an original can be the complete external raw archive.
          try storage.verifyFile(directory:folder,path:file,digest:expected,size:UInt64(count))
          if expected == selectedGeneration { includesSelectedManifest = true }
        }
        guard includesSelectedManifest else { throw PortraitExchangeCatalogError.missingExternalOwner("Selected quarantine evidence manifest") }
        found = true
      }
      guard found else { throw PortraitExchangeCatalogError.missingExternalOwner("No exact selected quarantine manifest for " + id) }
    }
  }
}
