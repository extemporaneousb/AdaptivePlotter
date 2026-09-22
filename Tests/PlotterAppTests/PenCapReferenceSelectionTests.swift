import CoreGraphics
import PlotterEpisodeModel
import PlotterModel
import PlotterRuntime
import Testing
@testable import PlotterApp

@Suite("Cap reference selection geometry")
struct PenCapReferenceSelectionTests {
  @Test("reverse drag maps the rectangle through zoom without recentering the anchor")
  func rectangleGeometry() throws {
    let transform = try #require(CameraPixelToViewTransform(
      frameWidth: 1920, frameHeight: 1080, viewWidth: 800, viewHeight: 600,
      focusRegion: PixelRect(x: 600, y: 100, width: 600, height: 450)))
    let a = try Point2<CameraPixelSpace>(x: 730, y: 200)
    let b = try Point2<CameraPixelSpace>(x: 850, y: 330)
    let region = try #require(PenCapReferenceSelectionGeometry.region(
      from: transform.point(b), to: transform.point(a), transform: transform))
    #expect(abs(region.minX - 730) < 0.001)
    #expect(abs(region.minY - 200) < 0.001)
    #expect(abs(region.maxX - 850) < 0.001)
    #expect(abs(region.maxY - 330) < 0.001)
    #expect(PenCapReferenceSelectionGeometry.region(
      from: CGPoint(x: -10, y: 0), to: transform.point(a), transform: transform) == nil)
  }

  @Test("explicit cap anchor reaches calibration instead of the reference bottom center")
  func calibrationAnchor() throws {
    let anchor = try Point2<CameraPixelSpace>(x: 112, y: 86)
    let result = try ToolCapAnchorEstimate(componentCentroid: Point2(x: 150, y: 75),
      componentBounds: AxisAlignedBounds(minX: 100, minY: 50, maxX: 200, maxY: 100),
      selectedAnchor: anchor, confidence: 0.95, estimatorRevision: "reference-fixture",
      source: .simulated, frameID: FrameID(rawValue: "anchor"), cameraConfigurationID: CameraConfigurationID())
    #expect(result.point == anchor)
    #expect(result.componentCentroid != anchor)
  }
}
