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
    if presentation.pointSelectionRequest?.purpose == .penCapAppearance, drawsReference {
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
    if request.purpose == .penCapAppearance, referenceRegion == nil {
      return .refused("Draw a reference around the cap and co-moving holder, then click the cap inside it.")
    }
    guard let submission = ExactFramePointSubmissionBuilder.submission(
      presentation: presentation, viewport: viewport, at: location, viewSize: viewSize,
      referenceRegion: request.purpose == .penCapAppearance ? referenceRegion : nil
    ), presentation.acceptsPendingPointSelection(submission) else {
      return .refused("Click inside the frozen camera image. If it has changed, restart this selection.")
    }
    if request.purpose == .penCapAppearance, let referenceRegion,
      !(submission.point.x >= referenceRegion.minX && submission.point.x < referenceRegion.maxX
        && submission.point.y >= referenceRegion.minY && submission.point.y < referenceRegion.maxY) {
      return .refused("Click the cap inside the reference rectangle, or choose Redraw Reference.")
    }
    return .staged(submission)
  }
}
