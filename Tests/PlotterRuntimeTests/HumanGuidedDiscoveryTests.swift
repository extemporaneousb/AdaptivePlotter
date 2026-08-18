import Foundation
import PlotterModel
import Testing

@testable import PlotterRuntime

@Suite("Human-Guided Discovery")
struct HumanGuidedDiscoveryTests {
  @Test("operator choices are only contextual YES and NO")
  func contextualChoices() {
    #expect(OperatorChoice.allCases == [.yes, .no])
  }

  @Test("Boundary Stop commits controller settlement without Camera or Vision steps")
  func boundaryStopOrdering() throws {
    let definition = DiscoverySequenceCatalog.definition(for: .boundaryPositiveX)
    #expect(
      definition.steps.map(\.id) == [
        "announce-jog", "start-jog", "stop-boundary", "cancel-and-idle",
        "commit-boundary-observation",
      ])
    #expect(definition.steps[2].action == .awaitContextualStop(.positiveX))
    #expect(definition.steps.last?.action == .commitBoundaryObservation(.positiveX))
    #expect(definition.questions.isEmpty)

    var transaction = DiscoveryTransaction(definition: definition)
    try transaction.begin()
    try transaction.record(.announcementCompleted)
    try transaction.record(.boundaryJogStarted(.positiveX, controllerSummary: "moving"))
    let final = try MachinePosition(x: 12, y: 3)
    #expect(throws: DiscoveryTransactionError.unexpectedEvent(stepID: "stop-boundary")) {
      try transaction.record(
        .boundaryJogCancelled(.positiveX, finalPosition: final, controllerSummary: "Idle")
      )
    }
    try transaction.record(.operatorStopRequested(.positiveX))
    try transaction.record(
      .boundaryJogCancelled(.positiveX, finalPosition: final, controllerSummary: "Idle")
    )
    #expect(transaction.currentStep?.id == "commit-boundary-observation")
    #expect(definition.steps.contains { $0.participant == .camera } == false)
    #expect(definition.steps.contains { $0.participant == .vision } == false)
  }

  @Test("Boundary has no generic choice ceremony or posterior phase")
  func boundaryHasNoQuestionOrPosteriorPhase() {
    for (sequenceID, direction) in [
      (DiscoverySequenceID.boundaryNegativeX, BoundaryDirection.negativeX),
      (.boundaryPositiveX, .positiveX),
      (.boundaryNegativeY, .negativeY),
      (.boundaryPositiveY, .positiveY),
    ] {
      let definition = DiscoverySequenceCatalog.definition(for: sequenceID)
      #expect(definition.questions.isEmpty)
      #expect(definition.steps.dropFirst().first?.action == .startBoundaryJog(direction))
      #expect(
        definition.steps.contains { step in
          if case .commitBoundaryObservation(let actual) = step.action {
            return actual == direction
          }
          return false
        })
      #expect(
        definition.steps.contains { step in
          if case .askQuestion = step.action { return true }
          if case .awaitOperatorChoice = step.action { return true }
          return false
        } == false)
    }

    let pen = DiscoverySequenceCatalog.definition(for: .penInteraction)
    #expect(
      pen.questions.map(\.prompt) == [
        "Is the pen currently up?",
        "Is the pen currently down?",
        "Is the pen up?",
      ])
  }

  @Test("Boundary announcements speak every signed axis without symbol pronunciation")
  func boundaryAnnouncementsUseSignedWords() {
    let expected: [(DiscoverySequenceID, String)] = [
      (.boundaryNegativeX, "Moving the plotter toward the negative X boundary."),
      (.boundaryPositiveX, "Moving the plotter toward the positive X boundary."),
      (.boundaryNegativeY, "Moving the plotter toward the negative Y boundary."),
      (.boundaryPositiveY, "Moving the plotter toward the positive Y boundary."),
    ]

    for (sequenceID, announcement) in expected {
      let definition = DiscoverySequenceCatalog.definition(for: sequenceID)
      #expect(definition.steps.first?.action == .announce(announcement))
    }
  }

  @Test("observed Pen Up advances directly to spoken lowering cue")
  func penUpAdvancesDirectlyToLoweringCue() throws {
    let definition = DiscoverySequenceCatalog.definition(for: .penInteraction)
    var transaction = DiscoveryTransaction(definition: definition)
    try transaction.begin()
    try transaction.record(.questionPresented)
    try transaction.record(.physicalPenConfirmed(
      .up,
      response: .yes,
      operatorSummary: "Operator observed Pen Up."
    ))
    #expect(transaction.currentStep?.id == "announce-down")
    #expect(transaction.currentStep?.action == .announce("Lowering the pen."))
  }

  @Test("every first side forces its opposite then permits either remaining-axis sign")
  func pairedBoundaryOrder() throws {
    for first in BoundaryDirection.allCases {
      var progress = PairedBoundaryProgress()
      try progress.accept(first, revisionID: LearningArtifactRevisionID())
      #expect(progress.allowedDirections == [first.opposite])
      try progress.accept(first.opposite, revisionID: LearningArtifactRevisionID())
      let remaining = BoundaryDirection.allCases.filter { $0.isXAxis != first.isXAxis }
      #expect(progress.allowedDirections == remaining)
      try progress.accept(remaining[0], revisionID: LearningArtifactRevisionID())
      #expect(progress.allowedDirections == [remaining[0].opposite])
      try progress.accept(remaining[0].opposite, revisionID: LearningArtifactRevisionID())
      #expect(progress.isComplete)
    }
  }

  @Test("negative observed fixture derives spans, center, local mapping, and round trip")
  func observedNegativeFixture() throws {
    let session = UUID()
    let aggregates = try [
      aggregate(.negativeX, positions: [(-351.473, -38.877)], session: session),
      aggregate(.positiveX, positions: [(-164.923, -38.877)], session: session),
      aggregate(.negativeY, positions: [(-351.473, -76.534)], session: session),
      aggregate(.positiveY, positions: [(-351.473, 82.633)], session: session),
    ]

    let center = try EstimatedMachineCenter.derive(from: aggregates)
    let local = try LearnedLocalCoordinateFrame.derive(from: aggregates)
    #expect(abs(center.xSpanMM - 186.550) < 1e-9)
    #expect(abs(center.ySpanMM - 159.167) < 1e-9)
    #expect(abs(center.point.x - (-258.198)) < 1e-9)
    #expect(abs(center.point.y - 3.0495) < 1e-9)
    #expect(center.consumedRevisionIDs == Set(aggregates.map(\.revisionID)))
    #expect(local.consumedAggregateRevisionIDs.count == 4)

    let lower = try local.localPoint(fromRaw: Point2(x: -351.473, y: -76.534))
    let upper = try local.localPoint(fromRaw: Point2(x: -164.923, y: 82.633))
    let localCenter = try local.localPoint(fromRaw: center.point)
    #expect(lower == (try Point2(x: 0, y: 0)))
    #expect(abs(upper.x - 186.550) < 1e-9)
    #expect(abs(upper.y - 159.167) < 1e-9)
    #expect(abs(localCenter.x - 93.275) < 1e-9)
    #expect(abs(localCenter.y - 79.5835) < 1e-9)
    #expect(try local.rawPoint(fromLocal: localCenter) == center.point)
  }

  @Test("four aggregates reject mixed controller context")
  func aggregateContextMismatch() throws {
    let session = UUID()
    let aggregates = try [
      aggregate(.negativeX, positions: [(-10, 0)], session: session),
      aggregate(.positiveX, positions: [(10, 0)], session: session),
      aggregate(.negativeY, positions: [(0, -10)], session: session),
      aggregate(.positiveY, positions: [(0, 10)], session: UUID()),
    ]
    #expect(throws: EstimatedMachineCenterError.incompatibleControllerContext) {
      _ = try EstimatedMachineCenter.derive(from: aggregates)
    }
    #expect(throws: LearnedLocalCoordinateFrameError.incompatibleControllerContext) {
      _ = try LearnedLocalCoordinateFrame.derive(from: aggregates)
    }
  }

  @Test("Boundary aggregation contains no camera compatibility dimension")
  func machineOnlyNumericCompatibility() throws {
    let side = try aggregate(
      .positiveX,
      positions: [(10, 0), (12, 0), (14, 0)],
      session: UUID()
    )
    #expect(side.validSampleCount == 3)
    #expect(side.estimateMM == 12)
    #expect(side.numericCompatibility.coordinateSpace == .machine)
    #expect(side.numericCompatibility.units == .millimeters)
    #expect(side.includedAttemptIDs.count == 3)
    guard case .sampleStandardDeviation(let deviation) = side.uncertainty else {
      Issue.record("N=3 must expose sample uncertainty")
      return
    }
    #expect(deviation == 2)
  }

  @Test("machine side identity requires no camera contact classification")
  func cameraContactIsAbsentFromSideIdentity() throws {
    let session = UUID()
    let aggregates = try [
      aggregate(.negativeX, positions: [(-10, 0)], session: session),
      aggregate(.positiveX, positions: [(10, 0)], session: session),
      aggregate(.negativeY, positions: [(0, -5)], session: session),
      aggregate(.positiveY, positions: [(0, 5)], session: session),
    ]
    #expect(try EstimatedMachineCenter.derive(from: aggregates).point == Point2(x: 0, y: 0))
  }

  @Test("Boundary attempt evidence retains only controller-side acceptance facts")
  func exactAttemptEvidence() throws {
    let attemptID = ExerciseAttemptID()
    let ownerID = BoundaryMotionOwnerID()
    let stopCapabilityID = UUID()
    let evidence = try boundaryEvidence(
      attemptID: attemptID,
      direction: .negativeX,
      x: -351.473,
      y: -38.877,
      session: UUID(),
      ownerID: ownerID,
      stopCapabilityID: stopCapabilityID
    )
    #expect(evidence.attemptID == attemptID)
    #expect(evidence.ownerID == ownerID)
    #expect(evidence.stopCapabilityID == stopCapabilityID)
    #expect(evidence.stopIntent == .operatorStop)
    #expect(evidence.finalPosition.point.x == -351.473)
    #expect(evidence.disposition == .succeeded)
  }

  @Test("registration retains full exact correspondence provenance")
  func registrationProvenance() throws {
    let context = RegistrationTestContext()
    let pairs = try registrationPairs()
    let fit = try MachineCameraRegistrationFit.fit(correspondences: pairs)
    let provenance = makeRegistrationProvenance(pairs, context: context)
    let registration = try makeRegistration(fit: fit, provenance: provenance, context: context)
    #expect(registration.correspondenceFrameIDs == Set(provenance.map(\.frameID)))
    #expect(registration.correspondenceRevisionIDs == Set(provenance.map(\.artifactRevisionID)))
    #expect(registration.capAnchorEstimatorRevision == "cap-bottom-center-anchor-v1")
    #expect(registration.opticalConfiguration.source == .simulated)
    #expect(registration.applicabilityDerivation == .boundaryEnvelopeInsetAndSymmetricallyReduced(
      safetyMarginMM: 10,
      maximumHalfSpanMM: 30
    ))
    #expect(provenance.allSatisfy { !$0.frameSHA256.isEmpty })
    #expect(provenance.map(\.captureNanoseconds) == [100, 101, 102, 103, 104])
    #expect(Set(provenance.map(\.attemptID)).count == 5)
  }

  @Test("known coordinate translation rebases camera registration without refitting evidence")
  func registrationCoordinateRebase() throws {
    let context = RegistrationTestContext()
    let pairs = try registrationPairs()
    let fit = try MachineCameraRegistrationFit.fit(correspondences: pairs)
    let registration = try makeRegistration(
      fit: fit,
      provenance: makeRegistrationProvenance(pairs, context: context),
      context: context
    )
    let delta = try Vector2<MachineSpace>(dx: 30, dy: -12)
    let rebased = try registration.rebasedForKnownMachineCoordinateChange(
      to: context.coordinateRevision + 1,
      delta: delta
    )
    let formerPoint = try Point2<MachineSpace>(x: 5, y: 5)
    let currentPoint = try formerPoint.translated(by: delta)

    #expect(rebased.coordinateRevision == context.coordinateRevision + 1)
    let rebasedCameraPoint = try rebased.fit.cameraPoint(from: currentPoint)
    let formerCameraPoint = try registration.fit.cameraPoint(from: formerPoint)
    #expect(rebasedCameraPoint.distance(to: formerCameraPoint) < 0.000_001)
    #expect(rebased.applicabilityRectangle.minX == registration.applicabilityRectangle.minX + 30)
    #expect(rebased.applicabilityRectangle.minY == registration.applicabilityRectangle.minY - 12)
    #expect(rebased.fit.maximumErrorPixels < 0.000_001)
  }

  @Test("optical registration rejects camera and cap-anchor-estimator mismatches")
  func opticalCompatibilityMismatch() throws {
    let context = RegistrationTestContext()
    let pairs = try registrationPairs()
    let fit = try MachineCameraRegistrationFit.fit(correspondences: pairs)

    var wrongCamera = makeRegistrationProvenance(pairs, context: context)
    wrongCamera[1] = provenance(
      pair: pairs[1],
      index: 1,
      context: context,
      camera: CameraConfigurationID()
    )
    #expect(throws: MachineCameraRegistrationError.correspondenceCameraMismatch) {
      _ = try makeRegistration(fit: fit, provenance: wrongCamera, context: context)
    }

    var wrongEstimator = makeRegistrationProvenance(pairs, context: context)
    wrongEstimator[2] = provenance(
      pair: pairs[2],
      index: 2,
      context: context,
      capAnchorEstimatorRevision: "different-cap-anchor-estimator"
    )
    #expect(throws: MachineCameraRegistrationError.correspondenceCapAnchorEstimatorMismatch) {
      _ = try makeRegistration(fit: fit, provenance: wrongEstimator, context: context)
    }
  }

  @Test("cap anchor is component bottom-center and not the hidden tip or centroid")
  func capAnchorPointDistinctFromCentroid() throws {
    let estimate = try ToolCapAnchorEstimate(
      componentCentroid: Point2(x: 20, y: 10),
      componentBounds: AxisAlignedBounds(minX: 12, minY: 2, maxX: 24, maxY: 18),
      confidence: 0.9,
      estimatorRevision: "cap-bottom-center-anchor-v1",
      source: .simulated,
      frameID: FrameID(rawValue: "contact-frame"),
      cameraConfigurationID: CameraConfigurationID()
    )
    #expect(estimate.point == (try Point2(x: 18, y: 18)))
    #expect(estimate.point != estimate.componentCentroid)
  }
}

private struct RegistrationTestContext {
  let session = UUID(uuidString: "00000000-0000-0000-0000-000000000101")!
  let coordinateRevision: UInt64 = 9
  let camera = CameraConfigurationID(
    UUID(uuidString: "00000000-0000-0000-0000-000000000102")!
  )
}

private func aggregate(
  _ direction: BoundaryDirection,
  positions: [(Double, Double)],
  session: UUID,
  coordinateRevision: UInt64 = 7
) throws -> BoundarySideAggregate {
  let estimator = AggregateEstimatorIdentity(
    name: "arithmetic-mean",
    revision: "boundary-machine-coordinate-v1"
  )
  let compatibility = BoundaryNumericCompatibility(
    direction: direction,
    controllerSessionID: session,
    coordinateRevision: coordinateRevision,
    numericEstimatorRevision: estimator.revision
  ).attemptCompatibility
  var history = try ExerciseAttemptHistory<BoundarySideAttemptEvidence>(
    compatibility: compatibility
  )
  for (index, position) in positions.enumerated() {
    let attemptID = ExerciseAttemptID()
    let evidence = try boundaryEvidence(
      attemptID: attemptID,
      direction: direction,
      x: position.0,
      y: position.1,
      session: session,
      coordinateRevision: coordinateRevision
    )
    try history.record(ExerciseAttempt(
      id: attemptID,
      disposition: .succeeded,
      compatibility: compatibility,
      acceptedSequence: UInt64(index + 1),
      value: evidence
    ))
  }
  return try BoundarySideAggregate(
    direction: direction,
    history: history,
    estimator: estimator
  )
}

private func boundaryEvidence(
  attemptID: ExerciseAttemptID,
  direction: BoundaryDirection,
  x: Double,
  y: Double,
  session: UUID,
  coordinateRevision: UInt64 = 7,
  ownerID: BoundaryMotionOwnerID = BoundaryMotionOwnerID(),
  stopCapabilityID: UUID = UUID()
) throws -> BoundarySideAttemptEvidence {
  return try BoundarySideAttemptEvidence(
    attemptID: attemptID,
    direction: direction,
    controllerSessionID: session,
    coordinateRevision: coordinateRevision,
    ownerID: ownerID,
    stopCapabilityID: stopCapabilityID,
    stopIntent: .operatorStop,
    finalPosition: MachinePosition(x: x, y: y),
    disposition: .succeeded
  )
}

private func registrationPairs() throws -> [MachineCameraRegistrationCorrespondence] {
  try [(5.0, 5.0), (0.0, 5.0), (5.0, 10.0), (10.0, 5.0), (5.0, 0.0)].map { x, y in
    MachineCameraRegistrationCorrespondence(
      machine: try Point2(x: x, y: y),
      camera: try Point2(x: x, y: y)
    )
  }
}

private func provenance(
  pair: MachineCameraRegistrationCorrespondence,
  index: Int,
  context: RegistrationTestContext,
  camera: CameraConfigurationID? = nil,
  capAnchorEstimatorRevision: String = "cap-bottom-center-anchor-v1"
) -> MachineCameraCorrespondenceProvenance {
  MachineCameraCorrespondenceProvenance(
    machinePoint: pair.machine,
    capAnchorPoint: pair.camera,
    source: .simulated,
    controllerSessionID: context.session,
    coordinateRevision: context.coordinateRevision,
    frameID: FrameID(rawValue: "correspondence-\(index)"),
    frameSHA256: "sha-\(index)",
    captureNanoseconds: UInt64(100 + index),
    cameraConfigurationID: camera ?? context.camera,
    attemptID: ExerciseAttemptID(),
    capAnchorEstimatorRevision: capAnchorEstimatorRevision,
    algorithmRevision: "test-correspondence-v1",
    capAnchorConfidence: 0.9,
    artifactRevisionID: LearningArtifactRevisionID()
  )
}

private func makeRegistrationProvenance(
  _ pairs: [MachineCameraRegistrationCorrespondence],
  context: RegistrationTestContext
) -> [MachineCameraCorrespondenceProvenance] {
  pairs.enumerated().map { provenance(pair: $0.element, index: $0.offset, context: context) }
}

private func makeRegistration(
  fit: MachineCameraRegistrationFit,
  provenance: [MachineCameraCorrespondenceProvenance],
  context: RegistrationTestContext
) throws -> MachineCameraRegistration {
  let candidateFit = try MachineCameraRegistrationFit.fit(
    correspondences: Array(fit.correspondences.prefix(3))
  )
  return try MachineCameraRegistration(
    candidateFit: candidateFit,
    fit: fit,
    source: .simulated,
    opticalConfiguration: try CameraOpticalConfigurationIdentity(
      source: .simulated,
      sensorFormat: "registration-test",
      width: 640,
      height: 480,
      pixelFormat: .bgra8,
      orientation: .up,
      mirrored: false,
      digitalZoomFactor: 1,
      lensIdentity: "simulated-lens",
      focusConfiguration: "fixed-focus",
      mountRevision: UUID(uuidString: "00000000-0000-0000-0000-000000000701")!,
      reframingRevision: UUID(uuidString: "00000000-0000-0000-0000-000000000702")!
    ),
    machineGeometry: MachineGeometryIdentity(),
    controllerSessionID: context.session,
    coordinateRevision: context.coordinateRevision,
    cameraConfigurationID: context.camera,
    fitCorrespondenceProvenance: Array(provenance.prefix(3)),
    holdoutCorrespondenceProvenance: Array(provenance.suffix(2)),
    maximumHoldoutResidualPixels: 0.25,
    estimatorRevision: "affine-fit-v1",
    uncertaintyPixels: 0.1,
    applicabilityRectangle: AxisAlignedBounds(minX: 0, minY: 0, maxX: 10, maxY: 10),
    applicabilityDerivation: .boundaryEnvelopeInsetAndSymmetricallyReduced(
      safetyMarginMM: 10,
      maximumHalfSpanMM: 30
    )
  )
}
