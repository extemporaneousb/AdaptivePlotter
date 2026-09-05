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
  case navigator
  case motion
  case exerciseDetail
}

enum WorkbenchPanel: CaseIterable, Hashable, Sendable {
  case learningPath
  case motion
  case exercise
  case videoSettings

  var title: String {
    switch self {
    case .learningPath: "Learning Path"
    case .motion: "Motion"
    case .exercise: "Exercise"
    case .videoSettings: "Video Settings"
    }
  }

  var systemImage: String {
    switch self {
    case .learningPath: "sidebar.left"
    case .motion: "rectangle.bottomthird.inset.filled"
    case .exercise: "sidebar.right"
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
  var navigatorIsPresented: Bool
  var motionIsPresented: Bool
  var exerciseDetailIsPresented: Bool

  init(
    navigatorIsPresented: Bool = true,
    motionIsPresented: Bool = false,
    exerciseDetailIsPresented: Bool = true
  ) {
    self.navigatorIsPresented = navigatorIsPresented
    self.motionIsPresented = motionIsPresented
    self.exerciseDetailIsPresented = exerciseDetailIsPresented
  }

  func isPresented(_ pane: WorkbenchPane) -> Bool {
    switch pane {
    case .navigator: navigatorIsPresented
    case .motion: motionIsPresented
    case .exerciseDetail: exerciseDetailIsPresented
    }
  }

  func toggling(_ pane: WorkbenchPane) -> WorkbenchPaneVisibility {
    var result = self
    switch pane {
    case .navigator: result.navigatorIsPresented.toggle()
    case .motion: result.motionIsPresented.toggle()
    case .exerciseDetail: result.exerciseDetailIsPresented.toggle()
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
  case activeExerciseRequiresWindowWidth(Int)

  var message: String {
    switch self {
    case .protectedCameraRequiresWindowWidth(let width):
      "Widen the window to at least \(width) points so the protected camera and Video Settings can coexist."
    case .activeExerciseRequiresWindowWidth(let width):
      "Widen the window to at least \(width) points so the protected camera, Video Settings, and active Exercise controls including Stop can coexist."
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
  let minimumNavigatorWidth: CGFloat
  let minimumDetailWidth: CGFloat
  let splitSeparation: CGFloat
  let inspectorWidth: CGFloat
  let inspectorSeparation: CGFloat

  init(
    minimumCameraWidth: CGFloat = 640,
    minimumNavigatorWidth: CGFloat = 220,
    minimumDetailWidth: CGFloat = 300,
    splitSeparation: CGFloat = 8,
    inspectorWidth: CGFloat = 360,
    inspectorSeparation: CGFloat = 8
  ) {
    self.minimumCameraWidth = Self.nonnegativeFinite(minimumCameraWidth)
    self.minimumNavigatorWidth = Self.nonnegativeFinite(minimumNavigatorWidth)
    self.minimumDetailWidth = Self.nonnegativeFinite(minimumDetailWidth)
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
    let presentedSideCount = [
      panes.navigatorIsPresented,
      panes.exerciseDetailIsPresented,
    ].filter { $0 }.count
    return minimumCameraWidth
      + (panes.navigatorIsPresented ? minimumNavigatorWidth : 0)
      + (panes.exerciseDetailIsPresented ? minimumDetailWidth : 0)
      + CGFloat(presentedSideCount) * splitSeparation
  }

  /// Hides the navigator first, then the Exercise detail only if it is not the
  /// active operation's protected control surface. A protected Exercise pane
  /// is restored before admission if it was previously hidden.
  func preparingPanesToShow(
    _ panes: WorkbenchPaneVisibility,
    availableWindowWidth: CGFloat,
    exerciseDetailMustRemainVisible: Bool
  ) -> WorkbenchPaneVisibility? {
    let width = Self.nonnegativeFinite(availableWindowWidth)
    func fits(_ candidate: WorkbenchPaneVisibility) -> Bool {
      width >= minimumContentWidth(for: candidate) + inspectorWidth + inspectorSeparation
    }

    var candidate = panes
    if exerciseDetailMustRemainVisible {
      candidate.exerciseDetailIsPresented = true
    }
    guard !fits(candidate) else { return candidate }

    candidate.navigatorIsPresented = false
    guard !fits(candidate) else { return candidate }
    guard !exerciseDetailMustRemainVisible else { return nil }
    candidate.exerciseDetailIsPresented = false
    return fits(candidate) ? candidate : nil
  }

  func presentation(
    layout: WorkbenchLayoutState,
    availableWindowWidth: CGFloat,
    exerciseDetailMustRemainVisible: Bool
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
    } else if preparingPanesToShow(
      layout.panes,
      availableWindowWidth: width,
      exerciseDetailMustRemainVisible: exerciseDetailMustRemainVisible
    ) == nil {
      let protectedPanes = WorkbenchPaneVisibility(
        navigatorIsPresented: false,
        motionIsPresented: layout.panes.motionIsPresented,
        exerciseDetailIsPresented: true
      )
      unavailableReason = .activeExerciseRequiresWindowWidth(
        Int(minimumContentWidth(for: protectedPanes) + inspectorWidth + inspectorSeparation)
      )
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
    availableWindowWidth: CGFloat,
    exerciseDetailMustRemainVisible: Bool
  ) -> WorkbenchLayoutState? {
    switch action {
    case .hide:
      return layout.hidingVideoSettings()
    case .show:
      guard !layout.videoSettingsIsPresented else { return layout }
      guard
        let panes = preparingPanesToShow(
          layout.panes,
          availableWindowWidth: availableWindowWidth,
          exerciseDetailMustRemainVisible: exerciseDetailMustRemainVisible
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
