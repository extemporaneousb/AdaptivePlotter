import CryptoKit
import Foundation
import PlotterModel
import PlotterTestSupport
import Testing
@testable import PlotterRuntime

@Suite("Read-only terminal drawing transfer")
struct DrawingRunTransferTests {
  @Test("Export retains selected raw record bytes and every original without changing archive")
  func exactTerminalExport() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("terminal-transfer-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("raw.json"), store = DrawingRunEvidenceStore(fileURL: url)
    let fixture = try makeFixture()
    let baseline = try await store.installMedia(frame: fixture.baseline, source: fixture.source)
    let terminal = try await store.installMedia(frame: fixture.terminal, source: fixture.source)
    _ = try await store.stageIntent(fixture.intent)
    _ = try await store.stageBaseline(runID: fixture.intent.runID, media: baseline)
    _ = try await store.markInkDispatchPossible(runID: fixture.intent.runID)
    let record = try terminalRecord(fixture.intent, baseline: baseline, terminal: terminal)
    _ = try await store.append(record)
    let archiveBytes = try Data(contentsOf: url)
    let exported = try await store.exportTerminalRecord(runID: record.runID)
    #expect(exported.record == record)
    #expect(try Data(contentsOf: url) == archiveBytes)
    let outer = try #require(JSONSerialization.jsonObject(with: archiveBytes) as? [String: Any])
    let encodedPayload = try #require(outer["payload"] as? String)
    let payload = try #require(Data(base64Encoded: encodedPayload))
    let manifest = try #require(JSONSerialization.jsonObject(with: payload) as? [String: Any])
    let entries = try #require(manifest["records"] as? [[String: Any]])
    let hash = try #require(entries.first?["sha256"] as? String)
    let originalRecord = try Data(contentsOf: directory.appendingPathComponent("raw.json.records").appendingPathComponent(hash + ".json"))
    #expect(exported.recordJSON == originalRecord)
    #expect(exported.originalMedia[baseline.frame.frameSHA256] == fixture.baseline.bytes.data)
    #expect(exported.originalMedia[terminal.frame.frameSHA256] == fixture.terminal.bytes.data)
    try record.validateOriginalMedia(exported.originalMedia)
    #expect(try await store.exportTerminalRecord(runID: record.runID).recordJSON == originalRecord)
    _ = try await store.deleteReview(recordID: record.recordID)
    await #expect(throws: (any Error).self) { try await store.exportTerminalRecord(runID: record.runID) }
  }

  @Test("Pure terminal validation refuses missing, additional and corrupt originals")
  func originalValidation() throws {
    let fixture = try makeFixture()
    let baseline = DrawingRunMediaReference(frame: fixture.baseline, source: fixture.source)
    let terminal = DrawingRunMediaReference(frame: fixture.terminal, source: fixture.source)
    let record = try terminalRecord(fixture.intent, baseline: baseline, terminal: terminal)
    let good = [baseline.frame.frameSHA256: fixture.baseline.bytes.data,
      terminal.frame.frameSHA256: fixture.terminal.bytes.data]
    try record.validateOriginalMedia(good)
    #expect(throws: (any Error).self) { try record.validateOriginalMedia([:]) }
    var extra = good; extra[String(repeating: "a", count: 64)] = Data([0])
    #expect(throws: (any Error).self) { try record.validateOriginalMedia(extra) }
    var corrupt = good
    corrupt[baseline.frame.frameSHA256] = Data(repeating: 0, count: fixture.baseline.bytes.count)
    #expect(throws: (any Error).self) { try record.validateOriginalMedia(corrupt) }
  }

  private func makeFixture() throws -> Fixture {
    let authority = try TipAuthorityFixture(), registration = try authority.registration()
    let program = try DrawingProgramCatalog.program(for: .line,
      style: StrokeStyle(nominalLineWidth: 0.4, penProfileID: PenProfileID()))
    let placement = try DrawingPlacement(fieldAnchor: Point2(x: 0, y: 0),
      machineAnchor: Point2(x: 0, y: 0), uniformScale: 1)
    let hash = try DrawingMaterialApplicability.registrationHash(registration)
    let digest = try Digest(bytes: stride(from: 0, to: hash.count, by: 2).map {
      UInt8(hash.dropFirst($0).prefix(2), radix: 16)!
    })
    let provenance = DrawingPlanningProvenance(modelRevisionID: DrawingModelRevisionID(registration.acceptedRevisionID.rawValue),
      modelContentHash: digest, registrationRevisionID: DrawingRegistrationRevisionID(registration.acceptedRevisionID.rawValue),
      registrationContentHash: digest)
    let plan = try DrawingPlanner.plan(program: program, placement: placement,
      drawableRegion: DrawableMachineRegion(bounds: AxisAlignedBounds(minX: 0, minY: 0, maxX: 200, maxY: 200)),
      provenance: provenance)
    let origin = DrawingOriginReference(libraryID: UUID(), captureID: UUID(), resultID: "fixture",
      resultRecordSHA256: SHA256.hash(data: Data("{}".utf8)).map { String(format: "%02x", $0) }.joined(),
      programHash: program.contentHash)
    let reference = DrawingRunCandidateReference(candidateID: origin.drawingID, contentHash: origin.identityHash,
      sourceProgram: program, origin: origin)
    let context = try DrawingRunAttemptContext(program: program, registration: registration,
      drawingFeedMMPerMinute: 300, penActuationProfile: .initialDefaults,
      paper: PaperRevisionContext(instance: PaperInstanceRevision(), contactPlane: authority.paper), candidate: reference)
    let intent = try DrawingRunIntent(runID: RunID(), requestID: UUID(), plan: plan, placementID: UUID(),
      role: .ordinaryDrawing, context: context, recordedAt: RuntimeTimestamp(monotonicNanoseconds: 1))
    let baseline = try StampedFrame(sequence: 1, captureNanoseconds: 2,
      cameraConfigurationID: authority.cameraConfigurationID, width: 640, height: 480,
      rowBytes: 640, pixelFormat: .gray8, bytes: OwnedFrameBytes(Array(repeating: 240, count: 640 * 480)))
    let terminal = try StampedFrame(sequence: 2, captureNanoseconds: 3,
      cameraConfigurationID: authority.cameraConfigurationID, width: 640, height: 480,
      rowBytes: 640, pixelFormat: .gray8, bytes: OwnedFrameBytes(Array(repeating: 230, count: 640 * 480)))
    return .init(intent: intent, baseline: baseline, terminal: terminal, source: authority.source)
  }

  private func terminalRecord(_ intent: DrawingRunIntent, baseline: DrawingRunMediaReference,
    terminal: DrawingRunMediaReference) throws -> DrawingRunEvidenceRecord {
    try DrawingRunEvidenceRecord(runID: intent.runID, requestID: intent.requestID,
      role: intent.role, evidenceDisposition: .cancelled, requestFrontier: .admitted,
      executionFrontiers: DrawingRunExecutionFrontiers(plannedStrokeCount: UInt32(intent.plan.strokes.count),
        commandedStrokeCount: 1, controllerCompletedStrokeCount: 0, inkVerifiedStrokeCount: 0),
      executionDisposition: .cancelled(reason: "Operator stop"),
      program: DrawingProgramEvidenceReference(program: intent.context.program),
      placement: DrawingPlacementEvidenceReference(placementID: intent.placementID, placement: intent.plan.placement),
      plan: DrawingExecutionPlanEvidenceReference(plan: intent.plan), planningProvenance: intent.plan.provenance,
      tipCalibration: DrawingTipCalibrationEvidenceReference(acceptedRevisionID: intent.context.registration.acceptedRevisionID,
        registrationEvidenceSHA256: DrawingMaterialApplicability.registrationHash(intent.context.registration),
        applicability: intent.context.registration.applicability, estimatorRevision: intent.context.registration.estimatorRevision),
      paper: intent.context.paper, observation: .notAttempted(.executionCancelledBeforeObservation),
      recordedAt: RuntimeTimestamp(monotonicNanoseconds: 4),
      attemptEvidence: DrawingRunAttemptEvidence(intent: intent, baselines: [baseline],
        terminalFrames: [terminal], missingCoverageReason: "Stopped before observation"))
  }

  private struct Fixture {
    let intent: DrawingRunIntent
    let baseline: StampedFrame
    let terminal: StampedFrame
    let source: FrameSourceIdentity
  }
}
