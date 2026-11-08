import Foundation
import DrawingLibrary
import PlotterModel
import PortraitCore
import PortraitLibrary
import PortraitStudioUI
import Testing
@testable import PlotterApp

@Suite("DX08 embedded shared browser route", .serialized)
@MainActor
struct DrawingTransferRouteTests {
  @Test("Actual embedded browser sends its edited exact child through Prepare across its own selection publication")
  func editedChildHandoff() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("dx08-app-route-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let library = DrawingLibrary(directoryURL: root)
    let studio = PortraitStudioModel(library: library)
    // Existing software-only composition: fake camera/controller/stores. No
    // physical pose verification, Draw, Run or Start action is requested here.
    let fixture = try await DrawingWorkbenchApplicationFixture.make(portraitStudio: studio, verifyPhysicalPose: false)
    defer { fixture.stores.remove() }
    let app = fixture.application
    do {
      let route = DrawingTransferView(application: app, close: {})
      let shared = route.browser
      #expect(shared.sketches === studio.sketches)
      let handoff = try #require(shared.handoff)
      let production = try await CatalogDrawingProducer().produce(input: .metricSquare40, settings: .init(style: app.drawingStrokeStyle))
      #expect(production.drawing.units.nominalPenWidthMM == nil && production.drawing.input == .none)
      let parent = try await studio.sketches.retain(production.drawing, reason: "explicit-save")
      let parentRef = try #require(parent.reference)
      let browser = DrawingLibraryBrowserModel(sketches: shared.sketches)
      await browser.select(parentRef).value
      let editor = try #require(browser.beginEdit())
      await editor.load()
      editor.remove([try #require(parent.program.strokes.first).id])
      #expect(await editor.save())
      let child = try #require(editor.savedDrawing), childRef = try #require(child.reference)
      #expect(child.parent == .present(parentRef))
      #expect(browser.finishEdit(editor))
      let epoch = studio.sketches.selectionEpoch
      let records = app.drawingEvidenceArchive.records
      await browser.sendSelected(using: handoff)
      #expect(browser.error == nil)
      #expect(studio.sketches.selectionEpoch > epoch)
      #expect(studio.sketches.selected?.reference == childRef)
      #expect(studio.projectedDrawing?.reference == childRef)
      #expect(app.drawingDraftSnapshot.authoredProgram == child.program)
      #expect(app.drawingRunSnapshot?.activeRunID == nil)
      #expect(app.drawingEvidenceArchive.records == records)
      browser.close()
      await app.shutdown(); await library.closeLibrary()
    } catch {
      await app.shutdown(); await library.closeLibrary()
      throw error
    }
  }
}
