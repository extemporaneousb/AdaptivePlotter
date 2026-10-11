import Foundation

/// C4: training owns configuration preferences, never placement or motion authority.
package struct PortraitTrainingScopeDefinition: Identifiable, Codable, Hashable, Sendable {
  package enum Mode: String, Codable, CaseIterable, Sendable { case drawingStyle, semanticBigHead }
  package let scope: PortraitStyleScope
  package let mode: Mode
  package let referenceRecipe: PortraitStyleRecipe
  package let schemaRevision: String
  package var id: UUID { scope.id }
  package static let currentRevision = "portrait-training-scope-v1"

  package init(
    scope: PortraitStyleScope,
    mode: Mode,
    referenceRecipe: PortraitStyleRecipe,
    schemaRevision: String
  ) {
    self.scope = scope
    self.mode = mode
    self.referenceRecipe = referenceRecipe
    self.schemaRevision = schemaRevision
  }
}

package struct PortraitTrainingPresentation: Codable, Hashable, Sendable {
  package let drawingHeightMM: Double
  package let inkWidthMM: Double
  package let inkWidthIsMeasured: Bool
  package init(drawingHeightMM: Double = 100, inkWidthMM: Double = 0.4, inkWidthIsMeasured: Bool = false) {
    self.drawingHeightMM = drawingHeightMM; self.inkWidthMM = inkWidthMM
    self.inkWidthIsMeasured = inkWidthIsMeasured
  }
  package init(_ context: PortraitPresentationContext) {
    self.init(drawingHeightMM: context.drawingHeightMM, inkWidthMM: context.inkWidthMM,
      inkWidthIsMeasured: context.inkWidthIsMeasured)
  }
}

package struct PortraitFeatureSchema: Codable, Hashable, Sendable {
  package struct Feature: Codable, Hashable, Sendable {
    package let name: String
    package let transform: String
    package let offset: Double
    package let scale: Double

    package init(name: String, transform: String, offset: Double, scale: Double) {
      self.name = name
      self.transform = transform
      self.offset = offset
      self.scale = scale
    }
  }
  package let revision: String
  package let features: [Feature]

  package init(revision: String, features: [Feature]) {
    self.revision = revision
    self.features = features
  }
}

package struct PortraitPreferenceDataset: Identifiable, Codable, Sendable {
  package enum Split: String, Codable, Sendable { case training, holdout }
  package struct Row: Codable, Sendable {
    package let candidateID: String
    package let label: PortraitLabelRevision
    package let sourceSHA256: String
    package let captureSessionID: UUID
    package let ancestryGroupID: UUID
    package let groupID: String
    package let split: Split
    package let features: [Double]
    package let producerRevision: String
    package let analysisRevision: String
    package let warpRevision: String?

    package init(
      candidateID: String,
      label: PortraitLabelRevision,
      sourceSHA256: String,
      captureSessionID: UUID,
      ancestryGroupID: UUID,
      groupID: String,
      split: Split,
      features: [Double],
      producerRevision: String,
      analysisRevision: String,
      warpRevision: String? = nil
    ) {
      self.candidateID = candidateID
      self.label = label
      self.sourceSHA256 = sourceSHA256
      self.captureSessionID = captureSessionID
      self.ancestryGroupID = ancestryGroupID
      self.groupID = groupID
      self.split = split
      self.features = features
      self.producerRevision = producerRevision
      self.analysisRevision = analysisRevision
      self.warpRevision = warpRevision
    }
  }
  package struct Group: Codable, Hashable, Sendable {
    package let id: String
    package let candidateIDs: [String]
    package let split: Split

    package init(id: String, candidateIDs: [String], split: Split) {
      self.id = id
      self.candidateIDs = candidateIDs
      self.split = split
    }
  }
  package struct Exclusion: Codable, Hashable, Sendable {
    package let candidateID: String?
    package let labelRevisionID: UUID?
    package let reason: String

    package init(candidateID: String? = nil, labelRevisionID: UUID? = nil, reason: String) {
      self.candidateID = candidateID
      self.labelRevisionID = labelRevisionID
      self.reason = reason
    }
  }
  package struct Payload: Codable, Sendable {
    package let revision: String
    package let scope: PortraitTrainingScopeDefinition
    package let featureSchema: PortraitFeatureSchema
    package let rows: [Row]
    package let groups: [Group]
    package let splitSeed: UInt64
    package let exclusions: [Exclusion]

    package init(
      revision: String,
      scope: PortraitTrainingScopeDefinition,
      featureSchema: PortraitFeatureSchema,
      rows: [Row],
      groups: [Group],
      splitSeed: UInt64,
      exclusions: [Exclusion]
    ) {
      self.revision = revision
      self.scope = scope
      self.featureSchema = featureSchema
      self.rows = rows
      self.groups = groups
      self.splitSeed = splitSeed
      self.exclusions = exclusions
    }
  }
  package let id: String
  package let payload: Payload
  package init(payload: Payload) throws {
    self.payload = payload
    id = PortraitCandidateCoding.digest(try PortraitCandidateCoding.encoder().encode(payload))
  }
}

package struct PortraitPreferenceModel: Codable, Hashable, Sendable {
  package let weights: [Double]
  /// Four finite strictly increasing thresholds for the five ordinal labels.
  package let thresholds: [Double]

  package init(weights: [Double], thresholds: [Double]) {
    self.weights = weights
    self.thresholds = thresholds
  }
}

package struct PortraitOrdinalFitConfiguration: Codable, Hashable, Sendable {
  package var revision = "ordinal-logistic-projected-gradient-v1"
  package var seed: UInt64 = 7
  package var maximumIterations = 600
  package var learningRate = 0.08
  package var regularization = 0.02
  package var minimumLabels = 6
  package var convergenceTolerance = 1e-8
  package static let standard = Self()
}

package struct PortraitPreferenceEvaluation: Codable, Hashable, Sendable {
  package let trainingCount: Int
  package let holdoutCount: Int
  package let trainingGroupCount: Int
  package let holdoutGroupCount: Int
  package let trainingLoss: Double
  package let holdoutLoss: Double?
  package let priorHoldoutLoss: Double?
  package let withinSourceOrderingAccuracy: Double?
  package let comparablePairCount: Int
  package let limitations: [String]

  package init(
    trainingCount: Int,
    holdoutCount: Int,
    trainingGroupCount: Int,
    holdoutGroupCount: Int,
    trainingLoss: Double,
    holdoutLoss: Double? = nil,
    priorHoldoutLoss: Double? = nil,
    withinSourceOrderingAccuracy: Double? = nil,
    comparablePairCount: Int,
    limitations: [String]
  ) {
    self.trainingCount = trainingCount
    self.holdoutCount = holdoutCount
    self.trainingGroupCount = trainingGroupCount
    self.holdoutGroupCount = holdoutGroupCount
    self.trainingLoss = trainingLoss
    self.holdoutLoss = holdoutLoss
    self.priorHoldoutLoss = priorHoldoutLoss
    self.withinSourceOrderingAccuracy = withinSourceOrderingAccuracy
    self.comparablePairCount = comparablePairCount
    self.limitations = limitations
  }
}

package struct PortraitPreferenceCheckpoint: Identifiable, Codable, Sendable {
  package enum Initialization: String, Codable, Sendable { case deterministicFullRefit }
  package enum OptimizerState: String, Codable, Sendable { case reset }
  package struct Payload: Codable, Sendable {
    package let revision: String
    package let dataset: PortraitPreferenceDataset
    package let configuration: PortraitOrdinalFitConfiguration
    package let parentCheckpointID: String?
    package let initialization: Initialization
    package let optimizerState: OptimizerState
    package let model: PortraitPreferenceModel
    package let completedIterations: Int
    package let converged: Bool
    package let evaluation: PortraitPreferenceEvaluation
    package let producerRevisions: [String]
    package let warpRevisions: [String]

    package init(
      revision: String,
      dataset: PortraitPreferenceDataset,
      configuration: PortraitOrdinalFitConfiguration,
      parentCheckpointID: String? = nil,
      initialization: Initialization,
      optimizerState: OptimizerState,
      model: PortraitPreferenceModel,
      completedIterations: Int,
      converged: Bool,
      evaluation: PortraitPreferenceEvaluation,
      producerRevisions: [String],
      warpRevisions: [String]
    ) {
      self.revision = revision
      self.dataset = dataset
      self.configuration = configuration
      self.parentCheckpointID = parentCheckpointID
      self.initialization = initialization
      self.optimizerState = optimizerState
      self.model = model
      self.completedIterations = completedIterations
      self.converged = converged
      self.evaluation = evaluation
      self.producerRevisions = producerRevisions
      self.warpRevisions = warpRevisions
    }
  }
  package let id: String
  package let payload: Payload
  package init(payload: Payload) throws {
    self.payload = payload
    id = PortraitCandidateCoding.digest(try PortraitCandidateCoding.encoder().encode(payload))
  }
  package var scopeID: UUID { payload.dataset.payload.scope.id }
}

package struct PortraitCheckpointLibrarySnapshot: Codable, Sendable {
  package var scopes: [PortraitTrainingScopeDefinition] = []
  package var checkpoints: [PortraitPreferenceCheckpoint] = []
  /// UUID strings keep index encoding independent of dictionary key coding conventions.
  package var activeCheckpointIDs: [String: String] = [:]

  package init(
    scopes: [PortraitTrainingScopeDefinition] = [],
    checkpoints: [PortraitPreferenceCheckpoint] = [],
    activeCheckpointIDs: [String: String] = [:]
  ) {
    self.scopes = scopes
    self.checkpoints = checkpoints
    self.activeCheckpointIDs = activeCheckpointIDs
  }
}

package struct PortraitCheckpointLibraryLoadResult: Sendable {
  package let snapshot: PortraitCheckpointLibrarySnapshot
  package let issues: [String]
  package let canWrite: Bool

  package init(snapshot: PortraitCheckpointLibrarySnapshot, issues: [String], canWrite: Bool) {
    self.snapshot = snapshot
    self.issues = issues
    self.canWrite = canWrite
  }
}

package struct PortraitTrainingSelection: Codable, Hashable, Sendable {
  package struct Proposal: Codable, Hashable, Sendable {
    package let recipeSHA256: String
    package let utility: Double
    package let diversity: Double

    package init(recipeSHA256: String, utility: Double, diversity: Double) {
      self.recipeSHA256 = recipeSHA256
      self.utility = utility
      self.diversity = diversity
    }
  }
  package let revision: String
  package let scopeID: UUID
  package let checkpointID: String?
  package let seed: UInt64
  package let proposals: [Proposal]
  package let selectedIndex: Int
  package let explored: Bool
  package let explorationProbability: Double

  package init(
    revision: String,
    scopeID: UUID,
    checkpointID: String? = nil,
    seed: UInt64,
    proposals: [Proposal],
    selectedIndex: Int,
    explored: Bool,
    explorationProbability: Double
  ) {
    self.revision = revision
    self.scopeID = scopeID
    self.checkpointID = checkpointID
    self.seed = seed
    self.proposals = proposals
    self.selectedIndex = selectedIndex
    self.explored = explored
    self.explorationProbability = explorationProbability
  }
}

package enum PortraitTrainingError: Error, LocalizedError {
  case invalid(String), incompatible(String), insufficientData(String), nonFinite, storage(String)
  package var errorDescription: String? {
    switch self {
    case .invalid(let detail): "Training data is invalid: " + detail
    case .incompatible(let detail): "Training inputs are incompatible: " + detail
    case .insufficientData(let detail): "More scoped ratings are needed: " + detail
    case .nonFinite: "The fit produced nonfinite values; the previous checkpoint remains active."
    case .storage(let detail): "Training storage is unavailable: " + detail
    }
  }
}
