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
  public let stickyAmbiguity: MotionAmbiguity?
  public let motionLimits: MotionLimits?
  public let operationInFlight: Bool
  public let lastMotionOutcome: MotionOutcome?
  public let lastPenOutcome: PenOutcome?

  public init(
    connection: MachineConnectionState,
    link: MachineLinkDescriptor,
    lastProbe: PassiveProbeResult?,
    blockers: [MachineBlocker],
    controllerState: ControllerState? = nil,
    position: MachinePosition? = nil,
    pins: ControllerPins = ControllerPins(rawValue: ""),
    penState: PenState = .unknown,
    stickyAmbiguity: MotionAmbiguity? = nil,
    motionLimits: MotionLimits? = nil,
    operationInFlight: Bool = false,
    lastMotionOutcome: MotionOutcome? = nil,
    lastPenOutcome: PenOutcome? = nil
  ) {
    self.connection = connection
    self.link = link
    self.lastProbe = lastProbe
    self.blockers = blockers
    self.controllerState = controllerState
    self.position = position
    self.pins = pins
    self.penState = penState
    self.stickyAmbiguity = stickyAmbiguity
    self.motionLimits = motionLimits
    self.operationInFlight = operationInFlight
    self.lastMotionOutcome = lastMotionOutcome
    self.lastPenOutcome = lastPenOutcome
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
    case penActuation
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
  private var stickyAmbiguity: MotionAmbiguity?
  private var motionLimits: MotionLimits?
  private var controllerMotionTiming: ControllerMotionTiming?
  private var activeOperation: ActiveOperation?
  private var lastMotionOutcome: MotionOutcome?
  private var lastPenOutcome: PenOutcome?

  public init(
    link: any MachineLink,
    selectionIsExplicit: Bool = true,
    motionLimits: MotionLimits? = nil,
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
    self.motionLimits = motionLimits
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
    motionLimits: MotionLimits? = nil,
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
      motionLimits: motionLimits,
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
      stickyAmbiguity: stickyAmbiguity,
      motionLimits: motionLimits,
      operationInFlight: activeOperation != nil,
      lastMotionOutcome: lastMotionOutcome,
      lastPenOutcome: lastPenOutcome
    )
  }

  public func updateMotionLimits(_ limits: MotionLimits) {
    motionLimits = limits
  }

  public func disconnect() async {
    if activeOperation == .relativeJog || activeOperation == .penActuation {
      setAmbiguous(.disconnected)
    }
    await link.close()
    connection = .disconnected
    controllerState = nil
    position = nil
    pins = ControllerPins(rawValue: "")
    penState = .unknown
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

    let preflightDeadline = addingClamped(clock.nowNanoseconds(), queryTimeoutNanoseconds)
    switch await requestMotionStatus(deadline: preflightDeadline) {
    case .status(let report):
      apply(report)
      if let refusal = validateFreshControllerStatus(wire) {
        await closeAndInvalidateKnowledge()
        return finishMotion(request: request, outcome: .refused(refusal))
      }
    case .ambiguous(let reason):
      await closeAndInvalidateKnowledge()
      return finishMotion(
        request: request,
        outcome: .refused(.freshStatusUnavailable(Self.preflightFailureDescription(reason)))
      )
    }

    connection = .moving
    let command = wire.bytes
    do {
      try await link.write(command)
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
          guard let finalPosition = report.machinePosition else {
            return finishMotion(
              request: request,
              outcome: ambiguous(.malformedReply("Idle status omitted a valid MPos"))
            )
          }
          connection = .connected
          let outcome = MotionOutcome.acceptedThenCompleted(finalPosition: finalPosition)
          return finishMotion(request: request, outcome: outcome)
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

    let preflightDeadline = addingClamped(clock.nowNanoseconds(), queryTimeoutNanoseconds)
    switch await requestMotionStatus(deadline: preflightDeadline) {
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
        outcome: .refused(.freshStatusUnavailable(Self.preflightFailureDescription(reason)))
      )
    }

    connection = .actuatingPen
    let profile = PenActuationProfile.legacyServo
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
    PenActuationProfile.legacyServo.actuationBytes(for: command)
  }

  public static var encodePenSettle: Data {
    PenActuationProfile.legacyServo.settleBytes
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
    guard let limits = motionLimits else { return .motionLimitsMissing }
    guard penState == .up else { return .penNotUp(penState) }
    guard wire.feedMMPerMinute <= limits.maximumFeedMMPerMinute else {
      return .feedExceedsMaximum(
        requested: wire.feedMMPerMinute,
        maximum: limits.maximumFeedMMPerMinute
      )
    }
    let distance = wire.delta.magnitude
    guard distance <= limits.maximumDistanceMM else {
      return .distanceExceedsMaximum(requested: distance, maximum: limits.maximumDistanceMM)
    }
    return nil
  }

  private func validateFreshControllerStatus(_ wire: WireRelativeJog) -> MotionRefusal? {
    guard let limits = motionLimits else { return .motionLimitsMissing }
    guard let controllerState else { return .controllerStateUnknown }
    guard controllerState.isRecognized else { return .controllerStateUnknown }
    guard !controllerState.isAlarm else { return .controllerAlarm("controller is in Alarm") }
    guard controllerState == .idle else { return .controllerNotIdle(controllerState) }
    guard !pins.hasRelevantLimitAsserted else {
      return .relevantLimitAsserted(pins.rawValue)
    }
    guard let position else { return .machinePositionUnknown }
    guard let destination = try? MachinePosition(
      x: position.point.x + wire.delta.dx,
      y: position.point.y + wire.delta.dy
    ) else {
      return .nonFiniteDelta
    }
    guard limits.bounds.contains(destination.point) else {
      return .destinationOutsideBounds(destination)
    }
    return nil
  }

  private func validatePenSession(_ command: PenCommand) -> PenRefusal? {
    guard selectionIsExplicit else { return .noSerialDeviceSelected }
    if let stickyAmbiguity { return .stickyAmbiguity(stickyAmbiguity) }
    guard connection == .connected else { return .notConnected }
    if command == .lower, motionLimits == nil { return .motionLimitsMissing }
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
    guard let limits = motionLimits else { return .motionLimitsMissing }
    guard let position else { return .machinePositionUnknown }
    guard limits.bounds.contains(position.point) else {
      return .machinePositionOutsideBounds(position)
    }
    return nil
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

  private static func preflightFailureDescription(_ reason: MotionAmbiguity) -> String {
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

  private func writePhysicalCommand(_ bytes: Data) async throws {
    try await link.write(bytes)
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
            penState = .unknown
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
      try await link.write(query)
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
            penState = .unknown
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

  private func ambiguousPen(_ reason: MotionAmbiguity) -> PenOutcome {
    setAmbiguous(reason)
    return .ambiguous(reason)
  }

  private func setAmbiguous(_ reason: MotionAmbiguity) {
    stickyAmbiguity = reason
    penState = .unknown
  }

  private func finishMotion(request: RelativeJogRequest, outcome: MotionOutcome) -> MotionOutcome {
    lastMotionOutcome = outcome
    recordMotionBestEffort(request: request, outcome: outcome)
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
    if report.controllerState.isAlarm { penState = .unknown }
  }

  private func applyAlarm(_ text: String) {
    controllerState = .alarm
    penState = .unknown
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
      try await link.write(bytes)
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
          if case .greeting = line.kind { penState = .unknown }
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
