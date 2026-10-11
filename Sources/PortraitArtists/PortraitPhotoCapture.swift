import Foundation
import PlotterModel
import PlotterRuntime

package struct PortraitPhoto: Identifiable, Codable, Equatable, Sendable {
  package let id: UUID
  package let data: Data
  package let label: String
  package let capturedAt: Date
  package let frameID: FrameID?
  package let captureNanoseconds: UInt64?
  // Retained solely for existing saved-program provenance, never a capture slot.
  package let pose: PortraitPose
  package var sourcePixelExtent: PortraitSourceCropExtent? = nil
  package var captureSessionID: UUID = UUID()
  package var selectionProvenance: PortraitCaptureSelectionProvenance? = nil

  package init(
    id: UUID,
    data: Data,
    label: String,
    capturedAt: Date,
    frameID: FrameID? = nil,
    captureNanoseconds: UInt64? = nil,
    pose: PortraitPose,
    sourcePixelExtent: PortraitSourceCropExtent? = nil,
    captureSessionID: UUID = UUID(),
    selectionProvenance: PortraitCaptureSelectionProvenance? = nil
  ) {
    self.id = id
    self.data = data
    self.label = label
    self.capturedAt = capturedAt
    self.frameID = frameID
    self.captureNanoseconds = captureNanoseconds
    self.pose = pose
    self.sourcePixelExtent = sourcePixelExtent
    self.captureSessionID = captureSessionID
    self.selectionProvenance = selectionProvenance
  }
}

package struct PortraitPhotoRetention: Sendable {
  package init(maximumCount: Int = 24, maximumBytes: Int = 32 * 1_024 * 1_024) {
    self.maximumCount = maximumCount
    self.maximumBytes = maximumBytes
  }

  package var maximumCount = 24
  package var maximumBytes = 32 * 1_024 * 1_024
}

/// The studio samples its own camera's latest delivered frame, independently of
/// the plotter preview and analysis cadence. Implementations must not publish it
/// to a different camera owner's preview or use it as physical drawing evidence.
package protocol PortraitFrameAcquiring: Sendable {
  func latestFrame(newerThanNanoseconds: UInt64) async throws -> StampedFrame?
}

package struct PortraitCameraFrameSource: PortraitFrameAcquiring {
  package let camera: CameraCapture
  package func latestFrame(newerThanNanoseconds: UInt64) async throws -> StampedFrame? {
    try await camera.materializeLatestFrame(
      newerThanNanoseconds: newerThanNanoseconds, policy: .returnOnly)?.frame
  }

  package init(camera: CameraCapture) {
    self.camera = camera
  }
}

package protocol PortraitCaptureClock: Sendable {
  func now() async -> TimeInterval
  func sleep(seconds: TimeInterval) async throws
}

package struct PortraitSystemCaptureClock: PortraitCaptureClock {
  package init() {}

  private let origin = ContinuousClock.now
  package func now() async -> TimeInterval {
    let elapsed = origin.duration(to: .now).components
    return Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18
  }
  package func sleep(seconds: TimeInterval) async throws {
    try await Task.sleep(for: .seconds(max(0, seconds)))
  }
}

package struct PortraitBurstSample: Sendable {
  package let data: Data
  package let frameID: FrameID?
  package let captureNanoseconds: UInt64?
  package let label: String
  package var sourcePixelExtent: PortraitSourceCropExtent? = nil
  package var selectionProvenance: PortraitCaptureSelectionProvenance? = nil

  package init(
    data: Data,
    frameID: FrameID? = nil,
    captureNanoseconds: UInt64? = nil,
    label: String,
    sourcePixelExtent: PortraitSourceCropExtent? = nil,
    selectionProvenance: PortraitCaptureSelectionProvenance? = nil
  ) {
    self.data = data
    self.frameID = frameID
    self.captureNanoseconds = captureNanoseconds
    self.label = label
    self.sourcePixelExtent = sourcePixelExtent
    self.selectionProvenance = selectionProvenance
  }
}

/// Bounds the temporary capture inputs until one source is selected. These
/// samples are never fused or exposed as separate gallery entries.
package struct PortraitBurstBuffer: Sendable {
  package let retention: PortraitPhotoRetention
  package private(set) var samples: [PortraitBurstSample] = []
  package private(set) var byteCount = 0

  package mutating func append(_ sample: PortraitBurstSample) {
    guard retention.maximumCount > 0, sample.data.count <= retention.maximumBytes else { return }
    samples.append(sample)
    byteCount += sample.data.count
    while samples.count > retention.maximumCount || byteCount > retention.maximumBytes {
      let index = samples.count > 2 ? 1 : 0
      byteCount -= samples.remove(at: index).data.count
    }
  }

  package init(retention: PortraitPhotoRetention, samples: [PortraitBurstSample] = [], byteCount: Int = 0) {
    self.retention = retention
    self.samples = samples
    self.byteCount = byteCount
  }
}
