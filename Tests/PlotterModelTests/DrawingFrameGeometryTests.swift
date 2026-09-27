import Foundation
import Testing
@testable import PlotterModel

@Suite("Authored drawing frame geometry")
struct DrawingFrameGeometryTests {
  @Test("all corners constrain translation and scaling for rotated affine camera responses",
    arguments: [-120.0, -45, 0, 30, 90])
  func affineContainment(degrees: Double) throws {
    let region = try DrawableMachineRegion(bounds: .init(minX: -30, minY: 10, maxX: 190, maxY: 160))
    let response = try AffineTransform2<MachineSpace, CameraPixelSpace>(m11: 3, m12: 0.8,
      m21: -0.4, m22: -2, tx: 100, ty: 500)
    let placement = try DrawingPlacement(fieldAnchor: .init(x: 50, y: 30),
      machineAnchor: .init(x: 300, y: -20), uniformScale: 5,
      rotationRadians: degrees * .pi / 180, cameraGeometry: .init(cameraFromMachine: response))
    let source = DrawingFrameGeometry(extent: try .init(width: 100, height: 60), placement: placement)
    #expect(!source.isContained(in: region))
    let bounded = try source.constrained(to: region)
    #expect(bounded.isContained(in: region))
    #expect(bounded.placement.rotationRadians == placement.rotationRadians)
    #expect(bounded.extent == source.extent)
    let maximum = try bounded.maximumScaleKeepingCenter(in: region)
    #expect(try bounded.replacing(scale: maximum).isContained(in: region))
    #expect(try !bounded.replacing(scale: maximum * 1.001).isContained(in: region))
    #expect(try bounded.constrained(to: region).machineCorners == bounded.machineCorners)
  }

  @Test("frame extent is independent of ink bounds and reaches the entire Boundary")
  func fullRegion() throws {
    let region = try DrawableMachineRegion(bounds: .init(minX: 0, minY: 0, maxX: 200, maxY: 100))
    let frame = DrawingFrameGeometry(extent: try .init(width: 100, height: 50),
      placement: try .init(fieldAnchor: .init(x: 50, y: 25), machineAnchor: .init(x: 100, y: 50), uniformScale: 4))
    let fitted = try frame.constrained(to: region)
    #expect(fitted.placement.uniformScale == 2)
    #expect(try fitted.machineCorners == [Point2(x: 0, y: 0), Point2(x: 200, y: 0),
      Point2(x: 200, y: 100), Point2(x: 0, y: 100)])
  }
}
