import Foundation
import PlotterModel
import PortraitArtists
import PortraitCore
import DrawingLibrary

package enum FlowPortfolioError: Error, LocalizedError, Sendable {
  case invalid(String), unavailable(String), conflict(String)
  package var errorDescription: String? {
    switch self { case .invalid(let value), .unavailable(let value), .conflict(let value): value }
  }
}

package enum FlowPortfolioPurpose: String, Codable, Sendable { case artist, validationFixture }

package struct FlowPortfolioBlob: Codable, Equatable, Sendable {
  package let sha256: String
  package let byteCount: Int
  package let mediaType: String
}

package struct FlowPortfolioSource: Codable, Identifiable, Equatable, Sendable {
  package let id: UUID
  package let createdAt: Date
  package var title: String
  package let image: FlowPortfolioBlob
  package var subjectID: String?
  package var sessionID: String?
  package var excluded = false
  package var importProvenance: FlowPortfolioSourceImport? = nil
  package var captureProvenance: FlowPortfolioCaptureProvenance? = nil
  package var photo: PhotoRef? = nil
  /// The selected derivation never changes the original Photo or holdout group.
  package var authoringOptions: PortraitAnalysisOptions? = nil
  /// Exact source identity is the minimum grouping boundary. Declared identities
  /// are joined transitively by the training consumer, never inferred from pixels.
  package var groupKeys: [String] {
    ["source:" + image.sha256] + (subjectID.map { ["subject:" + $0] } ?? [])
      + (sessionID.map { ["session:" + $0] } ?? [])
  }
}

package enum FlowPortfolioRoundStatus: String, Codable, Sendable { case generating, completed, cancelled, interrupted }
package struct FlowPortfolioRound: Codable, Identifiable, Equatable, Sendable {
  package let id: UUID
  package let createdAt: Date
  package let sourceID: UUID
  package let parentCandidateID: UUID?
  package let recipes: [FlowArtistRecipe]
  package let analysisOptions: PortraitAnalysisOptions
  package let seed: UInt64
  package let modelID: String?
  package var status: FlowPortfolioRoundStatus
  package var candidateIDs: [UUID]
  package var displayedCandidateIDs: [UUID]
  package var recommendedCandidateID: UUID?
  /// Exact stable-index membership used by the checkpoint when this winner was
  /// scored. Nil in older rounds means the historical score basis is unknown.
  package var recommendedRemovedIndices: [Int]? = nil
  package var failures: [FlowPortfolioGenerationFailure]
  /// Optional for old portfolios; absent values retain historical sampling semantics.
  package var explorationDepth: Int? = nil
  package var refinementRadius: Double? = nil
  package var explorationPolicy: String? = nil
}
package struct FlowPortfolioGenerationFailure: Codable, Equatable, Sendable {
  package let slot: Int
  package let message: String
  package let recordedAt: Date
}
package struct FlowPortfolioCandidate: Codable, Identifiable, Equatable, Sendable {
  package let id: UUID
  package let createdAt: Date
  package let sourceID: UUID
  package let roundID: UUID
  package let slot: Int
  package let parentCandidateID: UUID?
  package let recipe: FlowArtistRecipe
  package let modelID: String?
  package let raster: FlowPortfolioBlob
  package let preview: FlowPortfolioBlob
  package let programHash: String
  package let strokeCount: Int
  package var excluded = false
  package var title: String? = nil
  package var drawing: DrawingRef? = nil
  /// Hash of the private immutable authoring closure manifest; absent in legacy rows.
  package var authoringClosure: FlowPortfolioBlob? = nil
}
package struct FlowPortfolioChoice: Codable, Identifiable, Equatable, Sendable {
  package let id: UUID
  package let createdAt: Date
  package let roundID: UUID
  package let candidateID: UUID
  package let offeredCandidateIDs: [UUID]
  package let selectedItemID: UUID
  package let offeredItems: [FlowPortfolioPresentationItem]
  /// A navigation/refinement choice is retained separately from explicit rank.
  package let purpose: String
  package var feedback: FlowPortfolioFeedbackReference? = nil
}

package enum FlowPruneAction: String, Codable, Sendable { case remove, restore, undo, redo, modelProposal, inheritedSelection, completeTarget }
package struct FlowPortfolioPruneRevision: Codable, Identifiable, Equatable, Sendable {
  package let id: UUID
  package let createdAt: Date
  package let candidateID: UUID
  package let parentRevisionID: UUID?
  package let action: FlowPruneAction
  package let affectedIndices: [Int]
  package var removedIndices: [Int]
  package let modelID: String?
  /// Undo and redo point at the exact prior human operation they negate/reapply.
  package let operationID: UUID?
  package let inheritedFromRevisionID: UUID?
  package let historicalRecord: FlowPortfolioBlob?
  package let probabilities: [Double]?
  package let threshold: Double?
  package let policy: String?
  package var undoOperationIDs: [UUID]
  package var redoOperationIDs: [UUID]
  package var drawing: DrawingRef? = nil
  package var feedback: FlowPortfolioFeedbackReference? = nil
}

package enum FlowRankingScope: Codable, Equatable, Sendable { case round(UUID), source(UUID), candidate(UUID), portfolio }
package struct FlowPortfolioPresentationItem: Codable, Identifiable, Equatable, Sendable {
  /// Stable identity of the candidate or exact pruning revision.
  package let id: UUID
  package let candidateID: UUID
  package let revisionID: UUID?
  package let sourceID: UUID
  package let removedIndices: [Int]
  package init(id: UUID, candidateID: UUID, revisionID: UUID?, sourceID: UUID, removedIndices: [Int]) {
    self.id = id; self.candidateID = candidateID; self.revisionID = revisionID
    self.sourceID = sourceID; self.removedIndices = removedIndices
  }
}
package struct FlowPortfolioPresentation: Codable, Identifiable, Equatable, Sendable {
  package let id: UUID
  package let createdAt: Date
  package let scope: FlowRankingScope
  package let seed: UInt64
  package let items: [FlowPortfolioPresentationItem]
}
package struct FlowPortfolioRanking: Codable, Identifiable, Equatable, Sendable {
  package let id: UUID
  package let createdAt: Date
  package let presentationID: UUID
  /// Each inner group is tied. Omitted items remain unranked, never losers.
  package let orderedGroups: [[UUID]]
  package let skipped: Bool
  package let neither: Bool
  package let supersedesID: UUID?
  package var feedback: FlowPortfolioFeedbackReference? = nil
}

package struct FlowPortfolioTrainingSnapshot: Codable, Identifiable, Equatable, Sendable {
  package let id: UUID
  package let createdAt: Date
  package let portfolioID: UUID
  package let portfolioRevision: Int
  package let purpose: FlowPortfolioPurpose
  package let document: FlowPortfolioBlob
  package let contentSHA256: String
  package var manifest: ExchangeAsset? = nil
  package var publication: DrawingLibraryFeedbackRef? = nil
}
package struct FlowPortfolioFit: Codable, Identifiable, Equatable, Sendable {
  package let id: UUID
  package let createdAt: Date
  package let snapshotID: UUID
  package let checkpoint: FlowPortfolioBlob?
  package var hasCheckpoint: Bool { checkpoint != nil }
  package let report: FlowPortfolioBlob
}
package struct FlowPortfolioActivation: Codable, Identifiable, Equatable, Sendable {
  package let id: UUID
  package let createdAt: Date
  package let previousFitID: UUID?
  package let fitID: UUID?
}

package struct FlowPortfolioSnapshot: Codable, Equatable, Sendable {
  package let schemaVersion: Int
  package let purpose: FlowPortfolioPurpose
  package let id: UUID
  package let createdAt: Date
  package var revision: Int
  package var frozenManifest: ExchangeAsset? = nil
  package var frozenTrainingPublication: DrawingLibraryFeedbackRef? = nil
  package var sources: [FlowPortfolioSource]
  package var rounds: [FlowPortfolioRound]
  package var candidates: [FlowPortfolioCandidate]
  package var choices: [FlowPortfolioChoice]
  package var pruneRevisions: [FlowPortfolioPruneRevision]
  package var presentations: [FlowPortfolioPresentation]
  package var rankings: [FlowPortfolioRanking]
  package var trainingSnapshots: [FlowPortfolioTrainingSnapshot]
  package var fits: [FlowPortfolioFit]
  package var activations: [FlowPortfolioActivation]
  package var selectedSourceID: UUID?
  package var currentRoundID: UUID?
  package var currentCandidateID: UUID?
  package var currentPruneRevisionID: UUID?
  package var activeFitID: UUID?
  package var currentPresentationID: UUID?

  package static func empty(purpose: FlowPortfolioPurpose = .artist) -> Self {
    Self(schemaVersion: 2, purpose: purpose, id: UUID(), createdAt: Date(), revision: 0,
      sources: [], rounds: [], candidates: [], choices: [], pruneRevisions: [],
      presentations: [], rankings: [], trainingSnapshots: [], fits: [], activations: [],
      selectedSourceID: nil, currentRoundID: nil, currentCandidateID: nil,
      currentPruneRevisionID: nil, activeFitID: nil, currentPresentationID: nil)
  }
  package var latestRankings: [FlowPortfolioRanking] {
    let superseded = Set(rankings.compactMap(\.supersedesID))
    return rankings.filter { !superseded.contains($0.id) }
  }
  package func latestPrune(candidateID: UUID) -> FlowPortfolioPruneRevision? {
    pruneRevisions.last { $0.candidateID == candidateID }
  }
  /// Multiple retained authoring occurrences may adopt one exact Photo. Keep
  /// their historical IDs and answers while navigating the Photo's full history.
  package func photoSourceIDs(for sourceID: UUID) -> Set<UUID> {
    guard let photo = sources.first(where: { $0.id == sourceID })?.photo else { return [sourceID] }
    return Set(sources.filter { $0.photo == photo }.map(\.id))
  }
}
