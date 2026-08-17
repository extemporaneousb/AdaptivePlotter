import CryptoKit
import Foundation

public enum DrawingCatalogEntryID: String, Codable, Sendable, CaseIterable {
  case line
  case polyline
  case rectangle
  case square
  case triangle
  case regularPolygon
  case circle
  case ellipse
  case star
  case pyramid
  case elephant
}

extension DrawingCatalogEntryID: CanonicalEncodable {
  public func encodeCanonical(to encoder: inout CanonicalEncoder) throws {
    try encoder.appendString(rawValue)
  }
}

/// The deterministic curve-flattening contract used by built-in vector
/// sources. Error is measured in the generated program's FieldSpace units.
public struct CurveTessellationPolicy: Hashable, Codable, Sendable, CanonicalEncodable {
  public static let currentAlgorithmRevision: UInt16 = 1

  public let maximumChordError: Double
  public let algorithmRevision: UInt16
  public let maximumSegments: UInt32

  public init(
    maximumChordError: Double,
    algorithmRevision: UInt16 = Self.currentAlgorithmRevision,
    maximumSegments: UInt32 = 4_096
  ) throws {
    guard maximumChordError.isFinite, maximumChordError > 0 else {
      throw PlotterModelError.invalidValue("maximumChordError must be positive and finite")
    }
    guard algorithmRevision == Self.currentAlgorithmRevision else {
      throw PlotterModelError.invalidValue("unsupported curve tessellation revision")
    }
    guard maximumSegments >= 12 else {
      throw PlotterModelError.invalidValue("maximumSegments must be at least 12")
    }
    self.maximumChordError = maximumChordError
    self.algorithmRevision = algorithmRevision
    self.maximumSegments = maximumSegments
  }

  public static var catalogDefault: Self {
    // Constants are kept in one typed policy so the catalog cannot silently
    // change its curve density without changing provenance and content hashes.
    try! Self(maximumChordError: 0.25)
  }

  public func encodeCanonical(to encoder: inout CanonicalEncoder) throws {
    try encoder.appendString("CurveTessellationPolicy")
    try encoder.appendDouble(maximumChordError)
    encoder.appendUInt16(algorithmRevision)
    encoder.appendUInt32(maximumSegments)
  }

  private enum CodingKeys: String, CodingKey {
    case maximumChordError, algorithmRevision, maximumSegments
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    try self.init(
      maximumChordError: container.decode(Double.self, forKey: .maximumChordError),
      algorithmRevision: container.decode(UInt16.self, forKey: .algorithmRevision),
      maximumSegments: container.decode(UInt32.self, forKey: .maximumSegments)
    )
  }
}

public struct DrawingProgramCatalogEntry: Hashable, Codable, Sendable {
  public let id: DrawingCatalogEntryID
  public let displayName: String
  public let sourceIdentifier: String
  public let fieldExtent: Size2<FieldSpace>
  public let supportsCurveTessellation: Bool

  public init(
    id: DrawingCatalogEntryID,
    displayName: String,
    sourceIdentifier: String,
    fieldExtent: Size2<FieldSpace>,
    supportsCurveTessellation: Bool
  ) throws {
    let displayName = displayName.precomposedStringWithCanonicalMapping
    let sourceIdentifier = sourceIdentifier.precomposedStringWithCanonicalMapping
    guard !displayName.isEmpty, !sourceIdentifier.isEmpty else {
      throw PlotterModelError.invalidValue("catalog metadata cannot be empty")
    }
    self.id = id
    self.displayName = displayName
    self.sourceIdentifier = sourceIdentifier
    self.fieldExtent = fieldExtent
    self.supportsCurveTessellation = supportsCurveTessellation
  }

  private enum CodingKeys: String, CodingKey {
    case id, displayName, sourceIdentifier, fieldExtent, supportsCurveTessellation
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    try self.init(
      id: container.decode(DrawingCatalogEntryID.self, forKey: .id),
      displayName: container.decode(String.self, forKey: .displayName),
      sourceIdentifier: container.decode(String.self, forKey: .sourceIdentifier),
      fieldExtent: container.decode(Size2<FieldSpace>.self, forKey: .fieldExtent),
      supportsCurveTessellation: container.decode(Bool.self, forKey: .supportsCurveTessellation)
    )
  }
}

public enum DrawingProgramCatalogError: Error, Equatable, Sendable {
  case excessiveTessellation(maximum: UInt32)
}

/// Built-in logical vector sources. Every source resolves to the existing
/// DrawingProgram/LogicalStroke/Polyline primitives; execution never sees a
/// circle, polygon, or object-specific command.
public enum DrawingProgramCatalog {
  public static let entries: [DrawingProgramCatalogEntry] = [
    entry(.line, "Line", 100, 100),
    entry(.polyline, "Polyline", 100, 100),
    entry(.rectangle, "Rectangle", 100, 70),
    entry(.square, "Square", 100, 100),
    entry(.triangle, "Triangle", 100, 100),
    entry(.regularPolygon, "Regular Polygon", 100, 100),
    entry(.circle, "Circle", 100, 100, curve: true),
    entry(.ellipse, "Ellipse", 100, 70, curve: true),
    entry(.star, "Star", 100, 100),
    entry(.pyramid, "Pyramid", 100, 100),
    entry(.elephant, "Elephant", 140, 100),
  ]

  public static func entry(for id: DrawingCatalogEntryID) -> DrawingProgramCatalogEntry {
    entries.first { $0.id == id }!
  }

  public static func program(
    for id: DrawingCatalogEntryID,
    style: StrokeStyle,
    tessellation: CurveTessellationPolicy = .catalogDefault
  ) throws -> DrawingProgram {
    let metadata = entry(for: id)
    let paths: [Polyline<FieldSpace>]
    switch id {
    case .line:
      paths = [try polyline([(5, 50), (95, 50)])]
    case .polyline:
      paths = [try polyline([(5, 80), (28, 20), (50, 78), (72, 20), (95, 80)])]
    case .rectangle:
      paths = [try polyline([(2, 2), (98, 2), (98, 68), (2, 68), (2, 2)])]
    case .square:
      paths = [try polyline([(2, 2), (98, 2), (98, 98), (2, 98), (2, 2)])]
    case .triangle:
      paths = [try polyline([(50, 2), (98, 98), (2, 98), (50, 2)])]
    case .regularPolygon:
      paths = [try radialPolygon(vertexCount: 6, outerRadius: 48, innerRadius: nil)]
    case .circle:
      paths = [try ellipse(width: 96, height: 96, centerX: 50, centerY: 50, tessellation)]
    case .ellipse:
      paths = [try ellipse(width: 96, height: 66, centerX: 50, centerY: 35, tessellation)]
    case .star:
      paths = [try radialPolygon(vertexCount: 5, outerRadius: 48, innerRadius: 21)]
    case .pyramid:
      paths = try pyramidPaths()
    case .elephant:
      paths = try elephantPaths()
    }

    let curveSuffix =
      metadata.supportsCurveTessellation
      ? ".tess-\(tessellation.algorithmRevision)-\(String(format: "%016llx", tessellation.maximumChordError.bitPattern))-\(tessellation.maximumSegments)"
      : ""
    let sourceIdentifier = metadata.sourceIdentifier + curveSuffix
    let styleHash = try canonicalDigest(of: style)
    let programSeed = "program:\(sourceIdentifier):\(styleHash.description)"
    let programID = ProgramID(stableUUID(seed: programSeed))
    let strokes = paths.enumerated().map { index, path in
      LogicalStroke(
        id: StrokeID(stableUUID(seed: "stroke:\(programSeed):\(index)")),
        path: path,
        style: style,
        semanticRole: .drawing,
        ordering: UInt32(index)
      )
    }
    return try DrawingProgram(
      id: programID,
      fieldExtent: metadata.fieldExtent,
      strokes: strokes,
      source: DrawingSourceProvenance(
        kind: "built-in-vector-catalog",
        sourceIdentifier: sourceIdentifier
      )
    )
  }

  private static func entry(
    _ id: DrawingCatalogEntryID,
    _ displayName: String,
    _ width: Double,
    _ height: Double,
    curve: Bool = false
  ) -> DrawingProgramCatalogEntry {
    try! DrawingProgramCatalogEntry(
      id: id,
      displayName: displayName,
      sourceIdentifier: "adaptiveplotter.builtin.\(id.rawValue).v1",
      fieldExtent: Size2(width: width, height: height),
      supportsCurveTessellation: curve
    )
  }

  private static func polyline(_ coordinates: [(Double, Double)]) throws -> Polyline<FieldSpace> {
    try Polyline(points: coordinates.map { try Point2(x: $0.0, y: $0.1) })
  }

  private static func radialPolygon(
    vertexCount: Int,
    outerRadius: Double,
    innerRadius: Double?
  ) throws -> Polyline<FieldSpace> {
    let count = innerRadius == nil ? vertexCount : vertexCount * 2
    var points: [Point2<FieldSpace>] = []
    points.reserveCapacity(count + 1)
    for index in 0..<count {
      let radius = index.isMultiple(of: 2) ? outerRadius : (innerRadius ?? outerRadius)
      let angle = -.pi / 2 + 2 * .pi * Double(index) / Double(count)
      points.append(try Point2(x: 50 + radius * cos(angle), y: 50 + radius * sin(angle)))
    }
    points.append(points[0])
    return try Polyline(points: points)
  }

  private static func ellipse(
    width: Double,
    height: Double,
    centerX: Double,
    centerY: Double,
    _ policy: CurveTessellationPolicy
  ) throws -> Polyline<FieldSpace> {
    // The second derivative norm of this parameterization is bounded by the
    // largest radius. Linear interpolation error is therefore <= M*h^2/8.
    let maximumRadius = max(width, height) / 2
    let estimated = ceil(2 * Double.pi * sqrt(maximumRadius / (8 * policy.maximumChordError)))
    guard estimated.isFinite, estimated <= Double(policy.maximumSegments) else {
      throw DrawingProgramCatalogError.excessiveTessellation(maximum: policy.maximumSegments)
    }
    let segmentCount = UInt32(max(12, estimated))
    var points: [Point2<FieldSpace>] = []
    points.reserveCapacity(Int(segmentCount) + 1)
    for index in 0..<segmentCount {
      let angle = 2 * .pi * Double(index) / Double(segmentCount)
      points.append(
        try Point2(
          x: centerX + width / 2 * cos(angle),
          y: centerY + height / 2 * sin(angle)
        ))
    }
    points.append(points[0])
    return try Polyline(points: points)
  }

  private static func pyramidPaths() throws -> [Polyline<FieldSpace>] {
    [
      try polyline([(5, 66), (50, 92), (95, 66), (50, 49), (5, 66)]),
      try polyline([(50, 5), (5, 66)]),
      try polyline([(50, 5), (50, 49)]),
      try polyline([(50, 5), (95, 66)]),
    ]
  }

  private static func elephantPaths() throws -> [Polyline<FieldSpace>] {
    [
      try polyline([
        (18, 54), (22, 33), (41, 19), (80, 18), (97, 27), (107, 25),
        (119, 31), (124, 44), (122, 70), (115, 85), (107, 85), (108, 57),
        (98, 52), (92, 59), (90, 85), (80, 85), (78, 60), (53, 60),
        (51, 85), (41, 85), (39, 59), (28, 68), (18, 62), (18, 54),
      ]),
      try polyline([(87, 29), (104, 32), (101, 52), (89, 48), (87, 29)]),
      try polyline([(111, 58), (121, 54)]),
      try polyline([(108, 37), (110, 37)]),
      try polyline([(21, 34), (10, 23), (7, 28)]),
    ]
  }

  private static func stableUUID(seed: String) -> UUID {
    var bytes = Array(SHA256.hash(data: Data(seed.utf8)).prefix(16))
    bytes[6] = (bytes[6] & 0x0f) | 0x50
    bytes[8] = (bytes[8] & 0x3f) | 0x80
    return UUID(
      uuid: (
        bytes[0], bytes[1], bytes[2], bytes[3],
        bytes[4], bytes[5], bytes[6], bytes[7],
        bytes[8], bytes[9], bytes[10], bytes[11],
        bytes[12], bytes[13], bytes[14], bytes[15]
      ))
  }
}
