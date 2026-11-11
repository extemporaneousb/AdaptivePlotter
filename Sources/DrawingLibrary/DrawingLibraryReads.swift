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
  package func commonSnapshot<T>(_ db: DrawingLibraryDatabase, _ operation: (DrawingLibraryDatabase) throws -> T) throws -> T {
    try db.assertSelectedFile()
    let before = try DrawingLibraryFileState(db.url), generation = try db.generation
    try db.execute("BEGIN")
    defer { try? db.execute("ROLLBACK") }
    let value = try operation(db)
    try db.assertSelectedFile()
    guard try DrawingLibraryFileState(db.url) == before, try db.generation == generation else { throw DrawingLibraryError.staleSelection }
    return value
  }
  package func tableExists(_ table:String,in db:DrawingLibraryDatabase)throws->Bool {
    try db.scalar("SELECT name FROM sqlite_master WHERE type='table' AND name=?",[table]) != nil
  }
  public func drawing(_ ref: DrawingRef) throws -> Drawing {
    guard let db = try commonReadDatabase() else { throw DrawingLibraryError.missing(ref) }
    return try commonSnapshot(db) { db in
      guard try tableExists("dx_record", in: db), let stored = try db.scalar("SELECT digest FROM dx_record WHERE kind='drawing' AND namespace=? AND identity=?", [ref.issuer.uuidString.lowercased(), ref.revision.uuidString.lowercased()]) else {
        throw DrawingLibraryError.missing(ref)
      }
      let digest = try ExchangeDigest(stored)
      guard digest == ref.digest else { throw DrawingLibraryError.referenceConflict(ref, actual: digest) }
      if let metadata=try preparedMetadata(ref,database:db),metadata.tombstoned { throw DrawingLibraryError.deleted(ref) }
      if let cached = selectedDrawingCache[ref] {
        // A cache hit still belongs to an exact current publication/index. Its
        // selected fingerprints prove the assets without decoding the program.
        let candidates = try publicationCandidates(.drawing(ref), database: db)
        if let candidate = candidates.first(where: { $0.index == cached.indexDigest }) {
          do {
            let files = try publicationFiles(candidate, database: db)
            let index = try files.record(at: "data/exchange.json")
            guard ExchangeDigest.hash(index) == cached.indexDigest else { throw DrawingLibraryError.invalidIdentity }
            do {
              try cached.files.revalidateSelected()
              let selected = try cached.files.selectedVerifiedFiles()
              guard selected.entries.allSatisfy({ path, value in
                files.entries[path]?.digest == value.digest && files.entries[path]?.byteLength == value.byteLength
              }) else { throw DrawingLibraryError.invalidIdentity }
              touchSelectedDrawing(ref)
              return cached.value
            } catch {
              evictSelectedDrawing(ref)
              // Re-admit this very context before considering another one. A
              // benign inode replacement succeeds; corrupt/missing bytes throw.
              let proof = try ExchangeAdmission.selectDrawing(originalIndexJSON: index, selected: ref, files: files, producerValidators: producerValidators)
              if case .materialized(let frozen) = proof.admission {
                selectedDrawingCache[ref] = (proof.indexDigest, proof.files, frozen.drawing)
                touchSelectedDrawing(ref)
                return frozen.drawing
              }
            }
          } catch {
            evictSelectedDrawing(ref)
            throw error
          }
        }
        evictSelectedDrawing(ref)
      }
      let proof = try selectedDrawingPublication(for: ref, database: db)
      guard case .materialized(let frozen) = proof.admission else { throw DrawingLibraryError.unsupportedFeature("Opaque drawing representation") }
      let indexDigest = proof.indexDigest, files = proof.files
      selectedDrawingCache[ref] = (indexDigest, files, frozen.drawing)
      touchSelectedDrawing(ref)
      return frozen.drawing
    }
  }
  package struct LibraryPublicationCandidate {
    let transaction: String
    let index: ExchangeDigest
    let package: ExchangeDigest
  }
  package func publicationCandidates(_ reference: LibraryExchangeReference, database db: DrawingLibraryDatabase) throws -> [LibraryPublicationCandidate] {
    // Duplicate identical contexts are equivalent; transaction UUID order is not
    // a semantic choice. The caller may prefer an associated verified cache.
    try db.rows("SELECT MIN(t.id),t.index_digest,t.package_digest FROM dx_tx_record r JOIN dx_transaction t ON t.id=r.transaction_id WHERE r.kind=? AND r.namespace=? AND r.identity=? GROUP BY t.index_digest,t.package_digest ORDER BY t.index_digest,t.package_digest", reference.key.map(Optional.some)).map { row in
      guard let transaction = row[0], let index = row[1], let package = row[2] else { throw DrawingLibraryError.invalidIdentity }
      return .init(transaction: transaction, index: try ExchangeDigest(index), package: try ExchangeDigest(package))
    }
  }
  package func publicationFiles(_ candidate: LibraryPublicationCandidate, database db: DrawingLibraryDatabase) throws -> VerifiedExchangeFiles {
    let entries = try db.rows("SELECT f.path,f.digest,o.byte_length FROM dx_tx_file f JOIN dx_object o ON o.digest=f.digest WHERE f.transaction_id=? ORDER BY f.path", [candidate.transaction]).map { row -> LibraryExchangeStorageEntry in
      guard let path = row[0], let hash = row[1], let size = row[2].flatMap(UInt64.init) else { throw DrawingLibraryError.invalidIdentity }
      return .init(path: path, digest: try ExchangeDigest(hash), byteLength: size)
    }
    guard LibraryExchangeCatalog.inventoryDigest(entries) == candidate.package,
      entries.first(where: { $0.path == "data/exchange.json" })?.digest == candidate.index else { throw DrawingLibraryError.invalidIdentity }
    return try VerifiedExchangeFiles(catalogRoot: directoryURL, inventory: entries.map {
      .init(path: $0.path, storagePath: "objects/sha256/" + $0.digest.description, digest: $0.digest, byteLength: $0.byteLength)
    })
  }
  /// Selects a supported authored context, not a result delivery. Unsupported
  /// contexts remain independently inspectable/exportable through their result
  /// handles. Integrity failures are never treated as unsupported semantics.
  package func selectedDrawingPublication(for ref: DrawingRef, database db: DrawingLibraryDatabase) throws -> SelectedDrawingAdmission {
    var reason = "No supported Drawing publication context"
    let candidates = try publicationCandidates(.drawing(ref), database: db)
    guard !candidates.isEmpty else { throw DrawingLibraryError.missing(ref) }
    for candidate in candidates {
      let files = try publicationFiles(candidate, database: db)
      let index = try files.record(at: "data/exchange.json")
      guard ExchangeDigest.hash(index) == candidate.index else { throw DrawingLibraryError.invalidIdentity }
      do {
        let proof = try ExchangeAdmission.selectDrawing(originalIndexJSON: index, selected: ref, files: files, producerValidators: producerValidators)
        if case .materialized = proof.admission { return proof }
        reason = proof.capabilities.unsupportedReasons.first ?? "Opaque drawing representation"
      } catch DrawingExchangeError.unsupportedProfile(let profile) {
        reason = profile
      }
    }
    throw DrawingLibraryError.unsupportedFeature(reason)
  }

  public func drawings(limit: Int = 50, after: DrawingLibraryCursor? = nil) throws -> DrawingLibraryPage {
    try drawings(in: .all, limit: limit, after: after)
  }
  public func drawings(in scope: DrawingLibraryDrawingScope, limit: Int = 50, after: DrawingLibraryCursor? = nil) throws -> DrawingLibraryPage {
    guard limit > 0, limit <= 500 else { throw DrawingLibraryError.invalidQuery }
    if let after, after.scope != scope { throw DrawingLibraryError.invalidQuery }
    guard let db = try commonReadDatabase(), try tableExists("dx_drawing_summary",in:db) else { return .init(entries:[],next:nil) }
    return try commonSnapshot(db) { db in
      let generation = try db.generation
      if let after, after.generation != generation { throw DrawingLibraryError.staleSelection }
      var predicate = "WHERE COALESCE(m.tombstoned,0)=0", values: [String?] = []
      switch scope {
      case .all: break
      case .photo(let ref):
        try assertSourceReference(.photo(ref), database: db)
        predicate += " AND (s.namespace,s.identity) IN (SELECT d.source_namespace,d.source_identity FROM dx_link i JOIN dx_link d ON d.target_kind='input' AND d.target_namespace=i.source_namespace AND d.target_identity=i.source_identity AND d.relation='input' AND d.source_kind='drawing' WHERE i.source_kind='input' AND i.relation='photo' AND i.target_kind='photo' AND i.target_namespace=? AND i.target_identity=?)"
        values += [ref.issuer.uuidString.lowercased(), ref.revision.uuidString.lowercased()]
      case .input(let ref):
        try assertSourceReference(.input(ref), database: db)
        predicate += " AND (s.namespace,s.identity) IN (SELECT d.source_namespace,d.source_identity FROM dx_link d WHERE d.source_kind='drawing' AND d.relation='input' AND d.target_kind='input' AND d.target_namespace=? AND d.target_identity=?)"
        values += [ref.issuer.uuidString.lowercased(), ref.revision.uuidString.lowercased()]
      case .children(let ref):
        try assertSourceReference(.drawing(ref), database: db)
        predicate += " AND (s.namespace,s.identity) IN (SELECT d.source_namespace,d.source_identity FROM dx_link d WHERE d.source_kind='drawing' AND d.relation='parent' AND d.target_kind='drawing' AND d.target_namespace=? AND d.target_identity=?)"
        values += [ref.issuer.uuidString.lowercased(), ref.revision.uuidString.lowercased()]
      }
      func readPage(_ range: String, _ arguments: [String?], count: Int) throws -> [[String?]] {
        try db.rows("SELECT s.namespace,s.identity,s.digest,s.program_digest,printf('%!.17g',s.created_at),s.stroke_count,s.point_count,m.payload FROM dx_drawing_summary s LEFT JOIN dx_metadata m ON m.kind='drawing' AND m.namespace=s.namespace AND m.identity=s.identity " + predicate + range + " ORDER BY s.created_at DESC,s.namespace ASC,s.identity ASC LIMIT ?", values + arguments + [String(count)], work: { steps, scans in
          DrawingLibraryDiagnostics.shared.record("drawingPageVMSteps", count: UInt64(max(0, steps)))
          DrawingLibraryDiagnostics.shared.record("drawingPageFullscanSteps", count: UInt64(max(0, scans)))
        })
      }
      let rows: [[String?]]
      if let after {
        // Mixed DESC-date/ASC-identity order cannot use one tuple comparison.
        // The former OR predicate scanned from the index head (or the start of
        // a large date tie). Two disjoint ranges seek directly into that order.
        let tied = try readPage(" AND s.created_at=CAST(? AS REAL) AND (s.namespace,s.identity)>(?,?)",
          [after.date, after.issuer, after.revision], count: limit + 1)
        let remaining = limit + 1 - tied.count
        let older = remaining > 0
          ? try readPage(" AND s.created_at<CAST(? AS REAL)", [after.date], count: remaining) : []
        rows = tied + older
      } else { rows = try readPage("", [], count: limit + 1) }
      let page = Array(rows.prefix(limit))
      let entries = try page.map { row -> DrawingLibraryEntry in
        guard let issuer=row[0].flatMap(UUID.init(uuidString:)), let revision=row[1].flatMap(UUID.init(uuidString:)), let digest=row[2],let program=row[3],let count=row[5].flatMap(Int.init),let points=row[6].flatMap(Int.init) else { throw DrawingLibraryError.invalidIdentity }
        let metadata = try row[7].map { try JSONDecoder().decode(LibraryExchangeMetadata.self,from:Data($0.utf8)) }
        let ref=DrawingRef(issuer:issuer,revision:revision,digest:try ExchangeDigest(digest))
        if let metadata,metadata.reference != .drawing(ref) { throw DrawingLibraryError.invalidIdentity }
        return .init(reference:ref,title:metadata?.title,createdAt:row[4].flatMap(Double.init).map(Date.init(timeIntervalSince1970:)),programDigest:try ExchangeDigest(program),strokeCount:count,pointCount:points)
      }
      let next:DrawingLibraryCursor? = rows.count > limit ? .init(generation:generation,date:page.last![4]!,issuer:page.last![0]!,revision:page.last![1]!,scope:scope) : nil
      return .init(entries:entries,next:next)
    }
  }
}
