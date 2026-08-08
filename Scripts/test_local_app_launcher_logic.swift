import AppKit
import Foundation

@main
private struct LocalAppLauncherLogicTests {
    static func main() {
        let expected = ApplicationIdentity(
            bundlePath: "/tmp/Expected/AdaptivePlotter.app",
            executablePath: "/tmp/Expected/AdaptivePlotter.app/Contents/MacOS/AdaptivePlotter"
        )

        testRawProcessClassification(expected: expected)
        testRunningApplicationDecisions(expected: expected)
        testRuntimeProof(expected: expected)
        testSuccessDescription(expected: expected)
        print("AdaptivePlotter local launcher logic tests passed")
    }

    private static func testRawProcessClassification(expected: ApplicationIdentity) {
        let processes = [
            ProcessRecord(pid: 10, executablePath: expected.executablePath),
            ProcessRecord(pid: 11, executablePath: "/repo/.build/debug/AdaptivePlotter"),
            ProcessRecord(pid: 12, executablePath: "/repo/.build/release/AdaptivePlotter"),
            ProcessRecord(pid: 13, executablePath: "/repo/.build/x86_64-apple-macosx/debug/AdaptivePlotter"),
            ProcessRecord(pid: 14, executablePath: "/other-worktree/custom-output/AdaptivePlotter"),
            ProcessRecord(pid: 15, executablePath: "/repo/.build/debug/AdaptivePlotterLauncher"),
            ProcessRecord(pid: 16, executablePath: "/repo/.build/debug/AdaptivePlotterPackageTests"),
        ]
        let result = rawAdaptivePlotterProcesses(
            in: processes,
            expectedExecutablePath: expected.executablePath
        )
        expect(result.map(\.pid) == [11, 12, 13, 14], "raw process classification")
    }

    private static func testRunningApplicationDecisions(expected: ApplicationIdentity) {
        expect(
            runningApplicationDecision(records: [], expectedIdentity: expected) == .launch,
            "empty running state launches"
        )

        let exact = application(pid: 21, identity: expected)
        expect(
            runningApplicationDecision(records: [exact], expectedIdentity: expected)
                == .activate(exact),
            "exact existing instance is reused with stable PID"
        )

        let wrongPath = RunningApplicationRecord(
            pid: 22,
            bundleIdentifier: adaptivePlotterBundleIdentifier,
            bundlePath: "/Applications/AdaptivePlotter.app",
            executablePath: "/Applications/AdaptivePlotter.app/Contents/MacOS/AdaptivePlotter",
            activationPolicyRawValue: NSApplication.ActivationPolicy.regular.rawValue,
            isFinishedLaunching: true,
            isActive: true
        )
        expect(
            runningApplicationDecision(records: [wrongPath], expectedIdentity: expected)
                == .refuse([wrongPath]),
            "same identifier at wrong path is refused"
        )
        expect(
            runningApplicationDecision(records: [exact, application(pid: 23, identity: expected)], expectedIdentity: expected)
                == .refuse([exact, application(pid: 23, identity: expected)]),
            "multiple exact instances are refused"
        )
    }

    private static func testRuntimeProof(expected: ApplicationIdentity) {
        let exact = application(pid: 31, identity: expected)
        expect(
            runtimeProofIssue(
                application: exact,
                expectedIdentity: expected,
                requireFinishedLaunching: true,
                requireRegularPolicy: true,
                requireActive: true
            ) == nil,
            "complete runtime proof"
        )

        var invalid = exact
        invalid = RunningApplicationRecord(
            pid: invalid.pid,
            bundleIdentifier: invalid.bundleIdentifier,
            bundlePath: invalid.bundlePath,
            executablePath: invalid.executablePath,
            activationPolicyRawValue: NSApplication.ActivationPolicy.prohibited.rawValue,
            isFinishedLaunching: invalid.isFinishedLaunching,
            isActive: invalid.isActive
        )
        expect(
            runtimeProofIssue(
                application: invalid,
                expectedIdentity: expected,
                requireFinishedLaunching: true,
                requireRegularPolicy: true,
                requireActive: true
            ) == .notRegular(actualRawValue: NSApplication.ActivationPolicy.prohibited.rawValue),
            "prohibited raw-style activation policy is refused"
        )
    }

    private static func testSuccessDescription(expected: ApplicationIdentity) {
        let record = application(pid: 41, identity: expected)
        let description = successfulLaunchDescription(
            outcome: .activatedExisting,
            application: record
        )
        expect(description.contains("activated existing \(adaptivePlotterBundleIdentifier) pid=41"), "outcome and PID reporting")
        expect(description.contains("bundle=\(expected.bundlePath)"), "bundle reporting")
        expect(description.contains("executable=\(expected.executablePath)"), "executable reporting")
        expect(description.hasSuffix("activationPolicy=regular active=true"), "regular active proof reporting")
    }

    private static func application(
        pid: pid_t,
        identity: ApplicationIdentity
    ) -> RunningApplicationRecord {
        RunningApplicationRecord(
            pid: pid,
            bundleIdentifier: adaptivePlotterBundleIdentifier,
            bundlePath: identity.bundlePath,
            executablePath: identity.executablePath,
            activationPolicyRawValue: NSApplication.ActivationPolicy.regular.rawValue,
            isFinishedLaunching: true,
            isActive: true
        )
    }

    private static func expect(
        _ condition: @autoclosure () -> Bool,
        _ label: String
    ) {
        guard condition() else {
            FileHandle.standardError.write(
                Data("launcher logic test failed: \(label)\n".utf8)
            )
            Foundation.exit(EXIT_FAILURE)
        }
    }
}
