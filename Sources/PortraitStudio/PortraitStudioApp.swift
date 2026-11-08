import AppKit
import SwiftUI
import DrawingLibrary
import PortraitLibrary
import PortraitStudioUI

@main
struct PortraitStudioApp: App {
  @NSApplicationDelegateAdaptor(PortraitStudioApplicationDelegate.self) private var delegate
  @State private var dojo: FlowDojoModel
  @State private var acquisition: PortraitStudioModel
  private let launchError: String?
  private let library: DrawingLibrary

  init() {
    let args = CommandLine.arguments
    var location = FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent("Library/Application Support/PortraitStudio/DrawingLibrary", isDirectory: true)
    var error: String?
    if let index = args.firstIndex(of: "--library") {
      if args.filter({ $0 == "--library" }).count == 1, index + 1 < args.count, args[index + 1].hasPrefix("/") {
        location = URL(fileURLWithPath: args[index + 1], isDirectory: true)
      } else { error = "--library requires one absolute directory path." }
    }
    let owner = DrawingLibrary(directoryURL: location)
    library = owner
    _dojo = State(initialValue: FlowDojoModel(directory: location, library: owner))
    _acquisition = State(initialValue: PortraitStudioModel(library: owner))
    launchError = error
  }

  var body: some Scene {
    Window("Portrait Studio — Flow Edge Dojo", id: "portrait-studio") {
      if let launchError {
        ContentUnavailableView("Drawing Library configuration", systemImage: "folder.badge.questionmark", description: Text(launchError))
      } else {
        PortraitStudioDojoWindow(dojo: dojo, acquisition: acquisition, library: library, delegate: delegate)
      }
    }.defaultSize(width: 1440, height: 940)
  }
}

private struct PortraitStudioDojoWindow: View {
  @Environment(\.openWindow) private var openWindow
  @Bindable var dojo: FlowDojoModel
  @Bindable var acquisition: PortraitStudioModel
  let library: DrawingLibrary
  let delegate: PortraitStudioApplicationDelegate
  @State private var libraryError: String?
  var body: some View {
    FlowDojoView(model: dojo, camera: acquisition, selectCamera: {
      await acquisition.startCamera(); return acquisition.cameraStatus
    })
    .frame(minWidth: 1100, minHeight: 720)
    .overlay(alignment: .bottom) {
      if let libraryError { Text(libraryError).foregroundStyle(.red).padding() }
    }
    .task {
      delegate.dojo = dojo; delegate.acquisition = acquisition; delegate.library = library
      delegate.restorePortfolioWindow = {
        openWindow(id: "portrait-studio")
        NSApp.activate(ignoringOtherApps: true)
      }
      do { try await library.open() }
      catch { libraryError = "Drawing Library unavailable: " + error.localizedDescription }
      await acquisition.discover(excluding: nil)
    }
  }
}

@MainActor
final class PortraitStudioApplicationDelegate: NSObject, NSApplicationDelegate {
  var dojo: FlowDojoModel?
  var acquisition: PortraitStudioModel?
  var library: DrawingLibrary?
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
      await library?.closeLibrary()
      sender.reply(toApplicationShouldTerminate: true)
    }
    return .terminateLater
  }
}
