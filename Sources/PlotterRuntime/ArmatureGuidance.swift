import Foundation
import PlotterModel

public enum ArmatureVisibilityLabel: String, Codable, CaseIterable, Hashable, Sendable {
  case clear
  case partial
  case blocked

  fileprivate var score: Double {
    switch self {
    case .clear: 1
    case .partial: 0.5
    case .blocked: 0
    }
  }

  fileprivate static func from(score: Double) -> Self {
    if score >= 0.75 { return .clear }
    if score >= 0.25 { return .partial }
    return .blocked
  }
}

public enum ClearViewSearchDistance: Double, Codable, CaseIterable, Hashable, Sendable {
  case fiftyMillimeters = 50
  case tenMillimeters = 10

  public var millimeters: Double { rawValue }

  public var displayName: String {
    "\(Int(rawValue)) mm"
  }
}

/// One operator-selected finite Pen-Up search move. The direction and distance
/// are both explicit intent; no visibility fit selects or admits this move.
public struct ClearViewSearchMove: Codable, Hashable, Sendable {
  public let direction: BoundaryDirection
  public let distance: ClearViewSearchDistance

  public init(direction: BoundaryDirection, distance: ClearViewSearchDistance) {
    self.direction = direction
    self.distance = distance
  }

  public var delta: Vector2<MachineSpace> {
    let millimeters = distance.millimeters
    return switch direction {
    case .negativeX: try! Vector2<MachineSpace>(dx: -millimeters, dy: 0)
    case .positiveX: try! Vector2<MachineSpace>(dx: millimeters, dy: 0)
    case .negativeY: try! Vector2<MachineSpace>(dx: 0, dy: -millimeters)
    case .positiveY: try! Vector2<MachineSpace>(dx: 0, dy: millimeters)
    }
  }

  public func request(feedMMPerMinute: Double) -> RelativeJogRequest {
    RelativeJogRequest(delta: delta, feedMMPerMinute: feedMMPerMinute)
  }
}

public enum ArmatureGuidanceOutcome: Codable, Hashable, Sendable {
  case continueInDirection(ClearViewSearchMove)
  case reverse
  case stopped
  case acceptedPose
}

public struct ArmatureGuidanceContext: Codable, Hashable, Sendable {
  public let controllerSessionID: UUID
  public let coordinateRevision: UInt64
  public let cameraConfigurationID: CameraConfigurationID
  public let observationRegion: PixelRect
  public let toolPaperRevision: UUID

  public init(
    controllerSessionID: UUID,
    coordinateRevision: UInt64,
    cameraConfigurationID: CameraConfigurationID,
    observationRegion: PixelRect,
    toolPaperRevision: UUID
  ) {
    self.controllerSessionID = controllerSessionID
    self.coordinateRevision = coordinateRevision
    self.cameraConfigurationID = cameraConfigurationID
    self.observationRegion = observationRegion
    self.toolPaperRevision = toolPaperRevision
  }
}

public struct ArmatureRegionOverlapEstimate: Codable, Hashable, Sendable {
  public let fractionOfObservationRegion: Double
  public let visibility: ArmatureVisibilityLabel
  public let conservativeBounds: AxisAlignedBounds<CameraPixelSpace>?

  fileprivate init(
    fractionOfObservationRegion: Double,
    visibility: ArmatureVisibilityLabel,
    conservativeBounds: AxisAlignedBounds<CameraPixelSpace>?
  ) {
    self.fractionOfObservationRegion = fractionOfObservationRegion
    self.visibility = visibility
    self.conservativeBounds = conservativeBounds
  }
}

public struct ArmaturePoseObservationID: RawRepresentable, Codable, Hashable, Sendable {
  public let rawValue: UUID
  public init(rawValue: UUID) { self.rawValue = rawValue }
  public init() { rawValue = UUID() }
}

public struct ArmaturePoseObservation: Codable, Hashable, Sendable, Identifiable {
  public let id: ArmaturePoseObservationID
  public let frameID: FrameID
  public let frameSHA256: String
  public let captureNanoseconds: UInt64
  public let cameraConfigurationID: CameraConfigurationID
  public let controllerPosition: MachinePosition
  public let observationRegion: PixelRect
  public let overlapEstimate: ArmatureRegionOverlapEstimate
  public let humanLabel: ArmatureVisibilityLabel
  public let estimateAgreedWithHuman: Bool
  public let outcome: ArmatureGuidanceOutcome
}

/// A deliberately small current-scene fit. It interpolates the human labels
/// at recorded machine poses; it is visibility guidance, never motion authority.
public struct ArmatureVisibilityFit: Codable, Hashable, Sendable {
  public let distinctPoseCount: Int
  public let labelledPoses: [MachinePosition: ArmatureVisibilityLabel]

  public func estimate(at position: MachinePosition) -> ArmatureVisibilityLabel {
    var ranked: [(label: ArmatureVisibilityLabel, distance: Double)] = []
    for (labelledPosition, label) in labelledPoses {
      let distance = labelledPosition.point.distance(to: position.point)
      ranked.append((label: label, distance: distance))
    }
    ranked.sort { lhs, rhs in
      lhs.distance == rhs.distance
        ? lhs.label.rawValue < rhs.label.rawValue
        : lhs.distance < rhs.distance
    }
    guard !ranked.isEmpty else { return .blocked }
    let nearest = ranked.prefix(2)
    let exact = nearest.first { $0.distance == 0 }
    if let exact { return exact.label }
    let weighted = nearest.reduce((numerator: 0.0, denominator: 0.0)) { result, item in
      let weight = 1 / max(0.000_001, item.distance)
      return (result.numerator + item.label.score * weight, result.denominator + weight)
    }
    return .from(score: weighted.numerator / weighted.denominator)
  }
}

public struct ArmatureClearPose: Codable, Hashable, Sendable {
  public let sourceObservationID: ArmaturePoseObservationID
  public let position: MachinePosition
  public let context: ArmatureGuidanceContext
  public let returnFeedMMPerMinute: Double
}

public struct ArmatureGuidanceProposal: Codable, Hashable, Sendable {
  public let move: ClearViewSearchMove
  public let request: RelativeJogRequest
}

public enum ArmatureGuidanceInvalidationReason: String, Codable, Hashable, Sendable {
  case controllerReconnect
  case controllerCoordinateReset
  case cameraConfigurationChanged
  case observationRegionChanged
  case toolOrPaperChanged
  case explicitlyDiscarded
}

public enum ArmatureGuidanceError: Error, Equatable, Sendable {
  case frameCameraConfigurationMismatch
  case invalidObservationRegion
  case observationNotFound
  case acceptedPoseMustBeClear
  case invalidReturnFeed
  case noAcceptedClearPose
  case automatedReturnInvalidated(ArmatureGuidanceInvalidationReason)
  case contextMismatch(ArmatureGuidanceInvalidationReason)
  case alreadyAtClearPose
  case invalidProposalFeed
}

public struct ArmatureGuidanceState: Codable, Hashable, Sendable {
  public private(set) var context: ArmatureGuidanceContext
  public private(set) var observations: [ArmaturePoseObservation]
  public private(set) var visibilityFit: ArmatureVisibilityFit?
  public private(set) var acceptedClearPose: ArmatureClearPose?
  public private(set) var automatedReturnInvalidation: ArmatureGuidanceInvalidationReason?
  public let availableSearchMoves: [ClearViewSearchMove]

  public init(
    context: ArmatureGuidanceContext,
    availableSearchMoves: [ClearViewSearchMove] = Self.standardSearchMoves
  ) {
    self.context = context
    self.availableSearchMoves = availableSearchMoves.isEmpty
      ? Self.standardSearchMoves
      : availableSearchMoves
    observations = []
    visibilityFit = nil
    acceptedClearPose = nil
    automatedReturnInvalidation = nil
  }

  /// This is intentionally invariant: losing a learned return pose must not
  /// become a hidden global motion gate.
  public var manualMotionPermitted: Bool { true }

  @discardableResult
  public mutating func record(
    id: ArmaturePoseObservationID = ArmaturePoseObservationID(),
    frame: StampedFrame,
    controllerPosition: MachinePosition,
    armatureBounds: AxisAlignedBounds<CameraPixelSpace>?,
    humanLabel: ArmatureVisibilityLabel,
    outcome: ArmatureGuidanceOutcome
  ) throws -> ArmaturePoseObservation {
    guard frame.cameraConfigurationID == context.cameraConfigurationID else {
      throw ArmatureGuidanceError.frameCameraConfigurationMismatch
    }
    let overlap = try Self.overlapEstimate(
      conservativeBounds: armatureBounds,
      region: context.observationRegion,
      frame: frame
    )
    let observation = ArmaturePoseObservation(
      id: id,
      frameID: frame.id,
      frameSHA256: frame.contentSHA256,
      captureNanoseconds: frame.captureNanoseconds,
      cameraConfigurationID: frame.cameraConfigurationID,
      controllerPosition: controllerPosition,
      observationRegion: context.observationRegion,
      overlapEstimate: overlap,
      humanLabel: humanLabel,
      estimateAgreedWithHuman: overlap.visibility == humanLabel,
      outcome: outcome
    )
    observations.removeAll { $0.id == id }
    observations.append(observation)
    rebuildVisibilityFit()
    return observation
  }

  public mutating func acceptClearPose(
    observationID: ArmaturePoseObservationID,
    returnFeedMMPerMinute: Double
  ) throws {
    guard returnFeedMMPerMinute.isFinite, returnFeedMMPerMinute > 0 else {
      throw ArmatureGuidanceError.invalidReturnFeed
    }
    guard let observation = observations.first(where: { $0.id == observationID }) else {
      throw ArmatureGuidanceError.observationNotFound
    }
    guard observation.humanLabel == .clear else {
      throw ArmatureGuidanceError.acceptedPoseMustBeClear
    }
    acceptedClearPose = ArmatureClearPose(
      sourceObservationID: observationID,
      position: observation.controllerPosition,
      context: context,
      returnFeedMMPerMinute: returnFeedMMPerMinute
    )
    automatedReturnInvalidation = nil
  }

  /// Produces one finite closed pen-up travel request. The controller still
  /// owns the live pen-state and motion checks when this request is executed.
  public func penUpReturnRequest(
    from currentPosition: MachinePosition,
    currentContext: ArmatureGuidanceContext
  ) throws -> RelativeJogRequest {
    if let reason = automatedReturnInvalidation {
      throw ArmatureGuidanceError.automatedReturnInvalidated(reason)
    }
    guard let acceptedClearPose else { throw ArmatureGuidanceError.noAcceptedClearPose }
    if let mismatch = Self.contextMismatch(expected: acceptedClearPose.context, actual: currentContext) {
      throw ArmatureGuidanceError.contextMismatch(mismatch)
    }
    let delta = try Vector2<MachineSpace>(
      dx: acceptedClearPose.position.point.x - currentPosition.point.x,
      dy: acceptedClearPose.position.point.y - currentPosition.point.y
    )
    guard delta.dx != 0 || delta.dy != 0 else { throw ArmatureGuidanceError.alreadyAtClearPose }
    return RelativeJogRequest(delta: delta, feedMMPerMinute: acceptedClearPose.returnFeedMMPerMinute)
  }

  public func proposedActions(
    from _: MachinePosition,
    feedMMPerMinute: Double
  ) throws -> [ArmatureGuidanceProposal] {
    guard feedMMPerMinute.isFinite, feedMMPerMinute > 0 else {
      throw ArmatureGuidanceError.invalidProposalFeed
    }
    let preferred = preferredMoveOrder()
    return preferred.map {
      ArmatureGuidanceProposal(
        move: $0,
        request: $0.request(feedMMPerMinute: feedMMPerMinute)
      )
    }
  }

  public mutating func updateContext(_ updated: ArmatureGuidanceContext) {
    if let reason = Self.contextMismatch(expected: context, actual: updated) {
      invalidateAutomatedReturn(reason)
      observations = []
      visibilityFit = nil
    }
    context = updated
  }

  public mutating func invalidateAutomatedReturn(_ reason: ArmatureGuidanceInvalidationReason) {
    acceptedClearPose = nil
    automatedReturnInvalidation = reason
  }

  private mutating func rebuildVisibilityFit() {
    var labelledPoses: [MachinePosition: ArmatureVisibilityLabel] = [:]
    for observation in observations {
      labelledPoses[observation.controllerPosition] = observation.humanLabel
    }
    visibilityFit = labelledPoses.count >= 2
      ? ArmatureVisibilityFit(distinctPoseCount: labelledPoses.count, labelledPoses: labelledPoses)
      : nil
  }

  private func preferredMoveOrder() -> [ClearViewSearchMove] {
    guard let latest = observations.last else { return availableSearchMoves }
    switch latest.outcome {
    case .continueInDirection(let move):
      return [move] + availableSearchMoves.filter { $0 != move }
    case .reverse:
      guard observations.count >= 2,
        case .continueInDirection(let previous) = observations[observations.count - 2].outcome,
        let reverse = Self.reverse(of: previous)
      else { return Array(availableSearchMoves.reversed()) }
      return [reverse] + availableSearchMoves.filter { $0 != reverse }
    case .stopped, .acceptedPose:
      return []
    }
  }

  private static func reverse(of move: ClearViewSearchMove) -> ClearViewSearchMove? {
    let direction: BoundaryDirection = switch move.direction {
    case .negativeX: .positiveX
    case .positiveX: .negativeX
    case .negativeY: .positiveY
    case .positiveY: .negativeY
    }
    return ClearViewSearchMove(direction: direction, distance: move.distance)
  }

  public static let standardSearchMoves: [ClearViewSearchMove] =
    ClearViewSearchDistance.allCases.flatMap { distance in
      BoundaryDirection.allCases.map { direction in
        ClearViewSearchMove(direction: direction, distance: distance)
      }
    }

  private static func contextMismatch(
    expected: ArmatureGuidanceContext,
    actual: ArmatureGuidanceContext
  ) -> ArmatureGuidanceInvalidationReason? {
    if expected.controllerSessionID != actual.controllerSessionID { return .controllerReconnect }
    if expected.coordinateRevision != actual.coordinateRevision { return .controllerCoordinateReset }
    if expected.cameraConfigurationID != actual.cameraConfigurationID {
      return .cameraConfigurationChanged
    }
    if expected.observationRegion != actual.observationRegion { return .observationRegionChanged }
    if expected.toolPaperRevision != actual.toolPaperRevision { return .toolOrPaperChanged }
    return nil
  }

  private static func overlapEstimate(
    conservativeBounds: AxisAlignedBounds<CameraPixelSpace>?,
    region: PixelRect,
    frame: StampedFrame
  ) throws -> ArmatureRegionOverlapEstimate {
    guard region.x >= 0, region.y >= 0, region.width > 0, region.height > 0,
      region.x + region.width <= frame.width,
      region.y + region.height <= frame.height
    else { throw ArmatureGuidanceError.invalidObservationRegion }
    guard let bounds = conservativeBounds else {
      return ArmatureRegionOverlapEstimate(
        fractionOfObservationRegion: 1,
        visibility: .blocked,
        conservativeBounds: nil
      )
    }
    let regionMinX = Double(region.x)
    let regionMinY = Double(region.y)
    let regionMaxX = Double(region.x + region.width)
    let regionMaxY = Double(region.y + region.height)
    let intersectionWidth = max(0, min(regionMaxX, bounds.maxX) - max(regionMinX, bounds.minX))
    let intersectionHeight = max(0, min(regionMaxY, bounds.maxY) - max(regionMinY, bounds.minY))
    let fraction = min(
      1,
      (intersectionWidth * intersectionHeight) / Double(region.width * region.height)
    )
    let visibility: ArmatureVisibilityLabel
    if fraction == 0 {
      visibility = .clear
    } else if fraction < 0.35 {
      visibility = .partial
    } else {
      visibility = .blocked
    }
    return ArmatureRegionOverlapEstimate(
      fractionOfObservationRegion: fraction,
      visibility: visibility,
      conservativeBounds: bounds
    )
  }
}
