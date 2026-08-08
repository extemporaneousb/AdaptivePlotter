import Foundation
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

  @Test("flow coordinator stores presentation location only")
  func presentationLocation() {
    var flow = LearningPathFlowCoordinator()
    #expect(flow.phase == .connect)

    flow.present(.humanGuidedDiscovery(.boundaryDiscovery))
    #expect(flow.phase == .humanGuidedDiscovery(.boundaryDiscovery))

    flow.present(.observedDrawingTrials(.clearToolAndObserveInk))
    #expect(flow.phase == .observedDrawingTrials(.clearToolAndObserveInk))

    flow.present(.adaptiveDrawing)
    #expect(flow.phase == .adaptiveDrawing)
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

  @Test("start actions expose the exact runtime unavailable reason")
  func discoveryStartReasonsAreRendered() throws {
    let source = try learningPathViewSource()

    for reasonName in ["penStartUnavailableReason", "boundaryStartUnavailableReason"] {
      #expect(source.contains(".disabled(\(reasonName) != nil)"))
      #expect(source.contains("if let \(reasonName)"))
      #expect(source.contains("actionableError(\(reasonName))"))
    }
    #expect(source.contains("workspace.discoveryStartUnavailableReason("))
    #expect(source.contains("if let reason = presentation.primaryActionUnavailableReason"))
  }

  @Test("Clear-View acceptance stays disabled until the runtime label and observation are Clear")
  func clearViewAcceptanceRequiresCurrentClearEvidence() throws {
    let source = try learningPathViewSource()

    #expect(
      source.contains(
        "workspace.pendingClearViewLabel != .clear\n"
          + "              || workspace.lastArmatureObservation?.humanLabel != .clear"
      ))
    #expect(source.contains("let discoveryError = workspace.discoveryError"))
    #expect(source.contains("let explorationError = workspace.explorationError"))
  }
}

private func learningPathViewSource() throws -> String {
  let testFile = URL(fileURLWithPath: #filePath)
  let projectRoot = testFile
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
  return try String(
    contentsOf: projectRoot.appendingPathComponent("Sources/PlotterApp/LearningPathView.swift"),
    encoding: .utf8
  )
}
