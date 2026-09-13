import Foundation
import OSLog
import PlotterEpisodeRuntime
import PlotterRuntime

/// Nominal lower-machine capability retained by `PersistentMachineSession`.
/// Upper episode runtimes depend on this protocol instead of receiving an
/// arbitrary bag of effect-producing closures.
protocol PlotterMachineSession: Actor {
  func select(_ descriptor: MachineLinkDescriptor) async throws -> RunInterpreterSnapshot
  func snapshot() async -> RunInterpreterSnapshot?
  func requestPassiveProbe() async throws -> PassiveProbeResult
  func requestControllerAlarmClear() async -> ControllerAlarmClearOutcome
  func activateMotionGuard() async -> MotionGuardActivationOutcome
  func deactivateMotionGuard() async
  func beginRelativeJog(_ request: RelativeJogRequest) async -> RelativeJogAdmission
  func beginDrawingStroke(_ request: DrawingStrokeRequest) async -> DrawingStrokeAdmission
  func beginDrawingPlan(_ request: DrawingPlanRequest) async -> DrawingPlanAdmission
  func reconcilePenActuationProfile(_ profile: PenActuationProfile) async -> Bool
  func beginPenActuation(
    _ command: PenCommand,
    profile: PenActuationProfile
  ) async -> PenActuationAdmission
  func beginBoundaryMotion(
    _ request: BoundaryMotionRequest,
    renewalPlanner: BoundaryMotionRenewalPlanner?
  ) async -> BoundaryMotionAdmission
  func requestJogCancel(_ intent: JogCancelIntent) async -> JogCancelOutcome
  @discardableResult
  func recordWorkflowTelemetry(_ event: WorkflowTelemetryEvent) async -> Bool
  func disconnect() async
}

struct PlotterApplicationRuntimeDrawingRunInterpreterPort: PlotterDrawingRunInterpreterPort {
  let session: any PlotterMachineSession

  func snapshot() async -> RunInterpreterSnapshot? {
    await session.snapshot()
  }

  func normalizePenUp(profile: PenActuationProfile) async -> PenOutcome {
    await PlotterManualMotionComposition.settleNativePenCommand(
      using: session,
      command: .raise,
      profile: profile
    )
  }

  func travelToObservationPosition(_ request: RelativeJogRequest) async -> MotionOutcome {
    switch await PlotterManualMotionComposition.beginNativeRelativeMotion(
      using: session,
      request: request
    ) {
    case .admitted(let operation):
      return await operation.outcome()
    case .rejected(let outcome):
      return outcome
    }
  }

  func beginDrawingPlan(_ request: DrawingPlanRequest) async -> DrawingPlanAdmission {
    await session.beginDrawingPlan(request)
  }

  func requestStop(_ intent: JogCancelIntent) async -> JogCancelOutcome {
    await session.requestJogCancel(intent)
  }
}

enum MachineSessionComposition {
  static let session: any PlotterMachineSession = PersistentMachineSession()
  static let residualEffectPort: any PlotterApplicationResidualEffectPort =
    MachineSessionResidualEffectAdapter(session: session)
}

private struct MachineSessionResidualEffectAdapter: PlotterApplicationResidualEffectPort {
  let session: any PlotterMachineSession

  func recordWorkflowTelemetry(_ event: WorkflowTelemetryEvent) async {
    _ = await session.recordWorkflowTelemetry(event)
  }
}

private enum MachineSessionCompositionError: LocalizedError {
  case noSelectedController

  var errorDescription: String? {
    "Select one serial controller before requesting an operation."
  }
}

/// Bounds the best-effort controller journal in its existing storage owner.
/// A session includes its SQLite database and any sidecar files sharing the
/// same `session-*.sqlite` stem. Unknown files are never claimed or removed.
struct MachineSessionRetentionPolicy: Sendable {
  static let production = MachineSessionRetentionPolicy(
    maximumSessionCount: 10,
    maximumTotalBytes: 50 * 1_024 * 1_024
  )

  let maximumSessionCount: Int
  let maximumTotalBytes: Int

  init(maximumSessionCount: Int, maximumTotalBytes: Int) {
    precondition(maximumSessionCount >= 0)
    precondition(maximumTotalBytes >= 0)
    self.maximumSessionCount = maximumSessionCount
    self.maximumTotalBytes = maximumTotalBytes
  }

  func enforce(
    in directory: URL,
    fileManager: FileManager = .default
  ) throws {
    for url in try urlsToRemove(in: directory, fileManager: fileManager) {
      try fileManager.removeItem(at: url)
    }
  }

  func urlsToRemove(
    in directory: URL,
    fileManager: FileManager = .default
  ) throws -> [URL] {
    struct SessionGroup {
      let stem: String
      let urls: [URL]
      let totalBytes: Int
      let mostRecentModification: Date
    }

    let resourceKeys: Set<URLResourceKey> = [
      .contentModificationDateKey,
      .fileSizeKey,
      .isRegularFileKey,
    ]
    let urls = try fileManager.contentsOfDirectory(
      at: directory,
      includingPropertiesForKeys: Array(resourceKeys),
      options: [.skipsHiddenFiles]
    )
    let recognized = try urls.compactMap { url -> (String, URL, Int, Date)? in
      let name = url.lastPathComponent
      guard name.hasPrefix("session-"),
        let sqliteRange = name.range(of: ".sqlite")
      else { return nil }
      let suffix = name[sqliteRange.upperBound...]
      guard suffix.isEmpty || suffix == "-shm" || suffix == "-wal" || suffix == "-journal"
      else { return nil }
      let values = try url.resourceValues(forKeys: resourceKeys)
      guard values.isRegularFile == true else { return nil }
      let stem = String(name[..<sqliteRange.upperBound])
      return (
        stem,
        url,
        max(0, values.fileSize ?? 0),
        values.contentModificationDate ?? .distantPast
      )
    }
    let groups = Dictionary(grouping: recognized, by: \.0).map { stem, files in
      SessionGroup(
        stem: stem,
        urls: files.map(\.1),
        totalBytes: files.reduce(0) { $0 + $1.2 },
        mostRecentModification: files.map(\.3).max() ?? .distantPast
      )
    }.sorted {
      if $0.mostRecentModification != $1.mostRecentModification {
        return $0.mostRecentModification > $1.mostRecentModification
      }
      return $0.stem > $1.stem
    }

    var retainedCount = 0
    var retainedBytes = 0
    var removals: [URL] = []
    for group in groups {
      let fitsCount = retainedCount < maximumSessionCount
      let fitsBytes = group.totalBytes <= maximumTotalBytes - retainedBytes
      if fitsCount && fitsBytes {
        retainedCount += 1
        retainedBytes += group.totalBytes
      } else {
        removals.append(contentsOf: group.urls)
      }
    }
    return removals.sorted { $0.lastPathComponent < $1.lastPathComponent }
  }
}

/// Owns one controller, interpreter, serial link, and best-effort journal for
/// the explicitly selected device. Repeated probes and jogs reuse that session.
actor PersistentMachineSession: PlotterMachineSession {
  private static let logger = Logger(
    subsystem: "com.adaptiveplotter.app",
    category: "workflow-telemetry"
  )

  private var selectedDescriptor: MachineLinkDescriptor?
  private var interpreter: RunInterpreter?
  private var ledger: RunLedger?

  init(
    selectedDescriptor: MachineLinkDescriptor? = nil,
    interpreter: RunInterpreter? = nil,
    ledger: RunLedger? = nil
  ) {
    self.selectedDescriptor = selectedDescriptor
    self.interpreter = interpreter
    self.ledger = ledger
  }

  func select(_ descriptor: MachineLinkDescriptor) async throws -> RunInterpreterSnapshot {
    if selectedDescriptor == descriptor, let interpreter {
      return await interpreter.snapshot()
    }

    let retiringInterpreter = interpreter
    let retiringLedger = ledger
    selectedDescriptor = nil
    interpreter = nil
    ledger = nil
    await retiringInterpreter?.disconnect()
    await retiringLedger?.close()

    let clock = SystemRuntimeClock()
    let diagnostic = await makeBestEffortLedger(clock: clock)
    let link = RecordingMachineLink(
      underlying: try MachineController.bsdSerialLink(
        descriptor: descriptor,
        clock: clock
      ),
      router: PlotterManualMotionComposition.controllerRecordingRouter,
      clock: clock
    )
    let controller = MachineController(
      link: link,
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

  func requestControllerAlarmClear() async -> ControllerAlarmClearOutcome {
    guard let interpreter else { return .refused(.noSerialDeviceSelected) }
    return await interpreter.requestControllerAlarmClear()
  }

  func activateMotionGuard() async -> MotionGuardActivationOutcome {
    guard let interpreter else { return .refused(.noSerialDeviceSelected) }
    return await interpreter.activateMotionGuard()
  }

  func deactivateMotionGuard() async {
    await interpreter?.deactivateMotionGuard()
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

  func beginDrawingPlan(_ request: DrawingPlanRequest) async -> DrawingPlanAdmission {
    guard let interpreter else {
      let progress = DrawingPlanProgressSnapshot(
        operationID: request.operationID,
        planRevisionID: request.plan.revisionID,
        plannedStrokeCount: request.plan.strokes.count,
        plannedSegmentCount: request.plan.strokes.reduce(0) {
          $0 + max(0, $1.path.points.count - 1)
        },
        commandedStrokeCount: 0,
        controllerCompletedStrokeCount: 0,
        submittedSegmentCount: 0,
        controllerCompletedSegmentCount: 0,
        completedStrokeIDs: [],
        completedCheckpointIDs: [],
        activeStrokeID: nil,
        activeSegmentIndex: nil
      )
      return .rejected(.refused(progress: progress, reason: .notConnected))
    }
    return await interpreter.beginDrawingPlan(request)
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

  func reconcilePenActuationProfile(_ profile: PenActuationProfile) async -> Bool {
    // An absent controller has no commanded pen state to invalidate.
    guard let interpreter else { return true }
    return await interpreter.reconcilePenActuationProfile(profile)
  }

  func beginPenActuation(
    _ command: PenCommand,
    profile: PenActuationProfile
  ) async -> PenActuationAdmission {
    guard let interpreter else { return .rejected(.refused(.noSerialDeviceSelected)) }
    return await interpreter.beginPenActuation(command, profile: profile)
  }

  func disconnect() async {
    let retiringInterpreter = interpreter
    let retiringLedger = ledger
    selectedDescriptor = nil
    interpreter = nil
    ledger = nil
    await retiringInterpreter?.disconnect()
    await retiringLedger?.close()
  }

  @discardableResult
  func recordWorkflowTelemetry(_ event: WorkflowTelemetryEvent) async -> Bool {
    guard let interpreter else {
      Self.logger.notice(
        "Workflow telemetry unavailable for \(event.operation.rawValue, privacy: .public) \(event.phase.rawValue, privacy: .public)"
      )
      return false
    }
    return await interpreter.enqueueWorkflowTelemetry(event)
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
    let sessionDirectory =
      applicationSupport
      .appendingPathComponent("AdaptivePlotter", isDirectory: true)
      .appendingPathComponent("MachineSessions", isDirectory: true)
    let ledgerURL =
      sessionDirectory
      .appendingPathComponent("session-\(UUID().uuidString.lowercased())")
      .appendingPathExtension("sqlite")
    do {
      try fileManager.createDirectory(
        at: sessionDirectory,
        withIntermediateDirectories: true
      )
      let ledger = try RunLedger(databaseURL: ledgerURL)
      // Include the newly created database in the same retention decision.
      // Enforcing before creation would leave maximumSessionCount + 1 groups
      // immediately after every connection.
      do {
        try MachineSessionRetentionPolicy.production.enforce(
          in: sessionDirectory,
          fileManager: fileManager
        )
      } catch {
        Self.logger.error(
          "Machine-session retention failed: \(String(describing: error), privacy: .public)"
        )
      }
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
