import Foundation
import Testing
import PortraitCore

@Suite("DX05 selected catalog closure", .serialized)
struct DrawingLibrarySelectedClosureTests {
  private struct Fixture {
    let root: URL
    let reference: DrawingRef
    let indexJSON: Data
    let inventory: [ExchangeCatalogFile]
    let programStorageURL: URL
    func files(indexJSON: Data? = nil, extra: [ExchangeCatalogFile] = []) throws -> VerifiedExchangeFiles {
      var selectedInventory = inventory
      if let indexJSON {
        let digest = ExchangeDigest.hash(indexJSON)
        let storagePath = "objects/sha256/" + digest.description
        try indexJSON.write(to: root.appendingPathComponent(storagePath))
        selectedInventory.removeAll { $0.path == "data/exchange.json" }
        selectedInventory.append(.init(path: "data/exchange.json", storagePath: storagePath,
          digest: digest, byteLength: UInt64(indexJSON.count)))
      }
      return try VerifiedExchangeFiles(catalogRoot: root, inventory: selectedInventory + extra)
    }
  }

  private func withFixture(_ body: (Fixture) throws -> Void) throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("dx05-selected-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let zip = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
      .appendingPathComponent("Fixtures/DrawingExchange/v1/source-free.zip")
    let staged = try DrawingExchangeCarrier.stageZIP(zip, stagingParent: root)
    let index = try ExchangeIndex(originalJSON: staged.indexJSON)
    let reference = try #require(index.roots.first)
    let drawingPath = "data/drawings/\(reference.issuer.uuidString.lowercased())/\(reference.revision.uuidString.lowercased())/drawing.json"
    let drawingJSON = try #require(JSONSerialization.jsonObject(with: staged.files.record(at: drawingPath)) as? [String: Any])
    let representation = try #require(drawingJSON["representation"] as? [String: Any])
    let programHash = try #require(representation["object"] as? String)
    let cas = root.appendingPathComponent("catalog")
    try FileManager.default.createDirectory(at: cas.appendingPathComponent("objects/sha256"), withIntermediateDirectories: true)
    var inventory: [ExchangeCatalogFile] = []
    for entry in staged.files.entries.values.sorted(by: { $0.path < $1.path }) {
      let storagePath = "objects/sha256/" + entry.digest.description
      try staged.files.record(at: entry.path).write(to: cas.appendingPathComponent(storagePath))
      inventory.append(.init(path: entry.path, storagePath: storagePath, digest: entry.digest, byteLength: entry.byteLength))
    }
    try body(.init(root: cas, reference: reference, indexJSON: staged.indexJSON, inventory: inventory,
      programStorageURL: cas.appendingPathComponent("objects/sha256/" + programHash)))
  }

  @Test("Missing or corrupt unrelated CAS objects are not opened for a selected root")
  func unrelatedAssetsRemainUnread() throws {
    try withFixture { fixture in
      let unrelated = Data("unrelated artifact".utf8)
      let digest = ExchangeDigest.hash(unrelated)
      let path = "data/objects/sha256/" + digest.description
      let storagePath = "objects/sha256/" + digest.description
      var index = try #require(JSONSerialization.jsonObject(with: fixture.indexJSON) as? [String: Any])
      var assets = try #require(index["assets"] as? [[String: Any]])
      assets.append(["object": digest.description, "byteLength": unrelated.count,
        "mediaType": "application/octet-stream", "encoding": "example.unrelated/1"])
      index["assets"] = assets
      let indexJSON = try JSONSerialization.data(withJSONObject: index, options: [.sortedKeys])
      let extra = ExchangeCatalogFile(path: path, storagePath: storagePath, digest: digest, byteLength: UInt64(unrelated.count))
      for corrupt in [false, true] {
        if corrupt { try Data(repeating: 0, count: unrelated.count).write(to: fixture.root.appendingPathComponent(storagePath)) }
        let files = try fixture.files(indexJSON: indexJSON, extra: [extra])
        let selected = try ExchangeAdmission.selectDrawing(originalIndexJSON: indexJSON, selected: fixture.reference, files: files)
        guard case .materialized(let frozen) = selected.admission else { Issue.record("Selected source-free drawing was not materialized"); return }
        #expect(frozen.reference == fixture.reference)
        #expect(selected.statistics.materializationReadPassesByPath[path] == nil)
        #expect(selected.statistics.imageDecodeCount == 0)
        #expect(throws: (any Error).self) { try files.record(digest) }
      }
    }
  }

  @Test("Selected CAS bytes are checked initially and after materialization")
  func selectedTamperingIsRefused() throws {
    try withFixture { fixture in
      let files = try fixture.files()
      let selected = try ExchangeAdmission.selectDrawing(originalIndexJSON: fixture.indexJSON, selected: fixture.reference, files: files)
      guard case .materialized = selected.admission else { Issue.record("Expected valid selected drawing"); return }
      let original = try Data(contentsOf: fixture.programStorageURL)
      var changed = original
      changed[changed.startIndex] ^= 1
      try changed.write(to: fixture.programStorageURL)
      #expect(throws: (any Error).self) {
        try ExchangeAdmission.selectDrawing(originalIndexJSON: fixture.indexJSON, selected: fixture.reference, files: files)
      }
      #expect(throws: (any Error).self) {
        try ExchangeAdmission.selectDrawing(originalIndexJSON: fixture.indexJSON, selected: fixture.reference, files: fixture.files())
      }
      try original.write(to: fixture.programStorageURL)
      let repaired = try ExchangeAdmission.selectDrawing(originalIndexJSON: fixture.indexJSON, selected: fixture.reference, files: fixture.files())
      guard case .materialized = repaired.admission else { Issue.record("Repaired selected bytes did not admit"); return }
    }
  }

  @Test("Same DrawingRef cannot escape a different index's unsupported required feature")
  func indexContextIsPreservedAcrossRepeatedAndFreshSelection() throws {
    try withFixture { fixture in
      let files = try fixture.files()
      let known = try ExchangeAdmission.selectDrawing(originalIndexJSON: fixture.indexJSON, selected: fixture.reference, files: files)
      guard case .materialized(let frozen) = known.admission else { Issue.record("Expected known source-free drawing"); return }
      var json = try #require(JSONSerialization.jsonObject(with: fixture.indexJSON) as? [String: Any])
      json["requiredFeatures"] = ["example.unavailable-context/1"]
      let unknownJSON = try JSONSerialization.data(withJSONObject: json, options: [.sortedKeys])
      for selectedFiles in [try fixture.files(indexJSON: unknownJSON), try fixture.files(indexJSON: unknownJSON)] {
        let blocked = try ExchangeAdmission.selectDrawing(originalIndexJSON: unknownJSON, selected: fixture.reference, files: selectedFiles)
        guard case .opaque(let bytes, _) = blocked.admission else { Issue.record("Known Drawing escaped unknown index context"); continue }
        #expect(bytes == frozen.originalJSON)
        #expect(blocked.reference == known.reference)
        #expect(blocked.originalIndexJSON == unknownJSON)
        #expect(blocked.indexDigest != known.indexDigest)
        #expect(!blocked.capabilities.supported.contains(.drawing))
      }
      let understood = try ExchangeAdmission.selectDrawing(originalIndexJSON: unknownJSON, selected: fixture.reference,
        files: fixture.files(indexJSON: unknownJSON), supportedFeatures: ["example.unavailable-context/1"])
      guard case .materialized(let exact) = understood.admission else { Issue.record("Understood context did not admit"); return }
      #expect(exact.originalJSON == frozen.originalJSON)
      #expect(exact.drawing.requiredFeatures.isEmpty)
    }
  }

  @Test("Caller-supplied stripped index cannot override the resolver's pinned required-feature context")
  func suppliedIndexMustMatchPinnedIndexBytes() throws {
    try withFixture { fixture in
      var json = try #require(JSONSerialization.jsonObject(with: fixture.indexJSON) as? [String: Any])
      json["requiredFeatures"] = ["example.required-index-binding/1"]
      let unknownIndex = try JSONSerialization.data(withJSONObject: json, options: [.sortedKeys])
      let files = try fixture.files(indexJSON: unknownIndex)
      let matching = try ExchangeAdmission.selectDrawing(originalIndexJSON: unknownIndex, selected: fixture.reference, files: files)
      guard case .opaque = matching.admission else { Issue.record("Matching unknown index must remain opaque"); return }
      #expect(matching.originalIndexJSON == unknownIndex)
      #expect(throws: (any Error).self) {
        try ExchangeAdmission.selectDrawing(originalIndexJSON: fixture.indexJSON, selected: fixture.reference, files: files)
      }
      let stillMatching = try ExchangeAdmission.selectDrawing(originalIndexJSON: unknownIndex, selected: fixture.reference, files: files)
      guard case .opaque = stillMatching.admission else { Issue.record("Rejected stripped index contaminated resolver context"); return }
    }
  }
}
