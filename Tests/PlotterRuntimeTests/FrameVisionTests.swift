import Foundation
import PlotterModel
import PlotterRuntime
import PlotterTestSupport
import Testing

@Suite("Recorded frames and deterministic measurement")
struct FrameVisionTests {
  @Test("owned bytes do not alias later source mutation")
  func ownedBytes() {
    var source = Data([1, 2, 3, 4])
    let owned = OwnedFrameBytes(copying: source)
    source[0] = 99
    #expect(owned[0] == 1)
  }

  @Test("stable selection requires freshness, one camera configuration, and measured stability")
  func stableSelection() throws {
    let camera = CameraConfigurationID()
    let frames = try [
      grayFrame(value: 100, sequence: 1, time: 100, camera: camera),
      grayFrame(value: 101, sequence: 2, time: 110, camera: camera),
      grayFrame(value: 100, sequence: 3, time: 120, camera: camera),
    ]
    let requirement = try StableFrameRequirement(
      minimumFrameCount: 3,
      newerThanMonotonicNanoseconds: 90,
      maximumSpanNanoseconds: 50
    )
    let policy = try FrameStabilityPolicy(
      maximumMeanAbsoluteByteDelta: 1,
      algorithmRevision: "byte-delta-v1-test-only"
    )
    guard
      case .selected(let frame, let supporting, let maximumDelta) = StableFrameSelector.select(
        from: frames,
        requirement: requirement,
        policy: policy
      )
    else {
      Issue.record("expected stable selection")
      return
    }
    #expect(frame.id == frames[2].id)
    #expect(supporting == frames.map(\.id))
    #expect(maximumDelta == 1)

    let staleRequirement = try StableFrameRequirement(
      minimumFrameCount: 2,
      newerThanMonotonicNanoseconds: 200,
      maximumSpanNanoseconds: 50
    )
    #expect(
      StableFrameSelector.select(from: frames, requirement: staleRequirement, policy: policy)
        == .blocked(.noFreshFrame(newerThanNanoseconds: 200)))

    var changed = frames
    changed[2] = try grayFrame(value: 100, sequence: 3, time: 120, camera: CameraConfigurationID())
    #expect(
      StableFrameSelector.select(from: changed, requirement: requirement, policy: policy)
        == .blocked(.cameraConfigurationChanged))

    var unstable = frames
    unstable[2] = try grayFrame(value: 140, sequence: 3, time: 120, camera: camera)
    guard
      case .blocked(.unstable) = StableFrameSelector.select(
        from: unstable,
        requirement: requirement,
        policy: policy
      )
    else {
      Issue.record("expected unstable blocker")
      return
    }

    let repeatedSequence = [frames[0], frames[0]]
    #expect(
      StableFrameSelector.select(
        from: repeatedSequence,
        requirement: requirement,
        policy: policy
      ) == .blocked(.nonMonotonicSequence(previous: 1, next: 1))
    )
    let reversedTime = [
      frames[0],
      try grayFrame(value: 100, sequence: 2, time: 90, camera: camera),
    ]
    #expect(
      StableFrameSelector.select(
        from: reversedTime,
        requirement: requirement,
        policy: policy
      ) == .blocked(.nonMonotonicTimestamp(previous: 100, next: 90))
    )
  }

  @Test("frame decoding revalidates the content hash")
  func decodingRevalidatesHash() throws {
    let frame = try grayFrame(value: 1, sequence: 1, time: 1, camera: CameraConfigurationID())
    let encoded = try JSONEncoder().encode(frame)
    var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    object["contentSHA256"] = String(repeating: "0", count: 64)
    let tampered = try JSONSerialization.data(withJSONObject: object)
    #expect(throws: FrameError.contentHashMismatch) {
      _ = try JSONDecoder().decode(StampedFrame.self, from: tampered)
    }
  }

  @Test("VisionWorker measures one exact recorded frame deterministically")
  func exactFrameMeasurement() async throws {
    let simulator = PaperSceneSimulator(width: 16, height: 12)
    let frame = try simulator.render(
      strokes: [
        SimulatedPaperStroke(
          start: PaperPixelPoint(x: 2, y: 5),
          end: PaperPixelPoint(x: 12, y: 5),
          green: 190
        )
      ],
      sequence: 7,
      captureNanoseconds: 700,
      cameraConfigurationID: CameraConfigurationID()
    )
    let request = MeasurementRequest.greenInk(
      region: PixelRect(x: 0, y: 0, width: 16, height: 12),
      thresholds: GreenPixelThresholds(minimumGreen: 150, minimumGreenExcess: 80),
      algorithmRevision: "synthetic-green-v1"
    )
    let worker = VisionWorker()
    let first = try await worker.measure(request, in: frame)
    let second = try await worker.measure(request, in: frame)
    #expect(first == second)
    #expect(first.frameID == frame.id)
    #expect(first.frameSHA256 == frame.contentSHA256)
    #expect(first.matchingPixelCount == 11)
    #expect(first.boundingBox == PixelRect(x: 2, y: 5, width: 11, height: 1))
    #expect(first.centroid == (try Point2<CameraPixelSpace>(x: 7, y: 5)))
    #expect(first.overlayMeasurement?.matches(DisplayedFrame(source: .simulated, frame: frame)) == true)
  }

  @Test("vision honors padded BGRA row stride")
  func paddedBGRARowStride() async throws {
    let camera = CameraConfigurationID()
    let bytes: [UInt8] = [
      255, 255, 255, 255, 30, 200, 20, 255, 77, 77, 77, 77,
      255, 255, 255, 255, 255, 255, 255, 255, 88, 88, 88, 88,
    ]
    let frame = try StampedFrame(
      sequence: 1,
      captureNanoseconds: 1,
      cameraConfigurationID: camera,
      width: 2,
      height: 2,
      rowBytes: 12,
      pixelFormat: .bgra8,
      bytes: OwnedFrameBytes(bytes)
    )
    let result = try await VisionWorker().measure(
      .greenInk(
        region: PixelRect(x: 0, y: 0, width: 2, height: 2),
        thresholds: GreenPixelThresholds(minimumGreen: 150, minimumGreenExcess: 80),
        algorithmRevision: "padded-bgra-v1"
      ),
      in: frame
    )
    #expect(result.matchingPixelCount == 1)
    #expect(result.centroid == (try Point2<CameraPixelSpace>(x: 1, y: 0)))
  }

  @Test("overlay requires exact frame and camera configuration identity")
  func overlayIdentity() throws {
    let camera = CameraConfigurationID()
    let frame = try grayFrame(value: 1, sequence: 1, time: 1, camera: camera)
    let geometry = CameraPixelGeometry.point(try Point2(x: 0, y: 0))
    let measurement = CameraOverlayMeasurement(
      frameID: frame.id,
      cameraConfigurationID: camera,
      geometry: geometry,
      provenance: CameraMeasurementProvenance(operation: "test", algorithmRevision: "v1")
    )
    #expect(measurement.matches(DisplayedFrame(source: .simulated, frame: frame)))
    let otherFrame = try grayFrame(value: 1, sequence: 2, time: 2, camera: camera)
    #expect(!measurement.matches(DisplayedFrame(source: .simulated, frame: otherFrame)))
    let otherConfiguration = try grayFrame(
      value: 1, sequence: 2, time: 2, camera: CameraConfigurationID())
    #expect(!measurement.matches(DisplayedFrame(source: .simulated, frame: otherConfiguration)))
  }
}

private func grayFrame(
  value: UInt8,
  sequence: UInt64,
  time: UInt64,
  camera: CameraConfigurationID
) throws -> StampedFrame {
  try StampedFrame(
    sequence: sequence,
    captureNanoseconds: time,
    cameraConfigurationID: camera,
    width: 2,
    height: 2,
    rowBytes: 2,
    pixelFormat: .gray8,
    bytes: OwnedFrameBytes([UInt8](repeating: value, count: 4))
  )
}
