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
    #expect(proposals.count == 8)
    #expect(proposals.allSatisfy { $0.count == PortraitExplorationPolicy.maximumAttemptsPerSlot })
    #expect(proposals == PortraitExplorationPolicy.recipes(around: center, variation: 0.35, seed: 51))
    #expect(proposals != PortraitExplorationPolicy.recipes(around: center, variation: 0.35, seed: 52))
    for recipe in proposals.flatMap({ $0 }) {
      #expect(recipe.style == center.recipe.style)
      #expect(recipe.analysisOptions == center.recipe.analysisOptions)
      #expect(recipe.vectorOptions == recipe.vectorOptions.bounded)
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
      if style != .sketch && style != .sketchHatch {
        #expect(recipe.vectorOptions.sketchThreshold == center.recipe.vectorOptions.sketchThreshold)
      }
    }
  }

  @Test("the fixed nearby coupled broader mix changes grid positions across seeds")
  func shuffledPositions() throws {
    let center = try fixture()
    let positions = (1...8).map { seed in
      PortraitExplorationPolicy.recipes(around: center, variation: 0.35, seed: UInt64(seed)).map {
        // Recipe provenance identifies its generated move before grid placement.
        String($0[0].id.split(separator: "-")[2])
      }
    }
    #expect(Set(positions).count > 1)
    #expect(positions.allSatisfy { Set($0) == Set((0..<8).map(String.init)) })
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
    #expect(Set(recipes.map(\.vectorOptions)).count > 8)
  }

  @Test("manual spread scales the same seeded continuous moves and zero does not alter controls")
  func spread() throws {
    let center = try fixture()
    let zero = PortraitExplorationPolicy.recipes(around: center, variation: 0, seed: 1)
    #expect(zero.flatMap { $0 }.allSatisfy { $0.vectorOptions == center.recipe.vectorOptions })
    let narrow = PortraitExplorationPolicy.recipes(around: center, variation: 0.1, seed: 1).flatMap { $0 }
    let broad = PortraitExplorationPolicy.recipes(around: center, variation: 0.5, seed: 1).flatMap { $0 }
    // Smoothing begins at zero and reflection has no upper-bound collision at
    // these scales, so the exact continuous displacement is five times larger.
    for (a, b) in zip(narrow, broad) {
      #expect(abs(b.vectorOptions.smoothing - a.vectorOptions.smoothing * 5) < 1e-12)
    }
    #expect(PortraitExplorationPolicy.boundedVariation(.nan) == 0.35)
    #expect(PortraitExplorationPolicy.boundedVariation(-2) == 0)
    #expect(PortraitExplorationPolicy.boundedVariation(2) == 1)
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
      #expect(Set(recipes.map(\.vectorOptions)).count > 8)
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

  @Test("bounded receipt merge cannot replace newer saved choices with an older handoff snapshot")
  func receiptOrder() throws {
    let center = try fixture()
    let round = PortraitExplorationRound(id: UUID(), seed: 7, variation: 0,
      center: center, slots: (0..<9).map { index in
        .init(index: index, candidate: index == 4 ? center : nil,
          unavailableReason: index == 4 ? nil : "Zero variation")
      })
    let session = UUID()
    let records = (0..<66).map { sequence in
      PortraitExplorationRecord(round: round, action: .selected(index: 4),
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
