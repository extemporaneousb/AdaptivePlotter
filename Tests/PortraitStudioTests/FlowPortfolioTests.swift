import Foundation
import DrawingLibrary
import PlotterModel
import PortraitArtists
import PortraitCore
@testable import PortraitLibrary
import Testing

@Suite("Current Drawing authoring graph", .serialized)
struct FlowPortfolioTests {
  @Test("Equal generated geometry stays temporary; choice and edits retain exact refs and survive copied Library reopen")
  func portableRound() async throws {
    let root = temporary(), moved = temporary(), receiver = temporary(), zip = temporary().appendingPathExtension("zip")
    defer { for url in [root, moved, receiver, zip] { try? FileManager.default.removeItem(at: url) } }
    let store = try await StudioDrawingFixture.store(directory: root, purpose: .validationFixture)
    let source = try await store.addSource(data: Self.photo, title: "Synthetic source")
    let round = try await store.beginRound(sourceID: source.id, recipes: [.standard, .standard])
    let program = try Self.program(), production = try StudioDrawingFixture.production(program: program, raster: Self.raster)
    let preview = try PortraitDrawingPreview.png(program)
    let a = try await store.completeCandidate(roundID: round.id, slot: 0, production: production, previewPNG: preview)
    let b = try await store.completeCandidate(roundID: round.id, slot: 1, production: production, previewPNG: preview)
    try await store.finishRound(round.id)
    #expect(a.id != b.id)
    #expect(try await store.storage.library.drawings().entries.isEmpty)
    try await store.chooseCandidate(a.id)
    let base = try await store.retainedDrawing(candidateID: a.id)
    let edit = try await store.applyPrune(candidateID: a.id, action: .remove, indices: [0])
    let child = try await store.retainedDrawing(candidateID: a.id, revisionID: edit.id)
    #expect(child.reference != base.reference)
    #expect(child.parent == .present(try #require(base.reference)))
    #expect(child.program.strokes == Array(program.strokes.dropFirst()))
    let shown = try await store.presentRoundRanking(round.id, seed: 7)
    _ = try await store.recordRanking(presentationID: shown.id, orderedGroups: [shown.items.map(\.id)])
    let expected = await store.snapshot()
    let rankedPreview = try await store.presentationPreview(try #require(shown.items.first { $0.candidateID == b.id }))
    try await store.exportDrawing(child, to: zip)
    await store.closeLibrary()
    try FileManager.default.copyItem(at: root, to: moved)
    let reopened = try await StudioDrawingFixture.store(directory: moved)
    #expect(await reopened.snapshot() == expected)
    #expect(try await reopened.sourceData(source.id) == Self.photo)
    #expect(try await reopened.retainedDrawing(candidateID: a.id, revisionID: edit.id).reference == child.reference)
    await #expect(throws: FlowPortfolioError.self) { try await reopened.candidateProgram(b.id) }
    #expect(try await reopened.presentationPreview(try #require(shown.items.first { $0.candidateID == b.id })) == rankedPreview)
    let target = DrawingLibrary(directoryURL: receiver); try await target.open()
    #expect(try await target.importDrawings(from: zip).contains(try #require(child.reference)))
    #expect(try await target.drawing(try #require(child.reference)).program.strokes == child.program.strokes)
    await target.closeLibrary(); await reopened.closeLibrary()
  }

  @Test("Human remove restore undo and redo preserve stable root strokes and completed supervision")
  func exactPruning() async throws {
    let root = temporary(); defer { try? FileManager.default.removeItem(at: root) }
    let store = try await StudioDrawingFixture.store(directory: root)
    let source = try await store.addSource(data: Self.photo, title: "Fixture")
    let round = try await store.beginRound(sourceID: source.id, recipes: [.standard])
    let program = try Self.program()
    let candidate = try await store.completeCandidate(roundID: round.id, slot: 0,
      production: StudioDrawingFixture.production(program: program, raster: Self.raster), previewPNG: PortraitDrawingPreview.png(program))
    try await store.finishRound(round.id)
    _ = try await store.applyPrune(candidateID: candidate.id, action: .remove, indices: [0, 2])
    _ = try await store.applyPrune(candidateID: candidate.id, action: .restore, indices: [0])
    #expect(await store.snapshot().latestPrune(candidateID: candidate.id)?.removedIndices == [2])
    _ = try await store.applyPrune(candidateID: candidate.id, action: .undo)
    #expect(await store.snapshot().latestPrune(candidateID: candidate.id)?.removedIndices == [0, 2])
    _ = try await store.applyPrune(candidateID: candidate.id, action: .redo)
    let target = try await store.applyPrune(candidateID: candidate.id, action: .completeTarget)
    let drawing = try await store.retainedDrawing(candidateID: candidate.id, revisionID: target.id)
    #expect(drawing.program.strokes == program.strokes.enumerated().filter { $0.offset != 2 }.map(\.element))
    #expect(try await store.candidateProgram(candidate.id) == program)
    _ = try await store.applyPrune(candidateID: candidate.id, action: .remove, indices: [0, 1, 3])
    let empty = try #require(await store.snapshot().latestPrune(candidateID: candidate.id))
    await #expect(throws: DrawingExchangeError.allStrokesRemoved) { try await store.retainedDrawing(candidateID: candidate.id, revisionID: empty.id) }
    await store.closeLibrary()
  }
  @Test("Repeated exact choices coalesce and unchanged targets reuse refs while changed offered masks remain new feedback")
  func retainedSelectionRequests() async throws {
    let root = temporary(); defer { try? FileManager.default.removeItem(at: root) }
    let store = try await StudioDrawingFixture.store(directory: root)
    let source = try await store.addSource(data: Self.photo, title: "Fixture")
    let round = try await store.beginRound(sourceID: source.id, recipes: [.standard, .standard])
    let program = try Self.program(), production = try StudioDrawingFixture.production(program: program, raster: Self.raster)
    let preview = try PortraitDrawingPreview.png(program)
    let a = try await store.completeCandidate(roundID: round.id, slot: 0, production: production, previewPNG: preview)
    let b = try await store.completeCandidate(roundID: round.id, slot: 1, production: production, previewPNG: preview)
    try await store.finishRound(round.id)
    try await store.chooseCandidate(a.id)
    let original = try await store.retainedDrawing(candidateID: a.id), revision = await store.snapshot().revision
    try await store.chooseCandidate(a.id)
    let repeated = await store.snapshot()
    #expect(repeated.choices.count == 1 && repeated.revision == revision)
    #expect(try await store.retainedDrawing(candidateID: a.id).reference == original.reference)
    _ = try await store.applyPrune(candidateID: b.id, action: .remove, indices: [0])
    try await store.chooseCandidate(a.id)
    #expect(await store.snapshot().choices.count == 2)
    #expect(try await store.retainedDrawing(candidateID: a.id).reference == original.reference)
    let count = try await store.storage.library.drawings().entries.count
    let target = try await store.applyPrune(candidateID: a.id, action: .completeTarget)
    #expect(try await store.retainedDrawing(candidateID: a.id, revisionID: target.id).reference == original.reference)
    #expect(try await store.storage.library.drawings().entries.count == count)
    await store.closeLibrary()
  }

  private func temporary() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent("drawing-flow-" + UUID().uuidString) }
  static var photo: Data { FlowDojoFixture.image(1) }
  static let raster = PortraitRaster(width: 2, height: 2, luminance: [0,1,1,0], provenance: "synthetic-fixture", analysisSummary: "Synthetic geometry; no human quality evidence")
  static func program() throws -> DrawingProgram {
    let style = try StrokeStyle(nominalLineWidth: 0.4, penProfileID: PenProfileID())
    let coordinates: [[(Double, Double)]] = [[(10,10),(90,10)],[(10,30),(40,35),(90,30)],[(20,60),(75,70)],[(60,80),(70,90)]]
    return try DrawingProgram(id: ProgramID(), fieldExtent: .init(width: 100, height: 100), strokes: coordinates.enumerated().map { index, points in
      LogicalStroke(id: StrokeID(), path: try Polyline(points: points.map { try Point2(x: $0.0, y: $0.1) }), style: style, ordering: UInt32(index))
    }, source: .init(kind: "portrait", sourceIdentifier: "flow-artist-validation-fixture"))
  }
}
