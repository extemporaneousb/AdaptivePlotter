import Foundation
import PlotterEpisodeRuntime
import PlotterModel
import PlotterRuntime
import PlotterUI
import PortraitCore
import Testing
@testable import PortraitLibrary
@testable import PortraitStudioUI
@testable import PlotterApp

@Suite("Drawing transfer at the pre-motion boundary", .serialized)
@MainActor
struct DrawingTransferAdmissionTests {
  @Test("Raw staging freezes exact origin; replacing or deleting equal geometry withdraws admission")
  func exactOriginAdmission() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let studio = PortraitStudioModel(candidateStore: .init(directoryURL: directory))
    let fixture = try await DrawingWorkbenchApplicationFixture.make(portraitStudio: studio)
    defer { fixture.stores.remove() }
    let app = fixture.application
    do {
      let first = try transferTestPackage(), second = try transferTestPackage(programOverride: first.program)
      let firstDrawing = try await studio.sketches.importDrawingPackage(DrawingPackageCodec.encode(first))
      #expect(await app.projectSavedDrawing(firstDrawing) == nil)
      try await fixture.submit(.assertPaperCoverage)
      let intent = try await makeIntent(app)
      #expect(intent.context.candidate?.origin == first.origin)
      let staged = try await fixture.stores.evidencePort.stageIntent(intent)
      #expect(staged.attempts.first { $0.intent.runID == intent.runID }?.intent.context.candidate?.origin == first.origin)
      let penCommands = await fixture.machine.requestedPenCommands
      try await app.retainDrawingCandidateForAttempt(intent)
      let replacement = try await studio.sketches.importDrawingPackage(DrawingPackageCodec.encode(second))
      #expect(await app.projectSavedDrawing(replacement) == nil)
      #expect(app.drawingDraftSnapshot.program == intent.context.program)
      await #expect(throws: (any Error).self) { try await app.retainDrawingCandidateForAttempt(intent) }
      studio.sketches.remove(replacement.id)
      #expect(studio.sketches.drawingWasDeleted(replacement))
      #expect(app.savedDrawingReference(for: intent.context.program) == nil)
      let facts = await app.currentDrawingRunFacts(for: .live)
      #expect(facts.plan?.candidate == nil)
      #expect(await fixture.machine.requestedPenCommands == penCommands)
      #expect(await fixture.planGate.request == nil)
      await app.shutdown()
    } catch { await app.shutdown(); throw error }
  }

  @Test("Missing complete retained package refuses the actual pre-motion retention hook")
  func missingDurablePackage() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let studio = PortraitStudioModel(candidateStore: .init(directoryURL: directory))
    let fixture = try await DrawingWorkbenchApplicationFixture.make(portraitStudio: studio)
    defer { fixture.stores.remove() }
    let app = fixture.application
    do {
      let bytes = try DrawingPackageCodec.encode(transferTestPackage())
      let drawing = try await studio.sketches.importDrawingPackage(bytes)
      #expect(await app.projectSavedDrawing(drawing) == nil)
      try await fixture.submit(.assertPaperCoverage)
      let intent = try await makeIntent(app)
      _ = try await fixture.stores.evidencePort.stageIntent(intent)
      let payload = directory.appendingPathComponent("transfers")
        .appendingPathComponent(DrawingPackageCodec.sha256(bytes) + ".json")
      try FileManager.default.removeItem(at: payload)
      let penCommands = await fixture.machine.requestedPenCommands
      await #expect(throws: (any Error).self) { try await app.retainDrawingCandidateForAttempt(intent) }
      #expect(!FileManager.default.fileExists(atPath: payload.path))
      #expect(await fixture.machine.requestedPenCommands == penCommands)
      #expect(await fixture.planGate.request == nil)
      await app.shutdown()
    } catch { await app.shutdown(); throw error }
  }

  @Test("Source-free draft retention remains stable across fresh authored projection dates")
  func genericDraftRetention() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let studio = PortraitStudioModel(candidateStore: .init(directoryURL: directory))
    let fixture = try await DrawingWorkbenchApplicationFixture.make(portraitStudio: studio)
    defer { fixture.stores.remove() }
    let app = fixture.application
    do {
      let program = try DrawingProgramCatalog.program(for: .square, style: portraitTestStyle())
      let projection = app.plotterUIProjection(selectedItemID: app.testCurrentLearningPathItemID,
        manualDraft: ManualMotionDraft(), includesLearningPath: true, pendingDrawingProgram: program)
      let select = try #require(projection.semantic.request(matching: .drawingDraft(.selectProgram(program))))
      #expect(await app.submitPlotterUIRequest(select) == .accepted(requestID: select.id))
      try await fixture.submit(.fitInDrawableRegion)
      try await fixture.submit(.assertPaperCoverage)
      #expect(studio.projectedDrawing == nil)
      let intent = try await makeIntent(app)
      #expect(intent.context.candidate?.origin == nil)
      _ = try await fixture.stores.evidencePort.stageIntent(intent)
      try await app.retainDrawingCandidateForAttempt(intent)
      let saved = try #require(studio.sketches.sketches.first { $0.id == intent.context.candidate?.candidateID })
      try await app.retainDrawingCandidateForAttempt(intent)
      #expect(studio.sketches.sketches.first { $0.id == saved.id } == saved)
      #expect(await fixture.planGate.request == nil)
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
