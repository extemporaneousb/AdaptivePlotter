import Foundation

enum PortraitPreferenceDatasetBuilder {
  static func freeze(archive: PortraitCandidateArchive, scope: PortraitTrainingScopeDefinition, seed: UInt64) throws -> PortraitPreferenceDataset {
    try Task.checkCancellation()
    let schema = try PortraitTrainingFeatures.schema(scope: scope)
    let candidates = archive.entries.map(\.candidate).sorted { $0.id < $1.id }
    guard Set(candidates.map(\.id)).count == candidates.count,
      Set(archive.labels.map(\.id)).count == archive.labels.count else { throw PortraitTrainingError.invalid("Duplicate candidate or label IDs.") }
    let labels = Dictionary(uniqueKeysWithValues: archive.labels.map { ($0.id, $0) })
    var successors: [UUID: UUID] = [:]
    for label in archive.labels {
      try Task.checkCancellation()
      try PortraitArchiveValidation.label(label)
      if let previousID = label.previousRevisionID {
        guard let previous = labels[previousID], previous.candidateID == label.candidateID,
          previous.scope.id == label.scope.id, previous.presentation.physicalAttemptID == label.presentation.physicalAttemptID,
          successors[previousID] == nil else { throw PortraitTrainingError.invalid("Broken or forked label revision graph.") }
        successors[previousID] = label.id
      }
    }
    for label in archive.labels {
      try Task.checkCancellation()
      var visited: Set<UUID> = [], cursor: UUID? = label.id
      while let id = cursor {
        if visited.count % 128 == 0 { try Task.checkCancellation() }
        guard visited.insert(id).inserted else { throw PortraitTrainingError.invalid("Cyclic label revision graph.") }
        cursor = labels[id]?.previousRevisionID
      }
    }
    // Group the entire retained graph first: even an unlabeled bridge can leak a source.
    var parents = Array(candidates.indices)
    func root(_ start: Int) -> Int { var i = start; while parents[i] != i { i = parents[i] }; return i }
    var owners: [String: Int] = [:]
    for (index, candidate) in candidates.enumerated() {
      if index % 128 == 0 { try Task.checkCancellation() }
      for key in ["source:" + candidate.sourceSHA256, "capture:" + candidate.captureSessionID.uuidString,
        "ancestry:" + candidate.lineage.ancestryGroupID.uuidString] {
        if let owner = owners[key] { let a = root(index), b = root(owner); parents[max(a,b)] = min(a,b) }
        else { owners[key] = index }
      }
    }
    var members: [Int: [String]] = [:]
    for index in candidates.indices {
      if index % 128 == 0 { try Task.checkCancellation() }
      members[root(index), default: []].append(candidates[index].id)
    }
    var groupMembers: [String: [String]] = [:], groupForCandidate: [String: String] = [:]
    for ids in members.values {
      try Task.checkCancellation()
      let sorted = ids.sorted()
      let memberCandidates = candidates.filter { sorted.contains($0.id) }
      let anchors = memberCandidates.flatMap { ["source:" + $0.sourceSHA256, "capture:" + $0.captureSessionID.uuidString, "ancestry:" + $0.lineage.ancestryGroupID.uuidString] }
      let id = PortraitCandidateCoding.digest(Data(("portrait-source-group-v1|" + anchors.sorted().first!).utf8))
      groupMembers[id] = sorted
      for candidateID in sorted { groupForCandidate[candidateID] = id }
    }
    let candidateMap = Dictionary(uniqueKeysWithValues: candidates.map { ($0.id, $0) })
    var exclusions: [PortraitPreferenceDataset.Exclusion] = []
    var eligible: [(PortraitCandidate, PortraitLabelRevision, [Double])] = []
    var leafKeys: Set<String> = []
    for label in archive.labels.sorted(by: { $0.id.uuidString < $1.id.uuidString }) {
      try Task.checkCancellation()
      func exclude(_ reason: String) { exclusions.append(.init(candidateID: label.candidateID, labelRevisionID: label.id, reason: reason)) }
      if successors[label.id] != nil { exclude("Superseded label revision."); continue }
      let key = label.candidateID + "|" + label.scope.id.uuidString + "|" + (label.presentation.physicalAttemptID?.uuidString ?? "screen")
      guard leafKeys.insert(key).inserted else { throw PortraitTrainingError.invalid("Multiple current label roots for one candidate, scope and attempt.") }
      if archive.withdrawnLabelIDs.contains(label.id.uuidString) { exclude("Current label withdrawn; superseded labels remain excluded."); continue }
      guard label.scope == scope.scope else { exclude("Different named scope configuration or objective."); continue }
      guard let candidate = candidateMap[label.candidateID] else { exclude("Candidate assets were deleted or are unavailable."); continue }
      do {
        try PortraitArchiveValidation.label(label, candidate: candidate)
        let features = try PortraitTrainingFeatures.values(candidate: candidate, scope: scope, schema: schema,
          presentation: .init(label.presentation))
        eligible.append((candidate, label, features))
      } catch { exclude(error.localizedDescription) }
    }
    for candidate in candidates {
      try Task.checkCancellation()
      guard !archive.labels.contains(where: { $0.candidateID == candidate.id }) else { continue }
      exclusions.append(.init(candidateID: candidate.id, labelRevisionID: nil, reason: "Retained without a label; still participates in source grouping."))
    }
    let eligibleGroups = Set(eligible.compactMap { groupForCandidate[$0.0.id] })
    let ordered = eligibleGroups.sorted {
      let lhs = PortraitCandidateCoding.digest(Data("\(seed)|\($0)".utf8))
      let rhs = PortraitCandidateCoding.digest(Data("\(seed)|\($1)".utf8))
      return lhs == rhs ? $0 < $1 : lhs < rhs
    }
    let holdoutCount = ordered.count >= 3 ? max(1, ordered.count / 5) : 0
    let holdout = Set(ordered.prefix(holdoutCount))
    let groups = groupMembers.keys.sorted().map { id in
      PortraitPreferenceDataset.Group(id: id, candidateIDs: groupMembers[id]!, split: holdout.contains(id) ? .holdout : .training)
    }
    let rows = eligible.map { candidate, label, features in
      PortraitPreferenceDataset.Row(candidateID: candidate.id, label: label, sourceSHA256: candidate.sourceSHA256,
        captureSessionID: candidate.captureSessionID, ancestryGroupID: candidate.lineage.ancestryGroupID,
        groupID: groupForCandidate[candidate.id]!, split: holdout.contains(groupForCandidate[candidate.id]!) ? .holdout : .training,
        features: features, producerRevision: candidate.producerRevision,
        analysisRevision: candidate.raster.analysisGeometry?.preprocessingRevision ?? "legacy-or-synthetic-analysis-v1",
        warpRevision: candidate.warpManifest?.algorithmRevision)
    }.sorted { $0.label.id.uuidString < $1.label.id.uuidString }
    let dataset = try PortraitPreferenceDataset(payload: .init(revision: "portrait-preference-dataset-v1", scope: scope,
      featureSchema: schema, rows: rows, groups: groups, splitSeed: seed, exclusions: exclusions))
    try PortraitTrainingValidation.dataset(dataset)
    try Task.checkCancellation()
    return dataset
  }
}
