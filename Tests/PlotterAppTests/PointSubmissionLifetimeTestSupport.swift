import Foundation
import Observation
import os
import PlotterEpisodeModel
import PlotterUI
import Testing
@testable import PlotterApp

private struct PointSubmissionCancellationState {
  var task: Task<PlotterUIRequestDisposition, Never>?
  var cancelled = false
}

/// Mirrors SwiftUI invalidating its submitting task when accepting a point
/// changes the rendered selection projection, before continuation completes.
@MainActor
func submitPointCancellingCallerOnProjectionChange(
  _ app: PlotterApplicationRuntime, request: PlotterUIRequest
) async -> PlotterUIRequestDisposition {
  let state = OSAllocatedUnfairLock(initialState: PointSubmissionCancellationState())
  withObservationTracking {
    _ = app.pointSelectionEpisodeProjection
  } onChange: {
    state.withLock {
      $0.cancelled = true
      $0.task?.cancel()
    }
  }
  let task = Task { @MainActor in await app.submitPlotterUIRequest(request) }
  state.withLock { $0.task = task }
  let disposition = await task.value
  #expect(state.withLock { $0.cancelled })
  #expect(task.isCancelled)
  return disposition
}

@MainActor
final class CapCommitCancellationProbe {
  private(set) var task: Task<PlotterUIRequestDisposition?, Never>?
  private(set) var reachedCommittedOwner = false

  func arm(_ app: PlotterApplicationRuntime) {
    withObservationTracking {
      _ = app.livePenCapAppearanceSelection
    } onChange: {
      Task { @MainActor in
        self.reachedCommittedOwner = app.learningSelectionDiagnosticSnapshot.recoveryAttemptID != nil
        self.task = Task { @MainActor in
          guard app.learningSelectionDiagnosticSnapshot.recoveryAttemptID != nil else { return nil }
          let projection = app.testPlotterUIProjection(selectedItemID: app.currentLearningPathItemID,
            includesLearningPath: true).semantic
          guard let request = projection.request(for: PlotterAppUIActionID.reidentifyPenCap) else { return nil }
          return await app.submitPlotterUIRequest(request)
        }
      }
    }
  }
}
