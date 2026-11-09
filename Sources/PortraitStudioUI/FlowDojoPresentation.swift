import AppKit
import Foundation
import ImageIO
import PortraitArtists
import PortraitLibrary
import PortraitCore

/// Stable names and ancestry are projections of durable identities. Browsing
/// them never declares artistic preference or creates another drawing.
extension FlowDojoModel {
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
    let siblings = document?.candidates.filter { $0.sourceID == value.sourceID } ?? []
    return "Drawing \((siblings.firstIndex(where: { $0.id == value.id }) ?? 0) + 1)"
  }
  package func roundName(_ value: FlowPortfolioRound) -> String {
    let siblings = document?.rounds.filter { $0.sourceID == value.sourceID } ?? []
    return "Set \((siblings.firstIndex(where: { $0.id == value.id }) ?? 0) + 1)"
  }
  package var currentBranch: String {
    guard let round else { return "Start a broad set for this photo" }
    if let id = round.parentCandidateID, let parent = document?.candidates.first(where: { $0.id == id }) {
      return roundName(round) + " · refined from " + drawingName(parent)
    }
    return roundName(round) + " · broad exploration"
  }
  package var branchAncestors: [FlowPortfolioCandidate] {
    guard let document else { return [] }
    var next = round?.parentCandidateID, result: [FlowPortfolioCandidate] = [], seen = Set<UUID>()
    while let id = next, seen.insert(id).inserted,
      let parent = document.candidates.first(where: { $0.id == id }) {
      result.append(parent); next = parent.parentCandidateID
    }
    return result.reversed()
  }
  package func branchDepth(_ round: FlowPortfolioRound) -> Int {
    guard let document else { return 0 }
    var next = round.parentCandidateID, seen = Set<UUID>()
    while let id = next, seen.insert(id).inserted { next = document.candidates.first(where: { $0.id == id })?.parentCandidateID }
    return seen.count
  }

  package func branches(for sourceID: UUID) -> [FlowPortfolioRound] {
    guard let document else { return [] }
    let rounds = document.rounds.filter { $0.sourceID == sourceID }
    let candidates = Dictionary(uniqueKeysWithValues: document.candidates.map { ($0.id, $0) })
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
    for ranking in document.latestRankings.reversed() where !ranking.skipped && !ranking.neither {
      guard let tier = ranking.orderedGroups.first,
        let presentation = document.presentations.first(where: { $0.id == ranking.presentationID }),
        let item = presentation.items.first(where: { $0.sourceID == sourceID && tier.contains($0.id) }) else { continue }
      return item
    }
    for choice in document.choices.reversed() {
      if let item = choice.offeredItems.first(where: { $0.id == choice.selectedItemID && $0.sourceID == sourceID }) { return item }
    }
    let candidates = document.candidates.filter { $0.sourceID == sourceID }, ids = Set(candidates.map(\.id))
    if let edit = document.pruneRevisions.last(where: { ids.contains($0.candidateID) }) {
      return .init(id: edit.id, candidateID: edit.candidateID, revisionID: edit.id, sourceID: sourceID, removedIndices: edit.removedIndices)
    }
    guard let first = candidates.first else { return nil }
    return FlowPortfolioPresentationItem(id: first.id, candidateID: first.id, revisionID: nil, sourceID: sourceID, removedIndices: [])
  }
  package func representativeKey(_ source: FlowPortfolioSource) -> String {
    let prefix = (document?.id.uuidString ?? "") + ":" + source.id.uuidString
    guard let item = representative(for: source.id),
      let candidate = document?.candidates.first(where: { $0.id == item.candidateID }) else { return prefix + source.image.sha256 }
    return prefix + ":" + item.id.uuidString + ":" + candidate.programHash
  }
  package func representativeThumbnail(_ source: FlowPortfolioSource) async -> Data? {
    guard let item = representative(for: source.id), let store else { return await thumbnail(source: source) }
    let key = representativeKey(source)
    return try? await FlowDojoThumbnailCache.shared.load(key: key) {
      try await store.presentationPreview(item)
    }
  }

  package func thumbnail(source: FlowPortfolioSource) async -> Data? {
    guard let store else { return nil }
    return try? await FlowDojoThumbnailCache.shared.load(key: "source:" + source.image.sha256) {
      try await store.sourceData(source.id)
    }
  }
  package func previewIdentity(candidate: FlowPortfolioCandidate, revisionID: UUID? = nil) -> String {
    let revision = revisionID ?? document?.latestPrune(candidateID: candidate.id)?.id
    let source = document?.sources.first { $0.id == candidate.sourceID }?.image.sha256 ?? "no-source"
    return (document?.id.uuidString ?? "") + ":" + source + ":" + candidate.id.uuidString
      + ":" + candidate.programHash + ":" + candidate.preview.sha256 + ":" + (revision?.uuidString ?? "root")
  }
  package func rankingPreviewIdentity(_ item: FlowPortfolioPresentationItem) -> String {
    guard let candidate = document?.candidates.first(where: { $0.id == item.candidateID }) else { return item.id.uuidString }
    // A ranking freezes its own exact mask; the current editor's latest mask
    // must never substitute for an offered root or older revision.
    return (document?.id.uuidString ?? "") + ":rank:" + item.id.uuidString + ":" + candidate.programHash
      + ":" + candidate.preview.sha256 + ":" + (item.revisionID?.uuidString ?? "root")
  }
  package func thumbnail(candidate: FlowPortfolioCandidate) async -> Data? {
    guard let store else { return nil }
    let revision = document?.latestPrune(candidateID: candidate.id)
    let key = previewIdentity(candidate: candidate)
    return try? await FlowDojoThumbnailCache.shared.load(key: key) {
      let item = FlowPortfolioPresentationItem(id: revision?.id ?? candidate.id, candidateID: candidate.id,
        revisionID: revision?.id, sourceID: candidate.sourceID, removedIndices: revision?.removedIndices ?? [])
      return try await store.presentationPreview(item)
    }
  }
}

/// Encoded row thumbnails have a separate, bounded cost from decoded viewport
/// pixels. Both reads and thumbnail encodes coalesce under exact context keys.
package actor FlowDojoThumbnailCache {
  static let shared = FlowDojoThumbnailCache()
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
