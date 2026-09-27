import Foundation

/// The authored rectangle under the existing placement. It is not a second
/// drawable region: the accepted machine Boundary remains the only limit.
public struct DrawingFrameGeometry: Hashable, Sendable {
  public let extent: Size2<FieldSpace>
  public let placement: DrawingPlacement

  public init(extent: Size2<FieldSpace>, placement: DrawingPlacement) {
    self.extent = extent
    self.placement = placement
  }

  public var fieldCorners: [Point2<FieldSpace>] {
    [try! Point2(x: 0, y: 0), try! Point2(x: extent.width, y: 0),
      try! Point2(x: extent.width, y: extent.height), try! Point2(x: 0, y: extent.height)]
  }

  public var machineCorners: [Point2<MachineSpace>] {
    get throws { try fieldCorners.map { try placement.applying(to: $0) } }
  }

  public func isContained(in region: DrawableMachineRegion) -> Bool {
    (try? machineCorners.allSatisfy { region.contains($0) }) == true
  }

  public func replacing(center: Point2<MachineSpace>? = nil, scale: Double? = nil) throws -> Self {
    Self(extent: extent, placement: try DrawingPlacement(fieldAnchor: placement.fieldAnchor,
      machineAnchor: center ?? placement.machineAnchor, uniformScale: scale ?? placement.uniformScale,
      rotationRadians: placement.rotationRadians, cameraGeometry: placement.cameraGeometry))
  }

  /// Uniformly fit the whole authored frame, then translate it inside Boundary.
  /// All callers, including gesture staging and runtime authoring, use these corners.
  public func constrained(to region: DrawableMachineRegion) throws -> Self {
    if isContained(in: region) { return self }
    let bounds = region.effectiveBounds
    let corners = try machineCorners
    let width = corners.map(\.x).max()! - corners.map(\.x).min()!
    let height = corners.map(\.y).max()! - corners.map(\.y).min()!
    let ratio = min(1, (bounds.maxX - bounds.minX) / width, (bounds.maxY - bounds.minY) / height)
    let fitted = ratio < 1 ? try replacing(scale: placement.uniformScale * ratio) : self
    let points = try fitted.machineCorners
    let dx = max(bounds.minX - points.map(\.x).min()!, min(0, bounds.maxX - points.map(\.x).max()!))
    let dy = max(bounds.minY - points.map(\.y).min()!, min(0, bounds.maxY - points.map(\.y).max()!))
    return try fitted.replacing(center: Point2(x: fitted.placement.machineAnchor.x + dx,
      y: fitted.placement.machineAnchor.y + dy))
  }

  /// Resize handles keep the frame center fixed; rotation and authored aspect
  /// are unchanged. The nearest Boundary edge stops expansion.
  public func maximumScaleKeepingCenter(in region: DrawableMachineRegion) throws -> Double {
    let unit = try replacing(scale: 1)
    let center = placement.machineAnchor, bounds = region.effectiveBounds
    var maximum = Double.infinity
    for point in try unit.machineCorners {
      let dx = point.x - center.x, dy = point.y - center.y
      if dx > 0 { maximum = min(maximum, (bounds.maxX - center.x) / dx) }
      if dx < 0 { maximum = min(maximum, (bounds.minX - center.x) / dx) }
      if dy > 0 { maximum = min(maximum, (bounds.maxY - center.y) / dy) }
      if dy < 0 { maximum = min(maximum, (bounds.minY - center.y) / dy) }
    }
    guard maximum.isFinite, maximum > 0 else {
      throw PlotterModelError.invalidValue("The drawing frame center is outside Boundary.")
    }
    return maximum
  }
}
