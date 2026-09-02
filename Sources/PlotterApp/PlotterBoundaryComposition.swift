import EpisodeCore
import Foundation
import PlotterEpisodeModel
import PlotterEpisodeRuntime
import PlotterModel
import PlotterRuntime

@MainActor
final class PlotterApplicationRuntimeBoundaryRelay: PlotterBoundaryFactSource,
  PlotterBoundaryProjectionSink
{
  weak var application: PlotterApplicationRuntime?

  func currentBoundaryFacts(for environment: PlotterEnvironment) async
    -> PlotterBoundaryExternalFacts
  {
    guard let application else {
      preconditionFailure("The Boundary composition must be installed before admission.")
    }
    return await application.currentBoundaryExternalFacts(for: environment)
  }

  func publishBoundarySnapshot(_ snapshot: PlotterBoundaryRuntimeSnapshot) async {
    guard let application else { return }
    if snapshot.projection.reference.environment == .live,
      snapshot.projection.reference.operationID == nil,
      snapshot.projection.terminal != nil
    {
      // The lower controller-session owner has settled. Refresh its complete
      // snapshot before publishing the Boundary terminal so every dependent
      // admission and presentation observes the terminal Idle/MPos.
      _ = await application.refreshControllerSessionSnapshot()
    }
    application.installBoundarySnapshot(snapshot)
  }

}

struct PlotterBoundaryComposition: Sendable {
  let runtime: PlotterBoundaryRuntime
  let relay: PlotterApplicationRuntimeBoundaryRelay

  @MainActor
  func install(on application: PlotterApplicationRuntime) {
    relay.application = application
    application.installBoundarySnapshot(PlotterBoundaryRuntime.initialSnapshot(for: .live))
    application.installBoundarySnapshot(PlotterBoundaryRuntime.initialSnapshot(for: .simulated))
  }

  @MainActor
  static func make(
    machineSession: (any PlotterMachineSession),
    causalSimulator: PlotterCausalSimulatorEffectAdapter,
    statePersistencePort: any PlotterApplicationStatePersistencePort,
    speechEffectRuntime: PlotterSpeechEffectRuntime
  ) -> Self {
    let relay = PlotterApplicationRuntimeBoundaryRelay()
    let runtime = PlotterBoundaryRuntime(
      factSource: relay,
      effectPort: PlotterApplicationRuntimeBoundaryEffectPort(
        actions: machineSession,
        causalSimulator: causalSimulator,
        speechEffectRuntime: speechEffectRuntime
      ),
      persistencePort: PlotterApplicationRuntimeBoundaryPersistencePort(
        statePersistencePort: statePersistencePort
      ),
      projectionSink: relay
    )
    return Self(runtime: runtime, relay: relay)
  }
}

private actor PlotterApplicationRuntimeBoundaryEffectPort: PlotterBoundaryEffectPort {
  private enum LowerOwner: Sendable {
    case liveSide(BoundaryMotionOperation)
    case liveCenter(RelativeJogOperation)
    case simulated(PlotterCausalSimulatorOperation, isBoundary: Bool)
  }

  private let actions: (any PlotterMachineSession)
  private let causalSimulator: PlotterCausalSimulatorEffectAdapter
  private let speechEffectRuntime: PlotterSpeechEffectRuntime
  private var owners: [UUID: LowerOwner] = [:]

  init(
    actions: (any PlotterMachineSession),
    causalSimulator: PlotterCausalSimulatorEffectAdapter,
    speechEffectRuntime: PlotterSpeechEffectRuntime
  ) {
    self.actions = actions
    self.causalSimulator = causalSimulator
    self.speechEffectRuntime = speechEffectRuntime
  }

  func preparePenUp(
    environment: PlotterEnvironment,
    profile: PenActuationProfile
  ) async -> Result<Void, PlotterBoundaryLowerPortFailure> {
    if environment == .simulated {
      let outcome = await causalSimulator.executeRetainedWorkflowPen(
        .up,
        owner: EpisodeAuthorityID(rawValue: "PlotterBoundaryRuntime")
      )
      if let refusal = outcome.refusal {
        return .failure(
          PlotterBoundaryLowerPortFailure(
            detail: "Simulated Pen Up was refused: \(refusal)."
          )
        )
      }
      return .success(())
    }
    let outcome = await PlotterManualMotionComposition.settleNativePenCommand(
      using: actions,
      command: .raise,
      profile: profile
    )
    switch outcome {
    case .commandedAndSettled(.raise, .up):
      return .success(())
    case .commandedAndSettled:
      return .failure(
        PlotterBoundaryLowerPortFailure(
          detail: "The controller returned a mismatched Pen Up settlement.",
          ambiguous: true
        )
      )
    case .refused(let refusal):
      return .failure(PlotterBoundaryLowerPortFailure(detail: refusal.actionableDescription))
    case .ambiguous(let ambiguity):
      return .failure(
        PlotterBoundaryLowerPortFailure(
          detail: ambiguity.actionableDescription,
          ambiguous: true
        )
      )
    }
  }

  func admitSide(
    environment: PlotterEnvironment,
    direction: PlotterBoundaryDirection
  ) async -> PlotterBoundaryLowerAdmission {
    if environment == .simulated {
      let admission = await causalSimulator.admitRetainedWorkflowBoundary(
        direction: BoundaryDirection(direction),
        finiteSegmentLengthMM: 50,
        owner: EpisodeAuthorityID(rawValue: "PlotterBoundaryRuntime")
      )
      switch admission {
      case .admitted(let operation):
        let id = UUID()
        owners[id] = .simulated(operation, isBoundary: true)
        return .admitted(
          PlotterBoundaryLowerHandle(
            id: id,
            environment: environment,
            lowerOwnerID: id,
            cancellationCapabilityID: id
          )
        )
      case .refused(let refusal):
        return .refused(String(describing: refusal.refusal))
      }
    }
    let delta: Vector2<MachineSpace>
    switch direction {
    case .negativeX: delta = try! Vector2(dx: -50, dy: 0)
    case .positiveX: delta = try! Vector2(dx: 50, dy: 0)
    case .negativeY: delta = try! Vector2(dx: 0, dy: -50)
    case .positiveY: delta = try! Vector2(dx: 0, dy: 50)
    }
    let request = BoundaryMotionRequest(
      direction: BoundaryDirection(direction),
      segment: RelativeJogRequest(
        delta: delta,
        feedMMPerMinute: PlotterMotionThroughput.applicationXYFeedMMPerMinute
      ),
      renewalBounds: .fixed(50)
    )
    switch await actions.beginBoundaryMotion(request, renewalPlanner: nil) {
    case .admitted(let operation):
      let id = UUID()
      owners[id] = .liveSide(operation)
      return .admitted(
        PlotterBoundaryLowerHandle(
          id: id,
          environment: environment,
          lowerOwnerID: operation.ownerID.rawValue,
          cancellationCapabilityID: id
        )
      )
    case .rejected(let outcome):
      switch outcome {
      case .settled:
        return .ambiguous("A rejected Boundary admission returned settlement truth.")
      case .needsAttention(_, let terminal):
        return .refused(String(describing: terminal))
      }
    }
  }

  func prepareSideAdvisory(
    environment: PlotterEnvironment,
    direction: PlotterBoundaryDirection
  ) async -> Result<Void, PlotterBoundaryLowerPortFailure> {
    guard environment == .live else { return .success(()) }
    guard let announcement = boundaryAnnouncement(for: direction) else {
      return .failure(PlotterBoundaryLowerPortFailure(
        detail: "The retained Boundary announcement definition is unavailable."
      ))
    }
    // Speech outcome remains advisory. Runtime ownership surrounds this await
    // with exact cancellation/shutdown and fresh-fact checks before motion.
    _ = await speechEffectRuntime.perform(.init(message: announcement))
    return .success(())
  }

  private func boundaryAnnouncement(for direction: PlotterBoundaryDirection) -> String? {
    let sequenceID: DiscoverySequenceID = switch direction {
    case .negativeX: .boundaryNegativeX
    case .positiveX: .boundaryPositiveX
    case .negativeY: .boundaryNegativeY
    case .positiveY: .boundaryPositiveY
    }
    guard case .announce(let message) =
      DiscoverySequenceCatalog.definition(for: sequenceID).steps.first?.action
    else {
      return nil
    }
    return message
  }

  func admitCenterTravel(
    environment: PlotterEnvironment,
    delta: Vector2<MachineSpace>
  ) async -> PlotterBoundaryLowerAdmission {
    if environment == .simulated {
      let admission = await causalSimulator.admitRetainedWorkflowTravel(
        delta: try! SimulatedLearningMotionVector(dxMM: delta.dx, dyMM: delta.dy),
        owner: EpisodeAuthorityID(rawValue: "PlotterBoundaryRuntime.center")
      )
      switch admission {
      case .admitted(let operation):
        let id = UUID()
        owners[id] = .simulated(operation, isBoundary: false)
        return .admitted(
          PlotterBoundaryLowerHandle(
            id: id,
            environment: environment,
            lowerOwnerID: id,
            cancellationCapabilityID: id
          )
        )
      case .refused(let refusal):
        return .refused(String(describing: refusal.refusal))
      }
    }
    let request = RelativeJogRequest(
      delta: delta,
      feedMMPerMinute: PlotterMotionThroughput.applicationXYFeedMMPerMinute
    )
    switch await PlotterManualMotionComposition.beginNativeRelativeMotion(
      using: actions,
      request: request
    ) {
    case .admitted(let operation):
      let id = UUID()
      owners[id] = .liveCenter(operation)
      return .admitted(
        PlotterBoundaryLowerHandle(
          id: id,
          environment: environment,
          lowerOwnerID: operation.id,
          cancellationCapabilityID: id
        )
      )
    case .rejected(let outcome):
      return lowerAdmission(for: outcome)
    }
  }

  func waitForTerminal(
    _ handle: PlotterBoundaryLowerHandle
  ) async -> PlotterBoundaryLowerTerminal {
    guard let owner = owners[handle.id] else {
      return .ambiguous("The retained lower Boundary owner disappeared.", finalPosition: nil)
    }
    defer { owners[handle.id] = nil }
    switch owner {
    case .liveSide(let operation):
      switch await operation.outcome() {
      case .settled(let settlement):
        switch settlement.intent {
        case .operatorStop:
          return .operatorStopped(finalPosition: settlement.finalPosition, idleVerified: true)
        case .cancelAttempt:
          return .cancelled(finalPosition: settlement.finalPosition)
        case .shutdown:
          return .shutdown(finalPosition: settlement.finalPosition)
        }
      case .needsAttention(_, let terminal):
        return .ambiguous(String(describing: terminal), finalPosition: nil)
      }
    case .liveCenter(let operation):
      switch await operation.outcome() {
      case .acceptedThenCompleted(let position):
        return .completed(finalPosition: position, idleVerified: true)
      case .cancelled(let position):
        return .cancelled(finalPosition: position)
      case .refused(let refusal):
        return .refused(refusal.actionableDescription, finalPosition: nil)
      case .ambiguous(let ambiguity):
        return .ambiguous(ambiguity.actionableDescription, finalPosition: nil)
      }
    case .simulated(let operation, let isBoundary):
      let outcome = isBoundary
        ? await causalSimulator.executeBoundaryCooperatively(operation)
        : await causalSimulator.executeNaturally(operation)
      let position = try! MachinePosition(
        x: outcome.finalMPos.xMM,
        y: outcome.finalMPos.yMM
      )
      switch outcome.disposition {
      case .stopped:
        return .operatorStopped(finalPosition: position, idleVerified: true)
      case .naturallyCompleted:
        return .completed(finalPosition: position, idleVerified: true)
      case .cancelled:
        return .cancelled(finalPosition: position)
      case .shutdown:
        return .shutdown(finalPosition: position)
      case .failed:
        return .ambiguous("The causal simulator failed the retained operation.", finalPosition: position)
      }
    }
  }

  func requestCancellation(
    _ intent: PlotterBoundaryCancellationIntent,
    handle: PlotterBoundaryLowerHandle
  ) async {
    guard let owner = owners[handle.id] else { return }
    switch owner {
    case .liveSide, .liveCenter:
      _ = await actions.requestJogCancel(JogCancelIntent(intent))
    case .simulated(let operation, _):
      _ = await causalSimulator.request(SimulatedLearningOperationIntent(intent), for: operation)
    }
  }

  private func lowerAdmission(for outcome: MotionOutcome) -> PlotterBoundaryLowerAdmission {
    switch outcome {
    case .refused(let refusal): .refused(refusal.actionableDescription)
    case .ambiguous(let ambiguity): .ambiguous(ambiguity.actionableDescription)
    case .cancelled: .ambiguous("A rejected center-travel admission returned cancelled truth.")
    case .acceptedThenCompleted: .ambiguous("A rejected center-travel admission returned completion truth.")
    }
  }
}

private struct PlotterApplicationRuntimeBoundaryPersistencePort: PlotterBoundaryPersistencePort {
  let statePersistencePort: any PlotterApplicationStatePersistencePort

  func persistBoundaryCandidate(_ candidate: PlotterBoundaryPersistenceCandidate) async throws {
    guard candidate.environment == .live else { return }
    let existing: AcceptedLearningPathCheckpoint?
    switch statePersistencePort.loadAcceptedLearningPathCheckpoint() {
    case .absent:
      existing = nil
    case .loaded(let checkpoint):
      existing = checkpoint
    case .rejected(let detail):
      throw PlotterBoundaryCompositionError.checkpointUnavailable(detail)
    }
    if let existing, existing.semanticIdentity != candidate.semanticIdentity {
      throw PlotterBoundaryCompositionError.semanticIdentityChanged
    }
    let checkpoint = try AcceptedLearningPathCheckpoint(
      semanticIdentity: candidate.semanticIdentity,
      penInteraction: existing?.penInteraction,
      machineArtifacts: candidate.machineArtifacts,
      machineCamera: existing?.machineCamera,
      tipCalibration: existing?.tipCalibration,
      stageFour: existing?.stageFour,
      penCapAppearance: existing?.penCapAppearance,
      referenceFrame: existing?.referenceFrame
    )
    try statePersistencePort.saveAcceptedLearningPathCheckpoint(checkpoint)
  }
}

private enum PlotterBoundaryCompositionError: Error {
  case checkpointUnavailable(String)
  case semanticIdentityChanged
}

private extension BoundaryDirection {
  init(_ direction: PlotterBoundaryDirection) {
    self = BoundaryDirection(rawValue: direction.rawValue)!
  }
}

private extension JogCancelIntent {
  init(_ intent: PlotterBoundaryCancellationIntent) {
    switch intent {
    case .operatorStop: self = .operatorStop
    case .cancelAttempt: self = .cancelAttempt
    case .shutdown: self = .shutdown
    }
  }
}

private extension SimulatedLearningOperationIntent {
  init(_ intent: PlotterBoundaryCancellationIntent) {
    switch intent {
    case .operatorStop: self = .stop
    case .cancelAttempt: self = .cancel
    case .shutdown: self = .shutdown
    }
  }
}
