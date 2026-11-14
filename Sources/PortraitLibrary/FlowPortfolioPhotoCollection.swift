import Foundation
import PlotterModel
import PlotterRuntime
import PortraitArtists
import PortraitCore
import DrawingLibrary

/// Exact acquisition facts accompany the content-addressed image. A declared
/// capture session is neither an inferred subject nor an artistic preference.
package struct FlowPortfolioCaptureProvenance: Codable, Equatable, Sendable {
  package let photoID: UUID
  package let label: String
  package let capturedAt: Date
  package let frameID: FrameID?
  package let captureNanoseconds: UInt64?
  package let pose: PortraitPose
  package let sourcePixelExtent: PortraitSourceCropExtent?
  package let captureSessionID: UUID
  package let selectionProvenance: PortraitCaptureSelectionProvenance?
  package let imageSHA256: String

  package init(photo: PortraitPhoto) {
    photoID = photo.id; label = photo.label; capturedAt = photo.capturedAt
    frameID = photo.frameID; captureNanoseconds = photo.captureNanoseconds; pose = photo.pose
    sourcePixelExtent = photo.sourcePixelExtent; captureSessionID = photo.captureSessionID
    selectionProvenance = photo.selectionProvenance
    imageSHA256 = DrawingArtifactCoding.sha256(photo.data)
  }
}

/// The retained manifest carries original acquisition provenance, not preferences.
package struct FlowPortfolioSourceImport: Codable, Equatable, Sendable {
  package let collectionID: String
  package let entryID: String
  package let manifest: FlowPortfolioBlob
}

package struct FlowPhotoCollectionManifest: Codable, Equatable, Sendable {
  package let schemaVersion: Int
  package let id: String
  package let title: String
  package let entries: [FlowPhotoCollectionEntry]
}
package struct FlowPhotoCollectionEntry: Codable, Equatable, Sendable {
  package let id: String
  package let title: String
  package let filename: String
  package let sha256: String
  package let byteCount: Int
  /// A declared original acquisition session only; never inferred from pixels.
  package let sessionID: String?
  package let provenanceJSON: Data
}

/// A small self-contained source-only exchange. Loading performs no portfolio writes.
package struct FlowPhotoCollection: Sendable {
  package let manifest: FlowPhotoCollectionManifest
  package let manifestData: Data
  let images: [String: Data]

  package static func load(directory: URL) throws -> Self {
    let root = directory.resolvingSymlinksInPath().standardizedFileURL
    let manifestURL = root.appendingPathComponent("photo-collection.json")
    let metadata = try manifestURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
    guard metadata.isRegularFile == true, (metadata.fileSize ?? 0) <= 4_000_000 else {
      throw FlowPortfolioError.invalid("Photo collection manifest is missing or too large.")
    }
    let data = try Data(contentsOf: manifestURL)
    let manifest = try JSONDecoder().decode(FlowPhotoCollectionManifest.self, from: data)
    guard manifest.schemaVersion == 1, !manifest.id.isEmpty, manifest.id.utf8.count <= 256,
      !manifest.title.isEmpty, manifest.title.utf8.count <= 1024,
      (1...100).contains(manifest.entries.count),
      Set(manifest.entries.map(\.id)).count == manifest.entries.count else {
      throw FlowPortfolioError.invalid("Photo collection identity or entries are invalid.")
    }
    var images: [String: Data] = [:], total = 0
    for entry in manifest.entries {
      guard !entry.id.isEmpty, entry.id.utf8.count <= 256, !entry.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
        entry.title.utf8.count <= 1024, FlowPortfolioValidation.validHash(entry.sha256),
        entry.filename == "images/" + entry.sha256 + ".asset", (1...64_000_000).contains(entry.byteCount),
        (entry.sessionID?.utf8.count ?? 0) <= 256, entry.provenanceJSON.count <= 256_000,
        (try? JSONSerialization.jsonObject(with: entry.provenanceJSON)) != nil else {
        throw FlowPortfolioError.invalid("Photo collection entry has invalid provenance, identity or path.")
      }
      total += entry.byteCount
      guard total <= 256_000_000 else { throw FlowPortfolioError.invalid("Photo collection exceeds 256 MB.") }
      let url = root.appendingPathComponent(entry.filename).resolvingSymlinksInPath().standardizedFileURL
      guard url.path.hasPrefix(root.path + "/") else { throw FlowPortfolioError.invalid("Photo collection asset escapes its directory.") }
      let info = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
      guard info.isRegularFile == true, info.fileSize == entry.byteCount else { throw FlowPortfolioError.invalid("Photo collection asset size differs from its manifest.") }
      let bytes = try Data(contentsOf: url)
      guard DrawingArtifactCoding.sha256(bytes) == entry.sha256 else { throw FlowPortfolioError.invalid("Photo collection image hash differs from its manifest.") }
      _ = try FlowPortfolioStore.validatedSourceAsset(bytes)
      images[entry.id] = bytes
    }
    return Self(manifest: manifest, manifestData: data, images: images)
  }
}

extension FlowPortfolioStore {
  /// The photo identity makes an uncertain autosave retry idempotent. Separate
  /// capture identities remain separate observations even when pixels match.
  @discardableResult package func addCapturedSource(photo: PortraitPhoto, title: String, selecting: Bool = true) async throws -> FlowPortfolioSource {
    try requireArtifactMutationAdmission()
    defer { trimTransientCaches() }
    let provenance = FlowPortfolioCaptureProvenance(photo: photo)
    if let existing = state.sources.first(where: { $0.captureProvenance?.photoID == photo.id }) {
      guard existing.captureProvenance == provenance, existing.image.sha256 == provenance.imageSHA256 else {
        throw FlowPortfolioError.conflict("Capture identity was reused with different image bytes or acquisition metadata.")
      }
      return existing
    }
    guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, title.utf8.count <= 1024 else {
      throw FlowPortfolioError.invalid("Name the captured photograph.")
    }
    let asset = try FlowPortfolioStore.validatedSourceAsset(photo.data)
    var source = FlowPortfolioSource(id: UUID(), createdAt: Date(), title: title,
      image: try storage.retain(photo.data, mediaType: asset.mediaType), subjectID: nil,
      sessionID: "capture:" + photo.captureSessionID.uuidString, captureProvenance: provenance)
    try attachPhoto(to: &source, data: photo.data, capturedPhoto: photo)
    var next = state; next.sources.append(source)
    if selecting { next.selectedSourceID = source.id
      next.currentRoundID = nil; next.currentCandidateID = nil; next.currentPruneRevisionID = nil
    }
    try await commit(next)
    return source
  }

  /// Atomic, source-only import; an uncertain commit can be retried by source hash.
  /// Existing sources, labels, selections and groups are never rewritten.
  @discardableResult package func importPhotoCollection(_ collection: FlowPhotoCollection) async throws -> [FlowPortfolioSource] {
    try requireArtifactMutationAdmission()
    defer { trimTransientCaches() }
    var next = state, result: [FlowPortfolioSource] = []
    var retainedManifests: [String: FlowPhotoCollectionManifest] = [:]
    let manifest = try storage.retain(collection.manifestData, mediaType: "application/json")
    for entry in collection.manifest.entries {
      if let existing = next.sources.first(where: { $0.importProvenance?.collectionID == collection.manifest.id && $0.importProvenance?.entryID == entry.id }) {
        guard let provenance = existing.importProvenance else { throw FlowPortfolioError.invalid("Missing collection occurrence proof.") }
        let original: FlowPhotoCollectionManifest
        if let cached = retainedManifests[provenance.manifest.sha256] { original = cached }
        else {
          original = try JSONDecoder().decode(FlowPhotoCollectionManifest.self, from: await storage.read(provenance.manifest))
          retainedManifests[provenance.manifest.sha256] = original
        }
        guard original.id == collection.manifest.id,
          let occurrence = original.entries.first(where: { $0.id == entry.id }),
          occurrence.sha256 == entry.sha256, occurrence.byteCount == entry.byteCount,
          occurrence.sessionID == entry.sessionID, occurrence.provenanceJSON == entry.provenanceJSON,
          existing.image.sha256 == entry.sha256, existing.image.byteCount == entry.byteCount else {
          throw FlowPortfolioError.conflict("Collection occurrence was reused with different source bytes or acquisition facts.")
        }
        result.append(existing); continue
      }
      guard let bytes = collection.images[entry.id], DrawingArtifactCoding.sha256(bytes) == entry.sha256 else {
        throw FlowPortfolioError.invalid("Photo collection has lost a verified source image.")
      }
      let asset = try FlowPortfolioStore.validatedSourceAsset(bytes)
      var source = FlowPortfolioSource(id: UUID(), createdAt: Date(), title: entry.title,
        image: try storage.retain(bytes, mediaType: asset.mediaType), subjectID: nil, sessionID: entry.sessionID,
        importProvenance: .init(collectionID: collection.manifest.id, entryID: entry.id, manifest: manifest))
      try attachPhoto(to: &source, data: bytes)
      next.sources.append(source); result.append(source)
    }
    if next.sources.count != state.sources.count { try await commit(next) }
    return result
  }

  package func renameSource(sourceID: UUID, title: String) async throws {
    let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !title.isEmpty, title.utf8.count <= 1024, let index = state.sources.firstIndex(where: { $0.id == sourceID }) else {
      throw FlowPortfolioError.invalid("A photograph needs a nonempty name of at most 1024 bytes.")
    }
    var next = state; next.sources[index].title = title
    guard let ref = next.sources[index].photo else { throw FlowPortfolioError.unavailable("Photo reference is unavailable.") }
    try await commit(next, photoMetadata: [.init(reference: ref, patch: .init(title: .set(title)))])
  }

  package func renameCandidate(candidateID: UUID, title: String) async throws {
    let value = title.trimmingCharacters(in: .whitespacesAndNewlines)
    guard value.utf8.count <= 1024, let index = state.candidates.firstIndex(where: { $0.id == candidateID }) else {
      throw FlowPortfolioError.invalid("Drawing name is unavailable or too long.")
    }
    let title: String? = value.isEmpty ? nil : value
    guard state.candidates[index].title != title else { return }
    var next = state; next.candidates[index].title = title
    try await commit(next)
  }

  /// Navigation cannot create a choice or a training preference.
  package func selectCandidate(_ id: UUID) async throws {
    selectionOwner = UUID()
    guard let candidate = state.candidates.first(where: { $0.id == id }) else { throw FlowPortfolioError.unavailable("Drawing is unavailable.") }
    var next = state; next.selectedSourceID = candidate.sourceID; next.currentRoundID = candidate.roundID
    next.currentCandidateID = id; next.currentPruneRevisionID = next.latestPrune(candidateID: id)?.id
    if next != state { try await commit(next) }
  }
}
