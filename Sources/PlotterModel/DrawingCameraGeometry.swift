import Foundation

/// The accepted command-to-image response used to preserve artwork proportions
/// in the camera. This makes no claim about physical millimeters or camera pose.
public struct DrawingCameraGeometry: Hashable, Codable, Sendable, CanonicalEncodable {
  public let cameraFromMachine: AffineTransform2<MachineSpace, CameraPixelSpace>
  public let commandCorrection: AffineTransform2<MachineSpace, MachineSpace>
  /// Geometric mean of the observed axis scales; keeps nominal command area.
  public let referencePixelsPerUnit: Double
  public let maximumAxisScale: Double
  public var minimumAxisScale: Double { 1 / maximumAxisScale }
  public var maximumPixelsPerControllerUnit: Double { referencePixelsPerUnit * maximumAxisScale }

  public init(cameraFromMachine: AffineTransform2<MachineSpace, CameraPixelSpace>) throws {
    let a = cameraFromMachine
    let normalization = max(abs(a.m11), abs(a.m12), abs(a.m21), abs(a.m22))
    let x = a.m11 / normalization, y = a.m12 / normalization
    let z = a.m21 / normalization, w = a.m22 / normalization
    let determinant = abs(x * w - y * z)
    guard determinant > 1e-12 else {
      throw PlotterModelError.invalidValue("Camera drawing geometry has an ill-conditioned axis response")
    }
    let g11 = x * x + z * z, g12 = x * y + z * w, g22 = y * y + w * w
    let denominator = sqrt(determinant) * sqrt(g11 + g22 + 2 * determinant)
    // For A = Q S (polar decomposition), K = sqrt(|det A|) S^-1.
    // A K is a similarity: equal scale on both axes, retaining orientation and
    // reflection. K has determinant one, so Size retains its nominal area.
    let k11 = (g22 + determinant) / denominator
    let k12 = -g12 / denominator
    let k22 = (g11 + determinant) / denominator
    let pixels = normalization * sqrt(determinant)
    let maximum = (k11 + k22 + hypot(k11 - k22, 2 * k12)) / 2
    guard pixels.isFinite, pixels > 0, (pixels * maximum).isFinite else {
      throw PlotterModelError.invalidValue("Camera drawing geometry scale overflow")
    }
    self.cameraFromMachine = a
    commandCorrection = try AffineTransform2(m11: k11, m12: k12, m21: k12, m22: k22, tx: 0, ty: 0)
    referencePixelsPerUnit = pixels
    maximumAxisScale = maximum
  }

  public func encodeCanonical(to encoder: inout CanonicalEncoder) throws {
    try encoder.appendString("DrawingCameraGeometry-v1")
    try cameraFromMachine.encodeCanonical(to: &encoder)
  }

  private enum CodingKeys: String, CodingKey { case cameraFromMachine }
  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    try self.init(cameraFromMachine: container.decode(AffineTransform2<MachineSpace, CameraPixelSpace>.self,
      forKey: .cameraFromMachine))
  }
}
