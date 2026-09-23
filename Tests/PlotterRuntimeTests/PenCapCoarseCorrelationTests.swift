import Foundation
import PlotterModel
import Testing
@testable import PlotterRuntime

@Suite("Cap coarse correlation")
struct PenCapCoarseCorrelationTests {
  @Test("vector proposals agree with scalar NCC across ROI edges, layouts and scales")
  func scalarEquivalence() throws {
    let width = 48, height = 40
    let region = PixelRect(x: 3, y: 5, width: 41, height: 31)
    let samples = (0..<25).map { i in
      PenCapCoarseCorrelation.Sample(u: Double(i % 5) * 2.25 - 4.5,
        v: Double(i / 5) * 1.75 - 3.5,
        r: Double((i * 43 + 12) % 256), g: Double((i * 71 + 51) % 256),
        b: Double((i * 29 + 213) % 256))
    }
    for bgra in [false, true] {
      var pixels = [UInt8](repeating: 255, count: width * height * 4)
      for y in 0..<height {
        for x in 0..<width {
          let channels = [(x * 31 + y * 17 + 11) % 256, (x * 3 + y * 47 + 91) % 256,
            (x * 29 + y * 7 + 201) % 256]
          let i = (y * width + x) * 4
          for c in 0..<3 { pixels[i + (bgra ? 2 - c : c)] = UInt8(channels[c]) }
        }
      }
      let frame = try StampedFrame(sequence: 1, captureNanoseconds: 1,
        cameraConfigurationID: CameraConfigurationID(), width: width, height: height,
        rowBytes: width * 4, pixelFormat: bgra ? .bgra8 : .rgba8, bytes: OwnedFrameBytes(pixels))
      for scale in [0.85, 1.0, 1.15] {
        var vector: [Int: Double] = [:]
        try frame.bytes.withUnsafeBytes { bytes in
          try PenCapCoarseCorrelation.search(frame: frame, bytes: bytes, region: region,
            samples: samples, scale: scale, stridePixels: 3) { x, y, score in
            vector[Int(y) * width + Int(x)] = score
          }
        }
        var scalar: [Int: Double] = [:]
        for y in stride(from: region.y, to: region.y + region.height, by: 3) {
          for x in stride(from: region.x, to: region.x + region.width, by: 3) {
            if let score = scalarScore(x: x, y: y, scale: scale, region: region,
              samples: samples, pixels: pixels, width: width, bgra: bgra) {
              scalar[y * width + x] = score
            }
          }
        }
        #expect(Set(vector.keys) == Set(scalar.keys))
        for (key, score) in scalar {
          // The proposal pass uses Float vDSP accumulators. Full-resolution
          // refinement and all final acceptance gates continue to use Double.
          #expect(abs(try #require(vector[key]) - score) < 0.00002)
        }
      }
    }
  }

  private func scalarScore(x: Int, y: Int, scale: Double, region: PixelRect,
    samples: [PenCapCoarseCorrelation.Sample], pixels: [UInt8], width: Int, bgra: Bool) -> Double? {
    var sr = 0.0, sg = 0.0, sb = 0.0, tr = 0.0, tg = 0.0, tb = 0.0
    var ss = 0.0, tt = 0.0, st = 0.0
    for sample in samples {
      let px = Int(Double(x) + scale * sample.u), py = Int(Double(y) + scale * sample.v)
      guard px >= region.x, py >= region.y, px < region.x + region.width,
        py < region.y + region.height else { return nil }
      let i = (py * width + px) * 4
      let r = Double(pixels[i + (bgra ? 2 : 0)]), g = Double(pixels[i + 1])
      let b = Double(pixels[i + (bgra ? 0 : 2)])
      sr += r; sg += g; sb += b; tr += sample.r; tg += sample.g; tb += sample.b
      ss += r * r + g * g + b * b
      tt += sample.r * sample.r + sample.g * sample.g + sample.b * sample.b
      st += r * sample.r + g * sample.g + b * sample.b
    }
    let n = Double(samples.count)
    let a = ss - (sr * sr + sg * sg + sb * sb) / n
    let b = tt - (tr * tr + tg * tg + tb * tb) / n
    guard a > n * 3 * 16, b > n * 3 * 16 else { return nil }
    let correlation = (st - (sr * tr + sg * tg + sb * tb) / n) / sqrt(a * b)
    let difference = (abs(sr - tr) + abs(sg - tg) + abs(sb - tb)) / (n * 765)
    return correlation - difference * 0.15
  }
}
