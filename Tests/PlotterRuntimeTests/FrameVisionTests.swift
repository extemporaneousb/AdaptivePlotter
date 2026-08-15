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
    #expect(
      first.overlayMeasurement?.matches(DisplayedFrame(source: .simulated, frame: frame)) == true)
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

  @Test("full-frame region canonicalizes to unlocked priors and crop preserves cap scale")
  func sceneRegionPolicy() throws {
    let fullFrame = PixelRect(x: 0, y: 0, width: 640, height: 480)
    let unlocked = try PlotterSceneVisionPriors.c920StartupDefaults(
      frameWidth: 640,
      frameHeight: 480
    )
    let lockedFullFrame = try PlotterSceneVisionPriors.c920StartupDefaults(
      frameWidth: 640,
      frameHeight: 480,
      analysisRegion: fullFrame
    )
    #expect(unlocked == lockedFullFrame)

    let region = PixelRect(x: 120, y: 80, width: 320, height: 240)
    let cropped = try PlotterSceneVisionPriors.c920StartupDefaults(
      frameWidth: 640,
      frameHeight: 480,
      analysisRegion: region
    )
    #expect(cropped.capSearchRegion == region)
    #expect(cropped.minimumCapPixels == unlocked.minimumCapPixels)
    #expect(cropped.maximumCapPixels == unlocked.maximumCapPixels)
    #expect(region.width * region.height < unlocked.capSearchRegion.width * unlocked.capSearchRegion.height)
  }

  @Test("requested features execute only declared kernels and preserve cap determinism")
  func requestedFeatureKernels() async throws {
    let frame = try greenSceneFrame(rectangles: [(45, 32, 6, 10)])
    let priors = try PlotterSceneVisionPriors(
      capSearchRegion: PixelRect(x: 0, y: 20, width: 100, height: 50),
      minimumCapPixels: 20,
      maximumCapPixels: 200,
      algorithmRevision: "synthetic-plotter-scene-v1"
    )
    let worker = VisionWorker()
    let capOnly = try await worker.inspectPlotterScene(
      in: frame, requestedFeatures: [.penCap], priors: priors)
    let armatureOnly = try await worker.inspectPlotterScene(
      in: frame, requestedFeatures: [.armatureEnvelope], priors: priors)
    let combined = try await worker.inspectPlotterScene(
      in: frame, requestedFeatures: [.penCap, .armatureEnvelope], priors: priors)

    let cap = try #require(capOnly.penCap.measurement)
    #expect(cap.pixelCount == 60)
    #expect(capOnly.penCap == armatureOnly.penCap)
    #expect(capOnly.penCap == combined.penCap)
    #expect(capOnly.computation.executionCounts == [.penCap: 1])
    #expect(armatureOnly.computation.executionCounts == [.penCap: 1, .armatureEnvelope: 1])
    #expect(combined.computation.executionCounts == [.penCap: 1, .armatureEnvelope: 1])
    #expect(capOnly.overlays.map(\.provenance.kind) == [.penCap, .penCap])
    #expect(armatureOnly.overlays.map(\.provenance.kind) == [.armatureEstimate])
    let armature = try #require(combined.armatureEnvelope.estimate)
    #expect(armature.basis.contains("inferred"))
    #expect(armature.basis.contains("not segmented"))
    #expect(combined.overlays.last?.provenance.source == .inferred)
  }

  @Test("cap diagnostics distinguish no pixels rejected components and ambiguous leaders")
  func capDiagnostics() async throws {
    let worker = VisionWorker()
    let priors = try PlotterSceneVisionPriors(
      capSearchRegion: PixelRect(x: 0, y: 0, width: 120, height: 80),
      minimumCapPixels: 20,
      maximumCapPixels: 200,
      algorithmRevision: "cap-diagnostics-v1"
    )
    let none = try await worker.inspectPlotterScene(
      in: greenSceneFrame(rectangles: []), requestedFeatures: [.penCap], priors: priors)
    guard case .notFound(let noneDiagnostics) = none.penCap else {
      Issue.record("Expected no-threshold-pixel result")
      return
    }
    #expect(noneDiagnostics.thresholdPixelCount == 0)

    let rejected = try await worker.inspectPlotterScene(
      in: greenSceneFrame(rectangles: [(20, 20, 2, 2)]),
      requestedFeatures: [.penCap],
      priors: priors
    )
    guard case .candidatesRejected(let rejectedDiagnostics) = rejected.penCap else {
      Issue.record("Expected rejected candidate result")
      return
    }
    #expect(rejectedDiagnostics.componentCount == 1)
    #expect(
      rejectedDiagnostics.candidates[0].rejectionReasons.contains {
        if case .belowMinimumPixels = $0 { true } else { false }
      })

    let ambiguous = try await worker.inspectPlotterScene(
      in: greenSceneFrame(rectangles: [(20, 20, 6, 5), (60, 20, 6, 5)]),
      requestedFeatures: [.penCap],
      priors: priors
    )
    guard case .ambiguous(let counts, _) = ambiguous.penCap else {
      Issue.record("Expected equal leaders to be refused")
      return
    }
    #expect(counts == [30, 30])

    let nearEqual = try await worker.inspectPlotterScene(
      in: greenSceneFrame(rectangles: [(20, 20, 6, 5), (60, 20, 9, 3)]),
      requestedFeatures: [.penCap],
      priors: priors
    )
    guard case .ambiguous(let nearEqualCounts, _) = nearEqual.penCap else {
      Issue.record("Expected near-equal leaders to be refused")
      return
    }
    #expect(nearEqualCounts == [30, 27])

    let sparseConnectedPoints = (0..<10).flatMap { offset in
      [(20 + offset, 20 + offset), (29 - offset, 20 + offset)]
    }
    let lowConfidence = try await worker.inspectPlotterScene(
      in: greenSceneFrame(rectangles: [], greenPoints: sparseConnectedPoints),
      requestedFeatures: [.penCap],
      priors: priors
    )
    guard case .candidatesRejected(let lowConfidenceDiagnostics) = lowConfidence.penCap else {
      Issue.record("Expected low-confidence candidate to be refused")
      return
    }
    #expect(
      lowConfidenceDiagnostics.candidates[0].rejectionReasons.contains {
        if case .confidenceBelow = $0 { true } else { false }
      })
  }

  @Test("cropping reduces inspected pixels without changing object eligibility")
  func croppedInspectionCost() async throws {
    let frame = try greenSceneFrame(width: 200, height: 100, rectangles: [(60, 30, 6, 5)])
    let worker = VisionWorker()
    let unlocked = try await worker.inspectPlotterScene(
      in: frame,
      requestedFeatures: [.penCap]
    )
    let cropped = try await worker.inspectPlotterScene(
      in: frame,
      requestedFeatures: [.penCap],
      analysisRegion: PixelRect(x: 50, y: 20, width: 40, height: 30)
    )
    #expect(unlocked.penCap.measurement?.pixelCount == 30)
    #expect(cropped.penCap.measurement?.pixelCount == 30)
    #expect(cropped.computation.totalInspectedPixelCount < unlocked.computation.totalInspectedPixelCount)
  }

  @Test("operator-selected cap color changes the component admitted by typed Vision")
  func selectedPenCapColorDrivesRecognition() async throws {
    let width = 80
    let height = 60
    var pixels = [UInt8](repeating: 230, count: width * height * 4)
    for index in stride(from: 3, to: pixels.count, by: 4) { pixels[index] = 255 }
    for y in 20..<26 {
      for x in 25..<31 {
        setBGRA(&pixels, width: width, x: x, y: y, red: 45, green: 185, blue: 105)
      }
      for x in 50..<56 {
        setBGRA(&pixels, width: width, x: x, y: y, red: 30, green: 80, blue: 190)
      }
    }
    let frame = try StampedFrame(
      sequence: 1,
      captureNanoseconds: 10,
      cameraConfigurationID: CameraConfigurationID(),
      width: width,
      height: height,
      rowBytes: width * 4,
      pixelFormat: .bgra8,
      bytes: OwnedFrameBytes(pixels)
    )
    let region = PixelRect(x: 0, y: 0, width: width, height: height)
    let worker = VisionWorker()

    let green = try await worker.inspectPlotterScene(
      in: frame,
      requestedFeatures: [.penCap],
      analysisRegion: region,
      penCapColor: .green
    )
    let blue = try await worker.inspectPlotterScene(
      in: frame,
      requestedFeatures: [.penCap],
      analysisRegion: region,
      penCapColor: PenCapColor(red: 30, green: 80, blue: 190)
    )

    #expect(green.penCap.measurement?.boundingBox == PixelRect(x: 25, y: 20, width: 6, height: 6))
    #expect(blue.penCap.measurement?.boundingBox == PixelRect(x: 50, y: 20, width: 6, height: 6))
    #expect(green.algorithmRevision.contains("cap-2DB969"))
    #expect(blue.algorithmRevision.contains("cap-1E50BE"))
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
      provenance: CameraMeasurementProvenance(
        kind: .diagnostic,
        source: .diagnostic,
        algorithmRevision: "v1"
      )
    )
    #expect(measurement.matches(DisplayedFrame(source: .simulated, frame: frame)))
    let otherFrame = try grayFrame(value: 1, sequence: 2, time: 2, camera: camera)
    #expect(!measurement.matches(DisplayedFrame(source: .simulated, frame: otherFrame)))
    let otherConfiguration = try grayFrame(
      value: 1, sequence: 2, time: 2, camera: CameraConfigurationID())
    #expect(!measurement.matches(DisplayedFrame(source: .simulated, frame: otherConfiguration)))
  }
}
private func greenSceneFrame(
  width: Int = 120,
  height: Int = 80,
  rectangles: [(x: Int, y: Int, width: Int, height: Int)],
  greenPoints: [(x: Int, y: Int)] = []
) throws -> StampedFrame {
  var pixels = [UInt8](repeating: 190, count: width * height * 4)
  for index in stride(from: 3, to: pixels.count, by: 4) { pixels[index] = 255 }
  for rectangle in rectangles {
    for y in rectangle.y..<(rectangle.y + rectangle.height) {
      for x in rectangle.x..<(rectangle.x + rectangle.width) {
        setBGRA(&pixels, width: width, x: x, y: y, red: 40, green: 190, blue: 100)
      }
    }
  }
  for point in greenPoints {
    setBGRA(&pixels, width: width, x: point.x, y: point.y, red: 40, green: 190, blue: 100)
  }
  return try StampedFrame(
    sequence: 1,
    captureNanoseconds: 10,
    cameraConfigurationID: CameraConfigurationID(),
    width: width,
    height: height,
    rowBytes: width * 4,
    pixelFormat: .bgra8,
    bytes: OwnedFrameBytes(pixels)
  )
}

private func setBGRA(
  _ pixels: inout [UInt8],
  width: Int,
  x: Int,
  y: Int,
  red: UInt8,
  green: UInt8,
  blue: UInt8
) {
  let offset = (y * width + x) * 4
  pixels[offset] = blue
  pixels[offset + 1] = green
  pixels[offset + 2] = red
  pixels[offset + 3] = 255
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
