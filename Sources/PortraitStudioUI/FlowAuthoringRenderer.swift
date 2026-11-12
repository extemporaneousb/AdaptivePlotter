import CoreGraphics
import Foundation
import ImageIO
import PlotterModel
import PortraitArtists
import PortraitCore

/// One off-main worker retains expensive source analysis across a round.
package actor FlowAuthoringRenderer {
  package nonisolated static let analysisOptions = PortraitAnalysisOptions(cropToFace: true, removeBackground: true, faceCropMargin: 0.18)
  private var preparedSource: PortraitSourcePreparation?
  private var sourceHash: String?
  private var proposalRaster: PortraitRaster?

  package init() {}

  /// Recipe selection performs one cached source preparation, never a hidden
  /// drawing batch. The returned count is the complete rendering budget.
  package func proposals(data: Data, count: Int, seed: UInt64, parent: FlowArtistRecipe?,
    checkpoint: FlowArtistCheckpoint?) async throws -> [FlowArtistRecipe] {
    try Task.checkCancellation()
    if let checkpoint { try checkpoint.validateForInference() }
    let hash = DrawingArtifactCoding.sha256(data)
    if hash != sourceHash { preparedSource = nil; proposalRaster = nil; sourceHash = hash }
    if preparedSource == nil { preparedSource = try PortraitImageAnalyzer.prepareSource(data: data) }
    if proposalRaster == nil {
      proposalRaster = try PortraitImageAnalyzer.analyze(preparedSource: preparedSource!,
        options: Self.analysisOptions, maximumDimension: 320)
    }
    return try FlowArtistProposals.propose(count: count, seed: seed, parent: parent,
      raster: proposalRaster, checkpoint: checkpoint)
  }

  package func render(data: Data, recipe: FlowArtistRecipe, strokeStyle: StrokeStyle) async throws -> PortraitRenderResult {
    try await produce(data: data, recipe: recipe, strokeStyle: strokeStyle, nominalPenWidthMM: nil).artifacts
  }

  package func produce(data: Data, recipe: FlowArtistRecipe, strokeStyle: StrokeStyle,
    nominalPenWidthMM: Double?, parent: SourceLink<DrawingRef> = .none, photo: FrozenPhotoRecord? = nil) async throws -> DrawingProduction<PortraitRenderResult> {
    try Task.checkCancellation()
    let hash = DrawingArtifactCoding.sha256(data)
    if hash != sourceHash { preparedSource = nil; proposalRaster = nil; sourceHash = hash }
    do {
      let production = try await PortraitFlowDrawingProducer().produce(
        input: .init(data: data, preparedSource: preparedSource, parent: parent, photo: photo),
        settings: .init(recipe: recipe, analysisOptions: Self.analysisOptions,
          strokeStyle: strokeStyle, nominalPenWidthMM: nominalPenWidthMM))
      preparedSource = production.artifacts.preparedSource
      return production
    } catch let failure as PortraitPreparedRenderFailure {
      preparedSource = failure.preparedSource
      throw failure.underlyingError
    }
  }

  package static func preview(_ program: DrawingProgram, removed: Set<Int> = []) throws -> Data {
    try PortraitDrawingPreview.png(program, removed: removed)
  }
}
