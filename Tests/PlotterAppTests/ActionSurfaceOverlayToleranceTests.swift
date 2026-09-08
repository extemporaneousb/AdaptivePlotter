import PlotterModel
import PlotterRuntime
import Testing
@testable import PlotterApp

@Suite("Action Surface overlay tolerance")
@MainActor
struct ActionSurfaceOverlayToleranceTests {
  private let configuration = CameraConfigurationID()
  private var transform: CameraPixelToViewTransform {
    CameraPixelToViewTransform(frameWidth: 100, frameHeight: 100, viewWidth: 100, viewHeight: 100)!
  }

  @Test("eight-point deadband retains original geometry and provenance through new measurements")
  func jitterAndProvenance() throws {
    let cache = ActionSurfaceOverlayContentCache()
    let initial = try content(0)
    let displayed = cache.resolve(initial, transform: transform)
    for offset in [1.0, -1, 4, -4, 6, -6, 8, -8] {
      let incoming = try content(offset)
      let resolved = cache.resolve(incoming, transform: transform)
      #expect(resolved == displayed)
      #expect(resolved.overlays.first?.frameID == initial.overlays.first?.frameID)
      #expect(resolved.analyzedOverlayFrame == initial.analyzedOverlayFrame)
      #expect(incoming.overlays.first?.geometry != initial.overlays.first?.geometry)
    }
    let moved = try content(8.01)
    #expect(cache.resolve(moved, transform: transform).overlays == moved.overlays)
  }

  @Test("gradual movement accumulates against displayed geometry, not the preceding sample")
  func cumulativeDrift() throws {
    let cache = ActionSurfaceOverlayContentCache()
    var displayed = cache.resolve(try content(0), transform: transform)
    for offset in 1...8 {
      #expect(cache.resolve(try content(Double(offset)), transform: transform) == displayed)
    }
    let moved = try content(9)
    displayed = cache.resolve(moved, transform: transform)
    #expect(displayed.overlays == moved.overlays)
    for offset in 10...17 {
      #expect(cache.resolve(try content(Double(offset)), transform: transform) == displayed)
    }
    #expect(cache.resolve(try content(18), transform: transform) != displayed)
  }

  @Test("tolerance uses displayed points and viewport changes are immediate")
  func displayScaleAndViewport() throws {
    let cache = ActionSurfaceOverlayContentCache()
    let initial = cache.resolve(try content(0), transform: transform)
    let zoomed = CameraPixelToViewTransform(frameWidth: 100, frameHeight: 100,
      viewWidth: 200, viewHeight: 200)!
    let shifted = try content(1)
    #expect(cache.resolve(shifted, transform: zoomed).overlays == shifted.overlays)
    #expect(cache.resolve(try content(5), transform: zoomed).overlays == shifted.overlays)
    #expect(cache.resolve(try content(5.01), transform: zoomed) != shifted)
    #expect(initial.overlays != shifted.overlays)
  }

  @Test("metadata alone does not change drawing equality, but style and camera configuration do")
  func visualEquality() throws {
    let first = try content(0)
    let nextFrame = try content(0, revision: "different-detector-revision")
    #expect(first.overlays.first?.frameID != nextFrame.overlays.first?.frameID)
    #expect(first == nextFrame)
    #expect(first != (try content(0, kind: .armatureEstimate)))
    #expect(first != (try content(0, configuration: CameraConfigurationID())))
  }

  @Test("exact reviews, operator geometry, camera changes and removal bypass the deadband")
  func immediateTriggers() throws {
    let cache = ActionSurfaceOverlayContentCache()
    _ = cache.resolve(try content(0), transform: transform)
    let pinned = try content(1, pinned: true)
    #expect(cache.resolve(pinned, transform: transform).overlays == pinned.overlays)
    let exactMoved = try content(1.01, pinned: true)
    #expect(cache.resolve(exactMoved, transform: transform).overlays == exactMoved.overlays)
    let planned = try content(2, kind: .intendedPath)
    _ = cache.resolve(planned, transform: transform)
    let plannedMoved = try content(2.01, kind: .intendedPath)
    #expect(cache.resolve(plannedMoved, transform: transform).overlays == plannedMoved.overlays)
    _ = cache.resolve(try content(0), transform: transform)
    let otherCamera = try content(1, configuration: CameraConfigurationID())
    #expect(cache.resolve(otherCamera, transform: transform).overlays == otherCamera.overlays)
    let empty = ActionSurfaceOverlayContent(presentation: .init(displayedFrame: nil, overlays: []))
    #expect(cache.resolve(empty, transform: nil).overlays.isEmpty)
    let restored = try content(1)
    #expect(cache.resolve(restored, transform: transform).overlays == restored.overlays)
  }

  @Test("bounds movement respects the threshold and shape changes invalidate")
  func boundsAndTopology() throws {
    let cache = ActionSurfaceOverlayContentCache()
    let first = try content(0, bounds: true)
    _ = cache.resolve(first, transform: transform)
    #expect(cache.resolve(try content(5, bounds: true), transform: transform).overlays == first.overlays)
    let large = try content(9, bounds: true)
    #expect(cache.resolve(large, transform: transform).overlays == large.overlays)
    let point = try content(9)
    #expect(cache.resolve(point, transform: transform).overlays == point.overlays)
  }

  @Test("a distant armature vertex refreshes the entire measured scene and topology changes are immediate")
  func coherentSceneAndPolyline() throws {
    func scene(capOffset: Double, armatureOffset: Double, count: Int = 2) throws -> ActionSurfaceOverlayContent {
      var scene = try content(capOffset)
      let cap = scene.overlays[0]
      scene.overlays.append(CameraOverlayMeasurement(frameID: cap.frameID,
        cameraConfigurationID: cap.cameraConfigurationID,
        geometry: .polyline(try .init(points: (0..<count).map {
          try .init(x: 30 + Double($0) * 10 + armatureOffset, y: 30)
        })), provenance: .init(kind: .armatureEstimate, source: .inferred, algorithmRevision: "envelope-v1")))
      return scene
    }
    let cache = ActionSurfaceOverlayContentCache()
    let initial = try scene(capOffset: 0, armatureOffset: 0)
    _ = cache.resolve(initial, transform: transform)
    #expect(cache.resolve(try scene(capOffset: 4, armatureOffset: 4), transform: transform).overlays == initial.overlays)
    let moved = try scene(capOffset: 1, armatureOffset: 9)
    #expect(cache.resolve(moved, transform: transform).overlays == moved.overlays)
    let topology = try scene(capOffset: 1.01, armatureOffset: 9.01, count: 3)
    #expect(cache.resolve(topology, transform: transform).overlays == topology.overlays)
  }

  @Test("diagonal distance is bounded radially and changed detector provenance resets retained geometry")
  func radialDistanceAndDetectorChange() throws {
    let cache = ActionSurfaceOverlayContentCache()
    let initial = try content(0)
    _ = cache.resolve(initial, transform: transform)
    var diagonal = try content(6)
    let overlay = diagonal.overlays[0]
    diagonal.overlays[0] = CameraOverlayMeasurement(frameID: overlay.frameID,
      cameraConfigurationID: overlay.cameraConfigurationID,
      geometry: .point(try .init(x: 46, y: 46)), provenance: overlay.provenance)
    #expect(cache.resolve(diagonal, transform: transform).overlays == diagonal.overlays)
    let newDetector = try content(6.01, revision: "detector-v2")
    #expect(cache.resolve(newDetector, transform: transform).overlays == newDetector.overlays)
  }

  private func content(
    _ offset: Double,
    kind: CameraOverlayKind = .penCap,
    configuration: CameraConfigurationID? = nil,
    revision: String = "detector-v1",
    pinned: Bool = false,
    bounds: Bool = false
  ) throws -> ActionSurfaceOverlayContent {
    let frame = DisplayedFrame(source: .live(.init(rawValue: "tolerance-test")), frame: try StampedFrame(
      sequence: 1, captureNanoseconds: 1, cameraConfigurationID: configuration ?? self.configuration,
      width: 100, height: 100, rowBytes: 400, pixelFormat: .bgra8,
      bytes: OwnedFrameBytes(Array(repeating: 255, count: 40_000))))
    let geometry: CameraPixelGeometry = bounds
      ? .bounds(try .init(minX: 30 + offset, minY: 30, maxX: 50 + offset, maxY: 50))
      : .point(try .init(x: 40 + offset, y: 40))
    let overlay = CameraOverlayMeasurement(frameID: frame.frame.id,
      cameraConfigurationID: frame.frame.cameraConfigurationID, geometry: geometry,
      provenance: .init(kind: kind, source: .measured, algorithmRevision: revision))
    return ActionSurfaceOverlayContent(presentation: .init(displayedFrame: frame,
      usesAmbientPreviewFrame: !pinned, overlays: [overlay], analyzedOverlayFrame: .init(frame)))
  }
}
