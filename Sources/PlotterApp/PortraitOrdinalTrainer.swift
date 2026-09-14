import Foundation

enum PortraitOrdinalTrainer {
  static func utility(model: PortraitPreferenceModel, features: [Double]) throws -> Double {
    guard model.weights.count == features.count, model.weights.allSatisfy(\.isFinite), features.allSatisfy(\.isFinite) else { throw PortraitTrainingError.nonFinite }
    let result = zip(model.weights, features).reduce(0) { $0 + $1.0 * $1.1 }
    guard result.isFinite else { throw PortraitTrainingError.nonFinite }
    return result
  }

  private static func sigmoid(_ value: Double) -> Double {
    if value >= 0 { return 1 / (1 + exp(-value)) }
    let e = exp(value); return e / (1 + e)
  }

  private static func likelihood(_ model: PortraitPreferenceModel, row: PortraitPreferenceDataset.Row) throws -> (Double, Double, Double, Double) {
    let utility = try utility(model: model, features: row.features), category = row.label.rating - 1
    let upper = category == 4 ? 1 : sigmoid(model.thresholds[category] - utility)
    let lower = category == 0 ? 0 : sigmoid(model.thresholds[category - 1] - utility)
    let probability = max(1e-12, upper - lower)
    return (probability, upper * (1-upper), lower * (1-lower), utility)
  }

  private static func loss(_ model: PortraitPreferenceModel, rows: [PortraitPreferenceDataset.Row]) throws -> Double {
    guard !rows.isEmpty else { throw PortraitTrainingError.insufficientData("No evaluation rows.") }
    var total = 0.0
    for (index, row) in rows.enumerated() {
      if index % 128 == 0 { try Task.checkCancellation() }
      total -= log(try likelihood(model, row: row).0)
    }
    return total / Double(rows.count)
  }

  static func fit(dataset: PortraitPreferenceDataset, parent: PortraitPreferenceCheckpoint?,
    configuration: PortraitOrdinalFitConfiguration = .standard) async throws -> PortraitPreferenceCheckpoint {
    try Task.checkCancellation()
    try PortraitTrainingValidation.dataset(dataset)
    try PortraitTrainingValidation.configuration(configuration)
    let payload = dataset.payload
    let producerRevisions = Set(payload.rows.map(\.producerRevision)).sorted()
    let warpRevisions = Set(payload.rows.compactMap(\.warpRevision)).sorted()
    if let parent {
      try PortraitTrainingValidation.checkpoint(parent)
      guard parent.payload.dataset.payload.scope == payload.scope,
        parent.payload.dataset.payload.featureSchema == payload.featureSchema,
        parent.payload.producerRevisions == producerRevisions, parent.payload.warpRevisions == warpRevisions else {
        throw PortraitTrainingError.incompatible("Continued fit requires the same scope, feature schema, producer and warp revisions.")
      }
    }
    let train = payload.rows.filter { $0.split == .training }, holdout = payload.rows.filter { $0.split == .holdout }
    guard train.count >= configuration.minimumLabels else { throw PortraitTrainingError.insufficientData("At least \(configuration.minimumLabels) training labels are required after grouped holdout.") }
    guard Set(train.map { $0.label.rating }).count > 1 else { throw PortraitTrainingError.insufficientData("Ratings are constant.") }
    let activeCount = payload.scope.scope.activeParameters.count * 2
    guard (0..<activeCount).contains(where: { column in
      let values = train.map { $0.features[column] }; return (values.max() ?? 0) - (values.min() ?? 0) > 1e-8
    }) else { throw PortraitTrainingError.insufficientData("Active recipe parameters do not vary.") }
    let prior = PortraitPreferenceModel(weights: Array(repeating: 0, count: payload.featureSchema.features.count), thresholds: [-1.5, -0.5, 0.5, 1.5])
    var model = prior, previousObjective = Double.infinity, converged = false, completed = 0
    for iteration in 0..<configuration.maximumIterations {
      try Task.checkCancellation()
      if iteration % 16 == 0 { await Task.yield() }
      var weightGradient = Array(repeating: 0.0, count: model.weights.count), thresholdGradient = Array(repeating: 0.0, count: 4)
      for (index, row) in train.enumerated() {
        if index % 128 == 0 { try Task.checkCancellation() }
        let (probability, upperDerivative, lowerDerivative, _) = try likelihood(model, row: row)
        let du = (upperDerivative - lowerDerivative) / probability
        for column in weightGradient.indices { weightGradient[column] += du * row.features[column] / Double(train.count) }
        let category = row.label.rating - 1
        if category < 4 { thresholdGradient[category] -= upperDerivative / probability / Double(train.count) }
        if category > 0 { thresholdGradient[category - 1] += lowerDerivative / probability / Double(train.count) }
      }
      guard weightGradient.allSatisfy(\.isFinite), thresholdGradient.allSatisfy(\.isFinite) else { throw PortraitTrainingError.nonFinite }
      var weights = model.weights, thresholds = model.thresholds
      for index in weights.indices {
        weightGradient[index] += configuration.regularization * weights[index]
        weights[index] = min(30, max(-30, weights[index] - configuration.learningRate * weightGradient[index]))
      }
      for index in thresholds.indices { thresholds[index] = min(29, max(-29, thresholds[index] - configuration.learningRate * thresholdGradient[index])) }
      // Euclidean projection on ordered thresholds with a fixed 0.05 minimum gap.
      var blocks: [(sum: Double, count: Int)] = []
      for index in thresholds.indices {
        blocks.append((thresholds[index] - 0.05 * Double(index), 1))
        while blocks.count > 1 {
          let a = blocks[blocks.count-2], b = blocks[blocks.count-1]
          if a.sum / Double(a.count) <= b.sum / Double(b.count) { break }
          blocks.removeLast(2); blocks.append((a.sum+b.sum, a.count+b.count))
        }
      }
      thresholds = blocks.flatMap { block in Array(repeating: block.sum / Double(block.count), count: block.count) }
        .enumerated().map { $0.element + 0.05 * Double($0.offset) }
      guard weights.allSatisfy(\.isFinite), thresholds.allSatisfy(\.isFinite) else { throw PortraitTrainingError.nonFinite }
      model = .init(weights: weights, thresholds: thresholds)
      let objective = try loss(model, rows: train) + configuration.regularization * weights.reduce(0) { $0 + $1*$1 } / 2
      guard objective.isFinite else { throw PortraitTrainingError.nonFinite }
      completed = iteration + 1
      if abs(previousObjective - objective) < configuration.convergenceTolerance { converged = true; break }
      previousObjective = objective
    }
    try Task.checkCancellation()
    var limitations = ["Deterministic full refit resets optimizer state; no mid-iteration recovery is claimed.",
      "Grouped evaluation measures this retained labeled dataset; it does not establish real user preference or physical drawing quality."]
    let holdoutLoss = holdout.isEmpty ? nil : try loss(model, rows: holdout)
    var priorLoss: Double?
    if holdout.isEmpty { limitations.append("No independent heldout source groups are available.") }
    else if let parent {
      let parentTraining = parent.payload.dataset.payload.rows.filter { $0.split == .training }
      let sources = Set(parentTraining.map(\.sourceSHA256)), sessions = Set(parentTraining.map(\.captureSessionID)), ancestry = Set(parentTraining.map(\.ancestryGroupID))
      let overlap = holdout.contains { sources.contains($0.sourceSHA256) || sessions.contains($0.captureSessionID) || ancestry.contains($0.ancestryGroupID) }
      if overlap { limitations.append("Parent training overlaps child holdout provenance; independent parent comparison is omitted.") }
      else { priorLoss = try loss(parent.payload.model, rows: holdout); limitations.append("Prior holdout loss scores the compatible parent on this checkpoint's exact heldout rows.") }
    } else { priorLoss = try loss(prior, rows: holdout); limitations.append("Prior holdout loss scores the initial zero-weight ordinal model on identical heldout rows.") }
    var pairs = 0, correct = 0.0
    let sameSourceRows = Dictionary(grouping: holdout, by: \.sourceSHA256)
    var inspectedPairs = 0
    for source in sameSourceRows.keys.sorted() {
      try Task.checkCancellation()
      let rows = sameSourceRows[source]!
      var utilities: [Double] = []
      for (index, row) in rows.enumerated() {
        if index % 128 == 0 { try Task.checkCancellation(); await Task.yield() }
        utilities.append(try utility(model: model, features: row.features))
      }
      for i in rows.indices {
        if i % 128 == 0 { try Task.checkCancellation() }
        for j in (i + 1)..<rows.count {
          if inspectedPairs % 1024 == 0 { try Task.checkCancellation(); await Task.yield() }
          inspectedPairs += 1
          guard rows[i].label.rating != rows[j].label.rating else { continue }
          let difference = utilities[i] - utilities[j]
          let expected = Double(rows[i].label.rating - rows[j].label.rating)
          pairs += 1; correct += difference == 0 ? 0.5 : (difference * expected > 0 ? 1 : 0)
        }
      }
    }
    if pairs == 0 { limitations.append("No different-label, same-source heldout pairs exist; ordering accuracy is unavailable.") }
    let evaluation = PortraitPreferenceEvaluation(trainingCount: train.count, holdoutCount: holdout.count,
      trainingGroupCount: Set(train.map(\.groupID)).count, holdoutGroupCount: Set(holdout.map(\.groupID)).count,
      trainingLoss: try loss(model, rows: train), holdoutLoss: holdoutLoss, priorHoldoutLoss: priorLoss,
      withinSourceOrderingAccuracy: pairs == 0 ? nil : correct / Double(pairs), comparablePairCount: pairs, limitations: limitations)
    let checkpoint = try PortraitPreferenceCheckpoint(payload: .init(revision: "portrait-ordinal-checkpoint-v1", dataset: dataset,
      configuration: configuration, parentCheckpointID: parent?.id, initialization: .deterministicFullRefit,
      optimizerState: .reset, model: model, completedIterations: completed, converged: converged,
      evaluation: evaluation, producerRevisions: producerRevisions, warpRevisions: warpRevisions))
    try PortraitTrainingValidation.checkpoint(checkpoint)
    try Task.checkCancellation()
    return checkpoint
  }
}
