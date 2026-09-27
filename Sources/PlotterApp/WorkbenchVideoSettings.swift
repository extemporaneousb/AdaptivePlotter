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
        .disabled(application.workbenchCameraRole == .plotter && application.videoViewportAdjustmentUnavailableReason != nil)
        .accessibilityIdentifier("workbench.video.zoom")
      if application.workbenchCameraRole == .plotter {
        HStack {
          Button("Fit Machine Boundary") {
            guard application.videoViewportAdjustmentUnavailableReason == nil,
              let context = application.actionSurfacePresentation.viewportContext,
              context.fittedRegion != nil else { return }
            viewport.synchronize(with: context)
            viewport.showFittedBounds()
          }
          .disabled(application.videoViewportAdjustmentUnavailableReason != nil
            || application.actionSurfacePresentation.viewportContext?.fittedRegion == nil)
          .accessibilityIdentifier("workbench.video.fitMachineBoundary")
          Button("Show Full Video") {
            guard application.videoViewportAdjustmentUnavailableReason == nil else { return }
            viewport.showFullFrame()
          }
          .disabled(application.videoViewportAdjustmentUnavailableReason != nil)
          .accessibilityIdentifier("workbench.video.showFullVideo")
        }.controlSize(.small)
        Text("Reference frames").font(.subheadline.bold())
        ForEach([UserSceneOverlay.machineBoundary, .drawingRegion], id: \.self) { overlay in
          overlayToggle(overlay)
        }
        OperatorRequestButton(
          title: application.drawingTargetIsVisible ? "Hide Drawing" : "Show Drawing",
          request: semantic.request(matching: .drawingDraft(
            application.drawingTargetIsVisible ? .hideTarget : .showTarget)),
          unavailableReason: nil,
          sink: application,
          nativeActionIdentifier: "workbench.video.drawingVisibility"
        )
        .help("Show or hide the current drawing preview on the video. Its placement is retained.")
        .accessibilityIdentifier("workbench.video.drawingVisibility")
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
          Text("Vision diagnostics").font(.subheadline.bold())
          ForEach(UserSceneOverlay.allCases.filter(\.usesSceneAnalysis), id: \.self) { overlay in
            overlayToggle(overlay)
            if projection.enabledOverlays.contains(overlay) {
              VideoOverlayStatus(application: application, overlay: overlay)
            }
          }
          if projection.frameMode == .simulated { overlayToggle(.simulatorDiagnostics) }
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

  private func overlayToggle(_ overlay: UserSceneOverlay) -> some View {
    Toggle(overlay.title, isOn: Binding(
      get: { projection.enabledOverlays.contains(overlay) },
      set: { submit(PlotterAppUIActionID.observationOverlay(overlay.rawValue, enabled: $0)) }))
      .accessibilityIdentifier("workbench.video.\(overlay.rawValue)")
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

/// Observe analysis updates only inside the video diagnostics leaf.
private struct VideoOverlayStatus: View {
  let application: PlotterApplicationRuntime
  let overlay: UserSceneOverlay

  var body: some View {
    let _ = application.actionSurfacePreview.presentationRevision
    let status = application.overlayDiagnosticStatus(for: overlay)
    Text(status.message)
      .font(.caption)
      .foregroundStyle(status.state == .unavailable || status.state == .failed ? .orange : .secondary)
      .textSelection(.enabled)
      .accessibilityIdentifier("workbench.video.\(overlay.rawValue).status")
  }
}
