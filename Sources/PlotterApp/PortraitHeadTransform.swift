import CoreGraphics
import Foundation

/// A face-anchored geometric caricature, not a learned face generator. Two
/// monotone axis maps compose without folds; each keeps the image boundary
/// fixed. Compact falloff leaves distant shoulders and background stationary.
struct PortraitHeadTransform {
  private let center: CGPoint
  private let radius: CGSize
  private let width: Double
  private let height: Double
  private let amount: Double

  init?(faceBounds: CGRect?, width: Int, height: Int, scale: Double) {
    guard width >= 2, height >= 2, scale.isFinite,
      let face = Self.validFaceBounds(faceBounds) else { return nil }
    self.width = Double(width-1)
    self.height = Double(height-1)
    center = CGPoint(x: face.midX * Double(width-1), y: face.midY * Double(height-1))
    radius = CGSize(width: face.width * Double(width-1) * 1.8,
                    height: face.height * Double(height-1) * 1.6)
    amount = min(1.6, max(1, scale)) - 1
  }

  static func validFaceBounds(_ value: CGRect?) -> CGRect? {
    guard let value, [value.minX, value.minY, value.width, value.height].allSatisfy(\.isFinite),
      value.width > 0, value.height > 0 else { return nil }
    let clipped = value.intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
    guard !clipped.isNull, clipped.width > 0, clipped.height > 0,
      clipped.midX > 0, clipped.midX < 1, clipped.midY > 0, clipped.midY < 1 else { return nil }
    return clipped
  }

  func point(_ point: CGPoint) -> CGPoint {
    guard amount > 0 else { return point }
    let xStrength = 1 + amount * falloff(point.y, center: center.y, radius: radius.height, limit: height)
    let x = mapped(point.x, center: center.x, radius: radius.width, limit: width, strength: xStrength)
    let yStrength = 1 + amount * falloff(x, center: center.x, radius: radius.width, limit: width)
    let y = mapped(point.y, center: center.y, radius: radius.height, limit: height, strength: yStrength)
    return CGPoint(x: x, y: y)
  }

  /// For t in [0, 1], t + a*t*(1-t)^2 has derivative at least 1-a/3.
  /// With a <= 0.6 this stays positive, matches identity at the support edge
  /// with derivative 1, and has the requested local scale at the face center.
  private func mapped(_ value: Double, center: Double, radius: Double, limit: Double, strength: Double) -> Double {
    let delta = value-center
    let reach = min(radius, delta < 0 ? center : limit-center)
    guard reach > 0, abs(delta) < reach else { return value }
    let t = abs(delta)/reach
    let mapped = (t + (strength-1)*t*(1-t)*(1-t))*reach
    return min(limit, max(0, center + (delta < 0 ? -mapped : mapped)))
  }

  private func falloff(_ value: Double, center: Double, radius: Double, limit: Double) -> Double {
    let reach = min(radius, value < center ? center : limit-center)
    guard reach > 0 else { return 0 }
    let t = abs(value-center)/reach
    guard t < 1 else { return 0 }
    let value = 1-t*t
    return value*value
  }
}
