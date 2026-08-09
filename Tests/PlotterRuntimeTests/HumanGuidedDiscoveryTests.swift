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

  @Test("Boundary Stop orders settlement, exact evidence, and one atomic aggregate commit")
  func boundaryStopOrdering() throws {
    let definition = DiscoverySequenceCatalog.definition(for: .boundaryPositiveX)
    #expect(
      definition.steps.map(\.id) == [
        "announce-jog", "start-jog", "stop-boundary", "cancel-and-idle",
        "capture-frame", "measure-boundary", "commit-boundary-observation",
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
    #expect(transaction.currentStep?.id == "capture-frame")
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
    let firstCamera = CameraConfigurationID()
    let secondCamera = CameraConfigurationID()
    let aggregates = try [
      aggregate(.negativeX, positions: [(-351.473, -38.877, firstCamera)], session: session),
      aggregate(.positiveX, positions: [(-164.923, -38.877, secondCamera)], session: session),
      aggregate(.negativeY, positions: [(-351.473, -76.534, firstCamera)], session: session),
      aggregate(.positiveY, positions: [(-351.473, 82.633, secondCamera)], session: session),
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
      aggregate(.negativeX, positions: [(-10, 0, CameraConfigurationID())], session: session),
      aggregate(.positiveX, positions: [(10, 0, CameraConfigurationID())], session: session),
      aggregate(.negativeY, positions: [(0, -10, CameraConfigurationID())], session: session),
      aggregate(.positiveY, positions: [(0, 10, CameraConfigurationID())], session: UUID()),
    ]
    #expect(throws: EstimatedMachineCenterError.incompatibleControllerContext) {
      _ = try EstimatedMachineCenter.derive(from: aggregates)
    }
    #expect(throws: LearnedLocalCoordinateFrameError.incompatibleControllerContext) {
      _ = try LearnedLocalCoordinateFrame.derive(from: aggregates)
    }
  }

  @Test("camera changes do not split numeric Boundary aggregation")
  func cameraAgnosticNumericCompatibility() throws {
    let cameras = [CameraConfigurationID(), CameraConfigurationID(), CameraConfigurationID()]
    let side = try aggregate(
      .positiveX,
      positions: [(10, 0, cameras[0]), (12, 0, cameras[1]), (14, 0, cameras[2])],
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

  @Test("same camera contact point for all machine sides is irrelevant to side identity")
  func sameNearestEdgeIsIrrelevant() throws {
    let session = UUID()
    let camera = CameraConfigurationID()
    let contact = try Point2<CameraPixelSpace>(x: 100, y: 100)
    let aggregates = try [
      aggregate(.negativeX, positions: [(-10, 0, camera)], session: session, contact: contact),
      aggregate(.positiveX, positions: [(10, 0, camera)], session: session, contact: contact),
      aggregate(.negativeY, positions: [(0, -5, camera)], session: session, contact: contact),
      aggregate(.positiveY, positions: [(0, 5, camera)], session: session, contact: contact),
    ]
    #expect(try EstimatedMachineCenter.derive(from: aggregates).point == Point2(x: 0, y: 0))
  }

  @Test("exact attempt evidence retains owner, Stop, final MPos, exact frame, and contact estimator")
  func exactAttemptEvidence() throws {
    let attemptID = ExerciseAttemptID()
    let ownerID = BoundaryMotionOwnerID()
    let stopCapabilityID = UUID()
    let camera = CameraConfigurationID()
    let evidence = try boundaryEvidence(
      attemptID: attemptID,
      direction: .negativeX,
      x: -351.473,
      y: -38.877,
      session: UUID(),
      camera: camera,
      ownerID: ownerID,
      stopCapabilityID: stopCapabilityID
    )
    #expect(evidence.attemptID == attemptID)
    #expect(evidence.ownerID == ownerID)
    #expect(evidence.stopCapabilityID == stopCapabilityID)
    #expect(evidence.stopIntent == .operatorStop)
    #expect(evidence.finalPosition.point.x == -351.473)
    #expect(evidence.frameSource == .simulated)
    #expect(evidence.frameSHA256.hasPrefix("sha-"))
    #expect(evidence.captureNanoseconds == 100)
    #expect(evidence.cameraConfigurationID == camera)
    #expect(evidence.contactEstimatorRevision == "component-bottom-center-v1")
    #expect(evidence.contactConfidence == 0.9)
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
    #expect(registration.contactEstimatorRevision == "component-bottom-center-v1")
    #expect(provenance.allSatisfy { !$0.frameSHA256.isEmpty })
    #expect(provenance.map(\.captureNanoseconds) == [100, 101, 102, 103])
    #expect(Set(provenance.map(\.attemptID)).count == 4)
  }

  @Test("optical registration rejects camera and contact-estimator mismatches")
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
      contactEstimatorRevision: "different-contact-estimator"
    )
    #expect(throws: MachineCameraRegistrationError.correspondenceContactEstimatorMismatch) {
      _ = try makeRegistration(fit: fit, provenance: wrongEstimator, context: context)
    }
  }

  @Test("tool contact is component bottom-center and not its centroid")
  func contactPointDistinctFromCentroid() throws {
    let estimate = try ToolContactPointEstimate(
      componentCentroid: Point2(x: 20, y: 10),
      componentBounds: AxisAlignedBounds(minX: 12, minY: 2, maxX: 24, maxY: 18),
      confidence: 0.9,
      estimatorRevision: "component-bottom-center-v1",
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
  positions: [(Double, Double, CameraConfigurationID)],
  session: UUID,
  coordinateRevision: UInt64 = 7,
  contact: Point2<CameraPixelSpace>? = nil
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
      coordinateRevision: coordinateRevision,
      camera: position.2,
      contact: contact
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
  camera: CameraConfigurationID,
  ownerID: BoundaryMotionOwnerID = BoundaryMotionOwnerID(),
  stopCapabilityID: UUID = UUID(),
  contact: Point2<CameraPixelSpace>? = nil
) throws -> BoundarySideAttemptEvidence {
  let frameID = FrameID(rawValue: "frame-\(attemptID.rawValue.uuidString)")
  let contactPoint: Point2<CameraPixelSpace>
  if let contact {
    contactPoint = contact
  } else {
    contactPoint = try Point2(x: 100, y: 100)
  }
  let estimate = try ToolContactPointEstimate(
    componentCentroid: Point2(x: contactPoint.x, y: contactPoint.y - 2),
    componentBounds: AxisAlignedBounds(
      minX: contactPoint.x - 2,
      minY: contactPoint.y - 4,
      maxX: contactPoint.x + 2,
      maxY: contactPoint.y
    ),
    confidence: 0.9,
    estimatorRevision: "component-bottom-center-v1",
    source: .simulated,
    frameID: frameID,
    cameraConfigurationID: camera
  )
  return try BoundarySideAttemptEvidence(
    attemptID: attemptID,
    direction: direction,
    controllerSessionID: session,
    coordinateRevision: coordinateRevision,
    ownerID: ownerID,
    stopCapabilityID: stopCapabilityID,
    stopIntent: .operatorStop,
    finalPosition: MachinePosition(x: x, y: y),
    frameSource: .simulated,
    frameID: frameID,
    frameSHA256: "sha-\(attemptID.rawValue.uuidString)",
    captureNanoseconds: 100,
    cameraConfigurationID: camera,
    contactPoint: estimate,
    disposition: .succeeded
  )
}

private func registrationPairs() throws -> [MachineCameraRegistrationCorrespondence] {
  try [(0.0, 0.0), (10.0, 0.0), (0.0, 10.0), (10.0, 10.0)].map { x, y in
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
  contactEstimatorRevision: String = "component-bottom-center-v1"
) -> MachineCameraCorrespondenceProvenance {
  MachineCameraCorrespondenceProvenance(
    machinePoint: pair.machine,
    contactPoint: pair.camera,
    source: .simulated,
    controllerSessionID: context.session,
    coordinateRevision: context.coordinateRevision,
    frameID: FrameID(rawValue: "correspondence-\(index)"),
    frameSHA256: "sha-\(index)",
    captureNanoseconds: UInt64(100 + index),
    cameraConfigurationID: camera ?? context.camera,
    attemptID: ExerciseAttemptID(),
    contactEstimatorRevision: contactEstimatorRevision,
    algorithmRevision: "test-correspondence-v1",
    contactConfidence: 0.9,
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
  try MachineCameraRegistration(
    fit: fit,
    source: .simulated,
    controllerSessionID: context.session,
    coordinateRevision: context.coordinateRevision,
    cameraConfigurationID: context.camera,
    correspondenceProvenance: provenance,
    validationTargetFrameID: FrameID(rawValue: "target-validation"),
    validationMachinePoint: Point2(x: 4, y: 3),
    validationContactPoint: Point2(x: 4, y: 3),
    maximumValidationResidualPixels: 0.25,
    estimatorRevision: "affine-fit-v1",
    uncertaintyPixels: 0.1
  )
}
