import Foundation
import PlotterModel
import Testing
@testable import PlotterRuntime
@testable import PlotterApp

@Suite("Bounded tracking acquisition evidence", .serialized)
struct TrackingAcquisitionEvidenceTests {
  @Test("lost tracking retains exact analyzed pixels, immutable reference and numeric candidate diagnostics")
  func exactFailureEvidence() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let frame = try makeFrame()
    let region = PixelRect(x: 4, y: 4, width: 16, height: 16)
    let anchor = try Point2<CameraPixelSpace>(x: 9, y: 11)
    let reference = try PenCapVisualReference.capture(frame: frame.frame, region: region, anchor: anchor)
    let diagnostics = PenCapDiagnostics(inspectedPixelCount: 1024, thresholdPixelCount: 0,
      componentCount: 0, candidates: [], template: PenCapTemplateDiagnostics(
        candidates: [.init(score: 0.816, boundingBox: region, anchor: anchor)],
        acceptanceThreshold: 0.82, requiredMargin: 0.06, competitorScore: 0.636,
        predictionResidualPixels: 2.68, confirmedExampleCount: 1))
    let priors = try PlotterSceneVisionPriors(capSearchRegion: region, penCapReference: reference, searchCenter: anchor)
    let id = UUID()
    let recorder = TrackingAcquisitionEvidenceRecorder(directory: directory)
    let url = try await recorder.write(frame: frame, reference: reference, detection: .notFound(diagnostics),
      searchCenter: anchor, phase: .failure, acquisitionID: id, newerThanNanoseconds: 9,
      ownerEvidence: ["owner": "test-acquisition"], priors: priors)
    let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
    let saved = try decoder.decode(TrackingAcquisitionEvidence.self, from: Data(contentsOf: url))
    #expect(saved.acquisitionID == id && saved.phase == .failure)
    #expect(saved.reference == reference && saved.referenceIdentity == reference.identity)
    #expect(saved.camera.frameID == frame.frame.id && saved.camera.captureNanoseconds == 10)
    #expect(saved.detection?.candidates.first?.score == 0.816)
    #expect(saved.detection?.acceptanceThreshold == 0.82)
    #expect(saved.detection?.trackingPoint == nil)
    #expect(saved.options?.capSearchRegion == region)
    #expect(saved.ownerEvidence["controllerPosition"] == nil)
    let pixels = try Data(contentsOf: url.deletingLastPathComponent().appendingPathComponent(saved.camera.pixelsFile))
    #expect(pixels == frame.frame.bytes.data)
    #expect(RunLedger.sha256Hex(pixels) == saved.camera.contentSHA256)
  }

  @Test("retention evicts only owned acquisition folders and oversized input cannot erase evidence")
  func retentionAndFailure() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let unrelated = directory.appendingPathComponent("operator-notes.txt")
    try Data("keep".utf8).write(to: unrelated)
    let frame = try makeFrame()
    let recorder = TrackingAcquisitionEvidenceRecorder(directory: directory, maximumEntries: 2, maximumBytes: 30_000)
    var urls: [URL] = []
    for _ in 0..<3 {
      urls.append(try await recorder.write(frame: frame, reference: nil, detection: .failed("fixture"),
        searchCenter: nil, phase: .failure, acquisitionID: UUID(), newerThanNanoseconds: 0))
    }
    #expect(!FileManager.default.fileExists(atPath: urls[0].path))
    #expect(FileManager.default.fileExists(atPath: urls[1].path))
    #expect(FileManager.default.fileExists(atPath: urls[2].path))
    #expect(try String(contentsOf: unrelated, encoding: .utf8) == "keep")
    let refusing = TrackingAcquisitionEvidenceRecorder(directory: directory, maximumEntries: 2, maximumBytes: 1)
    let failure = await refusing.record(frame: frame, reference: nil, detection: .failed("original failure"),
      searchCenter: nil, phase: .failure, acquisitionID: UUID(), newerThanNanoseconds: 0)
    #expect(failure?.contains("could not be saved") == true)
    #expect(FileManager.default.fileExists(atPath: urls[2].path))
  }

  private func makeFrame() throws -> DisplayedFrame {
    var bytes = [UInt8](repeating: 255, count: 32 * 32 * 4)
    for y in 0..<32 { for x in 0..<32 { for c in 0..<3 {
      bytes[(y * 32 + x) * 4 + c] = ((x / 2 + y / 2) % 2 == 0) ? 20 : 230
    } } }
    return DisplayedFrame(source: .simulated, frame: try StampedFrame(sequence: 1,
      captureNanoseconds: 10, cameraConfigurationID: CameraConfigurationID(),
      width: 32, height: 32, rowBytes: 128, pixelFormat: .rgba8, bytes: OwnedFrameBytes(bytes)))
  }
}
