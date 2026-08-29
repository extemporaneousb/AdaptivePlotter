import EpisodeCore
import Foundation
import PlotterEpisodeModel
import PlotterModel
import PlotterRuntime
import os

/// The controller-commanded operation presented to the causal simulator. The
/// command is distinct from simulator plant, Pen, paper/ink, camera, Vision,
/// and evidence truth. Current workflow owners that do not yet have a target
/// `PlotterIntent` remain explicitly attributed instead of fabricating one.
public enum PlotterCausalSimulatorCommand: Hashable, Sendable {
  case manualJog(PlotterJogRequest)
  case retainedWorkflowBoundary(
    direction: BoundaryDirection,
    finiteSegmentLengthMM: Double,
    owner: EpisodeAuthorityID
  )
  case retainedWorkflowDrawing(
    delta: SimulatedLearningMotionVector,
    owner: EpisodeAuthorityID
  )
  case retainedWorkflowTravel(
    delta: SimulatedLearningMotionVector,
    owner: EpisodeAuthorityID
  )
}

public enum PlotterCausalSimulatorEffectAttribution: Hashable, Sendable {
  case episode(intent: PlotterIntent, effect: PlotterEffect)
  case retainedWorkflow(owner: EpisodeAuthorityID)

  public var intent: PlotterIntent? {
    guard case let .episode(intent, _) = self else { return nil }
    return intent
  }

  public var effect: PlotterEffect? {
    guard case let .episode(_, effect) = self else { return nil }
    return effect
  }
}

/// One exact adapter-owned causal operation. The simulator operation ID is the
/// Stop/cancel/shutdown identity; the typed episode attribution, when present,
/// is immutable for that ID.
public struct PlotterCausalSimulatorOperation: Hashable, Sendable {
  public let id: SimulatedLearningOperationID
  public let command: PlotterCausalSimulatorCommand
  public let attribution: PlotterCausalSimulatorEffectAttribution
  public let evidenceNotice: SimulatedLearningEvidenceNotice

  package let runtimeOperation: SimulatedLearningOperation

  package init(
    runtimeOperation: SimulatedLearningOperation,
    command: PlotterCausalSimulatorCommand,
    attribution: PlotterCausalSimulatorEffectAttribution
  ) {
    id = runtimeOperation.id
    self.runtimeOperation = runtimeOperation
    self.command = command
    self.attribution = attribution
    evidenceNotice = .notPhysicalEvidence
  }
}

public enum PlotterCausalSimulatorVisionTruth: String, Codable, Hashable, Sendable {
  /// The causal environment publishes frames. Only `VisionWorker` may derive a
  /// measurement from them; the simulator adapter never fabricates Vision.
  case notComputedBySimulator
}

/// Source-separated causal truth. `controllerCommand` is command attribution;
/// `plantPosition` and `penPose` are plant truth; ink and paper identity are
/// separate from camera publication; Vision and evidence are explicit limits.
public struct PlotterCausalSimulatorTruthSnapshot: Hashable, Sendable {
  public let controllerCommand: PlotterCausalSimulatorOperation?
  public let plantPosition: SimulatedLearningMPos
  public let penPose: SimulatedLearningPenPose
  public let paperRevision: UUID
  public let ink: [SimulatedLearningInkSegment]
  public let cameraConfigurationID: CameraConfigurationID
  public let cameraViewportID: SimulatedCameraViewportID
  public let cameraFrameSequence: UInt64
  public let latestCausalFrame: SimulatedLearningSceneFrame?
  public let visionTruth: PlotterCausalSimulatorVisionTruth
  public let visionAuthority: EpisodeAuthorityID
  public let evidenceClass: PlotterEvidenceClass
  public let physicalEvidenceClaimed: Bool
  public let runtime: SimulatedLearningSnapshot
  public let evidenceNotice: SimulatedLearningEvidenceNotice

  package init(
    controllerCommand: PlotterCausalSimulatorOperation?,
    runtime: SimulatedLearningSnapshot,
    ink: [SimulatedLearningInkSegment],
    latestCausalFrame: SimulatedLearningSceneFrame?
  ) {
    self.controllerCommand = controllerCommand
    plantPosition = runtime.mpos
    penPose = runtime.penPose
    paperRevision = runtime.toolPaperRevision
    self.ink = ink
    cameraConfigurationID = runtime.cameraConfigurationID
    cameraViewportID = runtime.viewportID
    cameraFrameSequence = runtime.frameSequence
    self.latestCausalFrame = latestCausalFrame
    visionTruth = .notComputedBySimulator
    visionAuthority = EpisodeAuthorityID(rawValue: "VisionWorker")
    evidenceClass = .simulatedCausal
    physicalEvidenceClaimed = false
    self.runtime = runtime
    evidenceNotice = .notPhysicalEvidence
  }
}

public struct PlotterCausalSimulatorAdmissionRefusal: Sendable {
  public let refusal: SimulatedLearningRefusal
  public let effectResult: PlotterEffectResult?
  public let observation: PlotterObservation
  public let truth: PlotterCausalSimulatorTruthSnapshot
  public let evidenceNotice: SimulatedLearningEvidenceNotice

  package init(
    refusal: SimulatedLearningRefusal,
    effectResult: PlotterEffectResult?,
    observation: PlotterObservation,
    truth: PlotterCausalSimulatorTruthSnapshot
  ) {
    self.refusal = refusal
    self.effectResult = effectResult
    self.observation = observation
    self.truth = truth
    evidenceNotice = .notPhysicalEvidence
  }
}

public enum PlotterCausalSimulatorAdmission: Sendable {
  case admitted(PlotterCausalSimulatorOperation)
  case refused(PlotterCausalSimulatorAdmissionRefusal)
}

public struct PlotterCausalSimulatorOperationOutcome: Hashable, Sendable {
  public let operation: PlotterCausalSimulatorOperation
  public let disposition: SimulatedLearningOperationDisposition
  public let finalMPos: SimulatedLearningMPos
  public let completedBoundarySegmentCount: Int
  public let observation: PlotterObservation
  public let effectResult: PlotterEffectResult?
  public let truth: PlotterCausalSimulatorTruthSnapshot
  public let evidenceNotice: SimulatedLearningEvidenceNotice

  package init(
    operation: PlotterCausalSimulatorOperation,
    disposition: SimulatedLearningOperationDisposition,
    finalMPos: SimulatedLearningMPos,
    completedBoundarySegmentCount: Int,
    observation: PlotterObservation,
    effectResult: PlotterEffectResult?,
    truth: PlotterCausalSimulatorTruthSnapshot
  ) {
    self.operation = operation
    self.disposition = disposition
    self.finalMPos = finalMPos
    self.completedBoundarySegmentCount = completedBoundarySegmentCount
    self.observation = observation
    self.effectResult = effectResult
    self.truth = truth
    evidenceNotice = .notPhysicalEvidence
  }
}

public struct PlotterCausalSimulatorImmediateOutcome: Hashable, Sendable {
  public let observation: PlotterObservation
  public let effectResult: PlotterEffectResult?
  public let refusal: SimulatedLearningRefusal?
  public let truth: PlotterCausalSimulatorTruthSnapshot
  public let evidenceNotice: SimulatedLearningEvidenceNotice

  package init(
    observation: PlotterObservation,
    effectResult: PlotterEffectResult?,
    refusal: SimulatedLearningRefusal?,
    truth: PlotterCausalSimulatorTruthSnapshot
  ) {
    self.observation = observation
    self.effectResult = effectResult
    self.refusal = refusal
    self.truth = truth
    evidenceNotice = .notPhysicalEvidence
  }
}

/// Deterministic package-test handshake at the sole gap between lower-runtime
/// terminal settlement and adapter truth publication. It can hold timing only;
/// it cannot choose an effect, terminal disposition, cancellation, or result.
package actor PlotterCausalSimulatorTerminalPublicationGate {
  private var heldOperationID: SimulatedLearningOperationID?
  private var releasedOperationIDs: Set<SimulatedLearningOperationID> = []
  private var heldWaiters:
    [CheckedContinuation<SimulatedLearningOperationID, Never>] = []
  private var releaseWaiters:
    [SimulatedLearningOperationID: [CheckedContinuation<Void, Never>]] = [:]

  package init() {}

  package func waitUntilHeld() async -> SimulatedLearningOperationID {
    if let heldOperationID { return heldOperationID }
    return await withCheckedContinuation { heldWaiters.append($0) }
  }

  package func release(operationID: SimulatedLearningOperationID) {
    precondition(
      heldOperationID == operationID,
      "Only the exact held simulator operation may be released."
    )
    releasedOperationIDs.insert(operationID)
    heldOperationID = nil
    let waiters = releaseWaiters.removeValue(forKey: operationID) ?? []
    waiters.forEach { $0.resume() }
  }

  fileprivate func holdBeforePublication(
    operationID: SimulatedLearningOperationID
  ) async {
    if releasedOperationIDs.contains(operationID) { return }
    await withCheckedContinuation { continuation in
      precondition(
        heldOperationID == nil || heldOperationID == operationID,
        "The terminal publication gate may hold only one exact operation."
      )
      releaseWaiters[operationID, default: []].append(continuation)
      guard heldOperationID == nil else { return }
      heldOperationID = operationID
      let waiters = heldWaiters
      heldWaiters.removeAll()
      waiters.forEach { $0.resume(returning: operationID) }
    }
  }
}

/// Mutable execution pacing is test scheduling policy, never effect authority.
/// The lock gives synchronous composition replacement a single exact value
/// that the adapter snapshots immediately before each causal execution.
private final class PlotterCausalSimulatorExecutionPacingAuthority: Sendable {
  private let value: OSAllocatedUnfairLock<any SimulatedLearningExecutionPacing>

  init(_ initialValue: any SimulatedLearningExecutionPacing) {
    value = OSAllocatedUnfairLock(initialState: initialValue)
  }

  func replace(with replacement: any SimulatedLearningExecutionPacing) {
    value.withLock { $0 = replacement }
  }

  func current() -> any SimulatedLearningExecutionPacing {
    value.withLock { $0 }
  }
}

private actor PlotterCausalSimulatorEffectAuthority {
  static let effectRevision = EpisodeRevisionIdentifier(
    rawValue: "plotter-causal-simulator-effect-v1"
  )

  let runtime: SimulatedLearningRuntime
  let pacingAuthority: PlotterCausalSimulatorExecutionPacingAuthority
  let terminalPublicationGate: PlotterCausalSimulatorTerminalPublicationGate?
  private var operations: [SimulatedLearningOperationID: PlotterCausalSimulatorOperation] = [:]
  private var outcomes:
    [SimulatedLearningOperationID: PlotterCausalSimulatorOperationOutcome] = [:]
  /// The admitted owner remains reserved after lower-runtime settlement until
  /// this actor publishes and caches the corresponding terminal outcome.
  private var activeOperation: PlotterCausalSimulatorOperation?

  init(
    runtime: SimulatedLearningRuntime,
    pacingAuthority: PlotterCausalSimulatorExecutionPacingAuthority,
    terminalPublicationGate: PlotterCausalSimulatorTerminalPublicationGate?
  ) {
    self.runtime = runtime
    self.pacingAuthority = pacingAuthority
    self.terminalPublicationGate = terminalPublicationGate
  }

  func admit(
    command: PlotterCausalSimulatorCommand,
    attribution: PlotterCausalSimulatorEffectAttribution
  ) async -> PlotterCausalSimulatorAdmission {
    let rawKind: SimulatedLearningOperationKind
    let permitsPossibleInk: Bool
    do {
      switch command {
      case let .manualJog(request):
        rawKind = request.routing == .drawingStroke
          ? .drawing(try motionVector(for: request))
          : .manualJog(try motionVector(for: request))
        permitsPossibleInk = request.routing == .possibleInk
      case let .retainedWorkflowBoundary(direction, finiteSegmentLengthMM, _):
        rawKind = .boundary(
          direction: direction,
          finiteSegmentLengthMM: finiteSegmentLengthMM
        )
        permitsPossibleInk = false
      case let .retainedWorkflowDrawing(delta, _):
        rawKind = .drawing(delta)
        permitsPossibleInk = false
      case let .retainedWorkflowTravel(delta, _):
        rawKind = .manualJog(delta)
        permitsPossibleInk = false
      }
    } catch {
      let truth = await truthSnapshot()
      let observation = causalObservation(truth.runtime)
      let refusal = SimulatedLearningRefusal.resultingPositionNonFinite
      return .refused(PlotterCausalSimulatorAdmissionRefusal(
        refusal: refusal,
        effectResult: typedRefusal(
          refusal,
          attribution: attribution,
          truth: truth,
          observation: observation
        ),
        observation: observation,
        truth: truth
      ))
    }

    if let activeOperation {
      let truth = await truthSnapshot()
      let observation = causalObservation(truth.runtime)
      let refusal = SimulatedLearningRefusal.operationAlreadyActive(activeOperation.id)
      return .refused(PlotterCausalSimulatorAdmissionRefusal(
        refusal: refusal,
        effectResult: typedRefusal(
          refusal,
          attribution: attribution,
          truth: truth,
          observation: observation
        ),
        observation: observation,
        truth: truth
      ))
    }

    let response = await runtime.admitCausalOperation(
      rawKind,
      permitsUnknownPenStateAsPossibleInk: permitsPossibleInk
    )
    switch response.result {
    case let .success(runtimeOperation):
      let operation = PlotterCausalSimulatorOperation(
        runtimeOperation: runtimeOperation,
        command: command,
        attribution: attribution
      )
      operations[operation.id] = operation
      activeOperation = operation
      return .admitted(operation)
    case let .failure(refusal):
      let truth = await truthSnapshot()
      let observation = causalObservation(truth.runtime)
      return .refused(PlotterCausalSimulatorAdmissionRefusal(
        refusal: refusal,
        effectResult: typedRefusal(
          refusal,
          attribution: attribution,
          truth: truth,
          observation: observation
        ),
        observation: observation,
        truth: truth
      ))
    }
  }

  func executeNaturally(
    _ operation: PlotterCausalSimulatorOperation
  ) async -> PlotterCausalSimulatorOperationOutcome {
    guard operations[operation.id] == operation else {
      return await unownedOutcome(
        operation,
        reason: "The adapter does not own the requested simulator operation ID."
      )
    }
    if let outcome = outcomes[operation.id] { return outcome }
    let response = await runtime.executeNaturally(
      operation.id,
      pacing: pacingAuthority.current()
    )
    return await settle(operation, response: response)
  }

  func executeBoundaryCooperatively(
    _ operation: PlotterCausalSimulatorOperation
  ) async -> PlotterCausalSimulatorOperationOutcome {
    guard operations[operation.id] == operation else {
      return await unownedOutcome(
        operation,
        reason: "The adapter does not own the requested Boundary operation ID."
      )
    }
    if let outcome = outcomes[operation.id] { return outcome }
    let response = await runtime.executeBoundaryCooperatively(
      operation.id,
      pacing: pacingAuthority.current()
    )
    return await settle(operation, response: response)
  }

  func request(
    _ intent: SimulatedLearningOperationIntent,
    for operation: PlotterCausalSimulatorOperation
  ) async -> PlotterCausalSimulatorOperationOutcome {
    guard operations[operation.id] == operation else {
      return await unownedOutcome(
        operation,
        reason: "The adapter does not own the requested cancellation operation ID."
      )
    }
    if let outcome = outcomes[operation.id] { return outcome }
    let response = await runtime.request(intent, for: operation.id)
    return await settle(operation, response: response)
  }

  func waitForOutcome(
    of operation: PlotterCausalSimulatorOperation
  ) async -> PlotterCausalSimulatorOperationOutcome {
    guard operations[operation.id] == operation else {
      return await unownedOutcome(
        operation,
        reason: "The adapter does not own the requested outcome operation ID."
      )
    }
    if let outcome = outcomes[operation.id] { return outcome }
    return await settle(operation, response: await runtime.waitForOutcome(of: operation.id))
  }

  func executePen(
    _ request: PlotterManualMotionEffectRequest
  ) async -> PlotterCausalSimulatorImmediateOutcome {
    let attribution = attribution(for: request)
    let pose: SimulatedLearningPenPose
    guard case let .setPen(pen) = request.intent else {
      let truth = await truthSnapshot()
      let observation = causalObservation(truth.runtime)
      return PlotterCausalSimulatorImmediateOutcome(
        observation: observation,
        effectResult: .failed(
          context: resultContext(for: attribution)!,
          failure: environmentFailure("The adapter received a non-Pen immediate effect.")
        ),
        refusal: nil,
        truth: truth
      )
    }
    pose = pen.position == .raised ? .up : .down
    return await executePenPose(
      pose,
      attribution: attribution,
      episodePosition: pen.position
    )
  }

  func executeRetainedWorkflowPen(
    _ pose: SimulatedLearningPenPose,
    owner: EpisodeAuthorityID
  ) async -> PlotterCausalSimulatorImmediateOutcome {
    await executePenPose(
      pose,
      attribution: .retainedWorkflow(owner: owner),
      episodePosition: nil
    )
  }

  private func executePenPose(
    _ pose: SimulatedLearningPenPose,
    attribution: PlotterCausalSimulatorEffectAttribution,
    episodePosition: PlotterPenPosition?
  ) async -> PlotterCausalSimulatorImmediateOutcome {
    if let activeOperation {
      let truth = makeTruthSnapshot(from: await runtime.causalTruthSnapshot())
      let observation = causalObservation(truth.runtime)
      let refusal = SimulatedLearningRefusal.operationAlreadyActive(activeOperation.id)
      return PlotterCausalSimulatorImmediateOutcome(
        observation: observation,
        effectResult: typedRefusal(
          refusal,
          attribution: attribution,
          truth: truth,
          observation: observation
        ),
        refusal: refusal,
        truth: truth
      )
    }

    let mutation = await runtime.setPenPoseWithCausalTruth(pose)
    let truth = makeTruthSnapshot(from: mutation.truth)
    let observation = causalObservation(truth.runtime)
    let result: PlotterEffectResult?
    let refusal: SimulatedLearningRefusal?
    switch mutation.response.result {
    case .success:
      refusal = nil
      if let context = resultContext(for: attribution), let episodePosition {
        result = .completed(
          context: context,
          output: .penSettled(
            position: episodePosition,
            observationID: observation.context.id
          )
        )
      } else {
        result = nil
      }
    case let .failure(lowerRefusal):
      refusal = lowerRefusal
      result = typedRefusal(
        lowerRefusal,
        attribution: attribution,
        truth: truth,
        observation: observation
      )
    }
    return PlotterCausalSimulatorImmediateOutcome(
      observation: observation,
      effectResult: result,
      refusal: refusal,
      truth: truth
    )
  }

  func truthSnapshot() async -> PlotterCausalSimulatorTruthSnapshot {
    makeTruthSnapshot(from: await runtime.causalTruthSnapshot())
  }

  private func makeTruthSnapshot(
    from lowerTruth: SimulatedLearningCausalTruth
  ) -> PlotterCausalSimulatorTruthSnapshot {
    let active = lowerTruth.snapshot.currentOperation.flatMap { operations[$0.id] }
    return PlotterCausalSimulatorTruthSnapshot(
      controllerCommand: active,
      runtime: lowerTruth.snapshot,
      ink: lowerTruth.persistentInk,
      latestCausalFrame: lowerTruth.latestPublishedCausalFrame
    )
  }

  private func settle(
    _ operation: PlotterCausalSimulatorOperation,
    response: SimulatedLearningResponse<SimulatedLearningOperationOutcome>
  ) async -> PlotterCausalSimulatorOperationOutcome {
    if let outcome = outcomes[operation.id] { return outcome }
    switch response.result {
    case let .success(runtimeOutcome):
      await terminalPublicationGate?.holdBeforePublication(operationID: operation.id)
      if let outcome = outcomes[operation.id] { return outcome }
      let truth = await truthSnapshot()
      return publishTerminalOutcome(
        operation,
        runtimeOutcome: runtimeOutcome,
        truth: truth
      )
    case let .failure(refusal):
      if case let .operationAlreadySettled(operationID, _) = refusal,
        operationID == operation.id
      {
        let terminalResponse = await runtime.waitForOutcome(of: operation.id)
        return await settle(operation, response: terminalResponse)
      }
      return await unavailableOutcome(
        operation,
        reason: "Simulator settlement was unavailable: \(refusal)."
      )
    }
  }

  /// Publishes one adapter outcome for the runtime's exact terminal result.
  /// There is deliberately no suspension between the cache check and write:
  /// concurrent execution, Stop/cancel/shutdown, and outcome-wait paths all
  /// return the first actor-isolated publication, including its observation.
  private func publishTerminalOutcome(
    _ operation: PlotterCausalSimulatorOperation,
    runtimeOutcome: SimulatedLearningOperationOutcome,
    truth: PlotterCausalSimulatorTruthSnapshot
  ) -> PlotterCausalSimulatorOperationOutcome {
    if let outcome = outcomes[operation.id] { return outcome }
    let observation = causalObservation(truth.runtime)
    let outcome = PlotterCausalSimulatorOperationOutcome(
      operation: operation,
      disposition: runtimeOutcome.disposition,
      finalMPos: runtimeOutcome.finalMPos,
      completedBoundarySegmentCount: runtimeOutcome.completedBoundarySegmentCount,
      observation: observation,
      effectResult: typedResult(
        for: runtimeOutcome.disposition,
        operation: operation,
        observation: observation,
        truth: truth
      ),
      truth: truth
    )
    outcomes[operation.id] = outcome
    if activeOperation == operation { activeOperation = nil }
    return outcome
  }

  private func unownedOutcome(
    _ operation: PlotterCausalSimulatorOperation,
    reason: String
  ) async -> PlotterCausalSimulatorOperationOutcome {
    let truth = await truthSnapshot()
    let observation = causalObservation(truth.runtime)
    let result = resultContext(for: operation.attribution).map {
      PlotterEffectResult.evidenceUnavailable(context: $0, reason: reason)
    }
    return PlotterCausalSimulatorOperationOutcome(
      operation: operation,
      disposition: .failed,
      finalMPos: truth.plantPosition,
      completedBoundarySegmentCount: 0,
      observation: observation,
      effectResult: result,
      truth: truth
    )
  }

  private func unavailableOutcome(
    _ operation: PlotterCausalSimulatorOperation,
    reason: String
  ) async -> PlotterCausalSimulatorOperationOutcome {
    if let outcome = outcomes[operation.id] { return outcome }
    let truth = await truthSnapshot()
    return publishUnavailableOutcome(operation, reason: reason, truth: truth)
  }

  private func publishUnavailableOutcome(
    _ operation: PlotterCausalSimulatorOperation,
    reason: String,
    truth: PlotterCausalSimulatorTruthSnapshot
  ) -> PlotterCausalSimulatorOperationOutcome {
    if let outcome = outcomes[operation.id] { return outcome }
    let observation = causalObservation(truth.runtime)
    let result = resultContext(for: operation.attribution).map {
      PlotterEffectResult.evidenceUnavailable(context: $0, reason: reason)
    }
    let outcome = PlotterCausalSimulatorOperationOutcome(
      operation: operation,
      disposition: .failed,
      finalMPos: truth.plantPosition,
      completedBoundarySegmentCount: 0,
      observation: observation,
      effectResult: result,
      truth: truth
    )
    outcomes[operation.id] = outcome
    if activeOperation == operation { activeOperation = nil }
    return outcome
  }

  private func typedResult(
    for disposition: SimulatedLearningOperationDisposition,
    operation: PlotterCausalSimulatorOperation,
    observation: PlotterObservation,
    truth: PlotterCausalSimulatorTruthSnapshot
  ) -> PlotterEffectResult? {
    guard let context = resultContext(for: operation.attribution) else { return nil }
    switch disposition {
    case .naturallyCompleted:
      return .completed(
        context: context,
        output: .motionSettled(observation.context.id)
      )
    case .stopped, .cancelled, .shutdown:
      let settlement: PlotterEffectCancellationSettlement
      switch operation.command {
      case .retainedWorkflowDrawing:
        settlement = .drawingStoppedWithPenRaised(
          observationID: observation.context.id,
          possibleInk: true
        )
      case let .manualJog(request):
        settlement = .controllerSettled(
          observationID: observation.context.id,
          possibleInk: request.routing != .relativeTravel
        )
      case .retainedWorkflowBoundary, .retainedWorkflowTravel:
        settlement = .controllerSettled(
          observationID: observation.context.id,
          possibleInk: false
        )
      }
      return .cancelledAfterSettlement(context: context, settlement: settlement)
    case .failed:
      if truth.runtime.stickyAmbiguity != nil {
        return .ambiguous(
          context: context,
          ambiguity: PlotterEffectAmbiguity(
            summary: "The causal simulator lost attributable segment completion.",
            observationIDs: [observation.context.id],
            possibleInk: truth.penPose != .up
          )
        )
      }
      return .failed(
        context: context,
        failure: environmentFailure("The causal simulator operation failed.")
      )
    }
  }

  private func typedRefusal(
    _ refusal: SimulatedLearningRefusal,
    attribution: PlotterCausalSimulatorEffectAttribution,
    truth: PlotterCausalSimulatorTruthSnapshot,
    observation: PlotterObservation
  ) -> PlotterEffectResult? {
    guard let context = resultContext(for: attribution) else { return nil }
    if case .stickyAmbiguity = refusal {
      return .ambiguous(
        context: context,
        ambiguity: PlotterEffectAmbiguity(
          summary: "The causal simulator has unresolved operation ambiguity.",
          observationIDs: [observation.context.id],
          possibleInk: truth.penPose != .up
        )
      )
    }
    return .refused(
      context: context,
      refusal: PlotterEffectRefusal(
        requirementID: requirement(for: refusal),
        owner: EpisodeAuthorityID(rawValue: "SimulatedLearningRuntime"),
        comparedRevision: Self.effectRevision,
        remedy: "Resolve causal simulator refusal: \(refusal)."
      )
    )
  }

  private func resultContext(
    for attribution: PlotterCausalSimulatorEffectAttribution
  ) -> PlotterEffectResultContext? {
    guard case let .episode(intent, effect) = attribution else { return nil }
    return PlotterEffectResultContext(
      episodeID: effect.context.episodeID,
      requestID: effect.context.requestID,
      intent: intent,
      effectID: effect.context.effectID,
      environment: .simulated,
      effectRevision: Self.effectRevision
    )
  }

  private func attribution(
    for request: PlotterManualMotionEffectRequest
  ) -> PlotterCausalSimulatorEffectAttribution {
    let intent = PlotterIntent.manualMotion(request.intent)
    let effect: PlotterEffect = switch request.intent {
    case let .jog(jog): .performManualMotion(context: request.context, request: jog)
    case let .setPen(pen): .setPen(context: request.context, request: pen)
    }
    return .episode(intent: intent, effect: effect)
  }

  private func requirement(
    for refusal: SimulatedLearningRefusal
  ) -> EpisodeRequirementID {
    let rawValue: String = switch refusal {
    case .sessionDisconnected, .sessionAlreadyConnected, .sessionAlreadyDisconnected:
      "plotter.simulatorSessionState"
    case .motionAuthorizationDisabled:
      "plotter.motionEnabled"
    case .operationAlreadyActive, .operationAlreadySettled, .staleOperation:
      "plotter.simulatorOperationIdentity"
    case .penMustBeUp, .penMustBeDown:
      "plotter.simulatorPenPose"
    case .stickyAmbiguity:
      "plotter.simulatorAmbiguityResolved"
    case .invalidBoundarySegmentLength, .resultingPositionNonFinite,
      .operationIsNotBoundary, .boundaryRequiresStopOrCancel, .injectedRefusal,
      .frameRenderingFailed:
      "plotter.simulatorCommandValid"
    }
    return EpisodeRequirementID(rawValue: rawValue)
  }

  private func motionVector(
    for request: PlotterJogRequest
  ) throws -> SimulatedLearningMotionVector {
    switch request.direction {
    case .positiveX:
      return try SimulatedLearningMotionVector(dxMM: request.distanceMM, dyMM: 0)
    case .negativeX:
      return try SimulatedLearningMotionVector(dxMM: -request.distanceMM, dyMM: 0)
    case .positiveY:
      return try SimulatedLearningMotionVector(dxMM: 0, dyMM: request.distanceMM)
    case .negativeY:
      return try SimulatedLearningMotionVector(dxMM: 0, dyMM: -request.distanceMM)
    }
  }
}

/// The sole effect-capable causal-simulator environment seam. It shares the
/// EA-06 adapter grammar for manual effects and also hosts transitional,
/// explicitly attributed lower-level workflow commands until their later
/// semantic packages land.
public struct PlotterCausalSimulatorEffectAdapter:
  PlotterManualMotionEffectAdapter, Sendable
{
  public let environment = PlotterEnvironment.simulated
  private let authority: PlotterCausalSimulatorEffectAuthority
  private let pacingAuthority: PlotterCausalSimulatorExecutionPacingAuthority

  public init(
    runtime: SimulatedLearningRuntime,
    pacing: any SimulatedLearningExecutionPacing = SimulatedLearningInteractivePacing()
  ) {
    self.init(
      runtime: runtime,
      pacing: pacing,
      terminalPublicationGate: nil
    )
  }

  package init(
    runtime: SimulatedLearningRuntime,
    pacing: any SimulatedLearningExecutionPacing = SimulatedLearningInteractivePacing(),
    terminalPublicationGate: PlotterCausalSimulatorTerminalPublicationGate
  ) {
    self.init(
      runtime: runtime,
      pacing: pacing,
      terminalPublicationGate: Optional(terminalPublicationGate)
    )
  }

  private init(
    runtime: SimulatedLearningRuntime,
    pacing: any SimulatedLearningExecutionPacing,
    terminalPublicationGate: PlotterCausalSimulatorTerminalPublicationGate?
  ) {
    let pacingAuthority = PlotterCausalSimulatorExecutionPacingAuthority(pacing)
    self.pacingAuthority = pacingAuthority
    authority = PlotterCausalSimulatorEffectAuthority(
      runtime: runtime,
      pacingAuthority: pacingAuthority,
      terminalPublicationGate: terminalPublicationGate
    )
  }

  /// Replaces only future execution suspension policy. Active operation,
  /// effect identity, plant state, and Stop/cancel authority are unchanged.
  public func replaceExecutionPacing(
    _ replacement: any SimulatedLearningExecutionPacing
  ) {
    pacingAuthority.replace(with: replacement)
  }

  public func admitManualJog(
    _ request: PlotterManualMotionEffectRequest
  ) async -> PlotterCausalSimulatorAdmission {
    guard case let .jog(jog) = request.intent else {
      preconditionFailure("Pen effects do not create causal motion operations.")
    }
    return await authority.admit(
      command: .manualJog(jog),
      attribution: .episode(
        intent: .manualMotion(request.intent),
        effect: .performManualMotion(context: request.context, request: jog)
      )
    )
  }

  public func admitRetainedWorkflowBoundary(
    direction: BoundaryDirection,
    finiteSegmentLengthMM: Double,
    owner: EpisodeAuthorityID
  ) async -> PlotterCausalSimulatorAdmission {
    return await authority.admit(
      command: .retainedWorkflowBoundary(
        direction: direction,
        finiteSegmentLengthMM: finiteSegmentLengthMM,
        owner: owner
      ),
      attribution: .retainedWorkflow(owner: owner)
    )
  }

  public func admitRetainedWorkflowDrawing(
    delta: SimulatedLearningMotionVector,
    owner: EpisodeAuthorityID
  ) async -> PlotterCausalSimulatorAdmission {
    return await authority.admit(
      command: .retainedWorkflowDrawing(delta: delta, owner: owner),
      attribution: .retainedWorkflow(owner: owner)
    )
  }

  public func admitRetainedWorkflowTravel(
    delta: SimulatedLearningMotionVector,
    owner: EpisodeAuthorityID
  ) async -> PlotterCausalSimulatorAdmission {
    await authority.admit(
      command: .retainedWorkflowTravel(delta: delta, owner: owner),
      attribution: .retainedWorkflow(owner: owner)
    )
  }

  public func executeNaturally(
    _ operation: PlotterCausalSimulatorOperation
  ) async -> PlotterCausalSimulatorOperationOutcome {
    await authority.executeNaturally(operation)
  }

  public func executeBoundaryCooperatively(
    _ operation: PlotterCausalSimulatorOperation
  ) async -> PlotterCausalSimulatorOperationOutcome {
    await authority.executeBoundaryCooperatively(operation)
  }

  public func request(
    _ intent: SimulatedLearningOperationIntent,
    for operation: PlotterCausalSimulatorOperation
  ) async -> PlotterCausalSimulatorOperationOutcome {
    await authority.request(intent, for: operation)
  }

  public func waitForOutcome(
    of operation: PlotterCausalSimulatorOperation
  ) async -> PlotterCausalSimulatorOperationOutcome {
    await authority.waitForOutcome(of: operation)
  }

  public func truthSnapshot() async -> PlotterCausalSimulatorTruthSnapshot {
    await authority.truthSnapshot()
  }

  public func executeRetainedWorkflowPen(
    _ pose: SimulatedLearningPenPose,
    owner: EpisodeAuthorityID
  ) async -> PlotterCausalSimulatorImmediateOutcome {
    await authority.executeRetainedWorkflowPen(pose, owner: owner)
  }

  public func makeOperation(
    for request: PlotterManualMotionEffectRequest,
    controllerRecorder _: PlotterManualMotionControllerRecorder?
  ) -> any PlotterManualMotionOperation {
    PlotterCausalSimulatorManualMotionOperation(adapter: self, request: request)
  }

  fileprivate func admit(
    _ request: PlotterManualMotionEffectRequest
  ) async -> PlotterCausalSimulatorAdmission {
    await admitManualJog(request)
  }

  fileprivate func executePen(
    _ request: PlotterManualMotionEffectRequest
  ) async -> PlotterCausalSimulatorImmediateOutcome {
    await authority.executePen(request)
  }

}

private actor PlotterCausalSimulatorManualMotionOperation: PlotterManualMotionOperation {
  private let adapter: PlotterCausalSimulatorEffectAdapter
  private let request: PlotterManualMotionEffectRequest
  private var didStart = false
  private var cancellationRequested = false
  private var operation: PlotterCausalSimulatorOperation?
  private var result: PlotterManualMotionOperationResult?
  private var waiters: [CheckedContinuation<PlotterManualMotionOperationResult, Never>] = []

  init(
    adapter: PlotterCausalSimulatorEffectAdapter,
    request: PlotterManualMotionEffectRequest
  ) {
    self.adapter = adapter
    self.request = request
  }

  func start() async {
    guard !didStart else { return }
    didStart = true
    switch request.intent {
    case .jog:
      switch await adapter.admit(request) {
      case let .admitted(operation):
        self.operation = operation
        if cancellationRequested {
          _ = await adapter.request(.stop, for: operation)
        }
        Task { [weak self] in await self?.settle(operation) }
      case let .refused(refusal):
        publish(manualDisposition(
          refusal.effectResult,
          observation: refusal.observation
        ))
      }
    case .setPen:
      let outcome = await adapter.executePen(request)
      publish(manualDisposition(outcome.effectResult, observation: outcome.observation))
    }
  }

  func requestCancellation() async {
    guard !cancellationRequested else { return }
    cancellationRequested = true
    if let operation { _ = await adapter.request(.stop, for: operation) }
  }

  func waitForSettlement() async -> PlotterManualMotionOperationResult {
    if let result { return result }
    return await withCheckedContinuation { waiters.append($0) }
  }

  private func settle(_ operation: PlotterCausalSimulatorOperation) async {
    let outcome = await adapter.executeNaturally(operation)
    publish(manualDisposition(outcome.effectResult, observation: outcome.observation))
  }

  private func publish(_ disposition: PlotterManualMotionOperationDisposition) {
    guard result == nil else { return }
    let value = PlotterManualMotionOperationResult(
      identity: PlotterManualMotionOperationIdentity(request: request),
      disposition: disposition
    )
    result = value
    let continuations = waiters
    waiters.removeAll()
    continuations.forEach { $0.resume(returning: value) }
  }
}

private func manualDisposition(
  _ result: PlotterEffectResult?,
  observation: PlotterObservation
) -> PlotterManualMotionOperationDisposition {
  guard let result else {
    return .failed(environmentFailure(
      "The causal simulator returned no episode result for an episode-attributed operation."
    ))
  }
  switch result {
  case .completed:
    return .completed(observation: observation)
  case let .refused(_, refusal):
    return .refused(refusal)
  case .cancelled:
    return .cancelledBeforeStart
  case let .cancelledAfterSettlement(_, settlement):
    return .cancelled(settlement: settlement, observation: observation)
  case let .ambiguous(_, ambiguity):
    return .ambiguous(ambiguity, observations: [observation])
  case let .timedOut(_, deadline):
    return .timedOut(deadline: deadline)
  case let .evidenceUnavailable(_, reason):
    return .evidenceUnavailable(reason: reason)
  case let .failed(_, failure):
    return .failed(failure)
  }
}

private func causalObservation(_ snapshot: SimulatedLearningSnapshot) -> PlotterObservation {
  .controller(PlotterControllerObservation(
    context: PlotterObservationContext(
      id: PlotterObservationID(rawValue: UUID()),
      observedAt: Date(),
      environment: .simulated,
      source: .causalSimulator,
      sourceRevision: PlotterCausalSimulatorEffectAuthority.effectRevision
    ),
    status: snapshot.currentOperation == nil ? .idle : .running,
    machinePosition: try? Point2(x: snapshot.mpos.xMM, y: snapshot.mpos.yMM),
    motionEnabled: snapshot.motionAuthorization == .enabled
  ))
}

private func environmentFailure(_ summary: String) -> PlotterEffectFailure {
  PlotterEffectFailure(
    code: .environmentFailure,
    owner: EpisodeAuthorityID(rawValue: "PlotterCausalSimulatorEffectAdapter"),
    summary: summary
  )
}
