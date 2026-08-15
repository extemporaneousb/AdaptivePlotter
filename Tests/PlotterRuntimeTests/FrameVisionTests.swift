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

  @Test("locked scene region bounds every default plotter-scene pixel scan")
  func lockedSceneRegionBoundsDefaultPriors() throws {
    let region = PixelRect(x: 120, y: 80, width: 320, height: 240)
    let priors = try PlotterSceneVisionPriors.c920StartupDefaults(
      frameWidth: 640,
      frameHeight: 480,
      analysisRegion: region
    )
    #expect(priors.capSearchRegion == region)

    for scan in [
      priors.capSearchRegion,
      priors.topFrameSideRegion,
      priors.rightFrameSideRegion,
    ] {
      #expect(scan.x >= region.x)
      #expect(scan.y >= region.y)
      #expect(scan.x + scan.width <= region.x + region.width)
      #expect(scan.y + scan.height <= region.y + region.height)
    }
    #expect(priors.algorithmRevision.contains("region-120-80-320-240"))
  }

  @Test("plotter scene finds cap and robust frame sides while rejecting light and ink distractors")
  func plotterSceneFeatures() async throws {
    let width = 120
    let height = 80
    var pixels = [UInt8](repeating: 190, count: width * height * 4)
    for index in stride(from: 3, to: pixels.count, by: 4) { pixels[index] = 255 }

    for x in 10..<90 where x % 13 != 0 {
      let innerY = 12 + Int(Double(x - 10) * 0.04)
      for y in (innerY - 4)...innerY {
        setBGRA(&pixels, width: width, x: x, y: y, red: 10, green: 80, blue: 160)
      }
    }
    for y in 15..<70 where y % 17 != 0 {
      let innerX = 92 + Int(Double(y - 15) * 0.03)
      for x in innerX...(innerX + 4) {
        setBGRA(&pixels, width: width, x: x, y: y, red: 10, green: 80, blue: 160)
      }
    }
    for y in 32..<42 {
      for x in 45..<51 {
        setBGRA(&pixels, width: width, x: x, y: y, red: 50, green: 180, blue: 120)
      }
    }
    for y in 50..<52 {
      for x in 80..<82 {
        setBGRA(&pixels, width: width, x: x, y: y, red: 40, green: 190, blue: 100)
      }
    }
    for y in 60..<62 {
      for x in 5..<35 {
        setBGRA(&pixels, width: width, x: x, y: y, red: 45, green: 185, blue: 105)
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
    let priors = try PlotterSceneVisionPriors(
      capSearchRegion: PixelRect(x: 0, y: 20, width: 100, height: 50),
      topFrameSideRegion: PixelRect(x: 10, y: 5, width: 80, height: 20),
      rightFrameSideRegion: PixelRect(x: 85, y: 12, width: 20, height: 60),
      minimumCapPixels: 20,
      maximumCapPixels: 200,
      lineResidualLimitPixels: 2,
      minimumLineSupportFraction: 0.30,
      algorithmRevision: "synthetic-plotter-scene-v1"
    )
    let result = try await VisionWorker().inspectPlotterScene(in: frame, priors: priors)
    let cap = try #require(result.cap)
    #expect(result.capComponentCount == 3)
    #expect(cap.pixelCount == 60)
    #expect(cap.boundingBox == PixelRect(x: 45, y: 32, width: 6, height: 10))
    #expect(cap.centroid == (try Point2<CameraPixelSpace>(x: 47.5, y: 36.5)))
    #expect(cap.confidence > 0.6)

    let top = try #require(result.topFrameSide)
    let right = try #require(result.rightFrameSide)
    #expect(top.supportPointCount > 60)
    #expect(top.rmsResidualPixels < 1)
    #expect(top.confidence > 0.5)
    #expect(right.supportPointCount > 40)
    #expect(right.rmsResidualPixels < 1)
    #expect(right.confidence > 0.5)
    let armature = try #require(result.armature)
    let drawingFrame = try #require(result.drawingFrame)
    #expect(armature.confidence > 0.3)
    #expect(armature.basis.contains("inferred"))
    #expect(drawingFrame.confidence > 0.3)
    #expect(drawingFrame.basis.contains("inferred"))
    #expect(result.overlays.count == 6)
    #expect(result.overlays.filter { $0.provenance.kind == .penCap }.count == 2)
    #expect(result.overlays.filter { $0.provenance.kind == .measuredFrameSide }.count == 2)
    #expect(result.overlays.filter { $0.provenance.kind == .drawingFrameEstimate }.count == 1)
    #expect(result.overlays.filter { $0.provenance.kind == .armatureEstimate }.count == 1)
    #expect(
      result.overlays
        .filter { $0.provenance.kind == .armatureEstimate }
        .allSatisfy { $0.provenance.source == .inferred }
    )
    let displayed = DisplayedFrame(source: .simulated, frame: frame)
    #expect(result.overlays.allSatisfy { $0.matches(displayed) })

    let otherFrame = try StampedFrame(
      sequence: 2,
      captureNanoseconds: 11,
      cameraConfigurationID: frame.cameraConfigurationID,
      width: width,
      height: height,
      rowBytes: width * 4,
      pixelFormat: .bgra8,
      bytes: OwnedFrameBytes(pixels)
    )
    #expect(
      result.overlays.allSatisfy {
        !$0.matches(DisplayedFrame(source: .simulated, frame: otherFrame))
      })
  }

  @Test("operator-selected cap color changes the component admitted by Vision")
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
        setBGRA(&pixels, width: width, x: x, y: y, red: 190, green: 30, blue: 170)
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
      analysisRegion: region,
      penCapColor: .green
    )
    let magenta = try await worker.inspectPlotterScene(
      in: frame,
      analysisRegion: region,
      penCapColor: PenCapColor(red: 190, green: 30, blue: 170)
    )

    #expect(green.cap?.boundingBox == PixelRect(x: 25, y: 20, width: 6, height: 6))
    #expect(magenta.cap?.boundingBox == PixelRect(x: 50, y: 20, width: 6, height: 6))
    #expect(green.algorithmRevision.contains("cap-2DB969"))
    #expect(magenta.algorithmRevision.contains("cap-BE1EAA"))
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
