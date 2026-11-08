import DrawingLibrary
import Foundation
import PlotterModel
import PortraitCore
import Testing

private extension DrawingLibrary {
  func cacheState() -> (Set<DrawingRef>, [DrawingRef]) {
    (Set(selectedDrawingCache.keys), selectedDrawingCacheRecency)
  }
  func copyCachedContextFixture(_ reference: DrawingRef, from source: DrawingLibrary) async throws {
    guard let cached = await source.selectedDrawingCache[reference] else { throw DrawingLibraryError.missing(reference) }
    selectedDrawingCache[reference] = cached
    touchSelectedDrawing(reference)
  }
  func publishContextFixture(_ admitted: ValidatedExchangePackage, transactionID: UUID) throws {
    let catalog = try commonCatalog()
    _ = try catalog.publish(admitted, transactionID: transactionID)
    refreshOwnership()
  }
}

@Suite("DX05 stored index context", .serialized)
struct DrawingLibraryIndexContextCacheTests {
  @Test("Supported contexts remain readable while an unassociated cache cannot escape an opaque-only context")
  func publicDrawingRechecksSelectedIndexContext() async throws {
    let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("dx05-index-cache-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: temporary) }
    let zip = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
      .appendingPathComponent("Fixtures/DrawingExchange/v1/source-free.zip")
    let staged = try DrawingExchangeCarrier.stageZIP(zip, stagingParent: temporary)
    let known = try ExchangeAdmission.validate(staged)
    let reference = try #require(known.index.known?.roots.first)
    guard case .materialized(let frozen) = try #require(known.drawings[reference]) else {
      Issue.record("Expected known fixture"); return
    }
    let directory = temporary.appendingPathComponent("library")
    let store = DrawingLibrary(directoryURL: directory)
    _ = try await store.retain(frozen.drawing, reason: "imported-known-fixture", closure: .init(publication: known))
    #expect(try await store.drawing(reference).reference == reference)

    var payload: [String: Data] = [:]
    for entry in staged.files.entries.values where entry.path.hasPrefix("data/") {
      payload[entry.path] = try staged.files.record(at: entry.path)
    }
    var index = try #require(JSONSerialization.jsonObject(with: staged.indexJSON) as? [String: Any])
    index["requiredFeatures"] = ["example.unknown-delivery-context/1"]
    payload["data/exchange.json"] = try JSONSerialization.data(withJSONObject: index, options: [.sortedKeys])
    var files = payload
    files["bagit.txt"] = try staged.files.record(at: "bagit.txt")
    files["manifest-sha256.txt"] = Data(payload.keys.sorted().map {
      ExchangeDigest.hash(payload[$0]!).description + "  " + $0 + "\n"
    }.joined().utf8)
    files["tagmanifest-sha256.txt"] = Data(["bagit.txt", "manifest-sha256.txt"].map {
      ExchangeDigest.hash(files[$0]!).description + "  " + $0 + "\n"
    }.joined().utf8)
    let source = temporary.appendingPathComponent("unknown-context-bag")
    for (path, bytes) in files {
      let destination = source.appendingPathComponent(path)
      try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
      try bytes.write(to: destination)
    }
    let altered = try DrawingExchangeCarrier.stageDirectory(source, stagingParent: temporary)
    let unknown = try ExchangeAdmission.validate(altered)
    guard case .opaque(let bytes, _) = try #require(unknown.drawings[reference]) else {
      Issue.record("Unknown index unexpectedly materialized"); return
    }
    #expect(bytes == frozen.originalJSON)
    // A transaction UUID no longer determines authored-context selection.
    let firstTransaction = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000000"))
    try await store.publishContextFixture(unknown, transactionID: firstTransaction)
    #expect(try await store.drawing(reference).reference == reference)
    guard case .opaque(let preserved, _) = try #require(unknown.drawings[reference]) else {
      Issue.record("Opaque publication was reinterpreted"); return
    }
    #expect(preserved == frozen.originalJSON)
    let opaqueDirectory = temporary.appendingPathComponent("opaque-only-library")
    let opaqueOnly = DrawingLibrary(directoryURL: opaqueDirectory)
    try await opaqueOnly.publishContextFixture(unknown, transactionID: UUID())
    try await opaqueOnly.copyCachedContextFixture(reference, from: store)
    await #expect(throws: DrawingLibraryError.self) { try await opaqueOnly.drawing(reference) }
    await opaqueOnly.closeLibrary()
    await store.closeLibrary()
    let reopened = DrawingLibrary(directoryURL: opaqueDirectory)
    await #expect(throws: DrawingLibraryError.self) { try await reopened.drawing(reference) }
    await reopened.closeLibrary()
  }

  @Test("Atomic replacement revalidates identical bytes, rejects tampering, and can recover")
  func selectedObjectAtomicReplacement() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("drawing-cache-replacement-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let library = DrawingLibrary(directoryURL: root)
    let style = try StrokeStyle(nominalLineWidth: 0.8, penProfileID: PenProfileID(UUID()))
    let program = try DrawingProgramCatalog.program(for: .line, style: style)
    let receipt = try DrawingProducerReceipt(id: "example.cache-replacement", version: "1", recordJSON: Data("{}".utf8))
    let value = try Drawing(program: program, input: .none, parent: .none, producer: receipt)
    let retained = try await library.retain(value, reason: "explicit-save")
    #expect(try await library.drawing(retained.reference).program == program)
    let path = root.appendingPathComponent("objects/sha256/" + retained.reference.digest.description)
    let exact = try Data(contentsOf: path)
    let before = try FileManager.default.attributesOfItem(atPath: path.path)[.systemFileNumber] as? NSNumber
    try exact.write(to: path, options: .atomic)
    let after = try FileManager.default.attributesOfItem(atPath: path.path)[.systemFileNumber] as? NSNumber
    #expect(before != nil && after != nil && before != after)
    let revalidated = try await library.drawing(retained.reference)
    #expect(revalidated.reference == retained.reference && revalidated.program == program)
    var changed = exact
    changed[changed.startIndex] ^= 1
    try changed.write(to: path, options: .atomic)
    await #expect(throws: (any Error).self) { try await library.drawing(retained.reference) }
    try exact.write(to: path, options: .atomic)
    let restored = try await library.drawing(retained.reference)
    #expect(restored.reference == retained.reference && restored.program == program)
    await library.closeLibrary()
  }

  @Test("Selected cache has bounded LRU residency and evicted drawings remain readable")
  func boundedSelectedCache() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("drawing-cache-lru-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let library = DrawingLibrary(directoryURL: root)
    let style = try StrokeStyle(nominalLineWidth: 0.8, penProfileID: PenProfileID(UUID()))
    let program = try DrawingProgramCatalog.program(for: .line, style: style)
    let receipt = try DrawingProducerReceipt(id: "example.cache-lru", version: "1", recordJSON: Data("{}".utf8))
    let value = try Drawing(program: program, input: .none, parent: .none, producer: receipt)
    var refs: [DrawingRef] = []
    for _ in 0..<9 { refs.append(try await library.retain(value, reason: "save").reference) }
    for ref in refs.prefix(8) { _ = try await library.drawing(ref) }
    _ = try await library.drawing(refs[0])
    _ = try await library.drawing(refs[8])
    let (cached, recency) = await library.cacheState()
    #expect(cached.count == 8 && recency.count == 8)
    #expect(cached.contains(refs[0]) && !cached.contains(refs[1]))
    #expect(recency.last == refs[8])
    #expect(try await library.drawing(refs[1]).program == program)
    try await library.delete(refs[1])
    let (afterDelete, deleteRecency) = await library.cacheState()
    #expect(!afterDelete.contains(refs[1]) && !deleteRecency.contains(refs[1]))
    await library.closeLibrary()
    let (afterClose, closedRecency) = await library.cacheState()
    #expect(afterClose.isEmpty && closedRecency.isEmpty)
  }

}
