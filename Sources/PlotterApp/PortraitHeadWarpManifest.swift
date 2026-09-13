import Foundation

struct PortraitHeadWarpBasis: Codable, Hashable, Sendable {
  let origin: PortraitLandmarkPoint
  let xAxis: PortraitLandmarkPoint
  let yAxis: PortraitLandmarkPoint
  let cropWidthSourcePixels: Double
  let cropHeightSourcePixels: Double
  let rasterWidth: Int
  let rasterHeight: Int
}

struct PortraitHeadWarpAnchor: Codable, Hashable, Sendable {
  enum Evidence: String, Codable, Hashable, Sendable { case measured, estimated, unavailable }
  let name: String
  let evidence: Evidence
  let point: PortraitLandmarkPoint?
  let derivation: String
}

/// A compact C2 vector field w(q) * (A*q+b), w=(1-r²)^3 within
/// the ellipse and zero outside. Repeated Euler maps are diffeomorphisms:
/// ||h Dv|| < 1, hence each map has positive determinant everywhere.
struct PortraitHeadWarpKernel: Codable, Hashable, Sendable {
  let name: String
  let center: PortraitLandmarkPoint
  let radius: PortraitLandmarkPoint
  let expansion: PortraitLandmarkPoint
  let translation: PortraitLandmarkPoint
  let steps: Int
  let derivativeNormBound: Double
  let displacementBound: Double
}

struct PortraitHeadWarpManifest: Codable, Hashable, Sendable {
  enum Status: String, Codable, Hashable, Sendable { case applied, limited, unavailable, identity, legacy }
  var schemaVersion = 1
  var algorithmRevision = "semantic-head-compact-flow-v1"
  let status: Status
  let summary: String
  let analysisSHA256: String?
  let basis: PortraitHeadWarpBasis?
  let anchors: [PortraitHeadWarpAnchor]
  let requested: PortraitSemanticHeadParameters
  let effective: PortraitSemanticHeadParameters
  let kernels: [PortraitHeadWarpKernel]
  /// Analytic lower bound on the full composed map's determinant, not a grid estimate.
  let minimumJacobianDeterminant: Double
  /// Conservative sum of field bounds in original source pixels; not physical millimeters.
  let maximumDisplacementSourcePixels: Double
}
