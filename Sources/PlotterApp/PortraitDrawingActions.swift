import PlotterModel
import PlotterUI

extension PlotterApplicationRuntime {
  /// Qualify the immutable candidate only after camera selection, exact program
  /// admission and Fit succeed through the ordinary production intent path.
  func projectPortrait(_ candidate: PortraitCandidate) async -> String? {
    await portraitStudio.acceptProjection(candidate) {
      let program = candidate.program
      if let error = await submitPortraitDrawingAction(PlotterAppUIActionID.observationCameraRole(.plotter)) {
        return error
      }
      if drawingDraftSnapshot.artworkPlan?.sourceProgramContentHash == program.contentHash {
        return await submitPortraitDrawingAction(PlotterAppUIActionID.drawingDraft(.showTarget))
      }
      if let error = await submitPortraitDrawingAction(
        PlotterAppUIActionID.drawingDraft(.selectProgram(program)), program: program
      ) { return error }
      return await submitPortraitDrawingAction(PlotterAppUIActionID.drawingDraft(.fitInDrawableRegion))
    }
  }

  /// Adapt at the current final scale and preserve that exact placement when
  /// accepting the new candidate. Rendering does not independently authorize Draw.
  func applyPortraitMaterial(_ profile: DrawingMaterialProfileRevision) async -> String? {
    guard let prior = portraitStudio.selectedCandidate,
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
      let candidate = portraitStudio.selectedCandidate
    else { return "Drawing placement or material changed during adaptation. The generated candidate is retained; review it before projection." }
    let projectionError = await portraitStudio.acceptProjection(candidate) {
      if let error = await submitPortraitDrawingAction(
        PlotterAppUIActionID.drawingDraft(.selectProgram(candidate.program)), program: candidate.program
      ) { return error }
      guard drawingDraftSnapshot.artworkPlan?.placement == artworkPlan.placement else {
        return "The adapted drawing could not retain its exact placement. Review its scale before drawing."
      }
      return nil
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
