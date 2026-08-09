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

@Test("Field geometry reaches a live surface only through an explicit registration")
func liveFieldOverlayUsesRegistration() throws {
  let cameraConfigurationID = CameraConfigurationID()
  let displayed = try testDisplayedFrame(configuration: cameraConfigurationID)
  let registration = try FieldRegistration.fit(
    id: FieldRegistrationID(),
    correspondences: [
      RegistrationCorrespondence(
        camera: try Point2(x: 0, y: 0),
        field: try Point2(x: 10, y: 20)
      ),
      RegistrationCorrespondence(
        camera: try Point2(x: 10, y: 0),
        field: try Point2(x: 20, y: 20)
      ),
      RegistrationCorrespondence(
        camera: try Point2(x: 0, y: 10),
        field: try Point2(x: 10, y: 30)
      ),
    ]
  )
  let fieldLine = try Polyline<FieldSpace>(points: [
    Point2(x: 10, y: 20),
    Point2(x: 20, y: 30),
  ])

  let overlay = try FieldOverlayProjection.overlay(
    fieldLine,
    on: displayed,
    using: CameraConfiguredFieldRegistration(
      registration: registration,
      cameraConfigurationID: cameraConfigurationID
    ),
    kind: .intendedPath,
    source: .planned,
    algorithmRevision: "registration-test"
  )

  guard case .polyline(let cameraLine) = overlay.geometry else {
    Issue.record("Expected camera-pixel polyline")
    return
  }
  #expect(abs(cameraLine.points[0].x) < 1e-9)
  #expect(abs(cameraLine.points[0].y) < 1e-9)
  #expect(abs(cameraLine.points[1].x - 10) < 1e-9)
  #expect(abs(cameraLine.points[1].y - 10) < 1e-9)
  #expect(overlay.matches(displayed))
}

@Test("Field overlay rejects a registration from another camera configuration")
func liveFieldOverlayRejectsConfigurationMismatch() throws {
  let registrationConfigurationID = CameraConfigurationID()
  let displayedConfigurationID = CameraConfigurationID()
  let displayed = try testDisplayedFrame(configuration: displayedConfigurationID)
  let registration = try FieldRegistration.fit(
    id: FieldRegistrationID(),
    correspondences: [
      RegistrationCorrespondence(
        camera: try Point2(x: 0, y: 0),
        field: try Point2(x: 0, y: 0)
      ),
      RegistrationCorrespondence(
        camera: try Point2(x: 10, y: 0),
        field: try Point2(x: 10, y: 0)
      ),
      RegistrationCorrespondence(
        camera: try Point2(x: 0, y: 10),
        field: try Point2(x: 0, y: 10)
      ),
    ]
  )
  let fieldLine = try Polyline<FieldSpace>(points: [
    Point2(x: 0, y: 0),
    Point2(x: 1, y: 1),
  ])

  #expect(
    throws: FieldOverlayProjectionError.cameraConfigurationMismatch(
      registration: registrationConfigurationID,
      displayedFrame: displayedConfigurationID
    )
  ) {
    try FieldOverlayProjection.overlay(
      fieldLine,
      on: displayed,
      using: CameraConfiguredFieldRegistration(
        registration: registration,
        cameraConfigurationID: registrationConfigurationID
      ),
      kind: .intendedPath,
      source: .planned,
      algorithmRevision: "registration-test"
    )
  }
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
