import CoreGraphics
import Foundation
import PlotterEpisodeModel
import PlotterEpisodeRuntime
import PlotterModel
import PlotterRuntime
import Testing
@testable import PlotterApp

@Suite("Video interaction ownership")
struct ActionSurfaceInteractionTests {
  @Test("Cap anchor submits with an editable drawing visible and retains its off-center geometry")
  func capSelectionOutranksDrawing() throws {
    let surface = try presentation(purpose: .penCapAppearance)
    let region = try AxisAlignedBounds<CameraPixelSpace>(minX: 12, minY: 12, maxX: 40, maxY: 42)
    let result = ActionSurfacePointStaging.stage(presentation: surface,
      viewport: ActionSurfaceViewportState(), at: CGPoint(x: 18, y: 24),
      viewSize: CGSize(width: 64, height: 64), referenceRegion: region)
    guard case .staged(let submission) = result else {
      Issue.record("Editable drawing swallowed the anchor: \(result)"); return
    }
    #expect(surface.drawingStudioCanvas?.placement.placementIsEnabled == true)
    #expect(submission.point == (try Point2<CameraPixelSpace>(x: 18, y: 24)))
    #expect(submission.referenceRegion == region)
    #expect(surface.acceptsPendingPointSelection(submission))
    #expect(ActionSurfaceDragIntent.resolve(presentation: surface,
      drawsReference: true, movesDrawing: true) == .reference)
    #expect(ActionSurfaceDragIntent.resolve(presentation: surface,
      drawsReference: false, movesDrawing: true) == .pan)
  }

  @Test("Drawing movement is explicit and other exact point requests also outrank it")
  func explicitDrawingMode() throws {
    let normal = try presentation()
    #expect(ActionSurfaceDragIntent.resolve(presentation: normal,
      drawsReference: true, movesDrawing: false) == .pan)
    #expect(ActionSurfaceDragIntent.resolve(presentation: normal,
      drawsReference: false, movesDrawing: true) == .drawing)
    let contact = try presentation(purpose: .toolContact)
    #expect(ActionSurfaceDragIntent.resolve(presentation: contact,
      drawsReference: true, movesDrawing: true) == .pan)
    guard case .staged(let submission) = ActionSurfacePointStaging.stage(
      presentation: contact, viewport: ActionSurfaceViewportState(),
      at: CGPoint(x: 18, y: 24), viewSize: CGSize(width: 64, height: 64),
      referenceRegion: nil) else { Issue.record("Contact click was swallowed"); return }
    #expect(submission.referenceRegion == nil)
    let locked = try presentation(locked: true)
    #expect(ActionSurfaceDragIntent.resolve(presentation: locked,
      drawsReference: false, movesDrawing: false) == .locked)
  }

  @Test("Panning between the rectangle and cap click preserves the camera-space anchor")
  func panBeforeAnchor() throws {
    let surface = try presentation(purpose: .penCapAppearance)
    let frame = try #require(surface.displayedFrame)
    let region = try AxisAlignedBounds<CameraPixelSpace>(minX: 12, minY: 12, maxX: 40, maxY: 42)
    var viewport = ActionSurfaceViewportState()
    viewport.synchronize(with: ActionSurfaceViewportContext(source: frame.source,
      cameraConfigurationID: frame.frame.cameraConfigurationID,
      frameWidth: 64, frameHeight: 64, fittedRegion: PixelRect(x: 8, y: 8, width: 48, height: 48),
      preferredInitialZoom: 1, presentationRevisionToken: "frozen"))
    viewport.pan(by: CGSize(width: -12, height: -4), viewSize: CGSize(width: 192, height: 192),
      frameWidth: 64, frameHeight: 64)
    let transform = try #require(CameraPixelToViewTransform(frameWidth: 64, frameHeight: 64,
      viewWidth: 192, viewHeight: 192, focusRegion: viewport.visibleRegion(frameWidth: 64, frameHeight: 64)))
    let anchor = try Point2<CameraPixelSpace>(x: 18, y: 24)
    guard case .staged(let submission) = ActionSurfacePointStaging.stage(presentation: surface,
      viewport: viewport, at: transform.point(anchor), viewSize: CGSize(width: 192, height: 192),
      referenceRegion: region) else { Issue.record("Pan prevented the anchor click"); return }
    #expect(submission.point == anchor)
    #expect(submission.referenceRegion == region)
    #expect(surface.acceptsPendingPointSelection(submission))
  }

  @Test("Missing rectangle, outside anchor, and letterbox clicks have explicit remedies")
  func clickRefusals() throws {
    let surface = try presentation(purpose: .penCapAppearance)
    let region = try AxisAlignedBounds<CameraPixelSpace>(minX: 12, minY: 12, maxX: 40, maxY: 42)
    for (point, size, reference) in [
      (CGPoint(x: 18, y: 24), CGSize(width: 64, height: 64), nil),
      (CGPoint(x: 40, y: 24), CGSize(width: 64, height: 64), region),
      (CGPoint(x: 0, y: 24), CGSize(width: 128, height: 64), region),
    ] {
      guard case .refused(let remedy) = ActionSurfacePointStaging.stage(
        presentation: surface, viewport: ActionSurfaceViewportState(), at: point,
        viewSize: size, referenceRegion: reference) else {
        Issue.record("Invalid selection had no feedback"); continue
      }
      #expect(!remedy.isEmpty)
    }
  }

  @Test("Live reference refusal remains attached to the frozen selection presentation")
  func runtimeFailurePresentation() throws {
    let surface = try presentation(purpose: .penCapAppearance,
      failure: "The rectangle has too little visual detail.")
    #expect(surface.resolvingAmbientPreviewFrame(surface.displayedFrame)
      .pointSelectionFailure == "The rectangle has too little visual detail.")
  }

  @Test("Sampled marker selects with one click and dragging only pans even with stale rectangle UI state")
  func sampledMarkerNeedsNoRectangle() throws {
    let surface = try presentation(purpose: .penCapAppearance, referenceMode: .sampledColorMarker)
    guard case .staged(let submission) = ActionSurfacePointStaging.stage(
      presentation: surface, viewport: ActionSurfaceViewportState(), at: CGPoint(x: 18, y: 24),
      viewSize: CGSize(width: 64, height: 64), referenceRegion: nil) else {
      Issue.record("Single marker click was refused"); return
    }
    #expect(submission.referenceRegion == nil)
    #expect(ActionSurfaceDragIntent.resolve(presentation: surface,
      drawsReference: true, movesDrawing: true) == .pan)
  }

  private func presentation(
    purpose: PlotterExactPointSelectionPurpose? = nil, locked: Bool = false, failure: String? = nil,
    referenceMode: PlotterTrackingReferenceMode? = nil
  ) throws -> ActionSurfacePresentation {
    let displayed = DisplayedFrame(source: .live(CameraDeviceID(rawValue: "selection-test")),
      frame: try StampedFrame(sequence: 1, captureNanoseconds: 1,
        cameraConfigurationID: CameraConfigurationID(), width: 64, height: 64,
        rowBytes: 256, pixelFormat: .bgra8,
        bytes: OwnedFrameBytes(Array(repeating: 64, count: 64 * 64 * 4))))
    let request = purpose.map {
      PlotterPointSelectionRequest(frame: exactPointSelectionFrame(displayed),
        sourceObservationID: PlotterObservationID(rawValue: UUID()),
        presentationTransformRevision: PlotterPresentationTransformRevision(),
        prompt: "Select the cap", purpose: $0, requiredPointCount: 1, referenceMode: referenceMode)
    }
    let draft = PlotterDrawingDraftSnapshot.initial(environment: .live,
      toolAssemblyRevision: ToolAssemblyRevision(),
      paper: PaperRevisionContext(instance: PaperInstanceRevision(), contactPlane: PaperContactPlaneRevision()))
    return ActionSurfacePresentation(displayedFrame: displayed, overlays: [],
      analysisRegionIsLocked: locked, pointSelectionRequest: request, pointSelectionFailure: failure,
      drawingStudioCanvas: DrawingStudioCanvasPresentation(draftProjection: draft.projection,
        placement: DrawingStudioPlacementPresentation(centerCameraPixel: nil, uniformScale: 1,
          allowedScale: 0.1...5, rotationDegrees: 0, placementIsEnabled: true), targetPreview: nil))
  }
}
