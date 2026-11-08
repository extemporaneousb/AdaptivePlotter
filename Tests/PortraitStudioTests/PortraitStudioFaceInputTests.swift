import CoreGraphics
import Foundation
import ImageIO
import PortraitCore
@testable import PortraitArtists
import Testing
import UniformTypeIdentifiers

@Suite("Active portrait source orientation and mask evidence")
struct PortraitStudioFaceInputTests {
  private func noFace(_ image: CGImage) -> PortraitFaceAnalysis {
    .init(requestRevision: 1, constellation: 0, platformVersion: "synthetic-fixture", status: .noFace,
      unavailableReason: nil, decodedWidth: image.width, decodedHeight: image.height, boundingBox: nil,
      observationConfidence: nil, landmarksConfidence: nil, roll: nil, yaw: nil, pitch: nil, regions: [])
  }
  @Test("EXIF orientation precedes active source analysis while original encoded facts remain unchanged")
  func exifOrientation() throws {
    let image = try image(width: 20, height: 40) { _, _ in (128, 40, 20) }
    let data = NSMutableData(), destination = try #require(CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil))
    CGImageDestinationAddImage(destination, image, [kCGImagePropertyOrientation: 6] as CFDictionary)
    #expect(CGImageDestinationFinalize(destination))
    var dimensions: [Int] = []
    let source = try PortraitImageAnalyzer.prepareSource(data: data as Data, faceAnalyzer: { image in
      dimensions = [image.width, image.height]; return noFace(image)
    }, personMaskAnalyzer: { _ in .init(status: .notRequested, requestRevision: 0) })
    #expect(dimensions == [40, 20]); #expect(source.image.width == 40 && source.image.height == 20)
    let encoded = try PortraitDrawingImages.sourceAsset(data as Data)
    #expect(encoded.width == 20 && encoded.height == 40 && encoded.orientation == 6)
    #expect(encoded.asset.bytes == data as Data)
  }
  @Test("Asymmetric source mask is retained in the same top-left raster basis as luminance")
  func maskAlignment() throws {
    let bytes = try png(image(width: 20, height: 20) { _, y in y < 10 ? (0, 0, 0) : (220, 220, 220) })
    let mask = try grayMask(width: 20, height: 20) { _, y in y < 10 ? 255 : 0 }
    let source = try PortraitImageAnalyzer.prepareSource(data: bytes, faceAnalyzer: noFace,
      personMaskAnalyzer: { _ in .init(image: mask, status: .applied, requestRevision: 1) })
    let raster = try PortraitImageAnalyzer.analyze(preparedSource: source,
      options: .init(cropToFace: false, removeBackground: true), maximumDimension: 20)
    let alpha = try #require(raster.personMask?.alpha)
    #expect(raster.width == 20 && raster.height == 20)
    #expect(alpha[5 * 20 + 10] > 0.9 && alpha[15 * 20 + 10] < 0.1)
    #expect(raster.luminance[5 * 20 + 10] < 0.1 && raster.luminance[15 * 20 + 10] > 0.95)
    #expect(raster.analysisGeometry?.crop.x == 0 && raster.analysisGeometry?.crop.y == 0)
    try raster.validateAnalysisEvidence()
  }
  private func grayMask(width: Int, height: Int, pixel: (Int, Int) -> UInt8) throws -> CGImage {
    let bytes = Data((0..<height).flatMap { y in (0..<width).map { x in pixel(x, y) } })
    let provider = try #require(CGDataProvider(data: bytes as CFData))
    return try #require(CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 8,
      bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: 0),
      provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
  }

  private func image(width: Int, height: Int, pixel: (Int, Int) -> (UInt8, UInt8, UInt8)) throws -> CGImage {
    let bytes = Data((0..<height).flatMap { y in (0..<width).flatMap { x -> [UInt8] in
      let color = pixel(x, y); return [color.0, color.1, color.2, 255]
    } })
    let provider = try #require(CGDataProvider(data: bytes as CFData))
    return try #require(CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
      bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGBitmapInfo(rawValue: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue),
      provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
  }

  private func png(_ image: CGImage) throws -> Data {
    let output = NSMutableData()
    let destination = try #require(CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil))
    CGImageDestinationAddImage(destination, image, nil)
    #expect(CGImageDestinationFinalize(destination))
    return output as Data
  }

}
