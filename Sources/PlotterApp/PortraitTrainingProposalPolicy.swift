import Foundation
import PlotterModel

struct PortraitTrainingComparison: Sendable {
  let prior: PortraitCandidate
  let current: PortraitCandidate
  let checkpointID: String
  let seed: UInt64
  let summary: String
}

struct PortraitTrainingProposalRequest: Sendable {
  enum Kind: Sendable { case broad, local, semanticHead }
  let parent: PortraitCandidate
  let scope: PortraitTrainingScopeDefinition
  let checkpoint: PortraitPreferenceCheckpoint?
  let priorCheckpoint: PortraitPreferenceCheckpoint?
  let presentation: PortraitTrainingPresentation
  let seed: UInt64
  let kind: Kind
  let comparesPrior: Bool
}

struct PortraitTrainingRenderOutput: Sendable {
  let candidate: PortraitCandidate
  let comparison: PortraitTrainingComparison?
}

/// Bounded real rendering, then learned ranking. All work runs inside the
/// Studio's existing joined renderer lifetime; pool members stay transient.
enum PortraitTrainingProposalPolicy {
  static let revision = "portrait-scoped-rendered-pool-v1"
  static let poolCount = 8
  static let explorationProbability = 0.2

  static func generate(_ request: PortraitTrainingProposalRequest,
    renderer: any PortraitRendering) async throws -> PortraitTrainingRenderOutput {
    try PortraitTrainingValidation.scope(request.scope)
    let schema = try PortraitTrainingFeatures.schema(scope: request.scope)
    for checkpoint in [request.checkpoint, request.priorCheckpoint].compactMap({ $0 }) {
      try PortraitTrainingValidation.checkpoint(checkpoint)
      guard checkpoint.payload.dataset.payload.scope == request.scope,
        checkpoint.payload.dataset.payload.featureSchema == schema else {
        throw PortraitTrainingError.incompatible("The selected checkpoint does not match this scope and feature schema.")
      }
    }
    guard let pose = request.parent.renderPose, let pen = request.parent.program.strokes.first?.style else {
      throw PortraitTrainingError.invalid("A complete source, pose and pen style are required.")
    }
    if request.kind == .local, request.scope.mode == .semanticBigHead {
      throw PortraitTrainingError.incompatible("Use Vary Big Head for semantic fitting; ordinary local exploration freezes the head.")
    }
    var random = PortraitRecipeRandom(seed: request.seed)
    var candidates: [PortraitCandidate] = [], features: [[Double]] = []
    for _ in 0..<poolCount {
      try Task.checkCancellation()
      let seed = random.next()
      let prior = request.kind == .local ? PortraitProposalPolicy.local(parent: request.parent, seed: seed)
        : PortraitProposalPolicy.broad(seed: seed, penWidthMM: pen.nominalLineWidth,
          bigHead: request.scope.mode == .semanticBigHead)
      var vectors = request.kind == .local ? request.parent.recipe.vectorOptions : request.scope.referenceRecipe.vectorOptions
      vectors.materialContext = request.parent.recipe.vectorOptions.materialContext
      let local = Set(PortraitProposalPolicy.localParameters(
        family: request.parent.proposal?.family ?? PortraitExplorationFamily.infer(from: request.parent.recipe),
        headScale: request.parent.recipe.vectorOptions.headScale))
      for parameter in request.scope.scope.activeParameters {
        if request.kind == .local, !local.contains(parameter) { continue }
        let value = request.kind == .semanticHead
          ? random.value(PortraitTrainingFeatures.bounds(parameter))
          : PortraitTrainingFeatures.value(parameter, in: prior.recipe.vectorOptions)
        vectors = PortraitTrainingFeatures.setting(parameter, value: value, in: vectors)
      }
      // Semantic exploration changes only amplitudes in this exact branch.
      if request.kind == .semanticHead {
        let head = vectors.semanticHead
        vectors = request.parent.recipe.vectorOptions
        vectors.semanticHead = head
      }
      let family: PortraitStyle
      if request.kind == .local || request.kind == .semanticHead { family = request.parent.recipe.style }
      else if request.scope.scope.allowedFamilies.contains(prior.recipe.style) { family = prior.recipe.style }
      else { family = request.scope.scope.allowedFamilies[random.index(request.scope.scope.allowedFamilies.count)] }
      let recipe = PortraitStyleRecipe(id: "scoped-" + String(seed), title: request.scope.scope.name,
        seed: seed, style: family, vectorOptions: vectors.bounded,
        analysisOptions: request.parent.recipe.analysisOptions)
      let rendered = try await renderer.render(.init(data: request.parent.sourceData, pose: pose,
        style: family, options: recipe.analysisOptions, cachedRaster: request.parent.raster,
        strokeStyle: pen, vectorOptions: recipe.vectorOptions, sourcePixelExtent: request.parent.sourcePixelExtent))
      let candidate = try makeCandidate(parent: request.parent, recipe: recipe, rendered: rendered,
        checkpointID: nil, kind: request.kind, selection: nil)
      let values = try PortraitTrainingFeatures.values(candidate: candidate, scope: request.scope,
        schema: schema, presentation: request.presentation)
      for checkpoint in [request.checkpoint, request.priorCheckpoint].compactMap({ $0 }) {
        guard checkpoint.payload.producerRevisions.contains(candidate.producerRevision),
          candidate.warpManifest.map({ checkpoint.payload.warpRevisions.contains($0.algorithmRevision) }) ?? checkpoint.payload.warpRevisions.isEmpty else {
          throw PortraitTrainingError.incompatible("Rendered producer or semantic warp differs from the fitted checkpoint.")
        }
      }
      candidates.append(candidate); features.append(values)
    }
    func selected(using checkpoint: PortraitPreferenceCheckpoint?) throws -> PortraitCandidate {
      var selectionRandom = PortraitRecipeRandom(seed: request.seed ^ 0x6a09e667f3bcc909)
      let explored = checkpoint == nil || selectionRandom.value(0...1) < explorationProbability
      let utilities = try features.map { values in
        try checkpoint.map { try PortraitOrdinalTrainer.utility(model: $0.payload.model, features: values) } ?? 0
      }
      var diversity = [Double](repeating: 0, count: features.count)
      for index in features.indices {
        var nearest = Double.infinity
        for other in features.indices where other != index {
          var distance = 0.0
          for component in features[index].indices {
            distance += abs(features[index][component] - features[other][component])
          }
          nearest = min(nearest, distance / Double(max(1, features[index].count)))
        }
        diversity[index] = nearest.isFinite ? nearest : 0
      }
      let index = explored ? selectionRandom.index(candidates.count) : candidates.indices.max {
        utilities[$0] + 0.05 * diversity[$0] < utilities[$1] + 0.05 * diversity[$1]
      }!
      let selection = PortraitTrainingSelection(revision: revision, scopeID: request.scope.id,
        checkpointID: checkpoint?.id, seed: request.seed,
        proposals: candidates.indices.map { .init(recipeSHA256: candidates[$0].recipeSHA256,
          utility: utilities[$0], diversity: diversity[$0]) }, selectedIndex: index,
        explored: explored, explorationProbability: explorationProbability)
      let chosen = candidates[index]
      return try makeCandidate(parent: request.parent, recipe: chosen.recipe,
        rendered: .init(raster: chosen.raster, program: chosen.program, warpManifest: chosen.warpManifest),
        checkpointID: checkpoint?.id, kind: request.kind, selection: selection)
    }
    let current = try selected(using: request.checkpoint)
    var comparison: PortraitTrainingComparison?
    if request.comparesPrior, let checkpoint = request.checkpoint {
      let prior = try selected(using: request.priorCheckpoint)
      comparison = .init(prior: prior, current: current, checkpointID: checkpoint.id, seed: request.seed,
        summary: "Same source, crop and eight rendered proposals; prior and selected checkpoint use the same seed. "
          + (prior.program.contentHash == current.program.contentHash ? "Both selected the same geometry. " : "The selections differ. ")
          + "This is a configuration comparison, not a human likeness or physical-quality result.")
    }
    return .init(candidate: current, comparison: comparison)
  }

  private static func makeCandidate(parent: PortraitCandidate, recipe: PortraitStyleRecipe,
    rendered: PortraitRenderResult, checkpointID: String?, kind: PortraitTrainingProposalRequest.Kind,
    selection: PortraitTrainingSelection?) throws -> PortraitCandidate {
    var metadata = PortraitProposalMetadata(policyRevision: revision,
      kind: kind == .semanticHead ? .semanticTraining : kind == .local ? .local : .broad,
      seed: recipe.seed, family: PortraitExplorationFamily.infer(from: recipe))
    metadata.trainingSelection = selection
    return try PortraitCandidate(sourceData: parent.sourceData, sourcePixelExtent: parent.sourcePixelExtent,
      raster: rendered.raster, recipe: recipe, program: rendered.program, photoID: parent.photoID,
      captureSessionID: parent.captureSessionID,
      lineage: .init(parentID: parent.id, parentProgramHash: parent.program.contentHash.description,
        parentRecipe: parent.recipe, ancestryGroupID: parent.lineage.ancestryGroupID),
      checkpointID: checkpointID, pose: parent.renderPose, proposal: metadata, warpManifest: rendered.warpManifest)
  }
}
