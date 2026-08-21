import Foundation
import PlotterModel
import PlotterRuntime
import Testing

@testable import PlotterApp

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
  #expect(manifest.purpose.contains("not motion or drawing evidence"))
  #expect(manifest.cameraConfigurationID == configurationID.rawValue.uuidString.lowercased())
  #expect(sample.sequence == 42)
  #expect(sample.captureNanoseconds == 12_345)
  #expect(sample.frameID == frame.id.rawValue)
  #expect(sample.contentSHA256 == frame.contentSHA256)
  let png = try Data(contentsOf: directory.appendingPathComponent(sample.filename))
  #expect(png.starts(with: [0x89, 0x50, 0x4E, 0x47]))
}

extension Array {
  fileprivate var only: Element? { count == 1 ? self[0] : nil }
}
