import Foundation

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
  case up
  case down
}

public enum SimulatedLearningValueError: Error, Hashable, Sendable {
  case nonFinitePosition
  case nonFiniteMotion
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

public struct SimulatedLearningSnapshot: Hashable, Sendable {
  public let session: SimulatedLearningSessionState
  public let motionAuthorization: SimulatedLearningMotionAuthorization
  public let penPose: SimulatedLearningPenPose
  public let mpos: SimulatedLearningMPos
  public let currentOperation: SimulatedLearningOperation?
  public let evidenceNotice: SimulatedLearningEvidenceNotice

  fileprivate init(
    session: SimulatedLearningSessionState,
    motionAuthorization: SimulatedLearningMotionAuthorization,
    penPose: SimulatedLearningPenPose,
    mpos: SimulatedLearningMPos,
    currentOperation: SimulatedLearningOperation?
  ) {
    self.session = session
    self.motionAuthorization = motionAuthorization
    self.penPose = penPose
    self.mpos = mpos
    self.currentOperation = currentOperation
    evidenceNotice = .notPhysicalEvidence
  }
}

public enum SimulatedLearningOperationIntent: String, Codable, Hashable, Sendable {
  case stop
  case cancel
}

public enum SimulatedLearningOperationDisposition: String, Codable, Hashable, Sendable {
  case stopped
  case cancelled
  case naturallyCompleted
}

public struct SimulatedLearningOperationOutcome: Hashable, Sendable {
  public let operation: SimulatedLearningOperation
  public let disposition: SimulatedLearningOperationDisposition
  public let finalMPos: SimulatedLearningMPos
  public let completedBoundarySegmentCount: Int
  public let evidenceNotice: SimulatedLearningEvidenceNotice

  fileprivate init(
    operation: SimulatedLearningOperation,
    disposition: SimulatedLearningOperationDisposition,
    finalMPos: SimulatedLearningMPos,
    completedBoundarySegmentCount: Int
  ) {
    self.operation = operation
    self.disposition = disposition
    self.finalMPos = finalMPos
    self.completedBoundarySegmentCount = completedBoundarySegmentCount
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
  private var nextOperationSequence: UInt64 = 1
  private var completedBoundarySegmentCounts: [SimulatedLearningOperationID: Int] = [:]
  private var outcomes: [SimulatedLearningOperationID: SimulatedLearningOperationOutcome] = [:]
  private var outcomeWaiters:
    [SimulatedLearningOperationID: [CheckedContinuation<SimulatedLearningOperationOutcome, Never>]] =
      [:]

  public init(initialMPos: SimulatedLearningMPos = .zero) {
    mpos = initialMPos
  }

  public func snapshot() -> SimulatedLearningSnapshot {
    makeSnapshot()
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
      }
    return .accepted(settle(operation, disposition: disposition))
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
    guard
      let updatedMPos = mpos.applying(
        Self.boundaryDelta(direction, lengthMM: segmentLengthMM)
      )
    else {
      return .refused(.resultingPositionNonFinite)
    }
    mpos = updatedMPos
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
    switch operation.kind {
    case .boundary:
      return .refused(.boundaryRequiresStopOrCancel)
    case .manualJog(let delta), .drawing(let delta):
      guard let updatedMPos = mpos.applying(delta) else {
        return .refused(.resultingPositionNonFinite)
      }
      mpos = updatedMPos
      return .accepted(settle(operation, disposition: .naturallyCompleted))
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
    guard penPose == requiredPenPose else {
      return .refused(requiredPenPose == .up ? .penMustBeUp : .penMustBeDown)
    }
    let operation = SimulatedLearningOperation(
      id: SimulatedLearningOperationID(sequence: nextOperationSequence),
      kind: kind
    )
    nextOperationSequence += 1
    currentOperation = operation
    completedBoundarySegmentCounts[operation.id] = 0
    return .accepted(operation)
  }

  private func settle(
    _ operation: SimulatedLearningOperation,
    disposition: SimulatedLearningOperationDisposition
  ) -> SimulatedLearningOperationOutcome {
    let outcome = SimulatedLearningOperationOutcome(
      operation: operation,
      disposition: disposition,
      finalMPos: mpos,
      completedBoundarySegmentCount: completedBoundarySegmentCounts[operation.id, default: 0]
    )
    outcomes[operation.id] = outcome
    currentOperation = nil
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
      currentOperation: currentOperation
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
