import AppKit
import Foundation
import PlotterRuntime
import SwiftUI

struct NativeWorkbenchPlacementProof: Codable, Equatable, Sendable {
  let panel: WorkbenchPanel
  let slot: WorkbenchSlot
  let width: Int
  let header: WorkbenchNativeControlVisibility
  let body: WorkbenchNativeControlVisibility
}

struct NativeWorkbenchReport: Encodable {
  let schema = "adaptiveplotter.native-workbench.v2"
  let provenance = "Actual signed SwiftUI App/Window and CGEvent input; simulated startup; no real camera, controller, motion or ink. Held Drawing Stop is separate software evidence."
  var failures: [String] = []
  var placements: [NativeWorkbenchPlacementProof] = []
  var bitmaps: [String] = []
  var inputs: [WorkbenchNativeInputSample] = []
  var nativeCounts: [String: WorkbenchNativeInputCounts] = [:]
  var learningStates: [Bool] = []
  var acceptedArtifactsUnchanged = false
  var windowPreferencesUnchanged = false
  var applicationWasActive = false
  var stopWasVisible = false
  var canvasOnlyWidths: [Int] = []
  var viewMenuWasPresent = false

  static func bodyControlIdentifier(for panel: WorkbenchPanel) -> String {
    switch panel {
    case .guidedLearning: "learning.exerciseActions"
    case .videoSettings: "workbench.video.cameraRole"
    case .motion: "motion.penDown"
    case .activeLearning: "learning.coverage.prepare"
    case .portraitStudio: "drawing.draw"
    }
  }

  static var requiredControlIdentifiers: [String] {
    ["workbench.scroll.inner", "workbench.resize", "learning.mode"]
      + WorkbenchPanel.allCases.map { "workbench.hide.\($0.rawValue)" }
      + WorkbenchPanel.allCases.map { "workbench.toggle.\($0.rawValue)" }
  }

  var verificationFailures: [String] {
    var result = failures
    let expected = Set(WorkbenchPanel.allCases.flatMap { panel in
      WorkbenchSlot.allCases.flatMap { slot in [1_000, 1_600].map { "\(panel.rawValue).\(slot.rawValue).\($0)" } }
    })
    if placements.count != expected.count
      || Set(placements.map { "\($0.panel.rawValue).\($0.slot.rawValue).\($0.width)" }) != expected {
      result.append("All 20 control/slot combinations at both widths lack complete header/body hit proofs.")
    }
    if bitmaps.count != 8 || Set(bitmaps).count != 8 { result.append("The eight actual workbench layout bitmaps were not retained.") }
    if placements.contains(where: {
      $0.header.identifier != "workbench.hide.\($0.panel.rawValue)"
        || $0.body.identifier != Self.bodyControlIdentifier(for: $0.panel)
        || $0.header.frame.isEmpty || $0.body.frame.isEmpty
        || $0.body.containingClipCount < 1
        || $0.body.panelIdentifier != "workbench.panel.\($0.panel.rawValue)"
        || !$0.body.fitsEveryContainingClip || !$0.header.fitsEveryContainingClip
    }) { result.append("A placement substitutes a header, missing body, or empty hit target for its actual panel controls.") }
    let expectedInnerContexts = Set(WorkbenchSlot.allCases.flatMap { slot in [1_000, 1_600].map { "\(slot.rawValue).\($0)" } })
    let measuredInnerContexts = Set(inputs.compactMap { sample -> String? in
      guard sample.targetIdentifier == "workbench.scroll.inner",
        let evidence = sample.scrollEvidence, evidence.controlIdentifier == "drawing.draw",
        !evidence.clipIdentity.isEmpty, evidence.beforeBounds != evidence.afterBounds else { return nil }
      return evidence.context
    })
    if measuredInnerContexts != expectedInnerContexts {
      result.append("Control-body native wheel movement lacks identified clip receipts at every slot/width; programmatic reveal is diagnostic only.")
    }
    if learningStates.count != 2 || Set(learningStates) != [false, true] {
      result.append("Native Learning On/Off round trip was not demonstrated.")
    }
    for id in Self.requiredControlIdentifiers {
      let minimum = id == "learning.mode" ? 2 : 8
      guard let count = nativeCounts[id], count.posted >= minimum,
        count.posted == count.dispatched, count.posted == count.handled,
        count.posted == count.acknowledged else {
        result.append("Missing correlated native control receipt: \(id).")
        continue
      }
    }
    if inputs.count != nativeCounts.values.reduce(0, { $0 + $1.acknowledged }) {
      result.append("Native receipt totals do not reconcile.")
    }
    for (id, count) in nativeCounts where inputs.filter({ $0.targetIdentifier == id }).count != count.acknowledged {
      result.append("Native \(id) receipts do not reconcile with its acknowledgment count.")
    }
    if inputs.contains(where: {
      let correlation = WorkbenchNativeEventCorrelation(expectedIdentity: $0.postedEventIdentity)
      return $0.eventUptimeSeconds == nil || !correlation.accepts($0.dispatchedEventIdentity)
        || !correlation.accepts($0.handledEventIdentity)
        || $0.dispatchEntryUptimeSeconds < $0.postedUptimeSeconds
        || $0.handlerUptimeSeconds < $0.dispatchEntryUptimeSeconds
        || !$0.visibleAcknowledgmentLatencyMilliseconds.isFinite
        || $0.visibleAcknowledgmentLatencyMilliseconds < $0.handlerLatencyMilliseconds
    }) { result.append("Native input lacks exact event correlation or ordered handler/visible acknowledgment.") }
    if Set(inputs.map(\.postedEventIdentity)).count != inputs.count {
      result.append("A native event identity was reused for multiple actions.")
    }
    if Set(canvasOnlyWidths) != [1_000, 1_600] || !viewMenuWasPresent {
      result.append("The permanent canvas with all controls closed or native View menu was not proved.")
    }
    if !applicationWasActive || !stopWasVisible { result.append("Actual app readiness or global Stop visibility was not proved.") }
    if !acceptedArtifactsUnchanged || !windowPreferencesUnchanged { result.append("Accepted artifacts or persisted window preferences changed.") }
    return result
  }
}

extension RunningAppPreviewPerformanceGate {
  static func runNativeWorkbench(application: PlotterApplicationRuntime,
    configuration: RunningAppPreviewPerformanceConfiguration, layout: Binding<WorkbenchLayoutState>) async {
    var report = NativeWorkbenchReport()
    let originalLayout = layout.wrappedValue
    let savedLayout = UserDefaults.standard.data(forKey: "AdaptivePlotter.workbenchLayout.v1")
    let originalLearning = application.learningIsEnabled
    let acceptedRevisions = Set(application.learningArtifactGraph.revisions)
    let originalTip = application.tipCameraRegistration
    let originalCompletion = application.interactiveLearningIsComplete
    let probe = RunningAppNativeInputProbe()
    let window = NSApp.mainWindow ?? NSApp.windows.first(where: { $0.isVisible && $0.contentView != nil })
    let originalFrame = window?.frame
    let directory = configuration.reportURL.deletingLastPathComponent().appendingPathComponent("native-workbench", isDirectory: true)
    var checkpointBefore: Data?
    var checkpointURL: URL?
    do {
      let base = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
        appropriateFor: nil, create: false)
      let url = base.appendingPathComponent("AdaptivePlotter/AcceptedArtifacts/accepted-learning-path-v1.json")
      checkpointURL = url
      if FileManager.default.fileExists(atPath: url.path) { checkpointBefore = try Data(contentsOf: url) }
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      try Data("ready\n".utf8).write(to: configuration.readyMarkerURL, options: .atomic)
      guard let window else { throw WorkbenchNativeInputError.unavailable("The production workbench window is absent.") }
      try await awaitWorkload("The signed application did not become active with a key/main workbench and native controls.") {
        NSApp.isActive && NSRunningApplication.current.isFinishedLaunching && window.isKeyWindow
          && window.isMainWindow && RunningAppNativeInputProbe.controlFrame("workbench.video.canvas") != nil
      }
      report.applicationWasActive = true
      probe.install()
      report.viewMenuWasPresent = NSApp.mainMenu?.items.contains { item in
        item.title == "View" && item.submenu?.items.contains { $0.title.contains("Video Settings") } == true
      } == true
      for slot in WorkbenchSlot.allCases {
        for width in [1_000, 1_600] {
          window.setContentSize(NSSize(width: CGFloat(width), height: 700))
          window.center()
          let slotIndex = WorkbenchSlot.allCases.firstIndex(of: slot)!
          for panel in WorkbenchPanel.allCases {
            // Only setup uses direct state. The final pane is opened through
            // its real View-menu key equivalent and closed with its native x.
            let fillers = Array(WorkbenchPanel.allCases.filter { $0 != panel }.prefix(slotIndex))
            layout.wrappedValue = WorkbenchLayoutState(presented: fillers)
            report.inputs.append(try await probe.togglePane(panel) {
              layout.wrappedValue.slot(of: panel) == slot
                && RunningAppNativeInputProbe.controlIsInside("workbench.panel.\(panel.rawValue)",
                  container: "workbench.dock.\(slot.dock.rawValue)")
            })
            let panelID = "workbench.panel.\(panel.rawValue)"
            let body = try RunningAppNativeInputProbe.inspectControl(
              NativeWorkbenchReport.bodyControlIdentifier(for: panel), in: window, panelIdentifier: panelID)
            let header = try RunningAppNativeInputProbe.inspectControl("workbench.hide.\(panel.rawValue)",
              in: window, panelIdentifier: panelID)
            report.placements.append(.init(panel: panel, slot: slot, width: width, header: header, body: body))
            if panel == .portraitStudio {
              report.inputs.append(try await probe.scrollWorkbench(innerControl: "drawing.draw",
                context: "\(slot.rawValue).\(width)"))
              let image = directory.appendingPathComponent("slot-\(slot.rawValue)-\(width).png")
              try captureNativeWorkbench(window, to: image)
              report.bitmaps.append(image.path)
              report.inputs.append(try await probe.resizeWorkbench())
              window.setContentSize(NSSize(width: CGFloat(width), height: 700))
            }
            report.inputs.append(try await probe.click("workbench.hide.\(panel.rawValue)") {
              !layout.wrappedValue.isPresented(panel)
                && RunningAppNativeInputProbe.controlFrame(panelID) == nil
            })
            guard fillers.allSatisfy({ layout.wrappedValue.isPresented($0) }) else {
              throw WorkbenchNativeInputError.unavailable("Closing a control hid a sibling.")
            }
          }
        }
      }
      for width in [1_000, 1_600] {
        layout.wrappedValue = WorkbenchLayoutState(presented: [])
        window.setContentSize(NSSize(width: CGFloat(width), height: 700))
        try await awaitWorkload("Closing all controls hid or narrowed the canvas.") {
          window.contentView?.layoutSubtreeIfNeeded()
          guard let canvas = RunningAppNativeInputProbe.controlFrame("workbench.video.canvas") else { return false }
          return canvas.width >= CGFloat(width) - 4
        }
        report.canvasOnlyWidths.append(width)
      }
      layout.wrappedValue = originalLayout
      layout.wrappedValue.setPresented(.guidedLearning, true)
      for expected in [!originalLearning, originalLearning] {
        report.inputs.append(try await probe.click("learning.mode") {
          application.learningIsEnabled == expected
            && RunningAppNativeInputProbe.controlValue("learning.mode.state")?.hasPrefix(expected ? "On|" : "Off|") == true
        })
        report.learningStates.append(application.learningIsEnabled)
      }
      _ = try RunningAppNativeInputProbe.inspectControl("workbench.stop", in: window)
      report.stopWasVisible = true
    } catch {
      report.failures.append(error.localizedDescription)
      if let window {
        try? captureNativeWorkbench(window, to: directory.appendingPathComponent("failure.png"))
        let state = "active=\(NSApp.isActive) finishedLaunching=\(NSRunningApplication.current.isFinishedLaunching) key=\(window.isKeyWindow) main=\(window.isMainWindow) style=\(window.styleMask.rawValue) frame=\(window.frame) hostChildren=\(window.contentView?.accessibilityChildren()?.count ?? 0) panels=\(RunningAppNativeInputProbe.panelText())\n"
        try? state.write(to: directory.appendingPathComponent("failure.txt"), atomically: true, encoding: .utf8)
      }
    }
    report.nativeCounts = probe.counts
    probe.uninstall()
    // Restoration is not recorded as native proof if the measured sequence failed.
    if application.learningIsEnabled != originalLearning {
      let ui = application.plotterUIProjection(selectedItemID: .humanGuidedDiscovery(.penInteraction),
        manualDraft: ManualMotionDraft(), includesLearningPath: true)
      if let request = ui.semantic.request(for: PlotterAppUIActionID.learningMode) {
        _ = await application.submitPlotterUIRequest(request)
      }
    }
    layout.wrappedValue = originalLayout
    if let window, let originalFrame { window.setFrame(originalFrame, display: true) }
    let checkpointAfter = checkpointURL.flatMap { try? Data(contentsOf: $0) }
    report.acceptedArtifactsUnchanged = checkpointURL != nil && checkpointBefore == checkpointAfter
      && Set(application.learningArtifactGraph.revisions) == acceptedRevisions
      && application.tipCameraRegistration == originalTip
      && application.interactiveLearningIsComplete == originalCompletion
      && application.learningIsEnabled == originalLearning
    report.windowPreferencesUnchanged = savedLayout == UserDefaults.standard.data(forKey: "AdaptivePlotter.workbenchLayout.v1")
    report.failures = report.verificationFailures
    do {
      let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
      try encoder.encode(report).write(to: configuration.reportURL, options: .atomic)
    } catch { FileHandle.standardError.write(Data("Native workbench report failed: \(error)\n".utf8)) }
    await application.shutdown()
    NSApp.terminate(nil)
  }

  private static func captureNativeWorkbench(_ window: NSWindow, to url: URL) throws {
    guard let host = window.contentView else { throw WorkbenchNativeInputError.unavailable("No native content to capture.") }
    host.layoutSubtreeIfNeeded(); window.displayIfNeeded(); host.displayIfNeeded()
    guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else {
      throw WorkbenchNativeInputError.unavailable("No workbench bitmap at \(host.bounds).")
    }
    host.cacheDisplay(in: host.bounds, to: bitmap)
    guard let bytes = bitmap.representation(using: .png, properties: [:]) else {
      throw WorkbenchNativeInputError.unavailable("Native workbench bitmap encoding failed.")
    }
    try bytes.write(to: url)
  }
}
