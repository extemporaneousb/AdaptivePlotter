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

  package func render(data: Data, recipe: FlowArtistRecipe, strokeStyle: StrokeStyle) async throws -> PortraitRenderResult {
    try Task.checkCancellation()
    let hash = DrawingPackageCodec.sha256(data)
    if hash != sourceHash { preparedSource = nil; sourceHash = hash }
    do {
      let result = try await PortraitImageAnalyzer().render(.init(data: data, pose: .front, style: .flowEdges,
        options: Self.analysisOptions,
        strokeStyle: strokeStyle, vectorOptions: recipe.vectorOptions, preparedSource: preparedSource))
      preparedSource = result.preparedSource
      return result
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
