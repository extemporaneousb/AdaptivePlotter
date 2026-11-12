import Foundation
import PortraitCore
import PortraitArtists
import PortraitLibrary
import PlotterModel
import PlotterUI

extension PlotterApplicationRuntime {
  /// Explicit Plot retains first; projection then passes the same admitted value directly.
  func projectDrawing(_ drawing: Drawing, isStillCurrent: () -> Bool = { true }) async -> String? {
    let selectionEpoch = portraitStudio.selectionEpoch
    let draftRevision = drawingDraftSnapshot.projection.draftRevision
    let priorProjection = portraitStudio.projectedDrawing?.reference
    do {
      try drawing.capabilities.require(.plot)
      let retained = try await portraitStudio.sketches.retain(drawing, reason: "plot-handoff")
      try retained.capabilities.require(.plot)
      guard !Task.isCancelled, isStillCurrent(), portraitStudio.selectionEpoch == selectionEpoch,
        drawingDraftSnapshot.projection.draftRevision == draftRevision else { return "Drawing handoff was cancelled." }
      try await portraitStudio.projectDrawing(retained, isStillCurrent: {
        !Task.isCancelled && isStillCurrent()
          && drawingDraftSnapshot.projection.draftRevision == draftRevision
          && portraitStudio.projectedDrawing?.reference == priorProjection
      })
      let ref = retained.reference
      func assertCurrent() throws {
        guard !Task.isCancelled, isStillCurrent(), portraitStudio.projectedDrawing?.reference == ref else {
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
      let drawing = portraitStudio.projectedDrawing,
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

  func saveCurrentDrawing() async -> String? {
    let snapshot = drawingDraftSnapshot
    guard let program = snapshot.authoredProgram else { return "Select an authored drawing before Save Drawing." }
    do {
      let drawing: Drawing
      if let projected = portraitStudio.projectedDrawing, projected.program == program { drawing = projected }
      else { drawing = try sourceFreeDrawing(program) }
      _ = try await portraitStudio.saveAuthoredDrawing(drawing) {
        drawingDraftSnapshot.projection.draftRevision == snapshot.projection.draftRevision
          && drawingDraftSnapshot.authoredProgram == snapshot.authoredProgram
      }
      return nil
    } catch { return error.localizedDescription }
  }

  /// Adapt at the current final scale and preserve that exact placement when
  /// accepting the new candidate. Rendering does not independently authorize Draw.
  func applyPortraitMaterial(_ profile: DrawingMaterialProfileRevision) async -> String? {
    guard let prior = portraitStudio.currentDrawing,
      let artworkPlan = drawingDraftSnapshot.artworkPlan,
      artworkPlan.sourceProgramContentHash == prior.program.contentHash,
      let plan = drawingDraftSnapshot.plan
    else { return "Project the selected portrait before adapting it to the current drawing scale." }
    if profile.qualification != .nominal && profile.qualification != .unavailable,
      drawingMaterials.activeRecord?.applicability != currentMaterialApplicability {
      return "The measured material's calibration, paper or actuation has changed. Measure it again or select nominal settings."
    }
    if let error = await portraitStudio.applyMaterial(profile,
      drawingHeightMM: prior.program.fieldExtent.height * artworkPlan.placement.minimumScale) { return error }
    guard drawingDraftSnapshot.plan?.contentHash == plan.contentHash,
      drawingMaterials.activeKey == profile.key,
      let candidate = portraitStudio.currentDrawing
    else { return "Drawing placement or material changed during adaptation. The generated candidate is retained; review it before projection." }
    let projectionError = await portraitStudio.acceptDrawingProjection(candidate) {
      if let error = await submitPortraitDrawingAction(
        PlotterAppUIActionID.drawingDraft(.selectProgram(candidate.program)), program: candidate.program
      ) { throw PlotterModelError.invalidValue(error) }
      guard drawingDraftSnapshot.artworkPlan?.placement == artworkPlan.placement else {
        throw PlotterModelError.invalidValue("The adapted drawing could not retain its exact placement. Review its scale before drawing.")
      }
    }
    if let projectionError { return projectionError }
    return await assessCurrentMaterial()
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
