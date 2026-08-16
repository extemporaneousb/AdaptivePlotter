import Foundation
import PlotterRuntime
import Testing

@testable import PlotterApp

struct OperatorButtonGrammarTests {
  @Test("enabled roles have one distinct semantic chrome")
  func enabledRolesHaveDistinctSemanticChrome() {
    #expect(OperatorButtonRole.commit.chrome(isEnabled: true) == .commit)
    #expect(OperatorButtonRole.interrupt.chrome(isEnabled: true) == .interrupt)
    #expect(OperatorButtonRole.editValue.chrome(isEnabled: true) == .editValue)
    #expect(OperatorButtonRole.utility.chrome(isEnabled: true) == .utility)
  }

  @Test("disabled state always owns dark noninteractive chrome")
  func everyDisabledRoleUsesTheSameChrome() {
    for role in OperatorButtonRole.allCases {
      #expect(role.chrome(isEnabled: false) == .disabled)
    }
  }

  @Test("every exercise action derives its role from its typed effect")
  func exhaustiveActionEffects() {
    let capability = ContextualStopCapabilityID(
      rawValue: UUID(uuidString: "00000000-0000-0000-0000-000000000101")!
    )
    let cases: [(ExerciseActionKind, ExerciseActionEffect)] = [
      (.start, .commit),
      (.choice(.yes), .commit),
      (.choice(.no), .interrupt),
      (.setPenSetpoint(.raise, 400), .editValue),
      (.stopAndAcceptBoundary(capability), .commit),
      (.stop(capability), .interrupt),
      (.cancel(capability), .interrupt),
      (.restart, .commit),
      (.redoThisStep, .commit),
      (.recordAnotherAttempt, .commit),
      (.redoBoundary(.positiveX), .commit),
      (.recordAnotherBoundaryAttempt(.positiveX), .commit),
      (.selectDirection(.boundary, .positiveX), .editValue),
      (.moveToEstimatedCenter, .commit),
      (.runCameraCalibrationAndBuildProposal, .commit),
      (.acceptCameraCalibrationProposal, .commit),
      (.rejectCameraCalibrationProposal, .interrupt),
      (.createNextSparseTipMark, .commit),
      (.reClickSparseTipFrame, .editValue),
      (.acceptSparseTipMark, .commit),
      (.revalidateTipCalibrationCheckpoint, .commit),
      (.acceptTipCalibration, .commit),
      (.rejectTipCalibration, .interrupt),
      (.paperReplaced, .interrupt),
      (.chooseIsolatedLinePlan(.positiveX), .commit),
      (.captureLocalPreLineBaseline, .commit),
      (.moveToLineStart, .commit),
      (.drawIsolatedLine, .commit),
      (.revealAndObserveNewInk, .commit),
      (.recordDrawingTrialAssessment(.observedGeometryAccepted), .commit),
      (.recordDrawingTrialAssessment(.inkOrGeometryUnclear), .commit),
    ]

    for (kind, effect) in cases {
      let action = ExerciseActionDescriptor(kind: kind, title: "Action")
      #expect(action.effect == effect)
      #expect(action.buttonRole == effect.buttonRole)
    }
  }

  @Test("Escape belongs only to Stop and no exercise action is implicit default")
  func boundaryShortcutGrammar() {
    let capability = ContextualStopCapabilityID(
      rawValue: UUID(uuidString: "00000000-0000-0000-0000-000000000102")!
    )
    let accept = ExerciseActionDescriptor(
      kind: .stopAndAcceptBoundary(capability),
      title: "Stop & Accept"
    )
    let stop = ExerciseActionDescriptor(kind: .stop(capability), title: "Stop")
    let cancel = ExerciseActionDescriptor(kind: .cancel(capability), title: "Cancel")

    #expect(accept.keyboardShortcut == nil)
    #expect(stop.keyboardShortcut == .escape)
    #expect(cancel.keyboardShortcut == nil)
    #expect(!accept.isDefaultAction)
    #expect(!stop.isDefaultAction)
    #expect(!cancel.isDefaultAction)
  }

  @Test("unavailable actions cannot retain enabled chrome")
  func unavailableActionUsesDisabledChrome() {
    let unavailable = ExerciseActionDescriptor(
      kind: .start,
      title: "Start",
      unavailableReason: "Controller unavailable."
    )

    #expect(!unavailable.isEnabled)
    #expect(unavailable.buttonRole.chrome(isEnabled: unavailable.isEnabled) == .disabled)
  }
}
