@testable import PortraitArtists
@testable import PortraitLibrary
@testable import PortraitStudioUI
import Foundation
import PlotterEpisodeRuntime
import PlotterModel
import PlotterUI
import Testing
@testable import PlotterApp
@testable import PlotterRuntime

@Suite("Portrait library ancestry at application boundaries", .serialized)
@MainActor
struct PortraitLineageIntegrationTests {
  @Test("portrait provenance cannot become a generic saved drawing; generic vector drawing remains supported")
  func authoredProvenanceGate() throws {
    let candidate = try portraitPersistenceCandidate(seed: 912)
    #expect(SavedDrawing.authored(program: candidate.program, projectedDrawing: nil,
      executionProgram: candidate.program) == nil)
    #expect(throws: SavedDrawingBrowserError.portraitProvenanceRequired) {
      try SavedDrawing(program: candidate.program).validateIntegrity()
    }
    #expect(SavedDrawing.authored(program: candidate.program,
      projectedDrawing: SavedDrawing(candidate: candidate), executionProgram: candidate.program)?.sourcePhotoID == candidate.photoID)
    let program = try DrawingProgramCatalog.program(for: .square, style: portraitTestStyle())
    let drawing = try #require(SavedDrawing.authored(program: program, projectedDrawing: nil, executionProgram: program))
    try drawing.validateIntegrity()
    #expect(drawing.portraitCandidate == nil)
  }

  @Test("an ordinary portrait without provenance durably refuses before Pen Up or plan dispatch")
  func missingProvenanceRefusesBeforeMotion() async throws {
    let fixture = try await DrawingWorkbenchApplicationFixture.make()
    defer { fixture.stores.remove() }
    let app = fixture.application
    do {
      let program = try PortraitVectorizer.program(from: portraitTestRaster(), pose: .front,
        style: .contours, strokeStyle: app.drawingStrokeStyle)
      let projection = app.plotterUIProjection(selectedItemID: app.testCurrentLearningPathItemID,
        manualDraft: ManualMotionDraft(), includesLearningPath: true, pendingDrawingProgram: program)
      let select = try #require(projection.semantic.request(matching: .drawingDraft(.selectProgram(program))))
      #expect(await app.submitPlotterUIRequest(select) == .accepted(requestID: select.id))
      try await fixture.submit(.fitInDrawableRegion)
      try await fixture.submit(.assertPaperCoverage)
      try await waitUntil { app.drawingRunSnapshot?.readiness == .ready }
      let penCommands = await fixture.machine.requestedPenCommands
      let request = try #require(app.testPlotterUIProjection().semantic.request(matching: .drawingRun(.start)))
      _ = await app.submitPlotterUIRequest(request)
      let terminal = try #require(app.drawingRunSnapshot?.terminal)
      #expect(terminal.disposition == .refused)
      #expect(await fixture.machine.requestedPenCommands == penCommands)
      #expect(await fixture.planGate.request == nil)
      guard case .loaded(let raw) = await fixture.stores.evidenceStore.load() else {
        Issue.record("Refused attempt was not durably preserved"); await app.shutdown(); return
      }
      #expect(raw.records.contains { $0.recordID == terminal.record.recordID })
      #expect(raw.attempts.first { $0.intent.runID == terminal.runID }?.inkDispatchPossible == false)
      await app.shutdown()
    } catch { await app.shutdown(); throw error }
  }

  @Test("equal-content capture occurrences survive actual save, handoff, pre-motion binding, deletion and reopen")
  func equalContentCaptureOccurrences() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let studio = PortraitStudioModel(candidateStore: .init(directoryURL: directory))
    let fixture = try await DrawingWorkbenchApplicationFixture.make(portraitStudio: studio)
    defer { fixture.stores.remove() }
    let app = fixture.application
    do {
      let first = try portraitPersistenceCandidate(seed: 913)
      let second = try PortraitCandidate(sourceData: first.sourceData, sourcePixelExtent: first.sourcePixelExtent,
        raster: first.raster, recipe: first.recipe, program: first.program, photoID: UUID(),
        captureSessionID: UUID(), createdAt: first.createdAt.addingTimeInterval(0.01),
        lineage: first.lineage, checkpointID: first.checkpointID, pose: first.pose,
        proposal: first.proposal, warpManifest: first.warpManifest)
      #expect(first.id == second.id && first.photoID != second.photoID)
      var stagedIntents: [UUID: DrawingRunIntent] = [:]
      for candidate in [first, second] {
        studio.sketches.retainSourcePhoto(.init(id: candidate.photoID, data: candidate.sourceData,
          label: "Independent capture", capturedAt: candidate.createdAt, frameID: nil,
          captureNanoseconds: nil, pose: .front, sourcePixelExtent: candidate.sourcePixelExtent,
          captureSessionID: candidate.captureSessionID))
        let priorPlacement = app.drawingDraftSnapshot.artworkPlan?.placement
        let priorPlanHash = app.drawingDraftSnapshot.plan?.contentHash
        let preservesAuthoredArtwork = app.drawingDraftSnapshot.authoredProgram == candidate.program
          && app.drawingDraftSnapshot.artworkPlan?.sourceProgramContentHash == candidate.program.contentHash
        if candidate.photoID == second.photoID { #expect(preservesAuthoredArtwork) }
        let projectionFailure = await app.projectPortrait(candidate)
        try #require(projectionFailure == nil,
          "Handoff failed: \(projectionFailure ?? "unknown"); persistence: \(studio.sketches.persistenceState); issues: \(studio.sketches.persistenceIssues); library: \(studio.sketches.libraryState)")
        #expect(studio.projectedDrawing?.sourcePhotoID == candidate.photoID)
        #expect(app.drawingDraftSnapshot.authoredProgram == candidate.program)
        if preservesAuthoredArtwork {
          let priorPlacement = try #require(priorPlacement)
          #expect(app.drawingDraftSnapshot.artworkPlan?.placement == priorPlacement)
          #expect(app.drawingDraftSnapshot.plan?.contentHash == priorPlanHash)
        }
        try await fixture.submit(.assertPaperCoverage)
        let intent = try await makeIntent(app)
        stagedIntents[candidate.photoID] = intent
        _ = try await fixture.stores.evidencePort.stageIntent(intent)
        try await app.retainDrawingCandidateForAttempt(intent)
        await studio.sketches.awaitLibrarySynchronization()
        let selection = try await studio.sketches.librarySelection(workID: intent.runID.description)
        #expect(selection.photo.id == candidate.photoID)
      }
      await studio.sketches.awaitLibrarySynchronization()
      let before = try await studio.sketches.librarySnapshot()
      #expect(Set(before.photos.map(\.id)) == Set([first.photoID, second.photoID]))
      let firstIdentity = PortraitDrawingIdentity(candidateID: first.id, photoID: first.photoID)
      let secondIdentity = PortraitDrawingIdentity(candidateID: second.id, photoID: second.photoID)
      #expect(try await studio.sketches.drawingForBrowsing(firstIdentity).sourcePhotoID == first.photoID)
      #expect(try await studio.sketches.drawingForBrowsing(secondIdentity).sourcePhotoID == second.photoID)
      // Identical reauthoring after drawing deletion preserves the capture,
      // retires its prior library work and binds the new immutable record.
      let priorSecondIntent = try #require(stagedIntents[second.photoID])
      studio.sketches.deleteDrawing(secondIdentity)
      await studio.sketches.awaitPersistence()
      let freshSecond = try PortraitCandidate(sourceData: second.sourceData, sourcePixelExtent: second.sourcePixelExtent,
        raster: second.raster, recipe: second.recipe, program: second.program, photoID: second.photoID,
        captureSessionID: second.captureSessionID, createdAt: Date().addingTimeInterval(0.01),
        lineage: second.lineage, checkpointID: second.checkpointID, pose: second.pose,
        proposal: second.proposal, warpManifest: second.warpManifest)
      let reauthoringFailure = await app.projectPortrait(freshSecond)
      try #require(reauthoringFailure == nil, "Reauthoring handoff failed: \(reauthoringFailure ?? "unknown")")
      var staleHandoffCalled = false
      #expect(await studio.acceptProjection(second, perform: { staleHandoffCalled = true; return nil }) != nil)
      #expect(!staleHandoffCalled)
      try await fixture.submit(.assertPaperCoverage)
      let newIntent = try await makeIntent(app)
      _ = try await fixture.stores.evidencePort.stageIntent(newIntent)
      try await app.retainDrawingCandidateForAttempt(newIntent)
      await studio.sketches.awaitLibrarySynchronization()
      await #expect(throws: (any Error).self) { try await app.retainDrawingCandidateForAttempt(priorSecondIntent) }
      studio.deleteRetainedSource(first.photoID, strokeStyle: app.drawingStrokeStyle)
      await studio.sketches.awaitPersistence()
      #expect(studio.projectedDrawing?.sourcePhotoID == second.photoID)
      await app.shutdown()
      let restarted = PortraitSketchCollection(store: .init(directoryURL: directory,
        evidenceArchiveURL: fixture.stores.evidencePort.archiveURL))
      let after = try await restarted.librarySnapshot()
      #expect(after.photos.map(\.id) == [second.photoID])
      #expect(try await restarted.drawingForBrowsing(secondIdentity).sourcePhotoID == second.photoID)
      #expect(try await restarted.drawingForBrowsing(secondIdentity).createdAt == freshSecond.createdAt)
      guard case .loaded(let raw) = await fixture.stores.evidenceStore.load() else {
        Issue.record("Raw ancestry was lost during reauthoring"); return
      }
      await restarted.reconcileDrawingEvidence(raw, sourceURL: fixture.stores.evidencePort.archiveURL)
      let selected = try await restarted.librarySelection(photoID: second.photoID)
      #expect(selected.works.contains { $0.runID == newIntent.runID })
      #expect(!selected.works.contains { $0.runID == priorSecondIntent.runID })
      await #expect(throws: (any Error).self) { try await restarted.drawingForBrowsing(firstIdentity) }
    } catch { await app.shutdown(); throw error }
  }

  @Test("an already visible identical target cannot change capture handoff during an active run")
  func visibleTargetKeepsActiveCapture() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let studio = PortraitStudioModel(candidateStore: .init(directoryURL: directory))
    let fixture = try await DrawingWorkbenchApplicationFixture.make(portraitStudio: studio)
    defer { fixture.stores.remove() }
    let app = fixture.application
    do {
      let first = try portraitPersistenceCandidate(seed: 990)
      let second = try PortraitCandidate(sourceData: first.sourceData, sourcePixelExtent: first.sourcePixelExtent,
        raster: first.raster, recipe: first.recipe, program: first.program, photoID: UUID(),
        captureSessionID: UUID(), createdAt: first.createdAt, lineage: first.lineage,
        checkpointID: first.checkpointID, pose: first.pose, proposal: first.proposal,
        warpManifest: first.warpManifest)
      #expect(await app.projectPortrait(first) == nil)
      try await fixture.submit(.assertPaperCoverage)
      try await waitUntil { app.drawingRunSnapshot?.readiness == .ready }
      let start = try #require(app.testPlotterUIProjection().semantic.request(matching: .drawingRun(.start)))
      let running = Task { await app.submitPlotterUIRequest(start) }
      do { try await waitUntilAsync { await fixture.planGate.request != nil } }
      catch { await fixture.planGate.release(.cancelled); _ = await running.value; throw error }
      let placement = app.drawingDraftSnapshot.artworkPlan?.placement
      let plan = app.drawingDraftSnapshot.plan
      #expect(app.drawingDraftSnapshot.isTargetVisible)
      #expect(await app.projectPortrait(second) != nil)
      #expect(studio.projectedDrawing?.sourcePhotoID == first.photoID)
      #expect(app.drawingDraftSnapshot.artworkPlan?.placement == placement)
      #expect(app.drawingDraftSnapshot.plan == plan)
      await fixture.planGate.release(.cancelled)
      _ = await running.value
      let terminal = try #require(app.drawingRunSnapshot?.terminal)
      await app.shutdown()
      let restarted = PortraitSketchCollection(store: .init(directoryURL: directory,
        evidenceArchiveURL: fixture.stores.evidencePort.archiveURL))
      let selection = try await restarted.librarySelection(workID: terminal.runID.description)
      #expect(selection.photo.id == first.photoID)
    } catch { await fixture.planGate.release(.cancelled); await app.shutdown(); throw error }
  }

  @Test("a failed catalog synchronization preserves the successful raw intent commit and marks browsing unavailable")
  func catalogFailureDoesNotFailRawPublication() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let blocked = directory.appendingPathComponent("blocked-portrait-store")
    try Data([1]).write(to: blocked)
    let studio = PortraitStudioModel(candidateStore: .init(directoryURL: blocked))
    let fixture = try await DrawingWorkbenchApplicationFixture.make(portraitStudio: studio)
    defer { fixture.stores.remove() }
    let app = fixture.application
    do {
      try await fixture.submit(.fitInDrawableRegion)
      try await fixture.submit(.assertPaperCoverage)
      let intent = try await makeIntent(app)
      let committed = try await fixture.stores.evidencePort.stageIntent(intent)
      #expect(committed.attempts.contains { $0.intent == intent })
      await studio.sketches.awaitLibrarySynchronization()
      guard case .loaded(let reopened) = await fixture.stores.evidenceStore.load() else {
        Issue.record("Catalog failure erased raw DrawingEvidence"); await app.shutdown(); return
      }
      #expect(reopened.attempts.contains { $0.intent == intent })
      guard case .failed = studio.sketches.libraryState else {
        Issue.record("Failed synchronization was presented as current"); await app.shutdown(); return
      }
      await #expect(throws: (any Error).self) { try await studio.sketches.librarySnapshot() }
      #expect(await fixture.planGate.request == nil)
      await app.shutdown()
    } catch { await app.shutdown(); throw error }
  }

  @Test("actual current pre-motion binding uses its stage receipt without decoding a corrupted historical raw component")
  func currentBindingDoesNotDecodeHistoricalRawComponent() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let studio = PortraitStudioModel(candidateStore: .init(directoryURL: directory))
    let fixture = try await DrawingWorkbenchApplicationFixture.make(portraitStudio: studio)
    defer { fixture.stores.remove() }
    let app = fixture.application
    do {
      let candidate = try portraitPersistenceCandidate(seed: 998)
      #expect(await app.projectPortrait(candidate) == nil)
      try await fixture.submit(.assertPaperCoverage)
      await studio.sketches.awaitLibrarySynchronization()
      // Add a historical component through the raw owner, after its catalog
      // startup verification, so the catalog has never decoded this leaf.
      let historical = try await CompleteAcceptedLearningFixture.make()
      _ = try await fixture.stores.evidenceStore.append(historical.borderRecord)
      let intent = try await makeIntent(app)
      let archive = try await fixture.stores.evidencePort.stageIntent(intent)
      #expect(studio.sketches.libraryState == .loading)
      let rawURL = fixture.stores.evidencePort.archiveURL
      let selected = try PortraitEvidenceSource.componentHashes(rawURL)
      let historicalHash = try #require(selected.records[historical.borderRecord.recordID.rawValue])
      let historicalFile = rawURL.deletingLastPathComponent()
        .appendingPathComponent(rawURL.lastPathComponent + ".records")
        .appendingPathComponent(historicalHash + ".json")
      let manifest = try Data(contentsOf: rawURL)
      try Data([0xff]).write(to: historicalFile, options: .atomic)
      let loadCount = await fixture.stores.evidencePort.loadCount
      let commands = await fixture.machine.requestedPenCommands
      try await app.retainDrawingCandidateForAttempt(intent)
      #expect(await fixture.stores.evidencePort.loadCount == loadCount)
      #expect(await fixture.machine.requestedPenCommands == commands)
      #expect(await fixture.planGate.request == nil)
      #expect(try Data(contentsOf: rawURL) == manifest)
      let db = try PortraitLibraryDatabase(url: directory.appendingPathComponent("library-v1.sqlite"), readOnly: true)
      #expect(try db.scalar("SELECT drawing_id FROM run_binding WHERE run_id=?", [intent.runID.description])
        == PortraitDrawingIdentity(candidateID: candidate.id, photoID: candidate.photoID).id)
      await studio.sketches.awaitLibrarySynchronization()
      guard case .failed = studio.sketches.libraryState else { Issue.record("Historical component damage was hidden by full projection"); await app.shutdown(); return }
      await #expect(throws: (any Error).self) { try await studio.sketches.librarySnapshot() }
      let verifier = PortraitCandidateStore(directoryURL: directory, evidenceArchiveURL: rawURL)
      await #expect(throws: (any Error).self) { try await verifier.reconcileEvidence(archive: archive, sourceURL: rawURL) }
      await app.shutdown()
    } catch { await app.shutdown(); throw error }
  }

  @Test("deleting a staged capture before binding cannot reassign its unbound run to an equal-ID surviving capture")
  func stagedCaptureDeletionCannotReassignRun() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let studio = PortraitStudioModel(candidateStore: .init(directoryURL: directory))
    let fixture = try await DrawingWorkbenchApplicationFixture.make(portraitStudio: studio)
    defer { fixture.stores.remove() }
    let app = fixture.application
    do {
      let first = try portraitPersistenceCandidate(seed: 1002)
      let surviving = try PortraitCandidate(sourceData: first.sourceData, sourcePixelExtent: first.sourcePixelExtent,
        raster: first.raster, recipe: first.recipe, program: first.program, photoID: UUID(),
        captureSessionID: UUID(), createdAt: first.createdAt.addingTimeInterval(0.01),
        lineage: first.lineage, checkpointID: first.checkpointID, pose: first.pose,
        proposal: first.proposal, warpManifest: first.warpManifest)
      #expect(first.id == surviving.id && first.photoID != surviving.photoID)
      #expect(await app.projectPortrait(surviving) == nil)
      try await fixture.submit(.assertPaperCoverage)
      let survivingIntent = try await makeIntent(app)
      _ = try await fixture.stores.evidencePort.stageIntent(survivingIntent)
      try await app.retainDrawingCandidateForAttempt(survivingIntent)
      await studio.sketches.awaitLibrarySynchronization()
      #expect(try await studio.sketches.librarySelection(workID: survivingIntent.runID.description).photo.id == surviving.photoID)
      #expect(await app.projectPortrait(first) == nil)
      try await fixture.submit(.assertPaperCoverage)
      let deletedIntent = try await makeIntent(app)
      _ = try await fixture.stores.evidencePort.stageIntent(deletedIntent)
      let rawURL = fixture.stores.evidencePort.archiveURL
      let manifest = try Data(contentsOf: rawURL)
      let commands = await fixture.machine.requestedPenCommands
      studio.sketches.deleteSource(photoID: first.photoID)
      await studio.sketches.awaitPersistence()
      #expect(studio.sketches.persistenceState == .saved)
      await #expect(throws: (any Error).self) { try await app.retainDrawingCandidateForAttempt(deletedIntent) }
      await studio.sketches.awaitLibrarySynchronization()
      #expect(studio.sketches.libraryState == .saved)
      #expect(await fixture.machine.requestedPenCommands == commands)
      #expect(await fixture.planGate.request == nil)
      #expect(try Data(contentsOf: rawURL) == manifest)
      guard case .loaded(let raw) = await fixture.stores.evidenceStore.load() else {
        Issue.record("Capture deletion changed the retained raw safety archive"); await app.shutdown(); return
      }
      #expect(raw.attempts.contains { $0.intent == deletedIntent && !$0.inkDispatchPossible })
      let db = try PortraitLibraryDatabase(url: directory.appendingPathComponent("library-v1.sqlite"), readOnly: true)
      #expect(try db.scalar("SELECT COUNT(*) FROM run_binding WHERE run_id=?", [deletedIntent.runID.description]) == "0")
      #expect(try db.scalar("SELECT COUNT(*) FROM work WHERE run_id=? AND deleted=0", [deletedIntent.runID.description]) == "0")
      #expect(try db.scalar("SELECT COUNT(*) FROM quarantine WHERE id=?", [deletedIntent.runID.description]) == "1")
      #expect(try db.scalar("SELECT drawing_id FROM run_binding WHERE run_id=?", [survivingIntent.runID.description])
        == PortraitDrawingIdentity(candidateID: surviving.id, photoID: surviving.photoID).id)
      let survivor = try await studio.sketches.librarySelection(photoID: surviving.photoID)
      #expect(survivor.drawings.map(\.identity) == [.init(candidateID: surviving.id, photoID: surviving.photoID)])
      #expect(survivor.works.map(\.runID) == [survivingIntent.runID])
      await #expect(throws: (any Error).self) { try await studio.sketches.librarySelection(workID: deletedIntent.runID.description) }
      await app.shutdown()
      let reopened = PortraitSketchCollection(store: .init(directoryURL: directory, evidenceArchiveURL: rawURL))
      await reopened.reconcileDrawingEvidence(raw, sourceURL: rawURL)
      #expect(reopened.libraryState == .saved)
      #expect(try await reopened.librarySnapshot().photos.map(\.id) == [surviving.photoID])
      #expect(try await reopened.librarySelection(workID: survivingIntent.runID.description).photo.id == surviving.photoID)
      #expect(try await reopened.drawingForBrowsing(.init(candidateID: surviving.id, photoID: surviving.photoID)).sourcePhotoID == surviving.photoID)
      await #expect(throws: (any Error).self) { try await reopened.librarySelection(workID: deletedIntent.runID.description) }
    } catch { await app.shutdown(); throw error }
  }

  @Test("refused and cancelled retention release the current stage publication and retain prepared history", arguments: [false, true])
  func unsuccessfulBindingReleasesPreparedHistory(cancelled: Bool) async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let studio = PortraitStudioModel(candidateStore: .init(directoryURL: directory))
    let fixture = try await DrawingWorkbenchApplicationFixture.make(portraitStudio: studio)
    defer { fixture.stores.remove() }
    let app = fixture.application
    do {
      let candidate = try portraitPersistenceCandidate(seed: 999)
      #expect(await app.projectPortrait(candidate) == nil)
      try await fixture.submit(.assertPaperCoverage)
      let intent = try await makeIntent(app)
      _ = try await fixture.stores.evidencePort.stageIntent(intent)
      #expect(studio.sketches.libraryState == .loading)
      if cancelled {
        let callback = Task {
          withUnsafeCurrentTask { $0?.cancel() }
          try await app.retainDrawingCandidateForAttempt(intent)
        }
        await #expect(throws: (any Error).self) { try await callback.value }
      } else {
        let generic = SavedDrawing(program: try DrawingProgramCatalog.program(for: .square, style: portraitTestStyle()))
        #expect(await app.projectSavedDrawing(generic) == nil)
        await #expect(throws: (any Error).self) { try await app.retainDrawingCandidateForAttempt(intent) }
      }
      await studio.sketches.awaitLibrarySynchronization()
      #expect(studio.sketches.libraryState == .saved)
      let selected = try await studio.sketches.librarySelection(photoID: candidate.photoID)
      #expect(selected.works.contains { $0.runID == intent.runID && !$0.executedOrPossibleInk })
      #expect(try await studio.sketches.librarySnapshot(filter: .plottedWorks).works.isEmpty)
      #expect(await fixture.planGate.request == nil)
      await app.shutdown()
    } catch { await app.shutdown(); throw error }
  }

  @Test("fresh and loaded ports publish idempotently recovered prepared intents without a new binding hold", arguments: [false, true])
  func recoveredPreparedStageDoesNotHoldPublication(loadFirst: Bool) async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let studio = PortraitStudioModel(candidateStore: .init(directoryURL: directory))
    let fixture = try await DrawingWorkbenchApplicationFixture.make(portraitStudio: studio)
    defer { fixture.stores.remove() }
    let app = fixture.application
    do {
      let candidate = try portraitPersistenceCandidate(seed: 1000)
      #expect(await app.projectPortrait(candidate) == nil)
      try await fixture.submit(.assertPaperCoverage)
      let intent = try await makeIntent(app)
      _ = try await fixture.stores.evidencePort.stageIntent(intent)
      try await app.retainDrawingCandidateForAttempt(intent)
      await studio.sketches.awaitLibrarySynchronization()
      let recovered = DrawingRunEvidencePort(store: fixture.stores.evidenceStore)
      await recovered.installPortraitLibrary(studio.sketches)
      if loadFirst {
        guard case .loaded = await recovered.load() else { Issue.record("Prepared raw fixture did not load"); await app.shutdown(); return }
      }
      _ = try await recovered.stageIntent(intent)
      await studio.sketches.awaitLibrarySynchronization()
      #expect(studio.sketches.libraryState == .saved)
      #expect(try await studio.sketches.librarySelection(workID: intent.runID.description).photo.id == candidate.photoID)
      await app.shutdown()
    } catch { await app.shutdown(); throw error }
  }

  @Test("later raw publication releases an abandoned stage event and publishes its latest prepared generation")
  func laterPublicationReleasesStage() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let studio = PortraitStudioModel(candidateStore: .init(directoryURL: directory))
    let fixture = try await DrawingWorkbenchApplicationFixture.make(portraitStudio: studio)
    defer { fixture.stores.remove() }
    let app = fixture.application
    do {
      let candidate = try portraitPersistenceCandidate(seed: 1001)
      #expect(await app.projectPortrait(candidate) == nil)
      try await fixture.submit(.assertPaperCoverage)
      let intent = try await makeIntent(app)
      _ = try await fixture.stores.evidencePort.stageIntent(intent)
      #expect(studio.sketches.libraryState == .loading)
      let latest = try await fixture.stores.evidencePort.annotateReview(.init(scope: .run(intent.runID), text: "Prepared only"))
      await studio.sketches.awaitLibrarySynchronization()
      #expect(studio.sketches.libraryState == .saved)
      let selected = try await studio.sketches.librarySelection(workID: intent.runID.description)
      #expect(selected.photo.id == candidate.photoID)
      #expect(selected.works.contains { $0.runID == intent.runID && !$0.executedOrPossibleInk })
      let manifestHash = try PortraitCandidateCoding.digest(Data(contentsOf: fixture.stores.evidencePort.archiveURL))
      #expect(selected.generation.evidenceSHA256 == manifestHash && latest.reviewNotes.count == 1)
      await app.shutdown()
    } catch { await app.shutdown(); throw error }
  }

  @Test("genuinely absent raw evidence admits retained photos without plotted works")
  func absentEvidenceKeepsPhotoOnlyLibrary() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let candidate = try portraitPersistenceCandidate(seed: 991)
    let photo = PortraitPhoto(id: candidate.photoID, data: candidate.sourceData, label: "Before the first run",
      capturedAt: candidate.createdAt, frameID: nil, captureNanoseconds: nil, pose: .front,
      sourcePixelExtent: candidate.sourcePixelExtent, captureSessionID: candidate.captureSessionID)
    let writer = PortraitSketchCollection(store: .init(directoryURL: directory))
    writer.retainSourcePhoto(photo)
    await writer.awaitPersistence()
    #expect(writer.persistenceState == .saved)
    let rawURL = directory.appendingPathComponent("raw/drawings.json")
    let port = DrawingRunEvidencePort(store: .init(fileURL: rawURL))
    let reader = PortraitSketchCollection(store: .init(directoryURL: directory, evidenceArchiveURL: rawURL))
    reader.requireEvidenceSynchronization()
    await port.installPortraitLibrary(reader)
    guard case .absent = await port.load() else { Issue.record("Photo-only fixture unexpectedly had raw evidence"); return }
    #expect(reader.libraryState == .saved && !reader.historyLoadHasCompleted)
    let all = try await reader.librarySnapshot()
    #expect(all.generation.evidenceSHA256 == nil)
    #expect(all.photos.map(\.id) == [photo.id] && all.drawings.isEmpty && all.works.isEmpty)
    #expect(try await reader.librarySnapshot(filter: .photosWithoutPlottedWorks).photos.map(\.id) == [photo.id])
    #expect(try await reader.librarySnapshot(filter: .plottedWorks).works.isEmpty)
    let selected = try await reader.librarySelection(photoID: photo.id)
    #expect(selected.drawings.isEmpty && selected.works.isEmpty && selected.program == nil)
    #expect(try await reader.photoForBrowsing(photo.id).data == photo.data)
  }

  @Test("disappearance of a selected raw manifest never becomes an empty successful library generation")
  func selectedEvidenceDisappearanceFailsBrowse() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let accepted = try await CompleteAcceptedLearningFixture.make()
    let stores = CompleteAcceptedLearningStores()
    defer { stores.remove() }
    try await stores.save(accepted)
    let collection = PortraitSketchCollection(store: .init(directoryURL: directory,
      evidenceArchiveURL: stores.evidencePort.archiveURL))
    let candidate = try portraitPersistenceCandidate(seed: 992)
    collection.retainSourcePhoto(.init(id: candidate.photoID, data: candidate.sourceData, label: "Retained",
      capturedAt: candidate.createdAt, frameID: nil, captureNanoseconds: nil, pose: .front,
      sourcePixelExtent: candidate.sourcePixelExtent, captureSessionID: candidate.captureSessionID))
    await collection.awaitPersistence()
    await stores.evidencePort.installPortraitLibrary(collection)
    guard case .loaded = await stores.evidencePort.load() else { Issue.record("Expected a committed raw fixture"); return }
    let before = try await collection.librarySnapshot()
    #expect(before.generation.evidenceSHA256 != nil && before.photos.map(\.id) == [candidate.photoID])
    try FileManager.default.removeItem(at: stores.evidencePort.archiveURL)
    guard case .absent = await stores.evidencePort.load() else { Issue.record("Raw owner did not report absent manifest"); return }
    guard case .failed = collection.libraryState else { Issue.record("Missing selected raw history was presented as current"); return }
    await #expect(throws: (any Error).self) { try await collection.librarySnapshot() }
    #expect(collection.sourcePhotos.first?.id == candidate.photoID)
  }

  @Test("cold actual handoff and pre-motion binding preserve unrelated SQL history without materializing its rasters")
  func coldHandoffPreservesHistoricalMetadata() async throws {
    let history = try await PortraitColdMutationHistoryFixture.make()
    defer { history.remove() }
    let store = PortraitCandidateStore(directoryURL: history.directory)
    let studio = PortraitStudioModel(candidateStore: store)
    let fixture = try await DrawingWorkbenchApplicationFixture.make(portraitStudio: studio)
    defer { fixture.stores.remove() }
    let app = fixture.application
    do {
      #expect(!studio.sketches.historyLoadHasCompleted && studio.sketches.entries.isEmpty)
      #expect(await store.assetBytesVerified == 0)
      #expect(await store.recordBytesEncoded == 0)
      let candidate = try portraitPersistenceCandidate(seed: 993)
      let failure = await app.projectPortrait(candidate)
      try #require(failure == nil, "Cold handoff failed: \(failure ?? "unknown")")
      #expect(studio.projectedDrawing?.sourcePhotoID == candidate.photoID)
      try await fixture.submit(.assertPaperCoverage)
      let intent = try await makeIntent(app)
      _ = try await fixture.stores.evidencePort.stageIntent(intent)
      try await app.retainDrawingCandidateForAttempt(intent)
      await studio.sketches.awaitLibrarySynchronization()
      #expect(try await studio.sketches.librarySelection(workID: intent.runID.description).photo.id == candidate.photoID)
      #expect(!studio.sketches.historyLoadHasCompleted && studio.sketches.entries.map(\.id) == [candidate.id])
      let authoredBytes = try PortraitCandidateCoding.encoder().encode(StoredCandidate(candidate)).count
      #expect(await store.recordBytesEncoded == authoredBytes)
      try history.expectPreserved()
      await app.shutdown()
    } catch { await app.shutdown(); throw error }
  }

  private func makeIntent(_ app: PlotterApplicationRuntime) async throws -> DrawingRunIntent {
    let facts = await app.currentDrawingRunFacts(for: .live)
    let plan = try #require(facts.plan)
    let context = try DrawingRunAttemptContext(program: plan.program, registration: plan.registration,
      materialProfile: plan.materialProfile, materialApplicability: plan.materialApplicability,
      paperStock: plan.paperStock, drawingFeedMMPerMinute: PlotterMotionThroughput.applicationXYFeedMMPerMinute,
      penActuationProfile: facts.penActuationProfile, paper: plan.paperCoverage.paper, candidate: plan.candidate)
    return try DrawingRunIntent(runID: RunID(), requestID: UUID(), plan: plan.plan,
      placementID: plan.placementID, role: .ordinaryDrawing, context: context,
      recordedAt: RuntimeTimestamp(monotonicNanoseconds: 100))
  }
}

/// Test-only SQL receipts verify that consumer delta commits retain the exact
/// immutable payload selectors and metadata of untouched history.
@MainActor
struct PortraitColdMutationHistoryFixture {
  let directory: URL
  let kept: PortraitCandidate
  let unkept: PortraitCandidate
  let label: PortraitLabelRevision
  let generic: SavedDrawing
  private let rows: [String: [[String?]]]
  private let payloads: [String: String]

  static func make() async throws -> Self {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("portrait-cold-history-\(UUID().uuidString)")
    let writer = PortraitSketchCollection(store: .init(directoryURL: directory))
    let kept = try portraitPersistenceCandidate(seed: 995)
    let unkept = try portraitPersistenceCandidate(seed: 996)
    writer.retainSourcePhoto(.init(id: kept.photoID, data: kept.sourceData, label: "Historical original",
      capturedAt: kept.createdAt, frameID: nil, captureNanoseconds: nil, pose: .front,
      sourcePixelExtent: kept.sourcePixelExtent, captureSessionID: kept.captureSessionID))
    writer.recordAttempt(kept, record: try .prepare(candidate: kept, pen: portraitTestStyle()))
    writer.setFeedback(.promising, for: kept.id)
    #expect(writer.rate(candidate: kept, rating: 4, scope: .screenSketch, presentation: try .init()) == nil)
    let label = try #require(writer.labels.first)
    writer.withdrawLabel(label.id)
    writer.recordAttempt(unkept, record: try .prepare(candidate: unkept, pen: portraitTestStyle()))
    writer.saveStyle(name: "Historical style", recipe: kept.recipe)
    let generic = SavedDrawing(program: try DrawingProgramCatalog.program(for: .square, style: portraitTestStyle()))
    #expect(await writer.saveDrawing(generic) == nil)
    await writer.awaitPersistence()
    try #require(writer.persistenceState == .saved)
    let db = try PortraitLibraryDatabase(url: directory.appendingPathComponent("library-v1.sqlite"), readOnly: true)
    var rows: [String: [[String?]]] = [:]
    for table in ["photo", "drawing", "label", "withdrawn_label", "generic_drawing"] {
      rows[table] = try db.rows("SELECT * FROM \(table) ORDER BY id")
    }
    rows["state"] = try db.rows("SELECT key,value FROM state WHERE key IN ('styles','tombstones') ORDER BY key")
    var payloads: [String: String] = [:]
    for folder in ["assets", "records"] {
      for file in try FileManager.default.contentsOfDirectory(at: directory.appendingPathComponent(folder),
        includingPropertiesForKeys: nil) {
        payloads[folder + "/" + file.lastPathComponent] = PortraitCandidateCoding.digest(try Data(contentsOf: file))
      }
    }
    return Self(directory: directory, kept: kept, unkept: unkept, label: label, generic: generic,
      rows: rows, payloads: payloads)
  }

  func expectPreserved() throws {
    let db = try PortraitLibraryDatabase(url: directory.appendingPathComponent("library-v1.sqlite"), readOnly: true)
    for (table, before) in rows {
      let after = try db.rows(table == "state"
        ? "SELECT key,value FROM state WHERE key IN ('styles','tombstones') ORDER BY key"
        : "SELECT * FROM \(table) ORDER BY id")
      for row in before { #expect(after.contains(row), "Untouched \(table) row changed: \(row)") }
    }
    for (path, hash) in payloads {
      #expect(try PortraitCandidateCoding.digest(Data(contentsOf: directory.appendingPathComponent(path))) == hash)
    }
  }

  func remove() { try? FileManager.default.removeItem(at: directory) }
}
