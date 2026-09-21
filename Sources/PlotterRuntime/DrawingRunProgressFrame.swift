import Foundation
import PlotterModel

/// Called only after a stroke and its Pen Up have settled. Awaiting observation
/// keeps the same plan owner; the observer cannot dispatch or resume movement.
public protocol DrawingPlanCheckpointObserver: Sendable {
  func reachedCheckpoint(_ progress: DrawingPlanProgressSnapshot, position: MachinePosition) async
}

/// Original pixels and the exact committed execution frontier at acquisition.
/// A stopped, pen-up controller pose does not prove arm clearance or visible ink.
public struct DrawingRunProgressFrame: Codable, Hashable, Sendable {
  public let media: DrawingRunMediaReference
  public let progress: DrawingPlanProgressSnapshot

  public init(media: DrawingRunMediaReference, progress: DrawingPlanProgressSnapshot) {
    self.media = media; self.progress = progress
  }

  /// Three quarter-run checkpoints, rounded up to completed strokes. Very short
  /// plans retain baseline/final images without intermediate pauses.
  public static func checkpointCounts(plannedStrokeCount count: Int) -> [Int] {
    guard count >= 4 else { return [] }
    return (1...3).map { quarter in
      count / 4 * quarter + (count % 4 * quarter + 3) / 4
    }
  }

  public static func validate(_ frames: [Self], intent: DrawingRunIntent,
    baselines: [DrawingRunMediaReference]) throws {
    guard frames.count <= 3 else { throw DrawingRunEvidenceError.invalidAttemptContext }
    guard !frames.isEmpty else { return }
    let schedule = try DrawingWireSchedule(plan: intent.plan)
    var priorCount = 0
    var priorCapture = baselines.map { $0.frame.captureNanoseconds }.max() ?? 0
    for item in frames {
      let p = item.progress, count = p.completedStrokeIDs.count
      let expected = Array(intent.plan.strokes.prefix(count))
      let completedSegments = schedule.strokes.prefix(count).reduce(0) { $0 + $1.segments.count }
      try item.media.validate()
      guard checkpointCounts(plannedStrokeCount: intent.plan.strokes.count).contains(count),
        count > priorCount, p.operationID.rawValue == intent.requestID,
        p.planRevisionID == intent.plan.revisionID, p.plannedStrokeCount == intent.plan.strokes.count,
        p.commandedStrokeCount == count, p.controllerCompletedStrokeCount == count,
        p.completedStrokeIDs == expected.map(\.logicalStrokeID),
        p.completedCheckpointIDs == expected.map(\.endingCheckpointID),
        p.activeStrokeID == nil, p.activeSegmentIndex == nil,
        p.plannedSegmentCount == schedule.segmentCount,
        p.submittedSegmentCount == completedSegments,
        p.controllerCompletedSegmentCount == completedSegments,
        p.acknowledgedSegmentCount == nil || p.acknowledgedSegmentCount == completedSegments,
        let pose = item.media.controllerPosition, let endpoint = expected.last?.path.points.last,
        MachinePositionAcceptancePolicy.accepts(pose, target: MachinePosition(point: endpoint)),
        let after = item.media.captureAfterNanoseconds, after >= priorCapture,
        after >= intent.recordedAt.monotonicNanoseconds,
        item.media.completionCaptureAfterNanoseconds == nil,
        let baseline = baselines.first, item.media.source == baseline.source,
        item.media.frame.cameraConfigurationID == baseline.frame.cameraConfigurationID,
        item.media.frame.width == baseline.frame.width, item.media.frame.height == baseline.frame.height,
        item.media.frame.pixelFormat == baseline.frame.pixelFormat else {
        throw DrawingRunEvidenceError.invalidAttemptContext
      }
      priorCount = count; priorCapture = item.media.frame.captureNanoseconds
    }
  }
}
