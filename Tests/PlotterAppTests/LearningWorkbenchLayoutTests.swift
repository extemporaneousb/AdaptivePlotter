import AppKit
import Foundation
import PlotterEpisodeModel
import SwiftUI
import Testing
@testable import PlotterApp

@Suite("Learning workbench layout policy")
struct LearningWorkbenchLayoutTests {
  @Test("target authoring accepts the current request before Learning is complete")
  @MainActor
  func opensStudioBeforeLearning() async throws {
    let workspace = makeCausalSimulatorAppFixture().workspace
    await workspace.performApplicationStartup(AdaptivePlotterLaunchPolicy(
      arguments: [AdaptivePlotterLaunchPolicy.simulatedArgument, "YES"]))
    let item = LearningPathItemID.humanGuidedDiscovery(.penInteraction)
    let before = workspace.testPlotterUIProjection(selectedItemID: item, includesLearningPath: true)
    #expect(!workspace.interactiveLearningIsComplete)
    #expect(workspace.tipCameraRegistration == nil)
    let request = try #require(before.semantic.request(for: PlotterAppUIActionID.drawingDraft(.showTarget)))
    #expect(workspace.drawingDraftSnapshot.projection.externalFacts == workspace.drawingDraftExternalFacts.revisions)
    let result = await workspace.submitPlotterUIRequest(request)
    guard case .accepted = result else {
      Issue.record("The initial workbench must permit authoring through its current request: \(result)")
      await workspace.shutdown()
      return
    }
    #expect(workspace.drawingTargetIsVisible)
    #expect(workspace.drawingDraftSnapshot.program?.strokes.first?.style != nil)
    #expect(workspace.drawingDraftSnapshot.plan == nil)
    #expect(workspace.drawingStudioPresentation.editingIsEnabled)
    #expect(workspace.drawingStudioPresentation.controls.isEmpty)
    let style = try #require(workspace.drawingDraftSnapshot.program?.strokes.first?.style)
    let portrait = try PortraitVectorizer.program(
      from: portraitTestRaster(), pose: .front, style: .hatch, strokeStyle: style)
    let selection = workspace.plotterUIProjection(selectedItemID: item, manualDraft: ManualMotionDraft(),
      includesLearningPath: true, pendingDrawingProgram: portrait)
    let usePortrait = try #require(selection.semantic.request(matching: .drawingDraft(.selectProgram(portrait))))
    #expect(await workspace.submitPlotterUIRequest(usePortrait) == .accepted(requestID: usePortrait.id))
    #expect(workspace.drawingDraftSnapshot.program == portrait)
    #expect(workspace.drawingDraftSnapshot.plan == nil)
    if let path = ProcessInfo.processInfo.environment["DRAWING_AUTHORING_SNAPSHOT"] {
      let projection = workspace.testPlotterUIProjection(selectedItemID: item, includesLearningPath: true)
      let view = DrawingStudioView(presentation: projection.drawingStudio,
        plotterUIProjection: projection.semantic, plotterUIIntentSink: workspace,
        panel: .portraitStudio)
      _ = NSApplication.shared
      let host = NSHostingView(rootView: view.frame(width: 390)
        .environment(\.colorScheme, .light).background(Color(nsColor: .windowBackgroundColor)))
      let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 390, height: 1000),
        styleMask: [.borderless], backing: .buffered, defer: false)
      window.isReleasedWhenClosed = false
      window.appearance = NSAppearance(named: .aqua)
      window.contentView = host
      host.frame = NSRect(x: 0, y: 0, width: 390, height: 1000)
      host.layoutSubtreeIfNeeded()
      try await Task.sleep(for: .milliseconds(100))
      host.layoutSubtreeIfNeeded()
      window.display()
      let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
      host.cacheDisplay(in: host.bounds, to: bitmap)
      let image = try #require(bitmap.cgImage)
      try PortraitImageAnalyzer.encodedImage(image).write(to: URL(fileURLWithPath: path))
      window.close()
    }
    #expect(!workspace.interactiveLearningIsComplete)
    await workspace.shutdown()
  }

  @Test("controls fill right left lower-right lower-left and replace the oldest")
  func slotAllocationAndReplacement() throws {
    let panels = WorkbenchPanel.dockPanels
    #expect(panels.map(\.title) == ["Guided Learning", "Video Settings", "Motion", "Active Learning", "Drawing"])
    // Each control can be the first, last, or displaced one.
    for offset in panels.indices {
      let order = Array(panels[offset...] + panels[..<offset])
      var layout = WorkbenchLayoutState(presented: [])
      for (index, panel) in order.prefix(4).enumerated() {
        layout.setPresented(panel, true)
        #expect(layout.slot(of: panel) == WorkbenchSlot.allCases[index])
      }
      #expect(layout.panels(in: .right) == [order[0], order[2]])
      #expect(layout.panels(in: .left) == [order[1], order[3]])
      layout.setPresented(order[0], true) // Revealing does not change age or position.
      layout.setPresented(order[4], true)
      #expect(!layout.isPresented(order[0]))
      #expect(layout.slot(of: order[4]) == .right)
      #expect(WorkbenchLayoutState.restored(from: layout.encoded) == layout)
    }
  }

  @Test("closing leaves sibling slots intact and reopening fills the first vacancy")
  func closeAndReopen() {
    var layout = WorkbenchLayoutState(presented: [.motion, .guidedLearning, .videoSettings, .portraitStudio])
    layout.setPresented(.motion, false)
    #expect(layout.panels(in: .right) == [.videoSettings])
    #expect(layout.slot(of: .videoSettings) == .rightBottom)
    layout.setPresented(.activeLearning, true)
    #expect(layout.slot(of: .activeLearning) == .right)
    #expect(layout.panels(in: .right) == [.activeLearning, .videoSettings])
    for panel in WorkbenchPanel.allCases { layout.setPresented(panel, false) }
    #expect(!layout.hasVisiblePanels)
    #expect(WorkbenchLayoutState.restored(from: layout.encoded) == layout)
  }

  @Test("legacy Video visibility cannot hide the canvas or create a settings pane")
  func migratesLegacyLayout() {
    let legacy = Data(#"{"placements":["video",{"position":"bottom","isPresented":false},"guidedLearning",{"position":"left","isPresented":false},"motion",{"position":"bottom","isPresented":true},"portraitStudio",{"position":"right","isPresented":true}]}"#.utf8)
    let layout = WorkbenchLayoutState.restored(from: legacy)
    #expect(layout.slot(of: .motion) == .right)
    #expect(layout.slot(of: .portraitStudio) == nil)
    #expect(layout.isPresented(.portraitStudio))
    #expect(!layout.isPresented(.videoSettings))
    #expect(!layout.isPresented(.guidedLearning))
    #expect(WorkbenchLayoutState.restored(from: Data("broken".utf8)) == WorkbenchLayoutState())
  }

  @Test("Portrait workspace preserves every dock and restores old portrait slots")
  func portraitWorkspacePreservesDocks() {
    var layout = WorkbenchLayoutState(presented: [.motion, .guidedLearning, .videoSettings, .drawing])
    let before = layout
    layout.setPresented(.portraitStudio, true)
    #expect(layout.isPresented(.portraitStudio))
    for panel in WorkbenchPanel.dockPanels { #expect(layout.slot(of: panel) == before.slot(of: panel)) }
    layout = .restored(from: layout.encoded)
    #expect(layout.isPresented(.portraitStudio))
    layout.setPresented(.portraitStudio, false)
    for panel in WorkbenchPanel.dockPanels { #expect(layout.slot(of: panel) == before.slot(of: panel)) }
  }

  @Test("exercise actions preserve readable button widths")
  func readableExerciseActionWidths() {
    #expect(ExerciseActionLayoutPolicy.maximumColumnCount(availableWidth: 340) == 1)
    #expect(ExerciseActionLayoutPolicy.maximumColumnCount(availableWidth: 500) == 2)
    #expect(ExerciseActionLayoutPolicy.maximumColumnCount(availableWidth: .infinity) == 1)
  }

  @Test("hiding and replacing panels preserve Learning, the draft, and exact action requests")
  @MainActor
  func hidingPanelPreservesOwners() async throws {
    let workspace = makeCausalSimulatorAppFixture().workspace
    let before = workspace.testPlotterUIProjection(includesLearningPath: true)
    let draft = workspace.drawingDraftSnapshot
    var layout = WorkbenchLayoutState()
    for panel in WorkbenchPanel.allCases {
      layout.setPresented(panel, true)
      layout.setPresented(panel, false)
    }
    let after = workspace.testPlotterUIProjection(includesLearningPath: true)
    #expect(!layout.hasVisiblePanels)
    #expect(before.learningIsEnabled == after.learningIsEnabled)
    #expect(before.semantic.actions == after.semantic.actions)
    #expect(before.currentLearningPathItemID == after.currentLearningPathItemID)
    #expect(workspace.drawingDraftSnapshot == draft)
    await workspace.shutdown()
  }
}
