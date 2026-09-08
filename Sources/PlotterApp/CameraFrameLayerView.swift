import AppKit
import SwiftUI

/// Upload the immutable frame once through Core Animation. Drawing it inside
/// Canvas caused RenderBox to rewrite every pixel's alpha on each preview.
/// The image and SwiftUI overlays share the exact same camera-to-view rect.
struct CameraFrameLayerView: NSViewRepresentable {
  let image: CGImage?
  let imageRect: CGRect

  func makeNSView(context: Context) -> CameraFrameLayerHost { CameraFrameLayerHost() }

  func updateNSView(_ view: CameraFrameLayerHost, context: Context) {
    view.display(image, in: imageRect)
  }
}

final class CameraFrameLayerHost: NSView {
  private let imageLayer = CALayer()
  private var displayedImage: CGImage?
  private var displayedRect: CGRect = .zero
  override var isFlipped: Bool { true }

  init() {
    super.init(frame: .zero)
    wantsLayer = true
    layer?.backgroundColor = NSColor.black.cgColor
    layer?.masksToBounds = true
    imageLayer.contentsGravity = .resize
    imageLayer.minificationFilter = .linear
    imageLayer.magnificationFilter = .linear
    layer?.addSublayer(imageLayer)
  }

  required init?(coder: NSCoder) { nil }
  override func hitTest(_ point: NSPoint) -> NSView? { nil }

  func display(_ image: CGImage?, in rect: CGRect) {
    // Overlay and control updates can revisit the representable with the same
    // pixels and viewport. They require no Core Animation transaction.
    guard displayedImage !== image || displayedRect != rect else { return }
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    if displayedImage !== image {
      displayedImage = image
      imageLayer.contents = image
    }
    if displayedRect != rect {
      displayedRect = rect
      imageLayer.frame = rect
    }
    CATransaction.commit()
  }
}
