import CoreGraphics
import Foundation
import PlotterModel
import PortraitArtists
import PortraitCore
import PortraitLibrary
@testable import PortraitStudioUI
import Testing

@Suite("Flow artist native mark grammar and bounded proposals", .serialized)
struct FlowArtistVariationTests {
  @Test("The cached live producer admits one program and retains preparation after admission failure")
  func liveProducerCache() async throws {
    let data = FlowAuthoringFixture.image(4), renderer = FlowAuthoringRenderer()
    let style = try StrokeStyle(nominalLineWidth: 0.4, penProfileID: PenProfileID())
    await #expect(throws: (any Error).self) {
      try await renderer.produce(data: data, recipe: .standard, strokeStyle: style, nominalPenWidthMM: -1)
    }
    let produced = try await renderer.produce(data: data, recipe: .standard,
      strokeStyle: style, nominalPenWidthMM: 0.6)
    #expect(produced.drawing.program == produced.artifacts.program)
    #expect(produced.drawing.programDigest == produced.artifacts.program.contentHash)
    #expect(produced.drawing.units.nominalPenWidthMM == 0.6)
    #expect(produced.drawing.capabilities.producerVerified)
    #expect(produced.artifacts.timings?.sourceCacheHit == true)
    #expect(produced.artifacts.preparedSource != nil)
    if case .unavailable = produced.drawing.input { } else { Issue.record("Transient input must remain explicitly unavailable") }
    let claim = try #require(JSONSerialization.jsonObject(with: produced.drawing.producer.originalJSON) as? [String: Any])
    #expect(claim["origin"] as? String == "rendered")

    let input = PortraitFlowDrawingProducer.Input(data: data)
    let settings = PortraitFlowDrawingProducer.Settings(recipe: .standard,
      analysisOptions: FlowAuthoringRenderer.analysisOptions, strokeStyle: style, nominalPenWidthMM: 0.6)
    let fullyValidatedClaim = try PortraitFlowProducerClaim(result: produced.artifacts,
      input: input, settings: settings, origin: "rendered")
    #expect(try PortraitCandidateCoding.encoder().encode(fullyValidatedClaim) == produced.drawing.producer.originalJSON)
    let validator = try PortraitFlowDrawingProducer.validator(result: produced.artifacts,
      input: input, settings: settings, expectedOrigin: .rendered)
    let key = DrawingProducerKey(id: PortraitFlowProducerClaim.producerID, version: PortraitFlowProducerClaim.version)
    let validators = DrawingProducerValidators([key: validator])
    let frozen = try DrawingExchangeCodec.freeze(produced.drawing, identity: .init(issuer: UUID()), createdAt: Date())
    let objects = [ExchangeDigest.hash(frozen.originalProgramJSON): frozen.originalProgramJSON,
      produced.drawing.producer.record: produced.drawing.producer.originalJSON]
    guard case .materialized(let reloaded) = try DrawingExchangeCodec.decode(frozen.originalJSON,
      objects: objects, expected: frozen.reference, validators: validators) else {
      Issue.record("Native rendered drawing unexpectedly opaque"); return
    }
    #expect(reloaded.drawing.capabilities.producerVerified)
    #expect(reloaded.drawing.program == produced.drawing.program)
    #expect(DrawingExchangeCodec.encode(reloaded) == frozen.originalJSON)
    #expect(reloaded.drawing.producer.originalJSON == produced.drawing.producer.originalJSON)
    let envelope = try #require(JSONSerialization.jsonObject(with: frozen.originalJSON) as? [String: Any])
    for field in ["sourceWidth", "rasterSHA256", "recipeRevision", "origin"] {
      var changedClaim = claim
      switch field {
      case "sourceWidth": changedClaim[field] = 999
      case "rasterSHA256": changedClaim[field] = String(repeating: "0", count: 64)
      case "recipeRevision": changedClaim[field] = "forged-recipe"
      default: changedClaim[field] = "reusedArtifacts"
      }
      let changedBytes = try JSONSerialization.data(withJSONObject: changedClaim, options: [.sortedKeys])
      let changedDigest = ExchangeDigest.hash(changedBytes)
      var changedEnvelope = envelope
      var producer = try #require(changedEnvelope["producer"] as? [String: Any])
      producer["record"] = changedDigest.description
      changedEnvelope["producer"] = producer
      let changedRecord = try JSONSerialization.data(withJSONObject: changedEnvelope, options: [.sortedKeys])
      var changedObjects = objects; changedObjects[changedDigest] = changedBytes
      // Outer record and producer digest are coherent; rejection must be semantic.
      do {
        _ = try DrawingExchangeCodec.decode(changedRecord, objects: changedObjects, validators: validators)
        Issue.record("Admitted tampered native claim: \(field)")
      } catch {
        #expect(error as? DrawingExchangeError == .invalidProducer(PortraitFlowProducerClaim.producerID))
      }
    }
    for field in ["input", "parent", "units"] {
      var changedEnvelope = envelope
      if field == "units" {
        var representation = try #require(changedEnvelope["representation"] as? [String: Any])
        representation["nominalPenWidthMillimeters"] = 0.8
        changedEnvelope["representation"] = representation
      } else if field == "input" {
        changedEnvelope[field] = ["state": "none"]
      } else {
        changedEnvelope[field] = ["state": "unavailable", "reason": "Forged parent"]
      }
      let changedRecord = try JSONSerialization.data(withJSONObject: changedEnvelope, options: [.sortedKeys])
      do {
        _ = try DrawingExchangeCodec.decode(changedRecord, objects: objects, validators: validators)
        Issue.record("Admitted mismatched native authored context: \(field)")
      } catch {
        #expect(error as? DrawingExchangeError == .invalidProducer(PortraitFlowProducerClaim.producerID))
      }
    }
  }

  @Test("Caller-supplied raster evidence cannot inherit a local-render validation proof")
  func suppliedRasterAlwaysValidates() async throws {
    let data = FlowAuthoringFixture.image(4)
    let style = try StrokeStyle(nominalLineWidth: 0.4, penProfileID: PenProfileID())
    let input = PortraitFlowDrawingProducer.Input(data: data)
    let settings = PortraitFlowDrawingProducer.Settings(recipe: .standard,
      analysisOptions: FlowAuthoringRenderer.analysisOptions, strokeStyle: style, nominalPenWidthMM: 0.4)
    let produced = try await PortraitFlowDrawingProducer().produce(input: input, settings: settings)
    let base = produced.artifacts.raster, width = base.width, height = base.height
    let geometry = try #require(base.analysisGeometry)
    let mask = PortraitPersonMask(status: .applied, requestRevision: 1, platformVersion: "test",
      width: width, height: height, sourceMaskWidth: width, sourceMaskHeight: height,
      sourceMaskCrop: .init(x: 0, y: 0, width: Double(width), height: Double(height)),
      alpha: Array(repeating: 1, count: width * height))
    func raster(luminance: [Double]? = nil, personMask: PortraitPersonMask? = nil,
      analysisGeometry: PortraitAnalysisGeometry? = nil) -> PortraitRaster {
      PortraitRaster(width: width, height: height, luminance: luminance ?? base.luminance,
        provenance: base.provenance, analysisSummary: base.analysisSummary,
        faceBounds: base.faceBounds, sourceCropExtent: base.sourceCropExtent,
        analysisGeometry: analysisGeometry ?? geometry, personMask: personMask ?? mask, faceAnalysis: base.faceAnalysis)
    }
    let healthy = PortraitRenderResult(raster: raster(), program: produced.drawing.program)
    for origin in [PortraitFlowDrawingProducer.Origin.providedArtifacts, .reusedArtifacts] {
      #expect(try PortraitFlowDrawingProducer.admit(result: healthy, input: input,
        settings: settings, origin: origin).drawing.capabilities.producerVerified)
    }
    _ = try PortraitFlowDrawingProducer.validator(result: healthy, input: input, settings: settings, expectedOrigin: .rendered)
    _ = try PortraitFlowProducerClaim(result: healthy, input: input, settings: settings, origin: "rendered")
    var nanLuminance = base.luminance; nanLuminance[0] = .nan
    var nanMask = mask; nanMask.alpha?[0] = .nan
    var outOfRangeMask = mask; outOfRangeMask.alpha?[0] = Double(1).nextUp
    var shortMask = mask; shortMask.alpha?.removeLast()
    let impossibleStatus = PortraitPersonMask(status: .notRequested, platformVersion: "test",
      width: width, height: height, sourceMaskWidth: width, sourceMaskHeight: height,
      sourceMaskCrop: mask.sourceMaskCrop, alpha: mask.alpha)
    let badGeometry = PortraitAnalysisGeometry(sourcePixelExtent: geometry.sourcePixelExtent,
      decodedWidth: geometry.decodedWidth, decodedHeight: geometry.decodedHeight, crop: geometry.crop,
      rasterWidth: width + 1, rasterHeight: height, contrastLow: geometry.contrastLow,
      contrastHigh: geometry.contrastHigh, contrastApplied: geometry.contrastApplied)
    let invalidRasters = [raster(luminance: nanLuminance), raster(luminance: Array(base.luminance.dropLast())),
      raster(personMask: nanMask), raster(personMask: outOfRangeMask), raster(personMask: shortMask),
      raster(personMask: impossibleStatus), raster(analysisGeometry: badGeometry)]
    for invalidRaster in invalidRasters {
      let result = PortraitRenderResult(raster: invalidRaster, program: produced.drawing.program)
      for origin in [PortraitFlowDrawingProducer.Origin.providedArtifacts, .reusedArtifacts] {
        #expect(throws: PortraitDrawingError.self) {
          try PortraitFlowDrawingProducer.admit(result: result, input: input, settings: settings, origin: origin)
        }
      }
      #expect(throws: PortraitDrawingError.self) {
        try PortraitFlowDrawingProducer.validator(result: result, input: input, settings: settings, expectedOrigin: .rendered)
      }
      #expect(throws: PortraitDrawingError.self) {
        try PortraitFlowProducerClaim(result: result, input: input, settings: settings, origin: "rendered")
      }
    }
  }

  @Test("Absent and zero mark coordinates preserve legacy recipe bytes and exact geometry")
  func zeroIdentity() throws {
    let encoder = DrawingArtifactCoding.encoder(), original = FlowArtistRecipe.standard
    let bytes = try encoder.encode(original)
    let decoded = try JSONDecoder().decode(FlowArtistRecipe.self, from: bytes)
    let zero = FlowArtistRecipe(values: original.values, marks: .init())
    #expect(try encoder.encode(zero) == bytes)
    #expect(decoded == original && zero == original)
    let object = try #require(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
    #expect(object["marks"] == nil)
    #expect((object["values"] as? [Double])?.count == 12)
    let raster = field(), style = try StrokeStyle(nominalLineWidth: 0.4, penProfileID: PenProfileID())
    var options = original.vectorOptions
    let before = try PortraitVectorizer.program(from: raster, pose: .front, style: .flowEdges,
      strokeStyle: style, vectorOptions: options)
    options.flowMarks = .init()
    let after = try PortraitVectorizer.program(from: raster, pose: .front, style: .flowEdges,
      strokeStyle: style, vectorOptions: options)
    #expect(before == after)
    #expect(before.source.sourceIdentifier.contains("|flow=flow-edge-v1"))
  }

  @Test("New forms alter tonal geometry while retaining exact structural curves and image bounds")
  func marks() throws {
    let raster = field()
    var base = matchedBase.vectorOptions
    base.flowSupport = nil; base.flowStructureSupport = nil
    let original = try PortraitFlowRenderer.layers(from: raster, options: base)
    #expect(!original.structure.isEmpty && !original.tone.isEmpty)
    for marks in forms.dropFirst().map(\.1) {
      var options = base; options.flowMarks = marks
      let result = try PortraitFlowRenderer.layers(from: raster, options: options)
      let repeated = try PortraitFlowRenderer.layers(from: raster, options: options)
      #expect(result.structure == original.structure)
      #expect(result.tone == repeated.tone)
      #expect(!result.tone.isEmpty && result.tone != original.tone)
      #expect(result.tone.reduce(0) { $0 + $1.count } < 100_000)
      for path in result.tone {
        #expect(path.count >= 2 && length(path) >= 12)
        #expect(path.allSatisfy { $0.x.isFinite && $0.y.isFinite
          && $0.x >= 1 && $0.y >= 1 && $0.x < Double(raster.width - 2) && $0.y < Double(raster.height - 2) })
      }
      if marks?.loop == 1 { #expect(result.tone.contains { $0.first == $0.last }) }
    }
  }

  @Test("Closed marks reject interior chord barriers, white regions, unsupported samples and cancellation")
  func closedBounds() async throws {
    func trace(blocked: Bool = false, light: Double = 0.2, confidence: Double = 1, sides: Int? = nil,
      clearance: Double = 0)
      throws -> PortraitFlowMarkTracer.Result? {
      try PortraitFlowMarkTracer.closed(seed: .init(x: 30, y: 30), radius: 5,
        polygonSides: sides, phase: 0, minimumLength: 12, width: 64, height: 64,
        spacing: { _ in 2 }, luminance: { _ in light },
        intersects: { p, _ in blocked && p.y > 32 }, support: { _ in confidence }, minimumSupport: 0.3,
        minimumClearance: clearance)
    }
    let circle = try #require(try trace()), polygon = try #require(try trace(sides: 4))
    #expect(circle.path.first == circle.path.last && polygon.path.count == 5)
    #expect(circle.samples.count >= circle.path.count - 1)
    #expect(polygon.samples.count > polygon.path.count)
    #expect(try trace(blocked: true) == nil)
    #expect(try trace(light: 1) == nil)
    #expect(try trace(confidence: 0) == nil)
    #expect(try trace(clearance: 10) == nil)
    #expect(try trace(sides: 3, clearance: 5) == nil)
    #expect(try trace(clearance: 3) != nil)
    let task = Task {
      withUnsafeCurrentTask { $0?.cancel() }
      return try PortraitFlowMarkTracer.closed(seed: .init(x: 30, y: 30), radius: 5,
        polygonSides: nil, phase: 0, minimumLength: 12, width: 64, height: 64,
        spacing: { _ in 2 }, luminance: { _ in 0.2 }, intersects: { _, _ in false },
        support: nil, minimumSupport: 0)
    }
    await #expect(throws: CancellationError.self) { try await task.value }
  }

  @Test("Small broad panels cover distinct mechanisms, source context changes proposals, refinement keeps its anchor")
  func proposals() throws {
    for count in [3, 4, 6, 8] {
      for seed in UInt64(1)...32 {
        let panel = FlowArtistRecipe.broad(count: count, seed: seed)
        #expect(panel.count == count && Set(panel).count == count)
        #expect(panel == FlowArtistRecipe.broad(count: count, seed: seed))
        #expect(Set(panel.map(\.themeTitle)).count >= min(count, 6))
        #expect(panel.contains { ($0.marks?.loop ?? 0) < 0.2 })
      }
    }
    #expect(Set(FlowArtistRecipe.broad(count: 8, seed: 1)) != Set(FlowArtistRecipe.broad(count: 8, seed: 2)))
    let dark = field(light: 0.2), bright = field(light: 0.8)
    let a = try FlowArtistProposals.propose(count: 8, seed: 19, parent: nil, raster: dark, checkpoint: nil)
    let b = try FlowArtistProposals.propose(count: 8, seed: 19, parent: nil, raster: bright, checkpoint: nil)
    #expect(a != b)
    #expect(a.map(\.themeTitle) == b.map(\.themeTitle))
    let parent = a[3]
    let local = try FlowArtistProposals.propose(count: 8, seed: 33, parent: parent, raster: dark, checkpoint: nil)
    #expect(local.count == 8 && local.first == parent)
    #expect(local.allSatisfy { candidate in
      zip(candidate.coordinates, parent.coordinates).allSatisfy { abs($0 - $1) <= 0.120000001 }
    })
  }

  @Test("Historical checkpoints preserve identity and archival validation while refusing current inference")
  func checkpointCompatibility() throws {
    let examples = (0..<3).map { index -> FlowArtistExample in
      var features = Array(repeating: 0.0, count: FlowArtistFeatures.drawingCount)
      features[0] = 1; features[1] = Double(index)
      return .init(id: "legacy-\(index)", sourceGroupID: "photo", recipe: .standard,
        features: features, strokeFeatures: [])
    }
    let fit = FlowArtistTraining.fit(examples: examples, rankings: [.init(id: "rank", tiers: [["legacy-2"], ["legacy-1"], ["legacy-0"]])])
    let current = try #require(fit.checkpoint)
    var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(current)) as? [String: Any])
    json["featureRevision"] = FlowArtistFeatures.legacyRevision
    json["recipeRevision"] = FlowArtistRecipe.legacyRevision
    json["rendererRevision"] = PortraitFlowRenderer.legacyRevision
    var ranker = try #require(json["ranker"] as? [String: Any])
    ranker["weights"] = Array((ranker["weights"] as! [Double]).prefix(123)); json["ranker"] = ranker
    let old = try JSONDecoder().decode(FlowArtistCheckpoint.self, from: JSONSerialization.data(withJSONObject: json))
    try old.validateArchive()
    let identity = old.id
    let restored = try JSONDecoder().decode(FlowArtistCheckpoint.self, from: JSONEncoder().encode(old))
    #expect(restored.id == identity)
    #expect(throws: (any Error).self) { try old.validateForInference() }
    try current.validateForInference()
    #expect(FlowArtistFeatures.proposal(recipe: .standard, raster: field()).count == FlowArtistFeatures.drawingCount)
  }

  @Test("Retain matched real-photo mark forms and equal-budget old/new panels without artistic labels",
    .enabled(if: ProcessInfo.processInfo.environment["FLOW_VARIATION_SOURCES"] != nil))
  func realPhotoVariation() async throws {
    let environment = ProcessInfo.processInfo.environment
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("flow-variation-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let input = URL(fileURLWithPath: try #require(environment["FLOW_VARIATION_SOURCES"]))
    let sources = try JSONDecoder().decode([String].self, from: Data(contentsOf: input))
    #expect((1...3).contains(sources.count))
    guard !FileManager.default.fileExists(atPath: root.path), (1...3).contains(sources.count) else {
      throw FlowArtistModelError.invalid("Variation evidence requires one to three declared sources and a new output directory.")
    }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    var rows: [VariationRow] = [], panels: [PanelRow] = []
    let style = try StrokeStyle(nominalLineWidth: 0.4, penProfileID: PenProfileID())
    for (sourceIndex, path) in sources.enumerated() {
      let data = try Data(contentsOf: URL(fileURLWithPath: path))
      let hash = DrawingArtifactCoding.sha256(data), renderer = FlowAuthoringRenderer()
      for (name, marks) in forms {
        let recipe = FlowArtistRecipe(values: matchedBase.values, marks: marks)
        let start = Date()
        let result = try await renderer.render(data: data, recipe: recipe, strokeStyle: style)
        let preview = try FlowAuthoringRenderer.preview(result.program)
        let filename = "source-\(sourceIndex)-\(name).png"
        try preview.write(to: root.appendingPathComponent(filename), options: .atomic)
        let metrics = VariationMetrics(result.program)
        rows.append(.init(sourceSHA256: hash, form: name, recipe: recipe, metrics: metrics,
          seconds: Date().timeIntervalSince(start), preview: filename))
        #expect(metrics.finiteAndBounded && metrics.strokeCount > 0)
      }
      if sourceIndex == 0 {
        for policy in ["legacy", "themes"] {
          let start = Date()
          let recipes = policy == "legacy" ? legacyBroad(count: 8, seed: 731)
            : try await renderer.proposals(data: data, count: 8, seed: 731, parent: nil, checkpoint: nil)
          var previews = Set<String>(), occupied: [Set<Int>] = [], titles: [String] = []
          for (index, recipe) in recipes.enumerated() {
            let result = try await renderer.render(data: data, recipe: recipe, strokeStyle: style)
            let preview = try FlowAuthoringRenderer.preview(result.program)
            try preview.write(to: root.appendingPathComponent("\(policy)-panel-\(index).png"), options: .atomic)
            previews.insert(DrawingArtifactCoding.sha256(preview)); occupied.append(occupancy(result.program))
            titles.append(recipe.themeTitle)
          }
          var distances: [Double] = []
          for a in occupied.indices { for b in occupied.indices where b > a {
            let union = occupied[a].union(occupied[b]).count
            distances.append(union == 0 ? 0 : 1 - Double(occupied[a].intersection(occupied[b]).count) / Double(union))
          } }
          panels.append(.init(policy: policy, requested: 8, rendered: recipes.count, uniquePreviews: previews.count,
            themeTitles: titles, minimumOccupancyDistance: distances.min() ?? 0,
            meanOccupancyDistance: distances.reduce(0, +) / Double(max(1, distances.count)),
            seconds: Date().timeIntervalSince(start)))
          #expect(recipes.count == 8)
        }
      }
    }
    let receipt = VariationReceipt(scope: "validationFixture: renderer/coverage experiment, no human artistic ratings or identity independence claim",
      rendererRevision: PortraitFlowRenderer.markRevision, proposalRevision: FlowArtistProposals.revision,
      forms: rows, panels: panels)
    try DrawingArtifactCoding.encoder().encode(receipt).write(to: root.appendingPathComponent("variation-receipt.json"), options: .atomic)
    #expect(rows.filter { $0.form == "looped" }.allSatisfy { $0.metrics.closedStrokeCount > 0 })
    #expect(rows.filter { $0.form == "polygon-loops" }.contains { $0.metrics.closedStrokeCount > 0 })
  }



  private var matchedBase: FlowArtistRecipe {
    .init(nativeValues: [5, 3, 0.18, 1.2, 1.5, 0.015, 0, 0.15, 0.2, 0.4, 0.25, 0])
  }
  private var forms: [(String, FlowArtistMarks?)] {
    [("fluid", nil), ("wavy", .init(wave: 1, scale: 0.45)),
     ("angular", .init(polygon: 1, scale: 0.8)), ("looped", .init(loop: 1, scale: 0.8)),
     ("polygon-loops", .init(polygon: 0.85, loop: 1, scale: 0.8)),
     ("blend", .init(wave: 0.6, polygon: 0.6, loop: 0.6, scale: 0.55))]
  }
  private func field(light: Double = 0.25) -> PortraitRaster {
    let width = 96, height = 96
    let values = (0..<(width * height)).map { index in
      let x = index % width, y = index / width
      return x < 5 || y < 5 || x > 90 || y > 90 ? 1.0 : x < 40 ? light : min(0.9, light + 0.15)
    }
    return .init(width: width, height: height, luminance: values,
      provenance: "native-mark-fixture-\(light)", analysisSummary: "Synthetic bounds fixture")
  }
  private func length(_ points: [CGPoint]) -> Double {
    zip(points, points.dropFirst()).reduce(0) { $0 + hypot($1.1.x - $1.0.x, $1.1.y - $1.0.y) }
  }
  private func occupancy(_ program: DrawingProgram) -> Set<Int> {
    var result = Set<Int>()
    for stroke in program.strokes {
      for (a, b) in zip(stroke.path.points, stroke.path.points.dropFirst()) {
        let ax = a.x / program.fieldExtent.width * 63, ay = a.y / program.fieldExtent.height * 63
        let bx = b.x / program.fieldExtent.width * 63, by = b.y / program.fieldExtent.height * 63
        let steps = max(1, Int(ceil(hypot(bx - ax, by - ay) * 2)))
        for i in 0...steps {
          let t = Double(i) / Double(steps)
          let x = min(63, max(0, Int((ax + (bx - ax) * t).rounded())))
          let y = min(63, max(0, Int((ay + (by - ay) * t).rounded())))
          result.insert(y * 64 + x)
        }
      }
    }
    return result
  }
  /// Frozen v1 proposal baseline, used only by this comparison experiment.
  private func legacyBroad(count: Int, seed: UInt64) -> [FlowArtistRecipe] {
    var random = FlowArtistRandom(seed: seed), pool: [FlowArtistRecipe] = []
    for index in 0..<max(64, count * 16) {
      var values = FlowArtistRecipe.names.map { _ in random.unit() }
      if index < 6 {
        values = FlowArtistRecipe.standard.values; values[6] = Double(index % 3) / 2
        values[11] = index < 3 ? 0 : 1; values[3] = index.isMultiple(of: 2) ? 0.12 : 0.7
        values[2] = index < 3 ? 0.12 : 0.85; values[4] = index < 3 ? 0.8 : 0.05
      }
      pool.append(.init(values: values))
    }
    var selected: [FlowArtistRecipe] = [.standard]
    func distance(_ recipe: FlowArtistRecipe) -> Double {
      selected.map { other in zip(recipe.values, other.values).enumerated().reduce(0) {
        $0 + pow($1.element.0 - $1.element.1, 2) * ([2, 3, 4, 6, 11].contains($1.offset) ? 2 : 1)
      } }.min() ?? 0
    }
    while selected.count < count {
      let index = pool.indices.max { distance(pool[$0]) < distance(pool[$1]) }!
      selected.append(pool.remove(at: index))
    }
    return selected
  }
}

private struct VariationMetrics: Codable {
  let strokeCount: Int
  let pointCount: Int
  let closedStrokeCount: Int
  let polygonLoopCount: Int
  let totalLength: Double
  let meanStraightness: Double
  let turningPerLength: Double
  let finiteAndBounded: Bool
  init(_ program: DrawingProgram) {
    strokeCount = program.strokes.count
    pointCount = program.strokes.reduce(0) { $0 + $1.path.points.count }
    closedStrokeCount = program.strokes.filter { $0.path.points.first == $0.path.points.last }.count
    polygonLoopCount = program.strokes.filter { $0.path.points.first == $0.path.points.last && $0.path.points.count <= 9 }.count
    totalLength = program.strokes.reduce(0) { $0 + $1.path.length }
    var straight = 0.0, turns = 0.0
    for stroke in program.strokes {
      let p = stroke.path.points
      if let first = p.first, let last = p.last {
        straight += hypot(last.x - first.x, last.y - first.y) / max(0.0001, stroke.path.length)
      }
      if p.count > 2 { for i in 1..<(p.count - 1) {
        let ux = p[i].x - p[i - 1].x, uy = p[i].y - p[i - 1].y
        let vx = p[i + 1].x - p[i].x, vy = p[i + 1].y - p[i].y
        let norm = hypot(ux, uy) * hypot(vx, vy)
        if norm > 1e-12 { turns += acos(min(1, max(-1, (ux * vx + uy * vy) / norm))) }
      } }
    }
    meanStraightness = straight / Double(max(1, strokeCount))
    turningPerLength = turns / max(0.0001, totalLength)
    finiteAndBounded = program.strokes.allSatisfy { $0.path.points.allSatisfy {
      $0.x.isFinite && $0.y.isFinite && $0.x >= 0 && $0.y >= 0
        && $0.x <= program.fieldExtent.width && $0.y <= program.fieldExtent.height
    } }
  }
}
private struct VariationRow: Codable {
  let sourceSHA256: String; let form: String; let recipe: FlowArtistRecipe
  let metrics: VariationMetrics; let seconds: Double; let preview: String
}
private struct PanelRow: Codable {
  let policy: String; let requested: Int; let rendered: Int; let uniquePreviews: Int
  let themeTitles: [String]; let minimumOccupancyDistance: Double
  let meanOccupancyDistance: Double; let seconds: Double
}
private struct VariationReceipt: Codable {
  let scope: String; let rendererRevision: String; let proposalRevision: String
  let forms: [VariationRow]; let panels: [PanelRow]
}
