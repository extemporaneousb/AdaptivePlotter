import Foundation
import DrawingLibrary
import PortraitCore

extension FlowPortfolioStore {
  package func historyStatistics() throws -> FlowAuthoringHistoryStatistics { try history.statistics() }
  package func auditHistoryStatistics() throws -> FlowAuthoringHistoryStatistics { try history.auditStatistics() }
  package func setHistoryFault(_ fault: (@Sendable (FlowAuthoringHistoryBoundary) throws -> Void)?) { history.fault = fault }

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
    let material = try history.read(candidate: candidate, source: source, round: round, sourceBytes: bytes)
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
