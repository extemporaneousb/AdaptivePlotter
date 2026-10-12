import AppKit
import SwiftUI
import PortraitStudioUI

@main
struct PortraitStudioApp: App {
  @NSApplicationDelegateAdaptor(PortraitStudioApplicationDelegate.self) private var delegate
  @State private var composition: PortraitStudioComposition?
  private let launchError: String?
  private let reviewLease: PortraitStudioReviewLibraryLease?

  init() {
    do {
      let library = try PortraitStudioLaunchOptions.reviewLibrary(arguments: CommandLine.arguments)
      reviewLease = try library.map(PortraitStudioReviewLibraryLease.init(directory:))
      let composition = PortraitStudioComposition(directoryURL: library ?? PortraitStudioComposition.privateLibraryURL)
      if library != nil { composition.workspace = .review }
      _composition = State(initialValue: composition)
      launchError = nil
    } catch {
      reviewLease = nil; _composition = State(initialValue: nil)
      launchError = error.localizedDescription
    }
  }

  var body: some Scene {
    Window("Portrait Studio", id: "portrait-studio") {
      if let composition {
        PortraitStudioRootView(composition: composition)
          .frame(minWidth: 1000, minHeight: 700)
          .task {
            delegate.composition = composition
            await composition.start()
          }
      } else {
        ContentUnavailableView("Review Library Unavailable", systemImage: "books.vertical",
          description: Text(launchError ?? "Library configuration is unavailable."))
      }
    }
    .defaultSize(width: 1280, height: 860)
  }
}

@MainActor
final class PortraitStudioApplicationDelegate: NSObject, NSApplicationDelegate {
  var composition: PortraitStudioComposition?
  private var terminating = false

  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

  func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    guard !terminating else { return .terminateLater }
    terminating = true
    Task {
      await composition?.shutdown()
      sender.reply(toApplicationShouldTerminate: true)
    }
    return .terminateLater
  }
}
