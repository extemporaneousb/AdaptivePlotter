import Foundation
import PlotterModel
import PlotterTestSupport
import Testing

@testable import PlotterRuntime

@Suite("Isolated ink observation")
struct IsolatedInkObservationTests {
  @Test("trial-local baseline isolates the new black line")
  func localBaselineLineObservation() async throws {
    let camera = CameraConfigurationID()
    let simulator = PaperSceneSimulator(width: 48, height: 32)
    let lineStart = PaperPixelPoint(x: 24, y: 16)
    let frames = try simulator.renderLocalBaselineAndLineSequence(
      preexistingInk: [],
      lineStart: lineStart,
      lineEnd: PaperPixelPoint(x: 31, y: 16),
      baselineSequence: 10,
      baselineCaptureNanoseconds: 10,
      cameraConfigurationID: camera
    )
    let outcome = await VisionWorker().observeIsolatedInk(
      IsolatedInkObservationRequest(
        localPreLineBaseline: sample(
          frames.localBaseline,
          try MachinePosition(x: 0, y: 0)
        ),
        postLine: sample(frames.postLine, try MachinePosition(x: 0, y: 0)),
        region: PixelRect(x: 0, y: 0, width: 48, height: 32),
        thresholds: thresholds,
        lineStartPoint: try Point2(x: 24, y: 16),
        tipRegistrationRevisionID: stageFourTipRevision,
        controllerSessionID: UUID(),
        coordinateRevision: 1,
        toolPaperRevision: UUID(),
        controllerPositionToleranceMM: ControllerPositionAcceptancePolicy.toleranceMM,
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
    #expect(observation.localPreLineBaseline.frameID == frames.localBaseline.id)
    #expect(observation.postLine.frameID == frames.postLine.id)
    #expect(observation.lineStartPoint == (try Point2(x: 24, y: 16)))
    #expect(observation.tipRegistrationRevisionID == stageFourTipRevision)
    #expect(observation.observedPixelCount >= 7)
    #expect(observation.residual != nil)
  }

  @Test("absent new line is a typed rejection and cannot manufacture ink")
  func absentLine() async throws {
    let camera = CameraConfigurationID()
    let simulator = PaperSceneSimulator(width: 30, height: 20)
    let existingInk = [
      SimulatedPaperStroke(
        start: PaperPixelPoint(x: 5, y: 5),
        end: PaperPixelPoint(x: 10, y: 5)
      )
    ]
    let first = try simulator.render(
      strokes: existingInk, sequence: 1, captureNanoseconds: 1,
      cameraConfigurationID: camera)
    let second = try simulator.render(
      strokes: existingInk, sequence: 2, captureNanoseconds: 2,
      cameraConfigurationID: camera)
    let outcome = await VisionWorker().observeIsolatedInk(
      IsolatedInkObservationRequest(
        localPreLineBaseline: sample(first, try MachinePosition(x: 0, y: 0)),
        postLine: sample(second, try MachinePosition(x: 0, y: 0)),
        region: PixelRect(x: 0, y: 0, width: 30, height: 20),
        thresholds: thresholds,
        lineStartPoint: try Point2(x: 19, y: 10),
        tipRegistrationRevisionID: stageFourTipRevision,
        controllerSessionID: UUID(),
        coordinateRevision: 1,
        toolPaperRevision: UUID(),
        controllerPositionToleranceMM: ControllerPositionAcceptancePolicy.toleranceMM,
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
    let outcome = await VisionWorker().observeIsolatedInk(
      lineRequest(
        baseline: sample(frames.localBaseline, pose),
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
    let outcome = await VisionWorker().observeIsolatedInk(
      lineRequest(
        baseline: sample(frames.localBaseline, try MachinePosition(x: 0, y: 0)),
        post: sample(frames.postLine, try MachinePosition(x: 0.2, y: 0))
      ))
    guard case .rejected(let rejection) = outcome,
      case .observationPoseMismatch(let distance, let tolerance) = rejection.reason
    else {
      Issue.record("expected Stage 4 pose mismatch; got \(outcome)")
      return
    }
    #expect(distance > tolerance)
  }
}
private let thresholds = InkPixelThresholds(minimumLuminanceDecrease: 20)
private let stageFourTipRevision = LearningArtifactRevisionID(
  rawValue: UUID(uuidString: "00000000-0000-0000-0000-000000000019")!
)

private func sample(
  _ frame: StampedFrame,
  _ position: MachinePosition,
  source: FrameSourceIdentity = .simulated
) -> SamePoseFrameSample {
  SamePoseFrameSample(source: source, frame: frame, controllerPosition: position)
}

private func lineFrames() throws -> SimulatedBaselineAndLineFrames {
  try PaperSceneSimulator(width: 48, height: 32).renderLocalBaselineAndLineSequence(
    preexistingInk: [],
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
    localPreLineBaseline: baseline,
    postLine: post,
    region: PixelRect(x: 6, y: 4, width: 36, height: 24),
    thresholds: thresholds,
    lineStartPoint: try! Point2(x: 24, y: 16),
    tipRegistrationRevisionID: stageFourTipRevision,
    controllerSessionID: UUID(uuidString: "00000000-0000-0000-0000-000000000020")!,
    coordinateRevision: 2,
    toolPaperRevision: UUID(uuidString: "00000000-0000-0000-0000-000000000021")!,
    controllerPositionToleranceMM: ControllerPositionAcceptancePolicy.toleranceMM,
    alignmentSearchRadiusPixels: 2,
    maximumAlignmentShiftPixels: 1,
    maximumBackgroundMeanAbsoluteDifference: 0.1,
    projectedActualStrokeDelta: try! Vector2(dx: 7, dy: 0),
    algorithmRevision: "line-test-v1",
    minimumLinePixels: 5
  )
}

private func rejectionReason(
  _ outcome: IsolatedInkObservationOutcome
) -> IsolatedInkRejectionReason? {
  guard case .rejected(let rejection) = outcome else { return nil }
  return rejection.reason
}
