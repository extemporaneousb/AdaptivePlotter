import Foundation
import DrawingLibrary
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
    #expect(result.count == 2 && after.sources.count == 3 && after.revision == before.revision + 1)
    #expect(after.sources[0] == original && after.selectedSourceID == before.selectedSourceID)
    #expect(result[0].id != original.id && result[0].photo != original.photo)
    #expect(result[0].image.sha256 == original.image.sha256)
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
    #expect(try await reopened.sourceData(after.sources[2].id) == images[1])
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

  @Test("Collection occurrence identity preserves equal pixels, retries live metadata and rejects changed entry facts")
  func occurrenceIdentity() async throws {
    let folder = temporary(), root = temporary()
    defer { for p in [folder, root] { try? FileManager.default.removeItem(at: p) } }
    let pixels = FlowDojoFixture.image(1)
    try writeCollection(folder, images: [pixels, pixels])
    let firstCollection = try FlowPhotoCollection.load(directory: folder)
    let store = try await StudioDrawingFixture.store(directory: root, purpose: .validationFixture)
    let imported = try await store.importPhotoCollection(firstCollection)
    #expect(imported.count == 2 && Set(imported.map(\.id)).count == 2)
    #expect(Set(imported.compactMap(\.photo)).count == 2)
    #expect(Set(imported.map { $0.image.sha256 }).count == 1)
    #expect(Set(imported.map { $0.groupKeys.first }).count == 1)
    try await store.renameSource(sourceID: imported[0].id, title: "Live title")
    try await store.setSourceGroups(sourceID: imported[0].id, subjectID: "operator-group", sessionID: nil, excluded: true)
    let beforeRetry = await store.snapshot()
    let retried = try await store.importPhotoCollection(firstCollection)
    #expect(retried.map(\.id) == imported.map(\.id))
    #expect(await store.snapshot() == beforeRetry)
    // Equal bytes and an equal entry ID in another declared collection remain a
    // new occurrence; the canonical pixel object can still be shared.
    let manifestURL = folder.appendingPathComponent("photo-collection.json")
    var wire = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: manifestURL)) as? [String: Any])
    wire["id"] = "another-collection"
    try JSONSerialization.data(withJSONObject: wire).write(to: manifestURL)
    let second = try await store.importPhotoCollection(FlowPhotoCollection.load(directory: folder))
    #expect(Set(second.map(\.id)).isDisjoint(with: Set(imported.map(\.id))))
    #expect(Set(second.compactMap(\.photo)).isDisjoint(with: Set(imported.compactMap(\.photo))))
    let beforeConflict = await store.snapshot()
    // Reusing the first collection+entry identity for different image bytes is
    // a conflict, never another acquisition or a content-hash based replacement.
    try writeCollection(folder, images: [FlowDojoFixture.image(2), pixels])
    let changed = try FlowPhotoCollection.load(directory: folder)
    await #expect(throws: (any Error).self) { try await store.importPhotoCollection(changed) }
    #expect(await store.snapshot() == beforeConflict)
  }

  @Test("Occurrence retry compares immutable acquisition session and provenance, not live curation", arguments: ["session", "provenance"])
  func originalImportFacts(kind: String) async throws {
    let folder = temporary(), root = temporary()
    defer { for p in [folder, root] { try? FileManager.default.removeItem(at: p) } }
    try writeCollection(folder, images: [FlowDojoFixture.image(1)])
    let collection = try FlowPhotoCollection.load(directory: folder)
    let store = try await StudioDrawingFixture.store(directory: root, purpose: .validationFixture)
    let first = try #require(try await store.importPhotoCollection(collection).first)
    try await store.renameSource(sourceID: first.id, title: "Curated title")
    try await store.setSourceGroups(sourceID: first.id, subjectID: nil, sessionID: "curated-session")
    let expected = await store.snapshot()
    _ = try await store.importPhotoCollection(collection)
    #expect(await store.snapshot() == expected)
    let original = collection.manifest.entries[0]
    let changed = FlowPhotoCollectionEntry(id: original.id, title: original.title, filename: original.filename,
      sha256: original.sha256, byteCount: original.byteCount,
      sessionID: kind == "session" ? "different-original-session" : original.sessionID,
      provenanceJSON: kind == "provenance" ? Data("{\"fixture\":\"different acquisition testimony\"}".utf8) : original.provenanceJSON)
    let manifest = FlowPhotoCollectionManifest(schemaVersion: 1, id: collection.manifest.id, title: collection.manifest.title, entries: [changed])
    try DrawingArtifactCoding.encoder().encode(manifest).write(to: folder.appendingPathComponent("photo-collection.json"))
    let conflicting = try FlowPhotoCollection.load(directory: folder)
    await #expect(throws: (any Error).self) { try await store.importPhotoCollection(conflicting) }
    #expect(await store.snapshot() == expected)
  }

  @Test("Common Photo metadata is the one live authority and navigation commits cannot overwrite it")
  func neutralMetadataAuthority() async throws {
    let root = temporary(); defer { try? FileManager.default.removeItem(at: root) }
    let library = DrawingLibrary(directoryURL: root)
    let store = FlowPortfolioStore(directory: root, purpose: .validationFixture, library: library)
    try await store.loadRecords()
    let source = try await store.addSource(data: FlowDojoFixture.image(1), title: "Initial")
    let ref = try #require(source.photo)
    #expect(try await library.photos().entries.map(\.reference) == [ref])
    #expect(try await library.photo(ref).reference == ref)
    #expect(try await library.drawings().entries.isEmpty)
    try await library.updatePhotoMetadata(ref, patch: .init(title: .set("Neutral edit"), subjectID: .set("neutral-subject"), excluded: true))
    try await store.refreshPhotoMetadata()
    let live = try #require(await store.snapshot().sources.first)
    #expect(live.title == "Neutral edit" && live.subjectID == "neutral-subject" && live.excluded)
    try await store.selectSource(source.id)
    let metadata = try await library.photoMetadata(ref)
    #expect(metadata.title == "Neutral edit" && metadata.subjectID == "neutral-subject" && metadata.excluded)
    try await store.renameSource(sourceID: source.id, title: "Flow edit")
    #expect(try await library.photoMetadata(ref).title == "Flow edit")
    let actual = try await library.photo(ref)
    #expect(actual.reference == ref)
    #expect(await store.snapshot().sources.first?.photo == ref)
    try await library.updatePhotoMetadata(ref, patch: .init(title: .set(" \t "), subjectID: .set(""), sessionID: .set(" \n ")))
    let cleared = try await library.photoMetadata(ref)
    #expect(cleared.title == nil && cleared.subjectID == nil && cleared.sessionID == nil)
    try await store.refreshPhotoMetadata()
    let displayed = try #require(await store.snapshot().sources.first)
    #expect(displayed.title == "Photo" && displayed.subjectID == nil && displayed.sessionID == nil)
    #expect(displayed.photo == ref)
    try await store.selectSource(source.id)
    let frozen = try await store.freezeTrainingSnapshot()
    let document = try await store.trainingDocument(snapshotID: frozen.id)
    #expect(document.sources.first?.title == "Photo" && document.sources.first?.photo == ref)
    #expect(try await library.photo(ref).record.originalJSON == actual.record.originalJSON)
    await library.closeLibrary()
  }

  @Test("Preparation refuses image bytes or dimensions that do not match its exact Photo")
  func exactPreparationSource() async throws {
    let root = temporary(); defer { try? FileManager.default.removeItem(at: root) }
    let store = try await StudioDrawingFixture.store(directory: root, purpose: .validationFixture)
    let data = FlowDojoFixture.image(1)
    let source = try await store.addSource(data: data, title: "Exact source")
    let photo = try await store.sourcePhoto(source.id)
    let result = try StudioDrawingFixture.production(program: FlowPortfolioTests.program(), raster: FlowPortfolioTests.raster).artifacts
    #expect(throws: (any Error).self) {
      try PortraitDrawingImages.input(result: result, data: FlowDojoFixture.image(2), photo: photo, identity: .init(issuer: UUID()))
    }
    let encoded = try PortraitDrawingImages.sourceAsset(data)
    let minimal = try DrawingImageAsset(descriptor: .init(asset: encoded.asset.descriptor.asset), bytes: data)
    let wrongDimensions = try DrawingImageRecords.photo(identity: .init(issuer: UUID()), original: minimal,
      width: encoded.width + 1, height: encoded.height,
      acquired: .unknown(provenance: "Deliberately contradictory synthetic dimensions"),
      imported: .unknown(provenance: "Synthetic fixture"))
    #expect(throws: (any Error).self) {
      try PortraitDrawingImages.input(result: result, data: data, photo: wrongDimensions, identity: .init(issuer: UUID()))
    }
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
      return .init(id: "entry-\(index)", title: "Fixture photo \(index)", filename: filename, sha256: hash, byteCount: data.count,
        sessionID: "capture:fixture-session", provenanceJSON: Data("{\"fixture\":true}".utf8))
    }
    let manifest = FlowPhotoCollectionManifest(schemaVersion: 1, id: "test-fixture-collection", title: "Explicit test fixtures", entries: entries)
    try DrawingArtifactCoding.encoder().encode(manifest).write(to: folder.appendingPathComponent("photo-collection.json"))
  }
}
