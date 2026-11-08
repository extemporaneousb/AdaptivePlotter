import DrawingLibrary
import Foundation
import PlotterModel
import PortraitCore

@main struct PublicClient {
  static func main() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("drawing-first-client-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let library = DrawingLibrary(directoryURL: root.appendingPathComponent("active"))
    let style = try StrokeStyle(nominalLineWidth: 0.8, penProfileID: PenProfileID(UUID()))
    let program = try DrawingProgramCatalog.program(for: .line, style: style)
    let receipt = try DrawingProducerReceipt(id: "example.public-client", version: "1", recordJSON: Data("{}".utf8))
    let value = try Drawing(program: program, input: .none, parent: .none, producer: receipt)
    let intent = DrawingLibraryRetentionIntent()
    let first = try await library.retain(value, title: "First", reason: "explicit-save", intent: intent)
    let second = try await library.retain(value, reason: "explicit-save")
    guard first.reference != second.reference else { throw ClientFailure.identity }
    try await library.rename(first.reference, title: "Renamed")
    let retry = try await library.retain(value, reason: "explicit-save", intent: intent)
    guard retry.reference == first.reference, retry.wasAlreadyRetained else { throw ClientFailure.retry }
    let page = try await library.drawings()
    guard page.entries.count == 2, page.entries.contains(where: {
      $0.reference == first.reference && $0.title == "Renamed"
    }) else { throw ClientFailure.page }
    let loaded = try await library.drawing(first.reference)
    guard loaded.program == program, loaded.units.nominalPenWidthMM == nil else { throw ClientFailure.value }
    try await verifyExtended(library: library, root: root, base: value)
    await library.closeLibrary()
    let copiedRoot = root.appendingPathComponent("offline")
    try FileManager.default.copyItem(at: root.appendingPathComponent("active"), to: copiedRoot)
    try FileManager.default.removeItem(at: root.appendingPathComponent("active"))
    let copied = DrawingLibrary(directoryURL: copiedRoot)
    guard try await copied.drawing(first.reference).program == program else { throw ClientFailure.copy }
    await copied.closeLibrary()
    print("PASS public concrete DrawingLibrary retain/page/load/rename/unknown-width/retry/offline-copy")
  }
  static func verifyExtended(library: DrawingLibrary, root: URL, base: Drawing) async throws {
    // Retry binds immutable payload, while mutable title remains outside it.
    let intent = DrawingLibraryRetentionIntent()
    _ = try await library.retain(base, reason: "save", intent: intent)
    let otherReceipt = try DrawingProducerReceipt(id: "example.public-client", version: "1", recordJSON: Data("{\"changed\":true}".utf8))
    let changed = try Drawing(program: base.program, input: .none, parent: .none, producer: otherReceipt)
    do { _ = try await library.retain(changed, reason: "save", intent: intent); throw ClientFailure.conflict }
    catch is DrawingLibraryError { }

    let key = UUID(), recordIntent = DrawingLibraryCommitIntent()
    let old = DrawingLibraryRecord(kind: "example.feedback/1", id: key, payload: Data("{\"rank\":1}".utf8))
    let updated = DrawingLibraryRecord(kind: old.kind, id: key, payload: Data("{\"rank\":2}".utf8))
    try await library.commitRecords([old], intent: recordIntent)
    try await library.commitRecords([updated])
    try await library.commitRecords([old], intent: recordIntent)
    guard try await library.records(kind: old.kind).first?.payload == updated.payload else { throw ClientFailure.records }
    let independent = DrawingLibraryRecord(kind: old.kind, id: UUID(), payload: Data("{}".utf8))
    try await library.commitRecords([independent])
    guard try await library.records(kind: old.kind).count == 2 else { throw ClientFailure.records }

    let firstStroke = base.program.strokes[0]
    let secondStroke = LogicalStroke(id: StrokeID(UUID()), path: firstStroke.path, style: firstStroke.style, ordering: 1)
    let two = try DrawingProgram(id: ProgramID(UUID()), fieldExtent: base.program.fieldExtent,
      strokes: [firstStroke, secondStroke], source: base.program.source)
    let parentValue = try Drawing(program: two, input: .none, parent: .none, producer: base.producer)
    let parent = try await library.prepareRetention(parentValue, reason: "committed-prune-parent")
    let childValue = try parent.drawing.applying(.remove([firstStroke.id]), to: parent.reference, programID: ProgramID(UUID()))
    let child = try await library.prepareRetention(childValue, reason: "committed-prune")
    let batch = try await library.commitRetentions([parent, child])
    guard batch.map(\.reference) == [parent.reference, child.reference] else { throw ClientFailure.parents }
    let loadedChild = try await library.drawing(child.reference)
    guard loadedChild.parent == .present(parent.reference), loadedChild.program.strokes.map(\.id) == [secondStroke.id] else { throw ClientFailure.parents }
    let exchange = root.appendingPathComponent("parent-child.zip")
    try await library.exportDrawing(child.reference, to: exchange)
    let imported = DrawingLibrary(directoryURL: root.appendingPathComponent("imported"))
    let importedRefs = try await imported.importDrawings(from: exchange)
    guard importedRefs == [child.reference],
      try await imported.drawing(parent.reference).program == parent.drawing.program,
      try await imported.drawing(child.reference).program == loadedChild.program else { throw ClientFailure.parents }
    await imported.closeLibrary()
    let multi = root.appendingPathComponent("multi-root")
    try multiRootPackage(exchange, roots: [parent.reference, child.reference], destination: multi)
    let multiStore = DrawingLibrary(directoryURL: root.appendingPathComponent("multi-imported"))
    guard Set(try await multiStore.importDrawings(from: multi)) == Set([parent.reference, child.reference]) else { throw ClientFailure.parents }
    await multiStore.closeLibrary()

    let pixels = try DrawingImageAsset.gray8(Data([0,85,170,255]), width: 2, height: 2)
    let photo = try DrawingImageRecords.photo(identity: .init(issuer: UUID()), original: pixels,
      width: 2, height: 2, acquired: .unknown(provenance: "Synthetic fixture; no camera capture"),
      imported: .known(try ExchangeTimestamp(wallTime: "2026-11-07T00:00:00Z"), provenance: "Synthetic fixture"))
    let preparation = try DrawingProducerReceipt(id: "example.identity-preparation", version: "1", recordJSON: Data("{}".utf8))
    let input = try DrawingImageRecords.input(identity: .init(issuer: UUID()), photo: photo, raster: pixels,
      width: 2, height: 2, orientation: "up", sourceToInput: ExchangeTransform([1,0,0,0,1,0,0,0,1]),
      inputToField: ExchangeTransform([50,0,0,0,-50,100,0,0,1]), mask: .none,
      operations: [DrawingImageOperation(kind: "identity", parametersJSON: Data("{}".utf8))], preparation: preparation)
    let photoDrawing = try Drawing(program: base.program, input: .present(input.reference), parent: .none, producer: base.producer)
    let photoRetained = try await library.retain(photoDrawing, reason: "explicit-save", closure: .init(input: input))
    guard try await library.drawing(photoRetained.reference).input == .present(input.reference) else { throw ClientFailure.photo }
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
  enum ClientFailure: Error { case identity, retry, page, value, copy, conflict, records, parents, photo }
}
