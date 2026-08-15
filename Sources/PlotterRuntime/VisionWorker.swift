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
public struct SceneFeatureSet: OptionSet, Codable, Hashable, Sendable {
  public let rawValue: UInt8

  public static let penCap = Self(rawValue: 1 << 0)
  public static let armatureEnvelope = Self(rawValue: 1 << 1)

  public init(rawValue: UInt8) {
    self.rawValue = rawValue
  }

  public var expandingDependencies: Self {
    contains(.armatureEnvelope) ? union(.penCap) : self
  }
}

public enum SceneVisionKernel: String, Codable, CaseIterable, Hashable, Sendable {
  case penCap
  case armatureEnvelope
}

public struct SceneVisionComputationDiagnostics: Codable, Hashable, Sendable {
  public let requestedFeatures: SceneFeatureSet
  public let expandedFeatures: SceneFeatureSet
  public let executionCounts: [SceneVisionKernel: Int]
  public let inspectedPixelCounts: [SceneVisionKernel: Int]

  public var totalInspectedPixelCount: Int {
    inspectedPixelCounts.values.reduce(0, +)
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

public struct InkPixelThresholds: Codable, Hashable, Sendable {
  public let minimumLuminanceDecrease: UInt8

  /// Paired-frame ink observation is color-independent. This threshold is the
  /// minimum reference-to-observation luminance decrease for one new ink pixel.
  /// Values are experiment inputs, not accepted product thresholds.
  public init(minimumLuminanceDecrease: UInt8) {
    self.minimumLuminanceDecrease = minimumLuminanceDecrease
  }
}

/// Operator-selected visible pen-cap color used by scene analysis and camera
/// calibration. The value is an input to recognition, not evidence that the
/// selected color was observed in any frame.
public struct PenCapColor: Codable, Hashable, Sendable {
  public let red: UInt8
  public let green: UInt8
  public let blue: UInt8

  public init(red: UInt8, green: UInt8, blue: UInt8) {
    self.red = red
    self.green = green
    self.blue = blue
  }

  public init?(hexRGB: String) {
    let value = hexRGB.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
    guard value.count == 6, let packed = UInt32(value, radix: 16) else { return nil }
    self.init(
      red: UInt8((packed >> 16) & 0xFF),
      green: UInt8((packed >> 8) & 0xFF),
      blue: UInt8(packed & 0xFF)
    )
  }

  public var hexRGB: String {
    String(format: "%02X%02X%02X", red, green, blue)
  }

  public static let green = PenCapColor(red: 45, green: 185, blue: 105)
}

/// Image-space scene priors from the current fixed C920 view. These regions
/// narrow distractors; they do not define machine coordinates or a mm scale.
public struct PlotterSceneVisionPriors: Hashable, Sendable {
  public let capSearchRegion: PixelRect
  public let penCapColor: PenCapColor
  public let minimumCapPixels: Int
  public let maximumCapPixels: Int
  public let minimumAcceptedCapConfidence: Double
  public let ambiguousCandidatePixelRatio: Double
  public let armatureHalfWidthFraction: Double
  public let armatureTopMarginFraction: Double
  public let armatureHeightFraction: Double
  public let algorithmRevision: String

  public init(
    capSearchRegion: PixelRect,
    penCapColor: PenCapColor = .green,
    minimumCapPixels: Int,
    maximumCapPixels: Int,
    minimumAcceptedCapConfidence: Double = 0.20,
    ambiguousCandidatePixelRatio: Double = 0.85,
    armatureHalfWidthFraction: Double = 0.055,
    armatureTopMarginFraction: Double = 0.025,
    armatureHeightFraction: Double = 0.56,
    algorithmRevision: String = "plotter-scene-v1"
  ) throws {
    guard minimumCapPixels > 0, maximumCapPixels >= minimumCapPixels,
      minimumAcceptedCapConfidence.isFinite,
      minimumAcceptedCapConfidence > 0, minimumAcceptedCapConfidence <= 1,
      ambiguousCandidatePixelRatio.isFinite,
      ambiguousCandidatePixelRatio > 0, ambiguousCandidatePixelRatio <= 1,
      armatureHalfWidthFraction.isFinite,
      armatureHalfWidthFraction > 0, armatureHalfWidthFraction < 0.5,
      armatureTopMarginFraction.isFinite,
      armatureTopMarginFraction >= 0, armatureTopMarginFraction < 0.5,
      armatureHeightFraction.isFinite,
      armatureHeightFraction > 0, armatureHeightFraction <= 1,
      !algorithmRevision.isEmpty
    else { throw FrameError.invalidVisionPolicy }
    self.capSearchRegion = capSearchRegion
    self.penCapColor = penCapColor
    self.minimumCapPixels = minimumCapPixels
    self.maximumCapPixels = maximumCapPixels
    self.minimumAcceptedCapConfidence = minimumAcceptedCapConfidence
    self.ambiguousCandidatePixelRatio = ambiguousCandidatePixelRatio
    self.armatureHalfWidthFraction = armatureHalfWidthFraction
    self.armatureTopMarginFraction = armatureTopMarginFraction
    self.armatureHeightFraction = armatureHeightFraction
    self.algorithmRevision = algorithmRevision
  }

  public static func c920StartupDefaults(
    frameWidth: Int,
    frameHeight: Int,
    analysisRegion: PixelRect? = nil,
    penCapColor: PenCapColor = .green
  ) throws -> Self {
    guard frameWidth > 0, frameHeight > 0 else { throw FrameError.invalidDimensions }
    let fullFrame = PixelRect(x: 0, y: 0, width: frameWidth, height: frameHeight)
    let canonicalRegion = analysisRegion == fullFrame ? nil : analysisRegion
    let region = canonicalRegion ?? fullFrame
    guard region.x >= 0, region.y >= 0, region.width > 0, region.height > 0,
      region.x + region.width <= frameWidth,
      region.y + region.height <= frameHeight
    else { throw FrameError.invalidRegion }
    let fullFrameArea = frameWidth * frameHeight
    let algorithmRevision =
      canonicalRegion.map {
        "c920-startup-scene-v3:cap-\(penCapColor.hexRGB):region-\($0.x)-\($0.y)-\($0.width)-\($0.height)"
      } ?? "c920-startup-scene-v3:cap-\(penCapColor.hexRGB):full-frame"
    let capSearchRegion =
      canonicalRegion == nil
      ? scaledRegion(x: 0.24, y: 0.14, width: 0.66, height: 0.54, within: region)
      : region
    return try Self(
      capSearchRegion: capSearchRegion,
      penCapColor: penCapColor,
      minimumCapPixels: max(24, fullFrameArea / 40_000),
      maximumCapPixels: max(48, fullFrameArea / 200),
      algorithmRevision: algorithmRevision
    )
  }

  private static func scaledRegion(
    x: Double,
    y: Double,
    width: Double,
    height: Double,
    within region: PixelRect
  ) -> PixelRect {
    let originX = region.x + Int((Double(region.width) * x).rounded(.down))
    let originY = region.y + Int((Double(region.height) * y).rounded(.down))
    let maxX = min(
      region.x + region.width,
      region.x + Int((Double(region.width) * (x + width)).rounded(.up))
    )
    let maxY = min(
      region.y + region.height,
      region.y + Int((Double(region.height) * (y + height)).rounded(.up))
    )
    return PixelRect(
      x: originX,
      y: originY,
      width: max(1, maxX - originX),
      height: max(1, maxY - originY)
    )
  }
}

public struct PenCapMeasurement: Hashable, Sendable {
  public let pixelCount: Int
  public let boundingBox: PixelRect
  public let centroid: Point2<CameraPixelSpace>
  public let confidence: Double
}

public enum PenCapCandidateRejectionReason: Hashable, Sendable {
  case belowMinimumPixels(actual: Int, minimum: Int)
  case aboveMaximumPixels(actual: Int, maximum: Int)
  case aspectRatioOutside(actual: Double, minimum: Double, maximum: Double)
  case fillFractionBelow(actual: Double, minimum: Double)
  case confidenceBelow(actual: Double, minimum: Double)

  public var actionableDescription: String {
    switch self {
    case .belowMinimumPixels(let actual, let minimum):
      "\(actual) pixels is below minimum \(minimum)"
    case .aboveMaximumPixels(let actual, let maximum):
      "\(actual) pixels exceeds maximum \(maximum)"
    case .aspectRatioOutside(let actual, let minimum, let maximum):
      String(format: "aspect %.2f is outside %.2f...%.2f", actual, minimum, maximum)
    case .fillFractionBelow(let actual, let minimum):
      String(format: "fill %.2f is below %.2f", actual, minimum)
    case .confidenceBelow(let actual, let minimum):
      String(format: "confidence %.2f is below %.2f", actual, minimum)
    }
  }
}

public struct PenCapCandidateDiagnostic: Hashable, Sendable {
  public let pixelCount: Int
  public let boundingBox: PixelRect
  public let aspectRatio: Double
  public let fillFraction: Double
  public let confidence: Double
  public let rejectionReasons: [PenCapCandidateRejectionReason]
}

public struct PenCapDiagnostics: Hashable, Sendable {
  public let inspectedPixelCount: Int
  public let thresholdPixelCount: Int
  public let componentCount: Int
  public let candidates: [PenCapCandidateDiagnostic]
}

public enum PenCapDetectionResult: Hashable, Sendable {
  case notRequested
  case found(PenCapMeasurement, diagnostics: PenCapDiagnostics)
  case notFound(PenCapDiagnostics)
  case candidatesRejected(PenCapDiagnostics)
  case ambiguous(candidatePixelCounts: [Int], diagnostics: PenCapDiagnostics)
  case failed(String)

  public var measurement: PenCapMeasurement? {
    guard case .found(let measurement, _) = self else { return nil }
    return measurement
  }

  public var diagnosticReason: String {
    switch self {
    case .notRequested: "not requested"
    case .found: "found"
    case .notFound: "no pixels passed the selected pen-cap color thresholds"
    case .candidatesRejected(let diagnostics):
      diagnostics.candidates.flatMap(\.rejectionReasons).first?.actionableDescription
        ?? "all components were rejected"
    case .ambiguous(let counts, _):
      "candidate sizes \(counts.map(String.init).joined(separator: ", ")); refusing to choose"
    case .failed(let reason): reason
    }
  }
}

/// A deliberately coarse cap-anchored envelope for the visible moving
/// armature. It is an inferred occlusion prior, not pixel-segmented geometry.
public struct ArmatureEstimate: Hashable, Sendable {
  public let bounds: AxisAlignedBounds<CameraPixelSpace>
  public let confidence: Double
  public let basis: String
}

public enum ArmatureEnvelopeResult: Hashable, Sendable {
  case notRequested
  case available(ArmatureEstimate)
  case unavailableBecausePenCap(PenCapDetectionResult)
  case failed(String)

  public var estimate: ArmatureEstimate? {
    guard case .available(let estimate) = self else { return nil }
    return estimate
  }
}

public struct PlotterSceneMeasurement: Hashable, Sendable {
  public let frameID: FrameID
  public let frameSHA256: String
  public let cameraConfigurationID: CameraConfigurationID
  public let penCap: PenCapDetectionResult
  public let armatureEnvelope: ArmatureEnvelopeResult
  public let overlays: [CameraOverlayMeasurement]
  public let algorithmRevision: String
  public let diagnosticSHA256: String
  public let computation: SceneVisionComputationDiagnostics
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

  public init() {}

  public func inspectPlotterScene(
    in frame: StampedFrame,
    requestedFeatures: SceneFeatureSet,
    priors suppliedPriors: PlotterSceneVisionPriors? = nil,
    analysisRegion: PixelRect? = nil,
    penCapColor: PenCapColor = .green
  ) throws -> PlotterSceneMeasurement {
    let expandedFeatures = requestedFeatures.expandingDependencies
    let priors =
      try suppliedPriors
      ?? PlotterSceneVisionPriors.c920StartupDefaults(
        frameWidth: frame.width,
        frameHeight: frame.height,
        analysisRegion: analysisRegion,
        penCapColor: penCapColor
      )
    try validate(priors.capSearchRegion, in: frame)

    var executionCounts: [SceneVisionKernel: Int] = [:]
    var inspectedPixelCounts: [SceneVisionKernel: Int] = [:]
    let penCap: PenCapDetectionResult
    if expandedFeatures.contains(.penCap) {
      executionCounts[.penCap] = 1
      inspectedPixelCounts[.penCap] = priors.capSearchRegion.width * priors.capSearchRegion.height
      penCap = try detectPenCap(frame: frame, priors: priors)
    } else {
      penCap = .notRequested
    }
    let armatureEnvelope: ArmatureEnvelopeResult
    if expandedFeatures.contains(.armatureEnvelope) {
      executionCounts[.armatureEnvelope] = 1
      inspectedPixelCounts[.armatureEnvelope] = 0
      if let cap = penCap.measurement {
        armatureEnvelope = .available(
          try armatureEstimate(cap: cap, frame: frame, priors: priors)
        )
      } else {
        armatureEnvelope = .unavailableBecausePenCap(penCap)
      }
    } else {
      armatureEnvelope = .notRequested
    }

    let capProvenance = CameraMeasurementProvenance(
      kind: .penCap,
      source: .measured,
      algorithmRevision: priors.algorithmRevision
    )
    let armatureProvenance = CameraMeasurementProvenance(
      kind: .armatureEstimate,
      source: .inferred,
      algorithmRevision: "\(priors.algorithmRevision):cap-anchored-armature-v1"
    )
    var overlays: [CameraOverlayMeasurement] = []
    if requestedFeatures.contains(.penCap), let cap = penCap.measurement {
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
    if requestedFeatures.contains(.armatureEnvelope),
      let armature = armatureEnvelope.estimate
    {
      overlays.append(
        CameraOverlayMeasurement(
          frameID: frame.id,
          cameraConfigurationID: frame.cameraConfigurationID,
          geometry: .bounds(armature.bounds),
          provenance: armatureProvenance
        ))
    }
    let computation = SceneVisionComputationDiagnostics(
      requestedFeatures: requestedFeatures,
      expandedFeatures: expandedFeatures,
      executionCounts: executionCounts,
      inspectedPixelCounts: inspectedPixelCounts
    )
    let diagnostic =
      "\(frame.contentSHA256)|\(priors.algorithmRevision)|\(requestedFeatures.rawValue)|"
      + "\(penCap)|\(armatureEnvelope)|\(computation)"
    return PlotterSceneMeasurement(
      frameID: frame.id,
      frameSHA256: frame.contentSHA256,
      cameraConfigurationID: frame.cameraConfigurationID,
      penCap: penCap,
      armatureEnvelope: armatureEnvelope,
      overlays: overlays,
      algorithmRevision: priors.algorithmRevision,
      diagnosticSHA256: RunLedger.sha256Hex(Data(diagnostic.utf8)),
      computation: computation
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

  private func detectPenCap(
    frame: StampedFrame,
    priors: PlotterSceneVisionPriors
  ) throws -> PenCapDetectionResult {
    let components = try capColorComponents(
      frame: frame,
      region: priors.capSearchRegion,
      priors: priors
    )
    let thresholdPixelCount = components.reduce(0) { $0 + $1.pixelCount }
    let inspectedPixelCount = priors.capSearchRegion.width * priors.capSearchRegion.height
    let candidates = components.map { component -> PenCapCandidateDiagnostic in
      let width = component.maxX - component.minX + 1
      let height = component.maxY - component.minY + 1
      let aspect = Double(width) / Double(height)
      let fill = Double(component.pixelCount) / Double(width * height)
      let sizeScore = min(1, Double(component.pixelCount) / Double(priors.minimumCapPixels * 4))
      let fillScore = min(1, fill / 0.5)
      let confidence = sizeScore * fillScore
      var reasons: [PenCapCandidateRejectionReason] = []
      if component.pixelCount < priors.minimumCapPixels {
        reasons.append(
          .belowMinimumPixels(actual: component.pixelCount, minimum: priors.minimumCapPixels)
        )
      }
      if component.pixelCount > priors.maximumCapPixels {
        reasons.append(
          .aboveMaximumPixels(actual: component.pixelCount, maximum: priors.maximumCapPixels)
        )
      }
      if aspect < 0.25 || aspect > 4 {
        reasons.append(.aspectRatioOutside(actual: aspect, minimum: 0.25, maximum: 4))
      }
      if fill < 0.20 {
        reasons.append(.fillFractionBelow(actual: fill, minimum: 0.20))
      }
      if confidence < priors.minimumAcceptedCapConfidence {
        reasons.append(
          .confidenceBelow(actual: confidence, minimum: priors.minimumAcceptedCapConfidence)
        )
      }
      return PenCapCandidateDiagnostic(
        pixelCount: component.pixelCount,
        boundingBox: PixelRect(
          x: component.minX,
          y: component.minY,
          width: width,
          height: height
        ),
        aspectRatio: aspect,
        fillFraction: fill,
        confidence: confidence,
        rejectionReasons: reasons
      )
    }.sorted(by: candidatePrecedes)
    let diagnostics = PenCapDiagnostics(
      inspectedPixelCount: inspectedPixelCount,
      thresholdPixelCount: thresholdPixelCount,
      componentCount: components.count,
      candidates: candidates
    )
    guard thresholdPixelCount > 0 else { return .notFound(diagnostics) }
    let eligible = candidates.filter(\.rejectionReasons.isEmpty)
    guard let leading = eligible.first else { return .candidatesRejected(diagnostics) }
    if eligible.count > 1 {
      let second = eligible[1]
      if Double(second.pixelCount) / Double(leading.pixelCount)
        >= priors.ambiguousCandidatePixelRatio
      {
        return .ambiguous(
          candidatePixelCounts: eligible.map(\.pixelCount),
          diagnostics: diagnostics
        )
      }
    }
    let component = components.first {
      $0.pixelCount == leading.pixelCount
        && $0.minX == leading.boundingBox.x
        && $0.minY == leading.boundingBox.y
    }!
    return .found(
      PenCapMeasurement(
        pixelCount: component.pixelCount,
        boundingBox: leading.boundingBox,
        centroid: try Point2(x: component.centroidX, y: component.centroidY),
        confidence: leading.confidence
      ),
      diagnostics: diagnostics
    )
  }

  private func candidatePrecedes(
    _ lhs: PenCapCandidateDiagnostic,
    _ rhs: PenCapCandidateDiagnostic
  ) -> Bool {
    if lhs.pixelCount != rhs.pixelCount { return lhs.pixelCount > rhs.pixelCount }
    if lhs.boundingBox.y != rhs.boundingBox.y { return lhs.boundingBox.y < rhs.boundingBox.y }
    if lhs.boundingBox.x != rhs.boundingBox.x { return lhs.boundingBox.x < rhs.boundingBox.x }
    if lhs.boundingBox.height != rhs.boundingBox.height {
      return lhs.boundingBox.height < rhs.boundingBox.height
    }
    return lhs.boundingBox.width < rhs.boundingBox.width
  }

  private func armatureEstimate(
    cap: PenCapMeasurement,
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

  private func capColorComponents(
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
          matching[localY * region.width + localX] = Self.matchesPenCapColor(
            red: red,
            green: green,
            blue: blue,
            target: priors.penCapColor
          )
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


  private static func matchesPenCapColor(
    red: UInt8,
    green: UInt8,
    blue: UInt8,
    target: PenCapColor
  ) -> Bool {
    let pixel = hsv(red: red, green: green, blue: blue)
    let selected = hsv(red: target.red, green: target.green, blue: target.blue)

    if selected.saturation < 0.15 {
      return pixel.saturation <= 0.22
        && abs(pixel.value - selected.value) <= 0.18
    }

    let directHueDistance = abs(pixel.hueDegrees - selected.hueDegrees)
    let hueDistance = min(directHueDistance, 360 - directHueDistance)
    return pixel.value >= 0.18
      && pixel.saturation >= max(0.18, selected.saturation * 0.35)
      && hueDistance <= 28
  }

  private static func hsv(
    red: UInt8,
    green: UInt8,
    blue: UInt8
  ) -> (hueDegrees: Double, saturation: Double, value: Double) {
    let red = Double(red) / 255
    let green = Double(green) / 255
    let blue = Double(blue) / 255
    let maximum = max(red, green, blue)
    let minimum = min(red, green, blue)
    let delta = maximum - minimum
    let saturation = maximum == 0 ? 0 : delta / maximum
    guard delta > 0 else { return (0, saturation, maximum) }
    let rawHue: Double
    if maximum == red {
      rawHue = 60 * ((green - blue) / delta).truncatingRemainder(dividingBy: 6)
    } else if maximum == green {
      rawHue = 60 * (((blue - red) / delta) + 2)
    } else {
      rawHue = 60 * (((red - green) / delta) + 4)
    }
    return (rawHue < 0 ? rawHue + 360 : rawHue, saturation, maximum)
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
