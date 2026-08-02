import Foundation

public enum PenServoState: UInt8, Codable, Sendable, CanonicalEncodable {
  case commandedUp = 0
  case operatorObservedUp = 1
  case unknown = 2

  public func encodeCanonical(to encoder: inout CanonicalEncoder) throws {
    encoder.appendUInt8(rawValue)
  }
}

public struct ObservationRegion: Hashable, Codable, Sendable, CanonicalEncodable {
  public let id: ObservationRegionID
  public let fieldBounds: AxisAlignedBounds<FieldSpace>

  public init(id: ObservationRegionID, fieldBounds: AxisAlignedBounds<FieldSpace>) {
    self.id = id
    self.fieldBounds = fieldBounds
  }

  public func encodeCanonical(to encoder: inout CanonicalEncoder) throws {
    try id.encodeCanonical(to: &encoder)
    try fieldBounds.encodeCanonical(to: &encoder)
  }
}

public struct ToolOcclusionEnvelope: Hashable, Codable, Sendable, CanonicalEncodable {
  public let id: ClearanceEnvelopeID
  public let cameraConfigurationID: CameraConfigurationID
  public let toolConfigurationID: ToolConfigurationID
  public let penServoState: PenServoState
  public let polygon: Polygon2<CameraPixelSpace>
  public let poseUncertaintyPixels: Double
  public let fixedMarginPixels: Double

  public init(
    id: ClearanceEnvelopeID,
    cameraConfigurationID: CameraConfigurationID,
    toolConfigurationID: ToolConfigurationID,
    penServoState: PenServoState,
    polygon: Polygon2<CameraPixelSpace>,
    poseUncertaintyPixels: Double,
    fixedMarginPixels: Double
  ) throws {
    guard poseUncertaintyPixels.isFinite, poseUncertaintyPixels >= 0,
      fixedMarginPixels.isFinite, fixedMarginPixels >= 0
    else {
      throw PlotterModelError.invalidValue("clearance margins must be finite and nonnegative")
    }
    self.id = id
    self.cameraConfigurationID = cameraConfigurationID
    self.toolConfigurationID = toolConfigurationID
    self.penServoState = penServoState
    self.polygon = polygon
    self.poseUncertaintyPixels = poseUncertaintyPixels
    self.fixedMarginPixels = fixedMarginPixels
  }

  public func conservativeInflatedBounds() throws -> AxisAlignedBounds<CameraPixelSpace> {
    try polygon.bounds.expanded(by: poseUncertaintyPixels + fixedMarginPixels)
  }

  public func encodeCanonical(to encoder: inout CanonicalEncoder) throws {
    try id.encodeCanonical(to: &encoder)
    try cameraConfigurationID.encodeCanonical(to: &encoder)
    try toolConfigurationID.encodeCanonical(to: &encoder)
    try penServoState.encodeCanonical(to: &encoder)
    try polygon.encodeCanonical(to: &encoder)
    try encoder.appendDouble(poseUncertaintyPixels)
    try encoder.appendDouble(fixedMarginPixels)
  }

  private enum CodingKeys: String, CodingKey {
    case id, cameraConfigurationID, toolConfigurationID, penServoState, polygon
    case poseUncertaintyPixels, fixedMarginPixels
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    try self.init(
      id: container.decode(ClearanceEnvelopeID.self, forKey: .id),
      cameraConfigurationID: container.decode(
        CameraConfigurationID.self,
        forKey: .cameraConfigurationID
      ),
      toolConfigurationID: container.decode(
        ToolConfigurationID.self,
        forKey: .toolConfigurationID
      ),
      penServoState: container.decode(PenServoState.self, forKey: .penServoState),
      polygon: container.decode(Polygon2<CameraPixelSpace>.self, forKey: .polygon),
      poseUncertaintyPixels: container.decode(Double.self, forKey: .poseUncertaintyPixels),
      fixedMarginPixels: container.decode(Double.self, forKey: .fixedMarginPixels)
    )
  }
}

public struct ClearancePose: Hashable, Codable, Sendable, CanonicalEncodable {
  public let id: ClearancePoseID
  public let machinePosition: Point2<MachineSpace>
  public let envelope: ToolOcclusionEnvelope

  public init(
    id: ClearancePoseID,
    machinePosition: Point2<MachineSpace>,
    envelope: ToolOcclusionEnvelope
  ) {
    self.id = id
    self.machinePosition = machinePosition
    self.envelope = envelope
  }

  public func encodeCanonical(to encoder: inout CanonicalEncoder) throws {
    try id.encodeCanonical(to: &encoder)
    try machinePosition.encodeCanonical(to: &encoder)
    try envelope.encodeCanonical(to: &encoder)
  }
}

public struct ClearancePath: Hashable, Codable, Sendable, CanonicalEncodable {
  public let id: ClearancePathID
  public let path: Polyline<MachineSpace>
  public let destinationPoseID: ClearancePoseID
  public let destinationMachinePosition: Point2<MachineSpace>
  public let maximumFeed: Double
  public let maximumDistance: Double

  public init(
    id: ClearancePathID,
    path: Polyline<MachineSpace>,
    destination: ClearancePose,
    maximumFeed: Double,
    maximumDistance: Double
  ) throws {
    guard maximumFeed.isFinite, maximumFeed > 0,
      maximumDistance.isFinite, maximumDistance > 0,
      path.length <= maximumDistance,
      path.end.distance(to: destination.machinePosition) <= 1e-9
    else {
      throw PlotterModelError.invalidValue("clearance path exceeds its bound or misses its pose")
    }
    self.id = id
    self.path = path
    destinationPoseID = destination.id
    destinationMachinePosition = destination.machinePosition
    self.maximumFeed = maximumFeed
    self.maximumDistance = maximumDistance
  }

  public func encodeCanonical(to encoder: inout CanonicalEncoder) throws {
    try id.encodeCanonical(to: &encoder)
    try path.encodeCanonical(to: &encoder)
    try destinationPoseID.encodeCanonical(to: &encoder)
    try destinationMachinePosition.encodeCanonical(to: &encoder)
    try encoder.appendDouble(maximumFeed)
    try encoder.appendDouble(maximumDistance)
  }

  private enum CodingKeys: String, CodingKey {
    case id, path, destinationPoseID, destinationMachinePosition, maximumFeed, maximumDistance
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let path = try container.decode(Polyline<MachineSpace>.self, forKey: .path)
    let destinationMachinePosition = try container.decode(
      Point2<MachineSpace>.self,
      forKey: .destinationMachinePosition
    )
    let maximumFeed = try container.decode(Double.self, forKey: .maximumFeed)
    let maximumDistance = try container.decode(Double.self, forKey: .maximumDistance)
    guard maximumFeed.isFinite, maximumFeed > 0,
      maximumDistance.isFinite, maximumDistance > 0,
      path.length <= maximumDistance,
      path.end.distance(to: destinationMachinePosition) <= 1e-9
    else {
      throw PlotterModelError.invalidValue("clearance path exceeds its bound or misses its pose")
    }
    id = try container.decode(ClearancePathID.self, forKey: .id)
    self.path = path
    destinationPoseID = try container.decode(ClearancePoseID.self, forKey: .destinationPoseID)
    self.destinationMachinePosition = destinationMachinePosition
    self.maximumFeed = maximumFeed
    self.maximumDistance = maximumDistance
  }
}

public enum ClearanceAssessment: Hashable, Codable, Sendable {
  case clear(minimumAxisSeparationPixels: Double)
  case blocked

  public var isClear: Bool {
    if case .clear = self { return true }
    return false
  }
}

public enum ClearanceValidator {
  /// Conservative first-slice policy: compare the inflated armature AABB with
  /// the AABB of the field ROI projected into camera pixels. False negatives
  /// are acceptable; a false clear is not.
  public static func assess(
    observationRegion: ObservationRegion,
    registration: FieldRegistration,
    clearancePose: ClearancePose
  ) throws -> ClearanceAssessment {
    let projectedCorners = try observationRegion.fieldBounds.corners.map {
      try registration.cameraPoint(from: $0)
    }
    guard let firstCorner = projectedCorners.first else {
      throw GeometryError.insufficientPoints(required: 1, actual: 0)
    }
    var minX = firstCorner.x
    var minY = firstCorner.y
    var maxX = firstCorner.x
    var maxY = firstCorner.y
    for corner in projectedCorners.dropFirst() {
      minX = min(minX, corner.x)
      minY = min(minY, corner.y)
      maxX = max(maxX, corner.x)
      maxY = max(maxY, corner.y)
    }
    let projectedBounds = try AxisAlignedBounds<CameraPixelSpace>(
      minX: minX, minY: minY, maxX: maxX, maxY: maxY
    )
    let envelopeBounds = try clearancePose.envelope.conservativeInflatedBounds()
    guard !envelopeBounds.intersects(projectedBounds) else { return .blocked }

    let horizontalGap = max(
      projectedBounds.minX - envelopeBounds.maxX,
      envelopeBounds.minX - projectedBounds.maxX,
      0
    )
    let verticalGap = max(
      projectedBounds.minY - envelopeBounds.maxY,
      envelopeBounds.minY - projectedBounds.maxY,
      0
    )
    return .clear(minimumAxisSeparationPixels: max(horizontalGap, verticalGap))
  }
}
