import Foundation
import PlotterModel
import PlotterTestSupport
import Testing

@testable import PlotterRuntime

@Suite("Visibility target and isolated ink observation")
struct IsolatedInkObservationTests {
  @Test("two same-pose target frames produce N=2 stable target evidence")
  func stableVisibilityTarget() async throws {
    let camera = CameraConfigurationID()
    let simulator = PaperSceneSimulator(width: 40, height: 30)
    let target = targetStrokes(center: PaperPixelPoint(x: 18, y: 15), radius: 4)
    let baseline = try simulator.render(
      strokes: [], sequence: 1, captureNanoseconds: 1,
      cameraConfigurationID: camera)
    let first = try simulator.render(
      strokes: target, sequence: 2, captureNanoseconds: 2,
      cameraConfigurationID: camera)
    let second = try simulator.render(
      strokes: target, sequence: 3, captureNanoseconds: 3,
      cameraConfigurationID: camera)
    let clearPose = try MachinePosition(x: 12, y: -5)

    let outcome = await VisionWorker().observeVisibilityTarget(
      visibilityRequest(
        baseline: sample(baseline, clearPose),
        targets: [
          sample(first, clearPose),
          sample(second, clearPose),
        ]
      )
    )
    guard case .observed(let observation) = outcome else {
      Issue.record("expected stable target; got \(outcome)")
      return
    }
    #expect(observation.validSampleCount == 2)
    #expect(observation.includedFrameIDs == [first.id, second.id])
    #expect(observation.estimatorRevision == "two-frame-component-mean-v1")
    #expect(observation.algorithmRevision == "visibility-test-v1")
    #expect(observation.targetPlanRevision == VisibilityTargetPlanV1.revision)
    #expect(observation.samples.allSatisfy { $0.pixelCount > 20 })
    #expect(observation.centroidUncertainty.dx == 0)
    #expect(observation.centroidUncertainty.dy == 0)
    #expect(observation.areaRatio == 1)
  }

  @Test("same camera pixels at a different reported clear pose are rejected")
  func clearPoseMismatch() async throws {
    let camera = CameraConfigurationID()
    let simulator = PaperSceneSimulator(width: 40, height: 30)
    let target = targetStrokes(center: PaperPixelPoint(x: 18, y: 15), radius: 4)
    let baseline = try simulator.render(
      strokes: [], sequence: 1, captureNanoseconds: 1,
      cameraConfigurationID: camera)
    let first = try simulator.render(
      strokes: target, sequence: 2, captureNanoseconds: 2,
      cameraConfigurationID: camera)
    let second = try simulator.render(
      strokes: target, sequence: 3, captureNanoseconds: 3,
      cameraConfigurationID: camera)
    let acceptedPose = try MachinePosition(x: 4, y: 5)
    let wrongPose = try MachinePosition(x: 4.2, y: 5)
    let outcome = await VisionWorker().observeVisibilityTarget(
      visibilityRequest(
        baseline: sample(baseline, acceptedPose),
        targets: [
          sample(first, acceptedPose),
          sample(second, wrongPose),
        ]
      )
    )
    guard case .rejected(.clearPoseMismatch(let frameID, let distance, let tolerance)) = outcome
    else {
      Issue.record("expected typed pose mismatch; got \(outcome)")
      return
    }
    #expect(frameID == second.id)
    #expect(distance > tolerance)
  }

  @Test("camera reconfiguration rejects target comparison")
  func targetCameraMismatch() async throws {
    let simulator = PaperSceneSimulator(width: 40, height: 30)
    let firstCamera = CameraConfigurationID()
    let target = targetStrokes(center: PaperPixelPoint(x: 18, y: 15), radius: 4)
    let baseline = try simulator.render(
      strokes: [], sequence: 1, captureNanoseconds: 1,
      cameraConfigurationID: firstCamera)
    let first = try simulator.render(
      strokes: target, sequence: 2, captureNanoseconds: 2,
      cameraConfigurationID: firstCamera)
    let second = try simulator.render(
      strokes: target, sequence: 3, captureNanoseconds: 3,
      cameraConfigurationID: CameraConfigurationID())
    let pose = try MachinePosition(x: 0, y: 0)
    let outcome = await VisionWorker().observeVisibilityTarget(
      visibilityRequest(
        baseline: sample(baseline, pose),
        targets: [
          sample(first, pose),
          sample(second, pose),
        ]
      )
    )
    #expect(outcome == .rejected(.cameraConfigurationMismatch))
  }

  @Test("simulated and live frames cannot enter one target observation")
  func targetSourceMismatch() async throws {
    let camera = CameraConfigurationID()
    let simulator = PaperSceneSimulator(width: 40, height: 30)
    let target = targetStrokes(center: PaperPixelPoint(x: 18, y: 15), radius: 4)
    let baseline = try simulator.render(
      strokes: [], sequence: 1, captureNanoseconds: 1,
      cameraConfigurationID: camera)
    let first = try simulator.render(
      strokes: target, sequence: 2, captureNanoseconds: 2,
      cameraConfigurationID: camera)
    let second = try simulator.render(
      strokes: target, sequence: 3, captureNanoseconds: 3,
      cameraConfigurationID: camera)
    let pose = try MachinePosition(x: 0, y: 0)
    let request = visibilityRequest(
      baseline: sample(baseline, pose),
      targets: [
        sample(first, pose),
        sample(second, pose, source: .live(CameraDeviceID(rawValue: "live-test"))),
      ]
    )
    #expect(await VisionWorker().observeVisibilityTarget(request) == .rejected(.sourceMismatch))
  }

  @Test("4 mm target at 2 px per mm uses diameter rather than bounding-box diagonal")
  func exactFourMillimeterProjection() async throws {
    let camera = CameraConfigurationID()
    let simulator = PaperSceneSimulator(width: 40, height: 30)
    let target = targetStrokes(center: PaperPixelPoint(x: 18, y: 15), radius: 4)
    let baseline = try simulator.render(
      strokes: [], sequence: 1, captureNanoseconds: 1,
      cameraConfigurationID: camera)
    let first = try simulator.render(
      strokes: target, sequence: 2, captureNanoseconds: 2,
      cameraConfigurationID: camera)
    let second = try simulator.render(
      strokes: target, sequence: 3, captureNanoseconds: 3,
      cameraConfigurationID: camera)
    let pose = try MachinePosition(x: 0, y: 0)

    let outcome = await VisionWorker().observeVisibilityTarget(
      visibilityRequest(
        baseline: sample(baseline, pose),
        targets: [sample(first, pose), sample(second, pose)],
        expectedDiameterPixels: 8...8
      )
    )
    guard case .observed(let observation) = outcome else {
      Issue.record("expected exact projected diameter to be accepted; got \(outcome)")
      return
    }
    #expect(observation.samples.allSatisfy {
      $0.bounds.maxX - $0.bounds.minX == 9 && $0.bounds.maxY - $0.bounds.minY == 9
    })
  }

  @Test("bounded integer alignment is retained and used for target differencing")
  func boundedTargetAlignment() async throws {
    let camera = CameraConfigurationID()
    let simulator = PaperSceneSimulator(width: 40, height: 30)
    let background = [SimulatedPaperStroke(
      start: PaperPixelPoint(x: 2, y: 2),
      end: PaperPixelPoint(x: 5, y: 7)
    )]
    let target = targetStrokes(center: PaperPixelPoint(x: 18, y: 15), radius: 4)
    let baseline = try simulator.render(
      strokes: background, sequence: 1, captureNanoseconds: 1,
      cameraConfigurationID: camera)
    let first = try shiftFrame(
      simulator.render(
        strokes: background + target, sequence: 2, captureNanoseconds: 2,
        cameraConfigurationID: camera),
      dx: 1,
      dy: 0
    )
    let second = try shiftFrame(
      simulator.render(
        strokes: background + target, sequence: 3, captureNanoseconds: 3,
        cameraConfigurationID: camera),
      dx: 1,
      dy: 0
    )
    let pose = try MachinePosition(x: 0, y: 0)

    let outcome = await VisionWorker().observeVisibilityTarget(
      visibilityRequest(
        baseline: sample(baseline, pose),
        targets: [sample(first, pose), sample(second, pose)]
      )
    )
    guard case .observed(let observation) = outcome else {
      Issue.record("expected aligned target; got \(outcome)")
      return
    }
    #expect(observation.samples.map(\.alignment.shiftX) == [1, 1])
    #expect(observation.samples.map(\.alignment.shiftY) == [0, 0])
    #expect(observation.samples.allSatisfy { $0.alignment.backgroundMeanAbsoluteDifference == 0 })
  }

  @Test("detected alignment outside acceptance policy is rejected")
  func excessiveTargetAlignment() async throws {
    let camera = CameraConfigurationID()
    let simulator = PaperSceneSimulator(width: 40, height: 30)
    let background = [SimulatedPaperStroke(
      start: PaperPixelPoint(x: 2, y: 2),
      end: PaperPixelPoint(x: 5, y: 7)
    )]
    let target = targetStrokes(center: PaperPixelPoint(x: 18, y: 15), radius: 4)
    let baseline = try simulator.render(
      strokes: background, sequence: 1, captureNanoseconds: 1,
      cameraConfigurationID: camera)
    let first = try shiftFrame(
      simulator.render(
        strokes: background + target, sequence: 2, captureNanoseconds: 2,
        cameraConfigurationID: camera),
      dx: 2,
      dy: 0
    )
    let second = try shiftFrame(
      simulator.render(
        strokes: background + target, sequence: 3, captureNanoseconds: 3,
        cameraConfigurationID: camera),
      dx: 2,
      dy: 0
    )
    let pose = try MachinePosition(x: 0, y: 0)
    let outcome = await VisionWorker().observeVisibilityTarget(
      visibilityRequest(
        baseline: sample(baseline, pose),
        targets: [sample(first, pose), sample(second, pose)]
      )
    )
    guard case .rejected(.excessiveAlignment(_, let shiftX, let shiftY, let maximum)) = outcome
    else {
      Issue.record("expected excessive alignment; got \(outcome)")
      return
    }
    #expect(shiftX == 2)
    #expect(shiftY == 0)
    #expect(maximum == 1)
  }

  @Test("background change outside target ROI is rejected after alignment")
  func excessiveTargetBackgroundResidual() async throws {
    let camera = CameraConfigurationID()
    let simulator = PaperSceneSimulator(width: 40, height: 30)
    let target = targetStrokes(center: PaperPixelPoint(x: 18, y: 15), radius: 4)
    let changedBackground = [SimulatedPaperStroke(
      start: PaperPixelPoint(x: 0, y: 20),
      end: PaperPixelPoint(x: 7, y: 29)
    )]
    let baseline = try simulator.render(
      strokes: [], sequence: 1, captureNanoseconds: 1,
      cameraConfigurationID: camera)
    let first = try simulator.render(
      strokes: changedBackground + target, sequence: 2, captureNanoseconds: 2,
      cameraConfigurationID: camera)
    let second = try simulator.render(
      strokes: changedBackground + target, sequence: 3, captureNanoseconds: 3,
      cameraConfigurationID: camera)
    let pose = try MachinePosition(x: 0, y: 0)
    let outcome = await VisionWorker().observeVisibilityTarget(
      visibilityRequest(
        baseline: sample(baseline, pose),
        targets: [sample(first, pose), sample(second, pose)],
        alignmentSearchRadiusPixels: 0,
        maximumAlignmentShiftPixels: 0
      )
    )
    guard case .rejected(.excessiveBackgroundResidual(_, let actual, let maximum)) = outcome
    else {
      Issue.record("expected background residual rejection; got \(outcome)")
      return
    }
    #expect(actual > maximum)
  }

  @Test("trial-local target-present baseline isolates the new line")
  func targetAnchoredLineObservation() async throws {
    let camera = CameraConfigurationID()
    let simulator = PaperSceneSimulator(width: 48, height: 32)
    let lineStart = PaperPixelPoint(x: 24, y: 16)
    let frames = try simulator.renderVisibilityTargetAndLineSequence(
      preexistingInk: [],
      targetCenter: PaperPixelPoint(x: 20, y: 16),
      lineStart: lineStart,
      lineEnd: PaperPixelPoint(x: 31, y: 16),
      baselineSequence: 10,
      baselineCaptureNanoseconds: 10,
      cameraConfigurationID: camera
    )
    let outcome = await VisionWorker().observeIsolatedInk(IsolatedInkObservationRequest(
      targetPresentBaseline: sample(
        frames.targetPresentBaseline,
        try MachinePosition(x: 0, y: 0)
      ),
      postLine: sample(frames.postLine, try MachinePosition(x: 0, y: 0)),
      region: PixelRect(x: 0, y: 0, width: 48, height: 32),
      thresholds: thresholds,
      lineStartPoint: try Point2(x: 24, y: 16),
      controllerSessionID: UUID(),
      coordinateRevision: 1,
      toolPaperRevision: UUID(),
      controllerPositionToleranceMM: 0.01,
      alignmentSearchRadiusPixels: 2,
      maximumAlignmentShiftPixels: 1,
      maximumBackgroundMeanAbsoluteDifference: 0.1,
      projectedActualStrokeDelta: try Vector2(dx: 7, dy: 0),
      algorithmRevision: "line-test-v1",
      minimumLinePixels: 5
    ))
    guard case .observed(let observation) = outcome else {
      Issue.record("expected line observation; got \(outcome)")
      return
    }
    #expect(observation.targetPresentBaseline.frameID == frames.targetPresentBaseline.id)
    #expect(observation.postLine.frameID == frames.postLine.id)
    #expect(observation.lineStartPoint == (try Point2(x: 24, y: 16)))
    #expect(observation.observedPixelCount >= 7)
    #expect(observation.residual != nil)
  }

  @Test("absent new line is a typed rejection and cannot manufacture ink")
  func absentLine() async throws {
    let camera = CameraConfigurationID()
    let simulator = PaperSceneSimulator(width: 30, height: 20)
    let target = targetStrokes(center: PaperPixelPoint(x: 15, y: 10), radius: 4)
    let first = try simulator.render(
      strokes: target, sequence: 1, captureNanoseconds: 1,
      cameraConfigurationID: camera)
    let second = try simulator.render(
      strokes: target, sequence: 2, captureNanoseconds: 2,
      cameraConfigurationID: camera)
    let outcome = await VisionWorker().observeIsolatedInk(IsolatedInkObservationRequest(
      targetPresentBaseline: sample(first, try MachinePosition(x: 0, y: 0)),
      postLine: sample(second, try MachinePosition(x: 0, y: 0)),
      region: PixelRect(x: 0, y: 0, width: 30, height: 20),
      thresholds: thresholds,
      lineStartPoint: try Point2(x: 19, y: 10),
      controllerSessionID: UUID(),
      coordinateRevision: 1,
      toolPaperRevision: UUID(),
      controllerPositionToleranceMM: 0.01,
      alignmentSearchRadiusPixels: 2,
      maximumAlignmentShiftPixels: 1,
      maximumBackgroundMeanAbsoluteDifference: 0.1,
      projectedActualStrokeDelta: try Vector2(dx: 5, dy: 0),
      algorithmRevision: "line-test-v1"
    ))
    #expect(rejectionReason(outcome) == .lineMissing)
  }

  @Test("Stage 4 line comparison rejects a source change")
  func lineSourceMismatch() async throws {
    let frames = try lineFrames()
    let pose = try MachinePosition(x: 0, y: 0)
    let outcome = await VisionWorker().observeIsolatedInk(lineRequest(
      baseline: sample(frames.targetPresentBaseline, pose),
      post: sample(
        frames.postLine,
        pose,
        source: .live(CameraDeviceID(rawValue: "live-stage4"))
      )
    ))
    #expect(rejectionReason(outcome) == .sourceMismatch)
  }

  @Test("Stage 4 line comparison rejects a different controller pose")
  func linePoseMismatch() async throws {
    let frames = try lineFrames()
    let outcome = await VisionWorker().observeIsolatedInk(lineRequest(
      baseline: sample(frames.targetPresentBaseline, try MachinePosition(x: 0, y: 0)),
      post: sample(frames.postLine, try MachinePosition(x: 0.2, y: 0))
    ))
    guard case .rejected(let rejection) = outcome,
      case .clearPoseMismatch(let distance, let tolerance) = rejection.reason
    else {
      Issue.record("expected Stage 4 pose mismatch; got \(outcome)")
      return
    }
    #expect(distance > tolerance)
  }

  @Test("two accepted target attempts aggregate across attempts without losing frame provenance")
  func visibilityTargetAttemptAggregate() async throws {
    let camera = CameraConfigurationID()
    let paper = UUID()
    let firstObservation = try await targetObservation(
      centerX: 18,
      sequenceBase: 10,
      camera: camera,
      toolPaperRevision: paper
    )
    let secondObservation = try await targetObservation(
      centerX: 20,
      sequenceBase: 20,
      camera: camera,
      toolPaperRevision: paper
    )
    let compatibility = targetAttemptCompatibility(camera: camera)
    let first = try ExerciseAttempt(
      disposition: .succeeded,
      compatibility: compatibility,
      acceptedSequence: 1,
      value: firstObservation
    )
    let excluded = try ExerciseAttempt<VisibilityTargetObservation>(
      disposition: .unclear("armature still overlaps the target"),
      compatibility: compatibility,
      acceptedSequence: 2,
      value: nil
    )
    let second = try ExerciseAttempt(
      disposition: .succeeded,
      compatibility: compatibility,
      acceptedSequence: 3,
      value: secondObservation
    )
    let history = try ExerciseAttemptHistory(
      compatibility: compatibility,
      attempts: [first, excluded, second]
    )

    let aggregate = try VisibilityTargetAttemptAggregate(history: history)
    #expect(aggregate.validAttemptCount == 2)
    #expect(aggregate.includedAttemptIDs == [first.id, second.id])
    #expect(aggregate.estimator.revision == "visibility-target-attempt-v1")
    #expect(aggregate.centroidEstimate.x == 19)
    #expect(aggregate.centroidEstimate.y == 15)
    let expectedUncertainty = try Vector2<CameraPixelSpace>(dx: sqrt(2), dy: 0)
    #expect(
      aggregate.uncertainty
        == .componentSampleStandardDeviation(expectedUncertainty)
    )
    #expect(aggregate.includedObservations.map(\.validSampleCount) == [2, 2])
    #expect(
      aggregate.includedObservations.flatMap(\.includedFrameIDs).count == 4
    )
    #expect(history.attempts.contains { $0.id == excluded.id && $0.value == nil })
  }

  @Test("N target attempts expose valid attempt N and reject paper-context pooling")
  func visibilityTargetNAttemptAggregateAndCompatibility() async throws {
    let camera = CameraConfigurationID()
    let paper = UUID()
    let compatibility = targetAttemptCompatibility(camera: camera)
    var observations: [VisibilityTargetObservation] = []
    for (index, center) in [17, 18, 19].enumerated() {
      observations.append(try await targetObservation(
        centerX: center,
        sequenceBase: UInt64(30 + index * 10),
        camera: camera,
        toolPaperRevision: paper
      ))
    }
    let attempts = try observations.enumerated().map { index, observation in
      try ExerciseAttempt(
        disposition: .succeeded,
        compatibility: compatibility,
        acceptedSequence: UInt64(index + 1),
        value: observation
      )
    }
    let history = try ExerciseAttemptHistory(
      compatibility: compatibility,
      attempts: attempts
    )
    #expect(try VisibilityTargetAttemptAggregate(history: history).validAttemptCount == 3)

    let incompatibleObservation = try await targetObservation(
      centerX: 18,
      sequenceBase: 70,
      camera: camera,
      toolPaperRevision: UUID()
    )
    let incompatibleAttempt = try ExerciseAttempt(
      disposition: .succeeded,
      compatibility: compatibility,
      acceptedSequence: 4,
      value: incompatibleObservation
    )
    var incompatibleHistory = history
    try incompatibleHistory.record(incompatibleAttempt)
    #expect(
      throws: VisibilityTargetAttemptAggregateError.observationContextMismatch(
        incompatibleAttempt.id
      )
    ) {
      _ = try VisibilityTargetAttemptAggregate(history: incompatibleHistory)
    }
  }
}

private let thresholds = GreenPixelThresholds(minimumGreen: 150, minimumGreenExcess: 80)

private func sample(
  _ frame: StampedFrame,
  _ position: MachinePosition,
  source: FrameSourceIdentity = .simulated
) -> SamePoseFrameSample {
  SamePoseFrameSample(source: source, frame: frame, controllerPosition: position)
}

private func visibilityRequest(
  baseline: SamePoseFrameSample,
  targets: [SamePoseFrameSample],
  expectedDiameterPixels: ClosedRange<Double> = 8...13,
  alignmentSearchRadiusPixels: Int = 2,
  maximumAlignmentShiftPixels: Int = 1,
  toolPaperRevision: UUID = UUID(
    uuidString: "00000000-0000-0000-0000-000000000011"
  )!
) -> VisibilityTargetObservationRequest {
  VisibilityTargetObservationRequest(
    baseline: baseline,
    targetSamples: targets,
    region: PixelRect(x: 8, y: 5, width: 22, height: 20),
    thresholds: thresholds,
    controllerSessionID: UUID(uuidString: "00000000-0000-0000-0000-000000000010")!,
    coordinateRevision: 3,
    toolPaperRevision: toolPaperRevision,
    controllerPositionToleranceMM: 0.05,
    expectedDiameterPixels: expectedDiameterPixels,
    minimumTargetPixels: 20,
    maximumCentroidSpreadPixels: 0.5,
    maximumAreaRatio: 1.1,
    maximumBackgroundMeanAbsoluteDifference: 0.1,
    alignmentSearchRadiusPixels: alignmentSearchRadiusPixels,
    maximumAlignmentShiftPixels: maximumAlignmentShiftPixels,
    algorithmRevision: "visibility-test-v1"
  )
}

private func targetAttemptCompatibility(
  camera: CameraConfigurationID
) -> AttemptCompatibility {
  AttemptCompatibility(
    cameraConfigurationID: camera,
    coordinateSpace: .cameraPixels,
    units: .pixels,
    group: AttemptGroupIdentity(rawValue: "visibility-target-test"),
    algorithmRevision: "visibility-test-v1"
  )
}

private func targetObservation(
  centerX: Int,
  sequenceBase: UInt64,
  camera: CameraConfigurationID,
  toolPaperRevision: UUID
) async throws -> VisibilityTargetObservation {
  let simulator = PaperSceneSimulator(width: 40, height: 30)
  let target = targetStrokes(center: PaperPixelPoint(x: centerX, y: 15), radius: 4)
  let baseline = try simulator.render(
    strokes: [],
    sequence: sequenceBase,
    captureNanoseconds: sequenceBase,
    cameraConfigurationID: camera
  )
  let first = try simulator.render(
    strokes: target,
    sequence: sequenceBase + 1,
    captureNanoseconds: sequenceBase + 1,
    cameraConfigurationID: camera
  )
  let second = try simulator.render(
    strokes: target,
    sequence: sequenceBase + 2,
    captureNanoseconds: sequenceBase + 2,
    cameraConfigurationID: camera
  )
  let pose = try MachinePosition(x: 0, y: 0)
  let outcome = await VisionWorker().observeVisibilityTarget(
    visibilityRequest(
      baseline: sample(baseline, pose),
      targets: [sample(first, pose), sample(second, pose)],
      toolPaperRevision: toolPaperRevision
    )
  )
  guard case .observed(let observation) = outcome else {
    throw TargetObservationFixtureError.rejected(String(describing: outcome))
  }
  return observation
}

private enum TargetObservationFixtureError: Error {
  case rejected(String)
}

private func lineFrames() throws -> SimulatedTargetAndLineFrames {
  try PaperSceneSimulator(width: 48, height: 32).renderVisibilityTargetAndLineSequence(
    preexistingInk: [],
    targetCenter: PaperPixelPoint(x: 20, y: 16),
    lineStart: PaperPixelPoint(x: 24, y: 16),
    lineEnd: PaperPixelPoint(x: 31, y: 16),
    baselineSequence: 10,
    baselineCaptureNanoseconds: 10,
    cameraConfigurationID: CameraConfigurationID()
  )
}

private func lineRequest(
  baseline: SamePoseFrameSample,
  post: SamePoseFrameSample
) -> IsolatedInkObservationRequest {
  IsolatedInkObservationRequest(
    targetPresentBaseline: baseline,
    postLine: post,
    region: PixelRect(x: 6, y: 4, width: 36, height: 24),
    thresholds: thresholds,
    lineStartPoint: try! Point2(x: 24, y: 16),
    controllerSessionID: UUID(uuidString: "00000000-0000-0000-0000-000000000020")!,
    coordinateRevision: 2,
    toolPaperRevision: UUID(uuidString: "00000000-0000-0000-0000-000000000021")!,
    controllerPositionToleranceMM: 0.01,
    alignmentSearchRadiusPixels: 2,
    maximumAlignmentShiftPixels: 1,
    maximumBackgroundMeanAbsoluteDifference: 0.1,
    projectedActualStrokeDelta: try! Vector2(dx: 7, dy: 0),
    algorithmRevision: "line-test-v1",
    minimumLinePixels: 5
  )
}

private func shiftFrame(_ frame: StampedFrame, dx: Int, dy: Int) throws -> StampedFrame {
  let components = frame.pixelFormat.bytesPerPixel
  var shifted = [UInt8](repeating: 255, count: frame.rowBytes * frame.height)
  for y in 0..<frame.height {
    for x in 0..<frame.width {
      let targetX = x + dx
      let targetY = y + dy
      guard targetX >= 0, targetX < frame.width, targetY >= 0, targetY < frame.height else {
        continue
      }
      let sourceOffset = y * frame.rowBytes + x * components
      let targetOffset = targetY * frame.rowBytes + targetX * components
      for component in 0..<components {
        shifted[targetOffset + component] = frame.bytes[sourceOffset + component]
      }
    }
  }
  return try StampedFrame(
    sequence: frame.sequence,
    captureNanoseconds: frame.captureNanoseconds,
    cameraConfigurationID: frame.cameraConfigurationID,
    width: frame.width,
    height: frame.height,
    rowBytes: frame.rowBytes,
    pixelFormat: frame.pixelFormat,
    bytes: OwnedFrameBytes(shifted)
  )
}

private func targetStrokes(center: PaperPixelPoint, radius: Int) -> [SimulatedPaperStroke] {
  let vertices = (0..<8).map { index in
    let angle = Double(index) * .pi / 4
    return PaperPixelPoint(
      x: center.x + Int((Double(radius) * cos(angle)).rounded()),
      y: center.y + Int((Double(radius) * sin(angle)).rounded())
    )
  }
  return (0..<8).map { index in
    SimulatedPaperStroke(start: vertices[index], end: vertices[(index + 1) % 8])
  }
}

private func rejectionReason(
  _ outcome: IsolatedInkObservationOutcome
) -> IsolatedInkRejectionReason? {
  guard case .rejected(let rejection) = outcome else { return nil }
  return rejection.reason
}
