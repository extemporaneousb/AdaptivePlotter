import CoreGraphics
import Foundation
import PlotterModel
import Testing
@testable import PlotterApp

@Suite("Flow shared preparation and mixed geometry")
struct PortraitFlowCacheTests {
  @Test("Bounded buffer kernels handle tiny and asymmetric lattices deterministically")
  func tinyLattices() throws {
    for (width, height) in [(3, 3), (4, 4), (5, 5), (3, 17), (17, 3), (5, 17), (17, 5)] {
      let luminance = (0..<(width * height)).map { Double(($0 % width + $0 / width) % 3) / 3 }
      let raster = PortraitRaster(width: width, height: height, luminance: luminance,
        provenance: "tiny-buffer-fixture", analysisSummary: "Synthetic border coverage")
      for coherence in [0.0, 4.0] {
        var options = PortraitVectorOptions.flowDefaults
        options.smoothing = coherence; options.minimumContourLength = 0
        let first = try PortraitFlowRenderer.layers(from: raster, options: options)
        let repeated = try PortraitFlowRenderer.layers(from: raster, options: options)
        #expect(first.structure == repeated.structure && first.tone == repeated.tone)
        for path in first.structure + first.tone {
          #expect(path.allSatisfy { $0.x.isFinite && $0.y.isFinite && $0.x >= 0 && $0.y >= 0
            && $0.x < Double(width) && $0.y < Double(height) })
        }
      }
    }
  }

  @Test("Density and stroke form reuse immutable evidence, structure and orientation")
  func stageReuse() throws {
    let raster = cacheRaster()
    var workspace = PortraitFlowRenderer.Workspace()
    var options = PortraitVectorOptions.flowDefaults
    let baseline = try PortraitFlowRenderer.layers(from: raster, options: options, workspace: &workspace)
    #expect(workspace.diagnostics.sourceBuilds == 1)
    #expect(workspace.diagnostics.structureBuilds == 1)
    #expect(workspace.diagnostics.orientationBuilds == 1)
    options.tonalStrength = 1.8
    options.flowRectilinearity = 0.5
    let mixed = try PortraitFlowRenderer.layers(from: raster, options: options, workspace: &workspace)
    #expect(workspace.diagnostics.sourceCacheHit)
    #expect(workspace.diagnostics.structureCacheHit)
    #expect(workspace.diagnostics.orientationCacheHit)
    #expect(workspace.diagnostics.sourceBuilds == 1)
    #expect(workspace.diagnostics.structureBuilds == 1)
    #expect(workspace.diagnostics.orientationBuilds == 1)
    #expect(mixed.structure == baseline.structure)
    #expect(mixed.tone.contains { $0.count == 2 })
    #expect(mixed.tone.contains { $0.count > 2 })
    let uncached = try PortraitFlowRenderer.layers(from: raster, options: options)
    #expect(mixed.structure == uncached.structure)
    #expect(mixed.tone == uncached.tone)
    options.smoothing = 4
    _ = try PortraitFlowRenderer.layers(from: raster, options: options, workspace: &workspace)
    #expect(workspace.diagnostics.sourceCacheHit && workspace.diagnostics.structureCacheHit)
    #expect(!workspace.diagnostics.orientationCacheHit)
    #expect(workspace.diagnostics.orientationBuilds == 2)
  }

  @Test("Preparation verifies exact source data and bounds each stage history")
  func sourceIdentityAndBounds() throws {
    var workspace = PortraitFlowRenderer.Workspace()
    var options = PortraitVectorOptions.flowDefaults
    for value in 0..<4 {
      options.smoothing = Double(value)
      options.sketchThreshold = 0.008 + Double(value) * 0.004
      _ = try PortraitFlowRenderer.layers(from: cacheRaster(), options: options, workspace: &workspace)
    }
    #expect(workspace.structureVariantCount == 2)
    #expect(workspace.orientationVariantCount == 2)
    // Same declared provenance and dimensions are insufficient for a cache hit.
    let changed = cacheRaster(shift: 7)
    let refreshed = try PortraitFlowRenderer.layers(from: changed, options: options, workspace: &workspace)
    let cold = try PortraitFlowRenderer.layers(from: changed, options: options)
    #expect(!workspace.diagnostics.sourceCacheHit)
    #expect(workspace.structureVariantCount == 1 && workspace.orientationVariantCount == 1)
    #expect(refreshed.structure == cold.structure && refreshed.tone == cold.tone)
  }

  @Test("Workspace memory belongs to a bounded Studio LRU and source removal releases it")
  func studioCacheBounds() throws {
    let raster = cacheRaster()
    var workspace = PortraitFlowRenderer.Workspace()
    let layers = try PortraitFlowRenderer.layers(from: raster, options: .flowDefaults, workspace: &workspace)
    let pen = try portraitTestStyle()
    let program = try PortraitVectorizer.program(from: raster, pose: .front, style: .flowEdges,
      strokeStyle: pen, vectorOptions: .flowDefaults, flowLayers: layers)
    var cache = PortraitRenderCache()
    var ids: [UUID] = []
    for _ in 0..<(PortraitRenderCache.maximumFlowWorkspaces + 1) {
      let id = UUID(); ids.append(id)
      let key = PortraitRenderCacheKey(photoID: id,
        configuration: .init(style: .flowEdges, vectors: .flowDefaults, analysis: .init()), strokeStyle: pen)
      cache.insert(.init(raster: raster, program: program, flowWorkspace: workspace), for: key)
      #expect(cache.result(for: key)?.flowWorkspace == nil)
    }
    #expect(cache.flowWorkspaceCount == PortraitRenderCache.maximumFlowWorkspaces)
    #expect(cache.flowWorkspace(for: .init(photoID: ids[0], analysis: .init(), maximumDimension: 320)) == nil)
    #expect(cache.flowWorkspace(for: .init(photoID: ids.last!, analysis: .init(), maximumDimension: 320)) != nil)
    cache.remove(photoID: ids.last!)
    #expect(cache.flowWorkspaceCount == PortraitRenderCache.maximumFlowWorkspaces - 1)
    #expect(cache.flowWorkspaceBytes <= PortraitRenderCache.maximumFlowWorkspaceBytes)
  }


  @Test("workspace eviction is also bounded by retained pixel and path bytes")
  func studioByteBounds() throws {
    let raster = cacheRaster()
    var workspace = PortraitFlowRenderer.Workspace()
    let layers = try PortraitFlowRenderer.layers(from: raster, options: .flowDefaults, workspace: &workspace)
    #expect(workspace.retainedByteCount > raster.luminance.count * MemoryLayout<Double>.stride)
    let pen = try portraitTestStyle()
    let program = try PortraitVectorizer.program(from: raster, pose: .front, style: .flowEdges,
      strokeStyle: pen, vectorOptions: .flowDefaults, flowLayers: layers)
    var cache = PortraitRenderCache(flowByteLimit: workspace.retainedByteCount * 2)
    let ids = (0..<3).map { _ in UUID() }
    for id in ids {
      cache.insert(.init(raster: raster, program: program, flowWorkspace: workspace), for: .init(photoID: id,
        configuration: .init(style: .flowEdges, vectors: .flowDefaults, analysis: .init()), strokeStyle: pen))
    }
    #expect(cache.flowWorkspaceCount == 2)
    #expect(cache.flowWorkspaceBytes == workspace.retainedByteCount * 2)
    #expect(cache.flowWorkspace(for: .init(photoID: ids[0], analysis: .init(), maximumDimension: 320)) == nil)
  }

  @Test("Mixed and straight strokes share structural and inter-stroke material clearance")
  func sharedOccupancy() throws {
    let raster = cacheRaster(barrier: true)
    var options = PortraitVectorOptions.flowDefaults
    options.hatchSpacing = 5
    options.materialContext = try .init(profile: .init(name: "Mixed pen", nominalWidthMM: 1.5), drawingHeightMM: 48)
    for mix in [0.5, 1.0] {
      options.flowRectilinearity = mix
      let layers = try PortraitFlowRenderer.layers(from: raster, options: options)
      try #require(!layers.structure.isEmpty)
      #expect(!layers.tone.isEmpty)
      if mix == 1 { #expect(layers.tone.allSatisfy { $0.count == 2 }) }
      let sampled = layers.tone.map(samplePath)
      for (index, path) in sampled.enumerated() {
        for point in path.enumerated().filter({ $0.offset.isMultiple(of: 3) }).map(\.element) {
          for prior in sampled.prefix(index) {
            #expect(prior.allSatisfy { hypot($0.x - point.x, $0.y - point.y) >= layers.minimumSpacing })
          }
          for boundary in layers.structure {
            #expect(boundary.allSatisfy { hypot($0.x - point.x, $0.y - point.y) >= layers.minimumSpacing })
          }
        }
      }
    }
  }

  @Test("Cancellation still applies when all preparation stages are cached")
  func cachedCancellation() async throws {
    let raster = cacheRaster()
    var workspace = PortraitFlowRenderer.Workspace()
    _ = try PortraitFlowRenderer.layers(from: raster, options: .flowDefaults, workspace: &workspace)
    let prepared = workspace
    let task = Task {
      withUnsafeCurrentTask { $0?.cancel() }
      var reused = prepared
      return try PortraitFlowRenderer.layers(from: raster, options: .flowDefaults, workspace: &reused)
    }
    await #expect(throws: CancellationError.self) { try await task.value }
  }
}

private func cacheRaster(shift: Int = 0, barrier: Bool = false) -> PortraitRaster {
  let width = 80, height = 96
  let values = (0..<(width * height)).map { index -> Double in
    if barrier, (39...41).contains(index % width) { return 0.02 }
    let x = Double(index % width - 40 - shift), y = Double(index / width - 48)
    return min(0.88, 0.15 + hypot(x, y) / 100)
  }
  return PortraitRaster(width: width, height: height, luminance: values,
    provenance: "cache-fixture", analysisSummary: "Synthetic radial field")
}

private func samplePath(_ path: [CGPoint]) -> [CGPoint] {
  guard let first = path.first else { return [] }
  var points = [first]
  for (a, b) in zip(path, path.dropFirst()) {
    let count = max(1, Int(ceil(hypot(b.x - a.x, b.y - a.y) / 0.8)))
    for i in 1...count {
      let t = Double(i) / Double(count)
      points.append(CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t))
    }
  }
  return points
}
