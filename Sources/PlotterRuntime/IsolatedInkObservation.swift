import Foundation
import PlotterModel

public struct ExactFrameProvenance: Codable, Hashable, Sendable {
  public let frameID: FrameID
  public let frameSHA256: String
  public let captureNanoseconds: UInt64
  public let cameraConfigurationID: CameraConfigurationID
  public let width: Int
  public let height: Int
  public let rowBytes: Int
  public let pixelFormat: FramePixelFormat

  public init(frame: StampedFrame) {
    frameID = frame.id
    frameSHA256 = frame.contentSHA256
    captureNanoseconds = frame.captureNanoseconds
    cameraConfigurationID = frame.cameraConfigurationID
    width = frame.width
    height = frame.height
    rowBytes = frame.rowBytes
    pixelFormat = frame.pixelFormat
  }
}

public struct IsolatedInkObservationRequest: Hashable, Sendable {
  public let targetPresentBaseline: SamePoseFrameSample
  public let postLine: SamePoseFrameSample
  public let region: PixelRect
  public let thresholds: GreenPixelThresholds
  public let lineStartPoint: Point2<CameraPixelSpace>
  public let controllerSessionID: UUID
  public let coordinateRevision: UInt64
  public let toolPaperRevision: UUID
  public let controllerPositionToleranceMM: Double
  public let alignmentSearchRadiusPixels: Int
  public let maximumAlignmentShiftPixels: Int
  public let maximumBackgroundMeanAbsoluteDifference: Double
  public let projectedActualStrokeDelta: Vector2<CameraPixelSpace>?
  public let algorithmRevision: String
  public let minimumLinePixels: Int
  public let maximumLineMinorToMajorVarianceRatio: Double

  public init(
    targetPresentBaseline: SamePoseFrameSample,
    postLine: SamePoseFrameSample,
    region: PixelRect,
    thresholds: GreenPixelThresholds,
    lineStartPoint: Point2<CameraPixelSpace>,
    controllerSessionID: UUID,
    coordinateRevision: UInt64,
    toolPaperRevision: UUID,
    controllerPositionToleranceMM: Double,
    alignmentSearchRadiusPixels: Int,
    maximumAlignmentShiftPixels: Int,
    maximumBackgroundMeanAbsoluteDifference: Double,
    projectedActualStrokeDelta: Vector2<CameraPixelSpace>?,
    algorithmRevision: String,
    minimumLinePixels: Int = 5,
    maximumLineMinorToMajorVarianceRatio: Double = 0.25
  ) {
    self.targetPresentBaseline = targetPresentBaseline
    self.postLine = postLine
    self.region = region
    self.thresholds = thresholds
    self.lineStartPoint = lineStartPoint
    self.controllerSessionID = controllerSessionID
    self.coordinateRevision = coordinateRevision
    self.toolPaperRevision = toolPaperRevision
    self.controllerPositionToleranceMM = controllerPositionToleranceMM
    self.alignmentSearchRadiusPixels = alignmentSearchRadiusPixels
    self.maximumAlignmentShiftPixels = maximumAlignmentShiftPixels
    self.maximumBackgroundMeanAbsoluteDifference = maximumBackgroundMeanAbsoluteDifference
    self.projectedActualStrokeDelta = projectedActualStrokeDelta
    self.algorithmRevision = algorithmRevision
    self.minimumLinePixels = minimumLinePixels
    self.maximumLineMinorToMajorVarianceRatio = maximumLineMinorToMajorVarianceRatio
  }
}

public enum IsolatedInkRejectionReason: Codable, Hashable, Sendable {
  case invalidPolicy
  case invalidRegion
  case framesNotStrictlyIncreasing
  case cameraConfigurationMismatch
  case sourceMismatch
  case clearPoseMismatch(distanceMM: Double, toleranceMM: Double)
  case excessiveAlignment(shiftX: Int, shiftY: Int, maximumPixels: Int)
  case excessiveBackgroundResidual(actual: Double, maximum: Double)
  case dimensionMismatch
  case pixelFormatMismatch
  case lineMissing
  case lineTooSmall(actualPixels: Int, minimumPixels: Int)
  case lineAmbiguous(candidateCount: Int)
  case lineNotLineLike(minorToMajorVarianceRatio: Double)
}

public struct IsolatedInkRejection: Codable, Hashable, Sendable {
  public let reason: IsolatedInkRejectionReason
  public let targetPresentBaseline: ExactFrameProvenance
  public let postLine: ExactFrameProvenance
}

public struct IsolatedInkResidual: Codable, Hashable, Sendable {
  public let rootMeanSquareEndpointPixels: Double
  public let maximumEndpointPixels: Double
  public let rootMeanSquareCrossTrackPixels: Double
}

public struct IsolatedInkObservation: Codable, Hashable, Sendable {
  public let targetPresentBaseline: ExactFrameProvenance
  public let postLine: ExactFrameProvenance
  public let region: PixelRect
  public let lineStartPoint: Point2<CameraPixelSpace>
  public let source: FrameSourceIdentity
  public let controllerSessionID: UUID
  public let coordinateRevision: UInt64
  public let toolPaperRevision: UUID
  public let alignment: IntegerFrameAlignment
  public let observedEndpoints: [Point2<CameraPixelSpace>]
  public let observedCentreline: Polyline<CameraPixelSpace>
  public let observedPixelCount: Int
  public let displacementPixels: Vector2<CameraPixelSpace>
  public let orientationRadians: Double
  public let intendedLine: Polyline<CameraPixelSpace>?
  public let residual: IsolatedInkResidual?
  public let overlays: [CameraOverlayMeasurement]
  public let algorithmRevision: String
}

public enum IsolatedInkObservationOutcome: Codable, Hashable, Sendable {
  case observed(IsolatedInkObservation)
  case rejected(IsolatedInkRejection)
}

public struct SamePoseFrameSample: Hashable, Sendable {
  public let source: FrameSourceIdentity
  public let frame: StampedFrame
  public let controllerPosition: MachinePosition

  public init(displayedFrame: DisplayedFrame, controllerPosition: MachinePosition) {
    source = displayedFrame.source
    frame = displayedFrame.frame
    self.controllerPosition = controllerPosition
  }

  public init(
    source: FrameSourceIdentity,
    frame: StampedFrame,
    controllerPosition: MachinePosition
  ) {
    self.source = source
    self.frame = frame
    self.controllerPosition = controllerPosition
  }
}

public enum VisibilityTargetSearchCircleError: Error, Equatable, Sendable {
  case invalidRadius
  case emptyAlgorithmRevision
  case anchorOutsideFrame
}

/// Camera-configuration-specific acquisition support for the first visibility
/// mark. The centre is the cap landmark measured in one exact target-pose
/// frame. Until the ink centroid is observed, the cap-to-tip displacement is
/// unknown, so Vision searches this bounded circle rather than pretending the
/// cap landmark is the paper-contact point.
public struct VisibilityTargetSearchCircle: Codable, Hashable, Sendable,
  CustomStringConvertible
{
  public let center: Point2<CameraPixelSpace>
  public let radiusPixels: Double
  public let boundingROI: PixelRect
  public let anchorFrame: ExactFrameProvenance
  public let source: FrameSourceIdentity
  public let algorithmRevision: String

  public init(
    center: Point2<CameraPixelSpace>,
    radiusPixels: Double,
    anchor: DisplayedFrame,
    algorithmRevision: String
  ) throws {
    guard radiusPixels.isFinite, radiusPixels > 0 else {
      throw VisibilityTargetSearchCircleError.invalidRadius
    }
    guard !algorithmRevision.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw VisibilityTargetSearchCircleError.emptyAlgorithmRevision
    }
    guard center.x >= 0, center.x < Double(anchor.frame.width),
      center.y >= 0, center.y < Double(anchor.frame.height)
    else {
      throw VisibilityTargetSearchCircleError.anchorOutsideFrame
    }
    let minimumX = max(0, Int(floor(center.x - radiusPixels)))
    let minimumY = max(0, Int(floor(center.y - radiusPixels)))
    let maximumXExclusive = min(
      anchor.frame.width,
      Int(ceil(center.x + radiusPixels)) + 1
    )
    let maximumYExclusive = min(
      anchor.frame.height,
      Int(ceil(center.y + radiusPixels)) + 1
    )
    self.center = center
    self.radiusPixels = radiusPixels
    boundingROI = PixelRect(
      x: minimumX,
      y: minimumY,
      width: maximumXExclusive - minimumX,
      height: maximumYExclusive - minimumY
    )
    anchorFrame = ExactFrameProvenance(frame: anchor.frame)
    source = anchor.source
    self.algorithmRevision = algorithmRevision
  }

  public func contains(x: Int, y: Int) -> Bool {
    let dx = Double(x) - center.x
    let dy = Double(y) - center.y
    return dx * dx + dy * dy <= radiusPixels * radiusPixels
  }

  public var description: String {
    String(
      format: "circle center %.1f, %.1f · radius %.0f px · bounds %@ · anchor %@",
      center.x,
      center.y,
      radiusPixels,
      String(describing: boundingROI),
      anchorFrame.frameID.rawValue
    )
  }
}

public struct VisibilityTargetObservationRequest: Hashable, Sendable {
  public let baseline: SamePoseFrameSample
  public let targetSamples: [SamePoseFrameSample]
  public let targetSearchCircle: VisibilityTargetSearchCircle
  public let thresholds: GreenPixelThresholds
  public let controllerSessionID: UUID
  public let coordinateRevision: UInt64
  public let toolPaperRevision: UUID
  public let controllerPositionToleranceMM: Double
  public let expectedDiameterPixels: ClosedRange<Double>
  public let minimumTargetPixels: Int
  public let maximumCentroidSpreadPixels: Double
  public let maximumAreaRatio: Double
  public let maximumBackgroundMeanAbsoluteDifference: Double
  public let alignmentSearchRadiusPixels: Int
  public let maximumAlignmentShiftPixels: Int
  public let estimatorRevision: String
  public let algorithmRevision: String
  public let targetPlanRevision: String

  public init(
    baseline: SamePoseFrameSample,
    targetSamples: [SamePoseFrameSample],
    targetSearchCircle: VisibilityTargetSearchCircle,
    thresholds: GreenPixelThresholds,
    controllerSessionID: UUID,
    coordinateRevision: UInt64,
    toolPaperRevision: UUID,
    controllerPositionToleranceMM: Double,
    expectedDiameterPixels: ClosedRange<Double>,
    minimumTargetPixels: Int,
    maximumCentroidSpreadPixels: Double,
    maximumAreaRatio: Double,
    maximumBackgroundMeanAbsoluteDifference: Double,
    alignmentSearchRadiusPixels: Int = 2,
    maximumAlignmentShiftPixels: Int = 1,
    estimatorRevision: String = "two-frame-component-mean-v1",
    algorithmRevision: String,
    targetPlanRevision: String
  ) {
    self.baseline = baseline
    self.targetSamples = targetSamples
    self.targetSearchCircle = targetSearchCircle
    self.thresholds = thresholds
    self.controllerSessionID = controllerSessionID
    self.coordinateRevision = coordinateRevision
    self.toolPaperRevision = toolPaperRevision
    self.controllerPositionToleranceMM = controllerPositionToleranceMM
    self.expectedDiameterPixels = expectedDiameterPixels
    self.minimumTargetPixels = minimumTargetPixels
    self.maximumCentroidSpreadPixels = maximumCentroidSpreadPixels
    self.maximumAreaRatio = maximumAreaRatio
    self.maximumBackgroundMeanAbsoluteDifference = maximumBackgroundMeanAbsoluteDifference
    self.alignmentSearchRadiusPixels = alignmentSearchRadiusPixels
    self.maximumAlignmentShiftPixels = maximumAlignmentShiftPixels
    self.estimatorRevision = estimatorRevision
    self.algorithmRevision = algorithmRevision
    self.targetPlanRevision = targetPlanRevision
  }
}

public struct IntegerFrameAlignment: Codable, Hashable, Sendable {
  public let shiftX: Int
  public let shiftY: Int
  public let backgroundMeanAbsoluteDifference: Double
  public let estimatorRevision: String
  public let supportRegion: PixelRect
  public let exclusionRegion: PixelRect
  public let evaluatedPixelCount: Int
}

public struct VisibilityTargetObservationProgress: Hashable, Sendable {
  public let sampleIndex: Int
  public let sampleCount: Int

  public init(sampleIndex: Int, sampleCount: Int) {
    self.sampleIndex = sampleIndex
    self.sampleCount = sampleCount
  }
}

public struct VisibilityTargetComponentSample: Codable, Hashable, Sendable {
  public let frame: ExactFrameProvenance
  public let centroid: Point2<CameraPixelSpace>
  public let pixelCount: Int
  public let bounds: AxisAlignedBounds<CameraPixelSpace>
  public let alignment: IntegerFrameAlignment
}

public enum VisibilityTargetObservationRejection: Codable, Hashable, Sendable {
  case invalidPolicy
  case requiresExactlyTwoTargetFrames(actual: Int)
  case framesNotStrictlyIncreasing
  case sourceMismatch
  case cameraConfigurationMismatch
  case searchCircleProvenanceMismatch
  case dimensionMismatch
  case pixelFormatMismatch
  case invalidRegion
  case observationAlreadyInProgress
  case insufficientAlignmentSupport(frameID: FrameID, actualPixels: Int, minimumPixels: Int)
  case indeterminateAlignment(frameID: FrameID)
  case clearPoseMismatch(frameID: FrameID, distanceMM: Double, toleranceMM: Double)
  case excessiveAlignment(frameID: FrameID, shiftX: Int, shiftY: Int, maximumPixels: Int)
  case excessiveBackgroundResidual(frameID: FrameID, actual: Double, maximum: Double)
  case targetMissing(frameID: FrameID)
  case targetTooSmall(frameID: FrameID, actualPixels: Int, minimumPixels: Int)
  case targetAmbiguous(frameID: FrameID, candidateCount: Int)
  case expectedDiameterMismatch(frameID: FrameID, actualPixels: Double)
  case unstableCentroid(actualPixels: Double, maximumPixels: Double)
  case unstableAreaRatio(actual: Double, maximum: Double)
}

/// Stable target evidence from exactly two post-target frames compared with one
/// compatible same-pose pre-target baseline.
public struct VisibilityTargetObservation: Codable, Hashable, Sendable {
  public let source: FrameSourceIdentity
  public let baseline: ExactFrameProvenance
  public let samples: [VisibilityTargetComponentSample]
  public let includedFrameIDs: [FrameID]
  public let validSampleCount: Int
  public let estimatorRevision: String
  public let algorithmRevision: String
  public let targetPlanRevision: String
  public let centroid: Point2<CameraPixelSpace>
  public let centroidUncertainty: Vector2<CameraPixelSpace>
  public let areaRatio: Double
  public let expectedDiameterPixels: ClosedRange<Double>
  public let controllerSessionID: UUID
  public let coordinateRevision: UInt64
  public let toolPaperRevision: UUID
  public let searchCircle: VisibilityTargetSearchCircle
  public let overlays: [CameraOverlayMeasurement]
}

public enum PenTipOffsetRegistrationError: Error, Equatable, Sendable {
  case emptyEstimatorRevision
  case capAnchorFrameMismatch
  case sourceMismatch
  case cameraConfigurationMismatch
  case searchCircleAnchorMismatch
  case missingObservationFrames
}

/// Learned camera-pixel translation from the visible cap landmark to the
/// centre of ink made at the same machine target pose. This is intentionally
/// separate from machine-camera registration: the latter maps carriage motion
/// to the cap landmark, while this value locates the hidden pen tip.
public struct PenTipOffsetRegistration: Codable, Hashable, Sendable {
  public let capAnchor: Point2<CameraPixelSpace>
  public let observedTip: Point2<CameraPixelSpace>
  public let capToTipOffset: Vector2<CameraPixelSpace>
  public let capAnchorFrame: ExactFrameProvenance
  public let observedFrameIDs: [FrameID]
  public let source: FrameSourceIdentity
  public let cameraConfigurationID: CameraConfigurationID
  public let targetPlanRevision: String
  public let observedTipUncertainty: Vector2<CameraPixelSpace>
  public let capAnchorConfidence: Double
  public let estimatorRevision: String

  public init(
    capAnchor: ToolCapAnchorEstimate,
    anchorFrame: DisplayedFrame,
    observation: VisibilityTargetObservation,
    estimatorRevision: String
  ) throws {
    guard !estimatorRevision.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw PenTipOffsetRegistrationError.emptyEstimatorRevision
    }
    guard capAnchor.frameID == anchorFrame.frame.id,
      capAnchor.cameraConfigurationID == anchorFrame.frame.cameraConfigurationID
    else {
      throw PenTipOffsetRegistrationError.capAnchorFrameMismatch
    }
    guard capAnchor.source == anchorFrame.source,
      observation.source == anchorFrame.source
    else {
      throw PenTipOffsetRegistrationError.sourceMismatch
    }
    guard observation.samples.allSatisfy({
      $0.frame.cameraConfigurationID == anchorFrame.frame.cameraConfigurationID
    }) else {
      throw PenTipOffsetRegistrationError.cameraConfigurationMismatch
    }
    guard observation.searchCircle.center == capAnchor.point,
      observation.searchCircle.anchorFrame.frameID == anchorFrame.frame.id,
      observation.searchCircle.anchorFrame.frameSHA256 == anchorFrame.frame.contentSHA256
    else {
      throw PenTipOffsetRegistrationError.searchCircleAnchorMismatch
    }
    guard !observation.includedFrameIDs.isEmpty else {
      throw PenTipOffsetRegistrationError.missingObservationFrames
    }
    self.capAnchor = capAnchor.point
    observedTip = observation.centroid
    capToTipOffset = try capAnchor.point.vector(to: observation.centroid)
    capAnchorFrame = ExactFrameProvenance(frame: anchorFrame.frame)
    observedFrameIDs = observation.includedFrameIDs
    source = observation.source
    cameraConfigurationID = anchorFrame.frame.cameraConfigurationID
    targetPlanRevision = observation.targetPlanRevision
    observedTipUncertainty = observation.centroidUncertainty
    capAnchorConfidence = capAnchor.confidence
    self.estimatorRevision = estimatorRevision
  }

  public func tipPoint(
    from projectedCapAnchor: Point2<CameraPixelSpace>
  ) throws -> Point2<CameraPixelSpace> {
    try projectedCapAnchor.translated(by: capToTipOffset)
  }
}

public enum VisibilityTargetObservationOutcome: Codable, Hashable, Sendable {
  case observed(VisibilityTargetObservation)
  case rejected(VisibilityTargetObservationRejection)
  case cancelled
}

extension VisionWorker {
  public func observeVisibilityTarget(
    _ request: VisibilityTargetObservationRequest,
    progress: @Sendable (VisibilityTargetObservationProgress) -> Void = { _ in }
  ) -> VisibilityTargetObservationOutcome {
    guard !Task.isCancelled else { return .cancelled }
    guard request.targetSamples.count == 2 else {
      return .rejected(.requiresExactlyTwoTargetFrames(actual: request.targetSamples.count))
    }
    guard request.controllerPositionToleranceMM.isFinite,
      request.controllerPositionToleranceMM >= 0,
      request.expectedDiameterPixels.lowerBound.isFinite,
      request.expectedDiameterPixels.upperBound.isFinite,
      request.expectedDiameterPixels.lowerBound > 0,
      request.expectedDiameterPixels.upperBound >= request.expectedDiameterPixels.lowerBound,
      request.minimumTargetPixels > 0,
      request.maximumCentroidSpreadPixels.isFinite,
      request.maximumCentroidSpreadPixels >= 0,
      request.maximumAreaRatio.isFinite,
      request.maximumAreaRatio >= 1,
      request.maximumBackgroundMeanAbsoluteDifference.isFinite,
      request.maximumBackgroundMeanAbsoluteDifference >= 0,
      request.alignmentSearchRadiusPixels >= 0,
      request.maximumAlignmentShiftPixels >= 0,
      request.maximumAlignmentShiftPixels <= request.alignmentSearchRadiusPixels,
      !request.estimatorRevision.isEmpty,
      !request.algorithmRevision.isEmpty,
      !request.targetPlanRevision.isEmpty
    else { return .rejected(.invalidPolicy) }

    let frames = [request.baseline.frame] + request.targetSamples.map(\.frame)
    guard Set([request.baseline.source] + request.targetSamples.map(\.source)).count == 1 else {
      return .rejected(.sourceMismatch)
    }
    guard Set(frames.map(\.cameraConfigurationID)).count == 1 else {
      return .rejected(.cameraConfigurationMismatch)
    }
    guard request.targetSearchCircle.source == request.baseline.source,
      request.targetSearchCircle.anchorFrame.cameraConfigurationID
        == request.baseline.frame.cameraConfigurationID
    else {
      return .rejected(.searchCircleProvenanceMismatch)
    }
    guard Set(frames.map { "\($0.width)x\($0.height)" }).count == 1 else {
      return .rejected(.dimensionMismatch)
    }
    guard Set(frames.map(\.pixelFormat)).count == 1 else {
      return .rejected(.pixelFormatMismatch)
    }
    guard zip(frames, frames.dropFirst()).allSatisfy({ lhs, rhs in
      lhs.captureNanoseconds < rhs.captureNanoseconds && lhs.id != rhs.id
    }), Set(frames.map(\.id)).count == 3
    else { return .rejected(.framesNotStrictlyIncreasing) }
    let targetSearchBounds = request.targetSearchCircle.boundingROI
    guard Self.contains(targetSearchBounds, in: request.baseline.frame) else {
      return .rejected(.invalidRegion)
    }
    let alignmentSupportROI = Self.expanded(
      targetSearchBounds,
      by: 32,
      clippedTo: request.baseline.frame
    )
    let alignmentExclusionROI = Self.expanded(
      targetSearchBounds,
      by: request.alignmentSearchRadiusPixels,
      clippedTo: request.baseline.frame
    )

    var samples: [VisibilityTargetComponentSample] = []
    for (index, target) in request.targetSamples.enumerated() {
      guard !Task.isCancelled else { return .cancelled }
      progress(VisibilityTargetObservationProgress(
        sampleIndex: index + 1,
        sampleCount: request.targetSamples.count
      ))
      guard !Task.isCancelled else { return .cancelled }
      let poseDistance = request.baseline.controllerPosition.point.distance(
        to: target.controllerPosition.point
      )
      guard poseDistance <= request.controllerPositionToleranceMM else {
        return .rejected(.clearPoseMismatch(
          frameID: target.frame.id,
          distanceMM: poseDistance,
          toleranceMM: request.controllerPositionToleranceMM
        ))
      }
      let alignment: IntegerFrameAlignment
      switch Self.bestLocalIntegerAlignment(
        request.baseline.frame,
        target.frame,
        supportRegion: alignmentSupportROI,
        excluding: alignmentExclusionROI,
        searchRadius: request.alignmentSearchRadiusPixels,
        minimumSupportPixels: 1_024
      ) {
      case .aligned(let value):
        alignment = value
      case .insufficientSupport(let actual):
        return .rejected(.insufficientAlignmentSupport(
          frameID: target.frame.id,
          actualPixels: actual,
          minimumPixels: 1_024
        ))
      case .indeterminate:
        return .rejected(.indeterminateAlignment(frameID: target.frame.id))
      case .cancelled:
        return .cancelled
      }
      guard max(abs(alignment.shiftX), abs(alignment.shiftY))
        <= request.maximumAlignmentShiftPixels
      else {
        return .rejected(.excessiveAlignment(
          frameID: target.frame.id,
          shiftX: alignment.shiftX,
          shiftY: alignment.shiftY,
          maximumPixels: request.maximumAlignmentShiftPixels
        ))
      }
      guard alignment.backgroundMeanAbsoluteDifference
        <= request.maximumBackgroundMeanAbsoluteDifference
      else {
        return .rejected(.excessiveBackgroundResidual(
          frameID: target.frame.id,
          actual: alignment.backgroundMeanAbsoluteDifference,
          maximum: request.maximumBackgroundMeanAbsoluteDifference
        ))
      }
      guard let pixels = Self.cancellableNewGreenPixels(
        from: request.baseline.frame,
        to: target.frame,
        searchCircle: request.targetSearchCircle,
        thresholds: request.thresholds,
        observationShiftX: alignment.shiftX,
        observationShiftY: alignment.shiftY
      ) else { return .cancelled }
      guard !pixels.isEmpty else {
        return .rejected(.targetMissing(frameID: target.frame.id))
      }
      guard let components = Self.cancellableComponents(pixels) else { return .cancelled }
      let eligible = components.filter { $0.count >= request.minimumTargetPixels }
      guard !eligible.isEmpty else {
        return .rejected(.targetTooSmall(
          frameID: target.frame.id,
          actualPixels: components.map(\.count).max() ?? 0,
          minimumPixels: request.minimumTargetPixels
        ))
      }
      guard eligible.count == 1 else {
        return .rejected(.targetAmbiguous(
          frameID: target.frame.id,
          candidateCount: eligible.count
        ))
      }
      let component = eligible[0]
      let minX = component.map(\.x).min()!
      let maxX = component.map(\.x).max()!
      let minY = component.map(\.y).min()!
      let maxY = component.map(\.y).max()!
      let diameter = Double(max(maxX - minX, maxY - minY))
      guard request.expectedDiameterPixels.contains(diameter) else {
        return .rejected(.expectedDiameterMismatch(
          frameID: target.frame.id,
          actualPixels: diameter
        ))
      }
      let bounds = try! AxisAlignedBounds<CameraPixelSpace>(
        minX: Double(minX) - 0.5,
        minY: Double(minY) - 0.5,
        maxX: Double(maxX) + 0.5,
        maxY: Double(maxY) + 0.5
      )
      samples.append(VisibilityTargetComponentSample(
        frame: ExactFrameProvenance(frame: target.frame),
        centroid: Self.centroid(component),
        pixelCount: component.count,
        bounds: bounds,
        alignment: alignment
      ))
    }

    let centroidSpread = samples[0].centroid.distance(to: samples[1].centroid)
    guard centroidSpread <= request.maximumCentroidSpreadPixels else {
      return .rejected(.unstableCentroid(
        actualPixels: centroidSpread,
        maximumPixels: request.maximumCentroidSpreadPixels
      ))
    }
    let counts = samples.map { Double($0.pixelCount) }
    let areaRatio = counts.max()! / counts.min()!
    guard areaRatio <= request.maximumAreaRatio else {
      return .rejected(.unstableAreaRatio(actual: areaRatio, maximum: request.maximumAreaRatio))
    }
    let mean = try! Point2<CameraPixelSpace>(
      x: samples.reduce(0) { $0 + $1.centroid.x } / 2,
      y: samples.reduce(0) { $0 + $1.centroid.y } / 2
    )
    let uncertainty = try! Vector2<CameraPixelSpace>(
      dx: abs(samples[0].centroid.x - samples[1].centroid.x) / sqrt(2),
      dy: abs(samples[0].centroid.y - samples[1].centroid.y) / sqrt(2)
    )
    let overlays = samples.map {
      CameraOverlayMeasurement(
        frameID: $0.frame.frameID,
        cameraConfigurationID: $0.frame.cameraConfigurationID,
        geometry: .point($0.centroid),
        provenance: CameraMeasurementProvenance(
          kind: .observedInk,
          source: .measured,
          algorithmRevision: request.algorithmRevision
        )
      )
    }
    return .observed(VisibilityTargetObservation(
      source: request.baseline.source,
      baseline: ExactFrameProvenance(frame: request.baseline.frame),
      samples: samples,
      includedFrameIDs: samples.map { $0.frame.frameID },
      validSampleCount: samples.count,
      estimatorRevision: request.estimatorRevision,
      algorithmRevision: request.algorithmRevision,
      targetPlanRevision: request.targetPlanRevision,
      centroid: mean,
      centroidUncertainty: uncertainty,
      areaRatio: areaRatio,
      expectedDiameterPixels: request.expectedDiameterPixels,
      controllerSessionID: request.controllerSessionID,
      coordinateRevision: request.coordinateRevision,
      toolPaperRevision: request.toolPaperRevision,
      searchCircle: request.targetSearchCircle,
      overlays: overlays
    ))
  }

  public func observeIsolatedInk(
    _ request: IsolatedInkObservationRequest
  ) -> IsolatedInkObservationOutcome {
    let provenance = (
      baseline: ExactFrameProvenance(frame: request.targetPresentBaseline.frame),
      post: ExactFrameProvenance(frame: request.postLine.frame)
    )
    func reject(_ reason: IsolatedInkRejectionReason) -> IsolatedInkObservationOutcome {
      .rejected(IsolatedInkRejection(
        reason: reason,
        targetPresentBaseline: provenance.baseline,
        postLine: provenance.post
      ))
    }

    guard request.minimumLinePixels >= 2,
      request.maximumLineMinorToMajorVarianceRatio.isFinite,
      request.maximumLineMinorToMajorVarianceRatio >= 0,
      request.maximumLineMinorToMajorVarianceRatio < 1,
      request.controllerPositionToleranceMM.isFinite,
      request.controllerPositionToleranceMM >= 0,
      request.alignmentSearchRadiusPixels >= 0,
      request.maximumAlignmentShiftPixels >= 0,
      request.maximumAlignmentShiftPixels <= request.alignmentSearchRadiusPixels,
      request.maximumBackgroundMeanAbsoluteDifference.isFinite,
      request.maximumBackgroundMeanAbsoluteDifference >= 0,
      !request.algorithmRevision.isEmpty
    else { return reject(.invalidPolicy) }
    guard request.targetPresentBaseline.source == request.postLine.source else {
      return reject(.sourceMismatch)
    }
    let frames = [request.targetPresentBaseline.frame, request.postLine.frame]
    guard Set(frames.map(\.cameraConfigurationID)).count == 1 else {
      return reject(.cameraConfigurationMismatch)
    }
    guard Set(frames.map { "\($0.width)x\($0.height)" }).count == 1 else {
      return reject(.dimensionMismatch)
    }
    guard Set(frames.map(\.pixelFormat)).count == 1 else {
      return reject(.pixelFormatMismatch)
    }
    guard request.targetPresentBaseline.frame.captureNanoseconds
      < request.postLine.frame.captureNanoseconds,
      Set(frames.map(\.id)).count == 2
    else { return reject(.framesNotStrictlyIncreasing) }
    guard Self.contains(request.region, in: request.targetPresentBaseline.frame) else {
      return reject(.invalidRegion)
    }
    let poseDistance = request.targetPresentBaseline.controllerPosition.point.distance(
      to: request.postLine.controllerPosition.point
    )
    guard poseDistance <= request.controllerPositionToleranceMM else {
      return reject(.clearPoseMismatch(
        distanceMM: poseDistance,
        toleranceMM: request.controllerPositionToleranceMM
      ))
    }
    let alignment = Self.bestIntegerAlignment(
      request.targetPresentBaseline.frame,
      request.postLine.frame,
      excluding: request.region,
      searchRadius: request.alignmentSearchRadiusPixels
    )
    guard max(abs(alignment.shiftX), abs(alignment.shiftY))
      <= request.maximumAlignmentShiftPixels
    else {
      return reject(.excessiveAlignment(
        shiftX: alignment.shiftX,
        shiftY: alignment.shiftY,
        maximumPixels: request.maximumAlignmentShiftPixels
      ))
    }
    guard alignment.backgroundMeanAbsoluteDifference
      <= request.maximumBackgroundMeanAbsoluteDifference
    else {
      return reject(.excessiveBackgroundResidual(
        actual: alignment.backgroundMeanAbsoluteDifference,
        maximum: request.maximumBackgroundMeanAbsoluteDifference
      ))
    }

    let linePixels = Self.newGreenPixels(
      from: request.targetPresentBaseline.frame,
      to: request.postLine.frame,
      region: request.region,
      thresholds: request.thresholds,
      observationShiftX: alignment.shiftX,
      observationShiftY: alignment.shiftY
    )
    guard !linePixels.isEmpty else { return reject(.lineMissing) }
    let lineComponents = Self.components(linePixels)
    let eligibleLines = lineComponents.filter { $0.count >= request.minimumLinePixels }
    guard !eligibleLines.isEmpty else {
      return reject(.lineTooSmall(
        actualPixels: lineComponents.map(\.count).max() ?? 0,
        minimumPixels: request.minimumLinePixels
      ))
    }
    guard eligibleLines.count == 1 else {
      return reject(.lineAmbiguous(candidateCount: eligibleLines.count))
    }
    let line = eligibleLines[0]
    guard let fit = Self.fitLine(line),
      fit.minorToMajorVarianceRatio <= request.maximumLineMinorToMajorVarianceRatio
    else {
      let ratio = Self.fitLine(line)?.minorToMajorVarianceRatio ?? .infinity
      return reject(.lineNotLineLike(minorToMajorVarianceRatio: ratio))
    }

    var observedEndpoints = [fit.start, fit.end]
    var intended: Polyline<CameraPixelSpace>?
    var residual: IsolatedInkResidual?
    if let delta = request.projectedActualStrokeDelta,
      delta.dx.isFinite, delta.dy.isFinite, delta.magnitude > 0,
      let intendedEnd = try? request.lineStartPoint.translated(by: delta),
      let intendedLine = try? Polyline(points: [request.lineStartPoint, intendedEnd])
    {
      intended = intendedLine
      let direct = fit.start.distance(to: request.lineStartPoint) + fit.end.distance(to: intendedEnd)
      let reversed = fit.end.distance(to: request.lineStartPoint) + fit.start.distance(to: intendedEnd)
      if reversed < direct { observedEndpoints.reverse() }
      let endpointErrors = [
        observedEndpoints[0].distance(to: request.lineStartPoint),
        observedEndpoints[1].distance(to: intendedEnd),
      ]
      let crossTrackSquared = line.map {
        let point = try! Point2<CameraPixelSpace>(x: Double($0.x), y: Double($0.y))
        let distance = Self.infiniteLineDistance(
          point,
          start: request.lineStartPoint,
          end: intendedEnd
        )
        return distance * distance
      }
      residual = IsolatedInkResidual(
        rootMeanSquareEndpointPixels: sqrt(endpointErrors.reduce(0) { $0 + $1 * $1 } / 2),
        maximumEndpointPixels: endpointErrors.max() ?? 0,
        rootMeanSquareCrossTrackPixels: sqrt(
          crossTrackSquared.reduce(0, +) / Double(crossTrackSquared.count)
        )
      )
    } else if Self.pointOrder(observedEndpoints[1], before: observedEndpoints[0]) {
      observedEndpoints.reverse()
    }

    guard let centreline = try? Polyline(points: observedEndpoints),
      let displacement = try? observedEndpoints[0].vector(to: observedEndpoints[1])
    else { return reject(.lineNotLineLike(minorToMajorVarianceRatio: .infinity)) }
    var overlays: [CameraOverlayMeasurement] = [
      CameraOverlayMeasurement(
        frameID: request.postLine.frame.id,
        cameraConfigurationID: request.postLine.frame.cameraConfigurationID,
        geometry: .polyline(centreline),
        provenance: CameraMeasurementProvenance(
          kind: .observedInk,
          source: .measured,
          algorithmRevision: request.algorithmRevision
        )
      )
    ]
    if let intended {
      overlays.append(CameraOverlayMeasurement(
        frameID: request.postLine.frame.id,
        cameraConfigurationID: request.postLine.frame.cameraConfigurationID,
        geometry: .polyline(intended),
        provenance: CameraMeasurementProvenance(
          kind: .intendedPath,
          source: .planned,
          algorithmRevision: request.algorithmRevision
        )
      ))
      for pair in zip(intended.points, observedEndpoints) {
        if pair.0 != pair.1, let geometry = try? Polyline(points: [pair.0, pair.1]) {
          overlays.append(CameraOverlayMeasurement(
            frameID: request.postLine.frame.id,
            cameraConfigurationID: request.postLine.frame.cameraConfigurationID,
            geometry: .polyline(geometry),
            provenance: CameraMeasurementProvenance(
              kind: .residual,
              source: .diagnostic,
              algorithmRevision: request.algorithmRevision
            )
          ))
        }
      }
    }
    return .observed(IsolatedInkObservation(
      targetPresentBaseline: provenance.baseline,
      postLine: provenance.post,
      region: request.region,
      lineStartPoint: request.lineStartPoint,
      source: request.targetPresentBaseline.source,
      controllerSessionID: request.controllerSessionID,
      coordinateRevision: request.coordinateRevision,
      toolPaperRevision: request.toolPaperRevision,
      alignment: alignment,
      observedEndpoints: observedEndpoints,
      observedCentreline: centreline,
      observedPixelCount: line.count,
      displacementPixels: displacement,
      orientationRadians: atan2(displacement.dy, displacement.dx),
      intendedLine: intended,
      residual: residual,
      overlays: overlays,
      algorithmRevision: request.algorithmRevision
    ))
  }
}

private extension VisionWorker {
  struct InkPixel: Hashable {
    let x: Int
    let y: Int
  }

  struct InkLineFit {
    let start: Point2<CameraPixelSpace>
    let end: Point2<CameraPixelSpace>
    let minorToMajorVarianceRatio: Double
  }

  struct BackgroundResidual {
    let meanAbsoluteDifference: Double
    let pixelCount: Int
  }

  enum LocalIntegerAlignmentOutcome {
    case aligned(IntegerFrameAlignment)
    case insufficientSupport(actualPixels: Int)
    case indeterminate
    case cancelled
  }

  static func expanded(
    _ region: PixelRect,
    by margin: Int,
    clippedTo frame: StampedFrame
  ) -> PixelRect {
    let minX = max(0, region.x - margin)
    let minY = max(0, region.y - margin)
    let maxX = min(frame.width, region.x + region.width + margin)
    let maxY = min(frame.height, region.y + region.height + margin)
    return PixelRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
  }

  static func contains(_ region: PixelRect, in frame: StampedFrame) -> Bool {
    region.x >= 0 && region.y >= 0 && region.width > 0 && region.height > 0
      && region.x + region.width <= frame.width
      && region.y + region.height <= frame.height
  }

  static func newGreenPixels(
    from reference: StampedFrame,
    to observation: StampedFrame,
    region: PixelRect,
    thresholds: GreenPixelThresholds,
    observationShiftX: Int = 0,
    observationShiftY: Int = 0
  ) -> Set<InkPixel> {
    var result: Set<InkPixel> = []
    for y in region.y..<(region.y + region.height) {
      for x in region.x..<(region.x + region.width) {
        let observedX = x + observationShiftX
        let observedY = y + observationShiftY
        guard observedX >= 0, observedX < observation.width,
          observedY >= 0, observedY < observation.height
        else { continue }
        if isGreen(observation, x: observedX, y: observedY, thresholds: thresholds)
          && !isGreen(reference, x: x, y: y, thresholds: thresholds)
        {
          result.insert(InkPixel(x: x, y: y))
        }
      }
    }
    return result
  }

  static func cancellableNewGreenPixels(
    from reference: StampedFrame,
    to observation: StampedFrame,
    searchCircle: VisibilityTargetSearchCircle,
    thresholds: GreenPixelThresholds,
    observationShiftX: Int = 0,
    observationShiftY: Int = 0
  ) -> Set<InkPixel>? {
    let region = searchCircle.boundingROI
    var result: Set<InkPixel> = []
    for y in region.y..<(region.y + region.height) {
      if (y - region.y).isMultiple(of: 16), Task.isCancelled { return nil }
      for x in region.x..<(region.x + region.width) {
        guard searchCircle.contains(x: x, y: y) else { continue }
        let observedX = x + observationShiftX
        let observedY = y + observationShiftY
        guard observedX >= 0, observedX < observation.width,
          observedY >= 0, observedY < observation.height
        else { continue }
        if isGreen(observation, x: observedX, y: observedY, thresholds: thresholds)
          && !isGreen(reference, x: x, y: y, thresholds: thresholds)
        {
          result.insert(InkPixel(x: x, y: y))
        }
      }
    }
    return Task.isCancelled ? nil : result
  }

  static func bestLocalIntegerAlignment(
    _ baseline: StampedFrame,
    _ observation: StampedFrame,
    supportRegion: PixelRect,
    excluding exclusionRegion: PixelRect,
    searchRadius: Int,
    minimumSupportPixels: Int
  ) -> LocalIntegerAlignmentOutcome {
    var candidates: [(shiftX: Int, shiftY: Int, residual: Double)] = []
    var minimumCandidateSupport = Int.max
    var evaluatedPixelCount = 0
    for shiftY in (-searchRadius)...searchRadius {
      for shiftX in (-searchRadius)...searchRadius {
        guard !Task.isCancelled else { return .cancelled }
        guard let residual = cancellableBackgroundMeanAbsoluteDifference(
          baseline,
          observation,
          supportRegion: supportRegion,
          excluding: exclusionRegion,
          observationShiftX: shiftX,
          observationShiftY: shiftY
        ) else { return .cancelled }
        minimumCandidateSupport = min(minimumCandidateSupport, residual.pixelCount)
        evaluatedPixelCount += residual.pixelCount
        candidates.append((
          shiftX: shiftX,
          shiftY: shiftY,
          residual: residual.meanAbsoluteDifference
        ))
      }
    }
    guard minimumCandidateSupport >= minimumSupportPixels else {
      return .insufficientSupport(actualPixels: max(0, minimumCandidateSupport))
    }
    candidates.sort { lhs, rhs in
      (
        lhs.residual,
        max(abs(lhs.shiftX), abs(lhs.shiftY)),
        abs(lhs.shiftX) + abs(lhs.shiftY),
        lhs.shiftY,
        lhs.shiftX
      ) < (
        rhs.residual,
        max(abs(rhs.shiftX), abs(rhs.shiftY)),
        abs(rhs.shiftX) + abs(rhs.shiftY),
        rhs.shiftY,
        rhs.shiftX
      )
    }
    guard let selected = candidates.first else {
      return .insufficientSupport(actualPixels: 0)
    }
    if selected.shiftX != 0 || selected.shiftY != 0,
      candidates.dropFirst().first.map({ abs($0.residual - selected.residual) <= 1e-9 }) == true
    {
      return .indeterminate
    }
    return .aligned(IntegerFrameAlignment(
      shiftX: selected.shiftX,
      shiftY: selected.shiftY,
      backgroundMeanAbsoluteDifference: selected.residual,
      estimatorRevision: "bounded-integer-local-background-mad-v2",
      supportRegion: supportRegion,
      exclusionRegion: exclusionRegion,
      evaluatedPixelCount: evaluatedPixelCount
    ))
  }

  static func cancellableBackgroundMeanAbsoluteDifference(
    _ baseline: StampedFrame,
    _ observation: StampedFrame,
    supportRegion: PixelRect,
    excluding exclusionRegion: PixelRect,
    observationShiftX: Int,
    observationShiftY: Int
  ) -> BackgroundResidual? {
    var absoluteDifference = 0.0
    var pixelCount = 0
    for y in supportRegion.y..<(supportRegion.y + supportRegion.height) {
      if (y - supportRegion.y).isMultiple(of: 16), Task.isCancelled { return nil }
      for x in supportRegion.x..<(supportRegion.x + supportRegion.width) {
        let excluded = x >= exclusionRegion.x && x < exclusionRegion.x + exclusionRegion.width
          && y >= exclusionRegion.y && y < exclusionRegion.y + exclusionRegion.height
        guard !excluded else { continue }
        let observedX = x + observationShiftX
        let observedY = y + observationShiftY
        guard observedX >= 0, observedX < observation.width,
          observedY >= 0, observedY < observation.height
        else { continue }
        let baseOffset = y * baseline.rowBytes + x * baseline.pixelFormat.bytesPerPixel
        let observedOffset = observedY * observation.rowBytes
          + observedX * observation.pixelFormat.bytesPerPixel
        for component in 0..<baseline.pixelFormat.bytesPerPixel {
          absoluteDifference += abs(
            Double(baseline.bytes[baseOffset + component])
              - Double(observation.bytes[observedOffset + component])
          )
        }
        pixelCount += 1
      }
    }
    guard !Task.isCancelled else { return nil }
    let byteCount = pixelCount * baseline.pixelFormat.bytesPerPixel
    return BackgroundResidual(
      meanAbsoluteDifference: byteCount == 0 ? 0 : absoluteDifference / Double(byteCount),
      pixelCount: pixelCount
    )
  }

  static func bestIntegerAlignment(
    _ baseline: StampedFrame,
    _ observation: StampedFrame,
    excluding region: PixelRect,
    searchRadius: Int
  ) -> IntegerFrameAlignment {
    var best: (shiftX: Int, shiftY: Int, residual: Double)?
    var evaluatedPixelCount = 0
    for shiftY in (-searchRadius)...searchRadius {
      for shiftX in (-searchRadius)...searchRadius {
        let residual = backgroundMeanAbsoluteDifference(
          baseline,
          observation,
          excluding: region,
          observationShiftX: shiftX,
          observationShiftY: shiftY
        )
        evaluatedPixelCount += residual.pixelCount
        let candidate = (
          shiftX: shiftX,
          shiftY: shiftY,
          residual: residual.meanAbsoluteDifference
        )
        if let current = best {
          let candidateRank = (
            candidate.residual,
            max(abs(candidate.shiftX), abs(candidate.shiftY)),
            abs(candidate.shiftX) + abs(candidate.shiftY),
            candidate.shiftY,
            candidate.shiftX
          )
          let currentRank = (
            current.residual,
            max(abs(current.shiftX), abs(current.shiftY)),
            abs(current.shiftX) + abs(current.shiftY),
            current.shiftY,
            current.shiftX
          )
          if candidateRank < currentRank { best = candidate }
        } else {
          best = candidate
        }
      }
    }
    let selected = best ?? (0, 0, 0)
    return IntegerFrameAlignment(
      shiftX: selected.shiftX,
      shiftY: selected.shiftY,
      backgroundMeanAbsoluteDifference: selected.residual,
      estimatorRevision: "bounded-integer-background-mad-v1",
      supportRegion: PixelRect(x: 0, y: 0, width: baseline.width, height: baseline.height),
      exclusionRegion: region,
      evaluatedPixelCount: evaluatedPixelCount
    )
  }

  static func backgroundMeanAbsoluteDifference(
    _ baseline: StampedFrame,
    _ observation: StampedFrame,
    excluding region: PixelRect,
    observationShiftX: Int,
    observationShiftY: Int
  ) -> BackgroundResidual {
    var absoluteDifference = 0.0
    var pixelCount = 0
    for y in 0..<baseline.height {
      for x in 0..<baseline.width {
        let inRegion = x >= region.x && x < region.x + region.width
          && y >= region.y && y < region.y + region.height
        guard !inRegion else { continue }
        let observedX = x + observationShiftX
        let observedY = y + observationShiftY
        guard observedX >= 0, observedX < observation.width,
          observedY >= 0, observedY < observation.height
        else { continue }
        let baseOffset = y * baseline.rowBytes + x * baseline.pixelFormat.bytesPerPixel
        let observedOffset = observedY * observation.rowBytes
          + observedX * observation.pixelFormat.bytesPerPixel
        for component in 0..<baseline.pixelFormat.bytesPerPixel {
          absoluteDifference += abs(
            Double(baseline.bytes[baseOffset + component])
              - Double(observation.bytes[observedOffset + component])
          )
        }
        pixelCount += 1
      }
    }
    let byteCount = pixelCount * baseline.pixelFormat.bytesPerPixel
    return BackgroundResidual(
      meanAbsoluteDifference: byteCount == 0 ? 0 : absoluteDifference / Double(byteCount),
      pixelCount: pixelCount
    )
  }

  static func isGreen(
    _ frame: StampedFrame,
    x: Int,
    y: Int,
    thresholds: GreenPixelThresholds
  ) -> Bool {
    let offset = y * frame.rowBytes + x * frame.pixelFormat.bytesPerPixel
    let red: UInt8
    let green: UInt8
    let blue: UInt8
    switch frame.pixelFormat {
    case .gray8:
      red = frame.bytes[offset]
      green = frame.bytes[offset]
      blue = frame.bytes[offset]
    case .rgba8:
      red = frame.bytes[offset]
      green = frame.bytes[offset + 1]
      blue = frame.bytes[offset + 2]
    case .bgra8:
      blue = frame.bytes[offset]
      green = frame.bytes[offset + 1]
      red = frame.bytes[offset + 2]
    }
    return green >= thresholds.minimumGreen
      && Int(green) - Int(max(red, blue)) >= Int(thresholds.minimumGreenExcess)
  }

  static func components(_ pixels: Set<InkPixel>) -> [[InkPixel]] {
    var remaining = pixels
    var result: [[InkPixel]] = []
    while let seed = remaining.first {
      remaining.remove(seed)
      var queue = [seed]
      var component: [InkPixel] = []
      while let current = queue.popLast() {
        component.append(current)
        for y in (current.y - 1)...(current.y + 1) {
          for x in (current.x - 1)...(current.x + 1) where x != current.x || y != current.y {
            let neighbor = InkPixel(x: x, y: y)
            if remaining.remove(neighbor) != nil { queue.append(neighbor) }
          }
        }
      }
      result.append(component)
    }
    return result.sorted {
      if $0.count != $1.count { return $0.count > $1.count }
      let l = centroid($0)
      let r = centroid($1)
      return pointOrder(l, before: r)
    }
  }

  static func cancellableComponents(_ pixels: Set<InkPixel>) -> [[InkPixel]]? {
    var remaining = pixels
    var result: [[InkPixel]] = []
    while let seed = remaining.first {
      guard !Task.isCancelled else { return nil }
      remaining.remove(seed)
      var queue = [seed]
      var component: [InkPixel] = []
      while let current = queue.popLast() {
        guard !Task.isCancelled else { return nil }
        component.append(current)
        for y in (current.y - 1)...(current.y + 1) {
          for x in (current.x - 1)...(current.x + 1) where x != current.x || y != current.y {
            let neighbor = InkPixel(x: x, y: y)
            if remaining.remove(neighbor) != nil { queue.append(neighbor) }
          }
        }
      }
      result.append(component)
    }
    return result.sorted {
      if $0.count != $1.count { return $0.count > $1.count }
      let l = centroid($0)
      let r = centroid($1)
      return pointOrder(l, before: r)
    }
  }

  static func centroid(_ pixels: [InkPixel]) -> Point2<CameraPixelSpace> {
    let x = pixels.reduce(0.0) { $0 + Double($1.x) } / Double(pixels.count)
    let y = pixels.reduce(0.0) { $0 + Double($1.y) } / Double(pixels.count)
    return try! Point2(x: x, y: y)
  }

  static func fitLine(_ pixels: [InkPixel]) -> InkLineFit? {
    guard pixels.count >= 2 else { return nil }
    let centre = centroid(pixels)
    let xx = pixels.reduce(0.0) { $0 + pow(Double($1.x) - centre.x, 2) } / Double(pixels.count)
    let yy = pixels.reduce(0.0) { $0 + pow(Double($1.y) - centre.y, 2) } / Double(pixels.count)
    let xy = pixels.reduce(0.0) {
      $0 + (Double($1.x) - centre.x) * (Double($1.y) - centre.y)
    } / Double(pixels.count)
    let trace = xx + yy
    let discriminant = sqrt(max(0, (xx - yy) * (xx - yy) + 4 * xy * xy))
    let major = (trace + discriminant) / 2
    let minor = max(0, (trace - discriminant) / 2)
    guard major > 0 else { return nil }
    let angle = 0.5 * atan2(2 * xy, xx - yy)
    let axisX = cos(angle)
    let axisY = sin(angle)
    let projections = pixels.map {
      (Double($0.x) - centre.x) * axisX + (Double($0.y) - centre.y) * axisY
    }
    guard let minimum = projections.min(), let maximum = projections.max(), maximum - minimum >= 1 else {
      return nil
    }
    return InkLineFit(
      start: try! Point2(x: centre.x + minimum * axisX, y: centre.y + minimum * axisY),
      end: try! Point2(x: centre.x + maximum * axisX, y: centre.y + maximum * axisY),
      minorToMajorVarianceRatio: minor / major
    )
  }

  static func infiniteLineDistance(
    _ point: Point2<CameraPixelSpace>,
    start: Point2<CameraPixelSpace>,
    end: Point2<CameraPixelSpace>
  ) -> Double {
    let dx = end.x - start.x
    let dy = end.y - start.y
    return abs(dy * point.x - dx * point.y + end.x * start.y - end.y * start.x)
      / hypot(dx, dy)
  }

  static func pointOrder(
    _ lhs: Point2<CameraPixelSpace>,
    before rhs: Point2<CameraPixelSpace>
  ) -> Bool {
    lhs.x == rhs.x ? lhs.y < rhs.y : lhs.x < rhs.x
  }
}
