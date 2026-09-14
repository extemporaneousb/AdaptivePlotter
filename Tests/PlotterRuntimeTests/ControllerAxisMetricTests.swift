import Foundation
import PlotterModel
import Testing
@testable import PlotterRuntime

@Suite("Independent controller axis metric")
struct ControllerAxisMetricTests {
  @Test("Exact fractional frame spans survive round trip without a wire or ink claim")
  func exactGeometry() throws {
    let fixture = try AxisMetricFixture()
    let geometry = try LearningFrameMetricGeometry.extract(record: fixture.record)
    #expect(geometry.edges.map(\.axis) == [.y, .x, .y, .x])
    #expect(geometry.edges.map(\.signedControllerDeltaMM) == [60.125, 40.375, -60.125, -40.375])
    #expect(geometry.record.evidenceDisposition == .visionUnclear)
    #expect(try JSONDecoder().decode(LearningFrameMetricGeometry.self,
      from: JSONEncoder().encode(geometry)) == geometry)
  }

  @Test("Line, skewed frame, wrong source, and legacy plan references cannot become metric geometry")
  func rejectsUnrelatedGeometry() throws {
    for invalid in ["line", "skew", "source"] {
      let fixture = try AxisMetricFixture(invalidGeometry: invalid)
      #expect(throws: ControllerAxisMetricError.invalidGeometry) {
        try LearningFrameMetricGeometry.extract(record: fixture.record)
      }
    }
    let fixture = try AxisMetricFixture()
    var record = try object(fixture.record)
    record["schemaVersion"] = 1
    var plan = try #require(record["plan"] as? [String: Any])
    plan.removeValue(forKey: "executionPlan"); record["plan"] = plan
    let legacy = try decode(DrawingRunEvidenceRecord.self, record)
    #expect(throws: ControllerAxisMetricError.invalidGeometry) {
      try LearningFrameMetricGeometry.extract(record: legacy)
    }
  }

  @Test("Separate measured axis factors correct existing unequal firmware settings once")
  func proposalAndRoundTrip() throws {
    let measurement = try AxisMetricFixture().measurement()
    let proposal = try ControllerAxisCalibrationProposal(measurement: measurement)
    #expect(abs(proposal.xFactor.estimate - 1.002) < 1e-12)
    #expect(abs(proposal.yFactor.estimate - 0.783) < 1e-12)
    #expect(proposal.oldXStepsPerMM == 40.18235)
    #expect(proposal.oldYStepsPerMM == 45.091)
    #expect(proposal.commands == ["$100=40.102", "$101=57.587"])
    #expect(proposal.validates(measurement: measurement))
    #expect(try JSONDecoder().decode(ControllerAxisMetricMeasurement.self,
      from: JSONEncoder().encode(measurement)) == measurement)
    #expect(try JSONDecoder().decode(ControllerAxisCalibrationProposal.self,
      from: JSONEncoder().encode(proposal)) == proposal)
    let readback = try ControllerCheckpointContext(probe: metricProbe(position: MachinePosition(x: 0, y: 0),
      configuration: proposal.commands + ["$110=900.000"]))
    #expect(proposal.validatesReadback(readback))
    #expect(!proposal.validatesReadback(measurement.baseline))
    let otherChanged = try ControllerCheckpointContext(probe: metricProbe(position: MachinePosition(x: 0, y: 0),
      configuration: proposal.commands + ["$110=901.000"]))
    #expect(!proposal.validatesReadback(otherChanged))
  }

  @Test("Partial, unconfirmed, and inconsistent opposite measurements remain unqualified")
  func provisionalAndMismatch() throws {
    let fixture = try AxisMetricFixture()
    let partial = try fixture.measurement(indices: [0, 1])
    #expect(partial.edges.count == 2)
    #expect(throws: ControllerAxisMetricError.incompleteMeasurement) {
      try ControllerAxisCalibrationProposal(measurement: partial)
    }
    let unconfirmed = try fixture.measurement(confirmed: false)
    #expect(throws: ControllerAxisMetricError.incompleteMeasurement) {
      try ControllerAxisCalibrationProposal(measurement: unconfirmed)
    }
    let mismatch = try fixture.measurement(lastEdgeOffset: 1)
    #expect(throws: ControllerAxisMetricError.incompatibleOppositeEdges) {
      try ControllerAxisCalibrationProposal(measurement: mismatch)
    }
  }

  @Test("Uncertainty is explicit and finite on construction and decode")
  func invalidNumbers() throws {
    for uncertainty in [-0.1, Double.infinity, Double.nan, 10] {
      #expect(throws: ControllerAxisMetricError.invalidMeasurement) {
        try ControllerAxisRulerMeasurement(segmentIndex: 0, physicalLengthMM: 10, uncertaintyMM: uncertainty)
      }
    }
    let row = try ControllerAxisRulerMeasurement(segmentIndex: 0, physicalLengthMM: 10, uncertaintyMM: 0.1)
    var payload = try object(row); payload.removeValue(forKey: "uncertaintyMM")
    #expect(throws: (any Error).self) { try decode(ControllerAxisRulerMeasurement.self, payload) }
    payload["uncertaintyMM"] = -1
    #expect(throws: ControllerAxisMetricError.invalidMeasurement) { try decode(ControllerAxisRulerMeasurement.self, payload) }
  }

  @Test("Historical Stage Four and paper identities cannot be substituted on decode")
  func sourceBinding() throws {
    let measurement = try AxisMetricFixture().measurement()
    var payload = try object(measurement)
    var checkpoint = try #require(payload["sourceCheckpoint"] as? [String: Any])
    var stage = try #require(checkpoint["stageFour"] as? [String: Any])
    stage["recordID"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(DrawingEvidenceRecordID()))
    checkpoint["stageFour"] = stage; payload["sourceCheckpoint"] = checkpoint
    #expect(throws: ControllerAxisMetricError.sourceMismatch) { try decode(ControllerAxisMetricMeasurement.self, payload) }
    payload = try object(measurement); payload["schemaVersion"] = 99
    #expect(throws: ControllerAxisMetricError.unsupportedSchema) { try decode(ControllerAxisMetricMeasurement.self, payload) }
  }

  @Test("Command quantization remains separate from ruler uncertainty and widens factor intervals")
  func commandQuantization() throws {
    let fixture = try AxisMetricFixture()
    let geometry = try LearningFrameMetricGeometry.extract(record: fixture.record)
    let measurement = try ControllerAxisMetricMeasurement(recordedAt: Date(), geometry: geometry,
      sourceCheckpoint: fixture.checkpoint, edges: geometry.edges.map {
        try ControllerAxisRulerMeasurement(segmentIndex: $0.segmentIndex,
          physicalLengthMM: $0.plannedControllerSpanMM, uncertaintyMM: 0)
      }, method: "Synthetic exact ruler; command quantization still present", operatorAxisAssociationConfirmed: true)
    let proposal = try ControllerAxisCalibrationProposal(measurement: measurement)
    #expect(geometry.edges.allSatisfy { $0.plannedControllerSpanUncertaintyMM == 0.001 })
    #expect(proposal.xFactor.lowerBound < 1 && proposal.xFactor.upperBound > 1)
    #expect(proposal.yFactor.lowerBound < 1 && proposal.yFactor.upperBound > 1)
  }

  @Test("Missing, duplicate, and nonpositive firmware settings cannot derive a correction")
  func malformedSettings() throws {
    for configuration in [["$100=40"], ["$100=40", "$101=0"], ["$100=40", "$101=45", "$101=46"], ["$100=nan", "$101=45"]] {
      let context = try ControllerCheckpointContext(probe: metricProbe(position: MachinePosition(x: 0, y: 0), configuration: configuration))
      #expect(throws: ControllerAxisMetricError.invalidConfiguration) {
        _ = try ControllerAxisCalibrationProposal.stepsPerMM(axis: .x, context: context)
        _ = try ControllerAxisCalibrationProposal.stepsPerMM(axis: .y, context: context)
      }
    }
  }

  @Test("Transfer counts and partial settings failures retain distinct attempted, written and acknowledged facts")
  func transferEvidence() throws {
    for count in [-1, 1000] {
      #expect(throws: ControllerAxisMetricError.invalidOutcome) {
        try ControllerAxisCalibrationCommandTransfer(command: "$100=40.1", writtenByteCount: count)
      }
    }
    #expect(throws: ControllerAxisMetricError.invalidOutcome) {
      try ControllerAxisCalibrationCommandTransfer(command: "$100=40\n$X", writtenByteCount: nil)
    }
    let first = try ControllerAxisCalibrationCommandTransfer(command: "$100=40.1", writtenByteCount: 10,
      acknowledgement: "ok", received: [MachineLinkReadReceipt(bytes: Data("ok\r\n".utf8), receivedAtMonotonicNanoseconds: 12)])
    let second = try ControllerAxisCalibrationCommandTransfer(command: "$101=57.5", writtenByteCount: 3, writeError: "disconnect")
    let outcome = try ControllerAxisCalibrationOutcome(status: .ambiguous,
      attemptedCommands: [first.command, second.command], acknowledgedCommands: [first.command],
      reason: "First acknowledged, second partial transfer; calibration unavailable", commandTransfers: [first, second])
    #expect(try JSONDecoder().decode(ControllerAxisCalibrationOutcome.self,
      from: JSONEncoder().encode(outcome)) == outcome)
    #expect(throws: ControllerAxisMetricError.invalidOutcome) {
      try ControllerAxisCalibrationOutcome(status: .cancelled, attemptedCommands: [first.command], reason: "Cancelled after write")
    }
    #expect(throws: ControllerAxisMetricError.invalidOutcome) {
      try ControllerAxisCalibrationCommandTransfer(command: first.command, writtenByteCount: 2, acknowledgement: "ok")
    }
    #expect(throws: ControllerAxisMetricError.invalidOutcome) {
      try ControllerAxisCalibrationOutcome(status: .applied,
        attemptedCommands: [first.command, second.command], acknowledgedCommands: [first.command, second.command],
        reason: "Unsupported claim without readback and transfers")
    }
    var payload = try object(second); payload["writtenByteCount"] = -1
    #expect(throws: ControllerAxisMetricError.invalidOutcome) { try decode(ControllerAxisCalibrationCommandTransfer.self, payload) }
  }
}

private func object<T: Encodable>(_ value: T) throws -> [String: Any] {
  try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as? [String: Any])
}
private func decode<T: Decodable>(_ type: T.Type, _ object: [String: Any]) throws -> T {
  try JSONDecoder().decode(type, from: JSONSerialization.data(withJSONObject: object))
}

struct AxisMetricFixture {
  let record: DrawingRunEvidenceRecord
  let checkpoint: AcceptedLearningPathCheckpoint
  init(invalidGeometry: String? = nil) throws {
    let tipFixture = try TipAuthorityFixture()
    let registration = try tipFixture.registration()
    let hash = try registration.drawingEvidenceContentHash()
    let provenance = DrawingPlanningProvenance(modelRevisionID: DrawingModelRevisionID(registration.acceptedRevisionID.rawValue),
      modelContentHash: hash, registrationRevisionID: DrawingRegistrationRevisionID(registration.acceptedRevisionID.rawValue), registrationContentHash: hash)
    var points = try [(0.0, 0.0), (0, 60.125), (40.375, 60.125), (40.375, 0), (0, 0)]
      .map { try Point2<FieldSpace>(x: $0.0, y: $0.1) }
    if invalidGeometry == "line" { points = Array(points.prefix(2)) }
    if invalidGeometry == "skew" { points[1] = try Point2(x: 1, y: 60.125) }
    let program = try DrawingProgram(id: ProgramID(), fieldExtent: Size2(width: 40.375, height: 60.125),
      strokes: [LogicalStroke(id: StrokeID(), path: Polyline(points: points),
        style: StrokeStyle(nominalLineWidth: 0.4, penProfileID: PenProfileID()), semanticRole: .trainingProbe, ordering: 0)],
      source: DrawingSourceProvenance(kind: invalidGeometry == "source" ? "portrait" : "learning-path-drawing-border",
        sourceIdentifier: "accepted-boundary-10mm-inset-drawing-border-v2"))
    let placement = try DrawingPlacement(fieldAnchor: Point2(x: 0, y: 0), machineAnchor: Point2(x: 0, y: 0), uniformScale: 1)
    let plan = try DrawingPlanner.plan(program: program, placement: placement,
      drawableRegion: DrawableMachineRegion(bounds: AxisAlignedBounds(minX: 0, minY: 0, maxX: 100, maxY: 100)), provenance: provenance)
    let paper = PaperRevisionContext(instance: PaperInstanceRevision(), contactPlane: tipFixture.paper)
    record = try DrawingRunEvidenceRecord(runID: RunID(), requestID: UUID(), role: .evaluationHoldout,
      evidenceDisposition: .visionUnclear, requestFrontier: .admitted,
      executionFrontiers: DrawingRunExecutionFrontiers(plannedStrokeCount: 1, commandedStrokeCount: 1,
        controllerCompletedStrokeCount: 1, inkVerifiedStrokeCount: 0), executionDisposition: .completed,
      program: DrawingProgramEvidenceReference(program: program), placement: DrawingPlacementEvidenceReference(placementID: UUID(), placement: placement),
      plan: DrawingExecutionPlanEvidenceReference(plan: plan), planningProvenance: provenance,
      tipCalibration: DrawingTipCalibrationEvidenceReference(acceptedRevisionID: registration.acceptedRevisionID,
        registrationEvidenceSHA256: hash.description, applicability: registration.applicability, estimatorRevision: registration.estimatorRevision),
      paper: paper, observation: .notAttempted(.frameEvidenceUnavailable), recordedAt: RuntimeTimestamp(monotonicNanoseconds: 1000))
    checkpoint = try AcceptedLearningPathCheckpoint(semanticIdentity: LearningPathSemanticIdentity(machineGeometry: tipFixture.machineGeometry,
      toolAssembly: tipFixture.toolAssembly, penContactProfile: tipFixture.contactProfile,
      paperInstance: paper.instance, paperContactPlane: paper.contactPlane, cameraMountRevision: tipFixture.mountRevision,
      cameraReframingRevision: tipFixture.optical.reframingRevision),
      machineArtifacts: metricCheckpoint(), tipCalibration: AcceptedTipCalibrationCheckpoint(registration: registration,
        acceptanceEvent: TipCalibrationAcceptanceEvent(acceptedRevisionID: registration.acceptedRevisionID,
          timestamp: registration.acceptedAt, actor: "synthetic metric fixture")),
      stageFour: AcceptedStageFourCheckpoint(recordID: record.recordID,
        tipCalibrationRevisionID: registration.acceptedRevisionID, paperContactPlane: paper.contactPlane))
  }
  func measurement(indices: [Int] = [0, 1, 2, 3], confirmed: Bool = true, lastEdgeOffset: Double = 0) throws -> ControllerAxisMetricMeasurement {
    let geometry = try LearningFrameMetricGeometry.extract(record: record)
    return try ControllerAxisMetricMeasurement(recordedAt: Date(timeIntervalSince1970: 1000), geometry: geometry,
      sourceCheckpoint: checkpoint, edges: indices.map { index in
        let edge = geometry.edges[index]
        return try ControllerAxisRulerMeasurement(segmentIndex: index,
          physicalLengthMM: edge.plannedControllerSpanMM * (edge.axis == .x ? 1.002 : 0.783) + (index == 3 ? lastEdgeOffset : 0), uncertaintyMM: 0.1)
      }, method: "Synthetic ruler fixture; not physical evidence", operatorAxisAssociationConfirmed: confirmed)
  }
}

private func metricCheckpoint() throws -> AcceptedMachineArtifactCheckpoint {
  let sessionID = UUID()
  let coordinateRevision: UInt64 = 11
  let attemptID = ExerciseAttemptID()
  let revisionID = LearningArtifactRevisionID()
  let evidence = try BoundarySideAttemptEvidence(
    attemptID: attemptID,
    direction: .positiveX,
    controllerSessionID: sessionID,
    coordinateRevision: coordinateRevision,
    ownerID: BoundaryMotionOwnerID(),
    stopCapabilityID: UUID(),
    stopIntent: .operatorStop,
    finalPosition: MachinePosition(x: 10, y: 0),
    disposition: .succeeded
  )
  let compatibility = BoundaryNumericCompatibility(
    direction: .positiveX,
    controllerSessionID: sessionID,
    coordinateRevision: coordinateRevision,
    numericEstimatorRevision: "boundary-machine-coordinate-v1"
  ).attemptCompatibility
  var history = try ExerciseAttemptHistory<BoundarySideAttemptEvidence>(
    compatibility: compatibility
  )
  try history.record(
    ExerciseAttempt(
      id: attemptID,
      disposition: .succeeded,
      compatibility: compatibility,
      acceptedSequence: 1,
      value: evidence
    )
  )
  let aggregate = try BoundarySideAggregate(
    direction: .positiveX,
    revisionID: revisionID,
    history: history
  )
  var progress = PairedBoundaryProgress()
  try progress.accept(.positiveX, revisionID: revisionID)
  let revision = LearningArtifactRevision(
    id: revisionID,
    kind: .boundarySideAggregate(.positiveX),
    attemptID: attemptID,
    disposition: .succeeded,
    state: .current
  )
  let position = try MachinePosition(x: 10, y: 0)
  return try AcceptedMachineArtifactCheckpoint(
    controllerContext: ControllerCheckpointContext(probe: metricProbe(position: position)),
    machinePositionAtSave: position,
    controllerSessionID: sessionID,
    coordinateRevision: coordinateRevision,
    acceptedAttemptSequence: 1,
    pairedBoundaryProgress: progress,
    acceptedBoundaryEvidence: [evidence],
    boundarySideAggregates: [aggregate],
    estimatedMachineCenter: nil,
    learnedLocalCoordinateFrame: nil,
    centerArrivalPosition: nil,
    acceptedRevisions: [revision]
  )
}

private func metricProbe(
  position: MachinePosition,
  configuration: [String] = ["$100=40.18235", "$101=45.09100", "$110=900.000"],
  parserState: [String] = ["[GC:G0 G54 G17 G21 G90 G94 M5 M9 T0 F0 S0]"]
) -> PassiveProbeResult {
  let link = MachineLinkDescriptor(
    identifier: "/dev/cu.checkpoint-fixture",
    displayName: "Checkpoint Fixture",
    bsdPath: "/dev/cu.checkpoint-fixture",
    transport: .bsdSerial
  )
  let reports: [(PassiveQuery, [String])] = [
    (.buildInfo, ["[VER:1.1h.20200101:checkpoint]"]),
    (.parserState, parserState),
    (
      .status,
      [String(format: "<Idle|MPos:%.3f,%.3f,0.000>", position.point.x, position.point.y)]
    ),
    (.configuration, configuration),
    (.coordinateOffsets, ["[G54:0.000,0.000,0.000]", "[G92:0.000,0.000,0.000]"]),
  ]
  let exchanges = reports.map { query, report in
    let text = query == .status ? report : report + ["ok"]
    return PassiveProbeExchange(
      query: query,
      commandID: UUID(),
      rawIO: [],
      lines: text.map { GRBLParser.parseLine(Data($0.utf8)) },
      completed: true,
      blocker: nil
    )
  }
  return PassiveProbeResult(
    link: link,
    startedAt: RuntimeTimestamp(monotonicNanoseconds: 1),
    completedAt: RuntimeTimestamp(monotonicNanoseconds: 2),
    exchanges: exchanges,
    blockers: []
  )
}
