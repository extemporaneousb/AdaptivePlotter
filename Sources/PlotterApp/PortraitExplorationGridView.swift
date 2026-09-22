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
    let displayID = model.explorationDisplayID
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
        .help("Restore the previous options and drawing")
        Button {
          guard let round else { return }
          model.resampleExploration(roundID: round.id, strokeStyle: strokeStyle)
        } label: {
          Label("New options", systemImage: "arrow.clockwise")
        }
        .disabled(round == nil || model.isExploring || model.isCapturing || model.isProcessing)
        .accessibilityIdentifier("portrait.exploration.resample")
        .labelStyle(.iconOnly)
        .help("Generate two new options")
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
      GeometryReader { geometry in
        HStack(spacing: 8) {
          ForEach(0..<PortraitExplorationPolicy.slotCount, id: \.self) { index in
            let slot = round?.slots.first { $0.index == index }
            let isCurrent = index == PortraitExplorationPolicy.centerIndex
            let candidate = isCurrent ? (round?.center ?? model.selectedCandidate) : slot?.candidate
            PortraitExplorationTileView(candidate: candidate,
              previewSource: PortraitPlanePreviewSource(material: material),
              nominalWidth: strokeStyle.nominalLineWidth,
              index: index, isLoading: model.isExploring || model.isProcessing,
              unavailableReason: slot?.unavailableReason, failureKind: slot?.failureKind, isPrevious: slot?.isPrevious ?? false,
              canSelect: displayID != nil && candidate != nil && (isCurrent || !model.isExploring)
                && !model.isProcessing && !model.isCapturing) {
                guard let displayID else { return }
                WorkbenchRequestTelemetry.nativeActionHandled("portrait.exploration.slot.\(index)")
                model.chooseExplorationSlot(index, roundID: displayID, strokeStyle: strokeStyle)
              }
              .frame(width: max(0, (geometry.size.width - 16) / 3), height: geometry.size.height)
          }
        }
        // One identity covers the pending and settled offer. Previously enabled
        // buttons can never resolve to a candidate from a different offer.
        .id(displayID)
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
  let failureKind: PortraitExplorationSlot.FailureKind?
  let isPrevious: Bool
  let canSelect: Bool
  let select: () -> Void

  private var title: String { index == PortraitExplorationPolicy.centerIndex ? "Current" : "Option \(index == 0 ? 1 : 2)" }
  private var detail: String {
    if let unavailableReason { return unavailableReason }
    if candidate != nil {
      return index == PortraitExplorationPolicy.centerIndex ? (isLoading ? "Keep this drawing while the options finish" : "Prefer this drawing and refine the options") : (isPrevious ? "Use this exact previously offered drawing" : "Use this exact drawing and show new alternatives")
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
            Image(systemName: unavailableReason == nil ? "photo" : (failureKind == .generationFailed ? "exclamationmark.triangle" : "arrow.clockwise"))
              .foregroundStyle(.secondary)
              .frame(maxWidth: .infinity, maxHeight: .infinity)
          }
        }
        .accessibilityHidden(true)
        Text(unavailableReason == nil ? (isPrevious ? "Previous option" : title) : (failureKind == .generationFailed ? "Generation failed" : "No new option"))
          .font(.caption2)
          .foregroundStyle(index == PortraitExplorationPolicy.centerIndex ? Color.primary : .secondary)
          .lineLimit(1)
      }
      .padding(4)
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .background(.background, in: RoundedRectangle(cornerRadius: 6))
      .overlay {
        RoundedRectangle(cornerRadius: 6)
          .stroke(index == PortraitExplorationPolicy.centerIndex ? Color.accentColor : .secondary.opacity(0.25), lineWidth: index == PortraitExplorationPolicy.centerIndex ? 2 : 1)
      }
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .disabled(!canSelect)
    .accessibilityLabel(index == PortraitExplorationPolicy.centerIndex ? "Keep current drawing" : "Select \(title.lowercased())")
    .accessibilityValue(unavailableReason ?? (candidate == nil ? (isLoading ? "Generating" : "No drawing") : title))
    .accessibilityIdentifier("portrait.exploration.slot.\(index)")
    .help(detail)
  }
}
