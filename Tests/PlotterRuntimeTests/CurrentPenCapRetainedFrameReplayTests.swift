import Foundation
import PlotterModel
import Testing
@testable import PlotterRuntime

@Suite("Current pen-cap retained-frame replay")
struct CurrentPenCapRetainedFrameReplayTests {
  @Test("retained observations preserve measured centroids and refuse the hand-occluded cap",
    .enabled(if: ProcessInfo.processInfo.environment["PEN_CAP_REPLAY_DIRECTORY"] != nil))
  func retainedAcquisitions() async throws {
    let directory = URL(fileURLWithPath: try #require(ProcessInfo.processInfo.environment["PEN_CAP_REPLAY_DIRECTORY"]))
    let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
      .filter { $0.lastPathComponent.hasPrefix("acquisition-") }
      .map { $0.appendingPathComponent("manifest.json") }
    let records = try files.map { url in
      (url, try JSONDecoder().decode(Record.self, from: Data(contentsOf: url)))
    }.sorted { $0.1.camera.captureNanoseconds < $1.1.camera.captureNanoseconds }
    #expect(!records.isEmpty)
    let worker = VisionWorker()
    var seen = 0, unavailable = 0
    for (manifest, record) in records {
      #expect(record.markerReference.identity == record.referenceIdentity)
      let camera = record.camera
      let pixels = try Data(contentsOf: manifest.deletingLastPathComponent().appendingPathComponent(camera.pixelsFile))
      #expect(RunLedger.sha256Hex(pixels) == camera.contentSHA256)
      let frame = DisplayedFrame(source: camera.source, frame: try StampedFrame(id: camera.frameID,
        sequence: camera.sequence, captureNanoseconds: camera.captureNanoseconds,
        cameraConfigurationID: camera.cameraConfigurationID, width: camera.width, height: camera.height,
        rowBytes: camera.rowBytes, pixelFormat: camera.pixelFormat, bytes: OwnedFrameBytes(copying: pixels)))
      let binding = try #require(PenCapReferenceBinding(markerReference: record.markerReference,
        frame: frame, opticalConfiguration: record.options.boundOpticalConfiguration))
      let start = ContinuousClock.now
      let result = try await worker.inspectPlotterScene(in: frame.frame, requestedFeatures: [.penCap],
        markerReference: record.markerReference, referenceBinding: binding, searchCenter: record.searchCenter)
      if let centroid = record.detection.centroid {
        let cap = try #require(result.penCap.measurement)
        #expect(cap.trackingPoint.distance(to: centroid) < 0.001)
        seen += 1
      } else {
        #expect(result.penCap.measurement == nil)
        unavailable += 1
      }
      print("PEN_CAP_REPLAY frame=\(camera.contentSHA256) expected=\(record.detection.disposition) actual=\(result.penCap.diagnosticReason) elapsed=\(start.duration(to: .now))")
    }
    #expect(seen > 0)
    #expect(unavailable > 0)
  }

  private struct Record: Decodable {
    let camera: Camera
    let markerReference: SampledColorMarkerReference
    let referenceIdentity: String
    let options: Options
    let detection: Detection
    let searchCenter: Point2<CameraPixelSpace>?
  }
  private struct Options: Decodable { let boundOpticalConfiguration: CameraOpticalConfigurationIdentity }
  private struct Detection: Decodable {
    let disposition: String
    let centroid: Point2<CameraPixelSpace>?
  }
  private struct Camera: Decodable {
    let source: FrameSourceIdentity
    let frameID: FrameID
    let sequence: UInt64
    let captureNanoseconds: UInt64
    let cameraConfigurationID: CameraConfigurationID
    let width, height, rowBytes: Int
    let pixelFormat: FramePixelFormat
    let contentSHA256: String
    let pixelsFile: String
  }
}
