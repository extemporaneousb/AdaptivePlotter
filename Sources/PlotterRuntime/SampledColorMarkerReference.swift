import Foundation
import PlotterModel

/// A fixed cap appearance. The tap selects a connected component; its centroid
/// is the calibration datum. Appearance and anchor policy never adapt in flight.
public struct SampledColorMarkerReference: Codable, Hashable, Sendable {
  public static let revision = "sampled-color-marker-v1"
  public let color: PenCapColor
  public let componentSaturation75: Double
  public let minimumSaturation: Double
  public let selectionPoint: Point2<CameraPixelSpace>
  public let acquisitionAnchor: Point2<CameraPixelSpace>
  public let componentBounds: PixelRect
  public let componentPixelCount: Int
  public let frameID: FrameID
  public let frameSHA256: String
  public let cameraConfigurationID: CameraConfigurationID
  public let opticalConfiguration: CameraOpticalConfigurationIdentity
  /// Absent in older chromatic references. The exact selection seeds spatial
  /// association within this capture generation; it never proves later pixels.
  public var captureNanoseconds: UInt64? = nil
  public var neutralContrast: PenCapNeutralContrast? = nil

  public var identity: String {
    let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
    return RunLedger.sha256Hex((try? encoder.encode(self)) ?? Data())
  }
  public var estimatorRevision: String { "\(Self.revision):\(identity)" }
  public var isValid: Bool {
    let hsv = VisionWorker.hsv(red: color.red, green: color.green, blue: color.blue)
    return !frameID.rawValue.isEmpty && frameSHA256.count == 64
      && frameSHA256.allSatisfy(\.isHexDigit)
      && (neutralContrast.map { $0.isValid && $0.accepts(red: Int(color.red), green: Int(color.green), blue: Int(color.blue)) }
        ?? (hsv.saturation >= 0.3 && hsv.value >= 0.12
          && Int(max(color.red, color.green, color.blue)) - Int(min(color.red, color.green, color.blue)) >= 20))
      && componentSaturation75.isFinite && (0...1).contains(componentSaturation75)
      && minimumSaturation.isFinite && (0.25...0.5).contains(minimumSaturation)
      && (neutralContrast != nil
        || abs(minimumSaturation - max(0.25, max(hsv.saturation, componentSaturation75) * 0.5)) < 1e-10)
      && componentPixelCount >= 9
      && componentBounds.width >= 2 && componentBounds.height >= 2
      && componentBounds.x > 0 && componentBounds.y > 0
      && componentBounds.x + componentBounds.width < opticalConfiguration.width
      && componentBounds.y + componentBounds.height < opticalConfiguration.height
      && componentPixelCount <= componentBounds.width * componentBounds.height
      && contains(selectionPoint) && contains(acquisitionAnchor)
      && (opticalConfiguration.pixelFormat == .rgba8 || opticalConfiguration.pixelFormat == .bgra8)
  }

  private func contains(_ point: Point2<CameraPixelSpace>) -> Bool {
    point.x >= Double(componentBounds.x) && point.x < Double(componentBounds.x + componentBounds.width)
      && point.y >= Double(componentBounds.y) && point.y < Double(componentBounds.y + componentBounds.height)
  }

  public static func capture(frame: DisplayedFrame, point: Point2<CameraPixelSpace>,
    opticalConfiguration: CameraOpticalConfigurationIdentity) throws -> Self {
    guard let frameSHA256 = frame.frame.materializedContentSHA256,
      opticalConfiguration.source == frame.source,
      opticalConfiguration.width == frame.frame.width, opticalConfiguration.height == frame.frame.height,
      opticalConfiguration.pixelFormat == frame.frame.pixelFormat,
      point.x >= 2, point.y >= 2,
      point.x < Double(frame.frame.width - 2), point.y < Double(frame.frame.height - 2),
      frame.frame.pixelFormat == .rgba8 || frame.frame.pixelFormat == .bgra8 else {
      throw SampledColorMarkerError.incompatibleFrame
    }
    // Median of a small neighborhood rejects isolated highlights and sensor noise.
    let colors = frame.frame.bytes.withUnsafeBytes { bytes -> [(UInt8, UInt8, UInt8)] in
      var result: [(UInt8, UInt8, UInt8)] = []
      for y in (Int(point.y) - 2)...(Int(point.y) + 2) {
        for x in (Int(point.x) - 2)...(Int(point.x) + 2) {
          let rgb = VisionWorker.rgb(frame: frame.frame, bytes: bytes, x: x, y: y)
          let hsv = VisionWorker.hsv(red: rgb.0, green: rgb.1, blue: rgb.2)
          if hsv.saturation >= 0.3 && hsv.value >= 0.12 { result.append(rgb) }
        }
      }
      return result
    }
    guard colors.count >= 9 else {
      return try captureNeutral(frame: frame, point: point, opticalConfiguration: opticalConfiguration)
    }
    let color = PenCapColor(red: colors.map(\.0).sorted()[colors.count / 2],
      green: colors.map(\.1).sorted()[colors.count / 2], blue: colors.map(\.2).sorted()[colors.count / 2])
    let sampled = VisionWorker.hsv(red: color.red, green: color.green, blue: color.blue)
    guard sampled.saturation >= 0.3, sampled.value >= 0.12,
      Int(max(color.red, color.green, color.blue)) - Int(min(color.red, color.green, color.blue)) >= 20 else {
      throw SampledColorMarkerError.insufficientChroma
    }
    let region = PixelRect(x: 0, y: 0, width: frame.frame.width, height: frame.frame.height)
    let initialComponents = try VisionWorker.colorComponents(frame: frame.frame, region: region,
      color: color, searchCenter: nil, markerPolicy: true, selectionPoint: point)
    guard let initial = initialComponents.first(where: \.containsSelectionPoint), initial.pixelCount >= 9 else {
      throw SampledColorMarkerError.insufficientChroma
    }
    // Learn chroma only from the clicked component's bounded support. A pale
    // face of folded tape can still select its saturated interior, while pale
    // same-hue reflections elsewhere do not define or adapt this policy.
    let saturations = frame.frame.bytes.withUnsafeBytes { bytes -> [Double] in
      var values: [Double] = []
      for index in initial.selectionSupportIndices ?? [] {
        let x = index % region.width, y = index / region.width
        let rgb = VisionWorker.rgb(frame: frame.frame, bytes: bytes, x: x, y: y)
        values.append(VisionWorker.hsv(red: rgb.0, green: rgb.1, blue: rgb.2).saturation)
      }
      return values.sorted()
    }
    guard !saturations.isEmpty else { throw SampledColorMarkerError.insufficientChroma }
    let saturation75 = saturations[Int(Double(saturations.count - 1) * 0.75)]
    let minimumSaturation = max(0.25, max(sampled.saturation, saturation75) * 0.5)
    let components = try VisionWorker.colorComponents(frame: frame.frame, region: region,
      color: color, searchCenter: nil, markerPolicy: true, selectionPoint: point,
      markerMinimumSaturation: minimumSaturation)
    guard let selected = components.first(where: \.containsSelectionPoint), selected.pixelCount >= 9 else {
      throw SampledColorMarkerError.insufficientChroma
    }
    let reference = Self(color: color, componentSaturation75: saturation75,
      minimumSaturation: minimumSaturation, selectionPoint: point,
      acquisitionAnchor: try Point2(x: selected.centroidX, y: selected.centroidY),
      componentBounds: selected.bounds, componentPixelCount: selected.pixelCount,
      frameID: frame.frame.id, frameSHA256: frameSHA256,
      cameraConfigurationID: frame.frame.cameraConfigurationID, opticalConfiguration: opticalConfiguration,
      captureNanoseconds: frame.frame.captureNanoseconds)
    guard reference.isValid else { throw SampledColorMarkerError.clipped }
    // The exact click identifies this component even when another similar cap
    // is visible elsewhere. Subsequent observations must establish association.
    return reference
  }

  private static func captureNeutral(frame: DisplayedFrame, point: Point2<CameraPixelSpace>,
    opticalConfiguration: CameraOpticalConfigurationIdentity) throws -> Self {
    let image = frame.frame
    let seed = image.bytes.withUnsafeBytes { bytes -> PenCapColor in
      var red: [UInt8] = [], green: [UInt8] = [], blue: [UInt8] = []
      for y in (Int(point.y) - 2)...(Int(point.y) + 2) {
        for x in (Int(point.x) - 2)...(Int(point.x) + 2) {
          let rgb = VisionWorker.rgb(frame: image, bytes: bytes, x: x, y: y)
          red.append(rgb.0); green.append(rgb.1); blue.append(rgb.2)
        }
      }
      return PenCapColor(red: red.sorted()[12], green: green.sorted()[12], blue: blue.sorted()[12])
    }
    let foreground = Double(Int(seed.red) + Int(seed.green) + Int(seed.blue)) / 3
    guard PenCapNeutralContrast.isNeutral(red: Int(seed.red), green: Int(seed.green), blue: Int(seed.blue)) else {
      throw SampledColorMarkerError.insufficientChroma
    }
    let region = PixelRect(x: 0, y: 0, width: image.width, height: image.height)
    // Find an enclosing contrasting background ring. Flat paper, a broad rail,
    // and a component connected to the frame edge cannot become a cap sample.
    for radius in [8, 16, 32, 64] {
      let x = Int(point.x), y = Int(point.y)
      guard x - radius > 0, y - radius > 0,
        x + radius < image.width - 1, y + radius < image.height - 1 else { continue }
      let ring = image.bytes.withUnsafeBytes { bytes -> [Double] in
        var values: [Double] = []
        for offset in -radius...radius {
          for (px, py) in [(x + offset, y - radius), (x + offset, y + radius),
            (x - radius, y + offset), (x + radius, y + offset)] {
            let rgb = VisionWorker.rgb(frame: image, bytes: bytes, x: px, y: py)
            values.append(Double(Int(rgb.0) + Int(rgb.1) + Int(rgb.2)) / 3)
          }
        }
        return values.sorted()
      }
      let background = ring[ring.count / 2]
      guard abs(background - foreground) >= 48 else { continue }
      let contrast = PenCapNeutralContrast(foreground: foreground, background: background)
      let contrastingCount = ring.filter {
        foreground < background ? $0 > contrast.threshold : $0 < contrast.threshold
      }.count
      guard contrastingCount * 4 >= ring.count * 3 else { continue }
      let components = try VisionWorker.colorComponents(frame: image, region: region, color: seed,
        searchCenter: nil, markerPolicy: true, selectionPoint: point, neutralContrast: contrast)
      guard let selected = components.first(where: \.containsSelectionPoint), selected.pixelCount >= 9,
        selected.bounds.x > x - radius, selected.bounds.y > y - radius,
        selected.bounds.x + selected.bounds.width < x + radius,
        selected.bounds.y + selected.bounds.height < y + radius else { continue }
      let result = Self(color: seed, componentSaturation75: 0, minimumSaturation: 0.25,
        selectionPoint: point, acquisitionAnchor: try Point2(x: selected.centroidX, y: selected.centroidY),
        componentBounds: selected.bounds, componentPixelCount: selected.pixelCount,
        frameID: image.id, frameSHA256: image.contentSHA256,
        cameraConfigurationID: image.cameraConfigurationID, opticalConfiguration: opticalConfiguration,
        captureNanoseconds: image.captureNanoseconds, neutralContrast: contrast)
      guard result.isValid else { throw SampledColorMarkerError.clipped }
      return result
    }
    throw SampledColorMarkerError.insufficientChroma
  }

  func acceptsGeometry(_ component: VisionWorker.PixelComponent, region: PixelRect) -> Bool {
    let bounds = component.bounds
    let areaRatio = Double(component.pixelCount) / Double(componentPixelCount)
    let widthRatio = Double(bounds.width) / Double(componentBounds.width)
    let heightRatio = Double(bounds.height) / Double(componentBounds.height)
    // Conservative fixed compatibility windows, versioned with the policy.
    // Appearance geometry is independent of any position-association hint.
    return component.pixelCount >= 9 && (0.5...2).contains(areaRatio)
      && (0.5...2).contains(widthRatio) && (0.5...2).contains(heightRatio)
      && bounds.x > region.x && bounds.y > region.y
      && bounds.x + bounds.width < region.x + region.width
      && bounds.y + bounds.height < region.y + region.height
  }
}

/// Fixed foreground/background contrast for a neutral (black, gray or white)
/// cap. This does not learn from later frames or infer a hidden cap position.
public struct PenCapNeutralContrast: Codable, Hashable, Sendable {
  public let foreground: Double
  public let background: Double
  var threshold: Double { (foreground + background) / 2 }
  var isValid: Bool {
    foreground.isFinite && background.isFinite
      && (0...255).contains(foreground) && (0...255).contains(background)
      && abs(foreground - background) >= 48
  }
  static func isNeutral(red: Int, green: Int, blue: Int) -> Bool {
    let maximum = max(red, green, blue)
    return max(red, green, blue) - min(red, green, blue) <= max(24, maximum * 28 / 100)
  }
  func accepts(red: Int, green: Int, blue: Int) -> Bool {
    guard Self.isNeutral(red: red, green: green, blue: blue) else { return false }
    let value = Double(red + green + blue) / 3
    return foreground < background ? value < threshold : value > threshold
  }
}

public enum SampledColorMarkerError: LocalizedError {
  case incompatibleFrame, insufficientChroma, clipped, ambiguous
  public var errorDescription: String? {
    switch self {
    case .incompatibleFrame: "Capture Pen Cap needs the current exact camera frame with matching optics."
    case .insufficientChroma: "Click inside the pen cap or tape where it is distinct from the surrounding background."
    case .clipped: "The pen cap touches the image edge. Bring the complete cap into view before clicking it."
    case .ambiguous: "Several matching pen caps are visible. Click the cap to identify it again."
    }
  }
}
