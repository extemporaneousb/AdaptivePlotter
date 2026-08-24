/// Spatial admission for commanded drawing geometry against an accepted region.
///
/// This policy is intentionally independent of controller-position settlement:
/// axis-aligned containment and Euclidean pose residual are different metrics
/// with different owners and revisions.
public enum DrawingRegionContainmentPolicy {
  public enum Metric: String, Codable, Hashable, Sendable {
    case axisAlignedClosedBounds
  }

  public enum Revision: String, Codable, Hashable, Sendable {
    case acceptedBoundaryNumericalEpsilonV1
  }

  public static let metric = Metric.axisAlignedClosedBounds
  public static let revision = Revision.acceptedBoundaryNumericalEpsilonV1

  /// Absorbs floating-point residue without admitting physically meaningful
  /// geometry outside the accepted Drawing Boundary.
  public static let numericalEpsilonMM = 1e-9

  public static func contains(
    _ point: Point2<MachineSpace>,
    in bounds: AxisAlignedBounds<MachineSpace>
  ) -> Bool {
    bounds.contains(point, tolerance: numericalEpsilonMM)
  }

  public static func contains(
    _ polyline: Polyline<MachineSpace>,
    in bounds: AxisAlignedBounds<MachineSpace>
  ) -> Bool {
    polyline.points.allSatisfy { contains($0, in: bounds) }
  }

  public static func containsCircle(
    center: Point2<MachineSpace>,
    radiusMM: Double,
    in bounds: AxisAlignedBounds<MachineSpace>
  ) -> Bool {
    radiusMM.isFinite && radiusMM >= 0
      && center.x - radiusMM >= bounds.minX - numericalEpsilonMM
      && center.x + radiusMM <= bounds.maxX + numericalEpsilonMM
      && center.y - radiusMM >= bounds.minY - numericalEpsilonMM
      && center.y + radiusMM <= bounds.maxY + numericalEpsilonMM
  }
}
