import CoreGraphics
import Foundation
import ImageIO
import PlotterModel
import PortraitArtists
import PortraitCore

/// One off-main worker retains expensive source analysis across a round.
package actor FlowDojoRenderer {
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
    let hash = DrawingPackageCodec.sha256(data)
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
    try await produce(data: data, recipe: recipe, strokeStyle: strokeStyle, nominalPenWidthMM: 0.4).artifacts
  }

  package func produce(data: Data, recipe: FlowArtistRecipe, strokeStyle: StrokeStyle,
    nominalPenWidthMM: Double, parent: SourceLink<DrawingRef> = .none) async throws -> DrawingProduction<PortraitRenderResult> {
    try Task.checkCancellation()
    let hash = DrawingPackageCodec.sha256(data)
    if hash != sourceHash { preparedSource = nil; proposalRaster = nil; sourceHash = hash }
    do {
      let production = try await PortraitFlowDrawingProducer().produce(
        input: .init(data: data, preparedSource: preparedSource, parent: parent),
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
    let scale = 640 / max(program.fieldExtent.width, program.fieldExtent.height)
    let width = max(1, Int(ceil(program.fieldExtent.width * scale)))
    let height = max(1, Int(ceil(program.fieldExtent.height * scale)))
    guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
      bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
      throw DrawingTransferError.unavailable("Cannot create a drawing preview.")
    }
    context.setFillColor(CGColor(gray: 1, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    context.setStrokeColor(CGColor(gray: 0, alpha: 1)); context.setLineCap(.round); context.setLineJoin(.round)
    for (index, stroke) in program.strokes.enumerated() where !removed.contains(index) {
      guard let first = stroke.path.points.first else { continue }
      context.beginPath(); context.move(to: CGPoint(x: first.x * scale, y: first.y * scale))
      for point in stroke.path.points.dropFirst() { context.addLine(to: CGPoint(x: point.x * scale, y: point.y * scale)) }
      context.setLineWidth(stroke.style.nominalLineWidth * scale); context.strokePath()
    }
    let bytes = NSMutableData()
    guard let image = context.makeImage(), let destination = CGImageDestinationCreateWithData(bytes, "public.png" as CFString, 1, nil) else {
      throw DrawingTransferError.unavailable("Cannot encode a drawing preview.")
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { throw DrawingTransferError.unavailable("Preview encoding failed.") }
    return bytes as Data
  }
}
