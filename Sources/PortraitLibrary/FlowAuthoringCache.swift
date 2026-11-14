import Foundation
import PortraitCore
import PortraitArtists

package struct FlowAuthoringCacheStatistics: Sendable {
  package let artifactCount: Int
  package let artifactBytes: Int
  package let temporaryDrawingCount: Int
  package let drawingInputCount: Int
  /// Conservative geometry/closure payload estimate; not allocator usage or RSS.
  package let temporaryDrawingBytes: Int
}

extension FlowPortfolioStore {
  package nonisolated static let maximumTemporaryDrawings = 25
  package nonisolated static let maximumTemporaryDrawingBytes = 256 * 1024 * 1024

  package func transientCacheStatistics() -> FlowAuthoringCacheStatistics {
    .init(artifactCount: storage.count, artifactBytes: storage.byteCount,
      temporaryDrawingCount: temporaryDrawings.count, drawingInputCount: drawingInputs.count,
      temporaryDrawingBytes: temporaryDrawings.reduce(0) { $0 + temporaryBytes($1.value, input: drawingInputs[$1.key]) })
  }
  func pinCandidate(_ id: UUID) { inFlightCandidates[id, default: 0] += 1 }
  func unpinCandidate(_ id: UUID) {
    if let count = inFlightCandidates[id], count > 1 { inFlightCandidates[id] = count - 1 }
    else { inFlightCandidates.removeValue(forKey: id) }
    trimTransientCaches()
  }
  private func temporaryBytes(_ drawing: Drawing, input: FrozenImageInputRecord?) -> Int {
    let geometry = drawing.cachedSummary.pointCount * 16 + drawing.cachedSummary.strokeCount * 128 + drawing.producer.originalJSON.count
    guard let input else { return geometry }
    // Both owners retain assets. Count both lists conservatively even where
    // their Data shares storage; cold admission need not preserve that sharing.
    return geometry + input.record.originalJSON.count + input.photo.record.originalJSON.count
      + input.assets.reduce(0) { $0 + $1.bytes.count }
      + input.photo.assets.reduce(0) { $0 + $1.bytes.count }
  }
  func admitTemporaryDrawing(_ drawing: Drawing, input: FrozenImageInputRecord?) throws {
    trimTransientCaches()
    let incoming = temporaryBytes(drawing, input: input)
    var current = transientCacheStatistics()
    if current.temporaryDrawingCount >= Self.maximumTemporaryDrawings
      || incoming > Self.maximumTemporaryDrawingBytes - current.temporaryDrawingBytes {
      evictOptionalHistory(); current = transientCacheStatistics()
    }
    guard current.temporaryDrawingCount < Self.maximumTemporaryDrawings,
      incoming <= Self.maximumTemporaryDrawingBytes - current.temporaryDrawingBytes else {
      throw FlowPortfolioError.unavailable("The active drawing panel exceeds the temporary authoring memory budget.")
    }
  }
  func admitTemporaryArtifacts(_ values: [Data]) throws {
    if !storage.canRetain(values) { evictOptionalHistory() }
    guard storage.canRetain(values) else {
      throw FlowPortfolioError.unavailable("The active drawing panel exceeds the temporary artifact memory budget.")
    }
  }
  private func evictOptionalHistory() { recentTransientRoundIDs = []; trimTransientCaches() }

  /// Metadata availability never substitutes for reading retained data. This
  /// detects known expired session artifacts; actual retained corruption still
  /// travels through the existing exact loader/recovery path.
  package func candidateUnavailableReason(_ id: UUID) async throws -> String? {
    guard let value = state.candidates.first(where: { $0.id == id }) else {
      return "This drawing is no longer in the authoring session."
    }
    let programAvailable = value.drawing != nil || temporaryDrawings[id] != nil
    if programAvailable && storage.isAvailable(value.raster) { return nil }
    if value.authoringClosure != nil {
      guard let source = state.sources.first(where: { $0.id == value.sourceID }),
        let round = state.rounds.first(where: { $0.id == value.roundID }) else { return "History source or round is unavailable." }
      do { try history.availability(candidate: value, source: source, round: round); return nil }
      catch { return "History unavailable: " + error.localizedDescription }
    }
    if try await historicalCandidate(id) != nil { return nil }
    return programAvailable
      ? "Preview only: the temporary source raster has expired. Start a broad sample to make new drawings."
      : "Preview only: temporary drawing geometry has expired. Start a broad sample to make new drawings."
  }
  package func candidateUnavailableReasons(_ ids: [UUID]) async throws -> [UUID: String] {
    var reasons: [UUID: String] = [:]
    for id in ids { if let reason = try await candidateUnavailableReason(id) { reasons[id] = reason } }
    return reasons
  }

  private func observeTransientRound() {
    let source = state.selectedSourceID
    let current = state.currentRoundID
    let options = state.rounds.first(where: { $0.id == current })?.analysisOptions
      ?? state.sources.first(where: { $0.id == source })?.authoringOptions
    if source != observedTransientSourceID || options != observedTransientOptions {
      recentTransientRoundIDs = []
    } else if current != observedTransientRoundID, let previous = observedTransientRoundID {
      recentTransientRoundIDs.removeAll { $0 == previous }
      recentTransientRoundIDs.insert(previous, at: 0)
    }
    observedTransientRoundID = current; observedTransientSourceID = source; observedTransientOptions = options
    recentTransientRoundIDs = Array(recentTransientRoundIDs.filter { $0 != current }.prefix(1))
  }
  func requireArtifactMutationAdmission() throws {
    guard !writeAdmissionActive, pendingGraphWrite == nil, pendingRetainedWrite == nil else {
      throw FlowPortfolioError.conflict("Recover the pending Library action before accepting another action.")
    }
    trimTransientCaches()
  }
  /// Never evict the dependencies of an unfinished publication. Pending batches
  /// also own immutable copies, so a retry cannot depend on a later cache fill.
  func trimTransientCaches() {
    guard !writeAdmissionActive, pendingGraphWrite == nil, pendingRetainedWrite == nil else { return }
    observeTransientRound()
    let rounds = Set(state.rounds.filter {
      $0.id == state.currentRoundID || $0.status == .generating || recentTransientRoundIDs.contains($0.id)
    }.map(\.id))
    let kept = Set(state.candidates.filter {
      $0.drawing == nil && (rounds.contains($0.roundID) || $0.id == state.currentCandidateID || inFlightCandidates[$0.id] != nil)
    }.map(\.id))
    temporaryDrawings = temporaryDrawings.filter { kept.contains($0.key) }
    drawingInputs = drawingInputs.filter { temporaryDrawings[$0.key] != nil }
    let blobs = state.candidates.filter { temporaryDrawings[$0.id] != nil }.flatMap { [$0.raster, $0.preview] }
      + previewArtifacts.values.map(\.image)
    storage.keepUnpublished(Set(blobs.map(\.sha256)))
    // Published image wrappers and learning vectors are reconstructed on demand;
    // they must not become a second, growing cache of the durable Library.
    let sources = Set(state.sources.map(\.id))
    sourcePhotoRecords = sourcePhotoRecords.filter { sources.contains($0.key) && !publishedPhotoIDs.contains($0.key) }
    featureCapsules = featureCapsules.filter { !committedRecords.contains(.init(kind: "adaptiveplotter.flow-features/2", id: $0.key)) }
    previewArtifacts = previewArtifacts.filter { !committedRecords.contains(.init(kind: "adaptiveplotter.flow-preview/2", id: $0.key)) }
  }
}
