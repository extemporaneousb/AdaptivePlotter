import PlotterModel
import SwiftUI

/// Each published slot owns an immutable candidate while its partner completes.
/// Buttons capture the round identity so stale clicks cannot select a later offer.
struct PortraitExplorationGridView<SourcePreview: View>: View {
  @Bindable var model: PortraitStudioModel
  let strokeStyle: PlotterModel.StrokeStyle
  var material: DrawingMaterialProfileRevision?
  @Binding var showsSource: Bool
  @ViewBuilder var sourcePreview: () -> SourcePreview

  var body: some View {
    let round = model.displayedExplorationRound
    let displayID = model.explorationDisplayID
    VStack(spacing: 6) {
      HStack(spacing: 8) {
        Text("Imaginations").font(.headline)
        StudioHelpButton("Browsing performance", text: model.browserTimingSummary)
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
          model.exploreSelection(strokeStyle: strokeStyle)
        } label: {
          Label("New options", systemImage: "arrow.clockwise")
        }
        .disabled(model.selectedCandidate == nil || model.isExploring || model.isCapturing || model.isProcessing)
        .accessibilityIdentifier("portrait.exploration.resample")
        .labelStyle(.iconOnly)
        .help("Generate two new options")
        Button { showsSource.toggle() } label: {
          Label(model.browsablePhotos.isEmpty ? "Source" : "Photos \(model.browsablePhotos.count)", systemImage: "photo")
        }
        .accessibilityIdentifier("portrait.sourceToggle")
        .help("Show the source photo or camera preview")
        .popover(isPresented: $showsSource, arrowEdge: .bottom) {
          VStack(alignment: .leading, spacing: 8) {
            Text("Source").font(.headline)
            sourcePreview()
              .frame(width: 330, height: 360)
              .clipShape(RoundedRectangle(cornerRadius: 6))
            if !model.browsablePhotos.isEmpty {
              PortraitPhotoStrip(model: model, strokeStyle: strokeStyle).frame(width: 330)
            }
          }
          .padding(12)
          .accessibilityIdentifier("portrait.sourceFrame")
        }
      }
      .controlSize(.small)
      HStack(spacing: 6) {
        Text("Explore").font(.caption).foregroundStyle(.secondary)
        Picker("Explore region", selection: $model.explorationRegion) {
          Text("Whole drawing").tag(Optional<PortraitTreatmentRegion>.none)
          ForEach(PortraitTreatmentRegion.allCases) { region in
            Text(region.rawValue).tag(Optional(region))
          }
        }.labelsHidden().controlSize(.small)
          .accessibilityIdentifier("portrait.exploration.region")
        Spacer(minLength: 0)
      }
      GeometryReader { geometry in
        HStack(spacing: 8) {
          ForEach(0..<PortraitExplorationPolicy.slotCount, id: \.self) { index in
            let slot = round?.slots.first { $0.index == index }
            let isCurrent = index == PortraitExplorationPolicy.centerIndex
            let candidate = isCurrent ? (round?.center ?? model.selectedCandidate) : slot?.candidate
            VStack(spacing: 4) {
            PortraitExplorationTileView(candidate: candidate,
              previewSource: PortraitPlanePreviewSource(material: material),
              nominalWidth: strokeStyle.nominalLineWidth,
              index: index, isLoading: model.isExploring || model.isProcessing,
              unavailableReason: slot?.unavailableReason, failureKind: slot?.failureKind, isPrevious: slot?.isPrevious ?? false,
              canSelect: displayID != nil && candidate != nil
                && !model.isProcessing && !model.isCapturing) {
                guard let displayID else { return }
                WorkbenchRequestTelemetry.nativeActionHandled("portrait.exploration.slot.\(index)")
                model.chooseExplorationSlot(index, roundID: displayID, strokeStyle: strokeStyle)
              }
            VStack(spacing: 2) {
              if let candidate {
                PortraitAttemptFeedbackButtons(model: model, candidate: candidate).frame(height: 16)
                Text(model.burdenSummary(for: candidate).replacingOccurrences(of: " drawing-heights of ink path", with: "×height"))
                  .font(.caption2).foregroundStyle(.secondary).lineLimit(1).frame(height: 12)
                  .help(model.burdenSummary(for: candidate) + ". Ink path is normalized by drawing height; this is not a time estimate.")
                Text(isCurrent ? candidate.recipe.title
                  : (model.sketches.entries.first(where: { $0.id == candidate.id })?.attempt?.changeCue ?? "Treatment"))
                  .font(.caption2).foregroundStyle(.secondary).lineLimit(1).frame(height: 12)
              } else {
                Color.clear.frame(height: 44).accessibilityHidden(true)
              }
            }
            .frame(height: 44)
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
    .onPreferenceChange(PortraitExplorationImageSizes.self) { model.observeExplorationPreviewSizes($0) }
  }
}

private struct PortraitExplorationImageSizes: PreferenceKey {
  static let defaultValue: [Int: CGSize] = [:]
  static func reduce(value: inout [Int: CGSize], nextValue: () -> [Int: CGSize]) {
    value.merge(nextValue(), uniquingKeysWith: { _, new in new })
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
      return index == PortraitExplorationPolicy.centerIndex ? (isLoading ? "Keep this drawing while the options finish" : "Inspect this drawing and refine the options") : (isPrevious ? "Use this exact previously offered drawing" : "Use this exact drawing and show new alternatives")
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
        .frame(minHeight: 92)
        .background {
          GeometryReader { geometry in
            Color.clear.preference(key: PortraitExplorationImageSizes.self, value: [index: geometry.size])
          }
        }
        .accessibilityHidden(true)
        Text(candidate == nil && isLoading && (unavailableReason == nil || unavailableReason == "Generating")
          ? "Generating" : unavailableReason == nil ? (isPrevious ? "Previous option" : title)
          : (failureKind == .generationFailed ? "Generation failed" : "No new option"))
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
    .accessibilityLabel(index == PortraitExplorationPolicy.centerIndex ? "Inspect current drawing" : "Select \(title.lowercased())")
    .accessibilityValue(unavailableReason ?? (candidate == nil ? (isLoading ? "Generating" : "No drawing") : title))
    .accessibilityIdentifier("portrait.exploration.slot.\(index)")
    .help(detail)
  }
}

struct PortraitAttemptFeedbackButtons: View {
  let model: PortraitStudioModel
  let candidate: PortraitCandidate
  var body: some View {
    HStack(spacing: 10) {
      Button { model.toggleFeedback(.promising, candidate: candidate) } label: {
        Image(systemName: model.feedback(for: candidate) == .promising ? "plus.circle.fill" : "plus.circle")
      }
      .foregroundStyle(model.feedback(for: candidate) == .promising ? Color.green : .secondary)
      .help("Promising: retain this exact attempt. Click again to clear feedback.")
      .accessibilityLabel("Mark promising")
      .accessibilityIdentifier("portrait.feedback.plus.\(candidate.id)")
      Button { model.toggleFeedback(.rejected, candidate: candidate) } label: {
        Image(systemName: model.feedback(for: candidate) == .rejected ? "minus.circle.fill" : "minus.circle")
      }
      .foregroundStyle(model.feedback(for: candidate) == .rejected ? Color.orange : .secondary)
      .help("Reject this exact treatment without deleting it. Click again to clear feedback.")
      .accessibilityLabel("Mark rejected")
      .accessibilityIdentifier("portrait.feedback.minus.\(candidate.id)")
    }.buttonStyle(.plain)
  }
}
