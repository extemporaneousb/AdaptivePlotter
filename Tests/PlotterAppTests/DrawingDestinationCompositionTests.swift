import Foundation
import AppKit
import SwiftUI
@testable import DrawingLibrary
import PortraitCore
import PortraitLibrary
import PortraitStudioUI
import PlotterModel
import Testing
@testable import PlotterApp

@Suite("DX12 actual destination preparation", .serialized)
@MainActor struct DrawingDestinationCompositionTests {
  @Test("An uncalibrated destination shows the exact reference without issuing a plan")
  func unplacedReferencePreview() async throws {
    let fixture = try PlotterApplicationFixture()
    let app = fixture.application
    await app.performApplicationStartup(.init(arguments: [AdaptivePlotterLaunchPolicy.simulatedArgument, "YES"]))
    do {
      let drawing = try drawingTestValue(program: portraitPersistenceCandidate(seed: 413).program)
      let retained = try await app.receivedDrawings.sketches.retain(drawing, reason: "test-handoff")
      let ref = try #require(retained.reference)
      let reply = try await app.drawingDestination.handle(.prepare(ref))
      #expect(reply == .referencePreview(ref))
      let window = DestinationWindowBindings()
      #expect(window.presentation.reveal(.unplaced(ref), application: app))
      #expect(window.route.drawing == ref && window.route.workspace == .plotter)
      #expect(app.drawingDraftSnapshot.authoredProgram == drawing.program)
      #expect(app.drawingDraftSnapshot.plan == nil)
      #expect(await fixture.machine.requestedPenCommands.isEmpty)
      #expect(await fixture.machine.requestedDrawingStrokes.isEmpty)
      await app.shutdown()
    } catch { await app.shutdown(); throw error }
  }
  @Test("Cold recovery ignores obsolete reference receipts after a new document selection")
  func recoveryPreservesCurrentReferenceStatus() async throws {
    let fixture = try PlotterApplicationFixture()
    let app = fixture.application
    await app.performApplicationStartup(.init(arguments: [AdaptivePlotterLaunchPolicy.simulatedArgument, "YES"]))
    let root = app.receivedDrawings.library.directoryURL.appendingPathComponent("reference-recovery")
    let delegate = AdaptivePlotterApplicationDelegate(composition: .init(application: app), destinationRoot: root)
    let recovered = AdaptivePlotterApplicationDelegate(composition: .init(application: app), destinationRoot: root)
    let window = DestinationWindowBindings()
    for owner in [delegate, recovered] {
      owner.completeDrawingDestinationRestoration(window.presentation.revealAction(application: app))
    }
    do {
      let client = DrawingDestinationClient(library: app.receivedDrawings.library, root: root)
      var selected: DrawingRef?
      var latestRequest: URL?
      for seed: UInt64 in [413, 414] {
        let drawing = try drawingTestValue(program: portraitPersistenceCandidate(seed: seed).program)
        let ref = try await app.receivedDrawings.library.retain(drawing, reason: "reference-recovery").reference
        let delivery = try await client.enqueue(.prepare(ref), drawing: ref)
        let request = DrawingDestinationFiles.requestURL(root: root, client: delivery.client, delivery: delivery.id)
        delegate.application(NSApplication.shared, open: [request])
        latestRequest = request
        await delegate.settleDrawingDocuments()
        #expect(app.canShowUnplacedDrawing(ref))
        selected = ref
      }
      let currentStatus = app.drawingDestinationStatus
      #expect(window.route.drawing == selected)
      // Leave only the historical delivery in the recovery scan, so directory
      // enumeration order cannot hide an obsolete status overwrite.
      try FileManager.default.removeItem(at: #require(latestRequest))
      recovered.startDrawingDestinationRecovery()
      let deadline = ContinuousClock.now.advanced(by: .seconds(5))
      while recovered.drawingDestinationRecoveryScanCount == 0, ContinuousClock.now < deadline {
        try await Task.sleep(for: .milliseconds(5))
      }
      try #require(recovered.drawingDestinationRecoveryScanCount > 0)
      #expect(window.route.drawing == selected)
      #expect(app.drawingDestinationStatus == currentStatus)
      #expect(await fixture.machine.requestedPenCommands.isEmpty)
      #expect(await fixture.machine.requestedDrawingStrokes.isEmpty)
      await recovered.settleDrawingDestinationRecovery()
      await app.shutdown()
    } catch {
      await recovered.settleDrawingDestinationRecovery()
      await app.shutdown()
      throw error
    }
  }
  @Test("Cached refusals preserve current preview status while foreground and fresh recovery report refusals", arguments: [false, true])
  func cachedRefusalDoesNotReplaceStatus(missingResponseFile: Bool) async throws {
    let fixture = try PlotterApplicationFixture()
    let app = fixture.application
    await app.performApplicationStartup(.init(arguments: [AdaptivePlotterLaunchPolicy.simulatedArgument, "YES"]))
    let library = app.receivedDrawings.library
    let root = library.directoryURL.appendingPathComponent("refusal-recovery")
    let window = DestinationWindowBindings()
    do {
      let drawing = try drawingTestValue(program: portraitPersistenceCandidate(seed: 417).program)
      let ref = try await library.retain(drawing, reason: "refusal-recovery").reference
      #expect(try await app.drawingDestination.handle(.prepare(ref)) == .referencePreview(ref))
      #expect(window.presentation.reveal(.unplaced(ref), application: app))
      // A genuine destination refusal is retained by the real transport, while
      // the existing unplaced preview remains current.
      app.drawingDestination = DrawingDestinationService(library: library,
        returnDirectory: root.appendingPathComponent("results"), prepare: { _, _, _ in nil }, current: { _ in nil })
      let foreground = AdaptivePlotterApplicationDelegate(composition: .init(application: app), destinationRoot: root)
      let recovery = AdaptivePlotterApplicationDelegate(composition: .init(application: app), destinationRoot: root)
      for owner in [foreground, recovery] {
        owner.completeDrawingDestinationRestoration(window.presentation.revealAction(application: app))
      }
      let client = DrawingDestinationClient(library: library, root: root)
      let old = try await client.enqueue(.prepare(ref), drawing: ref)
      foreground.application(NSApplication.shared, open: [DrawingDestinationFiles.requestURL(root: root, client: old.client, delivery: old.id)])
      await foreground.settleDrawingDocuments()
      let refusalStatus = "The drawing could not be prepared. Review the destination preview and readiness."
      #expect(app.drawingDestinationStatus == refusalStatus)
      if missingResponseFile {
        guard case .description(let description) = try await app.drawingDestination.handle(.describe) else {
          throw DrawingDestinationRefusal.preparationUnavailable
        }
        try FileManager.default.removeItem(at: DrawingDestinationFiles.responseURL(root: root,
          engine: description.engine, client: old.client, delivery: old.id))
      }
      app.drawingDestinationStatus = "Current reference preview"
      recovery.startDrawingDestinationRecovery()
      let deadline = ContinuousClock.now.advanced(by: .seconds(5))
      while recovery.drawingDestinationRecoveryScanCount == 0, ContinuousClock.now < deadline {
        try await Task.sleep(for: .milliseconds(5))
      }
      await recovery.settleDrawingDestinationRecovery()
      #expect(recovery.drawingDestinationRecoveryScanCount > 0)
      #expect(app.drawingDestinationStatus == "Current reference preview")
      #expect(window.route.drawing == ref)
      _ = try await client.enqueue(.prepare(ref), drawing: ref)
      let scans = recovery.drawingDestinationRecoveryScanCount
      recovery.startDrawingDestinationRecovery()
      let freshDeadline = ContinuousClock.now.advanced(by: .seconds(5))
      while recovery.drawingDestinationRecoveryScanCount == scans, ContinuousClock.now < freshDeadline {
        try await Task.sleep(for: .milliseconds(5))
      }
      await recovery.settleDrawingDestinationRecovery()
      #expect(recovery.drawingDestinationRecoveryScanCount > scans)
      #expect(app.drawingDestinationStatus == refusalStatus)
      #expect(window.route.drawing == ref)
      #expect(await fixture.machine.requestedPenCommands.isEmpty)
      #expect(await fixture.machine.requestedDrawingStrokes.isEmpty)
      await app.shutdown()
    } catch { await app.shutdown(); throw error }
  }
  @Test("Existing projection-bound fake-port composition prepares without any Start or controller dispatch")
  func actualPrepare() async throws {
    let fixture = try await DrawingWorkbenchApplicationFixture.make()
    defer { fixture.stores.remove() }
    let app = fixture.application
    do {
      let beforePen = await fixture.machine.requestedPenCommands
      let beforeStrokes = await fixture.machine.requestedDrawingStrokes
      let program = try #require(app.drawingDraftSnapshot.authoredProgram)
      let drawing = try drawingTestValue(program: program)
      #expect(await app.prepareDestinationDrawing(drawing) == nil)
      let ref = try #require(app.receivedDrawings.projectedDrawing?.reference)
      guard case .prepared(let ticket) = try await app.drawingDestination.handle(.prepare(ref)) else {
        Issue.record("Real owner did not prepare a genuine plan"); await app.shutdown(); return
      }
      #expect(ticket.facts.planHash == ExchangeDigest(try #require(app.drawingDraftSnapshot.plan).contentHash))
      #expect(ticket.facts.draftRevision == app.drawingDraftSnapshot.projection.draftRevision.rawValue)
      guard case .description(let description) = try await app.drawingDestination.handle(.describe) else { Issue.record("Missing Describe"); return }
      #expect(description.executionAvailable && description.reason == nil)
      #expect(description.documentProfiles.contains(DrawingExchangeCodec.drawingProfile))
      #expect(description.representations == [DrawingExchangeCodec.strokeProfile])
      #expect(description.mediumMapping == .preserveAuthoredStyleAndCaptureCurrentApplicability)
      #expect(!description.acceptsOptionOverrides && !description.requiresNominalPenWidth)
      let key = DrawingRequestKey(namespace: UUID())
      guard case .decision(let decision) = try await app.drawingDestination.handle(.submit(key, ticket)) else { Issue.record("Missing refused job"); return }
      #expect(decision.reason == .nativePlotRequired)
      try await fixture.submit(.setRotationDegrees(5))
      let staleKey = DrawingRequestKey(namespace: key.namespace)
      #expect(try await app.drawingDestination.handle(.submit(staleKey, ticket)) == .refused(.stalePreview))
      #expect(try await app.drawingDestination.handle(.status(.request(staleKey))) == .refused(.stalePreview))
      #expect(try await app.drawingDestination.handle(.submit(key, ticket)) == .decision(decision))
      #expect(await fixture.planGate.request == nil)
      #expect(await fixture.machine.requestedPenCommands == beforePen)
      #expect(await fixture.machine.requestedDrawingStrokes == beforeStrokes)
      await app.drawingDestination.close()
      do { _ = try await app.drawingDestination.handle(.prepare(ref)); Issue.record("Closed destination admitted work") } catch {}
      await app.shutdown()
    } catch { await app.shutdown(); throw error }
  }
  @Test("Actual document ingress prepares only, reports failures and never dispatches")
  func documentIngress() async throws {
    let fixture = try await DrawingWorkbenchApplicationFixture.make()
    defer { fixture.stores.remove() }
    let app = fixture.application
    let root = app.receivedDrawings.sketches.library.directoryURL.appendingPathComponent("document-test")
    let delegate = AdaptivePlotterApplicationDelegate(composition: .init(application: app), destinationRoot: root)
    let window = DestinationWindowBindings()
    delegate.completeDrawingDestinationRestoration(window.presentation.revealAction(application: app))
    do {
      let drawing = try drawingTestValue(program: #require(app.drawingDraftSnapshot.authoredProgram))
      let retained = try await app.receivedDrawings.sketches.retain(drawing, reason: "document-test")
      let client = DrawingDestinationClient(library: app.receivedDrawings.sketches.library, root: root)
      let delivery = try await client.enqueue(.prepare(#require(retained.reference)), drawing: retained.reference)
      let url = DrawingDestinationFiles.requestURL(root: root, client: delivery.client, delivery: delivery.id)
      var foregrounds = 0
      delegate.restoreOperatorWindow = { foregrounds += 1 }
      delegate.application(NSApplication.shared, open: [url, url])
      await delegate.settleDrawingDocuments()
      #expect(app.receivedDrawings.projectedDrawing?.reference == retained.reference)
      #expect(foregrounds == 2)
      #expect(window.route.workspace == .plotter && window.route.drawing == retained.reference)
      #expect(window.layout.isPresented(.drawing) && !window.reviewer)
      #expect(app.drawingDestinationStatus == "Drawing prepared in the preview. Review it before choosing Draw.")
      #expect(await fixture.planGate.request == nil)
      #expect(try await app.receivedDrawings.sketches.library.records(kind: "adaptiveplotter.destination.job").isEmpty)
      let missing = root.appendingPathComponent("missing.zip")
      delegate.application(NSApplication.shared, open: [missing])
      await delegate.settleDrawingDocuments()
      #expect(app.drawingDestinationStatus?.hasPrefix("Drawing could not be opened:") == true)
      #expect(foregrounds == 2)
      await app.shutdown()
    } catch { await app.shutdown(); throw error }
  }
  @Test("Actual delegate relaunch recovers pending Prepare without an open event and ignores Submit")
  func delegatePendingRecovery() async throws {
    let fixture = try await DrawingWorkbenchApplicationFixture.make()
    defer { fixture.stores.remove() }
    let app = fixture.application
    let root = app.receivedDrawings.sketches.library.directoryURL.appendingPathComponent("recovery-test")
    let spool = root.appendingPathComponent("transport")
    let clientLibrary = DrawingLibrary(directoryURL: root.appendingPathComponent("client"))
    let client = DrawingDestinationClient(library: clientLibrary, root: spool)
    let oldDelegate = AdaptivePlotterApplicationDelegate(composition: .init(application: app), destinationRoot: spool)
    let relaunched = AdaptivePlotterApplicationDelegate(composition: .init(application: app), destinationRoot: spool)
    let replyRecovery = AdaptivePlotterApplicationDelegate(composition: .init(application: app), destinationRoot: spool)
    let staleRecovery = AdaptivePlotterApplicationDelegate(composition: .init(application: app), destinationRoot: spool)
    let window = DestinationWindowBindings()
    for owner in [oldDelegate, relaunched, replyRecovery, staleRecovery] {
      owner.completeDrawingDestinationRestoration(window.presentation.revealAction(application: app))
    }
    func uncachedModificationDate(_ url: URL) throws -> Date? {
      var fresh = URL(fileURLWithPath: url.path)
      fresh.removeAllCachedResourceValues()
      return try fresh.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }
    func waitFor(_ predicate: @MainActor () -> Bool) async throws {
      let deadline = ContinuousClock.now.advanced(by: .seconds(5))
      while !predicate(), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(5)) }
      try #require(predicate(), "Delegate recovery did not settle within five seconds")
    }
    do {
      #expect(app.drawingDestinationStartupHasSettled)
      let program = try #require(app.drawingDraftSnapshot.authoredProgram)
      let drawing = try drawingTestValue(program: program)
      #expect(await app.prepareDestinationDrawing(drawing) == nil)
      let engineRef = try #require(app.receivedDrawings.projectedDrawing?.reference)
      guard case .prepared(let ticket) = try await app.drawingDestination.handle(.prepare(engineRef)),
        case .description(let description) = try await app.drawingDestination.handle(.describe) else {
        Issue.record("Missing actual preparation"); await app.shutdown(); return
      }
      oldDelegate.startDrawingDestinationRecovery()
      try await waitFor { oldDelegate.drawingDestinationRecoveryScanCount > 0 }
      await oldDelegate.settleDrawingDestinationRecovery()
      // The originating client durably published before the engine lost the
      // document-open event. Replacement delegate startup is the only receiver.
      let selected = try await clientLibrary.retain(drawing, reason: "pending-relaunch").reference
      let pending = try await client.enqueue(.prepare(selected), drawing: selected)
      let key = DrawingRequestKey(namespace: pending.client)
      let planted = try await client.enqueue(.submit(key, ticket), engine: description.engine)
      let responseURL = DrawingDestinationFiles.responseURL(root: spool, engine: description.engine, client: pending.client, delivery: pending.id)
      let submitResponse = DrawingDestinationFiles.responseURL(root: spool, engine: description.engine, client: planted.client, delivery: planted.id)
      let beforePen = await fixture.machine.requestedPenCommands
      let beforeStrokes = await fixture.machine.requestedDrawingStrokes
      var foregrounds = 0
      relaunched.restoreOperatorWindow = { foregrounds += 1 }
      relaunched.startDrawingDestinationRecovery()
      try await waitFor { FileManager.default.fileExists(atPath: responseURL.path) }
      let response = try DrawingDestinationFiles.read(DrawingDestinationResponse.self, from: responseURL)
      guard case .prepared(let recoveredTicket) = response.reply else { throw DrawingDestinationRefusal.preparationUnavailable }
      try await window.waitForDrawing(selected)
      #expect(recoveredTicket.facts.drawing == selected)
      #expect(window.route.workspace == .plotter && window.route.drawing == selected)
      #expect(window.layout.isPresented(.drawing) && !window.reviewer)
      let retained = try await app.receivedDrawings.sketches.library.drawing(selected)
      #expect(retained.reference == selected && retained.program == drawing.program)
      #expect(retained.producer.originalJSON == drawing.producer.originalJSON && retained.units.nominalPenWidthMM == nil)
      let preparedCount = try await app.receivedDrawings.sketches.library.records(kind: "adaptiveplotter.destination.prepared").count
      let modification = try uncachedModificationDate(responseURL)
      window.route.workspace = .library; window.reviewer = true; window.layout.setPresented(.drawing, false)
      let scans = relaunched.drawingDestinationRecoveryScanCount
      try await waitFor { relaunched.drawingDestinationRecoveryScanCount > scans }
      #expect(try uncachedModificationDate(responseURL) == modification)
      #expect(window.route.workspace == .library && window.reviewer && !window.layout.isPresented(.drawing))
      #expect(try await app.receivedDrawings.sketches.library.records(kind: "adaptiveplotter.destination.prepared").count == preparedCount)
      #expect(!FileManager.default.fileExists(atPath: submitResponse.path))
      #expect(try await app.receivedDrawings.sketches.library.records(kind: key.recordKind).isEmpty)
      #expect(try await app.receivedDrawings.sketches.library.records(kind: "adaptiveplotter.destination.job").isEmpty)
      await relaunched.settleDrawingDestinationRecovery()
      try FileManager.default.removeItem(at: responseURL)
      try FileManager.default.removeItem(at: #require(pending.authoredCarrier))
      replyRecovery.restoreOperatorWindow = { foregrounds += 1 }
      replyRecovery.startDrawingDestinationRecovery()
      try await waitFor { FileManager.default.fileExists(atPath: responseURL.path) }
      #expect(try DrawingDestinationFiles.read(DrawingDestinationResponse.self, from: responseURL) == response)
      try await window.waitForDrawing(selected)
      #expect(window.route.workspace == .plotter && window.route.drawing == selected && window.layout.isPresented(.drawing))
      #expect(foregrounds == 0)
      #expect(await fixture.machine.requestedPenCommands == beforePen)
      #expect(await fixture.machine.requestedDrawingStrokes == beforeStrokes)
      #expect(await fixture.planGate.request == nil)
      await replyRecovery.settleDrawingDestinationRecovery()
      try await fixture.submit(.setRotationDegrees(2))
      window.route.workspace = .library; window.reviewer = true; window.layout.setPresented(.drawing, false)
      staleRecovery.restoreOperatorWindow = { foregrounds += 1 }
      app.drawingDestinationStatus = "Current drawing remains selected"
      staleRecovery.startDrawingDestinationRecovery()
      try await waitFor { staleRecovery.drawingDestinationRecoveryScanCount > 0 }
      #expect(!app.preparedDrawingIsCurrent(recoveredTicket))
      #expect(window.route.workspace == .library && window.reviewer && !window.layout.isPresented(.drawing))
      #expect(app.drawingDestinationStatus == "Current drawing remains selected")
      #expect(foregrounds == 0)
      await staleRecovery.settleDrawingDestinationRecovery()
      await clientLibrary.closeLibrary(); await app.shutdown()
    } catch {
      await oldDelegate.settleDrawingDestinationRecovery()
      await relaunched.settleDrawingDestinationRecovery()
      await replyRecovery.settleDrawingDestinationRecovery()
      await staleRecovery.settleDrawingDestinationRecovery()
      await clientLibrary.closeLibrary(); await app.shutdown(); throw error
    }
  }
  @Test("Pending Prepare waits for held saved-Photo restoration and then reveals its exact current preview", arguments: [false, true])
  func pendingPrepareAfterViewRestoration(explicitOpen: Bool) async throws {
    let fixture = try await DrawingWorkbenchApplicationFixture.make()
    defer { fixture.stores.remove() }
    let app = fixture.application
    let root = app.receivedDrawings.sketches.library.directoryURL.appendingPathComponent("held-view-restoration")
    let spool = root.appendingPathComponent("transport")
    let clientLibrary = DrawingLibrary(directoryURL: root.appendingPathComponent("client"))
    let client = DrawingDestinationClient(library: clientLibrary, root: spool)
    let delegate = AdaptivePlotterApplicationDelegate(composition: .init(application: app), destinationRoot: spool)
    let window = DestinationWindowBindings(), gate = DestinationRestorationGate()
    window.route.photo = .init(issuer: UUID(), revision: UUID(), digest: .hash(Data("saved Photo restoration fixture".utf8)))
    var restoration: Task<Void, Never>?
    defer { gate.release() }
    do {
      let program = try #require(app.drawingDraftSnapshot.authoredProgram)
      let restoredDrawing = try drawingTestValue(program: program)
      let selected = try await clientLibrary.retain(restoredDrawing, reason: "pending-after-restoration").reference
      let delivery = try await client.enqueue(.prepare(selected), drawing: selected)
      guard case .description(let description) = try await app.drawingDestination.handle(.describe) else { throw DrawingDestinationRefusal.invalidDelivery }
      let responseURL = DrawingDestinationFiles.responseURL(root: spool, engine: description.engine, client: delivery.client, delivery: delivery.id)
      let requestURL = DrawingDestinationFiles.requestURL(root: spool, client: delivery.client, delivery: delivery.id)
      let beforePen = await fixture.machine.requestedPenCommands
      let beforeStrokes = await fixture.machine.requestedDrawingStrokes
      var foregrounds = 0, restorationFailure: String?
      var restoredReference: DrawingRef?
      delegate.restoreOperatorWindow = { foregrounds += 1 }
      delegate.startDrawingDestinationRecovery()
      if explicitOpen { delegate.application(NSApplication.shared, open: [requestURL]) }
      restoration = Task {
        await gate.wait()
        restorationFailure = await app.projectDrawing(restoredDrawing)
        restoredReference = app.receivedDrawings.projectedDrawing?.reference
        delegate.completeDrawingDestinationRestoration(window.presentation.revealAction(application: app))
      }
      try await gate.waitUntilEntered()
      #expect(app.drawingDestinationStartupHasSettled)
      #expect(delegate.drawingDestinationRecoveryScanCount == 0)
      #expect(!FileManager.default.fileExists(atPath: responseURL.path))
      #expect(try await app.receivedDrawings.sketches.library.records(kind: "adaptiveplotter.destination.prepared").isEmpty)
      gate.release()
      await restoration?.value
      await delegate.settleDrawingDocuments()
      let deadline = ContinuousClock.now.advanced(by: .seconds(5))
      while !FileManager.default.fileExists(atPath: responseURL.path), ContinuousClock.now < deadline {
        try await Task.sleep(for: .milliseconds(5))
      }
      let response = try DrawingDestinationFiles.read(DrawingDestinationResponse.self, from: responseURL)
      guard case .prepared(let ticket) = response.reply else { throw DrawingDestinationRefusal.preparationUnavailable }
      try await window.waitForDrawing(selected)
      #expect(restorationFailure == nil && restoredReference != nil && restoredReference != selected)
      #expect(ticket.facts.drawing == selected && app.receivedDrawings.projectedDrawing?.reference == selected)
      #expect(ticket.facts.planHash == ExchangeDigest(try #require(app.drawingDraftSnapshot.plan).contentHash))
      #expect(app.preparedDrawingIsCurrent(ticket))
      #expect(window.route.workspace == .plotter && window.route.drawing == selected && window.route.photo == nil)
      #expect(window.layout.isPresented(.drawing) && !window.reviewer)
      #expect(foregrounds == (explicitOpen ? 1 : 0))
      #expect(await fixture.machine.requestedPenCommands == beforePen)
      #expect(await fixture.machine.requestedDrawingStrokes == beforeStrokes)
      #expect(await fixture.planGate.request == nil)
      #expect(try await app.receivedDrawings.sketches.library.records(kind: "adaptiveplotter.destination.job").isEmpty)
      await delegate.settleDrawingDestinationRecovery()
      await clientLibrary.closeLibrary(); await app.shutdown()
    } catch {
      gate.release(); await restoration?.value
      await delegate.settleDrawingDestinationRecovery(); await delegate.settleDrawingDocuments()
      await clientLibrary.closeLibrary(); await app.shutdown(); throw error
    }
  }
  @Test("Held real artifact work preserves UI admission and stale queued handoff cannot project")
  func heldArtifactAndQueuedHandoff() async throws {
    let fixture = try await DrawingWorkbenchApplicationFixture.make()
    defer { fixture.stores.remove() }
    let app = fixture.application, gate = DestinationArtifactGate()
    app.drawingDestination = DrawingDestinationComposition.make(app,
      returnDirectory: app.receivedDrawings.sketches.library.directoryURL.appendingPathComponent("destination-results"))
    defer { gate.release(); DrawingDestinationArtifactObservation.shared.install(nil) }
    do {
      let program = try #require(app.drawingDraftSnapshot.authoredProgram)
      #expect(await app.prepareDestinationDrawing(try drawingTestValue(program: program)) == nil)
      let ref = try #require(app.receivedDrawings.projectedDrawing?.reference)
      guard case .prepared(let ticket) = try await app.drawingDestination.handle(.prepare(ref)),
        case .decision(let decision) = try await app.drawingDestination.handle(.submit(.init(namespace: UUID()), ticket)) else {
        Issue.record("Missing genuine prepared refusal"); await app.shutdown(); return
      }
      DrawingDestinationArtifactObservation.shared.install { job, boundary in if job == decision.job.handle, boundary == .assemblyStarted { gate.hold() } }
      let export = Task { try await app.drawingDestination.handle(.exportResult(decision.job.handle)) }
      try await gate.waitUntilEntered()
      #expect(!gate.snapshot().mainThread)
      let prior = app.drawingDraftSnapshot
      var isCurrent = true
      let obsolete = Task { await app.prepareDestinationDrawing(try drawingTestValue(program: program), isStillCurrent: { isCurrent }) }
      let queueDeadline = ContinuousClock.now.advanced(by: .seconds(5))
      while app.drawingDestination.inFlightOperationCount < 2, ContinuousClock.now < queueDeadline {
        try await Task.sleep(for: .milliseconds(5))
      }
      #expect(app.drawingDestination.inFlightOperationCount == 2)
      isCurrent = false
      gate.release()
      _ = try await export.value
      #expect(try await obsolete.value != nil)
      #expect(app.drawingDraftSnapshot.projection.draftRevision == prior.projection.draftRevision)
      #expect(app.receivedDrawings.projectedDrawing?.reference == ref)
      #expect(await fixture.planGate.request == nil)
      await app.shutdown()
    } catch { gate.release(); await app.shutdown(); throw error }
  }
  @Test("Default Authoring handoff rejects an intervening selection or draft generation before queued projection", arguments: [false, true])
  func defaultAuthoringGeneration(draftChanged: Bool) async throws {
    let fixture = try await DrawingWorkbenchApplicationFixture.make()
    defer { fixture.stores.remove() }
    let app = fixture.application, gate = DestinationArtifactGate()
    let library = app.receivedDrawings.sketches.library
    defer { gate.release() }
    do {
      let program = try #require(app.drawingDraftSnapshot.authoredProgram)
      #expect(await app.prepareDestinationDrawing(try drawingTestValue(program: program)) == nil)
      // Hold the actual retained Drawing commit BEFORE the shared Prepare can
      // project it. A concurrent export no longer owns the service's FIFO.
      try await library.holdNextDrawingRetentionCommit(gate)
      let obsolete = Task { await app.prepareDestinationDrawing(try drawingTestValue(program: program)) }
      try await gate.waitUntilEntered()
      #expect(!gate.snapshot().mainThread)
      if draftChanged { try await fixture.submit(.setRotationDegrees(3)) }
      else { app.receivedDrawings.clearDrawingSelection() }
      let expectedRevision = app.drawingDraftSnapshot.projection.draftRevision
      let expectedProjection = app.receivedDrawings.projectedDrawing?.reference
      gate.release()
      #expect(try await obsolete.value != nil)
      await library.clearDestinationTicketCommitGate()
      #expect(app.drawingDraftSnapshot.projection.draftRevision == expectedRevision)
      #expect(app.receivedDrawings.projectedDrawing?.reference == expectedProjection)
      #expect(await fixture.planGate.request == nil)
      await app.shutdown()
    } catch { gate.release(); await library.clearDestinationTicketCommitGate(); await app.shutdown(); throw error }
  }
  @Test("Caller cancellation invalidates queued preparation before projection", arguments: [false, true])
  func preparationCallerLifetime(closePanel: Bool) async throws {
    let fixture = try await DrawingWorkbenchApplicationFixture.make()
    defer { fixture.stores.remove() }
    let app = fixture.application, gate = DestinationArtifactGate()
    app.drawingDestination = DrawingDestinationComposition.make(app,
      returnDirectory: app.receivedDrawings.sketches.library.directoryURL.appendingPathComponent("destination-results"))
    defer { gate.release(); DrawingDestinationArtifactObservation.shared.install(nil) }
    do {
      let program = try #require(app.drawingDraftSnapshot.authoredProgram)
      #expect(await app.prepareDestinationDrawing(try drawingTestValue(program: program)) == nil)
      let ref = try #require(app.receivedDrawings.projectedDrawing?.reference)
      guard case .prepared(let ticket) = try await app.drawingDestination.handle(.prepare(ref)),
        case .decision(let decision) = try await app.drawingDestination.handle(.submit(.init(namespace: UUID()), ticket)) else {
        Issue.record("Missing genuine refusal"); await app.shutdown(); return
      }
      DrawingDestinationArtifactObservation.shared.install { job, boundary in
        if job == decision.job.handle, boundary == .assemblyStarted { gate.hold() }
      }
      let export = Task { try await app.drawingDestination.handle(.exportResult(decision.job.handle)) }
      try await gate.waitUntilEntered()
      var route = DrawingLibraryRoute(); route.workspace = .drawingStudio
      var layout = WorkbenchLayoutState(presented: [.drawing])
      let before = app.drawingDraftSnapshot.projection.draftRevision
      let handoff = Task {
        await app.prepareDestinationDrawingOutcome(try drawingTestValue(program: program), isStillCurrent: {
          route.workspace == .drawingStudio && layout.isPresented(.drawing)
        })
      }
      let deadline = ContinuousClock.now.advanced(by: .seconds(5))
      while app.drawingDestination.inFlightOperationCount < 2, ContinuousClock.now < deadline {
        try await Task.sleep(for: .milliseconds(5))
      }
      #expect(app.drawingDestination.inFlightOperationCount == 2)
      if closePanel { layout.setPresented(.drawing, false) }
      else { route.workspace = .library }
      let desiredRoute = route
      gate.release()
      _ = try await export.value
      let handoffResult = try await handoff.value
      if case .preview = handoffResult { Issue.record("Canceled caller adopted a queued preparation") }
      #expect(route == desiredRoute)
      #expect(app.drawingDraftSnapshot.projection.draftRevision == before)
      #expect(app.receivedDrawings.projectedDrawing?.reference == ref)
      #expect(await fixture.planGate.request == nil)
      await app.shutdown()
    } catch { gate.release(); await app.shutdown(); throw error }
  }
  @Test("Destination reveal keeps the exact ticket across a held real Library commit")
  func destinationTicketCommitRace() async throws {
    let fixture = try await DrawingWorkbenchApplicationFixture.make()
    defer { fixture.stores.remove() }
    let app = fixture.application, gate = DestinationArtifactGate(), window = DestinationWindowBindings()
    let library = app.receivedDrawings.sketches.library
    defer { gate.release() }
    do {
      #expect(await app.prepareDestinationDrawing(try drawingTestValue(program: #require(app.drawingDraftSnapshot.authoredProgram))) == nil)
      let reference = try #require(app.receivedDrawings.projectedDrawing?.reference)
      let drawing = try await library.drawing(reference)
      try await library.holdNextDestinationTicketCommit(gate)
      var shows = 0
      let handoff = Task {
        let outcome = await app.prepareDestinationDrawingOutcome(drawing)
        if case .preview(let preview) = outcome, window.presentation.reveal(preview, application: app) { shows += 1; return nil as String? }
        return "Preparation changed."
      }
      try await gate.waitUntilEntered()
      // This does not change workspace, selection or source identity. It changes
      // the real live plan while the already-frozen ticket waits on SQL commit.
      try await fixture.submit(.setRotationDegrees(4))
      let current = app.drawingDraftSnapshot
      gate.release()
      #expect(await handoff.value != nil)
      #expect(shows == 0 && window.route.workspace == .drawingStudio)
      #expect(app.drawingDraftSnapshot.projection.draftRevision == current.projection.draftRevision)
      #expect(app.drawingDraftSnapshot.plan?.contentHash == current.plan?.contentHash)
      #expect(app.receivedDrawings.projectedDrawing?.reference == reference)
      #expect(try await library.records(kind: "adaptiveplotter.destination.job").isEmpty)
      #expect(await fixture.planGate.request == nil)
      await library.clearDestinationTicketCommitGate()
      await app.shutdown()
    } catch {
      gate.release(); await library.clearDestinationTicketCommitGate(); await app.shutdown(); throw error
    }
  }
  @Test("Root shutdown closes physical ingress before joining held destination return")
  func shutdownDuringArtifact() async throws {
    let fixture = try await DrawingWorkbenchApplicationFixture.make()
    defer { fixture.stores.remove() }
    let app = fixture.application, gate = DestinationArtifactGate()
    app.drawingDestination = DrawingDestinationComposition.make(app,
      returnDirectory: app.receivedDrawings.sketches.library.directoryURL.appendingPathComponent("destination-results"))
    defer { gate.release(); DrawingDestinationArtifactObservation.shared.install(nil) }
    do {
      #expect(await app.prepareDestinationDrawing(try drawingTestValue(program: #require(app.drawingDraftSnapshot.authoredProgram))) == nil)
      let ref = try #require(app.receivedDrawings.projectedDrawing?.reference)
      guard case .prepared(let ticket) = try await app.drawingDestination.handle(.prepare(ref)),
        case .decision(let decision) = try await app.drawingDestination.handle(.submit(.init(namespace: UUID()), ticket)) else {
        Issue.record("Missing genuine prepared refusal"); await app.shutdown(); return
      }
      DrawingDestinationArtifactObservation.shared.install { job, boundary in if job == decision.job.handle, boundary == .assemblyStarted { gate.hold() } }
      let export = Task { try await app.drawingDestination.handle(.exportResult(decision.job.handle)) }
      try await gate.waitUntilEntered()
      let request = try #require(app.testPlotterUIProjection().semantic.request(for: PlotterAppUIActionID.drawingDraft(.setRotationDegrees(10))))
      let priorStrokes = await fixture.machine.requestedDrawingStrokes
      let shutdown = Task { await app.shutdown() }
      let deadline = ContinuousClock.now.advanced(by: .seconds(5))
      while !app.artifactResetEpisodeSnapshot.admissionClosed, ContinuousClock.now < deadline {
        try await Task.sleep(for: .milliseconds(5))
      }
      #expect(app.artifactResetEpisodeSnapshot.admissionClosed)
      if case .refused(let refusal) = await app.submitPlotterUIRequest(request) {
        #expect(refusal.reason == .retainedOwnerRefused)
      } else { Issue.record("Root ingress remained open while return publication was held") }
      #expect(await fixture.machine.requestedDrawingStrokes == priorStrokes)
      #expect(await fixture.planGate.request == nil)
      gate.release()
      _ = try await export.value
      await shutdown.value
    } catch { gate.release(); await app.shutdown(); throw error }
  }

  @Test("Actual quit drains a held document Prepare without adopting its late preview or status")
  func quitSuppressesLateDocumentPresentation() async throws {
    let fixture = try await DrawingWorkbenchApplicationFixture.make()
    defer { fixture.stores.remove() }
    let app = fixture.application, gate = DestinationArtifactGate()
    let library = app.receivedDrawings.sketches.library
    let root = library.directoryURL.appendingPathComponent("quit-document")
    let delegate = AdaptivePlotterApplicationDelegate(composition: .init(application: app), destinationRoot: root)
    let window = DestinationWindowBindings()
    delegate.completeDrawingDestinationRestoration(window.presentation.revealAction(application: app))
    var replies: [Bool] = [], foregrounds = 0
    delegate.replyToTermination = { _, accepted in replies.append(accepted) }
    delegate.restoreOperatorWindow = { foregrounds += 1 }
    defer { gate.release() }
    do {
      let drawing = try drawingTestValue(program: #require(app.drawingDraftSnapshot.authoredProgram))
      let retained = try await library.retain(drawing, reason: "quit-document")
      let document = root.appendingPathComponent("Drawing.drawingexchange")
      try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
      try await library.exportDrawing(retained.reference, to: document)
      try await library.holdNextDestinationTicketCommit(gate)
      delegate.application(NSApplication.shared, open: [document])
      try await gate.waitUntilEntered()
      let route = window.route
      app.drawingDestinationStatus = "Closing document fixture"
      #expect(delegate.applicationShouldTerminate(NSApplication.shared) == .terminateLater)
      await Task.yield()
      #expect(replies.isEmpty)
      gate.release()
      await delegate.settleDrawingDocuments()
      let deadline = ContinuousClock.now.advanced(by: .seconds(5))
      while replies.isEmpty, ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(5)) }
      #expect(replies == [true])
      #expect(window.route == route && foregrounds == 0)
      #expect(app.drawingDestinationStatus == "Closing document fixture")
      #expect(try await library.drawing(retained.reference).reference == retained.reference)
      #expect(try await library.records(kind: "adaptiveplotter.destination.prepared").count == 1)
      #expect(await fixture.planGate.request == nil)
      await library.clearDestinationTicketCommitGate()
      await library.closeLibrary()
    } catch {
      gate.release(); await delegate.settleDrawingDocuments()
      await library.clearDestinationTicketCommitGate(); await app.shutdown(); throw error
    }
  }

}

final class DestinationArtifactGate: @unchecked Sendable {
  private let condition = NSCondition()
  private var entered = false
  private var released = false
  private var observedMainThread = false
  func hold() {
    condition.lock(); entered = true; observedMainThread = Thread.isMainThread
    let deadline = Date().addingTimeInterval(20)
    while !released { if !condition.wait(until: deadline) { break } }
    condition.unlock()
  }
  func snapshot() -> (entered: Bool, mainThread: Bool) {
    condition.lock(); defer { condition.unlock() }; return (entered, observedMainThread)
  }
  @MainActor func waitUntilEntered() async throws {
    let deadline = ContinuousClock.now.advanced(by: .seconds(5))
    while !snapshot().entered, ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(5)) }
    try #require(snapshot().entered, "Artifact worker did not enter within five seconds")
  }
  func release() { condition.lock(); released = true; condition.broadcast(); condition.unlock() }
}

@MainActor private final class DestinationWindowBindings {
  var route = DrawingLibraryRoute()
  var layout = WorkbenchLayoutState(presented: [.drawing])
  var reviewer = false
  init() { route.workspace = .drawingStudio }
  func waitForDrawing(_ reference: DrawingRef) async throws {
    func matches() -> Bool { route.workspace == .plotter && route.drawing == reference && layout.isPresented(.drawing) && !reviewer }
    let deadline = ContinuousClock.now.advanced(by: .seconds(5))
    while !matches(), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(5)) }
    try #require(matches(), "The matching prepared Drawing was not revealed within five seconds")
  }
  var presentation: DrawingDestinationWindowPresentation {
    .init(layout: Binding(get: { self.layout }, set: { self.layout = $0 }), didReveal: { reference in
      self.route.workspace = .plotter
      if let reference { self.route.showDrawing(reference) }
      self.reviewer = false
    })
  }
}
@MainActor private final class DestinationRestorationGate {
  private var entered = false
  private var released = false
  private var continuation: CheckedContinuation<Void, Never>?
  func wait() async { entered = true; if !released { await withCheckedContinuation { continuation = $0 } } }
  func waitUntilEntered() async throws {
    let deadline = ContinuousClock.now.advanced(by: .seconds(5))
    while !entered, ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(5)) }
    try #require(entered, "Saved-Photo restoration did not enter within five seconds")
  }
  func release() { released = true; let pending = continuation; continuation = nil; pending?.resume() }
}

private extension DrawingLibrary {
  func holdNextDestinationTicketCommit(_ gate: DestinationArtifactGate) throws {
    let catalog = try commonCatalog()
    let sql = "SELECT COUNT(*) FROM domain_record WHERE kind='adaptiveplotter.destination.prepared'"
    let before = Int(try catalog.database.scalar(sql) ?? "0") ?? 0
    var armed = true
    catalog.injectFault = { boundary in
      guard armed, boundary == .beforeSQLCommit else { return }
      let count = Int(try catalog.database.scalar(sql) ?? "0") ?? 0
      if count > before { armed = false; gate.hold() }
    }
  }
  func holdNextDrawingRetentionCommit(_ gate: DestinationArtifactGate) throws {
    let catalog = try commonCatalog()
    let sql = "SELECT COUNT(*) FROM dx_retention_intent"
    let before = Int(try catalog.database.scalar(sql) ?? "0") ?? 0
    var armed = true
    catalog.injectFault = { boundary in
      guard armed, boundary == .beforeSQLCommit else { return }
      let count = Int(try catalog.database.scalar(sql) ?? "0") ?? 0
      if count > before { armed = false; gate.hold() }
    }
  }
  func clearDestinationTicketCommitGate() { cachedExchangeCatalog?.injectFault = nil }
}
