import Foundation
import Testing
@testable import PlotterApp

@Suite("Operational ordinal preference fitting")
struct PortraitOrdinalTrainingTests {
  @Test("real ordinal fit is deterministic and improves heldout known-preference ranking")
  func knownPreference() async throws {
    let (scope, archive) = try portraitTrainingFixture()
    let dataset = try PortraitPreferenceDatasetBuilder.freeze(archive: archive, scope: scope, seed: 7)
    let first = try await PortraitOrdinalTrainer.fit(dataset: dataset, parent: nil)
    let second = try await PortraitOrdinalTrainer.fit(dataset: dataset, parent: nil)
    #expect(first.id == second.id)
    #expect(first.payload.model == second.payload.model)
    #expect(first.payload.evaluation.comparablePairCount > 0)
    let ordering = try #require(first.payload.evaluation.withinSourceOrderingAccuracy)
    #expect(ordering > 0.9)
    let trainedLoss = try #require(first.payload.evaluation.holdoutLoss)
    let priorLoss = try #require(first.payload.evaluation.priorHoldoutLoss)
    #expect(trainedLoss < priorLoss)
    let low = try #require(dataset.payload.rows.first { $0.label.rating == 1 })
    let high = try #require(dataset.payload.rows.first { $0.label.rating == 5 })
    #expect(try PortraitOrdinalTrainer.utility(model: first.payload.model, features: high.features)
      > PortraitOrdinalTrainer.utility(model: first.payload.model, features: low.features))
    #expect(zip(first.payload.model.thresholds, first.payload.model.thresholds.dropFirst()).allSatisfy { $0 < $1 })
  }

  @Test("continued fit consumes revised labels and records deterministic reset parent lineage")
  func continuedFit() async throws {
    let fixture = try portraitTrainingFixture()
    let scope = fixture.0
    var archive = fixture.1
    let dataset = try PortraitPreferenceDatasetBuilder.freeze(archive: archive, scope: scope, seed: 7)
    let parent = try await PortraitOrdinalTrainer.fit(dataset: dataset, parent: nil)
    for old in archive.labels {
      let candidate = try #require(archive.entries.first { $0.id == old.candidateID }?.candidate)
      archive.labels.append(try .init(candidate: candidate, rating: 6-old.rating, scope: scope.scope,
        presentation: old.presentation, previousRevisionID: old.id,
        id: UUID(), createdAt: Date(timeIntervalSince1970: 200)))
    }
    let revised = try PortraitPreferenceDatasetBuilder.freeze(archive: archive, scope: scope, seed: 7)
    let child = try await PortraitOrdinalTrainer.fit(dataset: revised, parent: parent)
    #expect(child.payload.parentCheckpointID == parent.id)
    #expect(child.payload.initialization == .deterministicFullRefit)
    #expect(child.payload.optimizerState == .reset)
    #expect(child.payload.dataset.id != parent.payload.dataset.id)
    #expect(child.payload.model != parent.payload.model)
    #expect(child.payload.evaluation.priorHoldoutLoss != nil)
    let childLoss = try #require(child.payload.evaluation.holdoutLoss)
    let parentLoss = try #require(child.payload.evaluation.priorHoldoutLoss)
    #expect(childLoss < parentLoss)
  }

  @Test("scarcity, constant labels, inactive variation, and invalid numerical input fail explicitly")
  func insufficiency() async throws {
    let (scope, archive) = try portraitTrainingFixture(sourceCount: 1, samplesPerSource: 3)
    let sparse = try PortraitPreferenceDatasetBuilder.freeze(archive: archive, scope: scope, seed: 7)
    await #expect(throws: PortraitTrainingError.self) { try await PortraitOrdinalTrainer.fit(dataset: sparse, parent: nil) }
    let full = try portraitTrainingFixture(sourceCount: 1)
    var constant = full.1
    constant.labels = try constant.entries.map { try .init(candidate: $0.candidate, rating: 3, scope: full.0.scope, presentation: .init()) }
    let constantDataset = try PortraitPreferenceDatasetBuilder.freeze(archive: constant, scope: full.0, seed: 7)
    await #expect(throws: PortraitTrainingError.self) { try await PortraitOrdinalTrainer.fit(dataset: constantDataset, parent: nil) }
    var bad = PortraitOrdinalFitConfiguration.standard
    bad.learningRate = .nan
    await #expect(throws: PortraitTrainingError.self) { try await PortraitOrdinalTrainer.fit(dataset: constantDataset, parent: nil, configuration: bad) }
    #expect(throws: PortraitTrainingError.self) {
      try PortraitOrdinalTrainer.utility(model: .init(weights: [.nan], thresholds: [-1,0,1,2]), features: [1])
    }
  }

  @Test("cancelled fit cannot produce a completed checkpoint")
  func cancellation() async throws {
    let (scope, archive) = try portraitTrainingFixture()
    let dataset = try PortraitPreferenceDatasetBuilder.freeze(archive: archive, scope: scope, seed: 7)
    let operation = Task {
      withUnsafeCurrentTask { $0?.cancel() }
      return try await PortraitOrdinalTrainer.fit(dataset: dataset, parent: nil)
    }
    await #expect(throws: CancellationError.self) { try await operation.value }
  }

  @Test("no holdout gives explicit missing quality evidence and corrupted checkpoint is rejected")
  func missingEvidenceAndCorruption() async throws {
    let (scope, archive) = try portraitTrainingFixture(sourceCount: 1)
    let dataset = try PortraitPreferenceDatasetBuilder.freeze(archive: archive, scope: scope, seed: 7)
    let checkpoint = try await PortraitOrdinalTrainer.fit(dataset: dataset, parent: nil)
    #expect(checkpoint.payload.evaluation.holdoutLoss == nil)
    #expect(checkpoint.payload.evaluation.withinSourceOrderingAccuracy == nil)
    #expect(checkpoint.payload.evaluation.limitations.contains { $0.contains("No independent heldout") })
    let corrupted = try portraitTrainingReplacingJSON(checkpoint, key: "id", value: String(repeating: "0", count: 64))
    #expect(throws: PortraitTrainingError.self) { try PortraitTrainingValidation.checkpoint(corrupted) }
    let scopeChanged = PortraitStyleScope(id: scope.id, name: "Changed", revision: 2, objective: scope.scope.objective,
      allowedFamilies: scope.scope.allowedFamilies, activeParameters: scope.scope.activeParameters, frozenParameters: scope.scope.frozenParameters)
    let incompatibleDefinition = PortraitTrainingScopeDefinition(scope: scopeChanged, mode: scope.mode, referenceRecipe: scope.referenceRecipe,
      schemaRevision: scope.schemaRevision)
    var changedArchive = archive
    changedArchive.labels = try changedArchive.entries.enumerated().map { index, entry in
      try .init(candidate: entry.candidate, rating: 1 + index % 5, scope: scopeChanged, presentation: .init())
    }
    let incompatibleDataset = try PortraitPreferenceDatasetBuilder.freeze(archive: changedArchive, scope: incompatibleDefinition, seed: 7)
    await #expect(throws: PortraitTrainingError.self) { try await PortraitOrdinalTrainer.fit(dataset: incompatibleDataset, parent: checkpoint) }
  }
}
