import Foundation
import PlotterEpisodeModel
import PlotterEpisodeRuntime
import PlotterModel
import PlotterRuntime
import Testing

@testable import PlotterApp

@Suite("Drawing Studio presentation")
struct DrawingStudioPresentationTests {
  @Test("catalog presentation derives from the deterministic Model catalog")
  func catalogProjection() throws {
    let presentation = try studioPresentation(
      runState: .ready(detail: "Plan admitted."),
      editingIsEnabled: true
    )

    #expect(presentation.catalog.map(\.id) == DrawingCatalogEntryID.allCases)
    #expect(presentation.selectedCatalogItem?.title == "Circle")
    #expect(
      presentation.catalog.first { $0.id == .circle }?.detail
        .contains("deterministic curve tessellation") == true
    )
    #expect(presentation.evidenceRole == .ordinaryDrawing)
  }

  @Test("run and Stop controls preserve the exact typed owner capability")
  func executionControls() throws {
    let ready = try studioPresentation(
      runState: .ready(detail: "Plan admitted."),
      editingIsEnabled: true
    )
    #expect(ready.controls.map(\.intent) == [.start])
    #expect(ready.controls.allSatisfy { $0.isEnabled })

    let capability = PlotterDrawingRunStopCapabilityID()
    let running = try studioPresentation(
      runState: .running(capabilityID: capability, detail: "Stroke 2 of 4.")
    )
    #expect(running.controls.map(\.intent) == [.stop(capability)])
    #expect(running.controls.first?.role == .negative)
  }

  @Test("processing has no Stop or other accepted action")
  func processingControls() throws {
    let presentation = try studioPresentation(
      runState: .processing(detail: "Observing the exact post-run frame."),
      editingIsEnabled: false
    )

    #expect(presentation.runState.title == "Processing drawing evidence")
    #expect(presentation.controls.isEmpty)
  }

  @Test("runtime-derived target values render only on their exact frame")
  func previewExactFrameBoundary() throws {
    let exact = try drawingStudioTestFrame(sequence: 1)
    let stale = try drawingStudioTestFrame(sequence: 2)
    let canvas = try studioCanvas(frame: exact)

    #expect(canvas.targetPreview(for: exact) != nil)
    #expect(canvas.targetPreview(for: stale) == nil)
    #expect(
      ActionSurfacePresentation(
        displayedFrame: exact,
        overlays: [],
        drawingStudioCanvas: canvas
      ).drawingStudioCanvas?.targetPreview(for: exact)?.programContentHash
        == "program-hash"
    )
  }

  @Test("review states expose only review exit and new-run actions")
  func reviewControls() throws {
    let availableRunID = RunID()
    let terminalRunID = RunID()
    let available = try studioPresentation(
      runState: .reviewAvailable(runID: availableRunID, detail: "Observed geometry retained.")
    )
    let reviewing = try studioPresentation(
      runState: .reviewing(runID: availableRunID, detail: "Exact post-run frame displayed.")
    )
    let terminal = try studioPresentation(
      runState: .terminal(runID: terminalRunID, detail: "No exact post-run frame.")
    )

    #expect(available.controls.map(\.intent) == [
      .pinReview(availableRunID), .beginNewRun(availableRunID),
    ])
    #expect(reviewing.controls.map(\.intent) == [
      .unpinReview(availableRunID), .beginNewRun(availableRunID),
    ])
    #expect(terminal.controls.map(\.intent) == [.beginNewRun(terminalRunID)])
    #expect(!available.controls.map(\.intent).contains(.start))
  }

  @Test("disabled editing disables placement and Run without changing values")
  func editingBoundary() throws {
    let presentation = try studioPresentation(
      runState: .ready(detail: "Plan admission retained."),
      editingIsEnabled: false
    )

    #expect(!presentation.editingIsEnabled)
    #expect(!presentation.canvas.placement.placementIsEnabled)
    #expect(presentation.controls == [
      DrawingStudioControl(
        intent: .start,
        title: "Run Drawing",
        systemImage: "play.fill",
        role: .affirmative,
        isEnabled: false
      )
    ])
  }

  private func studioPresentation(
    runState: DrawingStudioRunState,
    editingIsEnabled: Bool = false
  ) throws -> DrawingStudioPresentation {
    let frame = try drawingStudioTestFrame(sequence: 1)
    return DrawingStudioPresentation(
      catalog: DrawingProgramCatalog.entries.map {
        DrawingStudioCatalogItemPresentation(catalogEntry: $0)
      },
      selectedCatalogItemID: .circle,
      evidenceRole: .ordinaryDrawing,
      canvas: try studioCanvas(frame: frame),
      editingIsEnabled: editingIsEnabled,
      runProjection: PlotterDrawingRunProjectionReference(
        environment: .live,
        runRevision: PlotterDrawingRunRevision(rawValue: 0),
        planIdentity: nil
      ),
      runState: runState
    )
  }

  private func studioCanvas(frame: DisplayedFrame) throws -> DrawingStudioCanvasPresentation {
    let initial = PlotterDrawingDraftSnapshot.initial(
      environment: .live,
      toolAssemblyRevision: ToolAssemblyRevision(),
      paper: PaperRevisionContext(
        instance: PaperInstanceRevision(),
        contactPlane: PaperContactPlaneRevision()
      )
    )
    return DrawingStudioCanvasPresentation(
      draftProjection: initial.projection,
      placement: DrawingStudioPlacementPresentation(
        centerCameraPixel: try Point2(x: 120, y: 120),
        uniformScale: 1,
        allowedScale: 0.1...5,
        rotationDegrees: 0,
        placementIsEnabled: true
      ),
      targetPreview: DrawingStudioTargetPreview(
        provenance: ExactFrameOverlayProvenance(frame),
        strokes: [try Polyline(points: [
          Point2<CameraPixelSpace>(x: 100, y: 100),
          Point2<CameraPixelSpace>(x: 140, y: 140),
        ])],
        bounds: try AxisAlignedBounds<CameraPixelSpace>(
          minX: 100, minY: 100, maxX: 140, maxY: 140
        ),
        programContentHash: "program-hash",
        executionPlanContentHash: "plan-hash",
        status: .ready
      )
    )
  }
}

private func drawingStudioTestFrame(sequence: UInt64) throws -> DisplayedFrame {
  DisplayedFrame(
    source: .live(CameraDeviceID(rawValue: "drawing-studio-presentation-camera")),
    frame: try StampedFrame(
      sequence: sequence,
      captureNanoseconds: sequence * 10,
      cameraConfigurationID: CameraConfigurationID(
        UUID(uuidString: "00000000-0000-0000-0000-000000000011")!
      ),
      width: 2,
      height: 2,
      rowBytes: 8,
      pixelFormat: .bgra8,
      bytes: OwnedFrameBytes(Array(repeating: UInt8(sequence), count: 16))
    )
  )
}
