import Foundation
import PlotterEpisodeRuntime
import PlotterModel
import PlotterRuntime
import PortraitCore
import Testing
@testable import PortraitArtists
@testable import PortraitLibrary
@testable import PlotterApp

@Suite("Durable drawing package library")
@MainActor
struct DrawingTransferLibraryTests {
  private func root() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("drawing-transfer-" + UUID().uuidString)
  }

  @Test("Imported package reopens intact, repeats without writing and never creates native photo rows")
  func durableRoundTrip() async throws {
    let directory = root(); defer { try? FileManager.default.removeItem(at: directory) }
    let package = try transferTestPackage(), bytes = try DrawingPackageCodec.encode(package)
    let store = PortraitCandidateStore(directoryURL: directory)
    let drawing = try await store.importDrawingPackage(bytes)
    #expect(drawing.transferOrigin == package.origin)
    #expect(drawing.sourcePhotoID == nil && drawing.portraitCandidate == nil)
    #expect(drawing.sourceImageData == package.source.bytes)
    #expect(drawing.program == package.program)
    let database = directory.appendingPathComponent("library-v1.sqlite")
    let before = try Data(contentsOf: database)
    #expect(try await store.importDrawingPackage(bytes) == drawing)
    #expect(try Data(contentsOf: database) == before)
    let reopened = PortraitCandidateStore(directoryURL: directory)
    #expect(try reopened.loadDrawing(drawing.id) == drawing)
    #expect(try await reopened.exportDrawingPackage(drawing) == bytes)
    try await reopened.validateDurableDrawing(drawing)
    let db = try PortraitLibraryDatabase(url: database, readOnly: true)
    #expect(try db.scalar("SELECT COUNT(*) FROM photo") == "0")
    #expect(try db.scalar("SELECT COUNT(*) FROM drawing") == "0")
    #expect(try db.scalar("SELECT COUNT(*) FROM generic_drawing") == "1")
    #expect(try db.scalar("PRAGMA user_version") == "2")
    #expect(try reopened.loadDrawingPage().drawings.first?.transferOrigin == package.origin)
  }

  @Test("Immutable-origin conflict and actual image metadata mismatch refuse before publication")
  func conflicts() async throws {
    let directory = root(); defer { try? FileManager.default.removeItem(at: directory) }
    let package = try transferTestPackage(), store = PortraitCandidateStore(directoryURL: directory)
    _ = try await store.importDrawingPackage(DrawingPackageCodec.encode(package))
    let changed = try DrawingPackage(origin: package.origin, program: package.program,
      createdAt: package.createdAt, title: "Changed claim", resultRecordJSON: package.resultRecordJSON,
      source: package.source, artistInput: package.artistInput, artist: package.artist, preview: package.preview)
    await #expect(throws: (any Error).self) {
      try await store.importDrawingPackage(DrawingPackageCodec.encode(changed))
    }
    let falseDimensions = DrawingPackageAsset(mediaType: package.source.mediaType,
      bytes: package.source.bytes, pixelWidth: 2, pixelHeight: 1)
    let corrupt = try DrawingPackage(origin: package.origin, program: package.program,
      createdAt: package.createdAt, title: package.title, resultRecordJSON: package.resultRecordJSON,
      source: falseDimensions, artistInput: package.artistInput, artist: package.artist, preview: package.preview)
    let untouched = root()
    defer { try? FileManager.default.removeItem(at: untouched) }
    await #expect(throws: (any Error).self) {
      try await PortraitCandidateStore(directoryURL: untouched).importDrawingPackage(DrawingPackageCodec.encode(corrupt))
    }
    #expect(!FileManager.default.fileExists(atPath: untouched.appendingPathComponent("library-v1.sqlite").path))
  }

  @Test("Deletion blocks delayed retention and exact user import restores without rewriting origin or dates")
  func deliberateRestore() async throws {
    let directory = root(); defer { try? FileManager.default.removeItem(at: directory) }
    let package = try transferTestPackage(), bytes = try DrawingPackageCodec.encode(package)
    let store = PortraitCandidateStore(directoryURL: directory)
    let drawing = try await store.importDrawingPackage(bytes)
    let deletion = PortraitArchiveTombstone(id: UUID(), kind: .candidate, identity: drawing.id,
      affectedCandidateIDs: [drawing.id], assetSHA256s: [], createdAt: Date())
    try await store.save(snapshot: .init(tombstones: [deletion]))
    await #expect(throws: (any Error).self) { try await store.importDrawingPackage(bytes) }
    await #expect(throws: (any Error).self) { try await store.ensureRetainedTransferredDrawing(drawing) }
    let restored = try await store.importDrawingPackage(bytes, restoreDeleted: true)
    #expect(restored == drawing)
    #expect(try await store.exportDrawingPackage(restored) == bytes)
    let broad = PortraitArchiveTombstone(id: UUID(), kind: .source, identity: package.source.sha256,
      affectedCandidateIDs: [], assetSHA256s: [], createdAt: Date())
    try await store.save(snapshot: .init(tombstones: [broad]))
    await #expect(throws: (any Error).self) { try await store.importDrawingPackage(bytes, restoreDeleted: true) }
  }

  @Test("Repeat import refuses damaged live records and unexplained absence without repair", arguments: ["record", "reference", "row"])
  func damagedRetainedDrawingRefusesRepair(damage: String) async throws {
    let directory = root(); defer { try? FileManager.default.removeItem(at: directory) }
    let bytes = try DrawingPackageCodec.encode(transferTestPackage())
    let drawing = try await PortraitCandidateStore(directoryURL: directory).importDrawingPackage(bytes)
    let database = directory.appendingPathComponent("library-v1.sqlite")
    let db = try PortraitLibraryDatabase(url: database)
    let value = try db.scalar("SELECT reference FROM generic_drawing WHERE id=?", [drawing.id])
    let encoded = try #require(value)
    let reference = try db.decode(SavedDrawingRecordReference.self, encoded)
    let hash = try #require(reference.recordSHA256)
    let recordURL = directory.appendingPathComponent("records").appendingPathComponent(hash)
    if damage == "record" { try FileManager.default.removeItem(at: recordURL) }
    else if damage == "reference" {
      try db.execute("UPDATE generic_drawing SET reference=? WHERE id=?", ["{malformed", drawing.id])
    } else { try db.execute("DELETE FROM generic_drawing WHERE id=?", [drawing.id]) }
    let before = try Data(contentsOf: database)
    let recordExisted = FileManager.default.fileExists(atPath: recordURL.path)
    let reopened = PortraitCandidateStore(directoryURL: directory)
    await #expect(throws: (any Error).self) { try await reopened.importDrawingPackage(bytes, restoreDeleted: true) }
    #expect(try Data(contentsOf: database) == before)
    #expect(FileManager.default.fileExists(atPath: recordURL.path) == recordExisted)
    #expect(try db.scalar("SELECT reference FROM generic_drawing WHERE id=?", [drawing.id])
      == (damage == "row" ? nil : damage == "reference" ? "{malformed" : encoded))
  }

  @Test("Terminal imports are immutable, can remain unlinked and never resurrect a deleted drawing")
  func terminalAttachment() async throws {
    let directory = root(); defer { try? FileManager.default.removeItem(at: directory) }
    let package = try transferTestPackage()
    let rawURL = directory.appendingPathComponent("raw.json")
    let exported = try await terminalExport(package, rawURL: rawURL)
    let attachment = try PortraitPlotAttachmentInspection.attachment(exported)
    let bytes = try PlotAttachmentCodec.encode(attachment)
    let rawBytes = try Data(contentsOf: rawURL)
    let store = PortraitCandidateStore(directoryURL: directory.appendingPathComponent("studio"))
    let unknown = try await store.importPlotAttachment(bytes)
    #expect(unknown.linkedDrawingID == nil)
    #expect(try await store.importPlotAttachment(bytes).disposition == .alreadyPresent)
    #expect(try await store.loadPlotAttachment(attachment.id) == attachment)
    let drawing = try await store.importDrawingPackage(DrawingPackageCodec.encode(package))
    #expect(try await store.plotAttachments(for: package.origin).first?.linkedDrawingID == drawing.id)
    #expect(try Data(contentsOf: rawURL) == rawBytes)
    let deletion = PortraitArchiveTombstone(id: UUID(), kind: .candidate, identity: drawing.id,
      affectedCandidateIDs: [drawing.id], assetSHA256s: [], createdAt: Date())
    try await store.save(snapshot: .init(tombstones: [deletion]))
    #expect(try await store.importPlotAttachment(bytes).linkedDrawingID == nil)
    #expect(try store.loadDrawingPage().drawings.isEmpty)
    var recordObject = try #require(JSONSerialization.jsonObject(with: attachment.recordJSON) as? [String: Any])
    // Same valid terminal identity, different immutable recording timestamp.
    var timestamp = try #require(recordObject["recordedAt"] as? [String: Any])
    timestamp["monotonicNanoseconds"] = 500
    recordObject["recordedAt"] = timestamp
    let changedRecord = try JSONSerialization.data(withJSONObject: recordObject, options: [.sortedKeys])
    let changed = try PlotAttachment(origin: attachment.origin, producerArchiveID: attachment.producerArchiveID,
      runID: attachment.runID, recordID: attachment.recordID, recordJSON: changedRecord, media: attachment.media)
    _ = try PortraitPlotAttachmentInspection.record(changed)
    await #expect(throws: (any Error).self) { try await store.importPlotAttachment(PlotAttachmentCodec.encode(changed)) }
  }

  @Test("Transferred raw run never falls through equal native source and program ancestry")
  func nativeLineageIsolation() async throws {
    let directory = root(); defer { try? FileManager.default.removeItem(at: directory) }
    let base = try transferTestPackage(), candidateBase = try portraitPersistenceCandidate()
    let program = try DrawingProgram(id: base.program.id, fieldExtent: base.program.fieldExtent,
      strokes: base.program.strokes, source: .init(kind: "portrait",
        sourceIdentifier: "portrait-v3|image=" + base.source.sha256 + "|pose=front"))
    let native = try PortraitCandidate(sourceData: base.source.bytes, sourcePixelExtent: candidateBase.sourcePixelExtent,
      raster: candidateBase.raster, recipe: candidateBase.recipe, program: program,
      photoID: UUID(), captureSessionID: UUID(), pose: .front)
    let package = try transferTestPackage(programOverride: program)
    let rawURL = directory.appendingPathComponent("raw.json")
    _ = try await terminalExport(package, rawURL: rawURL)
    let raw = DrawingRunEvidenceStore(fileURL: rawURL)
    guard case .loaded(let archive) = await raw.load() else { Issue.record("raw fixture unavailable"); return }
    let store = PortraitCandidateStore(directoryURL: directory.appendingPathComponent("library"))
    try await store.save(snapshot: .init(entries: [.init(candidate: native, reasons: [])]))
    try await store.reconcileEvidence(archive: archive)
    let db = try PortraitLibraryDatabase(url: directory.appendingPathComponent("library/library-v1.sqlite"), readOnly: true)
    #expect(try db.scalar("SELECT COUNT(*) FROM photo") == "1")
    #expect(try db.scalar("SELECT COUNT(*) FROM drawing") == "1")
    #expect(try db.scalar("SELECT COUNT(*) FROM work") == "0")
    #expect(try db.scalar("SELECT COUNT(*) FROM quarantine") == "0")
  }

  @Test("Plot metadata pages are bounded, complete, origin-filtered and independent of media payload reads")
  func boundedAttachmentPages() async throws {
    let directory = root(); defer { try? FileManager.default.removeItem(at: directory) }
    let store = PortraitCandidateStore(directoryURL: directory.appendingPathComponent("library"))
    let package = try transferTestPackage(), other = try transferTestPackage()
    var expected: Set<String> = [], matching: Set<String> = []
    for (index, source) in [package, other, package].enumerated() {
      let exported = try await terminalExport(source, rawURL: directory.appendingPathComponent("raw-\(index).json"))
      let attachment = try PortraitPlotAttachmentInspection.attachment(exported)
      let bytes = try PlotAttachmentCodec.encode(attachment)
      _ = try await store.importPlotAttachment(bytes)
      expected.insert(attachment.id)
      if source.origin == package.origin { matching.insert(attachment.id) }
      // Metadata pages must not read pixels or the unselected exact payload.
      let payload = directory.appendingPathComponent("library/transfers")
        .appendingPathComponent(DrawingPackageCodec.sha256(bytes) + ".json")
      try FileManager.default.removeItem(at: payload)
    }
    var cursor: PlotAttachmentPageCursor?, seen: [String] = []
    repeat {
      let page = try await store.plotAttachmentPage(after: cursor, limit: 1)
      #expect(page.attachments.count <= 1)
      seen += page.attachments.map(\.id); cursor = page.next
    } while cursor != nil
    #expect(seen.count == expected.count && Set(seen) == expected)
    cursor = nil; seen = []
    repeat {
      let page = try await store.plotAttachmentPage(after: cursor, limit: 1, for: package.origin)
      #expect(page.attachments.allSatisfy { $0.origin == package.origin })
      seen += page.attachments.map(\.id); cursor = page.next
    } while cursor != nil
    #expect(seen.count == matching.count && Set(seen) == matching)
  }

  private func terminalExport(_ package: DrawingPackage, rawURL: URL) async throws -> DrawingRunTerminalExport {
    let fixture = try await DrawingRunEpisodeFixtureCache.load()
    let built = PlotterDrawingPlanningAdapter.buildDraft(program: package.program, machineCenter: nil,
      uniformScale: 0.02, rotationDegrees: 0, drawableRegion: fixture.drawableRegion, registration: fixture.registration)
    let plan = try #require(built.plan)
    let drawing = try SavedDrawing(package: package)
    let context = try DrawingRunAttemptContext(program: package.program, registration: fixture.registration,
      drawingFeedMMPerMinute: PlotterMotionThroughput.applicationXYFeedMMPerMinute,
      penActuationProfile: .initialDefaults, paper: fixture.paper, candidate: drawing.runCandidateReference)
    let intent = try DrawingRunIntent(runID: RunID(), requestID: UUID(), plan: plan,
      placementID: UUID(), role: .ordinaryDrawing, context: context,
      recordedAt: RuntimeTimestamp(monotonicNanoseconds: 100))
    let record = try DrawingRunEvidenceRecord(runID: intent.runID, requestID: intent.requestID,
      role: intent.role, evidenceDisposition: .cancelled, requestFrontier: .admitted,
      executionFrontiers: DrawingRunExecutionFrontiers(plannedStrokeCount: UInt32(plan.strokes.count),
        commandedStrokeCount: 0, controllerCompletedStrokeCount: 0, inkVerifiedStrokeCount: 0),
      executionDisposition: .cancelled(reason: "Stopped before motion"),
      program: DrawingProgramEvidenceReference(program: package.program),
      placement: DrawingPlacementEvidenceReference(placementID: intent.placementID, placement: plan.placement),
      plan: DrawingExecutionPlanEvidenceReference(plan: plan), planningProvenance: plan.provenance,
      tipCalibration: DrawingTipCalibrationEvidenceReference(acceptedRevisionID: fixture.registration.acceptedRevisionID,
        registrationEvidenceSHA256: DrawingMaterialApplicability.registrationHash(fixture.registration),
        applicability: fixture.registration.applicability, estimatorRevision: fixture.registration.estimatorRevision),
      paper: fixture.paper, observation: .notAttempted(.executionCancelledBeforeObservation),
      recordedAt: RuntimeTimestamp(monotonicNanoseconds: 200),
      attemptEvidence: DrawingRunAttemptEvidence(intent: intent, baselines: [], terminalFrames: [],
        missingCoverageReason: "Stopped before motion"))
    let raw = DrawingRunEvidenceStore(fileURL: rawURL)
    _ = try await raw.stageIntent(intent); _ = try await raw.append(record)
    return try await raw.exportTerminalRecord(runID: intent.runID)
  }
}
