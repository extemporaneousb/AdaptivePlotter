import Foundation
import PlotterModel

public struct PixelRect: Codable, Hashable, Sendable {
  public let x: Int
  public let y: Int
  public let width: Int
  public let height: Int

  public init(x: Int, y: Int, width: Int, height: Int) {
    self.x = x
    self.y = y
    self.width = width
    self.height = height
  }
}

public struct GreenPixelThresholds: Codable, Hashable, Sendable {
  public let minimumGreen: UInt8
  public let minimumGreenExcess: UInt8

  /// Values are experiment inputs, not accepted product thresholds.
  public init(minimumGreen: UInt8, minimumGreenExcess: UInt8) {
    self.minimumGreen = minimumGreen
    self.minimumGreenExcess = minimumGreenExcess
  }
}

public enum MeasurementRequest: Codable, Hashable, Sendable {
  case statistics(region: PixelRect, algorithmRevision: String)
  case greenInk(region: PixelRect, thresholds: GreenPixelThresholds, algorithmRevision: String)
  case darkOcclusion(region: PixelRect, maximumLuma: UInt8, algorithmRevision: String)

  public var algorithmRevision: String {
    switch self {
    case .statistics(_, let revision), .greenInk(_, _, let revision),
      .darkOcclusion(_, _, let revision):
      revision
    }
  }

  public var region: PixelRect {
    switch self {
    case .statistics(let region, _), .greenInk(let region, _, _), .darkOcclusion(let region, _, _):
      region
    }
  }
}

public struct PixelPoint: Codable, Hashable, Sendable {
  public let x: Double
  public let y: Double

  public init(x: Double, y: Double) {
    self.x = x
    self.y = y
  }
}

public struct MeasurementResult: Codable, Hashable, Sendable {
  public let frameID: FrameID
  public let frameSHA256: String
  public let cameraConfigurationID: CameraConfigurationID
  public let request: MeasurementRequest
  public let matchingPixelCount: Int
  public let sampledPixelCount: Int
  public let centroid: PixelPoint?
  public let boundingBox: PixelRect?
  public let meanLuma: Double
  public let diagnosticSHA256: String
}

public actor VisionWorker {
  public init() {}

  public func measure(_ request: MeasurementRequest, in frame: StampedFrame) throws
    -> MeasurementResult
  {
    let region = request.region
    guard region.x >= 0, region.y >= 0, region.width > 0, region.height > 0,
      region.x + region.width <= frame.width,
      region.y + region.height <= frame.height
    else {
      throw FrameError.invalidRegion
    }

    var matching = 0
    var lumaSum = 0.0
    var xSum = 0.0
    var ySum = 0.0
    var minX = Int.max
    var minY = Int.max
    var maxX = Int.min
    var maxY = Int.min
    let sampled = region.width * region.height

    for y in region.y..<(region.y + region.height) {
      for x in region.x..<(region.x + region.width) {
        let (red, green, blue) = try rgb(frame: frame, x: x, y: y)
        let luma = 0.2126 * Double(red) + 0.7152 * Double(green) + 0.0722 * Double(blue)
        lumaSum += luma
        let isMatch: Bool
        switch request {
        case .statistics:
          isMatch = false
        case .greenInk(_, let thresholds, _):
          let competing = max(red, blue)
          isMatch =
            green >= thresholds.minimumGreen
            && Int(green) - Int(competing) >= Int(thresholds.minimumGreenExcess)
        case .darkOcclusion(_, let maximumLuma, _):
          isMatch = luma <= Double(maximumLuma)
        }
        if isMatch {
          matching += 1
          xSum += Double(x)
          ySum += Double(y)
          minX = min(minX, x)
          minY = min(minY, y)
          maxX = max(maxX, x)
          maxY = max(maxY, y)
        }
      }
    }

    let centroid =
      matching > 0
      ? PixelPoint(x: xSum / Double(matching), y: ySum / Double(matching))
      : nil
    let boundingBox =
      matching > 0
      ? PixelRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
      : nil
    let diagnostic =
      "\(frame.contentSHA256)|\(request.algorithmRevision)|\(matching)|\(sampled)|\(lumaSum)"
    return MeasurementResult(
      frameID: frame.id,
      frameSHA256: frame.contentSHA256,
      cameraConfigurationID: frame.cameraConfigurationID,
      request: request,
      matchingPixelCount: matching,
      sampledPixelCount: sampled,
      centroid: centroid,
      boundingBox: boundingBox,
      meanLuma: lumaSum / Double(sampled),
      diagnosticSHA256: RunLedger.sha256Hex(Data(diagnostic.utf8))
    )
  }

  private func rgb(frame: StampedFrame, x: Int, y: Int) throws -> (UInt8, UInt8, UInt8) {
    let offset = y * frame.rowBytes + x * frame.pixelFormat.bytesPerPixel
    switch frame.pixelFormat {
    case .gray8:
      let value = frame.bytes[offset]
      return (value, value, value)
    case .rgba8:
      return (frame.bytes[offset], frame.bytes[offset + 1], frame.bytes[offset + 2])
    case .bgra8:
      return (frame.bytes[offset + 2], frame.bytes[offset + 1], frame.bytes[offset])
    }
  }
}
