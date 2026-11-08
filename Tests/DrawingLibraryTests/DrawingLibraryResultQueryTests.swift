import Foundation
import DrawingLibrary
import PortraitCore
import Testing

@Suite("DX06 exact result selection and metadata", .serialized)
struct DrawingLibraryResultQueryTests {
  private func root() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("dx06-result-query-" + UUID().uuidString)
  }

  @Test("Authored and multiple result publications sharing a Drawing export only the requested complete inventory")
  func selectedPublicationInventory() async throws {
    let root = root(); defer { try? FileManager.default.removeItem(at: root) }
    let drawing = try DrawingLibraryResultFixture.drawing()
    let library = DrawingLibrary(directoryURL: root.appendingPathComponent("library"))
    var authored = try DrawingLibraryResultFixture(drawing: drawing)
    authored.index["kind"] = "drawing"
    authored.index["jobs"] = [String]()
    authored.index["attempts"] = [String]()
    authored.payload = authored.payload.filter { !$0.key.hasPrefix("data/jobs/") && !$0.key.hasPrefix("data/attempts/") }
    let authoredURL = root.appendingPathComponent("authored")
    try authored.write(to: authoredURL)
    #expect(try await library.importDrawings(from: authoredURL) == [drawing.reference])
    var references: [DrawingLibraryResultRef] = []
    var expected: [[String: Data]] = []
    for marker in ["one", "two", "three"] {
      let fixture = try DrawingLibraryResultFixture(drawing: drawing, marker: marker)
      let source = root.appendingPathComponent(marker)
      try fixture.write(to: source)
      let mounted = try await library.mountResult(from: source)
      references.append(mounted.reference)
      expected.append(try DrawingLibraryResultFixture.bytes(await library.result(mounted.reference)))
      try FileManager.default.removeItem(at: source)
    }
    #expect(Set(references).count == 3)
    #expect(try await library.results(for: drawing.reference).entries.count == 3)
    try FileManager.default.removeItem(at: authoredURL)
    for (position, reference) in references.enumerated() {
      let exported = root.appendingPathComponent("result-\(position).zip")
      try await library.exportResult(reference, to: exported)
      let offline = DrawingLibrary(directoryURL: root.appendingPathComponent("offline-\(position)"))
      let mounted = try await offline.mountResult(from: exported)
      #expect(mounted.reference == reference)
      let result = try await offline.result(mounted.reference)
      #expect(try DrawingLibraryResultFixture.bytes(result) == expected[position])
      #expect(result.receipts.count == 1)
      #expect(result.attempts.count == 3)
      await offline.closeLibrary()
    }
    // Neither digest alone is enough to substitute another requested publication.
    let wrong = DrawingLibraryResultRef(indexDigest: references[0].indexDigest, packageDigest: references[1].packageDigest)
    await #expect(throws: (any Error).self) { try await library.result(wrong) }
    let denied = root.appendingPathComponent("wrong.zip")
    await #expect(throws: (any Error).self) { try await library.exportResult(wrong, to: denied) }
    #expect(!FileManager.default.fileExists(atPath: denied.path))
    await library.closeLibrary()
  }

  @Test("Metadata paging uses numeric chronology, exact Drawing refs and no artwork reads")
  func boundedMetadataPages() async throws {
    let root = root(); defer { try? FileManager.default.removeItem(at: root) }
    let drawing = try DrawingLibraryResultFixture.drawing()
    let directory = root.appendingPathComponent("library")
    let library = DrawingLibrary(directoryURL: directory)
    let dates = ["2027-01-15T08:00:00.100Z", "2027-01-15T09:00:00.900+01:00", "2027-01-15T03:00:00.500-05:00"]
    var references: [DrawingLibraryResultRef] = []
    for (position, date) in dates.enumerated() {
      var fixture = try DrawingLibraryResultFixture(drawing: drawing, marker: "date-\(position)")
      fixture.index["includedAsOf"] = date
      let input = root.appendingPathComponent("input-\(position)")
      try fixture.write(to: input)
      references.append(try await library.mountResult(from: input).reference)
    }
    let artwork = directory.appendingPathComponent("objects")
    let held = directory.appendingPathComponent("held-artwork")
    try FileManager.default.moveItem(at: artwork, to: held)
    let first = try await library.results(for: drawing.reference, limit: 1)
    #expect(first.entries.map(\.reference) == [references[1]])
    #expect(first.entries.first?.includedAsOf == dates[1])
    let second = try await library.results(for: drawing.reference, limit: 1, after: #require(first.next))
    let third = try await library.results(for: drawing.reference, limit: 1, after: #require(second.next))
    #expect(second.entries.map(\.reference) == [references[2]])
    #expect(third.entries.map(\.reference) == [references[0]])
    #expect(third.next == nil)
    #expect(first.entries.allSatisfy { $0.drawingReferences == [drawing.reference] })
    let absent = DrawingRef(issuer: drawing.reference.issuer, revision: UUID(), digest: drawing.reference.digest)
    #expect(try await library.results(for: absent).entries.isEmpty)
    let wrong = DrawingRef(issuer: drawing.reference.issuer, revision: drawing.reference.revision,
      digest: .hash(Data("same issuer/revision with wrong digest".utf8)))
    do {
      _ = try await library.results(for: wrong)
      Issue.record("Existing Drawing identity accepted a divergent digest selector")
    } catch DrawingLibraryError.referenceConflict(let expected, let actual) {
      #expect(expected == wrong)
      #expect(actual == drawing.reference.digest)
    }
    await #expect(throws: (any Error).self) {
      try await library.results(for: wrong, limit: 1, after: #require(first.next))
    }
    for invalid in [0, 501] {
      await #expect(throws: (any Error).self) { try await library.results(for: drawing.reference, limit: invalid) }
    }
    await #expect(throws: (any Error).self) { try await library.result(references[0]) }
    try FileManager.default.moveItem(at: held, to: artwork)
    // The cursor is a metadata snapshot, not a license to silently traverse a newer generation.
    let another = try DrawingLibraryResultFixture(drawing: drawing, marker: "later-publication")
    let input = root.appendingPathComponent("later")
    try another.write(to: input)
    _ = try await library.mountResult(from: input)
    await #expect(throws: (any Error).self) {
      try await library.results(for: drawing.reference, limit: 1, after: #require(first.next))
    }
    await library.closeLibrary()
  }

  @Test("Equal numeric dates page deterministically by full publication identity")
  func equalChronology() async throws {
    let root = root(); defer { try? FileManager.default.removeItem(at: root) }
    let drawing = try DrawingLibraryResultFixture.drawing()
    let library = DrawingLibrary(directoryURL: root.appendingPathComponent("library"))
    var refs: [DrawingLibraryResultRef] = []
    for (position, date) in ["2027-01-15T08:00:00.500Z", "2027-01-15T09:00:00.500+01:00", "2027-01-15T03:00:00.500-05:00"].enumerated() {
      var fixture = try DrawingLibraryResultFixture(drawing: drawing, marker: "tie-\(position)")
      fixture.index["includedAsOf"] = date
      let input = root.appendingPathComponent("tie-\(position)")
      try fixture.write(to: input)
      refs.append(try await library.mountResult(from: input).reference)
    }
    let expected = refs.sorted {
      $0.indexDigest.description == $1.indexDigest.description
        ? $0.packageDigest.description < $1.packageDigest.description
        : $0.indexDigest.description < $1.indexDigest.description
    }
    var actual: [DrawingLibraryResultRef] = []
    var cursor: DrawingLibraryResultCursor?
    repeat {
      let page = try await library.results(for: drawing.reference, limit: 1, after: cursor)
      #expect(page.entries.count == 1)
      actual += page.entries.map(\.reference)
      cursor = page.next
    } while cursor != nil && actual.count <= refs.count
    #expect(cursor == nil)
    #expect(actual == expected)
    await library.closeLibrary()
  }

  @Test("Fractional chronology survives exact committed verification, reopen and redelivery")
  func fractionalCommittedChronology() async throws {
    let root = root(); defer { try? FileManager.default.removeItem(at: root) }
    var fixture = try DrawingLibraryResultFixture()
    fixture.index["includedAsOf"] = "1970-01-01T00:00:00.123Z"
    let input = root.appendingPathComponent("input")
    try fixture.write(to: input)
    let directory = root.appendingPathComponent("library")
    let library = DrawingLibrary(directoryURL: directory)
    let first = try await library.mountResult(from: input)
    let duplicate = try await library.mountResult(from: input)
    #expect(duplicate.wasAlreadyMounted)
    #expect(duplicate.reference == first.reference)
    #expect(try await library.results(for: fixture.frozen.reference).entries.first?.includedAsOf == "1970-01-01T00:00:00.123Z")
    await library.closeLibrary()
    let reopened = DrawingLibrary(directoryURL: directory)
    try await reopened.open()
    let again = try await reopened.mountResult(from: input)
    #expect(again.wasAlreadyMounted && again.reference == first.reference)
    #expect(try await reopened.results(for: fixture.frozen.reference).entries.map(\.reference) == [first.reference])
    #expect(try await reopened.result(first.reference).index.known?.includedAsOf == "1970-01-01T00:00:00.123Z")
    await reopened.closeLibrary()
  }

  @Test("Absent-root result inspection creates nothing and does not acquire the writer")
  func absentInspection() async throws {
    let root = root(); defer { try? FileManager.default.removeItem(at: root) }
    let library = DrawingLibrary(directoryURL: root)
    let fixture = try DrawingLibraryResultFixture()
    #expect(try await library.results(for: fixture.frozen.reference).entries.isEmpty)
    #expect(try await library.results().entries.isEmpty)
    let absent = DrawingLibraryResultRef(indexDigest: .hash(Data("absent-index".utf8)), packageDigest: .hash(Data("absent-inventory".utf8)))
    await #expect(throws: (any Error).self) { try await library.result(absent) }
    let export = root.deletingLastPathComponent().appendingPathComponent("absent-export-" + UUID().uuidString + ".zip")
    defer { try? FileManager.default.removeItem(at: export) }
    await #expect(throws: (any Error).self) { try await library.exportResult(absent, to: export) }
    #expect(!FileManager.default.fileExists(atPath: export.path))
    #expect(!FileManager.default.fileExists(atPath: root.path))
    await library.closeLibrary()
  }
}
