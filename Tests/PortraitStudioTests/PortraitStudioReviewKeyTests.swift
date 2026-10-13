import AppKit
import PortraitCore
import SwiftUI
import Testing
@testable import PortraitStudio

@Suite("Review keyboard admission", .serialized)
@MainActor
struct PortraitStudioReviewKeyTests {
  @Test("Only plain left/right and nonrepeated1–5 are review commands")
  func exactKeys() {
    #expect(PortraitStudioReviewKey.resolve(keyCode: 123, modifiers: [], isRepeat: false) == .previous)
    #expect(PortraitStudioReviewKey.resolve(keyCode: 124, modifiers: [.numericPad, .function], isRepeat: true) == .next)
    let codes: [UInt16] = [18, 19, 20, 21, 23]
    let choices: [PortraitReviewChoice] = [.a, .b, .tie, .neither, .skip]
    for (code, choice) in zip(codes, choices) {
      #expect(PortraitStudioReviewKey.resolve(keyCode: code, modifiers: [], isRepeat: false) == .score(choice))
      #expect(PortraitStudioReviewKey.resolve(keyCode: code, modifiers: [], isRepeat: true) == nil)
      for modifier in [NSEvent.ModifierFlags.command, .control, .option, .shift] {
        #expect(PortraitStudioReviewKey.resolve(keyCode: code, modifiers: modifier, isRepeat: false) == nil)
      }
    }
    #expect(PortraitStudioReviewKey.resolve(keyCode: 125, modifiers: [], isRepeat: false) == nil)
    #expect(PortraitStudioReviewKey.resolve(keyCode: 123, modifiers: .option, isRepeat: false) == nil)
  }

  @Test("Actual field editors and native/semantic value responders keep review keys")
  func editingControls() {
    _ = NSApplication.shared
    for responder in [NSTextView(), NSTextField(), NSSlider(), NSStepper(), NSPopUpButton(), NSComboBox(), NSSegmentedControl()] as [NSResponder] {
      #expect(PortraitStudioReviewKeyRouter.Coordinator.responderUsesReviewKeys(responder))
    }
    let semantic = NSView()
    for role in [NSAccessibility.Role.textField, .textArea, .slider, .popUpButton, .comboBox, .incrementor, .radioGroup] {
      semantic.setAccessibilityRole(role)
      #expect(PortraitStudioReviewKeyRouter.Coordinator.responderUsesReviewKeys(semantic))
    }
    let picker = NSPopUpButton()
    let leaf = NSView()
    picker.addSubview(leaf)
    #expect(PortraitStudioReviewKeyRouter.Coordinator.responderUsesReviewKeys(leaf))
    #expect(!PortraitStudioReviewKeyRouter.Coordinator.responderUsesReviewKeys(NSButton()))
  }

  @Test("Visibility, panel ownership, key/event windows and sheets gate commands without taking focus")
  func windowScope() throws {
    _ = NSApplication.shared
    let window = ReviewKeyTestWindow(contentRect: NSRect(x: -10000, y: -10000, width: 500, height: 300),
      styleMask: [.borderless], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    let content = NSView(frame: NSRect(x: 0, y: 0, width: 500, height: 300))
    let marker = PortraitStudioReviewKeyRouter.MarkerView(frame: NSRect(x: 0, y: 0, width: 300, height: 300))
    content.addSubview(marker); window.contentView = content
    window.orderFront(nil)
    defer { window.close() }
    let coordinator = PortraitStudioReviewKeyRouter.Coordinator()
    coordinator.view = marker
    var received: [PortraitStudioReviewKey] = []
    coordinator.handle = { received.append($0); return true }
    let key = try Self.key(in: window, code: 18)
    #expect(coordinator.receive(key) === key)
    coordinator.enabled = true; window.simulatesKeyWindow = true
    #expect(coordinator.receive(key) == nil)
    #expect(received == [.score(.a)])
    let field = NSTextField(frame: NSRect(x: 10, y: 10, width: 120, height: 24))
    content.addSubview(field)
    #expect(window.makeFirstResponder(field))
    #expect(coordinator.receive(key) === key)
    #expect(coordinator.receive(try Self.key(in: window, code: 123)) != nil)
    #expect(window.makeFirstResponder(nil))
    marker.isHidden = true
    #expect(coordinator.receive(key) === key)
    marker.isHidden = false
    window.simulatesKeyWindow = false
    #expect(coordinator.receive(key) === key)
    window.simulatesKeyWindow = true
    let sheet = NSWindow(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: false)
    sheet.isReleasedWhenClosed = false
    window.testSheet = sheet
    #expect(coordinator.receive(key) === key)
    window.testSheet = nil
    sheet.close()
    let outside = try #require(NSEvent.mouseEvent(with: .leftMouseDown, location: NSPoint(x: 400, y: 100),
      modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil,
      eventNumber: 1, clickCount: 1, pressure: 1))
    _ = coordinator.receive(outside)
    #expect(coordinator.receive(key) === key)
    let inside = try #require(NSEvent.mouseEvent(with: .leftMouseDown, location: NSPoint(x: 100, y: 100),
      modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil,
      eventNumber: 2, clickCount: 1, pressure: 1))
    _ = coordinator.receive(inside)
    #expect(coordinator.receive(key) == nil)
    coordinator.handle = { _ in false }
    #expect(coordinator.receive(key) === key)
    coordinator.remove()
    #expect(marker.hitTest(NSPoint(x: 50, y: 50)) == nil)
  }

  @Test("A focused native score button admits keys while a hosted SwiftUI picker retains them")
  func focusedButtonAndSwiftUIPicker() async throws {
    _ = NSApplication.shared
    let host = NSHostingView(rootView: Picker("Optional judgment", selection: Binding.constant(0)) {
      Text("Likeness").tag(0); Text("Expression").tag(1)
    }.pickerStyle(.menu).frame(width: 260, height: 60))
    let window = ReviewKeyTestWindow(contentRect: NSRect(x: -10000, y: -10000, width: 400, height: 200),
      styleMask: [.borderless], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    let content = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
    host.frame = NSRect(x: 0, y: 100, width: 260, height: 60); content.addSubview(host)
    let button = NSButton(title: "A", target: nil, action: nil)
    button.frame = NSRect(x: 10, y: 10, width: 60, height: 28); content.addSubview(button)
    let marker = PortraitStudioReviewKeyRouter.MarkerView(frame: content.bounds); content.addSubview(marker)
    window.contentView = content; window.orderFront(nil)
    defer { window.close() }
    for _ in 0..<3 { host.layoutSubtreeIfNeeded(); await Task.yield() }
    let picker = try #require(Self.views(host).compactMap { $0 as? NSPopUpButton }.first)
    let coordinator = PortraitStudioReviewKeyRouter.Coordinator()
    coordinator.view = marker; coordinator.enabled = true; window.simulatesKeyWindow = true
    var received: [PortraitStudioReviewKey] = []
    coordinator.handle = { received.append($0); return true }
    #expect(window.makeFirstResponder(button))
    #expect(window.firstResponder === button)
    let score = try Self.key(in: window, code: 19)
    #expect(coordinator.receive(score) == nil)
    #expect(received == [.score(.b)])
    #expect(window.makeFirstResponder(picker))
    #expect(window.firstResponder === picker)
    #expect(coordinator.receive(score) === score)
    let arrow = try Self.key(in: window, code: 124)
    #expect(coordinator.receive(arrow) === arrow)
    #expect(received == [.score(.b)])
  }

  @Test("A hosted segmented workspace picker retains both arrows and scoring numerals")
  func focusedSwiftUISegmentedPicker() async throws {
    _ = NSApplication.shared
    let host = NSHostingView(rootView: Picker("Workspace", selection: Binding.constant(0)) {
      Text("Studio").tag(0); Text("Review").tag(1)
    }.pickerStyle(.segmented).frame(width: 320, height: 60))
    let window = ReviewKeyTestWindow(contentRect: NSRect(x: -10000, y: -10000, width: 400, height: 200),
      styleMask: [.borderless], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    let content = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
    host.frame = NSRect(x: 0, y: 80, width: 320, height: 60); content.addSubview(host)
    let marker = PortraitStudioReviewKeyRouter.MarkerView(frame: content.bounds); content.addSubview(marker)
    window.contentView = content; window.orderFront(nil)
    defer { window.close() }
    for _ in 0..<3 { host.layoutSubtreeIfNeeded(); await Task.yield() }
    let picker = try #require(Self.views(host).compactMap { $0 as? NSSegmentedControl }.first)
    let coordinator = PortraitStudioReviewKeyRouter.Coordinator()
    coordinator.view = marker; coordinator.enabled = true; window.simulatesKeyWindow = true
    var received: [PortraitStudioReviewKey] = []
    coordinator.handle = { received.append($0); return true }
    #expect(window.makeFirstResponder(picker))
    #expect(window.firstResponder === picker)
    let codes: [UInt16] = [123, 124, 18, 19, 20, 21, 23]
    for code in codes {
      let event = try Self.key(in: window, code: code)
      #expect(coordinator.receive(event) === event)
    }
    #expect(received.isEmpty)
  }

  private static func key(in window: NSWindow, code: UInt16) throws -> NSEvent {
    try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
      timestamp: 0, windowNumber: window.windowNumber, context: nil, characters: "", charactersIgnoringModifiers: "",
      isARepeat: false, keyCode: code))
  }
  private static func views(_ root: NSView) -> [NSView] { [root] + root.subviews.flatMap(views) }
}

@MainActor
private final class ReviewKeyTestWindow: NSWindow {
  var simulatesKeyWindow = false
  var testSheet: NSWindow?
  override var isKeyWindow: Bool { simulatesKeyWindow }
  override var attachedSheet: NSWindow? { testSheet ?? super.attachedSheet }
}
