import PlotterModel

/// One immutable logical stroke, already serialized by DrawingWireSchedule.
public struct DrawingPolylineRequest: Codable, Hashable, Sendable {
  public let segments: [DrawingStrokeRequest]
  public let sourceSegmentRanges: [ClosedRange<Int>]?
  public init(segments: [DrawingStrokeRequest], sourceSegmentRanges: [ClosedRange<Int>]? = nil) {
    self.segments = segments
    self.sourceSegmentRanges = sourceSegmentRanges
  }
}

public struct DrawingPolylineEvidence: Codable, Hashable, Sendable {
  public let request: DrawingPolylineRequest
  public let submittedSegmentCount: Int
  public let acknowledgedSegmentCount: Int
  public let startPosition: MachinePosition
  public let startSampleNanoseconds: UInt64
  public let finalPosition: MachinePosition
  public let finalSampleNanoseconds: UInt64
}

public enum DrawingPolylineOutcome: Codable, Hashable, Sendable {
  case refused(DrawingStrokeRefusal)
  case completed(evidence: DrawingPolylineEvidence)
  case cancelled(evidence: DrawingPolylineEvidence, penRaiseOutcome: PenOutcome)
  case ambiguous(MotionAmbiguity)
}

/// Submission is emitted when the write attempt resolves, including a
/// possibly partial write. Acknowledgement means acceptance, never completion.
public enum DrawingPolylineProgress: Sendable {
  case submitting(Int)
  case acknowledged(Int)
  case cancellationSettled(UInt64, DrawingOperationSpan.Disposition)
  case penCleanup(started: UInt64, ended: UInt64, disposition: DrawingOperationSpan.Disposition)
}

/// Controller-operation elapsed time. These spans include protocol waits and
/// do not measure physical movement or pen contact. Missing legacy spans stay nil.
public struct DrawingOperationSpan: Codable, Hashable, Sendable {
  public enum Kind: String, Codable, Hashable, Sendable { case drawing, travel, penRaise, penLower }
  public let kind: Kind
  public let strokeID: StrokeID?
  public let startedNanoseconds: UInt64
  public let endedNanoseconds: UInt64
  public enum Disposition: String, Codable, Hashable, Sendable { case completed, refused, cancelled, ambiguous }
  public let disposition: Disposition

  public init(kind: Kind, strokeID: StrokeID?, startedNanoseconds: UInt64,
    endedNanoseconds: UInt64, disposition: Disposition) {
    precondition(endedNanoseconds >= startedNanoseconds)
    self.kind = kind
    self.strokeID = strokeID
    self.startedNanoseconds = startedNanoseconds
    self.endedNanoseconds = endedNanoseconds
    self.disposition = disposition
  }

  private enum CodingKeys: String, CodingKey {
    case kind, strokeID, startedNanoseconds, endedNanoseconds, disposition
  }
  public init(from decoder: any Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    let start = try values.decode(UInt64.self, forKey: .startedNanoseconds)
    let end = try values.decode(UInt64.self, forKey: .endedNanoseconds)
    guard end >= start else {
      throw DecodingError.dataCorruptedError(forKey: .endedNanoseconds, in: values,
        debugDescription: "operation span ends before it starts")
    }
    self.init(kind: try values.decode(Kind.self, forKey: .kind),
      strokeID: try values.decodeIfPresent(StrokeID.self, forKey: .strokeID),
      startedNanoseconds: start, endedNanoseconds: end,
      disposition: try values.decode(Disposition.self, forKey: .disposition))
  }
}

/// The immutable serialization mapping; progress counts distinguish the
/// dispatched prefix from the not-yet-submitted suffix.
public struct DrawingWireStrokeMapping: Codable, Hashable, Sendable {
  public let strokeID: StrokeID
  public let sourceSegmentRanges: [ClosedRange<Int>]
}
