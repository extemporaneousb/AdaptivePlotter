import Foundation
import PlotterModel
import Testing
@testable import PlotterRuntime

@Suite("Explicit sampled color marker")
struct SampledColorMarkerTests {
  let source = FrameSourceIdentity.live(CameraDeviceID(rawValue: "marker-fixture"))
  let mount = UUID()
  let reframing = UUID()

  @Test("one tap records its seed separately from the centroid and survives brightness changes without adaptation")
  func brightnessAndAnchor() async throws {
    let optical = try optics()
    let first = try frame()
    let reference = try SampledColorMarkerReference.capture(frame: first, point: Point2(x: 31, y: 32),
      opticalConfiguration: optical)
    #expect(reference.selectionPoint != reference.acquisitionAnchor)
    let identity = reference.identity
    for (gain, offset) in [(0.5, 0.0), (0.75, 0.0), (1.0, 0.0), (1.5, 0.0), (1.0, 35.0)] {
      let target = try frame(gain: gain, offset: offset)
      let measurement = try #require(try await detect(reference, in: target, optical: optical).measurement)
      #expect(measurement.referenceAnchor == measurement.centroid)
      #expect(measurement.trackingPoint.distance(to: reference.acquisitionAnchor) < 0.01)
      #expect(reference.identity == identity)
      let anchor = try ToolCapAnchorEstimate(componentCentroid: measurement.centroid,
        componentBounds: AxisAlignedBounds(minX: Double(measurement.boundingBox.x),
          minY: Double(measurement.boundingBox.y), maxX: Double(measurement.boundingBox.x + measurement.boundingBox.width),
          maxY: Double(measurement.boundingBox.y + measurement.boundingBox.height)),
        selectedAnchor: measurement.referenceAnchor, confidence: measurement.confidence,
        estimatorRevision: reference.estimatorRevision, source: source,
        frameID: target.frame.id, cameraConfigurationID: target.frame.cameraConfigurationID)
      #expect(anchor.point == measurement.centroid)
    }
  }

  @Test("near duplicate, absent, clipped, gray and unusably dark markers refuse without fallback")
  func adversaries() async throws {
    let optical = try optics()
    let reference = try SampledColorMarkerReference.capture(frame: frame(), point: Point2(x: 31, y: 32),
      opticalConfiguration: optical)
    for target in [try frame(duplicate: true), try frame(visible: false),
      try frame(originX: 0), try frame(gain: 0.05), try frame(gray: true)] {
      #expect(try await detect(reference, in: target, optical: optical).measurement == nil)
    }
    #expect(throws: SampledColorMarkerError.self) {
      try SampledColorMarkerReference.capture(frame: frame(duplicate: true), point: Point2(x: 31, y: 32),
        opticalConfiguration: optical)
    }
    #expect(throws: SampledColorMarkerError.self) {
      try SampledColorMarkerReference.capture(frame: frame(), point: Point2(x: 90, y: 80),
        opticalConfiguration: optical)
    }
  }

  @Test("saved marker requires exact semantic optics on each capture generation; mixed modes fail closed")
  func identityAndMode() async throws {
    let optical = try optics()
    let first = try frame()
    let marker = try SampledColorMarkerReference.capture(frame: first, point: Point2(x: 31, y: 32),
      opticalConfiguration: optical)
    let saved = try JSONDecoder().decode(SampledColorMarkerReference.self, from: JSONEncoder().encode(marker))
    let next = try frame()
    #expect(next.frame.cameraConfigurationID != marker.cameraConfigurationID)
    #expect(try await detect(saved, in: next, optical: optical).measurement != nil)
    #expect(marker.identity == saved.identity)
    #expect(PenCapReferenceBinding(markerReference: saved, frame: next,
      opticalConfiguration: try optics(mirrored: true)) == nil)
    let different = DisplayedFrame(source: .live(CameraDeviceID(rawValue: "wrong-camera")), frame: next.frame)
    #expect(PenCapReferenceBinding(markerReference: saved, frame: different, opticalConfiguration: optical) == nil)
    let missing = try await VisionWorker().inspectPlotterScene(in: next.frame,
      requestedFeatures: [.penCap], markerReference: saved)
    #expect(missing.penCap.measurement == nil)
    let visual = try PenCapVisualReference.capture(frame: first.frame,
      region: PixelRect(x: 24, y: 24, width: 28, height: 28), anchor: Point2(x: 31, y: 32))
    let binding = try #require(PenCapReferenceBinding(markerReference: saved, frame: next, opticalConfiguration: optical))
    let mixed = try await VisionWorker().inspectPlotterScene(in: next.frame, requestedFeatures: [.penCap],
      penCapReference: visual, markerReference: saved, referenceBinding: binding)
    #expect(mixed.penCap.measurement == nil)
  }

  @Test("BGRA padded rows preserve an off-center tap near the lower-right edge and accepted dim samples reacquire exactly")
  func paddedBGRAAndDimAcquisition() async throws {
    let optical = try CameraOpticalConfigurationIdentity(source: source, sensorFormat: "fixture-bgra-padded",
      width: 128, height: 96, pixelFormat: .bgra8, orientation: .up, mirrored: false,
      digitalZoomFactor: 1, lensIdentity: "fixed", focusConfiguration: "fixed",
      mountRevision: mount, reframingRevision: reframing)
    for gain in [0.25, 0.3, 0.5, 1.0] {
      let displayed = try frame(gain: gain, originX: 114, originY: 78, pixelFormat: .bgra8, padding: 12)
      let tap = try Point2<CameraPixelSpace>(x: 117, y: 81)
      let marker = try SampledColorMarkerReference.capture(frame: displayed, point: tap, opticalConfiguration: optical)
      #expect(marker.selectionPoint == tap)
      #expect(marker.acquisitionAnchor != tap)
      #expect(marker.frameSHA256 == displayed.frame.contentSHA256)
      #expect(marker.frameID == displayed.frame.id)
      let binding = try #require(PenCapReferenceBinding(markerReference: marker, frame: displayed,
        opticalConfiguration: optical))
      let detected = try await VisionWorker().inspectPlotterScene(in: displayed.frame,
        requestedFeatures: [.penCap], analysisRegion: PixelRect(x: 110, y: 74, width: 18, height: 22),
        markerReference: marker, referenceBinding: binding)
      #expect(detected.penCap.measurement?.trackingPoint == marker.acquisitionAnchor)
    }
    #expect(throws: SampledColorMarkerError.self) {
      try SampledColorMarkerReference.capture(
        frame: frame(gain: 0.2, originX: 114, originY: 78, pixelFormat: .bgra8, padding: 12),
        point: Point2(x: 117, y: 81), opticalConfiguration: optical)
    }
  }

  @Test("specialized full-domain mask equals scalar policy and rejects pale hue-matched glare")
  func maskPolicyAndGlare() async throws {
    let width = 67, height = 41, rowBytes = 67 * 4 + 12
    var pixels = [UInt8](repeating: 0, count: rowBytes * height)
    for y in 0..<height { for x in 0..<width {
      let i = y * rowBytes + x * 4
      pixels[i] = UInt8((x * 31 + y * 7) % 256)
      pixels[i + 1] = UInt8((x * 17 + y * 19) % 256)
      pixels[i + 2] = UInt8((x * 13 + y * 23) % 256)
    } }
    let frame = try StampedFrame(sequence: 1, captureNanoseconds: 1,
      cameraConfigurationID: CameraConfigurationID(), width: width, height: height,
      rowBytes: rowBytes, pixelFormat: .bgra8, bytes: OwnedFrameBytes(pixels))
    let region = PixelRect(x: 3, y: 2, width: 59, height: 35)
    for color in [PenCapColor(red: 17, green: 91, blue: 73), .green,
      PenCapColor(red: 190, green: 20, blue: 30)] {
      let hsv = VisionWorker.hsv(red: color.red, green: color.green, blue: color.blue)
      let fast = try VisionWorker.markerMask(frame: frame, region: region, color: color)
      for y in 0..<region.height { for x in 0..<region.width {
        let i = (y + region.y) * rowBytes + (x + region.x) * 4
        let scalar = VisionWorker.markerColorSupport(red: pixels[i + 2], green: pixels[i + 1],
          blue: pixels[i], selectedHue: hsv.hueDegrees, minimumSaturation: max(0.25, hsv.saturation * 0.5))
        #expect(fast[y * region.width + x] == Float(scalar))
      } }
    }
    let optical = try optics()
    let initial = try self.frame()
    let marker = try SampledColorMarkerReference.capture(frame: initial, point: Point2(x: 31, y: 32), opticalConfiguration: optical)
    var glareBytes = initial.frame.bytes.withUnsafeBytes { Array($0) }
    for y in 28..<44 { for x in 88..<100 {
      let i = (y * 128 + x) * 4
      glareBytes[i] = 179; glareBytes[i + 1] = 255; glareBytes[i + 2] = 220; glareBytes[i + 3] = 255
    } }
    let glare = DisplayedFrame(source: source, frame: try StampedFrame(sequence: 1, captureNanoseconds: 1,
      cameraConfigurationID: CameraConfigurationID(), width: 128, height: 96, rowBytes: 512,
      pixelFormat: .rgba8, bytes: OwnedFrameBytes(glareBytes)))
    #expect(try await detect(marker, in: glare, optical: optical).measurement?.trackingPoint == marker.acquisitionAnchor)
    #expect(try await detect(marker, in: self.frame(duplicate: true), optical: optical).measurement == nil)
    // A lower-saturation face remains connected to the same saturated marker.
    // Acquisition learns its chroma from that component, not the pale reflection.
    for y in 28..<44 { for x in 28..<34 {
      let i = (y * 128 + x) * 4
      glareBytes[i] = 95; glareBytes[i + 1] = 190; glareBytes[i + 2] = 145
    } }
    let folded = DisplayedFrame(source: source, frame: try StampedFrame(sequence: 1, captureNanoseconds: 1,
      cameraConfigurationID: CameraConfigurationID(), width: 128, height: 96, rowBytes: 512,
      pixelFormat: .rgba8, bytes: OwnedFrameBytes(glareBytes)))
    let fromPaleFace = try SampledColorMarkerReference.capture(frame: folded, point: Point2(x: 30, y: 32),
      opticalConfiguration: optical)
    #expect(fromPaleFace.minimumSaturation > 0.3)
    #expect(fromPaleFace.color != marker.color)
    #expect(try await detect(fromPaleFace, in: folded, optical: optical).measurement?.trackingPoint == marker.acquisitionAnchor)
  }

  private func detect(_ marker: SampledColorMarkerReference, in frame: DisplayedFrame,
    optical: CameraOpticalConfigurationIdentity) async throws -> PenCapDetectionResult {
    let binding = try #require(PenCapReferenceBinding(markerReference: marker, frame: frame,
      opticalConfiguration: optical))
    return try await VisionWorker().inspectPlotterScene(in: frame.frame, requestedFeatures: [.penCap],
      markerReference: marker, referenceBinding: binding).penCap
  }

  private func optics(mirrored: Bool = false) throws -> CameraOpticalConfigurationIdentity {
    try .init(source: source, sensorFormat: "fixture-rgba", width: 128, height: 96,
      pixelFormat: .rgba8, orientation: .up, mirrored: mirrored, digitalZoomFactor: 1,
      lensIdentity: "fixed", focusConfiguration: "fixed", mountRevision: mount, reframingRevision: reframing)
  }

  private func frame(gain: Double = 1, offset: Double = 0, duplicate: Bool = false,
    visible: Bool = true, originX: Int = 28, gray: Bool = false,
    originY: Int = 28, pixelFormat: FramePixelFormat = .rgba8, padding: Int = 0) throws -> DisplayedFrame {
    let width = 128, height = 96
    let rowBytes = width * 4 + padding
    var pixels = [UInt8](repeating: 220, count: rowBytes * height)
    // Blue ink/structure and a tiny green distractor remain outside the marker.
    for y in 60..<80 { for x in 8..<90 {
      let i = y * rowBytes + x * 4
      pixels[i] = pixelFormat == .rgba8 ? 15 : 150
      pixels[i + 1] = 45; pixels[i + 2] = pixelFormat == .rgba8 ? 150 : 15
    } }
    if visible {
      for ox in duplicate ? [originX, 88] : [originX] {
        for y in originY..<(originY + 16) { for x in ox..<(ox + 12) {
          let rgb: [Double] = gray ? [100, 100, 100]
            : pixelFormat == .rgba8 ? [25, 145, 90] : [90, 145, 25]
          let i = y * rowBytes + x * 4
          for c in 0..<3 { pixels[i + c] = UInt8(max(0, min(255, rgb[c] * gain + offset)).rounded()) }
          pixels[i + 3] = 255
        } }
      }
    }
    return DisplayedFrame(source: source, frame: try StampedFrame(sequence: 1, captureNanoseconds: 1,
      cameraConfigurationID: CameraConfigurationID(), width: width, height: height,
      rowBytes: rowBytes, pixelFormat: pixelFormat, bytes: OwnedFrameBytes(pixels)))
  }
}
