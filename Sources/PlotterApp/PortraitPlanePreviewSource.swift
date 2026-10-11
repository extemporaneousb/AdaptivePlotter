import PlotterModel
import PortraitStudioUI

extension PlotterApplicationRuntime {
  var portraitPlanePreviewSource: PortraitPlanePreviewSource {
    let record = drawingMaterials.activeRecord
    let applicable = record.map {
      $0.profile.qualification == .nominal ||
        ($0.profile.qualification != .unavailable && $0.applicability != nil
          && $0.applicability == currentMaterialApplicability)
    } ?? false
    return PortraitPlanePreviewSource(region: drawingDraftSnapshot.projection.externalFacts.drawableRegion,
      artworkPlan: drawingDraftSnapshot.artworkPlan, material: applicable ? record?.profile : nil,
      materialUnavailableReason: record != nil && !applicable ? "Active material is not applicable to the current setup." : nil)
  }
}
