import PlotterModel
import Testing

@testable import PlotterRuntime

@Suite("Physical jog camera observations")
struct PhysicalJogObservationTests {
  @Test("visible-tool evidence requires an exact live displayed frame")
  func exactLiveFrameRequired() async throws {
    let configuration = CameraConfigurationID()
    let frame = try capFrame(
      id: FrameID(rawValue: "live-frame"),
      sequence: 1,
      time: 100,
      configuration: configuration
    )
    let measurement = try await sceneMeasurement(frame)

    #expect(throws: PhysicalJogObservationFailure.liveCameraRequired) {
      _ = try VisibleToolFrameObservation(
        phase: .beforeMotion,
        displayedFrame: DisplayedFrame(source: .simulated, frame: frame),
        measurement: measurement
      )
    }

    let changedIdentity = try capFrame(
      id: FrameID(rawValue: "other-frame"),
      sequence: 2,
      time: 101,
      configuration: configuration
    )
    #expect(throws: PhysicalJogObservationFailure.frameIdentityMismatch) {
      _ = try VisibleToolFrameObservation(
        phase: .beforeMotion,
        displayedFrame: DisplayedFrame(
          source: .live(CameraDeviceID(rawValue: "camera-1")),
          frame: changedIdentity
        ),
        measurement: measurement
      )
    }

    let changedHash = try capFrame(
      id: frame.id,
      sequence: 2,
      time: 101,
      configuration: configuration,
      byteSalt: 1
    )
    #expect(throws: PhysicalJogObservationFailure.frameHashMismatch) {
      _ = try VisibleToolFrameObservation(
        phase: .beforeMotion,
        displayedFrame: DisplayedFrame(
          source: .live(CameraDeviceID(rawValue: "camera-1")),
          frame: changedHash
        ),
        measurement: measurement
      )
    }

    let changedConfiguration = try capFrame(
      id: frame.id,
      sequence: 2,
      time: 101,
      configuration: CameraConfigurationID()
    )
    #expect(throws: PhysicalJogObservationFailure.measurementConfigurationMismatch) {
      _ = try VisibleToolFrameObservation(
        phase: .beforeMotion,
        displayedFrame: DisplayedFrame(
          source: .live(CameraDeviceID(rawValue: "camera-1")),
          frame: changedConfiguration
        ),
        measurement: measurement
      )
    }
  }

  @Test("missing cap reports the requested observation phase")
  func missingCapIsPhaseSpecific() async throws {
    let frame = try blankFrame(
      id: FrameID(rawValue: "blank"),
      sequence: 1,
      time: 100,
      configuration: CameraConfigurationID()
    )
    let measurement = try await sceneMeasurement(frame)
    #expect(throws: PhysicalJogObservationFailure.capUnavailable(.afterMotion)) {
      _ = try VisibleToolFrameObservation(
        phase: .afterMotion,
        displayedFrame: DisplayedFrame(
          source: .live(CameraDeviceID(rawValue: "camera-1")),
          frame: frame
        ),
        measurement: measurement
      )
    }
  }

  @Test("paired observation requires one configuration and a strictly newer post frame")
  func pairFreshnessAndCameraDelta() async throws {
    let configuration = CameraConfigurationID()
    let before = try await visibleObservation(
      id: "before",
      sequence: 1,
      time: 100,
      configuration: configuration
    )
    let after = try await visibleObservation(
      id: "after",
      sequence: 2,
      time: 200,
      configuration: configuration,
      capOffsetX: 2,
      capOffsetY: 1
    )
    let request = try PhysicalJogObservationRequest(
      motion: RelativeJogRequest(
        delta: Vector2(dx: 1, dy: 0),
        feedMMPerMinute: 20
      ),
      split: .training
    )
    let start = try MachinePosition(x: 10, y: 20)
    let final = try MachinePosition(x: 11, y: 20)
    let observation = try PhysicalJogObservation(
      observationID: "jog-1",
      request: request,
      startPosition: start,
      startControllerSampleNanoseconds: 110,
      finalPosition: final,
      finalControllerSampleNanoseconds: 190,
      before: before,
      after: after
    )
    #expect(observation.cameraDelta.dx == 2)
    #expect(observation.cameraDelta.dy == 1)

    #expect(throws: PhysicalJogObservationFailure.postFrameNotNewer) {
      _ = try PhysicalJogObservation(
        observationID: "stale",
        request: request,
        startPosition: start,
        startControllerSampleNanoseconds: 110,
        finalPosition: final,
        finalControllerSampleNanoseconds: 190,
        before: after,
        after: before
      )
    }

    let otherConfiguration = try await visibleObservation(
      id: "changed-camera",
      sequence: 3,
      time: 300,
      configuration: CameraConfigurationID()
    )
    #expect(throws: PhysicalJogObservationFailure.cameraConfigurationChanged) {
      _ = try PhysicalJogObservation(
        observationID: "configuration-change",
        request: request,
        startPosition: start,
        startControllerSampleNanoseconds: 110,
        finalPosition: final,
        finalControllerSampleNanoseconds: 190,
        before: before,
        after: otherConfiguration
      )
    }
  }

  @Test("motion outcome remains independent from camera recording")
  func motionOutcomeIsPreserved() async throws {
    let observation = try await completeObservation()
    let completed = MotionOutcome.acceptedThenCompleted(
      finalPosition: observation.finalPosition
    )
    let recorded = PhysicalJogObservationOutcome.resolve(
      motionOutcome: completed,
      observation: observation
    )
    #expect(recorded == .recorded(observation))
    #expect(recorded.motionOutcome == completed)

    let refused = MotionOutcome.refused(.notConnected)
    let notRecorded = PhysicalJogObservationOutcome.resolve(
      motionOutcome: refused,
      observation: observation
    )
    #expect(
      notRecorded
        == .notRecorded(
          motionOutcome: refused,
          failure: .motionNotCompleted(refused)
        )
    )
    #expect(notRecorded.motionOutcome == refused)

    let wrongFinal = MotionOutcome.acceptedThenCompleted(
      finalPosition: try MachinePosition(x: 99, y: 99)
    )
    #expect(
      PhysicalJogObservationOutcome.resolve(
        motionOutcome: wrongFinal,
        observation: observation
      )
        == .notRecorded(
          motionOutcome: wrongFinal,
          failure: .motionNotCompleted(wrongFinal)
        )
    )
  }

  @Test("camera frames must bracket the controller motion samples")
  func crossModalTemporalOrder() async throws {
    let configuration = CameraConfigurationID()
    let beforeTooLate = try await visibleObservation(
      id: "before-too-late",
      sequence: 1,
      time: 120,
      configuration: configuration
    )
    let beforeAtStart = try await visibleObservation(
      id: "before-at-start",
      sequence: 1,
      time: 110,
      configuration: configuration
    )
    let afterMidMotion = try await visibleObservation(
      id: "after-mid-motion",
      sequence: 2,
      time: 190,
      configuration: configuration,
      capOffsetX: 1
    )
    let afterStrictlyLater = try await visibleObservation(
      id: "after-strictly-later",
      sequence: 2,
      time: 191,
      configuration: configuration,
      capOffsetX: 1
    )
    let request = try PhysicalJogObservationRequest(
      motion: RelativeJogRequest(
        delta: Vector2(dx: 1, dy: 0),
        feedMMPerMinute: 20
      ),
      split: .training
    )
    let start = try MachinePosition(x: 10, y: 20)
    let final = try MachinePosition(x: 11, y: 20)

    #expect(
      throws: PhysicalJogObservationFailure.beforeFrameAfterStartControllerSample(
        frameCaptureNanoseconds: 120,
        controllerSampleNanoseconds: 110
      )
    ) {
      _ = try PhysicalJogObservation(
        observationID: "late-before",
        request: request,
        startPosition: start,
        startControllerSampleNanoseconds: 110,
        finalPosition: final,
        finalControllerSampleNanoseconds: 190,
        before: beforeTooLate,
        after: afterStrictlyLater
      )
    }
    #expect(
      throws: PhysicalJogObservationFailure.afterFrameNotNewerThanFinalControllerSample(
        frameCaptureNanoseconds: 190,
        controllerSampleNanoseconds: 190
      )
    ) {
      _ = try PhysicalJogObservation(
        observationID: "mid-motion-after",
        request: request,
        startPosition: start,
        startControllerSampleNanoseconds: 110,
        finalPosition: final,
        finalControllerSampleNanoseconds: 190,
        before: beforeAtStart,
        after: afterMidMotion
      )
    }

    let accepted = try PhysicalJogObservation(
      observationID: "exact-boundaries",
      request: request,
      startPosition: start,
      startControllerSampleNanoseconds: 110,
      finalPosition: final,
      finalControllerSampleNanoseconds: 190,
      before: beforeAtStart,
      after: afterStrictlyLater
    )
    #expect(accepted.before.captureNanoseconds == accepted.startControllerSampleNanoseconds)
    #expect(accepted.after.captureNanoseconds > accepted.finalControllerSampleNanoseconds)
  }

  @Test("paired model conversion applies one exact registration with unique provenance")
  func pairedModelConversion() async throws {
    let observation = try await completeObservation()
    let registration = try identityRegistration(id: FieldRegistrationID())
    let pair = try observation.modelObservationPair(using: registration)

    #expect(pair.beforeEvidence.fieldRegistrationID == registration.id)
    #expect(pair.afterEvidence.fieldRegistrationID == registration.id)
    #expect(pair.beforeEvidence.frameID == observation.before.frameID.rawValue)
    #expect(pair.afterEvidence.frameID == observation.after.frameID.rawValue)
    #expect(pair.beforeObservation.provenance.observationID == "jog-1:before")
    #expect(pair.afterObservation.provenance.observationID == "jog-1:after")
    #expect(
      pair.beforeObservation.provenance.observationID
        != pair.afterObservation.provenance.observationID
    )
    #expect(pair.beforeObservation.machinePoint == observation.startPosition.point)
    #expect(pair.afterObservation.machinePoint == observation.finalPosition.point)
    #expect(pair.beforeObservation.split == .training)
    #expect(pair.afterObservation.split == .training)
    let expectedBeforeFieldPoint = try registration.fieldPoint(
      from: observation.before.capCentroid
    )
    #expect(pair.beforeObservation.observedFieldPoint == expectedBeforeFieldPoint)

    let unrelated = try identityRegistration(id: FieldRegistrationID())
    #expect(throws: ModelLearningError.physicalRegistrationMismatch) {
      _ = try DrawingModelTrainingObservation.physical(
        evidence: pair.beforeEvidence,
        registration: unrelated,
        split: .training,
        observationID: "wrong-registration",
        algorithmRevision: observation.before.algorithmRevision
      )
    }
  }
}

private func completeObservation() async throws -> PhysicalJogObservation {
  let configuration = CameraConfigurationID()
  let before = try await visibleObservation(
    id: "before",
    sequence: 1,
    time: 100,
    configuration: configuration
  )
  let after = try await visibleObservation(
    id: "after",
    sequence: 2,
    time: 200,
    configuration: configuration,
    capOffsetX: 1
  )
  return try PhysicalJogObservation(
    observationID: "jog-1",
    request: PhysicalJogObservationRequest(
      motion: RelativeJogRequest(
        delta: Vector2(dx: 1, dy: 0),
        feedMMPerMinute: 20
      ),
      split: .training
    ),
    startPosition: MachinePosition(x: 10, y: 20),
    startControllerSampleNanoseconds: 110,
    finalPosition: MachinePosition(x: 11, y: 20),
    finalControllerSampleNanoseconds: 190,
    before: before,
    after: after
  )
}

private func visibleObservation(
  id: String,
  sequence: UInt64,
  time: UInt64,
  configuration: CameraConfigurationID,
  capOffsetX: Int = 0,
  capOffsetY: Int = 0
) async throws -> VisibleToolFrameObservation {
  let frame = try capFrame(
    id: FrameID(rawValue: id),
    sequence: sequence,
    time: time,
    configuration: configuration,
    capOffsetX: capOffsetX,
    capOffsetY: capOffsetY
  )
  return try VisibleToolFrameObservation(
    phase: sequence == 1 ? .beforeMotion : .afterMotion,
    displayedFrame: DisplayedFrame(
      source: .live(CameraDeviceID(rawValue: "camera-1")),
      frame: frame
    ),
    measurement: try await sceneMeasurement(frame)
  )
}

private func sceneMeasurement(_ frame: StampedFrame) async throws -> PlotterSceneMeasurement {
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
    algorithmRevision: "visible-cap-test-v1"
  )
  return try await VisionWorker().inspectPlotterScene(in: frame, priors: priors)
}

private func capFrame(
  id: FrameID,
  sequence: UInt64,
  time: UInt64,
  configuration: CameraConfigurationID,
  capOffsetX: Int = 0,
  capOffsetY: Int = 0,
  byteSalt: UInt8 = 0
) throws -> StampedFrame {
  let width = 12
  let height = 12
  var bytes = Array(repeating: UInt8(0), count: width * height * 4)
  bytes[0] = byteSalt
  for y in (4 + capOffsetY)...(5 + capOffsetY) {
    for x in (4 + capOffsetX)...(5 + capOffsetX) {
      let offset = (y * width + x) * 4
      bytes[offset] = 0
      bytes[offset + 1] = 255
      bytes[offset + 2] = 0
      bytes[offset + 3] = 255
    }
  }
  return try StampedFrame(
    id: id,
    sequence: sequence,
    captureNanoseconds: time,
    cameraConfigurationID: configuration,
    width: width,
    height: height,
    rowBytes: width * 4,
    pixelFormat: .bgra8,
    bytes: OwnedFrameBytes(bytes)
  )
}

private func blankFrame(
  id: FrameID,
  sequence: UInt64,
  time: UInt64,
  configuration: CameraConfigurationID
) throws -> StampedFrame {
  let width = 12
  let height = 12
  return try StampedFrame(
    id: id,
    sequence: sequence,
    captureNanoseconds: time,
    cameraConfigurationID: configuration,
    width: width,
    height: height,
    rowBytes: width * 4,
    pixelFormat: .bgra8,
    bytes: OwnedFrameBytes(Array(repeating: UInt8(0), count: width * height * 4))
  )
}

private func identityRegistration(id: FieldRegistrationID) throws -> FieldRegistration {
  try FieldRegistration.fit(
    id: id,
    correspondences: [
      RegistrationCorrespondence(
        camera: Point2(x: 0, y: 0),
        field: Point2(x: 0, y: 0)
      ),
      RegistrationCorrespondence(
        camera: Point2(x: 100, y: 0),
        field: Point2(x: 100, y: 0)
      ),
      RegistrationCorrespondence(
        camera: Point2(x: 0, y: 100),
        field: Point2(x: 0, y: 100)
      ),
    ]
  )
}
