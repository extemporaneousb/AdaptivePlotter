import Foundation
import PlotterModel
import Testing

@testable import PlotterApp

@Suite("Semantic named-style production training", .serialized)
@MainActor
struct PortraitSemanticTrainingProductionTests {
  @Test("durable semantic ratings fit and change actual head proposals while the branch remains frozen")
  func semanticProductionLifecycle() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("semantic-training-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: directory) }
    let candidateStore = PortraitCandidateStore(directoryURL: directory.appendingPathComponent("candidates"))
    let checkpointStore = PortraitCheckpointStore(directory: directory.appendingPathComponent("training"))
    let model = PortraitStudioModel(candidateStore: candidateStore, checkpointStore: checkpointStore)
    await model.loadArchive()
    let source = try semanticTrainingSource()
    try source.validateIntegrity()
    #expect(model.sketches.retain(candidate: source, reason: .shortlisted) == nil)
    await model.sketches.awaitPersistence()
    model.sketches.selectedID = source.id
    let creationError = await model.createTrainingScope(name: "Wider forehead preference",
      mode: .semanticBigHead, objective: .screenAesthetic)
    #expect(creationError == nil)
    let scope = try #require(model.training.scope(model.selectedStyleScope.id), "\(model.training.status)")
    #expect(scope.mode == .semanticBigHead)
    #expect(scope.scope.allowedFamilies == [source.recipe.style])
    #expect(Set(scope.scope.activeParameters) == Set<PortraitTrainableParameter>([.foreheadWidth, .foreheadHeight, .eyeScale, .lateralScale]))
    #expect(scope.referenceRecipe == source.recipe)
    let originalProjected = model.projectedCandidate?.id
    var retainedIDs = Set<String>()
    var ratedWidths: [Double] = []
    for seed in UInt64(1)...16 {
      model.sketches.selectedID = source.id
      model.exploreSelectedStyle(seed: seed)
      await model.awaitRendering()
      let candidate = try #require(model.selectedCandidate, "\(model.explorationStatus ?? model.summary)")
      try assertFrozenSemanticBranch(candidate, source: source)
      #expect(candidate.checkpointID == nil)
      #expect(candidate.proposal?.kind == .semanticTraining)
      let head = try #require(candidate.recipe.vectorOptions.semanticHead)
      ratedWidths.append(head.foreheadWidth)
      let rating = min(5, 1 + Int(head.foreheadWidth / 0.12))
      #expect(model.rateSelection(rating, presentation: try .init(drawingHeightMM: 130, inkWidthMM: 0.8)) == nil)
      retainedIDs.insert(candidate.id)
    }
    #expect(retainedIDs.count == 16)
    #expect(Set(ratedWidths).count > 1)
    #expect(Set(model.sketches.labels.map(\.rating)).count > 1)
    await model.sketches.awaitPersistence()
    let durable = await PortraitCandidateStore(directoryURL: directory.appendingPathComponent("candidates")).load()
    #expect(durable.canWrite)
    #expect(Set(durable.archive.labels.map(\.candidateID)) == retainedIDs)
    #expect(durable.archive.labels.allSatisfy { $0.scope == scope.scope })
    #expect(durable.archive.entries.filter { retainedIDs.contains($0.id) }.allSatisfy {
      $0.candidate.raster.faceAnalysis == source.raster.faceAnalysis && $0.candidate.warpManifest != nil
    })
    await model.trainSelectedStyle()
    let checkpoint = try #require(model.training.checkpoint(model.training.pendingCheckpointID), "\(model.training.status)")
    #expect(checkpoint.payload.dataset.payload.rows.count == 16)
    #expect(Set(checkpoint.payload.dataset.payload.rows.map(\.candidateID)) == retainedIDs)
    #expect(checkpoint.payload.producerRevisions == ["portrait-v4"])
    let sourceManifest = try #require(source.warpManifest)
    #expect(checkpoint.payload.warpRevisions == [sourceManifest.algorithmRevision])
    #expect(checkpoint.payload.evaluation.holdoutCount == 0)
    #expect(checkpoint.payload.evaluation.holdoutLoss == nil)
    #expect(model.training.activeCheckpoint(for: scope.id) == nil)
    await model.activateStyleCheckpoint(checkpoint.id)
    #expect(model.training.activeCheckpoint(for: scope.id)?.id == checkpoint.id)
    let retainedCount = model.sketches.entries.count
    var priorWidths: [Double] = [], trainedWidths: [Double] = []
    var changedGeometry = 0
    for seed in UInt64(31)...42 {
      model.sketches.selectedID = source.id
      model.compareSelectedStyle(checkpointID: checkpoint.id, seed: seed)
      await model.awaitRendering()
      let comparison = try #require(model.trainingComparison, "\(model.explorationStatus ?? model.summary)")
      try assertFrozenSemanticBranch(comparison.prior, source: source)
      try assertFrozenSemanticBranch(comparison.current, source: source)
      #expect(comparison.prior.checkpointID == nil)
      #expect(comparison.current.checkpointID == checkpoint.id)
      #expect(comparison.current.proposal?.trainingSelection?.checkpointID == checkpoint.id)
      #expect(comparison.current.proposal?.trainingSelection?.proposals.map(\.recipeSHA256)
        == comparison.prior.proposal?.trainingSelection?.proposals.map(\.recipeSHA256))
      priorWidths.append(try #require(comparison.prior.recipe.vectorOptions.semanticHead).foreheadWidth)
      trainedWidths.append(try #require(comparison.current.recipe.vectorOptions.semanticHead).foreheadWidth)
      if comparison.current.program.strokes.map(\.path) != comparison.prior.program.strokes.map(\.path) {
        changedGeometry += 1
      }
    }
    #expect(trainedWidths != priorWidths)
    #expect(trainedWidths.reduce(0, +) > priorWidths.reduce(0, +))
    #expect(changedGeometry > 0)
    #expect(model.sketches.entries.count == retainedCount)
    #expect(model.sketches.labels.count == 16)
    #expect(model.projectedCandidate?.id == originalProjected)

    // The actual semantic Random route also consumes the activated checkpoint.
    model.sketches.selectedID = source.id
    model.randomStyle(strokeStyle: try #require(source.program.strokes.first?.style), bigHead: true, seed: 73)
    await model.awaitRendering()
    let trained = try #require(model.selectedCandidate, "\(model.explorationStatus ?? model.summary)")
    try assertFrozenSemanticBranch(trained, source: source)
    #expect(trained.checkpointID == checkpoint.id)
    #expect(trained.recipe.vectorOptions.semanticHead != source.recipe.vectorOptions.semanticHead)

    // Ordinary More Like This changes line style locally while retaining this exact head.
    model.moreLikeThis(seed: 91)
    await model.awaitRendering()
    let local = try #require(model.selectedCandidate, "\(model.explorationStatus ?? model.summary)")
    #expect(local.lineage.parentID == trained.id)
    #expect(local.sourceData == trained.sourceData)
    #expect(local.rasterSHA256 == trained.rasterSHA256)
    #expect(local.recipe.analysisOptions == trained.recipe.analysisOptions)
    #expect(local.recipe.style == trained.recipe.style)
    #expect(local.recipe.vectorOptions.semanticHead == trained.recipe.vectorOptions.semanticHead)
    #expect(local.recipe.vectorOptions.headScale == trained.recipe.vectorOptions.headScale)
    #expect(local.recipe.vectorOptions.materialContext == trained.recipe.vectorOptions.materialContext)
    #expect(local.warpManifest == trained.warpManifest)
    #expect(local.program.strokes.allSatisfy { $0.style == trained.program.strokes.first?.style })
    await model.shutdown()
    let restarted = await PortraitCheckpointStore(directory: directory.appendingPathComponent("training")).load()
    #expect(restarted.canWrite)
    #expect(restarted.snapshot.activeCheckpointIDs[scope.id.uuidString] == checkpoint.id)
    #expect(restarted.snapshot.checkpoints.first?.payload.dataset.id == checkpoint.payload.dataset.id)
    // Synthetic landmark software evidence only: no independent source holdout,
    // live Vision extraction, human likeness, or attended physical drawing is implied.
  }
}

func semanticTrainingSource() throws -> PortraitCandidate {
  let raster = try PortraitSemanticHeadGeometryTests().fixture(width: 80, height: 80)
  let material = try PortraitMaterialContext(profile: .init(name: "Semantic fixture pen", nominalWidthMM: 0.8),
    drawingHeightMM: 130)
  let options = PortraitVectorOptions(simplificationTolerance: 0, hatchSpacing: 10,
    semanticHead: .init(), materialContext: material)
  let recipe = PortraitStyleRecipe(id: "semantic-training-reference", title: "Semantic training reference",
    seed: 19, style: .hatch, vectorOptions: options, analysisOptions: .init())
  let pen = try StrokeStyle(nominalLineWidth: 0.8,
    penProfileID: PenProfileID(UUID(uuidString: "00000000-0000-0000-0000-000000000001")!))
  let program = try PortraitVectorizer.program(from: raster, pose: .front, style: .hatch,
    strokeStyle: pen, vectorOptions: options)
  let manifest = PortraitHeadTransform(raster: raster, parameters: try #require(options.semanticHead)).manifest
  #expect(manifest.status == .applied || manifest.status == .limited)
  return try PortraitCandidate(sourceData: Data("exact-existing-synthetic-semantic-fixture".utf8),
    sourcePixelExtent: raster.sourceCropExtent, raster: raster, recipe: recipe, program: program,
    photoID: UUID(), captureSessionID: UUID(), pose: .front, warpManifest: manifest)
}

private func assertFrozenSemanticBranch(_ candidate: PortraitCandidate, source: PortraitCandidate) throws {
  try candidate.validateIntegrity()
  #expect(candidate.id != source.id)
  #expect(candidate.lineage.parentID == source.id)
  #expect(candidate.sourceData == source.sourceData)
  #expect(candidate.sourceSHA256 == source.sourceSHA256)
  #expect(candidate.sourcePixelExtent == source.sourcePixelExtent)
  #expect(candidate.rasterSHA256 == source.rasterSHA256)
  #expect(candidate.raster.analysisGeometry == source.raster.analysisGeometry)
  #expect(candidate.raster.faceAnalysis == source.raster.faceAnalysis)
  #expect(candidate.recipe.analysisOptions == source.recipe.analysisOptions)
  #expect(candidate.recipe.style == source.recipe.style)
  #expect(candidate.renderPose == source.renderPose)
  var options = candidate.recipe.vectorOptions
  options.semanticHead = source.recipe.vectorOptions.semanticHead
  #expect(options == source.recipe.vectorOptions)
  #expect(!candidate.program.strokes.isEmpty)
  #expect(candidate.program.strokes.allSatisfy { $0.style == source.program.strokes.first?.style })
  #expect(candidate.program.fieldExtent == source.program.fieldExtent)
  let manifest = try #require(candidate.warpManifest)
  #expect(manifest.status == .applied || manifest.status == .limited || manifest.status == .identity)
  #expect(manifest.analysisSHA256 == source.warpManifest?.analysisSHA256)
  #expect(manifest.basis == source.warpManifest?.basis)
  #expect(manifest.minimumJacobianDeterminant > 0)
}
