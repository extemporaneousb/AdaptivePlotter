import Foundation
import PlotterRuntime
import SwiftUI

struct LearningPathNavigator: View {
  @Bindable var workspace: OperatorWorkspace
  @Binding var selection: LearningPathSelectionState

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      VStack(alignment: .leading, spacing: 5) {
        Text("Learning Path")
          .font(.title2.weight(.semibold))
        Text("Select a row to review it. Selection never starts or advances an exercise.")
          .font(.caption)
          .foregroundStyle(.secondary)
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
          ForEach(workspace.learningPathItemPresentations) { item in
            navigatorRow(item)
          }
        }
        .padding(8)
      }
    }
    .background(Color(nsColor: .controlBackgroundColor))
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
        + (item.id == selection.current ? ", runtime current" : "")
    )
    .accessibilityHint("Reviews this row without starting an action")
  }
}

/// Selected exercise detail. The scrollable detail and the pinned action strip
/// are deliberately separate so long evidence cannot push controls off-screen.
struct LearningPathView: View {
  @Bindable var workspace: OperatorWorkspace
  @Binding var selection: LearningPathSelectionState
  let utilities: UtilitiesPresentation
  let performUtilitiesAction: (UtilitiesVisibilityAction) -> Void

  var body: some View {
    let actionWorkspace = workspace
    let selectedPresentation = workspace.selectedOperatorActionPresentation(
      for: selection.selected
    )
    let pinnedActionStrip =
      workspace.currentExerciseActionStripPresentation
      ?? selectedPresentation.actionStrip

    VStack(spacing: 0) {
      detailHeader
      Divider()

      ScrollView {
        selectedDetail(selectedPresentation)
          .padding(14)
      }

      if let strip = pinnedActionStrip {
        Divider()
        ExerciseActionStripView(
          presentation: strip,
          reviewedItemID: selection.selected,
          perform: { kind, ownerID in
            await actionWorkspace.performExerciseAction(kind, for: ownerID)
          },
          selectDirection: { direction in
            await actionWorkspace.selectBoundaryDirection(direction)
          }
        )
      }
    }
    .background(Color(nsColor: .windowBackgroundColor))
  }

  private var detailHeader: some View {
    HStack(spacing: 8) {
      VStack(alignment: .leading, spacing: 2) {
        Text("SELECTED EXERCISE")
          .font(.caption2.monospaced().bold())
          .foregroundStyle(.secondary)
        Text("\(selection.selected.number) \(selection.selected.title)")
          .font(.headline)
          .lineLimit(2)
      }
      Spacer()
      Button {
        performUtilitiesAction(utilities.action)
      } label: {
        Label(utilities.actionTitle, systemImage: "sidebar.trailing")
      }
      .buttonStyle(.bordered)
      .disabled(!utilities.isActionEnabled)
      .help(
        utilities.unavailableReason
          ?? "\(utilities.actionTitle) for Camera and Overlay controls"
      )
    }
    .padding(12)
  }

  private func selectedDetail(_ presentation: OperatorActionPresentation) -> some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack(alignment: .firstTextBaseline) {
        statusLabel(presentation.status)
        Spacer()
        Text(presentation.stepNumber)
          .font(.caption.monospaced().bold())
          .foregroundStyle(.secondary)
      }

      Text(presentation.title)
        .font(.title2.weight(.semibold))
        .fixedSize(horizontal: false, vertical: true)

      if let participant = presentation.participant {
        labeledValue("Participant", participant)
      }

      if let timeline = presentation.timeline {
        timelineCard(timeline)
      }

      if let question = presentation.question {
        questionCard(question)
      }

      if !presentation.instructions.isEmpty {
        fragmentCard(
          label: "Instruction",
          fragments: presentation.instructions,
          color: Color(nsColor: .controlBackgroundColor)
        )
      }

      if !presentation.expectedObservation.isEmpty {
        fragmentCard(
          label: "Expected observation",
          fragments: presentation.expectedObservation,
          color: Color.green.opacity(0.09)
        )
      }

      if let requestedFeedMMPerMinute = presentation.requestedFeedMMPerMinute {
        labeledValue(
          "Requested feed",
          String(format: "%.1f mm/min", requestedFeedMMPerMinute)
        )
      }
      if let feedSource = presentation.feedSource {
        labeledValue("Feed source", feedSourceLabel(feedSource))
      }

      if let activity = presentation.activity {
        operationActivityCard(activity)
      }

      if !presentation.evidence.isEmpty {
        VStack(alignment: .leading, spacing: 8) {
          Text("EVIDENCE")
            .font(.caption2.monospaced().bold())
            .foregroundStyle(.secondary)
          ForEach(presentation.evidence) { evidence in
            VStack(alignment: .leading, spacing: 4) {
              Text(evidence.label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
              fragmentText(evidence.fragments)
                .font(.callout)
                .textSelection(.enabled)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(evidence.fragments.accessibilityText)
            }
          }
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .topLeading)
  }

  private func timelineCard(_ timeline: ExerciseTimelinePresentation) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack {
        Text("CURRENT TIMELINE POSITION")
          .font(.caption2.monospaced().bold())
          .foregroundStyle(.secondary)
        Spacer()
        Text(timeline.positionText)
          .font(.caption.monospaced().bold())
          .foregroundStyle(Color.accentColor)
      }
      ProgressView(value: Double(timeline.position), total: Double(timeline.total))
        .accessibilityLabel("Exercise timeline")
        .accessibilityValue(timeline.positionText)
      Text(timeline.currentLabel)
        .font(.callout.weight(.semibold))
    }
    .padding(10)
    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 9))
  }

  private func questionCard(_ question: ExerciseQuestionPresentation) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      Text("FOCUSED QUESTION")
        .font(.caption2.monospaced().bold())
        .foregroundStyle(.secondary)
      fragmentText(question.prompt)
        .font(.body)
        .fixedSize(horizontal: false, vertical: true)
        .textSelection(.enabled)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(question.prompt.accessibilityText)
        .accessibilityValue(question.choices.map(\.exactPhrase).joined(separator: " or "))
    }
    .padding(11)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 9))
  }

  private func operationActivityCard(
    _ activity: OperationActivityPresentation
  ) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(alignment: .firstTextBaseline) {
        Text("OPERATION ACTIVITY")
          .font(.caption2.monospaced().bold())
          .foregroundStyle(.secondary)
        Spacer()
        Label(activity.outcome.rawValue, systemImage: activitySystemImage(activity.outcome))
          .font(.caption.weight(.semibold))
          .foregroundStyle(activityColor(activity.outcome))
      }
      labeledValue("Actor", activity.actor)
      labeledValue("Action", activity.action)
      if !activity.detail.isEmpty {
        activityFragments("Detail", activity.detail)
      }
      if !activity.recovery.isEmpty {
        activityFragments("Recovery", activity.recovery)
      }
    }
    .padding(11)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(
      activityColor(activity.outcome).opacity(0.09),
      in: RoundedRectangle(cornerRadius: 9)
    )
    .accessibilityElement(children: .contain)
  }

  private func activityFragments(
    _ label: String,
    _ fragments: [PresentationFragment]
  ) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(label.uppercased())
        .font(.caption2.monospaced().bold())
        .foregroundStyle(.secondary)
      fragmentText(fragments)
        .font(.callout)
        .textSelection(.enabled)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(fragments.accessibilityText)
    }
  }

  private func fragmentCard(
    label: String,
    fragments: [PresentationFragment],
    color: Color
  ) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(label.uppercased())
        .font(.caption2.monospaced().bold())
        .foregroundStyle(.secondary)
      fragmentText(fragments)
        .font(.body)
        .fixedSize(horizontal: false, vertical: true)
        .textSelection(.enabled)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(fragments.accessibilityText)
    }
    .padding(11)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(color, in: RoundedRectangle(cornerRadius: 9))
  }

  private func labeledValue(_ label: String, _ value: String) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(label.uppercased())
        .font(.caption2.monospaced().bold())
        .foregroundStyle(.secondary)
      Text(value)
        .font(.callout)
        .textSelection(.enabled)
    }
  }
}

private struct ExerciseActionStripView: View {
  let presentation: ExerciseActionStripPresentation
  let reviewedItemID: LearningPathItemID
  let perform: (ExerciseActionKind, LearningPathItemID) async -> Void
  let selectDirection: @Sendable (BoundaryDirection) async -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 9) {
      HStack(alignment: .firstTextBaseline) {
        Text("EXERCISE ACTIONS")
          .font(.caption2.monospaced().bold())
          .foregroundStyle(.secondary)
        Spacer()
        Text("\(presentation.ownerID.number) \(presentation.ownerID.title)")
          .font(.caption.weight(.semibold))
          .foregroundStyle(.secondary)
      }

      if reviewedItemID != presentation.ownerID {
        Label(
          "Reviewing \(reviewedItemID.number); controls remain with the runtime action owner.",
          systemImage: "eye"
        )
        .font(.caption)
        .foregroundStyle(.secondary)
      }

      if let directionSelection = presentation.directionSelection {
        Picker(
          "Boundary direction",
          selection: Binding(
            get: { directionSelection.selected },
            set: { direction in
              Task { await selectDirection(direction) }
            }
          )
        ) {
          ForEach(directionSelection.options, id: \.self) { direction in
            Text(direction.displayName).tag(direction)
          }
        }
        .pickerStyle(.segmented)
        .accessibilityValue(
          PresentationCue.direction(directionSelection.selected).accessibilityValue
        )
      }

      ViewThatFits(in: .horizontal) {
        HStack(spacing: 8) {
          ForEach(presentation.actions) { action in
            actionButton(action)
          }
        }

        VStack(alignment: .leading, spacing: 7) {
          ForEach(presentation.actions) { action in
            actionButton(action)
          }
        }
      }

      ForEach(presentation.actions.filter { $0.unavailableReason != nil }) { action in
        if let reason = action.unavailableReason {
          Label("\(action.title): \(reason)", systemImage: "exclamationmark.triangle.fill")
            .font(.caption)
            .foregroundStyle(.orange)
            .textSelection(.enabled)
        }
      }
    }
    .padding(12)
    .background(.bar)
  }

  @ViewBuilder
  private func actionButton(_ action: ExerciseActionDescriptor) -> some View {
    let button = Button(action.title) {
      Task { await perform(action.kind, presentation.ownerID) }
    }
    .disabled(!action.isEnabled)

    switch action.role {
    case .positive:
      button
        .buttonStyle(.borderedProminent)
        .tint(.green)
    case .destructive:
      if case .stop = action.kind {
        button
          .buttonStyle(.borderedProminent)
          .tint(.red)
          .keyboardShortcut(.cancelAction)
      } else {
        button
          .buttonStyle(.borderedProminent)
          .tint(.red)
      }
    case .standard:
      if case .choice(let choice) = action.kind {
        button
          .buttonStyle(.borderedProminent)
          .tint(choice == .yes ? .green : .orange)
      } else {
        button.buttonStyle(.bordered)
      }
    }
  }
}

private func activityColor(_ outcome: OperationActivityOutcome) -> Color {
  switch outcome {
  case .inProgress: .accentColor
  case .succeeded: .green
  case .cancelled: .secondary
  case .needsAttention: .orange
  }
}

private func activitySystemImage(_ outcome: OperationActivityOutcome) -> String {
  switch outcome {
  case .inProgress: "arrow.triangle.2.circlepath"
  case .succeeded: "checkmark.circle.fill"
  case .cancelled: "xmark.circle"
  case .needsAttention: "exclamationmark.triangle.fill"
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
  case .next, .future: .secondary
  case .needsAttention: .orange
  }
}

private func statusSystemImage(_ status: LearningPathStageStatus) -> String {
  switch status {
  case .complete: "checkmark.circle.fill"
  case .current: "arrow.right.circle.fill"
  case .next: "circle"
  case .future: "clock"
  case .needsAttention: "exclamationmark.triangle.fill"
  }
}

private func feedSourceLabel(_ source: FeedSelectionSource) -> String {
  switch source {
  case .controllerReportedCeiling: "Controller-reported ceiling"
  case .existingFallback: "Existing fallback"
  }
}
