import CoreGraphics
import Foundation
import ImageIO
import PortraitCore
import Testing
import UniformTypeIdentifiers
@testable import PortraitStudio

@Suite("Fixed face conditioning")
struct PortraitStudioFaceInputTests {
  @Test("Face height and position are fixed while source aspect and scale are preserved")
  func uniformGeometry() throws {
    let first = try PortraitStudioArtistInput.framing(face: CGRect(x: 100, y: 200, width: 80, height: 100),
      orientedWidth: 600, orientedHeight: 800)
    let second = try PortraitStudioArtistInput.framing(face: CGRect(x: 10, y: 20, width: 60, height: 100),
      orientedWidth: 600, orientedHeight: 800)
    #expect(abs(first.faceInTarget.height - 1024 * 0.52) < 0.000_001)
    #expect(abs(first.faceInTarget.midX - 512) < 0.000_001)
    #expect(abs(first.faceInTarget.midY - 1024 * 0.54) < 0.000_001)
    #expect(first.faceInTarget.height == second.faceInTarget.height)
    #expect(abs(first.faceInTarget.width / first.faceInTarget.height - 0.8) < 0.000_001)
    #expect(abs(second.faceInTarget.width / second.faceInTarget.height - 0.6) < 0.000_001)
    #expect(first.crop.width == first.crop.height)
    #expect(second.crop.minX < 0)
    #expect(second.crop.minY < 0)
  }

  @Test("Edge faces keep fixed geometry with explicit white padding instead of crop clamping")
  func edgePadding() throws {
    let source = try png(image(width: 20, height: 20) { _, _ in (255, 0, 0) })
    let prepared = try PortraitStudioArtistInput.prepare(source,
      faceOverride: .init(x: 0, y: 0, width: 10, height: 10, declaration: "synthetic edge fixture"),
      maskGenerator: { _ in try centralMask() })
    let framed = try rgba(prepared.framedSourcePNG.bytes)
    #expect(pixel(framed, x: 100, y: 512) == [255, 255, 255, 255])
    #expect(pixel(framed, x: 512, y: 100) == [255, 255, 255, 255])
    #expect(pixel(framed, x: 512, y: 512) == [255, 0, 0, 255])
    let metadata = try #require(try JSONSerialization.jsonObject(with: prepared.preparationJSON) as? [String: Any])
    let pad = try #require(metadata["padding_target_pixels"] as? [String: Double])
    #expect(pad["left", default: 0] > 0 && pad["top", default: 0] > 0)
  }

  @Test("Nonfinite, out-of-bounds and overwide explicit faces are refused")
  func invalidGeometry() {
    for face in [CGRect(x: Double.nan, y: 1, width: 10, height: 10),
      CGRect(x: -1, y: 1, width: 10, height: 10), CGRect(x: 95, y: 1, width: 10, height: 10),
      CGRect(x: 1, y: 1, width: 80, height: 10)] {
      #expect(throws: DrawingTransferError.self) {
        try PortraitStudioArtistInput.framing(face: face, orientedWidth: 100, orientedHeight: 100)
      }
    }
  }

  @Test("Asymmetric foreground stays aligned with top-left source colors and exact retained assets")
  func asymmetricMaskAndSourceOrientation() throws {
    let source = try image(width: 20, height: 20) { _, y in
      y < 10 ? (255, 0, 0) : (0, 0, 255)
    }
    let bytes = try png(source)
    let prepared = try PortraitStudioArtistInput.prepare(bytes,
      faceOverride: .init(x: 5, y: 5, width: 10, height: 10, declaration: "synthetic geometry fixture"),
      maskGenerator: { _ in try grayMask(width: 32, height: 32) { x, y in x >= 4 && x < 28 && y >= 4 && y < 23 ? 255 : 0 } })
    #expect(prepared.source.bytes == bytes)
    #expect(prepared.squarePNG.pixelWidth == 1024 && prepared.squarePNG.pixelHeight == 1024)
    #expect(prepared.foregroundMaskPNG.pixelWidth == 32 && prepared.foregroundMaskPNG.pixelHeight == 32)
    let pixels = try rgba(prepared.squarePNG.bytes)
    #expect(pixel(pixels, x: 512, y: 300) == [255, 0, 0, 255])
    #expect(pixel(pixels, x: 512, y: 680) == [0, 0, 255, 255])
    #expect(pixel(pixels, x: 512, y: 900) == [255, 255, 255, 255])
    #expect(pixel(pixels, x: 30, y: 300) == [255, 255, 255, 255])
    let metadata = try #require(try JSONSerialization.jsonObject(with: prepared.preparationJSON) as? [String: Any])
    #expect(metadata["revision"] as? String == PortraitStudioArtistInput.preparationRevision)
    #expect(metadata["mask_sha256"] as? String == prepared.foregroundMaskPNG.sha256)
    #expect(metadata["framed_source_sha256"] as? String == prepared.framedSourcePNG.sha256)
    #expect(metadata["prepared_source_sha256"] as? String == prepared.squarePNG.sha256)
    #expect(metadata["face_request_performed"] as? Bool == false)
    let affine = try #require(metadata["affine_top_left"] as? [Double])
    #expect(affine[0] == affine[3] && affine[1] == 0 && affine[2] == 0)
  }

  @Test("EXIF is applied before face selection while the encoded source remains unchanged")
  func exifOrientation() throws {
    let source = try image(width: 20, height: 40) { _, _ in (128, 40, 20) }
    let data = NSMutableData()
    let destination = try #require(CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil))
    CGImageDestinationAddImage(destination, source, [kCGImagePropertyOrientation: 6] as CFDictionary)
    #expect(CGImageDestinationFinalize(destination))
    var detectedDimensions: [Int] = []
    let prepared = try PortraitStudioArtistInput.prepare(data as Data, faceDetector: { image in
      detectedDimensions = [image.width, image.height]
      return [.init(rectangle: CGRect(x: 10, y: 5, width: 10, height: 10), confidence: 0.9)]
    }, maskGenerator: { _ in try centralMask() })
    #expect(detectedDimensions == [40, 20])
    #expect(prepared.source.bytes == data as Data)
    #expect(prepared.source.pixelWidth == 20 && prepared.source.pixelHeight == 40)
    let metadata = try #require(try JSONSerialization.jsonObject(with: prepared.preparationJSON) as? [String: Any])
    #expect(metadata["original_exif_orientation"] as? Int == 6)
    #expect(metadata["oriented_width"] as? Int == 40)
    #expect(metadata["oriented_height"] as? Int == 20)
  }

  @Test("Multiple faces require an explicit selection and never select the first observation")
  func ambiguousFaceRefusal() throws {
    let source = try png(image(width: 20, height: 20) { _, _ in (30, 40, 50) })
    var maskCalled = false
    #expect(throws: DrawingTransferError.unavailable(
      "Multiple faces were detected. Select one with an explicit oriented face rectangle.")) {
      try PortraitStudioArtistInput.prepare(source, faceDetector: { _ in [
        .init(rectangle: CGRect(x: 1, y: 1, width: 4, height: 4), confidence: 0.8),
        .init(rectangle: CGRect(x: 12, y: 12, width: 4, height: 4), confidence: 0.9)]
      }, maskGenerator: { _ in maskCalled = true; return try centralMask() })
    }
    #expect(!maskCalled)
  }

  @Test("Low confidence observations do not admit segmentation or an implicit full-frame fallback")
  func lowConfidenceRefusal() throws {
    let source = try png(image(width: 20, height: 20) { _, _ in (30, 40, 50) })
    var maskCalled = false
    #expect(throws: DrawingTransferError.unavailable(
      "No confident face was detected. Supply an explicit oriented face rectangle.")) {
      try PortraitStudioArtistInput.prepare(source, faceDetector: { _ in [
        .init(rectangle: CGRect(x: 1, y: 1, width: 4, height: 4), confidence: 0.49)]
      }, maskGenerator: { _ in maskCalled = true; return try centralMask() })
    }
    #expect(!maskCalled)
  }

  @Test("Missing declaration and empty, uniform or face-excluding masks cannot publish a prepared input")
  func unusableMaskRefusal() throws {
    let source = try png(image(width: 20, height: 20) { _, _ in (30, 40, 50) })
    #expect(throws: DrawingTransferError.self) {
      try PortraitStudioArtistInput.prepare(source,
        faceOverride: .init(x: 5, y: 5, width: 10, height: 10, declaration: " "),
        maskGenerator: { _ in try centralMask() })
    }
    for mode in 0..<3 {
      #expect(throws: DrawingTransferError.unavailable(
        "Person segmentation did not produce a usable foreground mask covering the selected face.")) {
        try PortraitStudioArtistInput.prepare(source,
          faceOverride: .init(x: 5, y: 5, width: 10, height: 10, declaration: "synthetic mask refusal fixture"),
          maskGenerator: { _ in try grayMask(width: 32, height: 32) { x, _ in
            mode == 0 ? 0 : (mode == 1 ? 255 : (x < 2 ? 255 : 0))
          } })
      }
    }
  }

  private func centralMask() throws -> CGImage {
    try grayMask(width: 32, height: 32) { x, y in x >= 4 && x < 28 && y >= 4 && y < 30 ? 255 : 0 }
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

  private func rgba(_ bytes: Data) throws -> [UInt8] {
    let source = try #require(CGImageSourceCreateWithData(bytes as CFData, nil))
    let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
    var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
    let success = pixels.withUnsafeMutableBytes { storage in
      guard let context = CGContext(data: storage.baseAddress, width: image.width, height: image.height,
        bitsPerComponent: 8, bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
      context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
      return true
    }
    #expect(success)
    return pixels
  }

  private func pixel(_ bytes: [UInt8], x: Int, y: Int) -> [UInt8] {
    Array(bytes[((y * 1024 + x) * 4)..<((y * 1024 + x) * 4 + 4)])
  }
}
