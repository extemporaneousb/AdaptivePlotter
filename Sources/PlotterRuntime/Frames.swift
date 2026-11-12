import Foundation
@_exported import PlotterModel

/// Geometry is expressed in canonical camera pixels: origin at the top-left,
/// +X right, +Y down. Preview-space coordinates are deliberately absent.
public enum CameraPixelGeometry: Codable, Hashable, Sendable {
  case point(Point2<CameraPixelSpace>)
  case bounds(AxisAlignedBounds<CameraPixelSpace>)
  case polyline(Polyline<CameraPixelSpace>)
}

/// Semantic overlay identity. Rendering and operator visibility use this typed
/// value instead of matching ad-hoc strings produced by individual algorithms.
public enum CameraOverlayKind: String, Codable, CaseIterable, Hashable, Sendable {
  case intendedPath
  case calibrationGuide
  case observedInk
  case residual
  case acceptedBoundary
  // Preserve the durable raw value used by existing overlay archives.
  case drawingBorder = "calibratedDrawableRegion"
  case drawingRegion
  case paperCoverage
  case predictedContactPoint
  case penCap
  case armatureEstimate
  case diagnostic
}

/// Describes what sort of claim an overlay makes. In particular, an inferred
/// envelope and a simulated observation must never look like direct camera
/// measurement merely because they share camera-pixel geometry.
public enum CameraOverlaySource: String, Codable, Hashable, Sendable {
  case measured
  case inferred
  case planned
  case simulated
  case diagnostic
}

public struct CameraMeasurementProvenance: Codable, Hashable, Sendable {
  public let kind: CameraOverlayKind
  public let source: CameraOverlaySource
  public let algorithmRevision: String

  public init(
    kind: CameraOverlayKind,
    source: CameraOverlaySource,
    algorithmRevision: String
  ) {
    self.kind = kind
    self.source = source
    self.algorithmRevision = algorithmRevision
  }
}

/// Retains the exact pixels from which a measurement was derived. Evidence and
/// point selection use exact matching. A live preview may display the last
/// measured geometry with its original provenance; it must not relabel that
/// geometry as a measurement of newer pixels or another camera configuration.
public struct CameraOverlayMeasurement: Codable, Hashable, Sendable {
  public let frameID: FrameID
  public let cameraConfigurationID: CameraConfigurationID
  public let geometry: CameraPixelGeometry
  public let provenance: CameraMeasurementProvenance

  public init(
    frameID: FrameID,
    cameraConfigurationID: CameraConfigurationID,
    geometry: CameraPixelGeometry,
    provenance: CameraMeasurementProvenance
  ) {
    self.frameID = frameID
    self.cameraConfigurationID = cameraConfigurationID
    self.geometry = geometry
    self.provenance = provenance
  }

  public func matches(_ displayedFrame: DisplayedFrame) -> Bool {
    frameID == displayedFrame.frame.id
      && cameraConfigurationID == displayedFrame.frame.cameraConfigurationID
  }
}
