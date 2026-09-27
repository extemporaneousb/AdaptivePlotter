import Foundation
import PlotterModel

public enum ControllerAxisMetricError: Error, Equatable, Sendable {
  case invalidGeometry
  case sourceMismatch
  case invalidMeasurement
  case incompleteMeasurement
  case incompatibleOppositeEdges
  case invalidConfiguration
  case invalidProposal
  case invalidOutcome
  case unsupportedSchema
}

public enum ControllerMetricAxis: String, Codable, Hashable, Sendable { case x, y }

/// Segment identity is its exact plan/stroke identity and zero-based point-pair index.
public struct LearningFrameMetricEdge: Codable, Hashable, Sendable {
  public let segmentIndex: Int
  public let axis: ControllerMetricAxis
  public let start: Point2<MachineSpace>
  public let end: Point2<MachineSpace>
  public var signedControllerDeltaMM: Double { axis == .x ? end.x - start.x : end.y - start.y }
  public var plannedControllerSpanMM: Double { abs(signedControllerDeltaMM) }
  /// Conservative bound for two controller endpoints encoded at three decimal
  /// places. This is command quantization, separate from ruler uncertainty.
  public var plannedControllerSpanUncertaintyMM: Double { 0.001 }

  public init(segmentIndex: Int, axis: ControllerMetricAxis,
              start: Point2<MachineSpace>, end: Point2<MachineSpace>) throws {
    let delta = axis == .x ? end.x - start.x : end.y - start.y
    let cross = axis == .x ? end.y - start.y : end.x - start.x
    guard (0..<4).contains(segmentIndex), delta.isFinite, delta != 0,
      cross.isFinite, abs(cross) <= Self.roundoff(start, end) else {
      throw ControllerAxisMetricError.invalidGeometry
    }
    self.segmentIndex = segmentIndex; self.axis = axis; self.start = start; self.end = end
  }
  fileprivate static func roundoff(_ a: Point2<MachineSpace>, _ b: Point2<MachineSpace>) -> Double {
    ([1, abs(a.x), abs(a.y), abs(b.x), abs(b.y)].max() ?? 1) * 32 * Double.ulpOfOne
  }
  private enum CodingKeys: String, CodingKey { case segmentIndex, axis, start, end }
  public init(from decoder: any Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    try self.init(segmentIndex: c.decode(Int.self, forKey: .segmentIndex),
      axis: c.decode(ControllerMetricAxis.self, forKey: .axis),
      start: c.decode(Point2<MachineSpace>.self, forKey: .start),
      end: c.decode(Point2<MachineSpace>.self, forKey: .end))
  }
}

/// Planned controller spans with controller completion recorded. This is not a
/// serial-transmission receipt, measured physical geometry, or ink attribution.
public struct LearningFrameMetricGeometry: Codable, Hashable, Sendable {
  public let record: DrawingRunEvidenceRecord
  public var recordID: DrawingEvidenceRecordID { record.recordID }
  public var runID: RunID { record.runID }
  public var planID: ExecutionPlanRevisionID { record.plan.revisionID }
  public var strokeID: StrokeID { record.plan.executionPlan!.strokes[0].logicalStrokeID }
  public var edges: [LearningFrameMetricEdge] { try! Self.extractEdges(record) }
  private init(record: DrawingRunEvidenceRecord) throws {
    _ = try Self.extractEdges(record); self.record = record
  }
  public static func extract(record: DrawingRunEvidenceRecord) throws -> Self { try Self(record: record) }
  private static func extractEdges(_ record: DrawingRunEvidenceRecord) throws -> [LearningFrameMetricEdge] {
    guard record.executionDisposition == .completed, record.requestFrontier == .admitted,
      let plan = record.plan.executionPlan, plan.strokes.count == 1,
      record.executionFrontiers.plannedStrokeCount == 1,
      record.executionFrontiers.commandedStrokeCount == 1,
      record.executionFrontiers.controllerCompletedStrokeCount == 1,
      record.program.source?.kind == "learning-path-drawing-border",
      ["selected-working-region-observed-center-drawing-border-v3",
        "accepted-boundary-10mm-inset-drawing-border-v2", "retained-registration-drawing-border-v1"]
        .contains(record.program.source?.sourceIdentifier ?? ""),
      plan.sourceProgramID == record.program.programID,
      plan.sourceProgramContentHash == record.program.contentHash,
      plan.provenance == record.planningProvenance,
      plan.revisionID == record.plan.revisionID, plan.contentHash == record.plan.contentHash,
      try canonicalDigest(of: plan.placement) == record.placement.contentHash,
      plan.strokes[0].semanticRole == .trainingProbe else { throw ControllerAxisMetricError.invalidGeometry }
    let points = plan.strokes[0].path.points
    guard points.count == 5, points.first == points.last, Set(points.prefix(4)).count == 4 else {
      throw ControllerAxisMetricError.invalidGeometry
    }
    let edges = try (0..<4).map { index in
      let a = points[index], b = points[index + 1]
      let axis: ControllerMetricAxis = abs(b.x - a.x) <= LearningFrameMetricEdge.roundoff(a, b) ? .y : .x
      return try LearningFrameMetricEdge(segmentIndex: index, axis: axis, start: a, end: b)
    }
    guard edges.map(\.axis) == [.y, .x, .y, .x],
      edges[0].signedControllerDeltaMM > 0, edges[1].signedControllerDeltaMM > 0,
      edges[2].signedControllerDeltaMM < 0, edges[3].signedControllerDeltaMM < 0,
      abs(edges[0].signedControllerDeltaMM + edges[2].signedControllerDeltaMM)
        <= LearningFrameMetricEdge.roundoff(points[0], points[2]),
      abs(edges[1].signedControllerDeltaMM + edges[3].signedControllerDeltaMM)
        <= LearningFrameMetricEdge.roundoff(points[0], points[2]) else {
      throw ControllerAxisMetricError.invalidGeometry
    }
    return edges
  }
  private enum CodingKeys: String, CodingKey { case record }
  public init(from decoder: any Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    try self.init(record: c.decode(DrawingRunEvidenceRecord.self, forKey: .record))
  }
}

public struct ControllerAxisRulerMeasurement: Codable, Hashable, Sendable {
  public let segmentIndex: Int
  public let physicalLengthMM: Double
  public let uncertaintyMM: Double
  public init(segmentIndex: Int, physicalLengthMM: Double, uncertaintyMM: Double) throws {
    guard (0..<4).contains(segmentIndex), physicalLengthMM.isFinite, physicalLengthMM > 0,
      uncertaintyMM.isFinite, uncertaintyMM >= 0, physicalLengthMM > uncertaintyMM else {
      throw ControllerAxisMetricError.invalidMeasurement
    }
    self.segmentIndex = segmentIndex; self.physicalLengthMM = physicalLengthMM; self.uncertaintyMM = uncertaintyMM
  }
  private enum CodingKeys: String, CodingKey { case segmentIndex, physicalLengthMM, uncertaintyMM }
  public init(from decoder: any Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    try self.init(segmentIndex: c.decode(Int.self, forKey: .segmentIndex),
      physicalLengthMM: c.decode(Double.self, forKey: .physicalLengthMM),
      uncertaintyMM: c.decode(Double.self, forKey: .uncertaintyMM))
  }
}

/// Durable ruler observations; partial or unconfirmed observations never qualify a proposal.
/// The exact historical Learning package is evidence, never restoration authority.
public struct ControllerAxisMetricMeasurement: Codable, Hashable, Sendable {
  public static let schemaVersion = 1
  public let schemaVersion: Int
  public let measurementID: UUID
  public let recordedAt: Date
  public let geometry: LearningFrameMetricGeometry
  public let sourceCheckpoint: AcceptedLearningPathCheckpoint
  public let edges: [ControllerAxisRulerMeasurement]
  public let method: String
  public let operatorAxisAssociationConfirmed: Bool
  public let supersedesMeasurementID: UUID?
  public var baseline: ControllerCheckpointContext { sourceCheckpoint.machineArtifacts!.controllerContext }

  public init(measurementID: UUID = UUID(), recordedAt: Date, geometry: LearningFrameMetricGeometry,
              sourceCheckpoint: AcceptedLearningPathCheckpoint, edges: [ControllerAxisRulerMeasurement],
              method: String, operatorAxisAssociationConfirmed: Bool, supersedesMeasurementID: UUID? = nil) throws {
    try sourceCheckpoint.validate()
    let record = geometry.record
    guard let stage = sourceCheckpoint.stageFour, let tip = sourceCheckpoint.tipCalibration,
      let machine = sourceCheckpoint.machineArtifacts,
      machine.controllerContext.revision == ControllerCheckpointContext.revision,
      stage.recordID == record.recordID, stage.tipCalibrationRevisionID == record.tipCalibration.acceptedRevisionID,
      stage.paperContactPlane == record.paper.contactPlane,
      tip.registration.acceptedRevisionID == record.tipCalibration.acceptedRevisionID,
      tip.registration.applicability == record.tipCalibration.applicability,
      tip.registration.estimatorRevision == record.tipCalibration.estimatorRevision,
      try tip.registration.drawingEvidenceContentHash().description == record.tipCalibration.registrationEvidenceSHA256,
      record.planningProvenance.registrationContentHash.description == record.tipCalibration.registrationEvidenceSHA256,
      record.planningProvenance.registrationRevisionID.rawValue == tip.registration.acceptedRevisionID.rawValue,
      record.paper.instance == sourceCheckpoint.semanticIdentity.paperInstance,
      record.paper.contactPlane == sourceCheckpoint.semanticIdentity.paperContactPlane,
      machine.coordinateRevision == tip.registration.applicability.machineCoordinateFrame.rawValue else {
      throw ControllerAxisMetricError.sourceMismatch
    }
    guard recordedAt.timeIntervalSinceReferenceDate.isFinite, !edges.isEmpty, edges.count <= 4,
      Set(edges.map(\.segmentIndex)).count == edges.count,
      !method.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      supersedesMeasurementID != measurementID else { throw ControllerAxisMetricError.invalidMeasurement }
    schemaVersion = Self.schemaVersion; self.measurementID = measurementID; self.recordedAt = recordedAt
    self.geometry = geometry; self.sourceCheckpoint = sourceCheckpoint; self.edges = edges.sorted { $0.segmentIndex < $1.segmentIndex }
    self.method = method; self.operatorAxisAssociationConfirmed = operatorAxisAssociationConfirmed
    self.supersedesMeasurementID = supersedesMeasurementID
  }
  private enum CodingKeys: String, CodingKey {
    case schemaVersion, measurementID, recordedAt, geometry, sourceCheckpoint, edges, method,
      operatorAxisAssociationConfirmed, supersedesMeasurementID
  }
  public init(from decoder: any Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    guard try c.decode(Int.self, forKey: .schemaVersion) == Self.schemaVersion else { throw ControllerAxisMetricError.unsupportedSchema }
    try self.init(measurementID: c.decode(UUID.self, forKey: .measurementID),
      recordedAt: c.decode(Date.self, forKey: .recordedAt), geometry: c.decode(LearningFrameMetricGeometry.self, forKey: .geometry),
      sourceCheckpoint: c.decode(AcceptedLearningPathCheckpoint.self, forKey: .sourceCheckpoint),
      edges: c.decode([ControllerAxisRulerMeasurement].self, forKey: .edges), method: c.decode(String.self, forKey: .method),
      operatorAxisAssociationConfirmed: c.decode(Bool.self, forKey: .operatorAxisAssociationConfirmed),
      supersedesMeasurementID: c.decodeIfPresent(UUID.self, forKey: .supersedesMeasurementID))
  }
}

/// Conservative union of compatible opposite-edge intervals. Does not measure
/// orthogonality, backlash, or variation outside this frame.
public struct ControllerAxisMetricFactor: Codable, Hashable, Sendable {
  public let estimate: Double
  public let lowerBound: Double
  public let upperBound: Double
  public init(estimate: Double, lowerBound: Double, upperBound: Double) throws {
    guard estimate.isFinite, lowerBound.isFinite, upperBound.isFinite, lowerBound > 0,
      lowerBound <= estimate, estimate <= upperBound else { throw ControllerAxisMetricError.invalidMeasurement }
    self.estimate = estimate; self.lowerBound = lowerBound; self.upperBound = upperBound
  }
  public static func derive(axis: ControllerMetricAxis, measurement: ControllerAxisMetricMeasurement) throws -> Self {
    guard measurement.operatorAxisAssociationConfirmed, measurement.edges.count == 4 else {
      throw ControllerAxisMetricError.incompleteMeasurement
    }
    let values = measurement.edges.filter { measurement.geometry.edges[$0.segmentIndex].axis == axis }
    guard values.count == 2 else { throw ControllerAxisMetricError.incompleteMeasurement }
    guard values.allSatisfy({
      let edge = measurement.geometry.edges[$0.segmentIndex]
      return edge.plannedControllerSpanMM > edge.plannedControllerSpanUncertaintyMM
    }) else { throw ControllerAxisMetricError.invalidMeasurement }
    let intervals = values.map { value -> (Double, Double, Double) in
      let edge = measurement.geometry.edges[value.segmentIndex]
      let span = edge.plannedControllerSpanMM
      return ((value.physicalLengthMM - value.uncertaintyMM) / (span + edge.plannedControllerSpanUncertaintyMM),
              (value.physicalLengthMM + value.uncertaintyMM) / (span - edge.plannedControllerSpanUncertaintyMM),
              value.physicalLengthMM / span)
    }
    guard max(intervals[0].0, intervals[1].0) <= min(intervals[0].1, intervals[1].1) else {
      throw ControllerAxisMetricError.incompatibleOppositeEdges
    }
    return try Self(estimate: (intervals[0].2 + intervals[1].2) / 2,
      lowerBound: min(intervals[0].0, intervals[1].0), upperBound: max(intervals[0].1, intervals[1].1))
  }
  private enum CodingKeys: String, CodingKey { case estimate, lowerBound, upperBound }
  public init(from decoder: any Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    try self.init(estimate: c.decode(Double.self, forKey: .estimate), lowerBound: c.decode(Double.self, forKey: .lowerBound),
      upperBound: c.decode(Double.self, forKey: .upperBound))
  }
}

public struct ControllerAxisCalibrationProposal: Codable, Hashable, Sendable {
  public static let schemaVersion = 1
  public let schemaVersion: Int
  public let proposalID: UUID
  public let measurementID: UUID
  public let baseline: ControllerCheckpointContext
  public let oldMachineGeometry: MachineGeometryIdentity
  public let proposedMachineGeometry: MachineGeometryIdentity
  public let xFactor: ControllerAxisMetricFactor
  public let yFactor: ControllerAxisMetricFactor
  public var oldXStepsPerMM: Double { try! Self.stepsPerMM(axis: .x, context: baseline) }
  public var oldYStepsPerMM: Double { try! Self.stepsPerMM(axis: .y, context: baseline) }
  public var proposedXStepsPerMM: Double { Double(Self.formatted(oldXStepsPerMM / xFactor.estimate))! }
  public var proposedYStepsPerMM: Double { Double(Self.formatted(oldYStepsPerMM / yFactor.estimate))! }
  public var commands: [String] { ["$100=" + Self.formatted(proposedXStepsPerMM), "$101=" + Self.formatted(proposedYStepsPerMM)] }
  public init(measurement: ControllerAxisMetricMeasurement, proposalID: UUID = UUID(),
              proposedMachineGeometry: MachineGeometryIdentity = MachineGeometryIdentity()) throws {
    try self.init(proposalID: proposalID, measurementID: measurement.measurementID, baseline: measurement.baseline,
      oldMachineGeometry: measurement.sourceCheckpoint.semanticIdentity.machineGeometry,
      proposedMachineGeometry: proposedMachineGeometry, xFactor: .derive(axis: .x, measurement: measurement),
      yFactor: .derive(axis: .y, measurement: measurement))
  }
  private init(proposalID: UUID, measurementID: UUID, baseline: ControllerCheckpointContext,
               oldMachineGeometry: MachineGeometryIdentity, proposedMachineGeometry: MachineGeometryIdentity,
               xFactor: ControllerAxisMetricFactor, yFactor: ControllerAxisMetricFactor) throws {
    let x = try Self.stepsPerMM(axis: .x, context: baseline) / xFactor.estimate
    let y = try Self.stepsPerMM(axis: .y, context: baseline) / yFactor.estimate
    guard oldMachineGeometry != proposedMachineGeometry, x.isFinite, y.isFinite,
      (Double(Self.formatted(x)) ?? 0) > 0, (Double(Self.formatted(y)) ?? 0) > 0 else { throw ControllerAxisMetricError.invalidProposal }
    schemaVersion = Self.schemaVersion; self.proposalID = proposalID; self.measurementID = measurementID
    self.baseline = baseline; self.oldMachineGeometry = oldMachineGeometry; self.proposedMachineGeometry = proposedMachineGeometry
    self.xFactor = xFactor; self.yFactor = yFactor
  }
  public func validates(measurement: ControllerAxisMetricMeasurement) -> Bool {
    (try? Self(measurement: measurement, proposalID: proposalID, proposedMachineGeometry: proposedMachineGeometry)) == self
  }
  public func validatesReadback(_ context: ControllerCheckpointContext) -> Bool {
    guard baseline.comparison(with: context).differences.allSatisfy({ $0.field == .configuration }),
      (try? Self.stepsPerMM(axis: .x, context: context)) == proposedXStepsPerMM,
      (try? Self.stepsPerMM(axis: .y, context: context)) == proposedYStepsPerMM else { return false }
    func unrelated(_ values: [String]) -> [String] {
      values.filter { value in
        let key = value.split(separator: "=", omittingEmptySubsequences: false).first
        return key != "$100" && key != "$101"
      }
    }
    return unrelated(baseline.configuration) == unrelated(context.configuration)
  }
  public static func stepsPerMM(axis: ControllerMetricAxis, context: ControllerCheckpointContext) throws -> Double {
    let key = axis == .x ? "$100" : "$101"
    let entries = context.configuration.filter { $0.split(separator: "=", omittingEmptySubsequences: false).first == Substring(key) }
    guard context.revision == ControllerCheckpointContext.revision, entries.count == 1 else { throw ControllerAxisMetricError.invalidConfiguration }
    let parts = entries[0].split(separator: "=", omittingEmptySubsequences: false)
    guard parts.count == 2, let value = Double(parts[1]), value.isFinite, value > 0 else { throw ControllerAxisMetricError.invalidConfiguration }
    return value
  }
  private static func formatted(_ value: Double) -> String { String(format: "%.3f", locale: Locale(identifier: "en_US_POSIX"), value) }
  private enum CodingKeys: String, CodingKey { case schemaVersion, proposalID, measurementID, baseline, oldMachineGeometry, proposedMachineGeometry, xFactor, yFactor }
  public init(from decoder: any Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    guard try c.decode(Int.self, forKey: .schemaVersion) == Self.schemaVersion else { throw ControllerAxisMetricError.unsupportedSchema }
    try self.init(proposalID: c.decode(UUID.self, forKey: .proposalID), measurementID: c.decode(UUID.self, forKey: .measurementID),
      baseline: c.decode(ControllerCheckpointContext.self, forKey: .baseline),
      oldMachineGeometry: c.decode(MachineGeometryIdentity.self, forKey: .oldMachineGeometry),
      proposedMachineGeometry: c.decode(MachineGeometryIdentity.self, forKey: .proposedMachineGeometry),
      xFactor: c.decode(ControllerAxisMetricFactor.self, forKey: .xFactor), yFactor: c.decode(ControllerAxisMetricFactor.self, forKey: .yFactor))
  }
}

public struct ControllerAxisCalibrationCommandTransfer: Codable, Hashable, Sendable {
  public let command: String
  public let writtenByteCount: Int?
  public let writeError: String?
  public let acknowledgement: String?
  public let received: [MachineLinkReadReceipt]
  public init(command: String, writtenByteCount: Int?, writeError: String? = nil,
              acknowledgement: String? = nil, received: [MachineLinkReadReceipt] = []) throws {
    guard Self.validCommand(command), writtenByteCount.map({ $0 >= 0 && $0 <= command.utf8.count + 1 }) ?? true,
      writeError.map({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) ?? true,
      acknowledgement.map({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) ?? true,
      acknowledgement != "ok" || (writtenByteCount == command.utf8.count + 1 && writeError == nil)
    else { throw ControllerAxisMetricError.invalidOutcome }
    self.command = command; self.writtenByteCount = writtenByteCount; self.writeError = writeError
    self.acknowledgement = acknowledgement; self.received = received
  }
  fileprivate static func validCommand(_ command: String) -> Bool {
    let parts = command.split(separator: "=", omittingEmptySubsequences: false)
    guard parts.count == 2, ["$100", "$101"].contains(String(parts[0])),
      !command.contains("\n"), !command.contains("\r"), let value = Double(parts[1]), value.isFinite, value > 0 else { return false }
    return true
  }
  private enum CodingKeys: String, CodingKey { case command, writtenByteCount, writeError, acknowledgement, received }
  public init(from decoder: any Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    try self.init(command: c.decode(String.self, forKey: .command), writtenByteCount: c.decodeIfPresent(Int.self, forKey: .writtenByteCount),
      writeError: c.decodeIfPresent(String.self, forKey: .writeError), acknowledgement: c.decodeIfPresent(String.self, forKey: .acknowledgement),
      received: c.decode([MachineLinkReadReceipt].self, forKey: .received))
  }
}

public enum ControllerAxisCalibrationStatus: String, Codable, Hashable, Sendable { case refused, applied, ambiguous, cancelled }
public struct ControllerAxisCalibrationOutcome: Codable, Hashable, Sendable {
  public let status: ControllerAxisCalibrationStatus
  public let attemptedCommands: [String]
  public let acknowledgedCommands: [String]
  public let verifiedContext: ControllerCheckpointContext?
  public let reason: String
  public let baselineProbe: PassiveProbeResult?
  public let verificationProbe: PassiveProbeResult?
  public let commandTransfers: [ControllerAxisCalibrationCommandTransfer]
  public init(status: ControllerAxisCalibrationStatus, attemptedCommands: [String] = [],
              acknowledgedCommands: [String] = [], verifiedContext: ControllerCheckpointContext? = nil,
              reason: String, baselineProbe: PassiveProbeResult? = nil, verificationProbe: PassiveProbeResult? = nil,
              commandTransfers: [ControllerAxisCalibrationCommandTransfer] = []) throws {
    guard !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      attemptedCommands.count <= 2, Set(attemptedCommands).count == attemptedCommands.count,
      attemptedCommands.allSatisfy(ControllerAxisCalibrationCommandTransfer.validCommand),
      zip(attemptedCommands, ["$100=", "$101="]).allSatisfy({ $0.hasPrefix($1) }),
      Array(attemptedCommands.prefix(acknowledgedCommands.count)) == acknowledgedCommands,
      acknowledgedCommands.count <= commandTransfers.count,
      commandTransfers.prefix(acknowledgedCommands.count).allSatisfy({
        $0.writtenByteCount == $0.command.utf8.count + 1 && $0.writeError == nil && $0.acknowledgement == "ok"
      }),
      commandTransfers.count <= attemptedCommands.count,
      zip(commandTransfers, attemptedCommands).allSatisfy({ $0.command == $1 }),
      (status != .refused && status != .cancelled) || attemptedCommands.isEmpty,
      status != .applied || (attemptedCommands.count == 2 && acknowledgedCommands == attemptedCommands
        && commandTransfers.count == 2 && verifiedContext != nil && baselineProbe != nil && verificationProbe != nil
        && (try? ControllerCheckpointContext(probe: baselineProbe!)) != nil),
      verifiedContext == nil || verificationProbe == nil || (try? ControllerCheckpointContext(probe: verificationProbe!)) == verifiedContext
    else { throw ControllerAxisMetricError.invalidOutcome }
    self.status = status; self.attemptedCommands = attemptedCommands; self.acknowledgedCommands = acknowledgedCommands
    self.verifiedContext = verifiedContext; self.reason = reason; self.baselineProbe = baselineProbe
    self.verificationProbe = verificationProbe; self.commandTransfers = commandTransfers
  }
  private enum CodingKeys: String, CodingKey { case status, attemptedCommands, acknowledgedCommands, verifiedContext, reason, baselineProbe, verificationProbe, commandTransfers }
  public init(from decoder: any Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    try self.init(status: c.decode(ControllerAxisCalibrationStatus.self, forKey: .status),
      attemptedCommands: c.decode([String].self, forKey: .attemptedCommands), acknowledgedCommands: c.decode([String].self, forKey: .acknowledgedCommands),
      verifiedContext: c.decodeIfPresent(ControllerCheckpointContext.self, forKey: .verifiedContext), reason: c.decode(String.self, forKey: .reason),
      baselineProbe: c.decodeIfPresent(PassiveProbeResult.self, forKey: .baselineProbe), verificationProbe: c.decodeIfPresent(PassiveProbeResult.self, forKey: .verificationProbe),
      commandTransfers: c.decode([ControllerAxisCalibrationCommandTransfer].self, forKey: .commandTransfers))
  }
}
