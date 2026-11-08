import Foundation
import PortraitCore

/// A field-intent patch: clearing a value is different from leaving it alone.
public enum DrawingLibraryPhotoTextChange: Codable, Sendable {
  case unchanged
  case set(String?)
}
public struct DrawingLibraryPhotoMetadata: Codable, Equatable, Sendable {
  public var title: String?
  public var subjectID: String?
  public var sessionID: String?
  public var excluded: Bool
  public init(title: String? = nil, subjectID: String? = nil, sessionID: String? = nil, excluded: Bool = false) {
    self.title = title; self.subjectID = subjectID; self.sessionID = sessionID; self.excluded = excluded
  }
}
public struct DrawingLibraryPhotoMetadataPatch: Codable, Sendable {
  public let title: DrawingLibraryPhotoTextChange
  public let subjectID: DrawingLibraryPhotoTextChange
  public let sessionID: DrawingLibraryPhotoTextChange
  public let excluded: Bool?
  public init(title: DrawingLibraryPhotoTextChange = .unchanged, subjectID: DrawingLibraryPhotoTextChange = .unchanged,
    sessionID: DrawingLibraryPhotoTextChange = .unchanged, excluded: Bool? = nil) {
    self.title = title; self.subjectID = subjectID; self.sessionID = sessionID; self.excluded = excluded
  }
}
public struct DrawingLibraryPhotoMetadataUpdate: Codable, Sendable {
  public let reference: PhotoRef
  public let patch: DrawingLibraryPhotoMetadataPatch
  public init(reference: PhotoRef, patch: DrawingLibraryPhotoMetadataPatch) { self.reference = reference; self.patch = patch }
}
public struct DrawingLibraryPhotoEntry: Sendable {
  public let reference: PhotoRef
  /// Nil means the record's date vocabulary is opaque, not an explicit unknown date.
  public let acquired: DrawingImageDatedFact?
  public let imported: DrawingImageDatedFact?
  public let sortDate: Date?
  public let unsupportedReasons: [String]
  public let metadata: DrawingLibraryPhotoMetadata
}
public struct DrawingLibraryPhotoCursor: Sendable {
  let generation: DrawingLibraryGeneration
  let sortDate: Double?
  let namespace: String
  let identity: String
}
public struct DrawingLibraryPhotoPage: Sendable {
  public let entries: [DrawingLibraryPhotoEntry]
  public let next: DrawingLibraryPhotoCursor?
}
public struct DrawingLibraryInputEntry: Sendable {
  public let reference: ImageInputRef
  public let photo: PhotoRef
}
public struct DrawingLibraryInputCursor: Sendable {
  let generation: DrawingLibraryGeneration
  let photo: PhotoRef
  let namespace: String
  let identity: String
}
public struct DrawingLibraryInputPage: Sendable {
  public let entries: [DrawingLibraryInputEntry]
  public let next: DrawingLibraryInputCursor?
}
public struct DrawingLibraryRetentionState: Sendable {
  public let reference: DrawingRef
  public let reasons: [String]
  public let tombstoned: Bool
}

package struct DrawingLibrarySourceSummary: Codable, Equatable, Sendable {
  let reference: LibraryExchangeReference
  let knownContext: Bool
  let acquired: DrawingImageDatedFact?
  let imported: DrawingImageDatedFact?
  let sortDate: Double?
  let photo: PhotoRef?
  let unsupportedReasons: [String]
}
package struct DrawingLibraryRetentionMutation: Codable, Sendable {
  let reference: DrawingRef
  let reason: String?
  let retained: Bool?
  let restore: Bool
}

extension DrawingLibrary {
  public func photo(_ ref: PhotoRef) throws -> FrozenPhotoRecord {
    guard let db = try commonReadDatabase() else { throw DrawingLibraryError.unavailable("Photo is not present") }
    return try commonSnapshot(db) {
      try assertSourceReference(.photo(ref), database: db)
      for candidate in try publicationCandidates(.photo(ref), database: db) {
        let files = try publicationFiles(candidate, database: db)
        do { return try DrawingImageRecords.admitPhoto(ref, files: files) }
        catch DrawingExchangeError.unsupportedProfile { continue }
      }
      throw DrawingLibraryError.unsupportedFeature("No supported Photo publication context")
    }
  }
  public func input(_ ref: ImageInputRef) throws -> FrozenImageInputRecord {
    guard let db = try commonReadDatabase() else { throw DrawingLibraryError.unavailable("Input is not present") }
    return try commonSnapshot(db) {
      try assertSourceReference(.input(ref), database: db)
      for candidate in try publicationCandidates(.input(ref), database: db) {
        let files = try publicationFiles(candidate, database: db)
        do { return try DrawingImageRecords.admitInput(ref, files: files) }
        catch DrawingExchangeError.unsupportedProfile { continue }
      }
      throw DrawingLibraryError.unsupportedFeature("No supported Input publication context")
    }
  }
  package func assertSourceReference(_ ref: LibraryExchangeReference, database db: DrawingLibraryDatabase) throws {
    guard let raw = try db.scalar("SELECT digest FROM dx_record WHERE kind=? AND namespace=? AND identity=?", ref.key.map(Optional.some)) else {
      throw DrawingLibraryError.unavailable("Exact source is not present")
    }
    guard raw == ref.digest.description else { throw DrawingExchangeError.digestMismatch("Source reference") }
  }
  public func photoMetadata(_ ref: PhotoRef) throws -> DrawingLibraryPhotoMetadata {
    guard let db = try commonReadDatabase() else { throw DrawingLibraryError.unavailable("Photo is not present") }
    return try commonSnapshot(db) {
      try assertSourceReference(.photo(ref), database: db)
      return try sourceMetadata(ref, database: db)
    }
  }
  package func sourceMetadata(_ ref: PhotoRef, database db: DrawingLibraryDatabase) throws -> DrawingLibraryPhotoMetadata {
    guard let raw = try db.scalar("SELECT payload FROM dx_photo_metadata WHERE namespace=? AND identity=? AND digest=?", [LibraryExchangeReference.photo(ref).key[1], LibraryExchangeReference.photo(ref).key[2], ref.digest.description]) else { return .init() }
    return try db.decode(DrawingLibraryPhotoMetadata.self, raw)
  }
  public func updatePhotoMetadata(_ ref: PhotoRef, patch: DrawingLibraryPhotoMetadataPatch, intent: DrawingLibraryCommitIntent = .init()) throws {
    try commitRecords([], intent: intent, photoMetadata: [.init(reference: ref, patch: patch)])
  }
  public func photoMetadataRevision() throws -> Int64 {
    guard let db = try commonReadDatabase() else { return 0 }
    return try commonSnapshot(db) { Int64(try db.scalar("SELECT value FROM state WHERE key='photo_metadata_revision'") ?? "0") ?? 0 }
  }
  /// One bounded metadata read for the domain's live projection; no asset loads.
  public func photoMetadata(_ refs: [PhotoRef]) throws -> [PhotoRef: DrawingLibraryPhotoMetadata] {
    guard refs.count <= 10_000 else { throw DrawingLibraryError.invalidQuery }
    guard let db = try commonReadDatabase() else {
      guard refs.isEmpty else { throw DrawingLibraryError.unavailable("Exact Photo metadata is not present") }
      return [:]
    }
    return try commonSnapshot(db) {
      var result: [PhotoRef: DrawingLibraryPhotoMetadata] = [:]
      let wanted = Set(refs)
      let ordered = Array(wanted)
      for start in stride(from: 0, to: ordered.count, by: 200) {
        let chunk = ordered[start..<min(start + 200, ordered.count)]
        let predicate = Array(repeating: "(?,?)", count: chunk.count).joined(separator: ",")
        let arguments: [String?] = chunk.flatMap { [$0.issuer.uuidString.lowercased(), $0.revision.uuidString.lowercased()] }
        let rows = try db.rows("SELECT r.namespace,r.identity,r.digest,m.payload FROM dx_record r LEFT JOIN dx_photo_metadata m ON m.namespace=r.namespace AND m.identity=r.identity AND m.digest=r.digest WHERE r.kind='photo' AND (r.namespace,r.identity) IN (" + predicate + ")", arguments)
        var found = Set<PhotoRef>()
        for row in rows {
          guard let issuer = row[0].flatMap(UUID.init(uuidString:)), let revision = row[1].flatMap(UUID.init(uuidString:)), let digest = row[2] else { throw DrawingLibraryError.invalidIdentity }
          let ref = PhotoRef(issuer: issuer, revision: revision, digest: try ExchangeDigest(digest))
          guard wanted.contains(ref), !chunk.contains(where: { $0.issuer == issuer && $0.revision == revision && $0.digest != ref.digest }) else { throw DrawingExchangeError.digestMismatch("Photo metadata reference") }
          found.insert(ref)
          result[ref] = try row[3].map { try db.decode(DrawingLibraryPhotoMetadata.self, $0) } ?? .init()
        }
        guard found == Set(chunk) else { throw DrawingLibraryError.unavailable("Exact Photo metadata is not present") }
      }
      return result
    }
  }
  public func retention(_ ref: DrawingRef) throws -> DrawingLibraryRetentionState {
    guard let db = try commonReadDatabase() else { throw DrawingLibraryError.missing(ref) }
    return try commonSnapshot(db) {
      try assertSourceReference(.drawing(ref), database: db)
      let value = try preparedMetadata(ref, database: db) ?? .init(reference: .drawing(ref))
      return .init(reference: ref, reasons: value.retentionReasons, tombstoned: value.tombstoned)
    }
  }
  public func setRetentionReason(_ ref: DrawingRef, reason: String, retained: Bool, intent: DrawingLibraryCommitIntent = .init()) throws {
    guard !reason.isEmpty, reason.utf8.count <= 4096 else { throw DrawingLibraryError.invalidQuery }
    try mutateRetention(.init(reference: ref, reason: reason, retained: retained, restore: false), intent: intent)
  }
  public func restore(_ ref: DrawingRef, intent: DrawingLibraryCommitIntent = .init()) throws {
    try mutateRetention(.init(reference: ref, reason: nil, retained: nil, restore: true), intent: intent)
  }
  private func mutateRetention(_ mutation: DrawingLibraryRetentionMutation, intent: DrawingLibraryCommitIntent) throws {
    let catalog = try commonCatalog(); defer { refreshOwnership() }
    let batch = DrawingLibraryRecordBatch(records: [], removing: [], drawingRetention: [mutation])
    let request = try domainRequest(batch, assets: [])
    if try catalog.domainReceipt(intent.id, request: request) != nil { return }
    let prepared = try packageWithAssets(nil, assets: [], publicationID: intent.id)
    defer { try? FileManager.default.removeItem(at: prepared.temporaryRoot) }
    _ = try catalog.publish(prepared.package, domainCommit: .init(intent: intent.id, request: request, batch: batch, retained: []))
  }
}

extension LibraryExchangeCatalog {
  package func validatePhotoPatch(_ patch: DrawingLibraryPhotoMetadataPatch) throws {
    for (field, limit) in [(patch.title, 1024), (patch.subjectID, 256), (patch.sessionID, 256)] {
      if case .set(let value) = field, let value, value.utf8.count > limit { throw DrawingLibraryError.invalidQuery }
    }
  }
  package func applyPhotoMetadata(_ update: DrawingLibraryPhotoMetadataUpdate) throws {
    try validatePhotoPatch(update.patch)
    _ = try lookup(.photo(update.reference))
    let ref = update.reference, key = LibraryExchangeReference.photo(ref).key
    var value = try database.scalar("SELECT payload FROM dx_photo_metadata WHERE namespace=? AND identity=? AND digest=?", [key[1], key[2], ref.digest.description]).map { try database.decode(DrawingLibraryPhotoMetadata.self, $0) } ?? .init()
    func normalized(_ text: String?) -> String? {
      guard let text else { return nil }
      let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
      return value.isEmpty ? nil : value
    }
    if case .set(let text) = update.patch.title { value.title = normalized(text) }
    if case .set(let text) = update.patch.subjectID { value.subjectID = normalized(text) }
    if case .set(let text) = update.patch.sessionID { value.sessionID = normalized(text) }
    if let excluded = update.patch.excluded { value.excluded = excluded }
    try database.execute("INSERT INTO dx_photo_metadata(namespace,identity,digest,payload) VALUES(?,?,?,?) ON CONFLICT(namespace,identity) DO UPDATE SET payload=excluded.payload", [key[1], key[2], ref.digest.description, try database.encode(value)])
    let revision = Int64(try database.scalar("SELECT value FROM state WHERE key='photo_metadata_revision'") ?? "0") ?? 0
    try database.setState("photo_metadata_revision", String(revision + 1))
  }
  package func applyRetentionMutation(_ mutation: DrawingLibraryRetentionMutation) throws {
    _ = try lookup(.drawing(mutation.reference))
    var value = try metadata(.drawing(mutation.reference)) ?? .init(reference: .drawing(mutation.reference))
    if mutation.restore { value.tombstoned = false }
    if let reason = mutation.reason, let retained = mutation.retained {
      if retained, !value.retentionReasons.contains(reason) { value.retentionReasons.append(reason) }
      if !retained { value.retentionReasons.removeAll { $0 == reason } }
    }
    try writeMetadata(value)
  }
}

private func sourceDateFact(_ json: [String: Any], _ key: String) throws -> DrawingImageDatedFact? {
  guard let object = json[key] as? [String: Any], let provenance = object["provenance"] as? String else { return nil }
  switch object["state"] as? String {
  case "unknown": return .unknown(provenance: provenance)
  case "known":
    let data = try JSONSerialization.data(withJSONObject: object["time"] as Any)
    return .known(try JSONDecoder().decode(ExchangeTimestamp.self, from: data), provenance: provenance)
  default: return nil
  }
}
private func sourceWallDate(_ fact: DrawingImageDatedFact?) -> Date? {
  guard let fact, case .known(let timestamp, _) = fact, let wall = timestamp.wallTime else { return nil }
  let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
  return formatter.date(from: wall) ?? ISO8601DateFormatter().date(from: wall)
}
extension LibraryExchangeCatalog {
  package func sourceSummaries(_ package: ValidatedExchangePackage, references: [LibraryExchangeReference]) throws -> [DrawingLibrarySourceSummary] {
    var result: [DrawingLibrarySourceSummary] = []
    for ref in references {
      let path: String, profile: String
      switch ref {
      case .photo(let value):
        path = "data/photos/" + value.issuer.uuidString.lowercased() + "/" + value.revision.uuidString.lowercased() + "/photo.json"
        profile = "adaptiveplotter.photo/1"
      case .input(let value):
        path = "data/inputs/" + value.issuer.uuidString.lowercased() + "/" + value.revision.uuidString.lowercased() + "/input.json"
        profile = "adaptiveplotter.image-input/1"
      default: continue
      }
      let bytes = try package.files.record(at: path)
      guard ExchangeDigest.hash(bytes) == ref.digest else { throw DrawingLibraryError.invalidIdentity }
      let json = try ExchangeJSON.validate(bytes)
      let recognized = json["profile"] as? String == profile
      let supportedKind = ["drawing", "result", "feedback"].contains(package.index.known?.kind ?? "")
      let known = recognized && supportedKind && package.index.known?.requiredFeatures.isEmpty == true && (json["requiredFeatures"] as? [String])?.isEmpty == true
      var acquired: DrawingImageDatedFact?, imported: DrawingImageDatedFact?, photo: PhotoRef?
      if case .photo = ref, known {
        acquired = try sourceDateFact(json, "acquired"); imported = try sourceDateFact(json, "imported")
      }
      if case .input = ref, recognized, let raw = json["photo"] {
        photo = try JSONDecoder().decode(PhotoRef.self, from: JSONSerialization.data(withJSONObject: raw))
      }
      result.append(.init(reference: ref, knownContext: known, acquired: acquired, imported: imported,
        sortDate: (sourceWallDate(acquired) ?? sourceWallDate(imported))?.timeIntervalSince1970, photo: photo,
        unsupportedReasons: known ? [] : ["Unsupported source or publication requirements"]))
    }
    return result
  }
  package func applySourceSummary(_ value: DrawingLibrarySourceSummary) throws {
    let key = value.reference.key
    if let existing = try database.scalar("SELECT payload FROM dx_source_summary WHERE kind=? AND namespace=? AND identity=?", key.map(Optional.some)) {
      let prior = try database.decode(DrawingLibrarySourceSummary.self, existing)
      guard prior.reference == value.reference else { throw DrawingLibraryError.invalidIdentity }
      if prior.knownContext || !value.knownContext {
        if prior.knownContext == value.knownContext, prior != value { throw DrawingLibraryError.invalidIdentity }
        return
      }
    }
    try database.execute("INSERT INTO dx_source_summary(kind,namespace,identity,digest,payload,known_date,chronology,photo_namespace,photo_identity,photo_digest) VALUES(?,?,?,?,?,?,?,?,?,?) ON CONFLICT(kind,namespace,identity) DO UPDATE SET payload=excluded.payload,known_date=excluded.known_date,chronology=excluded.chronology,photo_namespace=excluded.photo_namespace,photo_identity=excluded.photo_identity,photo_digest=excluded.photo_digest", key.map(Optional.some) + [value.reference.digest.description, try database.encode(value), value.sortDate == nil ? "0" : "1", value.sortDate.map { String($0) }, value.photo?.issuer.uuidString.lowercased(), value.photo?.revision.uuidString.lowercased(), value.photo?.digest.description])
  }
  package func verifySourceSummary(_ value: DrawingLibrarySourceSummary) throws {
    guard let raw = try database.scalar("SELECT payload FROM dx_source_summary WHERE kind=? AND namespace=? AND identity=?", value.reference.key.map(Optional.some)) else { throw LibraryExchangeCatalogError.invalidPublication("Missing source projection") }
    let actual = try database.decode(DrawingLibrarySourceSummary.self, raw)
    guard actual.reference == value.reference, (!value.knownContext && actual.knownContext) || actual == value else { throw LibraryExchangeCatalogError.invalidPublication("Divergent source projection") }
    let values = actual.reference.key.map(Optional.some) + [actual.reference.digest.description, actual.sortDate == nil ? "0" : "1", actual.sortDate.map { String($0) }, actual.photo?.issuer.uuidString.lowercased(), actual.photo?.revision.uuidString.lowercased(), actual.photo?.digest.description]
    guard try database.scalar("SELECT COUNT(*) FROM dx_source_summary WHERE kind=? AND namespace=? AND identity=? AND digest=? AND known_date=CAST(? AS INTEGER) AND chronology IS CAST(? AS REAL) AND photo_namespace IS ? AND photo_identity IS ? AND photo_digest IS ?", values) == "1" else { throw LibraryExchangeCatalogError.invalidPublication("Divergent source query projection") }
  }
}

extension DrawingLibrary {
  public func photos(limit: Int = 50, after: DrawingLibraryPhotoCursor? = nil) throws -> DrawingLibraryPhotoPage {
    guard (1...500).contains(limit) else { throw DrawingLibraryError.invalidQuery }
    guard let db = try commonReadDatabase() else { return .init(entries: [], next: nil) }
    return try commonSnapshot(db) {
      let generation = try db.generation
      if let after, after.generation != generation { throw DrawingLibraryError.staleSelection }
      var predicate = "s.kind='photo'", values: [String?] = []
      if let after {
        if let date = after.sortDate {
          predicate += " AND (s.known_date=0 OR s.chronology<CAST(? AS REAL) OR (s.chronology=CAST(? AS REAL) AND (s.namespace,s.identity)>(?,?)))"
          values = [String(date), String(date), after.namespace, after.identity]
        } else { predicate += " AND s.known_date=0 AND (s.namespace,s.identity)>(?,?)"; values = [after.namespace, after.identity] }
      }
      let rows = try db.rows("SELECT s.payload,m.payload FROM dx_source_summary s LEFT JOIN dx_photo_metadata m ON m.namespace=s.namespace AND m.identity=s.identity AND m.digest=s.digest WHERE " + predicate + " ORDER BY s.known_date DESC,s.chronology DESC,s.namespace,s.identity LIMIT ?", values + [String(limit + 1)])
      let entries = try rows.prefix(limit).map { row -> DrawingLibraryPhotoEntry in
        let summary = try db.decode(DrawingLibrarySourceSummary.self, row[0])
        guard case .photo(let ref) = summary.reference else { throw DrawingLibraryError.invalidIdentity }
        return .init(reference: ref, acquired: summary.acquired, imported: summary.imported, sortDate: summary.sortDate.map(Date.init(timeIntervalSince1970:)), unsupportedReasons: summary.unsupportedReasons, metadata: try row[1].map { try db.decode(DrawingLibraryPhotoMetadata.self, $0) } ?? .init())
      }
      let next = rows.count > limit ? entries.last.map { DrawingLibraryPhotoCursor(generation: generation, sortDate: $0.sortDate?.timeIntervalSince1970, namespace: $0.reference.issuer.uuidString.lowercased(), identity: $0.reference.revision.uuidString.lowercased()) } : nil
      return .init(entries: entries, next: next)
    }
  }
  public func inputs(for photo: PhotoRef, limit: Int = 50, after: DrawingLibraryInputCursor? = nil) throws -> DrawingLibraryInputPage {
    guard (1...500).contains(limit) else { throw DrawingLibraryError.invalidQuery }
    if let after, after.photo != photo { throw DrawingLibraryError.invalidQuery }
    guard let db = try commonReadDatabase() else { return .init(entries: [], next: nil) }
    return try commonSnapshot(db) {
      let generation = try db.generation
      if let after, after.generation != generation { throw DrawingLibraryError.staleSelection }
      try assertSourceReference(.photo(photo), database: db)
      let rows = try db.rows("SELECT namespace,identity,digest FROM dx_source_summary WHERE kind='input' AND photo_namespace=? AND photo_identity=? AND photo_digest=? AND (namespace,identity)>(?,?) ORDER BY namespace,identity LIMIT ?", [photo.issuer.uuidString.lowercased(), photo.revision.uuidString.lowercased(), photo.digest.description, after?.namespace ?? "", after?.identity ?? "", String(limit + 1)])
      let entries = try rows.prefix(limit).map { row -> DrawingLibraryInputEntry in
        guard let issuer = row[0].flatMap(UUID.init(uuidString:)), let revision = row[1].flatMap(UUID.init(uuidString:)), let digest = row[2] else { throw DrawingLibraryError.invalidIdentity }
        return .init(reference: .init(issuer: issuer, revision: revision, digest: try ExchangeDigest(digest)), photo: photo)
      }
      let next = rows.count > limit ? entries.last.map { DrawingLibraryInputCursor(generation: generation, photo: photo, namespace: $0.reference.issuer.uuidString.lowercased(), identity: $0.reference.revision.uuidString.lowercased()) } : nil
      return .init(entries: entries, next: next)
    }
  }
}
