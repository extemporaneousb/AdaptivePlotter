import Darwin
import Foundation
import CryptoKit
import PortraitCore
@testable import DrawingLibrary
import Testing

@Suite("Drawing Exchange catalog foundation", .serialized)
struct LibraryExchangeCatalogTests {
  @Test("Exact publication is idempotent, record lookup pins the digest and metadata remains explicit")
  func exactPublication() throws {
    let root = try DX04Fixture.root(); defer { try? FileManager.default.removeItem(at: root) }
    let admitted = try DX04Fixture.admitted(parent: root)
    let db = try DrawingLibraryDatabase(url: root.appendingPathComponent("library/drawing-library.sqlite"))
    let catalog = try LibraryExchangeCatalog(database: db)
    let ref = LibraryExchangeReference.drawing(try #require(admitted.index.known?.roots.first))
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
    let db = try DrawingLibraryDatabase(url: root.appendingPathComponent("library/drawing-library.sqlite"))
    let catalog = try LibraryExchangeCatalog(database: db)
    _ = try catalog.publish(admitted)
    #expect(try db.scalar("SELECT COUNT(*) FROM dx_record") == "0")
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
    let expected = admitted.files.entries.values.map { LibraryExchangeStorageEntry(path:$0.path,digest:$0.digest,byteLength:$0.byteLength) }.sorted{$0.path < $1.path}
    let sql = root.appendingPathComponent("library/drawing-library.sqlite"),transaction: UUID
    do {
      let db = try DrawingLibraryDatabase(url:sql),catalog = try LibraryExchangeCatalog(database:db)
      transaction = try catalog.publish(admitted).transactionID
      #expect(try catalog.storage.pendingTransactions().isEmpty)
      #expect(try catalog.publicationInventory(transactionID:transaction) == expected)
      #expect(try db.scalar("SELECT COUNT(*) FROM dx_tx_file") == String(expected.count))
      #expect(try db.scalar("SELECT COUNT(*) FROM dx_tx_object") == String(Set(expected.map(\.digest)).count))
      #expect(throws:(any Error).self) { try db.execute("DELETE FROM dx_tx_object WHERE transaction_id=?",[transaction.uuidString.lowercased()]) }
    }
    let reopened = try LibraryExchangeCatalog(database:DrawingLibraryDatabase(url:sql))
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
      let db = try DrawingLibraryDatabase(url:root.appendingPathComponent("library/drawing-library.sqlite"))
      let catalog = try LibraryExchangeCatalog(database:db)
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
    let db = try DrawingLibraryDatabase(url:root.appendingPathComponent("library/drawing-library.sqlite"))
    _ = try LibraryExchangeCatalog(database:db).publish(admitted)
    let edge = try db.rows("SELECT source_kind,target_kind,relation FROM dx_link")
    #expect(edge.count == 1 && edge[0][0] == "input" && edge[0][1] == "photo" && edge[0][2] == "photo")
    #expect(try db.scalar("SELECT COUNT(*) FROM dx_record WHERE kind='drawing'") == "0")
  }

  @Test("Divergent exact identity preserves incoming bytes and never replaces the selected record")
  func divergentIdentity() throws {
    let root = try DX04Fixture.root(); defer { try? FileManager.default.removeItem(at: root) }
    let admitted = try DX04Fixture.admitted(parent: root)
    let db = try DrawingLibraryDatabase(url: root.appendingPathComponent("library/drawing-library.sqlite"))
    let catalog = try LibraryExchangeCatalog(database: db)
    let original = try #require(admitted.index.known?.roots.first)
    _ = try catalog.publish(admitted)
    let changed = try DX04Fixture.changedDrawing(admitted, parent: root)
    var conflictURL: URL?
    do { _ = try catalog.publish(changed); Issue.record("Expected preserved conflict") }
    catch LibraryExchangeCatalogError.preservedConflict(let url) { conflictURL = url }
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
    let db = try DrawingLibraryDatabase(url:root.appendingPathComponent("library/drawing-library.sqlite")),catalog = try LibraryExchangeCatalog(database:db)
    _ = try catalog.publish(admitted)
    #expect(throws:LibraryExchangeCatalogError.self) { _ = try catalog.publish(drawing) }
    #expect(try db.scalar("SELECT COUNT(*) FROM dx_record") == "1")
    #expect(try db.scalar("SELECT kind FROM dx_record") == "photo")
    #expect(try FileManager.default.contentsOfDirectory(atPath:root.appendingPathComponent("library/exchange-conflicts").path).count == 1)
  }

  @Test("Uncertain post-COMMIT response retries the original durable transaction")
  func uncertainCommit() throws {
    let root = try DX04Fixture.root(); defer { try? FileManager.default.removeItem(at: root) }
    let admitted = try DX04Fixture.admitted(parent: root)
    let db = try DrawingLibraryDatabase(url: root.appendingPathComponent("library/drawing-library.sqlite"))
    let catalog = try LibraryExchangeCatalog(database: db)
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
    let db = try DrawingLibraryDatabase(url: root.appendingPathComponent("library/drawing-library.sqlite"))
    let catalog = try LibraryExchangeCatalog(database: db)
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
    let db = try DrawingLibraryDatabase(url: root.appendingPathComponent("library/drawing-library.sqlite"))
    let catalog = try LibraryExchangeCatalog(database: db)
    let ref = LibraryExchangeReference.drawing(try #require(admitted.index.known?.roots.first))
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
    let store = DrawingLibrary(directoryURL:root.appendingPathComponent("library"))
    let admitted = try DX04Fixture.admitted(parent:root)
    func verify(store: isolated DrawingLibrary) throws {
      let catalog = try store.commonCatalog(), db = catalog.database
      let ref = LibraryExchangeReference.drawing(try #require(admitted.index.known?.roots.first))
      _ = try store.publishFixture(admitted)
      func updateDelta(_ title: String, owner: isolated DrawingLibrary) throws -> Int {
        let before = Int(try db.scalar("SELECT total_changes()") ?? "0")!
        try owner.updateFixtureMetadata(.init(reference:ref,title:title,retentionReasons:["chosen"],tombstoned:true))
        return Int(try db.scalar("SELECT total_changes()") ?? "0")! - before
      }
      #expect(try updateDelta("Small", owner: store) == 2)
      try store.seedMetadataFixture(ref)
      #expect(try updateDelta("Large", owner: store) == 2)
      let cached = try store.commonCatalog()
      #expect(cached === catalog) // A reconstruction would repeat integrity/recovery scans.
      #expect(try catalog.metadata(ref)?.title == "Large")
      let ownerDB = try store.libraryDatabase()
      let actorGeneration = try ownerDB.generation, expectedGeneration = try db.generation
      #expect(actorGeneration == expectedGeneration)
    }
    try await verify(store: store)
  }

  @Test("Explicit backup generation restores titles, retention and tombstones after catalog loss")
  func metadataRestore() async throws {
    let root = try DX04Fixture.root(); defer { try? FileManager.default.removeItem(at: root) }
    let library = root.appendingPathComponent("library"), store = DrawingLibrary(directoryURL: library)
    let admitted = try DX04Fixture.admitted(parent: root)
    let ref = LibraryExchangeReference.drawing(try #require(admitted.index.known?.roots.first))
    func verify(store: isolated DrawingLibrary) async throws {
      var catalog: LibraryExchangeCatalog? = try store.commonCatalog()
      let transaction = try store.publishFixture(admitted).transactionID
      let expected = LibraryExchangeMetadata(reference: ref, title: "Kept title", retentionReasons: ["chosen", "plot-submitted"], tombstoned: true)
      try store.updateFixtureMetadata(expected)
      let generation = try store.createMetadataBackup()
      _ = try #require(catalog)
      catalog = nil; await store.closeLibrary()
      try FileManager.default.removeItem(at: library.appendingPathComponent("drawing-library.sqlite"))
      #expect(throws: (any Error).self) { _ = try DrawingLibraryDatabase(url: library.appendingPathComponent("drawing-library.sqlite")) }
      try LibraryExchangeCatalog.restore(root: library, generationID: generation.generationID)
      let restoredOwner = DrawingLibrary(directoryURL: library)
      func verifyRestored(store: isolated DrawingLibrary) throws {
        let restored = try store.commonCatalog()
        #expect(try restored.metadata(ref) == expected)
        #expect(try restored.publish(admitted).transactionID == transaction)
        try restored.database.integrityCheck()
      }
      try await verifyRestored(store: restoredOwner)
    }
    try await verify(store: store)
  }







  @Test("Readonly projection connections opened before real atomic restore refuse displaced SQL for index and filtered queries")
  func readonlyRestoreRace() async throws {
    let root = try DX04Fixture.root(); defer { try? FileManager.default.removeItem(at: root) }
    let library = root.appendingPathComponent("library"), store = DrawingLibrary(directoryURL: library)
    let admitted = try DX04Fixture.admitted(parent: root)
    let ref = LibraryExchangeReference.drawing(try #require(admitted.index.known?.roots.first))
    func verify(store: isolated DrawingLibrary) async throws {
      var catalog: LibraryExchangeCatalog? = try store.commonCatalog()
      _ = try store.publishFixture(admitted, metadata: [.init(reference: ref, title: "Selected backup B")])
      let generation = try store.createMetadataBackup()
      try store.updateFixtureMetadata(.init(reference: ref, title: "Displaced connection A"))
      let sql = library.appendingPathComponent("drawing-library.sqlite")
      let displaced = try DrawingLibraryDatabase(url: sql, readOnly: true)
      let revisionA = try displaced.generation.revision
      _ = try #require(catalog)
      catalog = nil; await store.closeLibrary()
      try LibraryExchangeCatalog.restore(root: library, generationID: generation.generationID)
      let selected = try DrawingLibraryDatabase(url: sql, readOnly: true)
      let revisionB = try selected.generation.revision
      #expect(revisionA != revisionB)
      print("DX04_READONLY_RESTORE_GENERATIONS oldRevision=\(revisionA) selectedRevision=\(revisionB)")
      do { print("DX04_DISPLACED_RAW_GENERATION=\(try displaced.generation.revision)") }
      catch { print("DX04_DISPLACED_RAW_GENERATION_ERROR type=\(type(of: error)) error=\(error)") }
      #expect(throws: (any Error).self) { try displaced.assertSelectedFile() }
      #expect(throws: (any Error).self) { _ = try displaced.scalar("SELECT value FROM state WHERE key='revision'") }
      try selected.assertSelectedFile()
      #expect(try selected.generation.revision == revisionB)
    }
    try await verify(store: store)
  }

  @Test("A live cached owner refuses selected SQL loss or replacement before staging new assets")
  func liveSelectedSQLIdentity() async throws {
    for replacement in [false,true] {
      let root = try DX04Fixture.root(); defer { try? FileManager.default.removeItem(at:root) }
      let library = root.appendingPathComponent("library"),store = DrawingLibrary(directoryURL:library)
      let admitted = try DX04Fixture.admitted(parent:root)
      func verify(store: isolated DrawingLibrary) async throws {
        var catalog: LibraryExchangeCatalog? = try store.commonCatalog()
        let sql = library.appendingPathComponent("drawing-library.sqlite")
        try FileManager.default.moveItem(at:sql,to:library.appendingPathComponent("retained-original.sqlite"))
        if replacement { try Data("replacement".utf8).write(to:sql) }
        #expect(throws:(any Error).self) { _ = try #require(catalog).publish(admitted) }
        #expect(throws:(any Error).self) { _ = try store.libraryDatabase() }
        #expect(try FileManager.default.contentsOfDirectory(atPath:library.appendingPathComponent("exchange-staging").path).isEmpty)
        _ = try #require(catalog)
        catalog = nil; await store.closeLibrary()
      }
      try await verify(store: store)
    }
  }

  @Test("Metadata backup refuses missing current-format immutable objects")
  func selectedBackupClosure() async throws {
    let root = try DX04Fixture.root(); defer { try? FileManager.default.removeItem(at:root) }
    let library = root.appendingPathComponent("library"),store = DrawingLibrary(directoryURL:library)
    let admitted = try DX04Fixture.admitted(parent: root)
    _ = try await store.publishFixture(admitted)
    let object = try #require(admitted.files.entries.values.first { $0.path.hasSuffix("/drawing.json") })
    let source = library.appendingPathComponent("objects/sha256/" + object.digest.description)
    let bytes = try Data(contentsOf: source)
    try FileManager.default.removeItem(at: source)
    await #expect(throws: (any Error).self) { _ = try await store.createMetadataBackup() }
    try bytes.write(to: source)
    _ = try await store.createMetadataBackup()
    await store.closeLibrary()
  }



  @Test("A copied alias contends, readers stay available, distinct roots are independent, escaped DB keeps lease")
  func leaseLifetime() async throws {
    let root = try DX04Fixture.root(); defer { try? FileManager.default.removeItem(at: root) }
    let library = root.appendingPathComponent("library"), alias = root.appendingPathComponent("alias")
    let store = DrawingLibrary(directoryURL: library)
    func verify(store: isolated DrawingLibrary) async throws {
      // The raw connection outlives closeLibrary(), while remaining confined
      // to this original owner's executor rather than escaping to the test.
      var borrowed: DrawingLibraryDatabase? = try store.libraryDatabase()
      try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: library)
      #expect(throws: (any Error).self) { _ = try DrawingLibraryDatabase(url: alias.appendingPathComponent("drawing-library.sqlite")) }
      _ = try DrawingLibraryDatabase(url: library.appendingPathComponent("drawing-library.sqlite"), readOnly: true)
      _ = try DrawingLibraryDatabase(url: root.appendingPathComponent("other/drawing-library.sqlite"))
      await store.closeLibrary()
      #expect(borrowed != nil)
      var proof = try #require(borrowed).writerLease
      #expect(throws: (any Error).self) { _ = try DrawingLibraryDatabase(url: library.appendingPathComponent("drawing-library.sqlite"), writerLease: proof) }
      #expect(throws: (any Error).self) { _ = try DrawingLibraryDatabase(url: library.appendingPathComponent("drawing-library.sqlite")) }
      borrowed = nil; proof = nil
      let successor = DrawingLibrary(directoryURL: library)
      func verifySuccessor(store: isolated DrawingLibrary) throws {
        _ = try store.libraryDatabase()
      }
      try await verifySuccessor(store: successor)
    }
    try await verify(store: store)
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

extension DrawingLibrary {
  func seedMetadataFixture(_ ref: LibraryExchangeReference) throws {
    let db = try commonCatalog().database
    try db.transaction {
      for _ in 0..<10_000 {
        let key = ["drawing",UUID().uuidString.lowercased(),UUID().uuidString.lowercased(),ref.digest.description]
        try db.execute("INSERT INTO dx_record(kind,namespace,identity,digest) VALUES(?,?,?,?)", key.map(Optional.some))
        try db.execute("INSERT INTO dx_summary(kind,namespace,identity,digest) VALUES(?,?,?,?)", key.map(Optional.some))
      }
    }
    refreshOwnership()
  }
  func publishFixture(_ package: ValidatedExchangePackage, metadata: [LibraryExchangeMetadata] = []) throws -> LibraryExchangePublicationReceipt {
    let catalog = try commonCatalog()
    defer { refreshOwnership() }
    return try catalog.publish(package, metadata: metadata)
  }
  func updateFixtureMetadata(_ metadata: LibraryExchangeMetadata) throws {
    let catalog = try commonCatalog()
    defer { refreshOwnership() }
    try catalog.updateMetadata(metadata)
  }
}
