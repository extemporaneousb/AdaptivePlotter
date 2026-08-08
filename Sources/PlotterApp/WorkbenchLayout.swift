import CoreGraphics
import Foundation

enum WorkbenchDockSide: Sendable {
  case left
  case right
}

enum WorkbenchPanel: String, CaseIterable, Identifiable, Sendable {
  case motion = "Motion"
  case camera = "Camera"
  case overlays = "Overlays"
  case learningPath = "Learning Path"

  var id: Self { self }

  var dockSide: WorkbenchDockSide {
    switch self {
    case .motion:
      .left
    case .camera, .overlays, .learningPath:
      .right
    }
  }

  var systemImage: String {
    switch self {
    case .motion: "move.3d"
    case .camera: "camera"
    case .overlays: "square.3.layers.3d"
    case .learningPath: "chart.xyaxis.line"
    }
  }

  var preferredSize: CGSize {
    switch self {
    case .motion: CGSize(width: 390, height: 520)
    case .camera: CGSize(width: 390, height: 530)
    case .overlays: CGSize(width: 330, height: 410)
    case .learningPath: CGSize(width: 410, height: 510)
    }
  }
}

struct WorkbenchPanelPresentation: Equatable, Sendable {
  var isVisible: Bool
  var isCollapsed: Bool
}

/// Non-overlapping regions for the workbench content below its top bar.
///
/// A visible dock always consumes layout space. The action surface is therefore
/// reframed between the docks instead of being covered by a panel.
struct WorkbenchDockGeometry: Equatable, Sendable {
  let contentBounds: CGRect
  let leftDock: CGRect?
  let actionSurface: CGRect
  let rightDock: CGRect?

  func frame(for side: WorkbenchDockSide) -> CGRect? {
    switch side {
    case .left: leftDock
    case .right: rightDock
    }
  }
}

struct WorkbenchLayoutState: Equatable, Sendable {
  private var panels: [WorkbenchPanel: WorkbenchPanelPresentation]

  init() {
    panels = Dictionary(
      uniqueKeysWithValues: WorkbenchPanel.allCases.map {
        ($0, WorkbenchPanelPresentation(isVisible: false, isCollapsed: false))
      }
    )
  }

  subscript(panel: WorkbenchPanel) -> WorkbenchPanelPresentation {
    get {
      panels[panel]
        ?? WorkbenchPanelPresentation(isVisible: false, isCollapsed: false)
    }
    set { panels[panel] = newValue }
  }

  mutating func toggleVisibility(_ panel: WorkbenchPanel) {
    var value = self[panel]
    value.isVisible.toggle()
    panels[panel] = value
  }

  mutating func hide(_ panel: WorkbenchPanel) {
    var value = self[panel]
    value.isVisible = false
    panels[panel] = value
  }

  mutating func reveal(_ panel: WorkbenchPanel) {
    var value = self[panel]
    value.isVisible = true
    value.isCollapsed = false
    panels[panel] = value
  }

  mutating func hideAll() {
    for panel in WorkbenchPanel.allCases {
      hide(panel)
    }
  }

  mutating func toggleCollapsed(_ panel: WorkbenchPanel) {
    var value = self[panel]
    value.isCollapsed.toggle()
    panels[panel] = value
  }

  /// Stable panel order lets a dock render multiple visible panels in a single
  /// scroll container without any floating-window stacking or z-order.
  func visiblePanels(in side: WorkbenchDockSide) -> [WorkbenchPanel] {
    WorkbenchPanel.allCases.filter {
      $0.dockSide == side && self[$0].isVisible
    }
  }

  func hasVisiblePanels(in side: WorkbenchDockSide) -> Bool {
    !visiblePanels(in: side).isEmpty
  }

  /// Allocates fixed-width side docks and returns the camera-safe action region.
  /// Dock widths shrink symmetrically only when needed to preserve the requested
  /// minimum action-surface width. The caller renders each dock's panels in a
  /// vertical scroll view.
  func geometry(
    in containerSize: CGSize,
    topInset: CGFloat = 0,
    preferredDockWidth: CGFloat = 360,
    spacing: CGFloat = 10,
    minimumActionSurfaceWidth: CGFloat = 360
  ) -> WorkbenchDockGeometry {
    let width = Self.nonnegativeFinite(containerSize.width)
    let height = Self.nonnegativeFinite(containerSize.height)
    let boundedTopInset = min(Self.nonnegativeFinite(topInset), height)
    let contentBounds = CGRect(
      x: 0,
      y: boundedTopInset,
      width: width,
      height: height - boundedTopInset
    )

    let hasLeft = hasVisiblePanels(in: .left)
    let hasRight = hasVisiblePanels(in: .right)
    let dockCount = (hasLeft ? 1 : 0) + (hasRight ? 1 : 0)
    guard dockCount > 0 else {
      return WorkbenchDockGeometry(
        contentBounds: contentBounds,
        leftDock: nil,
        actionSurface: contentBounds,
        rightDock: nil
      )
    }

    let gap = Self.nonnegativeFinite(spacing)
    let totalGap = CGFloat(dockCount) * gap
    let requestedActionWidth = Self.nonnegativeFinite(minimumActionSurfaceWidth)
    let preservedActionWidth = min(requestedActionWidth, max(0, width - totalGap))
    let dockCapacity = max(0, width - totalGap - preservedActionWidth)
    let dockWidth = min(
      Self.nonnegativeFinite(preferredDockWidth),
      dockCapacity / CGFloat(dockCount)
    )

    let leftWidth = hasLeft ? dockWidth : 0
    let rightWidth = hasRight ? dockWidth : 0
    let actionMinX = leftWidth + (hasLeft ? gap : 0)
    let actionMaxX = width - rightWidth - (hasRight ? gap : 0)

    let leftDock = hasLeft
      ? CGRect(x: 0, y: boundedTopInset, width: leftWidth, height: contentBounds.height)
      : nil
    let rightDock = hasRight
      ? CGRect(
        x: width - rightWidth,
        y: boundedTopInset,
        width: rightWidth,
        height: contentBounds.height
      )
      : nil
    let actionSurface = CGRect(
      x: actionMinX,
      y: boundedTopInset,
      width: max(0, actionMaxX - actionMinX),
      height: contentBounds.height
    )

    return WorkbenchDockGeometry(
      contentBounds: contentBounds,
      leftDock: leftDock,
      actionSurface: actionSurface,
      rightDock: rightDock
    )
  }

  private static func nonnegativeFinite(_ value: CGFloat) -> CGFloat {
    guard value.isFinite else { return 0 }
    return max(0, value)
  }
}
