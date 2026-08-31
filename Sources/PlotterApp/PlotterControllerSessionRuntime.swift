import Foundation
import PlotterRuntime

struct PlotterControllerSessionReference: Hashable, Sendable {
  let revision: UInt64
  let capabilityID: UUID
}

enum PlotterControllerSessionIntent: Hashable, Sendable {
  case refreshSerialDevices
  case selectSerialDevice(MachineLinkDescriptor)
  case toggleConnection
  case requestPassiveProbe
  case clearAlarm
  case toggleMotionAuthorization
}

struct PlotterControllerSessionRequest: Hashable, Sendable {
  let reference: PlotterControllerSessionReference
  let intent: PlotterControllerSessionIntent
}

struct PlotterControllerSessionFacts: Sendable {
  let reference: PlotterControllerSessionReference
  let environment: OperatorFrameMode
  let selectedSerialDevice: MachineLinkDescriptor?
  let serialDevices: [MachineLinkDescriptor]
  let machineSnapshot: RunInterpreterSnapshot?
  let passiveProbe: PassiveProbeResult?
  let simulatedSnapshot: SimulatedLearningSnapshot?
  let machineError: String?
  let admissionClosed: Bool
  let controllerBusyReason: String?
  let discoveryBusyReason: String?
  let foreignOperationInFlight: Bool
  let frameModeSwitchInProgress: Bool
  let connectionActionInProgress: Bool
  let alarmClearInProgress: Bool
  let motionActionInProgress: Bool
  let lowerSessionAvailable: Bool
}

struct PlotterControllerSessionProjection: Sendable {
  let reference: PlotterControllerSessionReference
  let environment: OperatorFrameMode
  let serialDevices: [MachineLinkDescriptor]
  let selectedSerialDevice: MachineLinkDescriptor?
  let connectionActionTitle: String
  let selectionUnavailableReason: String?
  let connectionUnavailableReason: String?
  let sessionEstablished: Bool
  let motionAuthorized: Bool
  let motionAuthorizationUnavailableReason: String?
  let alarmClearUnavailableReason: String?
  let alarmClearInProgress: Bool
  let controllerConnectionText: String
  let controllerStateText: String
  let controllerAttentionText: String?
  let controllerLimitInputsText: String
  let controllerAlarmUnlockReadinessText: String
  let controllerAlarmEvidenceText: String?
  let motorPowerText: String
  let currentOperationText: String
  let machinePositionText: String
  let lastMotionOutcomeText: String
  let lastPenOutcomeText: String

  func request(_ intent: PlotterControllerSessionIntent) -> PlotterControllerSessionRequest {
    PlotterControllerSessionRequest(reference: reference, intent: intent)
  }
}

protocol PlotterControllerSessionIntentSink: Sendable {
  func submitControllerSessionRequest(
    _ request: PlotterControllerSessionRequest
  ) async -> PlotterControllerSessionDisposition
}

enum PlotterControllerSessionDisposition: Sendable {
  case completed(PlotterControllerSessionEffectResult)
  case refused(String)
  case cancelled
}

enum PlotterControllerSessionEffectResult: Sendable {
  case discovered([MachineLinkDescriptor], retiredLowerSession: Bool)
  case selected(MachineLinkDescriptor, retiredLowerSession: Bool)
  case liveSession(snapshot: RunInterpreterSnapshot?, probe: PassiveProbeResult?, error: String?)
  case liveDisconnected
  case simulated(SimulatedLearningSnapshot, action: String, refusal: String?)
}

enum PlotterControllerSessionRules {
  static func project(_ facts: PlotterControllerSessionFacts) -> PlotterControllerSessionProjection {
    let sessionEstablished = sessionEstablished(facts)
    let motionAuthorized = motionAuthorized(facts, sessionEstablished: sessionEstablished)
    let connectionText = controllerConnectionText(facts, sessionEstablished: sessionEstablished)
    let alarmEvidence = alarmEvidence(facts)
    return PlotterControllerSessionProjection(
      reference: facts.reference,
      environment: facts.environment,
      serialDevices: facts.serialDevices,
      selectedSerialDevice: facts.selectedSerialDevice,
      connectionActionTitle: connectionActionTitle(facts),
      selectionUnavailableReason: selectionUnavailableReason(facts),
      connectionUnavailableReason: connectionUnavailableReason(facts),
      sessionEstablished: sessionEstablished,
      motionAuthorized: motionAuthorized,
      motionAuthorizationUnavailableReason: motionAuthorizationUnavailableReason(
        facts,
        sessionEstablished: sessionEstablished,
        motionAuthorized: motionAuthorized
      ),
      alarmClearUnavailableReason: alarmClearUnavailableReason(facts, alarmEvidence: alarmEvidence),
      alarmClearInProgress: facts.alarmClearInProgress,
      controllerConnectionText: connectionText,
      controllerStateText: controllerStateText(facts),
      controllerAttentionText: controllerAttentionText(facts),
      controllerLimitInputsText: controllerLimitInputsText(facts),
      controllerAlarmUnlockReadinessText: controllerAlarmUnlockReadinessText(facts),
      controllerAlarmEvidenceText: alarmEvidence,
      motorPowerText: motorPowerText(facts),
      currentOperationText: currentOperationText(facts),
      machinePositionText: machinePositionText(facts),
      lastMotionOutcomeText: lastMotionOutcomeText(facts),
      lastPenOutcomeText: lastPenOutcomeText(facts)
    )
  }

  static func refusal(
    for intent: PlotterControllerSessionIntent,
    facts: PlotterControllerSessionFacts
  ) -> String? {
    let projection = project(facts)
    if facts.admissionClosed { return "The controller-session runtime is shut down." }
    switch intent {
    case .refreshSerialDevices:
      if let reason = facts.controllerBusyReason { return reason }
      return facts.foreignOperationInFlight ? "Wait for the current controller operation." : nil
    case .selectSerialDevice(let descriptor):
      if let reason = projection.selectionUnavailableReason { return reason }
      guard facts.serialDevices.contains(where: { $0.identifier == descriptor.identifier }) else {
        return "The selected serial controller is no longer available."
      }
      return nil
    case .toggleConnection:
      return projection.connectionUnavailableReason
    case .requestPassiveProbe:
      if let reason = facts.controllerBusyReason { return reason }
      if facts.frameModeSwitchInProgress { return "Wait for the frame source switch to finish." }
      if !facts.lowerSessionAvailable { return "Native machine composition is unavailable." }
      if facts.selectedSerialDevice == nil { return "Select one serial device first." }
      return facts.foreignOperationInFlight ? "Wait for the current controller operation." : nil
    case .clearAlarm:
      return projection.alarmClearUnavailableReason
    case .toggleMotionAuthorization:
      return projection.motionAuthorizationUnavailableReason
    }
  }

  private static func sessionEstablished(_ facts: PlotterControllerSessionFacts) -> Bool {
    if facts.environment == .simulated {
      return facts.simulatedSnapshot?.session == .connected
    }
    guard facts.passiveProbe?.blockers.isEmpty == true,
      let machine = facts.machineSnapshot?.machine,
      machine.controllerState?.isRecognized == true,
      machine.stickyAmbiguity == nil
    else { return false }
    switch machine.connection {
    case .connected, .moving, .actuatingPen: return true
    case .disconnected, .connecting, .probing, .blocked: return false
    }
  }

  private static func motionAuthorized(
    _ facts: PlotterControllerSessionFacts,
    sessionEstablished: Bool
  ) -> Bool {
    if facts.environment == .simulated {
      return facts.simulatedSnapshot?.motionAuthorization == .enabled
    }
    return sessionEstablished && facts.machineSnapshot?.machine.motionGuardState == .active
  }

  private static func selectionUnavailableReason(_ facts: PlotterControllerSessionFacts) -> String? {
    if let reason = facts.controllerBusyReason { return reason }
    if facts.serialDevices.isEmpty { return "No serial controllers are available." }
    if let reason = facts.discoveryBusyReason { return reason }
    if facts.foreignOperationInFlight || facts.motionActionInProgress {
      return "Wait for the current controller operation."
    }
    return nil
  }

  private static func connectionUnavailableReason(_ facts: PlotterControllerSessionFacts) -> String? {
    if let reason = facts.controllerBusyReason { return reason }
    if facts.connectionActionInProgress {
      return "The controller connection action is already in progress."
    }
    if let reason = facts.discoveryBusyReason { return reason }
    if facts.foreignOperationInFlight || facts.motionActionInProgress {
      return "Wait for the current operation."
    }
    if facts.environment == .simulated {
      return facts.simulatedSnapshot?.currentOperation == nil
        ? nil : "Stop or finish the current simulated operation first."
    }
    if linkIsOpen(facts.machineSnapshot) { return nil }
    if !facts.lowerSessionAvailable { return "Native machine composition is unavailable." }
    return facts.selectedSerialDevice == nil ? "Select one serial device first." : nil
  }

  private static func motionAuthorizationUnavailableReason(
    _ facts: PlotterControllerSessionFacts,
    sessionEstablished: Bool,
    motionAuthorized: Bool
  ) -> String? {
    if motionAuthorized { return connectionUnavailableReason(facts) }
    if let reason = facts.controllerBusyReason { return reason }
    if facts.motionActionInProgress { return "A Motion authorization action is in progress." }
    guard sessionEstablished else {
      return facts.environment == .simulated
        ? "Connect the learning simulator first." : "Connect the selected plotter first."
    }
    if facts.environment == .simulated { return nil }
    guard let snapshot = facts.machineSnapshot else {
      return MotionRefusal.notConnected.actionableDescription
    }
    let machine = snapshot.machine
    if let ambiguity = machine.stickyAmbiguity {
      return MotionRefusal.stickyAmbiguity(ambiguity).actionableDescription
    }
    if machine.operationInFlight || snapshot.currentOperation != .idle {
      return MotionRefusal.operationInFlight.actionableDescription
    }
    guard let state = machine.controllerState, state.isRecognized else {
      return MotionRefusal.controllerStateUnknown.actionableDescription
    }
    if state.isAlarm {
      return MotionRefusal.controllerAlarm("controller is in Alarm").actionableDescription
    }
    if state != .idle { return MotionRefusal.controllerNotIdle(state).actionableDescription }
    if machine.pins.hasRelevantLimitAsserted {
      return MotionRefusal.relevantLimitAsserted(machine.pins.rawValue).actionableDescription
    }
    if machine.position == nil { return MotionRefusal.machinePositionUnknown.actionableDescription }
    return nil
  }

  private static func alarmClearUnavailableReason(
    _ facts: PlotterControllerSessionFacts,
    alarmEvidence: String?
  ) -> String? {
    if let reason = facts.controllerBusyReason { return reason }
    if facts.environment == .simulated { return "SIMULATED owns no physical controller alarm." }
    if facts.alarmClearInProgress { return "Clear Alarm is already in progress." }
    if facts.connectionActionInProgress { return "Wait for the controller connection action." }
    if facts.foreignOperationInFlight { return "Wait for the current operation before clearing the controller alarm." }
    if let ambiguity = facts.machineSnapshot?.machine.stickyAmbiguity {
      return ControllerAlarmClearRefusal.stickyAmbiguity(ambiguity).actionableDescription
    }
    guard alarmEvidence != nil else {
      return ControllerAlarmClearRefusal.noCurrentAlarmEvidence.actionableDescription
    }
    guard let readiness = facts.machineSnapshot?.machine.controllerAlarmClearReadiness else {
      return ControllerAlarmClearRefusal.currentLimitStateUnknown(
        "no current controller snapshot"
      ).actionableDescription
    }
    switch readiness {
    case .armed: return nil
    case .blockedByAxisLimit(let pins):
      return ControllerAlarmClearRefusal.axisLimitAsserted(pins).actionableDescription
    case .limitStateUnknown:
      return ControllerAlarmClearRefusal.currentLimitStateUnknown(
        "the latest alarm probe did not establish axis-limit inputs"
      ).actionableDescription
    case .unavailable:
      return ControllerAlarmClearRefusal.noCurrentAlarmEvidence.actionableDescription
    }
  }

  private static func linkIsOpen(_ snapshot: RunInterpreterSnapshot?) -> Bool {
    guard let connection = snapshot?.machine.connection else { return false }
    switch connection {
    case .connecting, .connected, .probing, .moving, .actuatingPen: return true
    case .disconnected, .blocked: return false
    }
  }

  private static func connectionActionTitle(_ facts: PlotterControllerSessionFacts) -> String {
    if facts.environment == .simulated {
      return facts.simulatedSnapshot?.session == .connected ? "Disconnect" : "Connect"
    }
    return linkIsOpen(facts.machineSnapshot) ? "Disconnect" : "Connect"
  }

  private static func controllerConnectionText(
    _ facts: PlotterControllerSessionFacts,
    sessionEstablished: Bool
  ) -> String {
    if facts.environment == .simulated {
      return sessionEstablished ? "simulator connected" : "simulator disconnected"
    }
    guard facts.selectedSerialDevice != nil else { return "not selected" }
    guard let machine = facts.machineSnapshot?.machine else { return "not connected" }
    switch machine.connection {
    case .connected: return sessionEstablished ? "connected" : "not connected"
    case .disconnected: return "disconnected"
    case .connecting: return "connecting"
    case .probing: return "probing"
    case .moving: return "command in flight"
    case .actuatingPen: return "pen command in flight"
    case .blocked: return "blocked"
    }
  }

  private static func controllerStateText(_ facts: PlotterControllerSessionFacts) -> String {
    if facts.environment == .simulated {
      return facts.simulatedSnapshot?.currentOperation == nil ? "simulated Idle" : "simulated active"
    }
    return facts.machineSnapshot?.machine.controllerState?.rawValue ?? "unknown"
  }

  private static func alarmEvidence(_ facts: PlotterControllerSessionFacts) -> String? {
    guard facts.environment == .live else { return nil }
    return facts.machineSnapshot?.machine.blockers.compactMap { blocker in
      if case .controllerAlarm(let detail) = blocker { return detail }
      return nil
    }.first
  }

  private static func controllerAttentionText(_ facts: PlotterControllerSessionFacts) -> String? {
    if let machineError = facts.machineError { return machineError }
    if let blocker = facts.machineSnapshot?.machine.blockers.first {
      return machineBlockerLabel(blocker)
    }
    return facts.machineSnapshot?.machine.lastAlarmClearOutcome.flatMap { outcome in
      outcome == .acknowledged ? nil : outcome.actionableDescription
    }
  }

  private static func controllerLimitInputsText(_ facts: PlotterControllerSessionFacts) -> String {
    guard facts.environment == .live, let machine = facts.machineSnapshot?.machine else {
      return "unknown — no LIVE controller sample"
    }
    switch machine.controllerAlarmClearReadiness {
    case .armed: return "clear — sampled Pn has no X/Y/Z"
    case .blockedByAxisLimit(let pins): return "asserted — Pn:\(pins)"
    case .limitStateUnknown: return "unknown — Connect to resample"
    case .unavailable:
      guard let status = machine.lastProbe?.latestStatusReport else {
        return "unknown — Connect to sample"
      }
      return status.controllerPins.hasAxisLimitAsserted
        ? "asserted — Pn:\(status.controllerPins.rawValue)"
        : "clear — sampled Pn has no X/Y/Z"
    }
  }

  private static func controllerAlarmUnlockReadinessText(
    _ facts: PlotterControllerSessionFacts
  ) -> String {
    guard facts.environment == .live,
      let readiness = facts.machineSnapshot?.machine.controllerAlarmClearReadiness
    else { return "not armed — no LIVE controller" }
    switch readiness {
    case .armed: return "armed — manual clear available"
    case .blockedByAxisLimit(let pins): return "blocked — Pn:\(pins) is physically asserted"
    case .limitStateUnknown: return "not armed — limit inputs unknown"
    case .unavailable: return "not armed — no current alarm"
    }
  }

  private static func motorPowerText(_ facts: PlotterControllerSessionFacts) -> String {
    if facts.environment == .simulated { return "not present — nonphysical simulator" }
    guard facts.machineSnapshot?.machine.connection == .connected else { return "unverified" }
    return "not reported by controller"
  }

  private static func currentOperationText(_ facts: PlotterControllerSessionFacts) -> String {
    if facts.environment == .simulated {
      guard let operation = facts.simulatedSnapshot?.currentOperation else { return "simulated idle" }
      switch operation.kind {
      case .manualJog: return "simulated manual jog"
      case .boundary: return "simulated Boundary Discovery motion"
      case .drawing: return "simulated drawing stroke"
      }
    }
    guard let operation = facts.machineSnapshot?.currentOperation else { return "none" }
    switch operation {
    case .idle: return "idle"
    case .passiveProbe: return "controller inspection"
    case .alarmClear: return "clearing controller alarm"
    case .relativeJog: return "relative jog"
    case .boundaryMotion: return "Boundary Discovery motion"
    case .drawingStroke: return "single drawing stroke"
    case .drawingPlan: return "drawing execution plan"
    case .penActuation(let command): return "pen \(command.rawValue)"
    }
  }

  private static func machinePositionText(_ facts: PlotterControllerSessionFacts) -> String {
    if facts.environment == .simulated, let position = facts.simulatedSnapshot?.mpos {
      return String(format: "simulated X %.3f   Y %.3f", position.xMM, position.yMM)
    }
    guard let position = facts.machineSnapshot?.machine.position else { return "unknown" }
    return String(format: "X %.3f   Y %.3f", position.point.x, position.point.y)
  }

  private static func lastMotionOutcomeText(_ facts: PlotterControllerSessionFacts) -> String {
    if let drawing = facts.machineSnapshot?.lastDrawingStrokeOutcome {
      switch drawing {
      case .completed(let evidence):
        return String(
          format: "drawing completed at X %.3f Y %.3f",
          evidence.finalPosition.point.x,
          evidence.finalPosition.point.y
        )
      case .cancelled(let evidence, let penRaiseOutcome):
        return String(
          format: "drawing stopped at X %.3f Y %.3f; Pen Up: %@",
          evidence.finalPosition.point.x,
          evidence.finalPosition.point.y,
          String(describing: penRaiseOutcome)
        )
      case .refused(let refusal): return "drawing refused: \(refusal.actionableDescription)"
      case .ambiguous(let ambiguity):
        return "drawing ambiguous: \(ambiguity.actionableDescription)"
      }
    }
    guard let outcome = facts.machineSnapshot?.lastMotionOutcome else { return "none" }
    switch outcome {
    case .refused(let refusal): return "refused: \(refusal.actionableDescription)"
    case .acceptedThenCompleted(let position):
      return String(
        format: "completed at X %.3f Y %.3f",
        position.point.x,
        position.point.y
      )
    case .cancelled(let position):
      return String(
        format: "cancelled at X %.3f Y %.3f",
        position.point.x,
        position.point.y
      )
    case .ambiguous(let ambiguity): return "ambiguous: \(ambiguity.actionableDescription)"
    }
  }

  private static func lastPenOutcomeText(_ facts: PlotterControllerSessionFacts) -> String {
    if facts.environment == .simulated, let pose = facts.simulatedSnapshot?.penPose {
      return "simulated \(pose.rawValue); not physical evidence"
    }
    guard let outcome = facts.machineSnapshot?.lastPenOutcome else { return "none" }
    switch outcome {
    case .refused(let refusal): return "refused: \(refusal.actionableDescription)"
    case .commandedAndSettled(let command, let state):
      return "\(command.rawValue) acknowledged; commanded \(state.rawValue)"
    case .ambiguous(let ambiguity): return "ambiguous: \(ambiguity.actionableDescription)"
    }
  }
}

actor PlotterControllerSessionRuntime {
  private let lowerSession: (any PlotterMachineSession)?
  private let simulatedSession: SimulatedLearningRuntime
  private let discoverSerialDevices: @Sendable () -> [MachineLinkDescriptor]
  private let awaitEffectAdmission: @Sendable () async -> Void
  private var admissionClosed = false
  private var activeTask: Task<PlotterControllerSessionEffectResult?, Never>?
  private var activeOperationID: UUID?

  init(
    lowerSession: (any PlotterMachineSession)?,
    simulatedSession: SimulatedLearningRuntime,
    discoverSerialDevices: @escaping @Sendable () -> [MachineLinkDescriptor],
    awaitEffectAdmission: @escaping @Sendable () async -> Void = {}
  ) {
    self.lowerSession = lowerSession
    self.simulatedSession = simulatedSession
    self.discoverSerialDevices = discoverSerialDevices
    self.awaitEffectAdmission = awaitEffectAdmission
  }

  func submit(
    _ request: PlotterControllerSessionRequest,
    facts: PlotterControllerSessionFacts
  ) async -> PlotterControllerSessionDisposition {
    guard !admissionClosed, request.reference == facts.reference else {
      return .refused("The controller-session projection changed; use the current action.")
    }
    if let refusal = PlotterControllerSessionRules.refusal(for: request.intent, facts: facts) {
      return .refused(refusal)
    }
    guard activeTask == nil else { return .refused("A controller-session action is in progress.") }
    let operationID = UUID()
    let lowerSession = lowerSession
    let simulatedSession = simulatedSession
    let discoverSerialDevices = discoverSerialDevices
    let awaitEffectAdmission = awaitEffectAdmission
    let intent = request.intent
    let task = Task { () -> PlotterControllerSessionEffectResult? in
      await awaitEffectAdmission()
      guard !Task.isCancelled else { return nil }
      return await Self.execute(
        intent,
        facts: facts,
        lowerSession: lowerSession,
        simulatedSession: simulatedSession,
        discoverSerialDevices: discoverSerialDevices
      )
    }
    activeOperationID = operationID
    activeTask = task
    let result = await task.value
    guard activeOperationID == operationID else { return .cancelled }
    activeTask = nil
    activeOperationID = nil
    guard !admissionClosed, let result else { return .cancelled }
    return .completed(result)
  }

  func shutdown() async {
    guard !admissionClosed else { return }
    admissionClosed = true
    let task = activeTask
    task?.cancel()
    _ = await task?.value
    activeTask = nil
    activeOperationID = nil
    await lowerSession?.disconnect()
  }

  private static func execute(
    _ intent: PlotterControllerSessionIntent,
    facts: PlotterControllerSessionFacts,
    lowerSession: (any PlotterMachineSession)?,
    simulatedSession: SimulatedLearningRuntime,
    discoverSerialDevices: @Sendable () -> [MachineLinkDescriptor]
  ) async -> PlotterControllerSessionEffectResult? {
    guard !Task.isCancelled else { return nil }
    switch intent {
    case .refreshSerialDevices:
      let devices = discoverSerialDevices()
      let retires = facts.selectedSerialDevice.map { selected in
        !devices.contains(where: { $0.identifier == selected.identifier })
      } ?? false
      if retires {
        guard !Task.isCancelled else { return nil }
        await lowerSession?.disconnect()
        guard !Task.isCancelled else { return nil }
      }
      return .discovered(devices, retiredLowerSession: retires)
    case .selectSerialDevice(let descriptor):
      let retires = facts.selectedSerialDevice?.identifier != descriptor.identifier
        && facts.machineSnapshot != nil
      if retires {
        guard !Task.isCancelled else { return nil }
        await lowerSession?.disconnect()
        guard !Task.isCancelled else { return nil }
      }
      return .selected(descriptor, retiredLowerSession: retires)
    case .toggleConnection:
      if facts.environment == .simulated {
        let wasConnected = facts.simulatedSnapshot?.session == .connected
        guard !Task.isCancelled else { return nil }
        let response = wasConnected
          ? await simulatedSession.disconnect() : await simulatedSession.connect()
        guard !Task.isCancelled else { return nil }
        switch response.result {
        case .success(let snapshot):
          return .simulated(
            snapshot,
            action: wasConnected ? "Disconnect simulator" : "Connect simulator",
            refusal: nil
          )
        case .failure(let refusal):
          guard !Task.isCancelled else { return nil }
          let snapshot = await simulatedSession.snapshot()
          guard !Task.isCancelled else { return nil }
          return .simulated(
            snapshot,
            action: wasConnected ? "Disconnect simulator" : "Connect simulator",
            refusal: String(describing: refusal)
          )
        }
      }
      guard let lowerSession else { return nil }
      if PlotterControllerSessionRules.project(facts).connectionActionTitle == "Disconnect" {
        guard !Task.isCancelled else { return nil }
        await lowerSession.disconnect()
        return Task.isCancelled ? nil : .liveDisconnected
      }
      guard let descriptor = facts.selectedSerialDevice else { return nil }
      do {
        guard !Task.isCancelled else { return nil }
        _ = try await lowerSession.select(descriptor)
        guard !Task.isCancelled else { return nil }
        let probe = try await lowerSession.requestPassiveProbe()
        guard !Task.isCancelled else { return nil }
        let snapshot = await lowerSession.snapshot()
        return Task.isCancelled ? nil : .liveSession(snapshot: snapshot, probe: probe, error: nil)
      } catch {
        guard !Task.isCancelled else { return nil }
        let snapshot = await lowerSession.snapshot()
        return Task.isCancelled ? nil : .liveSession(
          snapshot: snapshot,
          probe: nil,
          error: error.localizedDescription
        )
      }
    case .requestPassiveProbe:
      guard let lowerSession else { return nil }
      do {
        guard !Task.isCancelled else { return nil }
        let probe = try await lowerSession.requestPassiveProbe()
        guard !Task.isCancelled else { return nil }
        let snapshot = await lowerSession.snapshot()
        return Task.isCancelled ? nil : .liveSession(snapshot: snapshot, probe: probe, error: nil)
      } catch {
        guard !Task.isCancelled else { return nil }
        let snapshot = await lowerSession.snapshot()
        return Task.isCancelled ? nil : .liveSession(
          snapshot: snapshot,
          probe: nil,
          error: error.localizedDescription
        )
      }
    case .clearAlarm:
      guard let lowerSession else { return nil }
      guard !Task.isCancelled else { return nil }
      let alarm = await lowerSession.requestControllerAlarmClear()
      guard !Task.isCancelled else { return nil }
      guard alarm == .acknowledged else {
        let snapshot = await lowerSession.snapshot()
        guard !Task.isCancelled else { return nil }
        return .liveSession(
          snapshot: snapshot,
          probe: nil,
          error: alarm.actionableDescription
        )
      }
      do {
        guard !Task.isCancelled else { return nil }
        let probe = try await lowerSession.requestPassiveProbe()
        guard !Task.isCancelled else { return nil }
        let snapshot = await lowerSession.snapshot()
        return Task.isCancelled ? nil : .liveSession(snapshot: snapshot, probe: probe, error: nil)
      } catch {
        guard !Task.isCancelled else { return nil }
        let snapshot = await lowerSession.snapshot()
        return Task.isCancelled ? nil : .liveSession(
          snapshot: snapshot,
          probe: nil,
          error: error.localizedDescription
        )
      }
    case .toggleMotionAuthorization:
      if facts.environment == .simulated {
        let wasEnabled = facts.simulatedSnapshot?.motionAuthorization == .enabled
        guard !Task.isCancelled else { return nil }
        let response = wasEnabled
          ? await simulatedSession.disableMotion() : await simulatedSession.enableMotion()
        guard !Task.isCancelled else { return nil }
        switch response.result {
        case .success(let snapshot):
          return .simulated(
            snapshot,
            action: wasEnabled ? "Disable simulated motion" : "Enable simulated motion",
            refusal: nil
          )
        case .failure(let refusal):
          guard !Task.isCancelled else { return nil }
          let snapshot = await simulatedSession.snapshot()
          guard !Task.isCancelled else { return nil }
          return .simulated(
            snapshot,
            action: wasEnabled ? "Disable simulated motion" : "Enable simulated motion",
            refusal: String(describing: refusal)
          )
        }
      }
      guard let lowerSession else { return nil }
      let enabled = PlotterControllerSessionRules.project(facts).motionAuthorized
      if enabled {
        guard !Task.isCancelled else { return nil }
        await lowerSession.deactivateMotionGuard()
        guard !Task.isCancelled else { return nil }
        let snapshot = await lowerSession.snapshot()
        return Task.isCancelled ? nil : .liveSession(snapshot: snapshot, probe: facts.passiveProbe, error: nil)
      }
      guard !Task.isCancelled else { return nil }
      let outcome = await lowerSession.activateMotionGuard()
      guard !Task.isCancelled else { return nil }
      let snapshot = await lowerSession.snapshot()
      switch outcome {
      case .activated:
        return Task.isCancelled ? nil : .liveSession(snapshot: snapshot, probe: facts.passiveProbe, error: nil)
      case .refused(let refusal):
        return Task.isCancelled ? nil : .liveSession(
          snapshot: snapshot,
          probe: facts.passiveProbe,
          error: refusal.actionableDescription
        )
      }
    }
  }
}
