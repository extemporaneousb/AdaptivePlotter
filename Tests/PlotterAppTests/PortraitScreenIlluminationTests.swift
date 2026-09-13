import AppKit
import Testing

@testable import PlotterApp

@Suite("Portrait display illumination lifecycle")
@MainActor
struct PortraitScreenIlluminationTests {
  @Test("illumination uses the complete host display frame and repeats do not reopen it")
  func hostDisplayGeometry() {
    let presenter = IlluminationPresenterProbe()
    let lifecycle = PortraitIlluminationLifecycle(presenter: presenter)
    let externalPortraitDisplay = CGRect(x: -1080, y: 200, width: 1080, height: 1920)
    for _ in 0..<3 {
      lifecycle.update(isActive: true, screenFrame: externalPortraitDisplay,
        applicationIsActive: true, cancel: {})
    }
    #expect(presenter.frames == [externalPortraitDisplay])
    lifecycle.update(isActive: false, screenFrame: externalPortraitDisplay,
      applicationIsActive: true, cancel: {})
    #expect(!presenter.isPresented)
  }

  @Test("Cancel suppresses queued active updates until the model acknowledges inactive")
  func cancellationCannotReopen() {
    let presenter = IlluminationPresenterProbe()
    let lifecycle = PortraitIlluminationLifecycle(presenter: presenter)
    let frame = CGRect(x: 0, y: 0, width: 1920, height: 1080)
    var cancellations = 0
    lifecycle.update(isActive: true, screenFrame: frame, applicationIsActive: true) { cancellations += 1 }
    presenter.cancel?()
    #expect(!presenter.isPresented)
    lifecycle.update(isActive: true, screenFrame: frame, applicationIsActive: true) { cancellations += 1 }
    lifecycle.interrupt()
    #expect(cancellations == 1)
    #expect(presenter.frames.count == 1)
    lifecycle.update(isActive: false, screenFrame: frame, applicationIsActive: true) { cancellations += 1 }
    lifecycle.update(isActive: true, screenFrame: frame, applicationIsActive: true) { cancellations += 1 }
    #expect(presenter.frames.count == 2)
  }

  @Test("deactivation or a disappearing host dismisses and cancels only the active capture")
  func interruption() {
    for removeHost in [false, true] {
      let presenter = IlluminationPresenterProbe()
      let lifecycle = PortraitIlluminationLifecycle(presenter: presenter)
      let frame = CGRect(x: 0, y: 0, width: 1920, height: 1080)
      var cancellations = 0
      lifecycle.update(isActive: true, screenFrame: frame, applicationIsActive: true) { cancellations += 1 }
      lifecycle.update(isActive: true, screenFrame: removeHost ? nil : frame,
        applicationIsActive: removeHost) { cancellations += 1 }
      #expect(!presenter.isPresented)
      #expect(cancellations == 1)
      lifecycle.interrupt()
      #expect(cancellations == 1)
    }
  }

  @Test("an inactive app cannot present a pending light after regaining focus")
  func backgroundRequest() {
    let presenter = IlluminationPresenterProbe()
    let lifecycle = PortraitIlluminationLifecycle(presenter: presenter)
    let frame = CGRect(x: 0, y: 0, width: 1920, height: 1080)
    var cancellations = 0
    lifecycle.update(isActive: true, screenFrame: frame, applicationIsActive: false) { cancellations += 1 }
    lifecycle.update(isActive: true, screenFrame: frame, applicationIsActive: true) { cancellations += 1 }
    #expect(presenter.frames.isEmpty)
    #expect(cancellations == 1)
  }

  @Test("the borderless light can receive Escape without becoming the app's main window")
  func escapeResponder() {
    _ = NSApplication.shared
    let window = PortraitIlluminationWindow(contentRect: .zero,
      styleMask: .borderless, backing: .buffered, defer: true)
    window.isReleasedWhenClosed = false
    var cancellations = 0
    window.cancel = { cancellations += 1 }
    #expect(window.canBecomeKey)
    #expect(!window.canBecomeMain)
    window.cancelOperation(nil)
    #expect(cancellations == 1)
    window.close()
  }
}

@MainActor
private final class IlluminationPresenterProbe: PortraitIlluminationPresenting {
  private(set) var frames: [CGRect] = []
  private(set) var isPresented = false
  var cancel: (@MainActor () -> Void)?
  func show(frame: CGRect, cancel: @escaping @MainActor () -> Void) {
    frames.append(frame)
    isPresented = true
    self.cancel = cancel
  }
  func dismiss() { isPresented = false }
}
