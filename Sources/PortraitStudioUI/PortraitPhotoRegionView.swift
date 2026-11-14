import AppKit
import SwiftUI
import PortraitArtists

/// Oriented original coordinates, top-left origin. Letterboxing never enters the region.
package enum PortraitPhotoRegionGeometry {
  package static func imageRect(image: CGSize, viewport: CGSize) -> CGRect {
    guard image.width > 0, image.height > 0 else { return .zero }
    let scale = min(viewport.width / image.width, viewport.height / image.height)
    let size = CGSize(width: image.width * scale, height: image.height * scale)
    return CGRect(x: (viewport.width - size.width) / 2, y: (viewport.height - size.height) / 2, width: size.width, height: size.height)
  }
  package static func display(_ region: PortraitNormalizedRegion, in rect: CGRect) -> CGRect {
    CGRect(x: rect.minX + region.x * rect.width, y: rect.minY + region.y * rect.height, width: region.width * rect.width, height: region.height * rect.height)
  }
}

package struct PortraitPhotoRegionView: NSViewRepresentable {
  let image: NSImage
  @Binding var region: PortraitNormalizedRegion?
  var selectionOnly: Bool
  var changed: () -> Void
  package func makeNSView(context: Context) -> PortraitPhotoRegionNSView { PortraitPhotoRegionNSView() }
  package func updateNSView(_ view: PortraitPhotoRegionNSView, context: Context) {
    view.image = image; view.region = region; view.selectionOnly = selectionOnly
    view.changed = { region = $0; changed() }; view.needsDisplay = true
  }
}

package final class PortraitPhotoRegionNSView: NSView {
  package var image: NSImage?
  package var region: PortraitNormalizedRegion?
  package var selectionOnly = false
  package var changed: ((PortraitNormalizedRegion) -> Void)?
  private var origin: CGPoint?
  private var original: PortraitNormalizedRegion?
  private var handle = 0
  override package var isFlipped: Bool { true }
  override package var acceptsFirstResponder: Bool { true }
  override package init(frame: NSRect) {
    super.init(frame: frame)
    setAccessibilityElement(true); setAccessibilityRole(.image)
    setAccessibilityIdentifier("portraitStudio.regionCanvas")
    setAccessibilityLabel("Photo region. Drag inside to move, drag corners to resize, or drag outside to select a new region. Apply region commits the change.")
  }
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
  override package func draw(_ dirtyRect: NSRect) {
    NSColor.controlBackgroundColor.setFill(); bounds.fill()
    guard let image else { return }
    let fit = PortraitPhotoRegionGeometry.imageRect(image: image.size, viewport: bounds.size)
    if selectionOnly, let r = region {
      let source = NSRect(x: r.x * image.size.width, y: (1-r.y-r.height) * image.size.height, width: r.width * image.size.width, height: r.height * image.size.height)
      let target = PortraitPhotoRegionGeometry.imageRect(image: source.size, viewport: bounds.size)
      image.draw(in: target, from: source, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
    } else {
      image.draw(in: fit, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
      if let region {
        let selection = PortraitPhotoRegionGeometry.display(region, in: fit)
        let shade = NSBezierPath(rect: fit); shade.append(NSBezierPath(rect: selection)); shade.windingRule = .evenOdd
        NSColor.black.withAlphaComponent(0.35).setFill(); shade.fill()
        NSColor.controlAccentColor.setStroke(); let path = NSBezierPath(rect: selection); path.lineWidth = 2; path.stroke()
        NSColor.controlAccentColor.setFill()
        for point in corners(selection) { NSBezierPath(ovalIn: CGRect(x: point.x-5, y: point.y-5, width: 10, height: 10)).fill() }
      }
    }
  }
  private func corners(_ rect: CGRect) -> [CGPoint] {
    [.init(x: rect.minX, y: rect.minY), .init(x: rect.maxX, y: rect.minY), .init(x: rect.minX, y: rect.maxY), .init(x: rect.maxX, y: rect.maxY)]
  }
  override package func mouseDown(with event: NSEvent) {
    guard !selectionOnly, let image else { return }
    let point = convert(event.locationInWindow, from: nil)
    let fit = PortraitPhotoRegionGeometry.imageRect(image: image.size, viewport: bounds.size)
    let selection = region.map { PortraitPhotoRegionGeometry.display($0, in: fit) }
    let corner = selection.flatMap { rect in corners(rect).firstIndex(where: { hypot($0.x-point.x, $0.y-point.y) < 14 }) }
    guard fit.contains(point) || corner != nil else { return }
    origin = point; original = region; handle = 0
    if let corner { handle = corner + 2 }
    else if let selection, selection.contains(point) { handle = 1 }
  }
  override package func mouseDragged(with event: NSEvent) {
    guard let origin, let image else { return }
    let fit = PortraitPhotoRegionGeometry.imageRect(image: image.size, viewport: bounds.size)
    guard fit.width > 0, fit.height > 0 else { return }
    let point = convert(event.locationInWindow, from: nil)
    let px = max(0, min(1, (point.x-fit.minX)/fit.width)), py = max(0, min(1, (point.y-fit.minY)/fit.height))
    let ox = (origin.x-fit.minX)/fit.width, oy = (origin.y-fit.minY)/fit.height
    let next: PortraitNormalizedRegion
    if handle == 1, let r = original {
      next = .init(x: max(0,min(1-r.width,r.x+px-ox)), y: max(0,min(1-r.height,r.y+py-oy)), width: r.width, height: r.height)
    } else {
      var ax = ox, ay = oy
      if handle >= 2, let r = original {
        ax = (handle == 2 || handle == 4) ? r.x+r.width : r.x
        ay = (handle == 2 || handle == 3) ? r.y+r.height : r.y
      }
      let x = min(0.98, min(ax,px)), y = min(0.98, min(ay,py))
      next = .init(x: x, y: y, width: min(1-x,max(0.02,abs(px-ax))), height: min(1-y,max(0.02,abs(py-ay))))
    }
    region = next; changed?(next); needsDisplay = true
  }
  override package func mouseUp(with event: NSEvent) { origin = nil; original = nil }
}
