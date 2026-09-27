import Foundation
import PlotterEpisodeRuntime
import PlotterModel
import PlotterRuntime
import SwiftUI

/// Copied, already-admitted drawing inputs. Equality compares only visible
/// output, never frame counters, artifact hashes, or diagnostic metadata.
struct ActionSurfaceOverlayContent: Equatable, Sendable {
  struct FrameContext: Equatable, Sendable {
    let source: FrameSourceIdentity
    let configuration: CameraConfigurationID
    let width: Int
    let height: Int
    let pixelFormat: FramePixelFormat
  }

  let frameContext: FrameContext?
  let allowsLiveGeometryTolerance: Bool
  let targetPreview: DrawingStudioTargetPreview?
  var overlays: [CameraOverlayMeasurement]
  var analyzedOverlayFrame: ExactFrameOverlayProvenance?
  let tipReview: ActionSurfaceTipReviewGeometry?
  let clickMarkers: [Point2<CameraPixelSpace>]
  let simulatedAnnotations: [SimulatedLearningAnnotation]

  init(presentation: ActionSurfacePresentation, stagedFrame: PlotterDrawingDraftFrame? = nil) {
    frameContext = presentation.displayedFrame.map {
      FrameContext(source: $0.source, configuration: $0.frame.cameraConfigurationID,
        width: $0.frame.width, height: $0.frame.height, pixelFormat: $0.frame.pixelFormat)
    }
    if case .live = presentation.displayedFrame?.source {
      allowsLiveGeometryTolerance = presentation.usesAmbientPreviewFrame
        && presentation.pointSelectionRequest == nil
        && presentation.tipPresentation.interactionPrompt == nil
    } else {
      allowsLiveGeometryTolerance = false
    }
    let preview = presentation.drawingStudioCanvas?.targetPreview(for: presentation.displayedFrame)
    if let stagedFrame, let original = presentation.drawingStudioCanvas?.frame, let preview,
      let center = try? original.cameraCenter, let nextCenter = try? stagedFrame.cameraCenter {
      let ratio = stagedFrame.geometry.placement.uniformScale / original.geometry.placement.uniformScale
      let strokes = try? preview.strokes.map { stroke in
        try Polyline<CameraPixelSpace>(points: stroke.points.map {
          try Point2(x: nextCenter.x + ($0.x - center.x) * ratio,
            y: nextCenter.y + ($0.y - center.y) * ratio)
        })
      }
      targetPreview = strokes.map { DrawingStudioTargetPreview(provenance: preview.provenance,
        strokes: $0, bounds: nil, programContentHash: preview.programContentHash,
        executionPlanContentHash: nil, status: preview.status,
        showsStrokeBounds: false) }
    } else { targetPreview = preview }
    overlays = presentation.renderedOverlays
    analyzedOverlayFrame = presentation.analyzedOverlayFrame
    tipReview = presentation.tipPresentation.reviewGeometry
    clickMarkers = presentation.tipPresentation.clickMarkers
    simulatedAnnotations = presentation.simulatedAnnotationsAreVisible
      ? presentation.simulatedAnnotations : []
  }

  static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.frameContext == rhs.frameContext
      && lhs.allowsLiveGeometryTolerance == rhs.allowsLiveGeometryTolerance
      && targetsDrawIdentically(lhs.targetPreview, rhs.targetPreview)
      && lhs.overlays.count == rhs.overlays.count
      && zip(lhs.overlays, rhs.overlays).allSatisfy {
        $0.geometry == $1.geometry && $0.provenance.kind == $1.provenance.kind
      }
      && lhs.tipReview == rhs.tipReview
      && lhs.clickMarkers == rhs.clickMarkers
      && lhs.simulatedAnnotations.count == rhs.simulatedAnnotations.count
      && zip(lhs.simulatedAnnotations, rhs.simulatedAnnotations).allSatisfy {
        $0.kind == $1.kind && $0.geometry == $1.geometry && $0.anchor == $1.anchor
          && $0.visibleLabel == $1.visibleLabel
      }
  }

  private static func targetsDrawIdentically(
    _ lhs: DrawingStudioTargetPreview?, _ rhs: DrawingStudioTargetPreview?
  ) -> Bool {
    switch (lhs, rhs) {
    case (nil, nil): true
    case (.some(let lhs), .some(let rhs)):
      lhs.strokes == rhs.strokes && lhs.bounds == rhs.bounds && lhs.showsStrokeBounds == rhs.showsStrokeBounds
        && (lhs.status == .ready) == (rhs.status == .ready)
    default: false
    }
  }
}

/// One retained presentation, compared against the last displayed geometry.
/// A deadband inside Equatable would be nontransitive and could lose gradual
/// movement. This cache applies hysteresis first, then Canvas uses exact visual
/// equality. It never alters measurements, frame bytes, or click transforms.
@MainActor
final class ActionSurfaceOverlayContentCache: ObservableObject {
  static let liveGeometryTolerancePoints = 8.0
  private var retained: ActionSurfaceOverlayContent?
  private var retainedTransform: CameraPixelToViewTransform?

  func resolve(
    _ incoming: ActionSurfaceOverlayContent,
    transform: CameraPixelToViewTransform?
  ) -> ActionSurfaceOverlayContent {
    var result = incoming
    defer {
      retained = result
      retainedTransform = transform
    }
    guard incoming.allowsLiveGeometryTolerance,
      let retained, retained.allowsLiveGeometryTolerance,
      incoming.frameContext == retained.frameContext,
      let transform, transform == retainedTransform,
      incoming.overlays.count == retained.overlays.count
    else { return result }

    let indices = incoming.overlays.indices.filter {
      Self.isPassiveSceneGeometry(incoming.overlays[$0])
    }
    guard !indices.isEmpty,
      indices == retained.overlays.indices.filter({ Self.isPassiveSceneGeometry(retained.overlays[$0]) }),
      indices.allSatisfy({ index in
        let next = incoming.overlays[index]
        let prior = retained.overlays[index]
        return next.provenance == prior.provenance
          && Self.geometry(prior.geometry, isWithinToleranceOf: next.geometry, scale: transform.scale)
      })
    else { return result }

    // Keep the scene group together, with its original frame provenance and
    // displayed-measurement caption. Other geometry remains fully current.
    for index in indices { result.overlays[index] = retained.overlays[index] }
    result.analyzedOverlayFrame = retained.analyzedOverlayFrame
    return result
  }

  private static func isPassiveSceneGeometry(_ overlay: CameraOverlayMeasurement) -> Bool {
    (overlay.provenance.kind == .penCap || overlay.provenance.kind == .armatureEstimate)
      && (overlay.provenance.source == .measured || overlay.provenance.source == .inferred)
  }

  private static func geometry(
    _ lhs: CameraPixelGeometry,
    isWithinToleranceOf rhs: CameraPixelGeometry,
    scale: Double
  ) -> Bool {
    func close(_ dx: Double, _ dy: Double) -> Bool {
      hypot(dx, dy) * scale <= liveGeometryTolerancePoints
    }
    switch (lhs, rhs) {
    case (.point(let lhs), .point(let rhs)):
      return close(lhs.x - rhs.x, lhs.y - rhs.y)
    case (.bounds(let lhs), .bounds(let rhs)):
      return close(max(abs(lhs.minX - rhs.minX), abs(lhs.maxX - rhs.maxX)),
        max(abs(lhs.minY - rhs.minY), abs(lhs.maxY - rhs.maxY)))
    case (.polyline(let lhs), .polyline(let rhs)):
      return lhs.points.count == rhs.points.count
        && zip(lhs.points, rhs.points).allSatisfy { close($0.x - $1.x, $0.y - $1.y) }
    default:
      return false
    }
  }
}
