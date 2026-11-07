import PlotterModel
import PlotterRuntime
import PortraitArtists

/// Acquisition stays with the host camera owner; authoring receives return-only frames.
package struct PortraitCameraFrameSource: PortraitFrameAcquiring {
  package let camera: CameraCapture
  package func latestFrame(newerThanNanoseconds: UInt64) async throws -> StampedFrame? {
    try await camera.materializeLatestFrame(
      newerThanNanoseconds: newerThanNanoseconds, policy: .returnOnly)?.frame
  }
  package func latestCaptureNanoseconds() async throws -> UInt64? {
    await camera.latestCaptureNanoseconds()
  }
  package init(camera: CameraCapture) { self.camera = camera }
}
