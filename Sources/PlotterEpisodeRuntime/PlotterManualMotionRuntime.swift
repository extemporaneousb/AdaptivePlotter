import EpisodeCore
import EpisodeRuntime
import CryptoKit
import Foundation
import PlotterEpisodeModel
import PlotterRuntime
import os

public struct PlotterManualMotionEffectRequest: Hashable, Sendable {
  public let context: PlotterEffectContext
  public let intent: PlotterManualMotionIntent
  public let effectRevision: EpisodeRevisionIdentifier

  public init(
    context: PlotterEffectContext,
    intent: PlotterManualMotionIntent,
    effectRevision: EpisodeRevisionIdentifier
  ) {
    self.context = context
    self.intent = intent
    self.effectRevision = effectRevision
  }
}

/// The adapter's one owner-produced terminal result. LIVE implementations map
/// existing RunInterpreter handles; SIMULATED implementations map exact
/// simulator operation IDs. Neither implementation may claim physical evidence.
public enum PlotterManualMotionOperationDisposition: Hashable, Sendable {
  case completed(observation: PlotterObservation)
  case refused(PlotterEffectRefusal)
  case cancelledBeforeStart
  case cancelled(
    settlement: PlotterEffectCancellationSettlement,
    observation: PlotterObservation
  )
  case ambiguous(PlotterEffectAmbiguity, observations: [PlotterObservation])
  case timedOut(deadline: Date)
  case evidenceUnavailable(reason: String)
  case failed(PlotterEffectFailure)
}

public struct PlotterManualMotionOperationIdentity: Hashable, Sendable {
  public let episodeID: EpisodeID
  public let requestID: IntentRequestID
  public let intent: PlotterManualMotionIntent
  public let effectID: EpisodeEffectID
  public let environment: PlotterEnvironment
  public let effectRevision: EpisodeRevisionIdentifier

  public init(request: PlotterManualMotionEffectRequest) {
    episodeID = request.context.episodeID
    requestID = request.context.requestID
    intent = request.intent
    effectID = request.context.effectID
    environment = request.context.environment
    effectRevision = request.effectRevision
  }
}

public struct PlotterManualMotionOperationResult: Hashable, Sendable {
  public let identity: PlotterManualMotionOperationIdentity
  public let disposition: PlotterManualMotionOperationDisposition
  public let settledAt: Date

  public init(
    identity: PlotterManualMotionOperationIdentity,
    disposition: PlotterManualMotionOperationDisposition,
    settledAt: Date = Date()
  ) {
    self.identity = identity
    self.disposition = disposition
    self.settledAt = settledAt
  }
}

/// A dormant exact operation. `start` initiates existing environment authority
/// and returns without waiting for settlement. Cancellation and settlement must
/// always target this same operation, including cancellation before `start`.
public protocol PlotterManualMotionOperation: Sendable {
  func start() async
  func requestCancellation() async
  func waitForSettlement() async -> PlotterManualMotionOperationResult
}

/// A narrow environment port. It does not own episode state, admission, Stop,
/// recording persistence, simulator plant state, or controller safety policy.
public protocol PlotterManualMotionEffectAdapter: Sendable {
  var environment: PlotterEnvironment { get }

  func makeOperation(
    for request: PlotterManualMotionEffectRequest,
    controllerRecorder: PlotterManualMotionControllerRecorder?
  ) -> any PlotterManualMotionOperation
}

/// Operation-bound bridge to EA-05A's low-level controller channel. Only a
/// LIVE adapter receives one. Callers submit the exact invocation/completion
/// produced at the MachineLink boundary; this type never synthesizes traffic.
public actor PlotterManualMotionControllerRecorder {
  private let store: EpisodeRecordingStore
  public let provenance: EpisodeRecordingProvenance
  private let recordingOriginMonotonicNanoseconds: UInt64
  private var lastDiagnostic: String?

  fileprivate init(
    store: EpisodeRecordingStore,
    provenance: EpisodeRecordingProvenance,
    recordingOriginMonotonicNanoseconds: UInt64
  ) {
    self.store = store
    self.provenance = provenance
    self.recordingOriginMonotonicNanoseconds = recordingOriginMonotonicNanoseconds
  }

  public func recordInvocation(
    _ invocation: ControllerInvocation,
    at monotonicOffsetNanoseconds: UInt64
  ) async {
    do {
      _ = try await store.recordControllerInvocation(
        invocation,
        at: monotonicOffsetNanoseconds,
        provenance: provenance
      )
    } catch {
      lastDiagnostic = "Controller invocation recording failed: \(error)"
    }
  }

  public func recordCompletion(
    _ completion: ControllerCompletion,
    at monotonicOffsetNanoseconds: UInt64
  ) async {
    do {
      _ = try await store.recordControllerCompletion(
        completion,
        at: monotonicOffsetNanoseconds,
        provenance: provenance
      )
    } catch {
      lastDiagnostic = "Controller completion recording failed: \(error)"
    }
  }

  public func diagnostic() -> String? {
    lastDiagnostic
  }

  /// Records an invocation at the exact source-clock boundary captured by the
  /// sole `MachineLink` decorator. The conversion origin is shared by every
  /// operation recorder created for this recording store.
  public func recordMachineLinkInvocation(
    _ invocation: ControllerInvocation,
    atSourceMonotonicNanoseconds value: UInt64
  ) async {
    guard let offset = recordingOffset(for: value) else { return }
    await recordInvocation(invocation, at: offset)
  }

  /// Records a completion at the exact source-clock boundary captured by the
  /// sole `MachineLink` decorator.
  public func recordMachineLinkCompletion(
    _ completion: ControllerCompletion,
    atSourceMonotonicNanoseconds value: UInt64
  ) async {
    guard let offset = recordingOffset(for: value) else { return }
    await recordCompletion(completion, at: offset)
  }

  /// Converts a FIX-02 receive-boundary timestamp without replacing it with a
  /// later adapter timestamp.
  public func controllerReadChunk(
    from receipt: MachineLinkReadReceipt
  ) -> ControllerReadChunk? {
    guard let offset = recordingOffset(for: receipt.receivedAtMonotonicNanoseconds) else {
      return nil
    }
    return ControllerReadChunk(bytes: receipt.bytes, monotonicOffsetNanoseconds: offset)
  }

  public func reportDiagnostic(_ diagnostic: String) {
    lastDiagnostic = diagnostic
  }

  private func recordingOffset(for sourceNanoseconds: UInt64) -> UInt64? {
    guard sourceNanoseconds >= recordingOriginMonotonicNanoseconds else {
      lastDiagnostic =
        "Controller recording source clock preceded the recording origin; no timestamp was fabricated."
      return nil
    }
    return sourceNanoseconds - recordingOriginMonotonicNanoseconds
  }
}

public struct PlotterManualMotionStopCapabilityID:
  RawRepresentable, Codable, Hashable, Sendable
{
  public let rawValue: UUID

  public init(rawValue: UUID = UUID()) {
    self.rawValue = rawValue
  }
}

public struct PlotterManualMotionActiveOperation: Hashable, Sendable {
  public let context: PlotterEffectContext
  public let intent: PlotterManualMotionIntent
  public let effectRevision: EpisodeRevisionIdentifier
  public let stopCapabilityID: PlotterManualMotionStopCapabilityID?

  public init(
    context: PlotterEffectContext,
    intent: PlotterManualMotionIntent,
    effectRevision: EpisodeRevisionIdentifier,
    stopCapabilityID: PlotterManualMotionStopCapabilityID?
  ) {
    self.context = context
    self.intent = intent
    self.effectRevision = effectRevision
    self.stopCapabilityID = stopCapabilityID
  }
}

public struct PlotterManualMotionRuntimeSnapshot: Sendable {
  public let projection: PlotterEpisodeProjection
  public let activeOperation: PlotterManualMotionActiveOperation?
  public let recordingDiagnostic: String?
  public let journal: PlotterManualMotionJournalSnapshot
  public let recording: EpisodeRecordingSnapshot?
  public let incidentSourceReferences: PlotterIncidentSourceArtifactReferences
  public let terminalPublicationIssue: PlotterManualMotionTerminalPublicationIssue?
  public let evidenceDispositionAction: PlotterManualMotionEvidenceDispositionAction?

  public init(
    projection: PlotterEpisodeProjection,
    activeOperation: PlotterManualMotionActiveOperation?,
    recordingDiagnostic: String?,
    journal: PlotterManualMotionJournalSnapshot,
    recording: EpisodeRecordingSnapshot?,
    incidentSourceReferences: PlotterIncidentSourceArtifactReferences,
    terminalPublicationIssue: PlotterManualMotionTerminalPublicationIssue?,
    evidenceDispositionAction: PlotterManualMotionEvidenceDispositionAction?
  ) {
    self.projection = projection
    self.activeOperation = activeOperation
    self.recordingDiagnostic = recordingDiagnostic
    self.journal = journal
    self.recording = recording
    self.incidentSourceReferences = incidentSourceReferences
    self.terminalPublicationIssue = terminalPublicationIssue
    self.evidenceDispositionAction = evidenceDispositionAction
  }
}

public enum PlotterManualMotionEvidenceDisposition: String, Codable, Hashable, Sendable {
  case acknowledgeAmbiguity
  case acknowledgePossibleInk
}

public struct PlotterManualMotionEvidenceDispositionAction: Hashable, Sendable {
  public let effectID: EpisodeEffectID
  public let environment: PlotterEnvironment
  public let observationID: PlotterObservationID
  public let disposition: PlotterManualMotionEvidenceDisposition
  public let summary: String

  public init(
    effectID: EpisodeEffectID,
    environment: PlotterEnvironment,
    observationID: PlotterObservationID,
    disposition: PlotterManualMotionEvidenceDisposition,
    summary: String
  ) {
    self.effectID = effectID
    self.environment = environment
    self.observationID = observationID
    self.disposition = disposition
    self.summary = summary
  }
}

public enum PlotterManualMotionEvidenceResolutionDisposition: String, Hashable, Sendable {
  case resolved
  case stale
  case mismatched
}

public struct PlotterManualMotionEvidenceResolutionResult: Sendable {
  public let disposition: PlotterManualMotionEvidenceResolutionDisposition
  public let snapshot: PlotterManualMotionRuntimeSnapshot
}

public struct PlotterManualMotionJournalSnapshot: Sendable {
  public let artifact: EpisodeArtifactReference
  public let fileURL: URL
  public let journal: EpisodeJournal<PlotterEpisodeEventPayload>

  public init(
    artifact: EpisodeArtifactReference,
    fileURL: URL,
    journal: EpisodeJournal<PlotterEpisodeEventPayload>
  ) {
    self.artifact = artifact
    self.fileURL = fileURL
    self.journal = journal
  }
}

public struct PlotterManualMotionPublicationRecoveryCapabilityID:
  RawRepresentable, Codable, Hashable, Sendable
{
  public let rawValue: UUID

  public init(rawValue: UUID = UUID()) {
    self.rawValue = rawValue
  }
}

public enum PlotterManualMotionTerminalPublicationStage: String, Codable, Hashable, Sendable {
  case cancellationRequested
  case cancellationObserved
  case cancellationSettling
  case observation
  case effectResult
}

public struct PlotterManualMotionTerminalPublicationIssue: Hashable, Sendable {
  public let recoveryCapabilityID: PlotterManualMotionPublicationRecoveryCapabilityID
  public let stage: PlotterManualMotionTerminalPublicationStage
  public let summary: String

  public init(
    recoveryCapabilityID: PlotterManualMotionPublicationRecoveryCapabilityID,
    stage: PlotterManualMotionTerminalPublicationStage,
    summary: String
  ) {
    self.recoveryCapabilityID = recoveryCapabilityID
    self.stage = stage
    self.summary = summary
  }
}

public enum PlotterManualMotionPublicationRecoveryDisposition: String, Hashable, Sendable {
  case published
  case stillIncomplete
  case stale
}

public struct PlotterManualMotionPublicationRecoveryResult: Sendable {
  public let disposition: PlotterManualMotionPublicationRecoveryDisposition
  public let snapshot: PlotterManualMotionRuntimeSnapshot
}

public enum PlotterManualMotionSubmissionDisposition: String, Hashable, Sendable {
  case accepted
  case refused
}

public struct PlotterManualMotionSubmission: Sendable {
  public let disposition: PlotterManualMotionSubmissionDisposition
  public let snapshot: PlotterManualMotionRuntimeSnapshot

  public init(
    disposition: PlotterManualMotionSubmissionDisposition,
    snapshot: PlotterManualMotionRuntimeSnapshot
  ) {
    self.disposition = disposition
    self.snapshot = snapshot
  }
}

public enum PlotterManualMotionStopDisposition: String, Hashable, Sendable {
  case settled
  case alreadyRequested
  case publicationPending
  case stale
}

public struct PlotterManualMotionStopResult: Sendable {
  public let disposition: PlotterManualMotionStopDisposition
  public let snapshot: PlotterManualMotionRuntimeSnapshot

  public init(
    disposition: PlotterManualMotionStopDisposition,
    snapshot: PlotterManualMotionRuntimeSnapshot
  ) {
    self.disposition = disposition
    self.snapshot = snapshot
  }
}

public enum PlotterManualMotionRuntimeError: Error, Equatable, Sendable {
  case adapterEnvironmentMismatch(expected: PlotterEnvironment, actual: PlotterEnvironment)
  case invalidManualEffect
  case operationAttributionRefused
}

package enum ManualMotionOperationLane: Hashable, Sendable {
  case machine
  case exactWorkflow
  case background
  case durable
}

package struct ManualMotionOperationContext: PlotterOperationContext {
  package typealias IntentIdentity = PlotterManualMotionIntent
  package typealias Environment = PlotterEnvironment
  package typealias AwaitedResult = PlotterAwaitedEffectResult

  package let owningSubsystem: EpisodeAuthorityID
  package let resultCurrentlyAwaited: PlotterAwaitedEffectResult
}

package actor ManualMotionOperationHandle: PlotterOperationHandle {
  package typealias OperationContext = ManualMotionOperationContext
  package typealias TerminalDisposition = PlotterManualMotionOperationDisposition

  private let identity: PlotterOperationIdentity<ManualMotionOperationContext>
  private let operation: any PlotterManualMotionOperation
  private var didStart = false
  private var wasCancelledBeforeStart = false

  package init(
    identity: PlotterOperationIdentity<ManualMotionOperationContext>,
    operation: any PlotterManualMotionOperation
  ) {
    self.identity = identity
    self.operation = operation
  }

  package func start() async {
    guard !didStart, !wasCancelledBeforeStart else { return }
    didStart = true
    await operation.start()
  }

  package func requestCancellation() async {
    guard didStart else {
      wasCancelledBeforeStart = true
      return
    }
    await operation.requestCancellation()
  }

  package func waitForSettlement() async
    -> PlotterOperationResult<ManualMotionOperationContext, PlotterManualMotionOperationDisposition>
  {
    if wasCancelledBeforeStart {
      return PlotterOperationResult(
        identity: identity,
        disposition: .cancelledBeforeStart,
        settledAt: Date()
      )
    }
    let result = await operation.waitForSettlement()
    let actualIdentity = PlotterOperationIdentity<ManualMotionOperationContext>(
      episodeID: result.identity.episodeID,
      requestID: result.identity.requestID,
      intentIdentity: result.identity.intent,
      effectID: result.identity.effectID,
      effectRevision: result.identity.effectRevision,
      environment: result.identity.environment
    )
    return PlotterOperationResult(
      identity: actualIdentity,
      disposition: result.disposition,
      settledAt: result.settledAt
    )
  }
}

private struct ActiveManualMotionOperation: Sendable {
  let identity: PlotterOperationIdentity<ManualMotionOperationContext>
  let request: PlotterManualMotionEffectRequest
  let handle: ManualMotionOperationHandle
  let stopCapability: StopCapability<ManualMotionOperationContext>?
  let completionCapability: CompletionCapability<ManualMotionOperationContext>
  let publicStopCapabilityID: PlotterManualMotionStopCapabilityID?
  let recorder: PlotterManualMotionControllerRecorder?

  var projection: PlotterManualMotionActiveOperation {
    PlotterManualMotionActiveOperation(
      context: request.context,
      intent: request.intent,
      effectRevision: request.effectRevision,
      stopCapabilityID: publicStopCapabilityID
    )
  }
}

private struct ActiveManualMotionStopTransaction {
  let capabilityID: PlotterManualMotionStopCapabilityID
  var waiters: [CheckedContinuation<PlotterManualMotionStopResult, Never>] = []
}

private enum PendingManualMotionStopStage: Sendable {
  case requestedNeedsPublication
  case requestedPublished
  case observedNeedsPublication
  case observedPublished
  case settlingNeedsPublication
  case settlingPublished
}

private struct PendingManualMotionStop: Sendable {
  let capabilityID: PlotterManualMotionStopCapabilityID
  let transaction: PlotterOperationStopTransaction<ManualMotionOperationContext>
  let recoveryCapabilityID: PlotterManualMotionPublicationRecoveryCapabilityID
  var stage: PendingManualMotionStopStage
}

private struct PendingManualMotionTerminalPublication: Sendable {
  let identity: PlotterOperationIdentity<ManualMotionOperationContext>
  let disposition: PlotterManualMotionOperationDisposition
  let recoveryCapabilityID: PlotterManualMotionPublicationRecoveryCapabilityID
  let observations: [PlotterObservation]
  let result: PlotterEffectResult
  var nextObservationIndex: Int
}

/// Package-only deterministic synchronization for the exact terminal-publication
/// boundary. It can pause and observe tests, but cannot choose an outcome,
/// publish state, cancel an operation, or grant Stop authority.
package final class PlotterManualMotionTerminalPublicationGate: Sendable {
  private struct State {
    var publicationIsHeld = false
    var duplicateHasJoined = false
    var isReleased = false
    var publicationWaiters: [CheckedContinuation<Void, Never>] = []
    var duplicateWaiters: [CheckedContinuation<Void, Never>] = []
    var releaseWaiters: [CheckedContinuation<Void, Never>] = []
  }

  private let state = OSAllocatedUnfairLock(initialState: State())

  package init() {}

  fileprivate func holdPublication() async {
    let (waiters, isReleased) = state.withLock { state in
      state.publicationIsHeld = true
      let waiters = state.publicationWaiters
      state.publicationWaiters.removeAll()
      return (waiters, state.isReleased)
    }
    waiters.forEach { $0.resume() }
    guard !isReleased else { return }
    await withCheckedContinuation { continuation in
      let resumeImmediately = state.withLock { state in
        guard !state.isReleased else { return true }
        state.releaseWaiters.append(continuation)
        return false
      }
      if resumeImmediately { continuation.resume() }
    }
  }

  fileprivate func noteDuplicateJoined() {
    let waiters = state.withLock { state in
      state.duplicateHasJoined = true
      let waiters = state.duplicateWaiters
      state.duplicateWaiters.removeAll()
      return waiters
    }
    waiters.forEach { $0.resume() }
  }

  package func waitUntilPublicationIsHeld() async {
    await withCheckedContinuation { continuation in
      let resumeImmediately = state.withLock { state in
        guard !state.publicationIsHeld else { return true }
        state.publicationWaiters.append(continuation)
        return false
      }
      if resumeImmediately { continuation.resume() }
    }
  }

  package func waitUntilDuplicateHasJoined() async {
    await withCheckedContinuation { continuation in
      let resumeImmediately = state.withLock { state in
        guard !state.duplicateHasJoined else { return true }
        state.duplicateWaiters.append(continuation)
        return false
      }
      if resumeImmediately { continuation.resume() }
    }
  }

  package func releasePublication() {
    let waiters = state.withLock { state in
      state.isReleased = true
      let waiters = state.releaseWaiters
      state.releaseWaiters.removeAll()
      return waiters
    }
    waiters.forEach { $0.resume() }
  }
}

/// Package-only synchronization at the cancellation journal pre-state seam.
/// It observes FIFO ordering only; it cannot publish, cancel, or mint recovery.
package final class PlotterManualMotionCancellationPublicationGate: Sendable {
  private struct State {
    var preStateIsHeld = false
    var mutationWaiterObserved = false
    var isReleased = false
    var preStateWaiters: [CheckedContinuation<Void, Never>] = []
    var mutationWaiters: [CheckedContinuation<Void, Never>] = []
    var releaseWaiters: [CheckedContinuation<Void, Never>] = []
  }

  private let state = OSAllocatedUnfairLock(initialState: State())
  package let targetPhase: PlotterEffectCancellationPhase

  package init(targetPhase: PlotterEffectCancellationPhase = .requested) {
    self.targetPhase = targetPhase
  }

  fileprivate func holdAfterPreStateRead(
    phase: PlotterEffectCancellationPhase
  ) async {
    guard phase == targetPhase else { return }
    let (waiters, released) = state.withLock { state in
      state.preStateIsHeld = true
      let waiters = state.preStateWaiters
      state.preStateWaiters.removeAll()
      return (waiters, state.isReleased)
    }
    waiters.forEach { $0.resume() }
    guard !released else { return }
    await withCheckedContinuation { continuation in
      let resumeImmediately = state.withLock { state in
        guard !state.isReleased else { return true }
        state.releaseWaiters.append(continuation)
        return false
      }
      if resumeImmediately { continuation.resume() }
    }
  }

  fileprivate func noteMutationWaiter() {
    let waiters = state.withLock { state in
      state.mutationWaiterObserved = true
      let waiters = state.mutationWaiters
      state.mutationWaiters.removeAll()
      return waiters
    }
    waiters.forEach { $0.resume() }
  }

  package func waitUntilPreStateIsHeld() async {
    await withCheckedContinuation { continuation in
      let resumeImmediately = state.withLock { state in
        guard !state.preStateIsHeld else { return true }
        state.preStateWaiters.append(continuation)
        return false
      }
      if resumeImmediately { continuation.resume() }
    }
  }

  package func waitUntilMutationWaiterIsObserved() async {
    await withCheckedContinuation { continuation in
      let resumeImmediately = state.withLock { state in
        guard !state.mutationWaiterObserved else { return true }
        state.mutationWaiters.append(continuation)
        return false
      }
      if resumeImmediately { continuation.resume() }
    }
  }

  package func releasePreState() {
    let waiters = state.withLock { state in
      state.isReleased = true
      let waiters = state.releaseWaiters
      state.releaseWaiters.removeAll()
      return waiters
    }
    waiters.forEach { $0.resume() }
  }
}

package enum PlotterManualMotionPrestartBoundary: Hashable, Sendable {
  case registered
  case registryStarted
  case progressRecorded
}

/// Package-only structural suspension at dormant-operation lifetime
/// boundaries. It observes ownership ordering and cannot start, cancel, or
/// settle an operation itself.
package final class PlotterManualMotionPrestartGate: Sendable {
  private struct State {
    var boundaryIsHeld = false
    var isReleased = false
    var boundaryWaiters: [CheckedContinuation<Void, Never>] = []
    var releaseWaiters: [CheckedContinuation<Void, Never>] = []
  }

  package let boundary: PlotterManualMotionPrestartBoundary
  private let state = OSAllocatedUnfairLock(initialState: State())

  package init(boundary: PlotterManualMotionPrestartBoundary) {
    self.boundary = boundary
  }

  fileprivate func hold(at boundary: PlotterManualMotionPrestartBoundary) async {
    guard boundary == self.boundary else { return }
    let (waiters, released) = state.withLock { state in
      state.boundaryIsHeld = true
      let waiters = state.boundaryWaiters
      state.boundaryWaiters.removeAll()
      return (waiters, state.isReleased)
    }
    waiters.forEach { $0.resume() }
    guard !released else { return }
    await withCheckedContinuation { continuation in
      let resumeImmediately = state.withLock { state in
        guard !state.isReleased else { return true }
        state.releaseWaiters.append(continuation)
        return false
      }
      if resumeImmediately { continuation.resume() }
    }
  }

  package func waitUntilBoundaryIsHeld() async {
    await withCheckedContinuation { continuation in
      let resumeImmediately = state.withLock { state in
        guard !state.boundaryIsHeld else { return true }
        state.boundaryWaiters.append(continuation)
        return false
      }
      if resumeImmediately { continuation.resume() }
    }
  }

  package func releaseBoundary() {
    let waiters = state.withLock { state in
      state.isReleased = true
      let waiters = state.releaseWaiters
      state.releaseWaiters.removeAll()
      return waiters
    }
    waiters.forEach { $0.resume() }
  }
}

private struct CommittedManualMotionEvent: Sendable {
  let event: PlotterEpisodeEvent
  let state: PlotterEpisodeState
}

public actor PlotterManualMotionRuntime {
  private typealias JournalPersistence =
    EpisodeJournalPersistenceAdapter<PlotterEpisodeEventPayload>
  private typealias Store = EpisodeStore<PlotterEpisodeReducer, JournalPersistence>
  private typealias Registry = PlotterOperationRegistry<
    ManualMotionOperationLane,
    ManualMotionOperationContext,
    ManualMotionOperationHandle
  >
  private typealias RegistryTerminal = PlotterOperationTerminalRecord<
    ManualMotionOperationLane,
    ManualMotionOperationContext,
    PlotterManualMotionOperationDisposition
  >

  public static let effectRevision = EpisodeRevisionIdentifier(
    rawValue: "plotter-manual-motion-effect-v2"
  )

  private let episodeID: EpisodeID
  private let manifestID: EpisodeManifestID
  private let store: Store
  private let journalFileURL: URL
  private let journalSchemaRevision = EpisodeRevisionIdentifier(
    rawValue: "plotter-manual-motion-journal-v1"
  )
  private let gateway = PlotterIntentGateway()
  private let liveAdapter: any PlotterManualMotionEffectAdapter
  private let simulatedAdapter: any PlotterManualMotionEffectAdapter
  private let recordingStore: EpisodeRecordingStore?
  private let recordingDirectoryURL: URL?
  private let recordingOriginMonotonicNanoseconds: UInt64
  private let registry: Registry
  private var active: ActiveManualMotionOperation?
  private var activeStopTransaction: ActiveManualMotionStopTransaction?
  private var pendingStop: PendingManualMotionStop?
  private var pendingTerminalPublication: PendingManualMotionTerminalPublication?
  private var terminalPublicationIssue: PlotterManualMotionTerminalPublicationIssue?
  /// Retains the one transaction-complete result only until successor admission.
  /// It makes a late duplicate idempotent without granting successor authority.
  private var lastSettledStopResult: (
    capabilityID: PlotterManualMotionStopCapabilityID,
    result: PlotterManualMotionStopResult
  )?
  private var terminalPublicationGate: PlotterManualMotionTerminalPublicationGate?
  private var cancellationPublicationGate:
    PlotterManualMotionCancellationPublicationGate?
  private var prestartGate: PlotterManualMotionPrestartGate?
  private var prestartShutdownSettlements: [
    PlotterOperationIdentity<ManualMotionOperationContext>:
      PlotterManualMotionOperationDisposition
  ] = [:]
  private var shutdownIsLatched = false
  private var shutdownRegistrySettlementIsComplete = false
  private var shutdownRegistrySettlementWaiters: [CheckedContinuation<Void, Never>] = []
  private var projectionRevision: UInt64 = 0
  private var lastRecordingDiagnostic: String?
  private var mutationPublicationBoundaryIsHeld = false
  private var mutationPublicationBoundaryWaiters: [CheckedContinuation<Void, Never>] = []

  public init(
    episodeID: EpisodeID = EpisodeID(rawValue: UUID()),
    journalFileURL: URL,
    liveAdapter: any PlotterManualMotionEffectAdapter,
    simulatedAdapter: any PlotterManualMotionEffectAdapter,
    recordingStore: EpisodeRecordingStore? = nil,
    recordingDirectoryURL: URL? = nil,
    recordingUnavailableDiagnostic: String? = nil,
    recordingClock: any RuntimeClock = SystemRuntimeClock()
  ) throws {
    guard liveAdapter.environment == .live else {
      throw PlotterManualMotionRuntimeError.adapterEnvironmentMismatch(
        expected: .live,
        actual: liveAdapter.environment
      )
    }
    guard simulatedAdapter.environment == .simulated else {
      throw PlotterManualMotionRuntimeError.adapterEnvironmentMismatch(
        expected: .simulated,
        actual: simulatedAdapter.environment
      )
    }
    self.episodeID = episodeID
    self.journalFileURL = journalFileURL
    self.liveAdapter = liveAdapter
    self.simulatedAdapter = simulatedAdapter
    self.recordingStore = recordingStore
    self.recordingDirectoryURL = recordingDirectoryURL
    recordingOriginMonotonicNanoseconds = recordingClock.nowNanoseconds()
    lastRecordingDiagnostic = recordingUnavailableDiagnostic

    let prototype = PlotterEpisodeState(
      episodeID: episodeID,
      canonicalDigest: EpisodeStateDigest(rawValue: "pending"),
      phase: .ready
    )
    let initial = PlotterEpisodeState(
      episodeID: episodeID,
      canonicalDigest: try PlotterEpisodeCanonicalDigestV1.digest(prototype),
      phase: .ready
    )
    let manifestID = EpisodeManifestID(rawValue: UUID())
    self.manifestID = manifestID
    store = try EpisodeStore.open(
      manifestID: manifestID,
      initialState: initial,
      reducer: PlotterEpisodeReducer(),
      persistence: JournalPersistence(
        fileURL: journalFileURL,
        journalSchemaRevision: journalSchemaRevision
      )
    )
    registry = PlotterOperationRegistry(lanes: try PlotterOperationLaneConfiguration(
      machine: ManualMotionOperationLane.machine,
      exactWorkflowCaptureVision: .exactWorkflow,
      backgroundAnalysis: .background,
      durableAppend: .durable,
      backgroundAnalysisLimit: 2
    ))
  }

  public func currentSnapshot() async -> PlotterManualMotionRuntimeSnapshot {
    await acquireMutationPublicationBoundary()
    defer { releaseMutationPublicationBoundary() }
    return await snapshot(for: await store.currentState())
  }

  public func submit(
    _ intent: PlotterManualMotionIntent,
    capabilityFacts: [PlotterCapabilityFact],
    environment: PlotterEnvironment
  ) async throws -> PlotterManualMotionSubmission {
    await acquireMutationPublicationBoundary()
    defer { releaseMutationPublicationBoundary() }

    let rootIntent = PlotterIntent.manualMotion(intent)
    let requestID = IntentRequestID(rawValue: UUID())
    let state = await store.currentState()
    // The exact active registry owner is the transient busy authority. A
    // generic intent-refusal event terminalizes the model's single active
    // request, so do not evaluate/commit a successor intent against this
    // cancellation revision. Refuse from the current transaction-complete
    // snapshot instead.
    guard active == nil else {
      return PlotterManualMotionSubmission(
        disposition: .refused,
        snapshot: await snapshot(for: state)
      )
    }
    let evaluated = try gateway.evaluate(
      requestID: requestID,
      intent: rootIntent,
      state: state,
      capabilityFacts: capabilityFacts,
      environment: environment
    )
    guard evaluated.decision.isAdmitted else {
      let committed = try await commit(
        payload: evaluated.payload,
        origin: .operatorRequest
      )
      return PlotterManualMotionSubmission(
        disposition: .refused,
        snapshot: await snapshot(for: committed.state)
      )
    }
    guard case let .intentAccepted(accepted) = evaluated.payload,
      let effect = accepted.effect(episodeID: episodeID),
      effect.context.environment == environment
    else { throw PlotterManualMotionRuntimeError.invalidManualEffect }

    let effectRequest = PlotterManualMotionEffectRequest(
      context: effect.context,
      intent: intent,
      effectRevision: Self.effectRevision
    )
    let adapter = environment == .live ? liveAdapter : simulatedAdapter
    let recorder = makeRecorder(for: effect.context)
    let operation = adapter.makeOperation(
      for: effectRequest,
      controllerRecorder: recorder
    )
    let identity = PlotterOperationIdentity<ManualMotionOperationContext>(
      episodeID: episodeID,
      requestID: requestID,
      intentIdentity: intent,
      effectID: effect.context.effectID,
      effectRevision: Self.effectRevision,
      environment: environment
    )
    let awaited: PlotterAwaitedEffectResult
    switch intent {
    case .jog:
      awaited = .controllerSettlement
    case .setPen:
      awaited = .penSettlement
    }
    let operationContext = ManualMotionOperationContext(
      owningSubsystem: EpisodeAuthorityID(rawValue: "MachineController"),
      resultCurrentlyAwaited: awaited
    )
    let handle = ManualMotionOperationHandle(identity: identity, operation: operation)
    let cancellationAvailable: Bool
    switch intent {
    case .jog: cancellationAvailable = true
    case .setPen: cancellationAvailable = false
    }
    let registration = try await registry.register(
      identity: identity,
      lane: .machine,
      context: operationContext,
      handle: handle,
      cancellationAvailable: cancellationAvailable
    )
    let stopCapability = registration.stopCapability
    let completionCapability = registration.completionCapability
    let permit = registration.takePermit()
    let publicStopCapabilityID: PlotterManualMotionStopCapabilityID?
    switch intent {
    case .jog:
      publicStopCapabilityID = PlotterManualMotionStopCapabilityID()
    case .setPen:
      publicStopCapabilityID = nil
    }

    await prestartGate?.hold(at: .registered)
    if await consumePrestartShutdownDisposition(for: identity) != nil {
      return PlotterManualMotionSubmission(
        disposition: .refused,
        snapshot: await snapshot(for: await store.currentState())
      )
    }

    let acceptedEvent: CommittedManualMotionEvent
    do {
      acceptedEvent = try await commit(
        payload: evaluated.payload,
        origin: .operatorRequest
      )
    } catch {
      _ = await registry.withdrawBeforeExternalStart(identity, using: completionCapability)
      throw error
    }
    let acceptedAttribution = attribution(identity: identity, event: acceptedEvent.event)
    switch await registry.start(permit, for: identity, attributedTo: acceptedAttribution) {
    case .accepted:
      break
    case .admissionClosed:
      let shutdown = await registry.shutdown()
      retainPrestartShutdownSettlements(shutdown.settled)
      if let disposition = await consumePrestartShutdownDisposition(for: identity) {
        return try await publishPrestartTerminalSubmission(
          disposition: disposition,
          request: effectRequest
        )
      }
      _ = await registry.withdrawBeforeExternalStart(identity, using: completionCapability)
      throw CancellationError()
    case .retired:
      let shutdown = await registry.shutdown()
      retainPrestartShutdownSettlements(shutdown.settled)
      if let disposition = await consumePrestartShutdownDisposition(for: identity) {
        return try await publishPrestartTerminalSubmission(
          disposition: disposition,
          request: effectRequest
        )
      }
      _ = await registry.withdrawBeforeExternalStart(identity, using: completionCapability)
      throw CancellationError()
    case .cancellationInProgress:
      let shutdown = await registry.shutdown()
      retainPrestartShutdownSettlements(shutdown.settled)
      if let disposition = await consumePrestartShutdownDisposition(for: identity) {
        return try await publishPrestartTerminalSubmission(
          disposition: disposition,
          request: effectRequest
        )
      }
      _ = await registry.withdrawBeforeExternalStart(identity, using: completionCapability)
      throw CancellationError()
    case .identityMismatch:
      _ = await registry.withdrawBeforeExternalStart(identity, using: completionCapability)
      throw PlotterManualMotionRuntimeError.operationAttributionRefused
    case .attributionRefused:
      _ = await registry.withdrawBeforeExternalStart(identity, using: completionCapability)
      throw PlotterManualMotionRuntimeError.operationAttributionRefused
    }

    await prestartGate?.hold(at: .registryStarted)
    if let disposition = await consumePrestartShutdownDisposition(for: identity) {
      return try await publishPrestartTerminalSubmission(
        disposition: disposition,
        request: effectRequest
      )
    }

    let progressAt = Date()
    let progress = try PlotterEffectProgress(
      episodeID: episodeID,
      requestID: requestID,
      intent: rootIntent,
      effectID: effect.context.effectID,
      effectRevision: Self.effectRevision,
      environment: environment,
      lane: .machine,
      owningSubsystem: .machineController,
      phase: .progressing,
      startedAt: acceptedEvent.event.recordedAt,
      lastAttributableProgressAt: progressAt,
      resultCurrentlyAwaited: awaited,
      cancellation: PlotterEffectCancellationStatus(
        availability: publicStopCapabilityID == nil ? .unavailable : .available,
        phase: .notRequested
      )
    )
    let progressEvent: CommittedManualMotionEvent
    do {
      progressEvent = try await commit(
        payload: .effectProgressed(progress),
        origin: .environment,
        recordedAt: progressAt
      )
    } catch {
      _ = await registry.withdrawBeforeExternalStart(identity, using: completionCapability)
      throw error
    }
    let progressUpdate = await registry.recordProgress(
      for: identity,
      phase: .progressing,
      attributedTo: attribution(identity: identity, event: progressEvent.event)
    )
    guard case .accepted = progressUpdate else {
      if progressUpdate == .alreadyTerminal || progressUpdate == .cancellationInProgress {
        let shutdown = await registry.shutdown()
        retainPrestartShutdownSettlements(shutdown.settled)
        if let disposition = await consumePrestartShutdownDisposition(for: identity) {
          return try await publishPrestartTerminalSubmission(
            disposition: disposition,
            request: effectRequest
          )
        }
      }
      _ = await registry.withdrawBeforeExternalStart(identity, using: completionCapability)
      throw PlotterManualMotionRuntimeError.operationAttributionRefused
    }

    await prestartGate?.hold(at: .progressRecorded)
    if shutdownIsLatched {
      await waitForShutdownRegistrySettlement()
      guard let disposition = await consumePrestartShutdownDisposition(for: identity) else {
        throw PlotterManualMotionRuntimeError.operationAttributionRefused
      }
      return try await publishPrestartTerminalSubmission(
        disposition: disposition,
        request: effectRequest
      )
    }

    lastSettledStopResult = nil
    active = ActiveManualMotionOperation(
      identity: identity,
      request: effectRequest,
      handle: handle,
      stopCapability: stopCapability,
      completionCapability: completionCapability,
      publicStopCapabilityID: publicStopCapabilityID,
      recorder: recorder
    )
    await handle.start()
    Task { [weak self] in
      let result = await handle.waitForSettlement()
      await self?.finishNaturally(
        result,
        completionCapability: completionCapability
      )
    }
    return PlotterManualMotionSubmission(
      disposition: .accepted,
      snapshot: await snapshot(for: progressEvent.state)
    )
  }

  public func stop(
    using capabilityID: PlotterManualMotionStopCapabilityID
  ) async -> PlotterManualMotionStopResult {
    if activeStopTransaction?.capabilityID == capabilityID {
      let gate = terminalPublicationGate
      return await withCheckedContinuation { continuation in
        activeStopTransaction!.waiters.append(continuation)
        gate?.noteDuplicateJoined()
      }
    }
    guard let owner = active else {
      if let lastSettledStopResult,
        lastSettledStopResult.capabilityID == capabilityID
      {
        return lastSettledStopResult.result
      }
      return PlotterManualMotionStopResult(
        disposition: .stale,
        snapshot: await snapshot(for: await store.currentState())
      )
    }
    guard owner.publicStopCapabilityID == capabilityID else {
      return PlotterManualMotionStopResult(
        disposition: .stale,
        snapshot: await snapshot(for: await store.currentState())
      )
    }
    activeStopTransaction = ActiveManualMotionStopTransaction(capabilityID: capabilityID)
    let result: PlotterManualMotionStopResult
    if let pendingTerminalPublication,
       pendingTerminalPublication.identity == owner.identity {
      let published = await resumeTerminalPublicationIfCurrent()
      result = PlotterManualMotionStopResult(
        disposition: published ? .settled : .publicationPending,
        snapshot: await snapshot(for: await store.currentState())
      )
    } else {
      if pendingStop == nil {
        guard let stopCapability = owner.stopCapability else {
          result = PlotterManualMotionStopResult(
            disposition: .stale,
            snapshot: await snapshot(for: await store.currentState())
          )
          completeStopTransaction(capabilityID: capabilityID, result: result)
          return result
        }
        switch await registry.beginStop(using: stopCapability) {
        case let .requested(transaction):
          pendingStop = PendingManualMotionStop(
            capabilityID: capabilityID,
            transaction: transaction,
            recoveryCapabilityID: PlotterManualMotionPublicationRecoveryCapabilityID(),
            stage: .requestedNeedsPublication
          )
        case .alreadyRequested:
          result = PlotterManualMotionStopResult(
            disposition: .alreadyRequested,
            snapshot: await snapshot(for: await store.currentState())
          )
          completeStopTransaction(capabilityID: capabilityID, result: result)
          return result
        case .unknownCapability, .retiredCapability, .identityMismatch:
          result = PlotterManualMotionStopResult(
            disposition: .stale,
            snapshot: await snapshot(for: await store.currentState())
          )
          completeStopTransaction(capabilityID: capabilityID, result: result)
          return result
        }
      }
      result = await advancePendingStop(for: owner)
    }
    completeStopTransaction(capabilityID: capabilityID, result: result)
    return result
  }

  package func installTerminalPublicationGateForTesting(
    _ gate: PlotterManualMotionTerminalPublicationGate
  ) {
    precondition(active == nil && activeStopTransaction == nil)
    terminalPublicationGate = gate
  }

  package func installCancellationPublicationGateForTesting(
    _ gate: PlotterManualMotionCancellationPublicationGate
  ) {
    precondition(active == nil && activeStopTransaction == nil)
    cancellationPublicationGate = gate
  }

  package func installPrestartGateForTesting(
    _ gate: PlotterManualMotionPrestartGate
  ) {
    precondition(active == nil && activeStopTransaction == nil)
    prestartGate = gate
  }

  package func registryOwnershipForTesting() async -> (
    activeEffectIDs: [EpisodeEffectID],
    terminalEffectIDs: [EpisodeEffectID]
  ) {
    let snapshot = await registry.snapshot()
    return (
      snapshot.active.map(\.identity.effectID),
      snapshot.terminal.map(\.identity.effectID)
    )
  }

  public func recoverTerminalPublication(
    using capabilityID: PlotterManualMotionPublicationRecoveryCapabilityID
  ) async -> PlotterManualMotionPublicationRecoveryResult {
    if pendingTerminalPublication?.recoveryCapabilityID == capabilityID {
      let published = await resumeTerminalPublicationIfCurrent()
      return PlotterManualMotionPublicationRecoveryResult(
        disposition: published ? .published : .stillIncomplete,
        snapshot: await snapshot(for: await store.currentState())
      )
    }
    if pendingStop?.recoveryCapabilityID == capabilityID,
       let stopCapabilityID = active?.publicStopCapabilityID {
      let result = await stop(using: stopCapabilityID)
      return PlotterManualMotionPublicationRecoveryResult(
        disposition: result.disposition == .settled ? .published : .stillIncomplete,
        snapshot: result.snapshot
      )
    }
    return PlotterManualMotionPublicationRecoveryResult(
      disposition: .stale,
      snapshot: await snapshot(for: await store.currentState())
    )
  }

  public func resolveTerminalEvidence(
    using action: PlotterManualMotionEvidenceDispositionAction
  ) async throws -> PlotterManualMotionEvidenceResolutionResult {
    await acquireMutationPublicationBoundary()
    defer { releaseMutationPublicationBoundary() }
    let state = await store.currentState()
    guard let current = evidenceDispositionAction(for: state) else {
      return PlotterManualMotionEvidenceResolutionResult(
        disposition: .stale,
        snapshot: await snapshot(for: state)
      )
    }
    guard current == action else {
      return PlotterManualMotionEvidenceResolutionResult(
        disposition: current.effectID == action.effectID ? .mismatched : .stale,
        snapshot: await snapshot(for: state)
      )
    }
    let journal = await store.currentJournal()
    guard let observation = journal.events.compactMap({ event -> PlotterObservation? in
      guard case let .observationRecorded(value) = event.payload,
            value.context.id == action.observationID else { return nil }
      return value
    }).last,
      observation.context.environment == action.environment
    else {
      return PlotterManualMotionEvidenceResolutionResult(
        disposition: .mismatched,
        snapshot: await snapshot(for: state)
      )
    }
    let question: PlotterEvidenceQuestion = action.disposition == .acknowledgePossibleInk
      ? .drawingOutcome : .motionSettlement
    let evidence = try PlotterEvidence(
      id: PlotterEvidenceID(rawValue: UUID()),
      episodeID: episodeID,
      subject: .observation(action.observationID),
      question: question,
      inputEnvironment: action.environment,
      evidenceClass: .operatorAssertion,
      acceptedBy: EpisodeAuthorityID(
        rawValue: "OperatorWorkspace.ManualMotionEvidenceDisposition"
      ),
      acceptedAt: Date(),
      applicabilityRevision: EpisodeRevisionIdentifier(
        rawValue: "manual-motion-operator-disposition-v1"
      ),
      artifactReferences: observation.context.artifactReferences
    )
    let committed = try await commit(
      payload: .evidenceDecided(.accepted(evidence)),
      origin: .operatorRequest,
      artifacts: observation.context.artifactReferences
    )
    return PlotterManualMotionEvidenceResolutionResult(
      disposition: .resolved,
      snapshot: await snapshot(for: committed.state)
    )
  }

  public func shutdown() async {
    if shutdownIsLatched {
      await waitForShutdownRegistrySettlement()
      return
    }
    shutdownIsLatched = true
    let report = await registry.shutdown()
    for terminal in report.settled {
      if let pendingStop, pendingStop.transaction.identity == terminal.identity {
        // The public Stop cursor remains the sole journal publisher. Shutdown
        // may settle the retained native handle, but it neither clears nor
        // replaces the exact publication/recovery authority.
        continue
      }
      guard active?.identity == terminal.identity else {
        prestartShutdownSettlements[terminal.identity] = terminal.disposition
        continue
      }
      _ = await publishTerminalIfCurrent(
        identity: terminal.identity,
        disposition: terminal.disposition,
        recoveryCapabilityID: PlotterManualMotionPublicationRecoveryCapabilityID()
      )
    }
    shutdownRegistrySettlementIsComplete = true
    let waiters = shutdownRegistrySettlementWaiters
    shutdownRegistrySettlementWaiters.removeAll()
    waiters.forEach { $0.resume() }
  }

  private func waitForShutdownRegistrySettlement() async {
    guard !shutdownRegistrySettlementIsComplete else { return }
    await withCheckedContinuation { continuation in
      shutdownRegistrySettlementWaiters.append(continuation)
    }
  }

  private func retainPrestartShutdownSettlements(
    _ terminals: [RegistryTerminal]
  ) {
    for terminal in terminals where active?.identity != terminal.identity {
      prestartShutdownSettlements[terminal.identity] = terminal.disposition
    }
  }

  private func consumePrestartShutdownDisposition(
    for identity: PlotterOperationIdentity<ManualMotionOperationContext>
  ) async -> PlotterManualMotionOperationDisposition? {
    if let retained = prestartShutdownSettlements.removeValue(forKey: identity) {
      return retained
    }
    let registrySnapshot = await registry.snapshot()
    return registrySnapshot.terminal.first {
      $0.identity == identity
    }?.disposition
  }

  private func publishPrestartTerminalSubmission(
    disposition: PlotterManualMotionOperationDisposition,
    request: PlotterManualMotionEffectRequest
  ) async throws -> PlotterManualMotionSubmission {
    let result = effectResult(for: normalize(disposition, for: request), request: request)
    let committed = try await commit(payload: .effectResult(result), origin: .environment)
    return PlotterManualMotionSubmission(
      disposition: .accepted,
      snapshot: await snapshot(for: committed.state)
    )
  }

  private func advancePendingStop(
    for owner: ActiveManualMotionOperation
  ) async -> PlotterManualMotionStopResult {
    while var pending = pendingStop,
          pending.capabilityID == owner.publicStopCapabilityID,
          owner.identity == active?.identity {
      switch pending.stage {
      case .requestedNeedsPublication:
        if let incomplete = await publishCancellationProgress(
          for: owner,
          phase: .cancelling,
          cancellationPhase: .requested,
          recoveryCapabilityID: pending.recoveryCapabilityID,
          issueStage: .cancellationRequested
        ) {
          return incomplete
        }
        pending.stage = .requestedPublished
        pendingStop = pending
      case .requestedPublished:
        guard case .advanced = await registry.observeStop(using: pending.transaction) else {
          return await unresolvedStopResult(
            recoveryCapabilityID: pending.recoveryCapabilityID,
            summary: "The exact registry Stop transaction could not publish cancellation observation."
          )
        }
        pending.stage = .observedNeedsPublication
        pendingStop = pending
      case .observedNeedsPublication:
        if let incomplete = await publishCancellationProgress(
          for: owner,
          phase: .cancelling,
          cancellationPhase: .observed,
          recoveryCapabilityID: pending.recoveryCapabilityID,
          issueStage: .cancellationObserved
        ) {
          return incomplete
        }
        pending.stage = .observedPublished
        pendingStop = pending
      case .observedPublished:
        guard case .advanced = await registry.beginStopSettlement(
          using: pending.transaction
        ) else {
          return await unresolvedStopResult(
            recoveryCapabilityID: pending.recoveryCapabilityID,
            summary: "The exact registry Stop transaction could not enter settlement."
          )
        }
        pending.stage = .settlingNeedsPublication
        pendingStop = pending
      case .settlingNeedsPublication:
        if let incomplete = await publishCancellationProgress(
          for: owner,
          phase: .settling,
          cancellationPhase: .settling,
          recoveryCapabilityID: pending.recoveryCapabilityID,
          issueStage: .cancellationSettling
        ) {
          return incomplete
        }
        pending.stage = .settlingPublished
        pendingStop = pending
      case .settlingPublished:
        let outcome = await registry.finishStop(using: pending.transaction)
        pendingStop = nil
        switch outcome {
        case let .settled(terminal):
          let published = await publishTerminalIfCurrent(
            identity: terminal.identity,
            disposition: terminal.disposition,
            recoveryCapabilityID: pending.recoveryCapabilityID
          )
          return PlotterManualMotionStopResult(
            disposition: published ? .settled : .publicationPending,
            snapshot: await snapshot(for: await store.currentState())
          )
        case let .resultRefused(refusal):
          retainAttributionRefusal(refusal, identity: owner.identity)
          return PlotterManualMotionStopResult(
            disposition: .publicationPending,
            snapshot: await snapshot(for: await store.currentState())
          )
        case .alreadyRequested:
          return PlotterManualMotionStopResult(
            disposition: .alreadyRequested,
            snapshot: await snapshot(for: await store.currentState())
          )
        case .unknownCapability, .retiredCapability, .identityMismatch:
          return PlotterManualMotionStopResult(
            disposition: .stale,
            snapshot: await snapshot(for: await store.currentState())
          )
        }
      }
    }
    return PlotterManualMotionStopResult(
      disposition: .stale,
      snapshot: await snapshot(for: await store.currentState())
    )
  }

  private func publishCancellationProgress(
    for owner: ActiveManualMotionOperation,
    phase: PlotterEffectProgressPhase,
    cancellationPhase: PlotterEffectCancellationPhase,
    recoveryCapabilityID: PlotterManualMotionPublicationRecoveryCapabilityID,
    issueStage: PlotterManualMotionTerminalPublicationStage
  ) async -> PlotterManualMotionStopResult? {
    await acquireMutationPublicationBoundary()
    defer { releaseMutationPublicationBoundary() }
    let state = await store.currentState()
    guard let current = state.activeEffectProgress,
          current.episodeID == owner.identity.episodeID,
          current.requestID == owner.identity.requestID,
          current.effectID == owner.identity.effectID else {
      terminalPublicationIssue = PlotterManualMotionTerminalPublicationIssue(
        recoveryCapabilityID: recoveryCapabilityID,
        stage: issueStage,
        summary: "The exact active effect progress was unavailable."
      )
      return PlotterManualMotionStopResult(
        disposition: .publicationPending,
        snapshot: await snapshot(for: state)
      )
    }
    await cancellationPublicationGate?.holdAfterPreStateRead(phase: cancellationPhase)
    do {
      let progress = try PlotterEffectProgress(
        episodeID: current.episodeID,
        requestID: current.requestID,
        intent: current.intent,
        effectID: current.effectID,
        effectRevision: current.effectRevision,
        environment: current.environment,
        lane: current.lane,
        owningSubsystem: current.owningSubsystem,
        phase: phase,
        startedAt: current.startedAt,
        lastAttributableProgressAt: Date(),
        resultCurrentlyAwaited: current.resultCurrentlyAwaited,
        deadline: current.deadline,
        cancellation: PlotterEffectCancellationStatus(
          availability: current.cancellation.availability,
          phase: cancellationPhase
        )
      )
      _ = try await commit(payload: .effectProgressed(progress), origin: .environment)
      terminalPublicationIssue = nil
      return nil
    } catch {
      terminalPublicationIssue = PlotterManualMotionTerminalPublicationIssue(
        recoveryCapabilityID: recoveryCapabilityID,
        stage: issueStage,
        summary: String(describing: error)
      )
      return PlotterManualMotionStopResult(
        disposition: .publicationPending,
        snapshot: await snapshot(for: await store.currentState())
      )
    }
  }

  private func unresolvedStopResult(
    recoveryCapabilityID: PlotterManualMotionPublicationRecoveryCapabilityID,
    summary: String
  ) async -> PlotterManualMotionStopResult {
    terminalPublicationIssue = PlotterManualMotionTerminalPublicationIssue(
      recoveryCapabilityID: recoveryCapabilityID,
      stage: .effectResult,
      summary: summary
    )
    return PlotterManualMotionStopResult(
      disposition: .publicationPending,
      snapshot: await snapshot(for: await store.currentState())
    )
  }

  private func retainAttributionRefusal(
    _ refusal: PlotterOperationResultRefusal<
      ManualMotionOperationContext,
      PlotterManualMotionOperationDisposition
    >,
    identity: PlotterOperationIdentity<ManualMotionOperationContext>
  ) {
    guard active?.identity == identity else { return }
    terminalPublicationIssue = PlotterManualMotionTerminalPublicationIssue(
      recoveryCapabilityID: PlotterManualMotionPublicationRecoveryCapabilityID(),
      stage: .effectResult,
      summary: "Operation result attribution was refused: \(refusal)"
    )
  }

  private func finishNaturally(
    _ result: PlotterOperationResult<
      ManualMotionOperationContext,
      PlotterManualMotionOperationDisposition
    >,
    completionCapability: CompletionCapability<ManualMotionOperationContext>
  ) async {
    switch await registry.settle(result, using: completionCapability) {
    case let .accepted(terminal):
      _ = await publishTerminalIfCurrent(
        identity: terminal.identity,
        disposition: terminal.disposition
      )
    case let .refused(refusal):
      retainAttributionRefusal(refusal, identity: result.identity)
    case .duplicate, .unknownCompletionCapability, .notStarted,
      .cancellationInProgress:
      break
    }
  }

  private func publishTerminalIfCurrent(
    identity: PlotterOperationIdentity<ManualMotionOperationContext>,
    disposition: PlotterManualMotionOperationDisposition,
    recoveryCapabilityID: PlotterManualMotionPublicationRecoveryCapabilityID =
      PlotterManualMotionPublicationRecoveryCapabilityID()
  ) async -> Bool {
    await acquireMutationPublicationBoundary()
    defer { releaseMutationPublicationBoundary() }
    guard let owner = active, owner.identity == identity else { return false }
    await terminalPublicationGate?.holdPublication()

    let normalized = normalize(disposition, for: owner.request)
    pendingTerminalPublication = PendingManualMotionTerminalPublication(
      identity: identity,
      disposition: normalized,
      recoveryCapabilityID: recoveryCapabilityID,
      observations: observations(in: normalized),
      result: effectResult(for: normalized, request: owner.request),
      nextObservationIndex: 0
    )
    return await resumeTerminalPublicationIfCurrentLocked()
  }

  private func resumeTerminalPublicationIfCurrent() async -> Bool {
    await acquireMutationPublicationBoundary()
    defer { releaseMutationPublicationBoundary() }
    return await resumeTerminalPublicationIfCurrentLocked()
  }

  private func resumeTerminalPublicationIfCurrentLocked() async -> Bool {
    guard var pending = pendingTerminalPublication,
          let owner = active,
          owner.identity == pending.identity else { return false }
    while pending.nextObservationIndex < pending.observations.count {
      let observation = pending.observations[pending.nextObservationIndex]
      do {
        _ = try await commit(
          payload: .observationRecorded(observation),
          origin: .environment
        )
        pending.nextObservationIndex += 1
        pendingTerminalPublication = pending
      } catch {
        terminalPublicationIssue = PlotterManualMotionTerminalPublicationIssue(
          recoveryCapabilityID: pending.recoveryCapabilityID,
          stage: .observation,
          summary: String(describing: error)
        )
        pendingTerminalPublication = pending
        return false
      }
    }
    do {
      _ = try await commit(payload: .effectResult(pending.result), origin: .environment)
    } catch {
      terminalPublicationIssue = PlotterManualMotionTerminalPublicationIssue(
        recoveryCapabilityID: pending.recoveryCapabilityID,
        stage: .effectResult,
        summary: String(describing: error)
      )
      pendingTerminalPublication = pending
      return false
    }
    if let diagnostic = await owner.recorder?.diagnostic() {
      lastRecordingDiagnostic = diagnostic
    }
    terminalPublicationIssue = nil
    pendingTerminalPublication = nil
    if active?.identity == pending.identity {
      active = nil
    }
    return true
  }

  private func completeStopTransaction(
    capabilityID: PlotterManualMotionStopCapabilityID,
    result: PlotterManualMotionStopResult
  ) {
    guard let transaction = activeStopTransaction,
      transaction.capabilityID == capabilityID
    else { return }
    activeStopTransaction = nil
    if result.disposition == .settled {
      lastSettledStopResult = (capabilityID, result)
    }
    transaction.waiters.forEach { $0.resume(returning: result) }
  }

  private func normalize(
    _ disposition: PlotterManualMotionOperationDisposition,
    for request: PlotterManualMotionEffectRequest
  ) -> PlotterManualMotionOperationDisposition {
    let environment = request.context.environment
    switch disposition {
    case let .completed(observation):
      guard observation.context.environment == environment else {
        return invalidAdapterResult("Completed observation environment did not match the effect.")
      }
    case let .cancelled(settlement, observation):
      guard observation.context.environment == environment,
        observation.context.id == settlement.observationID
      else {
        return invalidAdapterResult("Cancellation settlement did not match its observation.")
      }
      if case let .jog(jog) = request.intent,
        jog.routing == .drawingStroke,
        case .drawingStoppedWithPenRaised = settlement
      {
        return disposition
      }
      if case let .jog(jog) = request.intent,
        jog.routing == .drawingStroke
      {
        return .ambiguous(
          PlotterEffectAmbiguity(
            summary: "Drawing cancellation did not establish the required Pen-Up settlement.",
            observationIDs: [observation.context.id],
            possibleInk: true
          ),
          observations: [observation]
        )
      }
    case let .ambiguous(ambiguity, observations):
      guard observations.allSatisfy({ $0.context.environment == environment }),
        Set(observations.map(\.context.id)) == Set(ambiguity.observationIDs)
      else {
        return invalidAdapterResult("Ambiguity observations did not match their declared identities.")
      }
    case .cancelledBeforeStart, .refused, .timedOut, .evidenceUnavailable, .failed:
      break
    }
    return disposition
  }

  private func invalidAdapterResult(
    _ summary: String
  ) -> PlotterManualMotionOperationDisposition {
    .failed(PlotterEffectFailure(
      code: .environmentFailure,
      owner: EpisodeAuthorityID(rawValue: "PlotterManualMotionEffectAdapter"),
      summary: summary
    ))
  }

  private func observations(
    in disposition: PlotterManualMotionOperationDisposition
  ) -> [PlotterObservation] {
    switch disposition {
    case let .completed(observation), let .cancelled(_, observation):
      [observation]
    case let .ambiguous(_, observations):
      observations
    case .cancelledBeforeStart, .refused, .timedOut, .evidenceUnavailable, .failed:
      []
    }
  }

  private func effectResult(
    for disposition: PlotterManualMotionOperationDisposition,
    request: PlotterManualMotionEffectRequest
  ) -> PlotterEffectResult {
    let context = PlotterEffectResultContext(
      episodeID: request.context.episodeID,
      requestID: request.context.requestID,
      intent: .manualMotion(request.intent),
      effectID: request.context.effectID,
      environment: request.context.environment,
      effectRevision: request.effectRevision
    )
    switch disposition {
    case .cancelledBeforeStart:
      return .cancelled(context: context)
    case let .completed(observation):
      switch request.intent {
      case .jog:
        return .completed(context: context, output: .motionSettled(observation.context.id))
      case let .setPen(pen):
        return .completed(
          context: context,
          output: .penSettled(
            position: pen.position,
            observationID: observation.context.id
          )
        )
      }
    case let .refused(refusal):
      return .refused(context: context, refusal: refusal)
    case let .cancelled(settlement, _):
      return .cancelledAfterSettlement(context: context, settlement: settlement)
    case let .ambiguous(ambiguity, _):
      return .ambiguous(context: context, ambiguity: ambiguity)
    case let .timedOut(deadline):
      return .timedOut(context: context, deadline: deadline)
    case let .evidenceUnavailable(reason):
      return .evidenceUnavailable(context: context, reason: reason)
    case let .failed(failure):
      return .failed(context: context, failure: failure)
    }
  }

  private func makeRecorder(
    for context: PlotterEffectContext
  ) -> PlotterManualMotionControllerRecorder? {
    guard context.environment == .live, let recordingStore else { return nil }
    return PlotterManualMotionControllerRecorder(
      store: recordingStore,
      provenance: EpisodeRecordingProvenance(
        episodeID: context.episodeID,
        intentRequestID: context.requestID,
        effectID: context.effectID,
        environment: context.environment
      ),
      recordingOriginMonotonicNanoseconds: recordingOriginMonotonicNanoseconds
    )
  }

  private func attribution(
    identity: PlotterOperationIdentity<ManualMotionOperationContext>,
    event: PlotterEpisodeEvent
  ) -> PlotterOperationEventAttribution<ManualMotionOperationContext> {
    PlotterOperationEventAttribution(
      identity: identity,
      eventID: event.id,
      sequence: event.sequence,
      preStateRevision: event.preStateRevision,
      postStateRevision: event.postStateRevision,
      recordedAt: event.recordedAt
    )
  }

  private func commit(
    payload: PlotterEpisodeEventPayload,
    origin: EpisodeEventOrigin,
    recordedAt: Date = Date(),
    artifacts: [EpisodeArtifactReference] = []
  ) async throws -> CommittedManualMotionEvent {
    let preState = await store.currentState()
    let postRevision = EpisodeStateRevision(rawValue: preState.revision.rawValue + 1)
    let provisional = PlotterEpisodeEvent(
      id: EpisodeEventID(rawValue: UUID()),
      episodeID: episodeID,
      sequence: EpisodeEventSequence(rawValue: preState.revision.rawValue),
      recordedAt: recordedAt,
      actor: EpisodeEventActor(
        id: EpisodeActorID(rawValue: "PlotterManualMotionRuntime"),
        origin: origin
      ),
      correlationID: EpisodeCorrelationID(rawValue: UUID()),
      preStateRevision: preState.revision,
      postStateRevision: postRevision,
      payload: payload,
      artifactReferences: artifacts,
      postStateDigest: EpisodeStateDigest(rawValue: "pending")
    )
    let prototype = PlotterEpisodeReducer().reduce(state: preState, event: provisional).state
    let event = PlotterEpisodeEvent(
      id: provisional.id,
      episodeID: provisional.episodeID,
      sequence: provisional.sequence,
      recordedAt: provisional.recordedAt,
      actor: provisional.actor,
      correlationID: provisional.correlationID,
      preStateRevision: provisional.preStateRevision,
      postStateRevision: provisional.postStateRevision,
      payload: provisional.payload,
      artifactReferences: provisional.artifactReferences,
      postStateDigest: try PlotterEpisodeCanonicalDigestV1.digest(prototype)
    )
    let reduction = try await store.append(event)
    return CommittedManualMotionEvent(event: event, state: reduction.state)
  }

  private func snapshot(
    for state: PlotterEpisodeState
  ) async -> PlotterManualMotionRuntimeSnapshot {
    projectionRevision &+= 1
    let journal = await store.currentJournal()
    let recording = await recordingStore?.snapshot()
    let journalDigest = (try? Data(contentsOf: journalFileURL)).map { data in
      SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
    let artifact = EpisodeArtifactReference(
      id: EpisodeArtifactID(rawValue: journalFileURL.lastPathComponent),
      revision: journalSchemaRevision,
      digest: journalDigest
    )
    let incidentReferences = PlotterIncidentSourceArtifactReferences(
      episodeID: episodeID,
      journal: artifact,
      journalFileURL: journalFileURL,
      recordingID: recording?.recordingID,
      recordingDirectoryURL: recordingDirectoryURL,
      recordingDurability: recording?.durability,
      recordingCompletenessIssues: recording?.completenessIssues ?? []
    )
    return PlotterManualMotionRuntimeSnapshot(
      projection: PlotterEpisodeProjector.project(
        state: state,
        availabilities: [],
        revision: PlotterProjectionRevision(rawValue: projectionRevision),
        projectedAt: Date()
      ),
      activeOperation: active?.projection,
      recordingDiagnostic: lastRecordingDiagnostic,
      journal: PlotterManualMotionJournalSnapshot(
        artifact: artifact,
        fileURL: journalFileURL,
        journal: journal
      ),
      recording: recording,
      incidentSourceReferences: incidentReferences,
      terminalPublicationIssue: terminalPublicationIssue,
      evidenceDispositionAction: evidenceDispositionAction(for: state)
    )
  }

  private func evidenceDispositionAction(
    for state: PlotterEpisodeState
  ) -> PlotterManualMotionEvidenceDispositionAction? {
    guard state.phase == .awaitingEvidence,
      let terminal = state.lastTerminalEffect,
      case let .ambiguous(context, ambiguity) = terminal.result,
      case .manualMotion = context.intent,
      ambiguity.observationIDs.count == 1,
      let observationID = ambiguity.observationIDs.first
    else { return nil }
    return PlotterManualMotionEvidenceDispositionAction(
      effectID: context.effectID,
      environment: context.environment,
      observationID: observationID,
      disposition: ambiguity.possibleInk
        ? .acknowledgePossibleInk : .acknowledgeAmbiguity,
      summary: ambiguity.summary
    )
  }

  private func acquireMutationPublicationBoundary() async {
    guard mutationPublicationBoundaryIsHeld else {
      mutationPublicationBoundaryIsHeld = true
      return
    }
    cancellationPublicationGate?.noteMutationWaiter()
    await withCheckedContinuation { continuation in
      mutationPublicationBoundaryWaiters.append(continuation)
    }
  }

  private func releaseMutationPublicationBoundary() {
    guard !mutationPublicationBoundaryWaiters.isEmpty else {
      mutationPublicationBoundaryIsHeld = false
      return
    }
    mutationPublicationBoundaryWaiters.removeFirst().resume()
  }
}
