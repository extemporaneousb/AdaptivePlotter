import Foundation
import PlotterModel
import PlotterRuntime

struct PortraitLegacyLineageProof: Codable, Sendable {
  let runID: UUID
  let candidateID: String
  let photoID: UUID
  let sourceSHA256: String
  let programContentHash: String
  let executionProgramContentHash: String
  let method: String
  let evidenceGeneration: String
  let auditSHA256: String
  let recordSHA256: String
  let candidateRecordSHA256: String
}

extension PortraitCandidateStore {
  /// A photo-only library can have no raw archive. Disappearance of selected
  /// raw history must never be converted into an empty successful generation.
  func reconcileAbsentEvidence(sourceURL: URL) throws {
    try configureEvidenceArchiveURL(sourceURL)
    try ensureLibraryGraph()
    let db = try libraryDatabase()
    try assertCurrentInputs(db,checkEvidence:false)
    try db.transaction {
      guard !FileManager.default.fileExists(atPath:sourceURL.path),try db.generation.evidenceSHA256 == nil,
        try db.scalar("SELECT value FROM state WHERE key='evidence_dirty'") != "1",
        try db.scalar("SELECT (SELECT COUNT(*) FROM work)+(SELECT COUNT(*) FROM run_binding)+(SELECT COUNT(*) FROM quarantine)+(SELECT COUNT(*) FROM lineage_receipt)") == "0" else {
        throw PortraitLibraryError.staleGeneration
      }
      if try db.scalar("SELECT value FROM state WHERE key='evidence_absent'") != "1" {
        try db.setState("evidence_absent","1");try db.bumpRevision()
      }
      guard !FileManager.default.fileExists(atPath:sourceURL.path) else { throw PortraitLibraryError.staleGeneration }
    }
    refreshCommittedLibraryGeneration()
  }

  func assertCurrentInputs(_ db: PortraitLibraryDatabase, checkEvidence: Bool = true) throws {
    let generation = try db.generation
    if checkEvidence,try db.scalar("SELECT value FROM state WHERE key='evidence_dirty'") == "1" { throw PortraitLibraryError.staleGeneration }
    let legacy = legacyDirectoryURL.appendingPathComponent("index-v1.json")
    if FileManager.default.fileExists(atPath:legacy.path) {
      guard let expected = generation.legacyPortraitSHA256,
        try PortraitCandidateCoding.digest(Data(contentsOf:legacy)) == expected else { throw PortraitLibraryError.staleGeneration }
    } else if generation.legacyPortraitSHA256 != nil { throw PortraitLibraryError.staleGeneration }
    if checkEvidence,let evidenceArchiveURL {
      if FileManager.default.fileExists(atPath:evidenceArchiveURL.path) {
        guard let expected = generation.evidenceSHA256,
          try PortraitCandidateCoding.digest(Data(contentsOf:evidenceArchiveURL)) == expected else { throw PortraitLibraryError.staleGeneration }
      } else if generation.evidenceSHA256 != nil { throw PortraitLibraryError.staleGeneration }
    }
  }

  func validateDurableCandidate(_ candidate: PortraitCandidate) throws {
    try ensureLibraryGraph()
    let db = try libraryDatabase()
    try assertCurrentInputs(db,checkEvidence:false)
    let identity = PortraitDrawingIdentity(candidateID:candidate.id,photoID:candidate.photoID)
    guard let row = try db.rows("SELECT candidate_record,source_hash FROM drawing WHERE id=? AND deleted=0",[identity.id]).first,
      row[1] == candidate.sourceSHA256,let hash = row[0] else { throw PortraitLibraryError.missingDrawing }
    if durableCandidateCache[identity.id] == candidate,let files = durableCandidateFiles[identity.id],
      files.allSatisfy({(try? VerifiedFileState($0.key)) == $0.value}) { return }
    try candidate.validateIntegrity()
    let stored = try checkedCandidate(identity,recordHash:hash)
    let exact = try stored.materialize(source:readAsset(stored.sourceSHA256),raster:readAsset(stored.rasterSHA256))
    guard exact == candidate else { throw PortraitLibraryError.unresolvedLineage("immutable candidate differs from its capture occurrence") }
    durableCandidateCache[identity.id] = candidate
    let files = [directoryURL.appendingPathComponent("records").appendingPathComponent(hash),
      directoryURL.appendingPathComponent("assets").appendingPathComponent(stored.sourceSHA256),
      directoryURL.appendingPathComponent("assets").appendingPathComponent(stored.rasterSHA256)]
    durableCandidateFiles[identity.id] = try Dictionary(uniqueKeysWithValues:files.map{($0,try VerifiedFileState($0))})
  }

  private func checkedCandidate(_ identity:PortraitDrawingIdentity,recordHash:String) throws -> StoredCandidate {
    let db = try libraryDatabase()
    _ = try db.checkedDrawing(identity.id)
    guard let row = try db.rows("SELECT candidate_id,photo_id,source_hash,program_hash,raster_hash,recipe_hash,candidate_record FROM drawing WHERE id=? AND deleted=0",[identity.id]).first else { throw PortraitLibraryError.missingDrawing }
    let stored = try JSONDecoder().decode(StoredCandidate.self,from:readRecords(recordHash))
    guard stored.id == row[0],stored.photoID.uuidString.lowercased() == row[1],stored.sourceSHA256 == row[2],
      stored.program.contentHash.description == row[3],stored.rasterSHA256 == row[4],stored.recipeSHA256 == row[5],recordHash == row[6] else { throw PortraitLibraryError.database("candidate payload conflicts with normalized identity") }
    return stored
  }

  func loadDrawing(_ identity: PortraitDrawingIdentity) throws -> SavedDrawing {
    try ensureLibraryGraph()
    let db = try libraryDatabase();try assertCurrentInputs(db)
    guard let hash = try db.scalar("SELECT candidate_record FROM drawing WHERE id=? AND deleted=0",[identity.id]) else { throw PortraitLibraryError.missingDrawing }
    let stored = try checkedCandidate(identity,recordHash:hash)
    guard stored.id == identity.candidateID,stored.photoID == identity.photoID else { throw PortraitLibraryError.missingDrawing }
    return SavedDrawing(candidate:try stored.materialize(source:readAsset(stored.sourceSHA256),raster:readAsset(stored.rasterSHA256)))
  }

  func loadRetainedOccurrence(_ identity: PortraitDrawingIdentity) throws -> PortraitRetainedCandidate {
    try ensureLibraryGraph()
    let db = try libraryDatabase();try assertCurrentInputs(db,checkEvidence:false)
    guard let row = try db.rows("SELECT candidate_record,metadata_record FROM drawing WHERE id=? AND deleted=0",[identity.id]).first,
      let candidateHash = row[0],let metadataHash = row[1] else { throw PortraitLibraryError.missingDrawing }
    let stored = try checkedCandidate(identity,recordHash:candidateHash)
    let candidate = try stored.materialize(source:readAsset(stored.sourceSHA256),raster:readAsset(stored.rasterSHA256))
    let metadata = try JSONDecoder().decode(EntryMetadata.self,from:readRecords(metadataHash))
    guard metadata.candidateID == identity.candidateID else { throw PortraitLibraryError.database("selected occurrence metadata conflicts with normalized identity") }
    return .init(candidate:candidate,reasons:metadata.reasons,exploration:metadata.exploration,attempt:metadata.attempt)
  }

  func librarySnapshot(filter: PortraitLibraryFilter = .allPhotos, after cursor: PortraitLibraryCursor? = nil,
    limit requested: Int = 100) throws -> PortraitLibrarySnapshot {
    try ensureLibraryGraph()
    let db = try libraryDatabase();try assertCurrentInputs(db)
    let generation = try db.generation
    if let cursor, cursor.generation != generation || cursor.filter != filter { throw PortraitLibraryError.staleGeneration }
    let offset = cursor?.offset ?? 0,limit = min(100,max(1,requested))
    let photos: [PortraitLibraryPhoto],works: [PortraitLibraryWork],total: Int
    if filter == .plottedWorks {
      let whereSQL = "FROM work w JOIN drawing d ON d.id=w.drawing_id JOIN photo p ON p.id=d.photo_id WHERE w.executed=1 AND w.deleted=0 AND d.deleted=0 AND p.deleted=0"
      works = try db.rows("SELECT w.id " + whereSQL + " ORDER BY w.id LIMIT ? OFFSET ?",[String(limit),String(offset)]).map { try db.workProjection($0[0]!) }
      photos = [];total = Int(try db.scalar("SELECT COUNT(*) " + whereSQL) ?? "0") ?? 0
    } else {
      let existence = "EXISTS(SELECT 1 FROM drawing d JOIN work w ON w.drawing_id=d.id WHERE d.photo_id=p.id AND d.deleted=0 AND w.deleted=0 AND w.executed=1)"
      let predicate = filter == .photosWithPlottedWorks ? " AND " + existence : filter == .photosWithoutPlottedWorks ? " AND NOT " + existence : ""
      let whereSQL = "FROM photo p WHERE p.deleted=0" + predicate
      photos = try db.rows("SELECT p.id,(SELECT COUNT(*) FROM drawing d WHERE d.photo_id=p.id AND d.deleted=0),(SELECT COUNT(*) FROM drawing d JOIN work w ON w.drawing_id=d.id WHERE d.photo_id=p.id AND d.deleted=0 AND w.deleted=0 AND w.executed=1) " + whereSQL + " ORDER BY p.captured_at DESC,p.id LIMIT ? OFFSET ?",[String(limit),String(offset)]).map { row in
        .init(reference:try db.checkedPhoto(row[0]!),drawingCount:Int(row[1]!)!,plottedWorkCount:Int(row[2]!)!)
      }
      works = [];total = Int(try db.scalar("SELECT COUNT(*) " + whereSQL) ?? "0") ?? 0
    }
    try assertCurrentInputs(db)
    guard try db.generation == generation else { throw PortraitLibraryError.staleGeneration }
    return .init(generation:generation,photos:photos,drawings:[],works:works,
      next:offset + limit < total ? .init(generation:generation,filter:filter,offset:offset+limit) : nil)
  }

  func librarySelection(photoID: UUID, drawingIdentity: PortraitDrawingIdentity? = nil) throws -> PortraitLibrarySelection {
    try ensureLibraryGraph()
    let db = try libraryDatabase();try assertCurrentInputs(db)
    let generation = try db.generation
    guard let row = try db.rows("SELECT id,(SELECT COUNT(*) FROM drawing d WHERE d.photo_id=p.id AND d.deleted=0),(SELECT COUNT(*) FROM drawing d JOIN work w ON w.drawing_id=d.id WHERE d.photo_id=p.id AND d.deleted=0 AND w.deleted=0 AND w.executed=1) FROM photo p WHERE id=? AND deleted=0",[photoID.uuidString.lowercased()]).first else { throw PortraitLibraryError.missingPhoto }
    let photo = PortraitLibraryPhoto(reference:try db.checkedPhoto(row[0]!),drawingCount:Int(row[1]!)!,plottedWorkCount:Int(row[2]!)!)
    let drawings = try db.rows("SELECT id FROM drawing WHERE photo_id=? AND deleted=0 ORDER BY created_at DESC,id",[photoID.uuidString.lowercased()]).map { try db.checkedDrawing($0[0]!) }
    let works = try db.rows("SELECT w.id FROM work w JOIN drawing d ON d.id=w.drawing_id WHERE d.photo_id=? AND d.deleted=0 AND w.deleted=0 ORDER BY w.id",[photoID.uuidString.lowercased()]).map { try db.workProjection($0[0]!) }
    let sortedWorks = works.sorted { lhs,rhs in
      let a = lhs.recordedAt ?? .distantPast,b = rhs.recordedAt ?? .distantPast
      return a == b ? lhs.id < rhs.id : a > b
    }
    let defaultWork = sortedWorks.first(where:{$0.executedOrPossibleInk})
    let identityToSelect = drawingIdentity ?? defaultWork?.drawingIdentity ?? drawings.first?.identity
    let selectedWork = drawingIdentity == nil ? defaultWork?.id : sortedWorks.first(where:{$0.drawingIdentity == drawingIdentity})?.id
    var selected: PortraitLibraryDrawing?,program: DrawingProgram?
    if let identity = identityToSelect {
      guard identity.photoID == photoID, let selectedRow = try db.rows("SELECT summary,candidate_record,historical_record FROM drawing WHERE id=? AND deleted=0",[identity.id]).first else { throw PortraitLibraryError.missingDrawing }
      let historical = try selectedRow[2].map { try JSONDecoder().decode(PortraitHistoricalDrawing.self,from:readRecords($0)) }
      selected = try db.checkedDrawing(identity.id)
      if let hash = selectedRow[1] { program = try checkedCandidate(identity,recordHash:hash).program }
      else {
        guard let historical,historical.identity == identity,historical.sourceSHA256 == photo.reference.sourceSHA256,
          historical.program.contentHash.description == selected?.summary.programContentHash else { throw PortraitLibraryError.database("historical payload conflicts with normalized ancestry") }
        program = historical.program
      }
    }
    try assertCurrentInputs(db)
    guard try db.generation == generation else { throw PortraitLibraryError.staleGeneration }
    return .init(generation:generation,photo:photo,drawings:drawings,works:works,selectedDrawing:selected,program:program,selectedWorkID:selectedWork)
  }
  func librarySelection(drawingIdentity: PortraitDrawingIdentity) throws -> PortraitLibrarySelection {
    try librarySelection(photoID:drawingIdentity.photoID,drawingIdentity:drawingIdentity)
  }
  func librarySelection(workID: String) throws -> PortraitLibrarySelection {
    try ensureLibraryGraph()
    let db = try libraryDatabase();try assertCurrentInputs(db)
    guard let row = try db.rows("SELECT d.candidate_id,d.photo_id FROM work w JOIN drawing d ON d.id=w.drawing_id WHERE w.id=? AND w.deleted=0 AND d.deleted=0",[workID]).first,let photo = UUID(uuidString:row[1]!) else { throw PortraitLibraryError.missingDrawing }
    var selection = try librarySelection(drawingIdentity:.init(candidateID:row[0]!,photoID:photo))
    selection.selectedWorkID = workID
    return selection
  }

  func bindRunOccurrence(intent: DrawingRunIntent, candidate: PortraitCandidate,
    archive: DrawingRunEvidenceArchive, generation: String? = nil) throws {
    try validateDurableCandidate(candidate)
    guard archive.attempts.contains(where:{$0.intent == intent}),intent.context.candidate?.candidateID == candidate.id,
      intent.context.candidate?.sourceProgram == candidate.program,
      intent.context.candidate?.matches(intent.context.program) == true else { throw PortraitLibraryError.unresolvedLineage("staged intent differs from exact authored candidate") }
    let stagedProof: PortraitEvidenceSource.StagedAttemptProof?
    if let evidenceArchiveURL {
      stagedProof = try PortraitEvidenceSource.proveStagedAttempt(intent,archive:archive,url:evidenceArchiveURL,generation:generation)
    } else {
      // In-memory fixtures have no raw publisher. Production configures its
      // exact URL and always uses the selected component proof above.
      let syntheticHash = PortraitCandidateCoding.digest(try PortraitCandidateCoding.encoder().encode(archive))
      guard generation == nil || generation == syntheticHash else { throw PortraitLibraryError.staleGeneration }
      stagedProof = nil
    }
    let db = try libraryDatabase(),identity = PortraitDrawingIdentity(candidateID:candidate.id,photoID:candidate.photoID)
    let intentHash = PortraitCandidateCoding.digest(try PortraitCandidateCoding.encoder().encode(intent))
    try db.transaction {
      guard try db.scalar("SELECT value FROM state WHERE key=?",["catalog_hidden_run:"+intent.runID.description]) != "1",
        let candidateRecord = try db.scalar("SELECT candidate_record FROM drawing WHERE id=? AND deleted=0",[identity.id]) else { throw PortraitLibraryError.unresolvedLineage("run belongs to a deleted drawing version") }
      if let row = try db.rows("SELECT drawing_id,intent_hash FROM run_binding WHERE run_id=?",[intent.runID.description]).first,
        row[0] != identity.id || row[1] != intentHash { throw PortraitLibraryError.unresolvedLineage("run capture binding is immutable") }
      if let version = try db.scalar("SELECT value FROM state WHERE key=?",["binding_record:"+intent.runID.description]),version != candidateRecord { throw PortraitLibraryError.unresolvedLineage("run drawing version is immutable") }
      try db.execute("INSERT OR IGNORE INTO run_binding(run_id,drawing_id,intent_hash) VALUES(?,?,?)",[intent.runID.description,identity.id,intentHash])
      try db.setState("binding_record:"+intent.runID.description,candidateRecord)
      try db.setState("evidence_dirty","1")
      try db.bumpRevision()
      try stagedProof?.assertUnchanged()
    }
    refreshCommittedLibraryGeneration()
    // The existing collection schedules projection synchronization. The minimal
    // durable pre-motion binding never walks historical runs or media.
  }

  func checkedEvidenceGeneration(_ archive: DrawingRunEvidenceArchive, generation: String?) throws -> String {
    if let evidenceArchiveURL {
      if try PortraitEvidenceSource.envelopeVersion(evidenceArchiveURL) == 1 {
        let source = try PortraitEvidenceSource.read(evidenceArchiveURL)
        guard source.archive == archive,generation == nil || generation == source.sha256 else { throw PortraitLibraryError.staleGeneration }
        return source.sha256
      }
      let selected = try PortraitEvidenceSource.componentHashes(evidenceArchiveURL)
      var recordHashes: [UUID:String] = [:],attemptHashes: [UUID:String] = [:]
      for record in archive.records {
        let id = record.recordID.rawValue
        let hash: String
        guard let expected = selected.records[id] else { throw PortraitLibraryError.staleGeneration }
        if let cached = evidenceRecordHashes[id],cached.0 == record,cached.1 == expected { hash = cached.1 }
        else {
          guard try PortraitEvidenceSource.component(DrawingRunEvidenceRecord.self,hash:expected,url:evidenceArchiveURL) == record else { throw PortraitLibraryError.staleGeneration }
          hash = expected;evidenceRecordHashes[id] = (record,hash)
        }
        recordHashes[id] = hash
      }
      for attempt in archive.attempts {
        let id = attempt.intent.runID.rawValue
        let hash: String
        guard let expected = selected.attempts[id] else { throw PortraitLibraryError.staleGeneration }
        if let cached = evidenceAttemptHashes[id],cached.0 == attempt,cached.1 == expected { hash = cached.1 }
        else {
          guard try PortraitEvidenceSource.component(DrawingRunAttemptState.self,hash:expected,url:evidenceArchiveURL) == attempt else { throw PortraitLibraryError.staleGeneration }
          hash = expected;evidenceAttemptHashes[id] = (attempt,hash)
        }
        attemptHashes[id] = hash
      }
      let hash = try PortraitEvidenceSource.verifySelection(archive,url:evidenceArchiveURL,recordHashes:recordHashes,attemptHashes:attemptHashes)
      guard generation == nil || generation == hash else { throw PortraitLibraryError.staleGeneration }
      return hash
    }
    // In-memory fixtures have no raw publisher. Production always configures
    // the raw URL and therefore never substitutes this digest for its manifest.
    let hash = PortraitCandidateCoding.digest(try PortraitCandidateCoding.encoder().encode(archive))
    guard generation == nil || generation == hash else { throw PortraitLibraryError.staleGeneration }
    return hash
  }

  func reconcileEvidence(archive: DrawingRunEvidenceArchive, sourceURL: URL) throws {
    try configureEvidenceArchiveURL(sourceURL)
    try reconcileEvidence(archive:archive)
  }
  func bindRunOccurrence(intent: DrawingRunIntent,candidate: PortraitCandidate,
    archive: DrawingRunEvidenceArchive,sourceURL: URL) throws {
    try configureEvidenceArchiveURL(sourceURL)
    try bindRunOccurrence(intent:intent,candidate:candidate,archive:archive)
  }
}
