import PlotterModel
import PlotterRuntime

func drawingPresentationTestFrame(
  source: FrameSourceIdentity = .live(CameraDeviceID(rawValue: "drawing-presentation-camera")),
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
