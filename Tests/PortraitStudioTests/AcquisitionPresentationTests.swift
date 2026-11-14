import Foundation
import AppKit
import SwiftUI
import DrawingLibrary
import PlotterModel
import PortraitArtists
import PortraitCore
@testable import PortraitLibrary
import PortraitStudioUI
import Testing

@Suite("Photo acquisition retention and presentation", .serialized)
@MainActor
struct AcquisitionPresentationTests {
  @Test("A delayed immutable capture is retained once while import B owns source and presentation")
  func captureThenImport() async throws {
    let root = temporary(); defer { try? FileManager.default.removeItem(at: root) }
    let model = await opened(root)
    let gate = AcquisitionPresentationGate(), photo = capturePhoto(4)
    let delayed = Task {
      await FlowPhotoAcquisition.capture(model: model) { await gate.holdOnce(); return photo }
    }
    await gate.entered()
    let imported = await FlowPhotoAcquisition.importPhotos(model: model, multiple: false,
      pick: { _ in [URL(fileURLWithPath: "/fixture/B.png")] }, read: { _ in FlowAuthoringFixture.image(5) })
    let selected = try #require(imported.adopted), source = model.sourceData
    gate.release(); let stale = await delayed.value
    #expect(stale.photos.count == 1 && stale.adopted == nil && stale.failures.isEmpty)
    #expect(model.currentPhotoRef == selected && model.sourceData == source)
    let store = try #require(model.store)
    let durable = await store.snapshot()
    #expect(durable.sources.count == 3 && durable.sources.first(where: { $0.id == durable.selectedSourceID })?.photo == selected)
    #expect(durable.sources.filter { $0.captureProvenance?.photoID == photo.id }.count == 1)
    _ = await model.addCapturedPhoto(photo, title: "Replay", intent: model.beginPhotoAcquisition(isStillCurrent: { false }))
    #expect(await store.snapshot().sources.count == 3)
    await model.retryCandidateLoad()
    #expect(model.currentPhotoRef == selected && model.sourceData == source && model.error == nil)
    #expect(await model.shutdown())
  }

  @Test("New capture, photo navigation, retained drawing, tabs and route ABA revoke capture adoption", arguments: ["capture", "photo", "drawing", "tab", "away-return", "region", "cancel-task"])
  func delayedCaptureRevocation(replacement: String) async throws {
    let root = temporary(); defer { try? FileManager.default.removeItem(at: root) }
    let model = await opened(root), gate = AcquisitionPresentationGate()
    var routeEpoch = 0, route = "booth"
    let delayed = Task {
      await FlowPhotoAcquisition.capture(model: model, isStillCurrent: { routeEpoch == 0 && route == "booth" }) {
        await gate.holdOnce(); return capturePhoto(6)
      }
    }
    await gate.entered()
    if replacement == "cancel-task" {
      delayed.cancel()
    } else if replacement == "capture" {
      _ = await FlowPhotoAcquisition.capture(model: model) { capturePhoto(7) }
    } else if replacement == "photo" {
      await model.addPhoto(data: FlowAuthoringFixture.image(8), title: "New selection")
    } else if replacement == "region" {
      model.invalidateRegionPreview()
      await model.commitRegion(.init(x: 0, y: 0, width: 0.5, height: 1))
    } else {
      routeEpoch += 1; route = replacement
      if replacement == "away-return" { routeEpoch += 1; route = "booth" }
    }
    let ref = model.currentPhotoRef, pixels = model.sourceData, options = model.committedAnalysisOptions
    let suggestion = model.recommendationCandidate?.id, error = model.error
    gate.release(); let result = await delayed.value
    #expect(result.photos.count == 1 && result.adopted == nil)
    #expect(model.currentPhotoRef == ref && model.sourceData == pixels && model.committedAnalysisOptions == options)
    #expect(model.recommendationCandidate?.id == suggestion && model.error == error)
    let store = try #require(model.store)
    let snapshot = await store.snapshot()
    #expect(snapshot.sources.first(where: { $0.id == snapshot.selectedSourceID })?.photo == ref)
    await model.retryCandidateLoad()
    #expect(model.currentPhotoRef == ref && model.sourceData == pixels)
    #expect(await model.shutdown())
  }

  @Test("Picker, image read and collection load retain exact stale outcomes without adopting", arguments: ["picker", "image", "collection"])
  func delayedImportBoundaries(boundary: String) async throws {
    let root = temporary(), folder = temporary()
    defer { try? FileManager.default.removeItem(at: root); try? FileManager.default.removeItem(at: folder) }
    try writeCollection(folder)
    let model = await opened(root), gate = AcquisitionPresentationGate()
    var epoch = 0
    let collection = try FlowPhotoCollection.load(directory: folder)
    let task = Task {
      await FlowPhotoAcquisition.importPhotos(model: model, multiple: true, isStillCurrent: { epoch == 0 },
        pick: { _ in
          if boundary == "picker" { await gate.holdOnce() }
          return [boundary == "collection" ? folder : URL(fileURLWithPath: "/fixture/A.png")]
        }, read: { _ in
          if boundary == "image" { await gate.holdOnce() }
          return FlowAuthoringFixture.image(9)
        }, loadCollection: { _ in await gate.holdOnce(); return collection }, isCollection: { _ in boundary == "collection" })
    }
    await gate.entered(); epoch += 1
    let selected = model.currentPhotoRef, pixels = model.sourceData
    gate.release(); let result = await task.value
    #expect(result.photos.count == 1 && result.adopted == nil && result.failures.isEmpty)
    let store = try #require(model.store), durable = await store.snapshot()
    #expect(durable.sources.count == 2 && durable.sources.first(where: { $0.id == durable.selectedSourceID })?.photo == selected)
    #expect(model.currentPhotoRef == selected && model.sourceData == pixels && model.error == nil)
    await model.retryCandidateLoad(); #expect(model.currentPhotoRef == selected)
    if boundary == "collection" {
      let replay = await FlowPhotoAcquisition.importPhotos(model: model, multiple: true,
        pick: { _ in [folder] }, loadCollection: { _ in collection })
      #expect(replay.photos == result.photos && replay.adopted == result.photos.last)
      #expect(await store.snapshot().sources.count == 2)
    }
    #expect(await model.shutdown())
  }

  @Test("Admitted adoption restores only previous selection on tab change or shutdown", arguments: [false, true])
  func admittedSelectionRevocation(shutdown: Bool) async throws {
    let root = temporary(); defer { try? FileManager.default.removeItem(at: root) }
    let model = await opened(root), gate = AcquisitionPresentationGate(), store = try #require(model.store)
    let prior = await store.snapshot(), ref = model.currentPhotoRef, pixels = model.sourceData
    await store.setSourceAdoptionDidPersistHook { await gate.holdOnce() }
    var routeEpoch = 0
    let task = Task {
      await FlowPhotoAcquisition.capture(model: model, isStillCurrent: { routeEpoch == 0 }) { capturePhoto(10) }
    }
    await gate.entered()
    #expect(await store.snapshot().selectedSourceID != prior.selectedSourceID)
    routeEpoch += 1
    let closing: Task<Bool, Never>?
    if shutdown { closing = Task { await model.shutdown() }; await Task.yield() } else { closing = nil }
    gate.release(); let result = await task.value
    #expect(result.photos.count == 1 && result.adopted == nil)
    #expect(model.currentPhotoRef == ref && model.sourceData == pixels)
    if let closing { #expect(await closing.value) }
    let durable = await store.snapshot()
    #expect(durable.selectedSourceID == prior.selectedSourceID && durable.currentRoundID == prior.currentRoundID)
    #expect(durable.currentCandidateID == prior.currentCandidateID && durable.currentPruneRevisionID == prior.currentPruneRevisionID)
    #expect(durable.sources.count == prior.sources.count + 1)
    if !shutdown {
      await model.retryCandidateLoad(); #expect(model.currentPhotoRef == ref && model.sourceData == pixels)
      #expect(await model.shutdown())
    }
  }

  @Test("Revoking adoption inside an exact snapshot read preserves model pixels and restores durable selection")
  func adoptionSnapshotRevocation() async throws {
    let root = temporary(); defer { try? FileManager.default.removeItem(at: root) }
    let model = await opened(root), gate = AcquisitionPresentationGate()
    let ref = model.currentPhotoRef, pixels = model.sourceData
    var epoch = 0
    model.publicationBarrier = { boundary in if case .snapshotRead = boundary { await gate.holdOnce() } }
    let task = Task {
      await FlowPhotoAcquisition.capture(model: model, isStillCurrent: { epoch == 0 }) { capturePhoto(14) }
    }
    await gate.entered(); epoch += 1; gate.release()
    let result = await task.value
    #expect(result.photos.count == 1 && result.adopted == nil)
    #expect(model.currentPhotoRef == ref && model.sourceData == pixels)
    let durable = await model.store?.snapshot()
    #expect(durable?.sources.first(where: { $0.id == durable?.selectedSourceID })?.photo == ref)
    #expect(model.error == nil && !model.needsRecovery)
    await model.retryCandidateLoad(); #expect(model.currentPhotoRef == ref)
    #expect(await model.shutdown())
  }

  @Test("A same-route cancelled or failed import revokes older final errors", arguments: [false, true])
  func newerEmptyImportOwnsErrors(failing: Bool) async throws {
    let root = temporary(); defer { try? FileManager.default.removeItem(at: root) }
    let model = await opened(root), gate = AcquisitionPresentationGate()
    let older = Task {
      await FlowPhotoAcquisition.importPhotos(model: model, multiple: false,
        pick: { _ in [URL(fileURLWithPath: "/fixture/old.png")] }, read: { _ in
          await gate.holdOnce(); throw CocoaError(.fileReadCorruptFile)
        })
    }
    await gate.entered()
    let newer = await FlowPhotoAcquisition.importPhotos(model: model, multiple: false,
      pick: { _ in failing ? [URL(fileURLWithPath: "/fixture/new.png")] : [] },
      read: { _ in throw CocoaError(.fileReadNoPermission) })
    #expect(newer.presentationIsCurrent() && newer.adopted == nil)
    var displayedError = newer.failures.joined(separator: "\n")
    let expected = displayedError
    gate.release(); let result = await older.value
    #expect(!result.presentationIsCurrent() && result.adopted == nil && result.failures.count == 1)
    // This is the final publication gate used by the standalone window.
    if result.presentationIsCurrent() { displayedError = result.failures.joined(separator: "\n") }
    #expect(displayedError == expected)
    #expect(await model.shutdown())
  }

  @Test("Failed capture, import and sidebar load preserve the prior route and exact selected drawing", arguments: ["capture", "import", "sidebar"])
  func currentAdoptionFailurePreservesPresentation(operation: String) async throws {
    let root = temporary(); defer { try? FileManager.default.removeItem(at: root) }
    let model = await opened(root), gate = AcquisitionPresentationGate(), store = try #require(model.store)
    model.count = 3; await model.generate(refining: false)
    await model.selectCandidate(try #require(model.roundCandidates.first?.id), prune: true)
    await model.edit(.remove, ids: [try #require(model.program?.strokes.first?.id)])
    model.invalidateRegionPreview()
    let prior = await store.snapshot(), original = model.currentPhotoRef, pixels = model.sourceData, program = model.program
    let draftPending = model.regionPreviewPending
    let library = try #require(model.drawingLibrary)
    let sidebarPhoto = try PortraitDrawingImages.photo(data: FlowAuthoringFixture.image(15), issuer: UUID(), captureID: UUID(), capturedAt: nil, importedAt: Date())
    if operation == "sidebar" { try await library.commitRecords([], closure: .init(photo: sidebarPhoto)) }
    await store.setSourceAdoptionDidPersistHook { await gate.holdOnce() }
    var route = "A", callbacks = 0
    let sidebar = FlowAuthoringSidebar(model: model, photoSelected: { _ in callbacks += 1; route = "B" })
    let task = Task { () -> FlowPhotoAcquisitionResult in
      switch operation {
      case "capture": return await FlowPhotoAcquisition.capture(model: model) { capturePhoto(15) }
      case "import": return await FlowPhotoAcquisition.importPhotos(model: model, multiple: false,
        pick: { _ in [URL(fileURLWithPath: "/fixture/failed-B.png")] }, read: { _ in FlowAuthoringFixture.image(15) })
      default: await sidebar.openPhoto(sidebarPhoto.reference); return .init()
      }
    }
    await gate.entered()
    let admitted = await store.snapshot(), source = try #require(admitted.sources.last)
    let asset = root.appendingPathComponent("objects/sha256/" + source.image.sha256)
    let held = root.appendingPathComponent("held-original")
    try FileManager.default.moveItem(at: asset, to: held)
    gate.release(); let result = await task.value
    if operation != "sidebar" {
      #expect(result.photos == [source.photo].compactMap { $0 } && result.adopted == nil)
      #expect(result.presentationIsCurrent() && result.failures.count == 1)
    }
    #expect(route == "A" && callbacks == 0 && model.error != nil && !model.needsRecovery)
    #expect(model.currentPhotoRef == original && model.sourceData == pixels && model.program == program)
    #expect(model.regionPreviewPending == draftPending)
    let durable = await store.snapshot()
    #expect(durable.selectedSourceID == prior.selectedSourceID && durable.currentRoundID == prior.currentRoundID)
    #expect(durable.currentCandidateID == prior.currentCandidateID && durable.currentPruneRevisionID == prior.currentPruneRevisionID)
    #expect(durable.sources.count == prior.sources.count + 1 && durable.sources.filter { $0.photo == source.photo }.count == 1)
    try FileManager.default.moveItem(at: held, to: asset)
    await model.retryCandidateLoad()
    #expect(model.currentPhotoRef == original && model.sourceData == pixels && model.program == program && !model.needsRecovery)
    #expect(model.document == (await store.snapshot()))
    #expect(await model.shutdown())
  }

  @Test("An unchanged-head adoption failure cannot later adopt during recovery")
  func unchangedHeadRecoveryCannotPresent() async throws {
    let root = temporary(); defer { try? FileManager.default.removeItem(at: root) }
    let model = await opened(root), store = try #require(model.store)
    let original = model.currentPhotoRef, pixels = model.sourceData
    let intent = model.beginPhotoAcquisition()
    let retained = await model.addPhoto(data: FlowAuthoringFixture.image(21), title: "Retained B", intent: intent, adopting: false)
    let b = try #require(retained.photos.first), prior = await store.snapshot()
    // Exercise the existing real pre-pending publication admission guard. It
    // throws before preparing a pending write or advancing the durable head.
    await store.setAcquisitionAdmissionBusy(true)
    let result = await model.adoptRetainedPhoto(b, intent: intent)
    #expect(result.adopted == nil && result.failures.count == 1 && model.needsRecovery)
    #expect(await store.snapshot() == prior)
    await store.setAcquisitionAdmissionBusy(false)
    await model.recoverAutosave()
    #expect(!model.needsRecovery && model.currentPhotoRef == original && model.sourceData == pixels)
    #expect(result.adopted == nil && result.presentationIsCurrent())
    let after = await store.snapshot()
    #expect(after.selectedSourceID == prior.selectedSourceID && after.currentRoundID == prior.currentRoundID)
    #expect(after.currentCandidateID == prior.currentCandidateID && after.currentPruneRevisionID == prior.currentPruneRevisionID)
    #expect(after.sources.filter { $0.photo == b }.count == 1)
    await model.retryCandidateLoad(); #expect(model.currentPhotoRef == original)
    #expect(model.document == (await store.snapshot()))
    #expect(await model.shutdown())
  }

  @Test("A returned-empty capture may finish queued retention after recovery but cannot adopt")
  func queuedReturnedCaptureCannotPresent() async throws {
    let root = temporary(); defer { try? FileManager.default.removeItem(at: root) }
    let model = await opened(root), store = try #require(model.store), library = try #require(model.drawingLibrary)
    let photo = capturePhoto(22), gate = AcquisitionPresentationGate()
    let original = model.currentPhotoRef, pixels = model.sourceData, prior = await store.snapshot()
    let task = Task { await FlowPhotoAcquisition.capture(model: model) { await gate.holdOnce(); return photo } }
    await gate.entered()
    try await library.editFault(.beforeSQLPublication)
    await model.renameSource(try #require(model.selectedSource?.id), title: "Pending metadata")
    #expect(model.needsRecovery)
    gate.release(); let result = await task.value
    #expect(result.photos.isEmpty && result.adopted == nil)
    try await library.editFault(nil)
    await model.recoverAutosave()
    #expect(!model.needsRecovery && model.currentPhotoRef == original && model.sourceData == pixels)
    let durable = await store.snapshot()
    #expect(durable.sources.filter { $0.captureProvenance?.photoID == photo.id }.count == 1)
    #expect(durable.selectedSourceID == prior.selectedSourceID && durable.currentRoundID == prior.currentRoundID)
    #expect(durable.currentCandidateID == prior.currentCandidateID && durable.currentPruneRevisionID == prior.currentPruneRevisionID)
    #expect(result.adopted == nil)
    await model.retryCandidateLoad(); #expect(model.currentPhotoRef == original)
    #expect(model.document == (await store.snapshot()))
    #expect(await model.shutdown())
  }

  @Test("Pending live adoption recovery retains the new Photo once and restores unpublished selection", arguments: [LibraryExchangeCatalogBoundary.beforeSQLPublication, .afterSQLCommit])
  func livePendingAdoptionRecovery(boundary: LibraryExchangeCatalogBoundary) async throws {
    let root = temporary(); defer { try? FileManager.default.removeItem(at: root) }
    let model = await opened(root), store = try #require(model.store), library = try #require(model.drawingLibrary)
    model.count = 3; await model.generate(refining: false)
    await model.selectCandidate(try #require(model.roundCandidates.first?.id), prune: true)
    #expect(model.canSendToPlotter)
    model.invalidateRegionPreview()
    let prior = await store.snapshot(), original = model.currentPhotoRef, pixels = model.sourceData
    try await library.failSecondAcquisitionPublication(boundary)
    let result = await FlowPhotoAcquisition.capture(model: model) { capturePhoto(20) }
    #expect(result.photos.count == 1 && result.adopted == nil && result.failures.count == 1)
    #expect(result.presentationIsCurrent() && model.needsRecovery && model.currentPhotoRef == original && model.sourceData == pixels)
    await library.clearAcquisitionCompensationFault()
    await model.recoverAutosave()
    #expect(!model.needsRecovery && model.error == nil && model.currentPhotoRef == original && model.sourceData == pixels)
    let durable = await store.snapshot()
    #expect(durable.sources.count == prior.sources.count + 1)
    #expect(durable.selectedSourceID == prior.selectedSourceID && durable.currentRoundID == prior.currentRoundID)
    #expect(durable.currentCandidateID == prior.currentCandidateID && durable.currentPruneRevisionID == prior.currentPruneRevisionID)
    #expect(model.document == durable && model.regionPreviewPending && !model.canSendToPlotter)
    #expect(await model.shutdown())
  }

  @Test("Failed current or stale compensation reconciles pending persistence without replaying acquisition", arguments: [false, true])
  func staleCompensationRecovery(revoked: Bool) async throws {
    let root = temporary(); defer { try? FileManager.default.removeItem(at: root) }
    let model = await opened(root), gate = AcquisitionPresentationGate(), store = try #require(model.store)
    let library = try #require(model.drawingLibrary), original = model.currentPhotoRef
    model.count = 3; await model.generate(refining: false)
    await model.selectCandidate(try #require(model.roundCandidates.first?.id), prune: true)
    #expect(model.canSendToPlotter)
    model.invalidateRegionPreview()
    await store.setSourceAdoptionDidPersistHook { await gate.holdOnce() }
    var epoch = 0
    let task = Task {
      await FlowPhotoAcquisition.capture(model: model, isStillCurrent: { epoch == 0 }) { capturePhoto(17) }
    }
    await gate.entered()
    let source = try #require(await store.snapshot().sources.last)
    let asset = root.appendingPathComponent("objects/sha256/" + source.image.sha256)
    let held = root.appendingPathComponent("held-compensation-original")
    if revoked { epoch += 1 }
    else { try FileManager.default.moveItem(at: asset, to: held) }
    try await library.failAcquisitionCompensationAfterCommit()
    gate.release(); let result = await task.value
    #expect(result.photos.count == 1 && result.adopted == nil && result.presentationIsCurrent() == !revoked)
    #expect(model.needsRecovery && model.currentPhotoRef == original)
    if revoked { #expect(model.autosaveStatus.contains("recovery")) }
    await library.clearAcquisitionCompensationFault()
    if !revoked { try FileManager.default.moveItem(at: held, to: asset) }
    await model.recoverAutosave()
    #expect(!model.needsRecovery && model.error == nil && model.currentPhotoRef == original)
    #expect(model.regionPreviewPending && !model.canSendToPlotter)
    let durable = await store.snapshot()
    #expect(durable.sources.count == 2 && durable.sources.first(where: { $0.id == durable.selectedSourceID })?.photo == original)
    await model.retryCandidateLoad()
    #expect(model.document == (await store.snapshot()) && model.currentPhotoRef == original)
    #expect(await model.shutdown())
  }

  @Test("Delayed sidebar selection cannot publish across tab, drawing or route ABA", arguments: ["persist-tab", "persist-drawing", "persist-away-return", "read-tab", "read-drawing", "read-away-return"])
  func sidebarSelectionRevocation(scenario: String) async throws {
    let root = temporary(); defer { try? FileManager.default.removeItem(at: root) }
    let model = await opened(root), gate = AcquisitionPresentationGate(), store = try #require(model.store)
    model.count = 3; await model.generate(refining: false)
    await model.browseCandidate(try #require(model.roundCandidates.first?.id), prune: true)
    await model.edit(.remove, ids: [try #require(model.program?.strokes.first?.id)])
    let prior = await store.snapshot(), pixels = model.sourceData, program = model.program, ref = model.currentPhotoRef
    let library = try #require(model.drawingLibrary)
    let target = try PortraitDrawingImages.photo(data: FlowAuthoringFixture.image(18), issuer: UUID(), captureID: UUID(), capturedAt: nil, importedAt: Date())
    try await library.commitRecords([], closure: .init(photo: target))
    if scenario.hasPrefix("persist") { await store.setSourceAdoptionDidPersistHook { await gate.holdOnce() } }
    else { model.publicationBarrier = { if case .snapshotRead = $0 { await gate.holdOnce() } } }
    var callbacks: [PhotoRef] = [], route = "drawing", epoch = 0
    let sidebar = FlowAuthoringSidebar(model: model, photoSelected: { callbacks.append($0); route = "selected-photo" })
    let task = Task { await sidebar.openPhoto(target.reference) }
    await gate.entered()
    // The window's central route binding performs this same token invalidation.
    model.invalidatePhotoAcquisition(); epoch += 1; route = scenario.contains("tab") ? "photos" : "retained-drawing"
    if scenario.contains("away-return") { model.invalidatePhotoAcquisition(); epoch += 1; route = "drawing" }
    let expectedRoute = route, expectedEpoch = epoch
    gate.release(); await task.value
    #expect(callbacks.isEmpty && route == expectedRoute && epoch == expectedEpoch)
    #expect(model.currentPhotoRef == ref && model.sourceData == pixels && model.program == program)
    #expect(model.document?.currentRoundID == prior.currentRoundID && model.document?.currentCandidateID == prior.currentCandidateID)
    #expect(model.document?.currentPruneRevisionID == prior.currentPruneRevisionID && model.error == nil && !model.needsRecovery)
    let durable = await store.snapshot()
    #expect(durable.selectedSourceID == prior.selectedSourceID && durable.currentRoundID == prior.currentRoundID)
    #expect(durable.currentCandidateID == prior.currentCandidateID && durable.currentPruneRevisionID == prior.currentPruneRevisionID)
    #expect(durable.sources.contains { $0.photo == target.reference })
    await model.retryCandidateLoad()
    #expect(model.currentPhotoRef == ref && model.sourceData == pixels && model.program == program)
    #expect(model.document == (await store.snapshot()) && model.canEdit && model.canSendToPlotter)
    #expect(await model.shutdown())
  }

  @Test("A revoked source's candidate read error cannot disable the preceding valid drawing")
  func staleCandidateReadError() async throws {
    let root = temporary(); defer { try? FileManager.default.removeItem(at: root) }
    let model = await opened(root), store = try #require(model.store), library = try #require(model.drawingLibrary)
    model.count = 3; await model.generate(refining: false)
    await model.selectCandidate(try #require(model.roundCandidates.first?.id), prune: true)
    let a = try #require(model.currentPhotoRef), aProgram = model.program, aPixels = model.sourceData
    await model.addPhoto(data: FlowAuthoringFixture.image(19), title: "Unavailable candidate source")
    await model.generate(refining: false)
    let bCandidate = try #require(model.roundCandidates.first)
    await model.selectCandidate(bCandidate.id)
    let b = try #require(model.currentPhotoRef), drawing = try await store.candidateDrawing(bCandidate.id)
    let reference = try #require(drawing.reference)
    let object = root.appendingPathComponent("objects/sha256/" + DrawingArtifactCoding.sha256(try DrawingArtifactCoding.encoder().encode(drawing.program)))
    let original = try Data(contentsOf: object)
    await model.selectPhoto(a)
    try FileManager.default.removeItem(at: object)
    await library.evictSelectedDrawing(reference)
    await #expect(throws: (any Error).self) { try await store.candidateProgram(bCandidate.id) }
    let gate = AcquisitionPresentationGate()
    model.publicationBarrier = { if case .candidateRead(let id) = $0, id == bCandidate.id { await gate.holdOnce() } }
    var callbacks: [PhotoRef] = []
    let sidebar = FlowAuthoringSidebar(model: model, photoSelected: { callbacks.append($0) })
    let task = Task { await sidebar.openPhoto(b) }
    await gate.entered()
    #expect(model.currentPhotoRef == a && model.candidateLoadError == nil)
    model.invalidatePhotoAcquisition(); gate.release(); await task.value
    try original.write(to: object)
    #expect(callbacks.isEmpty && model.currentPhotoRef == a && model.sourceData == aPixels && model.program == aProgram)
    #expect(model.candidateLoadError == nil && model.canEdit && model.canSendToPlotter && model.error == nil)
    let durable = await store.snapshot()
    #expect(durable.sources.first(where: { $0.id == durable.selectedSourceID })?.photo == a)
    await model.retryCandidateLoad()
    #expect(model.currentPhotoRef == a && model.canEdit && model.canSendToPlotter && model.candidateLoadError == nil)
    #expect(await model.shutdown())
  }

  @Test("Hosted Drawing does not echo an imported source, while explicit sidebar selection still publishes")
  func drawingRouteEcho() async throws {
    _ = NSApplication.shared
    let root = temporary(); defer { try? FileManager.default.removeItem(at: root) }
    let model = await opened(root), owner = PortraitStudioModel(library: DrawingLibrary(directoryURL: root.appendingPathComponent("camera")))
    var callbacks: [PhotoRef] = []
    let host = NSHostingController(rootView: FlowAuthoringView(model: model, camera: owner, embedded: true,
      photoSelected: { if let reference = $0 { callbacks.append(reference) } }).frame(width: 1280, height: 850))
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1280, height: 850), styleMask: [.titled], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false; window.contentViewController = host
    defer { window.contentViewController = nil; window.close() }
    host.view.layoutSubtreeIfNeeded()
    try await Task.sleep(for: .milliseconds(40))
    let result = await FlowPhotoAcquisition.importPhotos(model: model, multiple: false,
      pick: { _ in [URL(fileURLWithPath: "/fixture/route.png")] }, read: { _ in FlowAuthoringFixture.image(16) })
    host.view.layoutSubtreeIfNeeded()
    try await Task.sleep(for: .milliseconds(40))
    #expect(result.adopted == model.currentPhotoRef && result.presentationIsCurrent())
    #expect(callbacks.isEmpty, "Only the import operation owns its final route reveal.")
    let reference = try #require(model.currentPhotoRef)
    let sidebar = FlowAuthoringSidebar(model: model, photoSelected: { callbacks.append($0) })
    await sidebar.openPhoto(reference)
    #expect(callbacks == [reference], "Explicit same-photo selection still publishes and revokes an older import.")
    #expect(!result.presentationIsCurrent())
    #expect(await model.shutdown()); await owner.shutdown()
  }

  @Test("Multi-file success and failure outcomes are operation local and only successes reveal", arguments: [["good", "bad", "good"], ["good", "bad"], ["bad"], []])
  func partialImport(files: [String]) async throws {
    let root = temporary(); defer { try? FileManager.default.removeItem(at: root) }
    let model = await opened(root), previous = model.currentPhotoRef
    let urls = files.enumerated().map { URL(fileURLWithPath: "/fixture/\($0.offset)-\($0.element).png") }
    let result = await FlowPhotoAcquisition.importPhotos(model: model, multiple: true, pick: { _ in urls }, read: { url in
      if url.lastPathComponent.contains("bad") { throw CocoaError(.fileReadCorruptFile) }
      return FlowAuthoringFixture.image(url.lastPathComponent.first == "0" ? 11 : 12)
    })
    #expect(result.photos.count == files.filter { $0 == "good" }.count)
    #expect(result.failures.count == files.filter { $0 == "bad" }.count)
    #expect(result.adopted == result.photos.last)
    #expect(model.currentPhotoRef == (result.photos.last ?? previous))
    let durable = await model.store?.snapshot()
    #expect(durable?.sources.count == 1 + result.photos.count)
    #expect(durable?.sources.first(where: { $0.id == durable?.selectedSourceID })?.photo == model.currentPhotoRef)
    #expect(await model.shutdown())
  }

  private func opened(_ root: URL) async -> FlowAuthoringModel {
    let model = FlowAuthoringModel(directory: root, purpose: .validationFixture, render: FlowAuthoringFixture.render)
    await model.open(); await model.addPhoto(data: FlowAuthoringFixture.image(1), title: "Initial source")
    return model
  }
  private func temporary() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString) }
  private func capturePhoto(_ value: Int) -> PortraitPhoto {
    PortraitPhoto(id: UUID(), data: FlowAuthoringFixture.image(value), label: "Capture", capturedAt: Date(),
      frameID: FrameID(), captureNanoseconds: UInt64(value), pose: .front)
  }
  private func writeCollection(_ folder: URL) throws {
    try FileManager.default.createDirectory(at: folder.appendingPathComponent("images"), withIntermediateDirectories: true)
    let image = FlowAuthoringFixture.image(13), hash = DrawingArtifactCoding.sha256(image)
    let filename = "images/" + hash + ".asset"
    try image.write(to: folder.appendingPathComponent(filename))
    let entry = FlowPhotoCollectionEntry(id: "photo", title: "Collection photo", filename: filename,
      sha256: hash, byteCount: image.count,
      sessionID: nil, provenanceJSON: Data("{}".utf8))
    let manifest = FlowPhotoCollectionManifest(schemaVersion: 1, id: "presentation-fixture", title: "Test collection", entries: [entry])
    try JSONEncoder().encode(manifest).write(to: folder.appendingPathComponent("photo-collection.json"))
  }
}

@MainActor private final class AcquisitionPresentationGate {
  private var didEnter = false
  private var waiting: CheckedContinuation<Void, Never>?
  private var enteredWaiters: [CheckedContinuation<Void, Never>] = []
  func holdOnce() async {
    guard !didEnter else { return }
    didEnter = true; enteredWaiters.forEach { $0.resume() }; enteredWaiters = []
    await withCheckedContinuation { waiting = $0 }
  }
  func entered() async {
    if didEnter { return }
    await withCheckedContinuation { enteredWaiters.append($0) }
  }
  func release() { waiting?.resume(); waiting = nil }
}

private extension DrawingLibrary {
  func failSecondAcquisitionPublication(_ selected: LibraryExchangeCatalogBoundary) throws {
    let catalog = try commonCatalog()
    var admissions = 0
    catalog.injectFault = { boundary in
      if boundary == .beforeSQLPublication { admissions += 1 }
      if admissions == 2, boundary == selected {
        throw DrawingLibraryError.unavailable("Injected unpublished acquisition selection failure")
      }
    }
  }
  func failAcquisitionCompensationAfterCommit() throws {
    let catalog = try commonCatalog()
    var armed = true
    catalog.injectFault = { boundary in
      if armed, boundary == .afterSQLCommit {
        armed = false
        throw DrawingLibraryError.unavailable("Injected stale-selection compensation persistence failure")
      }
    }
  }
  func clearAcquisitionCompensationFault() { cachedExchangeCatalog?.injectFault = nil }
}

private extension FlowPortfolioStore {
  func setAcquisitionAdmissionBusy(_ busy: Bool) { writeAdmissionActive = busy }
}
