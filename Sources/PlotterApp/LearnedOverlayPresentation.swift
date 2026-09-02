import PlotterRuntime

enum ActionSurfaceOverlayPresentationGrammar {
  static func semanticLabel(for kind: CameraOverlayKind) -> String? {
    switch kind {
    case .acceptedBoundary: LearningPathTerminology.Evidence.acceptedDrawingBoundaryOverlay
    case .drawingBorder: LearningPathTerminology.Evidence.drawingBorderOverlay
    case .paperCoverage: "CURRENT PAPER COVERAGE"
    case .predictedContactPoint: "PREDICTED CONTACT POINT · NOT OBSERVED"
    case .intendedPath, .observedInk, .residual, .penCap, .armatureEstimate, .diagnostic:
      nil
    }
  }
}
