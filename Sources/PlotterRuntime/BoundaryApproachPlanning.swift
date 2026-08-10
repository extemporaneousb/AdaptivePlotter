import Foundation
import PlotterModel

/// One exact-frame observation used only to advise the length of the next
/// finite Boundary segment. It is not accepted Boundary evidence.
public struct BoundaryApproachObservation: Hashable, Sendable {
  public let source: FrameSourceIdentity
  public let cameraConfigurationID: CameraConfigurationID
  public let captureNanoseconds: UInt64
  public let machinePosition: MachinePosition
  public let toolContact: Point2<CameraPixelSpace>
  public let toolConfidence: Double
  public let drawingFrame: Polyline<CameraPixelSpace>
  public let drawingFrameConfidence: Double

  public init(
    source: FrameSourceIdentity,
    cameraConfigurationID: CameraConfigurationID,
    captureNanoseconds: UInt64,
    machinePosition: MachinePosition,
    toolContact: Point2<CameraPixelSpace>,
    toolConfidence: Double,
    drawingFrame: Polyline<CameraPixelSpace>,
    drawingFrameConfidence: Double
  ) {
    self.source = source
    self.cameraConfigurationID = cameraConfigurationID
    self.captureNanoseconds = captureNanoseconds
    self.machinePosition = machinePosition
    self.toolContact = toolContact
    self.toolConfidence = toolConfidence
    self.drawingFrame = drawingFrame
    self.drawingFrameConfidence = drawingFrameConfidence
  }
}

public enum BoundaryApproachAdviceBasis: String, Hashable, Sendable {
  case projectedEnvelope
  case missingObservationFallback
  case establishingBaselineFallback
  case incompatibleObservationFallback
  case insufficientMotionFallback
  case noForwardIntersectionFallback
}

public struct BoundaryApproachAdvice: Hashable, Sendable {
  public let nextSegmentLengthMM: Double
  public let basis: BoundaryApproachAdviceBasis
  public let estimatedRemainingMM: Double?
  public let observedPixelsPerMM: Double?

  public init(
    nextSegmentLengthMM: Double,
    basis: BoundaryApproachAdviceBasis,
    estimatedRemainingMM: Double? = nil,
    observedPixelsPerMM: Double? = nil
  ) {
    self.nextSegmentLengthMM = nextSegmentLengthMM
    self.basis = basis
    self.estimatedRemainingMM = estimatedRemainingMM
    self.observedPixelsPerMM = observedPixelsPerMM
  }
}

/// Stateful so a valid approach can accelerate once, then only hold or
/// decrease segment length as the inferred envelope gets nearer.
public actor BoundaryApproachPlanner {
  public static let segmentTiersMM: [Double] = [40, 20, 10, 5, 2]

  private var previousObservation: BoundaryApproachObservation?
  private var selectedLengthMM = 10.0
  private var hasAcceptedProjection = false

  public init(seed: BoundaryApproachObservation?) {
    previousObservation = seed
  }

  public func advise(after current: BoundaryApproachObservation?) -> BoundaryApproachAdvice {
    guard let current else {
      return fallback(.missingObservationFallback)
    }
    guard Self.isProjectionEligible(current) else {
      return fallback(.incompatibleObservationFallback)
    }
    guard let previous = previousObservation else {
      previousObservation = current
      return fallback(.establishingBaselineFallback)
    }
    guard Self.isProjectionEligible(previous),
      previous.source == current.source,
      previous.cameraConfigurationID == current.cameraConfigurationID
    else {
      previousObservation = current
      return fallback(.establishingBaselineFallback)
    }
    guard current.captureNanoseconds > previous.captureNanoseconds else {
      return fallback(.incompatibleObservationFallback)
    }

    let machineTravelMM = previous.machinePosition.point.distance(to: current.machinePosition.point)
    let pixelTravel = previous.toolContact.distance(to: current.toolContact)
    guard machineTravelMM >= 0.5, pixelTravel >= 2 else {
      return fallback(.insufficientMotionFallback)
    }

    let directionX = current.toolContact.x - previous.toolContact.x
    let directionY = current.toolContact.y - previous.toolContact.y
    guard let remainingPixels = Self.forwardIntersectionDistance(
      origin: current.toolContact,
      directionX: directionX,
      directionY: directionY,
      envelope: current.drawingFrame
    ) else {
      return fallback(.noForwardIntersectionFallback)
    }

    let pixelsPerMM = pixelTravel / machineTravelMM
    let remainingMM = remainingPixels / pixelsPerMM
    // Retain 4 mm of estimated clearance and consume no more than half the
    // remainder so every accelerated renewal still gets a fresh observation.
    let usableMM = max(0, (remainingMM - 4) / 2)
    let tier = Self.segmentTiersMM.first(where: { $0 <= usableMM }) ?? 2
    let nextLength = hasAcceptedProjection ? min(selectedLengthMM, tier) : tier
    selectedLengthMM = nextLength
    hasAcceptedProjection = true
    previousObservation = current
    return BoundaryApproachAdvice(
      nextSegmentLengthMM: nextLength,
      basis: .projectedEnvelope,
      estimatedRemainingMM: remainingMM,
      observedPixelsPerMM: pixelsPerMM
    )
  }

  private func fallback(_ basis: BoundaryApproachAdviceBasis) -> BoundaryApproachAdvice {
    selectedLengthMM = min(selectedLengthMM, 10)
    return BoundaryApproachAdvice(nextSegmentLengthMM: selectedLengthMM, basis: basis)
  }

  private static func isProjectionEligible(_ observation: BoundaryApproachObservation) -> Bool {
    observation.toolConfidence >= 0.5 && observation.drawingFrameConfidence >= 0.5
  }

  private static func forwardIntersectionDistance(
    origin: Point2<CameraPixelSpace>,
    directionX: Double,
    directionY: Double,
    envelope: Polyline<CameraPixelSpace>
  ) -> Double? {
    let directionMagnitude = hypot(directionX, directionY)
    guard directionMagnitude > 0 else { return nil }
    var points = envelope.points
    if points.first != points.last, let first = points.first { points.append(first) }
    var nearestRayScale: Double?
    for (start, end) in zip(points, points.dropFirst()) {
      let segmentX = end.x - start.x
      let segmentY = end.y - start.y
      let denominator = cross(directionX, directionY, segmentX, segmentY)
      guard abs(denominator) > 1e-9 else { continue }
      let offsetX = start.x - origin.x
      let offsetY = start.y - origin.y
      let rayScale = cross(offsetX, offsetY, segmentX, segmentY) / denominator
      let segmentScale = cross(offsetX, offsetY, directionX, directionY) / denominator
      guard rayScale > 1e-9, segmentScale >= 0, segmentScale <= 1 else { continue }
      nearestRayScale = min(nearestRayScale ?? rayScale, rayScale)
    }
    return nearestRayScale.map { $0 * directionMagnitude }
  }

  private static func cross(_ ax: Double, _ ay: Double, _ bx: Double, _ by: Double) -> Double {
    ax * by - ay * bx
  }
}

public struct BoundaryMotionSegmentProgress: Hashable, Sendable {
  public let ownerID: BoundaryMotionOwnerID
  public let direction: BoundaryDirection
  public let completedSegmentCount: Int
  public let completedSegment: RelativeJogRequest
  public let startPosition: MachinePosition
  public let finalPosition: MachinePosition

  public init(
    ownerID: BoundaryMotionOwnerID,
    direction: BoundaryDirection,
    completedSegmentCount: Int,
    completedSegment: RelativeJogRequest,
    startPosition: MachinePosition,
    finalPosition: MachinePosition
  ) {
    self.ownerID = ownerID
    self.direction = direction
    self.completedSegmentCount = completedSegmentCount
    self.completedSegment = completedSegment
    self.startPosition = startPosition
    self.finalPosition = finalPosition
  }
}

/// Async injection seam. It returns only a length, so advisory code cannot
/// alter the admitted direction or controller-derived feed.
public struct BoundaryMotionRenewalPlanner: Sendable {
  private let resolve: @Sendable (BoundaryMotionSegmentProgress) async -> Double?

  public init(
    _ resolve: @escaping @Sendable (BoundaryMotionSegmentProgress) async -> Double?
  ) {
    self.resolve = resolve
  }

  public func nextSegmentLength(
    after progress: BoundaryMotionSegmentProgress
  ) async -> Double? {
    await resolve(progress)
  }
}
