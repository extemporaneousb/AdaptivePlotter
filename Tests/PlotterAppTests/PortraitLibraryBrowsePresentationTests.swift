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

@Suite("Portrait library browse projection", .serialized)
@MainActor
struct PortraitLibraryBrowsePresentationTests {
  @Test("all capture UUIDs remain reachable through bounded pages, including identical bytes and no drawings")
  func zeroDrawingCapturePages() async throws {
    let directory = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let photos = (0..<205).map { index in
      PortraitPhoto(id: UUID(), data: Data([1, 2, 3, 4]), label: "Capture \(index)",
        capturedAt: Date(timeIntervalSince1970: Double(index)), frameID: nil,
        captureNanoseconds: nil, pose: .front)
    }
    let store = PortraitCandidateStore(directoryURL: directory)
    try await store.save(snapshot: .init(sourcePhotos: photos))
    let collection = PortraitSketchCollection(store: store)
    var page = try await collection.librarySnapshot(filter: .allPhotos)
    #expect(page.photos.count == 100)
    var received = page.photos
    while let cursor = page.next {
      page = try await collection.librarySnapshot(filter: .allPhotos, after: cursor)
      #expect(page.photos.count <= 100)
      received += page.photos
    }
    #expect(received.count == 205)
    #expect(Set(received.map(\.id)) == Set(photos.map(\.id)))
    #expect(Set(received.map { $0.reference.sourceSHA256 }).count == 1)
    #expect(received.allSatisfy { $0.drawingCount == 0 && $0.plottedWorkCount == 0 })
    #expect(try await collection.librarySnapshot(filter: .photosWithPlottedWorks).photos.isEmpty)
    let without = try await collection.librarySnapshot(filter: .photosWithoutPlottedWorks)
    #expect(without.photos.map(\.id) == Array(photos.reversed().prefix(100)).map(\.id))
    #expect(try await collection.librarySnapshot(filter: .plottedWorks).works.isEmpty)
    let selection = try await collection.librarySelection(photoID: photos[0].id)
    #expect(selection.photo.id == photos[0].id && selection.drawings.isEmpty)
    #expect(selection.program == nil && selection.works.isEmpty)
    #expect(selection.photo.actualCapturedAt == photos[0].capturedAt)
    #expect(try await collection.photoForBrowsing(photos[0].id) == photos[0])
    #expect(try await collection.photoForBrowsing(photos[104].id) == photos[104])
    let refreshed = try await collection.librarySnapshot()
    #expect(!refreshed.photos.contains { $0.id == photos[0].id })
    let retained = PortraitLibraryBrowsePresentation.selectionAfterReload(current: .photo(photos[0].id),
      previousFilter: .allPhotos, filter: .allPhotos, initialPhotoID: nil, photos: refreshed.photos, works: [])
    #expect(retained == .photo(photos[0].id))
    guard case .photo(let selectedID) = retained else { Issue.record("Refresh lost selected capture"); return }
    #expect(try await collection.librarySelection(photoID: selectedID).photo.id == photos[0].id)
    let changed = PortraitLibraryBrowsePresentation.selectionAfterReload(current: retained,
      previousFilter: .allPhotos, filter: .photosWithPlottedWorks, initialPhotoID: nil, photos: [], works: [])
    #expect(changed == nil)
  }

  @Test("selected capture exposes every compact drawing, including a program older than the first 100")
  func completeSelectedDrawingMetadata() async throws {
    let directory = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let photoID = UUID(), session = UUID()
    let candidates = try (0..<105).map { index in
      let basis = try portraitPersistenceCandidate(seed: UInt64(index))
      return try PortraitCandidate(sourceData: basis.sourceData, sourcePixelExtent: basis.sourcePixelExtent,
        raster: basis.raster, recipe: basis.recipe, program: basis.program, photoID: photoID,
        captureSessionID: session, createdAt: Date(timeIntervalSince1970: Double(index)))
    }
    let source = PortraitPhoto(id: photoID, data: candidates[0].sourceData, label: "Source",
      capturedAt: Date(timeIntervalSince1970: 10), frameID: nil, captureNanoseconds: nil,
      pose: .front, captureSessionID: session)
    let store = PortraitCandidateStore(directoryURL: directory)
    try await store.save(snapshot: .init(entries: candidates.map { .init(candidate: $0, reasons: []) }, sourcePhotos: [source]))
    let collection = PortraitSketchCollection(store: store)
    let photo = try await collection.librarySelection(photoID: photoID)
    #expect(photo.drawings.count == 105)
    #expect(photo.program == candidates.last?.program)
    #expect(photo.selectedDrawing?.identity.candidateID == candidates.last?.id)
    #expect(photo.selectedWorkID == nil)
    let oldest = try #require(photo.drawings.last)
    #expect(oldest.identity.candidateID == candidates[0].id)
    let selected = try await collection.librarySelection(drawingIdentity: oldest.identity)
    #expect(selected.program == candidates[0].program)
    #expect(selected.selectedDrawing?.identity == oldest.identity)
    #expect(selected.drawings.count == 105)
    #expect(PortraitLibraryBrowsePresentation.selectionAfterReload(current: .drawing(oldest.identity),
      previousFilter: .allPhotos, filter: .allPhotos, initialPhotoID: nil, photos: [], works: []) == .drawing(oldest.identity))
    #expect(try await collection.drawingForBrowsing(oldest.identity).sourcePhotoID == photoID)
  }

  @Test("typed Studio inspection selects the exact capture occurrence when candidate and image hashes are equal")
  func exactCaptureInspection() async throws {
    let directory = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let model = PortraitStudioModel(candidateStore: .init(directoryURL: directory))
    let first = try portraitPersistenceCandidate(seed: 943)
    let second = try PortraitCandidate(sourceData: first.sourceData, sourcePixelExtent: first.sourcePixelExtent,
      raster: first.raster, recipe: first.recipe, program: first.program, photoID: UUID(), captureSessionID: UUID())
    for candidate in [first, second] {
      model.sketches.retainSourcePhoto(.init(id: candidate.photoID, data: candidate.sourceData,
        label: "Capture", capturedAt: candidate.createdAt, frameID: nil, captureNanoseconds: nil,
        pose: .front, captureSessionID: candidate.captureSessionID))
      #expect(model.sketches.retain(candidate: candidate, reason: .shortlisted) == nil)
      await model.sketches.awaitPersistence()
    }
    #expect(first.id == second.id && first.sourceSHA256 == second.sourceSHA256)
    let reader = PortraitStudioModel(candidateStore: .init(directoryURL: directory))
    let style = try portraitTestStyle()
    for candidate in [second, first, second] {
      let identity = PortraitDrawingIdentity(candidateID: candidate.id, photoID: candidate.photoID)
      #expect(await reader.inspectDrawing(identity, strokeStyle: style) == nil)
      #expect(reader.selectedPhotoID == candidate.photoID)
      #expect(reader.selectedCandidate?.photoID == candidate.photoID)
      #expect(reader.currentProgram == candidate.program)
      #expect(!reader.isProcessing)
    }
    await reader.shutdown(); await model.shutdown()
  }

  @Test("direct plotted work and photo selection expose the same valid chain while prepared history remains outside plotted filters")
  func plottedWorkChain() async throws {
    let directory = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let studio = PortraitStudioModel(candidateStore: .init(directoryURL: directory))
    let fixture = try await DrawingWorkbenchApplicationFixture.make(portraitStudio: studio)
    defer { fixture.stores.remove() }
    let app = fixture.application
    do {
      let candidate = try portraitPersistenceCandidate(seed: 944)
      studio.sketches.retainSourcePhoto(.init(id: candidate.photoID, data: candidate.sourceData,
        label: "Executed source", capturedAt: candidate.createdAt, frameID: nil,
        captureNanoseconds: nil, pose: .front, captureSessionID: candidate.captureSessionID))
      let newerPhotos = (1...160).map { index in
        PortraitPhoto(id: UUID(), data: Data([9, 8, 7]), label: "No drawing \(index)",
          capturedAt: candidate.createdAt.addingTimeInterval(Double(index)), frameID: nil,
          captureNanoseconds: nil, pose: .front)
      }
      for photo in newerPhotos { studio.sketches.retainSourcePhoto(photo) }
      await studio.sketches.awaitPersistence()
      #expect(await app.projectPortrait(candidate) == nil)
      try await fixture.submit(.assertPaperCoverage)
      try await waitUntil { app.drawingRunSnapshot?.readiness == .ready }
      let facts = await app.currentDrawingRunFacts(for: .live)
      let plan = try #require(facts.plan)
      let context = try DrawingRunAttemptContext(program: plan.program, registration: plan.registration,
        materialProfile: plan.materialProfile, materialApplicability: plan.materialApplicability,
        paperStock: plan.paperStock, drawingFeedMMPerMinute: PlotterMotionThroughput.applicationXYFeedMMPerMinute,
        penActuationProfile: facts.penActuationProfile, paper: plan.paperCoverage.paper, candidate: plan.candidate)
      let prepared = try DrawingRunIntent(runID: RunID(), requestID: UUID(), plan: plan.plan,
        placementID: plan.placementID, role: .ordinaryDrawing, context: context,
        recordedAt: RuntimeTimestamp(monotonicNanoseconds: 100))
      _ = try await fixture.stores.evidencePort.stageIntent(prepared)
      try await app.retainDrawingCandidateForAttempt(prepared)
      await studio.sketches.awaitLibrarySynchronization()
      #expect(try await studio.sketches.librarySnapshot(filter: .plottedWorks).works.isEmpty)
      #expect(try await studio.sketches.librarySnapshot(filter: .photosWithoutPlottedWorks).photos.count == 100)
      #expect(try await studio.sketches.librarySelection(photoID: candidate.photoID).works.count == 1)
      await fixture.planGate.release(.possibleInk)
      let start = try #require(app.testPlotterUIProjection().semantic.request(matching: .drawingRun(.start)))
      _ = await app.submitPlotterUIRequest(start)
      try await waitUntil { !app.drawingReviewRecords.isEmpty }
      await studio.sketches.awaitLibrarySynchronization()
      let works = try await studio.sketches.librarySnapshot(filter: .plottedWorks)
      let work = try #require(works.works.first)
      #expect(work.executedOrPossibleInk)
      #expect(works.works.count == 1)
      #expect(work.drawingTitle == candidate.recipe.title)
      #expect(work.sourcePhotoReference?.id == candidate.photoID)
      #expect(work.drawingIdentity == PortraitDrawingIdentity(candidateID: candidate.id, photoID: candidate.photoID))
      #expect(PortraitLibraryBrowsePresentation.workTitle(work) == candidate.recipe.title)
      #expect(!PortraitLibraryBrowsePresentation.workTitle(work).contains(work.id))
      let defaultChain = try await studio.sketches.librarySelection(photoID: candidate.photoID)
      #expect(defaultChain.selectedWorkID == work.id)
      #expect(defaultChain.selectedDrawing?.identity == work.drawingIdentity)
      #expect(defaultChain.program == candidate.program)
      let rowReader = PortraitSketchCollection(store: .init(directoryURL: directory,
        evidenceArchiveURL: fixture.stores.evidencePort.archiveURL))
      _ = try await rowReader.librarySnapshot(filter: .plottedWorks)
      #expect(try await rowReader.photoForBrowsing(candidate.photoID).data == candidate.sourceData)
      let reader = PortraitSketchCollection(store: .init(directoryURL: directory,
        evidenceArchiveURL: fixture.stores.evidencePort.archiveURL))
      let firstPage = try await reader.librarySnapshot()
      #expect(firstPage.photos.count == 100 && !firstPage.photos.contains { $0.id == candidate.photoID })
      await #expect(throws: (any Error).self) { try await reader.photoForBrowsing(candidate.photoID) }
      let direct = try await reader.librarySelection(workID: work.id)
      #expect(try await reader.photoForBrowsing(candidate.photoID).data == candidate.sourceData)
      let identity = try #require(direct.selectedDrawing?.identity)
      let fromPhoto = try await studio.sketches.librarySelection(photoID: candidate.photoID, drawingIdentity: identity)
      #expect(direct.photo.id == fromPhoto.photo.id && direct.photo.id == candidate.photoID)
      #expect(direct.program == fromPhoto.program && direct.program == candidate.program)
      #expect(direct.drawings.map(\.id) == fromPhoto.drawings.map(\.id))
      #expect(direct.works.map(\.id) == fromPhoto.works.map(\.id))
      #expect(direct.works.first { $0.id == work.id }?.media.map(\.id) == work.media.map(\.id))
      #expect(try await studio.sketches.librarySnapshot(filter: .photosWithPlottedWorks).photos.first?.plottedWorkCount == 1)
      #expect(try await studio.sketches.librarySnapshot(filter: .photosWithoutPlottedWorks).photos.count == 100)
      await app.shutdown()
    } catch { await app.shutdown(); throw error }
  }

  @Test("deleting one identical drawing occurrence preserves both photos, survivor work, restart, inspection and subsequent handoff")
  func deleteOneCaptureDrawing() async throws {
    let directory = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let studio = PortraitStudioModel(candidateStore: .init(directoryURL: directory))
    let fixture = try await DrawingWorkbenchApplicationFixture.make(portraitStudio: studio)
    defer { fixture.stores.remove() }
    let app = fixture.application
    do {
      let first = try portraitPersistenceCandidate(seed: 946)
      let second = try PortraitCandidate(sourceData: first.sourceData, sourcePixelExtent: first.sourcePixelExtent,
        raster: first.raster, recipe: first.recipe, program: first.program, photoID: UUID(), captureSessionID: UUID())
      let firstIdentity = PortraitDrawingIdentity(candidateID: first.id, photoID: first.photoID)
      let secondIdentity = PortraitDrawingIdentity(candidateID: second.id, photoID: second.photoID)
      #expect(first.id == second.id && first.sourceSHA256 == second.sourceSHA256)
      for candidate in [second, first] {
        studio.sketches.retainSourcePhoto(.init(id: candidate.photoID, data: candidate.sourceData,
          label: "Independent capture", capturedAt: candidate.createdAt, frameID: nil,
          captureNanoseconds: nil, pose: .front, captureSessionID: candidate.captureSessionID))
        #expect(studio.sketches.retain(candidate: candidate, reason: .shortlisted) == nil)
        await studio.sketches.awaitPersistence()
      }
      func stage() async throws -> RunID {
        try await fixture.submit(.assertPaperCoverage)
        let facts = await app.currentDrawingRunFacts(for: .live)
        let plan = try #require(facts.plan)
        let context = try DrawingRunAttemptContext(program: plan.program, registration: plan.registration,
          materialProfile: plan.materialProfile, materialApplicability: plan.materialApplicability,
          paperStock: plan.paperStock, drawingFeedMMPerMinute: PlotterMotionThroughput.applicationXYFeedMMPerMinute,
          penActuationProfile: facts.penActuationProfile, paper: plan.paperCoverage.paper, candidate: plan.candidate)
        let intent = try DrawingRunIntent(runID: RunID(), requestID: UUID(), plan: plan.plan,
          placementID: plan.placementID, role: .ordinaryDrawing, context: context,
          recordedAt: RuntimeTimestamp(monotonicNanoseconds: 100))
        _ = try await fixture.stores.evidencePort.stageIntent(intent)
        try await app.retainDrawingCandidateForAttempt(intent)
        await studio.sketches.awaitLibrarySynchronization()
        return intent.runID
      }
      #expect(await app.projectPortrait(second) == nil)
      let secondRun = try await stage()
      #expect(await app.projectPortrait(first) == nil)
      let firstRun = try await stage()
      let before = try Data(contentsOf: fixture.stores.evidencePort.archiveURL)
      studio.sketches.deleteDrawing(firstIdentity)
      await studio.sketches.awaitPersistence()
      #expect(try Data(contentsOf: fixture.stores.evidencePort.archiveURL) == before)
      let fresh = PortraitStudioModel(candidateStore: .init(directoryURL: directory,
        evidenceArchiveURL: fixture.stores.evidencePort.archiveURL))
      await fresh.sketches.load()
      #expect(fresh.sketches.entries.contains { $0.candidate.photoID == second.photoID })
      let roots = try await fresh.sketches.librarySnapshot()
      #expect(Set(roots.photos.map(\.id)) == Set([first.photoID, second.photoID]))
      #expect(roots.photos.first { $0.id == first.photoID }?.drawingCount == 0)
      #expect(roots.photos.first { $0.id == second.photoID }?.drawingCount == 1)
      let survivor = try await fresh.sketches.drawingForBrowsing(secondIdentity)
      #expect(survivor.sourcePhotoID == second.photoID && survivor.program == second.program)
      #expect(try await fresh.sketches.librarySelection(workID: secondRun.description).photo.id == second.photoID)
      await #expect(throws: (any Error).self) { try await fresh.sketches.drawingForBrowsing(firstIdentity) }
      await #expect(throws: (any Error).self) { try await fresh.sketches.librarySelection(workID: firstRun.description) }
      #expect(await fresh.inspectDrawing(secondIdentity, strokeStyle: app.drawingStrokeStyle) == nil)
      #expect(fresh.selectedCandidate?.photoID == second.photoID && !fresh.isProcessing)
      #expect(await fresh.sketches.saveDrawing(survivor) == nil)
      #expect(await app.projectSavedDrawing(survivor) == nil)
      #expect(studio.projectedDrawing?.sourcePhotoID == second.photoID)
      let newRun = try await stage()
      #expect(try await studio.sketches.librarySelection(workID: newRun.description).photo.id == second.photoID)
      #expect(try await studio.sketches.librarySelection(photoID: first.photoID).drawings.isEmpty)
      await fresh.shutdown()
      await app.shutdown()
    } catch { await app.shutdown(); throw error }
  }

  @Test("capture descriptions preserve acquisition time and keep absent historical time unknown")
  func captureDescriptionProvenance() async throws {
    let directory = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let candidate = try portraitPersistenceCandidate(seed: 945)
    let store = PortraitCandidateStore(directoryURL: directory)
    try await store.save(snapshot: .init(entries: [.init(candidate: candidate, reasons: [])]))
    let historic = try #require(try await store.librarySnapshot().photos.first)
    #expect(historic.actualCapturedAt == nil)
    #expect(PortraitLibraryBrowsePresentation.photoTitle(historic) == "Photo · Capture time unknown")
    let capturedAt = Date(timeIntervalSince1970: 1_700_000_000)
    let original = PortraitPhoto(id: candidate.photoID, data: candidate.sourceData, label: "Frame 0.8s",
      capturedAt: capturedAt, frameID: nil, captureNanoseconds: nil, pose: .front,
      captureSessionID: candidate.captureSessionID)
    try await store.save(snapshot: .init(entries: [.init(candidate: candidate, reasons: [])], sourcePhotos: [original]))
    let retained = try #require(try await store.librarySnapshot().photos.first)
    #expect(retained.actualCapturedAt == capturedAt)
    #expect(PortraitLibraryBrowsePresentation.photoTitle(retained)
      == "Photo · " + capturedAt.formatted(date: .abbreviated, time: .shortened))
    #expect(!PortraitLibraryBrowsePresentation.photoTitle(retained).contains("Frame 0.8s"))
  }

  @Test("work thumbnails prefer latest available terminal, then progress, and explicitly fall back to the source")
  func truthfulThumbnailSelection() throws {
    func media(_ id: String, stage: String, time: UInt64, available: Bool,
      completion: Bool = false) throws -> PortraitLibraryMedia {
      let frame = try StampedFrame(sequence: time, captureNanoseconds: time,
        cameraConfigurationID: CameraConfigurationID(), width: 1, height: 1,
        rowBytes: 4, pixelFormat: .bgra8, bytes: OwnedFrameBytes([0, 0, 0, 255]))
      return .init(id: id, stage: stage, reference: .init(frame: frame, source: .simulated,
        completionCaptureAfterNanoseconds: completion ? time - 1 : nil),
        isAvailable: available, unavailableReason: available ? nil : "Missing pixels")
    }
    let progress = try media("progress", stage: "progress-1", time: 30, available: true)
    let first = try media("first", stage: "terminal-1", time: 40, available: true)
    let latest = try media("latest", stage: "terminal-2", time: 50, available: true, completion: true)
    let missing = try media("missing", stage: "terminal-3", time: 60, available: false)
    #expect(PortraitLibraryBrowsePresentation.thumbnailChoice([progress, latest, missing, first]) == .media("latest"))
    #expect(PortraitLibraryBrowsePresentation.thumbnailChoice([missing, progress]) == .media("progress"))
    #expect(PortraitLibraryBrowsePresentation.thumbnailChoice([missing]) == .source)
    #expect(PortraitLibraryBrowsePresentation.thumbnailChoice([]) == .source)
    #expect(PortraitLibraryBrowsePresentation.mediaLabel(latest) == "Result")
    #expect(PortraitLibraryBrowsePresentation.mediaLabel(first) == "Terminal")
    #expect(PortraitLibraryBrowsePresentation.mediaLabel(progress) == "Progress")
  }

  private func temporaryDirectory() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("portrait-browse-\(UUID().uuidString)")
  }
  private func waitUntil(_ condition: () -> Bool) async throws {
    let deadline = ContinuousClock.now.advanced(by: .seconds(10))
    while !condition() {
      try #require(ContinuousClock.now < deadline)
      try await Task.sleep(for: .milliseconds(10))
    }
  }
}
