import CoreGraphics
import Foundation
import PlotterModel
import Testing

@testable import PlotterApp

@Suite("Portrait recipes and face-anchored geometry")
struct PortraitStyleRecipeTests {
  @Test("additive recipe options preserve old initializer and decoding defaults")
  func legacyOptions() throws {
    let vectors = try JSONDecoder().decode(PortraitVectorOptions.self, from: Data("{}".utf8))
    #expect(vectors == PortraitVectorOptions())
    #expect(!vectors.provenance.contains("hatchAngle="))
    #expect(!vectors.provenance.contains("headScale="))
    let analysis = try JSONDecoder().decode(PortraitAnalysisOptions.self,
      from: Data("{\"cropToFace\":false,\"removeBackground\":false}".utf8))
    #expect(analysis == PortraitAnalysisOptions(cropToFace: false, removeBackground: false))
    #expect(PortraitVectorOptions(hatchAngleDegrees: .nan, headScale: .infinity).bounded == vectors)
  }

  @Test("angled hatching authors clipped diagonal paths in both directions")
  func angledHatch() throws {
    let image = fixture()
    let program = try PortraitVectorizer.program(from: image, pose: .front, style: .crosshatch,
      strokeStyle: portraitTestStyle(), vectorOptions: PortraitVectorOptions(hatchSpacing: 8, hatchAngleDegrees: 30))
    #expect(!program.strokes.isEmpty)
    let points = program.strokes.flatMap(\.path.points)
    #expect(points.allSatisfy { $0.x >= 0 && $0.x <= 100 && $0.y >= 0 && $0.y <= 100 })
    let slopes = program.strokes.compactMap { stroke -> Double? in
      let a = stroke.path.start, b = stroke.path.end
      guard abs(b.x-a.x) > 0.01 else { return nil }
      return (b.y-a.y)/(b.x-a.x)
    }
    #expect(slopes.contains { abs($0 + tan(Double.pi/6)) < 0.001 })
    #expect(slopes.contains { abs($0 - tan(Double.pi/3)) < 0.001 })
    #expect(program.source.sourceIdentifier.contains("hatchAngle=30.0"))
  }

  @Test("face enlargement preserves canvas edges and distant shoulders without folding")
  func boundedHeadTransform() throws {
    let transform = try #require(PortraitHeadTransform(faceBounds: face, width: 101, height: 101, scale: 1.6))
    for value in stride(from: 0.0, through: 100, by: 5) {
      for point in [CGPoint(x: value, y: 0), CGPoint(x: value, y: 100),
                    CGPoint(x: 0, y: value), CGPoint(x: 100, y: value)] {
        #expect(transform.point(point) == point)
      }
    }
    #expect(transform.point(CGPoint(x: 25, y: 90)) == CGPoint(x: 25, y: 90))
    let left = transform.point(CGPoint(x: 35, y: 30))
    let right = transform.point(CGPoint(x: 65, y: 30))
    #expect(right.x-left.x > 35)
    for y in stride(from: 5.0, through: 95, by: 5) {
      for x in stride(from: 5.0, through: 95, by: 5) {
        let p = transform.point(CGPoint(x: x, y: y))
        let dx = transform.point(CGPoint(x: x+0.001, y: y))
        let dy = transform.point(CGPoint(x: x, y: y+0.001))
        let determinant = ((dx.x-p.x)*(dy.y-p.y)-(dx.y-p.y)*(dy.x-p.x))/0.000_001
        #expect(determinant > 0.2)
      }
    }
  }

  @Test("head geometry requires a detected face and long hatch paths follow its curve")
  func headTransformProvenance() throws {
    let options = PortraitVectorOptions(hatchSpacing: 10, headScale: 1.6)
    let image = fixture()
    let unchanged = try PortraitVectorizer.program(from: image, pose: .front, style: .hatch,
      strokeStyle: portraitTestStyle())
    let noFace = try PortraitVectorizer.program(from: image, pose: .front, style: .hatch,
      strokeStyle: portraitTestStyle(), vectorOptions: PortraitVectorOptions(headScale: 1.6))
    #expect(noFace.strokes.map(\.path) == unchanged.strokes.map(\.path))
    #expect(noFace.source.sourceIdentifier.contains("headTransform=unavailable"))
    var withFace = image
    withFace.faceBounds = face
    let transformed = try PortraitVectorizer.program(from: withFace, pose: .front, style: .hatch,
      strokeStyle: portraitTestStyle(), vectorOptions: options)
    #expect(transformed.strokes.contains { $0.path.points.count > 2 })
    #expect(transformed.source.sourceIdentifier.contains("headTransform=v1|headFace="))
    let repeated = try PortraitVectorizer.program(from: withFace, pose: .front, style: .hatch,
      strokeStyle: portraitTestStyle(), vectorOptions: options)
    #expect(transformed == repeated)
  }

  private var face: CGRect { CGRect(x: 0.3, y: 0.15, width: 0.4, height: 0.3) }
  private func fixture() -> PortraitRaster {
    PortraitRaster(width: 101, height: 101, luminance: Array(repeating: 0.1, count: 10_201),
      provenance: "geometry-fixture", analysisSummary: "Synthetic fixture")
  }
}
