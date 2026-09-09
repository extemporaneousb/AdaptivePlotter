import PlotterEpisodeModel
import PlotterEpisodeRuntime
import PlotterModel
import PlotterRuntime
import PlotterUI
import SwiftUI

struct PlotterApplicationRuntimeView: View {
  @Bindable var application: PlotterApplicationRuntime
  @AppStorage("AdaptivePlotter.workbenchLayout.v1") private var savedLayout = Data()
  @State private var gateLayout: WorkbenchLayoutState?
  @State private var selection = LearningPathSelectionState(current: .humanGuidedDiscovery(.penInteraction))
  @State private var actionSurfaceViewport = ActionSurfaceViewportState()
  @State private var manualMotionDraft = ManualMotionDraft()
  @State private var debugSnapshot: WorkbenchDebugSnapshot?
  @State private var pendingDrawingPlacement: PlotterDrawingDraftCameraPlacement?
  @State private var pendingPointSelection: PlotterPointSelectionSubmission?
  @State private var panelError: String?

  private var layout: Binding<WorkbenchLayoutState> {
    Binding(get: { gateLayout ?? .restored(from: savedLayout) }, set: {
      if gateLayout != nil { gateLayout = $0 } else { savedLayout = $0.encoded }
    })
  }

  private func currentProjection(program: DrawingProgram? = nil) -> PlotterAppUIProjection {
    application.plotterUIProjection(
      selectedItemID: selection.selected, manualDraft: manualMotionDraft, includesLearningPath: true,
      pendingDrawingProgram: program, pendingDrawingPlacement: pendingDrawingPlacement,
      pendingPointSelection: pendingPointSelection, observationViewport: actionSurfaceViewport)
  }

  var body: some View {
    let ui = currentProjection()
    VStack(spacing: 0) {
      commandBar(ui)
      if let panelError {
        HStack {
          Text(panelError).font(.caption).foregroundStyle(.orange).textSelection(.enabled)
          Spacer()
          Button("Dismiss") { self.panelError = nil }.buttonStyle(.borderless)
        }.padding(.horizontal, 10).padding(.vertical, 4)
      }
      Divider()
      WorkbenchPanels(layout: layout, select: reveal, content: panelContent)
      Divider()
      WorkbenchVoiceView(
        context: ui.learningPath.map { learning in
          let current = selection.selected == ui.currentLearningPathItemID ? learning
            : application.learningPathProjection(selectedItemID: ui.currentLearningPathItemID)
          return WorkbenchVoiceContext(presentation: current.selectedAction, projection: ui.semantic,
            actionStrip: learning.currentActionStrip)
        }, speech: application.speechEffectRuntime, sink: application)
        .padding(.horizontal, 12).padding(.vertical, 6)
    }
    .onChange(of: ui.currentLearningPathItemID, initial: true) { _, item in selection.updateCurrent(item) }
    .toolbar {
      WorkbenchToolbar(controllerSession: ui.controllerSession, application: application,
        motionRequestStatus: ui.motionRequestStatus, plotterUIProjection: ui.semantic,
        plotterUIIntentSink: application, capabilityPresentation: ui.workbenchCapability)
    }
    .toolbarRole(.editor)
    .sheet(item: $debugSnapshot) { WorkbenchDiagnosticsView(snapshot: $0) }
    .task {
      let launch = RunningAppPreviewPerformanceGate.usesSimulatedWorkbench
        ? AdaptivePlotterLaunchPolicy(arguments: [AdaptivePlotterLaunchPolicy.simulatedArgument, "YES"])
        : AdaptivePlotterLaunchPolicy.current
      await application.performApplicationStartup(launch)
      if RunningAppPreviewPerformanceGate.isRequested {
        var initial = WorkbenchLayoutState()
        for panel in WorkbenchPanel.allCases { initial.setPresented(panel, true) }
        initial.move(.activeLearning, to: .left)
        initial.move(.portraitStudio, to: .left)
        gateLayout = initial
      } else if layout.wrappedValue.isPresented(.portraitStudio) {
        await preparePanel(.portraitStudio)
      } else if layout.wrappedValue.isPresented(.activeLearning) {
        await preparePanel(.activeLearning)
      }
      await RunningAppPreviewPerformanceGate.runIfRequested(application: application,
        revealPanel: { panel in layout.wrappedValue.setPresented(panel, true) }, workbenchLayout: layout)
    }
  }

  private func commandBar(_ ui: PlotterAppUIProjection) -> some View {
    HStack(spacing: 12) {
      WorkbenchStopControls(projection: ui.semantic, sink: application)
      Spacer()
      Menu {
        ForEach(WorkbenchPanel.allCases) { panel in
          Button(panel.title) { reveal(panel) }
            .accessibilityIdentifier("workbench.show.\(panel.rawValue)")
        }
        Divider()
        ForEach(WorkbenchPanel.allCases) { panel in
          Menu("\(panel.title) Position") {
            ForEach(WorkbenchDock.allCases) { dock in
              Button(dock.title) { layout.wrappedValue.move(panel, to: dock) }
            }
            if layout.wrappedValue.isPresented(panel) {
              Button("Hide") { layout.wrappedValue.setPresented(panel, false) }
            }
          }
        }
      } label: { Label("Panels", systemImage: "rectangle.split.3x1") }
      .accessibilityIdentifier("workbench.panels")
      Button {
        debugSnapshot = WorkbenchDebugSnapshot(application: application, projection: currentProjection().semantic)
      } label: { Image(systemName: "wrench.and.screwdriver") }
      .accessibilityLabel("Diagnostics")
      .keyboardShortcut("d", modifiers: [.command, .shift])
    }
    .padding(.horizontal, 10).padding(.vertical, 6)
  }

  @ViewBuilder private func panelContent(_ panel: WorkbenchPanel) -> some View {
    // Resolve the cached projection at the rendering boundary. The retained
    // dock closure holds the application reference and local bindings, never
    // the frame-bearing aggregate projection.
    let ui = currentProjection()
    switch panel {
    case .guidedLearning:
      LearningPathView(selection: $selection, projection: ui.learningPath, learningMode: ui.learningMode,
        currentLearningPathItemID: ui.currentLearningPathItemID, plotterUIProjection: ui.semantic,
        plotterUIIntentSink: application)
    case .video:
      WorkbenchVideoPanel(application: application, projection: ui.observationConfiguration,
        semantic: ui.semantic, viewport: $actionSurfaceViewport,
        pendingDrawingPlacement: $pendingDrawingPlacement, pendingPointSelection: $pendingPointSelection)
    case .motion:
      ScrollView {
        MotionPanel(draft: $manualMotionDraft, presentation: ui.manualMotion,
          controllerSession: ui.controllerSession, learningIsEnabled: ui.learningIsEnabled,
          plotterUIProjection: ui.semantic, plotterUIIntentSink: application).padding(10)
      }
    case .activeLearning:
      ScrollView {
        VStack(alignment: .leading, spacing: 12) {
          paperControls(ui)
          DrawingStudioView(presentation: ui.drawingStudio, plotterUIProjection: ui.semantic,
            plotterUIIntentSink: application, panel: .activeLearning)
        }.padding(12)
      }
    case .portraitStudio:
      ScrollView {
        VStack(alignment: .leading, spacing: 12) {
          PortraitStudioView(model: application.portraitStudio, strokeStyle: application.drawingStrokeStyle,
            showOnPlotter: usePortraitProgram, selectCamera: { await selectCamera(.portrait) })
          if application.workbenchCameraRole == .plotter {
            paperControls(ui)
            DrawingStudioView(presentation: ui.drawingStudio, plotterUIProjection: ui.semantic,
              plotterUIIntentSink: application, panel: .portraitStudio)
          }
        }.padding(12)
      }
    }
  }

  private func paperControls(_ ui: PlotterAppUIProjection) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      if !application.paperCoverageIsCurrent {
        Text(ui.workbenchCapability.paper.detail).font(.caption).foregroundStyle(.secondary)
      }
      HStack {
        OperatorRequestButton(title: application.paperCoverageIsCurrent ? "Sheet Confirmed" : "Sheet Covers Target",
          request: ui.semantic.request(for: PlotterAppUIActionID.drawingDraft(.assertPaperCoverage)),
          unavailableReason: ui.paperManagementUnavailableReason, sink: application)
        Menu("Paper") {
          Button("New Sheet — Same Contact Plane") {
            Task { panelError = await submit(PlotterAppUIActionID.paperNewSheet) }
          }
          Button("Contact Plane Changed") {
            Task { panelError = await submit(PlotterAppUIActionID.paperContactPlane) }
          }
        }.disabled(ui.paperManagementUnavailableReason != nil)
      }
    }
  }

  private func reveal(_ panel: WorkbenchPanel) {
    layout.wrappedValue.setPresented(panel, true)
    Task { await preparePanel(panel) }
  }

  private func preparePanel(_ panel: WorkbenchPanel) async {
    panelError = nil
    switch panel {
    case .guidedLearning, .activeLearning: panelError = await selectCamera(.plotter)
    case .portraitStudio: panelError = await selectCamera(.portrait)
    case .motion, .video: break
    }
  }

  private func selectCamera(_ role: WorkbenchCameraRole) async -> String? {
    await submit(PlotterAppUIActionID.observationCameraRole(role))
  }

  private func usePortraitProgram(_ program: DrawingProgram) async -> String? {
    layout.wrappedValue.setPresented(.video, true)
    if let error = await selectCamera(.plotter) { return error }
    if let error = await submit(PlotterAppUIActionID.drawingDraft(.selectProgram(program)), program: program) {
      return error
    }
    return await submit(PlotterAppUIActionID.drawingDraft(.fitInDrawableRegion))
  }

  private func submit(_ action: PlotterUIActionID, program: DrawingProgram? = nil) async -> String? {
    let projection = currentProjection(program: program).semantic
    guard let request = projection.request(for: action) else {
      return projection.action(id: action)?.unavailableReason ?? "The requested action is unavailable in the current state."
    }
    if case .refused(let refusal) = await application.submitPlotterUIRequest(request) { return refusal.remedy }
    return nil
  }
}

enum WorkbenchStopPresentation {
  static func actions(in projection: PlotterUIProjection) -> [PlotterUIAction] {
    projection.actions.filter { action in
      if action.isLearningStop { return true }
      switch action.intent {
      case .manualStop, .drawingRun(.stop): return true
      default: return false
      }
    }
  }
}

struct WorkbenchStopControls: View {
  let projection: PlotterUIProjection
  let sink: any PlotterUIIntentSink
  var body: some View {
    let actions = WorkbenchStopPresentation.actions(in: projection)
    if actions.isEmpty {
      Button("Stop", systemImage: "stop.fill") {}.operatorButton(.stop, isEnabled: false)
        .accessibilityIdentifier("workbench.stop")
    } else {
      ForEach(actions) { action in
        OperatorRequestButton(title: "Stop", role: .stop, request: projection.request(for: action.id),
          unavailableReason: action.unavailableReason, sink: sink, nativeActionIdentifier: "workbench.stop")
          .keyboardShortcut(.cancelAction)
          .help(action.title)
          .accessibilityIdentifier("workbench.stop")
      }
    }
  }
}
