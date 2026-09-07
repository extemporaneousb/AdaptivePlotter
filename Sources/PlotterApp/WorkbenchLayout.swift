import CoreGraphics
import Foundation

enum LearningWorkbenchLayoutPolicy {
  static let minimumWindowWidth: CGFloat = 1_320
  static let minimumActionSurfaceWidth: CGFloat = 640
  static let minimumActionSurfaceHeight: CGFloat = 480
}

enum OverlayCardLayoutPolicy {
  static let minimumInspectorWidth: CGFloat = 280
  static let idealInspectorWidth: CGFloat = 360
  static let maximumInspectorWidth: CGFloat = 440
  static let supportedInspectorWidths = [
    minimumInspectorWidth,
    idealInspectorWidth,
    maximumInspectorWidth,
  ]
  static let minimumCardWidth: CGFloat = 248

  static func columnCount(availableWidth: CGFloat) -> Int {
    _ = availableWidth
    return 1
  }

  static func contentWidth(availableWidth: CGFloat, horizontalPadding: CGFloat = 16) -> CGFloat {
    max(0, availableWidth.isFinite ? availableWidth - horizontalPadding : 0)
  }
}

/// Keeps workflow action titles readable in the pinned exercise pane. The
/// grid gives up a column before compressing a button below this width; labels
/// then grow vertically instead of being truncated.
enum ExerciseActionLayoutPolicy {
  static let minimumButtonWidth: CGFloat = 180
  static let minimumButtonHeight: CGFloat = 32
  static let horizontalSpacing: CGFloat = 8

  static func maximumColumnCount(availableWidth: CGFloat) -> Int {
    let width = max(0, availableWidth.isFinite ? availableWidth : 0)
    return max(
      1,
      Int((width + horizontalSpacing) / (minimumButtonWidth + horizontalSpacing))
    )
  }
}

enum WorkbenchPane: Hashable, Sendable {
  case motion
  case learningPath
}

enum WorkbenchPanel: CaseIterable, Hashable, Sendable {
  case learningPath
  case motion
  case videoSettings

  var title: String {
    switch self {
    case .learningPath: "Learning Path"
    case .motion: "Motion"
    case .videoSettings: "Video Settings"
    }
  }

  var systemImage: String {
    switch self {
    case .learningPath: "sidebar.left"
    case .motion: "rectangle.bottomthird.inset.filled"
    case .videoSettings: "sidebar.trailing"
    }
  }

  func actionTitle(isPresented: Bool) -> String {
    "\(isPresented ? "Hide" : "Show") \(title)"
  }
}

/// Window-local presentation state. Hidden panes do not mutate Learning Path,
/// camera, controller, or exercise authority, and the camera is never a
/// hideable pane.
struct WorkbenchPaneVisibility: Equatable, Sendable {
  var motionIsPresented: Bool
  var learningPathIsPresented: Bool

  init(
    motionIsPresented: Bool = false,
    learningPathIsPresented: Bool = true
  ) {
    self.motionIsPresented = motionIsPresented
    self.learningPathIsPresented = learningPathIsPresented
  }

  func isPresented(_ pane: WorkbenchPane) -> Bool {
    switch pane {
    case .motion: motionIsPresented
    case .learningPath: learningPathIsPresented
    }
  }

  func toggling(_ pane: WorkbenchPane) -> WorkbenchPaneVisibility {
    var result = self
    switch pane {
    case .motion: result.motionIsPresented.toggle()
    case .learningPath: result.learningPathIsPresented.toggle()
    }
    return result
  }
}

enum VideoSettingsVisibilityAction: Hashable, Sendable {
  case show
  case hide
}

/// One atomic, window-local value for pane and inspector presentation. A Show
/// transition prepares side panes and presents Video Settings in the same
/// assignment, so it cannot wait behind unrelated main-actor work.
struct WorkbenchLayoutState: Equatable, Sendable {
  private(set) var panes: WorkbenchPaneVisibility
  private(set) var videoSettingsIsPresented: Bool

  init(
    panes: WorkbenchPaneVisibility = WorkbenchPaneVisibility(),
    videoSettingsIsPresented: Bool = false
  ) {
    self.panes = panes
    self.videoSettingsIsPresented = videoSettingsIsPresented
  }

  func toggling(_ pane: WorkbenchPane) -> Self {
    Self(
      panes: panes.toggling(pane),
      videoSettingsIsPresented: videoSettingsIsPresented
    )
  }

  func hidingVideoSettings() -> Self {
    Self(panes: panes, videoSettingsIsPresented: false)
  }

  func collapsingVideoSettingsIfNeeded(
    availableContentWidth: CGFloat,
    policy: VideoSettingsVisibilityPolicy
  ) -> Self {
    guard videoSettingsIsPresented,
      policy.shouldCollapsePresentedVideoSettings(
        availableContentWidth: availableContentWidth,
        panes: panes
      )
    else { return self }
    return hidingVideoSettings()
  }
}

enum VideoSettingsUnavailableReason: Hashable, Sendable {
  case protectedCameraRequiresWindowWidth(Int)

  var message: String {
    switch self {
    case .protectedCameraRequiresWindowWidth(let width):
      "Widen the window to at least \(width) points so the protected camera and Video Settings can coexist."
    }
  }
}

struct VideoSettingsPresentation: Equatable, Sendable {
  let isPresented: Bool
  let action: VideoSettingsVisibilityAction
  let actionTitle: String
  let unavailableReason: VideoSettingsUnavailableReason?

  var isActionEnabled: Bool { unavailableReason == nil }
  var unavailableReasonText: String? { unavailableReason?.message }
}

/// Pure inspector admission policy. The caller supplies the workbench content
/// width: while hidden it is the full window content width; while shown it is
/// the width remaining after the native inspector. Checking Show admission
/// against the protected workbench, inspector, and separator widths prevents
/// an open-then-close flash.
struct VideoSettingsVisibilityPolicy: Equatable, Sendable {
  let minimumCameraWidth: CGFloat
  let minimumLearningWidth: CGFloat
  let splitSeparation: CGFloat
  let inspectorWidth: CGFloat
  let inspectorSeparation: CGFloat

  init(
    minimumCameraWidth: CGFloat = 640,
    minimumLearningWidth: CGFloat = 340,
    splitSeparation: CGFloat = 8,
    inspectorWidth: CGFloat = 360,
    inspectorSeparation: CGFloat = 8
  ) {
    self.minimumCameraWidth = Self.nonnegativeFinite(minimumCameraWidth)
    self.minimumLearningWidth = Self.nonnegativeFinite(minimumLearningWidth)
    self.splitSeparation = Self.nonnegativeFinite(splitSeparation)
    self.inspectorWidth = Self.nonnegativeFinite(inspectorWidth)
    self.inspectorSeparation = Self.nonnegativeFinite(inspectorSeparation)
  }

  /// Video Settings can always be reached once the protected camera and inspector
  /// fit. Side panes collapse before this lower bound is used.
  var minimumWidthToShow: CGFloat {
    minimumCameraWidth + inspectorWidth + inspectorSeparation
  }

  func minimumContentWidth(for panes: WorkbenchPaneVisibility) -> CGFloat {
    minimumCameraWidth
      + (panes.learningPathIsPresented ? minimumLearningWidth + splitSeparation : 0)
  }

  /// The Learning panel is presentation only. Stop is also in the persistent
  /// command bar, so opening an inspector never depends on exercise completion.
  func preparingPanesToShow(
    _ panes: WorkbenchPaneVisibility,
    availableWindowWidth: CGFloat
  ) -> WorkbenchPaneVisibility? {
    let width = Self.nonnegativeFinite(availableWindowWidth)
    func fits(_ candidate: WorkbenchPaneVisibility) -> Bool {
      width >= minimumContentWidth(for: candidate) + inspectorWidth + inspectorSeparation
    }
    var candidate = panes
    if fits(candidate) { return candidate }
    candidate.learningPathIsPresented = false
    return fits(candidate) ? candidate : nil
  }

  func presentation(
    layout: WorkbenchLayoutState,
    availableWindowWidth: CGFloat
  ) -> VideoSettingsPresentation {
    if layout.videoSettingsIsPresented {
      return VideoSettingsPresentation(
        isPresented: true,
        action: .hide,
        actionTitle: WorkbenchPanel.videoSettings.actionTitle(isPresented: true),
        unavailableReason: nil
      )
    }

    let width = Self.nonnegativeFinite(availableWindowWidth)
    let unavailableReason: VideoSettingsUnavailableReason?
    if width < minimumWidthToShow {
      unavailableReason = .protectedCameraRequiresWindowWidth(Int(minimumWidthToShow))
    } else {
      unavailableReason = nil
    }
    return VideoSettingsPresentation(
      isPresented: false,
      action: .show,
      actionTitle: WorkbenchPanel.videoSettings.actionTitle(isPresented: false),
      unavailableReason: unavailableReason
    )
  }

  /// Returns the complete next layout for one synchronous state assignment.
  /// A refused Show has no state to commit.
  func transition(
    from layout: WorkbenchLayoutState,
    action: VideoSettingsVisibilityAction,
    availableWindowWidth: CGFloat
  ) -> WorkbenchLayoutState? {
    switch action {
    case .hide:
      return layout.hidingVideoSettings()
    case .show:
      guard !layout.videoSettingsIsPresented else { return layout }
      guard
        let panes = preparingPanesToShow(
          layout.panes,
          availableWindowWidth: availableWindowWidth
        )
      else { return nil }
      return WorkbenchLayoutState(
        panes: panes,
        videoSettingsIsPresented: true
      )
    }
  }

  /// While the inspector is open, the geometry reader reports the remaining
  /// workbench width. Close Video Settings only if even the currently presented
  /// side panes would violate the protected camera minimum.
  func shouldCollapsePresentedVideoSettings(
    availableContentWidth: CGFloat,
    panes: WorkbenchPaneVisibility
  ) -> Bool {
    Self.nonnegativeFinite(availableContentWidth) < minimumContentWidth(for: panes)
  }

  private static func nonnegativeFinite(_ value: CGFloat) -> CGFloat {
    guard value.isFinite else { return 0 }
    return max(0, value)
  }
}
