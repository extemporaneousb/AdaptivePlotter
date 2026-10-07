import Foundation
import Testing

@testable import PlotterApp

@Suite("Durable scoped portrait preference labels")
@MainActor
struct PortraitPreferenceCollectionTests {
  @Test("export preserves exact source, analyzed raster, vectors and label presentation")
  func exactSnapshot() throws {
    let archive = PortraitSketchCollection()
    let preferences = LegacyPortraitPreferenceExportFixture(collection: archive)
    let candidate = try portraitPersistenceCandidate()
    let presentation = try PortraitPresentationContext(drawingHeightMM: 150, inkWidthMM: 1.2)
    #expect(archive.rate(candidate: candidate, rating: 1, scope: .screenSketch, presentation: presentation) == nil)
    let data = try preferences.exportData()
    let document = try JSONDecoder().decode(PortraitPreferenceExport.self, from: data)
    #expect(document.schemaVersion == 2)
    let example = try #require(document.examples.first)
    #expect(example.candidate.id == candidate.id)
    #expect(example.photoData == candidate.sourceData)
    #expect(example.candidate.rasterSHA256 == candidate.rasterSHA256)
    #expect(example.program == candidate.program)
    #expect(example.recipe == candidate.recipe)
    #expect(example.rating == 1)
    #expect(example.label.presentation == presentation)
    #expect(example.label.scope == .screenSketch)
  }

  @Test("rerating appends immutable label revisions with distinct scale/ink context")
  func labelHistory() throws {
    let archive = PortraitSketchCollection()
    let preferences = LegacyPortraitPreferenceExportFixture(collection: archive)
    let candidate = try portraitPersistenceCandidate()
    #expect(archive.rate(candidate: candidate, rating: 2, scope: .screenSketch,
      presentation: try .init(drawingHeightMM: 100, inkWidthMM: 0.4)) == nil)
    let first = try #require(preferences.examples.first)
    #expect(archive.rate(candidate: candidate, rating: 5, scope: .screenSketch,
      presentation: try .init(drawingHeightMM: 200, inkWidthMM: 0.8)) == nil)
    #expect(archive.entries.count == 1)
    #expect(preferences.examples.count == 2)
    #expect(preferences.examples[0].label == first.label)
    #expect(preferences.examples[1].id != first.id)
    #expect(preferences.examples[1].label.previousRevisionID == first.id)
    #expect(preferences.examples[1].label.presentation != first.label.presentation)
  }

  @Test("withdrawing a label updates eligible examples but preserves historical identity")
  func withdrawLabel() throws {
    let archive = PortraitSketchCollection()
    let preferences = LegacyPortraitPreferenceExportFixture(collection: archive)
    let candidate = try portraitPersistenceCandidate()
    _ = archive.rate(candidate: candidate, rating: 3, scope: .screenSketch, presentation: try .init())
    let original = try #require(preferences.examples.first)
    let exportSnapshot = preferences.examples
    preferences.remove(original.id)
    #expect(preferences.examples.isEmpty)
    #expect(archive.labels.count == 1)
    #expect(archive.labels[0] == original.label)
    #expect(archive.entries.count == 1)
    #expect(archive.tombstones.contains { $0.kind == .label && $0.identity == original.id.uuidString })
    #expect(throws: PortraitPreferenceError.self) { try preferences.exportData() }
    let historical = try JSONDecoder().decode(PortraitPreferenceExport.self,
      from: LegacyPortraitPreferenceExportFixture.exportData(examples: exportSnapshot))
    #expect(historical.examples[0].id == original.id)
  }

  @Test("deleting then retaining identical content never resurrects old eligible labels")
  func deletionAndReretention() async throws {
    for deleteSource in [false, true] {
      let directory = FileManager.default.temporaryDirectory.appendingPathComponent("portrait-deletion-\(UUID().uuidString)")
      defer { try? FileManager.default.removeItem(at: directory) }
      let archive = PortraitSketchCollection(store: .init(directoryURL: directory))
      let preferences = LegacyPortraitPreferenceExportFixture(collection: archive)
      let candidate = try portraitPersistenceCandidate()
      _ = archive.rate(candidate: candidate, rating: 4, scope: .screenSketch, presentation: try .init())
      await archive.awaitPersistence()
      let deletedLabel = try #require(archive.labels.first)
      if deleteSource { archive.deleteSource(candidate.sourceSHA256) }
      else { archive.remove(candidate.id) }
      await archive.awaitPersistence()
      #expect(archive.retain(candidate: candidate, reason: .shortlisted) != nil)
      #expect(archive.rate(candidate: candidate, rating: 2, scope: .screenSketch, presentation: try .init()) != nil)
      await archive.awaitPersistence()
      #expect(preferences.examples.isEmpty)
      #expect(archive.entries.isEmpty && archive.labels == [deletedLabel])
      // Cold pending replay must discover committed deletion before it can add
      // a label, even when that deletion was not yet published to this owner.
      let coldDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("portrait-cold-deletion-\(UUID().uuidString)")
      defer { try? FileManager.default.removeItem(at: coldDirectory) }
      try FileManager.default.copyItem(at: directory, to: coldDirectory)
      let cold = PortraitSketchCollection(store: .init(directoryURL: coldDirectory))
      _ = cold.rate(candidate: candidate, rating: 2, scope: .screenSketch, presentation: try .init())
      await cold.awaitPersistence()
      #expect(cold.entries.isEmpty && cold.labels == [deletedLabel])
      #expect(cold.persistenceState == .saved && cold.unresolvedMutations == 0)
      // Explicit authoring can reproduce identical content. Creation provenance
      // must be fresh; content identity and the old label remain unchanged.
      let fresh = try PortraitCandidate(sourceData: candidate.sourceData, sourcePixelExtent: candidate.sourcePixelExtent,
        raster: candidate.raster, recipe: candidate.recipe, program: candidate.program,
        photoID: candidate.photoID, captureSessionID: candidate.captureSessionID, createdAt: Date(),
        lineage: candidate.lineage, checkpointID: candidate.checkpointID, pose: candidate.pose,
        proposal: candidate.proposal, warpManifest: candidate.warpManifest)
      let deletion = try #require(archive.tombstones.last)
      #expect(fresh.id == candidate.id && fresh.createdAt > deletion.createdAt)
      #expect(archive.retain(candidate: fresh, reason: .shortlisted) == nil)
      await archive.awaitPersistence()
      #expect(preferences.examples.isEmpty)
      #expect(archive.rate(candidate: fresh, rating: 2, scope: .screenSketch, presentation: try .init()) == nil)
      await archive.awaitPersistence()
      #expect(preferences.examples.count == 1)
      let newExample = try #require(preferences.examples.first)
      #expect(newExample.id != deletedLabel.id && newExample.candidate.createdAt == fresh.createdAt)
      #expect(archive.archive.withdrawnLabelIDs.contains(deletedLabel.id.uuidString))
      let restored = PortraitSketchCollection(store: .init(directoryURL: directory))
      await restored.load()
      #expect(LegacyPortraitPreferenceExportFixture(collection: restored).examples.count == 1)
      #expect(restored.labels.count == 2)
    }
  }

  @Test("decoded invalid presentation and conflicting scope are refused before retention")
  func invalidDecodedContracts() throws {
    let archive = PortraitSketchCollection()
    let candidate = try portraitPersistenceCandidate()
    let valid = try PortraitLabelRevision(candidate: candidate, rating: 3, scope: .screenSketch,
      presentation: .init())
    let bytes = try PortraitCandidateCoding.encoder().encode(valid)
    var json = try #require(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
    var presentation = try #require(json["presentation"] as? [String: Any])
    presentation["drawingHeightMM"] = -1
    json["presentation"] = presentation
    let decoded = try JSONDecoder().decode(PortraitLabelRevision.self, from: JSONSerialization.data(withJSONObject: json))
    #expect(archive.rate(candidate: candidate, rating: 3, scope: decoded.scope,
      presentation: decoded.presentation) != nil)
    let conflicting = PortraitStyleScope(id: UUID(), name: "Conflicting", revision: 1,
      objective: .screenAesthetic, allowedFamilies: [.hatch], activeParameters: [.headScale],
      frozenParameters: [.init(parameter: .headScale, value: 1)])
    #expect(archive.rate(candidate: candidate, rating: 3, scope: conflicting, presentation: try .init()) != nil)
    #expect(archive.entries.isEmpty)
    #expect(archive.labels.isEmpty)
  }

  @Test("export has no former session limit and remains independent of later withdrawals")
  func unboundedExportSnapshot() async throws {
    let archive = PortraitSketchCollection()
    let preferences = LegacyPortraitPreferenceExportFixture(collection: archive)
    let candidate = try portraitPersistenceCandidate()
    for rating in 0...39 {
      #expect(archive.rate(candidate: candidate, rating: rating % 5 + 1,
        scope: .screenSketch, presentation: try .init()) == nil)
    }
    let snapshot = preferences.examples
    preferences.remove(snapshot[0].id)
    let data = try await Task.detached {
      try LegacyPortraitPreferenceExportFixture.exportData(examples: snapshot)
    }.value
    #expect(try JSONDecoder().decode(PortraitPreferenceExport.self, from: data).examples.count == 40)
    #expect(preferences.examples.count == 39)
  }
}
