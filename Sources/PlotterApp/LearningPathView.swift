import Foundation
import PlotterRuntime
import SwiftUI

struct LearningPathView: View {
  @Bindable var workspace: OperatorWorkspace
  @State private var boundaryDirection: BoundaryDirection = .negativeX

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        header

        ForEach(workspace.learningPathStagePresentations) { presentation in
          stageCard(presentation)
        }

        if let action = workspace.currentOperatorActionPresentation {
          operatorActionPanel(action)
        }
      }
      .padding(18)
      .frame(maxWidth: 920, alignment: .leading)
      .frame(maxWidth: .infinity, alignment: .top)
    }
    .background(Color(nsColor: .windowBackgroundColor))
  }

  private var header: some View {
    VStack(alignment: .leading, spacing: 5) {
      Text("Learning Path")
        .font(.largeTitle.weight(.semibold))
      Text(
        "The numbered stages organize operator work. They do not replace the direct controller, motion, pen, camera, or evidence checks required by each action."
      )
      .font(.callout)
      .foregroundStyle(.secondary)
    }
  }

  @ViewBuilder
  private func stageCard(_ presentation: LearningPathStagePresentation) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(alignment: .firstTextBaseline, spacing: 10) {
        Text(presentation.stage.number)
          .font(.title3.monospaced().bold())
          .frame(width: 28, alignment: .leading)
        Text(presentation.stage.title)
          .font(.title3.weight(.semibold))
        Spacer()
        statusLabel(presentation.status)
      }

      Text(presentation.summary)
        .font(.callout)
        .foregroundStyle(.secondary)

      switch presentation.stage {
      case .humanGuidedDiscovery:
        humanGuidedDiscoveryRows(stageStatus: presentation.status)
      case .observedDrawingTrials:
        observedDrawingTrialRows(stageStatus: presentation.status)
      case .adaptiveDrawing:
        Text("Multi-stroke drawing with observation and checkpoint learning is not yet available.")
          .font(.caption)
          .foregroundStyle(.secondary)
      case .connect, .enableMotion:
        EmptyView()
      }
    }
    .padding(14)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
    .overlay {
      RoundedRectangle(cornerRadius: 10)
        .stroke(stageBorderColor(presentation.status), lineWidth: 1)
    }
  }

  private func humanGuidedDiscoveryRows(
    stageStatus: LearningPathStageStatus
  ) -> some View {
    VStack(alignment: .leading, spacing: 7) {
      ForEach(HumanGuidedDiscoveryStep.allCases) { step in
        sequenceRow(
          stepNumber: step.stepNumber,
          title: step.title,
          status: discoveryStatus(for: step, stageStatus: stageStatus)
        )
      }

      if stageStatus == .current || stageStatus == .needsAttention {
        discoveryCurrentControl

        if let discoveryError = workspace.discoveryError {
          actionableError(discoveryError)
        }
        if workspace.humanGuidedDiscoveryCurrentStep == .clearViewDiscovery,
          let explorationError = workspace.explorationError
        {
          actionableError(explorationError)
        }
      }
    }
  }

  private func observedDrawingTrialRows(
    stageStatus: LearningPathStageStatus
  ) -> some View {
    VStack(alignment: .leading, spacing: 7) {
      ForEach(ObservedDrawingTrialStep.allCases) { step in
        sequenceRow(
          stepNumber: step.stepNumber,
          title: step.title,
          status: drawingTrialStatus(for: step, stageStatus: stageStatus)
        )
      }

      if stageStatus == .current || stageStatus == .needsAttention,
        let explorationError = workspace.explorationError
      {
        actionableError(explorationError)
      }
    }
  }

  @ViewBuilder
  private var discoveryCurrentControl: some View {
    if workspace.currentOperatorActionPresentation == nil {
      switch workspace.humanGuidedDiscoveryCurrentStep {
      case .penInteraction:
        let penStartUnavailableReason = workspace.discoveryStartUnavailableReason(
          for: .penInteraction
        )
        VStack(alignment: .leading, spacing: 6) {
          Button("Begin Pen Interaction") {
            Task { await workspace.beginPenInteraction() }
          }
          .buttonStyle(.borderedProminent)
          .disabled(penStartUnavailableReason != nil)

          if let penStartUnavailableReason {
            actionableError(penStartUnavailableReason)
          }
        }

      case .boundaryDiscovery:
        let boundaryStartUnavailableReason = workspace.discoveryStartUnavailableReason(
          for: discoverySequenceID(for: boundaryDirection)
        )
        VStack(alignment: .leading, spacing: 8) {
          Picker("Boundary direction", selection: $boundaryDirection) {
            ForEach(BoundaryDirection.allCases, id: \.self) { direction in
              Text(direction.displayName).tag(direction)
            }
          }
          .pickerStyle(.segmented)

          Button("Begin Boundary Discovery") {
            Task { await workspace.beginBoundaryDiscovery(boundaryDirection) }
          }
          .buttonStyle(.borderedProminent)
          .disabled(boundaryStartUnavailableReason != nil)

          if let boundaryStartUnavailableReason {
            actionableError(boundaryStartUnavailableReason)
          }

          Text(
            "One relevant boundary observation is sufficient for the current path. Other directions remain optional additional observations."
          )
          .font(.caption)
          .foregroundStyle(.secondary)
        }

      case .clearViewDiscovery:
        VStack(alignment: .leading, spacing: 8) {
          Text("Label the exact current frame")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
          HStack {
            Button("Blocked") {
              Task { await workspace.recordClearViewLabel(.blocked) }
            }
            Button("Partial") {
              Task { await workspace.recordClearViewLabel(.partial) }
            }
            Button("Clear") {
              Task { await workspace.recordClearViewLabel(.clear) }
            }
          }
          Button("Accept Current Clear View") {
            Task { await workspace.acceptCurrentClearViewPose() }
          }
          .buttonStyle(.borderedProminent)
          .disabled(
            workspace.pendingClearViewLabel != .clear
              || workspace.lastArmatureObservation?.humanLabel != .clear
          )
        }
      }
    }
  }

  private func operatorActionPanel(_ presentation: OperatorActionPresentation) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(alignment: .firstTextBaseline) {
        Text("CURRENT ACTION")
          .font(.caption.monospaced().bold())
          .foregroundStyle(.secondary)
        Spacer()
        Text(presentation.stepNumber)
          .font(.caption.monospaced().bold())
          .foregroundStyle(.secondary)
      }

      Text(presentation.title)
        .font(.title2.weight(.semibold))

      actionFact("Participant", presentation.participant)
      actionFact("Action", presentation.action)
      actionFact("Expected observation", presentation.expectedObservation)

      if let requestedFeedMMPerMinute = presentation.requestedFeedMMPerMinute {
        actionFact(
          "Requested feed",
          String(format: "%.1f mm/min", requestedFeedMMPerMinute)
        )
      }
      if let feedSource = presentation.feedSource {
        actionFact("Feed source", feedSourceLabel(feedSource))
      }

      Divider()

      if !presentation.choices.isEmpty {
        HStack(spacing: 8) {
          ForEach(presentation.choices, id: \.self) { choice in
            Button(choice.exactPhrase) {
              Task { await workspace.answerCurrentQuestion(choice) }
            }
            .buttonStyle(.borderedProminent)
            .tint(choice == .no ? .gray : .accentColor)
          }
        }
        .disabled(presentation.primaryActionUnavailableReason != nil)
      } else if presentation.stepNumber
        == ObservedDrawingTrialStep.compareIntendedAndObservedGeometry.stepNumber
      {
        VStack(alignment: .leading, spacing: 8) {
          Text(presentation.primaryActionTitle ?? "Record Assessment")
            .font(.callout.weight(.semibold))
          HStack(spacing: 8) {
            Button("Observed Geometry Accepted") {
              Task {
                await workspace.recordDrawingTrialAssessment(.observedGeometryAccepted)
              }
            }
            Button("Ink or Geometry Unclear") {
              Task {
                await workspace.recordDrawingTrialAssessment(.inkOrGeometryUnclear)
              }
            }
          }
          .buttonStyle(.bordered)
          .disabled(presentation.primaryActionUnavailableReason != nil)
        }
      } else if let title = presentation.primaryActionTitle {
        Button(title) {
          Task { await workspace.performCurrentLearningPathAction() }
        }
        .buttonStyle(.borderedProminent)
        .disabled(presentation.primaryActionUnavailableReason != nil)
      }

      if let reason = presentation.primaryActionUnavailableReason {
        Label(reason, systemImage: "exclamationmark.triangle.fill")
          .font(.caption)
          .foregroundStyle(.orange)
          .textSelection(.enabled)
      }

      if workspace.contextualStopPresentation != nil {
        Text("Stop is available in the main workbench toolbar for the current operation.")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
    .padding(16)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
  }

  private func sequenceRow(
    stepNumber: String,
    title: String,
    status: LearningPathStageStatus
  ) -> some View {
    HStack(spacing: 9) {
      Image(systemName: statusSystemImage(status))
        .foregroundStyle(statusColor(status))
        .frame(width: 18)
      Text(stepNumber)
        .font(.caption.monospaced().bold())
        .foregroundStyle(.secondary)
        .frame(width: 34, alignment: .leading)
      Text(title)
        .font(.callout.weight(status == .current ? .semibold : .regular))
      Spacer()
      Text(status.rawValue)
        .font(.caption)
        .foregroundStyle(statusColor(status))
    }
  }

  private func statusLabel(_ status: LearningPathStageStatus) -> some View {
    Label(status.rawValue, systemImage: statusSystemImage(status))
      .font(.caption.weight(.semibold))
      .foregroundStyle(statusColor(status))
  }

  private func actionFact(_ label: String, _ value: String) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(label.uppercased())
        .font(.caption2.monospaced().bold())
        .foregroundStyle(.secondary)
      Text(value)
        .font(.callout)
        .textSelection(.enabled)
    }
  }

  private func actionableError(_ message: String) -> some View {
    Label(message, systemImage: "exclamationmark.triangle.fill")
      .font(.caption)
      .foregroundStyle(.orange)
      .textSelection(.enabled)
  }

  private func discoveryStatus(
    for step: HumanGuidedDiscoveryStep,
    stageStatus: LearningPathStageStatus
  ) -> LearningPathStageStatus {
    if stageStatus == .complete { return .complete }
    if step == .penInteraction, workspace.penInteractionCompleted { return .complete }
    if step == .boundaryDiscovery, workspace.relevantBoundaryObservationCount > 0 {
      return .complete
    }
    if step == workspace.humanGuidedDiscoveryCurrentStep {
      return stageStatus == .needsAttention ? .needsAttention : .current
    }
    return step.rawValue < workspace.humanGuidedDiscoveryCurrentStep.rawValue ? .complete : .next
  }

  private func drawingTrialStatus(
    for step: ObservedDrawingTrialStep,
    stageStatus: LearningPathStageStatus
  ) -> LearningPathStageStatus {
    if stageStatus == .future { return .future }
    if stageStatus == .complete { return .complete }
    guard let action = workspace.currentOperatorActionPresentation,
      let current = ObservedDrawingTrialStep.allCases.first(where: {
        $0.stepNumber == action.stepNumber
      })
    else {
      return stageStatus == .current ? .next : stageStatus
    }
    if step == current {
      return stageStatus == .needsAttention ? .needsAttention : .current
    }
    return step.rawValue < current.rawValue ? .complete : .next
  }

  private func stageBorderColor(_ status: LearningPathStageStatus) -> Color {
    switch status {
    case .complete: .green.opacity(0.5)
    case .current: .accentColor.opacity(0.7)
    case .next, .future: .secondary.opacity(0.25)
    case .needsAttention: .orange.opacity(0.8)
    }
  }

  private func statusColor(_ status: LearningPathStageStatus) -> Color {
    switch status {
    case .complete: .green
    case .current: .accentColor
    case .next: .secondary
    case .future: .secondary
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

  private func discoverySequenceID(for direction: BoundaryDirection) -> DiscoverySequenceID {
    switch direction {
    case .negativeX: .boundaryNegativeX
    case .positiveX: .boundaryPositiveX
    case .negativeY: .boundaryNegativeY
    case .positiveY: .boundaryPositiveY
    }
  }

}
