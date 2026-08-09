import CoreGraphics
import Testing

@testable import PlotterApp

@Suite("Learning workbench layout policy")
struct LearningWorkbenchLayoutTests {
  private let policy = LearningWorkbenchLayoutPolicy()

  @Test("camera is the largest region at the supported minimum window width")
  func minimumWindowWidth() {
    let allocation = policy.allocation(for: LearningWorkbenchLayoutPolicy.minimumWindowWidth)

    #expect(allocation.totalWidth == LearningWorkbenchLayoutPolicy.minimumWindowWidth)
    #expect(allocation.cameraWidth >= policy.minimumCameraWidth)
    #expect(allocation.cameraWidth > allocation.navigatorWidth)
    #expect(allocation.cameraWidth > allocation.detailWidth)
    #expect(LearningWorkbenchLayoutPolicy.minimumActionSurfaceWidth == 640)
    #expect(LearningWorkbenchLayoutPolicy.minimumActionSurfaceHeight == 480)
  }

  @Test("camera receives wide and full-screen growth")
  func wideWindow() {
    let normal = policy.allocation(for: 1_440)
    let wide = policy.allocation(for: 2_560)

    #expect(wide.navigatorWidth == normal.navigatorWidth)
    #expect(wide.detailWidth == normal.detailWidth)
    #expect(wide.cameraWidth > normal.cameraWidth)
    #expect(wide.totalWidth == 2_560)
  }

  @Test("side regions shrink before the protected camera")
  func undersizedWindow() {
    let allocation = policy.allocation(for: 1_000)

    #expect(allocation.cameraWidth == policy.minimumCameraWidth)
    #expect(allocation.navigatorWidth < policy.preferredNavigatorWidth)
    #expect(allocation.detailWidth < policy.preferredDetailWidth)
    #expect(allocation.totalWidth == 1_000)
  }

  @Test("nonfinite and negative widths remain bounded")
  func malformedWidths() {
    for width: CGFloat in [.nan, -CGFloat.infinity, -1] {
      let allocation = policy.allocation(for: width)
      #expect(allocation.totalWidth == 0)
      #expect(allocation.navigatorWidth == 0)
      #expect(allocation.cameraWidth == 0)
      #expect(allocation.detailWidth == 0)
    }
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
    #expect(
      !utilitiesPolicy.shouldCollapsePresentedUtilities(
        availableContentWidth: minimum,
        panes: panes
      )
    )
    #expect(
      utilitiesPolicy.shouldCollapsePresentedUtilities(
        availableContentWidth: minimum - 1,
        panes: panes
      )
    )
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
