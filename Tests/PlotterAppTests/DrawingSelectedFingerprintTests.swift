import Foundation
import Drawing
import Testing

@Suite("Selected exchange asset fingerprint boundaries")
struct DrawingSelectedFingerprintTests {
  @Test("Per-asset verification stays narrow while final read-set validation detects an earlier source mutation")
  func selectedReadSetSweep() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("selected-fingerprints-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let a = Data("first asset".utf8), b = Data("second asset".utf8)
    try a.write(to: root.appendingPathComponent("a")); try b.write(to: root.appendingPathComponent("b"))
    let da = ExchangeDigest.hash(a), db = ExchangeDigest.hash(b)
    let files = try VerifiedExchangeFiles(catalogRoot: root, inventory: [
      .init(path: "data/objects/sha256/" + da.description, storagePath: "a", digest: da, byteLength: UInt64(a.count)),
      .init(path: "data/objects/sha256/" + db.description, storagePath: "b", digest: db, byteLength: UInt64(b.count)),
    ])
    try files.verify(da); try files.verify(db)
    try Data(repeating: 0x78, count: a.count).write(to: root.appendingPathComponent("a"), options: .atomic)
    try files.verify(db)
    #expect(throws: (any Error).self) { try files.verify(da) }
    #expect(throws: (any Error).self) { try files.revalidateSelected() }
  }
}
