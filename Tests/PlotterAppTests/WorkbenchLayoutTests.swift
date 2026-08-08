import CoreGraphics
import Testing

@testable import PlotterApp

@Suite("Camera-first workbench layout")
struct WorkbenchLayoutTests {
  @Test("revealing a panel makes it visible and expanded")
  func revealMakesPanelVisibleAndExpanded() {
    var layout = WorkbenchLayoutState()
    layout.toggleCollapsed(.motion)

    layout.reveal(.motion)

    #expect(layout[.motion].isVisible)
    #expect(!layout[.motion].isCollapsed)
  }

  @Test("all detailed panels begin hidden and remain independently toggleable")
  func visibility() {
    var layout = WorkbenchLayoutState()
    #expect(WorkbenchPanel.allCases.allSatisfy { !layout[$0].isVisible })

    layout.toggleVisibility(.motion)
    layout.toggleVisibility(.overlays)
    layout.toggleCollapsed(.motion)
    #expect(layout[.motion].isVisible)
    #expect(layout[.motion].isCollapsed)
    #expect(layout[.overlays].isVisible)
    #expect(!layout[.camera].isVisible)

    layout.hideAll()
    #expect(WorkbenchPanel.allCases.allSatisfy { !layout[$0].isVisible })
    #expect(layout[.motion].isCollapsed)
  }

  @Test("panels use deterministic machine-left and vision-right docks")
  func deterministicDockAllocation() {
    var layout = WorkbenchLayoutState()
    layout.toggleVisibility(.learning)
    layout.toggleVisibility(.camera)
    layout.toggleVisibility(.motion)
    layout.toggleVisibility(.overlays)

    #expect(layout.visiblePanels(in: .left) == [.motion])
    #expect(layout.visiblePanels(in: .right) == [.camera, .overlays, .learning])
  }

  @Test("no visible panels gives the entire content area to the action surface")
  func unobstructedDefaultSurface() {
    let layout = WorkbenchLayoutState()
    let geometry = layout.geometry(
      in: CGSize(width: 1_200, height: 760),
      topInset: 64
    )

    #expect(geometry.contentBounds == CGRect(x: 0, y: 64, width: 1_200, height: 696))
    #expect(geometry.leftDock == nil)
    #expect(geometry.rightDock == nil)
    #expect(geometry.actionSurface == geometry.contentBounds)
  }

  @Test("one visible dock reserves space instead of covering the camera")
  func oneDockReservesSpace() {
    var layout = WorkbenchLayoutState()
    layout.toggleVisibility(.motion)

    let geometry = layout.geometry(
      in: CGSize(width: 1_200, height: 760),
      topInset: 64,
      preferredDockWidth: 360,
      spacing: 10,
      minimumActionSurfaceWidth: 360
    )

    #expect(geometry.leftDock == CGRect(x: 0, y: 64, width: 360, height: 696))
    #expect(geometry.actionSurface == CGRect(x: 370, y: 64, width: 830, height: 696))
    #expect(geometry.rightDock == nil)
    #expect(geometry.leftDock?.intersects(geometry.actionSurface) == false)
  }

  @Test("both docks reserve one shared rail per side and never overlay the action surface")
  func bothDocksNeverOverlay() {
    var layout = WorkbenchLayoutState()
    layout.toggleVisibility(.motion)
    layout.toggleVisibility(.camera)
    layout.toggleVisibility(.overlays)
    layout.toggleVisibility(.learning)

    let geometry = layout.geometry(
      in: CGSize(width: 1_200, height: 760),
      topInset: 64,
      preferredDockWidth: 360,
      spacing: 10,
      minimumActionSurfaceWidth: 360
    )

    #expect(geometry.leftDock == CGRect(x: 0, y: 64, width: 360, height: 696))
    #expect(geometry.actionSurface == CGRect(x: 370, y: 64, width: 460, height: 696))
    #expect(geometry.rightDock == CGRect(x: 840, y: 64, width: 360, height: 696))
    #expect(geometry.leftDock?.intersects(geometry.actionSurface) == false)
    #expect(geometry.rightDock?.intersects(geometry.actionSurface) == false)
    #expect(geometry.leftDock?.intersects(geometry.rightDock!) == false)
  }

  @Test("docks shrink symmetrically to preserve a camera-safe minimum")
  func narrowGeometryPreservesActionSurface() {
    var layout = WorkbenchLayoutState()
    layout.toggleVisibility(.motion)
    layout.toggleVisibility(.camera)

    let geometry = layout.geometry(
      in: CGSize(width: 900, height: 700),
      preferredDockWidth: 360,
      spacing: 10,
      minimumActionSurfaceWidth: 360
    )

    #expect(geometry.leftDock?.width == 260)
    #expect(geometry.rightDock?.width == 260)
    #expect(geometry.actionSurface.width == 360)
    #expect(geometry.leftDock?.maxX == 260)
    #expect(geometry.actionSurface.minX == 270)
    #expect(geometry.actionSurface.maxX == 630)
    #expect(geometry.rightDock?.minX == 640)
  }

  @Test("invalid dimensions stay bounded without overlapping regions")
  func invalidDimensionsAreBounded() {
    var layout = WorkbenchLayoutState()
    layout.toggleVisibility(.motion)
    layout.toggleVisibility(.camera)

    let geometry = layout.geometry(
      in: CGSize(width: CGFloat.nan, height: -20),
      topInset: CGFloat.infinity,
      preferredDockWidth: CGFloat.infinity,
      spacing: -CGFloat.infinity,
      minimumActionSurfaceWidth: CGFloat.nan
    )

    #expect(geometry.contentBounds == .zero)
    #expect(geometry.leftDock == .zero)
    #expect(geometry.actionSurface == .zero)
    #expect(geometry.rightDock == .zero)
  }
}
