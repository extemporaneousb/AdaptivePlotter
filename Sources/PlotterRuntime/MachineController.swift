import Foundation
import PlotterModel

public enum MachineConnectionState: String, Codable, Hashable, Sendable {
  case disconnected
  case connecting
  case connected
  case probing
  case moving
  case actuatingPen
  case blocked
}

public struct MachineSnapshot: Codable, Hashable, Sendable {
  public let connection: MachineConnectionState
  public let link: MachineLinkDescriptor
  public let lastProbe: PassiveProbeResult?
  public let blockers: [MachineBlocker]
  public let controllerState: ControllerState?
  public let position: MachinePosition?
  public let pins: ControllerPins
  /// Last controller-commanded pen state. This is not visual proof of the physical pen pose.
  public let penState: PenState
  public let motionGuardState: MotionGuardState
  public let stickyAmbiguity: MotionAmbiguity?
  public let operationInFlight: Bool
  public let lastMotionOutcome: MotionOutcome?
  public let lastDrawingStrokeOutcome: DrawingStrokeOutcome?
  public let lastPenOutcome: PenOutcome?
  public let jogCancellationInFlight: Bool
  public let lastJogCancelOutcome: JogCancelOutcome?
  public let controllerAxisFeedLimits: ControllerAxisFeedLimits?

  public init(
    connection: MachineConnectionState,
    link: MachineLinkDescriptor,
    lastProbe: PassiveProbeResult?,
    blockers: [MachineBlocker],
    controllerState: ControllerState? = nil,
    position: MachinePosition? = nil,
    pins: ControllerPins = ControllerPins(rawValue: ""),
    penState: PenState = .unknown,
    motionGuardState: MotionGuardState = .inactive,
    stickyAmbiguity: MotionAmbiguity? = nil,
    operationInFlight: Bool = false,
    lastMotionOutcome: MotionOutcome? = nil,
    lastDrawingStrokeOutcome: DrawingStrokeOutcome? = nil,
    lastPenOutcome: PenOutcome? = nil,
    jogCancellationInFlight: Bool = false,
    lastJogCancelOutcome: JogCancelOutcome? = nil,
    controllerAxisFeedLimits: ControllerAxisFeedLimits? = nil
  ) {
    self.connection = connection
    self.link = link
    self.lastProbe = lastProbe
    self.blockers = blockers
    self.controllerState = controllerState
    self.position = position
    self.pins = pins
    self.penState = penState
    self.motionGuardState = motionGuardState
    self.stickyAmbiguity = stickyAmbiguity
    self.operationInFlight = operationInFlight
    self.lastMotionOutcome = lastMotionOutcome
    self.lastDrawingStrokeOutcome = lastDrawingStrokeOutcome
    self.lastPenOutcome = lastPenOutcome
    self.jogCancellationInFlight = jogCancellationInFlight
    self.lastJogCancelOutcome = lastJogCancelOutcome
    self.controllerAxisFeedLimits = controllerAxisFeedLimits
  }
}

public enum SerialSelectionResult: Sendable, Equatable {
  case selected(MachineLinkDescriptor)
  case blocked(MachineBlocker)

  public static func resolve(
    _ descriptors: [MachineLinkDescriptor],
    selectedIdentifier: String? = nil
  ) -> SerialSelectionResult {
    if let selectedIdentifier,
      let selected = descriptors.first(where: { $0.identifier == selectedIdentifier })
    {
      return .selected(selected)
    }
    if descriptors.isEmpty { return .blocked(.noSerialDevice) }
    if descriptors.count == 1, let only = descriptors.first { return .selected(only) }
    return .blocked(.multipleSerialDevices(descriptors))
  }
}

public actor MachineController {
  public static let maximumCompletionTimeoutNanoseconds: UInt64 = 120_000_000_000

  private enum ActiveOperation {
    case passiveProbe
    case relativeJog
    case drawingStroke
    case penActuation
  }

  private enum JogCancellationProgress {
    case transmitting
    case transmitted
  }

  private struct WireRelativeJog {
    let delta: Vector2<MachineSpace>
    let feedMMPerMinute: Double
    let xText: String
    let yText: String
    let feedText: String

    var bytes: Data {
      var components = ["$J=G91", "G21"]
      if delta.dx != 0 { components.append("X\(xText)") }
      if delta.dy != 0 { components.append("Y\(yText)") }
      components.append("F\(feedText)")
      return Data((components.joined(separator: " ") + "\n").utf8)
    }

    var request: RelativeJogRequest {
      RelativeJogRequest(delta: delta, feedMMPerMinute: feedMMPerMinute)
    }
  }

  struct ControllerMotionTiming: Equatable, Sendable {
    let maximumXFeedMMPerMinute: Double
    let maximumYFeedMMPerMinute: Double
    let xAccelerationMMPerSecondSquared: Double
    let yAccelerationMMPerSecondSquared: Double
  }

  private let link: any MachineLink
  private let selectionIsExplicit: Bool
  private let ledger: RunLedger?
  private let runID: LedgerRunID?
  private let clock: any RuntimeClock
  private let queryTimeoutNanoseconds: UInt64
  private let maximumRawReceiveBytesPerQuery: Int
  private let maximumRawReceiveChunksPerQuery: Int
  private let statusPollIntervalNanoseconds: UInt64
  private let completionGraceNanoseconds: UInt64

  private var connection: MachineConnectionState = .disconnected
  private var lastProbe: PassiveProbeResult?
  private var blockers: [MachineBlocker] = []
  private var controllerState: ControllerState?
  private var position: MachinePosition?
  private var pins = ControllerPins(rawValue: "")
  private var penState: PenState = .unknown
  private var motionGuardState: MotionGuardState = .inactive
  private var stickyAmbiguity: MotionAmbiguity?
  private var controllerAxisFeedLimits: ControllerAxisFeedLimits?
  private var controllerMotionTiming: ControllerMotionTiming?
  private var activeOperation: ActiveOperation?
  private var lastMotionOutcome: MotionOutcome?
  private var lastDrawingStrokeOutcome: DrawingStrokeOutcome?
  private var lastPenOutcome: PenOutcome?
  private var activeJogCommandTransmitted = false
  private var preTransmissionJogCancellationRequested = false
  private var jogCancellationProgress: JogCancellationProgress?
  private var jogCancellationContinuation: CheckedContinuation<JogCancelOutcome, Never>?
  private var cancelWriteResolutionWaiters: [CheckedContinuation<Void, Never>] = []
  private var lastJogCancelOutcome: JogCancelOutcome?
  private var wireWriteInProgress = false
  private var priorityWireWriteWaiters: [CheckedContinuation<Void, Never>] = []
  private var regularWireWriteWaiters: [CheckedContinuation<Void, Never>] = []

  public init(
    link: any MachineLink,
    selectionIsExplicit: Bool = true,
    ledger: RunLedger? = nil,
    runID: LedgerRunID? = nil,
    clock: any RuntimeClock = SystemRuntimeClock(),
    queryTimeoutNanoseconds: UInt64 = 2_000_000_000,
    maximumRawReceiveBytesPerQuery: Int = 64 * 1_024,
    maximumRawReceiveChunksPerQuery: Int = 256,
    statusPollIntervalNanoseconds: UInt64 = 50_000_000,
    completionGraceNanoseconds: UInt64 = 1_000_000_000
  ) {
    self.link = link
    self.selectionIsExplicit = selectionIsExplicit
    self.ledger = ledger
    self.runID = runID
    self.clock = clock
    self.queryTimeoutNanoseconds = max(1, queryTimeoutNanoseconds)
    self.maximumRawReceiveBytesPerQuery = max(1, maximumRawReceiveBytesPerQuery)
    self.maximumRawReceiveChunksPerQuery = max(1, maximumRawReceiveChunksPerQuery)
    self.statusPollIntervalNanoseconds = statusPollIntervalNanoseconds
    self.completionGraceNanoseconds = completionGraceNanoseconds
  }

  public static func bsdSerial(
    descriptor: MachineLinkDescriptor,
    ledger: RunLedger? = nil,
    runID: LedgerRunID? = nil,
    clock: any RuntimeClock = SystemRuntimeClock(),
    queryTimeoutNanoseconds: UInt64 = 2_000_000_000,
    maximumRawReceiveBytesPerQuery: Int = 64 * 1_024,
    maximumRawReceiveChunksPerQuery: Int = 256,
    statusPollIntervalNanoseconds: UInt64 = 50_000_000,
    completionGraceNanoseconds: UInt64 = 1_000_000_000,
    writeTimeoutNanoseconds: UInt64 = 500_000_000
  ) throws -> MachineController {
    MachineController(
      link: try BSDSerialLink(
        descriptor: descriptor,
        writeTimeoutNanoseconds: writeTimeoutNanoseconds
      ),
      selectionIsExplicit: true,
      ledger: ledger,
      runID: runID,
      clock: clock,
      queryTimeoutNanoseconds: queryTimeoutNanoseconds,
      maximumRawReceiveBytesPerQuery: maximumRawReceiveBytesPerQuery,
      maximumRawReceiveChunksPerQuery: maximumRawReceiveChunksPerQuery,
      statusPollIntervalNanoseconds: statusPollIntervalNanoseconds,
      completionGraceNanoseconds: completionGraceNanoseconds
    )
  }

  public func snapshot() -> MachineSnapshot {
    MachineSnapshot(
      connection: connection,
      link: link.descriptor,
      lastProbe: lastProbe,
      blockers: blockers,
      controllerState: controllerState,
      position: position,
      pins: pins,
      penState: penState,
      motionGuardState: motionGuardState,
      stickyAmbiguity: stickyAmbiguity,
      operationInFlight: activeOperation != nil,
      lastMotionOutcome: lastMotionOutcome,
      lastDrawingStrokeOutcome: lastDrawingStrokeOutcome,
      lastPenOutcome: lastPenOutcome,
      jogCancellationInFlight: jogCancellationProgress != nil,
      lastJogCancelOutcome: lastJogCancelOutcome,
      controllerAxisFeedLimits: controllerAxisFeedLimits
    )
  }

  /// Activates operator authorization for machine-affecting commands in this
  /// connected session. Every command still refreshes controller status before
  /// transmitting; activation is consent, not cached proof that motion is safe.
  public func activateMotionGuard() -> MotionGuardActivationOutcome {
    if let refusal = validateMotionGuardActivation() {
      motionGuardState = .inactive
      return .refused(refusal)
    }
    motionGuardState = .active
    return .activated
  }

  public func deactivateMotionGuard() {
    motionGuardState = .inactive
  }

  public func disconnect() async {
    if activeOperation == .relativeJog || activeOperation == .drawingStroke
      || activeOperation == .penActuation
    {
      setAmbiguous(.disconnected)
    }
    await link.close()
    connection = .disconnected
    controllerState = nil
    position = nil
    pins = ControllerPins(rawValue: "")
    penState = .unknown
    motionGuardState = .inactive
    controllerAxisFeedLimits = nil
    controllerMotionTiming = nil
  }

  public func runPassiveProbe() async -> PassiveProbeResult {
    let started = timestamp()
    guard activeOperation == nil else {
      return PassiveProbeResult(
        link: link.descriptor,
        startedAt: started,
        completedAt: timestamp(),
        exchanges: [],
        blockers: [.transport("another controller operation is already in flight")]
      )
    }
    activeOperation = .passiveProbe
    defer { activeOperation = nil }
    blockers = []
    var exchanges: [PassiveProbeExchange] = []
    let probeID = UUID()
    recordProbeStartedBestEffort(probeID: probeID, started: started)

    do {
      try await ensureConnected()
      connection = .probing
    } catch {
      blockers = [.transport(String(describing: error))]
      invalidateConnectionKnowledge()
      return finishProbe(probeID: probeID, started: started, exchanges: exchanges)
    }

    for query in PassiveQuery.allCases {
      let exchange = await executePassive(query)
      exchanges.append(exchange)
      if let blocker = exchange.blocker {
        blockers.append(blocker)
        break
      }
    }
    if blockers.isEmpty {
      connection = .connected
    } else {
      await closeAndInvalidateKnowledge()
    }
    return finishProbe(probeID: probeID, started: started, exchanges: exchanges)
  }

  public func requestRelativeJog(_ request: RelativeJogRequest) async -> MotionOutcome {
    await executeRelativeJog(request)
  }

  /// Executes exactly one closed pen-down XY stroke. This operation deliberately
  /// does not reuse the ordinary Pen Up admission rule of `RelativeJogRequest`.
  /// It retains controller ownership until a final Idle status supplies MPos.
  public func requestDrawingStroke(
    _ request: DrawingStrokeRequest
  ) async -> DrawingStrokeOutcome {
    await executeDrawingStroke(request)
  }

  /// Requests GRBL's realtime Jog Cancel for the one currently transmitted
  /// `$J` jog or drawing stroke. This is not feed hold and it is not an
  /// emergency stop.
  /// The byte has no ordinary acknowledgement, so the original jog poll remains
  /// the sole reader and resolves this request only after observing Idle.
  public func requestJogCancel() async -> JogCancelOutcome {
    guard selectionIsExplicit else {
      return finishJogCancel(.refused(.noSerialDeviceSelected))
    }
    if let stickyAmbiguity {
      return finishJogCancel(.refused(.stickyAmbiguity(stickyAmbiguity)))
    }
    guard activeOperation == .relativeJog || activeOperation == .drawingStroke else {
      return finishJogCancel(
        .refused(connection == .disconnected ? .notConnected : .noActiveJog)
      )
    }
    guard jogCancellationProgress == nil else {
      return finishJogCancel(.refused(.alreadyRequested), replaceLastOutcome: false)
    }

    jogCancellationProgress = .transmitting
    await acquireWireWrite(priority: true)
    if let stickyAmbiguity {
      releaseWireWrite()
      resolveCancelWriteWaiters()
      return finishJogCancel(.ambiguous(stickyAmbiguity))
    }
    guard activeOperation == .relativeJog || activeOperation == .drawingStroke,
      jogCancellationProgress == .transmitting
    else {
      releaseWireWrite()
      jogCancellationProgress = nil
      resolveCancelWriteWaiters()
      return finishJogCancel(.refused(.noActiveJog))
    }
    guard activeJogCommandTransmitted else {
      preTransmissionJogCancellationRequested = true
      releaseWireWrite()
      jogCancellationProgress = nil
      resolveCancelWriteWaiters()
      return finishJogCancel(.refused(.noActiveJog))
    }
    do {
      try await link.write(Self.encodeJogCancel)
      let outcomeAfterWrite: JogCancelOutcome?
      if let stickyAmbiguity {
        outcomeAfterWrite = .ambiguous(stickyAmbiguity)
      } else if activeOperation != .relativeJog && activeOperation != .drawingStroke
        || !activeJogCommandTransmitted
        || jogCancellationProgress != .transmitting
      {
        outcomeAfterWrite = .refused(.noActiveJog)
      } else {
        jogCancellationProgress = .transmitted
        lastJogCancelOutcome = .transmitted
        outcomeAfterWrite = nil
      }
      releaseWireWrite()
      recordRawIOBestEffort(
        RawMachineIO(
          direction: .transmit,
          bytes: Self.encodeJogCancel,
          timestamp: timestamp()
        )
      )
      if let outcomeAfterWrite {
        resolveCancelWriteWaiters()
        return finishJogCancel(outcomeAfterWrite)
      }
    } catch let error as MachineLinkError {
      releaseWireWrite()
      let reason = ambiguityForCancelWriteError(error)
      setAmbiguous(reason)
      resolveCancelWriteWaiters()
      return finishJogCancel(.ambiguous(reason))
    } catch {
      releaseWireWrite()
      let reason = MotionAmbiguity.transport(String(describing: error))
      setAmbiguous(reason)
      resolveCancelWriteWaiters()
      return finishJogCancel(.ambiguous(reason))
    }

    resolveCancelWriteWaiters()
    return await withCheckedContinuation { continuation in
      jogCancellationContinuation = continuation
    }
  }

  private func executeRelativeJog(
    _ request: RelativeJogRequest
  ) async -> MotionOutcome {
    guard activeOperation == nil else {
      return finishMotion(request: request, outcome: .refused(.operationInFlight))
    }
    let wireResult = Self.makeWireRelativeJog(request)
    guard let wire = wireResult.wire else {
      return finishMotion(
        request: request,
        outcome: .refused(wireResult.refusal ?? .nonFiniteDelta)
      )
    }
    if let refusal = validateSessionAndRequest(wire) {
      let outcome = MotionOutcome.refused(refusal)
      lastMotionOutcome = outcome
      recordMotionBestEffort(request: request, outcome: outcome)
      return outcome
    }

    activeOperation = .relativeJog
    defer {
      activeJogCommandTransmitted = false
      preTransmissionJogCancellationRequested = false
      if jogCancellationProgress != nil {
        let reason = stickyAmbiguity
          ?? .transport("jog ended without a final Jog Cancel outcome")
        completeActiveJogCancellation(.ambiguous(reason))
      }
      jogCancellationProgress = nil
      activeOperation = nil
      if connection == .moving { connection = .connected }
    }

    do {
      try await link.discardPendingInput()
    } catch {
      await closeAndInvalidateKnowledge()
      return finishMotion(
        request: request,
        outcome: .refused(
          .freshStatusUnavailable(
            "could not discard pending controller input: \(String(describing: error))"
          )
        )
      )
    }
    if preTransmissionJogCancellationRequested {
      return finishMotion(request: request, outcome: .refused(.operationInFlight))
    }

    let admissionDeadline = addingClamped(clock.nowNanoseconds(), queryTimeoutNanoseconds)
    switch await requestMotionStatus(deadline: admissionDeadline) {
    case .status(let report):
      apply(report)
      if let refusal = validateFreshControllerStatus() {
        await closeAndInvalidateKnowledge()
        return finishMotion(request: request, outcome: .refused(refusal))
      }
    case .ambiguous(let reason):
      await closeAndInvalidateKnowledge()
      return finishMotion(
        request: request,
        outcome: .refused(.freshStatusUnavailable(Self.admissionFailureDescription(reason)))
      )
    }

    guard position != nil else {
      await closeAndInvalidateKnowledge()
      return finishMotion(
        request: request,
        outcome: .refused(.freshStatusUnavailable("fresh status omitted a valid MPos"))
      )
    }
    if preTransmissionJogCancellationRequested {
      connection = .connected
      return finishMotion(request: request, outcome: .refused(.operationInFlight))
    }

    connection = .moving
    let command = wire.bytes
    do {
      try await serializedWrite(command)
      activeJogCommandTransmitted = true
      recordRawIOBestEffort(
        RawMachineIO(direction: .transmit, bytes: command, timestamp: timestamp())
      )
    } catch let error as MachineLinkError {
      return finishMotion(request: request, outcome: outcomeForWriteError(error))
    } catch {
      return finishMotion(
        request: request,
        outcome: ambiguous(.transport(String(describing: error)))
      )
    }

    switch await awaitCommandAcknowledgement(context: "jog") {
    case .accepted:
      break
    case .rejected(let reason):
      connection = .connected
      if jogCancellationProgress != nil {
        completeActiveJogCancellation(.refused(.noActiveJog))
      }
      let outcome = MotionOutcome.refused(.controllerRejected(reason))
      return finishMotion(request: request, outcome: outcome)
    case .ambiguous(let reason):
      return finishMotion(request: request, outcome: ambiguous(reason))
    }

    let timeout = Self.completionTimeoutNanoseconds(
      for: wire.request,
      controllerMotionTiming: controllerMotionTiming,
      graceNanoseconds: completionGraceNanoseconds
    )
    let deadline = addingClamped(clock.nowNanoseconds(), timeout)
    while clock.nowNanoseconds() < deadline {
      let statusResult = await requestMotionStatus(deadline: deadline)
      switch statusResult {
      case .status(let report):
        apply(report)
        switch report.controllerState {
        case .idle:
          if jogCancellationProgress == .transmitting {
            await waitForCancelWriteResolution()
          }
          guard let finalPosition = report.machinePosition else {
            return finishMotion(
              request: request,
              outcome: ambiguous(.malformedReply("Idle status omitted a valid MPos"))
            )
          }
          connection = .connected
          if jogCancellationProgress == .transmitted {
            completeActiveJogCancellation(.completed(finalPosition: finalPosition))
            return finishMotion(
              request: request,
              outcome: .cancelled(finalPosition: finalPosition)
            )
          }
          if let stickyAmbiguity {
            return finishMotion(
              request: request,
              outcome: .ambiguous(stickyAmbiguity)
            )
          }
          return finishMotion(
            request: request,
            outcome: .acceptedThenCompleted(finalPosition: finalPosition)
          )
        case .run, .jog:
          do {
            try await sleepBeforeNextPoll(deadline: deadline)
          } catch {
            return finishMotion(
              request: request,
              outcome: ambiguous(.completionTimedOut(deadlineNanoseconds: deadline))
            )
          }
        case .alarm:
          return finishMotion(
            request: request,
            outcome: ambiguous(.controllerAlarm(report.state))
          )
        case .hold:
          return finishMotion(request: request, outcome: ambiguous(.controllerHold))
        case .door, .check, .home, .sleep, .tool, .unknown:
          return finishMotion(
            request: request,
            outcome: ambiguous(.unexpectedControllerState(report.controllerState))
          )
        }
      case .ambiguous(let reason):
        return finishMotion(request: request, outcome: ambiguous(reason))
      }
    }
    return finishMotion(
      request: request,
      outcome: ambiguous(.completionTimedOut(deadlineNanoseconds: deadline))
    )
  }

  private func executeDrawingStroke(
    _ request: DrawingStrokeRequest
  ) async -> DrawingStrokeOutcome {
    guard activeOperation == nil else {
      return finishDrawingStroke(request: request, outcome: .refused(.operationInFlight))
    }
    let motionRequest = RelativeJogRequest(
      delta: request.delta,
      feedMMPerMinute: request.feedMMPerMinute
    )
    let wireResult = Self.makeWireRelativeJog(motionRequest)
    guard let wire = wireResult.wire else {
      let refusal = Self.drawingStrokeRefusal(
        from: wireResult.refusal ?? .nonFiniteDelta
      )
      return finishDrawingStroke(request: request, outcome: .refused(refusal))
    }
    if let refusal = validateDrawingStrokeSessionAndRequest(wire) {
      return finishDrawingStroke(request: request, outcome: .refused(refusal))
    }

    activeOperation = .drawingStroke
    defer {
      activeJogCommandTransmitted = false
      preTransmissionJogCancellationRequested = false
      if jogCancellationProgress != nil {
        let reason = stickyAmbiguity
          ?? .transport("drawing stroke ended without a final Jog Cancel outcome")
        completeActiveJogCancellation(.ambiguous(reason))
      }
      jogCancellationProgress = nil
      activeOperation = nil
      if connection == .moving || connection == .actuatingPen { connection = .connected }
    }

    do {
      try await link.discardPendingInput()
    } catch {
      await closeAndInvalidateKnowledge()
      return finishDrawingStroke(
        request: request,
        outcome: .refused(
          .freshStatusUnavailable(
            "could not discard pending controller input: \(String(describing: error))"
          )
        )
      )
    }
    if preTransmissionJogCancellationRequested {
      return finishDrawingStroke(request: request, outcome: .refused(.operationInFlight))
    }

    let admissionDeadline = addingClamped(clock.nowNanoseconds(), queryTimeoutNanoseconds)
    switch await requestMotionStatus(deadline: admissionDeadline) {
    case .status(let report):
      apply(report)
      if let refusal = validateFreshControllerStatus() {
        await closeAndInvalidateKnowledge()
        return finishDrawingStroke(
          request: request,
          outcome: .refused(Self.drawingStrokeRefusal(from: refusal))
        )
      }
    case .ambiguous(let reason):
      await closeAndInvalidateKnowledge()
      return finishDrawingStroke(
        request: request,
        outcome: .refused(
          .freshStatusUnavailable(Self.admissionFailureDescription(reason))
        )
      )
    }

    guard let startPosition = position else {
      await closeAndInvalidateKnowledge()
      return finishDrawingStroke(
        request: request,
        outcome: .refused(
          .freshStatusUnavailable("fresh status omitted a valid MPos")
        )
      )
    }
    if preTransmissionJogCancellationRequested {
      connection = .connected
      return finishDrawingStroke(request: request, outcome: .refused(.operationInFlight))
    }
    let startSampleNanoseconds = clock.nowNanoseconds()

    connection = .moving
    let command = wire.bytes
    do {
      try await serializedWrite(command)
      activeJogCommandTransmitted = true
      recordRawIOBestEffort(
        RawMachineIO(direction: .transmit, bytes: command, timestamp: timestamp())
      )
    } catch let error as MachineLinkError {
      return finishDrawingStroke(
        request: request,
        outcome: drawingStrokeOutcomeForWriteError(error)
      )
    } catch {
      return finishDrawingStroke(
        request: request,
        outcome: ambiguousDrawingStroke(.transport(String(describing: error)))
      )
    }

    switch await awaitCommandAcknowledgement(context: "drawing stroke") {
    case .accepted:
      break
    case .rejected(let reason):
      connection = .connected
      if jogCancellationProgress != nil {
        completeActiveJogCancellation(.refused(.noActiveJog))
      }
      return finishDrawingStroke(
        request: request,
        outcome: .refused(.controllerRejected(reason))
      )
    case .ambiguous(let reason):
      return finishDrawingStroke(
        request: request,
        outcome: ambiguousDrawingStroke(reason)
      )
    }

    let timeout = Self.completionTimeoutNanoseconds(
      for: wire.request,
      controllerMotionTiming: controllerMotionTiming,
      graceNanoseconds: completionGraceNanoseconds
    )
    let deadline = addingClamped(clock.nowNanoseconds(), timeout)
    while clock.nowNanoseconds() < deadline {
      switch await requestMotionStatus(deadline: deadline) {
      case .status(let report):
        apply(report)
        switch report.controllerState {
        case .idle:
          if jogCancellationProgress == .transmitting {
            await waitForCancelWriteResolution()
          }
          guard let finalPosition = report.machinePosition else {
            return finishDrawingStroke(
              request: request,
              outcome: ambiguousDrawingStroke(
                .malformedReply("Idle status omitted a valid MPos")
              )
            )
          }
          connection = .connected
          let evidence = DrawingStrokeEvidence(
            request: request,
            startPosition: startPosition,
            startSampleNanoseconds: startSampleNanoseconds,
            finalPosition: finalPosition,
            finalSampleNanoseconds: clock.nowNanoseconds()
          )
          if jogCancellationProgress == .transmitted {
            let penRaiseOutcome = await transmitPenActuation(.raise)
            if case .ambiguous(let reason) = penRaiseOutcome {
              return finishDrawingStroke(
                request: request,
                outcome: .ambiguous(reason)
              )
            }
            if jogCancellationProgress == .transmitted {
              completeActiveJogCancellation(.completed(finalPosition: finalPosition))
            }
            return finishDrawingStroke(
              request: request,
              outcome: .cancelled(
                evidence: evidence,
                penRaiseOutcome: penRaiseOutcome
              )
            )
          }
          if let stickyAmbiguity {
            return finishDrawingStroke(
              request: request,
              outcome: .ambiguous(stickyAmbiguity)
            )
          }
          return finishDrawingStroke(
            request: request,
            outcome: .completed(evidence: evidence)
          )
        case .run, .jog:
          do {
            try await sleepBeforeNextPoll(deadline: deadline)
          } catch {
            return finishDrawingStroke(
              request: request,
              outcome: ambiguousDrawingStroke(
                .completionTimedOut(deadlineNanoseconds: deadline)
              )
            )
          }
        case .alarm:
          return finishDrawingStroke(
            request: request,
            outcome: ambiguousDrawingStroke(.controllerAlarm(report.state))
          )
        case .hold:
          return finishDrawingStroke(
            request: request,
            outcome: ambiguousDrawingStroke(.controllerHold)
          )
        case .door, .check, .home, .sleep, .tool, .unknown:
          return finishDrawingStroke(
            request: request,
            outcome: ambiguousDrawingStroke(
              .unexpectedControllerState(report.controllerState)
            )
          )
        }
      case .ambiguous(let reason):
        return finishDrawingStroke(
          request: request,
          outcome: ambiguousDrawingStroke(reason)
        )
      }
    }
    return finishDrawingStroke(
      request: request,
      outcome: ambiguousDrawingStroke(
        .completionTimedOut(deadlineNanoseconds: deadline)
      )
    )
  }

  /// Sends one closed pen command followed by the fixed settle dwell. A successful
  /// result records the controller-commanded state, not a visually proven state.
  public func requestPenActuation(_ command: PenCommand) async -> PenOutcome {
    guard activeOperation == nil else {
      return finishPen(command: command, outcome: .refused(.operationInFlight))
    }
    if let refusal = validatePenSession(command) {
      return finishPen(command: command, outcome: .refused(refusal))
    }

    activeOperation = .penActuation
    defer {
      activeOperation = nil
      if connection == .actuatingPen { connection = .connected }
    }

    do {
      try await link.discardPendingInput()
    } catch {
      await closeAndInvalidateKnowledge()
      return finishPen(
        command: command,
        outcome: .refused(
          .freshStatusUnavailable(
            "could not discard pending controller input: \(String(describing: error))"
          )
        )
      )
    }

    let admissionDeadline = addingClamped(clock.nowNanoseconds(), queryTimeoutNanoseconds)
    switch await requestMotionStatus(deadline: admissionDeadline) {
    case .status(let report):
      apply(report)
      if let refusal = validateFreshPenStatus(command) {
        await closeAndInvalidateKnowledge()
        return finishPen(command: command, outcome: .refused(refusal))
      }
    case .ambiguous(let reason):
      await closeAndInvalidateKnowledge()
      return finishPen(
        command: command,
        outcome: .refused(.freshStatusUnavailable(Self.admissionFailureDescription(reason)))
      )
    }

    return await transmitPenActuation(command)
  }

  /// Performs the already-admitted closed pen command. Drawing-stroke
  /// cancellation uses this exact wire path after its final Idle/MPos sample,
  /// while the drawing stroke remains the single active operation.
  private func transmitPenActuation(_ command: PenCommand) async -> PenOutcome {
    connection = .actuatingPen
    let profile = PenActuationProfile.localPlotter
    let actuationBytes = profile.actuationBytes(for: command)
    do {
      try await writePhysicalCommand(actuationBytes)
    } catch let error as MachineLinkError {
      return finishPen(command: command, outcome: penOutcomeForWriteError(error))
    } catch {
      return finishPen(
        command: command,
        outcome: ambiguousPen(.transport(String(describing: error)))
      )
    }

    switch await awaitCommandAcknowledgement(context: "pen actuation") {
    case .accepted:
      break
    case .rejected(let reason):
      connection = .connected
      return finishPen(command: command, outcome: .refused(.controllerRejected(reason)))
    case .ambiguous(let reason):
      return finishPen(command: command, outcome: ambiguousPen(reason))
    }

    let settleBytes = profile.settleBytes
    do {
      try await writePhysicalCommand(settleBytes)
    } catch let error as MachineLinkError {
      return finishPen(command: command, outcome: penOutcomeForWriteError(error))
    } catch {
      return finishPen(
        command: command,
        outcome: ambiguousPen(.transport(String(describing: error)))
      )
    }

    switch await awaitCommandAcknowledgement(context: "pen settle") {
    case .accepted:
      penState = command.commandedState
      connection = .connected
      return finishPen(
        command: command,
        outcome: .commandedAndSettled(
          command: command,
          commandedState: command.commandedState
        )
      )
    case .rejected(let reason):
      return finishPen(
        command: command,
        outcome: ambiguousPen(.settleCommandRejected(reason))
      )
    case .ambiguous(let reason):
      return finishPen(command: command, outcome: ambiguousPen(reason))
    }
  }

  public static func encodePenActuation(_ command: PenCommand) -> Data {
    PenActuationProfile.localPlotter.actuationBytes(for: command)
  }

  public static var encodePenSettle: Data {
    PenActuationProfile.localPlotter.settleBytes
  }

  public static func completionTimeoutNanoseconds(
    for request: RelativeJogRequest,
    graceNanoseconds: UInt64 = 1_000_000_000
  ) -> UInt64 {
    completionTimeoutNanoseconds(
      for: request,
      controllerMotionTiming: nil,
      graceNanoseconds: graceNanoseconds
    )
  }

  static func completionTimeoutNanoseconds(
    for request: RelativeJogRequest,
    controllerMotionTiming: ControllerMotionTiming?,
    graceNanoseconds: UInt64 = 1_000_000_000
  ) -> UInt64 {
    guard let wire = makeWireRelativeJog(request).wire else {
      return min(graceNanoseconds, maximumCompletionTimeoutNanoseconds)
    }
    let travelSeconds = estimatedTravelSeconds(
      wire: wire,
      controllerMotionTiming: controllerMotionTiming
    )
    let travelNanoseconds = travelSeconds * 1_000_000_000
    guard travelNanoseconds.isFinite,
      travelNanoseconds < Double(maximumCompletionTimeoutNanoseconds)
    else {
      return maximumCompletionTimeoutNanoseconds
    }
    let boundedTravel = UInt64(max(0, travelNanoseconds.rounded(.up)))
    return min(
      addingClamped(boundedTravel, graceNanoseconds),
      maximumCompletionTimeoutNanoseconds
    )
  }

  static func controllerMotionTiming(
    from exchanges: [PassiveProbeExchange]
  ) -> ControllerMotionTiming? {
    var settings: [String: Double] = [:]
    for exchange in exchanges where exchange.query == .configuration {
      for line in exchange.lines {
        guard case .configuration(let key, let value) = line.kind,
          let number = Double(value), number.isFinite, number > 0
        else { continue }
        settings[key] = number
      }
    }
    guard let maximumXFeed = settings["$110"],
      let maximumYFeed = settings["$111"],
      let xAcceleration = settings["$120"],
      let yAcceleration = settings["$121"]
    else { return nil }
    return ControllerMotionTiming(
      maximumXFeedMMPerMinute: maximumXFeed,
      maximumYFeedMMPerMinute: maximumYFeed,
      xAccelerationMMPerSecondSquared: xAcceleration,
      yAccelerationMMPerSecondSquared: yAcceleration
    )
  }

  private static func controllerAxisFeedLimits(
    from exchanges: [PassiveProbeExchange]
  ) -> ControllerAxisFeedLimits? {
    var settings: [String: Double] = [:]
    for exchange in exchanges where exchange.query == .configuration {
      for line in exchange.lines {
        guard case .configuration(let key, let value) = line.kind,
          let number = Double(value), number.isFinite, number > 0
        else { continue }
        settings[key] = number
      }
    }
    guard let maximumXFeed = settings["$110"],
      let maximumYFeed = settings["$111"]
    else { return nil }
    return ControllerAxisFeedLimits(
      maximumXFeedMMPerMinute: maximumXFeed,
      maximumYFeedMMPerMinute: maximumYFeed
    )
  }

  private static func estimatedTravelSeconds(
    wire: WireRelativeJog,
    controllerMotionTiming: ControllerMotionTiming?
  ) -> Double {
    let distance = wire.delta.magnitude
    guard let timing = controllerMotionTiming else {
      return distance / wire.feedMMPerMinute * 60
    }
    let xComponent = abs(wire.delta.dx) / distance
    let yComponent = abs(wire.delta.dy) / distance
    var pathFeedLimits: [Double] = []
    var pathAccelerationLimits: [Double] = []
    if xComponent > 0 {
      pathFeedLimits.append(timing.maximumXFeedMMPerMinute / xComponent)
      pathAccelerationLimits.append(timing.xAccelerationMMPerSecondSquared / xComponent)
    }
    if yComponent > 0 {
      pathFeedLimits.append(timing.maximumYFeedMMPerMinute / yComponent)
      pathAccelerationLimits.append(timing.yAccelerationMMPerSecondSquared / yComponent)
    }
    guard let controllerFeedLimit = pathFeedLimits.min(),
      let pathAcceleration = pathAccelerationLimits.min(),
      controllerFeedLimit.isFinite, controllerFeedLimit > 0,
      pathAcceleration.isFinite, pathAcceleration > 0
    else {
      return distance / wire.feedMMPerMinute * 60
    }
    let pathVelocity = min(wire.feedMMPerMinute, controllerFeedLimit) / 60
    let accelerationAndDecelerationDistance = pathVelocity * pathVelocity / pathAcceleration
    if distance >= accelerationAndDecelerationDistance {
      let accelerationSeconds = pathVelocity / pathAcceleration
      let cruiseSeconds =
        (distance - accelerationAndDecelerationDistance) / pathVelocity
      return 2 * accelerationSeconds + cruiseSeconds
    }
    return 2 * sqrt(distance / pathAcceleration)
  }

  public static func encodeRelativeJog(_ request: RelativeJogRequest) -> Data {
    makeWireRelativeJog(request).wire?.bytes ?? Data()
  }

  public static func encodeDrawingStroke(_ request: DrawingStrokeRequest) -> Data {
    encodeRelativeJog(
      RelativeJogRequest(
        delta: request.delta,
        feedMMPerMinute: request.feedMMPerMinute
      )
    )
  }

  /// GRBL/grblHAL realtime Jog Cancel. This is deliberately not the feed-hold
  /// byte (`!`) and not an emergency-stop claim.
  public static let encodeJogCancel = Data([0x85])

  private func ensureConnected() async throws {
    if connection == .connected || connection == .probing || connection == .moving
      || connection == .actuatingPen
    {
      return
    }
    connection = .connecting
    do {
      try await link.open()
      connection = .connected
    } catch {
      connection = .blocked
      throw error
    }
  }

  private func validateSessionAndRequest(_ wire: WireRelativeJog) -> MotionRefusal? {
    guard selectionIsExplicit else { return .noSerialDeviceSelected }
    if let stickyAmbiguity { return .stickyAmbiguity(stickyAmbiguity) }
    guard connection == .connected else { return .notConnected }
    guard motionGuardState == .active else { return .motionGuardInactive }
    guard penState == .up else { return .penNotUp(penState) }
    if let maximumFeed = controllerMaximumFeed(for: wire),
      wire.feedMMPerMinute > maximumFeed
    {
      return .feedExceedsMaximum(
        requested: wire.feedMMPerMinute,
        maximum: maximumFeed
      )
    }
    return nil
  }

  private func validateDrawingStrokeSessionAndRequest(
    _ wire: WireRelativeJog
  ) -> DrawingStrokeRefusal? {
    guard selectionIsExplicit else { return .noSerialDeviceSelected }
    if let stickyAmbiguity { return .stickyAmbiguity(stickyAmbiguity) }
    guard connection == .connected else { return .notConnected }
    guard motionGuardState == .active else { return .motionGuardInactive }
    guard penState == .down else { return .penNotDown(penState) }
    guard let maximumFeed = controllerMaximumFeed(for: wire) else {
      return .controllerFeedCapabilityUnknown
    }
    if wire.feedMMPerMinute > maximumFeed {
      return .feedExceedsMaximum(
        requested: wire.feedMMPerMinute,
        maximum: maximumFeed
      )
    }
    return nil
  }

  private func validateFreshControllerStatus() -> MotionRefusal? {
    guard let controllerState else { return .controllerStateUnknown }
    guard controllerState.isRecognized else { return .controllerStateUnknown }
    guard !controllerState.isAlarm else { return .controllerAlarm("controller is in Alarm") }
    guard controllerState == .idle else { return .controllerNotIdle(controllerState) }
    guard !pins.hasRelevantLimitAsserted else {
      return .relevantLimitAsserted(pins.rawValue)
    }
    guard position != nil else { return .machinePositionUnknown }
    return nil
  }

  private func validatePenSession(_ command: PenCommand) -> PenRefusal? {
    guard selectionIsExplicit else { return .noSerialDeviceSelected }
    if let stickyAmbiguity { return .stickyAmbiguity(stickyAmbiguity) }
    guard connection == .connected else { return .notConnected }
    guard motionGuardState == .active else { return .motionGuardInactive }
    return nil
  }

  private func validateFreshPenStatus(_ command: PenCommand) -> PenRefusal? {
    guard let controllerState else { return .controllerStateUnknown }
    guard controllerState.isRecognized else { return .controllerStateUnknown }
    guard !controllerState.isAlarm else { return .controllerAlarm("controller is in Alarm") }
    guard controllerState == .idle else { return .controllerNotIdle(controllerState) }
    guard command == .lower else { return nil }
    guard !pins.hasRelevantLimitAsserted else {
      return .relevantLimitAsserted(pins.rawValue)
    }
    guard position != nil else { return .machinePositionUnknown }
    return nil
  }

  private func validateMotionGuardActivation() -> MotionRefusal? {
    guard activeOperation == nil else { return .operationInFlight }
    guard selectionIsExplicit else { return .noSerialDeviceSelected }
    if let stickyAmbiguity { return .stickyAmbiguity(stickyAmbiguity) }
    guard connection == .connected else { return .notConnected }
    guard let controllerState, controllerState.isRecognized else {
      return .controllerStateUnknown
    }
    guard !controllerState.isAlarm else {
      return .controllerAlarm("controller is in Alarm")
    }
    guard controllerState == .idle else { return .controllerNotIdle(controllerState) }
    guard !pins.hasRelevantLimitAsserted else {
      return .relevantLimitAsserted(pins.rawValue)
    }
    return nil
  }

  private func controllerMaximumFeed(for wire: WireRelativeJog) -> Double? {
    guard let axisLimits = controllerAxisFeedLimits else { return nil }
    let xMagnitude = abs(wire.delta.dx)
    let yMagnitude = abs(wire.delta.dy)
    let scale = max(xMagnitude, yMagnitude)
    guard scale.isFinite, scale > 0 else { return nil }
    let scaledMagnitude = hypot(xMagnitude / scale, yMagnitude / scale)
    guard scaledMagnitude.isFinite, scaledMagnitude > 0 else { return nil }

    var pathLimits: [Double] = []
    let xComponent = (xMagnitude / scale) / scaledMagnitude
    let yComponent = (yMagnitude / scale) / scaledMagnitude
    if xComponent > 0 {
      pathLimits.append(axisLimits.maximumXFeedMMPerMinute / xComponent)
    }
    if yComponent > 0 {
      pathLimits.append(axisLimits.maximumYFeedMMPerMinute / yComponent)
    }
    return pathLimits.min()
  }

  private static func makeWireRelativeJog(
    _ request: RelativeJogRequest
  ) -> (wire: WireRelativeJog?, refusal: MotionRefusal?) {
    guard request.delta.dx.isFinite, request.delta.dy.isFinite else {
      return (nil, .nonFiniteDelta)
    }
    guard request.feedMMPerMinute.isFinite else {
      return (nil, .nonPositiveFeed(request.feedMMPerMinute))
    }
    let x = quantizedWireNumber(request.delta.dx)
    let y = quantizedWireNumber(request.delta.dy)
    let feed = quantizedWireNumber(request.feedMMPerMinute)
    guard let x, let y, let feed else { return (nil, .nonFiniteDelta) }
    guard x.value != 0 || y.value != 0 else { return (nil, .zeroDelta) }
    guard feed.value > 0 else { return (nil, .nonPositiveFeed(feed.value)) }
    guard let delta = try? Vector2<MachineSpace>(dx: x.value, dy: y.value) else {
      return (nil, .nonFiniteDelta)
    }
    return (
      WireRelativeJog(
        delta: delta,
        feedMMPerMinute: feed.value,
        xText: x.text,
        yText: y.text,
        feedText: feed.text
      ),
      nil
    )
  }

  private static func drawingStrokeRefusal(
    from refusal: MotionRefusal
  ) -> DrawingStrokeRefusal {
    switch refusal {
    case .noSerialDeviceSelected: return .noSerialDeviceSelected
    case .notConnected: return .notConnected
    case .motionGuardInactive: return .motionGuardInactive
    case .controllerStateUnknown: return .controllerStateUnknown
    case .controllerNotIdle(let state): return .controllerNotIdle(state)
    case .controllerAlarm(let detail): return .controllerAlarm(detail)
    case .relevantLimitAsserted(let pins): return .relevantLimitAsserted(pins)
    case .machinePositionUnknown: return .machinePositionUnknown
    case .nonFiniteDelta: return .nonFiniteDelta
    case .zeroDelta: return .zeroDelta
    case .nonPositiveFeed(let feed): return .nonPositiveFeed(feed)
    case .feedExceedsMaximum(let requested, let maximum):
      return .feedExceedsMaximum(requested: requested, maximum: maximum)
    case .penNotUp(let state): return .penNotDown(state)
    case .operationInFlight: return .operationInFlight
    case .stickyAmbiguity(let ambiguity): return .stickyAmbiguity(ambiguity)
    case .controllerRejected(let detail): return .controllerRejected(detail)
    case .freshStatusUnavailable(let detail): return .freshStatusUnavailable(detail)
    }
  }

  private static func admissionFailureDescription(_ reason: MotionAmbiguity) -> String {
    switch reason {
    case .disconnected:
      return "controller disconnected during the fresh status query"
    case .completionTimedOut, .acceptanceTimedOut:
      return "fresh status query timed out"
    case .malformedReply(let detail):
      return "fresh status reply was malformed: \(detail)"
    case .controllerAlarm(let detail):
      return "controller alarmed during the fresh status query: \(detail)"
    case .controllerHold:
      return "controller entered Hold during the fresh status query"
    case .unexpectedControllerState(let state):
      return "controller entered \(state.rawValue) during the fresh status query"
    case .settleCommandRejected(let detail):
      return "controller rejected a settle command during the fresh status query: \(detail)"
    case .partialWrite, .writeTimedOut, .writeCancelled, .transport:
      return "fresh status transport failed: \(reason.actionableDescription)"
    }
  }

  private enum AcknowledgementResult {
    case accepted
    case rejected(String)
    case ambiguous(MotionAmbiguity)
  }

  private func acquireWireWrite(priority: Bool) async {
    guard wireWriteInProgress else {
      wireWriteInProgress = true
      return
    }
    await withCheckedContinuation { continuation in
      if priority {
        priorityWireWriteWaiters.append(continuation)
      } else {
        regularWireWriteWaiters.append(continuation)
      }
    }
  }

  private func releaseWireWrite() {
    let continuation: CheckedContinuation<Void, Never>?
    if !priorityWireWriteWaiters.isEmpty {
      continuation = priorityWireWriteWaiters.removeFirst()
    } else if !regularWireWriteWaiters.isEmpty {
      continuation = regularWireWriteWaiters.removeFirst()
    } else {
      wireWriteInProgress = false
      continuation = nil
    }
    continuation?.resume()
  }

  private func serializedWrite(_ bytes: Data) async throws {
    await acquireWireWrite(priority: false)
    defer { releaseWireWrite() }
    try await link.write(bytes)
  }

  private func writePhysicalCommand(_ bytes: Data) async throws {
    try await serializedWrite(bytes)
    recordRawIOBestEffort(
      RawMachineIO(direction: .transmit, bytes: bytes, timestamp: timestamp())
    )
  }

  private func awaitCommandAcknowledgement(context: String) async -> AcknowledgementResult {
    var parser = GRBLParser()
    let deadline = addingClamped(clock.nowNanoseconds(), queryTimeoutNanoseconds)
    var receivedBytes = 0
    var receivedChunks = 0
    do {
      while clock.nowNanoseconds() < deadline {
        guard receivedBytes < maximumRawReceiveBytesPerQuery,
          receivedChunks < maximumRawReceiveChunksPerQuery
        else {
          return .ambiguous(.malformedReply("\(context) acknowledgement exceeded response bounds"))
        }
        let remaining = deadline - clock.nowNanoseconds()
        let data = try await link.read(
          maximumBytes: min(4_096, maximumRawReceiveBytesPerQuery - receivedBytes),
          timeoutNanoseconds: remaining
        )
        receivedBytes += data.count
        receivedChunks += 1
        recordRawIOBestEffort(
          RawMachineIO(direction: .receive, bytes: data, timestamp: timestamp())
        )
        for line in parser.consume(data) {
          switch line.kind {
          case .acknowledgement:
            return .accepted
          case .error(let code):
            return .rejected("error:\(code)")
          case .alarm:
            applyAlarm(line.text)
            return .ambiguous(.controllerAlarm(line.text))
          case .status(let report):
            apply(report)
          case .unknown:
            return .ambiguous(.malformedReply(line.text))
          case .greeting:
            applyControllerReset()
            return .ambiguous(.malformedReply("controller reset greeting arrived after \(context)"))
          case .configuration, .bracketReport, .message:
            continue
          }
        }
      }
      return .ambiguous(.acceptanceTimedOut)
    } catch MachineLinkError.timedOut {
      return .ambiguous(.acceptanceTimedOut)
    } catch MachineLinkError.disconnected {
      invalidateConnectionKnowledge()
      return .ambiguous(.disconnected)
    } catch {
      return .ambiguous(.transport(String(describing: error)))
    }
  }

  private enum MotionStatusResult {
    case status(ControllerStatusReport)
    case ambiguous(MotionAmbiguity)
  }

  private func requestMotionStatus(deadline: UInt64) async -> MotionStatusResult {
    let query = PassiveQuery.status.wireBytes
    do {
      try await serializedWrite(query)
      recordRawIOBestEffort(
        RawMachineIO(direction: .transmit, bytes: query, timestamp: timestamp())
      )
    } catch MachineLinkError.disconnected {
      invalidateConnectionKnowledge()
      return .ambiguous(.disconnected)
    } catch {
      return .ambiguous(.transport(String(describing: error)))
    }

    var parser = GRBLParser()
    var receivedBytes = 0
    var receivedChunks = 0
    let queryDeadline = min(deadline, addingClamped(clock.nowNanoseconds(), queryTimeoutNanoseconds))
    do {
      while clock.nowNanoseconds() < queryDeadline {
        guard receivedBytes < maximumRawReceiveBytesPerQuery,
          receivedChunks < maximumRawReceiveChunksPerQuery
        else {
          return .ambiguous(.malformedReply("status response exceeded response bounds"))
        }
        let remainingBytes = maximumRawReceiveBytesPerQuery - receivedBytes
        let data = try await link.read(
          maximumBytes: min(4_096, remainingBytes),
          timeoutNanoseconds: queryDeadline - clock.nowNanoseconds()
        )
        guard data.count <= remainingBytes else {
          return .ambiguous(.malformedReply("status response exceeded byte bound"))
        }
        receivedBytes += data.count
        receivedChunks += 1
        recordRawIOBestEffort(
          RawMachineIO(direction: .receive, bytes: data, timestamp: timestamp())
        )
        for line in parser.consume(data) {
          switch line.kind {
          case .status(let report):
            guard report.controllerState.isRecognized else {
              return .ambiguous(.malformedReply(line.text))
            }
            return .status(report)
          case .alarm:
            applyAlarm(line.text)
            return .ambiguous(.controllerAlarm(line.text))
          case .error(let code):
            return .ambiguous(.malformedReply("error:\(code) while polling status"))
          case .unknown:
            return .ambiguous(.malformedReply(line.text))
          case .greeting:
            applyControllerReset()
            return .ambiguous(
              .malformedReply("controller reset greeting arrived during status query")
            )
          default:
            continue
          }
        }
      }
      return .ambiguous(.completionTimedOut(deadlineNanoseconds: deadline))
    } catch MachineLinkError.timedOut {
      return .ambiguous(.completionTimedOut(deadlineNanoseconds: deadline))
    } catch MachineLinkError.disconnected {
      invalidateConnectionKnowledge()
      return .ambiguous(.disconnected)
    } catch {
      return .ambiguous(.transport(String(describing: error)))
    }
  }

  private func sleepBeforeNextPoll(deadline: UInt64) async throws {
    let now = clock.nowNanoseconds()
    guard now < deadline else { throw MachineLinkError.timedOut }
    try await clock.sleep(nanoseconds: min(statusPollIntervalNanoseconds, deadline - now))
  }

  private func outcomeForWriteError(_ error: MachineLinkError) -> MotionOutcome {
    switch error {
    case .writeTimedOut(let written, let total):
      if written > 0 {
        return ambiguous(.partialWrite(bytesWritten: written, totalBytes: total))
      }
      return ambiguous(.writeTimedOut(bytesWritten: written, totalBytes: total))
    case .writeCancelled(let written, let total):
      if written > 0 {
        return ambiguous(.partialWrite(bytesWritten: written, totalBytes: total))
      }
      return ambiguous(.writeCancelled(bytesWritten: written, totalBytes: total))
    case .disconnected, .notOpen:
      invalidateConnectionKnowledge()
      return ambiguous(.disconnected)
    default:
      return ambiguous(.transport(String(describing: error)))
    }
  }

  private func drawingStrokeOutcomeForWriteError(
    _ error: MachineLinkError
  ) -> DrawingStrokeOutcome {
    switch error {
    case .writeTimedOut(let written, let total):
      if written > 0 {
        return ambiguousDrawingStroke(.partialWrite(bytesWritten: written, totalBytes: total))
      }
      return ambiguousDrawingStroke(.writeTimedOut(bytesWritten: written, totalBytes: total))
    case .writeCancelled(let written, let total):
      if written > 0 {
        return ambiguousDrawingStroke(.partialWrite(bytesWritten: written, totalBytes: total))
      }
      return ambiguousDrawingStroke(.writeCancelled(bytesWritten: written, totalBytes: total))
    case .disconnected, .notOpen:
      invalidateConnectionKnowledge()
      return ambiguousDrawingStroke(.disconnected)
    default:
      return ambiguousDrawingStroke(.transport(String(describing: error)))
    }
  }

  private func ambiguityForCancelWriteError(_ error: MachineLinkError) -> MotionAmbiguity {
    switch error {
    case .writeTimedOut(let written, let total):
      if written > 0 {
        return .partialWrite(bytesWritten: written, totalBytes: total)
      }
      return .writeTimedOut(bytesWritten: written, totalBytes: total)
    case .writeCancelled(let written, let total):
      if written > 0 {
        return .partialWrite(bytesWritten: written, totalBytes: total)
      }
      return .writeCancelled(bytesWritten: written, totalBytes: total)
    case .disconnected, .notOpen:
      invalidateConnectionKnowledge()
      return .disconnected
    default:
      return .transport(String(describing: error))
    }
  }

  private func penOutcomeForWriteError(_ error: MachineLinkError) -> PenOutcome {
    switch error {
    case .writeTimedOut(let written, let total):
      if written > 0 {
        return ambiguousPen(.partialWrite(bytesWritten: written, totalBytes: total))
      }
      return ambiguousPen(.writeTimedOut(bytesWritten: written, totalBytes: total))
    case .writeCancelled(let written, let total):
      if written > 0 {
        return ambiguousPen(.partialWrite(bytesWritten: written, totalBytes: total))
      }
      return ambiguousPen(.writeCancelled(bytesWritten: written, totalBytes: total))
    case .disconnected, .notOpen:
      invalidateConnectionKnowledge()
      return ambiguousPen(.disconnected)
    default:
      return ambiguousPen(.transport(String(describing: error)))
    }
  }

  private func ambiguous(_ reason: MotionAmbiguity) -> MotionOutcome {
    setAmbiguous(reason)
    return .ambiguous(reason)
  }

  private func ambiguousDrawingStroke(_ reason: MotionAmbiguity) -> DrawingStrokeOutcome {
    setAmbiguous(reason)
    return .ambiguous(reason)
  }

  private func ambiguousPen(_ reason: MotionAmbiguity) -> PenOutcome {
    setAmbiguous(reason)
    return .ambiguous(reason)
  }

  private func setAmbiguous(_ reason: MotionAmbiguity) {
    stickyAmbiguity = reason
    penState = .unknown
    motionGuardState = .inactive
    if jogCancellationProgress != nil {
      completeActiveJogCancellation(.ambiguous(reason))
    }
  }

  @discardableResult
  private func finishJogCancel(
    _ outcome: JogCancelOutcome,
    replaceLastOutcome: Bool = true
  ) -> JogCancelOutcome {
    if replaceLastOutcome { lastJogCancelOutcome = outcome }
    return outcome
  }

  private func completeActiveJogCancellation(_ outcome: JogCancelOutcome) {
    lastJogCancelOutcome = outcome
    jogCancellationProgress = nil
    resolveCancelWriteWaiters()
    let continuation = jogCancellationContinuation
    jogCancellationContinuation = nil
    continuation?.resume(returning: outcome)
  }

  private func waitForCancelWriteResolution() async {
    guard jogCancellationProgress == .transmitting else { return }
    await withCheckedContinuation { continuation in
      cancelWriteResolutionWaiters.append(continuation)
    }
  }

  private func resolveCancelWriteWaiters() {
    let waiters = cancelWriteResolutionWaiters
    cancelWriteResolutionWaiters.removeAll(keepingCapacity: false)
    for waiter in waiters { waiter.resume() }
  }

  private func finishMotion(request: RelativeJogRequest, outcome: MotionOutcome) -> MotionOutcome {
    lastMotionOutcome = outcome
    recordMotionBestEffort(request: request, outcome: outcome)
    return outcome
  }

  private func finishDrawingStroke(
    request: DrawingStrokeRequest,
    outcome: DrawingStrokeOutcome
  ) -> DrawingStrokeOutcome {
    lastDrawingStrokeOutcome = outcome
    recordDrawingStrokeBestEffort(request: request, outcome: outcome)
    return outcome
  }

  private func finishPen(command: PenCommand, outcome: PenOutcome) -> PenOutcome {
    lastPenOutcome = outcome
    recordPenBestEffort(command: command, outcome: outcome)
    return outcome
  }

  private func apply(_ report: ControllerStatusReport) {
    controllerState = report.controllerState
    position = report.machinePosition
    pins = report.controllerPins
    if report.controllerState.isAlarm || report.controllerPins.hasRelevantLimitAsserted {
      penState = report.controllerState.isAlarm ? .unknown : penState
      motionGuardState = .inactive
    }
  }

  private func applyAlarm(_ text: String) {
    controllerState = .alarm
    penState = .unknown
    motionGuardState = .inactive
  }

  private func applyControllerReset() {
    penState = .unknown
    motionGuardState = .inactive
  }

  private func closeAndInvalidateKnowledge() async {
    await link.close()
    invalidateConnectionKnowledge()
  }

  private func invalidateConnectionKnowledge() {
    connection = .disconnected
    controllerState = nil
    position = nil
    pins = ControllerPins(rawValue: "")
    penState = .unknown
    motionGuardState = .inactive
    controllerAxisFeedLimits = nil
    controllerMotionTiming = nil
  }

  private func executePassive(_ query: PassiveQuery) async -> PassiveProbeExchange {
    let commandID = UUID()
    let bytes = query.wireBytes
    var rawIO: [RawMachineIO] = []
    var parsed: [ParsedControllerLine] = []
    var parser = GRBLParser()
    var validator = PassiveReplyValidator(query: query)
    var rawReceiveBytes = 0
    var rawReceiveChunks = 0
    let deadline = addingClamped(clock.nowNanoseconds(), queryTimeoutNanoseconds)

    do {
      try await serializedWrite(bytes)
      let transmitted = RawMachineIO(direction: .transmit, bytes: bytes, timestamp: timestamp())
      rawIO.append(transmitted)
      recordRawIOBestEffort(transmitted)

      while true {
        guard rawReceiveBytes < maximumRawReceiveBytesPerQuery,
          rawReceiveChunks < maximumRawReceiveChunksPerQuery
        else {
          return exchange(
            query: query,
            commandID: commandID,
            rawIO: rawIO,
            lines: parsed,
            blocker: .responseLimitExceeded(
              query,
              maximumBytes: maximumRawReceiveBytesPerQuery,
              maximumChunks: maximumRawReceiveChunksPerQuery
            )
          )
        }
        let now = clock.nowNanoseconds()
        guard now < deadline else { throw MachineLinkError.timedOut }
        let remainingNanoseconds = deadline - now
        let remainingBytes = maximumRawReceiveBytesPerQuery - rawReceiveBytes
        let receivedBytes = try await link.read(
          maximumBytes: min(4_096, remainingBytes),
          timeoutNanoseconds: remainingNanoseconds
        )
        guard receivedBytes.count <= remainingBytes else {
          throw MachineLinkError.readExceededMaximum(
            expected: remainingBytes,
            actual: receivedBytes.count
          )
        }
        rawReceiveBytes += receivedBytes.count
        rawReceiveChunks += 1
        let received = RawMachineIO(
          direction: .receive,
          bytes: receivedBytes,
          timestamp: timestamp()
        )
        rawIO.append(received)
        recordRawIOBestEffort(received)
        guard clock.nowNanoseconds() <= deadline else { throw MachineLinkError.timedOut }
        let newLines = parser.consume(receivedBytes)
        for line in newLines {
          parsed.append(line)
          if case .status(let report) = line.kind { apply(report) }
          if case .greeting = line.kind { applyControllerReset() }
          switch validator.consume(line) {
          case .continueReading:
            continue
          case .complete:
            return PassiveProbeExchange(
              query: query,
              commandID: commandID,
              rawIO: rawIO,
              lines: parsed,
              completed: true,
              blocker: nil
            )
          case .invalid(let reason):
            return exchange(
              query: query,
              commandID: commandID,
              rawIO: rawIO,
              lines: parsed,
              blocker: .invalidReply(query, reason: reason)
            )
          case .alarm(let text):
            applyAlarm(text)
            return exchange(
              query: query,
              commandID: commandID,
              rawIO: rawIO,
              lines: parsed,
              blocker: .controllerAlarm(text)
            )
          case .controllerError(let text):
            return exchange(
              query: query,
              commandID: commandID,
              rawIO: rawIO,
              lines: parsed,
              blocker: .controllerError(text)
            )
          }
        }
      }
    } catch MachineLinkError.timedOut {
      if let unterminated = parser.finishUnterminatedLine() { parsed.append(unterminated) }
      return exchange(
        query: query,
        commandID: commandID,
        rawIO: rawIO,
        lines: parsed,
        blocker: .timeout(query)
      )
    } catch {
      if case MachineLinkError.disconnected = error { invalidateConnectionKnowledge() }
      return exchange(
        query: query,
        commandID: commandID,
        rawIO: rawIO,
        lines: parsed,
        blocker: .transport(String(describing: error))
      )
    }
  }

  private func exchange(
    query: PassiveQuery,
    commandID: UUID,
    rawIO: [RawMachineIO],
    lines: [ParsedControllerLine],
    blocker: MachineBlocker
  ) -> PassiveProbeExchange {
    PassiveProbeExchange(
      query: query,
      commandID: commandID,
      rawIO: rawIO,
      lines: lines,
      completed: false,
      blocker: blocker
    )
  }

  private func timestamp() -> RuntimeTimestamp {
    RuntimeTimestamp(monotonicNanoseconds: clock.nowNanoseconds())
  }

  private func recordRawIOBestEffort(_ io: RawMachineIO) {
    guard let ledger, let runID, let payload = try? JSONEncoder().encode(io) else { return }
    Task {
      try? await ledger.appendEvent(
        runID: runID,
        timestamp: io.timestamp,
        kind: "machine.raw_io",
        payload: payload
      )
    }
  }

  private func recordProbeStartedBestEffort(probeID: UUID, started: RuntimeTimestamp) {
    guard let ledger, let runID else { return }
    let record = PassiveProbeStartedRecord(
      probeID: probeID,
      link: link.descriptor,
      startedAt: started,
      queries: PassiveQuery.allCases
    )
    guard let payload = try? JSONEncoder().encode(record) else { return }
    Task {
      try? await ledger.appendEvent(
        runID: runID,
        timestamp: started,
        kind: "machine.passive_probe.started",
        schemaVersion: 1,
        payload: payload
      )
    }
  }

  private func finishProbe(
    probeID: UUID,
    started: RuntimeTimestamp,
    exchanges: [PassiveProbeExchange]
  ) -> PassiveProbeResult {
    let result = PassiveProbeResult(
      link: link.descriptor,
      startedAt: started,
      completedAt: timestamp(),
      exchanges: exchanges,
      blockers: blockers
    )
    if let ledger, let runID {
      let record = PassiveProbeFinishedRecord(probeID: probeID, result: result)
      if let payload = try? JSONEncoder().encode(record) {
        Task {
          try? await ledger.appendEvent(
            runID: runID,
            timestamp: result.completedAt,
            kind: "machine.passive_probe.finished",
            schemaVersion: 1,
            payload: payload
          )
        }
      }
    }
    lastProbe = result
    controllerAxisFeedLimits = blockers.isEmpty
      ? Self.controllerAxisFeedLimits(from: exchanges)
      : nil
    controllerMotionTiming = blockers.isEmpty
      ? Self.controllerMotionTiming(from: exchanges)
      : nil
    return result
  }

  private func recordMotionBestEffort(request: RelativeJogRequest, outcome: MotionOutcome) {
    guard let ledger, let runID else { return }
    let record = MotionDiagnosticRecord(request: request, outcome: outcome, timestamp: timestamp())
    guard let payload = try? JSONEncoder().encode(record) else { return }
    Task {
      try? await ledger.appendEvent(
        runID: runID,
        timestamp: record.timestamp,
        kind: "machine.relative_jog.result",
        schemaVersion: 1,
        payload: payload
      )
    }
  }

  private func recordDrawingStrokeBestEffort(
    request: DrawingStrokeRequest,
    outcome: DrawingStrokeOutcome
  ) {
    guard let ledger, let runID else { return }
    let record = DrawingStrokeDiagnosticRecord(
      request: request,
      outcome: outcome,
      timestamp: timestamp()
    )
    guard let payload = try? JSONEncoder().encode(record) else { return }
    Task {
      try? await ledger.appendEvent(
        runID: runID,
        timestamp: record.timestamp,
        kind: "machine.drawing_stroke.result",
        schemaVersion: 1,
        payload: payload
      )
    }
  }

  private func recordPenBestEffort(command: PenCommand, outcome: PenOutcome) {
    guard let ledger, let runID else { return }
    let record = PenDiagnosticRecord(command: command, outcome: outcome, timestamp: timestamp())
    guard let payload = try? JSONEncoder().encode(record) else { return }
    Task {
      try? await ledger.appendEvent(
        runID: runID,
        timestamp: record.timestamp,
        kind: "machine.pen_actuation.result",
        schemaVersion: 1,
        payload: payload
      )
    }
  }
}

private enum PassiveReplyDecision {
  case continueReading
  case complete
  case invalid(String)
  case alarm(String)
  case controllerError(String)
}

private struct PassiveReplyValidator {
  private static let coordinateReportNames: Set<String> = [
    "G54", "G55", "G56", "G57", "G58", "G59", "G28", "G30", "G92", "TLO", "PRB",
  ]

  let query: PassiveQuery
  private var hasExpectedEvidence = false

  init(query: PassiveQuery) {
    self.query = query
  }

  mutating func consume(_ line: ParsedControllerLine) -> PassiveReplyDecision {
    switch line.kind {
    case .alarm:
      return .alarm(line.text)
    case .error:
      return .controllerError(line.text)
    case .status(let status) where status.controllerState == .alarm:
      return .alarm(line.text)
    default:
      break
    }

    if query == .status {
      switch line.kind {
      case .status(let status):
        guard status.controllerState.isRecognized else {
          return .invalid("status report has an empty or unrecognized controller state")
        }
        return .complete
      case .acknowledgement:
        return .invalid("status query received terminal acknowledgement instead of status")
      default:
        return .continueReading
      }
    }

    if isExpectedEvidence(line.kind) { hasExpectedEvidence = true }
    guard line.kind == .acknowledgement else { return .continueReading }
    guard hasExpectedEvidence else {
      return .invalid("terminal acknowledgement arrived before expected \(query.rawValue) report")
    }
    return .complete
  }

  private func isExpectedEvidence(_ kind: ControllerLineKind) -> Bool {
    switch (query, kind) {
    case (.buildInfo, .bracketReport(let name?, let value)):
      return name.caseInsensitiveCompare("VER") == .orderedSame && !value.isEmpty
    case (.parserState, .bracketReport(let name?, let value)):
      return name.caseInsensitiveCompare("GC") == .orderedSame && !value.isEmpty
    case (.configuration, .configuration(let key, let value)):
      let digits = key.dropFirst()
      return key.first == "$" && !digits.isEmpty && digits.allSatisfy(\.isNumber)
        && Double(value)?.isFinite == true
    case (.coordinateOffsets, .bracketReport(let name?, let value)):
      return Self.coordinateReportNames.contains(name.uppercased())
        && Self.isValidCoordinateReport(name: name, value: value)
    default:
      return false
    }
  }

  private static func isValidCoordinateReport(name: String, value: String) -> Bool {
    let name = name.uppercased()
    if name == "TLO" { return Double(value)?.isFinite == true }
    let coordinateText = value.split(separator: ":", maxSplits: 1).first.map(String.init) ?? ""
    let components = coordinateText.split(separator: ",", omittingEmptySubsequences: false)
    guard components.count >= 3 else { return false }
    return components.prefix(3).allSatisfy { Double($0)?.isFinite == true }
  }
}

private func quantizedWireNumber(_ value: Double) -> (value: Double, text: String)? {
  guard value.isFinite else { return nil }
  let text = String(format: "%.3f", locale: Locale(identifier: "en_US_POSIX"), value)
  guard let quantized = Double(text), quantized.isFinite else { return nil }
  let normalized = quantized == 0 ? 0 : quantized
  return (
    normalized,
    normalized == 0 ? "0.000" : text
  )
}

private func addingClamped(_ lhs: UInt64, _ rhs: UInt64) -> UInt64 {
  let (sum, overflow) = lhs.addingReportingOverflow(rhs)
  return overflow ? UInt64.max : sum
}
