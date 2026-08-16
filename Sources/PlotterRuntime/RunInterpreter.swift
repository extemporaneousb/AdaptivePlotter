import Foundation

public struct InterpreterTransitionToken: Codable, Hashable, Sendable {
  public let id: UUID
  public let generation: UInt64

  public init(id: UUID = UUID(), generation: UInt64) {
    self.id = id
    self.generation = generation
  }
}
public enum RunInterpreterError: Error, Equatable, Sendable {
  case transitionAlreadyInFlight
  case staleTransition
}

enum BoundaryMechanicalSettlementDecision: Equatable, Sendable {
  case settled(MachinePosition)
  case naturalHorizon(MachinePosition)
  case unattributable
}

enum BoundaryMechanicalSettlementPolicy {
  static func classify(
    segmentOutcome: MotionOutcome?,
    cancelOutcome: JogCancelOutcome
  ) -> BoundaryMechanicalSettlementDecision {
    switch segmentOutcome {
    case .acceptedThenCompleted(let position):
      // A late Stop can race with finite-horizon completion. No cancel result,
      // including `noActiveJog`, may turn that natural completion into evidence.
      return .naturalHorizon(position)
    case .cancelled(let position):
      guard cancelOutcome == .completed(finalPosition: position) else {
        return .unattributable
      }
      return .settled(position)
    case .none, .refused, .ambiguous:
      return .unattributable
    }
  }
}

/// A boundary operation whose logical owner is already registered with the
/// interpreter. Publishing this handle is the admission acknowledgement; a
/// caller may expose Stop only after it receives the handle.
public struct BoundaryMotionOperation: Sendable {
  public let ownerID: BoundaryMotionOwnerID
  private let task: Task<BoundaryMotionOutcome, Never>

  public init(
    ownerID: BoundaryMotionOwnerID,
    task: Task<BoundaryMotionOutcome, Never>
  ) {
    self.ownerID = ownerID
    self.task = task
  }

  public func outcome() async -> BoundaryMotionOutcome {
    await task.value
  }
}

public enum BoundaryMotionAdmission: Sendable {
  case admitted(BoundaryMotionOperation)
  case rejected(BoundaryMotionOutcome)
}

public struct RelativeJogOperation: Sendable {
  public let id: UUID
  private let task: Task<MotionOutcome, Never>

  public init(id: UUID, task: Task<MotionOutcome, Never>) {
    self.id = id
    self.task = task
  }

  public func outcome() async -> MotionOutcome {
    await task.value
  }
}

public enum RelativeJogAdmission: Sendable {
  case admitted(RelativeJogOperation)
  case rejected(MotionOutcome)
}

public struct DrawingStrokeOperation: Sendable {
  public let id: UUID
  private let task: Task<DrawingStrokeOutcome, Never>

  public init(id: UUID, task: Task<DrawingStrokeOutcome, Never>) {
    self.id = id
    self.task = task
  }

  public func outcome() async -> DrawingStrokeOutcome {
    await task.value
  }
}

public enum DrawingStrokeAdmission: Sendable {
  case admitted(DrawingStrokeOperation)
  case rejected(DrawingStrokeOutcome)
}

public enum RunOperation: Hashable, Sendable {
  case idle
  case passiveProbe
  case alarmClear
  case relativeJog(RelativeJogRequest)
  case boundaryMotion(BoundaryMotionRequest)
  case drawingStroke(DrawingStrokeRequest)
  case penActuation(PenCommand)
}

public struct RunInterpreterSnapshot: Hashable, Sendable {
  public let currentOperation: RunOperation
  public let machine: MachineSnapshot
  public let lastMotionOutcome: MotionOutcome?
  public let lastBoundaryMotionOutcome: BoundaryMotionOutcome?
  public let lastDrawingStrokeOutcome: DrawingStrokeOutcome?
  public let lastPenOutcome: PenOutcome?
  public let lastProbe: PassiveProbeResult?
  public let jogCancellationInFlight: Bool
  public let lastJogCancelOutcome: JogCancelOutcome?

  public init(
    currentOperation: RunOperation,
    machine: MachineSnapshot,
    lastMotionOutcome: MotionOutcome?,
    lastBoundaryMotionOutcome: BoundaryMotionOutcome? = nil,
    lastDrawingStrokeOutcome: DrawingStrokeOutcome? = nil,
    lastPenOutcome: PenOutcome? = nil,
    lastProbe: PassiveProbeResult?,
    jogCancellationInFlight: Bool = false,
    lastJogCancelOutcome: JogCancelOutcome? = nil
  ) {
    self.currentOperation = currentOperation
    self.machine = machine
    self.lastMotionOutcome = lastMotionOutcome
    self.lastBoundaryMotionOutcome = lastBoundaryMotionOutcome
    self.lastDrawingStrokeOutcome = lastDrawingStrokeOutcome
    self.lastPenOutcome = lastPenOutcome
    self.lastProbe = lastProbe
    self.jogCancellationInFlight = jogCancellationInFlight
    self.lastJogCancelOutcome = lastJogCancelOutcome
  }
}

/// Serializes the current operator-requested operation. MachineController still
/// owns protocol encoding, safety validation, transport, and physical outcome.
public actor RunInterpreter {
  private struct ActiveBoundaryMotion {
    let request: BoundaryMotionRequest
    var mechanicalCancelIntent: JogCancelIntent?
    var cancelTask: Task<JogCancelOutcome, Never>?
    var cancelOutcome: JogCancelOutcome?
    var completedSegmentCount = 0
    var completionWaiters: [CheckedContinuation<Void, Never>] = []
  }
  private let machineController: MachineController
  private var generation: UInt64 = 0
  private var activeTransition: InterpreterTransitionToken?
  private var currentOperation: RunOperation = .idle
  private var lastProbe: PassiveProbeResult?
  private var lastMotionOutcome: MotionOutcome?
  private var lastBoundaryMotionOutcome: BoundaryMotionOutcome?
  private var lastDrawingStrokeOutcome: DrawingStrokeOutcome?
  private var lastPenOutcome: PenOutcome?
  private var activeBoundaryMotion: ActiveBoundaryMotion?
  private var jogCancelRequestInFlight = false
  private var lastJogCancelOutcome: JogCancelOutcome?

  public init(machineController: MachineController) {
    self.machineController = machineController
  }

  public func snapshot() async -> RunInterpreterSnapshot {
    let machine = await machineController.snapshot()
    return RunInterpreterSnapshot(
      currentOperation: currentOperation,
      machine: machine,
      lastMotionOutcome: lastMotionOutcome,
      lastBoundaryMotionOutcome: lastBoundaryMotionOutcome,
      lastDrawingStrokeOutcome: lastDrawingStrokeOutcome,
      lastPenOutcome: lastPenOutcome,
      lastProbe: lastProbe,
      jogCancellationInFlight: jogCancelRequestInFlight || machine.jogCancellationInFlight,
      lastJogCancelOutcome: machine.lastJogCancelOutcome ?? lastJogCancelOutcome
    )
  }

  public func requestPassiveProbe() async throws -> PassiveProbeResult {
    let token = try beginPassiveProbe()
    let result = await machineController.runPassiveProbe()
    try completePassiveProbe(token: token, result: result)
    return result
  }

  public func requestControllerAlarmClear() async -> ControllerAlarmClearOutcome {
    guard currentOperation == .idle, activeTransition == nil else {
      return .refused(.operationInFlight)
    }
    generation &+= 1
    currentOperation = .alarmClear
    let outcome = await machineController.requestControllerAlarmClear()
    if currentOperation == .alarmClear { currentOperation = .idle }
    return outcome
  }

  public func activateMotionGuard() async -> MotionGuardActivationOutcome {
    await machineController.activateMotionGuard()
  }

  public func deactivateMotionGuard() async {
    await machineController.deactivateMotionGuard()
  }

  public func requestRelativeJog(_ request: RelativeJogRequest) async -> MotionOutcome {
    switch beginRelativeJog(request) {
    case .admitted(let operation):
      return await operation.outcome()
    case .rejected(let outcome):
      return outcome
    }
  }

  public func beginRelativeJog(_ request: RelativeJogRequest) -> RelativeJogAdmission {
    guard currentOperation == .idle else {
      let outcome = MotionOutcome.refused(.operationInFlight)
      lastMotionOutcome = outcome
      return .rejected(outcome)
    }
    generation &+= 1
    currentOperation = .relativeJog(request)
    let operationID = UUID()
    let task = Task { await self.runAdmittedRelativeJog(request) }
    return .admitted(RelativeJogOperation(id: operationID, task: task))
  }

  private func runAdmittedRelativeJog(_ request: RelativeJogRequest) async -> MotionOutcome {
    let outcome = await machineController.requestRelativeJog(request)
    lastMotionOutcome = outcome
    if case .relativeJog = currentOperation { currentOperation = .idle }
    return outcome
  }

  /// Registers the logical owner before returning. This closes the UI/runtime
  /// race where Stop could be published while the request task was still
  /// waiting to enter this actor.
  public func beginBoundaryMotion(
    _ request: BoundaryMotionRequest
  ) async -> BoundaryMotionAdmission {
    guard currentOperation == .idle else {
      let outcome = BoundaryMotionOutcome.needsAttention(
        ownerID: request.ownerID,
        terminal: .refusal(.operationInFlight)
      )
      lastBoundaryMotionOutcome = outcome
      return .rejected(outcome)
    }
    generation &+= 1
    currentOperation = .boundaryMotion(request)
    activeBoundaryMotion = ActiveBoundaryMotion(request: request)
    let task = Task { await self.runAdmittedBoundaryMotion(request) }
    return .admitted(BoundaryMotionOperation(ownerID: request.ownerID, task: task))
  }

  /// Runs one finite GRBL jog under the admitted Boundary owner. Natural
  /// completion is a needs-attention terminal and never boundary evidence.
  private func runAdmittedBoundaryMotion(
    _ request: BoundaryMotionRequest
  ) async -> BoundaryMotionOutcome {
    defer {
      if case .boundaryMotion(let current) = currentOperation,
        current.ownerID == request.ownerID
      {
        currentOperation = .idle
      }
      if activeBoundaryMotion?.request.ownerID == request.ownerID {
        let waiters = activeBoundaryMotion?.completionWaiters ?? []
        activeBoundaryMotion = nil
        for waiter in waiters { waiter.resume() }
      }
    }

    if activeBoundaryMotion?.mechanicalCancelIntent != nil {
      return await finishBoundarySettlement(request: request, segmentOutcome: nil)
    }
    let motionOutcome = await machineController.requestRelativeJog(request.segment)
    lastMotionOutcome = motionOutcome
    if case .acceptedThenCompleted = motionOutcome {
      activeBoundaryMotion?.completedSegmentCount = 1
    }

    if activeBoundaryMotion?.mechanicalCancelIntent != nil {
      switch motionOutcome {
      case .acceptedThenCompleted, .cancelled, .refused(.operationInFlight):
        return await finishBoundarySettlement(request: request, segmentOutcome: motionOutcome)
      case .refused(let refusal):
        return finishBoundaryNeedsAttention(
          request: request,
          terminal: Self.boundaryTerminal(for: refusal)
        )
      case .ambiguous(let ambiguity):
        return finishBoundaryNeedsAttention(
          request: request,
          terminal: Self.boundaryTerminal(for: ambiguity)
        )
      }
    }

    switch motionOutcome {
    case .acceptedThenCompleted(let finalPosition):
      let machine = await machineController.snapshot()
      if machine.pins.hasRelevantLimitAsserted {
        return finishBoundaryNeedsAttention(
          request: request,
          terminal: .limitAsserted(pins: machine.pins.rawValue, finalPosition: finalPosition)
        )
      }
      return finishBoundaryNeedsAttention(
        request: request,
        terminal: .fault(.transport(
          "boundary jog reached its finite horizon without an operator termination"
        ))
      )
    case .cancelled:
      return finishBoundaryNeedsAttention(
        request: request,
        terminal: .fault(.transport("boundary jog cancelled without a typed intent"))
      )
    case .refused(let refusal):
      return finishBoundaryNeedsAttention(
        request: request,
        terminal: Self.boundaryTerminal(for: refusal)
      )
    case .ambiguous(let ambiguity):
      return finishBoundaryNeedsAttention(
        request: request,
        terminal: Self.boundaryTerminal(for: ambiguity)
      )
    }
  }

  public func requestDrawingStroke(
    _ request: DrawingStrokeRequest
  ) async -> DrawingStrokeOutcome {
    switch beginDrawingStroke(request) {
    case .admitted(let operation):
      return await operation.outcome()
    case .rejected(let outcome):
      return outcome
    }
  }

  public func beginDrawingStroke(
    _ request: DrawingStrokeRequest
  ) -> DrawingStrokeAdmission {
    guard currentOperation == .idle else {
      let outcome = DrawingStrokeOutcome.refused(.operationInFlight)
      lastDrawingStrokeOutcome = outcome
      return .rejected(outcome)
    }
    generation &+= 1
    currentOperation = .drawingStroke(request)
    let operationID = UUID()
    let task = Task { await self.runAdmittedDrawingStroke(request) }
    return .admitted(DrawingStrokeOperation(id: operationID, task: task))
  }

  private func runAdmittedDrawingStroke(
    _ request: DrawingStrokeRequest
  ) async -> DrawingStrokeOutcome {
    let outcome = await machineController.requestDrawingStroke(request)
    lastDrawingStrokeOutcome = outcome
    if case .drawingStroke = currentOperation { currentOperation = .idle }
    return outcome
  }

  /// Priority subordinate request for the active `$J` operation. It deliberately
  /// does not replace `currentOperation`; the original jog remains the only
  /// owner of controller replies and final Idle completion.
  public func requestJogCancel(
    _ intent: JogCancelIntent
  ) async -> JogCancelOutcome {
    if case .boundaryMotion(let request) = currentOperation,
      activeBoundaryMotion?.request.ownerID == request.ownerID
    {
      guard activeBoundaryMotion?.mechanicalCancelIntent == nil else {
        return .refused(.alreadyRequested)
      }
      activeBoundaryMotion?.mechanicalCancelIntent = intent
      let controller = machineController
      let task = Task { await controller.requestJogCancel() }
      activeBoundaryMotion?.cancelTask = task
      let outcome = await task.value
      if activeBoundaryMotion?.request.ownerID == request.ownerID {
        activeBoundaryMotion?.cancelOutcome = outcome
      }
      lastJogCancelOutcome = outcome
      return outcome
    }

    guard !jogCancelRequestInFlight else {
      return .refused(.alreadyRequested)
    }
    switch currentOperation {
    case .relativeJog, .drawingStroke:
      break
    case .boundaryMotion:
      return .refused(.noActiveJog)
    case .idle, .passiveProbe, .alarmClear, .penActuation:
      let outcome = await machineController.requestJogCancel()
      lastJogCancelOutcome = outcome
      return outcome
    }

    jogCancelRequestInFlight = true
    defer { jogCancelRequestInFlight = false }
    let outcome = await machineController.requestJogCancel()
    lastJogCancelOutcome = outcome
    return outcome
  }

  public func requestPenActuation(
    _ command: PenCommand,
    profile: PenActuationProfile
  ) async -> PenOutcome {
    guard currentOperation == .idle else {
      let outcome = PenOutcome.refused(.operationInFlight)
      lastPenOutcome = outcome
      return outcome
    }
    generation &+= 1
    currentOperation = .penActuation(command)
    let outcome = await machineController.requestPenActuation(command, profile: profile)
    lastPenOutcome = outcome
    currentOperation = .idle
    return outcome
  }

  public func disconnect() async {
    if let boundary = activeBoundaryMotion {
      if let cancelTask = boundary.cancelTask {
        _ = await cancelTask.value
      } else {
        _ = await requestJogCancel(.shutdown)
      }
      await waitForBoundaryCompletion(ownerID: boundary.request.ownerID)
    }
    generation &+= 1
    activeTransition = nil
    currentOperation = .idle
    await machineController.disconnect()
  }

  public func beginPassiveProbe() throws -> InterpreterTransitionToken {
    guard currentOperation == .idle, activeTransition == nil else {
      throw RunInterpreterError.transitionAlreadyInFlight
    }
    generation &+= 1
    let token = InterpreterTransitionToken(generation: generation)
    activeTransition = token
    currentOperation = .passiveProbe
    return token
  }

  public func completePassiveProbe(
    token: InterpreterTransitionToken,
    result: PassiveProbeResult
  ) throws {
    guard activeTransition == token, token.generation == generation else {
      throw RunInterpreterError.staleTransition
    }
    lastProbe = result
    activeTransition = nil
    currentOperation = .idle
  }

  public func invalidatePendingTransition() {
    generation &+= 1
    activeTransition = nil
    currentOperation = .idle
  }

  private func finishBoundarySettlement(
    request: BoundaryMotionRequest,
    segmentOutcome: MotionOutcome?
  ) async -> BoundaryMotionOutcome {
    guard let boundary = activeBoundaryMotion,
      boundary.request.ownerID == request.ownerID,
      let mechanicalCancelIntent = boundary.mechanicalCancelIntent
    else {
      return finishBoundaryNeedsAttention(
        request: request,
        terminal: .fault(.transport("boundary owner lost its typed disposition"))
      )
    }
    let cancelOutcome: JogCancelOutcome
    if let task = boundary.cancelTask {
      cancelOutcome = await task.value
    } else {
      cancelOutcome = boundary.cancelOutcome ?? .refused(.noActiveJog)
    }
    activeBoundaryMotion?.cancelOutcome = cancelOutcome

    switch BoundaryMechanicalSettlementPolicy.classify(
      segmentOutcome: segmentOutcome,
      cancelOutcome: cancelOutcome
    ) {
    case .settled(let settledPosition):
      let outcome = BoundaryMotionOutcome.settled(
        BoundaryMotionSettlement(
          ownerID: request.ownerID,
          mechanicalCancelIntent: mechanicalCancelIntent,
          completedSegmentCount: boundary.completedSegmentCount,
          finalPosition: settledPosition,
          jogCancelOutcome: cancelOutcome
        )
      )
      lastBoundaryMotionOutcome = outcome
      return outcome
    case .naturalHorizon(let finalPosition):
      let machine = await machineController.snapshot()
      if machine.pins.hasRelevantLimitAsserted {
        return finishBoundaryNeedsAttention(
          request: request,
          terminal: .limitAsserted(
            pins: machine.pins.rawValue,
            finalPosition: finalPosition
          )
        )
      }
      return finishBoundaryNeedsAttention(
        request: request,
        terminal: .fault(.transport(
          "boundary jog reached its finite horizon without an operator termination"
        ))
      )
    case .unattributable:
      break
    }
    switch cancelOutcome {
    case .ambiguous(let ambiguity):
      return finishBoundaryNeedsAttention(
        request: request,
        terminal: Self.boundaryTerminal(for: ambiguity)
      )
    case .refused(.notConnected):
      return finishBoundaryNeedsAttention(request: request, terminal: .disconnected)
    case .refused(.stickyAmbiguity(let ambiguity)):
      return finishBoundaryNeedsAttention(
        request: request,
        terminal: Self.boundaryTerminal(for: ambiguity)
      )
    case .refused(let refusal):
      return finishBoundaryNeedsAttention(
        request: request,
        terminal: .fault(.transport("Jog Cancel refused: \(refusal.actionableDescription)"))
      )
    case .transmitted, .completed:
      return finishBoundaryNeedsAttention(
        request: request,
        terminal: .fault(.transport("boundary settlement omitted final MPos"))
      )
    }
  }

  private func waitForBoundaryCompletion(ownerID: BoundaryMotionOwnerID) async {
    guard activeBoundaryMotion?.request.ownerID == ownerID else { return }
    await withCheckedContinuation { continuation in
      activeBoundaryMotion?.completionWaiters.append(continuation)
    }
  }

  private func finishBoundaryNeedsAttention(
    request: BoundaryMotionRequest,
    terminal: BoundaryMotionTerminal
  ) -> BoundaryMotionOutcome {
    let outcome = BoundaryMotionOutcome.needsAttention(
      ownerID: request.ownerID,
      terminal: terminal
    )
    lastBoundaryMotionOutcome = outcome
    return outcome
  }

  private static func boundaryTerminal(for refusal: MotionRefusal) -> BoundaryMotionTerminal {
    switch refusal {
    case .notConnected: .disconnected
    case .controllerAlarm(let detail): .alarm(detail)
    case .relevantLimitAsserted(let pins): .limitAsserted(pins: pins, finalPosition: nil)
    case .stickyAmbiguity(let ambiguity): boundaryTerminal(for: ambiguity)
    default: .refusal(refusal)
    }
  }

  private static func boundaryTerminal(
    for ambiguity: MotionAmbiguity
  ) -> BoundaryMotionTerminal {
    switch ambiguity {
    case .disconnected: .disconnected
    case .controllerAlarm(let detail): .alarm(detail)
    default: .fault(ambiguity)
    }
  }
}
