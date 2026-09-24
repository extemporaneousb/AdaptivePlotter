import Foundation
import PlotterModel
import Testing
@testable import PlotterRuntime

@Suite("Recorded green marker replay")
struct MarkerRetainedFrameReplayTests {
  @Test("actual retained raw frames report DEBUG marker timing and preserve centroid under usable exposure changes",
    .enabled(if: ProcessInfo.processInfo.environment["MARKER_REFERENCE_REPLAY_DIRECTORY"] != nil))
  func rawGreenCorpus() async throws {
    let directory = URL(fileURLWithPath: try #require(ProcessInfo.processInfo.environment["MARKER_REFERENCE_REPLAY_DIRECTORY"]))
    let folders = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
      .filter { $0.lastPathComponent.hasPrefix("acquisition-") }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    let referenceFolder = try #require(folders.first {
      $0.lastPathComponent == "acquisition-BB9BF96B-706E-4136-8453-A2CEDCFA71AC"
    })
    let (original, referenceRecord) = try load(referenceFolder)
    let optical = referenceRecord.options.boundOpticalConfiguration
    // Analyst-selected interior seed in this exact raw image, not operator
    // confirmation or physical ground truth. The reference output is centroid.
    let reference = try SampledColorMarkerReference.capture(frame: original,
      point: Point2(x: 1495, y: 430), opticalConfiguration: optical)
    #expect(reference.componentPixelCount >= 9)
    var found = 0
    for folder in folders {
      let (frame, record) = try load(folder)
      guard record.options.boundOpticalConfiguration == optical else { continue }
      let binding = try #require(PenCapReferenceBinding(markerReference: reference,
        frame: frame, opticalConfiguration: optical))
      let started = ContinuousClock.now
      let measurement = try await VisionWorker().inspectPlotterScene(in: frame.frame,
        requestedFeatures: [.penCap], markerReference: reference, referenceBinding: binding)
      let duration = started.duration(to: .now)
      if let cap = measurement.penCap.measurement {
        found += 1
        #expect(cap.referenceAnchor == cap.centroid)
        print("MARKER_REPLAY raw=\(frame.frame.contentSHA256) pixels=\(cap.pixelCount) centroid=\(cap.trackingPoint) analysis=\(duration)")
      } else {
        print("MARKER_REPLAY raw=\(frame.frame.contentSHA256) refused=\(measurement.penCap) analysis=\(duration)")
      }
      if ProcessInfo.processInfo.environment["MARKER_COMPARE_TEMPLATE"] == "1", let visual = record.reference {
        let templateBinding = try #require(PenCapReferenceBinding(reference: visual, frame: frame,
          opticalConfiguration: optical))
        let templateStarted = ContinuousClock.now
        let result = try PenCapTemplateMatcher.detect(frame: frame.frame, reference: visual,
          region: PixelRect(x: 0, y: 0, width: frame.frame.width, height: frame.frame.height), binding: templateBinding)
        print("MARKER_TEMPLATE_BASELINE raw=\(frame.frame.contentSHA256) found=\(result.measurement != nil) analysis=\(templateStarted.duration(to: .now))")
      }
    }
    #expect(found > 0)
    for seed in [try Point2<CameraPixelSpace>(x: 1495, y: 430),
      try Point2(x: 1499, y: 417), try Point2(x: 1470, y: 427)] {
      let selected = try SampledColorMarkerReference.capture(frame: original, point: seed,
        opticalConfiguration: optical)
      var accepted = 0
      for folder in folders {
        let (frame, record) = try load(folder)
        guard record.options.boundOpticalConfiguration == optical else { continue }
        let binding = try #require(PenCapReferenceBinding(markerReference: selected,
          frame: frame, opticalConfiguration: optical))
        let result = try await VisionWorker().inspectPlotterScene(in: frame.frame,
          requestedFeatures: [.penCap], markerReference: selected, referenceBinding: binding)
        if result.penCap.measurement != nil { accepted += 1 }
        else { Issue.record("Seed \(seed) refused \(folder.lastPathComponent): \(result.penCap.diagnosticReason)") }
      }
      print("MARKER_SEED seed=\(seed) minimum_saturation=\(selected.minimumSaturation) accepted=\(accepted)/\(folders.count)")
    }
    for gain in [0.7, 1.3] {
      var bytes = original.frame.bytes.withUnsafeBytes { Array($0) }
      for row in 0..<original.frame.height { for column in 0..<original.frame.width {
        let index = row * original.frame.rowBytes + column * 4
        for channel in 0..<3 { bytes[index + channel] = UInt8(min(255, Double(bytes[index + channel]) * gain).rounded()) }
      } }
      let adjusted = DisplayedFrame(source: original.source, frame: try StampedFrame(sequence: 1,
        captureNanoseconds: 1, cameraConfigurationID: CameraConfigurationID(),
        width: original.frame.width, height: original.frame.height, rowBytes: original.frame.rowBytes,
        pixelFormat: original.frame.pixelFormat, bytes: OwnedFrameBytes(bytes)))
      let binding = try #require(PenCapReferenceBinding(markerReference: reference, frame: adjusted,
        opticalConfiguration: optical))
      let result = try await VisionWorker().inspectPlotterScene(in: adjusted.frame,
        requestedFeatures: [.penCap], markerReference: reference, referenceBinding: binding)
      let cap = try #require(result.penCap.measurement)
      let error = cap.trackingPoint.distance(to: reference.acquisitionAnchor)
      print("MARKER_EXPOSURE gain=\(gain) centroid_delta_pixels=\(error)")
      #expect(error < 1.5)
    }
  }

  private func load(_ folder: URL) throws -> (DisplayedFrame, Record) {
    let record = try JSONDecoder().decode(Record.self,
      from: Data(contentsOf: folder.appendingPathComponent("manifest.json")))
    let camera = record.camera
    let bytes = try Data(contentsOf: folder.appendingPathComponent(camera.pixelsFile))
    #expect(RunLedger.sha256Hex(bytes) == camera.contentSHA256)
    return (DisplayedFrame(source: camera.source, frame: try StampedFrame(id: camera.frameID,
      sequence: camera.sequence, captureNanoseconds: camera.captureNanoseconds,
      cameraConfigurationID: camera.cameraConfigurationID, width: camera.width,
      height: camera.height, rowBytes: camera.rowBytes, pixelFormat: camera.pixelFormat,
      bytes: OwnedFrameBytes(copying: bytes))), record)
  }
  private struct Record: Decodable {
    let camera: Camera
    let options: Options
    let reference: PenCapVisualReference?
  }
  private struct Options: Decodable { let boundOpticalConfiguration: CameraOpticalConfigurationIdentity }
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
