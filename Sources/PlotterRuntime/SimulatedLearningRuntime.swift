import Foundation
import PlotterModel

/// Provenance carried by every simulator response. Simulator state and outcomes
/// are deliberately not controller, camera, motion, or ink evidence.
public struct SimulatedLearningEvidenceNotice: Hashable, Sendable {
  public static let evidenceLabel = "SIMULATED — NOT PHYSICAL EVIDENCE"
  public static let notPhysicalEvidence = SimulatedLearningEvidenceNotice()

  public let label: String

  private init() {
    label = Self.evidenceLabel
  }
}

public enum SimulatedLearningSessionState: String, Codable, Hashable, Sendable {
  case disconnected
  case connected
}

public enum SimulatedLearningMotionAuthorization: String, Codable, Hashable, Sendable {
  case disabled
  case enabled
}

public enum SimulatedLearningPenPose: String, Codable, Hashable, Sendable {
  case unknown
  case up
  case down
}

public enum SimulatedLearningValueError: Error, Hashable, Sendable {
  case nonFinitePosition
  case nonFiniteMotion
}

public struct SimulatedLearningBoundaryTruth: Codable, Hashable, Sendable {
  public let negativeXMM: Double
  public let positiveXMM: Double
  public let negativeYMM: Double
  public let positiveYMM: Double

  public init(
    negativeXMM: Double = -40,
    positiveXMM: Double = 40,
    negativeYMM: Double = -30,
    positiveYMM: Double = 30
  ) {
    precondition(negativeXMM.isFinite && positiveXMM.isFinite)
    precondition(negativeYMM.isFinite && positiveYMM.isFinite)
    precondition(negativeXMM < positiveXMM && negativeYMM < positiveYMM)
    self.negativeXMM = negativeXMM
    self.positiveXMM = positiveXMM
    self.negativeYMM = negativeYMM
    self.positiveYMM = positiveYMM
  }

  public func limit(for direction: BoundaryDirection) -> Double {
    switch direction {
    case .negativeX: negativeXMM
    case .positiveX: positiveXMM
    case .negativeY: negativeYMM
    case .positiveY: positiveYMM
    }
  }
}

public struct SimulatedLearningInkSegment: Codable, Hashable, Sendable {
  public let start: SimulatedLearningMPos
  public let end: SimulatedLearningMPos

  public init(start: SimulatedLearningMPos, end: SimulatedLearningMPos) {
    self.start = start
    self.end = end
  }
}

public enum SimulatedLearningFault: Codable, Hashable, Sendable {
  case refuseNextOperation
  case ambiguityAtVisibilityTargetPhase(VisibilityTargetOperationPhase)
  case partialVisibilityTarget(segmentCount: Int)
  case cameraConfigurationChangeBeforeNextFrame
  case poseMismatchBeforeNextFrame(dxMM: Double, dyMM: Double)
  case absentInk
  case unstableTarget
  case excessiveBackgroundResidual
  case shutdownDuringOperation
}

public struct SimulatedLearningSceneFrame: Hashable, Sendable {
  public let displayedFrame: DisplayedFrame
  public let controllerPosition: SimulatedLearningMPos
  public let contactPoint: Point2<CameraPixelSpace>
  public let armatureBounds: AxisAlignedBounds<CameraPixelSpace>
  public let inkSegmentCount: Int
  public let toolPaperRevision: UUID
  public let evidenceNotice: SimulatedLearningEvidenceNotice

  fileprivate init(
    displayedFrame: DisplayedFrame,
    controllerPosition: SimulatedLearningMPos,
    contactPoint: Point2<CameraPixelSpace>,
    armatureBounds: AxisAlignedBounds<CameraPixelSpace>,
    inkSegmentCount: Int,
    toolPaperRevision: UUID
  ) {
    self.displayedFrame = displayedFrame
    self.controllerPosition = controllerPosition
    self.contactPoint = contactPoint
    self.armatureBounds = armatureBounds
    self.inkSegmentCount = inkSegmentCount
    self.toolPaperRevision = toolPaperRevision
    evidenceNotice = .notPhysicalEvidence
  }
}

/// A simulator-only position. It is intentionally not `MachinePosition` and
/// cannot be inserted into controller or physical-evidence paths.
public struct SimulatedLearningMPos: Codable, Hashable, Sendable {
  public static let zero = SimulatedLearningMPos(uncheckedXMM: 0, yMM: 0)

  public let xMM: Double
  public let yMM: Double

  public init(xMM: Double, yMM: Double) throws {
    guard xMM.isFinite, yMM.isFinite else {
      throw SimulatedLearningValueError.nonFinitePosition
    }
    self.init(uncheckedXMM: xMM, yMM: yMM)
  }

  private init(uncheckedXMM xMM: Double, yMM: Double) {
    self.xMM = xMM
    self.yMM = yMM
  }

  fileprivate func applying(_ delta: SimulatedLearningMotionVector) -> Self? {
    let resultX = xMM + delta.dxMM
    let resultY = yMM + delta.dyMM
    guard resultX.isFinite, resultY.isFinite else { return nil }
    return Self(uncheckedXMM: resultX, yMM: resultY)
  }
}

/// A simulator-only displacement in millimetres.
public struct SimulatedLearningMotionVector: Codable, Hashable, Sendable {
  public let dxMM: Double
  public let dyMM: Double

  public init(dxMM: Double, dyMM: Double) throws {
    guard dxMM.isFinite, dyMM.isFinite else {
      throw SimulatedLearningValueError.nonFiniteMotion
    }
    self.dxMM = dxMM
    self.dyMM = dyMM
  }

  fileprivate init(uncheckedDXMM dxMM: Double, dyMM: Double) {
    self.dxMM = dxMM
    self.dyMM = dyMM
  }
}

public struct SimulatedLearningOperationID: Codable, Hashable, Sendable {
  public let sequence: UInt64

  public init(sequence: UInt64) {
    self.sequence = sequence
  }
}

public enum SimulatedLearningOperationKind: Hashable, Sendable {
  case manualJog(SimulatedLearningMotionVector)
  case boundary(direction: BoundaryDirection, finiteSegmentLengthMM: Double)
  case drawing(SimulatedLearningMotionVector)
  case visibilityTarget(VisibilityTargetPlanV1)
}

public struct SimulatedLearningOperation: Hashable, Sendable {
  public let id: SimulatedLearningOperationID
  public let kind: SimulatedLearningOperationKind
  public let evidenceNotice: SimulatedLearningEvidenceNotice

  fileprivate init(id: SimulatedLearningOperationID, kind: SimulatedLearningOperationKind) {
    self.id = id
    self.kind = kind
    evidenceNotice = .notPhysicalEvidence
  }
}

public struct SimulatedLearningStickyAmbiguity: Codable, Hashable, Sendable {
  public let operationID: SimulatedLearningOperationID
  public let phase: VisibilityTargetOperationPhase

  public init(
    operationID: SimulatedLearningOperationID,
    phase: VisibilityTargetOperationPhase
  ) {
    self.operationID = operationID
    self.phase = phase
  }
}

public struct SimulatedLearningSnapshot: Hashable, Sendable {
  public let session: SimulatedLearningSessionState
  public let motionAuthorization: SimulatedLearningMotionAuthorization
  public let penPose: SimulatedLearningPenPose
  public let mpos: SimulatedLearningMPos
  public let currentOperation: SimulatedLearningOperation?
  public let stickyAmbiguity: SimulatedLearningStickyAmbiguity?
  public let boundaryTruth: SimulatedLearningBoundaryTruth
  public let cameraConfigurationID: CameraConfigurationID
  public let frameSequence: UInt64
  public let persistentInkSegmentCount: Int
  public let toolPaperRevision: UUID
  public let evidenceNotice: SimulatedLearningEvidenceNotice

  fileprivate init(
    session: SimulatedLearningSessionState,
    motionAuthorization: SimulatedLearningMotionAuthorization,
    penPose: SimulatedLearningPenPose,
    mpos: SimulatedLearningMPos,
    currentOperation: SimulatedLearningOperation?,
    stickyAmbiguity: SimulatedLearningStickyAmbiguity?,
    boundaryTruth: SimulatedLearningBoundaryTruth,
    cameraConfigurationID: CameraConfigurationID,
    frameSequence: UInt64,
    persistentInkSegmentCount: Int,
    toolPaperRevision: UUID
  ) {
    self.session = session
    self.motionAuthorization = motionAuthorization
    self.penPose = penPose
    self.mpos = mpos
    self.currentOperation = currentOperation
    self.stickyAmbiguity = stickyAmbiguity
    self.boundaryTruth = boundaryTruth
    self.cameraConfigurationID = cameraConfigurationID
    self.frameSequence = frameSequence
    self.persistentInkSegmentCount = persistentInkSegmentCount
    self.toolPaperRevision = toolPaperRevision
    evidenceNotice = .notPhysicalEvidence
  }
}

public enum SimulatedLearningOperationIntent: String, Codable, Hashable, Sendable {
  case stop
  case cancel
  case shutdown
}

public enum SimulatedLearningOperationDisposition: String, Codable, Hashable, Sendable {
  case stopped
  case cancelled
  case naturallyCompleted
  case failed
  case shutdown
}

public struct SimulatedLearningOperationOutcome: Hashable, Sendable {
  public let operation: SimulatedLearningOperation
  public let disposition: SimulatedLearningOperationDisposition
  public let finalMPos: SimulatedLearningMPos
  public let completedBoundarySegmentCount: Int
  public let visibilityTargetSceneDisposition: VisibilityTargetSceneDisposition?
  public let visibilityTargetFailurePhase: VisibilityTargetOperationPhase?
  public let evidenceNotice: SimulatedLearningEvidenceNotice

  fileprivate init(
    operation: SimulatedLearningOperation,
    disposition: SimulatedLearningOperationDisposition,
    finalMPos: SimulatedLearningMPos,
    completedBoundarySegmentCount: Int,
    visibilityTargetSceneDisposition: VisibilityTargetSceneDisposition? = nil,
    visibilityTargetFailurePhase: VisibilityTargetOperationPhase? = nil
  ) {
    self.operation = operation
    self.disposition = disposition
    self.finalMPos = finalMPos
    self.completedBoundarySegmentCount = completedBoundarySegmentCount
    self.visibilityTargetSceneDisposition = visibilityTargetSceneDisposition
    self.visibilityTargetFailurePhase = visibilityTargetFailurePhase
    evidenceNotice = .notPhysicalEvidence
  }
}

public struct SimulatedBoundarySegmentContinuation: Hashable, Sendable {
  public let operationID: SimulatedLearningOperationID
  public let completedSegmentCount: Int
  public let mpos: SimulatedLearningMPos
  public let evidenceNotice: SimulatedLearningEvidenceNotice

  fileprivate init(
    operationID: SimulatedLearningOperationID,
    completedSegmentCount: Int,
    mpos: SimulatedLearningMPos
  ) {
    self.operationID = operationID
    self.completedSegmentCount = completedSegmentCount
    self.mpos = mpos
    evidenceNotice = .notPhysicalEvidence
  }
}

public enum SimulatedLearningRefusal: Error, Hashable, Sendable {
  case sessionDisconnected
  case sessionAlreadyConnected
  case sessionAlreadyDisconnected
  case motionAuthorizationDisabled
  case operationAlreadyActive(SimulatedLearningOperationID)
  case operationAlreadySettled(
    SimulatedLearningOperationID,
    SimulatedLearningOperationDisposition
  )
  case staleOperation(
    requested: SimulatedLearningOperationID,
    active: SimulatedLearningOperationID?
  )
  case penMustBeUp
  case penMustBeDown
  case invalidBoundarySegmentLength
  case resultingPositionNonFinite
  case operationIsNotBoundary
  case boundaryRequiresStopOrCancel
  case injectedRefusal
  case stickyAmbiguity(SimulatedLearningStickyAmbiguity)
  case frameRenderingFailed(String)
}

/// Every simulator call returns this wrapper so simulated provenance cannot be
/// lost when an admission is refused.
public struct SimulatedLearningResponse<Value: Sendable>: Sendable {
  public let result: Result<Value, SimulatedLearningRefusal>
  public let evidenceNotice: SimulatedLearningEvidenceNotice

  fileprivate init(result: Result<Value, SimulatedLearningRefusal>) {
    self.result = result
    evidenceNotice = .notPhysicalEvidence
  }

  fileprivate static func accepted(_ value: Value) -> Self {
    Self(result: .success(value))
  }

  fileprivate static func refused(_ refusal: SimulatedLearningRefusal) -> Self {
    Self(result: .failure(refusal))
  }
}

/// Suspension policy for causal simulated execution. Every suspension is an
/// operator-intent boundary: after it returns, the runtime rechecks that the
/// same logical owner is still current before applying another causal action.
public protocol SimulatedLearningExecutionPacing: Sendable {
  func suspendBetweenSteps() async
}

public struct SimulatedLearningInteractivePacing: SimulatedLearningExecutionPacing, Sendable {
  public let stepDelay: Duration

  public init(stepDelay: Duration = .milliseconds(250)) {
    precondition(stepDelay >= .zero)
    self.stepDelay = stepDelay
  }

  public func suspendBetweenSteps() async {
    try? await Task.sleep(for: stepDelay)
  }
}

public struct SimulatedLearningImmediatePacing: SimulatedLearningExecutionPacing, Sendable {
  public init() {}

  public func suspendBetweenSteps() async {
    await Task.yield()
  }
}

/// Deterministic, nonphysical state machine for exercising the operator path.
/// It owns no serial session, `MachineController`, `MachineActions`, camera, or
/// evidence-producing type. Callers explicitly drive natural completions and
/// finite Boundary segment completions.
public actor SimulatedLearningRuntime {
  private var session: SimulatedLearningSessionState = .disconnected
  private var motionAuthorization: SimulatedLearningMotionAuthorization = .disabled
  private var penPose: SimulatedLearningPenPose = .up
  private var mpos: SimulatedLearningMPos
  private var currentOperation: SimulatedLearningOperation?
  private var stickyAmbiguity: SimulatedLearningStickyAmbiguity?
  private var nextOperationSequence: UInt64 = 1
  private var completedBoundarySegmentCounts: [SimulatedLearningOperationID: Int] = [:]
  private var outcomes: [SimulatedLearningOperationID: SimulatedLearningOperationOutcome] = [:]
  private let boundaryTruth: SimulatedLearningBoundaryTruth
  private var cameraConfigurationID: CameraConfigurationID
  private var frameSequence: UInt64 = 1
  private var frameTimestamp: UInt64 = 1
  private var inkSegments: [SimulatedLearningInkSegment] = []
  private var toolPaperRevision = UUID()
  private var injectedFaults: [SimulatedLearningFault] = []
  private var cooperativeExecutionOperationID: SimulatedLearningOperationID?
  private var visibilityTargetSceneByOperationID:
    [SimulatedLearningOperationID: VisibilityTargetSceneDisposition] = [:]
  private let frameWidth: Int
  private let frameHeight: Int
  private let pixelsPerMillimeter: Double
  private var outcomeWaiters:
    [SimulatedLearningOperationID: [CheckedContinuation<SimulatedLearningOperationOutcome, Never>]] =
      [:]

  public init(
    initialMPos: SimulatedLearningMPos = .zero,
    boundaryTruth: SimulatedLearningBoundaryTruth = SimulatedLearningBoundaryTruth(),
    frameWidth: Int = 640,
    frameHeight: Int = 480,
    pixelsPerMillimeter: Double = 4
  ) {
    precondition(frameWidth > 0 && frameHeight > 0)
    precondition(pixelsPerMillimeter.isFinite && pixelsPerMillimeter > 0)
    mpos = initialMPos
    self.boundaryTruth = boundaryTruth
    self.frameWidth = frameWidth
    self.frameHeight = frameHeight
    self.pixelsPerMillimeter = pixelsPerMillimeter
    cameraConfigurationID = CameraConfigurationID()
  }

  public func snapshot() -> SimulatedLearningSnapshot {
    makeSnapshot()
  }

  public func injectFault(_ fault: SimulatedLearningFault) {
    injectedFaults.append(fault)
  }

  public func persistentInk() -> [SimulatedLearningInkSegment] {
    inkSegments
  }

  /// Explicit simulated human fact. It clears only the causal paper scene and
  /// rotates paper compatibility; camera configuration remains a separate
  /// optical identity.
  public func recordPaperReplaced() -> SimulatedLearningResponse<SimulatedLearningSnapshot> {
    guard currentOperation == nil else {
      return .refused(.operationAlreadyActive(currentOperation!.id))
    }
    inkSegments.removeAll()
    toolPaperRevision = UUID()
    return .accepted(makeSnapshot())
  }

  public func connect() -> SimulatedLearningResponse<SimulatedLearningSnapshot> {
    guard session == .disconnected else {
      return .refused(.sessionAlreadyConnected)
    }
    session = .connected
    return .accepted(makeSnapshot())
  }

  public func disconnect() -> SimulatedLearningResponse<SimulatedLearningSnapshot> {
    guard session == .connected else {
      return .refused(.sessionAlreadyDisconnected)
    }
    guard currentOperation == nil else {
      return .refused(.operationAlreadyActive(currentOperation!.id))
    }
    session = .disconnected
    motionAuthorization = .disabled
    penPose = .up
    stickyAmbiguity = nil
    return .accepted(makeSnapshot())
  }

  public func enableMotion() -> SimulatedLearningResponse<SimulatedLearningSnapshot> {
    guard session == .connected else {
      return .refused(.sessionDisconnected)
    }
    motionAuthorization = .enabled
    return .accepted(makeSnapshot())
  }

  public func disableMotion() -> SimulatedLearningResponse<SimulatedLearningSnapshot> {
    guard session == .connected else {
      return .refused(.sessionDisconnected)
    }
    guard currentOperation == nil else {
      return .refused(.operationAlreadyActive(currentOperation!.id))
    }
    motionAuthorization = .disabled
    return .accepted(makeSnapshot())
  }

  public func setPenPose(
    _ pose: SimulatedLearningPenPose
  ) -> SimulatedLearningResponse<SimulatedLearningSnapshot> {
    guard session == .connected else {
      return .refused(.sessionDisconnected)
    }
    guard motionAuthorization == .enabled else {
      return .refused(.motionAuthorizationDisabled)
    }
    if let stickyAmbiguity { return .refused(.stickyAmbiguity(stickyAmbiguity)) }
    guard currentOperation == nil else {
      return .refused(.operationAlreadyActive(currentOperation!.id))
    }
    penPose = pose
    return .accepted(makeSnapshot())
  }

  public func beginManualJog(
    delta: SimulatedLearningMotionVector
  ) -> SimulatedLearningResponse<SimulatedLearningOperation> {
    beginOperation(kind: .manualJog(delta), requiredPenPose: .up)
  }

  public func beginBoundary(
    direction: BoundaryDirection,
    finiteSegmentLengthMM: Double
  ) -> SimulatedLearningResponse<SimulatedLearningOperation> {
    guard finiteSegmentLengthMM.isFinite, finiteSegmentLengthMM > 0 else {
      return .refused(.invalidBoundarySegmentLength)
    }
    return beginOperation(
      kind: .boundary(
        direction: direction,
        finiteSegmentLengthMM: finiteSegmentLengthMM
      ),
      requiredPenPose: .up
    )
  }

  public func beginDrawing(
    delta: SimulatedLearningMotionVector
  ) -> SimulatedLearningResponse<SimulatedLearningOperation> {
    beginOperation(kind: .drawing(delta), requiredPenPose: .down)
  }

  public func beginVisibilityTarget(
    plan: VisibilityTargetPlanV1 = VisibilityTargetPlanV1()
  ) -> SimulatedLearningResponse<SimulatedLearningOperation> {
    beginOperation(kind: .visibilityTarget(plan), requiredPenPose: .up)
  }

  /// The first Stop or Cancel accepted for an operation is its only terminal
  /// disposition. Actor isolation is the intent latch.
  public func request(
    _ intent: SimulatedLearningOperationIntent,
    for operationID: SimulatedLearningOperationID
  ) -> SimulatedLearningResponse<SimulatedLearningOperationOutcome> {
    if let outcome = outcomes[operationID] {
      return .refused(
        .operationAlreadySettled(operationID, outcome.disposition)
      )
    }
    guard let operation = currentOperation, operation.id == operationID else {
      return .refused(
        .staleOperation(requested: operationID, active: currentOperation?.id)
      )
    }
    let disposition: SimulatedLearningOperationDisposition =
      switch intent {
      case .stop: .stopped
      case .cancel: .cancelled
      case .shutdown: .shutdown
      }
    let scene: VisibilityTargetSceneDisposition?
    switch operation.kind {
    case .visibilityTarget:
      if penPose == .down { penPose = .up }
      scene = visibilityTargetSceneByOperationID[operation.id] ?? .pristine
    case .drawing:
      if penPose == .down { penPose = .up }
      scene = nil
    default:
      scene = nil
    }
    return .accepted(settle(
      operation,
      disposition: disposition,
      visibilityTargetSceneDisposition: scene
    ))
  }

  public func stop(
    _ operationID: SimulatedLearningOperationID
  ) -> SimulatedLearningResponse<SimulatedLearningOperationOutcome> {
    request(.stop, for: operationID)
  }

  public func cancel(
    _ operationID: SimulatedLearningOperationID
  ) -> SimulatedLearningResponse<SimulatedLearningOperationOutcome> {
    request(.cancel, for: operationID)
  }

  public func shutdown(
    _ operationID: SimulatedLearningOperationID
  ) -> SimulatedLearningResponse<SimulatedLearningOperationOutcome> {
    request(.shutdown, for: operationID)
  }

  /// Models one unambiguous finite wire segment completing beneath the same
  /// logical Boundary owner. It updates simulated MPos but never settles the
  /// Boundary operation or manufactures Boundary success.
  public func recordBoundarySegmentCompletion(
    for operationID: SimulatedLearningOperationID
  ) -> SimulatedLearningResponse<SimulatedBoundarySegmentContinuation> {
    if let outcome = outcomes[operationID] {
      return .refused(
        .operationAlreadySettled(operationID, outcome.disposition)
      )
    }
    guard let operation = currentOperation, operation.id == operationID else {
      return .refused(
        .staleOperation(requested: operationID, active: currentOperation?.id)
      )
    }
    guard case .boundary(let direction, let segmentLengthMM) = operation.kind else {
      return .refused(.operationIsNotBoundary)
    }
    if consumeInjectedShutdown() {
      _ = settle(operation, disposition: .shutdown)
      return .refused(.sessionDisconnected)
    }
    let proposedDelta = Self.boundaryDelta(direction, lengthMM: segmentLengthMM)
    guard let proposedMPos = mpos.applying(proposedDelta)
    else {
      return .refused(.resultingPositionNonFinite)
    }
    let limit = boundaryTruth.limit(for: direction)
    let reachesTruth: Bool = switch direction {
    case .negativeX: proposedMPos.xMM <= limit
    case .positiveX: proposedMPos.xMM >= limit
    case .negativeY: proposedMPos.yMM <= limit
    case .positiveY: proposedMPos.yMM >= limit
    }
    if reachesTruth {
      mpos = switch direction {
      case .negativeX, .positiveX: try! SimulatedLearningMPos(xMM: limit, yMM: mpos.yMM)
      case .negativeY, .positiveY: try! SimulatedLearningMPos(xMM: mpos.xMM, yMM: limit)
      }
    } else {
      mpos = proposedMPos
    }
    let completedCount = completedBoundarySegmentCounts[operationID, default: 0] + 1
    completedBoundarySegmentCounts[operationID] = completedCount
    return .accepted(
      SimulatedBoundarySegmentContinuation(
        operationID: operationID,
        completedSegmentCount: completedCount,
      mpos: mpos
      )
    )
  }

  /// Manual and drawing operations may complete naturally. Boundary is
  /// intentionally excluded because a finite segment is not exercise success.
  public func completeNaturally(
    _ operationID: SimulatedLearningOperationID
  ) -> SimulatedLearningResponse<SimulatedLearningOperationOutcome> {
    if let outcome = outcomes[operationID] {
      return .refused(
        .operationAlreadySettled(operationID, outcome.disposition)
      )
    }
    guard let operation = currentOperation, operation.id == operationID else {
      return .refused(
        .staleOperation(requested: operationID, active: currentOperation?.id)
      )
    }
    if consumeInjectedShutdown() {
      return .accepted(settle(operation, disposition: .shutdown))
    }
    switch operation.kind {
    case .boundary:
      return .refused(.boundaryRequiresStopOrCancel)
    case .manualJog(let delta):
      guard let updatedMPos = mpos.applying(delta) else {
        return .refused(.resultingPositionNonFinite)
      }
      mpos = updatedMPos
      return .accepted(settle(operation, disposition: .naturallyCompleted))
    case .drawing(let delta):
      guard let updatedMPos = mpos.applying(delta) else {
        return .refused(.resultingPositionNonFinite)
      }
      let start = mpos
      mpos = updatedMPos
      if removeFirstFault(matching: {
        if case .absentInk = $0 { return true }
        return false
      }) == nil {
        inkSegments.append(SimulatedLearningInkSegment(start: start, end: updatedMPos))
      }
      return .accepted(settle(operation, disposition: .naturallyCompleted))
    case .visibilityTarget:
      return .refused(.boundaryRequiresStopOrCancel)
    }
  }

  /// Drives an admitted finite operation with cooperative pacing. The default
  /// pacing is deliberately visible to a human operator. Tests may inject an
  /// immediate or controlled pacer without changing simulator causality.
  public func executeNaturally(
    _ operationID: SimulatedLearningOperationID,
    pacing: any SimulatedLearningExecutionPacing = SimulatedLearningInteractivePacing()
  ) async -> SimulatedLearningResponse<SimulatedLearningOperationOutcome> {
    if let outcome = outcomes[operationID] {
      return .refused(.operationAlreadySettled(operationID, outcome.disposition))
    }
    guard let operation = currentOperation, operation.id == operationID else {
      return .refused(.staleOperation(requested: operationID, active: currentOperation?.id))
    }
    guard cooperativeExecutionOperationID == nil else {
      return .refused(.operationAlreadyActive(cooperativeExecutionOperationID!))
    }
    cooperativeExecutionOperationID = operationID
    defer {
      if cooperativeExecutionOperationID == operationID {
        cooperativeExecutionOperationID = nil
      }
    }

    switch operation.kind {
    case .boundary:
      return .refused(.boundaryRequiresStopOrCancel)
    case .manualJog, .drawing:
      if let terminal = await suspendAndRecheck(
        operation,
        pacing: pacing,
        visibilityTargetSceneDisposition: nil
      ) {
        return terminal
      }
      return completeNaturally(operationID)
    case .visibilityTarget(let plan):
      return await executeVisibilityTargetNaturally(
        operation,
        plan: plan,
        pacing: pacing
      )
    }
  }

  /// Executes the causal simulator equivalent of the compound target owner.
  /// Ink segments are added one-by-one to persistent scene state; a configured
  /// partial-target fault leaves exactly that prefix and reports `inkPossible`.
  public func completeVisibilityTargetNaturally(
    _ operationID: SimulatedLearningOperationID
  ) -> SimulatedLearningResponse<SimulatedLearningOperationOutcome> {
    guard let operation = currentOperation, operation.id == operationID else {
      return .refused(.staleOperation(requested: operationID, active: currentOperation?.id))
    }
    guard case .visibilityTarget(let plan) = operation.kind else {
      return .refused(.operationIsNotBoundary)
    }
    if consumeInjectedShutdown() {
      return .accepted(settle(
        operation,
        disposition: .shutdown,
        visibilityTargetSceneDisposition: .pristine
      ))
    }
    let ambiguousPhase: VisibilityTargetOperationPhase? = removeFirstFault(matching: {
      if case .ambiguityAtVisibilityTargetPhase = $0 { return true }
      return false
    }).flatMap {
      guard case .ambiguityAtVisibilityTargetPhase(let phase) = $0 else { return nil }
      return phase
    }
    if ambiguousPhase == .approach {
      stickyAmbiguity = SimulatedLearningStickyAmbiguity(
        operationID: operation.id,
        phase: .approach
      )
      penPose = .unknown
      return .accepted(settle(
        operation,
        disposition: .failed,
        visibilityTargetSceneDisposition: .pristine,
        visibilityTargetFailurePhase: .approach
      ))
    }
    guard let perimeterStart = mpos.applying(SimulatedLearningMotionVector(
      uncheckedDXMM: plan.approachDelta.dx,
      dyMM: plan.approachDelta.dy
    )) else { return .refused(.resultingPositionNonFinite) }
    mpos = perimeterStart
    if ambiguousPhase == .lowerPen {
      stickyAmbiguity = SimulatedLearningStickyAmbiguity(
        operationID: operation.id,
        phase: .lowerPen
      )
      penPose = .unknown
      return .accepted(settle(
        operation,
        disposition: .failed,
        visibilityTargetSceneDisposition: .inkPossible,
        visibilityTargetFailurePhase: .lowerPen
      ))
    }
    penPose = .down

    let partialCount: Int? = removeFirstFault(matching: {
      if case .partialVisibilityTarget = $0 { return true }
      return false
    }).flatMap {
      guard case .partialVisibilityTarget(let count) = $0 else { return nil }
      return max(0, min(plan.segmentCount, count))
    }
    let omitInk = removeFirstFault(matching: {
      if case .absentInk = $0 { return true }
      return false
    }) != nil
    let segmentLimit = partialCount ?? plan.drawingDeltas.count
    for (index, delta) in plan.drawingDeltas.prefix(segmentLimit).enumerated() {
      if ambiguousPhase == .drawSegment(index) {
        stickyAmbiguity = SimulatedLearningStickyAmbiguity(
          operationID: operation.id,
          phase: .drawSegment(index)
        )
        return .accepted(settle(
          operation,
          disposition: .failed,
          visibilityTargetSceneDisposition: .inkPossible,
          visibilityTargetFailurePhase: .drawSegment(index)
        ))
      }
      let start = mpos
      guard let end = mpos.applying(SimulatedLearningMotionVector(
        uncheckedDXMM: delta.dx,
        dyMM: delta.dy
      )) else { return .refused(.resultingPositionNonFinite) }
      if !omitInk { inkSegments.append(SimulatedLearningInkSegment(start: start, end: end)) }
      mpos = end
    }
    if ambiguousPhase == .raisePen {
      stickyAmbiguity = SimulatedLearningStickyAmbiguity(
        operationID: operation.id,
        phase: .raisePen
      )
      penPose = .unknown
      return .accepted(settle(
        operation,
        disposition: .failed,
        visibilityTargetSceneDisposition: .inkPossible,
        visibilityTargetFailurePhase: .raisePen
      ))
    }
    penPose = .up
    let complete = segmentLimit == plan.segmentCount
    return .accepted(settle(
      operation,
      disposition: complete ? .naturallyCompleted : .failed,
      visibilityTargetSceneDisposition: .inkPossible
    ))
  }

  private func executeVisibilityTargetNaturally(
    _ operation: SimulatedLearningOperation,
    plan: VisibilityTargetPlanV1,
    pacing: any SimulatedLearningExecutionPacing
  ) async -> SimulatedLearningResponse<SimulatedLearningOperationOutcome> {
    let ambiguousPhase: VisibilityTargetOperationPhase? = removeFirstFault(matching: {
      if case .ambiguityAtVisibilityTargetPhase = $0 { return true }
      return false
    }).flatMap {
      guard case .ambiguityAtVisibilityTargetPhase(let phase) = $0 else { return nil }
      return phase
    }
    let partialCount: Int? = removeFirstFault(matching: {
      if case .partialVisibilityTarget = $0 { return true }
      return false
    }).flatMap {
      guard case .partialVisibilityTarget(let count) = $0 else { return nil }
      return max(0, min(plan.segmentCount, count))
    }
    let omitInk = removeFirstFault(matching: {
      if case .absentInk = $0 { return true }
      return false
    }) != nil

    if let terminal = await suspendAndRecheck(
      operation,
      pacing: pacing,
      visibilityTargetSceneDisposition: .pristine
    ) {
      return terminal
    }
    if ambiguousPhase == .approach {
      return settleVisibilityTargetAmbiguity(operation, phase: .approach, scene: .pristine)
    }
    guard let perimeterStart = mpos.applying(SimulatedLearningMotionVector(
      uncheckedDXMM: plan.approachDelta.dx,
      dyMM: plan.approachDelta.dy
    )) else { return .refused(.resultingPositionNonFinite) }
    mpos = perimeterStart

    if let terminal = await suspendAndRecheck(
      operation,
      pacing: pacing,
      visibilityTargetSceneDisposition: .pristine
    ) {
      return terminal
    }
    if ambiguousPhase == .lowerPen {
      visibilityTargetSceneByOperationID[operation.id] = .inkPossible
      return settleVisibilityTargetAmbiguity(operation, phase: .lowerPen, scene: .inkPossible)
    }
    penPose = .down
    visibilityTargetSceneByOperationID[operation.id] = .inkPossible

    let segmentLimit = partialCount ?? plan.drawingDeltas.count
    for (index, delta) in plan.drawingDeltas.prefix(segmentLimit).enumerated() {
      if let terminal = await suspendAndRecheck(
        operation,
        pacing: pacing,
        visibilityTargetSceneDisposition: .inkPossible
      ) {
        return terminal
      }
      if ambiguousPhase == .drawSegment(index) {
        return settleVisibilityTargetAmbiguity(
          operation,
          phase: .drawSegment(index),
          scene: .inkPossible
        )
      }
      let start = mpos
      guard let end = mpos.applying(SimulatedLearningMotionVector(
        uncheckedDXMM: delta.dx,
        dyMM: delta.dy
      )) else { return .refused(.resultingPositionNonFinite) }
      if !omitInk {
        inkSegments.append(SimulatedLearningInkSegment(start: start, end: end))
      }
      mpos = end
    }

    if let terminal = await suspendAndRecheck(
      operation,
      pacing: pacing,
      visibilityTargetSceneDisposition: .inkPossible
    ) {
      return terminal
    }
    if ambiguousPhase == .raisePen {
      return settleVisibilityTargetAmbiguity(operation, phase: .raisePen, scene: .inkPossible)
    }
    penPose = .up
    return .accepted(settle(
      operation,
      disposition: segmentLimit == plan.segmentCount ? .naturallyCompleted : .failed,
      visibilityTargetSceneDisposition: .inkPossible
    ))
  }

  private func suspendAndRecheck(
    _ operation: SimulatedLearningOperation,
    pacing: any SimulatedLearningExecutionPacing,
    visibilityTargetSceneDisposition: VisibilityTargetSceneDisposition?
  ) async -> SimulatedLearningResponse<SimulatedLearningOperationOutcome>? {
    await pacing.suspendBetweenSteps()
    if let outcome = outcomes[operation.id] {
      return .accepted(outcome)
    }
    guard currentOperation?.id == operation.id else {
      return .refused(
        .staleOperation(requested: operation.id, active: currentOperation?.id)
      )
    }
    if consumeInjectedShutdown() {
      return .accepted(settle(
        operation,
        disposition: .shutdown,
        visibilityTargetSceneDisposition: visibilityTargetSceneDisposition
      ))
    }
    return nil
  }

  private func settleVisibilityTargetAmbiguity(
    _ operation: SimulatedLearningOperation,
    phase: VisibilityTargetOperationPhase,
    scene: VisibilityTargetSceneDisposition
  ) -> SimulatedLearningResponse<SimulatedLearningOperationOutcome> {
    stickyAmbiguity = SimulatedLearningStickyAmbiguity(
      operationID: operation.id,
      phase: phase
    )
    if phase == .approach || phase == .lowerPen || phase == .raisePen {
      penPose = .unknown
    }
    return .accepted(settle(
      operation,
      disposition: .failed,
      visibilityTargetSceneDisposition: scene,
      visibilityTargetFailurePhase: phase
    ))
  }

  public func captureSceneFrame() -> SimulatedLearningResponse<SimulatedLearningSceneFrame> {
    if removeFirstFault(matching: {
      if case .cameraConfigurationChangeBeforeNextFrame = $0 { return true }
      return false
    }) != nil {
      cameraConfigurationID = CameraConfigurationID()
    }
    var renderedPosition = mpos
    if let fault = removeFirstFault(matching: {
      if case .poseMismatchBeforeNextFrame = $0 { return true }
      return false
    }), case .poseMismatchBeforeNextFrame(let dx, let dy) = fault,
      let shifted = renderedPosition.applying(
        SimulatedLearningMotionVector(uncheckedDXMM: dx, dyMM: dy)
      )
    {
      renderedPosition = shifted
    }
    do {
      let contact = cameraPoint(for: renderedPosition)
      let armature = try AxisAlignedBounds<CameraPixelSpace>(
        minX: contact.x - 7,
        minY: contact.y - 30,
        maxX: contact.x + 7,
        maxY: contact.y
      )
      var strokes = inkSegments.map {
        SimulatedCameraStroke(
          start: cameraPoint(for: $0.start),
          end: cameraPoint(for: $0.end),
          green: 190
        )
      }
      if removeFirstFault(matching: {
        if case .unstableTarget = $0 { return true }
        return false
      }) != nil, let last = strokes.last {
        strokes.append(SimulatedCameraStroke(
          start: try Point2(x: last.start.x + 3, y: last.start.y),
          end: try Point2(x: last.end.x + 3, y: last.end.y),
          green: 190
        ))
      }
      // The simulated armature is visible in the same pixels as the paper. Its
      // bottom-center is the contact point used by registration.
      let armatureVerticalCount = max(1, Int(armature.maxX - armature.minX))
      for offset in 0...armatureVerticalCount {
        let x = armature.minX + Double(offset)
        strokes.append(SimulatedCameraStroke(
          start: try Point2(x: x, y: armature.minY),
          end: try Point2(x: x, y: armature.maxY),
          green: 150
        ))
      }
      if removeFirstFault(matching: {
        if case .excessiveBackgroundResidual = $0 { return true }
        return false
      }) != nil {
        strokes.append(SimulatedCameraStroke(
          start: try Point2(x: 0, y: 0),
          end: try Point2(x: Double(frameWidth - 1), y: Double(frameHeight - 1)),
          green: 220
        ))
      }
      var source = try SimulatedFrameSource(
        width: frameWidth,
        height: frameHeight,
        fieldToCamera: AffineTransform2<FieldSpace, CameraPixelSpace>(
          m11: 1, m12: 0, m21: 0, m22: 1, tx: 0, ty: 0
        ),
        cameraConfigurationID: cameraConfigurationID,
        initialSequence: frameSequence
      )
      let displayed = try source.render(strokes: strokes, captureNanoseconds: frameTimestamp)
      frameSequence &+= 1
      frameTimestamp &+= 1
      return .accepted(SimulatedLearningSceneFrame(
        displayedFrame: displayed,
        controllerPosition: renderedPosition,
        contactPoint: contact,
        armatureBounds: armature,
        inkSegmentCount: inkSegments.count,
        toolPaperRevision: toolPaperRevision
      ))
    } catch {
      return .refused(.frameRenderingFailed(String(describing: error)))
    }
  }

  /// Waits for the outcome of the specified original owner. A later operation
  /// cannot satisfy this wait because waiters and outcomes are keyed by owner ID.
  public func waitForOutcome(
    of operationID: SimulatedLearningOperationID
  ) async -> SimulatedLearningResponse<SimulatedLearningOperationOutcome> {
    if let outcome = outcomes[operationID] {
      return .accepted(outcome)
    }
    guard currentOperation?.id == operationID else {
      return .refused(
        .staleOperation(requested: operationID, active: currentOperation?.id)
      )
    }
    let outcome = await withCheckedContinuation { continuation in
      outcomeWaiters[operationID, default: []].append(continuation)
    }
    return .accepted(outcome)
  }

  private func beginOperation(
    kind: SimulatedLearningOperationKind,
    requiredPenPose: SimulatedLearningPenPose
  ) -> SimulatedLearningResponse<SimulatedLearningOperation> {
    guard session == .connected else {
      return .refused(.sessionDisconnected)
    }
    guard motionAuthorization == .enabled else {
      return .refused(.motionAuthorizationDisabled)
    }
    guard currentOperation == nil else {
      return .refused(.operationAlreadyActive(currentOperation!.id))
    }
    if let stickyAmbiguity { return .refused(.stickyAmbiguity(stickyAmbiguity)) }
    guard penPose == requiredPenPose else {
      return .refused(requiredPenPose == .up ? .penMustBeUp : .penMustBeDown)
    }
    if removeFirstFault(matching: {
      if case .refuseNextOperation = $0 { return true }
      return false
    }) != nil {
      return .refused(.injectedRefusal)
    }
    let operation = SimulatedLearningOperation(
      id: SimulatedLearningOperationID(sequence: nextOperationSequence),
      kind: kind
    )
    nextOperationSequence += 1
    currentOperation = operation
    completedBoundarySegmentCounts[operation.id] = 0
    if case .visibilityTarget = kind {
      visibilityTargetSceneByOperationID[operation.id] = .pristine
    }
    return .accepted(operation)
  }

  private func settle(
    _ operation: SimulatedLearningOperation,
    disposition: SimulatedLearningOperationDisposition,
    visibilityTargetSceneDisposition: VisibilityTargetSceneDisposition? = nil,
    visibilityTargetFailurePhase: VisibilityTargetOperationPhase? = nil
  ) -> SimulatedLearningOperationOutcome {
    let outcome = SimulatedLearningOperationOutcome(
      operation: operation,
      disposition: disposition,
      finalMPos: mpos,
      completedBoundarySegmentCount: completedBoundarySegmentCounts[operation.id, default: 0],
      visibilityTargetSceneDisposition: visibilityTargetSceneDisposition,
      visibilityTargetFailurePhase: visibilityTargetFailurePhase
    )
    outcomes[operation.id] = outcome
    currentOperation = nil
    if cooperativeExecutionOperationID == operation.id {
      cooperativeExecutionOperationID = nil
    }
    visibilityTargetSceneByOperationID.removeValue(forKey: operation.id)
    completedBoundarySegmentCounts.removeValue(forKey: operation.id)
    let waiters = outcomeWaiters.removeValue(forKey: operation.id) ?? []
    for waiter in waiters {
      waiter.resume(returning: outcome)
    }
    return outcome
  }

  private func makeSnapshot() -> SimulatedLearningSnapshot {
    SimulatedLearningSnapshot(
      session: session,
      motionAuthorization: motionAuthorization,
      penPose: penPose,
      mpos: mpos,
      currentOperation: currentOperation,
      stickyAmbiguity: stickyAmbiguity,
      boundaryTruth: boundaryTruth,
      cameraConfigurationID: cameraConfigurationID,
      frameSequence: frameSequence,
      persistentInkSegmentCount: inkSegments.count,
      toolPaperRevision: toolPaperRevision
    )
  }

  private func removeFirstFault(
    matching predicate: (SimulatedLearningFault) -> Bool
  ) -> SimulatedLearningFault? {
    guard let index = injectedFaults.firstIndex(where: predicate) else { return nil }
    return injectedFaults.remove(at: index)
  }

  private func consumeInjectedShutdown() -> Bool {
    guard removeFirstFault(matching: {
      if case .shutdownDuringOperation = $0 { return true }
      return false
    }) != nil else { return false }
    session = .disconnected
    motionAuthorization = .disabled
    return true
  }

  private func cameraPoint(
    for position: SimulatedLearningMPos
  ) -> Point2<CameraPixelSpace> {
    try! Point2(
      x: Double(frameWidth) / 2 + position.xMM * pixelsPerMillimeter,
      y: Double(frameHeight) / 2 + position.yMM * pixelsPerMillimeter
    )
  }

  private static func boundaryDelta(
    _ direction: BoundaryDirection,
    lengthMM: Double
  ) -> SimulatedLearningMotionVector {
    // Values were validated when the Boundary operation was admitted.
    switch direction {
    case .negativeX:
      return SimulatedLearningMotionVector(uncheckedDXMM: -lengthMM, dyMM: 0)
    case .positiveX:
      return SimulatedLearningMotionVector(uncheckedDXMM: lengthMM, dyMM: 0)
    case .negativeY:
      return SimulatedLearningMotionVector(uncheckedDXMM: 0, dyMM: -lengthMM)
    case .positiveY:
      return SimulatedLearningMotionVector(uncheckedDXMM: 0, dyMM: lengthMM)
    }
  }
}
