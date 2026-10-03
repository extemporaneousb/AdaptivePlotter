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

  private struct SampleSpan {
    let first: Int
    let offset: Int
    let count: Int
  }

  /// Pixel overlap is separable: each column's weights are the same on every
  /// row. Retain the exact scalar weights and summation order, including zeros.
  private static func sampleSpans(origin: Double, extent: Double, scale: Double,
    samples: Int, limit: Int) -> (spans: [SampleSpan], weights: [Double]) {
    var spans: [SampleSpan] = [], weights: [Double] = []
    spans.reserveCapacity(samples)
    for index in 0..<samples {
      let start = (origin + Double(index) * extent / Double(samples)) * scale
      let end = min(Double(limit), (origin + Double(index + 1) * extent / Double(samples)) * scale)
      let first = max(0, min(limit - 1, Int(floor(start))))
      let last = max(first, min(limit - 1, Int(ceil(end)) - 1))
      spans.append(.init(first: first, offset: weights.count, count: last - first + 1))
      for pixel in first...last {
        weights.append(max(0, min(end, Double(pixel + 1)) - max(start, Double(pixel))))
      }
    }
    return (spans, weights)
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
    let columns = Self.sampleSpans(origin: crop.minX, extent: crop.width, scale: sx,
      samples: width, limit: level.width)
    let rows = Self.sampleSpans(origin: crop.minY, extent: crop.height, scale: sy,
      samples: height, limit: level.height)
    // Span construction bounds every address to the selected level. No pointer
    // escapes these scopes; cancellation still settles at each 16-row boundary.
    try level.luminance.withUnsafeBufferPointer { source in
      try values.withUnsafeMutableBufferPointer { target in
        try columns.spans.withUnsafeBufferPointer { columnSpans in
          try rows.spans.withUnsafeBufferPointer { rowSpans in
            try columns.weights.withUnsafeBufferPointer { columnWeights in
              try rows.weights.withUnsafeBufferPointer { rowWeights in
                let input = source.baseAddress!, output = target.baseAddress!
                let xs = columnSpans.baseAddress!, ys = rowSpans.baseAddress!
                let dxs = columnWeights.baseAddress!, dys = rowWeights.baseAddress!
                var y = 0
                while y < height {
                  if y.isMultiple(of: 16) { try Task.checkCancellation() }
                  let row = ys[y]
                  var x = 0
                  while x < width {
                    let column = xs[x]
                    var total = 0.0, area = 0.0, ry = 0
                    while ry < row.count {
                      let dy = dys[row.offset + ry]
                      let base = (row.first + ry) * level.width + column.first
                      var cx = 0
                      while cx < column.count {
                        let weight = dxs[column.offset + cx] * dy
                        total += Double(input[base + cx]) * weight
                        area += weight
                        cx += 1
                      }
                      ry += 1
                    }
                    guard area > 0 else { throw PortraitDrawingError.unreadableImage }
                    output[y * width + x] = min(1, max(0, total / (area * 255)))
                    x += 1
                  }
                  y += 1
                }
              }
            }
          }
        }
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
      let luminance = try grayscaleBytes(image, width: width, height: height)
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
