import Foundation
import PortraitArtists
import PortraitLibrary
import PortraitCore

package struct FlowAuthoringPhotoProgress: Equatable, Sendable {
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
package struct FlowAuthoringTrainingProgress: Equatable, Sendable {
  package private(set) var revision: Int
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
  private let photos: [UUID: FlowAuthoringPhotoProgress]

  package init(document: FlowPortfolioSnapshot, fittedDocument: FlowPortfolioSnapshot? = nil,
    activeDocument: FlowPortfolioSnapshot? = nil) {
    let plan = FlowPortfolioSupervision.plan(document)
    var firstSourceByPhoto: [PhotoRef: UUID] = [:], photoKeys: [UUID: UUID] = [:]
    for source in document.sources {
      if let photo = source.photo {
        let key = firstSourceByPhoto[photo] ?? source.id
        firstSourceByPhoto[photo] = key; photoKeys[source.id] = key
      } else { photoKeys[source.id] = source.id }
    }
    func photoKey(_ source: UUID) -> UUID { photoKeys[source] ?? source }
    revision = document.revision; photoCount = Set(photoKeys.values).count
    includedPhotoCount = Set(document.sources.filter { !$0.excluded }.map { photoKey($0.id) }).count
    generatedDrawingCount = document.candidates.count
    var values = Dictionary(uniqueKeysWithValues: Set(photoKeys.values).map { ($0, FlowAuthoringPhotoProgress()) })
    for c in document.candidates { values[photoKey(c.sourceID), default: .init()].candidateCount += 1 }
    var itemSources: [String: UUID] = [:]
    var roots: [String: UUID] = [:]
    var masks: [String: [Int]] = [:]
    var latestEdits: [UUID: FlowPortfolioPruneRevision] = [:]
    for revision in document.pruneRevisions { latestEdits[revision.candidateID] = revision }
    for entry in plan.entries {
      let c = entry.candidate
      values[photoKey(c.sourceID), default: .init()].supervisedCandidateCount += 1
      values[photoKey(c.sourceID), default: .init()].removeLabelCount += entry.labels.removedCount
      values[photoKey(c.sourceID), default: .init()].keepLabelCount += entry.labels.count - entry.labels.removedCount
      if !entry.labels.isEmpty {
        if latestEdits[c.id]?.action == .completeTarget { values[photoKey(c.sourceID), default: .init()].completedTargetCount += 1 }
        else { values[photoKey(c.sourceID), default: .init()].partialCorrectionCount += 1 }
      }
      itemSources[c.id.uuidString] = photoKey(c.sourceID); roots[c.id.uuidString] = c.id; masks[c.id.uuidString] = []
      for edit in entry.revisions { itemSources[edit.id.uuidString] = photoKey(c.sourceID); roots[edit.id.uuidString] = c.id; masks[edit.id.uuidString] = edit.removedIndices }
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
    photos = Dictionary(uniqueKeysWithValues: document.sources.map { ($0.id, values[photoKey($0.id)] ?? .init()) })
    choiceCount = plan.choices.count; choiceComparisonCount = choicePairs
    rankingCount = plan.explicitRankings.count; rankingComparisonCount = rankPairs; tieComparisonCount = ties
    removeLabelCount = values.values.reduce(0) { $0 + $1.removeLabelCount }
    keepLabelCount = values.values.reduce(0) { $0 + $1.keepLabelCount }
    completedTargetCount = values.values.reduce(0) { $0 + $1.completedTargetCount }
    partialCorrectionCount = values.values.reduce(0) { $0 + $1.partialCorrectionCount }
    supervisedCandidateCount = plan.entries.count
    feedbackPhotoCount = Set(plan.entries.map { photoKey($0.candidate.sourceID) }).count
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
    func comparison(_ frozen: FlowPortfolioSnapshot?, metadata: FlowPortfolioTrainingSnapshot?) -> FlowPortfolioSupervision.Plan? {
      guard let metadata else { return FlowPortfolioSupervision.plan(.empty(purpose: document.purpose)) }
      guard let frozen, frozen.id == document.id, frozen.revision == metadata.portfolioRevision else { return nil }
      return FlowPortfolioSupervision.plan(frozen)
    }
    let fittedPlan = comparison(fittedDocument, metadata: latest)
    let activePlan = active == latest && activeDocument == fittedDocument
      ? fittedPlan : comparison(activeDocument, metadata: active)
    let signature = FlowPortfolioSupervision.Signature(plan)
    hasTrainingChanges = fittedPlan.map { signature != FlowPortfolioSupervision.Signature($0) }
    activeHasTrainingChanges = activePlan.map { signature != FlowPortfolioSupervision.Signature($0) }
    func differences<K: Hashable, V: Equatable>(_ current: [K: V], _ prior: [K: V]) -> Int {
      Set(current.keys).union(prior.keys).filter { current[$0] != prior[$0] }.count
    }
    func choices(_ value: FlowPortfolioSupervision.Plan) -> [String: [[String]]] {
      Dictionary(uniqueKeysWithValues: value.rankings.filter { $0.provenance == .choice }.map { ($0.id, $0.tiers) })
    }
    func explicit(_ value: FlowPortfolioSupervision.Plan) -> [UUID: [[String]]] {
      let rankings = Dictionary(uniqueKeysWithValues: value.rankings.map { ($0.id, $0.tiers) })
      return Dictionary(uniqueKeysWithValues: value.explicitRankings.compactMap { record in
        rankings[record.id.uuidString].map { (record.presentationID, $0) }
      })
    }
    func labels(_ value: FlowPortfolioSupervision.Plan) -> [UUID: FlowPortfolioSupervision.Labels] {
      Dictionary(uniqueKeysWithValues: value.entries.filter { !$0.labels.isEmpty }.map { ($0.candidate.id, $0.labels) })
    }
    pendingChoiceCount = fittedPlan.map { differences(choices(plan), choices($0)) } ?? 0
    pendingRankingCount = fittedPlan.map { differences(explicit(plan), explicit($0)) } ?? 0
    pendingLabelCandidateCount = fittedPlan.map { differences(labels(plan), labels($0)) } ?? 0
    let withinBudget = exampleCount <= 5_000
      && FlowArtistTrainingLimits.accepts(featureValueCount: featureValueCount,
        explicitLabelCount: removeLabelCount + keepLabelCount + maskPairs)
      && choicePairs + rankPairs <= FlowArtistTrainingLimits.maximumComparisons
      && plan.entries.allSatisfy { $0.candidate.strokeCount <= 10_000 }
    canAttemptFit = withinBudget && (choicePairs + rankPairs >= 2
      || (removeLabelCount > 0 && keepLabelCount > 0) || maskPairs >= 2)
    if !withinBudget { readinessMessage = "This training selection exceeds the local fit limit. Exclude some feedback drawings or photos; their history stays saved." }
    else if canAttemptFit { readinessMessage = "Feedback is ready for a local fit. Fit results will report usable comparisons and photo-group holdout coverage." }
    else if removeLabelCount > 0 && keepLabelCount == 0 { readinessMessage = "Removal feedback is saved. Finish an intentional pruning target, restore lines, or rank alternative masks to supply keep evidence." }
    else { readinessMessage = "Choose between drawings, rank alternatives, or finish a pruning target. Browsing and generation alone do not teach preferences." }
  }

  package func atRevision(_ revision: Int) -> Self {
    var value = self; value.revision = revision; return value
  }
  package func photo(_ sourceID: UUID) -> FlowAuthoringPhotoProgress { photos[sourceID] ?? .init() }
}

/// Immutable event IDs cover the store's append-only feedback. Only grouping,
/// exclusion and fit selection are mutable semantic inputs. Titles, navigation
/// and the display revision deliberately do not trigger supervision regrouping.
package struct FlowAuthoringTrainingProgressKey: Equatable, Sendable {
  private struct Source: Equatable, Sendable {
    let id: UUID; let image: String; let photo: PhotoRef?; let subject: String?; let session: String?; let excluded: Bool
  }
  private struct Candidate: Equatable, Sendable {
    let id: UUID; let source: UUID; let program: String; let raster: String; let strokes: Int; let excluded: Bool
  }
  private let portfolio: UUID
  private let sources: [Source]
  private let candidates: [Candidate]
  private let choices: [UUID], prunes: [UUID], presentations: [UUID], rankings: [UUID]
  private let snapshots: [FlowPortfolioTrainingSnapshot]
  private let fits: [FlowPortfolioFit]
  private let active: UUID?
  package init(_ document: FlowPortfolioSnapshot) {
    portfolio = document.id
    sources = document.sources.map { .init(id: $0.id, image: $0.image.sha256, photo: $0.photo,
      subject: $0.subjectID, session: $0.sessionID, excluded: $0.excluded) }
    candidates = document.candidates.map { .init(id: $0.id, source: $0.sourceID,
      program: $0.programHash, raster: $0.raster.sha256, strokes: $0.strokeCount, excluded: $0.excluded) }
    choices = document.choices.map(\.id); prunes = document.pruneRevisions.map(\.id)
    presentations = document.presentations.map(\.id); rankings = document.rankings.map(\.id)
    snapshots = document.trainingSnapshots; fits = document.fits; active = document.activeFitID
  }
}
