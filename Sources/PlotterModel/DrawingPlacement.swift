import Foundation

/// Places one immutable field-space program in machine space. Ordinary artwork
/// can preserve camera proportions using the accepted command-to-image response.
/// The explicit field anchor makes resize and rotation behavior
/// stable instead of depending on a view's transient gesture origin.
public struct DrawingPlacement: Hashable, Codable, Sendable, CanonicalEncodable {
  public let fieldAnchor: Point2<FieldSpace>
  public let machineAnchor: Point2<MachineSpace>
  public let uniformScale: Double
  public let rotationRadians: Double
  public let cameraGeometry: DrawingCameraGeometry?

  public init(
    fieldAnchor: Point2<FieldSpace>,
    machineAnchor: Point2<MachineSpace>,
    uniformScale: Double,
    rotationRadians: Double = 0,
    cameraGeometry: DrawingCameraGeometry? = nil
  ) throws {
    guard uniformScale.isFinite, uniformScale > 0 else {
      throw PlotterModelError.invalidValue("uniformScale must be positive and finite")
    }
    guard rotationRadians.isFinite else {
      throw PlotterModelError.invalidValue("rotationRadians must be finite")
    }

    self.fieldAnchor = fieldAnchor
    self.machineAnchor = machineAnchor
    self.uniformScale = uniformScale
    self.cameraGeometry = cameraGeometry
    // Equivalent full rotations have one durable identity.
    let fullTurn = 2 * Double.pi
    var normalizedRotation = rotationRadians.truncatingRemainder(dividingBy: fullTurn)
    if normalizedRotation >= .pi { normalizedRotation -= fullTurn }
    if normalizedRotation < -.pi { normalizedRotation += fullTurn }
    self.rotationRadians = normalizedRotation == 0 ? 0 : normalizedRotation
  }

  public var fieldToMachineTransform: AffineTransform2<FieldSpace, MachineSpace> {
    get throws {
      let cosine = cos(rotationRadians)
      let sine = sin(rotationRadians)
      let k = cameraGeometry?.commandCorrection
      let a = k?.m11 ?? 1, b = k?.m12 ?? 0, c = k?.m21 ?? 0, d = k?.m22 ?? 1
      let m11 = uniformScale * (a * cosine + b * sine)
      let m12 = uniformScale * (-a * sine + b * cosine)
      let m21 = uniformScale * (c * cosine + d * sine)
      let m22 = uniformScale * (-c * sine + d * cosine)
      return try AffineTransform2(
        m11: m11,
        m12: m12,
        m21: m21,
        m22: m22,
        tx: machineAnchor.x - m11 * fieldAnchor.x - m12 * fieldAnchor.y,
        ty: machineAnchor.y - m21 * fieldAnchor.x - m22 * fieldAnchor.y
      )
    }
  }

  /// Conservative scale for isotropic material spacing policies in controller units.
  public var minimumScale: Double { uniformScale * (cameraGeometry?.minimumAxisScale ?? 1) }
  public var maximumScale: Double { uniformScale * (cameraGeometry?.maximumAxisScale ?? 1) }

  /// Lengths of the placed authored edges, not an axis-aligned bounding box or
  /// independent evidence of physical size.
  public func controllerEdgeLengths(for extent: Size2<FieldSpace>) throws -> Size2<MachineSpace> {
    guard cameraGeometry != nil else {
      return try Size2(width: extent.width * uniformScale, height: extent.height * uniformScale)
    }
    let a = try fieldToMachineTransform
    return try Size2(width: extent.width * hypot(a.m11, a.m21), height: extent.height * hypot(a.m12, a.m22))
  }

  public func applying(to point: Point2<FieldSpace>) throws -> Point2<MachineSpace> {
    try fieldToMachineTransform.applying(to: point)
  }

  public func applying(to polyline: Polyline<FieldSpace>) throws -> Polyline<MachineSpace> {
    try fieldToMachineTransform.applying(to: polyline)
  }

  public func encodeCanonical(to encoder: inout CanonicalEncoder) throws {
    try encoder.appendString("DrawingPlacement")
    try fieldAnchor.encodeCanonical(to: &encoder)
    try machineAnchor.encodeCanonical(to: &encoder)
    try encoder.appendDouble(uniformScale)
    try encoder.appendDouble(rotationRadians)
    // Preserve the exact pre-camera canonical representation of historical plans.
    if let cameraGeometry { try cameraGeometry.encodeCanonical(to: &encoder) }
  }

  private enum CodingKeys: String, CodingKey {
    case fieldAnchor, machineAnchor, uniformScale, rotationRadians, cameraGeometry
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    try self.init(
      fieldAnchor: container.decode(Point2<FieldSpace>.self, forKey: .fieldAnchor),
      machineAnchor: container.decode(Point2<MachineSpace>.self, forKey: .machineAnchor),
      uniformScale: container.decode(Double.self, forKey: .uniformScale),
      rotationRadians: container.decode(Double.self, forKey: .rotationRadians),
      cameraGeometry: container.decodeIfPresent(DrawingCameraGeometry.self, forKey: .cameraGeometry)
    )
  }
}
