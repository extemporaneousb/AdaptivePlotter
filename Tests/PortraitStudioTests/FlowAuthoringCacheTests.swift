import Foundation
import DrawingLibrary
import PortraitArtists
import PortraitCore
@testable import PortraitLibrary
import Testing

@Suite("Bounded temporary authoring artifacts", .serialized)
struct FlowAuthoringCacheTests {
  private func root() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString) }
  private func generate(_ store: FlowPortfolioStore, source: UUID) async throws -> FlowPortfolioCandidate {
    let round = try await store.beginRound(sourceID: source, recipes: [.standard])
    let program = try FlowPortfolioTests.program()
    let candidate = try await store.completeCandidate(roundID: round.id, slot: 0,
      production: StudioDrawingFixture.production(program: program, raster: FlowPortfolioTests.raster), previewPNG: PortraitDrawingPreview.png(program))
    try await store.finishRound(round.id); return candidate
  }
  @Test("The previous panel stays authorable; older unchosen geometry expires without durable retention")
  func expiry() async throws {
    let directory = root(); defer { try? FileManager.default.removeItem(at: directory) }
    let store = try await StudioDrawingFixture.store(directory: directory)
    let source = try await store.addSource(data: FlowPortfolioTests.photo, title: "Fixture")
    let old = try await generate(store, source: source.id)
    let previous = try await generate(store, source: source.id)
    #expect(try await store.candidateProgram(old.id).strokes.count == 4)
    let current = try await generate(store, source: source.id)
    await #expect(throws: FlowPortfolioError.self) { try await store.candidateProgram(old.id) }
    await #expect(throws: FlowPortfolioError.self) { try await store.retainedDrawing(candidateID: old.id) }
    #expect(try await store.candidateProgram(current.id).strokes.count == 4)
    #expect(try await store.candidateProgram(previous.id).strokes.count == 4)
    #expect(try await store.candidateUnavailableReason(old.id) != nil)
    #expect(try await store.candidateUnavailableReason(previous.id) == nil)
    #expect(try await store.library.drawings().entries.isEmpty)
    var stats = await store.transientCacheStatistics()
    #expect(stats.temporaryDrawingCount == 2 && stats.artifactCount == 2)
    try await store.chooseCandidate(current.id)
    stats = await store.transientCacheStatistics()
    #expect(stats.temporaryDrawingCount == 1 && stats.drawingInputCount == 0 && stats.artifactBytes == 0)
    #expect(try await store.candidateRaster(current.id) == FlowPortfolioTests.raster)
    #expect(try await store.sourceData(source.id) == FlowPortfolioTests.photo)
    #expect(await store.transientCacheStatistics().artifactBytes == 0)
    await store.closeLibrary()
  }
  @Test("Count pressure evicts an optional whole panel before admitting new mandatory results")
  func optionalPanelPressure() async throws {
    let directory = root(); defer { try? FileManager.default.removeItem(at: directory) }
    let store = try await StudioDrawingFixture.store(directory: directory)
    let source = try await store.addSource(data: FlowPortfolioTests.photo, title: "Fixture")
    let program = try FlowPortfolioTests.program()
    let production = try StudioDrawingFixture.production(program: program, raster: FlowPortfolioTests.raster)
    let preview = try PortraitDrawingPreview.png(program)
    let old = try await store.beginRound(sourceID: source.id, recipes: Array(repeating: .standard, count: 24))
    var previous: [FlowPortfolioCandidate] = []
    for slot in 0..<24 {
      previous.append(try await store.completeCandidate(roundID: old.id, slot: slot, production: production, previewPNG: preview))
    }
    try await store.finishRound(old.id)
    let current = try await store.beginRound(sourceID: source.id, recipes: [.standard, .standard])
    let first = try await store.completeCandidate(roundID: current.id, slot: 0, production: production, previewPNG: preview)
    #expect(await store.transientCacheStatistics().temporaryDrawingCount == 25)
    let second = try await store.completeCandidate(roundID: current.id, slot: 1, production: production, previewPNG: preview)
    try await store.finishRound(current.id)
    #expect(await store.transientCacheStatistics().temporaryDrawingCount == 2)
    #expect(try await store.candidateProgram(first.id) == program)
    #expect(try await store.candidateProgram(second.id) == program)
    for candidate in previous { #expect(try await store.candidateUnavailableReason(candidate.id) != nil) }
    #expect(try await store.library.drawings().entries.isEmpty)
    await store.closeLibrary()
  }

  @Test("Source and crop changes drop optional session geometry without retaining or judging it")
  func sourceAndRegionInvalidation() async throws {
    let directory = root(); defer { try? FileManager.default.removeItem(at: directory) }
    let store = try await StudioDrawingFixture.store(directory: directory)
    let source = try await store.addSource(data: FlowPortfolioTests.photo, title: "Fixture")
    let first = try await generate(store, source: source.id), second = try await generate(store, source: source.id)
    try await store.setAuthoringOptions(sourceID: source.id,
      options: .init(manualRegion: .init(x: 0.1, y: 0.1, width: 0.8, height: 0.8)))
    #expect(await store.transientCacheStatistics().temporaryDrawingCount == 0)
    #expect(try await store.candidateUnavailableReason(first.id) != nil)
    #expect(try await store.candidateUnavailableReason(second.id) != nil)
    let afterCrop = try await generate(store, source: source.id)
    _ = try await store.addSource(data: FlowPortfolioTests.photo, title: "Another source")
    #expect(try await store.candidateUnavailableReason(afterCrop.id) != nil)
    let state = await store.snapshot()
    #expect(state.choices.isEmpty && state.pruneRevisions.isEmpty)
    #expect(try await store.library.drawings().entries.isEmpty)
    await store.closeLibrary()
  }

  @Test("Pinned panel capacity rejects admission rather than evicting an in-flight generation")
  func pinnedLimit() async throws {
    let directory = root(); defer { try? FileManager.default.removeItem(at: directory) }
    let store = try await StudioDrawingFixture.store(directory: directory)
    let source = try await store.addSource(data: FlowPortfolioTests.photo, title: "Fixture")
    var candidates: [FlowPortfolioCandidate] = []
    for _ in 0..<FlowPortfolioStore.maximumTemporaryDrawings {
      let round = try await store.beginRound(sourceID: source.id, recipes: [.standard])
      let program = try FlowPortfolioTests.program()
      candidates.append(try await store.completeCandidate(roundID: round.id, slot: 0,
        production: StudioDrawingFixture.production(program: program, raster: FlowPortfolioTests.raster), previewPNG: PortraitDrawingPreview.png(program)))
      // Intentionally unfinished rounds represent outstanding generation owners.
    }
    let extra = try await store.beginRound(sourceID: source.id, recipes: [.standard])
    let program = try FlowPortfolioTests.program()
    await #expect(throws: FlowPortfolioError.self) {
      try await store.completeCandidate(roundID: extra.id, slot: 0,
        production: StudioDrawingFixture.production(program: program, raster: FlowPortfolioTests.raster), previewPNG: PortraitDrawingPreview.png(program))
    }
    #expect(try await store.candidateProgram(candidates[0].id).strokes.count == 4)
    #expect(await store.transientCacheStatistics().temporaryDrawingCount == FlowPortfolioStore.maximumTemporaryDrawings)
    await store.closeLibrary()
  }
  @Test("Failed pending graph recovery marks only its captured assets, leaving a late preview publishable")
  func pendingPublicationSnapshot() async throws {
    let directory = root(); defer { try? FileManager.default.removeItem(at: directory) }
    let store = try await StudioDrawingFixture.store(directory: directory)
    let source = try await store.addSource(data: FlowPortfolioTests.photo, title: "Fixture")
    let candidate = try await generate(store, source: source.id)
    let objects = directory.appendingPathComponent("objects/sha256"), held = directory.appendingPathComponent("objects/held")
    try FileManager.default.moveItem(at: objects, to: held)
    try Data([0]).write(to: objects)
    await #expect(throws: (any Error).self) { try await store.renameSource(sourceID: source.id, title: "Captured change") }
    #expect(await store.pendingGraphWrite != nil)
    try FileManager.default.removeItem(at: objects)
    try FileManager.default.moveItem(at: held, to: objects)
    _ = try await store.featureCapsule(candidateID: candidate.id)
    let item = FlowPortfolioPresentationItem(id: candidate.id, candidateID: candidate.id, revisionID: nil,
      sourceID: source.id, removedIndices: [])
    let preview = try await store.presentationPreview(item)
    try await store.reloadCommittedState()
    #expect(try await store.presentationPreview(item) == preview)
    try await store.renameSource(sourceID: source.id, title: "Publish late feature preview")
    await store.closeLibrary()
    let reopened = try await StudioDrawingFixture.store(directory: directory)
    #expect(try await reopened.presentationPreview(item) == preview)
    await reopened.closeLibrary()
  }
}
