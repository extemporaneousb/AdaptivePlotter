import PlotterEpisodeModel
import PlotterEpisodeRuntime
import PlotterRuntime
import PlotterUI
import SwiftUI

struct WorkbenchVideoPanel: View {
  let application: PlotterApplicationRuntime
  let projection: PlotterObservationConfigurationProjection
  let semantic: PlotterUIProjection
  @Binding var viewport: ActionSurfaceViewportState
  @Binding var pendingDrawingPlacement: PlotterDrawingDraftCameraPlacement?
  @Binding var pendingPointSelection: PlotterPointSelectionSubmission?
  @AppStorage("AdaptivePlotter.videoSettingsPresented") private var settingsArePresented = false
  @State private var requestError: String?

  var body: some View {
    VStack(spacing: 0) {
      HStack {
        HStack(spacing: 4) {
          ForEach([WorkbenchCameraRole.plotter, .portrait], id: \.self) { role in
            Button(role == .plotter ? "Plotter" : "Portrait") {
              WorkbenchRequestTelemetry.nativeActionHandled("workbench.camera.\(role.rawValue)")
              submit(PlotterAppUIActionID.observationCameraRole(role))
            }
            .buttonStyle(.bordered)
            .tint(application.workbenchCameraRole == role ? .accentColor : .secondary)
            .accessibilityIdentifier("workbench.camera.\(role.rawValue)")
            .accessibilityValue(application.workbenchCameraRole == role
              ? application.cameraRoleIsTransitioning ? "Switching" : "Selected" : "Not selected")
          }
        }
        .accessibilityIdentifier("workbench.video.cameraRole")
        if application.cameraRoleIsTransitioning { ProgressView().controlSize(.small) }
        Spacer()
        Button { settingsArePresented.toggle() } label: { Image(systemName: "slider.horizontal.3") }
          .buttonStyle(.borderless)
          .accessibilityLabel("Video Settings")
          .accessibilityIdentifier("workbench.video.settings")
      }.padding(8)
      if let error = requestError ?? application.cameraRoleError ?? selectedSourceError {
        Text(error).font(.caption).foregroundStyle(.orange)
          .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 8)
          .textSelection(.enabled)
          .accessibilityIdentifier("workbench.video.error")
      }
      if settingsArePresented {
        settings.padding(10)
        Divider()
      }
      WorkbenchCameraCanvas(application: application, semantic: semantic, viewport: $viewport,
        pendingDrawingPlacement: $pendingDrawingPlacement, pendingPointSelection: $pendingPointSelection)
        .frame(minWidth: 280, maxWidth: .infinity, minHeight: 180, maxHeight: .infinity)
        .accessibilityIdentifier("workbench.video.canvas")
    }
  }

  private var selectedSourceError: String? {
    switch application.workbenchCameraRole {
    case .plotter: application.cameraError ?? application.visionError
    case .portrait: application.portraitStudio.cameraStatus
    }
  }

  private var settings: some View {
    VStack(alignment: .leading, spacing: 10) {
      if application.workbenchCameraRole == .plotter {
        HStack {
          Picker("Source", selection: Binding(
            get: { projection.frameMode == .simulated ? "simulated" : projection.selectedCameraID?.rawValue ?? "" },
            set: { id in submit(id == "simulated" ? PlotterAppUIActionID.observationSimulated
              : PlotterAppUIActionID.observationCamera(id)) })) {
            Text("Simulator").tag("simulated")
            ForEach(projection.cameraDevices) { Text($0.name).tag($0.id.rawValue) }
          }
          .disabled(projection.sourceChangeUnavailableReason != nil)
          Button { submit(PlotterAppUIActionID.observationRefresh) } label: { Image(systemName: "arrow.clockwise") }
            .accessibilityLabel("Refresh cameras")
        }
        HStack {
          ForEach(UserSceneOverlay.allCases, id: \.self) { overlay in
            Toggle(overlay.title, isOn: Binding(
              get: { projection.enabledOverlays.contains(overlay) },
              set: { submit(PlotterAppUIActionID.observationOverlay(overlay.rawValue, enabled: $0)) }))
          }
        }
        Picker("Analysis rate", selection: Binding(get: { projection.cadence }, set: {
          submit(PlotterAppUIActionID.observationCadence($0))
        })) {
          ForEach(VisionAnalysisCadence.allCases, id: \.self) { Text("\($0.displayValue) fps").tag($0) }
        }.disabled(projection.frameMode != .live)
        HStack {
          Text("Zoom")
          Slider(value: $viewport.zoom, in: 0...1).disabled(projection.regionLock != nil)
          Button(projection.regionLock == nil ? "Lock Region" : "Unlock Region", action: submitRegion)
            .disabled(!application.displayedFrameAvailable)
        }
      } else {
        Text("Choose the portrait camera and capture a face in Portrait Studio.")
          .font(.caption).foregroundStyle(.secondary)
      }
    }
  }

  private func submit(_ action: PlotterUIActionID) {
    requestError = nil
    Task {
      guard let request = semantic.request(for: action) else {
        requestError = semantic.action(id: action)?.unavailableReason ?? "This camera action is unavailable."
        return
      }
      if case .refused(let refusal) = await application.submitPlotterUIRequest(request) { requestError = refusal.remedy }
    }
  }

  private func submitRegion() {
    // Exact frame binding is sampled when the operator acts. Settings rendering
    // never observes, compares, or copies a changing frame value.
    let surface = application.actionSurfacePresentation
    let current = surface.usesAmbientPreviewFrame
      ? application.videoPreviewProjection(
        displayedFrame: application.actionSurfacePreview.displayedFrame, observationViewport: viewport)
      : semantic
    Task {
      guard let request = current.request(for: PlotterAppUIActionID.observationRegion) else {
        requestError = "A current plotter frame is required to change the analysis region."
        return
      }
      if case .refused(let refusal) = await application.submitPlotterUIRequest(request) { requestError = refusal.remedy }
    }
  }
}

/// This leaf alone observes camera pixels. Both sources occupy the same Video
/// panel and use the same native image layer; controls never receive frame bytes.
private struct WorkbenchCameraCanvas: View {
  let application: PlotterApplicationRuntime
  let semantic: PlotterUIProjection
  @Binding var viewport: ActionSurfaceViewportState
  @Binding var pendingDrawingPlacement: PlotterDrawingDraftCameraPlacement?
  @Binding var pendingPointSelection: PlotterPointSelectionSubmission?
  var body: some View {
    if application.workbenchCameraRole == .portrait {
      PortraitCameraPreview(model: application.portraitStudio.preview)
    } else {
      PreviewingActionSurface(application: application, preview: application.actionSurfacePreview,
        viewport: $viewport, plotterUIProjection: semantic, plotterUIIntentSink: application,
        pendingDrawingPlacement: $pendingDrawingPlacement, pendingPointSelection: $pendingPointSelection)
    }
  }
}
