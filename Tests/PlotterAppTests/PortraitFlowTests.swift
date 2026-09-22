import CoreGraphics
import CoreText
import Foundation
import PlotterModel
import Testing
@testable import PlotterApp

@Suite("Flow Edge evidence and plot geometry")
struct PortraitFlowTests {
  @Test("Flow output is deterministic, finite, bounded and independent of legacy gamma")
  func deterministic() throws {
    let raster = flowFace()
    let options = PortraitVectorOptions.flowDefaults
    let first = try PortraitVectorizer.program(from: raster, pose: .front, style: .flowEdges,
      strokeStyle: portraitTestStyle(), vectorOptions: options)
    let second = try PortraitVectorizer.program(from: raster, pose: .front, style: .flowEdges,
      strokeStyle: portraitTestStyle(), vectorOptions: options)
    #expect(first == second)
    #expect(first.source.sourceIdentifier.contains("|flow=flow-edge-v1"))
    #expect(!first.strokes.isEmpty)
    for stroke in first.strokes {
      #expect(stroke.path.length > 0)
      #expect(stroke.path.points.allSatisfy {
        $0.x.isFinite && $0.y.isFinite && $0.x >= 0 && $0.y >= 0
          && $0.x <= first.fieldExtent.width && $0.y <= first.fieldExtent.height
      })
    }
    // Historical case raw values remain decodable, including hidden algorithms.
    for raw in ["Contour", "Hatch", "Crosshatch", "Sketch", "Sketch + hatch"] {
      #expect(try JSONDecoder().decode(PortraitStyle.self, from: Data("\"\(raw)\"".utf8)).rawValue == raw)
    }
  }

  @Test("Tone and coherence preserve the exact structural curves including small facial marks")
  func independentStructure() throws {
    let raster = flowFace()
    var low = PortraitVectorOptions.flowDefaults
    low.tonalStrength = 0.4; low.smoothing = 0
    var high = low
    high.tonalStrength = 2; high.smoothing = 4
    let a = try PortraitFlowRenderer.layers(from: raster, options: low)
    let b = try PortraitFlowRenderer.layers(from: raster, options: high)
    #expect(!a.structure.isEmpty)
    #expect(a.structure == b.structure)
    // These are real edge marks around the small synthetic eyes and mouth,
    // not merely survival of the large silhouette.
    for center in [CGPoint(x: 34, y: 52), CGPoint(x: 62, y: 52), CGPoint(x: 48, y: 84)] {
      #expect(a.structure.flatMap { $0 }.contains { hypot($0.x - center.x, $0.y - center.y) < 9 })
    }
    #expect(a.tone != b.tone)
  }

  @Test("A detailed smooth boundary is retained within a subpixel evidence tube")
  func smoothDetail() throws {
    let width = 96, height = 144
    func boundary(_ y: Double) -> Double { 48 + 8 * sin(y / 10) }
    let raster = flowRaster(width: width, height: height) { x, y in
      Double(x) < boundary(Double(y)) ? 0.2 : 0.86
    }
    let layers = try PortraitFlowRenderer.layers(from: raster, options: .flowDefaults)
    let longest = try #require(layers.structure.max { flowLength($0) < flowLength($1) })
    #expect(flowLength(longest) > 130)
    #expect(longest.allSatisfy { abs($0.x - boundary($0.y)) < 1.6 })
    #expect((longest.map(\.x).max()! - longest.map(\.x).min()!) > 14)
    var totalBend = 0.0
    for i in 1..<(longest.count - 1) {
      let dx = Double(longest[i - 1].x) - 2 * Double(longest[i].x) + Double(longest[i + 1].x)
      let dy = Double(longest[i - 1].y) - 2 * Double(longest[i].y) + Double(longest[i + 1].y)
      totalBend += hypot(dx, dy)
    }
    let meanBend = totalBend / Double(longest.count - 2)
    #expect(meanBend < 0.25)
  }

  @Test("Broad materials suppress parallel structural duplicates as well as tonal crowding")
  func materialFloor() throws {
    let raster = flowRaster(width: 96, height: 96) { x, _ in (x / 6).isMultiple(of: 2) ? 0.2 : 0.8 }
    var options = PortraitVectorOptions.flowDefaults
    options.minimumContourLength = 4
    let fine = try PortraitFlowRenderer.layers(from: raster, options: options)
    let profile = try DrawingMaterialProfileRevision(name: "Flow test broad pen", nominalWidthMM: 3)
    options.materialContext = try PortraitMaterialContext(profile: profile, drawingHeightMM: 48)
    options.tonalStrength = 2
    options.hatchSpacing = 1
    let broad = try PortraitFlowRenderer.layers(from: raster, options: options)
    #expect(broad.minimumSpacing == 9)
    #expect(broad.structure.count < fine.structure.count)
    #expect(!broad.structure.isEmpty)
    let means = broad.structure.map { $0.reduce(0) { $0 + $1.x } / Double($0.count) }.sorted()
    #expect(zip(means, means.dropFirst()).allSatisfy { $1 - $0 >= broad.minimumSpacing })
  }

  @Test("Tonal flow uses long separated strokes and does not fold into its own clearance")
  func separatedFlow() throws {
    let raster = flowRaster(width: 96, height: 96) { x, y in
      min(0.88, 0.12 + hypot(Double(x - 48), Double(y - 48)) / 100)
    }
    var options = PortraitVectorOptions.flowDefaults
    options.sketchThreshold = 0.08 // isolate the smooth field's tonal behavior
    options.hatchSpacing = 5
    options.materialContext = try .init(profile: .init(name: "Flow test pen", nominalWidthMM: 1.5), drawingHeightMM: 48)
    let result = try PortraitFlowRenderer.layers(from: raster, options: options)
    #expect(!result.tone.isEmpty)
    #expect(result.tone.allSatisfy { flowLength($0) >= 12 })
    #expect(result.tone.contains { flowLength($0) > 40 })
    for (index, path) in result.tone.enumerated() {
      // Sparse checks retain a strict physical-floor assertion without making
      // validation quadratic in every integration sample.
      for point in path.enumerated().filter({ $0.offset.isMultiple(of: 4) }).map(\.element) {
        for other in result.tone.dropFirst(index + 1) {
          #expect(other.allSatisfy { hypot(point.x - $0.x, point.y - $0.y) >= result.minimumSpacing })
        }
      }
      for i in stride(from: 0, to: path.count, by: 5) {
        for j in stride(from: i + 1, to: path.count, by: 5) where Double(j - i) * 0.9 > 30 {
          #expect(hypot(path[i].x - path[j].x, path[i].y - path[j].y) >= result.minimumSpacing)
        }
      }
    }
  }

  @Test("Flow analysis has a separate sampling contract and old raster cache cannot lower it")
  func sampling() async throws {
    #expect(PortraitImageAnalyzer.analysisMaximumDimension(for: .flowEdges) == 320)
    #expect(PortraitImageAnalyzer.analysisMaximumDimension(for: .contours) == 160)
    let old = flowFace()
    #expect(!PortraitImageAnalyzer.cachedRasterIsCompatible(old, with: .flowEdges))
    let request = PortraitRenderRequest(data: try portraitTestImage(), pose: .front, style: .flowEdges,
      options: .init(cropToFace: false, removeBackground: false), cachedRaster: old,
      strokeStyle: try portraitTestStyle(), vectorOptions: .flowDefaults)
    let rendered = try await PortraitImageAnalyzer().render(request)
    #expect(max(rendered.raster.width, rendered.raster.height) == 320)
    #expect(PortraitImageAnalyzer.cachedRasterIsCompatible(rendered.raster, with: .flowEdges))
    #expect(!PortraitImageAnalyzer.cachedRasterIsCompatible(rendered.raster, with: .contours))
  }

  @Test("Already-cancelled work stops before a flow program is produced")
  func cancellation() async throws {
    let task = Task {
      withUnsafeCurrentTask { $0?.cancel() }
      return try PortraitFlowRenderer.layers(from: flowFace(), options: .flowDefaults)
    }
    await #expect(throws: CancellationError.self) { try await task.value }
  }

  @Test("Opt-in local photo reference reports timing and exports a review contact sheet")
  func referencePhoto() async throws {
    let environment = ProcessInfo.processInfo.environment
    guard let input = environment["PORTRAIT_FLOW_REFERENCE_PHOTO"],
      let output = environment["PORTRAIT_FLOW_REFERENCE_OUTPUT"] else { return }
    let data = try Data(contentsOf: URL(fileURLWithPath: input))
    let analyzer = PortraitImageAnalyzer(), clock = ContinuousClock()
    let started = clock.now
    let baseline = try await analyzer.render(.init(data: data, pose: .front, style: .flowEdges,
      options: .init(), cachedRaster: nil, strokeStyle: portraitTestStyle(), vectorOptions: .flowDefaults))
    let cold = started.duration(to: clock.now)
    var variants: [(String, PortraitVectorOptions)] = [("Flow baseline", .flowDefaults)]
    var light = PortraitVectorOptions.flowDefaults; light.tonalStrength = 0.5
    var dense = PortraitVectorOptions.flowDefaults; dense.tonalStrength = 2
    var loose = PortraitVectorOptions.flowDefaults; loose.smoothing = 0
    var coherent = PortraitVectorOptions.flowDefaults; coherent.smoothing = 4
    variants += [("Density 0.5", light), ("Density 2.0", dense), ("Coherence 0", loose), ("Coherence 4", coherent)]
    var programs: [(String, DrawingProgram)] = []
    var timings: [Double] = []
    for (label, options) in variants {
      let begin = clock.now
      let rendered = try await analyzer.render(.init(data: data, pose: .front, style: .flowEdges,
        options: .init(), cachedRaster: baseline.raster, strokeStyle: portraitTestStyle(), vectorOptions: options))
      timings.append(flowMilliseconds(begin.duration(to: clock.now)))
      programs.append((label, rendered.program))
    }
    let destination = URL(fileURLWithPath: output, isDirectory: true)
    try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
    try flowReferenceSheet(photo: PortraitImageAnalyzer.image(from: data), programs: programs)
      .write(to: destination.appendingPathComponent("flow-reference.png"))
    let report: [String: Any] = ["revision": PortraitFlowRenderer.revision,
      "rasterWidth": baseline.raster.width, "rasterHeight": baseline.raster.height,
      "coldAnalysisAndRenderMS": flowMilliseconds(cold), "cachedRenderMS": timings,
      "labels": programs.map(\.0), "strokeCounts": programs.map { $0.1.strokes.count },
      "pointCounts": programs.map { $0.1.strokes.reduce(0) { $0 + $1.path.points.count } },
      "scope": "Local digital reference only; no physical likeness or ink validation"]
    let reportData = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
    try reportData.write(to: destination.appendingPathComponent("flow-reference.json"))
    print("PORTRAIT_FLOW_REFERENCE " + String(decoding: reportData, as: UTF8.self))
  }
}

private func flowRaster(width: Int, height: Int, value: (Int, Int) -> Double) -> PortraitRaster {
  PortraitRaster(width: width, height: height,
    luminance: (0..<height).flatMap { y in (0..<width).map { value($0, y) } },
    provenance: "flow-test", analysisSummary: "Synthetic evidence fixture",
    sourceCropExtent: try! .init(widthPixels: Double(width), heightPixels: Double(height)))
}

private func flowFace() -> PortraitRaster {
  flowRaster(width: 96, height: 128) { x, y in
    let u = Double(x), v = Double(y)
    let radius = pow((u - 48) / 33, 2) + pow((v - 64) / 51, 2)
    guard radius < 1 else { return 1 }
    var value = 0.45 + 0.3 * radius + 0.1 * u / 96
    for (cx, cy, sx, sy) in [(34.0, 52.0, 7.0, 2.5), (62, 52, 7, 2.5), (48, 84, 12, 2.5)] {
      value -= 0.5 * exp(-pow((u - cx) / sx, 2) - pow((v - cy) / sy, 2))
    }
    value -= 0.22 * exp(-pow((u - 51) / 3, 2) - pow((v - 68) / 10, 2))
    return max(0, value)
  }
}

private func flowLength(_ points: [CGPoint]) -> Double {
  zip(points, points.dropFirst()).reduce(0) { $0 + hypot($1.0.x - $1.1.x, $1.0.y - $1.1.y) }
}

private func flowMilliseconds(_ duration: Duration) -> Double {
  Double(duration.components.seconds) * 1000 + Double(duration.components.attoseconds) / 1e15
}

private func flowReferenceSheet(photo: CGImage, programs: [(String, DrawingProgram)]) throws -> Data {
  let tileWidth = 400, tileHeight = 470, padding = 22
  let context = try #require(CGContext(data: nil, width: tileWidth * 3, height: tileHeight * 2,
    bitsPerComponent: 8, bytesPerRow: tileWidth * 12, space: CGColorSpaceCreateDeviceRGB(),
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
  context.setFillColor(CGColor(gray: 1, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: tileWidth * 3, height: tileHeight * 2))
  for index in 0...programs.count {
    let origin = CGPoint(x: (index % 3) * tileWidth, y: (1 - index / 3) * tileHeight)
    let bounds = CGRect(x: origin.x + Double(padding), y: origin.y + Double(padding),
      width: Double(tileWidth - 2 * padding), height: Double(tileHeight - 65))
    let title = index == 0 ? "Source photo" : programs[index - 1].0
    let line = CTLineCreateWithAttributedString(NSAttributedString(string: title,
      attributes: [NSAttributedString.Key(kCTFontAttributeName as String): CTFontCreateWithName("Helvetica" as CFString, 16, nil)]))
    context.textPosition = CGPoint(x: bounds.minX, y: origin.y + Double(tileHeight - 25)); CTLineDraw(line, context)
    if index == 0 {
      let scale = min(bounds.width / Double(photo.width), bounds.height / Double(photo.height))
      context.draw(photo, in: CGRect(x: bounds.midX - Double(photo.width) * scale / 2,
        y: bounds.midY - Double(photo.height) * scale / 2, width: Double(photo.width) * scale, height: Double(photo.height) * scale))
    } else {
      let program = programs[index - 1].1
      let scale = min(bounds.width / program.fieldExtent.width, bounds.height / program.fieldExtent.height)
      let dx = bounds.midX - program.fieldExtent.width * scale / 2, dy = bounds.midY - program.fieldExtent.height * scale / 2
      context.setStrokeColor(CGColor(gray: 0.05, alpha: 1)); context.setLineWidth(0.7)
      context.setLineCap(.round); context.setLineJoin(.round)
      for stroke in program.strokes {
        guard let first = stroke.path.points.first else { continue }
        context.move(to: CGPoint(x: dx + first.x * scale, y: dy + first.y * scale))
        for point in stroke.path.points.dropFirst() { context.addLine(to: CGPoint(x: dx + point.x * scale, y: dy + point.y * scale)) }
        context.strokePath()
      }
    }
  }
  return try PortraitImageAnalyzer.encodedImage(#require(context.makeImage()))
}
