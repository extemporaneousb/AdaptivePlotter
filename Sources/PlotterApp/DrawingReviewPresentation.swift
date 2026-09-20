import PlotterModel

/// Presentation only: retained planned paths never assert controller completion
/// or observed ink, and no current Draft or calibration participates.
struct DrawingReviewGeometry {
  let title: String
  let explanation: String
  let preview: PortraitPlanePreview

  static let unavailableExplanation = "Geometry unavailable: this historical result retains neither an execution plan nor its source program."

  static func resolve(plan: ExecutionPlanRevision?, sourceProgram: DrawingProgram?) -> Self? {
    if let plan {
      return Self(title: "Retained execution plan",
        explanation: "Planned paths and placement retained with this result; not evidence of observed ink.",
        preview: .planned(plan))
    }
    guard let sourceProgram else { return nil }
    return Self(title: "Source reference",
      explanation: "Source program only; historical execution placement and clipping are unavailable.",
      preview: PortraitPlanePreviewSource().resolve(program: sourceProgram,
        nominalWidth: sourceProgram.strokes.first?.style.nominalLineWidth ?? 0.4))
  }

  static func photographExplanation(referenceCount: Int?, failed: Bool) -> String {
    guard let referenceCount else {
      return "This historical result has no retained photograph references. Planned geometry is not a photograph."
    }
    guard referenceCount > 0 else { return "No photograph was retained for this stage of the attempt." }
    return failed ? "The retained photograph could not be loaded. See the image error below."
      : "The retained photograph is unavailable."
  }
}
