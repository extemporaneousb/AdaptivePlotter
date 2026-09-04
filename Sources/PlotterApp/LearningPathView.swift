import Foundation
import PlotterEpisodeModel
import PlotterRuntime
import PlotterUI
import SwiftUI

struct LearningPathNavigator: View {
  @Binding var selection: LearningPathSelectionState
  let projection: LearningPathProjection
  let currentLearningPathItemID: LearningPathItemID
  let plotterUIProjection: PlotterUIProjection
  let plotterUIIntentSink: any PlotterUIIntentSink
  let close: () -> Void
  @State private var pendingResetPlan: LearningVacatePlan?

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(alignment: .top, spacing: 8) {
        VStack(alignment: .leading, spacing: 5) {
          Text("Learning Path")
            .font(.title2.weight(.semibold))
          Text("Select a row to review it. Selection never starts or advances an exercise.")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        Spacer(minLength: 8)
        Menu {
          Button(role: .destructive) {
            pendingResetPlan = projection.menu.resetAllPlan
          } label: {
            Label("Reset All Learning…", systemImage: "arrow.counterclockwise")
          }
          .disabled(projection.menu.resetAllPlan == nil)
        } label: {
          Image(systemName: "ellipsis.circle")
            .font(.title3)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .accessibilityLabel("Learning Path Actions")
        .help("Learning Path Actions")
        PanelCloseButton(panel: .learningPath, close: close)
      }
      .padding(14)

      if selection.isReviewingAnotherItem {
        Button {
          selection.returnToCurrent()
        } label: {
          Label("Return to Current", systemImage: "arrow.uturn.backward.circle.fill")
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.borderedProminent)
        .padding(.horizontal, 12)
        .padding(.bottom, 10)
      }

      Divider()

      ScrollView {
        LazyVStack(alignment: .leading, spacing: 2) {
          ForEach(projection.items) { item in
            navigatorRow(item)
          }
        }
        .padding(8)
      }
    }
    .background(Color(nsColor: .controlBackgroundColor))
    .sheet(item: $pendingResetPlan) { plan in
      LearningResetSheet(
        plan: plan,
        authorityError: projection.resetSurface.authorityError,
        plotterUIProjection: plotterUIProjection,
        plotterUIIntentSink: plotterUIIntentSink,
        completed: {
          selection.updateCurrent(currentLearningPathItemID)
          selection.returnToCurrent()
          pendingResetPlan = nil
        }
      )
    }
  }

  private func navigatorRow(_ item: LearningPathItemPresentation) -> some View {
    Button {
      selection.select(item.id)
    } label: {
      HStack(alignment: .top, spacing: 8) {
        Image(systemName: statusSystemImage(item.status))
          .foregroundStyle(statusColor(item.status))
          .frame(width: 17)

        VStack(alignment: .leading, spacing: 3) {
          HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(item.id.number)
              .font(.caption.monospaced().bold())
              .foregroundStyle(.secondary)
            Text(item.id.title)
              .font(.callout.weight(item.id == selection.current ? .semibold : .regular))
              .fixedSize(horizontal: false, vertical: true)
          }

          HStack(spacing: 5) {
            Text(item.status.rawValue)
              .font(.caption2.weight(.medium))
              .foregroundStyle(statusColor(item.status))
            if item.id == selection.current {
              Text("Runtime current")
                .font(.caption2.monospaced().bold())
                .foregroundStyle(Color.accentColor)
            }
          }
        }
        Spacer(minLength: 0)
      }
      .padding(.leading, CGFloat(item.id.navigationDepth) * 18)
      .padding(.horizontal, 8)
      .padding(.vertical, 7)
      .frame(maxWidth: .infinity, alignment: .leading)
      .contentShape(Rectangle())
      .background(
        item.id == selection.selected ? Color.accentColor.opacity(0.16) : Color.clear,
        in: RoundedRectangle(cornerRadius: 7)
      )
    }
    .buttonStyle(.plain)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(
      "\(item.id.number) \(item.id.title), \(item.status.rawValue)"
        + (item.id == selection.current ? ", current exercise" : "")
    )
    .accessibilityHint("Reviews this row without starting an action")
  }
}

/// Selected exercise prompt and its pinned, effect-bearing controls.
struct LearningPathView: View {
  @Binding var selection: LearningPathSelectionState
  let projection: LearningPathProjection
  let currentLearningPathItemID: LearningPathItemID
  let plotterUIProjection: PlotterUIProjection
  let plotterUIIntentSink: any PlotterUIIntentSink
  let close: () -> Void
  let closeUnavailableReason: String?

  var body: some View {
    let selectedPresentation = projection.selectedAction
    let pinnedActionStrip =
      projection.currentActionStrip
      ?? selectedPresentation.actionStrip

    VStack(spacing: 0) {
      HStack {
        Spacer()
        PanelCloseButton(
          panel: .exercise,
          close: close,
          unavailableReason: closeUnavailableReason
        )
      }
      .padding(12)

      ScrollView {
        selectedDetail(selectedPresentation)
        .padding(14)
      }

      if let strip = pinnedActionStrip {
        ExerciseActionStripView(
          presentation: strip,
          plotterUIProjection: plotterUIProjection,
          plotterUIIntentSink: plotterUIIntentSink
        )
      }
    }
    .background(Color(nsColor: .windowBackgroundColor))
  }

  private func selectedDetail(_ presentation: OperatorActionPresentation) -> some View {
    VStack(alignment: .leading, spacing: 14) {
      if let question = presentation.question {
        fragmentText(question.prompt)
          .font(.title3.weight(.medium))
          .fixedSize(horizontal: false, vertical: true)
          .textSelection(.enabled)
          .accessibilityElement(children: .ignore)
          .accessibilityLabel(question.prompt.accessibilityText)
          .accessibilityValue(question.choices.map(\.exactPhrase).joined(separator: " or "))
      }

      if !presentation.instructions.isEmpty {
        fragmentText(presentation.instructions)
          .font(.body)
          .fixedSize(horizontal: false, vertical: true)
          .textSelection(.enabled)
          .accessibilityElement(children: .ignore)
          .accessibilityLabel(presentation.instructions.accessibilityText)
      }
    }
    .frame(maxWidth: .infinity, alignment: .topLeading)
  }
}

private struct LearningResetSheet: View {
  let plan: LearningVacatePlan
  let authorityError: String?
  let plotterUIProjection: PlotterUIProjection
  let plotterUIIntentSink: any PlotterUIIntentSink
  let completed: () -> Void
  @Environment(\.dismiss) private var dismiss
  @State private var isPerforming = false
  @State private var requestRefusal: String?

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      Text(plan.title)
        .font(.title2.weight(.semibold))
      Text(confirmationSummary)
      .fixedSize(horizontal: false, vertical: true)

      if plan.scope == .all {
        Text(
          "Any active Learning Path attempt will be cancelled and settled first. Reset does not start motion or erase marks on the paper."
        )
        .font(.caption)
        .foregroundStyle(.secondary)
      }

      GroupBox("Steps to reset") {
        VStack(alignment: .leading, spacing: 5) {
          ForEach(plan.affectedItems) { item in
            Text("\(item.number)  \(item.title)")
              .font(.callout.monospaced())
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 4)
      }

      if plan.removesDurableCheckpoint {
        Label(
          "The affected saved LIVE machine and/or tip checkpoint will also be cleared.",
          systemImage: "externaldrive.badge.xmark"
        )
        .font(.caption)
        .foregroundStyle(.orange)
      }
      if plan.physicalInkMayRemain {
        Label(
          "Marks already on the paper will remain. Choose a clean area or replace the paper before drawing there again.",
          systemImage: "exclamationmark.triangle.fill"
        )
        .font(.caption.weight(.semibold))
        .foregroundStyle(.orange)
      }

      if let error = requestRefusal ?? authorityError {
        Label(error, systemImage: "exclamationmark.triangle.fill")
          .font(.caption)
          .foregroundStyle(.orange)
          .textSelection(.enabled)
      }

      HStack {
        Spacer()
        Button("Cancel") { dismiss() }
          .keyboardShortcut(.cancelAction)
          .disabled(isPerforming)
        Button(plan.title) {
          isPerforming = true
          Task { @MainActor in
            guard let request = plotterUIProjection.request(
              matching: .learningReset(plan.modelRequest)
            ) else {
              requestRefusal = "Refresh the current Learning reset preview before retrying."
              isPerforming = false
              return
            }
            let disposition = await plotterUIIntentSink.submitPlotterUIRequest(request)
            isPerforming = false
            if case .accepted = disposition {
              completed()
              dismiss()
            } else if case .refused(let refusal) = disposition {
              requestRefusal = refusal.remedy
            }
          }
        }
        .buttonStyle(.borderedProminent)
        .disabled(isPerforming)
      }
    }
    .padding(20)
    .frame(minWidth: 460, idealWidth: 500, maxWidth: 560)
  }

  private var confirmationSummary: String {
    if plan.scope == .all {
      return "This will completely clear the current \(plan.source.rawValue) Learning Path and its saved accepted checkpoint. The path will return to 1.1 Identify and Calibrate the Pen."
    }
    return "This will clear saved \(plan.source.rawValue) Learning Path results from \(plan.anchor.number) \(plan.anchor.title) onward."
  }
}

private struct ExerciseActionStripView: View {
  let presentation: PlotterUILearningActionStripDecision
  let plotterUIProjection: PlotterUIProjection
  let plotterUIIntentSink: any PlotterUIIntentSink
  @State private var requestRefusal: String?

  var body: some View {
    VStack(alignment: .leading, spacing: 9) {
      if let requestRefusal {
        Label(requestRefusal, systemImage: "exclamationmark.triangle.fill")
          .font(.caption)
          .foregroundStyle(.orange)
          .textSelection(.enabled)
      }

      if let adjustment = presentation.penAdjustment {
        penSetpointAdjustment(adjustment)
      }

      if let directionSelection = presentation.directionSelection {
        directionSelectionControl(directionSelection)
      }

      LazyVGrid(
        columns: [
          GridItem(
            .adaptive(minimum: ExerciseActionLayoutPolicy.minimumButtonWidth),
            spacing: ExerciseActionLayoutPolicy.horizontalSpacing
          )
        ],
        alignment: .leading,
        spacing: 7
      ) {
        ForEach(presentation.actions, id: \.request) { action in
          actionButton(action)
        }
      }

      ForEach(presentation.actions.filter { $0.unavailableReason != nil }, id: \.request) { action in
        if let reason = action.unavailableReason {
          Label("\(action.title): \(reason)", systemImage: "exclamationmark.triangle.fill")
            .font(.caption)
            .foregroundStyle(.orange)
            .textSelection(.enabled)
        }
      }
    }
    .padding(12)
  }

  private func penSetpointAdjustment(
    _ adjustment: PlotterUILearningPenAdjustmentDecision
  ) -> some View {
    let title = adjustment.command == .raise ? "Pen Up servo" : "Pen Down servo"
    let minimum = adjustment.candidates.map(\.value).min() ?? adjustment.value
    let maximum = adjustment.candidates.map(\.value).max() ?? adjustment.value
    let currentCandidate = adjustment.candidates.first { $0.value == adjustment.value }
    let unavailableReason: String? = if let currentCandidate {
      currentCandidate.decision.unavailableReason
    } else {
      "The exact current Pen setpoint request is unavailable."
    }
    return VStack(alignment: .leading, spacing: 6) {
      HStack {
        Text(title)
          .font(.caption.weight(.semibold))
        Spacer()
        Text("S\(adjustment.value)")
          .font(.body.monospaced().bold())
      }
      Slider(
        value: Binding(
          get: { Double(adjustment.value) },
          set: { value in
            let exactValue = Int(value.rounded())
            guard let candidate = adjustment.candidates.first(where: { $0.value == exactValue }) else {
              requestRefusal = "Refresh the exact current Pen setpoint choices before retrying."
              return
            }
            guard let unavailableReason = candidate.decision.unavailableReason else {
              submitLearningRequest(candidate.decision.request)
              return
            }
            requestRefusal = unavailableReason
          }
        ),
        in: Double(minimum)...Double(maximum),
        step: 1
      )
      .disabled(unavailableReason != nil)
      .help(unavailableReason ?? title)
      .accessibilityLabel(title)
      .accessibilityValue("S\(adjustment.value)")
      .accessibilityHint(
        "Adjusts and sends the current Pen \(adjustment.command == .raise ? "Up" : "Down") servo value."
      )
      Text("Move the slider until the physical pen position is correct, then confirm that position.")
        .font(.caption2)
        .foregroundStyle(.secondary)
    }
  }

  @ViewBuilder
  private func directionSelectionControl(
    _ selection: PlotterUILearningDirectionDecision
  ) -> some View {
    Text(selection.options.count > 1 ? "Available direction choices" : "Required next direction")
      .font(.caption2.monospaced().bold())
      .foregroundStyle(.secondary)

    if selection.options.count > 1 {
      Picker(
        "Boundary direction",
        selection: Binding(
          get: { selection.selected },
          set: { direction in
            guard let candidate = selection.candidates.first(where: { $0.direction == direction }) else {
              requestRefusal = "Refresh the exact current Boundary direction choices before retrying."
              return
            }
            guard let unavailableReason = candidate.decision.unavailableReason else {
              submitLearningRequest(candidate.decision.request)
              return
            }
            requestRefusal = unavailableReason
          }
        )
      ) {
        ForEach(selection.options, id: \.self) { direction in
          Text(directionName(direction)).tag(direction)
        }
      }
      .pickerStyle(.segmented)
      .disabled(selection.candidates.allSatisfy { $0.decision.unavailableReason != nil })
      .help(selection.candidates.compactMap(\.decision.unavailableReason).first ?? "Select Boundary direction")
      .accessibilityValue(PresentationCue.direction(
        PlotterLearningActionabilityFactAdapter().boundaryDirection(selection.selected)
      ).accessibilityValue)
      .accessibilityHint("Selects a direction without starting motion.")
    } else {
      HStack(spacing: 12) {
        Text("Boundary direction")
          .foregroundStyle(.primary)
        Spacer(minLength: 12)
        Text(directionName(selection.selected))
          .font(.body.monospaced().bold())
          .foregroundStyle(.primary)
          .padding(.horizontal, 12)
          .padding(.vertical, 5)
          .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
      }
      .accessibilityElement(children: .ignore)
      .accessibilityLabel("Boundary direction")
      .accessibilityValue(PresentationCue.direction(
        PlotterLearningActionabilityFactAdapter().boundaryDirection(selection.selected)
      ).accessibilityValue)
      .accessibilityHint("This opposite boundary is required next.")
    }
  }

  private func directionName(_ direction: PlotterUILearningBoundaryDirection) -> String {
    switch direction {
    case .positiveX: "X+"
    case .negativeX: "X−"
    case .positiveY: "Y+"
    case .negativeY: "Y−"
    }
  }


  private func submitLearningRequest(_ modelRequest: PlotterLearningActionRequest) {
    guard let request = plotterUIProjection.request(matching: .learningAction(modelRequest)) else {
      requestRefusal = "Refresh the current Learning action before retrying."
      return
    }
    Task { @MainActor in
      let disposition = await plotterUIIntentSink.submitPlotterUIRequest(request)
      if case .refused(let refusal) = disposition {
        requestRefusal = refusal.remedy
      } else {
        requestRefusal = nil
      }
    }
  }

  @ViewBuilder
  private func actionButton(_ action: PlotterUILearningActionDecision) -> some View {
    let exactRequest = plotterUIProjection.request(matching: .learningAction(action.request))
    let unavailableReason = action.unavailableReason
      ?? (exactRequest == nil ? "Refresh the current Learning action before retrying." : nil)
    let button = Button {
      submitLearningRequest(action.request)
    } label: {
      Text(action.title)
        .multilineTextAlignment(.center)
        .lineLimit(nil)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.vertical, 2)
        .frame(
          maxWidth: .infinity,
          minHeight: ExerciseActionLayoutPolicy.minimumButtonHeight
        )
    }
    .help(unavailableReason ?? action.title)

    let styledButton = button.operatorButton(
      action.buttonRole,
      isEnabled: unavailableReason == nil
    )
    if action.kind.isImmediateStopOrVisionCancel {
      styledButton.keyboardShortcut(.cancelAction)
    } else {
      styledButton
    }
  }
}

extension PlotterLearningAction {
  fileprivate var isImmediateStopOrVisionCancel: Bool {
    switch self {
    case .stop:
      true
    default:
      false
    }
  }
}

private func fragmentText(_ fragments: [PresentationFragment]) -> Text {
  fragments.enumerated().reduce(Text("")) { result, entry in
    let (index, fragment) = entry
    let separator = index == 0 ? "" : " "
    switch fragment {
    case .text(let text):
      return result + Text(separator + text)
    case .cue(let cue):
      return result
        + Text(separator + cue.visibleText)
        .bold()
        .foregroundColor(cueColor(cue))
    }
  }
}

private func cueColor(_ cue: PresentationCue) -> Color {
  switch cue {
  case .no, .stop, .down: .red
  case .yes, .up: .green
  case .direction: .accentColor
  }
}

private func statusLabel(_ status: LearningPathStageStatus) -> some View {
  Label(status.rawValue, systemImage: statusSystemImage(status))
    .font(.caption.weight(.semibold))
    .foregroundStyle(statusColor(status))
}

private func statusColor(_ status: LearningPathStageStatus) -> Color {
  switch status {
  case .complete: .green
  case .current: .accentColor
  case .next: .secondary
  case .needsAttention: .orange
  }
}

private func statusSystemImage(_ status: LearningPathStageStatus) -> String {
  switch status {
  case .complete: "checkmark.circle.fill"
  case .current: "arrow.right.circle.fill"
  case .next: "circle"
  case .needsAttention: "exclamationmark.triangle.fill"
  }
}
