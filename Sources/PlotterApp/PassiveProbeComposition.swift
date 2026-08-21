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
    deactivateMotionGuard: {
      await session.deactivateMotionGuard()
    },
    beginRelativeJog: { request in
      await session.beginRelativeJog(request)
    },
    beginDrawingStroke: { request in
      await session.beginDrawingStroke(request)
    },
    beginDrawingPlan: { request in
      await session.beginDrawingPlan(request)
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
