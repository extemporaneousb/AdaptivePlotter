import Foundation
import PlotterEpisodeRuntime
import SwiftUI

/// A view of existing operation owners; this does not admit or run work.
struct WorkbenchComputationPresentation: Hashable {
  let title: String
  let detail: String
}

extension PlotterApplicationRuntime {
  var workbenchComputationPresentation: WorkbenchComputationPresentation? {
    if let owner = exactWorkflowVisionOwner {
      return .init(title: "Analyzing \(owner.operatorLabel)",
        detail: "Comparing camera evidence. This step does not require another click.")
    }
    if borderValidationSnapshot.activeOperationID != nil {
      return .init(title: borderValidationSnapshot.step.title,
        detail: "Drawing Border validation is running. The next phase starts automatically.")
    }
    if let snapshot = drawingRunSnapshot,
      snapshot.activeRunID != nil || snapshot.phase == .appendingEvidence {
      let execution = DrawingStudioExecutionPresentation(snapshot: snapshot,
        phaseDetail: drawingRunPhaseDetail(snapshot.phase))
      return .init(title: execution.drawingIsDone ? "Drawing done" : "Drawing in progress",
        detail: execution.detail)
    }
    if let reason = currentCameraCalibrationBusyReason {
      return .init(title: "Calibrating camera", detail: reason)
    }
    return nil
  }
}

/// The clock updates this small view, never the workbench projection.
struct WorkbenchComputationStatus: View {
  let application: PlotterApplicationRuntime

  var body: some View {
    if let presentation = application.workbenchComputationPresentation {
      WorkbenchComputationPhaseView(presentation: presentation)
        .id(presentation)
    }
  }
}

struct WorkbenchComputationPhaseView: View {
  let presentation: WorkbenchComputationPresentation
  @State private var startedAt = Date()

  var body: some View {
    HStack(spacing: 10) {
      ProgressView().controlSize(.small)
      VStack(alignment: .leading, spacing: 2) {
        Text(presentation.title).font(.callout.bold())
        Text(presentation.detail).font(.caption).foregroundStyle(.secondary)
      }
      Spacer()
      TimelineView(.periodic(from: startedAt, by: 1)) { context in
        Text("\(Int(max(0, context.date.timeIntervalSince(startedAt)))) s")
          .font(.callout.monospacedDigit())
          .accessibilityLabel("Elapsed time in this phase")
      }
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 8)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(.quaternary)
    .accessibilityElement(children: .combine)
    .onAppear { WorkbenchRequestTelemetry.phase(presentation.title, isStarting: true) }
    .onDisappear { WorkbenchRequestTelemetry.phase(presentation.title, isStarting: false) }
  }
}
