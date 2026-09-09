import AppKit
import PlotterEpisodeModel
import PlotterRuntime
@testable import PlotterUI
import SwiftUI
import Testing
@testable import PlotterApp

@Suite("Workbench interaction rendering", .serialized)
@MainActor
struct WorkbenchInteractionRenderingTests {
  @Test("combined Learning panel renders with native controls at minimum width",
    .enabled(if: ProcessInfo.processInfo.environment["WORKBENCH_UI_SNAPSHOT"] != nil))
  func combinedPanel() async throws {
    let workspace = makeCausalSimulatorAppFixture().workspace
    let item = LearningPathItemID.humanGuidedDiscovery(.penInteraction)
    let base = try #require(workspace.testPlotterUIProjection(selectedItemID: item,
      includesLearningPath: true).learningPath)
    let actions = [
      PlotterUILearningActionDecision(itemID: "pen", action: .choice(.yes), title: "Confirm Pen Up"),
      PlotterUILearningActionDecision(itemID: "pen", action: .stopPenInteraction(.init()), title: "Stop Pen Interaction")
    ]
    let strip = PlotterUILearningActionStripDecision(ownerID: "pen", actions: actions,
      directionSelection: nil,
      penAdjustment: .init(command: .raise, value: 40,
        candidates: (0...100).map { .init(value: $0, decision: .init(itemID: "pen", action: .setPenSetpoint(.raise, $0))) }),
      mustRemainVisible: true)
    let semantic = PlotterUIProjection(revision: .init(rawValue: 1), runtimeRevisions: [],
      actions: (actions + (strip.penAdjustment?.candidates.map(\.decision) ?? [])).map {
        .init(id: .init(learningRequest: $0.request), title: $0.title,
          intent: .learningAction($0.request), unavailableReason: $0.unavailableReason)
      }, learning: nil, incidentPackage: .unavailable(reason: "Render fixture"), diagnostics: [],
      visitedCandidateCount: 103)
    let projection = LearningPathProjection(currentItemID: item, items: base.items,
      selectedAction: .init(itemID: item,
        instructions: [.text("Adjust the servo until the pen clears the paper, then confirm Pen Up.")],
        actionStrip: strip), currentActionStrip: strip, contextualStop: nil,
      resetSurface: base.resetSurface, menu: base.menu)
    let view = LearningPathView(selection: .constant(.init(current: item)), projection: projection,
      learningMode: workspace.testLearningModePresentation,
      currentLearningPathItemID: item, plotterUIProjection: semantic,
      plotterUIIntentSink: workspace)
    _ = NSApplication.shared
    for (scheme, name) in [(ColorScheme.light, "light"), (.dark, "dark")] {
      let host = NSHostingView(rootView: view.environment(\.colorScheme, scheme)
        .background(Color(nsColor: .windowBackgroundColor)))
      let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 390, height: 610),
        styleMask: [.borderless], backing: .buffered, defer: false)
      window.isReleasedWhenClosed = false
      window.appearance = NSAppearance(named: scheme == .light ? .aqua : .darkAqua)
      window.contentView = host
      host.frame = NSRect(x: 0, y: 0, width: 390, height: 610)
      host.layoutSubtreeIfNeeded()
      try await Task.sleep(for: .milliseconds(100))
      host.layoutSubtreeIfNeeded()
      window.display()
      host.display()
      let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
      host.cacheDisplay(in: host.bounds, to: bitmap)
      let bytes = try #require(bitmap.representation(using: .png, properties: [:]))
      try bytes.write(to: URL(fileURLWithPath:
        ProcessInfo.processInfo.environment["WORKBENCH_UI_SNAPSHOT"]! + "-" + name + ".png"))
      window.close()
    }
    await workspace.shutdown()
  }
}
