import Foundation
import DrawingLibrary
import PortraitLibrary
import PortraitArtists
import PortraitStudioUI
import Testing

@Suite("Cancelled generation terminal publication", .serialized)
@MainActor
struct GenerationCancellationPublicationTests {
  @Test("Cancel before first candidate and after admitted candidate publishes the exact durable terminal snapshot", arguments: [false, true])
  func settledCancellation(afterCandidate: Bool) async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let model = FlowAuthoringModel(directory: root, purpose: .validationFixture, render: FlowAuthoringFixture.render)
    await model.open(); await model.addPhoto(data: FlowAuthoringFixture.image(1), title: "Cancel source")
    let gate = CancellationPublicationGate()
    model.publicationBarrier = { boundary in
      if afterCandidate, case .candidateAdmitted = boundary { await gate.holdOnce() }
      if !afterCandidate, case .roundBegan = boundary { await gate.holdOnce() }
    }
    let task = Task { await model.generate(refining: false) }
    await gate.entered()
    let store = try #require(model.store)
    let before = await store.snapshot()
    #expect(before.rounds.last?.status == .generating)
    #expect(before.candidates.count == (afterCandidate ? 1 : 0))
    model.cancel(); gate.release(); await task.value
    let durable = await store.snapshot()
    #expect(model.document == durable)
    #expect(model.round?.status == .cancelled)
    #expect(model.roundCandidates.count == (afterCandidate ? 1 : 0))
    #expect(Set(model.previews.keys) == Set(model.roundCandidates.map(\.id)))
    #expect(Set(model.round?.displayedCandidateIDs ?? []) == Set(model.roundCandidates.map(\.id)))
    #expect(!model.isBusy && !model.isPreparingGeneration && !model.isRenderingGeneration)
    #expect(model.error == nil && !model.needsRecovery && model.canNavigateExploration)
    if let candidate = model.roundCandidates.first {
      await model.browseCandidate(candidate.id, prune: true)
      #expect(model.canEdit && model.canSendToPlotter && model.canRefineCandidate(candidate))
      #expect(model.program == (try await store.candidateProgram(candidate.id)))
    } else {
      #expect(!model.canEdit && !model.canSendToPlotter)
    }
    #expect(await model.shutdown())
  }

  @Test("Cancel while completeCandidate is durably committed but its awaited return is held")
  func cancellationInsideCandidateAdmission() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let model = FlowAuthoringModel(directory: root, purpose: .validationFixture, render: FlowAuthoringFixture.render)
    await model.open(); await model.addPhoto(data: FlowAuthoringFixture.image(1), title: "Admitted cancellation")
    let library = try #require(model.drawingLibrary), gate = DrawingEditCommitGate()
    defer { gate.release() }
    model.publicationBarrier = { boundary in
      if case .roundBegan = boundary { try? await library.holdGenerationCandidateAfterCommit(gate) }
    }
    let task = Task { await model.generate(refining: false) }
    #expect(await gate.waitUntilHeld())
    model.cancel(); gate.release(); await task.value
    await library.clearGenerationCandidateFault()
    let store = try #require(model.store), durable = await store.snapshot()
    #expect(model.document == durable && model.round?.status == .cancelled)
    #expect(model.roundCandidates.count == 1 && model.round?.displayedCandidateIDs.count == 1)
    #expect(Set(model.roundCandidates.map(\.slot)) == [0] && Set(model.previews.keys) == Set(model.roundCandidates.map(\.id)))
    #expect(!model.isBusy && !model.needsRecovery && model.error == nil)
    await model.browseCandidate(try #require(model.roundCandidates.first?.id), prune: true)
    #expect(model.canEdit && model.canSendToPlotter)
    #expect(await model.shutdown())
  }

  @Test("An actual renderer worker is cancelled before first admission and publishes its cancelled round")
  func actualWorkerCancellation() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let gate = CancellationPublicationGate(), observation = CancellationWorkerObservation()
    let model = FlowAuthoringModel(directory: root, purpose: .validationFixture, render: { data, recipe, pen in
      await gate.holdOnce()
      await observation.record(Task.isCancelled)
      return try await FlowAuthoringFixture.render(data, recipe, pen)
    })
    await model.open(); await model.addPhoto(data: FlowAuthoringFixture.image(1), title: "Renderer cancellation")
    let task = Task { await model.generate(refining: false) }
    await gate.entered(); #expect(model.isRenderingGeneration)
    model.cancel(); gate.release(); await task.value
    #expect(await observation.sawCancellation)
    #expect(model.round?.status == .cancelled && model.roundCandidates.isEmpty && model.previews.isEmpty)
    #expect(model.document == (await model.store?.snapshot()))
    #expect(!model.isBusy && !model.isRenderingGeneration && !model.isPreparingGeneration)
    #expect(!model.canEdit && !model.canSendToPlotter && !model.needsRecovery && model.error == nil)
    #expect(await model.shutdown())
  }

  @Test("A delayed terminal snapshot never publishes after source, region or generation replacement", arguments: ["source", "region", "generation"])
  func delayedTerminalNavigation(replacement: String) async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let model = FlowAuthoringModel(directory: root, purpose: .validationFixture, render: FlowAuthoringFixture.render)
    await model.open(); await model.addPhoto(data: FlowAuthoringFixture.image(2), title: "First source")
    let first = try #require(model.selectedSource?.id)
    await model.addPhoto(data: FlowAuthoringFixture.image(3), title: "Second source")
    let second = try #require(model.selectedSource?.id)
    await model.selectSource(first)
    let rendering = CancellationPublicationGate(), refresh = CancellationPublicationGate(), replacementRead = CancellationPublicationGate()
    var terminal = false, replacementStarted = false
    var stalePublications = 0
    var oldRound: UUID?
    model.publicationBarrier = { boundary in
      if case .candidateAdmitted = boundary { await rendering.holdOnce() }
      if case .terminalRefresh(let id) = boundary { terminal = true; oldRound = id }
      if terminal, case .snapshotRead = boundary {
        if replacementStarted { await replacementRead.holdOnce() }
        else { await refresh.holdOnce() }
      }
    }
    model.publicationDidPublish = { id in
      if replacementStarted, id == oldRound, model.round?.status == .cancelled { stalePublications += 1 }
    }
    let task = Task { await model.generate(refining: false) }
    await rendering.entered(); model.cancel(); rendering.release()
    await refresh.entered()
    let displayed = model.document, previews = model.previews, stage = model.stage
    let navigationStarted = CancellationPublicationGate()
    let navigate = Task {
      replacementStarted = true
      // Signals actor execution before entering the serial queued mutation.
      Task { await navigationStarted.holdOnce() }
      switch replacement {
      case "source": await model.selectSource(second)
      case "region": await model.commitRegion(.init(x: 0, y: 0, width: 0.5, height: 1))
      default: await model.generate(refining: false)
      }
    }
    await navigationStarted.entered(); navigationStarted.release()
    refresh.release(); await task.value
    await replacementRead.entered()
    // Inspect before the replacement refresh may publish. A final equal source
    // assertion alone would mask a stale terminal snapshot in this interval.
    #expect(model.document == displayed && model.previews == previews && model.stage == stage)
    #expect(stalePublications == 0 && model.error == nil)
    replacementRead.release(); await navigate.value
    #expect(stalePublications == 0)
    #expect(model.document == (await model.store?.snapshot()))
    #expect(!model.isBusy && !model.needsRecovery && model.error == nil)
    #expect(await model.shutdown())
  }

}

@MainActor private final class CancellationPublicationGate {
  private var didEnter = false
  private var waiting: CheckedContinuation<Void, Never>?
  private var enteredWaiters: [CheckedContinuation<Void, Never>] = []
  func holdOnce() async {
    guard !didEnter else { return }
    didEnter = true
    enteredWaiters.forEach { $0.resume() }; enteredWaiters = []
    await withCheckedContinuation { waiting = $0 }
  }
  func entered() async {
    if didEnter { return }
    await withCheckedContinuation { enteredWaiters.append($0) }
  }
  func release() { waiting?.resume(); waiting = nil }
}

private actor CancellationWorkerObservation {
  private(set) var sawCancellation = false
  func record(_ value: Bool) { sawCancellation = value }
}

private extension DrawingLibrary {
  func holdGenerationCandidateAfterCommit(_ gate: DrawingEditCommitGate) throws {
    let catalog = try commonCatalog()
    catalog.injectFault = { if $0 == .afterSQLCommit { try gate.hold() } }
  }
  func clearGenerationCandidateFault() { cachedExchangeCatalog?.injectFault = nil }
}
