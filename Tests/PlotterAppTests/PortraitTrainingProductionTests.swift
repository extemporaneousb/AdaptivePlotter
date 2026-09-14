import Foundation
import PlotterModel
import Testing
@testable import PlotterApp

@Suite("Named style production training", .serialized)
@MainActor
struct PortraitTrainingProductionTests {
  @Test("durable labels change actual proposals, reload into a child fit, compare and roll back")
  func productionLifecycle() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let candidateStore = PortraitCandidateStore(directoryURL: directory.appendingPathComponent("candidates"))
    let checkpointStore = PortraitCheckpointStore(directory: directory.appendingPathComponent("training"))
    let (scope, archive) = try portraitTrainingFixture()
    try await candidateStore.save(snapshot: archive)
    let model = PortraitStudioModel(candidateStore: candidateStore, checkpointStore: checkpointStore)
    await model.loadArchive()
    try await model.training.saveScope(scope)
    model.selectedStyleScope = scope.scope
    let source = try #require(model.sketches.entries.first?.candidate)
    model.sketches.selectedID = source.id
    await model.trainSelectedStyle()
    let first = try #require(model.training.checkpoint(model.training.pendingCheckpointID), "\(model.training.status)")
    #expect(model.training.activeCheckpoint(for: scope.id) == nil)
    #expect(first.payload.dataset.payload.rows.count == archive.labels.count)
    let retainedCount = model.sketches.entries.count
    var priorSpacing: [Int] = [], trainedSpacing: [Int] = []
    for seed in UInt64(1)...12 {
      model.sketches.selectedID = source.id
      model.exploreSelectedStyle(seed: seed)
      await model.awaitRendering()
      let prior = try #require(model.selectedCandidate, "\(model.summary)")
      #expect(prior.checkpointID == nil)
      priorSpacing.append(prior.recipe.vectorOptions.hatchSpacing)
    }
    await model.activateStyleCheckpoint(first.id)
    for seed in UInt64(1)...12 {
      model.sketches.selectedID = source.id
      model.randomStyle(strokeStyle: try #require(source.program.strokes.first?.style), seed: seed)
      await model.awaitRendering()
      let generated = try #require(model.selectedCandidate, "\(model.summary)")
      #expect(generated.checkpointID == first.id)
      #expect(generated.proposal?.trainingSelection?.checkpointID == first.id)
      #expect(generated.sourceSHA256 == source.sourceSHA256)
      #expect(generated.rasterSHA256 == source.rasterSHA256)
      #expect(generated.program == model.currentProgram)
      trainedSpacing.append(generated.recipe.vectorOptions.hatchSpacing)
    }
    #expect(priorSpacing != trainedSpacing)
    #expect(trainedSpacing.reduce(0, +) > priorSpacing.reduce(0, +))
    #expect(model.sketches.entries.count == retainedCount)
    #expect(model.sketches.labels.count == archive.labels.count)
    model.sketches.selectedID = source.id
    model.compareSelectedStyle(checkpointID: first.id, seed: 45)
    await model.awaitRendering()
    let comparison = try #require(model.trainingComparison, "\(model.summary)")
    #expect(comparison.current.checkpointID == first.id)
    #expect(comparison.prior.checkpointID == nil)
    #expect(comparison.current.rasterSHA256 == comparison.prior.rasterSHA256)
    #expect(comparison.current.proposal?.trainingSelection?.proposals.map(\.recipeSHA256)
      == comparison.prior.proposal?.trainingSelection?.proposals.map(\.recipeSHA256))
    await model.shutdown()

    let restarted = PortraitStudioModel(candidateStore: PortraitCandidateStore(directoryURL: directory.appendingPathComponent("candidates")),
      checkpointStore: PortraitCheckpointStore(directory: directory.appendingPathComponent("training")))
    await restarted.loadArchive()
    restarted.selectedStyleScope = scope.scope
    #expect(restarted.training.activeCheckpoint(for: scope.id)?.id == first.id)
    for entry in restarted.sketches.entries {
      let previous = try #require(archive.labels.first { $0.candidateID == entry.id })
      #expect(restarted.sketches.rate(candidate: entry.candidate, rating: 6 - previous.rating,
        scope: scope.scope, presentation: previous.presentation) == nil)
    }
    await restarted.sketches.awaitPersistence()
    await restarted.trainSelectedStyle()
    let child = try #require(restarted.training.checkpoint(restarted.training.pendingCheckpointID), "\(restarted.training.status)")
    #expect(child.payload.parentCheckpointID == first.id)
    #expect(child.payload.initialization == .deterministicFullRefit)
    #expect(child.payload.optimizerState == .reset)
    #expect(child.payload.dataset.id != first.payload.dataset.id)
    #expect(child.payload.model != first.payload.model)
    #expect(restarted.training.activeCheckpoint(for: scope.id)?.id == first.id)
    await restarted.activateStyleCheckpoint(child.id)
    #expect(restarted.training.activeCheckpoint(for: scope.id)?.id == child.id)
    await restarted.rollbackStyleCheckpoint()
    #expect(restarted.training.activeCheckpoint(for: scope.id)?.id == first.id)
    await restarted.rollbackStyleCheckpoint()
    #expect(restarted.training.activeCheckpoint(for: scope.id) == nil)
    await restarted.shutdown()
  }

  @Test("the default scope can fit its existing durable labels without assigning a new scope identity")
  func defaultScopeTraining() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    var archive = try portraitTrainingFixture().1
    archive.labels = try archive.labels.map { old in
      let candidate = try #require(archive.entries.first { $0.id == old.candidateID }?.candidate)
      return try .init(candidate: candidate, rating: old.rating, scope: .screenSketch,
        presentation: old.presentation, id: old.id, createdAt: old.createdAt)
    }
    let store = PortraitCandidateStore(directoryURL: directory.appendingPathComponent("candidates"))
    try await store.save(snapshot: archive)
    let model = PortraitStudioModel(candidateStore: store,
      checkpointStore: PortraitCheckpointStore(directory: directory.appendingPathComponent("training")))
    await model.loadArchive()
    #expect(model.training.scope(PortraitStyleScope.screenSketch.id) == nil)
    #expect(model.canTrainSelectedStyle)
    await model.trainSelectedStyle()
    let checkpoint = try #require(model.training.checkpoint(model.training.pendingCheckpointID), "\(model.training.status)")
    #expect(checkpoint.scopeID == PortraitStyleScope.screenSketch.id)
    #expect(Set(checkpoint.payload.dataset.payload.rows.map { $0.label.id }) == Set(archive.labels.map(\.id)))
    #expect(model.sketches.labels == archive.labels)
    await model.shutdown()
  }

  @Test("an incompatible active ordinary checkpoint falls back to exact local head-preserving exploration")
  func incompatibleLocalCheckpoint() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let (scope, archive) = try portraitTrainingFixture()
    let store = PortraitCandidateStore(directoryURL: directory.appendingPathComponent("candidates"))
    try await store.save(snapshot: archive)
    let model = PortraitStudioModel(candidateStore: store,
      checkpointStore: PortraitCheckpointStore(directory: directory.appendingPathComponent("training")))
    await model.loadArchive(); try await model.training.saveScope(scope)
    model.selectedStyleScope = scope.scope
    await model.trainSelectedStyle()
    let checkpoint = try #require(model.training.pendingCheckpointID, "\(model.training.status)")
    await model.activateStyleCheckpoint(checkpoint)
    let head = try semanticTrainingSource()
    #expect(model.sketches.retain(candidate: head, reason: .shortlisted) == nil)
    await model.sketches.awaitPersistence()
    model.sketches.selectedID = head.id
    model.moreLikeThis(seed: 27)
    await model.awaitRendering()
    let child = try #require(model.selectedCandidate, "\(model.summary)")
    #expect(child.lineage.parentID == head.id)
    #expect(child.proposal?.kind == .local)
    #expect(child.checkpointID == nil)
    #expect(child.recipe.vectorOptions.semanticHead == head.recipe.vectorOptions.semanticHead)
    #expect(child.warpManifest == head.warpManifest)
    #expect(child.sourceSHA256 == head.sourceSHA256)
    #expect(child.rasterSHA256 == head.rasterSHA256)
    #expect(child.program == model.currentProgram)
    #expect(model.explorationStatus?.contains("Local renderer prior") == true)
    #expect(model.training.activeCheckpoint(for: scope.id)?.id == checkpoint)
    await model.shutdown()
  }

  @Test("cancelled update joins its worker and restart retains the completed active parent")
  func cancelledUpdate() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let (scope, archive) = try portraitTrainingFixture()
    let library = PortraitTrainingLibrary(store: PortraitCheckpointStore(directory: directory))
    await library.load(); try await library.saveScope(scope)
    await library.train(scopeID: scope.id, archive: archive)
    let parent = try #require(library.pendingCheckpointID, "\(library.status)")
    await library.activate(parent, scopeID: scope.id)
    var configuration = PortraitOrdinalFitConfiguration.standard
    configuration.maximumIterations = 10000
    configuration.convergenceTolerance = 1e-14
    let update = Task { await library.train(scopeID: scope.id, archive: archive, configuration: configuration) }
    try await waitUntilAsync { library.isFitting }
    library.cancel()
    await update.value
    #expect(!library.isWorking)
    #expect(library.activeCheckpoint(for: scope.id)?.id == parent)
    #expect(library.checkpoints.count == 1)
    await library.shutdown()
    let restarted = PortraitTrainingLibrary(store: PortraitCheckpointStore(directory: directory))
    await restarted.load()
    #expect(restarted.activeCheckpoint(for: scope.id)?.id == parent)
    #expect(restarted.checkpoints.count == 1)
    await restarted.shutdown()
  }

  @Test("rapid Random and activation during a held renderer preserve captured checkpoint and projected drawing")
  func generationCapturesCheckpoint() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let (scope, archive) = try portraitTrainingFixture(sourceCount: 3)
    let store = PortraitCandidateStore(directoryURL: directory.appendingPathComponent("candidates"))
    try await store.save(snapshot: archive)
    let renderer = TrainingHeldRenderer()
    let model = PortraitStudioModel(renderer: renderer, candidateStore: store,
      checkpointStore: PortraitCheckpointStore(directory: directory.appendingPathComponent("training")))
    await model.loadArchive(); try await model.training.saveScope(scope)
    model.selectedStyleScope = scope.scope
    let source = try #require(model.sketches.entries.first?.candidate)
    model.sketches.selectedID = source.id
    let projectionError = await model.acceptProjection(source) { nil }
    #expect(projectionError == nil)
    await model.trainSelectedStyle()
    let checkpoint = try #require(model.training.pendingCheckpointID, "\(model.training.status)")
    await model.activateStyleCheckpoint(checkpoint)
    await renderer.arm()
    model.exploreSelectedStyle(seed: 6)
    do { try await waitUntilAsync { await renderer.isHeld() } }
    catch { await renderer.release(); await model.shutdown(); throw error }
    model.randomStyle(strokeStyle: try #require(source.program.strokes.first?.style), seed: 7)
    await model.activateStyleCheckpoint(nil)
    await renderer.release()
    await model.awaitRendering()
    #expect(model.selectedCandidate?.checkpointID == checkpoint)
    #expect(model.selectedCandidate?.proposal?.trainingSelection?.seed == 7)
    #expect(model.renderDiagnostics.maximumConcurrentWorkerCount == 1)
    #expect(model.training.activeCheckpoint(for: scope.id) == nil)
    #expect(model.projectedCandidate?.id == source.id)
    #expect(model.projectedCandidate?.program == source.program)
    await model.shutdown()
  }
}

private actor TrainingHeldRenderer: PortraitRendering {
  private var armed = false
  private var held = false
  private var releaseContinuation: CheckedContinuation<Void, Never>?
  func arm() { armed = true }
  func isHeld() -> Bool { held }
  func release() { armed = false; releaseContinuation?.resume(); releaseContinuation = nil; held = false }
  func render(_ request: PortraitRenderRequest) async throws -> PortraitRenderResult {
    if armed {
      armed = false; held = true
      await withCheckedContinuation { releaseContinuation = $0 }
    }
    try Task.checkCancellation()
    return try await PortraitImageAnalyzer().render(request)
  }
}
