import Foundation
import PlotterModel

/// Original pixel buffer, addressed by its SHA256. All layout and source metadata
/// remain bound to the exact capture, even when equal pixels deduplicate on disk.
public struct DrawingRunMediaReference: Codable, Hashable, Sendable {
  public let source: FrameSourceIdentity
  public let frame: ExactFrameProvenance
  public let sequence: UInt64
  public let byteCount: Int
  /// Observed controller pose for a run-owned capture; nil for an unbound available frame.
  public let controllerPosition: MachinePosition?
  /// Monotonic acquisition boundary captured after controller settlement. Nil
  /// preserves legacy or available-frame evidence without a freshness claim.
  public let captureAfterNanoseconds: UInt64?
  public init(frame: StampedFrame, source: FrameSourceIdentity,
    controllerPosition: MachinePosition? = nil, captureAfterNanoseconds: UInt64? = nil) {
    self.source = source; self.frame = ExactFrameProvenance(frame: frame)
    sequence = frame.sequence; byteCount = frame.bytes.count
    self.controllerPosition = controllerPosition
    self.captureAfterNanoseconds = captureAfterNanoseconds
  }

  func validate() throws {
    if let captureAfterNanoseconds {
      guard controllerPosition != nil, frame.captureNanoseconds > captureAfterNanoseconds else {
        throw DrawingRunEvidenceError.invalidMediaReference
      }
    }
    let bpp = frame.pixelFormat.bytesPerPixel
    guard frame.frameSHA256.utf8.count == 64,
      frame.frameSHA256.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }),
      frame.width > 0, frame.height > 0, frame.width <= Int.max / bpp,
      frame.rowBytes >= frame.width * bpp, frame.rowBytes <= Int.max / frame.height,
      byteCount >= frame.rowBytes * frame.height else {
      throw DrawingRunEvidenceError.invalidMediaReference
    }
  }
}
