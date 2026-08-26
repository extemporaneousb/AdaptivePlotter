import EpisodeCore
import Foundation

package enum PlotterOperationLaneRole: String, Hashable, Sendable {
  case machine
  case exactWorkflowCaptureVision
  case backgroundAnalysis
  case durableAppend
}

package enum PlotterOperationLaneConfigurationError<Lane>: Error, Equatable, Sendable
where Lane: Hashable & Sendable {
  case duplicateLane(Lane)
  case invalidBackgroundAnalysisLimit(Int)
}

/// Typed lane identities and their fixed runtime admission semantics.
///
/// Lane values come from the model that composes this unbound foundation. The
/// registry therefore remains independent of PlotterEpisodeModel while still
/// refusing untyped/string-selected lanes and inconsistent per-call capacity.
package struct PlotterOperationLaneConfiguration<Lane>: Sendable
where Lane: Hashable & Sendable {
  package let machine: Lane
  package let exactWorkflowCaptureVision: Lane
  package let backgroundAnalysis: Lane
  package let durableAppend: Lane
  package let backgroundAnalysisLimit: Int

  private let roleByLane: [Lane: PlotterOperationLaneRole]
  private let capacityByLane: [Lane: Int]

  package init(
    machine: Lane,
    exactWorkflowCaptureVision: Lane,
    backgroundAnalysis: Lane,
    durableAppend: Lane,
    backgroundAnalysisLimit: Int
  ) throws {
    guard backgroundAnalysisLimit > 0 else {
      throw PlotterOperationLaneConfigurationError<Lane>
        .invalidBackgroundAnalysisLimit(backgroundAnalysisLimit)
    }

    let definitions: [(Lane, PlotterOperationLaneRole, Int)] = [
      (machine, .machine, 1),
      (exactWorkflowCaptureVision, .exactWorkflowCaptureVision, 1),
      (backgroundAnalysis, .backgroundAnalysis, backgroundAnalysisLimit),
      (durableAppend, .durableAppend, 1),
    ]
    var roles: [Lane: PlotterOperationLaneRole] = [:]
    var capacities: [Lane: Int] = [:]
    for (lane, role, capacity) in definitions {
      guard roles[lane] == nil else {
        throw PlotterOperationLaneConfigurationError<Lane>.duplicateLane(lane)
      }
      roles[lane] = role
      capacities[lane] = capacity
    }

    self.machine = machine
    self.exactWorkflowCaptureVision = exactWorkflowCaptureVision
    self.backgroundAnalysis = backgroundAnalysis
    self.durableAppend = durableAppend
    self.backgroundAnalysisLimit = backgroundAnalysisLimit
    roleByLane = roles
    capacityByLane = capacities
  }

  fileprivate func role(for lane: Lane) -> PlotterOperationLaneRole? {
    roleByLane[lane]
  }

  fileprivate func capacity(for lane: Lane) -> Int? {
    capacityByLane[lane]
  }
}

/// Typed observable facts supplied by the composing model for one operation.
///
/// Intent and environment values do not live here. They are fields of the one
/// canonical `PlotterOperationIdentity`, so context cannot become a second
/// synchronized identity authority.
package protocol PlotterOperationContext: Hashable, Sendable {
  associatedtype IntentIdentity: Hashable & Sendable
  associatedtype Environment: Hashable & Sendable
  associatedtype AwaitedResult: Hashable & Sendable

  var owningSubsystem: EpisodeAuthorityID { get }
  var resultCurrentlyAwaited: AwaitedResult { get }
}

/// The one canonical identity for a registered Plotter operation.
package struct PlotterOperationIdentity<Context>: Hashable, Sendable
where Context: PlotterOperationContext {
  package let episodeID: EpisodeID
  package let requestID: IntentRequestID
  package let intentIdentity: Context.IntentIdentity
  package let effectID: EpisodeEffectID
  package let effectRevision: EpisodeRevisionIdentifier
  package let environment: Context.Environment

  package init(
    episodeID: EpisodeID,
    requestID: IntentRequestID,
    intentIdentity: Context.IntentIdentity,
    effectID: EpisodeEffectID,
    effectRevision: EpisodeRevisionIdentifier,
    environment: Context.Environment
  ) {
    self.episodeID = episodeID
    self.requestID = requestID
    self.intentIdentity = intentIdentity
    self.effectID = effectID
    self.effectRevision = effectRevision
    self.environment = environment
  }
}

/// Reference to one already-committed EpisodeCore event.
///
/// The registry validates attribution identity and ordering only. It neither
/// commits this event nor claims that the reference itself proves commitment;
/// later composition may supply it only after its EpisodeStore append returns.
package struct PlotterOperationEventAttribution<Context>: Hashable, Sendable
where Context: PlotterOperationContext {
  package let identity: PlotterOperationIdentity<Context>
  package let eventID: EpisodeEventID
  package let sequence: EpisodeEventSequence
  package let preStateRevision: EpisodeStateRevision
  package let postStateRevision: EpisodeStateRevision
  package let recordedAt: Date

  package init(
    identity: PlotterOperationIdentity<Context>,
    eventID: EpisodeEventID,
    sequence: EpisodeEventSequence,
    preStateRevision: EpisodeStateRevision,
    postStateRevision: EpisodeStateRevision,
    recordedAt: Date
  ) {
    self.identity = identity
    self.eventID = eventID
    self.sequence = sequence
    self.preStateRevision = preStateRevision
    self.postStateRevision = postStateRevision
    self.recordedAt = recordedAt
  }
}

package enum PlotterOperationAttributionRefusal<Context>: Equatable, Sendable
where Context: PlotterOperationContext {
  case identityMismatch(expected: PlotterOperationIdentity<Context>)
  case duplicateEventID(EpisodeEventID)
  case invalidStateRevisionTransition(
    pre: EpisodeStateRevision,
    post: EpisodeStateRevision
  )
  case eventSequenceRegression(
    previous: EpisodeEventSequence,
    actual: EpisodeEventSequence
  )
  case stateRevisionRegression(
    previousPost: EpisodeStateRevision,
    actualPre: EpisodeStateRevision
  )
  case timestampRegression(previous: Date, actual: Date)
}

/// Internal runtime permission. Its initializer is deliberately private: only
/// a successful registry admission can mint a value.
package struct EffectPermit<Context>: ~Copyable, Sendable
where Context: PlotterOperationContext {
  fileprivate let id: UUID
  package let identity: PlotterOperationIdentity<Context>

  private init(id: UUID, identity: PlotterOperationIdentity<Context>) {
    self.id = id
    self.identity = identity
  }

  fileprivate static func mint(for identity: PlotterOperationIdentity<Context>) -> Self {
    Self(id: UUID(), identity: identity)
  }
}

/// Revocable authority for one exact registered operation. It can neither mint
/// a permit nor identify a successor operation.
package struct StopCapability<Context>: Hashable, Sendable
where Context: PlotterOperationContext {
  fileprivate let id: UUID
  package let identity: PlotterOperationIdentity<Context>

  private init(id: UUID, identity: PlotterOperationIdentity<Context>) {
    self.id = id
    self.identity = identity
  }

  fileprivate static func mint(for identity: PlotterOperationIdentity<Context>) -> Self {
    Self(id: UUID(), identity: identity)
  }
}

/// Unforgeable authority for publishing one owner's terminal result. The
/// capability remains usable after settlement only to obtain deterministic
/// duplicate-versus-conflict classification for that same operation.
package struct CompletionCapability<Context>: Hashable, Sendable
where Context: PlotterOperationContext {
  fileprivate let id: UUID
  package let identity: PlotterOperationIdentity<Context>

  private init(id: UUID, identity: PlotterOperationIdentity<Context>) {
    self.id = id
    self.identity = identity
  }

  fileprivate static func mint(for identity: PlotterOperationIdentity<Context>) -> Self {
    Self(id: UUID(), identity: identity)
  }
}

/// The concrete handle retained by a registry is the original operation
/// handle, not an erased closure or a replacement cancellation task.
package protocol PlotterOperationHandle: Sendable {
  associatedtype OperationContext: PlotterOperationContext
  associatedtype TerminalDisposition: Hashable & Sendable

  func requestCancellation() async
  func waitForSettlement() async
    -> PlotterOperationResult<OperationContext, TerminalDisposition>
}

package enum PlotterOperationAdmissionState: String, Hashable, Sendable {
  case open
  case closed
}

package enum PlotterOperationLifecyclePhase: String, Hashable, Sendable {
  case waiting
  case progressing
  case cancelling
  case settling
  case suspectedStall
  case terminal
}

package enum PlotterOperationCancellationPhase: String, Hashable, Sendable {
  case notRequested
  case requested
  case observed
  case settling
  case refused
}

package enum PlotterOperationCancellationReason: String, Hashable, Sendable {
  case stop
  case shutdown
}

package enum PlotterOperationAdmissionError<Lane, Context>: Error, Equatable, Sendable
where Lane: Hashable & Sendable, Context: PlotterOperationContext {
  case admissionClosed
  case unconfiguredLane(Lane)
  case laneAtCapacity(lane: Lane, capacity: Int)
  case identityAlreadyKnown(PlotterOperationIdentity<Context>)
}

package enum EffectPermitConsumption<Context>: ~Copyable, Sendable
where Context: PlotterOperationContext {
  case accepted
  case admissionClosed
  case identityMismatch(
    expected: PlotterOperationIdentity<Context>,
    permit: EffectPermit<Context>
  )
  case attributionRefused(
    PlotterOperationAttributionRefusal<Context>,
    permit: EffectPermit<Context>
  )
  case retired
  case cancellationInProgress
}

package enum PlotterOperationProgressUpdate<Context>: Equatable, Sendable
where Context: PlotterOperationContext {
  case accepted
  case unknownIdentity
  case identityMismatch(expected: PlotterOperationIdentity<Context>)
  case notStarted
  case cancellationInProgress
  case alreadyTerminal
  case invalidLifecyclePhase
  case attributionRefused(PlotterOperationAttributionRefusal<Context>)
}

/// An owner-produced terminal result. Identity and settlement time travel with
/// the disposition through direct completion, Stop, and shutdown.
package struct PlotterOperationResult<Context, Disposition>: Hashable, Sendable
where Context: PlotterOperationContext, Disposition: Hashable & Sendable {
  package let identity: PlotterOperationIdentity<Context>
  package let disposition: Disposition
  package let settledAt: Date

  package init(
    identity: PlotterOperationIdentity<Context>,
    disposition: Disposition,
    settledAt: Date
  ) {
    self.identity = identity
    self.disposition = disposition
    self.settledAt = settledAt
  }
}

package enum PlotterOperationResultRefusal<Context, Disposition>:
  Error, Hashable, Sendable
where Context: PlotterOperationContext, Disposition: Hashable & Sendable {
  case identityMismatch(
    expected: PlotterOperationIdentity<Context>,
    actual: PlotterOperationIdentity<Context>
  )
  case terminalResultMismatch(
    expected: PlotterOperationResult<Context, Disposition>,
    actual: PlotterOperationResult<Context, Disposition>
  )
}

package enum PlotterOperationSettlement<Lane, Context, Disposition>: Equatable, Sendable
where Lane: Hashable & Sendable,
      Context: PlotterOperationContext,
      Disposition: Hashable & Sendable {
  case accepted(PlotterOperationTerminalRecord<Lane, Context, Disposition>)
  case unknownCompletionCapability
  case refused(PlotterOperationResultRefusal<Context, Disposition>)
  case notStarted
  case cancellationInProgress
  case duplicate(PlotterOperationTerminalRecord<Lane, Context, Disposition>)
}

package enum PlotterOperationStopOutcome<Lane, Context, Disposition>: Equatable, Sendable
where Lane: Hashable & Sendable,
      Context: PlotterOperationContext,
      Disposition: Hashable & Sendable {
  case settled(PlotterOperationTerminalRecord<Lane, Context, Disposition>)
  case resultRefused(PlotterOperationResultRefusal<Context, Disposition>)
  case alreadyRequested
  case unknownCapability
  case retiredCapability
  case identityMismatch
}

package struct PlotterOperationRegistration<Context>: ~Copyable, Sendable
where Context: PlotterOperationContext {
  private let permit: EffectPermit<Context>
  package let stopCapability: StopCapability<Context>?
  package let completionCapability: CompletionCapability<Context>

  fileprivate init(
    permit: consuming EffectPermit<Context>,
    stopCapability: StopCapability<Context>?,
    completionCapability: CompletionCapability<Context>
  ) {
    self.permit = permit
    self.stopCapability = stopCapability
    self.completionCapability = completionCapability
  }

  package consuming func takePermit() -> EffectPermit<Context> {
    permit
  }
}

package struct PlotterActiveOperationSnapshot<Lane, Context, Disposition>: Sendable
where Lane: Hashable & Sendable,
      Context: PlotterOperationContext,
      Disposition: Hashable & Sendable {
  package let identity: PlotterOperationIdentity<Context>
  package let lane: Lane
  package let laneRole: PlotterOperationLaneRole
  package let context: Context
  package let owningSubsystem: EpisodeAuthorityID
  package let resultCurrentlyAwaited: Context.AwaitedResult
  package let phase: PlotterOperationLifecyclePhase
  package let admittedAt: Date
  package let startedAt: Date?
  package let lastAttributableProgressAt: Date?
  package let lastAcceptedAttribution: PlotterOperationEventAttribution<Context>?
  package let deadline: Date?
  package let cancellationAvailable: Bool
  package let cancellationPhase: PlotterOperationCancellationPhase
  package let cancellationReason: PlotterOperationCancellationReason?
  package let lastCancellationResultRefusal: PlotterOperationResultRefusal<Context, Disposition>?
  package let stopCapability: StopCapability<Context>?
}

package struct PlotterOperationTerminalRecord<Lane, Context, Disposition>:
  Hashable, Sendable
where Lane: Hashable & Sendable,
      Context: PlotterOperationContext,
      Disposition: Hashable & Sendable {
  package let result: PlotterOperationResult<Context, Disposition>
  package let lane: Lane
  package let laneRole: PlotterOperationLaneRole
  package let context: Context
  package let owningSubsystem: EpisodeAuthorityID
  package let resultCurrentlyAwaited: Context.AwaitedResult
  package let phase: PlotterOperationLifecyclePhase
  package let admittedAt: Date
  package let startedAt: Date?
  package let lastAttributableProgressAt: Date?
  package let lastAcceptedAttribution: PlotterOperationEventAttribution<Context>?
  package let deadline: Date?
  package let cancellationAvailable: Bool
  package let cancellationPhase: PlotterOperationCancellationPhase
  package let cancellationReason: PlotterOperationCancellationReason?
  package let lastCancellationResultRefusal: PlotterOperationResultRefusal<Context, Disposition>?

  package var identity: PlotterOperationIdentity<Context> { result.identity }
  package var disposition: Disposition { result.disposition }
  package var settledAt: Date { result.settledAt }
}

package struct PlotterOperationRegistrySnapshot<Lane, Context, Disposition>: Sendable
where Lane: Hashable & Sendable,
      Context: PlotterOperationContext,
      Disposition: Hashable & Sendable {
  package let revision: UInt64
  package let lastChangedAt: Date
  package let admission: PlotterOperationAdmissionState
  package let active: [PlotterActiveOperationSnapshot<Lane, Context, Disposition>]
  package let terminal: [PlotterOperationTerminalRecord<Lane, Context, Disposition>]
}

package struct PlotterOperationShutdownReport<Lane, Context, Disposition>: Sendable
where Lane: Hashable & Sendable,
      Context: PlotterOperationContext,
      Disposition: Hashable & Sendable {
  package let admissionWasAlreadyClosed: Bool
  package let settled: [PlotterOperationTerminalRecord<Lane, Context, Disposition>]
  package let resultRefusals: [PlotterOperationResultRefusal<Context, Disposition>]
}

private struct ActiveOperation<Lane, Context, Handle>
where Lane: Hashable & Sendable,
      Context: PlotterOperationContext,
      Handle: PlotterOperationHandle,
      Handle.OperationContext == Context {
  let identity: PlotterOperationIdentity<Context>
  let lane: Lane
  let laneRole: PlotterOperationLaneRole
  let context: Context
  let handle: Handle
  var permitID: UUID?
  let stopCapability: StopCapability<Context>?
  let completionCapability: CompletionCapability<Context>
  let admittedAt: Date
  let deadline: Date?
  var phase: PlotterOperationLifecyclePhase
  var startedAt: Date?
  var lastAcceptedAttribution: PlotterOperationEventAttribution<Context>?
  var cancellationPhase: PlotterOperationCancellationPhase
  var cancellationReason: PlotterOperationCancellationReason?
  var cancellationOwnerID: UUID?
  var lastCancellationAttemptOwnerID: UUID?
  var lastCancellationResultRefusal:
    PlotterOperationResultRefusal<Context, Handle.TerminalDisposition>?
  var cancellationAttemptWaiters: [CheckedContinuation<
    PlotterOperationCancellationAttemptOutcome<
      Lane,
      Context,
      Handle.TerminalDisposition
    >,
    Never
  >]
}

private struct CancellationLease<Context, Handle>: Sendable
where Context: PlotterOperationContext,
      Handle: PlotterOperationHandle,
      Handle.OperationContext == Context {
  let identity: PlotterOperationIdentity<Context>
  let ownerID: UUID
  let handle: Handle
}

private struct CancellationAttemptReference<Context>: Sendable
where Context: PlotterOperationContext {
  let identity: PlotterOperationIdentity<Context>
  let ownerID: UUID
}

private enum PlotterOperationCancellationAttemptOutcome<Lane, Context, Disposition>:
  Sendable
where Lane: Hashable & Sendable,
      Context: PlotterOperationContext,
      Disposition: Hashable & Sendable {
  case settled(PlotterOperationTerminalRecord<Lane, Context, Disposition>)
  case refused(PlotterOperationResultRefusal<Context, Disposition>)
}

private enum CancellationFinish<Terminal, Refusal> {
  case settled(Terminal)
  case refused(Refusal)
  case noLongerOwner
}

/// Application-level owner for admitted effect operations.
///
/// This Foundation service deliberately has no effect runner, journal, device
/// adapter, or production composition. It owns only admission, the supplied
/// original typed handle, exact cancellation authority, settlement, and
/// inspectable lifecycle state.
package actor PlotterOperationRegistry<Lane, Context, Handle>
where Lane: Hashable & Sendable,
      Context: PlotterOperationContext,
      Handle: PlotterOperationHandle,
      Handle.OperationContext == Context {
  package typealias Identity = PlotterOperationIdentity<Context>
  package typealias Disposition = Handle.TerminalDisposition
  package typealias Result = PlotterOperationResult<Context, Disposition>
  package typealias ResultRefusal = PlotterOperationResultRefusal<Context, Disposition>
  package typealias TerminalRecord = PlotterOperationTerminalRecord<Lane, Context, Disposition>
  package typealias Settlement = PlotterOperationSettlement<Lane, Context, Disposition>
  package typealias StopOutcome = PlotterOperationStopOutcome<Lane, Context, Disposition>
  private typealias CancellationOutcome =
    PlotterOperationCancellationAttemptOutcome<Lane, Context, Disposition>

  private let lanes: PlotterOperationLaneConfiguration<Lane>
  private var admission: PlotterOperationAdmissionState = .open
  private var activeByIdentity: [Identity: ActiveOperation<Lane, Context, Handle>] = [:]
  private var activeCapabilityIdentity: [UUID: Identity] = [:]
  private var completionCapabilityIdentity: [UUID: Identity] = [:]
  private var retiredCapabilityIDs: Set<UUID> = []
  private var retiredPermitIDs: Set<UUID> = []
  private var acceptedAttributionEventIDs: Set<EpisodeEventID> = []
  private var terminalByIdentity: [Identity: TerminalRecord] = [:]
  private var terminalRecords: [TerminalRecord] = []
  private var cancellationAttemptOutcomes: [UUID: CancellationOutcome] = [:]
  private var cancellationAttemptObserverCounts: [UUID: Int] = [:]
  private var revision: UInt64 = 0
  private var lastChangedAt: Date

  package init(
    lanes: PlotterOperationLaneConfiguration<Lane>,
    openedAt: Date = Date()
  ) {
    self.lanes = lanes
    lastChangedAt = openedAt
  }

  package func register(
    identity: Identity,
    lane: Lane,
    context: Context,
    handle: Handle,
    cancellationAvailable: Bool,
    admittedAt: Date = Date(),
    deadline: Date? = nil
  ) throws -> PlotterOperationRegistration<Context> {
    guard admission == .open else {
      throw PlotterOperationAdmissionError<Lane, Context>.admissionClosed
    }
    guard let laneRole = lanes.role(for: lane), let capacity = lanes.capacity(for: lane) else {
      throw PlotterOperationAdmissionError<Lane, Context>.unconfiguredLane(lane)
    }
    if let known = activeByIdentity.values.first(where: {
      $0.identity.effectID == identity.effectID
    }) {
      throw PlotterOperationAdmissionError<Lane, Context>.identityAlreadyKnown(known.identity)
    }
    if let known = terminalRecords.first(where: {
      $0.identity.effectID == identity.effectID
    }) {
      throw PlotterOperationAdmissionError<Lane, Context>.identityAlreadyKnown(known.identity)
    }
    let occupancy = activeByIdentity.values.lazy.filter { $0.lane == lane }.count
    guard occupancy < capacity else {
      throw PlotterOperationAdmissionError<Lane, Context>.laneAtCapacity(
        lane: lane,
        capacity: capacity
      )
    }

    let permit = EffectPermit.mint(for: identity)
    let stopCapability = cancellationAvailable ? StopCapability.mint(for: identity) : nil
    let completionCapability = CompletionCapability.mint(for: identity)
    activeByIdentity[identity] = ActiveOperation(
      identity: identity,
      lane: lane,
      laneRole: laneRole,
      context: context,
      handle: handle,
      permitID: permit.id,
      stopCapability: stopCapability,
      completionCapability: completionCapability,
      admittedAt: admittedAt,
      deadline: deadline,
      phase: .waiting,
      startedAt: nil,
      lastAcceptedAttribution: nil,
      cancellationPhase: .notRequested,
      cancellationReason: nil,
      cancellationOwnerID: nil,
      lastCancellationAttemptOwnerID: nil,
      lastCancellationResultRefusal: nil,
      cancellationAttemptWaiters: []
    )
    if let stopCapability {
      activeCapabilityIdentity[stopCapability.id] = identity
    }
    completionCapabilityIdentity[completionCapability.id] = identity
    touch(at: admittedAt)
    return PlotterOperationRegistration(
      permit: permit,
      stopCapability: stopCapability,
      completionCapability: completionCapability
    )
  }

  /// Moves one exact permit into the registry and records start before the
  /// caller invokes its external environment owner. Recoverable validation
  /// refusals return the same move-only authority without changing registry
  /// state. Success, admission closure, cancellation, and retirement consume
  /// it permanently.
  package func start(
    _ permit: consuming EffectPermit<Context>,
    for identity: Identity,
    attributedTo attribution: PlotterOperationEventAttribution<Context>
  ) -> EffectPermitConsumption<Context> {
    let permitID = permit.id
    let permitIdentity = permit.identity
    guard var active = activeByIdentity[permitIdentity] else {
      precondition(
        retiredPermitIDs.remove(permitID) != nil,
        "a privately minted permit must remain active or be retired"
      )
      return .retired
    }
    precondition(
      active.identity == permitIdentity && active.permitID == permitID,
      "a privately minted noncopyable permit must match its active registration"
    )
    guard admission == .open else {
      active.permitID = nil
      activeByIdentity[permitIdentity] = active
      return .admissionClosed
    }
    guard permitIdentity == identity else {
      return .identityMismatch(expected: permitIdentity, permit: permit)
    }
    guard active.cancellationOwnerID == nil else {
      active.permitID = nil
      activeByIdentity[permitIdentity] = active
      return .cancellationInProgress
    }
    if let refusal = attributionRefusal(
      attribution,
      for: active,
      previous: nil
    ) {
      return .attributionRefused(refusal, permit: permit)
    }

    active.permitID = nil
    active.phase = .progressing
    active.startedAt = attribution.recordedAt
    active.lastAcceptedAttribution = attribution
    activeByIdentity[identity] = active
    acceptedAttributionEventIDs.insert(attribution.eventID)
    touch(at: attribution.recordedAt)
    return .accepted
  }

  package func recordProgress(
    for identity: Identity,
    phase: PlotterOperationLifecyclePhase,
    attributedTo attribution: PlotterOperationEventAttribution<Context>
  ) -> PlotterOperationProgressUpdate<Context> {
    guard var active = activeByIdentity[identity] else {
      if terminalByIdentity[identity] != nil { return .alreadyTerminal }
      return .unknownIdentity
    }
    guard active.identity == identity else {
      return .identityMismatch(expected: active.identity)
    }
    guard active.startedAt != nil else { return .notStarted }
    guard active.cancellationOwnerID == nil else { return .cancellationInProgress }
    guard phase == .waiting || phase == .progressing || phase == .suspectedStall else {
      return .invalidLifecyclePhase
    }
    if let refusal = attributionRefusal(
      attribution,
      for: active,
      previous: active.lastAcceptedAttribution
    ) {
      return .attributionRefused(refusal)
    }

    active.phase = phase
    active.lastAcceptedAttribution = attribution
    activeByIdentity[identity] = active
    acceptedAttributionEventIDs.insert(attribution.eventID)
    touch(at: attribution.recordedAt)
    return .accepted
  }

  package func settle(
    _ result: Result,
    using capability: CompletionCapability<Context>
  ) -> Settlement {
    guard let identity = completionCapabilityIdentity[capability.id],
          identity == capability.identity
    else { return .unknownCompletionCapability }
    guard result.identity == identity else {
      return .refused(
        .identityMismatch(expected: identity, actual: result.identity)
      )
    }
    guard let active = activeByIdentity[identity] else {
      guard let terminal = terminalByIdentity[identity] else {
        return .unknownCompletionCapability
      }
      guard terminal.result == result else {
        return .refused(
          .terminalResultMismatch(expected: terminal.result, actual: result)
        )
      }
      return .duplicate(terminal)
    }
    guard active.identity == identity else {
      return .refused(
        .identityMismatch(expected: active.identity, actual: result.identity)
      )
    }
    guard active.completionCapability == capability else {
      return .unknownCompletionCapability
    }
    guard active.startedAt != nil else { return .notStarted }
    guard active.cancellationOwnerID == nil else { return .cancellationInProgress }

    guard let terminal = terminalize(identity: identity, result: result) else {
      return .unknownCompletionCapability
    }
    return .accepted(terminal)
  }

  package func stop(
    using capability: StopCapability<Context>,
    at requestedAt: Date = Date()
  ) async -> StopOutcome {
    guard let identity = activeCapabilityIdentity[capability.id] else {
      if retiredCapabilityIDs.contains(capability.id) { return .retiredCapability }
      return .unknownCapability
    }
    guard var active = activeByIdentity[identity] else {
      return .unknownCapability
    }
    guard active.stopCapability == capability, active.identity == capability.identity else {
      return .identityMismatch
    }
    if let ownerID = active.cancellationOwnerID {
      let reference = retainCancellationAttemptReference(
        identity: identity,
        ownerID: ownerID
      )
      guard let outcome = await awaitCancellationAttempt(reference) else {
        return .alreadyRequested
      }
      return stopOutcome(for: outcome)
    }

    let lease = latchCancellation(
      active: &active,
      reason: .stop,
      requestedAt: requestedAt
    )
    activeByIdentity[identity] = active
    await lease.handle.requestCancellation()
    markCancellationObserved(lease, at: Date())
    let result = await lease.handle.waitForSettlement()
    switch finishCancellation(lease, result: result) {
    case let .settled(terminal):
      return .settled(terminal)
    case let .refused(refusal):
      return .resultRefused(refusal)
    case .noLongerOwner:
      return .alreadyRequested
    }
  }

  /// Closes admission and latches every exact active owner before the first
  /// suspension. All newly-owned cancellation requests are then issued before
  /// awaiting any settlement, so a slow owner cannot delay cancellation of a
  /// second active lane.
  package func shutdown(at requestedAt: Date = Date()) async
    -> PlotterOperationShutdownReport<Lane, Context, Disposition>
  {
    let wasAlreadyClosed = admission == .closed
    if admission == .open {
      admission = .closed
      touch(at: requestedAt)
    }

    var ownedLeases: [CancellationLease<Context, Handle>] = []
    var alreadyOwnedAttempts: [CancellationAttemptReference<Context>] = []
    for identity in Array(activeByIdentity.keys) {
      guard var active = activeByIdentity[identity] else { continue }
      if let ownerID = active.cancellationOwnerID {
        alreadyOwnedAttempts.append(
          retainCancellationAttemptReference(identity: identity, ownerID: ownerID)
        )
        continue
      }
      let lease = latchCancellation(
        active: &active,
        reason: .shutdown,
        requestedAt: requestedAt
      )
      activeByIdentity[identity] = active
      ownedLeases.append(lease)
    }

    await withTaskGroup(of: Void.self) { group in
      for lease in ownedLeases {
        group.addTask {
          await lease.handle.requestCancellation()
        }
      }
      await group.waitForAll()
    }
    for lease in ownedLeases {
      markCancellationObserved(lease, at: Date())
    }

    var settled: [TerminalRecord] = []
    var resultRefusals: [ResultRefusal] = []
    for lease in ownedLeases {
      let result = await lease.handle.waitForSettlement()
      switch finishCancellation(lease, result: result) {
      case let .settled(terminal):
        settled.append(terminal)
      case let .refused(refusal):
        resultRefusals.append(refusal)
      case .noLongerOwner:
        break
      }
    }
    for reference in alreadyOwnedAttempts {
      guard let outcome = await awaitCancellationAttempt(reference) else { continue }
      switch outcome {
      case let .settled(terminal):
        settled.append(terminal)
      case let .refused(refusal):
        resultRefusals.append(refusal)
      }
    }

    return PlotterOperationShutdownReport(
      admissionWasAlreadyClosed: wasAlreadyClosed,
      settled: settled,
      resultRefusals: resultRefusals
    )
  }

  package func snapshot() -> PlotterOperationRegistrySnapshot<Lane, Context, Disposition> {
    let active = activeByIdentity.values.map { operation in
      PlotterActiveOperationSnapshot(
        identity: operation.identity,
        lane: operation.lane,
        laneRole: operation.laneRole,
        context: operation.context,
        owningSubsystem: operation.context.owningSubsystem,
        resultCurrentlyAwaited: operation.context.resultCurrentlyAwaited,
        phase: operation.phase,
        admittedAt: operation.admittedAt,
        startedAt: operation.startedAt,
        lastAttributableProgressAt: operation.lastAcceptedAttribution?.recordedAt,
        lastAcceptedAttribution: operation.lastAcceptedAttribution,
        deadline: operation.deadline,
        cancellationAvailable: operation.stopCapability != nil,
        cancellationPhase: operation.cancellationPhase,
        cancellationReason: operation.cancellationReason,
        lastCancellationResultRefusal: operation.lastCancellationResultRefusal,
        stopCapability: operation.stopCapability
      )
    }
    return PlotterOperationRegistrySnapshot(
      revision: revision,
      lastChangedAt: lastChangedAt,
      admission: admission,
      active: active,
      terminal: terminalRecords
    )
  }

  private func stopOutcome(
    for outcome: PlotterOperationCancellationAttemptOutcome<Lane, Context, Disposition>
  ) -> StopOutcome {
    switch outcome {
    case let .settled(terminal):
      return .settled(terminal)
    case let .refused(refusal):
      return .resultRefused(refusal)
    }
  }

  private func retainCancellationAttemptReference(
    identity: Identity,
    ownerID: UUID
  ) -> CancellationAttemptReference<Context> {
    cancellationAttemptObserverCounts[ownerID, default: 0] += 1
    return CancellationAttemptReference(identity: identity, ownerID: ownerID)
  }

  private func publishCancellationAttemptOutcome(
    _ outcome: CancellationOutcome,
    ownerID: UUID
  ) {
    if cancellationAttemptObserverCounts[ownerID, default: 0] > 0 {
      cancellationAttemptOutcomes[ownerID] = outcome
    }
  }

  private func releaseCancellationAttemptReference(ownerID: UUID) {
    guard let count = cancellationAttemptObserverCounts[ownerID] else { return }
    if count == 1 {
      cancellationAttemptObserverCounts.removeValue(forKey: ownerID)
      cancellationAttemptOutcomes.removeValue(forKey: ownerID)
    } else {
      cancellationAttemptObserverCounts[ownerID] = count - 1
    }
  }

  private func latchCancellation(
    active: inout ActiveOperation<Lane, Context, Handle>,
    reason: PlotterOperationCancellationReason,
    requestedAt: Date
  ) -> CancellationLease<Context, Handle> {
    precondition(
      active.cancellationOwnerID == nil && active.cancellationAttemptWaiters.isEmpty,
      "a new cancellation attempt requires no active owner or waiters"
    )
    let ownerID = UUID()
    active.cancellationOwnerID = ownerID
    active.cancellationReason = reason
    active.cancellationPhase = .requested
    active.phase = .cancelling
    touch(at: requestedAt)
    return CancellationLease(
      identity: active.identity,
      ownerID: ownerID,
      handle: active.handle
    )
  }

  private func markCancellationObserved(
    _ lease: CancellationLease<Context, Handle>,
    at observedAt: Date
  ) {
    guard var active = activeByIdentity[lease.identity],
          active.identity == lease.identity,
          active.cancellationOwnerID == lease.ownerID
    else { return }
    active.cancellationPhase = .observed
    activeByIdentity[lease.identity] = active
    touch(at: observedAt)

    active.cancellationPhase = .settling
    active.phase = .settling
    activeByIdentity[lease.identity] = active
    touch(at: observedAt)
  }

  private func finishCancellation(
    _ lease: CancellationLease<Context, Handle>,
    result: Result
  ) -> CancellationFinish<TerminalRecord, ResultRefusal> {
    guard let active = activeByIdentity[lease.identity],
          active.identity == lease.identity,
          active.cancellationOwnerID == lease.ownerID
    else { return .noLongerOwner }
    guard result.identity == lease.identity else {
      let refusal = ResultRefusal.identityMismatch(
        expected: lease.identity,
        actual: result.identity
      )
      var recoverable = active
      let waiters = recoverable.cancellationAttemptWaiters
      recoverable.cancellationAttemptWaiters.removeAll()
      recoverable.cancellationOwnerID = nil
      recoverable.lastCancellationAttemptOwnerID = lease.ownerID
      recoverable.lastCancellationResultRefusal = refusal
      recoverable.cancellationPhase = .refused
      recoverable.phase = recoverable.startedAt == nil ? .waiting : .suspectedStall
      activeByIdentity[lease.identity] = recoverable
      touch(at: result.settledAt)
      publishCancellationAttemptOutcome(.refused(refusal), ownerID: lease.ownerID)
      for waiter in waiters {
        waiter.resume(returning: .refused(refusal))
      }
      return .refused(refusal)
    }
    guard let terminal = terminalize(identity: lease.identity, result: result) else {
      return .noLongerOwner
    }
    return .settled(terminal)
  }

  private func terminalize(
    identity: Identity,
    result: Result
  ) -> TerminalRecord? {
    precondition(result.identity == identity, "terminal result must match its active identity")
    guard let active = activeByIdentity.removeValue(forKey: identity) else {
      return nil
    }
    if let permitID = active.permitID {
      retiredPermitIDs.insert(permitID)
    }
    if let stopCapability = active.stopCapability {
      activeCapabilityIdentity.removeValue(forKey: stopCapability.id)
      retiredCapabilityIDs.insert(stopCapability.id)
    }
    let terminal = TerminalRecord(
      result: result,
      lane: active.lane,
      laneRole: active.laneRole,
      context: active.context,
      owningSubsystem: active.context.owningSubsystem,
      resultCurrentlyAwaited: active.context.resultCurrentlyAwaited,
      phase: .terminal,
      admittedAt: active.admittedAt,
      startedAt: active.startedAt,
      lastAttributableProgressAt: active.lastAcceptedAttribution?.recordedAt,
      lastAcceptedAttribution: active.lastAcceptedAttribution,
      deadline: active.deadline,
      cancellationAvailable: active.stopCapability != nil,
      cancellationPhase: active.cancellationPhase,
      cancellationReason: active.cancellationReason,
      lastCancellationResultRefusal: active.lastCancellationResultRefusal
    )
    terminalByIdentity[identity] = terminal
    terminalRecords.append(terminal)
    touch(at: result.settledAt)
    if let ownerID = active.cancellationOwnerID {
      publishCancellationAttemptOutcome(.settled(terminal), ownerID: ownerID)
    }
    for waiter in active.cancellationAttemptWaiters {
      waiter.resume(returning: .settled(terminal))
    }
    return terminal
  }

  private func awaitCancellationAttempt(
    _ reference: CancellationAttemptReference<Context>
  ) async -> PlotterOperationCancellationAttemptOutcome<Lane, Context, Disposition>? {
    if let outcome = cancellationAttemptOutcomes[reference.ownerID] {
      releaseCancellationAttemptReference(ownerID: reference.ownerID)
      return outcome
    }
    if let terminal = terminalByIdentity[reference.identity] {
      releaseCancellationAttemptReference(ownerID: reference.ownerID)
      return .settled(terminal)
    }
    guard var active = activeByIdentity[reference.identity] else {
      releaseCancellationAttemptReference(ownerID: reference.ownerID)
      return nil
    }
    if active.lastCancellationAttemptOwnerID == reference.ownerID,
       let refusal = active.lastCancellationResultRefusal
    {
      releaseCancellationAttemptReference(ownerID: reference.ownerID)
      return .refused(refusal)
    }
    guard active.cancellationOwnerID == reference.ownerID else {
      releaseCancellationAttemptReference(ownerID: reference.ownerID)
      return nil
    }
    let outcome = await withCheckedContinuation { continuation in
      active.cancellationAttemptWaiters.append(continuation)
      activeByIdentity[reference.identity] = active
    }
    releaseCancellationAttemptReference(ownerID: reference.ownerID)
    return outcome
  }

  private func touch(at date: Date) {
    revision += 1
    if date > lastChangedAt {
      lastChangedAt = date
    }
  }

  private func attributionRefusal(
    _ attribution: PlotterOperationEventAttribution<Context>,
    for active: ActiveOperation<Lane, Context, Handle>,
    previous: PlotterOperationEventAttribution<Context>?
  ) -> PlotterOperationAttributionRefusal<Context>? {
    guard attribution.identity == active.identity else {
      return .identityMismatch(expected: active.identity)
    }
    guard !acceptedAttributionEventIDs.contains(attribution.eventID) else {
      return .duplicateEventID(attribution.eventID)
    }
    let preRevision = attribution.preStateRevision.rawValue
    guard preRevision < UInt64.max,
          attribution.postStateRevision.rawValue == preRevision + 1
    else {
      return .invalidStateRevisionTransition(
        pre: attribution.preStateRevision,
        post: attribution.postStateRevision
      )
    }
    guard let previous else {
      guard attribution.recordedAt >= active.admittedAt else {
        return .timestampRegression(
          previous: active.admittedAt,
          actual: attribution.recordedAt
        )
      }
      return nil
    }
    guard attribution.sequence > previous.sequence else {
      return .eventSequenceRegression(
        previous: previous.sequence,
        actual: attribution.sequence
      )
    }
    guard attribution.preStateRevision >= previous.postStateRevision else {
      return .stateRevisionRegression(
        previousPost: previous.postStateRevision,
        actualPre: attribution.preStateRevision
      )
    }
    guard attribution.recordedAt >= previous.recordedAt else {
      return .timestampRegression(
        previous: previous.recordedAt,
        actual: attribution.recordedAt
      )
    }
    return nil
  }
}
