import Foundation
import PlotterModel
import Testing

@testable import PlotterRuntime

@Suite("Tip applicability evidence policy")
struct TipApplicabilityEvidencePolicyTests {
  @Test("calibration domains share drawing containment at floating-point edges")
  func domainRoundoffUsesSharedContainment() throws {
    let registration = try TipAuthorityFixture().registration()
    let edge = try Point2<MachineSpace>(x: registration.applicabilityRectangle.maxX.nextUp, y: 50)
    #expect(!registration.applicabilityRectangle.contains(edge))
    #expect(DrawingRegionContainmentPolicy.contains(edge, in: registration.applicabilityRectangle))
    #expect(try registration.tipPixel(at: edge) == registration.cameraFromMachine.applying(to: edge))
    #expect(try registration.diagnosticProjection(at: edge).applicability == .insideRecordedApplicability)
    let path = try Polyline(points: [Point2<MachineSpace>(x: 50, y: 50), edge])
    let projection = try TipApplicabilityEvidencePolicy.project(paths: [path], using: registration)
    #expect(projection.diagnosticLimitation == nil)
    #expect(projection.attributableCameraPolylines?.first?.points.count == 2)
  }

  @Test("outside projection remains diagnostic but cannot enter evidence")
  func outsideProjectionIsDiagnosticOnly() throws {
    let registration = try TipAuthorityFixture().registration()
    let outside = try Point2<MachineSpace>(x: -0.001, y: 50)
    let expected = try registration.cameraFromMachine.applying(to: outside)

    let diagnostic = try registration.diagnosticProjection(at: outside)

    #expect(diagnostic.registrationRevisionID == registration.acceptedRevisionID)
    #expect(diagnostic.recordedApplicabilityRectangle == registration.applicabilityRectangle)
    #expect(diagnostic.machinePoint == outside)
    #expect(diagnostic.cameraPoint == expected)
    #expect(diagnostic.applicability == .outsideRecordedApplicability)
    #expect(throws: GeometryError.outsideDomain) {
      try registration.tipPixel(at: outside)
    }
  }

  @Test("evidence projection is all-or-nothing and gates observer invocation")
  func evidenceProjectionIsAllOrNothing() async throws {
    let registration = try TipAuthorityFixture().registration()
    let inside = try Polyline<MachineSpace>(points: [
      Point2(x: 0, y: 0),
      Point2(x: 100, y: 100),
    ])
    let mixed = try Polyline<MachineSpace>(points: [
      Point2(x: 50, y: 50),
      Point2(x: 100.001, y: 50),
    ])

    let attributable = try TipApplicabilityEvidencePolicy.project(
      paths: [inside],
      using: registration
    )
    let projected = attributable.attributableCameraPolylines
    #expect(projected?.count == 1)
    let expectedPoints = try inside.points.map { try registration.tipPixel(at: $0) }
    #expect(projected?[0].points == expectedPoints)

    let diagnostic = try TipApplicabilityEvidencePolicy.project(
      paths: [inside, mixed],
      using: registration
    )
    let limitation = try #require(diagnostic.diagnosticLimitation)
    #expect(diagnostic.attributableCameraPolylines == nil)
    #expect(limitation.registrationRevisionID == registration.acceptedRevisionID)
    #expect(limitation.firstOutsideMachinePoint == mixed.points[1])
    #expect(limitation.recordedApplicabilityRectangle == registration.applicabilityRectangle)
  }

  @Test("only a distinct accepted registration expansion makes the same path attributable")
  func expandedAcceptedRevisionChangesApplicability() throws {
    let fixture = try TipAuthorityFixture()
    let original = try fixture.registration()
    let expanded = try expandedRegistration(fixture)
    let path = try Polyline<MachineSpace>(points: [
      Point2(x: -5, y: 50),
      Point2(x: 10, y: 50),
    ])

    #expect(original.acceptedRevisionID != expanded.acceptedRevisionID)
    let originalProjection = try TipApplicabilityEvidencePolicy.project(
      paths: [path],
      using: original
    )
    #expect(originalProjection.diagnosticLimitation != nil)
    let expandedProjection = try TipApplicabilityEvidencePolicy.project(
      paths: [path],
      using: expanded
    )
    #expect(expandedProjection.diagnosticLimitation == nil)
  }

  @Test("completed outside-applicability runs persist as non-attributable")
  func nonAttributableRunEvidenceIsTypedAndDurable() throws {
    let parts = try drawingEvidenceParts()
    let record = try DrawingRunEvidenceRecord(
      runID: RunID(),
      requestID: UUID(),
      role: .evaluationHoldout,
      evidenceDisposition: .nonAttributable,
      requestFrontier: .admitted,
      executionFrontiers: DrawingRunExecutionFrontiers(
        plannedStrokeCount: 1,
        commandedStrokeCount: 1,
        controllerCompletedStrokeCount: 1,
        inkVerifiedStrokeCount: 0
      ),
      executionDisposition: .completed,
      program: parts.program,
      placement: parts.placement,
      plan: parts.plan,
      planningProvenance: parts.planning,
      tipCalibration: parts.tip,
      paper: parts.paper,
      observation: .notAttempted(.projectionOutsideTipApplicability),
      recordedAt: RuntimeTimestamp(monotonicNanoseconds: 300)
    )

    #expect(record.readinessReference.disposition == .nonAttributable)
    #expect(record.schemaVersion == 3)
    #expect(record.executionFrontiers.inkVerifiedStrokeCount == 0)
    #expect(record.observation == .notAttempted(.projectionOutsideTipApplicability))
    let restored = try JSONDecoder().decode(
      DrawingRunEvidenceRecord.self,
      from: JSONEncoder().encode(record)
    )
    #expect(restored == record)
    var oldSchemaObject = try #require(
      JSONSerialization.jsonObject(with: JSONEncoder().encode(record)) as? [String: Any]
    )
    oldSchemaObject["schemaVersion"] = 2
    let mislabeledOldSchema = try JSONSerialization.data(withJSONObject: oldSchemaObject)
    #expect(throws: DrawingRunEvidenceError.unsupportedSchema(2)) {
      try JSONDecoder().decode(DrawingRunEvidenceRecord.self, from: mislabeledOldSchema)
    }

    #expect(throws: DrawingRunEvidenceError.incompatibleDisposition) {
      try DrawingRunEvidenceRecord(
        runID: RunID(),
        requestID: UUID(),
        role: .ordinaryDrawing,
        evidenceDisposition: .attributable,
        requestFrontier: .admitted,
        executionFrontiers: DrawingRunExecutionFrontiers(
          plannedStrokeCount: 1,
          commandedStrokeCount: 1,
          controllerCompletedStrokeCount: 1,
          inkVerifiedStrokeCount: 0
        ),
        executionDisposition: .completed,
        program: parts.program,
        placement: parts.placement,
        plan: parts.plan,
        planningProvenance: parts.planning,
        tipCalibration: parts.tip,
        paper: parts.paper,
        observation: .notAttempted(.projectionOutsideTipApplicability),
        recordedAt: RuntimeTimestamp(monotonicNanoseconds: 300)
      )
    }
  }
}

private func expandedRegistration(_ fixture: TipAuthorityFixture) throws -> TipCameraRegistration {
  let observations = try ToolContactCalibrationPosition.allCases.map { position in
    try AcceptedToolContactObservation(
      artifactRevisionID: LearningArtifactRevisionID(),
      observation: fixture.observation(position: position)
    )
  }
  let selection = try TipCalibrationModelSelection.fitAffineFirst(
    acceptedObservations: observations,
    capCameraFromMachine: fixture.registrationTransform()
  )
  return try TipCameraRegistration(
    modelForm: selection.modelForm,
    cameraFromMachine: selection.finalCameraFromMachine,
    modelSelectionEvidence: selection.evidence,
    uncertainty: selection.uncertainty,
    applicabilityRectangle: AxisAlignedBounds(minX: -10, minY: 0, maxX: 100, maxY: 100),
    acceptedObservations: observations,
    applicability: fixture.context(),
    acceptedRevisionID: LearningArtifactRevisionID(),
    machineCameraRegistrationRevisionID: fixture.machineCameraRevision,
    estimatorRevision: "tip-affine-fit-expanded-v1",
    acceptedAt: fixture.timestamp(800)
  )
}
