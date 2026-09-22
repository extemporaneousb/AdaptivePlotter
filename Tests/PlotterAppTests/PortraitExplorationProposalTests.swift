import Foundation
import PlotterModel
import Testing

@testable import PlotterApp

@Suite("Portrait exploration proposals")
struct PortraitExplorationProposalTests {
  @Test("seeded bounded proposals keep source analysis and algorithm fixed", arguments: PortraitStyle.allCases)
  func deterministic(style: PortraitStyle) throws {
    let center = try fixture(style: style)
    let proposals = PortraitExplorationPolicy.recipes(around: center, variation: 0.35, seed: 51)
    #expect(proposals.count == 2)
    #expect(proposals.allSatisfy { $0.count == PortraitExplorationPolicy.maximumAttemptsPerSlot })
    #expect(proposals == PortraitExplorationPolicy.recipes(around: center, variation: 0.35, seed: 51))
    #expect(proposals != PortraitExplorationPolicy.recipes(around: center, variation: 0.35, seed: 52))
    for recipe in proposals.flatMap({ $0 }) {
      #expect(recipe.style == center.recipe.style)
      #expect(recipe.analysisOptions == center.recipe.analysisOptions)
      #expect(recipe.vectorOptions == recipe.vectorOptions.bounded)
      if style == .flowEdges { #expect(recipe.vectorOptions.hatchSpacing >= 3) }
      #expect(recipe.vectorOptions.materialContext == center.recipe.vectorOptions.materialContext)
      #expect(recipe.vectorOptions.headScale == 1)
      #expect(recipe.vectorOptions.semanticHead == nil)
      if style != .contours { #expect(recipe.vectorOptions.contourLevels == center.recipe.vectorOptions.contourLevels) }
      if style == .contours || style == .sketch {
        #expect(recipe.vectorOptions.hatchSpacing == center.recipe.vectorOptions.hatchSpacing)
        #expect(recipe.vectorOptions.hatchAngleDegrees == center.recipe.vectorOptions.hatchAngleDegrees)
      }
      if style == .hatch || style == .crosshatch {
        #expect(recipe.vectorOptions.minimumContourLength == center.recipe.vectorOptions.minimumContourLength)
        #expect(recipe.vectorOptions.simplificationTolerance == center.recipe.vectorOptions.simplificationTolerance)
      }
      if style != .sketch && style != .sketchHatch && style != .flowEdges {
        #expect(recipe.vectorOptions.sketchThreshold == center.recipe.vectorOptions.sketchThreshold)
      }
    }
  }

  @Test("consistent accepted direction increases the internal step and rejection shrinks it")
  func adaptiveStep() {
    var search = PortraitExplorationSearchState()
    var first = PortraitVectorOptions()
    first.tonalStrength = 0.8
    var second = first; second.tonalStrength = 1
    var third = second; third.tonalStrength = 1.2
    search.prefer(second, over: first)
    let afterFirst = search.step
    search.prefer(third, over: second)
    #expect(search.step > afterFirst)
    let afterContinuation = search.step
    search.prefer(second, over: third)
    #expect(search.step < afterContinuation)
    search.prefer(second, over: second)
    #expect(search.direction == nil)
    for _ in 0..<50 { search.prefer(second, over: second) }
    #expect(search.step >= 0.12)
  }

  @Test("material snapshots and effective floors survive proposals without sampling hidden axes")
  func materialFloors() throws {
    let material = try PortraitMaterialContext(
      profile: .init(name: "Broad proposal fixture", nominalWidthMM: 5), drawingHeightMM: 2)
    var vectors = PortraitVectorOptions()
    vectors.materialContext = material
    let center = try fixture(style: .sketchHatch, vectors: vectors)
    let effective = try material.adapting(vectors, raster: center.raster)
    #expect(effective.minimumContourLength > 40)
    #expect(effective.hatchSpacing > 16)
    let recipes = PortraitExplorationPolicy.recipes(around: center, variation: 1, seed: 83).flatMap { $0 }
    for recipe in recipes {
      #expect(recipe.vectorOptions.materialContext == material)
      #expect(recipe.vectorOptions.minimumContourLength == vectors.minimumContourLength)
      #expect(recipe.vectorOptions.hatchSpacing == vectors.hatchSpacing)
      #expect(recipe.vectorOptions == recipe.vectorOptions.bounded)
      let rendered = try material.adapting(recipe.vectorOptions, raster: center.raster)
      #expect(rendered.minimumContourLength == effective.minimumContourLength)
      #expect(rendered.hatchSpacing == effective.hatchSpacing)
    }
    #expect(Set(recipes.map(\.vectorOptions)).count >= 2)
  }

  @Test("internal small steps keep productive minimum probes while zero remains unchanged")
  func spread() throws {
    let center = try fixture()
    let zero = PortraitExplorationPolicy.recipes(around: center, variation: 0, seed: 1)
    #expect(zero.flatMap { $0 }.allSatisfy { $0.vectorOptions == center.recipe.vectorOptions })
    let narrow = PortraitExplorationPolicy.recipes(around: center, variation: 0.1, seed: 1).flatMap { $0 }
    let broad = PortraitExplorationPolicy.recipes(around: center, variation: 0.5, seed: 1).flatMap { $0 }
    #expect(narrow.allSatisfy { $0.vectorOptions != center.recipe.vectorOptions })
    #expect(broad.allSatisfy { $0.vectorOptions != center.recipe.vectorOptions })
    #expect(narrow != broad)
    #expect(PortraitExplorationPolicy.boundedVariation(.nan) == 0.35)
    #expect(PortraitExplorationPolicy.boundedVariation(-2) == 0)
    #expect(PortraitExplorationPolicy.boundedVariation(2) == 1)
  }

  @Test("Flow minimum spacing and coarse material floors still admit effective moves at minimum trust step")
  func flowEffectiveMoves() throws {
    var vectors = PortraitVectorOptions.flowDefaults
    vectors.hatchSpacing = 3
    let center = try fixture(style: .flowEdges, vectors: vectors)
    var direction = [Double](repeating: 0, count: 9)
    direction[5] = -1
    for seed in UInt64(0)..<32 {
      let recipe = PortraitExplorationPolicy.recipes(around: center, variation: 0.12,
        seed: seed, direction: direction)[0][0]
      #expect(recipe.vectorOptions.hatchSpacing >= 5)
      #expect(PortraitExplorationPolicy.effectiveOptions(recipe.vectorOptions, center: center)
        != PortraitExplorationPolicy.effectiveOptions(vectors, center: center))
    }
    let material = try PortraitMaterialContext(
      profile: .init(name: "Floor fixture", nominalWidthMM: 1), drawingHeightMM: 8)
    vectors.materialContext = material
    let adaptedCenter = try fixture(style: .flowEdges, vectors: vectors)
    var subfloor = vectors; subfloor.minimumContourLength = 1; subfloor.hatchSpacing = 4
    var otherSubfloor = subfloor; otherSubfloor.minimumContourLength = 2; otherSubfloor.hatchSpacing = 5
    #expect(PortraitExplorationPolicy.effectiveOptions(subfloor, center: adaptedCenter)
      == PortraitExplorationPolicy.effectiveOptions(otherSubfloor, center: adaptedCenter))
    let spacingMove = PortraitExplorationPolicy.recipes(around: adaptedCenter, variation: 0.12,
      seed: 1, direction: direction)[0][0]
    #expect(PortraitExplorationPolicy.effectiveOptions(spacingMove.vectorOptions, center: adaptedCenter)
      != PortraitExplorationPolicy.effectiveOptions(vectors, center: adaptedCenter))
    #expect(spacingMove.vectorOptions.materialContext == material)
  }

  @Test("Flow line-form proposals use visible picker modes and recovery changes an ineffective axis")
  func lineFormModes() throws {
    for mode in [0.0, 0.5, 1.0] {
      var vectors = PortraitVectorOptions.flowDefaults
      vectors.flowRectilinearity = mode == 0 ? nil : mode
      let center = try fixture(style: .flowEdges, vectors: vectors)
      for seed in UInt64(0)..<32 {
        let recipes = PortraitExplorationPolicy.recipes(around: center, variation: 0.12, seed: seed)
        #expect(recipes.flatMap { $0 }.allSatisfy { [0.0, 0.5, 1.0].contains($0.vectorOptions.flowRectilinearity ?? 0) })
        let recovery = PortraitExplorationPolicy.recoveryRecipe(around: center, failed: center.recipe,
          rejection: .similarGeometry, neighbor: 0, seed: seed, variation: 0.12)
        #expect(recovery.vectorOptions.flowRectilinearity != vectors.flowRectilinearity)
      }
    }
  }

  @Test("reflection leaves legal nontrivial moves at extreme controls")
  func bounds() throws {
    for value in [0.0, 1.0] {
      var options = PortraitVectorOptions()
      options.tonalStrength = value == 0 ? 0.4 : 2
      options.smoothing = value * 4
      options.minimumContourLength = value * 40
      options.simplificationTolerance = value * 3
      options.contourLevels = value == 0 ? 1 : 12
      let center = try fixture(vectors: options)
      let recipes = PortraitExplorationPolicy.recipes(around: center, variation: 1, seed: 99).flatMap { $0 }
      #expect(recipes.allSatisfy { $0.vectorOptions == $0.vectorOptions.bounded })
      #expect(Set(recipes.map(\.vectorOptions)).count >= 2)
    }
  }

  @Test("visible geometry identity rejects provenance, direction and negligible coordinate differences")
  func geometryIdentity() throws {
    let center = try fixture()
    let original = center.program
    let reversed = try DrawingProgram(id: ProgramID(UUID()), fieldExtent: original.fieldExtent,
      strokes: original.strokes.reversed().enumerated().map { index, stroke in
        LogicalStroke(id: StrokeID(UUID()), path: try Polyline(points: Array(stroke.path.points.reversed())),
          style: stroke.style, ordering: UInt32(index))
      }, source: .init(kind: "fixture", sourceIdentifier: "different parameters same paths"))
    #expect(original.contentHash != reversed.contentHash)
    #expect(PortraitExplorationPolicy.geometryIdentity(original) == PortraitExplorationPolicy.geometryIdentity(reversed))
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

  @Test("v1 nine-slot and v2 three-slot receipts decode while unknown revisions fail")
  func legacyReceiptCompatibility() throws {
    let center = try fixture()
    let round = PortraitExplorationRound(id: UUID(), seed: 7, variation: 0.35,
      center: center, slots: (0..<3).map { index in
        .init(index: index, candidate: index == 1 ? center : nil,
          unavailableReason: index == 1 ? nil : "No option")
      })
    let record = PortraitExplorationRecord(round: round, action: .selected(index: 1),
      traceSessionID: UUID(), sequence: 0)
    var object = try #require(JSONSerialization.jsonObject(with: PortraitCandidateCoding.encoder().encode(record)) as? [String: Any])
    object["policyRevision"] = "portrait-preference-v2"
    let v2 = try JSONDecoder().decode(PortraitExplorationRecord.self,
      from: JSONSerialization.data(withJSONObject: object))
    try PortraitExplorationRecord.validate([v2], for: center)
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

  @Test("bounded receipt merge cannot replace newer saved choices with an older handoff snapshot")
  func receiptOrder() throws {
    let center = try fixture()
    let round = PortraitExplorationRound(id: UUID(), seed: 7, variation: 0,
      center: center, slots: (0..<3).map { index in
        .init(index: index, candidate: index == 1 ? center : nil,
          unavailableReason: index == 1 ? nil : "Zero variation")
      })
    let session = UUID()
    let records = (0..<66).map { sequence in
      PortraitExplorationRecord(round: round, action: .selected(index: 1),
        traceSessionID: session, sequence: UInt64(sequence))
    }
    let current = Array(records.suffix(PortraitExplorationPolicy.maximumRecords))
    let merged = PortraitExplorationRecord.merging(current, with: Array(records.prefix(2)))
    #expect(merged == current)
    #expect(merged.map(\.sequence) == Array(UInt64(2)..<UInt64(66)))
    try PortraitExplorationRecord.validate(merged, for: center)
    #expect(throws: (any Error).self) {
      try PortraitExplorationRecord.validate([records[1], records[0]], for: center)
    }
    #expect(throws: (any Error).self) {
      try PortraitExplorationRecord.validate([records[1], records[1]], for: center)
    }
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
