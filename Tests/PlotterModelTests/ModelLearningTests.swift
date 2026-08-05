import Testing

@testable import PlotterModel

@Suite("Drawing model learning")
struct ModelLearningTests {
  @Test("affine candidate converges while the accepted constant offset stays fixed")
  func affineConvergence() throws {
    let accepted = try priorSnapshot()
    let truth = try DrawingTransform(
      machineToField: AffineTransform2(
        m11: 1.8, m12: 0.2, m21: -0.1, m22: 1.4, tx: 5, ty: -3
      ),
      constantFieldCorrection: accepted.transform.constantFieldCorrection,
      machineDomain: accepted.transform.machineDomain
    )
    let observations = try observationSet(truth: truth)
    let candidate = try DrawingModelTrainer.fitCandidate(
      basedOn: accepted,
      observations: observations
    )
    let reorderedCandidate = try DrawingModelTrainer.fitCandidate(
      basedOn: accepted,
      observations: Array(observations.reversed())
    )

    #expect(candidate == reorderedCandidate)
    #expect(candidate.baseVersion == accepted.version)
    #expect(
      candidate.proposedTransform.constantFieldCorrection
        == accepted.transform.constantFieldCorrection
    )
    #expect(candidate.candidateEvaluation.training.rootMeanSquareError < 1e-10)
    #expect(candidate.candidateEvaluation.holdout.rootMeanSquareError < 1e-10)
    #expect(candidate.candidateEvaluation.holdout.maximumError < 1e-10)
    #expect(candidate.baselineEvaluation.holdout.rootMeanSquareError > 1)
  }

  @Test("a training fit that regresses held-out points is rejected")
  func holdoutRejectsNonImprovement() throws {
    let accepted = try priorSnapshot()
    let biased = try DrawingTransform(
      machineToField: AffineTransform2(
        m11: 1, m12: 0, m21: 0, m22: 1, tx: 10, ty: 0
      ),
      constantFieldCorrection: accepted.transform.constantFieldCorrection,
      machineDomain: accepted.transform.machineDomain
    )
    var observations = try [
      observation(machineX: -10, machineY: -10, truth: biased, split: .training, id: "t1"),
      observation(machineX: 10, machineY: -10, truth: biased, split: .training, id: "t2"),
      observation(machineX: -10, machineY: 10, truth: biased, split: .training, id: "t3"),
      observation(machineX: 10, machineY: 10, truth: biased, split: .training, id: "t4"),
    ]
    observations += try [
      observation(
        machineX: -5,
        machineY: 3,
        truth: accepted.transform,
        split: .holdout,
        id: "h1"
      ),
      observation(
        machineX: 8,
        machineY: 7,
        truth: accepted.transform,
        split: .holdout,
        id: "h2"
      ),
    ]
    let candidate = try DrawingModelTrainer.fitCandidate(
      basedOn: accepted,
      observations: observations
    )
    let criteria = try ModelAcceptanceCriteria(
      maximumHoldoutRootMeanSquareError: 100,
      maximumHoldoutError: 100,
      minimumHoldoutRootMeanSquareImprovement: 0
    )
    guard
      case .reject(.insufficientHoldoutImprovement(let improvement, let minimum)) =
        DrawingModelAcceptance.decision(for: candidate, criteria: criteria)
    else {
      Issue.record("expected holdout non-improvement rejection")
      return
    }
    #expect(improvement < 0)
    #expect(minimum == 0)
  }

  @Test("an eligible proposal becomes accepted only through explicit promotion")
  func explicitAcceptance() throws {
    let accepted = try priorSnapshot()
    let truth = try DrawingTransform(
      machineToField: AffineTransform2(
        m11: 1.2, m12: 0.1, m21: -0.05, m22: 0.9, tx: 3, ty: 4
      ),
      constantFieldCorrection: accepted.transform.constantFieldCorrection,
      machineDomain: accepted.transform.machineDomain
    )
    let candidate = try DrawingModelTrainer.fitCandidate(
      basedOn: accepted,
      observations: observationSet(truth: truth)
    )
    let criteria = try ModelAcceptanceCriteria(
      maximumHoldoutRootMeanSquareError: 0.001,
      maximumHoldoutError: 0.001,
      minimumHoldoutRootMeanSquareImprovement: 0.1
    )
    let decision = DrawingModelAcceptance.decision(for: candidate, criteria: criteria)
    #expect(decision == .accept)
    #expect(accepted.version == DrawingModelVersion(rawValue: 1))

    let promoted = try DrawingModelAcceptance.accept(
      candidate,
      replacing: accepted,
      decision: decision,
      as: DrawingModelVersion(rawValue: 2),
      acceptanceNote: "deterministic unit-test holdout passed"
    )
    #expect(promoted.version == DrawingModelVersion(rawValue: 2))
    #expect(accepted.version == DrawingModelVersion(rawValue: 1))
    let probe = try Point2<MachineSpace>(x: 6, y: -2)
    #expect(
      try promoted.predictedFieldPoint(for: probe).distance(
        to: truth.predictedFieldPoint(for: probe)
      ) < 1e-10
    )
  }

  @Test("online proposals are pinned and refused during a pen-down stroke")
  func strokePinning() throws {
    let accepted = try priorSnapshot()
    let truth = try DrawingTransform(
      machineToField: AffineTransform2(
        m11: 1.1, m12: 0.05, m21: 0.02, m22: 0.95, tx: 2, ty: -1
      ),
      constantFieldCorrection: accepted.transform.constantFieldCorrection,
      machineDomain: accepted.transform.machineDomain
    )
    var accumulator = OnlineModelAccumulator(
      acceptedModel: accepted,
      observations: try observationSet(truth: truth)
    )
    let pin = try accumulator.beginPenDownStroke(identifier: "stroke-7")
    #expect(pin.acceptedModel == accepted)
    #expect(pin.acceptedModel.version == DrawingModelVersion(rawValue: 1))
    #expect(throws: ModelLearningError.penDownStrokeActive("stroke-7")) {
      _ = try accumulator.proposeCandidate(
        at: .penUpBetweenStrokes(identifier: "checkpoint-invalid-while-down")
      )
    }

    try accumulator.endPenDownStroke(identifier: "stroke-7")
    let candidate = try accumulator.proposeCandidate(
      at: .penUpBetweenStrokes(identifier: "checkpoint-8")
    )
    #expect(candidate.baseVersion == pin.acceptedModel.version)
    #expect(accumulator.acceptedModel == accepted)
  }
}

private func priorSnapshot() throws -> AcceptedDrawingModelSnapshot {
  try AcceptedDrawingModelSnapshot(
    version: DrawingModelVersion(rawValue: 1),
    transform: DrawingTransform(
      machineToField: AffineTransform2(
        m11: 1, m12: 0, m21: 0, m22: 1, tx: 0, ty: 0
      ),
      constantFieldCorrection: Vector2(dx: 1.5, dy: -2),
      machineDomain: AxisAlignedBounds(minX: -20, minY: -20, maxX: 20, maxY: 20)
    ),
    provenance: DrawingModelSnapshotProvenance(origin: .prior(name: "unit-test-prior"))
  )
}

private func observationSet(truth: DrawingTransform) throws
  -> [DrawingModelTrainingObservation]
{
  try [
    observation(machineX: -10, machineY: -8, truth: truth, split: .training, id: "t1"),
    observation(machineX: 0, machineY: 0, truth: truth, split: .training, id: "t2"),
    observation(machineX: 10, machineY: 0, truth: truth, split: .training, id: "t3"),
    observation(machineX: 0, machineY: 10, truth: truth, split: .training, id: "t4"),
    observation(machineX: 7, machineY: -6, truth: truth, split: .training, id: "t5"),
    observation(machineX: -7, machineY: 6, truth: truth, split: .holdout, id: "h1"),
    observation(machineX: 9, machineY: 9, truth: truth, split: .holdout, id: "h2"),
  ]
}

private func observation(
  machineX: Double,
  machineY: Double,
  truth: DrawingTransform,
  split: ModelObservationSplit,
  id: String
) throws -> DrawingModelTrainingObservation {
  let machine = try Point2<MachineSpace>(x: machineX, y: machineY)
  return try DrawingModelTrainingObservation(
    machinePoint: machine,
    observedFieldPoint: truth.predictedFieldPoint(for: machine),
    split: split,
    provenance: ModelObservationProvenance(
      observationID: id,
      evidence: .simulated(scenarioID: "model-learning-tests"),
      algorithmRevision: "exact-affine-fixture-v1"
    )
  )
}
