import Foundation
import Testing
import PlotterModel
import PortraitCore
import PortraitArtists

@Suite("SwiftSketch physical cubic conversion")
struct SwiftSketchTests {
  @Test
  func testUniformFitPreservesSquareGeometryInNonsquareField() throws {
    let raw = try fixture([[0,0],[75,75],[149,149],[224,224]])
    let program = try SwiftSketchConverter.program(raw: raw, fieldWidthMM: 200, fieldHeightMM: 100,
      nominalPenWidthMM: 0.3, sourceIdentifier: "fixture")
    #expect(program.strokes.count == 32)
    let p = program.strokes[0].path.points
    #expect(p.first?.x == 50); #expect(p.first?.y == 100)
    #expect(p.last?.x == 150); #expect(p.last?.y == 0)
    #expect(p.count == 2)
    let again = try SwiftSketchConverter.program(raw: raw, fieldWidthMM: 200, fieldHeightMM: 100,
      nominalPenWidthMM: 0.3, sourceIdentifier: "fixture")
    #expect(program.contentHash == again.contentHash)
    #expect(program.strokes.map(\.ordering) == Array(0..<32).map(UInt32.init))
  }

  @Test
  func testDenseCurveSamplesStayWithinPhysicalFlatteningTolerance() throws {
    let curve = [[20.0,20],[20,200],[200,20],[200,200]]
    let program = try SwiftSketchConverter.program(raw: fixture(curve), fieldWidthMM: 100, fieldHeightMM: 100,
      nominalPenWidthMM: 0.1, sourceIdentifier: "curved-fixture")
    let points = program.strokes[0].path.points
    for index in 0...8192 {
      let t = Double(index)/8192, u = 1-t
      let x = (u*u*u*curve[0][0]+3*u*u*t*curve[1][0]+3*u*t*t*curve[2][0]+t*t*t*curve[3][0])/224*100
      let y = 100-(u*u*u*curve[0][1]+3*u*u*t*curve[1][1]+3*u*t*t*curve[2][1]+t*t*t*curve[3][1])/224*100
      let distances = zip(points, points.dropFirst()).map { a,b -> Double in
        let dx=b.x-a.x, dy=b.y-a.y, length=dx*dx+dy*dy
        let alpha=length==0 ? 0 : max(0,min(1,((x-a.x)*dx+(y-a.y)*dy)/length))
        return hypot(x-a.x-alpha*dx,y-a.y-alpha*dy)
      }
      let distance = try #require(distances.min())
      #expect(distance <= 0.025 + 1e-10)
    }
  }

  @Test
  func testRejectsOutOfFieldAndMalformedCubicsWithoutClamping() throws {
    #expect(throws: (any Error).self) {
      try SwiftSketchConverter.program(raw: fixture([[0,0],[-1,2],[3,4],[5,6]]),
        fieldWidthMM: 100, fieldHeightMM: 100, nominalPenWidthMM: 0.3, sourceIdentifier: "bad")
    }
    #expect(throws: (any Error).self) {
      try SwiftSketchConverter.program(raw: fixture([[0,0],[3,4],[5,6]]),
        fieldWidthMM: 100, fieldHeightMM: 100, nominalPenWidthMM: 0.3, sourceIdentifier: "bad")
    }
  }

  private func fixture(_ curve: [[Double]]) throws -> Data {
    let curves = Array(repeating: curve, count: 32)
    return try JSONSerialization.data(withJSONObject: ["schema_version":1,"canvas_width":224,"canvas_height":224,
      "coordinate_space":"image-pixels-y-down","curve_kind":"ordered-open-cubic",
      "refined":curves,"refined_normalized":curves,"diffusion_normalized":curves], options: [.sortedKeys])
  }
}
