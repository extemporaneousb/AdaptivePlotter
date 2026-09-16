import Foundation
import Testing
@testable import PlotterModel

@Suite("Camera-proportioned drawing placement")
struct DrawingCameraGeometryTests {
  @Test("Full camera response cancels unequal travel and shear at every authored rotation",
    arguments: [0.0, 90.0, 37.0, -45.0])
  func proportionalGeometry(degrees: Double) throws {
    for matrix in [[-1.6954, 0.0007, 0.0207, -1.3425], [2, 0.8, 0.1, 1],
      [0, -3, 2, 0], [-2, 0, 0, 1], [4, 0, 0, 4]] {
      let camera = try AffineTransform2<MachineSpace, CameraPixelSpace>(
        m11: matrix[0], m12: matrix[1], m21: matrix[2], m22: matrix[3], tx: 1600, ty: -120)
      let geometry = try DrawingCameraGeometry(cameraFromMachine: camera)
      let placement = try DrawingPlacement(fieldAnchor: Point2(x: 50, y: 70),
        machineAnchor: Point2(x: 210, y: -30), uniformScale: 0.7,
        rotationRadians: degrees * .pi / 180, cameraGeometry: geometry)
      let center = try placement.applying(to: placement.fieldAnchor)
      #expect(center.distance(to: placement.machineAnchor) < 1e-10)
      let source: [Point2<FieldSpace>] = try [Point2(x: 0, y: 0), Point2(x: 20, y: 0),
        Point2(x: 20, y: 40), Point2(x: 0, y: 40)]
      let points = try source.map { try camera.applying(to: placement.applying(to: $0)) }
      let expectedScale = 0.7 * sqrt(abs(camera.determinant))
      #expect(abs(points[0].distance(to: points[1]) - 20 * expectedScale) < 1e-9)
      #expect(abs(points[1].distance(to: points[2]) - 40 * expectedScale) < 1e-9)
      let x = try points[0].vector(to: points[1]), y = try points[0].vector(to: points[3])
      #expect(abs(x.dx * y.dx + x.dy * y.dy) < 1e-8)
      #expect(abs(try placement.fieldToMachineTransform.determinant - 0.49) < 1e-10)
      #expect(placement.minimumScale <= placement.maximumScale)
      #expect(try JSONDecoder().decode(DrawingPlacement.self, from: JSONEncoder().encode(placement)) == placement)
    }
  }

  @Test("Legacy placement canonical bytes and absent camera field remain unchanged")
  func legacyIdentity() throws {
    let placement = try DrawingPlacement(fieldAnchor: Point2(x: 50, y: 70),
      machineAnchor: Point2(x: 100, y: -40), uniformScale: 0.4, rotationRadians: 0.3)
    struct Legacy: CanonicalEncodable {
      let placement: DrawingPlacement
      func encodeCanonical(to encoder: inout CanonicalEncoder) throws {
        try encoder.appendString("DrawingPlacement")
        try placement.fieldAnchor.encodeCanonical(to: &encoder)
        try placement.machineAnchor.encodeCanonical(to: &encoder)
        try encoder.appendDouble(placement.uniformScale)
        try encoder.appendDouble(placement.rotationRadians)
      }
    }
    #expect(try canonicalDigest(of: placement) == canonicalDigest(of: Legacy(placement: placement)))
    let data = try JSONEncoder().encode(placement)
    #expect(!String(decoding: data, as: UTF8.self).contains("cameraGeometry"))
    #expect(try JSONDecoder().decode(DrawingPlacement.self, from: data) == placement)
    let camera = try DrawingCameraGeometry(cameraFromMachine: .init(m11: 2, m12: 0, m21: 0, m22: 1, tx: 0, ty: 0))
    let corrected = try DrawingPlacement(fieldAnchor: placement.fieldAnchor, machineAnchor: placement.machineAnchor,
      uniformScale: placement.uniformScale, rotationRadians: placement.rotationRadians, cameraGeometry: camera)
    #expect(try canonicalDigest(of: corrected) != canonicalDigest(of: placement))
  }

  @Test("Collapsed camera response is refused instead of creating extreme commands")
  func illConditionedResponse() throws {
    let camera = try AffineTransform2<MachineSpace, CameraPixelSpace>(
      m11: 1e5, m12: 0, m21: 0, m22: 1e-8, tx: 0, ty: 0)
    #expect(throws: PlotterModelError.self) { try DrawingCameraGeometry(cameraFromMachine: camera) }
  }
}
