import Darwin
import CryptoKit
import Foundation
import PortraitCore

/// A fixed marker distinguishes a lost selected catalog from a new Library.
/// It carries no reconstructible replacement for mutable metadata.
package enum LibraryExchangeCatalogSelection {
  private struct Marker: Codable, Equatable { let version: Int; let catalog: String }
  package static func markerPresent(root: URL) -> Bool {
    var info = stat()
    return lstat(root.path + "/drawing-authority.json", &info) == 0 || errno != ENOENT
  }
  package static let markerBytes = Data("{\"version\":1,\"catalog\":\"drawing-library.sqlite\"}".utf8)
  @discardableResult
  package static func validate(root: URL, database: URL, requireDatabase: Bool = true) throws -> Bool {
    let markerPath = root.path + "/drawing-authority.json"
    var info = stat()
    if lstat(markerPath, &info) != 0 {
      guard errno == ENOENT else { throw DrawingLibraryDatabaseError.database("Exchange authority marker is unavailable") }
      return false
    }
    guard info.st_mode & S_IFMT == S_IFREG, info.st_nlink == 1, info.st_size > 0, info.st_size <= 4096 else {
      throw DrawingLibraryDatabaseError.database("Exchange authority marker is not a bounded private file")
    }
    let fd = Darwin.open(markerPath, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
    guard fd >= 0 else { throw DrawingLibraryDatabaseError.database("Exchange authority marker cannot be opened") }
    defer { Darwin.close(fd) }
    var opened = stat()
    guard fstat(fd, &opened) == 0, opened.st_dev == info.st_dev, opened.st_ino == info.st_ino else {
      throw DrawingLibraryDatabaseError.database("Exchange authority marker changed")
    }
    var bytes = [UInt8](repeating: 0, count: 4097)
    let count = Darwin.read(fd, &bytes, bytes.count)
    guard count > 0, count <= 4096,
      let object = try? ExchangeJSON.validate(Data(bytes.prefix(count)), maximumBytes: 4096),
      Set(object.keys) == Set(["version", "catalog"]),
      let value = try? JSONDecoder().decode(Marker.self, from: Data(bytes.prefix(count))),
      value == Marker(version: 1, catalog: "drawing-library.sqlite"), database.lastPathComponent == value.catalog else {
      throw DrawingLibraryDatabaseError.database("Unknown or corrupt exchange authority marker; explicit recovery required")
    }
    if !requireDatabase { return true }
    var catalog = stat()
    guard lstat(database.path, &catalog) == 0, catalog.st_mode & S_IFMT == S_IFREG else {
      throw DrawingLibraryDatabaseError.database("Selected exchange catalog is missing; select a verified metadata backup generation")
    }
    return true
  }
}

package enum LibraryExchangeReference: Hashable, Codable, Sendable {
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
package struct LibraryExchangeMetadata: Codable, Equatable, Sendable {
  package let reference: LibraryExchangeReference
  package var title: String?
  package var retentionReasons: [String]
  package var tombstoned: Bool
  package init(reference: LibraryExchangeReference, title: String? = nil, retentionReasons: [String] = [], tombstoned: Bool = false) {
    self.reference = reference; self.title = title; self.retentionReasons = retentionReasons; self.tombstoned = tombstoned
  }
}
package struct LibraryExchangePublicationReceipt: Sendable {
  package let transactionID: UUID
  package let indexDigest: ExchangeDigest
  package let wasAlreadyPublished: Bool
}
package enum LibraryExchangeCatalogError: Error {
  case missing(LibraryExchangeReference), digestConflict(LibraryExchangeReference, existing: String)
  case preservedConflict(URL), invalidPublication(String)
  case unsupportedExternalOwner(String), missingExternalOwner(String)
}
package enum LibraryExchangeCatalogBoundary: String, CaseIterable {
  case beforeSQLPublication, beforeSQLCommit, afterSQLCommit, afterSQLPublication
  case beforeRestorePreservation, afterRestorePreservation, beforeRestoreSelection, afterRestoreSelection
}
struct LibraryExchangeLink: Codable {
  let source: LibraryExchangeReference
  let target: LibraryExchangeReference
  let relation: String
}
struct LibraryExchangePublication: Codable {
  let version: Int
  let transactionID: UUID
  let indexDigest: ExchangeDigest
  let packageDigest: ExchangeDigest
  let records: [LibraryExchangeReference]
  let links: [LibraryExchangeLink]
  let metadata: [LibraryExchangeMetadata]
  let attachments: [DrawingLibraryPublicationAttachment]
  let domainCommit: DrawingLibraryDomainCommit?
  let resultHeader: DrawingLibraryResultHeader?
  var sourceSummaries: [DrawingLibrarySourceSummary]? = nil
}

/// Internal transactional publication foundation for the concrete Library actor.
/// A caller confines this synchronous facade and its connection to one actor.
package final class LibraryExchangeCatalog {
  package let database: DrawingLibraryDatabase
  package let storage: LibraryExchangeStorage
  package var injectFault: ((LibraryExchangeCatalogBoundary) throws -> Void)?
  package init(database: DrawingLibraryDatabase,
    storageFault: @escaping (LibraryExchangeStorageFault) throws -> Void = { _ in }) throws {
    guard let lease = database.writerLease else { throw DrawingLibraryDatabaseError.database("Exchange publication requires the library writer") }
    try database.assertSelectedFile()
    self.database = database
    storage = try LibraryExchangeStorage(root: lease.canonicalRootURL, lease: lease, fault: storageFault)
    try database.integrityCheck()
    if try storage.readMetadata(name: "drawing-authority.json") == nil {
      try storage.durableMetadataWrite(LibraryExchangeCatalogSelection.markerBytes, name: "drawing-authority.json")
    }
    try database.execute(Self.schema)
    try recover()
  }

  package func publish(_ admitted: ValidatedExchangePackage, metadata: [LibraryExchangeMetadata] = [], transactionID: UUID = UUID(), attachments: [DrawingLibraryPublicationAttachment] = [], domainCommit: DrawingLibraryDomainCommit? = nil) throws -> LibraryExchangePublicationReceipt {
    try database.assertSelectedFile()
    guard admitted.integrityVerified else { throw LibraryExchangeCatalogError.invalidPublication("Unverified exchange") }
    let digest = ExchangeDigest.hash(admitted.index.originalJSON)
    if let commit=domainCommit,let prior=try domainReceipt(commit.intent,request:commit.request) {
      try verifyPublished(prior)
      return .init(transactionID:prior,indexDigest:digest,wasAlreadyPublished:true)
    }
    // Exact retry returns the original publication identity, even after an uncertain COMMIT response.
    let packageDigest = Self.inventoryDigest(admitted.files.entries.values.map { .init(path: $0.path, digest: $0.digest, byteLength: $0.byteLength) })
    if domainCommit == nil, attachments.isEmpty, let prior = try publishedTransaction(packageDigest) {
      try verifyPublished(prior)
      return .init(transactionID: prior, indexDigest: digest, wasAlreadyPublished: true)
    }
    let resultHeader = try DrawingLibraryResultHeader(admitted)
    let records = try references(admitted)
    guard Set(metadata.map(\.reference)).count == metadata.count,
      metadata.allSatisfy({ records.contains($0.reference) }) else {
      throw LibraryExchangeCatalogError.invalidPublication("Metadata must explicitly target unique included exact references")
    }
    let included=Set(records)
    if let commit=domainCommit {
      try validateDomainBatch(commit.batch,included:included,objects:Set(admitted.files.entries.values.map(\.digest)))
      for retained in commit.retained {
        _ = try lookup(retained.metadata.reference)
        if let prior=try retentionIntent(retained.intent,requestDigest:retained.request),case .drawing(let ref)=retained.metadata.reference,prior != ref { throw DrawingLibraryError.staleSelection }
      }
    }
    let libraryIdentity=try database.scalar("SELECT value FROM state WHERE key='library_uuid'")
    for attachment in attachments {
      guard let summary=attachment.summary,included.contains(.drawing(summary.reference)),libraryIdentity == nil || libraryIdentity.flatMap(UUID.init(uuidString:))==attachment.libraryUUID else { throw DrawingLibraryError.staleSelection }
      if let prior=try retentionIntent(attachment.intent,requestDigest:attachment.requestDigest),prior != summary.reference { throw DrawingLibraryError.staleSelection }
    }
    let intent = LibraryExchangePublication(version: 1, transactionID: transactionID, indexDigest: digest,
      packageDigest: packageDigest, records: records, links: try links(admitted), metadata: metadata, attachments: attachments, domainCommit: domainCommit, resultHeader: resultHeader, sourceSummaries: try sourceSummaries(admitted, references: records))
    let staging = try storage.stage(files: admitted.files, transactionID: transactionID, intent: JSONEncoder().encode(intent))
    do { try checkCollisions(intent) }
    catch is LibraryExchangeCatalogError { let preserved = try storage.preserveConflict(transactionID: transactionID); throw LibraryExchangeCatalogError.preservedConflict(preserved) }
    try installAndPublish(staging, intent: intent)
    return .init(transactionID: transactionID, indexDigest: digest, wasAlreadyPublished: false)
  }

  /// Recovery never guesses from geometry or filesystem names. A complete durable
  /// intent either has its exact SQL transaction, can finish, or remains inspectable.
  package func recover() throws {
    try database.assertSelectedFile()
    for staging in try storage.pendingTransactions() {
      let intent = try JSONDecoder().decode(LibraryExchangePublication.self, from: staging.intent)
      guard intent.version == 1, intent.transactionID == staging.transactionID else {
        throw LibraryExchangeCatalogError.invalidPublication("Journal transaction identity")
      }
      if let commit=intent.domainCommit,let prior=try domainReceipt(commit.intent,request:commit.request) {
        try verifyPublished(prior)
        try storage.finish(transactionID:staging.transactionID)
      } else if try database.scalar("SELECT id FROM dx_transaction WHERE id=?",[intent.transactionID.uuidString.lowercased()]) != nil {
        let prior=intent.transactionID
        try verifyPublished(prior)
        try storage.finish(transactionID: staging.transactionID)
      } else {
        do { try checkCollisions(intent) }
        catch is LibraryExchangeCatalogError { _ = try storage.preserveConflict(transactionID: staging.transactionID); continue }
        try installAndPublish(staging, intent: intent)
      }
    }
  }

  package func record(_ reference: LibraryExchangeReference, maximumBytes: Int = ExchangeJSON.maximumRecordBytes) throws -> Data {
    let digest = try lookup(reference)
    guard let length = try database.scalar("SELECT byte_length FROM dx_object WHERE digest=?", [digest]),
      let size = UInt64(length), maximumBytes > 0, size <= UInt64(maximumBytes) else {
      throw LibraryExchangeCatalogError.invalidPublication("Record exceeds materialization bound")
    }
    return try storage.readObject(digest: reference.digest, byteLength: size, maximumBytes: maximumBytes)
  }
  @discardableResult
  package func lookup(_ reference: LibraryExchangeReference) throws -> String {
    guard let digest = try database.scalar("SELECT digest FROM dx_record WHERE kind=? AND namespace=? AND identity=?", reference.key.map(Optional.some)) else {
      throw LibraryExchangeCatalogError.missing(reference)
    }
    guard digest == reference.digest.description else { throw LibraryExchangeCatalogError.digestConflict(reference, existing: digest) }
    return digest
  }
  package func metadata(_ reference: LibraryExchangeReference) throws -> LibraryExchangeMetadata? {
    _ = try lookup(reference)
    guard let raw = try database.scalar("SELECT payload FROM dx_metadata WHERE kind=? AND namespace=? AND identity=?", reference.key.map(Optional.some)) else { return nil }
    let value = try JSONDecoder().decode(LibraryExchangeMetadata.self, from: Data(raw.utf8))
    guard value.reference == reference else { throw LibraryExchangeCatalogError.invalidPublication("Mutable metadata contradicts its exact selector") }
    return value
  }
  package func updateMetadata(_ metadata: LibraryExchangeMetadata) throws {
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
  package func writeMetadata(_ value: LibraryExchangeMetadata) throws {
    let payload = String(decoding: try JSONEncoder().encode(value), as: UTF8.self)
    guard payload.utf8.count<=128*1024 else { throw DrawingExchangeError.limit("Drawing metadata") }
    try database.execute("INSERT INTO dx_metadata(kind,namespace,identity,digest,payload,tombstoned) VALUES(?,?,?,?,?,?) ON CONFLICT(kind,namespace,identity) DO UPDATE SET payload=excluded.payload,tombstoned=excluded.tombstoned", value.reference.key.map(Optional.some) + [value.reference.digest.description, payload,value.tombstoned ? "1" : "0"])
  }
  private func publishedTransaction(_ package: ExchangeDigest) throws -> UUID? {
    guard let value = try database.scalar("SELECT id FROM dx_transaction WHERE package_digest=?", [package.description]) else { return nil }
    guard let id = UUID(uuidString: value) else { throw LibraryExchangeCatalogError.invalidPublication("Stored transaction identity") }
    return id
  }
  /// Metadata-only exact path mapping; no blob probing or media materialization.
  package func publicationInventory(transactionID: UUID) throws -> [LibraryExchangeStorageEntry] {
    try verifyPublished(transactionID, verifyObjects: false)
  }
  @discardableResult
  private func verifyPublished(_ transaction: UUID, verifyObjects: Bool = true) throws -> [LibraryExchangeStorageEntry] {
    let id = transaction.uuidString.lowercased()
    guard let row = try database.rows("SELECT index_digest,package_digest,intent FROM dx_transaction WHERE id=?",[id]).first,
      let index = row[0],let package = row[1],let rawIntent = row[2],rawIntent.utf8.count <= LibraryExchangeStorage.maximumPublicationIntentBytes else {
      throw LibraryExchangeCatalogError.invalidPublication("Publication identity missing")
    }
    let intent = try JSONDecoder().decode(LibraryExchangePublication.self,from:Data(rawIntent.utf8))
    guard intent.version == 1,intent.transactionID == transaction,intent.indexDigest.description == index,intent.packageDigest.description == package else {
      throw LibraryExchangeCatalogError.invalidPublication("Publication identity contradicts frozen intent")
    }
    let entries = try database.rows("SELECT f.path,f.digest,o.byte_length FROM dx_tx_file f JOIN dx_object o ON o.digest=f.digest WHERE f.transaction_id=? ORDER BY f.path",[id]).map { row -> LibraryExchangeStorageEntry in
      guard let path = row[0],let hash = row[1],let raw = row[2],let length = UInt64(raw) else { throw LibraryExchangeCatalogError.invalidPublication("Publication file inventory invalid") }
      return .init(path:path,digest:try ExchangeDigest(hash),byteLength:length)
    }
    try LibraryExchangeStorage.validateInventory(entries)
    guard Self.inventoryDigest(entries) == intent.packageDigest,
      entries.first(where:{$0.path == "data/exchange.json"})?.digest == intent.indexDigest else {
      throw LibraryExchangeCatalogError.invalidPublication("Publication file inventory missing or divergent")
    }
    let digests = Set(entries.map { $0.digest.description })
    let selected = Set(try database.rows("SELECT digest FROM dx_tx_object WHERE transaction_id=?",[id]).compactMap{$0[0]})
    guard selected == digests else { throw LibraryExchangeCatalogError.invalidPublication("Publication object and path inventories differ") }
    let bindings = try database.rows("SELECT r.kind,r.namespace,r.identity,r.digest FROM dx_tx_record t JOIN dx_record r ON r.kind=t.kind AND r.namespace=t.namespace AND r.identity=t.identity WHERE t.transaction_id=?",[id])
    let actualBindings = Set(bindings.map { $0.map { $0 ?? "" }.joined(separator:"\0") })
    let expectedBindings = Set(intent.records.map { ($0.key + [$0.digest.description]).joined(separator:"\0") })
    guard actualBindings == expectedBindings else { throw LibraryExchangeCatalogError.invalidPublication("Publication exact-reference inventory differs") }
    if let commit=intent.domainCommit {
      guard try domainReceipt(commit.intent,request:commit.request)==intent.transactionID else { throw LibraryExchangeCatalogError.invalidPublication("Committed domain receipt is missing or divergent") }
    }
    for attachment in intent.attachments {
      guard let summary = attachment.summary, intent.records.contains(.drawing(summary.reference)) else {
        throw LibraryExchangeCatalogError.invalidPublication("Frozen attachment drawing is outside its publication")
      }
      try verifyAttachment(attachment)
    }
    for summary in intent.sourceSummaries ?? [] { try verifySourceSummary(summary) }
    if let header = intent.resultHeader { try verifyResultHeader(header, transaction: transaction) }
    if verifyObjects {
      var verified = Set<ExchangeDigest>()
      for entry in entries where verified.insert(entry.digest).inserted {
        try storage.verifyObject(digest:entry.digest,byteLength:entry.byteLength)
      }
    }
    return entries
  }
  private func checkCollisions(_ intent: LibraryExchangePublication) throws {
    for ref in intent.records {
      if ["drawing","photo","input","assessment","ranking"].contains(ref.key[0]),
        let existing = try database.rows("SELECT kind,digest FROM dx_record WHERE namespace=? AND identity=? AND kind IN ('drawing','photo','input','assessment','ranking')",[ref.key[1],ref.key[2]]).first,
        existing[0] != ref.key[0] || existing[1] != ref.digest.description {
        throw LibraryExchangeCatalogError.invalidPublication("Issuer/revision already identifies a different immutable record")
      }
      if let old = try database.scalar("SELECT digest FROM dx_record WHERE kind=? AND namespace=? AND identity=?", ref.key.map(Optional.some)), old != ref.digest.description {
        throw LibraryExchangeCatalogError.digestConflict(ref, existing: old)
      }
    }
    if let prior = try database.scalar("SELECT package_digest FROM dx_transaction WHERE id=?", [intent.transactionID.uuidString.lowercased()]), prior != intent.packageDigest.description {
      throw LibraryExchangeCatalogError.invalidPublication("Transaction ID already identifies different bytes")
    }
  }
  private func installAndPublish(_ staging: LibraryExchangeStaging, intent: LibraryExchangePublication) throws {
    let inventory = Dictionary(grouping: staging.entries, by: { $0.digest.description })
    guard Self.inventoryDigest(staging.entries) == intent.packageDigest, inventory[intent.indexDigest.description] != nil,
      intent.records.allSatisfy({ inventory[$0.digest.description] != nil }) else {
      throw LibraryExchangeCatalogError.invalidPublication("Journal reference outside immutable inventory")
    }
    try storage.installObjects(staging)
    try injectFault?(.beforeSQLPublication)
    try database.transaction {
      try checkCollisions(intent)
      let transaction = intent.transactionID.uuidString.lowercased()
      try database.execute("INSERT INTO dx_transaction(id,index_digest,package_digest,intent) VALUES(?,?,?,?)", [transaction,intent.indexDigest.description,intent.packageDigest.description,String(decoding:staging.intent,as:UTF8.self)])
      for entry in staging.entries {
        if let old = try database.scalar("SELECT byte_length FROM dx_object WHERE digest=?",[entry.digest.description]), old != String(entry.byteLength) { throw LibraryExchangeCatalogError.invalidPublication("Object size collision") }
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
      for summary in intent.sourceSummaries ?? [] { try applySourceSummary(summary); try verifySourceSummary(summary) }
      for value in intent.metadata { try writeMetadata(value) }
      for attachment in intent.attachments {
        guard let summary = attachment.summary, intent.records.contains(.drawing(summary.reference)) else {
          throw LibraryExchangeCatalogError.invalidPublication("Attachment drawing is outside its publication")
        }
        try apply(attachment)
        try verifyAttachment(attachment)
      }
      if let commit = intent.domainCommit { try applyDomainCommit(commit,transaction:intent.transactionID) }
      if let header = intent.resultHeader {
        try applyResultHeader(header, transaction: intent.transactionID)
        try verifyResultHeader(header, transaction: intent.transactionID)
      }
      try database.bumpRevision()
      try injectFault?(.beforeSQLCommit)
    }
    try injectFault?(.afterSQLCommit)
    try injectFault?(.afterSQLPublication)
    try storage.finish(transactionID: staging.transactionID)
  }

  package static func inventoryDigest(_ entries: [LibraryExchangeStorageEntry]) -> ExchangeDigest {
    let bytes = entries.sorted { $0.path < $1.path }.map { $0.path + "\0" + $0.digest.description + "\0" + String($0.byteLength) + "\n" }.joined()
    return .hash(Data(bytes.utf8))
  }

  private func references(_ package: ValidatedExchangePackage) throws -> [LibraryExchangeReference] {
    // The admitted v1 closure has checked every canonical record path, including
    // unselected records. Unknown index majors grant preservation only.
    guard package.index.known != nil else { return [] }
    var result: [LibraryExchangeReference] = []
    for file in package.files.entries.values.sorted(by: { $0.path < $1.path }) {
      let parts = file.path.split(separator: "/").map(String.init)
      guard parts.first == "data", parts.count >= 4 else { continue }
      func uuid(_ text: String) throws -> UUID {
        guard let id = UUID(uuidString: text), id.uuidString.lowercased() == text else { throw LibraryExchangeCatalogError.invalidPublication("Noncanonical admitted identity") }; return id
      }
      switch parts[1] {
      case "drawings", "photos", "inputs":
        guard parts.count == 5 else { throw LibraryExchangeCatalogError.invalidPublication("Record path") }
        let issuer = try uuid(parts[2]), revision = try uuid(parts[3])
        switch parts[1] {
        case "drawings": result.append(.drawing(.init(issuer: issuer, revision: revision, digest: file.digest)))
        case "photos": result.append(.photo(.init(issuer: issuer, revision: revision, digest: file.digest)))
        default: result.append(.input(.init(issuer: issuer, revision: revision, digest: file.digest)))
        }
      case "assessments", "rankings":
        guard parts.count == 4, parts[3].hasSuffix(".json") else { throw LibraryExchangeCatalogError.invalidPublication("Record path") }
        let issuer = try uuid(parts[2]), revision = try uuid(String(parts[3].dropLast(5)))
        if parts[1] == "assessments" { result.append(.assessment(.init(issuer: issuer, revision: revision, digest: file.digest))) }
        else { result.append(.ranking(.init(issuer: issuer, revision: revision, digest: file.digest))) }
      case "jobs":
        guard parts.count == 5 else { throw LibraryExchangeCatalogError.invalidPublication("Receipt path") }
        result.append(.receipt(.init(handle: .init(engine: try uuid(parts[2]), job: try uuid(parts[3])), receiptDigest: file.digest)))
      case "attempts":
        guard parts.count == 6, let sequence = UInt64(parts[4]) else { throw LibraryExchangeCatalogError.invalidPublication("Snapshot path") }
        result.append(.snapshot(try .init(archive: uuid(parts[2]), run: uuid(parts[3]), sequence: sequence, digest: file.digest)))
      default: break
      }
    }
    return result
  }
  private func links(_ package: ValidatedExchangePackage) throws -> [LibraryExchangeLink] {
    var result: [LibraryExchangeLink] = []
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

  package func backupInventory() throws -> [LibraryExchangeStorageEntry] {
    let entries = try database.rows("SELECT digest,byte_length FROM dx_object ORDER BY digest").map { row -> LibraryExchangeStorageEntry in
      guard let digest = row[0], let rawLength = row[1], let length = UInt64(rawLength) else { throw LibraryExchangeCatalogError.invalidPublication("Object inventory") }
      return .init(path: "objects/sha256/" + digest, digest: try ExchangeDigest(digest), byteLength: length)
    }
    return entries
  }
  private var storageRoot: URL { database.writerLease!.canonicalRootURL }
  private static let schema = """
  CREATE INDEX IF NOT EXISTS dx_photo_order ON dx_source_summary(kind,known_date DESC,chronology DESC,namespace,identity);
  CREATE INDEX IF NOT EXISTS dx_input_order ON dx_source_summary(kind,photo_namespace,photo_identity,photo_digest,namespace,identity);
  CREATE TABLE IF NOT EXISTS dx_result_publication(transaction_id TEXT PRIMARY KEY REFERENCES dx_transaction(id),included_as_of TEXT NOT NULL,chronology REAL NOT NULL,index_digest TEXT NOT NULL,package_digest TEXT NOT NULL,header TEXT NOT NULL,UNIQUE(index_digest,package_digest));
  CREATE INDEX IF NOT EXISTS dx_result_global_chronology ON dx_result_publication(chronology DESC,index_digest,package_digest);
  CREATE TABLE IF NOT EXISTS dx_result_root(transaction_id TEXT NOT NULL REFERENCES dx_result_publication(transaction_id),issuer TEXT NOT NULL,revision TEXT NOT NULL,digest TEXT NOT NULL,chronology REAL NOT NULL,index_digest TEXT NOT NULL,package_digest TEXT NOT NULL,PRIMARY KEY(transaction_id,issuer,revision,digest));
  CREATE INDEX IF NOT EXISTS dx_result_chronology ON dx_result_root(issuer,revision,digest,chronology DESC,index_digest,package_digest);
  CREATE TABLE IF NOT EXISTS domain_commit(id TEXT PRIMARY KEY,request_digest TEXT NOT NULL,transaction_id TEXT NOT NULL REFERENCES dx_transaction(id));
  CREATE TABLE IF NOT EXISTS domain_record(kind TEXT NOT NULL,id TEXT NOT NULL,payload TEXT NOT NULL,PRIMARY KEY(kind,id));
  CREATE TABLE IF NOT EXISTS domain_reference(kind TEXT NOT NULL,id TEXT NOT NULL,target_kind TEXT NOT NULL,namespace TEXT NOT NULL,identity TEXT NOT NULL,digest TEXT NOT NULL,PRIMARY KEY(kind,id,target_kind,namespace,identity),FOREIGN KEY(kind,id) REFERENCES domain_record(kind,id) ON DELETE CASCADE,FOREIGN KEY(target_kind,namespace,identity,digest) REFERENCES dx_record(kind,namespace,identity,digest));
  CREATE TABLE IF NOT EXISTS domain_asset(kind TEXT NOT NULL,id TEXT NOT NULL,digest TEXT NOT NULL REFERENCES dx_object(digest),PRIMARY KEY(kind,id,digest),FOREIGN KEY(kind,id) REFERENCES domain_record(kind,id) ON DELETE CASCADE);
  CREATE TABLE IF NOT EXISTS dx_retention_intent(id TEXT PRIMARY KEY,issuer TEXT NOT NULL,revision TEXT NOT NULL,digest TEXT NOT NULL,request_digest TEXT NOT NULL);
  CREATE TABLE IF NOT EXISTS dx_drawing_summary(namespace TEXT NOT NULL,identity TEXT NOT NULL,digest TEXT NOT NULL,program_digest TEXT NOT NULL,created_at REAL NOT NULL,stroke_count INTEGER NOT NULL,point_count INTEGER NOT NULL,min_x REAL NOT NULL,min_y REAL NOT NULL,max_x REAL NOT NULL,max_y REAL NOT NULL,PRIMARY KEY(namespace,identity));
  CREATE INDEX IF NOT EXISTS dx_drawing_chronological ON dx_drawing_summary(created_at DESC,namespace ASC,identity ASC);
  CREATE TABLE IF NOT EXISTS dx_object(digest TEXT PRIMARY KEY,byte_length TEXT NOT NULL);
  CREATE TABLE IF NOT EXISTS dx_record(kind TEXT NOT NULL,namespace TEXT NOT NULL,identity TEXT NOT NULL,digest TEXT NOT NULL REFERENCES dx_object(digest),PRIMARY KEY(kind,namespace,identity),UNIQUE(kind,namespace,identity,digest));
  CREATE UNIQUE INDEX IF NOT EXISTS dx_shared_identity ON dx_record(namespace,identity) WHERE kind IN ('drawing','photo','input','assessment','ranking');
  CREATE TABLE IF NOT EXISTS dx_transaction(id TEXT PRIMARY KEY,index_digest TEXT NOT NULL,package_digest TEXT NOT NULL,intent TEXT NOT NULL);
  CREATE INDEX IF NOT EXISTS dx_transaction_package ON dx_transaction(package_digest);
  CREATE TABLE IF NOT EXISTS dx_tx_object(transaction_id TEXT NOT NULL REFERENCES dx_transaction(id),digest TEXT NOT NULL REFERENCES dx_object(digest),PRIMARY KEY(transaction_id,digest));
  CREATE TABLE IF NOT EXISTS dx_tx_file(transaction_id TEXT NOT NULL,path TEXT NOT NULL,digest TEXT NOT NULL,PRIMARY KEY(transaction_id,path),FOREIGN KEY(transaction_id,digest) REFERENCES dx_tx_object(transaction_id,digest));
  CREATE TABLE IF NOT EXISTS dx_tx_record(transaction_id TEXT NOT NULL REFERENCES dx_transaction(id),kind TEXT NOT NULL,namespace TEXT NOT NULL,identity TEXT NOT NULL,PRIMARY KEY(transaction_id,kind,namespace,identity),FOREIGN KEY(kind,namespace,identity) REFERENCES dx_record(kind,namespace,identity));
  CREATE TABLE IF NOT EXISTS dx_link(source_kind TEXT NOT NULL,source_namespace TEXT NOT NULL,source_identity TEXT NOT NULL,target_kind TEXT NOT NULL,target_namespace TEXT NOT NULL,target_identity TEXT NOT NULL,relation TEXT NOT NULL,PRIMARY KEY(source_kind,source_namespace,source_identity,target_kind,target_namespace,target_identity,relation),FOREIGN KEY(source_kind,source_namespace,source_identity) REFERENCES dx_record(kind,namespace,identity),FOREIGN KEY(target_kind,target_namespace,target_identity) REFERENCES dx_record(kind,namespace,identity));
  CREATE TABLE IF NOT EXISTS dx_metadata(kind TEXT NOT NULL,namespace TEXT NOT NULL,identity TEXT NOT NULL,digest TEXT NOT NULL,payload TEXT NOT NULL,tombstoned INTEGER NOT NULL DEFAULT 0,PRIMARY KEY(kind,namespace,identity),FOREIGN KEY(kind,namespace,identity,digest) REFERENCES dx_record(kind,namespace,identity,digest));
  CREATE TABLE IF NOT EXISTS dx_summary(kind TEXT NOT NULL,namespace TEXT NOT NULL,identity TEXT NOT NULL,digest TEXT NOT NULL,PRIMARY KEY(kind,namespace,identity));
  """
}
