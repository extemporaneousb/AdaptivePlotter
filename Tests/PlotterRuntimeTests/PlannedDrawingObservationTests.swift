import Foundation
import PlotterModel
import PlotterTestSupport
import Testing

@testable import PlotterRuntime

@Suite("Planned drawing observation")
struct PlannedDrawingObservationTests {
  @Test("multi-segment planned ink yields exact-frame measured evidence")
  func multiSegmentShapeObservation() async throws {
    let fixture = try drawingFixture()
    let outcome = await VisionWorker().observePlannedDrawingInk(fixture.request)
    guard case .observed(let observation) = outcome else {
      Issue.record("expected planned drawing evidence; got \(outcome)")
      return
    }

    #expect(observation.evidence.frames == fixture.request.frames)
    #expect(observation.evidence.intendedInk == fixture.intended)
    #expect(observation.evidence.observedInk.count == 1)
    #expect(observation.evidence.observedInk[0].points.count >= 3)
    #expect(observation.evidence.residual != nil)
    #expect(observation.observedPixelCount >= 30)
    #expect(
      Set(observation.overlays.map(\.provenance.kind)) == [
        .intendedPath, .observedInk, .residual,
      ])
    #expect(
      observation.overlays.allSatisfy {
        $0.frameID == fixture.post.id
          && $0.cameraConfigurationID == fixture.post.cameraConfigurationID
      })
  }

  @Test("absent new ink is rejected without manufacturing observation evidence")
  func absentInk() async throws {
    let fixture = try drawingFixture(includeNewInk: false)
    let outcome = await VisionWorker().observePlannedDrawingInk(fixture.request)
    #expect(rejectionReason(outcome) == .inkMissing)
  }

  @Test("indistinguishable intended paths are rejected as ambiguous evidence")
  func ambiguousPathAssociation() async throws {
    let fixture = try drawingFixture()
    let duplicatedIntention = fixture.intended + fixture.intended
    let request = request(
      frames: fixture.request.frames,
      baseline: fixture.baseline,
      post: fixture.post,
      intended: duplicatedIntention
    )
    let outcome = await VisionWorker().observePlannedDrawingInk(request)
    guard let reason = rejectionReason(outcome),
      case .inkAmbiguous(let candidateCount) = reason
    else {
      Issue.record("expected ambiguous planned-path rejection; got \(outcome)")
      return
    }
    #expect(candidateCount > 0)
  }

  @Test("a request without an intended path is rejected as unsupported")
  func unsupportedDrawing() async throws {
    let fixture = try drawingFixture()
    let request = request(
      frames: fixture.request.frames,
      baseline: fixture.baseline,
      post: fixture.post,
      intended: []
    )
    let outcome = await VisionWorker().observePlannedDrawingInk(request)
    #expect(rejectionReason(outcome) == .unsupportedDrawing)
  }

  @Test("a sample outside the pinned exact frame pair is rejected")
  func mismatchedFrameIdentity() async throws {
    let fixture = try drawingFixture()
    let mismatchedPost = try PaperSceneSimulator(width: 48, height: 36).render(
      strokes: fixture.strokes,
      sequence: 12,
      captureNanoseconds: 12,
      cameraConfigurationID: CameraConfigurationID()
    )
    let request = request(
      frames: fixture.request.frames,
      baseline: fixture.baseline,
      post: mismatchedPost,
      intended: fixture.intended
    )
    let outcome = await VisionWorker().observePlannedDrawingInk(request)
    #expect(rejectionReason(outcome) == .invalidFrameIdentity)
  }

  @Test("a post-drawing frame from another controller pose is rejected")
  func mismatchedPose() async throws {
    let fixture = try drawingFixture()
    let request = request(
      frames: fixture.request.frames,
      baseline: fixture.baseline,
      post: fixture.post,
      intended: fixture.intended,
      postPosition: try MachinePosition(x: 0.2, y: 0)
    )
    let outcome = await VisionWorker().observePlannedDrawingInk(request)
    #expect(rejectionReason(outcome) == .observationPoseMismatch)
  }

  @Test("residual correspondence and overlay provenance are deterministic")
  func deterministicResidualAndOverlayProvenance() async throws {
    let fixture = try drawingFixture()
    let first = await VisionWorker().observePlannedDrawingInk(fixture.request)
    let second = await VisionWorker().observePlannedDrawingInk(fixture.request)
    #expect(first == second)
    guard case .observed(let observation) = first else {
      Issue.record("expected repeatable planned drawing observation; got \(first)")
      return
    }

    let intended = observation.overlays.filter { $0.provenance.kind == .intendedPath }
    let observed = observation.overlays.filter { $0.provenance.kind == .observedInk }
    let residual = observation.overlays.filter { $0.provenance.kind == .residual }
    #expect(intended.count == 1)
    #expect(observed.count == 1)
    #expect(!residual.isEmpty)
    #expect(intended.allSatisfy { $0.provenance.source == .planned })
    #expect(observed.allSatisfy { $0.provenance.source == .measured })
    #expect(residual.allSatisfy { $0.provenance.source == .diagnostic })
    #expect(Set(observation.overlays.map(\.provenance.algorithmRevision)).count == 1)
    #expect(
      observation.evidence.algorithmRevisions.contains {
        $0.component == "planned-drawing-observer" && $0.revision == "test-v1"
      })
    #expect(
      observation.evidence.algorithmRevisions.contains {
        $0.component == "integer-frame-alignment"
          && $0.revision == observation.alignment.estimatorRevision
      })
  }
}

private struct PlannedDrawingFixture {
  let baseline: StampedFrame
  let post: StampedFrame
  let intended: [Polyline<CameraPixelSpace>]
  let strokes: [SimulatedPaperStroke]
  let request: PlannedDrawingObservationRequest
}

private func drawingFixture(
  includeNewInk: Bool = true
) throws -> PlannedDrawingFixture {
  let camera = CameraConfigurationID()
  let simulator = PaperSceneSimulator(width: 48, height: 36)
  let strokes = [
    SimulatedPaperStroke(
      start: PaperPixelPoint(x: 8, y: 8),
      end: PaperPixelPoint(x: 32, y: 8)
    ),
    SimulatedPaperStroke(
      start: PaperPixelPoint(x: 32, y: 8),
      end: PaperPixelPoint(x: 32, y: 27)
    ),
  ]
  let baseline = try simulator.render(
    strokes: [],
    sequence: 10,
    captureNanoseconds: 10,
    cameraConfigurationID: camera
  )
  let post = try simulator.render(
    strokes: includeNewInk ? strokes : [],
    sequence: 11,
    captureNanoseconds: 11,
    cameraConfigurationID: camera
  )
  let intended = [
    try Polyline<CameraPixelSpace>(points: [
      try Point2(x: 8, y: 8),
      try Point2(x: 32, y: 8),
      try Point2(x: 32, y: 27),
    ])
  ]
  let frames = try DrawingObservationFramePair(
    source: .simulated,
    baseline: ExactFrameProvenance(frame: baseline),
    post: ExactFrameProvenance(frame: post)
  )
  return PlannedDrawingFixture(
    baseline: baseline,
    post: post,
    intended: intended,
    strokes: strokes,
    request: request(frames: frames, baseline: baseline, post: post, intended: intended)
  )
}

private func request(
  frames: DrawingObservationFramePair,
  baseline: StampedFrame,
  post: StampedFrame,
  intended: [Polyline<CameraPixelSpace>],
  postPosition: MachinePosition = try! MachinePosition(x: 0, y: 0)
) -> PlannedDrawingObservationRequest {
  PlannedDrawingObservationRequest(
    frames: frames,
    localPreDrawingBaseline: SamePoseFrameSample(
      source: .simulated,
      frame: baseline,
      controllerPosition: try! MachinePosition(x: 0, y: 0)
    ),
    postDrawing: SamePoseFrameSample(
      source: .simulated,
      frame: post,
      controllerPosition: postPosition
    ),
    region: PixelRect(x: 4, y: 4, width: 36, height: 28),
    intendedCameraPolylines: intended,
    thresholds: InkPixelThresholds(minimumLuminanceDecrease: 20),
    controllerPositionToleranceMM: MachinePositionAcceptancePolicy.toleranceMM,
    alignmentSearchRadiusPixels: 2,
    maximumAlignmentShiftPixels: 1,
    maximumBackgroundMeanAbsoluteDifference: 0.1,
    observerRevision: try! AlgorithmRevisionEvidence(
      component: "planned-drawing-observer",
      revision: "test-v1"
    )
  )
}

private func rejectionReason(
  _ outcome: PlannedDrawingObservationOutcome
) -> DrawingObservationRejectionReason? {
  guard case .rejected(let rejection) = outcome else { return nil }
  return rejection.reason
}
