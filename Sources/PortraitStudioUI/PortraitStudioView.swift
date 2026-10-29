import PortraitArtists
import PortraitLibrary
import PlotterModel
import PlotterRuntime
import SwiftUI
import UniformTypeIdentifiers

/// The embedded host enters the same portfolio dojo and retains its canonical drawing handoff.
package struct PortraitStudioView: View {
  @Environment(\.portraitActionTelemetry) private var recordAction
  @Bindable package var model: PortraitStudioModel
  package let strokeStyle: PlotterModel.StrokeStyle
  package var previewSource = PortraitPlanePreviewSource()
  package let showOnPlotter: (PortraitCandidate) async -> String?
  package var showEditedOnPlotter: ((SavedDrawing) async -> String?)? = nil
  package var selectCamera: () async -> String? = { nil }
  package var openReviewer: (UUID?) -> Void = { _ in }

  package let handoffTitle: String
  package let handoffErrorTitle: String
  package let handoffActionID: String
  package let handoffHelp: String

  @State package var showsAdjustments = false

  @State private var dojo: FlowDojoModel

  package var body: some View {
    FlowDojoView(model: dojo, camera: model, selectCamera: selectCamera,
      handoffTitle: handoffTitle, handoff: { bytes in
        guard let showEditedOnPlotter else { return "Drawing handoff is unavailable in this host." }
        do {
          let drawing = try await model.sketches.importDrawingPackage(bytes, restoreDeleted: false)
          return await showEditedOnPlotter(drawing)
        } catch { return error.localizedDescription }
      })
      .task(id: strokeStyle) { dojo.updateStrokeStyle(strokeStyle) }
      .onDisappear { dojo.cancel() }
  }

  package init(
    model: PortraitStudioModel,
    strokeStyle: PlotterModel.StrokeStyle,
    previewSource: PortraitPlanePreviewSource = PortraitPlanePreviewSource(),
    showOnPlotter: @escaping (PortraitCandidate) async -> String?,
    showEditedOnPlotter: ((SavedDrawing) async -> String?)? = nil,
    selectCamera: @escaping () async -> String? = { nil },
    openReviewer: @escaping (UUID?) -> Void = { _ in },
    showsAdjustments: Bool = false,
    handoffTitle: String = "Send to Drawing",
    handoffErrorTitle: String = "Drawing projection failed",
    handoffActionID: String = "portrait.showOnPlotter",
    handoffHelp: String = "Send to Drawing places it in Drawing; Draw there starts execution."
  ) {
    self.model = model
    _dojo = State(initialValue: model.portfolioDojo(strokeStyle: strokeStyle))
    self.strokeStyle = strokeStyle
    self.previewSource = previewSource
    self.showOnPlotter = showOnPlotter
    self.showEditedOnPlotter = showEditedOnPlotter
    self.selectCamera = selectCamera
    self.openReviewer = openReviewer
    self.showsAdjustments = showsAdjustments
    self.handoffTitle = handoffTitle
    self.handoffErrorTitle = handoffErrorTitle
    self.handoffActionID = handoffActionID
    self.handoffHelp = handoffHelp
  }
}

/// Preserve native controls and their shortcuts while moving whole actions onto
/// separate rows when their intrinsic widths exceed the available panel width.
package struct PortraitAdaptiveRow<Content: View>: View {
  private let content: Content
  package init(@ViewBuilder content: () -> Content) { self.content = content() }
  package var body: some View {
    ViewThatFits(in: .horizontal) {
      HStack(alignment: .center, spacing: 8) { content }.fixedSize(horizontal: true, vertical: false)
      VStack(alignment: .leading, spacing: 8) { content }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

/// Live frames are observed only by the preview leaf, never by editing controls.
package struct PortraitCameraPreview: View {
  package let model: PortraitCameraPreviewModel
  package var zoom: Double = 0
  @StateObject private var cache = FramePresentationImageCache()
  package var body: some View {
    GeometryReader { proxy in
      if let displayed = model.frame, let image = cache.image(from: displayed.frame),
        let transform = CameraPixelToViewTransform(frameWidth: displayed.frame.width,
          frameHeight: displayed.frame.height, viewWidth: proxy.size.width, viewHeight: proxy.size.height) {
        CameraFrameLayerView(image: image, imageRect: transform.imageRect).scaleEffect(1 + zoom * 3)
      } else {
        ContentUnavailableView("Portrait Camera", systemImage: "person.crop.rectangle")
      }
    }.clipped()
  }

  package init(model: PortraitCameraPreviewModel, zoom: Double = 0) {
    self.model = model
    self.zoom = zoom
  }
}
