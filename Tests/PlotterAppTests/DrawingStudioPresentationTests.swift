import PlotterModel
import PlotterRuntime
import Testing

@testable import PlotterApp

@Suite("Drawing Studio presentation")
struct DrawingStudioPresentationTests {
  @Test("catalog selection and source parameters remain immutable presentation values")
  func catalogAndParameters() throws {
    let presentation = try studioPresentation(
      runState: .ready(detail: "Plan admitted."),
      editingIsEnabled: true
    )

    #expect(presentation.catalog.map(\.id) == [.square, .circle])
    #expect(presentation.selectedCatalogItem?.title == "Circle")
    #expect(presentation.sourceParameters.map(\.id.rawValue) == ["diameter", "segments"])
    #expect(presentation.sourceParameters.map(\.value.displayText) == ["24.00", "48"])
  }

  @Test("built-in catalog projects every deterministic Model source")
  func builtInCatalogProjection() {
    let catalog = DrawingStudioCatalogItemPresentation.builtInCatalog

    #expect(catalog.map(\.id) == DrawingCatalogEntryID.allCases)
    #expect(catalog.first { $0.id == .elephant }?.title == "Elephant")
    #expect(
      catalog.first { $0.id == .circle }?.detail
        .contains("deterministic curve tessellation") == true
    )
  }

  @Test("run and Stop controls preserve the exact typed owner capability")
  func executionControls() throws {
    let ready = try studioPresentation(
      runState: .ready(detail: "Plan admitted."),
      editingIsEnabled: true
    )
    #expect(ready.controls.map(\.action) == [.centerInDrawableRegion, .run])
    #expect(ready.controls.allSatisfy { $0.isEnabled })

    let capability = ContextualStopCapabilityID()
    let running = try studioPresentation(
      runState: .running(capabilityID: capability, detail: "Stroke 2 of 4.")
    )
    #expect(running.controls.map(\.action) == [.stop(capability)])
    #expect(running.controls.first?.role == .negative)
  }

  @Test("processing has no Stop or other accepted action")
  func processingControls() throws {
    let processing = try studioPresentation(
      runState: .processing(detail: "Observing the exact post-run frame."),
      editingIsEnabled: false
    )

    #expect(processing.runState.title == "Processing drawing evidence")
    #expect(processing.controls.isEmpty)
  }

  @Test("target preview is rendered only on its exact frame")
  func previewExactFrameBoundary() throws {
    let exact = try drawingPresentationTestFrame()
    let stale = try drawingPresentationTestFrame()
    let canvas = try studioCanvas(frame: exact)

    #expect(canvas.targetPreview(for: exact) != nil)
    #expect(canvas.targetPreview(for: stale) == nil)

    let exactSurface = ActionSurfacePresentation(
      displayedFrame: exact,
      overlays: [],
      drawingStudioCanvas: canvas
    )
    let staleSurface = ActionSurfacePresentation(
      displayedFrame: stale,
      overlays: [],
      drawingStudioCanvas: canvas
    )
    #expect(
      exactSurface.drawingStudioCanvas?.targetPreview(for: exact)?.programContentHash
        == "program-hash"
    )
    #expect(staleSurface.drawingStudioCanvas?.targetPreview(for: stale) == nil)
  }

  @Test("review state exposes explicit review exit and new-run actions")
  func reviewControls() throws {
    let available = try studioPresentation(
      runState: .reviewAvailable(runID: "run-7", detail: "Observed geometry is retained."),
      editingIsEnabled: false
    )
    let reviewing = try studioPresentation(
      runState: .reviewing(runID: "run-7", detail: "Exact post-run frame displayed."),
      editingIsEnabled: false
    )

    #expect(available.controls.map(\.action) == [.reviewRun, .newRun])
    #expect(reviewing.controls.map(\.action) == [.resumeLivePreview, .newRun])
    #expect(available.controls.allSatisfy { $0.isEnabled })
    #expect(reviewing.controls.allSatisfy { $0.isEnabled })
    #expect(!available.controls.map(\.action).contains(.run))
  }

  @Test("disabled editing also disables video placement and editing controls")
  func editingBoundary() throws {
    let presentation = try studioPresentation(
      runState: .ready(detail: "Plan admission is temporarily retained."),
      editingIsEnabled: false
    )

    #expect(!presentation.editingIsEnabled)
    #expect(!presentation.canvas.placement.placementIsEnabled)
    #expect(
      presentation.controls.first { $0.action == .centerInDrawableRegion }?.isEnabled == false
    )
    #expect(presentation.controls.first { $0.action == .run }?.isEnabled == false)
  }

  private func studioPresentation(
    runState: DrawingStudioRunState,
    editingIsEnabled: Bool = false
  ) throws -> DrawingStudioPresentation {
    let frame = try drawingPresentationTestFrame()
    return DrawingStudioPresentation(
      catalog: [
        DrawingStudioCatalogItemPresentation(
          id: .square,
          title: "Square",
          detail: "Four closed edges.",
          systemImage: "square"
        ),
        DrawingStudioCatalogItemPresentation(
          id: .circle,
          title: "Circle",
          detail: "A tessellated closed circle.",
          systemImage: "circle"
        ),
      ],
      selectedCatalogItemID: .circle,
      sourceParameters: [
        DrawingStudioParameterPresentation(
          id: DrawingStudioParameterID(rawValue: "diameter"),
          title: "Diameter",
          detail: "Nominal field-space diameter.",
          value: .scalar(24),
          control: .scalar(range: 1...100, step: 1, unit: "mm")
        ),
        DrawingStudioParameterPresentation(
          id: DrawingStudioParameterID(rawValue: "segments"),
          title: "Segments",
          detail: "Curve tessellation ceiling.",
          value: .integer(48),
          control: .integer(range: 8...128, step: 8, unit: "")
        ),
      ],
      canvas: try studioCanvas(frame: frame),
      editingIsEnabled: editingIsEnabled,
      runState: runState
    )
  }

  private func studioCanvas(frame: DisplayedFrame) throws -> DrawingStudioCanvasPresentation {
    let start = try Point2<CameraPixelSpace>(x: 100, y: 100)
    let end = try Point2<CameraPixelSpace>(x: 140, y: 140)
    return DrawingStudioCanvasPresentation(
      placement: DrawingStudioPlacementPresentation(
        centerCameraPixel: try Point2(x: 120, y: 120),
        uniformScale: 1,
        allowedScale: 0.1...5,
        rotationDegrees: 0,
        placementIsEnabled: true
      ),
      targetPreview: DrawingStudioTargetPreview(
        provenance: ExactFrameOverlayProvenance(frame),
        strokes: [try Polyline(points: [start, end])],
        bounds: try AxisAlignedBounds(minX: 100, minY: 100, maxX: 140, maxY: 140),
        programContentHash: "program-hash",
        executionPlanContentHash: "plan-hash",
        status: .ready
      )
    )
  }
}
