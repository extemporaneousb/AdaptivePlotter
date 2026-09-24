import Foundation
import PlotterModel

/// A fixed chromatic marker. The tap selects the component; its centroid is the
/// calibration datum. Neither its color nor its anchor policy adapts in flight.
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

  public var identity: String {
    let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
    return RunLedger.sha256Hex((try? encoder.encode(self)) ?? Data())
  }
  public var estimatorRevision: String { "\(Self.revision):\(identity)" }
  public var isValid: Bool {
    let hsv = VisionWorker.hsv(red: color.red, green: color.green, blue: color.blue)
    return !frameID.rawValue.isEmpty && frameSHA256.count == 64
      && frameSHA256.allSatisfy(\.isHexDigit)
      && hsv.saturation >= 0.3 && hsv.value >= 0.12
      && Int(max(color.red, color.green, color.blue)) - Int(min(color.red, color.green, color.blue)) >= 20
      && componentSaturation75.isFinite && (0...1).contains(componentSaturation75)
      && minimumSaturation.isFinite && (0.25...0.5).contains(minimumSaturation)
      && abs(minimumSaturation - max(0.25, max(hsv.saturation, componentSaturation75) * 0.5)) < 1e-10
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
    guard colors.count >= 9 else { throw SampledColorMarkerError.insufficientChroma }
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
      cameraConfigurationID: frame.frame.cameraConfigurationID, opticalConfiguration: opticalConfiguration)
    guard reference.isValid else { throw SampledColorMarkerError.clipped }
    guard components.filter({ reference.acceptsGeometry($0, region: region) }).count == 1 else {
      throw SampledColorMarkerError.ambiguous
    }
    return reference
  }

  func acceptsGeometry(_ component: VisionWorker.PixelComponent, region: PixelRect) -> Bool {
    let bounds = component.bounds
    let areaRatio = Double(component.pixelCount) / Double(componentPixelCount)
    let widthRatio = Double(bounds.width) / Double(componentBounds.width)
    let heightRatio = Double(bounds.height) / Double(componentBounds.height)
    // Conservative fixed compatibility windows, versioned with the policy.
    // A second compatible component refuses rather than choosing by prediction.
    return component.pixelCount >= 9 && (0.5...2).contains(areaRatio)
      && (0.5...2).contains(widthRatio) && (0.5...2).contains(heightRatio)
      && bounds.x > region.x && bounds.y > region.y
      && bounds.x + bounds.width < region.x + region.width
      && bounds.y + bounds.height < region.y + region.height
  }
}

public enum SampledColorMarkerError: LocalizedError {
  case incompatibleFrame, insufficientChroma, clipped, ambiguous
  public var errorDescription: String? {
    switch self {
    case .incompatibleFrame: "The marker must be selected on the current exact camera frame with matching optics."
    case .insufficientChroma: "Click inside a clearly colored marker. This sample is too pale, dark, or small."
    case .clipped: "The marker touches the image edge. Bring the complete marker into view before selecting it."
    case .ambiguous: "More than one similar colored marker is visible. Use a distinctive marker color."
    }
  }
}
