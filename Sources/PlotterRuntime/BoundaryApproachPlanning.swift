import Foundation
import PlotterModel

public struct BoundaryMotionSegmentProgress: Hashable, Sendable {
  public let ownerID: BoundaryMotionOwnerID
  public let direction: BoundaryDirection
  public let completedSegmentCount: Int
  public let completedSegment: RelativeJogRequest
  public let startPosition: MachinePosition
  public let finalPosition: MachinePosition

  public init(
    ownerID: BoundaryMotionOwnerID,
    direction: BoundaryDirection,
    completedSegmentCount: Int,
    completedSegment: RelativeJogRequest,
    startPosition: MachinePosition,
    finalPosition: MachinePosition
  ) {
    self.ownerID = ownerID
    self.direction = direction
    self.completedSegmentCount = completedSegmentCount
    self.completedSegment = completedSegment
    self.startPosition = startPosition
    self.finalPosition = finalPosition
  }
}

/// Async injection seam. It returns only a length, so renewal policy cannot
/// alter the admitted direction or controller-derived feed.
public struct BoundaryMotionRenewalPlanner: Sendable {
  private let resolve: @Sendable (BoundaryMotionSegmentProgress) async -> Double?

  public init(
    _ resolve: @escaping @Sendable (BoundaryMotionSegmentProgress) async -> Double?
  ) {
    self.resolve = resolve
  }

  public func nextSegmentLength(
    after progress: BoundaryMotionSegmentProgress
  ) async -> Double? {
    await resolve(progress)
  }
}
