import CoreGraphics
import Foundation

enum LearningWorkbenchLayoutPolicy {
  static let minimumWindowWidth: CGFloat = 1_480
  static let minimumActionSurfaceWidth: CGFloat = 640
  static let minimumActionSurfaceHeight: CGFloat = 480
  static let minimumLearningExerciseWidth: CGFloat = 480
  static let idealLearningExerciseWidth: CGFloat = 580
  static let maximumLearningExerciseWidth: CGFloat = 760
  static let learningPathRailWidth: CGFloat = 188
}

enum WorkbenchInspectorLayoutPolicy {
  static let minimumInspectorWidth: CGFloat = 280
  static let idealInspectorWidth: CGFloat = 360
  static let maximumInspectorWidth: CGFloat = 440
}

/// Keeps workflow action titles readable in the pinned exercise pane. The
/// grid gives up a column before compressing a button below this width; labels
/// then grow vertically instead of being truncated.
enum ExerciseActionLayoutPolicy {
  static let minimumButtonWidth: CGFloat = 180
  static let minimumButtonHeight: CGFloat = 32
  static let horizontalSpacing: CGFloat = 8
}
