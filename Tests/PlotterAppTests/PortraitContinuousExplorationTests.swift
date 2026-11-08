@testable import PortraitArtists
@testable import PortraitLibrary
@testable import PortraitStudioUI
import Foundation
import PlotterModel
import Testing
@testable import PlotterApp

@Suite("Continuous portrait exploration", .serialized)
@MainActor
struct PortraitContinuousExplorationTests {




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
