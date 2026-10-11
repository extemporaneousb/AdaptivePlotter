@testable import PortraitArtists
@testable import PortraitLibrary
import Foundation
import PlotterEpisodeRuntime
import PlotterModel
import PlotterRuntime
import Testing
@testable import PlotterApp

@Suite("Portrait relational catalog integrity")
struct PortraitLibraryDatabaseTests {
  private func root() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent("portrait-sql-"+UUID().uuidString) }

  @MainActor
  @Test("Deleted captures remain in every fallback uniqueness census and committed bindings never fall through")
  func deletedOccurrenceRecoveryCensus() async throws {
    let directory = root();defer { try? FileManager.default.removeItem(at:directory) }
    let base = try portraitPersistenceCandidate(seed:1004)
    let program = try DrawingProgram(id:base.program.id,fieldExtent:base.program.fieldExtent,strokes:base.program.strokes,
      source:.init(kind:"portrait",sourceIdentifier:"portrait-v3|image="+base.sourceSHA256))
    let a = try PortraitCandidate(sourceData:base.sourceData,sourcePixelExtent:base.sourcePixelExtent,raster:base.raster,
      recipe:base.recipe,program:program,photoID:UUID(),captureSessionID:UUID(),pose:.front)
    let b = try PortraitCandidate(sourceData:a.sourceData,sourcePixelExtent:a.sourcePixelExtent,raster:a.raster,
      recipe:a.recipe,program:a.program,photoID:UUID(),captureSessionID:UUID(),pose:.front)
    #expect(a.id == b.id && a.photoID != b.photoID)
    let fixture = try await DrawingRunEpisodeFixtureCache.load()
    let built = PlotterDrawingPlanningAdapter.buildDraft(program:program,machineCenter:nil,uniformScale:0.02,
      rotationDegrees:0,drawableRegion:fixture.drawableRegion,registration:fixture.registration)
    let plan = try #require(built.plan)
    let known = try #require(SavedDrawing(candidate:a).runCandidateReference)
    let missingHash = try PlotterModel.Digest(bytes:Array(repeating:0xab,count:32))
    let missing = DrawingRunCandidateReference(candidateID:missingHash.description,contentHash:missingHash,sourceProgram:program)
    func intent(_ reference: DrawingRunCandidateReference?) throws -> DrawingRunIntent {
      let context = try DrawingRunAttemptContext(program:program,registration:fixture.registration,
        drawingFeedMMPerMinute:PlotterMotionThroughput.applicationXYFeedMMPerMinute,
        penActuationProfile:.initialDefaults,paper:fixture.paper,candidate:reference)
      return try DrawingRunIntent(runID:RunID(),requestID:UUID(),plan:plan,placementID:UUID(),role:.ordinaryDrawing,
        context:context,recordedAt:RuntimeTimestamp(monotonicNanoseconds:100))
    }
    for (index,reference) in [known,missing,nil].enumerated() {
      let location = directory.appendingPathComponent(String(index)),store = PortraitCandidateStore(directoryURL:location)
      try await store.save(snapshot:.init(entries:[.init(candidate:a,reasons:[])]))
      try await store.save(snapshot:.init(entries:[.init(candidate:b,reasons:[])]))
      let deletion = PortraitArchiveTombstone(id:UUID(),kind:.photo,identity:a.photoID.uuidString,
        affectedCandidateIDs:[],assetSHA256s:[],createdAt:Date())
      try await store.save(snapshot:.init(entries:[.init(candidate:b,reasons:[])],tombstones:[deletion]))
      let staged = try intent(reference)
      let archive = try DrawingRunEvidenceArchive(revision:0,records:[],attempts:[.init(intent:staged)])
      try await store.reconcileEvidence(archive:archive)
      let db = try PortraitLibraryDatabase(url:location.appendingPathComponent("library-v1.sqlite"),readOnly:true)
      #expect(try db.scalar("SELECT COUNT(*) FROM work") == "0")
      #expect(try db.scalar("SELECT COUNT(*) FROM drawing") == "2")
      #expect(try db.scalar("SELECT COUNT(*) FROM quarantine WHERE id=?",[staged.runID.description]) == "1")
      #expect(try await store.librarySnapshot().photos.map(\.id) == [b.photoID])
    }
    for deleted in [false,true] {
      let location = directory.appendingPathComponent(deleted ? "deleted-binding":"retired-binding")
      let store = PortraitCandidateStore(directoryURL:location)
      try await store.save(snapshot:.init(entries:[.init(candidate:a,reasons:[])]))
      try await store.save(snapshot:.init(entries:[.init(candidate:b,reasons:[])]))
      let staged = try intent(known),archive = try DrawingRunEvidenceArchive(revision:0,records:[],attempts:[.init(intent:staged)])
      try await store.bindRunOccurrence(intent:staged,candidate:a,archive:archive)
      try await store.reconcileEvidence(archive:archive)
      #expect(try await store.librarySelection(workID:staged.runID.description).photo.id == a.photoID)
      let db = try PortraitLibraryDatabase(url:location.appendingPathComponent("library-v1.sqlite"))
      if deleted { try db.execute("UPDATE drawing SET deleted=1 WHERE photo_id=?",[a.photoID.uuidString.lowercased()]) }
      else { try db.setState("binding_record:"+staged.runID.description,String(repeating:"0",count:64)) }
      try db.setState("evidence_dirty","1")
      try await store.reconcileEvidence(archive:archive)
      #expect(try db.scalar("SELECT COUNT(*) FROM work WHERE deleted=0") == "0")
      #expect(try db.scalar("SELECT drawing_id FROM run_binding WHERE run_id=?",[staged.runID.description]) == PortraitDrawingIdentity(candidateID:a.id,photoID:a.photoID).id)
      #expect(try db.scalar("SELECT COUNT(*) FROM quarantine WHERE id=?",[staged.runID.description]) == "1")
    }
  }

  @MainActor
  @Test("Selected staged attempt proof refuses missing/corrupt current components and manifest drift")
  func selectedStagedAttemptProof() async throws {
    let directory = root();defer { try? FileManager.default.removeItem(at:directory) }
    let fixture = try await DrawingRunEpisodeFixtureCache.load(),plan = fixture.plan
    let facts = fixture.facts()
    let context = try DrawingRunAttemptContext(program:plan.program,registration:plan.registration,
      materialProfile:plan.materialProfile,materialApplicability:plan.materialApplicability,paperStock:plan.paperStock,
      drawingFeedMMPerMinute:PlotterMotionThroughput.applicationXYFeedMMPerMinute,
      penActuationProfile:facts.penActuationProfile,paper:plan.paperCoverage.paper,candidate:plan.candidate)
    let intent = try DrawingRunIntent(runID:RunID(),requestID:UUID(),plan:plan.plan,placementID:plan.placementID,
      role:.ordinaryDrawing,context:context,recordedAt:RuntimeTimestamp(monotonicNanoseconds:100))
    let url = directory.appendingPathComponent("raw.json"),writer = DrawingRunEvidenceStore(fileURL:url)
    let archive = try await writer.stageIntent(intent)
    let proof = try PortraitEvidenceSource.proveStagedAttempt(intent,archive:archive,url:url)
    #expect(proof.generation == PortraitCandidateCoding.digest(try Data(contentsOf:url)))
    try proof.assertUnchanged()
    #expect(throws:(any Error).self) {
      _ = try PortraitEvidenceSource.proveStagedAttempt(intent,archive:archive,url:url,generation:String(repeating:"0",count:64))
    }
    let original = try Data(contentsOf:proof.componentURL)
    try Data("corrupt current selected component".utf8).write(to:proof.componentURL)
    #expect(throws:(any Error).self) { _ = try PortraitEvidenceSource.proveStagedAttempt(intent,archive:archive,url:url) }
    try original.write(to:proof.componentURL)
    try FileManager.default.removeItem(at:proof.componentURL)
    #expect(throws:(any Error).self) { _ = try PortraitEvidenceSource.proveStagedAttempt(intent,archive:archive,url:url) }
    try original.write(to:proof.componentURL)
    let changed = try await writer.annotateReview(.init(scope:.drawing("proof-drift"),text:"Unrelated raw metadata changed"))
    #expect(throws:(any Error).self) { try proof.assertUnchanged() }
    #expect(throws:(any Error).self) { _ = try PortraitEvidenceSource.proveStagedAttempt(intent,archive:archive,url:url,generation:proof.generation) }
    _ = try PortraitEvidenceSource.proveStagedAttempt(intent,archive:changed,url:url)
  }

  @Test("Cold mutation bootstrap preserves omitted immutable ancestry and generic drawings without reading historical assets")
  func compactMutationDelta() async throws {
    let directory = root();defer { try? FileManager.default.removeItem(at:directory) }
    let candidate = try portraitPersistenceCandidate()
    let reason = PortraitRetentionEvent(reason:.shortlisted,id:UUID(),createdAt:Date())
    let label = try PortraitLabelRevision(candidate:candidate,rating:3,scope:.screenSketch,presentation:.init())
    let style = PortraitSavedStyle(id:UUID(),name:"Unchanged",recipe:candidate.recipe,createdAt:Date())
    let generic = SavedDrawing(program:try DrawingProgramCatalog.program(for:.square,style:candidate.program.strokes[0].style))
    try await PortraitCandidateStore(directoryURL:directory).save(snapshot:.init(entries:[.init(candidate:candidate,reasons:[reason])],
      labels:[label],savedStyles:[style],savedDrawings:[generic],labelPhotoIDs:[label.id.uuidString.lowercased():candidate.photoID]))
    let db = try PortraitLibraryDatabase(url:directory.appendingPathComponent("library-v1.sqlite"),readOnly:true)
    let beforeDrawing = try db.rows("SELECT * FROM drawing"),beforeGeneric = try db.rows("SELECT * FROM generic_drawing")
    let beforeLabel = try db.rows("SELECT * FROM label"),beforePhoto = try db.rows("SELECT * FROM photo")
    let cold = PortraitCandidateStore(directoryURL:directory)
    let bootstrap = await cold.loadMutationState()
    #expect(bootstrap.canWrite && bootstrap.archive.entries.isEmpty && bootstrap.archive.sourcePhotos == nil && bootstrap.archive.savedDrawings == nil)
    #expect(bootstrap.archive.labels == [label] && bootstrap.archive.labelPhotoIDs?[label.id.uuidString.lowercased()] == candidate.photoID)
    #expect(bootstrap.archive.savedStyles?.map(\.id) == [style.id])
    #expect(bootstrap.archive.photoCaptureTimeUnknownIDs == [candidate.photoID])
    let assetBytes = await cold.assetBytesVerified,recordBytes = await cold.recordBytesEncoded
    #expect(assetBytes == 0 && recordBytes == 0)
    var delta = bootstrap.archive
    let photo = PortraitPhoto(id:UUID(),data:Data([5,6,7,8]),label:"New capture",capturedAt:Date(),frameID:nil,captureNanoseconds:nil,pose:.front)
    delta.sourcePhotos = [photo]
    try await cold.save(snapshot:delta,mode:.mutationDelta)
    #expect(try db.rows("SELECT * FROM drawing") == beforeDrawing)
    #expect(try db.rows("SELECT * FROM generic_drawing") == beforeGeneric)
    #expect(try db.rows("SELECT * FROM label") == beforeLabel)
    #expect(try db.rows("SELECT * FROM photo WHERE id=?",[candidate.photoID.uuidString.lowercased()]) == beforePhoto)
    let reopened = PortraitCandidateStore(directoryURL:directory)
    #expect(try await reopened.librarySnapshot().photos.count == 2)
    let exact = try await reopened.loadRetainedOccurrence(.init(candidateID:candidate.id,photoID:candidate.photoID))
    #expect(exact.candidate == candidate && exact.reasons == [reason])
    var deletion = (await reopened.loadMutationState()).archive
    deletion.savedStyles = []
    deletion.tombstones.append(.init(id:UUID(),kind:.candidate,identity:generic.id,affectedCandidateIDs:[],assetSHA256s:[],createdAt:Date()))
    try await reopened.save(snapshot:deletion,mode:.mutationDelta)
    #expect(try db.rows("SELECT * FROM drawing") == beforeDrawing)
    #expect(try db.scalar("SELECT COUNT(*) FROM generic_drawing") == "0")
    #expect(try await reopened.loadSavedStyles().isEmpty)
  }

  @Test("Absent raw evidence permits a photo-only library but never hides previously selected evidence")
  func explicitEvidenceAbsence() async throws {
    let directory = root();defer { try? FileManager.default.removeItem(at:directory) }
    let rawURL = directory.appendingPathComponent("raw.json")
    let candidate = try portraitPersistenceCandidate()
    let store = PortraitCandidateStore(directoryURL:directory.appendingPathComponent("library"),evidenceArchiveURL:rawURL)
    let photo = PortraitPhoto(id:UUID(),data:candidate.sourceData,label:"Only photo",capturedAt:Date(),frameID:nil,captureNanoseconds:nil,pose:.front)
    try await store.save(snapshot:.init(sourcePhotos:[photo]))
    try await store.reconcileAbsentEvidence(sourceURL:rawURL)
    #expect(try await store.librarySnapshot().photos.map(\.id) == [photo.id])
    let raw = try await DrawingRunEvidenceStore(fileURL:rawURL).annotateReview(.init(scope:.drawing("absence"),text:"Selected raw generation"))
    try await store.reconcileEvidence(archive:raw,generation:PortraitCandidateCoding.digest(try Data(contentsOf:rawURL)))
    try FileManager.default.removeItem(at:rawURL)
    await #expect(throws:(any Error).self) { try await store.reconcileAbsentEvidence(sourceURL:rawURL) }
    await #expect(throws:(any Error).self) { _ = try await store.librarySnapshot() }
  }

  @Test("Validated generation promotion uses SQLite backup and refuses original input drift before selecting a new destination")
  func validatedGenerationPromotion() async throws {
    let directory = root();defer { try? FileManager.default.removeItem(at:directory) }
    let legacy = directory.appendingPathComponent("legacy"),rawURL = directory.appendingPathComponent("evidence/raw.json")
    let candidate = try portraitPersistenceCandidate()
    try await PortraitCandidateStore(directoryURL:legacy).save(snapshot:.init(entries:[.init(candidate:candidate,reasons:[])]))
    let db = try PortraitLibraryDatabase(url:legacy.appendingPathComponent("library-v1.sqlite"),readOnly:true)
    let payload = try PortraitCandidateCoding.encoder().encode(db.index())
    try PortraitCandidateCoding.encoder().encode(IndexEnvelope(schemaVersion:4,sha256:PortraitCandidateCoding.digest(payload),payload:payload)).write(to:legacy.appendingPathComponent("index-v1.json"))
    _ = try await DrawingRunEvidenceStore(fileURL:rawURL).annotateReview(.init(scope:.drawing("promotion"),text:"Metadata fixture"))
    let source = directory.appendingPathComponent("verified/PortraitLibrary"),backup = directory.appendingPathComponent("backup")
    let receipt = try await PortraitLibraryReconciler.run(legacyDirectory:legacy,evidenceArchive:rawURL,destination:source,backupDirectory:backup)
    var databaseHash = PortraitCandidateCoding.digest(try Data(contentsOf:source.appendingPathComponent("library-v1.sqlite")))
    let destination = directory.appendingPathComponent("promoted/PortraitLibrary")
    let promoted = try await PortraitLibraryReconciler.installValidatedGeneration(sourceLibrary:source,destination:destination,
      legacyDirectory:legacy,evidenceArchive:rawURL,backupDirectory:backup,expectedDatabaseSHA256:databaseHash)
    #expect(promoted.photoCount == receipt.photoCount && promoted.drawingCount == receipt.drawingCount)
    let reopened = PortraitCandidateStore(directoryURL:destination,legacyDirectoryURL:legacy,evidenceArchiveURL:rawURL)
    #expect(try await reopened.librarySnapshot().photos.first?.id == candidate.photoID)
    #expect(try await reopened.loadDrawing(.init(candidateID:candidate.id,photoID:candidate.photoID)).portraitCandidate == candidate)
    let selectedRaster = source.appendingPathComponent("assets").appendingPathComponent(candidate.rasterSHA256)
    let rasterBytes = try Data(contentsOf:selectedRaster)
    try FileManager.default.removeItem(at:selectedRaster)
    let missingAsset = directory.appendingPathComponent("missing-asset/PortraitLibrary")
    await #expect(throws:(any Error).self) {
      _ = try await PortraitLibraryReconciler.installValidatedGeneration(sourceLibrary:source,destination:missingAsset,
        legacyDirectory:legacy,evidenceArchive:rawURL,backupDirectory:backup,expectedDatabaseSHA256:databaseHash)
    }
    #expect(!FileManager.default.fileExists(atPath:missingAsset.path))
    try rasterBytes.write(to:selectedRaster)
    let selectedDB = try PortraitLibraryDatabase(url:source.appendingPathComponent("library-v1.sqlite"))
    try selectedDB.execute("INSERT INTO quarantine(id,reason,manifest) VALUES('fixture-unresolved','missing original files','{}')")
    let missingReceipt = PortraitLibraryReconciler.Receipt(sourcePortraitSHA256:receipt.sourcePortraitSHA256,sourceEvidenceSHA256:receipt.sourceEvidenceSHA256,
      backupManifestSHA256:receipt.backupManifestSHA256,auditSHA256:nil,photoCount:receipt.photoCount,drawingCount:receipt.drawingCount,
      workCount:receipt.workCount,plottedWorkCount:receipt.plottedWorkCount,quarantineCount:1,destination:source.path)
    try PortraitCandidateCoding.encoder().encode(missingReceipt).write(to:source.appendingPathComponent("reconciliation-receipt.json"))
    databaseHash = PortraitCandidateCoding.digest(try Data(contentsOf:source.appendingPathComponent("library-v1.sqlite")))
    let missingQuarantine = directory.appendingPathComponent("missing-quarantine/PortraitLibrary")
    await #expect(throws:(any Error).self) {
      _ = try await PortraitLibraryReconciler.installValidatedGeneration(sourceLibrary:source,destination:missingQuarantine,
        legacyDirectory:legacy,evidenceArchive:rawURL,backupDirectory:backup,expectedDatabaseSHA256:databaseHash)
    }
    #expect(!FileManager.default.fileExists(atPath:missingQuarantine.path))
    try selectedDB.execute("DELETE FROM quarantine")
    try PortraitCandidateCoding.encoder().encode(receipt).write(to:source.appendingPathComponent("reconciliation-receipt.json"))
    databaseHash = PortraitCandidateCoding.digest(try Data(contentsOf:source.appendingPathComponent("library-v1.sqlite")))
    _ = try await DrawingRunEvidenceStore(fileURL:rawURL).annotateReview(.init(scope:.drawing("promotion"),text:"New raw generation"))
    let refused = directory.appendingPathComponent("refused/PortraitLibrary")
    await #expect(throws:(any Error).self) {
      _ = try await PortraitLibraryReconciler.installValidatedGeneration(sourceLibrary:source,destination:refused,
        legacyDirectory:legacy,evidenceArchive:rawURL,backupDirectory:backup,expectedDatabaseSHA256:databaseHash)
    }
    #expect(!FileManager.default.fileExists(atPath:refused.path))
  }

  @Test("Runtime modern manifest reconstructs typed evidence without inventing a wire archive schema")
  func modernEvidenceManifest() async throws {
    let directory = root();defer { try? FileManager.default.removeItem(at:directory) }
    let url = directory.appendingPathComponent("raw-evidence.json")
    let writer = DrawingRunEvidenceStore(fileURL:url)
    let expected = try await writer.annotateReview(.init(scope:.drawing("storage-diagnostic"),text:"Synthetic metadata only"))
    do {
      let source = try PortraitEvidenceSource.read(url)
      #expect(source.archive == expected)
      #expect(source.sha256 == PortraitCandidateCoding.digest(try Data(contentsOf:url)))
    } catch {
      print("RAW_SOURCE_DECODE_ERROR " + String(reflecting:error))
      if case DecodingError.keyNotFound(let key,let context) = error {
        print("RAW_SOURCE_MISSING_KEY " + key.stringValue + " CODING_PATH " + context.codingPath.map(\.stringValue).joined(separator:"."))
      }
      throw error
    }
  }

  @Test("Foreign keys reject orphan children and referenced ancestor deletion on every connection")
  func mandatoryAncestry() async throws {
    let directory = root();defer{try? FileManager.default.removeItem(at:directory)}
    let candidate = try portraitPersistenceCandidate()
    try await PortraitCandidateStore(directoryURL:directory).save(snapshot:.init(entries:[.init(candidate:candidate,reasons:[])]))
    let db = try PortraitLibraryDatabase(url:directory.appendingPathComponent("library-v1.sqlite"))
    #expect(try db.scalar("PRAGMA foreign_keys") == "1")
    #expect(throws:(any Error).self) { try db.execute("INSERT INTO work(id,drawing_id,run_id,executed,source_generation,payload) VALUES('orphan','missing','run',1,'generation','{}')") }
    #expect(throws:(any Error).self) { try db.execute("INSERT INTO media(id,work_id,source_generation,asset_hash,payload) VALUES('orphan','missing','generation','hash','{}')") }
    #expect(throws:(any Error).self) { try db.execute("DELETE FROM photo") }
    #expect(throws:(any Error).self) { try db.execute("UPDATE drawing SET photo_id=NULL") }
    try db.integrityCheck()
    let reader = try PortraitLibraryDatabase(url:db.url,readOnly:true)
    #expect(try reader.scalar("PRAGMA foreign_keys") == "1")
  }

  @Test("Unsupported schema and corrupt database never mutate or masquerade as an empty catalog")
  func unsupportedSchema() async throws {
    let directory = root();defer{try? FileManager.default.removeItem(at:directory)}
    let db = try PortraitLibraryDatabase(url:directory.appendingPathComponent("library-v1.sqlite"))
    try db.execute("PRAGMA user_version=99")
    let before = try Data(contentsOf:db.url)
    #expect(throws:(any Error).self) { _ = try PortraitLibraryDatabase(url:db.url) }
    let loaded = await PortraitCandidateStore(directoryURL:directory).load()
    #expect(!loaded.canWrite && !loaded.issues.isEmpty)
    #expect(try Data(contentsOf:db.url) == before)
  }

  @Test("Before-commit disk-full fault rolls back every new child and preserves previous generation")
  func rollbackBeforeCommit() async throws {
    let directory = root();defer{try? FileManager.default.removeItem(at:directory)}
    let store = PortraitCandidateStore(directoryURL:directory)
    let candidate = try portraitPersistenceCandidate()
    try await store.save(snapshot:.init(entries:[.init(candidate:candidate,reasons:[])]))
    let db = try PortraitLibraryDatabase(url:directory.appendingPathComponent("library-v1.sqlite"))
    let before = try db.generation
    db.injectFault = { point in if point == .beforeCommit { throw NSError(domain:NSPOSIXErrorDomain,code:28) } }
    #expect(throws:(any Error).self) {
      try db.transaction {
        try db.execute("INSERT INTO photo(id,source_hash,reference,captured_at) VALUES('new','hash','{}',0)")
        try db.bumpRevision()
      }
    }
    #expect(try db.scalar("SELECT COUNT(*) FROM photo WHERE id='new'") == "0")
    #expect(try db.generation == before)
    try db.integrityCheck()
  }

  @Test("After-commit interruption has durable committed truth on reopen")
  func reopenAfterCommitInterruption() throws {
    let directory = root();defer{try? FileManager.default.removeItem(at:directory)}
    let db = try PortraitLibraryDatabase(url:directory.appendingPathComponent("library-v1.sqlite"))
    db.injectFault = { point in if point == .afterCommit { throw NSError(domain:"interrupted",code:1) } }
    #expect(throws:(any Error).self) { try db.transaction { try db.setState("styles","[]");try db.bumpRevision() } }
    let reopened = try PortraitLibraryDatabase(url:db.url,readOnly:true)
    #expect(try reopened.generation.revision == 1)
    try reopened.integrityCheck()
  }

  @Test("Incomplete initial schema is not a selected generation and restart resumes legacy import")
  func incompleteInitialGeneration() async throws {
    let directory = root();defer{try? FileManager.default.removeItem(at:directory)}
    let candidate = try portraitPersistenceCandidate()
    let source = directory.appendingPathComponent("source"),target = directory.appendingPathComponent("target")
    try await PortraitCandidateStore(directoryURL:source).save(snapshot:.init(entries:[.init(candidate:candidate,reasons:[])]))
    let sourceDB = try PortraitLibraryDatabase(url:source.appendingPathComponent("library-v1.sqlite"),readOnly:true)
    let payload = try PortraitCandidateCoding.encoder().encode(sourceDB.index())
    try PortraitCandidateCoding.encoder().encode(IndexEnvelope(schemaVersion:4,sha256:PortraitCandidateCoding.digest(payload),payload:payload)).write(to:source.appendingPathComponent("index-v1.json"))
    _ = try PortraitLibraryDatabase(url:target.appendingPathComponent("library-v1.sqlite"))
    #expect(try !PortraitLibraryDatabase.hasCommittedGeneration(at:target.appendingPathComponent("library-v1.sqlite")))
    let restarted = PortraitCandidateStore(directoryURL:target,legacyDirectoryURL:source)
    let loaded = await restarted.load()
    #expect(loaded.canWrite && loaded.archive.entries.first?.id == candidate.id)
    #expect(try PortraitLibraryDatabase.hasCommittedGeneration(at:target.appendingPathComponent("library-v1.sqlite")))
  }

  @Test("Two capture UUIDs sharing one SHA are distinct roots and scoped tombstone cannot erase its sibling")
  func captureIdentity() async throws {
    let directory = root();defer{try? FileManager.default.removeItem(at:directory)}
    let candidate = try portraitPersistenceCandidate()
    let a = PortraitPhoto(id:UUID(),data:candidate.sourceData,label:"A",capturedAt:Date(),frameID:nil,captureNanoseconds:nil,pose:.front)
    let b = PortraitPhoto(id:UUID(),data:candidate.sourceData,label:"B",capturedAt:Date(),frameID:nil,captureNanoseconds:nil,pose:.front)
    let store = PortraitCandidateStore(directoryURL:directory)
    try await store.save(snapshot:.init(sourcePhotos:[a,b]))
    #expect(try await store.librarySnapshot().photos.count == 2)
    let tombstone = PortraitArchiveTombstone(id:UUID(),kind:.photo,identity:a.id.uuidString,affectedCandidateIDs:[],assetSHA256s:[PortraitCandidateCoding.digest(a.data)],createdAt:Date())
    try await store.save(snapshot:.init(tombstones:[tombstone],sourcePhotos:[b]))
    #expect(try await store.librarySnapshot().photos.map(\.id) == [b.id])
    try await store.save(snapshot:.init(sourcePhotos:[a,b]))
    #expect(try await store.librarySnapshot().photos.map(\.id) == [b.id])
    #expect(FileManager.default.fileExists(atPath:directory.appendingPathComponent("assets").appendingPathComponent(PortraitCandidateCoding.digest(b.data)).path))
  }

  @Test("FK-valid but conflicting projection payload is refused by the service")
  func semanticProjectionCorruption() async throws {
    let directory = root();defer{try? FileManager.default.removeItem(at:directory)}
    let candidate = try portraitPersistenceCandidate(),run = RunID()
    try await PortraitCandidateStore(directoryURL:directory).save(snapshot:.init(entries:[.init(candidate:candidate,reasons:[])]))
    let db = try PortraitLibraryDatabase(url:directory.appendingPathComponent("library-v1.sqlite"))
    let drawing = PortraitDrawingIdentity(candidateID:candidate.id,photoID:candidate.photoID)
    let work = PortraitLibraryWork(id:run.description,drawingID:drawing.id,photoID:UUID(),runID:run,recordID:nil,
      status:"possibleInk",recordedAt:nil,executedOrPossibleInk:true,sourceGeneration:"exact",media:[],recoveryMethod:"test")
    try db.execute("INSERT INTO work(id,drawing_id,run_id,executed,source_generation,payload) VALUES(?,?,?,?,?,?)",[run.description,drawing.id,run.description,"1","exact",try db.encode(work)])
    try db.integrityCheck() // SQL constraints alone cannot validate duplicated JSON.
    #expect(throws:(any Error).self) { _ = try db.workProjection(run.description) }
  }

  @Test("Changing the legacy generation invalidates pages until verified reconciliation")
  func sourceDrift() async throws {
    let directory = root();defer{try? FileManager.default.removeItem(at:directory)}
    let candidate = try portraitPersistenceCandidate()
    let store = PortraitCandidateStore(directoryURL:directory)
    try await store.save(snapshot:.init(entries:[.init(candidate:candidate,reasons:[])]))
    let db = try PortraitLibraryDatabase(url:directory.appendingPathComponent("library-v1.sqlite"))
    let legacy = directory.appendingPathComponent("index-v1.json")
    let original = Data("legacy-generation".utf8)
    try original.write(to:legacy)
    try db.setState("legacy_hash",PortraitCandidateCoding.digest(original))
    _ = try await store.librarySnapshot()
    try Data("changed-generation".utf8).write(to:legacy)
    await #expect(throws:(any Error).self) { _ = try await store.librarySnapshot() }
  }

  @Test("Ordinary save cannot acknowledge an unimported legacy delta; reopen merges its new capture")
  func unimportedDeltaCannotBeStamped() async throws {
    let directory = root();defer{try? FileManager.default.removeItem(at:directory)}
    let legacy = directory.appendingPathComponent("legacy"),canonical = directory.appendingPathComponent("canonical")
    let candidate = try portraitPersistenceCandidate()
    try await PortraitCandidateStore(directoryURL:legacy).save(snapshot:.init(entries:[.init(candidate:candidate,reasons:[])]))
    let sql = legacy.appendingPathComponent("library-v1.sqlite")
    var index = try PortraitLibraryDatabase(url:sql,readOnly:true).index()
    func publishFixture(_ index:IndexedArchive) throws {
      let payload = try PortraitCandidateCoding.encoder().encode(index)
      try PortraitCandidateCoding.encoder().encode(IndexEnvelope(schemaVersion:4,sha256:PortraitCandidateCoding.digest(payload),payload:payload)).write(to:legacy.appendingPathComponent("index-v1.json"))
    }
    try publishFixture(index);try FileManager.default.removeItem(at:sql)
    let store = PortraitCandidateStore(directoryURL:canonical,legacyDirectoryURL:legacy)
    let loaded = await store.load();#expect(loaded.canWrite)
    let extra = PortraitPhoto(id:UUID(),data:candidate.sourceData,label:"Late capture",capturedAt:Date(),frameID:nil,captureNanoseconds:nil,pose:.front)
    let references = (index.sourcePhotos ?? []) + [PortraitPhotoReference(extra)]
    index = IndexedArchive(schemaVersion:index.schemaVersion,entries:index.entries,labels:index.labels,tombstones:index.tombstones,
      savedStyles:index.savedStyles,sourcePhotos:references,photoCatalog:references,savedDrawings:index.savedDrawings,drawingCatalog:index.drawingCatalog)
    try publishFixture(index)
    await #expect(throws:(any Error).self) { try await store.save(snapshot:loaded.archive) }
    let reopened = PortraitCandidateStore(directoryURL:canonical,legacyDirectoryURL:legacy)
    let refreshed = await reopened.load();#expect(refreshed.canWrite)
    #expect(try await reopened.librarySnapshot().photos.contains{$0.id == extra.id})
    let snapshots = canonical.appendingPathComponent("ImportSnapshots")
    #expect(try FileManager.default.contentsOfDirectory(atPath:snapshots.path).count == 2)
  }

  @Test("Unknown legacy acquisition time stays unknown after full load, style save and reopen")
  func unknownAcquisitionTimeStaysUnknown() async throws {
    let directory = root();defer{try? FileManager.default.removeItem(at:directory)}
    let candidate = try portraitPersistenceCandidate()
    let store = PortraitCandidateStore(directoryURL:directory)
    try await store.save(snapshot:.init(entries:[.init(candidate:candidate,reasons:[])]))
    #expect(try await store.librarySnapshot().photos.first?.actualCapturedAt == nil)
    let loaded = await store.load()
    try await store.save(snapshot:loaded.archive)
    let reopened = PortraitCandidateStore(directoryURL:directory)
    #expect(try await reopened.librarySnapshot().photos.first?.actualCapturedAt == nil)
  }

  @Test("A photo descriptor cannot contradict its normalized capture identity even with no works")
  func photoDescriptorCorruption() async throws {
    let directory = root();defer{try? FileManager.default.removeItem(at:directory)}
    let candidate = try portraitPersistenceCandidate()
    let store = PortraitCandidateStore(directoryURL:directory)
    try await store.save(snapshot:.init(entries:[.init(candidate:candidate,reasons:[])]))
    let db = try PortraitLibraryDatabase(url:directory.appendingPathComponent("library-v1.sqlite"))
    let falsePhoto = PortraitPhoto(id:UUID(),data:candidate.sourceData,label:"False association",capturedAt:Date(),frameID:nil,captureNanoseconds:nil,pose:.front)
    try db.execute("UPDATE photo SET reference=?",[try db.encode(PortraitPhotoReference(falsePhoto))])
    try db.integrityCheck()
    await #expect(throws:(any Error).self) { _ = try await store.librarySnapshot() }
  }

  @Test("Conflicting legacy and canonical metadata changes fail closed without losing canonical styles or generic drawings")
  func simultaneousMetadataWritersRefuseMerge() async throws {
    let directory = root();defer{try? FileManager.default.removeItem(at:directory)}
    let legacy = directory.appendingPathComponent("legacy"),canonical = directory.appendingPathComponent("canonical")
    let candidate = try portraitPersistenceCandidate()
    try await PortraitCandidateStore(directoryURL:legacy).save(snapshot:.init(entries:[.init(candidate:candidate,reasons:[])]))
    let legacySQL = legacy.appendingPathComponent("library-v1.sqlite")
    let index = try PortraitLibraryDatabase(url:legacySQL,readOnly:true).index()
    let payload = try PortraitCandidateCoding.encoder().encode(index)
    let json = try PortraitCandidateCoding.encoder().encode(IndexEnvelope(schemaVersion:4,sha256:PortraitCandidateCoding.digest(payload),payload:payload))
    try json.write(to:legacy.appendingPathComponent("index-v1.json"));try FileManager.default.removeItem(at:legacySQL)
    let store = PortraitCandidateStore(directoryURL:canonical,legacyDirectoryURL:legacy)
    let loaded = await store.load();#expect(loaded.canWrite)
    var archive = loaded.archive
    let generic = SavedDrawing(program:try DrawingProgramCatalog.program(for:.square,style:candidate.program.strokes[0].style))
    archive.savedDrawings = (archive.savedDrawings ?? []) + [generic]
    archive.savedStyles = [.init(id:UUID(),name:"Canonical only",recipe:candidate.recipe,createdAt:Date())]
    try await store.save(snapshot:archive)
    let before = try Data(contentsOf:canonical.appendingPathComponent("library-v1.sqlite"))
    // A different, checksum-valid legacy generation that omits the new style.
    let changed = IndexedArchive(schemaVersion:index.schemaVersion,entries:index.entries,labels:index.labels,tombstones:index.tombstones,
      savedStyles:[],sourcePhotos:index.sourcePhotos,photoCatalog:index.photoCatalog,savedDrawings:index.savedDrawings,drawingCatalog:index.drawingCatalog)
    let changedPayload = try PortraitCandidateCoding.encoder().encode(changed)
    try PortraitCandidateCoding.encoder().encode(IndexEnvelope(schemaVersion:4,sha256:PortraitCandidateCoding.digest(changedPayload),payload:changedPayload)).write(to:legacy.appendingPathComponent("index-v1.json"))
    let after = await PortraitCandidateStore(directoryURL:canonical,legacyDirectoryURL:legacy).load()
    #expect(!after.canWrite)
    #expect(try Data(contentsOf:canonical.appendingPathComponent("library-v1.sqlite")) == before)
    let preserved = try PortraitLibraryDatabase(url:canonical.appendingPathComponent("library-v1.sqlite"),readOnly:true).index()
    #expect(preserved.savedStyles?.first?.name == "Canonical only")
    #expect(preserved.savedDrawings?.contains{$0.id == generic.id} == true)
  }
}
