import CoreGraphics
import PlotterEpisodeModel
import PlotterModel

/// Presentation-only gesture ownership. Exact point selection always outranks
/// drawing placement; navigation never submits either kind of edit.
enum ActionSurfaceDragIntent: Equatable {
  case reference, drawing, pan, locked

  static func resolve(
    presentation: ActionSurfacePresentation,
    drawsReference: Bool,
    movesDrawing: Bool
  ) -> Self {
    if presentation.pointSelectionRequest?.purpose == .penCapAppearance,
      presentation.pointSelectionRequest?.referenceMode != .sampledColorMarker, drawsReference {
      return .reference
    }
    if presentation.pointSelectionRequest == nil, movesDrawing,
      presentation.drawingStudioCanvas?.placement.placementIsEnabled == true {
      return .drawing
    }
    return presentation.analysisRegionIsLocked ? .locked : .pan
  }
}

enum ActionSurfacePointStagingResult: Equatable {
  case ignored
  case refused(String)
  case staged(PlotterPointSelectionSubmission)
}

enum ActionSurfacePointStaging {
  static func stage(
    presentation: ActionSurfacePresentation,
    viewport: ActionSurfaceViewportState,
    at location: CGPoint,
    viewSize: CGSize,
    referenceRegion: AxisAlignedBounds<CameraPixelSpace>?
  ) -> ActionSurfacePointStagingResult {
    guard let request = presentation.pointSelectionRequest else { return .ignored }
    if request.purpose == .penCapAppearance, request.referenceMode != .sampledColorMarker,
      referenceRegion == nil, request.referenceGeometry == nil {
      return .refused("Draw a compact reference on the fixed moving holder, then click a distinct landmark on that same surface.")
    }
    guard var submission = ExactFramePointSubmissionBuilder.submission(
      presentation: presentation, viewport: viewport, at: location, viewSize: viewSize,
      referenceRegion: request.purpose == .penCapAppearance && request.referenceMode != .sampledColorMarker
        ? referenceRegion : nil
    ), presentation.acceptsPendingPointSelection(submission) else {
      return .refused("Click inside the frozen camera image. If it has changed, restart this selection.")
    }
    if request.purpose == .penCapAppearance, request.referenceMode != .sampledColorMarker, referenceRegion == nil,
      let geometry = request.referenceGeometry {
      guard let translated = geometry.region(around: submission.point),
        translated.minX >= 0, translated.minY >= 0,
        translated.maxX <= Double(request.frame.width),
        translated.maxY <= Double(request.frame.height) else {
        return .refused("The retained reference extends outside this frame. Draw a smaller reference around the cap.")
      }
      submission = PlotterPointSelectionSubmission(selectionID: submission.selectionID,
        frame: submission.frame, point: submission.point,
        presentationTransformRevision: submission.presentationTransformRevision,
        referenceRegion: translated)
    }
    if request.purpose == .penCapAppearance, request.referenceMode != .sampledColorMarker, let referenceRegion,
      !(submission.point.x >= referenceRegion.minX && submission.point.x < referenceRegion.maxX
        && submission.point.y >= referenceRegion.minY && submission.point.y < referenceRegion.maxY) {
      return .refused("Click the cap inside the reference rectangle, or choose Redraw Reference.")
    }
    return .staged(submission)
  }
}
