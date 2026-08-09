import CoreGraphics
import Foundation

/// A deterministic width allocation used to verify the native three-region
/// split independently of SwiftUI rendering. `HSplitView` remains responsible
/// for live user resizing; these values define its initial and minimum policy.
struct LearningWorkbenchAllocation: Equatable, Sendable {
  let navigatorWidth: CGFloat
  let cameraWidth: CGFloat
  let detailWidth: CGFloat
  let dividerSpacing: CGFloat

  var totalWidth: CGFloat {
    navigatorWidth + cameraWidth + detailWidth + (2 * dividerSpacing)
  }
}

struct LearningWorkbenchLayoutPolicy: Equatable, Sendable {
  static let minimumWindowWidth: CGFloat = 1_440
  static let minimumActionSurfaceWidth: CGFloat = 640
  static let minimumActionSurfaceHeight: CGFloat = 480

  let preferredNavigatorWidth: CGFloat
  let preferredDetailWidth: CGFloat
  let minimumCameraWidth: CGFloat
  let dividerSpacing: CGFloat

  init(
    preferredNavigatorWidth: CGFloat = 280,
    preferredDetailWidth: CGFloat = 380,
    minimumCameraWidth: CGFloat = Self.minimumActionSurfaceWidth,
    dividerSpacing: CGFloat = 8
  ) {
    self.preferredNavigatorWidth = Self.nonnegativeFinite(preferredNavigatorWidth)
    self.preferredDetailWidth = Self.nonnegativeFinite(preferredDetailWidth)
    self.minimumCameraWidth = Self.nonnegativeFinite(minimumCameraWidth)
    self.dividerSpacing = Self.nonnegativeFinite(dividerSpacing)
  }

  /// Protects the camera first. When a width below the supported window minimum
  /// is supplied, side allocations shrink toward zero before the camera does.
  /// At supported widths the side regions keep stable preferred widths and all
  /// additional width belongs to the camera.
  func allocation(for containerWidth: CGFloat) -> LearningWorkbenchAllocation {
    let width = Self.nonnegativeFinite(containerWidth)
    let spacingTotal = min(width, 2 * dividerSpacing)
    let contentWidth = max(0, width - spacingTotal)
    let cameraWidth = min(minimumCameraWidth, contentWidth)
    let sideCapacity = max(0, contentWidth - cameraWidth)
    let preferredSideTotal = preferredNavigatorWidth + preferredDetailWidth

    let navigatorWidth: CGFloat
    let detailWidth: CGFloat
    if preferredSideTotal == 0 {
      navigatorWidth = 0
      detailWidth = 0
    } else if sideCapacity < preferredSideTotal {
      navigatorWidth = sideCapacity * preferredNavigatorWidth / preferredSideTotal
      detailWidth = sideCapacity - navigatorWidth
    } else {
      navigatorWidth = preferredNavigatorWidth
      detailWidth = preferredDetailWidth
    }

    let protectedCameraWidth = contentWidth - navigatorWidth - detailWidth
    return LearningWorkbenchAllocation(
      navigatorWidth: navigatorWidth,
      cameraWidth: protectedCameraWidth,
      detailWidth: detailWidth,
      dividerSpacing: spacingTotal / 2
    )
  }

  private static func nonnegativeFinite(_ value: CGFloat) -> CGFloat {
    guard value.isFinite else { return 0 }
    return max(0, value)
  }
}

enum WorkbenchPane: Hashable, Sendable {
  case navigator
  case motion
  case exerciseDetail
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
    motionIsPresented: Bool = true,
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

enum UtilitiesVisibilityAction: Hashable, Sendable {
  case show
  case hide
}

struct UtilitiesPresentation: Equatable, Sendable {
  let isPresented: Bool
  let action: UtilitiesVisibilityAction
  let actionTitle: String
  let unavailableReason: String?

  var isActionEnabled: Bool { unavailableReason == nil }
}

/// Pure inspector admission policy. The caller supplies the workbench content
/// width: while hidden it is the full window content width; while shown it is
/// the width remaining after the native inspector. Checking Show admission
/// against the protected workbench, inspector, and separator widths prevents
/// an open-then-close flash.
struct UtilitiesVisibilityPolicy: Equatable, Sendable {
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

  /// Utilities can always be reached once the protected camera and inspector
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

  /// Hides the navigator first, then the exercise detail only if necessary.
  /// Callers may forbid detail collapse while it owns active exercise actions.
  func preparingPanesToShow(
    _ panes: WorkbenchPaneVisibility,
    availableWindowWidth: CGFloat,
    canCollapseExerciseDetail: Bool
  ) -> WorkbenchPaneVisibility {
    let width = Self.nonnegativeFinite(availableWindowWidth)
    func fits(_ candidate: WorkbenchPaneVisibility) -> Bool {
      width >= minimumContentWidth(for: candidate) + inspectorWidth + inspectorSeparation
    }
    guard !fits(panes) else { return panes }

    var candidate = panes
    candidate.navigatorIsPresented = false
    guard !fits(candidate), canCollapseExerciseDetail else { return candidate }
    candidate.exerciseDetailIsPresented = false
    return candidate
  }

  func presentation(
    isPresented: Bool,
    availableWindowWidth: CGFloat
  ) -> UtilitiesPresentation {
    if isPresented {
      return UtilitiesPresentation(
        isPresented: true,
        action: .hide,
        actionTitle: "Hide Utilities",
        unavailableReason: nil
      )
    }

    let width = Self.nonnegativeFinite(availableWindowWidth)
    let unavailableReason =
      width >= minimumWidthToShow
      ? nil
      : "Widen the window to at least \(Int(minimumWidthToShow)) points so the protected camera and Utilities can coexist."
    return UtilitiesPresentation(
      isPresented: false,
      action: .show,
      actionTitle: "Show Utilities",
      unavailableReason: unavailableReason
    )
  }

  func transition(
    isPresented: Bool,
    action: UtilitiesVisibilityAction,
    availableWindowWidth: CGFloat
  ) -> Bool {
    switch action {
    case .hide:
      return false
    case .show:
      guard !isPresented else { return true }
      return presentation(
        isPresented: false,
        availableWindowWidth: availableWindowWidth
      ).isActionEnabled
    }
  }

  /// While the inspector is open, the geometry reader reports the remaining
  /// workbench width. Close Utilities only if even the currently presented
  /// side panes would violate the protected camera minimum.
  func shouldCollapsePresentedUtilities(
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
