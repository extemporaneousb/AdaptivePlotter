import CoreGraphics
import CoreText
import Foundation
import PlotterModel
import Testing
@testable import PlotterApp

@Suite("Rectilinear Flow tracing and reference geometry")
struct PortraitRectilinearFlowTests {
  @Test("Dominant direction produces one long finite straight segment without stair steps")
  func straightGeometry() throws {
    for tangent in [CGPoint(x: 0.8, y: 0.6), CGPoint(x: 0.2, y: 0.9), CGPoint(x: 1, y: 1)] {
      let result = try #require(try PortraitRectilinearFlowTracer.trace(
        seed: CGPoint(x: 80, y: 64), tangent: tangent, width: 160, height: 128,
        minimumLength: 12, spacing: { _ in 3 }, luminance: { _ in 0.3 }, intersects: { _, _ in false }))
      let horizontal = abs(tangent.x) >= abs(tangent.y)
      #expect(result.endpoints.count == 2)
      #expect(result.sampledPath.first == result.endpoints.first)
      #expect(result.sampledPath.last == result.endpoints.last)
      #expect(result.sampledPath.count > 100)
      #expect(result.radii.count == result.sampledPath.count)
      #expect(result.sampledPath.allSatisfy { point in
        point.x.isFinite && point.y.isFinite && point.x >= 1 && point.x < 158
          && point.y >= 1 && point.y < 126 && (horizontal ? point.y == 64 : point.x == 80)
      })
      #expect(zip(result.sampledPath, result.sampledPath.dropFirst()).allSatisfy {
        abs(hypot($1.x - $0.x, $1.y - $0.y) - 0.9) < 1e-10
      })
      let reversed = try PortraitRectilinearFlowTracer.trace(
        seed: CGPoint(x: 80, y: 64), tangent: CGPoint(x: -tangent.x, y: -tangent.y),
        width: 160, height: 128, minimumLength: 12, spacing: { _ in 3 },
        luminance: { _ in 0.3 }, intersects: { _, _ in false })
      #expect(result == reversed)
    }
  }

  @Test("Interior barriers stop a segment before its endpoints could bridge reserved ink")
  func interiorBarrier() throws {
    var checked: [CGPoint] = []
    let result = try #require(try PortraitRectilinearFlowTracer.trace(
      seed: CGPoint(x: 48, y: 48), tangent: CGPoint(x: 1, y: 0.1), width: 160, height: 96,
      minimumLength: 12, spacing: { _ in 4 }, luminance: { _ in 0.2 },
      intersects: { point, radius in
        checked.append(point)
        return abs(point.x - 82) < radius + 0.6
      }))
    #expect(result.endpoints[0].x < 2)
    #expect(result.endpoints[1].x <= 82 - 4.6)
    #expect(checked.contains { $0.x > result.endpoints[1].x })
    #expect(result.sampledPath.allSatisfy { abs($0.x - 82) >= 4.6 })
    #expect(result.radii.allSatisfy { $0 == 4 })
  }

  @Test("Local spacing is checked and retained throughout the segment")
  func changingClearance() throws {
    let spacing: (CGPoint) -> Double = { $0.x < 70 ? 2 : 8 }
    let result = try #require(try PortraitRectilinearFlowTracer.trace(
      seed: CGPoint(x: 48, y: 48), tangent: CGPoint(x: 1, y: 0), width: 160, height: 96,
      minimumLength: 12, spacing: spacing, luminance: { _ in 0.2 },
      intersects: { point, radius in abs(point.x - 90) < radius + 0.6 }))
    #expect(result.endpoints[1].x <= 90 - 8.6)
    #expect(zip(result.sampledPath, result.radii).allSatisfy { $1 == spacing($0) })
    #expect(result.radii.contains(2))
    #expect(result.radii.contains(8))
  }

  @Test("Light gaps and reserved seeds reject crossing or fragmented strokes")
  func stopsAndRejects() throws {
    let lit = try #require(try PortraitRectilinearFlowTracer.trace(
      seed: CGPoint(x: 48, y: 48), tangent: CGPoint(x: 1, y: 0), width: 160, height: 96,
      minimumLength: 12, spacing: { _ in 3 },
      luminance: { abs($0.x - 75) < 2 ? 1 : 0.2 }, intersects: { _, _ in false }))
    #expect(lit.endpoints[1].x <= 73)
    #expect(try PortraitRectilinearFlowTracer.trace(
      seed: CGPoint(x: 48, y: 48), tangent: CGPoint(x: 1, y: 0), width: 160, height: 96,
      minimumLength: 12, spacing: { _ in 3 }, luminance: { _ in 0.2 },
      intersects: { point, _ in abs(point.x - 48) >= 3 }) == nil)
    #expect(try PortraitRectilinearFlowTracer.trace(
      seed: CGPoint(x: 48, y: 48), tangent: CGPoint(x: 1, y: 0), width: 160, height: 96,
      minimumLength: 12, spacing: { _ in 3 }, luminance: { _ in 0.2 },
      intersects: { _, _ in true }) == nil)
    #expect(try PortraitRectilinearFlowTracer.trace(
      seed: CGPoint(x: 48, y: 48), tangent: CGPoint(x: 1, y: 0), width: 160, height: 96,
      minimumLength: 12, spacing: { _ in .nan }, luminance: { _ in 0.2 },
      intersects: { _, _ in false }) == nil)
  }

  @Test("Cancelled tracing does not publish a segment")
  func cancellation() async {
    let task = Task {
      withUnsafeCurrentTask { $0?.cancel() }
      return try PortraitRectilinearFlowTracer.trace(
        seed: CGPoint(x: 48, y: 48), tangent: CGPoint(x: 1, y: 0), width: 160, height: 96,
        minimumLength: 12, spacing: { _ in 3 }, luminance: { _ in 0.2 }, intersects: { _, _ in false })
    }
    await #expect(throws: CancellationError.self) { try await task.value }
  }

  @Test("Absent and zero line form preserve existing recipe encoding and geometry")
  func archiveCompatibility() throws {
    let legacyData = Data("{\"hatchSpacing\":8,\"smoothing\":1.5}".utf8)
    let legacy = try JSONDecoder().decode(PortraitVectorOptions.self, from: legacyData)
    #expect(legacy.flowRectilinearity == nil)
    let encoded = try JSONEncoder().encode(legacy)
    let dictionary = try #require(try JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    #expect(dictionary["flowRectilinearity"] == nil)
    var zero = legacy; zero.flowRectilinearity = 0
    #expect(zero.bounded == legacy.bounded)
    #expect(zero.bounded.provenance == legacy.bounded.provenance)
    let encoder = PortraitCandidateCoding.encoder()
    let zeroEncoding = try encoder.encode(zero.bounded)
    let legacyEncoding = try encoder.encode(legacy.bounded)
    #expect(zeroEncoding == legacyEncoding)
    let raster = rectilinearReferenceRaster()
    let first = try PortraitFlowRenderer.layers(from: raster, options: legacy.bounded)
    let second = try PortraitFlowRenderer.layers(from: raster, options: zero.bounded)
    #expect(first.structure == second.structure)
    #expect(first.tone == second.tone)
  }

  @Test("Line form bounds retain valid mixtures and canonicalize absent or invalid forms")
  func optionBounds() {
    for value in [0, -1, Double.nan, Double.infinity, -Double.infinity] {
      var options = PortraitVectorOptions.flowDefaults
      options.flowRectilinearity = value
      #expect(options.bounded.flowRectilinearity == nil)
      #expect(options.bounded.provenance == PortraitVectorOptions.flowDefaults.provenance)
    }
    var mixed = PortraitVectorOptions.flowDefaults
    mixed.flowRectilinearity = 0.5
    #expect(mixed.bounded.flowRectilinearity == 0.5)
    #expect(mixed.bounded.provenance != PortraitVectorOptions.flowDefaults.provenance)
    mixed.flowRectilinearity = 3
    #expect(mixed.bounded.flowRectilinearity == 1)
  }

  @Test("Opt-in local photo compares organic, mixed and rectilinear line forms")
  func referencePhoto() async throws {
    let environment = ProcessInfo.processInfo.environment
    guard let input = environment["PORTRAIT_FLOW_REFERENCE_PHOTO"],
      let output = environment["PORTRAIT_FLOW_REFERENCE_OUTPUT"] else { return }
    let data = try Data(contentsOf: URL(fileURLWithPath: input))
    let analyzer = PortraitImageAnalyzer(), clock = ContinuousClock()
    var cached: PortraitRaster?, programs: [(String, DrawingProgram)] = [], timings: [Double] = []
    var workspace: PortraitFlowRenderer.Workspace?
    for (label, amount) in [("Organic", 0.0), ("Mixed", 0.5), ("Rectilinear", 1.0)] {
      var options = PortraitVectorOptions.flowDefaults
      options.flowRectilinearity = amount > 0 ? amount : nil
      let start = clock.now
      let rendered = try await analyzer.render(.init(data: data, pose: .front, style: .flowEdges,
        options: .init(), cachedRaster: cached, strokeStyle: portraitTestStyle(), vectorOptions: options,
        flowWorkspace: workspace))
      let elapsed = start.duration(to: clock.now)
      timings.append(Double(elapsed.components.seconds) * 1000 + Double(elapsed.components.attoseconds) / 1e15)
      cached = rendered.raster; workspace = rendered.flowWorkspace
      programs.append((label, rendered.program))
    }
    let directory = URL(fileURLWithPath: output, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try rectilinearReferenceSheet(photo: PortraitImageAnalyzer.image(from: data), programs: programs)
      .write(to: directory.appendingPathComponent("flow-line-forms.png"))
    #if DEBUG
    let configuration = "debug"
    #else
    let configuration = "release"
    #endif
    let report: [String: Any] = ["revision": PortraitFlowRenderer.revision,
      "buildConfiguration": configuration,
      "labels": programs.map(\.0), "renderMS": timings,
      "firstTimingIncludesAnalysis": true,
      "strokeCounts": programs.map { $0.1.strokes.count },
      "pointCounts": programs.map { $0.1.strokes.reduce(0) { $0 + $1.path.points.count } },
      "scope": "Local digital geometry comparison; no physical ink or likeness validation"]
    let reportData = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
    try reportData.write(to: directory.appendingPathComponent("flow-line-forms.json"))
    print("PORTRAIT_FLOW_LINE_FORMS " + String(decoding: reportData, as: UTF8.self))
  }
}

private func rectilinearReferenceRaster() -> PortraitRaster {
  let width = 48, height = 64
  return PortraitRaster(width: width, height: height,
    luminance: (0..<height).flatMap { y in (0..<width).map { x in
      min(0.88, 0.2 + hypot(Double(x - 24), Double(y - 32)) / 75)
    } }, provenance: "rectilinear-reference", analysisSummary: "Synthetic tracing fixture",
    sourceCropExtent: try! .init(widthPixels: Double(width), heightPixels: Double(height)))
}

private func rectilinearReferenceSheet(photo: CGImage, programs: [(String, DrawingProgram)]) throws -> Data {
  let tileWidth = 400, tileHeight = 470, tileCount = programs.count + 1
  let context = try #require(CGContext(data: nil, width: tileWidth * tileCount, height: tileHeight,
    bitsPerComponent: 8, bytesPerRow: tileWidth * tileCount * 4, space: CGColorSpaceCreateDeviceRGB(),
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
  context.setFillColor(CGColor(gray: 1, alpha: 1))
  context.fill(CGRect(x: 0, y: 0, width: tileWidth * tileCount, height: tileHeight))
  for index in 0..<tileCount {
    let bounds = CGRect(x: index * tileWidth + 22, y: 22, width: tileWidth - 44, height: tileHeight - 65)
    let title = index == 0 ? "Source photo" : programs[index - 1].0
    let line = CTLineCreateWithAttributedString(NSAttributedString(string: title,
      attributes: [NSAttributedString.Key(kCTFontAttributeName as String): CTFontCreateWithName("Helvetica" as CFString, 16, nil)]))
    context.textPosition = CGPoint(x: bounds.minX, y: Double(tileHeight - 25)); CTLineDraw(line, context)
    if index == 0 {
      let scale = min(bounds.width / Double(photo.width), bounds.height / Double(photo.height))
      context.draw(photo, in: CGRect(x: bounds.midX - Double(photo.width) * scale / 2,
        y: bounds.midY - Double(photo.height) * scale / 2,
        width: Double(photo.width) * scale, height: Double(photo.height) * scale))
    } else {
      let program = programs[index - 1].1
      let scale = min(bounds.width / program.fieldExtent.width, bounds.height / program.fieldExtent.height)
      let dx = bounds.midX - program.fieldExtent.width * scale / 2
      let dy = bounds.midY - program.fieldExtent.height * scale / 2
      context.setStrokeColor(CGColor(gray: 0.05, alpha: 1)); context.setLineWidth(0.7)
      context.setLineCap(.round); context.setLineJoin(.round)
      for stroke in program.strokes {
        guard let first = stroke.path.points.first else { continue }
        context.move(to: CGPoint(x: dx + first.x * scale, y: dy + first.y * scale))
        for point in stroke.path.points.dropFirst() {
          context.addLine(to: CGPoint(x: dx + point.x * scale, y: dy + point.y * scale))
        }
        context.strokePath()
      }
    }
  }
  let image = try #require(context.makeImage())
  return try PortraitImageAnalyzer.encodedImage(image)
}
