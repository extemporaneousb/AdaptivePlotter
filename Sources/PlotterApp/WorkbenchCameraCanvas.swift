import PortraitStudioUI
import AppKit
import ImageIO
import PlotterEpisodeModel
import PlotterModel
import PlotterRuntime
import PlotterUI
import SwiftUI

enum WorkbenchCanvasContent: Equatable {
  case plotter, simulationPreview
  static func select(plotterFrameAvailable: Bool) -> Self { plotterFrameAvailable ? .plotter : .simulationPreview }
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
    let content = WorkbenchCanvasContent.select(plotterFrameAvailable: displayed != nil)
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

private struct WorkbenchPhotoCanvas: View {
  let data: Data?
  let zoom: Double
  @State private var image: CGImage?
  var body: some View {
    GeometryReader { proxy in
      if let image, let transform = CameraPixelToViewTransform(frameWidth: image.width,
        frameHeight: image.height, viewWidth: proxy.size.width, viewHeight: proxy.size.height) {
        CameraFrameLayerView(image: image, imageRect: transform.imageRect).scaleEffect(1 + zoom * 3)
      }
    }.clipped()
      .task(id: data) {
        let decoded = await Task.detached(priority: .userInitiated) {
          guard let data, let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil as CGImage? }
          return CGImageSourceCreateImageAtIndex(source, 0, nil)
        }.value
        if !Task.isCancelled { image = decoded }
      }
  }
}
