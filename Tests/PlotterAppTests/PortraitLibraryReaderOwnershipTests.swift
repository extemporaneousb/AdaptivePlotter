@testable import PortraitArtists
@testable import PortraitLibrary
@testable import PortraitStudioUI
import Foundation
import Testing

@Suite("Library readers preserve the single writer", .serialized)
@MainActor
struct PortraitLibraryReaderOwnershipTests {
  private func root() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent("portrait-read-owner-" + UUID().uuidString) }

  private func expectStyle(_ styles: [PortraitSavedStyle], equals expected: PortraitSavedStyle) throws {
    #expect(styles.count == 1)
    let actual = try #require(styles.first)
    #expect(actual.id == expected.id)
    #expect(actual.name == expected.name)
    #expect(actual.recipe == expected.recipe)
    #expect(actual.createdAt == expected.createdAt)
  }

  @Test("Independent committed metadata and exact occurrence readers do not acquire or change the live writer")
  func independentReaders() async throws {
    let directory = root(); defer { try? FileManager.default.removeItem(at: directory) }
    let candidate = try portraitPersistenceCandidate(seed: 1101)
    let style = PortraitSavedStyle(id: UUID(), name: "Committed style", recipe: candidate.recipe, createdAt: Date(timeIntervalSince1970: 1))
    let owner = PortraitCandidateStore(directoryURL: directory)
    try await owner.save(snapshot: .init(entries: [.init(candidate: candidate, reasons: [.init(reason: .shortlisted)])], savedStyles: [style]))
    let db = try await owner.libraryDatabase()
    let before = try Data(contentsOf: db.url), changes = try db.scalar("SELECT total_changes()"), generation = try db.generation
    let reader = PortraitCandidateStore(directoryURL: directory)
    try expectStyle(try await reader.loadSavedStyles(), equals: style)
    #expect(try await reader.librarySnapshot().photos.map(\.id) == [candidate.photoID])
    #expect(await reader.assetBytesVerified == 0)
    #expect(await reader.recordBytesEncoded == 0)
    let identity = PortraitDrawingIdentity(candidateID: candidate.id, photoID: candidate.photoID)
    #expect(try await reader.librarySelection(drawingIdentity: identity).program == candidate.program)
    #expect(try await reader.loadDrawing(identity).portraitCandidate == candidate)
    #expect(try await reader.loadRetainedOccurrence(identity).candidate == candidate)
    #expect(try Data(contentsOf: db.url) == before)
    #expect(try db.scalar("SELECT total_changes()") == changes)
    #expect(try db.generation == generation)
    #expect(throws: (any Error).self) { _ = try PortraitLibraryDatabase(url: db.url) }
    try db.transaction { try db.execute("UPDATE drawing SET deleted=1 WHERE id=?", [identity.id]); try db.bumpRevision() }
    await #expect(throws: (any Error).self) { _ = try await reader.loadDrawing(identity) }
  }

  @Test("Saved styles refuse existing invalid SQL without an Exchange marker or legacy fallback")
  func invalidSQLStylesRefuse() async throws {
    let directory = root(); defer { try? FileManager.default.removeItem(at: directory) }
    let candidate = try portraitPersistenceCandidate(seed: 1102)
    let owner = PortraitCandidateStore(directoryURL: directory)
    try await owner.save(snapshot: .init(entries: [.init(candidate: candidate, reasons: [])]))
    await owner.closeLibrary()
    let sql = directory.appendingPathComponent("library-v1.sqlite")
    let corrupt = Data("not SQLite".utf8)
    let style = PortraitSavedStyle(id: UUID(), name: "Fallback must not be selected", recipe: candidate.recipe, createdAt: Date(timeIntervalSince1970: 1))
    let styles = try JSONSerialization.jsonObject(with: PortraitCandidateCoding.encoder().encode([style]))
    let payload = try JSONSerialization.data(withJSONObject: ["schemaVersion": 1, "entries": [], "savedStyles": styles], options: [.sortedKeys])
    let legacy = try JSONSerialization.data(withJSONObject: ["schemaVersion": 1,
      "sha256": PortraitCandidateCoding.digest(payload), "payload": payload.base64EncodedString()], options: [.sortedKeys])
    try FileManager.default.removeItem(at: sql)
    try legacy.write(to: directory.appendingPathComponent("index-v1.json"))
    let reader = PortraitCandidateStore(directoryURL: directory)
    try expectStyle(try await reader.loadSavedStyles(), equals: style)
    #expect(!FileManager.default.fileExists(atPath: sql.path))
    try corrupt.write(to: sql)
    await #expect(throws: (any Error).self) { _ = try await reader.loadSavedStyles() }
    #expect(try Data(contentsOf: sql) == corrupt)
    #expect(try Data(contentsOf: directory.appendingPathComponent("index-v1.json")) == legacy)
  }

  @Test("Actual readonly snapshot connection refuses real atomic restore and the fresh reader selects the exact backup")
  func restoredReaderIdentity() async throws {
    let directory = root(); defer { try? FileManager.default.removeItem(at: directory) }
    let candidate = try portraitPersistenceCandidate(seed: 1103)
    let style = PortraitSavedStyle(id: UUID(), name: "Backup style", recipe: candidate.recipe, createdAt: Date(timeIntervalSince1970: 1))
    let owner = PortraitCandidateStore(directoryURL: directory)
    try await owner.save(snapshot: .init(entries: [.init(candidate: candidate, reasons: [])], savedStyles: [style]))
    let backup = try await owner.createExchangeMetadataBackup()
    try await owner.save(snapshot: .init(entries: [.init(candidate: candidate, reasons: [])], savedStyles: []))
    let reader = PortraitCandidateStore(directoryURL: directory)
    let displaced = try await reader.libraryReadDatabase()
    await owner.closeLibrary()
    try PortraitExchangeCatalog.restore(root: directory, generationID: backup.generationID)
    await #expect(throws: (any Error).self) {
      _ = try await reader.readLibrarySnapshot(displaced) { try displaced.scalar("SELECT value FROM state WHERE key='styles'") }
    }
    try expectStyle(try await reader.loadSavedStyles(), equals: style)
    let identity = PortraitDrawingIdentity(candidateID: candidate.id, photoID: candidate.photoID)
    #expect(try await reader.loadDrawing(identity).portraitCandidate == candidate)
  }

  @Test("First Exchange facade refuses prior same-file native SQL drift without refreshing stale expectations")
  func firstFacadeRejectsPriorDrift() async throws {
    let directory = root(); defer { try? FileManager.default.removeItem(at: directory) }
    let candidate = try portraitPersistenceCandidate(seed: 1105)
    let owner = PortraitCandidateStore(directoryURL: directory)
    let snapshot = PortraitCandidateArchive(entries: [.init(candidate: candidate, reasons: [])])
    try await owner.save(snapshot: snapshot)
    let db = try await owner.libraryDatabase()
    try db.transaction { try db.setState("styles", "[]"); try db.bumpRevision() }
    let bytes = try Data(contentsOf: db.url), generation = try db.generation
    await #expect(throws: (any Error).self) { _ = try await owner.exchangeCatalog() }
    #expect(try db.scalar("SELECT COUNT(*) FROM sqlite_master WHERE name LIKE 'dx_%'") == "0")
    #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent("exchange-authority.json").path))
    #expect(try Data(contentsOf: db.url) == bytes)
    #expect(try db.generation == generation)
    await #expect(throws: (any Error).self) { _ = try await owner.save(snapshot: snapshot) }
    #expect(try Data(contentsOf: db.url) == bytes)
  }

  @Test("Exact readers refuse changed selected record, source, raster and retained metadata bytes with SQL and live owner unchanged",
    arguments: ["record", "source", "raster", "metadata"])
  func selectedByteCorruption(kind: String) async throws {
    let directory = root(); defer { try? FileManager.default.removeItem(at: directory) }
    let candidate = try portraitPersistenceCandidate(seed: 1106)
    let owner = PortraitCandidateStore(directoryURL: directory)
    try await owner.save(snapshot: .init(entries: [.init(candidate: candidate, reasons: [.init(reason: .shortlisted)])]))
    let identity = PortraitDrawingIdentity(candidateID: candidate.id, photoID: candidate.photoID)
    let reader = PortraitCandidateStore(directoryURL: directory)
    #expect(try await reader.loadDrawing(identity).portraitCandidate == candidate)
    #expect(try await reader.loadRetainedOccurrence(identity).candidate == candidate)
    let db = try await owner.libraryDatabase()
    let row = try #require(db.rows("SELECT candidate_record,source_hash,raster_hash,metadata_record FROM drawing WHERE id=?", [identity.id]).first)
    let index = try #require(["record": 0, "source": 1, "raster": 2, "metadata": 3][kind])
    let hash = try #require(row[index])
    let path = directory.appendingPathComponent(kind == "record" || kind == "metadata" ? "records" : "assets").appendingPathComponent(hash)
    let original = try Data(contentsOf: path), sql = try Data(contentsOf: db.url)
    let changed = Data("Deliberately changed selected immutable bytes".utf8)
    try changed.write(to: path)
    func corruptRead(_ operation: () async throws -> Void) async {
      do { try await operation(); Issue.record("Changed selected bytes were accepted") }
      catch {
        guard let failure = error as? PortraitCandidateStoreError else { Issue.record("Wrong refusal cause: \(error)"); return }
        switch failure {
        case .invalidIndex(let reason): #expect((kind == "record" || kind == "metadata") && reason.contains("checksum"))
        case .invalidAsset(let actual): #expect((kind == "source" || kind == "raster") && actual == hash)
        default: Issue.record("Wrong selected-byte refusal: \(failure)")
        }
      }
    }
    if kind == "metadata" { #expect(try await reader.loadDrawing(identity).portraitCandidate == candidate) }
    else { await corruptRead { _ = try await reader.loadDrawing(identity) } }
    await corruptRead { _ = try await reader.loadRetainedOccurrence(identity) }
    #expect(try Data(contentsOf: db.url) == sql)
    #expect(try Data(contentsOf: path) == changed)
    #expect(try await reader.librarySnapshot().photos.map(\.id) == [candidate.photoID])
    try original.write(to: path)
    #expect(try await reader.loadRetainedOccurrence(identity).candidate == candidate)
    #expect(try Data(contentsOf: db.url) == sql)
  }

  @Test("Model shutdown drains its borrowed store; the actual external owner explicitly controls writer handoff")
  func borrowedShutdownAndHandoff() async throws {
    let directory = root(); defer { try? FileManager.default.removeItem(at: directory) }
    let candidate = try portraitPersistenceCandidate(seed: 1104)
    let owner = PortraitCandidateStore(directoryURL: directory)
    let model = PortraitStudioModel(candidateStore: owner)
    #expect(model.sketches.retain(candidate: candidate, reason: .shortlisted) == nil)
    await model.sketches.awaitPersistence()
    await model.shutdown()
    #expect(throws: (any Error).self) { _ = try PortraitLibraryDatabase(url: directory.appendingPathComponent("library-v1.sqlite")) }
    try await owner.save(snapshot: .init(entries: [.init(candidate: candidate, reasons: [.init(reason: .shortlisted)])]), mode: .mutationDelta)
    await owner.closeLibrary()
    let nextOwner = PortraitCandidateStore(directoryURL: directory)
    let reloaded = await nextOwner.load()
    #expect(reloaded.canWrite)
    #expect(reloaded.archive.entries.map(\.candidate) == [candidate])
  }
}
