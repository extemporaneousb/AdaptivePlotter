import AppKit
import Observation
import SwiftUI
import Testing
@testable import PlotterApp

@Suite("Native workbench geometry", .serialized)
@MainActor
struct WorkbenchNativeLayoutTests {
  @Observable @MainActor
  final class Model { var layout = WorkbenchLayoutState(presented: []) }

  private struct Harness: View {
    @Bindable var model: Model
    var body: some View {
      WorkbenchPanels(layout: $model.layout, autosavePrefix: nil) { panel in
        ScrollView { Text(panel.title).frame(maxWidth: .infinity, minHeight: 700) }
      } canvas: {
        Color.black.overlay { Text("Permanent canvas").foregroundStyle(.white) }
      }
    }
  }

  @Test("native splits preserve the canvas and fit every opening at both supported widths")
  func nativeSplitGeometry() async throws {
    _ = NSApplication.shared
    let model = Model()
    let host = NSHostingController(rootView: Harness(model: model))
    let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 1000, height: 700),
      styleMask: [.borderless], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentViewController = host
    window.orderFront(nil)
    defer { window.close() }
    await settle(host.view)
    let workspace = try #require(splits(host.view).first { $0.hosts["canvas"] != nil })
    let canvas = try #require(workspace.hosts["canvas"])
    for width in [1000, 1600] {
      window.setContentSize(NSSize(width: width, height: 700))
      model.layout = WorkbenchLayoutState(presented: [])
      await settle(host.view)
      #expect(workspace.identities == ["canvas"])
      #expect(abs(canvas.frame.width - CGFloat(width)) < 2)
      for panel in WorkbenchPanel.allCases {
        model.layout.setPresented(panel, true)
        await settle(host.view)
        #expect(workspace.hosts["canvas"] === canvas)
        #expect(canvas.frame.width >= 319)
        #expect(workspace.bounds.width <= CGFloat(width) + 1)
        for dock in [WorkbenchDock.left, .right] {
          guard let columnHost = workspace.hosts[dock.rawValue] else { continue }
          let column = try #require(splits(columnHost).first)
          #expect(column.identities == model.layout.panels(in: dock).map(\.rawValue))
          #expect(column.bounds.width >= 299)
          #expect(abs(column.bounds.width - columnHost.frame.width) < 2)
          #expect(abs(column.bounds.height - 700) < 2)
          let ordered = column.subviews.map(\.frame)
          #expect(ordered.allSatisfy { $0.height >= 179 && $0.maxY <= 701 })
          #expect(abs(ordered.map(\.height).reduce(0, +)
            + column.dividerThickness * CGFloat(ordered.count - 1) - 700) < 2)
          if ordered.count == 2 {
            #expect(abs(ordered[0].height - ordered[1].height) < 2)
            #expect(ordered[0].intersection(ordered[1]).isEmpty)
          }
        }
      }
      for panel in WorkbenchPanel.allCases { model.layout.setPresented(panel, false) }
      await settle(host.view)
      #expect(workspace.hosts["canvas"] === canvas)
      #expect(abs(canvas.frame.width - CGFloat(width)) < 2)
    }
  }

  @Test("native divider constraints and autosave retain the chosen width")
  func dividerPersistence() async throws {
    let prefix = "AdaptivePlotter.test.\(UUID().uuidString)"
    let key = "NSSplitView Subview Frames \(prefix).workspace.canvas-right"
    defer { UserDefaults.standard.removeObject(forKey: key) }
    let children: [WorkbenchNativeSplit.Child] = [
      .init(id: "canvas", minimum: 320, ideal: 680, content: AnyView(Color.black)),
      .init(id: "right", minimum: 300, ideal: 340, content: AnyView(Text("Controls"))),
    ]
    let split = WorkbenchNativeSplit.NativeView(vertical: true)
    split.frame = NSRect(x: 0, y: 0, width: 1000, height: 700)
    split.update(name: "workspace", autosavePrefix: prefix, children: children)
    split.setPosition(560, ofDividerAt: 0)
    let chosen = split.subviews[0].frame.width
    #expect(abs(chosen - 560) < 2)
    let restored = WorkbenchNativeSplit.NativeView(vertical: true)
    restored.update(name: "workspace", autosavePrefix: prefix, children: children)
    restored.frame = split.frame
    await settle(restored)
    #expect(abs(restored.subviews[0].frame.width - chosen) < 2)
    restored.setPosition(5, ofDividerAt: 0)
    #expect(restored.subviews[0].frame.width >= 319)
    restored.setPosition(995, ofDividerAt: 0)
    #expect(restored.subviews[1].frame.width >= 299)
  }

  private func settle(_ view: NSView) async {
    view.window?.layoutIfNeeded()
    view.layoutSubtreeIfNeeded()
    try? await Task.sleep(for: .milliseconds(40))
    view.layoutSubtreeIfNeeded()
    view.window?.layoutIfNeeded()
    view.window?.display()
    view.display()
    view.layoutSubtreeIfNeeded()
  }

  private func splits(_ view: NSView) -> [WorkbenchNativeSplit.NativeView] {
    if let split = view as? WorkbenchNativeSplit.NativeView { return [split] }
    return view.subviews.flatMap(splits)
  }
}
