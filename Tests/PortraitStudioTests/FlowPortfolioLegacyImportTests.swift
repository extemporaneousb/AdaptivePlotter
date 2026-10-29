import Foundation
import PlotterModel
import PortraitArtists
import PortraitCore
@testable import PortraitLibrary
import SQLite3
import Testing

@Suite("Explicit historical Flow portfolio import", .serialized)
@MainActor
struct FlowPortfolioLegacyImportTests {
  @Test("Historical import retains actual corrections without inventing positives or complete targets")
  func exactHistoricalOperations() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let old = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root); try? FileManager.default.removeItem(at: old) }
    let legacyStore = PortraitCandidateStore(directoryURL: old), collection = PortraitSketchCollection(store: legacyStore)
    let program = try FlowPortfolioTests.program()
    let recipe = PortraitStyleRecipe(id: "historical", title: "Historical fixture", seed: 0, style: .flowEdges,
      vectorOptions: .init(), analysisOptions: .init())
    let candidate = try PortraitCandidate(sourceData: FlowPortfolioTests.photo, sourcePixelExtent: nil,
      raster: FlowPortfolioTests.raster, recipe: recipe, program: program, photoID: UUID(), captureSessionID: UUID())
    collection.retainSourcePhoto(PortraitPhoto(id: candidate.photoID, data: candidate.sourceData,
      label: "Historical fixture source", capturedAt: candidate.createdAt, pose: .front,
      captureSessionID: candidate.captureSessionID))
    await collection.awaitPersistence()
    let base = SavedDrawing(candidate: candidate), bytes = try await collection.exportDrawingPackage(base)
    let package = try DrawingPackageCodec.decode(bytes)
    let generated = try DrawingStrokeSelection(editID: UUID(), createdAt: Date(), originalPackageJSON: bytes,
      baseOrigin: package.origin, baseProgram: package.program, initialRemovedStrokeIDs: [],
      operations: [.init(action: .remove, strokeIDs: [program.strokes[0].id])], operationSource: .exerciseProposal,
      exerciseContext: .init(id: UUID(), title: "Historical proposal", policyJSON: Data("{}".utf8)))
    let initial = try await collection.saveStrokeSelection(generated, base: base)
    let initialPackage = try #require(initial.transferredPackage)
    let human = try DrawingStrokeSelection(editID: UUID(), createdAt: Date(), originalPackageJSON: bytes,
      baseOrigin: initialPackage.origin, baseProgram: initialPackage.program,
      initialRemovedStrokeIDs: [program.strokes[0].id],
      operations: [.init(action: .remove, strokeIDs: [program.strokes[1].id])],
      operationSource: .human, exerciseContext: generated.exerciseContext)
    let edited = try await collection.saveStrokeSelection(human, base: initial)
    let editedBytes = try await collection.exportDrawingPackage(edited)
    let store = try FlowPortfolioStore(directory: root, purpose: .validationFixture)
    let imported = try await store.importLegacySelection(packageData: editedBytes)
    let repeated = try await store.importLegacySelection(packageData: editedBytes)
    #expect(imported == repeated)
    let state = await store.snapshot()
    #expect(state.legacyImports.count == 1)
    #expect(state.sources.count == 1 && state.candidates.count == 1)
    #expect(state.pruneRevisions.map(\.action) == [.inheritedSelection, .remove])
    #expect(state.pruneRevisions.first?.historicalRecord?.sha256 == DrawingPackageCodec.sha256(editedBytes))
    #expect(state.pruneRevisions.last?.affectedIndices == [1])
    #expect(state.pruneRevisions.last?.removedIndices == [0, 1])
    #expect(state.choices.isEmpty && state.rankings.isEmpty)
    #expect(state.pruneRevisions.allSatisfy { $0.action != .completeTarget })
    #expect(try await store.sourceData(imported.sourceID) == FlowPortfolioTests.photo)
    #expect(try await store.candidateProgram(imported.candidateID) == program)
    await #expect(throws: (any Error).self) { try await store.importLegacySelection(packageData: DrawingPackageCodec.encode(initialPackage)) }
  }

  @Test("Import only retained human targets from an explicit read-only historical library",
    .enabled(if: ProcessInfo.processInfo.environment["FLOW_PORTFOLIO_LEGACY_SOURCE"] != nil))
  func bootstrapRealPortfolio() async throws {
    let environment = ProcessInfo.processInfo.environment
    let sourcePath = try #require(environment["FLOW_PORTFOLIO_LEGACY_SOURCE"])
    let destinationPath = try #require(environment["FLOW_PORTFOLIO_LEGACY_DESTINATION"])
    try #require(sourcePath.hasPrefix("/") && destinationPath.hasPrefix("/") && sourcePath != destinationPath)
    let source = URL(fileURLWithPath: sourcePath, isDirectory: true), destination = URL(fileURLWithPath: destinationPath, isDirectory: true)
    try #require(!FileManager.default.fileExists(atPath: destination.path))
    var db: OpaquePointer?
    guard sqlite3_open_v2(source.appendingPathComponent("library-v1.sqlite").path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
      if let db { sqlite3_close(db) }
      throw FlowPortfolioError.unavailable("The declared historical library cannot be read.")
    }
    defer { sqlite3_close(db) }
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(db, "SELECT reference FROM generic_drawing ORDER BY ordinal", -1, &statement, nil) == SQLITE_OK else {
      throw FlowPortfolioError.invalid("Historical retained-drawing inventory is unavailable.")
    }
    defer { sqlite3_finalize(statement) }
    var packages: [Data] = []
    while sqlite3_step(statement) == SQLITE_ROW {
      guard let text = sqlite3_column_text(statement, 0),
        let reference = try JSONSerialization.jsonObject(with: Data(String(cString: text).utf8)) as? [String: Any],
        let hash = reference["recordSHA256"] as? String,
        hash.count == 64 && hash.allSatisfy(\.isHexDigit) else {
        throw FlowPortfolioError.invalid("Historical record reference is invalid.")
      }
      let url = source.appendingPathComponent("records").appendingPathComponent(hash)
      let bytes = try Data(contentsOf: url)
      guard DrawingPackageCodec.sha256(bytes) == hash else { throw FlowPortfolioError.invalid("Historical record checksum mismatch.") }
      let drawing = try JSONDecoder().decode(SavedDrawing.self, from: bytes)
      guard let package = drawing.transferredPackage,
        let selection = try DrawingStrokeSelection.record(in: package), selection.schemaVersion == 2,
        selection.operationSource == .human else { continue }
      packages.append(try DrawingPackageCodec.encode(package))
    }
    try #require(!packages.isEmpty)
    let portfolio = try FlowPortfolioStore(directory: destination, purpose: .artist)
    for bytes in packages {
      let imported = try await portfolio.importLegacySelection(packageData: bytes)
      let package = try DrawingPackageCodec.decode(bytes)
      let selection = try #require(try DrawingStrokeSelection.record(in: package))
      let original = try selection.original()
      #expect(try await portfolio.sourceData(imported.sourceID) == original.source.bytes)
      #expect(try await portfolio.candidateProgram(imported.candidateID) == original.program)
      let state = await portfolio.snapshot()
      let positions = Dictionary(uniqueKeysWithValues: original.program.strokes.enumerated().map { ($0.element.id, $0.offset) })
      let revisions = state.pruneRevisions.filter { $0.candidateID == imported.candidateID }
      let human = revisions.filter { $0.action == .remove || $0.action == .restore }
      #expect(human.map(\.affectedIndices) == (selection.operations ?? []).map { $0.strokeIDs.compactMap { positions[$0] }.sorted() })
      #expect(human.map(\.action) == (selection.operations ?? []).map { $0.action == .remove ? FlowPruneAction.remove : .restore })
      #expect(revisions.last?.removedIndices == selection.removedStrokeIDs.compactMap { positions[$0] }.sorted())
      #expect(imported.package.sha256 == DrawingPackageCodec.sha256(bytes))
    }
    let snapshot = await portfolio.snapshot()
    #expect(snapshot.legacyImports.count == packages.count)
    #expect(snapshot.rankings.isEmpty && snapshot.choices.isEmpty && snapshot.fits.isEmpty)
    #expect(!snapshot.pruneRevisions.contains { $0.action == .completeTarget })
    let operations = snapshot.pruneRevisions.filter { $0.action == .remove || $0.action == .restore }
    print("Historical Flow portfolio: \(snapshot.sources.count) sources; \(snapshot.legacyImports.count) exact human targets; \(operations.reduce(0) { $0 + $1.affectedIndices.count }) explicit stroke decisions; source bytes, root programs, per-operation indices, masks and retained package hashes verified; no invented rankings or completed targets. Destination: \(destination.path)")
  }
}
