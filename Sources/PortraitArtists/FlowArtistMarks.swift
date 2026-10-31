import Foundation

/// Additive native tonal-mark grammar. Zero amounts preserve the original Flow
/// renderer, provenance and recipe encoding. Scale has no effect by itself.
package struct FlowArtistMarks: Codable, Hashable, Sendable {
  package let wave: Double
  package let polygon: Double
  package let loop: Double
  package let scale: Double
  package var isActive: Bool { wave > 0 || polygon > 0 || loop > 0 }
  package var coordinates: [Double] { isActive ? [wave, polygon, loop, scale] : [0, 0, 0, 0] }
  package init(wave: Double = 0, polygon: Double = 0, loop: Double = 0, scale: Double = 0) {
    func bound(_ x: Double) -> Double { x.isFinite ? min(1, max(0, x)) : 0 }
    self.wave = bound(wave); self.polygon = bound(polygon); self.loop = bound(loop); self.scale = bound(scale)
  }
  private enum CodingKeys: String, CodingKey { case wave, polygon, loop, scale }
  package init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    let values = try [c.decode(Double.self, forKey: .wave), c.decode(Double.self, forKey: .polygon),
      c.decode(Double.self, forKey: .loop), c.decode(Double.self, forKey: .scale)]
    guard values.allSatisfy({ $0.isFinite && (0...1).contains($0) }) else {
      throw DecodingError.dataCorruptedError(forKey: .wave, in: c, debugDescription: "Invalid native Flow mark coordinates")
    }
    self.init(wave: values[0], polygon: values[1], loop: values[2], scale: values[3])
  }
}
