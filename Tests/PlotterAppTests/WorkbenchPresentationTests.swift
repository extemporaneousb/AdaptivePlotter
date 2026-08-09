import Foundation
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
    #expect(presentation.stopAction?.title == "Stop Manual Jog")
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
    #expect(
      MotionRequestStatusPresentation.needsAttention("Alarm.").label == "Needs Attention"
    )
    #expect(
      MotionRequestStatusPresentation.needsAttention("Alarm.").detail == "Alarm."
    )
  }

  @Test("LIVE and SIMULATED camera utilities retain one semantic action order")
  func cameraUtilityParity() {
    let live = CameraUtilityPresentation(
      mode: .live,
      actions: actions(unavailableReason: nil)
    )
    let simulated = CameraUtilityPresentation(
      mode: .simulated,
      actions: actions(unavailableReason: "LIVE camera capture only."),
      analysisCadenceUnavailableReason: "LIVE automatic analysis only."
    )

    #expect(live.actions.map(\.kind) == CameraUtilityActionKind.allCases)
    #expect(simulated.actions.map(\.kind) == CameraUtilityActionKind.allCases)
    #expect(live.actions.map(\.kind) == simulated.actions.map(\.kind))
    #expect(live.actions.allSatisfy { $0.isEnabled })
    #expect(simulated.actions.allSatisfy { !$0.isEnabled })
    #expect(
      simulated.analysisCadenceUnavailableReason == "LIVE automatic analysis only."
    )
  }

  private func actions(
    unavailableReason: String?
  ) -> [CameraUtilityActionPresentation] {
    CameraUtilityActionKind.allCases.map { kind in
      CameraUtilityActionPresentation(
        kind: kind,
        title: title(kind),
        systemImage: "circle",
        unavailableReason: unavailableReason
      )
    }
  }

  private func title(_ kind: CameraUtilityActionKind) -> String {
    switch kind {
    case .refresh: "Refresh"
    case .start: "Start Camera"
    case .stop: "Stop Camera"
    case .restart: "Restart Camera"
    case .analyzeOrResume: "Analyze Frame"
    case .saveSnapshot: "Save Snapshot"
    case .toggleAutomaticAnalysis: "Enable Auto Analyze"
    }
  }
}
