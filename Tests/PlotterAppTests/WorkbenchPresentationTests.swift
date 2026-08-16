import Foundation
import PlotterRuntime
import Testing

@testable import PlotterApp

@Suite("Workbench presentation contracts")
struct WorkbenchPresentationTests {
  @Test("manual motion uses explicit units and one capability-bound Stop")
  func manualMotionLabelsAndStop() {
    let capability = ContextualStopCapabilityID(
      rawValue: UUID(uuidString: "00000000-0000-0000-0000-000000000301")!
    )
    let presentation = ManualMotionPresentation(
      stopAction: ContextualStopActionPresentation(
        capabilityID: capability,
        title: "Stop Manual Jog",
        detail: "Stop this manual jog and wait for Idle."
      ),
      jogUnavailableReason: "A relative jog is already in progress."
    )

    #expect(ManualMotionPresentation.xDistanceLabel == "X distance (mm)")
    #expect(ManualMotionPresentation.yDistanceLabel == "Y distance (mm)")
    #expect(ManualMotionPresentation.feedLabel == "Feed (mm/min)")
    #expect(presentation.isStoppable)
    #expect(presentation.stopAction?.capabilityID == capability)
    #expect(presentation.jogControlsUnavailableReason != nil)

    let derivedDisable = ManualMotionPresentation(
      stopAction: presentation.stopAction,
      jogUnavailableReason: nil
    )
    #expect(
      derivedDisable.jogControlsUnavailableReason
        == "Stop the active manual jog before starting another."
    )
  }

  @Test("motion authorization and transient request state remain distinct")
  func motionRequestStatus() {
    #expect(MotionRequestStatusPresentation.ready.label == "Ready")
    #expect(MotionRequestStatusPresentation.ready.detail == nil)
    #expect(MotionRequestStatusPresentation.busy("Settling.").label == "Busy")
    #expect(MotionRequestStatusPresentation.busy("Settling.").detail == "Settling.")
    #expect(MotionRequestStatusPresentation.needsAttention("Alarm.").label == "Needs Attention")
    #expect(MotionRequestStatusPresentation.needsAttention("Alarm.").detail == "Alarm.")
  }

  @Test("active Boundary controls remain visible with one shared capability")
  func activeBoundaryControlsRemainVisible() {
    let capability = ContextualStopCapabilityID(
      rawValue: UUID(uuidString: "00000000-0000-0000-0000-000000000302")!
    )
    let active = ExerciseActionStripPresentation(
      ownerID: .humanGuidedDiscovery(.pairedBoundaryDiscoveryAndCentering),
      actions: [
        ExerciseActionDescriptor(
          kind: .stopAndAcceptBoundary(capability),
          title: "Stop & Accept"
        ),
        ExerciseActionDescriptor(kind: .stop(capability), title: "Stop"),
        ExerciseActionDescriptor(kind: .cancel(capability), title: "Cancel"),
      ],
      mustRemainVisible: true
    )
    let idle = ExerciseActionStripPresentation(
      ownerID: .observedDrawingTrial(.chooseIsolatedLinePlan),
      actions: [ExerciseActionDescriptor(kind: .start, title: "Start")]
    )

    #expect(active.mustRemainVisible)
    #expect(active.actions.map(\.buttonRole) == [.commit, .interrupt, .interrupt])
    #expect(!idle.mustRemainVisible)
  }

  @Test("Exercise script admits only Plotter and You speakers")
  func compactScriptSpeakers() {
    let lines = [
      ExerciseScriptLinePresentation(
        speaker: .plotter,
        fragments: [.text("Move to the selected boundary.")]
      ),
      ExerciseScriptLinePresentation(
        speaker: .you,
        fragments: [.text("Stop at the physical edge.")]
      ),
    ]

    #expect(lines.map(\.speaker) == [.plotter, .you])
    #expect(lines.map { $0.fragments.accessibilityText } == [
      "Move to the selected boundary.",
      "Stop at the physical edge.",
    ])
  }
}
