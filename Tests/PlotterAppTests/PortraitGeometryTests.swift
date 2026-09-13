import CoreGraphics
import CryptoKit
import Foundation
import ImageIO
import UniformTypeIdentifiers
import PlotterModel
import Testing

@testable import PlotterApp

@Suite("Portrait source metric")
struct PortraitGeometryTests {
  @Test("decoded source crop survives integer sampling and both 8/160 clamps",
    arguments: [(4000, 100), (100, 4000), (901, 1600), (1600, 901), (100, 100)])
  func sourceImageMetric(_ dimensions: (Int, Int)) throws {
    let (width, height) = dimensions
    let data = try image(width: width, height: height)
    let decoded = try PortraitImageAnalyzer.decodedImage(from: data)
    #expect(max(decoded.image.width, decoded.image.height) <= 1200)
    #expect(decoded.sourcePixelExtent.widthPixels == Double(width))
    #expect(decoded.sourcePixelExtent.heightPixels == Double(height))
    let raster = try PortraitImageAnalyzer.analyze(data: data,
      options: PortraitAnalysisOptions(cropToFace: false, removeBackground: false))
    let crop = try #require(raster.sourceCropExtent)
    #expect(crop.widthPixels == Double(width))
    #expect(crop.heightPixels == Double(height))
    let ratio = Double(width) / Double(height)
    #expect(raster.width == max(8, min(160, Int(160 * ratio))))
    #expect(raster.height == max(8, min(160, Int(160 / ratio))))
    let program = try PortraitVectorizer.program(from: raster, pose: .front, style: .hatch,
      strokeStyle: portraitTestStyle())
    #expect(abs(program.fieldExtent.width / program.fieldExtent.height - ratio) < 1e-12)
    // Exercise the actual legacy path as the pre-fix counterexample, with the
    // very same analyzed samples and vertices and only the crop metric missing.
    let legacyRaster = PortraitRaster(width: raster.width, height: raster.height,
      luminance: raster.luminance, provenance: raster.provenance,
      analysisSummary: raster.analysisSummary, faceBounds: raster.faceBounds)
    let legacyProgram = try PortraitVectorizer.program(from: legacyRaster, pose: .front, style: .hatch,
      strokeStyle: portraitTestStyle())
    let legacyRatio = legacyProgram.fieldExtent.width / legacyProgram.fieldExtent.height
    if width != height { #expect(abs(legacyRatio / ratio - 1) > 1e-4) }
    let receipt = "sourceSHA256=\(sha256(data)) analysis=\(raster.provenance) "
      + "metric=\(raster.metricProvenance) legacyProgram=\(legacyProgram.contentHash) program=\(program.contentHash)"
    print("DS-01 portrait geometry fixture: \(receipt)")
    try retainFixture(name: "\(width)x\(height)", source: data, raster: raster,
      program: program, legacyProgram: legacyProgram)
    #expect(program.source.sourceIdentifier.contains("portrait-v3|metric=source-crop-pixels-v1"))
  }

  @Test("bounded acquisition preserves source metric across normalized PNG rounding")
  func acquisitionMetric() async throws {
    let source = try image(width: 901, height: 1600)
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("ds01-source-\(UUID()).png")
    defer { try? FileManager.default.removeItem(at: url) }
    try source.write(to: url)
    let photo = try await PortraitImageAnalyzer().acquire(.file(url))
    let normalized = try PortraitImageAnalyzer.image(from: photo.data)
    #expect(max(normalized.width, normalized.height) <= 1200)
    #expect(photo.sourcePixelExtent == (try PortraitSourceCropExtent(widthPixels: 901, heightPixels: 1600)))
    let ratio = 901.0 / 1600.0
    #expect(abs(Double(normalized.width) / Double(normalized.height) - ratio) > 1e-5)
    let result = try await PortraitImageAnalyzer().render(PortraitRenderRequest(
      data: photo.data, pose: .front, style: .hatch,
      options: PortraitAnalysisOptions(cropToFace: false, removeBackground: false),
      cachedRaster: nil, strokeStyle: portraitTestStyle(), sourcePixelExtent: photo.sourcePixelExtent))
    #expect(abs(result.program.fieldExtent.width / result.program.fieldExtent.height - ratio) < 1e-12)
  }

  @Test("fractional original crop metric is distinct from rounded thumbnail crop dimensions")
  func fractionalCropMetric() throws {
    let original = try PortraitSourceCropExtent(widthPixels: 901, heightPixels: 1600)
    let crop = try PortraitImageAnalyzer.cropMetric(sourcePixelExtent: original,
      decodedWidth: 676, decodedHeight: 1200, cropWidth: 301, cropHeight: 703)
    #expect(abs(crop.widthPixels - 901.0 * 301.0 / 676.0) < 1e-10)
    #expect(abs(crop.heightPixels - 1600.0 * 703.0 / 1200.0) < 1e-10)
    #expect(crop.widthPixels != crop.widthPixels.rounded())
    #expect(abs(crop.aspectRatio - 301.0 / 703.0) > 1e-5)
    #expect(try JSONDecoder().decode(PortraitSourceCropExtent.self,
      from: JSONEncoder().encode(crop)) == crop)
  }

  @Test("extreme finite source ratios clamp before integer conversion; invalid metrics fail")
  func extremeFiniteMetric() throws {
    let data = try image(width: 10, height: 10)
    for ratio in [1e100, 1e-100] {
      let source = try PortraitSourceCropExtent(widthPixels: ratio, heightPixels: 1)
      let raster = try PortraitImageAnalyzer.analyze(data: data,
        options: PortraitAnalysisOptions(cropToFace: false, removeBackground: false),
        sourcePixelExtent: source)
      #expect(raster.width == (ratio > 1 ? 160 : 8))
      #expect(raster.height == (ratio > 1 ? 8 : 160))
      #expect(raster.sourceCropExtent == source)
    }
    for width in [Double.infinity, Double.nan, 0, -1, Double.greatestFiniteMagnitude] {
      #expect(throws: (any Error).self) { try PortraitSourceCropExtent(widthPixels: width, heightPixels: 1) }
    }
    #expect(throws: (any Error).self) {
      try PortraitSourceCropExtent(widthPixels: Double.leastNonzeroMagnitude,
        heightPixels: Double.greatestFiniteMagnitude)
    }
  }

  @Test("oriented source dimensions follow the thumbnail's EXIF axis swap")
  func orientedSourceMetric() throws {
    let upright = try PortraitImageAnalyzer.image(from: image(width: 16, height: 32))
    let data = NSMutableData()
    let destination = try #require(CGImageDestinationCreateWithData(data,
      UTType.tiff.identifier as CFString, 1, nil))
    CGImageDestinationAddImage(destination, upright, [kCGImagePropertyOrientation: 6] as CFDictionary)
    #expect(CGImageDestinationFinalize(destination))
    let decoded = try PortraitImageAnalyzer.decodedImage(from: data as Data)
    #expect(decoded.sourcePixelExtent.widthPixels == 32)
    #expect(decoded.sourcePixelExtent.heightPixels == 16)
    #expect(decoded.image.width == 32)
    #expect(decoded.image.height == 16)
  }

  @Test("each renderer maps identical sampled vertices through the explicit crop metric",
    arguments: PortraitStyle.allCases)
  func analyticVertexAndSegmentMapping(_ style: PortraitStyle) throws {
    let original = portraitTestRaster()
    let source = try PortraitSourceCropExtent(widthPixels: 4000, heightPixels: 100)
    let corrected = PortraitRaster(width: original.width, height: original.height,
      luminance: original.luminance, provenance: original.provenance,
      analysisSummary: original.analysisSummary, sourceCropExtent: source)
    let oldProgram = try PortraitVectorizer.program(from: original, pose: .front,
      style: style, strokeStyle: portraitTestStyle())
    let newProgram = try PortraitVectorizer.program(from: corrected, pose: .front,
      style: style, strokeStyle: portraitTestStyle())
    #expect(oldProgram.strokes.count == newProgram.strokes.count)
    let xFactor = newProgram.fieldExtent.width / oldProgram.fieldExtent.width
      * Double(original.width - 1) / Double(original.width)
    let yFactor = Double(original.height - 1) / Double(original.height)
    let xOffset = newProgram.fieldExtent.width * 0.5 / Double(original.width)
    let yOffset = newProgram.fieldExtent.height * 0.5 / Double(original.height)
    for (before, after) in zip(oldProgram.strokes, newProgram.strokes) {
      #expect(before.path.points.count == after.path.points.count)
      for (old, new) in zip(before.path.points, after.path.points) {
        // Analytic coordinates, including the interior vertices: X uses original
        // source-image metric while Y retains the existing top-left -> +Y-up flip.
        #expect(abs(new.x - (old.x * xFactor + xOffset)) < 1e-9)
        #expect(abs(new.y - (old.y * yFactor + yOffset)) < 1e-9)
      }
      for index in 1..<after.path.points.count {
        let oldA = before.path.points[index - 1], oldB = before.path.points[index]
        let newA = after.path.points[index - 1], newB = after.path.points[index]
        let expectedLength = hypot((oldB.x - oldA.x) * xFactor, (oldB.y - oldA.y) * yFactor)
        #expect(abs(hypot(newB.x - newA.x, newB.y - newA.y) - expectedLength) < 1e-9)
        let sampleDX = (oldB.x - oldA.x) / oldProgram.fieldExtent.width * Double(original.width - 1)
        let sampleDY = -(oldB.y - oldA.y) / oldProgram.fieldExtent.height * Double(original.height - 1)
        // Assert each sample-basis length in the retained original crop metric.
        if abs(sampleDX) > 1e-6 {
          #expect(abs((newB.x - newA.x) / sampleDX
            - newProgram.fieldExtent.width / Double(original.width)) < 1e-6)
        }
        if abs(sampleDY) > 1e-6 {
          #expect(abs(-(newB.y - newA.y) / sampleDY
            - newProgram.fieldExtent.height / Double(original.height)) < 1e-6)
        }
      }
    }
    #expect(newProgram.id != oldProgram.id)
    #expect(newProgram.contentHash != oldProgram.contentHash)
  }

  @Test("crop metric and analyzed samples round trip and survive preprocessing")
  func durableMetricAndHash() throws {
    let original = portraitTestRaster()
    let raster = PortraitRaster(width: original.width, height: original.height,
      luminance: original.luminance, provenance: original.provenance,
      analysisSummary: original.analysisSummary, faceBounds: CGRect(x: 0.2, y: 0.1, width: 0.6, height: 0.7),
      sourceCropExtent: try PortraitSourceCropExtent(widthPixels: 900, heightPixels: 1600))
    let data = try JSONEncoder().encode(raster)
    let decoded = try JSONDecoder().decode(PortraitRaster.self, from: data)
    #expect(decoded.sourceCropExtent == raster.sourceCropExtent)
    #expect(decoded.faceBounds == raster.faceBounds)
    #expect(decoded.luminance == raster.luminance)
    let first = try PortraitVectorizer.program(from: raster, pose: .front, style: .contours,
      strokeStyle: portraitTestStyle())
    let restored = try PortraitVectorizer.program(from: decoded, pose: .front, style: .contours,
      strokeStyle: portraitTestStyle())
    #expect(first == restored)
    #expect(first.fieldExtent.width == 56.25)
    #expect(try JSONDecoder().decode(DrawingProgram.self, from: JSONEncoder().encode(first)) == first)
  }

  @Test("legacy raster data preserves its declared unknown source metric; future versions and invalid extents fail")
  func legacyAndInvalidDecoding() throws {
    let original = portraitTestRaster()
    let encoded = try JSONEncoder().encode(original)
    var json = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    json.removeValue(forKey: "schemaVersion")
    let legacy = try JSONDecoder().decode(PortraitRaster.self,
      from: JSONSerialization.data(withJSONObject: json))
    #expect(legacy.sourceCropExtent == nil)
    #expect(legacy.metricProvenance == "legacy-sample-lattice-v1=79x99")
    let program = try PortraitVectorizer.program(from: legacy, pose: .front, style: .hatch,
      strokeStyle: portraitTestStyle())
    #expect(abs(program.fieldExtent.width - 100 * 79.0 / 99.0) < 1e-12)
    json["schemaVersion"] = PortraitRaster.schemaVersion + 1
    let future = try JSONSerialization.data(withJSONObject: json)
    #expect(throws: DecodingError.self) { try JSONDecoder().decode(PortraitRaster.self, from: future) }
    json["schemaVersion"] = PortraitRaster.schemaVersion
    json["sourceCropExtent"] = ["widthPixels": 0, "heightPixels": 100]
    let invalid = try JSONSerialization.data(withJSONObject: json)
    #expect(throws: (any Error).self) { try JSONDecoder().decode(PortraitRaster.self, from: invalid) }
  }

  private func retainFixture(name: String, source: Data, raster: PortraitRaster,
    program: DrawingProgram, legacyProgram: DrawingProgram) throws {
    guard let path = ProcessInfo.processInfo.environment["ADAPTIVEPLOTTER_GEOMETRY_EVIDENCE_DIRECTORY"] else { return }
    let directory = URL(fileURLWithPath: path).appendingPathComponent(name, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
    let analysis = try encoder.encode(raster)
    let programData = try encoder.encode(program)
    try source.write(to: directory.appendingPathComponent("source.png"), options: .atomic)
    try analysis.write(to: directory.appendingPathComponent("raster.json"), options: .atomic)
    try programData.write(to: directory.appendingPathComponent("program.json"), options: .atomic)
    try encoder.encode(legacyProgram).write(to: directory.appendingPathComponent("legacy-program.json"), options: .atomic)
    let trace: [String: String] = [
      "sourceSHA256": sha256(source), "rasterJSONSHA256": sha256(analysis),
      "programJSONSHA256": sha256(programData), "programContentHash": String(describing: program.contentHash),
      "legacyProgramContentHash": String(describing: legacyProgram.contentHash),
      "analysisProvenance": raster.provenance, "metricProvenance": raster.metricProvenance,
      "sampleToField": "x=(sampleX+0.5)/width*fieldWidth; y=(1-(sampleY+0.5)/height)*fieldHeight",
      "evidenceClass": "Software fixture; no physical metric or attended drawing evidence"
    ]
    try encoder.encode(trace).write(to: directory.appendingPathComponent("trace.json"), options: .atomic)
  }

  private func image(width: Int, height: Int) throws -> Data {
    let bytes = Data((0..<(width * height)).map { index in
      UInt8(index / width < height / 2 ? 0 : 255)
    })
    let provider = try #require(CGDataProvider(data: bytes as CFData))
    let image = try #require(CGImage(width: width, height: height, bitsPerComponent: 8,
      bitsPerPixel: 8, bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(),
      bitmapInfo: CGBitmapInfo(rawValue: 0), provider: provider, decode: nil,
      shouldInterpolate: false, intent: .defaultIntent))
    return try PortraitImageAnalyzer.encodedImage(image)
  }

  private func sha256(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }
}
