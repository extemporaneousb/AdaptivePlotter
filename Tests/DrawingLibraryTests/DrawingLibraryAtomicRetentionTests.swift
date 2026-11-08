import Foundation
import DrawingLibrary
import PlotterModel
import PortraitCore
import Testing

private enum InjectedPublicationFailure: Error { case boundary }
private extension DrawingLibrary {
  func failAt(_ boundary: LibraryExchangeCatalogBoundary?) throws {
    guard let expected = boundary else {
      cachedExchangeCatalog?.injectFault = nil
      return
    }
    let catalog = try commonCatalog()
    catalog.injectFault = { actual in
      if actual == expected { throw InjectedPublicationFailure.boundary }
    }
  }
  func committedDrawingCount() throws -> Int {
    guard let db = try commonReadDatabase(), try tableExists("dx_record", in: db) else { return 0 }
    return Int(try db.scalar("SELECT COUNT(*) FROM dx_record WHERE kind='drawing'") ?? "0") ?? 0
  }
}

@Suite("Drawing-first atomic selected paths", .serialized)
struct DrawingLibraryAtomicRetentionTests {
  private func value() throws -> Drawing {
    let style = try StrokeStyle(nominalLineWidth: 0.8, penProfileID: PenProfileID(UUID()))
    let line = try DrawingProgramCatalog.program(for: .line, style: style)
    let second = LogicalStroke(id: StrokeID(UUID()), path: line.strokes[0].path, style: style, ordering: 1)
    let program = try DrawingProgram(id: ProgramID(UUID()), fieldExtent: line.fieldExtent,
      strokes: [line.strokes[0], second], source: line.source)
    return try Drawing(program: program, input: .none, parent: .none,
      producer: DrawingProducerReceipt(id: "example.atomic", version: "1", recordJSON: Data("{}".utf8)))
  }
  @Test("Pure preparation writes no active library; parent and child publish together or neither")
  func atomicParentChild() async throws {
    for boundary in [LibraryExchangeCatalogBoundary.beforeSQLPublication, .afterSQLCommit] {
      let root = FileManager.default.temporaryDirectory.appendingPathComponent("drawing-atomic-" + UUID().uuidString)
      defer { try? FileManager.default.removeItem(at: root) }
      let library = DrawingLibrary(directoryURL: root)
      let parentValue = try value()
      let parent = try await library.prepareRetention(parentValue, reason: "committed-prune-parent")
      let childValue = try parent.drawing.applying(.remove([parentValue.program.strokes[0].id]),
        to: parent.reference, programID: ProgramID(UUID()))
      let child = try await library.prepareRetention(childValue, reason: "committed-prune")
      #expect(!FileManager.default.fileExists(atPath: root.path))
      try await library.failAt(boundary)
      await #expect(throws: InjectedPublicationFailure.self) {
        try await library.commitRetentions([parent, child])
      }
      // This independent readonly query must observe only committed SQL, not
      // clear the injector by entering the recovering writer accessor.
      #expect(try await library.committedDrawingCount() == (boundary == .beforeSQLPublication ? 0 : 2))
      try await library.failAt(nil)
      try await library.recover()
      #expect(Set(try await library.drawings().entries.map(\.reference)) == Set([parent.reference, child.reference]))
      let committed = try await library.commitRetentions([parent, child])
      #expect(Set(committed.map(\.reference)) == Set([parent.reference, child.reference]))
      #expect(try await library.committedDrawingCount() == 2)
      await library.closeLibrary()
      let reopened = DrawingLibrary(directoryURL: root)
      #expect(try await reopened.drawings().entries.count == 2)
      #expect(try await reopened.drawing(child.reference).parent == .present(parent.reference))
      #expect(try await reopened.drawing(parent.reference).program == parentValue.program)
      await reopened.closeLibrary()
    }
  }
  @Test("A multi-root current-format import publishes every root atomically")
  func importAllRoots() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("drawing-import-atomic-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let source = DrawingLibrary(directoryURL: root.appendingPathComponent("source"))
    let parent = try await source.prepareRetention(value(), reason: "save")
    let childValue = try parent.drawing.applying(.remove([parent.drawing.program.strokes[0].id]),
      to: parent.reference, programID: ProgramID(UUID()))
    let child = try await source.prepareRetention(childValue, reason: "committed-prune")
    _ = try await source.commitRetentions([parent, child])
    let package = root.appendingPathComponent("selected.zip")
    try await source.exportDrawing(child.reference, to: package)
    await source.closeLibrary()
    let multiRoot = root.appendingPathComponent("multi-root")
    try Self.multiRootPackage(package, roots: [parent.reference, child.reference], destination: multiRoot)
    let targetRoot = root.appendingPathComponent("target")
    let target = DrawingLibrary(directoryURL: targetRoot)
    try await target.failAt(.beforeSQLCommit)
    await #expect(throws: InjectedPublicationFailure.self) {
      try await target.importDrawings(from: multiRoot)
    }
    #expect(try await target.committedDrawingCount() == 0)
    try await target.failAt(nil)
    try await target.recover()
    #expect(try await target.committedDrawingCount() == 2)
    let imported = try await target.importDrawings(from: multiRoot)
    #expect(Set(imported) == Set([parent.reference, child.reference]))
    #expect(try await target.drawings().entries.count == 2)
    await target.closeLibrary()
    let reopened = DrawingLibrary(directoryURL: targetRoot)
    #expect(try await reopened.drawing(child.reference).parent == .present(parent.reference))
    #expect(try await reopened.drawing(parent.reference).program == parent.drawing.program)
    await reopened.closeLibrary()
  }

  static func multiRootPackage(_ zip: URL, roots: [DrawingRef], destination: URL) throws {
    let staging = destination.deletingLastPathComponent().appendingPathComponent("stage-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: staging) }
    let selected = try DrawingExchangeCarrier.stageZIP(zip, stagingParent: staging)
    var files: [String: Data] = [:]
    for entry in selected.files.entries.values { files[entry.path] = try selected.files.record(at: entry.path) }
    guard var index = try JSONSerialization.jsonObject(with: selected.indexJSON) as? [String: Any] else { throw DrawingExchangeError.malformed("Fixture index") }
    index["roots"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(roots))
    files["data/exchange.json"] = try JSONSerialization.data(withJSONObject: index, options: [.sortedKeys])
    files["manifest-sha256.txt"] = Data(files.keys.filter { $0.hasPrefix("data/") }.sorted().map {
      ExchangeDigest.hash(files[$0]!).description + "  " + $0 + "\n"
    }.joined().utf8)
    files["tagmanifest-sha256.txt"] = Data(files.keys.filter {
      !$0.hasPrefix("data/") && $0 != "tagmanifest-sha256.txt"
    }.sorted().map { ExchangeDigest.hash(files[$0]!).description + "  " + $0 + "\n" }.joined().utf8)
    for (path, bytes) in files {
      let file = destination.appendingPathComponent(path)
      try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
      try bytes.write(to: file)
    }
  }

}
