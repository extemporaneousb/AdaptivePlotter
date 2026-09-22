import CoreGraphics
import CoreText
import Foundation
import PlotterModel
import Testing

@testable import PlotterApp

@Suite("Flow support, scale and seed evidence")
struct PortraitFlowSupportTests {
  @Test("Zero support and irregularity preserve legacy geometry and never prepare support")
  func legacyBranch() throws {
    let raster = supportFace()
    var workspace = PortraitFlowRenderer.Workspace()
    let original = try PortraitFlowRenderer.layers(from: raster, options: .flowDefaults, workspace: &workspace)
    var options = PortraitVectorOptions.flowDefaults
    options.flowSupport = 0; options.flowStructureSupport = 0; options.flowSeedIrregularity = 0
    options.flowSupportScale = 1
    let disabled = try PortraitFlowRenderer.layers(from: raster, options: options, workspace: &workspace)
    #expect(original.structure == disabled.structure && original.tone == disabled.tone)
    #expect(workspace.supportLevelCount == 0)
    #expect(workspace.diagnostics.supportBuilds == 0)
    #expect(workspace.diagnostics.supportMS == 0)
    #expect(workspace.diagnostics.structureCacheHit && workspace.diagnostics.orientationCacheHit)
  }

  @Test("Tonal evidence rejects flat and tiny coherent texture instead of inventing fill")
  func quietAreas() throws {
    for noisy in [false, true] {
      let raster = supportRaster { x, _ in noisy ? 0.42 + 0.004 * sin(Double(x) * .pi / 3) : 0.42 }
      var options = PortraitVectorOptions.flowDefaults
      let legacy = try PortraitFlowRenderer.layers(from: raster, options: options)
      try #require(!legacy.tone.isEmpty)
      options.flowSupport = 0.7; options.flowSupportScale = 0.5
      for form in [0.0, 0.5, 1.0] {
        options.flowRectilinearity = form
        let supported = try PortraitFlowRenderer.layers(from: raster, options: options)
        #expect(supported.structure == legacy.structure)
        #expect(supported.tone.isEmpty)
      }
    }
  }

  @Test("Multiscale support retains broad low-gradient form and independent fine facial curves")
  func broadFormAndIndependentStructure() throws {
    let broad = supportRaster { x, y in
      0.18 + hypot(Double(x - 48), Double(y - 48)) / 180
    }
    var options = PortraitVectorOptions.flowDefaults
    options.sketchThreshold = 0.08
    options.flowSupport = 0.7; options.flowSupportScale = 0.5
    let result = try PortraitFlowRenderer.layers(from: broad, options: options)
    #expect(result.structure.isEmpty)
    try #require(!result.tone.isEmpty)
    #expect(result.tone.contains { supportLength($0) > 40 })
    // Turning on structural support must not silently activate tonal gating.
    var ungated = options
    ungated.flowSupport = nil; ungated.flowStructureSupport = 0.8
    let structuralOnly = try PortraitFlowRenderer.layers(from: broad, options: ungated)
    ungated.flowStructureSupport = nil
    let legacy = try PortraitFlowRenderer.layers(from: broad, options: ungated)
    #expect(structuralOnly.structure.isEmpty && structuralOnly.tone == legacy.tone)

    let face = supportFace()
    let baseline = try PortraitFlowRenderer.layers(from: face, options: .flowDefaults)
    options = .flowDefaults
    options.flowSupport = 0.8; options.flowSupportScale = 0.5
    let toneOnly = try PortraitFlowRenderer.layers(from: face, options: options)
    #expect(toneOnly.structure == baseline.structure)
    options.flowStructureSupport = 0.7
    let supported = try PortraitFlowRenderer.layers(from: face, options: options)
    try #require(!supported.structure.isEmpty)
    for center in [CGPoint(x: 34, y: 39), CGPoint(x: 62, y: 39), CGPoint(x: 48, y: 64)] {
      #expect(supported.structure.flatMap { $0 }.contains { hypot($0.x - center.x, $0.y - center.y) < 9 })
    }
  }

  @Test("Structural support removes weak repeated texture while keeping its measured silhouette")
  func structuralTexture() throws {
    let raster = supportRaster { x, _ in
      x < 72 ? 0.42 + 0.065 * sin(Double(x) * .pi / 3) : 0.94
    }
    var options = PortraitVectorOptions.flowDefaults
    let original = try PortraitFlowRenderer.layers(from: raster, options: options)
    options.flowStructureSupport = 0.75; options.flowSupportScale = 0.5
    let supported = try PortraitFlowRenderer.layers(from: raster, options: options)
    #expect(supported.structure.count < original.structure.count)
    let silhouette = try #require(supported.structure.first { path in
      supportLength(path) > 75 && path.allSatisfy { abs($0.x - 71.5) < 2 }
    })
    #expect(original.structure.contains(silhouette))
  }

  @Test("Support preparation is lazy, source-bound and fixed-size across parameter changes")
  func preparationReuse() throws {
    let raster = supportFace()
    var workspace = PortraitFlowRenderer.Workspace()
    var options = PortraitVectorOptions.flowDefaults
    options.flowSupport = 0.65
    _ = try PortraitFlowRenderer.layers(from: raster, options: options, workspace: &workspace)
    #expect(workspace.supportLevelCount == 1)
    #expect(workspace.diagnostics.supportBuilds == 1)
    #expect(workspace.diagnostics.supportLevelBuilds == 1)
    #expect(!workspace.diagnostics.supportCacheHit)
    for index in 0..<4 {
      options.flowSupport = 0.3 + Double(index) * 0.2
      options.flowStructureSupport = Double(index) * 0.2
      options.flowSupportScale = Double(index) / 3
      options.flowSeedIrregularity = Double(index) / 3
      let cached = try PortraitFlowRenderer.layers(from: raster, options: options, workspace: &workspace)
      #expect(workspace.supportLevelCount == [1, 2, 3, 3][index])
      #expect(workspace.diagnostics.supportLevelBuilds == [1, 2, 3, 3][index])
      #expect(workspace.diagnostics.supportBuilds == 1)
      #expect(workspace.diagnostics.supportCacheHit == (index == 0 || index == 3))
      #expect(workspace.diagnostics.rawStructureBuilds == 1)
      if index > 0 { #expect(workspace.diagnostics.rawStructureCacheHit) }
      var coldWorkspace = PortraitFlowRenderer.Workspace()
      let cold = try PortraitFlowRenderer.layers(from: raster, options: options, workspace: &coldWorkspace)
      #expect(coldWorkspace.supportLevelCount == [1, 2, 2, 1][index])
      #expect(cached.structure == cold.structure && cached.tone == cold.tone)
    }
    #expect(workspace.structureVariantCount <= 2 && workspace.orientationVariantCount <= 2)
    for threshold in [0.018, 0.024, 0.032] {
      options.sketchThreshold = threshold
      _ = try PortraitFlowRenderer.layers(from: raster, options: options, workspace: &workspace)
    }
    #expect(workspace.rawStructureVariantCount == 2)
    #expect(workspace.diagnostics.rawStructureBuilds == 4)
    let replacement = supportRaster { _, _ in 0.4 }
    _ = try PortraitFlowRenderer.layers(from: replacement, options: .flowDefaults, workspace: &workspace)
    #expect(workspace.supportLevelCount == 0)
    #expect(workspace.rawStructureVariantCount == 1)
    #expect(!workspace.diagnostics.sourceCacheHit)
    _ = try PortraitFlowRenderer.layers(from: replacement, options: options, workspace: &workspace)
    #expect(workspace.diagnostics.supportBuilds == 2 && workspace.supportLevelCount == 1)
    #expect(workspace.diagnostics.supportLevelBuilds == 4)
  }

  @Test("Seed irregularity is repeatable and cannot relax structural or material separation")
  func irregularityAndSpacing() throws {
    let flat = supportRaster { _, _ in 0.4 }
    var options = PortraitVectorOptions.flowDefaults
    let regular = try PortraitFlowRenderer.layers(from: flat, options: options)
    options.flowSeedIrregularity = 0.8
    var workspace = PortraitFlowRenderer.Workspace()
    let irregular = try PortraitFlowRenderer.layers(from: flat, options: options, workspace: &workspace)
    let repeatResult = try PortraitFlowRenderer.layers(from: flat, options: options)
    #expect(irregular.tone == repeatResult.tone && irregular.tone != regular.tone)
    #expect(irregular.structure == regular.structure && workspace.supportLevelCount == 0)

    let raster = supportRaster { x, y in
      (46...49).contains(x) ? 0.02 : 0.15 + hypot(Double(x - 48), Double(y - 48)) / 130
    }
    options.flowSupport = 0.65; options.flowSupportScale = 0.5
    options.hatchSpacing = 5; options.tonalStrength = 2
    options.materialContext = try .init(profile: .init(name: "Supported flow broad pen", nominalWidthMM: 1.5),
      drawingHeightMM: 48)
    for form in [0.0, 0.5, 1.0] {
      options.flowRectilinearity = form
      let layers = try PortraitFlowRenderer.layers(from: raster, options: options)
      try #require(!layers.structure.isEmpty && !layers.tone.isEmpty)
      if form == 1 { #expect(layers.tone.allSatisfy { $0.count == 2 }) }
      let paths = layers.tone.map(supportResample)
      for (index, path) in paths.enumerated() {
        for point in path.enumerated().filter({ $0.offset.isMultiple(of: 5) }).map(\.element) {
          #expect(point.x.isFinite && point.y.isFinite && point.x >= 0 && point.y >= 0
            && point.x < 96 && point.y < 96)
          for prior in paths.prefix(index) {
            #expect(prior.allSatisfy { hypot($0.x - point.x, $0.y - point.y) >= layers.minimumSpacing })
          }
          #expect(layers.structure.allSatisfy { curve in
            curve.allSatisfy { hypot($0.x - point.x, $0.y - point.y) >= layers.minimumSpacing }
          })
        }
      }
    }
  }

  @Test("Rectilinear support bridges a short weak gap and trims a weak tail")
  func rectilinearSupportGaps() throws {
    let result = try #require(try PortraitRectilinearFlowTracer.trace(seed: .init(x: 25, y: 48),
      tangent: .init(x: 1, y: 0), width: 96, height: 96, minimumLength: 12,
      spacing: { _ in 3 }, luminance: { _ in 0.3 }, intersects: { _, _ in false },
      support: { point in (point.x > 40 && point.x < 42) || point.x > 70 ? 0 : 1 },
      minimumSupport: 0.2, maximumUnsupportedLength: 3))
    #expect(result.endpoints.last!.x > 68 && result.endpoints.last!.x <= 70)
    #expect(result.sampledPath.contains { $0.x > 40 && $0.x < 42 })
    #expect(result.sampledPath.count == result.radii.count)
  }

  @Test("Support handles tiny kernels and cancellation both cold and with cached evidence")
  func boundsAndCancellation() async throws {
    var options = PortraitVectorOptions.flowDefaults
    options.flowSupport = 0.8; options.flowStructureSupport = 0.6; options.flowSupportScale = 1
    options.flowSeedIrregularity = 0.8
    for (width, height) in [(3, 3), (3, 17), (17, 3), (5, 5)] {
      let raster = supportRaster(width: width, height: height) { x, y in Double((x + y) % 3) / 3 }
      let result = try PortraitFlowRenderer.layers(from: raster, options: options)
      #expect((result.structure + result.tone).flatMap { $0 }.allSatisfy { $0.x.isFinite && $0.y.isFinite })
    }
    let raster = supportFace()
    var workspace = PortraitFlowRenderer.Workspace()
    _ = try PortraitFlowRenderer.layers(from: raster, options: options, workspace: &workspace)
    let prepared = workspace, configuration = options
    for warm in [false, true] {
      let task = Task {
        withUnsafeCurrentTask { $0?.cancel() }
        var reused = warm ? prepared : PortraitFlowRenderer.Workspace()
        return try PortraitFlowRenderer.layers(from: raster, options: configuration, workspace: &reused)
      }
      await #expect(throws: CancellationError.self) { try await task.value }
    }
  }

  @Test("Opt-in local photo separates support controls and structural versus tonal layers")
  func referencePhoto() async throws {
    let environment = ProcessInfo.processInfo.environment
    guard let input = environment["PORTRAIT_FLOW_REFERENCE_PHOTO"],
      let output = environment["PORTRAIT_FLOW_REFERENCE_OUTPUT"] else { return }
    let data = try Data(contentsOf: URL(fileURLWithPath: input)), pen = try portraitTestStyle()
    var tone = PortraitVectorOptions.flowDefaults
    tone.flowSupport = 0.65; tone.flowSupportScale = 0.5
    var structure = PortraitVectorOptions.flowDefaults
    structure.flowStructureSupport = 0.55; structure.flowSupportScale = 0.5
    var both = tone; both.flowStructureSupport = 0.55
    var irregular = both; irregular.flowSeedIrregularity = 0.65
    var broad = irregular; broad.flowSupportScale = 1
    let variants: [(String, PortraitVectorOptions)] = [("Legacy", .flowDefaults), ("Tone support 0.65", tone),
      ("Structure support 0.55", structure), ("Both / scale 0.5", both),
      ("Both + irregularity 0.65", irregular), ("Both + irregularity / scale 1", broad)]
    let analyzer = PortraitImageAnalyzer(), clock = ContinuousClock()
    var raster: PortraitRaster?, workspace: PortraitFlowRenderer.Workspace?
    var programs: [(String, DrawingProgram)] = [], reports: [[String: Any]] = []
    for (label, options) in variants {
      let started = clock.now
      let rendered = try await analyzer.render(.init(data: data, pose: .front, style: .flowEdges,
        options: .init(), cachedRaster: raster, strokeStyle: pen, vectorOptions: options, flowWorkspace: workspace))
      let elapsed = started.duration(to: clock.now)
      raster = rendered.raster; workspace = rendered.flowWorkspace
      programs.append((label, rendered.program))
      let diagnostics = try #require(workspace?.diagnostics)
      reports.append(["label": label, "renderMS": supportMS(elapsed), "supportMS": diagnostics.supportMS,
        "supportBuilds": diagnostics.supportBuilds, "supportLevelBuilds": diagnostics.supportLevelBuilds,
        "supportCacheHit": diagnostics.supportCacheHit,
        "sourceCacheHit": diagnostics.sourceCacheHit, "structureCacheHit": diagnostics.structureCacheHit,
        "rawStructureBuilds": diagnostics.rawStructureBuilds, "rawStructureCacheHit": diagnostics.rawStructureCacheHit,
        "rawStructureMS": diagnostics.rawStructureMS, "structureMS": diagnostics.structureMS,
        "orientationMS": diagnostics.orientationMS, "tracingMS": diagnostics.tracingMS,
        "pointCount": rendered.program.strokes.reduce(0) { $0 + $1.path.points.count },
        "strokeCount": rendered.program.strokes.count, "programHash": rendered.program.contentHash.description])
    }
    var prepared = try #require(workspace)
    let source = try #require(raster)
    let layers = try PortraitFlowRenderer.layers(from: source, options: both, workspace: &prepared)
    for (label, selection) in [("Both: structural layer", layers.structure), ("Both: tonal layer", layers.tone)] {
      if !selection.isEmpty {
        let program = try PortraitVectorizer.program(from: source, pose: .front, style: .flowEdges,
          strokeStyle: pen, vectorOptions: both,
          flowLayers: .init(structure: selection, tone: [], minimumSpacing: layers.minimumSpacing))
        programs.append((label, program))
      }
    }
    let directory = URL(fileURLWithPath: output, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try supportReferenceSheet(photo: PortraitImageAnalyzer.image(from: data), programs: programs)
      .write(to: directory.appendingPathComponent("flow-support.png"))
    #if DEBUG
    let configuration = "debug"
    #else
    let configuration = "release"
    #endif
    let report: [String: Any] = ["buildConfiguration": configuration, "variants": reports,
      "supportLevelCount": prepared.supportLevelCount,
      "structureStrokeCount": layers.structure.count, "toneStrokeCount": layers.tone.count,
      "scope": "Local digital evidence; no physical ink or perceptual likeness validation"]
    let encoded = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
    try encoded.write(to: directory.appendingPathComponent("flow-support.json"))
    print("PORTRAIT_FLOW_SUPPORT " + String(decoding: encoded, as: UTF8.self))
  }
}

private func supportRaster(width: Int = 96, height: Int = 96,
  value: (Int, Int) -> Double) -> PortraitRaster {
  PortraitRaster(width: width, height: height,
    luminance: (0..<height).flatMap { y in (0..<width).map { x in value(x, y) } },
    provenance: "support-fixture", analysisSummary: "Synthetic multiscale support evidence")
}

private func supportFace() -> PortraitRaster {
  supportRaster { x, y in
    let u = Double(x), v = Double(y)
    let radius = pow((u - 48) / 33, 2) + pow((v - 48) / 42, 2)
    guard radius < 1 else { return 1 }
    var value = 0.45 + 0.25 * radius
    for (cx, cy, sx, sy) in [(34.0, 39.0, 7.0, 2.5), (62, 39, 7, 2.5), (48, 64, 12, 2.5)] {
      value -= 0.5 * exp(-pow((u - cx) / sx, 2) - pow((v - cy) / sy, 2))
    }
    return max(0, value)
  }
}

private func supportLength(_ path: [CGPoint]) -> Double {
  zip(path, path.dropFirst()).reduce(0) { $0 + hypot($1.1.x - $1.0.x, $1.1.y - $1.0.y) }
}

private func supportResample(_ path: [CGPoint]) -> [CGPoint] {
  guard let first = path.first else { return [] }
  var result = [first]
  for (a, b) in zip(path, path.dropFirst()) {
    let count = max(1, Int(ceil(hypot(b.x - a.x, b.y - a.y) / 0.8)))
    for i in 1...count {
      let t = Double(i) / Double(count)
      result.append(CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t))
    }
  }
  return result
}

private func supportMS(_ duration: Duration) -> Double {
  Double(duration.components.seconds) * 1000 + Double(duration.components.attoseconds) / 1e15
}

private func supportReferenceSheet(photo: CGImage, programs: [(String, DrawingProgram)]) throws -> Data {
  let tileWidth = 400, tileHeight = 470, columns = 3
  let rows = (programs.count + columns) / columns
  let context = try #require(CGContext(data: nil, width: tileWidth * columns, height: tileHeight * rows,
    bitsPerComponent: 8, bytesPerRow: tileWidth * columns * 4, space: CGColorSpaceCreateDeviceRGB(),
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
  context.setFillColor(CGColor(gray: 1, alpha: 1))
  context.fill(CGRect(x: 0, y: 0, width: tileWidth * columns, height: tileHeight * rows))
  for index in 0...programs.count {
    let origin = CGPoint(x: (index % columns) * tileWidth, y: (rows - 1 - index / columns) * tileHeight)
    let bounds = CGRect(x: origin.x + 22, y: origin.y + 22, width: Double(tileWidth - 44), height: Double(tileHeight - 65))
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
