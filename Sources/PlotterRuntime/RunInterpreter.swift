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

public struct RuntimeProbeSnapshot: Sendable {
  public let generation: UInt64
  public let activeTransition: InterpreterTransitionToken?
  public let machine: MachineSnapshot
  public let lastProbe: PassiveProbeResult?

  public init(
    generation: UInt64,
    activeTransition: InterpreterTransitionToken?,
    machine: MachineSnapshot,
    lastProbe: PassiveProbeResult?
  ) {
    self.generation = generation
    self.activeTransition = activeTransition
    self.machine = machine
    self.lastProbe = lastProbe
  }
}

/// Serializes the current operation. It does not implement a phase, evidence,
/// replay, or execution-authority system.
public actor RunInterpreter {
  private let machineController: MachineController
  private var generation: UInt64 = 0
  private var activeTransition: InterpreterTransitionToken?
  private var lastProbe: PassiveProbeResult?

  public init(machineController: MachineController) {
    self.machineController = machineController
  }

  public func snapshot() async -> RuntimeProbeSnapshot {
    RuntimeProbeSnapshot(
      generation: generation,
      activeTransition: activeTransition,
      machine: await machineController.snapshot(),
      lastProbe: lastProbe
    )
  }

  public func requestPassiveProbe() async throws -> PassiveProbeResult {
    let token = try beginPassiveProbe()
    let result = await machineController.runPassiveProbe()
    try completePassiveProbe(token: token, result: result)
    return result
  }

  public func beginPassiveProbe() throws -> InterpreterTransitionToken {
    guard activeTransition == nil else { throw RunInterpreterError.transitionAlreadyInFlight }
    generation &+= 1
    let token = InterpreterTransitionToken(generation: generation)
    activeTransition = token
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
  }

  public func invalidatePendingTransition() {
    generation &+= 1
    activeTransition = nil
  }
}
