import CoreGraphics
import Testing

@testable import PlotterApp

@Suite("Camera-first workbench layout")
struct WorkbenchLayoutTests {
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
    #expect(layout.zIndex(for: .overlays) > layout.zIndex(for: .motion))

    layout.bringToFront(.motion)
    #expect(layout.zIndex(for: .motion) > layout.zIndex(for: .overlays))

    layout.hideAll()
    #expect(WorkbenchPanel.allCases.allSatisfy { !layout[$0].isVisible })
    #expect(layout[.motion].isCollapsed)
  }

  @Test("dragging clamps a panel center to the usable camera surface")
  func dragClamping() {
    var layout = WorkbenchLayoutState()
    let container = CGSize(width: 1_200, height: 760)
    let panel = CGSize(width: 390, height: 520)
    let initial = layout[.motion]

    layout.move(
      .motion,
      from: initial,
      translation: CGSize(width: -10_000, height: -10_000),
      in: container,
      panelSize: panel,
      topInset: 72
    )
    #expect(
      layout.center(
        for: .motion,
        in: container,
        panelSize: panel,
        topInset: 72
      ) == CGPoint(x: 195, y: 332)
    )

    let secondStart = layout[.motion]
    layout.move(
      .motion,
      from: secondStart,
      translation: CGSize(width: 10_000, height: 10_000),
      in: container,
      panelSize: panel,
      topInset: 72
    )
    #expect(
      layout.center(
        for: .motion,
        in: container,
        panelSize: panel,
        topInset: 72
      ) == CGPoint(x: 1_005, y: 500)
    )
  }
}
