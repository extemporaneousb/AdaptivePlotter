import Foundation
import PlotterModel
import Testing

@testable import PlotterApp

@Suite("Portrait exploration proposals")
struct PortraitExplorationProposalTests {
  @Test("single seeded proposal preserves source, renderer and material", arguments: PortraitStyle.allCases)
  func deterministic(style: PortraitStyle) throws {
    let center = try fixture(style: style)
    for seed in UInt64(0)..<32 {
      let recipe = PortraitExplorationPolicy.recipe(around: center, seed: seed)
      #expect(recipe == PortraitExplorationPolicy.recipe(around: center, seed: seed))
      #expect(recipe.style == style)
      #expect(recipe.analysisOptions == center.recipe.analysisOptions)
      #expect(recipe.vectorOptions == recipe.vectorOptions.bounded)
      #expect(recipe.vectorOptions.materialContext == center.recipe.vectorOptions.materialContext)
      #expect(PortraitExplorationPolicy.effectiveOptions(recipe.vectorOptions, center: center)
        != PortraitExplorationPolicy.effectiveOptions(center.recipe.vectorOptions, center: center))
    }
  }

  @Test("material floors and disabled evidence scale do not consume ineffective probes")
  func materialFloors() throws {
    var vectors = PortraitVectorOptions.flowDefaults
    vectors.flowSupportScale = 0.2
    vectors.materialContext = try PortraitMaterialContext(
      profile: .init(name: "Broad fixture", nominalWidthMM: 5), drawingHeightMM: 2)
    let center = try fixture(style: .flowEdges, vectors: vectors)
    for seed in UInt64(0)..<32 {
      let recipe = PortraitExplorationPolicy.recipe(around: center, seed: seed)
      #expect(recipe.vectorOptions.materialContext == vectors.materialContext)
      #expect(recipe.vectorOptions.hatchSpacing == vectors.hatchSpacing)
      #expect(recipe.vectorOptions.minimumContourLength == vectors.minimumContourLength)
      #expect(recipe.vectorOptions.flowSupportScale == 0.2)
      let effective = PortraitExplorationPolicy.effectiveOptions(recipe.vectorOptions, center: center)
      #expect(effective != PortraitExplorationPolicy.effectiveOptions(vectors, center: center))
      let recovery = PortraitExplorationPolicy.recoveryRecipe(around: center, failed: recipe,
        rejection: .noLines, neighbor: Int(seed % 2), seed: seed, variation: 0.35, excluding: [effective])
      #expect(recovery.vectorOptions.materialContext == vectors.materialContext)
      #expect(PortraitExplorationPolicy.effectiveOptions(recovery.vectorOptions, center: center) != effective)
    }
  }

  @Test("subpixel path changes fail the visual floor while displaced structure passes")
  func visibleDifference() throws {
    let center = try fixture()
    func shifted(_ fraction: Double) throws -> DrawingProgram {
      let program = center.program
      return try DrawingProgram(id: ProgramID(UUID()), fieldExtent: program.fieldExtent,
        strokes: program.strokes.enumerated().map { index, stroke in
          LogicalStroke(id: StrokeID(UUID()), path: try Polyline(points: stroke.path.points.map {
            try .init(x: $0.x * 0.8 + program.fieldExtent.width * fraction, y: $0.y * 0.8)
          }), style: stroke.style, ordering: UInt32(index))
        }, source: .init(kind: "fixture", sourceIdentifier: "visual-\(fraction)"))
    }
    let original = PortraitExplorationPolicy.VisibleGeometry(try shifted(0))
    let negligible = PortraitExplorationPolicy.VisibleGeometry(try shifted(0.00001))
    let visible = PortraitExplorationPolicy.VisibleGeometry(try shifted(0.08))
    #expect(!original.isMeaningfullyDifferent(from: negligible))
    #expect(original.isMeaningfullyDifferent(from: visible))
  }

  @Test("v1 nine-slot and v2/v3 three-slot receipts decode while unknown revisions fail")
  func legacyReceiptCompatibility() async throws {
    let center = try fixture()
    let record = PortraitExplorationRecord(traceSessionID: UUID(), sequence: 0,
      roundID: UUID(), policyRevision: "portrait-preference-v4", seed: 7, variation: 0.35,
      centerID: center.id, sourceSHA256: center.sourceSHA256,
      offers: (0..<3).map { index in
        .init(index: index, candidateID: index == 1 ? center.id : nil,
          recipe: index == 1 ? center.recipe : nil,
          programContentHash: index == 1 ? center.program.contentHash.description : nil,
          unavailableReason: index == 1 ? nil : "No option")
      }, action: .selected(index: 1))
    var object = try #require(JSONSerialization.jsonObject(with: PortraitCandidateCoding.encoder().encode(record)) as? [String: Any])
    for revision in ["portrait-preference-v2", "portrait-preference-v3", "portrait-preference-v4"] {
      object["policyRevision"] = revision
      let retained = try JSONDecoder().decode(PortraitExplorationRecord.self,
        from: JSONSerialization.data(withJSONObject: object))
      try PortraitExplorationRecord.validate([retained], for: center)
    }
    let offers = try #require(object["offers"] as? [[String: Any]])
    object["policyRevision"] = "portrait-neighborhood-v1"
    object["offers"] = (0..<9).map { index -> [String: Any] in
      var offer = offers[index == 4 ? 1 : 0]
      offer["index"] = index
      return offer
    }
    object["action"] = ["selected": ["index": 4]]
    let legacy = try JSONDecoder().decode(PortraitExplorationRecord.self,
      from: JSONSerialization.data(withJSONObject: object))
    try PortraitExplorationRecord.validate([legacy], for: center)
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = PortraitCandidateStore(directoryURL: directory)
    try await store.save(snapshot: .init(entries: [.init(candidate: center, reasons: [], exploration: [legacy])]))
    let collection = await PortraitSketchCollection(store: store)
    await collection.load()
    #expect(await collection.entries.first?.exploration == [legacy])
    #expect(await collection.retain(candidate: center, reason: .shortlisted) == nil)
    await collection.awaitPersistence()
    let loaded = await store.load()
    #expect(loaded.canWrite)
    #expect(loaded.archive.entries.first?.exploration == [legacy])
    object["policyRevision"] = "unknown-future-policy"
    let unknown = try JSONDecoder().decode(PortraitExplorationRecord.self,
      from: JSONSerialization.data(withJSONObject: object))
    #expect(throws: (any Error).self) { try PortraitExplorationRecord.validate([unknown], for: center) }
  }

  @Test("raster caches separate flow sampling from the historical analysis resolution")
  func rasterResolutionCache() throws {
    let candidate = try fixture()
    let pen = try portraitTestStyle()
    var cache = PortraitRenderCache()
    let result = PortraitRenderResult(raster: candidate.raster, program: candidate.program)
    cache.insert(result, for: .init(photoID: candidate.photoID,
      configuration: .init(style: .flowEdges, vectors: candidate.recipe.vectorOptions,
        analysis: candidate.recipe.analysisOptions), strokeStyle: pen))
    #expect(cache.raster(for: .init(photoID: candidate.photoID,
      analysis: candidate.recipe.analysisOptions, maximumDimension: 160)) == nil)
    #expect(cache.raster(for: .init(photoID: candidate.photoID,
      analysis: candidate.recipe.analysisOptions, maximumDimension: 320)) != nil)
  }

  private func fixture(style: PortraitStyle = .contours,
    vectors: PortraitVectorOptions = .init()) throws -> PortraitCandidate {
    let size = 32
    let raster = PortraitRaster(width: size, height: size,
      luminance: (0..<(size * size)).map { Double($0 % size) / Double(size - 1) },
      provenance: "exploration-policy-fixture", analysisSummary: "Deterministic gradient")
    let recipe = PortraitStyleRecipe(id: "fixture", title: "Fixture", seed: 0, style: style,
      vectorOptions: vectors, analysisOptions: .init(cropToFace: false, removeBackground: false))
    // The fixture's exact geometry is sufficient to seed proposals even for
    // styles whose extreme thresholds intentionally produce no lines.
    let program = try PortraitVectorizer.program(from: raster, pose: .front, style: .contours,
      strokeStyle: portraitTestStyle())
    return try PortraitCandidate(sourceData: Data([1]), sourcePixelExtent: nil,
      raster: raster, recipe: recipe, program: program, photoID: UUID(), captureSessionID: UUID(), pose: .front)
  }
}
