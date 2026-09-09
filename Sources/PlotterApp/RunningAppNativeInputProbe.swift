import AppKit
import CoreGraphics
import Foundation
import QuartzCore

struct WorkbenchNativeInputSample: Codable, Equatable, Sendable {
  let targetIdentifier: String
  let postedUptimeSeconds: Double
  var eventUptimeSeconds: Double?
  var postedEventIdentity: Int64 = 0
  var dispatchedEventIdentity: Int64? = nil
  var handledEventIdentity: Int64? = nil
  var dispatchEntryUptimeSeconds: Double = 0
  var handlerUptimeSeconds: Double = 0
  var handlerSource = "existing application control callback"
  let handlerLatencyMilliseconds: Double
  let visibleAcknowledgmentLatencyMilliseconds: Double
  var scrollEvidence: WorkbenchNativeScrollEvidence? = nil
}

struct WorkbenchNativeScrollEvidence: Codable, Equatable, Sendable {
  let context: String?
  let controlIdentifier: String
  let clipIdentity: String
  let outerClipIdentities: [String]
  let beforeBounds: CGRect
  let afterBounds: CGRect
  let documentBounds: CGRect

  var provesInnerWheelMovement: Bool {
    !clipIdentity.isEmpty && !outerClipIdentities.isEmpty && !outerClipIdentities.contains(clipIdentity)
      && beforeBounds.size == afterBounds.size && beforeBounds.origin != afterBounds.origin
      && documentBounds.height > beforeBounds.height + 30
  }

  static func wheelDelta(clip: CGRect, document: CGRect, documentIsFlipped: Bool) -> Int32? {
    let minimum = document.minY
    let maximum = max(minimum, document.maxY - clip.height)
    if clip.minY > minimum + 1 { return documentIsFlipped ? 120 : -120 }
    if clip.minY < maximum - 1 { return documentIsFlipped ? -120 : 120 }
    return nil
  }
}

/// Geometry for the existing bottom-right resize gesture, in screen coordinates
/// where positive Y points down. Returning nil means no visible feasible drag.
struct WorkbenchNativeResizeGeometry {
  static func delta(content: CGSize, minimum: CGSize, window: CGRect, visibleScreen: CGRect) -> CGSize? {
    let dx: CGFloat = content.width - 45 >= minimum.width ? -45 : 45
    let dy: CGFloat = content.height - 25 >= minimum.height ? -25 : 25
    for delta in [CGSize(width: dx, height: dy), CGSize(width: dx, height: 0), CGSize(width: 0, height: dy)] {
      let resized = CGRect(x: window.minX, y: window.minY - delta.height,
        width: window.width + delta.width, height: window.height + delta.height)
      if content.width + delta.width >= minimum.width,
        content.height + delta.height >= minimum.height, visibleScreen.contains(resized) { return delta }
    }
    return nil
  }
}

struct WorkbenchNativeInputCounts: Codable, Equatable, Sendable {
  var posted = 0
  var dispatched = 0
  var handled = 0
  var acknowledged = 0
}

struct WorkbenchNativeControlVisibility: Codable, Equatable, Sendable {
  let identifier: String
  let frame: CGRect
  let containingClipCount: Int
  let scrolledClipCount: Int
  var panelIdentifier: String? = nil
  var fitsEveryContainingClip = false
}

/// Correlates this probe's native events without attributing a preceding or
/// unrelated event to whichever control happens to be pending.
struct WorkbenchNativeEventCorrelation: Equatable, Sendable {
  let expectedIdentity: Int64
  func accepts(_ identity: Int64?) -> Bool {
    expectedIdentity > 0 && identity == expectedIdentity
  }
}

enum WorkbenchNativeInputError: LocalizedError {
  case unavailable(String)
  var errorDescription: String? {
    switch self { case .unavailable(let detail): detail }
  }
}

/// Gate-only probe of existing controls. CGEvents are posted to this process
/// from a detached producer; the existing control handler and updated native
/// accessibility tree provide independent delivery and visible-state receipts.
/// These are synthesized native inputs, not attended physical mouse evidence.
@MainActor
final class RunningAppNativeInputProbe {
  private var handledEvent: (identifier: String, eventUptime: Double?, identity: Int64, handledUptime: Double)?
  private var dispatchEntry: (eventUptime: Double, identity: Int64, dispatchedUptime: Double)?
  private var pendingIdentifier: String?
  private var pendingEvent: WorkbenchNativeEventCorrelation?
  private static var nextEventIdentity: Int64 = 1
  private var eventMonitor: Any?
  private(set) var counts: [String: WorkbenchNativeInputCounts] = [:]
  private(set) var submittedInputCount = 0
  private(set) var deliveredInputCount = 0
  private(set) var acknowledgedInputCount = 0

  func install() {
    eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseUp, .leftMouseDragged, .scrollWheel]) { [weak self] event in
      if let self, let identifier = self.pendingIdentifier, self.dispatchEntry == nil,
        let identity = event.cgEvent?.getIntegerValueField(.eventSourceUserData),
        self.pendingEvent?.accepts(identity) == true {
        self.dispatchEntry = (event.timestamp, identity, ProcessInfo.processInfo.systemUptime)
        self.deliveredInputCount += 1
        self.counts[identifier, default: .init()].dispatched += 1
      }
      return event
    }
    WorkbenchRequestTelemetry.nativeActionObserver = { [weak self] identifier, timestamp in
      self?.recordHandler(identifier, eventTimestamp: timestamp)
    }
  }

  func uninstall() {
    WorkbenchRequestTelemetry.nativeActionObserver = nil
    if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }
    eventMonitor = nil
  }

  func hideMotion(reveal: @MainActor (WorkbenchPanel) -> Void) async throws -> WorkbenchNativeInputSample {
    reveal(.motion)
    return try await click("workbench.hide.motion") {
      Self.element(identifier: "workbench.panel.motion") == nil
    }
  }

  func click(_ identifier: String, handlerIdentifier: String? = nil,
             fractionX: Double = 0.5, menuKeyCodes: [UInt16] = [],
             replacementText: String? = nil,
             acknowledgment: () -> Bool) async throws -> WorkbenchNativeInputSample {
    guard CGPreflightPostEventAccess() else {
      throw WorkbenchNativeInputError.unavailable(
        "Native input gate cannot post mouse events. Grant the signed application Accessibility access, then rerun the gate.")
    }
    try await awaitCondition("The visible \(identifier) control is unavailable") {
      Self.element(identifier: identifier)?.isAccessibilityEnabled() == true
    }
    guard let target = Self.element(identifier: identifier),
      let window = NSApplication.shared.windows.first(where: { $0.isVisible && $0.contentView != nil })
    else { throw WorkbenchNativeInputError.unavailable("No visible workbench window or \(identifier) control is available.") }
    window.contentView?.layoutSubtreeIfNeeded()
    window.displayIfNeeded()
    Self.revealControl(target, in: window)
    let frame = target.accessibilityFrame()
    let nativePoint = CGPoint(x: frame.minX + frame.width * fractionX, y: frame.midY)
    guard frame.width > 0, frame.height > 0, target.isAccessibilityEnabled(),
      Self.visibleHit(target: target, point: nativePoint, window: window), let screen = NSScreen.screens.first
    else { throw WorkbenchNativeInputError.unavailable("\(identifier) has no enabled, unclipped native hit target at the requested point.") }
    let point = CGPoint(x: nativePoint.x, y: screen.frame.maxY - nativePoint.y)
    handledEvent = nil
    dispatchEntry = nil
    let receiptIdentifier = handlerIdentifier ?? identifier
    pendingIdentifier = receiptIdentifier
    let identity = beginEvent()
    defer { pendingIdentifier = nil; pendingEvent = nil }
    let posted = try await Self.postMouseClick(at: point, keyCodes: menuKeyCodes, replacementText: replacementText, identity: identity)
    return try await acknowledge(posted: posted, identifier: receiptIdentifier, window: window, acknowledgment: acknowledgment)
  }

  private func recordHandler(_ identifier: String, eventTimestamp: Double?) {
    guard identifier == pendingIdentifier, handledEvent == nil,
      let identity = NSApp.currentEvent?.cgEvent?.getIntegerValueField(.eventSourceUserData),
      pendingEvent?.accepts(identity) == true else { return }
    handledEvent = (identifier, eventTimestamp, identity, ProcessInfo.processInfo.systemUptime)
    counts[identifier, default: .init()].handled += 1
  }

  private func acknowledge(posted: Double, identifier: String, window: NSWindow,
    acknowledgment: () -> Bool) async throws -> WorkbenchNativeInputSample {
    submittedInputCount += 1
    counts[identifier, default: .init()].posted += 1
    try await awaitCondition("The native \(identifier) event received no control-handler acknowledgment") {
      self.handledEvent?.identifier == identifier
    }
    guard let handledEvent, let dispatchEntry,
      pendingEvent?.accepts(dispatchEntry.identity) == true,
      pendingEvent?.accepts(handledEvent.identity) == true,
      handledEvent.eventUptime != nil
    else { throw WorkbenchNativeInputError.unavailable("The control handler did not identify the posted native mouse event.") }
    try await awaitCondition("\(identifier) produced no visible acknowledgment after its native handler") {
      window.contentView?.layoutSubtreeIfNeeded()
      window.displayIfNeeded()
      CATransaction.flush()
      return acknowledgment()
    }
    acknowledgedInputCount += 1
    counts[identifier, default: .init()].acknowledged += 1
    return WorkbenchNativeInputSample(targetIdentifier: identifier,
      postedUptimeSeconds: posted, eventUptimeSeconds: handledEvent.eventUptime,
      postedEventIdentity: pendingEvent?.expectedIdentity ?? 0,
      dispatchedEventIdentity: dispatchEntry.identity, handledEventIdentity: handledEvent.identity,
      dispatchEntryUptimeSeconds: dispatchEntry.dispatchedUptime, handlerUptimeSeconds: handledEvent.handledUptime,
      handlerLatencyMilliseconds: (handledEvent.handledUptime - posted) * 1_000,
      visibleAcknowledgmentLatencyMilliseconds: (ProcessInfo.processInfo.systemUptime - posted) * 1_000)
  }

  private func beginEvent() -> Int64 {
    let identity = Self.nextEventIdentity
    Self.nextEventIdentity += 1
    pendingEvent = WorkbenchNativeEventCorrelation(expectedIdentity: identity)
    return identity
  }

  func scrollWorkbench(innerControl: String? = nil, context: String? = nil) async throws -> WorkbenchNativeInputSample {
    guard let window = NSApplication.shared.windows.first(where: { $0.isVisible && $0.contentView != nil }),
      let root = window.contentView, let screen = NSScreen.screens.first else {
      throw WorkbenchNativeInputError.unavailable("No visible workbench is available for native scrolling.")
    }
    @MainActor func views(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(views) }
    let scrolls = views(root).compactMap { $0 as? NSScrollView }.filter {
      guard let document = $0.documentView else { return false }
      return document.bounds.height > $0.contentView.bounds.height + 30
        && window.frame.contains($0.accessibilityFrame())
    }
    let selected: NSScrollView?
    if let innerControl {
      guard let target = Self.element(identifier: innerControl) else {
        throw WorkbenchNativeInputError.unavailable("Missing inner scroll control \(innerControl).")
      }
      // This setup reveal is completed before native event bookkeeping begins.
      Self.revealControl(target, in: window)
      selected = Self.containingScrollViews(target, in: window).first { scroll in
        guard let document = scroll.documentView else { return false }
        return document.bounds.height > scroll.contentView.bounds.height + 30
          && !Self.outerScrollClipIdentities(of: scroll).isEmpty
      }
    } else { selected = scrolls.max(by: { $0.frame.height < $1.frame.height }) }
    guard let scroll = selected, let document = scroll.documentView else {
      throw WorkbenchNativeInputError.unavailable("No visible overflowing workbench body is available for the native scroll workload.")
    }
    let clip = scroll.contentView
    let beforeBounds = clip.bounds
    let before = beforeBounds.origin
    guard let wheelDelta = WorkbenchNativeScrollEvidence.wheelDelta(clip: beforeBounds,
      document: document.bounds, documentIsFlipped: document.isFlipped) else {
      throw WorkbenchNativeInputError.unavailable("The identified scroll clip has no available native wheel direction.")
    }
    var frame = window.convertToScreen(clip.convert(clip.bounds, to: nil)).intersection(window.frame)
    var ancestor = scroll.superview
    while let view = ancestor {
      if let outer = view as? NSScrollView {
        frame = frame.intersection(window.convertToScreen(outer.contentView.convert(outer.contentView.bounds, to: nil)))
      }
      ancestor = view.superview
    }
    let nativePoint = CGPoint(x: frame.midX, y: frame.midY)
    guard !frame.isEmpty, Self.visibleHit(target: scroll, point: nativePoint, window: window) else {
      throw WorkbenchNativeInputError.unavailable("The scroll body has no unobstructed native hit target.")
    }
    let identifier = innerControl == nil ? "workbench.scroll" : "workbench.scroll.inner"
    handledEvent = nil; dispatchEntry = nil; pendingIdentifier = identifier
    let identity = beginEvent()
    let originallyPosts = clip.postsBoundsChangedNotifications
    clip.postsBoundsChangedNotifications = true
    let observer = NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification, object: clip, queue: .main) { [weak self] _ in
      MainActor.assumeIsolated {
        guard let self, self.dispatchEntry != nil else { return }
        self.recordHandler(identifier, eventTimestamp: NSApplication.shared.currentEvent?.timestamp)
      }
    }
    defer {
      NotificationCenter.default.removeObserver(observer)
      clip.postsBoundsChangedNotifications = originallyPosts
      pendingIdentifier = nil
      pendingEvent = nil
    }
    let posted = try await Self.postViewportInput(at: CGPoint(x: nativePoint.x, y: screen.frame.maxY - nativePoint.y),
      scrollDelta: wheelDelta, identity: identity)
    var sample = try await acknowledge(posted: posted, identifier: identifier, window: window) { clip.bounds.origin != before }
    sample.handlerSource = "AppKit NSClipView bounds-change notification from native scroll dispatch"
    sample.scrollEvidence = WorkbenchNativeScrollEvidence(context: context,
      controlIdentifier: innerControl ?? "workbench", clipIdentity: Self.clipIdentity(clip),
      outerClipIdentities: Self.outerScrollClipIdentities(of: scroll),
      beforeBounds: beforeBounds, afterBounds: clip.bounds, documentBounds: document.bounds)
    return sample
  }

  private static func clipIdentity(_ clip: NSClipView) -> String {
    String(UInt(bitPattern: ObjectIdentifier(clip)), radix: 16)
  }

  private static func outerScrollClipIdentities(of scroll: NSScrollView) -> [String] {
    var identities: [String] = []
    var ancestor = scroll.superview
    while let view = ancestor {
      if let outer = view as? NSScrollView { identities.append(clipIdentity(outer.contentView)) }
      ancestor = view.superview
    }
    return identities
  }

  func resizeWorkbench() async throws -> WorkbenchNativeInputSample {
    guard let window = NSApplication.shared.windows.first(where: { $0.isVisible && $0.styleMask.contains(.resizable) }),
      let screen = window.screen ?? NSScreen.screens.first,
      let originalContent = window.contentView?.bounds.size else {
      throw WorkbenchNativeInputError.unavailable("No visible resizable workbench window is available.")
    }
    let original = window.frame
    let minimum = CGSize(width: max(window.contentMinSize.width, LearningWorkbenchLayoutPolicy.minimumWindowWidth),
      height: max(window.contentMinSize.height, AdaptivePlotterScenePolicy.minimumWindowHeight))
    guard let delta = WorkbenchNativeResizeGeometry.delta(content: originalContent, minimum: minimum,
      window: original, visibleScreen: screen.visibleFrame) else {
      throw WorkbenchNativeInputError.unavailable("No onscreen resize endpoint respects the workbench minimum size.")
    }
    let point = CGPoint(x: original.maxX - 2, y: (NSScreen.screens.first?.frame.maxY ?? screen.frame.maxY) - original.minY - 2)
    let end = CGPoint(x: point.x + delta.width, y: point.y + delta.height)
    let identifier = "workbench.resize"
    handledEvent = nil; dispatchEntry = nil; pendingIdentifier = identifier
    let identity = beginEvent()
    let observer = NotificationCenter.default.addObserver(forName: NSWindow.didResizeNotification, object: window, queue: .main) { [weak self] _ in
      MainActor.assumeIsolated {
        guard let self, self.dispatchEntry != nil else { return }
        self.recordHandler(identifier, eventTimestamp: NSApplication.shared.currentEvent?.timestamp)
      }
    }
    defer {
      NotificationCenter.default.removeObserver(observer)
      pendingIdentifier = nil
      pendingEvent = nil
      window.setFrame(original, display: true)
    }
    let posted = try await Self.postViewportInput(at: point, resizeTo: end, identity: identity)
    var sample = try await acknowledge(posted: posted, identifier: identifier, window: window) {
      window.frame.size != original.size && window.contentView?.bounds.size != originalContent
    }
    sample.handlerSource = "AppKit NSWindow resize notification from native border drag"
    return sample
  }

  static func panelText() -> [String: [String]] {
    var result: [String: [String]] = [:]
    for panel in WorkbenchPanel.allCases {
      guard let element = element(identifier: "workbench.panel.\(panel.rawValue)") else { continue }
      result[panel.rawValue] = descendants(element).compactMap { item in
        guard item.accessibilityRole() == .staticText else { return nil }
        return (item.accessibilityValue() as? String) ?? item.accessibilityLabel()
      }.sorted()
    }
    return result
  }

  static var stopIsPresent: Bool { element(identifier: "workbench.stop") != nil }

  static func controlValue(_ identifier: String) -> String? {
    element(identifier: identifier).map {
      "\($0.accessibilityValue() ?? "")|enabled=\($0.isAccessibilityEnabled())"
    }
  }

  static func controlLabel(_ identifier: String) -> String? { element(identifier: identifier)?.accessibilityLabel() }

  static func controlFrame(_ identifier: String) -> CGRect? { element(identifier: identifier)?.accessibilityFrame() }

  static func controlIsInside(_ identifier: String, container: String) -> Bool {
    guard let parent = element(identifier: container) else { return false }
    return descendants(parent).contains { $0.accessibilityIdentifier() == identifier }
  }

  /// A disabled Draw or Pen control must still be fully visible and hit-testable.
  /// This inspection never presses it or counts setup scrolling as native input.
  static func inspectControl(_ identifier: String, in window: NSWindow,
    panelIdentifier: String? = nil) throws -> WorkbenchNativeControlVisibility {
    guard let target = element(identifier: identifier) else {
      throw WorkbenchNativeInputError.unavailable("Missing native body/header control: \(identifier).")
    }
    if let panelIdentifier, !controlIsInside(identifier, container: panelIdentifier) {
      throw WorkbenchNativeInputError.unavailable("\(identifier) is not inside its declared \(panelIdentifier) panel.")
    }
    let scrolls = containingScrollViews(target, in: window)
    let before = scrolls.map { $0.contentView.bounds.origin }
    revealControl(target, in: window)
    let frame = target.accessibilityFrame()
    guard frame.width > 0, frame.height > 0, window.frame.contains(frame),
      NSScreen.screens.contains(where: { $0.visibleFrame.contains(frame) }),
      visibleHit(target: target, point: CGPoint(x: frame.midX, y: frame.midY), window: window)
    else { throw WorkbenchNativeInputError.unavailable("\(identifier) has no fully onscreen native hit target.") }
    for scroll in scrolls {
      let clip = window.convertToScreen(scroll.contentView.convert(scroll.contentView.bounds, to: nil))
        .insetBy(dx: -1, dy: -1)
      guard clip.contains(frame) else {
        throw WorkbenchNativeInputError.unavailable("\(identifier) is clipped by a containing native scroll view.")
      }
    }
    return WorkbenchNativeControlVisibility(identifier: identifier, frame: frame,
      containingClipCount: scrolls.count,
      scrolledClipCount: zip(scrolls, before).filter { $0.0.contentView.bounds.origin != $0.1 }.count,
      panelIdentifier: panelIdentifier, fitsEveryContainingClip: true)
  }

  private static func containingScrollViews(_ target: any NSAccessibilityProtocol, in window: NSWindow) -> [NSScrollView] {
    guard let root = window.contentView else { return [] }
    @MainActor func views(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(views) }
    let scrolls = views(root).compactMap { $0 as? NSScrollView }.filter { scroll in
      guard let document = scroll.documentView else { return false }
      return descendants(document).contains {
        ObjectIdentifier($0) == ObjectIdentifier(target)
          || (target.accessibilityIdentifier() != nil && $0.accessibilityIdentifier() == target.accessibilityIdentifier())
      }
    }
    return Array(scrolls.reversed())
  }

  private static func revealControl(_ target: any NSAccessibilityProtocol, in window: NSWindow) {
    guard let root = window.contentView else { return }
    // Preparation only; this is never counted as a native input sample.
    for scroll in containingScrollViews(target, in: window) {
      guard let document = scroll.documentView else { continue }
      let rect = document.convert(window.convertFromScreen(target.accessibilityFrame()), from: nil)
      document.scrollToVisible(rect.insetBy(dx: -6, dy: -6))
      scroll.reflectScrolledClipView(scroll.contentView)
      root.layoutSubtreeIfNeeded()
    }
    root.layoutSubtreeIfNeeded()
    window.displayIfNeeded()
  }

  private static func visibleHit(target: any NSAccessibilityProtocol, point: CGPoint, window: NSWindow) -> Bool {
    guard window.frame.contains(point) else { return false }
    var ancestor: (any NSAccessibilityProtocol)? = target
    while let current = ancestor {
      if current.accessibilityRole() == .scrollArea, !current.accessibilityFrame().contains(point) { return false }
      ancestor = current.accessibilityParent() as? any NSAccessibilityProtocol
    }
    guard var hit = window.accessibilityHitTest(point) as? any NSAccessibilityProtocol else { return false }
    for _ in 0..<30 {
      if ObjectIdentifier(hit) == ObjectIdentifier(target) { return true }
      if let identifier = target.accessibilityIdentifier(), hit.accessibilityIdentifier() == identifier { return true }
      guard let parent = hit.accessibilityParent() as? any NSAccessibilityProtocol else { break }
      hit = parent
    }
    return false
  }

  private static func element(identifier: String) -> (any NSAccessibilityProtocol)? {
    for window in NSApplication.shared.windows where window.isVisible {
      if let found = descendants(window).first(where: { $0.accessibilityIdentifier() == identifier }) {
        return found
      }
    }
    return nil
  }

  private static func descendants(_ root: any NSAccessibilityProtocol) -> [any NSAccessibilityProtocol] {
    var result: [any NSAccessibilityProtocol] = []
    var pending: [any NSAccessibilityProtocol] = [root]
    var visited: Set<ObjectIdentifier> = []
    while let element = pending.popLast(), result.count < 4_096 {
      guard visited.insert(ObjectIdentifier(element)).inserted else { continue }
      result.append(element)
      pending.append(contentsOf: (element.accessibilityChildren() ?? []).compactMap { $0 as? any NSAccessibilityProtocol })
    }
    return result
  }

  private func awaitCondition(_ failure: String, condition: () -> Bool) async throws {
    let deadline = ContinuousClock.now.advanced(by: .seconds(3))
    while !condition() {
      guard ContinuousClock.now < deadline else { throw WorkbenchNativeInputError.unavailable(failure) }
      try await Task.sleep(for: .milliseconds(5))
    }
  }

  private nonisolated static func postMouseClick(at point: CGPoint, keyCodes: [UInt16], replacementText: String?, identity: Int64) async throws -> Double {
    try await Task.detached(priority: .userInitiated) {
      guard let down = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown,
                               mouseCursorPosition: point, mouseButton: .left),
        let up = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp,
                         mouseCursorPosition: point, mouseButton: .left)
      else { throw WorkbenchNativeInputError.unavailable("Could not construct native mouse events.") }
      let posted = ProcessInfo.processInfo.systemUptime
      down.setIntegerValueField(.eventSourceUserData, value: identity)
      up.setIntegerValueField(.eventSourceUserData, value: identity)
      down.postToPid(ProcessInfo.processInfo.processIdentifier)
      up.postToPid(ProcessInfo.processInfo.processIdentifier)
      if let replacementText {
        // Only the existing bounded-motion numeric fields use this operation.
        for isDown in [true, false] {
          guard let select = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: isDown) else {
            throw WorkbenchNativeInputError.unavailable("Could not construct Select All for the motion field.")
          }
          select.flags = .maskCommand
          select.setIntegerValueField(.eventSourceUserData, value: identity)
          select.postToPid(ProcessInfo.processInfo.processIdentifier)
        }
        let characters = Array(replacementText.utf16)
        for isDown in [true, false] {
          guard let text = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: isDown) else {
            throw WorkbenchNativeInputError.unavailable("Could not construct numeric motion-field input.")
          }
          text.keyboardSetUnicodeString(stringLength: characters.count, unicodeString: characters)
          text.setIntegerValueField(.eventSourceUserData, value: identity)
          text.postToPid(ProcessInfo.processInfo.processIdentifier)
        }
      }
      for keyCode in keyCodes {
        for isDown in [true, false] {
          guard let key = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: isDown) else {
            throw WorkbenchNativeInputError.unavailable("Could not construct native menu keyboard events.")
          }
          key.setIntegerValueField(.eventSourceUserData, value: identity)
          key.postToPid(ProcessInfo.processInfo.processIdentifier)
        }
      }
      return posted
    }.value
  }

  private nonisolated static func postViewportInput(at point: CGPoint, resizeTo end: CGPoint? = nil,
    scrollDelta: Int32 = 0, identity: Int64) async throws -> Double {
    try await Task.detached(priority: .userInitiated) {
      var events: [CGEvent] = []
      if let end {
        for (kind, location) in [(CGEventType.leftMouseDown, point), (.leftMouseDragged, end), (.leftMouseUp, end)] {
          guard let event = CGEvent(mouseEventSource: nil, mouseType: kind, mouseCursorPosition: location, mouseButton: .left) else {
            throw WorkbenchNativeInputError.unavailable("Could not construct the native resize drag.")
          }
          events.append(event)
        }
      } else {
        guard let event = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1,
          wheel1: scrollDelta, wheel2: 0, wheel3: 0) else {
          throw WorkbenchNativeInputError.unavailable("Could not construct the native scroll event.")
        }
        event.location = point
        events.append(event)
      }
      let posted = ProcessInfo.processInfo.systemUptime
      for event in events {
        event.setIntegerValueField(.eventSourceUserData, value: identity)
        event.postToPid(ProcessInfo.processInfo.processIdentifier)
      }
      return posted
    }.value
  }
}
