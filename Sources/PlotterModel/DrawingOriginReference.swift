import CryptoKit
import Foundation

/// Frozen authoring identity only. This grants no placement or motion authority.
public struct DrawingOriginReference: Codable, Hashable, Sendable {
  public let libraryID: UUID
  public let captureID: UUID
  public let resultID: String
  public let resultRecordSHA256: String
  public let programHash: Digest

  public init(libraryID: UUID, captureID: UUID, resultID: String,
    resultRecordSHA256: String, programHash: Digest) {
    self.libraryID = libraryID; self.captureID = captureID; self.resultID = resultID
    self.resultRecordSHA256 = resultRecordSHA256; self.programHash = programHash
  }

  public var identityHash: Digest {
    let basis = "drawing-origin-v1\n" + libraryID.uuidString.lowercased() + "\n"
      + captureID.uuidString.lowercased() + "\n" + String(resultID.utf8.count)
      + ":" + resultID + "\n" + resultRecordSHA256
    // SHA256 always contains precisely Digest.byteCount bytes.
    return try! Digest(bytes: Array(SHA256.hash(data: Data(basis.utf8))))
  }

  public var drawingID: String { "transferred-" + identityHash.description }

  public func validate() throws {
    guard !resultID.isEmpty, resultID.utf8.count <= 1024,
      resultRecordSHA256.utf8.count == 64,
      resultRecordSHA256.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) })
    else { throw PlotterModelError.invalidValue("Invalid frozen drawing origin") }
  }
}
