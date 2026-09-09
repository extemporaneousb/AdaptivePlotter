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

  @Test("five independent panels have the requested initial docks")
  func panelInventory() {
    #expect(WorkbenchPanel.allCases.map(\.title) == ["Guided Learning", "Video", "Motion", "Active Learning", "Portrait Studio"])
    let layout = WorkbenchLayoutState()
    #expect(layout.panels(in: .left) == [.guidedLearning])
    #expect(layout.panels(in: .right) == [.video])
    #expect(layout.panels(in: .bottom) == [.motion])
    #expect(!layout.isPresented(.activeLearning))
    #expect(!layout.isPresented(.portraitStudio))
  }

  @Test("each of five panels moves independently into every dock and survives persistence")
  func independentDockingAndPersistence() throws {
    for panel in WorkbenchPanel.allCases {
      for dock in WorkbenchDock.allCases {
        var layout = WorkbenchLayoutState()
        let before = layout
        layout.setPresented(panel, true)
        layout.move(panel, to: dock)
        #expect(layout.panels(in: dock).contains(panel))
        for other in WorkbenchPanel.allCases where other != panel {
          #expect(layout.placement(of: other) == before.placement(of: other))
        }
        #expect(WorkbenchLayoutState.restored(from: layout.encoded) == layout)
        layout.setPresented(panel, false)
        #expect(!layout.panels(in: dock).contains(panel))
        let restored = WorkbenchLayoutState.restored(from: layout.encoded)
        #expect(!restored.isPresented(panel))
        #expect(restored.placement(of: panel).position == dock)
      }
    }
    #expect(WorkbenchLayoutState.restored(from: Data("broken".utf8)) == WorkbenchLayoutState())
  }

  @Test("all panels can occupy one region without displacing or hiding a sibling")
  func sharedDock() {
    for dock in WorkbenchDock.allCases {
      var layout = WorkbenchLayoutState()
      for panel in WorkbenchPanel.allCases {
        layout.setPresented(panel, true)
        layout.move(panel, to: dock)
      }
      #expect(layout.panels(in: dock) == WorkbenchPanel.allCases)
      for other in WorkbenchDock.allCases where other != dock { #expect(layout.panels(in: other).isEmpty) }
    }
  }

  @Test("exercise actions preserve readable button widths")
  func readableExerciseActionWidths() {
    #expect(ExerciseActionLayoutPolicy.maximumColumnCount(availableWidth: 340) == 1)
    #expect(ExerciseActionLayoutPolicy.maximumColumnCount(availableWidth: 500) == 2)
    #expect(ExerciseActionLayoutPolicy.maximumColumnCount(availableWidth: .infinity) == 1)
  }

  @Test("hiding and moving panels preserve Learning, the draft, and exact action requests")
  @MainActor
  func hidingPanelPreservesOwners() async throws {
    let workspace = makeCausalSimulatorAppFixture().workspace
    let before = workspace.testPlotterUIProjection(includesLearningPath: true)
    let draft = workspace.drawingDraftSnapshot
    var layout = WorkbenchLayoutState()
    for panel in WorkbenchPanel.allCases {
      layout.move(panel, to: .bottom)
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
