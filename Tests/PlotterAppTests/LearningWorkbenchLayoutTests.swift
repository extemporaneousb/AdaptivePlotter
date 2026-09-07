import Foundation
import PlotterEpisodeModel
import SwiftUI
import Testing
@testable import PlotterApp

@Suite("Learning workbench layout policy")
struct LearningWorkbenchLayoutTests {
  @Test("one Learning panel contains navigation and exercise controls")
  func panelInventory() {
    #expect(WorkbenchPanel.allCases.map(\.title) == ["Learning Path", "Motion", "Video Settings"])
    let layout = WorkbenchLayoutState()
    let hidden = layout.toggling(.learningPath)
    #expect(!hidden.panes.learningPathIsPresented)
    #expect(hidden.toggling(.learningPath) == layout)
    #expect(hidden.panes.motionIsPresented == layout.panes.motionIsPresented)
  }

  @Test("exercise actions preserve readable button widths")
  func readableExerciseActionWidths() {
    #expect(ExerciseActionLayoutPolicy.maximumColumnCount(availableWidth: 340) == 1)
    #expect(ExerciseActionLayoutPolicy.maximumColumnCount(availableWidth: 500) == 2)
    #expect(ExerciseActionLayoutPolicy.maximumColumnCount(availableWidth: .infinity) == 1)
  }

  @Test("Video Settings can collapse Learning without waiting for an exercise")
  func videoSettingsCollapsesLearning() throws {
    let policy = VideoSettingsVisibilityPolicy()
    let layout = WorkbenchLayoutState()
    let shown = try #require(policy.transition(from: layout, action: .show,
      availableWindowWidth: policy.minimumWidthToShow))
    #expect(shown.videoSettingsIsPresented)
    #expect(!shown.panes.learningPathIsPresented)
    #expect(policy.transition(from: shown, action: .show, availableWindowWidth: 0) == shown)
    #expect(policy.transition(from: shown, action: .hide, availableWindowWidth: 0) == shown.hidingVideoSettings())
    #expect(policy.transition(from: layout, action: .show,
      availableWindowWidth: policy.minimumWidthToShow - 1) == nil)
  }

  @Test("opening Video Settings does not reopen a deliberately hidden Learning panel")
  func hiddenLearningStaysHidden() throws {
    let policy = VideoSettingsVisibilityPolicy()
    let layout = WorkbenchLayoutState().toggling(.learningPath)
    let shown = try #require(policy.transition(from: layout, action: .show, availableWindowWidth: 2000))
    #expect(!shown.panes.learningPathIsPresented)
  }

  @Test("Video Settings diagnostic pull happens once on show")
  func diagnosticPull() throws {
    let policy = VideoSettingsVisibilityPolicy()
    let shown = try #require(videoSettingsOperatorActionDisposition(
      from: WorkbenchLayoutState(), action: .show, availableWindowWidth: 1600, policy: policy))
    #expect(shown.shouldRefreshDiagnostics)
    #expect(shown.layout.panes.learningPathIsPresented)
    let repeated = try #require(videoSettingsOperatorActionDisposition(
      from: shown.layout, action: .show, availableWindowWidth: 1600, policy: policy))
    #expect(!repeated.shouldRefreshDiagnostics)
  }

  @Test("the inspector collapses when remaining content cannot fit")
  func videoSettingsCollapse() {
    let policy = VideoSettingsVisibilityPolicy()
    let shown = WorkbenchLayoutState(videoSettingsIsPresented: true)
    let minimum = policy.minimumContentWidth(for: shown.panes)
    #expect(shown.collapsingVideoSettingsIfNeeded(availableContentWidth: minimum, policy: policy) == shown)
    #expect(!shown.collapsingVideoSettingsIfNeeded(availableContentWidth: minimum - 1,
      policy: policy).videoSettingsIsPresented)
  }

  @Test("closing Learning changes presentation without changing Learning or its action requests")
  @MainActor
  func hidingPanelPreservesLearning() async throws {
    let workspace = makeCausalSimulatorAppFixture().workspace
    let item = LearningPathItemID.humanGuidedDiscovery(.penInteraction)
    let before = workspace.testPlotterUIProjection(selectedItemID: item, includesLearningPath: true)
    let hidden = WorkbenchLayoutState().toggling(.learningPath)
    let after = workspace.testPlotterUIProjection(selectedItemID: item, includesLearningPath: true)
    #expect(!hidden.panes.learningPathIsPresented)
    #expect(before.learningIsEnabled == after.learningIsEnabled)
    #expect(before.semantic.actions == after.semantic.actions)
    #expect(before.currentLearningPathItemID == after.currentLearningPathItemID)
    let panel = LearningPathView(selection: .constant(.init(current: item)),
      projection: try #require(after.learningPath), currentLearningPathItemID: item,
      plotterUIProjection: after.semantic, plotterUIIntentSink: workspace, close: {})
    #expect(panel.projection == after.learningPath)
    await workspace.shutdown()
  }
}
