import AppKit
import Foundation
import ImageIO
import PortraitArtists
import PortraitLibrary
import PortraitCore

/// Stable names and ancestry are projections of durable identities. Browsing
/// them never declares artistic preference or creates another drawing.
extension FlowAuthoringModel {
  /// Completed metadata is not proof that a temporary drawing survived eviction
  /// or reopening. Only exact program/preview reads qualify a Booth suggestion.
  package var recommendationCandidate: FlowPortfolioCandidate? {
    guard let candidate = recommendationProposal, verifiedRecommendationIDs.contains(candidate.id),
      self.candidate?.id == candidate.id, program != nil, candidateLoadError == nil else { return nil }
    return candidate
  }
  private var recommendationProposal: FlowPortfolioCandidate? {
    guard !regionPreviewPending, let document, let source = selectedSource else { return nil }
    let rounds = document.rounds.filter {
      $0.sourceID == source.id && $0.status == .completed && $0.analysisOptions == committedAnalysisOptions
        && $0.modelID == activeCheckpoint?.id
    }
    func hasUsableMask(_ candidate: FlowPortfolioCandidate) -> Bool {
      (presentationIndex?.latestPrunes[candidate.id]?.removedIndices.count ?? 0) < candidate.strokeCount
    }
    if activeCheckpoint?.ranker != nil {
      for round in rounds.reversed() {
        if let id = round.recommendedCandidateID, !unavailableRecommendationIDs.contains(id),
          let candidate = presentationIndex?.candidates[id], hasUsableMask(candidate) { return candidate }
      }
    }
    for round in rounds.reversed() {
      let ids = round.displayedCandidateIDs.isEmpty ? round.candidateIDs : round.displayedCandidateIDs
      if let candidate = ids.lazy.compactMap({ id in self.presentationIndex?.candidates[id] })
        .first(where: { !unavailableRecommendationIDs.contains($0.id) && hasUsableMask($0) }) { return candidate }
    }
    return nil
  }
  package func isPredictedFavorite(_ candidate: FlowPortfolioCandidate) -> Bool {
    guard let checkpoint = activeCheckpoint, checkpoint.ranker != nil,
      candidateUnavailableReason(candidate) == nil, candidate.sourceID == selectedSource?.id,
      let round = presentationIndex?.rounds[candidate.roundID],
      round.status == .completed, round.modelID == checkpoint.id,
      round.analysisOptions == committedAnalysisOptions, round.recommendedCandidateID == candidate.id,
      let scoredMask = round.recommendedRemovedIndices, scoredMask.count < candidate.strokeCount,
      scoredMask == (presentationIndex?.latestPrunes[candidate.id]?.removedIndices ?? []) else { return false }
    if self.candidate?.id == candidate.id { return program != nil && candidateLoadError == nil }
    return previews[candidate.id] != nil
  }
  package var isRecommendationPredictedFavorite: Bool {
    recommendationCandidate.map(isPredictedFavorite) ?? false
  }
  package func ensureRecommendation() async {
    guard acceptsChanges, !isBusy, !needsRecovery, !regionPreviewPending, let source = selectedSource, let store else { return }
    let options = committedAnalysisOptions, checkpoint = activeCheckpoint?.id
    var intent = generationIntentRevision
    func isCurrent() -> Bool {
      !Task.isCancelled && acceptsChanges && !regionPreviewPending && !needsRecovery
        && generationIntentRevision == intent && selectedSource?.id == source.id
        && committedAnalysisOptions == options && activeCheckpoint?.id == checkpoint
    }
    clearRecommendationFailure()
    // At most one new budget is rendered. Evicted metadata cannot create an
    // unbounded retry loop, and corrupt retained work stays a truthful failure.
    for attempt in 0...1 {
      guard isCurrent() else { return }
      if let candidate = recommendationProposal {
        do {
          _ = try await store.candidateProgram(candidate.id)
          _ = try await store.candidatePreview(candidate.id)
          guard isCurrent() else { return }
          verifiedRecommendationIDs = [candidate.id]; clearRecommendationFailure()
          await browseCandidate(candidate.id)
          return
        } catch {
          guard isCurrent() else { return }
          reportRecommendationFailure(candidate.id, reason: "Suggestion unavailable: " + error.localizedDescription, excludeTemporary: candidate.drawing == nil)
          if candidate.drawing != nil { return }
        }
      }
      guard attempt == 0, isCurrent() else { return }
      await generate(refining: false, recommendation: true)
      // generate owns exactly one new admission; any other invalidation wins.
      guard generationIntentRevision == intent &+ 1 else { return }
      intent = generationIntentRevision
    }
  }
  package func exploreRecommendation() async {
    guard let candidate = recommendationCandidate, !isBusy else { return }
    let source = selectedSource?.id, options = committedAnalysisOptions
    await browseCandidate(candidate.id)
    guard !Task.isCancelled, selectedSource?.id == source, committedAnalysisOptions == options,
      self.candidate?.id == candidate.id else { return }
    await generate(refining: false, broadAnchor: candidate.id)
  }

  package func photoName(_ source: FlowPortfolioSource) -> String {
    if !source.title.hasPrefix("Frame ") { return source.title }
    let index = (document?.sources.firstIndex(where: { $0.id == source.id }) ?? 0) + 1
    return "Photo \(index) · " + source.createdAt.formatted(date: .abbreviated, time: .omitted)
  }
  package func nextPhotoTitle(capturedAt: Date) -> String {
    "Photo \((document?.sources.count ?? 0) + 1) · " + capturedAt.formatted(date: .abbreviated, time: .shortened)
  }
  package func drawingName(_ value: FlowPortfolioCandidate) -> String {
    if let name = value.title, !name.isEmpty { return name }
    return "Drawing \(presentationIndex?.drawingNumbers[value.id] ?? 1)"
  }
  package func roundName(_ value: FlowPortfolioRound) -> String {
    "Set \(presentationIndex?.roundNumbers[value.id] ?? 1)"
  }
  package var currentBranch: String {
    guard let round else { return "Start a broad set for this photo" }
    if let id = round.parentCandidateID, let parent = presentationIndex?.candidates[id] {
      return roundName(round) + " · refined from " + drawingName(parent)
    }
    return roundName(round) + " · broad exploration"
  }
  package var branchAncestors: [FlowPortfolioCandidate] {
    guard let index = presentationIndex else { return [] }
    var next = round?.parentCandidateID, result: [FlowPortfolioCandidate] = [], seen = Set<UUID>()
    while let id = next, seen.insert(id).inserted,
      let parent = index.candidates[id] {
      result.append(parent); next = parent.parentCandidateID
    }
    return result.reversed()
  }
  package func branchDepth(_ round: FlowPortfolioRound) -> Int {
    guard let index = presentationIndex else { return 0 }
    var next = round.parentCandidateID, seen = Set<UUID>()
    while let id = next, seen.insert(id).inserted { next = index.candidates[id]?.parentCandidateID }
    return seen.count
  }

  package func branches(for sourceID: UUID) -> [FlowPortfolioRound] {
    guard let document else { return [] }
    let sources = document.photoSourceIDs(for: sourceID)
    let rounds = document.rounds.filter { sources.contains($0.sourceID) }
    let candidates = presentationIndex?.candidates ?? [:]
    var children: [UUID: [FlowPortfolioRound]] = [:], roots: [FlowPortfolioRound] = []
    let ids = Set(rounds.map(\.id))
    for round in rounds {
      if let parent = round.parentCandidateID.flatMap({ candidates[$0]?.roundID }), ids.contains(parent) {
        children[parent, default: []].append(round)
      } else { roots.append(round) }
    }
    var visited = Set<UUID>(), result: [FlowPortfolioRound] = []
    func append(_ value: FlowPortfolioRound) {
      guard visited.insert(value.id).inserted else { return }
      result.append(value)
      for child in children[value.id] ?? [] { append(child) }
    }
    for root in roots { append(root) }
    for round in rounds { append(round) }
    return result
  }

  package func representative(for sourceID: UUID) -> FlowPortfolioPresentationItem? {
    guard let document else { return nil }
    let sources = document.photoSourceIDs(for: sourceID)
    for ranking in document.latestRankings.reversed() where !ranking.skipped && !ranking.neither {
      guard let tier = ranking.orderedGroups.first,
        let presentation = document.presentations.first(where: { $0.id == ranking.presentationID }),
        let item = presentation.items.first(where: { sources.contains($0.sourceID) && tier.contains($0.id) }) else { continue }
      return item
    }
    for choice in document.choices.reversed() {
      if let item = choice.offeredItems.first(where: { $0.id == choice.selectedItemID && sources.contains($0.sourceID) }) { return item }
    }
    let candidates = document.candidates.filter { sources.contains($0.sourceID) }, ids = Set(candidates.map(\.id))
    if let edit = document.pruneRevisions.last(where: { ids.contains($0.candidateID) }) {
      guard let candidate = candidates.first(where: { $0.id == edit.candidateID }) else { return nil }
      return .init(id: edit.id, candidateID: edit.candidateID, revisionID: edit.id, sourceID: candidate.sourceID, removedIndices: edit.removedIndices)
    }
    guard let first = candidates.first else { return nil }
    return FlowPortfolioPresentationItem(id: first.id, candidateID: first.id, revisionID: nil, sourceID: first.sourceID, removedIndices: [])
  }
  package func representativeKey(_ source: FlowPortfolioSource) -> String {
    let prefix = (document?.id.uuidString ?? "") + ":" + source.id.uuidString
    guard let item = representative(for: source.id),
      let candidate = presentationIndex?.candidates[item.candidateID] else { return prefix + source.image.sha256 }
    return prefix + ":" + item.id.uuidString + ":" + candidate.programHash
  }
  package func representativeThumbnail(_ source: FlowPortfolioSource) async -> Data? {
    guard let item = representative(for: source.id), let store else { return await thumbnail(source: source) }
    let key = representativeKey(source)
    return try? await FlowAuthoringThumbnailCache.shared.load(key: key) {
      try await store.presentationPreview(item)
    }
  }

  package func thumbnail(source: FlowPortfolioSource) async -> Data? {
    guard let store else { return nil }
    return try? await FlowAuthoringThumbnailCache.shared.load(key: "source:" + source.image.sha256) {
      try await store.sourceData(source.id)
    }
  }
  package func previewIdentity(candidate: FlowPortfolioCandidate, revisionID: UUID? = nil) -> String {
    let revision = revisionID ?? presentationIndex?.latestPrunes[candidate.id]?.id
    let source = presentationIndex?.sources[candidate.sourceID]?.image.sha256 ?? "no-source"
    return (document?.id.uuidString ?? "") + ":" + source + ":" + candidate.id.uuidString
      + ":" + candidate.programHash + ":" + candidate.preview.sha256 + ":" + (revision?.uuidString ?? "root")
  }
  package func rankingPreviewIdentity(_ item: FlowPortfolioPresentationItem) -> String {
    guard let candidate = presentationIndex?.candidates[item.candidateID] else { return item.id.uuidString }
    // A ranking freezes its own exact mask; the current editor's latest mask
    // must never substitute for an offered root or older revision.
    return (document?.id.uuidString ?? "") + ":rank:" + item.id.uuidString + ":" + candidate.programHash
      + ":" + candidate.preview.sha256 + ":" + (item.revisionID?.uuidString ?? "root")
  }
  package func thumbnail(candidate: FlowPortfolioCandidate) async -> Data? {
    guard let store else { return nil }
    let revision = presentationIndex?.latestPrunes[candidate.id]
    let key = previewIdentity(candidate: candidate)
    return try? await FlowAuthoringThumbnailCache.shared.load(key: key) {
      let item = FlowPortfolioPresentationItem(id: revision?.id ?? candidate.id, candidateID: candidate.id,
        revisionID: revision?.id, sourceID: candidate.sourceID, removedIndices: revision?.removedIndices ?? [])
      return try await store.presentationPreview(item)
    }
  }
}

/// Encoded row thumbnails have a separate, bounded cost from decoded viewport
/// pixels. Both reads and thumbnail encodes coalesce under exact context keys.
package actor FlowAuthoringThumbnailCache {
  static let shared = FlowAuthoringThumbnailCache()
  private struct Flight { let id: UUID; let task: Task<Data, Error> }
  private var values: [String: Data] = [:]
  private var order: [String] = []
  private var flights: [String: Flight] = [:]
  private var bytes = 0
  private let maximumEntries: Int, maximumBytes: Int, maximumInflight: Int
  package init(maximumEntries: Int = 80, maximumBytes: Int = 16 * 1024 * 1024, maximumInflight: Int = 2) {
    self.maximumEntries = max(1, maximumEntries); self.maximumBytes = max(1, maximumBytes)
    self.maximumInflight = max(1, maximumInflight)
  }
  package var statistics: [String: Int] { ["entries": values.count, "encodedBytes": bytes, "inflight": flights.count] }
  package func load(key identity: String, read: @escaping @Sendable () async throws -> Data) async throws -> Data {
    let key = identity + ":thumbnail/png/oriented/280/v1"
    while true {
      try Task.checkCancellation()
      if let data = values[key] { touch(key); return data }
      if let flight = flights[key] {
        do {
          let data = try await flight.task.value; finish(key, flight: flight, data: data)
          try Task.checkCancellation(); return data
        } catch { finish(key, flight: flight, data: nil); throw error }
      }
      if flights.count >= maximumInflight, let pending = flights.first {
        let data = try? await pending.value.task.value
        finish(pending.key, flight: pending.value, data: data)
        continue
      }
      let worker = Task.detached(priority: .utility) {
        let original = try await read(); try Task.checkCancellation()
        guard UInt64(original.count) <= ExchangeCarrierLimits().maximumEncodedImageBytes,
          let source = CGImageSourceCreateWithData(original as CFData, nil),
          let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: 280,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true
          ] as CFDictionary) else { throw CocoaError(.fileReadCorruptFile) }
        let data = try PortraitImageAnalyzer.encodedImage(image)
        try Task.checkCancellation(); return data
      }
      let flight = Flight(id: UUID(), task: worker); flights[key] = flight
      do {
        let data = try await worker.value; finish(key, flight: flight, data: data)
        try Task.checkCancellation(); return data
      } catch { finish(key, flight: flight, data: nil); throw error }
    }
  }
  private func touch(_ key: String) { order.removeAll { $0 == key }; order.append(key) }
  private func finish(_ key: String, flight: Flight, data: Data?) {
    guard flights[key]?.id == flight.id else { return }
    flights.removeValue(forKey: key)
    guard let data, data.count <= maximumBytes else { return }
    values[key] = data; bytes += data.count; touch(key)
    while order.count > maximumEntries || bytes > maximumBytes {
      if let removed = values.removeValue(forKey: order.removeFirst()) { bytes -= removed.count }
    }
  }
}
