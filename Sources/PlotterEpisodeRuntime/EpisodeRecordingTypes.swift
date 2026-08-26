import EpisodeCore
import Foundation
import PlotterEpisodeModel
import PlotterRuntime

public struct EpisodeRecordingID: RawRepresentable, Codable, Hashable, Sendable {
  public let rawValue: UUID

  public init(rawValue: UUID) {
    self.rawValue = rawValue
  }
}

public struct EpisodeRecordingSchemaRevision: RawRepresentable, Codable, Hashable, Sendable {
  public let rawValue: String

  public init(rawValue: String) {
    self.rawValue = rawValue
  }
}

public struct ControllerInvocationID: RawRepresentable, Codable, Hashable, Sendable {
  public let rawValue: UUID

  public init(rawValue: UUID) {
    self.rawValue = rawValue
  }
}

public struct CameraSourceIdentity: RawRepresentable, Codable, Hashable, Sendable {
  public let rawValue: String

  public init(rawValue: String) {
    self.rawValue = rawValue
  }
}

public struct CameraConfigurationIdentity: RawRepresentable, Codable, Hashable, Sendable {
  public let rawValue: UUID

  public init(rawValue: UUID) {
    self.rawValue = rawValue
  }
}

public struct CameraFrameIdentity: RawRepresentable, Codable, Hashable, Sendable {
  public let rawValue: String

  public init(rawValue: String) {
    self.rawValue = rawValue
  }
}

/// Optional diagnostic correlation only. These identities never make a
/// recording entry an episode event, effect result, or evidence value.
public struct EpisodeRecordingProvenance: Codable, Hashable, Sendable {
  public static let unattributed = EpisodeRecordingProvenance()

  public let episodeID: EpisodeID?
  public let intentRequestID: IntentRequestID?
  public let effectID: EpisodeEffectID?
  public let correlationID: EpisodeCorrelationID?
  public let environment: PlotterEnvironment?

  public init(
    episodeID: EpisodeID? = nil,
    intentRequestID: IntentRequestID? = nil,
    effectID: EpisodeEffectID? = nil,
    correlationID: EpisodeCorrelationID? = nil,
    environment: PlotterEnvironment? = nil
  ) {
    self.episodeID = episodeID
    self.intentRequestID = intentRequestID
    self.effectID = effectID
    self.correlationID = correlationID
    self.environment = environment
  }
}

public struct EpisodeFrameRetentionPolicy: Codable, Hashable, Sendable {
  public let maximumUniqueFrameCount: Int
  public let maximumTotalUniqueFrameBytes: Int

  public init(maximumUniqueFrameCount: Int, maximumTotalUniqueFrameBytes: Int) {
    self.maximumUniqueFrameCount = maximumUniqueFrameCount
    self.maximumTotalUniqueFrameBytes = maximumTotalUniqueFrameBytes
  }
}

enum EpisodeFrameRetentionAccounting {
  static func checkedSum<S: Sequence>(_ values: S) -> Int? where S.Element == Int {
    var total = 0
    for value in values {
      guard value >= 0 else { return nil }
      let (next, overflow) = total.addingReportingOverflow(value)
      guard !overflow else { return nil }
      total = next
    }
    return total
  }

  static func checkedAdding(_ lhs: Int, _ rhs: Int) -> Int? {
    guard lhs >= 0, rhs >= 0 else { return nil }
    let (result, overflow) = lhs.addingReportingOverflow(rhs)
    return overflow ? nil : result
  }

  static func checkedIncrement(_ value: Int) -> Int? {
    checkedAdding(value, 1)
  }
}

public enum ControllerParity: String, Codable, Hashable, Sendable {
  case none
  case even
  case odd
}

public enum ControllerFlowControl: String, Codable, Hashable, Sendable {
  case none
  case hardware
  case software
}

public struct ControllerOpenParameters: Codable, Hashable, Sendable {
  public let endpoint: String
  public let baudRate: UInt64
  public let dataBits: UInt8
  public let stopBits: UInt8
  public let parity: ControllerParity
  public let flowControl: ControllerFlowControl

  public init(
    endpoint: String,
    baudRate: UInt64,
    dataBits: UInt8 = 8,
    stopBits: UInt8 = 1,
    parity: ControllerParity = .none,
    flowControl: ControllerFlowControl = .none
  ) {
    self.endpoint = endpoint
    self.baudRate = baudRate
    self.dataBits = dataBits
    self.stopBits = stopBits
    self.parity = parity
    self.flowControl = flowControl
  }
}

public enum ControllerDiscardScope: String, Codable, Hashable, Sendable {
  case input
}

public struct ControllerDiscardParameters: Codable, Hashable, Sendable {
  public let scope: ControllerDiscardScope

  public init(scope: ControllerDiscardScope = .input) {
    self.scope = scope
  }
}

public struct ControllerRawWriteParameters: Codable, Hashable, Sendable {
  public let bytes: Data

  public init(bytes: Data) {
    self.bytes = bytes
  }
}

public struct ControllerTimedReadParameters: Codable, Hashable, Sendable {
  public let maximumByteCount: Int
  public let timeoutNanoseconds: UInt64

  public init(maximumByteCount: Int, timeoutNanoseconds: UInt64) {
    self.maximumByteCount = maximumByteCount
    self.timeoutNanoseconds = timeoutNanoseconds
  }
}

/// The exact operation and parameters presented to the controller owner.
public enum ControllerOperationInvocation: Codable, Hashable, Sendable {
  case open(ControllerOpenParameters)
  case close
  case discardInput(ControllerDiscardParameters)
  case rawWrite(ControllerRawWriteParameters)
  case timedRead(ControllerTimedReadParameters)
}

public struct ControllerInvocation: Codable, Hashable, Sendable {
  public let id: ControllerInvocationID
  public let operation: ControllerOperationInvocation

  public init(id: ControllerInvocationID, operation: ControllerOperationInvocation) {
    self.id = id
    self.operation = operation
  }
}

/// One exact chunk returned by a timed read, with its recording-clock offset.
public struct ControllerReadChunk: Codable, Hashable, Sendable {
  public let bytes: Data
  public let monotonicOffsetNanoseconds: UInt64

  public init(bytes: Data, monotonicOffsetNanoseconds: UInt64) {
    self.bytes = bytes
    self.monotonicOffsetNanoseconds = monotonicOffsetNanoseconds
  }
}

public enum ControllerErrorKind: String, Codable, Hashable, Sendable {
  case permissionDenied
  case endpointNotFound
  case alreadyOpen
  case notOpen
  case timeout
  case cancelled
  case inputOutput
  case protocolViolation
  case unknown
}

/// A typed failure plus any exact bytes transferred before the failure.
public struct ControllerOperationFailure: Codable, Hashable, Sendable {
  public let kind: ControllerErrorKind
  public let systemCode: Int32?
  public let diagnostic: String?
  public let partialByteCount: Int
  public let partialReadChunks: [ControllerReadChunk]

  public init(
    kind: ControllerErrorKind,
    systemCode: Int32? = nil,
    diagnostic: String? = nil,
    partialByteCount: Int = 0,
    partialReadChunks: [ControllerReadChunk] = []
  ) {
    self.kind = kind
    self.systemCode = systemCode
    self.diagnostic = diagnostic
    self.partialByteCount = partialByteCount
    self.partialReadChunks = partialReadChunks
  }
}

public enum ControllerOperationSuccess: Codable, Hashable, Sendable {
  case open
  case close
  case discardInput(discardedByteCount: Int)
  case rawWrite(writtenByteCount: Int)
  case timedRead(chunks: [ControllerReadChunk], timedOut: Bool)
}

public enum ControllerOperationOutcome: Codable, Hashable, Sendable {
  case succeeded(ControllerOperationSuccess)
  case failed(ControllerOperationFailure)
}

public struct ControllerCompletion: Codable, Hashable, Sendable {
  public let invocationID: ControllerInvocationID
  public let outcome: ControllerOperationOutcome

  public init(invocationID: ControllerInvocationID, outcome: ControllerOperationOutcome) {
    self.invocationID = invocationID
    self.outcome = outcome
  }
}

/// Invocation and completion are distinct transcript records by construction.
public enum ControllerTranscriptRecord: Codable, Hashable, Sendable {
  case invocation(ControllerInvocation)
  case completion(ControllerCompletion)
}

public struct CameraStreamIdentity: Codable, Hashable, Sendable {
  public let source: CameraSourceIdentity
  public let configuration: CameraConfigurationIdentity

  public init(source: CameraSourceIdentity, configuration: CameraConfigurationIdentity) {
    self.source = source
    self.configuration = configuration
  }
}

public enum CameraLifecycleFailureKind: String, Codable, Hashable, Sendable {
  case permissionDenied
  case sourceUnavailable
  case configurationRejected
  case interrupted
  case cancelled
  case inputOutput
  case unknown
}

/// The exact requested lifecycle operation that reached a terminal failure.
public enum CameraLifecycleOperation: Codable, Hashable, Sendable {
  case start(CameraStreamIdentity)
  case reconfigure(previous: CameraStreamIdentity, requested: CameraStreamIdentity)
  case stop(CameraStreamIdentity)
}

public struct CameraLifecycleFailure: Codable, Hashable, Sendable {
  public let operation: CameraLifecycleOperation
  public let kind: CameraLifecycleFailureKind
  public let diagnostic: String?

  public init(
    operation: CameraLifecycleOperation,
    kind: CameraLifecycleFailureKind,
    diagnostic: String? = nil
  ) {
    self.operation = operation
    self.kind = kind
    self.diagnostic = diagnostic
  }
}

/// Camera lifecycle stays separate from retained frame bytes.
public enum CameraLifecycleRecord: Codable, Hashable, Sendable {
  case startRequested(CameraStreamIdentity)
  case started(CameraStreamIdentity)
  case reconfigurationRequested(
    previous: CameraStreamIdentity,
    requested: CameraStreamIdentity
  )
  case reconfigured(previous: CameraStreamIdentity, current: CameraStreamIdentity)
  case stopRequested(CameraStreamIdentity)
  case stopped(CameraStreamIdentity)
  case failed(CameraLifecycleFailure)
}

public enum CameraPixelFormat: Codable, Hashable, Sendable {
  case bgra8
  case rgba8
  case gray8
  case encoded(mediaType: String)
}

/// Identity and layout of the exact frame as supplied by the camera owner.
public struct CameraFrameDescriptor: Codable, Hashable, Sendable {
  public let stream: CameraStreamIdentity
  public let frameID: CameraFrameIdentity
  public let sequence: UInt64
  public let captureNanoseconds: UInt64
  public let width: Int
  public let height: Int
  public let rowBytes: Int
  public let pixelFormat: CameraPixelFormat

  public init(
    stream: CameraStreamIdentity,
    frameID: CameraFrameIdentity,
    sequence: UInt64,
    captureNanoseconds: UInt64,
    width: Int,
    height: Int,
    rowBytes: Int,
    pixelFormat: CameraPixelFormat
  ) {
    self.stream = stream
    self.frameID = frameID
    self.sequence = sequence
    self.captureNanoseconds = captureNanoseconds
    self.width = width
    self.height = height
    self.rowBytes = rowBytes
    self.pixelFormat = pixelFormat
  }
}

public struct ContentAddressedFrameReference: Codable, Hashable, Sendable {
  public let contentSHA256: String
  public let byteCount: Int
  public let relativePath: String

  public init(contentSHA256: String, byteCount: Int, relativePath: String) {
    self.contentSHA256 = contentSHA256
    self.byteCount = byteCount
    self.relativePath = relativePath
  }
}

public struct CameraFrameRecord: Codable, Hashable, Sendable {
  public let descriptor: CameraFrameDescriptor
  public let artifact: ContentAddressedFrameReference

  public init(descriptor: CameraFrameDescriptor, artifact: ContentAddressedFrameReference) {
    self.descriptor = descriptor
    self.artifact = artifact
  }
}

public enum CameraRecordingRecord: Codable, Hashable, Sendable {
  case lifecycle(CameraLifecycleRecord)
  case frameReference(CameraFrameRecord)
}

public struct RunLedgerSequenceRange: Codable, Hashable, Sendable {
  public let first: Int64
  public let last: Int64

  public init(first: Int64, last: Int64) {
    self.first = first
    self.last = last
  }
}

public enum RunLedgerDiagnosticIntegrity: Codable, Hashable, Sendable {
  case verified
  case notVerified
  case payloadCorruption(sequence: Int64)
}

public enum RunLedgerDiagnosticCompleteness: Codable, Hashable, Sendable {
  case complete
  case incomplete(missingRanges: [RunLedgerSequenceRange])
}

/// A reference to the current diagnostic ledger only. The recording store
/// never opens, reads, mutates, or promotes the referenced ``RunLedger``.
public struct RunLedgerDiagnosticReference: Codable, Hashable, Sendable {
  public let runID: LedgerRunID
  public let recordedRange: RunLedgerSequenceRange
  public let integrity: RunLedgerDiagnosticIntegrity
  public let completeness: RunLedgerDiagnosticCompleteness

  public init(
    runID: LedgerRunID,
    recordedRange: RunLedgerSequenceRange,
    integrity: RunLedgerDiagnosticIntegrity,
    completeness: RunLedgerDiagnosticCompleteness
  ) {
    self.runID = runID
    self.recordedRange = recordedRange
    self.integrity = integrity
    self.completeness = completeness
  }
}

public enum EpisodeRecordingChannelRecord: Codable, Hashable, Sendable {
  case controller(ControllerTranscriptRecord)
  case camera(CameraRecordingRecord)
  case runLedgerDiagnostic(RunLedgerDiagnosticReference)
}

public struct EpisodeRecordingEntry: Codable, Hashable, Sendable {
  public let sequence: UInt64
  public let monotonicOffsetNanoseconds: UInt64
  public let provenance: EpisodeRecordingProvenance
  public let record: EpisodeRecordingChannelRecord

  public init(
    sequence: UInt64,
    monotonicOffsetNanoseconds: UInt64,
    provenance: EpisodeRecordingProvenance = .unattributed,
    record: EpisodeRecordingChannelRecord
  ) {
    self.sequence = sequence
    self.monotonicOffsetNanoseconds = monotonicOffsetNanoseconds
    self.provenance = provenance
    self.record = record
  }
}

public struct EpisodeRecordingClose: Codable, Hashable, Sendable {
  public let monotonicOffsetNanoseconds: UInt64

  public init(monotonicOffsetNanoseconds: UInt64) {
    self.monotonicOffsetNanoseconds = monotonicOffsetNanoseconds
  }
}

public enum EpisodeRecordingCompletenessIssue: Codable, Hashable, Sendable {
  case controllerCompletionMissing(ControllerInvocationID)
  case cameraStartIncomplete(CameraStreamIdentity)
  case cameraReconfigurationIncomplete(
    previous: CameraStreamIdentity,
    requested: CameraStreamIdentity
  )
  case cameraStopIncomplete(CameraStreamIdentity)
  case runLedgerIntegrityIncomplete(LedgerRunID)
  case runLedgerRangeIncomplete(
    runID: LedgerRunID,
    missingRanges: [RunLedgerSequenceRange]
  )
  case frameBytesMissing(ContentAddressedFrameReference)
  case frameBytesTruncated(reference: ContentAddressedFrameReference, actualByteCount: Int)
  case frameByteCountMismatch(reference: ContentAddressedFrameReference, actualByteCount: Int)
  case frameHashMismatch(reference: ContentAddressedFrameReference, actualSHA256: String)
  case frameArtifactUnreadable(ContentAddressedFrameReference)
  case frameArtifactUnsafe(
    reference: ContentAddressedFrameReference,
    reason: FrameArtifactConfinementFailure
  )
  case unreferencedFrameArtifact(ContentAddressedFrameReference)
  case unrecognizedFrameArtifact(relativePath: String)
  case durableFrameArtifactUnreadable(relativePath: String)
  case durableFrameArtifactUnsafe(
    relativePath: String,
    reason: FrameArtifactConfinementFailure
  )
  case durableFrameArtifactHashMismatch(relativePath: String, actualSHA256: String)
  case frameRetentionAccountingOverflow
}

public enum EpisodeRecordingDurability: Codable, Hashable, Sendable {
  case verified
  case uncertain(candidateWasObserved: Bool)
}

public enum FrameArtifactConfinementFailure: String, Codable, Hashable, Sendable {
  case symbolicLink
  case notOwnedByCurrentUser
  case externalHardLinks
  case unsafePermissions
}

public struct EpisodeRecordingSnapshot: Codable, Hashable, Sendable {
  public let formatVersion: UInt64
  public let recordingID: EpisodeRecordingID
  public let schemaRevision: EpisodeRecordingSchemaRevision
  public let frameRetentionPolicy: EpisodeFrameRetentionPolicy
  public let entries: [EpisodeRecordingEntry]
  public let close: EpisodeRecordingClose?
  public let durability: EpisodeRecordingDurability
  public let completenessIssues: [EpisodeRecordingCompletenessIssue]

  public var isClosed: Bool { close != nil }
  public var isComplete: Bool { completenessIssues.isEmpty }

  public init(
    formatVersion: UInt64,
    recordingID: EpisodeRecordingID,
    schemaRevision: EpisodeRecordingSchemaRevision,
    frameRetentionPolicy: EpisodeFrameRetentionPolicy,
    entries: [EpisodeRecordingEntry],
    close: EpisodeRecordingClose?,
    durability: EpisodeRecordingDurability,
    completenessIssues: [EpisodeRecordingCompletenessIssue]
  ) {
    self.formatVersion = formatVersion
    self.recordingID = recordingID
    self.schemaRevision = schemaRevision
    self.frameRetentionPolicy = frameRetentionPolicy
    self.entries = entries
    self.close = close
    self.durability = durability
    self.completenessIssues = completenessIssues
  }
}

public enum EpisodeRecordingError: Error, Equatable, Sendable {
  case destinationDirectoryMissing
  case destinationIsNotDirectory
  case manifestIsDirectory
  case readFailed
  case writeFailed
  case corruptEnvelope
  case unsupportedFormatVersion(expected: UInt64, actual: UInt64)
  case schemaRevisionMismatch(
    expected: EpisodeRecordingSchemaRevision,
    actual: EpisodeRecordingSchemaRevision
  )
  case recordingIDMismatch(expected: EpisodeRecordingID, actual: EpisodeRecordingID)
  case frameRetentionPolicyMismatch(
    expected: EpisodeFrameRetentionPolicy,
    actual: EpisodeFrameRetentionPolicy
  )
  case invalidFrameRetentionPolicy(EpisodeFrameRetentionPolicy)
  case frameRetentionLimitExceeded(
    policy: EpisodeFrameRetentionPolicy,
    currentUniqueFrameCount: Int,
    currentUniqueFrameBytes: Int,
    proposedUniqueFrameBytes: Int
  )
  case frameRetentionAccountingOverflow
  case payloadChecksumMismatch
  case corruptRecording
  case sequenceMismatch(index: Int, expected: UInt64, actual: UInt64)
  case monotonicOffsetRegression(previous: UInt64, actual: UInt64)
  case invalidControllerInvocation(ControllerInvocationID)
  case duplicateControllerInvocation(ControllerInvocationID)
  case controllerCompletionWithoutInvocation(ControllerInvocationID)
  case duplicateControllerCompletion(ControllerInvocationID)
  case controllerOperationMismatch(ControllerInvocationID)
  case invalidControllerPartialResult(ControllerInvocationID)
  case invalidCameraLifecycleTransition(CameraLifecycleRecord)
  case cameraFrameOutsideActiveLifecycle(
    frameID: CameraFrameIdentity,
    stream: CameraStreamIdentity
  )
  case invalidCameraFrame(CameraFrameIdentity)
  case duplicateCameraFrameIdentity(CameraFrameIdentity)
  case invalidFrameReference(ContentAddressedFrameReference)
  case invalidRunLedgerDiagnosticReference(LedgerRunID)
  case closed
  case alreadyClosed
  case requiresReopenAfterDurabilityUncertainty
  case concurrentWriterConflict
  case lockOpenFailed
  case lockAcquisitionFailed
  case temporaryFileCreationFailed(code: Int32)
  case temporaryFileWriteFailed(code: Int32)
  case temporaryFileSynchronizationFailed(code: Int32)
  case temporaryFileCloseFailed(code: Int32)
  case atomicReplacementFailed(code: Int32)
  case directorySynchronizationFailed(code: Int32)
  case postRenameDirectorySynchronizationUncertain(code: Int32)
  case frameBytesMissing(ContentAddressedFrameReference)
  case frameBytesTruncated(reference: ContentAddressedFrameReference, actualByteCount: Int)
  case frameByteCountMismatch(reference: ContentAddressedFrameReference, actualByteCount: Int)
  case frameHashMismatch(reference: ContentAddressedFrameReference, actualSHA256: String)
  case frameArtifactUnreadable(ContentAddressedFrameReference)
  case frameArtifactUnsafe(
    reference: ContentAddressedFrameReference,
    reason: FrameArtifactConfinementFailure
  )
  case recordingRootUnsafe(FrameArtifactConfinementFailure)
  case framesDirectoryUnsafe(FrameArtifactConfinementFailure)
  case manifestUnsafe(FrameArtifactConfinementFailure)
  case initializationMarkerMissing
  case initializationMarkerCorrupt
  case manifestMissingAfterInitialization
  case unrecognizedRecordingDirectory
}
