import Foundation
import PortraitCore

package struct DrawingLibraryAssetReuseStatistics: Sendable {
  package var verificationPasses = 0
  package var hashedBytes: UInt64 = 0
  package var cacheHits = 0
  package var cachedProofCount = 0
}

extension DrawingLibrary {
  package static let maximumExistingAssetProofs = 128

  /// Existing immutable objects can be referenced by a domain record without
  /// restaging their bytes. A DB length check and a sealed filesystem proof are
  /// required; the bounded cache retains fingerprints only, never asset Data.
  package func existingVerifiedAssets(_ descriptors: [ExchangeAssetDescriptor]) throws -> Set<ExchangeDigest> {
    guard descriptors.count <= 128 else { throw DrawingExchangeError.limit("Existing asset proof count") }
    var unique: [ExchangeDigest: ExchangeAssetDescriptor] = [:]
    for value in descriptors {
      if let old = unique[value.asset.object], old != value { throw DrawingExchangeError.malformed("Conflicting existing asset descriptors") }
      unique[value.asset.object] = value
    }
    var expectedBytes: UInt64 = 0
    for descriptor in unique.values {
      guard descriptor.asset.byteLength <= 256 * 1024 * 1024 - expectedBytes else { throw DrawingExchangeError.limit("Existing asset proof bytes") }
      expectedBytes += descriptor.asset.byteLength
    }
    guard let db = try commonReadDatabase(), try tableExists("dx_object", in: db) else { return [] }
    return try commonSnapshot(db) { db in
      var result = Set<ExchangeDigest>()
      for (digest, descriptor) in unique {
        guard let raw = try db.scalar("SELECT byte_length FROM dx_object WHERE digest=?", [digest.description]) else {
          existingAssetProofs.removeValue(forKey: digest); existingAssetRecency.removeAll { $0 == digest }; continue
        }
        guard let length = UInt64(raw), length == descriptor.asset.byteLength,
          length <= UInt64(DrawingExchangeLimits.maximumProgramBytes) else { throw DrawingLibraryError.corruptAsset(digest) }
        var hit = false
        if let proof = existingAssetProofs[digest] {
          do { try proof.revalidateSelected(); hit = true }
          catch { existingAssetProofs.removeValue(forKey: digest); existingAssetRecency.removeAll { $0 == digest } }
        }
        if hit { existingAssetDiagnostics.cacheHits += 1 }
        else {
          let path = "objects/sha256/" + digest.description
          let proof = try VerifiedExchangeFiles(catalogRoot: directoryURL,
            inventory: [.init(path: path, storagePath: path, digest: digest, byteLength: length)])
          try proof.verifyInventory()
          existingAssetDiagnostics.verificationPasses += 1
          existingAssetDiagnostics.hashedBytes += proof.statistics.hashedBytes
          existingAssetProofs[digest] = proof
        }
        existingAssetRecency.removeAll { $0 == digest }; existingAssetRecency.append(digest)
        while existingAssetRecency.count > Self.maximumExistingAssetProofs {
          existingAssetProofs.removeValue(forKey: existingAssetRecency.removeFirst())
        }
        result.insert(digest)
      }
      return result
    }
  }

  /// Creates a bounded selected resolver with virtual record paths mapped only
  /// to canonical CAS objects. Every expected length is checked against the DB;
  /// selected reads still establish/check their own hashes and sealed handles.
  package func assetFiles(_ inventory: [ExchangeCatalogFile], limits: ExchangeCarrierLimits) throws -> VerifiedExchangeFiles {
    guard inventory.count <= limits.maximumEntries,
      let db = try commonReadDatabase(), try tableExists("dx_object", in: db) else { throw DrawingLibraryError.invalidQuery }
    return try commonSnapshot(db) { db in
      var lengths: [ExchangeDigest: UInt64] = [:]
      for item in inventory {
        if let old = lengths[item.digest], old != item.byteLength { throw DrawingLibraryError.corruptAsset(item.digest) }
        lengths[item.digest] = item.byteLength
      }
      for (digest, length) in lengths {
        guard let raw = try db.scalar("SELECT byte_length FROM dx_object WHERE digest=?", [digest.description]),
          UInt64(raw) == length else { throw DrawingLibraryError.corruptAsset(digest) }
      }
      return try VerifiedExchangeFiles(catalogRoot: directoryURL, inventory: inventory.map {
        .init(path: $0.path, storagePath: "objects/sha256/" + $0.digest.description,
          digest: $0.digest, byteLength: $0.byteLength)
      }, limits: limits)
    }
  }

  package func assetReuseStatistics() -> DrawingLibraryAssetReuseStatistics {
    var value = existingAssetDiagnostics; value.cachedProofCount = existingAssetProofs.count; return value
  }
}
