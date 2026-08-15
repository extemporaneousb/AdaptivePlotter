import AppKit
import Darwin
import Foundation

let adaptivePlotterBundleIdentifier = "com.bullard.AdaptivePlotter"
let adaptivePlotterExecutableName = "AdaptivePlotter"
let adaptivePlotterLaunchTimeout: TimeInterval = 30

struct ApplicationIdentity: Equatable {
    let bundlePath: String
    let executablePath: String
}

struct ProcessRecord: Equatable {
    let pid: pid_t
    let executablePath: String
}

struct RunningApplicationRecord: Equatable {
    let pid: pid_t
    let bundleIdentifier: String?
    let bundlePath: String?
    let executablePath: String?
    let activationPolicyRawValue: Int
    let isFinishedLaunching: Bool
    let isActive: Bool
}

enum RunningApplicationDecision: Equatable {
    case launch
    case activate(RunningApplicationRecord)
    case refuse([RunningApplicationRecord])
}

enum LaunchOutcome: String {
    case launched
    case activatedExisting = "activated existing"
}

enum RequestedLaunchMode: Equatable {
    case normal
    case simulated
}

struct LauncherInvocation: Equatable {
    let validateOnly: Bool
    let mode: RequestedLaunchMode
    let bundlePath: String
}

func launcherInvocation(arguments: [String]) -> LauncherInvocation? {
    if arguments.count == 1 {
        guard !arguments[0].hasPrefix("--") else { return nil }
        return LauncherInvocation(
            validateOnly: false,
            mode: .normal,
            bundlePath: arguments[0]
        )
    }
    guard arguments.count == 2 else { return nil }
    switch arguments[0] {
    case "--validate-only":
        return LauncherInvocation(
            validateOnly: true,
            mode: .normal,
            bundlePath: arguments[1]
        )
    case "--simulated":
        return LauncherInvocation(
            validateOnly: false,
            mode: .simulated,
            bundlePath: arguments[1]
        )
    default:
        return nil
    }
}

func applicationArguments(for mode: RequestedLaunchMode) -> [String] {
    var arguments = [
        "-ApplePersistenceIgnoreState", "YES",
        "-NSQuitAlwaysKeepsWindows", "NO",
    ]
    if mode == .simulated {
        arguments.append(contentsOf: ["-AdaptivePlotterStartSimulated", "YES"])
    }
    return arguments
}

enum RuntimeProofIssue: Equatable {
    case bundleIdentifier(actual: String?)
    case bundlePath(actual: String?)
    case executablePath(actual: String?)
    case notFinishedLaunching
    case notRegular(actualRawValue: Int)
    case notActive
}

func canonicalPath(_ path: String) -> String {
    URL(fileURLWithPath: path)
        .standardizedFileURL
        .resolvingSymlinksInPath()
        .path
}

func rawAdaptivePlotterProcesses(
    in processes: [ProcessRecord],
    expectedExecutablePath: String
) -> [ProcessRecord] {
    let expected = canonicalPath(expectedExecutablePath)
    return processes.compactMap { process in
        let path = canonicalPath(process.executablePath)
        guard URL(fileURLWithPath: path).lastPathComponent == adaptivePlotterExecutableName,
              path != expected
        else {
            return nil
        }
        return ProcessRecord(pid: process.pid, executablePath: path)
    }
    .sorted {
        if $0.pid == $1.pid { return $0.executablePath < $1.executablePath }
        return $0.pid < $1.pid
    }
}

func runningApplicationDecision(
    records: [RunningApplicationRecord],
    expectedIdentity: ApplicationIdentity
) -> RunningApplicationDecision {
    let candidates = records
        .filter { $0.bundleIdentifier == adaptivePlotterBundleIdentifier }
        .sorted { $0.pid < $1.pid }
    guard !candidates.isEmpty else { return .launch }

    let expectedBundle = canonicalPath(expectedIdentity.bundlePath)
    let expectedExecutable = canonicalPath(expectedIdentity.executablePath)
    if candidates.count == 1,
       let only = candidates.first,
       only.bundlePath.map(canonicalPath) == expectedBundle,
       only.executablePath.map(canonicalPath) == expectedExecutable
    {
        return .activate(only)
    }
    return .refuse(candidates)
}

func successfulLaunchDescription(
    outcome: LaunchOutcome,
    application: RunningApplicationRecord
) -> String {
    let bundle = application.bundlePath ?? "<missing>"
    let executable = application.executablePath ?? "<missing>"
    return "\(outcome.rawValue) \(adaptivePlotterBundleIdentifier) "
        + "pid=\(application.pid) bundle=\(bundle) executable=\(executable) "
        + "activationPolicy=regular active=true"
}

func runtimeProofIssue(
    application: RunningApplicationRecord,
    expectedIdentity: ApplicationIdentity,
    requireFinishedLaunching: Bool,
    requireRegularPolicy: Bool,
    requireActive: Bool
) -> RuntimeProofIssue? {
    guard application.bundleIdentifier == adaptivePlotterBundleIdentifier else {
        return .bundleIdentifier(actual: application.bundleIdentifier)
    }
    let expectedBundle = canonicalPath(expectedIdentity.bundlePath)
    guard application.bundlePath.map(canonicalPath) == expectedBundle else {
        return .bundlePath(actual: application.bundlePath)
    }
    let expectedExecutable = canonicalPath(expectedIdentity.executablePath)
    guard application.executablePath.map(canonicalPath) == expectedExecutable else {
        return .executablePath(actual: application.executablePath)
    }
    if requireFinishedLaunching, !application.isFinishedLaunching {
        return .notFinishedLaunching
    }
    if requireRegularPolicy,
       application.activationPolicyRawValue
        != NSApplication.ActivationPolicy.regular.rawValue
    {
        return .notRegular(actualRawValue: application.activationPolicyRawValue)
    }
    if requireActive, !application.isActive {
        return .notActive
    }
    return nil
}

private struct ValidatedBundle {
    let url: URL
    let executableURL: URL

    var identity: ApplicationIdentity {
        ApplicationIdentity(bundlePath: url.path, executablePath: executableURL.path)
    }
}

private enum LauncherError: LocalizedError {
    case usage
    case missingBundle(URL)
    case unexpectedBundleIdentifier(actual: String?)
    case missingExecutable(URL)
    case unexpectedExecutable(actual: URL, expected: URL)
    case processInspectionFailed(String)
    case competingApplications(
        raw: [ProcessRecord],
        bundled: [RunningApplicationRecord]
    )
    case timedOut
    case launchFailed(Error)
    case missingRunningApplication
    case unexpectedRunningApplication(actual: String?)
    case unexpectedRunningBundle(actual: String?, expected: String)
    case unexpectedRunningExecutable(actual: String?, expected: String)
    case applicationDidNotBecomeRegular(pid: pid_t)
    case applicationDidNotFinishLaunching(pid: pid_t)
    case applicationCouldNotActivate(pid: pid_t)
    case applicationDidNotBecomeActive(pid: pid_t)
    case applicationTerminated(pid: pid_t)
    case postLaunchIdentityConflict(expectedPID: pid_t)
    case simulatedModeRequiresNewInstance(pid: pid_t)

    var errorDescription: String? {
        switch self {
        case .usage:
            return """
                usage:
                  AdaptivePlotterLauncher PATH_TO_ADAPTIVEPLOTTER_APP
                  AdaptivePlotterLauncher --simulated PATH_TO_ADAPTIVEPLOTTER_APP
                  AdaptivePlotterLauncher --validate-only PATH_TO_ADAPTIVEPLOTTER_APP

                --simulated launches the signed app directly into causal SIMULATED mode without camera discovery or startup.
                --validate-only validates bundle identity and cannot be combined with --simulated.
                """
        case .missingBundle(let url):
            return "AdaptivePlotter app bundle does not exist at \(url.path)"
        case .unexpectedBundleIdentifier(let actual):
            return "refusing app bundle with identifier \(actual ?? "<missing>"); expected \(adaptivePlotterBundleIdentifier)"
        case .missingExecutable(let url):
            return "AdaptivePlotter app bundle has no executable at \(url.path)"
        case .unexpectedExecutable(let actual, let expected):
            return "refusing app bundle executable \(actual.path); expected \(expected.path)"
        case .processInspectionFailed(let reason):
            return "could not inspect current-user processes before physical bundle launch: \(reason)"
        case .competingApplications(let raw, let bundled):
            var lines = [
                "refusing physical bundle launch because competing AdaptivePlotter processes are running. Close them before using make run-app; no process was terminated."
            ]
            lines.append(contentsOf: raw.map {
                "raw pid=\($0.pid) executable=\($0.executablePath)"
            })
            lines.append(contentsOf: bundled.map {
                "bundle pid=\($0.pid) identifier=\($0.bundleIdentifier ?? "<missing>") "
                    + "bundle=\($0.bundlePath ?? "<missing>") "
                    + "executable=\($0.executablePath ?? "<missing>")"
            })
            return lines.joined(separator: "\n")
        case .timedOut:
            return "LaunchServices did not complete the AdaptivePlotter launch within \(Int(adaptivePlotterLaunchTimeout)) seconds"
        case .launchFailed(let error):
            return "LaunchServices could not launch AdaptivePlotter: \(error.localizedDescription)"
        case .missingRunningApplication:
            return "LaunchServices reported success without a running AdaptivePlotter application"
        case .unexpectedRunningApplication(let actual):
            return "LaunchServices returned application identifier \(actual ?? "<missing>"); expected \(adaptivePlotterBundleIdentifier)"
        case .unexpectedRunningBundle(let actual, let expected):
            return "running AdaptivePlotter bundle is \(actual ?? "<missing>"); expected \(expected)"
        case .unexpectedRunningExecutable(let actual, let expected):
            return "running AdaptivePlotter executable is \(actual ?? "<missing>"); expected \(expected)"
        case .applicationDidNotBecomeRegular(let pid):
            return "AdaptivePlotter pid=\(pid) did not report regular foreground activation policy"
        case .applicationDidNotFinishLaunching(let pid):
            return "AdaptivePlotter pid=\(pid) did not finish launching"
        case .applicationCouldNotActivate(let pid):
            return "AdaptivePlotter pid=\(pid) rejected the activation request"
        case .applicationDidNotBecomeActive(let pid):
            return "AdaptivePlotter pid=\(pid) did not become the active foreground application"
        case .applicationTerminated(let pid):
            return "AdaptivePlotter pid=\(pid) terminated before launch identity could be proved"
        case .postLaunchIdentityConflict(let expectedPID):
            return "AdaptivePlotter pid=\(expectedPID) launched, but the post-launch process snapshot did not contain exactly that bundled instance"
        case .simulatedModeRequiresNewInstance(let pid):
            return "refusing --simulated because AdaptivePlotter pid=\(pid) is already running; quit it first so the nonpersistent simulated startup argument can be applied"
        }
    }
}

@MainActor
private final class LaunchCompletion {
    var application: NSRunningApplication?
    var error: Error?
    var isFinished = false
}

@MainActor
private enum LauncherCore {
    static func validatedBundle(path: String) throws -> ValidatedBundle {
        let url = URL(fileURLWithPath: path, isDirectory: true)
            .standardizedFileURL
            .resolvingSymlinksInPath()
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
              isDirectory.boolValue,
              url.pathExtension == "app"
        else {
            throw LauncherError.missingBundle(url)
        }

        guard let bundle = Bundle(url: url),
              bundle.bundleIdentifier == adaptivePlotterBundleIdentifier
        else {
            throw LauncherError.unexpectedBundleIdentifier(
                actual: Bundle(url: url)?.bundleIdentifier
            )
        }
        guard let executableURL = bundle.executableURL,
              FileManager.default.isExecutableFile(atPath: executableURL.path)
        else {
            throw LauncherError.missingExecutable(url)
        }
        let canonicalExecutable = executableURL.standardizedFileURL.resolvingSymlinksInPath()
        let expectedExecutable = url
            .appendingPathComponent("Contents/MacOS/\(adaptivePlotterExecutableName)")
            .standardizedFileURL
            .resolvingSymlinksInPath()
        guard canonicalExecutable == expectedExecutable else {
            throw LauncherError.unexpectedExecutable(
                actual: canonicalExecutable,
                expected: expectedExecutable
            )
        }
        return ValidatedBundle(url: url, executableURL: canonicalExecutable)
    }

    static func currentUserProcesses() throws -> [ProcessRecord] {
        let initialCount = proc_listallpids(nil, 0)
        guard initialCount >= 0 else {
            throw LauncherError.processInspectionFailed(
                String(cString: strerror(errno))
            )
        }

        var capacity = max(Int(initialCount) + 64, 256)
        var pids = [pid_t]()
        for _ in 0..<3 {
            var buffer = [pid_t](repeating: 0, count: capacity)
            let count = buffer.withUnsafeMutableBytes { bytes in
                proc_listallpids(bytes.baseAddress, Int32(bytes.count))
            }
            guard count >= 0 else {
                throw LauncherError.processInspectionFailed(
                    String(cString: strerror(errno))
                )
            }
            if Int(count) < capacity {
                pids = Array(buffer.prefix(Int(count)))
                break
            }
            capacity *= 2
        }
        guard !pids.isEmpty || initialCount == 0 else {
            throw LauncherError.processInspectionFailed("process table changed repeatedly during inspection")
        }

        let currentUID = getuid()
        return pids.compactMap { pid in
            guard pid > 0 else { return nil }
            var info = proc_bsdinfo()
            let infoSize = Int32(MemoryLayout<proc_bsdinfo>.size)
            let copied = withUnsafeMutablePointer(to: &info) { pointer in
                proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, pointer, infoSize)
            }
            guard copied == infoSize, info.pbi_uid == currentUID else { return nil }

            var pathBuffer = [CChar](
                repeating: 0,
                count: Int(PATH_MAX) * 4
            )
            let pathLength = pathBuffer.withUnsafeMutableBytes { bytes in
                proc_pidpath(pid, bytes.baseAddress, UInt32(bytes.count))
            }
            guard pathLength > 0 else { return nil }
            return ProcessRecord(
                pid: pid,
                executablePath: canonicalPath(String(cString: pathBuffer))
            )
        }
    }

    static func allCurrentUserProcesses() throws -> [ProcessRecord] {
        var byPID = Dictionary(uniqueKeysWithValues: try currentUserProcesses().map {
            ($0.pid, $0)
        })
        for application in NSWorkspace.shared.runningApplications {
            guard let path = application.executableURL?.path else { continue }
            byPID[application.processIdentifier] = ProcessRecord(
                pid: application.processIdentifier,
                executablePath: canonicalPath(path)
            )
        }
        return byPID.values.sorted { $0.pid < $1.pid }
    }

    static func snapshot(_ application: NSRunningApplication) -> RunningApplicationRecord {
        RunningApplicationRecord(
            pid: application.processIdentifier,
            bundleIdentifier: application.bundleIdentifier,
            bundlePath: application.bundleURL.map { canonicalPath($0.path) },
            executablePath: application.executableURL.map { canonicalPath($0.path) },
            activationPolicyRawValue: application.activationPolicy.rawValue,
            isFinishedLaunching: application.isFinishedLaunching,
            isActive: application.isActive
        )
    }

    static func expectedRunningApplications() -> [NSRunningApplication] {
        NSRunningApplication.runningApplications(
            withBundleIdentifier: adaptivePlotterBundleIdentifier
        )
        .sorted { $0.processIdentifier < $1.processIdentifier }
    }

    static func inspectEnvironment(
        expectedIdentity: ApplicationIdentity
    ) throws -> NSRunningApplication? {
        let applications = expectedRunningApplications()
        let records = applications.map(snapshot)
        let raw = rawAdaptivePlotterProcesses(
            in: try allCurrentUserProcesses(),
            expectedExecutablePath: expectedIdentity.executablePath
        )
        switch runningApplicationDecision(
            records: records,
            expectedIdentity: expectedIdentity
        ) {
        case .launch:
            guard raw.isEmpty else {
                throw LauncherError.competingApplications(raw: raw, bundled: [])
            }
            return nil
        case .activate(let expected):
            guard raw.isEmpty else {
                throw LauncherError.competingApplications(raw: raw, bundled: [])
            }
            return applications.first {
                $0.processIdentifier == expected.pid
            }
        case .refuse(let bundled):
            throw LauncherError.competingApplications(raw: raw, bundled: bundled)
        }
    }

    static func open(
        bundleURL: URL,
        arguments: [String]
    ) throws -> NSRunningApplication {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.addsToRecentItems = false
        configuration.createsNewApplicationInstance = false
        configuration.allowsRunningApplicationSubstitution = false
        configuration.arguments = arguments

        let completion = LaunchCompletion()
        NSWorkspace.shared.openApplication(
            at: bundleURL,
            configuration: configuration
        ) { application, error in
            completion.application = application
            completion.error = error
            completion.isFinished = true
        }

        let deadline = Date(timeIntervalSinceNow: adaptivePlotterLaunchTimeout)
        while !completion.isFinished, Date() < deadline {
            runLoopStep(deadline: deadline)
        }

        guard completion.isFinished else { throw LauncherError.timedOut }
        if let error = completion.error { throw LauncherError.launchFailed(error) }
        guard let application = completion.application else {
            throw LauncherError.missingRunningApplication
        }
        return application
    }

    static func proveIdentity(
        application: NSRunningApplication,
        expectedIdentity: ApplicationIdentity
    ) throws {
        let deadline = Date(timeIntervalSinceNow: adaptivePlotterLaunchTimeout)
        var last = snapshot(application)
        while Date() < deadline {
            last = snapshot(application)
            guard !application.isTerminated else {
                throw LauncherError.applicationTerminated(pid: last.pid)
            }
            try validateStaticIdentity(last, expectedIdentity: expectedIdentity)
            if last.isFinishedLaunching,
               last.activationPolicyRawValue == NSApplication.ActivationPolicy.regular.rawValue
            {
                return
            }
            runLoopStep(deadline: deadline)
        }
        if !last.isFinishedLaunching {
            throw LauncherError.applicationDidNotFinishLaunching(pid: last.pid)
        }
        throw LauncherError.applicationDidNotBecomeRegular(pid: last.pid)
    }

    static func activate(_ application: NSRunningApplication) throws {
        let pid = application.processIdentifier
        guard application.activate(options: [.activateAllWindows]) else {
            throw LauncherError.applicationCouldNotActivate(pid: pid)
        }
        let deadline = Date(timeIntervalSinceNow: adaptivePlotterLaunchTimeout)
        while !application.isActive, Date() < deadline {
            guard !application.isTerminated else {
                throw LauncherError.applicationTerminated(pid: pid)
            }
            runLoopStep(deadline: deadline)
        }
        guard application.isActive else {
            throw LauncherError.applicationDidNotBecomeActive(pid: pid)
        }
    }

    static func validatePostLaunchEnvironment(
        application: NSRunningApplication,
        expectedIdentity: ApplicationIdentity
    ) throws {
        guard let only = try inspectEnvironment(expectedIdentity: expectedIdentity),
              only.processIdentifier == application.processIdentifier
        else {
            throw LauncherError.postLaunchIdentityConflict(
                expectedPID: application.processIdentifier
            )
        }
    }

    static func completedProof(
        application: NSRunningApplication,
        expectedIdentity: ApplicationIdentity
    ) throws -> RunningApplicationRecord {
        let record = snapshot(application)
        let issue = runtimeProofIssue(
            application: record,
            expectedIdentity: expectedIdentity,
            requireFinishedLaunching: true,
            requireRegularPolicy: true,
            requireActive: true
        )
        switch issue {
        case .none:
            return record
        case .bundleIdentifier, .bundlePath, .executablePath:
            try validateStaticIdentity(record, expectedIdentity: expectedIdentity)
            preconditionFailure("static identity validation did not reject invalid proof")
        case .notFinishedLaunching:
            throw LauncherError.applicationDidNotFinishLaunching(pid: record.pid)
        case .notRegular:
            throw LauncherError.applicationDidNotBecomeRegular(pid: record.pid)
        case .notActive:
            throw LauncherError.applicationDidNotBecomeActive(pid: record.pid)
        }
    }

    private static func validateStaticIdentity(
        _ record: RunningApplicationRecord,
        expectedIdentity: ApplicationIdentity
    ) throws {
        let issue = runtimeProofIssue(
            application: record,
            expectedIdentity: expectedIdentity,
            requireFinishedLaunching: false,
            requireRegularPolicy: false,
            requireActive: false
        )
        switch issue {
        case .none:
            return
        case .bundleIdentifier(let actual):
            throw LauncherError.unexpectedRunningApplication(
                actual: actual
            )
        case .bundlePath(let actual):
            throw LauncherError.unexpectedRunningBundle(
                actual: actual,
                expected: canonicalPath(expectedIdentity.bundlePath)
            )
        case .executablePath(let actual):
            throw LauncherError.unexpectedRunningExecutable(
                actual: actual,
                expected: canonicalPath(expectedIdentity.executablePath)
            )
        case .notFinishedLaunching, .notRegular, .notActive:
            preconditionFailure("static identity validation requested dynamic proof")
        }
    }

    private static func runLoopStep(deadline: Date) {
        _ = RunLoop.current.run(
            mode: .default,
            before: min(deadline, Date(timeIntervalSinceNow: 0.05))
        )
    }
}

#if !ADAPTIVEPLOTTER_LAUNCHER_TESTING
@main
@MainActor
private struct AdaptivePlotterLauncher {
    static func main() {
        do {
            let arguments = Array(CommandLine.arguments.dropFirst())
            guard let invocation = launcherInvocation(arguments: arguments) else {
                throw LauncherError.usage
            }

            let bundle = try LauncherCore.validatedBundle(path: invocation.bundlePath)
            if invocation.validateOnly {
                print(bundle.url.path)
                return
            }

            let existing = try LauncherCore.inspectEnvironment(
                expectedIdentity: bundle.identity
            )
            let application: NSRunningApplication
            let outcome: LaunchOutcome
            if let existing {
                guard invocation.mode == .normal else {
                    throw LauncherError.simulatedModeRequiresNewInstance(
                        pid: existing.processIdentifier
                    )
                }
                application = existing
                outcome = .activatedExisting
            } else {
                application = try LauncherCore.open(
                    bundleURL: bundle.url,
                    arguments: applicationArguments(for: invocation.mode)
                )
                outcome = .launched
            }

            try LauncherCore.proveIdentity(
                application: application,
                expectedIdentity: bundle.identity
            )
            try LauncherCore.activate(application)
            try LauncherCore.validatePostLaunchEnvironment(
                application: application,
                expectedIdentity: bundle.identity
            )

            let proof = try LauncherCore.completedProof(
                application: application,
                expectedIdentity: bundle.identity
            )

            print(successfulLaunchDescription(
                outcome: outcome,
                application: proof
            ))
            if outcome == .activatedExisting {
                print(
                    "The rebuilt bundle is on disk, but pid=\(application.processIdentifier) "
                        + "continues running its previously loaded bits until quit and relaunch."
                )
            }
        } catch {
            let message = (error as? LocalizedError)?.errorDescription
                ?? error.localizedDescription
            FileHandle.standardError.write(
                Data("AdaptivePlotterLauncher: \(message)\n".utf8)
            )
            Foundation.exit(EXIT_FAILURE)
        }
    }
}
#endif
