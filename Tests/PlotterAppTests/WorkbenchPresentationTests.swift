import EpisodeCore
import Foundation
import PlotterEpisodeModel
import PlotterEpisodeRuntime
import PlotterModel
import PlotterRuntime
import Testing

@testable import PlotterApp

@Suite("Workbench presentation contracts")
struct WorkbenchPresentationTests {
  @Test("manual motion uses explicit units and one capability-bound Stop")
  func manualMotionLabelsAndStop() {
    let capability = PlotterManualMotionStopCapabilityID(
      rawValue: UUID(uuidString: "00000000-0000-0000-0000-000000000301")!
    )
    let presentation = ManualMotionPresentation(
      stopAction: ManualMotionStopActionPresentation(
        capabilityID: capability,
        title: "Stop Manual Jog",
        detail: "Stop this manual jog and wait for Idle."
      ),
      publicationRecovery: nil,
      evidenceDisposition: nil,
      jogUnavailableReason: "A relative jog is already in progress.",
      penUpUnavailableReason: nil,
      penDownUnavailableReason: nil,
      penStateText: "commanded up — not visually observed",
      modeText: "travel — commanded Pen Up",
      recordingDiagnostic: nil
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
      publicationRecovery: nil,
      evidenceDisposition: nil,
      jogUnavailableReason: nil,
      penUpUnavailableReason: nil,
      penDownUnavailableReason: nil,
      penStateText: presentation.penStateText,
      modeText: presentation.modeText,
      recordingDiagnostic: nil
    )
    #expect(
      derivedDisable.jogControlsUnavailableReason
        == "Stop the active manual jog before starting another."
    )
  }

  @Test("publication recovery carries one exact capability and disables every manual effect")
  func manualPublicationRecovery() {
    let capability = PlotterManualMotionPublicationRecoveryCapabilityID(
      rawValue: UUID(uuidString: "00000000-0000-0000-0000-000000000302")!
    )
    let remedy =
      "The Pen Down terminal result was not durably published. Retry this exact publication; the Pen command will not be issued again."
    let presentation = ManualMotionPresentation(
      stopAction: nil,
      publicationRecovery: ManualMotionPublicationRecoveryPresentation(
        capabilityID: capability,
        title: "Retry Pen Down Publication",
        remedy: remedy
      ),
      evidenceDisposition: nil,
      jogUnavailableReason: remedy,
      penUpUnavailableReason: remedy,
      penDownUnavailableReason: remedy,
      penStateText: "commanded down — not visually observed",
      modeText: "drawing — commanded Pen Down",
      recordingDiagnostic: nil
    )

    #expect(presentation.publicationRecovery?.capabilityID == capability)
    #expect(presentation.publicationPendingReason == remedy)
    #expect(presentation.jogControlsUnavailableReason == remedy)
    #expect(presentation.penUpUnavailableReason == remedy)
    #expect(presentation.penDownUnavailableReason == remedy)
    #expect(!presentation.isStoppable)
  }

  @Test("ambiguity disposition carries one exact typed action and disables every effect")
  func manualEvidenceDisposition() {
    let action = PlotterManualMotionEvidenceDispositionAction(
      effectID: EpisodeEffectID(rawValue: UUID()),
      environment: .live,
      observationID: PlotterObservationID(rawValue: UUID()),
      disposition: .acknowledgePossibleInk,
      summary: "Controller settlement was ambiguous."
    )
    let remedy =
      "Review the exact observation and acknowledge possible ink without reissuing work."
    let presentation = ManualMotionPresentation(
      stopAction: nil,
      publicationRecovery: nil,
      evidenceDisposition: ManualMotionEvidenceDispositionPresentation(
        action: action,
        title: "Acknowledge Possible Ink",
        remedy: remedy
      ),
      jogUnavailableReason: remedy,
      penUpUnavailableReason: remedy,
      penDownUnavailableReason: remedy,
      penStateText: "commanded down — not visually observed",
      modeText: "drawing — commanded Pen Down",
      recordingDiagnostic: nil
    )

    #expect(presentation.evidenceDisposition?.action == action)
    #expect(presentation.evidencePendingReason == remedy)
    #expect(presentation.attentionReason == remedy)
    #expect(presentation.jogControlsUnavailableReason == remedy)
    #expect(presentation.penUpUnavailableReason == remedy)
    #expect(presentation.penDownUnavailableReason == remedy)
    #expect(!presentation.isStoppable)
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

  @Test("active runtime action strip can keep its sole controls visible")
  func activeExerciseControlsRemainVisible() {
    let active = ExerciseActionStripPresentation(
      ownerID: .humanGuidedDiscovery(.calibratePenContactFromSparseMarks),
      actions: [
        ExerciseActionDescriptor(
          kind: .tipCalibration(.retryCommit),
          title: "Retry Calibration Commit"
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
      ownerID: .borderValidation(.chooseDrawingBorderPlan),
      actions: [
        ExerciseActionDescriptor(kind: .start, title: "Start", role: .positive)
      ]
    )

    #expect(active.mustRemainVisible)
    #expect(!idle.mustRemainVisible)
  }

  @Test("exact evidence remains structured alongside actor action outcome and recovery")
  func operationAndEvidenceProjection() {
    let activity = OperationActivityPresentation(
      actor: "Operator",
      action: "Reveal and Observe New Ink",
      outcome: .needsAttention,
      detail: [.text("Ink may exist after accepted Pen Down.")],
      recovery: [.text("Return to the local reveal pose and observe; do not redraw.")]
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
    #expect(activity.action == "Reveal and Observe New Ink")
    #expect(activity.outcome == .needsAttention)
    #expect(activity.recovery.accessibilityText.contains("do not redraw"))
    #expect(evidence.label == "Exact frames")
    #expect(evidence.fragments.accessibilityText.contains("frame-44 and frame-45"))
  }

}
