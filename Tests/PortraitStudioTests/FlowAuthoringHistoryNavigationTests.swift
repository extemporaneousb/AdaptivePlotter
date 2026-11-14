import Foundation
import DrawingLibrary
import PlotterModel
import PortraitArtists
import PortraitCore
import PortraitLibrary
import PortraitStudioUI
import Testing

@Suite("Exact authoring history through the model", .serialized)
@MainActor
struct FlowAuthoringHistoryNavigationTests {
  @Test("Four panels, old siblings and branches remain exactly authorable across source, region and cold reopen")
  func fourLevelBranches() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let model = FlowAuthoringModel(directory: root, nominalPenWidthMM: 0.3,
      purpose: .validationFixture, render: HistoryNavigationFixture.render)
    model.count = 3
    await model.open(); await model.addPhoto(data: FlowAuthoringFixture.image(3), title: "History source")
    try await configureSource(model)
    let photo = try #require(model.currentPhotoRef), store = try #require(model.store), library = try #require(model.drawingLibrary)
    await model.generate(refining: false)
    let a = try await freezePanel(model)
    #expect(a.candidates.allSatisfy { $0.drawing.units.nominalPenWidthMM == 0.3 })
    #expect(try await library.drawings().entries.isEmpty)
    await model.exploreCandidate(a.candidates[0].candidate.id)
    let b = try await freezePanel(model)
    #expect(b.round.parentCandidateID == a.candidates[0].candidate.id && b.round.explorationDepth == 1)
    await model.exploreCandidate(b.candidates[1].candidate.id)
    let c = try await freezePanel(model)
    #expect(c.round.parentCandidateID == b.candidates[1].candidate.id && c.round.explorationDepth == 2)
    await model.exploreCandidate(c.candidates[1].candidate.id)
    let d = try await freezePanel(model)
    #expect(d.round.parentCandidateID == c.candidates[1].candidate.id && d.round.explorationDepth == 3)
    let galleryBeforeNavigation = try await library.drawings().entries.count
    #expect(galleryBeforeNavigation == 3)
    let judgments = judgmentIdentity(model)
    // This is the production Back action's selectRound path, three levels.
    for panel in [c, b, a] { await model.selectRound(panel.round.id) }
    #expect(model.round?.id == a.round.id && model.roundCandidates.map(\.id) == a.candidates.map { $0.candidate.id })
    #expect(judgmentIdentity(model) == judgments)
    #expect(try await library.drawings().entries.count == galleryBeforeNavigation)
    let oldSibling = a.candidates[2]
    #expect(oldSibling.candidate.drawing == nil && model.candidateUnavailableReason(oldSibling.candidate) == nil)
    await model.browseCandidate(oldSibling.candidate.id, prune: true)
    try await assertExact(oldSibling, model: model)
    #expect(model.canEdit && model.canSendToPlotter && model.canRefineCandidate(oldSibling.candidate))
    #expect(judgmentIdentity(model) == judgments)
    #expect(try await library.drawings().entries.count == galleryBeforeNavigation)
    let removed = try #require(model.program?.strokes.first?.id)
    await model.edit(.remove, ids: [removed])
    let edited = try #require(model.prune)
    #expect(model.removedIDs == [removed] && model.canEdit && model.canSendToPlotter)
    await model.generate(refining: true)
    let editedBranch = try await freezePanel(model)
    #expect(editedBranch.round.parentCandidateID == oldSibling.candidate.id)
    let anchor = try #require(editedBranch.candidates.first { $0.candidate.slot == 0 })
    let inherited = try #require(model.document?.latestPrune(candidateID: anchor.candidate.id))
    #expect(inherited.inheritedFromRevisionID == edited.id && inherited.removedIndices == edited.removedIndices)
    #expect(anchor.drawing.program == oldSibling.drawing.program)
    // A second B sibling creates a branch without overwriting C or D.
    await model.selectRound(b.round.id)
    await model.exploreCandidate(b.candidates[2].candidate.id)
    let otherBranch = try await freezePanel(model)
    #expect(otherBranch.round.parentCandidateID == b.candidates[2].candidate.id)
    let afterActions = judgmentIdentity(model), galleryAfterActions = try await library.drawings().entries.count
    for panel in [c, d, otherBranch, editedBranch, a] {
      await model.selectRound(panel.round.id)
      let unchosen = panel.candidates.last!
      await model.browseCandidate(unchosen.candidate.id, prune: true)
      try await assertExact(unchosen, model: model)
    }
    #expect(judgmentIdentity(model) == afterActions)
    #expect(try await library.drawings().entries.count == galleryAfterActions)
    await model.addPhoto(data: FlowAuthoringFixture.image(4), title: "Other source")
    await model.selectPhoto(photo)
    await model.commitRegion(.init(x: 0.1, y: 0.1, width: 0.7, height: 0.8))
    #expect(model.round == nil && !model.canSendToPlotter)
    await model.commitRegion(nil)
    for panel in [b, c, d, otherBranch, editedBranch] {
      await model.selectRound(panel.round.id)
      await model.browseCandidate(panel.candidates.last!.candidate.id, prune: true)
      try await assertExact(panel.candidates.last!, model: model)
    }
    #expect(judgmentIdentity(model) == afterActions)
    #expect(try await library.drawings().entries.count == galleryAfterActions)
    #expect(try await store.historyStatistics().entryCount == 18)
    #expect(await model.shutdown())
    // Reopening restores child closures whose parent is a retained exact Drawing.
    // Reading only their program/raster would miss a lost parent or input record.
    let cold = FlowAuthoringModel(directory: root, purpose: .validationFixture, render: HistoryNavigationFixture.render)
    await cold.open()
    for panel in [b, c, d, otherBranch, editedBranch, a] {
      await cold.selectRound(panel.round.id)
      let original = panel.candidates.last!
      await cold.browseCandidate(original.candidate.id, prune: true)
      try await assertExact(original, model: cold)
      #expect(cold.currentPhotoRef == photo && cold.canEdit && cold.canSendToPlotter && cold.canRefineCandidate(original.candidate))
    }
    #expect(judgmentIdentity(cold) == afterActions)
    #expect(try await cold.drawingLibrary?.drawings().entries.count == galleryAfterActions)
    #expect(await cold.shutdown())
  }

  @Test("A full history spool refuses a new round locally while previous siblings remain editable")
  func modelHistoryCapacity() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let model = FlowAuthoringModel(directory: root, purpose: .validationFixture,
      render: HistoryNavigationFixture.render, historyPolicy: .init(maximumEntries: 3))
    model.count = 3
    await model.open(); await model.addPhoto(data: FlowAuthoringFixture.image(5), title: "Bounded history")
    try await configureSource(model)
    await model.generate(refining: false)
    let panel = try await freezePanel(model), before = model.document
    await model.generate(refining: false)
    #expect(model.error?.contains("history") == true && !model.needsRecovery && !model.isBusy)
    #expect(model.document == before && model.round?.status == .completed)
    #expect(try await model.store?.historyStatistics().entryCount == 3)
    await model.browseCandidate(panel.candidates[2].candidate.id, prune: true)
    try await assertExact(panel.candidates[2], model: model)
    #expect(model.error == nil && model.canEdit && model.canSendToPlotter && model.canRefineCandidate(panel.candidates[2].candidate))
    let id = try #require(model.program?.strokes.first?.id)
    await model.edit(.remove, ids: [id])
    #expect(model.removedIDs == [id] && !model.needsRecovery && model.canSendToPlotter)
    #expect(await model.shutdown())
  }

  @Test("A mid-round byte refusal settles the model and durable round while preserving old exact history")
  func modelMidRoundByteCapacity() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let first = FlowAuthoringModel(directory: root, purpose: .validationFixture, render: HistoryNavigationFixture.render)
    first.count = 3
    await first.open(); await first.addPhoto(data: FlowAuthoringFixture.image(6), title: "Byte-bound history")
    try await configureSource(first)
    await first.generate(refining: false)
    let panel = try await freezePanel(first), usage = try #require(try await first.store?.historyStatistics())
    #expect(await first.shutdown())
    let model = FlowAuthoringModel(directory: root, purpose: .validationFixture, render: HistoryNavigationFixture.render,
      historyPolicy: .init(maximumBytes: usage.byteCount + 1))
    await model.open(); await model.generate(refining: false)
    #expect(model.error?.contains("history") == true && !model.needsRecovery && !model.isBusy)
    #expect(model.round?.status == .cancelled && model.roundCandidates.isEmpty && model.round?.failures.count == 1)
    #expect(model.document == (await model.store?.snapshot()))
    #expect(!model.isPreparingGeneration && !model.isRenderingGeneration && !model.canSendToPlotter)
    #expect(try await model.store?.historyStatistics().entryCount == usage.entryCount)
    await model.selectRound(panel.round.id); await model.browseCandidate(panel.candidates[1].candidate.id, prune: true)
    try await assertExact(panel.candidates[1], model: model)
    #expect(model.error == nil && model.canEdit && model.canSendToPlotter)
    #expect(await model.shutdown())
  }

  private func configureSource(_ model: FlowAuthoringModel) async throws {
    let source = try #require(model.selectedSource), store = try #require(model.store)
    try await store.setAuthoringOptions(sourceID: source.id, options: HistoryNavigationFixture.options)
    await model.retryCandidateLoad()
  }

  private struct Panel { let round: FlowPortfolioRound; let candidates: [Material] }
  private struct Material {
    let candidate: FlowPortfolioCandidate
    let drawing: Drawing
    let input: FrozenImageInputRecord
    let raster: PortraitRaster
    let preview: Data
  }
  private func freezePanel(_ model: FlowAuthoringModel) async throws -> Panel {
    #expect(model.error == nil && !model.needsRecovery && model.round?.status == .completed)
    let store = try #require(model.store), round = try #require(model.round)
    var candidates: [Material] = []
    for candidate in model.roundCandidates {
      let drawing = try await store.candidateDrawing(candidate.id)
      let input = try #require(try await store.candidateInput(candidate.id))
      #expect(drawing.input == .present(input.reference))
      #expect(!drawing.producer.originalJSON.isEmpty)
      candidates.append(.init(candidate: candidate, drawing: drawing, input: input,
        raster: try await store.candidateRaster(candidate.id), preview: try await store.candidatePreview(candidate.id)))
    }
    #expect(candidates.count == 3)
    return .init(round: round, candidates: candidates)
  }
  private func assertExact(_ original: Material, model: FlowAuthoringModel) async throws {
    let store = try #require(model.store)
    #expect(model.candidate?.id == original.candidate.id && model.program == original.drawing.program)
    #expect(model.candidateUnavailableReason(original.candidate) == nil)
    let drawing = try await store.candidateDrawing(original.candidate.id)
    #expect(drawing.program == original.drawing.program && drawing.producer == original.drawing.producer)
    #expect(drawing.units == original.drawing.units && drawing.input == original.drawing.input && drawing.parent == original.drawing.parent)
    let input = try #require(try await store.candidateInput(original.candidate.id))
    #expect(input.record.originalJSON == original.input.record.originalJSON && input.photo.record.originalJSON == original.input.photo.record.originalJSON)
    #expect(assetClosure(input) == assetClosure(original.input))
    #expect(try await store.candidateRaster(original.candidate.id) == original.raster)
    #expect(try await store.candidatePreview(original.candidate.id) == original.preview)
    if let revision = model.document?.latestPrune(candidateID: original.candidate.id), !revision.removedIndices.isEmpty {
      let item = FlowPortfolioPresentationItem(id: revision.id, candidateID: original.candidate.id,
        revisionID: revision.id, sourceID: original.candidate.sourceID, removedIndices: revision.removedIndices)
      #expect(model.previews[original.candidate.id] == (try await store.presentationPreview(item)))
    } else { #expect(model.previews[original.candidate.id] == original.preview) }
    #expect(model.canEdit && model.canSendToPlotter && model.canRefineCandidate(original.candidate))
  }
  private struct ClosureAsset: Equatable { let descriptor: ExchangeAssetDescriptor; let bytes: Data }
  private func assetClosure(_ input: FrozenImageInputRecord) -> [String: ClosureAsset] {
    var values: [String: ClosureAsset] = [:]
    for asset in input.assets + input.photo.assets {
      let key = asset.descriptor.asset.object.description
      let value = ClosureAsset(descriptor: asset.descriptor, bytes: asset.bytes)
      if let prior = values[key] { #expect(prior == value) }
      else { values[key] = value }
    }
    return values
  }
  private func judgmentIdentity(_ model: FlowAuthoringModel) -> [UUID] {
    (model.document?.choices.map(\.id) ?? []) + (model.document?.pruneRevisions.map(\.id) ?? [])
      + (model.document?.rankings.map(\.id) ?? [])
  }
}

/// Measured image preparation supplies the real FrozenImageInput closure. The
/// vector oracle stays deterministic and inexpensive; no camera is involved.
private enum HistoryNavigationFixture {
  static let options = PortraitAnalysisOptions(cropToFace: false, removeBackground: false)
  static let render: @Sendable (Data, FlowArtistRecipe, StrokeStyle) async throws -> PortraitRenderResult = { data, recipe, pen in
    let drawing = try await FlowAuthoringFixture.render(data, recipe, pen)
    let raster = try PortraitImageAnalyzer.analyze(data: data, options: options, maximumDimension: 24)
    return .init(raster: raster, program: drawing.program)
  }
}
