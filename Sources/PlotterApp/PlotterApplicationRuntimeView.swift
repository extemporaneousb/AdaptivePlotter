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
  @State private var reviewerIsPresented = false
  @State private var materialSettingsPresented = false
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
          Text("Action needs attention").font(.caption).foregroundStyle(.orange)
          StudioHelpButton("Action needs attention", text: panelError)
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
      DrawingStudioActiveRunStatus(runState: ui.drawingStudio.runState,
        terminalDisposition: application.drawingRunSnapshot?.terminal?.disposition,
        resultPhotoMissing: application.drawingRunSnapshot?.terminal.map {
          !DrawingReviewPhotographs.hasResultPhoto($0.record)
        } ?? false).equatable()
      if layout.wrappedValue.isPresented(.portraitStudio) {
        VStack(spacing: 0) {
          HStack {
            Label("Portrait Studio", systemImage: "person.crop.rectangle").font(.headline)
            Spacer()
            Button("Plotter", systemImage: "video") {
              WorkbenchRequestTelemetry.nativeActionHandled("workbench.hide.portraitStudio")
              closePortraitStudio()
            }
            .accessibilityIdentifier("workbench.hide.portraitStudio")
          }.padding(.horizontal, 12).padding(.vertical, 6)
          panelContent(.portraitStudio)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("workbench.panel.portraitStudio")
      } else {
        WorkbenchPanels(layout: layout, select: { panel in Task { await preparePanel(panel) } },
          autosavePrefix: RunningAppPreviewPerformanceGate.isRequested ? nil : "AdaptivePlotter.workbench.v2",
          content: panelContent) {
          WorkbenchCameraCanvas(application: application, semantic: ui.semantic,
            viewport: $actionSurfaceViewport, pendingDrawingPlacement: $pendingDrawingPlacement,
            pendingPointSelection: $pendingPointSelection)
        }
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
    .background {
      PortraitScreenIllumination(isActive: application.portraitStudio.screenIlluminationActive) {
        Task { await application.portraitStudio.cancelRendering() }
      }
    }
    .sheet(isPresented: $reviewerIsPresented) {
      DrawingReviewerView(application: application, close: { reviewerIsPresented = false },
        showOnPlotter: usePortraitProgram)
    }
    .onChange(of: ui.currentLearningPathItemID, initial: true) { _, item in selection.updateCurrent(item) }
    .toolbar {
      WorkbenchToolbar(controllerSession: ui.controllerSession, plotterUIProjection: ui.semantic,
        plotterUIIntentSink: application, diagnosticsAreExporting: diagnosticExporter.isExporting,
        exportDiagnostics: exportDiagnostics)
    }
    .toolbarRole(.editor)
    .focusedSceneValue(\.workbenchMenu, WorkbenchMenuContext(layout: layout.wrappedValue,
      toggle: togglePanel, restore: restoreDefaultLayout))
    .task {
      let launch = RunningAppPreviewPerformanceGate.usesSimulatedWorkbench
        ? AdaptivePlotterLaunchPolicy(arguments: [AdaptivePlotterLaunchPolicy.simulatedArgument, "YES"])
        : AdaptivePlotterLaunchPolicy.current
      await application.performApplicationStartup(launch)
      if RunningAppPreviewPerformanceGate.isRequested {
        gateLayout = WorkbenchLayoutState(presented: [.guidedLearning, .motion, .activeLearning, .portraitStudio])
      }
      await RunningAppPreviewPerformanceGate.runIfRequested(application: application,
        revealPanel: { panel in
          if panel != .portraitStudio { layout.wrappedValue.setPresented(.portraitStudio, false) }
          layout.wrappedValue.setPresented(panel, true)
        }, workbenchLayout: layout)
    }
  }

  private func exportDiagnostics() {
    diagnosticExporter.export(WorkbenchDiagnosticCapture(application: application,
      projection: currentProjection().semantic, viewport: actionSurfaceViewport))
  }

  private func togglePanel(_ panel: WorkbenchPanel) {
    WorkbenchRequestTelemetry.nativeActionHandled("workbench.toggle.\(panel.rawValue)")
    if panel == .portraitStudio && layout.wrappedValue.isPresented(panel) { closePortraitStudio() }
    else if layout.wrappedValue.isPresented(panel) { layout.wrappedValue.setPresented(panel, false) }
    else { reveal(panel) }
  }

  private func closePortraitStudio() {
    layout.wrappedValue.setPresented(.portraitStudio, false)
    Task { panelError = await selectCamera(.plotter) }
  }

  private func restoreDefaultLayout() {
    let leavesPortrait = layout.wrappedValue.isPresented(.portraitStudio)
    layout.wrappedValue = WorkbenchLayoutState()
    if leavesPortrait { Task { panelError = await selectCamera(.plotter) } }
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
        cameraSelected: {})
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
    case .drawing:
      GeometryReader { geometry in
        VStack(spacing: 0) {
          if let preview = ui.drawingStudio.drawingPreview {
            DrawingStudioPlanPreviewView(preview: preview,
              imageHeight: min(160, max(24, geometry.size.height * 0.22)))
              .padding(.horizontal, 12).padding(.vertical, 8)
            Divider()
          }
          ScrollView {
            VStack(alignment: .leading, spacing: 12) {
              HStack {
                Button("Drawings", systemImage: "square.grid.2x2") { reviewerIsPresented = true }
                  .accessibilityIdentifier("drawing.openReviewer")
                Spacer()
                Button("Portrait Studio", systemImage: "person.crop.rectangle") { reveal(.portraitStudio) }
              }
              DrawingStudioView(presentation: ui.drawingStudio, plotterUIProjection: ui.semantic,
                plotterUIIntentSink: application, panel: .drawing,
                openReviewer: { reviewerIsPresented = true }) {
                  studioMaterialControls
                  paperControls(ui, showsExplanation: false)
                }
            }.padding(12)
          }
        }
      }
    case .portraitStudio:
      PortraitStudioView(model: application.portraitStudio, strokeStyle: application.drawingStrokeStyle,
        previewSource: application.portraitPlanePreviewSource,
        showOnPlotter: usePortraitProgram, selectCamera: { await selectCamera(.portrait) },
        openReviewer: { reviewerIsPresented = true })
        .padding(12)
        .task(id: application.observationConfigurationProjection.selectedCameraID) {
          await application.portraitStudio.discover(excluding: application.observationConfigurationProjection.selectedCameraID)
        }
    }
  }

  private var studioMaterialControls: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack {
        Text("Pen & material").font(.headline)
        Spacer()
        Button("Measurement setup", systemImage: "slider.horizontal.3") { materialSettingsPresented = true }
          .labelStyle(.iconOnly)
          .popover(isPresented: $materialSettingsPresented) {
            VStack(alignment: .leading, spacing: 12) {
              Text("Material measurement").font(.headline)
              TextField("Paper stock", text: $application.materialPaperStock)
              Picker("Image source", selection: $application.materialUsesBorderImages) {
                Text("Drawing Border before/after").tag(true)
                Text("Calibration marks").tag(false)
              }
              StudioHelpButton("Measurement source", text: "Choose the existing images used to estimate deposited ink width. This does not select or change the drawing's source photo.")
            }.padding(16).frame(width: 320)
          }
      }
      DrawingMaterialControls(library: application.drawingMaterials,
        currentApplicability: application.currentMaterialApplicability,
        measurementStatus: application.materialMeasurementStatus,
        canMeasureExistingInk: application.currentMaterialApplicability != nil,
        canApply: application.drawingDraftSnapshot.artworkPlan?.sourceProgramContentHash
          == application.portraitStudio.selectedCandidate?.program.contentHash
          && application.portraitStudio.selectedCandidate != nil,
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
      Button("Check Detail at This Size") {
        Task { panelError = await application.assessCurrentMaterial() }
      }.accessibilityIdentifier("drawing.material.assess")
      if let status = application.materialFeasibilityStatus {
        StudioHelpButton("Detail check", text: status)
      }
      if let context = application.portraitStudio.selectedCandidate?.recipe.vectorOptions.materialContext,
        let height = application.portraitPlanePreviewSource.resolve(
          program: application.portraitStudio.selectedCandidate?.program, nominalWidth: 0.4).materialReferenceHeight,
        !context.matches(drawingHeightMM: height,
          profileKey: application.drawingMaterials.activeKey) {
        HStack {
          Text("Detail adaptation out of date").font(.caption)
          StudioHelpButton("Detail adaptation", text: "The drawing scale or pen changed. Adapt Detail creates a new drawing with spacing adjusted for the current width; it does not change calibration.")
        }
      }
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("drawing.section.material")
  }

  private func paperControls(_ ui: PlotterAppUIProjection, showsExplanation: Bool = true) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      if showsExplanation && !application.paperCoverageIsCurrent {
        StudioHelpButton("Paper coverage", text: ui.workbenchCapability.paper.detail)
      }
      Text(application.sheetAcceptanceDetail).font(.caption).foregroundStyle(.secondary)
      HStack {
        OperatorRequestButton(title: application.sheetAcceptanceTitle,
          request: ui.semantic.request(for: PlotterAppUIActionID.drawingDraft(.assertPaperCoverage)),
          unavailableReason: application.paperAcceptanceUnavailableReason, sink: application,
          showsUnavailableReason: false)
          .accessibilityIdentifier("drawing.confirmSheet")
          .help(application.sheetAcceptanceDetail)
        if let reason = application.paperAcceptanceUnavailableReason {
          StudioHelpButton("Paper coverage unavailable", text: reason)
        }
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
    let leavesPortrait = panel != .portraitStudio && layout.wrappedValue.isPresented(.portraitStudio)
    if panel != .portraitStudio { layout.wrappedValue.setPresented(.portraitStudio, false) }
    layout.wrappedValue.setPresented(panel, true)
    Task { await preparePanel(panel, leavingPortrait: leavesPortrait) }
  }

  private func preparePanel(_ panel: WorkbenchPanel, leavingPortrait: Bool = false) async {
    panelError = nil
    switch panel {
    case .guidedLearning, .activeLearning, .drawing:
      layout.wrappedValue.setPresented(.portraitStudio, false)
      panelError = await selectCamera(.plotter)
    case .portraitStudio: break
    case .motion, .videoSettings:
      if leavingPortrait { panelError = await selectCamera(.plotter) }
    }
  }

  private func selectCamera(_ role: WorkbenchCameraRole) async -> String? {
    return await submit(PlotterAppUIActionID.observationCameraRole(role))
  }

  private func usePortraitProgram(_ candidate: PortraitCandidate) async -> String? {
    let error = await application.projectPortrait(candidate)
    if error == nil {
      layout.wrappedValue.setPresented(.portraitStudio, false)
      layout.wrappedValue.setPresented(.drawing, true)
    }
    return error
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
