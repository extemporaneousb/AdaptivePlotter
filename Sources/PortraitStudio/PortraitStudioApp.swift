import AppKit
import SwiftUI
import PortraitStudioUI

@main
struct PortraitStudioApp: App {
  @NSApplicationDelegateAdaptor(PortraitStudioApplicationDelegate.self) private var delegate
  @State private var composition = PortraitStudioComposition()

  var body: some Scene {
    Window("Portrait Studio", id: "portrait-studio") {
      PortraitStudioRootView(composition: composition)
        .frame(minWidth: 1000, minHeight: 700)
        .task {
          delegate.composition = composition
          await composition.start()
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
