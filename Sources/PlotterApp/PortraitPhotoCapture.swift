import Foundation
import PlotterModel
import PlotterRuntime

struct PortraitPhoto: Identifiable, Sendable {
  let id: UUID
  let data: Data
  let label: String
  let capturedAt: Date
  let frameID: FrameID?
  let captureNanoseconds: UInt64?
  // Retained solely for existing saved-program provenance, never a capture slot.
  let pose: PortraitPose
  var sourcePixelExtent: PortraitSourceCropExtent? = nil
  var captureSessionID: UUID = UUID()
  var selectionProvenance: PortraitCaptureSelectionProvenance? = nil
}

struct PortraitPhotoRetention: Sendable {
  var maximumCount = 24
  var maximumBytes = 32 * 1_024 * 1_024
}

/// The studio samples its own camera's latest delivered frame, independently of
/// the plotter preview and analysis cadence. Implementations must not publish it
/// to a different camera owner's preview or use it as physical drawing evidence.
protocol PortraitFrameAcquiring: Sendable {
  func latestFrame(newerThanNanoseconds: UInt64) async throws -> StampedFrame?
}

struct PortraitCameraFrameSource: PortraitFrameAcquiring {
  let camera: CameraCapture
  func latestFrame(newerThanNanoseconds: UInt64) async throws -> StampedFrame? {
    try await camera.materializeLatestFrame(
      newerThanNanoseconds: newerThanNanoseconds, policy: .returnOnly)?.frame
  }
}

protocol PortraitCaptureClock: Sendable {
  func now() async -> TimeInterval
  func sleep(seconds: TimeInterval) async throws
}

struct PortraitSystemCaptureClock: PortraitCaptureClock {
  private let origin = ContinuousClock.now
  func now() async -> TimeInterval {
    let elapsed = origin.duration(to: .now).components
    return Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18
  }
  func sleep(seconds: TimeInterval) async throws {
    try await Task.sleep(for: .seconds(max(0, seconds)))
  }
}

struct PortraitBurstSample: Sendable {
  let data: Data
  let frameID: FrameID?
  let captureNanoseconds: UInt64?
  let label: String
  var sourcePixelExtent: PortraitSourceCropExtent? = nil
  var selectionProvenance: PortraitCaptureSelectionProvenance? = nil
}

/// Bounds the temporary capture inputs until one source is selected. These
/// samples are never fused or exposed as separate gallery entries.
struct PortraitBurstBuffer: Sendable {
  let retention: PortraitPhotoRetention
  private(set) var samples: [PortraitBurstSample] = []
  private(set) var byteCount = 0

  mutating func append(_ sample: PortraitBurstSample) {
    guard retention.maximumCount > 0, sample.data.count <= retention.maximumBytes else { return }
    samples.append(sample)
    byteCount += sample.data.count
    while samples.count > retention.maximumCount || byteCount > retention.maximumBytes {
      let index = samples.count > 2 ? 1 : 0
      byteCount -= samples.remove(at: index).data.count
    }
  }
}
