import AppKit
import ImageIO
import PlotterEpisodeModel
import PlotterModel
import PlotterRuntime
import PlotterUI
import SwiftUI

enum WorkbenchCanvasContent: Equatable {
  case plotter, portraitVideo, portraitPhoto, simulationPreview

  static func select(portrait: Bool, portraitVideoAvailable: Bool, portraitPhotoAvailable: Bool,
    plotterFrameAvailable: Bool, retainedPlotterFrame: Bool, plotterLive: Bool, simulated: Bool) -> Self {
    if portrait {
      if portraitVideoAvailable { return .portraitVideo }
      return portraitPhotoAvailable ? .portraitPhoto : .simulationPreview
    }
    return plotterFrameAvailable && (retainedPlotterFrame || plotterLive || simulated)
      ? .plotter : .simulationPreview
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
      let surface = application.actionSurfacePresentation
      let displayed = surface.usesAmbientPreviewFrame
        ? application.actionSurfacePreview.displayedFrame : surface.displayedFrame
      let portrait = application.portraitStudio
      let content = WorkbenchCanvasContent.select(
        portrait: application.workbenchCameraRole == .portrait,
        portraitVideoAvailable: portrait.cameraIsRunning && portrait.preview.frame != nil,
        portraitPhotoAvailable: portrait.selectedPhoto != nil,
        plotterFrameAvailable: displayed != nil, retainedPlotterFrame: !surface.usesAmbientPreviewFrame,
        plotterLive: application.cameraIsLive, simulated: application.frameMode == .simulated)
      Group {
        switch content {
        case .plotter:
          PreviewingActionSurface(application: application, preview: application.actionSurfacePreview,
            viewport: $viewport, plotterUIProjection: semantic, plotterUIIntentSink: application,
            pendingDrawingPlacement: $pendingDrawingPlacement, pendingPointSelection: $pendingPointSelection)
            .overlay(alignment: .topLeading) {
              if let displayed, let detail = application.sparseTipGuideDetail(on: displayed) {
                Text(detail).font(.caption).foregroundStyle(.white)
                  .padding(6).background(.black.opacity(0.75)).padding(8)
                  .accessibilityIdentifier("workbench.calibrationGuideQualification")
              }
            }
        case .portraitVideo:
          PortraitCameraPreview(model: portrait.preview, zoom: viewport.zoom)
        case .portraitPhoto:
          WorkbenchPhotoCanvas(data: portrait.selectedPhoto, zoom: viewport.zoom)
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
