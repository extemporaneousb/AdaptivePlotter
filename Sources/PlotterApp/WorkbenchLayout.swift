import Foundation

enum WorkbenchPanel: String, CaseIterable, Identifiable, Sendable {
  case motion = "Motion"
  case camera = "Camera"
  case overlays = "Overlays"
  case learning = "Learning"
  case controller = "Controller"

  var id: Self { self }

  var systemImage: String {
    switch self {
    case .motion: "move.3d"
    case .camera: "camera"
    case .overlays: "square.3.layers.3d"
    case .learning: "chart.xyaxis.line"
    case .controller: "cable.connector"
    }
  }

  var preferredSize: CGSize {
    switch self {
    case .motion: CGSize(width: 390, height: 520)
    case .camera: CGSize(width: 390, height: 530)
    case .overlays: CGSize(width: 330, height: 410)
    case .learning: CGSize(width: 410, height: 510)
    case .controller: CGSize(width: 370, height: 500)
    }
  }
}

struct WorkbenchPanelPresentation: Equatable, Sendable {
  var isVisible: Bool
  var isCollapsed: Bool
  /// A normalized center within the usable camera surface, independently
  /// clamped for the current window and panel dimensions.
  var normalizedX: Double
  var normalizedY: Double
}

struct WorkbenchLayoutState: Equatable, Sendable {
  private var panels: [WorkbenchPanel: WorkbenchPanelPresentation]
  private var panelOrder: [WorkbenchPanel]

  init() {
    panelOrder = WorkbenchPanel.allCases
    panels = [
      .motion: .init(isVisible: false, isCollapsed: false, normalizedX: 0.12, normalizedY: 0.55),
      .camera: .init(isVisible: false, isCollapsed: false, normalizedX: 0.88, normalizedY: 0.42),
      .overlays: .init(isVisible: false, isCollapsed: false, normalizedX: 0.86, normalizedY: 0.78),
      .learning: .init(isVisible: false, isCollapsed: false, normalizedX: 0.58, normalizedY: 0.66),
      .controller: .init(isVisible: false, isCollapsed: false, normalizedX: 0.18, normalizedY: 0.32),
    ]
  }

  subscript(panel: WorkbenchPanel) -> WorkbenchPanelPresentation {
    get {
      panels[panel]
        ?? WorkbenchPanelPresentation(
          isVisible: false,
          isCollapsed: false,
          normalizedX: 0.5,
          normalizedY: 0.5
        )
    }
    set { panels[panel] = newValue }
  }

  mutating func toggleVisibility(_ panel: WorkbenchPanel) {
    var value = self[panel]
    value.isVisible.toggle()
    panels[panel] = value
    if value.isVisible { bringToFront(panel) }
  }

  mutating func hide(_ panel: WorkbenchPanel) {
    var value = self[panel]
    value.isVisible = false
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

  mutating func bringToFront(_ panel: WorkbenchPanel) {
    panelOrder.removeAll { $0 == panel }
    panelOrder.append(panel)
  }

  func zIndex(for panel: WorkbenchPanel) -> Double {
    Double(panelOrder.firstIndex(of: panel) ?? 0)
  }

  mutating func move(
    _ panel: WorkbenchPanel,
    from initial: WorkbenchPanelPresentation,
    translation: CGSize,
    in containerSize: CGSize,
    panelSize: CGSize,
    topInset: CGFloat
  ) {
    let initialCenter = Self.center(
      for: initial,
      in: containerSize,
      panelSize: panelSize,
      topInset: topInset
    )
    var value = self[panel]
    value.normalizedX = Self.normalized(
      initialCenter.x + translation.width,
      minimum: panelSize.width / 2,
      maximum: containerSize.width - panelSize.width / 2
    )
    value.normalizedY = Self.normalized(
      initialCenter.y + translation.height,
      minimum: topInset + panelSize.height / 2,
      maximum: containerSize.height - panelSize.height / 2
    )
    panels[panel] = value
  }

  func center(
    for panel: WorkbenchPanel,
    in containerSize: CGSize,
    panelSize: CGSize,
    topInset: CGFloat
  ) -> CGPoint {
    Self.center(
      for: self[panel],
      in: containerSize,
      panelSize: panelSize,
      topInset: topInset
    )
  }

  private static func center(
    for value: WorkbenchPanelPresentation,
    in containerSize: CGSize,
    panelSize: CGSize,
    topInset: CGFloat
  ) -> CGPoint {
    let minimumX = panelSize.width / 2
    let maximumX = max(minimumX, containerSize.width - panelSize.width / 2)
    let minimumY = topInset + panelSize.height / 2
    let maximumY = max(minimumY, containerSize.height - panelSize.height / 2)
    return CGPoint(
      x: interpolate(value.normalizedX, minimum: minimumX, maximum: maximumX),
      y: interpolate(value.normalizedY, minimum: minimumY, maximum: maximumY)
    )
  }

  private static func normalized(
    _ value: CGFloat,
    minimum: CGFloat,
    maximum: CGFloat
  ) -> Double {
    guard maximum > minimum else { return 0.5 }
    return min(1, max(0, Double((value - minimum) / (maximum - minimum))))
  }

  private static func interpolate(
    _ normalized: Double,
    minimum: CGFloat,
    maximum: CGFloat
  ) -> CGFloat {
    let bounded = min(1, max(0, normalized))
    return minimum + CGFloat(bounded) * (maximum - minimum)
  }
}
