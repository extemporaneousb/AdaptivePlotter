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

@Test("Target ROI focus magnifies exact camera coordinates without changing provenance")
func targetROIFocusMappingAndIdentity() throws {
  let region = PixelRect(x: 300, y: 200, width: 40, height: 20)
  let transform = try #require(
    CameraPixelToViewTransform(
      frameWidth: 640,
      frameHeight: 480,
      viewWidth: 400,
      viewHeight: 400,
      focusRegion: region
    )
  )
  #expect(transform.visibleCameraRect == CGRect(x: 300, y: 200, width: 40, height: 20))
  #expect(transform.point(try Point2(x: 300, y: 200)) == CGPoint(x: 0, y: 100))
  #expect(transform.point(try Point2(x: 340, y: 220)) == CGPoint(x: 400, y: 300))

  let displayed = try testDisplayedFrame()
  let context = ActionSurfaceViewportContext(
    source: displayed.source,
    cameraConfigurationID: displayed.frame.cameraConfigurationID,
    targetAreaIdentity: UUID(),
    roiAuthorityToken: "roi-1",
    region: PixelRect(x: 1, y: 1, width: 2, height: 2)
  )
  let matching = ActionSurfaceFocus(
    frameID: displayed.frame.id,
    cameraConfigurationID: displayed.frame.cameraConfigurationID,
    region: PixelRect(x: 1, y: 1, width: 2, height: 2),
    label: "target",
    viewportContext: context
  )
  #expect(ActionSurfacePresentation(displayedFrame: displayed, overlays: [], focus: matching).focus == matching)
  let stale = ActionSurfaceFocus(
    frameID: FrameID(),
    cameraConfigurationID: displayed.frame.cameraConfigurationID,
    region: matching.region,
    label: "stale",
    viewportContext: context
  )
  #expect(ActionSurfacePresentation(displayedFrame: displayed, overlays: [], focus: stale).focus == nil)
}

@Test("Viewport defaults full-frame, interpolates, and reaches the exact ROI")
func viewportZoomEndpointsAndInterpolation() {
  let context = ActionSurfaceViewportContext(
    source: .simulated,
    cameraConfigurationID: CameraConfigurationID(),
    targetAreaIdentity: UUID(),
    roiAuthorityToken: "roi-1",
    region: PixelRect(x: 300, y: 200, width: 40, height: 20)
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
  viewport.showExactROI()
  #expect(viewport.visibleRegion(frameWidth: 640, frameHeight: 480) == context.region)
}

@Test("Viewport survives frame and phase churn and resets for every ROI authority change")
func viewportStableContextPersistence() {
  let region = PixelRect(x: 20, y: 30, width: 40, height: 50)
  let context = ActionSurfaceViewportContext(
    source: .simulated,
    cameraConfigurationID: CameraConfigurationID(),
    targetAreaIdentity: UUID(),
    roiAuthorityToken: "roi-1",
    region: region
  )
  var viewport = ActionSurfaceViewportState()
  viewport.synchronize(with: context)
  viewport.zoom = 0.72
  let firstFocus = ActionSurfaceFocus(
    frameID: FrameID(),
    cameraConfigurationID: context.cameraConfigurationID,
    region: region,
    label: "capture phase",
    viewportContext: context
  )
  let laterFocus = ActionSurfaceFocus(
    frameID: FrameID(),
    cameraConfigurationID: context.cameraConfigurationID,
    region: region,
    label: "observation phase",
    viewportContext: context
  )
  #expect(firstFocus.frameID != laterFocus.frameID)
  #expect(firstFocus.label != laterFocus.label)
  #expect(firstFocus.viewportContext == laterFocus.viewportContext)
  viewport.synchronize(with: laterFocus.viewportContext)
  #expect(viewport.zoom == 0.72)

  let changedContexts = [
    ActionSurfaceViewportContext(
      source: .live(CameraDeviceID(rawValue: "camera-b")),
      cameraConfigurationID: context.cameraConfigurationID,
      targetAreaIdentity: context.targetAreaIdentity,
      roiAuthorityToken: context.roiAuthorityToken,
      region: region
    ),
    ActionSurfaceViewportContext(
      source: context.source,
      cameraConfigurationID: CameraConfigurationID(),
      targetAreaIdentity: context.targetAreaIdentity,
      roiAuthorityToken: context.roiAuthorityToken,
      region: region
    ),
    ActionSurfaceViewportContext(
      source: context.source,
      cameraConfigurationID: context.cameraConfigurationID,
      targetAreaIdentity: UUID(),
      roiAuthorityToken: context.roiAuthorityToken,
      region: region
    ),
    ActionSurfaceViewportContext(
      source: context.source,
      cameraConfigurationID: context.cameraConfigurationID,
      targetAreaIdentity: context.targetAreaIdentity,
      roiAuthorityToken: "roi-2",
      region: region
    ),
    ActionSurfaceViewportContext(
      source: context.source,
      cameraConfigurationID: context.cameraConfigurationID,
      targetAreaIdentity: context.targetAreaIdentity,
      roiAuthorityToken: context.roiAuthorityToken,
      region: PixelRect(x: 21, y: 30, width: 40, height: 50)
    ),
  ]
  for changedContext in changedContexts {
    var changedViewport = ActionSurfaceViewportState()
    changedViewport.synchronize(with: context)
    changedViewport.zoom = 0.72
    changedViewport.synchronize(with: changedContext)
    #expect(changedViewport.zoom == 0)
  }
}

@Test("Viewport and ROI outline use true frame intersections")
func viewportClipsROIAtEveryFrameEdge() {
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
    viewport.synchronize(with: ActionSurfaceViewportContext(
      source: .simulated,
      cameraConfigurationID: CameraConfigurationID(),
      targetAreaIdentity: UUID(),
      roiAuthorityToken: "roi-edge",
      region: region
    ))
    viewport.showExactROI()
    #expect(viewport.visibleRegion(frameWidth: 100, frameHeight: 100) == expected)
  }
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
      kind: .currentContact,
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
  #expect(grayPixels == [
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
