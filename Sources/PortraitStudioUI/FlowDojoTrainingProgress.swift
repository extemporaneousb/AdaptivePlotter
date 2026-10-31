import Foundation
import PortraitArtists
import PortraitLibrary

/// One metadata-only supervision projection feeds both UI coverage and fitting.
/// Photo/session connectivity is computed before exclusions or unused rows are trimmed.
package enum FlowDojoSupervision {
  package enum Labels: Equatable {
    case completed(strokeCount: Int, removedIndices: [Int])
    case partial([FlowArtistStrokeLabel])
    var count: Int { switch self { case .completed(let count, _): count; case .partial(let values): values.count } }
    var removedCount: Int { switch self { case .completed(_, let mask): mask.count; case .partial(let values): values.filter(\.removed).count } }
    var isEmpty: Bool { count == 0 }
    func expanded() -> [FlowArtistStrokeLabel] {
      switch self {
      case .partial(let values): return values
      case .completed(let count, let indices):
        let removed = Set(indices)
        return (0..<count).map { .init(index: $0, removed: removed.contains($0), provenance: .completedMask) }
      }
    }
  }
  package struct Entry {
    let candidate: FlowPortfolioCandidate
    let labels: Labels
    let revisions: [FlowPortfolioPruneRevision]
    let includeRoot: Bool
    let group: String
  }
  package struct Plan {
    let entries: [Entry]
    let rankings: [FlowArtistRanking]
    let choices: [FlowPortfolioChoice]
    let explicitRankings: [FlowPortfolioRanking]
    let sourceGroups: [UUID: String]
  }

  package struct Signature: Equatable {
    struct Drawing: Equatable {
      let programHash: String
      let rasterHash: String
      let recipe: FlowArtistRecipe
      let group: String
      let labels: Labels
      let includeRoot: Bool
      let revisions: [UUID: [Int]]
    }
    let drawings: [UUID: Drawing]
    let rankings: [String: FlowArtistRanking]
    init(_ plan: Plan) {
      drawings = Dictionary(uniqueKeysWithValues: plan.entries.map { entry in
        (entry.candidate.id, Drawing(programHash: entry.candidate.programHash, rasterHash: entry.candidate.raster.sha256,
          recipe: entry.candidate.recipe, group: entry.group, labels: entry.labels, includeRoot: entry.includeRoot,
          revisions: Dictionary(uniqueKeysWithValues: entry.revisions.map { ($0.id, $0.removedIndices) })))
      })
      rankings = Dictionary(uniqueKeysWithValues: plan.rankings.map { ($0.id, $0) })
    }
  }

  package static func plan(_ document: FlowPortfolioSnapshot) -> Plan {
    var groups = Dictionary(uniqueKeysWithValues: document.sources.map { ($0.id, Set($0.groupKeys)) })
    var changed = true
    while changed {
      changed = false
      for source in document.sources {
        var merged = groups[source.id] ?? []
        for other in document.sources where !(groups[other.id] ?? []).isDisjoint(with: merged) {
          merged.formUnion(groups[other.id] ?? [])
        }
        if merged != groups[source.id] { groups[source.id] = merged; changed = true }
      }
    }
    let sourceGroups = groups.mapValues { $0.sorted().joined(separator: "|") }
    let includedSources = Set(document.sources.filter { !$0.excluded }.map(\.id))
    let candidates = document.candidates.filter { !$0.excluded && includedSources.contains($0.sourceID) }
    let candidateIDs = Set(candidates.map(\.id))
    let revisions = Dictionary(grouping: document.pruneRevisions, by: \.candidateID)
    let allowedIDs = candidateIDs.union(document.pruneRevisions.filter { candidateIDs.contains($0.candidateID) }.map(\.id))
    let presentations = Dictionary(uniqueKeysWithValues: document.presentations.map { ($0.id, $0) })
    var rankings: [FlowArtistRanking] = [], explicit: [FlowPortfolioRanking] = [], choices: [FlowPortfolioChoice] = []
    for record in document.latestRankings where !record.skipped && !record.neither {
      guard let presentation = presentations[record.presentationID] else { continue }
      let allowed = Set(presentation.items.map(\.id)).intersection(allowedIDs)
      let tiers = record.orderedGroups.map { $0.filter { allowed.contains($0) } }.filter { !$0.isEmpty }
      guard tiers.reduce(0, { $0 + $1.count }) >= 2 else { continue }
      rankings.append(.init(id: record.id.uuidString, tiers: tiers.map { $0.map(\.uuidString) }, provenance: .ranking))
      explicit.append(record)
    }
    var seenChoices = Set<String>()
    for choice in document.choices {
      let key = ([choice.roundID.uuidString, choice.selectedItemID.uuidString]
        + choice.offeredItems.map { $0.id.uuidString }.sorted()).joined(separator: "|")
      guard seenChoices.insert(key).inserted, allowedIDs.contains(choice.selectedItemID) else { continue }
      let others = choice.offeredItems.filter { $0.id != choice.selectedItemID && allowedIDs.contains($0.id) }.map { $0.id.uuidString }
      guard !others.isEmpty else { continue }
      rankings.append(.init(id: choice.id.uuidString, tiers: [[choice.selectedItemID.uuidString], others], provenance: .choice))
      choices.append(choice)
    }
    let comparedIDs = Set(rankings.flatMap { $0.tiers.flatMap { $0 } })
    var entries: [Entry] = []
    for candidate in candidates {
      let edits = revisions[candidate.id] ?? [], latest = edits.last
      var labels: Labels = .partial([])
      if let latest, latest.action == .completeTarget {
        labels = .completed(strokeCount: candidate.strokeCount, removedIndices: latest.removedIndices)
      } else if let latest {
        let byID = Dictionary(uniqueKeysWithValues: edits.map { ($0.id, $0) })
        var decisions: [Int: FlowArtistStrokeLabel] = [:]
        for id in latest.undoOperationIDs {
          guard let edit = byID[id], edit.action == .remove || edit.action == .restore else { continue }
          for index in edit.affectedIndices {
            decisions[index] = .init(index: index, removed: edit.action == .remove,
              provenance: edit.action == .remove ? .remove : .restore)
          }
        }
        labels = .partial(decisions.keys.sorted().compactMap { decisions[$0] })
      }
      let rankedEdits = edits.filter { comparedIDs.contains($0.id.uuidString) }
      let includeRoot = !labels.isEmpty || comparedIDs.contains(candidate.id.uuidString)
      guard includeRoot || !rankedEdits.isEmpty else { continue }
      entries.append(.init(candidate: candidate, labels: labels, revisions: rankedEdits, includeRoot: includeRoot,
        group: sourceGroups[candidate.sourceID] ?? "source:" + candidate.sourceID.uuidString))
    }
    return Plan(entries: entries, rankings: rankings, choices: choices, explicitRankings: explicit, sourceGroups: sourceGroups)
  }
}

package struct FlowDojoPhotoProgress: Equatable, Sendable {
  package var candidateCount = 0
  package var supervisedCandidateCount = 0
  package var choiceCount = 0
  package var choiceComparisonCount = 0
  package var rankingCount = 0
  package var rankingComparisonCount = 0
  package var tieComparisonCount = 0
  package var removeLabelCount = 0
  package var keepLabelCount = 0
  package var completedTargetCount = 0
  package var partialCorrectionCount = 0
}

/// Counts describe effective current feedback, never approvals inferred from browsing.
/// Comparison counts precede numeric feature-degeneracy filtering; fit reports remain authoritative.
package struct FlowDojoTrainingProgress: Equatable, Sendable {
  package let revision: Int
  package let photoCount: Int
  package let includedPhotoCount: Int
  package let feedbackPhotoCount: Int
  package let feedbackGroupCount: Int
  package let generatedDrawingCount: Int
  package let choiceCount: Int
  package let choiceComparisonCount: Int
  package let rankingCount: Int
  package let rankingComparisonCount: Int
  package let tieComparisonCount: Int
  package let removeLabelCount: Int
  package let keepLabelCount: Int
  package let completedTargetCount: Int
  package let partialCorrectionCount: Int
  package let supervisedCandidateCount: Int
  package let exampleCount: Int
  package let featureValueCount: Int
  package let canAttemptFit: Bool
  package let readinessMessage: String
  package let latestFitAttemptRevision: Int?
  package let latestFitRevision: Int?
  package let activeFitRevision: Int?
  package let hasTrainingChanges: Bool?
  package let activeHasTrainingChanges: Bool?
  package let pendingChoiceCount: Int
  package let pendingRankingCount: Int
  package let pendingLabelCandidateCount: Int
  private let photos: [UUID: FlowDojoPhotoProgress]

  package init(document: FlowPortfolioSnapshot, fittedDocument: FlowPortfolioSnapshot? = nil,
    activeDocument: FlowPortfolioSnapshot? = nil) {
    let plan = FlowDojoSupervision.plan(document)
    revision = document.revision; photoCount = document.sources.count
    includedPhotoCount = document.sources.filter { !$0.excluded }.count
    generatedDrawingCount = document.candidates.count
    var values = Dictionary(uniqueKeysWithValues: document.sources.map { ($0.id, FlowDojoPhotoProgress()) })
    for c in document.candidates { values[c.sourceID, default: .init()].candidateCount += 1 }
    var itemSources: [String: UUID] = [:]
    var roots: [String: UUID] = [:]
    var masks: [String: [Int]] = [:]
    let latestEdits = Dictionary(grouping: document.pruneRevisions, by: \.candidateID).compactMapValues(\.last)
    for entry in plan.entries {
      let c = entry.candidate
      values[c.sourceID, default: .init()].supervisedCandidateCount += 1
      values[c.sourceID, default: .init()].removeLabelCount += entry.labels.removedCount
      values[c.sourceID, default: .init()].keepLabelCount += entry.labels.count - entry.labels.removedCount
      if !entry.labels.isEmpty {
        if latestEdits[c.id]?.action == .completeTarget { values[c.sourceID, default: .init()].completedTargetCount += 1 }
        else { values[c.sourceID, default: .init()].partialCorrectionCount += 1 }
      }
      itemSources[c.id.uuidString] = c.sourceID; roots[c.id.uuidString] = c.id; masks[c.id.uuidString] = []
      for edit in entry.revisions { itemSources[edit.id.uuidString] = c.sourceID; roots[edit.id.uuidString] = c.id; masks[edit.id.uuidString] = edit.removedIndices }
    }
    var choicePairs = 0, rankPairs = 0, ties = 0, maskPairs = 0
    for ranking in plan.rankings {
      let ordered = ranking.tiers.enumerated().flatMap { tier, ids in ids.map { (tier, $0) } }
      let sources = Set(ordered.compactMap { itemSources[$0.1] })
      for source in sources {
        if ranking.provenance == .choice { values[source, default: .init()].choiceCount += 1 }
        else { values[source, default: .init()].rankingCount += 1 }
      }
      for a in ordered.indices { for b in ordered.indices where b > a {
        if ranking.provenance == .choice && (ordered[a].0 != 0 || ordered[b].0 == 0) { continue }
        let pairSources = Set([itemSources[ordered[a].1], itemSources[ordered[b].1]].compactMap { $0 })
        if ranking.provenance == .choice {
          choicePairs += 1
          for source in pairSources { values[source, default: .init()].choiceComparisonCount += 1 }
        } else {
          rankPairs += 1
          for source in pairSources { values[source, default: .init()].rankingComparisonCount += 1 }
          if ordered[a].0 == ordered[b].0 {
            ties += 1
            for source in pairSources { values[source, default: .init()].tieComparisonCount += 1 }
          }
          if roots[ordered[a].1] == roots[ordered[b].1] && masks[ordered[a].1] != masks[ordered[b].1] { maskPairs += 1 }
        }
      } }
    }
    photos = values
    choiceCount = plan.choices.count; choiceComparisonCount = choicePairs
    rankingCount = plan.explicitRankings.count; rankingComparisonCount = rankPairs; tieComparisonCount = ties
    removeLabelCount = values.values.reduce(0) { $0 + $1.removeLabelCount }
    keepLabelCount = values.values.reduce(0) { $0 + $1.keepLabelCount }
    completedTargetCount = values.values.reduce(0) { $0 + $1.completedTargetCount }
    partialCorrectionCount = values.values.reduce(0) { $0 + $1.partialCorrectionCount }
    supervisedCandidateCount = plan.entries.count
    feedbackPhotoCount = Set(plan.entries.map { $0.candidate.sourceID }).count
    feedbackGroupCount = Set(plan.entries.map(\.group)).count
    exampleCount = plan.entries.reduce(0) { $0 + ($1.includeRoot ? 1 : 0) + $1.revisions.count }
    featureValueCount = plan.entries.reduce(0) { sum, entry in
      sum + ((entry.includeRoot ? 1 : 0) + entry.revisions.count)
        * (FlowArtistFeatures.drawingCount + entry.candidate.strokeCount * FlowArtistFeatures.strokeCount)
    }
    let snapshots = Dictionary(uniqueKeysWithValues: document.trainingSnapshots.map { ($0.id, $0) })
    let attempt = document.fits.last.flatMap { snapshots[$0.snapshotID] }
    let latest = document.fits.last(where: \.hasCheckpoint).flatMap { snapshots[$0.snapshotID] }
    let active = document.fits.first(where: { $0.id == document.activeFitID }).flatMap { snapshots[$0.snapshotID] }
    latestFitAttemptRevision = attempt?.portfolioRevision
    latestFitRevision = latest?.portfolioRevision; activeFitRevision = active?.portfolioRevision
    func comparison(_ frozen: FlowPortfolioSnapshot?, metadata: FlowPortfolioTrainingSnapshot?) -> FlowDojoSupervision.Plan? {
      guard let metadata else { return FlowDojoSupervision.plan(.empty(purpose: document.purpose)) }
      guard let frozen, frozen.id == document.id, frozen.revision == metadata.portfolioRevision else { return nil }
      return FlowDojoSupervision.plan(frozen)
    }
    let fittedPlan = comparison(fittedDocument, metadata: latest)
    let activePlan = comparison(activeDocument, metadata: active)
    let signature = FlowDojoSupervision.Signature(plan)
    hasTrainingChanges = fittedPlan.map { signature != FlowDojoSupervision.Signature($0) }
    activeHasTrainingChanges = activePlan.map { signature != FlowDojoSupervision.Signature($0) }
    func differences<K: Hashable, V: Equatable>(_ current: [K: V], _ prior: [K: V]) -> Int {
      Set(current.keys).union(prior.keys).filter { current[$0] != prior[$0] }.count
    }
    func choices(_ value: FlowDojoSupervision.Plan) -> [String: [[String]]] {
      Dictionary(uniqueKeysWithValues: value.rankings.filter { $0.provenance == .choice }.map { ($0.id, $0.tiers) })
    }
    func explicit(_ value: FlowDojoSupervision.Plan) -> [UUID: [[String]]] {
      let rankings = Dictionary(uniqueKeysWithValues: value.rankings.map { ($0.id, $0.tiers) })
      return Dictionary(uniqueKeysWithValues: value.explicitRankings.compactMap { record in
        rankings[record.id.uuidString].map { (record.presentationID, $0) }
      })
    }
    func labels(_ value: FlowDojoSupervision.Plan) -> [UUID: FlowDojoSupervision.Labels] {
      Dictionary(uniqueKeysWithValues: value.entries.filter { !$0.labels.isEmpty }.map { ($0.candidate.id, $0.labels) })
    }
    pendingChoiceCount = fittedPlan.map { differences(choices(plan), choices($0)) } ?? 0
    pendingRankingCount = fittedPlan.map { differences(explicit(plan), explicit($0)) } ?? 0
    pendingLabelCandidateCount = fittedPlan.map { differences(labels(plan), labels($0)) } ?? 0
    let withinBudget = exampleCount <= 5_000 && featureValueCount <= 8_000_000
      && removeLabelCount + keepLabelCount + maskPairs <= 20_000 && choicePairs + rankPairs <= 20_000
      && plan.entries.allSatisfy { $0.candidate.strokeCount <= 10_000 }
    canAttemptFit = withinBudget && (choicePairs + rankPairs >= 2
      || (removeLabelCount > 0 && keepLabelCount > 0) || maskPairs >= 2)
    if !withinBudget { readinessMessage = "This training selection exceeds the local fit limit. Exclude some feedback drawings or photos; their history stays saved." }
    else if canAttemptFit { readinessMessage = "Feedback is ready for a local fit. Fit results will report usable comparisons and photo-group holdout coverage." }
    else if removeLabelCount > 0 && keepLabelCount == 0 { readinessMessage = "Removal feedback is saved. Finish an intentional pruning target, restore lines, or rank alternative masks to supply keep evidence." }
    else { readinessMessage = "Choose between drawings, rank alternatives, or finish a pruning target. Browsing and generation alone do not teach preferences." }
  }

  package func photo(_ sourceID: UUID) -> FlowDojoPhotoProgress { photos[sourceID] ?? .init() }
}
