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
  case guidedLearning, video, motion, activeLearning, portraitStudio

  var id: String { rawValue }
  var title: String {
    switch self {
    case .guidedLearning: "Guided Learning"
    case .video: "Video"
    case .motion: "Motion"
    case .activeLearning: "Active Learning"
    case .portraitStudio: "Portrait Studio"
    }
  }
  var systemImage: String {
    switch self {
    case .guidedLearning: "graduationcap"
    case .video: "video"
    case .motion: "arrow.up.and.down.and.arrow.left.and.right"
    case .activeLearning: "chart.xyaxis.line"
    case .portraitStudio: "person.crop.rectangle"
    }
  }
  var defaultPosition: WorkbenchDock {
    switch self {
    case .guidedLearning: .left
    case .video, .portraitStudio: .right
    case .motion, .activeLearning: .bottom
    }
  }
  var isInitiallyPresented: Bool {
    self == .guidedLearning || self == .video || self == .motion
  }
}

enum WorkbenchDock: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
  case left, bottom, right
  var id: String { rawValue }
  var title: String { rawValue.capitalized }
}

/// Durable window preferences only. Moving or hiding a panel cannot close a
/// drawing draft, change the camera role, or mutate operational authority.
struct WorkbenchLayoutState: Codable, Equatable, Sendable {
  struct Placement: Codable, Equatable, Sendable {
    var position: WorkbenchDock
    var isPresented: Bool
  }

  private var placements: [WorkbenchPanel: Placement] = [:]

  func placement(of panel: WorkbenchPanel) -> Placement {
    placements[panel] ?? Placement(position: panel.defaultPosition, isPresented: panel.isInitiallyPresented)
  }
  func isPresented(_ panel: WorkbenchPanel) -> Bool { placement(of: panel).isPresented }
  func panels(in dock: WorkbenchDock) -> [WorkbenchPanel] {
    WorkbenchPanel.allCases.filter { isPresented($0) && placement(of: $0).position == dock }
  }
  var hasVisiblePanels: Bool { WorkbenchPanel.allCases.contains(where: isPresented) }

  mutating func setPresented(_ panel: WorkbenchPanel, _ presented: Bool) {
    var value = placement(of: panel)
    value.isPresented = presented
    placements[panel] = value
  }
  mutating func move(_ panel: WorkbenchPanel, to position: WorkbenchDock) {
    var value = placement(of: panel)
    value.position = position
    placements[panel] = value
  }
  static func restored(from data: Data) -> Self {
    (try? JSONDecoder().decode(Self.self, from: data)) ?? Self()
  }
  var encoded: Data { (try? JSONEncoder().encode(self)) ?? Data() }
}
