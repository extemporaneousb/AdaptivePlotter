import CoreGraphics
import PlotterModel
import PlotterRuntime
import Testing

@testable import PlotterApp

@Suite("Action Surface fractional panning")
struct ActionSurfaceFractionalPanTests {
  @Test("Small magnified drag increments produce the same viewport as their total")
  func incrementalMotion() {
    var incremental = viewport()
    var aggregate = incremental
    let initialRevision = incremental.presentationTransformRevision
    pan(&incremental, x: 0.4, y: 0.8)
    #expect(incremental.presentationTransformRevision == initialRevision)
    for _ in 1..<100 { pan(&incremental, x: 0.4, y: 0.8) }
    pan(&aggregate, x: 40, y: 80)

    #expect(region(incremental) == PixelRect(x: 395, y: 290, width: 100, height: 100))
    #expect(region(incremental) == region(aggregate))
    #expect(incremental.presentationTransformRevision != initialRevision)
  }

  @Test("Outward motion cannot accumulate at either frame edge")
  func edgeReversal() {
    var value = viewport()
    pan(&value, x: 100_000, y: 100_000)
    for _ in 0..<100 { pan(&value, x: 3, y: 3) }
    #expect(region(value) == PixelRect(x: 0, y: 0, width: 100, height: 100))
    pan(&value, x: -8, y: -8)
    #expect(region(value) == PixelRect(x: 1, y: 1, width: 100, height: 100))

    pan(&value, x: -100_000, y: -100_000)
    for _ in 0..<100 { pan(&value, x: -3, y: -3) }
    #expect(region(value) == PixelRect(x: 900, y: 900, width: 100, height: 100))
    pan(&value, x: 8, y: 8)
    #expect(region(value) == PixelRect(x: 899, y: 899, width: 100, height: 100))
  }

  @Test("Clipping one axis preserves small movement on the other")
  func independentAxisCarry() {
    var value = viewport()
    pan(&value, x: 100_000, y: 0)
    for _ in 0..<16 { pan(&value, x: 0.5, y: -0.5) }
    #expect(region(value) == PixelRect(x: 0, y: 301, width: 100, height: 100))
  }

  @Test("Presentation changes discard movement from the prior transform",
    arguments: ["zoom", "fit", "full", "context"])
  func resetCarry(change: String) {
    var value = viewport()
    pan(&value, x: 3, y: 3)
    switch change {
    case "zoom":
      value.zoom = 0.5
      value.zoom = 1
    case "fit":
      value.showFittedBounds()
    case "full":
      value.showFullFrame()
      value.showFittedBounds()
    default:
      value.synchronize(with: context(configuration: value.context!.cameraConfigurationID,
        revision: "changed"))
    }
    pan(&value, x: 3, y: 3)
    #expect(region(value) == PixelRect(x: 400, y: 300, width: 100, height: 100))
  }

  @Test("Compatible fitted-bound replacement retains focus and starts fresh fractional motion")
  func retainedRegion() {
    var value = viewport()
    pan(&value, x: 3, y: 3)
    value.synchronize(with: context(configuration: value.context!.cameraConfigurationID,
      fitted: PixelRect(x: 200, y: 200, width: 200, height: 200), revision: "new bounds"))
    pan(&value, x: 3, y: 3)
    #expect(region(value) == PixelRect(x: 400, y: 300, width: 100, height: 100))
    for _ in 0..<16 { pan(&value, x: 0.5, y: -0.5) }
    #expect(region(value) == PixelRect(x: 399, y: 301, width: 100, height: 100))
  }

  private func viewport() -> ActionSurfaceViewportState {
    var value = ActionSurfaceViewportState()
    value.synchronize(with: context())
    value.zoom = 1
    return value
  }

  private func context(configuration: CameraConfigurationID = CameraConfigurationID(),
    fitted: PixelRect = PixelRect(x: 400, y: 300, width: 100, height: 100),
    revision: String = "fractional pan") -> ActionSurfaceViewportContext {
    ActionSurfaceViewportContext(source: .simulated, cameraConfigurationID: configuration,
      frameWidth: 1_000, frameHeight: 1_000, fittedRegion: fitted,
      preferredInitialZoom: 0, presentationRevisionToken: revision)
  }

  private func pan(_ viewport: inout ActionSurfaceViewportState, x: Double, y: Double) {
    viewport.pan(by: CGSize(width: x, height: y), viewSize: CGSize(width: 800, height: 800),
      frameWidth: 1_000, frameHeight: 1_000)
  }

  private func region(_ viewport: ActionSurfaceViewportState) -> PixelRect? {
    viewport.visibleRegion(frameWidth: 1_000, frameHeight: 1_000)
  }
}
