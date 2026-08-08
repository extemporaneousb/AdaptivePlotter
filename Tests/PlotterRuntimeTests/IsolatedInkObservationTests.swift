import Foundation
import PlotterModel
import PlotterRuntime
import PlotterTestSupport
import Testing

@Suite("Paired isolated-ink observation")
struct IsolatedInkObservationTests {
  @Test("anchor-only observation is available before the drawing stroke")
  func anchorOnlyObservation() async throws {
    let camera = CameraConfigurationID()
    let frames = try PaperSceneSimulator(width: 20, height: 12).renderIsolatedInkSequence(
      preexistingInk: [],
      anchor: PaperPixelPoint(x: 4, y: 6),
      lineEnd: PaperPixelPoint(x: 14, y: 6),
      cleanSequence: 1,
      cleanCaptureNanoseconds: 1,
      cameraConfigurationID: camera
    )
    let outcome = await VisionWorker().observeAnchorDot(AnchorDotObservationRequest(
      cleanReference: frames.cleanReference,
      anchoredBaseline: frames.anchoredBaseline,
      region: PixelRect(x: 0, y: 0, width: 20, height: 12),
      thresholds: GreenPixelThresholds(minimumGreen: 150, minimumGreenExcess: 80),
      algorithmRevision: "anchor-test-v1"
    ))
    guard case .observed(let observation) = outcome else {
      Issue.record("expected anchor observation before stroke")
      return
    }
    #expect(observation.centroid == (try Point2(x: 4, y: 6)))
    #expect(observation.pixelCount == 5)
    #expect(observation.overlay.frameID == frames.anchoredBaseline.id)
  }

  @Test("clean to anchor and anchor to line isolate new ink and deterministic residual")
  func pairedObservation() async throws {
    let camera = CameraConfigurationID()
    let frames = try PaperSceneSimulator(width: 24, height: 16).renderIsolatedInkSequence(
      preexistingInk: [
        SimulatedPaperStroke(
          start: PaperPixelPoint(x: 1, y: 2),
          end: PaperPixelPoint(x: 20, y: 2)
        )
      ],
      anchor: PaperPixelPoint(x: 5, y: 8),
      lineEnd: PaperPixelPoint(x: 18, y: 8),
      cleanSequence: 1,
      cleanCaptureNanoseconds: 100,
      cameraConfigurationID: camera
    )
    let request = IsolatedInkObservationRequest(
      cleanReference: frames.cleanReference,
      anchoredBaseline: frames.anchoredBaseline,
      postLine: frames.postLine,
      region: PixelRect(x: 0, y: 0, width: 24, height: 16),
      thresholds: GreenPixelThresholds(minimumGreen: 150, minimumGreenExcess: 80),
      projectedActualStrokeDelta: try Vector2(dx: 13, dy: 0),
      algorithmRevision: "isolated-test-v1"
    )
    let outcome = await VisionWorker().observeIsolatedInk(request)
    guard case .observed(let observation) = outcome else {
      Issue.record("expected observed isolated line")
      return
    }
    #expect(observation.anchorCentroid == (try Point2(x: 5, y: 8)))
    #expect(observation.anchorPixelCount == 5)
    #expect(observation.observedPixelCount == 12)
    #expect(observation.observedCentreline.points.allSatisfy { $0.y == 8 })
    #expect(observation.intendedLine?.end == (try Point2(x: 18, y: 8)))
    #expect(abs((observation.residual?.rootMeanSquareEndpointPixels ?? -1) - sqrt(2)) < 1e-12)
    #expect(observation.residual?.maximumEndpointPixels == 2)
    #expect(observation.residual?.rootMeanSquareCrossTrackPixels == 0)
    #expect(observation.overlays.first?.frameID == frames.postLine.id)
    #expect(observation.overlays.allSatisfy { $0.cameraConfigurationID == camera })
    #expect(observation.cleanReference.frameSHA256 == frames.cleanReference.contentSHA256)
    #expect(observation.anchoredBaseline.frameID == frames.anchoredBaseline.id)
    #expect(observation.postLine.frameID == frames.postLine.id)
  }

  @Test("without projected camera delta result remains relative-only")
  func relativeOnly() async throws {
    let camera = CameraConfigurationID()
    let frames = try PaperSceneSimulator(width: 20, height: 12).renderIsolatedInkSequence(
      preexistingInk: [],
      anchor: PaperPixelPoint(x: 3, y: 6),
      lineEnd: PaperPixelPoint(x: 14, y: 6),
      cleanSequence: 1,
      cleanCaptureNanoseconds: 1,
      cameraConfigurationID: camera
    )
    let outcome = await VisionWorker().observeIsolatedInk(request(frames, projection: nil))
    guard case .observed(let observation) = outcome else {
      Issue.record("expected relative observation")
      return
    }
    #expect(observation.intendedLine == nil)
    #expect(observation.residual == nil)
    #expect(observation.displacementPixels.magnitude > 0)
    #expect(observation.orientationRadians.isFinite)
  }

  @Test("padded rows are honored while pre-existing green remains excluded")
  func paddedRows() async throws {
    let camera = CameraConfigurationID()
    let clean = try inkFrame(
      sequence: 1, time: 1, camera: camera, rowBytes: 36,
      greenPixels: Set((1...6).map { InkTestPoint(x: $0, y: 1) }))
    let anchorPoints: Set<InkTestPoint> = [
      InkTestPoint(x: 3, y: 5), InkTestPoint(x: 4, y: 5), InkTestPoint(x: 5, y: 5),
    ]
    let anchored = try inkFrame(
      sequence: 2, time: 2, camera: camera, rowBytes: 40,
      greenPixels: Set((1...6).map { InkTestPoint(x: $0, y: 1) }).union(anchorPoints))
    let linePoints = Set((1...5).map { InkTestPoint(x: 7, y: $0) })
    let post = try inkFrame(
      sequence: 3, time: 3, camera: camera, rowBytes: 44,
      greenPixels: Set((1...6).map { InkTestPoint(x: $0, y: 1) })
        .union(anchorPoints).union(linePoints))
    let frames = SimulatedIsolatedInkFrames(
      cleanReference: clean, anchoredBaseline: anchored, postLine: post)
    let outcome = await VisionWorker().observeIsolatedInk(
      request(frames, projection: try Vector2(dx: 0, dy: -4), minimumLinePixels: 5))
    guard case .observed(let observation) = outcome else {
      Issue.record("expected padded-row observation")
      return
    }
    #expect(observation.anchorPixelCount == 3)
    #expect(observation.observedPixelCount == 5)
  }

  @Test("camera, dimensions, pixel format, and frame order mismatches are typed")
  func compatibilityRejections() async throws {
    let camera = CameraConfigurationID()
    let otherCamera = CameraConfigurationID()
    let clean = try inkFrame(sequence: 1, time: 1, camera: camera, greenPixels: [])
    let anchored = try inkFrame(
      sequence: 2, time: 2, camera: camera,
      greenPixels: [InkTestPoint(x: 2, y: 2), InkTestPoint(x: 3, y: 2), InkTestPoint(x: 4, y: 2)])
    let wrongCamera = try inkFrame(
      sequence: 3, time: 3, camera: otherCamera,
      greenPixels: Set((2...8).map { InkTestPoint(x: $0, y: 2) }))
    let mismatch = SimulatedIsolatedInkFrames(
      cleanReference: clean, anchoredBaseline: anchored, postLine: wrongCamera)
    let cameraOutcome = await VisionWorker().observeIsolatedInk(request(mismatch, projection: nil))
    #expect(rejectionReason(cameraOutcome) == .cameraConfigurationMismatch)

    let stale = SimulatedIsolatedInkFrames(
      cleanReference: clean,
      anchoredBaseline: anchored,
      postLine: try inkFrame(
        sequence: 3, time: 2, camera: camera,
        greenPixels: Set((2...8).map { InkTestPoint(x: $0, y: 2) }))
    )
    let orderOutcome = await VisionWorker().observeIsolatedInk(request(stale, projection: nil))
    #expect(rejectionReason(orderOutcome) == .framesNotStrictlyIncreasing)

    let dimensionPost = try StampedFrame(
      sequence: 3, captureNanoseconds: 3, cameraConfigurationID: camera,
      width: 9, height: 8, rowBytes: 36, pixelFormat: .bgra8,
      bytes: OwnedFrameBytes([UInt8](repeating: 255, count: 36 * 8)))
    let dimensionMismatch = SimulatedIsolatedInkFrames(
      cleanReference: clean, anchoredBaseline: anchored, postLine: dimensionPost)
    #expect(
      rejectionReason(await VisionWorker().observeIsolatedInk(request(dimensionMismatch, projection: nil)))
        == .dimensionMismatch)

    let grayPost = try StampedFrame(
      sequence: 3, captureNanoseconds: 3, cameraConfigurationID: camera,
      width: 8, height: 8, rowBytes: 8, pixelFormat: .gray8,
      bytes: OwnedFrameBytes([UInt8](repeating: 255, count: 64)))
    let pixelMismatch = SimulatedIsolatedInkFrames(
      cleanReference: clean, anchoredBaseline: anchored, postLine: grayPost)
    #expect(
      rejectionReason(await VisionWorker().observeIsolatedInk(request(pixelMismatch, projection: nil)))
        == .pixelFormatMismatch)
  }

  @Test("missing, too-small, ambiguous, and non-line-like evidence have direct reasons")
  func evidenceRejections() async throws {
    let camera = CameraConfigurationID()
    let blank = try inkFrame(sequence: 1, time: 1, camera: camera, greenPixels: [])
    let blank2 = try inkFrame(sequence: 2, time: 2, camera: camera, greenPixels: [])
    let blank3 = try inkFrame(sequence: 3, time: 3, camera: camera, greenPixels: [])
    let missing = SimulatedIsolatedInkFrames(
      cleanReference: blank, anchoredBaseline: blank2, postLine: blank3)
    #expect(rejectionReason(await VisionWorker().observeIsolatedInk(request(missing, projection: nil))) == .anchorMissing)

    let smallAnchor = try inkFrame(
      sequence: 2, time: 2, camera: camera,
      greenPixels: [InkTestPoint(x: 2, y: 2)])
    let tooSmall = SimulatedIsolatedInkFrames(
      cleanReference: blank, anchoredBaseline: smallAnchor, postLine: blank3)
    #expect(
      rejectionReason(await VisionWorker().observeIsolatedInk(request(tooSmall, projection: nil)))
        == .anchorTooSmall(actualPixels: 1, minimumPixels: 3))

    let twoAnchors: Set<InkTestPoint> = [
      InkTestPoint(x: 1, y: 2), InkTestPoint(x: 2, y: 2), InkTestPoint(x: 3, y: 2),
      InkTestPoint(x: 5, y: 6), InkTestPoint(x: 6, y: 6), InkTestPoint(x: 7, y: 6),
    ]
    let ambiguousAnchor = try inkFrame(
      sequence: 2, time: 2, camera: camera, greenPixels: twoAnchors)
    let ambiguous = SimulatedIsolatedInkFrames(
      cleanReference: blank, anchoredBaseline: ambiguousAnchor,
      postLine: try inkFrame(sequence: 3, time: 3, camera: camera, greenPixels: twoAnchors))
    #expect(
      rejectionReason(await VisionWorker().observeIsolatedInk(request(ambiguous, projection: nil)))
        == .anchorAmbiguous(candidateCount: 2))

    let anchor: Set<InkTestPoint> = [
      InkTestPoint(x: 1, y: 1), InkTestPoint(x: 2, y: 1), InkTestPoint(x: 3, y: 1),
    ]
    let square: Set<InkTestPoint> = Set((5...7).flatMap { y in
      (5...7).map { x in InkTestPoint(x: x, y: y) }
    })
    let nonLineFrames = SimulatedIsolatedInkFrames(
      cleanReference: blank,
      anchoredBaseline: try inkFrame(sequence: 2, time: 2, camera: camera, greenPixels: anchor),
      postLine: try inkFrame(
        sequence: 3, time: 3, camera: camera, greenPixels: anchor.union(square)))
    guard case .lineNotLineLike = rejectionReason(
      await VisionWorker().observeIsolatedInk(request(nonLineFrames, projection: nil)))
    else {
      Issue.record("expected non-line-like rejection")
      return
    }

    let lineMissingFrames = SimulatedIsolatedInkFrames(
      cleanReference: blank,
      anchoredBaseline: try inkFrame(sequence: 2, time: 2, camera: camera, greenPixels: anchor),
      postLine: try inkFrame(sequence: 3, time: 3, camera: camera, greenPixels: anchor)
    )
    #expect(
      rejectionReason(await VisionWorker().observeIsolatedInk(request(lineMissingFrames, projection: nil)))
        == .lineMissing)

    let firstLine = Set((1...5).map { InkTestPoint(x: 6, y: $0) })
    let secondLine = Set((1...5).map { InkTestPoint(x: 4, y: $0) })
    let ambiguousLineFrames = SimulatedIsolatedInkFrames(
      cleanReference: blank,
      anchoredBaseline: try inkFrame(sequence: 2, time: 2, camera: camera, greenPixels: anchor),
      postLine: try inkFrame(
        sequence: 3, time: 3, camera: camera,
        greenPixels: anchor.union(firstLine).union(secondLine))
    )
    #expect(
      rejectionReason(await VisionWorker().observeIsolatedInk(request(ambiguousLineFrames, projection: nil)))
        == .lineAmbiguous(candidateCount: 2))
  }
}

private struct InkTestPoint: Hashable {
  let x: Int
  let y: Int
}

private func request(
  _ frames: SimulatedIsolatedInkFrames,
  projection: Vector2<CameraPixelSpace>?,
  minimumLinePixels: Int = 5
) -> IsolatedInkObservationRequest {
  IsolatedInkObservationRequest(
    cleanReference: frames.cleanReference,
    anchoredBaseline: frames.anchoredBaseline,
    postLine: frames.postLine,
    region: PixelRect(x: 0, y: 0, width: frames.cleanReference.width, height: frames.cleanReference.height),
    thresholds: GreenPixelThresholds(minimumGreen: 150, minimumGreenExcess: 80),
    projectedActualStrokeDelta: projection,
    algorithmRevision: "isolated-test-v1",
    minimumLinePixels: minimumLinePixels
  )
}

private func rejectionReason(
  _ outcome: IsolatedInkObservationOutcome
) -> IsolatedInkRejectionReason? {
  guard case .rejected(let rejection) = outcome else { return nil }
  return rejection.reason
}

private func inkFrame(
  sequence: UInt64,
  time: UInt64,
  camera: CameraConfigurationID,
  rowBytes: Int = 32,
  greenPixels: Set<InkTestPoint>
) throws -> StampedFrame {
  let width = 8
  let height = 8
  var bytes = [UInt8](repeating: 255, count: rowBytes * height)
  for point in greenPixels where point.x >= 0 && point.x < width && point.y >= 0 && point.y < height {
    let offset = point.y * rowBytes + point.x * 4
    bytes[offset] = 20
    bytes[offset + 1] = 190
    bytes[offset + 2] = 30
    bytes[offset + 3] = 255
  }
  return try StampedFrame(
    sequence: sequence,
    captureNanoseconds: time,
    cameraConfigurationID: camera,
    width: width,
    height: height,
    rowBytes: rowBytes,
    pixelFormat: .bgra8,
    bytes: OwnedFrameBytes(bytes)
  )
}
