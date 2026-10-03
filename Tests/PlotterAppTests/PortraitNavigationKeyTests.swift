import AppKit
import Testing
@testable import PlotterApp

@Suite("Portrait arrow routing")
@MainActor
struct PortraitNavigationKeyTests {
  @Test("unmodified arrows browse photos and Option arrows browse drawings")
  func exactModifiers() {
    #expect(PortraitNavigationKey.resolve(keyCode: 123, modifiers: []) == .previousPhoto)
    #expect(PortraitNavigationKey.resolve(keyCode: 124, modifiers: []) == .nextPhoto)
    #expect(PortraitNavigationKey.resolve(keyCode: 123, modifiers: [.option]) == .previousDrawing)
    #expect(PortraitNavigationKey.resolve(keyCode: 124, modifiers: [.option]) == .nextDrawing)
    #expect(PortraitNavigationKey.resolve(keyCode: 123, modifiers: [.numericPad, .function]) == .previousPhoto)
    let otherModifiers: [NSEvent.ModifierFlags] = [.command, .control, .shift, [.option, .shift], [.option, .command]]
    for modifiers in otherModifiers {
      #expect(PortraitNavigationKey.resolve(keyCode: 123, modifiers: modifiers) == nil)
      #expect(PortraitNavigationKey.resolve(keyCode: 124, modifiers: modifiers) == nil)
    }
    #expect(PortraitNavigationKey.resolve(keyCode: 125, modifiers: []) == nil)
    #expect(PortraitNavigationKey.resolve(keyCode: 126, modifiers: [.option]) == nil)
  }

  @Test("caret and native value editing retain their arrow keys")
  func editingResponders() {
    _ = NSApplication.shared
    for responder in [NSTextView(), NSTextField(), NSSlider(), NSStepper(), NSPopUpButton(), NSComboBox()] as [NSResponder] {
      #expect(PortraitNavigationKeyRouter.Coordinator.responderUsesArrows(responder))
    }
    let slider = NSSlider()
    let leaf = NSView()
    slider.addSubview(leaf)
    #expect(PortraitNavigationKeyRouter.Coordinator.responderUsesArrows(leaf))
    #expect(!PortraitNavigationKeyRouter.Coordinator.responderUsesArrows(NSButton()))
    #expect(!PortraitNavigationKeyRouter.Coordinator.responderUsesArrows(nil))
  }

  @Test("routing requires an active visible Portrait in the event window and consumes only admitted actions")
  func panelAndAdmissionScope() throws {
    _ = NSApplication.shared
    let window = NavigationTestWindow(contentRect: NSRect(x: -10000, y: -10000, width: 400, height: 300),
      styleMask: [.borderless], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    let content = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
    let marker = NSView(frame: NSRect(x: 0, y: 0, width: 200, height: 300))
    content.addSubview(marker)
    window.contentView = content
    window.orderFront(nil)
    defer { window.close() }
    let coordinator = PortraitNavigationKeyRouter.Coordinator()
    coordinator.view = marker
    var received: [PortraitNavigationKey] = []
    coordinator.handle = { received.append($0); return true }
    let key = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
      timestamp: 0, windowNumber: window.windowNumber, context: nil, characters: "", charactersIgnoringModifiers: "",
      isARepeat: false, keyCode: 123))
    #expect(coordinator.receive(key) === key)
    coordinator.enabled = true
    window.simulatesKeyWindow = true
    #expect(coordinator.receive(key) == nil)
    #expect(received == [.previousPhoto])
    let field = NSTextField(frame: NSRect(x: 10, y: 10, width: 100, height: 24))
    content.addSubview(field)
    #expect(window.makeFirstResponder(field))
    #expect(coordinator.receive(key) === key)
    let optionKey = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [.option],
      timestamp: 0, windowNumber: window.windowNumber, context: nil, characters: "", charactersIgnoringModifiers: "",
      isARepeat: false, keyCode: 123))
    #expect(coordinator.receive(optionKey) === optionKey)
    #expect(received == [.previousPhoto])
    #expect(window.makeFirstResponder(nil))
    coordinator.handle = { _ in false }
    #expect(coordinator.receive(key) === key)
    coordinator.handle = { received.append($0); return true }
    marker.isHidden = true
    #expect(coordinator.receive(key) === key)
    marker.isHidden = false
    window.simulatesKeyWindow = false
    #expect(coordinator.receive(key) === key)
    window.simulatesKeyWindow = true
    let outside = try #require(NSEvent.mouseEvent(with: .leftMouseDown, location: NSPoint(x: 300, y: 100),
      modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil,
      eventNumber: 1, clickCount: 1, pressure: 1))
    #expect(coordinator.receive(outside) === outside)
    #expect(coordinator.receive(key) === key)
    let inside = try #require(NSEvent.mouseEvent(with: .leftMouseDown, location: NSPoint(x: 100, y: 100),
      modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil,
      eventNumber: 2, clickCount: 1, pressure: 1))
    #expect(coordinator.receive(inside) === inside)
    #expect(coordinator.receive(key) == nil)
    #expect(received == [.previousPhoto, .previousPhoto])
    coordinator.remove()
    #expect(coordinator.receive(key) === key)
  }

  @Test("photo popovers admit their exact key parent and preserve the event window's text editing")
  func ownedParentRouting() throws {
    _ = NSApplication.shared
    func makeWindow() -> NavigationTestWindow {
      let window = NavigationTestWindow(contentRect: NSRect(x: -10000, y: -10000, width: 400, height: 300),
        styleMask: [.borderless], backing: .buffered, defer: false)
      window.isReleasedWhenClosed = false
      window.contentView = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
      window.orderFront(nil)
      return window
    }
    let parent = makeWindow()
    let popup = makeWindow()
    let unrelated = makeWindow()
    parent.addChildWindow(popup, ordered: .above)
    defer {
      parent.removeChildWindow(popup)
      popup.close()
      unrelated.close()
      parent.close()
    }
    parent.simulatesKeyWindow = true
    unrelated.simulatesKeyWindow = true
    let marker = NSView(frame: NSRect(x: 0, y: 0, width: 200, height: 300))
    popup.contentView?.addSubview(marker)
    let coordinator = PortraitNavigationKeyRouter.Coordinator()
    coordinator.view = marker
    coordinator.enabled = true
    var received: [PortraitNavigationKey] = []
    coordinator.handle = { received.append($0); return true }
    func key(in window: NSWindow, modifiers: NSEvent.ModifierFlags = []) throws -> NSEvent {
      try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers,
        timestamp: 0, windowNumber: window.windowNumber, context: nil, characters: "", charactersIgnoringModifiers: "",
        isARepeat: false, keyCode: 123))
    }
    let parentKey = try key(in: parent)
    let popupKey = try key(in: popup)
    let unrelatedKey = try key(in: unrelated)
    #expect(coordinator.receive(parentKey) === parentKey)
    coordinator.allowsParentKeyWindow = true
    #expect(coordinator.receive(parentKey) == nil)
    #expect(coordinator.receive(popupKey) == nil)
    #expect(coordinator.receive(unrelatedKey) === unrelatedKey)
    #expect(received == [.previousPhoto, .previousPhoto])
    let field = NSTextField(frame: NSRect(x: 10, y: 10, width: 100, height: 24))
    parent.contentView?.addSubview(field)
    #expect(parent.makeFirstResponder(field))
    #expect(coordinator.receive(parentKey) === parentKey)
    let optionKey = try key(in: parent, modifiers: [.option])
    #expect(coordinator.receive(optionKey) === optionKey)
    #expect(received == [.previousPhoto, .previousPhoto])
    #expect(parent.makeFirstResponder(nil))
    let parentClick = try #require(NSEvent.mouseEvent(with: .leftMouseDown, location: NSPoint(x: 300, y: 100),
      modifierFlags: [], timestamp: 0, windowNumber: parent.windowNumber, context: nil,
      eventNumber: 1, clickCount: 1, pressure: 1))
    #expect(coordinator.receive(parentClick) === parentClick)
    #expect(coordinator.receive(parentKey) == nil)
    parent.simulatesKeyWindow = false
    #expect(coordinator.receive(parentKey) === parentKey)
    #expect(coordinator.receive(popupKey) === popupKey)
    coordinator.remove()
  }

  @Test("the background marker cannot intercept pointer input")
  func transparentMarker() {
    let marker = PortraitNavigationKeyRouter.MarkerView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
    #expect(marker.hitTest(NSPoint(x: 50, y: 50)) == nil)
  }

  @Test("SwiftUI accessibility editing roles retain arrows without an NSControl")
  func semanticEditingResponder() {
    let view = NSView()
    view.setAccessibilityRole(.slider)
    #expect(PortraitNavigationKeyRouter.Coordinator.responderUsesArrows(view))
    view.setAccessibilityRole(.textField)
    #expect(PortraitNavigationKeyRouter.Coordinator.responderUsesArrows(view))
  }
}

/// Simulate activation without taking the operator's key window.
@MainActor
private final class NavigationTestWindow: NSWindow {
  var simulatesKeyWindow = false
  override var isKeyWindow: Bool { simulatesKeyWindow }
}
