import AppKit
import Foundation

private let expectedBundleIdentifier = "com.bullard.AdaptivePlotter"
private let launchTimeout: TimeInterval = 30

private enum LauncherError: LocalizedError {
    case usage
    case missingBundle(URL)
    case unexpectedBundleIdentifier(actual: String?)
    case missingExecutable(URL)
    case timedOut
    case launchFailed(Error)
    case missingRunningApplication
    case unexpectedRunningApplication(actual: String?)

    var errorDescription: String? {
        switch self {
        case .usage:
            return "usage: AdaptivePlotterLauncher [--validate-only] PATH_TO_ADAPTIVEPLOTTER_APP"
        case .missingBundle(let url):
            return "AdaptivePlotter app bundle does not exist at \(url.path)"
        case .unexpectedBundleIdentifier(let actual):
            return "refusing app bundle with identifier \(actual ?? "<missing>"); expected \(expectedBundleIdentifier)"
        case .missingExecutable(let url):
            return "AdaptivePlotter app bundle has no executable at \(url.path)"
        case .timedOut:
            return "LaunchServices did not complete the AdaptivePlotter launch within \(Int(launchTimeout)) seconds"
        case .launchFailed(let error):
            return "LaunchServices could not launch AdaptivePlotter: \(error.localizedDescription)"
        case .missingRunningApplication:
            return "LaunchServices reported success without a running AdaptivePlotter application"
        case .unexpectedRunningApplication(let actual):
            return "LaunchServices returned application identifier \(actual ?? "<missing>"); expected \(expectedBundleIdentifier)"
        }
    }
}

@MainActor
private final class LaunchCompletion {
    var application: NSRunningApplication?
    var error: Error?
    var isFinished = false
}

@main
@MainActor
private struct AdaptivePlotterLauncher {
    static func main() {
        do {
            let arguments = Array(CommandLine.arguments.dropFirst())
            let validateOnly: Bool
            let path: String

            if arguments.count == 1 {
                validateOnly = false
                path = arguments[0]
            } else if arguments.count == 2, arguments[0] == "--validate-only" {
                validateOnly = true
                path = arguments[1]
            } else {
                throw LauncherError.usage
            }

            let bundleURL = try validatedBundleURL(path: path)
            if validateOnly {
                print(bundleURL.path)
                return
            }

            let application = try launch(bundleURL: bundleURL)
            print("launched \(expectedBundleIdentifier) pid=\(application.processIdentifier)")
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            FileHandle.standardError.write(Data("AdaptivePlotterLauncher: \(message)\n".utf8))
            Foundation.exit(EXIT_FAILURE)
        }
    }

    private static func validatedBundleURL(path: String) throws -> URL {
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
              bundle.bundleIdentifier == expectedBundleIdentifier
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
        return url
    }

    private static func launch(bundleURL: URL) throws -> NSRunningApplication {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.addsToRecentItems = false
        configuration.createsNewApplicationInstance = true
        configuration.allowsRunningApplicationSubstitution = false

        let completion = LaunchCompletion()
        NSWorkspace.shared.openApplication(
            at: bundleURL,
            configuration: configuration
        ) { application, error in
            completion.application = application
            completion.error = error
            completion.isFinished = true
        }

        let deadline = Date(timeIntervalSinceNow: launchTimeout)
        while !completion.isFinished, Date() < deadline {
            _ = RunLoop.current.run(
                mode: .default,
                before: min(deadline, Date(timeIntervalSinceNow: 0.05))
            )
        }

        guard completion.isFinished else {
            throw LauncherError.timedOut
        }
        if let error = completion.error {
            throw LauncherError.launchFailed(error)
        }
        guard let application = completion.application else {
            throw LauncherError.missingRunningApplication
        }
        guard application.bundleIdentifier == expectedBundleIdentifier else {
            throw LauncherError.unexpectedRunningApplication(
                actual: application.bundleIdentifier
            )
        }
        return application
    }
}
