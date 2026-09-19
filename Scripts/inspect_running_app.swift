// Read the selected native process only. The sole optional AX action is its existing diagnostic export.
import AppKit
import ApplicationServices
import Foundation
import IOKit

// Read one local registry property; never request credentials or change session state.
// Only the active console's lock state leaves this function, not user identities.
func readScreenLockState() -> String {
  let root = IORegistryGetRootEntry(kIOMainPortDefault)
  guard root != 0 else { return "unknown" }
  defer { IOObjectRelease(root) }
  guard let property = IORegistryEntryCreateCFProperty(root, "IOConsoleUsers" as CFString,
    kCFAllocatorDefault, 0)?.takeRetainedValue(),
    let users = property as? [[String: Any]], users.count <= 64 else { return "unknown" }
  let activeConsole = users.filter { $0["kCGSSessionOnConsoleKey"] as? Bool == true }
  guard activeConsole.count == 1,
    let locked = activeConsole[0]["CGSSessionScreenIsLocked"] as? Bool else { return "unknown" }
  return locked ? "locked" : "unlocked"
}

let args = CommandLine.arguments
func argument(_ name: String) -> String? {
  guard let index = args.firstIndex(of: name), args.indices.contains(index + 1) else { return nil }
  return args[index + 1]
}
guard let outputPath = argument("--output") else {
  FileHandle.standardError.write(Data("Missing --output directory\n".utf8)); exit(64)
}
let output = URL(fileURLWithPath: outputPath)
let requestedPID = argument("--pid").flatMap(Int32.init)
if argument("--pid") != nil && (requestedPID == nil || requestedPID! <= 0) {
  FileHandle.standardError.write(Data("Invalid --pid\n".utf8)); exit(64)
}
let applications = NSWorkspace.shared.runningApplications.filter {
  $0.executableURL?.lastPathComponent == "AdaptivePlotter" && (requestedPID == nil || $0.processIdentifier == requestedPID)
}
let screenLockState = readScreenLockState()
var result: [String: Any] = [
  "capturedAt": ISO8601DateFormatter().string(from: Date()),
  "screenRecordingAuthorized": CGPreflightScreenCaptureAccess(),
  "accessibilityAuthorized": AXIsProcessTrusted(),
  "screenLockState": screenLockState,
  "screenLockStateSource": "IORegistryRoot.IOConsoleUsers.activeConsole",
  "limitations": ["Window pixels include overlays; exported camera pixels do not.",
                   "Window, accessibility, camera and controller snapshots have independent timestamps."]
]
var errors: [String] = []
if applications.count != 1 {
  errors.append("Expected one running AdaptivePlotter; found \(applications.count). Supply --pid when multiple copies are running.")
} else if let app = applications.first {
  let pid = app.processIdentifier
  result["pid"] = pid
  result["executable"] = app.executableURL?.path
  result["bundle"] = app.bundleURL?.path
  result["launchDate"] = app.launchDate.map { ISO8601DateFormatter().string(from: $0) }
  if screenLockState == "locked" {
    result["nativeCaptureSkippedReason"] = "lockedSession"
    result["accessibilityScope"] = "unavailableLockedSession"
    errors.append("The macOS console session is locked. Unlock the existing desktop and rerun inspection; Screen Recording and Accessibility permissions alone are insufficient. Window capture and diagnostic export were skipped. No unlock or activation was attempted.")
  } else {
    let windows = (CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []).filter {
      ($0[kCGWindowOwnerPID as String] as? Int32) == pid && ($0[kCGWindowLayer as String] as? Int) == 0
    }
    result["windows"] = windows
    let selectedWindow = windows.first
    let selectedBounds = (selectedWindow?[kCGWindowBounds as String] as? [String: Any])
      .flatMap { CGRect(dictionaryRepresentation: $0 as CFDictionary) }
    result["selectedWindowID"] = selectedWindow?[kCGWindowNumber as String]
    result["selectedWindowBounds"] = selectedWindow?[kCGWindowBounds as String]
    result["windowSelection"] = "Frontmost onscreen layer-zero window of the selected process."
    if CGPreflightScreenCaptureAccess(), let window = windows.first,
       let number = window[kCGWindowNumber as String] as? UInt32 {
      let process = Process()
      process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
      process.arguments = ["-x", "-o", "-l", String(number), output.appendingPathComponent("window.png").path]
      do {
        result["windowCaptureStartedAtUnix"] = Date().timeIntervalSince1970
        try process.run(); process.waitUntilExit()
        result["windowCaptureFinishedAtUnix"] = Date().timeIntervalSince1970
        result["windowCaptureExitCode"] = process.terminationStatus
        if process.terminationStatus != 0 { errors.append("Window capture failed; check window availability and Screen Recording permission.") }
      } catch { errors.append("Window capture: \(error)") }
    } else { errors.append("No capturable window or Screen Recording permission. No permission prompt was opened.") }

    func value(_ node: AXUIElement, _ key: String) -> CFTypeRef? {
      var value: CFTypeRef?
      return AXUIElementCopyAttributeValue(node, key as CFString, &value) == .success ? value : nil
    }
    let accessibilityDeadline = Date().addingTimeInterval(10)
    var accessibilityTruncated = false
    var elements: [[String: Any]] = []
    var exportButtons: [AXUIElement] = []
    func walk(_ node: AXUIElement, _ depth: Int) {
      guard depth < 16, elements.count < 1200, Date() < accessibilityDeadline else {
        accessibilityTruncated = true; return
      }
      var row: [String: Any] = ["depth": depth]
      for key in [kAXRoleAttribute, kAXTitleAttribute, kAXDescriptionAttribute, kAXIdentifierAttribute, kAXEnabledAttribute, kAXValueAttribute] {
        guard Date() < accessibilityDeadline else { accessibilityTruncated = true; break }
        if let item = value(node, key), CFGetTypeID(item) == CFStringGetTypeID() || CFGetTypeID(item) == CFBooleanGetTypeID() || CFGetTypeID(item) == CFNumberGetTypeID() { row[key] = item }
      }
      elements.append(row)
      if row[kAXRoleAttribute] as? String == kAXButtonRole,
         row[kAXIdentifierAttribute] as? String == "workbench.diagnostics",
         row[kAXEnabledAttribute] as? Bool == true { exportButtons.append(node) }
      for child in (value(node, kAXChildrenAttribute) as? [AXUIElement]) ?? [] { walk(child, depth + 1) }
    }
    if AXIsProcessTrusted() {
      let element = AXUIElementCreateApplication(pid)
      AXUIElementSetMessagingTimeout(element, 2)
      let accessibilityWindows = (value(element, kAXWindowsAttribute) as? [AXUIElement]) ?? []
      let matchingWindows = accessibilityWindows.filter { window in
        guard let selectedBounds,
          let rawPosition = value(window, kAXPositionAttribute), CFGetTypeID(rawPosition) == AXValueGetTypeID(),
          let rawSize = value(window, kAXSizeAttribute), CFGetTypeID(rawSize) == AXValueGetTypeID() else { return false }
        var position = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(rawPosition as! AXValue, .cgPoint, &position),
          AXValueGetValue(rawSize as! AXValue, .cgSize, &size) else { return false }
        return abs(position.x - selectedBounds.minX) < 2 && abs(position.y - selectedBounds.minY) < 2
          && abs(size.width - selectedBounds.width) < 2 && abs(size.height - selectedBounds.height) < 2
      }
      if matchingWindows.count == 1 {
        walk(matchingWindows[0], 0)
        result["accessibilityScope"] = "capturedWindow"
      } else {
        result["accessibilityScope"] = "unmatched"
        errors.append("Could not uniquely match the captured window to Accessibility geometry; no export action issued.")
      }
      result["accessibility"] = elements
      result["accessibilityTruncated"] = accessibilityTruncated
      if args.contains("--export-diagnostics") {
        if exportButtons.count == 1 {
          result["diagnosticExportRequestedAtUnix"] = Date().timeIntervalSince1970
          let code = AXUIElementPerformAction(exportButtons[0], kAXPressAction as CFString)
          result["diagnosticExportRequest"] = code.rawValue
          if code != .success { errors.append("Existing diagnostic export button refused AXPress: \(code.rawValue).") }
        } else { errors.append("Exactly one enabled diagnostic export button was not found; no action issued.") }
      }
    } else { errors.append("Accessibility permission is unavailable. No permission prompt or UI action was issued.") }
  }
}
result["errors"] = errors
let data = try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
try data.write(to: output.appendingPathComponent("native.json"), options: .atomic)
