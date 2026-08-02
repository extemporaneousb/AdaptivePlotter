import Foundation

public enum SourceRasterSpace: Sendable {}
public enum CameraPixelSpace: Sendable {}
public enum CameraPlaneSpace: Sendable {}
public enum FieldSpace: Sendable {}
public enum MachineSpace: Sendable {}
public enum ToolSpace: Sendable {}

public enum GeometryError: Error, Equatable, Sendable {
  case nonFiniteCoordinate
  case insufficientPoints(required: Int, actual: Int)
  case degenerateGeometry
  case invalidBounds
  case singularTransform
  case outsideDomain
  case forwardCheckFailed(error: Double, limit: Double)
}

@inline(__always)
private func normalizedFinite(_ value: Double) throws -> Double {
  guard value.isFinite else { throw GeometryError.nonFiniteCoordinate }
  return value == 0 ? 0 : value
}

public struct Point2<Space>: Hashable, Sendable, Codable {
  public let x: Double
  public let y: Double

  public init(x: Double, y: Double) throws {
    self.x = try normalizedFinite(x)
    self.y = try normalizedFinite(y)
  }

  fileprivate init(validatedX x: Double, validatedY y: Double) {
    self.x = x
    self.y = y
  }

  public func distance(to other: Self) -> Double {
    hypot(other.x - x, other.y - y)
  }

  public func vector(to other: Self) throws -> Vector2<Space> {
    try Vector2(dx: other.x - x, dy: other.y - y)
  }

  public func translated(by vector: Vector2<Space>) throws -> Self {
    try Self(x: x + vector.dx, y: y + vector.dy)
  }

  private enum CodingKeys: String, CodingKey { case x, y }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    try self.init(
      x: container.decode(Double.self, forKey: .x),
      y: container.decode(Double.self, forKey: .y)
    )
  }
}

extension Point2: CanonicalEncodable {
  public func encodeCanonical(to encoder: inout CanonicalEncoder) throws {
    try encoder.appendDouble(x)
    try encoder.appendDouble(y)
  }
}

public struct Vector2<Space>: Hashable, Sendable, Codable {
  public let dx: Double
  public let dy: Double

  public init(dx: Double, dy: Double) throws {
    self.dx = try normalizedFinite(dx)
    self.dy = try normalizedFinite(dy)
  }

  public var magnitude: Double { hypot(dx, dy) }

  private enum CodingKeys: String, CodingKey { case dx, dy }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    try self.init(
      dx: container.decode(Double.self, forKey: .dx),
      dy: container.decode(Double.self, forKey: .dy)
    )
  }
}

extension Vector2: CanonicalEncodable {
  public func encodeCanonical(to encoder: inout CanonicalEncoder) throws {
    try encoder.appendDouble(dx)
    try encoder.appendDouble(dy)
  }
}

public struct Size2<Space>: Hashable, Sendable, Codable {
  public let width: Double
  public let height: Double

  public init(width: Double, height: Double) throws {
    let width = try normalizedFinite(width)
    let height = try normalizedFinite(height)
    guard width > 0, height > 0 else { throw GeometryError.invalidBounds }
    self.width = width
    self.height = height
  }

  private enum CodingKeys: String, CodingKey { case width, height }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    try self.init(
      width: container.decode(Double.self, forKey: .width),
      height: container.decode(Double.self, forKey: .height)
    )
  }
}

extension Size2: CanonicalEncodable {
  public func encodeCanonical(to encoder: inout CanonicalEncoder) throws {
    try encoder.appendDouble(width)
    try encoder.appendDouble(height)
  }
}

public struct Polyline<Space>: Hashable, Sendable, Codable {
  public let points: [Point2<Space>]

  public init(points: [Point2<Space>]) throws {
    guard points.count >= 2 else {
      throw GeometryError.insufficientPoints(required: 2, actual: points.count)
    }
    guard zip(points, points.dropFirst()).contains(where: { $0 != $1 }) else {
      throw GeometryError.degenerateGeometry
    }
    self.points = points
  }

  public var start: Point2<Space> { points[0] }
  public var end: Point2<Space> { points[points.count - 1] }

  public var length: Double {
    zip(points, points.dropFirst()).reduce(0) { partial, pair in
      partial + pair.0.distance(to: pair.1)
    }
  }

  private enum CodingKeys: String, CodingKey { case points }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    try self.init(points: container.decode([Point2<Space>].self, forKey: .points))
  }
}

extension Polyline: CanonicalEncodable {
  public func encodeCanonical(to encoder: inout CanonicalEncoder) throws {
    try encoder.appendCount(points.count)
    for point in points { try point.encodeCanonical(to: &encoder) }
  }
}

public struct Polygon2<Space>: Hashable, Sendable, Codable {
  public let vertices: [Point2<Space>]
  public let bounds: AxisAlignedBounds<Space>

  public init(vertices: [Point2<Space>]) throws {
    guard vertices.count >= 3 else {
      throw GeometryError.insufficientPoints(required: 3, actual: vertices.count)
    }
    let signedDoubleArea = vertices.indices.reduce(0.0) { partial, index in
      let next = vertices[(index + 1) % vertices.count]
      let current = vertices[index]
      return partial + current.x * next.y - next.x * current.y
    }
    guard signedDoubleArea.isFinite, abs(signedDoubleArea) > 1e-12 else {
      throw GeometryError.degenerateGeometry
    }
    self.vertices = vertices
    var minX = vertices[0].x
    var minY = vertices[0].y
    var maxX = vertices[0].x
    var maxY = vertices[0].y
    for vertex in vertices.dropFirst() {
      minX = min(minX, vertex.x)
      minY = min(minY, vertex.y)
      maxX = max(maxX, vertex.x)
      maxY = max(maxY, vertex.y)
    }
    bounds = AxisAlignedBounds(
      validatedMinX: minX, validatedMinY: minY,
      validatedMaxX: maxX, validatedMaxY: maxY
    )
  }

  private enum CodingKeys: String, CodingKey { case vertices }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    try self.init(vertices: container.decode([Point2<Space>].self, forKey: .vertices))
  }
}

extension Polygon2: CanonicalEncodable {
  public func encodeCanonical(to encoder: inout CanonicalEncoder) throws {
    try encoder.appendCount(vertices.count)
    for vertex in vertices { try vertex.encodeCanonical(to: &encoder) }
  }
}

public struct AxisAlignedBounds<Space>: Hashable, Sendable, Codable {
  public let minX: Double
  public let minY: Double
  public let maxX: Double
  public let maxY: Double

  public init(minX: Double, minY: Double, maxX: Double, maxY: Double) throws {
    let minX = try normalizedFinite(minX)
    let minY = try normalizedFinite(minY)
    let maxX = try normalizedFinite(maxX)
    let maxY = try normalizedFinite(maxY)
    guard minX < maxX, minY < maxY else { throw GeometryError.invalidBounds }
    self.minX = minX
    self.minY = minY
    self.maxX = maxX
    self.maxY = maxY
  }

  fileprivate init(
    validatedMinX minX: Double,
    validatedMinY minY: Double,
    validatedMaxX maxX: Double,
    validatedMaxY maxY: Double
  ) {
    self.minX = minX
    self.minY = minY
    self.maxX = maxX
    self.maxY = maxY
  }

  public func contains(_ point: Point2<Space>, tolerance: Double = 0) -> Bool {
    point.x >= minX - tolerance && point.x <= maxX + tolerance
      && point.y >= minY - tolerance && point.y <= maxY + tolerance
  }

  public func expanded(by margin: Double) throws -> Self {
    let margin = try normalizedFinite(margin)
    guard margin >= 0 else { throw GeometryError.invalidBounds }
    return try Self(
      minX: minX - margin, minY: minY - margin,
      maxX: maxX + margin, maxY: maxY + margin
    )
  }

  public func intersects(_ other: Self) -> Bool {
    !(maxX < other.minX || other.maxX < minX || maxY < other.minY || other.maxY < minY)
  }

  public var corners: [Point2<Space>] {
    [
      Point2(validatedX: minX, validatedY: minY),
      Point2(validatedX: maxX, validatedY: minY),
      Point2(validatedX: maxX, validatedY: maxY),
      Point2(validatedX: minX, validatedY: maxY),
    ]
  }

  private enum CodingKeys: String, CodingKey { case minX, minY, maxX, maxY }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    try self.init(
      minX: container.decode(Double.self, forKey: .minX),
      minY: container.decode(Double.self, forKey: .minY),
      maxX: container.decode(Double.self, forKey: .maxX),
      maxY: container.decode(Double.self, forKey: .maxY)
    )
  }
}

extension AxisAlignedBounds: CanonicalEncodable {
  public func encodeCanonical(to encoder: inout CanonicalEncoder) throws {
    try encoder.appendDouble(minX)
    try encoder.appendDouble(minY)
    try encoder.appendDouble(maxX)
    try encoder.appendDouble(maxY)
  }
}

public struct AffineTransform2<From, To>: Hashable, Sendable, Codable {
  public let m11: Double
  public let m12: Double
  public let m21: Double
  public let m22: Double
  public let tx: Double
  public let ty: Double

  public init(
    m11: Double,
    m12: Double,
    m21: Double,
    m22: Double,
    tx: Double,
    ty: Double
  ) throws {
    self.m11 = try normalizedFinite(m11)
    self.m12 = try normalizedFinite(m12)
    self.m21 = try normalizedFinite(m21)
    self.m22 = try normalizedFinite(m22)
    self.tx = try normalizedFinite(tx)
    self.ty = try normalizedFinite(ty)
    guard abs(determinant) > 1e-12 else { throw GeometryError.singularTransform }
  }

  public var determinant: Double { m11 * m22 - m12 * m21 }

  public func applying(to point: Point2<From>) throws -> Point2<To> {
    try Point2(
      x: m11 * point.x + m12 * point.y + tx,
      y: m21 * point.x + m22 * point.y + ty
    )
  }

  public func applying(to polyline: Polyline<From>) throws -> Polyline<To> {
    try Polyline(points: polyline.points.map { try applying(to: $0) })
  }

  public func inverted() throws -> AffineTransform2<To, From> {
    let inverseDeterminant = 1 / determinant
    let a = m22 * inverseDeterminant
    let b = -m12 * inverseDeterminant
    let c = -m21 * inverseDeterminant
    let d = m11 * inverseDeterminant
    return try AffineTransform2<To, From>(
      m11: a,
      m12: b,
      m21: c,
      m22: d,
      tx: -(a * tx + b * ty),
      ty: -(c * tx + d * ty)
    )
  }

  private enum CodingKeys: String, CodingKey { case m11, m12, m21, m22, tx, ty }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    try self.init(
      m11: container.decode(Double.self, forKey: .m11),
      m12: container.decode(Double.self, forKey: .m12),
      m21: container.decode(Double.self, forKey: .m21),
      m22: container.decode(Double.self, forKey: .m22),
      tx: container.decode(Double.self, forKey: .tx),
      ty: container.decode(Double.self, forKey: .ty)
    )
  }
}

extension AffineTransform2: CanonicalEncodable {
  public func encodeCanonical(to encoder: inout CanonicalEncoder) throws {
    try encoder.appendDouble(m11)
    try encoder.appendDouble(m12)
    try encoder.appendDouble(m21)
    try encoder.appendDouble(m22)
    try encoder.appendDouble(tx)
    try encoder.appendDouble(ty)
  }
}
