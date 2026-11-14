import Foundation
import DrawingLibrary
import PortraitCore
import PortraitArtists
import PlotterModel

/// Frozen learning inputs survive a rank without retaining the compared geometry.
package struct FlowPortfolioFeatureProvenance: Codable, Equatable, Sendable {
  package let id: String
  package let version: String
  package let record: ExchangeAsset
  /// Records only the capability actually observed at extraction time.
  package let nativeVerified: Bool
}
package struct FlowPortfolioFeatureCapsule: Codable, Sendable {
  package let profile: String
  package let id: UUID
  package let candidateID: UUID
  package let sourceID: UUID
  package let programDigest: ExchangeDigest
  package let rootFeatures: ExchangeAsset?
  package let strokeIDs: [StrokeID]
  package let recipe: FlowArtistRecipe
  package let producer: FlowPortfolioFeatureProvenance
  package let extractor: FlowPortfolioFeatureProvenance
  package let drawing: [Double]
  package var strokes: [[Double]]
  package let removedIndices: [Int]
  package var requiredFeatures: [String] = []
  package var asset: ExchangeAsset { get throws { try ExchangeAsset(bytes: DrawingArtifactCoding.encoder().encode(self), mediaType: "application/json", encoding: "utf8-json") } }
}
package struct FlowPortfolioFeatureLocator: Codable, Sendable {
  package let id: UUID
  package let candidateID: UUID
  package let asset: ExchangeAsset
}

package struct FlowPortfolioPreviewArtifact: Codable, Sendable {
  package let id: UUID
  package let image: FlowPortfolioBlob
}

struct FlowLibraryEntity<Value: Codable>: Codable {
  let profile: String
  let ordinal: Int
  let value: Value
}
struct FlowPendingGraphWrite: Sendable {
  let next: FlowPortfolioSnapshot
  let records: [DrawingLibraryRecord]
  let assets: [DrawingLibraryClosureAsset]
  let closure: DrawingLibraryRetainedClosure
  let publishedBlobs: [FlowPortfolioBlob]
  let intent: DrawingLibraryCommitIntent
  let photoMetadata: [DrawingLibraryPhotoMetadataUpdate]
  let feedback: FlowPreparedFeedback?
}

private struct FlowPortfolioSession: Codable {
  let profile: String
  let purpose: FlowPortfolioPurpose
  let id: UUID
  let createdAt: Date
  let revision: Int
  let selectedSourceID: UUID?
  let currentRoundID: UUID?
  let currentCandidateID: UUID?
  let currentPruneRevisionID: UUID?
  let activeFitID: UUID?
  let currentPresentationID: UUID?
  init(_ value: FlowPortfolioSnapshot) {
    profile = "adaptiveplotter.flow-session/2"; purpose = value.purpose
    id = value.id; createdAt = value.createdAt; revision = value.revision
    selectedSourceID = value.selectedSourceID; currentRoundID = value.currentRoundID
    currentCandidateID = value.currentCandidateID; currentPruneRevisionID = value.currentPruneRevisionID
    activeFitID = value.activeFitID; currentPresentationID = value.currentPresentationID
  }
}

extension FlowPortfolioStore {
  func kind(_ name: String) -> String { "adaptiveplotter.flow-" + name + "/2" }
  private func rows<T: Codable>(_ type: T.Type, _ name: String) async throws -> [T] {
    let rows = try await storage.library.records(kind: kind(name))
    for row in rows { committedRecords.insert(row.key) }
    let values = try rows.map { row -> FlowLibraryEntity<T> in
      let value = try JSONDecoder().decode(FlowLibraryEntity<T>.self, from: row.payload)
      guard value.profile == kind(name), value.ordinal >= 0 else { throw FlowPortfolioError.invalid("Unsupported Library entity profile or order.") }
      return value
    }
    guard Set(values.map(\.ordinal)).count == values.count else { throw FlowPortfolioError.invalid("Duplicate Library entity order.") }
    return values.sorted { $0.ordinal < $1.ordinal }.map(\.value)
  }
  /// The opt-out is a diagnostic parity path through the original full numeric
  /// decoder. It changes no admission or validation rules and is never persisted.
  package func loadRecords(reusingEncodedStrokeBasis: Bool = true) async throws {
    try await storage.library.open()
    try history.open()
    let sessions = try await rows(FlowPortfolioSession.self, "session")
    guard sessions.count <= 1 else { throw FlowPortfolioError.invalid("Multiple Flow sessions in one Library.") }
    guard let header = sessions.first else { return }
    guard requestedPurpose == nil || requestedPurpose == header.purpose else { throw FlowPortfolioError.invalid("The Library purpose differs from this session.") }
    guard header.profile == "adaptiveplotter.flow-session/2" else { throw FlowPortfolioError.invalid("Unsupported Flow session.") }
    let feedbackBudget = FlowFeatureReadBudget(reusesEncodedStrokeBasis: reusingEncodedStrokeBasis)
    var next = FlowPortfolioSnapshot.empty(purpose: header.purpose)
    next = FlowPortfolioSnapshot(schemaVersion: 2, purpose: header.purpose, id: header.id,
      createdAt: header.createdAt, revision: header.revision,
      sources: try await rows(FlowPortfolioSource.self, "source"),
      rounds: try await rows(FlowPortfolioRound.self, "round"),
      candidates: try await rows(FlowPortfolioCandidate.self, "candidate"),
      choices: try await feedbackRows(FlowPortfolioChoice.self, name: "choice", budget: feedbackBudget),
      pruneRevisions: try await feedbackRows(FlowPortfolioPruneRevision.self, name: "prune", budget: feedbackBudget),
      presentations: try await rows(FlowPortfolioPresentation.self, "presentation"),
      rankings: try await feedbackRows(FlowPortfolioRanking.self, name: "ranking", budget: feedbackBudget),
      trainingSnapshots: try await rows(FlowPortfolioTrainingSnapshot.self, "training"),
      fits: try await rows(FlowPortfolioFit.self, "fit"),
      activations: try await rows(FlowPortfolioActivation.self, "activation"),
      selectedSourceID: header.selectedSourceID, currentRoundID: header.currentRoundID,
      currentCandidateID: header.currentCandidateID, currentPruneRevisionID: header.currentPruneRevisionID,
      activeFitID: header.activeFitID, currentPresentationID: header.currentPresentationID)
    try FlowPortfolioValidation.validate(next)
    lastFeedbackReadStatistics = feedbackBudget.statistics
    publishedPhotoIDs.formUnion(next.sources.map(\.id))
    storage.markPublished(durableAssets(next, includingLocalPreviews: false))
    state = next
    try await refreshPhotoMetadata()
  }

  func durableAssets(_ next: FlowPortfolioSnapshot, includingLocalPreviews: Bool = true) -> [FlowPortfolioBlob] {
    var blobs = next.sources.map(\.image) + next.sources.compactMap { $0.importProvenance?.manifest }
    for candidate in next.candidates where candidate.drawing != nil { blobs.append(contentsOf: [candidate.raster, candidate.preview]) }
    if includingLocalPreviews { blobs += previewArtifacts.values.map { $0.image } }
    for fit in next.fits { blobs.append(fit.report); if let checkpoint = fit.checkpoint { blobs.append(checkpoint) } }
    return blobs
  }

  func graphRecords(_ next: FlowPortfolioSnapshot, includingPreviews: Bool = true) throws -> [DrawingLibraryRecord] {
    var records: [DrawingLibraryRecord] = []
    func add<T: Codable & Equatable & Identifiable>(_ values: [T], previous: [T], _ name: String,
      refs: (T) -> [DrawingRef] = { _ in [] }, photos: (T) -> [PhotoRef] = { _ in [] }, assets: (T) -> [FlowPortfolioBlob] = { _ in [] }) throws where T.ID == UUID {
      let prior = Dictionary(uniqueKeysWithValues: previous.map { ($0.id, $0) })
      for (ordinal, value) in values.enumerated() where prior[value.id] != value {
        let bytes = try DrawingArtifactCoding.encoder().encode(FlowLibraryEntity(profile: kind(name), ordinal: ordinal, value: value))
        records.append(.init(kind: kind(name), id: value.id, payload: bytes, drawings: refs(value), photos: photos(value),
          assets: try assets(value).map { try ExchangeDigest($0.sha256) }))
      }
    }
    records.append(.init(kind: kind("session"), id: next.id, payload: try DrawingArtifactCoding.encoder().encode(FlowLibraryEntity(profile: kind("session"), ordinal: 0, value: FlowPortfolioSession(next)))))
    try add(next.sources, previous: state.sources, "source", photos: { $0.photo.map { [$0] } ?? [] }, assets: { [$0.image] + ($0.importProvenance.map { [$0.manifest] } ?? []) })
    try add(next.rounds, previous: state.rounds, "round")
    try add(next.candidates, previous: state.candidates, "candidate", refs: { $0.drawing.map { [$0] } ?? [] },
      assets: { value in
        guard let location = value.authoringClosureLocation, let manifest = value.authoringClosure else { return [] }
        return [manifest] + location.parts
      })
    func feedbackNavigation<T: Codable & Equatable & Identifiable>(_ values: [T], previous: [T], _ name: String,
      pointer: (T) -> FlowPortfolioFeedbackReference?, drawing: (T) -> DrawingRef? = { _ in nil }) throws where T.ID == UUID {
      let prior = Dictionary(uniqueKeysWithValues: previous.map { ($0.id, $0) })
      for (ordinal, value) in values.enumerated() where prior[value.id] != value {
        let payload: Data
        if let exact = pointer(value) {
          payload = try DrawingArtifactCoding.encoder().encode(FlowLibraryEntity(profile: kind(name), ordinal: ordinal,
            value: FlowFeedbackNavigation(id: value.id, feedback: exact, drawing: drawing(value))))
        } else {
          // Nonhuman model proposals/inherited masks remain attributed navigation,
          // never interpreted as an independent human assessment.
          guard name == "prune" else { throw FlowPortfolioError.invalid("Human feedback must have an exact canonical reference.") }
          payload = try DrawingArtifactCoding.encoder().encode(FlowLibraryEntity(profile: kind(name), ordinal: ordinal, value: value))
        }
        records.append(.init(kind: kind(name), id: value.id, payload: payload, drawings: drawing(value).map { [$0] } ?? []))
      }
    }
    try feedbackNavigation(next.choices, previous: state.choices, "choice", pointer: { $0.feedback })
    try feedbackNavigation(next.pruneRevisions, previous: state.pruneRevisions, "prune", pointer: { $0.feedback }, drawing: { $0.drawing })
    try add(next.presentations, previous: state.presentations, "presentation")
    try feedbackNavigation(next.rankings, previous: state.rankings, "ranking", pointer: { $0.feedback })
    try add(next.trainingSnapshots, previous: state.trainingSnapshots, "training")
    for (id, bytes) in frozenTrainingViews where !committedRecords.contains(.init(kind: kind("frozen-view"), id: id)) {
      records.append(.init(kind: kind("frozen-view"), id: id, payload: bytes))
    }
    try add(next.fits, previous: state.fits, "fit", assets: { [$0.report] + ($0.checkpoint.map { [$0] } ?? []) })
    try add(next.activations, previous: state.activations, "activation")
    for capsule in featureCapsules.values where !committedRecords.contains(.init(kind: kind("features"), id: capsule.id)) {
      records.append(.init(kind: kind("features"), id: capsule.id, payload: try DrawingArtifactCoding.encoder().encode(FlowLibraryEntity(profile: kind("features"), ordinal: 0, value: FlowPortfolioFeatureLocator(id: capsule.id, candidateID: capsule.candidateID, asset: try capsule.asset))), assets: [try capsule.asset.object]))
    }
    for preview in previewArtifacts.values where includingPreviews && !committedRecords.contains(.init(kind: kind("preview"), id: preview.id)) {
      records.append(.init(kind: kind("preview"), id: preview.id,
        payload: try DrawingArtifactCoding.encoder().encode(FlowLibraryEntity(profile: kind("preview"), ordinal: 0, value: preview)),
        assets: [try ExchangeDigest(preview.image.sha256)]))
    }
    return records
  }
  func publishRecords(_ next: FlowPortfolioSnapshot, photoMetadata: [DrawingLibraryPhotoMetadataUpdate] = [], feedbackOverride: FlowPreparedFeedback? = nil, additionalAssets: [DrawingLibraryClosureAsset] = []) async throws -> FlowPortfolioSnapshot {
    guard !writeAdmissionActive, pendingGraphWrite == nil, pendingRetainedWrite == nil else { throw FlowPortfolioError.conflict("Recover the pending Library action before accepting another action.") }
    writeAdmissionActive = true; defer { writeAdmissionActive = false }
    var next = next
    let feedback: FlowPreparedFeedback?
    if let feedbackOverride { feedback = feedbackOverride } else { feedback = try await prepareFeedback(next: &next) }
    guard additionalAssets.isEmpty || feedback == nil else {
      throw FlowPortfolioError.invalid("Generated history publication cannot create or replace artistic feedback.")
    }
    let records = try graphRecords(next)
    let photos = sourcePhotoRecords.filter { !publishedPhotoIDs.contains($0.key) }.map { DrawingLibraryRetainedClosure(photo: $0.value) }
    let closure = DrawingLibraryRetainedClosure(assets: photos.flatMap(\.assets), records: photos.flatMap(\.records))
    let publishedBlobs = durableAssets(next)
    let reusable = try await storage.library.existingVerifiedAssets(additionalAssets.map(\.descriptor))
    let newHistoryAssets = additionalAssets.filter { !reusable.contains($0.descriptor.asset.object) }
    let assets = try await storage.closureAssets(publishedBlobs) + featureClosureAssets() + newHistoryAssets
    let oldIDs = Set(state.sources.map(\.id))
    let initial = next.sources.filter { !oldIDs.contains($0.id) && newPhotoMetadataSources.contains($0.id) }.compactMap { source -> DrawingLibraryPhotoMetadataUpdate? in
      guard let ref = source.photo else { return nil }
      return .init(reference: ref, patch: .init(title: .set(source.title), subjectID: .set(source.subjectID), sessionID: .set(source.sessionID), excluded: source.excluded))
    }
    let write = FlowPendingGraphWrite(next: next, records: records, assets: assets, closure: closure, publishedBlobs: publishedBlobs, intent: .init(), photoMetadata: initial + photoMetadata, feedback: feedback)
    pendingGraphWrite = write
    try await finishPendingGraphWrite()
    return state
  }
  func finishPendingGraphWrite() async throws {
    guard let write = pendingGraphWrite else { return }
    if let feedback = write.feedback {
      _ = try await storage.library.commitFeedback(feedback.package, records: write.records, intent: write.intent, photoMetadata: write.photoMetadata)
      try? FileManager.default.removeItem(at: feedback.temporaryRoot)
    } else {
      try await storage.library.commitRecords(write.records, assets: write.assets, intent: write.intent, closure: write.closure, photoMetadata: write.photoMetadata)
    }
    publishedPhotoIDs.formUnion(write.next.sources.map(\.id))
    newPhotoMetadataSources.subtract(write.next.sources.map(\.id))
    storage.markPublished(write.publishedBlobs)
    for record in write.records { committedRecords.insert(record.key) }
    for record in write.records where record.kind == kind("frozen-view") { frozenTrainingViews.removeValue(forKey: record.id) }
    for asset in write.assets { featureSupportingAssets.removeValue(forKey: asset.descriptor.asset.object) }
    state = write.next; pendingGraphWrite = nil
    try await refreshPhotoMetadata()
  }

  package func featureCapsule(candidateID: UUID, revisionID: UUID? = nil) async throws -> FlowPortfolioFeatureCapsule {
    let id = revisionID ?? candidateID
    if let capsule = featureCapsules[id] { return capsule }
    let key = DrawingLibraryRecordKey(kind: kind("features"), id: id)
    if let row = try await storage.library.record(key) {
      let value = try JSONDecoder().decode(FlowLibraryEntity<FlowPortfolioFeatureLocator>.self, from: row.payload)
      guard value.profile == key.kind, value.value.id == id, value.value.candidateID == candidateID else { throw FlowPortfolioError.invalid("Feature capsule identity mismatch.") }
      committedRecords.insert(key)
      return try await readFeature(value.value.asset, expectedID: id, candidateID: candidateID)
    }
    let removed = revisionID.flatMap { id in state.pruneRevisions.first { $0.id == id }?.removedIndices } ?? []
    return try await captureFeatures(candidateID: candidateID, id: id, removedIndices: removed)
  }
  func captureFeatures(candidateID: UUID, id: UUID, removedIndices: [Int]) async throws -> FlowPortfolioFeatureCapsule {
    pinCandidate(candidateID); defer { unpinCandidate(candidateID) }
    if let capsule = featureCapsules[id] { return capsule }
    guard let candidate = state.candidates.first(where: { $0.id == candidateID }) else { throw FlowPortfolioError.unavailable("Drawing metadata is unavailable.") }
    let program = try await candidateProgram(candidateID), raster = try await candidateRaster(candidateID)
    let removed = Set(removedIndices)
    let drawing: Drawing
    if let temporary = temporaryDrawings[candidateID] { drawing = temporary }
    else if let reference = candidate.drawing { drawing = try await storage.library.drawing(reference) }
    else if let historical = try await historicalDrawing(candidateID) { drawing = historical }
    else { throw FlowPortfolioError.unavailable("Exact producer receipt is unavailable for feature extraction.") }
    guard drawing.program == program else { throw FlowPortfolioError.invalid("Feature producer/program mismatch.") }
    let producer = try featureSupport(drawing.producer.originalJSON)
    let configuration = try DrawingArtifactCoding.encoder().encode(FlowFeatureExtractorConfiguration.current)
    let extractor = try featureSupport(configuration)
    let root: FlowPortfolioFeatureCapsule?
    if id == candidateID { root = nil } else { root = try await featureCapsule(candidateID: candidateID) }
    let capsule = FlowPortfolioFeatureCapsule(profile: "adaptiveplotter.flow-features/3", id: id,
      candidateID: candidateID, sourceID: candidate.sourceID, programDigest: .init(program.contentHash), rootFeatures: try root?.asset, strokeIDs: program.strokes.map(\.id), recipe: candidate.recipe,
      producer: .init(id: drawing.producer.id, version: drawing.producer.version, record: producer, nativeVerified: drawing.capabilities.producerVerified),
      extractor: .init(id: "adaptiveplotter.flow-features", version: FlowArtistFeatures.revision, record: extractor, nativeVerified: false),
      drawing: FlowArtistFeatures.drawing(recipe: candidate.recipe, program: program, raster: raster, removedIndices: removed),
      strokes: root?.strokes ?? FlowArtistFeatures.strokes(recipe: candidate.recipe, program: program, raster: raster), removedIndices: removedIndices)
    let png = try PortraitDrawingPreview.png(program, removed: removed)
    previewArtifacts[id] = .init(id: id, image: try storage.retain(png, mediaType: "image/png"))
    featureCapsules[id] = capsule
    return capsule
  }
  package func presentationPreview(_ item: FlowPortfolioPresentationItem) async throws -> Data {
    pinCandidate(item.candidateID); defer { unpinCandidate(item.candidateID) }
    if let preview = previewArtifacts[item.id] { return try await storage.read(preview.image) }
    let key = DrawingLibraryRecordKey(kind: kind("preview"), id: item.id)
    if let row = try await storage.library.record(key) {
      let value = try JSONDecoder().decode(FlowLibraryEntity<FlowPortfolioPreviewArtifact>.self, from: row.payload)
      guard value.profile == key.kind, value.value.id == item.id else { throw FlowPortfolioError.invalid("Preview identity mismatch.") }
      committedRecords.insert(key)
      storage.markPublished([value.value.image])
      return try await storage.read(value.value.image)
    }
    let program = try await candidateProgram(item.candidateID)
    return try PortraitDrawingPreview.png(program, removed: Set(item.removedIndices))
  }

}

extension FlowPortfolioStore {
  func attachPhoto(to source: inout FlowPortfolioSource, data: Data, capturedPhoto: PortraitPhoto? = nil) throws {
    let bytes = data
    let facts = try source.captureProvenance.map { try DrawingArtifactCoding.encoder().encode($0) }
    let photo = try PortraitDrawingImages.photo(data: bytes, issuer: state.id, captureID: source.id,
      capturedAt: capturedPhoto?.capturedAt ?? source.captureProvenance?.capturedAt, importedAt: source.createdAt, facts: facts)
    source.photo = photo.reference; sourcePhotoRecords[source.id] = photo
    newPhotoMetadataSources.insert(source.id)
  }
  package func sourcePhoto(_ id: UUID) async throws -> FrozenPhotoRecord {
    if let photo = sourcePhotoRecords[id] { return photo }
    guard let source = state.sources.first(where: { $0.id == id }) else { throw FlowPortfolioError.unavailable("Source photograph unavailable.") }
    guard let ref = source.photo else { throw FlowPortfolioError.unavailable("Exact Photo reference is unavailable.") }
    let photo = try await storage.library.photo(ref)
    sourcePhotoRecords[id] = photo
    return photo
  }
  /// Refresh only on neutral metadata revision or membership change. The fields
  /// in Flow snapshots are projections, never a second mutation authority.
  package func refreshPhotoMetadata() async throws {
    let revision = try await storage.library.photoMetadataRevision()
    let refs = Set(state.sources.compactMap(\.photo))
    if revision != photoMetadataProjectionRevision || refs != photoMetadataProjectionRefs {
      photoMetadataProjectionValues = try await storage.library.photoMetadata(Array(refs))
      photoMetadataProjectionRevision = revision; photoMetadataProjectionRefs = refs
    }
    let values = photoMetadataProjectionValues
    for index in state.sources.indices {
      guard let ref = state.sources[index].photo, let value = values[ref] else { continue }
      state.sources[index].title = value.title ?? "Photo"
      state.sources[index].subjectID = value.subjectID
      state.sources[index].sessionID = value.sessionID
      state.sources[index].excluded = value.excluded
    }
    photoMetadataProjectionRevision = revision; photoMetadataProjectionRefs = refs
  }

  package func exportDrawing(_ drawing: Drawing, to url: URL) async throws {
    guard let reference = drawing.reference else { throw DrawingExchangeError.mismatchedParent }
    try await storage.library.exportDrawing(reference, to: url)
  }
}

package struct FlowMaterialSource: Sendable {
  package let data: Data
  package let raster: PortraitRaster
  package let recipe: FlowArtistRecipe
  package let analysisOptions: PortraitAnalysisOptions
  package let photo: FrozenPhotoRecord
}
extension FlowPortfolioStore {
  package func materialSource(for reference: DrawingRef) async throws -> FlowMaterialSource {
    var ref = reference, seen = Set<DrawingRef>()
    for _ in 0..<64 {
      guard seen.insert(ref).inserted else { throw DrawingExchangeError.mismatchedParent }
      if let candidate = state.candidates.first(where: { value in value.drawing == ref || state.pruneRevisions.contains { $0.candidateID == value.id && $0.drawing == ref } }),
        let round = state.rounds.first(where: { $0.id == candidate.roundID }) {
        return FlowMaterialSource(data: try await sourceData(candidate.sourceID), raster: try await candidateRaster(candidate.id),
          recipe: candidate.recipe, analysisOptions: round.analysisOptions, photo: try await sourcePhoto(candidate.sourceID))
      }
      let drawing = try await storage.library.drawing(ref)
      guard case .present(let parent) = drawing.parent else { break }; ref = parent
    }
    throw FlowPortfolioError.unavailable("The selected drawing has no known Flow source and recipe for material adaptation.")
  }
}
