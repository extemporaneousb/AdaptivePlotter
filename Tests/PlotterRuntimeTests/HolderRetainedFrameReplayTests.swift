import Foundation
import PlotterModel
import Testing
@testable import PlotterRuntime

@Suite("Retained holder-frame replay")
struct HolderRetainedFrameReplayTests {
  @Test("analyst-selected compact holder reference retains global gates across the raw eight-frame corpus",
    .enabled(if: ProcessInfo.processInfo.environment["HOLDER_REFERENCE_REPLAY_DIRECTORY"] != nil))
  func retainedCorpus() throws {
    let path = try #require(ProcessInfo.processInfo.environment["HOLDER_REFERENCE_REPLAY_DIRECTORY"])
    let directory = URL(fileURLWithPath: path)
    let manifest = try #require(JSONSerialization.jsonObject(with:
      Data(contentsOf: directory.appendingPathComponent("manifest.json"))) as? [String: Any])
    let records = try #require(manifest["frames"] as? [[String: Any]])
    #expect(records.count == 8)
    var frames: [DisplayedFrame] = []
    for record in records {
      let name = try #require(record["name"] as? String)
      let artifact = try #require(record["artifact"] as? [String: Any])
      let expectedHash = try #require(artifact["contentSHA256"] as? String)
      let descriptor = try #require(record["descriptor"] as? [String: Any])
      let stream = try #require(descriptor["stream"] as? [String: Any])
      let configuration = try #require(stream["configuration"] as? [String: Any])
      let configurationString = try #require(configuration["rawValue"] as? String)
      let configurationID = try #require(UUID(uuidString: configurationString))
      let sourceText = try #require(stream["source"] as? String)
      #expect(sourceText.hasPrefix("live:"))
      let source = FrameSourceIdentity.live(CameraDeviceID(rawValue: String(sourceText.dropFirst(5))))
      let bytes = try Data(contentsOf: directory.appendingPathComponent(name))
      #expect(RunLedger.sha256Hex(bytes) == expectedHash)
      let frame = try StampedFrame(sequence: UInt64(try #require(descriptor["sequence"] as? Int)),
        captureNanoseconds: UInt64(try #require(descriptor["captureNanoseconds"] as? Int)),
        cameraConfigurationID: CameraConfigurationID(configurationID), width: 1920, height: 1080,
        rowBytes: 7680, pixelFormat: .bgra8, bytes: OwnedFrameBytes(copying: bytes))
      frames.append(DisplayedFrame(source: source, frame: frame))
    }
    let first = try #require(frames.first)
    // Replay-only semantic context: the corpus does not contain observed mount,
    // focus, pen state or controller-pose labels. This supplies no live authority.
    let optical = try CameraOpticalConfigurationIdentity(source: first.source,
      sensorFormat: "retained-1920x1080-BGRA", width: 1920, height: 1080, pixelFormat: .bgra8,
      orientation: .up, mirrored: false, digitalZoomFactor: 1,
      lensIdentity: "replay-only-unobserved", focusConfiguration: "replay-only-unobserved",
      mountRevision: UUID(), reframingRevision: UUID())
    let captured = try PenCapVisualReference.capture(frame: first.frame,
      region: PixelRect(x: 1327, y: 357, width: 45, height: 38), anchor: Point2(x: 1347, y: 372),
      purpose: .rigidHolder, opticalConfiguration: optical)
    let reference = try JSONDecoder().decode(PenCapVisualReference.self, from: JSONEncoder().encode(captured))
    for (index, frame) in frames.enumerated() {
      let binding = try #require(PenCapReferenceBinding(reference: reference,
        frame: frame, opticalConfiguration: optical))
      let start = ContinuousClock.now
      let result = try PenCapTemplateMatcher.detect(frame: frame.frame, reference: reference,
        region: PixelRect(x: 0, y: 0, width: 1920, height: 1080), binding: binding)
      let elapsed = start.duration(to: .now)
      let measurement = try #require(result.measurement)
      let diagnostics = try #require(result.diagnostics?.template)
      #expect(diagnostics.acceptanceThreshold == 0.82)
      #expect(diagnostics.requiredMargin == 0.06)
      print("HOLDER_REPLAY frame=\(index + 1) score=\(measurement.confidence) anchor=\(measurement.trackingPoint) elapsed=\(elapsed)")
    }
    #expect(reference.identity == captured.identity)
  }
}
