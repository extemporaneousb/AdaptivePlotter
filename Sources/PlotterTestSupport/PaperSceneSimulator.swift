import Foundation
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
  public let red: UInt8
  public let green: UInt8
  public let blue: UInt8

  public init(
    start: PaperPixelPoint,
    end: PaperPixelPoint,
    red: UInt8 = 0,
    green: UInt8 = 0,
    blue: UInt8 = 0
  ) {
    self.start = start
    self.end = end
    self.red = red
    self.green = green
    self.blue = blue
  }
}

public struct SimulatedTargetAndLineFrames: Sendable, Equatable {
  public let preTargetClearViewBaseline: StampedFrame
  public let targetPresentBaseline: StampedFrame
  public let postLine: StampedFrame

  public init(
    preTargetClearViewBaseline: StampedFrame,
    targetPresentBaseline: StampedFrame,
    postLine: StampedFrame
  ) {
    self.preTargetClearViewBaseline = preTargetClearViewBaseline
    self.targetPresentBaseline = targetPresentBaseline
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
        red: $0.red,
        green: $0.green,
        blue: $0.blue
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

  /// Produces the same-pose blank baseline, the accepted closed visibility
  /// target, and the trial-local target-present frame with one added line.
  public func renderVisibilityTargetAndLineSequence(
    preexistingInk: [SimulatedPaperStroke],
    targetCenter: PaperPixelPoint,
    targetRadiusPixels: Int = 4,
    lineStart: PaperPixelPoint,
    lineEnd: PaperPixelPoint,
    baselineSequence: UInt64,
    baselineCaptureNanoseconds: UInt64,
    cameraConfigurationID: CameraConfigurationID
  ) throws -> SimulatedTargetAndLineFrames {
    precondition(targetRadiusPixels > 0)
    let vertices = (0..<8).map { index in
      let angle = Double(index) * .pi / 4
      return PaperPixelPoint(
        x: targetCenter.x + Int((Double(targetRadiusPixels) * cos(angle)).rounded()),
        y: targetCenter.y + Int((Double(targetRadiusPixels) * sin(angle)).rounded())
      )
    }
    let targetStrokes = (0..<8).map { index in
      SimulatedPaperStroke(start: vertices[index], end: vertices[(index + 1) % 8])
    }
    let baseline = try render(
      strokes: preexistingInk,
      sequence: baselineSequence,
      captureNanoseconds: baselineCaptureNanoseconds,
      cameraConfigurationID: cameraConfigurationID
    )
    let targetPresent = try render(
      strokes: preexistingInk + targetStrokes,
      sequence: baselineSequence + 1,
      captureNanoseconds: baselineCaptureNanoseconds + 1,
      cameraConfigurationID: cameraConfigurationID
    )
    let post = try render(
      strokes: preexistingInk + targetStrokes + [
        SimulatedPaperStroke(start: lineStart, end: lineEnd)
      ],
      sequence: baselineSequence + 2,
      captureNanoseconds: baselineCaptureNanoseconds + 2,
      cameraConfigurationID: cameraConfigurationID
    )
    return SimulatedTargetAndLineFrames(
      preTargetClearViewBaseline: baseline,
      targetPresentBaseline: targetPresent,
      postLine: post
    )
  }
}
