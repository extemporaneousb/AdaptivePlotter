import Foundation

public enum SemanticRole: UInt8, Codable, Sendable, CaseIterable {
  case drawing = 0
  case trainingProbe = 1
}

extension SemanticRole: CanonicalEncodable {
  public func encodeCanonical(to encoder: inout CanonicalEncoder) throws {
    encoder.appendUInt8(rawValue)
  }
}

public struct StrokeStyle: Hashable, Codable, Sendable, CanonicalEncodable {
  public let nominalLineWidth: Double
  public let penProfileID: PenProfileID

  public init(nominalLineWidth: Double, penProfileID: PenProfileID) throws {
    guard nominalLineWidth.isFinite, nominalLineWidth > 0 else {
      throw PlotterModelError.invalidValue("nominalLineWidth must be positive and finite")
    }
    self.nominalLineWidth = nominalLineWidth
    self.penProfileID = penProfileID
  }

  public func encodeCanonical(to encoder: inout CanonicalEncoder) throws {
    try encoder.appendDouble(nominalLineWidth)
    try penProfileID.encodeCanonical(to: &encoder)
  }

  private enum CodingKeys: String, CodingKey { case nominalLineWidth, penProfileID }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    try self.init(
      nominalLineWidth: container.decode(Double.self, forKey: .nominalLineWidth),
      penProfileID: container.decode(PenProfileID.self, forKey: .penProfileID)
    )
  }
}

public struct DrawingSourceProvenance: Hashable, Codable, Sendable, CanonicalEncodable {
  public let kind: String
  public let sourceIdentifier: String

  public init(kind: String, sourceIdentifier: String) throws {
    let kind = kind.precomposedStringWithCanonicalMapping
    let sourceIdentifier = sourceIdentifier.precomposedStringWithCanonicalMapping
    guard !kind.isEmpty, !sourceIdentifier.isEmpty else {
      throw PlotterModelError.invalidValue("drawing source provenance cannot be empty")
    }
    self.kind = kind
    self.sourceIdentifier = sourceIdentifier
  }

  public func encodeCanonical(to encoder: inout CanonicalEncoder) throws {
    try encoder.appendString(kind)
    try encoder.appendString(sourceIdentifier)
  }

  private enum CodingKeys: String, CodingKey { case kind, sourceIdentifier }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    try self.init(
      kind: container.decode(String.self, forKey: .kind),
      sourceIdentifier: container.decode(String.self, forKey: .sourceIdentifier)
    )
  }
}

public struct LogicalStroke: Hashable, Codable, Sendable, CanonicalEncodable {
  public let id: StrokeID
  public let path: Polyline<FieldSpace>
  public let style: StrokeStyle
  public let semanticRole: SemanticRole
  public let ordering: UInt32

  public init(
    id: StrokeID,
    path: Polyline<FieldSpace>,
    style: StrokeStyle,
    semanticRole: SemanticRole = .drawing,
    ordering: UInt32
  ) {
    self.id = id
    self.path = path
    self.style = style
    self.semanticRole = semanticRole
    self.ordering = ordering
  }

  public func encodeCanonical(to encoder: inout CanonicalEncoder) throws {
    try id.encodeCanonical(to: &encoder)
    try path.encodeCanonical(to: &encoder)
    try style.encodeCanonical(to: &encoder)
    try semanticRole.encodeCanonical(to: &encoder)
    encoder.appendUInt32(ordering)
  }
}

public struct DrawingProgram: Hashable, Sendable, Codable, CanonicalEncodable {
  public static let schemaVersion: UInt16 = 1

  public let id: ProgramID
  public let schemaVersion: UInt16
  public let fieldExtent: Size2<FieldSpace>
  public let strokes: [LogicalStroke]
  public let source: DrawingSourceProvenance
  public let contentHash: Digest

  public init(
    id: ProgramID,
    fieldExtent: Size2<FieldSpace>,
    strokes: [LogicalStroke],
    source: DrawingSourceProvenance
  ) throws {
    guard !strokes.isEmpty else {
      throw PlotterModelError.invalidValue("drawing program must contain a stroke")
    }
    guard Set(strokes.map(\.id)).count == strokes.count else {
      throw PlotterModelError.invalidValue("stroke IDs must be unique")
    }
    guard Set(strokes.map(\.ordering)).count == strokes.count else {
      throw PlotterModelError.invalidValue("stroke ordering values must be unique")
    }
    let field = try AxisAlignedBounds<FieldSpace>(
      minX: 0, minY: 0, maxX: fieldExtent.width, maxY: fieldExtent.height
    )
    guard
      strokes.allSatisfy({ stroke in
        stroke.path.points.allSatisfy { field.contains($0) }
      })
    else {
      throw PlotterModelError.invalidValue("stroke lies outside the declared field")
    }

    self.id = id
    schemaVersion = Self.schemaVersion
    self.fieldExtent = fieldExtent
    self.strokes = strokes.sorted { $0.ordering < $1.ordering }
    self.source = source
    contentHash = try canonicalDigest(
      of: DrawingProgramHashBasis(
        id: id,
        schemaVersion: Self.schemaVersion,
        fieldExtent: fieldExtent,
        strokes: self.strokes,
        source: source
      ))
  }

  public func encodeCanonical(to encoder: inout CanonicalEncoder) throws {
    try DrawingProgramHashBasis(
      id: id,
      schemaVersion: schemaVersion,
      fieldExtent: fieldExtent,
      strokes: strokes,
      source: source
    ).encodeCanonical(to: &encoder)
    encoder.appendDigest(contentHash)
  }

  private enum CodingKeys: String, CodingKey {
    case id, schemaVersion, fieldExtent, strokes, source, contentHash
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let encodedSchemaVersion = try container.decode(UInt16.self, forKey: .schemaVersion)
    guard encodedSchemaVersion == Self.schemaVersion else {
      throw PlotterModelError.invalidValue("unsupported DrawingProgram schema")
    }
    let decodedHash = try container.decode(Digest.self, forKey: .contentHash)
    let decoded = try Self(
      id: container.decode(ProgramID.self, forKey: .id),
      fieldExtent: container.decode(Size2<FieldSpace>.self, forKey: .fieldExtent),
      strokes: container.decode([LogicalStroke].self, forKey: .strokes),
      source: container.decode(DrawingSourceProvenance.self, forKey: .source)
    )
    guard decoded.contentHash == decodedHash else { throw PlotterModelError.contentHashMismatch }
    self = decoded
  }
}

private struct DrawingProgramHashBasis: CanonicalEncodable {
  let id: ProgramID
  let schemaVersion: UInt16
  let fieldExtent: Size2<FieldSpace>
  let strokes: [LogicalStroke]
  let source: DrawingSourceProvenance

  func encodeCanonical(to encoder: inout CanonicalEncoder) throws {
    try encoder.appendString("DrawingProgram")
    try id.encodeCanonical(to: &encoder)
    encoder.appendUInt16(schemaVersion)
    try fieldExtent.encodeCanonical(to: &encoder)
    try encoder.appendCount(strokes.count)
    for stroke in strokes { try stroke.encodeCanonical(to: &encoder) }
    try source.encodeCanonical(to: &encoder)
  }
}
