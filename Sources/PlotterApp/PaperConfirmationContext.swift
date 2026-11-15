import Foundation
import PlotterEpisodeModel
import PlotterEpisodeRuntime
import PlotterModel
import PlotterRuntime

/// Stable parts of the area an operator confirms. A new sheet deliberately
/// changes paper identity and run history, and ambient video may advance;
/// neither permits a different placement, calibration, tool, or contact plane.
struct PaperConfirmationContext: Equatable {
  let environment: PlotterEnvironment
  let placementID: UUID
  let cameraConfigurationID: CameraConfigurationID?
  let programHash: PlotterModel.Digest?
  let registrationRevision: LearningArtifactRevisionID?
  let opticalConfiguration: CameraOpticalConfigurationIdentity?
  let drawableRegion: DrawableMachineRegion?
  let placementGuide: PlotterDrawingDraftPlacementGuide?
  let contactPlane: PaperContactPlaneRevision
  let tool: ToolAssemblyRevision

  init(draft: PlotterDrawingDraftSnapshot, facts: PlotterDrawingDraftExternalFactRevisions) {
    environment = facts.environment
    placementID = draft.placementID
    cameraConfigurationID = facts.displayedFrame?.cameraConfigurationID
    programHash = draft.program?.contentHash
    registrationRevision = facts.registrationRevisionID
    opticalConfiguration = facts.opticalConfiguration
    drawableRegion = facts.drawableRegion
    placementGuide = facts.placementGuide
    contactPlane = facts.paper.contactPlane
    tool = facts.toolAssemblyRevision
  }
}
