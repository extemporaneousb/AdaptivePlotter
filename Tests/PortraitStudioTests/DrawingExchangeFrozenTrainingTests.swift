import Foundation
import DrawingLibrary
import PortraitArtists
import PortraitCore
@testable import PortraitLibrary
import PortraitStudioUI
import Testing

private extension FlowPortfolioStore {
  /// Erases session-only geometry and locator caches, never the pinned assets.
  func forgetFeedbackSessionArtifacts() {
    temporaryDrawings.removeAll(); drawingInputs.removeAll(); sourcePhotoRecords.removeAll()
    previewArtifacts.removeAll(); featureCapsules.removeAll(); featureSupportingAssets.removeAll()
    storage.keepUnpublished([])
  }
}

@Suite("DX09 frozen training authority", .serialized)
struct DrawingExchangeFrozenTrainingTests {
  @Test("Exact feature assets retain observed producer, extractor and ordered stroke basis")
  func featureFacts() async throws {
    let root = DrawingExchangeFeedbackFixture.root(); defer { try? FileManager.default.removeItem(at: root) }
    let fixture = try await DrawingExchangeFeedbackFixture.make(directory: root)
    let candidate = fixture.candidates[0][0]
    let drawing = try #require(await fixture.store.temporaryDrawings[candidate.id])
    let capsule = try await fixture.store.featureCapsule(candidateID: candidate.id)
    #expect(capsule.strokeIDs == drawing.program.strokes.map(\.id))
    #expect(capsule.recipe == candidate.recipe)
    #expect(capsule.strokes.count == capsule.strokeIDs.count)
    #expect(capsule.programDigest.description == candidate.programHash)
    #expect(capsule.producer.nativeVerified == drawing.capabilities.producerVerified)
    #expect(capsule.producer.id == drawing.producer.id && capsule.producer.version == drawing.producer.version)
    #expect(capsule.producer.record.object == ExchangeDigest.hash(drawing.producer.originalJSON))
    #expect(!capsule.extractor.nativeVerified)
    #expect(capsule.extractor.version == FlowArtistFeatures.revision)
    let presentation = try await fixture.store.presentRoundRanking(candidate.roundID, seed: 42)
    _ = try await fixture.store.recordRanking(presentationID: presentation.id, orderedGroups: presentation.items.map { [$0.id] })
    #expect(try await fixture.library.asset(capsule.asset.object) == DrawingArtifactCoding.encoder().encode(capsule))
    #expect(try await fixture.library.drawings().entries.isEmpty)
    await fixture.library.closeLibrary()
  }

  @Test("Cold frozen inputs ignore deleted live feature locators and absent temporary geometry")
  func hostileLiveLocators() async throws {
    let root = DrawingExchangeFeedbackFixture.root(); defer { try? FileManager.default.removeItem(at: root) }
    let fixture = try await DrawingExchangeFeedbackFixture.make(directory: root)
    let presentation = try await fixture.store.presentRoundRanking(fixture.candidates[0][0].roundID, seed: 42)
    _ = try await fixture.store.recordRanking(presentationID: presentation.id, orderedGroups: presentation.items.map { [$0.id] })
    let snapshot = try await fixture.store.freezeTrainingSnapshot()
    let frozen = try await fixture.store.trainingDocument(snapshotID: snapshot.id)
    let baseline = try await fixture.store.trainingInputs(snapshotID: snapshot.id)
    #expect(!baseline.rankings.isEmpty && baseline.seed == 42 && baseline.configuration == .current)
    let locators = try await fixture.library.records(kind: "adaptiveplotter.flow-features/2")
    try #require(!locators.isEmpty)
    // Delete navigation only; exact feature assets remain reachable from the
    // frozen manifest. A cold reader cannot pass through a warmed UUID cache.
    try await fixture.library.commitRecords([], removing: locators.map(\.key))
    await fixture.store.forgetFeedbackSessionArtifacts()
    await fixture.library.closeLibrary()
    let coldLibrary = DrawingLibrary(directoryURL: root)
    let cold = FlowPortfolioStore(directory: root, purpose: .validationFixture, library: coldLibrary)
    try await cold.loadRecords()
    let geometryEmpty = await cold.temporaryDrawings.isEmpty
    let featuresEmpty = await cold.featureCapsules.isEmpty
    #expect(geometryEmpty && featuresEmpty)
    let actual = try await cold.trainingInputs(snapshotID: snapshot.id)
    #expect(actual.examples == baseline.examples && actual.rankings == baseline.rankings)
    #expect(actual.seed == baseline.seed && actual.holdoutGroupIDs == baseline.holdoutGroupIDs)
    let adapter = try await FlowAuthoringTraining.dataset(store: cold, document: frozen)
    #expect(adapter.examples == baseline.examples && adapter.rankings == baseline.rankings)
    #expect(try await coldLibrary.drawings().entries.isEmpty)
    await coldLibrary.closeLibrary()
  }

  @Test("Neutral Photo curation changes future freezes without changing an existing manifest")
  func futureCurationOnly() async throws {
    let root = DrawingExchangeFeedbackFixture.root(); defer { try? FileManager.default.removeItem(at: root) }
    let fixture = try await DrawingExchangeFeedbackFixture.make(directory: root)
    let candidate = fixture.candidates[0][0]
    try await fixture.store.chooseCandidate(candidate.id)
    _ = try await fixture.store.applyPrune(candidateID: candidate.id, action: .remove, indices: [0])
    _ = try await fixture.store.applyPrune(candidateID: candidate.id, action: .completeTarget)
    let snapshot = try await fixture.store.freezeTrainingSnapshot()
    let baseline = try await fixture.store.trainingInputs(snapshotID: snapshot.id)
    try #require(!baseline.examples.isEmpty)
    let photo = try #require(fixture.sources[0].photo)
    try await fixture.library.updatePhotoMetadata(photo, patch: .init(subjectID: .set("later-curated-subject"), sessionID: .set("later-session"), excluded: true))
    let unchanged = try await fixture.store.trainingInputs(snapshotID: snapshot.id)
    #expect(unchanged.examples == baseline.examples && unchanged.rankings == baseline.rankings)
    #expect(unchanged.holdoutGroupIDs == baseline.holdoutGroupIDs)
    let later = try await fixture.store.freezeTrainingSnapshot()
    let excluded = try await fixture.store.trainingInputs(snapshotID: later.id)
    #expect(excluded.examples.isEmpty && excluded.rankings.isEmpty)
    await fixture.library.closeLibrary()
  }
  @Test("Closed manifest reload is independent of the original owner and refuses missing or corrupt exact feature assets")
  func offlineManifestAndSelectedIntegrity() async throws {
    let root = DrawingExchangeFeedbackFixture.root(); defer { try? FileManager.default.removeItem(at: root) }
    let originalDirectory = root.appendingPathComponent("original")
    let fixture = try await DrawingExchangeFeedbackFixture.make(directory: originalDirectory)
    let candidate = fixture.candidates[0][0]
    try await fixture.store.chooseCandidate(candidate.id)
    _ = try await fixture.store.applyPrune(candidateID: candidate.id, action: .remove, indices: [0])
    _ = try await fixture.store.applyPrune(candidateID: candidate.id, action: .completeTarget)
    let snapshot = try await fixture.store.freezeTrainingSnapshot()
    let manifest = try await fixture.store.trainingManifest(snapshotID: snapshot.id)
    let expected = try await fixture.store.trainingInputs(snapshotID: snapshot.id)
    #expect(manifest.seed == 42 && manifest.configuration == .current)
    #expect(manifest.holdoutGroupIDs == expected.holdoutGroupIDs)
    #expect(manifest.curation.map(\.id) == fixture.sources.map(\.id))
    #expect(!manifest.feedback.isEmpty && !manifest.entries.isEmpty)
    let asset = try #require(manifest.entries.first?.rootFeatures)
    let selected = originalDirectory.appendingPathComponent("objects/sha256/" + asset.object.description)
    let bytes = try Data(contentsOf: selected)
    try FileManager.default.removeItem(at: selected)
    await #expect(throws: (any Error).self) { try await fixture.store.trainingInputs(snapshotID: snapshot.id) }
    try Data(repeating: 0x78, count: bytes.count).write(to: selected, options: .atomic)
    await #expect(throws: (any Error).self) { try await fixture.store.trainingInputs(snapshotID: snapshot.id) }
    try bytes.write(to: selected, options: .atomic)
    let restored = try await fixture.store.trainingInputs(snapshotID: snapshot.id)
    #expect(restored.examples == expected.examples && restored.rankings == expected.rankings)
    let exported = root.appendingPathComponent("training.zip")
    try await fixture.store.exportTraining(snapshotID: snapshot.id, to: exported)
    let staging = root.appendingPathComponent("task-inspection")
    try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
    let staged = try DrawingExchangeCarrier.stageZIP(exported, stagingParent: staging)
    let task = try ExchangeAdmission.validate(staged)
    #expect(task.drawings.isEmpty)
    #expect(!task.files.entries.keys.contains { $0.hasPrefix("data/photos/") || $0.hasPrefix("data/inputs/") || $0.hasPrefix("data/drawings/") })
    #expect(task.index.known?.assets.allSatisfy { !["image/png", "image/jpeg"].contains($0.asset.mediaType) } == true)
    await fixture.library.closeLibrary()
    try FileManager.default.removeItem(at: originalDirectory)
    let offlineDirectory = root.appendingPathComponent("offline")
    let offlineLibrary = DrawingLibrary(directoryURL: offlineDirectory)
    let offline = FlowPortfolioStore(directory: offlineDirectory, purpose: .validationFixture, library: offlineLibrary)
    let loaded = try await offline.loadTraining(from: exported)
    #expect(loaded.examples == expected.examples && loaded.rankings == expected.rankings)
    #expect(loaded.seed == expected.seed && loaded.configuration == expected.configuration)
    #expect(loaded.holdoutGroupIDs == expected.holdoutGroupIDs)
    #expect(try await offlineLibrary.drawings().entries.isEmpty)
    #expect(!FileManager.default.fileExists(atPath: offlineDirectory.path))
    await offlineLibrary.closeLibrary()
  }

  @Test("A preserved task with an unknown manifest or extractor profile cannot train", arguments: ["profile", "extractorVersion", "trainerVersion"])
  func unsupportedFrozenProfile(field: String) async throws {
    let root = DrawingExchangeFeedbackFixture.root(); defer { try? FileManager.default.removeItem(at: root) }
    let fixture = try await DrawingExchangeFeedbackFixture.make(directory: root)
    let candidate = fixture.candidates[0][0]
    try await fixture.store.chooseCandidate(candidate.id)
    let snapshot = try await fixture.store.freezeTrainingSnapshot()
    let publication = try #require(snapshot.publication)
    let package = try await fixture.library.feedback(publication)
    let scope = try #require(package.index.known?.scope)
    var files: [String: Data] = [:]
    for path in package.files.entries.keys where path.hasPrefix("data/") { files[path] = try package.files.record(at: path) }
    let path = "data/objects/sha256/" + scope.object.description
    var manifest = try #require(JSONSerialization.jsonObject(with: package.files.record(scope.object)) as? [String: Any])
    manifest[field] = "example.unsupported/1"
    let bytes = try DrawingExchangeFeedbackFixture.json(manifest)
    let replacement = try ExchangeAsset(bytes: bytes, mediaType: "application/json", encoding: "utf8-json")
    files.removeValue(forKey: path)
    files["data/objects/sha256/" + replacement.object.description] = bytes
    let indexBytes = try #require(files["data/exchange.json"])
    var index = try #require(JSONSerialization.jsonObject(with: indexBytes) as? [String: Any])
    var assets = try #require(index["assets"] as? [[String: Any]])
    let position = try #require(assets.firstIndex { $0["object"] as? String == scope.object.description })
    assets[position] = try #require(JSONSerialization.jsonObject(with: DrawingArtifactCoding.encoder().encode(ExchangeAssetDescriptor(asset: replacement))) as? [String: Any])
    index["assets"] = assets
    index["scope"] = try JSONSerialization.jsonObject(with: DrawingArtifactCoding.encoder().encode(replacement))
    files["data/exchange.json"] = try DrawingExchangeFeedbackFixture.json(index)
    let changed = try FlowFeedbackCarrier.prepare(files)
    defer { try? FileManager.default.removeItem(at: changed.temporaryRoot) }
    #expect(try changed.package.files.record(replacement.object) == bytes)
    #expect(throws: (any Error).self) { try FlowTrainingReader.inputs(package: changed.package) }
    await fixture.library.closeLibrary()
  }

}
