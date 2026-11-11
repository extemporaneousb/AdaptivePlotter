import Foundation
import Darwin
import Testing
import PortraitCore
@testable import DrawingLibrary

struct LibraryExchangeStorageFixture {
  let bag: DrawingExchangeCarrierTestBag
  let root: URL
  let lease: DrawingLibraryWriterLease
  let storage: LibraryExchangeStorage
  init(fault: @escaping @Sendable (LibraryExchangeStorageFault) throws -> Void = { _ in }) throws {
    bag = try DrawingExchangeCarrierTestBag(files: ["data/exchange.json": Data("{\"profile\":\"unknown/91\"}".utf8),
      "data/unknown.bin": Data(repeating: 73, count: 150_000), "data/duplicate.bin": Data(repeating: 73, count: 150_000)])
    root = bag.root.appendingPathComponent("library")
    lease = try DrawingLibraryWriterLease(root: root)
    storage = try LibraryExchangeStorage(root: root, lease: lease, fault: fault)
  }
  func stage() throws -> LibraryExchangeStaging {
    let incoming = try DrawingExchangeCarrier.stageDirectory(bag.source, stagingParent: bag.root)
    return try storage.stage(files: incoming.files, transactionID: UUID(), intent: Data("catalog-owned opaque intent".utf8))
  }
  func stageURL(_ id: UUID) -> URL { root.appendingPathComponent("exchange-staging/" + id.uuidString.lowercased()) }
  func dispose() { bag.dispose() }
}
private enum StorageInjectedFailure: Error { case stop }

@Suite("DX04 immutable exchange storage", .serialized)
struct LibraryExchangeStorageTests {
  @Test func actualPublicationEncodingFitsDeclaredLibraryPolicy() throws {
    let digest = ExchangeDigest.hash(Data("budget proof".utf8))
    let records: [LibraryExchangeReference] = (0..<10_000).map { _ in
      .drawing(.init(issuer: UUID(), revision: UUID(), digest: digest))
    }
    let links = (0..<30_000).map { index in
      LibraryExchangeLink(source: records[index % records.count], target: records[(index + 1) % records.count], relation: "supersedes")
    }
    let metadata = records.map { LibraryExchangeMetadata(reference: $0, title: String(repeating: "t", count: 64),
      retentionReasons: [String(repeating: "r", count: 32), String(repeating: "s", count: 32)], tombstoned: false) }
    let id = UUID()
    let publication = LibraryExchangePublication(version: 1, transactionID: id, indexDigest: digest,
      packageDigest: digest, records: records, links: links, metadata: metadata, attachments: [], domainCommit: nil, resultHeader: nil)
    let intent = try JSONEncoder().encode(publication)
    #expect(intent.count > 1024 * 1024)
    #expect(intent.count <= LibraryExchangeStorage.maximumPublicationIntentBytes)
    let entries = (0..<20_000).map { _ in
      LibraryExchangeStorageEntry(path: "data/drawings/" + UUID().uuidString.lowercased() + "/" + UUID().uuidString.lowercased() + "/" + digest.description + ".json", digest: digest, byteLength: 1_000_000)
    }
    struct Journal: Encodable { let version: Int; let state: String; let stage: LibraryExchangeStaging }
    let journal = Journal(version: 1, state: "prepared", stage: .init(transactionID: id, intent: intent, entries: entries))
    let journalEncoder = JSONEncoder(); journalEncoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    let payload = try journalEncoder.encode(journal)
    // Exact outer base64 length plus the small fixed envelope fields; no second
    // giant encoded Data allocation is necessary to prove the envelope budget.
    struct Envelope: Encodable { let version: Int; let digest: ExchangeDigest; let payload: Data }
    let emptyEnvelopeBytes = try journalEncoder.encode(Envelope(version: 1, digest: digest, payload: Data())).count
    let envelopeBytes = emptyEnvelopeBytes + 4 * ((payload.count + 2) / 3)
    #expect(envelopeBytes <= LibraryExchangeStorage.maximumJournalBytes)
    #expect(LibraryExchangeStorage.maximumMetadataBytes == 16 * 1024 * 1024)
  }

  @Test func oversizedValidOpaqueIntentIsAResourceRefusalBeforePublication() throws {
    let f = try LibraryExchangeStorageFixture(); defer { f.dispose() }
    let incoming = try DrawingExchangeCarrier.stageDirectory(f.bag.source, stagingParent: f.bag.root)
    #expect(throws: LibraryExchangeStorageError.resourceLimit("publication intent exceeds 32MiB")) {
      try f.storage.stage(files: incoming.files, transactionID: UUID(), intent: Data(count: LibraryExchangeStorage.maximumPublicationIntentBytes + 1))
    }
    #expect(try f.storage.pendingTransactions().isEmpty)
    #expect(FileManager.default.fileExists(atPath: incoming.stagingURL.appendingPathComponent("data/unknown.bin").path))
  }

  @Test func exactBytesDedupRestartInventoryAndScopedCleanup() throws {
    let f = try LibraryExchangeStorageFixture(); defer { f.dispose() }
    let stage = try f.stage()
    let unrelated = try f.stage()
    try f.storage.installObjects(stage)
    let reopened = try LibraryExchangeStorage(root: f.root, lease: f.lease)
    #expect(Set(try reopened.pendingTransactions().map(\.transactionID)) == [stage.transactionID, unrelated.transactionID])
    #expect(try reopened.pendingTransactions().first(where: { $0.transactionID == stage.transactionID }) == stage)
    let objects = try FileManager.default.contentsOfDirectory(atPath: f.root.appendingPathComponent("objects/sha256").path)
    #expect(objects.count == Set(stage.entries.map(\.digest)).count)
    for entry in stage.entries {
      try reopened.verifyObject(digest: entry.digest, byteLength: entry.byteLength)
      #expect(try Data(contentsOf: reopened.objectURL(digest: entry.digest)) == Data(contentsOf: f.bag.source.appendingPathComponent(entry.path)))
    }
    try reopened.finish(transactionID: stage.transactionID)
    #expect(try reopened.pendingTransactions() == [unrelated])
    #expect(!FileManager.default.fileExists(atPath: f.stageURL(stage.transactionID).path))
    #expect(try FileManager.default.contentsOfDirectory(atPath: f.root.appendingPathComponent("objects/sha256").path).count == objects.count)
  }

  @Test func everyOwnedAssetBoundaryLeavesRecoverableIntentAndIncoming() throws {
    let boundaries: [LibraryExchangeStorageFault.Boundary] = [.beforeBlobCopy, .afterBlobCopy,
      .beforeBlobFileSync, .afterBlobFileSync, .beforeBlobInstall, .afterBlobInstall,
      .beforeBlobDirectorySync, .afterBlobDirectorySync, .beforeJournalTransition, .afterJournalTransition]
    for boundary in boundaries {
      let f = try LibraryExchangeStorageFixture(); defer { f.dispose() }
      let stage = try f.stage()
      let interrupted = try LibraryExchangeStorage(root: f.root, lease: f.lease) { event in
        if event.boundary == boundary { throw StorageInjectedFailure.stop }
      }
      #expect(throws: StorageInjectedFailure.self) { try interrupted.installObjects(stage) }
      #expect(FileManager.default.fileExists(atPath: f.bag.source.appendingPathComponent("data/unknown.bin").path))
      #expect(try f.storage.pendingTransactions() == [stage])
      try f.storage.installObjects(stage)
      for entry in stage.entries { try f.storage.verifyObject(digest: entry.digest, byteLength: entry.byteLength) }
    }
  }

  @Test func journalCreationFailuresPreserveUncertainStaging() throws {
    for boundary in [LibraryExchangeStorageFault.Boundary.beforeBagCopy, .duringBagCopy, .afterBagCopy, .beforeJournalCreation, .afterJournalCreation, .beforeStagingPublication] {
      let f = try LibraryExchangeStorageFixture { event in if event.boundary == boundary { throw StorageInjectedFailure.stop } }
      defer { f.dispose() }
      #expect(throws: StorageInjectedFailure.self) { try f.stage() }
      let children = try FileManager.default.contentsOfDirectory(atPath: f.root.appendingPathComponent("exchange-staging").path)
      #expect(children.count == 1)
      #expect(FileManager.default.fileExists(atPath: f.bag.source.appendingPathComponent("data/unknown.bin").path))
      #expect(try f.storage.pendingTransactions().isEmpty)
      #expect(children[0].hasPrefix(".preparing-"))
    }
  }

  @Test func conflictsAndCleanupFaultsAreScoped() throws {
    let f = try LibraryExchangeStorageFixture(); defer { f.dispose() }
    let first = try f.stage(), second = try f.stage()
    let conflict = try f.storage.preserveConflict(transactionID: first.transactionID)
    #expect(FileManager.default.fileExists(atPath: conflict.appendingPathComponent("bag/data/unknown.bin").path))
    #expect(try f.storage.pendingTransactions() == [second])
    for boundary in [LibraryExchangeStorageFault.Boundary.beforeCleanup, .duringCleanup, .afterCleanup] {
      let stage = try f.stage()
      let interrupted = try LibraryExchangeStorage(root: f.root, lease: f.lease) { event in if event.boundary == boundary { throw StorageInjectedFailure.stop } }
      #expect(throws: StorageInjectedFailure.self) { try interrupted.collectStaging(transactionID: stage.transactionID) }
      #expect(FileManager.default.fileExists(atPath: f.stageURL(stage.transactionID).path) == (boundary == .beforeCleanup))
    }
    #expect(try f.storage.pendingTransactions().contains(where: { $0.transactionID == second.transactionID }))
    #expect(FileManager.default.fileExists(atPath: f.stageURL(second.transactionID).path))
    #expect(FileManager.default.fileExists(atPath: conflict.path))
  }

  @Test func corruptMissingLinkedAndWrongLengthObjectsRefused() throws {
    let f = try LibraryExchangeStorageFixture(); defer { f.dispose() }
    let stage = try f.stage(); try f.storage.installObjects(stage)
    let entry = stage.entries.first(where: { $0.path == "data/unknown.bin" })!
    let object = f.storage.objectURL(digest: entry.digest)
    #expect(throws: (any Error).self) { try f.storage.verifyObject(digest: entry.digest, byteLength: entry.byteLength + 1) }
    let bytes = try Data(contentsOf: object)
    try FileManager.default.removeItem(at: object)
    #expect(throws: (any Error).self) { try f.storage.verifyObject(digest: entry.digest, byteLength: entry.byteLength) }
    try Data(repeating: 74, count: bytes.count).write(to: object)
    #expect(throws: (any Error).self) { try f.storage.installObjects(stage) }
    try FileManager.default.removeItem(at: object)
    try FileManager.default.createSymbolicLink(at: object, withDestinationURL: f.bag.source.appendingPathComponent(entry.path))
    #expect(throws: (any Error).self) { try f.storage.installObjects(stage) }
    try FileManager.default.removeItem(at: object)
    try bytes.write(to: object)
    let alias = f.root.appendingPathComponent("hardlink")
    #expect(link(object.path, alias.path) == 0)
    #expect(throws: (any Error).self) { try f.storage.verifyObject(digest: entry.digest, byteLength: entry.byteLength) }
  }

  @Test func forgedStageInventoryAndJournalCorruptionNeverDeleteBytes() throws {
    let f = try LibraryExchangeStorageFixture(); defer { f.dispose() }
    let stage = try f.stage()
    let forged = LibraryExchangeStaging(transactionID: stage.transactionID, intent: Data(), entries: stage.entries)
    #expect(throws: (any Error).self) { try f.storage.installObjects(forged) }
    let journal = f.stageURL(stage.transactionID).appendingPathComponent("journal.json")
    let original = try Data(contentsOf: journal)
    var wrongVersion = try JSONSerialization.jsonObject(with: original) as! [String: Any]
    wrongVersion["version"] = 2
    var wrongHash = try JSONSerialization.jsonObject(with: original) as! [String: Any]
    wrongHash["digest"] = String(repeating: "0", count: 64)
    for bytes in [Data("{\"version\":1,\"version\":1}".utf8), Data("{}".utf8), Data(original.dropLast()),
      try JSONSerialization.data(withJSONObject: wrongVersion), try JSONSerialization.data(withJSONObject: wrongHash)] {
      try bytes.write(to: journal)
      #expect(throws: (any Error).self) { try f.storage.pendingTransactions() }
      #expect(throws: (any Error).self) { try f.storage.collectStaging(transactionID: stage.transactionID) }
      #expect(FileManager.default.fileExists(atPath: f.stageURL(stage.transactionID).appendingPathComponent("bag/data/unknown.bin").path))
    }
  }

  @Test func publicationBoundaryLeavesCompleteRestartableStage() throws {
    let f = try LibraryExchangeStorageFixture { event in
      if event.boundary == .afterStagingPublication { throw StorageInjectedFailure.stop }
    }
    defer { f.dispose() }
    #expect(throws: StorageInjectedFailure.self) { try f.stage() }
    let pending = try f.storage.pendingTransactions()
    #expect(pending.count == 1)
    let reopened = try LibraryExchangeStorage(root: f.root, lease: f.lease)
    try reopened.installObjects(pending[0])
    try reopened.collectStaging(transactionID: pending[0].transactionID)
    #expect(try reopened.pendingTransactions().isEmpty)
  }

  @Test func unsafeAndCaseCollidingInventoriesRejected() throws {
    let digest = ExchangeDigest.hash(Data())
    for paths in [["../escape"], ["/absolute"], ["a\\b"], ["a", "A"], ["Dir/a", "dir/b"], ["a", "a/b"]] {
      #expect(throws: (any Error).self) {
        try LibraryExchangeStorage.validateInventory(paths.map { .init(path: $0, digest: digest, byteLength: 0) })
      }
    }
  }

  @Test func exactPrivateBagRejectsAddedOrLinkedEntries() throws {
    let f = try LibraryExchangeStorageFixture(); defer { f.dispose() }
    let stage = try f.stage()
    let bag = f.stageURL(stage.transactionID).appendingPathComponent("bag")
    let added = bag.appendingPathComponent("extra")
    try Data("not inventoried".utf8).write(to: added)
    #expect(throws: (any Error).self) { try f.storage.installObjects(stage) }
    try FileManager.default.removeItem(at: added)
    let original = bag.appendingPathComponent("data/unknown.bin")
    try FileManager.default.removeItem(at: original)
    try FileManager.default.createSymbolicLink(at: original, withDestinationURL: f.bag.source.appendingPathComponent("data/unknown.bin"))
    #expect(throws: (any Error).self) { try f.storage.installObjects(stage) }
    // The SQL owner may collect this unpublished stage; private cleanup refuses following the link.
    #expect(throws: (any Error).self) { try f.storage.collectStaging(transactionID: stage.transactionID) }
    #expect(try f.storage.pendingTransactions().isEmpty)
  }

  @Test func rootAliasesAndPromotionRetainDescriptorOwnership() throws {
    let f = try LibraryExchangeStorageFixture(); defer { f.dispose() }
    let alias = f.bag.root.appendingPathComponent("alias")
    try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: f.root)
    let throughAlias = try LibraryExchangeStorage(root: alias, lease: f.lease)
    let stage = try f.stage()
    let promoted = f.bag.root.appendingPathComponent("promoted")
    try FileManager.default.moveItem(at: f.root, to: promoted)
    #expect(!FileManager.default.fileExists(atPath: f.root.path))
    var promotedIdentity = stat()
    #expect(fstatat(AT_FDCWD, promoted.path, &promotedIdentity, 0) == 0)
    try throughAlias.installObjects(stage)
    for entry in stage.entries {
      let object = throughAlias.objectURL(digest: entry.digest)
      #expect(object.lastPathComponent == entry.digest.description)
      #expect(object.deletingLastPathComponent().lastPathComponent == "sha256")
      #expect(object.deletingLastPathComponent().deletingLastPathComponent().lastPathComponent == "objects")
      let returnedRoot = object.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
      var returnedIdentity = stat()
      #expect(fstatat(AT_FDCWD, returnedRoot.path, &returnedIdentity, 0) == 0)
      #expect(returnedIdentity.st_dev == promotedIdentity.st_dev)
      #expect(returnedIdentity.st_ino == promotedIdentity.st_ino)
      try throughAlias.verifyObject(digest: entry.digest, byteLength: entry.byteLength)
    }
    try throughAlias.finish(transactionID: stage.transactionID)
  }

  @Test func boundedObjectReadsUseVerifiedBytesAndRejectInvalidBudgets() throws {
    let f = try LibraryExchangeStorageFixture(); defer { f.dispose() }
    let stage = try f.stage(); try f.storage.installObjects(stage)
    let entry = stage.entries.first(where: { $0.path == "data/exchange.json" })!
    let read = try f.storage.readObject(digest: entry.digest, byteLength: entry.byteLength, maximumBytes: 1024)
    #expect(read == (try Data(contentsOf: f.bag.source.appendingPathComponent(entry.path))))
    for limit in [-1, 0, 1] {
      #expect(throws: (any Error).self) { try f.storage.readObject(digest: entry.digest, byteLength: entry.byteLength, maximumBytes: limit) }
    }
  }

  @Test func metadataMarkerRejectsLinksAndNeverTreatsCorruptionAsAbsence() throws {
    let f = try LibraryExchangeStorageFixture(); defer { f.dispose() }
    #expect(try f.storage.readMetadata() == nil)
    let bytes = Data("{\"version\":1}".utf8)
    try f.storage.durableMetadataWrite(bytes)
    #expect(try f.storage.readMetadata() == bytes)
    let marker = f.root.appendingPathComponent("drawing-authority.json")
    try Data("corrupt".utf8).write(to: marker)
    #expect(throws: (any Error).self) { try f.storage.durableMetadataWrite(bytes) }
    try FileManager.default.removeItem(at: marker)
    try FileManager.default.createSymbolicLink(atPath: marker.path, withDestinationPath: "missing")
    #expect(throws: (any Error).self) { try f.storage.readMetadata() }
    #expect(throws: (any Error).self) { try f.storage.durableMetadataWrite(bytes) }
  }
}
