import Foundation
import PortraitArtists
import PlotterModel

func portraitPersistenceCandidate(seed: UInt64 = 42,
  lineage: PortraitCandidateLineage? = nil) throws -> PortraitCandidate {
  let extent = try PortraitSourceCropExtent(widthPixels: 40, heightPixels: 40)
  let raster = PortraitRaster(width: 40, height: 40,
    luminance: Array(repeating: 0.1, count: 1600), provenance: "exact-owned-fixture",
    analysisSummary: "retained analysis", sourceCropExtent: extent)
  let recipe = PortraitStyleRecipe(id: "persistence-\(seed)", title: "Hatch \(seed)", seed: seed,
    style: .hatch, vectorOptions: .init(hatchSpacing: 8), analysisOptions: .init())
  let stroke = try StrokeStyle(nominalLineWidth: 0.8,
    penProfileID: PenProfileID(UUID(uuidString: "00000000-0000-0000-0000-000000000001")!))
  let program = try PortraitVectorizer.program(from: raster, pose: .front,
    style: recipe.style, strokeStyle: stroke, vectorOptions: recipe.vectorOptions)
  return try PortraitCandidate(sourceData: Data([1, 2, 3, 4]), sourcePixelExtent: extent,
    raster: raster, recipe: recipe, program: program, photoID: UUID(), captureSessionID: UUID(), lineage: lineage)
}
