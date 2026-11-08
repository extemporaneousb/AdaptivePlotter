@testable import PortraitArtists
@testable import PortraitStudioUI
import Foundation
import PlotterModel
import Testing
@testable import PlotterApp

@Suite("Portrait source browsing and cache identity")
struct PortraitBrowsingTests {




  @Test("render cache keys include analysis and pen style, and source removal invalidates every version")
  func cacheIdentityAndRemoval() throws {
    var cache = PortraitRenderCache()
    let source = UUID()
    let config = PortraitRenderConfiguration(style: .hatch, vectors: .init(), analysis: .init())
    let key = PortraitRenderCacheKey(photoID: source, configuration: config, strokeStyle: try portraitTestStyle())
    let raster = portraitTestRaster()
    let result = PortraitRenderResult(raster: raster, program: try PortraitVectorizer.program(
      from: raster, pose: .front, style: .hatch, strokeStyle: portraitTestStyle()))
    cache.insert(result, for: key)
    let otherPen = try StrokeStyle(nominalLineWidth: key.strokeStyle.nominalLineWidth + 1,
      penProfileID: key.strokeStyle.penProfileID)
    #expect(cache.result(for: .init(photoID: source, configuration: config, strokeStyle: otherPen)) == nil)
    var otherAnalysis = PortraitAnalysisOptions(); otherAnalysis.cropToFace = false
    #expect(cache.raster(for: .init(photoID: source, analysis: otherAnalysis)) == nil)
    #expect(cache.result(for: key)?.program == result.program)
    cache.remove(photoID: source)
    #expect(cache.result(for: key) == nil)
    #expect(cache.raster(for: .init(photoID: source, analysis: config.analysis)) == nil)
    for _ in 0..<40 {
      cache.insert(result, for: .init(photoID: UUID(), configuration: config, strokeStyle: key.strokeStyle))
    }
    #expect(cache.renders.count == PortraitRenderCache.maximumRenders)
    #expect(cache.renders.reduce(0) { total, item in
      total + item.1.program.strokes.reduce(0) { $0 + $1.path.points.count }
    } <= PortraitRenderCache.maximumPoints)
  }
}

private actor BrowsingRenderer: PortraitRendering {
  private(set) var calls = 0
  func render(_ request: PortraitRenderRequest) async throws -> PortraitRenderResult {
    calls += 1
    let basis = portraitTestRaster()
    let raster = request.cachedRaster ?? PortraitRaster(width: basis.width, height: basis.height,
      luminance: basis.luminance, provenance: "browsing-\(request.data.first ?? 0)",
      analysisSummary: "fixture")
    return PortraitRenderResult(raster: raster, program: try PortraitVectorizer.program(
      from: raster, pose: request.pose, style: request.style, strokeStyle: request.strokeStyle,
      vectorOptions: request.vectorOptions))
  }
}
