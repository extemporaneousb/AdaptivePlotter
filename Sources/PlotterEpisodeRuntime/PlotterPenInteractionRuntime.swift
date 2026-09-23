import Foundation
import PlotterEpisodeModel
import PlotterRuntime

public struct PlotterPenInteractionActuationRequest: Hashable, Sendable {
  public let operationID: PlotterPenInteractionOperationID
  public let environment: PlotterEnvironment
  public let command: PenCommand
  public let profile: PenActuationProfile

  public init(
    operationID: PlotterPenInteractionOperationID,
    environment: PlotterEnvironment,
    command: PenCommand,
    profile: PenActuationProfile
  ) {
    self.operationID = operationID
    self.environment = environment
    self.command = command
    self.profile = profile
  }
}

/// Exact retained-owner result. Controller settlement proves only the command
/// transcript; the optional MPos and simulator truth remain distinct facts and
/// never become physical Pen or ink evidence.
public struct PlotterPenInteractionActuationSettlement: Sendable {
  public let operationID: PlotterPenInteractionOperationID
  public let outcome: PenOutcome
  public let machineSnapshot: RunInterpreterSnapshot?
  public let simulatedTruth: PlotterCausalSimulatorTruthSnapshot?
  public let observedPosition: MachinePosition?
  public let timestamp: RuntimeTimestamp

  public init(
    operationID: PlotterPenInteractionOperationID,
    outcome: PenOutcome,
    machineSnapshot: RunInterpreterSnapshot?,
    simulatedTruth: PlotterCausalSimulatorTruthSnapshot?,
    observedPosition: MachinePosition?,
    timestamp: RuntimeTimestamp
  ) {
    self.operationID = operationID
    self.outcome = outcome
    self.machineSnapshot = machineSnapshot
    self.simulatedTruth = simulatedTruth
    self.observedPosition = observedPosition
    self.timestamp = timestamp
  }
}

public protocol PlotterPenInteractionActuationPort: Sendable {
  func settle(
    _ request: PlotterPenInteractionActuationRequest
  ) async -> PlotterPenInteractionActuationSettlement
}

/// Deterministic scheduling seam. It can delay only publication after the
/// retained lower port has returned; it cannot choose admission, effects,
/// cancellation, evidence, or terminal disposition.
package actor PlotterPenInteractionTerminalPublicationGate {
  private var armed = false
  private var held = false
  private var heldWaiters: [CheckedContinuation<Void, Never>] = []
  private var releaseWaiter: CheckedContinuation<Void, Never>?

  package init() {}

  package func holdNextPublication() { armed = true }

  package func waitUntilHeld() async {
    if held { return }
    await withCheckedContinuation { heldWaiters.append($0) }
  }

  package func release() {
    armed = false
    held = false
    releaseWaiter?.resume()
    releaseWaiter = nil
  }

  fileprivate func pauseIfArmed() async {
    guard armed else { return }
    armed = false
    held = true
    let waiters = heldWaiters
    heldWaiters = []
    waiters.forEach { $0.resume() }
    await withCheckedContinuation { releaseWaiter = $0 }
    held = false
  }
}

/// Deterministic scheduling seam for latest-only setpoint evidence. It can
/// pause only after a setpoint has passed normal semantic admission and
/// replaced the runtime-owned pending value, but before that submission joins
/// or drives the existing drain. Releasing it cannot dispatch or settle an
/// effect; only the runtime can advance the drain.
package actor PlotterPenInteractionSetpointAdmissionGate {
  private var armed = false
  private var held = false
  private var admissionCount = 0
  private var heldWaiters: [CheckedContinuation<Void, Never>] = []
  private var admissionCountWaiters: [(Int, CheckedContinuation<Void, Never>)] = []
  private var releaseWaiter: CheckedContinuation<Void, Never>?

  package init() {}

  package var isHeld: Bool { held }
  package var admittedSetpointCount: Int { admissionCount }

  package func holdNextAdmittedSetpoint() { armed = true }

  package func waitUntilHeld() async {
    if held { return }
    await withCheckedContinuation { heldWaiters.append($0) }
  }

  package func waitUntilAdmissionCount(_ expectedCount: Int) async {
    precondition(expectedCount > 0)
    if admissionCount >= expectedCount { return }
    await withCheckedContinuation {
      admissionCountWaiters.append((expectedCount, $0))
    }
  }

  package func release() {
    armed = false
    held = false
    releaseWaiter?.resume()
    releaseWaiter = nil
  }

  fileprivate func pauseAfterAdmissionIfArmed() async {
    admissionCount += 1
    let readyAdmissionWaiters = admissionCountWaiters.filter { $0.0 <= admissionCount }
    admissionCountWaiters.removeAll { $0.0 <= admissionCount }
    readyAdmissionWaiters.forEach { $0.1.resume() }
    guard armed else { return }
    armed = false
    held = true
    let waiters = heldWaiters
    heldWaiters = []
    waiters.forEach { $0.resume() }
    await withCheckedContinuation { releaseWaiter = $0 }
    held = false
  }
}

/// Deterministic seam that can hold a Confirm request only after the runtime
/// has published its new non-confirmable revision. It owns no production state.
package actor PlotterPenInteractionConfirmationAdmissionGate {
  private var held = false
  private var heldWaiters: [CheckedContinuation<Void, Never>] = []
  private var releaseWaiter: CheckedContinuation<Void, Never>?

  package init() {}

  package var isHeld: Bool { held }

  package func waitUntilHeld() async {
    if held { return }
    await withCheckedContinuation { heldWaiters.append($0) }
  }

  package func release() {
    held = false
    releaseWaiter?.resume()
    releaseWaiter = nil
  }

  fileprivate func pauseAfterPublication() async {
    held = true
    let waiters = heldWaiters
    heldWaiters = []
    waiters.forEach { $0.resume() }
    await withCheckedContinuation { releaseWaiter = $0 }
  }
}

public struct PlotterPenInteractionExecutionEvidence: Hashable, Sendable {
  public let command: PenCommand
  public let profile: PenActuationProfile
  public let outcome: PenOutcome
  public let position: MachinePosition?
  public let timestamp: RuntimeTimestamp

  public init(
    command: PenCommand,
    profile: PenActuationProfile,
    outcome: PenOutcome,
    position: MachinePosition?,
    timestamp: RuntimeTimestamp
  ) {
    self.command = command
    self.profile = profile
    self.outcome = outcome
    self.position = position
    self.timestamp = timestamp
  }
}

public struct PlotterPenInteractionRuntimeSnapshot: Sendable {
  public let projection: PlotterPenInteractionProjection
  public let profile: PenActuationProfile
  public let acceptedHistory: ExerciseAttemptHistory<PenInteractionAttemptEvidence>
  public let acceptedSequence: UInt64
  public let activeAttemptID: ExerciseAttemptID?
  public let activeAttemptMode: PlotterPenInteractionAttemptMode?
  public let lastExecutionByCommand: [PenCommand: PlotterPenInteractionExecutionEvidence]
  public let lastSettlement: PlotterPenInteractionActuationSettlement?

  public init(
    projection: PlotterPenInteractionProjection,
    profile: PenActuationProfile,
    acceptedHistory: ExerciseAttemptHistory<PenInteractionAttemptEvidence>,
    acceptedSequence: UInt64,
    activeAttemptID: ExerciseAttemptID?,
    activeAttemptMode: PlotterPenInteractionAttemptMode?,
    lastExecutionByCommand: [PenCommand: PlotterPenInteractionExecutionEvidence],
    lastSettlement: PlotterPenInteractionActuationSettlement?
  ) {
    self.projection = projection
    self.profile = profile
    self.acceptedHistory = acceptedHistory
    self.acceptedSequence = acceptedSequence
    self.activeAttemptID = activeAttemptID
    self.activeAttemptMode = activeAttemptMode
    self.lastExecutionByCommand = lastExecutionByCommand
    self.lastSettlement = lastSettlement
  }
}

/// Projection-only publication boundary. The runtime remains the sole owner of
/// admission, lower execution, cancellation, and settlement; the receiver can
/// only install the immutable snapshot that the runtime has already published.
@MainActor
public protocol PlotterPenInteractionProjectionSink: AnyObject, Sendable {
  func publishPenInteractionSnapshot(_ snapshot: PlotterPenInteractionRuntimeSnapshot)
}

/// Sole EA-10A semantic owner. It serializes admission, owns the exact lower
/// actuation task and publishes accepted operator observations only after that
/// task has settled. Cancellation latches before awaiting an in-flight lower
/// call; it never treats Task cancellation as proof that a physical command did
/// not reach the controller.
public actor PlotterPenInteractionRuntime {
  private struct PendingEvidence: Sendable {
    var upPositions: [MachinePosition?] = []
    var upValues: [Int] = []
    var upOutcomes: [PenOutcome?] = []
    var upTimestamps: [RuntimeTimestamp] = []
    var downPositions: [MachinePosition?] = []
    var downValues: [Int] = []
    var downOutcomes: [PenOutcome?] = []
    var downTimestamps: [RuntimeTimestamp] = []
  }

  private struct State: Sendable {
    var revision: UInt64 = 0
    var phase: PlotterPenInteractionPhase = .idle
    var operationID: PlotterPenInteractionOperationID?
    var cancellationID: PlotterPenInteractionCancellationCapabilityID?
    var profile = PenActuationProfile.initialDefaults
    var draft: PenActuationProfile?
    var history: ExerciseAttemptHistory<PenInteractionAttemptEvidence>
    var acceptedSequence: UInt64 = 0
    var attemptID: ExerciseAttemptID?
    var attemptMode: PlotterPenInteractionAttemptMode?
    var lastExecution: [PenCommand: PlotterPenInteractionExecutionEvidence] = [:]
    var pending = PendingEvidence()
    var lastSettlement: PlotterPenInteractionActuationSettlement?
    var lastRefusal: PlotterPenInteractionRefusal?
    var cancellationRequested = false
    var closed = false

    init(environment: PlotterEnvironment) {
      history = try! ExerciseAttemptHistory(
        compatibility: AttemptCompatibility(
          cameraConfigurationID: nil,
          coordinateSpace: .currentState,
          units: .state,
          group: AttemptGroupIdentity(
            rawValue: environment == .simulated
              ? "simulated-pen-interaction" : "pen-interaction"
          ),
          algorithmRevision: environment == .simulated
            ? "simulated-typed-operator-pen-observation-v1"
            : "typed-operator-pen-observation-v1"
        )
      )
    }
  }

  private let port: any PlotterPenInteractionActuationPort
  private let terminalPublicationGate: PlotterPenInteractionTerminalPublicationGate?
  private let setpointAdmissionGate: PlotterPenInteractionSetpointAdmissionGate?
  private let confirmationAdmissionGate: PlotterPenInteractionConfirmationAdmissionGate?
  private var states: [PlotterEnvironment: State]
  private var activeEnvironment: PlotterEnvironment?
  private var actuationTask: Task<PlotterPenInteractionActuationSettlement, Never>?
  private var actuationToken: UUID?
  private var terminalPublicationInProgress = false
  private var terminalPublicationWaiters: [CheckedContinuation<Void, Never>] = []
  private var pendingSetpointCommand: PlotterPenInteractionCommand?
  private var setpointDrainInProgress = false
  private var setpointDrainWaiters: [CheckedContinuation<Void, Never>] = []
  private weak var projectionSink: (any PlotterPenInteractionProjectionSink)?
  private var projectionPublicationInProgress = false
  private var projectionPublicationWaiters: [CheckedContinuation<Void, Never>] = []

  public init(port: any PlotterPenInteractionActuationPort) {
    self.port = port
    terminalPublicationGate = nil
    setpointAdmissionGate = nil
    confirmationAdmissionGate = nil
    states = [.live: State(environment: .live), .simulated: State(environment: .simulated)]
  }

  package init(
    port: any PlotterPenInteractionActuationPort,
    terminalPublicationGate: PlotterPenInteractionTerminalPublicationGate
  ) {
    self.port = port
    self.terminalPublicationGate = terminalPublicationGate
    setpointAdmissionGate = nil
    confirmationAdmissionGate = nil
    states = [.live: State(environment: .live), .simulated: State(environment: .simulated)]
  }

  package init(
    port: any PlotterPenInteractionActuationPort,
    setpointAdmissionGate: PlotterPenInteractionSetpointAdmissionGate
  ) {
    self.port = port
    terminalPublicationGate = nil
    self.setpointAdmissionGate = setpointAdmissionGate
    confirmationAdmissionGate = nil
    states = [.live: State(environment: .live), .simulated: State(environment: .simulated)]
  }

  package init(
    port: any PlotterPenInteractionActuationPort,
    terminalPublicationGate: PlotterPenInteractionTerminalPublicationGate,
    setpointAdmissionGate: PlotterPenInteractionSetpointAdmissionGate
  ) {
    self.port = port
    self.terminalPublicationGate = terminalPublicationGate
    self.setpointAdmissionGate = setpointAdmissionGate
    confirmationAdmissionGate = nil
    states = [.live: State(environment: .live), .simulated: State(environment: .simulated)]
  }

  package init(
    port: any PlotterPenInteractionActuationPort,
    confirmationAdmissionGate: PlotterPenInteractionConfirmationAdmissionGate
  ) {
    self.port = port
    terminalPublicationGate = nil
    setpointAdmissionGate = nil
    self.confirmationAdmissionGate = confirmationAdmissionGate
    states = [.live: State(environment: .live), .simulated: State(environment: .simulated)]
  }

  public func snapshot(
    environment: PlotterEnvironment
  ) -> PlotterPenInteractionRuntimeSnapshot {
    makeSnapshot(environment: environment)
  }

  /// Installs one projection-only receiver. Reinstalling the same receiver is
  /// inert. Publication is serialized with semantic admission, so an exact UI
  /// revision can never observe a state older than the runtime revision that
  /// produced it.
  public func installProjectionSink(
    _ sink: any PlotterPenInteractionProjectionSink
  ) async {
    if let projectionSink, projectionSink === sink { return }
    await awaitProjectionPublication()
    projectionSink = sink
    for environment in PlotterEnvironment.allCases {
      await publishProjection(environment: environment)
    }
  }

  public func submit(
    _ submission: PlotterPenInteractionSubmission
  ) async -> PlotterPenInteractionDisposition {
    await awaitProjectionPublication()
    let environment = submission.facts.environment
    guard submission.projection.environment == environment else {
      return refuse(submission, .environmentChanged, .useCurrentProjection, environment)
    }
    guard submission.projection == reference(environment: environment) else {
      return refuse(submission, .staleProjection, .useCurrentProjection, environment)
    }
    guard states[environment]?.closed == false else {
      return refuse(submission, .admissionClosed, .restartApplication, environment)
    }

    switch submission.intent {
    case .start(let mode, let rawAttemptID):
      guard submission.facts.learningEnabled else {
        return refuse(submission, .learningDisabled, .enableLearning, environment)
      }
      guard activeEnvironment == nil else {
        return refuse(
          submission, .interactionAlreadyActive, .finishOrCancelCurrentInteraction, environment)
      }
      guard submission.facts.capSelectionAvailable else {
        return refuse(submission, .capSelectionUnavailable, .completeExactCapSelection, environment)
      }
      var state = states[environment]!
      state.operationID = PlotterPenInteractionOperationID()
      state.cancellationID = PlotterPenInteractionCancellationCapabilityID()
      state.attemptID = ExerciseAttemptID(rawValue: rawAttemptID)
      state.attemptMode = mode
      state.draft = state.profile
      state.pending = PendingEvidence()
      state.lastExecution = [:]
      state.lastSettlement = nil
      state.cancellationRequested = false
      state.lastRefusal = nil
      state.phase = .awaitingCapSelection
      advance(&state)
      states[environment] = state
      activeEnvironment = environment
      await publishProjection(environment: environment)

    case .capSelectionAccepted:
      guard activeEnvironment == environment,
        states[environment]?.phase == .awaitingCapSelection
      else {
        return refuse(submission, .capSelectionRequired, .completeExactCapSelection, environment)
      }
      mutate(environment) {
        $0.lastRefusal = nil
        $0.phase = .awaitingConfirmation(.raise)
        advance(&$0)
      }
      await publishProjection(environment: environment)

    case .setpoint(let command, let value):
      guard (0...1000).contains(value) else {
        return refuse(submission, .setpointOutOfRange(value), .choosePublishedSetpointRange, environment)
      }
      guard acceptsSetpoint(command, environment: environment) else {
        return refuse(submission, .commandNotExpected, .useCurrentPrompt, environment)
      }
      if let refusal = effectRefusal(submission.facts) {
        return refuse(submission, refusal.0, refusal.1, environment)
      }
      let startsDrain = !setpointDrainInProgress
      if startsDrain {
        setpointDrainInProgress = true
      }
      mutate(environment) {
        let profile = $0.draft ?? $0.profile
        $0.draft = profile.replacingValue(for: command.runtimeCommand, with: value)
        $0.lastRefusal = nil
        $0.phase = .drainingSetpoint(command)
        advance(&$0)
      }
      pendingSetpointCommand = command
      // Claim the one drain and publish a non-confirmable exact revision before
      // the projection sink, deterministic seam, or retained lower port can
      // suspend this submission.
      await publishProjection(environment: environment)
      await setpointAdmissionGate?.pauseAfterAdmissionIfArmed()
      if startsDrain {
        while let pending = pendingSetpointCommand {
          pendingSetpointCommand = nil
          await settle(pending, environment: environment)
        }
        finishSetpointDrain()
      } else {
        await waitForSetpointDrain()
      }

    case .actuate(let command):
      guard states[environment]?.phase == .awaitingControllerCommand(command) else {
        return refuse(submission, .commandNotExpected, .useCurrentPrompt, environment)
      }
      if let refusal = effectRefusal(submission.facts) {
        return refuse(submission, refusal.0, refusal.1, environment)
      }
      mutate(environment) {
        $0.lastRefusal = nil
        advance(&$0)
      }
      await settle(command, environment: environment)

    case .confirm(let command):
      guard isExpectedConfirmation(command, environment: environment) else {
        return refuse(submission, .commandNotExpected, .useCurrentPrompt, environment)
      }
      // Confirmation is an operator fact, not a reason to leave the old green
      // action live while unrelated drains or publications settle. Publish a
      // new non-confirmable revision before the first suspension.
      mutate(environment) {
        $0.lastRefusal = nil
        $0.phase = .confirming(command)
        advance(&$0)
      }
      await publishProjection(environment: environment)
      await confirmationAdmissionGate?.pauseAfterPublication()
      await waitForSetpointDrain()
      if let task = actuationTask { _ = await task.value }
      await awaitTerminalPublication()
      guard activeEnvironment == environment,
        states[environment]?.phase == .confirming(command)
      else {
        return .superseded(makeSnapshot(environment: environment).projection)
      }
      recordConfirmation(command, environment: environment)
      await publishProjection(environment: environment)

    case .abortAndRaise(let capability):
      guard activeEnvironment == environment,
        states[environment]?.cancellationID == capability
      else {
        return refuse(
          submission, .cancellationCapabilityMismatch,
          .useExactCancellationCapability, environment
        )
      }
      if let refusal = effectRefusal(submission.facts) {
        return refuse(submission, refusal.0, refusal.1, environment)
      }
      mutate(environment) {
        $0.cancellationRequested = true
        $0.phase = .cancelling
        advance(&$0)
      }
      await publishProjection(environment: environment)
      pendingSetpointCommand = nil
      await waitForSetpointDrain()
      await settle(.raise, environment: environment)
      await awaitTerminalPublication()
      recordTerminal(.cancelled, environment: environment)
      await publishProjection(environment: environment)

    case .finish(let disposition):
      guard activeEnvironment == environment else {
        return refuse(submission, .interactionNotActive, .useCurrentProjection, environment)
      }
      pendingSetpointCommand = nil
      await waitForSetpointDrain()
      if let task = actuationTask { _ = await task.value }
      await awaitTerminalPublication()
      recordTerminal(disposition, environment: environment)
      await publishProjection(environment: environment)

    case .cancel(let capability), .stop(let capability):
      guard activeEnvironment == environment,
        states[environment]?.cancellationID == capability
      else {
        return refuse(
          submission, .cancellationCapabilityMismatch,
          .useExactCancellationCapability, environment
        )
      }
      mutate(environment) {
        $0.cancellationRequested = true
        $0.phase = .cancelling
        advance(&$0)
      }
      await publishProjection(environment: environment)
      pendingSetpointCommand = nil
      await waitForSetpointDrain()
      if let task = actuationTask { _ = await task.value }
      await awaitTerminalPublication()
      recordTerminal(.cancelled, environment: environment)
      await publishProjection(environment: environment)

    case .reset:
      guard activeEnvironment == nil else {
        return refuse(
          submission, .interactionAlreadyActive, .finishOrCancelCurrentInteraction, environment)
      }
      let closed = states[environment]?.closed ?? false
      states[environment] = State(environment: environment)
      states[environment]?.closed = closed
      await publishProjection(environment: environment)
    }
    return .applied(makeSnapshot(environment: environment).projection)
  }

  public func restore(
    _ checkpoint: AcceptedPenInteractionCheckpoint?,
    environment: PlotterEnvironment
  ) {
    guard activeEnvironment == nil else { return }
    var state = State(environment: environment)
    guard let checkpoint else {
      states[environment] = state
      return
    }
    var history = state.history
    let attempt = try! ExerciseAttempt(
      id: checkpoint.revision.attemptID,
      disposition: .succeeded,
      compatibility: history.compatibility,
      acceptedSequence: checkpoint.acceptedSequence,
      value: checkpoint.evidence
    )
    try! history.record(attempt)
    state.history = history
    state.profile = checkpoint.evidence.actuationProfile
    state.acceptedSequence = checkpoint.acceptedSequence
    state.revision = 1
    states[environment] = state
  }

  public func shutdown() async {
    for environment in PlotterEnvironment.allCases {
      mutate(environment) { state in
        state.closed = true
        if state.operationID != nil {
          state.cancellationRequested = true
          state.phase = .cancelling
          advance(&state)
        }
      }
    }
    for environment in PlotterEnvironment.allCases {
      await publishProjection(environment: environment)
    }
    pendingSetpointCommand = nil
    await waitForSetpointDrain()
    if let task = actuationTask { _ = await task.value }
    await awaitTerminalPublication()
    if let environment = activeEnvironment {
      recordTerminal(.cancelled, environment: environment)
      await publishProjection(environment: environment)
    }
    projectionSink = nil
  }

  private func settle(
    _ command: PlotterPenInteractionCommand,
    environment: PlotterEnvironment
  ) async {
    guard let operationID = states[environment]?.operationID else { return }
    let profile = states[environment]?.draft ?? states[environment]!.profile
    mutate(environment) {
      $0.phase = .settling(command)
      advance(&$0)
    }
    await publishProjection(environment: environment)
    let request = PlotterPenInteractionActuationRequest(
      operationID: operationID,
      environment: environment,
      command: command.runtimeCommand,
      profile: profile
    )
    let token = UUID()
    let task = Task { [port] in await port.settle(request) }
    actuationToken = token
    actuationTask = task
    let settlement = await task.value
    guard actuationToken == token else { return }
    terminalPublicationInProgress = true
    await terminalPublicationGate?.pauseIfArmed()
    defer { finishTerminalPublication() }
    actuationTask = nil
    actuationToken = nil
    guard activeEnvironment == environment,
      states[environment]?.operationID == settlement.operationID
    else { return }
    let execution = PlotterPenInteractionExecutionEvidence(
      command: request.command,
      profile: request.profile,
      outcome: settlement.outcome,
      position: settlement.observedPosition,
      timestamp: settlement.timestamp
    )
    mutate(environment) { state in
      state.lastExecution[request.command] = execution
      state.lastSettlement = settlement
      if state.cancellationRequested {
        state.phase = .cancelling
      } else {
        switch settlement.outcome {
        case .commandedAndSettled:
          state.phase = pendingSetpointCommand.map(PlotterPenInteractionPhase.drainingSetpoint)
            ?? .awaitingConfirmation(command)
        case .refused(let refusal):
          state.phase = .refused(.lowerRefused(refusal.actionableDescription))
        case .ambiguous(let ambiguity):
          state.phase = .possiblePhysicalChange(ambiguity.actionableDescription)
        }
      }
      advance(&state)
    }
    await publishProjection(environment: environment)
  }

  private func awaitTerminalPublication() async {
    guard terminalPublicationInProgress else { return }
    await withCheckedContinuation { terminalPublicationWaiters.append($0) }
  }

  private func finishTerminalPublication() {
    terminalPublicationInProgress = false
    let waiters = terminalPublicationWaiters
    terminalPublicationWaiters = []
    waiters.forEach { $0.resume() }
  }

  private func publishProjection(environment: PlotterEnvironment) async {
    await awaitProjectionPublication()
    projectionPublicationInProgress = true
    let snapshot = makeSnapshot(environment: environment)
    if let projectionSink {
      await projectionSink.publishPenInteractionSnapshot(snapshot)
    }
    finishProjectionPublication()
  }

  private func awaitProjectionPublication() async {
    guard projectionPublicationInProgress else { return }
    await withCheckedContinuation { projectionPublicationWaiters.append($0) }
  }

  private func finishProjectionPublication() {
    projectionPublicationInProgress = false
    let waiters = projectionPublicationWaiters
    projectionPublicationWaiters = []
    waiters.forEach { $0.resume() }
  }

  private func recordConfirmation(
    _ command: PlotterPenInteractionCommand,
    environment: PlotterEnvironment
  ) {
    var state = states[environment]!
    state.lastRefusal = nil
    let runtimeCommand = command.runtimeCommand
    let profile = state.draft ?? state.profile
    let execution = state.lastExecution[runtimeCommand].flatMap {
      $0.profile.value(for: runtimeCommand) == profile.value(for: runtimeCommand) ? $0 : nil
    }
    let position = execution?.position
    let timestamp = execution?.timestamp
      ?? RuntimeTimestamp(monotonicNanoseconds: DispatchTime.now().uptimeNanoseconds)
    if command == .raise {
      state.pending.upPositions.append(position)
      state.pending.upValues.append(profile.raisedSpindleValue)
      state.pending.upOutcomes.append(execution?.outcome)
      state.pending.upTimestamps.append(timestamp)
      if state.pending.downValues.isEmpty {
        state.phase = .awaitingControllerCommand(.lower)
      } else {
        commitSuccess(&state)
      }
    } else {
      state.pending.downPositions.append(position)
      state.pending.downValues.append(profile.loweredSpindleValue)
      state.pending.downOutcomes.append(execution?.outcome)
      state.pending.downTimestamps.append(timestamp)
      state.phase = .awaitingControllerCommand(.raise)
    }
    state.profile = profile
    advance(&state)
    states[environment] = state
    if state.phase == .succeeded { activeEnvironment = nil }
  }

  private func commitSuccess(_ state: inout State) {
    guard let attemptID = state.attemptID else { return }
    let sequence = state.acceptedSequence &+ 1
    let evidence = PenInteractionAttemptEvidence(
      actuationProfile: state.draft ?? state.profile,
      confirmedUpPositions: state.pending.upPositions,
      confirmedUpSpindleValues: state.pending.upValues,
      confirmedUpControllerOutcomes: state.pending.upOutcomes,
      confirmedUpTimestamps: state.pending.upTimestamps,
      confirmedDownPositions: state.pending.downPositions,
      confirmedDownSpindleValues: state.pending.downValues,
      confirmedDownControllerOutcomes: state.pending.downOutcomes,
      confirmedDownTimestamps: state.pending.downTimestamps
    )
    let attempt = try! ExerciseAttempt(
      id: attemptID,
      disposition: .succeeded,
      compatibility: state.history.compatibility,
      acceptedSequence: sequence,
      value: evidence
    )
    if state.attemptMode == .replacement,
      let existing = state.history.includedSuccessfulAttempts.last
    {
      try! state.history.recordReplacement(attempt, replacing: existing.id)
    } else {
      try! state.history.record(attempt)
    }
    state.acceptedSequence = sequence
    state.profile = evidence.actuationProfile
    state.phase = .succeeded
    state.operationID = nil
    state.cancellationID = nil
    state.attemptID = nil
    state.attemptMode = nil
  }

  private func recordTerminal(
    _ disposition: PlotterPenInteractionTerminalDisposition,
    environment: PlotterEnvironment
  ) {
    var state = states[environment]!
    if let attemptID = state.attemptID {
      let sequence = state.acceptedSequence &+ 1
      let attempt = try! ExerciseAttempt<PenInteractionAttemptEvidence>(
        id: attemptID,
        disposition: disposition.runtimeDisposition,
        compatibility: state.history.compatibility,
        acceptedSequence: sequence,
        value: nil
      )
      if state.attemptMode == .replacement,
        let existing = state.history.includedSuccessfulAttempts.last
      {
        try! state.history.recordReplacement(attempt, replacing: existing.id)
      } else {
        try! state.history.record(attempt)
      }
      state.acceptedSequence = sequence
    }
    if let settlement = state.lastSettlement {
      switch settlement.outcome {
      case .commandedAndSettled:
        state.phase = .possiblePhysicalChange(
          "The Pen Interaction ended after a settled Pen command. Inspect the pen and paper; no command was resent."
        )
      case .ambiguous(let ambiguity):
        state.phase = .possiblePhysicalChange(
          "Pen command delivery is ambiguous: \(ambiguity.actionableDescription). Do not resend automatically."
        )
      case .refused(let refusal):
        state.phase = .refused(.lowerRefused(refusal.actionableDescription))
      }
    } else {
      state.phase = .idle
    }
    state.operationID = nil
    state.cancellationID = nil
    state.attemptID = nil
    state.attemptMode = nil
    state.draft = nil
    state.pending = PendingEvidence()
    state.lastExecution = [:]
    state.cancellationRequested = false
    advance(&state)
    states[environment] = state
    activeEnvironment = nil
  }

  private func effectRefusal(
    _ facts: PlotterPenInteractionAdmissionFacts
  ) -> (PlotterPenInteractionRefusalReason, PlotterPenInteractionRemedy)? {
    if let ambiguity = facts.stickyAmbiguity {
      return (.stickyAmbiguity(ambiguity), .resolveAmbiguityWithoutAutomaticResend)
    }
    if !facts.controllerSessionEstablished {
      return (.controllerUnavailable, .connectAndProbeController)
    }
    if !facts.motionAuthorized {
      return (.motionAuthorizationRequired, .authorizeMotion)
    }
    if facts.lowerOperationInFlight {
      return (.lowerOperationInFlight, .waitForLowerSettlement)
    }
    return nil
  }

  private func isExpectedConfirmation(
    _ command: PlotterPenInteractionCommand,
    environment: PlotterEnvironment
  ) -> Bool {
    states[environment]?.phase == .awaitingConfirmation(command)
  }

  private func acceptsSetpoint(
    _ command: PlotterPenInteractionCommand,
    environment: PlotterEnvironment
  ) -> Bool {
    switch states[environment]?.phase {
    case .awaitingConfirmation(let expected), .drainingSetpoint(let expected),
      .settling(let expected):
      expected == command
    default: false
    }
  }

  private func waitForSetpointDrain() async {
    guard setpointDrainInProgress else { return }
    await withCheckedContinuation { setpointDrainWaiters.append($0) }
  }

  private func finishSetpointDrain() {
    setpointDrainInProgress = false
    let waiters = setpointDrainWaiters
    setpointDrainWaiters = []
    waiters.forEach { $0.resume() }
  }

  private func refuse(
    _ submission: PlotterPenInteractionSubmission,
    _ reason: PlotterPenInteractionRefusalReason,
    _ remedy: PlotterPenInteractionRemedy,
    _ environment: PlotterEnvironment
  ) -> PlotterPenInteractionDisposition {
    let refusal = PlotterPenInteractionRefusal(
      requestID: submission.requestID,
      reason: reason,
      remedy: remedy,
      currentProjection: reference(environment: environment)
    )
    mutate(environment) {
      $0.lastRefusal = refusal
      advance(&$0)
    }
    return .refused(refusal)
  }

  private func mutate(_ environment: PlotterEnvironment, _ body: (inout State) -> Void) {
    var state = states[environment]!
    body(&state)
    states[environment] = state
  }

  private func advance(_ state: inout State) { state.revision &+= 1 }

  private func reference(
    environment: PlotterEnvironment
  ) -> PlotterPenInteractionProjectionReference {
    let state = states[environment]!
    return PlotterPenInteractionProjectionReference(
      environment: environment,
      revision: PlotterPenInteractionRevision(rawValue: state.revision),
      operationID: state.operationID
    )
  }

  private func makeSnapshot(
    environment: PlotterEnvironment
  ) -> PlotterPenInteractionRuntimeSnapshot {
    let state = states[environment]!
    let profile = state.draft ?? state.profile
    return PlotterPenInteractionRuntimeSnapshot(
      projection: PlotterPenInteractionProjection(
        reference: reference(environment: environment),
        phase: state.phase,
        profile: profile.episodeProfile,
        cancellationCapabilityID: state.cancellationID,
        lastRefusal: state.lastRefusal,
        evidenceCount: state.history.includedSuccessfulAttempts.count,
        physicalEvidenceClaimed: false
      ),
      profile: profile,
      acceptedHistory: state.history,
      acceptedSequence: state.acceptedSequence,
      activeAttemptID: state.attemptID,
      activeAttemptMode: state.attemptMode,
      lastExecutionByCommand: state.lastExecution,
      lastSettlement: state.lastSettlement
    )
  }
}

private extension PlotterPenInteractionCommand {
  var runtimeCommand: PenCommand {
    switch self {
    case .raise: .raise
    case .lower: .lower
    }
  }
}

private extension PenActuationProfile {
  var episodeProfile: PlotterPenInteractionProfile {
    PlotterPenInteractionProfile(
      raisedSpindleValue: raisedSpindleValue,
      loweredSpindleValue: loweredSpindleValue,
      settleSeconds: settleSeconds
    )
  }
}

private extension PlotterPenInteractionTerminalDisposition {
  var runtimeDisposition: ExerciseAttemptDisposition {
    switch self {
    case .refused(let reason): .refused(reason)
    case .unclear(let reason): .unclear(reason)
    case .cancelled: .cancelled
    case .ambiguous(let reason): .ambiguous(reason)
    case .failed(let reason): .failed(reason)
    }
  }
}
