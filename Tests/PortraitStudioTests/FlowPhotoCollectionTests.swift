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
    let store = try FlowPortfolioStore(directory: root, purpose: .validationFixture)
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
    #expect(try Data(contentsOf: root.appendingPathComponent("objects/" + provenance.manifest.sha256)) == collection.manifestData)
    _ = try await store.importPhotoCollection(collection)
    #expect(await store.snapshot() == after)
    try FileManager.default.copyItem(at: root, to: copy)
    let reopened = try FlowPortfolioStore(directory: copy)
    #expect(await reopened.snapshot() == after)
    #expect(try await reopened.sourceData(after.sources[1].id) == images[1])
  }

  @Test("Legacy heads remain read-only until mutation publishes a writer floor preserving new fields")
  func writerCapabilityFloor() async throws {
    let folder = temporary(), root = temporary(), legacy = temporary(), reopenedURL = temporary(), unsupported = temporary()
    defer { for p in [folder, root, legacy, reopenedURL, unsupported] { try? FileManager.default.removeItem(at: p) } }
    let images = [FlowDojoFixture.image(1), FlowDojoFixture.image(2)]
    try writeCollection(folder, images: images)
    let original = try FlowPortfolioStore(directory: root, purpose: .validationFixture)
    _ = try await original.addSource(data: images[0], title: "Legacy source")
    let decoder = JSONDecoder(), encoder = DrawingPackageCodec.encoder()
    let initial = try decoder.decode(FlowPortfolioHead.self, from: Data(contentsOf: root.appendingPathComponent("portfolio.json")))
    #expect(initial.schemaVersion == 2)
    try FileManager.default.copyItem(at: root, to: legacy)
    let headURL = legacy.appendingPathComponent("portfolio.json")
    let legacyHead = FlowPortfolioHead(schemaVersion: 1, portfolioID: initial.portfolioID,
      revision: initial.revision, recordSHA256: initial.recordSHA256)
    let legacyBytes = try encoder.encode(legacyHead)
    try legacyBytes.write(to: headURL)
    let oldRecords = try FileManager.default.contentsOfDirectory(at: legacy.appendingPathComponent("records"), includingPropertiesForKeys: nil)
    let oldBytes = try Dictionary(uniqueKeysWithValues: oldRecords.map { ($0.lastPathComponent, try Data(contentsOf: $0)) })
    let store = try FlowPortfolioStore(directory: legacy)
    #expect(try Data(contentsOf: headURL) == legacyBytes, "Opening an old portfolio does not publish a migration.")
    let collection = try FlowPhotoCollection.load(directory: folder)
    let imported = try await store.importPhotoCollection(collection)
    let source = try #require(imported.last)
    try await store.renameSource(sourceID: source.id, title: "Retained historical photo")
    let recipe = FlowArtistRecipe(values: FlowArtistRecipe.standard.values, marks: .init(wave: 0.5, polygon: 0.2, loop: 0.4, scale: 0.3))
    let round = try await store.beginRound(sourceID: source.id, recipes: [recipe])
    let program = try FlowPortfolioTests.program()
    let candidate = try await store.completeCandidate(roundID: round.id, slot: 0, program: program,
      raster: FlowPortfolioTests.raster, previewPNG: DrawingPackageLibraryValidation.preview(program).bytes)
    try await store.renameCandidate(candidateID: candidate.id, title: "Named mark study")
    let expected = await store.snapshot()
    let newHead = try decoder.decode(FlowPortfolioHead.self, from: Data(contentsOf: headURL))
    #expect(newHead.schemaVersion == 2 && newHead.revision == expected.revision)
    for (name, bytes) in oldBytes {
      #expect(try Data(contentsOf: legacy.appendingPathComponent("records/" + name)) == bytes)
    }
    try FileManager.default.copyItem(at: legacy, to: reopenedURL)
    let reopened = try FlowPortfolioStore(directory: reopenedURL)
    #expect(await reopened.snapshot() == expected)
    #expect(expected.sources.last?.importProvenance != nil && expected.candidates.last?.recipe.marks == recipe.marks)
    #expect(expected.candidates.last?.title == "Named mark study")
    try FileManager.default.copyItem(at: legacy, to: unsupported)
    let unknown = FlowPortfolioHead(schemaVersion: 3, portfolioID: newHead.portfolioID,
      revision: newHead.revision, recordSHA256: newHead.recordSHA256)
    try encoder.encode(unknown).write(to: unsupported.appendingPathComponent("portfolio.json"))
    #expect(throws: (any Error).self) { try FlowPortfolioStore(directory: unsupported) }
  }

  @Test("Camera source metadata survives retry and relocation without merging distinct captures")
  func capturedPhotoProvenance() async throws {
    let root = temporary(), copy = temporary()
    defer { for p in [root, copy] { try? FileManager.default.removeItem(at: p) } }
    let store = try FlowPortfolioStore(directory: root, purpose: .validationFixture)
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
    let reopened = try FlowPortfolioStore(directory: copy)
    #expect(await reopened.snapshot() == expected)
    #expect(try await reopened.sourceData(source.id) == data)
  }

  @Test("Bad hashes and escaping source paths fail before any portfolio mutation")
  func invalidCollection() async throws {
    let folder = temporary(), root = temporary()
    defer { for p in [folder, root] { try? FileManager.default.removeItem(at: p) } }
    try writeCollection(folder, images: [FlowDojoFixture.image(1)])
    let store = try FlowPortfolioStore(directory: root, purpose: .validationFixture)
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
    let store = try FlowPortfolioStore(directory: root, purpose: .validationFixture)
    let source = try await store.addSource(data: FlowDojoFixture.image(1), title: "Before")
    let round = try await store.beginRound(sourceID: source.id, recipes: [.standard])
    let program = try FlowPortfolioTests.program()
    let candidate = try await store.completeCandidate(roundID: round.id, slot: 0, program: program,
      raster: FlowPortfolioTests.raster, previewPNG: DrawingPackageLibraryValidation.preview(program).bytes)
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
    let reopened = try FlowPortfolioStore(directory: copy)
    #expect(await reopened.snapshot() == document)
    try await store.renameCandidate(candidateID: candidate.id, title: " ")
    #expect(await store.snapshot().candidates.first?.title == nil)
  }

  @Test("Import an explicitly authorized retained photo set with a before/after preservation receipt",
    .enabled(if: ProcessInfo.processInfo.environment["FLOW_PHOTO_COLLECTION"] != nil))
  func importDeclaredCollection() async throws {
    let environment = ProcessInfo.processInfo.environment
    let collectionURL = URL(fileURLWithPath: try #require(environment["FLOW_PHOTO_COLLECTION"]))
    let destination = URL(fileURLWithPath: try #require(environment["FLOW_PHOTO_DESTINATION"]))
    let receiptURL = URL(fileURLWithPath: try #require(environment["FLOW_PHOTO_IMPORT_RECEIPT"]))
    let personal = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Documents/Flow Edge Portfolio.flowportfolio")
    if destination.standardizedFileURL == personal.standardizedFileURL {
      try #require(environment["FLOW_PHOTO_ALLOW_ARTIST_WRITE"] == "YES", "Original artist writes require explicit coordinator authorization after app shutdown.")
    }
    try #require(!FileManager.default.fileExists(atPath: receiptURL.path), "Preserve earlier import receipts.")
    let collection = try FlowPhotoCollection.load(directory: collectionURL)
    let store = try FlowPortfolioStore(directory: destination)
    let before = await store.snapshot()
    let result = try await store.importPhotoCollection(collection)
    let after = await store.snapshot()
    var expected = before
    expected.revision = after.revision
    expected.sources = after.sources
    let originalFeedbackUnchanged = after == expected
      && Array(after.sources.prefix(before.sources.count)) == before.sources
    try #require(originalFeedbackUnchanged, "Photo import must preserve every existing record and selection.")
    for source in result {
      try #require(DrawingPackageCodec.sha256(try await store.sourceData(source.id)) == source.image.sha256)
    }
    struct Receipt: Encodable {
      let purpose: String; let destination: String; let collectionID: String; let manifestSHA256: String
      let beforeRevision: Int; let afterRevision: Int; let beforeSourceCount: Int; let afterSourceCount: Int
      let retainedOriginalSourceIDs: [UUID]; let importedSourceHashes: [String]; let originalFeedbackUnchanged: Bool
    }
    let receipt = Receipt(purpose: "Source-only curated historical import; no preferences or inferred subject identities",
      destination: destination.path, collectionID: collection.manifest.id, manifestSHA256: DrawingPackageCodec.sha256(collection.manifestData),
      beforeRevision: before.revision, afterRevision: after.revision, beforeSourceCount: before.sources.count, afterSourceCount: after.sources.count,
      retainedOriginalSourceIDs: before.sources.map(\.id), importedSourceHashes: result.map { $0.image.sha256 }, originalFeedbackUnchanged: originalFeedbackUnchanged)
    try DrawingPackageCodec.encoder().encode(receipt).write(to: receiptURL, options: .atomic)
  }

  private func temporary() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent("flow-photos-" + UUID().uuidString) }
  private func writeCollection(_ folder: URL, images: [Data]) throws {
    try FileManager.default.createDirectory(at: folder.appendingPathComponent("images"), withIntermediateDirectories: true)
    let entries = try images.enumerated().map { index, data -> FlowPhotoCollectionEntry in
      let hash = DrawingPackageCodec.sha256(data), filename = "images/" + hash + ".asset"
      try data.write(to: folder.appendingPathComponent(filename))
      return .init(id: hash, title: "Fixture photo \(index)", filename: filename, sha256: hash, byteCount: data.count,
        sessionID: "capture:fixture-session", provenanceJSON: Data("{\"fixture\":true}".utf8))
    }
    let manifest = FlowPhotoCollectionManifest(schemaVersion: 1, id: "test-fixture-collection", title: "Explicit test fixtures", entries: entries)
    try DrawingPackageCodec.encoder().encode(manifest).write(to: folder.appendingPathComponent("photo-collection.json"))
  }
}
