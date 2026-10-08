import Foundation
import PlotterModel
import PlotterRuntime

extension PortraitCandidateStore {
  func reconcileEvidence(archive: DrawingRunEvidenceArchive, generation: String? = nil,
    recoveryProofs: [PortraitLegacyLineageProof] = []) throws {
    try ensureLibraryGraph()
    let exactGeneration = try checkedEvidenceGeneration(archive,generation:generation)
    let db = try libraryDatabase()
    if try db.generation.evidenceSHA256 == exactGeneration,
      try db.scalar("SELECT value FROM state WHERE key='evidence_dirty'") != "1" {
      let proofsAlreadyRetained = try recoveryProofs.allSatisfy { proof in
        try db.scalar("SELECT record_hash FROM lineage_receipt WHERE run_id=? AND drawing_id=?",[RunID(proof.runID).description,PortraitDrawingIdentity(candidateID:proof.candidateID,photoID:proof.photoID).id]) == proof.recordSHA256
      }
      if proofsAlreadyRetained { return }
    }
    let proofByRun = Dictionary(uniqueKeysWithValues:recoveryProofs.map{($0.runID,$0)})
    let records = Dictionary(uniqueKeysWithValues:archive.records.map{($0.runID,$0)})
    let attempts = Dictionary(uniqueKeysWithValues:archive.attempts.map{($0.intent.runID,$0)})
    let runIDs = Set(records.keys).union(attempts.keys)
    var projections: [PortraitLibraryWork] = []
    var unresolved: [(String,String,String)] = []
    var historicals: [PortraitHistoricalDrawing] = []
    for runID in runIDs.sorted(by:{$0.description < $1.description}) {
      if try db.scalar("SELECT value FROM state WHERE key=?",["catalog_hidden_run:"+runID.description]) == "1" { continue }
      let record = records[runID],attempt = attempts[runID]
      let intent = attempt?.intent ?? record?.attemptEvidence?.intent
      let kind = intent?.context.program.source.kind ?? record?.program.source?.kind
      guard kind == "portrait",intent?.role == .ordinaryDrawing || record?.role == .ordinaryDrawing else { continue }
      do {
        let resolved = try resolveOccurrence(db:db,runID:runID,intent:intent,record:record,proof:proofByRun[runID.rawValue],generation:exactGeneration)
        if let historical = resolved.historical { try preserveHistoricalPayload(historical);historicals.append(historical) }
        let executed = attempt?.inkDispatchPossible == true || (record?.executionFrontiers.commandedStrokeCount ?? 0) > 0 || (record?.executionFrontiers.controllerCompletedStrokeCount ?? 0) > 0
        var media: [PortraitLibraryMedia] = []
        let baselines = attempt?.baselines ?? record?.attemptEvidence?.baselines ?? []
        for (i,reference) in baselines.enumerated() { media.append(verifyProjectionMedia(reference,stage:"baseline-\(i+1)",workID:runID.description)) }
        let progress = attempt?.progressFrames ?? record?.attemptEvidence?.progressFrames ?? []
        for (i,frame) in progress.enumerated() { media.append(verifyProjectionMedia(frame.media,stage:"progress-\(i+1)",workID:runID.description)) }
        for (i,reference) in (record?.attemptEvidence?.terminalFrames ?? []).enumerated() { media.append(verifyProjectionMedia(reference,stage:"terminal-\(i+1)",workID:runID.description)) }
        let deleted = record.map{archive.deletedReviewRecordIDs.contains($0.recordID)} ?? false
        let dismissed = archive.dismissedReviewRunIDs.contains(runID)
        let status = record.map{String(describing:$0.executionDisposition)} ?? (executed ? "possibleInk" : "preparedWithoutInkDispatch")
        let work = PortraitLibraryWork(id:runID.description,drawingID:resolved.identity.id,photoID:resolved.identity.photoID,
          runID:runID,recordID:record?.recordID,status:status,recordedAt:record?.recordedAt.wallTime ?? intent?.recordedAt.wallTime,executedOrPossibleInk:executed,sourceGeneration:exactGeneration,
          media:media,recoveryMethod:resolved.method)
        projections.append(work)
        if deleted || dismissed { unresolved.append(("review-hidden:"+runID.description,"review tombstone",try db.encode(work))) }
      } catch {
        let isLineageFailure: Bool
        if let library = error as? PortraitLibraryError {
          switch library {
          case .unresolvedLineage,.missingPhoto,.missingDrawing: isLineageFailure = true
          default: isLineageFailure = false
          }
        } else if let storeError = error as? PortraitCandidateStoreError,case .invalidAsset = storeError { isLineageFailure = true }
        else { isLineageFailure = false }
        guard isLineageFailure else { throw error }
        let payload = try record.map{try db.encode($0)} ?? attempt.map{try db.encode($0)} ?? "{}"
        let reason = error.localizedDescription
        try preserveQuarantine(id:runID.description,payload:Data(payload.utf8),record:record,attempt:attempt,reason:reason,generation:exactGeneration)
        unresolved.append((runID.description,reason,payload))
      }
    }
    // The raw publisher can advance while pixel verification or independent
    // quarantine writes run. Reject that entire generation before SQL commit.
    guard try checkedEvidenceGeneration(archive,generation:exactGeneration) == exactGeneration else { throw PortraitLibraryError.staleGeneration }
    try db.transaction {
      for historical in historicals { try installHistoricalRow(db,historical) }
      for proof in recoveryProofs {
        let identity = PortraitDrawingIdentity(candidateID:proof.candidateID,photoID:proof.photoID)
        guard projections.contains(where:{$0.runID.rawValue == proof.runID && $0.drawingID == identity.id}) else { continue }
        try db.execute("INSERT OR IGNORE INTO lineage_receipt(run_id,drawing_id,record_hash,program_hash,source_hash,method,audit_hash) VALUES(?,?,?,?,?,?,?)",[RunID(proof.runID).description,identity.id,proof.recordSHA256,proof.programContentHash,proof.sourceSHA256,proof.method,proof.auditSHA256])
      }
      for work in projections {
        if let previous = try db.scalar("SELECT drawing_id FROM work WHERE id=?",[work.id]),previous != work.drawingID { throw PortraitLibraryError.unresolvedLineage("existing run occurrence cannot be reassociated") }
        let deleted = archive.dismissedReviewRunIDs.contains(work.runID) || work.recordID.map{archive.deletedReviewRecordIDs.contains($0)} == true
        try db.execute("INSERT INTO work(id,drawing_id,run_id,record_id,executed,source_generation,payload,deleted) VALUES(?,?,?,?,?,?,?,?) ON CONFLICT(id) DO UPDATE SET record_id=excluded.record_id,executed=excluded.executed,source_generation=excluded.source_generation,payload=excluded.payload,deleted=MAX(work.deleted,excluded.deleted)",
          [work.id,work.drawingID,work.runID.description,work.recordID?.description,work.executedOrPossibleInk ? "1":"0",exactGeneration,try db.encode(work),deleted ? "1":"0"])
        try db.execute("DELETE FROM media WHERE work_id=?",[work.id])
        for media in work.media {
          try db.execute("INSERT INTO media(id,work_id,source_generation,asset_hash,payload) VALUES(?,?,?,?,?) ON CONFLICT(id) DO UPDATE SET source_generation=excluded.source_generation,payload=excluded.payload",[media.id,work.id,exactGeneration,media.reference.frame.frameSHA256,try db.encode(media)])
        }
        try db.execute("DELETE FROM quarantine WHERE id=?",[work.id])
      }
      for (id,reason,payload) in unresolved where !id.hasPrefix("review-hidden:") {
        try db.execute("INSERT INTO quarantine(id,reason,manifest) VALUES(?,?,?) ON CONFLICT(id) DO UPDATE SET reason=excluded.reason,manifest=excluded.manifest",[id,reason,payload])
        // A failed current association cannot leave an older projection visible.
        try db.execute("UPDATE work SET deleted=1 WHERE id=?",[id])
      }
      try db.setState("evidence_hash",exactGeneration);try db.setState("evidence_dirty",nil);try db.bumpRevision();try db.integrityCheck()
    }
    // Update the facade's optimistic selector after a projection-only commit.
    refreshCommittedLibraryGeneration()
  }

  private func resolveOccurrence(db: PortraitLibraryDatabase,runID: RunID,intent: DrawingRunIntent?,
    record: DrawingRunEvidenceRecord?,proof: PortraitLegacyLineageProof?,generation: String)
    throws -> (identity:PortraitDrawingIdentity,method:String,historical:PortraitHistoricalDrawing?) {
    if let row = try db.rows("SELECT d.candidate_id,d.photo_id,b.intent_hash,d.candidate_record,d.deleted,p.deleted FROM run_binding b JOIN drawing d ON d.id=b.drawing_id JOIN photo p ON p.id=d.photo_id WHERE b.run_id=?",[runID.description]).first {
      guard row[4] == "0",row[5] == "0" else {
        throw PortraitLibraryError.unresolvedLineage("committed run binding belongs to a deleted capture occurrence")
      }
      guard let intent,PortraitCandidateCoding.digest(try PortraitCandidateCoding.encoder().encode(intent)) == row[2],
        intent.context.candidate?.candidateID == row[0] else { throw PortraitLibraryError.unresolvedLineage("committed run binding differs from raw intent") }
      if let version = try db.scalar("SELECT value FROM state WHERE key=?",["binding_record:"+runID.description]),version != row[3] {
        throw PortraitLibraryError.unresolvedLineage("committed run binding belongs to a retired drawing version")
      }
      return (.init(candidateID:row[0]!,photoID:UUID(uuidString:row[1]!)!),"committed_capture_occurrence",nil)
    }
    if let receipt = try db.rows("SELECT d.candidate_id,d.photo_id,r.record_hash,r.program_hash,r.source_hash,r.method,r.audit_hash FROM lineage_receipt r JOIN drawing d ON d.id=r.drawing_id JOIN photo p ON p.id=d.photo_id WHERE r.run_id=? AND d.deleted=0 AND p.deleted=0 AND d.program_hash=r.program_hash AND d.source_hash=r.source_hash",[runID.description]).first {
      guard let record else { throw PortraitLibraryError.unresolvedLineage("retained lineage receipt requires its exact terminal record") }
      let encoder = JSONEncoder();encoder.outputFormatting = [.sortedKeys]
      let hash = try evidenceRecordHashes[record.recordID.rawValue]?.1 ?? PortraitCandidateCoding.digest(encoder.encode(record))
      guard hash == receipt[2] else { throw PortraitLibraryError.unresolvedLineage("immutable raw record differs from retained recovery proof") }
      return (.init(candidateID:receipt[0]!,photoID:UUID(uuidString:receipt[1]!)!),receipt[5]! + ":" + receipt[6]!,nil)
    }
    if let reference = intent?.context.candidate {
      // A deleted occurrence still proves that this capture-independent ID is
      // insufficient to choose its surviving sibling for an unbound raw run.
      let rows = try db.rows("SELECT d.candidate_id,d.photo_id,d.program_hash,d.deleted,p.deleted FROM drawing d JOIN photo p ON p.id=d.photo_id WHERE d.candidate_id=?",[reference.candidateID])
      guard reference.matches(intent!.context.program) else { throw PortraitLibraryError.unresolvedLineage("explicit reference does not match execution program") }
      if !rows.isEmpty {
        guard rows.count == 1 else { throw PortraitLibraryError.unresolvedLineage("capture association is ambiguous without a committed run binding") }
        guard rows[0][2] == reference.sourceProgram.contentHash.description,rows[0][3] == "0",rows[0][4] == "0" else {
          throw PortraitLibraryError.unresolvedLineage("explicit referenced occurrence is unavailable or differs from its source program")
        }
        return (.init(candidateID:reference.candidateID,photoID:UUID(uuidString:rows[0][1]!)!),"explicit_validated_reference",nil)
      }
      // Preserve the original referenced historical identity. Exact source hash
      // may recover one capture; recipe/raster/checkpoint remain unknown.
      let tokens = reference.sourceProgram.source.sourceIdentifier.split(separator:"|").filter{$0.hasPrefix("image=")}
      guard tokens.count == 1,let token = tokens.first else { throw PortraitLibraryError.missingPhoto }
      let sourceHash = String(token.dropFirst(6))
      let photos = try db.rows("SELECT id,deleted FROM photo WHERE source_hash=?",[sourceHash])
      guard photos.count == 1,photos[0][1] == "0",let photo = UUID(uuidString:photos[0][0]!) else { throw PortraitLibraryError.unresolvedLineage("historical source capture unavailable or ambiguous") }
      let identity = PortraitDrawingIdentity(candidateID:reference.candidateID,photoID:photo)
      let proofHash = PortraitCandidateCoding.digest(try PortraitCandidateCoding.encoder().encode(reference))
      let historical = PortraitHistoricalDrawing(identity:identity,program:reference.sourceProgram,sourceSHA256:sourceHash,
        recoveryMethod:"explicit_historical_program_unique_source",proofSHA256:proofHash)
      return (identity,historical.recoveryMethod,historical)
    }
    if let proof {
      guard proof.evidenceGeneration == generation,proof.runID == runID.rawValue,
        proof.executionProgramContentHash == record?.program.contentHash.description,
        proof.recordSHA256 == record.flatMap { evidenceRecordHashes[$0.recordID.rawValue]?.1 },
        let row = try db.rows("SELECT photo_id,source_hash,program_hash,candidate_record FROM drawing WHERE id=? AND deleted=0",[PortraitDrawingIdentity(candidateID:proof.candidateID,photoID:proof.photoID).id]).first,
        row[0] == proof.photoID.uuidString.lowercased(),row[1] == proof.sourceSHA256,row[2] == proof.programContentHash,row[3] == proof.candidateRecordSHA256 else { throw PortraitLibraryError.unresolvedLineage("audit proof does not match immutable selected graph") }
      return (.init(candidateID:proof.candidateID,photoID:proof.photoID),proof.method + ":" + proof.auditSHA256,nil)
    }
    // Exact full-program identity needs one capture occurrence. Known composed
    // legacy mappings require the separately hash-bound audit proof above.
    let hash = record?.program.contentHash.description ?? intent?.context.program.contentHash.description
    let rows = try db.rows("SELECT d.candidate_id,d.photo_id,d.deleted,p.deleted FROM drawing d JOIN photo p ON p.id=d.photo_id WHERE d.program_hash=?",[hash])
    guard rows.count == 1,rows[0][2] == "0",rows[0][3] == "0" else { throw PortraitLibraryError.unresolvedLineage("no unique exact source program/capture association") }
    return (.init(candidateID:rows[0][0]!,photoID:UUID(uuidString:rows[0][1]!)!),"unique_exact_program",nil)
  }

  private func preserveHistoricalPayload(_ value: PortraitHistoricalDrawing) throws {
    let bytes = try PortraitCandidateCoding.encoder().encode(value)
    let hash = PortraitCandidateCoding.digest(bytes)
    let target = directoryURL.appendingPathComponent("records").appendingPathComponent(hash)
    try FileManager.default.createDirectory(at:target.deletingLastPathComponent(),withIntermediateDirectories:true)
    if !FileManager.default.fileExists(atPath:target.path) { try bytes.write(to:target,options:.atomic);try synchronize(target) }
    guard PortraitCandidateCoding.digest(try Data(contentsOf:target)) == hash else { throw PortraitLibraryError.database("historical payload checksum invalid") }
  }

  private func installHistoricalRow(_ db: PortraitLibraryDatabase,_ value: PortraitHistoricalDrawing) throws {
    let summary = SavedDrawingSummary(id:value.identity.candidateID,title:"Historical portrait (recipe unknown)",createdAt:Date(timeIntervalSince1970:0),programContentHash:value.program.contentHash.description,programKind:value.program.source.kind,strokeCount:value.program.strokes.count,strokeStyle:value.program.strokes.first?.style,pose:nil,photoID:value.identity.photoID,sourceSHA256:value.sourceSHA256,recipe:nil,isSaved:false,feedback:nil)
    try db.execute("INSERT OR IGNORE INTO drawing(id,candidate_id,photo_id,source_hash,program_hash,historical_record,recovery_method,proof_hash,summary,created_at) VALUES(?,?,?,?,?,?,?,?,?,?)",[value.identity.id,value.identity.candidateID,value.identity.photoID.uuidString.lowercased(),value.sourceSHA256,value.program.contentHash.description,PortraitCandidateCoding.digest(try PortraitCandidateCoding.encoder().encode(value)),value.recoveryMethod,value.proofSHA256,try db.encode(summary),"0"])
  }

  private func verifyProjectionMedia(_ reference: DrawingRunMediaReference,stage:String,workID:String) -> PortraitLibraryMedia {
    let id = workID + ":" + stage + ":" + reference.frame.frameSHA256
    guard let evidenceArchiveURL else { return .init(id:id,stage:stage,reference:reference,isAvailable:false,unavailableReason:"Raw media path is unavailable") }
    let file = evidenceArchiveURL.deletingLastPathComponent().appendingPathComponent(evidenceArchiveURL.lastPathComponent + ".media").appendingPathComponent(reference.frame.frameSHA256 + ".pixels")
    do {
      let state = try VerifiedFileState(file)
      if projectionMediaFiles[file] == state { return .init(id:id,stage:stage,reference:reference,isAvailable:true,unavailableReason:nil) }
      let bytes = try Data(contentsOf:file)
      guard bytes.count == reference.byteCount,PortraitCandidateCoding.digest(bytes) == reference.frame.frameSHA256 else { throw PortraitLibraryError.database("pixel checksum or extent invalid") }
      guard try VerifiedFileState(file) == state else { throw PortraitLibraryError.staleGeneration }
      projectionMediaFiles[file] = state
      return .init(id:id,stage:stage,reference:reference,isAvailable:true,unavailableReason:nil)
    } catch { return .init(id:id,stage:stage,reference:reference,isAvailable:false,unavailableReason:error.localizedDescription) }
  }

  private func preserveQuarantine(id:String,payload:Data,record:DrawingRunEvidenceRecord?,attempt:DrawingRunAttemptState?,reason:String,generation:String) throws {
    let root = directoryURL.deletingLastPathComponent().appendingPathComponent("PortraitQuarantine").appendingPathComponent(id)
    try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
    let typedRecordURL = root.appendingPathComponent(PortraitCandidateCoding.digest(payload) + ".json")
    if !FileManager.default.fileExists(atPath:typedRecordURL.path) { try payload.write(to:typedRecordURL,options:.atomic);try synchronize(typedRecordURL) }
    guard PortraitCandidateCoding.digest(try Data(contentsOf:typedRecordURL)) == PortraitCandidateCoding.digest(payload) else { throw PortraitLibraryError.database("quarantine typed metadata changed") }
    var originals: [[String:Any]] = []
    if let archiveURL = evidenceArchiveURL {
      struct Envelope: Decodable { let payload: Data }
      let originalManifest = try Data(contentsOf:archiveURL)
      let envelope = try JSONDecoder().decode(Envelope.self,from:originalManifest)
      let selected = try JSONSerialization.jsonObject(with:envelope.payload) as? [String:Any] ?? [:]
      var sourceFiles = [archiveURL]
      for (key,identity) in [("records",record?.recordID.rawValue),("attempts",attempt?.intent.runID.rawValue)] {
        guard let identity else { continue }
        let references = selected[key] as? [[String:Any]] ?? []
        if let reference = references.first(where:{($0["id"] as? String)?.lowercased() == identity.uuidString.lowercased()}),let hash = reference["sha256"] as? String {
          sourceFiles.append(archiveURL.deletingLastPathComponent().appendingPathComponent(archiveURL.lastPathComponent + ".records").appendingPathComponent(hash + ".json"))
        }
      }
      let baselines: [DrawingRunMediaReference] = attempt?.baselines ?? record?.attemptEvidence?.baselines ?? []
      let progress: [DrawingRunProgressFrame] = attempt?.progressFrames ?? record?.attemptEvidence?.progressFrames ?? []
      let terminal: [DrawingRunMediaReference] = record?.attemptEvidence?.terminalFrames ?? []
      let media = baselines + progress.map(\.media) + terminal
      sourceFiles += media.map { archiveURL.deletingLastPathComponent().appendingPathComponent(archiveURL.lastPathComponent + ".media").appendingPathComponent($0.frame.frameSHA256 + ".pixels") }
      var observedHashes: [String] = []
      if let record {
        switch record.observation {
        case .observed(let value): observedHashes = [value.frames.baseline.frameSHA256,value.frames.post.frameSHA256]
        default: break
        }
      }
      sourceFiles += observedHashes.map { archiveURL.deletingLastPathComponent().appendingPathComponent(archiveURL.lastPathComponent + ".media").appendingPathComponent($0 + ".pixels") }
      for source in Set(sourceFiles) {
        guard FileManager.default.fileExists(atPath:source.path) else { originals.append(["source":source.path,"availability":"missing"]);continue }
        let bytes = try Data(contentsOf:source),hash = PortraitCandidateCoding.digest(bytes)
        let copy = root.appendingPathComponent(hash + ".original")
        if !FileManager.default.fileExists(atPath:copy.path) { try bytes.write(to:copy,options:.atomic);try synchronize(copy) }
        guard PortraitCandidateCoding.digest(try Data(contentsOf:copy)) == hash else { throw PortraitLibraryError.database("quarantine copy checksum invalid") }
        originals.append(["source":source.path,"file":copy.lastPathComponent,"sha256":hash,"byteCount":bytes.count])
      }
    }
    let manifest = try JSONSerialization.data(withJSONObject:["id":id,"reason":reason,"sourceGeneration":generation,"payloadSHA256":PortraitCandidateCoding.digest(payload),"originalFiles":originals],options:[.sortedKeys,.prettyPrinted])
    let file = root.appendingPathComponent(PortraitCandidateCoding.digest(manifest) + ".manifest.json")
    if !FileManager.default.fileExists(atPath:file.path) { try manifest.write(to:file,options:.atomic);try synchronize(file) }
    guard PortraitCandidateCoding.digest(try Data(contentsOf:file)) == PortraitCandidateCoding.digest(manifest) else { throw PortraitLibraryError.database("quarantine manifest changed") }
  }
}
