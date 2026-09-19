import CoreGraphics
import Foundation

enum LearningWorkbenchLayoutPolicy {
  static let minimumWindowWidth: CGFloat = 1_000
}

enum ExerciseActionLayoutPolicy {
  static let minimumButtonWidth: CGFloat = 180
  static let minimumButtonHeight: CGFloat = 32
  static let horizontalSpacing: CGFloat = 8

  static func maximumColumnCount(availableWidth: CGFloat) -> Int {
    let width = max(0, availableWidth.isFinite ? availableWidth : 0)
    return max(1, Int((width + horizontalSpacing) / (minimumButtonWidth + horizontalSpacing)))
  }
}

enum WorkbenchPanel: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
  case guidedLearning, videoSettings, motion, activeLearning, drawing, portraitStudio

  static var dockPanels: [Self] { allCases.filter { $0 != .portraitStudio } }

  var id: String { rawValue }
  var title: String {
    switch self {
    case .guidedLearning: "Guided Learning"
    case .videoSettings: "Video Settings"
    case .motion: "Motion"
    case .activeLearning: "Active Learning"
    case .drawing: "Drawing"
    case .portraitStudio: "Portrait Studio"
    }
  }
  var systemImage: String {
    switch self {
    case .guidedLearning: "graduationcap"
    case .videoSettings: "slider.horizontal.3"
    case .motion: "arrow.up.and.down.and.arrow.left.and.right"
    case .activeLearning: "chart.xyaxis.line"
    case .drawing: "pencil.and.outline"
    case .portraitStudio: "person.crop.rectangle"
    }
  }
  func actionTitle(isPresented: Bool) -> String { "\(isPresented ? "Hide" : "Show") \(title)" }
}

enum WorkbenchDock: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
  case left, right
  var id: String { rawValue }
  var title: String { rawValue.capitalized }
}

enum WorkbenchSlot: String, CaseIterable, Codable, Hashable, Sendable {
  // Declaration order is the operator's opening order.
  case right, left, rightBottom, leftBottom

  var dock: WorkbenchDock {
    switch self {
    case .right, .rightBottom: .right
    case .left, .leftBottom: .left
    }
  }
}

/// Window preferences only. The central canvas is not a member of this model.
/// Slot identity survives closing a sibling; opening a fifth replaces the oldest.
struct WorkbenchLayoutState: Codable, Equatable, Sendable {
  private var slots: [WorkbenchSlot: WorkbenchPanel] = [:]
  private var openingOrder: [WorkbenchPanel] = []
  // Optional for decoding existing v1 layouts without rewriting their dock slots.
  private var portraitWorkspace: Bool?

  init(presented: [WorkbenchPanel] = [.guidedLearning]) {
    for panel in presented { setPresented(panel, true) }
  }

  func slot(of panel: WorkbenchPanel) -> WorkbenchSlot? { slots.first { $0.value == panel }?.key }
  func isPresented(_ panel: WorkbenchPanel) -> Bool {
    panel == .portraitStudio ? portraitWorkspace == true : slot(of: panel) != nil
  }
  func panels(in dock: WorkbenchDock) -> [WorkbenchPanel] {
    WorkbenchSlot.allCases.filter { $0.dock == dock }.compactMap { slots[$0] }
  }
  var hasVisiblePanels: Bool { !slots.isEmpty || portraitWorkspace == true }

  mutating func setPresented(_ panel: WorkbenchPanel, _ presented: Bool) {
    if panel == .portraitStudio {
      portraitWorkspace = presented
      return
    }
    if !presented {
      if let slot = slot(of: panel) { slots[slot] = nil }
      openingOrder.removeAll { $0 == panel }
      return
    }
    guard !isPresented(panel) else { return }
    let destination = WorkbenchSlot.allCases.first { slots[$0] == nil }
      ?? openingOrder.first.flatMap { slot(of: $0) }
      ?? .right
    if let displaced = slots[destination] { openingOrder.removeAll { $0 == displaced } }
    slots[destination] = panel
    openingOrder.append(panel)
  }

  static func restored(from data: Data) -> Self {
    if var decoded = try? JSONDecoder().decode(Self.self, from: data),
      Set(decoded.slots.values).count == decoded.slots.count,
      Set(decoded.openingOrder) == Set(decoded.slots.values),
      decoded.openingOrder.count == decoded.slots.count {
      if let oldSlot = decoded.slot(of: .portraitStudio) {
        decoded.slots[oldSlot] = nil
        decoded.openingOrder.removeAll { $0 == .portraitStudio }
        decoded.portraitWorkspace = true
      }
      return decoded
    }
    // v1 used left/bottom/right docks and included a closable Video canvas.
    // Preserve visible controls; the old Video preference cannot hide the canvas.
    struct Legacy: Decodable {
      struct Placement: Decodable { let position: String; let isPresented: Bool }
      let placements: [String: Placement]
      init(from decoder: any Decoder) throws {
        enum Key: CodingKey { case placements }
        let container = try decoder.container(keyedBy: Key.self)
        var entries = try container.nestedUnkeyedContainer(forKey: .placements)
        var values: [String: Placement] = [:]
        while !entries.isAtEnd {
          let key = try entries.decode(String.self)
          values[key] = try entries.decode(Placement.self)
        }
        placements = values
      }
    }
    guard let legacy = try? JSONDecoder().decode(Legacy.self, from: data) else { return Self() }
    let visible = WorkbenchPanel.allCases.filter { panel in
      guard panel != .videoSettings else { return false }
      return legacy.placements[panel.rawValue]?.isPresented ?? (panel == .guidedLearning || panel == .motion)
    }
    return Self(presented: visible)
  }
  var encoded: Data { (try? JSONEncoder().encode(self)) ?? Data() }
}
