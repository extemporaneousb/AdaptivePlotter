import Foundation
import PlotterModel
import PlotterRuntime

enum PassiveProbeComposition {
  static let run: OperatorWorkspace.PassiveProbeRunner = { descriptor in
    let fileManager = FileManager.default
    let applicationSupport = try? fileManager.url(
      for: .applicationSupportDirectory,
      in: .userDomainMask,
      appropriateFor: nil,
      create: true
    )
    let proposedLedgerURL = applicationSupport.map {
      $0.appendingPathComponent("AdaptivePlotter", isDirectory: true)
        .appendingPathComponent("PassiveRuns", isDirectory: true)
        .appendingPathComponent("passive-\(UUID().uuidString.lowercased())")
        .appendingPathExtension("sqlite")
    }
    let clock = SystemRuntimeClock()
    var ledger: RunLedger?
    var runID: LedgerRunID?
    if let proposedLedgerURL {
      try? fileManager.createDirectory(
        at: proposedLedgerURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
      )
      do {
        let newLedger = try RunLedger(databaseURL: proposedLedgerURL)
        let newRunID = try await newLedger.createRun(
          buildID: Bundle.main.object(
            forInfoDictionaryKey: "CFBundleVersion"
          ) as? String ?? "swiftpm-prototype-unverified",
          createdAt: RuntimeTimestamp(monotonicNanoseconds: clock.nowNanoseconds())
        )
        ledger = newLedger
        runID = newRunID
      } catch {
        ledger = nil
        runID = nil
      }
    }

    let controller = try MachineController.bsdSerial(
      descriptor: descriptor,
      ledger: ledger,
      runID: runID,
      clock: clock
    )
    let interpreter = RunInterpreter(machineController: controller)
    do {
      let result = try await interpreter.requestPassiveProbe()
      await controller.disconnect()
      await ledger?.close()
      return PassiveProbeRunReceipt(
        probe: result,
        ledgerURL: ledger == nil ? nil : proposedLedgerURL
      )
    } catch {
      await controller.disconnect()
      await ledger?.close()
      throw error
    }
  }
}
