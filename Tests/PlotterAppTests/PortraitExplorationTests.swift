import Foundation
import PlotterModel
import Testing

@testable import PlotterApp

@Suite("Portrait exploration ownership")
@MainActor
struct PortraitExplorationTests {
  @Test("a new source leaves retired archive styles and preserves the material snapshot")
  func newSourceUsesActiveStyle() async throws {
    let model = PortraitStudioModel(renderer: ExplorationTestRenderer())
    let material = try PortraitMaterialContext(
      profile: .init(name: "Retained material", nominalWidthMM: 0.4), drawingHeightMM: 100)
    model.style = .hatch
    model.vectorOptions.materialContext = material
    model.setPhoto(Data([1]), for: .front, strokeStyle: try portraitTestStyle())
    #expect(model.style == .flowEdges)
    #expect(model.vectorOptions.materialContext == material)
    #expect(model.vectorOptions.hatchSpacing == PortraitVectorOptions.flowDefaults.hatchSpacing)
    await model.awaitRendering()
    #expect(model.selectedCandidate?.recipe.style == .flowEdges)
    await model.shutdown()
  }

  @Test("neighbor promotion and center resampling preserve exact candidates and Back grids")
  func exactTransitions() async throws {
    let renderer = ExplorationTestRenderer()
    let model = PortraitStudioModel(renderer: renderer, explorationSeed: 918)
    model.style = .contours
    model.vectorOptions = PortraitVectorOptions()
    let pen = try portraitTestStyle()
    model.setPhoto(Data([1]), for: .front, strokeStyle: pen)
    await model.awaitRendering()
    let original = try #require(model.selectedCandidate)
    model.setExplorationEnabled(true, strokeStyle: pen)
    await model.awaitRendering()
    let first = try #require(model.explorationRound)
    #expect(first.slots.count == 3)
    #expect(first.slots.map(\.index) == Array(0..<3))
    #expect(try candidateBytes(first.center) == candidateBytes(original))
    #expect(try candidateBytes(#require(first.slots[1].candidate)) == candidateBytes(original))
    let neighbor = try #require(first.slots.first { $0.index != 1 && $0.candidate != nil })
    let chosen = try #require(neighbor.candidate)
    model.chooseExplorationSlot(neighbor.index, roundID: first.id, strokeStyle: pen)
    #expect(try candidateBytes(#require(model.selectedCandidate)) == candidateBytes(chosen))
    await model.awaitRendering()
    let second = try #require(model.explorationRound)
    #expect(try candidateBytes(second.center) == candidateBytes(chosen))
    let calls = await renderer.requests.count
    model.goBackExploration()
    let restored = try #require(model.explorationRound)
    #expect(try roundBytes(restored) == roundBytes(first))
    #expect(await renderer.requests.count == calls)
    model.chooseExplorationSlot(1, roundID: restored.id, strokeStyle: pen)
    await model.awaitRendering()
    let resampled = try #require(model.explorationRound)
    #expect(resampled.id != first.id)
    #expect(resampled.seed != first.seed)
    #expect(try candidateBytes(resampled.center) == candidateBytes(original))
    model.goBackExploration()
    #expect(try roundBytes(#require(model.explorationRound)) == roundBytes(first))
    await model.shutdown()
  }

  @Test("preferring Current shrinks the internal step and Back restores the exact search state")
  func adaptivePreferenceAndBack() async throws {
    let renderer = ExplorationTestRenderer()
    let model = PortraitStudioModel(renderer: renderer, explorationSeed: 7)
    model.style = .contours
    model.vectorOptions = PortraitVectorOptions()
    let pen = try portraitTestStyle()
    model.setPhoto(Data([1]), for: .front, strokeStyle: pen)
    await model.awaitRendering()
    model.setExplorationEnabled(true, strokeStyle: pen)
    await model.awaitRendering()
    let first = try #require(model.explorationRound)
    let originalSearch = model.explorationSearch
    model.chooseExplorationSlot(1, roundID: first.id, strokeStyle: pen)
    #expect(model.explorationSearch.step < originalSearch.step)
    #expect(try candidateBytes(#require(model.selectedCandidate)) == candidateBytes(first.center))
    await model.awaitRendering()
    model.goBackExploration()
    #expect(try roundBytes(#require(model.explorationRound)) == roundBytes(first))
    #expect(model.explorationSearch == originalSearch)
    await model.shutdown()
  }

  @Test("stale tile identities cannot select a different round and manual edits reset history")
  func staleChoiceAndManualEdit() async throws {
    let model = PortraitStudioModel(renderer: ExplorationTestRenderer(), explorationSeed: 13)
    model.style = .contours
    model.vectorOptions = PortraitVectorOptions()
    let pen = try portraitTestStyle()
    model.setPhoto(Data([1]), for: .front, strokeStyle: pen)
    await model.awaitRendering()
    model.setExplorationEnabled(true, strokeStyle: pen)
    await model.awaitRendering()
    let first = try #require(model.explorationRound)
    model.resampleExploration(roundID: first.id, strokeStyle: pen)
    await model.awaitRendering()
    let second = try #require(model.explorationRound)
    model.chooseExplorationSlot(0, roundID: first.id, strokeStyle: pen)
    #expect(try roundBytes(#require(model.explorationRound)) == roundBytes(second))
    model.vectorOptions.tonalStrength = 1.65
    model.renderIfConfigurationChanged(strokeStyle: pen)
    await model.awaitRendering()
    let edited = try #require(model.explorationRound)
    #expect(edited.center.recipe.vectorOptions.tonalStrength == 1.65)
    #expect(!model.canGoBackExploration)
    #expect(edited.center.id != second.center.id)
    #expect(edited.slots.compactMap(\.candidate).allSatisfy {
      $0.photoID == edited.center.photoID && $0.recipe.style == edited.center.recipe.style
        && $0.recipe.analysisOptions == edited.center.recipe.analysisOptions
    })
    await model.shutdown()
  }

  @Test("source removal cannot be undone by a renderer that ignores cancellation")
  func removedSourceRejectsLateResult() async throws {
    let renderer = ExplorationTestRenderer()
    let model = PortraitStudioModel(renderer: renderer)
    model.style = .contours
    model.vectorOptions = PortraitVectorOptions()
    let pen = try portraitTestStyle()
    model.setPhoto(Data([1]), for: .front, strokeStyle: pen)
    await model.awaitRendering()
    let photo = try #require(model.selectedPhotoID)
    await renderer.holdNext()
    model.setExplorationEnabled(true, strokeStyle: pen)
    try await renderer.waitUntilHeld()
    model.removePhoto(photo, strokeStyle: pen)
    await renderer.release()
    await model.awaitRendering()
    #expect(model.explorationRound == nil)
    #expect(model.selectedCandidate == nil)
    #expect(!model.canGoBackExploration)
    #expect(model.recentPhotos.isEmpty)
    #expect(model.workDiagnostics.maximumConcurrentWorkerCount == 1)
    await model.shutdown()
  }

  @Test("source replacement joins old work and publishes only the new source")
  func sourceReplacementRejectsLateResult() async throws {
    let renderer = ExplorationTestRenderer()
    let model = PortraitStudioModel(renderer: renderer)
    model.style = .contours
    model.vectorOptions = PortraitVectorOptions()
    let pen = try portraitTestStyle()
    model.setPhoto(Data([1]), for: .front, strokeStyle: pen)
    await model.awaitRendering()
    await renderer.holdNext()
    model.setExplorationEnabled(true, strokeStyle: pen)
    try await renderer.waitUntilHeld()
    model.setPhoto(Data([2]), for: .front, strokeStyle: pen)
    await renderer.release()
    await model.awaitRendering()
    let round = try #require(model.explorationRound)
    #expect(round.center.sourceData == Data([2]))
    #expect(round.slots.compactMap(\.candidate).allSatisfy { $0.sourceData == Data([2]) })
    #expect(!model.canGoBackExploration)
    #expect(model.workDiagnostics.maximumConcurrentWorkerCount == 1)
    await model.shutdown()
  }

  @Test("Current and Back immediately cancel pending alternatives and reject their late result")
  func pendingCurrentAndBack() async throws {
    let renderer = ExplorationTestRenderer()
    let model = PortraitStudioModel(renderer: renderer)
    model.style = .contours
    model.vectorOptions = PortraitVectorOptions()
    let pen = try portraitTestStyle()
    model.setPhoto(Data([1]), for: .front, strokeStyle: pen)
    await model.awaitRendering()
    model.setExplorationEnabled(true, strokeStyle: pen)
    await model.awaitRendering()
    let first = try #require(model.explorationRound)
    let calls = await renderer.requests.count
    await renderer.holdNext()
    model.resampleExploration(roundID: first.id, strokeStyle: pen)
    try await renderer.waitUntilHeld()
    let pendingID = try #require(model.explorationDisplayID)
    #expect(model.isExploring)
    model.chooseExplorationSlot(1, roundID: pendingID, strokeStyle: pen)
    #expect(!model.isExploring)
    #expect(model.explorationRound?.id == pendingID)
    #expect(model.selectedCandidate?.id == first.center.id)
    #expect(await renderer.requests.count == calls + 1)
    model.goBackExploration()
    #expect(try roundBytes(#require(model.explorationRound)) == roundBytes(first))
    model.chooseExplorationSlot(1, roundID: pendingID, strokeStyle: pen)
    #expect(model.explorationRound?.id == first.id)
    await renderer.release()
    await model.awaitRendering()
    #expect(try roundBytes(#require(model.explorationRound)) == roundBytes(first))
    #expect(await renderer.requests.count == calls + 1)
    #expect(model.workDiagnostics.maximumConcurrentWorkerCount == 1)
    await model.shutdown()
  }

  @Test("failed proposals are bounded unavailable slots while center remains usable")
  func invalidProposals() async throws {
    let renderer = ExplorationTestRenderer()
    let model = PortraitStudioModel(renderer: renderer)
    model.style = .contours
    model.vectorOptions = PortraitVectorOptions()
    let pen = try portraitTestStyle()
    model.setPhoto(Data([1]), for: .front, strokeStyle: pen)
    await model.awaitRendering()
    let center = try #require(model.selectedCandidate)
    await renderer.rejectFutureRequests()
    model.setExplorationEnabled(true, strokeStyle: pen)
    await model.awaitRendering()
    let round = try #require(model.explorationRound)
    #expect(round.slots.count == 3)
    #expect(round.slots.filter { $0.index != 1 }.allSatisfy {
      $0.candidate == nil && !($0.unavailableReason ?? "").isEmpty
    })
    #expect(try candidateBytes(#require(model.selectedCandidate)) == candidateBytes(center))
    #expect(await renderer.requests.count <= 1 + 2 * 2)
    #expect(!model.isExploring)
    #expect(model.keepSelection() == nil)
    await model.shutdown()
  }

  @Test("explicit handoff freezes the chosen program while exploration continues")
  func handoffIsolation() async throws {
    let model = PortraitStudioModel(renderer: ExplorationTestRenderer())
    model.style = .contours
    model.vectorOptions = PortraitVectorOptions()
    let pen = try portraitTestStyle()
    model.setPhoto(Data([1]), for: .front, strokeStyle: pen)
    await model.awaitRendering()
    model.setExplorationEnabled(true, strokeStyle: pen)
    await model.awaitRendering()
    let first = try #require(model.explorationRound)
    let accepted = try #require(model.selectedCandidate)
    #expect(await model.acceptProjection(accepted, perform: { nil }) == nil)
    let slot = try #require(first.slots.first { $0.index != 1 && $0.candidate != nil })
    model.chooseExplorationSlot(slot.index, roundID: first.id, strokeStyle: pen)
    await model.awaitRendering()
    #expect(model.selectedCandidate?.id != accepted.id)
    #expect(try candidateBytes(#require(model.projectedCandidate)) == candidateBytes(accepted))
    #expect(model.sketches.entries.first?.candidate.program == accepted.program)
    #expect(model.sketches.entries.count == 1)
    await model.shutdown()
  }

  @Test("expanded algorithm comparisons follow promoted and restored center recipes")
  func expandedStylesRemainCoherent() async throws {
    let model = PortraitStudioModel(renderer: ExplorationTestRenderer())
    model.style = .contours
    model.vectorOptions = PortraitVectorOptions()
    let pen = try portraitTestStyle()
    model.setPhoto(Data([1]), for: .front, strokeStyle: pen)
    await model.awaitRendering()
    model.setStyleComparisonExpanded(true, strokeStyle: pen)
    model.setExplorationEnabled(true, strokeStyle: pen)
    await model.awaitRendering()
    let first = try #require(model.explorationRound)
    let slot = try #require(first.slots.first { $0.index != 1 && $0.candidate != nil })
    let selected = try #require(slot.candidate)
    model.chooseExplorationSlot(slot.index, roundID: first.id, strokeStyle: pen)
    await model.awaitRendering()
    #expect(model.selectedCandidate?.id == selected.id)
    #expect(model.algorithmCandidates.count == PortraitStyle.authoringCases.count)
    #expect(model.algorithmCandidates.allSatisfy {
      $0.recipe.vectorOptions == selected.recipe.vectorOptions
    })
    model.goBackExploration()
    await model.awaitRendering()
    #expect(try roundBytes(#require(model.explorationRound)) == roundBytes(first))
    #expect(model.algorithmCandidates.count == PortraitStyle.authoringCases.count)
    #expect(model.algorithmCandidates.allSatisfy {
      $0.recipe.vectorOptions == first.center.recipe.vectorOptions
    })
    await model.shutdown()
  }

  @Test("save/load retains bounded offered recipes and choices, and deletion removes them")
  func archiveTraceAndHistoryBounds() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("portrait-grid-\(UUID())")
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = PortraitCandidateStore(directoryURL: directory)
    let renderer = ExplorationTestRenderer()
    let model = PortraitStudioModel(renderer: renderer, candidateStore: store)
    model.style = .contours
    model.vectorOptions = PortraitVectorOptions()
    let pen = try portraitTestStyle()
    model.setPhoto(Data([1]), for: .front, strokeStyle: pen)
    await model.awaitRendering()
    await renderer.rejectFutureRequests()
    model.setExplorationEnabled(true, strokeStyle: pen)
    await model.awaitRendering()
    let calls = await renderer.requests.count
    var retainedRounds: [PortraitExplorationRound] = []
    for _ in 0..<(PortraitExplorationPolicy.maximumRecords + 3) {
      let round = try #require(model.explorationRound)
      retainedRounds.append(round)
      model.chooseExplorationSlot(1, roundID: round.id, strokeStyle: pen)
      await model.awaitRendering()
    }
    #expect(await renderer.requests.count <= calls + (PortraitExplorationPolicy.maximumRecords + 3) * 4)
    #expect(model.keepSelection() == nil)
    await model.sketches.awaitPersistence()
    let expected = try #require(model.sketches.entries.first)
    let trace = try #require(expected.exploration)
    #expect(trace.count == PortraitExplorationPolicy.maximumRecords)
    #expect(trace.allSatisfy { $0.offers.count == 3 && $0.sourceSHA256 == expected.candidate.sourceSHA256 })
    #expect(trace.contains { $0.action == .selected(index: 1) })
    let reloaded = await PortraitCandidateStore(directoryURL: directory).load()
    #expect(reloaded.canWrite)
    #expect(reloaded.archive.entries.first?.exploration == trace)
    #expect(reloaded.archive.entries.first?.candidate.program == expected.candidate.program)
    var backCount = 0
    while model.canGoBackExploration {
      model.goBackExploration()
      #expect(try roundBytes(#require(model.explorationRound))
        == roundBytes(retainedRounds[retainedRounds.count - 1 - backCount]))
      backCount += 1
    }
    #expect(backCount == PortraitExplorationPolicy.maximumHistoryRounds)
    model.sketches.deleteSource(expected.candidate.sourceSHA256)
    await model.sketches.awaitPersistence()
    let deleted = await PortraitCandidateStore(directoryURL: directory).load()
    #expect(deleted.archive.entries.isEmpty)
    #expect(deleted.archive.tombstones.contains { $0.kind == .source })
    await model.shutdown()
  }

  @Test("legacy archive entries without exploration receipts remain readable")
  func legacyArchiveWithoutTrace() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("portrait-legacy-grid-\(UUID())")
    defer { try? FileManager.default.removeItem(at: directory) }
    let model = PortraitStudioModel(renderer: ExplorationTestRenderer())
    model.style = .contours
    model.vectorOptions = PortraitVectorOptions()
    model.setPhoto(Data([1]), for: .front, strokeStyle: try portraitTestStyle())
    await model.awaitRendering()
    let candidate = try #require(model.selectedCandidate)
    let archive = PortraitCandidateArchive(entries: [.init(candidate: candidate, reasons: [])])
    try await PortraitCandidateStore(directoryURL: directory).save(snapshot: archive)
    let loaded = await PortraitCandidateStore(directoryURL: directory).load()
    #expect(loaded.canWrite)
    #expect(loaded.archive.entries.first?.exploration == nil)
    #expect(loaded.archive.entries.first?.candidate.id == candidate.id)
    await model.shutdown()
  }

  @Test("delayed handoff retains only the choices present when acceptance began")
  func delayedHandoffFreezesTrace() async throws {
    let model = PortraitStudioModel(renderer: ExplorationTestRenderer())
    model.style = .contours
    model.vectorOptions = PortraitVectorOptions()
    let pen = try portraitTestStyle()
    model.setPhoto(Data([1]), for: .front, strokeStyle: pen)
    await model.awaitRendering()
    model.setExplorationEnabled(true, strokeStyle: pen)
    await model.awaitRendering()
    let first = try #require(model.explorationRound)
    let accepted = first.center
    let gate = ExplorationAcceptanceGate()
    let handoff = Task { await model.acceptProjection(accepted, perform: { await gate.hold(); return nil }) }
    try await gate.waitUntilHeld()
    model.resampleExploration(roundID: first.id, strokeStyle: pen)
    await model.awaitRendering()
    let later = try #require(model.explorationRound)
    await gate.release()
    #expect(await handoff.value == nil)
    let retained = try #require(model.sketches.entries.first)
    #expect(retained.candidate.id == accepted.id)
    #expect(retained.exploration?.contains { $0.roundID == first.id } == true)
    #expect(retained.exploration?.contains { $0.roundID == later.id } == false)
    await model.shutdown()
  }

  @Test("hiding and reopening a settled grid preserves exact offers without new work")
  func hiddenGridRetainsOffers() async throws {
    let renderer = ExplorationTestRenderer()
    let model = PortraitStudioModel(renderer: renderer)
    model.style = .contours
    model.vectorOptions = PortraitVectorOptions()
    let pen = try portraitTestStyle()
    model.setPhoto(Data([1]), for: .front, strokeStyle: pen)
    await model.awaitRendering()
    model.setExplorationEnabled(true, strokeStyle: pen)
    await model.awaitRendering()
    let first = try #require(model.explorationRound)
    let calls = await renderer.requests.count
    model.setExplorationEnabled(false, strokeStyle: pen)
    await model.cancelRendering()
    model.setExplorationEnabled(true, strokeStyle: pen)
    await model.awaitRendering()
    #expect(try roundBytes(#require(model.explorationRound)) == roundBytes(first))
    #expect(await renderer.requests.count == calls)
    await model.shutdown()
  }

  @Test("the selected candidate can be saved while its neighborhood is still rendering")
  func keepWhileNeighborsPending() async throws {
    let renderer = ExplorationTestRenderer()
    let model = PortraitStudioModel(renderer: renderer)
    model.style = .contours
    model.vectorOptions = PortraitVectorOptions()
    let pen = try portraitTestStyle()
    model.setPhoto(Data([1]), for: .front, strokeStyle: pen)
    await model.awaitRendering()
    let center = try #require(model.selectedCandidate)
    await renderer.holdNext()
    model.setExplorationEnabled(true, strokeStyle: pen)
    try await renderer.waitUntilHeld()
    #expect(model.isExploring)
    #expect(model.keepSelection() == nil)
    #expect(try candidateBytes(#require(model.sketches.entries.first?.candidate)) == candidateBytes(center))
    await renderer.release()
    await model.awaitRendering()
    #expect(model.selectedCandidate?.id == center.id)
    await model.shutdown()
  }

  @Test("an old delayed handoff cannot overwrite a newer saved trace after bounded trimming")
  func delayedHandoffPreservesNewerSavedTrace() async throws {
    let renderer = ExplorationTestRenderer()
    let model = PortraitStudioModel(renderer: renderer)
    model.style = .contours
    model.vectorOptions = PortraitVectorOptions()
    let pen = try portraitTestStyle()
    model.setPhoto(Data([1]), for: .front, strokeStyle: pen)
    await model.awaitRendering()
    model.setExplorationEnabled(true, strokeStyle: pen)
    await model.awaitRendering()
    let first = try #require(model.explorationRound)
    let gate = ExplorationAcceptanceGate()
    let handoff = Task { await model.acceptProjection(first.center, perform: { await gate.hold(); return nil }) }
    try await gate.waitUntilHeld()
    await renderer.rejectFutureRequests()
    await model.awaitRendering()
    for _ in 0..<PortraitExplorationPolicy.maximumRecords {
      model.resampleExploration(roundID: try #require(model.explorationRound).id, strokeStyle: pen)
      await model.awaitRendering()
    }
    #expect(model.selectedCandidate?.id == first.center.id)
    #expect(model.keepSelection() == nil)
    let newerTrace = try #require(model.sketches.entries.first?.exploration)
    #expect(newerTrace.count == PortraitExplorationPolicy.maximumRecords)
    #expect(!newerTrace.contains { $0.roundID == first.id })
    await gate.release()
    #expect(await handoff.value == nil)
    #expect(model.sketches.entries.first?.exploration == newerTrace)
    #expect(model.sketches.entries.count == 1)
    await model.shutdown()
  }

  @Test("closing a pending grid joins its old worker before regenerating on reopen")
  func hiddenPendingGridReopensSerially() async throws {
    let renderer = ExplorationTestRenderer()
    let model = PortraitStudioModel(renderer: renderer)
    model.style = .contours
    model.vectorOptions = PortraitVectorOptions()
    let pen = try portraitTestStyle()
    model.setPhoto(Data([1]), for: .front, strokeStyle: pen)
    await model.awaitRendering()
    let center = try #require(model.selectedCandidate)
    await renderer.holdNext()
    model.setExplorationEnabled(true, strokeStyle: pen)
    try await renderer.waitUntilHeld()
    model.setExplorationEnabled(false, strokeStyle: pen)
    model.setExplorationEnabled(true, strokeStyle: pen)
    #expect(await renderer.requests.count == 2)
    #expect(model.selectedCandidate?.id == center.id)
    await renderer.release()
    await model.awaitRendering()
    let round = try #require(model.explorationRound)
    #expect(round.center.id == center.id)
    #expect(model.workDiagnostics.maximumConcurrentWorkerCount == 1)
    #expect(await renderer.requests.count <= 2 + 2 * PortraitExplorationPolicy.maximumAttemptsPerSlot)
    await model.shutdown()
  }

  private func candidateBytes(_ candidate: PortraitCandidate) throws -> Data {
    try PortraitCandidateCoding.encoder().encode(candidate)
  }

  private func roundBytes(_ round: PortraitExplorationRound) throws -> Data {
    var bytes = Data("\(round.id)|\(round.seed)|\(round.variation)".utf8)
    bytes.append(try candidateBytes(round.center))
    for slot in round.slots {
      bytes.append(Data("|\(slot.index)|\(slot.unavailableReason ?? "")".utf8))
      if let candidate = slot.candidate { bytes.append(try candidateBytes(candidate)) }
    }
    return bytes
  }
}

private actor ExplorationTestRenderer: PortraitRendering {
  private(set) var requests: [PortraitRenderRequest] = []
  private var holdsNext = false
  private var rejectsFuture = false
  private var releaseWaiter: CheckedContinuation<Void, Never>?

  func holdNext() { holdsNext = true }
  func rejectFutureRequests() { rejectsFuture = true }
  func render(_ request: PortraitRenderRequest) async throws -> PortraitRenderResult {
    requests.append(request)
    if holdsNext {
      holdsNext = false
      await withCheckedContinuation { releaseWaiter = $0 }
    }
    if rejectsFuture { throw PortraitDrawingError.unreadableImage }
    let raster = request.cachedRaster ?? portraitTestRaster()
    // Deliberately ignore cancellation to test publication ownership.
    let program = try await Task.detached {
      try PortraitVectorizer.program(from: raster, pose: request.pose, style: request.style,
        strokeStyle: request.strokeStyle, vectorOptions: request.vectorOptions)
    }.value
    return PortraitRenderResult(raster: raster, program: program)
  }
  func waitUntilHeld() async throws {
    let deadline = ContinuousClock.now.advanced(by: .seconds(5))
    while releaseWaiter == nil {
      try #require(ContinuousClock.now < deadline, "Exploration worker never reached the held render.")
      try await Task.sleep(for: .milliseconds(1))
    }
  }
  func release() { releaseWaiter?.resume(); releaseWaiter = nil }
}

private actor ExplorationAcceptanceGate {
  private var waiter: CheckedContinuation<Void, Never>?
  func hold() async { await withCheckedContinuation { waiter = $0 } }
  func waitUntilHeld() async throws {
    let deadline = ContinuousClock.now.advanced(by: .seconds(5))
    while waiter == nil {
      try #require(ContinuousClock.now < deadline)
      try await Task.sleep(for: .milliseconds(1))
    }
  }
  func release() { waiter?.resume(); waiter = nil }
}
