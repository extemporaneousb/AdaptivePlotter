import Foundation
import PlotterModel

/// Inspection-only terminal evidence envelope. Runtime semantic validation is
/// performed by PortraitLibrary; PortraitCore owns no execution/evidence store.
public struct PlotAttachment: Codable, Equatable, Sendable {
  public let schemaVersion: Int
  public let origin: DrawingOriginReference
  public let producerArchiveID: UUID
  public let runID: UUID
  public let recordID: UUID
  public let recordJSON: Data
  public let recordSHA256: String
  public let media: [DrawingPackageAsset]

  public init(origin: DrawingOriginReference, producerArchiveID: UUID, runID: UUID,
    recordID: UUID, recordJSON: Data, media: [DrawingPackageAsset]) throws {
    schemaVersion = 1; self.origin = origin; self.producerArchiveID = producerArchiveID
    self.runID = runID; self.recordID = recordID; self.recordJSON = recordJSON
    recordSHA256 = DrawingPackageCodec.sha256(recordJSON)
    self.media = media.sorted { $0.sha256 < $1.sha256 }
    try validate()
  }

  public var id: String {
    producerArchiveID.uuidString.lowercased() + ":" + runID.uuidString.lowercased()
  }

  public func validate() throws {
    guard schemaVersion == 1 else { throw DrawingTransferError.invalid("Unsupported plot attachment version.") }
    try origin.validate()
    guard recordJSON.count <= 64 * 1024 * 1024,
      DrawingPackageCodec.sha256(recordJSON) == recordSHA256,
      media.count <= DrawingTransferLimits.maximumOriginals,
      Set(media.map(\.sha256)).count == media.count,
      media.reduce(0, { $0 + $1.bytes.count }) <= DrawingTransferLimits.attachmentMediaBytes else {
      throw DrawingTransferError.invalid("Plot attachment hash, originals, or byte limits are invalid.")
    }
    try DrawingPackageCodec.validateJSON(recordJSON)
    for asset in media { try asset.validate(maximumBytes: DrawingTransferLimits.originalMediaBytes) }
  }
}

public enum PlotAttachmentCodec {
  public static func encode(_ attachment: PlotAttachment) throws -> Data {
    try attachment.validate()
    let bytes = try DrawingPackageCodec.encoder().encode(attachment)
    guard bytes.count <= DrawingTransferLimits.attachmentJSONBytes else {
      throw DrawingTransferError.limit("Plot attachment file exceeds its byte limit.")
    }
    return bytes
  }
  public static func decode(_ data: Data) throws -> PlotAttachment {
    guard data.count <= DrawingTransferLimits.attachmentJSONBytes else {
      throw DrawingTransferError.limit("Plot attachment file exceeds its byte limit.")
    }
    let value = try JSONDecoder().decode(PlotAttachment.self, from: data)
    try value.validate()
    return value
  }
}
