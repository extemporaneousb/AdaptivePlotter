import CoreGraphics
import CoreVideo
import CryptoKit
import Foundation
import Vision

/// Source-owned preparation, independent of crop, output resolution and style.
/// CGImages are immutable; this value crosses to the serial render worker only.
struct PortraitSourcePreparation: @unchecked Sendable {
  static let revision = 1

  struct Key: Hashable, Sendable {
    let contentDigest: String
    let suppliedSourcePixelExtent: PortraitSourceCropExtent?
    var revision = PortraitSourcePreparation.revision

    init(data: Data, sourcePixelExtent: PortraitSourceCropExtent?) {
      contentDigest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
      suppliedSourcePixelExtent = sourcePixelExtent
    }
  }

  struct PersonMask: @unchecked Sendable {
    let image: CGImage?
    let status: PortraitPersonMaskStatus
    let requestRevision: Int
    let unavailableReason: String?
  }

  /// Compact luminance levels are reused when resampling every framing. Crop
  /// coordinates stay on the decoded source; they are never rounded to a level.
  struct Level: Sendable {
    let width: Int
    let height: Int
    let luminance: [UInt8]
  }

  let key: Key
  let image: CGImage
  let sourcePixelExtent: PortraitSourceCropExtent
  let faceAnalysis: PortraitFaceAnalysis
  let personMask: PersonMask
  let levels: [Level]

  /// Retained pixel/array payload, rather than a source-count approximation.
  /// Images count their row strides, including padding. Shared image storage may
  /// be counted twice, which makes eviction conservative rather than optimistic.
  var retainedByteCount: Int {
    var bytes = image.bytesPerRow * image.height
    if let mask = personMask.image { bytes += mask.bytesPerRow * mask.height }
    for level in levels { bytes += level.luminance.count * MemoryLayout<UInt8>.stride }
    for region in faceAnalysis.regions {
      bytes += region.points.count * MemoryLayout<PortraitLandmarkPoint>.stride
      bytes += (region.precisionEstimates?.count ?? 0) * MemoryLayout<Double>.stride
    }
    bytes += key.contentDigest.utf8.count + faceAnalysis.platformVersion.utf8.count
    bytes += faceAnalysis.unavailableReason?.utf8.count ?? 0
    bytes += personMask.unavailableReason?.utf8.count ?? 0
    return bytes
  }

  func sample(crop: CGRect, width: Int, height: Int) throws
    -> (values: [Double], levelWidth: Int, levelHeight: Int) {
    try Task.checkCancellation()
    guard width > 0, height > 0, crop.width > 0, crop.height > 0,
      crop.minX >= 0, crop.minY >= 0, crop.maxX <= Double(image.width),
      crop.maxY <= Double(image.height), !levels.isEmpty
    else { throw PortraitDrawingError.unreadableImage }
    // Choose a level with at least one evidence pixel per output sample.
    // Integrating the complete footprint supplies the low-pass filter needed
    // for reduction; point/bilinear sampling alone would alias fine texture.
    let level = levels.last(where: {
      crop.width * Double($0.width) / Double(image.width) >= Double(width)
        && crop.height * Double($0.height) / Double(image.height) >= Double(height)
    }) ?? levels[0]
    let sx = Double(level.width) / Double(image.width)
    let sy = Double(level.height) / Double(image.height)
    var values = [Double](repeating: 0, count: width * height)
    for y in 0..<height {
      if y.isMultiple(of: 16) { try Task.checkCancellation() }
      let top = (crop.minY + Double(y) * crop.height / Double(height)) * sy
      let bottom = min(Double(level.height),
        (crop.minY + Double(y + 1) * crop.height / Double(height)) * sy)
      let firstY = max(0, min(level.height - 1, Int(floor(top))))
      let lastY = max(firstY, min(level.height - 1, Int(ceil(bottom)) - 1))
      for x in 0..<width {
        let left = (crop.minX + Double(x) * crop.width / Double(width)) * sx
        let right = min(Double(level.width),
          (crop.minX + Double(x + 1) * crop.width / Double(width)) * sx)
        let firstX = max(0, min(level.width - 1, Int(floor(left))))
        let lastX = max(firstX, min(level.width - 1, Int(ceil(right)) - 1))
        var total = 0.0, area = 0.0
        for row in firstY...lastY {
          let dy = max(0, min(bottom, Double(row + 1)) - max(top, Double(row)))
          for column in firstX...lastX {
            let dx = max(0, min(right, Double(column + 1)) - max(left, Double(column)))
            let weight = dx * dy
            total += Double(level.luminance[row * level.width + column]) * weight
            area += weight
          }
        }
        guard area > 0 else { throw PortraitDrawingError.unreadableImage }
        values[y * width + x] = min(1, max(0, total / (area * 255)))
      }
    }
    return (values, level.width, level.height)
  }
}

struct PortraitRenderTimings: Sendable {
  var sourceCacheHit = false
  var rasterCacheHit = false
  var sourceMS = 0.0
  var cropMS = 0.0
  var flowMS = 0.0
  var vectorMS = 0.0
}

extension PortraitImageAnalyzer {
  /// Dependencies are injectable for deterministic reuse/cancellation tests;
  /// production uses one full-frame Vision request for each analysis kind.
  static func prepareSource(data: Data, sourcePixelExtent: PortraitSourceCropExtent? = nil,
    faceAnalyzer: (CGImage) throws -> PortraitFaceAnalysis = PortraitFaceLandmarkAnalyzer.analyze,
    personMaskAnalyzer: (CGImage) throws -> PortraitSourcePreparation.PersonMask = preparePersonMask
  ) throws -> PortraitSourcePreparation {
    try Task.checkCancellation()
    let decoded = try decodedImage(from: data)
    let image = decoded.image
    let face = try faceAnalyzer(image)
    try Task.checkCancellation()
    let mask = try personMaskAnalyzer(image)
    try Task.checkCancellation()
    var levels: [PortraitSourcePreparation.Level] = []
    let maximum = max(image.width, image.height)
    var dimension = maximum
    repeat {
      let scale = Double(dimension) / Double(maximum)
      let width = max(1, Int((Double(image.width) * scale).rounded()))
      let height = max(1, Int((Double(image.height) * scale).rounded()))
      let luminance = try grayscale(image, width: width, height: height).map { UInt8(($0 * 255).rounded()) }
      levels.append(.init(width: width, height: height, luminance: luminance))
      dimension /= 2
    } while dimension >= 150
    try Task.checkCancellation()
    return PortraitSourcePreparation(key: .init(data: data, sourcePixelExtent: sourcePixelExtent),
      image: image, sourcePixelExtent: sourcePixelExtent ?? decoded.sourcePixelExtent,
      faceAnalysis: face, personMask: mask, levels: levels)
  }

  static func preparePersonMask(_ image: CGImage) throws -> PortraitSourcePreparation.PersonMask {
    try Task.checkCancellation()
    let request = VNGeneratePersonSegmentationRequest()
    request.qualityLevel = .accurate
    request.outputPixelFormat = kCVPixelFormatType_OneComponent8
    do {
      try VNImageRequestHandler(cgImage: image, orientation: .up).perform([request])
      try Task.checkCancellation()
      guard let buffer = request.results?.first?.pixelBuffer else {
        return .init(image: nil, status: .noPerson, requestRevision: request.revision,
          unavailableReason: "Vision returned no person mask")
      }
      return .init(image: try maskImage(buffer), status: .applied,
        requestRevision: request.revision, unavailableReason: nil)
    } catch is CancellationError { throw CancellationError() }
    catch {
      return .init(image: nil, status: .unavailable, requestRevision: request.revision,
        unavailableReason: error.localizedDescription)
    }
  }
}
