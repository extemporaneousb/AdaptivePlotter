import PortraitArtists
import CSQLite
import Foundation
import PlotterModel
import PlotterRuntime

package struct PreparedPortraitOccurrence {
  package let candidate: StoredCandidate
  package let reference: IndexedEntry
  package let summary: SavedDrawingSummary
  package let saved: Bool

  package init(candidate: StoredCandidate, reference: IndexedEntry, summary: SavedDrawingSummary, saved: Bool) {
    self.candidate = candidate
    self.reference = reference
    self.summary = summary
    self.saved = saved
  }
}

/// A connection is confined to the PortraitCandidateStore actor. Independent
/// legacy-compatible catalog reads open read-only connections and transactions.
package final class PortraitLibraryDatabase {
  package let url: URL
  private var db: OpaquePointer?
  private let encoder = PortraitCandidateCoding.encoder()
  package enum Fault: String { case beforeCommit, afterCommit }
  package var injectFault: ((Fault) throws -> Void)?
  package static func hasCommittedGeneration(at url: URL) throws -> Bool {
    guard FileManager.default.fileExists(atPath:url.path) else { return false }
    let connection = try PortraitLibraryDatabase(url:url,readOnly:true)
    return try connection.scalar("SELECT value FROM state WHERE key='portrait_graph_selected'") == "1"
  }

  package init(url: URL, readOnly: Bool = false) throws {
    self.url = url
    if !readOnly { try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true) }
    let flags = (readOnly ? SQLITE_OPEN_READONLY : SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE) | SQLITE_OPEN_FULLMUTEX
    guard sqlite3_open_v2(url.path, &db, flags, nil) == SQLITE_OK else { throw failure() }
    sqlite3_busy_timeout(db, 5000)
    try execute("PRAGMA foreign_keys=ON")
    guard try scalar("PRAGMA foreign_keys") == "1" else { throw PortraitLibraryError.database("foreign key enforcement unavailable") }
    let existingVersion = try scalar("PRAGMA user_version")
    guard existingVersion == "0" || existingVersion == "1" || existingVersion == "2" else { throw PortraitLibraryError.database("unsupported schema") }
    if !readOnly {
      try execute("PRAGMA journal_mode=DELETE")
      try execute("PRAGMA synchronous=FULL")
      if existingVersion == "0" { try execute(Self.schema) }
    }
    guard let version = try scalar("PRAGMA user_version"), version == "1" || version == "2" else {
      throw PortraitLibraryError.database("unsupported schema")
    }
  }
  deinit { sqlite3_close(db) }

  private func failure() -> PortraitLibraryError {
    .database(db.map { String(cString: sqlite3_errmsg($0)) } ?? "connection unavailable")
  }
  package func execute(_ sql: String, _ values: [String?] = []) throws {
    if values.isEmpty {
      guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else { throw failure() }
      return
    }
    let stmt = try prepare(sql, values)
    defer { sqlite3_finalize(stmt) }
    guard sqlite3_step(stmt) == SQLITE_DONE else { throw failure() }
  }
  private func prepare(_ sql: String, _ values: [String?]) throws -> OpaquePointer {
    var stmt: OpaquePointer?
    guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else { throw failure() }
    let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    for (index, value) in values.enumerated() {
      let code = value.map { sqlite3_bind_text(stmt, Int32(index + 1), $0, -1, transient) }
        ?? sqlite3_bind_null(stmt, Int32(index + 1))
      guard code == SQLITE_OK else { sqlite3_finalize(stmt); throw failure() }
    }
    return stmt
  }
  package func rows(_ sql: String, _ values: [String?] = []) throws -> [[String?]] {
    let stmt = try prepare(sql, values)
    defer { sqlite3_finalize(stmt) }
    var result: [[String?]] = []
    while true {
      let code = sqlite3_step(stmt)
      if code == SQLITE_DONE { return result }
      guard code == SQLITE_ROW else { throw failure() }
      result.append((0..<sqlite3_column_count(stmt)).map { index in
        sqlite3_column_type(stmt, index) == SQLITE_NULL ? nil
          : String(cString: sqlite3_column_text(stmt, index))
      })
    }
  }
  package func scalar(_ sql: String, _ values: [String?] = []) throws -> String? { try rows(sql, values).first?.first ?? nil }
  package func encode<T: Encodable>(_ value: T) throws -> String { String(decoding: try encoder.encode(value), as: UTF8.self) }
  package func decode<T: Decodable>(_ type: T.Type, _ value: String?) throws -> T {
    guard let value else { throw PortraitLibraryError.database("required payload missing") }
    return try JSONDecoder().decode(type, from: Data(value.utf8))
  }
  package func transaction<T>(_ operation: () throws -> T) throws -> T {
    try execute("BEGIN IMMEDIATE")
    do {
      let value = try operation()
      try injectFault?(.beforeCommit)
      try execute("COMMIT")
      try injectFault?(.afterCommit)
      return value
    } catch { try? execute("ROLLBACK"); throw error }
  }
  package func integrityCheck() throws {
    guard try scalar("PRAGMA integrity_check") == "ok", try rows("PRAGMA foreign_key_check").isEmpty else {
      throw PortraitLibraryError.database("integrity or foreign key check failed")
    }
  }
  package var generation: PortraitLibraryGeneration {
    get throws {
      .init(revision: Int64(try scalar("SELECT value FROM state WHERE key='revision'") ?? "0") ?? 0,
        legacyPortraitSHA256: try scalar("SELECT value FROM state WHERE key='legacy_hash'"),
        evidenceSHA256: try scalar("SELECT value FROM state WHERE key='evidence_hash'"))
    }
  }
  package func setState(_ key: String, _ value: String?) throws {
    if let value { try execute("INSERT INTO state(key,value) VALUES(?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value", [key,value]) }
    else { try execute("DELETE FROM state WHERE key=?", [key]) }
  }
  package func workProjection(_ id: String) throws -> PortraitLibraryWork {
    guard let row = try rows("SELECT w.id,w.drawing_id,d.photo_id,w.run_id,w.record_id,w.executed,w.source_generation,w.payload,d.summary,p.reference,d.candidate_id FROM work w JOIN drawing d ON d.id=w.drawing_id JOIN photo p ON p.id=d.photo_id WHERE w.id=?",[id]).first,
      let photoID = UUID(uuidString:row[2]!),let run = UUID(uuidString:row[3]!) else { throw PortraitLibraryError.missingDrawing }
    let payload = try decode(PortraitLibraryWork.self,row[7])
    guard payload.id == row[0],payload.drawingID == row[1],payload.photoID == photoID,payload.runID.rawValue == run,
      payload.recordID?.description == row[4],payload.executedOrPossibleInk == (row[5] == "1"),payload.sourceGeneration == row[6] else { throw PortraitLibraryError.database("work payload conflicts with foreign key ancestry") }
    let media = try rows("SELECT id,work_id,source_generation,asset_hash,payload FROM media WHERE work_id=? ORDER BY id",[id]).map { child -> PortraitLibraryMedia in
      let value = try decode(PortraitLibraryMedia.self,child[4])
      guard value.id == child[0],child[1] == id,child[2] == row[6],value.reference.frame.frameSHA256 == child[3] else { throw PortraitLibraryError.database("media payload conflicts with foreign key ancestry") }
      return value
    }
    guard Set(payload.media.map(\.id)).count == payload.media.count else { throw PortraitLibraryError.database("duplicate work media identity") }
    guard Dictionary(uniqueKeysWithValues:media.map{($0.id,$0)}) == Dictionary(uniqueKeysWithValues:payload.media.map{($0.id,$0)}) else { throw PortraitLibraryError.database("work media list conflicts with normalized children") }
    let descriptor = try checkedDrawing(row[1]!)
    let summary = descriptor.summary,photo = try checkedPhoto(row[2]!)
    guard summary.id == row[10],summary.photoID == photoID,photo.id == photoID,summary.sourceSHA256 == photo.sourceSHA256 else { throw PortraitLibraryError.database("drawing/photo metadata conflicts with normalized ancestry") }
    var result = PortraitLibraryWork(id:row[0]!,drawingID:row[1]!,photoID:photoID,runID:RunID(run),
      recordID:row[4].flatMap(UUID.init(uuidString:)).map{DrawingEvidenceRecordID($0)},status:payload.status,recordedAt:payload.recordedAt,
      executedOrPossibleInk:row[5] == "1",sourceGeneration:row[6]!,media:media,recoveryMethod:payload.recoveryMethod)
    result.drawingTitle = summary.title;result.sourcePhotoReference = photo
    result.drawingIdentity = .init(candidateID:row[10]!,photoID:photoID)
    return result
  }
  package func bumpRevision() throws { try setState("revision", String((try generation).revision + 1)) }
  package func checkedPhoto(_ id:String) throws -> PortraitPhotoReference {
    guard let row = try rows("SELECT id,source_hash,reference FROM photo WHERE id=?",[id]).first else { throw PortraitLibraryError.missingPhoto }
    let reference = try decode(PortraitPhotoReference.self,row[2])
    guard reference.id.uuidString.lowercased() == row[0],reference.sourceSHA256 == row[1] else { throw PortraitLibraryError.database("photo metadata conflicts with normalized identity") }
    return reference
  }
  package func checkedDrawing(_ id:String) throws -> PortraitLibraryDrawing {
    guard let row = try rows("SELECT candidate_id,photo_id,source_hash,program_hash,summary,candidate_record,historical_record,recovery_method,proof_hash FROM drawing WHERE id=?",[id]).first,
      let photo = UUID(uuidString:row[1]!) else { throw PortraitLibraryError.missingDrawing }
    guard PortraitDrawingIdentity(candidateID:row[0]!,photoID:photo).id == id else { throw PortraitLibraryError.database("drawing occurrence key conflicts with ancestry") }
    let summary = try decode(SavedDrawingSummary.self,row[4]),reference = try checkedPhoto(row[1]!)
    guard summary.id == row[0],summary.photoID == photo,summary.sourceSHA256 == row[2],reference.sourceSHA256 == row[2],summary.programContentHash == row[3] else { throw PortraitLibraryError.database("drawing metadata conflicts with normalized identity") }
    if let historicalHash = row[6] {
      guard historicalHash.count == 64,historicalHash.allSatisfy(\.isHexDigit),row[7]?.isEmpty == false,row[8]?.count == 64 else { throw PortraitLibraryError.database("historical payload reference invalid") }
    }
    return .init(identity:.init(candidateID:row[0]!,photoID:photo),summary:summary,isRenderable:row[5] != nil,recoveryMethod:row[7])
  }

  package func index() throws -> IndexedArchive {
    try execute("BEGIN")
    defer { try? execute("ROLLBACK") }
    let entries = try rows("SELECT candidate_id,candidate_record,metadata_record FROM drawing WHERE canonical=1 AND deleted=0 AND candidate_record IS NOT NULL ORDER BY ordinal")
      .map { row in IndexedEntry(candidateID: row[0]!, candidateSHA256: row[1]!, metadataSHA256: row[2]!) }
    let tombstones = try decode([PortraitArchiveTombstone].self,try scalar("SELECT value FROM state WHERE key='tombstones'") ?? "[]")
    let labelRows = try rows("SELECT l.id,l.record_hash,d.id,d.photo_id FROM label l JOIN drawing d ON d.id=l.drawing_id ORDER BY l.ordinal")
    let labels = try labelRows.map { row -> LabelReference in
      guard let id = UUID(uuidString:row[0]!) else { throw PortraitLibraryError.database("invalid label identity") }
      return .init(id:id,sha256:row[1]!)
    } + rows("SELECT id,record_hash FROM withdrawn_label").map { row -> LabelReference in
      guard let id = UUID(uuidString:row[0]!) else { throw PortraitLibraryError.database("invalid withdrawn label identity") }
      return .init(id:id,sha256:row[1]!)
    }
    let photos = try rows("SELECT id FROM photo WHERE deleted=0 ORDER BY captured_at DESC,id").map { try checkedPhoto($0[0]!) }
    let summaries = try rows("SELECT id FROM drawing WHERE canonical=1 AND deleted=0 ORDER BY created_at DESC,id").map { try checkedDrawing($0[0]!).summary }
    let generic = try rows("SELECT reference,summary FROM generic_drawing ORDER BY ordinal")
    let saved = try (rows("SELECT candidate_id FROM drawing WHERE canonical=1 AND deleted=0 AND saved=1").map { SavedDrawingRecordReference(id:$0[0]!,candidateID:$0[0]!,recordSHA256:nil) }
      + generic.map { try decode(SavedDrawingRecordReference.self,$0[0]) })
    var result = IndexedArchive(schemaVersion:4, entries:entries,labels:labels,
      tombstones:tombstones,
      savedStyles:try scalar("SELECT value FROM state WHERE key='styles'").map { try decode([PortraitSavedStyle].self,$0) }, sourcePhotos:photos)
    result.labelPhotoIDs = labelRows.isEmpty ? nil : try Dictionary(uniqueKeysWithValues:labelRows.map { row in
      guard let label = UUID(uuidString:row[0]!),let photo = UUID(uuidString:row[3]!) else { throw PortraitLibraryError.database("invalid label capture identity") }
      return (label.uuidString.lowercased(),photo)
    })
    result.photoCatalog = photos; result.savedDrawings = saved
    result.drawingCatalog = summaries + (try generic.map { try decode(SavedDrawingSummary.self,$0[1]) })
    return result
  }

  /// Assets/records must already be synchronized by the facade. This is the
  /// sole atomic selector of a complete valid graph, never a flat writable index.
  package func commit(index: IndexedArchive, candidates: [String: StoredCandidate], occurrences: [PreparedPortraitOccurrence], legacyHash: String?, expected: PortraitLibraryGeneration?, mode: PortraitCandidateSaveMode = .fullArchive) throws {
    try transaction {
      if let expected, try generation != expected { throw PortraitLibraryError.staleGeneration }
      let previous = try decode([PortraitArchiveTombstone].self, try scalar("SELECT value FROM state WHERE key='tombstones'") ?? "[]")
      let tombstones = previous + index.tombstones.filter { candidate in !previous.contains(where:{$0.id == candidate.id}) }
      for tombstone in tombstones {
        let affected: [[String?]]
        switch tombstone.kind {
        case .photo: affected = try rows("SELECT id FROM drawing WHERE photo_id=?",[tombstone.identity.lowercased()])
        case .drawing: affected = try rows("SELECT id FROM drawing WHERE id=? AND created_at<=?",[tombstone.identity.lowercased(),String(tombstone.createdAt.timeIntervalSince1970)])
        case .candidate:
          affected = try Set(tombstone.affectedCandidateIDs + [tombstone.identity]).flatMap {
            try rows("SELECT id FROM drawing WHERE candidate_id=? AND created_at<=?",[$0,String(tombstone.createdAt.timeIntervalSince1970)])
          }
        case .source: affected = try rows("SELECT id FROM drawing WHERE source_hash=? AND created_at<=?",[tombstone.identity,String(tombstone.createdAt.timeIntervalSince1970)])
        case .label: affected = []
        }
        for row in affected {
          let drawingID = row[0]!
          let runs = try rows("SELECT run_id FROM work WHERE drawing_id=? UNION SELECT run_id FROM run_binding WHERE drawing_id=?",[drawingID,drawingID])
          for run in runs { try setState("catalog_hidden_run:"+run[0]!,"1") }
          try execute("UPDATE work SET deleted=1 WHERE drawing_id=?",[drawingID])
        }
      }
      for photo in index.sourcePhotos ?? [] {
        var retainedPhoto = photo
        if let old = try scalar("SELECT reference FROM photo WHERE id=?",[photo.id.uuidString.lowercased()]) {
          let previous = try decode(PortraitPhotoReference.self,old)
          if !(photo.captureTimeKnown ?? (photo.candidateRecordSHA256 == nil)),previous.candidateRecordSHA256 != nil {
            retainedPhoto.candidateRecordSHA256 = previous.candidateRecordSHA256
            retainedPhoto.captureTimeKnown = false
          }
        }
        if let hash = try scalar("SELECT source_hash FROM photo WHERE id=?",[photo.id.uuidString.lowercased()]), hash != photo.sourceSHA256 { throw PortraitLibraryError.unresolvedLineage("capture identity changed") }
        try execute("INSERT INTO photo(id,source_hash,reference,captured_at) VALUES(?,?,?,?) ON CONFLICT(id) DO UPDATE SET reference=excluded.reference",[photo.id.uuidString.lowercased(),photo.sourceSHA256,try encode(retainedPhoto),String(photo.capturedAt.timeIntervalSince1970)])
      }
      let summaries = Dictionary(uniqueKeysWithValues:(index.drawingCatalog ?? []).map{($0.id,$0)})
      let snapshotOrdinals = Dictionary(uniqueKeysWithValues:index.entries.enumerated().map { ($0.element.candidateID,$0.offset) })
      var nextDeltaOrdinal = (Int(try scalar("SELECT MAX(ordinal) FROM drawing") ?? "-1") ?? -1) + 1
      var orderedOccurrences = occurrences
      if case .mutationDelta = mode {
        orderedOccurrences = occurrences.enumerated().sorted { left,right in
          let leftOrder = snapshotOrdinals[left.element.candidate.id] ?? index.entries.count+left.offset
          let rightOrder = snapshotOrdinals[right.element.candidate.id] ?? index.entries.count+right.offset
          return leftOrder == rightOrder ? left.offset < right.offset : leftOrder < rightOrder
        }.map { $0.element }
      }
      for (ordinal,prepared) in orderedOccurrences.enumerated() {
        let candidate = prepared.candidate,entry = prepared.reference
        var summary = prepared.summary
        let identity = PortraitDrawingIdentity(candidateID:candidate.id,photoID:candidate.photoID)
        let canonical = try scalar("SELECT id FROM drawing WHERE candidate_id=? AND canonical=1",[candidate.id]) == nil
        var saved = prepared.saved
        var replacing = false
        var previousOrdinal: Int?
        if let old = try rows("SELECT program_hash,source_hash,raster_hash,recipe_hash,candidate_record,saved,metadata_record,summary,created_at,ordinal FROM drawing WHERE id=?",[identity.id]).first {
          previousOrdinal = old[9].flatMap(Int.init)
          guard old[0] == candidate.program.contentHash.description,old[1] == candidate.sourceSHA256,
            old[2] == candidate.rasterSHA256,old[3] == candidate.recipeSHA256 else { throw PortraitLibraryError.unresolvedLineage("immutable drawing occurrence changed") }
          if old[4] != entry.candidateSHA256 {
            let oldBytes = try Data(contentsOf:url.deletingLastPathComponent().appendingPathComponent("records").appendingPathComponent(old[4]!))
            guard PortraitCandidateCoding.digest(oldBytes) == old[4] else { throw PortraitLibraryError.database("retired immutable record checksum failed") }
            let oldCandidate = try JSONDecoder().decode(StoredCandidate.self,from:oldBytes)
            // The facade validated synchronized incoming bytes before this transaction.
            let newBytes = try Data(contentsOf:url.deletingLastPathComponent().appendingPathComponent("records").appendingPathComponent(entry.candidateSHA256))
            guard PortraitCandidateCoding.digest(newBytes) == entry.candidateSHA256 else { throw PortraitLibraryError.database("new immutable record checksum failed") }
            let replacement = try JSONDecoder().decode(StoredCandidate.self,from:newBytes)
            guard oldCandidate.id == replacement.id,oldCandidate.photoID == replacement.photoID,
              oldCandidate.captureSessionID == replacement.captureSessionID,oldCandidate.program == replacement.program,
              tombstones.contains(where:{ tombstone in
                let matches = tombstone.kind == .drawing ? tombstone.identity.lowercased() == identity.id
                  : tombstone.kind == .candidate && (tombstone.identity == candidate.id || tombstone.affectedCandidateIDs.contains(candidate.id))
                return matches && oldCandidate.createdAt <= tombstone.createdAt && replacement.createdAt > tombstone.createdAt
              }) else { throw PortraitLibraryError.unresolvedLineage("immutable drawing occurrence changed") }
            let retired = ["identity":identity.id,"candidateRecordSHA256":old[4]!,"metadataRecordSHA256":old[6]!,"summary":old[7]!,"createdAt":old[8]!]
            try setState("retired_drawing:"+identity.id+":"+old[4]!,try encode(retired))
            replacing = true
          }
          saved = saved || (!replacing && old[5] == "1")
          if saved != prepared.saved {
            summary = .init(id:summary.id,title:summary.title,createdAt:summary.createdAt,
              programContentHash:summary.programContentHash,programKind:summary.programKind,strokeCount:summary.strokeCount,
              strokeStyle:summary.strokeStyle,pose:summary.pose,photoID:summary.photoID,sourceSHA256:summary.sourceSHA256,
              recipe:summary.recipe,isSaved:saved,feedback:summary.feedback)
          }
        }
        let conflictUpdate = replacing
          ? "candidate_record=excluded.candidate_record,metadata_record=excluded.metadata_record,saved=excluded.saved,summary=excluded.summary,created_at=excluded.created_at,deleted=0,ordinal=excluded.ordinal"
          : "metadata_record=excluded.metadata_record,saved=excluded.saved,summary=excluded.summary"
        let cacheOrdinal: Int
        if case .mutationDelta = mode {
          if let previousOrdinal,!replacing { cacheOrdinal = previousOrdinal }
          else { cacheOrdinal = nextDeltaOrdinal;nextDeltaOrdinal += 1 }
        } else { cacheOrdinal = snapshotOrdinals[candidate.id] ?? index.entries.count+ordinal }
        try execute("INSERT INTO drawing(id,candidate_id,photo_id,source_hash,program_hash,candidate_record,metadata_record,raster_hash,recipe_hash,summary,created_at,saved,canonical,ordinal) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?) ON CONFLICT(id) DO UPDATE SET "+conflictUpdate,[identity.id,candidate.id,candidate.photoID.uuidString.lowercased(),candidate.sourceSHA256,candidate.program.contentHash.description,entry.candidateSHA256,entry.metadataSHA256,candidate.rasterSHA256,candidate.recipeSHA256,try encode(summary),String(candidate.createdAt.timeIntervalSince1970),saved ? "1":"0",canonical ? "1":"0",String(cacheOrdinal)])
      }
      for (ordinal,label) in index.labels.enumerated() {
        // Exact label candidate association is verified by the facade.
        let bytes = try Data(contentsOf:url.deletingLastPathComponent().appendingPathComponent("records").appendingPathComponent(label.sha256))
        let payload = try JSONDecoder().decode(PortraitLabelRevision.self,from:bytes)
        if let existing = try rows("SELECT l.drawing_id,l.record_hash,d.photo_id FROM label l JOIN drawing d ON d.id=l.drawing_id WHERE l.id=?",[label.id.uuidString]).first {
          if let requested = index.labelPhotoIDs?[label.id.uuidString.lowercased()],requested.uuidString.lowercased() != existing[2] { throw PortraitLibraryError.database("immutable label capture changed") }
          guard existing[1] == label.sha256 else { throw PortraitLibraryError.database("immutable label changed") }
          continue
        }
        let photo = index.labelPhotoIDs?[label.id.uuidString.lowercased()] ?? (legacyHash == nil ? nil : candidates[payload.candidateID]?.photoID)
        let authoredOccurrence = photo.map { PortraitDrawingIdentity(candidateID:payload.candidateID,photoID:$0).id }
        let drawing = authoredOccurrence
        guard let drawing else {
          if tombstones.contains(where:{$0.affectedCandidateIDs.contains(payload.candidateID) || ($0.kind == .label && $0.identity == label.id.uuidString)}) {
            try execute("INSERT OR IGNORE INTO withdrawn_label(id,record_hash) VALUES(?,?)",[label.id.uuidString,label.sha256]);continue
          }
          throw PortraitLibraryError.missingDrawing
        }
        let authored = try checkedDrawing(drawing)
        guard authored.summary.programContentHash == payload.programContentHash else { throw PortraitLibraryError.database("label program conflicts with exact drawing occurrence") }
        if let previous = payload.previousRevisionID,
          let prior = try rows("SELECT d.photo_id,d.candidate_id FROM label l JOIN drawing d ON d.id=l.drawing_id WHERE l.id=?",[previous.uuidString]).first {
          guard prior[0] == photo?.uuidString.lowercased(),prior[1] == payload.candidateID else { throw PortraitLibraryError.database("label revision crosses capture occurrences") }
        }
        try execute("INSERT INTO label(id,drawing_id,record_hash,ordinal) VALUES(?,?,?,?)",[label.id.uuidString,drawing,label.sha256,String(ordinal)])
      }
      if case .fullArchive = mode { try execute("DELETE FROM generic_drawing") }
      for (ordinal,reference) in (index.savedDrawings ?? []).filter({$0.candidateID == nil}).enumerated() {
        guard let summary = summaries[reference.id] else { throw PortraitLibraryError.missingDrawing }
        try execute("INSERT INTO generic_drawing(id,reference,summary,ordinal) VALUES(?,?,?,?) ON CONFLICT(id) DO UPDATE SET reference=excluded.reference,summary=excluded.summary",[reference.id,try encode(reference),try encode(summary),String(ordinal)])
      }
      for tombstone in tombstones {
        switch tombstone.kind {
        case .photo:
          try execute("UPDATE drawing SET deleted=1 WHERE photo_id=?",[tombstone.identity.lowercased()])
          try execute("UPDATE photo SET deleted=1 WHERE id=?",[tombstone.identity.lowercased()])
        case .source:
          try execute("UPDATE drawing SET deleted=1 WHERE source_hash=? AND created_at<=?",[tombstone.identity,String(tombstone.createdAt.timeIntervalSince1970)])
          try execute("UPDATE photo SET deleted=1 WHERE source_hash=? AND captured_at<=?",[tombstone.identity,String(tombstone.createdAt.timeIntervalSince1970)])
        case .drawing:
          try execute("UPDATE drawing SET deleted=1 WHERE id=? AND created_at<=?",[tombstone.identity.lowercased(),String(tombstone.createdAt.timeIntervalSince1970)])
        case .candidate:
          for id in Set(tombstone.affectedCandidateIDs + [tombstone.identity]) { try execute("UPDATE drawing SET deleted=1 WHERE candidate_id=? AND created_at<=?",[id,String(tombstone.createdAt.timeIntervalSince1970)]) }
          for id in Set(tombstone.affectedCandidateIDs + [tombstone.identity]) {
            if let encoded = try scalar("SELECT summary FROM generic_drawing WHERE id=?",[id]),
              try decode(SavedDrawingSummary.self,encoded).createdAt <= tombstone.createdAt {
              try execute("DELETE FROM generic_drawing WHERE id=?",[id])
            }
          }
        case .label:
          // Withdrawn immutable revisions remain ancestry nodes. Eligibility
          // is determined by the explicit tombstone, never row disappearance.
          break
        }
      }
      // Canonical is an adapter choice for the existing one-candidate cache.
      // It never changes the immutable capture association of an occurrence.
      try execute("UPDATE drawing SET canonical=0 WHERE deleted=1 OR candidate_record IS NULL")
      try execute("UPDATE drawing SET canonical=1 WHERE deleted=0 AND candidate_record IS NOT NULL AND id=(SELECT chosen.id FROM drawing chosen WHERE chosen.candidate_id=drawing.candidate_id AND chosen.deleted=0 AND chosen.candidate_record IS NOT NULL ORDER BY chosen.canonical DESC,chosen.ordinal,chosen.id LIMIT 1)")
      try setState("tombstones",try encode(tombstones))
      if case .fullArchive = mode { try setState("styles",try index.savedStyles.map { try encode($0) }) }
      else if let styles = index.savedStyles { try setState("styles",try encode(styles)) }
      if let legacyHash { try setState("legacy_hash",legacyHash);try setState("canonical_library_dirty",nil) }
      else { try setState("canonical_library_dirty","1") }
      try setState("portrait_graph_selected","1")
      try bumpRevision();try integrityCheck()
    }
  }

  package func backup(to destination: URL) throws {
    var target: OpaquePointer?
    guard sqlite3_open_v2(destination.path,&target,SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE,nil) == SQLITE_OK, let target else { throw failure() }
    defer { sqlite3_close(target) }
    func targetForeignKeysEnabled() -> Bool {
      var statement: OpaquePointer?
      guard sqlite3_prepare_v2(target,"PRAGMA foreign_keys",-1,&statement,nil) == SQLITE_OK,let statement else { return false }
      defer { sqlite3_finalize(statement) }
      return sqlite3_step(statement) == SQLITE_ROW && sqlite3_column_int(statement,0) == 1
    }
    guard sqlite3_exec(target,"PRAGMA foreign_keys=ON",nil,nil,nil) == SQLITE_OK,targetForeignKeysEnabled() else {
      throw PortraitLibraryError.database("backup destination foreign key enforcement unavailable")
    }
    guard let backup = sqlite3_backup_init(target,"main",db,"main") else { throw failure() }
    let code = sqlite3_backup_step(backup,-1);let finish = sqlite3_backup_finish(backup)
    guard code == SQLITE_DONE,finish == SQLITE_OK else { throw PortraitLibraryError.database("backup failed") }
    guard targetForeignKeysEnabled() else { throw PortraitLibraryError.database("backup destination foreign key enforcement changed") }
  }

  private static let schema = """
  CREATE TABLE IF NOT EXISTS state(key TEXT PRIMARY KEY,value TEXT NOT NULL);
  CREATE TABLE IF NOT EXISTS photo(id TEXT PRIMARY KEY,source_hash TEXT NOT NULL,reference TEXT NOT NULL,captured_at REAL NOT NULL,deleted INTEGER NOT NULL DEFAULT 0,UNIQUE(id,source_hash));
  CREATE TABLE IF NOT EXISTS drawing(id TEXT PRIMARY KEY,candidate_id TEXT NOT NULL,photo_id TEXT NOT NULL,source_hash TEXT NOT NULL,program_hash TEXT NOT NULL,candidate_record TEXT,metadata_record TEXT,historical_record TEXT,recovery_method TEXT,proof_hash TEXT,raster_hash TEXT,recipe_hash TEXT,summary TEXT NOT NULL,created_at REAL NOT NULL,saved INTEGER NOT NULL DEFAULT 0,canonical INTEGER NOT NULL DEFAULT 0,ordinal INTEGER NOT NULL DEFAULT 0,deleted INTEGER NOT NULL DEFAULT 0,UNIQUE(candidate_id,photo_id),FOREIGN KEY(photo_id,source_hash) REFERENCES photo(id,source_hash) ON DELETE RESTRICT,CHECK((candidate_record IS NOT NULL AND metadata_record IS NOT NULL AND raster_hash IS NOT NULL AND recipe_hash IS NOT NULL) OR historical_record IS NOT NULL));
  CREATE UNIQUE INDEX IF NOT EXISTS canonical_candidate ON drawing(candidate_id) WHERE canonical=1;
  CREATE INDEX IF NOT EXISTS drawings_by_photo ON drawing(photo_id,deleted);
  CREATE TABLE IF NOT EXISTS label(id TEXT PRIMARY KEY,drawing_id TEXT NOT NULL REFERENCES drawing(id) ON DELETE RESTRICT,record_hash TEXT NOT NULL,ordinal INTEGER NOT NULL);
  CREATE TABLE IF NOT EXISTS withdrawn_label(id TEXT PRIMARY KEY,record_hash TEXT NOT NULL);
  CREATE TABLE IF NOT EXISTS generic_drawing(id TEXT PRIMARY KEY,reference TEXT NOT NULL,summary TEXT NOT NULL,ordinal INTEGER NOT NULL);
  CREATE TABLE IF NOT EXISTS work(id TEXT PRIMARY KEY,drawing_id TEXT NOT NULL REFERENCES drawing(id) ON DELETE RESTRICT,run_id TEXT NOT NULL UNIQUE,record_id TEXT,executed INTEGER NOT NULL,source_generation TEXT NOT NULL,payload TEXT NOT NULL,deleted INTEGER NOT NULL DEFAULT 0);
  CREATE INDEX IF NOT EXISTS works_by_drawing ON work(drawing_id,executed,deleted);
  CREATE TABLE IF NOT EXISTS media(id TEXT PRIMARY KEY,work_id TEXT NOT NULL REFERENCES work(id) ON DELETE RESTRICT,source_generation TEXT NOT NULL,asset_hash TEXT NOT NULL,payload TEXT NOT NULL);
  CREATE TABLE IF NOT EXISTS lineage_receipt(run_id TEXT PRIMARY KEY,drawing_id TEXT NOT NULL REFERENCES drawing(id) ON DELETE RESTRICT,record_hash TEXT NOT NULL,program_hash TEXT NOT NULL,source_hash TEXT NOT NULL,method TEXT NOT NULL,audit_hash TEXT NOT NULL);
  CREATE TABLE IF NOT EXISTS run_binding(run_id TEXT PRIMARY KEY,drawing_id TEXT NOT NULL REFERENCES drawing(id) ON DELETE RESTRICT,intent_hash TEXT NOT NULL);
  CREATE TABLE IF NOT EXISTS quarantine(id TEXT PRIMARY KEY,reason TEXT NOT NULL,manifest TEXT NOT NULL);
  PRAGMA user_version=1;
  """
}
