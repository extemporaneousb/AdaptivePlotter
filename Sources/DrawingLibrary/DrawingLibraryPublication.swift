import Foundation
import PortraitCore

package struct DrawingLibraryPublishedSummary: Codable, Sendable {
  package let reference: DrawingRef
  package let programDigest: ExchangeDigest
  package let createdAt: Date
  package let strokeCount: Int
  package let pointCount: Int
  package let minX: Double
  package let minY: Double
  package let maxX: Double
  package let maxY: Double
  package init(_ frozen: FrozenDrawingRecord, createdAt: Date) {
    reference = frozen.reference; programDigest = ExchangeDigest(frozen.drawing.programDigest)
    let json = try? JSONSerialization.jsonObject(with: frozen.originalJSON) as? [String: Any]
    let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    let wireDate = (json?["createdAt"] as? String).flatMap { formatter.date(from: $0) ?? ISO8601DateFormatter().date(from: $0) }
    self.createdAt = wireDate ?? createdAt
    let summary = frozen.drawing.summary()
    strokeCount = summary.strokeCount; pointCount = summary.pointCount
    minX = summary.bounds.minX; minY = summary.bounds.minY; maxX = summary.bounds.maxX; maxY = summary.bounds.maxY
  }
}
/// Journaled typed final-transaction work; no SQL callback crosses this seam.
package struct DrawingLibraryPublicationAttachment: Codable, Sendable {
  package let libraryUUID: UUID
  package let intent: UUID
  package let requestDigest: ExchangeDigest
  package let summary: DrawingLibraryPublishedSummary?
}

extension LibraryExchangeCatalog {
  package func retentionIntent(_ id: UUID, requestDigest: ExchangeDigest) throws -> DrawingRef? {
    guard let row = try database.rows("SELECT issuer,revision,digest,request_digest FROM dx_retention_intent WHERE id=?", [id.uuidString.lowercased()]).first else { return nil }
    guard let storedRequest = row[3] else { throw DrawingLibraryError.invalidIdentity }
    let expected = try ExchangeDigest(storedRequest)
    guard expected == requestDigest else { throw DrawingLibraryError.retentionIntentConflict(id, expected: expected, actual: requestDigest) }
    guard let issuer = row[0].flatMap(UUID.init(uuidString:)), let revision = row[1].flatMap(UUID.init(uuidString:)), let digest = row[2] else { throw DrawingLibraryError.invalidIdentity }
    return .init(issuer: issuer, revision: revision, digest: try ExchangeDigest(digest))
  }
  package func retainMetadata(_ metadata: LibraryExchangeMetadata, intent: UUID, requestDigest: ExchangeDigest) throws {
    guard case .drawing(let ref) = metadata.reference else { throw DrawingLibraryError.invalidIdentity }
    try database.transaction {
      _ = try lookup(metadata.reference)
      if let prior = try retentionIntent(intent, requestDigest: requestDigest), prior != ref { throw DrawingLibraryError.staleSelection }
      try writeMetadata(metadata)
      try database.execute("INSERT OR IGNORE INTO dx_retention_intent(id,issuer,revision,digest,request_digest) VALUES(?,?,?,?,?)", [intent.uuidString.lowercased(), ref.issuer.uuidString.lowercased(), ref.revision.uuidString.lowercased(), ref.digest.description, requestDigest.description])
      try database.bumpRevision()
    }
  }
  /// Recovered COMMIT evidence must include every immutable attachment row.
  /// Mutable titles and retention reasons are deliberately outside this check.
  package func verifyAttachment(_ attachment: DrawingLibraryPublicationAttachment) throws {
    guard let identity = try database.scalar("SELECT value FROM state WHERE key='library_uuid'"),
      UUID(uuidString: identity) == attachment.libraryUUID, let summary = attachment.summary else {
      throw LibraryExchangeCatalogError.invalidPublication("Frozen publication library identity or summary is missing")
    }
    let ref = summary.reference
    guard try retentionIntent(attachment.intent, requestDigest: attachment.requestDigest) == ref else {
      throw LibraryExchangeCatalogError.invalidPublication("Frozen retention intent is missing or divergent")
    }
    let values: [String?] = [ref.issuer.uuidString.lowercased(), ref.revision.uuidString.lowercased(),
      ref.digest.description, summary.programDigest.description, String(summary.createdAt.timeIntervalSince1970),
      String(summary.strokeCount), String(summary.pointCount), String(summary.minX), String(summary.minY),
      String(summary.maxX), String(summary.maxY)]
    // Compare numeric SQLite values to the exact journal values in SQLite itself;
    // sqlite3_column_text intentionally rounds REAL values for display.
    guard try database.scalar("SELECT COUNT(*) FROM dx_drawing_summary WHERE namespace=? AND identity=? AND digest=? AND program_digest=? AND created_at=CAST(? AS REAL) AND stroke_count=CAST(? AS INTEGER) AND point_count=CAST(? AS INTEGER) AND min_x=CAST(? AS REAL) AND min_y=CAST(? AS REAL) AND max_x=CAST(? AS REAL) AND max_y=CAST(? AS REAL)", values) == "1" else {
      throw LibraryExchangeCatalogError.invalidPublication("Frozen drawing summary is missing or divergent")
    }
  }

  package func apply(_ attachment: DrawingLibraryPublicationAttachment) throws {
    guard attachment.summary != nil else { throw LibraryExchangeCatalogError.invalidPublication("Publication attachment lacks its exact drawing summary") }
    if let existing = try database.scalar("SELECT value FROM state WHERE key='library_uuid'") {
      guard UUID(uuidString: existing) == attachment.libraryUUID else { throw DrawingLibraryError.invalidIdentity }
    } else {
      try database.setState("library_uuid", attachment.libraryUUID.uuidString.lowercased())

    }
    if let summary = attachment.summary {
      let ref = summary.reference
      if let prior = try retentionIntent(attachment.intent, requestDigest: attachment.requestDigest), prior != ref { throw DrawingLibraryError.staleSelection }
      try database.execute("INSERT OR IGNORE INTO dx_retention_intent(id,issuer,revision,digest,request_digest) VALUES(?,?,?,?,?)", [attachment.intent.uuidString.lowercased(), ref.issuer.uuidString.lowercased(), ref.revision.uuidString.lowercased(), ref.digest.description, attachment.requestDigest.description])
      try database.execute("INSERT OR IGNORE INTO dx_drawing_summary(namespace,identity,digest,program_digest,created_at,stroke_count,point_count,min_x,min_y,max_x,max_y) VALUES(?,?,?,?,?,?,?,?,?,?,?)", [ref.issuer.uuidString.lowercased(), ref.revision.uuidString.lowercased(), ref.digest.description, summary.programDigest.description, String(summary.createdAt.timeIntervalSince1970), String(summary.strokeCount), String(summary.pointCount), String(summary.minX), String(summary.minY), String(summary.maxX), String(summary.maxY)])
    }
  }
}
