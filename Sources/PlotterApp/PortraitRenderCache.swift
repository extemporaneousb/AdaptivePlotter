import Foundation
import PlotterModel

struct PortraitRenderConfiguration: Hashable {
  let style: PortraitStyle
  let vectors: PortraitVectorOptions
  let analysis: PortraitAnalysisOptions
}

struct PortraitRenderCacheKey: Hashable {
  let photoID: UUID
  let configuration: PortraitRenderConfiguration
  let strokeStyle: StrokeStyle
}

struct PortraitRasterCacheKey: Hashable {
  let photoID: UUID
  let analysis: PortraitAnalysisOptions
}

/// Studio-local LRU caches. Bounds apply to vectors and analysis independently;
/// removing a recent source also releases every cached version of that source.
struct PortraitRenderCache {
  static let maximumRenders = 24
  static let maximumPoints = 200_000
  static let maximumRasters = 32
  private(set) var renders: [(PortraitRenderCacheKey, PortraitRenderResult)] = []
  private var rasters: [(PortraitRasterCacheKey, PortraitRaster)] = []

  mutating func result(for key: PortraitRenderCacheKey) -> PortraitRenderResult? {
    guard let index = renders.firstIndex(where: { $0.0 == key }) else { return nil }
    let entry = renders.remove(at: index)
    renders.append(entry)
    return entry.1
  }

  mutating func raster(for key: PortraitRasterCacheKey) -> PortraitRaster? {
    guard let index = rasters.firstIndex(where: { $0.0 == key }) else { return nil }
    let entry = rasters.remove(at: index)
    rasters.append(entry)
    return entry.1
  }

  mutating func insert(_ result: PortraitRenderResult, for key: PortraitRenderCacheKey) {
    let rasterKey = PortraitRasterCacheKey(photoID: key.photoID, analysis: key.configuration.analysis)
    rasters.removeAll { $0.0 == rasterKey }
    rasters.append((rasterKey, result.raster))
    if rasters.count > Self.maximumRasters { rasters.removeFirst() }
    renders.removeAll { $0.0 == key }
    guard pointCount(result) <= Self.maximumPoints else { return }
    renders.append((key, result))
    while renders.count > Self.maximumRenders || renders.reduce(0, { $0 + pointCount($1.1) }) > Self.maximumPoints {
      renders.removeFirst()
    }
  }

  mutating func remove(photoID: UUID) {
    renders.removeAll { $0.0.photoID == photoID }
    rasters.removeAll { $0.0.photoID == photoID }
  }

  private func pointCount(_ result: PortraitRenderResult) -> Int {
    result.program.strokes.reduce(0) { $0 + $1.path.points.count }
  }
}
