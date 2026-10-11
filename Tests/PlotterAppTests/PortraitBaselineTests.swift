@testable import PortraitArtists
import CryptoKit
import Foundation
import PlotterModel
import Testing
@testable import PlotterApp

/// Frozen before Studio extraction. Changing expected values is an explicit
/// baseline revision, never an automatic consequence of running this test.
@Suite("Portrait Studio frozen renderer baseline", .serialized)
struct PortraitBaselineTests {
  @Test("current artists retain exact authored output", arguments: [PortraitStyle.flowEdges, .contours, .sketch])
  func frozenOutput(style: PortraitStyle) throws {
    let pixels = Self.pixels()
    let inputSHA256 = SHA256.hash(data: Data(pixels)).map { String(format: "%02x", $0) }.joined()
    let raster = PortraitRaster(width: 96, height: 128,
      luminance: pixels.map { Double($0) / 255 },
      provenance: "portrait-baseline-integer-face-96x128-v1",
      analysisSummary: "Portable synthetic baseline; no Vision or camera",
      sourceCropExtent: try .init(widthPixels: 96, heightPixels: 128))
    let options = PortraitVectorPreset.balanced.options(for: style)
    let program = try PortraitVectorizer.program(from: raster, pose: .front,
      style: style, strokeStyle: portraitTestStyle(), vectorOptions: options)
    let repeated = try PortraitVectorizer.program(from: raster, pose: .front,
      style: style, strokeStyle: portraitTestStyle(), vectorOptions: options)
    let pointCount = program.strokes.reduce(0) { $0 + $1.path.points.count }
    let report = Report(fixture: raster.provenance, inputSHA256: inputSHA256,
      style: style.rawValue, strokeCount: program.strokes.count, pointCount: pointCount,
      programSHA256: program.contentHash.description)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
    let reportBytes = try encoder.encode(report)
    print("PORTRAIT_BASELINE " + String(decoding: reportBytes, as: UTF8.self))
    if let directory = ProcessInfo.processInfo.environment["PORTRAIT_BASELINE_OUTPUT"] {
      let root = URL(fileURLWithPath: directory, isDirectory: true)
      try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
      let name = style.rawValue.replacingOccurrences(of: " ", with: "-")
      try reportBytes.write(to: root.appendingPathComponent(name + ".report.json"), options: .atomic)
      try encoder.encode(program).write(to: root.appendingPathComponent(name + ".program.json"), options: .atomic)
      try encoder.encode(options).write(to: root.appendingPathComponent(name + ".options.json"), options: .atomic)
      try (Data("P5\n96 128\n255\n".utf8) + Data(pixels))
        .write(to: root.appendingPathComponent("input.pgm"), options: .atomic)
    }
    #expect(program == repeated)
    #expect(program.fieldExtent.width == 75 && program.fieldExtent.height == 100)
    #expect(inputSHA256 == "2493f5340ca94eb682cf54869c9d6ed85cdd9e8515fecb625175108eb1b66cdb")
    let expected: (strokes: Int, points: Int, hash: String)
    switch style {
    case .flowEdges: expected = (6, 561, "f25cf16b4a21f9f5fbf12cd125ac919fcf42a089728fe2066b2e7c365cbe603c")
    case .contours: expected = (12, 181, "9f0065a14f51efb4784030af95742604beae7e4efea46c4307a4fd7bab3ff529")
    case .sketch: expected = (8, 73, "0ddd07660e46aab1fb2c3b9c729a29d110852b6d9ff91c4cebc049c54f4b9042")
    default: Issue.record("Unsupported baseline artist"); return
    }
    #expect(program.strokes.count == expected.strokes)
    #expect(pointCount == expected.points)
    #expect(program.contentHash.description == expected.hash)
  }

  private struct Report: Encodable {
    let fixture: String
    let inputSHA256: String
    let style: String
    let strokeCount: Int
    let pointCount: Int
    let programSHA256: String
  }

  /// Integer-only construction fixes the input bytes independently of libm,
  /// CoreGraphics color conversion, face detection, and image codec versions.
  private static func pixels() -> [UInt8] {
    (0..<(96 * 128)).map { index in
      let x = index % 96, y = index / 96
      let dx = x - 48, dy = y - 60
      let radius = dx * dx * 2500 + dy * dy * 1024
      guard radius < 1024 * 2500 else { return 245 }
      var value = 90 + radius * 100 / (1024 * 2500) + x / 3
      if y < 31 + abs(dx) / 5 { value = 35 + x / 4 }
      if (abs(x - 35) <= 6 || abs(x - 61) <= 6) && abs(y - 51) <= 2 { value = 20 }
      if abs(x - 51) <= 2 && (58...73).contains(y) { value = 70 }
      if abs(dx) <= 11 && abs(y - 82) <= 2 { value = 45 }
      return UInt8(value)
    }
  }
}
