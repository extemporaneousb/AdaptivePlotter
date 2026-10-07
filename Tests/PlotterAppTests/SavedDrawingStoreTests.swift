import Foundation
import PlotterModel
import Testing

@testable import PlotterApp

@Suite("Saved drawings and bounded metadata browsing")
@MainActor
struct SavedDrawingStoreTests {
  @Test("source-free drawing saves once, reloads exactly and survives later metadata mutations")
  func sourceFreeRoundTrip() async throws {
    let directory = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let source = try portraitPersistenceCandidate()
    let program = try DrawingProgram(id: source.program.id, fieldExtent: source.program.fieldExtent,
      strokes: source.program.strokes, source: .init(kind: "authored", sourceIdentifier: "source-free-fixture"))
    let drawing = SavedDrawing(program: program)
    let writer = PortraitSketchCollection(store: .init(directoryURL: directory))
    #expect(await writer.saveDrawing(drawing) == nil)
    let firstIndex = try Data(contentsOf: directory.appendingPathComponent("index-v1.json"))
    #expect(await writer.saveDrawing(drawing) == nil)
    #expect(try Data(contentsOf: directory.appendingPathComponent("index-v1.json")) == firstIndex)
    #expect(writer.entries.isEmpty && writer.sketches.count == 1)
    #expect(writer.sketches.first?.sourceImageData == nil)
    let reader = PortraitSketchCollection(store: .init(directoryURL: directory))
    await reader.loadDrawingBrowser()
    #expect(!reader.historyLoadHasCompleted && reader.archive.entries.isEmpty && reader.archive.savedDrawings == nil)
    #expect(reader.drawingSummaries.map(\.id) == [drawing.id])
    #expect(reader.drawingSummaries.first?.programContentHash == program.contentHash.description)
    let selected = try await reader.drawingForBrowsing(drawing.id)
    #expect(selected == drawing && selected.portraitCandidate == nil)
    #expect(!reader.historyLoadHasCompleted)
    await reader.load()
    #expect(reader.sketches == [drawing])
    #expect(try PortraitCandidateStore.retainedByteCount(snapshot: reader.archive) == reader.retainedBytes)
    reader.remove(drawing.id)
    await reader.awaitPersistence()
    #expect(reader.sketches.isEmpty)
    #expect(await reader.saveDrawing(drawing) != nil)
    #expect(throws: (any Error).self) { try PortraitCandidateStore(directoryURL: directory).loadDrawing(drawing.id) }
  }

  @Test("saving an authored bordered drawing persists only original source geometry and establishes exact later run linkage")
  func authoredBorderSave() async throws {
    let pen = try portraitTestStyle()
    let program = try DrawingProgramCatalog.program(for: .square, style: pen)
    let border = LogicalStroke(id: StrokeID(UUID()), path: try Polyline<FieldSpace>(points: [
      .init(x: 0, y: 0), .init(x: 100, y: 0), .init(x: 100, y: 100), .init(x: 0, y: 100), .init(x: 0, y: 0)
    ]), style: pen, ordering: 1)
    let execution = try DrawingProgram(id: ProgramID(UUID()), fieldExtent: program.fieldExtent,
      strokes: program.strokes + [border], source: .init(kind: program.source.kind,
        sourceIdentifier: program.source.sourceIdentifier + "|draw-border-v1|artwork=\(program.contentHash)"))
    let drawing = try #require(SavedDrawing.authored(program: program, projectedDrawing: nil, executionProgram: execution))
    #expect(drawing.program == program && drawing.program != execution)
    #expect(drawing.runCandidateReference?.matches(execution) == true)
    let unrelated = try DrawingProgramCatalog.program(for: .triangle, style: pen)
    #expect(SavedDrawing.authored(program: unrelated, projectedDrawing: drawing, executionProgram: execution) == nil)
    let directory = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let model = PortraitStudioModel(candidateStore: .init(directoryURL: directory))
    #expect(await model.saveAuthoredDrawing(drawing, isStillCurrent: { true }) == nil)
    #expect(model.projectedDrawing == drawing)
    #expect(model.projectedDrawing?.executionReference(for: execution)?.sourceProgram == program)
    #expect(try PortraitCandidateStore(directoryURL: directory).loadDrawing(drawing.id).program == program)
    await model.shutdown()
  }

  @Test("compact filtered pages find old variants without opening candidate records or blobs")
  func compactFilteredPages() async throws {
    let directory = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let candidates = try (1...125).map { try portraitPersistenceCandidate(seed: UInt64($0)) }
    let archive = PortraitCandidateArchive(entries: candidates.map {
      .init(candidate: $0, reasons: [.init(reason: .shortlisted)])
    })
    let writer = PortraitCandidateStore(directoryURL: directory)
    try await writer.save(snapshot: archive)
    let reader = PortraitCandidateStore(directoryURL: directory)
    let first = try reader.loadDrawingPage(limit: 20)
    #expect(first.drawings.count == 20 && first.next != nil && first.candidateRecordsRead == 0)
    let oldest = try #require(candidates.first)
    let page = try reader.loadDrawingPage(limit: 1, photoID: oldest.photoID, style: .hatch)
    #expect(page.drawings.map(\.id) == [oldest.id] && page.next == nil && page.candidateRecordsRead == 0)
    // Advisory metadata remains available even when selected pixels are damaged.
    try FileManager.default.removeItem(at: directory.appendingPathComponent("assets").appendingPathComponent(oldest.sourceSHA256))
    #expect(try reader.loadDrawingPage(photoID: oldest.photoID).drawings.map(\.id) == [oldest.id])
    #expect(throws: (any Error).self) { try reader.loadDrawing(oldest.id) }
    let index = directory.appendingPathComponent("index-v1.json")
    let bytes = try Data(contentsOf: index)
    let loaded = await reader.load()
    #expect(!loaded.canWrite)
    await #expect(throws: (any Error).self) { try await reader.save(snapshot: loaded.archive) }
    #expect(try Data(contentsOf: index) == bytes)
  }

  @Test("v3 legacy retention browses in bounded batches and retains exact portrait record identity")
  func legacyV3Read() async throws {
    let directory = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let candidates = try (1...125).map { try portraitPersistenceCandidate(seed: UInt64($0)) }
    let candidate = try #require(candidates.first)
    try await PortraitCandidateStore(directoryURL: directory).save(snapshot: .init(entries: candidates.map {
      .init(candidate: $0, reasons: [.init(reason: .shortlisted)])
    }))
    let url = directory.appendingPathComponent("index-v1.json")
    var envelope = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    let payload = try #require(Data(base64Encoded: envelope["payload"] as? String ?? ""))
    var indexed = try #require(JSONSerialization.jsonObject(with: payload) as? [String: Any])
    let entry = try #require((indexed["entries"] as? [[String: Any]])?.first)
    let candidateHash = try #require(entry["candidateSHA256"] as? String)
    let record = directory.appendingPathComponent("records").appendingPathComponent(candidateHash)
    let originalRecord = try Data(contentsOf: record)
    indexed["schemaVersion"] = 3; indexed["savedDrawings"] = nil; indexed["drawingCatalog"] = nil
    let oldPayload = try JSONSerialization.data(withJSONObject: indexed, options: [.sortedKeys])
    envelope["schemaVersion"] = 3; envelope["payload"] = oldPayload.base64EncodedString()
    envelope["sha256"] = PortraitCandidateCoding.digest(oldPayload)
    try JSONSerialization.data(withJSONObject: envelope, options: [.sortedKeys]).write(to: url)
    let indexBytes = try Data(contentsOf: url)
    let reader = PortraitCandidateStore(directoryURL: directory)
    let page = try reader.loadDrawingPage(limit: 1)
    #expect(page.candidateRecordsRead == 1 && page.drawings.first?.isSaved == true)
    let collection = PortraitSketchCollection(store: .init(directoryURL: directory))
    await collection.loadDrawingBrowser(photoID: candidate.photoID, style: .hatch)
    #expect(collection.drawingSummaries.map(\.id) == [candidate.id])
    #expect(!collection.historyLoadHasCompleted && collection.entries.isEmpty)
    #expect(try reader.loadDrawing(candidate.id).portraitCandidate == candidate)
    #expect(try Data(contentsOf: url) == indexBytes)
    let loaded = await reader.load()
    #expect(loaded.canWrite && loaded.archive.savedDrawings?.first?.portraitCandidate == candidate)
    try await reader.save(snapshot: loaded.archive)
    #expect(try Data(contentsOf: record) == originalRecord)
    #expect(try reader.loadDrawingPage().candidateRecordsRead == 0)
  }

  @Test("Send awaits canonical Save, preserves the captured snapshot and rejects deletion while pending")
  func durableHandoffAndDeletion() async throws {
    let directory = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let candidate = try portraitPersistenceCandidate()
    let model = PortraitStudioModel(candidateStore: .init(directoryURL: directory))
    var performed = false
    let error = await model.acceptProjection(candidate) {
      let persisted = await PortraitCandidateStore(directoryURL: directory).load()
      #expect(persisted.archive.savedDrawings?.first?.id == candidate.id)
      performed = true
      return nil
    }
    #expect(error == nil && performed && model.projectedDrawing?.id == candidate.id)
    #expect(model.sketches.sketches.map(\.id) == [candidate.id])
    let deleted = await model.acceptProjection(candidate) {
      model.sketches.remove(candidate.id)
      return nil
    }
    #expect(deleted != nil)
    await model.sketches.awaitPersistence()
    #expect(model.sketches.sketches.isEmpty)
    #expect(await model.sketches.saveDrawing(SavedDrawing(candidate: candidate)) != nil)
    await model.shutdown()
  }

  @Test("failed Save prevents handoff and preserves the corrupt canonical index")
  func failedSaveBlocksHandoff() async throws {
    let directory = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let url = directory.appendingPathComponent("index-v1.json")
    let bytes = Data("corrupt retained archive".utf8)
    try bytes.write(to: url)
    let model = PortraitStudioModel(candidateStore: .init(directoryURL: directory))
    var performed = false
    let error = await model.acceptProjection(try portraitPersistenceCandidate()) { performed = true; return nil }
    #expect(error != nil && !performed && model.projectedDrawing == nil)
    #expect(try Data(contentsOf: url) == bytes)
    await model.shutdown()
  }

  @Test("cold photo and style matching loads only an exact existing result and never starts rendering or full archive recovery")
  func coldPhotoStyleMatching() async throws {
    let directory = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let original = try portraitPersistenceCandidate()
    let pen = try #require(original.program.strokes.first?.style)
    let raster = portraitTestRaster()
    let vectors = PortraitVectorOptions.nativeDefaults(for: .contours)
    let recipe = PortraitStyleRecipe(id: "existing-contour", title: "Contour", seed: 7,
      style: .contours, vectorOptions: vectors, analysisOptions: .init())
    let program = try PortraitVectorizer.program(from: raster, pose: .front,
      style: .contours, strokeStyle: pen, vectorOptions: vectors)
    let candidate = try PortraitCandidate(sourceData: original.sourceData, sourcePixelExtent: original.sourcePixelExtent,
      raster: raster, recipe: recipe, program: program, photoID: original.photoID,
      captureSessionID: original.captureSessionID)
    let flowRecipe = PortraitStyleRecipe(id: "existing-flow", title: "Flow Edge", seed: 8,
      style: .flowEdges, vectorOptions: .nativeDefaults(for: .flowEdges), analysisOptions: .init())
    let flowProgram = try PortraitVectorizer.program(from: raster, pose: .front,
      style: .flowEdges, strokeStyle: pen, vectorOptions: flowRecipe.vectorOptions)
    let flow = try PortraitCandidate(sourceData: original.sourceData, sourcePixelExtent: original.sourcePixelExtent,
      raster: raster, recipe: flowRecipe, program: flowProgram, photoID: original.photoID,
      captureSessionID: original.captureSessionID)
    try await PortraitCandidateStore(directoryURL: directory).save(snapshot: .init(entries: [candidate, flow].map {
      .init(candidate: $0, reasons: [.init(reason: .shortlisted)])
    }))
    let model = PortraitStudioModel(candidateStore: .init(directoryURL: directory))
    await model.loadPhotoBrowser()
    model.selectPhoto(original.photoID, strokeStyle: pen)
    await model.awaitRendering()
    #expect(model.completedCandidate?.id == candidate.id && !model.sketches.historyLoadHasCompleted)
    #expect(model.renderDiagnostics.startedWorkerCount == 0)
    model.selectStyle(.flowEdges, strokeStyle: pen)
    await model.awaitRendering()
    #expect(model.completedCandidate?.id == flow.id && !model.sketches.historyLoadHasCompleted)
    #expect(model.renderDiagnostics.startedWorkerCount == 0)
    await model.shutdown()
  }

  private func temporaryDirectory() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("saved-drawing-tests-\(UUID().uuidString)")
  }
}
