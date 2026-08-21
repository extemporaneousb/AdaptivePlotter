import Foundation
import PlotterModel
import Testing

@testable import PlotterRuntime

struct TipCalibrationAuthorityTests {
  @Test("Tool contact evidence preserves exact asserted-center provenance")
  func toolContactObservationIsImmutableExactEvidence() throws {
    let fixture = try TipAuthorityFixture()
    let profile = PenActuationProfile(
      raisedSpindleValue: 55,
      loweredSpindleValue: 805,
      settleSeconds: 0.3
    )
    let observation = try fixture.observation(position: .center, penProfile: profile)

    #expect(observation.disposition == .accepted)
    #expect(observation.click.role == .assertedCenter)
    #expect(observation.preMarkFrame.archivedBytes == nil)
    #expect(observation.capMapResidualPixels == 2)
    #expect(observation.revealEvidence.capMapResidualPixels == 1)
    #expect(observation.penDown.profile == profile)
    #expect(observation.penDown.profile.value(for: .lower) == 805)
    #expect(observation.penUp.profile.value(for: .raise) == 55)
    #expect(try observation.durableEvidenceSHA256().count == 64)
    #expect(!observation.disposition.blacklistsPhysicalLocation)

    let ambiguous = try fixture.observation(
      position: .negativeX,
      disposition: .ambiguous("Pen Down completion is unknown."),
      penDown: .ambiguous(.transport("unknown post-write state"))
    )
    #expect(ambiguous.disposition.blacklistsPhysicalLocation)
  }

  @Test("Tool contact evidence retains cap-map extrapolation residual without gating acceptance")
  func toolContactObservationCapResidualIsDiagnostic() throws {
    let observation = try TipAuthorityFixture().observation(
      position: .positiveX,
      capPredictionOffsetAtMark: 100
    )

    #expect(observation.disposition == .accepted)
    #expect(observation.capMapResidualPixels == 100)
  }

  @Test("Accepted contact evidence requires settled motion, cap checks, lower, and raise")
  func acceptedObservationRequiresSettledEvidence() throws {
    let fixture = try TipAuthorityFixture()
    let acceptedGeometryResidue = try fixture.observation(
      position: .center,
      markGeometryCenterResidualMM: 0.013
    )
    #expect(
      MachinePositionAcceptancePolicy.accepts(
        acceptedGeometryResidue.markGeometry.center,
        target: acceptedGeometryResidue.intendedMarkPosition
      )
    )
    #expect(throws: TipCalibrationAuthorityError.invalidAcceptedPenEvidence) {
      try fixture.observation(
        position: .center,
        penDown: .ambiguous(.transport("unknown post-write state"))
      )
    }
    #expect(throws: TipCalibrationAuthorityError.frameEvidenceMismatch) {
      try fixture.observation(position: .center, markPositionResidualMM: 0.051)
    }
    #expect(throws: TipCalibrationAuthorityError.frameEvidenceMismatch) {
      try fixture.observation(position: .center, revealPositionResidualMM: 0.051)
    }
    #expect(throws: TipCalibrationAuthorityError.frameEvidenceMismatch) {
      try fixture.observation(position: .center, markGeometryCenterResidualMM: 0.051)
    }
  }

  @Test("Tip registration consumes all five observations without a residual gate")
  func registrationConsumesAllFiveWithoutResidualGate() throws {
    let fixture = try TipAuthorityFixture()
    let registration = try fixture.registration(clickOffsetAtNegativeY: 100)

    #expect(registration.modelForm == .directAffine)
    #expect(registration.modelSelectionEvidence.observationIDs.count == 5)
    #expect(registration.observationEvidence.count == 5)
    #expect(registration.uncertainty.maximumResidualPixels > 10)
    #expect(registration.consumedObservationIDs.count == 5)
  }

  @Test("Applicability uses nonzero tolerance for target, geometry, and settlement")
  func applicabilityUsesMachinePositionTolerance() throws {
    let fixture = try TipAuthorityFixture()
    let observations = try ToolContactCalibrationPosition.allCases.map { position in
      try AcceptedToolContactObservation(
        artifactRevisionID: LearningArtifactRevisionID(),
        observation: fixture.observation(
          position: position,
          machinePointOverride: position == .positiveX ? Point2(x: 100.013, y: 50) : nil,
          markPositionResidualMM: position == .positiveX ? 0.013 : 0.01,
          markGeometryCenterResidualMM: position == .positiveX ? 0.013 : 0
        )
      )
    }
    let selection = try TipCalibrationModelSelection.fitAffineFirst(
      acceptedObservations: observations,
      capCameraFromMachine: AffineTransform2(
        m11: 2, m12: 0, m21: 0, m22: 3, tx: 10, ty: 20
      )
    )

    let registration = try TipCameraRegistration(
      modelForm: selection.modelForm,
      cameraFromMachine: selection.finalCameraFromMachine,
      modelSelectionEvidence: selection.evidence,
      uncertainty: selection.uncertainty,
      applicabilityRectangle: AxisAlignedBounds(minX: 0, minY: 0, maxX: 100, maxY: 100),
      acceptedObservations: observations,
      applicability: fixture.context(),
      acceptedRevisionID: LearningArtifactRevisionID(),
      machineCameraRegistrationRevisionID: fixture.machineCameraRevision,
      estimatorRevision: "tip-affine-fit-boundary-settlement-v1",
      acceptedAt: RuntimeTimestamp(
        monotonicNanoseconds: 800,
        wallTime: Date(timeIntervalSince1970: 0.8)
      )
    )

    #expect(registration.observationEvidence.count == 5)
    #expect(
      abs(observations[3].observation.intendedMarkPosition.point.x - 100.013) < 1e-9
    )
    #expect(
      abs(observations[3].observation.actualSettledPosition.point.x - 100.026) < 1e-9
    )
    #expect(
      abs(observations[3].observation.markGeometry.center.point.x - 100.026) < 1e-9
    )
  }

  @Test("Applicability rejects machine positions beyond the shared tolerance")
  func applicabilityRejectsPositionOutsideTolerance() throws {
    let fixture = try TipAuthorityFixture()
    let observations = try ToolContactCalibrationPosition.allCases.map { position in
      try AcceptedToolContactObservation(
        artifactRevisionID: LearningArtifactRevisionID(),
        observation: fixture.observation(
          position: position,
          machinePointOverride: position == .positiveX ? Point2(x: 100.051, y: 50) : nil
        )
      )
    }
    let selection = try TipCalibrationModelSelection.fitAffineFirst(
      acceptedObservations: observations,
      capCameraFromMachine: AffineTransform2(
        m11: 2, m12: 0, m21: 0, m22: 3, tx: 10, ty: 20
      )
    )

    #expect(throws: TipCalibrationAuthorityError.invalidApplicabilityContext) {
      try TipCameraRegistration(
        modelForm: selection.modelForm,
        cameraFromMachine: selection.finalCameraFromMachine,
        modelSelectionEvidence: selection.evidence,
        uncertainty: selection.uncertainty,
        applicabilityRectangle: AxisAlignedBounds(
          minX: 0,
          minY: 0,
          maxX: 100,
          maxY: 100
        ),
        acceptedObservations: observations,
        applicability: fixture.context(),
        acceptedRevisionID: LearningArtifactRevisionID(),
        machineCameraRegistrationRevisionID: fixture.machineCameraRevision,
        estimatorRevision: "tip-affine-fit-outside-tolerance-v1",
        acceptedAt: RuntimeTimestamp(
          monotonicNanoseconds: 800,
          wallTime: Date(timeIntervalSince1970: 0.8)
        )
      )
    }
  }

  @Test("model construction fits affine first from all five observations")
  func affineFirstModelSelection() throws {
    let fixture = try TipAuthorityFixture()
    let observations = try ToolContactCalibrationPosition.allCases.map { position in
      try AcceptedToolContactObservation(
        artifactRevisionID: LearningArtifactRevisionID(),
        observation: fixture.observation(position: position)
      )
    }
    let exactCap = try AffineTransform2<MachineSpace, CameraPixelSpace>(
      m11: 2, m12: 0, m21: 0, m22: 3, tx: 10, ty: 20
    )
    let selection = try TipCalibrationModelSelection.fitAffineFirst(
      acceptedObservations: observations,
      capCameraFromMachine: exactCap
    )
    #expect(selection.modelForm == .directAffine)
    #expect(selection.evidence.observationIDs == observations.map { $0.observation.id })
    #expect(selection.uncertainty.maximumResidualPixels < 1e-9)
  }

  @Test("constant correction is used only when all-five affine construction throws")
  func constantConstructionFallback() throws {
    let fixture = try TipAuthorityFixture()
    let repeatedMachinePoint = try Point2<MachineSpace>(x: 50, y: 50)
    let observations = try ToolContactCalibrationPosition.allCases.map { position in
      try AcceptedToolContactObservation(
        artifactRevisionID: LearningArtifactRevisionID(),
        observation: fixture.observation(
          position: position,
          machinePointOverride: repeatedMachinePoint
        )
      )
    }
    let cap = try AffineTransform2<MachineSpace, CameraPixelSpace>(
      m11: 2, m12: 0, m21: 0, m22: 3, tx: 10, ty: 20
    )
    let selection = try TipCalibrationModelSelection.fitAffineFirst(
      acceptedObservations: observations,
      capCameraFromMachine: cap
    )
    #expect(selection.modelForm == .constantCameraPixelCorrection)
    #expect(selection.evidence.selectedModelForm == .constantCameraPixelCorrection)
    #expect(selection.evidence.observationIDs.count == 5)
  }

  @Test("Affine covariance must be positive semidefinite")
  func covarianceRejectsIndefiniteMatrix() {
    var covariance = Array(repeating: 0.0, count: 36)
    for index in 0..<6 { covariance[index * 6 + index] = 1 }
    covariance[1] = 2
    covariance[6] = 2
    #expect(throws: TipCalibrationAuthorityError.invalidUncertainty) {
      try TipCalibrationUncertainty(
        affineParameterCovariance: covariance,
        rootMeanSquareResidualPixels: 1,
        maximumResidualPixels: 2
      )
    }
  }

  @Test("Applicability distinguishes retain, revalidate, quarantine, and invalidate")
  func applicabilityMatrix() throws {
    let fixture = try TipAuthorityFixture()
    let registration = try fixture.registration()

    #expect(
      try registration.applicabilityDecision(
        for: .presentationTransformChanged(PresentationTransformRevision())
      ) == .retain
    )
    if case .requireExplicitRevalidation = try registration.applicabilityDecision(
      for: .captureSessionRestarted(
        CameraCaptureSessionID(),
        provenOpticalConfiguration: fixture.optical
      )
    ) {
    } else {
      Issue.record("capture restart with proven semantic optics must require revalidation")
    }
    if case .quarantine = try registration.applicabilityDecision(
      for: .paperContactPlaneChanged(PaperContactPlaneRevision())
    ) {
    } else {
      Issue.record("paper replacement must quarantine contact calibration")
    }
    if case .invalidate = try registration.applicabilityDecision(for: .unknownOpticalChange) {
    } else {
      Issue.record("unknown optical change must invalidate")
    }
    if case .invalidate = try registration.applicabilityDecision(for: .toolAssemblyChanged) {
    } else {
      Issue.record("tool assembly change must invalidate")
    }
  }

  @Test("Known machine coordinate rebase preserves physical tip prediction")
  func knownMachineCoordinateRebase() throws {
    let fixture = try TipAuthorityFixture()
    let registration = try fixture.registration()
    let oldPoint = try Point2<MachineSpace>(x: 20, y: 30)
    let delta = try Vector2<MachineSpace>(dx: 7, dy: -4)
    let newPoint = try oldPoint.translated(by: delta)
    let expected = try registration.tipPixel(at: oldPoint)

    let rebased = try registration.rebasedForKnownMachineCoordinateChange(
      to: MachineCoordinateFrameRevision(rawValue: 12),
      delta: delta
    )

    #expect(try rebased.tipPixel(at: newPoint) == expected)
    #expect(rebased.applicabilityRectangle.minX == registration.applicabilityRectangle.minX + 7)
    #expect(rebased.applicabilityRectangle.minY == registration.applicabilityRectangle.minY - 4)
    #expect(rebased.applicability.machineCoordinateFrame.rawValue == 12)
  }

  @Test("Proven crop or resample rebase updates projection and covariance")
  func knownPixelTransformRebasesProjectionAndCovariance() throws {
    let fixture = try TipAuthorityFixture()
    let registration = try fixture.registration()
    let machinePoint = try Point2<MachineSpace>(x: 20, y: 30)
    let oldPixel = try registration.tipPixel(at: machinePoint)
    let transform = try AffineTransform2<CameraPixelSpace, CameraPixelSpace>(
      m11: 2, m12: 0, m21: 0, m22: 2, tx: 4, ty: -6
    )
    let expected = try transform.applying(to: oldPixel)
    let rebasedOptical = try fixture.optical(width: 1_280, height: 960)
    let evidence = try KnownCameraPixelRebaseEvidence(
      fromOpticalConfiguration: fixture.optical,
      toOpticalConfiguration: rebasedOptical,
      transform: transform,
      captureSessionID: CameraCaptureSessionID(),
      evidenceSHA256: String(repeating: "f", count: 64),
      algorithmRevision: "known-resample-v1"
    )

    let rebased = try registration.applyingKnownPixelTransform(evidence)

    #expect(try rebased.tipPixel(at: machinePoint) == expected)
    #expect(
      rebased.uncertainty.rootMeanSquareResidualPixels
        == registration.uncertainty.rootMeanSquareResidualPixels * 2
    )
    #expect(
      rebased.observationEvidence[0].observedPoint
        == (try transform.applying(to: registration.observationEvidence[0].observedPoint))
    )
    #expect(
      rebased.uncertainty.affineParameterCovariance
        != registration.uncertainty.affineParameterCovariance
    )

    let remounted = try fixture.optical(
      width: 1_280,
      height: 960,
      mountRevision: UUID()
    )
    #expect(throws: TipCalibrationAuthorityError.sourceRebaseNotPermitted) {
      try KnownCameraPixelRebaseEvidence(
        fromOpticalConfiguration: fixture.optical,
        toOpticalConfiguration: remounted,
        transform: transform,
        captureSessionID: CameraCaptureSessionID(),
        evidenceSHA256: String(repeating: "e", count: 64),
        algorithmRevision: "invalid-rebase-v1"
      )
    }
  }

  @Test("Tip checkpoint loads quarantined and needs fresh substantive revalidation")
  func checkpointQuarantineAndRevalidation() throws {
    let fixture = try TipAuthorityFixture()
    let registration = try fixture.registration()
    let checkpoint = try AcceptedTipCalibrationCheckpoint(
      registration: registration,
      acceptanceEvent: TipCalibrationAcceptanceEvent(
        acceptedRevisionID: registration.acceptedRevisionID,
        timestamp: fixture.timestamp(900),
        actor: "operator"
      )
    )
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("tip-checkpoint-\(UUID().uuidString)", isDirectory: true)
    let url = directory.appendingPathComponent("checkpoint.json")
    let store = AcceptedTipCalibrationCheckpointStore(fileURL: url)
    defer { try? FileManager.default.removeItem(at: directory) }

    try store.save(checkpoint)
    let loaded: AcceptedTipCalibrationCheckpoint
    switch store.load() {
    case .quarantined(let value): loaded = value
    case .absent: throw TipFixtureError.unexpected("checkpoint absent")
    case .rejected(let reason): throw TipFixtureError.unexpected(reason)
    }

    let evidence = try fixture.revalidationEvidence(
      context: registration.applicability,
      frameTime: 950,
      timestamp: 1_000
    )
    if case .restored(let authority) = loaded.revalidate(with: evidence) {
      #expect(authority.registration.acceptedRevisionID == registration.acceptedRevisionID)
      #expect(authority.effectiveApplicability == registration.applicability)
    } else {
      Issue.record("fresh cap and controller evidence must restore matching semantics")
    }

    #expect(throws: TipCalibrationAuthorityError.frameEvidenceMismatch) {
      try fixture.revalidationEvidence(
        context: registration.applicability,
        frameTime: 950,
        timestamp: 1_000,
        capPredictionOffset: 4,
        maximumCapResidual: 2
      )
    }

    let changedPaper = fixture.context(paper: PaperContactPlaneRevision())
    let paperEvidence = try fixture.revalidationEvidence(
      context: changedPaper,
      frameTime: 1_100,
      timestamp: 1_200
    )
    if case .quarantined = loaded.revalidate(with: paperEvidence) {
    } else {
      Issue.record("paper replacement must require a fresh complete Stage 3.4 calibration")
    }

    let staleEvidence = try fixture.revalidationEvidence(
      context: registration.applicability,
      frameTime: 840,
      timestamp: 850
    )
    if case .quarantined = loaded.revalidate(with: staleEvidence) {
    } else {
      Issue.record("evidence older than acceptance must remain quarantined")
    }

    var corrupted = try Data(contentsOf: url)
    corrupted[corrupted.startIndex] ^= 0x01
    try corrupted.write(to: url, options: [.atomic])
    if case .rejected = store.load() {
    } else {
      Issue.record("corrupted checkpoint bytes must never load as quarantined authority")
    }
  }

  @Test("Repeated checkpoint revalidation preserves the durable source revision")
  func repeatedCheckpointRevalidationPreservesSourceRevision() throws {
    let fixture = try TipAuthorityFixture()
    let original = try fixture.registration()
    let first = try original.revalidatedFromCheckpoint(
      evidence: fixture.revalidationEvidence(
        context: original.applicability,
        frameTime: 900,
        timestamp: 950
      ),
      acceptedRevisionID: LearningArtifactRevisionID(),
      machineCameraRegistrationRevisionID: fixture.machineCameraRevision,
      observationArtifactRevisionIDs: Dictionary(
        uniqueKeysWithValues:
          original.observationEvidence.map { ($0.observationID, LearningArtifactRevisionID()) }
      ),
      acceptedAt: fixture.timestamp(1_000)
    )
    let second = try first.revalidatedFromCheckpoint(
      evidence: fixture.revalidationEvidence(
        context: first.applicability,
        frameTime: 1_100,
        timestamp: 1_150
      ),
      acceptedRevisionID: LearningArtifactRevisionID(),
      machineCameraRegistrationRevisionID: fixture.machineCameraRevision,
      observationArtifactRevisionIDs: Dictionary(
        uniqueKeysWithValues:
          first.observationEvidence.map { ($0.observationID, LearningArtifactRevisionID()) }
      ),
      acceptedAt: fixture.timestamp(1_200)
    )

    guard case .checkpointRevalidated(let sourceRevision, _) = second.derivation else {
      Issue.record("A repeatedly restored checkpoint must retain revalidation provenance.")
      return
    }
    #expect(sourceRevision == original.acceptedRevisionID)
  }

  @Test("Artifact graph enforces exact tip-calibration dependency shapes")
  func graphEnforcesDependencyShapesAndTransitiveInvalidation() throws {
    let fixture = try TipAuthorityFixture()
    let registration = try fixture.registration()
    var graph = LearningDependencyGraph()
    let machine = try graph.commitReplacement(
      LearningArtifactRevision(
        id: registration.machineCameraRegistrationRevisionID,
        kind: .machineCameraRegistration,
        attemptID: ExerciseAttemptID(),
        disposition: .succeeded
      )
    ).currentRevision

    let invalidObservationID = ToolContactObservationID()
    #expect(
      throws: LearningDependencyGraphError.invalidDependencyShape(
        .toolContactObservation(invalidObservationID)
      )
    ) {
      try graph.commitReplacement(
        LearningArtifactRevision(
          kind: .toolContactObservation(invalidObservationID),
          attemptID: ExerciseAttemptID(),
          disposition: .succeeded
        )
      )
    }

    var observations: [LearningArtifactRevision] = []
    for evidence in registration.observationEvidence {
      observations.append(
        try graph.commitReplacement(
          LearningArtifactRevision(
            id: evidence.observationArtifactRevisionID,
            kind: .toolContactObservation(evidence.observationID),
            attemptID: ExerciseAttemptID(),
            disposition: .succeeded,
            consumedRevisionIDs: [machine.id]
          )
        ).currentRevision)
    }
    #expect(
      throws: LearningDependencyGraphError.invalidDependencyShape(.tipCameraRegistration)
    ) {
      try graph.commitReplacement(
        LearningArtifactRevision(
          kind: .tipCameraRegistration,
          attemptID: ExerciseAttemptID(),
          disposition: .succeeded,
          consumedRevisionIDs: Set(observations.prefix(4).map(\.id)).union([machine.id])
        )
      )
    }
    let tip = try graph.commitReplacement(
      LearningArtifactRevision(
        id: registration.acceptedRevisionID,
        kind: .tipCameraRegistration,
        attemptID: ExerciseAttemptID(),
        disposition: .succeeded,
        consumedRevisionIDs: Set(observations.map(\.id)).union([machine.id])
      )
    ).currentRevision

    let replaced = observations[0]
    let replacement = try graph.commitReplacement(
      LearningArtifactRevision(
        kind: replaced.kind,
        attemptID: ExerciseAttemptID(),
        disposition: .succeeded,
        consumedRevisionIDs: [machine.id]
      )
    )

    #expect(replacement.supersededRevisionID == replaced.id)
    #expect(replacement.invalidatedRevisionIDs == [tip.id])
    #expect(graph.revision(id: tip.id)?.state == .invalidated)
    #expect(graph.currentRevision(for: .tipCameraRegistration) == nil)
  }
}

private enum TipFixtureError: Error {
  case unexpected(String)
}

private struct TipAuthorityFixture {
  let source = FrameSourceIdentity.live(CameraDeviceID(rawValue: "camera-a"))
  let captureSession = CameraCaptureSessionID()
  let optical: CameraOpticalConfigurationIdentity
  let cameraConfigurationID = CameraConfigurationID()
  let machineGeometry = MachineGeometryIdentity()
  let coordinateFrame = MachineCoordinateFrameRevision(rawValue: 11)
  let toolAssembly = ToolAssemblyRevision()
  let contactProfile = PenContactProfileRevision()
  let paper = PaperContactPlaneRevision()
  let machineCameraRevision = LearningArtifactRevisionID()
  let mountRevision = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!

  init() throws {
    optical = try Self.makeOptical(
      source: source,
      width: 640,
      height: 480,
      mountRevision: mountRevision
    )
  }

  func optical(
    width: Int,
    height: Int,
    mountRevision: UUID? = nil
  ) throws -> CameraOpticalConfigurationIdentity {
    try Self.makeOptical(
      source: source,
      width: width,
      height: height,
      mountRevision: mountRevision ?? self.mountRevision
    )
  }

  func context(paper: PaperContactPlaneRevision? = nil) -> TipCalibrationApplicabilityContext {
    TipCalibrationApplicabilityContext(
      opticalConfiguration: optical,
      machineGeometry: machineGeometry,
      machineCoordinateFrame: coordinateFrame,
      toolAssembly: toolAssembly,
      penContactProfile: contactProfile,
      paperContactPlane: paper ?? self.paper
    )
  }

  func observation(
    position: ToolContactCalibrationPosition,
    disposition: ToolContactObservationDisposition = .accepted,
    penDown: PenOutcome = .commandedAndSettled(command: .lower, commandedState: .down),
    penProfile: PenActuationProfile = .initialDefaults,
    clickOffsetX: Double = 0.5,
    machinePointOverride: Point2<MachineSpace>? = nil,
    markPositionResidualMM: Double = 0.01,
    markGeometryCenterResidualMM: Double = 0,
    revealPositionResidualMM: Double = 0.01,
    capPredictionOffsetAtMark: Double = 2,
    paper: PaperContactPlaneRevision? = nil,
    timeOffset: UInt64 = 0
  ) throws -> ToolContactObservation {
    let machinePoint = try machinePointOverride ?? calibrationPoint(position)
    let intended = MachinePosition(point: machinePoint)
    let actual = try MachinePosition(x: machinePoint.x + markPositionResidualMM, y: machinePoint.y)
    let markGeometryCenter = try MachinePosition(
      x: machinePoint.x + markGeometryCenterResidualMM,
      y: machinePoint.y
    )
    let revealActual = try MachinePosition(
      x: machinePoint.x + revealPositionResidualMM,
      y: machinePoint.y
    )
    let pre = try frame(id: "pre-\(position.rawValue)", hashCharacter: "a", time: 100 + timeOffset)
    let post = try frame(
      id: "post-\(position.rawValue)",
      hashCharacter: "b",
      time: 400 + timeOffset
    )
    let preCap = try capEstimate(frame: pre, x: 321, y: 230)
    let postCap = try capEstimate(frame: post, x: 322, y: 231)
    let controllerEvidence = try ControllerContextEvidenceReference(
      passiveProbeID: UUID(),
      evidenceSHA256: String(repeating: "c", count: 64),
      algorithmRevision: "controller-context-v1"
    )
    let predicted = try registrationTransform().applying(to: actual.point)
    let click = try Point2<CameraPixelSpace>(
      x: predicted.x + clickOffsetX,
      y: predicted.y
    )
    return try ToolContactObservation(
      attemptID: ExerciseAttemptID(),
      operationID: ToolContactOperationID(),
      calibrationPosition: position,
      intendedMarkPosition: intended,
      actualSettledPosition: actual,
      machineGeometry: machineGeometry,
      controllerSessionID: UUID(),
      machineCoordinateFrame: coordinateFrame,
      controllerContextEvidence: controllerEvidence,
      markGeometry: ToolContactMarkGeometryEvidence(
        center: markGeometryCenter,
        radiusMM: 2,
        chordCount: 16,
        maximumFeedMMPerMinute: 100
      ),
      penDown: PenActuationEvidence(
        outcome: penDown,
        profile: penProfile,
        timestamp: timestamp(200 + timeOffset)
      ),
      penUp: PenActuationEvidence(
        outcome: .commandedAndSettled(command: .raise, commandedState: .up),
        profile: penProfile,
        timestamp: timestamp(300 + timeOffset)
      ),
      toolAssembly: toolAssembly,
      penContactProfile: contactProfile,
      paperContactPlane: paper ?? self.paper,
      preMarkFrame: pre,
      preMarkCapEstimate: preCap,
      revealEvidence: ToolContactRevealEvidence(
        intendedPosition: intended,
        actualSettledPosition: revealActual,
        settledAt: timestamp(350 + timeOffset),
        controllerContextEvidence: controllerEvidence,
        frame: post,
        capEstimate: postCap,
        capMapPrediction: Point2(x: postCap.point.x + 1, y: postCap.point.y),
        maximumCapMapResidualPixels: 2
      ),
      click: ToolContactClickEvidence(
        point: click,
        pointingUncertaintyPixels: Vector2(dx: 1.5, dy: 1.5),
        timestamp: timestamp(500 + timeOffset),
        presentationTransformRevision: PresentationTransformRevision()
      ),
      capMapPredictionAtMark: Point2(
        x: preCap.point.x + capPredictionOffsetAtMark,
        y: preCap.point.y
      ),
      disposition: disposition,
      consumedLearningArtifactRevisionIDs: [machineCameraRevision],
      algorithmRevisions: [
        AlgorithmRevisionEvidence(component: "contact-observation", revision: "circle-v1")
      ]
    )
  }

  func registration(clickOffsetAtNegativeY: Double = 0.5) throws -> TipCameraRegistration {
    let observations = try ToolContactCalibrationPosition.allCases.map { position in
      try AcceptedToolContactObservation(
        artifactRevisionID: LearningArtifactRevisionID(),
        observation: observation(
          position: position,
          clickOffsetX: position == .negativeY ? clickOffsetAtNegativeY : 0.5
        )
      )
    }
    let selection = try TipCalibrationModelSelection.fitAffineFirst(
      acceptedObservations: observations,
      capCameraFromMachine: registrationTransform()
    )
    return try TipCameraRegistration(
      modelForm: selection.modelForm,
      cameraFromMachine: selection.finalCameraFromMachine,
      modelSelectionEvidence: selection.evidence,
      uncertainty: selection.uncertainty,
      applicabilityRectangle: AxisAlignedBounds(minX: 0, minY: 0, maxX: 100, maxY: 100),
      acceptedObservations: observations,
      applicability: context(),
      acceptedRevisionID: LearningArtifactRevisionID(),
      machineCameraRegistrationRevisionID: machineCameraRevision,
      estimatorRevision: "tip-affine-fit-v1",
      acceptedAt: timestamp(800)
    )
  }

  func revalidationEvidence(
    context: TipCalibrationApplicabilityContext,
    frameTime: UInt64,
    timestamp evidenceTime: UInt64,
    capPredictionOffset: Double = 1,
    maximumCapResidual: Double = 2
  ) throws -> TipCalibrationRevalidationEvidence {
    let frame = try ExactTipCalibrationFrame(
      frameID: FrameID(rawValue: "revalidation-\(frameTime)"),
      frameSHA256: String(repeating: "d", count: 64),
      source: source,
      captureSessionID: CameraCaptureSessionID(),
      opticalConfiguration: context.opticalConfiguration,
      cameraConfigurationID: cameraConfigurationID,
      captureNanoseconds: frameTime,
      width: context.opticalConfiguration.width,
      height: context.opticalConfiguration.height,
      pixelFormat: context.opticalConfiguration.pixelFormat
    )
    let cap = try capEstimate(frame: frame, x: 321, y: 230)
    return try TipCalibrationRevalidationEvidence(
      currentApplicability: context,
      currentMachineCameraRegistrationRevisionID: machineCameraRevision,
      controllerContextEvidence: ControllerContextEvidenceReference(
        passiveProbeID: UUID(),
        evidenceSHA256: String(repeating: "e", count: 64),
        algorithmRevision: "controller-context-v1"
      ),
      frame: frame,
      capEstimate: cap,
      capMapPrediction: Point2(x: cap.point.x + capPredictionOffset, y: cap.point.y),
      maximumCapMapResidualPixels: maximumCapResidual,
      timestamp: timestamp(evidenceTime),
      algorithmRevision: "tip-checkpoint-revalidation-v1"
    )
  }

  func timestamp(_ nanoseconds: UInt64) -> RuntimeTimestamp {
    RuntimeTimestamp(
      monotonicNanoseconds: nanoseconds,
      wallTime: Date(timeIntervalSince1970: Double(nanoseconds) / 1_000)
    )
  }

  private func calibrationPoint(
    _ position: ToolContactCalibrationPosition
  ) throws -> Point2<MachineSpace> {
    switch position {
    case .center: try Point2(x: 50, y: 50)
    case .negativeX: try Point2(x: 10, y: 50)
    case .positiveY: try Point2(x: 50, y: 90)
    case .positiveX: try Point2(x: 90, y: 50)
    case .negativeY: try Point2(x: 50, y: 10)
    }
  }

  private func registrationTransform() throws
    -> AffineTransform2<MachineSpace, CameraPixelSpace>
  {
    try AffineTransform2(m11: 2, m12: 0, m21: 0, m22: 3, tx: 10, ty: 20)
  }

  private func capEstimate(
    frame: ExactTipCalibrationFrame,
    x: Double,
    y: Double
  ) throws -> ToolCapAnchorEstimate {
    try ToolCapAnchorEstimate(
      componentCentroid: Point2(x: x, y: y),
      componentBounds: AxisAlignedBounds(
        minX: x - 10,
        minY: y - 20,
        maxX: x + 10,
        maxY: y + 10
      ),
      confidence: 0.95,
      estimatorRevision: "cap-estimator-v1",
      source: source,
      frameID: frame.frameID,
      cameraConfigurationID: cameraConfigurationID
    )
  }

  private func frame(
    id: String,
    hashCharacter: Character,
    time: UInt64
  ) throws -> ExactTipCalibrationFrame {
    try ExactTipCalibrationFrame(
      frameID: FrameID(rawValue: id),
      frameSHA256: String(repeating: hashCharacter, count: 64),
      source: source,
      captureSessionID: captureSession,
      opticalConfiguration: optical,
      cameraConfigurationID: cameraConfigurationID,
      captureNanoseconds: time,
      width: optical.width,
      height: optical.height,
      pixelFormat: optical.pixelFormat
    )
  }

  private static func makeOptical(
    source: FrameSourceIdentity,
    width: Int,
    height: Int,
    mountRevision: UUID
  ) throws -> CameraOpticalConfigurationIdentity {
    try CameraOpticalConfigurationIdentity(
      source: source,
      sensorFormat: "native-sensor-format",
      width: width,
      height: height,
      pixelFormat: .gray8,
      orientation: .up,
      mirrored: false,
      digitalZoomFactor: 1,
      lensIdentity: "fixed-lens",
      focusConfiguration: "locked",
      mountRevision: mountRevision,
      reframingRevision: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
    )
  }
}
