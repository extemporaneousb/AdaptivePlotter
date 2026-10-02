import CryptoKit
import Foundation
import PlotterRuntime

struct DrawingMaterialSnapshot: Codable, Sendable {
  var records: [DrawingMaterialRecord] = []
  var activeKey: String?
  // Explicit deletion removes the record, while this identity receipt prevents
  // a deleted immutable key being reused for different material data.
  var revisionDigests: [String: String] = [:]

  static func digest(_ record: DrawingMaterialRecord) throws -> String {
    let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
    var object = try JSONSerialization.jsonObject(with: encoder.encode(record)) as! [String: Any]
    if var measurement = object["measurement"] as? [String: Any],
      var registration = measurement["registration"] as? [String: Any] {
      if let sessions = registration["captureSessionIDs"] as? [Any] {
        registration["captureSessionIDs"] = try sessions.map { session in
          (session, String(decoding: try JSONSerialization.data(withJSONObject: session, options: [.sortedKeys, .fragmentsAllowed]), as: UTF8.self))
        }.sorted { $0.1 < $1.1 }.map(\.0)
      }
      measurement["registration"] = registration; object["measurement"] = measurement
    }
    return SHA256.hash(data: try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]))
      .map { String(format: "%02x", $0) }.joined()
  }

  func validate() throws {
    guard Set(records.map { $0.profile.key }).count == records.count,
      activeKey == nil || records.contains(where: { $0.profile.key == activeKey }) else {
      throw DrawingMaterialStorageError.invalid("Duplicate material revision or unavailable active selection.")
    }
    for record in records {
      try record.validate()
      if let known = revisionDigests[record.profile.key], known != (try Self.digest(record)) {
        throw DrawingMaterialStorageError.invalid("Material revision identity receipt does not match its record.")
      }
    }
  }
}

enum DrawingMaterialStorageError: Error, LocalizedError {
  case invalid(String)
  var errorDescription: String? {
    switch self { case .invalid(let message): message }
  }
}

/// Serialized settings installer. Measurement records contain references; raw
/// image ownership belongs to the drawing-run archive, never this settings file.
actor DrawingMaterialStore {
  nonisolated let directoryURL: URL
  private let write: @Sendable (Data, URL) throws -> Void

  init(directoryURL: URL, write: @escaping @Sendable (Data, URL) throws -> Void = { bytes, url in
    try bytes.write(to: url, options: .atomic)
    let handle = try FileHandle(forWritingTo: url)
    try handle.synchronize()
    try handle.close()
  }) {
    self.directoryURL = directoryURL
    self.write = write
  }

  nonisolated static func defaultStore() -> DrawingMaterialStore {
    return .init(directoryURL: AdaptivePlotterStoragePaths.production.drawingMaterialsDirectory)
  }

  private var indexURL: URL { directoryURL.appendingPathComponent("index-v1.json") }

  func load() throws -> DrawingMaterialSnapshot {
    let manager = FileManager.default
    var isDirectory: ObjCBool = false
    if manager.fileExists(atPath: directoryURL.path, isDirectory: &isDirectory), !isDirectory.boolValue {
      throw DrawingMaterialStorageError.invalid("The material archive location is not a directory.")
    }
    guard manager.fileExists(atPath: indexURL.path) else { return .init() }
    let envelope = try JSONDecoder().decode(Envelope.self, from: Data(contentsOf: indexURL))
    guard envelope.schemaVersion == 1, Self.digest(envelope.payload) == envelope.sha256 else {
      throw DrawingMaterialStorageError.invalid("The material archive is corrupt or unsupported. Its original file is preserved; repair it before retrying.")
    }
    let snapshot = try JSONDecoder().decode(DrawingMaterialSnapshot.self, from: envelope.payload)
    try snapshot.validate()
    return snapshot
  }

  func save(_ snapshot: DrawingMaterialSnapshot) throws {
    // Re-read before every replacement: a newly damaged index is never silently
    // overwritten, even after this store has loaded a healthy prior revision.
    let existing = try load()
    try snapshot.validate()
    for record in snapshot.records {
      if let prior = existing.records.first(where: { $0.profile.key == record.profile.key }), prior != record {
        throw DrawingMaterialStorageError.invalid("Material revision \(record.profile.key) is immutable. Create a new revision.")
      }
    }
    var committed = snapshot
    for (key, digest) in existing.revisionDigests {
      if let proposed = committed.revisionDigests[key], proposed != digest {
        throw DrawingMaterialStorageError.invalid("A deleted material revision cannot be reused with different data.")
      }
      committed.revisionDigests[key] = digest
    }
    for record in committed.records {
      let digest = try DrawingMaterialSnapshot.digest(record)
      if let prior = committed.revisionDigests[record.profile.key], prior != digest {
        throw DrawingMaterialStorageError.invalid("Material revision identity is immutable, including after deletion.")
      }
      committed.revisionDigests[record.profile.key] = digest
    }
    let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
    let payload = try encoder.encode(committed)
    let envelope = Envelope(schemaVersion: 1, sha256: Self.digest(payload), payload: payload)
    try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    try write(encoder.encode(envelope), indexURL)
    let installed = try load()
    guard installed.records == snapshot.records, installed.activeKey == snapshot.activeKey else {
      throw DrawingMaterialStorageError.invalid("The installed material archive did not match the requested snapshot.")
    }
  }

  private static func digest(_ bytes: Data) -> String {
    SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
  }
  private struct Envelope: Codable {
    let schemaVersion: Int
    let sha256: String
    let payload: Data
  }
}
