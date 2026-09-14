import Foundation
import PlotterModel

/// The immutable display context of a new screen rating. Reference previews
/// preserve a rendering normalization without asserting a physical placement.
struct PortraitDisplayEvidence: Codable, Hashable, Sendable {
  enum Mode: String, Codable, Hashable, Sendable { case reference, planned }
  enum WidthSource: String, Codable, Hashable, Sendable { case applicableMaterial, nominalProgram }

  let mode: Mode
  let programContentHash: String
  let region: DrawableMachineRegion?
  let placement: DrawingPlacement?
  let planContentHash: String?
  let widthSource: WidthSource

  init(mode: Mode, programContentHash: String, region: DrawableMachineRegion? = nil,
    placement: DrawingPlacement? = nil, planContentHash: String? = nil,
    widthSource: WidthSource) throws {
    self.mode = mode
    self.programContentHash = programContentHash
    self.region = region
    self.placement = placement
    self.planContentHash = planContentHash
    self.widthSource = widthSource
    try validate()
  }

  func validate() throws {
    guard Self.isDigest(programContentHash) else { throw PortraitCandidateError.invalidPresentation }
    switch mode {
    case .reference:
      guard placement == nil, planContentHash == nil else { throw PortraitCandidateError.invalidPresentation }
    case .planned:
      guard region != nil, placement != nil, let planContentHash, Self.isDigest(planContentHash) else {
        throw PortraitCandidateError.invalidPresentation
      }
    }
  }

  private static func isDigest(_ value: String) -> Bool {
    value.count == 64 && value.allSatisfy(\.isHexDigit)
  }

  private enum CodingKeys: String, CodingKey {
    case mode, programContentHash, region, placement, planContentHash, widthSource
  }

  init(from decoder: any Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    try self.init(mode: values.decode(Mode.self, forKey: .mode),
      programContentHash: values.decode(String.self, forKey: .programContentHash),
      region: values.decodeIfPresent(DrawableMachineRegion.self, forKey: .region),
      placement: values.decodeIfPresent(DrawingPlacement.self, forKey: .placement),
      planContentHash: values.decodeIfPresent(String.self, forKey: .planContentHash),
      widthSource: values.decode(WidthSource.self, forKey: .widthSource))
  }
}
