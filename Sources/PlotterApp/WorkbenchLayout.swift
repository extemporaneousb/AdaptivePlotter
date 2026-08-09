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
