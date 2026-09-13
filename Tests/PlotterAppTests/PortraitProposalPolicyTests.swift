import Foundation
import Testing

@testable import PlotterApp

@Suite("Balanced portrait exploration policy")
struct PortraitProposalPolicyTests {
  @Test("broad sampling follows the declared 30/30/30/4/3/3 family distribution")
  func weightedDistribution() {
    let expected: [PortraitExplorationFamily: Int] = [
      .contour: 30, .tonalContour: 30, .cleanLine: 30,
      .hatch: 4, .crosshatch: 3, .sketchHatch: 3,
    ]
    #expect(Dictionary(uniqueKeysWithValues: PortraitProposalPolicy.familyWeights.map { ($0.family, $0.weight) }) == expected)
    var counts: [PortraitExplorationFamily: Int] = [:]
    for seed in UInt64(0)..<10_000 {
      let proposal = PortraitProposalPolicy.broad(seed: seed, penWidthMM: 0.8)
      counts[proposal.metadata.family, default: 0] += 1
      #expect(proposal.recipe.style == proposal.metadata.family.style)
      if proposal.metadata.family == .contour { #expect((1...3).contains(proposal.recipe.vectorOptions.contourLevels)) }
      if proposal.metadata.family == .tonalContour { #expect((4...8).contains(proposal.recipe.vectorOptions.contourLevels)) }
    }
    for (family, weight) in expected {
      // This fixed 10,000-seed population must remain within one percentage
      // point of its declared distribution, including the deliberate hatch tail.
      #expect(abs(Double(counts[family, default: 0]) / 100 - Double(weight)) < 1)
    }
    #expect(counts == [.contour: 2970, .tonalContour: 3031, .cleanLine: 2944,
      .hatch: 430, .crosshatch: 341, .sketchHatch: 284])
  }

  @Test("broad seeds reproduce recipes and metadata and existing random callers use this prior")
  func reproducibility() throws {
    for width in [0.1, 0.8, 1.4, 5] {
      for seed in [UInt64(0), 42, .max] {
        for bigHead in [false, true] {
          let proposal = PortraitProposalPolicy.broad(seed: seed, penWidthMM: width, bigHead: bigHead)
          #expect(proposal == PortraitProposalPolicy.broad(seed: seed, penWidthMM: width, bigHead: bigHead))
          #expect(proposal.recipe == PortraitStyleRecipe.random(seed: seed, penWidthMM: width, bigHead: bigHead))
          #expect(proposal.metadata.policyRevision == "portrait-proposal-v1")
          #expect(proposal.metadata.kind == .broad)
          #expect(proposal.metadata.seed == seed)
          #expect(proposal.recipe.vectorOptions == proposal.recipe.vectorOptions.bounded)
          #expect(bigHead ? proposal.recipe.vectorOptions.headScale > 1 : proposal.recipe.vectorOptions.headScale == 1)
          let encoded = try JSONEncoder().encode(proposal.metadata)
          #expect(try JSONDecoder().decode(PortraitProposalMetadata.self, from: encoded) == proposal.metadata)
        }
      }
    }
    #expect(PortraitProposalPolicy.broad(seed: 42, penWidthMM: .infinity)
      == PortraitProposalPolicy.broad(seed: 42, penWidthMM: 0.8))
    #expect(PortraitStyleRecipe.catalog().contains { $0.style == .crosshatch })
    #expect(PortraitStyleRecipe.catalog().contains { $0.style == .sketchHatch })
  }

  @Test("local neighborhoods preserve analysis, family, head and irrelevant controls at every boundary")
  func localBoundaries() throws {
    for family in PortraitExplorationFamily.allCases {
      for headScale in [1.0, 1.6] {
        for upper in [false, true] {
          let options = PortraitVectorOptions(
            contourLevels: upper ? 12 : 1, minimumContourLength: upper ? 40 : 0,
            simplificationTolerance: upper ? 3 : 0, hatchSpacing: upper ? 16 : 1,
            tonalStrength: upper ? 2 : 0.4, smoothing: upper ? 4 : 0,
            sketchThreshold: upper ? 0.08 : 0.002, hatchAngleDegrees: upper ? 90 : -90,
            headScale: headScale)
          let recipe = PortraitStyleRecipe(id: "boundary-\(family)-\(upper)-\(headScale)",
            title: "Boundary fixture", seed: 91, style: family.style, vectorOptions: options,
            analysisOptions: .init(cropToFace: false, removeBackground: false, faceCropMargin: 0.63))
          let parent = try candidate(recipe: recipe, family: family)
          let original = try PortraitCandidateCoding.encoder().encode(parent)
          let active = PortraitProposalPolicy.localParameters(family: family, headScale: headScale)
          for seed in UInt64(0)..<16 {
            let local = PortraitProposalPolicy.local(parent: parent, seed: seed)
            #expect(local == PortraitProposalPolicy.local(parent: parent, seed: seed))
            #expect(local.metadata.family == family)
            #expect(local.metadata.kind == .local)
            #expect(local.recipe.style == parent.recipe.style)
            #expect(local.recipe.analysisOptions == parent.recipe.analysisOptions)
            #expect(local.recipe.vectorOptions.headScale == headScale)
            #expect(local.recipe.vectorOptions == local.recipe.vectorOptions.bounded)
            for parameter in PortraitTrainableParameter.allCases {
              let old = value(parameter, options), new = value(parameter, local.recipe.vectorOptions)
              if active.contains(parameter) {
                #expect(abs(new - old) <= PortraitProposalPolicy.localRadius(parameter: parameter) + 1e-12)
              } else { #expect(new == old) }
            }
          }
          #expect(try PortraitCandidateCoding.encoder().encode(parent) == original)
        }
      }
    }
  }

  @Test("local metadata preserves a contour branch category after its level count crosses the inference boundary")
  func categoryIsNotReinferred() throws {
    let recipe = PortraitStyleRecipe(id: "tonal-at-three", title: "Tonal branch", seed: 9,
      style: .contours, vectorOptions: .init(contourLevels: 3), analysisOptions: .init())
    let explicit = try candidate(recipe: recipe, family: .tonalContour)
    #expect(PortraitProposalPolicy.local(parent: explicit, seed: 42).metadata.family == .tonalContour)
    let legacy = try candidate(recipe: recipe, family: nil)
    #expect(PortraitProposalPolicy.local(parent: legacy, seed: 42).metadata.family == .contour)
  }

  @Test("local proposals change relevant controls and leave pure hatch path filters untouched")
  func localVariation() throws {
    for family in PortraitExplorationFamily.allCases {
      let recipe = PortraitStyleRecipe(id: family.rawValue, title: "Fixture", seed: 0,
        style: family.style, vectorOptions: .init(), analysisOptions: .init())
      let parent = try candidate(recipe: recipe, family: family)
      let options = (UInt64(0)..<32).map { PortraitProposalPolicy.local(parent: parent, seed: $0).recipe.vectorOptions }
      #expect(Set(options).count == 32)
      if family == .hatch || family == .crosshatch {
        #expect(options.allSatisfy { $0.minimumContourLength == recipe.vectorOptions.minimumContourLength
          && $0.simplificationTolerance == recipe.vectorOptions.simplificationTolerance
          && $0.contourLevels == recipe.vectorOptions.contourLevels
          && $0.sketchThreshold == recipe.vectorOptions.sketchThreshold })
      }
    }
  }

  private func candidate(recipe: PortraitStyleRecipe,
    family: PortraitExplorationFamily?) throws -> PortraitCandidate {
    // The policy consumes only the immutable recipe and proposal metadata; this
    // envelope supplies an unrelated valid vector payload without running Vision.
    let base = try portraitPersistenceCandidate()
    let metadata = family.map { PortraitProposalMetadata(policyRevision: "fixture", kind: .broad, seed: 91, family: $0) }
    return try PortraitCandidate(sourceData: base.sourceData, sourcePixelExtent: base.sourcePixelExtent,
      raster: base.raster, recipe: recipe, program: base.program, photoID: base.photoID,
      captureSessionID: base.captureSessionID, proposal: metadata)
  }

  private func value(_ parameter: PortraitTrainableParameter, _ options: PortraitVectorOptions) -> Double {
    switch parameter {
    case .contourLevels: Double(options.contourLevels)
    case .minimumContourLength: options.minimumContourLength
    case .simplificationTolerance: options.simplificationTolerance
    case .hatchSpacing: Double(options.hatchSpacing)
    case .tonalStrength: options.tonalStrength
    case .smoothing: options.smoothing
    case .sketchThreshold: options.sketchThreshold
    case .hatchAngleDegrees: options.hatchAngleDegrees
    case .headScale: options.headScale
    case .foreheadWidth, .foreheadHeight, .eyeScale, .lateralScale: 0
    }
  }
}
