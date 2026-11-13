import PortraitCore
import PortraitLibrary
import PortraitStudioUI
import PlotterEpisodeModel
import PlotterEpisodeRuntime
import PlotterModel
import PlotterRuntime
import PlotterUI
import SwiftUI
import AppKit

struct PlotterApplicationRuntimeView: View {
  @Bindable var application: PlotterApplicationRuntime
  var drawingDestinationRestorationCompleted: @MainActor (@escaping DrawingDestinationReveal) -> Void = { _ in }
  @AppStorage("AdaptivePlotter.workbenchLayout.v1") private var savedLayout = Data()
  @State private var gateLayout: WorkbenchLayoutState?
  @State private var selection = LearningPathSelectionState(current: .humanGuidedDiscovery(.penInteraction))
  @State private var actionSurfaceViewport = ActionSurfaceViewportState()
  @State private var historyIsPresented = false
  @State private var materialSettingsPresented = false
  @State private var manualMotionDraft = ManualMotionDraft()
  @State private var diagnosticExporter = WorkbenchDiagnosticExporter()
  @State private var pendingDrawingPlacement: PlotterDrawingDraftCameraPlacement?
  @State private var pendingPointSelection: PlotterPointSelectionSubmission?
  @State private var panelError: String?
  @State private var replacementPaperRequest: PlotterUIRequest?
  @State private var confirmsPaperReplacement = false

  private var layout: Binding<WorkbenchLayoutState> {
    Binding(get: { gateLayout ?? .restored(from: savedLayout) }, set: {
      if gateLayout != nil { gateLayout = $0 } else { savedLayout = $0.encoded }
    })
  }
  private var drawingDestinationWindowPresentation: DrawingDestinationWindowPresentation {
    .init(layout: layout, didReveal: { _ in historyIsPresented = false })
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
        HStack {
          ForEach([WorkbenchPanel.drawing, .motion, .videoSettings], id: \.self) { panel in
            Button(panel.title) { togglePanel(panel) }
          }
          Spacer()
        }.padding(.horizontal, 12).padding(.vertical, 6)
        if historyIsPresented {
          DrawingExecutionHistoryView(application: application, close: { historyIsPresented = false })
        } else {
        WorkbenchPanels(layout: layout, select: { panel in Task { await preparePanel(panel) } },
          autosavePrefix: RunningAppPreviewPerformanceGate.isRequested ? nil : "AdaptivePlotter.workbench.v2",
          content: panelContent) {
          WorkbenchCameraCanvas(application: application, semantic: ui.semantic,
            showVideoSettings: { layout.wrappedValue.setPresented(.videoSettings, true) },
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
    .environment(\.drawingPresentationPolicy, DrawingPresentationPolicy(modalUnavailableReason:
      WorkbenchStopPresentation.modalUnavailableReason(in: ui.semantic)))
    .onChange(of: ui.currentLearningPathItemID, initial: true) { _, item in selection.updateCurrent(item) }
    .toolbar {
      WorkbenchToolbar(savedLearningAction: ui.semantic.actions.first { action in
          if case .learningAction(let request) = action.intent { return request.action == .applySavedLearning }
          return false
        }, controllerSession: ui.controllerSession, plotterUIProjection: ui.semantic,
        plotterUIIntentSink: application, diagnosticsAreExporting: diagnosticExporter.isExporting,
        exportDiagnostics: exportDiagnostics)
    }
    .toolbarRole(.automatic)
    .focusedSceneValue(\.workbenchMenu, WorkbenchMenuContext(layout: layout.wrappedValue,
      toggle: togglePanel, restore: restoreDefaultLayout))
    .task {
      let launch = RunningAppPreviewPerformanceGate.usesSimulatedWorkbench
        ? AdaptivePlotterLaunchPolicy(arguments: [AdaptivePlotterLaunchPolicy.simulatedArgument, "YES"])
        : AdaptivePlotterLaunchPolicy.current
      await application.awaitWindowStartup(launch)
      guard !Task.isCancelled, application.drawingDestinationStartupHasSettled else { return }
      if application.receivedDrawings.projectedDrawing != nil { drawingDestinationWindowPresentation.showDestination() }
      drawingDestinationRestorationCompleted(drawingDestinationWindowPresentation.revealAction(application: application))
      if RunningAppPreviewPerformanceGate.isRequested {
        gateLayout = WorkbenchLayoutState(presented: [.guidedLearning, .motion, .activeLearning])
      }
      await RunningAppPreviewPerformanceGate.runIfRequested(application: application,
        revealPanel: { panel in
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
    layout.wrappedValue.setPresented(panel, !layout.wrappedValue.isPresented(panel))
  }

  private func restoreDefaultLayout() { layout.wrappedValue = WorkbenchLayoutState() }

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
              Button("Execution History", systemImage: "clock.arrow.circlepath") { historyIsPresented = true }
                .accessibilityIdentifier("drawing.executionHistory.open")
              DrawingStudioView(presentation: ui.drawingStudio, plotterUIProjection: ui.semantic,
                plotterUIIntentSink: application, panel: .drawing,
                openReviewer: { historyIsPresented = true }) {
                  studioMaterialControls
                  paperControls(ui, showsExplanation: false)
                }
            }.padding(12)
          }
        }
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
        canApply: false,
        measure: { await application.prepareMaterialInspection() }, apply: { _ in "Prepare drawing detail in Portrait Studio." },
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

    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("drawing.section.material")
  }

  private func paperControls(_ ui: PlotterAppUIProjection, showsExplanation: Bool = true) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      if showsExplanation && !application.paperCoverageIsCurrent {
        StudioHelpButton("Paper coverage", text: ui.workbenchCapability.paper.detail)
      }
      if application.drawingRunSnapshot?.terminal != nil {
        Text("To draw again: replace the sheet, choose Replace Paper, confirm sheet coverage, then Draw. Your drawing and placement are retained.")
          .font(.caption)
      }
      Text(application.sheetAcceptanceDetail).font(.caption).foregroundStyle(.secondary)
      VStack(alignment: .leading, spacing: 6) {
        OperatorRequestButton(title: application.sheetAcceptanceTitle,
          request: ui.semantic.request(for: PlotterAppUIActionID.drawingDraft(.assertPaperCoverage)),
          unavailableReason: application.paperAcceptanceUnavailableReason, sink: application,
          showsUnavailableReason: false)
          .accessibilityIdentifier("drawing.confirmSheet")
          .help(application.sheetAcceptanceDetail)
        if let reason = application.paperAcceptanceUnavailableReason {
          StudioHelpButton("Paper coverage unavailable", text: reason)
        }
        Button("Replace Paper…") {
          replacementPaperRequest = ui.semantic.request(for: PlotterAppUIActionID.paperNewSheet)
          confirmsPaperReplacement = replacementPaperRequest != nil
        }
        .disabled(ui.semantic.request(for: PlotterAppUIActionID.paperNewSheet) == nil)
        .accessibilityIdentifier("drawing.replacePaper")
        .help(ui.paperManagementUnavailableReason ?? "Replace the sheet on the same surface, then confirm. Keeps the drawing and placement.")
        .confirmationDialog("Replace the paper on the same surface", isPresented: $confirmsPaperReplacement) {
          Button("Paper Replaced — Keep Drawing") {
            guard let request = replacementPaperRequest else { return }
            replacementPaperRequest = nil
            Task {
              if case .refused(let refusal) = await application.submitPlotterUIRequest(request) {
                panelError = refusal.remedy
              }
            }
          }
          Button("Cancel", role: .cancel) { replacementPaperRequest = nil }
        } message: {
          Text("Confirm after replacing the sheet. Calibration and drawing placement are retained. Confirm sheet coverage next, then press Draw.")
        }
        Menu("Paper Options") {
          Button("Contact Plane Changed") {
            Task { panelError = await submit(PlotterAppUIActionID.paperContactPlane) }
          }
        }.disabled(ui.paperManagementUnavailableReason != nil)
      }
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("drawing.section.paper")
  }

  private func preparePanel(_ panel: WorkbenchPanel) async {
    panelError = nil
    if panel == .guidedLearning || panel == .activeLearning || panel == .drawing {
      panelError = await submit(PlotterAppUIActionID.observationCameraRole(.plotter))
    }
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
  static func modalUnavailableReason(in projection: PlotterUIProjection) -> String? {
    actions(in: projection).contains { $0.unavailableReason == nil }
      ? "Stop the active operation before opening a file picker or camera panel." : nil
  }
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
