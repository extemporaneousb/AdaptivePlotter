import DrawingLibrary
import Foundation
import PlotterModel
import PortraitCore
import PortraitStudioUI
import Testing

private actor DrawingReadGate {
  private var entered = false
  private var observer: CheckedContinuation<Void, Never>?
  private var pending: CheckedContinuation<Void, Never>?
  func pause() async {
    entered = true; observer?.resume(); observer = nil
    await withCheckedContinuation { pending = $0 }
  }
  func waitUntilEntered() async {
    if entered { return }
    await withCheckedContinuation { observer = $0 }
  }
  func release() { pending?.resume(); pending = nil }
}

@Suite("Exact drawing projection arbitration", .serialized)
@MainActor
struct DrawingProjectionRaceTests {
  private func pair(_ library: DrawingLibrary) async throws -> (Drawing, Drawing) {
    try await library.open()
    let style = try StrokeStyle(nominalLineWidth: 0.8, penProfileID: PenProfileID(UUID()))
    let program = try DrawingProgramCatalog.program(for: .line, style: style)
    let value = try Drawing(program: program, input: .none, parent: .none,
      producer: DrawingProducerReceipt(id: "example.projection-race", version: "1", recordJSON: Data("{}".utf8)))
    let first = try await library.retain(value, reason: "explicit-save")
    let second = try await library.retain(value, reason: "explicit-save")
    return try await (library.drawing(first.reference), library.drawing(second.reference))
  }

  private func unsupportedExchange(program: DrawingProgram, at bag: URL) throws -> DrawingRef {
    let value = try Drawing(program: program, input: .none, parent: .none,
      producer: DrawingProducerReceipt(id: "example.projection-feature", version: "1", recordJSON: Data("{}".utf8)))
    let frozen = try DrawingExchangeCodec.freeze(value, identity: .init(issuer: UUID()), createdAt: Date())
    var record = try #require(JSONSerialization.jsonObject(with: frozen.originalJSON) as? [String: Any])
    record["requiredFeatures"] = ["example.unsupported-plot/1"]
    let bytes = try JSONSerialization.data(withJSONObject: record, options: [.sortedKeys, .withoutEscapingSlashes])
    let reference = DrawingRef(issuer: frozen.reference.issuer, revision: frozen.reference.revision, digest: .hash(bytes))
    let programAsset = try ExchangeAsset(bytes: frozen.originalProgramJSON, mediaType: "application/json", encoding: DrawingExchangeCodec.strokeProfile)
    let receiptAsset = try ExchangeAsset(bytes: value.producer.originalJSON, mediaType: "application/json", encoding: "utf8-json")
    let encoder = DrawingArtifactCoding.encoder()
    let index: [String: Any] = ["profile": "adaptiveplotter.exchange/1", "requiredFeatures": [String](),
      "kind": "drawing", "roots": try JSONSerialization.jsonObject(with: encoder.encode([reference])),
      "includedAsOf": ISO8601DateFormatter().string(from: Date()),
      "assets": try JSONSerialization.jsonObject(with: encoder.encode([ExchangeAssetDescriptor(asset: programAsset), ExchangeAssetDescriptor(asset: receiptAsset)])),
      "attempts": [String](), "assessments": [String]()]
    let files: [String: Data] = ["data/exchange.json": try JSONSerialization.data(withJSONObject: index, options: [.sortedKeys, .withoutEscapingSlashes]),
      "data/drawings/" + reference.issuer.uuidString.lowercased() + "/" + reference.revision.uuidString.lowercased() + "/drawing.json": bytes,
      "data/objects/sha256/" + programAsset.object.description: frozen.originalProgramJSON,
      "data/objects/sha256/" + receiptAsset.object.description: value.producer.originalJSON]
    for (path, bytes) in files {
      let url = bag.appendingPathComponent(path)
      try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
      try bytes.write(to: url)
    }
    let bagit = Data("BagIt-Version: 1.0\nTag-File-Character-Encoding: UTF-8\n".utf8)
    let manifest = Data(files.keys.sorted().map { DrawingArtifactCoding.sha256(files[$0]!) + "  " + $0 + "\n" }.joined().utf8)
    try bagit.write(to: bag.appendingPathComponent("bagit.txt"))
    try manifest.write(to: bag.appendingPathComponent("manifest-sha256.txt"))
    try Data((DrawingArtifactCoding.sha256(bagit) + "  bagit.txt\n" + DrawingArtifactCoding.sha256(manifest) + "  manifest-sha256.txt\n").utf8)
      .write(to: bag.appendingPathComponent("tagmanifest-sha256.txt"))
    return reference
  }

  @Test("Unsupported per-record plot requirements remain inspectable but cannot replace projected selection")
  func unsupportedPlotCannotPublish() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("drawing-unsupported-projection-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let library = DrawingLibrary(directoryURL: root.appendingPathComponent("library"))
    let (prior, _) = try await pair(library)
    let model = PortraitStudioModel(library: library)
    try await model.projectDrawing(prior)
    let bag = root.appendingPathComponent("unsupported-exchange")
    let reference = try unsupportedExchange(program: prior.program, at: bag)
    #expect(try await library.importDrawings(from: bag) == [reference])
    let exact = try await library.drawing(reference)
    #expect(exact.program == prior.program && exact.capabilities.supported.isEmpty)
    #expect(try await library.drawings().entries.contains { $0.reference == reference })
    await #expect(throws: DrawingExchangeError.unsupportedFeature("example.unsupported-plot/1")) {
      try await model.projectDrawing(exact)
    }
    #expect(model.currentDrawing?.reference == prior.reference)
    #expect(model.projectedDrawing?.reference == prior.reference)
    #expect(model.sketches.selected?.reference == prior.reference)
    var callbackWasInvoked = false
    let refusal = await model.acceptDrawingProjection(exact) { callbackWasInvoked = true }
    #expect(refusal != nil && !callbackWasInvoked)
    #expect(model.currentDrawing?.reference == prior.reference)
    #expect(model.projectedDrawing?.reference == prior.reference)
    #expect(model.sketches.selected?.reference == prior.reference)
    try await library.exportDrawing(reference, to: root.appendingPathComponent("preserved.zip"))
    #expect(try await library.drawing(reference).requiredFeatures == ["example.unsupported-plot/1"])
    await model.shutdown(); await library.closeLibrary()
  }

  @Test("An older delayed read cannot overwrite a newer equal-geometry exact ref")
  func newerSelectionWins() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("drawing-projection-race-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let library = DrawingLibrary(directoryURL: root)
    let (first, second) = try await pair(library)
    #expect(first.program == second.program && first.reference != second.reference)
    let gate = DrawingReadGate()
    let model = PortraitStudioModel(library: library, drawingLoader: { ref in
      if ref == first.reference { await gate.pause() }
      return try await library.drawing(ref)
    })
    let older = Task { try await model.projectDrawing(first) }
    await gate.waitUntilEntered()
    try await model.projectDrawing(second)
    await gate.release()
    await #expect(throws: CancellationError.self) { try await older.value }
    #expect(model.projectedDrawing?.reference == second.reference)
    #expect(model.currentDrawing?.reference == second.reference)
    #expect(model.sketches.selected?.reference == second.reference)
    await model.shutdown(); await library.closeLibrary()
  }

  @Test("Save, explicit clear and a loaded collection selection invalidate an older projection read")
  func otherSelectionPublicationsWin() async throws {
    for mode in ["save", "clear", "collection"] {
      let root = FileManager.default.temporaryDirectory.appendingPathComponent("drawing-selection-race-" + UUID().uuidString)
      defer { try? FileManager.default.removeItem(at: root) }
      let library = DrawingLibrary(directoryURL: root)
      let (first, second) = try await pair(library), gate = DrawingReadGate()
      let model = PortraitStudioModel(library: library, drawingLoader: { ref in
        if ref == first.reference { await gate.pause() }
        return try await library.drawing(ref)
      })
      let old = Task { try await model.projectDrawing(first) }
      await gate.waitUntilEntered()
      switch mode {
      case "save": _ = try await model.saveAuthoredDrawing(second, isStillCurrent: { true })
      case "clear": model.clearDrawingSelection()
      default: try model.sketches.selectLoaded(second)
      }
      await gate.release()
      await #expect(throws: CancellationError.self) { try await old.value }
      #expect(model.currentDrawing?.reference != first.reference)
      #expect(model.projectedDrawing?.reference != first.reference)
      if mode != "clear" { #expect(model.sketches.selected?.reference == second.reference) }
      await model.shutdown(); await library.closeLibrary()
    }
  }

  @Test("Cancellation, shutdown and a changed caller predicate cannot publish a delayed selection")
  func invalidatedReadCannotPublish() async throws {
    for mode in ["cancel", "shutdown", "caller"] {
      let root = FileManager.default.temporaryDirectory.appendingPathComponent("drawing-projection-invalid-" + UUID().uuidString)
      defer { try? FileManager.default.removeItem(at: root) }
      let library = DrawingLibrary(directoryURL: root)
      let (first, _) = try await pair(library)
      let gate = DrawingReadGate()
      let model = PortraitStudioModel(library: library, drawingLoader: { ref in
        await gate.pause()
        return try await library.drawing(ref)
      })
      var callerIsCurrent = true
      let delayed = Task { try await model.projectDrawing(first, isStillCurrent: { callerIsCurrent }) }
      await gate.waitUntilEntered()
      switch mode {
      case "cancel": delayed.cancel()
      case "shutdown": await model.shutdown()
      default: callerIsCurrent = false
      }
      await gate.release()
      await #expect(throws: CancellationError.self) { try await delayed.value }
      #expect(model.projectedDrawing == nil && model.currentDrawing == nil && model.sketches.selected == nil)
      await model.shutdown(); await library.closeLibrary()
    }
  }
}
