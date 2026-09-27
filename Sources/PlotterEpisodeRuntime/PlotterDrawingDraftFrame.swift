import PlotterModel

/// A projection of the authored frame, independent of composed or clipped ink.
/// The affine response is the same accepted response used by DrawingPlacement.
public struct PlotterDrawingDraftFrame: Hashable, Sendable {
  public let geometry: DrawingFrameGeometry
  public let boundary: DrawableMachineRegion
  public let cameraFromMachine: AffineTransform2<MachineSpace, CameraPixelSpace>

  public init(geometry: DrawingFrameGeometry, boundary: DrawableMachineRegion,
    cameraFromMachine: AffineTransform2<MachineSpace, CameraPixelSpace>) {
    self.geometry = geometry
    self.boundary = boundary
    self.cameraFromMachine = cameraFromMachine
  }

  public var cameraCorners: [Point2<CameraPixelSpace>] {
    get throws { try geometry.machineCorners.map { try cameraFromMachine.applying(to: $0) } }
  }

  public var cameraCenter: Point2<CameraPixelSpace> {
    get throws { try cameraFromMachine.applying(to: geometry.placement.machineAnchor) }
  }

  public func replacing(geometry: DrawingFrameGeometry) -> Self {
    Self(geometry: geometry, boundary: boundary, cameraFromMachine: cameraFromMachine)
  }

  public func translated(to center: Point2<CameraPixelSpace>) throws -> Self {
    let machine = try cameraFromMachine.inverted().applying(to: center)
    return replacing(geometry: try geometry.replacing(center: machine).constrained(to: boundary))
  }

  public func resized(scale: Double, minimumScale: Double) throws -> Self {
    let maximum = try geometry.maximumScaleKeepingCenter(in: boundary)
    return replacing(geometry: try geometry.replacing(scale: max(min(minimumScale, maximum), min(scale, maximum))))
  }
}
