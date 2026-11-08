import Foundation
import PlotterModel
import PlotterRuntime
import PortraitArtists
import PortraitCore
@testable import PortraitLibrary
import Testing

@Suite("Curated source photo exchange", .serialized)
struct FlowPhotoCollectionTests {
  @Test("Source-only import retains provenance, preserves originals and is atomic and idempotent")
  func portableImport() async throws {
    let folder = temporary(), root = temporary(), copy = temporary()
    defer { for p in [folder, root, copy] { try? FileManager.default.removeItem(at: p) } }
    let images = [FlowDojoFixture.image(1), FlowDojoFixture.image(2)]
    try writeCollection(folder, images: images)
    let collection = try FlowPhotoCollection.load(directory: folder)
    let store = try await StudioDrawingFixture.store(directory: root, purpose: .validationFixture)
    let original = try await store.addSource(data: images[0], title: "Original name")
    let before = await store.snapshot()
    let result = try await store.importPhotoCollection(collection)
    let after = await store.snapshot()
    #expect(result.count == 2 && after.sources.count == 2 && after.revision == before.revision + 1)
    #expect(after.sources[0] == original && after.selectedSourceID == before.selectedSourceID)
    #expect(after.choices.isEmpty && after.pruneRevisions.isEmpty && after.rounds.isEmpty && after.rankings.isEmpty)
    #expect(after.sources[1].subjectID == nil && after.sources[1].sessionID == "capture:fixture-session")
    let provenance = try #require(after.sources[1].importProvenance)
    #expect(provenance.collectionID == collection.manifest.id)
    #expect(try Data(contentsOf: root.appendingPathComponent("objects/sha256/" + provenance.manifest.sha256)) == collection.manifestData)
    _ = try await store.importPhotoCollection(collection)
    #expect(await store.snapshot() == after)
    try FileManager.default.copyItem(at: root, to: copy)
    let reopened = try await StudioDrawingFixture.store(directory: copy)
    #expect(await reopened.snapshot() == after)
    #expect(try await reopened.sourceData(after.sources[1].id) == images[1])
  }



  @Test("Camera source metadata survives retry and relocation without merging distinct captures")
  func capturedPhotoProvenance() async throws {
    let root = temporary(), copy = temporary()
    defer { for p in [root, copy] { try? FileManager.default.removeItem(at: p) } }
    let store = try await StudioDrawingFixture.store(directory: root, purpose: .validationFixture)
    let data = FlowDojoFixture.image(1), session = UUID()
    let selection = PortraitCaptureSelectionProvenance(capturedFrameCount: 8, evaluatedFrameCount: 6,
      method: .sharpnessAndExposure, selectedSharpness: 0.04, selectedMeanLuminance: 0.5, selectedClippedFraction: 0.01)
    let photo = PortraitPhoto(id: UUID(), data: data, label: "Exact acquisition label",
      capturedAt: Date(timeIntervalSince1970: 123456), frameID: FrameID(), captureNanoseconds: 7654321,
      pose: .front, sourcePixelExtent: try .init(widthPixels: 64, heightPixels: 64),
      captureSessionID: session, selectionProvenance: selection)
    let source = try await store.addCapturedSource(photo: photo, title: "Captured portrait")
    let metadata = try #require(source.captureProvenance)
    #expect(metadata == FlowPortfolioCaptureProvenance(photo: photo))
    #expect(source.subjectID == nil && source.sessionID == "capture:" + session.uuidString)
    try await store.renameSource(sourceID: source.id, title: "User renamed portrait")
    let beforeRetry = await store.snapshot()
    let retry = try await store.addCapturedSource(photo: photo, title: "Captured portrait")
    #expect(retry.id == source.id && retry.title == "User renamed portrait")
    #expect(await store.snapshot() == beforeRetry)
    let collision = PortraitPhoto(id: photo.id, data: FlowDojoFixture.image(2), label: photo.label,
      capturedAt: photo.capturedAt, frameID: photo.frameID, captureNanoseconds: photo.captureNanoseconds,
      pose: photo.pose, sourcePixelExtent: photo.sourcePixelExtent, captureSessionID: session, selectionProvenance: selection)
    await #expect(throws: (any Error).self) { try await store.addCapturedSource(photo: collision, title: "Collision") }
    #expect(await store.snapshot() == beforeRetry)
    let second = PortraitPhoto(id: UUID(), data: data, label: "Later exact capture",
      capturedAt: photo.capturedAt.addingTimeInterval(1), frameID: FrameID(), captureNanoseconds: 7654999,
      pose: .front, sourcePixelExtent: photo.sourcePixelExtent, captureSessionID: session, selectionProvenance: selection)
    let other = try await store.addCapturedSource(photo: second, title: "Second capture")
    #expect(other.id != source.id && other.image.sha256 == source.image.sha256)
    let expected = await store.snapshot()
    #expect(expected.sources.count == 2 && expected.choices.isEmpty && expected.rankings.isEmpty && expected.pruneRevisions.isEmpty)
    try FileManager.default.copyItem(at: root, to: copy)
    let reopened = try await StudioDrawingFixture.store(directory: copy)
    #expect(await reopened.snapshot() == expected)
    #expect(try await reopened.sourceData(source.id) == data)
  }

  @Test("Bad hashes and escaping source paths fail before any portfolio mutation")
  func invalidCollection() async throws {
    let folder = temporary(), root = temporary()
    defer { for p in [folder, root] { try? FileManager.default.removeItem(at: p) } }
    try writeCollection(folder, images: [FlowDojoFixture.image(1)])
    let store = try await StudioDrawingFixture.store(directory: root, purpose: .validationFixture)
    let before = await store.snapshot()
    let manifestURL = folder.appendingPathComponent("photo-collection.json")
    let bytes = try Data(contentsOf: manifestURL)
    let manifest = try JSONDecoder().decode(FlowPhotoCollectionManifest.self, from: bytes)
    try Data("wrong".utf8).write(to: folder.appendingPathComponent(manifest.entries[0].filename))
    #expect(throws: (any Error).self) { try FlowPhotoCollection.load(directory: folder) }
    var json = try #require(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
    var entries = try #require(json["entries"] as? [[String: Any]])
    entries[0]["filename"] = "../outside.png"; json["entries"] = entries
    try JSONSerialization.data(withJSONObject: json).write(to: manifestURL)
    #expect(throws: (any Error).self) { try FlowPhotoCollection.load(directory: folder) }
    #expect(await store.snapshot() == before)
  }

  @Test("Renaming and browsing are durable navigation and supply no preference")
  func namesAndNavigation() async throws {
    let root = temporary(), copy = temporary(); defer { for p in [root, copy] { try? FileManager.default.removeItem(at: p) } }
    let store = try await StudioDrawingFixture.store(directory: root, purpose: .validationFixture)
    let source = try await store.addSource(data: FlowDojoFixture.image(1), title: "Before")
    let round = try await store.beginRound(sourceID: source.id, recipes: [.standard])
    let program = try FlowPortfolioTests.program()
    let candidate = try await store.completeCandidate(roundID: round.id, slot: 0, production: StudioDrawingFixture.production(program: program, raster: FlowPortfolioTests.raster), previewPNG: PortraitDrawingPreview.png(program))
    try await store.finishRound(round.id)
    try await store.renameSource(sourceID: source.id, title: "Window portrait")
    try await store.renameCandidate(candidateID: candidate.id, title: "Angular study")
    try await store.selectCandidate(candidate.id)
    let document = await store.snapshot()
    #expect(document.sources.first?.title == "Window portrait" && document.candidates.first?.title == "Angular study")
    #expect(document.choices.isEmpty && document.currentCandidateID == candidate.id)
    try await store.selectCandidate(candidate.id)
    #expect(await store.snapshot() == document)
    try FileManager.default.copyItem(at: root, to: copy)
    let reopened = try await StudioDrawingFixture.store(directory: copy)
    #expect(await reopened.snapshot() == document)
    try await store.renameCandidate(candidateID: candidate.id, title: " ")
    #expect(await store.snapshot().candidates.first?.title == nil)
  }



  private func temporary() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent("flow-photos-" + UUID().uuidString) }
  private func writeCollection(_ folder: URL, images: [Data]) throws {
    try FileManager.default.createDirectory(at: folder.appendingPathComponent("images"), withIntermediateDirectories: true)
    let entries = try images.enumerated().map { index, data -> FlowPhotoCollectionEntry in
      let hash = DrawingArtifactCoding.sha256(data), filename = "images/" + hash + ".asset"
      try data.write(to: folder.appendingPathComponent(filename))
      return .init(id: hash, title: "Fixture photo \(index)", filename: filename, sha256: hash, byteCount: data.count,
        sessionID: "capture:fixture-session", provenanceJSON: Data("{\"fixture\":true}".utf8))
    }
    let manifest = FlowPhotoCollectionManifest(schemaVersion: 1, id: "test-fixture-collection", title: "Explicit test fixtures", entries: entries)
    try DrawingArtifactCoding.encoder().encode(manifest).write(to: folder.appendingPathComponent("photo-collection.json"))
  }
}
