import Foundation
import PlotterEpisodeRuntime
import PlotterRuntime
import Testing
@testable import PlotterApp

/// In-memory ports and existing queue barriers exercise synchronization
/// lifetime. No camera, controller, paper files or new scheduler is involved.
@Suite("Drawing Draft synchronization lifetime", .serialized)
@MainActor
struct DrawingDraftSynchronizationLifetimeTests {
  @Test("replacement waits for a canceled predecessor's noncooperative paper load")
  func replacementJoinsHeldFirstLoad() async throws {
    let gate = DrawingRunHoldGate()
    let paper = ComputationPaperPersistenceProbe(loadGate: gate)
    let draft = nominalDrawingDraftRuntime(paperPersistence: paper)
    let workspace = drawingDraftSynchronizationTestWorkspace(draft: draft)
    if workspace.drawingDraftSynchronizationTask == nil { workspace.markSemanticPresentationChangedForTesting() }
    await gate.waitUntilHeld()
    let predecessor = try #require(workspace.drawingDraftSynchronizationTask)
    workspace.markSemanticPresentationChangedForTesting()
    let replacement = try #require(workspace.drawingDraftSynchronizationTask)
    #expect(predecessor.isCancelled)
    #expect(!replacement.isCancelled)
    // The lower port actually holds the predecessor. Give the replacement
    // executor turns to attempt entry: cancel-and-spawn queues a second Draft
    // mutation here, whereas the retained chain still awaits its predecessor.
    for _ in 0..<8 {
      await Task.yield()
      #expect(await draft.pendingMutationCount == 0)
    }
    _ = workspace.testPlotterUIProjection() // the MainActor remains usable
    await gate.release()
    await replacement.value
    #expect(await paper.loadCount == 1)
    #expect(await draft.pendingMutationCount == 0)
    #expect(workspace.drawingDraftSnapshot.projection.externalFacts == workspace.drawingDraftExternalFacts.revisions)
    let run = try #require(workspace.drawingRunSnapshot)
    #expect(run.readiness != .synchronizing)
    await workspace.shutdown()
  }

  @Test("superseding a nested Run-to-Draft waiter settles without a task-chain cycle",
    arguments: [false, true])
  func cancellationBeyondFirstPublication(shutdownWhileHeld: Bool) async throws {
    let loadGate = DrawingRunHoldGate()
    let clearGate = DrawingRunHoldGate()
    let paper = ComputationPaperPersistenceProbe(loadGate: loadGate, clearGate: clearGate)
    let draft = nominalDrawingDraftRuntime(paperPersistence: paper)
    let workspace = drawingDraftSynchronizationTestWorkspace(draft: draft)
    if workspace.drawingDraftSynchronizationTask == nil { workspace.markSemanticPresentationChangedForTesting() }
    await loadGate.waitUntilHeld()
    let predecessor = try #require(workspace.drawingDraftSynchronizationTask)
    let scheduled = workspace.computationDiagnosticsForTesting.drawingDraftSynchronizationCount
    let facts = workspace.drawingDraftExternalFacts
    let clearing = Task { await draft.clearPaperCoverageForRetainedPaperLifecycle(facts: facts) }
    do {
      try await waitForExecutorTurnsAsync { await draft.pendingMutationCount == 1 }
      await loadGate.release()
      await clearGate.waitUntilHeld()
      // The queued clear now owns persistence. With no camera subscription or
      // other scheduled generation, this next waiter is the predecessor's
      // Run -> currentDrawingRunFacts -> Draft call, after its first publish.
      try await waitForExecutorTurnsAsync { await draft.pendingMutationCount == 1 }
      #expect(workspace.computationDiagnosticsForTesting.drawingDraftSynchronizationCount == scheduled)
      #expect(workspace.drawingDraftSnapshot.program != nil)
      let beforeClear = workspace.drawingDraftSnapshot.projection
      workspace.markSemanticPresentationChangedForTesting()
      let successor = try #require(workspace.drawingDraftSynchronizationTask)
      #expect(predecessor.isCancelled)
      await predecessor.value // real cancellation-aware nested waiter settles
      try await waitForExecutorTurnsAsync { await draft.pendingMutationCount == 1 }
      #expect(workspace.drawingDraftSnapshot.projection == beforeClear)
      if shutdownWhileHeld {
        let scheduledBeforeShutdown = workspace.computationDiagnosticsForTesting.drawingDraftSynchronizationCount
        var shutdownCompleted = false
        let shutdown = Task { await workspace.shutdown(); shutdownCompleted = true }
        try await waitUntil { shutdownCompleted }
        #expect(successor.isCancelled)
        #expect(await draft.pendingMutationCount == 0)
        #expect(workspace.drawingDraftSynchronizationTask == nil)
        #expect(workspace.computationDiagnosticsForTesting.drawingDraftSynchronizationCount == scheduledBeforeShutdown)
        // Shutdown joined the canceled chain while the unrelated test clear
        // still owns persistence. It cannot be awaiting a replacement task.
        await clearGate.release()
        _ = await clearing.value
        await shutdown.value
      } else {
        await clearGate.release()
        let cleared = await clearing.value
        #expect(cleared.disposition == .applied)
        await successor.value
        #expect(workspace.drawingDraftSnapshot.projection.draftRevision == cleared.snapshot.projection.draftRevision)
        #expect(workspace.drawingDraftSnapshot.projection.externalFacts == workspace.drawingDraftExternalFacts.revisions)
        let run = try #require(workspace.drawingRunSnapshot)
        #expect(run.readiness != .synchronizing)
        await workspace.shutdown()
      }
    } catch {
      await loadGate.release()
      await clearGate.release()
      _ = await clearing.value
      await workspace.shutdown()
      throw error
    }
  }
}

@MainActor
func drawingDraftSynchronizationTestWorkspace(draft: PlotterDrawingDraftRuntime) -> PlotterApplicationRuntime {
  PlotterApplicationRuntime(penInteractionRuntime: nominalPenInteractionRuntime(),
    boundaryRuntime: nominalBoundaryRuntime(),
    speechEffectRuntime: PlotterSpeechEffectRuntime(announcer: ImmediateSpeechAnnouncer()),
    drawingDraftRuntime: draft,
    drawingRunComposition: nominalDrawingRunComposition(),
    incidentPackageUIService: nominalIncidentPackageUIService(),
    observationPreferences: TestObservationPreferencePort())
}

actor ComputationPaperPersistenceProbe: PlotterDrawingDraftPaperPersistence {
  private let loadGate: DrawingRunHoldGate?
  private let clearGate: DrawingRunHoldGate?
  private(set) var loadCount = 0

  init(loadGate: DrawingRunHoldGate? = nil, clearGate: DrawingRunHoldGate? = nil) {
    self.loadGate = loadGate
    self.clearGate = clearGate
  }

  func load() async -> PaperCoverageObservation? {
    loadCount += 1
    await loadGate?.hold()
    return nil
  }

  func save(_: PaperCoverageObservation) {}

  func clear() async { await clearGate?.hold() }
}
