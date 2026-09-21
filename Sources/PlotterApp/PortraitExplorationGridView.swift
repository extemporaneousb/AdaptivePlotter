import PlotterModel
import SwiftUI

/// The round is immutable while selectable. Buttons capture its identity, so a
/// release from an earlier displayed round cannot choose a later slot's result.
struct PortraitExplorationGridView<SourcePreview: View>: View {
  let model: PortraitStudioModel
  let strokeStyle: PlotterModel.StrokeStyle
  var material: DrawingMaterialProfileRevision?
  @Binding var showsSource: Bool
  @ViewBuilder var sourcePreview: () -> SourcePreview

  var body: some View {
    let round = model.explorationRound
    VStack(spacing: 6) {
      HStack(spacing: 8) {
        Text("Imaginations").font(.headline)
        Spacer(minLength: 0)
        Button {
          WorkbenchRequestTelemetry.nativeActionHandled("portrait.exploration.back")
          model.goBackExploration()
        } label: {
          Label("Back", systemImage: "arrow.uturn.backward")
        }
        .disabled(!model.canGoBackExploration || model.isCapturing)
        .accessibilityIdentifier("portrait.exploration.back")
        .help("Restore the previous grid and its variation")
        Button { showsSource.toggle() } label: {
          Label("Source", systemImage: "photo")
        }
        .accessibilityIdentifier("portrait.sourceToggle")
        .help("Show the source photo or camera preview")
        .popover(isPresented: $showsSource, arrowEdge: .bottom) {
          VStack(alignment: .leading, spacing: 8) {
            Text("Source").font(.headline)
            sourcePreview()
              .frame(width: 330, height: 360)
              .clipShape(RoundedRectangle(cornerRadius: 6))
          }
          .padding(12)
          .accessibilityIdentifier("portrait.sourceFrame")
        }
      }
      .controlSize(.small)
      PortraitAdjustmentSlider("Variation", value: Binding(
        get: { model.explorationVariation * 100 },
        set: { model.setExplorationVariation($0 / 100, strokeStyle: strokeStyle) }),
        range: 0...100, step: 1, unit: "%", precision: 0,
        identifier: "portrait.exploration.variation")
        .disabled(model.selectedCandidate == nil || model.isCapturing || model.isProcessing)
        .help("Spread of the eight alternatives. Changes on release and leaves the current drawing unchanged.")
      GeometryReader { geometry in
        let tileWidth = max(0, (geometry.size.width - 12) / 3)
        let tileHeight = max(0, (geometry.size.height - 12) / 3)
        VStack(spacing: 6) {
          ForEach(0..<3, id: \.self) { row in
            HStack(spacing: 6) {
              ForEach(0..<3, id: \.self) { column in
                let index = row * 3 + column
                let slot = round?.slots.first { $0.index == index }
                let candidate = index == 4 ? (round?.center ?? model.selectedCandidate) : slot?.candidate
                PortraitExplorationTileView(candidate: candidate,
                  previewSource: PortraitPlanePreviewSource(material: material),
                  nominalWidth: strokeStyle.nominalLineWidth,
                  index: index, isLoading: model.isExploring || model.isProcessing,
                  unavailableReason: slot?.unavailableReason,
                  canSelect: round != nil && candidate != nil && !model.isExploring
                    && !model.isProcessing && !model.isCapturing) {
                    guard let round else { return }
                    WorkbenchRequestTelemetry.nativeActionHandled("portrait.exploration.slot.\(index)")
                    model.chooseExplorationSlot(index, roundID: round.id, strokeStyle: strokeStyle)
                  }
                  .frame(width: tileWidth, height: tileHeight)
              }
            }
          }
        }
        // A new offer replaces the button identities as a unit. A press begun
        // on a discarded offer cannot finish on a new candidate in that slot.
        .id(round?.id)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("portrait.exploration.grid")
  }
}

private struct PortraitExplorationTileView: View {
  let candidate: PortraitCandidate?
  let previewSource: PortraitPlanePreviewSource
  let nominalWidth: Double
  let index: Int
  let isLoading: Bool
  let unavailableReason: String?
  let canSelect: Bool
  let select: () -> Void

  private var title: String { index == 4 ? "Current" : "Option \(index < 4 ? index + 1 : index)" }
  private var detail: String {
    if let unavailableReason { return unavailableReason }
    if candidate != nil {
      return index == 4 ? "Keep this drawing and show new alternatives" : "Use this exact drawing and show new alternatives"
    }
    return isLoading ? "Generating alternatives" : "Choose or capture a photo to explore drawings"
  }

  var body: some View {
    Button(action: select) {
      VStack(spacing: 2) {
        Group {
          if let candidate {
            PortraitPlaneProgramPreview(preview: previewSource.resolve(
              program: candidate.program, nominalWidth: nominalWidth))
          } else if isLoading {
            ProgressView().controlSize(.small)
              .frame(maxWidth: .infinity, maxHeight: .infinity)
          } else {
            Image(systemName: unavailableReason == nil ? "photo" : "exclamationmark.circle")
              .foregroundStyle(.secondary)
              .frame(maxWidth: .infinity, maxHeight: .infinity)
          }
        }
        .accessibilityHidden(true)
        Text(unavailableReason == nil ? title : "Unavailable")
          .font(.caption2)
          .foregroundStyle(index == 4 ? Color.primary : .secondary)
          .lineLimit(1)
      }
      .padding(4)
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .background(.background, in: RoundedRectangle(cornerRadius: 6))
      .overlay {
        RoundedRectangle(cornerRadius: 6)
          .stroke(index == 4 ? Color.accentColor : .secondary.opacity(0.25), lineWidth: index == 4 ? 2 : 1)
      }
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .disabled(!canSelect)
    .accessibilityLabel(index == 4 ? "Current drawing; show new alternatives" : "Select \(title.lowercased())")
    .accessibilityValue(unavailableReason ?? (candidate == nil ? (isLoading ? "Generating" : "No drawing") : title))
    .accessibilityIdentifier("portrait.exploration.slot.\(index)")
    .help(detail)
  }
}
