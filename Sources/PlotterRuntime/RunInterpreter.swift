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

public enum RunOperation: Hashable, Sendable {
  case idle
  case passiveProbe
  case relativeJog(RelativeJogRequest)
  case observedJog(PhysicalJogObservationRequest)
  case penActuation(PenCommand)
}

public struct RunInterpreterSnapshot: Hashable, Sendable {
  public let currentOperation: RunOperation
  public let machine: MachineSnapshot
  public let lastMotionOutcome: MotionOutcome?
  public let lastPhysicalJogObservationOutcome: PhysicalJogObservationOutcome?
  public let lastPenOutcome: PenOutcome?
  public let lastProbe: PassiveProbeResult?
  public let jogCancellationInFlight: Bool
  public let lastJogCancelOutcome: JogCancelOutcome?

  public init(
    currentOperation: RunOperation,
    machine: MachineSnapshot,
    lastMotionOutcome: MotionOutcome?,
    lastPhysicalJogObservationOutcome: PhysicalJogObservationOutcome? = nil,
    lastPenOutcome: PenOutcome? = nil,
    lastProbe: PassiveProbeResult?,
    jogCancellationInFlight: Bool = false,
    lastJogCancelOutcome: JogCancelOutcome? = nil
  ) {
    self.currentOperation = currentOperation
    self.machine = machine
    self.lastMotionOutcome = lastMotionOutcome
    self.lastPhysicalJogObservationOutcome = lastPhysicalJogObservationOutcome
    self.lastPenOutcome = lastPenOutcome
    self.lastProbe = lastProbe
    self.jogCancellationInFlight = jogCancellationInFlight
    self.lastJogCancelOutcome = lastJogCancelOutcome
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
  private var lastPhysicalJogObservationOutcome: PhysicalJogObservationOutcome?
  private var lastPenOutcome: PenOutcome?
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
      lastPhysicalJogObservationOutcome: lastPhysicalJogObservationOutcome,
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

  public func activateMotionGuard() async -> MotionGuardActivationOutcome {
    await machineController.activateMotionGuard()
  }

  public func deactivateMotionGuard() async {
    await machineController.deactivateMotionGuard()
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

  /// Priority subordinate request for the active `$J` operation. It deliberately
  /// does not replace `currentOperation`; the original jog remains the only
  /// owner of controller replies and final Idle completion.
  public func requestJogCancel() async -> JogCancelOutcome {
    guard !jogCancelRequestInFlight else {
      return .refused(.alreadyRequested)
    }
    switch currentOperation {
    case .relativeJog, .observedJog:
      break
    case .idle, .passiveProbe, .penActuation:
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

  /// Captures exact visible-tool evidence around one controller-owned jog.
  ///
  /// The observation provider owns camera selection and vision analysis. This
  /// method only serializes the before/move/after ordering. A camera failure is
  /// diagnostic evidence failure, never machine ambiguity, and a transmitted
  /// motion is never resent or inverted here.
  public func requestObservedJog(
    _ request: PhysicalJogObservationRequest,
    observe: @Sendable (
      _ phase: PhysicalObservationPhase,
      _ newerThanNanoseconds: UInt64
    ) async -> Result<VisibleToolFrameObservation, PhysicalJogObservationFailure>
  ) async -> PhysicalJogObservationOutcome {
    guard currentOperation == .idle else {
      let motionOutcome = MotionOutcome.refused(.operationInFlight)
      return .notRecorded(
        motionOutcome: motionOutcome,
        failure: .motionNotCompleted(motionOutcome)
      )
    }

    generation &+= 1
    currentOperation = .observedJog(request)
    defer { currentOperation = .idle }

    let before: VisibleToolFrameObservation
    switch await observe(.beforeMotion, 0) {
    case .success(let observation):
      before = observation
    case .failure(let failure):
      let outcome = PhysicalJogObservationOutcome.notRecorded(
        motionOutcome: nil,
        failure: failure
      )
      lastPhysicalJogObservationOutcome = outcome
      return outcome
    }

    let execution = await machineController.requestRelativeJogWithEvidence(request.motion)
    let motionOutcome = execution.outcome
    lastMotionOutcome = motionOutcome

    guard case .acceptedThenCompleted(let finalPosition) = motionOutcome else {
      let outcome = PhysicalJogObservationOutcome.notRecorded(
        motionOutcome: motionOutcome,
        failure: .motionNotCompleted(motionOutcome)
      )
      lastPhysicalJogObservationOutcome = outcome
      return outcome
    }
    guard let controllerEvidence = execution.completedEvidence,
      controllerEvidence.request == request.motion,
      controllerEvidence.finalPosition == finalPosition
    else {
      let outcome = PhysicalJogObservationOutcome.notRecorded(
        motionOutcome: motionOutcome,
        failure: .controllerMotionEvidenceUnavailable
      )
      lastPhysicalJogObservationOutcome = outcome
      return outcome
    }

    let after: VisibleToolFrameObservation
    switch await observe(.afterMotion, controllerEvidence.finalSampleNanoseconds) {
    case .success(let observation):
      after = observation
    case .failure(let failure):
      let outcome = PhysicalJogObservationOutcome.notRecorded(
        motionOutcome: motionOutcome,
        failure: failure
      )
      lastPhysicalJogObservationOutcome = outcome
      return outcome
    }

    let outcome = PhysicalJogObservationOutcome.resolve(
      motionOutcome: motionOutcome,
      observation: try PhysicalJogObservation(
        observationID: UUID().uuidString,
        request: request,
        startPosition: controllerEvidence.startPosition,
        startControllerSampleNanoseconds: controllerEvidence.startSampleNanoseconds,
        finalPosition: controllerEvidence.finalPosition,
        finalControllerSampleNanoseconds: controllerEvidence.finalSampleNanoseconds,
        before: before,
        after: after
      )
    )
    lastPhysicalJogObservationOutcome = outcome
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
