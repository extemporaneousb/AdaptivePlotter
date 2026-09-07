import PlotterRuntime

enum ActionSurfaceOverlayPresentationGrammar {
  static func semanticLabel(for kind: CameraOverlayKind) -> String? {
    switch kind {
    case .acceptedBoundary: LearningPathTerminology.Evidence.acceptedDrawingBoundaryOverlay
    case .drawingBorder: LearningPathTerminology.Evidence.drawingBorderOverlay
    case .paperCoverage: "CURRENT PAPER COVERAGE"
    case .predictedContactPoint: nil
    case .intendedPath, .observedInk, .residual, .penCap, .armatureEstimate, .diagnostic:
      nil
    }
  }
}
