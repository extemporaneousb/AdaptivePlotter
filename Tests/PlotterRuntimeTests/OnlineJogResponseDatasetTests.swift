import PlotterModel
import Testing

@testable import PlotterRuntime

@Suite("Current-session jog response diagnostics")
struct OnlineJogResponseDatasetTests {
  @Test("training episodes recover an exact through-origin response matrix")
  func exactKnownMatrix() async throws {
    let configuration = CameraConfigurationID()
    var dataset = try OnlineJogResponseDataset(
      cameraConfigurationID: configuration,
      algorithmRevision: "cap-response-v1"
    )
    try await dataset.record(
      episode(
        id: "train-x",
        split: .training,
        actualDX: 1,
        actualDY: 0,
        cameraDX: 2,
        cameraDY: -1,
        configuration: configuration
      )
    )
    try await dataset.record(
      episode(
        id: "train-y",
        split: .training,
        actualDX: 0,
        actualDY: 1,
        cameraDX: 3,
        cameraDY: 4,
        configuration: configuration
      )
    )

    let candidate = try dataset.proposeCandidate()
    #expect(candidate.matrix.cameraXPerMachineX == 2)
    #expect(candidate.matrix.cameraXPerMachineY == 3)
    #expect(candidate.matrix.cameraYPerMachineX == -1)
    #expect(candidate.matrix.cameraYPerMachineY == 4)
    #expect(candidate.trainingMetrics.episodeCount == 2)
    #expect(candidate.trainingMetrics.rootMeanSquarePixels == 0)
    #expect(candidate.trainingMetrics.maximumPixels == 0)
    #expect(candidate.holdoutMetrics == nil)
  }

  @Test("holdout episodes do not influence fitting and receive separate metrics")
  func splitIsolationAndHoldoutMetrics() async throws {
    let configuration = CameraConfigurationID()
    var dataset = try OnlineJogResponseDataset(
      cameraConfigurationID: configuration,
      algorithmRevision: "cap-response-v1"
    )
    try await dataset.record(
      episode(
        id: "train-x",
        split: .training,
        actualDX: 1,
        actualDY: 0,
        cameraDX: 2,
        cameraDY: -1,
        configuration: configuration
      )
    )
    try await dataset.record(
      episode(
        id: "train-y",
        split: .training,
        actualDX: 0,
        actualDY: 1,
        cameraDX: 3,
        cameraDY: 4,
        configuration: configuration
      )
    )
    try await dataset.record(
      episode(
        id: "holdout-noisy",
        split: .holdout,
        actualDX: 2,
        actualDY: -1,
        cameraDX: 2,
        cameraDY: -6,
        configuration: configuration
      )
    )

    let candidate = try dataset.proposeCandidate()
    #expect(candidate.matrix.cameraXPerMachineX == 2)
    #expect(candidate.matrix.cameraXPerMachineY == 3)
    #expect(candidate.matrix.cameraYPerMachineX == -1)
    #expect(candidate.matrix.cameraYPerMachineY == 4)
    #expect(candidate.trainingMetrics.rootMeanSquarePixels == 0)
    #expect(candidate.holdoutMetrics?.episodeCount == 1)
    #expect(candidate.holdoutMetrics?.rootMeanSquarePixels == 1)
    #expect(candidate.holdoutMetrics?.maximumPixels == 1)
    #expect(
      dataset.summary
        == OnlineJogResponseDatasetSummary(
          episodeCount: 3,
          trainingCount: 2,
          holdoutCount: 1,
          episodeIDs: ["train-x", "train-y", "holdout-noisy"],
          trainingEpisodeIDs: ["train-x", "train-y"],
          holdoutEpisodeIDs: ["holdout-noisy"]
        )
    )
  }

  @Test("dataset rejects duplicate, camera, revision, and zero-motion episodes")
  func recordingInvariants() async throws {
    let configuration = CameraConfigurationID()
    var dataset = try OnlineJogResponseDataset(
      cameraConfigurationID: configuration,
      algorithmRevision: "cap-response-v1"
    )
    let valid = try await episode(
      id: "valid",
      split: .training,
      actualDX: 1,
      actualDY: 0,
      cameraDX: 2,
      cameraDY: -1,
      configuration: configuration
    )
    try dataset.record(valid)
    #expect(throws: OnlineJogResponseError.duplicateEpisodeID("valid")) {
      try dataset.record(valid)
    }

    let wrongConfiguration = CameraConfigurationID()
    let wrongCamera = try await episode(
      id: "wrong-camera",
      split: .training,
      actualDX: 1,
      actualDY: 0,
      cameraDX: 2,
      cameraDY: -1,
      configuration: wrongConfiguration
    )
    #expect(
      throws: OnlineJogResponseError.cameraConfigurationMismatch(
        expected: configuration,
        actual: wrongConfiguration
      )
    ) {
      try dataset.record(wrongCamera)
    }

    let wrongRevision = try await episode(
      id: "wrong-revision",
      split: .training,
      actualDX: 1,
      actualDY: 0,
      cameraDX: 2,
      cameraDY: -1,
      configuration: configuration,
      revision: "cap-response-v2"
    )
    #expect(
      throws: OnlineJogResponseError.algorithmRevisionMismatch(
        expected: "cap-response-v1",
        actual: "cap-response-v2"
      )
    ) {
      try dataset.record(wrongRevision)
    }

    let zeroMotion = try await episode(
      id: "zero-motion",
      split: .training,
      actualDX: 0,
      actualDY: 0,
      cameraDX: 1,
      cameraDY: 0,
      configuration: configuration
    )
    #expect(
      throws: OnlineJogResponseError.invalidActualControllerDelta("zero-motion")
    ) {
      try dataset.record(zeroMotion)
    }
    #expect(dataset.summary.episodeCount == 1)
  }

  @Test("physical observation rejects an analysis revision change")
  func observationRevisionMustStayFixed() async throws {
    let configuration = CameraConfigurationID()
    let before = try await visible(
      id: "revision-before",
      sequence: 1,
      captureNanoseconds: 100,
      configuration: configuration,
      revision: "cap-response-v1"
    )
    let after = try await visible(
      id: "revision-after",
      sequence: 2,
      captureNanoseconds: 200,
      configuration: configuration,
      revision: "cap-response-v2",
      capOffsetX: 1
    )
    #expect(
      throws: PhysicalJogObservationFailure.algorithmRevisionChanged(
        before: "cap-response-v1",
        after: "cap-response-v2"
      )
    ) {
      _ = try PhysicalJogObservation(
        observationID: "revision-change",
        request: PhysicalJogObservationRequest(
          motion: RelativeJogRequest(
            delta: Vector2(dx: 1, dy: 0),
            feedMMPerMinute: 10
          ),
          split: .training
        ),
        startPosition: MachinePosition(x: 0, y: 0),
        startControllerSampleNanoseconds: 110,
        finalPosition: MachinePosition(x: 1, y: 0),
        finalControllerSampleNanoseconds: 190,
        before: before,
        after: after
      )
    }
  }

  @Test("candidate fitting rejects insufficient and rank-deficient training motion")
  func trainingGeometryMustSpanTwoAxes() async throws {
    let configuration = CameraConfigurationID()
    var dataset = try OnlineJogResponseDataset(
      cameraConfigurationID: configuration,
      algorithmRevision: "cap-response-v1"
    )
    try await dataset.record(
      episode(
        id: "x-1",
        split: .training,
        actualDX: 1,
        actualDY: 0,
        cameraDX: 2,
        cameraDY: 1,
        configuration: configuration
      )
    )
    #expect(
      throws: OnlineJogResponseError.insufficientTrainingEpisodes(
        required: 2,
        actual: 1
      )
    ) {
      _ = try dataset.proposeCandidate()
    }

    try await dataset.record(
      episode(
        id: "x-2",
        split: .training,
        actualDX: 2,
        actualDY: 0,
        cameraDX: 4,
        cameraDY: 2,
        configuration: configuration
      )
    )
    #expect(throws: OnlineJogResponseError.rankDeficientTrainingGeometry) {
      _ = try dataset.proposeCandidate()
    }
  }

  @Test("dataset binding rejects an empty analysis revision")
  func revisionBindingMustBeNonempty() {
    #expect(throws: OnlineJogResponseError.invalidAlgorithmRevision) {
      _ = try OnlineJogResponseDataset(
        cameraConfigurationID: CameraConfigurationID(),
        algorithmRevision: "  "
      )
    }
  }
}

private func episode(
  id: String,
  split: ModelObservationSplit,
  actualDX: Double,
  actualDY: Double,
  cameraDX: Int,
  cameraDY: Int,
  configuration: CameraConfigurationID,
  revision: String = "cap-response-v1"
) async throws -> PhysicalJogObservation {
  let before = try await visible(
    id: "\(id)-before",
    sequence: 1,
    captureNanoseconds: 100,
    configuration: configuration,
    revision: revision
  )
  let after = try await visible(
    id: "\(id)-after",
    sequence: 2,
    captureNanoseconds: 200,
    configuration: configuration,
    revision: revision,
    capOffsetX: cameraDX,
    capOffsetY: cameraDY
  )
  return try PhysicalJogObservation(
    observationID: id,
    request: PhysicalJogObservationRequest(
      motion: RelativeJogRequest(
        delta: Vector2(dx: actualDX, dy: actualDY),
        feedMMPerMinute: 10
      ),
      split: split
    ),
    startPosition: MachinePosition(x: 20, y: 20),
    startControllerSampleNanoseconds: 110,
    finalPosition: MachinePosition(x: 20 + actualDX, y: 20 + actualDY),
    finalControllerSampleNanoseconds: 190,
    before: before,
    after: after
  )
}

private func visible(
  id: String,
  sequence: UInt64,
  captureNanoseconds: UInt64,
  configuration: CameraConfigurationID,
  revision: String,
  capOffsetX: Int = 0,
  capOffsetY: Int = 0
) async throws -> VisibleToolFrameObservation {
  let frame = try responseFrame(
    id: FrameID(rawValue: id),
    sequence: sequence,
    captureNanoseconds: captureNanoseconds,
    configuration: configuration,
    capOffsetX: capOffsetX,
    capOffsetY: capOffsetY
  )
  let priors = try PlotterSceneVisionPriors(
    capSearchRegion: PixelRect(x: 0, y: 0, width: frame.width, height: frame.height),
    topFrameSideRegion: PixelRect(x: 0, y: 0, width: frame.width, height: 3),
    rightFrameSideRegion: PixelRect(
      x: frame.width - 3,
      y: 0,
      width: 3,
      height: frame.height
    ),
    minimumCapPixels: 3,
    maximumCapPixels: 16,
    lineResidualLimitPixels: 2,
    algorithmRevision: revision
  )
  let measurement = try await VisionWorker().inspectPlotterScene(in: frame, priors: priors)
  return try VisibleToolFrameObservation(
    phase: sequence == 1 ? .beforeMotion : .afterMotion,
    displayedFrame: DisplayedFrame(
      source: .live(CameraDeviceID(rawValue: "response-test-camera")),
      frame: frame
    ),
    measurement: measurement
  )
}

private func responseFrame(
  id: FrameID,
  sequence: UInt64,
  captureNanoseconds: UInt64,
  configuration: CameraConfigurationID,
  capOffsetX: Int,
  capOffsetY: Int
) throws -> StampedFrame {
  let width = 24
  let height = 24
  var bytes = Array(repeating: UInt8(0), count: width * height * 4)
  for y in (10 + capOffsetY)...(11 + capOffsetY) {
    for x in (10 + capOffsetX)...(11 + capOffsetX) {
      let offset = (y * width + x) * 4
      bytes[offset + 1] = 255
      bytes[offset + 3] = 255
    }
  }
  return try StampedFrame(
    id: id,
    sequence: sequence,
    captureNanoseconds: captureNanoseconds,
    cameraConfigurationID: configuration,
    width: width,
    height: height,
    rowBytes: width * 4,
    pixelFormat: .bgra8,
    bytes: OwnedFrameBytes(bytes)
  )
}
