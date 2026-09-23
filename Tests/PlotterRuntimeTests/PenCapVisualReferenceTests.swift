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

  @Test("a clipped high-score reference explains its rejection for single and confirmed-example searches")
  func clippedReferenceDiagnostics() throws {
    let width = 320, height = 240
    let original = try scene(origins: [(80, 64)], scale: 4, width: width, height: height)
    let reference = try PenCapVisualReference.capture(frame: original,
      region: PixelRect(x: 80, y: 64, width: 112, height: 96), anchor: Point2(x: 96, y: 140))
    let target = try scene(origins: [(0, 64)], scale: 4, width: width, height: height)
    var pixels = target.bytes.withUnsafeBytes { Array($0) }
    target.bytes.withUnsafeBytes { bytes in
      // The object starts one camera pixel beyond the left edge. Its bounded
      // reference samples still match, but the transformed rectangle is clipped.
      for y in 0..<height {
        for x in 0..<(width - 1) {
          let i = (y * width + x) * 4
          for c in 0..<4 { pixels[i + c] = bytes[i + 4 + c] }
        }
      }
    }
    let clipped = try StampedFrame(sequence: 2, captureNanoseconds: 2,
      cameraConfigurationID: configuration, width: width, height: height,
      rowBytes: width * 4, pixelFormat: .rgba8, bytes: OwnedFrameBytes(pixels))
    var bank = reference
    bank.confirmedExamples = [reference, reference]
    for selected in [reference, bank] {
      let result = try PenCapTemplateMatcher.detect(frame: clipped, reference: selected,
        region: PixelRect(x: 0, y: 0, width: width, height: height), searchCenter: try Point2(x: 15, y: 140))
      #expect(result.measurement == nil)
      let diagnostic = try #require(result.diagnostics?.template)
      #expect(try #require(diagnostic.candidates.first).score >= diagnostic.acceptanceThreshold)
      #expect(diagnostic.rejectionReason == .referenceClipped)
      #expect(diagnostic.predictionResidualPixels != nil)
      #expect(result.diagnosticReason.contains("clipped"))
      #expect(result.diagnosticReason.contains("score"))
    }
  }

  @Test("legacy v1 serialized references retain identity when examples are absent")
  func legacyIdentity() throws {
    let ref = try reference(scene(origins: [(20, 16)]))
    let encoder = JSONEncoder()
    encoder.outputFormatting = .sortedKeys
    let data = try encoder.encode(ref)
    let dictionary = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    #expect(dictionary["confirmedExamples"] == nil)
    #expect(PenCapVisualReference.revision == "cap-visual-reference-v1")
    let restored = try JSONDecoder().decode(PenCapVisualReference.self, from: data)
    #expect(restored.identity == RunLedger.sha256Hex(data))
  }

  @Test("motion prediction seeds refinement without hiding a distant match or resolving a duplicate")
  func predictionDoesNotGrantIdentity() async throws {
    let ref = try reference(scene(origins: [(20, 16)]))
    let hint = try Point2<CameraPixelSpace>(x: 24, y: 35)
    let distant = try await VisionWorker().inspectPlotterScene(in: scene(origins: [(92, 48)]),
      requestedFeatures: [.penCap], penCapReference: ref, searchCenter: hint)
    let cap = try #require(distant.penCap.measurement)
    #expect(abs(cap.trackingPoint.x - 96) <= 1.5)
    #expect(abs(cap.trackingPoint.y - 67) <= 1.5)
    let diagnostics = try #require(distant.penCap.diagnostics?.template)
    #expect(try #require(diagnostics.predictionResidualPixels) > 70)
    let duplicate = try await VisionWorker().inspectPlotterScene(in: scene(origins: [(20, 16), (92, 48)]),
      requestedFeatures: [.penCap], penCapReference: ref, searchCenter: hint)
    #expect(duplicate.penCap.measurement == nil)
    #expect(duplicate.penCap.diagnosticReason.contains("ambiguous"))
    #expect(duplicate.penCap.diagnosticReason.contains("margin"))
  }

  @Test("rejected patterns retain candidate scores and predictions")
  func rejectedDiagnostics() async throws {
    let ref = try reference(scene(origins: [(20, 16)]))
    let result = try await VisionWorker().inspectPlotterScene(in: scene(origins: [(72, 32)], scale: 2),
      requestedFeatures: [.penCap], penCapReference: ref, searchCenter: try Point2(x: 80, y: 60))
    #expect(result.penCap.measurement == nil)
    let diagnostics = try #require(result.penCap.diagnostics?.template)
    #expect(!diagnostics.candidates.isEmpty)
    #expect(diagnostics.predictionResidualPixels != nil)
    #expect(result.penCap.diagnosticReason.contains("score"))
    #expect(result.penCap.diagnosticReason.contains("camera pixels"))
  }

  @Test("confirmed appearances recover changing backgrounds without averaging anchors or self-training")
  func confirmedBackgrounds() async throws {
    let original = try scene(origins: [(20, 16)])
    let changed = try scene(origins: [(76, 38)], background: 40)
    let first = try PenCapVisualReference.capture(frame: original,
      region: PixelRect(x: 16, y: 12, width: 36, height: 32), anchor: Point2(x: 24, y: 35))
    let second = try PenCapVisualReference.capture(frame: changed,
      region: PixelRect(x: 72, y: 34, width: 36, height: 32), anchor: Point2(x: 80, y: 57))
      .retainingConfirmedExamples(from: first)
    let identity = second.identity
    for (frame, x, y) in [(original, 24.0, 35.0), (changed, 80.0, 57.0)] {
      let result = try await VisionWorker().inspectPlotterScene(in: frame,
        requestedFeatures: [.penCap], penCapReference: second)
      let cap = try #require(result.penCap.measurement)
      #expect(abs(cap.trackingPoint.x - x) <= 1.5)
      #expect(abs(cap.trackingPoint.y - y) <= 1.5)
      #expect(result.penCap.diagnostics?.template?.confirmedExampleCount == 2)
    }
    var combinedPixels = changed.bytes.withUnsafeBytes { Array($0) }
    original.bytes.withUnsafeBytes { bytes in
      for y in 12..<44 {
        for x in 16..<52 {
          let i = y * original.rowBytes + x * 4
          for c in 0..<4 { combinedPixels[i + c] = bytes[i + c] }
        }
      }
    }
    let combined = try StampedFrame(sequence: 2, captureNanoseconds: 2,
      cameraConfigurationID: configuration, width: original.width, height: original.height,
      rowBytes: original.rowBytes, pixelFormat: .rgba8, bytes: OwnedFrameBytes(combinedPixels))
    let ambiguous = try await VisionWorker().inspectPlotterScene(in: combined,
      requestedFeatures: [.penCap], penCapReference: second, searchCenter: try Point2(x: 80, y: 57))
    #expect(ambiguous.penCap.measurement == nil)
    #expect(ambiguous.penCap.diagnosticReason.contains("ambiguous"))
    #expect(try #require(ambiguous.penCap.diagnostics?.template?.competitorScore) > 0.95)
    #expect(second.identity == identity)
    #expect(try JSONDecoder().decode(PenCapVisualReference.self,
      from: JSONEncoder().encode(second)) == second)
    let bounded = first.retainingConfirmedExamples(from: second).retainingConfirmedExamples(from: second)
    #expect(try #require(bounded.confirmedExamples).count <= 2)
  }

  @Test("dark multicolor structure tolerates a uniform illumination change")
  func illumination() async throws {
    let ref = try reference(scene(origins: [(20, 16)]))
    let result = try await VisionWorker().inspectPlotterScene(in: scene(origins: [(76, 38)], illumination: 0.55),
      requestedFeatures: [.penCap], penCapReference: ref)
    let cap = try #require(result.penCap.measurement)
    #expect(abs(cap.trackingPoint.x - 80) <= 1.5)
    #expect(abs(cap.trackingPoint.y - 57) <= 1.5)
  }

  private func reference(_ frame: StampedFrame) throws -> PenCapVisualReference {
    try .capture(frame: frame, region: PixelRect(x: 20, y: 16, width: 28, height: 24),
      anchor: Point2(x: 24, y: 35))
  }

  private func scene(origins: [(Int, Int)], scale: Double = 1,
    configuration: CameraConfigurationID? = nil, time: UInt64 = 1,
    width: Int = 144, height: Int = 96, monochrome: Bool = false,
    background: UInt8 = 220, illumination: Double = 1) throws -> StampedFrame {
    var bytes = [UInt8](repeating: background, count: width * height * 4)
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
          rgb = rgb.map { UInt8((Double($0) * illumination).rounded()) }
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
