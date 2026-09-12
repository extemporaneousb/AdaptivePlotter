import PlotterEpisodeModel
import PlotterEpisodeRuntime
import PlotterRuntime
import PlotterUI
import SwiftUI

struct WorkbenchVideoSettings: View {
  let application: PlotterApplicationRuntime
  let projection: PlotterObservationConfigurationProjection
  let semantic: PlotterUIProjection
  @Binding var viewport: ActionSurfaceViewportState
  var cameraSelected: () -> Void = {}
  @State private var requestError: String?

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 12) {
        Picker("Camera", selection: Binding(get: { application.workbenchCameraRole }, set: { role in
          cameraSelected()
          WorkbenchRequestTelemetry.nativeActionHandled("workbench.camera.\(role.rawValue)")
          submit(PlotterAppUIActionID.observationCameraRole(role))
        })) {
          Text("Plotter").tag(WorkbenchCameraRole.plotter)
          Text("Portrait").tag(WorkbenchCameraRole.portrait)
        }
        .accessibilityIdentifier("workbench.video.cameraRole")
        if application.cameraRoleIsTransitioning { ProgressView().controlSize(.small) }
        if let error = requestError ?? application.cameraRoleError ?? selectedSourceError {
          Text(error).font(.caption).foregroundStyle(.orange).textSelection(.enabled)
            .accessibilityIdentifier("workbench.video.error")
        }
        settings
      }.padding(10)
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
      Text("Zoom")
      Slider(value: $viewport.zoom, in: 0...1)
        .disabled(application.workbenchCameraRole == .plotter && projection.regionLock != nil)
        .accessibilityIdentifier("workbench.video.zoom")
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
        VStack(alignment: .leading, spacing: 8) {
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
        VStack(alignment: .leading, spacing: 8) {
          Button(projection.regionLock == nil ? "Lock Region" : "Unlock Region", action: submitRegion)
            .disabled(!application.displayedFrameAvailable)
        }
        ForEach(application.completedComparisonReviewPresentation.controls) { control in
          let intent: PlotterUIRetainedComparisonIntent = control.intent == .reviewComparison
            ? .reviewExactFrame : .resumeLivePreview
          OperatorRequestButton(
            title: control.title, role: control.role,
            request: semantic.request(matching: .retainedComparisonReview(intent)),
            unavailableReason: nil, sink: application
          )
          .accessibilityIdentifier("workbench.video.comparison")
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
