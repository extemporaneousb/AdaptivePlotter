import Foundation
import DrawingLibrary
import PortraitCore
import Testing

private extension DrawingLibrary {
  func photoSummaryPayloadBytes(_ ref: PhotoRef) throws -> Int {
    guard let db = try commonReadDatabase() else { throw DrawingLibraryError.unavailable("No source summary") }
    return Int(try db.scalar("SELECT length(CAST(payload AS BLOB)) FROM dx_source_summary WHERE kind='photo' AND namespace=? AND identity=? AND digest=?", [ref.issuer.uuidString.lowercased(), ref.revision.uuidString.lowercased(), ref.digest.description]) ?? "0") ?? 0
  }
}

@Suite("DX07 bounded neutral source queries", .serialized)
struct DrawingLibraryPhotoQueryTests {
  private func key(_ ref: PhotoRef) -> String {
    [ref.issuer.uuidString.lowercased(), ref.revision.uuidString.lowercased(), ref.digest.description].joined(separator: "/")
  }
  private func inputKey(_ ref: ImageInputRef) -> String {
    [ref.issuer.uuidString.lowercased(), ref.revision.uuidString.lowercased(), ref.digest.description].joined(separator: "/")
  }

  @Test("Photo chronology separates acquired/imported/unknown and sorts unknown below known pre-1970 dates without artwork")
  func chronologyWithoutArtwork() async throws {
    let root = DrawingLibraryPhotoFixture.root()
    defer { try? FileManager.default.removeItem(at: root) }
    let old = try DrawingLibraryPhotoFixture(acquired: .known(ExchangeTimestamp(wallTime: "1960-01-01T00:00:00.123Z"), provenance: "fixture capture"))
    let tied = try DrawingLibraryPhotoFixture(acquired: .known(ExchangeTimestamp(wallTime: "1960-01-01T01:00:00.123+01:00"), provenance: "fixture offset capture"))
    let imported = try DrawingLibraryPhotoFixture(imported: .known(ExchangeTimestamp(wallTime: "2027-01-15T08:00:00Z"), provenance: "fixture import"))
    let ancient = try DrawingLibraryPhotoFixture(imported: .known(ExchangeTimestamp(wallTime: "1900-01-01T00:00:00Z"), provenance: "fixture old import"))
    let unknown = try DrawingLibraryPhotoFixture()
    let event = try DrawingLibraryPhotoFixture(acquired: .known(ExchangeTimestamp(event: ExchangeEventClock(clockID: "fixture", bootSession: UUID(), ticks: "42", ticksPerSecond: 1)), provenance: "fixture event only"))
    let library = DrawingLibrary(directoryURL: root)
    for fixture in [old, tied, imported, ancient, unknown, event] { try await fixture.publish(to: library) }
    let expected = [imported.photo.reference] + [old.photo.reference, tied.photo.reference].sorted { key($0) < key($1) } + [ancient.photo.reference] + [unknown.photo.reference, event.photo.reference].sorted { key($0) < key($1) }
    let artwork = root.appendingPathComponent("objects"), held = root.appendingPathComponent("held")
    try FileManager.default.moveItem(at: artwork, to: held)
    var refs: [PhotoRef] = []
    var entries: [DrawingLibraryPhotoEntry] = []
    var cursor: DrawingLibraryPhotoCursor?
    repeat {
      let page = try await library.photos(limit: 1, after: cursor)
      #expect(page.entries.count == 1)
      entries += page.entries; refs += page.entries.map(\.reference)
      cursor = page.next
    } while cursor != nil && refs.count <= expected.count
    #expect(cursor == nil && refs == expected)
    let known = try #require(entries.first { $0.reference == old.photo.reference })
    if case .known(let time, let provenance)? = known.acquired {
      #expect(time.wallTime == "1960-01-01T00:00:00.123Z" && provenance == "fixture capture")
    } else { Issue.record("Acquired date fact lost") }
    let importedEntry = try #require(entries.first { $0.reference == imported.photo.reference })
    if case .unknown(let provenance)? = importedEntry.acquired {
      #expect(provenance == "Synthetic acquisition unknown")
    } else { Issue.record("Import was given a fabricated acquisition date") }
    if case .known(let time, _)? = importedEntry.imported { #expect(time.wallTime == "2027-01-15T08:00:00Z") }
    else { Issue.record("Import date unavailable") }
    let unknownEntry = try #require(entries.first { $0.reference == unknown.photo.reference })
    #expect(unknownEntry.sortDate == nil)
    let eventEntry = try #require(entries.first { $0.reference == event.photo.reference })
    #expect(eventEntry.sortDate == nil)
    if case .known(let time, _)? = eventEntry.acquired {
      #expect(time.wallTime == nil && time.event?.ticks == "42")
    } else { Issue.record("Known event-only acquisition became an invented wall date or opaque fact") }
    if case .unknown? = unknownEntry.acquired {} else { Issue.record("Explicit unknown acquired fact became opaque or known") }
    #expect(try await library.inputs(for: old.photo.reference).entries.map(\.reference) == [old.input.reference])
    await #expect(throws: (any Error).self) { try await library.photo(old.photo.reference) }
    for invalid in [0, 501] {
      await #expect(throws: (any Error).self) { try await library.photos(limit: invalid) }
    }
    try FileManager.default.moveItem(at: held, to: artwork)
    let first = try await library.photos(limit: 1)
    let firstCursor = try #require(first.next)
    let extra = try DrawingLibraryPhotoFixture()
    try await extra.publish(to: library)
    await #expect(throws: (any Error).self) { try await library.photos(limit: 1, after: firstCursor) }
    await library.closeLibrary()
  }

  @Test("Prepared inputs page by exact reference and bind cursors to the complete PhotoRef")
  func exactInputPages() async throws {
    let root = DrawingLibraryPhotoFixture.root()
    defer { try? FileManager.default.removeItem(at: root) }
    let fixture = try DrawingLibraryPhotoFixture()
    let library = DrawingLibrary(directoryURL: root)
    let raster = try #require(fixture.input.assets.first { $0.descriptor.asset.object == fixture.input.record.raster.object })
    let mask = try #require(fixture.input.assets.first { $0.descriptor.asset.object == fixture.input.record.mask?.object })
    var refs: [ImageInputRef] = []
    for _ in 0..<3 {
      let input = try DrawingImageRecords.input(identity: .init(issuer: UUID()), photo: fixture.photo, raster: raster,
        width: 2, height: 2, orientation: "up", sourceToInput: fixture.input.record.sourceToInput,
        inputToField: fixture.input.record.inputToField, mask: .present(mask),
        operations: [DrawingImageOperation(kind: "identity", parametersJSON: Data("{}".utf8))],
        preparation: DrawingProducerReceipt(id: "example.dx07-input-order", version: "1", recordJSON: Data("{}".utf8)))
      try await library.commitRecords([], closure: .init(input: input)); refs.append(input.reference)
    }
    let first = try await library.inputs(for: fixture.photo.reference, limit: 1)
    let firstCursor = try #require(first.next)
    var actual: [ImageInputRef] = []
    var cursor: DrawingLibraryInputCursor?
    repeat {
      let page = try await library.inputs(for: fixture.photo.reference, limit: 1, after: cursor)
      #expect(page.entries.allSatisfy { $0.photo == fixture.photo.reference })
      actual += page.entries.map(\.reference); cursor = page.next
    } while cursor != nil && actual.count <= refs.count
    #expect(actual == refs.sorted { inputKey($0) < inputKey($1) } && cursor == nil)
    let another = try DrawingLibraryPhotoFixture()
    try await another.publish(to: library)
    await #expect(throws: (any Error).self) { try await library.inputs(for: another.photo.reference, limit: 1, after: firstCursor) }
    let wrong = PhotoRef(issuer: fixture.photo.reference.issuer, revision: fixture.photo.reference.revision, digest: .hash(Data("wrong digest".utf8)))
    await #expect(throws: (any Error).self) { try await library.inputs(for: wrong) }
    for invalid in [0, 501] {
      await #expect(throws: (any Error).self) { try await library.inputs(for: fixture.photo.reference, limit: invalid) }
    }
    await library.closeLibrary()
  }

  @Test("Opaque Photo date vocabulary is unavailable rather than an invented unknown fact")
  func opaqueDateFacts() async throws {
    let root = DrawingLibraryPhotoFixture.root()
    defer { try? FileManager.default.removeItem(at: root) }
    let fixture = try DrawingLibraryPhotoFixture()
    var payload = try fixture.packagePayload()
    var photoJSON = try #require(JSONSerialization.jsonObject(with: payload[fixture.photoPath]!) as? [String: Any])
    photoJSON["profile"] = "adaptiveplotter.photo/9"
    let photoBytes = try DrawingLibraryPhotoFixture.json(photoJSON)
    payload[fixture.photoPath] = photoBytes
    let photo = PhotoRef(issuer: fixture.photo.reference.issuer, revision: fixture.photo.reference.revision, digest: .hash(photoBytes))
    var inputJSON = try #require(JSONSerialization.jsonObject(with: payload[fixture.inputPath]!) as? [String: Any])
    inputJSON["photo"] = try DrawingLibraryPhotoFixture.wire(photo)
    let inputBytes = try DrawingLibraryPhotoFixture.json(inputJSON)
    payload[fixture.inputPath] = inputBytes
    let input = ImageInputRef(issuer: fixture.input.reference.issuer, revision: fixture.input.reference.revision, digest: .hash(inputBytes))
    var index = try #require(JSONSerialization.jsonObject(with: payload["data/exchange.json"]!) as? [String: Any])
    index["photos"] = try DrawingLibraryPhotoFixture.wire([photo]); index["inputs"] = try DrawingLibraryPhotoFixture.wire([input])
    payload["data/exchange.json"] = try DrawingLibraryPhotoFixture.json(index)
    let library = DrawingLibrary(directoryURL: root.appendingPathComponent("library"))
    try await library.publishPhotoFixture(payload)
    let entry = try #require(try await library.photos().entries.first)
    #expect(entry.reference == photo && entry.acquired == nil && entry.imported == nil && entry.sortDate == nil)
    #expect(!entry.unsupportedReasons.isEmpty)
    await #expect(throws: (any Error).self) { try await library.photo(photo) }
    await #expect(throws: (any Error).self) { try await library.input(input) }
    await library.closeLibrary()
  }

  @Test("Metadata projection stays compact with a large inert record extension and pages without its bytes")
  func compactSourceProjection() async throws {
    let root = DrawingLibraryPhotoFixture.root()
    defer { try? FileManager.default.removeItem(at: root) }
    let fixture = try DrawingLibraryPhotoFixture()
    var payload = try fixture.packagePayload()
    var photoJSON = try #require(JSONSerialization.jsonObject(with: payload[fixture.photoPath]!) as? [String: Any])
    photoJSON["vendorNotes"] = String(repeating: "inert source extension ", count: 8192)
    let photoBytes = try DrawingLibraryPhotoFixture.json(photoJSON)
    #expect(photoBytes.count > 128 * 1024)
    payload[fixture.photoPath] = photoBytes
    let photo = PhotoRef(issuer: fixture.photo.reference.issuer, revision: fixture.photo.reference.revision, digest: .hash(photoBytes))
    var inputJSON = try #require(JSONSerialization.jsonObject(with: payload[fixture.inputPath]!) as? [String: Any])
    inputJSON["photo"] = try DrawingLibraryPhotoFixture.wire(photo)
    let inputBytes = try DrawingLibraryPhotoFixture.json(inputJSON)
    payload[fixture.inputPath] = inputBytes
    let input = ImageInputRef(issuer: fixture.input.reference.issuer, revision: fixture.input.reference.revision, digest: .hash(inputBytes))
    var index = try #require(JSONSerialization.jsonObject(with: payload["data/exchange.json"]!) as? [String: Any])
    index["photos"] = try DrawingLibraryPhotoFixture.wire([photo]); index["inputs"] = try DrawingLibraryPhotoFixture.wire([input])
    payload["data/exchange.json"] = try DrawingLibraryPhotoFixture.json(index)
    let directory = root.appendingPathComponent("library")
    let owner = DrawingLibrary(directoryURL: directory)
    try await owner.publishPhotoFixture(payload)
    #expect(try await owner.photo(photo).record.originalJSON == photoBytes)
    await owner.closeLibrary()
    let artwork = directory.appendingPathComponent("objects"), held = directory.appendingPathComponent("held")
    try FileManager.default.moveItem(at: artwork, to: held)
    let reader = DrawingLibrary(directoryURL: directory)
    let size = try await reader.photoSummaryPayloadBytes(photo)
    #expect(size > 0 && size < 8192)
    let entries = try await reader.photos(limit: 1).entries
    #expect(entries.map(\.reference) == [photo])
    #expect(entries.first?.sortDate == nil)
    #expect(try await reader.inputs(for: photo).entries.map(\.reference) == [input])
    try FileManager.default.moveItem(at: held, to: artwork)
    await reader.closeLibrary()
  }

  @Test("Absent-root source queries and loads create no files or writer")
  func absentInspection() async throws {
    let root = DrawingLibraryPhotoFixture.root()
    defer { try? FileManager.default.removeItem(at: root) }
    let fixture = try DrawingLibraryPhotoFixture()
    let library = DrawingLibrary(directoryURL: root)
    #expect(try await library.photos().entries.isEmpty)
    #expect(try await library.photoMetadataRevision() == 0)
    #expect(try await library.photoMetadata([]).isEmpty)
    await #expect(throws: (any Error).self) { try await library.photoMetadata(fixture.photo.reference) }
    #expect(try await library.inputs(for: fixture.photo.reference).entries.isEmpty)
    await #expect(throws: (any Error).self) { try await library.photo(fixture.photo.reference) }
    await #expect(throws: (any Error).self) { try await library.input(fixture.input.reference) }
    #expect(!FileManager.default.fileExists(atPath: root.path))
    await library.closeLibrary()
  }
  @Test("A disposable schema-10 catalog is refused without migration or backfill")
  func refusesPriorInternalSchema() async throws {
    let root = DrawingLibraryPhotoFixture.root()
    defer { try? FileManager.default.removeItem(at: root) }
    let owner = DrawingLibrary(directoryURL: root)
    try await owner.open()
    await owner.closeLibrary()
    let catalog = root.appendingPathComponent("drawing-library.sqlite")
    do {
      let database = try DrawingLibraryDatabase(url: catalog)
      try database.execute("PRAGMA user_version=10")
    }
    let before = try Data(contentsOf: catalog)
    let reader = DrawingLibrary(directoryURL: root)
    await #expect(throws: (any Error).self) { try await reader.photos() }
    await #expect(throws: (any Error).self) { try await reader.photoMetadataRevision() }
    await #expect(throws: (any Error).self) { try await reader.open() }
    #expect(try Data(contentsOf: catalog) == before)
    await reader.closeLibrary()
  }

  @Test("Unsupported source-only index kind remains preservable without invented Photo date facts")
  func unsupportedIndexKindFacts() async throws {
    let root = DrawingLibraryPhotoFixture.root()
    defer { try? FileManager.default.removeItem(at: root) }
    let fixture = try DrawingLibraryPhotoFixture(acquired: .known(ExchangeTimestamp(wallTime: "2027-01-15T08:00:00Z"), provenance: "Known fixture claim"))
    var payload = try fixture.packagePayload()
    var index = try #require(JSONSerialization.jsonObject(with: payload["data/exchange.json"]!) as? [String: Any])
    index["kind"] = "future"
    payload["data/exchange.json"] = try DrawingLibraryPhotoFixture.json(index)
    let library = DrawingLibrary(directoryURL: root.appendingPathComponent("library"))
    try await library.publishPhotoFixture(payload)
    let entry = try #require(try await library.photos().entries.first)
    #expect(entry.reference == fixture.photo.reference)
    #expect(entry.acquired == nil && entry.imported == nil && entry.sortDate == nil)
    #expect(!entry.unsupportedReasons.isEmpty)
    await #expect(throws: (any Error).self) { try await library.photo(fixture.photo.reference) }
    #expect(try await library.asset(fixture.photo.record.original.object) == fixture.photo.assets.first { $0.descriptor.asset.object == fixture.photo.record.original.object }?.bytes)
    await library.closeLibrary()
  }

}
