@testable import PortraitArtists
@testable import PortraitLibrary
import Foundation
import Testing
@testable import PlotterApp

@Suite("Independent saved-style loading")
@MainActor
struct PortraitSavedStyleLoadingTests {
  @Test("Small committed catalog loads before unavailable candidate geometry, with corruption visible")
  func catalogWithoutRecords() async throws {
    let directory = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let candidate = try portraitPersistenceCandidate()
    let collection = PortraitSketchCollection(store: .init(directoryURL: directory))
    collection.saveStyle(name: "Keep this", recipe: candidate.recipe)
    for seed in 1...16 { _ = collection.retain(candidate: try portraitPersistenceCandidate(seed: UInt64(seed)), reason: .shortlisted) }
    await collection.awaitPersistence()
    let index = try Data(contentsOf: directory.appendingPathComponent("library-v1.sqlite"))
    let records = try FileManager.default.contentsOfDirectory(at: directory.appendingPathComponent("records"), includingPropertiesForKeys: nil)
    #expect(records.count == 32)
    let payload = try PortraitCandidateCoding.encoder().encode(PortraitLibraryDatabase(url:directory.appendingPathComponent("library-v1.sqlite"),readOnly:true).index())
    let indexed = try #require(JSONSerialization.jsonObject(with: payload) as? [String: Any])
    let catalog = try #require(indexed["drawingCatalog"] as? [[String: Any]])
    let references = try #require(indexed["entries"] as? [[String: Any]])
    #expect(catalog.count == 16 && references.count == 16)
    #expect((catalog + references).allSatisfy {
      $0["program"] == nil && $0["strokes"] == nil && $0["raster"] == nil && $0["sourceData"] == nil
    })
    // Recipe, source and drawing summaries grow with the metadata population;
    // geometry and original pixels remain outside this independently readable index.
    let catalogOwner = try PortraitLibraryDatabase(url:directory.appendingPathComponent("library-v1.sqlite"),readOnly:true)
    let candidateRows = try catalogOwner.rows("SELECT * FROM drawing ORDER BY id")
    #expect(try catalogOwner.scalar("SELECT COUNT(*) FROM drawing WHERE length(candidate_record)=64 AND length(metadata_record)=64 AND length(source_hash)=64 AND length(raster_hash)=64") == "16")
    #expect(try records.reduce(0) { try $0 + Data(contentsOf: $1).count } > 0)
    let unavailableBytes = try Data(contentsOf:records[0])
    try FileManager.default.removeItem(at: records[0])
    let store = PortraitCandidateStore(directoryURL: directory)
    #expect(try await store.loadSavedStyles().map(\.name) == ["Keep this"])
    let restored = PortraitSketchCollection(store: store)
    await restored.load()
    #expect(restored.savedStyles.map(\.name) == ["Keep this"])
    #expect(restored.savedStylesState == .saved)
    if case .failed = restored.persistenceState {} else { Issue.record("Bulk corruption must still block writes") }
    restored.saveStyle(name: "Pending", recipe: candidate.recipe)
    await restored.awaitPersistence()
    #expect(restored.unresolvedMutations == 1)
    #expect(try Data(contentsOf: directory.appendingPathComponent("library-v1.sqlite")) == index)
    try unavailableBytes.write(to:records[0])
    restored.retryPersistence()
    await restored.awaitPersistence()
    #expect(restored.persistenceState == .saved && restored.unresolvedMutations == 0)
    #expect(restored.savedStyles.map(\.name) == ["Keep this","Pending"])
    #expect(restored.entries.count == 16)
    #expect(try catalogOwner.rows("SELECT * FROM drawing ORDER BY id") == candidateRows)
  }

  @Test("Manifest checksum failure never pretends an unavailable library is empty; repaired retry restores it")
  func catalogFailureAndRetry() async throws {
    let directory = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let writer = PortraitSketchCollection(store: .init(directoryURL: directory))
    writer.saveStyle(name: "Original", recipe: try portraitPersistenceCandidate().recipe)
    await writer.awaitPersistence()
    let url = directory.appendingPathComponent("library-v1.sqlite")
    let valid = try Data(contentsOf:url)
    try Data("corrupt SQLite".utf8).write(to:url)
    let reader = PortraitSketchCollection(store: .init(directoryURL: directory))
    await reader.load()
    if case .failed = reader.savedStylesState {} else { Issue.record("Recipe loading failure was hidden") }
    try valid.write(to: url)
    reader.retryPersistence()
    await reader.awaitPersistence()
    #expect(reader.savedStylesState == .saved)
    #expect(reader.savedStyles.map(\.name) == ["Original"])
    #expect(try Data(contentsOf: url) == valid)
  }

  @Test("Legacy catalog inspection is read-only; full load upgrades without changing retained history")
  func legacyReadOnly() async throws {
    let directory = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let candidate = try portraitPersistenceCandidate()
    let writer = PortraitSketchCollection(store: .init(directoryURL: directory))
    _ = writer.retain(candidate: candidate, reason: .shortlisted)
    writer.saveStyle(name: "Legacy", recipe: candidate.recipe)
    await writer.awaitPersistence()
    let record = try #require(FileManager.default.contentsOfDirectory(at: directory.appendingPathComponent("records"), includingPropertiesForKeys: nil).first { url in
      (try? JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])?["program"] != nil
    })
    let storedCandidate = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: record)) as? [String: Any])
    let reasons = try JSONSerialization.jsonObject(with: PortraitCandidateCoding.encoder().encode(writer.entries[0].reasons))
    var archive: [String: Any] = ["schemaVersion": 1, "entries": [["candidate": storedCandidate, "reasons": reasons]],
      "labels": [], "tombstones": []]
    archive["savedStyles"] = try JSONSerialization.jsonObject(with: PortraitCandidateCoding.encoder().encode(writer.savedStyles))
    let payload = try JSONSerialization.data(withJSONObject: archive, options: [.sortedKeys])
    let legacy = try JSONSerialization.data(withJSONObject: ["schemaVersion": 1,
      "sha256": PortraitCandidateCoding.digest(payload), "payload": payload.base64EncodedString()])
    let index = directory.appendingPathComponent("index-v1.json")
    try legacy.write(to: index)
    try FileManager.default.removeItem(at:directory.appendingPathComponent("library-v1.sqlite"))
    let legacyStore = PortraitCandidateStore(directoryURL: directory)
    #expect(try await legacyStore.loadSavedStyles().first?.name == "Legacy")
    #expect(try Data(contentsOf: index) == legacy)
    let reader = PortraitSketchCollection(store: legacyStore)
    await reader.load()
    #expect(reader.entries.map(\.id) == [candidate.id])
    #expect(reader.savedStyles.first?.recipe == candidate.recipe)
    #expect(try Data(contentsOf:index) == legacy)
    #expect(try PortraitLibraryDatabase(url:directory.appendingPathComponent("library-v1.sqlite"),readOnly:true).generation.revision > 0)
    reader.saveStyle(name: "New", recipe: candidate.recipe)
    await reader.awaitPersistence()
    let restored = PortraitSketchCollection(store: .init(directoryURL: directory))
    await restored.load()
    #expect(restored.entries.first?.candidate.program == candidate.program)
    #expect(restored.savedStyles.map(\.name) == ["Legacy", "New"])
  }

  @Test("Read-only cold catalog inspection", .enabled(if: ProcessInfo.processInfo.environment["PORTRAIT_STYLE_CATALOG_INSPECTION_DIR"] != nil))
  func readOnlyCatalogInspection() async throws {
    let directory = URL(fileURLWithPath: try #require(ProcessInfo.processInfo.environment["PORTRAIT_STYLE_CATALOG_INSPECTION_DIR"]))
    let index = directory.appendingPathComponent("index-v1.json")
    let before = try FileManager.default.attributesOfItem(atPath: index.path)
    let start = ProcessInfo.processInfo.systemUptime
    let styles = try await PortraitCandidateStore(directoryURL: directory).loadSavedStyles()
    let elapsed = ProcessInfo.processInfo.systemUptime - start
    let after = try FileManager.default.attributesOfItem(atPath: index.path)
    #expect(!styles.isEmpty)
    #expect(before[.size] as? NSNumber == after[.size] as? NSNumber)
    #expect(before[.modificationDate] as? Date == after[.modificationDate] as? Date)
    print("Read-only legacy catalog: \(styles.count) styles in \(elapsed) seconds; \(before[.size] ?? 0) index bytes; size/mtime unchanged.")
  }

  private func temporaryDirectory() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("portrait-style-load-\(UUID().uuidString)")
  }
}
