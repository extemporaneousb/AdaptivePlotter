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

/// A boundary operation whose logical owner is already registered with the
/// interpreter. Publishing this handle is the admission acknowledgement; a
/// caller may expose Stop only after it receives the handle.
public struct BoundaryMotionOperation: Sendable {
  public let ownerID: BoundaryMotionOwnerID
  private let task: Task<BoundaryMotionOutcome, Never>

  public init(
    ownerID: BoundaryMotionOwnerID,
    task: Task<BoundaryMotionOutcome, Never>
  ) {
    self.ownerID = ownerID
    self.task = task
  }

  public func outcome() async -> BoundaryMotionOutcome {
    await task.value
  }
}

public enum BoundaryMotionAdmission: Sendable {
  case admitted(BoundaryMotionOperation)
  case rejected(BoundaryMotionOutcome)
}

public struct RelativeJogOperation: Sendable {
  public let id: UUID
  private let task: Task<MotionOutcome, Never>

  public init(id: UUID, task: Task<MotionOutcome, Never>) {
    self.id = id
    self.task = task
  }

  public func outcome() async -> MotionOutcome {
    await task.value
  }
}

public enum RelativeJogAdmission: Sendable {
  case admitted(RelativeJogOperation)
  case rejected(MotionOutcome)
}

public struct DrawingStrokeOperation: Sendable {
  public let id: UUID
  private let task: Task<DrawingStrokeOutcome, Never>

  public init(id: UUID, task: Task<DrawingStrokeOutcome, Never>) {
    self.id = id
    self.task = task
  }

  public func outcome() async -> DrawingStrokeOutcome {
    await task.value
  }
}

public enum DrawingStrokeAdmission: Sendable {
  case admitted(DrawingStrokeOperation)
  case rejected(DrawingStrokeOutcome)
}

/// Handle for the one admitted compound target operation. The logical owner is
/// registered before this handle is returned, so the UI may safely publish its
/// owner-bound Stop capability.
public struct VisibilityTargetOperation: Sendable {
  public let id: UUID
  private let task: Task<VisibilityTargetOperationOutcome, Never>

  public init(id: UUID, task: Task<VisibilityTargetOperationOutcome, Never>) {
    self.id = id
    self.task = task
  }

  public func outcome() async -> VisibilityTargetOperationOutcome {
    await task.value
  }
}

public enum VisibilityTargetAdmission: Sendable {
  case admitted(VisibilityTargetOperation)
  case rejected(VisibilityTargetOperationOutcome)
}

public enum VisibilityTargetIntentOutcome: Hashable, Sendable {
  case accepted(intent: VisibilityTargetOperationIntent, jogCancelOutcome: JogCancelOutcome?)
  case alreadyLatched(VisibilityTargetOperationIntent)
  case staleOperation
}

public enum RunOperation: Hashable, Sendable {
  case idle
  case passiveProbe
  case relativeJog(RelativeJogRequest)
  case boundaryMotion(BoundaryMotionRequest)
  case drawingStroke(DrawingStrokeRequest)
  case visibilityTarget(VisibilityTargetOperationRequest)
  case penActuation(PenCommand)
}

public struct RunInterpreterSnapshot: Hashable, Sendable {
  public let currentOperation: RunOperation
  public let machine: MachineSnapshot
  public let lastMotionOutcome: MotionOutcome?
  public let lastBoundaryMotionOutcome: BoundaryMotionOutcome?
  public let lastDrawingStrokeOutcome: DrawingStrokeOutcome?
  public let lastVisibilityTargetOutcome: VisibilityTargetOperationOutcome?
  public let lastPenOutcome: PenOutcome?
  public let lastProbe: PassiveProbeResult?
  public let jogCancellationInFlight: Bool
  public let lastJogCancelOutcome: JogCancelOutcome?

  public init(
    currentOperation: RunOperation,
    machine: MachineSnapshot,
    lastMotionOutcome: MotionOutcome?,
    lastBoundaryMotionOutcome: BoundaryMotionOutcome? = nil,
    lastDrawingStrokeOutcome: DrawingStrokeOutcome? = nil,
    lastVisibilityTargetOutcome: VisibilityTargetOperationOutcome? = nil,
    lastPenOutcome: PenOutcome? = nil,
    lastProbe: PassiveProbeResult?,
    jogCancellationInFlight: Bool = false,
    lastJogCancelOutcome: JogCancelOutcome? = nil
  ) {
    self.currentOperation = currentOperation
    self.machine = machine
    self.lastMotionOutcome = lastMotionOutcome
    self.lastBoundaryMotionOutcome = lastBoundaryMotionOutcome
    self.lastDrawingStrokeOutcome = lastDrawingStrokeOutcome
    self.lastVisibilityTargetOutcome = lastVisibilityTargetOutcome
    self.lastPenOutcome = lastPenOutcome
    self.lastProbe = lastProbe
    self.jogCancellationInFlight = jogCancellationInFlight
    self.lastJogCancelOutcome = lastJogCancelOutcome
  }
}

/// Serializes the current operator-requested operation. MachineController still
/// owns protocol encoding, safety validation, transport, and physical outcome.
public actor RunInterpreter {
  private struct ActiveBoundaryMotion {
    let request: BoundaryMotionRequest
    var renewalOpen = true
    var cancelIntent: JogCancelIntent?
    var cancelTask: Task<JogCancelOutcome, Never>?
    var cancelOutcome: JogCancelOutcome?
    var completedSegmentCount = 0
    var lastSettledPosition: MachinePosition?
    var completionWaiters: [CheckedContinuation<Void, Never>] = []
  }


  private struct ActiveVisibilityTarget {
    let request: VisibilityTargetOperationRequest
    var phase: VisibilityTargetOperationPhase = .approach
    var scene: VisibilityTargetSceneDisposition = .pristine
    var intent: VisibilityTargetOperationIntent?
    var jogCancelTask: Task<JogCancelOutcome, Never>?
    var jogCancelOutcome: JogCancelOutcome?
    var completionWaiters: [CheckedContinuation<Void, Never>] = []
  }

  private let machineController: MachineController
  private var generation: UInt64 = 0
  private var activeTransition: InterpreterTransitionToken?
  private var currentOperation: RunOperation = .idle
  private var lastProbe: PassiveProbeResult?
  private var lastMotionOutcome: MotionOutcome?
  private var lastBoundaryMotionOutcome: BoundaryMotionOutcome?
  private var lastDrawingStrokeOutcome: DrawingStrokeOutcome?
  private var lastVisibilityTargetOutcome: VisibilityTargetOperationOutcome?
  private var lastPenOutcome: PenOutcome?
  private var activeBoundaryMotion: ActiveBoundaryMotion?
  private var activeVisibilityTarget: ActiveVisibilityTarget?
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
      lastBoundaryMotionOutcome: lastBoundaryMotionOutcome,
      lastDrawingStrokeOutcome: lastDrawingStrokeOutcome,
      lastVisibilityTargetOutcome: lastVisibilityTargetOutcome,
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
    switch beginRelativeJog(request) {
    case .admitted(let operation):
      return await operation.outcome()
    case .rejected(let outcome):
      return outcome
    }
  }

  public func beginRelativeJog(_ request: RelativeJogRequest) -> RelativeJogAdmission {
    guard currentOperation == .idle else {
      let outcome = MotionOutcome.refused(.operationInFlight)
      lastMotionOutcome = outcome
      return .rejected(outcome)
    }
    generation &+= 1
    currentOperation = .relativeJog(request)
    let operationID = UUID()
    let task = Task { await self.runAdmittedRelativeJog(request) }
    return .admitted(RelativeJogOperation(id: operationID, task: task))
  }

  private func runAdmittedRelativeJog(_ request: RelativeJogRequest) async -> MotionOutcome {
    let outcome = await machineController.requestRelativeJog(request)
    lastMotionOutcome = outcome
    if case .relativeJog = currentOperation { currentOperation = .idle }
    return outcome
  }

  /// Registers the logical owner before returning. This closes the UI/runtime
  /// race where Stop could be published while the request task was still
  /// waiting to enter this actor.
  public func beginBoundaryMotion(
    _ request: BoundaryMotionRequest,
    renewalPlanner: BoundaryMotionRenewalPlanner? = nil
  ) async -> BoundaryMotionAdmission {
    guard currentOperation == .idle else {
      let outcome = BoundaryMotionOutcome.needsAttention(
        ownerID: request.ownerID,
        terminal: .refusal(.operationInFlight)
      )
      lastBoundaryMotionOutcome = outcome
      return .rejected(outcome)
    }
    generation &+= 1
    currentOperation = .boundaryMotion(request)
    activeBoundaryMotion = ActiveBoundaryMotion(request: request)
    activeBoundaryMotion?.lastSettledPosition = await machineController.snapshot().position
    let task = Task {
      await self.runAdmittedBoundaryMotion(request, renewalPlanner: renewalPlanner)
    }
    return .admitted(BoundaryMotionOperation(ownerID: request.ownerID, task: task))
  }

  /// Compatibility entry point for non-UI callers. UI composition uses
  /// `beginBoundaryMotion` so it cannot publish Stop before admission.
  public func requestBoundaryMotion(
    _ request: BoundaryMotionRequest
  ) async -> BoundaryMotionOutcome {
    switch await beginBoundaryMotion(request) {
    case .admitted(let operation):
      return await operation.outcome()
    case .rejected(let outcome):
      return outcome
    }
  }

  /// Runs finite GRBL jog segments under one admitted logical Boundary
  /// Discovery owner. Natural segment completion yields and rechecks the Stop
  /// latch before renewal; it is never successful boundary evidence.
  private func runAdmittedBoundaryMotion(
    _ request: BoundaryMotionRequest,
    renewalPlanner: BoundaryMotionRenewalPlanner?
  ) async -> BoundaryMotionOutcome {
    defer {
      if case .boundaryMotion(let current) = currentOperation,
        current.ownerID == request.ownerID
      {
        currentOperation = .idle
      }
      if activeBoundaryMotion?.request.ownerID == request.ownerID {
        let waiters = activeBoundaryMotion?.completionWaiters ?? []
        activeBoundaryMotion = nil
        for waiter in waiters { waiter.resume() }
      }
    }

    var currentSegment = request.segment
    let controllerStartPosition = await machineController.snapshot().position
    guard var segmentStartPosition =
      activeBoundaryMotion?.lastSettledPosition ?? controllerStartPosition
    else {
      return finishBoundaryNeedsAttention(
        request: request,
        terminal: .fault(.transport("boundary motion started without a controller position"))
      )
    }
    while activeBoundaryMotion?.renewalOpen == true {
      if activeBoundaryMotion?.cancelIntent != nil {
        return await finishBoundarySettlement(request: request, segmentOutcome: nil)
      }
      let motionOutcome = await machineController.requestRelativeJog(currentSegment)
      lastMotionOutcome = motionOutcome
      if case .acceptedThenCompleted = motionOutcome {
        activeBoundaryMotion?.completedSegmentCount += 1
      }
      if case .acceptedThenCompleted(let position) = motionOutcome {
        activeBoundaryMotion?.lastSettledPosition = position
      }

      if activeBoundaryMotion?.cancelIntent != nil {
        switch motionOutcome {
        case .acceptedThenCompleted, .cancelled, .refused(.operationInFlight):
          return await finishBoundarySettlement(
            request: request,
            segmentOutcome: motionOutcome
          )
        case .refused(let refusal):
          return finishBoundaryNeedsAttention(
            request: request,
            terminal: Self.boundaryTerminal(for: refusal)
          )
        case .ambiguous(let ambiguity):
          return finishBoundaryNeedsAttention(
            request: request,
            terminal: Self.boundaryTerminal(for: ambiguity)
          )
        }
      }

      switch motionOutcome {
      case .acceptedThenCompleted(let finalPosition):
        let machine = await machineController.snapshot()
        if machine.pins.hasRelevantLimitAsserted {
          return finishBoundaryNeedsAttention(
            request: request,
            terminal: .limitAsserted(
              pins: machine.pins.rawValue,
              finalPosition: finalPosition
            )
          )
        }
        await Task.yield()
        if activeBoundaryMotion?.cancelIntent != nil {
          return await finishBoundarySettlement(
            request: request,
            segmentOutcome: motionOutcome
          )
        }
        guard activeBoundaryMotion?.renewalOpen == true else {
          return finishBoundaryNeedsAttention(
            request: request,
            terminal: .fault(.transport("boundary renewal closed without a disposition"))
          )
        }
        if let renewalPlanner {
          let progress = BoundaryMotionSegmentProgress(
            ownerID: request.ownerID,
            direction: request.direction,
            completedSegmentCount: activeBoundaryMotion?.completedSegmentCount ?? 0,
            completedSegment: currentSegment,
            startPosition: segmentStartPosition,
            finalPosition: finalPosition
          )
          let proposedLength = await renewalPlanner.nextSegmentLength(after: progress)
          if activeBoundaryMotion?.cancelIntent != nil {
            return await finishBoundarySettlement(
              request: request,
              segmentOutcome: motionOutcome
            )
          }
          currentSegment = request.segment(
            lengthMM: request.renewalBounds.clamped(proposedLength)
          )
        }
        segmentStartPosition = finalPosition
      case .cancelled:
        return finishBoundaryNeedsAttention(
          request: request,
          terminal: .fault(.transport("boundary segment cancelled without a typed intent"))
        )
      case .refused(let refusal):
        return finishBoundaryNeedsAttention(
          request: request,
          terminal: Self.boundaryTerminal(for: refusal)
        )
      case .ambiguous(let ambiguity):
        return finishBoundaryNeedsAttention(
          request: request,
          terminal: Self.boundaryTerminal(for: ambiguity)
        )
      }
    }

    return await finishBoundarySettlement(request: request, segmentOutcome: nil)
  }

  public func requestDrawingStroke(
    _ request: DrawingStrokeRequest
  ) async -> DrawingStrokeOutcome {
    switch beginDrawingStroke(request) {
    case .admitted(let operation):
      return await operation.outcome()
    case .rejected(let outcome):
      return outcome
    }
  }

  public func beginDrawingStroke(
    _ request: DrawingStrokeRequest
  ) -> DrawingStrokeAdmission {
    guard currentOperation == .idle else {
      let outcome = DrawingStrokeOutcome.refused(.operationInFlight)
      lastDrawingStrokeOutcome = outcome
      return .rejected(outcome)
    }
    generation &+= 1
    currentOperation = .drawingStroke(request)
    let operationID = UUID()
    let task = Task { await self.runAdmittedDrawingStroke(request) }
    return .admitted(DrawingStrokeOperation(id: operationID, task: task))
  }

  private func runAdmittedDrawingStroke(
    _ request: DrawingStrokeRequest
  ) async -> DrawingStrokeOutcome {
    let outcome = await machineController.requestDrawingStroke(request)
    lastDrawingStrokeOutcome = outcome
    if case .drawingStroke = currentOperation { currentOperation = .idle }
    return outcome
  }

  public func beginVisibilityTarget(
    _ request: VisibilityTargetOperationRequest
  ) -> VisibilityTargetAdmission {
    guard currentOperation == .idle else {
      let outcome = VisibilityTargetOperationOutcome.needsAttention(
        phase: .approach,
        scene: .pristine,
        failure: .approach(.refused(.operationInFlight))
      )
      lastVisibilityTargetOutcome = outcome
      return .rejected(outcome)
    }
    generation &+= 1
    currentOperation = .visibilityTarget(request)
    activeVisibilityTarget = ActiveVisibilityTarget(request: request)
    let task = Task { await self.runAdmittedVisibilityTarget(request) }
    return .admitted(VisibilityTargetOperation(id: request.id, task: task))
  }

  public func requestVisibilityTarget(
    _ request: VisibilityTargetOperationRequest
  ) async -> VisibilityTargetOperationOutcome {
    switch beginVisibilityTarget(request) {
    case .admitted(let operation): await operation.outcome()
    case .rejected(let outcome): outcome
    }
  }

  /// First-intent latch for Stop, Cancel, and shutdown. Only an in-flight Pen-
  /// Up approach or Pen-Down drawing segment has a compatible jog cancel. The
  /// compound owner remains the sole owner while that subordinate cancel
  /// settles.
  public func requestVisibilityTargetIntent(
    _ intent: VisibilityTargetOperationIntent,
    operationID: UUID
  ) async -> VisibilityTargetIntentOutcome {
    guard var active = activeVisibilityTarget, active.request.id == operationID else {
      return .staleOperation
    }
    if let latched = active.intent { return .alreadyLatched(latched) }
    active.intent = intent
    activeVisibilityTarget = active

    let shouldCancelJog: Bool = switch active.phase {
    case .approach, .drawSegment: true
    case .lowerPen, .raisePen: false
    }
    let cancelOutcome: JogCancelOutcome?
    if shouldCancelJog {
      let cancelTask = Task { await machineController.requestJogCancel() }
      if activeVisibilityTarget?.request.id == operationID {
        activeVisibilityTarget?.jogCancelTask = cancelTask
      }
      cancelOutcome = await cancelTask.value
    } else {
      cancelOutcome = nil
    }
    if activeVisibilityTarget?.request.id == operationID {
      activeVisibilityTarget?.jogCancelOutcome = cancelOutcome
    }
    return .accepted(intent: intent, jogCancelOutcome: cancelOutcome)
  }

  private func runAdmittedVisibilityTarget(
    _ request: VisibilityTargetOperationRequest
  ) async -> VisibilityTargetOperationOutcome {
    defer {
      if case .visibilityTarget(let current) = currentOperation, current.id == request.id {
        currentOperation = .idle
      }
      if activeVisibilityTarget?.request.id == request.id {
        let waiters = activeVisibilityTarget?.completionWaiters ?? []
        activeVisibilityTarget = nil
        for waiter in waiters { waiter.resume() }
      }
    }

    guard request.approachFeedMMPerMinute.isFinite,
      request.approachFeedMMPerMinute > 0,
      request.drawingFeedMMPerMinute.isFinite,
      request.drawingFeedMMPerMinute > 0
    else {
      return finishVisibilityTarget(
        .needsAttention(
          phase: .approach,
          scene: .pristine,
          failure: .approach(.refused(.nonPositiveFeed(request.approachFeedMMPerMinute)))
        )
      )
    }

    setVisibilityTargetPhase(.approach, id: request.id)
    let approachOutcome = await machineController.requestRelativeJog(
      request.plan.approachRequest(feedMMPerMinute: request.approachFeedMMPerMinute)
    )
    lastMotionOutcome = approachOutcome
    switch approachOutcome {
    case .acceptedThenCompleted:
      if let disposition = latchedVisibilityTargetDisposition(id: request.id) {
        return await settleVisibilityTargetDisposition(disposition, requestID: request.id)
      }
    case .cancelled:
      guard let disposition = latchedVisibilityTargetDisposition(id: request.id) else {
        return finishVisibilityTarget(.needsAttention(
          phase: .approach,
          scene: .pristine,
          failure: .stoppedWithoutSettlement
        ))
      }
      return await settleVisibilityTargetDisposition(disposition, requestID: request.id)
    case .refused, .ambiguous:
      return finishVisibilityTarget(.needsAttention(
        phase: .approach,
        scene: .pristine,
        failure: .approach(approachOutcome)
      ))
    }

    setVisibilityTargetPhase(.lowerPen, id: request.id)
    let lowerOutcome = await machineController.requestPenActuation(.lower)
    lastPenOutcome = lowerOutcome
    switch lowerOutcome {
    case .commandedAndSettled:
      activeVisibilityTarget?.scene = .inkPossible
      if let disposition = latchedVisibilityTargetDisposition(id: request.id) {
        return await settleVisibilityTargetDisposition(disposition, requestID: request.id)
      }
    case .refused:
      return finishVisibilityTarget(.needsAttention(
        phase: .lowerPen,
        scene: .pristine,
        failure: .pen(lowerOutcome)
      ))
    case .ambiguous:
      activeVisibilityTarget?.scene = .inkPossible
      return finishVisibilityTarget(.needsAttention(
        phase: .lowerPen,
        scene: .inkPossible,
        failure: .pen(lowerOutcome)
      ))
    }

    var finalPosition: MachinePosition?
    let drawingRequests = request.plan.drawingRequests(
      feedMMPerMinute: request.drawingFeedMMPerMinute
    )
    for (index, drawingRequest) in drawingRequests.enumerated() {
      if let disposition = latchedVisibilityTargetDisposition(id: request.id) {
        return await settleVisibilityTargetDisposition(disposition, requestID: request.id)
      }
      setVisibilityTargetPhase(.drawSegment(index), id: request.id)
      let outcome = await machineController.requestDrawingStroke(drawingRequest)
      lastDrawingStrokeOutcome = outcome
      switch outcome {
      case .completed(let evidence):
        finalPosition = evidence.finalPosition
        if let disposition = latchedVisibilityTargetDisposition(id: request.id) {
          return await settleVisibilityTargetDisposition(disposition, requestID: request.id)
        }
      case .cancelled(_, let penRaiseOutcome):
        lastPenOutcome = penRaiseOutcome
        guard let disposition = latchedVisibilityTargetDisposition(id: request.id),
          case .commandedAndSettled = penRaiseOutcome
        else {
          return finishVisibilityTarget(.needsAttention(
            phase: .drawSegment(index),
            scene: .inkPossible,
            failure: .drawing(segmentIndex: index, outcome: outcome)
          ))
        }
        return await settleVisibilityTargetDisposition(disposition, requestID: request.id)
      case .refused:
        if case .refused(.operationInFlight) = outcome,
          let disposition = latchedVisibilityTargetDisposition(id: request.id)
        {
          return await settleVisibilityTargetDisposition(
            disposition,
            requestID: request.id
          )
        }
        return await raiseAfterVisibilityTargetFailure(
          phase: .drawSegment(index),
          failure: .drawing(segmentIndex: index, outcome: outcome),
          requestID: request.id
        )
      case .ambiguous:
        return finishVisibilityTarget(.needsAttention(
          phase: .drawSegment(index),
          scene: .inkPossible,
          failure: .drawing(segmentIndex: index, outcome: outcome)
        ))
      }
    }

    setVisibilityTargetPhase(.raisePen, id: request.id)
    let raiseOutcome = await machineController.requestPenActuation(.raise)
    lastPenOutcome = raiseOutcome
    guard case .commandedAndSettled = raiseOutcome else {
      return finishVisibilityTarget(.needsAttention(
        phase: .raisePen,
        scene: .inkPossible,
        failure: .pen(raiseOutcome)
      ))
    }
    if let disposition = latchedVisibilityTargetDisposition(id: request.id) {
      return await settleVisibilityTargetDisposition(disposition, requestID: request.id)
    }
    guard let finalPosition else {
      return finishVisibilityTarget(.needsAttention(
        phase: .raisePen,
        scene: .inkPossible,
        failure: .stoppedWithoutSettlement
      ))
    }
    return finishVisibilityTarget(.completed(finalPosition: finalPosition, scene: .inkPossible))
  }

  private func raiseAfterVisibilityTargetFailure(
    phase: VisibilityTargetOperationPhase,
    failure: VisibilityTargetOperationFailure,
    requestID: UUID
  ) async -> VisibilityTargetOperationOutcome {
    setVisibilityTargetPhase(.raisePen, id: requestID)
    let raiseOutcome = await machineController.requestPenActuation(.raise)
    lastPenOutcome = raiseOutcome
    if case .ambiguous = raiseOutcome {
      return finishVisibilityTarget(.needsAttention(
        phase: .raisePen,
        scene: .inkPossible,
        failure: .pen(raiseOutcome)
      ))
    }
    return finishVisibilityTarget(.needsAttention(
      phase: phase,
      scene: .inkPossible,
      failure: failure
    ))
  }

  private func settleVisibilityTargetDisposition(
    _ intent: VisibilityTargetOperationIntent,
    requestID: UUID
  ) async -> VisibilityTargetOperationOutcome {
    let scene = activeVisibilityTarget?.scene ?? .pristine
    if scene == .inkPossible {
      setVisibilityTargetPhase(.raisePen, id: requestID)
      let snapshot = await machineController.snapshot()
      if snapshot.penState == .down {
        let raise = await machineController.requestPenActuation(.raise)
        lastPenOutcome = raise
        guard case .commandedAndSettled = raise else {
          return finishVisibilityTarget(.needsAttention(
            phase: .raisePen,
            scene: scene,
            failure: .pen(raise)
          ))
        }
      }
    }
    if let cancelTask = activeVisibilityTarget?.jogCancelTask {
      let outcome = await cancelTask.value
      if activeVisibilityTarget?.request.id == requestID {
        activeVisibilityTarget?.jogCancelOutcome = outcome
      }
    }
    return finishVisibilityTarget(dispositionOutcome(intent, scene: scene))
  }

  private func setVisibilityTargetPhase(_ phase: VisibilityTargetOperationPhase, id: UUID) {
    guard activeVisibilityTarget?.request.id == id else { return }
    activeVisibilityTarget?.phase = phase
  }

  private func latchedVisibilityTargetDisposition(
    id: UUID
  ) -> VisibilityTargetOperationIntent? {
    guard activeVisibilityTarget?.request.id == id else { return nil }
    return activeVisibilityTarget?.intent
  }

  private func dispositionOutcome(
    _ intent: VisibilityTargetOperationIntent,
    scene: VisibilityTargetSceneDisposition
  ) -> VisibilityTargetOperationOutcome {
    let cancel = activeVisibilityTarget?.jogCancelOutcome
    return switch intent {
    case .stop: .stopped(scene: scene, jogCancelOutcome: cancel)
    case .cancel: .cancelled(scene: scene, jogCancelOutcome: cancel)
    case .shutdown: .shutdown(scene: scene, jogCancelOutcome: cancel)
    }
  }

  private func finishVisibilityTarget(
    _ outcome: VisibilityTargetOperationOutcome
  ) -> VisibilityTargetOperationOutcome {
    lastVisibilityTargetOutcome = outcome
    return outcome
  }

  /// Priority subordinate request for the active `$J` operation. It deliberately
  /// does not replace `currentOperation`; the original jog remains the only
  /// owner of controller replies and final Idle completion.
  public func requestJogCancel(
    _ intent: JogCancelIntent = .operatorStop
  ) async -> JogCancelOutcome {
    if case .boundaryMotion(let request) = currentOperation,
      activeBoundaryMotion?.request.ownerID == request.ownerID
    {
      guard activeBoundaryMotion?.cancelIntent == nil else {
        return .refused(.alreadyRequested)
      }
      activeBoundaryMotion?.renewalOpen = false
      activeBoundaryMotion?.cancelIntent = intent
      let controller = machineController
      let task = Task { await controller.requestJogCancel() }
      activeBoundaryMotion?.cancelTask = task
      let outcome = await task.value
      if activeBoundaryMotion?.request.ownerID == request.ownerID {
        activeBoundaryMotion?.cancelOutcome = outcome
      }
      lastJogCancelOutcome = outcome
      return outcome
    }

    guard !jogCancelRequestInFlight else {
      return .refused(.alreadyRequested)
    }
    switch currentOperation {
    case .relativeJog, .drawingStroke:
      break
    case .boundaryMotion, .visibilityTarget:
      return .refused(.noActiveJog)
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
    if let boundary = activeBoundaryMotion {
      if let cancelTask = boundary.cancelTask {
        _ = await cancelTask.value
      } else {
        _ = await requestJogCancel(.shutdown)
      }
      await waitForBoundaryCompletion(ownerID: boundary.request.ownerID)
    }
    if let target = activeVisibilityTarget {
      _ = await requestVisibilityTargetIntent(.shutdown, operationID: target.request.id)
      await waitForVisibilityTargetCompletion(operationID: target.request.id)
    }
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

  private func finishBoundarySettlement(
    request: BoundaryMotionRequest,
    segmentOutcome: MotionOutcome?
  ) async -> BoundaryMotionOutcome {
    guard let boundary = activeBoundaryMotion,
      boundary.request.ownerID == request.ownerID,
      let intent = boundary.cancelIntent
    else {
      return finishBoundaryNeedsAttention(
        request: request,
        terminal: .fault(.transport("boundary owner lost its typed disposition"))
      )
    }
    let cancelOutcome: JogCancelOutcome
    if let task = boundary.cancelTask {
      cancelOutcome = await task.value
    } else {
      cancelOutcome = boundary.cancelOutcome ?? .refused(.noActiveJog)
    }
    activeBoundaryMotion?.cancelOutcome = cancelOutcome

    let finalPosition: MachinePosition?
    switch segmentOutcome {
    case .acceptedThenCompleted(let position), .cancelled(let position):
      finalPosition = position
    case .none, .refused, .ambiguous:
      if case .completed(let position) = cancelOutcome {
        finalPosition = position
      } else {
        finalPosition = nil
      }
    }
    let settledPosition = finalPosition ?? boundary.lastSettledPosition
    if let settledPosition,
      cancelOutcome == .completed(finalPosition: settledPosition)
        || cancelOutcome == .refused(.noActiveJog)
    {
      let outcome = BoundaryMotionOutcome.settled(
        BoundaryMotionSettlement(
          ownerID: request.ownerID,
          intent: intent,
          completedSegmentCount: boundary.completedSegmentCount,
          finalPosition: settledPosition,
          jogCancelOutcome: cancelOutcome
        )
      )
      lastBoundaryMotionOutcome = outcome
      return outcome
    }
    switch cancelOutcome {
    case .ambiguous(let ambiguity):
      return finishBoundaryNeedsAttention(
        request: request,
        terminal: Self.boundaryTerminal(for: ambiguity)
      )
    case .refused(.notConnected):
      return finishBoundaryNeedsAttention(request: request, terminal: .disconnected)
    case .refused(.stickyAmbiguity(let ambiguity)):
      return finishBoundaryNeedsAttention(
        request: request,
        terminal: Self.boundaryTerminal(for: ambiguity)
      )
    case .refused(let refusal):
      return finishBoundaryNeedsAttention(
        request: request,
        terminal: .fault(.transport("Jog Cancel refused: \(refusal.actionableDescription)"))
      )
    case .transmitted, .completed:
      return finishBoundaryNeedsAttention(
        request: request,
        terminal: .fault(.transport("boundary settlement omitted final MPos"))
      )
    }
  }

  private func waitForBoundaryCompletion(ownerID: BoundaryMotionOwnerID) async {
    guard activeBoundaryMotion?.request.ownerID == ownerID else { return }
    await withCheckedContinuation { continuation in
      activeBoundaryMotion?.completionWaiters.append(continuation)
    }
  }

  private func waitForVisibilityTargetCompletion(operationID: UUID) async {
    guard activeVisibilityTarget?.request.id == operationID else { return }
    await withCheckedContinuation { continuation in
      activeVisibilityTarget?.completionWaiters.append(continuation)
    }
  }

  private func finishBoundaryNeedsAttention(
    request: BoundaryMotionRequest,
    terminal: BoundaryMotionTerminal
  ) -> BoundaryMotionOutcome {
    activeBoundaryMotion?.renewalOpen = false
    let outcome = BoundaryMotionOutcome.needsAttention(
      ownerID: request.ownerID,
      terminal: terminal
    )
    lastBoundaryMotionOutcome = outcome
    return outcome
  }

  private static func boundaryTerminal(for refusal: MotionRefusal) -> BoundaryMotionTerminal {
    switch refusal {
    case .notConnected: .disconnected
    case .controllerAlarm(let detail): .alarm(detail)
    case .relevantLimitAsserted(let pins): .limitAsserted(pins: pins, finalPosition: nil)
    case .stickyAmbiguity(let ambiguity): boundaryTerminal(for: ambiguity)
    default: .refusal(refusal)
    }
  }

  private static func boundaryTerminal(
    for ambiguity: MotionAmbiguity
  ) -> BoundaryMotionTerminal {
    switch ambiguity {
    case .disconnected: .disconnected
    case .controllerAlarm(let detail): .alarm(detail)
    default: .fault(ambiguity)
    }
  }
}
