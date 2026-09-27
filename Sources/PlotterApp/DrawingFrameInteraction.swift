import CoreGraphics
import PlotterEpisodeModel
import PlotterEpisodeRuntime
import PlotterModel
import PlotterRuntime
import SwiftUI

/// View-local gesture state. The exact retained frame and Draft request still
/// own submission; this type only derives a bounded staged placement.
struct DrawingFrameDrag {
  let original: PlotterDrawingDraftFrame
  let start: Point2<CameraPixelSpace>
  let corner: Int?

  init?(frame: PlotterDrawingDraftFrame, start: CGPoint, transform: CameraPixelToViewTransform) {
    guard let cameraStart = transform.cameraPoint(start), let corners = try? frame.cameraCorners else { return nil }
    let views = corners.map(transform.point)
    let handle = views.indices.min(by: {
      hypot(views[$0].x - start.x, views[$0].y - start.y) < hypot(views[$1].x - start.x, views[$1].y - start.y)
    }).flatMap { hypot(views[$0].x - start.x, views[$0].y - start.y) <= 12 ? $0 : nil }
    if handle == nil {
      var signs: [Double] = []
      for index in corners.indices {
        let a = corners[index], b = corners[(index + 1) % corners.count]
        signs.append((b.x - a.x) * (cameraStart.y - a.y) - (b.y - a.y) * (cameraStart.x - a.x))
      }
      guard signs.allSatisfy({ $0 >= 0 }) || signs.allSatisfy({ $0 <= 0 }) else { return nil }
    }
    original = frame
    self.start = cameraStart
    corner = handle
  }

  func updated(at point: Point2<CameraPixelSpace>, minimumScale: Double) throws -> PlotterDrawingDraftFrame {
    let center = try original.cameraCenter
    if let corner {
      let handle = try original.cameraCorners[corner]
      let x = handle.x - center.x, y = handle.y - center.y
      let ratio = 1 + ((point.x - start.x) * x + (point.y - start.y) * y) / (x * x + y * y)
      return try original.resized(scale: original.geometry.placement.uniformScale * ratio, minimumScale: minimumScale)
    }
    return try original.translated(to: Point2(x: center.x + point.x - start.x, y: center.y + point.y - start.y))
  }
}

struct DrawingFrameOverlay: View {
  let frame: PlotterDrawingDraftFrame
  let transform: CameraPixelToViewTransform
  let editing: Bool
  let staged: Bool

  var body: some View {
    Canvas { context, _ in
      guard let corners = try? frame.cameraCorners, let first = corners.first else { return }
      let color: Color = .yellow
      var path = Path()
      path.move(to: transform.point(first))
      for corner in corners.dropFirst() { path.addLine(to: transform.point(corner)) }
      path.closeSubpath()
      context.stroke(path, with: .color(.black.opacity(0.8)), style: .init(lineWidth: 3.5, dash: [6, 3]))
      context.stroke(path, with: .color(color), style: .init(lineWidth: 1.5, dash: [6, 3]))
      if editing {
        for corner in corners {
          let point = transform.point(corner)
          let handle = Path(CGRect(x: point.x - 5, y: point.y - 5, width: 10, height: 10))
          context.fill(handle, with: .color(.black))
          context.stroke(handle, with: .color(color), lineWidth: 2)
        }
      }
      let projected = corners.map(transform.point)
      let caption = CGPoint(x: projected.map(\.x).min()!, y: projected.map(\.y).min()! - 9)
      context.draw(Text(staged ? "ARTWORK POSITION · STAGED" : "ARTWORK POSITION")
        .font(.caption2.monospaced().bold()).foregroundStyle(color),
        at: caption, anchor: .bottomLeading)
    }
    .allowsHitTesting(false)
    .accessibilityLabel(editing ? "Drawing frame. Drag the body to move; drag a corner to resize about its center." : "Drawing frame")
  }
}

struct DrawingFrameEditSession {
  let id: UUID
  let frame: DisplayedFrame
  let projection: PlotterDrawingDraftProjectionReference

  func matches(_ current: PlotterDrawingDraftProjectionReference) -> Bool {
    Self.matches(projection, current)
  }

  static func matches(_ origin: PlotterDrawingDraftProjectionReference, _ current: PlotterDrawingDraftProjectionReference) -> Bool {
    let a = origin.externalFacts, b = current.externalFacts
    return origin.environment == current.environment && origin.draftRevision == current.draftRevision
      && a.registrationRevisionID == b.registrationRevisionID && a.drawableRegion == b.drawableRegion
      && a.opticalConfiguration == b.opticalConfiguration && a.toolAssemblyRevision == b.toolAssemblyRevision
      && a.paper == b.paper && a.materialContextHash == b.materialContextHash
      && a.coverageRecordIDs == b.coverageRecordIDs && a.drawingArchiveIsAvailable == b.drawingArchiveIsAvailable
      && a.drawingBorderBounds == b.drawingBorderBounds && a.placementGuide == b.placementGuide
      && a.interactiveLearningIsComplete == b.interactiveLearningIsComplete
      && !b.runInProgress && !b.terminalRequiresNewPlan
  }
}
