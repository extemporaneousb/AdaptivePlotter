import CoreGraphics
import CoreText
import Foundation
import PlotterModel
import Testing
@testable import PlotterApp

@Suite("Regional prototype recipes")
struct PortraitPrototypeRecipeTests {
  @Test("Absent regional fields preserve legacy bytes, provenance and program identity")
  func legacyIdentity() throws {
    let bytes = Data(#"{"contourLevels":6,"hatchAngleDegrees":0,"hatchSpacing":8,"headScale":1,"minimumContourLength":6,"simplificationTolerance":0.25,"sketchThreshold":0.012,"smoothing":1.5,"tonalStrength":1}"#.utf8)
    let old = try JSONDecoder().decode(PortraitVectorOptions.self, from: bytes)
    #expect(old.regionalTreatment == nil && old.regionalAdjustments == nil && old.eyeExaggeration == nil)
    #expect(try PortraitCandidateCoding.encoder().encode(old) == bytes)
    #expect(old.provenance == PortraitVectorOptions.flowDefaults.provenance)
    let raster = try regionalFixture()
    let a = try PortraitVectorizer.program(from: raster, pose: .front, style: .flowEdges,
      strokeStyle: portraitTestStyle(), vectorOptions: old)
    let b = try PortraitVectorizer.program(from: raster, pose: .front, style: .flowEdges,
      strokeStyle: portraitTestStyle(), vectorOptions: .flowDefaults)
    #expect(a == b)
    #expect(!a.source.sourceIdentifier.contains("|regional="))
    #expect(!a.source.sourceIdentifier.contains("|regionalEvidence="))
  }

  @Test("Three recipes produce contrasting actual geometry and bind regional evidence")
  func contrastingGeometry() throws {
    let raster = try regionalFixture()
    let programs = try PortraitPrototypeRecipe.allCases.map {
      try PortraitVectorizer.program(from: raster, pose: .front, style: $0.style,
        strokeStyle: portraitTestStyle(), vectorOptions: $0.options())
    }
    for (index, program) in programs.enumerated() {
      #expect(!program.strokes.isEmpty)
      #expect(program.source.sourceIdentifier.contains("regionalEvidence="))
      #expect(program.strokes.allSatisfy { $0.path.length > 0 && $0.path.points.allSatisfy { $0.x.isFinite && $0.y.isFinite } })
      #expect(PortraitStrokeBurden(program: program).pointCount < 180_000)
      for other in programs.dropFirst(index + 1) { #expect(program.strokes.map(\.path) != other.strokes.map(\.path)) }
    }
    // Explicit extra shadow centerlines provide a measurable language difference,
    // while exaggeration moves geometry using retained landmark evidence.
    let comic = PortraitPrototypeRecipe.angularComic.options()
    var withoutShadows = comic; withoutShadows.regionalTreatment?.shadowStrength = 0
    withoutShadows.regionalTreatment?.contourEmphasis = 0
    let baseComic = try PortraitVectorizer.program(from: raster, pose: .front, style: .flowEdges,
      strokeStyle: portraitTestStyle(), vectorOptions: withoutShadows)
    #expect(programs[1].strokes.count > baseComic.strokes.count)
    var unwarped = PortraitPrototypeRecipe.landmarkExaggeration.options(); unwarped.eyeExaggeration = nil
    let baseExaggeration = try PortraitVectorizer.program(from: raster, pose: .front, style: .flowEdges,
      strokeStyle: portraitTestStyle(), vectorOptions: unwarped)
    #expect(programs[2].strokes.map(\.path) != baseExaggeration.strokes.map(\.path))
  }

  @Test("Saved prototype recipes and exact candidates retain active overlays")
  func archiveRoundTrip() throws {
    let raster = try regionalFixture()
    var options = PortraitPrototypeRecipe.angularComic.options()
    options.regionalAdjustments = [.init(scope: .eyes, skinSuppression: 0, angularity: 0.8)]
    options.eyeExaggeration = .init(amount: 0.25)
    let recipe = PortraitStyleRecipe(id: "regional-archive", title: "Comic with eyes", seed: 17,
      style: .flowEdges, vectorOptions: options, analysisOptions: .init())
    let program = try PortraitVectorizer.program(from: raster, pose: .front, style: .flowEdges,
      strokeStyle: portraitTestStyle(), vectorOptions: options)
    let candidate = try PortraitCandidate(sourceData: Data("synthetic-regional".utf8), sourcePixelExtent: raster.sourceCropExtent,
      raster: raster, recipe: recipe, program: program, photoID: UUID(), captureSessionID: UUID(), pose: .front)
    let bytes = try PortraitCandidateCoding.encoder().encode(candidate)
    let restored = try JSONDecoder().decode(PortraitCandidate.self, from: bytes)
    try restored.validateIntegrity()
    #expect(restored.recipe == recipe && restored.program == program)
    #expect(try PortraitCandidateCoding.encoder().encode(restored) == bytes)
  }

  @Test("Optional real-photo prototype contact sheet and measured warm times")
  func referencePhoto() async throws {
    let environment = ProcessInfo.processInfo.environment
    guard let input = environment["PORTRAIT_PROTOTYPE_REFERENCE_PHOTO"],
      let output = environment["PORTRAIT_PROTOTYPE_REFERENCE_OUTPUT"] else { return }
    let data = try Data(contentsOf: URL(fileURLWithPath: input))
    let analyzer = PortraitImageAnalyzer(), clock = ContinuousClock()
    var cache: PortraitRaster?, workspace: PortraitFlowRenderer.Workspace?
    var programs: [(String, DrawingProgram)] = [], reports: [[String: Any]] = []
    for prototype in PortraitPrototypeRecipe.allCases {
      let started = clock.now
      let result = try await analyzer.render(.init(data: data, pose: .front, style: prototype.style,
        options: .init(), cachedRaster: cache, strokeStyle: portraitTestStyle(), vectorOptions: prototype.options(),
        flowWorkspace: workspace))
      let elapsed = started.duration(to: clock.now)
      cache = result.raster; workspace = result.flowWorkspace
      let burden = PortraitStrokeBurden(program: result.program)
      var eyeProof: [String: Any] = [:]
      if let parameters = prototype.options().eyeExaggeration {
        let manifest = PortraitEyeTransform(raster: result.raster, parameters: parameters).manifest
        var baselineOptions = prototype.options(); baselineOptions.eyeExaggeration = nil
        let baseline = try await analyzer.render(.init(data: data, pose: .front, style: prototype.style,
          options: .init(), cachedRaster: result.raster, strokeStyle: portraitTestStyle(),
          vectorOptions: baselineOptions, flowWorkspace: result.flowWorkspace))
        let finalPaths = result.program.strokes.map(\.path), basePaths = baseline.program.strokes.map(\.path)
        // Ordinal differences can include shifts after a split; this is not a
        // count of spatially modified curves (exterior isolation is tested separately).
        let changedPositions = zip(finalPaths, basePaths).filter { $0 != $1 }.count + abs(finalPaths.count-basePaths.count)
        eyeProof = ["applied": manifest.applied, "amount": manifest.amount,
          "supportCount": manifest.supports.count, "minimumJacobianDeterminant": manifest.minimumJacobianDeterminant,
          "geometryChanged": finalPaths != basePaths, "changedStrokePositions": changedPositions,
          "baselinePointCount": PortraitStrokeBurden(program: baseline.program).pointCount,
          "warpedPointCount": burden.pointCount]
        if environment["PORTRAIT_PROTOTYPE_REQUIRE_EYE_WARP"] == "1" {
          #expect(manifest.applied)
          #expect(finalPaths != basePaths)
          #expect(result.program.source.sourceIdentifier.contains("|eyeWarp="))
        }
      }
      programs.append((prototype.title, result.program))
      reports.append(["title": prototype.title,
        "elapsedMS": Double(elapsed.components.seconds) * 1_000 + Double(elapsed.components.attoseconds) / 1e15,
        "strokes": burden.strokeCount, "points": burden.pointCount, "pathLengthPerDrawingHeight": burden.pathLengthPerDrawingHeight,
        "eyeWarpProof": eyeProof,
        "regionalSummary": PortraitRegionalTreatment.summary(raster: result.raster, options: prototype.options()) ?? "none",
        "warpSummary": prototype.options().eyeExaggeration.map { PortraitEyeTransform(raster: result.raster, parameters: $0).manifest.summary } ?? result.warpManifest?.summary ?? "none", "hash": result.program.contentHash.description])
    }
    let destination = URL(fileURLWithPath: output, isDirectory: true)
    try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
    try prototypeReferenceSheet(photo: PortraitImageAnalyzer.image(from: data), programs: programs)
      .write(to: destination.appendingPathComponent("prototype-reference.png"))
    #if DEBUG
    let build = "debug"
    #else
    let build = "release"
    #endif
    let report: [String: Any] = ["build": build, "sourceSHA256": PortraitCandidateCoding.digest(data),
      "scope": "Digital geometry only; no aesthetic or physical likeness acceptance", "prototypes": reports]
    try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
      .write(to: destination.appendingPathComponent("prototype-reference.json"))
  }
}

private func prototypeReferenceSheet(photo: CGImage, programs: [(String, DrawingProgram)]) throws -> Data {
  let tileWidth = 440, tileHeight = 480
  let context = try #require(CGContext(data: nil, width: tileWidth * 4, height: tileHeight,
    bitsPerComponent: 8, bytesPerRow: tileWidth * 16, space: CGColorSpaceCreateDeviceRGB(),
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
  context.setFillColor(CGColor(gray: 1, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: tileWidth * 4, height: tileHeight))
  for index in 0...programs.count {
    let bounds = CGRect(x: index * tileWidth + 20, y: 20, width: tileWidth - 40, height: tileHeight - 80)
    let title = index == 0 ? "Retained source photo" : programs[index - 1].0
    let line = CTLineCreateWithAttributedString(NSAttributedString(string: title,
      attributes: [NSAttributedString.Key(kCTFontAttributeName as String): CTFontCreateWithName("Helvetica" as CFString, 17, nil)]))
    context.textPosition = CGPoint(x: bounds.minX, y: Double(tileHeight - 30)); CTLineDraw(line, context)
    if index == 0 {
      let scale = min(bounds.width / Double(photo.width), bounds.height / Double(photo.height))
      context.draw(photo, in: CGRect(x: bounds.midX - Double(photo.width)*scale/2, y: bounds.midY - Double(photo.height)*scale/2,
        width: Double(photo.width)*scale, height: Double(photo.height)*scale))
    } else {
      let program = programs[index - 1].1
      let scale = min(bounds.width / program.fieldExtent.width, bounds.height / program.fieldExtent.height)
      let dx = bounds.midX - program.fieldExtent.width*scale/2, dy = bounds.midY - program.fieldExtent.height*scale/2
      context.setStrokeColor(CGColor(gray: 0.05, alpha: 1)); context.setLineWidth(0.7)
      context.setLineCap(.round); context.setLineJoin(.round)
      for stroke in program.strokes {
        guard let first = stroke.path.points.first else { continue }
        context.move(to: CGPoint(x: dx + first.x*scale, y: dy + first.y*scale))
        for point in stroke.path.points.dropFirst() { context.addLine(to: CGPoint(x: dx + point.x*scale, y: dy + point.y*scale)) }
        context.strokePath()
      }
    }
  }
  return try PortraitImageAnalyzer.encodedImage(#require(context.makeImage()))
}
