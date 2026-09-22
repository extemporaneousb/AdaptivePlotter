import Foundation
import PlotterModel

/// Immutable, bounded image reference. Coordinates and dimensions are source-camera
/// pixels; viewport zoom never changes its scale or the independent anchor.
public struct PenCapVisualReference: Codable, Hashable, Sendable {
  public static let revision = "cap-visual-reference-v1"
  public let region: PixelRect
  public let anchor: Point2<CameraPixelSpace>
  public let frameWidth: Int
  public let frameHeight: Int
  public let cameraConfigurationID: CameraConfigurationID
  public let sampleWidth: Int
  public let sampleHeight: Int
  public let rgb: [UInt8]

  public var identity: String {
    // Sorted encoding also binds the anchor and camera geometry, not just appearance.
    let encoder = JSONEncoder()
    encoder.outputFormatting = .sortedKeys
    return RunLedger.sha256Hex((try? encoder.encode(self)) ?? Data())
  }

  public var isValid: Bool {
    (24...100_000).contains(frameWidth) && (24...100_000).contains(frameHeight)
      && region.x >= 0 && region.y >= 0 && region.width >= 12 && region.height >= 12
      && region.x <= frameWidth - region.width && region.y <= frameHeight - region.height
      && region.width <= frameWidth / 2 && region.height <= frameHeight / 2
      && anchor.x >= Double(region.x) && anchor.x < Double(region.x + region.width)
      && anchor.y >= Double(region.y) && anchor.y < Double(region.y + region.height)
      && (4...32).contains(sampleWidth) && (4...32).contains(sampleHeight)
      && rgb.count == sampleWidth * sampleHeight * 3
      && Self.contrast(rgb) >= 8
  }

  public static func capture(
    frame: StampedFrame, region: PixelRect, anchor: Point2<CameraPixelSpace>
  ) throws -> Self {
    guard frame.pixelFormat == .rgba8 || frame.pixelFormat == .bgra8,
      region.x >= 0, region.y >= 0, region.width >= 12, region.height >= 12,
      region.width <= frame.width / 2, region.height <= frame.height / 2,
      region.x <= frame.width - region.width, region.y <= frame.height - region.height,
      anchor.x >= Double(region.x), anchor.x < Double(region.x + region.width),
      anchor.y >= Double(region.y), anchor.y < Double(region.y + region.height)
    else { throw PenCapReferenceError.invalidRegion }
    let factor = min(1, 32 / Double(max(region.width, region.height)))
    let width = max(4, Int((Double(region.width) * factor).rounded()))
    let height = max(4, Int((Double(region.height) * factor).rounded()))
    var pixels: [UInt8] = []
    pixels.reserveCapacity(width * height * 3)
    frame.bytes.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) in
      for y in 0..<height {
        for x in 0..<width {
          let px = Double(region.x) + (Double(x) + 0.5) * Double(region.width) / Double(width) - 0.5
          let py = Double(region.y) + (Double(y) + 0.5) * Double(region.height) / Double(height) - 0.5
          let ix = Int(floor(px)), iy = Int(floor(py))
          let fx = px - Double(ix), fy = py - Double(iy)
          let i = iy * frame.rowBytes + ix * 4
          let j = min(iy + 1, frame.height - 1) * frame.rowBytes + ix * 4
          let next = ix + 1 < frame.width ? 4 : 0
          let redIndex = frame.pixelFormat == .rgba8 ? 0 : 2
          for channel in [redIndex, 1, 2 - redIndex] {
            let top = Double(bytes[i + channel]) * (1 - fx) + Double(bytes[i + next + channel]) * fx
            let bottom = Double(bytes[j + channel]) * (1 - fx) + Double(bytes[j + next + channel]) * fx
            pixels.append(UInt8(min(255, max(0, (top * (1 - fy) + bottom * fy).rounded()))))
          }
        }
      }
    }
    let reference = Self(region: region, anchor: anchor, frameWidth: frame.width,
      frameHeight: frame.height, cameraConfigurationID: frame.cameraConfigurationID,
      sampleWidth: width, sampleHeight: height, rgb: pixels)
    guard reference.isValid else { throw PenCapReferenceError.insufficientDetail }
    return reference
  }

  private static func contrast(_ pixels: [UInt8]) -> Double {
    guard !pixels.isEmpty else { return 0 }
    var variance = 0.0
    for channel in 0..<3 {
      let values = stride(from: channel, to: pixels.count, by: 3).map { Double(pixels[$0]) }
      let mean = values.reduce(0, +) / Double(values.count)
      variance += values.reduce(0) { $0 + pow($1 - mean, 2) } / Double(values.count)
    }
    return sqrt(variance / 3)
  }
}

public enum PenCapReferenceError: LocalizedError {
  case invalidRegion, insufficientDetail
  public var errorDescription: String? {
    switch self {
    case .invalidRegion:
      "Draw a rectangle around the cap and co-moving holder (at least 12 camera pixels per side, at most half the frame), then click the cap inside it."
    case .insufficientDetail:
      "The rectangle has too little visual detail. Include the cap edges and part of the holder that moves with it."
    }
  }
}

/// Coarse global appearance search followed by bounded affine refinement. There is
/// no adaptive template update: a bad match cannot silently replace the reference.
struct PenCapTemplateMatcher {
  private struct Pose {
    var x: Double
    var y: Double
    var sx: Double = 1
    var sy: Double = 1
    var angle: Double = 0
    var shear: Double = 0
    var score: Double = -1
    func point(_ u: Double, _ v: Double) -> (Double, Double) {
      let a = sx * u + shear * v, b = sy * v
      return (x + cos(angle) * a - sin(angle) * b,
        y + sin(angle) * a + cos(angle) * b)
    }
  }
  private struct Sample {
    let u: Double, v: Double
    let r: Double, g: Double, b: Double
  }

  static func detect(frame: StampedFrame, reference: PenCapVisualReference,
    region: PixelRect) throws -> PenCapDetectionResult {
    guard reference.isValid, frame.width == reference.frameWidth,
      frame.height == reference.frameHeight,
      frame.cameraConfigurationID == reference.cameraConfigurationID,
      frame.pixelFormat == .rgba8 || frame.pixelFormat == .bgra8
    else { return .failed("Cap reference does not match this camera configuration. Identify Pen Cap again.") }
    let w = Double(reference.region.width), h = Double(reference.region.height)
    func samples(step: Int) -> [Sample] {
      var result: [Sample] = []
      for y in stride(from: 0, to: reference.sampleHeight, by: step) {
        for x in stride(from: 0, to: reference.sampleWidth, by: step) {
          let i = (y * reference.sampleWidth + x) * 3
          result.append(Sample(u: (Double(x) + 0.5) / Double(reference.sampleWidth) * w - w / 2,
            v: (Double(y) + 0.5) / Double(reference.sampleHeight) * h - h / 2,
            r: Double(reference.rgb[i]), g: Double(reference.rgb[i + 1]), b: Double(reference.rgb[i + 2])))
        }
      }
      return result
    }
    let coarse = samples(step: max(1, max(reference.sampleWidth, reference.sampleHeight) / 8))
    let fine = samples(step: 1)
    return try frame.bytes.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) in
      let redIndex = frame.pixelFormat == .rgba8 ? 0 : 2
      func score(_ pose: Pose, _ samples: [Sample], interpolate: Bool = false) -> Double {
        // Per-channel mean subtraction prevents a uniformly colored field from
        // matching simply because its RGB triplet resembles the reference.
        var sr = 0.0, sg = 0.0, sb = 0.0, tr = 0.0, tg = 0.0, tb = 0.0
        var ss = 0.0, tt = 0.0, st = 0.0
        let c = cos(pose.angle), sn = sin(pose.angle)
        let a11 = c * pose.sx, a12 = c * pose.shear - sn * pose.sy
        let a21 = sn * pose.sx, a22 = sn * pose.shear + c * pose.sy
        for sample in samples {
          let px = pose.x + a11 * sample.u + a12 * sample.v
          let py = pose.y + a21 * sample.u + a22 * sample.v
          let x = interpolate ? Int(floor(px - 0.5)) : Int(px)
          let y = interpolate ? Int(floor(py - 0.5)) : Int(py)
          guard x >= region.x, y >= region.y,
            x < region.x + region.width, y < region.y + region.height else { return -1 }
          let i = y * frame.rowBytes + x * 4
          var r = Double(bytes[i + redIndex]), g = Double(bytes[i + 1]), b = Double(bytes[i + 2 - redIndex])
          if interpolate {
            let fx = px - 0.5 - Double(x), fy = py - 0.5 - Double(y)
            let next = x + 1 < frame.width ? 4 : 0
            let j = min(y + 1, frame.height - 1) * frame.rowBytes + x * 4
            func channel(_ offset: Int) -> Double {
              let top = Double(bytes[i + offset]) * (1 - fx) + Double(bytes[i + next + offset]) * fx
              let bottom = Double(bytes[j + offset]) * (1 - fx) + Double(bytes[j + next + offset]) * fx
              return top * (1 - fy) + bottom * fy
            }
            r = channel(redIndex); g = channel(1); b = channel(2 - redIndex)
          }
          sr += r; sg += g; sb += b
          tr += sample.r; tg += sample.g; tb += sample.b
          ss += r*r + g*g + b*b
          tt += sample.r*sample.r + sample.g*sample.g + sample.b*sample.b
          st += r*sample.r + g*sample.g + b*sample.b
        }
        let n = Double(samples.count)
        let a = ss - (sr*sr + sg*sg + sb*sb) / n
        let b = tt - (tr*tr + tg*tg + tb*tb) / n
        guard a > n * 3 * 16, b > n * 3 * 16 else { return -1 }
        let correlation = (st - (sr*tr + sg*tg + sb*tb) / n) / sqrt(a*b)
        let colorDifference = (abs(sr-tr) + abs(sg-tg) + abs(sb-tb)) / (n * 765)
        return correlation - colorDifference * 0.15
      }
      var candidates: [Pose] = []
      func retain(_ candidate: Pose) {
        guard candidate.score > 0.20 else { return }
        if let index = candidates.firstIndex(where: {
          abs($0.x - candidate.x) < w * 0.3 && abs($0.y - candidate.y) < h * 0.3
        }) {
          if candidate.score > candidates[index].score { candidates[index] = candidate }
        } else { candidates.append(candidate) }
        candidates.sort { $0.score > $1.score }
        if candidates.count > 12 { candidates.removeLast() }
      }
      let stridePixels = max(1, min(8, Int(min(w, h) / 12)))
      for scale in [0.85, 1.0, 1.15] {
        for y in stride(from: region.y, to: region.y + region.height, by: stridePixels) {
          try Task.checkCancellation()
          for x in stride(from: region.x, to: region.x + region.width, by: stridePixels) {
            var pose = Pose(x: Double(x), y: Double(y), sx: scale, sy: scale)
            pose.score = score(pose, coarse)
            retain(pose)
          }
        }
      }
      var refined: [Pose] = []
      for var pose in candidates {
        // Coarse samples can favor an adjacent scale/translation basin. Search
        // the local translation grid at every coarse scale before affine descent.
        let seed = pose
        pose.score = score(pose, fine, interpolate: true)
        let localStep = max(1, stridePixels / 2)
        for scale in [0.85, 1.0, 1.15] {
          for dy in stride(from: -stridePixels, through: stridePixels, by: localStep) {
            for dx in stride(from: -stridePixels, through: stridePixels, by: localStep) {
              let trial = Pose(x: seed.x + Double(dx), y: seed.y + Double(dy), sx: scale, sy: scale)
              let value = score(trial, fine, interpolate: true)
              if value > pose.score { pose = trial; pose.score = value }
            }
          }
        }
        for step in [Double(stridePixels), Double(stridePixels) / 2, 1.0, 0.5] {
          for _ in 0..<3 {
            try Task.checkCancellation()
            let initial = pose
            for parameter in 0..<6 {
              for sign in [-1.0, 1.0] {
                var trial = pose
                switch parameter {
                case 0: trial.x += sign * step
                case 1: trial.y += sign * step
                case 2: trial.sx += sign * step / w
                case 3: trial.sy += sign * step / h
                case 4: trial.angle += sign * step / max(w, h)
                default: trial.shear += sign * step / max(w, h)
                }
                guard (0.8...1.25).contains(trial.sx), (0.8...1.25).contains(trial.sy),
                  abs(trial.angle) <= 0.175, abs(trial.shear) <= 0.12 else { continue }
                trial.score = score(trial, fine, interpolate: true)
                if trial.score > pose.score { pose = trial }
              }
            }
            if pose.score == initial.score { break }
          }
        }
        refined.append(pose)
      }
      refined.sort { $0.score > $1.score }
      guard let best = refined.first, best.score >= 0.82 else {
        return .failed("Cap tracking lost: the selected visual pattern is not visible or the match is too weak. Identify Pen Cap again if the pen changed.")
      }
      if let competitor = refined.dropFirst().first(where: {
        abs($0.x - best.x) > w * 0.4 || abs($0.y - best.y) > h * 0.4
      }), best.score - competitor.score < 0.06 {
        return .failed("Cap tracking ambiguous: more than one region matches the selected pattern.")
      }
      let corners = [(-w/2,-h/2),(w/2,-h/2),(-w/2,h/2),(w/2,h/2)].map { best.point($0.0,$0.1) }
      let minX = Int(floor(corners.map(\.0).min()!)), minY = Int(floor(corners.map(\.1).min()!))
      let maxX = Int(ceil(corners.map(\.0).max()!)), maxY = Int(ceil(corners.map(\.1).max()!))
      guard minX >= region.x, minY >= region.y, maxX <= region.x + region.width,
        maxY <= region.y + region.height else { return .failed("Cap tracking lost: the reference is clipped by the image edge.") }
      let (x, y) = best.point(reference.anchor.x - Double(reference.region.x) - w/2,
        reference.anchor.y - Double(reference.region.y) - h/2)
      let box = PixelRect(x: minX, y: minY, width: maxX-minX, height: maxY-minY)
      return .found(PenCapMeasurement(referenceAnchor: try Point2(x: x, y: y),
        pixelCount: reference.rgb.count / 3,
        boundingBox: box, centroid: try Point2(x: best.x, y: best.y), confidence: min(1, best.score)),
        diagnostics: PenCapDiagnostics(inspectedPixelCount: region.width * region.height,
          thresholdPixelCount: reference.rgb.count / 3, componentCount: refined.count, candidates: []))
    }
  }
}
