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
    let index = try Data(contentsOf: directory.appendingPathComponent("index-v1.json"))
    let records = try FileManager.default.contentsOfDirectory(at: directory.appendingPathComponent("records"), includingPropertiesForKeys: nil)
    #expect(records.count == 1)
    #expect(index.count < 16_384)
    #expect(try Data(contentsOf: records[0]).count > index.count * 4)
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
    #expect(try Data(contentsOf: directory.appendingPathComponent("index-v1.json")) == index)
  }

  @Test("Manifest checksum failure never pretends an unavailable library is empty; repaired retry restores it")
  func catalogFailureAndRetry() async throws {
    let directory = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let writer = PortraitSketchCollection(store: .init(directoryURL: directory))
    writer.saveStyle(name: "Original", recipe: try portraitPersistenceCandidate().recipe)
    await writer.awaitPersistence()
    let url = directory.appendingPathComponent("index-v1.json")
    let valid = try Data(contentsOf: url)
    var envelope = try #require(JSONSerialization.jsonObject(with: valid) as? [String: Any])
    envelope["sha256"] = String(repeating: "0", count: 64)
    try JSONSerialization.data(withJSONObject: envelope).write(to: url)
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

  @Test("Legacy embedded archive remains readable and byte-exact until an actual save")
  func legacyReadOnly() async throws {
    let directory = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let candidate = try portraitPersistenceCandidate()
    let writer = PortraitSketchCollection(store: .init(directoryURL: directory))
    _ = writer.retain(candidate: candidate, reason: .shortlisted)
    writer.saveStyle(name: "Legacy", recipe: candidate.recipe)
    await writer.awaitPersistence()
    let record = try #require(FileManager.default.contentsOfDirectory(at: directory.appendingPathComponent("records"), includingPropertiesForKeys: nil).first)
    var archive = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: record)) as? [String: Any])
    archive["savedStyles"] = try JSONSerialization.jsonObject(with: PortraitCandidateCoding.encoder().encode(writer.savedStyles))
    let payload = try JSONSerialization.data(withJSONObject: archive, options: [.sortedKeys])
    let legacy = try JSONSerialization.data(withJSONObject: ["schemaVersion": 1,
      "sha256": PortraitCandidateCoding.digest(payload), "payload": payload.base64EncodedString()])
    let index = directory.appendingPathComponent("index-v1.json")
    try legacy.write(to: index)
    let reader = PortraitSketchCollection(store: .init(directoryURL: directory))
    await reader.load()
    #expect(reader.entries.map(\.id) == [candidate.id])
    #expect(reader.savedStyles.first?.recipe == candidate.recipe)
    #expect(try Data(contentsOf: index) == legacy)
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
