import Foundation
import PlotterEpisodeModel
import PlotterEpisodeRuntime
import PlotterRuntime
import PlotterUI
import SwiftUI

/// One Learning panel with exercise selection, prompt, and current controls.
struct LearningPathView: View {
  @Binding var selection: LearningPathSelectionState
  let projection: LearningPathProjection?
  let learningMode: LearningModePresentation
  let plotterUIProjection: PlotterUIProjection
  let plotterUIIntentSink: any PlotterUIIntentSink
  @State private var pendingResetPlan: LearningVacatePlan?

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(alignment: .top, spacing: 10) {
        Text(learningMode.isEnabled ? "Learning On" : "Learning Off")
          .font(.headline)
          .accessibilityIdentifier("learning.mode.state")
          .accessibilityValue(learningMode.isEnabled ? "On" : "Off")
        Spacer(minLength: 0)
        OperatorRequestButton(title: learningMode.actionTitle,
          request: plotterUIProjection.request(for: PlotterAppUIActionID.learningMode),
          unavailableReason: learningMode.remedy, sink: plotterUIIntentSink,
          nativeActionIdentifier: "learning.mode")
          .accessibilityIdentifier("learning.mode")
      }.padding(12)
      if learningMode.isEnabled, let projection {
        Divider()
        learningContent(projection)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }

  @ViewBuilder private func learningContent(_ projection: LearningPathProjection) -> some View {
    let selectedPresentation = projection.selectedAction
    let pinnedActionStrip =
      projection.currentActionStrip
      ?? selectedPresentation.actionStrip

    VStack(alignment: .leading, spacing: 0) {
      HStack {
        Picker("Exercise", selection: Binding(
          get: { selection.selected }, set: { selection.select($0) }
        )) {
          ForEach(projection.items) { item in
            Label("\(item.id.number)  \(item.id.title) · \(item.status.rawValue)",
              systemImage: statusSystemImage(item.status))
              .tag(item.id)
          }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .accessibilityIdentifier("learning.exercisePicker")
        Menu {
          Button("Reset All Learning…", role: .destructive) {
            pendingResetPlan = projection.menu.resetAllPlan
          }
          .disabled(projection.menu.resetAllPlan == nil)
        } label: {
          Image(systemName: "ellipsis.circle")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .accessibilityLabel("Learning Path Actions")
      }
      .padding(12)
      if selection.isReviewingAnotherItem {
        Button("Return to Current Exercise") { selection.returnToCurrent() }
          .buttonStyle(.borderless)
          .padding(.horizontal, 12)
          .padding(.bottom, 10)
      }
      Divider()
      ScrollView {
        VStack(alignment: .leading, spacing: 0) {
          selectedDetail(selectedPresentation).padding(16)
          if let strip = pinnedActionStrip {
            ExerciseActionStripView(
              presentation: strip,
              plotterUIProjection: plotterUIProjection,
              plotterUIIntentSink: plotterUIIntentSink
            )
            .accessibilityIdentifier("learning.exerciseActions")
          }
        }
      }

    }
    .sheet(item: $pendingResetPlan) { plan in
      LearningResetSheet(
        plan: plan, authorityError: projection.resetSurface.authorityError,
        plotterUIProjection: plotterUIProjection, plotterUIIntentSink: plotterUIIntentSink,
        completed: {
          // The runtime may have published its new current item while this
          // sheet awaited reset. Never restore the pre-submit captured item.
          selection.returnToCurrent()
          pendingResetPlan = nil
        }
      )
    }
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

      if presentation.actions.contains(where: { $0.action == .tipCalibration(.revalidateCheckpoint) }) {
        PositionPenPreparationControls(plotterUIProjection: plotterUIProjection,
          plotterUIIntentSink: plotterUIIntentSink)
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
        ForEach(presentation.actions, id: \.controlIdentity) { action in
          actionButton(action)
        }
      }


    }
    .padding(12)
  }

  private func penSetpointAdjustment(
    _ adjustment: PlotterUILearningPenAdjustmentDecision
  ) -> some View {
    PenSetpointControl(adjustment: adjustment, submit: submitLearningRequest)
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
    OperatorRequestButton(
      title: action.title, role: action.buttonRole,
      request: exactRequest, unavailableReason: unavailableReason,
      sink: plotterUIIntentSink, expands: true
    )
  }
}

/// Dragging is a local draft. Commit one selected setpoint on release instead
/// of repeatedly replacing the command/confirmation surface under the pointer.
private struct PenSetpointControl: View {
  let adjustment: PlotterUILearningPenAdjustmentDecision
  let submit: (PlotterLearningActionRequest) -> Void
  @State private var draft = PenSetpointDraft()
  @State private var isEditing = false

  var body: some View {
    let title = adjustment.command == .raise ? "Pen Up servo" : "Pen Down servo"
    let value = draft.value ?? adjustment.value
    let minimum = adjustment.candidates.map(\.value).min() ?? value
    let maximum = adjustment.candidates.map(\.value).max() ?? value
    let reason = adjustment.candidates.first { $0.value == adjustment.value }?.decision.unavailableReason
    VStack(alignment: .leading, spacing: 6) {
      HStack {
        Text(title).font(.caption.weight(.semibold))
        Spacer()
        Text("S\(value)").font(.body.monospaced().bold())
      }
      Slider(value: Binding(
        get: { Double(value) },
        set: {
          draft.change(to: Int($0.rounded()))
          if !isEditing { commitDraft() }
        }
      ), in: Double(minimum)...Double(maximum), onEditingChanged: { editing in
        isEditing = editing
        if !editing { commitDraft() }
      })
      .disabled(reason != nil)
      .help(reason ?? "Release to send the selected servo setting")
      .accessibilityLabel(title)
      .accessibilityValue("S\(value)")
      Text(reason ?? "Release to apply the setting, then confirm the physical pen position.")
        .font(.caption2).foregroundStyle(.secondary)
    }
    .onChange(of: adjustment.command) { _, _ in draft = PenSetpointDraft() }
  }

  private func commitDraft() {
    if let selected = draft.commit(),
      let candidate = adjustment.candidates.first(where: { $0.value == selected }) {
      submit(candidate.decision.request)
    }
  }
}

struct PenSetpointDraft {
  private(set) var value: Int?
  mutating func change(to value: Int) { self.value = value }
  mutating func commit() -> Int? {
    defer { value = nil }
    return value
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
  case .stop: .orange
  case .no, .down, .yes, .up: .primary
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
