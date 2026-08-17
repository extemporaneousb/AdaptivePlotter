import CryptoKit
import Foundation

public struct DrawableMachineRegion: Hashable, Codable, Sendable, CanonicalEncodable {
  public let bounds: AxisAlignedBounds<MachineSpace>
  public let edgeClearance: Double

  public init(bounds: AxisAlignedBounds<MachineSpace>, edgeClearance: Double = 0) throws {
    guard edgeClearance.isFinite, edgeClearance >= 0 else {
      throw PlotterModelError.invalidValue("edgeClearance must be nonnegative and finite")
    }
    let effectiveMinX = bounds.minX + edgeClearance
    let effectiveMinY = bounds.minY + edgeClearance
    let effectiveMaxX = bounds.maxX - edgeClearance
    let effectiveMaxY = bounds.maxY - edgeClearance
    guard
      effectiveMinX.isFinite, effectiveMinY.isFinite,
      effectiveMaxX.isFinite, effectiveMaxY.isFinite,
      effectiveMinX < effectiveMaxX, effectiveMinY < effectiveMaxY
    else {
      throw PlotterModelError.invalidValue("edgeClearance consumes the drawable region")
    }
    self.bounds = bounds
    self.edgeClearance = edgeClearance == 0 ? 0 : edgeClearance
  }

  public var effectiveBounds: AxisAlignedBounds<MachineSpace> {
    try! AxisAlignedBounds(
      minX: bounds.minX + edgeClearance,
      minY: bounds.minY + edgeClearance,
      maxX: bounds.maxX - edgeClearance,
      maxY: bounds.maxY - edgeClearance
    )
  }

  public func contains(_ point: Point2<MachineSpace>, tolerance: Double = 0) -> Bool {
    guard tolerance.isFinite, tolerance >= 0 else { return false }
    return effectiveBounds.contains(point, tolerance: tolerance)
  }

  public func contains(_ polyline: Polyline<MachineSpace>, tolerance: Double = 0) -> Bool {
    polyline.points.allSatisfy { contains($0, tolerance: tolerance) }
  }

  public func encodeCanonical(to encoder: inout CanonicalEncoder) throws {
    try encoder.appendString("DrawableMachineRegion")
    try bounds.encodeCanonical(to: &encoder)
    try encoder.appendDouble(edgeClearance)
  }

  private enum CodingKeys: String, CodingKey { case bounds, edgeClearance }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    try self.init(
      bounds: container.decode(AxisAlignedBounds<MachineSpace>.self, forKey: .bounds),
      edgeClearance: container.decode(Double.self, forKey: .edgeClearance)
    )
  }
}

public struct DrawingPlanningProvenance: Hashable, Codable, Sendable, CanonicalEncodable {
  public let modelRevisionID: DrawingModelRevisionID
  public let modelContentHash: Digest
  public let registrationRevisionID: DrawingRegistrationRevisionID
  public let registrationContentHash: Digest

  public init(
    modelRevisionID: DrawingModelRevisionID,
    modelContentHash: Digest,
    registrationRevisionID: DrawingRegistrationRevisionID,
    registrationContentHash: Digest
  ) {
    self.modelRevisionID = modelRevisionID
    self.modelContentHash = modelContentHash
    self.registrationRevisionID = registrationRevisionID
    self.registrationContentHash = registrationContentHash
  }

  public func encodeCanonical(to encoder: inout CanonicalEncoder) throws {
    try encoder.appendString("DrawingPlanningProvenance")
    try modelRevisionID.encodeCanonical(to: &encoder)
    encoder.appendDigest(modelContentHash)
    try registrationRevisionID.encodeCanonical(to: &encoder)
    encoder.appendDigest(registrationContentHash)
  }
}

public struct ExecutionPlanRevisionID: Hashable, Codable, Sendable, CustomStringConvertible {
  public let rawValue: Digest

  public init(_ rawValue: Digest) {
    self.rawValue = rawValue
  }

  public var description: String { rawValue.description }
}

extension ExecutionPlanRevisionID: CanonicalEncodable {
  public func encodeCanonical(to encoder: inout CanonicalEncoder) throws {
    encoder.appendDigest(rawValue)
  }
}

public struct PlannedMachineStroke: Hashable, Codable, Sendable, CanonicalEncodable {
  public let logicalStrokeID: StrokeID
  public let path: Polyline<MachineSpace>
  public let style: StrokeStyle
  public let semanticRole: SemanticRole
  public let ordering: UInt32
  public let endingCheckpointID: PlanCheckpointID

  public init(
    logicalStrokeID: StrokeID,
    path: Polyline<MachineSpace>,
    style: StrokeStyle,
    semanticRole: SemanticRole,
    ordering: UInt32,
    endingCheckpointID: PlanCheckpointID
  ) {
    self.logicalStrokeID = logicalStrokeID
    self.path = path
    self.style = style
    self.semanticRole = semanticRole
    self.ordering = ordering
    self.endingCheckpointID = endingCheckpointID
  }

  public func encodeCanonical(to encoder: inout CanonicalEncoder) throws {
    try logicalStrokeID.encodeCanonical(to: &encoder)
    try path.encodeCanonical(to: &encoder)
    try style.encodeCanonical(to: &encoder)
    try semanticRole.encodeCanonical(to: &encoder)
    encoder.appendUInt32(ordering)
    try endingCheckpointID.encodeCanonical(to: &encoder)
  }
}

public struct ExecutionCheckpoint: Hashable, Codable, Sendable, CanonicalEncodable {
  public let id: PlanCheckpointID
  public let afterStrokeID: StrokeID
  public let ordering: UInt32

  public init(id: PlanCheckpointID, afterStrokeID: StrokeID, ordering: UInt32) {
    self.id = id
    self.afterStrokeID = afterStrokeID
    self.ordering = ordering
  }

  public func encodeCanonical(to encoder: inout CanonicalEncoder) throws {
    try id.encodeCanonical(to: &encoder)
    try afterStrokeID.encodeCanonical(to: &encoder)
    encoder.appendUInt32(ordering)
  }
}

public enum DrawingPlanningError: Error, Equatable, Sendable {
  case emptyPlan
  case duplicateStrokeIdentity
  case duplicateOrdering
  case invalidCheckpointTopology
  case outsideDrawableRegion(strokeID: StrokeID, pointIndex: Int)
  case contentHashMismatch
}

public struct ExecutionPlanRevision: Hashable, Codable, Sendable, CanonicalEncodable {
  public static let schemaVersion: UInt16 = 1

  public let revisionID: ExecutionPlanRevisionID
  public let schemaVersion: UInt16
  public let sourceProgramID: ProgramID
  public let sourceProgramContentHash: Digest
  public let placement: DrawingPlacement
  public let drawableRegion: DrawableMachineRegion
  public let provenance: DrawingPlanningProvenance
  public let strokes: [PlannedMachineStroke]
  public let checkpoints: [ExecutionCheckpoint]
  public let contentHash: Digest

  public init(
    sourceProgramID: ProgramID,
    sourceProgramContentHash: Digest,
    placement: DrawingPlacement,
    drawableRegion: DrawableMachineRegion,
    provenance: DrawingPlanningProvenance,
    strokes: [PlannedMachineStroke],
    checkpoints: [ExecutionCheckpoint]
  ) throws {
    guard !strokes.isEmpty else { throw DrawingPlanningError.emptyPlan }
    guard Set(strokes.map(\.logicalStrokeID)).count == strokes.count else {
      throw DrawingPlanningError.duplicateStrokeIdentity
    }
    guard Set(strokes.map(\.ordering)).count == strokes.count else {
      throw DrawingPlanningError.duplicateOrdering
    }

    let orderedStrokes = strokes.sorted { $0.ordering < $1.ordering }
    let orderedCheckpoints = checkpoints.sorted { $0.ordering < $1.ordering }
    guard
      orderedCheckpoints.count == orderedStrokes.count,
      Set(orderedCheckpoints.map(\.id)).count == orderedCheckpoints.count,
      Set(orderedCheckpoints.map(\.afterStrokeID)).count == orderedCheckpoints.count,
      Set(orderedCheckpoints.map(\.ordering)).count == orderedCheckpoints.count,
      zip(orderedStrokes, orderedCheckpoints).allSatisfy({ stroke, checkpoint in
        checkpoint.afterStrokeID == stroke.logicalStrokeID
          && checkpoint.id == stroke.endingCheckpointID
          && checkpoint.ordering == stroke.ordering
      })
    else {
      throw DrawingPlanningError.invalidCheckpointTopology
    }

    for stroke in orderedStrokes {
      for (pointIndex, point) in stroke.path.points.enumerated()
      where !drawableRegion.contains(point) {
        throw DrawingPlanningError.outsideDrawableRegion(
          strokeID: stroke.logicalStrokeID,
          pointIndex: pointIndex
        )
      }
    }

    let basis = ExecutionPlanRevisionHashBasis(
      schemaVersion: Self.schemaVersion,
      sourceProgramID: sourceProgramID,
      sourceProgramContentHash: sourceProgramContentHash,
      placement: placement,
      drawableRegion: drawableRegion,
      provenance: provenance,
      strokes: orderedStrokes,
      checkpoints: orderedCheckpoints
    )
    let hash = try canonicalDigest(of: basis)
    revisionID = ExecutionPlanRevisionID(hash)
    schemaVersion = Self.schemaVersion
    self.sourceProgramID = sourceProgramID
    self.sourceProgramContentHash = sourceProgramContentHash
    self.placement = placement
    self.drawableRegion = drawableRegion
    self.provenance = provenance
    self.strokes = orderedStrokes
    self.checkpoints = orderedCheckpoints
    contentHash = hash
  }

  public func encodeCanonical(to encoder: inout CanonicalEncoder) throws {
    try ExecutionPlanRevisionHashBasis(
      schemaVersion: schemaVersion,
      sourceProgramID: sourceProgramID,
      sourceProgramContentHash: sourceProgramContentHash,
      placement: placement,
      drawableRegion: drawableRegion,
      provenance: provenance,
      strokes: strokes,
      checkpoints: checkpoints
    ).encodeCanonical(to: &encoder)
    try revisionID.encodeCanonical(to: &encoder)
    encoder.appendDigest(contentHash)
  }

  private enum CodingKeys: String, CodingKey {
    case revisionID, schemaVersion, sourceProgramID, sourceProgramContentHash
    case placement, drawableRegion, provenance, strokes, checkpoints, contentHash
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let encodedSchemaVersion = try container.decode(UInt16.self, forKey: .schemaVersion)
    guard encodedSchemaVersion == Self.schemaVersion else {
      throw PlotterModelError.invalidValue("unsupported ExecutionPlanRevision schema")
    }
    let decodedRevisionID = try container.decode(
      ExecutionPlanRevisionID.self,
      forKey: .revisionID
    )
    let decodedHash = try container.decode(Digest.self, forKey: .contentHash)
    let decoded = try Self(
      sourceProgramID: container.decode(ProgramID.self, forKey: .sourceProgramID),
      sourceProgramContentHash: container.decode(Digest.self, forKey: .sourceProgramContentHash),
      placement: container.decode(DrawingPlacement.self, forKey: .placement),
      drawableRegion: container.decode(DrawableMachineRegion.self, forKey: .drawableRegion),
      provenance: container.decode(DrawingPlanningProvenance.self, forKey: .provenance),
      strokes: container.decode([PlannedMachineStroke].self, forKey: .strokes),
      checkpoints: container.decode([ExecutionCheckpoint].self, forKey: .checkpoints)
    )
    guard decoded.revisionID == decodedRevisionID, decoded.contentHash == decodedHash else {
      throw DrawingPlanningError.contentHashMismatch
    }
    self = decoded
  }
}

public enum DrawingPlanner {
  public static func plan(
    program: DrawingProgram,
    placement: DrawingPlacement,
    drawableRegion: DrawableMachineRegion,
    provenance: DrawingPlanningProvenance
  ) throws -> ExecutionPlanRevision {
    let placementHash = try canonicalDigest(of: placement)
    let regionHash = try canonicalDigest(of: drawableRegion)
    let provenanceHash = try canonicalDigest(of: provenance)
    var planned: [PlannedMachineStroke] = []
    var checkpoints: [ExecutionCheckpoint] = []
    planned.reserveCapacity(program.strokes.count)
    checkpoints.reserveCapacity(program.strokes.count)

    for stroke in program.strokes {
      let checkpointID = PlanCheckpointID(
        stablePlanUUID(
          seed: [
            program.contentHash.description,
            placementHash.description,
            regionHash.description,
            provenanceHash.description,
            stroke.id.description,
          ].joined(separator: ":")))
      planned.append(
        PlannedMachineStroke(
          logicalStrokeID: stroke.id,
          path: try placement.applying(to: stroke.path),
          style: stroke.style,
          semanticRole: stroke.semanticRole,
          ordering: stroke.ordering,
          endingCheckpointID: checkpointID
        ))
      checkpoints.append(
        ExecutionCheckpoint(
          id: checkpointID,
          afterStrokeID: stroke.id,
          ordering: stroke.ordering
        ))
    }

    return try ExecutionPlanRevision(
      sourceProgramID: program.id,
      sourceProgramContentHash: program.contentHash,
      placement: placement,
      drawableRegion: drawableRegion,
      provenance: provenance,
      strokes: planned,
      checkpoints: checkpoints
    )
  }
}

private struct ExecutionPlanRevisionHashBasis: CanonicalEncodable {
  let schemaVersion: UInt16
  let sourceProgramID: ProgramID
  let sourceProgramContentHash: Digest
  let placement: DrawingPlacement
  let drawableRegion: DrawableMachineRegion
  let provenance: DrawingPlanningProvenance
  let strokes: [PlannedMachineStroke]
  let checkpoints: [ExecutionCheckpoint]

  func encodeCanonical(to encoder: inout CanonicalEncoder) throws {
    try encoder.appendString("ExecutionPlanRevision")
    encoder.appendUInt16(schemaVersion)
    try sourceProgramID.encodeCanonical(to: &encoder)
    encoder.appendDigest(sourceProgramContentHash)
    try placement.encodeCanonical(to: &encoder)
    try drawableRegion.encodeCanonical(to: &encoder)
    try provenance.encodeCanonical(to: &encoder)
    try encoder.appendCount(strokes.count)
    for stroke in strokes { try stroke.encodeCanonical(to: &encoder) }
    try encoder.appendCount(checkpoints.count)
    for checkpoint in checkpoints { try checkpoint.encodeCanonical(to: &encoder) }
  }
}

private func stablePlanUUID(seed: String) -> UUID {
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
