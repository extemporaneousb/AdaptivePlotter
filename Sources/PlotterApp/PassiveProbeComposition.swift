import Foundation
import PlotterModel
import PlotterRuntime

enum PassiveProbeComposition {
  static let run: OperatorWorkspace.PassiveProbeRunner = { descriptor in
    let fileManager = FileManager.default
    let applicationSupport = try fileManager.url(
      for: .applicationSupportDirectory,
      in: .userDomainMask,
      appropriateFor: nil,
      create: true
    )
    let runDirectory =
      applicationSupport
      .appendingPathComponent("AdaptivePlotter", isDirectory: true)
      .appendingPathComponent("PassiveRuns", isDirectory: true)
    try fileManager.createDirectory(
      at: runDirectory,
      withIntermediateDirectories: true
    )

    try await requireRecoveryClear(in: runDirectory)

    let ledgerURL =
      runDirectory
      .appendingPathComponent("passive-\(UUID().uuidString.lowercased())")
      .appendingPathExtension("sqlite")
    let clock = SystemRuntimeClock()
    let ledger = try RunLedger(databaseURL: ledgerURL)

    do {
      let runID = try await ledger.createRun(
        buildID: Bundle.main.object(
          forInfoDictionaryKey: "CFBundleVersion"
        ) as? String ?? "swiftpm-prototype-unverified",
        createdAt: RuntimeTimestamp(monotonicNanoseconds: clock.nowNanoseconds())
      )
      let controller = try MachineController.bsdSerial(
        descriptor: descriptor,
        ledger: ledger,
        runID: runID,
        clock: clock
      )
      let initialAuthority = try ExecutionAuthority(
        allowed: false,
        operation: nil,
        planID: nil,
        modelID: nil,
        stateEstimateID: nil,
        fixedSafetyPolicyID: SafetyPolicyID(),
        evidence: [],
        limits: try AuthorityLimits(
          maximumFeed: 0,
          maximumDistance: 0,
          maximumCommandHorizonNanoseconds: 0
        ),
        blockers: [
          try RunBlocker(
            code: "machine.passive_probe_not_run",
            summary: "Passive controller interrogation has not completed."
          )
        ]
      )
      let interpreter = RunInterpreter(
        machineController: controller,
        ledger: ledger,
        runID: runID,
        initialAuthority: initialAuthority
      )
      do {
        try await interpreter.reconcileRecordedCommandIntents()
        let result = try await interpreter.requestPassiveProbe()
        let authority = await interpreter.snapshot()
        await controller.disconnect()
        await ledger.close()
        return PassiveProbeRunReceipt(
          probe: result,
          completionAuthority: authority,
          ledgerURL: ledgerURL
        )
      } catch {
        await controller.disconnect()
        throw error
      }
    } catch {
      await ledger.close()
      throw error
    }
  }

  static func requireRecoveryClear(in runDirectory: URL) async throws {
    let recovery = await PassiveRunRecoveryScanner.scan(directoryURL: runDirectory)
    guard !recovery.blocksPoweredProbe else {
      throw PassiveRunRecoveryRequiredError(scan: recovery)
    }
  }
}
