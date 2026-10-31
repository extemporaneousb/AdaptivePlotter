import CryptoKit
import Foundation

package enum FlowArtistLabelProvenance: String, Codable, Sendable { case remove, restore, completedMask }
package enum FlowArtistRankingProvenance: String, Codable, Sendable { case ranking, choice }

package struct FlowArtistStrokeLabel: Codable, Equatable, Sendable {
  package let index: Int
  package let removed: Bool
  package let provenance: FlowArtistLabelProvenance
  package init(index: Int, removed: Bool, provenance: FlowArtistLabelProvenance) {
    self.index = index; self.removed = removed; self.provenance = provenance
  }
}

package struct FlowArtistExample: Codable, Equatable, Sendable {
  package let id: String
  package let sourceGroupID: String
  package let recipe: FlowArtistRecipe
  package let features: [Double]
  package let strokeFeatures: [[Double]]
  package let strokeLabels: [FlowArtistStrokeLabel]
  package let baseDrawingID: String?
  package let removedIndices: [Int]
  package init(id: String, sourceGroupID: String, recipe: FlowArtistRecipe, features: [Double],
    strokeFeatures: [[Double]], strokeLabels: [FlowArtistStrokeLabel] = [],
    baseDrawingID: String? = nil, removedIndices: [Int] = []) {
    self.id = id; self.sourceGroupID = sourceGroupID; self.recipe = recipe; self.features = features
    self.strokeFeatures = strokeFeatures; self.strokeLabels = strokeLabels
    self.baseDrawingID = baseDrawingID; self.removedIndices = removedIndices.sorted()
  }
}

package struct FlowArtistRanking: Codable, Equatable, Sendable {
  package let id: String
  /// Each tier is a tie; earlier tiers are preferred. Omitted items are unranked.
  package let tiers: [[String]]
  package let provenance: FlowArtistRankingProvenance
  package init(id: String, tiers: [[String]], provenance: FlowArtistRankingProvenance = .ranking) {
    self.id = id; self.tiers = tiers; self.provenance = provenance
  }
}

package struct FlowArtistHeadReport: Codable, Equatable, Sendable {
  package let status: String
  package let trainingCount: Int
  package let holdoutCount: Int
  package let trainingGroupCount: Int
  package let holdoutGroupCount: Int
  package let trainingLoss: Double?
  package let holdoutLoss: Double?
  package let baselineLoss: Double?
  package let accuracy: Double?
  package var deploymentPrecision: Double? = nil
  package var deploymentRecall: Double? = nil
  package var deploymentCorrectionRate: Double? = nil
  package var keepAllCorrectionRate: Double? = nil
  /// Direct artist labels only. Pairwise mask preferences are not independent
  /// remove/keep decisions. Optional fields retain old checkpoint byte identity.
  package var trainingRemoveCount: Int? = nil
  package var trainingKeepCount: Int? = nil
  package var holdoutRemoveCount: Int? = nil
  package var holdoutKeepCount: Int? = nil
  package var isFitted: Bool { trainingLoss != nil }
  package var improvesHoldout: Bool { holdoutLoss.map { $0 < (baselineLoss ?? $0) } ?? false }
  package static func unavailable(_ reason: String) -> Self {
    Self(status: reason, trainingCount: 0, holdoutCount: 0, trainingGroupCount: 0,
      holdoutGroupCount: 0, trainingLoss: nil, holdoutLoss: nil, baselineLoss: nil, accuracy: nil)
  }
}

package struct FlowArtistFitConfiguration: Codable, Equatable, Sendable {
  package let revision: String
  package let l2: Double
  package let maximumIterations: Int
  package let gradientTolerance: Double
  package let deletionThreshold: Double
  package let nonemptyPolicy: String
  package static let current = Self(revision: "flow-artist-regularized-bt-logistic-v1", l2: 0.015,
    maximumIterations: 700, gradientTolerance: 1e-7, deletionThreshold: 0.65,
    nonemptyPolicy: "retain-lowest-deletion-probability-tie-first-v1")
}

package struct FlowArtistLinearHead: Codable, Equatable, Sendable {
  package let weights: [Double]
  package let report: FlowArtistHeadReport
}

package struct FlowArtistFitReport: Codable, Equatable, Sendable {
  package let checkpoint: FlowArtistCheckpoint?
  package let summary: String
  package let ranker: FlowArtistHeadReport
  package let deleter: FlowArtistHeadReport
  package static func unavailable(_ reason: String) -> Self {
    .init(checkpoint: nil, summary: reason, ranker: .unavailable(reason), deleter: .unavailable(reason))
  }
}

package enum FlowArtistModelError: Error, LocalizedError {
  case invalid(String)
  package var errorDescription: String? { if case let .invalid(message) = self { return message }; return nil }
}

/// Immutable deployment artifact. Replacing the active checkpoint is owned by
/// the portfolio transaction; inference never mutates a fitted checkpoint.
package struct FlowArtistCheckpoint: Codable, Equatable, Sendable {
  package let schemaVersion: Int
  package let featureRevision: String
  package let recipeRevision: String
  package let rendererRevision: String
  package let ranker: FlowArtistLinearHead?
  package let deleter: FlowArtistLinearHead?
  package let sourceGroupIDs: [String]
  package let holdoutGroupIDs: [String]
  package let exampleIDs: [String]
  package let rankingIDs: [String]
  package let trainingDataSHA256: String
  package let seed: UInt64
  package let fitConfiguration: FlowArtistFitConfiguration

  package var id: String { (try? FlowArtistCoding.digest(self)) ?? "invalid-checkpoint" }
  package var isExperimental: Bool {
    guard let ranker, let deleter, ranker.report.improvesHoldout, deleter.report.improvesHoldout,
      (deleter.report.holdoutRemoveCount ?? 0) > 0,
      (deleter.report.holdoutKeepCount ?? 0) > 0,
      let correction = deleter.report.deploymentCorrectionRate,
      let baseline = deleter.report.keepAllCorrectionRate else { return true }
    // Pairwise mask ordering does not establish calibrated per-stroke deletion
    // probabilities. The actual threshold needs independent direct-label evidence.
    return correction >= baseline
  }

  /// Archives remain readable independently of which feature space is currently
  /// fitted. Never reinterpret old coefficients as the new mark coordinates.
  package func validateArchive() throws {
    let legacy = featureRevision == FlowArtistFeatures.legacyRevision
      && recipeRevision == FlowArtistRecipe.legacyRevision
      && rendererRevision == PortraitFlowRenderer.legacyRevision
    let current = featureRevision == FlowArtistFeatures.revision
      && recipeRevision == FlowArtistRecipe.revision
      && rendererRevision == PortraitFlowRenderer.markRevision
    guard schemaVersion == 1, legacy || current,
      fitConfiguration == .current,
      ranker != nil || deleter != nil, !sourceGroupIDs.isEmpty,
      Set(sourceGroupIDs).count == sourceGroupIDs.count,
      Set(holdoutGroupIDs).count == holdoutGroupIDs.count,
      Set(holdoutGroupIDs).isSubset(of: Set(sourceGroupIDs)),
      Set(exampleIDs).count == exampleIDs.count, Set(rankingIDs).count == rankingIDs.count,
      trainingDataSHA256.count == 64, trainingDataSHA256.allSatisfy({ $0.isHexDigit }) else {
      throw FlowArtistModelError.invalid("Checkpoint schema, renderer, feature space or training manifest is incompatible.")
    }
    for (head, dimension) in [(ranker, legacy ? 123 : FlowArtistFeatures.drawingCount),
      (deleter, legacy ? 84 : FlowArtistFeatures.strokeCount)] {
      if let head {
        let report = head.report
        let directCounts = [report.trainingRemoveCount, report.trainingKeepCount,
          report.holdoutRemoveCount, report.holdoutKeepCount]
        if directCounts.contains(where: { $0 != nil }) {
          guard let trainRemove = report.trainingRemoveCount, let trainKeep = report.trainingKeepCount,
            let testRemove = report.holdoutRemoveCount, let testKeep = report.holdoutKeepCount,
            directCounts.compactMap({ $0 }).allSatisfy({ (0...20_000).contains($0) }),
            trainRemove + trainKeep <= report.trainingCount,
            testRemove + testKeep <= report.holdoutCount else {
            throw FlowArtistModelError.invalid("Checkpoint direct-label coverage is inconsistent with its observations.")
          }
        }
        let boundedMeasurements: [(String, Double?)] = [("accuracy", report.accuracy),
          ("deploymentPrecision", report.deploymentPrecision), ("deploymentRecall", report.deploymentRecall),
          ("deploymentCorrectionRate", report.deploymentCorrectionRate), ("keepAllCorrectionRate", report.keepAllCorrectionRate)]
        for (name, value) in boundedMeasurements {
          if let value, !value.isFinite || !(0...1).contains(value) {
            throw FlowArtistModelError.invalid("Checkpoint measurement \(name)=\(value) is outside [0, 1].")
          }
        }
        guard head.weights.count == dimension, head.weights.allSatisfy({ $0.isFinite && abs($0) < 1e6 }),
          report.trainingCount > 0, report.trainingGroupCount > 0, report.holdoutCount >= 0,
          report.holdoutGroupCount >= 0, let loss = report.trainingLoss, loss.isFinite, loss >= 0,
          [report.holdoutLoss, report.baselineLoss, report.accuracy, report.deploymentPrecision,
            report.deploymentRecall, report.deploymentCorrectionRate, report.keepAllCorrectionRate]
            .compactMap({ $0 }).allSatisfy(\.isFinite),
          report.holdoutLoss.map({ $0 >= 0 }) ?? true,
          report.baselineLoss.map({ $0 >= 0 }) ?? true,
          [report.accuracy, report.deploymentPrecision, report.deploymentRecall,
            report.deploymentCorrectionRate, report.keepAllCorrectionRate]
            .compactMap({ $0 }).allSatisfy({ (0...1).contains($0) }) else {
          throw FlowArtistModelError.invalid("Checkpoint contains invalid fitted coefficients or measurements.")
        }
      }
    }
  }

  package func validateForInference() throws {
    try validateArchive()
    guard featureRevision == FlowArtistFeatures.revision, recipeRevision == FlowArtistRecipe.revision,
      rendererRevision == PortraitFlowRenderer.markRevision else {
      throw FlowArtistModelError.invalid("This retained checkpoint uses the earlier Flow feature space. Its report and drawings remain available; fit this portfolio again to activate the current mark grammar.")
    }
  }

  package func validate() throws { try validateForInference() }

  package func score(features: [Double]) throws -> Double {
    try validate()
    try Self.validateFeatures(features, dimension: FlowArtistFeatures.drawingCount)
    return ranker.map { FlowArtistMath.dot($0.weights, features) } ?? 0
  }

  package func deletionProbabilities(strokeFeatures: [[Double]]) throws -> [Double] {
    try validate()
    guard strokeFeatures.count <= 10_000 else { throw FlowArtistModelError.invalid("Too many stroke features.") }
    return try strokeFeatures.map { features in
      try Self.validateFeatures(features, dimension: FlowArtistFeatures.strokeCount)
      return deleter.map { FlowArtistMath.sigmoid(FlowArtistMath.dot($0.weights, features)) } ?? 0
    }
  }

  /// Conservative proposal policy. Never silently synthesize geometry or emit an
  /// empty drawing. Full probabilities remain available for retained inference.
  package func removedIndices(strokeFeatures: [[Double]], threshold: Double = 0.65) throws -> Set<Int> {
    guard threshold.isFinite, (0.5...1).contains(threshold) else {
      throw FlowArtistModelError.invalid("Deletion probability threshold must be between 0.5 and 1.")
    }
    let probabilities = try deletionProbabilities(strokeFeatures: strokeFeatures)
    var result = Set(probabilities.indices.filter { probabilities[$0] >= threshold })
    if !probabilities.isEmpty, result.count == probabilities.count,
      let keep = probabilities.indices.min(by: { probabilities[$0] < probabilities[$1] }) { result.remove(keep) }
    return result
  }

  private static func validateFeatures(_ features: [Double], dimension: Int) throws {
    guard features.count == dimension, features.allSatisfy({ $0.isFinite && abs($0) <= 100 }) else {
      throw FlowArtistModelError.invalid("Feature vector differs from the fitted schema.")
    }
  }
}

package enum FlowArtistCoding {
  package static func digest<T: Encodable>(_ value: T) throws -> String {
    let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
    return SHA256.hash(data: try encoder.encode(value)).map { String(format: "%02x", $0) }.joined()
  }
}

package enum FlowArtistMath {
  package static func dot(_ a: [Double], _ b: [Double]) -> Double { zip(a, b).reduce(0) { $0 + $1.0 * $1.1 } }
  package static func sigmoid(_ value: Double) -> Double { 1 / (1 + exp(-max(-35, min(35, value)))) }
  package static func loss(probability: Double, target: Double) -> Double {
    let p = min(1 - 1e-12, max(1e-12, probability))
    return -(target * log(p) + (1 - target) * log(1 - p))
  }
}
