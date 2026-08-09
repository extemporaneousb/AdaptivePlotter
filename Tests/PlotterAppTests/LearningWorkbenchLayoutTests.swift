import Testing

@testable import PlotterApp

@Suite("Learning workbench layout policy")
struct LearningWorkbenchLayoutTests {
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

  @Test("Utilities is reachable at the supported window width by yielding a side pane")
  func utilitiesMinimumWidth() {
    let utilitiesPolicy = UtilitiesVisibilityPolicy()
    let presentation = utilitiesPolicy.presentation(
      isPresented: false,
      availableWindowWidth: LearningWorkbenchLayoutPolicy.minimumWindowWidth
    )

    #expect(presentation.action == .show)
    #expect(presentation.actionTitle == "Show Utilities")
    #expect(presentation.isActionEnabled)
    #expect(
      utilitiesPolicy.transition(
        isPresented: false,
        action: .show,
        availableWindowWidth: LearningWorkbenchLayoutPolicy.minimumWindowWidth
      )
    )

    let prepared = utilitiesPolicy.preparingPanesToShow(
      WorkbenchPaneVisibility(),
      availableWindowWidth: LearningWorkbenchLayoutPolicy.minimumWindowWidth,
      canCollapseExerciseDetail: true
    )
    #expect(!prepared.navigatorIsPresented)
    #expect(prepared.exerciseDetailIsPresented)
    #expect(
      utilitiesPolicy.minimumContentWidth(for: prepared)
        + utilitiesPolicy.inspectorWidth + utilitiesPolicy.inspectorSeparation
        <= LearningWorkbenchLayoutPolicy.minimumWindowWidth
    )
  }

  @Test("Utilities Show and Hide are deterministic and idempotent")
  func utilitiesTransitions() {
    let utilitiesPolicy = UtilitiesVisibilityPolicy()
    let wideWidth = utilitiesPolicy.minimumWidthToShow

    #expect(
      utilitiesPolicy.transition(
        isPresented: false,
        action: .show,
        availableWindowWidth: wideWidth
      )
    )
    #expect(
      utilitiesPolicy.transition(
        isPresented: true,
        action: .show,
        availableWindowWidth: 0
      )
    )
    #expect(
      !utilitiesPolicy.transition(
        isPresented: true,
        action: .hide,
        availableWindowWidth: 0
      )
    )
    #expect(
      !utilitiesPolicy.transition(
        isPresented: false,
        action: .hide,
        availableWindowWidth: wideWidth
      )
    )

    let shown = utilitiesPolicy.presentation(
      isPresented: true,
      availableWindowWidth: LearningWorkbenchLayoutPolicy.minimumWindowWidth
    )
    #expect(shown.action == .hide)
    #expect(shown.actionTitle == "Hide Utilities")
    #expect(shown.isActionEnabled)
  }

  @Test("presented Utilities collapses before the protected workbench is starved")
  func utilitiesCollapse() {
    let utilitiesPolicy = UtilitiesVisibilityPolicy()
    let panes = WorkbenchPaneVisibility(navigatorIsPresented: false)
    let minimum = utilitiesPolicy.minimumContentWidth(for: panes)
    let collapsesAtMinimum = utilitiesPolicy.shouldCollapsePresentedUtilities(
      availableContentWidth: minimum,
      panes: panes
    )
    let collapsesBelowMinimum = utilitiesPolicy.shouldCollapsePresentedUtilities(
      availableContentWidth: minimum - 1,
      panes: panes
    )

    #expect(!collapsesAtMinimum)
    #expect(collapsesBelowMinimum)
  }

  @Test("Utilities does not hide an action-owning exercise pane")
  func utilitiesPreservesActiveExerciseControls() {
    let utilitiesPolicy = UtilitiesVisibilityPolicy()
    let prepared = utilitiesPolicy.preparingPanesToShow(
      WorkbenchPaneVisibility(),
      availableWindowWidth: 1_200,
      canCollapseExerciseDetail: false
    )

    #expect(!prepared.navigatorIsPresented)
    #expect(prepared.exerciseDetailIsPresented)
  }
}
