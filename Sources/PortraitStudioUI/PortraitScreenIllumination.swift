import AppKit
import SwiftUI

/// SwiftUI supplies the existing capture-light state. This bridge only presents
/// its white surface beyond the canvas, over the display containing this view's
/// host window. It never changes display brightness or camera ownership.
package struct PortraitScreenIllumination: NSViewRepresentable {
  package let isActive: Bool
  package let cancel: @MainActor () -> Void

  package func makeCoordinator() -> Coordinator { Coordinator() }

  package func makeNSView(context: Context) -> HostView {
    let view = HostView()
    view.windowChanged = { [weak coordinator = context.coordinator] window in
      coordinator?.setHostWindow(window)
    }
    return view
  }

  package func updateNSView(_ view: HostView, context: Context) {
    context.coordinator.update(isActive: isActive, cancel: cancel)
    context.coordinator.setHostWindow(view.window)
  }

  package static func dismantleNSView(_ view: HostView, coordinator: Coordinator) {
    view.windowChanged = nil
    coordinator.dismantle()
  }

  package final class HostView: NSView {
    package var windowChanged: ((NSWindow?) -> Void)?
    package override func viewDidMoveToWindow() {
      super.viewDidMoveToWindow()
      windowChanged?(window)
    }
    package override func hitTest(_ point: NSPoint) -> NSView? { nil }
  }

  @MainActor
  package final class Coordinator: NSObject {
    private let lifecycle = PortraitIlluminationLifecycle(presenter: PortraitIlluminationWindowPresenter())
    private weak var hostWindow: NSWindow?
    private var active = false
    private var cancel: @MainActor () -> Void = {}
    private let hostNotifications = [NSWindow.willCloseNotification, NSWindow.didMiniaturizeNotification,
      NSWindow.didChangeScreenNotification]

    package override init() {
      super.init()
      for name in [NSApplication.didResignActiveNotification, NSApplication.didHideNotification,
        NSApplication.willTerminateNotification, NSApplication.didChangeScreenParametersNotification] {
        NotificationCenter.default.addObserver(self, selector: #selector(interrupted), name: name, object: nil)
      }
    }

    package func update(isActive: Bool, cancel: @escaping @MainActor () -> Void) {
      active = isActive
      self.cancel = cancel
      refresh()
    }

    package func setHostWindow(_ window: NSWindow?) {
      guard hostWindow !== window else { return }
      if let previous = hostWindow {
        for name in hostNotifications {
          NotificationCenter.default.removeObserver(self, name: name, object: previous)
        }
        lifecycle.interrupt()
      }
      hostWindow = window
      if let window {
        for name in hostNotifications {
          NotificationCenter.default.addObserver(self, selector: #selector(interrupted), name: name, object: window)
        }
      }
      refresh()
    }

    private func refresh() {
      let frame = hostWindow.flatMap { $0.isVisible ? $0.screen?.frame : nil }
      lifecycle.update(isActive: active, screenFrame: frame,
        applicationIsActive: NSApplication.shared.isActive, cancel: cancel)
    }

    @objc private func interrupted(_ notification: Notification) { lifecycle.interrupt() }

    package func dismantle() {
      lifecycle.interrupt()
      NotificationCenter.default.removeObserver(self)
      hostWindow = nil
    }
  }

  package init(isActive: Bool, cancel: @escaping @MainActor () -> Void) {
    self.isActive = isActive
    self.cancel = cancel
  }
}

@MainActor
package protocol PortraitIlluminationPresenting: AnyObject {
  func show(frame: CGRect, cancel: @escaping @MainActor () -> Void)
  func dismiss()
}

/// Suppression lasts until the authoritative model goes inactive, so a queued
/// SwiftUI update cannot reopen a light that Escape or deactivation dismissed.
@MainActor
package final class PortraitIlluminationLifecycle {
  private let presenter: any PortraitIlluminationPresenting
  private var requestedActive = false
  private var suppressed = false
  private var presentedFrame: CGRect?
  private var cancel: @MainActor () -> Void = {}

  package init(presenter: any PortraitIlluminationPresenting) { self.presenter = presenter }

  package func update(isActive: Bool, screenFrame: CGRect?, applicationIsActive: Bool,
    cancel: @escaping @MainActor () -> Void) {
    requestedActive = isActive
    self.cancel = cancel
    guard isActive else {
      suppressed = false
      presentedFrame = nil
      presenter.dismiss()
      return
    }
    guard applicationIsActive else { interrupt(); return }
    guard !suppressed else { return }
    guard let screenFrame, !screenFrame.isEmpty else {
      if presentedFrame != nil { interrupt() }
      return
    }
    guard presentedFrame != screenFrame else { return }
    presentedFrame = screenFrame
    presenter.show(frame: screenFrame) { [weak self] in self?.interrupt() }
  }

  package func interrupt() {
    presentedFrame = nil
    presenter.dismiss()
    guard requestedActive, !suppressed else { return }
    suppressed = true
    cancel()
  }
}

@MainActor
private final class PortraitIlluminationWindowPresenter: PortraitIlluminationPresenting {
  private var window: PortraitIlluminationWindow?
  private weak var returnWindow: NSWindow?

  func show(frame: CGRect, cancel: @escaping @MainActor () -> Void) {
    if let window {
      window.setFrame(frame, display: true)
      return
    }
    returnWindow = NSApplication.shared.keyWindow
    let light = PortraitIlluminationWindow(contentRect: frame,
      styleMask: .borderless, backing: .buffered, defer: false)
    light.title = "Portrait Capture Light"
    light.backgroundColor = .white
    light.isOpaque = true
    light.hasShadow = false
    light.isReleasedWhenClosed = false
    light.hidesOnDeactivate = true
    light.animationBehavior = .none
    light.level = .screenSaver
    light.collectionBehavior = [.fullScreenAuxiliary, .transient, .ignoresCycle]
    light.cancel = cancel
    let content = NSHostingView(rootView: PortraitFullScreenLight(cancel: cancel))
    content.sizingOptions = []
    light.contentView = content
    light.setFrame(frame, display: false)
    window = light
    light.makeKeyAndOrderFront(nil)
  }

  func dismiss() {
    guard let window else { return }
    let wasKey = window.isKeyWindow
    self.window = nil
    window.cancel = nil
    window.orderOut(nil)
    window.close()
    if wasKey, NSApplication.shared.isActive, let returnWindow,
      returnWindow.isVisible, !returnWindow.isMiniaturized {
      returnWindow.makeKey()
    }
    returnWindow = nil
  }
}

package final class PortraitIlluminationWindow: NSWindow {
  package var cancel: (@MainActor () -> Void)?
  package override var canBecomeKey: Bool { true }
  package override var canBecomeMain: Bool { false }
  package override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
  package override func cancelOperation(_ sender: Any?) { cancel?() }
}

private struct PortraitFullScreenLight: View {
  let cancel: @MainActor () -> Void
  var body: some View {
    ZStack {
      Color.white.ignoresSafeArea()
      VStack(spacing: 12) {
        Text("Capturing portrait").font(.title2.weight(.semibold))
        Text("Turn slowly to capture several angles.").font(.body)
        Button("Cancel Capture · Esc", action: cancel)
          .keyboardShortcut(.cancelAction)
          .buttonStyle(.bordered)
          .controlSize(.large)
          .accessibilityIdentifier("portrait.cancelScreenIllumination")
      }
      .foregroundStyle(.black)
      .padding(24)
    }
    .environment(\.colorScheme, .light)
    .accessibilityIdentifier("portrait.screenIllumination")
  }
}
