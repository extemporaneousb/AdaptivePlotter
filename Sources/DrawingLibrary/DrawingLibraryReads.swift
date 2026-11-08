import Foundation
import PortraitCore

extension DrawingLibrary {
  package func commonReadDatabase() throws -> DrawingLibraryDatabase? {
    guard !closed else { throw DrawingLibraryError.closed }
    guard FileManager.default.fileExists(atPath: commonDatabaseURL.path) else {
      if LibraryExchangeCatalogSelection.markerPresent(root: directoryURL) { throw DrawingLibraryError.ownership("Selected catalog is missing") }
      return nil
    }
    return try DrawingLibraryDatabase(url: commonDatabaseURL, readOnly: true)
  }
  package func commonSnapshot<T>(_ db: DrawingLibraryDatabase, _ operation: () throws -> T) throws -> T {
    try db.assertSelectedFile()
    let before = try DrawingLibraryFileState(db.url), generation = try db.generation
    try db.execute("BEGIN")
    defer { try? db.execute("ROLLBACK") }
    let value = try operation()
    try db.assertSelectedFile()
    guard try DrawingLibraryFileState(db.url) == before, try db.generation == generation else { throw DrawingLibraryError.staleSelection }
    return value
  }
  package func tableExists(_ table:String,in db:DrawingLibraryDatabase)throws->Bool {
    try db.scalar("SELECT name FROM sqlite_master WHERE type='table' AND name=?",[table]) != nil
  }
  public func drawing(_ ref: DrawingRef) throws -> Drawing {
    guard let db = try commonReadDatabase() else { throw DrawingLibraryError.missing(ref) }
    return try commonSnapshot(db) {
      guard try tableExists("dx_record", in: db), let stored = try db.scalar("SELECT digest FROM dx_record WHERE kind='drawing' AND namespace=? AND identity=?", [ref.issuer.uuidString.lowercased(), ref.revision.uuidString.lowercased()]) else {
        throw DrawingLibraryError.missing(ref)
      }
      let digest = try ExchangeDigest(stored)
      guard digest == ref.digest else { throw DrawingLibraryError.referenceConflict(ref, actual: digest) }
      if let metadata=try preparedMetadata(ref,database:db),metadata.tombstoned { throw DrawingLibraryError.deleted(ref) }
      let inventory = try publicationFiles(for: ref, db: db)
      let files = try VerifiedExchangeFiles(catalogRoot: directoryURL, inventory: inventory)
      let index = try files.record(at: "data/exchange.json"), indexDigest = ExchangeDigest.hash(index)
      if let cached = selectedDrawingCache[ref] {
        if cached.indexDigest == indexDigest {
          do {
            try cached.files.revalidateSelected()
            touchSelectedDrawing(ref)
            return cached.value
          } catch {
            // A valid immutable object may have a new inode or file version.
            // Require fresh admission to verify its bytes again.
          }
        }
        evictSelectedDrawing(ref)
      }
      let proof = try ExchangeAdmission.selectDrawing(originalIndexJSON: index, selected: ref, files: files, producerValidators: producerValidators)
      guard case .materialized(let frozen) = proof.admission else {
        throw DrawingLibraryError.unsupportedFeature(proof.capabilities.unsupportedReasons.first ?? "Opaque drawing representation")
      }
      selectedDrawingCache[ref] = (indexDigest, files, frozen.drawing)
      touchSelectedDrawing(ref)
      return frozen.drawing
    }
  }
  package func publicationFiles(for ref: DrawingRef, db: DrawingLibraryDatabase) throws -> [ExchangeCatalogFile] {
    guard let transaction = try db.scalar("SELECT transaction_id FROM dx_tx_record WHERE kind='drawing' AND namespace=? AND identity=? ORDER BY transaction_id LIMIT 1", [ref.issuer.uuidString.lowercased(), ref.revision.uuidString.lowercased()]) else { throw DrawingLibraryError.missing(ref) }
    return try db.rows("SELECT f.path,f.digest,o.byte_length FROM dx_tx_file f JOIN dx_object o ON o.digest=f.digest WHERE f.transaction_id=? ORDER BY f.path", [transaction]).map { row in
      guard let path = row[0], let hash = row[1], let size = row[2].flatMap(UInt64.init) else { throw DrawingLibraryError.invalidIdentity }
      return .init(path: path, storagePath: "objects/sha256/" + hash, digest: try ExchangeDigest(hash), byteLength: size)
    }
  }

  public func drawings(limit: Int = 50, after: DrawingLibraryCursor? = nil) throws -> DrawingLibraryPage {
    guard limit > 0, limit <= 500 else { throw DrawingLibraryError.invalidQuery }
    guard let db = try commonReadDatabase(), try tableExists("dx_drawing_summary",in:db) else { return .init(entries:[],next:nil) }
    return try commonSnapshot(db) {
      let generation = try db.generation
      if let after, after.generation != generation { throw DrawingLibraryError.staleSelection }
      var predicate = "WHERE COALESCE(m.tombstoned,0)=0", values: [String?] = []
      if let after {
        predicate += " AND (s.created_at < CAST(? AS REAL) OR (s.created_at=CAST(? AS REAL) AND (s.namespace>? OR (s.namespace=? AND s.identity>?))))"
        values = [after.date,after.date,after.issuer,after.issuer,after.revision]
      }
      let rows = try db.rows("SELECT s.namespace,s.identity,s.digest,s.program_digest,printf('%!.17g',s.created_at),s.stroke_count,s.point_count,m.payload FROM dx_drawing_summary s LEFT JOIN dx_metadata m ON m.kind='drawing' AND m.namespace=s.namespace AND m.identity=s.identity " + predicate + " ORDER BY s.created_at DESC,s.namespace ASC,s.identity ASC LIMIT ?",values+[String(limit+1)])
      let page = Array(rows.prefix(limit))
      let entries = try page.map { row -> DrawingLibraryEntry in
        guard let issuer=row[0].flatMap(UUID.init(uuidString:)), let revision=row[1].flatMap(UUID.init(uuidString:)), let digest=row[2],let program=row[3],let count=row[5].flatMap(Int.init),let points=row[6].flatMap(Int.init) else { throw DrawingLibraryError.invalidIdentity }
        let metadata = try row[7].map { try JSONDecoder().decode(LibraryExchangeMetadata.self,from:Data($0.utf8)) }
        let ref=DrawingRef(issuer:issuer,revision:revision,digest:try ExchangeDigest(digest))
        if let metadata,metadata.reference != .drawing(ref) { throw DrawingLibraryError.invalidIdentity }
        return .init(reference:ref,title:metadata?.title,createdAt:row[4].flatMap(Double.init).map(Date.init(timeIntervalSince1970:)),programDigest:try ExchangeDigest(program),strokeCount:count,pointCount:points)
      }
      let next:DrawingLibraryCursor? = rows.count > limit ? .init(generation:generation,date:page.last![4]!,issuer:page.last![0]!,revision:page.last![1]!) : nil
      return .init(entries:entries,next:next)
    }
  }
}
