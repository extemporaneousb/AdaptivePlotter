import PlotterEpisodeModel
import PlotterEpisodeRuntime
import PlotterModel
import PlotterRuntime
import PlotterUI
import SwiftUI
import AppKit

struct PlotterApplicationRuntimeView: View {
  @Bindable var application: PlotterApplicationRuntime
  @AppStorage("AdaptivePlotter.workbenchLayout.v1") private var savedLayout = Data()
  @State private var gateLayout: WorkbenchLayoutState?
  @State private var selection = LearningPathSelectionState(current: .humanGuidedDiscovery(.penInteraction))
  @State private var actionSurfaceViewport = ActionSurfaceViewportState()
  @State private var canvasShowsPortraitPhoto = false
  @State private var manualMotionDraft = ManualMotionDraft()
  @State private var diagnosticExporter = WorkbenchDiagnosticExporter()
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
      if let panelError {
        HStack {
          Text(panelError).font(.caption).foregroundStyle(.orange).textSelection(.enabled)
          Spacer()
          Button("Dismiss") { self.panelError = nil }.buttonStyle(.borderless)
        }.padding(.horizontal, 10).padding(.vertical, 4)
      }
      Divider()
      if let status = diagnosticExporter.status {
        HStack {
          Text(status).font(.caption).textSelection(.enabled).lineLimit(2)
          if let url = diagnosticExporter.savedURL {
            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
          }
          Spacer()
          if !diagnosticExporter.isExporting {
            Button("Dismiss") { diagnosticExporter.dismissStatus() }.buttonStyle(.borderless)
          }
        }.padding(.horizontal, 10).padding(.vertical, 4)
      }
      DrawingStudioActiveRunStatus(runState: ui.drawingStudio.runState).equatable()
      WorkbenchPanels(layout: layout, select: { panel in Task { await preparePanel(panel) } },
        autosavePrefix: RunningAppPreviewPerformanceGate.isRequested ? nil : "AdaptivePlotter.workbench.v2",
        content: panelContent) {
        WorkbenchCameraCanvas(application: application, semantic: ui.semantic,
          showsPortraitPhoto: canvasShowsPortraitPhoto,
          viewport: $actionSurfaceViewport, pendingDrawingPlacement: $pendingDrawingPlacement,
          pendingPointSelection: $pendingPointSelection)
      }
      Divider()
      WorkbenchVoiceView(
        context: ui.learningPath.map { learning in
          let current = selection.selected == ui.currentLearningPathItemID ? learning
            : application.learningPathProjection(selectedItemID: ui.currentLearningPathItemID)
          return WorkbenchVoiceContext(presentation: current.selectedAction, projection: ui.semantic,
            actionStrip: learning.currentActionStrip)
        }, controller: application.workbenchVoiceController)
        .padding(.horizontal, 12).padding(.vertical, 6)
    }
    .onChange(of: ui.currentLearningPathItemID, initial: true) { _, item in selection.updateCurrent(item) }
    .toolbar {
      WorkbenchToolbar(controllerSession: ui.controllerSession, plotterUIProjection: ui.semantic,
        plotterUIIntentSink: application, diagnosticsAreExporting: diagnosticExporter.isExporting,
        exportDiagnostics: exportDiagnostics)
    }
    .toolbarRole(.editor)
    .focusedSceneValue(\.workbenchMenu, WorkbenchMenuContext(layout: layout.wrappedValue,
      toggle: togglePanel, restore: { layout.wrappedValue = WorkbenchLayoutState() }))
    .task {
      let launch = RunningAppPreviewPerformanceGate.usesSimulatedWorkbench
        ? AdaptivePlotterLaunchPolicy(arguments: [AdaptivePlotterLaunchPolicy.simulatedArgument, "YES"])
        : AdaptivePlotterLaunchPolicy.current
      await application.performApplicationStartup(launch)
      if RunningAppPreviewPerformanceGate.isRequested {
        gateLayout = WorkbenchLayoutState(presented: [.guidedLearning, .motion, .activeLearning, .portraitStudio])
      }
      await RunningAppPreviewPerformanceGate.runIfRequested(application: application,
        revealPanel: { panel in layout.wrappedValue.setPresented(panel, true) }, workbenchLayout: layout)
    }
  }

  private func exportDiagnostics() {
    diagnosticExporter.export(WorkbenchDiagnosticCapture(application: application,
      projection: currentProjection().semantic))
  }

  private func togglePanel(_ panel: WorkbenchPanel) {
    WorkbenchRequestTelemetry.nativeActionHandled("workbench.toggle.\(panel.rawValue)")
    if layout.wrappedValue.isPresented(panel) { layout.wrappedValue.setPresented(panel, false) }
    else { reveal(panel) }
  }

  @ViewBuilder func panelContent(_ panel: WorkbenchPanel) -> some View {
    // Resolve the cached projection at the rendering boundary. The retained
    // dock closure holds the application reference and local bindings, never
    // the frame-bearing aggregate projection.
    let ui = currentProjection()
    switch panel {
    case .guidedLearning:
      LearningPathView(selection: $selection, projection: ui.learningPath, learningMode: ui.learningMode,
        plotterUIProjection: ui.semantic,
        plotterUIIntentSink: application)
    case .videoSettings:
      WorkbenchVideoSettings(application: application, projection: ui.observationConfiguration,
        semantic: ui.semantic, viewport: $actionSurfaceViewport,
        cameraSelected: { canvasShowsPortraitPhoto = false })
    case .motion:
      ScrollView {
        MotionPanel(draft: $manualMotionDraft, presentation: ui.manualMotion,
          controllerSession: ui.controllerSession,
          motionSnapshotReader: { await application.latestMotionReadoutSnapshot() },
          learningIsEnabled: ui.learningIsEnabled,
          plotterUIProjection: ui.semantic, plotterUIIntentSink: application).padding(10)
      }
    case .activeLearning:
      ScrollView {
        VStack(alignment: .leading, spacing: 12) {
          paperControls(ui)
          DrawingStudioView(presentation: ui.drawingStudio, plotterUIProjection: ui.semantic,
            plotterUIIntentSink: application, panel: .activeLearning)
          DisclosureGroup("Measure Learning frame") {
            AxisMetricCalibrationView(geometry: application.axisMetricFrame,
              latestMeasurement: application.latestAxisMetricMeasurement,
              proposal: application.axisCalibrationProposal,
              status: application.axisMetricStatus ?? application.axisMetricRecoveryError,
              busy: application.axisCalibrationInProgress,
              applyUnavailableReason: application.axisMetricApplyUnavailableReason,
              onSave: { edges, method, confirmed in
                await application.saveAxisMetricMeasurement(edges, method: method, axesConfirmed: confirmed)
              }, onApply: { await application.applyAxisMetricCalibration() })
            if application.axisMetricHasPendingPublication {
              Button("Retry calibration evidence save") {
                Task { await application.retryAxisMetricEvidencePublication() }
              }
            }
          }
        }.padding(12)
      }
    case .portraitStudio:
      ScrollView {
        VStack(alignment: .leading, spacing: 12) {
          PortraitStudioView(model: application.portraitStudio, strokeStyle: application.drawingStrokeStyle,
            previewSource: application.portraitPlanePreviewSource,
            showOnPlotter: usePortraitProgram, selectCamera: { await selectCamera(.portrait) },
            showPhoto: { canvasShowsPortraitPhoto = true }) {
              DrawingStudioPhysicalGallery(application: application)
            }
          if application.workbenchCameraRole == .plotter {
            DrawingStudioView(presentation: ui.drawingStudio, plotterUIProjection: ui.semantic,
              plotterUIIntentSink: application, panel: .portraitStudio) {
                studioMaterialControls
                paperControls(ui, showsExplanation: false)
              }
          } else {
            studioMaterialControls
          }
        }.padding(12)
      }
    }
  }

  private var studioMaterialControls: some View {
    VStack(alignment: .leading, spacing: 10) {
      TextField("Paper stock for material measurement", text: $application.materialPaperStock)
      Picker("Existing ink source", selection: $application.materialUsesBorderImages) {
        Text("Drawing Border before/after").tag(true)
        Text("Calibration marks in current plotter frame").tag(false)
      }
      DrawingMaterialControls(library: application.drawingMaterials,
        currentApplicability: application.currentMaterialApplicability,
        measurementStatus: application.materialMeasurementStatus,
        canMeasureExistingInk: application.currentMaterialApplicability != nil,
        canApply: application.drawingDraftSnapshot.plan != nil,
        measure: { await application.prepareMaterialInspection() }, apply: applyPortraitMaterial,
        verifyMedia: { await application.verifyMaterialMedia($0) })
      .onChange(of: application.drawingMaterials.activeKey) { _, _ in
        application.drawingMaterialSelectionDidChange()
      }
      .sheet(item: $application.materialInspection) { inspection in
        DrawingMaterialInspectionView(inspection: inspection,
          confirm: { await application.confirmMaterialInspection(inspection) },
          cancel: { application.materialInspection = nil })
      }
      Button("Assess Material at Current Scale") {
        Task { panelError = await application.assessCurrentMaterial() }
      }.accessibilityIdentifier("drawing.material.assess")
      if let status = application.materialFeasibilityStatus {
        Text(status).font(.caption).foregroundStyle(.secondary)
      }
      if let context = application.portraitStudio.selectedCandidate?.recipe.vectorOptions.materialContext,
        let program = application.drawingDraftSnapshot.program,
        let plan = application.drawingDraftSnapshot.plan,
        !context.matches(drawingHeightMM: program.fieldExtent.height * plan.placement.uniformScale,
          profileKey: application.drawingMaterials.activeKey) {
        Text("Material or drawing scale changed. Apply the current material to create a newly adapted candidate.")
          .font(.caption).foregroundStyle(.secondary)
      }
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("drawing.section.material")
  }

  private func paperControls(_ ui: PlotterAppUIProjection, showsExplanation: Bool = true) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      if showsExplanation && !application.paperCoverageIsCurrent {
        Text(ui.workbenchCapability.paper.detail).font(.caption).foregroundStyle(.secondary)
      }
      HStack {
        OperatorRequestButton(title: application.paperCoverageIsCurrent ? "Sheet Confirmed" : "Sheet Covers Target",
          request: ui.semantic.request(for: PlotterAppUIActionID.drawingDraft(.assertPaperCoverage)),
          unavailableReason: ui.paperManagementUnavailableReason, sink: application)
          .accessibilityIdentifier("drawing.confirmSheet")
          .help("Confirm that this sheet covers the outlined Drawing Boundary.")
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
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("drawing.section.paper")
  }

  private func reveal(_ panel: WorkbenchPanel) {
    layout.wrappedValue.setPresented(panel, true)
    if panel == .portraitStudio { Task { await application.portraitStudio.discover(excluding: application.observationConfigurationProjection.selectedCameraID) } }
  }

  private func preparePanel(_ panel: WorkbenchPanel) async {
    panelError = nil
    switch panel {
    case .guidedLearning, .activeLearning: panelError = await selectCamera(.plotter)
    case .portraitStudio: panelError = await selectCamera(.portrait)
    case .motion, .videoSettings: break
    }
  }

  private func selectCamera(_ role: WorkbenchCameraRole) async -> String? {
    canvasShowsPortraitPhoto = false
    return await submit(PlotterAppUIActionID.observationCameraRole(role))
  }

  private func usePortraitProgram(_ candidate: PortraitCandidate) async -> String? {
    canvasShowsPortraitPhoto = false
    return await application.projectPortrait(candidate)
  }

  private func applyPortraitMaterial(_ profile: DrawingMaterialProfileRevision) async -> String? {
    await application.applyPortraitMaterial(profile)
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
      Button("Achtung!", systemImage: "stop.fill") {}.operatorButton(.stop, isEnabled: false)
        .accessibilityLabel("Stop")
        .accessibilityIdentifier("workbench.stop")
    } else {
      ForEach(actions) { action in
        OperatorRequestButton(title: "Achtung!", role: .stop, request: projection.request(for: action.id),
          unavailableReason: action.unavailableReason, sink: sink, nativeActionIdentifier: "workbench.stop")
          .keyboardShortcut(.cancelAction)
          .help(action.title)
          .accessibilityLabel(action.title)
          .accessibilityIdentifier("workbench.stop")
      }
    }
  }
}
