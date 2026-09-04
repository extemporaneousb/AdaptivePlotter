import Foundation
import PlotterEpisodeModel
import PlotterModel
import PlotterRuntime

public extension AcceptedMachineArtifactCheckpoint {
  var acceptedBoundaryAggregates: [BoundarySideAggregate] {
    boundarySideAggregates
  }

  init(
    checkpointID: UUID = UUID(),
    controllerContext: ControllerCheckpointContext,
    machinePositionAtSave: MachinePosition,
    controllerSessionID: UUID,
    coordinateRevision: UInt64,
    acceptedAttemptSequence: UInt64,
    pairedBoundaryProgress: PairedBoundaryProgress,
    acceptedBoundaryEvidence: [BoundarySideAttemptEvidence],
    acceptedBoundaryAggregates: [BoundarySideAggregate],
    estimatedMachineCenter: EstimatedMachineCenter?,
    learnedLocalCoordinateFrame: LearnedLocalCoordinateFrame?,
    centerArrivalPosition: MachinePosition?,
    acceptedRevisions: [LearningArtifactRevision]
  ) throws {
    try self.init(
      checkpointID: checkpointID,
      controllerContext: controllerContext,
      machinePositionAtSave: machinePositionAtSave,
      controllerSessionID: controllerSessionID,
      coordinateRevision: coordinateRevision,
      acceptedAttemptSequence: acceptedAttemptSequence,
      pairedBoundaryProgress: pairedBoundaryProgress,
      acceptedBoundaryEvidence: acceptedBoundaryEvidence,
      boundarySideAggregates: acceptedBoundaryAggregates,
      estimatedMachineCenter: estimatedMachineCenter,
      learnedLocalCoordinateFrame: learnedLocalCoordinateFrame,
      centerArrivalPosition: centerArrivalPosition,
      acceptedRevisions: acceptedRevisions
    )
  }
}

public struct PlotterBoundaryExternalFacts: Sendable {
  public let environment: PlotterEnvironment
  public let learningEnabled: Bool
  public let controllerSessionEstablished: Bool
  public let motionAuthorized: Bool
  public let foreignLowerOperationInFlight: Bool
  public let stickyAmbiguity: String?
  public let controllerSessionID: UUID
  public let coordinateRevision: UInt64
  public let machinePosition: MachinePosition?
  public let interpreterIsIdle: Bool
  public let passiveProbe: PassiveProbeResult?
  public let penActuationProfile: PenActuationProfile
  public let semanticIdentity: LearningPathSemanticIdentity

  public init(
    environment: PlotterEnvironment,
    learningEnabled: Bool,
    controllerSessionEstablished: Bool,
    motionAuthorized: Bool,
    foreignLowerOperationInFlight: Bool,
    stickyAmbiguity: String?,
    controllerSessionID: UUID,
    coordinateRevision: UInt64,
    machinePosition: MachinePosition?,
    interpreterIsIdle: Bool,
    passiveProbe: PassiveProbeResult?,
    penActuationProfile: PenActuationProfile,
    semanticIdentity: LearningPathSemanticIdentity
  ) {
    self.environment = environment
    self.learningEnabled = learningEnabled
    self.controllerSessionEstablished = controllerSessionEstablished
    self.motionAuthorized = motionAuthorized
    self.foreignLowerOperationInFlight = foreignLowerOperationInFlight
    self.stickyAmbiguity = stickyAmbiguity
    self.controllerSessionID = controllerSessionID
    self.coordinateRevision = coordinateRevision
    self.machinePosition = machinePosition
    self.interpreterIsIdle = interpreterIsIdle
    self.passiveProbe = passiveProbe
    self.penActuationProfile = penActuationProfile
    self.semanticIdentity = semanticIdentity
  }

  fileprivate var effectIdentity: EffectIdentity {
    EffectIdentity(
      environment: environment,
      learningEnabled: learningEnabled,
      controllerSessionEstablished: controllerSessionEstablished,
      motionAuthorized: motionAuthorized,
      foreignLowerOperationInFlight: foreignLowerOperationInFlight,
      stickyAmbiguity: stickyAmbiguity,
      controllerSessionID: controllerSessionID,
      coordinateRevision: coordinateRevision,
      machinePosition: machinePosition,
      interpreterIsIdle: interpreterIsIdle,
      passiveProbe: passiveProbe,
      penActuationProfile: penActuationProfile,
      semanticIdentity: semanticIdentity
    )
  }

  fileprivate struct EffectIdentity: Hashable, Sendable {
    let environment: PlotterEnvironment
    let learningEnabled: Bool
    let controllerSessionEstablished: Bool
    let motionAuthorized: Bool
    let foreignLowerOperationInFlight: Bool
    let stickyAmbiguity: String?
    let controllerSessionID: UUID
    let coordinateRevision: UInt64
    let machinePosition: MachinePosition?
    let interpreterIsIdle: Bool
    let passiveProbe: PassiveProbeResult?
    let penActuationProfile: PenActuationProfile
    let semanticIdentity: LearningPathSemanticIdentity
  }
}

public protocol PlotterBoundaryFactSource: Sendable {
  func currentBoundaryFacts(for environment: PlotterEnvironment) async
    -> PlotterBoundaryExternalFacts
}

public struct PlotterBoundaryLowerHandle: Hashable, Sendable {
  public let id: UUID
  public let environment: PlotterEnvironment
  public let lowerOwnerID: UUID
  public let cancellationCapabilityID: UUID

  public init(
    id: UUID,
    environment: PlotterEnvironment,
    lowerOwnerID: UUID,
    cancellationCapabilityID: UUID
  ) {
    self.id = id
    self.environment = environment
    self.lowerOwnerID = lowerOwnerID
    self.cancellationCapabilityID = cancellationCapabilityID
  }
}

public enum PlotterBoundaryLowerAdmission: Sendable {
  case admitted(PlotterBoundaryLowerHandle)
  case refused(String)
  case ambiguous(String)
}

public enum PlotterBoundaryLowerTerminal: Hashable, Sendable {
  case operatorStopped(finalPosition: MachinePosition, idleVerified: Bool)
  case completed(finalPosition: MachinePosition, idleVerified: Bool)
  case cancelled(finalPosition: MachinePosition?)
  case shutdown(finalPosition: MachinePosition?)
  case refused(String, finalPosition: MachinePosition?)
  case ambiguous(String, finalPosition: MachinePosition?)
}

public protocol PlotterBoundaryEffectPort: Sendable {
  func preparePenUp(
    environment: PlotterEnvironment,
    profile: PenActuationProfile
  ) async -> Result<Void, PlotterBoundaryLowerPortFailure>

  func prepareSideAdvisory(
    environment: PlotterEnvironment,
    direction: PlotterBoundaryDirection
  ) async -> Result<Void, PlotterBoundaryLowerPortFailure>

  func admitSide(
    environment: PlotterEnvironment,
    direction: PlotterBoundaryDirection
  ) async -> PlotterBoundaryLowerAdmission

  func admitCenterTravel(
    environment: PlotterEnvironment,
    delta: Vector2<MachineSpace>
  ) async -> PlotterBoundaryLowerAdmission

  func waitForTerminal(
    _ handle: PlotterBoundaryLowerHandle
  ) async -> PlotterBoundaryLowerTerminal

  func requestCancellation(
    _ intent: PlotterBoundaryCancellationIntent,
    handle: PlotterBoundaryLowerHandle
  ) async
}

public struct PlotterBoundaryLowerPortFailure: Error, Hashable, Sendable {
  public let detail: String
  public let ambiguous: Bool

  public init(detail: String, ambiguous: Bool = false) {
    self.detail = detail
    self.ambiguous = ambiguous
  }
}

public struct PlotterBoundaryPersistenceCandidate: Sendable {
  public let environment: PlotterEnvironment
  public let semanticIdentity: LearningPathSemanticIdentity
  public let machineArtifacts: AcceptedMachineArtifactCheckpoint

  public init(
    environment: PlotterEnvironment,
    semanticIdentity: LearningPathSemanticIdentity,
    machineArtifacts: AcceptedMachineArtifactCheckpoint
  ) {
    self.environment = environment
    self.semanticIdentity = semanticIdentity
    self.machineArtifacts = machineArtifacts
  }
}

public protocol PlotterBoundaryPersistencePort: Sendable {
  func persistBoundaryCandidate(_ candidate: PlotterBoundaryPersistenceCandidate) async throws
}

@MainActor
public protocol PlotterBoundaryProjectionSink: AnyObject, Sendable {
  func publishBoundarySnapshot(_ snapshot: PlotterBoundaryRuntimeSnapshot) async
}

public struct PlotterBoundaryRuntimeSnapshot: Sendable {
  public let projection: PlotterBoundaryProjection
  public let pairedProgress: PairedBoundaryProgress
  public let acceptedEvidence: [BoundarySideAttemptEvidence]
  public let acceptedAggregates: [BoundaryDirection: BoundarySideAggregate]
  public let estimatedCenter: EstimatedMachineCenter?
  public let localCoordinateFrame: LearnedLocalCoordinateFrame?
  public let centerArrivalPosition: MachinePosition?
  public let attemptTerminals: [PlotterBoundaryTerminal]
  public let acceptedAttemptSequence: UInt64
  public let currentRevisions: [LearningArtifactRevision]
  public let acceptedMachineArtifacts: AcceptedMachineArtifactCheckpoint?

  public init(
    projection: PlotterBoundaryProjection,
    pairedProgress: PairedBoundaryProgress,
    acceptedEvidence: [BoundarySideAttemptEvidence],
    acceptedAggregates: [BoundaryDirection: BoundarySideAggregate],
    estimatedCenter: EstimatedMachineCenter?,
    localCoordinateFrame: LearnedLocalCoordinateFrame?,
    centerArrivalPosition: MachinePosition?,
    attemptTerminals: [PlotterBoundaryTerminal],
    acceptedAttemptSequence: UInt64,
    currentRevisions: [LearningArtifactRevision],
    acceptedMachineArtifacts: AcceptedMachineArtifactCheckpoint?
  ) {
    self.projection = projection
    self.pairedProgress = pairedProgress
    self.acceptedEvidence = acceptedEvidence
    self.acceptedAggregates = acceptedAggregates
    self.estimatedCenter = estimatedCenter
    self.localCoordinateFrame = localCoordinateFrame
    self.centerArrivalPosition = centerArrivalPosition
    self.attemptTerminals = attemptTerminals
    self.acceptedAttemptSequence = acceptedAttemptSequence
    self.currentRevisions = currentRevisions
    self.acceptedMachineArtifacts = acceptedMachineArtifacts
  }
}

/// A scheduling-only test seam. It grants no effect, cancellation, or result
/// authority; release merely allows the already-admitted owner to continue.
public actor PlotterBoundaryAdmissionGate {
  private var held = false
  private var ready = false
  private var waiter: CheckedContinuation<Void, Never>?
  private var readyWaiters: [CheckedContinuation<Void, Never>] = []

  public init(held: Bool = false) { self.held = held }

  public func hold() { held = true }

  public func waitUntilReady() async {
    if ready { return }
    await withCheckedContinuation { readyWaiters.append($0) }
  }

  public func release() {
    held = false
    waiter?.resume()
    waiter = nil
  }

  fileprivate func arriveAndWaitIfHeld() async {
    ready = true
    let waiters = readyWaiters
    readyWaiters.removeAll()
    waiters.forEach { $0.resume() }
    guard held else { return }
    await withCheckedContinuation { waiter = $0 }
  }
}

/// A scheduling-only test seam after lower terminal truth and before durable
/// publication. It cannot select or rewrite the terminal result.
public actor PlotterBoundaryTerminalPublicationGate {
  private var held = false
  private var ready = false
  private var waiter: CheckedContinuation<Void, Never>?
  private var readyWaiters: [CheckedContinuation<Void, Never>] = []

  public init(held: Bool = false) { self.held = held }

  public func hold() { held = true }

  public func waitUntilReady() async {
    if ready { return }
    await withCheckedContinuation { readyWaiters.append($0) }
  }

  public func release() {
    held = false
    waiter?.resume()
    waiter = nil
  }

  fileprivate func arriveAndWaitIfHeld() async {
    ready = true
    let waiters = readyWaiters
    readyWaiters.removeAll()
    waiters.forEach { $0.resume() }
    guard held else { return }
    await withCheckedContinuation { waiter = $0 }
  }
}

/// Runtime-owned one-shot ordering latch. Unlike the package test gates, this
/// is mandatory production ownership: the operation task cannot inspect facts
/// or reach a lower port until the reserving snapshot has finished publishing.
private actor PlotterBoundaryReservationPublicationLatch {
  private var released = false
  private var waiters: [CheckedContinuation<Void, Never>] = []

  func waitForPublication() async {
    if released { return }
    await withCheckedContinuation { waiters.append($0) }
  }

  func releaseAfterPublication() {
    guard !released else { return }
    released = true
    let continuations = waiters
    waiters.removeAll()
    continuations.forEach { $0.resume() }
  }
}

public actor PlotterBoundaryRuntime {
  private struct Authority: Sendable {
    var histories: [BoundaryDirection: ExerciseAttemptHistory<BoundarySideAttemptEvidence>] = [:]
    var evidence: [BoundarySideAttemptEvidence] = []
    var aggregates: [BoundaryDirection: BoundarySideAggregate] = [:]
    var progress = PairedBoundaryProgress()
    var center: EstimatedMachineCenter?
    var localFrame: LearnedLocalCoordinateFrame?
    var centerArrival: MachinePosition?
    var acceptedSequence: UInt64 = 0
    var revisions: [LearningArtifactRevision] = []
    var checkpoint: AcceptedMachineArtifactCheckpoint?
  }

  private struct ActiveOperation: Sendable {
    let attemptID: PlotterBoundaryAttemptID
    let operationID: PlotterBoundaryOperationID
    let capabilityID: PlotterBoundaryCancellationCapabilityID
    let activity: PlotterBoundaryActivityKind
    let direction: PlotterBoundaryDirection?
    let mode: PlotterBoundaryAttemptMode
    let reservationPublicationLatch: PlotterBoundaryReservationPublicationLatch
    var admittedFacts: PlotterBoundaryExternalFacts.EffectIdentity?
    var lowerHandle: PlotterBoundaryLowerHandle?
    var cancellation: PlotterBoundaryCancellationIntent?
    var cancellationSent = false
    var terminalPublicationStarted = false
  }

  private struct PendingPublication: Sendable {
    let capabilityID: PlotterBoundaryPublicationRecoveryCapabilityID
    let authority: Authority
    let candidate: PlotterBoundaryPersistenceCandidate
    let terminal: PlotterBoundaryTerminal
  }

  private struct PendingReset: Sendable {
    let capabilityID: PlotterBoundaryResetCapabilityID
    let priorPhase: PlotterBoundaryPhase
  }

  private struct State: Sendable {
    var revision = PlotterBoundaryRevision(rawValue: 0)
    var phase = PlotterBoundaryPhase.idle
    var selectedDirection = PlotterBoundaryDirection.negativeX
    var authority = Authority()
    var active: ActiveOperation?
    var pendingPublication: PendingPublication?
    var pendingReset: PendingReset?
    var lastRefusal: PlotterBoundaryRefusal?
    var terminal: PlotterBoundaryTerminal?
    var terminals: [PlotterBoundaryTerminal] = []
    var admissionClosed = false
  }

  private let factSource: any PlotterBoundaryFactSource
  private let effectPort: any PlotterBoundaryEffectPort
  private let persistencePort: any PlotterBoundaryPersistencePort
  private let admissionGate: PlotterBoundaryAdmissionGate?
  private let terminalPublicationGate: PlotterBoundaryTerminalPublicationGate?
  private weak var projectionSink: (any PlotterBoundaryProjectionSink)?
  private var states: [PlotterEnvironment: State] = [
    .live: State(),
    .simulated: State(),
  ]
  private var operationTasks: [PlotterEnvironment: Task<Void, Never>] = [:]

  public init(
    factSource: any PlotterBoundaryFactSource,
    effectPort: any PlotterBoundaryEffectPort,
    persistencePort: any PlotterBoundaryPersistencePort,
    projectionSink: (any PlotterBoundaryProjectionSink)? = nil,
    admissionGate: PlotterBoundaryAdmissionGate? = nil,
    terminalPublicationGate: PlotterBoundaryTerminalPublicationGate? = nil
  ) {
    self.factSource = factSource
    self.effectPort = effectPort
    self.persistencePort = persistencePort
    self.projectionSink = projectionSink
    self.admissionGate = admissionGate
    self.terminalPublicationGate = terminalPublicationGate
  }

  public func installProjectionSink(_ sink: (any PlotterBoundaryProjectionSink)?) async {
    projectionSink = sink
    if let sink {
      for environment in PlotterEnvironment.allCases {
        await sink.publishBoundarySnapshot(snapshot(for: environment))
      }
    }
  }

  public nonisolated static func initialSnapshot(
    for environment: PlotterEnvironment
  ) -> PlotterBoundaryRuntimeSnapshot {
    let progress = PairedBoundaryProgress()
    return PlotterBoundaryRuntimeSnapshot(
      projection: PlotterBoundaryProjection(
        reference: PlotterBoundaryProjectionReference(
          environment: environment,
          revision: PlotterBoundaryRevision(rawValue: 0),
          operationID: nil
        ),
        phase: .idle,
        selectedDirection: .negativeX,
        allowedDirections: progress.allowedDirections.map(PlotterBoundaryDirection.init),
        acceptedAggregates: [:],
        estimatedCenter: nil,
        centerArrival: nil,
        centerArrivalRetryRequired: false,
        cancellationCapabilityID: nil,
        publicationRecoveryCapabilityID: nil,
        resetCapabilityID: nil,
        lastRefusal: nil,
        terminal: nil,
        physicalEvidenceClaimed: false
      ),
      pairedProgress: progress,
      acceptedEvidence: [],
      acceptedAggregates: [:],
      estimatedCenter: nil,
      localCoordinateFrame: nil,
      centerArrivalPosition: nil,
      attemptTerminals: [],
      acceptedAttemptSequence: 0,
      currentRevisions: [],
      acceptedMachineArtifacts: nil
    )
  }

  public func snapshot(for environment: PlotterEnvironment) -> PlotterBoundaryRuntimeSnapshot {
    let state = states[environment]!
    let authority = state.authority
    let allowed = authority.progress.allowedDirections.map(PlotterBoundaryDirection.init)
    let summaries = Dictionary(uniqueKeysWithValues: authority.aggregates.map { direction, value in
      (
        PlotterBoundaryDirection(direction),
        PlotterBoundaryAggregateSummary(
          direction: PlotterBoundaryDirection(direction),
          estimateMM: value.estimateMM,
          validSampleCount: value.validSampleCount,
          revisionID: value.revisionID.rawValue
        )
      )
    })
    let reference = PlotterBoundaryProjectionReference(
      environment: environment,
      revision: state.revision,
      operationID: state.active?.operationID
    )
    let projection = PlotterBoundaryProjection(
      reference: reference,
      phase: state.phase,
      selectedDirection: state.selectedDirection,
      allowedDirections: allowed,
      acceptedAggregates: summaries,
      estimatedCenter: authority.center.map {
        PlotterBoundaryPositionSummary(xMM: $0.point.x, yMM: $0.point.y)
      },
      centerArrival: authority.centerArrival.map {
        PlotterBoundaryPositionSummary(xMM: $0.point.x, yMM: $0.point.y)
      },
      centerArrivalRetryRequired: centerArrivalRetryIsRequired(
        state: state,
        authority: authority
      ),
      cancellationCapabilityID: state.active?.capabilityID,
      publicationRecoveryCapabilityID: state.pendingPublication?.capabilityID,
      resetCapabilityID: state.pendingReset?.capabilityID,
      lastRefusal: state.lastRefusal,
      terminal: state.terminal,
      physicalEvidenceClaimed: false
    )
    return PlotterBoundaryRuntimeSnapshot(
      projection: projection,
      pairedProgress: authority.progress,
      acceptedEvidence: authority.evidence,
      acceptedAggregates: authority.aggregates,
      estimatedCenter: authority.center,
      localCoordinateFrame: authority.localFrame,
      centerArrivalPosition: authority.centerArrival,
      attemptTerminals: state.terminals,
      acceptedAttemptSequence: authority.acceptedSequence,
      currentRevisions: authority.revisions.filter { $0.state == .current },
      acceptedMachineArtifacts: authority.checkpoint
    )
  }

  private func centerArrivalRetryIsRequired(
    state: State,
    authority: Authority
  ) -> Bool {
    guard authority.center != nil,
      authority.centerArrival == nil,
      let terminal = state.terminal,
      terminal.activity == .centerArrival
    else {
      return false
    }

    switch terminal.disposition {
    case .cancelled, .shutdown, .refused, .ambiguous:
      return true
    case .accepted, .publicationIncomplete:
      return false
    }
  }

  public func submit(_ submission: PlotterBoundarySubmission) async -> PlotterBoundaryDisposition {
    let environment = submission.projection.environment
    guard states[environment] != nil else {
      return refusal(
        submission,
        reason: .environmentChanged,
        remedy: .useCurrentProjection
      )
    }
    guard submission.projection == snapshot(for: environment).projection.reference else {
      return refusal(submission, reason: .staleProjection, remedy: .useCurrentProjection)
    }

    switch submission.intent {
    case .stop(let capability):
      return await cancelActive(
        submission,
        capability: capability,
        intent: .operatorStop
      )
    case .cancel(let capability):
      return await cancelActive(
        submission,
        capability: capability,
        intent: .cancelAttempt
      )
    case .recoverPublication(let capability):
      return await recoverPublication(submission, capability: capability)
    case .reserveReset:
      return await reserveReset(submission)
    case .commitReset(let capability):
      return await commitReset(submission, capability: capability)
    case .abortReset(let capability):
      return await abortReset(submission, capability: capability)
    case .selectDirection(let direction):
      guard states[environment]!.pendingReset == nil else {
        return refusal(
          submission,
          reason: .resetTransactionInFlight,
          remedy: .waitForResetTransaction
        )
      }
      guard states[environment]!.active == nil,
        states[environment]!.pendingPublication == nil
      else {
        return refusal(submission, reason: .operationInFlight, remedy: .waitForActiveOwner)
      }
      let allowed = states[environment]!.authority.progress.allowedDirections
        .map(PlotterBoundaryDirection.init)
      guard allowed.contains(direction) else {
        return refusal(
          submission,
          reason: .directionNotAllowed(direction),
          remedy: .choosePublishedDirection
        )
      }
      states[environment]!.selectedDirection = direction
      advanceRevision(environment)
      await publish(environment)
      return .applied(snapshot(for: environment).projection)
    case .acquire(let direction, let mode):
      return await admit(
        submission,
        direction: direction,
        mode: mode,
        activity: .sideAcquisition
      )
    case .moveToEstimatedCenter(let retry):
      let state = states[environment]!
      guard state.authority.centerArrival == nil else {
        return refusal(
          submission,
          reason: .centerArrivalAlreadyAccepted,
          remedy: .continueAfterAcceptedCenter
        )
      }
      let expectedRetry = centerArrivalRetryIsRequired(
        state: state,
        authority: state.authority
      )
      guard retry == expectedRetry else {
        return refusal(
          submission,
          reason: .centerRetryMismatch(expected: expectedRetry, submitted: retry),
          remedy: .usePublishedCenterRetry
        )
      }
      return await admit(
        submission,
        direction: nil,
        mode: retry ? .replacement : .normal,
        activity: .centerArrival
      )
    }
  }

  private func reserveReset(
    _ submission: PlotterBoundarySubmission
  ) async -> PlotterBoundaryDisposition {
    let environment = submission.projection.environment
    guard !states[environment]!.admissionClosed else {
      return refusal(submission, reason: .admissionClosed, remedy: .restartApplication)
    }
    guard states[environment]!.active == nil else {
      return refusal(submission, reason: .operationInFlight, remedy: .waitForActiveOwner)
    }
    guard states[environment]!.pendingPublication == nil else {
      return refusal(
        submission,
        reason: .publicationRecoveryRequired,
        remedy: .retryExactPublication
      )
    }
    guard states[environment]!.pendingReset == nil else {
      return refusal(
        submission,
        reason: .resetTransactionInFlight,
        remedy: .waitForResetTransaction
      )
    }
    let capability = PlotterBoundaryResetCapabilityID()
    states[environment]!.pendingReset = PendingReset(
      capabilityID: capability,
      priorPhase: states[environment]!.phase
    )
    states[environment]!.phase = .resetReserved(capability)
    advanceRevision(environment)
    await publish(environment)
    return .applied(snapshot(for: environment).projection)
  }

  private func commitReset(
    _ submission: PlotterBoundarySubmission,
    capability: PlotterBoundaryResetCapabilityID
  ) async -> PlotterBoundaryDisposition {
    let environment = submission.projection.environment
    guard let pendingReset = states[environment]!.pendingReset else {
      return refusal(
        submission,
        reason: .resetNotReserved,
        remedy: .reserveResetTransaction
      )
    }
    guard pendingReset.capabilityID == capability else {
      return refusal(
        submission,
        reason: .resetCapabilityMismatch,
        remedy: .useExactResetCapability
      )
    }
    let nextRevision = PlotterBoundaryRevision(
      rawValue: states[environment]!.revision.rawValue &+ 1
    )
    let admissionClosed = states[environment]!.admissionClosed
    states[environment] = State(
      revision: nextRevision,
      admissionClosed: admissionClosed
    )
    await publish(environment)
    return .applied(snapshot(for: environment).projection)
  }

  private func abortReset(
    _ submission: PlotterBoundarySubmission,
    capability: PlotterBoundaryResetCapabilityID
  ) async -> PlotterBoundaryDisposition {
    let environment = submission.projection.environment
    guard let pendingReset = states[environment]!.pendingReset else {
      return refusal(
        submission,
        reason: .resetNotReserved,
        remedy: .reserveResetTransaction
      )
    }
    guard pendingReset.capabilityID == capability else {
      return refusal(
        submission,
        reason: .resetCapabilityMismatch,
        remedy: .useExactResetCapability
      )
    }
    states[environment]!.pendingReset = nil
    states[environment]!.phase = pendingReset.priorPhase
    advanceRevision(environment)
    await publish(environment)
    return .applied(snapshot(for: environment).projection)
  }

  public func restore(
    _ checkpoint: AcceptedMachineArtifactCheckpoint,
    environment: PlotterEnvironment
  ) async throws {
    guard states[environment]!.active == nil,
      states[environment]!.pendingPublication == nil,
      states[environment]!.pendingReset == nil
    else { throw PlotterBoundaryRestoreError.activeOwner }
    var authority = Authority()
    let restored = try checkpoint.restoredBoundaryHistories()
    authority.histories = Dictionary(uniqueKeysWithValues: restored.compactMap { direction, groups in
      guard let history = groups.values.first else { return nil }
      return (direction, history)
    })
    authority.evidence = checkpoint.acceptedBoundaryEvidence
    authority.aggregates = Dictionary(uniqueKeysWithValues: checkpoint.boundarySideAggregates.map {
      ($0.direction, $0)
    })
    authority.progress = checkpoint.pairedBoundaryProgress
    authority.center = checkpoint.estimatedMachineCenter
    authority.localFrame = checkpoint.learnedLocalCoordinateFrame
    authority.centerArrival = checkpoint.centerArrivalPosition
    authority.acceptedSequence = checkpoint.acceptedAttemptSequence
    authority.revisions = checkpoint.acceptedRevisions
    authority.checkpoint = checkpoint
    states[environment]!.authority = authority
    states[environment]!.selectedDirection = authority.progress.allowedDirections.first
      .map(PlotterBoundaryDirection.init) ?? .negativeX
    states[environment]!.phase = .idle
    states[environment]!.terminal = nil
    states[environment]!.lastRefusal = nil
    advanceRevision(environment)
    await publish(environment)
  }

  public func installRebasedMachineArtifacts(
    _ checkpoint: AcceptedMachineArtifactCheckpoint,
    environment: PlotterEnvironment
  ) async throws {
    try await restore(checkpoint, environment: environment)
  }

  /// Closes admission and records the first-winning cancellation intent without
  /// waiting for an operation that may currently be suspended in advisory
  /// speech. Composition cancels that retained speech owner before joining the
  /// operation through `shutdown()`.
  public func beginShutdown() async {
    for environment in PlotterEnvironment.allCases {
      var changed = false
      if !states[environment]!.admissionClosed {
        states[environment]!.admissionClosed = true
        changed = true
      }
      if var active = states[environment]!.active,
        !active.terminalPublicationStarted
      {
        if active.cancellation == nil {
          active.cancellation = .shutdown
          changed = true
        }
        let cancellation = active.cancellation!
        states[environment]!.active = active
        if states[environment]!.phase != .cancelling(cancellation) {
          states[environment]!.phase = .cancelling(cancellation)
          changed = true
        }
        if changed {
          advanceRevision(environment)
          await publish(environment)
        }
        if let current = states[environment]!.active,
          current.operationID == active.operationID,
          let handle = current.lowerHandle,
          !current.cancellationSent
        {
          states[environment]!.active?.cancellationSent = true
          await effectPort.requestCancellation(current.cancellation ?? cancellation, handle: handle)
        }
      } else if changed {
        advanceRevision(environment)
        await publish(environment)
      }
    }
  }

  public func shutdown() async {
    await beginShutdown()
    for environment in PlotterEnvironment.allCases {
      if let operationTask = operationTasks[environment] {
        await operationTask.value
      }
    }
  }

  private func admit(
    _ submission: PlotterBoundarySubmission,
    direction: PlotterBoundaryDirection?,
    mode: PlotterBoundaryAttemptMode,
    activity: PlotterBoundaryActivityKind
  ) async -> PlotterBoundaryDisposition {
    let environment = submission.projection.environment
    guard !states[environment]!.admissionClosed else {
      return refusal(submission, reason: .admissionClosed, remedy: .restartApplication)
    }
    guard states[environment]!.pendingReset == nil else {
      return refusal(
        submission,
        reason: .resetTransactionInFlight,
        remedy: .waitForResetTransaction
      )
    }
    guard states[environment]!.active == nil,
      states[environment]!.pendingPublication == nil
    else {
      return refusal(submission, reason: .operationInFlight, remedy: .waitForActiveOwner)
    }
    let reservationPublicationLatch = PlotterBoundaryReservationPublicationLatch()
    let active = ActiveOperation(
      attemptID: PlotterBoundaryAttemptID(),
      operationID: PlotterBoundaryOperationID(),
      capabilityID: PlotterBoundaryCancellationCapabilityID(),
      activity: activity,
      direction: direction,
      mode: mode,
      reservationPublicationLatch: reservationPublicationLatch,
      admittedFacts: nil
    )
    states[environment]!.active = active
    states[environment]!.phase = .reserving(activity: activity, direction: direction)
    states[environment]!.lastRefusal = nil
    states[environment]!.terminal = nil
    advanceRevision(environment)
    let operationID = active.operationID
    operationTasks[environment] = Task { [weak self] in
      await self?.prepareAndExecute(
        submission,
        environment: environment,
        operationID: operationID
      )
    }
    await publish(environment)
    await reservationPublicationLatch.releaseAfterPublication()
    return .applied(snapshot(for: environment).projection)
  }

  private func admissionRefusal(
    facts: PlotterBoundaryExternalFacts
  ) -> (PlotterBoundaryRefusalReason, PlotterBoundaryRemedy)? {
    guard states[facts.environment] != nil else {
      return (.environmentChanged, .useCurrentProjection)
    }
    guard facts.learningEnabled else {
      return (.learningDisabled, .enableLearning)
    }
    if let ambiguity = facts.stickyAmbiguity {
      return (.stickyAmbiguity(ambiguity), .resolveAmbiguityWithoutAutomaticResend)
    }
    guard !facts.foreignLowerOperationInFlight else {
      return (.lowerOperationInFlight, .waitForActiveOwner)
    }
    if facts.environment == .live {
      guard facts.controllerSessionEstablished, facts.interpreterIsIdle,
        facts.machinePosition != nil, facts.passiveProbe != nil
      else {
        return (
          .controllerUnavailable("A fresh Idle controller snapshot and passive probe are required."),
          .connectAndProbeController
        )
      }
      guard facts.motionAuthorized else {
        return (.motionAuthorizationRequired, .authorizeMotion)
      }
    }
    return nil
  }

  private func prepareAndExecute(
    _ submission: PlotterBoundarySubmission,
    environment: PlotterEnvironment,
    operationID: PlotterBoundaryOperationID
  ) async {
    guard let reservationPublicationLatch = states[environment]!.active?
      .reservationPublicationLatch,
      states[environment]!.active?.operationID == operationID
    else { return }
    await reservationPublicationLatch.waitForPublication()
    // This package-only gate is scheduling-only. The exact operation and
    // cancellation capability have already been installed and published, so
    // tests can hold the real pre-fact boundary without bypassing admission.
    await admissionGate?.arriveAndWaitIfHeld()
    guard states[environment]!.active?.operationID == operationID else { return }
    if await cancelBeforeLowerIfNeeded(environment, operationID: operationID) {
      return
    }

    let facts = await factSource.currentBoundaryFacts(for: environment)
    guard states[environment]!.active?.operationID == operationID else { return }
    if await cancelBeforeLowerIfNeeded(environment, operationID: operationID) {
      return
    }
    guard facts.environment == environment else {
      await refuseReservedAdmission(
        submission,
        environment: environment,
        operationID: operationID,
        reason: .environmentChanged,
        remedy: .useCurrentProjection
      )
      return
    }
    if let (reason, remedy) = admissionRefusal(facts: facts) {
      await refuseReservedAdmission(
        submission,
        environment: environment,
        operationID: operationID,
        reason: reason,
        remedy: remedy
      )
      return
    }

    let active = states[environment]!.active!
    if active.activity == .sideAcquisition {
      guard let direction = active.direction else {
        await refuseReservedAdmission(
          submission,
          environment: environment,
          operationID: operationID,
          reason: .sourceFactsChanged,
          remedy: .refreshCurrentFacts
        )
        return
      }
      let allowed = states[environment]!.authority.progress.allowedDirections
        .map(PlotterBoundaryDirection.init)
      let hasAccepted = states[environment]!.authority.aggregates[BoundaryDirection(direction)] != nil
      switch active.mode {
      case .normal where !allowed.contains(direction):
        await refuseReservedAdmission(
          submission,
          environment: environment,
          operationID: operationID,
          reason: .directionNotAllowed(direction),
          remedy: .choosePublishedDirection
        )
        return
      case .replacement where !hasAccepted, .additional where !hasAccepted:
        await refuseReservedAdmission(
          submission,
          environment: environment,
          operationID: operationID,
          reason: .acceptedDirectionRequired(direction),
          remedy: .recordRequiredDirection
        )
        return
      default:
        break
      }
    } else if states[environment]!.authority.center == nil {
      await refuseReservedAdmission(
        submission,
        environment: environment,
        operationID: operationID,
        reason: .centerUnavailable,
        remedy: .completeAllFourSides
      )
      return
    }

    states[environment]!.active?.admittedFacts = facts.effectIdentity
    states[environment]!.phase = active.direction.map(PlotterBoundaryPhase.admitting) ?? .centering
    advanceRevision(environment)
    await publish(environment)
    await execute(environment: environment, operationID: operationID)
  }

  private func refuseReservedAdmission(
    _ submission: PlotterBoundarySubmission,
    environment: PlotterEnvironment,
    operationID: PlotterBoundaryOperationID,
    reason: PlotterBoundaryRefusalReason,
    remedy: PlotterBoundaryRemedy
  ) async {
    guard let active = states[environment]!.active,
      active.operationID == operationID
    else { return }
    let provisional = PlotterBoundaryRefusal(
      requestID: submission.requestID,
      reason: reason,
      remedy: remedy,
      currentProjection: snapshot(for: environment).projection.reference
    )
    states[environment]!.lastRefusal = provisional
    await publishTerminal(
      environment,
      terminal: makeTerminal(
        active,
        disposition: .refused(String(describing: reason)),
        finalPosition: nil
      )
    )
    let settled = PlotterBoundaryRefusal(
      requestID: submission.requestID,
      reason: reason,
      remedy: remedy,
      currentProjection: snapshot(for: environment).projection.reference
    )
    states[environment]!.lastRefusal = settled
    states[environment]!.phase = .refused(reason)
    advanceRevision(environment)
    await publish(environment)
  }

  private func execute(
    environment: PlotterEnvironment,
    operationID: PlotterBoundaryOperationID
  ) async {
    guard let active = states[environment]!.active,
      active.operationID == operationID,
      let admittedFacts = active.admittedFacts
    else { return }
    if await cancelBeforeLowerIfNeeded(environment, operationID: operationID) { return }
    let fresh = await factSource.currentBoundaryFacts(for: environment)
    guard fresh.effectIdentity == admittedFacts else {
      await settleWithoutLower(
        environment,
        operationID: operationID,
        disposition: .refused("Effect-relevant Boundary facts changed before lower admission."),
        detail: "Effect-relevant Boundary facts changed before lower admission."
      )
      return
    }

    states[environment]!.phase = active.direction.map(PlotterBoundaryPhase.normalizingPenUp)
      ?? .normalizingPenUpForCenter
    advanceRevision(environment)
    await publish(environment)
    let preparation = await effectPort.preparePenUp(
      environment: environment,
      profile: fresh.penActuationProfile
    )
    switch preparation {
    case .success:
      break
    case .failure(let failure):
      await settleWithoutLower(
        environment,
        operationID: operationID,
        disposition: failure.ambiguous ? .ambiguous(failure.detail) : .refused(failure.detail),
        detail: failure.detail
      )
      return
    }
    if await cancelBeforeLowerIfNeeded(environment, operationID: operationID) { return }

    if active.activity == .sideAcquisition, let direction = active.direction {
      states[environment]!.phase = .admitting(direction: direction)
      advanceRevision(environment)
      await publish(environment)
      if await cancelBeforeLowerIfNeeded(environment, operationID: operationID) { return }
      let advisory = await effectPort.prepareSideAdvisory(
        environment: environment,
        direction: direction
      )
      if await cancelBeforeLowerIfNeeded(environment, operationID: operationID) { return }
      if case .failure(let failure) = advisory {
        await settleWithoutLower(
          environment,
          operationID: operationID,
          disposition: failure.ambiguous
            ? .ambiguous(failure.detail)
            : .refused(failure.detail),
          detail: failure.detail
        )
        return
      }
    }

    let beforeEffect: PlotterBoundaryExternalFacts
    let admission: PlotterBoundaryLowerAdmission
    if active.activity == .sideAcquisition {
      states[environment]!.phase = .moving(direction: active.direction!)
      advanceRevision(environment)
      await publish(environment)
      if await cancelBeforeLowerIfNeeded(environment, operationID: operationID) { return }
      guard let revalidated = await freshEffectFactsBeforeLower(
        environment,
        operationID: operationID,
        admittedFacts: admittedFacts
      ) else { return }
      beforeEffect = revalidated
      admission = await effectPort.admitSide(
        environment: environment,
        direction: active.direction!
      )
    } else {
      states[environment]!.phase = .centering
      advanceRevision(environment)
      await publish(environment)
      if await cancelBeforeLowerIfNeeded(environment, operationID: operationID) { return }
      guard let revalidated = await freshEffectFactsBeforeLower(
        environment,
        operationID: operationID,
        admittedFacts: admittedFacts
      ) else { return }
      beforeEffect = revalidated
      guard let position = beforeEffect.machinePosition,
        let center = states[environment]!.authority.center
      else {
        await settleWithoutLower(
          environment,
          operationID: operationID,
          disposition: .refused("The exact current machine position or accepted center is unavailable."),
          detail: "The exact current machine position or accepted center is unavailable."
        )
        return
      }
      let delta = try! Vector2<MachineSpace>(
        dx: center.point.x - position.point.x,
        dy: center.point.y - position.point.y
      )
      admission = await effectPort.admitCenterTravel(
        environment: environment,
        delta: delta
      )
    }

    let handle: PlotterBoundaryLowerHandle
    switch admission {
    case .admitted(let admitted):
      handle = admitted
    case .refused(let detail):
      await settleWithoutLower(
        environment,
        operationID: operationID,
        disposition: .refused(detail),
        detail: detail
      )
      return
    case .ambiguous(let detail):
      await settleWithoutLower(
        environment,
        operationID: operationID,
        disposition: .ambiguous(detail),
        detail: detail
      )
      return
    }

    guard states[environment]!.active?.operationID == operationID else { return }
    states[environment]!.active?.lowerHandle = handle
    if let cancellation = states[environment]!.active?.cancellation {
      states[environment]!.active?.cancellationSent = true
      await effectPort.requestCancellation(cancellation, handle: handle)
    }
    let terminal = await effectPort.waitForTerminal(handle)
    await terminalPublicationGate?.arriveAndWaitIfHeld()
    await settleLowerTerminal(
      environment,
      operationID: operationID,
      handle: handle,
      lowerTerminal: terminal,
      facts: beforeEffect
    )
  }

  private func freshEffectFactsBeforeLower(
    _ environment: PlotterEnvironment,
    operationID: PlotterBoundaryOperationID,
    admittedFacts: PlotterBoundaryExternalFacts.EffectIdentity
  ) async -> PlotterBoundaryExternalFacts? {
    let facts = await factSource.currentBoundaryFacts(for: environment)
    if await cancelBeforeLowerIfNeeded(environment, operationID: operationID) {
      return nil
    }
    guard states[environment]!.active?.operationID == operationID,
      facts.effectIdentity == admittedFacts,
      !states[environment]!.admissionClosed
    else {
      await settleWithoutLower(
        environment,
        operationID: operationID,
        disposition: .refused("Boundary facts changed before the first motion effect."),
        detail: "Boundary facts changed before the first motion effect."
      )
      return nil
    }
    return facts
  }

  private func cancelBeforeLowerIfNeeded(
    _ environment: PlotterEnvironment,
    operationID: PlotterBoundaryOperationID
  ) async -> Bool {
    guard let active = states[environment]!.active,
      active.operationID == operationID,
      let cancellation = active.cancellation
    else { return false }
    await settleWithoutLower(
      environment,
      operationID: operationID,
      disposition: cancellation == .shutdown ? .shutdown : .cancelled,
      detail: "The exact Boundary owner was cancelled before lower motion admission."
    )
    return true
  }

  private func settleLowerTerminal(
    _ environment: PlotterEnvironment,
    operationID: PlotterBoundaryOperationID,
    handle: PlotterBoundaryLowerHandle,
    lowerTerminal: PlotterBoundaryLowerTerminal,
    facts: PlotterBoundaryExternalFacts
  ) async {
    guard let active = states[environment]!.active,
      active.operationID == operationID,
      active.lowerHandle == handle
    else { return }
    let position: MachinePosition?
    let disposition: PlotterBoundaryTerminalDisposition
    let acceptsValue: Bool
    switch lowerTerminal {
    case .operatorStopped(let finalPosition, let idleVerified):
      position = finalPosition
      acceptsValue = active.activity == .sideAcquisition && idleVerified
      disposition = acceptsValue
        ? .accepted
        : .refused("The controller did not publish fresh Idle/final MPos for the exact Stop owner.")
    case .completed(let finalPosition, let idleVerified):
      position = finalPosition
      acceptsValue = active.activity == .centerArrival && idleVerified
      disposition = acceptsValue
        ? .accepted
        : .refused("Boundary side acquisition requires exact operator Stop; natural completion is not accepted.")
    case .cancelled(let finalPosition):
      position = finalPosition
      acceptsValue = false
      disposition = .cancelled
    case .shutdown(let finalPosition):
      position = finalPosition
      acceptsValue = false
      disposition = .shutdown
    case .refused(let detail, let finalPosition):
      position = finalPosition
      acceptsValue = false
      disposition = .refused(detail)
    case .ambiguous(let detail, let finalPosition):
      position = finalPosition
      acceptsValue = false
      disposition = .ambiguous(detail)
    }
    let terminal = makeTerminal(
      active,
      disposition: disposition,
      finalPosition: position
    )
    guard acceptsValue, let position else {
      await publishTerminal(environment, terminal: terminal)
      return
    }
    do {
      var authority = states[environment]!.authority
      if active.activity == .sideAcquisition {
        authority = try stageAcceptedSide(
          authority,
          active: active,
          handle: handle,
          finalPosition: position,
          facts: facts
        )
      } else {
        authority = try stageAcceptedCenter(
          authority,
          active: active,
          finalPosition: position
        )
      }
      if environment == .simulated {
        installAcceptedAuthority(authority, environment: environment)
        await publishTerminal(environment, terminal: terminal)
        return
      }
      guard let probe = facts.passiveProbe else {
        await publishTerminal(
          environment,
          terminal: makeTerminal(
            active,
            disposition: .ambiguous("The fresh controller probe disappeared before persistence."),
            finalPosition: position
          )
        )
        return
      }
      let candidate = try persistenceCandidate(
        environment: environment,
        authority: authority,
        position: position,
        facts: facts,
        probe: probe
      )
      authority.checkpoint = candidate.machineArtifacts
      states[environment]!.phase = .publishing
      advanceRevision(environment)
      await publish(environment)
      do {
        try await persistencePort.persistBoundaryCandidate(candidate)
        guard states[environment]!.active?.operationID == operationID else { return }
        installAcceptedAuthority(authority, environment: environment)
        await publishTerminal(environment, terminal: terminal)
      } catch {
        let capability = PlotterBoundaryPublicationRecoveryCapabilityID()
        states[environment]!.pendingPublication = PendingPublication(
          capabilityID: capability,
          authority: authority,
          candidate: candidate,
          terminal: terminal
        )
        states[environment]!.phase = .publicationIncomplete(capability)
        states[environment]!.terminal = makeTerminal(
          active,
          disposition: .publicationIncomplete(String(describing: error)),
          finalPosition: position
        )
        states[environment]!.active = nil
        operationTasks[environment] = nil
        advanceRevision(environment)
        await publish(environment)
      }
    } catch {
      let detail = (error as? LocalizedError)?.errorDescription
        ?? String(describing: error)
      await publishTerminal(
        environment,
        terminal: makeTerminal(
          active,
          disposition: .ambiguous(detail),
          finalPosition: position
        )
      )
    }
  }

  private func stageAcceptedSide(
    _ original: Authority,
    active: ActiveOperation,
    handle: PlotterBoundaryLowerHandle,
    finalPosition: MachinePosition,
    facts: PlotterBoundaryExternalFacts
  ) throws -> Authority {
    var authority = original
    let direction = BoundaryDirection(active.direction!)
    let attemptID = ExerciseAttemptID(rawValue: active.attemptID.rawValue)
    let revision = LearningArtifactRevision(
      kind: .boundarySideAggregate(direction),
      attemptID: attemptID,
      disposition: .succeeded,
      state: .current
    )
    let evidence = try BoundarySideAttemptEvidence(
      attemptID: attemptID,
      direction: direction,
      controllerSessionID: facts.controllerSessionID,
      coordinateRevision: facts.coordinateRevision,
      ownerID: BoundaryMotionOwnerID(rawValue: handle.lowerOwnerID),
      stopCapabilityID: handle.cancellationCapabilityID,
      stopIntent: .operatorStop,
      finalPosition: finalPosition,
      disposition: .succeeded
    )
    let compatibility = BoundaryNumericCompatibility(
      direction: direction,
      controllerSessionID: facts.controllerSessionID,
      coordinateRevision: facts.coordinateRevision,
      numericEstimatorRevision: "boundary-machine-coordinate-v1"
    ).attemptCompatibility
    var history = try authority.histories[direction]
      ?? ExerciseAttemptHistory(compatibility: compatibility)
    authority.acceptedSequence &+= 1
    let attempt = try ExerciseAttempt(
      id: attemptID,
      disposition: .succeeded,
      compatibility: compatibility,
      acceptedSequence: authority.acceptedSequence,
      value: evidence
    )
    if active.mode == .replacement, !history.includedSuccessfulAttempts.isEmpty {
      try history.recordWholeIncludedSetReplacement(attempt)
    } else {
      try history.record(attempt)
    }
    let aggregate = try BoundarySideAggregate(
      direction: direction,
      revisionID: revision.id,
      history: history
    )
    authority.histories[direction] = history
    authority.evidence.append(evidence)
    authority.aggregates[direction] = aggregate
    authority.revisions.removeAll { revision in
      if case .boundarySideAggregate(let currentDirection) = revision.kind {
        return currentDirection == direction
      }
      return false
    }
    authority.revisions.append(revision)

    var progress = PairedBoundaryProgress()
    var ordered = authority.progress.acceptedDirections
    if !ordered.contains(direction) { ordered.append(direction) }
    for acceptedDirection in ordered {
      guard let accepted = authority.aggregates[acceptedDirection] else { continue }
      try progress.accept(acceptedDirection, revisionID: accepted.revisionID)
    }
    authority.progress = progress
    if progress.isComplete {
      let values = BoundaryDirection.allCases.compactMap { authority.aggregates[$0] }
      authority.center = try EstimatedMachineCenter.derive(from: values)
      authority.localFrame = try LearnedLocalCoordinateFrame.derive(from: values)
      let centerRevision = LearningArtifactRevision(
        kind: .estimatedMachineCenter,
        attemptID: attemptID,
        disposition: .succeeded,
        consumedRevisionIDs: authority.center!.consumedRevisionIDs,
        state: .current
      )
      authority.revisions.removeAll { $0.kind == .estimatedMachineCenter }
      authority.revisions.append(centerRevision)
      authority.centerArrival = nil
    } else {
      authority.center = nil
      authority.localFrame = nil
      authority.centerArrival = nil
      authority.revisions.removeAll {
        $0.kind == .estimatedMachineCenter || $0.kind == .centerArrival
      }
    }
    return authority
  }

  private func stageAcceptedCenter(
    _ original: Authority,
    active: ActiveOperation,
    finalPosition: MachinePosition
  ) throws -> Authority {
    var authority = original
    guard let center = authority.center,
      let centerRevision = authority.revisions.first(where: {
        $0.kind == .estimatedMachineCenter && $0.state == .current
      })
    else { throw PlotterBoundaryRestoreError.incompleteBoundary }
    let residual = MachinePositionAcceptancePolicy.residualMM(
      finalPosition,
      from: MachinePosition(point: center.point)
    )
    guard MachinePositionAcceptancePolicy.accepts(residualMM: residual) else {
      throw PlotterBoundaryRestoreError.centerResidualExceeded(residual)
    }
    authority.centerArrival = finalPosition
    let attemptID = ExerciseAttemptID(rawValue: active.attemptID.rawValue)
    authority.revisions.removeAll { $0.kind == .centerArrival }
    authority.revisions.append(
      LearningArtifactRevision(
        kind: .centerArrival,
        attemptID: attemptID,
        disposition: .succeeded,
        consumedRevisionIDs: [centerRevision.id],
        state: .current
      )
    )
    return authority
  }

  private func persistenceCandidate(
    environment: PlotterEnvironment,
    authority: Authority,
    position: MachinePosition,
    facts: PlotterBoundaryExternalFacts,
    probe: PassiveProbeResult
  ) throws -> PlotterBoundaryPersistenceCandidate {
    let checkpoint = try AcceptedMachineArtifactCheckpoint(
      controllerContext: try ControllerCheckpointContext(probe: probe),
      machinePositionAtSave: position,
      controllerSessionID: facts.controllerSessionID,
      coordinateRevision: facts.coordinateRevision,
      acceptedAttemptSequence: authority.acceptedSequence,
      pairedBoundaryProgress: authority.progress,
      acceptedBoundaryEvidence: authority.evidence,
      boundarySideAggregates: BoundaryDirection.allCases.compactMap { authority.aggregates[$0] },
      estimatedMachineCenter: authority.center,
      learnedLocalCoordinateFrame: authority.localFrame,
      centerArrivalPosition: authority.centerArrival,
      acceptedRevisions: authority.revisions
    )
    return PlotterBoundaryPersistenceCandidate(
      environment: environment,
      semanticIdentity: facts.semanticIdentity,
      machineArtifacts: checkpoint
    )
  }

  private func cancelActive(
    _ submission: PlotterBoundarySubmission,
    capability: PlotterBoundaryCancellationCapabilityID,
    intent: PlotterBoundaryCancellationIntent
  ) async -> PlotterBoundaryDisposition {
    let environment = submission.projection.environment
    guard var active = states[environment]!.active,
      !active.terminalPublicationStarted
    else {
      return refusal(
        submission,
        reason: .cancellationCapabilityMismatch,
        remedy: .useExactCancellationCapability
      )
    }
    guard active.capabilityID == capability else {
      return refusal(
        submission,
        reason: .cancellationCapabilityMismatch,
        remedy: .useExactCancellationCapability
      )
    }
    let operationTask = operationTasks[environment]
    if active.cancellation == nil { active.cancellation = intent }
    states[environment]!.active = active
    states[environment]!.phase = .cancelling(active.cancellation!)
    advanceRevision(environment)
    await publish(environment)
    if let current = states[environment]!.active,
      current.operationID == active.operationID,
      let handle = current.lowerHandle,
      !current.cancellationSent
    {
      states[environment]!.active?.cancellationSent = true
      await effectPort.requestCancellation(current.cancellation ?? active.cancellation!, handle: handle)
    }
    if let operationTask { await operationTask.value }
    return .applied(snapshot(for: environment).projection)
  }

  private func recoverPublication(
    _ submission: PlotterBoundarySubmission,
    capability: PlotterBoundaryPublicationRecoveryCapabilityID
  ) async -> PlotterBoundaryDisposition {
    let environment = submission.projection.environment
    guard let pending = states[environment]!.pendingPublication,
      pending.capabilityID == capability
    else {
      return refusal(
        submission,
        reason: .publicationRecoveryCapabilityMismatch,
        remedy: .retryExactPublication
      )
    }
    states[environment]!.phase = .publishing
    advanceRevision(environment)
    await publish(environment)
    do {
      try await persistencePort.persistBoundaryCandidate(pending.candidate)
      guard states[environment]!.pendingPublication?.capabilityID == capability else {
        return refusal(
          submission,
          reason: .publicationRecoveryCapabilityMismatch,
          remedy: .retryExactPublication
        )
      }
      installAcceptedAuthority(pending.authority, environment: environment)
      states[environment]!.pendingPublication = nil
      states[environment]!.terminal = pending.terminal
      states[environment]!.terminals.append(pending.terminal)
      states[environment]!.phase = .idle
      advanceRevision(environment)
      await publish(environment)
      return .applied(snapshot(for: environment).projection)
    } catch {
      states[environment]!.phase = .publicationIncomplete(capability)
      advanceRevision(environment)
      await publish(environment)
      return refusal(
        submission,
        reason: .persistenceFailed(String(describing: error)),
        remedy: .retryExactPublication
      )
    }
  }

  private func settleWithoutLower(
    _ environment: PlotterEnvironment,
    operationID: PlotterBoundaryOperationID,
    disposition: PlotterBoundaryTerminalDisposition,
    detail: String
  ) async {
    guard let active = states[environment]!.active,
      active.operationID == operationID
    else { return }
    let terminal = makeTerminal(active, disposition: disposition, finalPosition: nil)
    await publishTerminal(environment, terminal: terminal)
  }

  private func installAcceptedAuthority(
    _ authority: Authority,
    environment: PlotterEnvironment
  ) {
    states[environment]!.authority = authority
    let allowed = authority.progress.allowedDirections.map(PlotterBoundaryDirection.init)
    guard !allowed.contains(states[environment]!.selectedDirection) else { return }
    states[environment]!.selectedDirection = allowed.first ?? .negativeX
  }

  private func publishTerminal(
    _ environment: PlotterEnvironment,
    terminal: PlotterBoundaryTerminal
  ) async {
    guard var active = states[environment]!.active,
      active.operationID == terminal.operationID,
      !active.terminalPublicationStarted
    else { return }
    active.terminalPublicationStarted = true
    states[environment]!.active = active
    states[environment]!.terminal = terminal
    states[environment]!.terminals.append(terminal)
    states[environment]!.phase = .publishing
    advanceRevision(environment)
    await publish(environment)
    guard states[environment]!.active?.operationID == terminal.operationID,
      states[environment]!.active?.terminalPublicationStarted == true
    else { return }
    states[environment]!.active = nil
    states[environment]!.phase = terminal.disposition == .accepted ? .idle : .needsAttention(
      String(describing: terminal.disposition)
    )
    operationTasks[environment] = nil
    advanceRevision(environment)
    await publish(environment)
  }

  private func makeTerminal(
    _ active: ActiveOperation,
    disposition: PlotterBoundaryTerminalDisposition,
    finalPosition: MachinePosition?
  ) -> PlotterBoundaryTerminal {
    PlotterBoundaryTerminal(
      attemptID: active.attemptID,
      operationID: active.operationID,
      activity: active.activity,
      direction: active.direction,
      disposition: disposition,
      finalPosition: finalPosition.map {
        PlotterBoundaryPositionSummary(xMM: $0.point.x, yMM: $0.point.y)
      },
      physicalEvidenceClaimed: false
    )
  }

  private func refusal(
    _ submission: PlotterBoundarySubmission,
    reason: PlotterBoundaryRefusalReason,
    remedy: PlotterBoundaryRemedy
  ) -> PlotterBoundaryDisposition {
    let environment = submission.projection.environment
    let refusal = PlotterBoundaryRefusal(
      requestID: submission.requestID,
      reason: reason,
      remedy: remedy,
      currentProjection: snapshot(for: environment).projection.reference
    )
    states[environment]!.lastRefusal = refusal
    return .refused(refusal)
  }

  private func advanceRevision(_ environment: PlotterEnvironment) {
    states[environment]!.revision = PlotterBoundaryRevision(
      rawValue: states[environment]!.revision.rawValue &+ 1
    )
  }

  private func publish(_ environment: PlotterEnvironment) async {
    guard let projectionSink else { return }
    await projectionSink.publishBoundarySnapshot(snapshot(for: environment))
  }
}

public enum PlotterBoundaryRestoreError: Error, LocalizedError, Hashable, Sendable {
  case activeOwner
  case incompleteBoundary
  case centerResidualExceeded(Double)

  public var errorDescription: String? {
    switch self {
    case .activeOwner:
      return "Boundary restore is unavailable while an exact Boundary operation, publication recovery, or reset transaction owns the runtime."
    case .incompleteBoundary:
      return "The accepted Boundary does not currently provide both an estimated center and its current revision; center arrival was not accepted."
    case .centerResidualExceeded(let residual):
      let residualDescription = residual.isFinite
        ? "\(String(format: "%.3f", residual)) mm"
        : "non-finite residual"
      let toleranceDescription = String(
        format: "%.3f",
        MachinePositionAcceptancePolicy.toleranceMM
      )
      return "The reported center-arrival position has a \(residualDescription), outside the \(toleranceDescription) mm tolerance."
    }
  }
}

private extension PlotterBoundaryDirection {
  init(_ direction: BoundaryDirection) {
    self = PlotterBoundaryDirection(rawValue: direction.rawValue)!
  }
}

private extension BoundaryDirection {
  init(_ direction: PlotterBoundaryDirection) {
    self = BoundaryDirection(rawValue: direction.rawValue)!
  }
}
