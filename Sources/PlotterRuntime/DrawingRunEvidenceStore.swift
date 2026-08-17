import CryptoKit
import Foundation
import PlotterModel

public enum DrawingRunEvidenceArchiveError: Error, Equatable, Sendable {
  case unsupportedSchema(UInt16)
  case revisionMismatch(expected: UInt64, actual: UInt64)
  case duplicateRecordID(DrawingEvidenceRecordID)
  case duplicateRunID(RunID)
}

/// Append-only value persisted by `DrawingRunEvidenceStore`. Existing facts
/// are never replaced; a new record creates a new archive revision.
public struct DrawingRunEvidenceArchive: Codable, Hashable, Sendable {
  public static let schemaVersion: UInt16 = 1

  public let schemaVersion: UInt16
  public let archiveID: UUID
  public let revision: UInt64
  public let records: [DrawingRunEvidenceRecord]

  public init(
    archiveID: UUID = UUID(),
    revision: UInt64,
    records: [DrawingRunEvidenceRecord]
  ) throws {
    guard revision == UInt64(records.count) else {
      throw DrawingRunEvidenceArchiveError.revisionMismatch(
        expected: UInt64(records.count),
        actual: revision
      )
    }
    var recordIDs = Set<DrawingEvidenceRecordID>()
    var runIDs = Set<RunID>()
    for record in records {
      guard recordIDs.insert(record.recordID).inserted else {
        throw DrawingRunEvidenceArchiveError.duplicateRecordID(record.recordID)
      }
      guard runIDs.insert(record.runID).inserted else {
        throw DrawingRunEvidenceArchiveError.duplicateRunID(record.runID)
      }
    }
    schemaVersion = Self.schemaVersion
    self.archiveID = archiveID
    self.revision = revision
    self.records = records
  }

  public init(archiveID: UUID = UUID()) {
    schemaVersion = Self.schemaVersion
    self.archiveID = archiveID
    revision = 0
    records = []
  }

  public func appending(_ record: DrawingRunEvidenceRecord) throws -> Self {
    try Self(
      archiveID: archiveID,
      revision: revision + 1,
      records: records + [record]
    )
  }

  private enum CodingKeys: String, CodingKey { case schemaVersion, archiveID, revision, records }

  public init(from decoder: any Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    let decodedSchema = try values.decode(UInt16.self, forKey: .schemaVersion)
    guard decodedSchema == Self.schemaVersion else {
      throw DrawingRunEvidenceArchiveError.unsupportedSchema(decodedSchema)
    }
    try self.init(
      archiveID: values.decode(UUID.self, forKey: .archiveID),
      revision: values.decode(UInt64.self, forKey: .revision),
      records: values.decode([DrawingRunEvidenceRecord].self, forKey: .records)
    )
  }
}

public enum DrawingRunEvidenceStoreRejection: Error, Equatable, Sendable {
  case unsupportedEnvelopeSchema(UInt16)
  case unsupportedArchiveSchema(UInt16)
  case integrityMismatch
  case malformedEnvelope(String)
  case invalidArchive(String)
}

public enum DrawingRunEvidenceStoreLoadResult: Sendable {
  case absent
  case loaded(DrawingRunEvidenceArchive)
  case rejected(DrawingRunEvidenceStoreRejection)
}

public enum DrawingRunEvidenceStoreError: Error, Equatable, Sendable {
  case existingArchiveRejected(DrawingRunEvidenceStoreRejection)
}

/// Atomic, integrity-checked persistence intended for an injected Application
/// Support file path. It records immutable facts only: there is deliberately no
/// readiness-promotion, model-acceptance, authorization, or motion-replay API.
public actor DrawingRunEvidenceStore {
  private static let envelopeSchemaVersion: UInt16 = 1

  private struct Envelope: Codable {
    let schemaVersion: UInt16
    let payload: Data
    let payloadSHA256: String
  }

  public nonisolated let fileURL: URL

  public init(fileURL: URL) {
    self.fileURL = fileURL
  }

  public func load() -> DrawingRunEvidenceStoreLoadResult {
    Self.load(from: fileURL)
  }

  @discardableResult
  public func append(
    _ record: DrawingRunEvidenceRecord,
    archiveID: UUID = UUID()
  ) throws -> DrawingRunEvidenceArchive {
    let current: DrawingRunEvidenceArchive
    switch Self.load(from: fileURL) {
    case .absent:
      current = DrawingRunEvidenceArchive(archiveID: archiveID)
    case .loaded(let loaded):
      current = loaded
    case .rejected(let rejection):
      throw DrawingRunEvidenceStoreError.existingArchiveRejected(rejection)
    }
    let updated = try current.appending(record)
    try save(updated)
    return updated
  }

  private func save(_ archive: DrawingRunEvidenceArchive) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let payload = try encoder.encode(archive)
    let envelope = Envelope(
      schemaVersion: Self.envelopeSchemaVersion,
      payload: payload,
      payloadSHA256: Self.sha256(payload)
    )
    try FileManager.default.createDirectory(
      at: fileURL.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try encoder.encode(envelope).write(to: fileURL, options: [.atomic])
  }

  private nonisolated static func load(from fileURL: URL) -> DrawingRunEvidenceStoreLoadResult {
    guard FileManager.default.fileExists(atPath: fileURL.path) else { return .absent }
    let envelope: Envelope
    do {
      envelope = try JSONDecoder().decode(Envelope.self, from: Data(contentsOf: fileURL))
    } catch {
      return .rejected(.malformedEnvelope(String(describing: error)))
    }
    guard envelope.schemaVersion == envelopeSchemaVersion else {
      return .rejected(.unsupportedEnvelopeSchema(envelope.schemaVersion))
    }
    guard sha256(envelope.payload) == envelope.payloadSHA256 else {
      return .rejected(.integrityMismatch)
    }
    do {
      return .loaded(try JSONDecoder().decode(
        DrawingRunEvidenceArchive.self,
        from: envelope.payload
      ))
    } catch DrawingRunEvidenceArchiveError.unsupportedSchema(let schema) {
      return .rejected(.unsupportedArchiveSchema(schema))
    } catch {
      return .rejected(.invalidArchive(String(describing: error)))
    }
  }

  private nonisolated static func sha256(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }
}
