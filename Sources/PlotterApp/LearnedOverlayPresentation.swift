import PlotterRuntime

enum ActionSurfaceOverlayPresentationGrammar {
  static func semanticLabel(for kind: CameraOverlayKind) -> String? {
    switch kind {
    case .calibrationGuide: nil
    case .acceptedBoundary: "MACHINE BOUNDARY"
    case .drawingRegion: "DRAWING REGION"
    case .drawingBorder: LearningPathTerminology.Evidence.drawingBorderOverlay
    case .paperCoverage: "CURRENT PAPER COVERAGE"
    case .predictedContactPoint: nil
    case .intendedPath, .observedInk, .residual, .penCap, .armatureEstimate, .diagnostic:
      nil
    }
  }
}
