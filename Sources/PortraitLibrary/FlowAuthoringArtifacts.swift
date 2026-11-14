import Foundation
import PortraitCore
import PortraitArtists
import DrawingLibrary

/// Domain records use the common library owner. Generated artifacts live only in
/// this bounded authoring session until an explicit retention or feedback action.
final class FlowAuthoringArtifacts: @unchecked Sendable {
  let library: DrawingLibrary
  private var assets: [String: Data] = [:]
  private var published = Set<String>()
  package static let maximumCount = 128
  package static let maximumBytes = 256 * 1024 * 1024
  var count: Int { assets.count }
  private(set) var byteCount = 0
  func keepUnpublished(_ hashes: Set<String>) {
    var retainedBytes = 0
    assets = assets.filter { entry in
      guard hashes.contains(entry.key), !published.contains(entry.key) else { return false }
      retainedBytes += entry.value.count
      return true
    }
    byteCount = retainedBytes
  }

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
    if assets[digest] == nil { byteCount += bytes.count }
    assets[digest] = bytes
    return .init(sha256: digest, byteCount: bytes.count, mediaType: mediaType)
  }
  func isAvailable(_ blob: FlowPortfolioBlob) -> Bool { assets[blob.sha256] != nil || published.contains(blob.sha256) }
  func canRetain(_ values: [Data]) -> Bool {
    var additions: [String: Int] = [:]
    for bytes in values {
      let digest = ExchangeDigest.hash(bytes).description
      if assets[digest] == nil && !published.contains(digest) { additions[digest] = bytes.count }
    }
    return additions.count <= Self.maximumCount - assets.count
      && additions.values.reduce(0, +) <= Self.maximumBytes - byteCount
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
    for blob in blobs {
      published.insert(blob.sha256)
      if let removed = assets.removeValue(forKey: blob.sha256) { byteCount -= removed.count }
    }
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
