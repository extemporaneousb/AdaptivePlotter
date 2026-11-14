import Foundation
import PortraitCore
import DrawingLibrary
import PortraitArtists

/// One metadata-only supervision projection feeds both UI coverage and fitting.
/// Photo/session connectivity is computed before exclusions or unused rows are trimmed.
package enum FlowPortfolioSupervision {
  package enum Labels: Equatable {
    case completed(strokeCount: Int, removedIndices: [Int])
    case partial([FlowArtistStrokeLabel])
    package var count: Int { switch self { case .completed(let count, _): count; case .partial(let values): values.count } }
    package var removedCount: Int { switch self { case .completed(_, let mask): mask.count; case .partial(let values): values.filter(\.removed).count } }
    package var isEmpty: Bool { count == 0 }
    package func expanded() -> [FlowArtistStrokeLabel] {
      switch self {
      case .partial(let values): return values
      case .completed(let count, let indices):
        let removed = Set(indices)
        return (0..<count).map { .init(index: $0, removed: removed.contains($0), provenance: .completedMask) }
      }
    }
  }
  package struct Entry {
    package let candidate: FlowPortfolioCandidate
    package let labels: Labels
    package let revisions: [FlowPortfolioPruneRevision]
    package let includeRoot: Bool
    package let group: String
  }
  package struct Plan {
    package let entries: [Entry]
    package let rankings: [FlowArtistRanking]
    package let choices: [FlowPortfolioChoice]
    package let explicitRankings: [FlowPortfolioRanking]
    package let sourceGroups: [UUID: String]
  }

  package struct Signature: Equatable {
    package struct Drawing: Equatable {
      package let programHash: String
      package let rasterHash: String
      package let recipe: FlowArtistRecipe
      package let group: String
      package let labels: Labels
      package let includeRoot: Bool
      package let revisions: [UUID: [Int]]
    }
    package let drawings: [UUID: Drawing]
    package let rankings: [String: FlowArtistRanking]
    package init(_ plan: Plan) {
      drawings = Dictionary(uniqueKeysWithValues: plan.entries.map { entry in
        (entry.candidate.id, Drawing(programHash: entry.candidate.programHash, rasterHash: entry.candidate.raster.sha256,
          recipe: entry.candidate.recipe, group: entry.group, labels: entry.labels, includeRoot: entry.includeRoot,
          revisions: Dictionary(uniqueKeysWithValues: entry.revisions.map { ($0.id, $0.removedIndices) })))
      })
      rankings = Dictionary(uniqueKeysWithValues: plan.rankings.map { ($0.id, $0) })
    }
  }

  package static func plan(_ document: FlowPortfolioSnapshot) -> Plan {
    let sourceGroups = FlowSourceConnectivity.groups(document.sources.map { ($0.id, $0.groupKeys) })
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


package struct FlowFrozenFeedback: Codable, Equatable, Sendable {
  package let judgmentID: UUID
  package let assessment: AssessmentRef
  package let ranking: RankingCapsuleRef?
}
package struct FlowFrozenSourceCuration: Codable, Equatable, Sendable {
  package let id: UUID
  package let imageDigest: String
  package let subjectID: String?
  package let sessionID: String?
  package let excluded: Bool
  package let group: String
  package let reason: String
}
package struct FlowFrozenTrainingEntry: Codable, Equatable, Sendable {
  package let exampleID: UUID
  package let candidateID: UUID
  package let sourceID: UUID
  package let rootFeatures: ExchangeAsset
  package let features: ExchangeAsset
  package let labels: [FlowArtistStrokeLabel]
  package let removedIndices: [Int]
  package let includeRoot: Bool
  package let group: String
  package let recipe: FlowArtistRecipe
}
package struct FlowPortfolioTrainingManifest: Codable, Equatable, Sendable {
  package let profile: String
  package let id: UUID
  package let portfolioID: UUID
  package let portfolioRevision: Int
  package let entries: [FlowFrozenTrainingEntry]
  package let rankings: [FlowArtistRanking]
  package let feedback: [FlowFrozenFeedback]
  package let curation: [FlowFrozenSourceCuration]
  package let excludedCandidateIDs: [UUID]
  package let selectedPruneIDs: [UUID: UUID]
  package let selectedRankingIDs: [UUID]
  package let seed: UInt64
  package let configuration: FlowArtistFitConfiguration
  package let holdoutGroupIDs: [String]
  package let extractorVersion: String
  package let trainerVersion: String
  package var requiredFeatures: [String] = []
}
package struct FlowPortfolioTrainingInputs: Sendable {
  package let examples: [FlowArtistExample]
  package let rankings: [FlowArtistRanking]
  package let seed: UInt64
  package let configuration: FlowArtistFitConfiguration
  package let holdoutGroupIDs: [String]
}

extension FlowPortfolioStore {
  @discardableResult package func freezeTrainingSnapshot(id: UUID? = nil) async throws -> FlowPortfolioTrainingSnapshot {
    if let id, let existing = state.trainingSnapshots.first(where: { $0.id == id }) { return existing }
    try await refreshPhotoMetadata()
    let snapshotID = id ?? UUID(), document = state
    let plan = FlowPortfolioSupervision.plan(document)
    let budget = FlowFeatureReadBudget()
    var files: [String: Data] = [:], descriptors: [ExchangeDigest: ExchangeAssetDescriptor] = [:]
    var feedback: [FlowFrozenFeedback] = [], featureRefs: [UUID: ExchangeAsset] = [:]
    var pairs: [(UUID, FlowPortfolioFeedbackReference)] = []
    for value in document.choices { guard let ref = value.feedback else { throw FlowPortfolioError.invalid("Choice has no canonical feedback.") }; pairs.append((value.id, ref)) }
    for value in document.pruneRevisions where value.action != .modelProposal && value.action != .inheritedSelection {
      guard let ref = value.feedback else { throw FlowPortfolioError.invalid("Pruning has no canonical feedback.") }; pairs.append((value.id, ref))
    }
    for value in document.rankings { guard let ref = value.feedback else { throw FlowPortfolioError.invalid("Ranking has no canonical feedback.") }; pairs.append((value.id, ref)) }
    func copyAsset(_ asset: ExchangeAsset, from package: ValidatedExchangePackage) throws {
      let bytes = try FlowFeedbackReader.exactJSON(asset, package: package, budget: budget)
      guard let descriptor = package.index.known?.assets.first(where: { $0.asset.object == asset.object }), descriptor.asset == asset,
        descriptor.asset.mediaType == "application/json" else { throw FlowPortfolioError.invalid("Task dependency is not exact feature/receipt JSON.") }
      if let old = descriptors[asset.object], old != descriptor { throw FlowPortfolioError.invalid("Task asset descriptor conflict.") }
      descriptors[asset.object] = descriptor; files["data/objects/sha256/" + asset.object.description] = bytes
    }
    for (judgmentID, ref) in pairs {
      try Task.checkCancellation()
      let package = try await storage.library.feedback(ref.publication)
      try autoreleasepool {
      let previousBatch = budget.batchedFiles
      budget.batchedFiles = package.files
      defer { budget.batchedFiles = previousBatch }
      if ref.ranking != nil { _ = try FlowFeedbackReader.value(FlowPortfolioRanking.self, reference: ref, id: judgmentID, package: package, budget: budget) }
      else if document.choices.contains(where: { $0.id == judgmentID }) { _ = try FlowFeedbackReader.value(FlowPortfolioChoice.self, reference: ref, id: judgmentID, package: package, budget: budget) }
      else { _ = try FlowFeedbackReader.value(FlowPortfolioPruneRevision.self, reference: ref, id: judgmentID, package: package, budget: budget) }
      feedback.append(.init(judgmentID: judgmentID, assessment: ref.assessment, ranking: ref.ranking))
      for entry in package.files.entries.values where entry.path.hasPrefix("data/assessments/") || entry.path.hasPrefix("data/rankings/") {
        let bytes = try package.files.record(at: entry.path, maximumBytes: ExchangeJSON.maximumRecordBytes)
        if let old = files[entry.path], old != bytes { throw FlowPortfolioError.invalid("Task record conflict.") }; files[entry.path] = bytes
      }
      for asset in try FlowFeedbackReader.featureAssets(package, budget: budget) {
        let capsule = try FlowFeedbackReader.feature(asset, package: package, budget: budget)
        if let prior = featureRefs[capsule.id], prior != asset { throw FlowPortfolioError.invalid("Judgments disagree on exact feature basis.") }
        featureRefs[capsule.id] = asset
        try copyAsset(asset, from: package); try copyAsset(capsule.producer.record, from: package); try copyAsset(capsule.extractor.record, from: package)
      }
      for assessment in package.assessments.values {
        for asset in assessment.supportingAssets { try copyAsset(asset, from: package) }
        let record = try ExchangeJSON.validate(assessment.originalJSON)
        if let region = record["regionOrStrokes"] { try copyAsset(FlowFeedbackReader.decodeJSON(region, ExchangeAsset.self), from: package) }
      }
      try package.files.revalidateSelected()
      }
    }
    var entries: [FlowFrozenTrainingEntry] = []
    for entry in plan.entries {
      guard let root = featureRefs[entry.candidate.id] else { throw FlowPortfolioError.unavailable("Frozen feedback root features are missing.") }
      if entry.includeRoot {
        entries.append(.init(exampleID: entry.candidate.id, candidateID: entry.candidate.id, sourceID: entry.candidate.sourceID,
          rootFeatures: root, features: root, labels: entry.labels.expanded(), removedIndices: [], includeRoot: true, group: entry.group, recipe: entry.candidate.recipe))
      }
      for revision in entry.revisions {
        guard let exact = featureRefs[revision.id] else { throw FlowPortfolioError.unavailable("Frozen ranked-mask features are missing.") }
        entries.append(.init(exampleID: revision.id, candidateID: entry.candidate.id, sourceID: entry.candidate.sourceID,
          rootFeatures: root, features: exact, labels: [], removedIndices: revision.removedIndices, includeRoot: false, group: entry.group, recipe: entry.candidate.recipe))
      }
    }
    let curation = document.sources.map { source in
      FlowFrozenSourceCuration(id: source.id, imageDigest: source.image.sha256, subjectID: source.subjectID, sessionID: source.sessionID,
        excluded: source.excluded, group: plan.sourceGroups[source.id] ?? "source:" + source.id.uuidString,
        reason: source.excluded ? "Operator excluded this source." : "Included by the current curation.")
    }
    let manifest = FlowPortfolioTrainingManifest(profile: "adaptiveplotter.flow-training-task/1", id: snapshotID,
      portfolioID: document.id, portfolioRevision: document.revision, entries: entries, rankings: plan.rankings, feedback: feedback,
      curation: curation, excludedCandidateIDs: document.candidates.filter(\.excluded).map(\.id),
      selectedPruneIDs: Dictionary(uniqueKeysWithValues: document.candidates.compactMap { candidate in document.latestPrune(candidateID: candidate.id).map { (candidate.id, $0.id) } }),
      selectedRankingIDs: document.latestRankings.map(\.id), seed: 42, configuration: .current,
      holdoutGroupIDs: FlowArtistTraining.holdoutGroups(entries.map(\.group), seed: 42), extractorVersion: FlowArtistFeatures.revision,
      trainerVersion: FlowArtistFitConfiguration.current.revision)
    let bytes = try DrawingArtifactCoding.encoder().encode(manifest)
    let manifestAsset = try ExchangeAsset(bytes: bytes, mediaType: "application/json", encoding: "utf8-json")
    descriptors[manifestAsset.object] = .init(asset: manifestAsset); files["data/objects/sha256/" + manifestAsset.object.description] = bytes
    let index: [String: Any] = ["profile": "adaptiveplotter.exchange/1", "requiredFeatures": [String](), "kind": "feedback", "roots": [String](), "attempts": [String](),
      "includedAsOf": ISO8601DateFormatter().string(from: Date()), "assets": try JSONSerialization.jsonObject(with: DrawingArtifactCoding.encoder().encode(descriptors.values.sorted { $0.asset.object.description < $1.asset.object.description })),
      "assessments": try JSONSerialization.jsonObject(with: DrawingArtifactCoding.encoder().encode(feedback.map(\.assessment))),
      "rankingCapsules": try JSONSerialization.jsonObject(with: DrawingArtifactCoding.encoder().encode(feedback.compactMap(\.ranking))),
      "scope": try JSONSerialization.jsonObject(with: DrawingArtifactCoding.encoder().encode(manifestAsset))]
    files["data/exchange.json"] = try JSONSerialization.data(withJSONObject: index, options: [.sortedKeys, .withoutEscapingSlashes])
    let task = try FlowFeedbackCarrier.prepare(files)
    // Validate the very same exact-files reader used by future fits and offline loads.
    _ = try FlowTrainingReader.inputs(package: task.package)
    let viewBytes = try DrawingArtifactCoding.encoder().encode(document)
    let view = FlowPortfolioBlob(sha256: ExchangeDigest.hash(viewBytes).description, byteCount: viewBytes.count, mediaType: "application/json")
    frozenTrainingViews[snapshotID] = viewBytes
    var snapshot = FlowPortfolioTrainingSnapshot(id: snapshotID, createdAt: Date(), portfolioID: document.id,
      portfolioRevision: document.revision, purpose: document.purpose, document: view, contentSHA256: view.sha256)
    snapshot.manifest = manifestAsset; snapshot.publication = DrawingLibraryFeedbackRef(publication: task.package)
    var next = state; next.trainingSnapshots.append(snapshot)
    try await commit(next, feedback: task)
    return snapshot
  }
  package func trainingDocument(snapshotID: UUID) async throws -> FlowPortfolioSnapshot {
    guard let snapshot = state.trainingSnapshots.first(where: { $0.id == snapshotID }), let manifest = snapshot.manifest,
      let publication = snapshot.publication,
      let row = try await storage.library.record(.init(kind: kind("frozen-view"), id: snapshotID)),
      row.payload.count == snapshot.document.byteCount, ExchangeDigest.hash(row.payload).description == snapshot.contentSHA256 else {
      throw FlowPortfolioError.unavailable("Exact frozen training view unavailable.")
    }
    var document = try JSONDecoder().decode(FlowPortfolioSnapshot.self, from: row.payload)
    try FlowPortfolioValidation.validate(document)
    guard document.id == snapshot.portfolioID, document.revision == snapshot.portfolioRevision else { throw FlowPortfolioError.invalid("Frozen training view identity.") }
    document.frozenManifest = manifest; document.frozenTrainingPublication = publication; return document
  }
  package func trainingManifest(snapshotID: UUID) async throws -> FlowPortfolioTrainingManifest {
    guard let snapshot = state.trainingSnapshots.first(where: { $0.id == snapshotID }), let publication = snapshot.publication,
      let manifest = snapshot.manifest else { throw FlowPortfolioError.unavailable("Training task unavailable.") }
    let selected = try await storage.library.feedback(publication)
    let value = try FlowTrainingReader.manifest(package: selected)
    guard selected.index.known?.scope == manifest, value.id == snapshotID else { throw FlowPortfolioError.invalid("Training task navigation differs from exact scope.") }; return value
  }
  package func trainingInputs(snapshotID: UUID) async throws -> FlowPortfolioTrainingInputs {
    guard let snapshot = state.trainingSnapshots.first(where: { $0.id == snapshotID }), let publication = snapshot.publication,
      let manifest = snapshot.manifest else { throw FlowPortfolioError.unavailable("Training task unavailable.") }
    return try await trainingInputs(manifest: manifest, publication: publication)
  }
  package func trainingInputs(manifest: ExchangeAsset, publication: DrawingLibraryFeedbackRef) async throws -> FlowPortfolioTrainingInputs {
    let selected = try await storage.library.feedback(publication)
    guard selected.index.known?.scope == manifest else { throw FlowPortfolioError.invalid("Exact training scope mismatch.") }
    return try FlowTrainingReader.inputs(package: selected)
  }
  package func exportTraining(snapshotID: UUID, to destination: URL) async throws {
    _ = try await trainingInputs(snapshotID: snapshotID)
    guard let publication = state.trainingSnapshots.first(where: { $0.id == snapshotID })?.publication else { throw FlowPortfolioError.unavailable("Training task unavailable.") }
    try await storage.library.exportFeedback(publication, to: destination)
  }
  package func loadTraining(from source: URL) async throws -> FlowPortfolioTrainingInputs {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("flow-task-read-" + UUID().uuidString.lowercased(), isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
    defer { try? FileManager.default.removeItem(at: root) }
    var directory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: source.path, isDirectory: &directory) else { throw FlowPortfolioError.unavailable("Task carrier unavailable.") }
    let staged = try directory.boolValue ? DrawingExchangeCarrier.stageDirectory(source, stagingParent: root) : DrawingExchangeCarrier.stageZIP(source, stagingParent: root)
    return try FlowTrainingReader.inputs(package: ExchangeAdmission.validate(staged))
  }
}

/// This is the single task decoder for both owned and offline carriers. UUID
/// navigation and current source/geometry caches are not reachable from it.
enum FlowTrainingReader {
  static func manifest(package: ValidatedExchangePackage, budget: FlowFeatureReadBudget = .init()) throws -> FlowPortfolioTrainingManifest {
    guard let index = package.index.known, index.kind == "feedback", index.requiredFeatures.isEmpty,
      index.roots.isEmpty, index.photos.isEmpty, index.inputs.isEmpty, index.jobs.isEmpty, index.attempts.isEmpty,
      package.drawings.isEmpty, let scope = index.scope,
      scope.mediaType == "application/json", scope.encoding == "utf8-json",
      index.assets.allSatisfy({ $0.asset.mediaType == "application/json" && $0.asset.encoding == "utf8-json" }) else {
      throw FlowPortfolioError.unavailable("Unsupported feature-only training task context.")
    }
    let bytes = try FlowFeedbackReader.exactJSON(scope, package: package, budget: budget, maximumBytes: ExchangeJSON.maximumRecordBytes)
    let manifest = try JSONDecoder().decode(FlowPortfolioTrainingManifest.self, from: bytes)
    guard manifest.profile == "adaptiveplotter.flow-training-task/1", manifest.requiredFeatures.isEmpty, manifest.portfolioRevision >= 0,
      manifest.extractorVersion == FlowArtistFeatures.revision, manifest.trainerVersion == FlowArtistFitConfiguration.current.revision,
      manifest.configuration == .current, manifest.entries.count <= 5000, manifest.feedback.count <= 5000,
      Set(manifest.entries.map(\.exampleID)).count == manifest.entries.count,
      Set(manifest.feedback.map(\.judgmentID)).count == manifest.feedback.count,
      Set(manifest.curation.map(\.id)).count == manifest.curation.count,
      Set(manifest.excludedCandidateIDs).count == manifest.excludedCandidateIDs.count else {
      throw FlowPortfolioError.unavailable("Unsupported or malformed training manifest.")
    }
    if budget.batchedFiles !== package.files { try package.files.revalidateSelected() }
    return manifest
  }
  static func inputs(package: ValidatedExchangePackage, budget: FlowFeatureReadBudget = .init()) throws -> FlowPortfolioTrainingInputs {
    let previousBatch = budget.batchedFiles
    budget.batchedFiles = package.files
    defer { budget.batchedFiles = previousBatch }
    let manifest = try manifest(package: package, budget: budget)
    let exactFeatureAssets = try FlowFeedbackReader.featureAssets(package, budget: budget)
    let publication = DrawingLibraryFeedbackRef(publication: package)
    var choices: [FlowPortfolioChoice] = [], prunes: [FlowPortfolioPruneRevision] = [], ranks: [FlowPortfolioRanking] = []
    var presentations: [UUID: FlowPortfolioPresentation] = [:]
    for frozen in manifest.feedback {
      try Task.checkCancellation()
      let ref = FlowPortfolioFeedbackReference(publication: publication, assessment: frozen.assessment, ranking: frozen.ranking)
      guard let assessment = package.assessments[frozen.assessment] else { throw FlowPortfolioError.invalid("Pinned feedback missing.") }
      if let ranking = frozen.ranking {
        ranks.append(try FlowFeedbackReader.value(FlowPortfolioRanking.self, reference: ref, id: frozen.judgmentID, package: package, budget: budget))
        guard let capsule = package.rankingCapsules[ranking] else { throw FlowPortfolioError.invalid("Pinned ranking missing.") }
        let presentation = try FlowFeedbackReader.decodeJSON(ExchangeJSON.validate(capsule.originalJSON)["flowPresentation"], FlowPortfolioPresentation.self)
        if let prior = presentations[presentation.id], prior != presentation { throw FlowPortfolioError.invalid("Ranking presentation divergence.") }; presentations[presentation.id] = presentation
      } else if assessment.answerType == "adaptiveplotter.flow-choice" {
        choices.append(try FlowFeedbackReader.value(FlowPortfolioChoice.self, reference: ref, id: frozen.judgmentID, package: package, budget: budget))
      } else if assessment.answerType == "adaptiveplotter.flow-pruning" {
        prunes.append(try FlowFeedbackReader.value(FlowPortfolioPruneRevision.self, reference: ref, id: frozen.judgmentID, package: package, budget: budget))
      } else { throw FlowPortfolioError.unavailable("Unknown frozen feedback answer semantics.") }
    }
    var features: [UUID: (ExchangeAsset, FlowPortfolioFeatureCapsule)] = [:]
    for asset in exactFeatureAssets {
      let value = try FlowFeedbackReader.feature(asset, package: package, budget: budget)
      if let old = features[value.id], old.0 != asset { throw FlowPortfolioError.invalid("Frozen feature identity conflict.") }
      features[value.id] = (asset, value)
    }
    // Recompute connectivity from frozen declarations BEFORE exclusions. No
    // current Photo metadata, image decoding or source lookup occurs here.
    let groups = FlowSourceConnectivity.groups(manifest.curation.map { source in
      var keys = ["source:" + source.imageDigest]
      if let subject = source.subjectID { keys.append("subject:" + subject) }
      if let session = source.sessionID { keys.append("session:" + session) }
      return (source.id, keys)
    })
    for source in manifest.curation {
      guard FlowPortfolioValidation.validHash(source.imageDigest), source.group == groups[source.id],
        source.reason == (source.excluded ? "Operator excluded this source." : "Included by the current curation.") else { throw FlowPortfolioError.invalid("Frozen curation/connectivity proof.") }
    }
    let includedSources = Set(manifest.curation.filter { !$0.excluded }.map(\.id)), excludedCandidates = Set(manifest.excludedCandidateIDs)
    let eligibleIDs = Set(features.values.filter { includedSources.contains($0.1.sourceID) && !excludedCandidates.contains($0.1.candidateID) }.map { $0.1.id })
    let rankScopes = Dictionary(grouping: ranks, by: \.presentationID)
    for values in rankScopes.values {
      let replaced = Set(values.compactMap(\.supersedesID))
      guard values.filter({ !replaced.contains($0.id) }).count == 1 else { throw FlowPortfolioError.invalid("Divergent ranking revision scope.") }
    }
    let pruneBranches = Dictionary(grouping: prunes, by: { $0.candidateID.uuidString + ":" + ($0.parentRevisionID?.uuidString ?? "root") })
    guard pruneBranches.values.allSatisfy({ $0.count == 1 }) else { throw FlowPortfolioError.invalid("Divergent pruning revision scope.") }
    for values in Dictionary(grouping: prunes, by: \.candidateID).values {
      let parents = Set(values.compactMap(\.parentRevisionID)), heads = values.filter { !parents.contains($0.id) }
      guard heads.count == 1, let head = heads.first, manifest.selectedPruneIDs[head.candidateID] == head.id else { throw FlowPortfolioError.invalid("Frozen pruning head.") }
      var seen = Set<UUID>(), current: FlowPortfolioPruneRevision? = head
      while let value = current {
        guard seen.insert(value.id).inserted else { throw FlowPortfolioError.invalid("Pruning cycle.") }
        current = value.parentRevisionID.flatMap { parent in values.first { $0.id == parent } }
      }
      guard seen.count == values.count else { throw FlowPortfolioError.invalid("Disconnected pruning supervision.") }
    }
    let superseded = Set(ranks.compactMap(\.supersedesID)), current = ranks.filter { !superseded.contains($0.id) }
    guard Set(current.map(\.id)) == Set(manifest.selectedRankingIDs), Set(manifest.selectedRankingIDs).count == manifest.selectedRankingIDs.count else { throw FlowPortfolioError.invalid("Frozen selected ranking revisions.") }
    var rankings: [FlowArtistRanking] = []
    for rank in current where !rank.skipped && !rank.neither {
      guard let presentation = presentations[rank.presentationID] else { throw FlowPortfolioError.invalid("Pinned presentation missing.") }
      let allowed = Set(presentation.items.map(\.id)).intersection(eligibleIDs)
      let tiers = rank.orderedGroups.map { $0.filter { allowed.contains($0) } }.filter { !$0.isEmpty }
      if tiers.flatMap({ $0 }).count >= 2 { rankings.append(.init(id: rank.id.uuidString, tiers: tiers.map { $0.map(\.uuidString) }, provenance: .ranking)) }
    }
    var seenChoices = Set<String>()
    for choice in choices {
      let key = ([choice.roundID.uuidString, choice.selectedItemID.uuidString] + choice.offeredItems.map { $0.id.uuidString }.sorted()).joined(separator: "|")
      guard seenChoices.insert(key).inserted, eligibleIDs.contains(choice.selectedItemID) else { continue }
      let others = choice.offeredItems.filter { $0.id != choice.selectedItemID && eligibleIDs.contains($0.id) }.map { $0.id.uuidString }
      if !others.isEmpty { rankings.append(.init(id: choice.id.uuidString, tiers: [[choice.selectedItemID.uuidString], others], provenance: .choice)) }
    }
    guard rankings.sorted(by: { $0.id < $1.id }) == manifest.rankings.sorted(by: { $0.id < $1.id }) else { throw FlowPortfolioError.invalid("Frozen resolved rankings differ from canonical answers.") }
    let compared = Set(rankings.flatMap { $0.tiers.flatMap { $0 } })
    var labelsByCandidate: [UUID: [FlowArtistStrokeLabel]] = [:]
    for (candidateID, selectedID) in manifest.selectedPruneIDs {
      guard let selected = prunes.first(where: { $0.id == selectedID && $0.candidateID == candidateID }) else {
        // Attributed model/inherited masks are not human supervision.
        guard let feature = features[selectedID]?.1, feature.candidateID == candidateID else { continue }
        continue
      }
      guard let root = features[candidateID]?.1 else { throw FlowPortfolioError.invalid("Prune root features missing.") }
      if selected.action == .completeTarget {
        let removed = Set(selected.removedIndices)
        labelsByCandidate[candidateID] = root.strokeIDs.indices.map { .init(index: $0, removed: removed.contains($0), provenance: .completedMask) }
      } else {
        var decisions: [Int: FlowArtistStrokeLabel] = [:]
        for operation in selected.undoOperationIDs {
          guard let edit = prunes.first(where: { $0.id == operation && $0.candidateID == candidateID }), edit.action == .remove || edit.action == .restore else { throw FlowPortfolioError.invalid("Pinned pruning operation missing.") }
          for index in edit.affectedIndices { decisions[index] = .init(index: index, removed: edit.action == .remove, provenance: edit.action == .remove ? .remove : .restore) }
        }
        labelsByCandidate[candidateID] = decisions.keys.sorted().compactMap { decisions[$0] }
      }
    }
    var expectedExampleIDs = Set(compared)
    for (candidateID, labels) in labelsByCandidate where !labels.isEmpty && eligibleIDs.contains(candidateID) { expectedExampleIDs.insert(candidateID.uuidString) }
    guard Set(manifest.entries.map { $0.exampleID.uuidString }) == expectedExampleIDs else { throw FlowPortfolioError.invalid("Frozen example membership differs from supervision.") }
    var examples: [FlowArtistExample] = [], elements = 0, labelCount = 0
    let sources = Dictionary(uniqueKeysWithValues: manifest.curation.map { ($0.id, $0) })
    for entry in manifest.entries {
      try Task.checkCancellation()
      guard let root = features[entry.candidateID], let selected = features[entry.exampleID],
        root.0 == entry.rootFeatures, selected.0 == entry.features, root.1.id == root.1.candidateID, root.1.removedIndices.isEmpty,
        selected.1.candidateID == entry.candidateID, root.1.sourceID == entry.sourceID, selected.1.sourceID == entry.sourceID,
        selected.1.programDigest == root.1.programDigest, (selected.1.rootFeatures == entry.rootFeatures || entry.includeRoot), selected.1.strokeIDs == root.1.strokeIDs, selected.1.strokes == root.1.strokes,
        entry.recipe == root.1.recipe, entry.recipe == selected.1.recipe, selected.1.removedIndices == entry.removedIndices,
        sources[entry.sourceID]?.group == entry.group, eligibleIDs.contains(entry.exampleID),
        entry.includeRoot == (entry.exampleID == entry.candidateID),
        entry.labels == (entry.includeRoot ? labelsByCandidate[entry.candidateID] ?? [] : []) else {
        throw FlowPortfolioError.invalid("Frozen training entry differs from exact feature/label basis.")
      }
      elements += root.1.strokes.count * FlowArtistFeatures.strokeCount + FlowArtistFeatures.drawingCount; labelCount += entry.labels.count
      guard FlowArtistTrainingLimits.accepts(featureValueCount: elements, explicitLabelCount: labelCount) else { throw FlowPortfolioError.unavailable("Frozen training allocation budget exceeded.") }
      examples.append(.init(id: entry.exampleID.uuidString, sourceGroupID: entry.group, recipe: entry.recipe,
        features: selected.1.drawing, strokeFeatures: root.1.strokes, strokeLabels: entry.labels,
        baseDrawingID: entry.candidateID.uuidString, removedIndices: entry.removedIndices))
    }
    guard manifest.holdoutGroupIDs == FlowArtistTraining.holdoutGroups(examples.map(\.sourceGroupID), seed: manifest.seed) else { throw FlowPortfolioError.invalid("Frozen partition differs from exact groups/seed.") }
    try package.files.revalidateSelected()
    return .init(examples: examples, rankings: manifest.rankings, seed: manifest.seed, configuration: manifest.configuration, holdoutGroupIDs: manifest.holdoutGroupIDs)
  }
}
