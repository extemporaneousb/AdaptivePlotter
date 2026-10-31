import Foundation
import PlotterModel
import PortraitArtists
import Testing

@Suite("Flow artist model and native proposal learning", .serialized)
struct FlowArtistModelTests {
  @Test("Broad and local recipes are deterministic native Flow coordinates, including straight and angular controls")
  func sampling() throws {
    let broad = FlowArtistRecipe.broad(count: 12, seed: 739)
    #expect(broad == FlowArtistRecipe.broad(count: 12, seed: 739))
    #expect(Set(broad).count == 12)
    #expect(broad.contains { ($0.vectorOptions.flowRectilinearity ?? 0) > 0.8 })
    #expect(broad.contains { ($0.vectorOptions.regionalTreatment?.angularity ?? 0) > 0.8 })
    let center = broad[3], refined = center.refined(count: 8, seed: 15, radius: 0.08)
    #expect(refined.first == center)
    #expect(refined == center.refined(count: 8, seed: 15, radius: 0.08))
    for recipe in refined {
      #expect(zip(recipe.values, center.values).allSatisfy { abs($0 - $1) <= 0.080000001 })
      #expect(recipe.vectorOptions.drawingParameters == nil)
      #expect(recipe.vectorOptions.semanticHead == nil)
    }
    let decoded = try JSONDecoder().decode(FlowArtistRecipe.self, from: JSONEncoder().encode(center))
    #expect(decoded == center)
    #expect(throws: (any Error).self) { try JSONDecoder().decode(FlowArtistRecipe.self, from: Data("{\"values\":[2]}".utf8)) }
  }

  @Test("Drawing features distinguish masks of identical recipes, retain image interactions and finite stroke context")
  func features() throws {
    let program = try fixtureProgram()
    let raster = PortraitRaster(width: 8, height: 8, luminance: (0..<64).map { Double($0 % 8) / 7 },
      provenance: "synthetic", analysisSummary: "Synthetic feature fixture")
    let dark = PortraitRaster(width: 8, height: 8, luminance: Array(repeating: 0.1, count: 64),
      provenance: "synthetic-dark", analysisSummary: "Synthetic feature fixture")
    let full = FlowArtistFeatures.drawing(recipe: .standard, program: program, raster: raster)
    let pruned = FlowArtistFeatures.drawing(recipe: .standard, program: program, raster: raster, removedIndices: [0])
    #expect(full.count == FlowArtistFeatures.drawingCount)
    #expect(full != pruned)
    #expect(full != FlowArtistFeatures.drawing(recipe: .standard, program: program, raster: dark))
    let strokes = FlowArtistFeatures.strokes(recipe: .standard, program: program, raster: raster)
    #expect(strokes.count == program.strokes.count)
    #expect(strokes.allSatisfy { $0.count == FlowArtistFeatures.strokeCount && $0.allSatisfy(\.isFinite) })
    #expect(strokes[0] != strokes[1])
  }

  @Test("A real numeric fit improves independent synthetic-photo holdouts, survives reload, deploys and rolls back exactly")
  func fitDeployRollback() throws {
    let dataset = fixtureDataset()
    let report = FlowArtistTraining.fit(examples: dataset.examples, rankings: dataset.rankings)
    let model = try #require(report.checkpoint)
    try model.validate()
    #expect(model.sourceGroupIDs.count == 12)
    #expect(model.holdoutGroupIDs.count == 3)
    #expect(report.ranker.improvesHoldout)
    #expect(report.deleter.improvesHoldout)
    #expect(try #require(report.ranker.accuracy) > 0.65)
    #expect(try #require(report.deleter.accuracy) > 0.7)
    let restored = try JSONDecoder().decode(FlowArtistCheckpoint.self, from: JSONEncoder().encode(model))
    #expect(restored.id == model.id)
    #expect(restored == model)
    let example = dataset.examples[0]
    #expect(try restored.score(features: example.features) == model.score(features: example.features))
    let probabilities = try restored.deletionProbabilities(strokeFeatures: example.strokeFeatures)
    #expect(probabilities.count == example.strokeFeatures.count)
    #expect(Set(probabilities).count > 1)
    let removed = try dataset.examples.map { try restored.removedIndices(strokeFeatures: $0.strokeFeatures, threshold: 0.5) }
    #expect(removed.contains { !$0.isEmpty })
    #expect(zip(removed, dataset.examples).allSatisfy { $0.count < $1.strokeFeatures.count })
    let refit = try #require(FlowArtistTraining.fit(examples: dataset.examples, rankings: dataset.rankings, seed: 43).checkpoint)
    var active = model
    let before = try active.score(features: example.features)
    active = refit
    #expect(active.id != model.id)
    active = restored
    #expect(try active.score(features: example.features) == before)
    #expect(FlowArtistTraining.fit(examples: Array(dataset.examples.reversed()), rankings: Array(dataset.rankings.reversed())).checkpoint == model)
  }

  @Test("No labels and deletion-only one-class evidence remain unfitted; a ranking head can fit independently")
  func evidenceBoundaries() throws {
    #expect(FlowArtistTraining.fit(examples: [], rankings: []).checkpoint == nil)
    let dataset = fixtureDataset()
    let oneClass = dataset.examples.map { example in
      FlowArtistExample(id: example.id, sourceGroupID: example.sourceGroupID, recipe: example.recipe,
        features: example.features, strokeFeatures: example.strokeFeatures,
        strokeLabels: example.strokeLabels.filter(\.removed))
    }
    let noRanks = FlowArtistTraining.fit(examples: oneClass, rankings: [])
    #expect(noRanks.checkpoint == nil)
    #expect(noRanks.deleter.status.contains("both remove and keep"))
    let partial = try #require(FlowArtistTraining.fit(examples: oneClass, rankings: dataset.rankings).checkpoint)
    #expect(partial.ranker != nil && partial.deleter == nil)
    #expect(partial.isExperimental)
    #expect(try partial.removedIndices(strokeFeatures: oneClass[0].strokeFeatures).isEmpty)
    let small = dataset.examples.filter { $0.sourceGroupID == "photo-0" }
    let smallRanks = dataset.rankings.filter { $0.id == "rank-0" }
    let exploratory = try #require(FlowArtistTraining.fit(examples: small, rankings: smallRanks).checkpoint)
    #expect(exploratory.holdoutGroupIDs.isEmpty && exploratory.isExperimental)
    #expect(exploratory.ranker?.report.holdoutLoss == nil)
  }

  @Test("Malformed schemas, nonfinite features, inconsistent labels and corrupted checkpoints are refused")
  func malformed() throws {
    let dataset = fixtureDataset(), source = dataset.examples[0]
    let bad = FlowArtistExample(id: source.id, sourceGroupID: source.sourceGroupID, recipe: source.recipe,
      features: [.nan], strokeFeatures: source.strokeFeatures)
    #expect(FlowArtistTraining.fit(examples: [bad], rankings: []).checkpoint == nil)
    let invalid = FlowArtistExample(id: source.id, sourceGroupID: source.sourceGroupID, recipe: source.recipe,
      features: source.features, strokeFeatures: source.strokeFeatures,
      strokeLabels: [.init(index: 0, removed: false, provenance: .remove)])
    #expect(FlowArtistTraining.fit(examples: [invalid], rankings: []).checkpoint == nil)
    #expect(FlowArtistTraining.fit(examples: [source, source], rankings: []).checkpoint == nil)
    let model = try #require(FlowArtistTraining.fit(examples: dataset.examples, rankings: dataset.rankings).checkpoint)
    var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(model)) as? [String: Any])
    object["featureRevision"] = "different-features"
    let corrupted = try JSONDecoder().decode(FlowArtistCheckpoint.self, from: JSONSerialization.data(withJSONObject: object))
    #expect(throws: (any Error).self) { try corrupted.validate() }
    #expect(throws: (any Error).self) { try model.score(features: [1, 2]) }
    #expect(throws: (any Error).self) { try model.removedIndices(strokeFeatures: source.strokeFeatures, threshold: .nan) }
  }

  @Test("Refinement choice trains only chosen comparisons; unchosen alternatives are not tied")
  func choiceSemantics() throws {
    let dataset = fixtureDataset(), examples = Array(dataset.examples.prefix(6))
    let choice = FlowArtistRanking(id: "choice", tiers: [[examples[0].id], Array(examples.dropFirst().map(\.id))], provenance: .choice)
    let report = FlowArtistTraining.fit(examples: examples, rankings: [choice])
    #expect(report.ranker.trainingCount == 5)
    let tied = FlowArtistRanking(id: "rank", tiers: choice.tiers)
    #expect(FlowArtistTraining.fit(examples: examples, rankings: [tied]).ranker.trainingCount == 15)
  }

  @Test("Ranked masks on an exact common basis train deletion utility without fabricated per-stroke labels")
  func rankedMasks() throws {
    var examples: [FlowArtistExample] = [], rankings: [FlowArtistRanking] = []
    for group in 0..<4 {
      let strokeFeatures = [0.1, 0.9, 0.2, 0.8].map { value -> [Double] in
        var features = Array(repeating: 0.0, count: FlowArtistFeatures.strokeCount)
        features[0] = 1; features[1] = value
        return features
      }
      let masks = [[1, 3], [1], [], [0]]
      var ids: [String] = []
      for (index, mask) in masks.enumerated() {
        let id = "mask-\(group)-\(index)"
        var features = Array(repeating: 0.0, count: FlowArtistFeatures.drawingCount)
        features[0] = 1; features[1] = Double(mask.count) / 4
        features[2] = mask.reduce(0) { $0 + strokeFeatures[$1][1] } / 4
        examples.append(.init(id: id, sourceGroupID: "photo-\(group)", recipe: .standard,
          features: features, strokeFeatures: strokeFeatures, baseDrawingID: "base-\(group)", removedIndices: mask))
        ids.append(id)
      }
      rankings.append(.init(id: "ranked-mask-\(group)", tiers: ids.map { [$0] }))
    }
    let fitted = FlowArtistTraining.fit(examples: examples, rankings: rankings)
    let model = try #require(fitted.checkpoint)
    #expect(model.deleter != nil)
    #expect(fitted.deleter.improvesHoldout)
    let predictions = try model.deletionProbabilities(strokeFeatures: examples[0].strokeFeatures)
    #expect(predictions[1] > predictions[0])
    #expect(predictions[3] > predictions[2])
    // Different bases do not provide attributable mask-comparison supervision.
    let unrelated = examples.map { FlowArtistExample(id: $0.id, sourceGroupID: $0.sourceGroupID,
      recipe: $0.recipe, features: $0.features, strokeFeatures: $0.strokeFeatures,
      baseDrawingID: $0.id, removedIndices: $0.removedIndices) }
    #expect(FlowArtistTraining.fit(examples: unrelated, rankings: rankings).checkpoint?.deleter == nil)
  }

  @Test("Perfect held-out rankings with uneven group burdens remain valid at the floating-point metric boundary")
  func boundedMetrics() throws {
    var examples: [FlowArtistExample] = [], rankings: [FlowArtistRanking] = []
    // These panels produce 15, 21, 28 and 45 comparisons. Sequential summation
    // of their normalized weights can exceed one by a few floating-point ulps.
    for (group, count) in [6, 7, 8, 10].enumerated() {
      var ids: [String] = []
      for index in 0..<count {
        let id = "bounded-\(group)-\(index)"
        var features = Array(repeating: 0.0, count: FlowArtistFeatures.drawingCount)
        features[0] = 1; features[1] = Double(index) / Double(count)
        examples.append(.init(id: id, sourceGroupID: "bounded-photo-\(group)", recipe: .standard,
          features: features, strokeFeatures: []))
        ids.append(id)
      }
      rankings.append(.init(id: "bounded-ranking-\(group)", tiers: ids.reversed().map { [$0] }))
    }
    let result = FlowArtistTraining.fit(examples: examples, rankings: rankings)
    let checkpoint = try #require(result.checkpoint, "\(result.summary)")
    try checkpoint.validate()
    #expect(checkpoint.holdoutGroupIDs.count == 1)
    #expect(result.ranker.accuracy == 1)
    #expect(result.ranker.improvesHoldout)
    // Deployment rates also average binary outcomes. Nine removal labels yield
    // a keep-all error of one, whose naive weighted accumulation is 1 + one ulp.
    let holdout = try #require(checkpoint.holdoutGroupIDs.first)
    let deletionExamples = (0..<4).map { group -> FlowArtistExample in
      let groupID = "bounded-photo-\(group)"
      var features = Array(repeating: 0.0, count: FlowArtistFeatures.drawingCount)
      features[0] = 1
      var strokes: [[Double]] = [], labels: [FlowArtistStrokeLabel] = []
      for index in 0..<9 {
        let removed = groupID == holdout || index.isMultiple(of: 2)
        var stroke = Array(repeating: 0.0, count: FlowArtistFeatures.strokeCount)
        stroke[0] = 1; stroke[1] = removed ? 1 : -1
        strokes.append(stroke)
        labels.append(.init(index: index, removed: removed, provenance: .completedMask))
      }
      return .init(id: "bounded-delete-\(group)", sourceGroupID: groupID, recipe: .standard,
        features: features, strokeFeatures: strokes, strokeLabels: labels)
    }
    let deletionResult = FlowArtistTraining.fit(examples: deletionExamples, rankings: [])
    let deletionCheckpoint = try #require(deletionResult.checkpoint, "\(deletionResult.summary)")
    try deletionCheckpoint.validate()
    #expect(deletionResult.deleter.keepAllCorrectionRate == 1)
    #expect(abs(try #require(deletionResult.deleter.deploymentCorrectionRate) - 1.0 / 9) < 1e-12)
    #expect(abs(try #require(deletionResult.deleter.deploymentRecall) - 8.0 / 9) < 1e-12)
    #expect(deletionResult.deleter.trainingRemoveCount == 15)
    #expect(deletionResult.deleter.trainingKeepCount == 12)
    #expect(deletionResult.deleter.holdoutRemoveCount == 9)
    #expect(deletionResult.deleter.holdoutKeepCount == 0)
    #expect(deletionResult.deleter.status.contains("false-deletion cost is untested"))
    let combined = try #require(FlowArtistTraining.fit(examples: examples + deletionExamples,
      rankings: rankings).checkpoint)
    #expect(combined.ranker?.report.improvesHoldout == true)
    #expect(combined.deleter?.report.improvesHoldout == true)
    #expect(combined.isExperimental) // A remove-only holdout cannot assess false deletions.
    var legacy = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(combined)) as? [String: Any])
    var oldDeleter = try #require(legacy["deleter"] as? [String: Any])
    var oldReport = try #require(oldDeleter["report"] as? [String: Any])
    for key in ["trainingRemoveCount", "trainingKeepCount", "holdoutRemoveCount", "holdoutKeepCount"] {
      oldReport.removeValue(forKey: key)
    }
    oldDeleter["report"] = oldReport; legacy["deleter"] = oldDeleter
    let legacyCheckpoint = try JSONDecoder().decode(FlowArtistCheckpoint.self,
      from: JSONSerialization.data(withJSONObject: legacy))
    try legacyCheckpoint.validateArchive()
    #expect(legacyCheckpoint.deleter?.report.holdoutKeepCount == nil && legacyCheckpoint.isExperimental)
    // Normalize computed roundoff; do not weaken validation of stored artifacts.
    var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(checkpoint)) as? [String: Any])
    var ranker = try #require(object["ranker"] as? [String: Any])
    var report = try #require(ranker["report"] as? [String: Any])
    report["accuracy"] = 1.01; ranker["report"] = report; object["ranker"] = ranker
    let corrupt = try JSONDecoder().decode(FlowArtistCheckpoint.self, from: JSONSerialization.data(withJSONObject: object))
    #expect(throws: (any Error).self) { try corrupt.validate() }
  }

  private func fixtureDataset() -> (examples: [FlowArtistExample], rankings: [FlowArtistRanking]) {
    var random = FlowArtistRandom(seed: 421), examples: [FlowArtistExample] = [], rankings: [FlowArtistRanking] = []
    for group in 0..<12 {
      let photo = Double(group) / 11
      var ordered: [(String, Double)] = []
      for candidate in 0..<6 {
        let tone = random.unit(), rect = random.unit(), id = "photo-\(group)-candidate-\(candidate)"
        var features = Array(repeating: 0.0, count: FlowArtistFeatures.drawingCount)
        features.replaceSubrange(0..<7, with: [1, tone, rect, tone * tone, rect * rect, photo * tone, photo * rect])
        var strokes: [[Double]] = [], labels: [FlowArtistStrokeLabel] = []
        for index in 0..<12 {
          let edge = Double(index) / 11, region = random.unit()
          var stroke = Array(repeating: 0.0, count: FlowArtistFeatures.strokeCount)
          stroke.replaceSubrange(0..<6, with: [1, edge, region, rect, photo * region, rect * edge])
          let removed = -1.2 + 2 * edge - region - 0.5 * rect + 1.5 * photo * region - 0.6 * rect * edge > 0
          strokes.append(stroke)
          labels.append(.init(index: index, removed: removed, provenance: .completedMask))
        }
        examples.append(.init(id: id, sourceGroupID: "photo-\(group)", recipe: .standard,
          features: features, strokeFeatures: strokes, strokeLabels: labels))
        ordered.append((id, -pow(tone - (0.2 + 0.6 * photo), 2) - pow(rect - (0.9 - 0.7 * photo), 2)))
      }
      rankings.append(.init(id: "rank-\(group)", tiers: ordered.sorted { $0.1 > $1.1 }.map { [$0.0] }))
    }
    return (examples, rankings)
  }

  private func fixtureProgram() throws -> DrawingProgram {
    let style = try StrokeStyle(nominalLineWidth: 0.4, penProfileID: PenProfileID())
    let a = LogicalStroke(id: StrokeID(), path: try .init(points: [.init(x: 10, y: 20), .init(x: 70, y: 20)]), style: style, ordering: 0)
    let b = LogicalStroke(id: StrokeID(), path: try .init(points: [.init(x: 20, y: 70), .init(x: 35, y: 50), .init(x: 80, y: 80)]), style: style, ordering: 1)
    return try DrawingProgram(id: ProgramID(), fieldExtent: .init(width: 100, height: 100), strokes: [a, b],
      source: .init(kind: "portrait", sourceIdentifier: "synthetic-flow-artist-tests"))
  }
}
