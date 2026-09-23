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

  @Test("retained raw views preserve the exact clicked anchor and expose unsupported cross-pose appearance",
    .enabled(if: ProcessInfo.processInfo.environment["PLOTTER_CAP_CROSS_POSE_REPLAY_DIRECTORY"] != nil))
  func retainedRawCrossPoseFrames() throws {
    let directory = URL(fileURLWithPath: try #require(ProcessInfo.processInfo.environment["PLOTTER_CAP_CROSS_POSE_REPLAY_DIRECTORY"]))
    let reference = try JSONDecoder().decode(PenCapVisualReference.self,
      from: Data(contentsOf: directory.appendingPathComponent("current-reference.json")))
    #expect(reference.identity == "29815e8ef4f41d9cdaf216cd7104c4d3c9122125b21a9b27f8f2a9eb28b89371")
    let frames = try JSONDecoder().decode([RawReplayFrame].self,
      from: Data(contentsOf: directory.appendingPathComponent("manifest.json")))
    let hashes = [
      "868104d54232a555ed7730a04fd8e4492861efc1f6dfebce643e44efc00d96e9",
      "d5e8afa8bef60a166fde892b0bfce87669f9d57c6f7c04be9a4f050101112b77",
      "9e0202e7e3129f0c5e067dedef65772abaf0bd8c8445d136a99b4a92f3dad0a7",
      "ef87773a35e611e413fd135bc8cebb88f37d47316d988965f98551e663c69144",
      "1b961d097ece2f6c2cb0a472b71063dd754a8ecebea382c97428372a8715d7ec"
    ]
    try #require(frames.count == hashes.count)
    for (index, saved) in frames.enumerated() {
      let raw = try Data(contentsOf: directory.appendingPathComponent(saved.name + ".frame"))
      #expect(RunLedger.sha256Hex(raw) == hashes[index])
      let descriptor = saved.descriptor
      let frame = try StampedFrame(id: FrameID(rawValue: descriptor.frameID), sequence: descriptor.sequence,
        captureNanoseconds: descriptor.captureNanoseconds, cameraConfigurationID: descriptor.stream.configuration,
        width: descriptor.width, height: descriptor.height, rowBytes: descriptor.rowBytes,
        pixelFormat: .bgra8, bytes: OwnedFrameBytes(Array(raw)))
      #expect(frame.cameraConfigurationID == reference.cameraConfigurationID)
      for predicted in [false, true] {
        // Earlier views have no retained operator anchor. This hint is only a
        // visually approximate proposal, never precision ground truth.
        let hint = index < 3 ? try Point2<CameraPixelSpace>(x: 1158, y: 107) : reference.anchor
        let start = ContinuousClock.now
        let result = try PenCapTemplateMatcher.detect(frame: frame, reference: reference,
          region: PixelRect(x: 0, y: 0, width: frame.width, height: frame.height),
          searchCenter: predicted ? hint : nil)
        let diagnostic = try #require(result.diagnostics?.template)
        let best = try #require(diagnostic.candidates.first)
        #expect(diagnostic.acceptanceThreshold == 0.82)
        #expect(diagnostic.requiredMargin == 0.06)
        if index < 3 {
          // The current single appearance is insufficient at the earlier pose;
          // refusing it is preferable to accepting a displaced cap anchor.
          // This is NOT the unavailable old-reference acquisition failure.
          #expect(result.measurement == nil)
          #expect(best.score < diagnostic.acceptanceThreshold)
          #expect(best.score > 0.80)
          #expect(best.score - (try #require(diagnostic.competitorScore)) > diagnostic.requiredMargin)
        } else {
          let cap = try #require(result.measurement)
          #expect(best.score > 0.99)
          if index == 4 {
            #expect(cap.trackingPoint.distance(to: reference.anchor) < 0.1)
            #expect(try PenCapVisualReference.capture(frame: frame, region: reference.region,
              anchor: reference.anchor) == reference)
          }
        }
        print("CAP_CROSS_POSE_REPLAY frame=\(saved.name) rawBGRA_SHA256=\(hashes[index]) referenceIdentity=\(reference.identity) prediction=\(predicted) elapsed=\(start.duration(to: .now)) anchor=\(best.anchor) \(diagnostic.summary)")
      }
    }
  }

  private struct RawReplayFrame: Decodable {
    let name: String
    let descriptor: Descriptor
    struct Descriptor: Decodable {
      let frameID: String
      let sequence: UInt64
      let captureNanoseconds: UInt64
      let width: Int, height: Int, rowBytes: Int
      let stream: Stream
      struct Stream: Decodable { let configuration: CameraConfigurationID }
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
