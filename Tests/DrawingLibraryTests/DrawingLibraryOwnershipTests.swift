import CSQLite
import Foundation
import DrawingLibrary
import PlotterModel
import PortraitCore
import Testing

@Suite("Drawing-first one writer and mutation expectations", .serialized)
struct DrawingLibraryOwnershipTests {
  private func value() throws -> Drawing {
    let style = try StrokeStyle(nominalLineWidth: 0.8, penProfileID: PenProfileID(UUID()))
    return try Drawing(program: DrawingProgramCatalog.program(for: .line, style: style), input: .none, parent: .none,
      producer: DrawingProducerReceipt(id: "example.ownership", version: "1", recordJSON: Data("{}".utf8)))
  }
  @Test("Borrowed read owner coexists; same-owner domain and drawing writes interleave")
  func sharedOwner() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("drawing-owner-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let writer = DrawingLibrary(directoryURL: root), reader = DrawingLibrary(directoryURL: root)
    let first = try await writer.retain(value(), reason: "save")
    #expect(try await reader.drawing(first.reference).reference == first.reference)
    let record = DrawingLibraryRecord(kind: "example.interleaving/1", id: UUID(), payload: Data("{}".utf8))
    try await writer.commitRecords([record])
    try await writer.rename(first.reference, title: "Owned metadata")
    _ = try await writer.retain(value(), reason: "save")
    #expect(try await writer.records(kind: record.kind).count == 1)
    #expect(try await writer.drawings().entries.count == 2)
    await #expect(throws: (any Error).self) { try await reader.retain(value(), reason: "competing-write") }
    await reader.closeLibrary()
    try await writer.rename(first.reference, title: "Writer still owns lease")
    await writer.closeLibrary()
    let successor = DrawingLibrary(directoryURL: root)
    _ = try await successor.retain(value(), reason: "save")
    #expect(try await successor.drawings().entries.count == 3)
    await successor.closeLibrary()
  }

  @Test("Foreign SQL drift refuses before refreshing ownership or writing metadata")
  func foreignDrift() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("drawing-drift-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let library = DrawingLibrary(directoryURL: root)
    let retained = try await library.retain(value(), title: "Original", reason: "save")
    var connection: OpaquePointer?
    let status = sqlite3_open_v2(root.appendingPathComponent("drawing-library.sqlite").path,
      &connection, SQLITE_OPEN_READWRITE, nil)
    #expect(status == SQLITE_OK)
    let raw = try #require(connection)
    defer { sqlite3_close(raw) }
    #expect(sqlite3_exec(raw, "UPDATE state SET value=CAST(value AS INTEGER)+1 WHERE key='revision'", nil, nil, nil) == SQLITE_OK)
    #expect(sqlite3_changes(raw) == 1)
    await #expect(throws: (any Error).self) { try await library.rename(retained.reference, title: "Must not commit") }
    await #expect(throws: (any Error).self) {
      try await library.commitRecords([.init(kind: "example.forbidden/1", id: UUID(), payload: Data("{}".utf8))])
    }
    #expect(try await library.drawings().entries.first?.title == "Original")
    #expect(try await library.records(kind: "example.forbidden/1").isEmpty)
    await library.closeLibrary()
  }
}
