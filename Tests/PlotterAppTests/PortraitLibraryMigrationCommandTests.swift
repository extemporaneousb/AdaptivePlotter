import Foundation
import PlotterRuntime
import Testing
@testable import PlotterApp

@Suite("Storage-only portrait reconciliation command")
struct PortraitLibraryMigrationCommandTests {
  @Test("Typed restart, same-generation idempotence and isolated raw drift", .enabled(if:ProcessInfo.processInfo.environment["PORTRAIT_VERIFY_LIBRARY"] != nil))
  func verifyValidatedGeneration() async throws {
    let env = ProcessInfo.processInfo.environment
    func input(_ key:String) throws -> URL { URL(fileURLWithPath:try #require(env[key])) }
    let library = try input("PORTRAIT_VERIFY_LIBRARY"),legacy = try input("PORTRAIT_VERIFY_LEGACY")
    let evidence = try input("PORTRAIT_VERIFY_EVIDENCE"),output = try input("PORTRAIT_VERIFY_RECEIPT")
    let started = Date(),store = PortraitCandidateStore(directoryURL:library,legacyDirectoryURL:legacy,evidenceArchiveURL:evidence)
    try await store.ensureLibraryGraph();try await store.verifyLibraryIntegrity();try await store.verifySelectedPayloads()
    let databaseURL = library.appendingPathComponent("library-v1.sqlite")
    let originalDBHash = PortraitCandidateCoding.digest(try Data(contentsOf:databaseURL))
    let db = try PortraitLibraryDatabase(url:databaseURL,readOnly:true),generation = try db.generation
    let raw = try PortraitEvidenceSource.read(evidence)
    try await store.reconcileEvidence(archive:raw.archive,generation:raw.sha256)
    #expect(try db.generation == generation)
    #expect(PortraitCandidateCoding.digest(try Data(contentsOf:databaseURL)) == originalDBHash)
    let queryStart = Date()
    var totals: [String:Int] = [:]
    for filter in PortraitLibraryFilter.allCases {
      var count = 0,cursor: PortraitLibraryCursor?
      repeat {
        let page = try await store.librarySnapshot(filter:filter,after:cursor)
        count += page.photos.count + page.works.count;cursor = page.next
      } while cursor != nil
      totals[filter.rawValue] = count
    }
    #expect(totals == ["allPhotos":160,"photosWithPlottedWorks":19,"photosWithoutPlottedWorks":141,"plottedWorks":23])
    let querySeconds = Date().timeIntervalSince(queryStart)
    var chains: [[String:Any]] = []
    let selectedChains = [("run_id","1e3c9f46-1ca2-4c94-a392-8a0e70a44d05"),("record_id","4148d2af-4e11-4530-b6b6-091a49ba97cc")]
    for (column,identity) in selectedChains {
      let selectedWorkID = try db.scalar("SELECT id FROM work WHERE "+column+"=?",[identity])
      let workID = try #require(selectedWorkID)
      let selection = try await store.librarySelection(workID:workID)
      let work = try #require(selection.works.first{$0.id == workID})
      let drawing = try #require(selection.selectedDrawing),program = try #require(selection.program)
      #expect(work.media.count == 6 && work.media.allSatisfy(\.isAvailable))
      #expect(program.contentHash.description == drawing.summary.programContentHash)
      #expect(work.drawingIdentity == drawing.identity && drawing.identity.photoID == selection.photo.id)
      chains.append(["recordID":work.recordID!.description,"runID":work.runID.description,"photoID":selection.photo.id.uuidString,
        "candidateID":drawing.identity.candidateID,"programHash":program.contentHash.description,"sourceHash":selection.photo.reference.sourceSHA256,
        "mediaStages":work.media.map(\.stage),"mediaHashes":work.media.map{ $0.reference.frame.frameSHA256 }])
    }
    let historicalID = "993711a19ff668fc1238eeba09b6743e750236998eb60805430d592f6af321cb"
    let selectedHistoricalPhoto = try db.scalar("SELECT photo_id FROM drawing WHERE candidate_id=? AND candidate_record IS NULL",[historicalID])
    let historicalPhoto = try #require(selectedHistoricalPhoto)
    let history = try await store.librarySelection(drawingIdentity:.init(candidateID:historicalID,photoID:try #require(UUID(uuidString:historicalPhoto))))
    #expect(history.selectedDrawing?.isRenderable == false && history.program != nil)
    let bootstrap = await store.loadMutationState()
    #expect(bootstrap.canWrite && bootstrap.archive.entries.isEmpty)
    #expect(await store.assetBytesVerified == 0)
    let cloneRoot = output.deletingLastPathComponent().appendingPathComponent("isolated-drift-"+UUID().uuidString)
    let cloneLibrary = cloneRoot.appendingPathComponent("PortraitLibrary"),cloneRaw = cloneRoot.appendingPathComponent("DrawingEvidence")
    try FileManager.default.createDirectory(at:cloneLibrary,withIntermediateDirectories:true)
    try await store.backupDatabase(to:cloneLibrary.appendingPathComponent("library-v1.sqlite"))
    for name in ["records","assets"] { try FileManager.default.copyItem(at:library.appendingPathComponent(name),to:cloneLibrary.appendingPathComponent(name)) }
    try FileManager.default.copyItem(at:evidence.deletingLastPathComponent(),to:cloneRaw)
    let cloneEvidence = cloneRaw.appendingPathComponent(evidence.lastPathComponent)
    let cloned = PortraitCandidateStore(directoryURL:cloneLibrary,legacyDirectoryURL:legacy,evidenceArchiveURL:cloneEvidence)
    let changed = try await DrawingRunEvidenceStore(fileURL:cloneEvidence).annotateReview(.init(scope:.drawing("disposable-drift"),text:"Isolated generation change; no machine effects"))
    await #expect(throws:(any Error).self) { _ = try await cloned.librarySnapshot() }
    try await cloned.reconcileEvidence(archive:changed,generation:PortraitCandidateCoding.digest(try Data(contentsOf:cloneEvidence)))
    let cloneDB = try PortraitLibraryDatabase(url:cloneLibrary.appendingPathComponent("library-v1.sqlite"),readOnly:true)
    #expect(try cloneDB.scalar("SELECT COUNT(*) FROM lineage_receipt") == "8")
    #expect(try cloneDB.scalar("SELECT COUNT(*) FROM work WHERE deleted=0") == "30")
    #expect(try cloneDB.scalar("SELECT COUNT(*) FROM work WHERE deleted=0 AND executed=1") == "23")
    #expect(try cloneDB.scalar("SELECT COUNT(*) FROM quarantine") == "4")
    try await cloned.verifyLibraryIntegrity()
    try await cloned.verifySelectedPayloads()
    let reopened = PortraitCandidateStore(directoryURL:cloneLibrary,legacyDirectoryURL:legacy,evidenceArchiveURL:cloneEvidence)
    #expect(try await reopened.librarySnapshot(filter:.photosWithPlottedWorks).photos.count == 19)
    #expect(try db.generation == generation && PortraitCandidateCoding.digest(Data(contentsOf:databaseURL)) == originalDBHash)
    #expect(try PortraitCandidateCoding.digest(Data(contentsOf:evidence)) == raw.sha256)
    let receipt: [String:Any] = ["sourceLibrary":library.path,"sourceDatabaseSHA256":originalDBHash,"evidenceSHA256":raw.sha256,
      "sameGenerationIdempotent":true,"typedQueryTotals":totals,"querySeconds":querySeconds,"elapsedSeconds":Date().timeIntervalSince(started),
      "chains":chains,"historicalCandidateID":historicalID,"historicalRenderable":false,"coldBootstrapHistoricalAssetBytes":await store.assetBytesVerified,
      "isolatedClone":cloneRoot.path,"recoveredReceiptsSurvivingDrift":8,"cloneWorks":30,"clonePlottedWorks":23,"cloneQuarantines":4]
    try JSONSerialization.data(withJSONObject:receipt,options:[.sortedKeys,.prettyPrinted]).write(to:output,options:.atomic)
    print("PORTRAIT_TYPED_ACCEPTANCE_RECEIPT "+output.path)
  }

  @Test("Explicit migration inputs", .enabled(if:ProcessInfo.processInfo.environment["PORTRAIT_RECONCILE_LEGACY"] != nil))
  func runCommand() async throws {
    let env = ProcessInfo.processInfo.environment
    func input(_ key:String) throws -> URL { URL(fileURLWithPath:try #require(env[key])) }
    let receipt: PortraitLibraryReconciler.Receipt
    if let source = env["PORTRAIT_RECONCILE_PROMOTE_SOURCE"] {
      receipt = try await PortraitLibraryReconciler.installValidatedGeneration(sourceLibrary:URL(fileURLWithPath:source),
        destination:input("PORTRAIT_RECONCILE_DESTINATION"),legacyDirectory:input("PORTRAIT_RECONCILE_LEGACY"),
        evidenceArchive:input("PORTRAIT_RECONCILE_EVIDENCE"),backupDirectory:input("PORTRAIT_RECONCILE_BACKUP"),
        expectedDatabaseSHA256:try #require(env["PORTRAIT_RECONCILE_PROMOTE_DB_SHA256"]),
        auditURL:env["PORTRAIT_RECONCILE_AUDIT"].map{URL(fileURLWithPath:$0)})
    } else {
      receipt = try await PortraitLibraryReconciler.run(legacyDirectory:input("PORTRAIT_RECONCILE_LEGACY"),
        evidenceArchive:input("PORTRAIT_RECONCILE_EVIDENCE"),destination:input("PORTRAIT_RECONCILE_DESTINATION"),
        backupDirectory:input("PORTRAIT_RECONCILE_BACKUP"),auditURL:env["PORTRAIT_RECONCILE_AUDIT"].map{URL(fileURLWithPath:$0)})
    }
    let bytes = try PortraitCandidateCoding.encoder().encode(receipt)
    if let output = env["PORTRAIT_RECONCILE_RECEIPT"] { try bytes.write(to:URL(fileURLWithPath:output),options:.atomic) }
    print("PORTRAIT_RECONCILIATION_RECEIPT " + String(decoding:bytes,as:UTF8.self))
  }
}
