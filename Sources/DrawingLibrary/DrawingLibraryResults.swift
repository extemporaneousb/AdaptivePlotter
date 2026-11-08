import Foundation
import PortraitCore

/// Selects a delivery, not an arbitrary publication containing the same Drawing.
public struct DrawingLibraryResultRef: Hashable, Codable, Sendable {
  public let indexDigest: ExchangeDigest
  public let packageDigest: ExchangeDigest
  public init(indexDigest: ExchangeDigest, packageDigest: ExchangeDigest) {
    self.indexDigest = indexDigest; self.packageDigest = packageDigest
  }
}
public struct DrawingLibraryResultMount: Sendable {
  public let reference: DrawingLibraryResultRef
  public let wasAlreadyMounted: Bool
}
/// Declared roots only. This metadata grants no interpretation capability.
public struct DrawingLibraryResultEntry: Sendable, Identifiable {
  public var id: DrawingLibraryResultRef { reference }
  public let reference: DrawingLibraryResultRef
  public let includedAsOf: String
  public let drawingReferences: [DrawingRef]
  public let jobReferences: [JobReceiptRef]
  public let attemptReferences: [SnapshotRef]
  public let assessmentReferences: [AssessmentRef]
}
public struct DrawingLibraryResultCursor: Sendable {
  package let drawing: DrawingRef?
  package let generation: DrawingLibraryGeneration
  package let chronology: String
  package let reference: DrawingLibraryResultRef
}
public struct DrawingLibraryResultPage: Sendable {
  public let entries: [DrawingLibraryResultEntry]
  public let next: DrawingLibraryResultCursor?
}

/// Derived only from admitted Core index metadata, frozen into the publication
/// intent so recovery and duplicate verification cannot lose a visible result.
struct DrawingLibraryResultHeader: Codable, Equatable {
  let includedAsOf: String
  let chronology: Double
  let drawings: [DrawingRef]
  let jobs: [JobReceiptRef]
  let attempts: [SnapshotRef]
  let assessments: [AssessmentRef]
  let summaries: [DrawingLibraryPublishedSummary]?
  init?(_ admitted: ValidatedExchangePackage) throws {
    guard let index = admitted.index.known, index.kind == "result" else { return nil }
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    let fractional = formatter.date(from: index.includedAsOf)
    formatter.formatOptions = [.withInternetDateTime]
    guard let date = fractional ?? formatter.date(from: index.includedAsOf) else { throw DrawingLibraryError.invalidIdentity }
    includedAsOf = index.includedAsOf; chronology = date.timeIntervalSince1970
    drawings = index.roots; jobs = index.jobs; attempts = index.attempts; assessments = index.assessments
    summaries = try index.roots.compactMap { ref in
      guard case .materialized(let frozen)? = admitted.drawings[ref] else { return nil }
      return try DrawingLibraryPublishedSummary(original: frozen)
    }
  }
  func entry(_ reference: DrawingLibraryResultRef) -> DrawingLibraryResultEntry {
    .init(reference: reference, includedAsOf: includedAsOf, drawingReferences: drawings,
      jobReferences: jobs, attemptReferences: attempts, assessmentReferences: assessments)
  }
}

extension DrawingLibrary {
  /// Stages and validates an inert current-format result, then commits its exact
  /// inventory and metadata through the same owner/journal as authored drawings.
  public func mountResult(from source: URL) throws -> DrawingLibraryResultMount {
    let temp = FileManager.default.temporaryDirectory.appendingPathComponent("result-mount-" + UUID().uuidString.lowercased(), isDirectory: true)
    try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
    defer { try? FileManager.default.removeItem(at: temp) }
    var directory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: source.path, isDirectory: &directory) else { throw DrawingLibraryError.unavailable("Result source unavailable") }
    let staged = try directory.boolValue ? DrawingExchangeCarrier.stageDirectory(source, stagingParent: temp) : DrawingExchangeCarrier.stageZIP(source, stagingParent: temp)
    let admitted = try ExchangeAdmission.validate(staged, producerValidators: producerValidators, payloadValidators: payloadValidators)
    guard admitted.index.known?.kind == "result" else { throw DrawingLibraryError.unsupportedFeature("Mount requires a current result index") }
    let reference = DrawingLibraryResultRef(indexDigest: .hash(admitted.index.originalJSON), packageDigest: LibraryExchangeCatalog.inventoryDigest(admitted.files.entries.values.map { .init(path: $0.path, digest: $0.digest, byteLength: $0.byteLength) }))
    let catalog = try commonCatalog()
    defer { refreshOwnership() }
    do {
      let receipt = try catalog.publish(admitted)
      return .init(reference: reference, wasAlreadyMounted: receipt.wasAlreadyPublished)
    } catch LibraryExchangeCatalogError.preservedConflict(let location) {
      throw DrawingLibraryError.quarantinedConflict(location)
    }
  }

  /// Recomputes capability admission for this publication's own verified files.
  /// No cached header can grant interpretation or choose another delivery.
  public func result(_ reference: DrawingLibraryResultRef) throws -> ValidatedExchangePackage {
    guard let db = try commonReadDatabase() else { throw DrawingLibraryError.unavailable("Result is not mounted") }
    return try commonSnapshot(db) {
      let files = try resultFiles(reference, database: db)
      let admitted = try ExchangeAdmission.validate(files: files, producerValidators: producerValidators, payloadValidators: payloadValidators)
      guard admitted.index.known?.kind == "result", ExchangeDigest.hash(admitted.index.originalJSON) == reference.indexDigest else { throw DrawingLibraryError.invalidIdentity }
      return admitted
    }
  }

  public func results(for drawing: DrawingRef, limit: Int = 50, after: DrawingLibraryResultCursor? = nil) throws -> DrawingLibraryResultPage {
    try queryResults(drawing: drawing, limit: limit, after: after)
  }

  /// Global metadata discovery includes opaque deliveries without inventing
  /// Drawing program metrics or granting their interpretation.
  public func results(limit: Int = 50, after: DrawingLibraryResultCursor? = nil) throws -> DrawingLibraryResultPage {
    try queryResults(drawing: nil, limit: limit, after: after)
  }

  private func queryResults(drawing: DrawingRef?, limit: Int, after: DrawingLibraryResultCursor?) throws -> DrawingLibraryResultPage {
    guard limit > 0, limit <= 500 else { throw DrawingLibraryError.invalidQuery }
    if let after, after.drawing != drawing { throw DrawingLibraryError.invalidQuery }
    guard let db = try commonReadDatabase() else { return .init(entries: [], next: nil) }
    return try commonSnapshot(db) {
      if let drawing, try tableExists("dx_record", in: db), let stored = try db.scalar("SELECT digest FROM dx_record WHERE kind='drawing' AND namespace=? AND identity=?", [drawing.issuer.uuidString.lowercased(), drawing.revision.uuidString.lowercased()]) {
        let actual = try ExchangeDigest(stored)
        guard actual == drawing.digest else { throw DrawingLibraryError.referenceConflict(drawing, actual: actual) }
      }
      guard try tableExists("dx_result_publication", in: db) else { return .init(entries: [], next: nil) }
      let generation = try db.generation
      if let after, after.generation != generation { throw DrawingLibraryError.staleSelection }
      let alias = drawing == nil ? "p" : "r"
      let from = drawing == nil ? "dx_result_publication p" : "dx_result_root r JOIN dx_result_publication p ON p.transaction_id=r.transaction_id"
      var predicate = "1=1", values: [String?] = []
      if let drawing {
        predicate = "r.issuer=? AND r.revision=? AND r.digest=?"
        values = [drawing.issuer.uuidString.lowercased(), drawing.revision.uuidString.lowercased(), drawing.digest.description]
      }
      if let after {
        predicate += " AND (\(alias).chronology<CAST(? AS REAL) OR (\(alias).chronology=CAST(? AS REAL) AND (\(alias).index_digest>? OR (\(alias).index_digest=? AND \(alias).package_digest>?))))"
        values += [after.chronology, after.chronology, after.reference.indexDigest.description, after.reference.indexDigest.description, after.reference.packageDigest.description]
      }
      let rows = try db.rows("SELECT \(alias).index_digest,\(alias).package_digest,printf('%!.17g',\(alias).chronology),p.header FROM " + from + " WHERE " + predicate + " ORDER BY \(alias).chronology DESC,\(alias).index_digest ASC,\(alias).package_digest ASC LIMIT ?", values + [String(limit + 1)])
      let page = Array(rows.prefix(limit))
      let entries = try page.map { row -> DrawingLibraryResultEntry in
        guard let index = row[0], let package = row[1], let json = row[3], json.utf8.count <= ExchangeJSON.maximumRecordBytes else { throw DrawingLibraryError.invalidIdentity }
        let ref = DrawingLibraryResultRef(indexDigest: try ExchangeDigest(index), packageDigest: try ExchangeDigest(package))
        let header = try JSONDecoder().decode(DrawingLibraryResultHeader.self, from: Data(json.utf8))
        if let drawing, !header.drawings.contains(drawing) { throw DrawingLibraryError.invalidIdentity }
        return header.entry(ref)
      }
      let next: DrawingLibraryResultCursor?
      if rows.count > limit, let last = page.last, let date = last[2], let entry = entries.last {
        next = .init(drawing: drawing, generation: generation, chronology: date, reference: entry.reference)
      } else { next = nil }
      return .init(entries: entries, next: next)
    }
  }

  /// Preserves the original result index, tags, extensions and entire inventory.
  /// Unsupported interpretation does not prevent byte-preserving re-export.
  public func exportResult(_ reference: DrawingLibraryResultRef, to destination: URL) throws {
    let admitted = try result(reference)
    if destination.pathExtension.lowercased() == "zip" { try DrawingExchangeCarrier.preserveZIP(admitted.files, to: destination) }
    else { try DrawingExchangeCarrier.preserveDirectory(admitted.files, to: destination) }
  }

  package func resultFiles(_ reference: DrawingLibraryResultRef, database db: DrawingLibraryDatabase) throws -> VerifiedExchangeFiles {
    guard try tableExists("dx_result_publication", in: db),
      let transaction = try db.scalar("SELECT t.id FROM dx_transaction t JOIN dx_result_publication r ON r.transaction_id=t.id WHERE t.index_digest=? AND t.package_digest=? ORDER BY t.id LIMIT 1", [reference.indexDigest.description, reference.packageDigest.description]) else {
      throw DrawingLibraryError.unavailable("Result publication is not mounted")
    }
    let inventory = try db.rows("SELECT f.path,f.digest,o.byte_length FROM dx_tx_file f JOIN dx_object o ON o.digest=f.digest WHERE f.transaction_id=? ORDER BY f.path", [transaction]).map { row -> LibraryExchangeStorageEntry in
      guard let path = row[0], let digest = row[1], let length = row[2].flatMap(UInt64.init) else { throw DrawingLibraryError.invalidIdentity }
      return .init(path: path, digest: try ExchangeDigest(digest), byteLength: length)
    }
    guard LibraryExchangeCatalog.inventoryDigest(inventory) == reference.packageDigest,
      inventory.first(where: { $0.path == "data/exchange.json" })?.digest == reference.indexDigest else { throw DrawingLibraryError.invalidIdentity }
    return try VerifiedExchangeFiles(catalogRoot: directoryURL, inventory: inventory.map {
      .init(path: $0.path, storagePath: "objects/sha256/" + $0.digest.description, digest: $0.digest, byteLength: $0.byteLength)
    })
  }
}

extension LibraryExchangeCatalog {
  func applyResultHeader(_ header: DrawingLibraryResultHeader, transaction: UUID) throws {
    let id = transaction.uuidString.lowercased()
    let json = try DrawingArtifactCoding.encoder().encode(header)
    guard json.count <= ExchangeJSON.maximumRecordBytes,
      let row = try database.rows("SELECT index_digest,package_digest FROM dx_transaction WHERE id=?", [id]).first,
      let index = row[0], let package = row[1] else { throw DrawingLibraryError.invalidIdentity }
    try database.execute("INSERT OR IGNORE INTO dx_result_publication(transaction_id,included_as_of,chronology,index_digest,package_digest,header) VALUES(?,?,?,?,?,?)", [id, header.includedAsOf, String(header.chronology), index, package, String(decoding: json, as: UTF8.self)])
    guard let canonical = try database.scalar("SELECT transaction_id FROM dx_result_publication WHERE index_digest=? AND package_digest=?", [index, package]) else {
      throw LibraryExchangeCatalogError.invalidPublication("Canonical result publication is missing")
    }
    if canonical != id {
      // The domain/attachment transaction is distinct; the exact delivered result
      // identity is not. Existing immutable projections must verify, not replay.
      try verifyResultHeader(header, transaction: transaction)
      return
    }
    for summary in header.summaries ?? [] { try applySummary(summary) }
    for drawing in Set(header.drawings) {
      try database.execute("INSERT INTO dx_result_root(transaction_id,issuer,revision,digest,chronology,index_digest,package_digest) VALUES(?,?,?,?,?,?,?)", [id, drawing.issuer.uuidString.lowercased(), drawing.revision.uuidString.lowercased(), drawing.digest.description, String(header.chronology), index, package])
    }
  }
  func verifyResultHeader(_ header: DrawingLibraryResultHeader, transaction: UUID) throws {
    let id = transaction.uuidString.lowercased()
    guard let row = try database.rows("SELECT p.included_as_of,printf('%!.17g',p.chronology),p.header,t.index_digest,t.package_digest,p.index_digest,p.package_digest,p.transaction_id FROM dx_transaction t JOIN dx_result_publication p ON p.index_digest=t.index_digest AND p.package_digest=t.package_digest JOIN dx_transaction c ON c.id=p.transaction_id AND c.index_digest=p.index_digest AND c.package_digest=p.package_digest WHERE t.id=?", [id]).first,
      row[0] == header.includedAsOf, row[1].flatMap(Double.init) == header.chronology, row[3] == row[5], row[4] == row[6],
      let json = row[2], json.utf8.count <= ExchangeJSON.maximumRecordBytes,
      try JSONDecoder().decode(DrawingLibraryResultHeader.self, from: Data(json.utf8)) == header else {
      throw LibraryExchangeCatalogError.invalidPublication("Result header missing or divergent")
    }
    for summary in header.summaries ?? [] { try verifySummary(summary) }
    guard let canonical = row[7] else { throw DrawingLibraryError.invalidIdentity }
    let roots = try database.rows("SELECT issuer,revision,digest,printf('%!.17g',chronology),index_digest,package_digest FROM dx_result_root WHERE transaction_id=?", [canonical])
    let expected = Set(header.drawings.map { [$0.issuer.uuidString.lowercased(), $0.revision.uuidString.lowercased(), $0.digest.description].joined(separator: "\0") })
    guard Set(roots.map { Array($0.prefix(3)).map { $0 ?? "" }.joined(separator: "\0") }) == expected,
      roots.allSatisfy({ $0[3].flatMap(Double.init) == header.chronology && $0[4] == row[3] && $0[5] == row[4] }) else {
      throw LibraryExchangeCatalogError.invalidPublication("Result root association missing or divergent")
    }
  }
}
