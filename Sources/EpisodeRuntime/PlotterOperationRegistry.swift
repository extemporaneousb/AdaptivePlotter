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

package struct PlotterOperationIdentity: Hashable, Sendable {
  package let episodeID: EpisodeID
  package let requestID: IntentRequestID
  package let effectID: EpisodeEffectID
  package let effectRevision: EpisodeRevisionIdentifier

  package init(
    episodeID: EpisodeID,
    requestID: IntentRequestID,
    effectID: EpisodeEffectID,
    effectRevision: EpisodeRevisionIdentifier
  ) {
    self.episodeID = episodeID
    self.requestID = requestID
    self.effectID = effectID
    self.effectRevision = effectRevision
  }
}

/// Typed observable facts that every registered operation must expose.
///
/// The composing Plotter model supplies its concrete intent, environment, and
/// awaited-result vocabularies. Keeping them as associated types preserves the
/// EpisodeRuntime -> EpisodeCore boundary without permitting an opaque context
/// that cannot satisfy runtime observability.
package protocol PlotterOperationContext: Hashable, Sendable {
  associatedtype IntentIdentity: Hashable & Sendable
  associatedtype Environment: Hashable & Sendable
  associatedtype AwaitedResult: Hashable & Sendable

  var intentIdentity: IntentIdentity { get }
  var environment: Environment { get }
  var owningSubsystem: EpisodeAuthorityID { get }
  var resultCurrentlyAwaited: AwaitedResult { get }
}

/// Reference to one already-committed EpisodeCore event.
///
/// The registry validates attribution identity and ordering only. It neither
/// commits this event nor claims that the reference itself proves commitment;
/// later composition may supply it only after its EpisodeStore append returns.
package struct PlotterOperationEventAttribution: Hashable, Sendable {
  package let identity: PlotterOperationIdentity
  package let eventID: EpisodeEventID
  package let sequence: EpisodeEventSequence
  package let preStateRevision: EpisodeStateRevision
  package let postStateRevision: EpisodeStateRevision
  package let recordedAt: Date

  package init(
    identity: PlotterOperationIdentity,
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

package enum PlotterOperationAttributionRefusal: Equatable, Sendable {
  case identityMismatch(expected: PlotterOperationIdentity)
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
package struct EffectPermit: ~Copyable, Sendable {
  fileprivate let id: UUID
  package let identity: PlotterOperationIdentity

  private init(id: UUID, identity: PlotterOperationIdentity) {
    self.id = id
    self.identity = identity
  }

  fileprivate static func mint(for identity: PlotterOperationIdentity) -> Self {
    Self(id: UUID(), identity: identity)
  }
}

/// Revocable authority for one exact registered operation. It can neither mint
/// a permit nor identify a successor operation.
package struct StopCapability: Hashable, Sendable {
  fileprivate let id: UUID
  package let identity: PlotterOperationIdentity

  private init(id: UUID, identity: PlotterOperationIdentity) {
    self.id = id
    self.identity = identity
  }

  fileprivate static func mint(for identity: PlotterOperationIdentity) -> Self {
    Self(id: UUID(), identity: identity)
  }
}

/// The concrete handle retained by a registry is the original operation
/// handle, not an erased closure or a replacement cancellation task.
package protocol PlotterOperationHandle: Sendable {
  associatedtype TerminalDisposition: Hashable & Sendable

  func requestCancellation() async
  func waitForSettlement() async -> TerminalDisposition
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
}

package enum PlotterOperationCancellationPhase: String, Hashable, Sendable {
  case notRequested
  case requested
  case observed
  case settling
}

package enum PlotterOperationCancellationReason: String, Hashable, Sendable {
  case stop
  case shutdown
}

package enum PlotterOperationAdmissionError<Lane>: Error, Equatable, Sendable
where Lane: Hashable & Sendable {
  case admissionClosed
  case unconfiguredLane(Lane)
  case laneAtCapacity(lane: Lane, capacity: Int)
  case effectAlreadyKnown(PlotterOperationIdentity)
}

package enum EffectPermitConsumption: ~Copyable, Sendable {
  case accepted
  case identityMismatch(
    expected: PlotterOperationIdentity,
    permit: EffectPermit
  )
  case attributionRefused(
    PlotterOperationAttributionRefusal,
    permit: EffectPermit
  )
  case retired
  case cancellationInProgress
}

package enum PlotterOperationProgressUpdate: Equatable, Sendable {
  case accepted
  case unknownEffect
  case identityMismatch(expected: PlotterOperationIdentity)
  case notStarted
  case cancellationInProgress
  case alreadyTerminal
  case invalidLifecyclePhase
  case attributionRefused(PlotterOperationAttributionRefusal)
}

package enum PlotterOperationSettlement<Disposition>: Equatable, Sendable
where Disposition: Hashable & Sendable {
  case accepted(Disposition)
  case unknownEffect
  case identityMismatch(expected: PlotterOperationIdentity)
  case notStarted
  case cancellationInProgress
  case duplicate(Disposition)
}

package enum PlotterOperationStopOutcome<Disposition>: Equatable, Sendable
where Disposition: Hashable & Sendable {
  case settled(Disposition)
  case alreadyRequested
  case unknownCapability
  case retiredCapability
  case identityMismatch
}

package struct PlotterOperationRegistration: ~Copyable, Sendable {
  private let permit: EffectPermit
  package let stopCapability: StopCapability?

  fileprivate init(
    permit: consuming EffectPermit,
    stopCapability: StopCapability?
  ) {
    self.permit = permit
    self.stopCapability = stopCapability
  }

  package consuming func takePermit() -> EffectPermit {
    permit
  }
}

package struct PlotterActiveOperationSnapshot<Lane, Context>: Sendable
where Lane: Hashable & Sendable, Context: PlotterOperationContext {
  package let identity: PlotterOperationIdentity
  package let lane: Lane
  package let laneRole: PlotterOperationLaneRole
  package let context: Context
  package let intentIdentity: Context.IntentIdentity
  package let environment: Context.Environment
  package let owningSubsystem: EpisodeAuthorityID
  package let resultCurrentlyAwaited: Context.AwaitedResult
  package let phase: PlotterOperationLifecyclePhase
  package let admittedAt: Date
  package let startedAt: Date?
  package let lastAttributableProgressAt: Date?
  package let lastAcceptedAttribution: PlotterOperationEventAttribution?
  package let deadline: Date?
  package let cancellationAvailable: Bool
  package let cancellationPhase: PlotterOperationCancellationPhase
  package let cancellationReason: PlotterOperationCancellationReason?
  package let stopCapability: StopCapability?
}

package struct PlotterOperationTerminalRecord<Lane, Context, Disposition>: Sendable
where Lane: Hashable & Sendable,
      Context: PlotterOperationContext,
      Disposition: Hashable & Sendable {
  package let identity: PlotterOperationIdentity
  package let lane: Lane
  package let laneRole: PlotterOperationLaneRole
  package let context: Context
  package let intentIdentity: Context.IntentIdentity
  package let environment: Context.Environment
  package let owningSubsystem: EpisodeAuthorityID
  package let resultCurrentlyAwaited: Context.AwaitedResult
  package let lastAcceptedAttribution: PlotterOperationEventAttribution?
  package let disposition: Disposition
  package let settledAt: Date
  package let cancellationReason: PlotterOperationCancellationReason?
}

package struct PlotterOperationRegistrySnapshot<Lane, Context, Disposition>: Sendable
where Lane: Hashable & Sendable,
      Context: PlotterOperationContext,
      Disposition: Hashable & Sendable {
  package let revision: UInt64
  package let lastChangedAt: Date
  package let admission: PlotterOperationAdmissionState
  package let active: [PlotterActiveOperationSnapshot<Lane, Context>]
  package let terminal: [PlotterOperationTerminalRecord<Lane, Context, Disposition>]
}

package struct PlotterOperationShutdownReport<Lane, Context, Disposition>: Sendable
where Lane: Hashable & Sendable,
      Context: PlotterOperationContext,
      Disposition: Hashable & Sendable {
  package let admissionWasAlreadyClosed: Bool
  package let settled: [PlotterOperationTerminalRecord<Lane, Context, Disposition>]
}

private struct ActiveOperation<Lane, Context, Handle>
where Lane: Hashable & Sendable,
      Context: PlotterOperationContext,
      Handle: PlotterOperationHandle {
  let identity: PlotterOperationIdentity
  let lane: Lane
  let laneRole: PlotterOperationLaneRole
  let context: Context
  let handle: Handle
  var permitID: UUID?
  let stopCapability: StopCapability?
  let admittedAt: Date
  let deadline: Date?
  var phase: PlotterOperationLifecyclePhase
  var startedAt: Date?
  var lastAcceptedAttribution: PlotterOperationEventAttribution?
  var cancellationPhase: PlotterOperationCancellationPhase
  var cancellationReason: PlotterOperationCancellationReason?
  var cancellationOwnerID: UUID?
  var settlementWaiters: [CheckedContinuation<Handle.TerminalDisposition, Never>]
}

private struct CancellationLease<Handle>: Sendable
where Handle: PlotterOperationHandle {
  let identity: PlotterOperationIdentity
  let ownerID: UUID
  let handle: Handle
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
      Handle: PlotterOperationHandle {
  package typealias Disposition = Handle.TerminalDisposition
  package typealias TerminalRecord = PlotterOperationTerminalRecord<Lane, Context, Disposition>

  private let lanes: PlotterOperationLaneConfiguration<Lane>
  private var admission: PlotterOperationAdmissionState = .open
  private var activeByEffectID: [EpisodeEffectID: ActiveOperation<Lane, Context, Handle>] = [:]
  private var activeCapabilityEffectID: [UUID: EpisodeEffectID] = [:]
  private var retiredCapabilityIDs: Set<UUID> = []
  private var retiredPermitIDs: Set<UUID> = []
  private var acceptedAttributionEventIDs: Set<EpisodeEventID> = []
  private var terminalByEffectID: [EpisodeEffectID: TerminalRecord] = [:]
  private var terminalRecords: [TerminalRecord] = []
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
    identity: PlotterOperationIdentity,
    lane: Lane,
    context: Context,
    handle: Handle,
    cancellationAvailable: Bool,
    admittedAt: Date = Date(),
    deadline: Date? = nil
  ) throws -> PlotterOperationRegistration {
    guard admission == .open else {
      throw PlotterOperationAdmissionError<Lane>.admissionClosed
    }
    guard let laneRole = lanes.role(for: lane), let capacity = lanes.capacity(for: lane) else {
      throw PlotterOperationAdmissionError<Lane>.unconfiguredLane(lane)
    }
    if let active = activeByEffectID[identity.effectID] {
      throw PlotterOperationAdmissionError<Lane>.effectAlreadyKnown(active.identity)
    }
    if let terminal = terminalByEffectID[identity.effectID] {
      throw PlotterOperationAdmissionError<Lane>.effectAlreadyKnown(terminal.identity)
    }
    let occupancy = activeByEffectID.values.lazy.filter { $0.lane == lane }.count
    guard occupancy < capacity else {
      throw PlotterOperationAdmissionError<Lane>.laneAtCapacity(
        lane: lane,
        capacity: capacity
      )
    }

    let permit = EffectPermit.mint(for: identity)
    let stopCapability = cancellationAvailable ? StopCapability.mint(for: identity) : nil
    activeByEffectID[identity.effectID] = ActiveOperation(
      identity: identity,
      lane: lane,
      laneRole: laneRole,
      context: context,
      handle: handle,
      permitID: permit.id,
      stopCapability: stopCapability,
      admittedAt: admittedAt,
      deadline: deadline,
      phase: .waiting,
      startedAt: nil,
      lastAcceptedAttribution: nil,
      cancellationPhase: .notRequested,
      cancellationReason: nil,
      cancellationOwnerID: nil,
      settlementWaiters: []
    )
    if let stopCapability {
      activeCapabilityEffectID[stopCapability.id] = identity.effectID
    }
    touch(at: admittedAt)
    return PlotterOperationRegistration(
      permit: permit,
      stopCapability: stopCapability
    )
  }

  /// Moves one exact permit into the registry and records start before the
  /// caller invokes its external environment owner. Recoverable validation
  /// refusals return the same move-only authority without changing registry
  /// state. Success, cancellation, and retirement consume it permanently.
  package func start(
    _ permit: consuming EffectPermit,
    for identity: PlotterOperationIdentity,
    attributedTo attribution: PlotterOperationEventAttribution
  ) -> EffectPermitConsumption {
    let permitID = permit.id
    let permitIdentity = permit.identity
    guard var active = activeByEffectID[permitIdentity.effectID] else {
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
    guard permitIdentity == identity else {
      return .identityMismatch(expected: permitIdentity, permit: permit)
    }
    guard active.cancellationOwnerID == nil else {
      active.permitID = nil
      activeByEffectID[permitIdentity.effectID] = active
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
    activeByEffectID[identity.effectID] = active
    acceptedAttributionEventIDs.insert(attribution.eventID)
    touch(at: attribution.recordedAt)
    return .accepted
  }

  package func recordProgress(
    for identity: PlotterOperationIdentity,
    phase: PlotterOperationLifecyclePhase,
    attributedTo attribution: PlotterOperationEventAttribution
  ) -> PlotterOperationProgressUpdate {
    guard var active = activeByEffectID[identity.effectID] else {
      if terminalByEffectID[identity.effectID] != nil { return .alreadyTerminal }
      return .unknownEffect
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
    activeByEffectID[identity.effectID] = active
    acceptedAttributionEventIDs.insert(attribution.eventID)
    touch(at: attribution.recordedAt)
    return .accepted
  }

  package func settle(
    identity: PlotterOperationIdentity,
    disposition: Disposition,
    at settledAt: Date = Date()
  ) -> PlotterOperationSettlement<Disposition> {
    guard let active = activeByEffectID[identity.effectID] else {
      guard let terminal = terminalByEffectID[identity.effectID] else {
        return .unknownEffect
      }
      guard terminal.identity == identity else {
        return .identityMismatch(expected: terminal.identity)
      }
      return .duplicate(terminal.disposition)
    }
    guard active.identity == identity else {
      return .identityMismatch(expected: active.identity)
    }
    guard active.startedAt != nil else { return .notStarted }
    guard active.cancellationOwnerID == nil else { return .cancellationInProgress }

    _ = terminalize(
      effectID: identity.effectID,
      disposition: disposition,
      settledAt: settledAt
    )
    return .accepted(disposition)
  }

  package func stop(
    using capability: StopCapability,
    at requestedAt: Date = Date()
  ) async -> PlotterOperationStopOutcome<Disposition> {
    guard let effectID = activeCapabilityEffectID[capability.id] else {
      if retiredCapabilityIDs.contains(capability.id) { return .retiredCapability }
      return .unknownCapability
    }
    guard var active = activeByEffectID[effectID] else {
      return .unknownCapability
    }
    guard active.stopCapability == capability, active.identity == capability.identity else {
      return .identityMismatch
    }
    guard active.cancellationOwnerID == nil else { return .alreadyRequested }

    let lease = latchCancellation(
      active: &active,
      reason: .stop,
      requestedAt: requestedAt
    )
    activeByEffectID[effectID] = active
    await lease.handle.requestCancellation()
    markCancellationObserved(lease, at: Date())
    let disposition = await lease.handle.waitForSettlement()
    guard finishCancellation(lease, disposition: disposition, at: Date()) != nil else {
      return .alreadyRequested
    }
    return .settled(disposition)
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

    var ownedLeases: [CancellationLease<Handle>] = []
    var alreadyOwnedEffectIDs: [EpisodeEffectID] = []
    for effectID in Array(activeByEffectID.keys) {
      guard var active = activeByEffectID[effectID] else { continue }
      if active.cancellationOwnerID != nil {
        alreadyOwnedEffectIDs.append(effectID)
        continue
      }
      let lease = latchCancellation(
        active: &active,
        reason: .shutdown,
        requestedAt: requestedAt
      )
      activeByEffectID[effectID] = active
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
    for lease in ownedLeases {
      let disposition = await lease.handle.waitForSettlement()
      if let terminal = finishCancellation(lease, disposition: disposition, at: Date()) {
        settled.append(terminal)
      }
    }
    for effectID in alreadyOwnedEffectIDs {
      if let terminal = await awaitTerminal(effectID: effectID) {
        settled.append(terminal)
      }
    }

    return PlotterOperationShutdownReport(
      admissionWasAlreadyClosed: wasAlreadyClosed,
      settled: settled
    )
  }

  package func snapshot() -> PlotterOperationRegistrySnapshot<Lane, Context, Disposition> {
    let active = activeByEffectID.values.map { operation in
      PlotterActiveOperationSnapshot(
        identity: operation.identity,
        lane: operation.lane,
        laneRole: operation.laneRole,
        context: operation.context,
        intentIdentity: operation.context.intentIdentity,
        environment: operation.context.environment,
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

  private func latchCancellation(
    active: inout ActiveOperation<Lane, Context, Handle>,
    reason: PlotterOperationCancellationReason,
    requestedAt: Date
  ) -> CancellationLease<Handle> {
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
    _ lease: CancellationLease<Handle>,
    at observedAt: Date
  ) {
    guard var active = activeByEffectID[lease.identity.effectID],
          active.identity == lease.identity,
          active.cancellationOwnerID == lease.ownerID
    else { return }
    active.cancellationPhase = .observed
    activeByEffectID[lease.identity.effectID] = active
    touch(at: observedAt)

    active.cancellationPhase = .settling
    active.phase = .settling
    activeByEffectID[lease.identity.effectID] = active
    touch(at: observedAt)
  }

  private func finishCancellation(
    _ lease: CancellationLease<Handle>,
    disposition: Disposition,
    at settledAt: Date
  ) -> TerminalRecord? {
    guard let active = activeByEffectID[lease.identity.effectID],
          active.identity == lease.identity,
          active.cancellationOwnerID == lease.ownerID
    else { return nil }
    return terminalize(
      effectID: lease.identity.effectID,
      disposition: disposition,
      settledAt: settledAt
    )
  }

  private func terminalize(
    effectID: EpisodeEffectID,
    disposition: Disposition,
    settledAt: Date
  ) -> TerminalRecord? {
    guard let active = activeByEffectID.removeValue(forKey: effectID) else {
      return nil
    }
    if let permitID = active.permitID {
      retiredPermitIDs.insert(permitID)
    }
    if let stopCapability = active.stopCapability {
      activeCapabilityEffectID.removeValue(forKey: stopCapability.id)
      retiredCapabilityIDs.insert(stopCapability.id)
    }
    let terminal = TerminalRecord(
      identity: active.identity,
      lane: active.lane,
      laneRole: active.laneRole,
      context: active.context,
      intentIdentity: active.context.intentIdentity,
      environment: active.context.environment,
      owningSubsystem: active.context.owningSubsystem,
      resultCurrentlyAwaited: active.context.resultCurrentlyAwaited,
      lastAcceptedAttribution: active.lastAcceptedAttribution,
      disposition: disposition,
      settledAt: settledAt,
      cancellationReason: active.cancellationReason
    )
    terminalByEffectID[effectID] = terminal
    terminalRecords.append(terminal)
    touch(at: settledAt)
    for waiter in active.settlementWaiters {
      waiter.resume(returning: disposition)
    }
    return terminal
  }

  private func awaitTerminal(effectID: EpisodeEffectID) async -> TerminalRecord? {
    if let terminal = terminalByEffectID[effectID] { return terminal }
    guard var active = activeByEffectID[effectID] else { return nil }
    let disposition = await withCheckedContinuation { continuation in
      active.settlementWaiters.append(continuation)
      activeByEffectID[effectID] = active
    }
    return terminalByEffectID[effectID] ?? TerminalRecord(
      identity: active.identity,
      lane: active.lane,
      laneRole: active.laneRole,
      context: active.context,
      intentIdentity: active.context.intentIdentity,
      environment: active.context.environment,
      owningSubsystem: active.context.owningSubsystem,
      resultCurrentlyAwaited: active.context.resultCurrentlyAwaited,
      lastAcceptedAttribution: active.lastAcceptedAttribution,
      disposition: disposition,
      settledAt: Date(),
      cancellationReason: active.cancellationReason
    )
  }

  private func touch(at date: Date) {
    revision += 1
    if date > lastChangedAt {
      lastChangedAt = date
    }
  }

  private func attributionRefusal(
    _ attribution: PlotterOperationEventAttribution,
    for active: ActiveOperation<Lane, Context, Handle>,
    previous: PlotterOperationEventAttribution?
  ) -> PlotterOperationAttributionRefusal? {
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
