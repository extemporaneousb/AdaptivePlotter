import Foundation
import DrawingLibrary
import PlotterModel
import PortraitArtists
import PortraitCore
@testable import PortraitLibrary
import Testing

private extension FlowPortfolioStore {
  /// Build the pre-spool domain row directly. completeCandidate now promises a
  /// modern exact closure and must not be used to simulate archived missing input.
  func installPreSpoolPreparationFixture(roundID: UUID, program: DrawingProgram,
    raster: FlowPortfolioBlob, preview: FlowPortfolioBlob) async throws -> FlowPortfolioCandidate {
    guard let round = state.rounds.first(where: { $0.id == roundID }) else {
      throw FlowPortfolioError.invalid("Historical fixture round is unavailable.")
    }
    let candidate = FlowPortfolioCandidate(id: UUID(), createdAt: Date(), sourceID: round.sourceID,
      roundID: round.id, slot: 0, parentCandidateID: round.parentCandidateID,
      recipe: round.recipes[0], modelID: round.modelID, raster: raster, preview: preview,
      programHash: program.contentHash.description, strokeCount: program.strokes.count)
    var next = state; next.candidates.append(candidate)
    next.rounds[next.rounds.firstIndex { $0.id == roundID }!].candidateIDs.append(candidate.id)
    try await commit(next)
    return candidate
  }
  func forgetHistoricalFixtureArtifacts() {
    temporaryDrawings.removeAll(); drawingInputs.removeAll(); sourcePhotoRecords.removeAll()
    previewArtifacts.removeAll(); featureCapsules.removeAll(); featureSupportingAssets.removeAll()
    storage.keepUnpublished([])
  }
}

@Suite("Recovered historical preparation closure", .serialized)
struct FlowHistoricalPreparationTests {
  @Test("Retention reconstructs only evidenced Photo preparation and remains editable after reopen", arguments: [false, true])
  func recoveredPreparation(knownGeometry: Bool) async throws {
    let root = DrawingExchangeFeedbackFixture.root(); defer { try? FileManager.default.removeItem(at: root) }
    let store = try await StudioDrawingFixture.store(directory: root, purpose: .validationFixture)
    let bytes = FlowPortfolioTests.photo
    let image = try PortraitDrawingImages.sourceAsset(bytes)
    let source = try await store.addSource(data: bytes, title: "Synthetic recovered source")
    let photoRef = try #require(source.photo)
    let geometry = try PortraitAnalysisGeometry(sourcePixelExtent: .init(widthPixels: Double(image.width), heightPixels: Double(image.height)), decodedWidth: image.width, decodedHeight: image.height, crop: .init(x: 0, y: 0, width: Double(image.width), height: Double(image.height)), rasterWidth: 2, rasterHeight: 2, contrastLow: 0, contrastHigh: 1, contrastApplied: true)
    let raster = PortraitRaster(width: 2, height: 2, luminance: [0,1,1,0], provenance: "explicit-synthetic-recovery-fixture", analysisSummary: "Known test preparation; no camera/physical claim", sourceCropExtent: knownGeometry ? geometry.sourcePixelExtent : nil, analysisGeometry: knownGeometry ? geometry : nil)
    let round = try await store.beginRound(sourceID: source.id, recipes: [.standard])
    let program = try FlowPortfolioTests.program(), preview = try PortraitDrawingPreview.png(program)
    let programBytes = try DrawingArtifactCoding.encoder().encode(program), rasterBytes = try DrawingArtifactCoding.encoder().encode(raster)
    let programAsset = try ExchangeAsset(bytes: programBytes, mediaType: "application/json", encoding: "utf8-json")
    let rasterAsset = try ExchangeAsset(bytes: rasterBytes, mediaType: "application/json", encoding: "utf8-json")
    let previewImage = try PortraitDrawingImages.sourceAsset(preview)
    let candidate = try await store.installPreSpoolPreparationFixture(roundID: round.id, program: program,
      raster: .init(sha256: rasterAsset.object.description, byteCount: rasterBytes.count, mediaType: "application/json"),
      preview: .init(sha256: previewImage.asset.descriptor.asset.object.description, byteCount: preview.count, mediaType: "image/png"))
    try await store.finishRound(round.id)
    #expect(candidate.authoringClosure == nil && candidate.authoringClosureLocation == nil)
    #expect(try await store.historyStatistics().entryCount == 0)
    #expect(await store.transientCacheStatistics().temporaryDrawingCount == 0)
    let candidateRow = try #require(try await store.library.record(.init(kind: "adaptiveplotter.flow-candidate/2", id: candidate.id)))
    let persistedCandidate = try JSONDecoder().decode(FlowLibraryEntity<FlowPortfolioCandidate>.self, from: candidateRow.payload)
    #expect(persistedCandidate.value.authoringClosure == nil && persistedCandidate.value.authoringClosureLocation == nil)
    let history = FlowHistoricalCandidate(id: candidate.id, program: .init(sha256: programAsset.object.description, byteCount: programBytes.count, mediaType: "application/json"), raster: candidate.raster, preview: candidate.preview)
    try await store.library.commitRecords([.init(kind: "adaptiveplotter.flow-historical-candidate/1", id: candidate.id, payload: DrawingArtifactCoding.encoder().encode(history), assets: [programAsset.object, rasterAsset.object, previewImage.asset.descriptor.asset.object])], assets: [.init(descriptor: .init(asset: programAsset), bytes: programBytes), .init(descriptor: .init(asset: rasterAsset), bytes: rasterBytes), .init(descriptor: previewImage.asset.descriptor, bytes: preview)])
    let frozen = try await store.freezeTrainingSnapshot()
    let frozenDocument = try await store.trainingDocument(snapshotID: frozen.id)
    await store.forgetHistoricalFixtureArtifacts()
    let archived = try #require(try await store.historicalDrawing(candidate.id))
    let retained = try await store.retainedDrawing(candidateID: candidate.id), ref = try #require(retained.reference)
    #expect(retained.program == program)
    #expect(retained.producer == archived.producer && retained.units == archived.units && retained.parent == archived.parent)
    #expect(retained.capabilities.producerVerified == archived.capabilities.producerVerified)
    let photo = try await store.library.photo(photoRef)
    #expect(photo.assets.first { $0.descriptor.asset == photo.record.original }?.bytes == bytes)
    let underPhoto = try await store.library.drawings(in: .photo(photoRef)).entries.map(\.reference)
    var reconstructedInput: ImageInputRef?
    if knownGeometry {
      guard case .present(let inputRef) = retained.input else { Issue.record("Known archived geometry lost its exact preparation link"); await store.closeLibrary(); return }
      reconstructedInput = inputRef
      let input = try await store.library.input(inputRef)
      #expect(input.photo.reference == photoRef)
      #expect(inputRef.revision == candidate.id)
      #expect(underPhoto.contains(ref))
      #expect(try await store.library.inputs(for: photoRef).entries.map(\.reference) == [inputRef])
      #expect(try await store.library.drawings(in: .input(inputRef)).entries.map(\.reference) == [ref])
    } else {
      guard case .unavailable = retained.input else { Issue.record("Unknown preparation was invented"); await store.closeLibrary(); return }
      #expect(!underPhoto.contains(ref))
      #expect(try await store.library.inputs(for: photoRef).entries.isEmpty)
    }
    #expect(try await store.retainedDrawing(candidateID: candidate.id).reference == ref)
    #expect(try await store.trainingDocument(snapshotID: frozen.id) == frozenDocument)
    await store.closeLibrary()
    let reopened = try await StudioDrawingFixture.store(directory: root)
    let reopenedBase = try await reopened.retainedDrawing(candidateID: candidate.id)
    #expect(reopenedBase.reference == ref)
    #expect(reopenedBase.producer == retained.producer && reopenedBase.units == retained.units)
    #expect(reopenedBase.input == retained.input && reopenedBase.parent == retained.parent)
    let edit = try await reopened.applyPrune(candidateID: candidate.id, action: .remove, indices: [0])
    let child = try await reopened.retainedDrawing(candidateID: candidate.id, revisionID: edit.id)
    #expect(child.parent == .present(ref))
    #expect(child.input == retained.input && child.units == retained.units)
    if let reconstructedInput {
      #expect(try await reopened.library.inputs(for: photoRef).entries.map(\.reference) == [reconstructedInput])
      #expect(try await reopened.library.drawings(in: .photo(photoRef)).entries.count == 2)
      #expect(Set(try await reopened.library.drawings(in: .input(reconstructedInput)).entries.map(\.reference)) == [ref, try #require(child.reference)])
    } else { #expect(try await reopened.library.drawings(in: .photo(photoRef)).entries.isEmpty) }
    #expect(try await reopened.trainingDocument(snapshotID: frozen.id) == frozenDocument)
    await reopened.closeLibrary()
  }
}
