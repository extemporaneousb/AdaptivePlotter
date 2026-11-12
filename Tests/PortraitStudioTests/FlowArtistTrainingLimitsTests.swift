import PortraitArtists
import PortraitStudioUI
import Testing

@Suite("Current Flow training allocation limits")
struct FlowArtistTrainingLimitsTests {
  @Test("The measured historical selection fits the current allocation ceiling; both ceilings remain bounded")
  func boundaries() {
    #expect(FlowArtistTrainingLimits.accepts(featureValueCount: 8_037_846, explicitLabelCount: 1_947))
    #expect(FlowArtistTrainingLimits.accepts(featureValueCount: 10_000_000, explicitLabelCount: 20_000))
    #expect(!FlowArtistTrainingLimits.accepts(featureValueCount: 10_000_001, explicitLabelCount: 1_947))
    #expect(!FlowArtistTrainingLimits.accepts(featureValueCount: 8_037_846, explicitLabelCount: 20_001))
    #expect(!FlowArtistTrainingLimits.accepts(featureValueCount: -1, explicitLabelCount: 0))
  }

  @Test("Authoring allocation estimates admit the measured count and reject the next oversized contribution")
  func authoringBudget() throws {
    var budget = FlowAuthoringTraining.Budget()
    for index in 0..<358 {
      try budget.admit(strokeCount: index < 132 ? 211 : 210, revisionCount: 0,
        labelCount: index < 9 ? 210 : (index == 9 ? 57 : 0))
    }
    // The measured count plus a 10,000-stroke basis still fits; another does not.
    try budget.admit(strokeCount: 10_000, revisionCount: 0, labelCount: 0)
    #expect(throws: (any Error).self) {
      try budget.admit(strokeCount: 10_000, revisionCount: 0, labelCount: 0)
    }
  }

  @Test("Trainer admits 358 examples with the measured logical feature count, and refuses more than ten million before fitting")
  func trainerPreflight() {
    let row = Array(repeating: 0.0, count: FlowArtistFeatures.strokeCount)
    let drawing = Array(repeating: 0.0, count: FlowArtistFeatures.drawingCount)
    func examples(oversized: Bool) -> [FlowArtistExample] {
      (0..<358).map { index in
        // Reuse immutable row storage to test the actual trainer preflight
        // without allocating ten million independent Doubles or fitting a head.
        let strokes = oversized ? 263 : (index < 132 ? 211 : 210)
        let labels = index < 9 ? 210 : (index == 9 ? 57 : 0)
        return FlowArtistExample(id: "capacity-\(index)", sourceGroupID: "capacity-photo", recipe: .standard,
          features: drawing, strokeFeatures: Array(repeating: row, count: strokes),
          strokeLabels: (0..<labels).map { .init(index: $0, removed: true, provenance: .remove) })
      }
    }
    let measured = examples(oversized: false)
    var featureValueCount = 0, explicitLabelCount = 0
    for example in measured {
      featureValueCount += example.features.count
      for row in example.strokeFeatures { featureValueCount += row.count }
      explicitLabelCount += example.strokeLabels.count
    }
    #expect(featureValueCount == 8_037_846)
    #expect(explicitLabelCount == 1_947)
    let accepted = FlowArtistTraining.fit(examples: measured, rankings: [])
    #expect(accepted.checkpoint == nil)
    #expect(accepted.deleter.status.contains("Needs both remove and keep"))
    let rejected = FlowArtistTraining.fit(examples: examples(oversized: true), rankings: [])
    #expect(rejected.checkpoint == nil)
    #expect(rejected.summary.contains("exceeds 10 million feature values"))
  }
}
