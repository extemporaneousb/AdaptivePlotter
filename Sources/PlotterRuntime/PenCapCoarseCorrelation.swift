import Accelerate
import Foundation
import PlotterModel

/// Vectorized form of the matcher's per-channel mean-subtracted RGB correlation.
/// Every grid position in the search region is scored, including when a motion
/// prediction is available. Vectorization changes cost, not the search domain.
enum PenCapCoarseCorrelation {
  struct Sample {
    let u: Double, v: Double
    let r: Double, g: Double, b: Double
  }

  static func search(frame: StampedFrame, bytes: UnsafeRawBufferPointer, region: PixelRect,
    samples: [Sample], scale: Double, stridePixels: Int,
    visit: (Double, Double, Double) -> Void) throws {
    let offsets = samples.map { (Int(floor(scale * $0.u)), Int(floor(scale * $0.v))) }
    guard let minX = offsets.map(\.0).min(), let maxX = offsets.map(\.0).max(),
      let minY = offsets.map(\.1).min(), let maxY = offsets.map(\.1).max() else { return }
    let xs = stride(from: region.x, to: region.x + region.width, by: stridePixels).filter {
      $0 + minX >= region.x && $0 + maxX < region.x + region.width
    }
    let ys = stride(from: region.y, to: region.y + region.height, by: stridePixels).filter {
      $0 + minY >= region.y && $0 + maxY < region.y + region.height
    }
    guard let firstX = xs.first, !ys.isEmpty else { return }
    let count = xs.count * ys.count, n = vDSP_Length(count)
    let sampleCount = Double(samples.count)
    let tr = samples.reduce(0) { $0 + $1.r }, tg = samples.reduce(0) { $0 + $1.g }
    let tb = samples.reduce(0) { $0 + $1.b }
    let variance = samples.reduce(0) {
      $0 + pow($1.r - tr / sampleCount, 2) + pow($1.g - tg / sampleCount, 2)
        + pow($1.b - tb / sampleCount, 2)
    }
    guard variance > sampleCount * 3 * 16 else { return }
    var sums = Array(repeating: [Float](repeating: 0, count: count), count: 3)
    var squares = [Float](repeating: 0, count: count)
    var products = [Float](repeating: 0, count: count)
    var target = [Float](repeating: 0, count: count)
    var squared = [Float](repeating: 0, count: count)
    let channelOffsets = frame.pixelFormat == .rgba8 ? [0, 1, 2] : [2, 1, 0]
    let means = [tr / sampleCount, tg / sampleCount, tb / sampleCount]
    let pixels = bytes.bindMemory(to: UInt8.self)
    for (sampleIndex, sample) in samples.enumerated() {
      try Task.checkCancellation()
      let offset = offsets[sampleIndex]
      for channel in 0..<3 {
        target.withUnsafeMutableBufferPointer { destination in
          for (row, y) in ys.enumerated() {
            let start = (y + offset.1) * frame.rowBytes + (firstX + offset.0) * 4 + channelOffsets[channel]
            vDSP_vfltu8(pixels.baseAddress! + start, vDSP_Stride(stridePixels * 4),
              destination.baseAddress! + row * xs.count, 1, vDSP_Length(xs.count))
          }
        }
        // Copies of the accumulators avoid overlapping Swift exclusivity; vDSP
        // performs the arithmetic in optimized platform code in Debug as well.
        let previousSum = sums[channel]
        vDSP_vadd(previousSum, 1, target, 1, &sums[channel], 1, n)
        vDSP_vsq(target, 1, &squared, 1, n)
        let previousSquares = squares
        vDSP_vadd(previousSquares, 1, squared, 1, &squares, 1, n)
        var coefficient = Float(([sample.r, sample.g, sample.b][channel]) - means[channel])
        let previousProducts = products
        vDSP_vsma(target, 1, &coefficient, previousProducts, 1, &products, 1, n)
      }
    }
    for (row, y) in ys.enumerated() {
      try Task.checkCancellation()
      for (column, x) in xs.enumerated() {
        let index = row * xs.count + column
        let sr = Double(sums[0][index]), sg = Double(sums[1][index]), sb = Double(sums[2][index])
        let targetVariance = Double(squares[index]) - (sr * sr + sg * sg + sb * sb) / sampleCount
        guard targetVariance > sampleCount * 3 * 16 else { continue }
        let correlation = Double(products[index]) / sqrt(targetVariance * variance)
        let colorDifference = (abs(sr - tr) + abs(sg - tg) + abs(sb - tb)) / (sampleCount * 765)
        visit(Double(x), Double(y), correlation - colorDifference * 0.15)
      }
    }
  }
}
