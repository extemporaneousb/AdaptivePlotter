import Foundation
import PlotterEpisodeModel
import PlotterEpisodeRuntime
import PlotterModel
import PlotterRuntime
import Testing
@testable import PlotterApp

/// One production composition journey. All source labels, ruler-independent
/// material pixels, camera/controller effects and physical ratings are synthetic;
/// these assertions establish software linkage, not learned or attended quality.
@Suite("Trainable Drawing Studio campaign journey", .serialized)
@MainActor
struct StudioCampaignJourneyTests {
  @Test("attended targets select exact unit-scale plans at zero and ninety degrees without dispatch")
  func prepareExactMetricTargets() async throws {
    let f = try await DrawingWorkbenchApplicationFixture.make()
    defer { f.stores.remove() }
    let app = f.application
    do {
      let feeds = await f.machine.requestedFeeds
      let penCommands = await f.machine.requestedPenCommands
      for id in [DrawingCatalogEntryID.metricSquare40, .metricRectangle40x20] {
        try await f.submit(.selectCatalogItem(id))
        if !app.drawingTargetIsVisible { try await f.submit(.showTarget) }
        #expect(app.drawingTargetIsVisible)
        try await f.submit(.setUniformScale(1))
        for rotation in [0.0, 90.0] {
          try await f.submit(.setRotationDegrees(rotation))
          try await f.submit(.centerInDrawableRegion)
          let program = try #require(app.drawingDraftSnapshot.program)
          let plan = try #require(app.drawingDraftSnapshot.plan)
          #expect(plan.placement.uniformScale == 1)
          try assertStudioProportions(program: program, plan: plan)
          let points = try #require(plan.strokes.first?.path.points)
          #expect(points.count == 5)
          let edges = zip(points, points.dropFirst()).map { $0.distance(to: $1) }
          let expected = id == .metricSquare40 ? [40.0, 40, 40, 40] : [40.0, 20, 40, 20]
          #expect(zip(edges, expected).allSatisfy { abs($0 - $1) < 1e-8 })
          if id == .metricSquare40 {
            #expect(plan.strokes.count == 3)
            for diagonal in plan.strokes.dropFirst() {
              #expect(abs(diagonal.path.points[0].distance(to: diagonal.path.points[1]) - 40 * sqrt(2)) < 1e-8)
            }
          }
          #expect(!app.drawingDraftSnapshot.paperCoverageIsCurrent)
          #expect(await f.planGate.request == nil)
        }
      }
      #expect(await f.machine.requestedFeeds == feeds)
      #expect(await f.machine.requestedPenCommands == penCommands)
      await app.shutdown()
    } catch { await app.shutdown(); throw error }
  }

  @Test("branch, scoped fit, reload/update/rollback, measured projection and Draw retain one immutable lineage")
  func completeStudioJourney() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let candidatesURL = directory.appendingPathComponent("candidates")
    let trainingURL = directory.appendingPathComponent("training")
    let materialsURL = directory.appendingPathComponent("materials")
    let store = PortraitCandidateStore(directoryURL: candidatesURL)
    let (scope, seedArchive) = try portraitTrainingFixture()
    try await store.save(snapshot: seedArchive)
    let firstModel = PortraitStudioModel(candidateStore: store,
      checkpointStore: PortraitCheckpointStore(directory: trainingURL))
    await firstModel.loadArchive()
    try await firstModel.training.saveScope(scope)
    firstModel.selectedStyleScope = scope.scope
    let source = try #require(firstModel.sketches.entries.first?.candidate)
    firstModel.selectHistory(source.id)
    let initialCount = firstModel.sketches.entries.count
    firstModel.moreLikeThis(seed: 83)
    await firstModel.awaitRendering()
    let branch = try #require(firstModel.selectedCandidate)
    #expect(branch.lineage.parentID == source.id)
    #expect(branch.sourceSHA256 == source.sourceSHA256 && branch.rasterSHA256 == source.rasterSHA256)
    #expect(branch.recipe.style == source.recipe.style)
    #expect(firstModel.sketches.entries.count == initialCount)
    firstModel.historyParent()
    try assertStudioCandidate(firstModel.selectedCandidate, equals: source)
    firstModel.selectHistory(branch.id)
    try assertStudioCandidate(firstModel.selectedCandidate, equals: branch)
    #expect(firstModel.rateSelection(1) == nil)
    await firstModel.sketches.awaitPersistence()
    #expect(firstModel.sketches.entries.count == initialCount + 1)
    #expect(firstModel.sketches.labels.last?.scope == scope.scope)
    await firstModel.trainSelectedStyle()
    let parent = try #require(firstModel.training.checkpoint(firstModel.training.pendingCheckpointID), "\(firstModel.training.status)")
    #expect(firstModel.training.activeCheckpoint(for: scope.id) == nil)
    var priorSpacing: [Int] = [], trainedSpacing: [Int] = []
    for seed in UInt64(1)...12 {
      firstModel.selectHistory(source.id)
      firstModel.exploreSelectedStyle(seed: seed)
      await firstModel.awaitRendering()
      let candidate = try #require(firstModel.selectedCandidate)
      #expect(candidate.checkpointID == nil)
      priorSpacing.append(candidate.recipe.vectorOptions.hatchSpacing)
    }
    await firstModel.activateStyleCheckpoint(parent.id)
    for seed in UInt64(1)...12 {
      firstModel.selectHistory(source.id)
      firstModel.randomStyle(strokeStyle: try #require(source.program.strokes.first?.style), seed: seed)
      await firstModel.awaitRendering()
      let candidate = try #require(firstModel.selectedCandidate)
      #expect(candidate.checkpointID == parent.id)
      #expect(candidate.proposal?.trainingSelection?.checkpointID == parent.id)
      trainedSpacing.append(candidate.recipe.vectorOptions.hatchSpacing)
    }
    #expect(priorSpacing != trainedSpacing)
    #expect(trainedSpacing.reduce(0, +) > priorSpacing.reduce(0, +))
    let trained = try #require(firstModel.selectedCandidate)
    #expect(firstModel.rateSelection(4) == nil)
    await firstModel.sketches.awaitPersistence()
    let beforeReload = firstModel.sketches.archive
    let immutableParent = try studioJourneyBytes(parent)
    await firstModel.shutdown()

    let model = PortraitStudioModel(candidateStore: PortraitCandidateStore(directoryURL: candidatesURL),
      checkpointStore: PortraitCheckpointStore(directory: trainingURL))
    await model.loadArchive()
    model.selectedStyleScope = scope.scope
    #expect(model.training.activeCheckpoint(for: scope.id)?.id == parent.id)
    #expect(try studioJourneyBytes(model.sketches.archive) == studioJourneyBytes(beforeReload))
    for entry in model.sketches.entries {
      let label = try #require(beforeReload.labels.last { $0.candidateID == entry.id })
      #expect(model.sketches.rate(candidate: entry.candidate, rating: 6 - label.rating,
        scope: scope.scope, presentation: label.presentation) == nil)
    }
    await model.sketches.awaitPersistence()
    await model.trainSelectedStyle()
    let child = try #require(model.training.checkpoint(model.training.pendingCheckpointID), "\(model.training.status)")
    #expect(child.payload.parentCheckpointID == parent.id)
    #expect(child.payload.initialization == .deterministicFullRefit && child.payload.optimizerState == .reset)
    #expect(child.payload.dataset.id != parent.payload.dataset.id)
    #expect(child.payload.model != parent.payload.model)
    #expect(model.training.activeCheckpoint(for: scope.id)?.id == parent.id)
    await model.activateStyleCheckpoint(child.id)
    model.selectHistory(trained.id)
    model.compareSelectedStyle(checkpointID: child.id, seed: 45)
    await model.awaitRendering()
    let comparison = try #require(model.trainingComparison)
    #expect(comparison.current.checkpointID == child.id)
    #expect(comparison.prior.checkpointID == parent.id)
    #expect(comparison.current.rasterSHA256 == comparison.prior.rasterSHA256)
    await model.rollbackStyleCheckpoint()
    #expect(model.training.activeCheckpoint(for: scope.id)?.id == parent.id)
    #expect(try studioJourneyBytes(model.training.checkpoint(parent.id)) == studioJourneyBytes(Optional(parent)))
    model.selectHistory(trained.id)
    try assertStudioCandidate(model.selectedCandidate, equals: trained)
    let labelsBeforeDraw = model.sketches.labels
    let materials = DrawingMaterialLibrary(store: DrawingMaterialStore(directoryURL: materialsURL))
    await materials.load()
    #expect(materials.createNominal(name: "Synthetic campaign marker", widthMM: 0.4) == nil)
    await materials.flush()
    let f = try await DrawingWorkbenchApplicationFixture.make(portraitStudio: model, drawingMaterials: materials)
    defer { f.stores.remove() }
    let app = f.application
    do {
      app.materialPaperStock = "Synthetic campaign paper"
      app.drawingMaterialSelectionDidChange()
      #expect(await app.projectPortrait(trained) == nil)
      try assertStudioCandidate(model.projectedCandidate, equals: trained)
      let fitted = try #require(app.drawingDraftSnapshot.plan)
      try await f.submit(.setUniformScale(floor(fitted.placement.uniformScale * 75) / 100))
      try await f.submit(.setRotationDegrees(90))
      try await f.submit(.centerInDrawableRegion)
      let beforeMaterial = try #require(app.drawingDraftSnapshot.plan)
      try assertStudioProportions(program: trained.program, plan: beforeMaterial)
      let measured = try await makeStudioCampaignMeasuredMaterial(f)
      #expect(materials.activeKey == measured.profile.key)
      #expect(await app.applyPortraitMaterial(measured.profile) == nil)
      let adapted = try #require(model.selectedCandidate)
      let finalPlan = try #require(app.drawingDraftSnapshot.plan)
      #expect(adapted.id != trained.id && adapted.lineage.parentID == trained.id)
      #expect(adapted.rasterSHA256 == trained.rasterSHA256)
      #expect(adapted.recipe.vectorOptions.materialContext?.profile == measured.profile)
      #expect(adapted.recipe.vectorOptions.materialContext?.drawingHeightMM
        == trained.program.fieldExtent.height * beforeMaterial.placement.uniformScale)
      #expect(finalPlan.placement == beforeMaterial.placement)
      try assertStudioCandidate(model.projectedCandidate, equals: adapted)
      #expect(model.sketches.labels == labelsBeforeDraw)
      try assertStudioProportions(program: adapted.program, plan: finalPlan)
      let paperFrame = try await f.camera.publishNextFrame()
      try await waitForExecutorTurns(conditionDescription: "campaign exact paper frame") {
        app.actionSurfacePreview.displayedFrame?.frame.id == paperFrame.frame.id
      }
      try await f.submit(.assertPaperCoverage)
      #expect(app.drawingDraftSnapshot.paperCoverageObservation?.frame.frameID == paperFrame.frame.id)
      try await waitUntil { app.drawingRunSnapshot?.readiness == .ready }
      let draw = try #require(app.testPlotterUIProjection().semantic.request(matching: .drawingRun(.start)))
      let operation = Task { await app.submitPlotterUIRequest(draw) }
      do { try await waitUntilAsync { await f.planGate.request != nil } }
      catch { await f.planGate.release(.cancelled); _ = await operation.value; throw error }
      let admitted = try #require(await f.planGate.request)
      #expect(admitted.plan.contentHash == finalPlan.contentHash)
      let beforeFinish = await f.stores.evidenceStore.load()
      guard case .loaded(let staged) = beforeFinish else { throw StudioJourneyFailure.missingArchive }
      #expect(staged.attempts.contains { $0.intent.context.candidate?.candidateID == adapted.id })
      #expect(WorkbenchStopPresentation.actions(in: app.testPlotterUIProjection().semantic).count == 1)
      await f.planGate.release(.completed)
      #expect(await operation.value == .accepted(requestID: draw.id))
      let terminal = try #require(app.drawingRunSnapshot?.terminal)
      #expect(terminal.disposition == .succeeded)
      let attempt = try #require(terminal.record.attemptEvidence)
      #expect(attempt.intent.context.candidate?.candidateID == adapted.id)
      #expect(attempt.intent.context.candidate?.sourceProgram == adapted.program)
      #expect(attempt.intent.context.materialProfile == measured.profile)
      #expect(!attempt.baselines.isEmpty && !attempt.terminalFrames.isEmpty)
      let coverage = try #require(attempt.mediaCoverage)
      #expect(coverage.registration == app.tipCameraRegistration)
      let coveragePixels = coverage.region.width * coverage.region.height
      #expect(coverage.uncoveredMask.count == coveragePixels)
      #expect(coverage.perPixelSource.count == coveragePixels)
      #expect(coverage.baselineRGBA.count == coveragePixels * 4 && coverage.resultRGBA.count == coveragePixels * 4)
      #expect(zip(coverage.uncoveredMask, coverage.perPixelSource).allSatisfy { unknown, source in
        unknown == (source == nil)
      })
      try await waitUntil { app.physicalAttempts(candidateID: adapted.id).contains(terminal.record) }
      let images = try await app.physicalAttemptImages(terminal.record)
      #expect(images.count == attempt.baselines.count + attempt.terminalFrames.count)
      #expect(app.ratePhysicalAttempt(terminal.record, rating: 3) == nil)
      await model.sketches.awaitPersistence()
      let physicalLabel = try #require(model.sketches.labels.last)
      #expect(physicalLabel.scope.objective == .physicalRealization)
      #expect(physicalLabel.presentation.physicalRecordID == terminal.record.recordID.rawValue)
      #expect(!physicalLabel.presentation.inkWidthIsMeasured)
      #expect(model.sketches.labels.filter { $0.scope.objective == .screenAesthetic } == labelsBeforeDraw)
      try assertStudioCandidate(model.sketches.entries.first { $0.id == trained.id }?.candidate, equals: trained)
      #expect(try studioJourneyBytes(#require(model.training.checkpoint(parent.id))) == immutableParent)
      await app.shutdown()

      let restored = PortraitStudioModel(candidateStore: PortraitCandidateStore(directoryURL: candidatesURL),
        checkpointStore: PortraitCheckpointStore(directory: trainingURL))
      await restored.loadArchive()
      #expect(restored.training.activeCheckpoint(for: scope.id)?.id == parent.id)
      #expect(restored.training.checkpoint(child.id) != nil)
      try assertStudioCandidate(restored.sketches.entries.first { $0.id == adapted.id }?.candidate, equals: adapted)
      try assertStudioCandidate(restored.sketches.entries.first { $0.id == trained.id }?.candidate, equals: trained)
      #expect(restored.sketches.labels.contains(physicalLabel))
      let materialReload = DrawingMaterialLibrary(store: DrawingMaterialStore(directoryURL: materialsURL))
      await materialReload.load()
      #expect(materialReload.activeRecord == measured)
      guard case .loaded(let durable) = await f.stores.evidenceStore.load() else { throw StudioJourneyFailure.missingArchive }
      #expect(durable.records.contains(terminal.record))
      for reference in attempt.baselines + attempt.terminalFrames {
        let frame = try await f.stores.evidenceStore.readMedia(reference)
        #expect(ExactFrameProvenance(frame: frame) == reference.frame)
      }
      await restored.shutdown()
      // Optional retained test artifact, outside operational application data.
      // It preserves the real fixture stores for the one aggregate review.
      if let destination = ProcessInfo.processInfo.environment["STUDIO_CAMPAIGN_EVIDENCE_DIRECTORY"] {
        let output = URL(fileURLWithPath: destination, isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: directory, to: output.appendingPathComponent("authoring"))
        try FileManager.default.copyItem(at: f.stores.directory, to: output.appendingPathComponent("drawing"))
        try studioJourneyBytes(finalPlan).write(to: output.appendingPathComponent("plan.json"))
        try studioJourneyBytes(terminal.record).write(to: output.appendingPathComponent("terminal-record.json"))
        try studioJourneyBytes(measured).write(to: output.appendingPathComponent("measured-material.json"))
        let receipt: [String: Any] = [
          "schema": "adaptiveplotter.studio-campaign-software-journey.v1",
          "evidenceClass": "synthetic software composition; no attended or learned-quality claim",
          "sourceSHA256": source.sourceSHA256, "sourceCandidate": source.id,
          "branchCandidate": branch.id, "trainedCandidate": trained.id, "adaptedCandidate": adapted.id,
          "parentCheckpoint": parent.id, "childCheckpoint": child.id,
          "parentDataset": parent.payload.dataset.id, "childDataset": child.payload.dataset.id,
          "activeAfterRollback": parent.id, "priorSpacing": priorSpacing, "trainedSpacing": trainedSpacing,
          "planHash": finalPlan.contentHash.description, "materialRevision": measured.profile.key,
          "runID": terminal.record.runID.rawValue.uuidString,
          "recordID": terminal.record.recordID.rawValue.uuidString,
          "physicalLabelID": physicalLabel.id.uuidString,
          "coveredPixels": coverage.coveredPixelCount,
          "unobservedPixels": coveragePixels - coverage.coveredPixelCount,
          "originalFrameHashes": (attempt.baselines + attempt.terminalFrames).map { $0.frame.frameSHA256 }
        ]
        try JSONSerialization.data(withJSONObject: receipt, options: [.sortedKeys, .prettyPrinted])
          .write(to: output.appendingPathComponent("receipt.json"))
      }
    } catch { await f.planGate.release(.cancelled); await app.shutdown(); throw error }
  }
}

private enum StudioJourneyFailure: Error { case missingArchive }

private func studioJourneyBytes<T: Encodable>(_ value: T) throws -> Data {
  let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
  return try encoder.encode(value)
}

private func assertStudioProportions(program: DrawingProgram, plan: ExecutionPlanRevision) throws {
  #expect(program.strokes.count == plan.strokes.count)
  for (source, executed) in zip(program.strokes, plan.strokes) {
    #expect(source.id == executed.logicalStrokeID)
    #expect(source.path.points.count == executed.path.points.count)
    for index in source.path.points.indices.dropFirst() {
      let a = source.path.points[index - 1], b = source.path.points[index]
      let c = executed.path.points[index - 1], d = executed.path.points[index]
      let expected = hypot(b.x - a.x, b.y - a.y) * plan.placement.uniformScale
      #expect(abs(hypot(d.x - c.x, d.y - c.y) - expected) < 1e-8)
    }
  }
}

private func assertStudioCandidate(_ actual: PortraitCandidate?, equals expected: PortraitCandidate) throws {
  let candidate = try #require(actual)
  #expect(try studioJourneyBytes(candidate) == studioJourneyBytes(expected))
}
