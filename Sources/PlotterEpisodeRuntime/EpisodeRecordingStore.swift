import Foundation

/// An unbound, serialized recording service. It records typed runtime facts but
/// does not interpret them as semantic events, evidence, or execution authority.
public actor EpisodeRecordingStore {
  public static let currentFormatVersion: UInt64 = 1

  private let persistence: EpisodeRecordingPersistence
  private var document: EpisodeRecordingDocument
  private var durability: EpisodeRecordingDurability

  private init(
    persistence: EpisodeRecordingPersistence,
    document: EpisodeRecordingDocument,
    durability: EpisodeRecordingDurability = .verified
  ) {
    self.persistence = persistence
    self.document = document
    self.durability = durability
  }

  /// Opens an existing recording or an empty recording at a pre-provisioned
  /// directory. A closed recording reopens read-only and cannot accept records.
  public static func open(
    directoryURL: URL,
    recordingID: EpisodeRecordingID,
    schemaRevision: EpisodeRecordingSchemaRevision,
    frameRetentionPolicy: EpisodeFrameRetentionPolicy
  ) throws -> EpisodeRecordingStore {
    try open(
      directoryURL: directoryURL,
      recordingID: recordingID,
      schemaRevision: schemaRevision,
      frameRetentionPolicy: frameRetentionPolicy,
      persistenceFault: .none
    )
  }

  static func open(
    directoryURL: URL,
    recordingID: EpisodeRecordingID,
    schemaRevision: EpisodeRecordingSchemaRevision,
    frameRetentionPolicy: EpisodeFrameRetentionPolicy,
    persistenceFault: EpisodeRecordingPersistenceFault
  ) throws -> EpisodeRecordingStore {
    try validate(frameRetentionPolicy)
    let persistence = try EpisodeRecordingPersistence(
      directoryURL: directoryURL,
      fault: persistenceFault
    )
    let initial = EpisodeRecordingDocument(
      formatVersion: currentFormatVersion,
      recordingID: recordingID,
      schemaRevision: schemaRevision,
      frameRetentionPolicy: frameRetentionPolicy,
      entries: [],
      close: nil
    )
    let document = try persistence.loadOrInitialize(initial)
    guard document.recordingID == recordingID else {
      throw EpisodeRecordingError.recordingIDMismatch(
        expected: recordingID,
        actual: document.recordingID
      )
    }
    guard document.schemaRevision == schemaRevision else {
      throw EpisodeRecordingError.schemaRevisionMismatch(
        expected: schemaRevision,
        actual: document.schemaRevision
      )
    }
    guard document.frameRetentionPolicy == frameRetentionPolicy else {
      throw EpisodeRecordingError.frameRetentionPolicyMismatch(
        expected: frameRetentionPolicy,
        actual: document.frameRetentionPolicy
      )
    }
    try validate(document)
    return EpisodeRecordingStore(persistence: persistence, document: document)
  }

  public func snapshot() -> EpisodeRecordingSnapshot {
    EpisodeRecordingSnapshot(
      formatVersion: document.formatVersion,
      recordingID: document.recordingID,
      schemaRevision: document.schemaRevision,
      frameRetentionPolicy: document.frameRetentionPolicy,
      entries: document.entries,
      close: document.close,
      durability: durability,
      completenessIssues: completenessIssues(in: document, persistence: persistence)
    )
  }

  @discardableResult
  public func recordControllerInvocation(
    _ invocation: ControllerInvocation,
    at monotonicOffsetNanoseconds: UInt64,
    provenance: EpisodeRecordingProvenance = .unattributed
  ) throws -> EpisodeRecordingEntry {
    try append(
      .controller(.invocation(invocation)),
      at: monotonicOffsetNanoseconds,
      provenance: provenance
    )
  }

  @discardableResult
  public func recordControllerCompletion(
    _ completion: ControllerCompletion,
    at monotonicOffsetNanoseconds: UInt64,
    provenance: EpisodeRecordingProvenance = .unattributed
  ) throws -> EpisodeRecordingEntry {
    try append(
      .controller(.completion(completion)),
      at: monotonicOffsetNanoseconds,
      provenance: provenance
    )
  }

  @discardableResult
  public func recordCameraLifecycle(
    _ lifecycle: CameraLifecycleRecord,
    at monotonicOffsetNanoseconds: UInt64,
    provenance: EpisodeRecordingProvenance = .unattributed
  ) throws -> EpisodeRecordingEntry {
    try append(
      .camera(.lifecycle(lifecycle)),
      at: monotonicOffsetNanoseconds,
      provenance: provenance
    )
  }

  @discardableResult
  public func recordRunLedgerDiagnosticReference(
    _ reference: RunLedgerDiagnosticReference,
    at monotonicOffsetNanoseconds: UInt64,
    provenance: EpisodeRecordingProvenance = .unattributed
  ) throws -> EpisodeRecordingEntry {
    try append(
      .runLedgerDiagnostic(reference),
      at: monotonicOffsetNanoseconds,
      provenance: provenance
    )
  }

  /// Durably installs and verifies the exact bytes before publishing their
  /// typed reference in the ordered recording. A failed manifest append can
  /// leave only an unreferenced content-addressed artifact, never a record that
  /// acknowledges missing or unverifiable bytes.
  @discardableResult
  public func recordCameraFrame(
    _ descriptor: CameraFrameDescriptor,
    bytes: Data,
    at monotonicOffsetNanoseconds: UInt64,
    provenance: EpisodeRecordingProvenance = .unattributed
  ) throws -> EpisodeRecordingEntry {
    try requireVerifiedDurability()
    guard document.close == nil else { throw EpisodeRecordingError.closed }
    try validate(descriptor)
    try validate(bytes, for: descriptor)
    let reference = persistence.reference(for: bytes)
    let lifecycle = try cameraLifecycleState(in: document)
    guard lifecycle.isActive(descriptor.stream) else {
      throw EpisodeRecordingError.cameraFrameOutsideActiveLifecycle(
        frameID: descriptor.frameID,
        stream: descriptor.stream
      )
    }
    if let previous = document.entries.last?.monotonicOffsetNanoseconds,
       monotonicOffsetNanoseconds < previous {
      throw EpisodeRecordingError.monotonicOffsetRegression(
        previous: previous,
        actual: monotonicOffsetNanoseconds
      )
    }
    let entry = EpisodeRecordingEntry(
      sequence: UInt64(document.entries.count),
      monotonicOffsetNanoseconds: monotonicOffsetNanoseconds,
      provenance: provenance,
      record: .camera(.frameReference(CameraFrameRecord(
        descriptor: descriptor,
        artifact: reference
      )))
    )
    var candidate = document
    candidate.entries.append(entry)
    try validate(candidate, enforceRetention: false)
    try commitFrame(bytes, as: reference, candidate: candidate)
    return entry
  }

  public func frameBytes(for reference: ContentAddressedFrameReference) throws -> Data {
    guard document.entries.contains(where: { entry in
      guard case let .camera(.frameReference(frame)) = entry.record else { return false }
      return frame.artifact == reference
    }) else {
      throw EpisodeRecordingError.invalidFrameReference(reference)
    }
    return try persistence.loadFrame(reference)
  }

  /// Durably closes admission. Completeness remains independently inspectable:
  /// closing never manufactures absent controller completions, camera stops, or
  /// frame bytes.
  public func close(at monotonicOffsetNanoseconds: UInt64) throws {
    try requireVerifiedDurability()
    guard document.close == nil else { throw EpisodeRecordingError.alreadyClosed }
    if let previous = document.entries.last?.monotonicOffsetNanoseconds,
       monotonicOffsetNanoseconds < previous {
      throw EpisodeRecordingError.monotonicOffsetRegression(
        previous: previous,
        actual: monotonicOffsetNanoseconds
      )
    }
    var candidate = document
    candidate.close = EpisodeRecordingClose(
      monotonicOffsetNanoseconds: monotonicOffsetNanoseconds
    )
    try commit(candidate)
  }

  private func append(
    _ record: EpisodeRecordingChannelRecord,
    at monotonicOffsetNanoseconds: UInt64,
    provenance: EpisodeRecordingProvenance
  ) throws -> EpisodeRecordingEntry {
    try requireVerifiedDurability()
    guard document.close == nil else { throw EpisodeRecordingError.closed }
    if let previous = document.entries.last?.monotonicOffsetNanoseconds,
       monotonicOffsetNanoseconds < previous {
      throw EpisodeRecordingError.monotonicOffsetRegression(
        previous: previous,
        actual: monotonicOffsetNanoseconds
      )
    }
    let entry = EpisodeRecordingEntry(
      sequence: UInt64(document.entries.count),
      monotonicOffsetNanoseconds: monotonicOffsetNanoseconds,
      provenance: provenance,
      record: record
    )
    var candidate = document
    candidate.entries.append(entry)
    try validate(candidate)
    try commit(candidate)
    return entry
  }

  private func requireVerifiedDurability() throws {
    guard durability == .verified else {
      throw EpisodeRecordingError.requiresReopenAfterDurabilityUncertainty
    }
  }

  private func commit(_ candidate: EpisodeRecordingDocument) throws {
    do {
      try persistence.commit(candidate, replacing: document)
      document = candidate
    } catch let error as EpisodeRecordingError {
      guard case .postRenameDirectorySynchronizationUncertain = error else { throw error }
      var candidateWasObserved = false
      if let reloaded = try? persistence.load(), reloaded == candidate {
        document = candidate
        candidateWasObserved = true
      }
      durability = .uncertain(candidateWasObserved: candidateWasObserved)
      throw error
    }
  }

  private func commitFrame(
    _ bytes: Data,
    as reference: ContentAddressedFrameReference,
    candidate: EpisodeRecordingDocument
  ) throws {
    do {
      try persistence.commitFrame(
        bytes,
        as: reference,
        candidate: candidate,
        replacing: document
      )
      document = candidate
    } catch let error as EpisodeRecordingError {
      guard case .postRenameDirectorySynchronizationUncertain = error else { throw error }
      var candidateWasObserved = false
      if let reloaded = try? persistence.load(), reloaded == candidate {
        document = candidate
        candidateWasObserved = true
      }
      durability = .uncertain(candidateWasObserved: candidateWasObserved)
      throw error
    }
  }
}

struct EpisodeRecordingDocument: Codable, Hashable {
  let formatVersion: UInt64
  let recordingID: EpisodeRecordingID
  let schemaRevision: EpisodeRecordingSchemaRevision
  let frameRetentionPolicy: EpisodeFrameRetentionPolicy
  var entries: [EpisodeRecordingEntry]
  var close: EpisodeRecordingClose?
}

private func validate(
  _ document: EpisodeRecordingDocument,
  enforceRetention: Bool = true
) throws {
  guard document.formatVersion == EpisodeRecordingStore.currentFormatVersion else {
    throw EpisodeRecordingError.unsupportedFormatVersion(
      expected: EpisodeRecordingStore.currentFormatVersion,
      actual: document.formatVersion
    )
  }
  guard !document.schemaRevision.rawValue.isEmpty else {
    throw EpisodeRecordingError.corruptRecording
  }
  try validate(document.frameRetentionPolicy)

  var previousOffset: UInt64?
  var invocations: [ControllerInvocationID: ControllerOperationInvocation] = [:]
  var invocationOffsets: [ControllerInvocationID: UInt64] = [:]
  var completions = Set<ControllerInvocationID>()
  var frameIdentities = Set<CameraFrameIdentity>()
  var cameraLifecycle = CameraLifecycleState()
  for (index, entry) in document.entries.enumerated() {
    let expectedSequence = UInt64(index)
    guard entry.sequence == expectedSequence else {
      throw EpisodeRecordingError.sequenceMismatch(
        index: index,
        expected: expectedSequence,
        actual: entry.sequence
      )
    }
    if let previousOffset, entry.monotonicOffsetNanoseconds < previousOffset {
      throw EpisodeRecordingError.monotonicOffsetRegression(
        previous: previousOffset,
        actual: entry.monotonicOffsetNanoseconds
      )
    }
    previousOffset = entry.monotonicOffsetNanoseconds

    switch entry.record {
    case let .controller(.invocation(invocation)):
      guard invocations[invocation.id] == nil else {
        throw EpisodeRecordingError.duplicateControllerInvocation(invocation.id)
      }
      try validate(invocation)
      invocations[invocation.id] = invocation.operation
      invocationOffsets[invocation.id] = entry.monotonicOffsetNanoseconds
    case let .controller(.completion(completion)):
      guard let operation = invocations[completion.invocationID],
            let invocationOffset = invocationOffsets[completion.invocationID] else {
        throw EpisodeRecordingError.controllerCompletionWithoutInvocation(
          completion.invocationID
        )
      }
      guard completions.insert(completion.invocationID).inserted else {
        throw EpisodeRecordingError.duplicateControllerCompletion(completion.invocationID)
      }
      try validate(
        completion,
        for: operation,
        invocationOffset: invocationOffset,
        completionOffset: entry.monotonicOffsetNanoseconds
      )
    case let .camera(.frameReference(frame)):
      try validate(frame.descriptor)
      try validate(frame.artifact)
      try validateByteCount(frame.artifact.byteCount, for: frame.descriptor)
      guard cameraLifecycle.isActive(frame.descriptor.stream) else {
        throw EpisodeRecordingError.cameraFrameOutsideActiveLifecycle(
          frameID: frame.descriptor.frameID,
          stream: frame.descriptor.stream
        )
      }
      guard frameIdentities.insert(frame.descriptor.frameID).inserted else {
        throw EpisodeRecordingError.duplicateCameraFrameIdentity(frame.descriptor.frameID)
      }
    case let .camera(.lifecycle(lifecycle)):
      try cameraLifecycle.consume(lifecycle)
    case let .runLedgerDiagnostic(reference):
      try validate(reference)
    }
  }

  if let close = document.close,
     let previousOffset,
     close.monotonicOffsetNanoseconds < previousOffset {
    throw EpisodeRecordingError.monotonicOffsetRegression(
      previous: previousOffset,
      actual: close.monotonicOffsetNanoseconds
    )
  }
  if enforceRetention { try validateRetentionState(document) }
}

private func validate(_ policy: EpisodeFrameRetentionPolicy) throws {
  guard policy.maximumUniqueFrameCount > 0,
        policy.maximumTotalUniqueFrameBytes > 0 else {
    throw EpisodeRecordingError.invalidFrameRetentionPolicy(policy)
  }
}

private func validateRetentionState(_ document: EpisodeRecordingDocument) throws {
  var unique: [String: Int] = [:]
  for entry in document.entries {
    guard case let .camera(.frameReference(frame)) = entry.record else { continue }
    if let existing = unique[frame.artifact.contentSHA256],
       existing != frame.artifact.byteCount {
      throw EpisodeRecordingError.corruptRecording
    }
    unique[frame.artifact.contentSHA256] = frame.artifact.byteCount
  }
  guard let totalBytes = EpisodeFrameRetentionAccounting.checkedSum(unique.values) else {
    throw EpisodeRecordingError.corruptRecording
  }
  guard unique.count <= document.frameRetentionPolicy.maximumUniqueFrameCount,
        totalBytes <= document.frameRetentionPolicy.maximumTotalUniqueFrameBytes else {
    throw EpisodeRecordingError.corruptRecording
  }
}

private func validate(_ reference: RunLedgerDiagnosticReference) throws {
  guard valid(reference.recordedRange) else {
    throw EpisodeRecordingError.invalidRunLedgerDiagnosticReference(reference.runID)
  }
  if case let .payloadCorruption(sequence) = reference.integrity,
     !(reference.recordedRange.first...reference.recordedRange.last).contains(sequence) {
    throw EpisodeRecordingError.invalidRunLedgerDiagnosticReference(reference.runID)
  }
  if case let .incomplete(missingRanges) = reference.completeness {
    guard !missingRanges.isEmpty,
          missingRanges.allSatisfy({ range in
            valid(range)
              && range.first >= reference.recordedRange.first
              && range.last <= reference.recordedRange.last
          }) else {
      throw EpisodeRecordingError.invalidRunLedgerDiagnosticReference(reference.runID)
    }
  }
}

private func valid(_ range: RunLedgerSequenceRange) -> Bool {
  range.first >= 0 && range.last >= range.first
}

private func validate(_ invocation: ControllerInvocation) throws {
  switch invocation.operation {
  case let .open(parameters):
    guard !parameters.endpoint.isEmpty,
          parameters.baudRate > 0,
          parameters.dataBits > 0,
          parameters.stopBits > 0 else {
      throw EpisodeRecordingError.invalidControllerInvocation(invocation.id)
    }
  case let .timedRead(parameters):
    guard parameters.maximumByteCount > 0 else {
      throw EpisodeRecordingError.invalidControllerInvocation(invocation.id)
    }
  case .close, .discardInput, .rawWrite:
    break
  }
}

private func validate(
  _ completion: ControllerCompletion,
  for invocation: ControllerOperationInvocation,
  invocationOffset: UInt64,
  completionOffset: UInt64
) throws {
  switch completion.outcome {
  case let .succeeded(success):
    switch (invocation, success) {
    case (.open, .open), (.close, .close):
      return
    case let (.discardInput, .discardInput(discardedByteCount)):
      guard discardedByteCount >= 0 else {
        throw EpisodeRecordingError.invalidControllerPartialResult(completion.invocationID)
      }
    case let (.rawWrite(parameters), .rawWrite(writtenByteCount)):
      guard writtenByteCount == parameters.bytes.count else {
        throw EpisodeRecordingError.invalidControllerPartialResult(completion.invocationID)
      }
    case let (.timedRead(parameters), .timedRead(chunks, _)):
      try validateReadChunks(
        chunks,
        maximumByteCount: parameters.maximumByteCount,
        completionID: completion.invocationID,
        invocationOffset: invocationOffset,
        completionOffset: completionOffset
      )
    default:
      throw EpisodeRecordingError.controllerOperationMismatch(completion.invocationID)
    }
  case let .failed(failure):
    guard failure.partialByteCount >= 0 else {
      throw EpisodeRecordingError.invalidControllerPartialResult(completion.invocationID)
    }
    switch invocation {
    case .open, .close:
      guard failure.partialByteCount == 0, failure.partialReadChunks.isEmpty else {
        throw EpisodeRecordingError.invalidControllerPartialResult(completion.invocationID)
      }
    case .discardInput:
      guard failure.partialReadChunks.isEmpty else {
        throw EpisodeRecordingError.invalidControllerPartialResult(completion.invocationID)
      }
    case let .rawWrite(parameters):
      guard failure.partialByteCount <= parameters.bytes.count,
            failure.partialReadChunks.isEmpty else {
        throw EpisodeRecordingError.invalidControllerPartialResult(completion.invocationID)
      }
    case let .timedRead(parameters):
      try validateReadChunks(
        failure.partialReadChunks,
        maximumByteCount: parameters.maximumByteCount,
        completionID: completion.invocationID,
        invocationOffset: invocationOffset,
        completionOffset: completionOffset
      )
      guard failure.partialReadChunks.reduce(0, { $0 + $1.bytes.count })
              == failure.partialByteCount else {
        throw EpisodeRecordingError.invalidControllerPartialResult(completion.invocationID)
      }
    }
  }
}

private func validateReadChunks(
  _ chunks: [ControllerReadChunk],
  maximumByteCount: Int,
  completionID: ControllerInvocationID,
  invocationOffset: UInt64,
  completionOffset: UInt64
) throws {
  var previousOffset: UInt64?
  var byteCount = 0
  for chunk in chunks {
    guard !chunk.bytes.isEmpty else {
      throw EpisodeRecordingError.invalidControllerPartialResult(completionID)
    }
    guard chunk.monotonicOffsetNanoseconds >= invocationOffset,
          chunk.monotonicOffsetNanoseconds <= completionOffset else {
      throw EpisodeRecordingError.invalidControllerPartialResult(completionID)
    }
    if let previousOffset,
       chunk.monotonicOffsetNanoseconds < previousOffset {
      throw EpisodeRecordingError.invalidControllerPartialResult(completionID)
    }
    previousOffset = chunk.monotonicOffsetNanoseconds
    byteCount += chunk.bytes.count
  }
  guard byteCount <= maximumByteCount else {
    throw EpisodeRecordingError.invalidControllerPartialResult(completionID)
  }
}

private func validate(_ descriptor: CameraFrameDescriptor) throws {
  guard !descriptor.stream.source.rawValue.isEmpty,
        !descriptor.frameID.rawValue.isEmpty,
        descriptor.width > 0,
        descriptor.height > 0,
        descriptor.rowBytes > 0 else {
    throw EpisodeRecordingError.invalidCameraFrame(descriptor.frameID)
  }
}

private func validate(_ bytes: Data, for descriptor: CameraFrameDescriptor) throws {
  try validateByteCount(bytes.count, for: descriptor)
}

private func validateByteCount(_ byteCount: Int, for descriptor: CameraFrameDescriptor) throws {
  let minimumRowBytes: Int
  switch descriptor.pixelFormat {
  case .bgra8, .rgba8:
    let (value, overflow) = descriptor.width.multipliedReportingOverflow(by: 4)
    guard !overflow else { throw EpisodeRecordingError.invalidCameraFrame(descriptor.frameID) }
    minimumRowBytes = value
  case .gray8:
    minimumRowBytes = descriptor.width
  case .encoded:
    guard byteCount > 0 else {
      throw EpisodeRecordingError.invalidCameraFrame(descriptor.frameID)
    }
    return
  }
  let (expectedByteCount, overflow) = descriptor.rowBytes.multipliedReportingOverflow(
    by: descriptor.height
  )
  guard !overflow,
        descriptor.rowBytes >= minimumRowBytes,
        byteCount == expectedByteCount else {
    throw EpisodeRecordingError.invalidCameraFrame(descriptor.frameID)
  }
}

private func validate(_ reference: ContentAddressedFrameReference) throws {
  let digest = reference.contentSHA256
  guard digest.count == 64,
        digest.allSatisfy({ $0.isHexDigit && !$0.isUppercase }),
        reference.byteCount >= 0,
        reference.relativePath == "frames/\(digest).frame" else {
    throw EpisodeRecordingError.invalidFrameReference(reference)
  }
}

private func completenessIssues(
  in document: EpisodeRecordingDocument,
  persistence: EpisodeRecordingPersistence
) -> [EpisodeRecordingCompletenessIssue] {
  var issues: [EpisodeRecordingCompletenessIssue] = []
  var pendingInvocations = Set<ControllerInvocationID>()
  var cameraLifecycle = CameraLifecycleState()

  for entry in document.entries {
    switch entry.record {
    case let .controller(.invocation(invocation)):
      pendingInvocations.insert(invocation.id)
    case let .controller(.completion(completion)):
      pendingInvocations.remove(completion.invocationID)
    case let .camera(.lifecycle(lifecycle)):
      try? cameraLifecycle.consume(lifecycle)
    case let .camera(.frameReference(frame)):
      if let issue = persistence.frameIssue(frame.artifact) {
        issues.append(issue)
      }
    case let .runLedgerDiagnostic(reference):
      switch reference.integrity {
      case .verified:
        break
      case .notVerified, .payloadCorruption:
        issues.append(.runLedgerIntegrityIncomplete(reference.runID))
      }
      if case let .incomplete(missingRanges) = reference.completeness {
        issues.append(.runLedgerRangeIncomplete(
          runID: reference.runID,
          missingRanges: missingRanges
        ))
      }
    }
  }

  let referencedFrames = Set<ContentAddressedFrameReference>(
    document.entries.compactMap { entry in
    guard case let .camera(.frameReference(frame)) = entry.record else { return nil }
    return frame.artifact
    }
  )
  issues.append(contentsOf: persistence.unreferencedFrameArtifactIssues(
    referenced: referencedFrames
  ))

  issues.append(contentsOf: pendingInvocations
    .sorted { $0.rawValue.uuidString < $1.rawValue.uuidString }
    .map(EpisodeRecordingCompletenessIssue.controllerCompletionMissing))
  issues.append(contentsOf: cameraLifecycle.completenessIssues)
  return issues
}

private struct CameraLifecycleState {
  private var pendingStarts = Set<CameraStreamIdentity>()
  private var activeBySource: [CameraSourceIdentity: CameraStreamIdentity] = [:]
  private var pendingReconfigurations: [CameraSourceIdentity: CameraReconfiguration] = [:]
  private var pendingStops = Set<CameraStreamIdentity>()

  mutating func consume(_ record: CameraLifecycleRecord) throws {
    let streams = streams(in: record)
    guard streams.allSatisfy({ !$0.source.rawValue.isEmpty }) else {
      throw EpisodeRecordingError.invalidCameraLifecycleTransition(record)
    }

    switch record {
    case let .startRequested(stream):
      guard activeBySource[stream.source] == nil,
            !pendingStarts.contains(where: { $0.source == stream.source }),
            pendingReconfigurations[stream.source] == nil,
            !pendingStops.contains(where: { $0.source == stream.source }) else {
        throw EpisodeRecordingError.invalidCameraLifecycleTransition(record)
      }
      pendingStarts.insert(stream)
    case let .started(stream):
      guard pendingStarts.remove(stream) != nil,
            activeBySource[stream.source] == nil else {
        throw EpisodeRecordingError.invalidCameraLifecycleTransition(record)
      }
      activeBySource[stream.source] = stream
    case let .reconfigurationRequested(previous, requested):
      guard previous.source == requested.source,
            previous.configuration != requested.configuration,
            activeBySource[previous.source] == previous,
            pendingReconfigurations[previous.source] == nil,
            !pendingStops.contains(previous),
            !pendingStarts.contains(where: { $0.source == previous.source }) else {
        throw EpisodeRecordingError.invalidCameraLifecycleTransition(record)
      }
      pendingReconfigurations[previous.source] = CameraReconfiguration(
        previous: previous,
        requested: requested
      )
    case let .reconfigured(previous, current):
      let expected = CameraReconfiguration(previous: previous, requested: current)
      guard pendingReconfigurations[previous.source] == expected,
            activeBySource[previous.source] == previous else {
        throw EpisodeRecordingError.invalidCameraLifecycleTransition(record)
      }
      pendingReconfigurations.removeValue(forKey: previous.source)
      activeBySource[previous.source] = current
    case let .stopRequested(stream):
      guard activeBySource[stream.source] == stream,
            pendingReconfigurations[stream.source] == nil,
            !pendingStops.contains(stream) else {
        throw EpisodeRecordingError.invalidCameraLifecycleTransition(record)
      }
      pendingStops.insert(stream)
    case let .stopped(stream):
      guard pendingStops.remove(stream) != nil,
            activeBySource[stream.source] == stream else {
        throw EpisodeRecordingError.invalidCameraLifecycleTransition(record)
      }
      activeBySource.removeValue(forKey: stream.source)
    case let .failed(failure):
      switch failure.operation {
      case let .start(stream):
        guard pendingStarts.remove(stream) != nil else {
          throw EpisodeRecordingError.invalidCameraLifecycleTransition(record)
        }
      case let .reconfigure(previous, requested):
        let expected = CameraReconfiguration(previous: previous, requested: requested)
        guard pendingReconfigurations[previous.source] == expected,
              activeBySource[previous.source] == previous else {
          throw EpisodeRecordingError.invalidCameraLifecycleTransition(record)
        }
        pendingReconfigurations.removeValue(forKey: previous.source)
      case let .stop(stream):
        guard pendingStops.remove(stream) != nil,
              activeBySource[stream.source] == stream else {
          throw EpisodeRecordingError.invalidCameraLifecycleTransition(record)
        }
      }
    }
  }

  func isActive(_ stream: CameraStreamIdentity) -> Bool {
    activeBySource[stream.source] == stream
  }

  var completenessIssues: [EpisodeRecordingCompletenessIssue] {
    var issues = pendingStarts
      .sorted { streamSortKey($0) < streamSortKey($1) }
      .map(EpisodeRecordingCompletenessIssue.cameraStartIncomplete)
    issues.append(contentsOf: pendingReconfigurations.values
      .sorted { streamSortKey($0.previous) < streamSortKey($1.previous) }
      .map { .cameraReconfigurationIncomplete(
        previous: $0.previous,
        requested: $0.requested
      ) })
    issues.append(contentsOf: activeBySource.values
      .sorted { streamSortKey($0) < streamSortKey($1) }
      .map(EpisodeRecordingCompletenessIssue.cameraStopIncomplete))
    return issues
  }
}

private func cameraLifecycleState(
  in document: EpisodeRecordingDocument
) throws -> CameraLifecycleState {
  var state = CameraLifecycleState()
  for entry in document.entries {
    guard case let .camera(.lifecycle(record)) = entry.record else { continue }
    try state.consume(record)
  }
  return state
}

private struct CameraReconfiguration: Equatable {
  let previous: CameraStreamIdentity
  let requested: CameraStreamIdentity
}

private func streams(in record: CameraLifecycleRecord) -> [CameraStreamIdentity] {
  switch record {
  case let .startRequested(stream),
       let .started(stream),
       let .stopRequested(stream),
       let .stopped(stream):
    return [stream]
  case let .reconfigurationRequested(previous, requested),
       let .reconfigured(previous, requested):
    return [previous, requested]
  case let .failed(failure):
    switch failure.operation {
    case let .start(stream), let .stop(stream):
      return [stream]
    case let .reconfigure(previous, requested):
      return [previous, requested]
    }
  }
}

private func streamSortKey(_ stream: CameraStreamIdentity) -> String {
  "\(stream.source.rawValue)|\(stream.configuration.rawValue.uuidString)"
}
