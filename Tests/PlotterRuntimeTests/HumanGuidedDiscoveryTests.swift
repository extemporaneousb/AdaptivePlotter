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

  @Test("boundary sequence makes Stop a distinct event before cancel and evidence")
  func boundaryStopOrdering() throws {
    let definition = DiscoverySequenceCatalog.definition(for: .boundaryPositiveX)
    #expect(
      definition.steps.map(\.id) == [
        "announce-jog", "start-jog", "stop-boundary", "cancel-and-idle",
        "capture-frame", "measure-boundary", "adjust-posterior",
      ])
    #expect(definition.steps[2].action == .awaitContextualStop(.positiveX))
    #expect(definition.questions.isEmpty)

    var transaction = DiscoveryTransaction(definition: definition)
    try transaction.begin()
    try transaction.record(.announcementCompleted)
    try transaction.record(
      .boundaryJogStarted(.positiveX, controllerSummary: "moving")
    )
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

  @Test("boundary starts without contextual YES or NO while Pen Interaction retains prompts")
  func boundaryHasNoReadyQuestionAndPenPromptsRemain() {
    for (sequenceID, direction) in [
      (DiscoverySequenceID.boundaryNegativeX, BoundaryDirection.negativeX),
      (.boundaryPositiveX, .positiveX),
      (.boundaryNegativeY, .negativeY),
      (.boundaryPositiveY, .positiveY),
    ] {
      let definition = DiscoverySequenceCatalog.definition(for: sequenceID)
      #expect(definition.questions.isEmpty)
      #expect(
        definition.steps.first?.action
          == .announce("Moving toward \(direction.displayName) boundary.")
      )
      #expect(definition.steps.dropFirst().first?.action == .startBoundaryJog(direction))
      #expect(
        definition.steps.contains { step in
          if case .askQuestion = step.action { return true }
          return false
        } == false)
      #expect(
        definition.steps.contains { step in
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
    #expect(pen.steps.count == 12)
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
    #expect(definition.questions.count == 3)
    #expect(
      definition.steps.contains { step in
        if case .awaitOperatorChoice = step.action { return true }
        return false
      } == false
    )
  }

  @Test("pen interaction has announcements before both typed actuations")
  func penAnnouncementOrdering() {
    let actions = DiscoverySequenceCatalog.definition(for: .penInteraction).steps.map(\.action)
    let down = actions.firstIndex(of: .actuatePen(.lower))
    let announceDown = actions.firstIndex(of: .announce("Lowering the pen."))
    let up = actions.firstIndex(of: .actuatePen(.raise))
    let announceUp = actions.firstIndex(of: .announce("Raising the pen."))
    #expect(announceDown != nil && down != nil && announceDown! < down!)
    #expect(announceUp != nil && up != nil && announceUp! < up!)
  }

  @Test("controller feed ceiling selects participating axes only")
  func controllerFeedCeiling() throws {
    let limits = ControllerAxisFeedLimits(
      maximumXFeedMMPerMinute: 900,
      maximumYFeedMMPerMinute: 600
    )
    #expect(limits.applicableFeedCeiling(for: try Vector2(dx: 2, dy: 0)) == 900)
    #expect(limits.applicableFeedCeiling(for: try Vector2(dx: 0, dy: -2)) == 600)
    #expect(limits.applicableFeedCeiling(for: try Vector2(dx: 2, dy: -2)) == 600)
    #expect(limits.applicableFeedCeiling(for: try Vector2(dx: 0, dy: 0)) == nil)
  }


  @Test("every first side forces its opposite then permits either remaining-axis sign")
  func pairedBoundaryOrder() throws {
    for first in BoundaryDirection.allCases {
      var progress = PairedBoundaryProgress()
      let firstRevision = LearningArtifactRevisionID()
      try progress.accept(first, revisionID: firstRevision)
      #expect(progress.allowedDirections == [first.opposite])
      try progress.accept(first.opposite, revisionID: LearningArtifactRevisionID())
      let expectedRemaining = BoundaryDirection.allCases.filter { $0.isXAxis != first.isXAxis }
      #expect(progress.allowedDirections == expectedRemaining)
      let third = expectedRemaining.last!
      try progress.accept(third, revisionID: LearningArtifactRevisionID())
      #expect(progress.allowedDirections == [third.opposite])
      try progress.accept(third.opposite, revisionID: LearningArtifactRevisionID())
      #expect(progress.isComplete)
      #expect(progress.allowedDirections.isEmpty)
    }
  }

  @Test("machine center consumes four same-context side revisions without camera compatibility")
  func estimatedCenter() throws {
    let session = UUID()
    let firstCamera = CameraConfigurationID()
    let secondCamera = CameraConfigurationID()
    let observations = try [
      boundary(.negativeX, x: -12, y: 2, session: session, camera: firstCamera),
      boundary(.positiveX, x: 28, y: -1, session: session, camera: secondCamera),
      boundary(.negativeY, x: 4, y: -20, session: session, camera: firstCamera),
      boundary(.positiveY, x: 5, y: 10, session: session, camera: secondCamera),
    ]
    let center = try EstimatedMachineCenter.derive(from: observations)
    #expect(center.point == (try Point2<MachineSpace>(x: 8, y: -5)))
    #expect(center.xSpanMM == 40)
    #expect(center.ySpanMM == 30)
    #expect(center.consumedRevisionIDs == Set(observations.map(\.revisionID)))
    #expect(center.sampleCountByAxis == ["X": 2, "Y": 2])
  }

  @Test("tool contact is component bottom-center and not its centroid")
  func contactPointDistinctFromCentroid() throws {
    let centroid = try Point2<CameraPixelSpace>(x: 20, y: 10)
    let estimate = try ToolContactPointEstimate(
      componentCentroid: centroid,
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

  @Test("registration retains per-correspondence source controller camera and validation provenance")
  func registrationProvenance() throws {
    let context = RegistrationTestContext()
    let pairs = try registrationPairs()
    let fit = try MachineCameraRegistrationFit.fit(correspondences: pairs)
    let provenance = makeRegistrationProvenance(pairs, context: context)
    let validationPoint = try Point2<MachineSpace>(x: 4, y: 3)
    let registration = try MachineCameraRegistration(
      fit: fit,
      source: .simulated,
      controllerSessionID: context.session,
      coordinateRevision: context.coordinateRevision,
      cameraConfigurationID: context.camera,
      correspondenceProvenance: provenance,
      validationTargetFrameID: FrameID(rawValue: "target-validation"),
      validationMachinePoint: validationPoint,
      validationContactPoint: try Point2(x: 4, y: 3),
      maximumValidationResidualPixels: 0.25,
      estimatorRevision: "affine-fit-v1",
      uncertaintyPixels: 0.1
    )

    #expect(registration.validationResidualPixels == 0)
    #expect(registration.correspondenceFrameIDs == Set(provenance.map(\.frameID)))
    #expect(registration.correspondenceRevisionIDs == Set(provenance.map(\.artifactRevisionID)))
  }

  @Test("registration rejects one correspondence from another frame source")
  func registrationSourceMismatch() throws {
    let context = RegistrationTestContext()
    let pairs = try registrationPairs()
    let fit = try MachineCameraRegistrationFit.fit(correspondences: pairs)
    var provenance = makeRegistrationProvenance(pairs, context: context)
    provenance[1] = MachineCameraCorrespondenceProvenance(
      machinePoint: provenance[1].machinePoint,
      contactPoint: provenance[1].contactPoint,
      source: .live(CameraDeviceID(rawValue: "live-camera")),
      controllerSessionID: context.session,
      coordinateRevision: context.coordinateRevision,
      frameID: provenance[1].frameID,
      cameraConfigurationID: context.camera,
      artifactRevisionID: provenance[1].artifactRevisionID
    )
    #expect(throws: MachineCameraRegistrationError.correspondenceSourceMismatch) {
      _ = try makeRegistration(fit: fit, provenance: provenance, context: context)
    }
  }

  @Test("registration rejects one correspondence from another controller context")
  func registrationControllerMismatch() throws {
    let context = RegistrationTestContext()
    let pairs = try registrationPairs()
    let fit = try MachineCameraRegistrationFit.fit(correspondences: pairs)
    var provenance = makeRegistrationProvenance(pairs, context: context)
    provenance[2] = MachineCameraCorrespondenceProvenance(
      machinePoint: provenance[2].machinePoint,
      contactPoint: provenance[2].contactPoint,
      source: .simulated,
      controllerSessionID: UUID(),
      coordinateRevision: context.coordinateRevision,
      frameID: provenance[2].frameID,
      cameraConfigurationID: context.camera,
      artifactRevisionID: provenance[2].artifactRevisionID
    )
    #expect(throws: MachineCameraRegistrationError.correspondenceControllerMismatch) {
      _ = try makeRegistration(fit: fit, provenance: provenance, context: context)
    }
  }

  @Test("registration rejects a target-center validation residual beyond policy")
  func registrationValidationResidual() throws {
    let context = RegistrationTestContext()
    let pairs = try registrationPairs()
    let fit = try MachineCameraRegistrationFit.fit(correspondences: pairs)
    let provenance = makeRegistrationProvenance(pairs, context: context)
    #expect(
      throws: MachineCameraRegistrationError.validationResidualExceeded(
        actualPixels: 10,
        maximumPixels: 1
      )
    ) {
      _ = try MachineCameraRegistration(
        fit: fit,
        source: .simulated,
        controllerSessionID: context.session,
        coordinateRevision: context.coordinateRevision,
        cameraConfigurationID: context.camera,
        correspondenceProvenance: provenance,
        validationTargetFrameID: FrameID(rawValue: "bad-validation"),
        validationMachinePoint: try Point2(x: 4, y: 3),
        validationContactPoint: try Point2(x: 14, y: 3),
        maximumValidationResidualPixels: 1,
        estimatorRevision: "affine-fit-v1",
        uncertaintyPixels: 0.1
      )
    }
  }
}

private struct RegistrationTestContext {
  let session = UUID(uuidString: "00000000-0000-0000-0000-000000000101")!
  let coordinateRevision: UInt64 = 9
  let camera = CameraConfigurationID(
    UUID(uuidString: "00000000-0000-0000-0000-000000000102")!
  )
}

private func registrationPairs() throws -> [MachineCameraRegistrationCorrespondence] {
  try [
    (0.0, 0.0),
    (10.0, 0.0),
    (0.0, 10.0),
    (10.0, 10.0),
  ].map { x, y in
    MachineCameraRegistrationCorrespondence(
      machine: try Point2(x: x, y: y),
      camera: try Point2(x: x, y: y)
    )
  }
}

private func makeRegistrationProvenance(
  _ pairs: [MachineCameraRegistrationCorrespondence],
  context: RegistrationTestContext
) -> [MachineCameraCorrespondenceProvenance] {
  pairs.enumerated().map { index, pair in
    MachineCameraCorrespondenceProvenance(
      machinePoint: pair.machine,
      contactPoint: pair.camera,
      source: .simulated,
      controllerSessionID: context.session,
      coordinateRevision: context.coordinateRevision,
      frameID: FrameID(rawValue: "correspondence-\(index)"),
      cameraConfigurationID: context.camera,
      artifactRevisionID: LearningArtifactRevisionID()
    )
  }
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

private func boundary(
  _ direction: BoundaryDirection,
  x: Double,
  y: Double,
  session: UUID,
  camera: CameraConfigurationID
) throws -> AcceptedBoundarySide {
  AcceptedBoundarySide(
    direction: direction,
    revisionID: LearningArtifactRevisionID(),
    controllerSessionID: session,
    coordinateRevision: 7,
    finalPosition: try MachinePosition(x: x, y: y),
    contactPoint: try ToolContactPointEstimate(
      componentCentroid: Point2(x: x, y: y - 2),
      componentBounds: AxisAlignedBounds(minX: x - 2, minY: y - 4, maxX: x + 2, maxY: y),
      confidence: 0.8,
      estimatorRevision: "component-bottom-center-v1",
      source: .simulated,
      frameID: FrameID(rawValue: "\(direction.rawValue)-\(camera)"),
      cameraConfigurationID: camera
    ),
    sideEstimatorRevision: "side-v1",
    uncertaintyPixels: 0.5
  )
}
