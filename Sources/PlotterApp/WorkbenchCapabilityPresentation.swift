/// A product-capability statement copied from the current artifact owners.
///
/// This value is presentation only. Its cases deliberately do not form an
/// authorization ladder: controller admission remains owned by the runtime.
enum WorkbenchLearningCapabilityState: CaseIterable, Hashable, Sendable {
  case learningNeeded
  case savedMapNeedsRevalidation
  case mapReady
  case interactiveLearningComplete
  case adaptiveDrawingReady

  var title: String {
    switch self {
    case .learningNeeded: "Pen-tip calibration required"
    case .savedMapNeedsRevalidation: "Saved calibration needs revalidation"
    case .mapReady: "Pen-tip calibration ready"
    case .interactiveLearningComplete:
      "Learning complete"
    case .adaptiveDrawingReady: "Adaptive drawing ready"
    }
  }

  var detail: String {
    switch self {
    case .learningNeeded:
      "No current accepted pen-tip calibration is available."
    case .savedMapNeedsRevalidation:
      "The saved pen-tip calibration cannot be used until its current applicability is explicitly revalidated."
    case .mapReady:
      "The current accepted pen-tip calibration is available; Drawing Border validation is still pending."
    case .interactiveLearningComplete:
      "The calibrated Drawing Border trial completed. Its observation quality is retained separately; adaptive readiness is not established."
    case .adaptiveDrawingReady:
      "The current drawing-readiness assessment is accepted for its declared scope."
    }
  }
}

/// Paper status is independent from learned model status. A current map never
/// implies that a drawable sheet is present in the camera view.
enum WorkbenchPaperSetupState: Hashable, Sendable {
  case setupRequired(reason: String)
  case current(detail: String)

  var title: String {
    switch self {
    case .setupRequired: "Paper setup required"
    case .current: "Paper current"
    }
  }

  var detail: String {
    switch self {
    case .setupRequired(let reason), .current(let reason): reason
    }
  }

}

struct WorkbenchCapabilityPresentation: Hashable, Sendable {
  let learning: WorkbenchLearningCapabilityState
  let paper: WorkbenchPaperSetupState

  var accessibilityValue: String {
    "\(learning.title). \(learning.detail) \(paper.title). \(paper.detail)"
  }
}
