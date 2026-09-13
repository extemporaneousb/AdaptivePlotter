import Foundation
import PlotterModel

/// Immutable adaptation at an explicitly selected drawing height. The profile
/// value survives library changes; placement changes require a new adaptation.
struct PortraitMaterialContext: Codable, Hashable, Sendable {
  let revision: String
  let profile: DrawingMaterialProfileRevision
  let drawingHeightMM: Double

  init(profile: DrawingMaterialProfileRevision, drawingHeightMM: Double) throws {
    try profile.validate()
    guard drawingHeightMM.isFinite, drawingHeightMM > 0 else { throw PortraitCandidateError.invalidPresentation }
    revision = "portrait-material-v1"; self.profile = profile; self.drawingHeightMM = drawingHeightMM
  }

  private enum CodingKeys: String, CodingKey { case revision, profile, drawingHeightMM }
  init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    guard try values.decode(String.self, forKey: .revision) == "portrait-material-v1" else {
      throw PortraitCandidateError.integrityMismatch
    }
    try self.init(profile: values.decode(DrawingMaterialProfileRevision.self, forKey: .profile),
      drawingHeightMM: values.decode(Double.self, forKey: .drawingHeightMM))
  }

  var provenance: String {
    let profileBytes = try? PortraitCandidateCoding.encoder().encode(profile)
    return "\(revision)|material=\(profile.key)|materialSHA256=\(profileBytes.map(PortraitCandidateCoding.digest) ?? "invalid")|materialWidth=\(profile.conservativeWidthMM)|materialQualification=\(profile.qualification.rawValue)|materialHeight=\(drawingHeightMM)"
  }

  func adapting(_ options: PortraitVectorOptions, raster: PortraitRaster) throws -> PortraitVectorOptions {
    try profile.validate()
    let aspect = raster.sourceCropExtent?.aspectRatio ?? Double(raster.width-1)/Double(raster.height-1)
    let xSamples = Double(raster.sourceCropExtent == nil ? raster.width-1 : raster.width)
    let ySamples = Double(raster.sourceCropExtent == nil ? raster.height-1 : raster.height)
    let minimumPitch = min(drawingHeightMM*aspect/xSamples, drawingHeightMM/ySamples)
    let widthPixels = profile.conservativeWidthMM/minimumPitch
    guard widthPixels.isFinite, widthPixels > 0, widthPixels < 10_000 else {
      throw PortraitCandidateError.invalidPresentation
    }
    var adapted = options
    // This material floor is separate from the operator's bounded style knob.
    // Spacing above the raster height may legitimately yield no usable drawing.
    adapted.hatchSpacing = max(options.hatchSpacing, Int(ceil(widthPixels*1.5)))
    adapted.minimumContourLength = max(options.minimumContourLength, widthPixels)
    return adapted
  }

  func matches(drawingHeightMM: Double, profileKey: String?) -> Bool {
    profile.key == profileKey && drawingHeightMM.isFinite
      && abs(self.drawingHeightMM-drawingHeightMM) <= max(1e-9, abs(drawingHeightMM)*1e-9)
  }
}
