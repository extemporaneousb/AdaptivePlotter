import AppKit
import SwiftUI

/// One route owns these keys; button shortcuts would intercept Option-arrow
/// word movement before the text responder can handle it.
enum PortraitNavigationKey: Equatable {
  case previousPhoto, nextPhoto, previousDrawing, nextDrawing

  static func resolve(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> Self? {
    guard keyCode == 123 || keyCode == 124 else { return nil }
    let modifiers = modifiers.intersection([.command, .option, .control, .shift])
    guard modifiers.isEmpty || modifiers == .option else { return nil }
    if modifiers == .option { return keyCode == 123 ? .previousDrawing : .nextDrawing }
    return keyCode == 123 ? .previousPhoto : .nextPhoto
  }
}

/// The marker follows the Portrait panel's bounds and window. It never changes
/// first responder; normal text, value and menu editing retain native arrows.
struct PortraitNavigationKeyRouter: NSViewRepresentable {
  let enabled: Bool
  let handle: (PortraitNavigationKey) -> Bool
  var allowsParentKeyWindow = false

  func makeCoordinator() -> Coordinator { Coordinator() }
  func makeNSView(context: Context) -> NSView {
    let view = MarkerView()
    context.coordinator.view = view
    context.coordinator.install()
    return view
  }
  func updateNSView(_ nsView: NSView, context: Context) {
    context.coordinator.allowsParentKeyWindow = allowsParentKeyWindow
    context.coordinator.enabled = enabled
    context.coordinator.handle = handle
  }
  static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
    coordinator.remove()
  }

  final class MarkerView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
  }

  @MainActor
  final class Coordinator {
    weak var view: NSView?
    var enabled = false
    var allowsParentKeyWindow = false
    var handle: ((PortraitNavigationKey) -> Bool)?
    // Opening Portrait admits navigation immediately. Clicking a sibling panel
    // gives that panel ownership until the user clicks Portrait again.
    private var panelIsActive = true
    private var monitor: Any?

    func install() {
      monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .rightMouseDown]) { [weak self] event in
        let consumed = MainActor.assumeIsolated {
          guard let self else { return false }
          return self.receive(event) == nil
        }
        return consumed ? nil : event
      }
    }
    func remove() {
      if let monitor { NSEvent.removeMonitor(monitor) }
      monitor = nil
      handle = nil
    }
    func receive(_ event: NSEvent) -> NSEvent? {
      guard let view, let window = view.window, let eventWindow = event.window else { return event }
      if event.type == .leftMouseDown || event.type == .rightMouseDown {
        guard eventWindow === window else { return event }
        panelIsActive = view.bounds.contains(view.convert(event.locationInWindow, from: nil))
        return event
      }
      let ownedParentIsKey = allowsParentKeyWindow && window.parent?.isKeyWindow == true
      let comesFromOwnedParent = ownedParentIsKey && eventWindow === window.parent
      guard event.type == .keyDown, eventWindow === window || comesFromOwnedParent,
        enabled, panelIsActive, !view.isHiddenOrHasHiddenAncestor,
        (window.isKeyWindow || ownedParentIsKey),
        window.attachedSheet == nil, eventWindow.attachedSheet == nil,
        window.parent?.attachedSheet == nil, NSApp.modalWindow == nil,
        !Self.responderUsesArrows(eventWindow.firstResponder),
        let action = PortraitNavigationKey.resolve(keyCode: event.keyCode, modifiers: event.modifierFlags),
        handle?(action) == true else { return event }
      return nil
    }

    static func responderUsesArrows(_ responder: NSResponder?) -> Bool {
      if responder is NSTextView { return true }
      var view = responder as? NSView
      while let current = view {
        if current is NSTextField || current is NSSlider || current is NSStepper
          || current is NSPopUpButton || current is NSComboBox { return true }
        // SwiftUI controls need not be backed by the corresponding NSControl.
        if let role = current.accessibilityRole(),
          [NSAccessibility.Role.textField, .textArea, .slider, .popUpButton, .comboBox, .incrementor].contains(role) {
          return true
        }
        view = current.superview
      }
      return false
    }
  }
}
