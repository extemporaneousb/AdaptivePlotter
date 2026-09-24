import Foundation
import PlotterModel
import Testing
@testable import PlotterRuntime

@Suite("Persistent holder reference admission")
struct HolderReferenceBindingTests {
  private let source = FrameSourceIdentity.live(CameraDeviceID(rawValue: "holder-camera"))
  private let mount = UUID()
  private let reframing = UUID()

  @Test("a restored holder binds to new capture UUID without changing its acquisition or anchor identity")
  func restoredReference() async throws {
    let first = try frame(origins: [(12, 16)], time: 1)
    let optical = try optics()
    let reference = try holder(first, optical: optical)
    let restored = try JSONDecoder().decode(PenCapVisualReference.self, from: JSONEncoder().encode(reference))
    let identity = restored.identity
    let worker = VisionWorker()
    let initialBinding = try #require(PenCapReferenceBinding(reference: restored,
      frame: DisplayedFrame(source: source, frame: first), opticalConfiguration: optical))
    let initial = try await worker.inspectPlotterScene(in: first, requestedFeatures: [.penCap],
      penCapReference: restored, referenceBinding: initialBinding)
    #expect(initial.penCap.measurement != nil)
    // This displacement is deliberately beyond the short-interval continuity
    // limit, but belongs to a new capture generation after restart.
    let restarted = try frame(origins: [(100, 16)], time: 1_000_001)
    #expect(restarted.cameraConfigurationID != first.cameraConfigurationID)
    let missingBinding = try await worker.inspectPlotterScene(in: restarted,
      requestedFeatures: [.penCap], penCapReference: restored)
    #expect(missingBinding.penCap.measurement == nil)
    let binding = try #require(PenCapReferenceBinding(reference: restored,
      frame: DisplayedFrame(source: source, frame: restarted), opticalConfiguration: optical))
    let result = try await worker.inspectPlotterScene(in: restarted,
      requestedFeatures: [.penCap], penCapReference: restored, referenceBinding: binding)
    let measured = try #require(result.penCap.measurement)
    #expect(abs(measured.trackingPoint.x - 104) < 1.5)
    #expect(abs(measured.trackingPoint.y - 35) < 1.5)
    #expect(result.cameraConfigurationID == restarted.cameraConfigurationID)
    #expect(restored.cameraConfigurationID == first.cameraConfigurationID)
    #expect(restored.identity == identity)
    #expect(restored.isRigidHolder)
    #expect(restored.opticalConfiguration == optical)
    // A binding is limited to the capture generation it inspected.
    let third = try frame(origins: [(100, 16)], time: 2_000_001)
    let stale = try await worker.inspectPlotterScene(in: third, requestedFeatures: [.penCap],
      penCapReference: restored, referenceBinding: binding)
    #expect(stale.penCap.measurement == nil)
  }

  @Test("different source, mount, reframing, mirror or dimensions cannot acquire a binding")
  func incompatibleOptics() throws {
    let first = try frame(origins: [(12, 16)])
    let reference = try holder(first, optical: optics())
    let current = try frame(origins: [(12, 16)])
    let displayed = DisplayedFrame(source: source, frame: current)
    for optical in [try optics(mount: UUID()), try optics(reframing: UUID()),
      try optics(mirrored: true), try optics(width: 160)] {
      #expect(PenCapReferenceBinding(reference: reference, frame: displayed,
        opticalConfiguration: optical) == nil)
    }
    let otherSource = DisplayedFrame(source: .live(CameraDeviceID(rawValue: "another-camera")), frame: current)
    #expect(PenCapReferenceBinding(reference: reference, frame: otherSource,
      opticalConfiguration: try optics()) == nil)
  }

  @Test("legacy encoding and cap meaning stay unchanged; confirmed examples cannot mix anchor purposes")
  func legacyAndBank() throws {
    let original = try frame(origins: [(12, 16)])
    let legacy = try PenCapVisualReference.capture(frame: original,
      region: PixelRect(x: 12, y: 16, width: 28, height: 24), anchor: Point2(x: 16, y: 35))
    let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
    let data = try encoder.encode(legacy)
    let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    #expect(object["purpose"] == nil)
    #expect(object["opticalConfiguration"] == nil)
    #expect(legacy.identity == RunLedger.sha256Hex(data))
    let selected = try holder(original, optical: optics())
    #expect(selected.retainingConfirmedExamples(from: legacy).confirmedExamples == nil)
    var invalid = selected
    invalid.confirmedExamples = [legacy]
    #expect(!invalid.isValid)
    let next = try frame(origins: [(12, 16)])
    let sameHolder = try holder(next, optical: optics())
    #expect(sameHolder.retainingConfirmedExamples(from: selected).isValid)
  }

  @Test("pen color and surrounding blue marks do not replace holder identity; duplicate and occluded holders refuse")
  func distractors() async throws {
    let initial = try frame(origins: [(12, 16)])
    let optical = try optics()
    let reference = try holder(initial, optical: optical)
    let target = try frame(origins: [(76, 38)], distractor: true)
    let binding = try #require(PenCapReferenceBinding(reference: reference,
      frame: DisplayedFrame(source: source, frame: target), opticalConfiguration: optical))
    let result = try await VisionWorker().inspectPlotterScene(in: target, requestedFeatures: [.penCap],
      penCapReference: reference, referenceBinding: binding)
    let measurement = try #require(result.penCap.measurement)
    #expect(abs(measurement.trackingPoint.x - 80) < 1.5)
    #expect(abs(measurement.trackingPoint.y - 57) < 1.5)
    for origins in [[(12, 16), (92, 48)], []] {
      let frame = try frame(origins: origins, distractor: true)
      let binding = try #require(PenCapReferenceBinding(reference: reference,
        frame: DisplayedFrame(source: source, frame: frame), opticalConfiguration: optical))
      let refused = try await VisionWorker().inspectPlotterScene(in: frame, requestedFeatures: [.penCap],
        penCapReference: reference, referenceBinding: binding)
      #expect(refused.penCap.measurement == nil)
      #expect(refused.penCap.diagnostics?.template?.acceptanceThreshold == 0.82)
      #expect(refused.penCap.diagnostics?.template?.requiredMargin == 0.06)
    }
  }

  private func optics(mount: UUID? = nil, reframing: UUID? = nil,
    mirrored: Bool = false, width: Int = 144) throws -> CameraOpticalConfigurationIdentity {
    try .init(source: source, sensorFormat: "fixture-rgba", width: width, height: 96,
      pixelFormat: .rgba8, orientation: .up, mirrored: mirrored, digitalZoomFactor: 1,
      lensIdentity: "fixed", focusConfiguration: "fixed", mountRevision: mount ?? self.mount,
      reframingRevision: reframing ?? self.reframing)
  }

  private func holder(_ frame: StampedFrame, optical: CameraOpticalConfigurationIdentity) throws -> PenCapVisualReference {
    try .capture(frame: frame, region: PixelRect(x: 12, y: 16, width: 28, height: 24),
      anchor: Point2(x: 16, y: 35), purpose: .rigidHolder, opticalConfiguration: optical)
  }

  private func frame(origins: [(Int, Int)], time: UInt64 = 1,
    distractor: Bool = false) throws -> StampedFrame {
    let width = 144, height = 96
    var bytes = [UInt8](repeating: 220, count: width * height * 4)
    if distractor {
      // Replaceable pen and blue ink-like marks outside the holder support.
      for y in 4..<10 { for x in 65..<138 {
        let i = (y * width + x) * 4
        bytes[i] = 5; bytes[i + 1] = 40; bytes[i + 2] = 190
      } }
    }
    for (ox, oy) in origins { for y in 0..<24 { for x in 0..<28 {
      let rgb: [UInt8]
      if x < 7 && y > 8 { rgb = [135, 15, 20] }
      else if x > 17 && y < 17 { rgb = [25, 65, 145] }
      else if (x > 10 && x < 14) || y < 3 { rgb = [170, 165, 160] }
      else { rgb = [12, 12, 14] }
      let i = ((oy + y) * width + ox + x) * 4
      bytes[i] = rgb[0]; bytes[i + 1] = rgb[1]; bytes[i + 2] = rgb[2]; bytes[i + 3] = 255
    } } }
    return try StampedFrame(sequence: 1, captureNanoseconds: time,
      cameraConfigurationID: CameraConfigurationID(), width: width, height: height,
      rowBytes: width * 4, pixelFormat: .rgba8, bytes: OwnedFrameBytes(bytes))
  }
}
