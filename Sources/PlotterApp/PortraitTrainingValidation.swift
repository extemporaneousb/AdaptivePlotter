import Foundation

enum PortraitTrainingValidation {
  static func scope(_ definition: PortraitTrainingScopeDefinition) throws {
    let scope = definition.scope
    let active = Set(scope.activeParameters), frozen = Set(scope.frozenParameters.map(\.parameter))
    guard definition.referenceRecipe.vectorOptions.drawingParameters == nil,
      definition.schemaRevision == PortraitTrainingScopeDefinition.currentRevision,
      !scope.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, scope.revision > 0,
      !scope.allowedFamilies.isEmpty, Set(scope.allowedFamilies).count == scope.allowedFamilies.count,
      !active.isEmpty, active.count == scope.activeParameters.count, frozen.count == scope.frozenParameters.count,
      active.isDisjoint(with: frozen), definition.referenceRecipe.vectorOptions == definition.referenceRecipe.vectorOptions.bounded,
      scope.frozenParameters.allSatisfy({ $0.value.isFinite && PortraitTrainingFeatures.bounds($0.parameter).contains($0.value) }) else {
      throw PortraitTrainingError.invalid("Unsupported named scope configuration.")
    }
    if definition.mode == .semanticBigHead {
      guard active.isSubset(of: PortraitTrainingFeatures.semanticParameters), definition.referenceRecipe.vectorOptions.semanticHead != nil,
        scope.allowedFamilies.count == 1, scope.allowedFamilies.first == definition.referenceRecipe.style else {
        throw PortraitTrainingError.invalid("Big Head varies only semantic amplitudes in one fixed line family.")
      }
    } else if !active.isDisjoint(with: PortraitTrainingFeatures.semanticParameters.union([.headScale])) {
      throw PortraitTrainingError.invalid("Ordinary style training cannot vary head geometry.")
    }
  }

  static func dataset(_ dataset: PortraitPreferenceDataset) throws {
    let payload = dataset.payload
    guard dataset.id == (try PortraitPreferenceDataset(payload: payload)).id,
      payload.revision == "portrait-preference-dataset-v1",
      payload.featureSchema == (try PortraitTrainingFeatures.schema(scope: payload.scope)),
      Set(payload.rows.map { $0.label.id }).count == payload.rows.count,
      Set(payload.groups.map(\.id)).count == payload.groups.count else {
      throw PortraitTrainingError.invalid("Dataset digest, schema, or identity mismatch.")
    }
    var memberships: [String: PortraitPreferenceDataset.Group] = [:]
    for group in payload.groups {
      guard isDigest(group.id), !group.candidateIDs.isEmpty, group.candidateIDs == group.candidateIDs.sorted(),
        Set(group.candidateIDs).count == group.candidateIDs.count else { throw PortraitTrainingError.invalid("Invalid source group.") }
      for id in group.candidateIDs {
        guard isDigest(id), memberships[id] == nil else { throw PortraitTrainingError.invalid("Candidate occurs in multiple source groups.") }
        memberships[id] = group
      }
    }
    var sourceGroups: [String: String] = [:], currentLabels: Set<String> = []
    for row in payload.rows {
      try PortraitArchiveValidation.label(row.label)
      guard row.label.scope == payload.scope.scope, row.label.candidateID == row.candidateID,
        isDigest(row.candidateID), isDigest(row.sourceSHA256), isDigest(row.label.programContentHash),
        row.features.count == payload.featureSchema.features.count,
        row.features.allSatisfy({ $0.isFinite && (-1.000000001...1.000000001).contains($0) }),
        !row.producerRevision.isEmpty, !row.analysisRevision.isEmpty,
        row.warpRevision.map({ !$0.isEmpty }) ?? true,
        let group = memberships[row.candidateID], group.id == row.groupID, group.split == row.split else {
        throw PortraitTrainingError.invalid("Dataset row provenance, feature or group mismatch.")
      }
      let activeCount = payload.scope.scope.activeParameters.count * 2
      for column in stride(from: 0, to: activeCount, by: 2) {
        guard abs(row.features[column + 1] - row.features[column] * row.features[column]) < 1e-9 else {
          throw PortraitTrainingError.invalid("Quadratic feature does not match its declared transform.")
        }
      }
      guard row.features.dropFirst(activeCount).allSatisfy({ $0 >= 0 && $0 <= 1 }) else {
        throw PortraitTrainingError.invalid("Source, family or presentation features exceed normalized bounds.")
      }
      let labelKey = row.candidateID + "|" + (row.label.presentation.physicalAttemptID?.uuidString ?? "screen")
      guard currentLabels.insert(labelKey).inserted else { throw PortraitTrainingError.invalid("Duplicate current label in dataset.") }
      for key in ["s:" + row.sourceSHA256, "c:" + row.captureSessionID.uuidString, "a:" + row.ancestryGroupID.uuidString] {
        if let previous = sourceGroups[key], previous != row.groupID { throw PortraitTrainingError.invalid("Shared source crosses dataset groups.") }
        sourceGroups[key] = row.groupID
      }
    }
  }

  static func configuration(_ configuration: PortraitOrdinalFitConfiguration) throws {
    guard configuration.revision == "ordinal-logistic-projected-gradient-v1",
      (1...10000).contains(configuration.maximumIterations), (2...100000).contains(configuration.minimumLabels),
      configuration.learningRate.isFinite, (0...1).contains(configuration.learningRate), configuration.learningRate > 0,
      configuration.regularization.isFinite, (0...10).contains(configuration.regularization),
      configuration.convergenceTolerance.isFinite, configuration.convergenceTolerance > 0 else {
      throw PortraitTrainingError.invalid("Invalid optimizer configuration.")
    }
  }

  static func checkpoint(_ checkpoint: PortraitPreferenceCheckpoint) throws {
    let payload = checkpoint.payload
    try dataset(payload.dataset)
    try configuration(payload.configuration)
    let evaluation = payload.evaluation
    let train = payload.dataset.payload.rows.filter { $0.split == .training }, holdout = payload.dataset.payload.rows.filter { $0.split == .holdout }
    guard checkpoint.id == (try PortraitPreferenceCheckpoint(payload: payload)).id,
      payload.revision == "portrait-ordinal-checkpoint-v1",
      payload.parentCheckpointID.map(isDigest) ?? true,
      payload.model.weights.count == payload.dataset.payload.featureSchema.features.count,
      payload.model.weights.allSatisfy({ $0.isFinite && abs($0) <= 30 }),
      payload.model.thresholds.count == 4, payload.model.thresholds.allSatisfy({ $0.isFinite && abs($0) <= 30 }),
      zip(payload.model.thresholds, payload.model.thresholds.dropFirst()).allSatisfy({ $0 < $1 }),
      (1...payload.configuration.maximumIterations).contains(payload.completedIterations),
      train.count >= payload.configuration.minimumLabels, Set(train.map { $0.label.rating }).count > 1,
      evaluation.trainingCount == train.count, evaluation.holdoutCount == holdout.count,
      evaluation.trainingGroupCount == Set(train.map(\.groupID)).count,
      evaluation.holdoutGroupCount == Set(holdout.map(\.groupID)).count,
      evaluation.trainingLoss.isFinite, evaluation.trainingLoss >= 0,
      [evaluation.holdoutLoss, evaluation.priorHoldoutLoss].compactMap({ $0 }).allSatisfy({ $0.isFinite && $0 >= 0 }),
      evaluation.withinSourceOrderingAccuracy.map({ $0.isFinite && (0...1).contains($0) }) ?? true,
      evaluation.comparablePairCount >= 0,
      (holdout.isEmpty ? evaluation.holdoutLoss == nil : evaluation.holdoutLoss != nil),
      payload.producerRevisions == Set(payload.dataset.payload.rows.map(\.producerRevision)).sorted(),
      payload.warpRevisions == Set(payload.dataset.payload.rows.compactMap(\.warpRevision)).sorted() else {
      throw PortraitTrainingError.invalid("Checkpoint digest, numerical state or evaluation mismatch.")
    }
  }

  static func isDigest(_ value: String) -> Bool { value.count == 64 && value.allSatisfy { $0.isHexDigit && !$0.isUppercase } }
}
