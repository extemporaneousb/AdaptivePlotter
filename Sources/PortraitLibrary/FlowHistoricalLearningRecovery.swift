import Foundation
import DrawingLibrary
import PortraitArtists
import PortraitCore
import PlotterModel

/// Offline, explicit personal recovery. Neither app reads the retired journal.
/// Original bytes and prior fit artifacts remain inspectable by domain kind.
package enum FlowHistoricalLearningRecovery {
  struct Blob: Decodable { let path: String; let sha256: ExchangeDigest
    func read() throws -> Data {
      let bytes = try Data(contentsOf: URL(fileURLWithPath: path), options: .mappedIfSafe)
      guard bytes.count <= 128 * 1024 * 1024, ExchangeDigest.hash(bytes) == sha256 else { throw FlowPortfolioError.invalid("Historical artifact digest/size mismatch.") }
      return bytes
    }
  }
  struct Plan: Decodable {
    struct Head: Decodable { let recordSHA256: ExchangeDigest }
    let profile: String
    let head: Head
    let snapshot: FlowPortfolioSnapshot
    let artifacts: [Blob]
    let candidates: [FlowHistoricalCandidate]
    let counts: [String: Int]
  }
  package struct Receipt: Codable, Sendable {
    package let profile: String
    package let archiveID: UUID
    package let archiveHead: ExchangeDigest
    package let counts: [String: Int]
    package let trainingSnapshotID: UUID
    package let examples: Int
    package let rankings: Int
    package let explicitStrokeLabels: Int
    package let fitID: UUID
    package let fitSummary: String
    package let checkpointProduced: Bool
    package let modelActivated: Bool
    package let alreadyRecovered: Bool
  }
  package static func snapshotID(archiveID: UUID, head: ExchangeDigest) -> UUID {
    let hash = ExchangeDigest.hash(Data(("adaptiveplotter.flow-recovery-task/1/" + archiveID.uuidString.lowercased() + "/" + head.description).utf8)).description
    let bytes = Array(hash.prefix(32))
    let text = [String(bytes[0..<8]), String(bytes[8..<12]), String(bytes[12..<16]), String(bytes[16..<20]), String(bytes[20..<32])].joined(separator: "-")
    return UUID(uuidString: text)!
  }
  package static func recover(planURL: URL, library: DrawingLibrary) async throws -> Receipt {
    let selected = library.directoryURL.standardizedFileURL.resolvingSymlinksInPath().path
    let applicationSupport = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support").path
    guard !["PortraitStudio", "AdaptivePlotter"].contains(where: { selected.hasPrefix(applicationSupport + "/" + $0 + "/") }) else {
      throw FlowPortfolioError.invalid("Recovery requires an offline Library copy; live application catalogs are refused.")
    }
    let raw = try Data(contentsOf: planURL), plan = try JSONDecoder().decode(Plan.self, from: raw)
    guard plan.profile == "adaptiveplotter.personal-flow-recovery/1", plan.artifacts.count <= 10_000,
      plan.candidates.count <= 5000 else { throw FlowPortfolioError.invalid("Unsupported personal recovery plan.") }
    try FlowPortfolioValidation.validate(plan.snapshot)
    let marker = DrawingLibraryRecordKey(kind: "adaptiveplotter.flow-historical-recovery/1", id: plan.snapshot.id)
    if let prior = try await library.record(marker) {
      let receipt = try JSONDecoder().decode(Receipt.self, from: prior.payload)
      guard receipt.counts == plan.counts, receipt.archiveID == plan.snapshot.id, receipt.archiveHead == plan.head.recordSHA256,
        receipt.trainingSnapshotID == snapshotID(archiveID: receipt.archiveID, head: receipt.archiveHead) else {
        throw FlowPortfolioError.conflict("This archive identity was already recovered from a different head.")
      }
      let cold = FlowPortfolioStore(directory: library.directoryURL, library: library)
      try await cold.loadRecords()
      _ = try await cold.trainingDocument(snapshotID: receipt.trainingSnapshotID)
      let inputs = try await cold.trainingInputs(snapshotID: receipt.trainingSnapshotID)
      let current = await cold.snapshot()
      guard let fit = current.fits.first(where: { $0.id == receipt.fitID && $0.snapshotID == receipt.trainingSnapshotID }),
        inputs.examples.count == receipt.examples, inputs.rankings.count == receipt.rankings,
        inputs.examples.reduce(0, { $0 + $1.strokeLabels.count }) == receipt.explicitStrokeLabels else {
        throw FlowPortfolioError.conflict("Recovered task or fit no longer matches its completion receipt.")
      }
      let report = try JSONDecoder().decode(FlowArtistFitReport.self, from: await cold.fitReportData(fitID: fit.id))
      let checkpoint: FlowArtistCheckpoint?
      if fit.hasCheckpoint { checkpoint = try JSONDecoder().decode(FlowArtistCheckpoint.self, from: await cold.checkpointData(fitID: fit.id)) }
      else { checkpoint = nil }
      guard report.summary == receipt.fitSummary, report.checkpoint == checkpoint, (checkpoint != nil) == receipt.checkpointProduced else {
        throw FlowPortfolioError.conflict("Recovered report/checkpoint differs from its completion receipt.")
      }
      if let checkpoint {
        try checkpoint.validateArchive()
        guard Set(checkpoint.exampleIDs) == Set(inputs.examples.map(\.id)), Set(checkpoint.rankingIDs) == Set(inputs.rankings.map(\.id)),
          checkpoint.seed == inputs.seed, checkpoint.fitConfiguration == inputs.configuration, checkpoint.holdoutGroupIDs == inputs.holdoutGroupIDs,
          checkpoint.sourceGroupIDs == Set(inputs.examples.map(\.sourceGroupID)).sorted() else {
          throw FlowPortfolioError.conflict("Recovered checkpoint no longer matches its exact frozen inputs.")
        }
      }
      return .init(profile: receipt.profile, archiveID: receipt.archiveID, archiveHead: receipt.archiveHead, counts: receipt.counts,
        trainingSnapshotID: receipt.trainingSnapshotID, examples: receipt.examples, rankings: receipt.rankings,
        explicitStrokeLabels: receipt.explicitStrokeLabels, fitID: receipt.fitID, fitSummary: receipt.fitSummary,
        checkpointProduced: receipt.checkpointProduced, modelActivated: current.activeFitID == fit.id, alreadyRecovered: true)
    }
    let store = FlowPortfolioStore(directory: library.directoryURL, library: library)
    try await store.loadRecords()
    return try await store.recoverHistorical(plan: plan, raw: raw, marker: marker)
  }

  /// Recreates original archive bytes from the preserved CAS without requiring
  /// the old journal reader or the original filesystem paths to remain present.
  package static func exportArchive(id: UUID, library: DrawingLibrary, to output: URL) async throws {
    guard !FileManager.default.fileExists(atPath: output.path),
      let row = try await library.record(.init(kind: "adaptiveplotter.flow-historical-archive/1", id: id)),
      let digest = try ExchangeJSON.validate(row.payload)["plan"] as? String else { throw FlowPortfolioError.invalid("Historical archive unavailable or export destination exists.") }
    let raw = try await library.asset(ExchangeDigest(digest), maximumBytes: 16 * 1024 * 1024)
    let plan = try JSONDecoder().decode(Plan.self, from: raw)
    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
    do {
      for blob in plan.artifacts {
        let original = URL(fileURLWithPath: blob.path), name = original.lastPathComponent
        let relative: String
        if name == "portfolio.json" { relative = name }
        else {
          let folder = original.deletingLastPathComponent().lastPathComponent
          guard ["objects", "records"].contains(folder), name == blob.sha256.description else { throw FlowPortfolioError.invalid("Historical archive path mismatch.") }
          relative = folder + "/" + name
        }
        let target = output.appendingPathComponent(relative)
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try await library.asset(blob.sha256, maximumBytes: 128 * 1024 * 1024).write(to: target, options: .atomic)
      }
      // The historical administrative lock had no data and grants no current
      // authority. All 4,879 data files above retain their original exact bytes.
      try Data().write(to: output.appendingPathComponent("writer.lock"), options: .atomic)
    } catch { try? FileManager.default.removeItem(at: output); throw error }
  }
}

struct FlowHistoricalCandidate: Codable {
  let id: UUID
  let program: FlowPortfolioBlob
  let raster: FlowPortfolioBlob
  let preview: FlowPortfolioBlob
}

extension FlowPortfolioStore {
  func historicalCandidate(_ id: UUID) async throws -> FlowHistoricalCandidate? {
    guard let row = try await library.record(.init(kind: "adaptiveplotter.flow-historical-candidate/1", id: id)) else { return nil }
    let value = try JSONDecoder().decode(FlowHistoricalCandidate.self, from: row.payload)
    guard value.id == id else { throw FlowPortfolioError.invalid("Historical candidate identity mismatch.") }
    return value
  }
  func historicalBytes(_ blob: FlowPortfolioBlob) async throws -> Data {
    let bytes = try await library.asset(ExchangeDigest(blob.sha256), maximumBytes: 128 * 1024 * 1024)
    guard bytes.count == blob.byteCount else { throw FlowPortfolioError.invalid("Historical artifact length mismatch.") }
    return bytes
  }
  func historicalDrawing(_ id: UUID) async throws -> Drawing? {
    guard let archived = try await historicalCandidate(id), let candidate = state.candidates.first(where: { $0.id == id }) else { return nil }
    let program = try JSONDecoder().decode(DrawingProgram.self, from: await historicalBytes(archived.program))
    guard program.contentHash.description == candidate.programHash, program.strokes.count == candidate.strokeCount else { throw FlowPortfolioError.invalid("Historical program differs from its recorded candidate.") }
    let receipt: [String: Any] = ["profile": "adaptiveplotter.recovered-flow-producer/1", "candidateID": id.uuidString.lowercased(),
      "originalProgramSHA256": archived.program.sha256, "recordedProgramHash": candidate.programHash,
      "limitations": "Original bytes verified. Features extracted during explicit recovery with the current extractor; original native producer capability is unverified."]
    return try Drawing(program: program, input: .unavailable(reason: "Historical preparation mapping was not recorded", knownRef: nil),
      parent: .unavailable(reason: "Historical ancestry remains in the recovered domain graph", knownRef: nil),
      producer: .init(id: "adaptiveplotter.recovered-flow", version: "1", recordJSON: JSONSerialization.data(withJSONObject: receipt, options: [.sortedKeys, .withoutEscapingSlashes])))
  }

  func recoverHistorical(plan: FlowHistoricalLearningRecovery.Plan, raw: Data, marker: DrawingLibraryRecordKey) async throws -> FlowHistoricalLearningRecovery.Receipt {
    let original = state
    func merge<T: Codable & Equatable & Identifiable>(_ old: [T], _ added: [T]) throws -> [T] {
      let previous = Dictionary(uniqueKeysWithValues: old.map { ($0.id, $0) })
      for value in added {
        if let existing = previous[value.id], existing != value {
          var before = try ExchangeJSON.validate(DrawingArtifactCoding.encoder().encode(existing))
          let incoming = try ExchangeJSON.validate(DrawingArtifactCoding.encoder().encode(value))
          // A previous interrupted recovery may already have committed exact
          // canonical feedback/retention refs. Missing historical pointers do
          // not replace those admitted current refs on a retry.
          for field in ["feedback", "drawing"] where incoming[field] == nil { before.removeValue(forKey: field) }
          if T.self == FlowPortfolioSource.self {
            for field in ["title", "subjectID", "sessionID", "excluded"] { before.removeValue(forKey: field) }
            var neutral = incoming
            for field in ["title", "subjectID", "sessionID", "excluded"] { neutral.removeValue(forKey: field) }
            guard NSDictionary(dictionary: before).isEqual(to: neutral) else { throw FlowPortfolioError.conflict("Divergent historical source identity: \(value.id)") }
          } else {
            guard NSDictionary(dictionary: before).isEqual(to: incoming) else { throw FlowPortfolioError.conflict("Divergent historical domain identity: \(value.id)") }
          }
        }
      }
      return old + added.filter { previous[$0.id] == nil }
    }
    // Preserve every original object and journal record as ordinary exact CAS
    // assets, with an inspectable inventory, in bounded independent publications.
    var pending: [DrawingLibraryClosureAsset] = [], digests: [ExchangeDigest] = [], byteCount = 0
    func descriptor(_ bytes: Data) throws -> DrawingLibraryClosureAsset {
      .init(descriptor: .init(asset: try ExchangeAsset(bytes: bytes, mediaType: "application/octet-stream", encoding: "opaque")), bytes: bytes)
    }
    for blob in plan.artifacts {
      let bytes = try blob.read()
      if byteCount + bytes.count > 64 * 1024 * 1024 || pending.count >= 64 {
        try await library.commitRecords([], assets: pending); pending = []; byteCount = 0
      }
      pending.append(try descriptor(bytes)); digests.append(blob.sha256); byteCount += bytes.count
    }
    if !pending.isEmpty { try await library.commitRecords([], assets: pending) }
    let archiveAsset = try descriptor(raw)
    let archiveRecord = DrawingLibraryRecord(kind: "adaptiveplotter.flow-historical-archive/1", id: plan.snapshot.id,
      payload: try JSONSerialization.data(withJSONObject: ["profile": "adaptiveplotter.flow-historical-archive/1",
        "plan": archiveAsset.descriptor.asset.object.description, "counts": plan.counts,
        "limitations": "Historical fits/checkpoints are preserved with their exact original training documents and are not activated as current models."], options: [.sortedKeys]),
      assets: Array(Set(digests + [archiveAsset.descriptor.asset.object])))
    try await library.commitRecords([archiveRecord], assets: [archiveAsset])
    for batchStart in stride(from: 0, to: plan.candidates.count, by: 100) {
      let records = try plan.candidates[batchStart..<min(batchStart + 100, plan.candidates.count)].map { candidate in
        DrawingLibraryRecord(kind: "adaptiveplotter.flow-historical-candidate/1", id: candidate.id,
          payload: try DrawingArtifactCoding.encoder().encode(candidate), assets: try [candidate.program, candidate.raster, candidate.preview].map { try ExchangeDigest($0.sha256) })
      }
      for record in records { if let old = try await library.record(record.key), old.payload != record.payload || old.assets != record.assets { throw FlowPortfolioError.conflict("Divergent recovered candidate identity.") } }
      try await library.commitRecords(records)
    }
    var imported = plan.snapshot
    for index in imported.sources.indices {
      if let ref = imported.sources[index].photo {
        let exact = try await library.photo(ref), source = imported.sources[index]
        guard exact.record.original.object.description == source.image.sha256,
          exact.record.original.byteLength == UInt64(source.image.byteCount), exact.record.original.mediaType == source.image.mediaType else {
          throw FlowPortfolioError.invalid("Mapped historical Photo differs from its original encoded source.")
        }
      }
      else {
        let source = imported.sources[index], bytes = try await historicalBytes(source.image)
        let photo = try PortraitDrawingImages.photo(data: bytes, issuer: imported.id, captureID: source.id,
          capturedAt: source.captureProvenance?.capturedAt, importedAt: source.createdAt,
          facts: DrawingArtifactCoding.encoder().encode(source))
        try await library.commitRecords([], closure: .init(photo: photo), photoMetadata: [.init(reference: photo.reference,
          patch: .init(title: .set(source.title), subjectID: .set(source.subjectID), sessionID: .set(source.sessionID), excluded: source.excluded))])
        imported.sources[index].photo = photo.reference
      }
    }
    var next = original
    next.sources = try merge(original.sources, imported.sources)
    next.rounds = try merge(original.rounds, imported.rounds)
    next.candidates = try merge(original.candidates, imported.candidates)
    next.choices = try merge(original.choices, imported.choices)
    next.pruneRevisions = try merge(original.pruneRevisions, imported.pruneRevisions)
    next.presentations = try merge(original.presentations, imported.presentations)
    next.rankings = try merge(original.rankings, imported.rankings)
    // Feature capture resolves the full recovered graph. No partially recovered
    // session is committed until all original human answers have canonical refs.
    state = next
    storage.markPublished(imported.sources.map(\.image))
    var all = next
    let choices = next.choices.filter { $0.feedback == nil }, prunes = next.pruneRevisions.filter { $0.feedback == nil }
    let ranks = next.rankings.filter { $0.feedback == nil }
    enum Answer { case choice(FlowPortfolioChoice), prune(FlowPortfolioPruneRevision), rank(FlowPortfolioRanking) }
    let answers = choices.map(Answer.choice) + prunes.filter { $0.action != .modelProposal && $0.action != .inheritedSelection }.map(Answer.prune) + ranks.map(Answer.rank)
    var batches: [[Answer]] = []
    var group: [Answer] = []
    for answer in answers {
      if case .rank = answer {
        if !group.isEmpty { batches.append(group); group = [] }
        batches.append([answer])
      } else {
        group.append(answer)
        if group.count == 8 { batches.append(group); group = [] }
      }
    }
    if !group.isEmpty { batches.append(group) }
    for answers in batches {
      var batch = all
      batch.choices = []; batch.pruneRevisions = []; batch.rankings = all.rankings.filter { $0.feedback != nil }
      for answer in answers {
        switch answer { case .choice(let v): batch.choices.append(v); case .prune(let v): batch.pruneRevisions.append(v); case .rank(let v): batch.rankings.append(v) }
      }
      if let prepared = try await prepareFeedback(next: &batch) {
        var featureRows: [DrawingLibraryRecord] = []
        for capsule in featureCapsules.values where !committedRecords.contains(.init(kind: kind("features"), id: capsule.id)) {
          featureRows.append(.init(kind: kind("features"), id: capsule.id, payload: try DrawingArtifactCoding.encoder().encode(
            FlowLibraryEntity(profile: kind("features"), ordinal: 0, value: FlowPortfolioFeatureLocator(id: capsule.id, candidateID: capsule.candidateID, asset: capsule.asset))), assets: [try capsule.asset.object]))
        }
        for preview in previewArtifacts.values where !committedRecords.contains(.init(kind: kind("preview"), id: preview.id)) {
          featureRows.append(.init(kind: kind("preview"), id: preview.id, payload: try DrawingArtifactCoding.encoder().encode(
            FlowLibraryEntity(profile: kind("preview"), ordinal: 0, value: preview)), assets: [try ExchangeDigest(preview.image.sha256)]))
        }
        _ = try await library.commitFeedback(prepared.package, records: featureRows)
        try? FileManager.default.removeItem(at: prepared.temporaryRoot)
        for row in featureRows { committedRecords.insert(row.key) }
        for v in batch.choices { if let i = all.choices.firstIndex(where: { $0.id == v.id }) { all.choices[i] = v } }
        for v in batch.pruneRevisions { if let i = all.pruneRevisions.firstIndex(where: { $0.id == v.id }) { all.pruneRevisions[i] = v } }
        for v in batch.rankings { if let i = all.rankings.firstIndex(where: { $0.id == v.id }) { all.rankings[i] = v } }
        trimTransientCaches()
      }
    }
    state = original
    all.revision = original.revision + 1
    try FlowPortfolioValidation.validate(all)
    let graph = try graphRecords(all)
    try await library.commitRecords(graph)
    state = all
    try await loadRecords()
    let taskID = FlowHistoricalLearningRecovery.snapshotID(archiveID: imported.id, head: plan.head.recordSHA256)
    if state.trainingSnapshots.contains(where: { $0.id == taskID }) {
      let retained = try await trainingDocument(snapshotID: taskID)
      func feedbackProof(_ value: FlowPortfolioSnapshot) throws -> Data {
        var rows: [FlowFrozenFeedback] = []
        func add(_ id: UUID, _ reference: FlowPortfolioFeedbackReference?) throws {
          guard let reference else { throw FlowPortfolioError.conflict("Recovery task has missing canonical feedback.") }
          rows.append(.init(judgmentID: id, assessment: reference.assessment, ranking: reference.ranking))
        }
        for choice in value.choices { try add(choice.id, choice.feedback) }
        for prune in value.pruneRevisions where prune.action != .inheritedSelection && prune.action != .modelProposal { try add(prune.id, prune.feedback) }
        for ranking in value.rankings { try add(ranking.id, ranking.feedback) }
        return try DrawingArtifactCoding.encoder().encode(rows.sorted { $0.judgmentID.uuidString < $1.judgmentID.uuidString })
      }
      guard FlowPortfolioSupervision.Signature(FlowPortfolioSupervision.plan(retained)) == FlowPortfolioSupervision.Signature(FlowPortfolioSupervision.plan(state)),
        try feedbackProof(retained) == feedbackProof(state) else {
        throw FlowPortfolioError.conflict("The recovery task for this archive head already has different frozen supervision.")
      }
    }
    let frozen = try await freezeTrainingSnapshot(id: taskID)
    let inputs = try await trainingInputs(snapshotID: frozen.id)
    let report: FlowArtistFitReport, fit: FlowPortfolioFit
    if let previous = state.fits.first(where: { $0.snapshotID == frozen.id }) {
      let reportBytes = try await fitReportData(fitID: previous.id)
      let checkpointBytes: Data?
      if let archived = previous.checkpoint { checkpointBytes = try await historicalBytes(archived) }
      else { checkpointBytes = nil }
      report = try JSONDecoder().decode(FlowArtistFitReport.self, from: reportBytes)
      let checkpoint = try checkpointBytes.map { try JSONDecoder().decode(FlowArtistCheckpoint.self, from: $0) }
      guard report.checkpoint == checkpoint else { throw FlowPortfolioError.conflict("Retained recovery fit differs from its report.") }
      if let checkpoint {
        try checkpoint.validateArchive()
        guard Set(checkpoint.exampleIDs) == Set(inputs.examples.map(\.id)), Set(checkpoint.rankingIDs) == Set(inputs.rankings.map(\.id)),
          checkpoint.seed == inputs.seed, checkpoint.fitConfiguration == inputs.configuration, checkpoint.holdoutGroupIDs == inputs.holdoutGroupIDs,
          checkpoint.sourceGroupIDs == Set(inputs.examples.map(\.sourceGroupID)).sorted() else {
          throw FlowPortfolioError.conflict("Retained recovery fit differs from its exact frozen inputs.")
        }
      }
      fit = try await installFit(checkpoint: checkpointBytes, report: reportBytes, snapshotID: frozen.id)
    } else {
      report = FlowArtistTraining.fit(examples: inputs.examples, rankings: inputs.rankings,
        seed: inputs.seed, configuration: inputs.configuration, frozenHoldoutGroupIDs: inputs.holdoutGroupIDs)
      fit = try await installFit(checkpoint: report.checkpoint.map { try DrawingArtifactCoding.encoder().encode($0) },
        report: DrawingArtifactCoding.encoder().encode(report), snapshotID: frozen.id)
    }
    try await reloadCommittedState()
    let reopened = try await trainingInputs(snapshotID: frozen.id)
    guard reopened.examples.count == inputs.examples.count, reopened.rankings == inputs.rankings else { throw FlowPortfolioError.invalid("Recovered training task changed after reopen.") }
    let receipt = FlowHistoricalLearningRecovery.Receipt(profile: "adaptiveplotter.personal-flow-recovery-receipt/1",
      archiveID: imported.id, archiveHead: plan.head.recordSHA256, counts: plan.counts, trainingSnapshotID: frozen.id,
      examples: inputs.examples.count, rankings: inputs.rankings.count,
      explicitStrokeLabels: inputs.examples.reduce(0) { $0 + $1.strokeLabels.count }, fitID: fit.id,
      fitSummary: report.summary, checkpointProduced: report.checkpoint != nil,
      modelActivated: state.activeFitID == fit.id, alreadyRecovered: false)
    try await library.commitRecords([.init(kind: marker.kind, id: marker.id, payload: DrawingArtifactCoding.encoder().encode(receipt))])
    return receipt
  }
}
