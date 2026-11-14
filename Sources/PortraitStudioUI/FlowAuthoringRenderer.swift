import CoreGraphics
import Foundation
import ImageIO
import PlotterModel
import PortraitArtists
import PortraitCore

/// One off-main worker retains expensive source analysis across a round.
package actor FlowAuthoringRenderer {
  package nonisolated static let analysisOptions = PortraitAnalysisOptions(cropToFace: true, removeBackground: true, faceCropMargin: 0.18)
  private let preparationCache = PortraitFlowPreparationCache()

  package init() {}

  /// Recipe selection performs one cached source preparation, never a hidden
  /// drawing batch. The returned count is the complete rendering budget.
  package func proposals(data: Data, count: Int, seed: UInt64, parent: FlowArtistRecipe?,
    checkpoint: FlowArtistCheckpoint?, analysisOptions: PortraitAnalysisOptions = FlowAuthoringRenderer.analysisOptions,
    refinementRadius: Double = 0.06, photoReference: PhotoRef? = nil) async throws -> [FlowArtistRecipe] {
    try Task.checkCancellation()
    if let checkpoint { try checkpoint.validateForInference() }
    let raster = try await preparationCache.analyzedRaster(data: data, options: analysisOptions, photoReference: photoReference)
    return try FlowArtistProposals.propose(count: count, seed: seed, parent: parent,
      raster: raster, checkpoint: checkpoint, refinementRadius: refinementRadius)
  }

  package func render(data: Data, recipe: FlowArtistRecipe, strokeStyle: StrokeStyle) async throws -> PortraitRenderResult {
    try await produce(data: data, recipe: recipe, strokeStyle: strokeStyle, nominalPenWidthMM: nil).artifacts
  }

  package func produce(data: Data, recipe: FlowArtistRecipe, strokeStyle: StrokeStyle,
    nominalPenWidthMM: Double?, parent: SourceLink<DrawingRef> = .none, photo: FrozenPhotoRecord? = nil,
    analysisOptions: PortraitAnalysisOptions = FlowAuthoringRenderer.analysisOptions) async throws -> DrawingProduction<PortraitRenderResult> {
    try Task.checkCancellation()
    return try await PortraitFlowDrawingProducer().produce(
      input: .init(data: data, parent: parent, photo: photo),
      settings: .init(recipe: recipe, analysisOptions: analysisOptions,
        strokeStyle: strokeStyle, nominalPenWidthMM: nominalPenWidthMM),
      preparationCache: preparationCache)
  }

  package static func preview(_ program: DrawingProgram, removed: Set<Int> = []) throws -> Data {
    try PortraitDrawingPreview.png(program, removed: removed)
  }
}
