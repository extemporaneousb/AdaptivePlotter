import AppKit
import Foundation
import DrawingLibrary
import PortraitCore
import PortraitLibrary
import PortraitStudioUI
import SwiftUI
import Testing
@testable import PortraitStudio

@Suite("DX08 shared Drawing browser authority", .serialized)
@MainActor
struct DrawingBrowserTests {
  @Test("Equal geometry remains two exact rows and an edit parents the selected occurrence")
  func exactOccurrenceSelection() async throws {
    let root = DrawingEditFixture.root(); defer { try? FileManager.default.removeItem(at: root) }
    let library = DrawingLibrary(directoryURL: root)
    let value = try DrawingEditFixture.value()
    let first = try await library.retain(value, title: "A", reason: "save")
    let second = try await library.retain(value, title: "B", reason: "save")
    let sketches = PortraitSketchCollection(library: library)
    let browser = DrawingLibraryBrowserModel(sketches: sketches)
    await sketches.load()
    #expect(Set(sketches.entries.map(\.reference)) == Set([first.reference, second.reference]))
    await browser.select(second.reference).value
    #expect(sketches.selectionID == .retained(second.reference))
    let editor = try #require(browser.beginEdit())
    #expect(editor.base.reference == second.reference)
    await editor.load(); editor.remove([try #require(value.program.strokes.first).id])
    #expect(await editor.save())
    let child = try #require(editor.savedDrawing)
    #expect(child.parent == .present(second.reference))
    #expect(browser.finishEdit(editor))
    #expect(sketches.selected?.reference == child.reference)
    #expect(browser.editor == nil)
    #expect(!browser.finishEdit(editor))
    #expect(try await library.drawings().entries.count == 3)
    browser.close(); await sketches.shutdown(); await library.closeLibrary()
  }

  @Test("Dismissal and a later equal-geometry selection refuse stale editor completion")
  func staleEditorAdoption() async throws {
    let root = DrawingEditFixture.root(); defer { try? FileManager.default.removeItem(at: root) }
    let library = DrawingLibrary(directoryURL: root)
    let value = try DrawingEditFixture.value()
    let first = try await library.retain(value, reason: "A"), second = try await library.retain(value, reason: "B")
    let sketches = PortraitSketchCollection(library: library)
    let browser = DrawingLibraryBrowserModel(sketches: sketches)
    await browser.select(first.reference).value
    let editor = try #require(browser.beginEdit())
    await editor.load(); editor.remove([try #require(value.program.strokes.first).id])
    #expect(await editor.save())
    await browser.select(second.reference).value
    #expect(!browser.finishEdit(editor))
    #expect(sketches.selected?.reference == second.reference)
    let next = try #require(browser.beginEdit()); await next.load()
    let count = try await library.drawings().entries.count
    browser.dismissEditor()
    #expect(next.isClosed && browser.editor == nil)
    #expect(!browser.finishEdit(next))
    #expect(try await library.drawings().entries.count == count)
    browser.close(); await sketches.shutdown(); await library.closeLibrary()
  }

  @Test("Unsupported Drawing-own features refuse edit and handoff while intrinsic source uncertainty remains editable")
  func capabilityBoundary() async throws {
    let root = DrawingEditFixture.root(); defer { try? FileManager.default.removeItem(at: root) }
    let library = DrawingLibrary(directoryURL: root.appendingPathComponent("library"))
    let own = try await DrawingEditFixture.imported(in: library, directory: root, unsupportedOwn: true)
    let source = try await DrawingEditFixture.imported(in: library, directory: root, uncertainSource: true)
    let sketches = PortraitSketchCollection(library: library)
    let browser = DrawingLibraryBrowserModel(sketches: sketches)
    await browser.select(try #require(own.drawing.reference)).value
    #expect(browser.beginEdit() == nil && browser.makeHandoffRequest() == nil)
    await browser.select(try #require(source.drawing.reference)).value
    #expect(!source.drawing.capabilities.sourceSemanticsSupported)
    #expect(browser.beginEdit() != nil)
    browser.dismissEditor()
    #expect(browser.makeHandoffRequest() != nil)
    browser.close(); await sketches.shutdown(); await library.closeLibrary()
  }

  @Test("Handoff token allows its own exact selection publication and rejects a different occurrence")
  func handoffToken() async throws {
    let root = DrawingEditFixture.root(); defer { try? FileManager.default.removeItem(at: root) }
    let library = DrawingLibrary(directoryURL: root)
    let value = try DrawingEditFixture.value()
    let first = try await library.retain(value, reason: "A"), second = try await library.retain(value, reason: "B")
    let sketches = PortraitSketchCollection(library: library)
    let browser = DrawingLibraryBrowserModel(sketches: sketches)
    await browser.select(first.reference).value
    let request = try #require(browser.makeHandoffRequest())
    #expect(request.isCurrent && request.drawing.reference == first.reference)
    var sent = false
    await browser.sendSelected { drawing, token in
      #expect(token.isCurrent && drawing.reference == first.reference)
      let epoch = sketches.selectionEpoch
      do { try sketches.selectLoaded(drawing) } catch { return error.localizedDescription }
      #expect(sketches.selectionEpoch > epoch)
      #expect(token.isCurrent)
      sent = true
      return nil
    }
    #expect(sent && browser.error == nil)
    let afterSend = try #require(browser.makeHandoffRequest())
    #expect(afterSend.isCurrent)
    await browser.select(second.reference).value
    #expect(!afterSend.isCurrent && !request.isCurrent)
    let next = try #require(browser.makeHandoffRequest())
    browser.close()
    #expect(!next.isCurrent)
    await sketches.shutdown(); await library.closeLibrary()
  }

  @Test("Browser metadata refresh never retains viewed geometry and leaves exact selection authority shared")
  func metadataBrowse() async throws {
    let root = DrawingEditFixture.root(); defer { try? FileManager.default.removeItem(at: root) }
    let library = DrawingLibrary(directoryURL: root)
    let value = try DrawingEditFixture.value()
    let first = try await library.retain(value, title: "Before", reason: "save")
    let sketches = PortraitSketchCollection(library: library)
    let browser = DrawingLibraryBrowserModel(sketches: sketches)
    await sketches.load(); await browser.select(first.reference).value
    let selected = sketches.selectionID
    try await sketches.rename(first.reference, title: "After")
    #expect(sketches.selectionID == selected && sketches.entries.first?.title == "After")
    #expect(try await library.drawings().entries.count == 1)
    let artwork = root.appendingPathComponent("objects"), held = root.appendingPathComponent("held")
    try FileManager.default.moveItem(at: artwork, to: held)
    await sketches.load()
    #expect(sketches.entries.first?.title == "After" && sketches.error == nil)
    try FileManager.default.moveItem(at: held, to: artwork)
    browser.close(); await sketches.shutdown(); await library.closeLibrary()
  }
  private func descendants(_ view: NSView) -> [NSView] {
    [view] + view.subviews.flatMap { descendants($0) }
  }
  private func accessibilityTree(_ root: any NSAccessibilityProtocol) -> [any NSAccessibilityProtocol] {
    var pending: [any NSAccessibilityProtocol] = [root]
    if let window = root as? NSWindow, let content = window.contentView {
      pending.append(content)
      pending += NSAccessibility.unignoredChildrenForOnlyChild(from: content).compactMap { $0 as? any NSAccessibilityProtocol }
    }
    var visited = Set<ObjectIdentifier>()
    var result: [any NSAccessibilityProtocol] = []
    while let element = pending.popLast(), result.count < 4096 {
      guard visited.insert(ObjectIdentifier(element)).inserted else { continue }
      result.append(element)
      pending += (element.accessibilityChildren() ?? []).compactMap { $0 as? any NSAccessibilityProtocol }.reversed()
    }
    return result
  }
  private func action(_ identifier: String, label: String, in window: NSWindow) -> (any NSAccessibilityProtocol)? {
    let buttons = accessibilityTree(window).filter { $0.accessibilityRole() == .button }
    return buttons.first { $0.accessibilityIdentifier() == identifier }
      ?? buttons.first { $0.accessibilityLabel() == label || ($0 as? NSButton)?.title == label }
  }
  private func enabled(_ element: any NSAccessibilityProtocol) -> Bool {
    if let control = element as? NSControl { return control.isEnabled }
    if element.responds(to: NSSelectorFromString("isAccessibilityEnabled")) { return element.isAccessibilityEnabled() }
    return true
  }
  private func actionDiagnostics(_ window: NSWindow) -> String {
    accessibilityTree(window).filter { $0.accessibilityRole() == .button }.prefix(40).map {
      "id=\($0.accessibilityIdentifier() ?? "nil") label=\($0.accessibilityLabel() ?? ($0 as? NSButton)?.title ?? "nil") enabled=\(enabled($0))"
    }.joined(separator: "; ")
  }
  private func press(_ identifier: String, label: String, in window: NSWindow) throws {
    let target = try #require(action(identifier, label: label, in: window), "Missing \(identifier). Actions: \(actionDiagnostics(window))")
    try #require(enabled(target), "Disabled \(identifier). Actions: \(actionDiagnostics(window))")
    try #require(target.accessibilityPerformPress(), "Press refused: \(identifier)")
  }
  private func pumpNativeUI() {
    _ = RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.005))
  }
  private func waitForUI(_ predicate: () -> Bool) async -> Bool {
    for _ in 0..<400 {
      if predicate() { return true }
      await Task.yield(); pumpNativeUI()
    }
    return predicate()
  }
  private func settleHostedView(_ view: NSView) async {
    for _ in 0..<8 {
      view.window?.layoutIfNeeded(); view.layoutSubtreeIfNeeded()
      view.window?.displayIfNeeded(); view.displayIfNeeded()
      try? await Task.sleep(for: .milliseconds(50))
    }
    view.layoutSubtreeIfNeeded(); view.window?.displayIfNeeded(); view.displayIfNeeded()
  }
  private func hostElementDiagnostics(_ elements: [any NSAccessibilityProtocol]) -> String {
    elements.prefix(64).map {
      "role=\(String(describing: $0.accessibilityRole())) id=\($0.accessibilityIdentifier() ?? "nil") label=\($0.accessibilityLabel() ?? "nil")"
    }.joined(separator: "; ")
  }
  private func diagnoseKnownHostedControl() async {
    let identifier = "dx08.hostProbe.knownButton"
    let host = NSHostingController(rootView: VStack {
      Text("Independent DX08 host probe")
      Button("Known DX08 Button") { }.accessibilityIdentifier(identifier)
    }.padding(12).background(Color(nsColor: .windowBackgroundColor)).environment(\.colorScheme, .light))
    host.sizingOptions = []
    let window = NSWindow(contentRect: .init(x: -10000, y: -10000, width: 320, height: 160),
      styleMask: [.borderless], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false; window.appearance = NSAppearance(named: .aqua)
    window.backgroundColor = .windowBackgroundColor; window.contentViewController = host
    window.setContentSize(.init(width: 320, height: 160)); window.orderFront(nil)
    defer { window.orderOut(nil); window.contentViewController = nil; window.close() }
    await settleHostedView(host.view)
    let before = accessibilityTree(window)
    print("DX08 independent host before initialization: found=\(before.contains { $0.accessibilityIdentifier() == identifier }) finished=\(NSRunningApplication.current.isFinishedLaunching) active=\(NSApp.isActive) key=\(window.isKeyWindow) elements=\(hostElementDiagnostics(before))")
    // Complete only this test process's ordinary AppKit initialization. This
    // launches no application process and neither activates nor keys a window.
    if !NSRunningApplication.current.isFinishedLaunching {
      NSApplication.shared.finishLaunching()
      await settleHostedView(host.view)
    }
    let after = accessibilityTree(window)
    print("DX08 independent host after initialization: found=\(after.contains { $0.accessibilityIdentifier() == identifier }) finished=\(NSRunningApplication.current.isFinishedLaunching) active=\(NSApp.isActive) key=\(window.isKeyWindow) elements=\(hostElementDiagnostics(after))")
    // The probe is diagnostic only. Production route assertions below remain
    // mandatory even if this host cannot expose the independent known button.
  }
  private func eraseFirstLine(_ canvas: PortraitLineEditorNSView) throws {
    let program = try #require(canvas.program)
    let geometry = PortraitLineSelectionGeometry(program: program, size: canvas.bounds.size)
    let line = try #require(geometry.lines.first)
    let start = try #require(line.points.first), end = try #require(line.points.last)
    let point = CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2)
    func event(_ type: NSEvent.EventType) throws -> NSEvent {
      try #require(NSEvent.mouseEvent(with: type, location: canvas.convert(point, to: nil), modifierFlags: [],
        timestamp: 0, windowNumber: canvas.window?.windowNumber ?? 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
    }
    canvas.mouseDown(with: try event(.leftMouseDown)); canvas.mouseUp(with: try event(.leftMouseUp))
  }

  @Test("AX-capable host: actual standalone Edit sheet, native canvas, Done and Cancel workflow",
    .enabled(if: ProcessInfo.processInfo.environment["PORTRAIT_NATIVE_AX_CHECK"] == "1"))
  func standaloneNativeEditorRoute() async throws {
    _ = NSApplication.shared
    await diagnoseKnownHostedControl()
    let root = DrawingEditFixture.root(); defer { try? FileManager.default.removeItem(at: root) }
    let library = DrawingLibrary(directoryURL: root)
    let acquisition = PortraitStudioModel(library: library)
    let dojo = FlowDojoModel(directory: root, library: library)
    let delegate = PortraitStudioApplicationDelegate()
    // Inspect/host the real browser property, not the main window body: this
    // performs no camera discovery, application launch or default-store access.
    let standalone = PortraitStudioDojoWindow(dojo: dojo, acquisition: acquisition, library: library, delegate: delegate)
    let shared = standalone.drawingBrowser
    #expect(shared.sketches === acquisition.sketches && shared.handoff == nil)
    let base = try await acquisition.sketches.retain(DrawingEditFixture.value(), reason: "save")
    let baseRef = try #require(base.reference)
    try acquisition.sketches.selectLoaded(base)
    await acquisition.sketches.load()
    let host = NSHostingController(rootView: shared.frame(width: 960, height: 700))
    host.sizingOptions = []
    let window = NSWindow(contentRect: .init(x: -10000, y: -10000, width: 960, height: 700),
      styleMask: [.titled, .closable], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false; window.appearance = NSAppearance(named: .aqua)
    window.backgroundColor = .windowBackgroundColor; window.contentViewController = host
    window.setContentSize(.init(width: 960, height: 700))
    defer {
      if let sheet = window.attachedSheet { window.endSheet(sheet); sheet.close() }
      window.orderOut(nil); window.contentViewController = nil; window.close()
    }
    window.orderFront(nil)
    await settleHostedView(host.view)
    print("DX08 production browser host: finished=\(NSRunningApplication.current.isFinishedLaunching) elements=\(hostElementDiagnostics(accessibilityTree(window)))")
    do {
      try #require(await waitForUI { self.action("drawing.library.edit", label: "Edit", in: window).map(self.enabled) == true },
        "Edit unavailable. Actions: \(actionDiagnostics(window))")
      try press("drawing.library.edit", label: "Edit", in: window)
      try #require(await waitForUI { window.attachedSheet != nil })
      let sheet = try #require(window.attachedSheet)
      if let content = sheet.contentView { await settleHostedView(content) }
      try #require(await waitForUI {
        guard let view = sheet.contentView else { return false }
        return self.descendants(view).compactMap { $0 as? PortraitLineEditorNSView }.contains { $0.model?.canEdit == true }
      })
      let sheetContent = try #require(sheet.contentView)
      let canvas = try #require(descendants(sheetContent).compactMap { $0 as? PortraitLineEditorNSView }.first)
      try eraseFirstLine(canvas)
      #expect(canvas.model?.removed.count == 1)
      try #require(await waitForUI { self.action("drawing.membershipEditor.done", label: "Done", in: sheet).map(self.enabled) == true },
        "Done unavailable. Actions: \(actionDiagnostics(sheet))")
      try press("drawing.membershipEditor.done", label: "Done", in: sheet)
      try #require(await waitForUI { window.attachedSheet == nil && acquisition.sketches.selected?.reference != baseRef })
      let child = try #require(acquisition.sketches.selected)
      #expect(child.parent == .present(baseRef))
      #expect(child.program.strokes == Array(base.program.strokes.dropFirst()))
      let count = try await library.drawings().entries.count
      #expect(count == 2)
      try press("drawing.library.edit", label: "Edit", in: window)
      try #require(await waitForUI { window.attachedSheet != nil })
      let cancelledSheet = try #require(window.attachedSheet)
      if let content = cancelledSheet.contentView { await settleHostedView(content) }
      try #require(await waitForUI { self.action("drawing.membershipEditor.cancel", label: "Cancel", in: cancelledSheet).map(self.enabled) == true },
        "Cancel unavailable. Actions: \(actionDiagnostics(cancelledSheet))")
      try press("drawing.membershipEditor.cancel", label: "Cancel", in: cancelledSheet)
      try #require(await waitForUI { window.attachedSheet == nil })
      #expect(acquisition.sketches.selected?.reference == child.reference)
      #expect(try await library.drawings().entries.count == count)
      window.orderOut(nil); window.contentViewController = nil
      _ = await dojo.shutdown(); await acquisition.shutdown(); await library.closeLibrary()
    } catch {
      window.orderOut(nil); window.contentViewController = nil
      _ = await dojo.shutdown(); await acquisition.shutdown(); await library.closeLibrary()
      throw error
    }
  }

  @Test("Standalone production constructors and native canvas integrate with model save/adoption without AX button or sheet claims")
  func standaloneNativeCanvasModelIntegration() async throws {
    _ = NSApplication.shared
    let root = DrawingEditFixture.root(); defer { try? FileManager.default.removeItem(at: root) }
    let library = DrawingLibrary(directoryURL: root)
    let acquisition = PortraitStudioModel(library: library)
    let dojo = FlowDojoModel(directory: root, library: library)
    let standalone = PortraitStudioDojoWindow(dojo: dojo, acquisition: acquisition, library: library,
      delegate: PortraitStudioApplicationDelegate())
    let shared = standalone.drawingBrowser
    #expect(shared.sketches === acquisition.sketches && shared.handoff == nil)
    let base = try await shared.sketches.retain(DrawingEditFixture.value(), reason: "save")
    let baseRef = try #require(base.reference)
    try shared.sketches.selectLoaded(base)
    await shared.sketches.load()
    let browserHost = NSHostingController(rootView: shared.frame(width: 960, height: 700))
    browserHost.sizingOptions = []
    let browserWindow = NSWindow(contentRect: .init(x: -10000, y: -10000, width: 960, height: 700),
      styleMask: [.borderless], backing: .buffered, defer: false)
    browserWindow.isReleasedWhenClosed = false; browserWindow.contentViewController = browserHost
    browserWindow.setContentSize(.init(width: 960, height: 700)); browserWindow.orderFront(nil)
    defer { browserWindow.orderOut(nil); browserWindow.contentViewController = nil; browserWindow.close() }
    let browser = DrawingLibraryBrowserModel(sketches: shared.sketches)
    var editorWindow: NSWindow?
    defer {
      editorWindow?.orderOut(nil); editorWindow?.contentViewController = nil; editorWindow?.close()
    }
    do {
      await settleHostedView(browserHost.view)
      #expect(browserHost.view.bounds.width > 0 && browserHost.view.bounds.height > 0)
      let editor = try #require(browser.beginEdit())
      #expect(editor.base.reference == baseRef)
      await editor.load()
      // This is the same production constructor used by the browser's sheet.
      // Save/adoption below deliberately use the real models, not AX controls.
      let editorView = DrawingMembershipEditor(model: editor, completion: { _ = browser.finishEdit(editor) },
        cancel: { browser.dismissEditor() })
      let editorHost = NSHostingController(rootView: editorView.frame(width: 900, height: 650))
      editorHost.sizingOptions = []
      let window = NSWindow(contentRect: .init(x: -10000, y: -10000, width: 900, height: 650),
        styleMask: [.borderless], backing: .buffered, defer: false)
      editorWindow = window; window.isReleasedWhenClosed = false; window.contentViewController = editorHost
      window.setContentSize(.init(width: 900, height: 650)); window.orderFront(nil)
      await settleHostedView(editorHost.view)
      try #require(await waitForUI {
        self.descendants(editorHost.view).compactMap { $0 as? PortraitLineEditorNSView }.contains { $0.model?.canEdit == true }
      })
      let canvas = try #require(descendants(editorHost.view).compactMap { $0 as? PortraitLineEditorNSView }.first)
      #expect(canvas.model === editor && canvas.program == base.program)
      #expect(canvas.bounds.width > 0 && canvas.bounds.height > 0)
      let frame = canvas.convert(canvas.bounds, to: editorHost.view)
      #expect(editorHost.view.bounds.insetBy(dx: -1, dy: -1).contains(frame))
      try eraseFirstLine(canvas)
      let firstStroke = try #require(base.program.strokes.first)
      #expect(editor.removed == [firstStroke.id])
      #expect(await editor.save())
      let saved = try #require(editor.savedDrawing)
      #expect(browser.finishEdit(editor))
      #expect(shared.sketches.selected?.reference == saved.reference)
      #expect(saved.parent == .present(baseRef) && saved.program.strokes == Array(base.program.strokes.dropFirst()))
      let count = try await library.drawings().entries.count
      #expect(count == 2)
      let cancelled = try #require(browser.beginEdit()); await cancelled.load()
      cancelled.remove([try #require(saved.program.strokes.first).id])
      #expect(cancelled.hasUnsavedChanges)
      browser.dismissEditor()
      #expect(cancelled.isClosed && browser.editor == nil)
      #expect(shared.sketches.selected?.reference == saved.reference)
      #expect(try await library.drawings().entries.count == count)
      browser.close()
      window.orderOut(nil); window.contentViewController = nil
      browserWindow.orderOut(nil); browserWindow.contentViewController = nil
      _ = await dojo.shutdown(); await acquisition.shutdown(); await library.closeLibrary()
    } catch {
      browser.close()
      editorWindow?.orderOut(nil); editorWindow?.contentViewController = nil
      browserWindow.orderOut(nil); browserWindow.contentViewController = nil
      _ = await dojo.shutdown(); await acquisition.shutdown(); await library.closeLibrary()
      throw error
    }
  }

}
