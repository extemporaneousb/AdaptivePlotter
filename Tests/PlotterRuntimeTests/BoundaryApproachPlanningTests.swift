import PlotterModel
import Testing

@testable import PlotterRuntime

@Suite("Boundary approach planning")
struct BoundaryApproachPlanningTests {
  @Test("renewal length cannot alter admitted direction, feed, or hard bounds")
  func requestReconstruction() throws {
    let request = BoundaryMotionRequest(
      direction: .negativeY,
      segment: RelativeJogRequest(
        delta: try Vector2(dx: 0, dy: -10),
        feedMMPerMinute: 275
      ),
      renewalBounds: BoundaryMotionSegmentBounds(minimumMM: 2, fallbackMM: 10, maximumMM: 40)
    )

    let coarse = request.segment(lengthMM: 200)
    #expect(coarse.delta == (try Vector2(dx: 0, dy: -40)))
    #expect(coarse.feedMMPerMinute == 275)

    let fine = request.segment(lengthMM: 0.1)
    #expect(fine.delta == (try Vector2(dx: 0, dy: -2)))
    #expect(fine.feedMMPerMinute == 275)
  }

  @Test("first exact probe can accelerate to 40 mm and later advice only decreases")
  func tieredMonotonicApproach() async throws {
    let camera = CameraConfigurationID()
    let source = FrameSourceIdentity.live(CameraDeviceID(rawValue: "camera"))
    let envelope = try rectangle(maxX: 220)
    let planner = BoundaryApproachPlanner(
      seed: try observation(
        source: source, camera: camera, capture: 1, machineX: 0, pixelX: 10,
        envelope: envelope
      )
    )

    let first = await planner.advise(
      after: try observation(
        source: source, camera: camera, capture: 2, machineX: 10, pixelX: 20,
        envelope: envelope
      )
    )
    #expect(first.nextSegmentLengthMM == 40)
    #expect(first.basis == .projectedEnvelope)

    let second = await planner.advise(
      after: try observation(
        source: source, camera: camera, capture: 3, machineX: 90, pixelX: 100,
        envelope: envelope
      )
    )
    #expect(second.nextSegmentLengthMM == 40)

    let third = await planner.advise(
      after: try observation(
        source: source, camera: camera, capture: 4, machineX: 150, pixelX: 160,
        envelope: envelope
      )
    )
    #expect(third.nextSegmentLengthMM == 20)

    let fourth = await planner.advise(
      after: try observation(
        source: source, camera: camera, capture: 5, machineX: 190, pixelX: 200,
        envelope: envelope
      )
    )
    #expect(fourth.nextSegmentLengthMM == 5)
  }

  @Test("missing or incompatible frames fall back to 10 mm and cannot re-accelerate")
  func conservativeFallback() async throws {
    let camera = CameraConfigurationID()
    let source = FrameSourceIdentity.live(CameraDeviceID(rawValue: "camera"))
    let envelope = try rectangle(maxX: 220)
    let planner = BoundaryApproachPlanner(
      seed: try observation(
        source: source, camera: camera, capture: 10, machineX: 0, pixelX: 10,
        envelope: envelope
      )
    )
    #expect(
      await planner.advise(
        after: try observation(
          source: source, camera: camera, capture: 11, machineX: 10, pixelX: 20,
          envelope: envelope
        )
      ).nextSegmentLengthMM == 40
    )

    let missing = await planner.advise(after: nil)
    #expect(missing.nextSegmentLengthMM == 10)
    #expect(missing.basis == .missingObservationFallback)

    let later = await planner.advise(
      after: try observation(
        source: source, camera: camera, capture: 12, machineX: 20, pixelX: 30,
        envelope: envelope
      )
    )
    #expect(later.nextSegmentLengthMM == 10)

    let stale = await planner.advise(
      after: try observation(
        source: source, camera: camera, capture: 12, machineX: 30, pixelX: 40,
        envelope: envelope
      )
    )
    #expect(stale.nextSegmentLengthMM == 10)
    #expect(stale.basis == .incompatibleObservationFallback)
  }

  private func observation(
    source: FrameSourceIdentity,
    camera: CameraConfigurationID,
    capture: UInt64,
    machineX: Double,
    pixelX: Double,
    envelope: Polyline<CameraPixelSpace>
  ) throws -> BoundaryApproachObservation {
    BoundaryApproachObservation(
      source: source,
      cameraConfigurationID: camera,
      captureNanoseconds: capture,
      machinePosition: try MachinePosition(x: machineX, y: 0),
      toolContact: try Point2(x: pixelX, y: 50),
      toolConfidence: 0.9,
      drawingFrame: envelope,
      drawingFrameConfidence: 0.8
    )
  }

  private func rectangle(maxX: Double) throws -> Polyline<CameraPixelSpace> {
    try Polyline(points: [
      Point2(x: 0, y: 0), Point2(x: maxX, y: 0),
      Point2(x: maxX, y: 100), Point2(x: 0, y: 100), Point2(x: 0, y: 0),
    ])
  }
}
