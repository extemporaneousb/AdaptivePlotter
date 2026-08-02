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
    var pixels = [UInt8](repeating: 255, count: width * height * 4)
    for stroke in strokes {
      draw(stroke, into: &pixels)
    }
    return try StampedFrame(
      sequence: sequence,
      captureNanoseconds: captureNanoseconds,
      cameraConfigurationID: cameraConfigurationID,
      width: width,
      height: height,
      rowBytes: width * 4,
      pixelFormat: .rgba8,
      bytes: OwnedFrameBytes(pixels)
    )
  }

  private func draw(_ stroke: SimulatedPaperStroke, into pixels: inout [UInt8]) {
    var x = stroke.start.x
    var y = stroke.start.y
    let dx = abs(stroke.end.x - stroke.start.x)
    let sx = stroke.start.x < stroke.end.x ? 1 : -1
    let dy = -abs(stroke.end.y - stroke.start.y)
    let sy = stroke.start.y < stroke.end.y ? 1 : -1
    var error = dx + dy
    while true {
      if x >= 0, x < width, y >= 0, y < height {
        let offset = (y * width + x) * 4
        pixels[offset] = 20
        pixels[offset + 1] = stroke.green
        pixels[offset + 2] = 30
        pixels[offset + 3] = 255
      }
      if x == stroke.end.x, y == stroke.end.y { break }
      let doubled = 2 * error
      if doubled >= dy {
        error += dy
        x += sx
      }
      if doubled <= dx {
        error += dx
        y += sy
      }
    }
  }
}
