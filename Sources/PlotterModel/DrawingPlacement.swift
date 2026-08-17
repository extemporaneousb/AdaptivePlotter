import Foundation

/// A similarity transform that places one immutable field-space program in
/// machine space. The explicit field anchor makes resize and rotation behavior
/// stable instead of depending on a view's transient gesture origin.
public struct DrawingPlacement: Hashable, Codable, Sendable, CanonicalEncodable {
  public let fieldAnchor: Point2<FieldSpace>
  public let machineAnchor: Point2<MachineSpace>
  public let uniformScale: Double
  public let rotationRadians: Double

  public init(
    fieldAnchor: Point2<FieldSpace>,
    machineAnchor: Point2<MachineSpace>,
    uniformScale: Double,
    rotationRadians: Double = 0
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
      let m11 = uniformScale * cosine
      let m12 = -uniformScale * sine
      let m21 = uniformScale * sine
      let m22 = uniformScale * cosine
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
  }

  private enum CodingKeys: String, CodingKey {
    case fieldAnchor, machineAnchor, uniformScale, rotationRadians
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    try self.init(
      fieldAnchor: container.decode(Point2<FieldSpace>.self, forKey: .fieldAnchor),
      machineAnchor: container.decode(Point2<MachineSpace>.self, forKey: .machineAnchor),
      uniformScale: container.decode(Double.self, forKey: .uniformScale),
      rotationRadians: container.decode(Double.self, forKey: .rotationRadians)
    )
  }
}
