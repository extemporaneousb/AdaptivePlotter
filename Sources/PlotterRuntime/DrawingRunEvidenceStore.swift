import Darwin
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

  fileprivate init(validated current: Self, records: [DrawingRunEvidenceRecord]? = nil,
    attempts: [DrawingRunAttemptState]? = nil) {
    schemaVersion = Self.schemaVersion; archiveID = current.archiveID
    self.records = records ?? current.records; revision = UInt64(self.records.count)
    self.attempts = attempts ?? current.attempts
    noInkConfirmations = current.noInkConfirmations
    deletedReviewRecordIDs = current.deletedReviewRecordIDs
    axisMetricMeasurements = current.axisMetricMeasurements
    axisCalibrationAttempts = current.axisCalibrationAttempts
    axisCalibrationTerminals = current.axisCalibrationTerminals
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
  private static let envelopeSchemaVersion: UInt16 = 2

  private struct Envelope: Codable {
    let schemaVersion: UInt16
    let payload: Data
    let payloadSHA256: String
  }

  private struct Component: Codable {
    let id: UUID
    let sha256: String
  }

  private struct Manifest: Codable {
    let archiveID: UUID
    let revision: UInt64
    let records: [Component]
    let attempts: [Component]
    let noInkConfirmations: [DrawingRunNoInkConfirmation]
    let deletedReviewRecordIDs: [DrawingEvidenceRecordID]
    let axisMetricMeasurements: [Component]
    let axisCalibrationAttempts: [Component]
    let axisCalibrationTerminals: [Component]
  }

  private struct VerificationReceipt {
    let bytes: Data
    let manifest: Manifest?
    let files: [URL: VerifiedFileState]
  }

  private var cachedArchive: DrawingRunEvidenceArchive?
  private var cachedManifest: Manifest?
  private var committedBytes: Data?
  private var verifiedFiles: [URL: VerifiedFileState] = [:]
  public private(set) var componentBytesEncoded = 0
  public private(set) var mediaBytesVerified = 0

  public nonisolated let fileURL: URL

  public init(fileURL: URL) {
    self.fileURL = fileURL
  }

  public func load() -> DrawingRunEvidenceStoreLoadResult {
    if let cachedArchive, cachedManifest != nil, let committedBytes,
      let read = try? VerifiedFileState.read(fileURL), read.bytes == committedBytes,
      verifiedFiles.allSatisfy({ (try? VerifiedFileState($0.key)) == $0.value }) {
      return .loaded(cachedArchive)
    }
    var receipt: VerificationReceipt?
    let result = Self.load(from: fileURL, receipt: &receipt)
    guard case .loaded(let archive) = result else {
      cachedArchive = nil; cachedManifest = nil; committedBytes = nil; verifiedFiles = [:]
      return result
    }
    do {
      guard let receipt else { throw CocoaError(.fileReadUnknown) }
      cache(archive, receipt: receipt)
      // Pay the one-time legacy split at startup, never during Draw admission.
      if cachedManifest == nil { try save(archive) }
      return .loaded(archive)
    } catch {
      return .rejected(.invalidArchive(String(describing: error)))
    }
  }

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

  private func verifyMedia(_ reference: DrawingRunMediaReference) throws {
    try reference.validate()
    let url = Self.mediaURL(reference, archiveURL: fileURL)
    if let state = verifiedFiles[url], state.byteCount == Int64(reference.byteCount),
      try VerifiedFileState(url) == state { return }
    var state: VerifiedFileState?
    _ = try Self.readMedia(reference, archiveURL: fileURL, state: &state)
    mediaBytesVerified += reference.byteCount
    verifiedFiles[url] = state
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
    try verifyMedia(media)
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
    try verifyMedia(frame.media)
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
    for baseline in state.baselines { try verifyMedia(baseline) }
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
    guard !current.records.contains(where: { $0.recordID == record.recordID }) else {
      throw DrawingRunEvidenceArchiveError.duplicateRecordID(record.recordID)
    }
    guard !current.records.contains(where: { $0.runID == record.runID }) else {
      throw DrawingRunEvidenceArchiveError.duplicateRunID(record.runID)
    }
    _ = try DrawingRunEvidenceArchive(revision: 1, records: [record],
      attempts: current.attempts.filter { $0.intent.runID == record.runID })
    let updated = DrawingRunEvidenceArchive(validated: current, records: current.records + [record])
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
    if let cachedArchive, let committedBytes {
      let (bytes, _) = try VerifiedFileState.read(fileURL)
      if bytes == committedBytes,
        verifiedFiles.allSatisfy({ (try? VerifiedFileState($0.key)) == $0.value }) {
        return cachedArchive
      }
      return try readCurrentArchive(archiveID: archiveID, requiresExisting: true)
    }
    return try readCurrentArchive(archiveID: archiveID, requiresExisting: false)
  }

  private func readCurrentArchive(archiveID: UUID, requiresExisting: Bool) throws -> DrawingRunEvidenceArchive {
    var receipt: VerificationReceipt?
    switch Self.load(from: fileURL, receipt: &receipt) {
    case .absent:
      if requiresExisting { throw DrawingRunEvidenceStoreError.existingArchiveRejected(.invalidArchive("Committed evidence disappeared")) }
      return DrawingRunEvidenceArchive(archiveID: archiveID)
    case .loaded(let archive):
      guard let receipt else { throw CocoaError(.fileReadUnknown) }
      cache(archive, receipt: receipt)
      return archive
    case .rejected(let rejection): throw DrawingRunEvidenceStoreError.existingArchiveRejected(rejection)
    }
  }

  private func cache(_ archive: DrawingRunEvidenceArchive, receipt: VerificationReceipt) {
    cachedArchive = archive; cachedManifest = receipt.manifest
    committedBytes = receipt.bytes; verifiedFiles = receipt.files
  }

  private func saving(_ current: DrawingRunEvidenceArchive,
    attempts: [DrawingRunAttemptState]) throws -> DrawingRunEvidenceArchive {
    let previous = Dictionary(uniqueKeysWithValues: current.attempts.map { ($0.intent.runID, $0) })
    let changed = attempts.filter { previous[$0.intent.runID] != $0 }
    let changedIDs = Set(changed.map { $0.intent.runID })
    let records = current.records.filter { changedIDs.contains($0.runID) }
    _ = try DrawingRunEvidenceArchive(revision: UInt64(records.count), records: records, attempts: changed)
    let updated = DrawingRunEvidenceArchive(validated: current, attempts: attempts)
    try save(updated)
    return updated
  }

  private func save(_ archive: DrawingRunEvidenceArchive) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let oldRecords = Dictionary(uniqueKeysWithValues: (cachedArchive?.records ?? []).map { ($0.recordID.rawValue, $0) })
    let recordRefs = Dictionary(uniqueKeysWithValues: (cachedManifest?.records ?? []).map { ($0.id, $0) })
    let oldAttempts = Dictionary(uniqueKeysWithValues: (cachedArchive?.attempts ?? []).map { ($0.intent.runID.rawValue, $0) })
    let attemptRefs = Dictionary(uniqueKeysWithValues: (cachedManifest?.attempts ?? []).map { ($0.id, $0) })
    var records: [Component] = [], attempts: [Component] = []
    for record in archive.records {
      if oldRecords[record.recordID.rawValue] == record, let reference = recordRefs[record.recordID.rawValue] {
        records.append(reference)
      } else {
        if let attempt = record.attemptEvidence {
          for reference in attempt.baselines + attempt.terminalFrames + attempt.progressFrames.map(\.media) { try verifyMedia(reference) }
          if let coverage = attempt.mediaCoverage { try Self.verifyCoverage(coverage, attempt: attempt, archiveURL: fileURL) }
        }
        records.append(try installComponent(record, id: record.recordID.rawValue, encoder: encoder))
      }
    }
    for attempt in archive.attempts {
      if oldAttempts[attempt.intent.runID.rawValue] == attempt, let reference = attemptRefs[attempt.intent.runID.rawValue] {
        attempts.append(reference)
      } else {
        for reference in attempt.baselines + attempt.progressFrames.map(\.media) { try verifyMedia(reference) }
        attempts.append(try installComponent(attempt, id: attempt.intent.runID.rawValue, encoder: encoder))
      }
    }
    let manifest = Manifest(archiveID: archive.archiveID, revision: archive.revision,
      records: records, attempts: attempts, noInkConfirmations: archive.noInkConfirmations,
      deletedReviewRecordIDs: archive.deletedReviewRecordIDs,
      axisMetricMeasurements: try componentReferences(archive.axisMetricMeasurements,
        previous: cachedArchive?.axisMetricMeasurements ?? [], references: cachedManifest?.axisMetricMeasurements ?? [],
        id: { $0.measurementID }, encoder: encoder),
      axisCalibrationAttempts: try componentReferences(archive.axisCalibrationAttempts,
        previous: cachedArchive?.axisCalibrationAttempts ?? [], references: cachedManifest?.axisCalibrationAttempts ?? [],
        id: { $0.proposal.proposalID }, encoder: encoder),
      axisCalibrationTerminals: try componentReferences(archive.axisCalibrationTerminals,
        previous: cachedArchive?.axisCalibrationTerminals ?? [], references: cachedManifest?.axisCalibrationTerminals ?? [],
        id: { $0.proposalID }, encoder: encoder))
    let payload = try encoder.encode(manifest)
    let bytes = try encoder.encode(Envelope(schemaVersion: Self.envelopeSchemaVersion,
      payload: payload, payloadSHA256: Self.sha256(payload)))
    try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try bytes.write(to: fileURL, options: [.atomic])
    try Self.synchronizeFile(fileURL)
    // Publish only after the exact index and all referenced components are durable.
    // Superseded blobs are retained after uncertain commits; the index alone selects truth.
    cachedArchive = archive; cachedManifest = manifest; committedBytes = bytes
    verifiedFiles[fileURL] = try VerifiedFileState(fileURL)
  }

  private func installComponent<T: Encodable>(_ value: T, id: UUID, encoder: JSONEncoder) throws -> Component {
    let bytes = try encoder.encode(value)
    componentBytesEncoded += bytes.count
    let hash = Self.sha256(bytes)
    let url = Self.componentURL(hash, archiveURL: fileURL)
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    if FileManager.default.fileExists(atPath: url.path) {
      let (existing, _) = try VerifiedFileState.read(url)
      guard Self.sha256(existing) == hash else {
        throw DrawingRunEvidenceStoreError.existingArchiveRejected(.integrityMismatch)
      }
    } else {
      try bytes.write(to: url, options: [.atomic]); try Self.synchronizeFile(url)
    }
    let (installed, state) = try VerifiedFileState.read(url)
    guard Self.sha256(installed) == hash else { throw DrawingRunEvidenceStoreError.existingArchiveRejected(.integrityMismatch) }
    verifiedFiles[url] = state
    return Component(id: id, sha256: hash)
  }

  private func componentReferences<T: Encodable & Equatable>(_ values: [T], previous: [T],
    references: [Component], id: (T) -> UUID, encoder: JSONEncoder) throws -> [Component] {
    let old = Dictionary(uniqueKeysWithValues: previous.map { (id($0), $0) })
    let retained = Dictionary(uniqueKeysWithValues: references.map { ($0.id, $0) })
    return try values.map { value in
      if old[id(value)] == value, let reference = retained[id(value)] { return reference }
      return try installComponent(value, id: id(value), encoder: encoder)
    }
  }

  private nonisolated static func componentURL(_ hash: String, archiveURL: URL) -> URL {
    archiveURL.deletingLastPathComponent().appendingPathComponent(archiveURL.lastPathComponent + ".records", isDirectory: true)
      .appendingPathComponent(hash + ".json")
  }

  private nonisolated static func readComponent<T: Decodable>(_ reference: Component,
    archiveURL: URL, as type: T.Type, files: inout [URL: VerifiedFileState]) throws -> T {
    guard reference.sha256.count == 64, reference.sha256.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else {
      throw DrawingRunEvidenceStoreRejection.integrityMismatch
    }
    let url = componentURL(reference.sha256, archiveURL: archiveURL)
    let (bytes, state) = try VerifiedFileState.read(url)
    guard sha256(bytes) == reference.sha256 else { throw DrawingRunEvidenceStoreRejection.integrityMismatch }
    files[url] = state
    return try JSONDecoder().decode(type, from: bytes)
  }

  private nonisolated static func load(from fileURL: URL) -> DrawingRunEvidenceStoreLoadResult {
    var receipt: VerificationReceipt?
    return load(from: fileURL, receipt: &receipt)
  }

  private nonisolated static func load(from fileURL: URL,
    receipt: inout VerificationReceipt?) -> DrawingRunEvidenceStoreLoadResult {
    guard FileManager.default.fileExists(atPath: fileURL.path) else { return .absent }
    let envelope: Envelope
    let bytes: Data
    let indexState: VerifiedFileState
    do {
      (bytes, indexState) = try VerifiedFileState.read(fileURL)
      envelope = try JSONDecoder().decode(Envelope.self, from: bytes)
    }
    catch { return .rejected(.malformedEnvelope(String(describing: error))) }
    guard [1, 2].contains(envelope.schemaVersion) else { return .rejected(.unsupportedEnvelopeSchema(envelope.schemaVersion)) }
    guard sha256(envelope.payload) == envelope.payloadSHA256 else { return .rejected(.integrityMismatch) }
    do {
      let archive: DrawingRunEvidenceArchive
      var manifest: Manifest?
      var files: [URL: VerifiedFileState] = [fileURL: indexState]
      if envelope.schemaVersion == 1 {
        archive = try JSONDecoder().decode(DrawingRunEvidenceArchive.self, from: envelope.payload)
      } else {
        let decodedManifest = try JSONDecoder().decode(Manifest.self, from: envelope.payload)
        manifest = decodedManifest
        let records = try decodedManifest.records.map { reference -> DrawingRunEvidenceRecord in
          let record = try readComponent(reference, archiveURL: fileURL, as: DrawingRunEvidenceRecord.self, files: &files)
          guard record.recordID.rawValue == reference.id else { throw DrawingRunEvidenceStoreRejection.integrityMismatch }
          return record
        }
        let attempts = try decodedManifest.attempts.map { reference -> DrawingRunAttemptState in
          let attempt = try readComponent(reference, archiveURL: fileURL, as: DrawingRunAttemptState.self, files: &files)
          guard attempt.intent.runID.rawValue == reference.id else { throw DrawingRunEvidenceStoreRejection.integrityMismatch }
          return attempt
        }
        archive = try DrawingRunEvidenceArchive(archiveID: decodedManifest.archiveID, revision: decodedManifest.revision,
          records: records, attempts: attempts, deletedReviewRecordIDs: decodedManifest.deletedReviewRecordIDs,
          noInkConfirmations: decodedManifest.noInkConfirmations,
          axisMetricMeasurements: decodedManifest.axisMetricMeasurements.map {
            let value = try readComponent($0, archiveURL: fileURL, as: ControllerAxisMetricMeasurement.self, files: &files)
            guard value.measurementID == $0.id else { throw DrawingRunEvidenceStoreRejection.integrityMismatch }
            return value
          },
          axisCalibrationAttempts: decodedManifest.axisCalibrationAttempts.map {
            let value = try readComponent($0, archiveURL: fileURL, as: ControllerAxisCalibrationAttempt.self, files: &files)
            guard value.proposal.proposalID == $0.id else { throw DrawingRunEvidenceStoreRejection.integrityMismatch }
            return value
          },
          axisCalibrationTerminals: decodedManifest.axisCalibrationTerminals.map {
            let value = try readComponent($0, archiveURL: fileURL, as: ControllerAxisCalibrationTerminal.self, files: &files)
            guard value.proposalID == $0.id else { throw DrawingRunEvidenceStoreRejection.integrityMismatch }
            return value
          })
      }
      try verifyMedia(in: archive, archiveURL: fileURL, files: &files)
      guard files.allSatisfy({ (try? VerifiedFileState($0.key)) == $0.value }) else {
        throw DrawingRunEvidenceStoreRejection.invalidArchive("Evidence changed during verification; retry the read.")
      }
      receipt = VerificationReceipt(bytes: bytes, manifest: manifest, files: files)
      return .loaded(archive)
    } catch let rejection as DrawingRunEvidenceStoreRejection { return .rejected(rejection) }
    catch DrawingRunEvidenceStoreError.invalidMedia(let reason) { return .rejected(.invalidMedia(reason)) }
    catch DrawingRunEvidenceArchiveError.unsupportedSchema(let schema) { return .rejected(.unsupportedArchiveSchema(schema)) }
    catch { return .rejected(.invalidArchive(String(describing: error))) }
  }

  private nonisolated static func mediaURL(_ reference: DrawingRunMediaReference,
    archiveURL: URL) -> URL {
    archiveURL.deletingLastPathComponent()
      .appendingPathComponent(archiveURL.lastPathComponent + ".media", isDirectory: true)
      .appendingPathComponent(reference.frame.frameSHA256 + ".pixels")
  }

  private nonisolated static func readMedia(_ reference: DrawingRunMediaReference,
    archiveURL: URL) throws -> StampedFrame {
    var state: VerifiedFileState?
    return try readMedia(reference, archiveURL: archiveURL, state: &state)
  }

  private nonisolated static func readMedia(_ reference: DrawingRunMediaReference,
    archiveURL: URL, state: inout VerifiedFileState?) throws -> StampedFrame {
    do {
      try reference.validate()
      let (bytes, verifiedState) = try VerifiedFileState.read(mediaURL(reference, archiveURL: archiveURL))
      guard bytes.count == reference.byteCount, sha256(bytes) == reference.frame.frameSHA256 else {
        throw DrawingRunEvidenceStoreError.invalidMedia("Missing or corrupt original frame " + reference.frame.frameSHA256)
      }
      state = verifiedState
      let frame = reference.frame
      return try StampedFrame(id: frame.frameID, sequence: reference.sequence,
        captureNanoseconds: frame.captureNanoseconds, cameraConfigurationID: frame.cameraConfigurationID,
        width: frame.width, height: frame.height, rowBytes: frame.rowBytes,
        pixelFormat: frame.pixelFormat, bytes: OwnedFrameBytes(copying: bytes))
    } catch {
      throw DrawingRunEvidenceStoreError.invalidMedia(String(describing: error))
    }
  }

  private nonisolated static func mediaReferences(in archive: DrawingRunEvidenceArchive) -> Set<DrawingRunMediaReference> {
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
    return Set(references)
  }

  private nonisolated static func verifyMedia(in archive: DrawingRunEvidenceArchive,
    archiveURL: URL, files: inout [URL: VerifiedFileState]) throws {
    for reference in mediaReferences(in: archive) {
      var state: VerifiedFileState?
      _ = try readMedia(reference, archiveURL: archiveURL, state: &state)
      files[mediaURL(reference, archiveURL: archiveURL)] = state
    }
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
    // Atomic rename selects the commit; synchronize that directory entry too.
    let descriptor = url.deletingLastPathComponent().withUnsafeFileSystemRepresentation { Darwin.open($0!, O_RDONLY) }
    guard descriptor >= 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
    defer { Darwin.close(descriptor) }
    guard Darwin.fsync(descriptor) == 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
  }

  private nonisolated static func sha256(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }
}
