import PlotterModel
import PlotterRuntime
import SwiftUI

/// SwiftUI retains this Canvas while pixels advance underneath it. Viewport and
/// exact drawing changes redraw immediately; passive scene jitter is stabilized upstream.
struct ActionSurfaceOverlayCanvas: View, Equatable {
  let content: ActionSurfaceOverlayContent
  let transform: CameraPixelToViewTransform?
  let diagnostics: ActionSurfacePreviewModel?

  nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.transform == rhs.transform && lhs.content == rhs.content
      && lhs.diagnostics === rhs.diagnostics
  }

  var body: some View {
    let _ = diagnostics?.recordOverlayCanvasBuild()
    Canvas { context, _ in
      diagnostics?.recordOverlayCanvasDraw()
      guard let transform else { return }
      drawFrameAndOverlays(context: &context, transform: transform)
    }
  }

  private func drawFrameAndOverlays(
    context: inout GraphicsContext,
    transform: CameraPixelToViewTransform
  ) {
    if let targetPreview = content.targetPreview {
      draw(targetPreview, in: &context, transform: transform)
    }
    for overlay in content.overlays {
      draw(overlay, in: &context, transform: transform)
    }
    if let review = content.tipReview {
      draw(review, in: &context, transform: transform)
    }
    for (index, click) in content.clickMarkers.enumerated() {
      drawCollectedClick(click, ordinal: index + 1, in: &context, transform: transform)
    }
    if !content.simulatedAnnotations.isEmpty {
      for annotation in content.simulatedAnnotations {
        draw(annotation, in: &context, transform: transform)
      }
    }
  }

  private func draw(
    _ target: DrawingStudioTargetPreview,
    in context: inout GraphicsContext,
    transform: CameraPixelToViewTransform
  ) {
    let color: Color = target.status == .ready ? .cyan : .orange
    for stroke in target.strokes {
      var path = Path()
      path.move(to: transform.point(stroke.start))
      for point in stroke.points.dropFirst() {
        path.addLine(to: transform.point(point))
      }
      context.stroke(path, with: .color(color), lineWidth: 2)
    }
    if target.showsStrokeBounds, let bounds = target.bounds,
      let minimum = try? Point2<CameraPixelSpace>(x: bounds.minX, y: bounds.minY),
      let maximum = try? Point2<CameraPixelSpace>(x: bounds.maxX, y: bounds.maxY)
    {
      let minimumView = transform.point(minimum)
      let maximumView = transform.point(maximum)
      context.stroke(
        Path(CGRect(
          x: minimumView.x,
          y: minimumView.y,
          width: maximumView.x - minimumView.x,
          height: maximumView.y - minimumView.y
        )),
        with: .color(color),
        style: SwiftUI.StrokeStyle(lineWidth: 1, dash: [5, 4])
      )
      context.draw(
        Text("TARGET DRAWING · PLANNED")
          .font(.caption2.monospaced().bold())
          .foregroundStyle(color),
        at: minimumView,
        anchor: .bottomLeading
      )
    }
  }

  private func drawCollectedClick(
    _ click: Point2<CameraPixelSpace>,
    ordinal: Int,
    in context: inout GraphicsContext,
    transform: CameraPixelToViewTransform
  ) {
    let center = transform.point(click)
    let radius: CGFloat = 6
    context.stroke(
      Path(
        ellipseIn: CGRect(
          x: center.x - radius,
          y: center.y - radius,
          width: radius * 2,
          height: radius * 2
        )
      ),
      with: .color(.cyan),
      lineWidth: 2
    )
    context.draw(
      Text("\(ordinal)").font(.caption2.monospaced().bold()).foregroundStyle(.cyan),
      at: CGPoint(x: center.x + 10, y: center.y - 10),
      anchor: .center
    )
  }

  private func draw(
    _ review: ActionSurfaceTipReviewGeometry,
    in context: inout GraphicsContext,
    transform: CameraPixelToViewTransform
  ) {
    let click = transform.point(review.click)
    let uncertaintyRect = CGRect(
      x: click.x - review.pointingUncertaintyPixels.dx * transform.scale,
      y: click.y - review.pointingUncertaintyPixels.dy * transform.scale,
      width: review.pointingUncertaintyPixels.dx * transform.scale * 2,
      height: review.pointingUncertaintyPixels.dy * transform.scale * 2
    )
    context.stroke(
      Path(ellipseIn: uncertaintyRect),
      with: .color(.cyan),
      style: SwiftUI.StrokeStyle(lineWidth: 1.5, dash: [3, 2])
    )
    let crossRadius: CGFloat = 5
    var cross = Path()
    cross.move(to: CGPoint(x: click.x - crossRadius, y: click.y))
    cross.addLine(to: CGPoint(x: click.x + crossRadius, y: click.y))
    cross.move(to: CGPoint(x: click.x, y: click.y - crossRadius))
    cross.addLine(to: CGPoint(x: click.x, y: click.y + crossRadius))
    context.stroke(cross, with: .color(.cyan), lineWidth: 2)

    if let prediction = review.prediction {
      let predicted = transform.point(prediction)
      let radius: CGFloat = 5
      context.fill(
        Path(
          ellipseIn: CGRect(
            x: predicted.x - radius,
            y: predicted.y - radius,
            width: radius * 2,
            height: radius * 2
          )),
        with: .color(.purple)
      )
    }
    if let residual = review.residual {
      var path = Path()
      path.move(to: transform.point(residual.start))
      for point in residual.points.dropFirst() {
        path.addLine(to: transform.point(point))
      }
      context.stroke(path, with: .color(.orange), lineWidth: 1.5)
    }
  }

  private func draw(
    _ annotation: SimulatedLearningAnnotation,
    in context: inout GraphicsContext,
    transform: CameraPixelToViewTransform
  ) {
    let style = annotationStyle(for: annotation.kind)
    let stroke = SwiftUI.StrokeStyle(lineWidth: style.width, dash: style.dash)
    switch annotation.geometry {
    case .point(let point):
      let center = transform.point(point)
      let radius = max(3, transform.scale * 1.5)
      context.stroke(
        Path(
          ellipseIn: CGRect(
            x: center.x - radius,
            y: center.y - radius,
            width: radius * 2,
            height: radius * 2
          )),
        with: .color(style.color),
        style: stroke
      )
    case .bounds(let bounds):
      guard let min = try? Point2<CameraPixelSpace>(x: bounds.minX, y: bounds.minY),
        let max = try? Point2<CameraPixelSpace>(x: bounds.maxX, y: bounds.maxY)
      else { return }
      let minimum = transform.point(min)
      let maximum = transform.point(max)
      context.stroke(
        Path(
          CGRect(
            x: minimum.x,
            y: minimum.y,
            width: maximum.x - minimum.x,
            height: maximum.y - minimum.y
          )),
        with: .color(style.color),
        style: stroke
      )
    case .polyline(let polyline):
      var path = Path()
      path.move(to: transform.point(polyline.start))
      for point in polyline.points.dropFirst() {
        path.addLine(to: transform.point(point))
      }
      context.stroke(path, with: .color(style.color), style: stroke)
    }
    // Ink and trail annotations can contain one item per segment. Labelling
    // every segment obscures the geometry, especially calibration circles.
    if annotation.kind == .ink || annotation.kind == .recentMotionTrail { return }
    context.draw(
      Text(annotation.visibleLabel)
        .font(.caption2.monospaced().bold())
        .foregroundStyle(style.color),
      at: transform.point(annotation.anchor),
      anchor: annotation.kind == .currentCapAnchor ? .topLeading : .bottomLeading
    )
  }

  private func annotationStyle(
    for kind: SimulatedLearningAnnotationKind
  ) -> (color: Color, width: CGFloat, dash: [CGFloat]) {
    switch kind {
    case .truthEnvelope, .directionLabel:
      return (.orange, 2, [8, 5])
    case .acceptedLearnedSide, .learnedCenter:
      return (.cyan, 3, [])
    case .currentCapAnchor:
      return (.green, 2.5, [])
    case .recentMotionTrail:
      return (.white.opacity(0.75), 1.5, [3, 3])
    case .currentOperation:
      return (.red, 3, [])
    case .ink:
      return (.blue, 2, [])
    }
  }

  private func draw(
    _ overlay: CameraOverlayMeasurement,
    in context: inout GraphicsContext,
    transform: CameraPixelToViewTransform
  ) {
    switch overlay.geometry {
    case let .point(point):
      let style = lineStyle(for: overlay.provenance.kind)
      let center = transform.point(point)
      let radius = max(3, transform.scale * 2)
      let rect = CGRect(
        x: center.x - radius,
        y: center.y - radius,
        width: radius * 2,
        height: radius * 2
      )
      context.stroke(Path(ellipseIn: rect), with: .color(style.color), lineWidth: style.width)
    case let .bounds(bounds):
      guard
        let minimumCamera = try? Point2<CameraPixelSpace>(x: bounds.minX, y: bounds.minY),
        let maximumCamera = try? Point2<CameraPixelSpace>(x: bounds.maxX, y: bounds.maxY)
      else { return }
      let minimum = transform.point(minimumCamera)
      let maximum = transform.point(maximumCamera)
      let style = lineStyle(for: overlay.provenance.kind)
      context.stroke(
        Path(
          CGRect(
            x: minimum.x,
            y: minimum.y,
            width: maximum.x - minimum.x,
            height: maximum.y - minimum.y
          )
        ),
        with: .color(style.color),
        style: SwiftUI.StrokeStyle(lineWidth: style.width, dash: style.dash)
      )
    case let .polyline(polyline):
      var path = Path()
      path.move(to: transform.point(polyline.start))
      for point in polyline.points.dropFirst() {
        path.addLine(to: transform.point(point))
      }
      let style = lineStyle(for: overlay.provenance.kind)
      context.stroke(
        path,
        with: .color(style.color),
        style: SwiftUI.StrokeStyle(lineWidth: style.width, dash: style.dash)
      )
    }
    if let label = ActionSurfaceOverlayPresentationGrammar.semanticLabel(
      for: overlay.provenance.kind
    ),
      let anchor = overlayLabelAnchor(overlay.geometry)
    {
      let style = lineStyle(for: overlay.provenance.kind)
      context.draw(
        Text(label)
          .font(.caption2.monospaced().bold())
          .foregroundStyle(style.color),
        at: transform.point(anchor),
        anchor: .bottomLeading
      )
    }
  }

  private func overlayLabelAnchor(
    _ geometry: CameraPixelGeometry
  ) -> Point2<CameraPixelSpace>? {
    switch geometry {
    case .point(let point): point
    case .bounds(let bounds):
      try? Point2(x: bounds.minX, y: bounds.minY)
    case .polyline(let polyline): polyline.start
    }
  }

  private func lineStyle(
    for kind: CameraOverlayKind
  ) -> (color: Color, width: CGFloat, dash: [CGFloat]) {
    switch kind {
    case .intendedPath:
      return (.cyan, 2, [])
    case .calibrationGuide:
      return (.purple, 1.5, [5, 4])
    case .observedInk:
      return (.white, 3, [])
    case .residual:
      return (.orange, 1.5, [])
    case .acceptedBoundary:
      return (.orange, 2.5, [12, 6])
    case .drawingBorder:
      return (.blue, 2.5, [9, 5])
    case .paperCoverage:
      return (.mint, 2, [4, 3])
    case .predictedContactPoint:
      return (.secondary, 1.5, [3, 3])
    case .penCap:
      return (.yellow, 2, [])
    case .armatureEstimate:
      return (.green, 2.5, [7, 4])
    case .diagnostic:
      return (.gray, 1.5, [3, 3])
    }
  }
}
