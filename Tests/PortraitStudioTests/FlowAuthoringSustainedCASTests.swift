import Foundation
@testable import DrawingLibrary
import PlotterModel
import PortraitArtists
import PortraitCore
@testable import PortraitLibrary
import Testing

@Suite("Sustainable exact history in Library CAS", .serialized)
struct FlowAuthoringSustainedCASTests {
  private func temporary() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent("flow-sustained-cas-" + UUID().uuidString) }
  private func open(_ directory: URL) async throws -> FlowPortfolioStore {
    let store = FlowPortfolioStore(directory: directory, purpose: .validationFixture)
    try await store.loadRecords(); return store
  }
  private func native(_ store: FlowPortfolioStore, source: FlowPortfolioSource) async throws -> DrawingProduction<PortraitRenderResult> {
    let photo = try await store.sourcePhoto(source.id), data = try await store.sourceData(source.id)
    let style = try FlowPortfolioTests.program().strokes[0].style
    return try await PortraitFlowDrawingProducer().produce(input: .init(data: data, photo: photo),
      settings: .init(recipe: FlowArtistRecipe.standard.withoutSyntheticLoops,
        analysisOptions: .init(cropToFace: false, removeBackground: false), strokeStyle: style, nominalPenWidthMM: 0.35))
  }
  private func generate(_ store: FlowPortfolioStore, source: UUID, count: Int, panelSize: Int,
    production: DrawingProduction<PortraitRenderResult>) async throws -> [FlowPortfolioCandidate] {
    let claim = try JSONDecoder().decode(PortraitFlowProducerClaim.self, from: production.drawing.producer.originalJSON)
    let preview = try PortraitDrawingPreview.png(production.drawing.program)
    var result: [FlowPortfolioCandidate] = []
    while result.count < count {
      let slots = min(panelSize, count - result.count)
      let round = try await store.beginRound(sourceID: source, recipes: Array(repeating: claim.settings.recipe, count: slots),
        analysisOptions: claim.settings.analysisOptions)
      for slot in 0..<slots {
        result.append(try await store.completeCandidate(roundID: round.id, slot: slot, production: production, previewPNG: preview))
        let cache = await store.transientCacheStatistics()
        #expect(cache.temporaryDrawingCount <= FlowPortfolioStore.maximumTemporaryDrawings)
        #expect(cache.temporaryDrawingBytes <= FlowPortfolioStore.maximumTemporaryDrawingBytes)
      }
      try await store.finishRound(round.id)
    }
    return result
  }
  private func exact(_ candidate: FlowPortfolioCandidate, store: FlowPortfolioStore,
    production: DrawingProduction<PortraitRenderResult>) async throws {
    #expect(try await store.candidateUnavailableReason(candidate.id) == nil)
    let actual = try await store.candidateDrawing(candidate.id)
    #expect(actual.program == production.drawing.program && actual.producer == production.drawing.producer)
    #expect(actual.input == production.drawing.input && actual.parent == production.drawing.parent && actual.units == production.drawing.units)
    let input = try #require(try await store.candidateInput(candidate.id))
    let expected = try #require(production.artifacts.drawingInput)
    #expect(input.reference == expected.reference && input.record.originalJSON == expected.record.originalJSON)
    #expect(input.photo.reference == expected.photo.reference && input.photo.record.originalJSON == expected.photo.record.originalJSON)
    #expect(try await store.candidateRaster(candidate.id) == production.artifacts.raster)
    #expect(try await store.candidatePreview(candidate.id) == PortraitDrawingPreview.png(production.drawing.program))
  }
  private func neutral(_ store: FlowPortfolioStore, photo: PhotoRef) async throws {
    #expect(try await store.library.drawings().entries.isEmpty)
    #expect(try await store.library.inputs(for: photo).entries.isEmpty)
    let state = await store.snapshot()
    #expect(state.choices.isEmpty && state.pruneRevisions.isEmpty && state.rankings.isEmpty)
  }
  @Test("More than 512 precomputed native candidates remain usable through cold reopen without gallery or learning promotion")
  func beyondFormerEntryLimit() async throws {
    let root = temporary(); defer { try? FileManager.default.removeItem(at: root) }
    let store = try await open(root)
    let source = try await store.addSource(data: FlowPortfolioTests.photo, title: "Native count-bound regression fixture")
    let produced = try await native(store, source: source)
    let clock = ContinuousClock(), start = clock.now
    let candidates = try await generate(store, source: source.id, count: 520, panelSize: 24, production: produced)
    print("FLOW_CAS_520_PRECOMPUTED_NATIVE_ADMISSIONS=\(start.duration(to: clock.now))")
    #expect(candidates.count == 520)
    let stats = try await store.historyStatistics()
    #expect(stats.entryCount == 520 && stats.libraryEntryCount == 520 && stats.legacyEntryCount == 0)
    #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("flow-authoring-history-v1").path))
    try await neutral(store, photo: #require(source.photo))
    await store.closeLibrary()
    let reopened = try await open(root)
    for candidate in [candidates[0], candidates[257], candidates[519]] { try await exact(candidate, store: reopened, production: produced) }
    let afterReopen = try await generate(reopened, source: source.id, count: 1, panelSize: 1, production: produced)
    let resumedStats = try await reopened.historyStatistics()
    #expect(afterReopen.count == 1 && resumedStats.entryCount == 521)
    try await neutral(reopened, photo: #require(source.photo))
    // Refinement is explicit user intent: retain only this old unchosen parent.
    // All neutrality assertions above precede that retention; no choice/judgment
    // is invented merely to exercise an old branch after the former count cap.
    let oldSibling = candidates[257]
    try await reopened.selectRound(oldSibling.roundID)
    let parent = try await reopened.retainedDrawing(candidateID: oldSibling.id)
    let parentRef = try #require(parent.reference)
    let parentClaim = try JSONDecoder().decode(PortraitFlowProducerClaim.self, from: parent.producer.originalJSON)
    let recipe = try FlowArtistProposals.propose(count: 2, seed: 521, parent: oldSibling.recipe,
      raster: produced.artifacts.raster, checkpoint: nil, refinementRadius: 0.06)[1]
    let photo = try await reopened.sourcePhoto(source.id), data = try await reopened.sourceData(source.id)
    let childProduction = try await PortraitFlowDrawingProducer().produce(
      input: .init(data: data, parent: .present(parentRef), photo: photo),
      settings: .init(recipe: recipe, analysisOptions: parentClaim.settings.analysisOptions,
        strokeStyle: parentClaim.settings.strokeStyle, nominalPenWidthMM: parentClaim.settings.nominalPenWidthMM))
    let branch = try await reopened.beginRound(sourceID: source.id, recipes: [recipe], parentCandidateID: oldSibling.id,
      analysisOptions: parentClaim.settings.analysisOptions, explorationDepth: 1, refinementRadius: 0.06,
      explorationPolicy: "contracting-neighborhood-v1")
    let child = try await reopened.completeCandidate(roundID: branch.id, slot: 0, production: childProduction,
      previewPNG: PortraitDrawingPreview.png(childProduction.drawing.program))
    try await reopened.finishRound(branch.id)
    #expect(child.parentCandidateID == oldSibling.id && child.sourceID == source.id)
    #expect(childProduction.drawing.parent == .present(parentRef) && childProduction.drawing.units == parent.units)
    let childInput = try #require(childProduction.artifacts.drawingInput)
    #expect(childProduction.drawing.input == .present(childInput.reference) && childInput.photo.reference == source.photo)
    #expect(try await reopened.library.drawings().entries.count == 1)
    let afterBranch = await reopened.snapshot()
    #expect(afterBranch.choices.isEmpty && afterBranch.pruneRevisions.isEmpty && afterBranch.rankings.isEmpty)
    #expect(try await reopened.historyStatistics().entryCount == 522)
    await reopened.closeLibrary()
    let coldBranch = try await open(root)
    try await exact(child, store: coldBranch, production: childProduction)
    let coldParent = try await coldBranch.library.drawing(parentRef)
    #expect(coldParent.program == parent.program && coldParent.producer == parent.producer && coldParent.input == parent.input)
    #expect(coldParent.units == parent.units && coldParent.parent == parent.parent)
    #expect(try await coldBranch.library.drawings().entries.count == 1)
    await coldBranch.closeLibrary()
  }
  @Test("Seventy candidates sharing one 31MiB Photo cross the former aggregate cap without restaging or rehashing that source per candidate")
  func largeOriginalDeduplication() async throws {
    let root = temporary(); defer { try? FileManager.default.removeItem(at: root) }
    let bytes = FlowAuthoringHistoryTests.paddedPNG(FlowPortfolioTests.photo, payloadBytes: 31 * 1024 * 1024)
    #expect(bytes.count < DrawingArtifactLimits.sourceBytes)
    let store = try await open(root)
    let source = try await store.addSource(data: bytes, title: "Shared large original regression fixture")
    let produced = try await native(store, source: source)
    let before = await store.library.assetReuseStatistics()
    let candidates = try await generate(store, source: source.id, count: 70, panelSize: 3, production: produced)
    let after = await store.library.assetReuseStatistics(), stats = try await store.historyStatistics()
    #expect(70 * source.image.byteCount > 2 * 1024 * 1024 * 1024)
    #expect(stats.entryCount == 70 && stats.byteCount < 2 * source.image.byteCount)
    // The full-source digest is established once for reuse, then bounded sealed
    // fingerprints are checked. New tiny parts retain their own normal admission.
    #expect(after.hashedBytes - before.hashedBytes < UInt64(source.image.byteCount + 2 * 1024 * 1024))
    #expect(after.cacheHits > before.cacheHits + 69)
    #expect(after.cachedProofCount <= DrawingLibrary.maximumExistingAssetProofs)
    let digest = try ExchangeDigest(source.image.sha256)
    #expect(try await store.library.historyAssetTransactionFileCount(digest) == 1)
    #expect(try Data(contentsOf: root.appendingPathComponent("objects/sha256/" + source.image.sha256)) == bytes)
    #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("flow-authoring-history-v1").path))
    print("FLOW_CAS_SHARED_PHOTO_ADMISSIONS=70 sourceBytes=\(bytes.count) uniqueHistoryBytes=\(stats.byteCount) reuseHashedBytes=\(after.hashedBytes-before.hashedBytes) cacheHits=\(after.cacheHits-before.cacheHits)")
    try await neutral(store, photo: #require(source.photo))
    await store.closeLibrary()
    let reopened = try await open(root)
    for candidate in [candidates[0], candidates[35], candidates[69]] { try await exact(candidate, store: reopened, production: produced) }
    try await neutral(reopened, photo: #require(source.photo))
    await reopened.closeLibrary()
  }
  @Test("A real staging-directory obstruction preserves prior history and recovers the same candidate commit intent once")
  func actualFilesystemFailure() async throws {
    let root = temporary(); defer { try? FileManager.default.removeItem(at: root) }
    let store = try await open(root)
    let source = try await store.addSource(data: FlowPortfolioTests.photo, title: "Filesystem recovery fixture")
    let produced = try await native(store, source: source)
    let old = try #require(try await generate(store, source: source.id, count: 1, panelSize: 1, production: produced).first)
    await store.closeLibrary()
    let recovering = try await open(root)
    let claim = try JSONDecoder().decode(PortraitFlowProducerClaim.self, from: produced.drawing.producer.originalJSON)
    let round = try await recovering.beginRound(sourceID: source.id, recipes: [claim.settings.recipe], analysisOptions: claim.settings.analysisOptions)
    let staging = root.appendingPathComponent("exchange-staging"), held = root.appendingPathComponent("exchange-staging-held-test")
    try FileManager.default.moveItem(at: staging, to: held)
    try Data([0]).write(to: staging) // Real ENOTDIR/allocation failure, no fake thrown fault.
    await #expect(throws: (any Error).self) {
      try await recovering.completeCandidate(roundID: round.id, slot: 0, production: produced,
        previewPNG: PortraitDrawingPreview.png(produced.drawing.program))
    }
    let intent = try #require(await recovering.pendingGraphWrite?.intent.id)
    #expect(await recovering.snapshot().candidates.count == 1)
    try await exact(old, store: recovering, production: produced)
    try FileManager.default.removeItem(at: staging); try FileManager.default.moveItem(at: held, to: staging)
    try await recovering.reloadCommittedState()
    #expect(await recovering.pendingGraphWrite == nil)
    #expect(await recovering.snapshot().candidates.count == 2)
    #expect(try await recovering.library.historyDomainCommitCount(intent) == 1)
    try await recovering.reloadCommittedState()
    #expect(try await recovering.library.historyDomainCommitCount(intent) == 1)
    try await recovering.finishRound(round.id)
    _ = try await generate(recovering, source: source.id, count: 1, panelSize: 1, production: produced)
    #expect(await recovering.snapshot().candidates.count == 3)
    try await exact(old, store: recovering, production: produced)
    try await neutral(recovering, photo: #require(source.photo))
    await recovering.closeLibrary()
  }
}

private extension DrawingLibrary {
  func historyAssetTransactionFileCount(_ digest: ExchangeDigest) throws -> Int {
    guard let db = try commonReadDatabase() else { return 0 }
    return Int(try db.scalar("SELECT COUNT(*) FROM dx_tx_file WHERE digest=?", [digest.description]) ?? "0") ?? 0
  }
  func historyDomainCommitCount(_ intent: UUID) throws -> Int {
    guard let db = try commonReadDatabase() else { return 0 }
    return Int(try db.scalar("SELECT COUNT(*) FROM domain_commit WHERE id=?", [intent.uuidString.lowercased()]) ?? "0") ?? 0
  }
}
