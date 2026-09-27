import Foundation
import PlotterModel

public enum DrawingRunObservationPlanError: Error, Equatable, Sendable {
  case invalidPolicy, currentPositionOutsideAcceptedBounds, drawingOutsideAcceptedBounds
}

public struct DrawingRunObservationPose: Codable, Hashable, Sendable {
  public let id: UUID
  public let position: MachinePosition
  /// Distance from the conservative rectangle containing the planned drawing.
  /// This is an XY geometric fact, not measured armature or paper visibility.
  public let minimumGeometryClearanceMM: Double
}

/// An immutable proposal consumed by the existing run owner. It cannot dispatch
/// movement. In particular a terminal failure/Stop does not authorize its poses.
public struct DrawingRunObservationPlan: Codable, Hashable, Sendable {
  public enum Mode: String, Codable, Hashable, Sendable { case singlePose, multiPose }
  public enum Policy: String, Sendable {
    case nearestClearing = "accepted-bounds-drawing-rectangle-v1"
    case carriagePark = "accepted-bounds-carriage-park-v2"
  }
  public let executionPlanRevisionID: ExecutionPlanRevisionID
  public let acceptedMovementBounds: AxisAlignedBounds<MachineSpace>
  public let currentPosition: MachinePosition
  public let requestedClearanceMM: Double
  public let poses: [DrawingRunObservationPose]
  public let mode: Mode
  public let requestedClearanceAchieved: Bool
  public let requiredPenState: PenState
  public let limitations: [String]
  public let derivationVersion: String

  public init(executionPlan: ExecutionPlanRevision,
    acceptedMovementBounds bounds: AxisAlignedBounds<MachineSpace>,
    currentPosition: MachinePosition, requestedClearanceMM: Double = 10,
    maximumPoseCount: Int = 3, policy: Policy = .carriagePark) throws {
    guard requestedClearanceMM.isFinite, requestedClearanceMM > 0,
      (1...3).contains(maximumPoseCount) else { throw DrawingRunObservationPlanError.invalidPolicy }
    guard bounds.contains(currentPosition.point) else {
      throw DrawingRunObservationPlanError.currentPositionOutsideAcceptedBounds
    }
    let points = executionPlan.strokes.flatMap { $0.path.points }
    guard !points.isEmpty, points.allSatisfy({ bounds.contains($0) }) else {
      throw DrawingRunObservationPlanError.drawingOutsideAcceptedBounds
    }
    let minX = points.map(\.x).min()!, maxX = points.map(\.x).max()!
    let minY = points.map(\.y).min()!, maxY = points.map(\.y).max()!
    func clearance(_ p: Point2<MachineSpace>) -> Double {
      hypot(max(minX - p.x, 0, p.x - maxX), max(minY - p.y, 0, p.y - maxY))
    }
    let x = currentPosition.point.x, y = currentPosition.point.y
    var candidates = [currentPosition.point]
    func add(_ px: Double, _ py: Double) throws {
      let p = try Point2<MachineSpace>(x: max(bounds.minX, min(bounds.maxX, px)),
        y: max(bounds.minY, min(bounds.maxY, py)))
      if !candidates.contains(p) { candidates.append(p) }
    }
    // Bounded edge projections include nearby clearing positions; corners cover
    // diagonal clearances when neither side alone admits the requested margin.
    for px in [bounds.minX, minX-requestedClearanceMM, maxX+requestedClearanceMM, bounds.maxX] {
      try add(px, y)
      for py in [bounds.minY, bounds.maxY] { try add(px, py) }
    }
    for py in [bounds.minY, minY-requestedClearanceMM, maxY+requestedClearanceMM, bounds.maxY] {
      try add(x, py)
    }
    func nearer(_ a: Point2<MachineSpace>, _ b: Point2<MachineSpace>) -> Bool {
      let da = a.distance(to: currentPosition.point), db = b.distance(to: currentPosition.point)
      return da == db ? (a.x == b.x ? a.y < b.y : a.x < b.x) : da < db
    }
    let clearing = candidates.filter { clearance($0) >= requestedClearanceMM }.sorted(by: nearer)
    var selected: [Point2<MachineSpace>]
    if policy == .carriagePark {
      // The supported carriage extends behind the pen along Y. Merely raising
      // the tip beyond the upper drawing edge leaves its rails over the image.
      // Park at the minimum-Y accepted edge and the X edge with most lateral
      // clearance. This remains a geometric proposal, not measured visibility.
      let left = try Point2<MachineSpace>(x: bounds.minX, y: bounds.minY)
      let right = try Point2<MachineSpace>(x: bounds.maxX, y: bounds.minY)
      let leftGap = minX - bounds.minX, rightGap = bounds.maxX - maxX
      selected = [leftGap == rightGap ? (nearer(left, right) ? left : right)
        : leftGap > rightGap ? left : right]
    } else if let first = clearing.first {
      selected = [first]
    } else {
      // Geometric shortfall is explicit. Additional poses maximize separation;
      // they provide opportunities for actual masks, never presumed coverage.
      candidates.sort {
        clearance($0) == clearance($1) ? nearer($0, $1) : clearance($0) > clearance($1)
      }
      selected = [candidates.removeFirst()]
      while selected.count < maximumPoseCount, !candidates.isEmpty {
        let best = candidates.indices.max { a, b in
          let da = selected.map { $0.distance(to: candidates[a]) }.min()!
          let db = selected.map { $0.distance(to: candidates[b]) }.min()!
          return da == db ? nearer(candidates[b], candidates[a]) : da < db
        }!
        selected.append(candidates.remove(at: best))
      }
    }
    self.executionPlanRevisionID = executionPlan.revisionID
    acceptedMovementBounds = bounds
    self.currentPosition = currentPosition
    self.requestedClearanceMM = requestedClearanceMM
    poses = selected.map { DrawingRunObservationPose(id: UUID(), position: MachinePosition(point: $0),
      minimumGeometryClearanceMM: clearance($0)) }
    mode = selected.count == 1 ? .singlePose : .multiPose
    requestedClearanceAchieved = selected.contains { clearance($0) >= requestedClearanceMM }
    requiredPenState = .up
    derivationVersion = policy.rawValue
    limitations = [
      "XY clearance excludes an unmeasured armature envelope; actual visibility remains unknown until exact-frame evidence establishes it.",
      "Only the run owner may execute these pen-up poses; Stop, failed execution or ambiguous motion prohibits automatic photo repositioning."
    ] + (requestedClearanceAchieved ? [] : [policy == .nearestClearing
      ? "No candidate achieves the requested drawing-region clearance inside accepted movement bounds; coverage may remain incomplete."
      : "The bounded carriage park cannot achieve the requested drawing-region clearance; final visibility remains unverified."])
  }
}

extension DrawingRunObservationPlan {
  /// Reconstruct geometric decisions against the intent's retained execution
  /// plan. A decoded proposal remains evidence, never permission to resume.
  public func validate(executionPlan: ExecutionPlanRevision) throws {
    guard (1...3).contains(poses.count), Set(poses.map(\.id)).count == poses.count,
      requiredPenState == .up, executionPlanRevisionID == executionPlan.revisionID else {
      throw DrawingRunObservationPlanError.invalidPolicy
    }
    guard let policy = Policy(rawValue: derivationVersion) else {
      throw DrawingRunObservationPlanError.invalidPolicy
    }
    let rebuilt = try DrawingRunObservationPlan(executionPlan: executionPlan,
      acceptedMovementBounds: acceptedMovementBounds, currentPosition: currentPosition,
      requestedClearanceMM: requestedClearanceMM, maximumPoseCount: poses.count, policy: policy)
    guard rebuilt.poses.map(\.position) == poses.map(\.position),
      rebuilt.poses.map(\.minimumGeometryClearanceMM) == poses.map(\.minimumGeometryClearanceMM),
      rebuilt.mode == mode, rebuilt.requestedClearanceAchieved == requestedClearanceAchieved,
      rebuilt.derivationVersion == derivationVersion, rebuilt.limitations == limitations else {
      throw DrawingRunObservationPlanError.invalidPolicy
    }
  }
}
