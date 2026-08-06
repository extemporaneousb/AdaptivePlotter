import Testing

@testable import PlotterModel

@Suite("Current-session online model dataset")
struct OnlineModelDatasetTests {
  @Test("summary exposes fixed split and evidence counts")
  func summaryCounts() throws {
    let accepted = try acceptedModel()
    let training = try observation(id: "training-1", split: .training)
    let holdout = try observation(id: "holdout-1", split: .holdout)
    let accumulator = OnlineModelAccumulator(
      acceptedModel: accepted,
      observations: [training, holdout]
    )

    #expect(
      accumulator.datasetSummary
        == OnlineModelDatasetSummary(
          observationCount: 2,
          trainingCount: 1,
          holdoutCount: 1,
          physicalCount: 0,
          simulatedCount: 2,
          observationIDs: ["training-1", "holdout-1"]
        )
    )
  }

  @Test("episode batch recording is atomic when any identifier is duplicated")
  func batchIsAtomic() throws {
    var accumulator = OnlineModelAccumulator(
      acceptedModel: try acceptedModel(),
      observations: [try observation(id: "existing", split: .training)]
    )
    let before = accumulator.datasetSummary

    #expect(throws: ModelLearningError.duplicateObservationID("existing")) {
      try accumulator.record(
        [
          observation(id: "new-before", split: .training),
          observation(id: "existing", split: .training),
        ],
        at: .penUpBetweenStrokes(identifier: "jog-1")
      )
    }
    #expect(accumulator.datasetSummary == before)
  }

  @Test("episode batches cannot enter the dataset during a pen-down stroke")
  func batchRespectsStrokePin() throws {
    var accumulator = OnlineModelAccumulator(acceptedModel: try acceptedModel())
    _ = try accumulator.beginPenDownStroke(identifier: "stroke-1")

    #expect(throws: ModelLearningError.penDownStrokeActive("stroke-1")) {
      try accumulator.record(
        [
          observation(id: "before", split: .training),
          observation(id: "after", split: .training),
        ],
        at: .penUpBetweenStrokes(identifier: "invalid")
      )
    }
    #expect(accumulator.datasetSummary.observationCount == 0)
  }
}

private func acceptedModel() throws -> AcceptedDrawingModelSnapshot {
  try AcceptedDrawingModelSnapshot(
    version: DrawingModelVersion(rawValue: 1),
    transform: DrawingTransform(
      machineToField: AffineTransform2(
        m11: 1,
        m12: 0,
        m21: 0,
        m22: 1,
        tx: 0,
        ty: 0
      ),
      machineDomain: AxisAlignedBounds(
        minX: -100,
        minY: -40,
        maxX: 100,
        maxY: 40
      )
    ),
    provenance: DrawingModelSnapshotProvenance(
      origin: .prior(name: "current-session-test-prior")
    )
  )
}

private func observation(id: String, split: ModelObservationSplit) throws
  -> DrawingModelTrainingObservation
{
  try DrawingModelTrainingObservation(
    machinePoint: Point2(x: Double(id.count), y: Double(id.count + 1)),
    observedFieldPoint: Point2(x: Double(id.count + 2), y: Double(id.count + 3)),
    split: split,
    provenance: ModelObservationProvenance(
      observationID: id,
      evidence: .simulated(scenarioID: "current-session-dataset-test"),
      algorithmRevision: "dataset-test-v1"
    )
  )
}
