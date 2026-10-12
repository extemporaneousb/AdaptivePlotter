import Foundation
import PortraitCore
import PortraitLibrary
import Testing
@testable import PortraitStudio

@Suite("Opt-in retained worker failure data chain", .serialized)
struct PortraitStudioFailureEvidenceTests {
  @Test("Actual post-input fault-injection receipt survives journal and dataset with no drawing",
    .enabled(if: ProcessInfo.processInfo.environment["PORTRAIT_REAL_PILOT_ROOT"] != nil))
  func ingestRetainedFailure() async throws {
    let root = URL(fileURLWithPath: try #require(ProcessInfo.processInfo.environment["PORTRAIT_REAL_PILOT_ROOT"]),
      isDirectory: true)
    let fixture = root.appendingPathComponent("repair-verification/post-input-runtime-version-fixture", isDirectory: true)
    func read(_ name: String) throws -> Data {
      try PortraitStudioFiles.read(fixture.appendingPathComponent(name), maximumBytes: 1024 * 1024)
    }
    let originalRequest = try read("request.json")
    let originalManifest = try read("fixture-manifest.json")
    let kind = try read("test-kind.json")
    let input = try PortraitStudioArtistInput.imageAsset(read("fixture-input.png"))
    let artistInput = try PortraitStudioArtistInput.imageAsset(read("attempt/artist-input.png"))
    let responseBytes = try read("attempt/response.json")
    let provenance = try read("attempt/provenance.json")
    let externalRequest = try #require(try JSONSerialization.jsonObject(with: originalRequest) as? [String: Any])
    let response = try #require(try JSONSerialization.jsonObject(with: responseBytes) as? [String: Any])
    let id = try #require((externalRequest["request_id"] as? String).flatMap(UUID.init(uuidString:)))
    #expect(response["request_id"] as? String == id.uuidString.lowercased())
    #expect(response["status"] as? String == "failed")
    #expect(externalRequest["input_sha256"] as? String == input.sha256)
    #expect((response["files"] as? [String: String])?["artist-input.png"] == artistInput.sha256)
    #expect((response["files"] as? [String: String])?["provenance.json"] == DrawingPackageCodec.sha256(provenance))
    let settings = try JSONSerialization.data(withJSONObject: [
      "evidence_kind": "fault-injection-contract-fixture", "inference": "mocked; not pretrained inference",
      "fixture_capture_identity": "local synthetic PNG occurrence, no human photographic session",
      "original_absolute_request_clock": "unknown", "preprocessing": "unchanged", "seed": 42,
      "input_policy": "retained exact fixture PNG; no new model or preparation work during ingestion"
    ], options: [.sortedKeys])
    let request = try PortraitReviewGenerationRequest(id: id, captureID: UUID(), acquisitionID: nil,
      source: input, inputs: [
        .init(role: "external-frozen-request", asset: .init(mediaType: "application/json", bytes: originalRequest)),
        .init(role: "external-frozen-manifest", asset: .init(mediaType: "application/json", bytes: originalManifest)),
        .init(role: "fault-injection-kind", asset: .init(mediaType: "application/json", bytes: kind))
      ], artist: .init(identifier: "swiftsketch.cpu.contract-fixture", revision: "mock-runtime-import-failure-v2",
        settingsJSON: settings), environmentJSON: kind,
      conversionJSON: Data("{\"conversion\":\"not attempted: worker failed before inference\"}".utf8), seed: 42,
      material: .init(widthMM: 100, heightMM: 100, nominalLineWidthMM: 0.4,
        provenance: "unused nominal test declaration; no drawing or physical pen claim"),
      recordingMode: .retrospectiveExternalImport)
    let store = PortraitCandidateStore(directoryURL: root.appendingPathComponent("FailureLibrary", isDirectory: true))
    try await store.beginReviewGeneration(request)
    let outcome = try await store.finishReviewGeneration(id: id, status: .failed,
      reason: try #require(response["reason"] as? String), outputs: [
        .init(role: "artist-input", asset: artistInput),
        .init(role: "worker-provenance", asset: .init(mediaType: "application/json", bytes: provenance)),
        .init(role: "worker-response", asset: .init(mediaType: "application/json", bytes: responseBytes))
      ], runtimeEnvironmentJSON: provenance, runtimeMetricsJSON: responseBytes)
    #expect(outcome.status == .failed && outcome.origin == nil && outcome.packageSHA256 == nil)
    #expect(outcome.runtimeEnvironmentJSON == provenance && outcome.runtimeMetricsJSON == responseBytes)
    let destination = root.appendingPathComponent("FailureDataset", isDirectory: true)
    let manifest = try await store.exportReviewDataset(to: destination)
    #expect(manifest.counts.requests == 1 && manifest.counts.failed == 1 && manifest.counts.drawingResults == 0)
    #expect(manifest.counts.labelRevisions == 0 && manifest.counts.comparisons == 0)
    for bytes in [input.bytes, artistInput.bytes, originalRequest, originalManifest, kind, provenance, responseBytes] {
      let sha = DrawingPackageCodec.sha256(bytes)
      let file = try #require(manifest.files.first(where: { $0.sha256 == sha }))
      let retained = try PortraitStudioFiles.read(destination.appendingPathComponent(file.path), maximumBytes: 1024 * 1024)
      #expect(retained == bytes && DrawingPackageCodec.sha256(retained) == sha)
    }
    let record = try #require(manifest.records.first(where: { $0.kind == "outcome" && $0.id == id }))
    let retained = try PortraitStudioFiles.read(destination.appendingPathComponent("assets/" + record.fileSHA256),
      maximumBytes: 1024 * 1024)
    #expect(try JSONDecoder().decode(PortraitReviewGenerationOutcome.self, from: retained) == outcome)
  }
}
