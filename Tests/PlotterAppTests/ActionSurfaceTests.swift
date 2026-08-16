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

@MainActor
@Test("Viewport defaults full-frame and uses fitted bounds only after operator action")
func viewportZoomEndpointsAndInterpolation() {
  let context = ActionSurfaceViewportContext(
    source: .simulated,
    cameraConfigurationID: CameraConfigurationID(),
    fittedRegion: PixelRect(x: 300, y: 200, width: 40, height: 20)
  )
  let preferences = VideoPresentationPreferences()
  preferences.synchronize(with: context)
  #expect(preferences.zoom == 0)
  #expect(
    preferences.visibleRect(frameWidth: 640, frameHeight: 480)
      == PixelRect(x: 0, y: 0, width: 640, height: 480)
  )

  preferences.fitCurrentSuggestion()
  preferences.setZoom(0.5)
  #expect(
    preferences.visibleRect(frameWidth: 640, frameHeight: 480)
      == PixelRect(x: 150, y: 100, width: 340, height: 250)
  )
  preferences.fitCurrentSuggestion()
  #expect(preferences.visibleRect(frameWidth: 640, frameHeight: 480) == context.fittedRegion)
}

@MainActor
@Test("Learning context never changes an operator viewport or locked ROI")
func viewportPresentationOnlyContext() throws {
  let context = ActionSurfaceViewportContext(
    source: .simulated,
    cameraConfigurationID: CameraConfigurationID(),
    fittedRegion: PixelRect(x: 20, y: 30, width: 40, height: 50)
  )
  let preferences = VideoPresentationPreferences()
  preferences.synchronize(with: context)
  preferences.fitCurrentSuggestion()
  preferences.setZoom(0.72)
  preferences.pan(
    by: CGSize(width: -20, height: -10),
    viewSize: CGSize(width: 640, height: 480),
    frameWidth: 640,
    frameHeight: 480
  )
  let operatorRegion = preferences.visibleRect(frameWidth: 640, frameHeight: 480)
  preferences.synchronize(
    with: ActionSurfaceViewportContext(
      source: context.source,
      cameraConfigurationID: context.cameraConfigurationID,
      fittedRegion: context.fittedRegion
    ))
  #expect(preferences.zoom == 0.72)
  #expect(preferences.visibleRect(frameWidth: 640, frameHeight: 480) == operatorRegion)

  let displayedFrame = try testDisplayedFrame(
    source: context.source,
    configuration: context.cameraConfigurationID,
    width: 640,
    height: 480
  )
  #expect(preferences.lockVisibleRect(for: displayedFrame) == operatorRegion)
  #expect(preferences.analysisROI == operatorRegion)

  preferences.synchronize(
    with: ActionSurfaceViewportContext(
      source: context.source,
      cameraConfigurationID: context.cameraConfigurationID,
      fittedRegion: PixelRect(x: 25, y: 35, width: 40, height: 50)
    ))
  #expect(preferences.zoom == 0.72)
  #expect(preferences.visibleRect(frameWidth: 640, frameHeight: 480) == operatorRegion)
  #expect(preferences.analysisROI == operatorRegion)

  preferences.synchronize(
    with: ActionSurfaceViewportContext(
      source: context.source,
      cameraConfigurationID: CameraConfigurationID(),
      fittedRegion: context.fittedRegion
    ))
  #expect(preferences.zoom == 0)
  #expect(preferences.analysisROI == nil)
}

@MainActor
@Test("Viewport drag pans the zoomed camera region and clamps at frame edges")
func viewportDragPanning() {
  let context = ActionSurfaceViewportContext(
    source: .simulated,
    cameraConfigurationID: CameraConfigurationID(),
    fittedRegion: nil
  )
  let preferences = VideoPresentationPreferences()
  preferences.synchronize(with: context)
  preferences.setZoom(1)
  #expect(
    preferences.visibleRect(frameWidth: 100, frameHeight: 100)
      == PixelRect(x: 25, y: 25, width: 50, height: 50)
  )

  preferences.pan(
    by: CGSize(width: -100, height: -100),
    viewSize: CGSize(width: 100, height: 100),
    frameWidth: 100,
    frameHeight: 100
  )
  #expect(
    preferences.visibleRect(frameWidth: 100, frameHeight: 100)
      == PixelRect(x: 50, y: 50, width: 50, height: 50)
  )

  preferences.pan(
    by: CGSize(width: 1_000, height: 1_000),
    viewSize: CGSize(width: 100, height: 100),
    frameWidth: 100,
    frameHeight: 100
  )
  #expect(
    preferences.visibleRect(frameWidth: 100, frameHeight: 100)
      == PixelRect(x: 0, y: 0, width: 50, height: 50)
  )
}

@MainActor
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
    let preferences = VideoPresentationPreferences()
    preferences.synchronize(
      with: ActionSurfaceViewportContext(
        source: .simulated,
        cameraConfigurationID: CameraConfigurationID(),
        fittedRegion: region
      ))
    preferences.fitCurrentSuggestion()
    #expect(
      preferences.visibleRect(frameWidth: 100, frameHeight: 100)
        == (expected ?? PixelRect(x: 0, y: 0, width: 100, height: 100))
    )
  }
}

@MainActor
@Test("Sparse mark focus is a suggestion until explicitly accepted")
func sparseMarkPreferredZoom() {
  let region = PixelRect(x: 210, y: 160, width: 213, height: 160)
  let preferences = VideoPresentationPreferences()
  preferences.synchronize(
    with: ActionSurfaceViewportContext(
      source: .simulated,
      cameraConfigurationID: CameraConfigurationID(),
      fittedRegion: region
    ))

  #expect(preferences.zoom == 0)
  #expect(
    preferences.visibleRect(frameWidth: 640, frameHeight: 480)
      == PixelRect(x: 0, y: 0, width: 640, height: 480)
  )
  preferences.fitCurrentSuggestion()
  #expect(preferences.visibleRect(frameWidth: 640, frameHeight: 480) == region)
}

@MainActor
@Test("Zoom is display-only until lock and unlock preserves geometry")
func viewportAnalysisROILockSemantics() throws {
  let displayedFrame = try testDisplayedFrame(width: 100, height: 100)
  let preferences = VideoPresentationPreferences()
  preferences.synchronize(
    with: ActionSurfaceViewportContext(
      source: displayedFrame.source,
      cameraConfigurationID: displayedFrame.frame.cameraConfigurationID,
      fittedRegion: nil
    ))
  preferences.setZoom(1)

  let visible = try #require(preferences.visibleRect(frameWidth: 100, frameHeight: 100))
  #expect(visible == PixelRect(x: 25, y: 25, width: 50, height: 50))
  #expect(preferences.analysisROI == nil)
  #expect(preferences.lockVisibleRect(for: displayedFrame) == visible)
  #expect(preferences.analysisROI == visible)
  #expect(preferences.visibleRect(frameWidth: 100, frameHeight: 100) == visible)

  preferences.unlockAnalysisROI()
  #expect(preferences.analysisROI == nil)
  #expect(preferences.visibleRect(frameWidth: 100, frameHeight: 100) == visible)
}

@MainActor
@Test("Panned rendered viewport is the exact analysis lock rectangle")
func pannedViewportLockUsesRenderedRectangle() throws {
  let displayedFrame = try testDisplayedFrame(width: 100, height: 100)
  let preferences = VideoPresentationPreferences()
  preferences.synchronize(
    with: ActionSurfaceViewportContext(
      source: displayedFrame.source,
      cameraConfigurationID: displayedFrame.frame.cameraConfigurationID,
      fittedRegion: nil
    ))
  preferences.setZoom(0.7)
  preferences.pan(
    by: CGSize(width: 9, height: -6),
    viewSize: CGSize(width: 100, height: 100),
    frameWidth: 100,
    frameHeight: 100
  )
  let renderedRegion = try #require(
    preferences.visibleRect(frameWidth: 100, frameHeight: 100)
  )

  #expect(preferences.lockVisibleRect(for: displayedFrame) == renderedRegion)
  #expect(preferences.analysisROI == renderedRegion)

  preferences.unlockAnalysisROI()
  #expect(preferences.analysisROI == nil)
  #expect(preferences.visibleRect(frameWidth: 100, frameHeight: 100) == renderedRegion)
}

@MainActor
@Test("Source or configuration reset clears geometry and lock but preserves video choices")
func viewportSourceResetPreservesOperatorVideoChoices() throws {
  let first = try testDisplayedFrame(width: 100, height: 100)
  let reconfiguredID = CameraConfigurationID()
  let preferences = VideoPresentationPreferences()
  preferences.selectCadence(.tenFPS)
  preferences.setOverlay(.armatureEnvelope, enabled: false)
  #expect(preferences.overlayPreferenceState.lastMutationSource == .operatorAction)
  preferences.synchronize(
    with: ActionSurfaceViewportContext(
      source: first.source,
      cameraConfigurationID: first.frame.cameraConfigurationID,
      fittedRegion: nil
    ))
  preferences.setZoom(1)
  _ = preferences.lockVisibleRect(for: first)

  preferences.synchronize(
    with: ActionSurfaceViewportContext(
      source: first.source,
      cameraConfigurationID: reconfiguredID,
      fittedRegion: PixelRect(x: 10, y: 10, width: 20, height: 20)
    ))

  #expect(preferences.zoom == 0)
  #expect(preferences.analysisROI == nil)
  #expect(preferences.cadence == .tenFPS)
  #expect(preferences.enabledOverlays == [.penCap])
  #expect(preferences.overlayPreferenceState.lastMutationSource == .operatorAction)

  let reconfigured = try testDisplayedFrame(
    source: first.source,
    configuration: reconfiguredID,
    width: 100,
    height: 100
  )
  preferences.setZoom(1)
  _ = preferences.lockVisibleRect(for: reconfigured)
  preferences.synchronize(
    with: ActionSurfaceViewportContext(
      source: .simulated,
      cameraConfigurationID: reconfiguredID,
      fittedRegion: nil
    ))

  #expect(preferences.zoom == 0)
  #expect(preferences.analysisROI == nil)
  #expect(preferences.cadence == .tenFPS)
  #expect(preferences.enabledOverlays == [.penCap])
  #expect(preferences.overlayPreferenceState.lastMutationSource == .operatorAction)
}

@Test("Tip presentation hides prediction until after selection")
func tipPredictionVisibilityPolicy() throws {
  #expect(ActionSurfaceTipPresentation.notCalibrated.statusText == "Tip not calibrated")
  if case .awaitingClick = ActionSurfaceTipPresentation.awaitingClick {
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
      geometry: .point(point),
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
  let duplicatedAccessibility = ActionSurfacePresentation(
    displayedFrame: displayed,
    overlays: [],
    simulatedAnnotations: [matching, matching],
    simulatedViewportID: viewport
  )
  #expect(duplicatedAccessibility.simulatedAnnotations.count == 2)
  #expect(
    duplicatedAccessibility.simulatedAnnotationAccessibilityValues
      == ["Simulated current position"]
  )

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

@Test("Only simulated presentation carries a source badge")
func simulatedSourceBadge() throws {
  let live = try testDisplayedFrame(source: .live(CameraDeviceID(rawValue: "camera-a")))
  let simulated = try testDisplayedFrame(source: .simulated)

  let livePresentation = ActionSurfacePresentation(displayedFrame: live, overlays: [])
  let simulatedPresentation = ActionSurfacePresentation(displayedFrame: simulated, overlays: [])

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
  configuration: CameraConfigurationID = CameraConfigurationID(),
  width: Int = 2,
  height: Int = 2
) throws -> DisplayedFrame {
  DisplayedFrame(
    source: source,
    frame: try StampedFrame(
      sequence: 1,
      captureNanoseconds: 10,
      cameraConfigurationID: configuration,
      width: width,
      height: height,
      rowBytes: width * 4,
      pixelFormat: .bgra8,
      bytes: OwnedFrameBytes(Array(repeating: 255, count: width * height * 4))
    )
  )
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
