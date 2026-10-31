import Foundation

/// Pairwise Bradley–Terry utility and contextual binary stroke selection. See
/// https://proceedings.mlr.press/v37/park15.pdf for score-difference preference
/// likelihood; the model here is deliberately a small single-artist regression.
package enum FlowArtistTraining {
  private struct Row {
    let x: [Double]
    let y: Double
    var weight: Double
    let groups: Set<String>
    var isComparison = false
  }

  package static func fit(examples: [FlowArtistExample], rankings: [FlowArtistRanking], seed: UInt64 = 42) -> FlowArtistFitReport {
    func unavailable(_ reason: String) -> FlowArtistFitReport {
      .init(checkpoint: nil, summary: reason, ranker: .unavailable(reason), deleter: .unavailable(reason))
    }
    guard examples.count <= 5000, rankings.count <= 5000,
      Set(examples.map(\.id)).count == examples.count,
      Set(rankings.map(\.id)).count == rankings.count else {
      return unavailable("Training refused duplicate identities or an oversized dataset.")
    }
    guard !examples.isEmpty else { return unavailable("No curated examples. Generate drawings and add rankings or pruning decisions.") }
    var featureElements = 0, explicitLabels = 0
    for example in examples {
      if Task.isCancelled { return unavailable("Fit cancelled; the active checkpoint remains unchanged.") }
      featureElements += example.features.count + example.strokeFeatures.reduce(0) { $0 + $1.count }
      explicitLabels += example.strokeLabels.count
      guard featureElements <= 8_000_000, explicitLabels <= 20_000 else {
        return unavailable("This local fit exceeds 8 million feature values or 20,000 explicit stroke labels. Exclude some sources or drawings from this fit; their portfolio records remain intact.")
      }
      guard !example.id.isEmpty, !example.sourceGroupID.isEmpty,
        valid(example.features, count: FlowArtistFeatures.drawingCount),
        example.strokeFeatures.count <= 10_000,
        example.strokeFeatures.allSatisfy({ valid($0, count: FlowArtistFeatures.strokeCount) }),
        Set(example.removedIndices).count == example.removedIndices.count,
        example.removedIndices.allSatisfy({ example.strokeFeatures.indices.contains($0) }),
        Set(example.strokeLabels.map(\.index)).count == example.strokeLabels.count,
        example.strokeLabels.allSatisfy({ label in
          example.strokeFeatures.indices.contains(label.index)
            && (label.provenance != .remove || label.removed)
            && (label.provenance != .restore || !label.removed)
        }) else { return unavailable("Training refused malformed features, duplicate stroke labels or inconsistent correction provenance.") }
    }
    let examples = examples.sorted { $0.id < $1.id }, rankings = rankings.sorted { $0.id < $1.id }
    let byID = Dictionary(uniqueKeysWithValues: examples.map { ($0.id, $0) })
    let groups = Set(examples.map(\.sourceGroupID)).sorted()
    var random = FlowArtistRandom(seed: seed)
    var groupOrder: [(group: String, key: UInt64)] = []
    for group in groups { groupOrder.append((group: group, key: random.next())) }
    groupOrder.sort { left, right in left.key == right.key ? left.group < right.group : left.key < right.key }
    let shuffled: [String] = groupOrder.map { $0.group }
    // Small-data fits remain explicitly experimental instead of inventing
    // independent-photo quality. Three groups permit a fixed held-out group.
    let holdout = Set<String>(groups.count >= 3 ? Array(shuffled.suffix(max(1, groups.count / 4))) : [])
    var rankRows: [Row] = [], maskRows: [Row] = []
    for ranking in rankings {
      let ids = ranking.tiers.flatMap { $0 }
      guard !ranking.id.isEmpty, ids.count <= 100, ranking.tiers.allSatisfy({ !$0.isEmpty }),
        Set(ids).count == ids.count, ids.allSatisfy({ byID[$0] != nil }) else {
        return unavailable("Training refused a ranking with missing, repeated or unbounded drawing identities.")
      }
      var rows: [Row] = [], masks: [Row] = []
      let ordered = ranking.tiers.enumerated().flatMap { tier, ids in ids.sorted().map { (tier, $0) } }
      for a in ordered.indices { for b in ordered.indices where b > a {
        if ranking.provenance == .choice, ordered[a].0 != 0 || ordered[b].0 == 0 { continue }
        let left = byID[ordered[a].1]!, right = byID[ordered[b].1]!
        let target = ordered[a].0 == ordered[b].0 ? 0.5 : 1.0
        let delta = zip(left.features, right.features).map { $0 - $1 }
        if delta.contains(where: { abs($0) > 1e-12 }) {
          rows.append(Row(x: delta, y: target, weight: 1,
            groups: Set([left.sourceGroupID, right.sourceGroupID]), isComparison: true))
        }
        // A ranked pair of exact masks on one frozen basis directly informs
        // deletion utility, without converting either entire mask into invented
        // independent per-stroke approvals. Different recipes/photos cannot
        // identify a deletion effect and therefore do not enter this objective.
        if ranking.provenance == .ranking, let basis = left.baseDrawingID,
          basis == right.baseDrawingID, left.recipe == right.recipe,
          left.sourceGroupID == right.sourceGroupID,
          !left.strokeFeatures.isEmpty, left.strokeFeatures == right.strokeFeatures,
          left.removedIndices != right.removedIndices {
          var difference = Array(repeating: 0.0, count: FlowArtistFeatures.strokeCount)
          let a = Set(left.removedIndices), b = Set(right.removedIndices)
          let normalizer = Double(left.strokeFeatures.count)
          for index in a.symmetricDifference(b).sorted() {
            let direction = a.contains(index) ? 1.0 : -1.0
            for column in difference.indices { difference[column] += direction * left.strokeFeatures[index][column] / normalizer }
          }
          if difference.contains(where: { abs($0) > 1e-12 }) {
            masks.append(Row(x: difference, y: target, weight: 1,
              groups: [left.sourceGroupID], isComparison: true))
          }
        }
      } }
      // A refinement choice is intentional but weaker than an explicit rank.
      let strength = ranking.provenance == .ranking ? 1.0 : 0.2
      rankRows += rows.map { Row(x: $0.x, y: $0.y, weight: strength / Double(max(1, rows.count)), groups: $0.groups, isComparison: true) }
      maskRows += masks.map { Row(x: $0.x, y: $0.y, weight: 1 / Double(max(1, masks.count)), groups: $0.groups, isComparison: true) }
      guard rankRows.count <= 20_000, maskRows.count + explicitLabels <= 20_000 else {
        return unavailable("This local fit exceeds 20,000 comparisons or deletion observations. Curate a smaller training selection; no portfolio data was discarded.")
      }
    }
    var deletionRows: [Row] = []
    for example in examples where !example.strokeLabels.isEmpty {
      let total = example.strokeLabels.reduce(0.0) { $0 + ($1.provenance == .completedMask ? 0.5 : 1) }
      deletionRows += example.strokeLabels.map { label in
        Row(x: example.strokeFeatures[label.index], y: label.removed ? 1 : 0,
          weight: (label.provenance == .completedMask ? 0.5 : 1) / total, groups: [example.sourceGroupID])
      }
    }
    deletionRows += maskRows
    let ranker = fitHead(rows: rankRows, holdout: holdout, dimension: FlowArtistFeatures.drawingCount, pairwise: true)
    let deleter = fitHead(rows: deletionRows, holdout: holdout, dimension: FlowArtistFeatures.strokeCount,
      pairwise: false, deletionExamples: examples)
    if Task.isCancelled { return unavailable("Fit cancelled; the active checkpoint remains unchanged.") }
    let rankReport = ranker.head?.report ?? .unavailable(ranker.reason)
    let deleteReport = deleter.head?.report ?? .unavailable(deleter.reason)
    guard ranker.head != nil || deleter.head != nil else {
      return .init(checkpoint: nil, summary: "Ranker: \(ranker.reason) Deletion: \(deleter.reason)", ranker: rankReport, deleter: deleteReport)
    }
    // Bound transient JSON memory to one example. Ranked masks often share a
    // large stroke feature matrix; encoding the full expanded dataset at once
    // would duplicate that matrix into a second large allocation.
    struct Manifest: Encodable {
      let revision: String
      let exampleDigests: [String]
      let rankingDigests: [String]
      let configuration: FlowArtistFitConfiguration
    }
    let digest: String
    do {
      var exampleDigests: [String] = [], rankingDigests: [String] = []
      for example in examples { try Task.checkCancellation(); exampleDigests.append(try FlowArtistCoding.digest(example)) }
      for ranking in rankings { try Task.checkCancellation(); rankingDigests.append(try FlowArtistCoding.digest(ranking)) }
      digest = try FlowArtistCoding.digest(Manifest(revision: "ordered-example-ranking-digests-v1",
        exampleDigests: exampleDigests, rankingDigests: rankingDigests, configuration: .current))
    } catch is CancellationError { return unavailable("Fit cancelled; the active checkpoint remains unchanged.") }
    catch { return unavailable("Training manifest could not be encoded.") }
    let checkpoint = FlowArtistCheckpoint(schemaVersion: 1, featureRevision: FlowArtistFeatures.revision,
      recipeRevision: FlowArtistRecipe.revision, rendererRevision: PortraitFlowRenderer.markRevision,
      ranker: ranker.head, deleter: deleter.head, sourceGroupIDs: groups,
      holdoutGroupIDs: holdout.sorted(), exampleIDs: examples.map(\.id), rankingIDs: rankings.map(\.id),
      trainingDataSHA256: digest, seed: seed, fitConfiguration: .current)
    do { try checkpoint.validate() }
    catch { return unavailable("Fit produced an invalid checkpoint: \(error.localizedDescription) The active model is unchanged.") }
    let status = checkpoint.isExperimental ? "Experimental fit; held-out artistic improvement is not established." : "Both heads improve their fixed photo-group holdout losses. Human artistic evaluation remains separate."
    return .init(checkpoint: checkpoint, summary: status + " Ranker: \(rankReport.status) Deletion: \(deleteReport.status)",
      ranker: rankReport, deleter: deleteReport)
  }

  private static func valid(_ features: [Double], count: Int) -> Bool {
    features.count == count && features.allSatisfy { $0.isFinite && abs($0) <= 100 }
  }

  private static func fitHead(rows: [Row], holdout: Set<String>, dimension: Int, pairwise: Bool,
    deletionExamples: [FlowArtistExample] = []) -> (head: FlowArtistLinearHead?, reason: String) {
    var training = rows.filter { $0.groups.isDisjoint(with: holdout) }
    var testing = rows.filter { !$0.groups.isEmpty && $0.groups.isSubset(of: holdout) }
    // Comparisons crossing the split are intentionally excluded, not leaked.
    guard training.count >= 2 else { return (nil, pairwise ? "Needs at least two usable preference comparisons." : "Needs explicit pruning labels.") }
    if !pairwise {
      let corrected = training.filter { !$0.isComparison }
      let compared = training.filter(\.isComparison)
      guard (corrected.contains(where: { $0.y == 0 }) && corrected.contains(where: { $0.y == 1 })) || compared.count >= 2 else {
        return (nil, "Needs both remove and keep evidence; untouched unfinished lines are not positive labels.")
      }
    }
    equalizeGroups(&training); equalizeGroups(&testing)
    var weights = Array(repeating: 0.0, count: dimension)
    let configuration = FlowArtistFitConfiguration.current, lambda = configuration.l2
    // A Lipschitz upper bound gives a deterministic safe full-batch step.
    let averageNorm = training.reduce(0.0) { $0 + $1.weight * FlowArtistMath.dot($1.x, $1.x) }
    let rate = 1 / (0.25 * averageNorm + lambda + 1e-9)
    for iteration in 0..<configuration.maximumIterations {
      if Task.isCancelled { return (nil, "Fit cancelled; the active checkpoint remains unchanged.") }
      var gradient = weights.map { lambda * $0 }
      gradient[0] = 0
      for row in training {
        let error = (FlowArtistMath.sigmoid(FlowArtistMath.dot(weights, row.x)) - row.y) * row.weight
        for column in weights.indices { gradient[column] += error * row.x[column] }
      }
      for column in weights.indices { weights[column] -= rate * gradient[column] }
      if iteration > 40, gradient.map({ abs($0) }).max()! < configuration.gradientTolerance { break }
    }
    guard weights.allSatisfy(\.isFinite) else { return (nil, "Nonfinite fit refused.") }
    let direct = training.filter { !$0.isComparison }
    let directWeight = direct.reduce(0.0) { $0 + $1.weight }
    let prior = directWeight > 0 ? direct.reduce(0.0) { $0 + $1.weight * $1.y } / directWeight : 0.5
    func loss(_ rows: [Row], learned: Bool) -> Double {
      rows.reduce(0) { sum, row in sum + row.weight * FlowArtistMath.loss(
        probability: learned ? FlowArtistMath.sigmoid(FlowArtistMath.dot(weights, row.x)) : (row.isComparison ? 0.5 : prior), target: row.y) }
    }
    let holdoutLoss = testing.isEmpty ? nil : loss(testing, learned: true)
    let baseline = testing.isEmpty ? nil : loss(testing, learned: false)
    let accuracy = testing.isEmpty ? nil : testing.reduce(0.0) { sum, row in
      let prediction = FlowArtistMath.sigmoid(FlowArtistMath.dot(weights, row.x))
      let correct = row.y == 0.5 ? abs(prediction - 0.5) <= 0.1 : (prediction >= 0.5) == (row.y > 0.5)
      return sum + (correct ? row.weight : 0)
    }
    var status: String
    if let holdoutLoss, let baseline {
      status = String(format: "%d training / %d holdout observations; holdout loss %.4f, baseline %.4f.", training.count, testing.count, holdoutLoss, baseline)
    } else { status = "\(training.count) training observations; no independent-photo holdout measurements." }
    let heldoutDirect = testing.filter { !$0.isComparison }
    if !pairwise, !testing.isEmpty {
      if !heldoutDirect.contains(where: { $0.y == 0 }) {
        status += " Holdout has no explicit keep labels; false-deletion cost is untested."
      }
      if !heldoutDirect.contains(where: { $0.y == 1 }) {
        status += " Holdout has no explicit remove labels; missed-removal cost is untested."
      }
    }
    var report = FlowArtistHeadReport(status: status, trainingCount: training.count, holdoutCount: testing.count,
      trainingGroupCount: Set(training.flatMap(\.groups)).count, holdoutGroupCount: Set(testing.flatMap(\.groups)).count,
      trainingLoss: loss(training, learned: true), holdoutLoss: holdoutLoss, baselineLoss: baseline,
      accuracy: accuracy.map { boundedRate($0) })
    if !pairwise {
      report.trainingRemoveCount = direct.filter { $0.y == 1 }.count
      report.trainingKeepCount = direct.filter { $0.y == 0 }.count
      report.holdoutRemoveCount = heldoutDirect.filter { $0.y == 1 }.count
      report.holdoutKeepCount = heldoutDirect.filter { $0.y == 0 }.count
      deploymentMetrics(examples: deletionExamples.filter { holdout.contains($0.sourceGroupID) },
        weights: weights, report: &report)
    }
    return (.init(weights: weights, report: report), status)
  }

  /// Exact deployed threshold plus nonempty safeguard, evaluated only where the
  /// artist supplied a label. Equal photo weighting prevents dense masks winning.
  private static func deploymentMetrics(examples: [FlowArtistExample], weights: [Double], report: inout FlowArtistHeadReport) {
    var grouped: [String: [Double]] = [:], counts: [String: Double] = [:]
    for example in examples where !example.strokeLabels.isEmpty {
      let probabilities = example.strokeFeatures.map { FlowArtistMath.sigmoid(FlowArtistMath.dot(weights, $0)) }
      var removed = Set(probabilities.indices.filter { probabilities[$0] >= FlowArtistFitConfiguration.current.deletionThreshold })
      if !probabilities.isEmpty, removed.count == probabilities.count,
        let keep = probabilities.indices.min(by: { probabilities[$0] < probabilities[$1] }) { removed.remove(keep) }
      var metrics = [0.0, 0, 0, 0, 0]
      for label in example.strokeLabels {
        let predicted = removed.contains(label.index), weight = 1 / Double(example.strokeLabels.count)
        if predicted && label.removed { metrics[0] += weight }
        if predicted && !label.removed { metrics[1] += weight }
        if !predicted && label.removed { metrics[2] += weight }
        if predicted != label.removed { metrics[3] += weight }
        if label.removed { metrics[4] += weight }
      }
      grouped[example.sourceGroupID, default: [0, 0, 0, 0, 0]] = zip(grouped[example.sourceGroupID] ?? [0, 0, 0, 0, 0], metrics).map { $0 + $1 }
      counts[example.sourceGroupID, default: 0] += 1
    }
    guard !grouped.isEmpty else { return }
    var totals = [0.0, 0, 0, 0, 0]
    for group in grouped.keys.sorted() {
      let metrics = grouped[group]!
      for index in totals.indices { totals[index] += metrics[index] / (counts[group]! * Double(grouped.count)) }
    }
    report.deploymentPrecision = totals[0] + totals[1] > 0 ? boundedRate(totals[0] / (totals[0] + totals[1])) : nil
    report.deploymentRecall = totals[0] + totals[2] > 0 ? boundedRate(totals[0] / (totals[0] + totals[2])) : nil
    report.deploymentCorrectionRate = boundedRate(totals[3])
    report.keepAllCorrectionRate = boundedRate(totals[4])
  }

  /// These rates are convex combinations of binary outcomes. Floating-point
  /// accumulation can exceed one by a few ulps; normalize at computation while
  /// retaining nonfinite results for strict checkpoint validation to reject.
  private static func boundedRate(_ value: Double) -> Double {
    value.isFinite ? min(1, max(0, value)) : value
  }

  /// Reweight observation burden per source group. Single-source rows receive
  /// equal aggregate group weight; arbitrary cross-source comparison graphs do
  /// not guarantee exact balance. No row count manufactures independent subjects.
  private static func equalizeGroups(_ rows: inout [Row]) {
    guard !rows.isEmpty else { return }
    var totals: [String: Double] = [:]
    for row in rows { for group in row.groups { totals[group, default: 0] += row.weight / Double(row.groups.count) } }
    for index in rows.indices {
      let divisor = rows[index].groups.reduce(0.0) { $0 + (totals[$1] ?? 1) } / Double(rows[index].groups.count)
      rows[index].weight /= max(1e-12, divisor)
    }
    let total = rows.reduce(0) { $0 + $1.weight }
    for index in rows.indices { rows[index].weight /= total }
  }
}
