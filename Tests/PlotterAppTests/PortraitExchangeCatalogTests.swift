import Darwin
import Foundation
import CryptoKit
import PortraitCore
@testable import PortraitLibrary
import Testing

@Suite("Drawing Exchange catalog foundation", .serialized)
struct PortraitExchangeCatalogTests {
  @Test("Exact publication is idempotent, record lookup pins the digest and metadata remains explicit")
  func exactPublication() throws {
    let root = try DX04Fixture.root(); defer { try? FileManager.default.removeItem(at: root) }
    let admitted = try DX04Fixture.admitted(parent: root)
    let db = try PortraitLibraryDatabase(url: root.appendingPathComponent("library/library-v1.sqlite"))
    let catalog = try PortraitExchangeCatalog(database: db)
    let ref = PortraitExchangeReference.drawing(try #require(admitted.index.known?.roots.first))
    let first = try catalog.publish(admitted, metadata: [.init(reference: ref, title: "Original", retentionReasons: ["explicit-save"])])
    let count = try db.scalar("SELECT total_changes()")
    let again = try catalog.publish(admitted)
    #expect(again.wasAlreadyPublished && again.transactionID == first.transactionID)
    #expect(try db.scalar("SELECT total_changes()") == count)
    #expect(ExchangeDigest.hash(try catalog.record(ref)) == ref.digest)
    #expect(try catalog.metadata(ref)?.retentionReasons == ["explicit-save"])
    #expect(throws: (any Error).self) { _ = try catalog.record(ref, maximumBytes: -1) }
    if case .drawing(let drawing) = ref {
      let wrong = DrawingRef(issuer: drawing.issuer, revision: drawing.revision, digest: .hash(Data("wrong".utf8)))
      #expect(throws: (any Error).self) { _ = try catalog.lookup(.drawing(wrong)) }
    }
    try db.integrityCheck()
  }

  @Test("Unknown index majors remain inert preserved groups without invented source-free drawings")
  func opaqueIndexPreservation() throws {
    let root = try DX04Fixture.root(); defer { try? FileManager.default.removeItem(at: root) }
    let fixture = DX04Fixture.fixture.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("dx03/closure/unknown-index-minimal.zip")
    let admitted = try ExchangeAdmission.validate(DrawingExchangeCarrier.stageZIP(fixture, stagingParent: root))
    let db = try PortraitLibraryDatabase(url: root.appendingPathComponent("library/library-v1.sqlite"))
    let catalog = try PortraitExchangeCatalog(database: db)
    _ = try catalog.publish(admitted)
    #expect(try db.scalar("SELECT COUNT(*) FROM dx_record") == "0")
    #expect(try db.scalar("SELECT COUNT(*) FROM photo") == "0")
    for entry in admitted.files.entries.values { try catalog.storage.verifyObject(digest: entry.digest, byteLength: entry.byteLength) }
    #expect(try catalog.publish(admitted).wasAlreadyPublished)
  }

  @Test("Opaque future paths and equal-byte distinct names retain authoritative mapping after journal cleanup and restart")
  func opaquePathInventory() throws {
    let root = try DX04Fixture.root(); defer { try? FileManager.default.removeItem(at:root) }
    let index = Data("{\"profile\":\"adaptiveplotter.exchange/9\",\"vendor\":\"future arbitrary layout\"}".utf8),same = Data([1,2,3,4,5])
    let bag = try DrawingExchangeCarrierTestBag(files:["data/exchange.json":index,"data/future/tree/alpha.payload":same,"data/vendor/another-name.bin":same])
    defer { bag.dispose() }
    let admitted = try ExchangeAdmission.validate(DrawingExchangeCarrier.stageDirectory(bag.source,stagingParent:root))
    let expected = admitted.files.entries.values.map { PortraitExchangeStorageEntry(path:$0.path,digest:$0.digest,byteLength:$0.byteLength) }.sorted{$0.path < $1.path}
    let sql = root.appendingPathComponent("library/library-v1.sqlite"),transaction: UUID
    do {
      let db = try PortraitLibraryDatabase(url:sql),catalog = try PortraitExchangeCatalog(database:db)
      transaction = try catalog.publish(admitted).transactionID
      #expect(try catalog.storage.pendingTransactions().isEmpty)
      #expect(try catalog.publicationInventory(transactionID:transaction) == expected)
      #expect(try db.scalar("SELECT COUNT(*) FROM dx_tx_file") == String(expected.count))
      #expect(try db.scalar("SELECT COUNT(*) FROM dx_tx_object") == String(Set(expected.map(\.digest)).count))
      #expect(throws:(any Error).self) { try db.execute("DELETE FROM dx_tx_object WHERE transaction_id=?",[transaction.uuidString.lowercased()]) }
    }
    let reopened = try PortraitExchangeCatalog(database:PortraitLibraryDatabase(url:sql))
    let mapping = try reopened.publicationInventory(transactionID:transaction)
    #expect(mapping == expected)
    #expect(mapping.first{$0.path == "data/future/tree/alpha.payload"}?.digest == mapping.first{$0.path == "data/vendor/another-name.bin"}?.digest)
    #expect(try reopened.publish(admitted).wasAlreadyPublished)
  }

  @Test("Incomplete or divergent stored path inventory refuses query and idempotent retry despite intact blobs")
  func storedInventoryCorruption() throws {
    for mutation in ["missing","renamed"] {
      let root = try DX04Fixture.root(); defer { try? FileManager.default.removeItem(at:root) }
      let admitted = try DX04Fixture.admitted(parent:root)
      let db = try PortraitLibraryDatabase(url:root.appendingPathComponent("library/library-v1.sqlite"))
      let catalog = try PortraitExchangeCatalog(database:db)
      let transaction = try catalog.publish(admitted).transactionID
      if mutation == "missing" { try db.execute("DELETE FROM dx_tx_file WHERE path='data/exchange.json'") }
      else { try db.execute("UPDATE dx_tx_file SET path='data/renamed.json' WHERE path='data/exchange.json'") }
      try db.integrityCheck() // FK validity alone cannot reconstruct the original closure.
      #expect(throws:(any Error).self) { _ = try catalog.publicationInventory(transactionID:transaction) }
      #expect(throws:(any Error).self) { _ = try catalog.publish(admitted) }
    }
  }

  @Test("Known input-to-photo edge stays exact even when photo profile is opaque")
  func normalizedInputPhoto() throws {
    let root = try DX04Fixture.root(); defer { try? FileManager.default.removeItem(at: root) }
    let issuer = UUID(), photoID = UUID(), inputID = UUID()
    let issuerText = issuer.uuidString.lowercased(), photoText = photoID.uuidString.lowercased(), inputText = inputID.uuidString.lowercased()
    let photo = try JSONSerialization.data(withJSONObject: ["profile":"adaptiveplotter.photo/9","ref":["issuer":issuerText,"revision":photoText],"vendor":"opaque"])
    let pixels = Data([10,20]), parameters = Data("{}".utf8)
    let raster = try ExchangeAsset(bytes: pixels,mediaType:"application/octet-stream",encoding:"raw-gray8")
    let parameter = try ExchangeAsset(bytes: parameters,mediaType:"application/json",encoding:"example.parameters/1")
    let layout = try ExchangeRasterLayout(width:2,height:1,bytesPerPixel:1,rowStride:2)
    func json<T: Encodable>(_ value: T) throws -> Any { try JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) }
    let descriptor = ExchangeAssetDescriptor(asset:raster,pixelLayout:layout)
    let input: [String:Any] = ["profile":"adaptiveplotter.image-input/1","requiredFeatures":[],"ref":["issuer":issuerText,"revision":inputText],
      "photo":["issuer":issuerText,"revision":photoText,"digest":ExchangeDigest.hash(photo).description],
      "pixelBasis":["dimensions":["width":2,"height":1],"orientation":"up","origin":"top-left","xAxis":"right","yAxis":"down","pixelEdges":"integer","pixelCenters":"half-integer"],
      "sourceToInput":[1,0,0,0,1,0,0,0,1],"inputToField":[1,0,0,0,1,0,0,0,1],"raster":try json(descriptor),"mask":["state":"none"],
      "operations":[["kind":"identity","parameters":try json(parameter)]],"preparation":["id":"example.preparation","version":"1","record":parameter.object.description]]
    let inputBytes = try JSONSerialization.data(withJSONObject:input)
    let inputRef = ImageInputRef(issuer:issuer,revision:inputID,digest:.hash(inputBytes))
    let index: [String:Any] = ["profile":"adaptiveplotter.exchange/1","requiredFeatures":[],"kind":"feedback","roots":[],"includedAsOf":"2026-11-07T00:00:00Z",
      "assets":try [descriptor,ExchangeAssetDescriptor(asset:parameter)].map(json),"attempts":[],"assessments":[],"inputs":[try json(inputRef)]]
    let bag = try DrawingExchangeCarrierTestBag(files:["data/exchange.json":try JSONSerialization.data(withJSONObject:index),
      "data/photos/"+issuerText+"/"+photoText+"/photo.json":photo,"data/inputs/"+issuerText+"/"+inputText+"/input.json":inputBytes,
      "data/objects/sha256/"+raster.object.description:pixels,"data/objects/sha256/"+parameter.object.description:parameters])
    defer { bag.dispose() }
    let admitted = try ExchangeAdmission.validate(DrawingExchangeCarrier.stageDirectory(bag.source,stagingParent:root))
    let db = try PortraitLibraryDatabase(url:root.appendingPathComponent("library/library-v1.sqlite"))
    _ = try PortraitExchangeCatalog(database:db).publish(admitted)
    let edge = try db.rows("SELECT source_kind,target_kind,relation FROM dx_link")
    #expect(edge.count == 1 && edge[0][0] == "input" && edge[0][1] == "photo" && edge[0][2] == "photo")
    #expect(try db.scalar("SELECT COUNT(*) FROM drawing") == "0")
  }

  @Test("Divergent exact identity preserves incoming bytes and never replaces the selected record")
  func divergentIdentity() throws {
    let root = try DX04Fixture.root(); defer { try? FileManager.default.removeItem(at: root) }
    let admitted = try DX04Fixture.admitted(parent: root)
    let db = try PortraitLibraryDatabase(url: root.appendingPathComponent("library/library-v1.sqlite"))
    let catalog = try PortraitExchangeCatalog(database: db)
    let original = try #require(admitted.index.known?.roots.first)
    _ = try catalog.publish(admitted)
    let changed = try DX04Fixture.changedDrawing(admitted, parent: root)
    var conflictURL: URL?
    do { _ = try catalog.publish(changed); Issue.record("Expected preserved conflict") }
    catch PortraitExchangeCatalogError.preservedConflict(let url) { conflictURL = url }
    #expect(FileManager.default.fileExists(atPath: try #require(conflictURL).path))
    #expect(ExchangeDigest.hash(try catalog.record(.drawing(original))) == original.digest)
    #expect(try db.scalar("SELECT COUNT(*) FROM dx_transaction") == "1")
  }

  @Test("Shared issuer/revision cannot change record kind across separate admitted deliveries")
  func crossDeliveryIdentityKindConflict() throws {
    let root = try DX04Fixture.root(); defer { try? FileManager.default.removeItem(at:root) }
    let drawing = try DX04Fixture.admitted(parent:root),ref = try #require(drawing.index.known?.roots.first)
    let issuer = ref.issuer.uuidString.lowercased(),revision = ref.revision.uuidString.lowercased()
    let photo = try JSONSerialization.data(withJSONObject:["profile":"adaptiveplotter.photo/9","ref":["issuer":issuer,"revision":revision],"vendor":"opaque"])
    let photoRef = PhotoRef(issuer:ref.issuer,revision:ref.revision,digest:.hash(photo))
    let encodedRef = try JSONSerialization.jsonObject(with:JSONEncoder().encode(photoRef))
    let index: [String:Any] = ["profile":"adaptiveplotter.exchange/1","requiredFeatures":[],"kind":"feedback","roots":[],"includedAsOf":"2026-11-07T00:00:00Z","assets":[],"attempts":[],"assessments":[],"photos":[encodedRef]]
    let bag = try DrawingExchangeCarrierTestBag(files:["data/exchange.json":try JSONSerialization.data(withJSONObject:index),"data/photos/"+issuer+"/"+revision+"/photo.json":photo])
    defer { bag.dispose() }
    let admitted = try ExchangeAdmission.validate(DrawingExchangeCarrier.stageDirectory(bag.source,stagingParent:root))
    let db = try PortraitLibraryDatabase(url:root.appendingPathComponent("library/library-v1.sqlite")),catalog = try PortraitExchangeCatalog(database:db)
    _ = try catalog.publish(admitted)
    #expect(throws:PortraitExchangeCatalogError.self) { _ = try catalog.publish(drawing) }
    #expect(try db.scalar("SELECT COUNT(*) FROM dx_record") == "1")
    #expect(try db.scalar("SELECT kind FROM dx_record") == "photo")
    #expect(try FileManager.default.contentsOfDirectory(atPath:root.appendingPathComponent("library/exchange-conflicts").path).count == 1)
  }

  @Test("Uncertain post-COMMIT response retries the original durable transaction")
  func uncertainCommit() throws {
    let root = try DX04Fixture.root(); defer { try? FileManager.default.removeItem(at: root) }
    let admitted = try DX04Fixture.admitted(parent: root)
    let db = try PortraitLibraryDatabase(url: root.appendingPathComponent("library/library-v1.sqlite"))
    let catalog = try PortraitExchangeCatalog(database: db)
    catalog.injectFault = { if $0 == .afterSQLCommit { throw DX04Fixture.Failure.injected } }
    #expect(throws: (any Error).self) { _ = try catalog.publish(admitted) }
    catalog.injectFault = nil
    try catalog.recover()
    #expect(try catalog.publish(admitted).wasAlreadyPublished)
    #expect(try db.scalar("SELECT COUNT(*) FROM dx_transaction") == "1")
    #expect(try catalog.storage.pendingTransactions().isEmpty)
  }

  @Test("Missing or corrupt selected objects refuse exact retry and bounded record load")
  func missingObject() throws {
    let root = try DX04Fixture.root(); defer { try? FileManager.default.removeItem(at: root) }
    let admitted = try DX04Fixture.admitted(parent: root)
    let db = try PortraitLibraryDatabase(url: root.appendingPathComponent("library/library-v1.sqlite"))
    let catalog = try PortraitExchangeCatalog(database: db)
    let ref = try #require(admitted.index.known?.roots.first)
    _ = try catalog.publish(admitted)
    let object = catalog.storage.objectURL(digest: ref.digest)
    let original = try Data(contentsOf: object)
    try FileManager.default.removeItem(at: object)
    #expect(throws: (any Error).self) { _ = try catalog.record(.drawing(ref)) }
    #expect(throws: (any Error).self) { _ = try catalog.publish(admitted) }
    try Data("corrupt".utf8).write(to: object)
    #expect(throws: (any Error).self) { _ = try catalog.record(.drawing(ref)) }
    try original.write(to: object)
    #expect(try catalog.publish(admitted).wasAlreadyPublished)
  }

  @Test("One metadata update writes two rows at 1 and 10001 exact indexed references; explicit rebuild preserves authority")
  func boundedMetadataMutation() throws {
    let root = try DX04Fixture.root(); defer { try? FileManager.default.removeItem(at: root) }
    let admitted = try DX04Fixture.admitted(parent: root)
    let db = try PortraitLibraryDatabase(url: root.appendingPathComponent("library/library-v1.sqlite"))
    let catalog = try PortraitExchangeCatalog(database: db)
    let ref = PortraitExchangeReference.drawing(try #require(admitted.index.known?.roots.first))
    _ = try catalog.publish(admitted)
    func updateDelta(_ title: String) throws -> Int {
      let before = Int(try db.scalar("SELECT total_changes()") ?? "0")!
      try catalog.updateMetadata(.init(reference: ref, title: title, retentionReasons: ["chosen"], tombstoned: true))
      return Int(try db.scalar("SELECT total_changes()") ?? "0")! - before
    }
    #expect(try updateDelta("Small") == 2)
    try db.transaction {
      for _ in 0..<10_000 {
        let key = ["drawing", UUID().uuidString.lowercased(), UUID().uuidString.lowercased(), ref.digest.description]
        try db.execute("INSERT INTO dx_record(kind,namespace,identity,digest) VALUES(?,?,?,?)", key.map(Optional.some))
        try db.execute("INSERT INTO dx_summary(kind,namespace,identity,digest) VALUES(?,?,?,?)", key.map(Optional.some))
      }
    }
    #expect(try updateDelta("Large") == 2)
    let metadata = try catalog.metadata(ref)
    let immutable = try db.scalar("SELECT COUNT(*) FROM dx_record")
    try catalog.rebuildDerivedRows()
    #expect(try db.scalar("SELECT COUNT(*) FROM dx_record") == immutable)
    #expect(try catalog.metadata(ref) == metadata)
    #expect(metadata?.tombstoned == true && metadata?.retentionReasons == ["chosen"])
  }

  @Test("Actor metadata wrapper reuses startup validation and writes two rows at 1 and 10001 indexed references")
  func boundedActorMetadataMutation() async throws {
    let root = try DX04Fixture.root(); defer { try? FileManager.default.removeItem(at:root) }
    let store = PortraitCandidateStore(directoryURL:root.appendingPathComponent("library"))
    let admitted = try DX04Fixture.admitted(parent:root)
    let catalog = try await store.exchangeCatalog(), db = catalog.database
    let ref = PortraitExchangeReference.drawing(try #require(admitted.index.known?.roots.first))
    _ = try await store.publishExchange(admitted)
    func updateDelta(_ title: String) async throws -> Int {
      let before = Int(try db.scalar("SELECT total_changes()") ?? "0")!
      try await store.updateExchangeMetadata(.init(reference:ref,title:title,retentionReasons:["chosen"],tombstoned:true))
      return Int(try db.scalar("SELECT total_changes()") ?? "0")! - before
    }
    #expect(try await updateDelta("Small") == 2)
    try db.transaction {
      for _ in 0..<10_000 {
        let key = ["drawing",UUID().uuidString.lowercased(),UUID().uuidString.lowercased(),ref.digest.description]
        try db.execute("INSERT INTO dx_record(kind,namespace,identity,digest) VALUES(?,?,?,?)",key.map(Optional.some))
        try db.execute("INSERT INTO dx_summary(kind,namespace,identity,digest) VALUES(?,?,?,?)",key.map(Optional.some))
      }
    }
    #expect(try await updateDelta("Large") == 2)
    let cached = try await store.exchangeCatalog()
    #expect(cached === catalog) // A reconstruction would repeat integrity/recovery scans.
    #expect(try catalog.metadata(ref)?.title == "Large")
    let ownerDB = try await store.libraryDatabase()
    let actorGeneration = try ownerDB.generation, expectedGeneration = try db.generation
    #expect(actorGeneration == expectedGeneration)
  }

  @Test("Explicit backup generation restores titles, retention and tombstones after catalog loss")
  func metadataRestore() async throws {
    let root = try DX04Fixture.root(); defer { try? FileManager.default.removeItem(at: root) }
    let library = root.appendingPathComponent("library"), store = PortraitCandidateStore(directoryURL: library)
    let admitted = try DX04Fixture.admitted(parent: root)
    let ref = PortraitExchangeReference.drawing(try #require(admitted.index.known?.roots.first))
    var catalog: PortraitExchangeCatalog? = try await store.exchangeCatalog()
    let transaction = try #require(catalog).publish(admitted).transactionID
    let expected = PortraitExchangeMetadata(reference: ref, title: "Kept title", retentionReasons: ["chosen", "plot-submitted"], tombstoned: true)
    try #require(catalog).updateMetadata(expected)
    let generation = try await store.createExchangeMetadataBackup()
    catalog = nil; await store.closeLibrary()
    try FileManager.default.removeItem(at: library.appendingPathComponent("library-v1.sqlite"))
    #expect(throws: (any Error).self) { _ = try PortraitLibraryDatabase(url: library.appendingPathComponent("library-v1.sqlite")) }
    try PortraitExchangeCatalog.restore(root: library, generationID: generation.generationID)
    let restored = try await store.exchangeCatalog()
    #expect(try restored.metadata(ref) == expected)
    #expect(try restored.publish(admitted).transactionID == transaction)
    try restored.database.integrityCheck()
  }

  @Test("Marker-selected missing/corrupt SQL and unsafe markers refuse normal browse instead of legacy fallback")
  func selectedCatalogLoss() async throws {
    for mode in ["missing", "corrupt", "broken-marker", "unknown-marker"] {
      let root = try DX04Fixture.root(); defer { try? FileManager.default.removeItem(at: root) }
      let library = root.appendingPathComponent("library"), store = PortraitCandidateStore(directoryURL: library)
      var catalog: PortraitExchangeCatalog? = try await store.exchangeCatalog()
      #expect(catalog != nil)
      catalog = nil; await store.closeLibrary()
      let sql = library.appendingPathComponent("library-v1.sqlite"), marker = library.appendingPathComponent("exchange-authority.json")
      try Data("legacy would be an invalid fallback".utf8).write(to: library.appendingPathComponent("index-v1.json"))
      switch mode {
      case "missing": try FileManager.default.removeItem(at: sql)
      case "corrupt": try Data("broken sqlite".utf8).write(to: sql)
      case "broken-marker": try FileManager.default.removeItem(at: marker); try FileManager.default.createSymbolicLink(at: marker, withDestinationURL: root.appendingPathComponent("absent"))
      default: try Data("{\"version\":999,\"catalog\":\"library-v1.sqlite\"}".utf8).write(to: marker)
      }
      #expect(throws: (any Error).self) { _ = try store.loadPhotoPage() }
      #expect(throws: (any Error).self) { _ = try store.loadDrawingPage() }
      #expect(throws: (any Error).self) { _ = try store.loadDrawingPage(photoID: UUID()) }
      await #expect(throws: (any Error).self) { _ = try await store.loadSavedStyles() }
      let loaded = await store.load()
      #expect(!loaded.canWrite)
    }
  }

  @Test("One browse Store reobserves absent then selected authority and reads independently of the live writer")
  func browseSelectionReobserved() async throws {
    let root = try DX04Fixture.root(); defer { try? FileManager.default.removeItem(at: root) }
    let library = root.appendingPathComponent("library"), store = PortraitCandidateStore(directoryURL: library)
    #expect(try store.loadPhotoPage().photos.isEmpty)
    #expect(try store.loadDrawingPage(photoID: UUID()).drawings.isEmpty)
    #expect(!FileManager.default.fileExists(atPath: library.path))
    var catalog: PortraitExchangeCatalog? = try await store.exchangeCatalog()
    #expect(catalog != nil)
    // Both queries are independent readonly connections while the actual writer lives.
    #expect(try store.loadPhotoPage().photos.isEmpty)
    #expect(try store.loadDrawingPage(photoID: UUID()).drawings.isEmpty)
    catalog = nil; await store.closeLibrary()
    try FileManager.default.removeItem(at: library.appendingPathComponent("library-v1.sqlite"))
    #expect(throws: (any Error).self) { _ = try store.loadPhotoPage() }
    #expect(throws: (any Error).self) { _ = try store.loadDrawingPage(photoID: UUID()) }
  }

  @Test("Selected authority without a committed legacy graph refuses bootstrap and preserves both authorities")
  func selectedUncommittedGraphRefusesImport() async throws {
    let root = try DX04Fixture.root(); defer { try? FileManager.default.removeItem(at: root) }
    let library = root.appendingPathComponent("library"), store = PortraitCandidateStore(directoryURL: library)
    let catalog = try await store.exchangeCatalog()
    let admitted = try DX04Fixture.admitted(parent: root)
    let ref = PortraitExchangeReference.drawing(try #require(admitted.index.known?.roots.first))
    let metadata = PortraitExchangeMetadata(reference: ref, title: "Keep exact metadata", retentionReasons: ["operator"], tombstoned: true)
    _ = try catalog.publish(admitted, metadata: [metadata])
    let legacy = library.appendingPathComponent("index-v1.json")
    let legacyBytes = Data("Preserved legacy evidence must never replace selected mutable authority".utf8)
    try legacyBytes.write(to: legacy)
    let before = try Data(contentsOf: catalog.database.url)
    let flag = try catalog.database.scalar("SELECT value FROM state WHERE key='portrait_graph_selected'")
    #expect(flag != "1")
    await #expect(throws: (any Error).self) { try await store.ensureLibraryGraph() }
    await #expect(throws: (any Error).self) { _ = try await store.librarySnapshot() }
    await #expect(throws: (any Error).self) { _ = try await store.loadSavedStyles() }
    #expect(try catalog.database.scalar("SELECT value FROM state WHERE key='portrait_graph_selected'") == flag)
    #expect(try catalog.metadata(ref) == metadata)
    #expect(try Data(contentsOf: catalog.database.url) == before)
    #expect(try Data(contentsOf: legacy) == legacyBytes)
  }

  @Test("Readonly projection connections opened before real atomic restore refuse displaced SQL for index and filtered queries")
  func readonlyRestoreRace() async throws {
    let root = try DX04Fixture.root(); defer { try? FileManager.default.removeItem(at: root) }
    let library = root.appendingPathComponent("library"), store = PortraitCandidateStore(directoryURL: library)
    let admitted = try DX04Fixture.admitted(parent: root)
    let ref = PortraitExchangeReference.drawing(try #require(admitted.index.known?.roots.first))
    var catalog: PortraitExchangeCatalog? = try await store.exchangeCatalog()
    _ = try #require(catalog).publish(admitted, metadata: [.init(reference: ref, title: "Selected backup B")])
    let generation = try await store.createExchangeMetadataBackup()
    try #require(catalog).updateMetadata(.init(reference: ref, title: "Displaced connection A"))
    let sql = library.appendingPathComponent("library-v1.sqlite")
    let displaced = try PortraitLibraryDatabase(url: sql, readOnly: true)
    let revisionA = try displaced.generation.revision
    catalog = nil; await store.closeLibrary()
    try PortraitExchangeCatalog.restore(root: library, generationID: generation.generationID)
    let selected = try PortraitLibraryDatabase(url: sql, readOnly: true)
    let revisionB = try selected.generation.revision
    #expect(revisionA != revisionB)
    print("DX04_READONLY_RESTORE_GENERATIONS oldRevision=\(revisionA) selectedRevision=\(revisionB)")
    do { print("DX04_DISPLACED_RAW_GENERATION=\(try displaced.generation.revision)") }
    catch { print("DX04_DISPLACED_RAW_GENERATION_ERROR type=\(type(of: error)) error=\(error)") }
    var indexError: (any Error)?, filteredError: (any Error)?
    do { _ = try PortraitCandidateStore.browseIndex(sql, database: displaced) }
    catch { indexError = error; print("DX04_DISPLACED_INDEX_ERROR type=\(type(of: error)) error=\(error)") }
    do { _ = try store.drawingPage(database: displaced, photoID: UUID()) }
    catch { filteredError = error; print("DX04_DISPLACED_FILTERED_ERROR type=\(type(of: error)) error=\(error)") }
    #expect(indexError != nil)
    #expect(filteredError != nil)
    _ = try PortraitCandidateStore.browseIndex(sql, database: selected)
    #expect(try store.drawingPage(database: selected, photoID: UUID()).drawings.isEmpty)
  }

  @Test("A live cached owner refuses selected SQL loss or replacement before staging new assets")
  func liveSelectedSQLIdentity() async throws {
    for replacement in [false,true] {
      let root = try DX04Fixture.root(); defer { try? FileManager.default.removeItem(at:root) }
      let library = root.appendingPathComponent("library"),store = PortraitCandidateStore(directoryURL:library)
      let admitted = try DX04Fixture.admitted(parent:root)
      var catalog: PortraitExchangeCatalog? = try await store.exchangeCatalog()
      let sql = library.appendingPathComponent("library-v1.sqlite")
      try FileManager.default.moveItem(at:sql,to:library.appendingPathComponent("retained-original.sqlite"))
      if replacement { try Data("replacement".utf8).write(to:sql) }
      #expect(throws:(any Error).self) { _ = try #require(catalog).publish(admitted) }
      await #expect(throws:(any Error).self) { _ = try await store.libraryDatabase() }
      #expect(try FileManager.default.contentsOfDirectory(atPath:library.appendingPathComponent("exchange-staging").path).isEmpty)
      catalog = nil; await store.closeLibrary()
    }
  }

  @Test("Metadata backup refuses missing selected local/review objects and external quarantine without materializing media")
  func selectedBackupClosure() async throws {
    let root = try DX04Fixture.root(); defer { try? FileManager.default.removeItem(at:root) }
    let library = root.appendingPathComponent("library"),store = PortraitCandidateStore(directoryURL:library)
    let candidate = try portraitPersistenceCandidate()
    _ = try await store.save(snapshot:.init(entries:[.init(candidate:candidate,reasons:[])]))
    let source = library.appendingPathComponent("assets/" + candidate.sourceSHA256)
    let bytes = try Data(contentsOf:source)
    try FileManager.default.removeItem(at:source)
    await #expect(throws:(any Error).self) { _ = try await store.createExchangeMetadataBackup() }
    try bytes.write(to:source)
    let db = try await store.libraryDatabase()
    let missing = ExchangeDigest.hash(Data("missing-review".utf8)).description
    try db.setState("review.request." + UUID().uuidString.lowercased(),missing)
    await #expect(throws:(any Error).self) { _ = try await store.createExchangeMetadataBackup() }
    try db.execute("DELETE FROM state WHERE key LIKE 'review.request.%'")
    try db.execute("INSERT INTO quarantine(id,reason,manifest) VALUES('external','separate archive owner','{}')")
    await #expect(throws:PortraitExchangeCatalogError.self) { _ = try await store.createExchangeMetadataBackup() }
  }

  @Test("External quarantine originals stream beyond metadata bounds and unavailable owner blocks restore before selection")
  func externalQuarantineAvailability() async throws {
    let root = try DX04Fixture.root(); defer { try? FileManager.default.removeItem(at:root) }
    let library = root.appendingPathComponent("library"),store = PortraitCandidateStore(directoryURL:library)
    let id = UUID().uuidString.lowercased(),reason = "historical exact association unavailable"
    let external = root.appendingPathComponent("PortraitQuarantine/" + id)
    try FileManager.default.createDirectory(at:external,withIntermediateDirectories:true)
    let original = external.appendingPathComponent("original-evidence.bin")
    FileManager.default.createFile(atPath:original.path,contents:nil)
    let output = try FileHandle(forWritingTo:original)
    let buffer = Data(repeating:0x51,count:1024 * 1024)
    var hash = SHA256()
    for _ in 0..<9 { try output.write(contentsOf:buffer); hash.update(data:buffer) }
    try output.synchronize(); try output.close()
    let generation = hash.finalize().map { String(format:"%02x",$0) }.joined()
    let payload = Data("{}".utf8),payloadHash = ExchangeDigest.hash(payload).description
    try payload.write(to:external.appendingPathComponent(payloadHash + ".json"))
    let manifest: [String:Any] = ["id":id,"reason":reason,"sourceGeneration":generation,"payloadSHA256":payloadHash,
      "originalFiles":[["file":"original-evidence.bin","sha256":generation,"byteCount":9 * 1024 * 1024]]]
    let bytes = try JSONSerialization.data(withJSONObject:manifest,options:[.sortedKeys])
    try bytes.write(to:external.appendingPathComponent(ExchangeDigest.hash(bytes).description + ".manifest.json"))
    do {
      let db = try await store.libraryDatabase()
      try db.setState("evidence_hash",generation)
      try db.execute("INSERT INTO quarantine(id,reason,manifest) VALUES(?,?,?)",[id,reason,"{}"])
    }
    await store.closeLibrary()
    let alias = root.appendingPathComponent("aliases/library-link")
    try FileManager.default.createDirectory(at:alias.deletingLastPathComponent(),withIntermediateDirectories:true)
    try FileManager.default.createSymbolicLink(at:alias,withDestinationURL:library)
    let aliasOwner = PortraitCandidateStore(directoryURL:alias)
    let backup = try await aliasOwner.createExchangeMetadataBackup()
    await aliasOwner.closeLibrary()
    #expect(backup.objects.isEmpty)
    #expect(!FileManager.default.fileExists(atPath:backup.rootURL.appendingPathComponent("PortraitQuarantine").path))
    await store.closeLibrary()
    let sql = library.appendingPathComponent("library-v1.sqlite"),before = try Data(contentsOf:sql)
    try FileManager.default.removeItem(at:original)
    #expect(throws:(any Error).self) { try PortraitExchangeCatalog.restore(root:library,generationID:backup.generationID) }
    #expect(try Data(contentsOf:sql) == before)
  }

  @Test("A copied alias contends, readers stay available, distinct roots are independent, escaped DB keeps lease")
  func leaseLifetime() async throws {
    let root = try DX04Fixture.root(); defer { try? FileManager.default.removeItem(at: root) }
    let library = root.appendingPathComponent("library"), alias = root.appendingPathComponent("alias")
    let store = PortraitCandidateStore(directoryURL: library)
    var borrowed: PortraitLibraryDatabase? = try await store.libraryDatabase()
    try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: library)
    #expect(throws: (any Error).self) { _ = try PortraitLibraryDatabase(url: alias.appendingPathComponent("library-v1.sqlite")) }
    _ = try PortraitLibraryDatabase(url: library.appendingPathComponent("library-v1.sqlite"), readOnly: true)
    _ = try PortraitLibraryDatabase(url: root.appendingPathComponent("other/library-v1.sqlite"))
    await store.closeLibrary()
    #expect(borrowed != nil)
    var proof = try #require(borrowed).writerLease
    #expect(throws: (any Error).self) { _ = try PortraitLibraryDatabase(url: library.appendingPathComponent("library-v1.sqlite"), writerLease: proof) }
    #expect(throws: (any Error).self) { _ = try PortraitLibraryDatabase(url: library.appendingPathComponent("library-v1.sqlite")) }
    borrowed = nil; proof = nil
    _ = try await store.libraryDatabase()
  }
}

enum DX04Fixture {
  enum Failure: Error { case injected, timeout, process }
  static func root() throws -> URL {
    let result = FileManager.default.temporaryDirectory.appendingPathComponent("dx04-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: result, withIntermediateDirectories: true)
    return result
  }
  static var fixture: URL { URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures/DrawingExchange/v1/source-free.zip") }
  static func admitted(parent: URL) throws -> ValidatedExchangePackage {
    try ExchangeAdmission.validate(DrawingExchangeCarrier.stageZIP(fixture, stagingParent: parent))
  }
  static func changedDrawing(_ original: ValidatedExchangePackage, parent: URL) throws -> ValidatedExchangePackage {
    let bag = parent.appendingPathComponent("changed-" + UUID().uuidString)
    try DrawingExchangeCarrier.preserveDirectory(original.files, to: bag)
    let drawing = try #require(original.files.entries.keys.first { $0.hasSuffix("/drawing.json") })
    let target = bag.appendingPathComponent(drawing)
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: target.path)
    var bytes = try Data(contentsOf: target); bytes.append(10); try bytes.write(to: target)
    let indexURL = bag.appendingPathComponent("data/exchange.json")
    var index = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: indexURL)) as? [String: Any])
    var roots = try #require(index["roots"] as? [[String: Any]])
    roots[0]["digest"] = ExchangeDigest.hash(bytes).description; index["roots"] = roots
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: indexURL.path)
    try JSONSerialization.data(withJSONObject: index, options: [.sortedKeys]).write(to: indexURL)
    let paths = original.files.entries.keys.filter { $0.hasPrefix("data/") }.sorted()
    let manifest = try paths.map { ExchangeDigest.hash(try Data(contentsOf: bag.appendingPathComponent($0))).description + "  " + $0 + "\n" }.joined()
    for (name, data) in [("manifest-sha256.txt", Data(manifest.utf8))] {
      try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: bag.appendingPathComponent(name).path); try data.write(to: bag.appendingPathComponent(name))
    }
    let tags = try ["bagit.txt", "manifest-sha256.txt"].map { ExchangeDigest.hash(try Data(contentsOf: bag.appendingPathComponent($0))).description + "  " + $0 + "\n" }.joined()
    let tag = bag.appendingPathComponent("tagmanifest-sha256.txt")
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: tag.path); try Data(tags.utf8).write(to: tag)
    return try ExchangeAdmission.validate(DrawingExchangeCarrier.stageDirectory(bag, stagingParent: parent))
  }
}
