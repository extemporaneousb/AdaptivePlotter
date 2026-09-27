import CoreGraphics
import Foundation
import PlotterEpisodeRuntime
import PlotterModel
import PlotterRuntime
import SwiftUI

struct CalibrationWorkingRegionPresentation: Equatable {
  let context: PlotterTipWorkingRegionContext
  let bounds: AxisAlignedBounds<MachineSpace>
  let edit: PlotterTipWorkingRegionEdit?
  let isStale: Bool
  var unavailableReason: String? = nil
}

enum CalibrationWorkingRegionGeometry {
  /// Available even when the default Boundary handles lie outside the camera.
  static func smaller(_ bounds: AxisAlignedBounds<MachineSpace>) throws -> AxisAlignedBounds<MachineSpace> {
    let cx = (bounds.minX + bounds.maxX) / 2, cy = (bounds.minY + bounds.maxY) / 2
    let halfWidth = max(TipCalibrationWorkingRegionPolicy.minimumSpanMM, (bounds.maxX-bounds.minX)*0.8) / 2
    let halfHeight = max(TipCalibrationWorkingRegionPolicy.minimumSpanMM, (bounds.maxY-bounds.minY)*0.8) / 2
    return try AxisAlignedBounds(minX: cx-halfWidth, minY: cy-halfHeight, maxX: cx+halfWidth, maxY: cy+halfHeight)
  }
}

struct CalibrationWorkingRegionDrag {
  let original: AxisAlignedBounds<MachineSpace>
  let context: PlotterTipWorkingRegionContext
  let start: Point2<MachineSpace>
  let corner: Int?

  init?(bounds: AxisAlignedBounds<MachineSpace>, context: PlotterTipWorkingRegionContext,
    start: CGPoint, transform: CameraPixelToViewTransform) {
    guard let pixel = transform.cameraPoint(start),
      let inverse = try? context.machineMap.fit.cameraFromMachine.inverted(),
      let machine = try? inverse.applying(to: pixel),
      let path = try? DrawingBorderPlan(bounds: bounds),
      let corners = try? path.pathPositions.dropLast().map({ try context.machineMap.fit.cameraPoint(from: $0.point) }) else { return nil }
    let points = corners.map(transform.point)
    let nearest = points.indices.min { hypot(points[$0].x-start.x, points[$0].y-start.y) < hypot(points[$1].x-start.x, points[$1].y-start.y) }
    let handle = nearest.flatMap { hypot(points[$0].x-start.x, points[$0].y-start.y) <= 12 ? $0 : nil }
    guard handle != nil || bounds.contains(machine) else { return nil }
    self.original = bounds
    self.context = context
    self.start = machine
    self.corner = handle
  }

  func updated(at pixel: Point2<CameraPixelSpace>) throws -> AxisAlignedBounds<MachineSpace> {
    let point = try context.machineMap.fit.cameraFromMachine.inverted().applying(to: pixel)
    let boundary = context.boundary
    let dx = point.x - start.x, dy = point.y - start.y
    let minimum = TipCalibrationWorkingRegionPolicy.minimumSpanMM
    if let corner {
      // DrawingBorderPlan order: lower-left, upper-left, upper-right, lower-right.
      let left = corner == 0 || corner == 1, bottom = corner == 0 || corner == 3
      return try AxisAlignedBounds(
        minX: left ? max(boundary.minX, min(original.maxX-minimum, original.minX+dx)) : original.minX,
        minY: bottom ? max(boundary.minY, min(original.maxY-minimum, original.minY+dy)) : original.minY,
        maxX: left ? original.maxX : min(boundary.maxX, max(original.minX+minimum, original.maxX+dx)),
        maxY: bottom ? original.maxY : min(boundary.maxY, max(original.minY+minimum, original.maxY+dy)))
    }
    let x = max(boundary.minX-original.minX, min(boundary.maxX-original.maxX, dx))
    let y = max(boundary.minY-original.minY, min(boundary.maxY-original.maxY, dy))
    return try AxisAlignedBounds(minX: original.minX+x, minY: original.minY+y,
      maxX: original.maxX+x, maxY: original.maxY+y)
  }
}

struct CalibrationWorkingRegionOverlay: View {
  let context: PlotterTipWorkingRegionContext
  let bounds: AxisAlignedBounds<MachineSpace>
  let transform: CameraPixelToViewTransform
  let editing: Bool
  var showsRegion = true

  var body: some View {
    Canvas { graphics, _ in
      guard let batch = try? SparseTipBatchMarkPlan(boundaryEnvelope: context.boundary, workingRegion: bounds),
        let extent = try? DrawingBorderPlan(bounds: batch.workingRegion) else { return }
      func projected(_ positions: [MachinePosition]) -> [CGPoint]? {
        try? positions.map { transform.point(try context.machineMap.fit.cameraPoint(from: $0.point)) }
      }
      func outline(_ points: [CGPoint], color: Color, dash: [CGFloat]) {
        guard let first = points.first else { return }
        var path = Path(); path.move(to: first)
        for point in points.dropFirst() { path.addLine(to: point) }
        // Paper can fill the video with white; retain contrast without changing
        // the semantic colors or dash patterns of the reference outlines.
        graphics.stroke(path, with: .color(.black.opacity(0.8)), style: SwiftUI.StrokeStyle(lineWidth: 3.5, dash: dash))
        graphics.stroke(path, with: .color(color), style: SwiftUI.StrokeStyle(lineWidth: 1.5, dash: dash))
      }
      guard let corners = projected(extent.pathPositions) else { return }
      if showsRegion { outline(corners, color: .yellow, dash: [6, 3]) }
      for mark in batch.marks {
        if let points = projected(mark.circle.pathPositions) { outline(points, color: .cyan, dash: []) }
      }
      if editing && showsRegion {
        for point in corners.dropLast() {
          let handle = Path(CGRect(x: point.x-5, y: point.y-5, width: 10, height: 10))
          graphics.fill(handle, with: .color(.black)); graphics.stroke(handle, with: .color(.yellow), lineWidth: 2)
        }
      }
    }
    .allowsHitTesting(false)
    .accessibilityLabel("Drawing Region. Approximate cap projection with unknown tip offset. Circles inset 10 millimeters, leaving 8 millimeters outline clearance.")
  }
}
