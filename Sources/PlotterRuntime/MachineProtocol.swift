import Foundation
import PlotterModel

public protocol MachineLink: Sendable {
  var descriptor: MachineLinkDescriptor { get }
  func open() async throws
  func close() async
  func discardPendingInput() async throws
  func write(_ bytes: Data) async throws
  func read(maximumBytes: Int, timeoutNanoseconds: UInt64) async throws -> Data
}

public struct MachineLinkDescriptor: Codable, Hashable, Sendable {
  public let identifier: String
  public let displayName: String
  public let bsdPath: String?
  public let transport: Transport

  public enum Transport: String, Codable, Hashable, Sendable {
    case bsdSerial
    case simulated
  }

  public init(identifier: String, displayName: String, bsdPath: String?, transport: Transport) {
    self.identifier = identifier
    self.displayName = displayName
    self.bsdPath = bsdPath
    self.transport = transport
  }
}

public enum MachineLinkError: Error, Equatable, Sendable {
  case notOpen
  case alreadyOpen
  case timedOut
  case writeTimedOut(bytesWritten: Int, totalBytes: Int)
  case writeCancelled(bytesWritten: Int, totalBytes: Int)
  case readExceededMaximum(expected: Int, actual: Int)
  case disconnected
  case unexpectedWrite(expected: Data, actual: Data)
  case invalidPath(String)
  case operatingSystem(code: Int32, operation: String)
}

public struct RelativeJogRequest: Codable, Hashable, Sendable {
  public let delta: Vector2<MachineSpace>
  public let feedMMPerMinute: Double

  public init(delta: Vector2<MachineSpace>, feedMMPerMinute: Double) {
    self.delta = delta
    self.feedMMPerMinute = feedMMPerMinute
  }
}

public struct ControllerAxisFeedLimits: Codable, Hashable, Sendable {
  public let maximumXFeedMMPerMinute: Double
  public let maximumYFeedMMPerMinute: Double

  public init(maximumXFeedMMPerMinute: Double, maximumYFeedMMPerMinute: Double) {
    precondition(maximumXFeedMMPerMinute.isFinite && maximumXFeedMMPerMinute > 0)
    precondition(maximumYFeedMMPerMinute.isFinite && maximumYFeedMMPerMinute > 0)
    self.maximumXFeedMMPerMinute = maximumXFeedMMPerMinute
    self.maximumYFeedMMPerMinute = maximumYFeedMMPerMinute
  }

  /// Returns the conservative controller-reported ceiling for the axes that
  /// participate in this typed path. This selects a request feed; it is not a
  /// claim about achieved physical velocity.
  public func applicableFeedCeiling(for delta: Vector2<MachineSpace>) -> Double? {
    var limits: [Double] = []
    if delta.dx != 0 { limits.append(maximumXFeedMMPerMinute) }
    if delta.dy != 0 { limits.append(maximumYFeedMMPerMinute) }
    return limits.min()
  }
}

public enum FeedSelectionSource: String, Codable, Hashable, Sendable {
  case controllerReportedCeiling
  case existingFallback
}

public struct TravelFeedSelection: Codable, Hashable, Sendable {
  public let requestedFeedMMPerMinute: Double
  public let source: FeedSelectionSource

  public init(requestedFeedMMPerMinute: Double, source: FeedSelectionSource) {
    precondition(requestedFeedMMPerMinute.isFinite && requestedFeedMMPerMinute > 0)
    self.requestedFeedMMPerMinute = requestedFeedMMPerMinute
    self.source = source
  }
}

/// One closed finite XY move whose admission requires the controller-commanded
/// pen state to be Down. Ordinary carriage travel continues to use
/// `RelativeJogRequest` and continues to require Pen Up.
public struct DrawingStrokeRequest: Codable, Hashable, Sendable {
  public let delta: Vector2<MachineSpace>
  public let feedMMPerMinute: Double

  public init(delta: Vector2<MachineSpace>, feedMMPerMinute: Double) {
    self.delta = delta
    self.feedMMPerMinute = feedMMPerMinute
  }
}

public enum VisibilityTargetStartConvention: String, Codable, Hashable, Sendable {
  case positiveXPerimeter
}

public enum VisibilityTargetTraversalDirection: String, Codable, Hashable, Sendable {
  case forward
  case reverse
}

/// One controller-settled edge traversal within the revisioned visibility
/// target. `segmentIndex` identifies the geometric octagon edge while
/// `traversalIndex` identifies its position in the complete two-pass sequence.
public struct VisibilityTargetTraversalStep: Codable, Hashable, Sendable {
  public let passIndex: Int
  public let direction: VisibilityTargetTraversalDirection
  public let segmentIndex: Int
  public let traversalIndex: Int
  public let delta: Vector2<MachineSpace>

  public init(
    passIndex: Int,
    direction: VisibilityTargetTraversalDirection,
    segmentIndex: Int,
    traversalIndex: Int,
    delta: Vector2<MachineSpace>
  ) {
    precondition(passIndex >= 0)
    precondition(segmentIndex >= 0)
    precondition(traversalIndex >= 0)
    self.passIndex = passIndex
    self.direction = direction
    self.segmentIndex = segmentIndex
    self.traversalIndex = traversalIndex
    self.delta = delta
  }
}

public struct VisibilityTargetTraversalRequest: Codable, Hashable, Sendable {
  public let step: VisibilityTargetTraversalStep
  public let drawingRequest: DrawingStrokeRequest

  public init(step: VisibilityTargetTraversalStep, drawingRequest: DrawingStrokeRequest) {
    self.step = step
    self.drawingRequest = drawingRequest
  }
}

/// The frozen double-trace visibility target: one closed regular 4 mm octagon
/// traversed once forward and then immediately over the same edges in reverse.
/// Both passes share one Pen Down interval and one logical operation owner.
/// Geometry is target-center-relative and does not define a workspace envelope.
public struct VisibilityTargetPlanV2: Codable, Hashable, Sendable {
  public static let revision = "visibility-target-octagon-double-trace-v2"

  public let diameterMM: Double
  public let radiusMM: Double
  public let perimeterSegmentCount: Int
  public let passCount: Int
  public let startConvention: VisibilityTargetStartConvention
  public let relativeVertices: [Point2<MachineSpace>]
  public let approachDelta: Vector2<MachineSpace>
  public let traversalSteps: [VisibilityTargetTraversalStep]
  public let algorithmRevision: String

  public var drawingStepCount: Int { traversalSteps.count }

  public init() {
    diameterMM = 4
    radiusMM = 2
    perimeterSegmentCount = 8
    passCount = 2
    startConvention = .positiveXPerimeter
    let vertices = (0..<8).map { index in
      let angle = Double(index) * .pi / 4
      return try! Point2<MachineSpace>(x: 2 * cos(angle), y: 2 * sin(angle))
    }
    relativeVertices = vertices
    approachDelta = try! Vector2<MachineSpace>(dx: 2, dy: 0)
    let forwardDeltas = (0..<8).map { index in
      try! vertices[index].vector(to: vertices[(index + 1) % vertices.count])
    }
    let forward = forwardDeltas.enumerated().map { index, delta in
      VisibilityTargetTraversalStep(
        passIndex: 0,
        direction: .forward,
        segmentIndex: index,
        traversalIndex: index,
        delta: delta
      )
    }
    let reverse = forwardDeltas.indices.reversed().enumerated().map { offset, segmentIndex in
      let forwardDelta = forwardDeltas[segmentIndex]
      return VisibilityTargetTraversalStep(
        passIndex: 1,
        direction: .reverse,
        segmentIndex: segmentIndex,
        traversalIndex: forward.count + offset,
        delta: try! Vector2(dx: -forwardDelta.dx, dy: -forwardDelta.dy)
      )
    }
    traversalSteps = forward + reverse
    algorithmRevision = Self.revision
  }

  public func approachRequest(feedMMPerMinute: Double) -> RelativeJogRequest {
    RelativeJogRequest(delta: approachDelta, feedMMPerMinute: feedMMPerMinute)
  }

  public func traversalRequests(
    feedMMPerMinute: Double
  ) -> [VisibilityTargetTraversalRequest] {
    traversalSteps.map {
      VisibilityTargetTraversalRequest(
        step: $0,
        drawingRequest: DrawingStrokeRequest(
          delta: $0.delta,
          feedMMPerMinute: feedMMPerMinute
        )
      )
    }
  }
}

public enum VisibilityTargetSceneDisposition: String, Codable, Hashable, Sendable {
  case pristine
  case inkPossible
  case targetObserved
  case targetUnusable
}

public struct VisibilityTargetOperationRequest: Codable, Hashable, Sendable {
  public let id: UUID
  public let plan: VisibilityTargetPlanV2
  public let approachFeedMMPerMinute: Double
  public let drawingFeedMMPerMinute: Double

  public init(
    id: UUID = UUID(),
    plan: VisibilityTargetPlanV2 = VisibilityTargetPlanV2(),
    approachFeedMMPerMinute: Double,
    drawingFeedMMPerMinute: Double
  ) {
    self.id = id
    self.plan = plan
    self.approachFeedMMPerMinute = approachFeedMMPerMinute
    self.drawingFeedMMPerMinute = drawingFeedMMPerMinute
  }
}

public enum VisibilityTargetOperationPhase: Codable, Hashable, Sendable {
  case approach
  case lowerPen
  case draw(VisibilityTargetTraversalStep)
  case raisePen
}

/// Controller-side progress only. It records what the operation admitted and
/// settled; it is never a claim that ink was visibly present.
public struct VisibilityTargetOperationProgress: Codable, Hashable, Sendable {
  public let planRevision: String
  public let phase: VisibilityTargetOperationPhase
  public let dispositionRequestedDuringPhase: VisibilityTargetOperationPhase?
  public let completedTraversalStepCount: Int
  public let lastCompletedTraversalStep: VisibilityTargetTraversalStep?

  public init(
    planRevision: String,
    phase: VisibilityTargetOperationPhase,
    dispositionRequestedDuringPhase: VisibilityTargetOperationPhase? = nil,
    completedTraversalStepCount: Int,
    lastCompletedTraversalStep: VisibilityTargetTraversalStep?
  ) {
    precondition(!planRevision.isEmpty)
    precondition(completedTraversalStepCount >= 0)
    self.planRevision = planRevision
    self.phase = phase
    self.dispositionRequestedDuringPhase = dispositionRequestedDuringPhase
    self.completedTraversalStepCount = completedTraversalStepCount
    self.lastCompletedTraversalStep = lastCompletedTraversalStep
  }
}

public enum VisibilityTargetOperationIntent: String, Codable, Hashable, Sendable {
  case stop
  case cancel
  case shutdown
}

public enum VisibilityTargetOperationFailure: Codable, Hashable, Sendable {
  case approach(MotionOutcome)
  case pen(PenOutcome)
  case drawing(step: VisibilityTargetTraversalStep, outcome: DrawingStrokeOutcome)
  case stoppedWithoutSettlement
}

public enum VisibilityTargetOperationOutcome: Codable, Hashable, Sendable {
  case completed(
    finalPosition: MachinePosition,
    scene: VisibilityTargetSceneDisposition,
    progress: VisibilityTargetOperationProgress
  )
  case stopped(
    scene: VisibilityTargetSceneDisposition,
    jogCancelOutcome: JogCancelOutcome?,
    progress: VisibilityTargetOperationProgress
  )
  case cancelled(
    scene: VisibilityTargetSceneDisposition,
    jogCancelOutcome: JogCancelOutcome?,
    progress: VisibilityTargetOperationProgress
  )
  case shutdown(
    scene: VisibilityTargetSceneDisposition,
    jogCancelOutcome: JogCancelOutcome?,
    progress: VisibilityTargetOperationProgress
  )
  case needsAttention(
    phase: VisibilityTargetOperationPhase,
    scene: VisibilityTargetSceneDisposition,
    failure: VisibilityTargetOperationFailure,
    progress: VisibilityTargetOperationProgress
  )
}

/// Explicit operator authorization for machine-affecting commands in the
/// current controller session. It is cleared by disconnects and controller
/// faults; it is never inferred from a successful probe.
public enum MotionGuardState: String, Codable, Hashable, Sendable {
  case inactive
  case active
}

public struct MachinePosition: Codable, Hashable, Sendable {
  public let point: Point2<MachineSpace>

  public init(point: Point2<MachineSpace>) {
    self.point = point
  }

  public init(x: Double, y: Double) throws {
    point = try Point2(x: x, y: y)
  }
}

public enum PenState: String, Codable, Hashable, Sendable {
  case unknown
  case up
  case down
}

/// The only pen actions that the native runtime can put on the controller wire.
/// This is intentionally not a raw G-code escape hatch.
public enum PenCommand: String, Codable, Hashable, Sendable {
  case raise
  case lower

  public var commandedState: PenState {
    switch self {
    case .raise: .up
    case .lower: .down
    }
  }
}

/// Fixed local encoding recovered from the plotter's proven pen mechanism.
/// The values are not operator-editable controller settings.
public struct PenActuationProfile: Hashable, Sendable {
  public static let localPlotter = PenActuationProfile(
    raisedSpindleValue: 40,
    loweredSpindleValue: 760,
    settleSeconds: 0.3
  )

  public let raisedSpindleValue: Int
  public let loweredSpindleValue: Int
  public let settleSeconds: Double

  private init(
    raisedSpindleValue: Int,
    loweredSpindleValue: Int,
    settleSeconds: Double
  ) {
    self.raisedSpindleValue = raisedSpindleValue
    self.loweredSpindleValue = loweredSpindleValue
    self.settleSeconds = settleSeconds
  }

  public func actuationBytes(for command: PenCommand) -> Data {
    let value = command == .raise ? raisedSpindleValue : loweredSpindleValue
    return Data("M3 S\(value)\n".utf8)
  }

  public var settleBytes: Data {
    let seconds = String(
      format: "%.1f",
      locale: Locale(identifier: "en_US_POSIX"),
      settleSeconds
    )
    return Data("G4 P\(seconds)\n".utf8)
  }
}

public enum PenRefusal: Codable, Hashable, Sendable {
  case noSerialDeviceSelected
  case notConnected
  case motionGuardInactive
  case controllerStateUnknown
  case controllerNotIdle(ControllerState)
  case controllerAlarm(String)
  case relevantLimitAsserted(String)
  case machinePositionUnknown
  case operationInFlight
  case stickyAmbiguity(MotionAmbiguity)
  case controllerRejected(String)
  case freshStatusUnavailable(String)
}

/// `commandedAndSettled` is controller evidence only: both the actuation and
/// fixed dwell were acknowledged. It is not camera evidence of the physical pen.
public enum PenOutcome: Codable, Hashable, Sendable {
  case refused(PenRefusal)
  case commandedAndSettled(command: PenCommand, commandedState: PenState)
  case ambiguous(MotionAmbiguity)
}

extension PenRefusal {
  public var actionableDescription: String {
    switch self {
    case .noSerialDeviceSelected:
      return "Select one serial controller before actuating the pen."
    case .notConnected:
      return "Connect and run the passive controller probe before actuating the pen."
    case .motionGuardInactive:
      return "Enable Motion before actuating the pen."
    case .controllerStateUnknown:
      return "Query the controller until its current state is known."
    case .controllerNotIdle(let state):
      return "Wait for controller Idle; current state is \(state.rawValue)."
    case .controllerAlarm(let detail):
      return "Controller alarm: \(detail). Clear it physically, then reconnect and probe."
    case .relevantLimitAsserted(let pins):
      return "A motion limit is asserted (Pn:\(pins)); inspect the machine before lowering the pen."
    case .machinePositionUnknown:
      return "Probe the controller until a valid MPos is available before lowering the pen."
    case .operationInFlight:
      return "Wait for the current controller operation to finish."
    case .stickyAmbiguity(let ambiguity):
      return "Pen control is disabled after an ambiguous physical command: \(ambiguity.actionableDescription)"
    case .controllerRejected(let detail):
      return "Controller rejected the pen command (\(detail)); inspect the controller state before retrying."
    case .freshStatusUnavailable(let detail):
      return "Fresh pre-command controller status was unavailable (\(detail)); reconnect and probe before retrying."
    }
  }
}

public enum ControllerState: String, Codable, Hashable, Sendable {
  case idle
  case run
  case hold
  case jog
  case alarm
  case door
  case check
  case home
  case sleep
  case tool
  case unknown

  public init(statusText: String) {
    let base = statusText.split(separator: ":", maxSplits: 1).first?.lowercased() ?? ""
    self = Self(rawValue: base) ?? .unknown
  }

  public var isRecognized: Bool { self != .unknown }
  public var isAlarm: Bool { self == .alarm }
}

public struct ControllerPins: Codable, Hashable, Sendable {
  public let rawValue: String

  public init(rawValue: String) {
    self.rawValue = rawValue
  }

  public var xLimitAsserted: Bool { rawValue.uppercased().contains("X") }
  public var yLimitAsserted: Bool { rawValue.uppercased().contains("Y") }
  public var hasRelevantLimitAsserted: Bool { xLimitAsserted || yLimitAsserted }
}

public enum MotionRefusal: Codable, Hashable, Sendable {
  case noSerialDeviceSelected
  case notConnected
  case motionGuardInactive
  case controllerStateUnknown
  case controllerNotIdle(ControllerState)
  case controllerAlarm(String)
  case relevantLimitAsserted(String)
  case machinePositionUnknown
  case nonFiniteDelta
  case zeroDelta
  case nonPositiveFeed(Double)
  case feedExceedsMaximum(requested: Double, maximum: Double)
  case penNotUp(PenState)
  case operationInFlight
  case stickyAmbiguity(MotionAmbiguity)
  case controllerRejected(String)
  case freshStatusUnavailable(String)
}

public enum MotionGuardActivationOutcome: Codable, Hashable, Sendable {
  case activated
  case refused(MotionRefusal)
}

public enum MotionAmbiguity: Codable, Hashable, Sendable {
  case partialWrite(bytesWritten: Int, totalBytes: Int)
  case writeTimedOut(bytesWritten: Int, totalBytes: Int)
  case writeCancelled(bytesWritten: Int, totalBytes: Int)
  case acceptanceTimedOut
  case completionTimedOut(deadlineNanoseconds: UInt64)
  case disconnected
  case malformedReply(String)
  case controllerAlarm(String)
  case controllerHold
  case unexpectedControllerState(ControllerState)
  case settleCommandRejected(String)
  case transport(String)
}

public enum MotionOutcome: Codable, Hashable, Sendable {
  case refused(MotionRefusal)
  case acceptedThenCompleted(finalPosition: MachinePosition)
  /// The controller accepted the `$J` request, then a closed GRBL realtime
  /// jog-cancel byte was transmitted and Idle was observed at this position.
  /// The requested destination must not be inferred from this outcome.
  case cancelled(finalPosition: MachinePosition)
  case ambiguous(MotionAmbiguity)
}

/// Pre-write reasons a closed drawing stroke can be refused. This is distinct
/// from `MotionRefusal` so the Pen Down requirement cannot weaken or be confused
/// with ordinary Pen Up carriage travel.
public enum DrawingStrokeRefusal: Codable, Hashable, Sendable {
  case noSerialDeviceSelected
  case notConnected
  case motionGuardInactive
  case controllerStateUnknown
  case controllerNotIdle(ControllerState)
  case controllerAlarm(String)
  case relevantLimitAsserted(String)
  case machinePositionUnknown
  case nonFiniteDelta
  case zeroDelta
  case nonPositiveFeed(Double)
  case controllerFeedCapabilityUnknown
  case feedExceedsMaximum(requested: Double, maximum: Double)
  case penNotDown(PenState)
  case operationInFlight
  case stickyAmbiguity(MotionAmbiguity)
  case controllerRejected(String)
  case freshStatusUnavailable(String)
}

/// Exact controller-owned position samples for one accepted drawing stroke.
/// The evidence makes no claim about visible ink or physical pen contact.
public struct DrawingStrokeEvidence: Codable, Hashable, Sendable {
  public let request: DrawingStrokeRequest
  public let startPosition: MachinePosition
  public let startSampleNanoseconds: UInt64
  public let finalPosition: MachinePosition
  public let finalSampleNanoseconds: UInt64

  init(
    request: DrawingStrokeRequest,
    startPosition: MachinePosition,
    startSampleNanoseconds: UInt64,
    finalPosition: MachinePosition,
    finalSampleNanoseconds: UInt64
  ) {
    self.request = request
    self.startPosition = startPosition
    self.startSampleNanoseconds = startSampleNanoseconds
    self.finalPosition = finalPosition
    self.finalSampleNanoseconds = finalSampleNanoseconds
  }
}

/// A completed stroke remains Pen Down so its caller can perform the explicit
/// raise that belongs to the drawing episode. A clean cancellation performs one
/// fixed typed Pen Up attempt while retaining the stroke owner, and reports that
/// exact result. Any uncertain post-write result is top-level `ambiguous`.
public enum DrawingStrokeOutcome: Codable, Hashable, Sendable {
  case refused(DrawingStrokeRefusal)
  case completed(evidence: DrawingStrokeEvidence)
  case cancelled(evidence: DrawingStrokeEvidence, penRaiseOutcome: PenOutcome)
  case ambiguous(MotionAmbiguity)
}

/// Reasons the closed GRBL realtime jog-cancel surface can refuse without
/// putting bytes on the wire.
public enum JogCancelRefusal: Codable, Hashable, Sendable {
  case noSerialDeviceSelected
  case notConnected
  case noActiveJog
  case alreadyRequested
  case stickyAmbiguity(MotionAmbiguity)
}

/// A GRBL realtime jog-cancel byte has no ordinary `ok` acknowledgement.
/// `transmitted` therefore means exactly one `0x85` byte was written; only a
/// later typed Idle status promotes it to `completed`.
public enum JogCancelOutcome: Codable, Hashable, Sendable {
  case refused(JogCancelRefusal)
  case transmitted
  case completed(finalPosition: MachinePosition)
  case ambiguous(MotionAmbiguity)
}

extension JogCancelRefusal {
  public var actionableDescription: String {
    switch self {
    case .noSerialDeviceSelected:
      return "Select one serial controller before requesting Jog Cancel."
    case .notConnected:
      return "Connect to the selected controller before requesting Jog Cancel."
    case .noActiveJog:
      return "Jog Cancel is available only while a transmitted $J jog is active."
    case .alreadyRequested:
      return "A Jog Cancel byte has already been requested for the current jog."
    case .stickyAmbiguity(let ambiguity):
      return "Jog Cancel is unavailable after an ambiguous physical command: \(ambiguity.actionableDescription)"
    }
  }
}

extension MotionRefusal {
  public var actionableDescription: String {
    switch self {
    case .noSerialDeviceSelected:
      return "Select one serial controller before moving."
    case .notConnected:
      return "Connect and run the passive controller probe before moving."
    case .motionGuardInactive:
      return "Enable Motion before moving."
    case .controllerStateUnknown:
      return "Query the controller until its current state is known."
    case .controllerNotIdle(let state):
      return "Wait for controller Idle; current state is \(state.rawValue)."
    case .controllerAlarm(let detail):
      return "Controller alarm: \(detail). Clear it physically, then reconnect and probe."
    case .relevantLimitAsserted(let pins):
      return "A motion limit is asserted (Pn:\(pins)); inspect the machine before retrying."
    case .machinePositionUnknown:
      return "Probe the controller until a valid MPos is available."
    case .nonFiniteDelta:
      return "Enter finite X and Y move values."
    case .zeroDelta:
      return "Enter a nonzero X or Y move."
    case .nonPositiveFeed(let feed):
      return "Feed must be positive and finite; received \(feed)."
    case .feedExceedsMaximum(let requested, let maximum):
      return "Feed \(requested) mm/min exceeds the controller-reported axis limit \(maximum)."
    case .penNotUp:
      return "Issue a successful Pen Up command before moving."
    case .operationInFlight:
      return "Wait for the current controller operation to finish."
    case .stickyAmbiguity(let ambiguity):
      return "Motion is disabled after an ambiguous command: \(ambiguity.actionableDescription)"
    case .controllerRejected(let detail):
      return "Controller rejected the jog (\(detail)); correct the request and retry."
    case .freshStatusUnavailable(let detail):
      return "Fresh pre-move controller status was unavailable (\(detail)); reconnect and probe before retrying."
    }
  }
}

extension DrawingStrokeRefusal {
  public var actionableDescription: String {
    switch self {
    case .noSerialDeviceSelected:
      return "Select one serial controller before drawing."
    case .notConnected:
      return "Connect and run the passive controller probe before drawing."
    case .motionGuardInactive:
      return "Enable Motion before drawing."
    case .controllerStateUnknown:
      return "Query the controller until its current state is known."
    case .controllerNotIdle(let state):
      return "Wait for controller Idle; current state is \(state.rawValue)."
    case .controllerAlarm(let detail):
      return "Controller alarm: \(detail). Clear it physically, then reconnect and probe."
    case .relevantLimitAsserted(let pins):
      return "A motion limit is asserted (Pn:\(pins)); inspect the machine before drawing."
    case .machinePositionUnknown:
      return "Probe the controller until a valid MPos is available before drawing."
    case .nonFiniteDelta:
      return "The drawing stroke requires finite X and Y deltas."
    case .zeroDelta:
      return "The drawing stroke requires one nonzero machine delta."
    case .nonPositiveFeed(let feed):
      return "Drawing feed must be positive and finite; received \(feed)."
    case .controllerFeedCapabilityUnknown:
      return "Probe the controller until its X/Y feed capabilities are known before drawing."
    case .feedExceedsMaximum(let requested, let maximum):
      return "Drawing feed \(requested) mm/min exceeds the controller-reported axis limit \(maximum)."
    case .penNotDown:
      return "Issue a successful Pen Down command before drawing."
    case .operationInFlight:
      return "Wait for the current controller operation to finish."
    case .stickyAmbiguity(let ambiguity):
      return "Drawing is disabled after an ambiguous command: \(ambiguity.actionableDescription)"
    case .controllerRejected(let detail):
      return "Controller rejected the drawing stroke (\(detail)); inspect the controller state before retrying."
    case .freshStatusUnavailable(let detail):
      return "Fresh pre-stroke controller status was unavailable (\(detail)); reconnect and probe before retrying."
    }
  }
}

extension MotionAmbiguity {
  public var actionableDescription: String {
    switch self {
    case .partialWrite(let written, let total):
      return "Only \(written) of \(total) command bytes were written; inspect and reconnect."
    case .writeTimedOut(let written, let total):
      return "The write timed out after \(written) of \(total) bytes; inspect and reconnect."
    case .writeCancelled(let written, let total):
      return "The write was cancelled after \(written) of \(total) bytes; inspect and reconnect."
    case .acceptanceTimedOut:
      return "No bounded controller acknowledgement arrived; inspect and reconnect."
    case .completionTimedOut:
      return "The accepted jog did not reach a known Idle state before its deadline; inspect and reconnect."
    case .disconnected:
      return "The controller disconnected during a physical command; inspect and reconnect."
    case .malformedReply(let detail):
      return "The controller reply was not trustworthy (\(detail)); inspect and reconnect."
    case .controllerAlarm(let detail):
      return "The controller alarmed after transmission (\(detail)); inspect and reconnect."
    case .controllerHold:
      return "The controller entered Hold after accepting the jog; inspect before reconnecting."
    case .unexpectedControllerState(let state):
      return "The controller entered unexpected state \(state.rawValue); inspect and reconnect."
    case .settleCommandRejected(let detail):
      return "The pen actuation was accepted but its settle command was rejected (\(detail)); inspect and reconnect."
    case .transport(let detail):
      return "The transport failed after a physical command may have started (\(detail)); inspect and reconnect."
    }
  }
}

public struct MotionDiagnosticRecord: Codable, Hashable, Sendable {
  public let request: RelativeJogRequest
  public let outcome: MotionOutcome
  public let timestamp: RuntimeTimestamp

  public init(
    request: RelativeJogRequest,
    outcome: MotionOutcome,
    timestamp: RuntimeTimestamp
  ) {
    self.request = request
    self.outcome = outcome
    self.timestamp = timestamp
  }
}

public struct DrawingStrokeDiagnosticRecord: Codable, Hashable, Sendable {
  public let request: DrawingStrokeRequest
  public let outcome: DrawingStrokeOutcome
  public let timestamp: RuntimeTimestamp

  public init(
    request: DrawingStrokeRequest,
    outcome: DrawingStrokeOutcome,
    timestamp: RuntimeTimestamp
  ) {
    self.request = request
    self.outcome = outcome
    self.timestamp = timestamp
  }
}

public struct PenDiagnosticRecord: Codable, Hashable, Sendable {
  public let command: PenCommand
  public let outcome: PenOutcome
  public let timestamp: RuntimeTimestamp

  public init(command: PenCommand, outcome: PenOutcome, timestamp: RuntimeTimestamp) {
    self.command = command
    self.outcome = outcome
    self.timestamp = timestamp
  }
}

public enum PassiveQuery: String, Codable, CaseIterable, Hashable, Sendable {
  case buildInfo
  case parserState
  case status
  case configuration
  case coordinateOffsets

  public var wireBytes: Data {
    switch self {
    case .buildInfo: Data("$I\n".utf8)
    case .parserState: Data("$G\n".utf8)
    case .status: Data("?".utf8)
    case .configuration: Data("$$\n".utf8)
    case .coordinateOffsets: Data("$#\n".utf8)
    }
  }

  var terminatesOnStatus: Bool { self == .status }
}

public enum MachineIODirection: String, Codable, Hashable, Sendable {
  case transmit
  case receive
}

public struct RawMachineIO: Codable, Hashable, Sendable {
  public let direction: MachineIODirection
  public let bytes: Data
  public let timestamp: RuntimeTimestamp

  public init(direction: MachineIODirection, bytes: Data, timestamp: RuntimeTimestamp) {
    self.direction = direction
    self.bytes = bytes
    self.timestamp = timestamp
  }
}

public struct PassiveProbeExchange: Codable, Hashable, Sendable {
  public let query: PassiveQuery
  public let commandID: UUID
  public let rawIO: [RawMachineIO]
  public let lines: [ParsedControllerLine]
  public let completed: Bool
  public let blocker: MachineBlocker?

  public init(
    query: PassiveQuery,
    commandID: UUID,
    rawIO: [RawMachineIO],
    lines: [ParsedControllerLine],
    completed: Bool,
    blocker: MachineBlocker?
  ) {
    self.query = query
    self.commandID = commandID
    self.rawIO = rawIO
    self.lines = lines
    self.completed = completed
    self.blocker = blocker
  }
}

public enum MachineBlocker: Codable, Hashable, Sendable {
  case noSerialDevice
  case multipleSerialDevices([MachineLinkDescriptor])
  case transport(String)
  case timeout(PassiveQuery)
  case invalidReply(PassiveQuery, reason: String)
  case responseLimitExceeded(PassiveQuery, maximumBytes: Int, maximumChunks: Int)
  case controllerAlarm(String)
  case controllerError(String)
}

public struct ParsedControllerRecord: Codable, Hashable, Sendable {
  public let text: String
  public let kind: ControllerLineKind

  public init(text: String, kind: ControllerLineKind) {
    self.text = text
    self.kind = kind
  }
}

public struct PassiveProbeExchangeRecord: Codable, Hashable, Sendable {
  public let query: PassiveQuery
  public let commandID: UUID
  public let parsedLines: [ParsedControllerRecord]
  public let completed: Bool
  public let blocker: MachineBlocker?

  public init(exchange: PassiveProbeExchange) {
    query = exchange.query
    commandID = exchange.commandID
    parsedLines = exchange.lines.map { ParsedControllerRecord(text: $0.text, kind: $0.kind) }
    completed = exchange.completed
    blocker = exchange.blocker
  }
}

public struct PassiveProbeStartedRecord: Codable, Hashable, Sendable {
  public let probeID: UUID
  public let link: MachineLinkDescriptor
  public let startedAt: RuntimeTimestamp
  public let queries: [PassiveQuery]

  public init(
    probeID: UUID,
    link: MachineLinkDescriptor,
    startedAt: RuntimeTimestamp,
    queries: [PassiveQuery]
  ) {
    self.probeID = probeID
    self.link = link
    self.startedAt = startedAt
    self.queries = queries
  }
}

public struct PassiveProbeFinishedRecord: Codable, Hashable, Sendable {
  public let probeID: UUID
  public let link: MachineLinkDescriptor
  public let startedAt: RuntimeTimestamp
  public let completedAt: RuntimeTimestamp
  public let exchanges: [PassiveProbeExchangeRecord]
  public let blockers: [MachineBlocker]

  public init(result: PassiveProbeResult) {
    probeID = result.probeID
    link = result.link
    startedAt = result.startedAt
    completedAt = result.completedAt
    exchanges = result.exchanges.map(PassiveProbeExchangeRecord.init)
    blockers = result.blockers
  }
}

public struct PassiveProbeResult: Codable, Hashable, Sendable {
  public let probeID: UUID
  public let link: MachineLinkDescriptor
  public let startedAt: RuntimeTimestamp
  public let completedAt: RuntimeTimestamp
  public let exchanges: [PassiveProbeExchange]
  public let blockers: [MachineBlocker]

  public init(
    probeID: UUID = UUID(),
    link: MachineLinkDescriptor,
    startedAt: RuntimeTimestamp,
    completedAt: RuntimeTimestamp,
    exchanges: [PassiveProbeExchange],
    blockers: [MachineBlocker]
  ) {
    self.probeID = probeID
    self.link = link
    self.startedAt = startedAt
    self.completedAt = completedAt
    self.exchanges = exchanges
    self.blockers = blockers
  }
}
