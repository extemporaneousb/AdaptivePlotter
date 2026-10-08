import Foundation
import Testing

@testable import PlotterApp

@Suite("Durable scoped portrait preference labels")
@MainActor
struct PortraitPreferenceCollectionTests {
  @Test("cold Clear Unkept History explicitly joins full history before deriving exact drawing deletion")
  func coldClearLoadsHistory() async throws {
    let history = try await PortraitColdMutationHistoryFixture.make()
    defer { history.remove() }
    let collection = PortraitSketchCollection(store: .init(directoryURL: history.directory))
    #expect(!collection.historyLoadHasCompleted && collection.attempts.isEmpty)
    collection.clearUnkeptHistory()
    await collection.awaitPersistence()
    #expect(collection.historyLoadHasCompleted && collection.persistenceState == .saved)
    #expect(collection.attempts.map(\.id) == [history.kept.id])
    #expect(collection.labels == [history.label])
    #expect(collection.savedStyles.map(\.name) == ["Historical style"])
    #expect(collection.sketches.contains(history.generic))
    #expect(collection.tombstones.contains { $0.kind == .drawing
      && $0.identity == PortraitDrawingIdentity(candidateID: history.unkept.id, photoID: history.unkept.photoID).id })
    let restarted = PortraitSketchCollection(store: .init(directoryURL: history.directory))
    #expect(try await restarted.librarySelection(photoID: history.kept.photoID).drawings.first?.summary.feedback == .promising)
    #expect(try await restarted.librarySelection(photoID: history.unkept.photoID).drawings.isEmpty)
  }

  @Test("failed explicit history remains incomplete and Retry verifies full history before committing pending labels")
  func failedFullHistoryRetry() async throws {
    let history = try await PortraitColdMutationHistoryFixture.make()
    defer { history.remove() }
    let db = try PortraitLibraryDatabase(url: history.directory.appendingPathComponent("library-v1.sqlite"), readOnly: true)
    let selectedHash = try db.scalar("SELECT record_hash FROM label WHERE id=?", [history.label.id.uuidString])
    let hash = try #require(selectedHash)
    let path = history.directory.appendingPathComponent("records").appendingPathComponent(hash)
    let bytes = try Data(contentsOf: path)
    try FileManager.default.removeItem(at: path)
    let collection = PortraitSketchCollection(store: .init(directoryURL: history.directory))
    await collection.load()
    #expect(!collection.historyLoadHasCompleted)
    guard case .failed = collection.persistenceState else { Issue.record("Damaged full history was admitted"); return }
    let candidate = try portraitPersistenceCandidate(seed: 997)
    #expect(collection.rate(candidate: candidate, rating: 3, scope: .screenSketch, presentation: try .init()) == nil)
    await collection.awaitPersistence()
    #expect(!collection.historyLoadHasCompleted && collection.unresolvedMutations > 0)
    try bytes.write(to: path, options: .atomic)
    collection.retryPersistence()
    await collection.awaitPersistence()
    #expect(collection.historyLoadHasCompleted && collection.persistenceState == .saved)
    #expect(Set(collection.entries.map(\.id)) == Set([history.kept.id, history.unkept.id, candidate.id]))
    #expect(collection.labels.contains(history.label) && collection.labels.count == 2)
    try history.expectPreserved()
  }

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
      if deleteSource { archive.deleteSource(photoID: candidate.photoID) }
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
      // A deleted capture cannot be recreated by a later timestamp. Reimporting
      // identical bytes creates a new capture while retaining content identity.
      if deleteSource {
        let late = try PortraitCandidate(sourceData: candidate.sourceData, sourcePixelExtent: candidate.sourcePixelExtent,
          raster: candidate.raster, recipe: candidate.recipe, program: candidate.program,
          photoID: candidate.photoID, captureSessionID: candidate.captureSessionID, createdAt: Date(),
          lineage: candidate.lineage, checkpointID: candidate.checkpointID, pose: candidate.pose,
          proposal: candidate.proposal, warpManifest: candidate.warpManifest)
        #expect(archive.retain(candidate: late, reason: .shortlisted) != nil)
      }
      let fresh = try PortraitCandidate(sourceData: candidate.sourceData, sourcePixelExtent: candidate.sourcePixelExtent,
        raster: candidate.raster, recipe: candidate.recipe, program: candidate.program,
        photoID: deleteSource ? UUID() : candidate.photoID,
        captureSessionID: deleteSource ? UUID() : candidate.captureSessionID, createdAt: Date(),
        lineage: candidate.lineage, checkpointID: candidate.checkpointID, pose: candidate.pose,
        proposal: candidate.proposal, warpManifest: candidate.warpManifest)
      let deletion = try #require(archive.tombstones.last)
      #expect(fresh.id == candidate.id && fresh.createdAt > deletion.createdAt)
      #expect(!deleteSource || fresh.photoID != candidate.photoID)
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

  @Test("batched equal-content capture ratings keep separate ancestry and deleting one preserves the other", arguments: [false, true])
  func captureScopedLabels(deletePhoto: Bool) async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("portrait-label-occurrences-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: directory) }
    let collection = PortraitSketchCollection(store: .init(directoryURL: directory))
    let first = try portraitPersistenceCandidate(seed: 984)
    let second = try PortraitCandidate(sourceData: first.sourceData, sourcePixelExtent: first.sourcePixelExtent,
      raster: first.raster, recipe: first.recipe, program: first.program, photoID: UUID(),
      captureSessionID: UUID(), createdAt: first.createdAt, lineage: first.lineage,
      checkpointID: first.checkpointID, pose: first.pose, proposal: first.proposal,
      warpManifest: first.warpManifest)
    #expect(first.id == second.id && first.photoID != second.photoID)
    // Intentionally do not yield between these ratings. The batch must persist
    // both occurrences even though the advisory cache holds one candidate ID.
    #expect(collection.rate(candidate: first, rating: 4, scope: .screenSketch, presentation: try .init()) == nil)
    let firstLabel = try #require(collection.labels.last)
    #expect(collection.rate(candidate: second, rating: 2, scope: .screenSketch, presentation: try .init()) == nil)
    let secondLabel = try #require(collection.labels.last)
    #expect(secondLabel.previousRevisionID == nil)
    #expect(collection.rate(candidate: first, rating: 5, scope: .screenSketch, presentation: try .init()) == nil)
    let firstRevision = try #require(collection.labels.last)
    #expect(firstRevision.previousRevisionID == firstLabel.id)
    await collection.awaitPersistence()
    #expect(collection.persistenceState == .saved && collection.unresolvedMutations == 0)
    #expect(collection.archive.labelPhotoIDs?[firstLabel.id.uuidString.lowercased()] == first.photoID)
    #expect(collection.archive.labelPhotoIDs?[secondLabel.id.uuidString.lowercased()] == second.photoID)
    let secondIdentity = PortraitDrawingIdentity(candidateID: second.id, photoID: second.photoID)
    #expect(try await collection.drawingForBrowsing(secondIdentity).sourcePhotoID == second.photoID)
    if deletePhoto { collection.deleteSource(photoID: first.photoID) }
    else { collection.deleteDrawing(.init(candidateID: first.id, photoID: first.photoID)) }
    await collection.awaitPersistence()
    #expect(collection.archive.withdrawnLabelIDs.contains(firstLabel.id.uuidString))
    #expect(collection.archive.withdrawnLabelIDs.contains(firstRevision.id.uuidString))
    #expect(!collection.archive.withdrawnLabelIDs.contains(secondLabel.id.uuidString))
    let restored = PortraitSketchCollection(store: .init(directoryURL: directory))
    await restored.load()
    #expect(restored.persistenceState == .saved && restored.labels.count == 3)
    for original in [firstLabel, secondLabel, firstRevision] {
      let retained = try #require(restored.labels.first { $0.id == original.id })
      #expect(try PortraitCandidateCoding.encoder().encode(retained) == PortraitCandidateCoding.encoder().encode(original))
    }
    #expect(restored.archive.labelPhotoIDs?[secondLabel.id.uuidString.lowercased()] == second.photoID)
    let eligible = LegacyPortraitPreferenceExportFixture(collection: restored).examples
    #expect(eligible.map(\.id) == [secondLabel.id])
    #expect(eligible.first?.candidate.photoID == second.photoID)
    #expect(restored.rate(candidate: second, rating: 3, scope: .screenSketch, presentation: try .init()) == nil)
    let next = try #require(restored.labels.last)
    #expect(next.previousRevisionID == secondLabel.id)
    await restored.awaitPersistence()
    let reopened = PortraitSketchCollection(store: .init(directoryURL: directory))
    await reopened.load()
    #expect(Set(LegacyPortraitPreferenceExportFixture(collection: reopened).examples.map(\.id)) == Set([secondLabel.id, next.id]))
  }

  @Test("batched equal candidate IDs preserve per-capture attempts, feedback and retention across restart")
  func batchedOccurrenceMetadata() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("portrait-occurrence-metadata-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: directory) }
    let collection = PortraitSketchCollection(store: .init(directoryURL: directory))
    let first = try portraitPersistenceCandidate(seed: 985)
    let second = try PortraitCandidate(sourceData: first.sourceData, sourcePixelExtent: first.sourcePixelExtent,
      raster: first.raster, recipe: first.recipe, program: first.program, photoID: UUID(),
      captureSessionID: UUID(), createdAt: first.createdAt, lineage: first.lineage,
      checkpointID: first.checkpointID, pose: first.pose, proposal: first.proposal,
      warpManifest: first.warpManifest)
    let firstAttempt = try PortraitAttemptRecord.prepare(candidate: first, pen: portraitTestStyle())
    let secondAttempt = try PortraitAttemptRecord.prepare(candidate: second, pen: portraitTestStyle())
    collection.recordAttempt(first, record: firstAttempt)
    collection.setFeedback(.promising, for: first.id)
    collection.recordAttempt(second, record: secondAttempt)
    collection.setFeedback(.rejected, for: second.id)
    #expect(collection.retain(candidate: first, reason: .shortlisted) == nil)
    await collection.awaitPersistence()
    #expect(collection.persistenceState == .saved && collection.unresolvedMutations == 0)
    let restored = PortraitSketchCollection(store: .init(directoryURL: directory))
    await restored.load()
    let canonical = try #require(restored.entries.first)
    #expect([first.photoID, second.photoID].contains(canonical.candidate.photoID))
    #expect(canonical.attempt?.thumbnailPNG == (canonical.candidate.photoID == first.photoID
      ? firstAttempt.thumbnailPNG : secondAttempt.thumbnailPNG))
    #expect(canonical.attempt?.feedback == (canonical.candidate.photoID == first.photoID ? .promising : .rejected))
    #expect(canonical.reasons.contains { $0.reason == .shortlisted } == (canonical.candidate.photoID == first.photoID))
    let firstProjection = try await restored.librarySelection(photoID: first.photoID)
    let secondProjection = try await restored.librarySelection(photoID: second.photoID)
    #expect(firstProjection.drawings.first?.summary.feedback == .promising)
    #expect(secondProjection.drawings.first?.summary.feedback == .rejected)
    #expect(firstProjection.drawings.first?.summary.isSaved == true)
    #expect(secondProjection.drawings.first?.summary.isSaved == false)
    #expect(try await restored.drawingForBrowsing(.init(candidateID: second.id, photoID: second.photoID)).sourcePhotoID == second.photoID)
  }

  @Test("feedback queued for a committed capture cannot move to a later equal-ID attempt")
  func committedFeedbackKeepsCapture() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("portrait-feedback-capture-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: directory) }
    let collection = PortraitSketchCollection(store: .init(directoryURL: directory))
    let first = try portraitPersistenceCandidate(seed: 987)
    let second = try PortraitCandidate(sourceData: first.sourceData, sourcePixelExtent: first.sourcePixelExtent,
      raster: first.raster, recipe: first.recipe, program: first.program, photoID: UUID(),
      captureSessionID: UUID(), createdAt: first.createdAt, lineage: first.lineage,
      checkpointID: first.checkpointID, pose: first.pose, proposal: first.proposal,
      warpManifest: first.warpManifest)
    collection.recordAttempt(first, record: try .prepare(candidate: first, pen: portraitTestStyle()))
    await collection.awaitPersistence()
    #expect(collection.persistenceState == .saved)
    collection.setFeedback(.promising, for: first.id)
    collection.recordAttempt(second, record: try .prepare(candidate: second, pen: portraitTestStyle()))
    #expect(collection.entries.first?.candidate.photoID == second.photoID)
    #expect(collection.entries.first?.attempt?.feedback == .unknown)
    await collection.awaitPersistence()
    #expect(collection.persistenceState == .saved)
    let restored = PortraitSketchCollection(store: .init(directoryURL: directory))
    #expect(try await restored.librarySelection(photoID: first.photoID).drawings.first?.summary.feedback == .promising)
    #expect(try await restored.librarySelection(photoID: second.photoID).drawings.first?.summary.feedback == .unknown)
    // The metadata-only browser binds its displayed capture before the mutation
    // owner loads canonical history, then reads only that occurrence's metadata.
    await restored.loadDrawingBrowser(photoID: second.photoID)
    #expect(restored.entries.isEmpty && !restored.historyLoadHasCompleted)
    restored.setFeedback(.rejected, for: second.id)
    await restored.awaitPersistence()
    #expect(restored.persistenceState == .saved)
    let reopened = PortraitSketchCollection(store: .init(directoryURL: directory))
    #expect(try await reopened.librarySelection(photoID: first.photoID).drawings.first?.summary.feedback == .promising)
    #expect(try await reopened.librarySelection(photoID: second.photoID).drawings.first?.summary.feedback == .rejected)
  }

  @Test("withdrawing a predecessor in the same rating batch preserves its descendant and immutable ancestry")
  func batchedWithdrawnPredecessor() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("portrait-withdrawn-ancestry-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: directory) }
    let collection = PortraitSketchCollection(store: .init(directoryURL: directory))
    let candidate = try portraitPersistenceCandidate(seed: 988)
    #expect(collection.rate(candidate: candidate, rating: 4, scope: .screenSketch, presentation: try .init()) == nil)
    let predecessor = try #require(collection.labels.last)
    #expect(collection.rate(candidate: candidate, rating: 2, scope: .screenSketch, presentation: try .init()) == nil)
    let descendant = try #require(collection.labels.last)
    #expect(descendant.previousRevisionID == predecessor.id)
    collection.withdrawLabel(predecessor.id)
    await collection.awaitPersistence()
    #expect(collection.persistenceState == .saved && collection.unresolvedMutations == 0)
    let restored = PortraitSketchCollection(store: .init(directoryURL: directory))
    await restored.load()
    #expect(restored.persistenceState == .saved && restored.labels.count == 2)
    #expect(restored.labels.first { $0.id == predecessor.id } == predecessor)
    #expect(restored.labels.first { $0.id == descendant.id } == descendant)
    #expect(restored.archive.withdrawnLabelIDs.contains(predecessor.id.uuidString))
    #expect(!restored.archive.withdrawnLabelIDs.contains(descendant.id.uuidString))
    #expect(LegacyPortraitPreferenceExportFixture(collection: restored).examples.map(\.id) == [descendant.id])
  }

  @Test("new clear and string removal delete only their captured portrait occurrence", arguments: [false, true])
  func newDeletionKeepsSavedSibling(clear: Bool) async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("portrait-deletion-sibling-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: directory) }
    let collection = PortraitSketchCollection(store: .init(directoryURL: directory))
    let first = try portraitPersistenceCandidate(seed: 989)
    #expect(collection.rate(candidate: first, rating: 4, scope: .screenSketch, presentation: try .init()) == nil)
    let keptLabel = try #require(collection.labels.first)
    await collection.awaitPersistence()
    let second = try PortraitCandidate(sourceData: first.sourceData, sourcePixelExtent: first.sourcePixelExtent,
      raster: first.raster, recipe: first.recipe, program: first.program, photoID: UUID(),
      captureSessionID: UUID(), createdAt: first.createdAt, lineage: first.lineage,
      checkpointID: first.checkpointID, pose: first.pose, proposal: first.proposal,
      warpManifest: first.warpManifest)
    collection.recordAttempt(second, record: try .prepare(candidate: second, pen: portraitTestStyle()))
    if clear { collection.clearUnkeptHistory() }
    else { collection.remove(second.id) }
    await collection.awaitPersistence()
    #expect(collection.persistenceState == .saved)
    #expect(collection.tombstones.last?.kind == .drawing)
    #expect(collection.tombstones.last?.affectedCandidateIDs.isEmpty == true)
    let restored = PortraitSketchCollection(store: .init(directoryURL: directory))
    await restored.load()
    let firstProjection = try await restored.librarySelection(photoID: first.photoID)
    let secondProjection = try await restored.librarySelection(photoID: second.photoID)
    #expect(firstProjection.drawings.map(\.identity) == [.init(candidateID: first.id, photoID: first.photoID)])
    #expect(secondProjection.drawings.isEmpty)
    #expect(LegacyPortraitPreferenceExportFixture(collection: restored).examples.map(\.id) == [keptLabel.id])
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
