import Foundation
import PlotterModel
import Testing
@testable import PlotterApp

@Suite("Continuous portrait exploration", .serialized)
@MainActor
struct PortraitContinuousExplorationTests {
  @Test("actual Contour and Flow Edge regional exploration stays renewable", arguments: [PortraitStyle.contours, .flowEdges], [PortraitTreatmentRegion.eyes, .face])
  func regionalSequence(style: PortraitStyle, region: PortraitTreatmentRegion) async throws {
    let renderer = RegionalSequenceRenderer(raster: try regionalFixture())
    let model = PortraitStudioModel(renderer: renderer, explorationSeed: 310)
    let pen = try portraitTestStyle()
    model.resetStyle(style, strokeStyle: pen)
    model.setPhoto(Data([1]), for: .front, strokeStyle: pen)
    await model.awaitRendering()
    let original = try #require(model.selectedCandidate)
    model.explorationRegion = region
    var accepted = 0, lateAccepted = 0, geometry = Set<String>()
    var times: [Double] = []
    for step in 0..<24 {
      let before = try #require(model.selectedCandidate)
      let calls = await renderer.calls
      let started = ProcessInfo.processInfo.systemUptime
      model.nextPortrait(strokeStyle: pen)
      await model.awaitRendering()
      times.append((ProcessInfo.processInfo.systemUptime - started) * 1000)
      let after = try #require(model.selectedCandidate)
      #expect(await renderer.calls - calls <= 2)
      #expect(after.recipe.style == style)
      #expect(after.rasterSHA256 == original.rasterSHA256)
      #expect((after.recipe.vectorOptions.regionalAdjustments?.count ?? 0) <= 1)
      #expect(after.recipe.vectorOptions.tonalStrength == original.recipe.vectorOptions.tonalStrength)
      if before.id != after.id {
        accepted += 1
        if step >= 12 { lateAccepted += 1 }
        // Ignore provenance/IDs: actual retained stroke points must differ.
        geometry.insert(after.program.strokes.map { String(describing: $0.path.points) }.joined())
        let calls = await renderer.calls
        model.previousPortrait()
        #expect(model.selectedCandidate?.program == before.program)
        model.nextPortrait(strokeStyle: pen)
        #expect(model.selectedCandidate?.program == after.program)
        #expect(await renderer.calls == calls)
      }
    }
    print("REGIONAL_SEQUENCE style=\(style.rawValue) region=\(region.rawValue) accepted=\(accepted)/24 late=\(lateAccepted)/12 unique=\(geometry.count) mean_ms=\(times.reduce(0,+)/Double(times.count)) rejections=\(model.explorationRejections)")
    #expect(accepted >= 12)
    #expect(lateAccepted >= 5)
    #expect(geometry.count >= 8)
    #expect(model.workDiagnostics.maximumConcurrentWorkerCount == 1)
    await model.shutdown()
  }

  @Test("Previous at the beginning generates and Next returns the exact starting drawing")
  func extendBeginning() async throws {
    let renderer = ExplorationTestRenderer()
    let model = PortraitStudioModel(renderer: renderer, explorationSeed: 310)
    let pen = try portraitTestStyle()
    model.setPhoto(Data([1]), for: .front, strokeStyle: pen)
    await model.awaitRendering()
    let original = try #require(model.selectedCandidate)
    #expect(!model.canGoBackExploration)
    model.previousPortrait()
    await model.awaitRendering()
    let previous = try #require(model.selectedCandidate)
    #expect(previous.id != original.id)
    let calls = await renderer.requests.count
    model.nextPortrait(strokeStyle: pen)
    #expect(model.selectedCandidate?.program == original.program)
    model.previousPortrait()
    #expect(model.selectedCandidate?.program == previous.program)
    #expect(await renderer.requests.count == calls)
    await model.shutdown()
  }

  @Test("an eye edit is judged locally despite dense exterior ink, with Y-axis mapping preserved")
  func regionalDistance() throws {
    let raster = try regionalFixture()
    let pen = try portraitTestStyle()
    func drawing(eyeY: Double, exteriorY: Double = 0) throws -> DrawingProgram {
      let lines = (0..<60).map { index in
        [CGPoint(x: 1, y: Double(index) * 0.5 + exteriorY), CGPoint(x: 99, y: Double(index) * 0.5 + exteriorY)]
      } + [[CGPoint(x: 39, y: eyeY), CGPoint(x: 45, y: eyeY)]]
      return try DrawingProgram(id: ProgramID(UUID()), fieldExtent: .init(width: 100, height: 100),
        strokes: lines.enumerated().map { index, path in
          try LogicalStroke(id: StrokeID(UUID()), path: Polyline(points: path.map { try .init(x: $0.x, y: $0.y) }),
            style: pen, ordering: UInt32(index))
        }, source: .init(kind: "test", sourceIdentifier: "local-distance"))
    }
    let original = try drawing(eyeY: 56)
    let changed = try drawing(eyeY: 60)
    let a = PortraitExplorationPolicy.VisibleGeometry(original)
    let b = PortraitExplorationPolicy.VisibleGeometry(changed)
    let mask = try #require(PortraitExplorationPolicy.VisibleGeometry.regionMask(.eyes, raster: raster, program: original))
    #expect(!a.isMeaningfullyDifferent(from: b))
    #expect(a.isMeaningfullyDifferent(from: b, mask: mask))
    #expect(!a.isMeaningfullyDifferent(from: a, mask: mask))
    #expect(!a.isMeaningfullyDifferent(from: PortraitExplorationPolicy.VisibleGeometry(try drawing(eyeY: 56, exteriorY: 3)), mask: mask))
  }

  @Test("canonical reset works within the same kernel and preserves framing and material")
  func canonicalReset() async throws {
    let renderer = RegionalSequenceRenderer(raster: try regionalFixture())
    let model = PortraitStudioModel(renderer: renderer)
    let pen = try portraitTestStyle()
    let material = try PortraitMaterialContext(profile: .init(name: "Test", nominalWidthMM: 0.4), drawingHeightMM: 100)
    model.options.cropToFace = false
    model.vectorOptions.materialContext = material
    model.setPhoto(Data([1]), for: .front, strokeStyle: pen)
    await model.awaitRendering()
    for style in [PortraitStyle.contours, .flowEdges] {
      model.resetStyle(style, strokeStyle: pen)
      await model.awaitRendering()
      let canonical = model.vectorOptions
      model.vectorOptions.tonalStrength = 1.9
      model.vectorOptions.setTreatment(.init(scope: .eyes, shadowStrength: 0.8))
      model.renderIfConfigurationChanged(strokeStyle: pen)
      await model.awaitRendering()
      model.resetStyle(style, strokeStyle: pen)
      await model.awaitRendering()
      #expect(model.vectorOptions == canonical)
      #expect(model.vectorOptions.materialContext == material)
      #expect(!model.options.cropToFace)
      #expect(model.selectedCandidate?.recipe.style == style)
    }
    await model.shutdown()
  }

  @Test("legacy stacks retain exact geometry until edited, and new edits cannot grow indefinitely")
  func historicalStack() throws {
    let raster = try regionalFixture()
    var old = PortraitVectorOptions()
    old.regionalAdjustments = (0..<8).map { _ in .init(scope: .face, skinSuppression: 0, featureProtection: 1) }
    let encoded = try PortraitCandidateCoding.encoder().encode(old)
    let decoded = try JSONDecoder().decode(PortraitVectorOptions.self, from: encoded)
    #expect(decoded == old)
    let pen = try portraitTestStyle()
    let original = try PortraitVectorizer.program(from: raster, pose: .front, style: .contours, strokeStyle: pen, vectorOptions: old)
    #expect(try PortraitVectorizer.program(from: raster, pose: .front, style: .contours, strokeStyle: pen, vectorOptions: decoded) == original)
    for region in [PortraitTreatmentRegion.eyes, .mouth, .skin, .silhouette, .face] {
      old.setTreatment(.init(scope: region, skinSuppression: 0, featureProtection: 1))
      #expect((old.regionalAdjustments?.count ?? 0) <= 12)
      _ = try PortraitVectorizer.program(from: raster, pose: .front, style: .contours, strokeStyle: pen, vectorOptions: old)
    }
    #expect(old.regionalAdjustments?.count == 5)
    for index in 0..<100 {
      old.setTreatment(.init(scope: .eyes, skinSuppression: 0, angularity: Double(index % 10)/10))
    }
    #expect(old.regionalAdjustments?.count == 5)
  }
}

private actor RegionalSequenceRenderer: PortraitRendering {
  let raster: PortraitRaster
  private(set) var calls = 0
  init(raster: PortraitRaster) { self.raster = raster }
  func render(_ request: PortraitRenderRequest) async throws -> PortraitRenderResult {
    calls += 1
    return .init(raster: raster, program: try PortraitVectorizer.program(from: raster,
      pose: request.pose, style: request.style, strokeStyle: request.strokeStyle,
      vectorOptions: request.vectorOptions))
  }
}
