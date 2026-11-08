@testable import PortraitArtists
@testable import PortraitLibrary
@testable import PortraitStudioUI
import Foundation
import PlotterModel
import Testing
@testable import PlotterApp

@Suite("Shared-parameter preference learning")
struct PortraitParameterPreferenceTests {
  @Test("Independent held-out preferences activate a finite repeatable model")
  func heldOutLearning() throws {
    let rows = observations()
    let report = PortraitParameterPreference.fit(rows, contextID: "fixture")
    let model = try #require(report.model)
    #expect(model.holdoutLoss < model.baselineLoss)
    #expect(model.orderingAccuracy == 1)
    #expect(model.trainingCount == 18 && model.holdoutCount == 6)
    #expect(model.score(.init(detail: 0.9)) > model.score(.init(detail: 0.1)))
    #expect(model.id == PortraitParameterPreference.fit(Array(rows.reversed()), contextID: "fixture").model?.id)
    let bytes = try PortraitCandidateCoding.encoder().encode(model)
    #expect(try JSONDecoder().decode(PortraitParameterPreference.Model.self, from: bytes).id == model.id)
  }

  @Test("Sparse votes, shared ancestry and failed holdout do not activate learning")
  func fallbackAndLeakage() {
    #expect(PortraitParameterPreference.fit(Array(observations().prefix(3)), contextID: "fixture").model == nil)
    let shared = UUID()
    let related = observations().map { replacing($0, ancestry: shared) }
    #expect(Set(PortraitParameterPreference.groups(related)).count == 1)
    #expect(PortraitParameterPreference.fit(related, contextID: "fixture").model == nil)
    let sessions = observations().map { replacing($0, session: shared) }
    #expect(Set(PortraitParameterPreference.groups(sessions)).count == 1)
    var reversedHoldout = observations()
    let lastGroup = PortraitParameterPreference.groups(reversedHoldout).max()!
    let groups = PortraitParameterPreference.groups(reversedHoldout)
    for index in reversedHoldout.indices where groups[index] == lastGroup {
      reversedHoldout[index] = replacing(reversedHoldout[index], promising: !reversedHoldout[index].promising)
    }
    #expect(PortraitParameterPreference.fit(reversedHoldout, contextID: "fixture").model == nil)
  }

  @Test("Learned proposals preserve family, material and regions; baseline exploration remains", arguments: [PortraitStyle.contours, .flowEdges])
  func proposalAuthority(style: PortraitStyle) throws {
    let center = try candidate(style: style, seed: 1)
    let context = try #require(PortraitParameterPreference.contextID(center))
    let model = try #require(PortraitParameterPreference.fit(observations(), contextID: context).model)
    let recipe = try #require(model.recipe(around: center, seed: 7))
    #expect(recipe.style == center.recipe.style)
    #expect(recipe.analysisOptions == center.recipe.analysisOptions)
    var expected = center.recipe.vectorOptions
    expected.drawingParameters = recipe.vectorOptions.drawingParameters
    #expect(recipe.vectorOptions == expected)
    #expect(recipe.vectorOptions.drawingParameters == recipe.vectorOptions.drawingParameters?.bounded)
    #expect(model.recipe(around: center, seed: 8) == nil)
    #expect(model.recipe(around: try candidate(style: style, seed: 3, tone: 1.8), seed: 7) == nil)
    let geometry = try PortraitVectorizer.program(from: center.raster, pose: .front, style: style,
      strokeStyle: portraitTestStyle(), vectorOptions: recipe.vectorOptions)
    #expect(!geometry.strokes.isEmpty)
    #expect(geometry.strokes.map(\.path) != center.program.strokes.map(\.path))
    #expect(model.recipe(around: try candidate(style: style == .contours ? .flowEdges : .contours, seed: 2), seed: 7) == nil)
  }





  private func observations() -> [PortraitParameterPreference.Observation] {
    var result: [PortraitParameterPreference.Observation] = []
    for group in 0..<4 {
      let session = UUID(), ancestry = UUID()
      for sample in 0..<6 {
        let detail = sample < 3 ? 0.15 + Double(sample) * 0.08 : 0.7 + Double(sample - 3) * 0.08
        let parameters = PortraitDrawingParameters(detail: detail, smoothness: 0.4 + Double(sample % 3) * 0.1)
        result.append(.init(candidateID: String(format: "%02d-%02d", group, sample),
          proposalIdentity: "\(group)-\(sample)", feedbackID: UUID(), sourceSHA256: "source-\(group)",
          sessionID: session, ancestryID: ancestry, parameters: parameters, promising: sample >= 3))
      }
    }
    return result
  }

  private func replacing(_ row: PortraitParameterPreference.Observation, ancestry: UUID? = nil,
    session: UUID? = nil, promising: Bool? = nil) -> PortraitParameterPreference.Observation {
    .init(candidateID: row.candidateID, proposalIdentity: row.proposalIdentity, feedbackID: row.feedbackID,
      sourceSHA256: row.sourceSHA256, sessionID: session ?? row.sessionID, ancestryID: ancestry ?? row.ancestryID,
      parameters: row.parameters, promising: promising ?? row.promising)
  }

  private func candidate(style: PortraitStyle, seed: UInt64, tone: Double = 1) throws -> PortraitCandidate {
    let raster = try regionalFixture()
    var options = PortraitVectorOptions(drawingParameters: .init(detail: 0.15, tone: tone))
    options.setTreatment(.init(scope: .eyes, angularity: 0.2))
    let recipe = PortraitStyleRecipe(id: "learning", title: "Shared", seed: seed, style: style,
      vectorOptions: options, analysisOptions: .init())
    let program = try PortraitVectorizer.program(from: raster, pose: .front, style: style,
      strokeStyle: portraitTestStyle(), vectorOptions: options)
    return try PortraitCandidate(sourceData: Data([1]), sourcePixelExtent: nil, raster: raster,
      recipe: recipe, program: program, photoID: UUID(), captureSessionID: UUID(), pose: .front)
  }
}
