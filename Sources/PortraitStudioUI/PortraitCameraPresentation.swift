import SwiftUI
import PortraitCore
import PlotterModel
import PlotterRuntime

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
