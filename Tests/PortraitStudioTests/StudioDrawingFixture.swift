import Foundation
import DrawingLibrary
import PlotterModel
import PortraitArtists
import PortraitCore
@testable import PortraitLibrary

/// Fresh disposable owners and explicitly synthetic artifacts; no historical format adapter.
enum StudioDrawingFixture {
  static func store(directory: URL, purpose: FlowPortfolioPurpose? = nil) async throws -> FlowPortfolioStore {
    let store = FlowPortfolioStore(directory: directory, purpose: purpose)
    try await store.loadRecords()
    return store
  }
  static func production(program: DrawingProgram, raster: PortraitRaster) throws -> DrawingProduction<PortraitRenderResult> {
    let receipt = try DrawingProducerReceipt(id: "example.studio-fixture", version: "1", recordJSON: Data("{\"origin\":\"synthetic-test-geometry\"}".utf8))
    return .init(drawing: try Drawing(program: program, input: .unavailable(reason: "Synthetic fixture has no source preparation facts", knownRef: nil), parent: .none, producer: receipt),
      artifacts: .init(raster: raster, program: program))
  }
}
