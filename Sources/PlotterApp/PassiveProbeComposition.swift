import Foundation
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
    activateMotionGuard: {
      await session.activateMotionGuard()
    },
    requestRelativeJog: { request in
      await session.requestRelativeJog(request)
    },
    requestObservedJog: { request, observe in
      await session.requestObservedJog(request, observe: observe)
    },
    requestPenActuation: { command in
      await session.requestPenActuation(command)
    },
    requestJogCancel: {
      await session.requestJogCancel()
    },
    disconnect: {
      await session.disconnect()
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
  private var selectedDescriptor: MachineLinkDescriptor?
  private var interpreter: RunInterpreter?
  private var ledger: RunLedger?

  func select(_ descriptor: MachineLinkDescriptor) async throws -> RunInterpreterSnapshot {
    if selectedDescriptor == descriptor, let interpreter {
      return await interpreter.snapshot()
    }

    await interpreter?.disconnect()
    await ledger?.close()
    selectedDescriptor = nil
    interpreter = nil
    ledger = nil

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
    return await newInterpreter.snapshot()
  }

  func snapshot() async -> RunInterpreterSnapshot? {
    await interpreter?.snapshot()
  }

  func requestPassiveProbe() async throws -> PassiveProbeResult {
    guard let interpreter else { throw MachineSessionCompositionError.noSelectedController }
    return try await interpreter.requestPassiveProbe()
  }

  func activateMotionGuard() async -> MotionGuardActivationOutcome {
    guard let interpreter else { return .refused(.noSerialDeviceSelected) }
    return await interpreter.activateMotionGuard()
  }

  func requestRelativeJog(_ request: RelativeJogRequest) async -> MotionOutcome {
    guard let interpreter else { return .refused(.noSerialDeviceSelected) }
    return await interpreter.requestRelativeJog(request)
  }

  func requestJogCancel() async -> JogCancelOutcome {
    guard let interpreter else { return .refused(.noSerialDeviceSelected) }
    return await interpreter.requestJogCancel()
  }

  func requestObservedJog(
    _ request: PhysicalJogObservationRequest,
    observe: @Sendable (PhysicalObservationPhase, UInt64) async
      -> Result<VisibleToolFrameObservation, PhysicalJogObservationFailure>
  ) async -> PhysicalJogObservationOutcome {
    guard let interpreter else {
      let motionOutcome = MotionOutcome.refused(.noSerialDeviceSelected)
      return .notRecorded(
        motionOutcome: motionOutcome,
        failure: .motionNotCompleted(motionOutcome)
      )
    }
    return await interpreter.requestObservedJog(request, observe: observe)
  }

  func requestPenActuation(_ command: PenCommand) async -> PenOutcome {
    guard let interpreter else { return .refused(.noSerialDeviceSelected) }
    return await interpreter.requestPenActuation(command)
  }

  func disconnect() async {
    await interpreter?.disconnect()
    await ledger?.close()
    selectedDescriptor = nil
    interpreter = nil
    ledger = nil
  }

  private func makeBestEffortLedger(
    clock: any RuntimeClock
  ) async -> (ledger: RunLedger?, runID: LedgerRunID?) {
    let fileManager = FileManager.default
    guard let applicationSupport = try? fileManager.url(
      for: .applicationSupportDirectory,
      in: .userDomainMask,
      appropriateFor: nil,
      create: true
    ) else {
      return (nil, nil)
    }
    let ledgerURL = applicationSupport
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
