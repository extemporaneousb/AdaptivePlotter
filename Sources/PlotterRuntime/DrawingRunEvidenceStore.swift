import CryptoKit
import Foundation
import PlotterModel

public enum DrawingRunEvidenceArchiveError: Error, Equatable, Sendable {
  case unsupportedSchema(UInt16)
  case revisionMismatch(expected: UInt64, actual: UInt64)
  case duplicateRecordID(DrawingEvidenceRecordID)
  case duplicateRunID(RunID)
  case invalidAttempt(RunID)
  case invalidAxisCalibrationEvidence(String)
  case invalidReviewDeletion(DrawingEvidenceRecordID)
}

/// An explicit operator assertion; it does not rewrite execution or Vision facts.
public struct DrawingRunNoInkConfirmation: Codable, Hashable, Sendable {
  public let runID: RunID
  public let recordedAt: Date

  public init(runID: RunID, recordedAt: Date = Date()) {
    self.runID = runID
    self.recordedAt = recordedAt
  }
}

extension DrawingRunEvidenceRecord {
  /// Operator testimony is distinct from machine execution and vision evidence.
  public var allowsNoInkConfirmation: Bool {
    guard case .cancelled = executionDisposition else { return false }
    return executionFrontiers.inkVerifiedStrokeCount == 0 && role == .ordinaryDrawing
  }
}

/// Immutable execution facts, operator assertions and review deletions.
/// Deleting a review never removes no-redraw facts or shared media ownership.
public struct DrawingRunEvidenceArchive: Codable, Hashable, Sendable {
  public static let schemaVersion: UInt16 = 5

  public let schemaVersion: UInt16
  public let archiveID: UUID
  public let revision: UInt64
  public let records: [DrawingRunEvidenceRecord]
  public let attempts: [DrawingRunAttemptState]
  public let noInkConfirmations: [DrawingRunNoInkConfirmation]
  public var confirmedNoInkRunIDs: Set<RunID> { Set(noInkConfirmations.map(\.runID)) }
  /// Review tombstones do not change no-redraw eligibility.
  public let deletedReviewRecordIDs: [DrawingEvidenceRecordID]
  public var reviewRecords: [DrawingRunEvidenceRecord] {
    let deleted = Set(deletedReviewRecordIDs)
    return records.filter { !deleted.contains($0.recordID) }
  }
  public let axisMetricMeasurements: [ControllerAxisMetricMeasurement]
  public let axisCalibrationAttempts: [ControllerAxisCalibrationAttempt]
  public let axisCalibrationTerminals: [ControllerAxisCalibrationTerminal]
  public var incompleteAttempts: [DrawingRunAttemptState] {
    let sealed = Set(records.map(\.runID))
    return attempts.filter { !sealed.contains($0.intent.runID) }
  }

  public init(
    archiveID: UUID = UUID(),
    revision: UInt64,
    records: [DrawingRunEvidenceRecord],
    attempts: [DrawingRunAttemptState] = [],
    deletedReviewRecordIDs: [DrawingEvidenceRecordID] = [],
    noInkConfirmations: [DrawingRunNoInkConfirmation] = [],
    axisMetricMeasurements: [ControllerAxisMetricMeasurement] = [],
    axisCalibrationAttempts: [ControllerAxisCalibrationAttempt] = [],
    axisCalibrationTerminals: [ControllerAxisCalibrationTerminal] = []
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
    var confirmedRuns = Set<RunID>()
    for confirmation in noInkConfirmations {
      guard confirmedRuns.insert(confirmation.runID).inserted,
        confirmation.recordedAt.timeIntervalSinceReferenceDate.isFinite,
        records.contains(where: { $0.runID == confirmation.runID && $0.allowsNoInkConfirmation }) else {
        throw DrawingRunEvidenceArchiveError.invalidAttempt(confirmation.runID)
      }
    }
    self.noInkConfirmations = noInkConfirmations
    var deletionIDs = Set<DrawingEvidenceRecordID>()
    for recordID in deletedReviewRecordIDs {
      guard recordIDs.contains(recordID), deletionIDs.insert(recordID).inserted else {
        throw DrawingRunEvidenceArchiveError.invalidReviewDeletion(recordID)
      }
    }
    var intentIDs = Set<RunID>()
    for attempt in attempts {
      let runID = attempt.intent.runID
      try attempt.intent.validate()
      guard intentIDs.insert(runID).inserted, attempt.baselines.count <= 4,
        Set(attempt.baselines).count == attempt.baselines.count,
        !attempt.inkDispatchPossible || !attempt.baselines.isEmpty else {
        throw DrawingRunEvidenceArchiveError.invalidAttempt(runID)
      }
      guard attempt.progressFrames.isEmpty || attempt.inkDispatchPossible else {
        throw DrawingRunEvidenceArchiveError.invalidAttempt(runID)
      }
      try DrawingRunProgressFrame.validate(attempt.progressFrames, intent: attempt.intent, baselines: attempt.baselines)
      let optical = attempt.intent.context.registration.applicability.opticalConfiguration
      for (index, media) in attempt.baselines.enumerated() {
        try media.validate()
        guard media.source == optical.source, media.frame.width == optical.width,
          media.frame.height == optical.height, media.frame.pixelFormat == optical.pixelFormat,
          media.frame.cameraConfigurationID == attempt.baselines.first?.frame.cameraConfigurationID else {
          throw DrawingRunEvidenceArchiveError.invalidAttempt(runID)
        }
        if let observation = attempt.intent.observationPlan, let position = media.controllerPosition {
          guard observation.poses.indices.contains(index),
            MachinePositionAcceptancePolicy.accepts(position, target: observation.poses[index].position) else {
            throw DrawingRunEvidenceArchiveError.invalidAttempt(runID)
          }
        }
      }
    }
    for record in records {
      try record.validateAttemptEvidence()
      if let evidence = record.attemptEvidence {
        guard let state = attempts.first(where: { $0.intent.runID == record.runID }),
          state.intent == evidence.intent, state.baselines == evidence.baselines,
          state.progressFrames == evidence.progressFrames,
          record.executionFrontiers.commandedStrokeCount == 0 || state.inkDispatchPossible else {
          throw DrawingRunEvidenceArchiveError.invalidAttempt(record.runID)
        }
      } else if intentIDs.contains(record.runID) {
        throw DrawingRunEvidenceArchiveError.invalidAttempt(record.runID)
      }
    }
    try Self.validateAxisEvidence(measurements: axisMetricMeasurements,
      attempts: axisCalibrationAttempts, terminals: axisCalibrationTerminals, records: records)
    self.axisMetricMeasurements = axisMetricMeasurements
    self.axisCalibrationAttempts = axisCalibrationAttempts
    self.axisCalibrationTerminals = axisCalibrationTerminals
    schemaVersion = Self.schemaVersion
    self.archiveID = archiveID
    self.revision = revision
    self.records = records
    self.attempts = attempts
    self.deletedReviewRecordIDs = deletedReviewRecordIDs
  }

  public init(archiveID: UUID = UUID()) {
    schemaVersion = Self.schemaVersion
    self.archiveID = archiveID
    revision = 0
    records = []
    attempts = []
    deletedReviewRecordIDs = []
    noInkConfirmations = []
    axisMetricMeasurements = []
    axisCalibrationAttempts = []
    axisCalibrationTerminals = []
  }

  public func appending(_ record: DrawingRunEvidenceRecord) throws -> Self {
    try Self(
      archiveID: archiveID,
      revision: revision + 1,
      records: records + [record],
      attempts: attempts, deletedReviewRecordIDs: deletedReviewRecordIDs, noInkConfirmations: noInkConfirmations,
      axisMetricMeasurements: axisMetricMeasurements,
      axisCalibrationAttempts: axisCalibrationAttempts, axisCalibrationTerminals: axisCalibrationTerminals
    )
  }

  public func confirmingNoInk(_ confirmation: DrawingRunNoInkConfirmation) throws -> Self {
    if confirmedNoInkRunIDs.contains(confirmation.runID) { return self }
    return try Self(archiveID: archiveID, revision: revision, records: records,
      attempts: attempts, deletedReviewRecordIDs: deletedReviewRecordIDs,
      noInkConfirmations: noInkConfirmations + [confirmation],
      axisMetricMeasurements: axisMetricMeasurements,
      axisCalibrationAttempts: axisCalibrationAttempts, axisCalibrationTerminals: axisCalibrationTerminals)
  }

  public func deletingReview(recordID: DrawingEvidenceRecordID) throws -> Self {
    if deletedReviewRecordIDs.contains(recordID) { return self }
    return try Self(archiveID: archiveID, revision: revision, records: records,
      attempts: attempts, deletedReviewRecordIDs: deletedReviewRecordIDs + [recordID], noInkConfirmations: noInkConfirmations,
      axisMetricMeasurements: axisMetricMeasurements,
      axisCalibrationAttempts: axisCalibrationAttempts, axisCalibrationTerminals: axisCalibrationTerminals)
  }

  private static func validateAxisEvidence(measurements: [ControllerAxisMetricMeasurement],
    attempts: [ControllerAxisCalibrationAttempt], terminals: [ControllerAxisCalibrationTerminal],
    records: [DrawingRunEvidenceRecord]) throws {
    func require(_ value: Bool, _ reason: String) throws {
      if !value { throw DrawingRunEvidenceArchiveError.invalidAxisCalibrationEvidence(reason) }
    }
    var retained = [UUID: ControllerAxisMetricMeasurement]()
    for measurement in measurements {
      try require(retained[measurement.measurementID] == nil, "Duplicate measurement identity")
      try require(records.contains(measurement.geometry.record), "Measurement source record differs from archive")
      if let previous = measurement.supersedesMeasurementID {
        try require(retained[previous]?.geometry == measurement.geometry,
          "Measurement correction must name an earlier observation of the same exact frame")
      }
      retained[measurement.measurementID] = measurement
    }
    var prepared = [UUID: ControllerAxisCalibrationProposal]()
    for attempt in attempts {
      let proposal = attempt.proposal
      try require(attempt.recordedAt.timeIntervalSinceReferenceDate.isFinite,
        "Invalid calibration timestamp")
      try require(prepared[proposal.proposalID] == nil, "Duplicate calibration preparation")
      guard let measurement = retained[proposal.measurementID], proposal.validates(measurement: measurement) else {
        throw DrawingRunEvidenceArchiveError.invalidAxisCalibrationEvidence("Proposal does not derive from its retained measurement")
      }
      try require(!prepared.values.contains { $0.proposedMachineGeometry == proposal.proposedMachineGeometry },
        "Geometry revision reused")
      prepared[proposal.proposalID] = proposal
    }
    var terminalIDs = Set<UUID>()
    for terminal in terminals {
      guard let proposal = prepared[terminal.proposalID], terminalIDs.insert(terminal.proposalID).inserted,
        terminal.recordedAt.timeIntervalSinceReferenceDate.isFinite else {
        throw DrawingRunEvidenceArchiveError.invalidAxisCalibrationEvidence("Terminal has no unique prepared calibration")
      }
      let outcome = terminal.outcome
      try require(Array(proposal.commands.prefix(outcome.attemptedCommands.count)) == outcome.attemptedCommands,
        "Terminal attempted commands differ from proposal")
      if outcome.status == .applied {
        try require(outcome.verifiedContext.map(proposal.validatesReadback) == true,
          "Applied calibration has no matching settings readback")
      }
    }
  }

  private enum CodingKeys: String, CodingKey { case schemaVersion, archiveID, revision, records, attempts, deletedReviewRecordIDs, noInkConfirmations, axisMetricMeasurements, axisCalibrationAttempts, axisCalibrationTerminals }

  public init(from decoder: any Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    let decodedSchema = try values.decode(UInt16.self, forKey: .schemaVersion)
    guard (1...Self.schemaVersion).contains(decodedSchema) else {
      throw DrawingRunEvidenceArchiveError.unsupportedSchema(decodedSchema)
    }
    try self.init(
      archiveID: values.decode(UUID.self, forKey: .archiveID),
      revision: values.decode(UInt64.self, forKey: .revision),
      records: values.decode([DrawingRunEvidenceRecord].self, forKey: .records),
      attempts: values.decodeIfPresent([DrawingRunAttemptState].self, forKey: .attempts) ?? [],
      deletedReviewRecordIDs: values.decodeIfPresent([DrawingEvidenceRecordID].self, forKey: .deletedReviewRecordIDs) ?? [],
      noInkConfirmations: values.decodeIfPresent([DrawingRunNoInkConfirmation].self, forKey: .noInkConfirmations) ?? [],
      axisMetricMeasurements: values.decodeIfPresent([ControllerAxisMetricMeasurement].self, forKey: .axisMetricMeasurements) ?? [],
      axisCalibrationAttempts: values.decodeIfPresent([ControllerAxisCalibrationAttempt].self, forKey: .axisCalibrationAttempts) ?? [],
      axisCalibrationTerminals: values.decodeIfPresent([ControllerAxisCalibrationTerminal].self, forKey: .axisCalibrationTerminals) ?? []
    )
  }
}

public enum DrawingRunEvidenceStoreRejection: Error, Equatable, Sendable {
  case unsupportedEnvelopeSchema(UInt16)
  case unsupportedArchiveSchema(UInt16)
  case integrityMismatch
  case malformedEnvelope(String)
  case invalidArchive(String)
  case invalidMedia(String)
}

public enum DrawingRunEvidenceStoreLoadResult: Sendable {
  case absent
  case loaded(DrawingRunEvidenceArchive)
  case rejected(DrawingRunEvidenceStoreRejection)
}

public enum DrawingRunEvidenceStoreError: Error, Equatable, Sendable {
  case existingArchiveRejected(DrawingRunEvidenceStoreRejection)
  case missingAttempt(RunID)
  case immutableAttempt(RunID)
  case invalidMedia(String)
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

  public func load() -> DrawingRunEvidenceStoreLoadResult { loadSnapshot() }

  /// Startup reads the same atomic archive before installing Saved Learning.
  /// It never mutates the store or bypasses checksum/semantic validation.
  public nonisolated func loadSnapshot() -> DrawingRunEvidenceStoreLoadResult {
    Self.load(from: fileURL)
  }

  public func installMedia(frame: StampedFrame, source: FrameSourceIdentity) throws
    -> DrawingRunMediaReference {
    let reference = DrawingRunMediaReference(frame: frame, source: source)
    try reference.validate()
    let data = frame.bytes.data
    guard Self.sha256(data) == reference.frame.frameSHA256 else {
      throw DrawingRunEvidenceStoreError.invalidMedia("Frame content differs from its identity")
    }
    let destination = Self.mediaURL(reference, archiveURL: fileURL)
    try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(),
      withIntermediateDirectories: true)
    if FileManager.default.fileExists(atPath: destination.path) {
      _ = try Self.readMedia(reference, archiveURL: fileURL)
    } else {
      try data.write(to: destination, options: [.atomic])
      try Self.synchronizeFile(destination)
      _ = try Self.readMedia(reference, archiveURL: fileURL)
    }
    return reference
  }

  public func readMedia(_ reference: DrawingRunMediaReference) throws -> StampedFrame {
    try Self.readMedia(reference, archiveURL: fileURL)
  }

  @discardableResult
  public func stageIntent(_ intent: DrawingRunIntent) throws -> DrawingRunEvidenceArchive {
    let current = try currentArchive()
    if let existing = current.attempts.first(where: { $0.intent.runID == intent.runID }) {
      guard existing.intent == intent else { throw DrawingRunEvidenceStoreError.immutableAttempt(intent.runID) }
      return current
    }
    guard !current.records.contains(where: { $0.runID == intent.runID }) else {
      throw DrawingRunEvidenceStoreError.immutableAttempt(intent.runID)
    }
    return try saving(current, attempts: current.attempts + [DrawingRunAttemptState(intent: intent)])
  }

  @discardableResult
  public func stageBaseline(runID: RunID, media: DrawingRunMediaReference) throws
    -> DrawingRunEvidenceArchive {
    _ = try readMedia(media)
    let current = try currentArchive()
    guard let index = current.attempts.firstIndex(where: { $0.intent.runID == runID }) else {
      throw DrawingRunEvidenceStoreError.missingAttempt(runID)
    }
    let state = current.attempts[index]
    if state.baselines.contains(media) { return current }
    guard !current.records.contains(where: { $0.runID == runID }) else {
      throw DrawingRunEvidenceStoreError.immutableAttempt(runID)
    }
    guard !state.inkDispatchPossible else {
      throw DrawingRunEvidenceStoreError.immutableAttempt(runID)
    }
    var attempts = current.attempts
    attempts[index] = DrawingRunAttemptState(intent: state.intent,
      baselines: state.baselines + [media])
    return try saving(current, attempts: attempts)
  }

  @discardableResult
  public func stageProgressFrame(runID: RunID, frame: DrawingRunProgressFrame) throws -> DrawingRunEvidenceArchive {
    _ = try readMedia(frame.media)
    let current = try currentArchive()
    guard let index = current.attempts.firstIndex(where: { $0.intent.runID == runID }) else {
      throw DrawingRunEvidenceStoreError.missingAttempt(runID)
    }
    let state = current.attempts[index]
    if state.progressFrames.contains(frame) { return current }
    guard state.inkDispatchPossible, !current.records.contains(where: { $0.runID == runID }) else {
      throw DrawingRunEvidenceStoreError.immutableAttempt(runID)
    }
    var attempts = current.attempts
    attempts[index] = DrawingRunAttemptState(intent: state.intent, baselines: state.baselines,
      inkDispatchPossible: true, progressFrames: state.progressFrames + [frame])
    return try saving(current, attempts: attempts)
  }

  @discardableResult
  public func markInkDispatchPossible(runID: RunID) throws -> DrawingRunEvidenceArchive {
    let current = try currentArchive()
    guard let index = current.attempts.firstIndex(where: { $0.intent.runID == runID }) else {
      throw DrawingRunEvidenceStoreError.missingAttempt(runID)
    }
    let state = current.attempts[index]
    if state.inkDispatchPossible { return current }
    guard !current.records.contains(where: { $0.runID == runID }) else {
      throw DrawingRunEvidenceStoreError.immutableAttempt(runID)
    }
    guard !state.baselines.isEmpty else {
      throw DrawingRunEvidenceStoreError.immutableAttempt(runID)
    }
    var attempts = current.attempts
    attempts[index] = DrawingRunAttemptState(intent: state.intent,
      baselines: state.baselines, inkDispatchPossible: true)
    return try saving(current, attempts: attempts)
  }

  @discardableResult
  public func append(_ record: DrawingRunEvidenceRecord, archiveID: UUID = UUID()) throws
    -> DrawingRunEvidenceArchive {
    var current = try currentArchive(archiveID: archiveID)
    // Only the exact schema-4 seal is idempotent. A changed outcome/identity and
    // historical duplicate submissions preserve the existing rejection contract.
    if record.attemptEvidence != nil, current.records.contains(record) { return current }
    if let evidence = record.attemptEvidence,
      !current.attempts.contains(where: { $0.intent.runID == record.runID }) {
      guard record.executionFrontiers.commandedStrokeCount == 0 else {
        throw DrawingRunEvidenceStoreError.missingAttempt(record.runID)
      }
      // A pre-dispatch failure can retain and seal its intent in this one write.
      current = try DrawingRunEvidenceArchive(archiveID: current.archiveID,
        revision: current.revision, records: current.records,
        attempts: current.attempts + [DrawingRunAttemptState(intent: evidence.intent,
          baselines: evidence.baselines)],
        deletedReviewRecordIDs: current.deletedReviewRecordIDs, noInkConfirmations: current.noInkConfirmations,
        axisMetricMeasurements: current.axisMetricMeasurements,
        axisCalibrationAttempts: current.axisCalibrationAttempts,
        axisCalibrationTerminals: current.axisCalibrationTerminals)
    }
    let updated = try current.appending(record)
    try save(updated)
    return updated
  }

  /// Persist operator testimony atomically before changing runtime eligibility.
  @discardableResult
  public func confirmNoInk(_ confirmation: DrawingRunNoInkConfirmation) throws -> DrawingRunEvidenceArchive {
    let current = try currentArchive()
    let updated = try current.confirmingNoInk(confirmation)
    if updated != current { try save(updated) }
    return updated
  }

  @discardableResult
  public func deleteReview(recordID: DrawingEvidenceRecordID) throws -> DrawingRunEvidenceArchive {
    let current = try currentArchive()
    let updated = try current.deletingReview(recordID: recordID)
    if updated != current { try save(updated) }
    return updated
  }

  @discardableResult
  public func appendAxisMetricMeasurement(_ measurement: ControllerAxisMetricMeasurement) throws -> DrawingRunEvidenceArchive {
    let current = try currentArchive()
    if current.axisMetricMeasurements.contains(measurement) { return current }
    return try savingAxisEvidence(current, measurements: current.axisMetricMeasurements + [measurement],
      attempts: current.axisCalibrationAttempts, terminals: current.axisCalibrationTerminals)
  }

  @discardableResult
  public func prepareAxisCalibration(_ attempt: ControllerAxisCalibrationAttempt) throws -> DrawingRunEvidenceArchive {
    let current = try currentArchive()
    if current.axisCalibrationAttempts.contains(attempt) { return current }
    return try savingAxisEvidence(current, measurements: current.axisMetricMeasurements,
      attempts: current.axisCalibrationAttempts + [attempt], terminals: current.axisCalibrationTerminals)
  }

  @discardableResult
  public func appendAxisCalibrationTerminal(_ terminal: ControllerAxisCalibrationTerminal) throws -> DrawingRunEvidenceArchive {
    let current = try currentArchive()
    if current.axisCalibrationTerminals.contains(terminal) { return current }
    return try savingAxisEvidence(current, measurements: current.axisMetricMeasurements,
      attempts: current.axisCalibrationAttempts, terminals: current.axisCalibrationTerminals + [terminal])
  }

  private func savingAxisEvidence(_ current: DrawingRunEvidenceArchive,
    measurements: [ControllerAxisMetricMeasurement], attempts: [ControllerAxisCalibrationAttempt],
    terminals: [ControllerAxisCalibrationTerminal]) throws -> DrawingRunEvidenceArchive {
    let updated = try DrawingRunEvidenceArchive(archiveID: current.archiveID,
      revision: current.revision, records: current.records, attempts: current.attempts,
      deletedReviewRecordIDs: current.deletedReviewRecordIDs, noInkConfirmations: current.noInkConfirmations,
      axisMetricMeasurements: measurements, axisCalibrationAttempts: attempts,
      axisCalibrationTerminals: terminals)
    try save(updated)
    return updated
  }

  private func currentArchive(archiveID: UUID = UUID()) throws -> DrawingRunEvidenceArchive {
    switch Self.load(from: fileURL) {
    case .absent: return DrawingRunEvidenceArchive(archiveID: archiveID)
    case .loaded(let archive): return archive
    case .rejected(let rejection): throw DrawingRunEvidenceStoreError.existingArchiveRejected(rejection)
    }
  }

  private func saving(_ current: DrawingRunEvidenceArchive,
    attempts: [DrawingRunAttemptState]) throws -> DrawingRunEvidenceArchive {
    let updated = try DrawingRunEvidenceArchive(archiveID: current.archiveID,
      revision: current.revision, records: current.records, attempts: attempts,
      deletedReviewRecordIDs: current.deletedReviewRecordIDs, noInkConfirmations: current.noInkConfirmations,
      axisMetricMeasurements: current.axisMetricMeasurements,
      axisCalibrationAttempts: current.axisCalibrationAttempts,
      axisCalibrationTerminals: current.axisCalibrationTerminals)
    try save(updated)
    return updated
  }

  private func save(_ archive: DrawingRunEvidenceArchive) throws {
    try Self.verifyMedia(in: archive, archiveURL: fileURL)
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
    try Self.synchronizeFile(fileURL)
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
      let archive = try JSONDecoder().decode(DrawingRunEvidenceArchive.self, from: envelope.payload)
      try verifyMedia(in: archive, archiveURL: fileURL)
      return .loaded(archive)
    } catch DrawingRunEvidenceStoreError.invalidMedia(let reason) {
      return .rejected(.invalidMedia(reason))
    } catch DrawingRunEvidenceArchiveError.unsupportedSchema(let schema) {
      return .rejected(.unsupportedArchiveSchema(schema))
    } catch {
      return .rejected(.invalidArchive(String(describing: error)))
    }
  }

  private nonisolated static func mediaURL(_ reference: DrawingRunMediaReference,
    archiveURL: URL) -> URL {
    archiveURL.deletingLastPathComponent()
      .appendingPathComponent(archiveURL.lastPathComponent + ".media", isDirectory: true)
      .appendingPathComponent(reference.frame.frameSHA256 + ".pixels")
  }

  private nonisolated static func readMedia(_ reference: DrawingRunMediaReference,
    archiveURL: URL) throws -> StampedFrame {
    do {
      try reference.validate()
      let bytes = try Data(contentsOf: mediaURL(reference, archiveURL: archiveURL))
      guard bytes.count == reference.byteCount, sha256(bytes) == reference.frame.frameSHA256 else {
        throw DrawingRunEvidenceStoreError.invalidMedia("Missing or corrupt original frame " + reference.frame.frameSHA256)
      }
      let frame = reference.frame
      return try StampedFrame(id: frame.frameID, sequence: reference.sequence,
        captureNanoseconds: frame.captureNanoseconds, cameraConfigurationID: frame.cameraConfigurationID,
        width: frame.width, height: frame.height, rowBytes: frame.rowBytes,
        pixelFormat: frame.pixelFormat, bytes: OwnedFrameBytes(copying: bytes))
    } catch {
      throw DrawingRunEvidenceStoreError.invalidMedia(String(describing: error))
    }
  }

  private nonisolated static func verifyMedia(in archive: DrawingRunEvidenceArchive,
    archiveURL: URL) throws {
    var references: [DrawingRunMediaReference] = []
    for attempt in archive.attempts {
      references += attempt.baselines
      references += attempt.progressFrames.map(\.media)
    }
    for record in archive.records {
      guard let attempt = record.attemptEvidence else { continue }
      references += attempt.baselines
      references += attempt.terminalFrames
      references += attempt.progressFrames.map(\.media)
    }
    for reference in Set(references) { _ = try readMedia(reference, archiveURL: archiveURL) }
    for record in archive.records {
      guard let attempt = record.attemptEvidence, let coverage = attempt.mediaCoverage else { continue }
      try verifyCoverage(coverage, attempt: attempt, archiveURL: archiveURL)
    }
  }

  /// Checks the claimed per-pixel derivation against original, verified bytes.
  /// A valid checksum alone cannot turn a fabricated composite into evidence.
  private nonisolated static func verifyCoverage(_ coverage: DrawingRunMediaCoverage,
    attempt: DrawingRunAttemptEvidence, archiveURL: URL) throws {
    try coverage.validate()
    var originals: [(baseline: StampedFrame, result: StampedFrame)] = []
    for view in coverage.views {
      guard let before = attempt.baselines.first(where: {
        $0.source == view.frames.source && $0.frame == view.frames.baseline
      }), let after = attempt.terminalFrames.first(where: {
        $0.source == view.frames.source && $0.frame == view.frames.post
      }) else { throw DrawingRunEvidenceStoreError.invalidMedia("Composite lacks its exact original frames") }
      originals.append((try readMedia(before, archiveURL: archiveURL),
        try readMedia(after, archiveURL: archiveURL)))
    }
    func equalsPixel(_ frame: StampedFrame, x: Int, y: Int, output: Data, offset: Int) -> Bool {
      let input = y * frame.rowBytes + x * frame.pixelFormat.bytesPerPixel
      switch frame.pixelFormat {
      case .gray8:
        return output[offset] == frame.bytes[input] && output[offset + 1] == frame.bytes[input]
          && output[offset + 2] == frame.bytes[input]
      case .rgba8:
        return (0..<3).allSatisfy { output[offset + $0] == frame.bytes[input + $0] }
      case .bgra8:
        return output[offset] == frame.bytes[input + 2] && output[offset + 1] == frame.bytes[input + 1]
          && output[offset + 2] == frame.bytes[input]
      }
    }
    for (index, source) in coverage.perPixelSource.enumerated() {
      guard let source else { continue }
      let frames = originals[source.viewIndex]
      guard equalsPixel(frames.baseline, x: source.baselineX, y: source.baselineY,
        output: coverage.baselineRGBA, offset: index * 4),
        equalsPixel(frames.result, x: source.resultX, y: source.resultY,
          output: coverage.resultRGBA, offset: index * 4) else {
        throw DrawingRunEvidenceStoreError.invalidMedia("Composite pixels differ from retained originals")
      }
    }
  }

  private nonisolated static func synchronizeFile(_ url: URL) throws {
    let handle = try FileHandle(forWritingTo: url)
    defer { try? handle.close() }
    try handle.synchronize()
  }

  private nonisolated static func sha256(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }
}
