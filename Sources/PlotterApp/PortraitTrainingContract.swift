import Foundation

/// C4: training owns configuration preferences, never placement or motion authority.
struct PortraitTrainingScopeDefinition: Identifiable, Codable, Hashable, Sendable {
  enum Mode: String, Codable, CaseIterable, Sendable { case drawingStyle, semanticBigHead }
  let scope: PortraitStyleScope
  let mode: Mode
  let referenceRecipe: PortraitStyleRecipe
  let schemaRevision: String
  var id: UUID { scope.id }
  static let currentRevision = "portrait-training-scope-v1"
}

struct PortraitTrainingPresentation: Codable, Hashable, Sendable {
  let drawingHeightMM: Double
  let inkWidthMM: Double
  let inkWidthIsMeasured: Bool
  init(drawingHeightMM: Double = 100, inkWidthMM: Double = 0.4, inkWidthIsMeasured: Bool = false) {
    self.drawingHeightMM = drawingHeightMM; self.inkWidthMM = inkWidthMM
    self.inkWidthIsMeasured = inkWidthIsMeasured
  }
  init(_ context: PortraitPresentationContext) {
    self.init(drawingHeightMM: context.drawingHeightMM, inkWidthMM: context.inkWidthMM,
      inkWidthIsMeasured: context.inkWidthIsMeasured)
  }
}

struct PortraitFeatureSchema: Codable, Hashable, Sendable {
  struct Feature: Codable, Hashable, Sendable {
    let name: String
    let transform: String
    let offset: Double
    let scale: Double
  }
  let revision: String
  let features: [Feature]
}

struct PortraitPreferenceDataset: Identifiable, Codable, Sendable {
  enum Split: String, Codable, Sendable { case training, holdout }
  struct Row: Codable, Sendable {
    let candidateID: String
    let label: PortraitLabelRevision
    let sourceSHA256: String
    let captureSessionID: UUID
    let ancestryGroupID: UUID
    let groupID: String
    let split: Split
    let features: [Double]
    let producerRevision: String
    let analysisRevision: String
    let warpRevision: String?
  }
  struct Group: Codable, Hashable, Sendable {
    let id: String
    let candidateIDs: [String]
    let split: Split
  }
  struct Exclusion: Codable, Hashable, Sendable {
    let candidateID: String?
    let labelRevisionID: UUID?
    let reason: String
  }
  struct Payload: Codable, Sendable {
    let revision: String
    let scope: PortraitTrainingScopeDefinition
    let featureSchema: PortraitFeatureSchema
    let rows: [Row]
    let groups: [Group]
    let splitSeed: UInt64
    let exclusions: [Exclusion]
  }
  let id: String
  let payload: Payload
  init(payload: Payload) throws {
    self.payload = payload
    id = PortraitCandidateCoding.digest(try PortraitCandidateCoding.encoder().encode(payload))
  }
}

struct PortraitPreferenceModel: Codable, Hashable, Sendable {
  let weights: [Double]
  /// Four finite strictly increasing thresholds for the five ordinal labels.
  let thresholds: [Double]
}

struct PortraitOrdinalFitConfiguration: Codable, Hashable, Sendable {
  var revision = "ordinal-logistic-projected-gradient-v1"
  var seed: UInt64 = 7
  var maximumIterations = 600
  var learningRate = 0.08
  var regularization = 0.02
  var minimumLabels = 6
  var convergenceTolerance = 1e-8
  static let standard = Self()
}

struct PortraitPreferenceEvaluation: Codable, Hashable, Sendable {
  let trainingCount: Int
  let holdoutCount: Int
  let trainingGroupCount: Int
  let holdoutGroupCount: Int
  let trainingLoss: Double
  let holdoutLoss: Double?
  let priorHoldoutLoss: Double?
  let withinSourceOrderingAccuracy: Double?
  let comparablePairCount: Int
  let limitations: [String]
}

struct PortraitPreferenceCheckpoint: Identifiable, Codable, Sendable {
  enum Initialization: String, Codable, Sendable { case deterministicFullRefit }
  enum OptimizerState: String, Codable, Sendable { case reset }
  struct Payload: Codable, Sendable {
    let revision: String
    let dataset: PortraitPreferenceDataset
    let configuration: PortraitOrdinalFitConfiguration
    let parentCheckpointID: String?
    let initialization: Initialization
    let optimizerState: OptimizerState
    let model: PortraitPreferenceModel
    let completedIterations: Int
    let converged: Bool
    let evaluation: PortraitPreferenceEvaluation
    let producerRevisions: [String]
    let warpRevisions: [String]
  }
  let id: String
  let payload: Payload
  init(payload: Payload) throws {
    self.payload = payload
    id = PortraitCandidateCoding.digest(try PortraitCandidateCoding.encoder().encode(payload))
  }
  var scopeID: UUID { payload.dataset.payload.scope.id }
}

struct PortraitCheckpointLibrarySnapshot: Codable, Sendable {
  var scopes: [PortraitTrainingScopeDefinition] = []
  var checkpoints: [PortraitPreferenceCheckpoint] = []
  /// UUID strings keep index encoding independent of dictionary key coding conventions.
  var activeCheckpointIDs: [String: String] = [:]
}

struct PortraitCheckpointLibraryLoadResult: Sendable {
  let snapshot: PortraitCheckpointLibrarySnapshot
  let issues: [String]
  let canWrite: Bool
}

struct PortraitTrainingSelection: Codable, Hashable, Sendable {
  struct Proposal: Codable, Hashable, Sendable {
    let recipeSHA256: String
    let utility: Double
    let diversity: Double
  }
  let revision: String
  let scopeID: UUID
  let checkpointID: String?
  let seed: UInt64
  let proposals: [Proposal]
  let selectedIndex: Int
  let explored: Bool
  let explorationProbability: Double
}

enum PortraitTrainingError: Error, LocalizedError {
  case invalid(String), incompatible(String), insufficientData(String), nonFinite, storage(String)
  var errorDescription: String? {
    switch self {
    case .invalid(let detail): "Training data is invalid: " + detail
    case .incompatible(let detail): "Training inputs are incompatible: " + detail
    case .insufficientData(let detail): "More scoped ratings are needed: " + detail
    case .nonFinite: "The fit produced nonfinite values; the previous checkpoint remains active."
    case .storage(let detail): "Training storage is unavailable: " + detail
    }
  }
}
