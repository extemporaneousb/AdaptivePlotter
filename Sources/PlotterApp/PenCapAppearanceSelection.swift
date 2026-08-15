import Foundation
import PlotterModel
import PlotterRuntime

struct PenCapAppearanceSelection: Codable, Hashable, Sendable {
  let color: PenCapColor
  let frameID: FrameID
  let frameSHA256: String
  let source: FrameSourceIdentity
  let cameraConfigurationID: CameraConfigurationID
  let width: Int
  let height: Int
  let pixelFormat: FramePixelFormat
  let clickPoint: Point2<CameraPixelSpace>
  let usableSampleCount: Int
  let totalSampleCount: Int
  let algorithmRevision: String

  func matches(_ frame: DisplayedFrame) -> Bool {
    frameID == frame.frame.id
      && frameSHA256 == frame.frame.contentSHA256
      && source == frame.source
      && cameraConfigurationID == frame.frame.cameraConfigurationID
      && width == frame.frame.width
      && height == frame.frame.height
      && pixelFormat == frame.frame.pixelFormat
  }

  var persistedLiveRejectionReason: String? {
    guard case .live = source else {
      return
        "Persisted pen-cap appearance was ignored because its source is SIMULATED. Use Identify Pen Cap on a LIVE camera frame."
    }
    guard !frameID.rawValue.isEmpty,
      frameSHA256.count == 64,
      frameSHA256.allSatisfy({ $0.isHexDigit }),
      width > 0,
      height > 0,
      pixelFormat == .rgba8 || pixelFormat == .bgra8,
      clickPoint.x >= 0,
      clickPoint.x < Double(width),
      clickPoint.y >= 0,
      clickPoint.y < Double(height),
      usableSampleCount >= PenCapAppearanceSampler.minimumUsablePixels,
      totalSampleCount >= usableSampleCount,
      algorithmRevision == PenCapAppearanceSampler.algorithmRevision,
      PenCapAppearanceSampler.isUsable(color)
    else {
      return
        "Persisted LIVE pen-cap appearance was ignored because its exact-frame sample provenance is invalid. Use Identify Pen Cap again."
    }
    return nil
  }
}

enum PersistedPenCapAppearanceLoadState: Hashable, Sendable {
  case absent
  case accepted
  case refused(String)

  var unavailableMessage: String {
    switch self {
    case .absent, .accepted:
      "Not learned — use Identify Pen Cap before LIVE pen-cap or armature analysis."
    case .refused(let reason):
      reason
    }
  }
}

enum PenCapAppearanceSamplingError: LocalizedError, Equatable, Sendable {
  case staleExactFrame
  case unsupportedPixelFormat(FramePixelFormat)
  case insufficientChromaticPixels(usable: Int, required: Int, total: Int)
  case representativeColorRejected(hexRGB: String)

  var errorDescription: String? {
    switch self {
    case .staleExactFrame:
      "The pen-cap click did not belong to the frozen exact frame. Click Identify Pen Cap again."
    case .unsupportedPixelFormat(let format):
      "Pen-cap color sampling requires an exact RGBA or BGRA frame; \(format.rawValue) is unsupported."
    case .insufficientChromaticPixels(let usable, let required, let total):
      "Pen-cap color sampling found \(usable) usable chromatic pixels out of \(total); at least \(required) are required. Click the colored cap body, not the tip or background."
    case .representativeColorRejected(let hexRGB):
      "The median sampled color #\(hexRGB) is gray, white, or dark. Click a visibly colored area of the pen-cap body."
    }
  }
}

enum PenCapAppearanceSampler {
  static let patchRadius = 4
  static let minimumUsablePixels = 9
  static let minimumSaturation = 0.20
  static let minimumValue = 0.10
  static let maximumValue = 0.98
  static let algorithmRevision = "pen-cap-click-9x9-median-v1"

  static func sample(
    frame: DisplayedFrame,
    selection: ActionSurfacePointSelection
  ) throws -> PenCapAppearanceSelection {
    guard exactFrame(selection.frame, matches: frame),
      selection.point.x >= 0, selection.point.x < Double(frame.frame.width),
      selection.point.y >= 0, selection.point.y < Double(frame.frame.height)
    else { throw PenCapAppearanceSamplingError.staleExactFrame }
    guard frame.frame.pixelFormat == .rgba8 || frame.frame.pixelFormat == .bgra8 else {
      throw PenCapAppearanceSamplingError.unsupportedPixelFormat(frame.frame.pixelFormat)
    }

    let centerX = Int(selection.point.x.rounded())
    let centerY = Int(selection.point.y.rounded())
    let minimumX = max(0, centerX - patchRadius)
    let maximumX = min(frame.frame.width - 1, centerX + patchRadius)
    let minimumY = max(0, centerY - patchRadius)
    let maximumY = min(frame.frame.height - 1, centerY + patchRadius)
    let total = (maximumX - minimumX + 1) * (maximumY - minimumY + 1)
    var usable: [(red: UInt8, green: UInt8, blue: UInt8)] = []
    usable.reserveCapacity(total)
    for y in minimumY...maximumY {
      for x in minimumX...maximumX {
        let offset = y * frame.frame.rowBytes + x * 4
        let first = frame.frame.bytes[offset]
        let green = frame.frame.bytes[offset + 1]
        let third = frame.frame.bytes[offset + 2]
        let pixel = frame.frame.pixelFormat == .rgba8
          ? (red: first, green: green, blue: third)
          : (red: third, green: green, blue: first)
        let hsv = saturationAndValue(red: pixel.red, green: pixel.green, blue: pixel.blue)
        if hsv.saturation >= minimumSaturation,
          hsv.value >= minimumValue,
          hsv.value <= maximumValue
        {
          usable.append(pixel)
        }
      }
    }
    guard usable.count >= minimumUsablePixels else {
      throw PenCapAppearanceSamplingError.insufficientChromaticPixels(
        usable: usable.count,
        required: minimumUsablePixels,
        total: total
      )
    }
    let color = PenCapColor(
      red: median(usable.map(\.red)),
      green: median(usable.map(\.green)),
      blue: median(usable.map(\.blue))
    )
    guard isUsable(color)
    else {
      throw PenCapAppearanceSamplingError.representativeColorRejected(hexRGB: color.hexRGB)
    }
    return PenCapAppearanceSelection(
      color: color,
      frameID: frame.frame.id,
      frameSHA256: frame.frame.contentSHA256,
      source: frame.source,
      cameraConfigurationID: frame.frame.cameraConfigurationID,
      width: frame.frame.width,
      height: frame.frame.height,
      pixelFormat: frame.frame.pixelFormat,
      clickPoint: selection.point,
      usableSampleCount: usable.count,
      totalSampleCount: total,
      algorithmRevision: algorithmRevision
    )
  }

  private static func exactFrame(
    _ expected: ExactTipCalibrationFrame,
    matches frame: DisplayedFrame
  ) -> Bool {
    expected.frameID == frame.frame.id
      && expected.frameSHA256 == frame.frame.contentSHA256
      && expected.source == frame.source
      && expected.cameraConfigurationID == frame.frame.cameraConfigurationID
      && expected.width == frame.frame.width
      && expected.height == frame.frame.height
      && expected.pixelFormat == frame.frame.pixelFormat
  }

  private static func median(_ values: [UInt8]) -> UInt8 {
    let sorted = values.sorted()
    let middle = sorted.count / 2
    if sorted.count.isMultiple(of: 2) {
      return UInt8((UInt16(sorted[middle - 1]) + UInt16(sorted[middle])) / 2)
    }
    return sorted[middle]
  }

  private static func saturationAndValue(
    red: UInt8,
    green: UInt8,
    blue: UInt8
  ) -> (saturation: Double, value: Double) {
    let channels = [Double(red), Double(green), Double(blue)].map { $0 / 255 }
    let maximum = channels.max() ?? 0
    let minimum = channels.min() ?? 0
    return (maximum == 0 ? 0 : (maximum - minimum) / maximum, maximum)
  }

  static func isUsable(_ color: PenCapColor) -> Bool {
    let sample = saturationAndValue(red: color.red, green: color.green, blue: color.blue)
    return sample.saturation >= minimumSaturation
      && sample.value >= minimumValue
      && sample.value <= maximumValue
  }
}
