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

  let preferredNavigatorWidth: CGFloat
  let preferredDetailWidth: CGFloat
  let minimumCameraWidth: CGFloat
  let dividerSpacing: CGFloat

  init(
    preferredNavigatorWidth: CGFloat = 280,
    preferredDetailWidth: CGFloat = 380,
    minimumCameraWidth: CGFloat = 640,
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
  let minimumWorkbenchWidth: CGFloat
  let inspectorWidth: CGFloat
  let inspectorSeparation: CGFloat

  init(
    minimumWorkbenchWidth: CGFloat = LearningWorkbenchLayoutPolicy.minimumWindowWidth,
    inspectorWidth: CGFloat = 360,
    inspectorSeparation: CGFloat = 8
  ) {
    self.minimumWorkbenchWidth = Self.nonnegativeFinite(minimumWorkbenchWidth)
    self.inspectorWidth = Self.nonnegativeFinite(inspectorWidth)
    self.inspectorSeparation = Self.nonnegativeFinite(inspectorSeparation)
  }

  var minimumWidthToShow: CGFloat {
    minimumWorkbenchWidth + inspectorWidth + inspectorSeparation
  }

  func presentation(
    isPresented: Bool,
    availableContentWidth: CGFloat
  ) -> UtilitiesPresentation {
    if isPresented {
      return UtilitiesPresentation(
        isPresented: true,
        action: .hide,
        actionTitle: "Hide Utilities",
        unavailableReason: nil
      )
    }

    let width = Self.nonnegativeFinite(availableContentWidth)
    let unavailableReason =
      width >= minimumWidthToShow
      ? nil
      : "Widen the window to at least \(Int(minimumWidthToShow)) points to preserve the camera while Utilities is open."
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
    availableContentWidth: CGFloat
  ) -> Bool {
    switch action {
    case .hide:
      return false
    case .show:
      guard !isPresented else { return true }
      return presentation(
        isPresented: false,
        availableContentWidth: availableContentWidth
      ).isActionEnabled
    }
  }

  func shouldCollapsePresentedUtilities(availableContentWidth: CGFloat) -> Bool {
    Self.nonnegativeFinite(availableContentWidth) < minimumWorkbenchWidth
  }

  private static func nonnegativeFinite(_ value: CGFloat) -> CGFloat {
    guard value.isFinite else { return 0 }
    return max(0, value)
  }
}
