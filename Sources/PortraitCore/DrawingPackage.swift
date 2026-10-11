import CryptoKit
import Foundation
import PlotterModel

public enum DrawingTransferError: Error, LocalizedError, Equatable, Sendable {
  case invalid(String), limit(String), conflict(String), unavailable(String)
  public var errorDescription: String? {
    switch self {
    case .invalid(let message), .limit(let message), .conflict(let message), .unavailable(let message): message
    }
  }
}

public enum DrawingTransferLimits {
  public static let drawingJSONBytes = 128 * 1024 * 1024
  public static let drawingEmbeddedBytes = 64 * 1024 * 1024
  public static let sourceBytes = 32 * 1024 * 1024
  public static let inputBytes = 16 * 1024 * 1024
  public static let previewBytes = 8 * 1024 * 1024
  public static let maximumStrokes = 10_000
  public static let maximumPoints = 250_000
  public static let maximumImageDimension = 8192
  public static let maximumImagePixels = 32 * 1024 * 1024
  public static let attachmentJSONBytes = 384 * 1024 * 1024
  public static let attachmentMediaBytes = 256 * 1024 * 1024
  public static let originalMediaBytes = 64 * 1024 * 1024
  public static let maximumOriginals = 128
}

public struct DrawingPackageAsset: Codable, Equatable, Sendable {
  public let mediaType: String
  public let sha256: String
  public let bytes: Data
  public let pixelWidth: Int?
  public let pixelHeight: Int?

  public init(mediaType: String, bytes: Data, pixelWidth: Int? = nil, pixelHeight: Int? = nil) {
    self.mediaType = mediaType; self.bytes = bytes
    sha256 = DrawingPackageCodec.sha256(bytes)
    self.pixelWidth = pixelWidth; self.pixelHeight = pixelHeight
  }

  public func validate(maximumBytes: Int, requireImage: Bool = false) throws {
    guard !bytes.isEmpty, bytes.count <= maximumBytes else {
      throw DrawingTransferError.limit("Transfer asset is empty or exceeds its byte limit.")
    }
    guard !mediaType.isEmpty, mediaType.utf8.count <= 128,
      DrawingPackageCodec.sha256(bytes) == sha256 else {
      throw DrawingTransferError.invalid("Transfer asset hash or media type is invalid.")
    }
    if pixelWidth != nil || pixelHeight != nil {
      guard let width = pixelWidth, let height = pixelHeight, width > 0, height > 0,
        width <= DrawingTransferLimits.maximumImageDimension,
        height <= DrawingTransferLimits.maximumImageDimension,
        width <= DrawingTransferLimits.maximumImagePixels / height else {
        throw DrawingTransferError.limit("Transfer image dimensions exceed the supported limit.")
      }
    }
    if requireImage {
      guard mediaType == "image/png" || mediaType == "image/jpeg",
        pixelWidth != nil, pixelHeight != nil else {
        throw DrawingTransferError.invalid("Transfer image must declare a supported encoding and dimensions.")
      }
    }
  }
}

public struct DrawingPackageArtist: Codable, Equatable, Sendable {
  public let identifier: String
  public let revision: String
  public let settingsJSON: Data
  public init(identifier: String, revision: String, settingsJSON: Data) {
    self.identifier = identifier; self.revision = revision; self.settingsJSON = settingsJSON
  }
}

/// An immutable authored result. All original input and result bytes are embedded;
/// this format contains no filesystem paths and no executable artist code.
public struct DrawingPackage: Codable, Equatable, Sendable {
  public let schemaVersion: Int
  public let origin: DrawingOriginReference
  public let program: DrawingProgram
  public let createdAt: Date
  public let title: String
  public let resultRecordJSON: Data
  public let source: DrawingPackageAsset
  public let artistInput: DrawingPackageAsset
  public let artist: DrawingPackageArtist
  public let preview: DrawingPackageAsset
  public let legacyCandidateJSON: Data?

  public init(origin: DrawingOriginReference, program: DrawingProgram, createdAt: Date,
    title: String, resultRecordJSON: Data, source: DrawingPackageAsset,
    artistInput: DrawingPackageAsset, artist: DrawingPackageArtist,
    preview: DrawingPackageAsset, legacyCandidateJSON: Data? = nil) throws {
    schemaVersion = 1; self.origin = origin; self.program = program; self.createdAt = createdAt
    self.title = title; self.resultRecordJSON = resultRecordJSON; self.source = source
    self.artistInput = artistInput; self.artist = artist; self.preview = preview
    self.legacyCandidateJSON = legacyCandidateJSON
    try validate()
  }

  public func validate() throws {
    guard schemaVersion == 1 else { throw DrawingTransferError.invalid("Unsupported drawing package version.") }
    try origin.validate()
    // Version one is the portrait authoring bridge. Requiring the existing
    // source kind preserves the Draft owner's source-provenance admission gate.
    guard program.source.kind == "portrait", program.contentHash == origin.programHash,
      DrawingPackageCodec.sha256(resultRecordJSON) == origin.resultRecordSHA256,
      createdAt.timeIntervalSinceReferenceDate.isFinite,
      !title.isEmpty, title.utf8.count <= 4096,
      !artist.identifier.isEmpty, artist.identifier.utf8.count <= 256,
      !artist.revision.isEmpty, artist.revision.utf8.count <= 256 else {
      throw DrawingTransferError.invalid("Drawing package identity or authoring metadata is invalid.")
    }
    guard program.strokes.count <= DrawingTransferLimits.maximumStrokes,
      program.strokes.reduce(0, { $0 + $1.path.points.count }) <= DrawingTransferLimits.maximumPoints else {
      throw DrawingTransferError.limit("Drawing package exceeds the stroke or point limit.")
    }
    let sizes = [source.bytes.count, artistInput.bytes.count, preview.bytes.count,
      resultRecordJSON.count, legacyCandidateJSON?.count ?? 0, artist.settingsJSON.count]
    guard sizes.reduce(0, +) <= DrawingTransferLimits.drawingEmbeddedBytes,
      artist.settingsJSON.count <= 1024 * 1024 else {
      throw DrawingTransferError.limit("Drawing package exceeds the embedded byte limit.")
    }
    try DrawingPackageCodec.validateJSON(resultRecordJSON)
    try DrawingPackageCodec.validateJSON(artist.settingsJSON)
    if let legacyCandidateJSON {
      guard legacyCandidateJSON == resultRecordJSON else {
        throw DrawingTransferError.invalid("Legacy result bytes differ from the frozen result record.")
      }
    }
    try source.validate(maximumBytes: DrawingTransferLimits.sourceBytes, requireImage: true)
    try artistInput.validate(maximumBytes: DrawingTransferLimits.inputBytes)
    try preview.validate(maximumBytes: DrawingTransferLimits.previewBytes, requireImage: true)
  }
}

public enum DrawingPackageCodec {
  public static func sha256(_ bytes: Data) -> String {
    SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
  }
  public static func encoder() -> JSONEncoder {
    let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    return encoder
  }
  static func validateJSON(_ data: Data) throws {
    guard !data.isEmpty, (try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])) != nil
    else { throw DrawingTransferError.invalid("Frozen transfer metadata is not valid JSON.") }
  }
  public static func encode(_ package: DrawingPackage) throws -> Data {
    try package.validate()
    let bytes = try encoder().encode(package)
    guard bytes.count <= DrawingTransferLimits.drawingJSONBytes else {
      throw DrawingTransferError.limit("Drawing package file exceeds its byte limit.")
    }
    return bytes
  }
  public static func decode(_ data: Data) throws -> DrawingPackage {
    guard data.count <= DrawingTransferLimits.drawingJSONBytes else {
      throw DrawingTransferError.limit("Drawing package file exceeds its byte limit.")
    }
    let package = try JSONDecoder().decode(DrawingPackage.self, from: data)
    try package.validate()
    return package
  }
}
