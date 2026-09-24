import PlotterModel
import SwiftUI

/// Pure camera-coordinate conversion shared with selection tests. A drag across
/// letterboxing is refused rather than being silently clamped into another patch.
enum PenCapReferenceSelectionGeometry {
  static func region(from start: CGPoint, to end: CGPoint,
    transform: CameraPixelToViewTransform?) -> AxisAlignedBounds<CameraPixelSpace>? {
    guard let a = transform?.cameraPoint(start), let b = transform?.cameraPoint(end),
      abs(a.x - b.x) >= 1, abs(a.y - b.y) >= 1 else { return nil }
    return try? AxisAlignedBounds(minX: min(a.x, b.x), minY: min(a.y, b.y),
      maxX: max(a.x, b.x), maxY: max(a.y, b.y))
  }
}

struct PenCapReferenceSelectionOverlay: View {
  let region: AxisAlignedBounds<CameraPixelSpace>?
  let transform: CameraPixelToViewTransform?

  var body: some View {
    if let region, let transform,
      let a = try? Point2<CameraPixelSpace>(x: region.minX, y: region.minY),
      let b = try? Point2<CameraPixelSpace>(x: region.maxX, y: region.maxY) {
      let start = transform.point(a), end = transform.point(b)
      Path { path in
        path.addRect(CGRect(x: start.x, y: start.y,
          width: end.x - start.x, height: end.y - start.y))
      }
      .stroke(.yellow, style: StrokeStyle(lineWidth: 2, dash: [6, 3]))
      .accessibilityLabel("Selected tracking reference rectangle; click the landmark inside it")
    }
  }
}
