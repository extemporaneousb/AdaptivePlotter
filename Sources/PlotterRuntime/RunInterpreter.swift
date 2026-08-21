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

/// The handle is published only after the entire plan has one registered
/// interpreter owner. Awaiting it never transfers operation ownership to the
/// caller.
public struct DrawingPlanOperation: Sendable {
  public let id: DrawingPlanOperationID
  public let planRevisionID: ExecutionPlanRevisionID
  private let task: Task<DrawingPlanOutcome, Never>

  public init(
    id: DrawingPlanOperationID,
    planRevisionID: ExecutionPlanRevisionID,
    task: Task<DrawingPlanOutcome, Never>
  ) {
    self.id = id
    self.planRevisionID = planRevisionID
    self.task = task
  }

  public func outcome() async -> DrawingPlanOutcome {
    await task.value
  }
}

public enum DrawingPlanAdmission: Sendable {
  case admitted(DrawingPlanOperation)
  case rejected(DrawingPlanOutcome)
}

public enum RunOperation: Hashable, Sendable {
  case idle
  case passiveProbe
  case alarmClear
  case relativeJog(RelativeJogRequest)
  case boundaryMotion(BoundaryMotionRequest)
  case drawingStroke(DrawingStrokeRequest)
  case drawingPlan(DrawingPlanOperationID)
  case penActuation(PenCommand)
}

public struct RunInterpreterSnapshot: Hashable, Sendable {
  public let currentOperation: RunOperation
  public let machine: MachineSnapshot
  public let lastMotionOutcome: MotionOutcome?
  public let lastBoundaryMotionOutcome: BoundaryMotionOutcome?
  public let lastDrawingStrokeOutcome: DrawingStrokeOutcome?
  public let lastDrawingPlanOutcome: DrawingPlanOutcome?
  public let drawingPlanProgress: DrawingPlanProgressSnapshot?
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
    lastDrawingPlanOutcome: DrawingPlanOutcome? = nil,
    drawingPlanProgress: DrawingPlanProgressSnapshot? = nil,
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
    self.lastDrawingPlanOutcome = lastDrawingPlanOutcome
    self.drawingPlanProgress = drawingPlanProgress
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
  private struct ActiveDrawingPlan {
    let request: DrawingPlanRequest
    let plannedSegmentCount: Int
    var commandedStrokeCount = 0
    var controllerCompletedStrokeCount = 0
    var submittedSegmentCount = 0
    var controllerCompletedSegmentCount = 0
    var completedStrokeIDs: [StrokeID] = []
    var completedCheckpointIDs: [PlanCheckpointID] = []
    var activeStrokeID: StrokeID?
    var activeSegmentIndex: Int?
    var cancelIntent: JogCancelIntent?
    var cancelTask: Task<JogCancelOutcome, Never>?
    var cancelOutcome: JogCancelOutcome?
    var completionWaiters: [CheckedContinuation<Void, Never>] = []

    init(request: DrawingPlanRequest) {
      self.request = request
      plannedSegmentCount = request.plan.strokes.reduce(0) { count, stroke in
        count + zip(stroke.path.points, stroke.path.points.dropFirst()).filter { $0 != $1 }.count
      }
    }

    var snapshot: DrawingPlanProgressSnapshot {
      DrawingPlanProgressSnapshot(
        operationID: request.operationID,
        planRevisionID: request.plan.revisionID,
        plannedStrokeCount: request.plan.strokes.count,
        plannedSegmentCount: plannedSegmentCount,
        commandedStrokeCount: commandedStrokeCount,
        controllerCompletedStrokeCount: controllerCompletedStrokeCount,
        submittedSegmentCount: submittedSegmentCount,
        controllerCompletedSegmentCount: controllerCompletedSegmentCount,
        completedStrokeIDs: completedStrokeIDs,
        completedCheckpointIDs: completedCheckpointIDs,
        activeStrokeID: activeStrokeID,
        activeSegmentIndex: activeSegmentIndex
      )
    }
  }
  private let machineController: MachineController
  private var generation: UInt64 = 0
  private var activeTransition: InterpreterTransitionToken?
  private var currentOperation: RunOperation = .idle
  private var lastProbe: PassiveProbeResult?
  private var lastMotionOutcome: MotionOutcome?
  private var lastBoundaryMotionOutcome: BoundaryMotionOutcome?
  private var lastDrawingStrokeOutcome: DrawingStrokeOutcome?
  private var lastDrawingPlanOutcome: DrawingPlanOutcome?
  private var drawingPlanProgress: DrawingPlanProgressSnapshot?
  private var lastPenOutcome: PenOutcome?
  private var activeBoundaryMotion: ActiveBoundaryMotion?
  private var activeDrawingPlan: ActiveDrawingPlan?
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
      lastDrawingPlanOutcome: lastDrawingPlanOutcome,
      drawingPlanProgress: drawingPlanProgress,
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

  public func requestControllerAlarmClear() async -> ControllerAlarmClearOutcome {
    guard currentOperation == .idle, activeTransition == nil else {
      return .refused(.operationInFlight)
    }
    generation &+= 1
    currentOperation = .alarmClear
    let outcome = await machineController.requestControllerAlarmClear()
    if currentOperation == .alarmClear { currentOperation = .idle }
    return outcome
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

  public func requestDrawingPlan(
    _ request: DrawingPlanRequest
  ) async -> DrawingPlanOutcome {
    switch beginDrawingPlan(request) {
    case .admitted(let operation):
      return await operation.outcome()
    case .rejected(let outcome):
      return outcome
    }
  }

  /// Registers one owner for travel, pen actuation, every drawing segment, and
  /// every checkpoint before publishing the operation handle.
  public func beginDrawingPlan(
    _ request: DrawingPlanRequest
  ) -> DrawingPlanAdmission {
    guard currentOperation == .idle else {
      let progress = ActiveDrawingPlan(request: request).snapshot
      let outcome = DrawingPlanOutcome.refused(
        progress: progress,
        reason: .operationInFlight
      )
      lastDrawingPlanOutcome = outcome
      return .rejected(outcome)
    }
    generation &+= 1
    currentOperation = .drawingPlan(request.operationID)
    activeDrawingPlan = ActiveDrawingPlan(request: request)
    drawingPlanProgress = activeDrawingPlan?.snapshot
    let task = Task { await self.runAdmittedDrawingPlan(request) }
    return .admitted(DrawingPlanOperation(
      id: request.operationID,
      planRevisionID: request.plan.revisionID,
      task: task
    ))
  }

  private func runAdmittedDrawingPlan(
    _ request: DrawingPlanRequest
  ) async -> DrawingPlanOutcome {
    defer {
      if currentOperation == .drawingPlan(request.operationID) {
        currentOperation = .idle
      }
      if activeDrawingPlan?.request.operationID == request.operationID {
        let waiters = activeDrawingPlan?.completionWaiters ?? []
        activeDrawingPlan = nil
        for waiter in waiters { waiter.resume() }
      }
    }

    var lastKnownPosition = await machineController.snapshot().position
    if activeDrawingPlan?.cancelIntent != nil {
      return await finishDrawingPlanCancellation(
        request: request,
        finalPosition: lastKnownPosition,
        penRaiseOutcome: nil
      )
    }

    // Pen state is controller-command knowledge, not a prerequisite the
    // operator must re-verify. Always issue the idempotent Pen Up command before
    // plan travel, including when this process previously commanded Pen Up.
    let initialPenUp = await executePlanPen(.raise, request: request)
    switch initialPenUp {
    case .commandedAndSettled:
      break
    case .refused(let refusal):
      return finishDrawingPlan(.refused(
        progress: currentDrawingPlanProgress(request),
        reason: .initialPenRaise(refusal)
      ))
    case .ambiguous(let ambiguity):
      return finishDrawingPlan(.ambiguous(
        progress: currentDrawingPlanProgress(request),
        reason: .pen(command: .raise, reason: ambiguity)
      ))
    }
    lastKnownPosition = await machineController.snapshot().position
    if activeDrawingPlan?.cancelIntent != nil {
      return await finishDrawingPlanCancellation(
        request: request,
        finalPosition: lastKnownPosition,
        penRaiseOutcome: nil
      )
    }

    for stroke in request.plan.strokes {
      activeDrawingPlan?.activeStrokeID = stroke.logicalStrokeID
      activeDrawingPlan?.activeSegmentIndex = nil
      publishDrawingPlanProgress()

      var sampledPosition = lastKnownPosition
      if sampledPosition == nil {
        sampledPosition = await machineController.snapshot().position
      }
      guard var currentPosition = sampledPosition else {
        return finishDrawingPlan(.refused(
          progress: currentDrawingPlanProgress(request),
          reason: .machinePositionUnavailable
        ))
      }
      let strokeStart = MachinePosition(point: stroke.path.start)
      if !MachinePositionAcceptancePolicy.accepts(currentPosition, target: strokeStart) {
        let delta: Vector2<MachineSpace>
        do {
          delta = try currentPosition.point.vector(to: stroke.path.start)
        } catch {
          return finishDrawingPlan(.refused(
            progress: currentDrawingPlanProgress(request),
            reason: .machinePositionUnavailable
          ))
        }
        let travel = RelativeJogRequest(
          delta: delta,
          feedMMPerMinute: request.travelFeedMMPerMinute
        )
        let outcome = await machineController.requestRelativeJog(travel)
        lastMotionOutcome = outcome
        switch outcome {
        case .acceptedThenCompleted(let finalPosition):
          currentPosition = finalPosition
          lastKnownPosition = finalPosition
          guard MachinePositionAcceptancePolicy.accepts(finalPosition, target: strokeStart) else {
            return finishDrawingPlan(.ambiguous(
              progress: currentDrawingPlanProgress(request),
              reason: .travelSettledOutsidePlannedPoint(
                expected: stroke.path.start,
                actual: finalPosition
              )
            ))
          }
        case .cancelled(let finalPosition):
          lastKnownPosition = finalPosition
          return await finishDrawingPlanCancellation(
            request: request,
            finalPosition: finalPosition,
            penRaiseOutcome: nil
          )
        case .refused(let refusal):
          if activeDrawingPlan?.cancelIntent != nil {
            return await finishDrawingPlanCancellation(
              request: request,
              finalPosition: lastKnownPosition,
              penRaiseOutcome: nil
            )
          }
          return finishDrawingPlan(.refused(
            progress: currentDrawingPlanProgress(request),
            reason: .travel(refusal)
          ))
        case .ambiguous(let ambiguity):
          return finishDrawingPlan(.ambiguous(
            progress: currentDrawingPlanProgress(request),
            reason: .travel(ambiguity)
          ))
        }
      }
      if activeDrawingPlan?.cancelIntent != nil {
        return await finishDrawingPlanCancellation(
          request: request,
          finalPosition: lastKnownPosition,
          penRaiseOutcome: nil
        )
      }

      let lowerOutcome = await executePlanPen(.lower, request: request)
      switch lowerOutcome {
      case .commandedAndSettled:
        break
      case .refused(let refusal):
        if activeDrawingPlan?.cancelIntent != nil {
          return await finishDrawingPlanCancellation(
            request: request,
            finalPosition: lastKnownPosition,
            penRaiseOutcome: nil
          )
        }
        return finishDrawingPlan(.refused(
          progress: currentDrawingPlanProgress(request),
          reason: .penLower(refusal)
        ))
      case .ambiguous(let ambiguity):
        return finishDrawingPlan(.ambiguous(
          progress: currentDrawingPlanProgress(request),
          reason: .pen(command: .lower, reason: ambiguity)
        ))
      }
      if activeDrawingPlan?.cancelIntent != nil {
        let raise = await executePlanPen(.raise, request: request)
        if case .ambiguous(let ambiguity) = raise {
          return finishDrawingPlan(.ambiguous(
            progress: currentDrawingPlanProgress(request),
            reason: .pen(command: .raise, reason: ambiguity)
          ))
        }
        return await finishDrawingPlanCancellation(
          request: request,
          finalPosition: lastKnownPosition,
          penRaiseOutcome: raise
        )
      }

      let segments = Array(zip(
        stroke.path.points,
        stroke.path.points.dropFirst()
      ).enumerated()).filter { $0.element.0 != $0.element.1 }
      for (strokeSegmentOrdinal, indexedPair) in segments.enumerated() {
        let segmentIndex = indexedPair.offset
        let pair = indexedPair.element
        if activeDrawingPlan?.cancelIntent != nil {
          let raise = await executePlanPen(.raise, request: request)
          if case .ambiguous(let ambiguity) = raise {
            return finishDrawingPlan(.ambiguous(
              progress: currentDrawingPlanProgress(request),
              reason: .pen(command: .raise, reason: ambiguity)
            ))
          }
          return await finishDrawingPlanCancellation(
            request: request,
            finalPosition: lastKnownPosition,
            penRaiseOutcome: raise
          )
        }
        if strokeSegmentOrdinal == 0 {
          activeDrawingPlan?.commandedStrokeCount += 1
        }
        activeDrawingPlan?.activeSegmentIndex = segmentIndex
        activeDrawingPlan?.submittedSegmentCount += 1
        publishDrawingPlanProgress()
        let segment = DrawingStrokeRequest(
          delta: try! pair.0.vector(to: pair.1),
          feedMMPerMinute: request.drawingFeedMMPerMinute
        )
        let outcome = await machineController.requestDrawingStroke(segment)
        lastDrawingStrokeOutcome = outcome
        switch outcome {
        case .completed(let evidence):
          activeDrawingPlan?.controllerCompletedSegmentCount += 1
          if strokeSegmentOrdinal == segments.count - 1 {
            activeDrawingPlan?.controllerCompletedStrokeCount += 1
          }
          publishDrawingPlanProgress()
          lastKnownPosition = evidence.finalPosition
          let target = MachinePosition(point: pair.1)
          guard MachinePositionAcceptancePolicy.accepts(evidence.finalPosition, target: target)
          else {
            let raise = await executePlanPen(.raise, request: request)
            if case .ambiguous(let ambiguity) = raise {
              return finishDrawingPlan(.ambiguous(
                progress: currentDrawingPlanProgress(request),
                reason: .pen(command: .raise, reason: ambiguity)
              ))
            }
            return finishDrawingPlan(.possibleInk(
              progress: currentDrawingPlanProgress(request),
              reason: .controllerCompletedOutsidePlannedPoint(
                expected: pair.1,
                actual: evidence.finalPosition
              ),
              penRaiseOutcome: raise
            ))
          }
        case .cancelled(let evidence, let penRaiseOutcome):
          lastKnownPosition = evidence.finalPosition
          lastPenOutcome = penRaiseOutcome
          return await finishDrawingPlanCancellation(
            request: request,
            finalPosition: evidence.finalPosition,
            penRaiseOutcome: penRaiseOutcome
          )
        case .refused(let refusal):
          let raise = await executePlanPen(.raise, request: request)
          if case .ambiguous(let ambiguity) = raise {
            return finishDrawingPlan(.ambiguous(
              progress: currentDrawingPlanProgress(request),
              reason: .pen(command: .raise, reason: ambiguity)
            ))
          }
          if activeDrawingPlan?.cancelIntent != nil {
            return await finishDrawingPlanCancellation(
              request: request,
              finalPosition: lastKnownPosition,
              penRaiseOutcome: raise
            )
          }
          return finishDrawingPlan(.possibleInk(
            progress: currentDrawingPlanProgress(request),
            reason: .strokeRefused(refusal),
            penRaiseOutcome: raise
          ))
        case .ambiguous(let ambiguity):
          return finishDrawingPlan(.ambiguous(
            progress: currentDrawingPlanProgress(request),
            reason: .stroke(ambiguity)
          ))
        }
        if activeDrawingPlan?.cancelIntent != nil {
          let raise = await executePlanPen(.raise, request: request)
          if case .ambiguous(let ambiguity) = raise {
            return finishDrawingPlan(.ambiguous(
              progress: currentDrawingPlanProgress(request),
              reason: .pen(command: .raise, reason: ambiguity)
            ))
          }
          return await finishDrawingPlanCancellation(
            request: request,
            finalPosition: lastKnownPosition,
            penRaiseOutcome: raise
          )
        }
      }

      let raiseOutcome = await executePlanPen(.raise, request: request)
      switch raiseOutcome {
      case .commandedAndSettled:
        break
      case .refused(let refusal):
        return finishDrawingPlan(.possibleInk(
          progress: currentDrawingPlanProgress(request),
          reason: .penRaiseRefused(refusal),
          penRaiseOutcome: raiseOutcome
        ))
      case .ambiguous(let ambiguity):
        return finishDrawingPlan(.ambiguous(
          progress: currentDrawingPlanProgress(request),
          reason: .pen(command: .raise, reason: ambiguity)
        ))
      }
      if activeDrawingPlan?.cancelIntent != nil {
        return await finishDrawingPlanCancellation(
          request: request,
          finalPosition: lastKnownPosition,
          penRaiseOutcome: raiseOutcome
        )
      }
      activeDrawingPlan?.completedStrokeIDs.append(stroke.logicalStrokeID)
      activeDrawingPlan?.completedCheckpointIDs.append(stroke.endingCheckpointID)
      activeDrawingPlan?.activeStrokeID = nil
      activeDrawingPlan?.activeSegmentIndex = nil
      publishDrawingPlanProgress()
    }

    var sampledFinalPosition = lastKnownPosition
    if sampledFinalPosition == nil {
      sampledFinalPosition = await machineController.snapshot().position
    }
    guard let finalPosition = sampledFinalPosition else {
      return finishDrawingPlan(.refused(
        progress: currentDrawingPlanProgress(request),
        reason: .machinePositionUnavailable
      ))
    }
    return finishDrawingPlan(.completed(
      progress: currentDrawingPlanProgress(request),
      finalPosition: finalPosition
    ))
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

    if case .drawingPlan(let operationID) = currentOperation,
      activeDrawingPlan?.request.operationID == operationID
    {
      guard activeDrawingPlan?.cancelIntent == nil else {
        return .refused(.alreadyRequested)
      }
      activeDrawingPlan?.cancelIntent = intent
      let controller = machineController
      let task = Task { await controller.requestJogCancel() }
      activeDrawingPlan?.cancelTask = task
      let outcome = await task.value
      if activeDrawingPlan?.request.operationID == operationID {
        activeDrawingPlan?.cancelOutcome = outcome
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
    case .boundaryMotion, .drawingPlan:
      return .refused(.noActiveJog)
    case .idle, .passiveProbe, .alarmClear, .penActuation:
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

  public func requestPenActuation(
    _ command: PenCommand,
    profile: PenActuationProfile
  ) async -> PenOutcome {
    guard currentOperation == .idle else {
      let outcome = PenOutcome.refused(.operationInFlight)
      lastPenOutcome = outcome
      return outcome
    }
    generation &+= 1
    currentOperation = .penActuation(command)
    let outcome = await machineController.requestPenActuation(command, profile: profile)
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
    if let drawingPlan = activeDrawingPlan {
      if let cancelTask = drawingPlan.cancelTask {
        _ = await cancelTask.value
      } else {
        _ = await requestJogCancel(.shutdown)
      }
      await waitForDrawingPlanCompletion(operationID: drawingPlan.request.operationID)
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
    guard activeTransition != nil else { return }
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

  private func waitForDrawingPlanCompletion(operationID: DrawingPlanOperationID) async {
    guard activeDrawingPlan?.request.operationID == operationID else { return }
    await withCheckedContinuation { continuation in
      activeDrawingPlan?.completionWaiters.append(continuation)
    }
  }

  private func executePlanPen(
    _ command: PenCommand,
    request: DrawingPlanRequest
  ) async -> PenOutcome {
    let outcome = await machineController.requestPenActuation(
      command,
      profile: request.penActuationProfile
    )
    lastPenOutcome = outcome
    return outcome
  }

  private func currentDrawingPlanProgress(
    _ request: DrawingPlanRequest
  ) -> DrawingPlanProgressSnapshot {
    if let activeDrawingPlan,
      activeDrawingPlan.request.operationID == request.operationID
    {
      return activeDrawingPlan.snapshot
    }
    return ActiveDrawingPlan(request: request).snapshot
  }

  private func publishDrawingPlanProgress() {
    if let activeDrawingPlan {
      drawingPlanProgress = activeDrawingPlan.snapshot
    }
  }

  private func finishDrawingPlan(_ outcome: DrawingPlanOutcome) -> DrawingPlanOutcome {
    lastDrawingPlanOutcome = outcome
    drawingPlanProgress = outcome.progress
    return outcome
  }

  private func finishDrawingPlanCancellation(
    request: DrawingPlanRequest,
    finalPosition: MachinePosition?,
    penRaiseOutcome: PenOutcome?
  ) async -> DrawingPlanOutcome {
    guard let active = activeDrawingPlan,
      active.request.operationID == request.operationID,
      let intent = active.cancelIntent
    else {
      return finishDrawingPlan(.ambiguous(
        progress: currentDrawingPlanProgress(request),
        reason: .travel(.transport("drawing plan lost its cancellation owner"))
      ))
    }
    let cancelOutcome: JogCancelOutcome
    if let task = active.cancelTask {
      cancelOutcome = await task.value
    } else {
      cancelOutcome = active.cancelOutcome ?? .refused(.noActiveJog)
    }
    activeDrawingPlan?.cancelOutcome = cancelOutcome
    return finishDrawingPlan(.cancelled(
      progress: currentDrawingPlanProgress(request),
      intent: intent,
      jogCancelOutcome: cancelOutcome,
      finalPosition: finalPosition,
      penRaiseOutcome: penRaiseOutcome
    ))
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
