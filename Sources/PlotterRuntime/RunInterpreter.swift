import Foundation
import PlotterModel

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

public enum AuthorityTransitionReason: String, Codable, Hashable, Sendable {
  case passiveProbeCompleted
  case recordedCommandReconciliation
}

public struct AuthorityTransitionRecord: Codable, Hashable, Sendable {
  public let reason: AuthorityTransitionReason
  public let generation: UInt64
  public let transitionToken: InterpreterTransitionToken?
  public let priorAuthority: ExecutionAuthority
  public let resultingAuthority: ExecutionAuthority
  public let unresolvedCommandIDs: [UUID]
  public let machineBlockers: [MachineBlocker]

  public init(
    reason: AuthorityTransitionReason,
    generation: UInt64,
    transitionToken: InterpreterTransitionToken?,
    priorAuthority: ExecutionAuthority,
    resultingAuthority: ExecutionAuthority,
    unresolvedCommandIDs: [UUID],
    machineBlockers: [MachineBlocker]
  ) {
    self.reason = reason
    self.generation = generation
    self.transitionToken = transitionToken
    self.priorAuthority = priorAuthority
    self.resultingAuthority = resultingAuthority
    self.unresolvedCommandIDs = unresolvedCommandIDs
    self.machineBlockers = machineBlockers
  }
}

public struct RuntimeAuthoritySnapshot: Codable, Hashable, Sendable {
  public let generation: UInt64
  public let authority: ExecutionAuthority
  public let activeTransition: InterpreterTransitionToken?
  public let machine: MachineSnapshot
  public let unresolvedCommandIntents: [UnresolvedCommandIntent]

  public init(
    generation: UInt64,
    authority: ExecutionAuthority,
    activeTransition: InterpreterTransitionToken?,
    machine: MachineSnapshot,
    unresolvedCommandIntents: [UnresolvedCommandIntent]
  ) {
    self.generation = generation
    self.authority = authority
    self.activeTransition = activeTransition
    self.machine = machine
    self.unresolvedCommandIntents = unresolvedCommandIntents
  }
}

public actor RunInterpreter {
  private let machineController: MachineController
  private let ledger: RunLedger
  private let runID: LedgerRunID
  private var authority: ExecutionAuthority
  private var generation: UInt64 = 0
  private var activeTransition: InterpreterTransitionToken?
  private var unresolved: [UnresolvedCommandIntent] = []

  public init(
    machineController: MachineController,
    ledger: RunLedger,
    runID: LedgerRunID,
    initialAuthority: ExecutionAuthority
  ) {
    self.machineController = machineController
    self.ledger = ledger
    self.runID = runID
    authority = initialAuthority
  }

  public func snapshot() async -> RuntimeAuthoritySnapshot {
    RuntimeAuthoritySnapshot(
      generation: generation,
      authority: authority,
      activeTransition: activeTransition,
      machine: await machineController.snapshot(),
      unresolvedCommandIntents: unresolved
    )
  }

  public func requestPassiveProbe() async throws -> PassiveProbeResult {
    let token = try beginPassiveProbe()
    let result = await machineController.runPassiveProbe()
    try await completePassiveProbe(token: token, result: result)
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
  ) async throws {
    guard activeTransition == token, token.generation == generation else {
      throw RunInterpreterError.staleTransition
    }
    let priorAuthority = authority
    unresolved = try await ledger.unresolvedCommandIntents(runID: runID)
    var nextBlockers = try result.blockers.map {
      try RunBlocker(code: "machine.passive_probe", summary: String(describing: $0))
    }
    if !unresolved.isEmpty {
      nextBlockers.append(
        try RunBlocker(
          code: "machine.command_outcome_ambiguous",
          summary:
            "Recorded command intent remains unresolved after passive controller interrogation."
        )
      )
    }
    let nextAuthority: ExecutionAuthority
    if nextBlockers.isEmpty {
      nextAuthority = try ExecutionAuthority(
        allowed: true,
        operation: .passiveInterrogation,
        planID: nil,
        modelID: nil,
        stateEstimateID: nil,
        fixedSafetyPolicyID: authority.fixedSafetyPolicyID,
        evidence: authority.evidence,
        limits: authority.limits,
        blockers: []
      )
    } else {
      nextAuthority = try blockedAuthority(nextBlockers)
    }
    try await recordAuthorityTransition(
      AuthorityTransitionRecord(
        reason: .passiveProbeCompleted,
        generation: generation,
        transitionToken: token,
        priorAuthority: priorAuthority,
        resultingAuthority: nextAuthority,
        unresolvedCommandIDs: unresolved.map(\.commandID),
        machineBlockers: result.blockers
      )
    )
    authority = nextAuthority
    activeTransition = nil
  }

  public func invalidatePendingTransition() {
    generation &+= 1
    activeTransition = nil
  }

  /// Prepared, written, and already-ambiguous commands all require physical
  /// reconciliation after reopen. None is interpreted as unsent work.
  public func reconcileRecordedCommandIntents() async throws {
    unresolved = try await ledger.unresolvedCommandIntents(runID: runID)
    guard !unresolved.isEmpty else { return }
    let priorAuthority = authority
    let nextAuthority = try blockedAuthority([
      RunBlocker(
        code: "machine.command_outcome_ambiguous",
        summary:
          "Recorded command intent requires passive controller reconciliation and inspection."
      )
    ])
    try await recordAuthorityTransition(
      AuthorityTransitionRecord(
        reason: .recordedCommandReconciliation,
        generation: generation,
        transitionToken: activeTransition,
        priorAuthority: priorAuthority,
        resultingAuthority: nextAuthority,
        unresolvedCommandIDs: unresolved.map(\.commandID),
        machineBlockers: []
      )
    )
    authority = nextAuthority
  }

  public func recordedReplay(_ events: [SequencedRunEvent]) throws -> RecordedRunState {
    try RecordedRunReducer.replay(events)
  }

  private func blockedAuthority(_ blockers: [RunBlocker]) throws -> ExecutionAuthority {
    try ExecutionAuthority(
      allowed: false,
      operation: nil,
      planID: authority.planID,
      modelID: authority.modelID,
      stateEstimateID: authority.stateEstimateID,
      fixedSafetyPolicyID: authority.fixedSafetyPolicyID,
      evidence: authority.evidence,
      limits: authority.limits,
      blockers: blockers
    )
  }

  private func recordAuthorityTransition(_ record: AuthorityTransitionRecord) async throws {
    try await ledger.appendEvent(
      runID: runID,
      timestamp: RuntimeTimestamp(monotonicNanoseconds: DispatchTime.now().uptimeNanoseconds),
      kind: "runtime.authority.transition",
      schemaVersion: 1,
      payload: try JSONEncoder().encode(record)
    )
  }
}
