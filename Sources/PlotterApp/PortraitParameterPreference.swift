import Foundation
import PlotterModel

/// Learns preferences within the existing stroke vocabulary. No geometry, family,
/// material, framing or regional authority is learned or replaced here.
enum PortraitParameterPreference {
  static let revision = "portrait-shared-parameter-preference-v1"
  static let maximumLabels = 256

  struct Observation: Sendable {
    let candidateID: String
    let proposalIdentity: String
    let feedbackID: UUID
    let sourceSHA256: String
    let sessionID: UUID
    let ancestryID: UUID
    let parameters: PortraitDrawingParameters
    let promising: Bool
  }

  struct Model: Codable, Sendable {
    let revision: String
    let contextID: String
    let weights: [Double]
    let parameterRanges: [[Double]]
    let candidateIDs: [String]
    let feedbackIDs: [UUID]
    let holdoutGroupIDs: [String]
    let trainingCount: Int
    let holdoutCount: Int
    let holdoutLoss: Double
    let baselineLoss: Double
    let orderingAccuracy: Double
    var id: String {
      (try? PortraitCandidateCoding.encoder().encode(self)).map(PortraitCandidateCoding.digest) ?? ""
    }

    func score(_ parameters: PortraitDrawingParameters) -> Double {
      zip(weights, features(parameters)).reduce(0) { $0 + $1.0 * $1.1 }
    }

    func supports(_ parameters: PortraitDrawingParameters) -> Bool {
      guard parameterRanges.count == 4,
        parameterRanges.allSatisfy({ $0.count == 2 && $0.allSatisfy(\.isFinite) && $0[0] <= $0[1] }) else { return false }
      return zip(raw(parameters), parameterRanges).allSatisfy {
        $0.0 >= $0.1[0] - 1e-10 && $0.0 <= $0.1[1] + 1e-10
      }
    }

    /// Rank cheap parameter proposals before rendering; keep one in four requests
    /// on the original sampler so learning never removes continued exploration.
    func recipe(around center: PortraitCandidate, seed: UInt64) -> PortraitStyleRecipe? {
      guard revision == PortraitParameterPreference.revision,
        contextID == PortraitParameterPreference.contextID(center), weights.count == 9,
        weights.allSatisfy(\.isFinite), let current = center.recipe.vectorOptions.drawingParameters,
        supports(current), !seed.isMultiple(of: 4) else { return nil }
      let recipes = (0..<12).map { index -> PortraitStyleRecipe in
        let proposal = PortraitExplorationPolicy.recipe(around: center,
          seed: seed &+ UInt64(index) &* 0x9e3779b97f4a7c15)
        var options = center.recipe.vectorOptions
        let values = zip(raw(proposal.vectorOptions.drawingParameters!), parameterRanges)
          .map { min($0.1[1], max($0.1[0], $0.0)) }
        options.drawingParameters = .init(detail: values[0], tone: values[1],
          smoothness: values[2], minimumLine: values[3])
        return .init(id: proposal.id, title: proposal.title, seed: proposal.seed,
          style: center.recipe.style, vectorOptions: options, analysisOptions: center.recipe.analysisOptions)
      }
      return recipes.filter { $0.vectorOptions.drawingParameters != current }.max { score($0.vectorOptions.drawingParameters!) < score($1.vectorOptions.drawingParameters!) }
    }
  }

  struct Report: Sendable {
    let model: Model?
    let labelCount: Int
    let groupCount: Int
    let summary: String
  }

  /// Frozen renderer/context inputs exclude the inactive legacy fields replaced
  /// by shared parameters. Feedback from a different pen/size/pose/region stays out.
  static func contextID(_ candidate: PortraitCandidate) -> String? {
    guard candidate.recipe.vectorOptions.drawingParameters != nil,
      let pen = candidate.program.strokes.first?.style else { return nil }
    struct Context: Encodable {
      let revision: String
      let producer: String
      let flowRenderer: String?
      let style: PortraitStyle
      let analysis: PortraitAnalysisOptions
      let pose: PortraitPose?
      let options: PortraitVectorOptions
      let pen: StrokeStyle
      let height: Double
    }
    let flowRenderer = candidate.program.source.sourceIdentifier.split(separator: "|")
      .first(where: { $0.hasPrefix("flow=") }).map { String($0.dropFirst(5)) }
    if candidate.recipe.style == .flowEdges, flowRenderer != PortraitFlowRenderer.revision { return nil }
    var options = candidate.recipe.vectorOptions.bounded
    let defaults = PortraitVectorOptions()
    options.drawingParameters = nil
    options.contourLevels = defaults.contourLevels; options.hatchSpacing = defaults.hatchSpacing
    options.sketchThreshold = defaults.sketchThreshold; options.tonalStrength = defaults.tonalStrength
    options.smoothing = defaults.smoothing; options.minimumContourLength = defaults.minimumContourLength
    options.simplificationTolerance = defaults.simplificationTolerance
    return (try? PortraitCandidateCoding.encoder().encode(Context(revision: revision,
      producer: candidate.producerRevision, flowRenderer: flowRenderer, style: candidate.recipe.style,
      analysis: candidate.recipe.analysisOptions, pose: candidate.renderPose, options: options,
      pen: pen, height: candidate.program.fieldExtent.height))).map(PortraitCandidateCoding.digest)
  }

  static func report(around center: PortraitCandidate, archive: PortraitCandidateArchive) -> Report {
    guard let context = contextID(center) else {
      return .init(model: nil, labelCount: 0, groupCount: 0,
        summary: "Feedback learning uses shared parameters; this recipe retains its original controls.")
    }
    // Latest explicit vote per exact proposal wins. Saving, browsing and the
    // absence of a vote contribute no label. Apply the cap before numerical work.
    let voted = archive.entries.compactMap { entry -> (PortraitRetainedCandidate, PortraitAttemptFeedbackRevision)? in
      guard let vote = entry.attempt?.feedbackRevisions.last else { return nil }
      return (entry, vote)
    }.sorted { $0.1.createdAt > $1.1.createdAt }
    var identities = Set<String>(), rows: [Observation] = []
    for (entry, vote) in voted {
      guard let attempt = entry.attempt,
        contextID(entry.candidate) == context,
        identities.insert(attempt.proposalIdentity).inserted else { continue }
      guard vote.value != .unknown, let parameters = entry.candidate.recipe.vectorOptions.drawingParameters else { continue }
      rows.append(.init(candidateID: entry.id, proposalIdentity: attempt.proposalIdentity,
        feedbackID: vote.id, sourceSHA256: entry.candidate.sourceSHA256,
        sessionID: entry.candidate.captureSessionID, ancestryID: entry.candidate.lineage.ancestryGroupID,
        parameters: parameters, promising: vote.value == .promising))
      if rows.count == maximumLabels { break }
    }
    return fit(rows, contextID: context)
  }

  private static func raw(_ parameters: PortraitDrawingParameters) -> [Double] {
    let p = parameters.bounded
    return [p.detail, p.tone, p.smoothness, p.minimumLine]
  }

  static func features(_ parameters: PortraitDrawingParameters) -> [Double] {
    let p = parameters.bounded
    let values = [p.detail * 2 - 1, (p.tone - 0.4) / 0.8 - 1,
      p.smoothness * 2 - 1, p.minimumLine / 0.0375 - 1]
    return [1] + values + values.map { $0 * $0 }
  }

  /// Equal weight per connected source/session/ancestry group. The split is made
  /// before fitting and held fixed; no repeated search against the holdout.
  static func fit(_ observations: [Observation], contextID: String) -> Report {
    let rows = Array(observations.prefix(maximumLabels)).sorted { $0.candidateID < $1.candidateID }
    let memberships = groups(rows)
    let groupIDs = Set(memberships).sorted()
    func unavailable(_ reason: String) -> Report {
      .init(model: nil, labelCount: rows.count, groupCount: groupIDs.count, summary: reason)
    }
    guard rows.count >= 16, groupIDs.count >= 4 else {
      return unavailable("Next explores. Learning needs 16 explicit votes across at least four independent photo groups (\(rows.count) votes, \(groupIDs.count) groups here).")
    }
    let holdoutIDs = Set(groupIDs.suffix(max(1, groupIDs.count / 4)))
    let train = rows.indices.filter { !holdoutIDs.contains(memberships[$0]) }
    let holdout = rows.indices.filter { holdoutIDs.contains(memberships[$0]) }
    let positive = train.filter { rows[$0].promising }.count
    guard train.count >= 12, positive >= 4, train.count - positive >= 4,
      holdout.count >= 4, Set(holdout.map { rows[$0].promising }).count == 2 else {
      return unavailable("Next explores. Learning needs both promising and rejected examples in independent training and holdout groups.")
    }
    let counts = Dictionary(grouping: train, by: { memberships[$0] }).mapValues(\.count)
    let x = rows.map { features($0.parameters) }
    var weights = [Double](repeating: 0, count: 9)
    for _ in 0..<240 {
      var gradient = weights.map { 0.05 * $0 }
      gradient[0] = 0
      for index in train {
        let prediction = sigmoid(dot(weights, x[index]))
        let error = prediction - (rows[index].promising ? 1 : 0)
        let weight = 1 / Double(counts[memberships[index]]! * counts.count)
        for column in weights.indices { gradient[column] += error * x[index][column] * weight }
      }
      for column in weights.indices { weights[column] -= 0.15 * gradient[column] }
    }
    let prior = train.reduce(0.0) { $0 + (rows[$1].promising ? 1 : 0) / Double(counts[memberships[$1]]! * counts.count) }
    func loss(_ probability: (Int) -> Double) -> Double {
      let holdoutCounts = Dictionary(grouping: holdout, by: { memberships[$0] }).mapValues(\.count)
      return holdout.reduce(0) { total, index in
        let p = min(1 - 1e-9, max(1e-9, probability(index)))
        return total - log(rows[index].promising ? p : 1 - p)
          / Double(holdoutCounts[memberships[index]]! * holdoutCounts.count)
      }
    }
    let learnedLoss = loss { sigmoid(dot(weights, x[$0])) }, baselineLoss = loss { _ in prior }
    var pairs = 0, correct = 0
    for good in holdout where rows[good].promising {
      for bad in holdout where !rows[bad].promising && rows[good].sourceSHA256 == rows[bad].sourceSHA256 {
        pairs += 1
        if dot(weights, x[good]) > dot(weights, x[bad]) { correct += 1 }
      }
    }
    let accuracy = pairs == 0 ? 0 : Double(correct) / Double(pairs)
    guard weights.allSatisfy(\.isFinite), learnedLoss.isFinite,
      learnedLoss + 0.02 < baselineLoss, pairs >= 2, accuracy >= 0.6 else {
      return unavailable("Next explores. The fitted parameters did not improve independent-photo holdout preferences.")
    }
    let trainingParameters = train.map { raw(rows[$0].parameters) }
    let ranges = (0..<4).map { column in
      [trainingParameters.map { $0[column] }.min()!, trainingParameters.map { $0[column] }.max()!]
    }
    let model = Model(revision: revision, contextID: contextID, weights: weights, parameterRanges: ranges,
      candidateIDs: rows.map(\.candidateID), feedbackIDs: rows.map(\.feedbackID),
      holdoutGroupIDs: holdoutIDs.sorted(), trainingCount: train.count, holdoutCount: holdout.count,
      holdoutLoss: learnedLoss, baselineLoss: baselineLoss, orderingAccuracy: accuracy)
    return .init(model: model, labelCount: rows.count, groupCount: groupIDs.count,
      summary: "Feedback tunes shared parameters for Next (\(rows.count) votes, \(groupIDs.count) independent groups). One in four requests still explores.")
  }

  private static func dot(_ a: [Double], _ b: [Double]) -> Double {
    zip(a, b).reduce(0) { $0 + $1.0 * $1.1 }
  }
  private static func sigmoid(_ x: Double) -> Double { 1 / (1 + exp(-max(-30, min(30, x)))) }

  static func groups(_ rows: [Observation]) -> [String] {
    var parents = Array(rows.indices), first: [String: Int] = [:]
    func root(_ index: Int) -> Int {
      var value = index
      while parents[value] != value { value = parents[value] }
      return value
    }
    for (index, row) in rows.enumerated() {
      for key in ["source:" + row.sourceSHA256, "session:" + row.sessionID.uuidString,
        "ancestry:" + row.ancestryID.uuidString] {
        if let previous = first[key] { parents[root(index)] = root(previous) }
        else { first[key] = index }
      }
    }
    let members = Dictionary(grouping: rows.indices, by: root)
    let names = members.mapValues { $0.map { rows[$0].candidateID }.min()! }
    return rows.indices.map { names[root($0)]! }
  }
}
