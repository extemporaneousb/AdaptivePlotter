import CryptoKit
import Foundation
import PlotterModel

/// Pure verification shared by the raw store and inspection-only transfer readers.
/// Constructing a frame grants no capture, machine, or execution authority.
public enum DrawingRunMediaValidation {
  public static func frame(reference: DrawingRunMediaReference, bytes: Data) throws -> StampedFrame {
    try reference.validate()
    let hash = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    guard bytes.count == reference.byteCount, hash == reference.frame.frameSHA256 else {
      throw DrawingRunEvidenceStoreError.invalidMedia("Missing or corrupt original frame " + reference.frame.frameSHA256)
    }
    let frame = reference.frame
    return try StampedFrame(id: frame.frameID, sequence: reference.sequence,
      captureNanoseconds: frame.captureNanoseconds, cameraConfigurationID: frame.cameraConfigurationID,
      width: frame.width, height: frame.height, rowBytes: frame.rowBytes,
      pixelFormat: frame.pixelFormat, bytes: OwnedFrameBytes(copying: bytes))
  }
}
