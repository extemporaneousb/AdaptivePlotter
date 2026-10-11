import Foundation
import PlotterModel

package struct PortraitRenderConfiguration: Hashable {
  package let style: PortraitStyle
  package let vectors: PortraitVectorOptions
  package let analysis: PortraitAnalysisOptions

  package init(style: PortraitStyle, vectors: PortraitVectorOptions, analysis: PortraitAnalysisOptions) {
    self.style = style
    self.vectors = vectors
    self.analysis = analysis
  }
}

package struct PortraitRenderCacheKey: Hashable {
  package let photoID: UUID
  package let configuration: PortraitRenderConfiguration
  package let strokeStyle: StrokeStyle

  package init(photoID: UUID, configuration: PortraitRenderConfiguration, strokeStyle: StrokeStyle) {
    self.photoID = photoID
    self.configuration = configuration
    self.strokeStyle = strokeStyle
  }
}

package struct PortraitRasterCacheKey: Hashable {
  package let photoID: UUID
  package let analysis: PortraitAnalysisOptions
  package var maximumDimension: Int = 160

  package init(photoID: UUID, analysis: PortraitAnalysisOptions, maximumDimension: Int = 160) {
    self.photoID = photoID
    self.analysis = analysis
    self.maximumDimension = maximumDimension
  }
}

/// Studio-local LRU caches. Bounds apply to vectors and analysis independently;
/// removing a recent source also releases every cached version of that source.
package struct PortraitRenderCache {
  package static let maximumRenders = 24
  package static let maximumPoints = 200_000
  package static let maximumRasters = 32
  package static let maximumFlowWorkspaces = 8
  package static let maximumFlowWorkspaceBytes = 64 * 1_024 * 1_024
  package static let maximumSourcePreparations = 8
  package static let maximumSourcePreparationBytes = 48 * 1_024 * 1_024
  private let sourceByteLimit: Int
  private let flowByteLimit: Int

  private struct SourceEntry {
    let preparation: PortraitSourcePreparation
    var photoIDs: Set<UUID>
  }
  private var sources: [SourceEntry] = []
  package private(set) var renders: [(PortraitRenderCacheKey, PortraitRenderResult)] = []
  private var rasters: [(PortraitRasterCacheKey, PortraitRaster)] = []
  private var flowWorkspaces: [(PortraitRasterCacheKey, PortraitFlowRenderer.Workspace)] = []
  package var flowWorkspaceCount: Int { flowWorkspaces.count }
  package var flowWorkspaceBytes: Int { flowWorkspaces.reduce(0) { $0 + $1.1.retainedByteCount } }
  package var sourcePreparationCount: Int { sources.count }
  package var sourcePreparationBytes: Int { sources.reduce(0) { $0 + $1.preparation.retainedByteCount } }

  package init(sourceByteLimit: Int = Self.maximumSourcePreparationBytes,
    flowByteLimit: Int = Self.maximumFlowWorkspaceBytes) {
    self.sourceByteLimit = max(0, sourceByteLimit)
    self.flowByteLimit = max(0, flowByteLimit)
  }

  package mutating func sourcePreparation(for photoID: UUID) -> PortraitSourcePreparation? {
    guard let index = sources.firstIndex(where: { $0.photoIDs.contains(photoID) }) else { return nil }
    let entry = sources.remove(at: index)
    sources.append(entry)
    return entry.preparation
  }

  package mutating func insertSourcePreparation(_ preparation: PortraitSourcePreparation, for photoID: UUID) {
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

  package mutating func flowWorkspace(for key: PortraitRasterCacheKey) -> PortraitFlowRenderer.Workspace? {
    guard let index = flowWorkspaces.firstIndex(where: { $0.0 == key }) else { return nil }
    let entry = flowWorkspaces.remove(at: index)
    flowWorkspaces.append(entry)
    return entry.1
  }

  package mutating func result(for key: PortraitRenderCacheKey) -> PortraitRenderResult? {
    guard let index = renders.firstIndex(where: { $0.0 == key }) else { return nil }
    let entry = renders.remove(at: index)
    renders.append(entry)
    return entry.1
  }

  package mutating func raster(for key: PortraitRasterCacheKey) -> PortraitRaster? {
    guard let index = rasters.firstIndex(where: { $0.0 == key }) else { return nil }
    let entry = rasters.remove(at: index)
    rasters.append(entry)
    return entry.1
  }

  package mutating func insert(_ result: PortraitRenderResult, for key: PortraitRenderCacheKey) {
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

  package mutating func remove(photoID: UUID) {
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
