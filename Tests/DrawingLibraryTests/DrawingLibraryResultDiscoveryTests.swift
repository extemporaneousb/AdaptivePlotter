import Foundation
import DrawingLibrary
import PortraitCore
import Testing

private extension DrawingLibrary {
  func resultDiscoveryState(_ ref: DrawingRef) throws -> (LibraryExchangeMetadata?, String?, String?) {
    guard let db = try commonReadDatabase() else { return (nil, nil, nil) }
    return (try preparedMetadata(ref, database: db),
      try db.scalar("SELECT value FROM state WHERE key='library_uuid'"),
      try db.scalar("SELECT COUNT(*) FROM dx_retention_intent"))
  }
}

@Suite("DX06 current result discovery", .serialized)
struct DrawingLibraryResultDiscoveryTests {
  private func root() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("dx06-discovery-" + UUID().uuidString)
  }
  private func authored(_ fixture: DrawingLibraryResultFixture, at url: URL) throws {
    var value = fixture
    value.index["kind"] = "drawing"
    value.index["jobs"] = [String]()
    value.index["attempts"] = [String]()
    value.payload = value.payload.filter { !$0.key.hasPrefix("data/jobs/") && !$0.key.hasPrefix("data/attempts/") }
    try value.write(to: url)
  }

  @Test("Empty-library mount is discoverable after readonly reopen without fabricated retention or identity")
  func discoverDrawingAfterReopen() async throws {
    let root = root(); defer { try? FileManager.default.removeItem(at: root) }
    let fixture = try DrawingLibraryResultFixture()
    let input = root.appendingPathComponent("input")
    try fixture.write(to: input)
    let directory = root.appendingPathComponent("library")
    let owner = DrawingLibrary(directoryURL: directory)
    let mounted = try await owner.mountResult(from: input)
    let bytes = try DrawingLibraryResultFixture.bytes(await owner.result(mounted.reference))
    await owner.closeLibrary()
    let reader = DrawingLibrary(directoryURL: directory)
    let drawing = try #require(try await reader.drawings().entries.first)
    #expect(drawing.reference == fixture.frozen.reference)
    #expect(drawing.strokeCount == fixture.frozen.drawing.program.strokes.count)
    #expect(drawing.createdAt == Date(timeIntervalSince1970: 1_800_000_000))
    #expect(try await reader.results(for: drawing.reference).entries.map(\.reference) == [mounted.reference])
    #expect(try await reader.results().entries.map(\.reference) == [mounted.reference])
    #expect(try DrawingLibraryResultFixture.bytes(await reader.result(mounted.reference)) == bytes)
    let state = try await reader.resultDiscoveryState(drawing.reference)
    #expect(state.0 == nil)
    #expect(state.1 == nil)
    #expect(state.2 == "0")
    let exported = root.appendingPathComponent("readonly.zip")
    try await reader.exportResult(mounted.reference, to: exported)
    let offline = DrawingLibrary(directoryURL: root.appendingPathComponent("offline"))
    let again = try await offline.mountResult(from: exported)
    #expect(again.reference == mounted.reference)
    #expect(try DrawingLibraryResultFixture.bytes(await offline.result(again.reference)) == bytes)
    await reader.closeLibrary()
    await offline.closeLibrary()
  }

  @Test("Mount preserves existing title, creation date, reasons, UUID and tombstone")
  func preserveAuthoredMetadata() async throws {
    let root = root(); defer { try? FileManager.default.removeItem(at: root) }
    let fixture = try DrawingLibraryResultFixture()
    let authoredURL = root.appendingPathComponent("authored")
    try authored(fixture, at: authoredURL)
    let library = DrawingLibrary(directoryURL: root.appendingPathComponent("library"))
    _ = try await library.importDrawings(from: authoredURL)
    let ref = fixture.frozen.reference
    try await library.rename(ref, title: "Chosen title")
    let bound = try await library.drawing(ref)
    _ = try await library.retain(bound, reason: "explicit-choose")
    let before = try await library.resultDiscoveryState(ref)
    let summary = try #require(try await library.drawings().entries.first)
    #expect(before.0?.retentionReasons.contains("explicit-choose") == true)
    let input = root.appendingPathComponent("result")
    try fixture.write(to: input)
    let mounted = try await library.mountResult(from: input)
    #expect(try await library.mountResult(from: input).wasAlreadyMounted)
    let after = try await library.resultDiscoveryState(ref)
    #expect(after.0 == before.0 && after.1 == before.1 && after.2 == before.2)
    let discovered = try #require(try await library.drawings().entries.first)
    #expect(discovered.reference == summary.reference && discovered.createdAt == summary.createdAt && discovered.title == "Chosen title")
    try await library.delete(ref)
    let tombstoned = try await library.resultDiscoveryState(ref)
    let next = try DrawingLibraryResultFixture(drawing: fixture.frozen, marker: "later-result")
    let nextURL = root.appendingPathComponent("next")
    try next.write(to: nextURL)
    _ = try await library.mountResult(from: nextURL)
    #expect(try await library.drawings().entries.isEmpty)
    let final = try await library.resultDiscoveryState(ref)
    #expect(final.0 == tombstoned.0 && final.1 == tombstoned.1 && final.2 == tombstoned.2)
    #expect(final.0?.tombstoned == true)
    #expect(try await library.results(for: ref).entries.count == 2)
    #expect(try await library.result(mounted.reference).attempts.count == 3)
    await library.closeLibrary()
  }

  @Test("Opaque feature-gated roots remain globally discoverable after readonly reopen without invented Drawing metrics")
  func opaqueGlobalDiscovery() async throws {
    let root = root(); defer { try? FileManager.default.removeItem(at: root) }
    let fixture = try DrawingLibraryResultFixture(features: ["example.unknown-discovery/1"])
    let input = root.appendingPathComponent("input")
    try fixture.write(to: input)
    let directory = root.appendingPathComponent("library")
    let owner = DrawingLibrary(directoryURL: directory)
    let mounted = try await owner.mountResult(from: input)
    let bytes = try DrawingLibraryResultFixture.bytes(await owner.result(mounted.reference))
    await owner.closeLibrary()
    let reader = DrawingLibrary(directoryURL: directory)
    #expect(try await reader.drawings().entries.isEmpty)
    let page = try await reader.results()
    #expect(page.entries.map(\.reference) == [mounted.reference])
    #expect(page.entries.first?.drawingReferences == [fixture.frozen.reference])
    let result = try await reader.result(mounted.reference)
    #expect(!result.capabilities.supported.contains(.interpretResults))
    #expect(!result.capabilities.supported.contains(.physicalInterpretation))
    if case .opaque? = result.drawings[fixture.frozen.reference] {} else { Issue.record("Opaque root was materialized") }
    let exported = root.appendingPathComponent("opaque.zip")
    try await reader.exportResult(mounted.reference, to: exported)
    let offline = DrawingLibrary(directoryURL: root.appendingPathComponent("offline"))
    let again = try await offline.mountResult(from: exported)
    #expect(try DrawingLibraryResultFixture.bytes(await offline.result(again.reference)) == bytes)
    await reader.closeLibrary()
    await offline.closeLibrary()
  }

  @Test("Global pages deduplicate multi-root publications and reject drawing-scoped cursors in both directions")
  func globalPagingAndScope() async throws {
    let root = root(); defer { try? FileManager.default.removeItem(at: root) }
    let primary = try DrawingLibraryResultFixture.drawing()
    let secondary = try DrawingLibraryResultFixture.drawing()
    let library = DrawingLibrary(directoryURL: root.appendingPathComponent("library"))
    var refs: [DrawingLibraryResultRef] = []
    let dates = ["2027-01-15T08:00:00.100Z", "2027-01-15T09:00:00.900+01:00", "2027-01-15T03:00:00.900-05:00"]
    for (position, date) in dates.enumerated() {
      var fixture = try DrawingLibraryResultFixture(drawing: primary, marker: "global-\(position)")
      fixture.index["includedAsOf"] = date
      fixture.index["roots"] = try DrawingLibraryResultFixture.wire([primary.reference, secondary.reference])
      let secondRef = secondary.reference
      fixture.payload["data/drawings/\(secondRef.issuer.uuidString.lowercased())/\(secondRef.revision.uuidString.lowercased())/drawing.json"] = secondary.originalJSON
      var assets = try #require(fixture.index["assets"] as? [[String: Any]])
      let extra = [try ExchangeAsset(bytes: secondary.originalProgramJSON, mediaType: "application/json", encoding: DrawingExchangeCodec.strokeProfile),
        try ExchangeAsset(bytes: secondary.drawing.producer.originalJSON, mediaType: "application/json", encoding: "utf8-json")]
      for (asset, bytes) in zip(extra, [secondary.originalProgramJSON, secondary.drawing.producer.originalJSON]) {
        fixture.payload["data/objects/sha256/" + asset.object.description] = bytes
        let descriptor = try #require(DrawingLibraryResultFixture.wire(ExchangeAssetDescriptor(asset: asset)) as? [String: Any])
        if !assets.contains(where: { ($0["object"] as? String) == asset.object.description }) { assets.append(descriptor) }
      }
      fixture.index["assets"] = assets
      let input = root.appendingPathComponent("input-\(position)")
      try fixture.write(to: input)
      refs.append(try await library.mountResult(from: input).reference)
    }
    let tied = [refs[1], refs[2]].sorted { $0.indexDigest.description < $1.indexDigest.description }
    let expected = tied + [refs[0]]
    let first = try await library.results(limit: 1)
    #expect(first.entries.map(\.reference) == Array(expected.prefix(1)))
    let perDrawing = try await library.results(for: primary.reference, limit: 1)
    let perDrawingCursor = try #require(perDrawing.next)
    let firstCursor = try #require(first.next)
    await #expect(throws: (any Error).self) { try await library.results(after: perDrawingCursor) }
    await #expect(throws: (any Error).self) { try await library.results(for: primary.reference, after: firstCursor) }
    let artwork = root.appendingPathComponent("library/objects")
    let held = root.appendingPathComponent("held")
    try FileManager.default.moveItem(at: artwork, to: held)
    var seen: [DrawingLibraryResultRef] = []
    var cursor: DrawingLibraryResultCursor?
    repeat {
      let page = try await library.results(limit: 1, after: cursor)
      #expect(page.entries.count == 1)
      #expect(page.entries.first?.drawingReferences == [primary.reference, secondary.reference])
      seen += page.entries.map(\.reference)
      cursor = page.next
    } while cursor != nil && seen.count <= refs.count
    #expect(seen == expected && cursor == nil)
    #expect(try await library.results(for: secondary.reference).entries.count == 3)
    for invalid in [0, 501] {
      await #expect(throws: (any Error).self) { try await library.results(limit: invalid) }
    }
    try FileManager.default.moveItem(at: held, to: artwork)
    await library.closeLibrary()
  }
}
