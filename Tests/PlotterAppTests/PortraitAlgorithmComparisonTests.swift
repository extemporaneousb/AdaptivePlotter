import Foundation
import PlotterModel
import Testing

@testable import PlotterApp

@Suite("Portrait algorithm comparison")
@MainActor
struct PortraitAlgorithmComparisonTests {
  @Test("folded Styles render only the chosen algorithm for source, tuning and pen changes")
  func foldedWorkload() async throws {
    let renderer = ComparisonRenderer()
    let model = PortraitStudioModel(renderer: renderer)
    let pen = try portraitTestStyle()
    model.style = .sketch
    #expect(!model.isStyleComparisonExpanded)
    model.setPhoto(Data([1]), for: .front, strokeStyle: pen)
    await model.awaitRendering()
    #expect(await renderer.requests.count == 1)
    model.vectorOptions.simplificationTolerance += 0.2
    model.renderIfConfigurationChanged(strokeStyle: pen)
    await model.awaitRendering()
    #expect(await renderer.requests.count == 2)
    let wider = try StrokeStyle(nominalLineWidth: 1.2, penProfileID: pen.penProfileID)
    model.renderIfNeeded(strokeStyle: wider)
    await model.awaitRendering()
    #expect(await renderer.requests.count == 3)
    model.setPhoto(Data([2]), for: .front, strokeStyle: wider)
    await model.awaitRendering()
    let requests = await renderer.requests
    #expect(requests.count == 4)
    #expect(requests.allSatisfy { $0.style == .sketch })
    #expect(requests[1].cachedRaster != nil && requests[2].cachedRaster != nil)
    #expect(model.algorithmCandidates.map(\.recipe.style) == [.sketch])
    #expect(model.selectedCandidate?.sourceData == Data([2]))
    #expect(!model.isComparingAlgorithms)
    await model.shutdown()
  }

  @Test("opening renders two missing alternatives and reopening preserves cached candidate identities")
  func demandAndCacheReuse() async throws {
    let renderer = ComparisonRenderer()
    let model = PortraitStudioModel(renderer: renderer)
    let pen = try portraitTestStyle()
    model.setPhoto(Data([1]), for: .front, strokeStyle: pen)
    await model.awaitRendering()
    let selected = try #require(model.selectedCandidate)
    model.setStyleComparisonExpanded(true, strokeStyle: pen)
    #expect(model.selectedCandidate?.id == selected.id)
    #expect(!model.isProcessing)
    await model.awaitRendering()
    let identities = model.algorithmCandidates.map(\.id)
    #expect(identities.count == 3)
    let requests = await renderer.requests
    #expect(requests.count == 3)
    #expect(requests[1].cachedRaster == nil)
    #expect(requests[2].cachedRaster != nil)
    model.selectAlgorithm(.sketch, strokeStyle: pen)
    let chosen = try #require(model.selectedCandidate)
    model.setStyleComparisonExpanded(false, strokeStyle: pen)
    model.setStyleComparisonExpanded(true, strokeStyle: pen)
    await model.awaitRendering()
    #expect(await renderer.requests.count == 3)
    #expect(model.algorithmCandidates.map(\.id) == identities)
    #expect(model.selectedCandidate?.id == chosen.id)
    model.setStyleComparisonExpanded(false, strokeStyle: pen)
    model.vectorOptions.sketchThreshold += 0.002
    model.renderIfConfigurationChanged(strokeStyle: pen)
    await model.awaitRendering()
    #expect(await renderer.requests.count == 4)
    #expect(model.algorithmCandidates.map(\.id) == identities)
    #expect(model.selectedCandidate?.recipe.style == .sketch)
    await model.shutdown()
  }

  @Test("first opening after manual tuning uses the original source-context baselines")
  func lazyBaselineAfterTuning() async throws {
    let renderer = ComparisonRenderer()
    let model = PortraitStudioModel(renderer: renderer)
    let pen = try portraitTestStyle()
    model.setPhoto(Data([1]), for: .front, strokeStyle: pen)
    await model.awaitRendering()
    let initial = try #require(model.selectedCandidate)
    let baseline = model.vectorOptions
    model.vectorOptions.tonalStrength += 0.3
    model.renderIfConfigurationChanged(strokeStyle: pen)
    await model.awaitRendering()
    let tuned = try #require(model.selectedCandidate)
    model.setStyleComparisonExpanded(true, strokeStyle: pen)
    await model.awaitRendering()
    #expect(await renderer.requests.count == 4)
    #expect(model.selectedCandidate?.id == tuned.id)
    #expect(model.algorithmCandidates.allSatisfy { $0.recipe.vectorOptions == baseline })
    #expect(model.algorithmCandidates.first { $0.recipe.style == initial.recipe.style }?.id == initial.id)
    let references = try PortraitCandidateCoding.encoder().encode(model.algorithmCandidates)
    for tile in model.algorithmCandidates {
      model.selectAlgorithm(tile.recipe.style, strokeStyle: pen)
      model.renderIfConfigurationChanged(strokeStyle: pen)
      #expect(model.selectedCandidate?.id == tile.id)
      #expect(model.currentProgram == tile.program)
      #expect(model.vectorOptions == tile.recipe.vectorOptions)
      #expect(try PortraitCandidateCoding.encoder().encode(model.algorithmCandidates) == references)
    }
    #expect(await renderer.requests.count == 4)
    await model.shutdown()
  }

  @Test("a held style reference survives manual authoring changes and cannot replace the tuned drawing")
  func heldReferenceSurvivesTuning() async throws {
    let renderer = ComparisonRenderer(heldCall: 2)
    let model = PortraitStudioModel(renderer: renderer)
    let pen = try portraitTestStyle()
    let baseline = model.vectorOptions
    model.setStyleComparisonExpanded(true, strokeStyle: pen)
    model.setPhoto(Data([1]), for: .front, strokeStyle: pen)
    try await renderer.waitUntilHeld()
    let initialID = try #require(model.algorithmCandidates.first?.id)
    model.vectorOptions.tonalStrength += 0.3
    model.renderIfConfigurationChanged(strokeStyle: pen)
    #expect(model.algorithmCandidates.first?.id == initialID)
    let tuned = model.vectorOptions
    await renderer.release()
    await model.awaitRendering()
    #expect(await renderer.cancelledStyles.isEmpty)
    #expect(await renderer.requests.count == 4)
    #expect(model.selectedCandidate?.recipe.vectorOptions == tuned)
    #expect(model.algorithmCandidates.count == 3)
    #expect(model.algorithmCandidates.allSatisfy { $0.recipe.vectorOptions == baseline })
    #expect(model.algorithmCandidates.first?.id == initialID)
    #expect(model.workDiagnostics.maximumConcurrentWorkerCount == 1)
    await model.shutdown()
  }

  @Test("held style references survive neighbor, Current and Back without new style renders")
  func heldReferenceSurvivesTrajectory() async throws {
    let renderer = ComparisonRenderer()
    let model = PortraitStudioModel(renderer: renderer, explorationSeed: 918)
    model.style = .contours
    model.vectorOptions = PortraitVectorOptions()
    let pen = try portraitTestStyle()
    model.setPhoto(Data([1]), for: .front, strokeStyle: pen)
    await model.awaitRendering()
    let initialReference = try #require(model.algorithmCandidates.first)
    model.setExplorationEnabled(true, strokeStyle: pen)
    await model.awaitRendering()
    let first = try #require(model.explorationRound)
    let option = try #require(first.slots.first { $0.index != 1 && $0.candidate != nil })
    await renderer.holdNextCall()
    model.setStyleComparisonExpanded(true, strokeStyle: pen)
    try await renderer.waitUntilHeld()
    model.chooseExplorationSlot(option.index, roundID: first.id, strokeStyle: pen)
    #expect(model.selectedCandidate?.id == option.candidate?.id)
    #expect(model.algorithmCandidates.first?.id == initialReference.id)
    model.goBackExploration()
    #expect(model.selectedCandidate?.id == first.center.id)
    #expect(model.explorationRound?.id == first.id)
    model.chooseExplorationSlot(1, roundID: first.id, strokeStyle: pen)
    await renderer.release()
    await model.awaitRendering()
    #expect(await renderer.cancelledStyles.isEmpty)
    #expect(model.algorithmCandidates.count == 3)
    #expect(model.algorithmCandidates.first { $0.recipe.style == .contours }?.id == initialReference.id)
    let stableReferences = try PortraitCandidateCoding.encoder().encode(model.algorithmCandidates)
    let styleCalls = await renderer.requests.filter { $0.style != .contours }.count
    #expect(styleCalls == 2)
    for _ in 0..<3 {
      let current = try #require(model.explorationRound)
      model.chooseExplorationSlot(1, roundID: current.id, strokeStyle: pen)
      await model.awaitRendering()
      #expect(try PortraitCandidateCoding.encoder().encode(model.algorithmCandidates) == stableReferences)
      model.goBackExploration()
      #expect(model.explorationRound?.id == current.id)
      #expect(try PortraitCandidateCoding.encoder().encode(model.algorithmCandidates) == stableReferences)
    }
    #expect(await renderer.requests.filter { $0.style != .contours }.count == styleCalls)
    #expect(model.workDiagnostics.maximumConcurrentWorkerCount == 1)
    await model.shutdown()
  }

  @Test("reference jobs cannot satisfy newer authoring intent with the same render key but different lineage")
  func sameKeyDifferentLineage() async throws {
    let renderer = ComparisonRenderer(heldCall: 2, heldCalls: [3])
    let model = PortraitStudioModel(renderer: renderer)
    let pen = try portraitTestStyle()
    model.setStyleComparisonExpanded(true, strokeStyle: pen)
    model.setPhoto(Data([1]), for: .front, strokeStyle: pen)
    try await renderer.waitUntilHeld()
    let parent = try #require(model.selectedCandidate)
    model.style = .contours
    model.render(strokeStyle: pen, parent: parent)
    #expect(model.isProcessing)
    await renderer.release()
    // The explicit authoring request consumes the reference's cached vectors,
    // but prepares a distinct candidate with the requested lineage. A later
    // reference is held so we inspect the result before the drain completes.
    try await renderer.waitUntilHeld()
    let selected = try #require(model.selectedCandidate)
    #expect(selected.recipe.style == .contours)
    #expect(selected.lineage.parentID == parent.id)
    let reference = try #require(model.algorithmCandidates.first { $0.recipe.style == .contours })
    #expect(reference.lineage.parentID == nil)
    #expect(reference.id != selected.id)
    #expect(reference.program == selected.program)
    await renderer.release()
    await model.awaitRendering()
    #expect(model.selectedCandidate?.id == selected.id)
    #expect(await renderer.requests.count == 3)
    #expect(model.renderCacheHits == 1)
    await model.shutdown()
  }

  @Test("changing comparison context rejects a held reference", arguments: ["source", "framing", "material", "pen"])
  func heldReferenceContextReplacement(change: String) async throws {
    let renderer = ComparisonRenderer(heldCall: 2)
    let model = PortraitStudioModel(renderer: renderer)
    let pen = try portraitTestStyle()
    model.setStyleComparisonExpanded(true, strokeStyle: pen)
    model.setPhoto(Data([1]), for: .front, strokeStyle: pen)
    try await renderer.waitUntilHeld()
    let oldID = try #require(model.algorithmCandidates.first?.id)
    var nextPen = pen
    if change == "source" {
      model.setPhoto(Data([2]), for: .front, strokeStyle: pen)
    } else {
      if change == "framing" { model.options.faceCropMargin += 0.1 }
      if change == "material" {
        model.vectorOptions.materialContext = try .init(
          profile: .init(name: "New reference material", nominalWidthMM: 0.4), drawingHeightMM: 100)
      }
      if change == "pen" { nextPen = try .init(nominalLineWidth: 1.2, penProfileID: pen.penProfileID) }
      model.renderIfNeeded(strokeStyle: nextPen)
    }
    #expect(model.algorithmCandidates.isEmpty)
    await renderer.release()
    await model.awaitRendering()
    #expect(await renderer.cancelledStyles == [.contours])
    #expect(model.algorithmCandidates.count == 3)
    #expect(!model.algorithmCandidates.contains { $0.id == oldID })
    #expect(model.algorithmCandidates.allSatisfy {
      $0.photoID == model.selectedPhotoID && $0.recipe.analysisOptions == model.options
        && $0.recipe.vectorOptions.materialContext == model.vectorOptions.materialContext
        && $0.program.strokes.allSatisfy { $0.style == nextPen }
    })
    #expect(model.workDiagnostics.maximumConcurrentWorkerCount == 1)
    await model.shutdown()
  }

  @Test("global Cancel prevents a canceled reference from being reused by authoring restarted before settlement")
  func canceledReferenceCannotSatisfyRestart() async throws {
    let renderer = ComparisonRenderer(heldCall: 2)
    let model = PortraitStudioModel(renderer: renderer)
    let pen = try portraitTestStyle()
    let baseline = model.vectorOptions
    model.setStyleComparisonExpanded(true, strokeStyle: pen)
    model.setPhoto(Data([1]), for: .front, strokeStyle: pen)
    try await renderer.waitUntilHeld()
    let initialReference = try #require(model.algorithmCandidates.first)
    let cancellation = Task { await model.cancelRendering() }
    let deadline = ContinuousClock.now.advanced(by: .seconds(5))
    while model.isComparingAlgorithms {
      try #require(ContinuousClock.now < deadline, "Global cancellation did not stop comparison demand.")
      try await Task.sleep(for: .milliseconds(1))
    }
    // Cancel is joining the held reference. A newer user request must enqueue
    // its missing baseline again, even though source context and style key match.
    model.vectorOptions.tonalStrength += 0.3
    let tuned = model.vectorOptions
    model.renderIfConfigurationChanged(strokeStyle: pen)
    #expect(await renderer.requests.count == 2)
    await renderer.release()
    await cancellation.value
    await model.awaitRendering()
    #expect(await renderer.cancelledStyles == [.contours])
    #expect(await renderer.requests.count == 5)
    #expect(model.algorithmCandidates.count == 3)
    #expect(model.algorithmCandidates.allSatisfy { $0.recipe.vectorOptions == baseline })
    #expect(model.algorithmCandidates.first?.id == initialReference.id)
    #expect(model.selectedCandidate?.recipe.vectorOptions == tuned)
    #expect(model.currentProgram != nil)
    #expect(model.workDiagnostics.maximumConcurrentWorkerCount == 1)
    #expect(model.workDiagnostics.startedWorkerCount == model.workDiagnostics.settledWorkerCount)
    await model.shutdown()
  }

  @Test("folding cancels an active alternative and late results cannot publish", arguments: [false, true])
  func foldingHeldAlternative(reopenBeforeSettlement: Bool) async throws {
    let renderer = ComparisonRenderer(heldCall: 2)
    let model = PortraitStudioModel(renderer: renderer)
    let pen = try portraitTestStyle()
    model.setStyleComparisonExpanded(true, strokeStyle: pen)
    model.setPhoto(Data([1]), for: .front, strokeStyle: pen)
    try await renderer.waitUntilHeld()
    let selected = try #require(model.selectedCandidate)
    model.setStyleComparisonExpanded(false, strokeStyle: pen)
    #expect(!model.isComparingAlgorithms)
    #expect(!model.isProcessing)
    #expect(model.selectedCandidate?.id == selected.id)
    if reopenBeforeSettlement {
      // Repeated disclosure changes must not reuse the cancelled worker or
      // create a second expensive task while it is still settling.
      for _ in 0..<3 {
        model.setStyleComparisonExpanded(true, strokeStyle: pen)
        model.setStyleComparisonExpanded(false, strokeStyle: pen)
      }
      model.setStyleComparisonExpanded(true, strokeStyle: pen)
    }
    await renderer.release()
    await model.awaitRendering()
    #expect(await renderer.cancelledStyles == [.contours])
    #expect(model.selectedCandidate?.id == selected.id)
    if !reopenBeforeSettlement {
      #expect(await renderer.requests.count == 2)
      #expect(model.algorithmCandidates.map(\.recipe.style) == [.flowEdges])
      model.setStyleComparisonExpanded(true, strokeStyle: pen)
      await model.awaitRendering()
    }
    #expect(await renderer.requests.count == 4)
    #expect(model.algorithmCandidates.map(\.recipe.style) == PortraitStyle.authoringCases)
    #expect(model.selectedCandidate?.id == selected.id)
    #expect(model.workDiagnostics.maximumConcurrentWorkerCount == 1)
    #expect(model.workDiagnostics.startedWorkerCount == model.workDiagnostics.settledWorkerCount)
    await model.shutdown()
  }

  @Test("folding while the selected render is held preserves that worker and drops alternatives")
  func foldingHeldSelection() async throws {
    let renderer = ComparisonRenderer(heldCall: 1)
    let model = PortraitStudioModel(renderer: renderer)
    let pen = try portraitTestStyle()
    model.setStyleComparisonExpanded(true, strokeStyle: pen)
    model.setPhoto(Data([1]), for: .front, strokeStyle: pen)
    try await renderer.waitUntilHeld()
    model.setStyleComparisonExpanded(false, strokeStyle: pen)
    #expect(model.isProcessing)
    await renderer.release()
    await model.awaitRendering()
    #expect(await renderer.requests.count == 1)
    #expect(await renderer.cancelledStyles.isEmpty)
    #expect(model.selectedCandidate?.recipe.style == .flowEdges)
    #expect(!model.isProcessing)
    #expect(!model.isComparingAlgorithms)
    await model.shutdown()
  }

  @Test("active algorithms share compatible analysis and selecting installs the exact tile")
  func exactSelectionAndSharedAnalysis() async throws {
    let renderer = ComparisonRenderer()
    let model = PortraitStudioModel(renderer: renderer)
    let pen = try portraitTestStyle()
    model.vectorOptions.headScale = 1.4
    model.vectorOptions.semanticHead = .init()
    model.setStyleComparisonExpanded(true, strokeStyle: pen)
    model.setPhoto(Data([1]), for: .front, strokeStyle: pen)
    await model.awaitRendering()
    #expect(model.algorithmCandidates.map(\.recipe.style) == PortraitStyle.authoringCases)
    #expect(model.algorithmCandidates.allSatisfy { $0.sourceData == Data([1]) })
    #expect(Set(model.algorithmCandidates.map(\.rasterSHA256)).count == 1)
    #expect(model.algorithmCandidates.allSatisfy {
      $0.checkpointID == nil && $0.proposal == nil && $0.warpManifest == nil
        && $0.recipe.vectorOptions.headScale == 1 && $0.recipe.vectorOptions.semanticHead == nil
    })
    let requests = await renderer.requests
    #expect(requests.count == PortraitStyle.authoringCases.count)
    #expect(requests.filter { $0.cachedRaster == nil }.count == 2)
    #expect(model.selectedAlgorithm == .flowEdges)
    for tile in model.algorithmCandidates {
      model.selectAlgorithm(tile.recipe.style, strokeStyle: pen)
      model.renderIfConfigurationChanged(strokeStyle: pen)
      #expect(model.selectedCandidate?.id == tile.id)
      #expect(model.selectedCandidate?.createdAt == tile.createdAt)
      #expect(model.currentProgram == tile.program)
      #expect(model.selectedPhoto == tile.sourceData)
      #expect(model.renderConfiguration == .init(style: tile.recipe.style,
        vectors: tile.recipe.vectorOptions, analysis: tile.recipe.analysisOptions))
    }
    // Returning to the Studio does not reset selection or enqueue more work.
    model.renderIfNeeded(strokeStyle: pen)
    #expect(await renderer.requests.count == requests.count)
    #expect(model.selectedAlgorithm == .sketch)
    #expect(model.workDiagnostics.maximumConcurrentWorkerCount == 1)
    #expect(!model.isComparingAlgorithms)
    await model.shutdown()
  }

  @Test("source and framing supersession discard held work and all stale algorithm jobs")
  func supersededComparison() async throws {
    let renderer = ComparisonRenderer(heldCall: 1)
    let model = PortraitStudioModel(renderer: renderer)
    let pen = try portraitTestStyle()
    model.setStyleComparisonExpanded(true, strokeStyle: pen)
    model.setPhoto(Data([1]), for: .front, strokeStyle: pen)
    try await renderer.waitUntilHeld()
    model.options.cropToFace = false
    model.vectorOptions.hatchSpacing = 7
    model.renderIfConfigurationChanged(strokeStyle: pen)
    model.setPhoto(Data([2]), for: .front, strokeStyle: pen)
    #expect(model.algorithmCandidates.isEmpty)
    #expect(model.currentProgram == nil)
    await renderer.release()
    await model.awaitRendering()
    #expect(model.algorithmCandidates.count == PortraitStyle.authoringCases.count)
    #expect(model.algorithmCandidates.allSatisfy {
      $0.sourceData == Data([2]) && !$0.recipe.analysisOptions.cropToFace
        && $0.recipe.vectorOptions.hatchSpacing == 7
        && $0.photoID == model.selectedPhotoID
    })
    let requests = await renderer.requests
    #expect(requests.count == PortraitStyle.authoringCases.count + 1)
    #expect(requests.dropFirst().allSatisfy { $0.data == Data([2]) })
    #expect(model.workDiagnostics.maximumConcurrentWorkerCount == 1)
    #expect(model.workDiagnostics.startedWorkerCount == model.workDiagnostics.settledWorkerCount)
    await model.shutdown()
  }

  @Test("late comparison tiles cannot change the selected drawing")
  func selectionDuringComparison() async throws {
    let renderer = ComparisonRenderer(heldCall: 3)
    let model = PortraitStudioModel(renderer: renderer)
    let pen = try portraitTestStyle()
    model.setStyleComparisonExpanded(true, strokeStyle: pen)
    model.setPhoto(Data([1]), for: .front, strokeStyle: pen)
    try await renderer.waitUntilHeld()
    let tile = try #require(model.algorithmCandidates.first { $0.recipe.style == .contours })
    model.selectAlgorithm(.contours, strokeStyle: pen)
    model.renderIfConfigurationChanged(strokeStyle: pen)
    await renderer.release()
    await model.awaitRendering()
    #expect(model.selectedCandidate?.id == tile.id)
    #expect(model.selectedCandidate?.createdAt == tile.createdAt)
    #expect(model.currentProgram == tile.program)
    #expect(model.algorithmCandidates.count == 3)
    #expect(await renderer.requests.count == 3)
    await model.shutdown()
  }

  @Test("pen changes replace every algorithm result while preserving current source analysis")
  func penInvalidation() async throws {
    let renderer = ComparisonRenderer()
    let model = PortraitStudioModel(renderer: renderer)
    let pen = try portraitTestStyle()
    model.setStyleComparisonExpanded(true, strokeStyle: pen)
    model.setPhoto(Data([1]), for: .front, strokeStyle: pen)
    await model.awaitRendering()
    let oldIDs = model.algorithmCandidates.map(\.id)
    let wider = try StrokeStyle(nominalLineWidth: 1.2, penProfileID: pen.penProfileID)
    model.renderIfNeeded(strokeStyle: wider)
    #expect(model.algorithmCandidates.isEmpty)
    await model.awaitRendering()
    #expect(model.algorithmCandidates.count == 3)
    #expect(model.algorithmCandidates.map(\.id) != oldIDs)
    #expect(model.algorithmCandidates.allSatisfy {
      $0.program.strokes.allSatisfy { $0.style == wider }
    })
    let requests = await renderer.requests
    #expect(requests.count == 6)
    #expect(requests.dropFirst(3).allSatisfy { $0.cachedRaster != nil })
    let selected = model.selectedCandidate?.id
    model.selectAlgorithm(.contours, strokeStyle: pen)
    #expect(model.selectedCandidate?.id == selected)
    await model.shutdown()
  }

  @Test("saving and projection retain exact drawings without changing authoring selection")
  func retentionDoesNotNavigate() async throws {
    let model = PortraitStudioModel(renderer: ComparisonRenderer())
    let pen = try portraitTestStyle()
    model.renderIfNeeded(strokeStyle: pen)
    model.setPhoto(Data([1]), for: .front, strokeStyle: pen)
    await model.awaitRendering()
    let candidate = try #require(model.selectedCandidate)
    #expect(model.keepSelection() == nil)
    #expect(model.sketches.selectedID == nil)
    #expect(model.selectedCandidate?.id == candidate.id)
    #expect(await model.acceptProjection(candidate) { nil } == nil)
    #expect(model.sketches.selectedID == nil)
    #expect(model.projectedCandidate?.id == candidate.id)
    #expect(model.sketches.entries.map(\.id) == [candidate.id])
    model.setPhoto(Data([2]), for: .front, strokeStyle: pen)
    await model.awaitRendering()
    model.sketches.selectedID = candidate.id
    #expect(model.selectedPhoto == candidate.sourceData)
    #expect(model.selectedPhoto != model.recentPhotos.last?.data)
    await model.shutdown()
  }

  @Test("deleting a burst cancels its selected held render and does not resurrect its source")
  func deleteHeldBurst() async throws {
    let renderer = ComparisonRenderer(heldCall: 1)
    let model = PortraitStudioModel(renderer: renderer)
    let pen = try portraitTestStyle()
    model.renderIfNeeded(strokeStyle: pen)
    model.setPhoto(Data([1]), for: .front, strokeStyle: pen)
    try await renderer.waitUntilHeld()
    model.removeSelectedBurst(strokeStyle: pen)
    #expect(model.algorithmCandidates.isEmpty)
    #expect(model.recentPhotos.isEmpty)
    await renderer.release()
    await model.awaitRendering()
    #expect(model.selectedPhoto == nil)
    #expect(model.currentProgram == nil)
    #expect(model.selectedCandidate == nil)
    #expect(model.algorithmCandidates.isEmpty)
    #expect(await renderer.requests.count == 1)
    #expect(!model.isComparingAlgorithms)
    #expect(model.workDiagnostics.activeWorkerCount == 0)
    await model.shutdown()
  }
}

private actor ComparisonRenderer: PortraitRendering {
  private(set) var requests: [PortraitRenderRequest] = []
  private(set) var cancelledStyles: [PortraitStyle] = []
  private var heldCalls: Set<Int>
  private var waiter: CheckedContinuation<Void, Never>?

  init(heldCall: Int? = nil, heldCalls: Set<Int> = []) {
    self.heldCalls = heldCalls.union(heldCall.map { [$0] } ?? [])
  }

  func holdNextCall() { heldCalls.insert(requests.count + 1) }

  func render(_ request: PortraitRenderRequest) async throws -> PortraitRenderResult {
    requests.append(request)
    let raster = request.cachedRaster ?? portraitTestRaster()
    let result = PortraitRenderResult(raster: raster, program: try PortraitVectorizer.program(from: raster,
      pose: request.pose, style: request.style, strokeStyle: request.strokeStyle,
      vectorOptions: request.vectorOptions))
    if heldCalls.contains(requests.count) {
      await withCheckedContinuation { waiter = $0 }
    }
    if Task.isCancelled { cancelledStyles.append(request.style) }
    // Return an already-completed result even after cancellation, so these
    // tests exercise the model's revision/source publication guards.
    return result
  }

  func waitUntilHeld() async throws {
    let deadline = ContinuousClock.now.advanced(by: .seconds(5))
    while waiter == nil {
      try #require(ContinuousClock.now < deadline)
      try await Task.sleep(for: .milliseconds(1))
    }
  }

  func release() { waiter?.resume(); waiter = nil }
}
