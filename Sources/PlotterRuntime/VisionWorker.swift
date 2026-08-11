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

/// Image-space scene priors from the current fixed C920 view. These regions
/// narrow distractors; they do not define machine coordinates or a mm scale.
public struct PlotterSceneVisionPriors: Hashable, Sendable {
  public let capSearchRegion: PixelRect
  public let topFrameSideRegion: PixelRect
  public let rightFrameSideRegion: PixelRect
  public let minimumGreen: UInt8
  public let minimumGreenOverRed: UInt8
  public let minimumGreenOverBlue: UInt8
  public let minimumCapPixels: Int
  public let maximumCapPixels: Int
  public let minimumBlue: UInt8
  public let minimumBlueOverRed: UInt8
  public let minimumBlueOverGreen: UInt8
  public let lineResidualLimitPixels: Double
  public let minimumLineSupportFraction: Double
  public let armatureHalfWidthFraction: Double
  public let armatureTopMarginFraction: Double
  public let armatureHeightFraction: Double
  public let algorithmRevision: String

  public init(
    capSearchRegion: PixelRect,
    topFrameSideRegion: PixelRect,
    rightFrameSideRegion: PixelRect,
    minimumGreen: UInt8 = 75,
    minimumGreenOverRed: UInt8 = 28,
    minimumGreenOverBlue: UInt8 = 12,
    minimumCapPixels: Int,
    maximumCapPixels: Int,
    minimumBlue: UInt8 = 70,
    minimumBlueOverRed: UInt8 = 40,
    minimumBlueOverGreen: UInt8 = 18,
    lineResidualLimitPixels: Double,
    minimumLineSupportFraction: Double = 0.25,
    armatureHalfWidthFraction: Double = 0.055,
    armatureTopMarginFraction: Double = 0.025,
    armatureHeightFraction: Double = 0.56,
    algorithmRevision: String = "plotter-scene-v1"
  ) throws {
    guard minimumCapPixels > 0, maximumCapPixels >= minimumCapPixels,
      lineResidualLimitPixels.isFinite, lineResidualLimitPixels > 0,
      minimumLineSupportFraction.isFinite,
      minimumLineSupportFraction > 0, minimumLineSupportFraction <= 1,
      armatureHalfWidthFraction.isFinite,
      armatureHalfWidthFraction > 0, armatureHalfWidthFraction < 0.5,
      armatureTopMarginFraction.isFinite,
      armatureTopMarginFraction >= 0, armatureTopMarginFraction < 0.5,
      armatureHeightFraction.isFinite,
      armatureHeightFraction > 0, armatureHeightFraction <= 1,
      !algorithmRevision.isEmpty
    else { throw FrameError.invalidVisionPolicy }
    self.capSearchRegion = capSearchRegion
    self.topFrameSideRegion = topFrameSideRegion
    self.rightFrameSideRegion = rightFrameSideRegion
    self.minimumGreen = minimumGreen
    self.minimumGreenOverRed = minimumGreenOverRed
    self.minimumGreenOverBlue = minimumGreenOverBlue
    self.minimumCapPixels = minimumCapPixels
    self.maximumCapPixels = maximumCapPixels
    self.minimumBlue = minimumBlue
    self.minimumBlueOverRed = minimumBlueOverRed
    self.minimumBlueOverGreen = minimumBlueOverGreen
    self.lineResidualLimitPixels = lineResidualLimitPixels
    self.minimumLineSupportFraction = minimumLineSupportFraction
    self.armatureHalfWidthFraction = armatureHalfWidthFraction
    self.armatureTopMarginFraction = armatureTopMarginFraction
    self.armatureHeightFraction = armatureHeightFraction
    self.algorithmRevision = algorithmRevision
  }

  public static func c920StartupDefaults(frameWidth: Int, frameHeight: Int) throws -> Self {
    guard frameWidth > 0, frameHeight > 0 else { throw FrameError.invalidDimensions }
    let area = frameWidth * frameHeight
    return try Self(
      capSearchRegion: scaledRegion(
        x: 0.24, y: 0.14, width: 0.66, height: 0.54,
        frameWidth: frameWidth, frameHeight: frameHeight),
      topFrameSideRegion: scaledRegion(
        x: 0.34, y: 0.09, width: 0.54, height: 0.13,
        frameWidth: frameWidth, frameHeight: frameHeight),
      rightFrameSideRegion: scaledRegion(
        x: 0.84, y: 0.14, width: 0.10, height: 0.54,
        frameWidth: frameWidth, frameHeight: frameHeight),
      minimumCapPixels: max(24, area / 40_000),
      maximumCapPixels: max(48, area / 200),
      lineResidualLimitPixels: max(2, Double(frameHeight) * 0.003),
      algorithmRevision: "c920-startup-scene-v1"
    )
  }

  private static func scaledRegion(
    x: Double,
    y: Double,
    width: Double,
    height: Double,
    frameWidth: Int,
    frameHeight: Int
  ) -> PixelRect {
    let originX = Int((Double(frameWidth) * x).rounded(.down))
    let originY = Int((Double(frameHeight) * y).rounded(.down))
    let maxX = min(frameWidth, Int((Double(frameWidth) * (x + width)).rounded(.up)))
    let maxY = min(frameHeight, Int((Double(frameHeight) * (y + height)).rounded(.up)))
    return PixelRect(
      x: originX,
      y: originY,
      width: max(1, maxX - originX),
      height: max(1, maxY - originY)
    )
  }
}

public struct GreenCapMeasurement: Hashable, Sendable {
  public let pixelCount: Int
  public let boundingBox: PixelRect
  public let centroid: Point2<CameraPixelSpace>
  public let confidence: Double
}

public struct FrameSideMeasurement: Hashable, Sendable {
  public let geometry: Polyline<CameraPixelSpace>
  public let supportPointCount: Int
  public let inlierCount: Int
  public let rmsResidualPixels: Double
  public let confidence: Double
}

/// A deliberately coarse cap-anchored envelope for the visible moving
/// armature. It is an inferred occlusion prior, not pixel-segmented geometry.
public struct ArmatureEstimate: Hashable, Sendable {
  public let bounds: AxisAlignedBounds<CameraPixelSpace>
  public let confidence: Double
  public let basis: String
}

/// A coarse four-sided image-space frame inferred from the measured top and
/// right sides. The unobserved bottom and left sides are a parallelogram prior,
/// not direct pixel measurements or a machine-to-camera registration.
public struct DrawingFrameEstimate: Hashable, Sendable {
  public let geometry: Polyline<CameraPixelSpace>
  public let confidence: Double
  public let basis: String

  public init(
    geometry: Polyline<CameraPixelSpace>,
    confidence: Double,
    basis: String
  ) {
    self.geometry = geometry
    self.confidence = confidence
    self.basis = basis
  }
}

public struct PlotterSceneMeasurement: Hashable, Sendable {
  public let frameID: FrameID
  public let frameSHA256: String
  public let cameraConfigurationID: CameraConfigurationID
  public let greenComponentCount: Int
  public let cap: GreenCapMeasurement?
  public let topFrameSide: FrameSideMeasurement?
  public let rightFrameSide: FrameSideMeasurement?
  public let drawingFrame: DrawingFrameEstimate?
  public let armature: ArmatureEstimate?
  public let overlays: [CameraOverlayMeasurement]
  public let algorithmRevision: String
  public let diagnosticSHA256: String
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

public struct MeasurementResult: Codable, Hashable, Sendable {
  public let frameID: FrameID
  public let frameSHA256: String
  public let cameraConfigurationID: CameraConfigurationID
  public let request: MeasurementRequest
  public let matchingPixelCount: Int
  public let sampledPixelCount: Int
  public let centroid: Point2<CameraPixelSpace>?
  public let boundingBox: PixelRect?
  public let geometry: CameraPixelGeometry?
  public let meanLuma: Double
  public let diagnosticSHA256: String

  public var overlayMeasurement: CameraOverlayMeasurement? {
    guard let geometry else { return nil }
    return CameraOverlayMeasurement(
      frameID: frameID,
      cameraConfigurationID: cameraConfigurationID,
      geometry: geometry,
      provenance: CameraMeasurementProvenance(
        kind: request.overlayKind,
        source: request.overlaySource,
        algorithmRevision: request.algorithmRevision
      )
    )
  }
}

extension MeasurementRequest {
  public var overlayKind: CameraOverlayKind {
    switch self {
    case .statistics, .darkOcclusion: .diagnostic
    case .greenInk: .observedInk
    }
  }

  public var overlaySource: CameraOverlaySource {
    switch self {
    case .statistics: .diagnostic
    case .greenInk, .darkOcclusion: .measured
    }
  }
}

public actor VisionWorker {
  private struct PixelComponent {
    let pixelCount: Int
    let minX: Int
    let minY: Int
    let maxX: Int
    let maxY: Int
    let centroidX: Double
    let centroidY: Double
  }

  private struct RegressionPoint {
    let independent: Double
    let dependent: Double
  }

  private enum FrameSideOrientation: Equatable {
    case top
    case right
  }

  public init() {}

  public func inspectPlotterScene(
    in frame: StampedFrame,
    priors suppliedPriors: PlotterSceneVisionPriors? = nil
  ) throws -> PlotterSceneMeasurement {
    let priors = try suppliedPriors
      ?? PlotterSceneVisionPriors.c920StartupDefaults(
        frameWidth: frame.width,
        frameHeight: frame.height
      )
    try validate(priors.capSearchRegion, in: frame)
    try validate(priors.topFrameSideRegion, in: frame)
    try validate(priors.rightFrameSideRegion, in: frame)

    let components = try greenComponents(
      frame: frame,
      region: priors.capSearchRegion,
      priors: priors
    ).filter { $0.pixelCount >= 2 }
    // The observed marker is a compact filled component. This broad shape
    // rejection prevents a long green ink stroke from becoming the cap.
    let eligible = components
      .filter {
        let width = $0.maxX - $0.minX + 1
        let height = $0.maxY - $0.minY + 1
        let aspect = Double(width) / Double(height)
        let fill = Double($0.pixelCount) / Double(width * height)
        return $0.pixelCount >= priors.minimumCapPixels
          && $0.pixelCount <= priors.maximumCapPixels
          && aspect >= 0.25 && aspect <= 4
          && fill >= 0.20
      }
      .sorted { $0.pixelCount > $1.pixelCount }
    let cap = try eligible.first.map { component in
      let secondLargest = eligible
        .dropFirst()
        .map(\.pixelCount)
        .max() ?? 0
      let sizeScore = min(
        1,
        Double(component.pixelCount) / Double(priors.minimumCapPixels * 4)
      )
      let separationScore = max(
        0,
        1 - Double(secondLargest) / Double(component.pixelCount)
      )
      return GreenCapMeasurement(
        pixelCount: component.pixelCount,
        boundingBox: PixelRect(
          x: component.minX,
          y: component.minY,
          width: component.maxX - component.minX + 1,
          height: component.maxY - component.minY + 1
        ),
        centroid: try Point2<CameraPixelSpace>(
          x: component.centroidX,
          y: component.centroidY
        ),
        confidence: sizeScore * separationScore
      )
    }
    let top = try frameSide(
      frame: frame,
      region: priors.topFrameSideRegion,
      orientation: .top,
      priors: priors
    )
    let right = try frameSide(
      frame: frame,
      region: priors.rightFrameSideRegion,
      orientation: .right,
      priors: priors
    )
    let drawingFrame = try drawingFrameEstimate(top: top, right: right, frame: frame)
    let armature = try cap.map {
      try armatureEstimate(cap: $0, frame: frame, priors: priors)
    }

    let capProvenance = CameraMeasurementProvenance(
      kind: .penCap,
      source: .measured,
      algorithmRevision: priors.algorithmRevision
    )
    let frameSideProvenance = CameraMeasurementProvenance(
      kind: .measuredFrameSide,
      source: .measured,
      algorithmRevision: priors.algorithmRevision
    )
    let drawingFrameProvenance = CameraMeasurementProvenance(
      kind: .drawingFrameEstimate,
      source: .inferred,
      algorithmRevision: "\(priors.algorithmRevision):two-side-closure-v1"
    )
    let armatureProvenance = CameraMeasurementProvenance(
      kind: .armatureEstimate,
      source: .inferred,
      algorithmRevision: "\(priors.algorithmRevision):cap-anchored-armature-v1"
    )
    var overlays: [CameraOverlayMeasurement] = []
    if let cap {
      let box = cap.boundingBox
      overlays.append(
        CameraOverlayMeasurement(
          frameID: frame.id,
          cameraConfigurationID: frame.cameraConfigurationID,
          geometry: .bounds(
            try AxisAlignedBounds<CameraPixelSpace>(
              minX: Double(box.x),
              minY: Double(box.y),
              maxX: Double(box.x + box.width),
              maxY: Double(box.y + box.height)
            )),
          provenance: capProvenance
        ))
      overlays.append(
        CameraOverlayMeasurement(
          frameID: frame.id,
          cameraConfigurationID: frame.cameraConfigurationID,
          geometry: .point(cap.centroid),
          provenance: capProvenance
        ))
    }
    for side in [top, right].compactMap({ $0 }) {
      overlays.append(
        CameraOverlayMeasurement(
          frameID: frame.id,
          cameraConfigurationID: frame.cameraConfigurationID,
          geometry: .polyline(side.geometry),
          provenance: frameSideProvenance
        ))
    }
    if let drawingFrame {
      overlays.append(
        CameraOverlayMeasurement(
          frameID: frame.id,
          cameraConfigurationID: frame.cameraConfigurationID,
          geometry: .polyline(drawingFrame.geometry),
          provenance: drawingFrameProvenance
        ))
    }
    if let armature {
      overlays.append(
        CameraOverlayMeasurement(
          frameID: frame.id,
          cameraConfigurationID: frame.cameraConfigurationID,
          geometry: .bounds(armature.bounds),
          provenance: armatureProvenance
        ))
    }
    let capPixelCount = cap?.pixelCount ?? 0
    let topInlierCount = top?.inlierCount ?? 0
    let topResidual = top?.rmsResidualPixels ?? Double.infinity
    let rightInlierCount = right?.inlierCount ?? 0
    let rightResidual = right?.rmsResidualPixels ?? Double.infinity
    let drawingFrameConfidence = drawingFrame?.confidence ?? 0
    let armatureConfidence = armature?.confidence ?? 0
    let diagnostic =
      "\(frame.contentSHA256)|\(priors.algorithmRevision)|\(components.count)|"
      + "\(capPixelCount)|\(topInlierCount)|\(topResidual)|"
      + "\(rightInlierCount)|\(rightResidual)|"
      + "\(drawingFrameConfidence)|\(armatureConfidence)"
    return PlotterSceneMeasurement(
      frameID: frame.id,
      frameSHA256: frame.contentSHA256,
      cameraConfigurationID: frame.cameraConfigurationID,
      greenComponentCount: components.count,
      cap: cap,
      topFrameSide: top,
      rightFrameSide: right,
      drawingFrame: drawingFrame,
      armature: armature,
      overlays: overlays,
      algorithmRevision: priors.algorithmRevision,
      diagnosticSHA256: RunLedger.sha256Hex(Data(diagnostic.utf8))
    )
  }

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

    try frame.bytes.withUnsafeBytes { bytes in
      for y in region.y..<(region.y + region.height) {
        try Task.checkCancellation()
        for x in region.x..<(region.x + region.width) {
          let (red, green, blue) = Self.rgb(frame: frame, bytes: bytes, x: x, y: y)
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
    }

    let centroid =
      matching > 0
      ? try Point2<CameraPixelSpace>(x: xSum / Double(matching), y: ySum / Double(matching))
      : nil
    let boundingBox =
      matching > 0
      ? PixelRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
      : nil
    let geometry = try boundingBox.map {
      CameraPixelGeometry.bounds(
        try AxisAlignedBounds<CameraPixelSpace>(
          minX: Double($0.x),
          minY: Double($0.y),
          maxX: Double($0.x + $0.width),
          maxY: Double($0.y + $0.height)
        ))
    }
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
      geometry: geometry,
      meanLuma: lumaSum / Double(sampled),
      diagnosticSHA256: RunLedger.sha256Hex(Data(diagnostic.utf8))
    )
  }

  private func validate(_ region: PixelRect, in frame: StampedFrame) throws {
    guard region.x >= 0, region.y >= 0, region.width > 0, region.height > 0,
      region.x + region.width <= frame.width,
      region.y + region.height <= frame.height
    else { throw FrameError.invalidRegion }
  }

  private func armatureEstimate(
    cap: GreenCapMeasurement,
    frame: StampedFrame,
    priors: PlotterSceneVisionPriors
  ) throws -> ArmatureEstimate {
    let halfWidth = Double(frame.width) * priors.armatureHalfWidthFraction
    let topMargin = Double(frame.height) * priors.armatureTopMarginFraction
    let height = Double(frame.height) * priors.armatureHeightFraction
    let minX = max(0, cap.centroid.x - halfWidth)
    let maxX = min(Double(frame.width - 1), cap.centroid.x + halfWidth)
    let minY = max(0, Double(cap.boundingBox.y) - topMargin)
    let maxY = min(Double(frame.height - 1), minY + height)
    return ArmatureEstimate(
      bounds: try AxisAlignedBounds(
        minX: minX,
        minY: minY,
        maxX: maxX,
        maxY: maxY
      ),
      confidence: min(1, cap.confidence * 0.55),
      basis: "cap-anchored C920 envelope; inferred, not segmented"
    )
  }

  private func drawingFrameEstimate(
    top: FrameSideMeasurement?,
    right: FrameSideMeasurement?,
    frame: StampedFrame
  ) throws -> DrawingFrameEstimate? {
    guard let top, let right else { return nil }
    let topLeft = top.geometry.points.min { $0.x < $1.x }!
    let measuredTopRight = top.geometry.points.max { $0.x < $1.x }!
    let measuredRightTop = right.geometry.points.min { $0.y < $1.y }!
    let bottomRight = right.geometry.points.max { $0.y < $1.y }!
    let topRight = try Point2<CameraPixelSpace>(
      x: (measuredTopRight.x + measuredRightTop.x) / 2,
      y: (measuredTopRight.y + measuredRightTop.y) / 2
    )
    let bottomLeft = try Point2<CameraPixelSpace>(
      x: min(
        Double(frame.width - 1),
        max(0, bottomRight.x - (topRight.x - topLeft.x))
      ),
      y: min(
        Double(frame.height - 1),
        max(0, bottomRight.y - (topRight.y - topLeft.y))
      )
    )
    return DrawingFrameEstimate(
      geometry: try Polyline(points: [
        topLeft,
        topRight,
        bottomRight,
        bottomLeft,
        topLeft,
      ]),
      confidence: min(top.confidence, right.confidence) * 0.65,
      basis: "measured top/right with inferred parallel bottom/left; image space only"
    )
  }

  private func greenComponents(
    frame: StampedFrame,
    region: PixelRect,
    priors: PlotterSceneVisionPriors
  ) throws -> [PixelComponent] {
    let count = region.width * region.height
    let matching = try frame.bytes.withUnsafeBytes { bytes in
      var matching = [Bool](repeating: false, count: count)
      for localY in 0..<region.height {
        try Task.checkCancellation()
        for localX in 0..<region.width {
          let (red, green, blue) = Self.rgb(
            frame: frame,
            bytes: bytes,
            x: region.x + localX,
            y: region.y + localY
          )
          matching[localY * region.width + localX] =
            green >= priors.minimumGreen
            && Int(green) - Int(red) >= Int(priors.minimumGreenOverRed)
            && Int(green) - Int(blue) >= Int(priors.minimumGreenOverBlue)
        }
      }
      return matching
    }

    var visited = [Bool](repeating: false, count: count)
    var components: [PixelComponent] = []
    for seed in 0..<count where matching[seed] && !visited[seed] {
      try Task.checkCancellation()
      var queue = [seed]
      var cursor = 0
      visited[seed] = true
      var pixelCount = 0
      var xSum = 0.0
      var ySum = 0.0
      var minX = Int.max
      var minY = Int.max
      var maxX = Int.min
      var maxY = Int.min
      while cursor < queue.count {
        if cursor.isMultiple(of: 4_096) { try Task.checkCancellation() }
        let index = queue[cursor]
        cursor += 1
        let localX = index % region.width
        let localY = index / region.width
        let x = region.x + localX
        let y = region.y + localY
        pixelCount += 1
        xSum += Double(x)
        ySum += Double(y)
        minX = min(minX, x)
        minY = min(minY, y)
        maxX = max(maxX, x)
        maxY = max(maxY, y)

        for deltaY in -1...1 {
          for deltaX in -1...1 where deltaX != 0 || deltaY != 0 {
            let nextX = localX + deltaX
            let nextY = localY + deltaY
            guard nextX >= 0, nextX < region.width,
              nextY >= 0, nextY < region.height
            else { continue }
            let next = nextY * region.width + nextX
            guard matching[next], !visited[next] else { continue }
            visited[next] = true
            queue.append(next)
          }
        }
      }
      components.append(
        PixelComponent(
          pixelCount: pixelCount,
          minX: minX,
          minY: minY,
          maxX: maxX,
          maxY: maxY,
          centroidX: xSum / Double(pixelCount),
          centroidY: ySum / Double(pixelCount)
        ))
    }
    return components
  }

  private func frameSide(
    frame: StampedFrame,
    region: PixelRect,
    orientation: FrameSideOrientation,
    priors: PlotterSceneVisionPriors
  ) throws -> FrameSideMeasurement? {
    let primaryCount = orientation == .top ? region.width : region.height
    let points = try frame.bytes.withUnsafeBytes { bytes in
      var points: [RegressionPoint] = []
      for primary in 0..<primaryCount {
        try Task.checkCancellation()
        var secondaryMatches: [Int] = []
        let secondaryCount = orientation == .top ? region.height : region.width
        for secondary in 0..<secondaryCount {
          let x = orientation == .top ? region.x + primary : region.x + secondary
          let y = orientation == .top ? region.y + secondary : region.y + primary
          let (red, green, blue) = Self.rgb(frame: frame, bytes: bytes, x: x, y: y)
          guard blue >= priors.minimumBlue,
            Int(blue) - Int(red) >= Int(priors.minimumBlueOverRed),
            Int(blue) - Int(green) >= Int(priors.minimumBlueOverGreen)
          else { continue }
          secondaryMatches.append(secondary)
        }
        guard secondaryMatches.count >= 4 else { continue }
        let fraction = orientation == .top ? 0.90 : 0.10
        let index = Int((Double(secondaryMatches.count - 1) * fraction).rounded(.down))
        if orientation == .top {
          points.append(
            RegressionPoint(
              independent: Double(region.x + primary),
              dependent: Double(region.y + secondaryMatches[index])
            ))
        } else {
          points.append(
            RegressionPoint(
              independent: Double(region.y + primary),
              dependent: Double(region.x + secondaryMatches[index])
            ))
        }
      }
      return points
    }

    let minimumSupport = max(
      2,
      Int((Double(primaryCount) * priors.minimumLineSupportFraction).rounded(.up))
    )
    guard points.count >= minimumSupport else { return nil }
    let supportCount = points.count
    guard let seed = robustLineSeed(points) else { return nil }
    var slope = seed.slope
    var intercept = seed.intercept
    var inliers = points.filter {
      abs($0.dependent - (slope * $0.independent + intercept))
        <= priors.lineResidualLimitPixels
    }
    guard inliers.count >= minimumSupport else { return nil }
    for _ in 0..<3 {
      guard let fit = linearFit(inliers) else { return nil }
      slope = fit.slope
      intercept = fit.intercept
      inliers = points.filter {
        abs($0.dependent - (slope * $0.independent + intercept))
          <= priors.lineResidualLimitPixels
      }
      guard inliers.count >= minimumSupport else { return nil }
    }
    guard let finalFit = linearFit(inliers) else { return nil }
    slope = finalFit.slope
    intercept = finalFit.intercept
    let rms = sqrt(
      inliers.reduce(0) {
        let residual = $1.dependent - (slope * $1.independent + intercept)
        return $0 + residual * residual
      } / Double(inliers.count)
    )
    let coverage = Double(inliers.count) / Double(primaryCount)
    let supportScore = min(1, coverage / priors.minimumLineSupportFraction)
    let residualScore = max(0, 1 - rms / (priors.lineResidualLimitPixels * 2))
    let geometry: Polyline<CameraPixelSpace>
    switch orientation {
    case .top:
      let startX = Double(region.x)
      let endX = Double(region.x + region.width - 1)
      geometry = try Polyline(points: [
        try Point2(x: startX, y: slope * startX + intercept),
        try Point2(x: endX, y: slope * endX + intercept),
      ])
    case .right:
      let startY = Double(region.y)
      let endY = Double(region.y + region.height - 1)
      geometry = try Polyline(points: [
        try Point2(x: slope * startY + intercept, y: startY),
        try Point2(x: slope * endY + intercept, y: endY),
      ])
    }
    return FrameSideMeasurement(
      geometry: geometry,
      supportPointCount: supportCount,
      inlierCount: inliers.count,
      rmsResidualPixels: rms,
      confidence: supportScore * residualScore
    )
  }

  private func robustLineSeed(
    _ points: [RegressionPoint]
  ) -> (slope: Double, intercept: Double)? {
    guard points.count >= 2 else { return nil }
    let ordered = points.sorted { $0.independent < $1.independent }
    let groupCount = max(1, ordered.count / 3)
    let first = Array(ordered.prefix(groupCount))
    let last = Array(ordered.suffix(groupCount))
    let firstIndependent = median(first.map(\.independent))
    let lastIndependent = median(last.map(\.independent))
    guard lastIndependent > firstIndependent else { return nil }
    let slope =
      (median(last.map(\.dependent)) - median(first.map(\.dependent)))
      / (lastIndependent - firstIndependent)
    let intercept = median(ordered.map { $0.dependent - slope * $0.independent })
    return (slope, intercept)
  }

  private func median(_ values: [Double]) -> Double {
    let ordered = values.sorted()
    let middle = ordered.count / 2
    if ordered.count.isMultiple(of: 2) {
      return (ordered[middle - 1] + ordered[middle]) / 2
    }
    return ordered[middle]
  }

  private func linearFit(_ points: [RegressionPoint]) -> (slope: Double, intercept: Double)? {
    guard points.count >= 2 else { return nil }
    let count = Double(points.count)
    let meanIndependent = points.reduce(0) { $0 + $1.independent } / count
    let meanDependent = points.reduce(0) { $0 + $1.dependent } / count
    let denominator = points.reduce(0) {
      let delta = $1.independent - meanIndependent
      return $0 + delta * delta
    }
    guard denominator > 0 else { return nil }
    let slope = points.reduce(0) {
      $0 + ($1.independent - meanIndependent) * ($1.dependent - meanDependent)
    } / denominator
    return (slope, meanDependent - slope * meanIndependent)
  }

  private static func rgb(
    frame: StampedFrame,
    bytes: UnsafeRawBufferPointer,
    x: Int,
    y: Int
  ) -> (UInt8, UInt8, UInt8) {
    let offset = y * frame.rowBytes + x * frame.pixelFormat.bytesPerPixel
    switch frame.pixelFormat {
    case .gray8:
      let value = bytes[offset]
      return (value, value, value)
    case .rgba8:
      return (bytes[offset], bytes[offset + 1], bytes[offset + 2])
    case .bgra8:
      return (bytes[offset + 2], bytes[offset + 1], bytes[offset])
    }
  }
}
