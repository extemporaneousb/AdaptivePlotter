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

  @Test("split selector introspection uses a separate retained delegate without sidebar recursion")
  func selectorIntrospectionAndDelegateLifetime() throws {
    _ = NSApplication.shared
    weak var weakOwner: WorkbenchNativeSplit.NativeView?
    weak var weakDelegate: AnyObject?
    var owner: WorkbenchNativeSplit.NativeView?
    var externallyRetainedDelegate: (any NSSplitViewDelegate)?
    try autoreleasepool {
      let split = WorkbenchNativeSplit.NativeView(vertical: true)
      owner = split
      weakOwner = split
      let delegate = try #require(split.delegate)
      // Check this before probing unknown selectors: the old self-delegate
      // configuration recursively entered AppKit's NSSplitViewSidebar category.
      try #require((delegate as AnyObject) !== split)
      weakDelegate = delegate as AnyObject
      for selectorName in [
        "splitView:resizeSubviewsWithOldSize:",
        "splitView:canCollapseSubview:",
        "splitView:constrainMinCoordinate:ofSubviewAt:",
        "splitView:constrainMaxCoordinate:ofSubviewAt:",
      ] {
        #expect(delegate.responds(to: NSSelectorFromString(selectorName)))
      }
      let unknown = NSSelectorFromString("adaptivePlotterUnknownSidebarSelectorForRegression:")
      #expect(!delegate.responds(to: unknown))
      #expect(!split.responds(to: unknown))
      // This exact sidebar query reproduces the production crash when the
      // split is its own delegate; an unrelated unknown selector does not.
      #expect(!split.responds(to: NSSelectorFromString("toggleSidebar:")))
      // Optional AppKit queries may change their result with the OS; the
      // regression is finite response without delegate-to-view recursion.
      for selectorName in [
        "splitView:shouldHideDividerAtIndex:",
        "splitView:effectiveRect:forDrawnRect:ofDividerAtIndex:",
        "accessibilityChildren",
        "accessibilityRole",
      ] {
        _ = split.responds(to: NSSelectorFromString(selectorName))
      }
    }
    #expect(weakOwner != nil)
    #expect(weakDelegate != nil, "NSSplitView's weak delegate requires a separate strong owner")
    externallyRetainedDelegate = owner?.delegate
    autoreleasepool { owner = nil }
    #expect(weakOwner == nil, "The retained delegate must refer weakly back to its split")
    #expect(weakDelegate != nil)
    #expect(externallyRetainedDelegate?.responds(to:
      NSSelectorFromString("adaptivePlotterUnknownSidebarSelectorForRegression:")) == false)
    autoreleasepool { externallyRetainedDelegate = nil }
    #expect(weakDelegate == nil, "No unrelated owner should retain the detached delegate")
  }

  @Test("retained delegates forward nested resize and divider constraints to stable hosts")
  func nestedDelegateForwarding() throws {
    _ = NSApplication.shared
    let workspace = WorkbenchNativeSplit.NativeView(vertical: true)
    workspace.frame = NSRect(x: 0, y: 0, width: 1000, height: 700)
    let children: [WorkbenchNativeSplit.Child] = [
      .init(id: "canvas", minimum: 320, ideal: 680, content: AnyView(Color.black)),
      .init(id: "right", minimum: 300, ideal: 340, children: [
        .init(id: "upper", minimum: 180, ideal: 340, content: AnyView(Text("Upper controls"))),
        .init(id: "lower", minimum: 180, ideal: 340, content: AnyView(Text("Lower controls"))),
      ]),
    ]
    workspace.update(name: "delegate-regression", autosavePrefix: nil, children: children)
    let canvas = try #require(workspace.hosts["canvas"])
    let column = try #require(workspace.hosts["right"] as? WorkbenchNativeSplit.NativeView)
    let upper = try #require(column.hosts["upper"])
    let lower = try #require(column.hosts["lower"])
    let outerDelegate = try #require(workspace.delegate)
    let innerDelegate = try #require(column.delegate)
    try #require((outerDelegate as AnyObject) !== workspace)
    try #require((innerDelegate as AnyObject) !== column)
    #expect((outerDelegate as AnyObject) !== (innerDelegate as AnyObject))
    for split in [workspace, column] {
      #expect(!split.responds(to: NSSelectorFromString("toggleSidebar:")))
      #expect(!split.responds(to: NSSelectorFromString("adaptivePlotterUnknownSidebarSelectorForRegression:")))
      // Exercise AppKit's actual accessibility entry point without asserting
      // availability or inventing a replacement accessibility tree.
      _ = split.accessibilityChildren()
    }
    #expect(outerDelegate.splitView?(workspace, canCollapseSubview: canvas) == false)
    #expect(innerDelegate.splitView?(column, canCollapseSubview: upper) == false)
    #expect(outerDelegate.splitView?(workspace, constrainMinCoordinate: 0, ofSubviewAt: 0) == 320)
    #expect(outerDelegate.splitView?(workspace, constrainMaxCoordinate: 2000, ofSubviewAt: 0)
      == column.frame.maxX - 300 - workspace.dividerThickness)
    #expect(innerDelegate.splitView?(column, constrainMinCoordinate: 0, ofSubviewAt: 0) == 180)
    #expect(innerDelegate.splitView?(column, constrainMaxCoordinate: 2000, ofSubviewAt: 0)
      == lower.frame.maxY - 180 - column.dividerThickness)

    let outerSize = workspace.bounds.size
    workspace.setFrameSize(NSSize(width: 1480, height: 900))
    outerDelegate.splitView?(workspace, resizeSubviewsWithOldSize: outerSize)
    innerDelegate.splitView?(column, resizeSubviewsWithOldSize: NSSize(width: 340, height: 700))
    #expect(workspace.hosts["canvas"] === canvas && workspace.hosts["right"] === column)
    #expect(column.hosts["upper"] === upper && column.hosts["lower"] === lower)
    #expect((workspace.delegate as AnyObject?) === (outerDelegate as AnyObject))
    #expect((column.delegate as AnyObject?) === (innerDelegate as AnyObject))
    #expect(abs(canvas.frame.width + column.frame.width + workspace.dividerThickness - 1480) < 1)
    #expect(canvas.frame.width >= 320 && column.frame.width >= 300)
    #expect(abs(column.frame.height - 900) < 1)
    #expect(abs(upper.frame.height + lower.frame.height + column.dividerThickness - 900) < 1)
    #expect(upper.frame.height >= 180 && lower.frame.height >= 180)
    #expect(upper.frame.intersection(lower.frame).isEmpty)
    workspace.setPosition(1, ofDividerAt: 0)
    #expect(canvas.frame.width >= 319)
    column.setPosition(1, ofDividerAt: 0)
    #expect(upper.frame.height >= 179)
    column.setPosition(899, ofDividerAt: 0)
    #expect(lower.frame.height >= 179)
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
