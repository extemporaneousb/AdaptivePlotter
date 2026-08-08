import PlotterModel
import PlotterRuntime

public struct PaperPixelPoint: Sendable, Equatable {
  public let x: Int
  public let y: Int

  public init(x: Int, y: Int) {
    self.x = x
    self.y = y
  }
}

public struct SimulatedPaperStroke: Sendable, Equatable {
  public let start: PaperPixelPoint
  public let end: PaperPixelPoint
  public let green: UInt8

  public init(start: PaperPixelPoint, end: PaperPixelPoint, green: UInt8 = 180) {
    self.start = start
    self.end = end
    self.green = green
  }
}

public struct SimulatedIsolatedInkFrames: Sendable, Equatable {
  public let cleanReference: StampedFrame
  public let anchoredBaseline: StampedFrame
  public let postLine: StampedFrame

  public init(
    cleanReference: StampedFrame,
    anchoredBaseline: StampedFrame,
    postLine: StampedFrame
  ) {
    self.cleanReference = cleanReference
    self.anchoredBaseline = anchoredBaseline
    self.postLine = postLine
  }
}

/// An independent paper renderer. Controller replies never enter this API, so
/// controller completion cannot manufacture synthetic ink success.
public struct PaperSceneSimulator: Sendable {
  public let width: Int
  public let height: Int

  public init(width: Int, height: Int) {
    self.width = width
    self.height = height
  }

  public func render(
    strokes: [SimulatedPaperStroke],
    sequence: UInt64,
    captureNanoseconds: UInt64,
    cameraConfigurationID: CameraConfigurationID
  ) throws -> StampedFrame {
    var source = try SimulatedFrameSource(
      width: width,
      height: height,
      fieldToCamera: AffineTransform2<FieldSpace, CameraPixelSpace>(
        m11: 1, m12: 0, m21: 0, m22: 1, tx: 0, ty: 0),
      cameraConfigurationID: cameraConfigurationID,
      initialSequence: sequence
    )
    let cameraStrokes = try strokes.map {
      SimulatedCameraStroke(
        start: try Point2<CameraPixelSpace>(x: Double($0.start.x), y: Double($0.start.y)),
        end: try Point2<CameraPixelSpace>(x: Double($0.end.x), y: Double($0.end.y)),
        green: $0.green
      )
    }
    return try source.render(strokes: cameraStrokes, captureNanoseconds: captureNanoseconds).frame
  }

  public func renderModelMismatch(
    scene: SimulatedModelMismatchScene,
    fieldToCamera: AffineTransform2<FieldSpace, CameraPixelSpace>,
    sequence: UInt64,
    captureNanoseconds: UInt64,
    cameraConfigurationID: CameraConfigurationID
  ) throws -> SimulatedOverlaySceneContent {
    var source = try SimulatedFrameSource(
      width: width,
      height: height,
      fieldToCamera: fieldToCamera,
      cameraConfigurationID: cameraConfigurationID,
      initialSequence: sequence
    )
    return try source.renderModelMismatch(
      scene,
      captureNanoseconds: captureNanoseconds
    )
  }

  /// Produces the three exact views consumed by paired isolated-ink analysis.
  /// The anchor is a small stationary cross; the post frame adds only the line.
  public func renderIsolatedInkSequence(
    preexistingInk: [SimulatedPaperStroke],
    anchor: PaperPixelPoint,
    lineEnd: PaperPixelPoint,
    cleanSequence: UInt64,
    cleanCaptureNanoseconds: UInt64,
    cameraConfigurationID: CameraConfigurationID
  ) throws -> SimulatedIsolatedInkFrames {
    let anchorStrokes = [
      SimulatedPaperStroke(
        start: PaperPixelPoint(x: anchor.x - 1, y: anchor.y),
        end: PaperPixelPoint(x: anchor.x + 1, y: anchor.y)
      ),
      SimulatedPaperStroke(
        start: PaperPixelPoint(x: anchor.x, y: anchor.y - 1),
        end: PaperPixelPoint(x: anchor.x, y: anchor.y + 1)
      ),
    ]
    let clean = try render(
      strokes: preexistingInk,
      sequence: cleanSequence,
      captureNanoseconds: cleanCaptureNanoseconds,
      cameraConfigurationID: cameraConfigurationID
    )
    let anchored = try render(
      strokes: preexistingInk + anchorStrokes,
      sequence: cleanSequence + 1,
      captureNanoseconds: cleanCaptureNanoseconds + 1,
      cameraConfigurationID: cameraConfigurationID
    )
    let post = try render(
      strokes: preexistingInk + anchorStrokes + [
        SimulatedPaperStroke(start: anchor, end: lineEnd)
      ],
      sequence: cleanSequence + 2,
      captureNanoseconds: cleanCaptureNanoseconds + 2,
      cameraConfigurationID: cameraConfigurationID
    )
    return SimulatedIsolatedInkFrames(
      cleanReference: clean,
      anchoredBaseline: anchored,
      postLine: post
    )
  }
}
