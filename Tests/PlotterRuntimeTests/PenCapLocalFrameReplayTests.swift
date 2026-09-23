import Foundation
import CoreGraphics
import ImageIO
import PlotterModel
import Testing
@testable import PlotterRuntime

/// Opt-in offline replay. Set PLOTTER_CAP_REPLAY_DIRECTORY to a directory with
/// reference.json and the two named retained camera PNGs. No camera/app access.
/// Derived occlusion/duplicate/shadow inputs are controlled perturbations, not
/// additional physical captures or a reconstruction of the unavailable failure.
@Suite("Cap local frame replay", .serialized)
struct PenCapLocalFrameReplayTests {
  @Test(.enabled(if: ProcessInfo.processInfo.environment["PLOTTER_CAP_REPLAY_DIRECTORY"] != nil))
  func retainedFrames() throws {
    let directory = URL(fileURLWithPath: try #require(ProcessInfo.processInfo.environment["PLOTTER_CAP_REPLAY_DIRECTORY"]))
    let referenceBytes = try Data(contentsOf: directory.appendingPathComponent("reference.json"))
    let reference = try JSONDecoder().decode(PenCapVisualReference.self, from: referenceBytes)
    let cases = [
      ("selected-reference-frame.png", "c487ba470cfe3c3b00016957a495934d058749de15d5613fc58d9f5598da6ee0", reference.anchor),
      // Fifth saved calibration observation; the PNG is the retained final fit frame.
      ("calibration-reference-frame.png", "10aa58283acb19cac15699daca8e80d5daf54b42885c2c63c2a4c3358b198b52",
        try Point2<CameraPixelSpace>(x: 1331.0161, y: 349.0904))
    ]
    for (name, expectedHash, expectedAnchor) in cases {
      let data = try Data(contentsOf: directory.appendingPathComponent(name))
      #expect(RunLedger.sha256Hex(data) == expectedHash)
      let pixels = try decode(data)
      let frame = try makeFrame(pixels, reference: reference)
      for predicted in [false, true] {
        for iteration in 1...3 {
          let start = ContinuousClock.now
          let result = try PenCapTemplateMatcher.detect(frame: frame, reference: reference,
            region: PixelRect(x: 0, y: 0, width: frame.width, height: frame.height),
            searchCenter: predicted ? expectedAnchor : nil)
          let elapsed = start.duration(to: .now)
          let cap = try #require(result.measurement)
          #expect(cap.trackingPoint.distance(to: expectedAnchor) < 0.75)
          print("CAP_REPLAY frame=\(name) prediction=\(predicted) iteration=\(iteration) pngSHA256=\(expectedHash) normalizedRGBA_SHA256=\(RunLedger.sha256Hex(Data(pixels))) referenceSHA256=\(RunLedger.sha256Hex(referenceBytes)) elapsed=\(elapsed) anchor=\(cap.trackingPoint) \(result.diagnostics?.template?.summary ?? result.diagnosticReason)")
        }
      }
    }
  }

  @Test(.enabled(if: ProcessInfo.processInfo.environment["PLOTTER_CAP_REPLAY_DIRECTORY"] != nil))
  func controlledRealAppearancePerturbations() throws {
    let directory = URL(fileURLWithPath: try #require(ProcessInfo.processInfo.environment["PLOTTER_CAP_REPLAY_DIRECTORY"]))
    let reference = try JSONDecoder().decode(PenCapVisualReference.self,
      from: Data(contentsOf: directory.appendingPathComponent("reference.json")))
    let original = try decode(Data(contentsOf: directory.appendingPathComponent("selected-reference-frame.png")))
    let box = reference.region
    let wrongHint = try Point2<CameraPixelSpace>(x: 100, y: 500)
    var shaded = original, missing = original, duplicate = original
    for y in 0..<box.height {
      for x in 0..<box.width {
        let source = ((box.y + y) * reference.frameWidth + box.x + x) * 4
        let target = ((500 + y) * reference.frameWidth + 100 + x) * 4
        for c in 0..<3 {
          shaded[source + c] = UInt8((Double(original[source + c]) * 0.65).rounded())
          missing[source + c] = 220
          duplicate[target + c] = original[source + c]
        }
      }
    }
    for (name, pixels, shouldFind) in [("wrong-prediction", original, true),
      ("uniform-shadow", shaded, true), ("cap-occluded", missing, false),
      ("duplicate-cap", duplicate, false)] {
      let result = try PenCapTemplateMatcher.detect(frame: makeFrame(pixels, reference: reference),
        reference: reference, region: PixelRect(x: 0, y: 0, width: reference.frameWidth,
          height: reference.frameHeight), searchCenter: wrongHint)
      print("CAP_PERTURBATION case=\(name) normalizedRGBA_SHA256=\(RunLedger.sha256Hex(Data(pixels))) \(result.diagnostics?.template?.summary ?? result.diagnosticReason)")
      if shouldFind {
        let cap = try #require(result.measurement)
        #expect(cap.trackingPoint.distance(to: reference.anchor) < 0.75)
      } else {
        #expect(result.measurement == nil)
        #expect(result.diagnostics?.template != nil)
      }
      if name == "duplicate-cap" { #expect(result.diagnosticReason.contains("ambiguous")) }
    }
  }

  private func makeFrame(_ pixels: [UInt8], reference: PenCapVisualReference) throws -> StampedFrame {
    try StampedFrame(sequence: 1, captureNanoseconds: 1,
      cameraConfigurationID: reference.cameraConfigurationID, width: reference.frameWidth,
      height: reference.frameHeight, rowBytes: reference.frameWidth * 4,
      pixelFormat: .rgba8, bytes: OwnedFrameBytes(pixels))
  }

  private func decode(_ data: Data) throws -> [UInt8] {
    let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
    let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
    var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
    let success = pixels.withUnsafeMutableBytes { bytes in
      guard let context = CGContext(data: bytes.baseAddress, width: image.width, height: image.height,
        bitsPerComponent: 8, bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
      context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
      return true
    }
    #expect(success)
    return pixels
  }
}
