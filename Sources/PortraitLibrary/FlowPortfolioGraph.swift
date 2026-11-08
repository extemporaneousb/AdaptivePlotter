import Foundation
import DrawingLibrary
import PortraitCore
import PortraitArtists
import PlotterModel

/// Frozen learning inputs survive a rank without retaining the compared geometry.
package struct FlowPortfolioFeatureCapsule: Codable, Sendable {
  package let id: UUID
  package let candidateID: UUID
  package let programDigest: ExchangeDigest
  package let drawing: [Double]
  package let strokes: [[Double]]
  package let removedIndices: [Int]
}

package struct FlowPortfolioPreviewArtifact: Codable, Sendable {
  package let id: UUID
  package let image: FlowPortfolioBlob
}

private struct FlowLibraryEntity<Value: Codable>: Codable {
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
  private func kind(_ name: String) -> String { "adaptiveplotter.flow-" + name + "/2" }
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
  package func loadRecords() async throws {
    try await storage.library.open()
    let sessions = try await rows(FlowPortfolioSession.self, "session")
    guard sessions.count <= 1 else { throw FlowPortfolioError.invalid("Multiple Flow sessions in one Library.") }
    guard let header = sessions.first else { return }
    guard requestedPurpose == nil || requestedPurpose == header.purpose else { throw FlowPortfolioError.invalid("The Library purpose differs from this session.") }
    guard header.profile == "adaptiveplotter.flow-session/2" else { throw FlowPortfolioError.invalid("Unsupported Flow session.") }
    var next = FlowPortfolioSnapshot.empty(purpose: header.purpose)
    next = FlowPortfolioSnapshot(schemaVersion: 2, purpose: header.purpose, id: header.id,
      createdAt: header.createdAt, revision: header.revision,
      sources: try await rows(FlowPortfolioSource.self, "source"),
      rounds: try await rows(FlowPortfolioRound.self, "round"),
      candidates: try await rows(FlowPortfolioCandidate.self, "candidate"),
      choices: try await rows(FlowPortfolioChoice.self, "choice"),
      pruneRevisions: try await rows(FlowPortfolioPruneRevision.self, "prune"),
      presentations: try await rows(FlowPortfolioPresentation.self, "presentation"),
      rankings: try await rows(FlowPortfolioRanking.self, "ranking"),
      trainingSnapshots: try await rows(FlowPortfolioTrainingSnapshot.self, "training"),
      fits: try await rows(FlowPortfolioFit.self, "fit"),
      activations: try await rows(FlowPortfolioActivation.self, "activation"),
      selectedSourceID: header.selectedSourceID, currentRoundID: header.currentRoundID,
      currentCandidateID: header.currentCandidateID, currentPruneRevisionID: header.currentPruneRevisionID,
      activeFitID: header.activeFitID, currentPresentationID: header.currentPresentationID)
    try FlowPortfolioValidation.validate(next)
    publishedPhotoIDs.formUnion(next.sources.map(\.id))
    storage.markPublished(durableAssets(next, includingLocalPreviews: false))
    state = next
  }

  func durableAssets(_ next: FlowPortfolioSnapshot, includingLocalPreviews: Bool = true) -> [FlowPortfolioBlob] {
    var blobs = next.sources.map(\.image) + next.sources.compactMap { $0.importProvenance?.manifest }
    for candidate in next.candidates where candidate.drawing != nil { blobs.append(contentsOf: [candidate.raster, candidate.preview]) }
    if includingLocalPreviews { blobs += previewArtifacts.values.map { $0.image } }
    blobs += next.trainingSnapshots.map(\.document)
    for fit in next.fits { blobs.append(fit.report); if let checkpoint = fit.checkpoint { blobs.append(checkpoint) } }
    return blobs
  }

  func graphRecords(_ next: FlowPortfolioSnapshot) throws -> [DrawingLibraryRecord] {
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
    try add(next.candidates, previous: state.candidates, "candidate", refs: { $0.drawing.map { [$0] } ?? [] })
    try add(next.choices, previous: state.choices, "choice")
    try add(next.pruneRevisions, previous: state.pruneRevisions, "prune", refs: { $0.drawing.map { [$0] } ?? [] })
    try add(next.presentations, previous: state.presentations, "presentation")
    try add(next.rankings, previous: state.rankings, "ranking")
    try add(next.trainingSnapshots, previous: state.trainingSnapshots, "training", assets: { [$0.document] })
    try add(next.fits, previous: state.fits, "fit", assets: { [$0.report] + ($0.checkpoint.map { [$0] } ?? []) })
    try add(next.activations, previous: state.activations, "activation")
    for capsule in featureCapsules.values where !committedRecords.contains(.init(kind: kind("features"), id: capsule.id)) {
      records.append(.init(kind: kind("features"), id: capsule.id, payload: try DrawingArtifactCoding.encoder().encode(FlowLibraryEntity(profile: kind("features"), ordinal: 0, value: capsule))))
    }
    for preview in previewArtifacts.values where !committedRecords.contains(.init(kind: kind("preview"), id: preview.id)) {
      records.append(.init(kind: kind("preview"), id: preview.id,
        payload: try DrawingArtifactCoding.encoder().encode(FlowLibraryEntity(profile: kind("preview"), ordinal: 0, value: preview)),
        assets: [try ExchangeDigest(preview.image.sha256)]))
    }
    return records
  }
  func publishRecords(_ next: FlowPortfolioSnapshot) async throws -> FlowPortfolioSnapshot {
    guard !writeAdmissionActive, pendingGraphWrite == nil, pendingRetainedWrite == nil else { throw FlowPortfolioError.conflict("Recover the pending Library action before accepting another action.") }
    writeAdmissionActive = true; defer { writeAdmissionActive = false }
    let records = try graphRecords(next)
    let photos = sourcePhotoRecords.filter { !publishedPhotoIDs.contains($0.key) }.map { DrawingLibraryRetainedClosure(photo: $0.value) }
    let closure = DrawingLibraryRetainedClosure(assets: photos.flatMap(\.assets), records: photos.flatMap(\.records))
    let publishedBlobs = durableAssets(next)
    let assets = try await storage.closureAssets(publishedBlobs)
    let write = FlowPendingGraphWrite(next: next, records: records, assets: assets, closure: closure, publishedBlobs: publishedBlobs, intent: .init())
    pendingGraphWrite = write
    try await finishPendingGraphWrite()
    return next
  }
  func finishPendingGraphWrite() async throws {
    guard let write = pendingGraphWrite else { return }
    try await storage.library.commitRecords(write.records, assets: write.assets, intent: write.intent, closure: write.closure)
    publishedPhotoIDs.formUnion(write.next.sources.map(\.id))
    storage.markPublished(write.publishedBlobs)
    for record in write.records { committedRecords.insert(record.key) }
    state = write.next; pendingGraphWrite = nil
  }

  package func featureCapsule(candidateID: UUID, revisionID: UUID? = nil) async throws -> FlowPortfolioFeatureCapsule {
    let id = revisionID ?? candidateID
    if let capsule = featureCapsules[id] { return capsule }
    let key = DrawingLibraryRecordKey(kind: kind("features"), id: id)
    if let row = try await storage.library.record(key) {
      let value = try JSONDecoder().decode(FlowLibraryEntity<FlowPortfolioFeatureCapsule>.self, from: row.payload)
      guard value.profile == key.kind, value.value.id == id, value.value.candidateID == candidateID else { throw FlowPortfolioError.invalid("Feature capsule identity mismatch.") }
      committedRecords.insert(key)
      return value.value
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
    let capsule = FlowPortfolioFeatureCapsule(id: id, candidateID: candidateID, programDigest: .init(program.contentHash),
      drawing: FlowArtistFeatures.drawing(recipe: candidate.recipe, program: program, raster: raster, removedIndices: removed),
      strokes: FlowArtistFeatures.strokes(recipe: candidate.recipe, program: program, raster: raster), removedIndices: removedIndices)
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
  }
  package func sourcePhoto(_ id: UUID) async throws -> FrozenPhotoRecord {
    if let photo = sourcePhotoRecords[id] { return photo }
    guard let source = state.sources.first(where: { $0.id == id }) else { throw FlowPortfolioError.unavailable("Source photograph unavailable.") }
    let bytes = try await storage.read(source.image)
    let facts = try source.captureProvenance.map { try DrawingArtifactCoding.encoder().encode($0) }
    let photo = try PortraitDrawingImages.photo(data: bytes, issuer: state.id, captureID: source.id,
      capturedAt: source.captureProvenance?.capturedAt, importedAt: source.createdAt, facts: facts)
    guard source.photo == photo.reference else { throw DrawingExchangeError.mismatchedParent }
    return photo
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
