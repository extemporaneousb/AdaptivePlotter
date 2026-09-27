import PlotterModel
import SwiftUI

/// The run's immutable plan owns its preview through terminal review. An idle
/// draft may instead expose an explicitly unplaced source reference.
enum DrawingStudioPreview: Hashable, Sendable {
  case planned(ExecutionPlanRevision, retained: Bool)
  case reference(DrawingProgram)

  static func resolve(draftProgram: DrawingProgram?, draftPlan: ExecutionPlanRevision?,
    retainedPlan: ExecutionPlanRevision?, runOwnsPlan: Bool) -> Self? {
    if runOwnsPlan { return retainedPlan.map { .planned($0, retained: true) } }
    if let draftPlan { return .planned(draftPlan, retained: false) }
    return draftProgram.map(Self.reference)
  }

  var plan: ExecutionPlanRevision? {
    guard case .planned(let plan, _) = self else { return nil }
    return plan
  }

  var title: String {
    switch self {
    case .planned(_, true): "Run drawing"
    case .planned(_, false): "Planned drawing"
    case .reference: "Reference drawing"
    }
  }

  var detail: String {
    switch self {
    case .planned(_, true):
      "The exact drawing retained by this run, including placement and any selected drawing frame. Later Studio edits do not replace it. The outer outline is the learned machine Boundary. This preview is not evidence that ink was deposited."
    case .planned(_, false):
      "The current planned drawing, including placement and any selected drawing frame. The outer outline is the learned machine Boundary. Draw uses this plan after its prerequisites are satisfied. This preview does not establish physical dimensions or pen contact."
    case .reference:
      "The authored drawing before placement is available. This reference is fitted for viewing and does not show an admitted drawing size or location."
    }
  }

  var plane: PortraitPlanePreview {
    switch self {
    case .planned(let plan, _): .planned(plan)
    case .reference(let program):
      PortraitPlanePreviewSource().resolve(program: program,
        nominalWidth: program.strokes.first?.style.nominalLineWidth ?? 0.4)
    }
  }
}

/// The same production preview remains outside the Drawing controls' scroller.
struct DrawingStudioPlanPreviewView: View {
  let preview: DrawingStudioPreview
  let imageHeight: CGFloat

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack {
        Text(preview.title).font(.headline)
        StudioHelpButton(preview.title, text: preview.detail)
      }
      PortraitPlaneProgramPreview(preview: preview.plane)
        .frame(height: imageHeight)
        .accessibilityLabel(preview.title)
        .accessibilityIdentifier("drawing.planPreview")
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("drawing.previewSection")
  }
}
