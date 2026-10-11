import CoreGraphics
import PlotterModel
import PlotterRuntime

package enum ActionSurfaceScalePolicy: String, Sendable {
  case aspectFit
}

/// Presentation-only projection from top-left-origin camera pixels into the
/// aspect-fitted image rectangle. Camera +Y remains view +Y.
package struct CameraPixelToViewTransform: Equatable, Sendable {
  package let frameWidth: Double
  package let frameHeight: Double
  package let viewWidth: Double
  package let viewHeight: Double
  package let scale: Double
  package let originX: Double
  package let originY: Double
  package let visibleCameraRect: CGRect

  package init?(
    frameWidth: Int,
    frameHeight: Int,
    viewWidth: Double,
    viewHeight: Double,
    focusRegion: PixelRect? = nil,
    policy: ActionSurfaceScalePolicy = .aspectFit
  ) {
    guard frameWidth > 0, frameHeight > 0, viewWidth > 0, viewHeight > 0 else { return nil }
    let requestedRect =
      focusRegion.map {
        CGRect(x: $0.x, y: $0.y, width: $0.width, height: $0.height)
      } ?? CGRect(x: 0, y: 0, width: frameWidth, height: frameHeight)
    let frameRect = CGRect(x: 0, y: 0, width: frameWidth, height: frameHeight)
    let clippedRect = requestedRect.intersection(frameRect)
    guard !clippedRect.isNull, clippedRect.width > 0, clippedRect.height > 0 else { return nil }
    visibleCameraRect = clippedRect
    let horizontalScale = viewWidth / clippedRect.width
    let verticalScale = viewHeight / clippedRect.height
    switch policy {
    case .aspectFit:
      scale = min(horizontalScale, verticalScale)
    }
    self.frameWidth = Double(frameWidth)
    self.frameHeight = Double(frameHeight)
    self.viewWidth = viewWidth
    self.viewHeight = viewHeight
    originX = (viewWidth - clippedRect.width * scale) / 2 - clippedRect.minX * scale
    originY = (viewHeight - clippedRect.height * scale) / 2 - clippedRect.minY * scale
  }

  package var imageRect: CGRect {
    CGRect(
      x: originX,
      y: originY,
      width: frameWidth * scale,
      height: frameHeight * scale
    )
  }

  package func point(_ cameraPoint: Point2<CameraPixelSpace>) -> CGPoint {
    CGPoint(
      x: originX + cameraPoint.x * scale,
      y: originY + cameraPoint.y * scale
    )
  }

  package func cameraPoint(_ viewPoint: CGPoint) -> Point2<CameraPixelSpace>? {
    let x = (viewPoint.x - originX) / scale
    let y = (viewPoint.y - originY) / scale
    guard visibleCameraRect.contains(CGPoint(x: x, y: y)),
      x >= 0, x < frameWidth, y >= 0, y < frameHeight
    else { return nil }
    return try? Point2(x: x, y: y)
  }
}
