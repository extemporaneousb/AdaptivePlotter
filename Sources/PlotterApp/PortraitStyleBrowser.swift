import PlotterModel
import SwiftUI

/// The five algorithm tiles display the exact candidates selected by a click.
struct PortraitStyleBrowser: View {
  let model: PortraitStudioModel
  let strokeStyle: PlotterModel.StrokeStyle
  var material: DrawingMaterialProfileRevision?

  var body: some View {
    HStack(spacing: 8) {
      ForEach(PortraitStyle.allCases) { style in
        let candidate = model.algorithmCandidates.first { $0.recipe.style == style }
        Button {
          WorkbenchRequestTelemetry.nativeActionHandled("portrait.algorithm.\(style.id)")
          model.selectAlgorithm(style, strokeStyle: strokeStyle)
        } label: {
          VStack(spacing: 5) {
            PortraitPlaneProgramPreview(preview: PortraitPlanePreviewSource(material: material).resolve(
              program: candidate?.program, nominalWidth: strokeStyle.nominalLineWidth))
              .overlay {
                if candidate == nil && (model.isProcessing || model.isComparingAlgorithms) { ProgressView().controlSize(.small) }
              }
              .frame(maxWidth: .infinity, maxHeight: .infinity)
            Text(style.rawValue).font(.caption).lineLimit(1)
          }
          .padding(5)
          .background(.background, in: RoundedRectangle(cornerRadius: 6))
          .overlay {
            RoundedRectangle(cornerRadius: 6)
              .stroke(model.selectedAlgorithm == style ? Color.accentColor : Color.secondary.opacity(0.25),
                lineWidth: model.selectedAlgorithm == style ? 2 : 1)
          }
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(candidate == nil || model.isCapturing)
        .accessibilityLabel("Select \(style.rawValue) style")
        .accessibilityValue(model.selectedAlgorithm == style ? "Selected" : "")
        .accessibilityIdentifier("portrait.algorithm.\(style.id)")
      }
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("portrait.algorithms")
  }
}
