import Foundation
import DrawingLibrary
import PortraitCore
import Testing

private enum ResultHeaderFailure: Error { case afterCommit }
private extension DrawingLibrary {
  func resultHeaderFailure(_ enabled: Bool) throws {
    if !enabled { cachedExchangeCatalog?.injectFault = nil; return }
    let catalog = try commonCatalog()
    catalog.injectFault = { if $0 == .afterSQLCommit { throw ResultHeaderFailure.afterCommit } }
  }
  func removeResultProjection(_ kind: String, package: ExchangeDigest) throws {
    guard let db = cachedExchangeCatalog?.database else { throw DrawingLibraryError.invalidIdentity }
    if kind == "header" {
      try db.execute("DELETE FROM dx_result_root WHERE transaction_id IN (SELECT id FROM dx_transaction WHERE package_digest=?)", [package.description])
    }
    let table = kind == "root" ? "dx_result_root" : "dx_result_publication"
    try db.execute("DELETE FROM " + table + " WHERE transaction_id IN (SELECT id FROM dx_transaction WHERE package_digest=?)", [package.description])
  }
}

@Suite("DX06 stored result integrity", .serialized)
struct DrawingLibraryResultIntegrityTests {
  @Test("Catalog inventories must still prove complete carrier manifests", arguments: ["missing-tag", "payload-mismatch", "tag-omission", "extra-payload"])
  func fullStoredCarrierProof(kind: String) throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("dx06-carrier-proof-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let fixture = try DrawingLibraryResultFixture()
    let input = root.appendingPathComponent("input")
    try fixture.write(to: input)
    let staging = root.appendingPathComponent("staging")
    try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
    let staged = try DrawingExchangeCarrier.stageDirectory(input, stagingParent: staging)
    var bytes = try DrawingLibraryResultFixture.bytes(ExchangeAdmission.validate(staged))
    switch kind {
    case "missing-tag": bytes.removeValue(forKey: "tagmanifest-sha256.txt")
    case "payload-mismatch": bytes["data/objects/sha256/" + fixture.media.object.description] = Data("different bytes, internally honest catalog digest".utf8)
    case "tag-omission":
      bytes["tagmanifest-sha256.txt"] = Data((ExchangeDigest.hash(bytes["bagit.txt"]!).description + "  bagit.txt\n").utf8)
    default: bytes["data/unmanifested.json"] = Data("{}".utf8)
    }
    let catalog = root.appendingPathComponent("catalog")
    var inventory: [ExchangeCatalogFile] = []
    for (path, data) in bytes {
      let url = catalog.appendingPathComponent(path)
      try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
      try data.write(to: url)
      inventory.append(.init(path: path, storagePath: path, digest: .hash(data), byteLength: UInt64(data.count)))
    }
    // Every catalog digest accurately describes the modified bytes. Merely
    // hashing those bytes is insufficient to grant whole-carrier admission.
    let files = try VerifiedExchangeFiles(catalogRoot: catalog, inventory: inventory)
    #expect(throws: (any Error).self) { try ExchangeAdmission.validate(files: files) }
  }
  @Test("Uncertain committed recovery refuses missing result projections rather than accepting a false duplicate", arguments: ["root", "header"])
  func committedProjectionProof(kind: String) async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("dx06-header-proof-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let fixture = try DrawingLibraryResultFixture()
    let input = root.appendingPathComponent("input")
    try fixture.write(to: input)
    let directory = root.appendingPathComponent("library")
    let library = DrawingLibrary(directoryURL: directory)
    try await library.open()
    try await library.resultHeaderFailure(true)
    await #expect(throws: ResultHeaderFailure.self) { try await library.mountResult(from: input) }
    let entry = try #require(try await library.results(for: fixture.frozen.reference).entries.first)
    try await library.removeResultProjection(kind, package: entry.reference.packageDigest)
    try await library.resultHeaderFailure(false)
    await library.closeLibrary()
    let reopened = DrawingLibrary(directoryURL: directory)
    await #expect(throws: (any Error).self) { try await reopened.recover() }
    await #expect(throws: (any Error).self) { try await reopened.mountResult(from: input) }
    await reopened.closeLibrary()
  }

}
