import Foundation
import PlotterModel

public struct SimulatedCameraStroke: Hashable, Sendable {
  public let start: Point2<CameraPixelSpace>
  public let end: Point2<CameraPixelSpace>
  public let red: UInt8
  public let green: UInt8
  public let blue: UInt8

  public init(
    start: Point2<CameraPixelSpace>,
    end: Point2<CameraPixelSpace>,
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

public enum SimulatedFrameSourceError: Error, Equatable, Sendable {
  case invalidDimensions
}

/// A deterministic production frame source for the same renderer and vision
/// path as a live camera. It has no machine-link dependency and cannot create a
/// controller or physical-motion outcome.
public struct SimulatedFrameSource: Sendable {
  public let width: Int
  public let height: Int
  public let cameraConfigurationID: CameraConfigurationID
  public let fieldToCamera: AffineTransform2<FieldSpace, CameraPixelSpace>
  public private(set) var sequence: UInt64
  private var lastTimestamp: UInt64

  public init(
    width: Int,
    height: Int,
    fieldToCamera: AffineTransform2<FieldSpace, CameraPixelSpace>,
    cameraConfigurationID: CameraConfigurationID = CameraConfigurationID(),
    initialSequence: UInt64 = 1
  ) throws {
    guard width > 0, height > 0 else { throw SimulatedFrameSourceError.invalidDimensions }
    self.width = width
    self.height = height
    self.fieldToCamera = fieldToCamera
    self.cameraConfigurationID = cameraConfigurationID
    sequence = initialSequence
    lastTimestamp = 0
  }

  public mutating func render(
    strokes: [SimulatedCameraStroke],
    captureNanoseconds: UInt64? = nil
  ) throws -> DisplayedFrame {
    let proposedTimestamp = captureNanoseconds ?? DispatchTime.now().uptimeNanoseconds
    let timestamp = max(proposedTimestamp, lastTimestamp &+ 1)
    var pixels = [UInt8](repeating: 255, count: width * height * 4)
    for stroke in strokes { draw(stroke, into: &pixels) }
    let frame = try StampedFrame(
      id: FrameID(rawValue: "simulated-\(cameraConfigurationID)-\(sequence)"),
      sequence: sequence,
      captureNanoseconds: timestamp,
      cameraConfigurationID: cameraConfigurationID,
      width: width,
      height: height,
      rowBytes: width * 4,
      pixelFormat: .bgra8,
      bytes: OwnedFrameBytes(pixels)
    )
    sequence &+= 1
    lastTimestamp = timestamp
    return DisplayedFrame(source: .simulated, frame: frame)
  }

  public func cameraPolyline(from fieldPolyline: Polyline<FieldSpace>) throws
    -> Polyline<CameraPixelSpace>
  {
    try fieldToCamera.applying(to: fieldPolyline)
  }

  private func draw(_ stroke: SimulatedCameraStroke, into pixels: inout [UInt8]) {
    var x = Int(stroke.start.x.rounded())
    var y = Int(stroke.start.y.rounded())
    let endX = Int(stroke.end.x.rounded())
    let endY = Int(stroke.end.y.rounded())
    let dx = abs(endX - x)
    let sx = x < endX ? 1 : -1
    let dy = -abs(endY - y)
    let sy = y < endY ? 1 : -1
    var error = dx + dy
    while true {
      if x >= 0, x < width, y >= 0, y < height {
        let offset = (y * width + x) * 4
        pixels[offset] = stroke.blue
        pixels[offset + 1] = stroke.green
        pixels[offset + 2] = stroke.red
        pixels[offset + 3] = 255
      }
      if x == endX, y == endY { break }
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
