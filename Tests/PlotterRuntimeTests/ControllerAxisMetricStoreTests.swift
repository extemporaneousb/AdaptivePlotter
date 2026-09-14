import CryptoKit
import Foundation
import PlotterModel
import Testing
@testable import PlotterRuntime

@Suite("Durable independent axis calibration evidence")
struct ControllerAxisMetricStoreTests {
  @Test("Exact measurement retries preserve bytes; conflicting identities and wrong-frame corrections reject")
  func measurementIdentity() async throws {
    let disk = AxisMetricDisk(); defer { disk.remove() }
    let fixture = try AxisMetricFixture(), other = try AxisMetricFixture()
    let measurement = try fixture.measurement()
    try await disk.store.append(fixture.record)
    let first = try await disk.store.appendAxisMetricMeasurement(measurement)
    let bytes = try Data(contentsOf: disk.url)
    #expect(first.revision == 1)
    #expect(try await disk.store.appendAxisMetricMeasurement(measurement) == first)
    #expect(try Data(contentsOf: disk.url) == bytes)
    let conflicting = try copy(measurement, method: "Different ruler report with reused identity")
    await #expect(throws: (any Error).self) { try await disk.store.appendAxisMetricMeasurement(conflicting) }
    #expect(try Data(contentsOf: disk.url) == bytes)
    try await disk.store.append(other.record)
    let wrongFrame = try copy(other.measurement(), measurementID: UUID(), supersedes: measurement.measurementID)
    await #expect(throws: (any Error).self) { try await disk.store.appendAxisMetricMeasurement(wrongFrame) }
    let corrected = try copy(measurement, measurementID: UUID(), method: "Corrected same-frame measurement", supersedes: measurement.measurementID)
    let retained = try await disk.store.appendAxisMetricMeasurement(corrected)
    #expect(retained.axisMetricMeasurements == [measurement, corrected])
    #expect(retained.revision == 2)
    #expect(try disk.snapshot().axisMetricMeasurements.map(\.sourceCheckpoint) == [fixture.checkpoint, fixture.checkpoint])
  }

  @Test("Preparation must rederive from the retained measurement and interrupted preparation survives restart")
  func preparedWithoutTerminal() async throws {
    let disk = AxisMetricDisk(); defer { disk.remove() }
    let fixture = try AxisMetricFixture(), measurement = try fixture.measurement()
    let proposal = try ControllerAxisCalibrationProposal(measurement: measurement)
    let attempt = ControllerAxisCalibrationAttempt(proposal: proposal, recordedAt: Date(timeIntervalSince1970: 1001))
    try await disk.store.append(fixture.record)
    await #expect(throws: (any Error).self) { try await disk.store.prepareAxisCalibration(attempt) }
    try await disk.store.appendAxisMetricMeasurement(measurement)
    var object = try jsonObject(proposal)
    object["xFactor"] = ["estimate": 1.1, "lowerBound": 1.09, "upperBound": 1.11]
    let altered = try JSONDecoder().decode(ControllerAxisCalibrationProposal.self,
      from: JSONSerialization.data(withJSONObject: object))
    #expect(!altered.validates(measurement: measurement))
    await #expect(throws: (any Error).self) {
      try await disk.store.prepareAxisCalibration(ControllerAxisCalibrationAttempt(proposal: altered))
    }
    let prepared = try await disk.store.prepareAxisCalibration(attempt)
    #expect(try await disk.store.prepareAxisCalibration(attempt) == prepared)
    let restarted = DrawingRunEvidenceStore(fileURL: disk.url)
    guard case .loaded(let restored) = restarted.loadSnapshot() else {
      Issue.record("Prepared calibration must survive restart"); return
    }
    #expect(restored == prepared)
    #expect(restored.axisCalibrationAttempts == [attempt])
    #expect(restored.axisCalibrationTerminals.isEmpty)
    #expect(restored.axisMetricMeasurements[0].sourceCheckpoint == fixture.checkpoint)
    #expect(restored.axisMetricMeasurements[0].geometry.record == fixture.record)
    #expect(restored.revision == 1)
  }

  @Test("Terminal receipts require preparation, exact proposed commands, and a unique immutable terminal")
  func terminalBinding() async throws {
    let disk = AxisMetricDisk(); defer { disk.remove() }
    let fixture = try AxisMetricFixture(), measurement = try fixture.measurement()
    let proposal = try ControllerAxisCalibrationProposal(measurement: measurement)
    let refused = try ControllerAxisCalibrationOutcome(status: .refused, reason: "Synthetic stale baseline; no write")
    let terminal = ControllerAxisCalibrationTerminal(proposalID: proposal.proposalID, outcome: refused,
      recordedAt: Date(timeIntervalSince1970: 1002))
    try await disk.store.append(fixture.record)
    try await disk.store.appendAxisMetricMeasurement(measurement)
    await #expect(throws: (any Error).self) { try await disk.store.appendAxisCalibrationTerminal(terminal) }
    try await disk.store.prepareAxisCalibration(ControllerAxisCalibrationAttempt(proposal: proposal))
    let wrong = try ControllerAxisCalibrationOutcome(status: .ambiguous,
      attemptedCommands: ["$100=999.000"], reason: "Synthetic wrong command")
    await #expect(throws: (any Error).self) {
      try await disk.store.appendAxisCalibrationTerminal(ControllerAxisCalibrationTerminal(proposalID: proposal.proposalID, outcome: wrong))
    }
    let complete = try await disk.store.appendAxisCalibrationTerminal(terminal)
    #expect(try await disk.store.appendAxisCalibrationTerminal(terminal) == complete)
    let conflict = ControllerAxisCalibrationTerminal(proposalID: proposal.proposalID, outcome: refused,
      recordedAt: Date(timeIntervalSince1970: 1003))
    await #expect(throws: (any Error).self) { try await disk.store.appendAxisCalibrationTerminal(conflict) }
    #expect(try disk.snapshot() == complete)
  }

  @Test("Normal records and every drawing attempt mutation retain all metric arrays and record-count revision")
  func unrelatedDrawingMutations() async throws {
    let disk = AxisMetricDisk(); defer { disk.remove() }
    let fixture = try AxisMetricFixture(), measurement = try fixture.measurement()
    try await disk.store.append(fixture.record)
    try await disk.store.appendAxisMetricMeasurement(measurement)
    let proposal = try ControllerAxisCalibrationProposal(measurement: measurement)
    let preparation = ControllerAxisCalibrationAttempt(proposal: proposal)
    let terminal = ControllerAxisCalibrationTerminal(proposalID: proposal.proposalID,
      outcome: try ControllerAxisCalibrationOutcome(status: .cancelled, reason: "Cancelled before any write"))
    try await disk.store.prepareAxisCalibration(preparation)
    try await disk.store.appendAxisCalibrationTerminal(terminal)
    func check(_ archive: DrawingRunEvidenceArchive, revision: UInt64) {
      #expect(archive.axisMetricMeasurements == [measurement])
      #expect(archive.axisCalibrationAttempts == [preparation])
      #expect(archive.axisCalibrationTerminals == [terminal])
      #expect(archive.revision == revision)
    }
    let other = try AxisMetricFixture()
    check(try await disk.store.append(other.record), revision: 2)
    let input = try attemptInput(registration: #require(fixture.checkpoint.tipCalibration).registration)
    check(try await disk.store.stageIntent(input.intent), revision: 2)
    let baseline = try await disk.store.installMedia(frame: input.frame, source: input.source)
    check(try await disk.store.stageBaseline(runID: input.intent.runID, media: baseline), revision: 2)
    check(try await disk.store.markInkDispatchPossible(runID: input.intent.runID), revision: 2)
    let sealed = try cancelledRecord(input.intent, baselines: [baseline], commanded: true)
    check(try await disk.store.append(sealed), revision: 3)
    // append's pre-dispatch failure branch creates its attempt and record atomically.
    let beforeDispatch = try attemptInput(registration: #require(fixture.checkpoint.tipCalibration).registration)
    check(try await disk.store.append(cancelledRecord(beforeDispatch.intent, baselines: [], commanded: false)), revision: 4)
    check(try disk.snapshot(), revision: 4)
    #expect(try disk.snapshot().records.first == fixture.record)
  }

  @Test("Checksum or semantic corruption rejects synchronous restart and every axis write preserves corrupt bytes")
  func corruptionIsReadOnly() async throws {
    for semantic in [false, true] {
      let disk = AxisMetricDisk(); defer { disk.remove() }
      let fixture = try AxisMetricFixture(), measurement = try fixture.measurement()
      try await disk.store.append(fixture.record)
      try await disk.store.appendAxisMetricMeasurement(measurement)
      let attempt = ControllerAxisCalibrationAttempt(proposal: try ControllerAxisCalibrationProposal(measurement: measurement))
      try await disk.store.prepareAxisCalibration(attempt)
      var envelope = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: disk.url)) as? [String: Any])
      if semantic {
        let encoded = try #require(envelope["payload"] as? String)
        let payload = try #require(Data(base64Encoded: encoded))
        var archive = try #require(JSONSerialization.jsonObject(with: payload) as? [String: Any])
        archive["axisMetricMeasurements"] = []
        let broken = try JSONSerialization.data(withJSONObject: archive, options: [.sortedKeys])
        envelope["payload"] = broken.base64EncodedString()
        envelope["payloadSHA256"] = SHA256.hash(data: broken).map { String(format: "%02x", $0) }.joined()
      } else {
        envelope["payloadSHA256"] = String(repeating: "0", count: 64)
      }
      let corruptBytes = try JSONSerialization.data(withJSONObject: envelope, options: [.sortedKeys])
      try corruptBytes.write(to: disk.url)
      let restarted = DrawingRunEvidenceStore(fileURL: disk.url)
      guard case .rejected = restarted.loadSnapshot() else { Issue.record("Corrupt axis archive must reject"); continue }
      await #expect(throws: (any Error).self) { try await restarted.appendAxisMetricMeasurement(measurement) }
      await #expect(throws: (any Error).self) { try await restarted.prepareAxisCalibration(attempt) }
      let terminal = ControllerAxisCalibrationTerminal(proposalID: attempt.proposal.proposalID,
        outcome: try ControllerAxisCalibrationOutcome(status: .refused, reason: "Never invoked"))
      await #expect(throws: (any Error).self) { try await restarted.appendAxisCalibrationTerminal(terminal) }
      #expect(try Data(contentsOf: disk.url) == corruptBytes)
    }
  }
}

private struct AxisMetricDisk {
  let url = FileManager.default.temporaryDirectory.appendingPathComponent("axis-metric-\(UUID())").appendingPathComponent("runs.json")
  var store: DrawingRunEvidenceStore { DrawingRunEvidenceStore(fileURL: url) }
  func remove() { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
  func snapshot() throws -> DrawingRunEvidenceArchive {
    guard case .loaded(let archive) = store.loadSnapshot() else {
      throw DrawingRunEvidenceArchiveError.invalidAxisCalibrationEvidence("Expected loaded test archive")
    }
    return archive
  }
}

private func copy(_ value: ControllerAxisMetricMeasurement, measurementID: UUID? = nil,
                  method: String? = nil, supersedes: UUID? = nil) throws -> ControllerAxisMetricMeasurement {
  try ControllerAxisMetricMeasurement(measurementID: measurementID ?? value.measurementID,
    recordedAt: value.recordedAt, geometry: value.geometry, sourceCheckpoint: value.sourceCheckpoint,
    edges: value.edges, method: method ?? value.method,
    operatorAxisAssociationConfirmed: value.operatorAxisAssociationConfirmed, supersedesMeasurementID: supersedes)
}
private func jsonObject<T: Encodable>(_ value: T) throws -> [String: Any] {
  try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as? [String: Any])
}

private func attemptInput(registration: TipCameraRegistration) throws
  -> (intent: DrawingRunIntent, frame: StampedFrame, source: FrameSourceIdentity) {
  let program = try DrawingProgramCatalog.program(for: .line,
    style: StrokeStyle(nominalLineWidth: 0.4, penProfileID: PenProfileID()))
  let placement = try DrawingPlacement(fieldAnchor: Point2(x: 0, y: 0), machineAnchor: Point2(x: 0, y: 0), uniformScale: 1)
  let hash = try registration.drawingEvidenceContentHash()
  let plan = try DrawingPlanner.plan(program: program, placement: placement,
    drawableRegion: DrawableMachineRegion(bounds: AxisAlignedBounds(minX: 0, minY: 0, maxX: 200, maxY: 200)),
    provenance: DrawingPlanningProvenance(modelRevisionID: DrawingModelRevisionID(registration.acceptedRevisionID.rawValue),
      modelContentHash: hash, registrationRevisionID: DrawingRegistrationRevisionID(registration.acceptedRevisionID.rawValue), registrationContentHash: hash))
  let context = try DrawingRunAttemptContext(program: program, registration: registration,
    drawingFeedMMPerMinute: 300, penActuationProfile: .initialDefaults,
    paper: PaperRevisionContext(instance: PaperInstanceRevision(), contactPlane: registration.applicability.paperContactPlane))
  let intent = try DrawingRunIntent(runID: RunID(), requestID: UUID(), plan: plan, placementID: UUID(),
    role: .ordinaryDrawing, context: context, recordedAt: RuntimeTimestamp(monotonicNanoseconds: 1))
  let optical = registration.applicability.opticalConfiguration
  let frame = try StampedFrame(sequence: 1, captureNanoseconds: 2, cameraConfigurationID: CameraConfigurationID(),
    width: optical.width, height: optical.height, rowBytes: optical.width, pixelFormat: .gray8,
    bytes: OwnedFrameBytes(Array(repeating: 240, count: optical.width * optical.height)))
  return (intent, frame, optical.source)
}

private func cancelledRecord(_ intent: DrawingRunIntent, baselines: [DrawingRunMediaReference], commanded: Bool) throws -> DrawingRunEvidenceRecord {
  try DrawingRunEvidenceRecord(runID: intent.runID, requestID: intent.requestID, role: intent.role,
    evidenceDisposition: .cancelled, requestFrontier: .admitted,
    executionFrontiers: DrawingRunExecutionFrontiers(plannedStrokeCount: UInt32(intent.plan.strokes.count),
      commandedStrokeCount: commanded ? 1 : 0, controllerCompletedStrokeCount: 0, inkVerifiedStrokeCount: 0),
    executionDisposition: .cancelled(reason: "Synthetic stop"), program: DrawingProgramEvidenceReference(program: intent.context.program),
    placement: DrawingPlacementEvidenceReference(placementID: intent.placementID, placement: intent.plan.placement),
    plan: DrawingExecutionPlanEvidenceReference(plan: intent.plan), planningProvenance: intent.plan.provenance,
    tipCalibration: DrawingTipCalibrationEvidenceReference(acceptedRevisionID: intent.context.registration.acceptedRevisionID,
      registrationEvidenceSHA256: DrawingMaterialApplicability.registrationHash(intent.context.registration),
      applicability: intent.context.registration.applicability, estimatorRevision: intent.context.registration.estimatorRevision),
    paper: intent.context.paper, observation: .notAttempted(.executionCancelledBeforeObservation),
    recordedAt: RuntimeTimestamp(monotonicNanoseconds: 4),
    attemptEvidence: DrawingRunAttemptEvidence(intent: intent, baselines: baselines, terminalFrames: [],
      missingCoverageReason: "Synthetic cancellation; no camera capture"))
}
