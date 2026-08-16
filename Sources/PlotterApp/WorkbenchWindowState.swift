import SwiftUI

enum InspectorSelection: Equatable, Sendable {
  case none
  case video
  case diagnostics
}

enum WorkbenchWindowSurface: Equatable, Sendable {
  case learningExercise
  case motion
  case video
  case diagnostics

  var title: String {
    switch self {
    case .learningExercise: "Learning"
    case .motion: "Motion"
    case .video: "Video Settings"
    case .diagnostics: "Diagnostics"
    }
  }

  var systemImage: String {
    switch self {
    case .learningExercise: "point.3.connected.trianglepath.dotted"
    case .motion: "move.3d"
    case .video: "video"
    case .diagnostics: "stethoscope"
    }
  }
}

/// The only mutable owner of window composition. Geometry and inspector
/// admission never write this value; every visibility change is an explicit
/// toolbar, View-menu, close, or equivalent operator action.
struct WorkbenchWindowState: Equatable, Sendable {
  var learningExerciseIsPresented = true
  var motionIsPresented = true
  var inspectorSelection = InspectorSelection.none

  func isPresented(_ surface: WorkbenchWindowSurface) -> Bool {
    return switch surface {
    case .learningExercise: learningExerciseIsPresented
    case .motion: motionIsPresented
    case .video: inspectorSelection == .video
    case .diagnostics: inspectorSelection == .diagnostics
    }
  }

  func actionTitle(for surface: WorkbenchWindowSurface) -> String {
    "\(isPresented(surface) ? "Hide" : "Show") \(surface.title)"
  }

  mutating func toggle(_ surface: WorkbenchWindowSurface) {
    switch surface {
    case .learningExercise:
      learningExerciseIsPresented.toggle()
    case .motion:
      motionIsPresented.toggle()
    case .video:
      inspectorSelection = inspectorSelection == .video ? .none : .video
    case .diagnostics:
      inspectorSelection = inspectorSelection == .diagnostics ? .none : .diagnostics
    }
  }

  mutating func closeInspector() {
    inspectorSelection = .none
  }
}

struct WorkbenchWindowCommandContext {
  let state: Binding<WorkbenchWindowState>
  let learningShowUnavailableReason: String?
  let learningHideUnavailableReason: String?
  let motionHideUnavailableReason: String?

  func unavailableReason(for surface: WorkbenchWindowSurface) -> String? {
    guard state.wrappedValue.isPresented(surface) else {
      return surface == .learningExercise ? learningShowUnavailableReason : nil
    }
    return switch surface {
    case .learningExercise: learningHideUnavailableReason
    case .motion: motionHideUnavailableReason
    case .video, .diagnostics: nil
    }
  }

  func perform(_ surface: WorkbenchWindowSurface) {
    guard unavailableReason(for: surface) == nil else { return }
    state.wrappedValue.toggle(surface)
  }
}

private struct WorkbenchWindowCommandContextKey: FocusedValueKey {
  typealias Value = WorkbenchWindowCommandContext
}

extension FocusedValues {
  var workbenchWindowCommandContext: WorkbenchWindowCommandContext? {
    get { self[WorkbenchWindowCommandContextKey.self] }
    set { self[WorkbenchWindowCommandContextKey.self] = newValue }
  }
}

struct WorkbenchViewCommands: Commands {
  @FocusedValue(\.workbenchWindowCommandContext) private var context

  var body: some Commands {
    CommandGroup(after: .sidebar) {
      Divider()
      command(.learningExercise, key: "1")
      command(.motion, key: "2")
      command(.video, key: "3")
      command(.diagnostics, key: "4")
    }
  }

  private func command(
    _ surface: WorkbenchWindowSurface,
    key: KeyEquivalent
  ) -> some View {
    Button(context?.state.wrappedValue.actionTitle(for: surface) ?? "Show \(surface.title)") {
      context?.perform(surface)
    }
    .keyboardShortcut(key, modifiers: [.command, .option])
    .disabled(context == nil || context?.unavailableReason(for: surface) != nil)
  }
}
