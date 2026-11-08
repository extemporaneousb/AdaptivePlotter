import Foundation
import DrawingLibrary
import PortraitCore
import Testing

@Suite("Exact Library navigation", .serialized)
struct DrawingLibraryNavigationTests {
  @Test("Photo and Input scopes keep exact occurrences, cursor scope and tombstones")
  func relationships() async throws {
    let root = DrawingLibraryPhotoFixture.root()
    defer { try? FileManager.default.removeItem(at: root) }
    let library = DrawingLibrary(directoryURL: root)
    let a = try DrawingLibraryPhotoFixture(), b = try DrawingLibraryPhotoFixture()
    try await a.publish(to: library); try await b.publish(to: library)
    let first = try await library.retain(a.drawing(), reason: "navigation")
    let second = try await library.retain(a.drawing(), reason: "navigation")
    let unrelated = try await library.retain(b.drawing(), reason: "navigation")
    let aRef = first.reference, secondRef = second.reference
    let page = try await library.drawings(in: .photo(a.photo.reference), limit: 1)
    let cursor = try #require(page.next)
    let next = try await library.drawings(in: .photo(a.photo.reference), limit: 1, after: cursor)
    #expect(Set((page.entries + next.entries).map(\.reference)) == Set([aRef, secondRef]))
    await #expect(throws: (any Error).self) { try await library.drawings(in: .input(a.input.reference), after: cursor) }
    #expect(try await library.drawings(in: .input(b.input.reference)).entries.map(\.reference) == [unrelated.reference])
    try await library.delete(aRef)
    #expect(try await library.drawings(in: .photo(a.photo.reference)).entries.map(\.reference) == [secondRef])
    await #expect(throws: (any Error).self) { try await library.drawings(in: .photo(a.photo.reference), after: cursor) }
    await library.closeLibrary()
  }

  @Test("Direct parent branches and scoped binding pages stay metadata-only")
  func parentAndNavigationRows() async throws {
    let root = DrawingLibraryPhotoFixture.root()
    defer { try? FileManager.default.removeItem(at: root) }
    let library = DrawingLibrary(directoryURL: root)
    let frozen = try DrawingLibraryResultFixture.drawing()
    let parentValue = try Drawing(program: frozen.drawing.program, input: .none, parent: .none, producer: frozen.drawing.producer)
    let parent = try await library.retain(parentValue, reason: "parent")
    let childValue = try Drawing(program: frozen.drawing.program, input: .none,
      parent: .present(parent.reference), producer: frozen.drawing.producer)
    let child = try await library.retain(childValue, reason: "child")
    #expect(try await library.drawings(in: .children(parent.reference)).entries.map(\.reference) == [child.reference])
    let kind = "example.dx10-navigation/1"
    let records = (0..<3).map { _ in DrawingLibraryRecord(kind: kind, id: UUID(), payload: Data("{}".utf8), drawings: [parent.reference]) }
    try await library.commitRecords(records)
    let objects = root.appendingPathComponent("objects"), held = root.appendingPathComponent("held")
    try FileManager.default.moveItem(at: objects, to: held)
    let first = try await library.records(kind: kind, for: parent.reference, limit: 1)
    let cursor = try #require(first.next)
    #expect(first.entries.count == 1)
    await #expect(throws: (any Error).self) { try await library.records(kind: kind, for: child.reference, after: cursor) }
    #expect(try await library.drawings(in: .children(parent.reference)).entries.count == 1)
    #expect(try await library.records(kind: kind, for: child.reference).entries.isEmpty)
    try FileManager.default.moveItem(at: held, to: objects)
    try await library.rename(parent.reference, title: "new title")
    await #expect(throws: (any Error).self) { try await library.records(kind: kind, for: parent.reference, after: cursor) }
    let oversized = DrawingLibraryRecord(kind: "example.large/1", id: UUID(), payload: try JSONEncoder().encode(["profile": "example.large-navigation/1", "padding": String(repeating: "x", count: 70_000)]), drawings: [parent.reference])
    try await library.commitRecords([oversized])
    await #expect(throws: (any Error).self) { try await library.records(kind: oversized.kind, for: parent.reference) }
    await library.closeLibrary()
  }

  @Test("Attempt pages use each snapshot target and count an archive/run once without object reads")
  func attemptTargets() async throws {
    let root = DrawingLibraryPhotoFixture.root()
    defer { try? FileManager.default.removeItem(at: root) }
    let library = DrawingLibrary(directoryURL: root.appendingPathComponent("library"))
    var fixture = try DrawingLibraryResultFixture(count: 3)
    let other = try DrawingLibraryResultFixture.drawing()
    let otherFixture = try DrawingLibraryResultFixture(drawing: other, count: 0, refused: true)
    fixture.payload.merge(otherFixture.payload) { existing, _ in existing }
    fixture.index["roots"] = try DrawingLibraryResultFixture.wire([fixture.frozen.reference, other.reference])
    // Extra declared root has no attempt. Its typed Drawing closure is present.
    let old = try #require(fixture.index["assets"] as? [[String: Any]])
    let extra = try #require(otherFixture.index["assets"] as? [[String: Any]])
    var descriptors: [String: [String: Any]] = [:]
    for descriptor in old + extra {
      let digest = try #require(descriptor["object"] as? String)
      descriptors[digest] = descriptor
    }
    fixture.index["assets"] = Array(descriptors.values)
    // The extra refused receipt is not part of the declared result: remove it.
    for path in otherFixture.payload.keys where path.hasPrefix("data/jobs/") { fixture.payload.removeValue(forKey: path) }
    let source = root.appendingPathComponent("source")
    try fixture.write(to: source)
    _ = try await library.mountResult(from: source)
    let page = try await library.attempts(for: fixture.frozen.reference)
    #expect(page.entries.count == 1 && page.entries.first?.snapshot == fixture.snapshots.last)
    #expect(page.entries.first?.environment == "simulation")
    #expect(try await library.attempts(for: other.reference).entries.isEmpty)
    let objects = library.directoryURL.appendingPathComponent("objects")
    let held = library.directoryURL.appendingPathComponent("held")
    try FileManager.default.moveItem(at: objects, to: held)
    defer { try? FileManager.default.moveItem(at: held, to: objects) }
    #expect(try await library.attempts(for: fixture.frozen.reference).entries.count == 1)
    await library.closeLibrary()
  }
}
