import Foundation

package struct PortraitHeadWarpBasis: Codable, Hashable, Sendable {
  package let origin: PortraitLandmarkPoint
  package let xAxis: PortraitLandmarkPoint
  package let yAxis: PortraitLandmarkPoint
  package let cropWidthSourcePixels: Double
  package let cropHeightSourcePixels: Double
  package let rasterWidth: Int
  package let rasterHeight: Int

  package init(
    origin: PortraitLandmarkPoint,
    xAxis: PortraitLandmarkPoint,
    yAxis: PortraitLandmarkPoint,
    cropWidthSourcePixels: Double,
    cropHeightSourcePixels: Double,
    rasterWidth: Int,
    rasterHeight: Int
  ) {
    self.origin = origin
    self.xAxis = xAxis
    self.yAxis = yAxis
    self.cropWidthSourcePixels = cropWidthSourcePixels
    self.cropHeightSourcePixels = cropHeightSourcePixels
    self.rasterWidth = rasterWidth
    self.rasterHeight = rasterHeight
  }
}

package struct PortraitHeadWarpAnchor: Codable, Hashable, Sendable {
  package enum Evidence: String, Codable, Hashable, Sendable { case measured, estimated, unavailable }
  package let name: String
  package let evidence: Evidence
  package let point: PortraitLandmarkPoint?
  package let derivation: String

  package init(name: String, evidence: Evidence, point: PortraitLandmarkPoint? = nil, derivation: String) {
    self.name = name
    self.evidence = evidence
    self.point = point
    self.derivation = derivation
  }
}

/// A compact C2 vector field w(q) * (A*q+b), w=(1-r²)^3 within
/// the ellipse and zero outside. Repeated Euler maps are diffeomorphisms:
/// ||h Dv|| < 1, hence each map has positive determinant everywhere.
package struct PortraitHeadWarpKernel: Codable, Hashable, Sendable {
  package let name: String
  package let center: PortraitLandmarkPoint
  package let radius: PortraitLandmarkPoint
  package let expansion: PortraitLandmarkPoint
  package let translation: PortraitLandmarkPoint
  package let steps: Int
  package let derivativeNormBound: Double
  package let displacementBound: Double

  package init(
    name: String,
    center: PortraitLandmarkPoint,
    radius: PortraitLandmarkPoint,
    expansion: PortraitLandmarkPoint,
    translation: PortraitLandmarkPoint,
    steps: Int,
    derivativeNormBound: Double,
    displacementBound: Double
  ) {
    self.name = name
    self.center = center
    self.radius = radius
    self.expansion = expansion
    self.translation = translation
    self.steps = steps
    self.derivativeNormBound = derivativeNormBound
    self.displacementBound = displacementBound
  }
}

package struct PortraitHeadWarpManifest: Codable, Hashable, Sendable {
  package enum Status: String, Codable, Hashable, Sendable { case applied, limited, unavailable, identity, legacy }
  package var schemaVersion = 1
  package var algorithmRevision = "semantic-head-compact-flow-v1"
  package let status: Status
  package let summary: String
  package let analysisSHA256: String?
  package let basis: PortraitHeadWarpBasis?
  package let anchors: [PortraitHeadWarpAnchor]
  package let requested: PortraitSemanticHeadParameters
  package let effective: PortraitSemanticHeadParameters
  package let kernels: [PortraitHeadWarpKernel]
  /// Analytic lower bound on the full composed map's determinant, not a grid estimate.
  package let minimumJacobianDeterminant: Double
  /// Conservative sum of field bounds in original source pixels; not physical millimeters.
  package let maximumDisplacementSourcePixels: Double

  package init(
    schemaVersion: Int = 1,
    algorithmRevision: String = "semantic-head-compact-flow-v1",
    status: Status,
    summary: String,
    analysisSHA256: String? = nil,
    basis: PortraitHeadWarpBasis? = nil,
    anchors: [PortraitHeadWarpAnchor],
    requested: PortraitSemanticHeadParameters,
    effective: PortraitSemanticHeadParameters,
    kernels: [PortraitHeadWarpKernel],
    minimumJacobianDeterminant: Double,
    maximumDisplacementSourcePixels: Double
  ) {
    self.schemaVersion = schemaVersion
    self.algorithmRevision = algorithmRevision
    self.status = status
    self.summary = summary
    self.analysisSHA256 = analysisSHA256
    self.basis = basis
    self.anchors = anchors
    self.requested = requested
    self.effective = effective
    self.kernels = kernels
    self.minimumJacobianDeterminant = minimumJacobianDeterminant
    self.maximumDisplacementSourcePixels = maximumDisplacementSourcePixels
  }
}
