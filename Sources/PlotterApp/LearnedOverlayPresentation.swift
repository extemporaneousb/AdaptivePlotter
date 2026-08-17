import PlotterRuntime

enum ActionSurfaceOverlayStyleToken: Hashable, Sendable {
  case intendedCyan
  case observedWhite
  case residualOrange
  case drawableRegionBlueDashed
  case paperCoverageMintDashed
  case predictedContactPurple
  case penCapYellow
  case inferredArmatureGreenDashed
  case diagnosticGrayDashed
}

enum ActionSurfaceOverlayPresentationGrammar {
  static func semanticLabel(for kind: CameraOverlayKind) -> String? {
    switch kind {
    case .calibratedDrawableRegion: "CALIBRATED DRAWABLE REGION"
    case .paperCoverage: "CURRENT PAPER COVERAGE"
    case .predictedContactPoint: "PREDICTED CONTACT POINT · NOT OBSERVED"
    case .intendedPath, .observedInk, .residual, .penCap, .armatureEstimate, .diagnostic:
      nil
    }
  }

  static func styleToken(for kind: CameraOverlayKind) -> ActionSurfaceOverlayStyleToken {
    switch kind {
    case .intendedPath: .intendedCyan
    case .observedInk: .observedWhite
    case .residual: .residualOrange
    case .calibratedDrawableRegion: .drawableRegionBlueDashed
    case .paperCoverage: .paperCoverageMintDashed
    case .predictedContactPoint: .predictedContactPurple
    case .penCap: .penCapYellow
    case .armatureEstimate: .inferredArmatureGreenDashed
    case .diagnostic: .diagnosticGrayDashed
    }
  }
}
