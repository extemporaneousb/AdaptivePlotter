import Foundation
import PlotterModel
import PlotterRuntime
import Testing

@testable import PlotterApp

@Test("Startup recorder writes spaced canonical PNG samples and a non-calibration manifest")
func startupFrameRecorderWritesPNGSet() async throws {
  let root = FileManager.default.temporaryDirectory
    .appendingPathComponent("AdaptivePlotter-startup-frame-test-\(UUID())", isDirectory: true)
  defer { try? FileManager.default.removeItem(at: root) }
  let device = CameraDevice(id: CameraDeviceID(rawValue: "c920"), name: "HD Pro Webcam C920")
  let configurationID = CameraConfigurationID()
  let frames = AsyncStream<DisplayedFrame> { continuation in
    for (sequence, timestamp) in [(1, 100), (2, 250), (3, 700)] as [(UInt64, UInt64)] {
      continuation.yield(
        DisplayedFrame(
          source: .live(device.id),
          frame: try! StampedFrame(
            sequence: sequence,
            captureNanoseconds: timestamp,
            cameraConfigurationID: configurationID,
            width: 2,
            height: 2,
            rowBytes: 8,
            pixelFormat: .bgra8,
            bytes: OwnedFrameBytes([
              0, 255, 0, 255, 0, 255, 0, 255,
              0, 255, 0, 255, 0, 255, 0, 255,
            ])
          )
        ))
    }
    continuation.finish()
  }
  let recorder = StartupFrameRecorder(
    rootDirectory: root,
    sampleCount: 2,
    minimumIntervalNanoseconds: 500
  )

  let directory = try await recorder.record(frames: frames, device: device)
  let manifestData = try Data(
    contentsOf: directory.appendingPathComponent("manifest.json"))
  let manifest = try JSONDecoder().decode(StartupFrameRecorder.Manifest.self, from: manifestData)

  #expect(manifest.purpose.contains("not calibration evidence"))
  #expect(manifest.cameraDeviceID == "c920")
  #expect(manifest.samples.map(\.sequence) == [1, 3])
  for sample in manifest.samples {
    let png = try Data(contentsOf: directory.appendingPathComponent(sample.filename))
    #expect(png.starts(with: [0x89, 0x50, 0x4E, 0x47]))
  }
}

@Test("Manual camera snapshot preserves the exact frame in PNG and manifest")
func manualCameraSnapshotPreservesExactFrame() throws {
  let root = FileManager.default.temporaryDirectory
    .appendingPathComponent("AdaptivePlotter-manual-frame-test-\(UUID())", isDirectory: true)
  defer { try? FileManager.default.removeItem(at: root) }
  let device = CameraDevice(id: CameraDeviceID(rawValue: "c920"), name: "HD Pro Webcam C920")
  let configurationID = CameraConfigurationID()
  let frame = try StampedFrame(
    sequence: 42,
    captureNanoseconds: 12_345,
    cameraConfigurationID: configurationID,
    width: 2,
    height: 2,
    rowBytes: 8,
    pixelFormat: .bgra8,
    bytes: OwnedFrameBytes([
      0, 255, 0, 255, 0, 255, 0, 255,
      0, 255, 0, 255, 0, 255, 0, 255,
    ])
  )
  let displayedFrame = DisplayedFrame(source: .live(device.id), frame: frame)
  let recorder = StartupFrameRecorder(rootDirectory: root)

  let directory = try recorder.recordSnapshot(displayedFrame, device: device)
  let manifest = try JSONDecoder().decode(
    StartupFrameRecorder.Manifest.self,
    from: Data(contentsOf: directory.appendingPathComponent("manifest.json"))
  )
  let sample = try #require(manifest.samples.only)

  #expect(manifest.purpose.contains("operator-requested"))
  #expect(manifest.purpose.contains("not calibration evidence"))
  #expect(manifest.cameraConfigurationID == configurationID.rawValue.uuidString.lowercased())
  #expect(sample.sequence == 42)
  #expect(sample.captureNanoseconds == 12_345)
  #expect(sample.frameID == frame.id.rawValue)
  #expect(sample.contentSHA256 == frame.contentSHA256)
  let png = try Data(contentsOf: directory.appendingPathComponent(sample.filename))
  #expect(png.starts(with: [0x89, 0x50, 0x4E, 0x47]))
}

private extension Array {
  var only: Element? { count == 1 ? self[0] : nil }
}
