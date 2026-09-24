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

/// Image-space search hints and inferred armature geometry. A predicted cap
/// center changes scan order only; observed components determine the result.
public struct PlotterSceneVisionPriors: Hashable, Sendable {
  public let capSearchRegion: PixelRect
  public let penCapColor: PenCapColor
  public let penCapReference: PenCapVisualReference?
  public let markerReference: SampledColorMarkerReference?
  public let referenceBinding: PenCapReferenceBinding?
  public let searchCenter: Point2<CameraPixelSpace>?
  public let armatureHalfWidthFraction: Double
  public let armatureTopMarginFraction: Double
  public let armatureHeightFraction: Double
  public let algorithmRevision: String

  public init(
    capSearchRegion: PixelRect,
    penCapColor: PenCapColor = .green,
    penCapReference: PenCapVisualReference? = nil,
    markerReference: SampledColorMarkerReference? = nil,
    referenceBinding: PenCapReferenceBinding? = nil,
    searchCenter: Point2<CameraPixelSpace>? = nil,
    armatureHalfWidthFraction: Double = 0.055,
    armatureTopMarginFraction: Double = 0.025,
    armatureHeightFraction: Double = 0.56,
    algorithmRevision: String = "plotter-scene-v1"
  ) throws {
    guard
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
    self.penCapReference = penCapReference
    self.markerReference = markerReference
    self.referenceBinding = referenceBinding
    self.searchCenter = searchCenter
    self.armatureHalfWidthFraction = armatureHalfWidthFraction
    self.armatureTopMarginFraction = armatureTopMarginFraction
    self.armatureHeightFraction = armatureHeightFraction
    self.algorithmRevision = algorithmRevision
  }

  public static func sceneDefaults(
    frameWidth: Int,
    frameHeight: Int,
    analysisRegion: PixelRect? = nil,
    penCapColor: PenCapColor = .green,
    penCapReference: PenCapVisualReference? = nil,
    markerReference: SampledColorMarkerReference? = nil,
    referenceBinding: PenCapReferenceBinding? = nil,
    searchCenter: Point2<CameraPixelSpace>? = nil
  ) throws -> Self {
    guard frameWidth > 0, frameHeight > 0 else { throw FrameError.invalidDimensions }
    let fullFrame = PixelRect(x: 0, y: 0, width: frameWidth, height: frameHeight)
    let canonicalRegion = analysisRegion == fullFrame ? nil : analysisRegion
    let region = canonicalRegion ?? fullFrame
    guard region.x >= 0, region.y >= 0, region.width > 0, region.height > 0,
      region.x + region.width <= frameWidth,
      region.y + region.height <= frameHeight
    else { throw FrameError.invalidRegion }
    let algorithmRevision =
      canonicalRegion.map {
        "observed-cap-components-v4:cap-\(penCapColor.hexRGB):region-\($0.x)-\($0.y)-\($0.width)-\($0.height)"
      } ?? "observed-cap-components-v4:cap-\(penCapColor.hexRGB):full-frame"
    return try Self(
      capSearchRegion: region,
      penCapColor: penCapColor,
      penCapReference: penCapReference,
      markerReference: markerReference,
      referenceBinding: referenceBinding,
      searchCenter: searchCenter,
      algorithmRevision: markerReference?.estimatorRevision
        ?? penCapReference.map { "\(PenCapVisualReference.revision):\($0.identity)" } ?? algorithmRevision
    )
  }
}

public struct PenCapMeasurement: Hashable, Sendable {
  public var referenceAnchor: Point2<CameraPixelSpace>? = nil
  public var trackingPoint: Point2<CameraPixelSpace> { referenceAnchor ?? centroid }
  public let pixelCount: Int
  public let boundingBox: PixelRect
  public let centroid: Point2<CameraPixelSpace>
  public let confidence: Double
}

public struct PenCapCandidateDiagnostic: Hashable, Sendable {
  public let pixelCount: Int
  public let boundingBox: PixelRect
  public let colorSimilarity: Double
  public let supportScore: Double
  public let aspectRatio: Double
  public let fillFraction: Double
  public let confidence: Double
}

public struct PenCapTemplateCandidateDiagnostic: Hashable, Sendable {
  public let score: Double
  public let boundingBox: PixelRect
  public let anchor: Point2<CameraPixelSpace>
}

public enum PenCapTemplateRejectionReason: Hashable, Sendable {
  case referenceClipped

  public var detail: String {
    switch self {
    case .referenceClipped: "reference is clipped by the image or search-region edge"
    }
  }
}

public struct PenCapTemplateDiagnostics: Hashable, Sendable {
  public let candidates: [PenCapTemplateCandidateDiagnostic]
  public let acceptanceThreshold: Double
  public let requiredMargin: Double
  public let competitorScore: Double?
  public let predictionResidualPixels: Double?
  public let confirmedExampleCount: Int
  public var rejectionReason: PenCapTemplateRejectionReason? = nil

  public var summary: String {
    let score = candidates.first.map { String(format: "%.3f", $0.score) } ?? "none"
    let margin = candidates.first.flatMap { best in competitorScore.map { best.score - $0 } }
    var result = "template score \(score) (minimum \(String(format: "%.3f", acceptanceThreshold)))"
    if let margin { result += "; competing-match margin \(String(format: "%.3f", margin)) (minimum \(String(format: "%.3f", requiredMargin)))" }
    if let predictionResidualPixels { result += "; prediction residual \(String(format: "%.2f", predictionResidualPixels)) camera pixels" }
    if let rejectionReason { result += "; \(rejectionReason.detail)" }
    return result
  }
}

public struct PenCapDiagnostics: Hashable, Sendable {
  public let inspectedPixelCount: Int
  public let thresholdPixelCount: Int
  public let componentCount: Int
  public let candidates: [PenCapCandidateDiagnostic]
  public var template: PenCapTemplateDiagnostics? = nil
}

public enum PenCapDetectionResult: Hashable, Sendable {
  case notRequested
  case found(PenCapMeasurement, diagnostics: PenCapDiagnostics)
  case notFound(PenCapDiagnostics)
  case ambiguous(candidatePixelCounts: [Int], diagnostics: PenCapDiagnostics)
  case failed(String)

  public var measurement: PenCapMeasurement? {
    guard case .found(let measurement, _) = self else { return nil }
    return measurement
  }

  public var diagnostics: PenCapDiagnostics? {
    switch self {
    case .found(_, let diagnostics), .notFound(let diagnostics), .ambiguous(_, let diagnostics): diagnostics
    case .notRequested, .failed: nil
    }
  }

  public var diagnosticReason: String {
    switch self {
    case .notRequested: "not requested"
    case .found: "found"
    case .notFound(let diagnostics):
      if let template = diagnostics.template { "Reference tracking lost: \(template.summary)" }
      else if diagnostics.thresholdPixelCount > 0 {
        "colored candidates were found, but none passed the reference size or complete-visibility checks"
      }
      else { "no pixels passed the selected pen-cap color thresholds" }
    case .ambiguous(let counts, let diagnostics):
      if let template = diagnostics.template { "Reference tracking ambiguous: \(template.summary)" }
      else { "candidate sizes \(counts.map(String.init).joined(separator: ", ")); refusing to choose" }
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
  private var lastReferenceMatch: (identity: String, configuration: CameraConfigurationID, time: UInt64, point: Point2<CameraPixelSpace>)?

  struct PixelComponent {
    let pixelCount: Int
    let minX: Int
    let minY: Int
    let maxX: Int
    let maxY: Int
    let centroidX: Double
    let centroidY: Double
    let colorSimilarity: Double
    var containsSelectionPoint: Bool = false
    var selectionSupportIndices: [Int]? = nil
    var bounds: PixelRect { PixelRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1) }

    // Color agreement dominates raw area; additional pixels contribute with
    // diminishing weight. This is ranking, never a score acceptance threshold.
    var supportScore: Double { sqrt(Double(pixelCount)) * colorSimilarity * colorSimilarity }
  }

  public init() {}

  public func inspectPlotterScene(
    in frame: StampedFrame,
    requestedFeatures: SceneFeatureSet,
    priors suppliedPriors: PlotterSceneVisionPriors? = nil,
    analysisRegion: PixelRect? = nil,
    penCapColor: PenCapColor = .green,
    penCapReference: PenCapVisualReference? = nil,
    markerReference: SampledColorMarkerReference? = nil,
    referenceBinding: PenCapReferenceBinding? = nil,
    searchCenter: Point2<CameraPixelSpace>? = nil
  ) throws -> PlotterSceneMeasurement {
    let frame = frame.materializingContentHash(for: .analysis)
    let frameSHA256 = frame.contentSHA256
    let expandedFeatures = requestedFeatures.expandingDependencies
    let priors =
      try suppliedPriors
      ?? PlotterSceneVisionPriors.sceneDefaults(
        frameWidth: frame.width,
        frameHeight: frame.height,
        analysisRegion: analysisRegion,
        penCapColor: penCapColor,
        penCapReference: penCapReference,
        markerReference: markerReference,
        referenceBinding: referenceBinding,
        searchCenter: searchCenter
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
          geometry: .point(cap.trackingPoint),
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
      "\(frameSHA256)|\(priors.algorithmRevision)|\(requestedFeatures.rawValue)|"
      + "\(penCap)|\(armatureEnvelope)|\(computation)"
    return PlotterSceneMeasurement(
      frameID: frame.id,
      frameSHA256: frameSHA256,
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
    let frame = frame.materializingContentHash(for: .analysis)
    let frameSHA256 = frame.contentSHA256
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
      "\(frameSHA256)|\(request.algorithmRevision)|\(matching)|\(sampled)|\(lumaSum)"
    return MeasurementResult(
      frameID: frame.id,
      frameSHA256: frameSHA256,
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
    if let marker = priors.markerReference {
      guard priors.penCapReference == nil,
        priors.referenceBinding?.admits(marker, frame: frame) == true else {
        return .failed("Marker tracking requires the saved marker's matching camera and optical configuration.")
      }
      return try detectColorMarker(frame: frame, priors: priors, marker: marker)
    }
    if let reference = priors.penCapReference {
      let result = try PenCapTemplateMatcher.detect(frame: frame, reference: reference,
        region: priors.capSearchRegion, searchCenter: priors.searchCenter, binding: priors.referenceBinding)
      if let cap = result.measurement {
        let identity = reference.identity
        if let previous = lastReferenceMatch, previous.identity == identity,
          previous.configuration == frame.cameraConfigurationID,
          frame.captureNanoseconds > previous.time {
          let seconds = Double(frame.captureNanoseconds - previous.time) / 1_000_000_000
          // Short-interval continuity is deliberately generous; a long capture
          // gap requires global reacquisition with the same uniqueness checks.
          let travel = Double(max(reference.region.width, reference.region.height)) * 2
            + Double(max(frame.width, frame.height)) * 0.5 * seconds
          if seconds <= 2, previous.point.distance(to: cap.trackingPoint) > travel {
            return .failed("Reference tracking lost: the matching region jumped too far between frames.")
          }
        }
        if lastReferenceMatch?.identity != identity
          || lastReferenceMatch?.configuration != frame.cameraConfigurationID
          || frame.captureNanoseconds >= (lastReferenceMatch?.time ?? 0) {
          lastReferenceMatch = (identity, frame.cameraConfigurationID, frame.captureNanoseconds, cap.trackingPoint)
        }
      }
      return result
    }
    let components = try Self.colorComponents(
      frame: frame,
      region: priors.capSearchRegion,
      color: priors.penCapColor, searchCenter: priors.searchCenter
    )
    let thresholdPixelCount = components.reduce(0) { $0 + $1.pixelCount }
    let totalSupport = components.reduce(0.0) { $0 + $1.supportScore }
    let inspectedPixelCount = priors.capSearchRegion.width * priors.capSearchRegion.height
    let candidates = components.map { component -> PenCapCandidateDiagnostic in
      let width = component.maxX - component.minX + 1
      let height = component.maxY - component.minY + 1
      let aspect = Double(width) / Double(height)
      let fill = Double(component.pixelCount) / Double(width * height)
      // Relative color support and fill describe the observation; neither is
      // an acceptance gate. No frame-area, aspect, or learned-position cutoff.
      let confidence = component.supportScore / totalSupport * fill
      return PenCapCandidateDiagnostic(
        pixelCount: component.pixelCount,
        boundingBox: PixelRect(
          x: component.minX,
          y: component.minY,
          width: width,
          height: height
        ),
        colorSimilarity: component.colorSimilarity,
        supportScore: component.supportScore,
        aspectRatio: aspect,
        fillFraction: fill,
        confidence: confidence
      )
    }.sorted(by: candidatePrecedes)
    let diagnostics = PenCapDiagnostics(
      inspectedPixelCount: inspectedPixelCount,
      thresholdPixelCount: thresholdPixelCount,
      componentCount: components.count,
      candidates: candidates
    )
    guard thresholdPixelCount > 0 else { return .notFound(diagnostics) }
    guard let leading = candidates.first else { return .notFound(diagnostics) }
    if candidates.count > 1 {
      let second = candidates[1]
      if second.supportScore == leading.supportScore {
        return .ambiguous(
          candidatePixelCounts: candidates.map(\.pixelCount),
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
    if lhs.supportScore != rhs.supportScore { return lhs.supportScore > rhs.supportScore }
    if lhs.boundingBox.y != rhs.boundingBox.y { return lhs.boundingBox.y < rhs.boundingBox.y }
    if lhs.boundingBox.x != rhs.boundingBox.x { return lhs.boundingBox.x < rhs.boundingBox.x }
    if lhs.boundingBox.height != rhs.boundingBox.height {
      return lhs.boundingBox.height < rhs.boundingBox.height
    }
    return lhs.boundingBox.width < rhs.boundingBox.width
  }

  private func detectColorMarker(frame: StampedFrame, priors: PlotterSceneVisionPriors,
    marker: SampledColorMarkerReference) throws -> PenCapDetectionResult {
    let components = try Self.colorComponents(frame: frame, region: priors.capSearchRegion,
      color: marker.color, searchCenter: nil, markerPolicy: true,
      markerMinimumSaturation: marker.minimumSaturation)
    let candidates = components.map { component in
      let bounds = component.bounds
      return PenCapCandidateDiagnostic(pixelCount: component.pixelCount, boundingBox: bounds,
        colorSimilarity: component.colorSimilarity, supportScore: component.supportScore,
        aspectRatio: Double(bounds.width) / Double(bounds.height),
        fillFraction: Double(component.pixelCount) / Double(bounds.width * bounds.height),
        confidence: component.colorSimilarity)
    }.sorted(by: candidatePrecedes)
    let diagnostics = PenCapDiagnostics(
      inspectedPixelCount: priors.capSearchRegion.width * priors.capSearchRegion.height,
      thresholdPixelCount: components.reduce(0) { $0 + $1.pixelCount },
      componentCount: components.count, candidates: candidates)
    let compatible = components.filter { marker.acceptsGeometry($0, region: priors.capSearchRegion) }
    guard let component = compatible.first else { return .notFound(diagnostics) }
    guard compatible.count == 1 else {
      return .ambiguous(candidatePixelCounts: compatible.map(\.pixelCount), diagnostics: diagnostics)
    }
    let centroid = try Point2<CameraPixelSpace>(x: component.centroidX, y: component.centroidY)
    return .found(PenCapMeasurement(referenceAnchor: centroid,
      pixelCount: component.pixelCount, boundingBox: component.bounds,
      centroid: centroid, confidence: component.colorSimilarity), diagnostics: diagnostics)
  }

  private func armatureEstimate(
    cap: PenCapMeasurement,
    frame: StampedFrame,
    priors: PlotterSceneVisionPriors
  ) throws -> ArmatureEstimate {
    let halfWidth = Double(frame.width) * priors.armatureHalfWidthFraction
    let topMargin = Double(frame.height) * priors.armatureTopMarginFraction
    let height = Double(frame.height) * priors.armatureHeightFraction
    let minX = max(0, cap.trackingPoint.x - halfWidth)
    let maxX = min(Double(frame.width - 1), cap.trackingPoint.x + halfWidth)
    let capTop = priors.penCapReference == nil && priors.markerReference == nil
      ? Double(cap.boundingBox.y) : cap.trackingPoint.y
    let minY = max(0, capTop - topMargin)
    let maxY = min(Double(frame.height - 1), minY + height)
    return ArmatureEstimate(
      bounds: try AxisAlignedBounds(
        minX: minX,
        minY: minY,
        maxX: maxX,
        maxY: maxY
      ),
      confidence: min(1, cap.confidence * 0.55),
      basis: priors.markerReference != nil ? "marker-centroid-anchored envelope; inferred, not segmented"
        : priors.penCapReference?.isRigidHolder == true
        ? "holder-landmark-anchored envelope; inferred, not segmented"
        : "cap-anchored C920 envelope; inferred, not segmented"
    )
  }

  static func colorComponents(
    frame: StampedFrame,
    region: PixelRect,
    color: PenCapColor,
    searchCenter: Point2<CameraPixelSpace>?,
    markerPolicy: Bool = false,
    selectionPoint: Point2<CameraPixelSpace>? = nil,
    markerMinimumSaturation: Double? = nil
  ) throws -> [PixelComponent] {
    let count = region.width * region.height
    let selectedColor = Self.hsv(red: color.red, green: color.green, blue: color.blue)
    // Expand outwards from the hint, covering every pixel in the search domain.
    // A bad or off-image prediction cannot hide a component or break a tie.
    let columns = Self.centerOutIndices(count: region.width,
      center: searchCenter.map { $0.x - Double(region.x) })
    let rows = Self.centerOutIndices(count: region.height,
      center: searchCenter.map { $0.y - Double(region.y) })
    let matching = markerPolicy ? try Self.markerMask(frame: frame, region: region, color: color,
      minimumSaturation: markerMinimumSaturation)
      : try frame.bytes.withUnsafeBytes { bytes in
      var matching = [Float](repeating: 0, count: count)
      for localY in rows {
        try Task.checkCancellation()
        for localX in columns {
          let (red, green, blue) = Self.rgb(
            frame: frame,
            bytes: bytes,
            x: region.x + localX,
            y: region.y + localY
          )
          matching[localY * region.width + localX] = Float(Self.penCapColorSupport(
            red: red,
            green: green,
            blue: blue,
            selected: selectedColor
          ))
        }
      }
      return matching
    }

    var visited = [Bool](repeating: false, count: count)
    var components: [PixelComponent] = []
    var nextSeed = 0
    while nextSeed < count {
      let seed = nextSeed
      nextSeed += 1
      guard matching[seed] > 0, !visited[seed] else { continue }
      try Task.checkCancellation()
      var queue = [seed]
      var cursor = 0
      visited[seed] = true
      var pixelCount = 0
      var colorSupport = 0.0
      var xSum = 0.0
      var ySum = 0.0
      var minX = Int.max
      var minY = Int.max
      var maxX = Int.min
      var maxY = Int.min
      var containsSelectionPoint = false
      while cursor < queue.count {
        if cursor.isMultiple(of: 4_096) { try Task.checkCancellation() }
        let index = queue[cursor]
        cursor += 1
        let localX = index % region.width
        let localY = index / region.width
        let x = region.x + localX
        let y = region.y + localY
        if let selectionPoint, x == Int(selectionPoint.x), y == Int(selectionPoint.y) {
          containsSelectionPoint = true
        }
        pixelCount += 1
        colorSupport += Double(matching[index])
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
            guard matching[next] > 0, !visited[next] else { continue }
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
          centroidY: ySum / Double(pixelCount),
          colorSimilarity: colorSupport / Double(pixelCount),
          containsSelectionPoint: containsSelectionPoint,
          selectionSupportIndices: containsSelectionPoint ? queue : nil
        ))
    }
    return components
  }


  private static func centerOutIndices(count: Int, center: Double?) -> [Int] {
    guard let center else { return Array(0..<count) }
    let start = Int(min(Double(count - 1), max(0, center)).rounded())
    var indices = [start]
    indices.reserveCapacity(count)
    for distance in 1..<count {
      if start - distance >= 0 { indices.append(start - distance) }
      if start + distance < count { indices.append(start + distance) }
    }
    return indices
  }

  private static func penCapColorSupport(
    red: UInt8,
    green: UInt8,
    blue: UInt8,
    selected: (hueDegrees: Double, saturation: Double, value: Double)
  ) -> Double {
    let pixel = hsv(red: red, green: green, blue: blue)
    if selected.saturation < 0.15 {
      guard pixel.saturation <= 0.22,
        abs(pixel.value - selected.value) <= 0.18 else { return 0 }
      return (1 - abs(pixel.saturation - selected.saturation))
        * (1 - abs(pixel.value - selected.value))
    }

    let directHueDistance = abs(pixel.hueDegrees - selected.hueDegrees)
    let hueDistance = min(directHueDistance, 360 - directHueDistance)
    guard pixel.value >= 0.18,
      pixel.saturation >= max(0.18, selected.saturation * 0.35),
      hueDistance <= 28 else { return 0 }
    // Retain the existing color segmentation, then compare actual color to the
    // identified cap. A broad pale reflection has less chromatic support than
    // the saturated cap even when its raw component area is larger.
    let saturationSimilarity = min(pixel.saturation, selected.saturation)
      / max(pixel.saturation, selected.saturation)
    let hueSimilarity = (1 + cos(hueDistance * .pi / 180)) / 2
    let valueSimilarity = 1 - abs(pixel.value - selected.value)
    return saturationSimilarity * hueSimilarity * valueSimilarity
  }

  static func markerColorSupport(red: UInt8, green: UInt8, blue: UInt8,
    selectedHue: Double, minimumSaturation: Double) -> Double {
    let maximum = Int(max(red, green, blue))
    let delta = maximum - Int(min(red, green, blue))
    // Cheap integer rejection avoids HSV work for paper/rails. A fixed noise
    // floor rejects unusably dark/desaturated pixels; brightness does not rank
    // components or pull the centroid toward their brighter side.
    guard maximum >= 31, delta >= 20,
      Double(delta) / Double(maximum) >= minimumSaturation else { return 0 }
    let hue = hsv(red: red, green: green, blue: blue).hueDegrees
    let distance = abs(hue - selectedHue)
    return min(distance, 360 - distance) <= 22 ? 1 : 0
  }

  /// Full-resolution binary scan specialized for the selected marker. Hoisted
  /// byte layout and raw buffers avoid per-pixel generic RGB/HSV calls in Debug.
  /// This implements the scalar policy exactly, without downsampling or a ROI hint.
  static func markerMask(frame: StampedFrame, region: PixelRect, color: PenCapColor,
    minimumSaturation configuredMinimum: Double? = nil) throws -> [Float] {
    let selected = hsv(red: color.red, green: color.green, blue: color.blue)
    let minimumSaturation = configuredMinimum ?? max(0.25, selected.saturation * 0.5)
    let redOffset = frame.pixelFormat == .rgba8 ? 0 : 2
    let blueOffset = 2 - redOffset
    var mask = [Float](repeating: 0, count: region.width * region.height)
    try frame.bytes.withUnsafeBytes { raw in
      try mask.withUnsafeMutableBufferPointer { destination in
        let bytes = raw.bindMemory(to: UInt8.self).baseAddress!
        let output = destination.baseAddress!
        var y = 0
        while y < region.height {
          try Task.checkCancellation()
          var pixel = bytes + (region.y + y) * frame.rowBytes + region.x * 4
          var match = output + y * region.width
          var remaining = region.width
          while remaining > 0 {
            remaining -= 1
            let red = Int(pixel[redOffset]), green = Int(pixel[1]), blue = Int(pixel[blueOffset])
            pixel += 4
            let selectedPixel = match
            match += 1
            var maximum = red, minimum = red
            if green > maximum { maximum = green }; if blue > maximum { maximum = blue }
            if green < minimum { minimum = green }; if blue < minimum { minimum = blue }
            let delta = maximum - minimum
            if maximum < 31 || delta < 20 || Double(delta) / Double(maximum) < minimumSaturation { continue }
            let hue: Double
            if maximum == red {
              // The ratio is in [-1, 1], so remainder by six is unnecessary.
              let rawHue = 60 * (Double(green - blue) / Double(delta))
              hue = rawHue < 0 ? rawHue + 360 : rawHue
            } else if maximum == green {
              hue = 60 * (Double(blue - red) / Double(delta) + 2)
            } else {
              hue = 60 * (Double(red - green) / Double(delta) + 4)
            }
            let difference = hue - selected.hueDegrees
            let distance = difference < 0 ? -difference : difference
            if distance <= 22 || distance >= 338 { selectedPixel.pointee = 1 }
          }
          y += 1
        }
      }
    }
    return mask
  }

  static func hsv(
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

  static func rgb(
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
