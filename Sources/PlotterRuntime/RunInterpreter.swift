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

public enum RunOperation: Codable, Hashable, Sendable {
  case idle
  case passiveProbe
  case relativeJog(RelativeJogRequest)
  case penActuation(PenCommand)
}

public struct RunInterpreterSnapshot: Codable, Hashable, Sendable {
  public let currentOperation: RunOperation
  public let machine: MachineSnapshot
  public let lastMotionOutcome: MotionOutcome?
  public let lastPenOutcome: PenOutcome?
  public let lastProbe: PassiveProbeResult?

  public init(
    currentOperation: RunOperation,
    machine: MachineSnapshot,
    lastMotionOutcome: MotionOutcome?,
    lastPenOutcome: PenOutcome? = nil,
    lastProbe: PassiveProbeResult?
  ) {
    self.currentOperation = currentOperation
    self.machine = machine
    self.lastMotionOutcome = lastMotionOutcome
    self.lastPenOutcome = lastPenOutcome
    self.lastProbe = lastProbe
  }
}

/// Serializes the current operator-requested operation. MachineController still
/// owns protocol encoding, safety validation, transport, and physical outcome.
public actor RunInterpreter {
  private let machineController: MachineController
  private var generation: UInt64 = 0
  private var activeTransition: InterpreterTransitionToken?
  private var currentOperation: RunOperation = .idle
  private var lastProbe: PassiveProbeResult?
  private var lastMotionOutcome: MotionOutcome?
  private var lastPenOutcome: PenOutcome?

  public init(machineController: MachineController) {
    self.machineController = machineController
  }

  public func snapshot() async -> RunInterpreterSnapshot {
    RunInterpreterSnapshot(
      currentOperation: currentOperation,
      machine: await machineController.snapshot(),
      lastMotionOutcome: lastMotionOutcome,
      lastPenOutcome: lastPenOutcome,
      lastProbe: lastProbe
    )
  }

  public func requestPassiveProbe() async throws -> PassiveProbeResult {
    let token = try beginPassiveProbe()
    let result = await machineController.runPassiveProbe()
    try completePassiveProbe(token: token, result: result)
    return result
  }

  public func updateMotionLimits(_ limits: MotionLimits) async {
    await machineController.updateMotionLimits(limits)
  }

  public func requestRelativeJog(_ request: RelativeJogRequest) async -> MotionOutcome {
    guard currentOperation == .idle else {
      let outcome = MotionOutcome.refused(.operationInFlight)
      lastMotionOutcome = outcome
      return outcome
    }
    generation &+= 1
    currentOperation = .relativeJog(request)
    let outcome = await machineController.requestRelativeJog(request)
    lastMotionOutcome = outcome
    currentOperation = .idle
    return outcome
  }

  public func requestPenActuation(_ command: PenCommand) async -> PenOutcome {
    guard currentOperation == .idle else {
      let outcome = PenOutcome.refused(.operationInFlight)
      lastPenOutcome = outcome
      return outcome
    }
    generation &+= 1
    currentOperation = .penActuation(command)
    let outcome = await machineController.requestPenActuation(command)
    lastPenOutcome = outcome
    currentOperation = .idle
    return outcome
  }

  public func disconnect() async {
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
}
