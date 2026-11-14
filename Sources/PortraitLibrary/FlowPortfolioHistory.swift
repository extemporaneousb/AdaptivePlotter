import Foundation
import DrawingLibrary
import PortraitCore

extension FlowPortfolioStore {
  package func historyStatistics() throws -> FlowAuthoringHistoryStatistics {
    let entries = state.candidates.filter { $0.authoringClosure != nil }
    let common = entries.filter { $0.authoringClosureLocation != nil }
    var unique: [String: Int] = [:]
    func add(_ value: FlowPortfolioBlob) throws {
      if let prior = unique[value.sha256], prior != value.byteCount { throw FlowPortfolioError.invalid("Conflicting history asset lengths.") }
      unique[value.sha256] = value.byteCount
    }
    for candidate in common {
      if let manifest = candidate.authoringClosure { try add(manifest) }
      for part in candidate.authoringClosureLocation?.parts ?? [] { try add(part) }
    }
    return .init(entryCount: entries.count, byteCount: unique.values.reduce(0, +),
      libraryEntryCount: common.count, legacyEntryCount: entries.count - common.count)
  }
  /// Audits unique committed CAS objects in bounded batches, not historical directories.
  package func auditHistoryStatistics() async throws -> FlowAuthoringHistoryStatistics {
    var unique: [String: FlowPortfolioBlob] = [:]
    for candidate in state.candidates where candidate.authoringClosureLocation != nil {
      if let manifest = candidate.authoringClosure { unique[manifest.sha256] = manifest }
      for part in candidate.authoringClosureLocation?.parts ?? [] { unique[part.sha256] = part }
    }
    var batch: [ExchangeCatalogFile] = [], bytes = 0
    var limits = ExchangeCarrierLimits(); limits.maximumEntries = 128
    limits.maximumExpandedBytes = UInt64(FlowAuthoringHistory.maximumRehydrationBytes)
    let readLimits = limits
    func audit(_ values: [ExchangeCatalogFile]) async throws {
      guard !values.isEmpty else { return }
      let files = try await library.assetFiles(values, limits: readLimits); try files.verifyInventory()
    }
    for value in unique.values {
      if batch.count == 128 || value.byteCount > FlowAuthoringHistory.maximumRehydrationBytes - bytes {
        try await audit(batch); batch = []; bytes = 0
      }
      let digest = try ExchangeDigest(value.sha256)
      batch.append(.init(path: "data/objects/sha256/" + value.sha256, storagePath: "", digest: digest, byteLength: UInt64(value.byteCount)))
      bytes += value.byteCount
    }
    try await audit(batch); return try historyStatistics()
  }
  package func setHistoryFault(_ fault: (@Sendable (FlowAuthoringHistoryBoundary) throws -> Void)?) { historyFault = fault }

  /// Exact disk material replaces only a missing hot-tier entry. No rendering,
  /// retention, selection or feedback action is implied by rehydration.
  func restoreHistoryCandidate(_ id: UUID) async throws {
    guard temporaryDrawings[id] == nil,
      let candidate = state.candidates.first(where: { $0.id == id }),
      candidate.drawing == nil, candidate.authoringClosure != nil else { return }
    guard let source = state.sources.first(where: { $0.id == candidate.sourceID }),
      let round = state.rounds.first(where: { $0.id == candidate.roundID }) else {
      throw FlowPortfolioError.unavailable("Authoring history has lost its source or round.")
    }
    let bytes = try await sourceData(source.id)
    let material = try await history.read(candidate: candidate, source: source, round: round, sourceBytes: bytes, library: library)
    let drawing: Drawing
    if let original = material.originalReference {
      drawing = try await library.drawing(original)
      guard drawing.program == material.drawing.program, drawing.producer == material.drawing.producer,
        drawing.input == material.drawing.input, drawing.parent == material.drawing.parent,
        drawing.units == material.drawing.units else { throw DrawingExchangeError.mismatchedParent }
    } else { drawing = material.drawing }
    if case .present(let parent) = drawing.parent { _ = try await library.drawing(parent) }
    try admitTemporaryDrawing(drawing, input: material.input)
    try admitTemporaryArtifacts([material.rasterBytes, material.preview])
    guard try storage.retain(material.rasterBytes, mediaType: "application/json") == candidate.raster,
      try storage.retain(material.preview, mediaType: "image/png") == candidate.preview else {
      throw FlowPortfolioError.invalid("Authoring history raster or preview differs from its candidate.")
    }
    temporaryDrawings[id] = drawing
    if let input = material.input { drawingInputs[id] = input }
  }
}
