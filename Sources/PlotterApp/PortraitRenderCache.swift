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
  var maximumDimension: Int = 160
}

/// Studio-local LRU caches. Bounds apply to vectors and analysis independently;
/// removing a recent source also releases every cached version of that source.
struct PortraitRenderCache {
  static let maximumRenders = 24
  static let maximumPoints = 200_000
  static let maximumRasters = 32
  static let maximumFlowWorkspaces = 8
  static let maximumFlowWorkspaceBytes = 64 * 1_024 * 1_024
  static let maximumSourcePreparations = 8
  static let maximumSourcePreparationBytes = 48 * 1_024 * 1_024
  private let sourceByteLimit: Int
  private let flowByteLimit: Int

  private struct SourceEntry {
    let preparation: PortraitSourcePreparation
    var photoIDs: Set<UUID>
  }
  private var sources: [SourceEntry] = []
  private(set) var renders: [(PortraitRenderCacheKey, PortraitRenderResult)] = []
  private var rasters: [(PortraitRasterCacheKey, PortraitRaster)] = []
  private var flowWorkspaces: [(PortraitRasterCacheKey, PortraitFlowRenderer.Workspace)] = []
  var flowWorkspaceCount: Int { flowWorkspaces.count }
  var flowWorkspaceBytes: Int { flowWorkspaces.reduce(0) { $0 + $1.1.retainedByteCount } }
  var sourcePreparationCount: Int { sources.count }
  var sourcePreparationBytes: Int { sources.reduce(0) { $0 + $1.preparation.retainedByteCount } }

  init(sourceByteLimit: Int = Self.maximumSourcePreparationBytes,
    flowByteLimit: Int = Self.maximumFlowWorkspaceBytes) {
    self.sourceByteLimit = max(0, sourceByteLimit)
    self.flowByteLimit = max(0, flowByteLimit)
  }

  mutating func sourcePreparation(for photoID: UUID) -> PortraitSourcePreparation? {
    guard let index = sources.firstIndex(where: { $0.photoIDs.contains(photoID) }) else { return nil }
    let entry = sources.remove(at: index)
    sources.append(entry)
    return entry.preparation
  }

  mutating func insertSourcePreparation(_ preparation: PortraitSourcePreparation, for photoID: UUID) {
    // One immutable image preparation may be shared by multiple retained photos.
    // Replacing bytes under a photo identity invalidates that association first.
    for index in sources.indices { sources[index].photoIDs.remove(photoID) }
    sources.removeAll { $0.photoIDs.isEmpty && $0.preparation.key != preparation.key }
    if let index = sources.firstIndex(where: { $0.preparation.key == preparation.key }) {
      var entry = sources.remove(at: index)
      entry.photoIDs.insert(photoID)
      sources.append(entry)
    } else if preparation.retainedByteCount <= sourceByteLimit {
      sources.append(SourceEntry(preparation: preparation, photoIDs: [photoID]))
    }
    while sources.count > Self.maximumSourcePreparations || sourcePreparationBytes > sourceByteLimit {
      sources.removeFirst()
    }
  }

  mutating func flowWorkspace(for key: PortraitRasterCacheKey) -> PortraitFlowRenderer.Workspace? {
    guard let index = flowWorkspaces.firstIndex(where: { $0.0 == key }) else { return nil }
    let entry = flowWorkspaces.remove(at: index)
    flowWorkspaces.append(entry)
    return entry.1
  }

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
    if let source = result.preparedSource { insertSourcePreparation(source, for: key.photoID) }
    let rasterKey = PortraitRasterCacheKey(photoID: key.photoID, analysis: key.configuration.analysis,
      maximumDimension: PortraitImageAnalyzer.analysisMaximumDimension(for: key.configuration.style))
    rasters.removeAll { $0.0 == rasterKey }
    rasters.append((rasterKey, result.raster))
    if rasters.count > Self.maximumRasters { rasters.removeFirst() }
    if let workspace = result.flowWorkspace {
      flowWorkspaces.removeAll { $0.0 == rasterKey }
      if workspace.retainedByteCount <= flowByteLimit { flowWorkspaces.append((rasterKey, workspace)) }
      while flowWorkspaces.count > Self.maximumFlowWorkspaces || flowWorkspaceBytes > flowByteLimit {
        flowWorkspaces.removeFirst()
      }
    }
    renders.removeAll { $0.0 == key }
    guard pointCount(result) <= Self.maximumPoints else { return }
    // Heavy preparation has independent byte-bounded LRUs. The 24 final
    // drawing variants must not keep evicted source or Flow buffers alive.
    var retained = result
    retained.flowWorkspace = nil
    retained.preparedSource = nil
    renders.append((key, retained))
    while renders.count > Self.maximumRenders || renders.reduce(0, { $0 + pointCount($1.1) }) > Self.maximumPoints {
      renders.removeFirst()
    }
  }

  mutating func remove(photoID: UUID) {
    renders.removeAll { $0.0.photoID == photoID }
    rasters.removeAll { $0.0.photoID == photoID }
    flowWorkspaces.removeAll { $0.0.photoID == photoID }
    for index in sources.indices { sources[index].photoIDs.remove(photoID) }
    sources.removeAll { $0.photoIDs.isEmpty }
  }

  private func pointCount(_ result: PortraitRenderResult) -> Int {
    result.program.strokes.reduce(0) { $0 + $1.path.points.count }
  }
}
