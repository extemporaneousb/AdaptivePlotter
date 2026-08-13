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

  @Test("Video Settings is reachable at the supported window width by yielding a side pane")
  func videoSettingsMinimumWidth() {
    let videoSettingsPolicy = VideoSettingsVisibilityPolicy()
    let presentation = videoSettingsPolicy.presentation(
      isPresented: false,
      availableWindowWidth: LearningWorkbenchLayoutPolicy.minimumWindowWidth
    )

    #expect(presentation.action == .show)
    #expect(presentation.actionTitle == "Show Video Settings")
    #expect(presentation.isActionEnabled)
    #expect(
      videoSettingsPolicy.transition(
        isPresented: false,
        action: .show,
        availableWindowWidth: LearningWorkbenchLayoutPolicy.minimumWindowWidth
      )
    )

    let prepared = videoSettingsPolicy.preparingPanesToShow(
      WorkbenchPaneVisibility(),
      availableWindowWidth: LearningWorkbenchLayoutPolicy.minimumWindowWidth,
      canCollapseExerciseDetail: true
    )
    #expect(!prepared.navigatorIsPresented)
    #expect(prepared.exerciseDetailIsPresented)
    #expect(
      videoSettingsPolicy.minimumContentWidth(for: prepared)
        + videoSettingsPolicy.inspectorWidth + videoSettingsPolicy.inspectorSeparation
        <= LearningWorkbenchLayoutPolicy.minimumWindowWidth
    )
  }

  @Test("Video Settings Show and Hide are deterministic and idempotent")
  func videoSettingsTransitions() {
    let videoSettingsPolicy = VideoSettingsVisibilityPolicy()
    let wideWidth = videoSettingsPolicy.minimumWidthToShow

    #expect(
      videoSettingsPolicy.transition(
        isPresented: false,
        action: .show,
        availableWindowWidth: wideWidth
      )
    )
    #expect(
      videoSettingsPolicy.transition(
        isPresented: true,
        action: .show,
        availableWindowWidth: 0
      )
    )
    #expect(
      !videoSettingsPolicy.transition(
        isPresented: true,
        action: .hide,
        availableWindowWidth: 0
      )
    )
    #expect(
      !videoSettingsPolicy.transition(
        isPresented: false,
        action: .hide,
        availableWindowWidth: wideWidth
      )
    )

    let shown = videoSettingsPolicy.presentation(
      isPresented: true,
      availableWindowWidth: LearningWorkbenchLayoutPolicy.minimumWindowWidth
    )
    #expect(shown.action == .hide)
    #expect(shown.actionTitle == "Hide Video Settings")
    #expect(shown.isActionEnabled)
  }

  @Test("presented Video Settings collapses before the protected workbench is starved")
  func videoSettingsCollapse() {
    let videoSettingsPolicy = VideoSettingsVisibilityPolicy()
    let panes = WorkbenchPaneVisibility(navigatorIsPresented: false)
    let minimum = videoSettingsPolicy.minimumContentWidth(for: panes)
    let collapsesAtMinimum = videoSettingsPolicy.shouldCollapsePresentedVideoSettings(
      availableContentWidth: minimum,
      panes: panes
    )
    let collapsesBelowMinimum = videoSettingsPolicy.shouldCollapsePresentedVideoSettings(
      availableContentWidth: minimum - 1,
      panes: panes
    )

    #expect(!collapsesAtMinimum)
    #expect(collapsesBelowMinimum)
  }

  @Test("Video Settings does not hide an action-owning exercise pane")
  func videoSettingsPreservesActiveExerciseControls() {
    let videoSettingsPolicy = VideoSettingsVisibilityPolicy()
    let prepared = videoSettingsPolicy.preparingPanesToShow(
      WorkbenchPaneVisibility(),
      availableWindowWidth: 1_200,
      canCollapseExerciseDetail: false
    )

    #expect(!prepared.navigatorIsPresented)
    #expect(prepared.exerciseDetailIsPresented)
  }
}
