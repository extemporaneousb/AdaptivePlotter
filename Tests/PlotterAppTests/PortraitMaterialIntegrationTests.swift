import DrawingLibrary
import Foundation
import PlotterModel
import PortraitArtists
import PortraitCore
import PortraitStudioUI
import Testing
@testable import PlotterApp

@Suite("Current Drawing material adaptation", .serialized)
@MainActor
struct PortraitMaterialIntegrationTests {
  @Test("Adaptation creates an exact child while retaining the original drawing and source")
  func immutableAdaptation() async throws {
    let library = DrawingFirstTestStorage.library()
    let model = PortraitStudioModel(library: library)
    let dojo = model.portfolioDojo(strokeStyle: try portraitTestStyle())
    await dojo.open()
    await dojo.addPhoto(data: try portraitTestImage(), title: "Synthetic material source")
    dojo.count = 3
    await dojo.generate(refining: false)
    let candidate = try #require(dojo.roundCandidates.first, "\(dojo.error ?? "No candidate")")
    await dojo.selectCandidate(candidate.id)
    #expect(dojo.error == nil, "\(dojo.error ?? "")")
    let parent = try await dojo.retainedDrawing()
    let reference = try #require(parent.reference)
    try await model.projectDrawing(parent)
    let originalProducer = parent.producer.originalJSON
    let profile = try DrawingMaterialProfileRevision(name: "Declared fixture width", nominalWidthMM: 1.2)
    let error = await model.applyMaterial(profile, drawingHeightMM: 20)
    #expect(error == nil, "\(error ?? "")")
    let adapted = try #require(model.currentDrawing)
    #expect(adapted.reference != reference)
    #expect(adapted.parent == .present(reference))
    #expect(adapted.program.contentHash != parent.program.contentHash)
    #expect(model.currentDrawingMaterialContext?.profile == profile)
    #expect(model.currentDrawingMaterialContext?.drawingHeightMM == 20)
    let unchanged = try await library.drawing(reference)
    #expect(unchanged.program == parent.program && unchanged.producer.originalJSON == originalProducer)
    #expect(unchanged.input == parent.input)
    await model.shutdown(); await library.closeLibrary()
  }
}
