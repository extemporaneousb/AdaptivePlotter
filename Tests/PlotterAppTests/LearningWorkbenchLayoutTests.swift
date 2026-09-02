import Foundation
import PlotterEpisodeModel
import SwiftUI
import Testing

@testable import PlotterApp

@Suite("Learning workbench layout policy")
struct LearningWorkbenchLayoutTests {
  @Test("all four panel toggles have consistent state-dependent titles")
  func panelActionTitles() {
    #expect(WorkbenchPanel.allCases.count == 4)
    #expect(
      WorkbenchPanel.allCases.map { $0.actionTitle(isPresented: false) }
        == ["Show Learning Path", "Show Motion", "Show Exercise", "Show Video Settings"]
    )
    #expect(
      WorkbenchPanel.allCases.map { $0.actionTitle(isPresented: true) }
        == ["Hide Learning Path", "Hide Motion", "Hide Exercise", "Hide Video Settings"]
    )
  }

  @Test("exercise actions preserve readable button widths across pane sizes")
  func readableExerciseActionWidths() {
    #expect(ExerciseActionLayoutPolicy.minimumButtonWidth == 180)
    #expect(ExerciseActionLayoutPolicy.maximumColumnCount(availableWidth: 300) == 1)
    #expect(ExerciseActionLayoutPolicy.maximumColumnCount(availableWidth: 500) == 2)
    #expect(ExerciseActionLayoutPolicy.maximumColumnCount(availableWidth: 600) == 3)
    #expect(ExerciseActionLayoutPolicy.maximumColumnCount(availableWidth: .infinity) == 1)
  }

  @Test("all non-camera panes collapse and restore independently")
  func paneVisibility() {
    let initial = WorkbenchPaneVisibility()
    let navigatorHidden = initial.toggling(.navigator)
    let motionHidden = navigatorHidden.toggling(.motion)
    let detailHidden = motionHidden.toggling(.exerciseDetail)

    #expect(!navigatorHidden.navigatorIsPresented)
    #expect(navigatorHidden.motionIsPresented)
    #expect(!motionHidden.motionIsPresented)
    #expect(!detailHidden.exerciseDetailIsPresented)
    #expect(detailHidden.toggling(.navigator).navigatorIsPresented)
    #expect(detailHidden.toggling(.motion).motionIsPresented)
    #expect(detailHidden.toggling(.exerciseDetail).exerciseDetailIsPresented)
  }

  @Test("Video Settings is reachable at the supported width by collapsing the navigator")
  func videoSettingsMinimumWidth() {
    let videoSettingsPolicy = VideoSettingsVisibilityPolicy()
    let layout = WorkbenchLayoutState()
    let presentation = videoSettingsPolicy.presentation(
      layout: layout,
      availableWindowWidth: LearningWorkbenchLayoutPolicy.minimumWindowWidth,
      exerciseDetailMustRemainVisible: false
    )

    #expect(presentation.action == .show)
    #expect(presentation.actionTitle == "Show Video Settings")
    #expect(presentation.isActionEnabled)
    guard
      let transitioned = videoSettingsPolicy.transition(
        from: layout,
        action: .show,
        availableWindowWidth: LearningWorkbenchLayoutPolicy.minimumWindowWidth,
        exerciseDetailMustRemainVisible: false
      )
    else {
      Issue.record("Supported window width refused Video Settings")
      return
    }

    #expect(transitioned.videoSettingsIsPresented)
    #expect(!transitioned.panes.navigatorIsPresented)
    #expect(transitioned.panes.exerciseDetailIsPresented)
    #expect(
      videoSettingsPolicy.minimumContentWidth(for: transitioned.panes)
        + videoSettingsPolicy.inspectorWidth + videoSettingsPolicy.inspectorSeparation
        <= LearningWorkbenchLayoutPolicy.minimumWindowWidth
    )
  }

  @Test("Video Settings Show and Hide are deterministic and idempotent")
  func videoSettingsTransitions() {
    let videoSettingsPolicy = VideoSettingsVisibilityPolicy()
    let wideWidth = videoSettingsPolicy.minimumWidthToShow
    let hidden = WorkbenchLayoutState()

    guard
      let shown = videoSettingsPolicy.transition(
        from: hidden,
        action: .show,
        availableWindowWidth: wideWidth,
        exerciseDetailMustRemainVisible: false
      )
    else {
      Issue.record("Minimum supported width refused Video Settings")
      return
    }
    #expect(shown.videoSettingsIsPresented)
    #expect(
      videoSettingsPolicy.transition(
        from: shown,
        action: .show,
        availableWindowWidth: 0,
        exerciseDetailMustRemainVisible: false
      ) == shown
    )
    #expect(
      videoSettingsPolicy.transition(
        from: shown,
        action: .hide,
        availableWindowWidth: 0,
        exerciseDetailMustRemainVisible: false
      ) == shown.hidingVideoSettings()
    )
    #expect(
      videoSettingsPolicy.transition(
        from: hidden,
        action: .hide,
        availableWindowWidth: wideWidth,
        exerciseDetailMustRemainVisible: false
      ) == hidden
    )

    let shownPresentation = videoSettingsPolicy.presentation(
      layout: shown,
      availableWindowWidth: LearningWorkbenchLayoutPolicy.minimumWindowWidth,
      exerciseDetailMustRemainVisible: false
    )
    #expect(shownPresentation.action == .hide)
    #expect(shownPresentation.actionTitle == "Hide Video Settings")
    #expect(shownPresentation.isActionEnabled)
  }

  @Test("Video Settings diagnostics pull occurs only on hidden-to-presented transition")
  func videoSettingsDiagnosticsPullDisposition() throws {
    let policy = VideoSettingsVisibilityPolicy()
    let hidden = WorkbenchLayoutState()
    let width = policy.minimumWidthToShow
    let shown = try #require(
      videoSettingsOperatorActionDisposition(
        from: hidden,
        action: .show,
        availableWindowWidth: width,
        exerciseDetailMustRemainVisible: false,
        policy: policy
      )
    )
    let repeatedShow = try #require(
      videoSettingsOperatorActionDisposition(
        from: shown.layout,
        action: .show,
        availableWindowWidth: width,
        exerciseDetailMustRemainVisible: false,
        policy: policy
      )
    )
    let hiddenAgain = try #require(
      videoSettingsOperatorActionDisposition(
        from: shown.layout,
        action: .hide,
        availableWindowWidth: width,
        exerciseDetailMustRemainVisible: false,
        policy: policy
      )
    )

    #expect(shown.layout.videoSettingsIsPresented)
    #expect(shown.shouldRefreshDiagnostics)
    #expect(repeatedShow.layout == shown.layout)
    #expect(!repeatedShow.shouldRefreshDiagnostics)
    #expect(!hiddenAgain.layout.videoSettingsIsPresented)
    #expect(!hiddenAgain.shouldRefreshDiagnostics)
  }

  @Test("Video Settings Show is atomic while exact active Stop capability remains stable")
  func videoSettingsShowDoesNotAwaitMotionSettlement() {
    let policy = VideoSettingsVisibilityPolicy()
    let capability = ContextualStopCapabilityID(
      rawValue: UUID(uuidString: "00000000-0000-0000-0000-000000000401")!
    )
    let heldMotionStop = ContextualStopPresentation(
      capabilityID: capability,
      title: "Stop Calibration Batch",
      detail: "Stop the active supervised move and wait for settlement."
    )
    let protection = ExercisePaneProtectionPresentation(mustRemainVisible: true)
    let initial = WorkbenchLayoutState()

    guard
      let shown = policy.transition(
        from: initial,
        action: .show,
        availableWindowWidth: LearningWorkbenchLayoutPolicy.minimumWindowWidth,
        exerciseDetailMustRemainVisible: protection.mustRemainVisible
      )
    else {
      Issue.record("A fitting protected Exercise layout refused Video Settings")
      return
    }

    #expect(shown.videoSettingsIsPresented)
    #expect(shown.panes.exerciseDetailIsPresented)
    #expect(heldMotionStop.capabilityID == capability)
  }

  @Test("presented Video Settings collapses before the protected workbench is starved")
  func videoSettingsCollapse() {
    let videoSettingsPolicy = VideoSettingsVisibilityPolicy()
    let panes = WorkbenchPaneVisibility(navigatorIsPresented: false)
    let minimum = videoSettingsPolicy.minimumContentWidth(for: panes)
    let shown = WorkbenchLayoutState(panes: panes, videoSettingsIsPresented: true)
    let retainedAtMinimum = shown.collapsingVideoSettingsIfNeeded(
      availableContentWidth: minimum,
      policy: videoSettingsPolicy
    )
    let collapsedBelowMinimum = shown.collapsingVideoSettingsIfNeeded(
      availableContentWidth: minimum - 1,
      policy: videoSettingsPolicy
    )

    #expect(retainedAtMinimum.videoSettingsIsPresented)
    #expect(!collapsedBelowMinimum.videoSettingsIsPresented)
    #expect(collapsedBelowMinimum.panes == panes)
  }

  @Test("protected narrow layout refuses Video Settings before acceptance")
  func videoSettingsRefusesProtectedNarrowLayout() {
    let videoSettingsPolicy = VideoSettingsVisibilityPolicy()
    let layout = WorkbenchLayoutState()
    let presentation = videoSettingsPolicy.presentation(
      layout: layout,
      availableWindowWidth: 1_200,
      exerciseDetailMustRemainVisible: true
    )

    #expect(
      presentation.unavailableReason
        == .activeExerciseRequiresWindowWidth(1_316)
    )
    #expect(
      presentation.unavailableReasonText?.contains("active Exercise controls including Stop")
        == true
    )
    #expect(!presentation.isActionEnabled)
    #expect(
      videoSettingsPolicy.transition(
        from: layout,
        action: .show,
        availableWindowWidth: 1_200,
        exerciseDetailMustRemainVisible: true
      ) == nil
    )
    #expect(layout == WorkbenchLayoutState())
  }

  @Test("unprotected Video Settings admission collapses navigator before Exercise")
  func videoSettingsUnprotectedCollapseOrder() {
    let policy = VideoSettingsVisibilityPolicy()
    let initial = WorkbenchLayoutState()
    let navigatorOnly = policy.transition(
      from: initial,
      action: .show,
      availableWindowWidth: 1_440,
      exerciseDetailMustRemainVisible: false
    )
    let bothSidePanes = policy.transition(
      from: initial,
      action: .show,
      availableWindowWidth: 1_200,
      exerciseDetailMustRemainVisible: false
    )

    #expect(navigatorOnly?.panes.navigatorIsPresented == false)
    #expect(navigatorOnly?.panes.exerciseDetailIsPresented == true)
    #expect(bothSidePanes?.panes.navigatorIsPresented == false)
    #expect(bothSidePanes?.panes.exerciseDetailIsPresented == false)
    #expect(navigatorOnly?.videoSettingsIsPresented == true)
    #expect(bothSidePanes?.videoSettingsIsPresented == true)
  }

  @Test("navigator and detail receive the same single root Learning projection")
  @MainActor
  func learningProjectionHasOneRootConsumerValue() {
    let workspace = makeCausalSimulatorAppFixture().workspace
    let itemID = LearningPathItemID.humanGuidedDiscovery(.penInteraction)
    let binding = Binding.constant(LearningPathSelectionState(current: itemID))
    workspace.resetComputationDiagnosticsForTesting()
    let appProjection = workspace.testPlotterUIProjection(
      selectedItemID: itemID,
      includesLearningPath: true
    )
    let projection = appProjection.learningPath!

    let navigator = LearningPathNavigator(
      selection: binding,
      projection: projection,
      currentLearningPathItemID: appProjection.currentLearningPathItemID,
      plotterUIProjection: appProjection.semantic,
      plotterUIIntentSink: workspace,
      close: {}
    )
    let detail = LearningPathView(
      selection: binding,
      projection: projection,
      currentLearningPathItemID: appProjection.currentLearningPathItemID,
      plotterUIProjection: appProjection.semantic,
      plotterUIIntentSink: workspace,
      close: {},
      closeUnavailableReason: nil
    )

    #expect(navigator.projection == detail.projection)
    #expect(navigator.projection == projection)
    #expect(workspace.computationDiagnosticsForTesting.learningProjectionBuildCount == 1)
  }
}
