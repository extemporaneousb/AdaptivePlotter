import CryptoKit
import EpisodeCore
import Foundation
import PlotterEpisodeModel
import PlotterRuntime

/// Durable source locators that an incident-package caller can inspect before
/// constructing the existing unbound `PlotterIncidentPackageSource`. This value
/// owns no persistence, export, or completeness decision.
public struct PlotterIncidentSourceArtifactReferences: Codable, Hashable, Sendable {
  public let episodeID: EpisodeID
  public let journal: EpisodeArtifactReference
  public let journalFileURL: URL
  public let recordingID: EpisodeRecordingID?
  public let recordingDirectoryURL: URL?
  public let recordingDurability: EpisodeRecordingDurability?
  public let recordingCompletenessIssues: [EpisodeRecordingCompletenessIssue]

  public init(
    episodeID: EpisodeID,
    journal: EpisodeArtifactReference,
    journalFileURL: URL,
    recordingID: EpisodeRecordingID?,
    recordingDirectoryURL: URL?,
    recordingDurability: EpisodeRecordingDurability?,
    recordingCompletenessIssues: [EpisodeRecordingCompletenessIssue]
  ) {
    self.episodeID = episodeID
    self.journal = journal
    self.journalFileURL = journalFileURL
    self.recordingID = recordingID
    self.recordingDirectoryURL = recordingDirectoryURL
    self.recordingDurability = recordingDurability
    self.recordingCompletenessIssues = recordingCompletenessIssues
  }
}

struct PlotterIncidentPackageBudget: Codable, Hashable, Sendable {
  static let standard = PlotterIncidentPackageBudget(
    maximumJournalEventCount: 10_000,
    maximumRecordingEntryCount: 100_000,
    maximumFrameReferenceCount: 10_000,
    maximumObservationCount: 10_000,
    maximumMeasurementCount: 10_000,
    maximumEvidenceDecisionCount: 10_000,
    maximumOutcomeCount: 1_000,
    maximumAssessmentCount: 1_000,
    maximumArtifactStatusCount: 20_000,
    maximumOwnerCount: 64,
    maximumAmbiguityCount: 1_000,
    maximumTotalItemCount: 200_000,
    maximumEmbeddedRecordingByteCount: 64 * 1_024 * 1_024,
    maximumReferencedFrameByteCount: 64 * 1_024 * 1_024,
    maximumExportByteCount: 96 * 1_024 * 1_024
  )

  let maximumJournalEventCount: Int
  let maximumRecordingEntryCount: Int
  let maximumFrameReferenceCount: Int
  let maximumObservationCount: Int
  let maximumMeasurementCount: Int
  let maximumEvidenceDecisionCount: Int
  let maximumOutcomeCount: Int
  let maximumAssessmentCount: Int
  let maximumArtifactStatusCount: Int
  let maximumOwnerCount: Int
  let maximumAmbiguityCount: Int
  let maximumTotalItemCount: Int
  let maximumEmbeddedRecordingByteCount: Int
  let maximumReferencedFrameByteCount: Int
  let maximumExportByteCount: Int

  init(
    maximumJournalEventCount: Int,
    maximumRecordingEntryCount: Int,
    maximumFrameReferenceCount: Int,
    maximumObservationCount: Int,
    maximumMeasurementCount: Int,
    maximumEvidenceDecisionCount: Int,
    maximumOutcomeCount: Int,
    maximumAssessmentCount: Int,
    maximumArtifactStatusCount: Int,
    maximumOwnerCount: Int,
    maximumAmbiguityCount: Int,
    maximumTotalItemCount: Int,
    maximumEmbeddedRecordingByteCount: Int,
    maximumReferencedFrameByteCount: Int,
    maximumExportByteCount: Int
  ) {
    self.maximumJournalEventCount = maximumJournalEventCount
    self.maximumRecordingEntryCount = maximumRecordingEntryCount
    self.maximumFrameReferenceCount = maximumFrameReferenceCount
    self.maximumObservationCount = maximumObservationCount
    self.maximumMeasurementCount = maximumMeasurementCount
    self.maximumEvidenceDecisionCount = maximumEvidenceDecisionCount
    self.maximumOutcomeCount = maximumOutcomeCount
    self.maximumAssessmentCount = maximumAssessmentCount
    self.maximumArtifactStatusCount = maximumArtifactStatusCount
    self.maximumOwnerCount = maximumOwnerCount
    self.maximumAmbiguityCount = maximumAmbiguityCount
    self.maximumTotalItemCount = maximumTotalItemCount
    self.maximumEmbeddedRecordingByteCount = maximumEmbeddedRecordingByteCount
    self.maximumReferencedFrameByteCount = maximumReferencedFrameByteCount
    self.maximumExportByteCount = maximumExportByteCount
  }
}

enum PlotterIncidentOwnerDomain: String, Codable, CaseIterable, Hashable, Sendable {
  case episodeStore
  case recordingStore
  case replayService
  case episodeModel
  case operationRegistry
  case machineController
  case cameraCapture
  case visionWorker
  case planning
  case workflow
  case persistence
  case simulator
  case userInterface
}

struct PlotterIncidentCurrentOwner: Codable, Hashable, Sendable {
  let domain: PlotterIncidentOwnerDomain
  let authorityID: EpisodeAuthorityID
  let revision: EpisodeRevisionIdentifier
  let observedAt: Date

  init(
    domain: PlotterIncidentOwnerDomain,
    authorityID: EpisodeAuthorityID,
    revision: EpisodeRevisionIdentifier,
    observedAt: Date
  ) {
    self.domain = domain
    self.authorityID = authorityID
    self.revision = revision
    self.observedAt = observedAt
  }
}

enum PlotterIncidentAmbiguityKind: String, Codable, CaseIterable, Hashable, Sendable {
  case possibleInk
  case controller
  case camera
  case vision
  case evidence
  case persistence
  case workflow
  case runtimePresentation
}

struct PlotterIncidentUnresolvedAmbiguity: Codable, Hashable, Sendable {
  let id: UUID
  let episodeID: EpisodeID
  let kind: PlotterIncidentAmbiguityKind
  let subject: PlotterIncidentAmbiguitySubject
  let owner: EpisodeAuthorityID
  let observedAt: Date
  let summary: String

  init(
    id: UUID,
    episodeID: EpisodeID,
    kind: PlotterIncidentAmbiguityKind,
    subject: PlotterIncidentAmbiguitySubject,
    owner: EpisodeAuthorityID,
    observedAt: Date,
    summary: String
  ) {
    self.id = id
    self.episodeID = episodeID
    self.kind = kind
    self.subject = subject
    self.owner = owner
    self.observedAt = observedAt
    self.summary = summary
  }
}

enum PlotterIncidentAmbiguitySubject: Codable, Hashable, Sendable {
  case episode
  case inkMeasurement(PlotterMeasurementID)
}

enum PlotterIncidentArtifactAvailability: Codable, Hashable, Sendable {
  case available
  case missing
  case corrupt(actualSHA256: String?)
  case unsafe(reason: String)
  case mismatched(
    actualRevision: EpisodeRevisionIdentifier,
    actualSHA256: String?
  )
  case retentionIncomplete(reason: String)
  case unavailable(reason: String)

}

struct PlotterIncidentArtifactStatus: Codable, Hashable, Sendable {
  let reference: EpisodeArtifactReference
  let availability: PlotterIncidentArtifactAvailability

  init(
    reference: EpisodeArtifactReference,
    availability: PlotterIncidentArtifactAvailability
  ) {
    self.reference = reference
    self.availability = availability
  }
}

enum PlotterIncidentFrameRetention: String, Codable, Hashable, Sendable {
  case referenceOnly
  case sensitiveReferenceOnly
}

enum PlotterIncidentFrameAvailability: Codable, Hashable, Sendable {
  case noSourceReportedIssue
  case missing
  case truncated(actualByteCount: Int)
  case byteCountMismatch(actualByteCount: Int)
  case hashMismatch(actualSHA256: String)
  case unreadable
  case unsafe(FrameArtifactConfinementFailure)
}

struct PlotterIncidentFrameReference: Codable, Hashable, Sendable {
  let descriptor: CameraFrameDescriptor
  let artifact: ContentAddressedFrameReference
  let retention: PlotterIncidentFrameRetention
  let availability: [PlotterIncidentFrameAvailability]
}

enum PlotterIncidentRuntimePresentationComparison: Codable, Hashable, Sendable {
  case aligned(
    runtimeRevision: EpisodeStateRevision,
    projectionRevision: PlotterProjectionRevision
  )
  case userInterfaceStale(
    runtimeRevision: EpisodeStateRevision,
    projectedRuntimeRevision: EpisodeStateRevision,
    projectionRevision: PlotterProjectionRevision
  )
  case runtimeSnapshotStale(
    runtimeRevision: EpisodeStateRevision,
    projectedRuntimeRevision: EpisodeStateRevision,
    projectionRevision: PlotterProjectionRevision
  )
  case sameRevisionDigestMismatch(
    revision: EpisodeStateRevision,
    runtimeDigest: EpisodeStateDigest,
    projectedDigest: EpisodeStateDigest,
    projectionRevision: PlotterProjectionRevision
  )
}

enum PlotterIncidentRecordingSourceFact: Codable, Hashable, Sendable {
  case sourceSnapshotNotRevalidated
  case sourceReportedOpen
  case sourceReportedDurabilityUncertain(candidateWasObserved: Bool)
  case sourceReportedIssue(EpisodeRecordingCompletenessIssue)
  case episodeProvenanceUnavailable(sequence: UInt64)
  case environmentProvenanceUnavailable(sequence: UInt64)
}

struct PlotterIncidentPackageCounts: Codable, Hashable, Sendable {
  let journalEvents: Int
  let recordingEntries: Int
  let frameReferences: Int
  let observations: Int
  let measurements: Int
  let evidenceDecisions: Int
  let outcomes: Int
  let assessments: Int
  let artifactStatuses: Int
  let currentOwners: Int
  let unresolvedAmbiguities: Int
}

struct PlotterIncidentPackageBoundedness: Codable, Hashable, Sendable {
  let budget: PlotterIncidentPackageBudget
  let sourceCounts: PlotterIncidentPackageCounts
  let includedCounts: PlotterIncidentPackageCounts
  let embeddedRecordingByteCount: Int
  let omittedReferencedFrameByteCount: Int
  let omittedReferencedFrameCount: Int
  let isTruncated: Bool
}

struct PlotterIncidentPackage: Codable, Hashable, Sendable {
  let formatVersion: UInt64
  let manifest: PlotterEpisodeManifest
  let journal: EpisodeJournal<PlotterEpisodeEventPayload>
  let sourceReportedRecording: EpisodeRecordingSnapshot
  let frameReferences: [PlotterIncidentFrameReference]
  let observations: [PlotterObservation]
  let measurements: [PlotterMeasurement]
  let evidenceDecisions: [PlotterEvidenceDecision]
  let outcomes: [PlotterEpisodeOutcome]
  let assessments: [PlotterAssessment]
  let runtimeState: PlotterEpisodeState
  let userInterfaceProjection: PlotterEpisodeProjection
  let runtimePresentationComparison: PlotterIncidentRuntimePresentationComparison
  let currentOwners: [PlotterIncidentCurrentOwner]
  let artifactStatuses: [PlotterIncidentArtifactStatus]
  let recordingSourceFacts: [PlotterIncidentRecordingSourceFact]
  let unresolvedAmbiguities: [PlotterIncidentUnresolvedAmbiguity]
  let boundedness: PlotterIncidentPackageBoundedness

  var hasUnresolvedAmbiguity: Bool {
    !unresolvedAmbiguities.isEmpty
  }
}

enum PlotterIncidentExportEncoding: String, Codable, Hashable, Sendable {
  case canonicalJSONV1
}

struct PlotterIncidentPackageExport: Codable, Hashable, Sendable {
  let formatVersion: UInt64
  let encoding: PlotterIncidentExportEncoding
  let payloadByteCount: Int
  let payloadSHA256: String
  let payload: Data
}

struct PlotterIncidentPackageSource: Sendable {
  let manifest: PlotterEpisodeManifest
  let journal: EpisodeJournal<PlotterEpisodeEventPayload>
  let recording: EpisodeRecordingSnapshot
  let observations: [PlotterObservation]
  let measurements: [PlotterMeasurement]
  let evidenceDecisions: [PlotterEvidenceDecision]
  let outcomes: [PlotterEpisodeOutcome]
  let assessments: [PlotterAssessment]
  let runtimeState: PlotterEpisodeState
  let userInterfaceProjection: PlotterEpisodeProjection
  let currentOwners: [PlotterIncidentCurrentOwner]
  let artifactStatuses: [PlotterIncidentArtifactStatus]
  let sensitiveFrameIDs: [CameraFrameIdentity]
  let unresolvedAmbiguities: [PlotterIncidentUnresolvedAmbiguity]

  init(
    manifest: PlotterEpisodeManifest,
    journal: EpisodeJournal<PlotterEpisodeEventPayload>,
    recording: EpisodeRecordingSnapshot,
    observations: [PlotterObservation],
    measurements: [PlotterMeasurement],
    evidenceDecisions: [PlotterEvidenceDecision],
    outcomes: [PlotterEpisodeOutcome],
    assessments: [PlotterAssessment],
    runtimeState: PlotterEpisodeState,
    userInterfaceProjection: PlotterEpisodeProjection,
    currentOwners: [PlotterIncidentCurrentOwner],
    artifactStatuses: [PlotterIncidentArtifactStatus],
    sensitiveFrameIDs: [CameraFrameIdentity],
    unresolvedAmbiguities: [PlotterIncidentUnresolvedAmbiguity]
  ) {
    self.manifest = manifest
    self.journal = journal
    self.recording = recording
    self.observations = observations
    self.measurements = measurements
    self.evidenceDecisions = evidenceDecisions
    self.outcomes = outcomes
    self.assessments = assessments
    self.runtimeState = runtimeState
    self.userInterfaceProjection = userInterfaceProjection
    self.currentOwners = currentOwners
    self.artifactStatuses = artifactStatuses
    self.sensitiveFrameIDs = sensitiveFrameIDs
    self.unresolvedAmbiguities = unresolvedAmbiguities
  }
}

public enum PlotterIncidentIdentityKind: String, Codable, Hashable, Sendable {
  case episode
  case manifest
  case definition
  case recording
  case observation
  case measurement
  case evidence
  case outcome
  case assessment
  case ambiguity
  case artifact
  case artifactRevision
  case frame
  case owner
  case ownerRevision
}

public enum PlotterIncidentRelationshipKind: String, Codable, Hashable, Sendable {
  case manifestJournal
  case runtimeEpisode
  case userInterfaceEpisode
  case recordingEpisode
  case journalSemanticValues
  case runtimeJournalRevision
  case runtimeJournalDigest
  case runtimeObservationIDs
  case runtimeMeasurementIDs
  case runtimeEvidenceIDs
  case runtimeOutcome
  case runtimeAssessment
  case evidenceSubject
  case evidenceEnvironment
  case outcomeEvidence
  case assessmentOutcome
  case assessmentEvidence
  case frameReference
  case artifactReference
  case currentOwners
  case ambiguityEpisode
  case possibleInkAmbiguity
}

public enum PlotterIncidentBudgetSection: String, Codable, Hashable, Sendable {
  case journalEvents
  case recordingEntries
  case frameReferences
  case observations
  case measurements
  case evidenceDecisions
  case outcomes
  case assessments
  case artifactStatuses
  case currentOwners
  case unresolvedAmbiguities
  case totalItems
  case embeddedRecordingBytes
  case referencedFrameBytes
  case exportBytes
}

public enum PlotterIncidentPackageRefusal: Error, Codable, Hashable, Sendable {
  case invalidBudget(PlotterIncidentBudgetSection, value: Int)
  case invalidIdentity(PlotterIncidentIdentityKind)
  case duplicateIdentifier(PlotterIncidentIdentityKind)
  case conflictingArtifactReference(EpisodeArtifactID)
  case missingArtifactStatus(EpisodeArtifactID)
  case unexpectedArtifactStatus(EpisodeArtifactID)
  case invalidArtifactStatus(EpisodeArtifactID)
  case relationshipMismatch(PlotterIncidentRelationshipKind)
  case canonicalStateDigestUnavailable
  case canonicalStateDigestMismatch
  case countLimitExceeded(
    section: PlotterIncidentBudgetSection,
    maximum: Int,
    actual: Int
  )
  case arithmeticOverflow(PlotterIncidentBudgetSection)
  case encodingFailed
  case payloadByteCountMismatch(expected: Int, actual: Int)
  case payloadDigestMismatch
  case unsupportedFormatVersion(expected: UInt64, actual: UInt64)
  case unsupportedEncoding
  case noncanonicalPayload
  case corruptPayload
}

enum PlotterIncidentPackageAssemblyOutcome: Hashable, Sendable {
  case assembled(PlotterIncidentPackageExport)
  case refused(PlotterIncidentPackageRefusal)
}

enum PlotterIncidentPackageVerificationOutcome: Hashable, Sendable {
  case envelopeIntegrityConfirmed(PlotterIncidentPackage)
  case refused(PlotterIncidentPackageRefusal)
}

/// A pure, unbound value assembler. It returns bytes to its caller and owns no
/// persistence, artifact materialization, effect execution, or application ingress.
struct PlotterIncidentPackageAssembler: Sendable {
  static let formatVersion: UInt64 = 1

  func assemble(
    _ source: PlotterIncidentPackageSource,
    budget: PlotterIncidentPackageBudget = .standard
  ) -> PlotterIncidentPackageAssemblyOutcome {
    switch buildPackage(source, budget: budget) {
    case let .failure(refusal):
      return .refused(refusal)
    case let .success(package):
      do {
        let payload = try Self.canonicalPayload(package)
        guard payload.count <= budget.maximumExportByteCount else {
          return .refused(.countLimitExceeded(
            section: .exportBytes,
            maximum: budget.maximumExportByteCount,
            actual: payload.count
          ))
        }
        return .assembled(PlotterIncidentPackageExport(
          formatVersion: Self.formatVersion,
          encoding: .canonicalJSONV1,
          payloadByteCount: payload.count,
          payloadSHA256: Self.sha256(payload),
          payload: payload
        ))
      } catch {
        return .refused(.encodingFailed)
      }
    }
  }

  /// Confirms only the canonical envelope bytes, version, size, digest, and
  /// package-level reference contract. It does not validate or promote the
  /// source recording snapshot's store-owned integrity or completeness.
  func verify(
    _ export: PlotterIncidentPackageExport,
    maximumExportByteCount: Int = PlotterIncidentPackageBudget.standard.maximumExportByteCount
  ) -> PlotterIncidentPackageVerificationOutcome {
    guard maximumExportByteCount >= 0 else {
      return .refused(.invalidBudget(.exportBytes, value: maximumExportByteCount))
    }
    guard export.formatVersion == Self.formatVersion else {
      return .refused(.unsupportedFormatVersion(
        expected: Self.formatVersion,
        actual: export.formatVersion
      ))
    }
    guard export.encoding == .canonicalJSONV1 else {
      return .refused(.unsupportedEncoding)
    }
    guard export.payload.count <= maximumExportByteCount else {
      return .refused(.countLimitExceeded(
        section: .exportBytes,
        maximum: maximumExportByteCount,
        actual: export.payload.count
      ))
    }
    guard export.payloadByteCount == export.payload.count else {
      return .refused(.payloadByteCountMismatch(
        expected: export.payloadByteCount,
        actual: export.payload.count
      ))
    }
    guard Self.isSHA256(export.payloadSHA256),
          Self.sha256(export.payload) == export.payloadSHA256 else {
      return .refused(.payloadDigestMismatch)
    }

    let package: PlotterIncidentPackage
    do {
      package = try JSONDecoder().decode(PlotterIncidentPackage.self, from: export.payload)
      guard try Self.canonicalPayload(package) == export.payload else {
        return .refused(.noncanonicalPayload)
      }
    } catch {
      return .refused(.corruptPayload)
    }
    guard package.formatVersion == Self.formatVersion else {
      return .refused(.unsupportedFormatVersion(
        expected: Self.formatVersion,
        actual: package.formatVersion
      ))
    }

    let source = PlotterIncidentPackageSource(
      manifest: package.manifest,
      journal: package.journal,
      recording: package.sourceReportedRecording,
      observations: package.observations,
      measurements: package.measurements,
      evidenceDecisions: package.evidenceDecisions,
      outcomes: package.outcomes,
      assessments: package.assessments,
      runtimeState: package.runtimeState,
      userInterfaceProjection: package.userInterfaceProjection,
      currentOwners: package.currentOwners,
      artifactStatuses: package.artifactStatuses,
      sensitiveFrameIDs: package.frameReferences.compactMap {
        $0.retention == .sensitiveReferenceOnly ? $0.descriptor.frameID : nil
      },
      unresolvedAmbiguities: package.unresolvedAmbiguities
    )
    guard case let .assembled(reassembled) = assemble(
      source,
      budget: package.boundedness.budget
    ), reassembled == export else {
      if case let .failure(refusal) = buildPackage(source, budget: package.boundedness.budget) {
        return .refused(refusal)
      }
      return .refused(.noncanonicalPayload)
    }
    return .envelopeIntegrityConfirmed(package)
  }

  private func buildPackage(
    _ source: PlotterIncidentPackageSource,
    budget: PlotterIncidentPackageBudget
  ) -> Result<PlotterIncidentPackage, PlotterIncidentPackageRefusal> {
    if let refusal = validateBudget(budget) { return .failure(refusal) }
    if let refusal = validateIdentitiesAndRelationships(source) { return .failure(refusal) }

    let frameRecords = source.recording.entries.compactMap(Self.frameRecord)
    let counts = PlotterIncidentPackageCounts(
      journalEvents: source.journal.events.count,
      recordingEntries: source.recording.entries.count,
      frameReferences: frameRecords.count,
      observations: source.observations.count,
      measurements: source.measurements.count,
      evidenceDecisions: source.evidenceDecisions.count,
      outcomes: source.outcomes.count,
      assessments: source.assessments.count,
      artifactStatuses: source.artifactStatuses.count,
      currentOwners: source.currentOwners.count,
      unresolvedAmbiguities: source.unresolvedAmbiguities.count
    )
    if let refusal = validateCounts(counts, budget: budget) { return .failure(refusal) }

    let recordingByteCount: Int
    switch Self.recordingByteCount(source.recording) {
    case let .failure(refusal): return .failure(refusal)
    case let .success(count): recordingByteCount = count
    }
    guard recordingByteCount <= budget.maximumEmbeddedRecordingByteCount else {
      return .failure(.countLimitExceeded(
        section: .embeddedRecordingBytes,
        maximum: budget.maximumEmbeddedRecordingByteCount,
        actual: recordingByteCount
      ))
    }

    let frameByteCount: Int
    switch Self.checkedSum(frameRecords.map(\.artifact.byteCount), section: .referencedFrameBytes) {
    case let .failure(refusal): return .failure(refusal)
    case let .success(count): frameByteCount = count
    }
    guard frameByteCount <= budget.maximumReferencedFrameByteCount else {
      return .failure(.countLimitExceeded(
        section: .referencedFrameBytes,
        maximum: budget.maximumReferencedFrameByteCount,
        actual: frameByteCount
      ))
    }
    let sensitive = Set(source.sensitiveFrameIDs)
    let frameReferences = frameRecords.map { record in
      PlotterIncidentFrameReference(
        descriptor: record.descriptor,
        artifact: record.artifact,
        retention: sensitive.contains(record.descriptor.frameID)
          ? .sensitiveReferenceOnly : .referenceOnly,
        availability: Self.frameAvailability(
          for: record.artifact,
          issues: source.recording.completenessIssues
        )
      )
    }
    let sortedOwners = source.currentOwners.sorted { $0.domain.rawValue < $1.domain.rawValue }
    let sortedStatuses = source.artifactStatuses.sorted {
      $0.reference.id.rawValue < $1.reference.id.rawValue
    }
    let sortedAmbiguities = source.unresolvedAmbiguities.sorted {
      $0.id.uuidString < $1.id.uuidString
    }
    let recordingFacts = Self.recordingSourceFacts(source.recording)
    let comparison = Self.presentationComparison(
      runtime: source.runtimeState,
      projection: source.userInterfaceProjection
    )
    let boundedness = PlotterIncidentPackageBoundedness(
      budget: budget,
      sourceCounts: counts,
      includedCounts: counts,
      embeddedRecordingByteCount: recordingByteCount,
      omittedReferencedFrameByteCount: frameByteCount,
      omittedReferencedFrameCount: frameReferences.count,
      isTruncated: false
    )
    return .success(PlotterIncidentPackage(
      formatVersion: Self.formatVersion,
      manifest: source.manifest,
      journal: source.journal,
      sourceReportedRecording: source.recording,
      frameReferences: frameReferences,
      observations: source.observations,
      measurements: source.measurements,
      evidenceDecisions: source.evidenceDecisions,
      outcomes: source.outcomes,
      assessments: source.assessments,
      runtimeState: source.runtimeState,
      userInterfaceProjection: source.userInterfaceProjection,
      runtimePresentationComparison: comparison,
      currentOwners: sortedOwners,
      artifactStatuses: sortedStatuses,
      recordingSourceFacts: recordingFacts,
      unresolvedAmbiguities: sortedAmbiguities,
      boundedness: boundedness
    ))
  }

  private func validateBudget(
    _ budget: PlotterIncidentPackageBudget
  ) -> PlotterIncidentPackageRefusal? {
    let values: [(PlotterIncidentBudgetSection, Int)] = [
      (.journalEvents, budget.maximumJournalEventCount),
      (.recordingEntries, budget.maximumRecordingEntryCount),
      (.frameReferences, budget.maximumFrameReferenceCount),
      (.observations, budget.maximumObservationCount),
      (.measurements, budget.maximumMeasurementCount),
      (.evidenceDecisions, budget.maximumEvidenceDecisionCount),
      (.outcomes, budget.maximumOutcomeCount),
      (.assessments, budget.maximumAssessmentCount),
      (.artifactStatuses, budget.maximumArtifactStatusCount),
      (.currentOwners, budget.maximumOwnerCount),
      (.unresolvedAmbiguities, budget.maximumAmbiguityCount),
      (.totalItems, budget.maximumTotalItemCount),
      (.embeddedRecordingBytes, budget.maximumEmbeddedRecordingByteCount),
      (.referencedFrameBytes, budget.maximumReferencedFrameByteCount),
      (.exportBytes, budget.maximumExportByteCount),
    ]
    for (section, value) in values where value < 0 {
      return .invalidBudget(section, value: value)
    }
    return nil
  }

  private func validateCounts(
    _ counts: PlotterIncidentPackageCounts,
    budget: PlotterIncidentPackageBudget
  ) -> PlotterIncidentPackageRefusal? {
    let limits: [(PlotterIncidentBudgetSection, Int, Int)] = [
      (.journalEvents, counts.journalEvents, budget.maximumJournalEventCount),
      (.recordingEntries, counts.recordingEntries, budget.maximumRecordingEntryCount),
      (.frameReferences, counts.frameReferences, budget.maximumFrameReferenceCount),
      (.observations, counts.observations, budget.maximumObservationCount),
      (.measurements, counts.measurements, budget.maximumMeasurementCount),
      (.evidenceDecisions, counts.evidenceDecisions, budget.maximumEvidenceDecisionCount),
      (.outcomes, counts.outcomes, budget.maximumOutcomeCount),
      (.assessments, counts.assessments, budget.maximumAssessmentCount),
      (.artifactStatuses, counts.artifactStatuses, budget.maximumArtifactStatusCount),
      (.currentOwners, counts.currentOwners, budget.maximumOwnerCount),
      (.unresolvedAmbiguities, counts.unresolvedAmbiguities, budget.maximumAmbiguityCount),
    ]
    for (section, actual, maximum) in limits where actual > maximum {
      return .countLimitExceeded(section: section, maximum: maximum, actual: actual)
    }
    switch Self.checkedSum(limits.map { $0.1 }, section: .totalItems) {
    case let .failure(refusal): return refusal
    case let .success(total) where total > budget.maximumTotalItemCount:
      return .countLimitExceeded(
        section: .totalItems,
        maximum: budget.maximumTotalItemCount,
        actual: total
      )
    case .success:
      return nil
    }
  }

  private func validateIdentitiesAndRelationships(
    _ source: PlotterIncidentPackageSource
  ) -> PlotterIncidentPackageRefusal? {
    let episodeID = source.manifest.episodeID
    guard Self.isNonzero(episodeID.rawValue) else { return .invalidIdentity(.episode) }
    guard Self.isNonzero(source.manifest.id.rawValue) else { return .invalidIdentity(.manifest) }
    guard Self.isNonzero(source.manifest.definitionID.rawValue) else {
      return .invalidIdentity(.definition)
    }
    guard Self.isNonempty(source.manifest.definitionRevision.rawValue),
          Self.isNonempty(source.manifest.domainRevision.rawValue),
          Self.isNonempty(source.manifest.evaluatorRevision.rawValue),
          Self.isNonempty(source.manifest.reducerRevision.rawValue),
          Self.isNonempty(source.manifest.schemaRevisions.state.rawValue),
          Self.isNonempty(source.manifest.schemaRevisions.event.rawValue),
          Self.isNonempty(source.manifest.schemaRevisions.journal.rawValue),
          Self.isNonempty(source.manifest.buildRevision.rawValue) else {
      return .invalidIdentity(.artifactRevision)
    }
    guard source.journal.manifestID == source.manifest.id,
          source.journal.episodeID == episodeID else {
      return .relationshipMismatch(.manifestJournal)
    }
    guard source.runtimeState.episodeID == episodeID else {
      return .relationshipMismatch(.runtimeEpisode)
    }
    guard source.userInterfaceProjection.episodeID == episodeID else {
      return .relationshipMismatch(.userInterfaceEpisode)
    }
    if let refusal = validateRecordingEpisodeProvenance(
      source.recording,
      episodeID: episodeID
    ) {
      return refusal
    }
    if let refusal = validateSemanticValues(source) { return refusal }
    if let refusal = validateRuntimeClosure(source) { return refusal }
    if let refusal = validateArtifactClosure(source) { return refusal }
    if let refusal = validateOwnersAndAmbiguity(source) { return refusal }
    return validateSensitiveFrames(source)
  }

  private func validateRecordingEpisodeProvenance(
    _ recording: EpisodeRecordingSnapshot,
    episodeID: EpisodeID
  ) -> PlotterIncidentPackageRefusal? {
    for entry in recording.entries {
      if let recordedEpisodeID = entry.provenance.episodeID,
         recordedEpisodeID != episodeID {
        return .relationshipMismatch(.recordingEpisode)
      }
    }
    return nil
  }

  private func validateSemanticValues(
    _ source: PlotterIncidentPackageSource
  ) -> PlotterIncidentPackageRefusal? {
    var journalObservations: [PlotterObservation] = []
    var journalMeasurements: [PlotterMeasurement] = []
    var journalEvidenceDecisions: [PlotterEvidenceDecision] = []
    var journalOutcomes: [PlotterEpisodeOutcome] = []
    var journalAssessments: [PlotterAssessment] = []
    for event in source.journal.events {
      switch event.payload {
      case let .observationRecorded(value): journalObservations.append(value)
      case let .measurementRecorded(value): journalMeasurements.append(value)
      case let .evidenceDecided(value): journalEvidenceDecisions.append(value)
      case let .outcomeRecorded(value): journalOutcomes.append(value)
      case let .assessmentRecorded(value): journalAssessments.append(value)
      case .intentAccepted, .intentRefused:
        break
      case let .effectProgressed(progress):
        guard progress.episodeID == source.manifest.episodeID else {
          return .relationshipMismatch(.runtimeEpisode)
        }
      case let .effectResult(result):
        guard result.context.episodeID == source.manifest.episodeID else {
          return .relationshipMismatch(.runtimeEpisode)
        }
      }
    }
    guard source.observations == journalObservations,
          source.measurements == journalMeasurements,
          source.evidenceDecisions == journalEvidenceDecisions,
          source.outcomes == journalOutcomes,
          source.assessments == journalAssessments else {
      return .relationshipMismatch(.journalSemanticValues)
    }

    let observationIDs = source.observations.map(\.context.id)
    guard observationIDs.allSatisfy({ Self.isNonzero($0.rawValue) }) else {
      return .invalidIdentity(.observation)
    }
    guard Set(observationIDs).count == observationIDs.count else {
      return .duplicateIdentifier(.observation)
    }
    let observationEnvironmentByID = Dictionary(uniqueKeysWithValues:
      source.observations.map { ($0.context.id, $0.context.environment) }
    )
    let measurementIDs = source.measurements.map(\.context.id)
    guard measurementIDs.allSatisfy({ Self.isNonzero($0.rawValue) }) else {
      return .invalidIdentity(.measurement)
    }
    guard Set(measurementIDs).count == measurementIDs.count else {
      return .duplicateIdentifier(.measurement)
    }
    let measurementSourceObservationIDsByID = Dictionary(uniqueKeysWithValues:
      source.measurements.map { ($0.context.id, $0.context.sourceObservationIDs) }
    )
    let observationSet = Set(observationIDs)
    for measurement in source.measurements {
      guard measurement.context.sourceObservationIDs.allSatisfy(observationSet.contains) else {
        return .relationshipMismatch(.evidenceSubject)
      }
    }

    var acceptedEvidence: [PlotterEvidenceID: PlotterEvidence] = [:]
    for decision in source.evidenceDecisions {
      let subject: PlotterEvidenceSubject
      let acceptedEvidenceValue: PlotterEvidence?
      switch decision {
      case let .accepted(evidence):
        guard Self.isNonzero(evidence.id.rawValue) else { return .invalidIdentity(.evidence) }
        guard evidence.episodeID == source.manifest.episodeID else {
          return .relationshipMismatch(.runtimeEpisode)
        }
        guard acceptedEvidence.updateValue(evidence, forKey: evidence.id) == nil else {
          return .duplicateIdentifier(.evidence)
        }
        subject = evidence.subject
        acceptedEvidenceValue = evidence
      case let .refused(refusal):
        subject = refusal.subject
        acceptedEvidenceValue = nil
      }
      guard Self.subjectExists(
        subject,
        observationIDs: observationSet,
        measurementIDs: Set(measurementIDs)
      ) else {
        return .relationshipMismatch(.evidenceSubject)
      }
      if let evidence = acceptedEvidenceValue {
        switch evidence.subject {
        case let .observation(observationID):
          guard observationEnvironmentByID[observationID] == evidence.inputEnvironment else {
            return .relationshipMismatch(.evidenceEnvironment)
          }
        case let .measurement(measurementID):
          guard let sourceObservationIDs = measurementSourceObservationIDsByID[measurementID],
                sourceObservationIDs.allSatisfy({
                  observationEnvironmentByID[$0] == evidence.inputEnvironment
                }) else {
            return .relationshipMismatch(.evidenceEnvironment)
          }
        }
      }
    }

    var outcomeEvidenceIDs: [PlotterOutcomeID: Set<PlotterEvidenceID>] = [:]
    for outcome in source.outcomes {
      guard Self.isNonzero(outcome.id.rawValue) else { return .invalidIdentity(.outcome) }
      guard outcome.episodeID == source.manifest.episodeID else {
        return .relationshipMismatch(.runtimeEpisode)
      }
      guard outcomeEvidenceIDs[outcome.id] == nil else {
        return .duplicateIdentifier(.outcome)
      }
      let acceptedByOutcome = Set(outcome.acceptedEvidenceIDs)
      guard acceptedByOutcome.count == outcome.acceptedEvidenceIDs.count,
            outcome.acceptedEvidenceIDs.allSatisfy({ acceptedEvidence[$0] != nil }) else {
        return .relationshipMismatch(.outcomeEvidence)
      }
      outcomeEvidenceIDs[outcome.id] = acceptedByOutcome
    }

    var assessmentIDs: Set<PlotterAssessmentID> = []
    for assessment in source.assessments {
      guard Self.isNonzero(assessment.id.rawValue) else {
        return .invalidIdentity(.assessment)
      }
      guard assessment.episodeID == source.manifest.episodeID,
            let acceptedByAssessedOutcome = outcomeEvidenceIDs[assessment.outcomeID] else {
        return .relationshipMismatch(.assessmentOutcome)
      }
      guard assessmentIDs.insert(assessment.id).inserted else {
        return .duplicateIdentifier(.assessment)
      }
      var criterionIDs: Set<EpisodeAssessmentCriterionID> = []
      for criterion in assessment.criteria {
        guard Self.isNonempty(criterion.criterionID.rawValue),
              criterionIDs.insert(criterion.criterionID).inserted,
              Set(criterion.evidenceIDs).count == criterion.evidenceIDs.count,
              criterion.evidenceIDs.allSatisfy(acceptedByAssessedOutcome.contains) else {
          return .relationshipMismatch(.assessmentEvidence)
        }
      }
    }
    return nil
  }

  private func validateRuntimeClosure(
    _ source: PlotterIncidentPackageSource
  ) -> PlotterIncidentPackageRefusal? {
    let finalRevision = source.journal.events.last?.postStateRevision
      ?? source.journal.initialStateRevision
    guard source.runtimeState.revision == finalRevision else {
      return .relationshipMismatch(.runtimeJournalRevision)
    }
    do {
      guard try PlotterEpisodeCanonicalDigestV1.digest(source.runtimeState)
        == source.runtimeState.canonicalDigest else {
        return .canonicalStateDigestMismatch
      }
    } catch {
      return .canonicalStateDigestUnavailable
    }
    if let finalDigest = source.journal.events.last?.postStateDigest,
       finalDigest != source.runtimeState.canonicalDigest {
      return .relationshipMismatch(.runtimeJournalDigest)
    }
    if let progress = source.runtimeState.activeEffectProgress {
      guard progress.episodeID == source.manifest.episodeID,
            source.runtimeState.pendingEffectID == progress.effectID else {
        return .relationshipMismatch(.runtimeEpisode)
      }
    }
    if let terminal = source.runtimeState.lastTerminalEffect,
       terminal.result.context.episodeID != source.manifest.episodeID {
      return .relationshipMismatch(.runtimeEpisode)
    }
    guard source.runtimeState.observationIDs == source.observations.map(\.context.id) else {
      return .relationshipMismatch(.runtimeObservationIDs)
    }
    guard source.runtimeState.measurementIDs == source.measurements.map(\.context.id) else {
      return .relationshipMismatch(.runtimeMeasurementIDs)
    }
    let acceptedEvidenceIDs = source.evidenceDecisions.compactMap { decision in
      if case let .accepted(evidence) = decision { return evidence.id }
      return nil
    }
    guard source.runtimeState.acceptedEvidenceIDs == acceptedEvidenceIDs else {
      return .relationshipMismatch(.runtimeEvidenceIDs)
    }
    guard source.runtimeState.outcome == source.outcomes.last else {
      return .relationshipMismatch(.runtimeOutcome)
    }
    guard source.runtimeState.assessment == source.assessments.last else {
      return .relationshipMismatch(.runtimeAssessment)
    }
    return nil
  }

  private func validateArtifactClosure(
    _ source: PlotterIncidentPackageSource
  ) -> PlotterIncidentPackageRefusal? {
    var required: [EpisodeArtifactID: EpisodeArtifactReference] = [:]
    let allReferences = source.journal.events.flatMap(\.artifactReferences)
      + source.observations.flatMap(\.context.artifactReferences)
      + source.evidenceDecisions.flatMap { decision -> [EpisodeArtifactReference] in
        if case let .accepted(evidence) = decision { return evidence.artifactReferences }
        return []
      }
    for reference in allReferences {
      guard Self.validArtifactReference(reference) else {
        return .invalidIdentity(.artifact)
      }
      if let existing = required[reference.id], existing != reference {
        return .conflictingArtifactReference(reference.id)
      }
      required[reference.id] = reference
    }

    var supplied: [EpisodeArtifactID: PlotterIncidentArtifactStatus] = [:]
    for status in source.artifactStatuses {
      guard Self.validArtifactReference(status.reference) else {
        return .invalidIdentity(.artifact)
      }
      guard Self.validArtifactAvailability(status.availability) else {
        return .invalidArtifactStatus(status.reference.id)
      }
      guard supplied.updateValue(status, forKey: status.reference.id) == nil else {
        return .duplicateIdentifier(.artifact)
      }
    }
    for (id, reference) in required {
      guard let status = supplied[id] else { return .missingArtifactStatus(id) }
      guard status.reference == reference else {
        return .relationshipMismatch(.artifactReference)
      }
    }
    if let unexpected = supplied.keys.first(where: { required[$0] == nil }) {
      return .unexpectedArtifactStatus(unexpected)
    }
    return nil
  }

  private func validateOwnersAndAmbiguity(
    _ source: PlotterIncidentPackageSource
  ) -> PlotterIncidentPackageRefusal? {
    let domains = source.currentOwners.map(\.domain)
    guard Set(domains).count == domains.count else {
      return .duplicateIdentifier(.owner)
    }
    guard Set(domains) == Set(PlotterIncidentOwnerDomain.allCases) else {
      return .relationshipMismatch(.currentOwners)
    }
    for owner in source.currentOwners {
      guard Self.isNonempty(owner.authorityID.rawValue) else {
        return .invalidIdentity(.owner)
      }
      guard Self.isNonempty(owner.revision.rawValue) else {
        return .invalidIdentity(.ownerRevision)
      }
    }
    var ambiguityIDs: Set<UUID> = []
    for ambiguity in source.unresolvedAmbiguities {
      guard Self.isNonzero(ambiguity.id) else { return .invalidIdentity(.ambiguity) }
      guard ambiguityIDs.insert(ambiguity.id).inserted else {
        return .duplicateIdentifier(.ambiguity)
      }
      guard ambiguity.episodeID == source.manifest.episodeID else {
        return .relationshipMismatch(.ambiguityEpisode)
      }
      guard Self.isNonempty(ambiguity.owner.rawValue),
            Self.isNonempty(ambiguity.summary) else {
        return .invalidIdentity(.ambiguity)
      }
    }
    let possibleInkMeasurementIDs = Set<PlotterMeasurementID>(source.measurements.compactMap { measurement in
      guard case let .ink(ink) = measurement,
            ink.classification == .possibleInk || ink.classification == .unclear else {
        return nil
      }
      return ink.context.id
    })
    var linkedPossibleInkMeasurementIDs: Set<PlotterMeasurementID> = []
    for ambiguity in source.unresolvedAmbiguities {
      switch (ambiguity.kind, ambiguity.subject) {
      case let (.possibleInk, .inkMeasurement(measurementID)):
        guard possibleInkMeasurementIDs.contains(measurementID),
              linkedPossibleInkMeasurementIDs.insert(measurementID).inserted else {
          return .relationshipMismatch(.possibleInkAmbiguity)
        }
      case (.possibleInk, .episode), (_, .inkMeasurement(_)):
        return .relationshipMismatch(.possibleInkAmbiguity)
      case (_, .episode):
        break
      }
    }
    guard linkedPossibleInkMeasurementIDs == possibleInkMeasurementIDs else {
      return .relationshipMismatch(.possibleInkAmbiguity)
    }
    return nil
  }

  private func validateSensitiveFrames(
    _ source: PlotterIncidentPackageSource
  ) -> PlotterIncidentPackageRefusal? {
    guard Set(source.sensitiveFrameIDs).count == source.sensitiveFrameIDs.count else {
      return .duplicateIdentifier(.frame)
    }
    let recorded = Set(source.recording.entries.compactMap(Self.frameRecord).map {
      $0.descriptor.frameID
    })
    guard source.sensitiveFrameIDs.allSatisfy(recorded.contains) else {
      return .relationshipMismatch(.frameReference)
    }
    return nil
  }

  private static func presentationComparison(
    runtime: PlotterEpisodeState,
    projection: PlotterEpisodeProjection
  ) -> PlotterIncidentRuntimePresentationComparison {
    if projection.runtimeStateRevision < runtime.revision {
      return .userInterfaceStale(
        runtimeRevision: runtime.revision,
        projectedRuntimeRevision: projection.runtimeStateRevision,
        projectionRevision: projection.projectionRevision
      )
    }
    if projection.runtimeStateRevision > runtime.revision {
      return .runtimeSnapshotStale(
        runtimeRevision: runtime.revision,
        projectedRuntimeRevision: projection.runtimeStateRevision,
        projectionRevision: projection.projectionRevision
      )
    }
    if projection.runtimeStateDigest != runtime.canonicalDigest {
      return .sameRevisionDigestMismatch(
        revision: runtime.revision,
        runtimeDigest: runtime.canonicalDigest,
        projectedDigest: projection.runtimeStateDigest,
        projectionRevision: projection.projectionRevision
      )
    }
    return .aligned(
      runtimeRevision: runtime.revision,
      projectionRevision: projection.projectionRevision
    )
  }

  private static func recordingSourceFacts(
    _ recording: EpisodeRecordingSnapshot
  ) -> [PlotterIncidentRecordingSourceFact] {
    var facts: [PlotterIncidentRecordingSourceFact] = [.sourceSnapshotNotRevalidated]
    if !recording.isClosed { facts.append(.sourceReportedOpen) }
    if case let .uncertain(candidateWasObserved) = recording.durability {
      facts.append(.sourceReportedDurabilityUncertain(
        candidateWasObserved: candidateWasObserved
      ))
    }
    facts.append(contentsOf: recording.completenessIssues.map {
      PlotterIncidentRecordingSourceFact.sourceReportedIssue($0)
    })
    for entry in recording.entries {
      if entry.provenance.episodeID == nil {
        facts.append(.episodeProvenanceUnavailable(sequence: entry.sequence))
      }
      if entry.provenance.environment == nil {
        facts.append(.environmentProvenanceUnavailable(sequence: entry.sequence))
      }
    }
    return facts
  }

  private static func frameAvailability(
    for reference: ContentAddressedFrameReference,
    issues: [EpisodeRecordingCompletenessIssue]
  ) -> [PlotterIncidentFrameAvailability] {
    var statuses: [PlotterIncidentFrameAvailability] = []
    for issue in issues {
      switch issue {
      case let .frameBytesMissing(actual) where actual == reference:
        statuses.append(.missing)
      case let .frameBytesTruncated(actual, byteCount) where actual == reference:
        statuses.append(.truncated(actualByteCount: byteCount))
      case let .frameByteCountMismatch(actual, byteCount) where actual == reference:
        statuses.append(.byteCountMismatch(actualByteCount: byteCount))
      case let .frameHashMismatch(actual, digest) where actual == reference:
        statuses.append(.hashMismatch(actualSHA256: digest))
      case let .frameArtifactUnreadable(actual) where actual == reference:
        statuses.append(.unreadable)
      case let .frameArtifactUnsafe(actual, reason) where actual == reference:
        statuses.append(.unsafe(reason))
      default:
        break
      }
    }
    return statuses.isEmpty ? [.noSourceReportedIssue] : statuses
  }

  private static func frameRecord(
    _ entry: EpisodeRecordingEntry
  ) -> CameraFrameRecord? {
    guard case let .camera(.frameReference(record)) = entry.record else { return nil }
    return record
  }

  private static func subjectExists(
    _ subject: PlotterEvidenceSubject,
    observationIDs: Set<PlotterObservationID>,
    measurementIDs: Set<PlotterMeasurementID>
  ) -> Bool {
    switch subject {
    case let .observation(id): return observationIDs.contains(id)
    case let .measurement(id): return measurementIDs.contains(id)
    }
  }

  private static func validArtifactReference(_ reference: EpisodeArtifactReference) -> Bool {
    guard isNonempty(reference.id.rawValue), isNonempty(reference.revision.rawValue) else {
      return false
    }
    if let digest = reference.digest { return isSHA256(digest) }
    return true
  }

  private static func validArtifactAvailability(
    _ availability: PlotterIncidentArtifactAvailability
  ) -> Bool {
    switch availability {
    case .available, .missing:
      return true
    case let .corrupt(actualSHA256):
      return actualSHA256.map(isSHA256) ?? true
    case let .unsafe(reason), let .retentionIncomplete(reason), let .unavailable(reason):
      return isNonempty(reason)
    case let .mismatched(actualRevision, actualSHA256):
      return isNonempty(actualRevision.rawValue) && (actualSHA256.map(isSHA256) ?? true)
    }
  }

  private static func isSHA256(_ value: String) -> Bool {
    value.utf8.count == 64 && value.utf8.allSatisfy {
      (48...57).contains($0) || (97...102).contains($0)
    }
  }

  private static func isNonempty(_ value: String) -> Bool {
    !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  private static func isNonzero(_ value: UUID) -> Bool {
    value != UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))
  }

  private static func checkedSum(
    _ values: [Int],
    section: PlotterIncidentBudgetSection
  ) -> Result<Int, PlotterIncidentPackageRefusal> {
    var total = 0
    for value in values {
      guard value >= 0 else { return .failure(.arithmeticOverflow(section)) }
      let (next, overflow) = total.addingReportingOverflow(value)
      guard !overflow else { return .failure(.arithmeticOverflow(section)) }
      total = next
    }
    return .success(total)
  }

  private static func recordingByteCount(
    _ recording: EpisodeRecordingSnapshot
  ) -> Result<Int, PlotterIncidentPackageRefusal> {
    var values: [Int] = []
    values.reserveCapacity(recording.entries.count)
    for entry in recording.entries {
      guard case let .controller(record) = entry.record else { continue }
      switch record {
      case let .invocation(invocation):
        if case let .rawWrite(parameters) = invocation.operation {
          values.append(parameters.bytes.count)
        }
      case let .completion(completion):
        switch completion.outcome {
        case let .succeeded(.timedRead(chunks, _)):
          values.append(contentsOf: chunks.map { $0.bytes.count })
        case let .failed(failure):
          values.append(contentsOf: failure.partialReadChunks.map { $0.bytes.count })
        case .succeeded:
          break
        }
      }
    }
    return checkedSum(values, section: .embeddedRecordingBytes)
  }

  private static func canonicalPayload(_ package: PlotterIncidentPackage) throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    return try encoder.encode(package)
  }

  private static func sha256(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }
}
