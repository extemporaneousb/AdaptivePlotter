import Foundation
import OSLog
import PlotterRuntime

enum MachineSessionComposition {
  private static let session = PersistentMachineSession()

  static let actions = OperatorWorkspace.MachineActions(
    select: { descriptor in
      try await session.select(descriptor)
    },
    snapshot: {
      await session.snapshot()
    },
    requestPassiveProbe: {
      try await session.requestPassiveProbe()
    },
    requestControllerAlarmClear: {
      await session.requestControllerAlarmClear()
    },
    activateMotionGuard: {
      await session.activateMotionGuard()
    },
    beginRelativeJog: { request in
      await session.beginRelativeJog(request)
    },
    beginDrawingStroke: { request in
      await session.beginDrawingStroke(request)
    },
    requestPenActuation: { command, profile in
      await session.requestPenActuation(command, profile: profile)
    },
    beginBoundaryMotion: { request, renewalPlanner in
      await session.beginBoundaryMotion(request, renewalPlanner: renewalPlanner)
    },
    requestJogCancel: { intent in
      await session.requestJogCancel(intent)
    },
    disconnect: {
      await session.disconnect()
    }
  )

  static let workflowTelemetryActions = OperatorWorkspace.WorkflowTelemetryActions(
    record: { event in
      await session.recordWorkflowTelemetry(event)
    }
  )
}

private enum MachineSessionCompositionError: LocalizedError {
  case noSelectedController

  var errorDescription: String? {
    "Select one serial controller before requesting an operation."
  }
}

/// Owns one controller, interpreter, serial link, and best-effort journal for
/// the explicitly selected device. Repeated probes and jogs reuse that session.
private actor PersistentMachineSession {
  private static let logger = Logger(
    subsystem: "com.adaptiveplotter.app",
    category: "workflow-telemetry"
  )

  private var selectedDescriptor: MachineLinkDescriptor?
  private var interpreter: RunInterpreter?
  private var ledger: RunLedger?
  private var ledgerRunID: LedgerRunID?
  private var clock: (any RuntimeClock)?

  func select(_ descriptor: MachineLinkDescriptor) async throws -> RunInterpreterSnapshot {
    if selectedDescriptor == descriptor, let interpreter {
      return await interpreter.snapshot()
    }

    await interpreter?.disconnect()
    await ledger?.close()
    selectedDescriptor = nil
    interpreter = nil
    ledger = nil
    ledgerRunID = nil
    clock = nil

    let clock = SystemRuntimeClock()
    let diagnostic = await makeBestEffortLedger(clock: clock)
    let controller = try MachineController.bsdSerial(
      descriptor: descriptor,
      ledger: diagnostic.ledger,
      runID: diagnostic.runID,
      clock: clock
    )
    let newInterpreter = RunInterpreter(machineController: controller)
    selectedDescriptor = descriptor
    interpreter = newInterpreter
    ledger = diagnostic.ledger
    ledgerRunID = diagnostic.runID
    self.clock = clock
    return await newInterpreter.snapshot()
  }

  func snapshot() async -> RunInterpreterSnapshot? {
    await interpreter?.snapshot()
  }

  func requestPassiveProbe() async throws -> PassiveProbeResult {
    guard let interpreter else { throw MachineSessionCompositionError.noSelectedController }
    return try await interpreter.requestPassiveProbe()
  }

  func requestControllerAlarmClear() async -> ControllerAlarmClearOutcome {
    guard let interpreter else { return .refused(.noSerialDeviceSelected) }
    return await interpreter.requestControllerAlarmClear()
  }

  func activateMotionGuard() async -> MotionGuardActivationOutcome {
    guard let interpreter else { return .refused(.noSerialDeviceSelected) }
    return await interpreter.activateMotionGuard()
  }

  func beginRelativeJog(_ request: RelativeJogRequest) async -> RelativeJogAdmission {
    guard let interpreter else {
      return .rejected(.refused(.noSerialDeviceSelected))
    }
    return await interpreter.beginRelativeJog(request)
  }

  func beginDrawingStroke(_ request: DrawingStrokeRequest) async -> DrawingStrokeAdmission {
    guard let interpreter else {
      return .rejected(.refused(.noSerialDeviceSelected))
    }
    return await interpreter.beginDrawingStroke(request)
  }

  func beginBoundaryMotion(
    _ request: BoundaryMotionRequest,
    renewalPlanner: BoundaryMotionRenewalPlanner?
  ) async -> BoundaryMotionAdmission {
    guard let interpreter else {
      return .rejected(
        .needsAttention(
          ownerID: request.ownerID,
          terminal: .refusal(.noSerialDeviceSelected)
        )
      )
    }
    return await interpreter.beginBoundaryMotion(request, renewalPlanner: renewalPlanner)
  }

  func requestJogCancel(_ intent: JogCancelIntent) async -> JogCancelOutcome {
    guard let interpreter else { return .refused(.noSerialDeviceSelected) }
    return await interpreter.requestJogCancel(intent)
  }

  func requestPenActuation(
    _ command: PenCommand,
    profile: PenActuationProfile
  ) async -> PenOutcome {
    guard let interpreter else { return .refused(.noSerialDeviceSelected) }
    return await interpreter.requestPenActuation(command, profile: profile)
  }

  func disconnect() async {
    await interpreter?.disconnect()
    await ledger?.close()
    selectedDescriptor = nil
    interpreter = nil
    ledger = nil
    ledgerRunID = nil
    clock = nil
  }

  func recordWorkflowTelemetry(_ event: WorkflowTelemetryEvent) async {
    guard let ledger, let runID = ledgerRunID, let clock else {
      Self.logger.notice(
        "Workflow telemetry unavailable for \(event.operation.rawValue, privacy: .public) \(event.phase.rawValue, privacy: .public)"
      )
      return
    }
    do {
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.sortedKeys]
      let payload = try encoder.encode(event)
      _ = try await ledger.appendEvent(
        runID: runID,
        timestamp: RuntimeTimestamp(monotonicNanoseconds: clock.nowNanoseconds()),
        kind: "workflow.\(event.operation.rawValue).\(event.phase.rawValue)",
        schemaVersion: WorkflowTelemetryEvent.schemaVersion,
        payload: payload
      )
    } catch {
      Self.logger.error(
        "Workflow telemetry write failed for \(event.operation.rawValue, privacy: .public) \(event.phase.rawValue, privacy: .public): \(String(describing: error), privacy: .public)"
      )
    }
  }

  private func makeBestEffortLedger(
    clock: any RuntimeClock
  ) async -> (ledger: RunLedger?, runID: LedgerRunID?) {
    let fileManager = FileManager.default
    guard
      let applicationSupport = try? fileManager.url(
        for: .applicationSupportDirectory,
        in: .userDomainMask,
        appropriateFor: nil,
        create: true
      )
    else {
      return (nil, nil)
    }
    let ledgerURL =
      applicationSupport
      .appendingPathComponent("AdaptivePlotter", isDirectory: true)
      .appendingPathComponent("MachineSessions", isDirectory: true)
      .appendingPathComponent("session-\(UUID().uuidString.lowercased())")
      .appendingPathExtension("sqlite")
    do {
      try fileManager.createDirectory(
        at: ledgerURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
      )
      let ledger = try RunLedger(databaseURL: ledgerURL)
      let runID = try await ledger.createRun(
        buildID: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
          ?? "swiftpm-local",
        createdAt: RuntimeTimestamp(monotonicNanoseconds: clock.nowNanoseconds())
      )
      return (ledger, runID)
    } catch {
      return (nil, nil)
    }
  }
}
