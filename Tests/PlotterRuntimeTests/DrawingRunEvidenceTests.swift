import Foundation
import PlotterModel
@testable import PlotterRuntime
import Testing

@Suite("Durable drawing-run evidence")
struct DrawingRunEvidenceTests {
  @Test("record round-trip retains typed provenance, frame comparison, and trial role")
  func recordRoundTrip() throws {
    let record = try drawingEvidenceFixture(role: .reservedHoldout)

    let restored = try JSONDecoder().decode(
      DrawingRunEvidenceRecord.self,
      from: JSONEncoder().encode(record)
    )

    #expect(restored == record)
    #expect(restored.role == .reservedHoldout)
    #expect(restored.readinessReference.recordID == record.recordID)
    #expect(restored.readinessReference.disposition == .attributable)
    #expect(restored.paper.instance == record.paper.instance)
    #expect(restored.paper.contactPlane == record.paper.contactPlane)
    guard case .observed(let observed) = restored.observation else {
      Issue.record("fixture observation should remain observed")
      return
    }
    #expect(observed.frames.baseline.frameID != observed.frames.post.frameID)
    #expect(observed.residual?.correspondenceCount == 2)
  }

  @Test("training and holdout evidence require attributable comparison residuals")
  func evidenceRoleRequiresComparison() throws {
    let fixture = try drawingEvidenceParts()
    let withoutResidual = try DrawingObservedInkEvidence(
      frames: fixture.frames,
      intendedInk: fixture.intended,
      observedInk: fixture.observed,
      residual: nil,
      algorithmRevisions: fixture.algorithms
    )

    #expect(throws: DrawingRunEvidenceError.missingComparisonEvidence) {
      try DrawingRunEvidenceRecord(
        runID: RunID(),
        requestID: UUID(),
        role: .training,
        evidenceDisposition: .attributable,
        requestFrontier: .admitted,
        executionFrontiers: try DrawingRunExecutionFrontiers(
          plannedStrokeCount: 1,
          commandedStrokeCount: 1,
          controllerCompletedStrokeCount: 1,
          inkVerifiedStrokeCount: 1
        ),
        executionDisposition: .completed,
        program: fixture.program,
        placement: fixture.placement,
        plan: fixture.plan,
        planningProvenance: fixture.planning,
        tipCalibration: fixture.tip,
        paper: fixture.paper,
        observation: .observed(withoutResidual),
        recordedAt: RuntimeTimestamp(monotonicNanoseconds: 300)
      )
    }
  }

  @Test("frontiers and dispositions cannot claim facts out of order")
  func invalidFrontiersAndDisposition() throws {
    #expect(throws: DrawingRunEvidenceError.invalidFrontier) {
      try DrawingRunExecutionFrontiers(
        plannedStrokeCount: 2,
        commandedStrokeCount: 1,
        controllerCompletedStrokeCount: 2,
        inkVerifiedStrokeCount: 0
      )
    }

    let fixture = try drawingEvidenceParts()
    let observed = try DrawingObservedInkEvidence(
      frames: fixture.frames,
      intendedInk: fixture.intended,
      observedInk: fixture.observed,
      residual: fixture.residual,
      algorithmRevisions: fixture.algorithms
    )
    #expect(throws: DrawingRunEvidenceError.incompatibleDisposition) {
      try DrawingRunEvidenceRecord(
        runID: RunID(),
        requestID: UUID(),
        role: .ordinaryDrawing,
        evidenceDisposition: .refused,
        requestFrontier: .admitted,
        executionFrontiers: try DrawingRunExecutionFrontiers(
          plannedStrokeCount: 1,
          commandedStrokeCount: 1,
          controllerCompletedStrokeCount: 1,
          inkVerifiedStrokeCount: 1
        ),
        executionDisposition: .completed,
        program: fixture.program,
        placement: fixture.placement,
        plan: fixture.plan,
        planningProvenance: fixture.planning,
        tipCalibration: fixture.tip,
        paper: fixture.paper,
        observation: .observed(observed),
        recordedAt: RuntimeTimestamp(monotonicNanoseconds: 300)
      )
    }
  }

  @Test("completed execution can retain typed frame-unavailable Vision evidence")
  func completedExecutionWithoutPostFrame() throws {
    let fixture = try drawingEvidenceParts()

    let record = try DrawingRunEvidenceRecord(
      runID: RunID(),
      requestID: UUID(),
      role: .ordinaryDrawing,
      evidenceDisposition: .visionUnclear,
      requestFrontier: .admitted,
      executionFrontiers: DrawingRunExecutionFrontiers(
        plannedStrokeCount: 1,
        commandedStrokeCount: 1,
        controllerCompletedStrokeCount: 1,
        inkVerifiedStrokeCount: 0
      ),
      executionDisposition: .completed,
      program: fixture.program,
      placement: fixture.placement,
      plan: fixture.plan,
      planningProvenance: fixture.planning,
      tipCalibration: fixture.tip,
      paper: fixture.paper,
      observation: .notAttempted(.frameEvidenceUnavailable),
      recordedAt: RuntimeTimestamp(monotonicNanoseconds: 300)
    )

    let restored = try JSONDecoder().decode(
      DrawingRunEvidenceRecord.self,
      from: JSONEncoder().encode(record)
    )
    #expect(restored == record)
    #expect(restored.evidenceDisposition == .visionUnclear)
    #expect(restored.observation == .notAttempted(.frameEvidenceUnavailable))
  }

  @Test("atomic store appends immutable facts and rejects tampering")
  func storeRoundTripAndTamper() async throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("drawing-evidence-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let fileURL = directory.appendingPathComponent("drawing-runs.json")
    let store = DrawingRunEvidenceStore(fileURL: fileURL)
    let record = try drawingEvidenceFixture(role: .ordinaryDrawing)

    let appended = try await store.append(record)
    #expect(appended.revision == 1)
    #expect(appended.records == [record])
    guard case .loaded(let loaded) = await store.load() else {
      Issue.record("saved evidence archive should load")
      return
    }
    #expect(loaded == appended)

    await #expect(throws: DrawingRunEvidenceArchiveError.duplicateRecordID(record.recordID)) {
      try await store.append(record)
    }
    guard case .loaded(let afterDuplicate) = await store.load() else {
      Issue.record("duplicate append must preserve the prior archive")
      return
    }
    #expect(afterDuplicate == appended)

    var bytes = try Data(contentsOf: fileURL)
    bytes[bytes.count / 2] ^= 0x01
    try bytes.write(to: fileURL, options: [.atomic])
    guard case .rejected = await store.load() else {
      Issue.record("tampered evidence archive must be rejected")
      return
    }
  }

  @Test("corrupt existing archive blocks append instead of replacing facts")
  func corruptArchiveBlocksAppend() async throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("drawing-evidence-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let fileURL = directory.appendingPathComponent("drawing-runs.json")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try Data("not an archive".utf8).write(to: fileURL)
    let store = DrawingRunEvidenceStore(fileURL: fileURL)

    do {
      _ = try await store.append(try drawingEvidenceFixture(role: .ordinaryDrawing))
      Issue.record("append must not overwrite an unreadable fact archive")
    } catch let error as DrawingRunEvidenceStoreError {
      guard case .existingArchiveRejected(.malformedEnvelope) = error else {
        Issue.record("expected typed malformed-envelope rejection, got \(error)")
        return
      }
    }
    #expect(try Data(contentsOf: fileURL) == Data("not an archive".utf8))
  }
}

private struct DrawingEvidenceFixtureParts {
  let program: DrawingProgramEvidenceReference
  let placement: DrawingPlacementEvidenceReference
  let plan: DrawingExecutionPlanEvidenceReference
  let planning: DrawingPlanningProvenance
  let tip: DrawingTipCalibrationEvidenceReference
  let paper: PaperRevisionContext
  let frames: DrawingObservationFramePair
  let intended: [Polyline<CameraPixelSpace>]
  let observed: [Polyline<CameraPixelSpace>]
  let residual: DrawingResidualEvidence
  let algorithms: Set<AlgorithmRevisionEvidence>
}

private func drawingEvidenceFixture(
  role: DrawingTrialEvidenceRole
) throws -> DrawingRunEvidenceRecord {
  let fixture = try drawingEvidenceParts()
  let observation = try DrawingObservedInkEvidence(
    frames: fixture.frames,
    intendedInk: fixture.intended,
    observedInk: fixture.observed,
    residual: fixture.residual,
    algorithmRevisions: fixture.algorithms
  )
  return try DrawingRunEvidenceRecord(
    runID: RunID(),
    requestID: UUID(),
    role: role,
    evidenceDisposition: .attributable,
    requestFrontier: .admitted,
    executionFrontiers: DrawingRunExecutionFrontiers(
      plannedStrokeCount: 1,
      commandedStrokeCount: 1,
      controllerCompletedStrokeCount: 1,
      inkVerifiedStrokeCount: 1
    ),
    executionDisposition: .completed,
    program: fixture.program,
    placement: fixture.placement,
    plan: fixture.plan,
    planningProvenance: fixture.planning,
    tipCalibration: fixture.tip,
    paper: fixture.paper,
    observation: .observed(observation),
    recordedAt: RuntimeTimestamp(monotonicNanoseconds: 300)
  )
}

private func drawingEvidenceParts() throws -> DrawingEvidenceFixtureParts {
  let programHash = try evidenceDigest(1)
  let placementHash = try evidenceDigest(2)
  let planHash = try evidenceDigest(3)
  let planning = DrawingPlanningProvenance(
    modelRevisionID: DrawingModelRevisionID(),
    modelContentHash: try evidenceDigest(4),
    registrationRevisionID: DrawingRegistrationRevisionID(),
    registrationContentHash: try evidenceDigest(5)
  )
  let optical = try CameraOpticalConfigurationIdentity(
    source: .simulated,
    sensorFormat: "fixture",
    width: 20,
    height: 10,
    pixelFormat: .gray8,
    orientation: .up,
    mirrored: false,
    digitalZoomFactor: 1,
    lensIdentity: "fixture-lens",
    focusConfiguration: "fixed",
    mountRevision: UUID(),
    reframingRevision: UUID()
  )
  let paper = PaperRevisionContext(
    instance: PaperInstanceRevision(),
    contactPlane: PaperContactPlaneRevision()
  )
  let applicability = TipCalibrationApplicabilityContext(
    opticalConfiguration: optical,
    machineGeometry: MachineGeometryIdentity(),
    machineCoordinateFrame: MachineCoordinateFrameRevision(rawValue: 1),
    toolAssembly: ToolAssemblyRevision(),
    penContactProfile: PenContactProfileRevision(),
    paperContactPlane: paper.contactPlane
  )
  let cameraConfigurationID = CameraConfigurationID()
  let baseline = try evidenceFrame(
    id: FrameID(rawValue: "baseline"),
    captureNanoseconds: 100,
    cameraConfigurationID: cameraConfigurationID
  )
  let post = try evidenceFrame(
    id: FrameID(rawValue: "post"),
    captureNanoseconds: 200,
    cameraConfigurationID: cameraConfigurationID
  )
  let intended = try Polyline<CameraPixelSpace>(points: [
    Point2(x: 2, y: 5),
    Point2(x: 10, y: 5),
  ])
  let observed = try Polyline<CameraPixelSpace>(points: [
    Point2(x: 2.5, y: 5.25),
    Point2(x: 10.5, y: 5.25),
  ])
  return DrawingEvidenceFixtureParts(
    program: DrawingProgramEvidenceReference(programID: ProgramID(), contentHash: programHash),
    placement: DrawingPlacementEvidenceReference(
      placementID: UUID(),
      contentHash: placementHash
    ),
    plan: try DrawingExecutionPlanEvidenceReference(
      revisionID: ExecutionPlanRevisionID(planHash),
      contentHash: planHash
    ),
    planning: planning,
    tip: try DrawingTipCalibrationEvidenceReference(
      acceptedRevisionID: LearningArtifactRevisionID(),
      registrationEvidenceSHA256: String(repeating: "a", count: 64),
      applicability: applicability,
      estimatorRevision: "tip-affine-v1"
    ),
    paper: paper,
    frames: try DrawingObservationFramePair(
      source: .simulated,
      baseline: ExactFrameProvenance(frame: baseline),
      post: ExactFrameProvenance(frame: post)
    ),
    intended: [intended],
    observed: [observed],
    residual: try DrawingResidualEvidence(
      correspondenceCount: 2,
      rootMeanSquarePixels: 0.5,
      maximumPixels: 0.6,
      rootMeanSquareCrossTrackPixels: 0.25
    ),
    algorithms: [try AlgorithmRevisionEvidence(
      component: "drawing-observation",
      revision: "v1"
    )]
  )
}

private func evidenceDigest(_ byte: UInt8) throws -> Digest {
  try Digest(bytes: Array(repeating: byte, count: Digest.byteCount))
}

private func evidenceFrame(
  id: FrameID,
  captureNanoseconds: UInt64,
  cameraConfigurationID: CameraConfigurationID
) throws -> StampedFrame {
  try StampedFrame(
    id: id,
    sequence: captureNanoseconds,
    captureNanoseconds: captureNanoseconds,
    cameraConfigurationID: cameraConfigurationID,
    width: 20,
    height: 10,
    rowBytes: 20,
    pixelFormat: .gray8,
    bytes: OwnedFrameBytes(Array(repeating: 255, count: 200))
  )
}
