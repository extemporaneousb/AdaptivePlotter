import Foundation

public enum PassiveRunRecoveryIssue: Hashable, Sendable {
  case directoryInspectionFailed(directoryURL: URL, reason: String)
  case unsafeDatabaseEntry(databaseURL: URL, reason: String)
  case databaseInspectionFailed(databaseURL: URL, reason: String)
  case integrityCheckFailed(databaseURL: URL)
  case emptyDatabase(databaseURL: URL)
  case unfinishedRun(databaseURL: URL, runID: LedgerRunID)
  case malformedRunLifecycle(databaseURL: URL, runID: LedgerRunID, reason: String)
  case unresolvedCommands(databaseURL: URL, runID: LedgerRunID, commandIDs: [UUID])

  public var summary: String {
    switch self {
    case let .directoryInspectionFailed(directoryURL, reason):
      "Cannot inspect \(directoryURL.path): \(reason)"
    case let .unsafeDatabaseEntry(databaseURL, reason):
      "Unsafe passive-run entry \(databaseURL.lastPathComponent): \(reason)"
    case let .databaseInspectionFailed(databaseURL, reason):
      "Cannot verify \(databaseURL.lastPathComponent): \(reason)"
    case let .integrityCheckFailed(databaseURL):
      "SQLite integrity check failed for \(databaseURL.lastPathComponent)."
    case let .emptyDatabase(databaseURL):
      "No run record exists in \(databaseURL.lastPathComponent)."
    case let .unfinishedRun(databaseURL, runID):
      "Run \(runID) in \(databaseURL.lastPathComponent) has no single complete passive-probe lifecycle."
    case let .malformedRunLifecycle(databaseURL, runID, reason):
      "Run \(runID) in \(databaseURL.lastPathComponent) has invalid passive-probe evidence: \(reason)"
    case let .unresolvedCommands(databaseURL, runID, commandIDs):
      "Run \(runID) in \(databaseURL.lastPathComponent) has unresolved commands: "
        + commandIDs.map(\.uuidString).joined(separator: ", ") + "."
    }
  }
}

public struct PassiveRunRecoveryScan: Hashable, Sendable {
  public let inspectedDatabaseURLs: [URL]
  public let issues: [PassiveRunRecoveryIssue]

  public init(inspectedDatabaseURLs: [URL], issues: [PassiveRunRecoveryIssue]) {
    self.inspectedDatabaseURLs = inspectedDatabaseURLs
    self.issues = issues
  }

  public var blocksPoweredProbe: Bool { !issues.isEmpty }
}

public struct PassiveRunRecoveryRequiredError: LocalizedError, Equatable, Sendable {
  public let scan: PassiveRunRecoveryScan

  public init(scan: PassiveRunRecoveryScan) {
    self.scan = scan
  }

  public var errorDescription: String? {
    let count = scan.issues.count
    let noun = count == 1 ? "issue" : "issues"
    return "RECOVERY BLOCKED: \(count) prior passive-run \(noun) require inspection. "
      + "No powered probe was started; no prior command was replayed or mutated. "
      + scan.issues.map(\.summary).joined(separator: " ")
  }
}

/// Discovers prior passive-run ledgers and evaluates them without replaying or
/// changing any recorded command intent. Results are stable by filename, run,
/// event, and command sequence so the same evidence produces the same blocker.
public enum PassiveRunRecoveryScanner {
  public static func scan(directoryURL: URL) async -> PassiveRunRecoveryScan {
    let directory = directoryURL.standardizedFileURL
    let candidates: [URL]
    do {
      candidates = try FileManager.default.contentsOfDirectory(
        at: directory,
        includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
        options: [.skipsHiddenFiles]
      )
      .filter {
        $0.pathExtension == "sqlite"
          && $0.deletingPathExtension().lastPathComponent.hasPrefix("passive-")
      }
      .sorted { $0.lastPathComponent < $1.lastPathComponent }
    } catch {
      return PassiveRunRecoveryScan(
        inspectedDatabaseURLs: [],
        issues: [
          .directoryInspectionFailed(directoryURL: directory, reason: String(describing: error))
        ]
      )
    }

    var inspected: [URL] = []
    var issues: [PassiveRunRecoveryIssue] = []
    for candidate in candidates {
      let databaseURL = candidate.standardizedFileURL
      inspected.append(databaseURL)
      do {
        let values = try databaseURL.resourceValues(forKeys: [
          .isRegularFileKey, .isSymbolicLinkKey,
        ])
        guard values.isSymbolicLink != true, values.isRegularFile == true else {
          issues.append(
            .unsafeDatabaseEntry(
              databaseURL: databaseURL,
              reason: "entry is not a regular, non-symbolic-link file"
            )
          )
          continue
        }
        guard databaseURL.path.hasPrefix(directory.path + "/") else {
          issues.append(
            .unsafeDatabaseEntry(databaseURL: databaseURL, reason: "entry escapes run directory")
          )
          continue
        }

        let ledger = try RunLedger.openReadOnly(databaseURL: databaseURL)
        do {
          guard try await ledger.integrityCheck() else {
            issues.append(.integrityCheckFailed(databaseURL: databaseURL))
            await ledger.close()
            continue
          }
          let runs = try await ledger.runSummaries()
          guard !runs.isEmpty else {
            issues.append(.emptyDatabase(databaseURL: databaseURL))
            await ledger.close()
            continue
          }
          for run in runs {
            let commands = try await ledger.unresolvedCommandIntents(runID: run.runID)
            if !commands.isEmpty {
              issues.append(
                .unresolvedCommands(
                  databaseURL: databaseURL,
                  runID: run.runID,
                  commandIDs: commands.map(\.commandID)
                )
              )
            }
            let events: [LedgerEvent]
            do {
              events = try await ledger.events(runID: run.runID)
            } catch let error as RunLedgerError {
              if case .payloadCorruption = error {
                issues.append(
                  .malformedRunLifecycle(
                    databaseURL: databaseURL,
                    runID: run.runID,
                    reason: String(describing: error)
                  )
                )
                continue
              }
              throw error
            }
            if let lifecycleIssue = validateLifecycle(events) {
              issues.append(
                lifecycleIssue.isUnfinished
                  ? .unfinishedRun(databaseURL: databaseURL, runID: run.runID)
                  : .malformedRunLifecycle(
                    databaseURL: databaseURL,
                    runID: run.runID,
                    reason: lifecycleIssue.reason
                  )
              )
            }
          }
          await ledger.close()
        } catch {
          await ledger.close()
          throw error
        }
      } catch {
        issues.append(
          .databaseInspectionFailed(databaseURL: databaseURL, reason: String(describing: error))
        )
      }
    }
    return PassiveRunRecoveryScan(inspectedDatabaseURLs: inspected, issues: issues)
  }

  private struct LifecycleIssue {
    let isUnfinished: Bool
    let reason: String
  }

  private static func validateLifecycle(_ events: [LedgerEvent]) -> LifecycleIssue? {
    let starts = events.filter { $0.kind == "machine.passive_probe.started" }
    let finishes = events.filter { $0.kind == "machine.passive_probe.finished" }
    let transitionEvents = events.filter { $0.kind == "runtime.authority.transition" }
    guard starts.count == 1, finishes.count == 1, !transitionEvents.isEmpty else {
      return LifecycleIssue(
        isUnfinished: true,
        reason: "expected one start, finish, and passive-probe authority transition"
      )
    }
    let startEvent = starts[0]
    let finishEvent = finishes[0]
    guard startEvent.schemaVersion == 1, finishEvent.schemaVersion == 1,
      transitionEvents.allSatisfy({ $0.schemaVersion == 1 })
    else {
      return LifecycleIssue(isUnfinished: false, reason: "unsupported lifecycle schema version")
    }
    do {
      let started = try JSONDecoder().decode(
        PassiveProbeStartedRecord.self, from: startEvent.payload)
      let finished = try JSONDecoder().decode(
        PassiveProbeFinishedRecord.self, from: finishEvent.payload)
      let transitions = try transitionEvents.map { event in
        (
          event,
          try JSONDecoder().decode(AuthorityTransitionRecord.self, from: event.payload)
        )
      }
      let completions = transitions.filter { $0.1.reason == .passiveProbeCompleted }
      guard completions.count == 1 else {
        return LifecycleIssue(
          isUnfinished: true,
          reason: "expected exactly one passive-probe authority transition"
        )
      }
      let transitionEvent = completions[0].0
      guard startEvent.sequence < finishEvent.sequence,
        finishEvent.sequence < transitionEvent.sequence
      else {
        return LifecycleIssue(isUnfinished: false, reason: "lifecycle records are out of order")
      }
      guard started.probeID == finished.probeID else {
        return LifecycleIssue(isUnfinished: false, reason: "start and finish probe IDs differ")
      }
      guard started.link == finished.link else {
        return LifecycleIssue(isUnfinished: false, reason: "start and finish links differ")
      }
      guard started.startedAt == finished.startedAt else {
        return LifecycleIssue(isUnfinished: false, reason: "start and finish timestamps differ")
      }
      guard started.queries == PassiveQuery.allCases else {
        return LifecycleIssue(
          isUnfinished: false, reason: "start query list is not the closed passive set")
      }
    } catch {
      return LifecycleIssue(
        isUnfinished: false,
        reason: "version-1 lifecycle payload cannot be decoded: \(error)"
      )
    }
    return nil
  }
}
