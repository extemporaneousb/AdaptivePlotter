import Foundation
import CoreGraphics
import ImageIO
import PlotterModel
import PortraitCore

package enum PortraitDrawingPreview {
  package static func png(_ program: DrawingProgram, removed: Set<Int> = []) throws -> Data {
    let scale = 640 / max(program.fieldExtent.width, program.fieldExtent.height)
    let width = max(1, Int(ceil(program.fieldExtent.width * scale)))
    let height = max(1, Int(ceil(program.fieldExtent.height * scale)))
    guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
      bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
      throw DrawingExchangeError.malformed("Cannot create a drawing preview.")
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
      throw DrawingExchangeError.malformed("Cannot encode a drawing preview.")
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { throw DrawingExchangeError.malformed("Preview encoding failed.") }
    return bytes as Data
  }
}
