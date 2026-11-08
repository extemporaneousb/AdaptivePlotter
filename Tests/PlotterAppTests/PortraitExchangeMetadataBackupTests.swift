import Foundation
import Testing
import PortraitCore
@testable import DrawingLibrary

private enum BackupInjectedFailure: Error { case stop }
@Suite("DX04 immutable metadata backup", .serialized)
struct LibraryExchangeMetadataBackupTests {
  private func makeGeneration(_ f: LibraryExchangeStorageFixture, id: UUID = UUID(),
    objects: [LibraryExchangeStorageEntry] = []) throws -> LibraryExchangeBackupGeneration {
    try LibraryExchangeMetadataBackup(storage: f.storage).create(generationID: id, objects: objects,
      onlineBackup: { try Data("test SQL snapshot: titles retention tombstones transaction identities".utf8).write(to: $0) },
      validate: { url in
        let snapshot = try Data(contentsOf: url)
        #expect(snapshot.starts(with: Data("test SQL snapshot".utf8)))
      })
  }

  @Test func wholeLibraryInventoryExceedsCarrierBudgetWithBoundedLines() throws {
    // Metadata only: no 100k-file tree and no media allocation.
    let count = 100_001
    let objects = try (0..<count).map { index -> LibraryExchangeStorageEntry in
      let hex = String(repeating: "0", count: 48) + String(format: "%016llx", UInt64(index))
      let digest = try ExchangeDigest(hex)
      return .init(path: "objects/sha256/" + hex, digest: digest, byteLength: 12345)
    }
    var emitted = 0, total: UInt64 = 0, largest = 0
    let facts = try LibraryExchangeMetadataBackup.encodeInventory(objects) { line in
      emitted += 1; total += UInt64(line.count); largest = max(largest, line.count)
      #expect(line.last == 10)
    }
    #expect(emitted == count)
    #expect(facts.entryCount == UInt64(count))
    #expect(facts.byteLength == total)
    #expect(facts.byteLength > 16 * 1024 * 1024)
    #expect(largest <= LibraryExchangeMetadataBackup.InventoryPolicy.maximumLineBytes)
    let longest = LibraryExchangeStorageEntry(path: "objects/sha256/" + String(repeating: "f", count: 64),
      digest: try ExchangeDigest(String(repeating: "f", count: 64)), byteLength: UInt64(Int64.max))
    var longestBytes = 0
    _ = try LibraryExchangeMetadataBackup.encodeInventory([longest]) { longestBytes = $0.count }
    // Canonical allowed paths and Int64 lengths fit the declared 2m-row scale
    // below 1GiB without relying on the single-carrier 100k/16MiB policy.
    #expect(UInt64(longestBytes) * LibraryExchangeMetadataBackup.InventoryPolicy.maximumEntries < LibraryExchangeMetadataBackup.InventoryPolicy.maximumBytes)
    #expect(throws: (any Error).self) { try LibraryExchangeMetadataBackup.encodeInventory([longest, longest]) { _ in } }
  }

  @Test func validChecksumsDoNotAdmitMalformedStreamedInventory() throws {
    let f = try LibraryExchangeStorageFixture(); defer { f.dispose() }
    let stage = try f.stage(); try f.storage.installObjects(stage)
    let entry = stage.entries[0]
    let object = LibraryExchangeStorageEntry(path: "objects/sha256/" + entry.digest.description, digest: entry.digest, byteLength: entry.byteLength)
    let generation = try makeGeneration(f, objects: [object])
    let inventoryURL = generation.rootURL.appendingPathComponent("inventory.jsonl")
    let good = try Data(contentsOf: inventoryURL)
    let manifestURL = generation.rootURL.appendingPathComponent("manifest.json")
    let originalEnvelope = try JSONSerialization.jsonObject(with: Data(contentsOf: manifestURL)) as! [String: Any]
    for (bytes, count) in [(Data(good.dropLast()), 1), (good + good, 2), (Data(repeating: 97, count: 1025) + Data([10]), 1)] {
      try bytes.write(to: inventoryURL, options: .atomic)
      var outer = originalEnvelope
      var payload = try JSONSerialization.jsonObject(with: Data(base64Encoded: outer["payload"] as! String)!) as! [String: Any]
      payload["inventory"] = ["digest": ExchangeDigest.hash(bytes).description, "byteLength": bytes.count, "entryCount": count]
      let encoded = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
      outer["payload"] = encoded.base64EncodedString(); outer["digest"] = ExchangeDigest.hash(encoded).description
      try JSONSerialization.data(withJSONObject: outer, options: [.sortedKeys]).write(to: manifestURL, options: .atomic)
      #expect(throws: (any Error).self) {
        try LibraryExchangeMetadataBackup(storage: f.storage).prepareRestore(generationID: generation.generationID, validate: { _ in })
      }
    }
  }

  @Test func generationIsExplicitImmutableAndRestoreIsSelfContained() throws {
    let f = try LibraryExchangeStorageFixture(); defer { f.dispose() }
    let stage = try f.stage(); try f.storage.installObjects(stage)
    let objects = Dictionary(grouping: stage.entries, by: \.digest).values.map { entries in
      LibraryExchangeStorageEntry(path: "objects/sha256/" + entries[0].digest.description, digest: entries[0].digest, byteLength: entries[0].byteLength)
    }.sorted { $0.path < $1.path }
    let backup = LibraryExchangeMetadataBackup(storage: f.storage)
    let generation = try makeGeneration(f, objects: objects)
    let newer = try makeGeneration(f)
    #expect(generation.generationID != newer.generationID)
    // Remove originals: restore must consume the selected snapshot's own inventory.
    for object in objects { try FileManager.default.removeItem(at: f.root.appendingPathComponent(object.path)) }
    let plan = try backup.prepareRestore(generationID: generation.generationID, validate: { _ in })
    #expect(plan.objects == objects)
    #expect(plan.rootURL != generation.rootURL)
    #expect(try Data(contentsOf: plan.databaseURL) == Data(contentsOf: generation.databaseURL))
    try backup.installRestoredObjects(plan)
    for entry in objects { try f.storage.verifyObject(digest: entry.digest, byteLength: entry.byteLength) }
    #expect(!FileManager.default.fileExists(atPath: f.root.appendingPathComponent("drawing-library.sqlite").path))
    #expect(throws: (any Error).self) { try makeGeneration(f, id: generation.generationID) }
  }

  @Test func currentCASAssetsAreIncludedWithoutMetadataReconstruction() throws {
    let f = try LibraryExchangeStorageFixture(); defer { f.dispose() }
    let entries = try ["source pixels", "producer receipt", "domain preview"].map { label in
      let bytes = Data(label.utf8), digest = ExchangeDigest.hash(bytes)
      let path = "objects/sha256/" + digest.description
      let target = f.root.appendingPathComponent(path)
      try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
      try bytes.write(to: target)
      return LibraryExchangeStorageEntry(path: path, digest: digest, byteLength: UInt64(bytes.count))
    }
    let generation = try makeGeneration(f, objects: entries.sorted { $0.path < $1.path })
    for entry in entries {
      #expect(try Data(contentsOf: generation.rootURL.appendingPathComponent(entry.path)) == Data(contentsOf: f.root.appendingPathComponent(entry.path)))
    }
    let plan = try LibraryExchangeMetadataBackup(storage: f.storage).prepareRestore(generationID: generation.generationID, validate: { _ in })
    #expect(plan.objects == entries.sorted { $0.path < $1.path })
  }

  @Test func corruptDatabaseManifestAndMissingObjectsRefuseRestore() throws {
    for target in ["database", "manifest", "object", "inventory"] {
      let f = try LibraryExchangeStorageFixture(); defer { f.dispose() }
      let stage = try f.stage(); try f.storage.installObjects(stage)
      let entry = stage.entries[0]
      let object = LibraryExchangeStorageEntry(path: "objects/sha256/" + entry.digest.description, digest: entry.digest, byteLength: entry.byteLength)
      let generation = try makeGeneration(f, objects: [object])
      switch target {
      case "database": try Data("corrupt".utf8).write(to: generation.databaseURL)
      case "manifest": try Data("{\"version\":1,\"version\":1}".utf8).write(to: generation.rootURL.appendingPathComponent("manifest.json"))
      case "inventory": try Data("truncated".utf8).write(to: generation.rootURL.appendingPathComponent("inventory.jsonl"), options: .atomic)
      default: try FileManager.default.removeItem(at: generation.rootURL.appendingPathComponent(object.path))
      }
      #expect(throws: (any Error).self) {
        try LibraryExchangeMetadataBackup(storage: f.storage).prepareRestore(generationID: generation.generationID, validate: { _ in })
      }
      #expect(!FileManager.default.fileExists(atPath: f.root.appendingPathComponent("drawing-library.sqlite").path))
      #expect(FileManager.default.fileExists(atPath: generation.rootURL.path))
    }
  }

  @Test func interruptedSnapshotsRemainInspectableAndUnpublished() throws {
    let f = try LibraryExchangeStorageFixture(); defer { f.dispose() }
    let id = UUID(), backup = LibraryExchangeMetadataBackup(storage: f.storage)
    #expect(throws: BackupInjectedFailure.self) {
      try backup.create(generationID: id, objects: [], onlineBackup: { url in
        try Data("partial database".utf8).write(to: url); throw BackupInjectedFailure.stop
      }, validate: { _ in })
    }
    #expect(throws: (any Error).self) { try backup.prepareRestore(generationID: id, validate: { _ in }) }
    let names = try FileManager.default.contentsOfDirectory(atPath: f.root.appendingPathComponent("metadata-backups").path)
    #expect(names.count == 1)
    #expect(names[0].hasPrefix(".partial-" + id.uuidString.lowercased()))
    #expect(FileManager.default.fileExists(atPath: f.root.appendingPathComponent("metadata-backups/" + names[0] + "/drawing-library.sqlite").path))
  }

  @Test func backupPublicationFaultsHaveExplicitDurabilityMeaning() throws {
    for boundary in [LibraryExchangeStorageFault.Boundary.beforeBackupPublish, .afterBackupPublish] {
      let f = try LibraryExchangeStorageFixture(); defer { f.dispose() }
      let id = UUID()
      let interrupted = try LibraryExchangeStorage(root: f.root, lease: f.lease) { event in
        if event.boundary == boundary { throw BackupInjectedFailure.stop }
      }
      #expect(throws: BackupInjectedFailure.self) {
        try LibraryExchangeMetadataBackup(storage: interrupted).create(generationID: id, objects: [],
          onlineBackup: { try Data("consistent metadata".utf8).write(to: $0) }, validate: { _ in })
      }
      let backup = LibraryExchangeMetadataBackup(storage: f.storage)
      if boundary == .beforeBackupPublish {
        #expect(throws: (any Error).self) { try backup.prepareRestore(generationID: id, validate: { _ in }) }
      } else {
        let plan = try backup.prepareRestore(generationID: id, validate: { _ in })
        #expect(plan.generationID == id)
      }
    }
  }

  @Test func validatorRefusalAndUnsafeInventoriesCannotReplaceActiveMetadata() throws {
    let f = try LibraryExchangeStorageFixture(); defer { f.dispose() }
    let active = f.root.appendingPathComponent("drawing-library.sqlite"), activeBytes = Data("active unchanged".utf8)
    try activeBytes.write(to: active)
    let backup = LibraryExchangeMetadataBackup(storage: f.storage)
    let id = UUID()
    #expect(throws: BackupInjectedFailure.self) {
      try backup.create(generationID: id, objects: [], onlineBackup: { try Data("SQL".utf8).write(to: $0) },
        validate: { _ in throw BackupInjectedFailure.stop })
    }
    let digest = ExchangeDigest.hash(Data())
    for path in ["../drawing-library.sqlite", "drawing-library.sqlite", "photos/" + digest.description, "objects/sha256/wrong", "review-v1/../" + digest.description] {
      #expect(throws: (any Error).self) {
        try makeGeneration(f, objects: [.init(path: path, digest: digest, byteLength: 0)])
      }
    }
    #expect(try Data(contentsOf: active) == activeBytes)
    let generation = try makeGeneration(f)
    #expect(throws: BackupInjectedFailure.self) {
      try backup.prepareRestore(generationID: generation.generationID, validate: { _ in throw BackupInjectedFailure.stop })
    }
    #expect(try Data(contentsOf: active) == activeBytes)
  }

  @Test func backupAssetFaultLeavesOriginalAndPartialWithoutGeneration() throws {
    let f = try LibraryExchangeStorageFixture(); defer { f.dispose() }
    let stage = try f.stage(); try f.storage.installObjects(stage)
    let entry = stage.entries[0]
    let object = LibraryExchangeStorageEntry(path: "objects/sha256/" + entry.digest.description, digest: entry.digest, byteLength: entry.byteLength)
    let id = UUID()
    let interrupted = try LibraryExchangeStorage(root: f.root, lease: f.lease) { event in
      if event.boundary == .afterBlobFileSync { throw BackupInjectedFailure.stop }
    }
    #expect(throws: BackupInjectedFailure.self) {
      try LibraryExchangeMetadataBackup(storage: interrupted).create(generationID: id, objects: [object],
        onlineBackup: { try Data("consistent SQL".utf8).write(to: $0) }, validate: { _ in })
    }
    try f.storage.verifyObject(digest: object.digest, byteLength: object.byteLength)
    #expect(!FileManager.default.fileExists(atPath: f.root.appendingPathComponent("metadata-backups/" + id.uuidString.lowercased()).path))
    #expect(try FileManager.default.contentsOfDirectory(atPath: f.root.appendingPathComponent("metadata-backups").path).count == 1)
  }
}
