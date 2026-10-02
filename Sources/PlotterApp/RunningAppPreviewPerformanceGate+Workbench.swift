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

struct NativePortraitWorkspaceProof: Codable, Equatable, Sendable {
  let width: Int
  let header: WorkbenchNativeControlVisibility
  let capture: WorkbenchNativeControlVisibility
}

struct NativeWorkbenchReport: Encodable {
  let schema = "adaptiveplotter.native-workbench.v3"
  let provenance = "Actual signed SwiftUI App/Window and CGEvent input; simulated startup; no real camera, controller, motion or ink. Held Drawing Stop is separate software evidence."
  var failures: [String] = []
  var placements: [NativeWorkbenchPlacementProof] = []
  var portraitWorkspaces: [NativePortraitWorkspaceProof] = []
  var bitmaps: [String] = []
  var inputs: [WorkbenchNativeInputSample] = []
  var fittingDrawingBodies: [WorkbenchNativeFittingBodyEvidence] = []
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
    case .portraitStudio: "portrait.capture"
    case .drawing: "drawing.draw"
    }
  }

  static var requiredControlIdentifiers: [String] {
    ["workbench.scroll.inner", "workbench.resize", "learning.mode"]
      + WorkbenchPanel.allCases.map { "workbench.hide.\($0.rawValue)" }
      + WorkbenchPanel.allCases.map { "workbench.toggle.\($0.rawValue)" }
  }

  var verificationFailures: [String] {
    var result = failures
    let expected = Set(WorkbenchPanel.dockPanels.flatMap { panel in
      WorkbenchSlot.allCases.flatMap { slot in [1_000, 1_600].map { "\(panel.rawValue).\(slot.rawValue).\($0)" } }
    })
    if placements.count != expected.count
      || Set(placements.map { "\($0.panel.rawValue).\($0.slot.rawValue).\($0.width)" }) != expected {
      result.append("The five dock controls lack complete header/body hit proofs at every slot and width.")
    }
    if bitmaps.count != 10 || Set(bitmaps).count != 10 { result.append("The ten actual dock/workspace layout bitmaps were not retained.") }
    if portraitWorkspaces.count != 2 || Set(portraitWorkspaces.map(\.width)) != [1_000, 1_600]
      || portraitWorkspaces.contains(where: {
        $0.header.identifier != "workbench.hide.portraitStudio"
          || $0.capture.identifier != "portrait.capture"
          || $0.header.frame.isEmpty || $0.capture.frame.isEmpty
          || $0.header.panelIdentifier != "workbench.panel.portraitStudio"
          || $0.capture.panelIdentifier != "workbench.panel.portraitStudio"
          || !$0.header.fitsEveryContainingClip || !$0.capture.fitsEveryContainingClip
          || $0.capture.containingClipCount != 0
      }) { result.append("The full Portrait Studio workspace lacks unclipped persistent capture/exit hit proofs at both widths.") }
    if placements.contains(where: {
      $0.header.identifier != "workbench.hide.\($0.panel.rawValue)"
        || $0.body.identifier != Self.bodyControlIdentifier(for: $0.panel)
        || $0.header.frame.isEmpty || $0.body.frame.isEmpty
        || $0.body.containingClipCount < 1
        || $0.body.panelIdentifier != "workbench.panel.\($0.panel.rawValue)"
        || !$0.body.fitsEveryContainingClip || !$0.header.fitsEveryContainingClip
    }) { result.append("A placement substitutes a header, missing body, or empty hit target for its actual panel controls.") }
    let expectedInnerContexts = Set(WorkbenchSlot.allCases.flatMap { slot in [1_000, 1_600].map { "\(slot.rawValue).\($0)" } })
    let innerInputs = inputs.filter { $0.targetIdentifier == "workbench.scroll.inner" }
    let measuredInnerContexts = Set(innerInputs.compactMap { sample -> String? in
      guard let evidence = sample.scrollEvidence, evidence.controlIdentifier == "drawing.draw",
        evidence.provesInnerWheelMovement else { return nil }
      return evidence.context
    })
    let fittingContexts = Set(fittingDrawingBodies.filter(\.provesCompleteDrawingBody).map(\.context))
    if !measuredInnerContexts.isDisjoint(with: fittingContexts)
      || measuredInnerContexts.union(fittingContexts) != expectedInnerContexts
      || innerInputs.count != measuredInnerContexts.count
      || fittingDrawingBodies.count != fittingContexts.count {
      result.append("Control-body reachability lacks native wheel movement for overflow or complete visible Drawing-body proof at every slot/width; programmatic reveal is diagnostic only.")
    }
    if learningStates.count != 2 || Set(learningStates) != [false, true] {
      result.append("Native Learning On/Off round trip was not demonstrated.")
    }
    for id in Self.requiredControlIdentifiers {
      let minimum = id == "workbench.scroll.inner" ? expectedInnerContexts.subtracting(fittingContexts).count
        : (id == "learning.mode" || id.hasSuffix(".portraitStudio") ? 2 : 8)
      let count = nativeCounts[id, default: .init()]
      guard count.posted >= minimum,
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
      let url = AdaptivePlotterStoragePaths.production.acceptedLearningCheckpoint
      checkpointURL = url
      if FileManager.default.fileExists(atPath: url.path) { checkpointBefore = try Data(contentsOf: url) }
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      try Data("ready\n".utf8).write(to: configuration.readyMarkerURL, options: .atomic)
      guard let window else { throw WorkbenchNativeInputError.unavailable("The production workbench window is absent.") }
      layout.wrappedValue = WorkbenchLayoutState(presented: [.guidedLearning])
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
          for panel in WorkbenchPanel.dockPanels {
            // Only setup uses direct state. The final pane is opened through
            // its real View-menu key equivalent and closed with its native x.
            let fillers = Array(WorkbenchPanel.dockPanels.filter { $0 != panel }.prefix(slotIndex))
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
            if panel == .drawing {
              let context = "\(slot.rawValue).\(width)"
              if let fitting = try RunningAppNativeInputProbe.inspectFittingDrawingBody(context: context, in: window) {
                report.fittingDrawingBodies.append(fitting)
              } else {
                report.inputs.append(try await probe.scrollWorkbench(innerControl: "drawing.draw", context: context))
              }
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
        layout.wrappedValue = WorkbenchLayoutState(presented: [.drawing])
        window.setContentSize(NSSize(width: CGFloat(width), height: 700))
        report.inputs.append(try await probe.togglePane(.portraitStudio) {
          layout.wrappedValue.isPresented(.portraitStudio)
            && RunningAppNativeInputProbe.controlFrame("workbench.panel.portraitStudio") != nil
            && RunningAppNativeInputProbe.controlFrame("workbench.video.canvas") == nil
        })
        let panelID = "workbench.panel.portraitStudio"
        let header = try RunningAppNativeInputProbe.inspectControl("workbench.hide.portraitStudio",
          in: window, panelIdentifier: panelID)
        let capture = try RunningAppNativeInputProbe.inspectControl("portrait.capture",
          in: window, panelIdentifier: panelID)
        report.portraitWorkspaces.append(.init(width: width, header: header, capture: capture))
        let image = directory.appendingPathComponent("portrait-workspace-\(width).png")
        try captureNativeWorkbench(window, to: image)
        report.bitmaps.append(image.path)
        report.inputs.append(try await probe.click("workbench.hide.portraitStudio") {
          !layout.wrappedValue.isPresented(.portraitStudio)
            && RunningAppNativeInputProbe.controlFrame(panelID) == nil
            && RunningAppNativeInputProbe.controlFrame("workbench.panel.drawing") != nil
        })
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
