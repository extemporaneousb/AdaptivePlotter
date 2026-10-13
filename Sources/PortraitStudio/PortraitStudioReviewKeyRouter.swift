import AppKit
import PortraitCore
import SwiftUI

enum PortraitStudioReviewKey: Equatable {
  case previous, next, score(PortraitReviewChoice)

  static func resolve(keyCode: UInt16, modifiers: NSEvent.ModifierFlags, isRepeat: Bool) -> Self? {
    guard modifiers.intersection([.command, .option, .control, .shift]).isEmpty else { return nil }
    if keyCode == 123 { return .previous }
    if keyCode == 124 { return .next }
    guard !isRepeat else { return nil }
    switch keyCode {
    case 18: return .score(.a)
    case 19: return .score(.b)
    case 20: return .score(.tie)
    case 21: return .score(.neither)
    case 23: return .score(.skip)
    default: return nil
    }
  }
}

/// Local routing preserves the actual field editor and value-control responder.
/// The background marker neither takes focus nor intercepts pointer input.
struct PortraitStudioReviewKeyRouter: NSViewRepresentable {
  var enabled: Bool
  var handle: (PortraitStudioReviewKey) -> Bool

  func makeCoordinator() -> Coordinator { Coordinator() }
  func makeNSView(context: Context) -> NSView {
    let view = MarkerView()
    context.coordinator.view = view
    context.coordinator.install()
    return view
  }
  func updateNSView(_ nsView: NSView, context: Context) {
    context.coordinator.enabled = enabled
    context.coordinator.handle = handle
  }
  static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) { coordinator.remove() }

  final class MarkerView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
  }

  @MainActor final class Coordinator {
    weak var view: NSView?
    var enabled = false
    var handle: ((PortraitStudioReviewKey) -> Bool)?
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
      guard event.type == .keyDown, eventWindow === window, enabled, panelIsActive,
        !view.isHiddenOrHasHiddenAncestor, window.isKeyWindow,
        window.attachedSheet == nil, window.parent?.attachedSheet == nil, NSApp.modalWindow == nil,
        !Self.responderUsesReviewKeys(eventWindow.firstResponder),
        let key = PortraitStudioReviewKey.resolve(keyCode: event.keyCode,
          modifiers: event.modifierFlags, isRepeat: event.isARepeat), handle?(key) == true else { return event }
      return nil
    }

    static func responderUsesReviewKeys(_ responder: NSResponder?) -> Bool {
      if responder is NSTextView { return true }
      var view = responder as? NSView
      while let current = view {
        if current is NSTextField || current is NSSlider || current is NSStepper
          || current is NSPopUpButton || current is NSComboBox || current is NSSegmentedControl { return true }
        if let role = current.accessibilityRole(),
          [NSAccessibility.Role.textField, .textArea, .slider, .popUpButton, .comboBox, .incrementor, .radioGroup].contains(role) {
          return true
        }
        view = current.superview
      }
      return false
    }
  }
}
