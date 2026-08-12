import Foundation
import PlotterModel
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
      actions: actions(unavailableReason: "LIVE camera capture only.")
    )

    #expect(live.actions.map(\.kind) == CameraUtilityActionKind.allCases)
    #expect(simulated.actions.map(\.kind) == CameraUtilityActionKind.allCases)
    #expect(live.actions.map(\.kind) == simulated.actions.map(\.kind))
    #expect(live.actions.allSatisfy { $0.isEnabled })
    #expect(simulated.actions.allSatisfy { !$0.isEnabled })
  }

  @Test("active runtime action strip can keep its sole controls visible")
  func activeExerciseControlsRemainVisible() {
    let active = ExerciseActionStripPresentation(
      ownerID: .humanGuidedDiscovery(.discoverAndAcceptClearView),
      actions: [
        ExerciseActionDescriptor(
          kind: .recordClearViewLabel(.blocked),
          title: "Blocked"
        ),
        ExerciseActionDescriptor(
          kind: .cancel,
          title: "Cancel Attempt",
          role: .destructive
        ),
      ],
      mustRemainVisible: true
    )
    let idle = ExerciseActionStripPresentation(
      ownerID: .observedDrawingTrial(.chooseIsolatedLinePlan),
      actions: [
        ExerciseActionDescriptor(kind: .start, title: "Start", role: .positive)
      ]
    )

    #expect(active.mustRemainVisible)
    #expect(!idle.mustRemainVisible)
  }

  @Test("foreground Vision exposes one capability-bound cancel and truthful circle phase")
  func visibilityObservationPresentation() throws {
    let frame = try StampedFrame(
      sequence: 1,
      captureNanoseconds: 1,
      cameraConfigurationID: CameraConfigurationID(),
      width: 100,
      height: 100,
      rowBytes: 100,
      pixelFormat: .gray8,
      bytes: OwnedFrameBytes(Array(repeating: 0, count: 10_000))
    )
    let searchCircle = try VisibilityTargetSearchCircle(
      center: Point2(x: 28, y: 34),
      radiusPixels: 18,
      anchor: DisplayedFrame(source: .simulated, frame: frame),
      algorithmRevision: "presentation-search-circle-v1"
    )
    let operation = VisibilityObservationOperationPresentation(
      id: VisibilityObservationOperationID(),
      cancelCapabilityID: VisibilityObservationCancelCapabilityID(),
      phase: .analyzingSecondFrame,
      searchCircle: searchCircle,
      targetPlanRevision: VisibilityTargetPlanV2.revision
    )
    #expect(operation.busyDetail.contains("frame 2 of 2"))
    #expect(operation.busyDetail.contains("R 18 px"))
    #expect(operation.busyDetail.contains(VisibilityTargetPlanV2.revision))
    #expect(
      ExerciseActionKind.cancelVisibilityObservation(operation.cancelCapabilityID)
        != .cancel
    )
    #expect(VisibilityObservationPhase.allCases == [
      .preparing,
      .acquiringFirstFrame,
      .acquiringSecondFrame,
      .analyzingFirstFrame,
      .analyzingSecondFrame,
      .cancelling,
      .committing,
    ])
  }

  @Test("exact evidence remains structured alongside actor action outcome and recovery")
  func operationAndEvidenceProjection() {
    let activity = OperationActivityPresentation(
      actor: "Operator",
      action: "Observe Existing Visibility Target",
      outcome: .needsAttention,
      detail: [.text("Ink may exist after accepted Pen Down.")],
      recovery: [.text("Return to the accepted Clear pose and observe; do not redraw.")]
    )
    let evidence = ExerciseEvidencePresentation(
      label: "Exact frames",
      fragments: [
        .text("baseline frame-40"),
        .text("post frames frame-44 and frame-45"),
        .text("camera configuration camera-A"),
      ]
    )

    #expect(activity.actor == "Operator")
    #expect(activity.action == "Observe Existing Visibility Target")
    #expect(activity.outcome == .needsAttention)
    #expect(activity.recovery.accessibilityText.contains("do not redraw"))
    #expect(evidence.label == "Exact frames")
    #expect(evidence.fragments.accessibilityText.contains("frame-44 and frame-45"))
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
    }
  }
}
