import Foundation
import DrawingLibrary
import PlotterModel
import PortraitCore
import Testing

@Suite("Drawing-first public value flow", .serialized)
struct DrawingLibraryValueFlowTests {
  private func drawing() throws -> Drawing {
    let style = try StrokeStyle(nominalLineWidth: 0.8, penProfileID: PenProfileID(UUID()))
    let program = try DrawingProgramCatalog.program(for: .line, style: style)
    let receipt = try DrawingProducerReceipt(id: "example.drawing-first", version: "1", recordJSON: Data("{}".utf8))
    return try Drawing(program: program, input: .none, parent: .none, producer: receipt)
  }
  private func root() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("drawing-first-" + UUID().uuidString)
  }
  private func objects(_ root: URL) throws -> [String: Data] {
    try Dictionary(uniqueKeysWithValues: FileManager.default.contentsOfDirectory(
      at: root.appendingPathComponent("objects/sha256"), includingPropertiesForKeys: nil)
      .map { ($0.lastPathComponent, try Data(contentsOf: $0)) })
  }

  @Test("Fresh equal geometry has distinct revisions; exact retry and rename survive offline copy")
  func identityRetryRenameCopy() async throws {
    let temporary = root(); defer { try? FileManager.default.removeItem(at: temporary) }
    let original = temporary.appendingPathComponent("original")
    let copy = temporary.appendingPathComponent("copy")
    let library = DrawingLibrary(directoryURL: original)
    #expect(try await library.drawings().entries.isEmpty)
    let value = try drawing()
    let intent = DrawingLibraryRetentionIntent()
    let first = try await library.retain(value, title: "First", reason: "explicit-save", intent: intent)
    let second = try await library.retain(value, title: "Second", reason: "explicit-save")
    #expect(first.reference != second.reference)
    let frozen = try objects(original)
    try await library.rename(first.reference, title: "Renamed")
    let retry = try await library.retain(value, title: "Stale title", reason: "explicit-save", intent: intent)
    #expect(retry.reference == first.reference && retry.wasAlreadyRetained)
    let page = try await library.drawings()
    #expect(page.entries.count == 2)
    #expect(page.entries.contains { $0.reference == first.reference && $0.title == "Renamed" })
    let loaded = try await library.drawing(first.reference)
    #expect(loaded.reference == first.reference && loaded.program == value.program)
    #expect(loaded.units.nominalPenWidthMM == nil)
    #expect(try objects(original) == frozen)
    await library.closeLibrary()
    try FileManager.default.copyItem(at: original, to: copy)
    try FileManager.default.removeItem(at: original)
    let offline = DrawingLibrary(directoryURL: copy)
    #expect(try await offline.drawing(first.reference).program == value.program)
    #expect(try objects(copy) == frozen)
    await offline.closeLibrary()
  }

  @Test("Metadata pages and title clearing do not materialize immutable artwork")
  func metadataWithoutArtwork() async throws {
    let directory = root(); defer { try? FileManager.default.removeItem(at: directory) }
    let library = DrawingLibrary(directoryURL: directory)
    let retained = try await library.retain(drawing(), title: "Title", reason: "explicit-save")
    let artwork = directory.appendingPathComponent("objects")
    let held = directory.appendingPathComponent("held-artwork")
    try FileManager.default.moveItem(at: artwork, to: held)
    #expect(try await library.drawings().entries.count == 1)
    try await library.rename(retained.reference, title: nil)
    #expect(try await library.drawings().entries.first?.title == nil)
    await #expect(throws: (any Error).self) { try await library.drawing(retained.reference) }
    try FileManager.default.moveItem(at: held, to: artwork)
    #expect(try await library.drawing(retained.reference).reference == retained.reference)
    await library.closeLibrary()
  }

  @Test("A stable retention intent refuses a different immutable request")
  func immutableRequestConflict() async throws {
    let directory = root(); defer { try? FileManager.default.removeItem(at: directory) }
    let library = DrawingLibrary(directoryURL: directory)
    let value = try drawing(), intent = DrawingLibraryRetentionIntent()
    let retained = try await library.retain(value, reason: "explicit-save", intent: intent)
    let changedReceipt = try DrawingProducerReceipt(id: "example.drawing-first", version: "1",
      recordJSON: Data("{\"different\":true}".utf8))
    let changed = try Drawing(program: value.program, input: .none, parent: .none, producer: changedReceipt)
    await #expect(throws: (any Error).self) {
      try await library.retain(changed, reason: "explicit-save", intent: intent)
    }
    #expect(try await library.drawings().entries.map(\.reference) == [retained.reference])
    await library.closeLibrary()
  }
}
