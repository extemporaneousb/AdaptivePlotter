import PlotterRuntime
import Testing

@testable import PlotterApp

@Suite("Learning Path presentation")
struct LearningPathPresentationTests {
  @Test("operator journey has the exact five numbered stages")
  func exactFiveStageJourney() {
    #expect(LearningPathStage.allCases.map(\.number) == ["1", "2", "3", "4", "5"])
    #expect(
      LearningPathStage.allCases.map(\.title) == [
        "Connect",
        "Enable Motion",
        "Human-Guided Discovery",
        "Observed Drawing Trials",
        "Adaptive Drawing",
      ])
  }

  @Test("stage statuses are presentation terms without a progress percentage")
  func stageStatuses() {
    #expect(
      LearningPathStageStatus.allCases.map(\.rawValue) == [
        "Complete",
        "Current",
        "Next",
        "Future",
        "Needs Attention",
      ])
  }

  @Test("Human-Guided Discovery exposes the exact ordered substeps")
  func exactDiscoverySteps() {
    #expect(HumanGuidedDiscoveryStep.allCases.map(\.stepNumber) == ["3.1", "3.2", "3.3"])
    #expect(
      HumanGuidedDiscoveryStep.allCases.map(\.title) == [
        "Pen Interaction",
        "Boundary Discovery",
        "Clear-View Discovery",
      ])
  }

  @Test("Observed Drawing Trials exposes the exact six-step sequence")
  func exactDrawingTrialSteps() {
    #expect(
      ObservedDrawingTrialStep.allCases.map(\.stepNumber) == [
        "4.1", "4.2", "4.3", "4.4", "4.5", "4.6",
      ])
    #expect(
      ObservedDrawingTrialStep.allCases.map(\.title) == [
        "Capture Clean Reference",
        "Choose Line Start",
        "Create Anchor Mark",
        "Draw Isolated Line",
        "Clear Tool and Observe Ink",
        "Compare Intended and Observed Geometry",
      ])
  }

  @Test("operator action keeps buttons typed and unavailable reason runtime-owned")
  func typedOperatorAction() {
    let action = OperatorActionPresentation(
      stepNumber: "3.1",
      title: "Confirm Pen Up",
      participant: "Operator",
      action: "Observe the mechanism.",
      expectedObservation: "The pen is physically Up.",
      primaryActionUnavailableReason: "Current runtime fact is missing.",
      choices: [.yes, .no]
    )

    #expect(action.choices == [.yes, .no])
    #expect(action.primaryActionUnavailableReason == "Current runtime fact is missing.")
    #expect(action.requestedFeedMMPerMinute == nil)
    #expect(action.feedSource == nil)
  }

}
