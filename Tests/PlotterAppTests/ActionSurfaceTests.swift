import CoreGraphics
import Foundation
import PlotterModel
import PlotterRuntime
import Testing

@testable import PlotterApp

@Test("Aspect-fit mapping preserves camera top-left origin and +Y down")
func aspectFitMappingCornersAndCenter() throws {
  let transform = try #require(
    CameraPixelToViewTransform(
      frameWidth: 640,
      frameHeight: 480,
      viewWidth: 800,
      viewHeight: 800
    )
  )

  #expect(transform.imageRect == CGRect(x: 0, y: 100, width: 800, height: 600))
  #expect(transform.point(try Point2(x: 0, y: 0)) == CGPoint(x: 0, y: 100))
  #expect(transform.point(try Point2(x: 640, y: 480)) == CGPoint(x: 800, y: 700))
  #expect(transform.point(try Point2(x: 320, y: 240)) == CGPoint(x: 400, y: 400))
  #expect(transform.point(try Point2(x: 0, y: 1)).y > transform.point(try Point2(x: 0, y: 0)).y)
}

@Test("Aspect-fit mapping letterboxes wide and tall view sizes")
func aspectFitMappingMultipleSizes() throws {
  let wide = try #require(
    CameraPixelToViewTransform(
      frameWidth: 100,
      frameHeight: 200,
      viewWidth: 400,
      viewHeight: 200
    )
  )
  #expect(wide.imageRect == CGRect(x: 150, y: 0, width: 100, height: 200))

  let tall = try #require(
    CameraPixelToViewTransform(
      frameWidth: 200,
      frameHeight: 100,
      viewWidth: 200,
      viewHeight: 400
    )
  )
  #expect(tall.imageRect == CGRect(x: 0, y: 150, width: 200, height: 100))
}

@Test("Inverse mapping round-trips full-frame and zoomed camera pixels")
func inverseMappingRoundTrip() throws {
  let region = PixelRect(x: 300, y: 200, width: 40, height: 20)
  for focus in [nil, region] {
    let transform = try #require(
      CameraPixelToViewTransform(
        frameWidth: 640, frameHeight: 480, viewWidth: 800, viewHeight: 600,
        focusRegion: focus
      ))
    let camera = try Point2<CameraPixelSpace>(x: focus == nil ? 321.25 : 321, y: 211.75)
    let roundTrip = try #require(transform.cameraPoint(transform.point(camera)))
    #expect(abs(roundTrip.x - camera.x) < 1e-9)
    #expect(abs(roundTrip.y - camera.y) < 1e-9)
  }
}

@Test("Inverse mapping rejects clicks in aspect-fit letterboxes")
func inverseMappingRejectsLetterbox() throws {
  let transform = try #require(
    CameraPixelToViewTransform(
      frameWidth: 100, frameHeight: 200, viewWidth: 400, viewHeight: 200
    ))
  #expect(transform.cameraPoint(CGPoint(x: 149, y: 100)) == nil)
  #expect(transform.cameraPoint(CGPoint(x: 251, y: 100)) == nil)
  #expect(try #require(transform.cameraPoint(CGPoint(x: 200, y: 100))).x == 50)
}

@Test("Viewport defaults full-frame, interpolates, and reaches fitted learned bounds")
func viewportZoomEndpointsAndInterpolation() {
  let context = ActionSurfaceViewportContext(
    source: .simulated,
    cameraConfigurationID: CameraConfigurationID(),
    fittedRegion: PixelRect(x: 300, y: 200, width: 40, height: 20),
    preferredInitialZoom: 0,
    presentationRevisionToken: "bounds-1"
  )
  var viewport = ActionSurfaceViewportState()
  viewport.synchronize(with: context)
  #expect(viewport.zoom == 0)
  #expect(viewport.visibleRegion(frameWidth: 640, frameHeight: 480) == nil)

  viewport.zoom = 0.5
  #expect(
    viewport.visibleRegion(frameWidth: 640, frameHeight: 480)
      == PixelRect(x: 150, y: 100, width: 340, height: 250)
  )
  let evidenceRevision = viewport.presentationTransformRevision
  viewport.showFittedBounds()
  #expect(viewport.visibleRegion(frameWidth: 640, frameHeight: 480) == context.fittedRegion)
  #expect(viewport.presentationTransformRevision != evidenceRevision)
}

@Test("Viewport preserves operator zoom across compatible semantic context changes")
func viewportPresentationOnlyContext() {
  let context = ActionSurfaceViewportContext(
    source: .simulated,
    cameraConfigurationID: CameraConfigurationID(),
    fittedRegion: PixelRect(x: 20, y: 30, width: 40, height: 50),
    preferredInitialZoom: 0,
    presentationRevisionToken: "machine-fit-1"
  )
  var viewport = ActionSurfaceViewportState()
  viewport.synchronize(with: context)
  viewport.zoom = 0.72
  viewport.pan(
    by: CGSize(width: -20, height: -10),
    viewSize: CGSize(width: 640, height: 480),
    frameWidth: 640,
    frameHeight: 480
  )
  let operatorRegion = viewport.visibleRegion(frameWidth: 640, frameHeight: 480)
  viewport.synchronize(with: context)
  #expect(viewport.zoom == 0.72)
  viewport.synchronize(
    with: ActionSurfaceViewportContext(
      source: context.source,
      cameraConfigurationID: context.cameraConfigurationID,
      fittedRegion: context.fittedRegion,
      preferredInitialZoom: 0,
      presentationRevisionToken: "machine-fit-2"
    ))
  #expect(viewport.zoom == 0.72)
  #expect(viewport.visibleRegion(frameWidth: 640, frameHeight: 480) == operatorRegion)

  viewport.zoom = 0.44
  viewport.synchronize(
    with: ActionSurfaceViewportContext(
      source: context.source,
      cameraConfigurationID: CameraConfigurationID(),
      fittedRegion: context.fittedRegion,
      preferredInitialZoom: 0,
      presentationRevisionToken: "different-camera"
    ))
  #expect(viewport.zoom == 0)
}

@Test("Viewport drag pans the zoomed camera region and clamps at frame edges")
func viewportDragPanning() {
  let context = ActionSurfaceViewportContext(
    source: .simulated,
    cameraConfigurationID: CameraConfigurationID(),
    fittedRegion: nil,
    preferredInitialZoom: 1,
    presentationRevisionToken: "drag-region"
  )
  var viewport = ActionSurfaceViewportState()
  viewport.synchronize(with: context)
  #expect(
    viewport.visibleRegion(frameWidth: 100, frameHeight: 100)
      == PixelRect(x: 25, y: 25, width: 50, height: 50)
  )

  viewport.pan(
    by: CGSize(width: -100, height: -100),
    viewSize: CGSize(width: 100, height: 100),
    frameWidth: 100,
    frameHeight: 100
  )
  #expect(
    viewport.visibleRegion(frameWidth: 100, frameHeight: 100)
      == PixelRect(x: 50, y: 50, width: 50, height: 50)
  )

  viewport.pan(
    by: CGSize(width: 1_000, height: 1_000),
    viewSize: CGSize(width: 100, height: 100),
    frameWidth: 100,
    frameHeight: 100
  )
  #expect(
    viewport.visibleRegion(frameWidth: 100, frameHeight: 100)
      == PixelRect(x: 0, y: 0, width: 50, height: 50)
  )
}

@Test("Fitted presentation bounds use true frame intersections")
func viewportClipsFittedBoundsAtEveryFrameEdge() {
  let cases: [(PixelRect, PixelRect?)] = [
    (
      PixelRect(x: -10, y: -5, width: 20, height: 20),
      PixelRect(x: 0, y: 0, width: 10, height: 15)
    ),
    (
      PixelRect(x: 90, y: 95, width: 20, height: 20),
      PixelRect(x: 90, y: 95, width: 10, height: 5)
    ),
    (
      PixelRect(x: 25, y: -4, width: 30, height: 12),
      PixelRect(x: 25, y: 0, width: 30, height: 8)
    ),
    (PixelRect(x: 101, y: 10, width: 20, height: 20), nil),
  ]

  for (region, expected) in cases {
    #expect(cameraFrameIntersection(region, frameWidth: 100, frameHeight: 100) == expected)
    var viewport = ActionSurfaceViewportState()
    viewport.synchronize(
      with: ActionSurfaceViewportContext(
        source: .simulated,
        cameraConfigurationID: CameraConfigurationID(),
        fittedRegion: region,
        preferredInitialZoom: 0,
        presentationRevisionToken: "bounds-edge"
      ))
    viewport.showFittedBounds()
    #expect(viewport.visibleRegion(frameWidth: 100, frameHeight: 100) == expected)
  }
}

@Test("Sparse batch context preserves operator zoom and pan without fitted focus")
func sparseBatchPreservesViewport() {
  let configuration = CameraConfigurationID()
  let learnedBounds = PixelRect(x: 80, y: 60, width: 480, height: 360)
  var viewport = ActionSurfaceViewportState()
  viewport.synchronize(
    with: ActionSurfaceViewportContext(
      source: .simulated,
      cameraConfigurationID: configuration,
      fittedRegion: learnedBounds,
      preferredInitialZoom: 0,
      presentationRevisionToken: "machine-bounds"
    ))
  viewport.zoom = 0.63
  viewport.pan(
    by: CGSize(width: -32, height: -18),
    viewSize: CGSize(width: 640, height: 480),
    frameWidth: 640,
    frameHeight: 480
  )
  let priorRegion = viewport.visibleRegion(frameWidth: 640, frameHeight: 480)
  for token in [
    "sparse-batch-started",
    "sparse-batch-frozen-frame",
    "sparse-batch-clicks-changed",
    "sparse-batch-fitting",
    "sparse-batch-proposal",
  ] {
    viewport.synchronize(
      with: ActionSurfaceViewportContext(
        source: .simulated,
        cameraConfigurationID: configuration,
        fittedRegion: learnedBounds,
        preferredInitialZoom: 0,
        presentationRevisionToken: token
      ))
    #expect(viewport.zoom == 0.63)
    #expect(viewport.visibleRegion(frameWidth: 640, frameHeight: 480) == priorRegion)
  }

}

@Test("Tip presentation hides prediction until after selection")
func tipPredictionVisibilityPolicy() throws {
  #expect(ActionSurfaceTipPresentation.notCalibrated.statusText == "Tip not calibrated")
  if case .awaitingClick = ActionSurfaceTipPresentation.awaitingClick("Click mark center") {
  } else {
    Issue.record("awaiting click state must not contain a prediction")
  }
  let prediction = try Point2<CameraPixelSpace>(x: 12, y: 14)
  let selection = try Point2<CameraPixelSpace>(x: 13, y: 14)
  let selected = ActionSurfaceTipPresentation.selected(
    click: selection,
    pointingUncertaintyPixels: try Vector2(dx: 1.5, dy: 2),
    prediction: prediction,
    residualPixels: 1
  )
  #expect(selected.statusText == "Selection residual 1.000 px")
  let geometry = try #require(selected.reviewGeometry)
  #expect(geometry.click == selection)
  let uncertainty = try Vector2<CameraPixelSpace>(dx: 1.5, dy: 2)
  #expect(geometry.pointingUncertaintyPixels == uncertainty)
  #expect(geometry.prediction == prediction)
  #expect(geometry.residual?.start == prediction)
  #expect(geometry.residual?.end == selection)

  let clicks = [
    try Point2<CameraPixelSpace>(x: 10, y: 20),
    try Point2<CameraPixelSpace>(x: 30, y: 40),
  ]
  let collecting = ActionSurfaceTipPresentation.collectingClicks(
    prompt: "Click all five circle centers on this unchanged frame.",
    clicks: clicks
  )
  #expect(collecting.statusText == "2/5 centers selected · Click all five circle centers on this unchanged frame.")
  #expect(collecting.clickMarkers == clicks)
}

@Test("Every click permutation associates to canonical machine positions")
func sparseTipClickAssociationIsOrderIndependent() throws {
  let fixture = try sparseAssociationFixture()
  for clicks in testPermutations(of: fixture.clickedByPosition.map { $0.1 }) {
    let associations = try associateSparseTipClicks(
      using: fixture.fit,
      knownMachinePositions: fixture.known,
      clicks: clicks
    )
    #expect(associations.map(\.calibrationPosition) == ToolContactCalibrationPosition.allCases)
    for association in associations {
      #expect(
        association.clickedCameraPoint
          == fixture.clickedByPosition.first {
            $0.0 == association.calibrationPosition
          }?.1
      )
    }
  }
}

@Test("Sparse click association has no distance or ambiguity rejection gate")
func sparseTipClickAssociationNeverQualityGates() throws {
  let fixture = try sparseAssociationFixture()
  var distantClicks = fixture.clickedByPosition.map { $0.1 }
  distantClicks[0] = try Point2(x: distantClicks[0].x + 4_000, y: distantClicks[0].y - 3_000)
  let distant = try associateSparseTipClicks(
    using: fixture.fit,
    knownMachinePositions: fixture.known,
    clicks: Array(distantClicks.reversed())
  )
  #expect(distant.count == 5)

  let tiedClicks = try [
    Point2<CameraPixelSpace>(x: 290, y: 190),
    Point2<CameraPixelSpace>(x: 310, y: 190),
    Point2<CameraPixelSpace>(x: 310, y: 210),
    Point2<CameraPixelSpace>(x: 290, y: 210),
    Point2<CameraPixelSpace>(x: 300, y: 200),
  ]
  let tiedForward = try associateSparseTipClicks(
    using: fixture.fit,
    knownMachinePositions: Array(fixture.known.reversed()),
    clicks: tiedClicks
  )
  let tiedReverse = try associateSparseTipClicks(
    using: fixture.fit,
    knownMachinePositions: fixture.known,
    clicks: Array(tiedClicks.reversed())
  )
  #expect(tiedForward.map(\.calibrationPosition) == ToolContactCalibrationPosition.allCases)
  #expect(tiedForward == tiedReverse)
}

@Test("Exact selection request rejects a stale frame hash, source, or dimensions")
func exactSelectionRequestProvenance() throws {
  let displayed = try testDisplayedFrame(source: .simulated)
  let optical = try CameraOpticalConfigurationIdentity(
    source: displayed.source,
    sensorFormat: "test",
    width: displayed.frame.width,
    height: displayed.frame.height,
    pixelFormat: displayed.frame.pixelFormat,
    orientation: .up,
    mirrored: false,
    digitalZoomFactor: 1,
    lensIdentity: "fixed-lens",
    focusConfiguration: "fixed-focus",
    mountRevision: UUID(),
    reframingRevision: UUID()
  )
  let exact = try ExactTipCalibrationFrame(
    frameID: displayed.frame.id,
    frameSHA256: displayed.frame.contentSHA256,
    source: displayed.source,
    captureSessionID: CameraCaptureSessionID(),
    opticalConfiguration: optical,
    cameraConfigurationID: displayed.frame.cameraConfigurationID,
    captureNanoseconds: displayed.frame.captureNanoseconds,
    width: displayed.frame.width,
    height: displayed.frame.height,
    pixelFormat: displayed.frame.pixelFormat
  )
  let request = ActionSurfacePointSelectionRequest(
    frame: exact,
    presentationTransformRevision: PresentationTransformRevision(),
    prompt: "Click center"
  )
  #expect(request.matches(displayed))
  let stale = try testDisplayedFrame(
    source: .simulated, configuration: displayed.frame.cameraConfigurationID)
  #expect(!request.matches(stale))
}

@Test("Overlay is hidden when frame or camera configuration identity differs")
func overlayIdentityMismatchIsHidden() throws {
  let configuration = CameraConfigurationID()
  let displayed = try testDisplayedFrame(configuration: configuration)
  let matching = CameraOverlayMeasurement(
    frameID: displayed.frame.id,
    cameraConfigurationID: configuration,
    geometry: .point(try Point2(x: 1, y: 1)),
    provenance: .init(kind: .diagnostic, source: .diagnostic, algorithmRevision: "v1")
  )
  let wrongFrame = CameraOverlayMeasurement(
    frameID: FrameID(),
    cameraConfigurationID: configuration,
    geometry: .point(try Point2(x: 1, y: 1)),
    provenance: .init(kind: .diagnostic, source: .diagnostic, algorithmRevision: "v1")
  )
  let wrongConfiguration = CameraOverlayMeasurement(
    frameID: displayed.frame.id,
    cameraConfigurationID: CameraConfigurationID(),
    geometry: .point(try Point2(x: 1, y: 1)),
    provenance: .init(kind: .diagnostic, source: .diagnostic, algorithmRevision: "v1")
  )

  let presentation = ActionSurfacePresentation(
    displayedFrame: displayed,
    overlays: [wrongFrame, matching, wrongConfiguration]
  )

  #expect(presentation.overlays == [matching])
}

@Test("Simulated annotations require exact frame configuration and viewport identity")
func simulatedAnnotationIdentityAndToggle() throws {
  let configuration = CameraConfigurationID()
  let displayed = try testDisplayedFrame(
    source: .simulated,
    configuration: configuration
  )
  let viewport = SimulatedCameraViewportID(rawValue: "viewport-a")
  let point = try Point2<CameraPixelSpace>(x: 12, y: 18)
  func annotation(
    frameID: FrameID,
    configurationID: CameraConfigurationID,
    viewportID: SimulatedCameraViewportID
  ) -> SimulatedLearningAnnotation {
    SimulatedLearningAnnotation(
      kind: .currentCapAnchor,
      anchor: point,
      geometry: .point(point),
      visibleLabel: "MPOS",
      accessibleValue: "Simulated current position",
      frameID: frameID,
      cameraConfigurationID: configurationID,
      viewportID: viewportID
    )
  }
  let matching = annotation(
    frameID: displayed.frame.id,
    configurationID: configuration,
    viewportID: viewport
  )
  let wrongFrame = annotation(
    frameID: FrameID(),
    configurationID: configuration,
    viewportID: viewport
  )
  let wrongConfiguration = annotation(
    frameID: displayed.frame.id,
    configurationID: CameraConfigurationID(),
    viewportID: viewport
  )
  let wrongViewport = annotation(
    frameID: displayed.frame.id,
    configurationID: configuration,
    viewportID: SimulatedCameraViewportID(rawValue: "viewport-b")
  )

  let visible = ActionSurfacePresentation(
    displayedFrame: displayed,
    overlays: [],
    simulatedAnnotations: [wrongFrame, wrongConfiguration, wrongViewport, matching],
    simulatedViewportID: viewport
  )
  #expect(visible.simulatedAnnotations == [matching])
  #expect(visible.rendererIdentity == "canonical-stamped-frame")

  let hidden = ActionSurfacePresentation(
    displayedFrame: displayed,
    overlays: [],
    simulatedAnnotations: [matching],
    simulatedViewportID: viewport,
    simulatedAnnotationsAreVisible: false
  )
  #expect(hidden.simulatedAnnotations.isEmpty)
  #expect(hidden.displayedFrame?.frame == visible.displayedFrame?.frame)
}

@Test("Live and simulated frames use the same canonical renderer")
func liveAndSimulatorShareRenderer() throws {
  let live = try testDisplayedFrame(source: .live(CameraDeviceID(rawValue: "camera-a")))
  let simulated = try testDisplayedFrame(source: .simulated)

  let livePresentation = ActionSurfacePresentation(displayedFrame: live, overlays: [])
  let simulatedPresentation = ActionSurfacePresentation(displayedFrame: simulated, overlays: [])

  #expect(ActionSurfacePresentation.rendererIdentity == "canonical-stamped-frame")
  #expect(livePresentation.rendererIdentity == simulatedPresentation.rendererIdentity)
  #expect(livePresentation.sourceBadgeLabel == nil)
  #expect(simulatedPresentation.sourceBadgeLabel == "SIMULATED")
}

@Test("Presentation image interprets padded BGRA, RGBA, and gray rows exactly")
func presentationImagePixelFormatsAndPaddedStride() throws {
  let configuration = CameraConfigurationID()
  let expectedColorPixels = [
    RGBPixel(red: 255, green: 0, blue: 0),
    RGBPixel(red: 0, green: 255, blue: 0),
    RGBPixel(red: 0, green: 0, blue: 255),
    RGBPixel(red: 255, green: 255, blue: 255),
  ]

  let bgra = try StampedFrame(
    sequence: 1,
    captureNanoseconds: 1,
    cameraConfigurationID: configuration,
    width: 2,
    height: 2,
    rowBytes: 12,
    pixelFormat: .bgra8,
    bytes: OwnedFrameBytes([
      0, 0, 255, 17, 0, 255, 0, 18, 91, 92, 93, 94,
      255, 0, 0, 19, 255, 255, 255, 20, 81, 82, 83, 84,
    ])
  )
  let rgba = try StampedFrame(
    sequence: 2,
    captureNanoseconds: 2,
    cameraConfigurationID: configuration,
    width: 2,
    height: 2,
    rowBytes: 12,
    pixelFormat: .rgba8,
    bytes: OwnedFrameBytes([
      255, 0, 0, 17, 0, 255, 0, 18, 91, 92, 93, 94,
      0, 0, 255, 19, 255, 255, 255, 20, 81, 82, 83, 84,
    ])
  )
  let gray = try StampedFrame(
    sequence: 3,
    captureNanoseconds: 3,
    cameraConfigurationID: configuration,
    width: 2,
    height: 2,
    rowBytes: 4,
    pixelFormat: .gray8,
    bytes: OwnedFrameBytes([
      0, 127, 91, 92,
      200, 255, 81, 82,
    ])
  )

  let bgraPixels = try renderedRGBPixels(bgra)
  let rgbaPixels = try renderedRGBPixels(rgba)
  let grayPixels = try renderedRGBPixels(gray)
  #expect(bgraPixels == expectedColorPixels)
  #expect(rgbaPixels == expectedColorPixels)
  #expect(
    grayPixels == [
      RGBPixel(red: 0, green: 0, blue: 0),
      RGBPixel(red: 127, green: 127, blue: 127),
      RGBPixel(red: 200, green: 200, blue: 200),
      RGBPixel(red: 255, green: 255, blue: 255),
    ])
}

@MainActor
@Test("Frame identity cache converts once across repeated projection updates and remains bounded")
func presentationImageCacheIsIdentityKeyedAndBounded() throws {
  let cache = FramePresentationImageCache()
  let frameID = FrameID()
  let configurationID = CameraConfigurationID()
  let frame = try testFrame(id: frameID, configuration: configurationID)

  let initialImage = try #require(cache.image(from: frame))
  for index in 0..<2_000 {
    _ = CameraPixelToViewTransform(
      frameWidth: frame.width,
      frameHeight: frame.height,
      viewWidth: Double(320 + index % 7),
      viewHeight: Double(240 + index % 5)
    )
    let repeatedImage = try #require(cache.image(from: frame))
    #expect(repeatedImage === initialImage)
  }
  #expect(cache.conversionCount == 1)
  #expect(cache.cachedEntryCount == 1)

  let sameIdentity = try testFrame(
    id: frameID,
    configuration: configurationID,
    bytes: Array(repeating: 0, count: 16)
  )
  #expect(cache.image(from: sameIdentity) === initialImage)
  #expect(cache.conversionCount == 1)

  for sequence in 2...121 {
    let advancingFrame = try testFrame(
      id: FrameID(),
      configuration: configurationID,
      sequence: UInt64(sequence)
    )
    _ = try #require(cache.image(from: advancingFrame))
    #expect(cache.cachedEntryCount == 1)
  }
  #expect(cache.conversionCount == 121)

  let reconfigured = try testFrame(
    id: frameID,
    configuration: CameraConfigurationID()
  )
  _ = try #require(cache.image(from: reconfigured))
  #expect(cache.conversionCount == 122)
  #expect(cache.cachedEntryCount == 1)
}

private func testDisplayedFrame(
  source: FrameSourceIdentity = .live(CameraDeviceID(rawValue: "camera-a")),
  configuration: CameraConfigurationID = CameraConfigurationID()
) throws -> DisplayedFrame {
  DisplayedFrame(
    source: source,
    frame: try StampedFrame(
      sequence: 1,
      captureNanoseconds: 10,
      cameraConfigurationID: configuration,
      width: 2,
      height: 2,
      rowBytes: 8,
      pixelFormat: .bgra8,
      bytes: OwnedFrameBytes(Array(repeating: 255, count: 16))
    )
  )
}

private func sparseAssociationFixture() throws -> (
  fit: MachineCameraRegistrationFit,
  known: [SparseTipKnownMachinePosition],
  clickedByPosition: [(ToolContactCalibrationPosition, Point2<CameraPixelSpace>)]
) {
  let machineByPosition: [ToolContactCalibrationPosition: MachinePosition] = [
    .center: try MachinePosition(x: 0, y: 0),
    .negativeX: try MachinePosition(x: -30, y: 0),
    .positiveY: try MachinePosition(x: 0, y: 30),
    .positiveX: try MachinePosition(x: 30, y: 0),
    .negativeY: try MachinePosition(x: 0, y: -30),
  ]
  let known = ToolContactCalibrationPosition.allCases.map {
    SparseTipKnownMachinePosition(
      calibrationPosition: $0,
      machinePosition: machineByPosition[$0]!
    )
  }
  let correspondences = try known.map { knownPosition in
    let machine = knownPosition.machinePosition.point
    return MachineCameraRegistrationCorrespondence(
      machine: machine,
      camera: try Point2(
        x: 300 + 2 * machine.x + 0.25 * machine.y,
        y: 200 - 0.4 * machine.x + 1.5 * machine.y
      )
    )
  }
  let fit = try MachineCameraRegistrationFit.fit(correspondences: correspondences)
  let clickedByPosition = try known.map { knownPosition in
    (
      knownPosition.calibrationPosition,
      try Point2<CameraPixelSpace>(
        x: fit.cameraPoint(from: knownPosition.machinePosition.point).x + 17,
        y: fit.cameraPoint(from: knownPosition.machinePosition.point).y - 11
      )
    )
  }
  return (fit, known, clickedByPosition)
}

private func testPermutations<T>(of values: [T]) -> [[T]] {
  guard !values.isEmpty else { return [[]] }
  return values.indices.flatMap { index in
    var remaining = values
    let next = remaining.remove(at: index)
    return testPermutations(of: remaining).map { [next] + $0 }
  }
}

private struct RGBPixel: Equatable {
  let red: UInt8
  let green: UInt8
  let blue: UInt8
}

private func renderedRGBPixels(_ frame: StampedFrame) throws -> [RGBPixel] {
  let image = try #require(FrameImageFactory.image(from: frame))
  let outputRowBytes = frame.width * 4
  var output = [UInt8](repeating: 0, count: outputRowBytes * frame.height)
  let didDraw = output.withUnsafeMutableBytes { bytes -> Bool in
    guard
      let baseAddress = bytes.baseAddress,
      let context = CGContext(
        data: baseAddress,
        width: frame.width,
        height: frame.height,
        bitsPerComponent: 8,
        bytesPerRow: outputRowBytes,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
          .union(.byteOrder32Big).rawValue
      )
    else { return false }
    context.interpolationQuality = .none
    context.draw(
      image,
      in: CGRect(x: 0, y: 0, width: frame.width, height: frame.height)
    )
    return true
  }
  try #require(didDraw)

  return stride(from: 0, to: output.count, by: 4).map { offset in
    RGBPixel(
      red: output[offset],
      green: output[offset + 1],
      blue: output[offset + 2]
    )
  }
}

private func testFrame(
  id: FrameID = FrameID(),
  configuration: CameraConfigurationID = CameraConfigurationID(),
  sequence: UInt64 = 1,
  bytes: [UInt8] = Array(repeating: 255, count: 16)
) throws -> StampedFrame {
  try StampedFrame(
    id: id,
    sequence: sequence,
    captureNanoseconds: sequence,
    cameraConfigurationID: configuration,
    width: 2,
    height: 2,
    rowBytes: 8,
    pixelFormat: .bgra8,
    bytes: OwnedFrameBytes(bytes)
  )
}
