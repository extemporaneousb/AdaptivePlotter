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
    let authoring = FlowAuthoringModel(library: library, strokeStyle: try portraitTestStyle())
    await authoring.open()
    await authoring.addPhoto(data: try portraitTestImage(), title: "Synthetic material source")
    authoring.count = 3
    await authoring.generate(refining: false)
    let candidate = try #require(authoring.roundCandidates.first, "\(authoring.error ?? "No candidate")")
    await authoring.selectCandidate(candidate.id)
    #expect(authoring.error == nil, "\(authoring.error ?? "")")
    let parent = try await authoring.retainedDrawing()
    let reference = try #require(parent.reference)
    try await model.projectDrawing(parent)
    let originalProducer = parent.producer.originalJSON
    let profile = try DrawingMaterialProfileRevision(name: "Declared fixture width", nominalWidthMM: 1.2)
    let error = await model.applyMaterial(profile, drawingHeightMM: 20, authoring: authoring)
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
    _ = await authoring.shutdown(); await model.shutdown(); await library.closeLibrary()
  }
}
