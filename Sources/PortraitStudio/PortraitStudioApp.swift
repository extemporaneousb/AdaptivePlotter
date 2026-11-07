import AppKit
import SwiftUI
import PortraitLibrary
import PortraitStudioUI

@main
struct PortraitStudioApp: App {
  @NSApplicationDelegateAdaptor(PortraitStudioApplicationDelegate.self) private var delegate
  @State private var dojo: FlowDojoModel
  @State private var acquisition: PortraitStudioModel
  private let launchError: String?

  init() {
    let args = CommandLine.arguments
    var location = FlowDojoModel.defaultDirectory
    var error: String?
    if let index = args.firstIndex(of: "--portfolio") {
      if args.filter({ $0 == "--portfolio" }).count == 1, index + 1 < args.count, args[index + 1].hasPrefix("/") {
        location = URL(fileURLWithPath: args[index + 1], isDirectory: true)
      } else { error = "--portfolio requires one absolute directory path." }
    }
    if args.contains("--review-library") {
      error = "This release uses Flow Edge portfolios. Historical review libraries remain unchanged; launch without --review-library or choose --portfolio with a new portfolio directory."
    }
    _dojo = State(initialValue: FlowDojoModel(directory: location, nominalPenWidthMM: 0.4))
    _acquisition = State(initialValue: PortraitStudioModel(candidateStore: PortraitCandidateStore(directoryURL: PortraitStudioComposition.privateLibraryURL)))
    launchError = error
  }

  var body: some Scene {
    Window("Portrait Studio — Flow Edge Dojo", id: "portrait-studio") {
      if let launchError {
        ContentUnavailableView("Portfolio configuration", systemImage: "folder.badge.questionmark", description: Text(launchError))
      } else {
        PortraitStudioDojoWindow(dojo: dojo, acquisition: acquisition, delegate: delegate)
      }
    }.defaultSize(width: 1440, height: 940)
  }
}

private struct PortraitStudioDojoWindow: View {
  @Environment(\.openWindow) private var openWindow
  @Bindable var dojo: FlowDojoModel
  @Bindable var acquisition: PortraitStudioModel
  let delegate: PortraitStudioApplicationDelegate
  var body: some View {
    FlowDojoView(model: dojo, camera: acquisition, selectCamera: {
      await acquisition.startCamera(); return acquisition.cameraStatus
    })
    .frame(minWidth: 1100, minHeight: 720)
    .task {
      delegate.dojo = dojo; delegate.acquisition = acquisition
      delegate.restorePortfolioWindow = {
        openWindow(id: "portrait-studio")
        NSApp.activate(ignoringOtherApps: true)
      }
      await acquisition.discover(excluding: nil)
    }
  }
}

@MainActor
final class PortraitStudioApplicationDelegate: NSObject, NSApplicationDelegate {
  var dojo: FlowDojoModel?
  var acquisition: PortraitStudioModel?
  var restorePortfolioWindow: (() -> Void)?
  private var terminating = false
  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
  func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    guard !terminating else { return .terminateLater }
    if dojo?.needsRecovery == true {
      restorePortfolioWindow?()
      let alert = NSAlert(); alert.messageText = "Portfolio autosave needs recovery"
      alert.informativeText = "Resolve the write error and use Recover autosave before closing. Pending edits remain in this window."
      alert.addButton(withTitle: "Return to portfolio"); alert.runModal()
      return .terminateCancel
    }
    terminating = true
    Task {
      if await dojo?.shutdown() == false {
        restorePortfolioWindow?()
        terminating = false
        sender.reply(toApplicationShouldTerminate: false)
        return
      }
      await acquisition?.shutdown()
      sender.reply(toApplicationShouldTerminate: true)
    }
    return .terminateLater
  }
}
