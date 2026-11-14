import Foundation
import DrawingLibrary
import PlotterModel
import PortraitArtists
import PortraitCore
@testable import PortraitLibrary
import PortraitStudioUI
import Testing

@Suite("Studio exact-input exploration and local editing", .serialized)
@MainActor
struct FlowAuthoringExplorationTests {
  @Test("Comparison overlays cannot strand pruning or survive drawing navigation")
  func comparisonPolicy() async throws {
    let root = DrawingEditFixture.root(); defer { try? FileManager.default.removeItem(at: root) }
    let model = FlowAuthoringModel(directory: root, purpose: .validationFixture, render: FlowAuthoringFixture.render)
    await model.open(); await model.addPhoto(data: FlowAuthoringFixture.image(1), title: "Fixture")
    model.count = 3; await model.generate(refining: false)
    let values = model.roundCandidates
    await model.browseCandidate(values[0].id)
    model.showsOriginal = true; model.showsPhoto = true
    #expect(!model.canEdit && model.editingUnavailableReason != nil)
    model.beginPruning()
    #expect(model.canEdit && !model.showsOriginal && !model.showsPhoto)
    model.showsPhoto = true
    await model.browseCandidate(values[1].id, prune: true)
    #expect(model.canEdit && model.stage == .prune)
    #expect(model.document?.choices.isEmpty == true)
    #expect(await model.shutdown())
  }

  @Test("Tile choices contract radius, preserve exact mask anchors and history remains neutral")
  func contractingNeighborhood() async throws {
    let root = DrawingEditFixture.root(); defer { try? FileManager.default.removeItem(at: root) }
    let model = FlowAuthoringModel(directory: root, purpose: .validationFixture, render: FlowAuthoringFixture.render)
    await model.open(); await model.addPhoto(data: FlowAuthoringFixture.image(2), title: "Fixture")
    model.count = 3; await model.generate(refining: false)
    let broad = try #require(model.round), parent = try #require(model.roundCandidates.first)
    var oldJSON = try #require(JSONSerialization.jsonObject(with: DrawingArtifactCoding.encoder().encode(broad)) as? [String: Any])
    for key in ["explorationDepth", "refinementRadius", "explorationPolicy", "recommendedRemovedIndices"] { oldJSON.removeValue(forKey: key) }
    let decoded = try JSONDecoder().decode(FlowPortfolioRound.self, from: JSONSerialization.data(withJSONObject: oldJSON))
    #expect(decoded.explorationDepth == nil && decoded.refinementRadius == nil && decoded.explorationPolicy == nil
      && decoded.recommendedRemovedIndices == nil)
    await model.browseCandidate(parent.id, prune: true)
    await model.edit(.remove, ids: [try #require(model.program?.strokes.first?.id)])
    let mask = try #require(model.prune)
    await model.exploreCandidate(parent.id)
    #expect(model.round?.explorationDepth == 1 && model.round?.refinementRadius == 0.06)
    let anchor = try #require(model.roundCandidates.first { $0.slot == 0 })
    #expect(model.document?.latestPrune(candidateID: anchor.id)?.inheritedFromRevisionID == mask.id)
    #expect(model.document?.choices.count == 1)
    await model.exploreCandidate(anchor.id)
    #expect(model.round?.explorationDepth == 2)
    #expect(abs(try #require(model.round?.refinementRadius) - 0.051) < 1e-10)
    let count = model.document?.choices.count
    await model.selectRound(broad.id)
    #expect(model.document?.choices.count == count)
    await model.generate(refining: false)
    #expect(model.round?.explorationDepth == 0 && model.round?.refinementRadius == nil)
    #expect(await model.shutdown())
  }

  @Test("An all-removed tile refuses exploration before feedback or pending-page admission")
  func emptyTileRefusal() async throws {
    let root = DrawingEditFixture.root(); defer { try? FileManager.default.removeItem(at: root) }
    let model = FlowAuthoringModel(directory: root, purpose: .validationFixture, render: FlowAuthoringFixture.render)
    await model.open(); await model.addPhoto(data: FlowAuthoringFixture.image(3), title: "Fixture")
    model.count = 3; await model.generate(refining: false)
    let candidate = try #require(model.roundCandidates.first)
    await model.browseCandidate(candidate.id, prune: true)
    await model.edit(.remove, ids: Set(try #require(model.program).strokes.map(\.id)))
    let choices = model.document?.choices.count, rounds = model.document?.rounds.count
    await model.exploreCandidate(candidate.id)
    #expect(model.document?.choices.count == choices && model.document?.rounds.count == rounds)
    #expect(model.pendingExplorationParentID == nil && !model.isBusy && model.error != nil)
    #expect(!model.canSendToPlotter && !model.needsRecovery)
    #expect(await model.shutdown())
  }

  @Test("Back restores authorable unchosen siblings for a new branch without recovery")
  func backThenUnchosenSiblingBranch() async throws {
    let root = DrawingEditFixture.root(); defer { try? FileManager.default.removeItem(at: root) }
    let model = FlowAuthoringModel(directory: root, purpose: .validationFixture, render: FlowAuthoringFixture.render)
    await model.open(); await model.addPhoto(data: FlowAuthoringFixture.image(3), title: "Fixture")
    model.count = 3; await model.generate(refining: false)
    let broad = try #require(model.round), originalCandidates = model.roundCandidates
    let chosen = originalCandidates[0], sibling = originalCandidates[1]
    await model.exploreCandidate(chosen.id)
    let choices = model.document?.choices.count, rounds = model.document?.rounds.count
    await model.selectRound(broad.id)
    #expect(model.document?.choices.count == choices)
    let store = try #require(model.store)
    let programAvailable = (try? await store.candidateProgram(sibling.id)) != nil
    let rasterAvailable = (try? await store.candidateRaster(sibling.id)) != nil
    let previewAvailable = (try? await store.presentationPreview(.init(id: sibling.id, candidateID: sibling.id,
      revisionID: nil, sourceID: sibling.sourceID, removedIndices: []))) != nil
    let diagnostic: [String: Any] = ["siblingID": sibling.id.uuidString, "programAvailable": programAvailable,
      "rasterAvailable": rasterAvailable, "previewAvailable": previewAvailable,
      "drawingRefPresent": model.document?.candidates.first(where: { $0.id == sibling.id })?.drawing != nil]
    let evidence = URL(fileURLWithPath: ProcessInfo.processInfo.environment["FLOW_TEST_DIAGNOSTIC_OUTPUT"] ?? "/tmp/portrait-studio-evidence")
    try FileManager.default.createDirectory(at: evidence, withIntermediateDirectories: true)
    try JSONSerialization.data(withJSONObject: diagnostic, options: [.prettyPrinted, .sortedKeys])
      .write(to: evidence.appendingPathComponent("back-sibling-diagnostic.json"))
    #expect(programAvailable && rasterAvailable && previewAvailable)
    await model.exploreCandidate(sibling.id)
    #expect(model.error == nil && !model.needsRecovery && !model.isBusy)
    #expect(model.round?.parentCandidateID == sibling.id)
    #expect(model.document?.choices.count == (choices ?? 0) + 1 && model.document?.rounds.count == (rounds ?? 0) + 1)
    #expect(await model.shutdown())
  }

  @Test("Genuinely missing private history refuses before feedback and leaves only available offered choices")
  func expiredHistoryRefusal() async throws {
    let root = DrawingEditFixture.root(); defer { try? FileManager.default.removeItem(at: root) }
    let first = FlowAuthoringModel(directory: root, purpose: .validationFixture, render: FlowAuthoringFixture.render)
    await first.open(); await first.addPhoto(data: FlowAuthoringFixture.image(3), title: "Fixture")
    first.count = 3; await first.generate(refining: false)
    let candidates = first.roundCandidates, selected = candidates[0], expired = candidates[1]
    await first.selectCandidate(selected.id)
    let choices = first.document?.choices.count, rounds = first.document?.rounds.count
    let unretained = try #require(first.document).candidates.filter { $0.drawing == nil }
    #expect(Set(unretained.map(\.id)) == Set(candidates.dropFirst().map(\.id)))
    #expect(await first.shutdown())
    // Cold reopening normally rehydrates exact siblings. Remove only their
    // unretained private manifests to exercise a genuinely unavailable history.
    for candidate in unretained {
      try FileManager.default.removeItem(at: privateHistoryEntry(root, candidate: candidate))
    }
    #expect(FileManager.default.fileExists(atPath: privateHistoryEntry(root, candidate: selected).path))
    let model = FlowAuthoringModel(directory: root, render: FlowAuthoringFixture.render)
    await model.open()
    #expect(model.previews[expired.id] != nil && model.candidateUnavailableReason(expired) != nil)
    #expect(!model.canRefineCandidate(expired) && model.candidateUnavailableReason(selected) == nil)
    await model.exploreCandidate(expired.id)
    #expect(model.error != nil && !model.needsRecovery && model.pendingExplorationParentID == nil)
    #expect(model.document?.choices.count == choices && model.document?.rounds.count == rounds)
    let store = try #require(model.store)
    await #expect(throws: FlowPortfolioError.self) { try await store.chooseCandidate(expired.id) }
    #expect(await store.snapshot().choices.count == choices)
    await model.exploreCandidate(selected.id)
    let offered = try #require(model.document?.choices.last?.offeredCandidateIDs)
    #expect(offered == [selected.id])
    #expect(!model.needsRecovery && model.error == nil)
    #expect(await model.shutdown())
  }

  @Test("Committed crop preserves Photo bytes and grouping; explicit history restores its own input")
  func cropIdentity() async throws {
    let root = DrawingEditFixture.root(); defer { try? FileManager.default.removeItem(at: root) }
    let model = FlowAuthoringModel(directory: root, purpose: .validationFixture, render: FlowAuthoringFixture.render)
    await model.open(); await model.addPhoto(data: FlowAuthoringFixture.image(3), title: "Fixture")
    model.count = 3; await model.generate(refining: false)
    let original = try #require(model.selectedSource), oldRound = try #require(model.round)
    let crop = PortraitNormalizedRegion(x: 0.1, y: 0.2, width: 0.6, height: 0.5)
    model.invalidateRegionPreview(); #expect(!model.canSendToPlotter && model.recommendationCandidate == nil)
    await model.commitRegion(crop)
    #expect(model.round == nil && model.candidate == nil && model.committedAnalysisOptions.manualRegion == crop)
    #expect(model.selectedSource?.photo == original.photo && model.selectedSource?.image == original.image)
    #expect(model.selectedSource?.groupKeys == original.groupKeys)
    #expect(model.sourceData == FlowAuthoringFixture.image(3))
    await model.selectSource(original.id)
    #expect(model.round == nil && model.committedAnalysisOptions.manualRegion == crop)
    await model.selectRound(oldRound.id)
    #expect(model.committedAnalysisOptions == oldRound.analysisOptions)
    #expect(model.selectedSource?.authoringOptions?.manualRegion == crop)
    let beforeLibrary = try #require(model.drawingLibrary)
    let key = DrawingLibraryRecordKey(kind: "adaptiveplotter.flow-source/2", id: original.id)
    let beforeRow = try #require(await beforeLibrary.record(key))
    let persisted = try JSONDecoder().decode(FlowLibraryEntity<FlowPortfolioSource>.self, from: beforeRow.payload)
    #expect(persisted.value.authoringOptions?.manualRegion == crop)
    #expect(await model.shutdown())
    let reopened = FlowAuthoringModel(directory: root, render: FlowAuthoringFixture.render)
    await reopened.open()
    let reopenedStore = try #require(reopened.store), reopenedLibrary = try #require(reopened.drawingLibrary)
    let beforeSelection = await reopenedStore.snapshot()
    let reopenedRow = try #require(await reopenedLibrary.record(key))
    let beforeError = reopened.error
    #expect(reopened.committedAnalysisOptions == oldRound.analysisOptions)
    #expect(reopened.selectedSource?.authoringOptions?.manualRegion == crop)
    await reopened.selectSource(original.id)
    let afterSelection = await reopenedStore.snapshot()
    let afterRow = try #require(await reopenedLibrary.record(key))
    let diagnostic: [String: Any] = [
      "persistedSourceBeforeShutdown": try JSONSerialization.jsonObject(with: beforeRow.payload),
      "reopenedSourceRow": try JSONSerialization.jsonObject(with: reopenedRow.payload),
      "afterSelectSourceRow": try JSONSerialization.jsonObject(with: afterRow.payload),
      "reopenedStoreBeforeSelection": try JSONSerialization.jsonObject(with: DrawingArtifactCoding.encoder().encode(beforeSelection)),
      "reopenedStoreAfterSelection": try JSONSerialization.jsonObject(with: DrawingArtifactCoding.encoder().encode(afterSelection)),
      "modelErrorBeforeSelection": beforeError.map { $0 as Any } ?? NSNull(),
      "modelErrorAfterSelection": reopened.error.map { $0 as Any } ?? NSNull(),
      "needsRecovery": reopened.needsRecovery,
      "modelCurrentRoundIDAfterSelection": reopened.round.map { $0.id.uuidString as Any } ?? NSNull()]
    let evidence = URL(fileURLWithPath: ProcessInfo.processInfo.environment["FLOW_TEST_DIAGNOSTIC_OUTPUT"] ?? "/tmp/portrait-studio-evidence")
    try FileManager.default.createDirectory(at: evidence, withIntermediateDirectories: true)
    try JSONSerialization.data(withJSONObject: diagnostic, options: [.prettyPrinted, .sortedKeys])
      .write(to: evidence.appendingPathComponent("cropIdentity-reopen-diagnostic.json"))
    #expect(reopened.error == nil && !reopened.needsRecovery)
    #expect(reopened.round == nil && reopened.committedAnalysisOptions.manualRegion == crop)
    #expect(await reopened.shutdown())
  }

  @Test("Discarding a newer crop draft retains the same-photo region that already committed")
  func discardDraftAfterOlderRegionCommit() async throws {
    let root = DrawingEditFixture.root(); defer { try? FileManager.default.removeItem(at: root) }
    let model = FlowAuthoringModel(directory: root, purpose: .validationFixture, render: FlowAuthoringFixture.render)
    await model.open(); await model.addPhoto(data: FlowAuthoringFixture.image(4), title: "Fixture")
    model.count = 3; await model.generate(refining: false)
    await model.browseCandidate(try #require(model.roundCandidates.first).id)
    #expect(model.canSendToPlotter)
    let photo = model.currentPhotoRef, library = try #require(model.drawingLibrary)
    let regionA = PortraitNormalizedRegion(x: 0.1, y: 0.1, width: 0.7, height: 0.7)
    let gate = DrawingEditCommitGate(); try await library.editGate(gate)
    defer { gate.release() }
    model.invalidateRegionPreview()
    let savingA = Task { await model.commitRegion(regionA) }
    #expect(await gate.waitUntilHeld())
    // The view keeps draft B; the model invalidates only its render authority.
    model.invalidateRegionPreview()
    gate.release(); await savingA.value
    try await library.editFault(nil)
    #expect(model.regionPreviewPending && model.committedAnalysisOptions.manualRegion == regionA)
    #expect(model.round == nil && model.candidate == nil && model.program == nil)
    model.discardRegionPreview()
    #expect(!model.regionPreviewPending && model.currentPhotoRef == photo)
    #expect(model.selectedSource?.authoringOptions?.manualRegion == regionA)
    #expect(model.round == nil && !model.canSendToPlotter && model.error == nil && !model.needsRecovery)
    #expect(await model.shutdown())
  }

  @Test("Navigation cancels a held direct retention result while preserving its durable drawing")
  func retainedDrawingNavigationEpoch() async throws {
    let root = DrawingEditFixture.root(); defer { try? FileManager.default.removeItem(at: root) }
    let model = FlowAuthoringModel(directory: root, purpose: .validationFixture, render: FlowAuthoringFixture.render)
    await model.open(); await model.addPhoto(data: FlowAuthoringFixture.image(5), title: "Destination source")
    let destinationSource = try #require(model.selectedSource)
    await model.addPhoto(data: FlowAuthoringFixture.image(6), title: "Retained source")
    model.count = 3; await model.generate(refining: false)
    await model.browseCandidate(try #require(model.roundCandidates.first).id)
    let original = try #require(model.program), library = try #require(model.drawingLibrary)
    let gate = DrawingEditCommitGate(); try await library.editGate(gate)
    defer { gate.release() }
    let retaining = Task { () -> Result<Drawing, Error> in
      do { return .success(try await model.retainedDrawing()) }
      catch { return .failure(error) }
    }
    #expect(await gate.waitUntilHeld())
    let revision = model.generationIntentRevision
    let navigating = Task { await model.selectSource(destinationSource.id) }
    while model.generationIntentRevision == revision { await Task.yield() }
    gate.release(); await navigating.value
    switch await retaining.value {
    case .failure(let error): #expect(error is CancellationError)
    case .success: Issue.record("A superseded direct retention returned a Send drawing.")
    }
    try await library.editFault(nil)
    // The navigation may have met the active publication guard; retrying after
    // settlement is neutral and must never replay or remove the durable save.
    await model.selectSource(destinationSource.id)
    #expect(model.selectedSource?.id == destinationSource.id && model.program == nil)
    let retained = try await library.drawings().entries
    #expect(retained.count == 1 && model.document?.choices.isEmpty == true && !model.needsRecovery)
    let reference = try #require(retained.first?.reference)
    #expect(try await library.drawing(reference).program == original)
    #expect(await model.shutdown())
  }

  @Test("Actual preparation worker cancellation stops before candidate publication")
  func actualPreparationCancellation() async throws {
    let root = DrawingEditFixture.root(); defer { try? FileManager.default.removeItem(at: root) }
    let model = FlowAuthoringModel(directory: root, purpose: .validationFixture)
    await model.open(); await model.addPhoto(data: FlowAuthoringFixture.image(12), title: "Actual producer cancellation fixture")
    let generating = Task { await model.generate(refining: false) }
    var finished = false
    let joining = Task { await generating.value; finished = true }
    while !model.isPreparingGeneration && !finished { await Task.yield() }
    #expect(model.isPreparingGeneration)
    model.cancel(); await joining.value
    #expect(!model.isPreparingGeneration && model.roundCandidates.isEmpty && !model.isBusy)
    #expect(model.document?.rounds.isEmpty == true && !model.needsRecovery)
    #expect(await model.shutdown())
  }

  @Test("Completed tiles and Back replace active generation without stale commits", arguments: [false, true])
  func navigationDuringRender(back: Bool) async throws {
    let root = DrawingEditFixture.root(); defer { try? FileManager.default.removeItem(at: root) }
    let gate = ExplorationRenderGate()
    let model = FlowAuthoringModel(directory: root, purpose: .validationFixture, render: { data, recipe, style in
      await gate.pauseIfArmed()
      return try await FlowAuthoringFixture.render(data, recipe, style)
    })
    await model.open(); await model.addPhoto(data: FlowAuthoringFixture.image(6), title: "Fixture")
    model.count = 3; await model.generate(refining: false)
    let broad = try #require(model.round), parent = try #require(model.roundCandidates.first)
    await model.browseCandidate(parent.id)
    await gate.arm()
    let rendering = Task { await model.generate(refining: true) }
    await gate.waitUntilPaused()
    #expect(model.canNavigateExploration && !model.canEdit && !model.canSendToPlotter)
    let sketches = PortraitSketchCollection(library: try #require(model.drawingLibrary))
    let independent = PortraitLineEditModel(base: try DrawingEditFixture.value(), sketches: sketches)
    await independent.load(); #expect(independent.canEdit)
    independent.remove([try #require(independent.base.program.strokes.first?.id)])
    #expect(independent.remainingCount == 2)
    independent.close(); await sketches.shutdown()
    let interrupted = try #require(model.round), anchor = try #require(model.roundCandidates.first)
    let navigation = Task {
      if back { await model.selectRound(broad.id) }
      else { await model.exploreCandidate(anchor.id) }
    }
    // Admission occurs on MainActor before either durable operation can settle.
    while back ? model.pendingExplorationParentID != nil : model.pendingExplorationParentID != anchor.id { await Task.yield() }
    await gate.release(); await rendering.value; await navigation.value
    let saved = try #require(model.document?.rounds.first { $0.id == interrupted.id })
    #expect(saved.status == .cancelled && saved.candidateIDs.count == 1)
    if back {
      #expect(model.round?.id == broad.id && model.document?.choices.isEmpty == true)
    } else {
      #expect(model.round?.parentCandidateID == anchor.id && model.document?.choices.count == 1)
    }
    #expect(await model.shutdown())
  }

  @Test("Legacy loop parent is never reused or index-inherited under a sanitized recipe")
  func legacyLoopAnchor() async throws {
    let root = DrawingEditFixture.root(); defer { try? FileManager.default.removeItem(at: root) }
    let model = FlowAuthoringModel(directory: root, purpose: .validationFixture, render: FlowAuthoringFixture.render)
    await model.open(); await model.addPhoto(data: FlowAuthoringFixture.image(7), title: "Fixture")
    let source = try #require(model.selectedSource), store = try #require(model.store)
    let legacy = FlowArtistRecipe(values: FlowArtistRecipe.standard.values, marks: .init(loop: 1, scale: 0.5))
    let old = try await store.beginRound(sourceID: source.id, recipes: [legacy], analysisOptions: model.committedAnalysisOptions)
    let result = try await FlowAuthoringFixture.render(FlowAuthoringFixture.image(7), legacy, model.strokeStyle)
    let candidate = try await store.completeCandidate(roundID: old.id, slot: 0,
      production: StudioDrawingFixture.production(program: result.program, raster: result.raster),
      previewPNG: PortraitDrawingPreview.png(result.program))
    try await store.finishRound(old.id)
    await model.selectRound(old.id); await model.browseCandidate(candidate.id, prune: true)
    await model.edit(.remove, ids: [try #require(model.program?.strokes.first?.id)])
    let parentProgram = try #require(model.program)
    await model.generate(refining: true)
    let child = try #require(model.roundCandidates.first { $0.slot == 0 })
    #expect((child.recipe.marks?.loop ?? 0) == 0)
    #expect(model.document?.latestPrune(candidateID: child.id) == nil)
    #expect(try await store.candidateProgram(child.id) != parentProgram)
    #expect(try await store.candidateProgram(candidate.id) == parentProgram)
    #expect(await model.shutdown())
  }

  @Test("Same-ID candidate load retries a restored exact private closure without stale geometry")
  func retryMissingCandidate() async throws {
    let root = DrawingEditFixture.root(); defer { try? FileManager.default.removeItem(at: root) }
    let model = FlowAuthoringModel(directory: root, purpose: .validationFixture, render: FlowAuthoringFixture.render)
    await model.open(); await model.addPhoto(data: FlowAuthoringFixture.image(4), title: "Fixture")
    model.count = 3; await model.generate(refining: false)
    let first = try #require(model.roundCandidates.first), store = try #require(model.store)
    await model.browseCandidate(first.id)
    let exact = try await store.candidateProgram(first.id)
    let closure = privateHistoryEntry(root, candidate: first)
    let held = root.appendingPathComponent("held-private-" + first.id.uuidString.lowercased(), isDirectory: true)
    try FileManager.default.moveItem(at: closure, to: held)
    defer {
      if FileManager.default.fileExists(atPath: held.path) { try? FileManager.default.moveItem(at: held, to: closure) }
    }
    // RAM eviction alone must rehydrate from disk. With both exact tiers held
    // away, this is an actual unavailable load for the same candidate identity.
    _ = try #require(await store.takeTemporaryForRetry(first.id))
    await model.browseCandidate(first.id)
    await model.retryCandidateLoad()
    #expect(model.candidate?.id == first.id && model.program == nil && model.candidateLoadError != nil)
    #expect(!model.canEdit && !model.canSendToPlotter && !model.needsRecovery)
    try FileManager.default.moveItem(at: held, to: closure)
    await model.retryCandidateLoad()
    #expect(model.candidate?.id == first.id && model.program == exact && model.candidateLoadError == nil)
    #expect(model.canEdit && model.canSendToPlotter && model.candidateUnavailableReason(first) == nil)
    #expect(await model.shutdown())
  }

  @Test("Automatic baseline recommendation reuses exact neutral cold history without another render")
  func boundedRecommendation() async throws {
    let root = DrawingEditFixture.root(); defer { try? FileManager.default.removeItem(at: root) }
    let renders = ExplorationRenderCounter()
    let render: @Sendable (Data, FlowArtistRecipe, StrokeStyle) async throws -> PortraitRenderResult = { data, recipe, style in
      await renders.record()
      return try await FlowAuthoringFixture.render(data, recipe, style)
    }
    let model = FlowAuthoringModel(directory: root, purpose: .validationFixture, render: render)
    await model.open(); await model.addPhoto(data: FlowAuthoringFixture.image(8), title: "Fixture")
    await model.ensureRecommendation()
    let recommendation = try #require(model.recommendationCandidate), round = try #require(model.round)
    let program = try #require(model.program), preview = try #require(model.previews[recommendation.id])
    #expect(!model.isRecommendationPredictedFavorite)
    #expect(model.roundCandidates.count == 1 && model.document?.rounds.count == 1)
    #expect(model.document?.choices.isEmpty == true && model.canSendToPlotter)
    #expect(await renders.calls == 1)
    let library = try #require(model.drawingLibrary)
    #expect(try await library.drawings().entries.isEmpty)
    await model.ensureRecommendation()
    #expect(model.document?.rounds.count == 1)
    #expect(await renders.calls == 1)
    #expect(await model.shutdown())
    let reopened = FlowAuthoringModel(directory: root, render: render)
    await reopened.open(); await reopened.ensureRecommendation()
    #expect(reopened.document?.rounds.count == 1 && reopened.round?.id == round.id)
    #expect(reopened.recommendationCandidate?.id == recommendation.id && reopened.program == program)
    #expect(reopened.previews[recommendation.id] == preview && reopened.canSendToPlotter)
    #expect(await renders.calls == 1)
    #expect(reopened.document?.choices.isEmpty == true && reopened.document?.pruneRevisions.isEmpty == true)
    #expect(reopened.document?.rankings.isEmpty == true && reopened.document?.presentations.isEmpty == true)
    #expect(reopened.error == nil && !reopened.needsRecovery)
    let reopenedLibrary = try #require(reopened.drawingLibrary)
    #expect(try await reopenedLibrary.drawings().entries.isEmpty)
    #expect(await reopened.shutdown())
  }

  @Test("Opening a suggestion preserves its transient exact preview while a neutral broad set loads")
  func broadSuggestionAnchor() async throws {
    let root = DrawingEditFixture.root(); defer { try? FileManager.default.removeItem(at: root) }
    let gate = ExplorationRenderGate()
    let model = FlowAuthoringModel(directory: root, purpose: .validationFixture, render: { data, recipe, style in
      await gate.pauseIfArmed()
      return try await FlowAuthoringFixture.render(data, recipe, style)
    })
    await model.open(); await model.addPhoto(data: FlowAuthoringFixture.image(11), title: "Fixture")
    await model.ensureRecommendation()
    let suggestion = try #require(model.recommendationCandidate), exactPreview = try #require(model.previews[suggestion.id])
    await gate.arm()
    let entering = Task { await model.exploreRecommendation() }
    await gate.waitUntilPaused()
    #expect(model.pendingBroadAnchorID == suggestion.id && model.pendingBroadAnchorPreview == exactPreview)
    #expect(model.round?.parentCandidateID == nil && model.round?.explorationDepth == 0 && model.round?.refinementRadius == nil)
    #expect(model.document?.choices.isEmpty == true && model.pendingExplorationParentID == nil)
    await gate.release(); await entering.value
    #expect(model.pendingBroadAnchorID == nil && model.pendingBroadAnchorPreview == nil && model.document?.choices.isEmpty == true)
    #expect(await model.shutdown())
  }

  @Test("Obsolete automatic recommendation cannot reselect its source after navigation")
  func staleRecommendation() async throws {
    let root = DrawingEditFixture.root(); defer { try? FileManager.default.removeItem(at: root) }
    let gate = ExplorationRenderGate()
    let model = FlowAuthoringModel(directory: root, purpose: .validationFixture, render: { data, recipe, style in
      await gate.pauseIfArmed()
      return try await FlowAuthoringFixture.render(data, recipe, style)
    })
    await model.open(); await model.addPhoto(data: FlowAuthoringFixture.image(9), title: "First")
    let first = try #require(model.selectedSource)
    await model.addPhoto(data: FlowAuthoringFixture.image(10), title: "Second")
    let second = try #require(model.selectedSource)
    await model.selectSource(first.id); await gate.arm()
    let recommending = Task { await model.ensureRecommendation() }
    await gate.waitUntilPaused()
    let revision = model.generationIntentRevision
    let navigating = Task { await model.selectSource(second.id) }
    while model.generationIntentRevision == revision { await Task.yield() }
    await gate.release(); await recommending.value; await navigating.value
    #expect(model.selectedSource?.id == second.id && model.program == nil && model.candidate == nil)
    #expect(model.recommendationCandidate == nil && model.document?.choices.isEmpty == true)
    #expect(await model.shutdown())
  }

  @Test("Rapid duplicate tile clicks admit one exact offered-set choice and one child")
  func duplicateClickAdmission() async throws {
    let root = DrawingEditFixture.root(); defer { try? FileManager.default.removeItem(at: root) }
    let model = FlowAuthoringModel(directory: root, purpose: .validationFixture, render: FlowAuthoringFixture.render)
    await model.open(); await model.addPhoto(data: FlowAuthoringFixture.image(5), title: "Fixture")
    model.count = 3; await model.generate(refining: false)
    let parent = try #require(model.roundCandidates.first)
    let first = Task { await model.exploreCandidate(parent.id) }
    let second = Task { await model.exploreCandidate(parent.id) }
    await first.value; await second.value
    #expect(model.document?.choices.count == 1 && model.document?.rounds.count == 2)
    #expect(model.round?.parentCandidateID == parent.id && model.pendingExplorationParentID == nil)
    #expect(await model.shutdown())
  }
}

extension FlowPortfolioStore {
  fileprivate func takeTemporaryForRetry(_ id: UUID) -> Drawing? { temporaryDrawings.removeValue(forKey: id) }
}

private actor ExplorationRenderGate {
  private var armed = false
  private var paused = false
  private var releaseWaiter: CheckedContinuation<Void, Never>?
  private var pauseWaiter: CheckedContinuation<Void, Never>?
  func arm() { armed = true }
  func pauseIfArmed() async {
    guard armed else { return }
    armed = false; paused = true; pauseWaiter?.resume(); pauseWaiter = nil
    await withCheckedContinuation { releaseWaiter = $0 }
  }
  func waitUntilPaused() async {
    if paused { return }
    await withCheckedContinuation { pauseWaiter = $0 }
  }
  func release() { releaseWaiter?.resume(); releaseWaiter = nil; paused = false }
}

private func privateHistoryEntry(_ root: URL, candidate: FlowPortfolioCandidate) -> URL {
  if candidate.authoringClosureLocation?.storage == "library-assets/1", let closure = candidate.authoringClosure {
    // The identity-bound manifest is unique; source/input parts may be shared
    // with other candidates and must never be removed to simulate this fault.
    return root.appendingPathComponent("objects/sha256/" + closure.sha256)
  }
  return root.appendingPathComponent("flow-authoring-history-v1", isDirectory: true)
    .appendingPathComponent(candidate.id.uuidString.lowercased(), isDirectory: true)
}
private actor ExplorationRenderCounter {
  private(set) var calls = 0
  func record() { calls += 1 }
}
