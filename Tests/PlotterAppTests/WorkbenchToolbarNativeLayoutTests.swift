import AppKit
import PlotterUI
import SwiftUI
import Testing
@testable import PlotterApp

/// A fixture-only host checks AppKit's actual toolbar geometry without launching
/// or replacing the operator application or selecting physical hardware.
@Suite("Workbench native toolbar geometry", .serialized)
@MainActor
struct WorkbenchToolbarNativeLayoutTests {
  @Test("everyday toolbar destinations remain visible at the minimum window width")
  func minimumToolbarGeometry() async throws {
    _ = NSApplication.shared
    let log = EventLog()
    let application = plotterApplicationRuntime(machine: try LowerMachineSessionFixture(log: log), log: log)
    do {
      let projection = application.testPlotterUIProjection()
      #expect(projection.controllerSession.environment == .live)
      #expect(projection.controllerSession.motionAuthorizationUnavailableReason != nil)
      let layout = WorkbenchLayoutState(presented: [.motion, .drawing])
      let navigation = WorkbenchNavigationControls(layout: layout,
        reviewerIsPresented: false, selectDestination: { _ in })
      let measuredNavigation = NSHostingView(rootView: navigation.fixedSize())
      #expect(measuredNavigation.fittingSize.width <= 1000)
      let host = NSHostingController(rootView: VStack(spacing: 0) {
        navigation
        Divider()
        Color.clear
      }.frame(minWidth: 1000, minHeight: 300)
        .toolbar {
          WorkbenchToolbar(savedLearningAction: nil,
            controllerSession: projection.controllerSession, plotterUIProjection: projection.semantic,
            plotterUIIntentSink: application, diagnosticsAreExporting: false, exportDiagnostics: {})
        }.toolbarRole(.automatic))
      let window = NSWindow(contentRect: .init(x: -10000, y: -10000, width: 1000, height: 300),
        styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
      window.isReleasedWhenClosed = false
      window.contentViewController = host
      window.toolbarStyle = .unified
      window.orderFront(nil)
      defer { window.close() }
      for width in [1000, 1600] {
        window.setContentSize(.init(width: width, height: 300))
        for _ in 0..<12 {
          window.layoutIfNeeded()
          host.view.layoutSubtreeIfNeeded()
          await Task.yield()
          try await Task.sleep(for: .milliseconds(10))
        }
        let toolbar = try #require(window.toolbar, "SwiftUI must install a native NSToolbar")
        let visible = try #require(toolbar.visibleItems)
        for identifier in ["workbench.savedLearning", "workbench.stop", "workbench.controllerSession", "workbench.diagnostics"] {
          #expect(visible.contains { $0.itemIdentifier.rawValue == identifier },
            "The \(identifier) control overflowed at \(width) px")
        }
        #expect(window.frame.width <= CGFloat(width) + 1)
        // AX materialization is optional in the command-line host. Geometry and
        // native toolbar membership are mandatory; this is not an input receipt.
        let controls = descendants(host.view)
        if controls.contains(where: { $0.accessibilityIdentifier() == "workbench.navigation" }) {
          for destination in WorkbenchToolbarDestination.allCases {
            #expect(controls.contains { $0.accessibilityIdentifier() == "workbench.destination.\(destination.rawValue)" })
          }
        }
        if let path = ProcessInfo.processInfo.environment["ADAPTIVEPLOTTER_TOOLBAR_SNAPSHOT_PATH"],
          let chrome = window.contentView?.superview,
          let bitmap = chrome.bitmapImageRepForCachingDisplay(in: chrome.bounds) {
          chrome.cacheDisplay(in: chrome.bounds, to: bitmap)
          if let data = bitmap.representation(using: .png, properties: [:]) {
            let url = URL(fileURLWithPath: path).deletingPathExtension()
              .appendingPathExtension("\(width).png")
            try data.write(to: url)
          }
        }
      }
      await application.shutdown()
    } catch {
      await application.shutdown()
      throw error
    }
  }

  private func descendants(_ root: NSView?) -> [any NSAccessibilityProtocol] {
    guard let root else { return [] }
    func walk(_ element: any NSAccessibilityProtocol, depth: Int) -> [any NSAccessibilityProtocol] {
      guard depth < 20 else { return [] }
      let children = (element.accessibilityChildren() ?? []).compactMap { $0 as? any NSAccessibilityProtocol }
      return [element] + children.flatMap { walk($0, depth: depth + 1) }
    }
    return walk(root, depth: 0)
  }

}
