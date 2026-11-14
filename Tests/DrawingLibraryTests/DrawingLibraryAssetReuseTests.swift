import Foundation
import PortraitCore
@testable import DrawingLibrary
import Testing

@Suite("Verified Library asset reuse", .serialized)
struct DrawingLibraryAssetReuseTests {
  @Test("First proof hashes existing CAS bytes; warm reuse neither rehashes nor materializes asset Data")
  func streamedProofAndWarmReuse() async throws {
    try await withFixture(count: 1) { fixture, library in
      let asset = fixture.assets[0], initial = await library.assetReuseStatistics()
      #expect(initial.cachedProofCount == 0)
      let firstAssets = try await library.existingVerifiedAssets([asset.descriptor])
      #expect(firstAssets == [asset.digest])
      let first = await library.assetReuseStatistics()
      #expect(first.verificationPasses == initial.verificationPasses + 1)
      #expect(first.hashedBytes == initial.hashedBytes + UInt64(asset.bytes.count))
      #expect(first.cachedProofCount == 1 && first.cacheHits == initial.cacheHits)
      #expect(await library.cachedAssetProofMaterializedBytes() == 0)
      let warmAssets = try await library.existingVerifiedAssets([asset.descriptor])
      #expect(warmAssets == [asset.digest])
      let warm = await library.assetReuseStatistics()
      #expect(warm.verificationPasses == first.verificationPasses && warm.hashedBytes == first.hashedBytes)
      #expect(warm.cacheHits == first.cacheHits + 1 && warm.cachedProofCount == 1)
      #expect(await library.cachedAssetProofMaterializedBytes() == 0)
      let stored = try await library.record(fixture.key)
      #expect(stored?.assets == [asset.digest])
    }
  }

  @Test("Proof cache remains at 128, evicts least-recently-used proofs and closes without retaining authority")
  func boundedProofLifetime() async throws {
    try await withFixture(count: 129) { fixture, library in
      for asset in fixture.assets.prefix(128) {
        #expect(try await library.existingVerifiedAssets([asset.descriptor]) == [asset.digest])
      }
      let full = await library.assetReuseStatistics()
      #expect(full.cachedProofCount == 128 && full.verificationPasses == 128)
      let first = fixture.assets[0], evicted = fixture.assets[1], extra = fixture.assets[128]
      _ = try await library.existingVerifiedAssets([first.descriptor])
      _ = try await library.existingVerifiedAssets([extra.descriptor])
      let overflow = await library.assetReuseStatistics()
      #expect(overflow.cachedProofCount == 128 && overflow.verificationPasses == full.verificationPasses + 1)
      _ = try await library.existingVerifiedAssets([first.descriptor])
      let recent = await library.assetReuseStatistics()
      #expect(recent.cacheHits == overflow.cacheHits + 1 && recent.hashedBytes == overflow.hashedBytes)
      _ = try await library.existingVerifiedAssets([evicted.descriptor])
      let reread = await library.assetReuseStatistics()
      #expect(reread.verificationPasses == recent.verificationPasses + 1)
      #expect(reread.hashedBytes == recent.hashedBytes + UInt64(evicted.bytes.count) && reread.cachedProofCount == 128)
      #expect(await library.cachedAssetProofMaterializedBytes() == 0)
      await library.closeLibrary()
      #expect(await library.assetReuseStatistics().cachedProofCount == 0)
      await #expect(throws: DrawingLibraryError.self) { try await library.existingVerifiedAssets([first.descriptor]) }
      let reopened = DrawingLibrary(directoryURL: fixture.root)
      #expect(await reopened.assetReuseStatistics().cachedProofCount == 0)
      #expect(try await reopened.existingVerifiedAssets([first.descriptor]) == [first.digest])
      #expect(await reopened.assetReuseStatistics().verificationPasses == 1)
      await reopened.closeLibrary()
    }
  }

  @Test("Same-size mutation, wrong inode replacement and missing objects revoke cached proof until exact restoration", arguments: ["in-place", "replacement", "missing"])
  func changedObjectsAreRefused(change: String) async throws {
    try await withFixture(count: 1) { fixture, library in
      let asset = fixture.assets[0], object = fixture.objectURL(asset.digest)
      let held = fixture.root.appendingPathComponent("held-original")
      if change == "in-place" {
        // Commit installs immutable 0400 objects. Establish the proof only after
        // making this disposable fixture writable, so the later fault is bytes.
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: object.path)
      }
      _ = try await library.existingVerifiedAssets([asset.descriptor])
      let proved = await library.assetReuseStatistics(), originalInode = try inode(object)
      var wrong = asset.bytes; wrong[wrong.startIndex] ^= 0x7f
      switch change {
      case "in-place":
        try overwrite(object, with: wrong)
        #expect(try inode(object) == originalInode)
        #expect(try Data(contentsOf: object) == wrong)
      case "replacement":
        try FileManager.default.moveItem(at: object, to: held)
        try wrong.write(to: object)
        #expect(try inode(object) != originalInode)
      default:
        try FileManager.default.moveItem(at: object, to: held)
      }
      await #expect(throws: (any Error).self) { try await library.existingVerifiedAssets([asset.descriptor]) }
      #expect(await library.assetReuseStatistics().cachedProofCount == 0)
      if change == "in-place" { try overwrite(object, with: asset.bytes) }
      else {
        if FileManager.default.fileExists(atPath: object.path) { try FileManager.default.removeItem(at: object) }
        try FileManager.default.moveItem(at: held, to: object)
      }
      #expect(try await library.existingVerifiedAssets([asset.descriptor]) == [asset.digest])
      let restored = await library.assetReuseStatistics()
      #expect(restored.verificationPasses == proved.verificationPasses + 1)
      #expect(restored.hashedBytes == proved.hashedBytes + UInt64(asset.bytes.count) && restored.cachedProofCount == 1)
      #expect(try await library.asset(asset.digest) == asset.bytes)
      #expect(await library.cachedAssetProofMaterializedBytes() == 0)
    }
  }

  @Test("Identical bytes at a replacement inode require a fresh hash before becoming reusable")
  func exactReplacementIsReverified() async throws {
    try await withFixture(count: 1) { fixture, library in
      let asset = fixture.assets[0], object = fixture.objectURL(asset.digest)
      _ = try await library.existingVerifiedAssets([asset.descriptor])
      let before = await library.assetReuseStatistics(), originalInode = try inode(object)
      try FileManager.default.moveItem(at: object, to: fixture.root.appendingPathComponent("previous-inode"))
      try asset.bytes.write(to: object)
      #expect(try inode(object) != originalInode)
      #expect(try await library.existingVerifiedAssets([asset.descriptor]) == [asset.digest])
      let replacement = await library.assetReuseStatistics()
      #expect(replacement.verificationPasses == before.verificationPasses + 1 && replacement.cacheHits == before.cacheHits)
      #expect(replacement.hashedBytes == before.hashedBytes + UInt64(asset.bytes.count))
      _ = try await library.existingVerifiedAssets([asset.descriptor])
      let warm = await library.assetReuseStatistics()
      #expect(warm.cacheHits == replacement.cacheHits + 1 && warm.hashedBytes == replacement.hashedBytes)
    }
  }

  @Test("DB lengths and membership remain authoritative over warm proofs and unindexed physical files")
  func expectedCatalogFactsAreChecked() async throws {
    try await withFixture(count: 1) { fixture, library in
      let asset = fixture.assets[0]
      _ = try await library.existingVerifiedAssets([asset.descriptor])
      let wrongLength = try changingLength(asset.descriptor, to: UInt64(asset.bytes.count + 1))
      await #expect(throws: DrawingLibraryError.self) { try await library.existingVerifiedAssets([wrongLength]) }
      let wrongInventory = ExchangeCatalogFile(path: "history/input.bin", storagePath: "ignored", digest: asset.digest,
        byteLength: UInt64(asset.bytes.count + 1))
      await #expect(throws: DrawingLibraryError.self) { try await library.assetFiles([wrongInventory], limits: .init()) }
      let otherBytes = Data("unindexed immutable bytes".utf8)
      let unindexed = try ExchangeAsset(bytes: otherBytes, mediaType: "application/octet-stream", encoding: "example.asset-reuse/1")
      try otherBytes.write(to: fixture.objectURL(unindexed.object))
      let before = await library.assetReuseStatistics()
      #expect(try await library.existingVerifiedAssets([.init(asset: unindexed)]).isEmpty)
      let absent = ExchangeCatalogFile(path: "history/unindexed.bin", storagePath: "ignored", digest: unindexed.object,
        byteLength: unindexed.byteLength)
      await #expect(throws: DrawingLibraryError.self) { try await library.assetFiles([absent], limits: .init()) }
      #expect(await library.assetReuseStatistics().hashedBytes == before.hashedBytes)
      #expect(try await library.existingVerifiedAssets([asset.descriptor]) == [asset.digest])
    }
  }

  @Test("Virtual paths resolve only canonical CAS objects, never the supplied alternate storage path")
  func canonicalStorageMapping() async throws {
    try await withFixture(count: 1) { fixture, library in
      let asset = fixture.assets[0], logical = "history/program.bin"
      let decoy = fixture.root.appendingPathComponent("caller-decoy.bin")
      try Data(repeating: 0xff, count: asset.bytes.count).write(to: decoy)
      let alternate = ExchangeCatalogFile(path: logical, storagePath: "caller-decoy.bin", digest: asset.digest,
        byteLength: UInt64(asset.bytes.count))
      let files = try await library.assetFiles([alternate], limits: .init())
      #expect(Set(files.entries.keys) == [logical])
      #expect(try files.record(at: logical) == asset.bytes)
      let unsafe = ExchangeCatalogFile(path: logical, storagePath: "../../caller-selected-file", digest: asset.digest,
        byteLength: UInt64(asset.bytes.count))
      let mapped = try await library.assetFiles([unsafe], limits: .init())
      #expect(try mapped.record(at: logical) == asset.bytes)
      let object = fixture.objectURL(asset.digest), held = fixture.root.appendingPathComponent("canonical-held")
      try FileManager.default.moveItem(at: object, to: held)
      // Even an exact alternate copy cannot substitute for the canonical object.
      try asset.bytes.write(to: decoy)
      let missing = try await library.assetFiles([alternate], limits: .init())
      #expect(throws: (any Error).self) { try missing.record(at: logical) }
      try FileManager.default.moveItem(at: held, to: object)
      let restored = try await library.assetFiles([alternate], limits: .init())
      #expect(try restored.record(at: logical) == asset.bytes)
    }
  }

  @Test("Inventory and explicit selected-read bounds reject oversized work before materialization")
  func boundedSelectedReads() async throws {
    try await withFixture(count: 2) { fixture, library in
      let inventory = fixture.assets.enumerated().map { index, asset in
        ExchangeCatalogFile(path: "history/\(index).bin", storagePath: "ignored", digest: asset.digest,
          byteLength: UInt64(asset.bytes.count))
      }
      var limits = ExchangeCarrierLimits(); limits.maximumEntries = 1
      let entryCountLimits = limits
      await #expect(throws: (any Error).self) { try await library.assetFiles(inventory, limits: entryCountLimits) }
      limits = .init(); limits.maximumEntryBytes = UInt64(fixture.assets[0].bytes.count - 1)
      let entryByteLimits = limits
      await #expect(throws: DrawingExchangeError.self) { try await library.assetFiles([inventory[0]], limits: entryByteLimits) }
      limits = .init(); limits.maximumExpandedBytes = inventory.reduce(0) { $0 + $1.byteLength } - 1
      let expandedLimits = limits
      await #expect(throws: DrawingExchangeError.self) { try await library.assetFiles(inventory, limits: expandedLimits) }
      let files = try await library.assetFiles([inventory[0]], limits: .init())
      #expect(files.statistics.hashedBytes == 0 && files.statistics.materializedBytesRead == 0)
      #expect(throws: DrawingExchangeError.self) {
        try files.record(at: inventory[0].path, maximumBytes: fixture.assets[0].bytes.count - 1)
      }
      #expect(files.statistics.hashedBytes == 0 && files.statistics.materializedBytesRead == 0)
      #expect(try files.record(at: inventory[0].path, maximumBytes: fixture.assets[0].bytes.count) == fixture.assets[0].bytes)
      #expect(files.statistics.hashedBytes == UInt64(fixture.assets[0].bytes.count))
      #expect(files.statistics.materializedBytesRead == UInt64(fixture.assets[0].bytes.count))
      let tooMany = Array(repeating: fixture.assets[0].descriptor, count: 129)
      await #expect(throws: DrawingExchangeError.self) { try await library.existingVerifiedAssets(tooMany) }
    }
  }

  private struct Asset: Sendable {
    let bytes: Data
    let descriptor: ExchangeAssetDescriptor
    var digest: ExchangeDigest { descriptor.asset.object }
  }
  private struct Fixture: Sendable {
    let root: URL
    let assets: [Asset]
    let key: DrawingLibraryRecordKey
    func objectURL(_ digest: ExchangeDigest) -> URL { root.appendingPathComponent("objects/sha256/" + digest.description) }
  }
  private func withFixture(count: Int, _ body: (Fixture, DrawingLibrary) async throws -> Void) async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("asset-reuse-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let assets = try (0..<count).map { index -> Asset in
      let bytes = Data("verified tiny CAS asset \(index)".utf8)
      return .init(bytes: bytes, descriptor: .init(asset: try ExchangeAsset(bytes: bytes,
        mediaType: "application/octet-stream", encoding: "example.asset-reuse/1")))
    }
    let row = DrawingLibraryRecord(kind: "example.asset-reuse/1", id: UUID(), payload: Data("{}".utf8), assets: assets.map(\.digest))
    let writer = DrawingLibrary(directoryURL: root)
    do {
      try await writer.commitRecords([row], assets: assets.map { .init(descriptor: $0.descriptor, bytes: $0.bytes) })
      await writer.closeLibrary()
    } catch { await writer.closeLibrary(); throw error }
    let library = DrawingLibrary(directoryURL: root), fixture = Fixture(root: root, assets: assets, key: row.key)
    do { try await body(fixture, library); await library.closeLibrary() }
    catch { await library.closeLibrary(); throw error }
  }
  private func inode(_ url: URL) throws -> UInt64 {
    let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
    return try #require(attributes[.systemFileNumber] as? NSNumber).uint64Value
  }
  private func overwrite(_ url: URL, with bytes: Data) throws {
    let handle = try FileHandle(forWritingTo: url)
    defer { try? handle.close() }
    try handle.write(contentsOf: bytes); try handle.synchronize()
  }
  private func changingLength(_ descriptor: ExchangeAssetDescriptor, to length: UInt64) throws -> ExchangeAssetDescriptor {
    var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(descriptor)) as? [String: Any])
    json["byteLength"] = length
    return try JSONDecoder().decode(ExchangeAssetDescriptor.self, from: JSONSerialization.data(withJSONObject: json))
  }
}

private extension DrawingLibrary {
  func cachedAssetProofMaterializedBytes() -> UInt64 {
    existingAssetProofs.values.reduce(0) { $0 + $1.statistics.materializedBytesRead }
  }
}
