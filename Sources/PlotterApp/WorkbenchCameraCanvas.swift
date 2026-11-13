import PortraitStudioUI
import AppKit
import PlotterEpisodeModel
import PlotterModel
import PlotterRuntime
import PlotterUI
import SwiftUI

enum WorkbenchCanvasContent: Equatable {
  case plotter, simulationPreview, waitingForCamera
  static func select(plotterFrameAvailable: Bool, isSimulated: Bool) -> Self {
    if plotterFrameAvailable { return .plotter }
    return isSimulated ? .simulationPreview : .waitingForCamera
  }
}

struct WorkbenchCanvasPresentation {
  let content: WorkbenchCanvasContent
  let displayedFrame: DisplayedFrame?
  let plotterFrameStatus: String?
  let showsSparseTipGuide: Bool
}

@MainActor
extension PlotterApplicationRuntime {
  var workbenchCanvasPresentation: WorkbenchCanvasPresentation {
    let surface = actionSurfacePresentation
    let displayed = surface.usesAmbientPreviewFrame
      ? actionSurfacePreview.displayedFrame : surface.displayedFrame
    let content = WorkbenchCanvasContent.select(plotterFrameAvailable: displayed != nil, isSimulated: frameMode == .simulated)
    // A held image remains camera-sourced; only its temporal qualification changes.
    // This presentation does not make that image fresh enough for an observation.
    let status: String?
    if workbenchCameraRole == .plotter, surface.usesAmbientPreviewFrame,
      case .live = displayed?.source {
      if let owner = exactWorkflowVisionOwner {
        status = owner.capAcquisitionStatus.map { "Camera frame held · \($0)" }
          ?? "Camera frame held · \(owner.operatorLabel)"
      } else {
        status = cameraIsLive ? nil : "Last camera frame · waiting for video"
      }
    } else {
      status = nil
    }
    return WorkbenchCanvasPresentation(content: content, displayedFrame: displayed,
      plotterFrameStatus: status, showsSparseTipGuide: surface.pointSelectionRequest == nil)
  }
}

/// Permanently mounted by the window. Only this leaf observes preview frames
/// and its freshness clock; neither is an input to the control-pane layout.
struct WorkbenchCameraCanvas: View {
  let application: PlotterApplicationRuntime
  let semantic: PlotterUIProjection
  var showVideoSettings: () -> Void = {}
  @Binding var viewport: ActionSurfaceViewportState
  @Binding var pendingDrawingPlacement: PlotterDrawingDraftCameraPlacement?
  @Binding var pendingPointSelection: PlotterPointSelectionSubmission?

  var body: some View {
    TimelineView(.periodic(from: .now, by: 0.5)) { _ in
      let canvas = application.workbenchCanvasPresentation
      let displayed = canvas.displayedFrame
      Group {
        switch canvas.content {
        case .plotter:
          PreviewingActionSurface(application: application, preview: application.actionSurfacePreview,
            viewport: $viewport, plotterUIProjection: semantic, plotterUIIntentSink: application,
            pendingDrawingPlacement: $pendingDrawingPlacement, pendingPointSelection: $pendingPointSelection,
            frameStatus: canvas.plotterFrameStatus,
            calibrationGuideQualification: canvas.showsSparseTipGuide
              ? displayed.flatMap { application.sparseTipGuideDetail(on: $0) } : nil)
            .accessibilityIdentifier("workbench.canvas.plotter")
        case .simulationPreview:
          WorkbenchSimulationCanvas(application: application, zoom: viewport.zoom)
        case .waitingForCamera:
          ContentUnavailableView {
            Label("No live camera image", systemImage: "video.slash")
          } description: {
            Text(application.cameraError ?? application.cameraRoleError
              ?? (application.selectedCameraID == nil
                ? "Choose a camera in Video Settings. Refresh sources if your camera is missing."
                : "Waiting for camera video · \(application.cameraStateText)"))
          } actions: {
            Button("Video Settings", action: showVideoSettings)
              .accessibilityIdentifier("workbench.canvas.videoSettings")
          }
          .environment(\.colorScheme, .dark)
          .accessibilityIdentifier("workbench.canvas.waitingForCamera")
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)

    }
    .frame(minWidth: 320, maxWidth: .infinity, minHeight: 180, maxHeight: .infinity)
    .background(.black)
    .clipped()
  }
}

private struct WorkbenchSimulationCanvas: View {
  let application: PlotterApplicationRuntime
  let zoom: Double
  @State private var frame: DisplayedFrame?
  @State private var failed = false
  @StateObject private var cache = FramePresentationImageCache()

  var body: some View {
    GeometryReader { proxy in
      if let frame, let image = cache.image(from: frame.frame),
        let transform = CameraPixelToViewTransform(frameWidth: frame.frame.width,
          frameHeight: frame.frame.height, viewWidth: proxy.size.width, viewHeight: proxy.size.height) {
        CameraFrameLayerView(image: image, imageRect: transform.imageRect)
          .scaleEffect(1 + zoom * 3)
      } else if failed {
        ContentUnavailableView("Simulation image unavailable", systemImage: "video.slash")
      } else {
        ProgressView("Preparing simulation…").frame(maxWidth: .infinity, maxHeight: .infinity)
      }
    }
    .clipped()
    .overlay(alignment: .topLeading) {
      Text("Simulation · no camera image").font(.caption.weight(.medium))
        .padding(8).foregroundStyle(.white).background(.black.opacity(0.7)).padding(8)
    }
    .accessibilityIdentifier("workbench.canvas.simulationPreview")
    .task {
      frame = await application.canvasSimulationPreview()
      failed = frame == nil
    }
  }
}
