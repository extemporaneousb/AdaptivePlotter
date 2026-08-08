import Foundation
import PlotterModel
import Testing

@testable import PlotterRuntime

@Suite("Human-Guided Discovery")
struct HumanGuidedDiscoveryTests {
  @Test("operator choices are only contextual YES and NO")
  func contextualChoices() {
    #expect(OperatorChoice.allCases == [.yes, .no])
  }

  @Test("boundary sequence makes Stop a distinct event before cancel and evidence")
  func boundaryStopOrdering() throws {
    let definition = DiscoverySequenceCatalog.definition(for: .boundaryPositiveX)
    #expect(definition.steps.map(\.id) == [
      "question-ready", "answer-ready", "announce-jog", "start-jog",
      "stop-boundary", "cancel-and-idle", "capture-frame", "measure-boundary",
      "adjust-posterior",
    ])
    #expect(definition.steps[4].action == .awaitContextualStop(.positiveX))

    var transaction = DiscoveryTransaction(definition: definition)
    try transaction.begin()
    try transaction.record(.questionPresented)
    try transaction.record(.operatorChoiceAccepted(.yes))
    try transaction.record(.announcementCompleted)
    try transaction.record(
      .boundaryJogStarted(.positiveX, controllerSummary: "moving")
    )
    let final = try MachinePosition(x: 12, y: 3)
    #expect(throws: DiscoveryTransactionError.unexpectedEvent(stepID: "stop-boundary")) {
      try transaction.record(
        .boundaryJogCancelled(.positiveX, finalPosition: final, controllerSummary: "Idle")
      )
    }
    try transaction.record(.operatorStopRequested(.positiveX))
    try transaction.record(
      .boundaryJogCancelled(.positiveX, finalPosition: final, controllerSummary: "Idle")
    )
    #expect(transaction.currentStep?.id == "capture-frame")
  }

  @Test("pen interaction has announcements before both typed actuations")
  func penAnnouncementOrdering() {
    let actions = DiscoverySequenceCatalog.definition(for: .penInteraction).steps.map(\.action)
    let down = actions.firstIndex(of: .actuatePen(.lower))
    let announceDown = actions.firstIndex(of: .announce("Lowering the pen."))
    let up = actions.firstIndex(of: .actuatePen(.raise))
    let announceUp = actions.firstIndex(of: .announce("Raising the pen."))
    #expect(announceDown != nil && down != nil && announceDown! < down!)
    #expect(announceUp != nil && up != nil && announceUp! < up!)
  }

  @Test("controller feed ceiling selects participating axes only")
  func controllerFeedCeiling() throws {
    let limits = ControllerAxisFeedLimits(
      maximumXFeedMMPerMinute: 900,
      maximumYFeedMMPerMinute: 600
    )
    #expect(limits.applicableFeedCeiling(for: try Vector2(dx: 2, dy: 0)) == 900)
    #expect(limits.applicableFeedCeiling(for: try Vector2(dx: 0, dy: -2)) == 600)
    #expect(limits.applicableFeedCeiling(for: try Vector2(dx: 2, dy: -2)) == 600)
    #expect(limits.applicableFeedCeiling(for: try Vector2(dx: 0, dy: 0)) == nil)
  }
}
