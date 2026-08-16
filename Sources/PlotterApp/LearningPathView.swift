import Foundation
import PlotterRuntime
import SwiftUI

/// One Learning interface: the native tree rail and selected exercise consume
/// the same fresh projection and cannot drift into parallel navigator/detail
/// contracts.
struct LearningExercisePane: View {
  @Bindable var workspace: OperatorWorkspace
  @Binding var selection: LearningPathSelectionState
  let close: () -> Void
  let closeUnavailableReason: String?
  @State private var pendingInvalidationPlan: LearningInvalidationPlan?

  var body: some View {
    let projection = workspace.learningPathProjection(selectedItemID: selection.selected)

    HSplitView {
      LearningPathRail(
        items: projection.items,
        currentItemID: projection.currentItemID,
        selection: $selection
      )
      .frame(
        minWidth: LearningWorkbenchLayoutPolicy.learningPathRailWidth,
        idealWidth: LearningWorkbenchLayoutPolicy.learningPathRailWidth,
        maxWidth: LearningWorkbenchLayoutPolicy.learningPathRailWidth + 60
      )

      CompactExerciseDetail(
        presentation: projection.selectedAction,
        close: close,
        closeUnavailableReason: closeUnavailableReason,
        perform: { kind, ownerID in
          await workspace.performExerciseAction(kind, for: ownerID)
        },
        requestInvalidation: { pendingInvalidationPlan = $0 }
      )
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    .background(Color(nsColor: .windowBackgroundColor))
    .sheet(item: $pendingInvalidationPlan) { plan in
      LearningInvalidationSheet(
        workspace: workspace,
        plan: plan,
        completed: {
          selection.updateCurrent(workspace.currentLearningPathItemID)
          selection.returnToCurrent()
          pendingInvalidationPlan = nil
        }
      )
    }
  }
}

private struct LearningPathRail: View {
  let items: [LearningPathItemPresentation]
  let currentItemID: LearningPathItemID
  @Binding var selection: LearningPathSelectionState

  var body: some View {
    VStack(spacing: 0) {
      HStack(spacing: 6) {
        Text("Learning Path")
          .font(.headline)
        Spacer(minLength: 0)
        if selection.selected != currentItemID {
          Button {
            selection.select(currentItemID)
          } label: {
            Image(systemName: "location.fill")
          }
          .buttonStyle(.borderless)
          .accessibilityLabel("Return to Current Step")
          .help("Return to Current Step")
        }
      }
      .padding(.horizontal, 10)
      .padding(.vertical, 9)

      Divider()

      List(selection: selectedItemBinding) {
        ForEach(items) { item in
          LearningPathRailRow(
            item: item,
            isCurrent: item.id == currentItemID,
            depth: LearningPathTree.curriculum.depth(of: item.id) ?? 0
          )
          .tag(item.id)
        }
      }
      .listStyle(.sidebar)
      .accessibilityLabel("Learning Path")
    }
    .background(Color(nsColor: .controlBackgroundColor))
  }

  private var selectedItemBinding: Binding<LearningPathItemID?> {
    Binding(
      get: { selection.selected },
      set: { itemID in
        if let itemID { selection.select(itemID) }
      }
    )
  }
}

private struct LearningPathRailRow: View {
  let item: LearningPathItemPresentation
  let isCurrent: Bool
  let depth: Int

  var body: some View {
    HStack(spacing: 6) {
      Image(systemName: statusSystemImage(item.status))
        .foregroundStyle(statusColor(item.status))
        .frame(width: 14)
      VStack(alignment: .leading, spacing: 1) {
        Text(item.id.number)
          .font(.caption.monospaced().bold())
        Text(item.id.title)
          .font(.caption)
          .lineLimit(2)
      }
      Spacer(minLength: 0)
      if isCurrent {
        Circle()
          .fill(Color.accentColor)
          .frame(width: 6, height: 6)
          .accessibilityHidden(true)
      }
    }
    .padding(.leading, CGFloat(depth) * 12)
    .padding(.vertical, 3)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(
      "\(item.id.number) \(item.id.title), \(item.status.rawValue)"
        + (isCurrent ? ", current" : "")
    )
    .accessibilityHint("Reviews this step without starting it")
  }
}

private struct CompactExerciseDetail: View {
  let presentation: OperatorActionPresentation
  let close: () -> Void
  let closeUnavailableReason: String?
  let perform: (ExerciseActionKind, LearningPathItemID) async -> Void
  let requestInvalidation: (LearningInvalidationPlan) -> Void

  var body: some View {
    VStack(spacing: 0) {
      HStack(alignment: .firstTextBaseline, spacing: 8) {
        Text(presentation.heading)
          .font(.title2.weight(.semibold))
          .fixedSize(horizontal: false, vertical: true)
        Spacer(minLength: 8)
        PanelCloseButton(
          title: "Hide Learning",
          close: close,
          unavailableReason: closeUnavailableReason
        )
      }
      .padding(12)

      Divider()

      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          script

          if let question = presentation.question {
            VStack(alignment: .leading, spacing: 5) {
              Text("Question:")
                .font(.headline)
              fragmentText(question.prompt)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(question.prompt.accessibilityText)
            }
          }

          if let actionStrip = presentation.actionStrip {
            CompactExerciseActions(
              presentation: actionStrip,
              perform: perform
            )
          }

          invalidationControls(presentation.invalidation)
        }
        .padding(14)
      }
    }
  }

  private var script: some View {
    VStack(alignment: .leading, spacing: 7) {
      Text("Script:")
        .font(.headline)
      ForEach(Array(presentation.script.enumerated()), id: \.offset) { _, line in
        HStack(alignment: .firstTextBaseline, spacing: 7) {
          Text("\(line.speaker.rawValue):")
            .font(.callout.weight(.semibold))
            .frame(width: 54, alignment: .trailing)
          fragmentText(line.fragments)
            .font(.body)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(
              "\(line.speaker.rawValue): \(line.fragments.accessibilityText)"
            )
        }
      }
    }
  }

  @ViewBuilder
  private func invalidationControls(_ invalidation: LearningInvalidationPresentation) -> some View {
    if invalidation.selectedPlan != nil || invalidation.invalidateAllPlan != nil {
      Divider()
      HStack {
        if let selectedPlan = invalidation.selectedPlan {
          Button(selectedPlan.title) { requestInvalidation(selectedPlan) }
            .operatorButton(
              .interrupt,
              isEnabled: invalidation.unavailableReason == nil
            )
            .help(invalidation.unavailableReason ?? selectedPlan.message)
        }
        if let allPlan = invalidation.invalidateAllPlan {
          Menu {
            Button(allPlan.title, role: .destructive) { requestInvalidation(allPlan) }
              .disabled(invalidation.unavailableReason != nil)
          } label: {
            Image(systemName: "ellipsis.circle")
          }
          .menuStyle(.borderlessButton)
          .accessibilityLabel("More Learning invalidation actions")
          .help(invalidation.unavailableReason ?? allPlan.message)
        }
      }
    }
  }
}

private struct CompactExerciseActions: View {
  let presentation: ExerciseActionStripPresentation
  let perform: (ExerciseActionKind, LearningPathItemID) async -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      if let adjustment = presentation.penSetpointAdjustment {
        VStack(alignment: .leading, spacing: 5) {
          HStack {
            Text(adjustment.title)
            Spacer()
            Text("S\(adjustment.value)").font(.body.monospaced().bold())
          }
          Slider(
            value: Binding(
              get: { Double(adjustment.value) },
              set: { value in
                Task {
                  await perform(
                    .setPenSetpoint(adjustment.command, Int(value.rounded())),
                    presentation.ownerID
                  )
                }
              }
            ),
            in: Double(adjustment.minimumValue)...Double(adjustment.maximumValue),
            step: 1
          )
          .tint(.blue)
          .accessibilityLabel(adjustment.title)
          .accessibilityValue("S\(adjustment.value)")
        }
      }

      if let direction = presentation.directionSelection {
        if direction.allowsSelection {
          Picker(
            direction.purpose.label,
            selection: Binding(
              get: { direction.selected },
              set: { selected in
                Task {
                  await perform(
                    .selectDirection(direction.purpose, selected),
                    presentation.ownerID
                  )
                }
              }
            )
          ) {
            ForEach(direction.options, id: \.self) { option in
              Text(option.displayName).tag(option)
            }
          }
          .pickerStyle(.segmented)
          .tint(.blue)
        } else {
          LabeledContent(direction.purpose.label, value: direction.selected.displayName)
        }
      }

      LazyVGrid(
        columns: [
          GridItem(
            .adaptive(minimum: ExerciseActionLayoutPolicy.minimumButtonWidth),
            spacing: ExerciseActionLayoutPolicy.horizontalSpacing
          )
        ],
        alignment: .leading,
        spacing: 8
      ) {
        ForEach(presentation.actions) { action in
          actionButton(action)
        }
      }
    }
  }

  @ViewBuilder
  private func actionButton(_ action: ExerciseActionDescriptor) -> some View {
    let button = Button {
      Task { await perform(action.kind, presentation.ownerID) }
    } label: {
      Text(action.title)
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        .frame(
          maxWidth: .infinity,
          minHeight: ExerciseActionLayoutPolicy.minimumButtonHeight
        )
    }
    .operatorButton(action.buttonRole, isEnabled: action.isEnabled)
    .help(action.unavailableReason ?? action.title)

    switch action.keyboardShortcut {
    case .escape:
      button.keyboardShortcut(.cancelAction)
    case nil:
      button
    }
  }
}

private struct LearningInvalidationSheet: View {
  @Bindable var workspace: OperatorWorkspace
  let plan: LearningInvalidationPlan
  let completed: () -> Void
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      Text(plan.title)
        .font(.title2.weight(.semibold))
      Text(plan.message)
        .fixedSize(horizontal: false, vertical: true)

      GroupBox("Data to invalidate") {
        VStack(alignment: .leading, spacing: 5) {
          ForEach(plan.affectedItemIDs) { item in
            Text("\(item.number)  \(item.title)")
              .font(.callout.monospaced())
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 4)
      }

      if plan.removesDurableMachineRegistration || plan.removesDurableTipRegistration {
        Label(
          "The affected saved registration checkpoint will also be deleted.",
          systemImage: "externaldrive.badge.xmark"
        )
        .font(.caption)
        .foregroundStyle(.orange)
      }

      HStack {
        Spacer()
        Button("Cancel") { dismiss() }
          .operatorButton(.interrupt)
          .keyboardShortcut(.cancelAction)
        Button(plan.title) {
          if workspace.performLearningInvalidation(plan) {
            completed()
            dismiss()
          }
        }
        .operatorButton(.interrupt)
      }
    }
    .padding(20)
    .frame(minWidth: 460, idealWidth: 500, maxWidth: 560)
  }
}

private func statusSystemImage(_ status: LearningPathStageStatus) -> String {
  switch status {
  case .complete: "checkmark.circle.fill"
  case .current: "record.circle.fill"
  case .next: "circle"
  case .needsAttention: "exclamationmark.triangle.fill"
  }
}

private func statusColor(_ status: LearningPathStageStatus) -> Color {
  switch status {
  case .complete: .green
  case .current: .accentColor
  case .next: .secondary
  case .needsAttention: .orange
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
  case .direction: .blue
  }
}
