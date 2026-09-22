import Foundation
import PlotterModel
import Testing
@testable import PlotterRuntime

@Suite("Cap visual reference")
struct PenCapVisualReferenceTests {
  private let configuration = CameraConfigurationID()

  @Test("dark multicolor holder tracks an off-center anchor through translation")
  func translation() async throws {
    let initial = try scene(origins: [(20, 16)])
    let reference = try reference(initial)
    let result = try await VisionWorker().inspectPlotterScene(in: scene(origins: [(76, 38)]),
      requestedFeatures: [.penCap], penCapReference: reference)
    let cap = try #require(result.penCap.measurement)
    #expect(abs(cap.trackingPoint.x - 80) <= 1.5)
    #expect(abs(cap.trackingPoint.y - 57) <= 1.5)
    #expect(cap.boundingBox.width <= 36)
    #expect(result.algorithmRevision.contains(reference.identity))
    #expect(try JSONDecoder().decode(PenCapVisualReference.self,
      from: JSONEncoder().encode(reference)) == reference)
  }

  @Test("scale change maps the anchor rather than using the box center")
  func scale() async throws {
    let ref = try reference(scene(origins: [(20, 16)]))
    let result = try await VisionWorker().inspectPlotterScene(in: scene(origins: [(60, 32)], scale: 1.15),
      requestedFeatures: [.penCap], penCapReference: ref)
    let cap = try #require(result.penCap.measurement)
    #expect(abs(cap.trackingPoint.x - 64.6) <= 2)
    #expect(abs(cap.trackingPoint.y - 53.85) <= 2)
  }

  @Test("missing, duplicate, oversized and incompatible patterns do not produce a cap")
  func refusals() async throws {
    let ref = try reference(scene(origins: [(20, 16)]))
    for frame in [try scene(origins: []), try scene(origins: [(12, 16), (82, 40)]),
      try scene(origins: [(20, 16)], scale: 2),
      try scene(origins: [(20, 16)], configuration: CameraConfigurationID())] {
      let result = try await VisionWorker().inspectPlotterScene(in: frame,
        requestedFeatures: [.penCap], penCapReference: ref)
      #expect(result.penCap.measurement == nil)
    }
  }

  @Test("uniform dark references lack detail; a black shape with contrasting edges is usable")
  func contrast() throws {
    let empty = try scene(origins: [])
    #expect(throws: PenCapReferenceError.self) { try reference(empty) }
    #expect(try reference(scene(origins: [(20, 16)])).isValid)
  }

  @Test("short-interval implausible jump is rejected without updating the last anchor")
  func continuity() async throws {
    let initial = try scene(origins: [(12, 16)], time: 1)
    let ref = try PenCapVisualReference.capture(frame: initial,
      region: PixelRect(x: 12, y: 16, width: 28, height: 24), anchor: Point2(x: 16, y: 35))
    let worker = VisionWorker()
    let first = try await worker.inspectPlotterScene(in: initial, requestedFeatures: [.penCap], penCapReference: ref)
    #expect(first.penCap.measurement != nil)
    let jumped = try await worker.inspectPlotterScene(in: scene(origins: [(100, 16)], time: 1_000_001),
      requestedFeatures: [.penCap], penCapReference: ref)
    #expect(jumped.penCap.measurement == nil)
    #expect(jumped.penCap.diagnosticReason.contains("jumped"))
    let recovered = try await worker.inspectPlotterScene(in: scene(origins: [(16, 16)], time: 2_000_001),
      requestedFeatures: [.penCap], penCapReference: ref)
    #expect(recovered.penCap.measurement != nil)
  }

  @Test("1080p full-frame reference search remains bounded and reports camera-pixel geometry")
  func fullResolution() async throws {
    let initial = try scene(origins: [(300, 200)], scale: 3, width: 1920, height: 1080)
    let ref = try PenCapVisualReference.capture(frame: initial,
      region: PixelRect(x: 300, y: 200, width: 84, height: 72), anchor: Point2(x: 312, y: 257))
    let target = try scene(origins: [(760, 420)], scale: 3, width: 1920, height: 1080)
    let start = ContinuousClock.now
    let result = try await VisionWorker().inspectPlotterScene(in: target,
      requestedFeatures: [.penCap], penCapReference: ref)
    let elapsed = start.duration(to: .now)
    print("CAP_REFERENCE_1080P", elapsed)
    let cap = try #require(result.penCap.measurement)
    #expect(abs(cap.trackingPoint.x - 772) <= 3)
    #expect(abs(cap.trackingPoint.y - 477) <= 3)
    #expect(elapsed < .seconds(10))
  }

  @Test("black and gray structure is recognized without a chromatic pixel requirement")
  func achromatic() async throws {
    let initial = try scene(origins: [(20, 16)], monochrome: true)
    let ref = try reference(initial)
    let result = try await VisionWorker().inspectPlotterScene(in: scene(origins: [(77, 39)], monochrome: true),
      requestedFeatures: [.penCap], penCapReference: ref)
    let cap = try #require(result.penCap.measurement)
    #expect(abs(cap.trackingPoint.x - 81) <= 2)
    #expect(abs(cap.trackingPoint.y - 58) <= 2)
  }

  private func reference(_ frame: StampedFrame) throws -> PenCapVisualReference {
    try .capture(frame: frame, region: PixelRect(x: 20, y: 16, width: 28, height: 24),
      anchor: Point2(x: 24, y: 35))
  }

  private func scene(origins: [(Int, Int)], scale: Double = 1,
    configuration: CameraConfigurationID? = nil, time: UInt64 = 1,
    width: Int = 144, height: Int = 96, monochrome: Bool = false) throws -> StampedFrame {
    var bytes = [UInt8](repeating: 220, count: width * height * 4)
    for (ox, oy) in origins {
      for y in 0..<Int(24 * scale) {
        for x in 0..<Int(28 * scale) {
          let u = Int(Double(x) / scale), v = Int(Double(y) / scale)
          var rgb: [UInt8]
          if u < 7 && v > 8 { rgb = [135, 15, 20] }
          else if u > 17 && v < 17 { rgb = [25, 65, 145] }
          else if (u > 10 && u < 14) || v < 3 { rgb = [170, 165, 160] }
          else { rgb = [12, 12, 14] }
          if monochrome { rgb = Array(repeating: UInt8(rgb.map(Int.init).reduce(0, +) / 3), count: 3) }
          let i = ((oy+y)*width+ox+x)*4
          bytes[i] = rgb[0]; bytes[i+1] = rgb[1]; bytes[i+2] = rgb[2]; bytes[i+3] = 255
        }
      }
    }
    return try StampedFrame(sequence: 1, captureNanoseconds: time,
      cameraConfigurationID: configuration ?? self.configuration,
      width: width, height: height, rowBytes: width*4, pixelFormat: .rgba8,
      bytes: OwnedFrameBytes(bytes))
  }
}
