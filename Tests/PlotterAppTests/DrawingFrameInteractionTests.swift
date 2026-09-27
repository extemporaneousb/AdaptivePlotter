import AppKit
import SwiftUI
import CoreGraphics
import Foundation
import PlotterEpisodeRuntime
import PlotterModel
import PlotterRuntime
import Testing
@testable import PlotterApp

@Suite("Video drawing frame interaction")
struct DrawingFrameInteractionTests {
  @Test("body dragging preserves grab offset through zoom and pan and stops at Boundary")
  func bodyDrag() throws {
    let frame = try fixture()
    let transform = try #require(CameraPixelToViewTransform(frameWidth: 800, frameHeight: 600,
      viewWidth: 1000, viewHeight: 700, focusRegion: PixelRect(x: 50, y: 30, width: 600, height: 420)))
    let center = try frame.cameraCenter
    let grab = try Point2<CameraPixelSpace>(x: center.x + 8, y: center.y + 6)
    let drag = try #require(DrawingFrameDrag(frame: frame, start: transform.point(grab), transform: transform))
    #expect(drag.corner == nil)
    let same = try drag.updated(at: grab, minimumScale: 0.02)
    #expect(try same.cameraCenter.distance(to: center) < 1e-9)
    let moved = try drag.updated(at: Point2(x: grab.x + 15, y: grab.y - 10), minimumScale: 0.02)
    #expect(try moved.cameraCenter.distance(to: Point2(x: center.x + 15, y: center.y - 10)) < 1e-9)
    #expect(moved.geometry.placement.uniformScale == frame.geometry.placement.uniformScale)
    let limited = try drag.updated(at: Point2(x: 5000, y: -5000), minimumScale: 0.02)
    #expect(limited.geometry.isContained(in: frame.boundary))
  }

  @Test("each corner uniformly resizes about center and stops before any corner leaves Boundary", arguments: 0..<4)
  func cornerResize(index: Int) throws {
    let frame = try fixture()
    let transform = try #require(CameraPixelToViewTransform(frameWidth: 800, frameHeight: 600,
      viewWidth: 800, viewHeight: 600))
    let corner = try frame.cameraCorners[index], center = try frame.cameraCenter
    let drag = try #require(DrawingFrameDrag(frame: frame, start: transform.point(corner), transform: transform))
    #expect(drag.corner == index)
    let expanded = try drag.updated(at: Point2(x: center.x + 10 * (corner.x - center.x),
      y: center.y + 10 * (corner.y - center.y)), minimumScale: 0.02)
    #expect(expanded.geometry.isContained(in: frame.boundary))
    #expect(expanded.geometry.placement.machineAnchor == frame.geometry.placement.machineAnchor)
    #expect(expanded.geometry.placement.rotationRadians == frame.geometry.placement.rotationRadians)
    #expect(expanded.geometry.extent == frame.geometry.extent)
    let maximum = try frame.geometry.maximumScaleKeepingCenter(in: frame.boundary)
    #expect(abs(expanded.geometry.placement.uniformScale - maximum) < 1e-10)
    #expect(try !expanded.geometry.replacing(scale: maximum * 1.01).isContained(in: frame.boundary))
  }

  func fixture() throws -> PlotterDrawingDraftFrame {
    let response = try AffineTransform2<MachineSpace, CameraPixelSpace>(m11: 2, m12: 0.5,
      m21: 0.3, m22: -2, tx: 130, ty: 450)
    let placement = try DrawingPlacement(fieldAnchor: .init(x: 50, y: 30),
      machineAnchor: .init(x: 100, y: 80), uniformScale: 0.8, rotationRadians: .pi / 6,
      cameraGeometry: .init(cameraFromMachine: response))
    return PlotterDrawingDraftFrame(geometry: .init(extent: try .init(width: 100, height: 60), placement: placement),
      boundary: try .init(bounds: .init(minX: 0, minY: 0, maxX: 200, maxY: 160)), cameraFromMachine: response)
  }
}


@Suite("Drawing frame native overlay", .serialized)
@MainActor
struct DrawingFrameOverlayRenderingTests {
  @Test("production overlay renders projected frame and four resize handles offscreen",
    .enabled(if: ProcessInfo.processInfo.environment["ACTION_SURFACE_RENDER_TEST"] == "1"))
  func nativeFrameOverlay() async throws {
    _ = NSApplication.shared
    let frame = try DrawingFrameInteractionTests().fixture()
    let transform = try #require(CameraPixelToViewTransform(frameWidth: 800, frameHeight: 600,
      viewWidth: 800, viewHeight: 600))
    let view = DrawingFrameOverlay(frame: frame, transform: transform, editing: true, staged: true)
      .frame(width: 800, height: 600).background(.black)
    let host = NSHostingView(rootView: view)
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
      styleMask: [.borderless], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = host
    defer { window.close() }
    host.layoutSubtreeIfNeeded()
    window.display()
    try await Task.sleep(for: .milliseconds(100))
    host.display()
    let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
    host.cacheDisplay(in: host.bounds, to: bitmap)
    let png = try #require(bitmap.representation(using: .png, properties: [:]))
    try png.write(to: URL(fileURLWithPath: "/tmp/adaptiveplotter-frame-overlay.png"))
    let scale = Double(bitmap.pixelsWide) / 800
    for corner in try frame.cameraCorners {
      let point = transform.point(corner)
      let x = Int(point.x * scale), y = Int(point.y * scale)
      var colored = 0
      for row in (y - Int(7 * scale))...(y + Int(7 * scale)) {
        for column in (x - Int(7 * scale))...(x + Int(7 * scale)) {
          guard row >= 0, row < bitmap.pixelsHigh, column >= 0, column < bitmap.pixelsWide,
            let color = bitmap.colorAt(x: column, y: row)?.usingColorSpace(.deviceRGB) else { continue }
          if color.redComponent > 0.6 && color.greenComponent > 0.5 && color.blueComponent < 0.4 { colored += 1 }
        }
      }
      #expect(colored > 10, "Missing resize handle at projected corner \(point)")
    }
  }
}
