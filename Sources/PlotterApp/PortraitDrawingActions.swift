import Foundation
import PortraitCore
import PortraitLibrary
import PlotterModel
import PlotterUI

extension PlotterApplicationRuntime {
  /// Explicit Plot retains first; projection then passes the same admitted value directly.
  func projectDrawing(_ drawing: Drawing, isStillCurrent: () -> Bool = { true }) async -> String? {
    let selectionEpoch = receivedDrawings.selectionEpoch
    let draftRevision = drawingDraftSnapshot.projection.draftRevision
    let priorProjection = receivedDrawings.projectedDrawing?.reference
    do {
      try drawing.capabilities.require(.plot)
      let retained = try await receivedDrawings.sketches.retain(drawing, reason: "plot-handoff")
      try retained.capabilities.require(.plot)
      guard !Task.isCancelled, isStillCurrent(), receivedDrawings.selectionEpoch == selectionEpoch,
        drawingDraftSnapshot.projection.draftRevision == draftRevision else { return "Drawing handoff was cancelled." }
      try await receivedDrawings.projectDrawing(retained, isStillCurrent: {
        !Task.isCancelled && isStillCurrent()
          && drawingDraftSnapshot.projection.draftRevision == draftRevision
          && receivedDrawings.projectedDrawing?.reference == priorProjection
      })
      let ref = retained.reference
      func assertCurrent() throws {
        guard !Task.isCancelled, isStillCurrent(), receivedDrawings.projectedDrawing?.reference == ref else {
          throw CancellationError()
        }
      }
      do {
        let program = retained.program
        if workbenchCameraRole != .plotter || cameraRoleIsTransitioning,
          let error = await submitPortraitDrawingAction(PlotterAppUIActionID.observationCameraRole(.plotter)) {
          throw PlotterModelError.invalidValue(error)
        }
        try assertCurrent()
        if drawingDraftSnapshot.authoredProgram == program,
          drawingDraftSnapshot.artworkPlan?.sourceProgramContentHash == program.contentHash {
          if drawingDraftSnapshot.isTargetVisible { return nil }
          if let error = await submitPortraitDrawingAction(PlotterAppUIActionID.drawingDraft(.showTarget)) {
            throw PlotterModelError.invalidValue(error)
          }
          return nil
        }
        if let error = await submitPortraitDrawingAction(
          PlotterAppUIActionID.drawingDraft(.selectProgram(program)), program: program) {
          throw PlotterModelError.invalidValue(error)
        }
        try assertCurrent()
        if let ref, canShowUnplacedDrawing(ref) { return nil }
        if let error = await submitPortraitDrawingAction(PlotterAppUIActionID.drawingDraft(.fitInDrawableRegion)) {
          throw PlotterModelError.invalidValue(error)
        }
        try assertCurrent()
        return nil
      }
    } catch { return error.localizedDescription }
  }

  /// Use the draft owner's exact authored source and prove the known execution
  /// composition, rather than saving placement/border geometry as new artwork.
  func authoredDrawing(for executionProgram: DrawingProgram) -> Drawing? {
    guard let program = drawingDraftSnapshot.authoredProgram,
      let drawing = receivedDrawings.projectedDrawing,
      drawing.program == program,
      drawing.executionReference(for: executionProgram) != nil else { return nil }
    return drawing
  }

  /// Built-in drafts use a source-free receipt; portrait output must come from its producer.
  func sourceFreeDrawing(_ program: DrawingProgram) throws -> Drawing {
    guard program.source.kind != "portrait" else {
      throw PlotterModelError.invalidValue("The portrait producer receipt is unavailable.")
    }
    let record = try JSONSerialization.data(withJSONObject: ["kind": program.source.kind,
      "sourceIdentifier": program.source.sourceIdentifier], options: [.sortedKeys])
    let receipt = try DrawingProducerReceipt(id: "adaptiveplotter.builtin", version: "1", recordJSON: record)
    return try Drawing(program: program, input: .none, parent: .none, producer: receipt)
  }

  private func submitPortraitDrawingAction(
    _ action: PlotterUIActionID, program: DrawingProgram? = nil
  ) async -> String? {
    let projection = plotterUIProjection(selectedItemID: currentLearningPathItemID,
      manualDraft: ManualMotionDraft(), includesLearningPath: true,
      pendingDrawingProgram: program).semantic
    guard let request = projection.request(for: action) else {
      return projection.action(id: action)?.unavailableReason
        ?? "The requested action is unavailable in the current state."
    }
    if case .refused(let refusal) = await submitPlotterUIRequest(request) { return refusal.remedy }
    return nil
  }
}
