import Foundation
import PortraitArtists
import PortraitCore

/// The live UI and opt-in real-output validation use one canonical package path.
enum PortraitStudioArtistPackageFactory {
  static func package(request: PortraitReviewGenerationRequest, producerLibraryID: UUID,
    result: SwiftSketchWorkerResult) throws -> DrawingPackage {
    try request.validate()
    guard result.requestID == request.id, result.status == .succeeded,
      let raw = result.rawOutputJSON, let derived = result.artistInputPNG,
      let preview = result.previewPNG else {
      throw SwiftSketchError.invalid("A complete successful worker result must match its frozen request.")
    }
    let material = request.material
    let program = try SwiftSketchConverter.program(raw: raw,
      fieldWidthMM: material.widthMM, fieldHeightMM: material.heightMM,
      nominalPenWidthMM: material.nominalLineWidthMM, sourceIdentifier: request.source.sha256)
    let record = try DrawingPackageCodec.encoder().encode(ResultRecord(requestID: request.id,
      raw: raw, provenance: result.provenanceJSON, response: result.responseJSON, conversion: request.conversionJSON))
    return try DrawingPackage(origin: .init(libraryID: producerLibraryID, captureID: request.captureID,
      resultID: "swiftsketch-" + request.id.uuidString.lowercased(),
      resultRecordSHA256: DrawingPackageCodec.sha256(record), programHash: program.contentHash),
      program: program, createdAt: request.createdAt, title: "SwiftSketch",
      resultRecordJSON: record, source: request.source,
      artistInput: try PortraitStudioArtistInput.imageAsset(derived), artist: request.artist,
      preview: try PortraitStudioArtistInput.imageAsset(preview))
  }

  static func assets(_ result: SwiftSketchWorkerResult) -> [PortraitReviewAsset] {
    let retained: [(String, Data?, String)] = [("worker-response", result.responseJSON, "application/json"),
      ("raw-cubics", result.rawOutputJSON, "application/json"),
      ("worker-provenance", result.provenanceJSON, "application/json"),
      ("artist-input", result.artistInputPNG, "image/png"),
      ("artist-preview", result.previewPNG, "image/png")]
    return retained.compactMap { role, bytes, type in
      guard let bytes else { return nil }
      return .init(role: role, asset: .init(mediaType: type, bytes: bytes))
    }
  }

  private struct ResultRecord: Codable {
    let requestID: UUID
    let raw: Data
    let provenance: Data?
    let response: Data
    let conversion: Data
  }
}
