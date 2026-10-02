import CoreGraphics
import Foundation
import ImageIO

/// Describes selection of an original camera frame, not a reconstructed image
/// or evidence of a camera focus adjustment.
struct PortraitCaptureSelectionProvenance: Codable, Sendable, Equatable {
  enum Method: String, Codable, Sendable {
    case sharpnessAndExposure
    case latestAvailable
  }

  let capturedFrameCount: Int
  let evaluatedFrameCount: Int
  let method: Method
  let selectedSharpness: Double?
  let selectedMeanLuminance: Double?
  let selectedClippedFraction: Double?
}

enum PortraitBurstSelector {
  static let maximumEvaluatedFrames = 8
  static let maximumThumbnailDimension = 128
  static let maximumEncodedFrameBytes = 8 * 1_024 * 1_024

  /// Score only bounded thumbnails, then return the exact source bytes, frame
  /// identity and pixel extent. Equal scores favor the later, more settled frame.
  static func select(from samples: [PortraitBurstSample]) throws -> PortraitBurstSample? {
    try Task.checkCancellation()
    guard let fallback = samples.last else { return nil }
    var chosen = fallback
    var bestQuality: Quality?
    var evaluatedCount = 0
    for sample in samples.suffix(maximumEvaluatedFrames) {
      try Task.checkCancellation()
      guard let quality = try measure(sample.data) else { continue }
      evaluatedCount += 1
      if quality.score >= (bestQuality?.score ?? -.infinity) {
        chosen = sample
        bestQuality = quality
      }
    }
    try Task.checkCancellation()
    chosen.selectionProvenance = PortraitCaptureSelectionProvenance(
      capturedFrameCount: samples.count, evaluatedFrameCount: evaluatedCount,
      method: bestQuality == nil ? .latestAvailable : .sharpnessAndExposure,
      selectedSharpness: bestQuality?.sharpness,
      selectedMeanLuminance: bestQuality?.meanLuminance,
      selectedClippedFraction: bestQuality?.clippedFraction)
    return chosen
  }

  private struct Quality {
    let sharpness: Double
    let meanLuminance: Double
    let clippedFraction: Double

    var score: Double {
      // Exposure gates the edge score so clipped noise cannot beat a usable
      // frame merely by containing more high-frequency contrast.
      let exposure = max(0, min(1, min(meanLuminance, 1 - meanLuminance) / 0.2))
      let usableFraction = 1 - clippedFraction
      return exposure * usableFraction * usableFraction * (0.1 + min(1, sqrt(sharpness)))
    }
  }

  private static func measure(_ data: Data) throws -> Quality? {
    guard data.count <= maximumEncodedFrameBytes,
      let source = CGImageSourceCreateWithData(data as CFData,
        [kCGImageSourceShouldCache: false] as CFDictionary),
      let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceShouldCacheImmediately: true,
        kCGImageSourceThumbnailMaxPixelSize: maximumThumbnailDimension,
      ] as CFDictionary), image.width >= 4, image.height >= 4 else { return nil }
    try Task.checkCancellation()
    let width = image.width, height = image.height
    var pixels = [UInt8](repeating: 0, count: width * height)
    let rendered = pixels.withUnsafeMutableBytes { buffer -> Bool in
      guard let context = CGContext(data: buffer.baseAddress, width: width, height: height,
        bitsPerComponent: 8, bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(),
        bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return false }
      context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
      return true
    }
    guard rendered else { return nil }

    // Center-weight the score by excluding the outer eighth, reducing the
    // influence of a sharp background while the subject is slightly blurred.
    let xRange = max(1, width / 8)..<min(width - 1, width - width / 8)
    let yRange = max(1, height / 8)..<min(height - 1, height - height / 8)
    var count = 0, clipped = 0
    var luminanceSum = 0.0, laplacianSum = 0.0, laplacianSquaredSum = 0.0
    for y in yRange {
      try Task.checkCancellation()
      for x in xRange {
        let index = y * width + x
        let value = Double(pixels[index]) / 255
        let laplacian = (Double(pixels[index - 1]) + Double(pixels[index + 1])
          + Double(pixels[index - width]) + Double(pixels[index + width])) / 255 - 4 * value
        luminanceSum += value
        laplacianSum += laplacian
        laplacianSquaredSum += laplacian * laplacian
        if value <= 0.02 || value >= 0.98 { clipped += 1 }
        count += 1
      }
    }
    guard count > 0 else { return nil }
    let countDouble = Double(count), meanLaplacian = laplacianSum / countDouble
    return Quality(sharpness: max(0, laplacianSquaredSum / countDouble - meanLaplacian * meanLaplacian),
      meanLuminance: luminanceSum / countDouble, clippedFraction: Double(clipped) / countDouble)
  }
}
