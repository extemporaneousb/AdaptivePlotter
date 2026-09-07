import CoreGraphics
import CoreVideo
import CryptoKit
import Foundation
import ImageIO
import UniformTypeIdentifiers
import Vision

struct PortraitAnalysisOptions: Hashable, Sendable {
  var cropToFace = true
  var removeBackground = true
}

/// Invoked on a worker task only after capture/import or an analysis option
/// changes. No continuous Vision requests run on either camera's preview path.
enum PortraitImageAnalyzer {
  static func image(from data: Data) throws -> CGImage {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil),
      let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceThumbnailMaxPixelSize: 1200,
      ] as CFDictionary)
    else { throw PortraitDrawingError.unreadableImage }
    return image
  }

  static func encodedImage(_ image: CGImage) throws -> Data {
    let data = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)
    else { throw PortraitDrawingError.unreadableImage }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { throw PortraitDrawingError.unreadableImage }
    return data as Data
  }

  static func analyze(data: Data, options: PortraitAnalysisOptions) throws -> PortraitRaster {
    let image = try image(from: data)
    var crop = CGRect(x: 0, y: 0, width: image.width, height: image.height)
    var notes: [String] = []
    if options.cropToFace {
      let faces = VNDetectFaceRectanglesRequest()
      do {
        try VNImageRequestHandler(cgImage: image, orientation: .up).perform([faces])
        if let face = faces.results?.max(by: { $0.boundingBox.width*$0.boundingBox.height < $1.boundingBox.width*$1.boundingBox.height }) {
          let bounds = face.boundingBox.insetBy(dx: -face.boundingBox.width * 0.35, dy: -face.boundingBox.height * 0.45)
          crop = CGRect(x: bounds.minX * Double(image.width), y: (1-bounds.maxY) * Double(image.height),
                        width: bounds.width * Double(image.width), height: bounds.height * Double(image.height))
            .intersection(crop).integral.intersection(crop)
          notes.append("Face crop")
        } else { notes.append("No face located; full photo") }
      } catch { notes.append("Face detection unavailable (\(error.localizedDescription)); full photo") }
    } else { notes.append("Full photo") }
    guard let cropped = image.cropping(to: crop) else { throw PortraitDrawingError.unreadableImage }
    let ratio = Double(cropped.width) / Double(cropped.height)
    let width = max(8, min(160, Int(160 * ratio)))
    let height = max(8, min(160, Int(160 / ratio)))
    var luminance = try grayscale(cropped, width: width, height: height)
    // Normalize illumination before whitening the background; the matte must
    // not bias the contrast percentiles toward white.
    let sorted = luminance.sorted()
    let low = sorted[sorted.count / 50], high = sorted[sorted.count * 49 / 50]
    if high - low > 0.05 {
      luminance = luminance.map { min(1, max(0, ($0-low)/(high-low))) }
    }
    if options.removeBackground {
      do {
        let request = VNGeneratePersonSegmentationRequest()
        request.qualityLevel = .accurate
        request.outputPixelFormat = kCVPixelFormatType_OneComponent8
        try VNImageRequestHandler(cgImage: image, orientation: .up).perform([request])
        if let buffer = request.results?.first?.pixelBuffer {
          let mask = try maskImage(buffer)
          let maskCrop = CGRect(
            x: crop.minX / Double(image.width) * Double(mask.width),
            y: crop.minY / Double(image.height) * Double(mask.height),
            width: crop.width / Double(image.width) * Double(mask.width),
            height: crop.height / Double(image.height) * Double(mask.height))
          if let croppedMask = mask.cropping(to: maskCrop) {
            let alpha = try grayscale(croppedMask, width: width, height: height)
            if alpha.contains(where: { $0 > 0.5 }) {
              luminance = zip(luminance, alpha).map { value, mask in 1 - mask*(1-value) }
              notes.append("Person background removed")
            } else { notes.append("No person mask; background retained") }
          } else { notes.append("Mask crop unavailable; background retained") }
        } else { notes.append("No person mask; background retained") }
      } catch { notes.append("Person masking unavailable (\(error.localizedDescription)); background retained") }
    }
    let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    let rasterDigest = SHA256.hash(data: Data(luminance.map { UInt8(($0*255).rounded()) }))
      .map { String(format: "%02x", $0) }.joined()
    return PortraitRaster(
      width: width, height: height, luminance: luminance,
      provenance: "image=\(digest)|raster=\(rasterDigest)|crop=\(crop)|size=\(width)x\(height)|face=\(options.cropToFace)|mask=\(options.removeBackground)",
      analysisSummary: notes.joined(separator: " · "))
  }

  static func grayscale(_ image: CGImage, width: Int, height: Int) throws -> [Double] {
    var bytes = [UInt8](repeating: 255, count: width*height)
    let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
      guard let context = CGContext(data: buffer.baseAddress, width: width, height: height,
                                    bitsPerComponent: 8, bytesPerRow: width,
                                    space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)
      else { return false }
      context.interpolationQuality = .high
      context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
      return true
    }
    guard drawn else { throw PortraitDrawingError.unreadableImage }
    return bytes.map { Double($0) / 255 }
  }

  private static func maskImage(_ buffer: CVPixelBuffer) throws -> CGImage {
    CVPixelBufferLockBaseAddress(buffer, .readOnly)
    defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
    guard let address = CVPixelBufferGetBaseAddress(buffer) else { throw PortraitDrawingError.unreadableImage }
    let rowBytes = CVPixelBufferGetBytesPerRow(buffer), height = CVPixelBufferGetHeight(buffer)
    let data = Data(bytes: address, count: rowBytes*height)
    guard let provider = CGDataProvider(data: data as CFData),
      let image = CGImage(width: CVPixelBufferGetWidth(buffer), height: height,
                          bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: rowBytes,
                          space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: 0),
                          provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    else { throw PortraitDrawingError.unreadableImage }
    return image
  }
}
