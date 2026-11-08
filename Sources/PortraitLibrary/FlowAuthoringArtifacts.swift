import Foundation
import PortraitCore
import DrawingLibrary
import PortraitArtists

/// Domain records use the common library owner. Generated artifacts live only in
/// this bounded authoring session until an explicit retention or feedback action.
final class FlowAuthoringArtifacts: @unchecked Sendable {
  let library: DrawingLibrary
  private var assets: [String: Data] = [:]
  private var published = Set<String>()
  package static let maximumCount = 128
  package static let maximumBytes = 256 * 1024 * 1024
  var count: Int { assets.count }
  var byteCount: Int { assets.values.reduce(0) { $0 + $1.count } }
  func keepUnpublished(_ hashes: Set<String>) { assets = assets.filter { hashes.contains($0.key) && !published.contains($0.key) } }

  init(library: DrawingLibrary) { self.library = library }
  func retain(_ bytes: Data, mediaType: String) throws -> FlowPortfolioBlob {
    guard !bytes.isEmpty, bytes.count <= 128 * 1024 * 1024, !mediaType.isEmpty else {
      throw FlowPortfolioError.invalid("Authoring artifact is empty or exceeds its size limit.")
    }
    let digest = ExchangeDigest.hash(bytes).description
    guard !published.contains(digest) else {
      return .init(sha256: digest, byteCount: bytes.count, mediaType: mediaType)
    }
    guard assets[digest] != nil || (assets.count < Self.maximumCount && bytes.count <= Self.maximumBytes - byteCount) else {
      throw FlowPortfolioError.unavailable("The active drawing panel exceeds the temporary artifact memory budget.")
    }
    assets[digest] = bytes
    return .init(sha256: digest, byteCount: bytes.count, mediaType: mediaType)
  }
  func read(_ blob: FlowPortfolioBlob) async throws -> Data {
    let bytes: Data
    if let cached = assets[blob.sha256] { bytes = cached }
    else {
      guard published.contains(blob.sha256) else {
        throw FlowPortfolioError.unavailable("This temporary artifact expired without being retained.")
      }
      bytes = try await library.asset(ExchangeDigest(blob.sha256), maximumBytes: 128 * 1024 * 1024)
    }
    guard bytes.count == blob.byteCount, ExchangeDigest.hash(bytes).description == blob.sha256 else {
      throw FlowPortfolioError.invalid("Artifact length or digest differs from its exact reference.")
    }
    return bytes
  }
  func markPublished(_ blobs: [FlowPortfolioBlob]) {
    published.formUnion(blobs.map(\.sha256))
    for blob in blobs { assets.removeValue(forKey: blob.sha256) }
  }
  func closureAssets(_ blobs: [FlowPortfolioBlob]) async throws -> [DrawingLibraryClosureAsset] {
    var result: [DrawingLibraryClosureAsset] = []
    for values in Dictionary(grouping: blobs, by: \.sha256).values where !published.contains(values[0].sha256) {
      guard assets[values[0].sha256] != nil else { continue }
      let blob = values[0], bytes = try await read(values[0])
      let descriptor: ExchangeAssetDescriptor
      if ["image/png", "image/jpeg"].contains(blob.mediaType) { descriptor = try PortraitDrawingImages.sourceAsset(bytes).asset.descriptor }
      else { descriptor = .init(asset: try ExchangeAsset(bytes: bytes, mediaType: blob.mediaType, encoding: blob.mediaType == "application/json" ? "utf8-json" : "opaque")) }
      result.append(DrawingLibraryClosureAsset(descriptor: descriptor, bytes: bytes))
    }
    return result
  }
}
