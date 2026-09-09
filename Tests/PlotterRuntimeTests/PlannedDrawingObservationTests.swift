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
    let computation = try #require(observation.computation)
    #expect(computation.alignmentEvaluatedPixelCount == observation.alignment.evaluatedPixelCount)
    #expect(computation.alignmentCoarseCandidateCount == 25)
    #expect(computation.alignmentVerifiedCandidateCount == 3)
    #expect(
      computation.inkEvaluatedPixelCount
        == fixture.request.region.width * fixture.request.region.height
    )
    // The final pass visits one leaf and two segments per pixel. The bounded
    // correspondence-reference search is additional counted work.
    #expect(computation.associationEvaluationCount > observation.observedPixelCount * 3)
    #expect(computation.associationEvaluationCount <= fixture.request.maximumAssociationEvaluationCount)
    #expect(computation.cancellationCheckpointCount > 0)
    #expect(
      computation.maximumEvaluationCountBetweenCancellationChecks
        <= VisionWorker.plannedDrawingCancellationEvaluationChunkSize
    )
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
    guard case .rejected(let rejection) = outcome else { return }
    #expect(rejection.detectedPixelCount == 0)
  }

  @Test("a clearly visible displaced border produces a residual, not a correspondence failure")
  func displacedBorderRemainsMeasurable() async throws {
    let fixture = try closedBorderFixture(offsetX: 6, offsetY: 6)
    let outcome = await VisionWorker().observePlannedDrawingInk(fixture.request)
    guard case .observed(let observation) = outcome else {
      Issue.record("visible displaced border was discarded: \(outcome)")
      return
    }
    let residual = try #require(observation.evidence.residual)
    #expect(residual.maximumPixels > 4)
    #expect(residual.rootMeanSquarePixels > 2)
    #expect(observation.observedPixelCount >= 72)
    #expect(observation.evidence.frames == fixture.request.frames)
    #expect(observation.diagnosticSummary.contains("Path residual RMS"))
  }

  @Test("one distant changed pixel does not discard an otherwise measured border")
  func strayPixelDoesNotVetoBorder() async throws {
    let fixture = try closedBorderFixture(includeStrayPixel: true)
    let outcome = await VisionWorker().observePlannedDrawingInk(fixture.request)
    guard case .observed(let observation) = outcome else {
      Issue.record("visible border was discarded because of a stray pixel: \(outcome)")
      return
    }
    #expect(observation.evidence.residual != nil)
    #expect(observation.observedPixelCount == 73)
  }

  @Test("detected pixels without sampled geometry remain distinct from missing ink in durable diagnostics")
  func detectedButUnsampledPixelDiagnosticsRoundTrip() async throws {
    let fixture = try drawingFixture()
    let post = try PaperSceneSimulator(width: 48, height: 36).render(
      strokes: [SimulatedPaperStroke(
        start: PaperPixelPoint(x: 8, y: 8), end: PaperPixelPoint(x: 8, y: 8)
      )],
      sequence: 11, captureNanoseconds: 11,
      cameraConfigurationID: fixture.baseline.cameraConfigurationID
    )
    let frames = try DrawingObservationFramePair(
      source: .simulated, baseline: ExactFrameProvenance(frame: fixture.baseline),
      post: ExactFrameProvenance(frame: post)
    )
    let outcome = await VisionWorker().observePlannedDrawingInk(request(
      frames: frames, baseline: fixture.baseline, post: post, intended: fixture.intended
    ))
    guard case .rejected(let rejection) = outcome else {
      Issue.record("a single pixel cannot define a sampled path")
      return
    }
    #expect(rejection.reason == .correspondenceUnavailable)
    #expect(rejection.detectedPixelCount == 1)
    #expect(rejection.diagnosticSummary.contains("1 newly darkened pixels detected"))
    let encoded = try JSONEncoder().encode(rejection)
    #expect(try JSONDecoder().decode(DrawingObservationRejection.self, from: encoded) == rejection)
    var legacy = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    legacy.removeValue(forKey: "detectedPixelCount")
    let restored = try JSONDecoder().decode(
      DrawingObservationRejection.self, from: JSONSerialization.data(withJSONObject: legacy)
    )
    #expect(restored.reason == rejection.reason)
    #expect(restored.detectedPixelCount == nil)
    #expect(restored.diagnosticSummary.contains("Detected pixel count unavailable"))
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
      postPosition: try MachinePosition(x: 1.001, y: 0)
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

  @Test("bounded alignment matches exhaustive shifts across the 49-candidate envelope")
  func boundedAlignmentParityAcrossMaximumEnvelope() async throws {
    let exclusion = PixelRect(x: 26, y: 20, width: 18, height: 14)
    for shiftY in -3...3 {
      for shiftX in -3...3 {
        let frames = try texturedAlignmentFrames(shiftX: shiftX, shiftY: shiftY)
        let exhaustive = VisionWorker.bestIntegerAlignment(
          frames.baseline,
          frames.observation,
          excluding: exclusion,
          searchRadius: 3
        )
        let bounded = try await VisionWorker.boundedSubsampledIntegerAlignment(
          frames.baseline,
          frames.observation,
          excluding: exclusion,
          searchRadius: 3,
          baseComputation: .zero,
          checkpointHandler: nil
        )

        #expect(bounded.alignment.shiftX == shiftX)
        #expect(bounded.alignment.shiftY == shiftY)
        #expect(bounded.alignment.shiftX == exhaustive.shiftX)
        #expect(bounded.alignment.shiftY == exhaustive.shiftY)
        #expect(
          bounded.alignment.backgroundMeanAbsoluteDifference
            == exhaustive.backgroundMeanAbsoluteDifference
        )
        #expect(
          bounded.alignment.estimatorRevision
            == "bounded-subsampled-finalist-background-mad-v2"
        )
      }
    }
  }

  @Test("bounded alignment verifies three candidates and materially reduces pixel work")
  func boundedAlignmentComputationBudget() async throws {
    let frames = try texturedAlignmentFrames(shiftX: 3, shiftY: -3)
    let exclusion = PixelRect(x: 26, y: 20, width: 18, height: 14)
    let exhaustive = VisionWorker.bestIntegerAlignment(
      frames.baseline,
      frames.observation,
      excluding: exclusion,
      searchRadius: 3
    )
    let bounded = try await VisionWorker.boundedSubsampledIntegerAlignment(
      frames.baseline,
      frames.observation,
      excluding: exclusion,
      searchRadius: 3,
      baseComputation: .zero,
      checkpointHandler: nil
    )

    #expect(bounded.coarseCandidateCount == 49)
    #expect(bounded.verifiedCandidateCount == 3)
    #expect(bounded.alignment.evaluatedPixelCount * 10 < exhaustive.evaluatedPixelCount * 4)
    #expect(
      bounded.maximumEvaluationCountBetweenCancellationChecks <= frames.baseline.width
    )
  }

  @Test("alignment without background support is rejected before full verification")
  func alignmentWithoutBackgroundSupportIsRejected() async throws {
    let frames = try texturedAlignmentFrames(shiftX: 0, shiftY: 0)
    let fullFrameRegion = PixelRect(
      x: 0,
      y: 0,
      width: frames.baseline.width,
      height: frames.baseline.height
    )
    let intended = [
      try Polyline<CameraPixelSpace>(points: [
        try Point2(x: 12, y: 12),
        try Point2(x: 24, y: 12),
      ])
    ]
    let pair = try DrawingObservationFramePair(
      source: .simulated,
      baseline: ExactFrameProvenance(frame: frames.baseline),
      post: ExactFrameProvenance(frame: frames.observation)
    )
    let recorder = PlannedObservationCheckpointRecorder()

    let outcome = await VisionWorker().observePlannedDrawingInk(
      request(
        frames: pair,
        baseline: frames.baseline,
        post: frames.observation,
        intended: intended,
        region: fullFrameRegion,
        alignmentSearchRadiusPixels: 3,
        maximumAlignmentShiftPixels: 3
      ),
      checkpointHandler: { checkpoint in await recorder.receive(checkpoint) }
    )

    #expect(
      rejectionReason(outcome)
        == .algorithmFailure(code: "alignment-support-unavailable")
    )
    let checkpoints = await recorder.checkpoints
    let maximumVerifiedCandidateCount =
      checkpoints.map(\.computation.alignmentVerifiedCandidateCount).max() ?? 0
    #expect(maximumVerifiedCandidateCount == 0)
    #expect(maximumVerifiedCandidateCount <= 3)
    #expect(
      checkpoints.map(\.computation.alignmentCoarseCandidateCount).max() == 49
    )
    #expect(!checkpoints.contains { $0.stage == .alignmentCompleted })
  }

  @Test("a verified shift outside the accepted maximum is refused")
  func excessiveVerifiedAlignmentIsRejected() async throws {
    let frames = try texturedAlignmentFrames(shiftX: 3, shiftY: 0)
    let intended = [
      try Polyline<CameraPixelSpace>(points: [
        try Point2(x: 24, y: 24),
        try Point2(x: 44, y: 24),
      ])
    ]
    let pair = try DrawingObservationFramePair(
      source: .simulated,
      baseline: ExactFrameProvenance(frame: frames.baseline),
      post: ExactFrameProvenance(frame: frames.observation)
    )
    let outcome = await VisionWorker().observePlannedDrawingInk(
      request(
        frames: pair,
        baseline: frames.baseline,
        post: frames.observation,
        intended: intended,
        region: PixelRect(x: 12, y: 12, width: 48, height: 36),
        alignmentSearchRadiusPixels: 3,
        maximumAlignmentShiftPixels: 2,
        maximumBackgroundMeanAbsoluteDifference: 255
      ))

    #expect(rejectionReason(outcome) == .excessiveAlignment)
  }

  @Test("full-resolution finalist residual remains the refusal authority")
  func verifiedResidualThresholdIsRejected() async throws {
    let fixture = try drawingFixture()
    let changedPost = try changingBackground(
      fixture.post,
      outside: fixture.request.region,
      value: 220
    )
    let frames = try DrawingObservationFramePair(
      source: .simulated,
      baseline: ExactFrameProvenance(frame: fixture.baseline),
      post: ExactFrameProvenance(frame: changedPost)
    )
    let outcome = await VisionWorker().observePlannedDrawingInk(
      request(
        frames: frames,
        baseline: fixture.baseline,
        post: changedPost,
        intended: fixture.intended,
        maximumAlignmentShiftPixels: 2,
        maximumBackgroundMeanAbsoluteDifference: 1
      ))

    #expect(rejectionReason(outcome) == .excessiveBackgroundResidual)
  }

  @Test(
    "alignment, extraction, and association cancellation settle without partial observation",
    arguments: [
      PlannedDrawingObservationCheckpointStage.alignmentRow,
      .inkExtractionChunk,
      .associationChunk,
    ])
  func cancellationSettlesAtKernelCheckpoint(
    stage: PlannedDrawingObservationCheckpointStage
  ) async throws {
    let fixture = try drawingFixture()
    let gate = PlannedObservationCheckpointGate(holding: stage, afterEvaluations: 1)
    let worker = VisionWorker()
    let observationTask = Task {
      await worker.observePlannedDrawingInk(
        fixture.request,
        checkpointHandler: { checkpoint in await gate.receive(checkpoint) }
      )
    }

    try await waitUntil { await gate.isHolding }
    observationTask.cancel()
    await gate.release()
    let outcome = await observationTask.value

    #expect(rejectionReason(outcome) == .computationCancelled)
    let checkpoints = await gate.checkpoints
    #expect(checkpoints.contains { $0.stage == stage })
    #expect(!checkpoints.contains { $0.stage == .observationCompleted })
    #expect(
      checkpoints.map(\.computation.maximumEvaluationCountBetweenCancellationChecks).max() ?? 0
        <= VisionWorker.plannedDrawingCancellationEvaluationChunkSize
    )
  }
}

private actor PlannedObservationCheckpointRecorder {
  private(set) var checkpoints: [PlannedDrawingObservationCheckpoint] = []

  func receive(_ checkpoint: PlannedDrawingObservationCheckpoint) {
    checkpoints.append(checkpoint)
  }
}

private actor PlannedObservationCheckpointGate {
  let holdingStage: PlannedDrawingObservationCheckpointStage
  let minimumEvaluationCount: Int
  private var continuation: CheckedContinuation<Void, Never>?
  private var didHold = false
  private(set) var checkpoints: [PlannedDrawingObservationCheckpoint] = []

  init(
    holding: PlannedDrawingObservationCheckpointStage,
    afterEvaluations minimumEvaluationCount: Int = 0
  ) {
    holdingStage = holding
    self.minimumEvaluationCount = minimumEvaluationCount
  }

  var stages: [PlannedDrawingObservationCheckpointStage] {
    checkpoints.map(\.stage)
  }

  var isHolding: Bool { continuation != nil }

  func receive(_ checkpoint: PlannedDrawingObservationCheckpoint) async {
    checkpoints.append(checkpoint)
    let relevantEvaluationCount: Int
    switch checkpoint.stage {
    case .alignmentCandidate, .alignmentRow, .alignmentCompleted:
      relevantEvaluationCount = checkpoint.computation.alignmentEvaluatedPixelCount
    case .inkExtractionChunk, .inkScanCompleted:
      relevantEvaluationCount = checkpoint.computation.inkEvaluatedPixelCount
    case .associationChunk, .associationCompleted:
      relevantEvaluationCount = checkpoint.computation.associationEvaluationCount
    case .beforeAlignment, .observationCompleted:
      relevantEvaluationCount = 0
    }
    guard checkpoint.stage == holdingStage,
      relevantEvaluationCount >= minimumEvaluationCount,
      !didHold
    else { return }
    didHold = true
    await withCheckedContinuation { continuation in
      self.continuation = continuation
    }
  }

  func release() {
    continuation?.resume()
    continuation = nil
  }
}

private struct PlannedDrawingFixture {
  let baseline: StampedFrame
  let post: StampedFrame
  let intended: [Polyline<CameraPixelSpace>]
  let strokes: [SimulatedPaperStroke]
  let request: PlannedDrawingObservationRequest
}

private func closedBorderFixture(
  offsetX: Int = 0,
  offsetY: Int = 0,
  includeStrayPixel: Bool = false
) throws -> PlannedDrawingFixture {
  let camera = CameraConfigurationID()
  let simulator = PaperSceneSimulator(width: 48, height: 36)
  let corners = [(8, 8), (30, 8), (30, 22), (8, 22), (8, 8)]
  var strokes = zip(corners, corners.dropFirst()).map { start, end in
    SimulatedPaperStroke(
      start: PaperPixelPoint(x: start.0 + offsetX, y: start.1 + offsetY),
      end: PaperPixelPoint(x: end.0 + offsetX, y: end.1 + offsetY)
    )
  }
  if includeStrayPixel {
    strokes.append(SimulatedPaperStroke(
      start: PaperPixelPoint(x: 20, y: 15), end: PaperPixelPoint(x: 20, y: 15)
    ))
  }
  let baseline = try simulator.render(
    strokes: [], sequence: 10, captureNanoseconds: 10, cameraConfigurationID: camera
  )
  let post = try simulator.render(
    strokes: strokes, sequence: 11, captureNanoseconds: 11, cameraConfigurationID: camera
  )
  let intended = [try Polyline<CameraPixelSpace>(points: corners.map {
    try Point2(x: Double($0.0), y: Double($0.1))
  })]
  let frames = try DrawingObservationFramePair(
    source: .simulated,
    baseline: ExactFrameProvenance(frame: baseline), post: ExactFrameProvenance(frame: post)
  )
  return PlannedDrawingFixture(
    baseline: baseline, post: post, intended: intended, strokes: strokes,
    request: request(frames: frames, baseline: baseline, post: post, intended: intended)
  )
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
  postPosition: MachinePosition = try! MachinePosition(x: 0, y: 0),
  region: PixelRect = PixelRect(x: 4, y: 4, width: 36, height: 28),
  alignmentSearchRadiusPixels: Int = 2,
  maximumAlignmentShiftPixels: Int = 1,
  maximumBackgroundMeanAbsoluteDifference: Double = 0.1
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
    region: region,
    intendedCameraPolylines: intended,
    thresholds: InkPixelThresholds(minimumLuminanceDecrease: 20),
    controllerPositionToleranceMM: MachinePositionAcceptancePolicy.toleranceMM,
    alignmentSearchRadiusPixels: alignmentSearchRadiusPixels,
    maximumAlignmentShiftPixels: maximumAlignmentShiftPixels,
    maximumBackgroundMeanAbsoluteDifference: maximumBackgroundMeanAbsoluteDifference,
    observerRevision: try! AlgorithmRevisionEvidence(
      component: "planned-drawing-observer",
      revision: "test-v1"
    )
  )
}

private struct TexturedAlignmentFrames {
  let baseline: StampedFrame
  let observation: StampedFrame
}

private func texturedAlignmentFrames(
  shiftX: Int,
  shiftY: Int,
  width: Int = 80,
  height: Int = 64
) throws -> TexturedAlignmentFrames {
  let camera = CameraConfigurationID()
  var baselineBytes = [UInt8](repeating: 0, count: width * height)
  var observationBytes = [UInt8](repeating: 0, count: width * height)
  for y in 0..<height {
    for x in 0..<width {
      baselineBytes[y * width + x] = UInt8((x * 37 + y * 61 + x * y * 17) % 251)
      observationBytes[y * width + x] = UInt8((x * 19 + y * 43 + 113) % 251)
    }
  }
  for y in 0..<height {
    for x in 0..<width {
      let observationX = x + shiftX
      let observationY = y + shiftY
      guard observationX >= 0, observationX < width,
        observationY >= 0, observationY < height
      else { continue }
      observationBytes[observationY * width + observationX] = baselineBytes[y * width + x]
    }
  }
  return TexturedAlignmentFrames(
    baseline: try StampedFrame(
      sequence: 100,
      captureNanoseconds: 100,
      cameraConfigurationID: camera,
      width: width,
      height: height,
      rowBytes: width,
      pixelFormat: .gray8,
      bytes: OwnedFrameBytes(baselineBytes)
    ),
    observation: try StampedFrame(
      sequence: 101,
      captureNanoseconds: 101,
      cameraConfigurationID: camera,
      width: width,
      height: height,
      rowBytes: width,
      pixelFormat: .gray8,
      bytes: OwnedFrameBytes(observationBytes)
    )
  )
}

private func changingBackground(
  _ frame: StampedFrame,
  outside region: PixelRect,
  value: UInt8
) throws -> StampedFrame {
  var bytes = Array(frame.bytes.data)
  for y in 0..<frame.height {
    for x in 0..<frame.width {
      let isInside =
        x >= region.x && x < region.x + region.width
        && y >= region.y && y < region.y + region.height
      guard !isInside else { continue }
      let offset = y * frame.rowBytes + x * frame.pixelFormat.bytesPerPixel
      for component in 0..<frame.pixelFormat.bytesPerPixel {
        bytes[offset + component] = value
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
    bytes: OwnedFrameBytes(bytes)
  )
}

private func rejectionReason(
  _ outcome: PlannedDrawingObservationOutcome
) -> DrawingObservationRejectionReason? {
  guard case .rejected(let rejection) = outcome else { return nil }
  return rejection.reason
}

private func waitUntil(
  attempts: Int = 10_000,
  condition: @escaping @Sendable () async -> Bool
) async throws {
  for _ in 0..<attempts {
    if await condition() { return }
    try await Task.sleep(nanoseconds: 100_000)
  }
  throw PlannedDrawingObservationTestError.timedOut
}

private enum PlannedDrawingObservationTestError: Error {
  case timedOut
}
