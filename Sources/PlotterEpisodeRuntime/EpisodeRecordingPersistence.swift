import CryptoKit
import Darwin
import Foundation

enum EpisodeRecordingPersistenceFault: Sendable {
  case none
  case manifestDirectorySynchronizationFailureOnce
  case manifestReplacementOutcomeUncertainWithoutInstallOnce
  case manifestPreRenameFailureOnce
  case inventoryAccountingOverflowOnce
  case initializationPauseAfterMarker(signalURL: URL, releaseURL: URL)
  case signalBeforeCommitLock(URL)
  case signalImmediatelyBeforeCommitKernelLock(URL)
}

final class EpisodeRecordingPersistence {
  private static let manifestName = "episode-recording.json"
  private static let markerName = ".episode-recording.initialized"
  private static let lockName = "episode-recording.json.lock"
  private static let framesName = "frames"

  private let root: RootDirectoryDescriptor
  private let inProcessCommitLock: NSLock
  private let faultState: EpisodeRecordingPersistenceFaultState

  init(
    directoryURL: URL,
    fault: EpisodeRecordingPersistenceFault = .none
  ) throws {
    var pathStatus = Darwin.stat()
    let pathResult = directoryURL.standardizedFileURL.path.withCString {
      Darwin.lstat($0, &pathStatus)
    }
    guard pathResult == 0 else {
      if errno == ENOENT { throw EpisodeRecordingError.destinationDirectoryMissing }
      throw EpisodeRecordingError.readFailed
    }
    guard fileType(pathStatus) != S_IFLNK else {
      throw EpisodeRecordingError.recordingRootUnsafe(.symbolicLink)
    }
    guard fileType(pathStatus) == S_IFDIR else {
      throw EpisodeRecordingError.destinationIsNotDirectory
    }

    let descriptor = directoryURL.standardizedFileURL.path.withCString {
      Darwin.open($0, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
    }
    guard descriptor >= 0 else {
      throw EpisodeRecordingError.destinationIsNotDirectory
    }
    do {
      root = try RootDirectoryDescriptor(descriptor: descriptor)
    } catch {
      _ = Darwin.close(descriptor)
      throw error
    }
    inProcessCommitLock = RecordingCommitLocks.lock(for: root.identity)
    faultState = EpisodeRecordingPersistenceFaultState(fault)
    try validateFramesDirectoryIfPresent()
  }

  func reference(for bytes: Data) -> ContentAddressedFrameReference {
    let digest = sha256(bytes)
    return ContentAddressedFrameReference(
      contentSHA256: digest,
      byteCount: bytes.count,
      relativePath: "\(Self.framesName)/\(digest).frame"
    )
  }

  func load() throws -> EpisodeRecordingDocument? {
    let marker = try loadMarker()
    guard let manifestStatus = try relativeFileStatus(
      named: Self.manifestName,
      directoryDescriptor: root.descriptor
    ) else {
      if marker != nil { throw EpisodeRecordingError.manifestMissingAfterInitialization }
      return nil
    }
    guard let marker else { throw EpisodeRecordingError.initializationMarkerMissing }
    let encoded = try readOwnedRegularFile(
      named: Self.manifestName,
      status: manifestStatus,
      directoryDescriptor: root.descriptor,
      unsafeError: { .manifestUnsafe($0) },
      unreadableError: .readFailed
    )
    let envelope: EpisodeRecordingEnvelope
    do {
      envelope = try JSONDecoder().decode(EpisodeRecordingEnvelope.self, from: encoded)
    } catch {
      throw EpisodeRecordingError.corruptEnvelope
    }
    guard envelope.formatVersion == EpisodeRecordingStore.currentFormatVersion else {
      throw EpisodeRecordingError.unsupportedFormatVersion(
        expected: EpisodeRecordingStore.currentFormatVersion,
        actual: envelope.formatVersion
      )
    }
    guard sha256(envelope.recordingPayload) == envelope.payloadSHA256 else {
      throw EpisodeRecordingError.payloadChecksumMismatch
    }
    let document: EpisodeRecordingDocument
    do {
      document = try JSONDecoder().decode(
        EpisodeRecordingDocument.self,
        from: envelope.recordingPayload
      )
    } catch {
      throw EpisodeRecordingError.corruptRecording
    }
    guard marker.recordingID == document.recordingID,
          marker.schemaRevision == document.schemaRevision,
          marker.frameRetentionPolicy == document.frameRetentionPolicy else {
      throw EpisodeRecordingError.initializationMarkerCorrupt
    }
    return document
  }

  func loadOrInitialize(
    _ initial: EpisodeRecordingDocument
  ) throws -> EpisodeRecordingDocument {
    try withExclusiveCommitLock {
      if let existing = try load() { return existing }
      let contents = try directoryEntryNames(in: root.descriptor).filter {
        $0 != Self.lockName
      }
      guard contents.isEmpty else {
        throw EpisodeRecordingError.unrecognizedRecordingDirectory
      }

      let marker = EpisodeRecordingInitializationMarker(
        recordingID: initial.recordingID,
        schemaRevision: initial.schemaRevision,
        frameRetentionPolicy: initial.frameRetentionPolicy
      )
      try durablyReplaceRelativeFile(
        named: Self.markerName,
        in: root.descriptor,
        with: try encodeMarker(marker),
        fault: .none
      )
      try faultState.pauseAfterInitializationMarkerIfRequested()
      try durablyReplaceRelativeFile(
        named: Self.manifestName,
        in: root.descriptor,
        with: try encodeDocument(initial),
        fault: .none
      )
      guard let loaded = try load() else {
        throw EpisodeRecordingError.manifestMissingAfterInitialization
      }
      return loaded
    }
  }

  func commit(
    _ candidate: EpisodeRecordingDocument,
    replacing expected: EpisodeRecordingDocument
  ) throws {
    let encoded = try encodeDocument(candidate)
    try withExclusiveCommitLock(signalCommitKernelLockBoundary: true) {
      guard try load() == expected else {
        throw EpisodeRecordingError.concurrentWriterConflict
      }
      try durablyReplaceRelativeFile(
        named: Self.manifestName,
        in: root.descriptor,
        with: encoded,
        fault: faultState.consumeManifestFault()
      )
    }
  }

  func commitFrame(
    _ bytes: Data,
    as reference: ContentAddressedFrameReference,
    candidate: EpisodeRecordingDocument,
    replacing expected: EpisodeRecordingDocument
  ) throws {
    let encoded = try encodeDocument(candidate)
    try withExclusiveCommitLock(signalCommitKernelLockBoundary: true) {
      guard try load() == expected else {
        throw EpisodeRecordingError.concurrentWriterConflict
      }
      let inventory = try frameArtifactInventory()
      try enforceRetention(
        adding: reference,
        to: inventory,
        policy: candidate.frameRetentionPolicy
      )
      try storeFrameUnlocked(bytes, as: reference)
      try durablyReplaceRelativeFile(
        named: Self.manifestName,
        in: root.descriptor,
        with: encoded,
        fault: faultState.consumeManifestFault()
      )
    }
  }

  private func storeFrameUnlocked(
    _ bytes: Data,
    as reference: ContentAddressedFrameReference
  ) throws {
    let framesDescriptor = try openFramesDirectory(creatingIfMissing: true)
    defer { _ = Darwin.close(framesDescriptor) }
    let filename = frameFilename(reference)
    if try relativeFileStatus(named: filename, directoryDescriptor: framesDescriptor) != nil {
      let existing = try loadFrame(reference, directoryDescriptor: framesDescriptor)
      guard existing == bytes else {
        throw EpisodeRecordingError.frameHashMismatch(
          reference: reference,
          actualSHA256: sha256(existing)
        )
      }
      return
    }

    let temporaryName = ".\(filename).\(UUID().uuidString).tmp"
    let descriptor = temporaryName.withCString {
      Darwin.openat(
        framesDescriptor,
        $0,
        O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC,
        mode_t(S_IRUSR)
      )
    }
    guard descriptor >= 0 else {
      throw EpisodeRecordingError.temporaryFileCreationFailed(code: errno)
    }
    var descriptorIsOpen = true
    var temporaryIsNamed = true
    defer {
      if descriptorIsOpen { _ = Darwin.close(descriptor) }
      if temporaryIsNamed {
        temporaryName.withCString { _ = Darwin.unlinkat(framesDescriptor, $0, 0) }
      }
    }
    try writeAll(bytes, to: descriptor)
    try synchronizeFile(descriptor)
    guard Darwin.close(descriptor) == 0 else {
      descriptorIsOpen = false
      throw EpisodeRecordingError.temporaryFileCloseFailed(code: errno)
    }
    descriptorIsOpen = false

    let linkResult = temporaryName.withCString { source in
      filename.withCString { destination in
        Darwin.linkat(framesDescriptor, source, framesDescriptor, destination, 0)
      }
    }
    if linkResult == -1 && errno == EEXIST {
      temporaryName.withCString { _ = Darwin.unlinkat(framesDescriptor, $0, 0) }
      temporaryIsNamed = false
      let existing = try loadFrame(reference, directoryDescriptor: framesDescriptor)
      guard existing == bytes else {
        throw EpisodeRecordingError.frameHashMismatch(
          reference: reference,
          actualSHA256: sha256(existing)
        )
      }
      return
    }
    guard linkResult == 0 else {
      throw EpisodeRecordingError.atomicReplacementFailed(code: errno)
    }
    guard temporaryName.withCString({ Darwin.unlinkat(framesDescriptor, $0, 0) }) == 0 else {
      throw EpisodeRecordingError.frameArtifactUnsafe(
        reference: reference,
        reason: .externalHardLinks
      )
    }
    temporaryIsNamed = false
    try synchronizeDirectoryDescriptor(framesDescriptor)
    _ = try loadFrame(reference, directoryDescriptor: framesDescriptor)
  }

  func loadFrame(_ reference: ContentAddressedFrameReference) throws -> Data {
    let framesDescriptor: Int32
    do {
      framesDescriptor = try openFramesDirectory(creatingIfMissing: false)
    } catch EpisodeRecordingError.destinationDirectoryMissing {
      throw EpisodeRecordingError.frameBytesMissing(reference)
    }
    defer { _ = Darwin.close(framesDescriptor) }
    return try loadFrame(reference, directoryDescriptor: framesDescriptor)
  }

  func frameIssue(
    _ reference: ContentAddressedFrameReference
  ) -> EpisodeRecordingCompletenessIssue? {
    do {
      _ = try loadFrame(reference)
      return nil
    } catch let error as EpisodeRecordingError {
      switch error {
      case .frameBytesMissing:
        return .frameBytesMissing(reference)
      case let .frameBytesTruncated(_, actualByteCount):
        return .frameBytesTruncated(reference: reference, actualByteCount: actualByteCount)
      case let .frameByteCountMismatch(_, actualByteCount):
        return .frameByteCountMismatch(reference: reference, actualByteCount: actualByteCount)
      case let .frameHashMismatch(_, actualSHA256):
        return .frameHashMismatch(reference: reference, actualSHA256: actualSHA256)
      case .frameArtifactUnreadable:
        return .frameArtifactUnreadable(reference)
      case let .frameArtifactUnsafe(_, reason):
        return .frameArtifactUnsafe(reference: reference, reason: reason)
      case let .framesDirectoryUnsafe(reason):
        return .frameArtifactUnsafe(reference: reference, reason: reason)
      default:
        return .frameArtifactUnreadable(reference)
      }
    } catch {
      return .frameArtifactUnreadable(reference)
    }
  }

  func unreferencedFrameArtifactIssues(
    referenced: Set<ContentAddressedFrameReference>
  ) -> [EpisodeRecordingCompletenessIssue] {
    let referencedPaths = Set(referenced.map(\.relativePath))
    do {
      let inventory = try frameArtifactInventory()
      guard inventory.totalBytes != nil else {
        throw EpisodeRecordingError.frameRetentionAccountingOverflow
      }
      return inventory.artifacts.compactMap { artifact in
        guard !referencedPaths.contains(artifact.relativePath) else { return nil }
        switch artifact.classification {
        case let .valid(reference):
          return .unreferencedFrameArtifact(reference)
        case .unrecognized:
          return .unrecognizedFrameArtifact(relativePath: artifact.relativePath)
        case .unreadable:
          return .durableFrameArtifactUnreadable(relativePath: artifact.relativePath)
        case let .unsafe(reason):
          return .durableFrameArtifactUnsafe(
            relativePath: artifact.relativePath,
            reason: reason
          )
        case let .hashMismatch(actualSHA256):
          return .durableFrameArtifactHashMismatch(
            relativePath: artifact.relativePath,
            actualSHA256: actualSHA256
          )
        }
      }
    } catch let error as EpisodeRecordingError {
      if case .frameRetentionAccountingOverflow = error {
        return [.frameRetentionAccountingOverflow]
      }
      if case let .framesDirectoryUnsafe(reason) = error {
        return [.durableFrameArtifactUnsafe(
          relativePath: Self.framesName,
          reason: reason
        )]
      }
      return [.durableFrameArtifactUnreadable(relativePath: Self.framesName)]
    } catch {
      return [.durableFrameArtifactUnreadable(relativePath: Self.framesName)]
    }
  }

  private func frameArtifactInventory() throws -> DurableFrameArtifactInventory {
    let framesDescriptor: Int32
    do {
      framesDescriptor = try openFramesDirectory(creatingIfMissing: false)
    } catch EpisodeRecordingError.destinationDirectoryMissing {
      return DurableFrameArtifactInventory(artifacts: [])
    }
    defer { _ = Darwin.close(framesDescriptor) }

    var artifacts: [DurableFrameArtifact] = []
    for filename in try directoryEntryNames(in: framesDescriptor).sorted() {
      let relativePath = "\(Self.framesName)/\(filename)"
      guard let status = try relativeFileStatus(
        named: filename,
        directoryDescriptor: framesDescriptor
      ) else { continue }
      guard status.st_size >= 0,
            let chargedByteCount = Int(exactly: status.st_size) else {
        throw EpisodeRecordingError.frameRetentionAccountingOverflow
      }
      let classification: DurableFrameArtifactClassification
      if fileType(status) == S_IFLNK {
        classification = .unsafe(.symbolicLink)
      } else if fileType(status) != S_IFREG {
        classification = .unreadable
      } else if status.st_uid != Darwin.geteuid() {
        classification = .unsafe(.notOwnedByCurrentUser)
      } else if status.st_nlink != 1 {
        classification = .unsafe(.externalHardLinks)
      } else if status.st_mode & mode_t(0o777) != mode_t(S_IRUSR) {
        classification = .unsafe(.unsafePermissions)
      } else if !isValidFrameFilename(filename) {
        classification = .unrecognized
      } else {
        let digest = String(filename.dropLast(".frame".count))
        do {
          let bytes = try readOwnedRegularFile(
            named: filename,
            status: status,
            directoryDescriptor: framesDescriptor,
            unsafeError: { reason in
              .frameArtifactUnsafe(
                reference: ContentAddressedFrameReference(
                  contentSHA256: digest,
                  byteCount: chargedByteCount,
                  relativePath: relativePath
                ),
                reason: reason
              )
            },
            unreadableError: .readFailed
          )
          let actualDigest = sha256(bytes)
          if actualDigest == digest {
            classification = .valid(ContentAddressedFrameReference(
              contentSHA256: digest,
              byteCount: bytes.count,
              relativePath: relativePath
            ))
          } else {
            classification = .hashMismatch(actualSHA256: actualDigest)
          }
        } catch let error as EpisodeRecordingError {
          if case let .frameArtifactUnsafe(_, reason) = error {
            classification = .unsafe(reason)
          } else {
            classification = .unreadable
          }
        } catch {
          classification = .unreadable
        }
      }
      artifacts.append(DurableFrameArtifact(
        relativePath: relativePath,
        chargedByteCount: chargedByteCount,
        classification: classification
      ))
    }
    if faultState.consumeInventoryAccountingOverflowIfRequested() {
      artifacts.append(DurableFrameArtifact(
        relativePath: "frames/.accounting-overflow-a",
        chargedByteCount: Int.max,
        classification: .unrecognized
      ))
      artifacts.append(DurableFrameArtifact(
        relativePath: "frames/.accounting-overflow-b",
        chargedByteCount: 1,
        classification: .unrecognized
      ))
    }
    return DurableFrameArtifactInventory(artifacts: artifacts)
  }

  private func enforceRetention(
    adding reference: ContentAddressedFrameReference,
    to inventory: DurableFrameArtifactInventory,
    policy: EpisodeFrameRetentionPolicy
  ) throws {
    guard let currentBytes = inventory.totalBytes else {
      throw EpisodeRecordingError.frameRetentionAccountingOverflow
    }
    let target = inventory.artifacts.first { $0.relativePath == reference.relativePath }
    if case let .valid(existing)? = target?.classification, existing == reference {
      return
    }
    if target != nil {
      _ = try loadFrame(reference)
      return
    }
    guard let proposedCount = EpisodeFrameRetentionAccounting.checkedIncrement(
      inventory.uniqueCount
    ),
    let proposedBytes = EpisodeFrameRetentionAccounting.checkedAdding(
      currentBytes,
      reference.byteCount
    ) else {
      throw EpisodeRecordingError.frameRetentionAccountingOverflow
    }
    guard proposedCount <= policy.maximumUniqueFrameCount,
          proposedBytes <= policy.maximumTotalUniqueFrameBytes else {
      throw EpisodeRecordingError.frameRetentionLimitExceeded(
        policy: policy,
        currentUniqueFrameCount: inventory.uniqueCount,
        currentUniqueFrameBytes: currentBytes,
        proposedUniqueFrameBytes: reference.byteCount
      )
    }
  }

  private func isValidFrameFilename(_ filename: String) -> Bool {
    guard filename.hasSuffix(".frame") else { return false }
    let digest = filename.dropLast(".frame".count)
    return digest.count == 64
      && digest.allSatisfy { $0.isHexDigit && !$0.isUppercase }
  }

  private func loadMarker() throws -> EpisodeRecordingInitializationMarker? {
    guard let status = try relativeFileStatus(
      named: Self.markerName,
      directoryDescriptor: root.descriptor
    ) else { return nil }
    let encoded = try readOwnedRegularFile(
      named: Self.markerName,
      status: status,
      directoryDescriptor: root.descriptor,
      unsafeError: { .manifestUnsafe($0) },
      unreadableError: .initializationMarkerCorrupt
    )
    let envelope: EpisodeRecordingMarkerEnvelope
    do {
      envelope = try JSONDecoder().decode(EpisodeRecordingMarkerEnvelope.self, from: encoded)
    } catch {
      throw EpisodeRecordingError.initializationMarkerCorrupt
    }
    guard envelope.formatVersion == EpisodeRecordingStore.currentFormatVersion,
          sha256(envelope.markerPayload) == envelope.payloadSHA256 else {
      throw EpisodeRecordingError.initializationMarkerCorrupt
    }
    do {
      return try JSONDecoder().decode(
        EpisodeRecordingInitializationMarker.self,
        from: envelope.markerPayload
      )
    } catch {
      throw EpisodeRecordingError.initializationMarkerCorrupt
    }
  }

  private func encodeMarker(_ marker: EpisodeRecordingInitializationMarker) throws -> Data {
    do {
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.sortedKeys]
      let payload = try encoder.encode(marker)
      return try encoder.encode(EpisodeRecordingMarkerEnvelope(
        formatVersion: EpisodeRecordingStore.currentFormatVersion,
        markerPayload: payload,
        payloadSHA256: sha256(payload)
      ))
    } catch {
      throw EpisodeRecordingError.writeFailed
    }
  }

  private func encodeDocument(_ document: EpisodeRecordingDocument) throws -> Data {
    do {
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.sortedKeys]
      let payload = try encoder.encode(document)
      return try encoder.encode(EpisodeRecordingEnvelope(
        formatVersion: EpisodeRecordingStore.currentFormatVersion,
        recordingPayload: payload,
        payloadSHA256: sha256(payload)
      ))
    } catch {
      throw EpisodeRecordingError.writeFailed
    }
  }

  private func withExclusiveCommitLock<Value>(
    signalCommitKernelLockBoundary: Bool = false,
    _ operation: () throws -> Value
  ) throws -> Value {
    try faultState.signalBeforeCommitLockIfRequested()
    inProcessCommitLock.lock()
    defer { inProcessCommitLock.unlock() }
    let lockDescriptor = Self.lockName.withCString {
      Darwin.openat(
        root.descriptor,
        $0,
        O_CREAT | O_RDWR | O_NOFOLLOW | O_CLOEXEC,
        mode_t(S_IRUSR | S_IWUSR)
      )
    }
    guard lockDescriptor >= 0 else { throw EpisodeRecordingError.lockOpenFailed }
    defer { _ = Darwin.close(lockDescriptor) }
    var status = Darwin.stat()
    guard Darwin.fstat(lockDescriptor, &status) == 0,
          fileType(status) == S_IFREG,
          status.st_uid == Darwin.geteuid(),
          status.st_nlink == 1 else {
      throw EpisodeRecordingError.lockOpenFailed
    }

    var kernelLock = Darwin.flock()
    kernelLock.l_start = 0
    kernelLock.l_len = 0
    kernelLock.l_pid = 0
    kernelLock.l_type = Int16(F_WRLCK)
    kernelLock.l_whence = Int16(SEEK_SET)
    if signalCommitKernelLockBoundary {
      try faultState.signalImmediatelyBeforeCommitKernelLockIfRequested()
    }
    guard Darwin.fcntl(lockDescriptor, F_SETLKW, &kernelLock) != -1 else {
      throw EpisodeRecordingError.lockAcquisitionFailed
    }
    defer {
      kernelLock.l_type = Int16(F_UNLCK)
      _ = Darwin.fcntl(lockDescriptor, F_SETLK, &kernelLock)
    }
    return try operation()
  }

  private func directoryEntryNames(in descriptor: Int32) throws -> [String] {
    let duplicate = Darwin.dup(descriptor)
    guard duplicate >= 0 else { throw EpisodeRecordingError.readFailed }
    guard let directory = Darwin.fdopendir(duplicate) else {
      _ = Darwin.close(duplicate)
      throw EpisodeRecordingError.readFailed
    }
    defer { Darwin.closedir(directory) }
    var names: [String] = []
    while let entry = Darwin.readdir(directory) {
      let name = withUnsafePointer(to: &entry.pointee.d_name) { pointer in
        pointer.withMemoryRebound(to: CChar.self, capacity: 256) {
          String(cString: $0)
        }
      }
      if name != "." && name != ".." { names.append(name) }
    }
    return names
  }

  private func loadFrame(
    _ reference: ContentAddressedFrameReference,
    directoryDescriptor: Int32
  ) throws -> Data {
    let filename = frameFilename(reference)
    guard let status = try relativeFileStatus(
      named: filename,
      directoryDescriptor: directoryDescriptor
    ) else { throw EpisodeRecordingError.frameBytesMissing(reference) }
    guard fileType(status) != S_IFREG
      || status.st_mode & mode_t(0o777) == mode_t(S_IRUSR) else {
      throw EpisodeRecordingError.frameArtifactUnsafe(
        reference: reference,
        reason: .unsafePermissions
      )
    }
    let bytes = try readOwnedRegularFile(
      named: filename,
      status: status,
      directoryDescriptor: directoryDescriptor,
      unsafeError: {
        .frameArtifactUnsafe(reference: reference, reason: $0)
      },
      unreadableError: .frameArtifactUnreadable(reference)
    )
    guard bytes.count >= reference.byteCount else {
      throw EpisodeRecordingError.frameBytesTruncated(
        reference: reference,
        actualByteCount: bytes.count
      )
    }
    guard bytes.count == reference.byteCount else {
      throw EpisodeRecordingError.frameByteCountMismatch(
        reference: reference,
        actualByteCount: bytes.count
      )
    }
    let digest = sha256(bytes)
    guard digest == reference.contentSHA256 else {
      throw EpisodeRecordingError.frameHashMismatch(
        reference: reference,
        actualSHA256: digest
      )
    }
    return bytes
  }

  private func frameFilename(_ reference: ContentAddressedFrameReference) -> String {
    "\(reference.contentSHA256).frame"
  }

  private func validateFramesDirectoryIfPresent() throws {
    guard let status = try relativeFileStatus(
      named: Self.framesName,
      directoryDescriptor: root.descriptor
    ) else { return }
    try validateFramesDirectoryStatus(status)
  }

  private func validateFramesDirectoryStatus(_ status: Darwin.stat) throws {
    guard fileType(status) != S_IFLNK else {
      throw EpisodeRecordingError.framesDirectoryUnsafe(.symbolicLink)
    }
    guard fileType(status) == S_IFDIR else {
      throw EpisodeRecordingError.destinationIsNotDirectory
    }
    guard status.st_uid == Darwin.geteuid() else {
      throw EpisodeRecordingError.framesDirectoryUnsafe(.notOwnedByCurrentUser)
    }
  }

  private func openFramesDirectory(creatingIfMissing: Bool) throws -> Int32 {
    if try relativeFileStatus(
      named: Self.framesName,
      directoryDescriptor: root.descriptor
    ) == nil {
      guard creatingIfMissing else {
        throw EpisodeRecordingError.destinationDirectoryMissing
      }
      let result = Self.framesName.withCString {
        Darwin.mkdirat(root.descriptor, $0, mode_t(S_IRWXU))
      }
      guard result == 0 || errno == EEXIST else {
        throw EpisodeRecordingError.writeFailed
      }
      try synchronizeDirectoryDescriptor(root.descriptor)
    }
    guard let expected = try relativeFileStatus(
      named: Self.framesName,
      directoryDescriptor: root.descriptor
    ) else { throw EpisodeRecordingError.writeFailed }
    try validateFramesDirectoryStatus(expected)
    let descriptor = Self.framesName.withCString {
      Darwin.openat(
        root.descriptor,
        $0,
        O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC
      )
    }
    guard descriptor >= 0 else {
      throw EpisodeRecordingError.destinationIsNotDirectory
    }
    var actual = Darwin.stat()
    guard Darwin.fstat(descriptor, &actual) == 0,
          actual.st_dev == expected.st_dev,
          actual.st_ino == expected.st_ino,
          actual.st_uid == Darwin.geteuid() else {
      _ = Darwin.close(descriptor)
      throw EpisodeRecordingError.framesDirectoryUnsafe(.notOwnedByCurrentUser)
    }
    return descriptor
  }
}

private struct DurableFrameArtifactInventory {
  let artifacts: [DurableFrameArtifact]

  var uniqueCount: Int { artifacts.count }
  var totalBytes: Int? {
    EpisodeFrameRetentionAccounting.checkedSum(artifacts.lazy.map(\.chargedByteCount))
  }
}

private struct DurableFrameArtifact {
  let relativePath: String
  let chargedByteCount: Int
  let classification: DurableFrameArtifactClassification
}

private enum DurableFrameArtifactClassification {
  case valid(ContentAddressedFrameReference)
  case unrecognized
  case unreadable
  case unsafe(FrameArtifactConfinementFailure)
  case hashMismatch(actualSHA256: String)
}

private struct EpisodeRecordingEnvelope: Codable {
  let formatVersion: UInt64
  let recordingPayload: Data
  let payloadSHA256: String
}

private struct EpisodeRecordingInitializationMarker: Codable, Equatable {
  let recordingID: EpisodeRecordingID
  let schemaRevision: EpisodeRecordingSchemaRevision
  let frameRetentionPolicy: EpisodeFrameRetentionPolicy
}

private struct EpisodeRecordingMarkerEnvelope: Codable {
  let formatVersion: UInt64
  let markerPayload: Data
  let payloadSHA256: String
}

private enum ManifestCommitFault {
  case none
  case installedButDirectorySyncFailed
  case outcomeUncertainWithoutInstall
  case definiteFailureBeforeInstall
}

private final class EpisodeRecordingPersistenceFaultState {
  private let lock = NSLock()
  private var fault: EpisodeRecordingPersistenceFault

  init(_ fault: EpisodeRecordingPersistenceFault) {
    self.fault = fault
  }

  func signalBeforeCommitLockIfRequested() throws {
    let signalURL: URL?
    lock.lock()
    if case let .signalBeforeCommitLock(url) = fault {
      signalURL = url
      fault = .none
    } else {
      signalURL = nil
    }
    lock.unlock()
    if let signalURL { try publishTestSignal(at: signalURL) }
  }

  func signalImmediatelyBeforeCommitKernelLockIfRequested() throws {
    let signalURL: URL?
    lock.lock()
    if case let .signalImmediatelyBeforeCommitKernelLock(url) = fault {
      signalURL = url
      fault = .none
    } else {
      signalURL = nil
    }
    lock.unlock()
    if let signalURL { try publishTestSignal(at: signalURL) }
  }

  func pauseAfterInitializationMarkerIfRequested() throws {
    let rendezvous: (signal: URL, release: URL)?
    lock.lock()
    if case let .initializationPauseAfterMarker(signalURL, releaseURL) = fault {
      rendezvous = (signalURL, releaseURL)
      fault = .none
    } else {
      rendezvous = nil
    }
    lock.unlock()
    guard let rendezvous else { return }
    try publishTestSignal(at: rendezvous.signal)
    for _ in 0..<10_000 {
      if FileManager.default.fileExists(atPath: rendezvous.release.path) { return }
      Darwin.usleep(1_000)
    }
    throw EpisodeRecordingError.readFailed
  }

  func consumeInventoryAccountingOverflowIfRequested() -> Bool {
    lock.lock()
    defer { lock.unlock() }
    guard case .inventoryAccountingOverflowOnce = fault else { return false }
    fault = .none
    return true
  }

  func consumeManifestFault() -> ManifestCommitFault {
    lock.lock()
    defer { lock.unlock() }
    let result: ManifestCommitFault
    switch fault {
    case .none:
      result = .none
    case .manifestDirectorySynchronizationFailureOnce:
      result = .installedButDirectorySyncFailed
    case .manifestReplacementOutcomeUncertainWithoutInstallOnce:
      result = .outcomeUncertainWithoutInstall
    case .manifestPreRenameFailureOnce:
      result = .definiteFailureBeforeInstall
    case .initializationPauseAfterMarker, .signalBeforeCommitLock,
         .signalImmediatelyBeforeCommitKernelLock,
         .inventoryAccountingOverflowOnce:
      result = .none
    }
    fault = .none
    return result
  }
}

private func publishTestSignal(at url: URL) throws {
  do {
    try Data().write(to: url, options: .atomic)
  } catch {
    throw EpisodeRecordingError.writeFailed
  }
}

private struct RootDirectoryIdentity: Hashable {
  let device: UInt64
  let inode: UInt64
}

private final class RootDirectoryDescriptor {
  let descriptor: Int32
  let identity: RootDirectoryIdentity

  init(descriptor: Int32) throws {
    var status = Darwin.stat()
    guard Darwin.fstat(descriptor, &status) == 0,
          fileType(status) == S_IFDIR else {
      throw EpisodeRecordingError.destinationIsNotDirectory
    }
    guard status.st_uid == Darwin.geteuid() else {
      throw EpisodeRecordingError.recordingRootUnsafe(.notOwnedByCurrentUser)
    }
    self.descriptor = descriptor
    identity = RootDirectoryIdentity(
      device: UInt64(status.st_dev),
      inode: UInt64(status.st_ino)
    )
  }

  deinit {
    _ = Darwin.close(descriptor)
  }
}

private enum RecordingCommitLocks {
  private static let registryLock = NSLock()
  nonisolated(unsafe) private static var locksByRoot: [RootDirectoryIdentity: NSLock] = [:]

  static func lock(for identity: RootDirectoryIdentity) -> NSLock {
    registryLock.lock()
    defer { registryLock.unlock() }
    if let existing = locksByRoot[identity] { return existing }
    let lock = NSLock()
    locksByRoot[identity] = lock
    return lock
  }
}

private func relativeFileStatus(
  named name: String,
  directoryDescriptor: Int32
) throws -> Darwin.stat? {
  var status = Darwin.stat()
  let result = name.withCString {
    Darwin.fstatat(directoryDescriptor, $0, &status, AT_SYMLINK_NOFOLLOW)
  }
  if result == 0 { return status }
  if errno == ENOENT { return nil }
  throw EpisodeRecordingError.readFailed
}

private func fileType(_ status: Darwin.stat) -> mode_t {
  status.st_mode & mode_t(S_IFMT)
}

private func readOwnedRegularFile(
  named name: String,
  status: Darwin.stat,
  directoryDescriptor: Int32,
  unsafeError: (FrameArtifactConfinementFailure) -> EpisodeRecordingError,
  unreadableError: EpisodeRecordingError
) throws -> Data {
  guard fileType(status) != S_IFLNK else { throw unsafeError(.symbolicLink) }
  guard fileType(status) == S_IFREG else { throw unreadableError }
  guard status.st_uid == Darwin.geteuid() else {
    throw unsafeError(.notOwnedByCurrentUser)
  }
  guard status.st_nlink == 1 else { throw unsafeError(.externalHardLinks) }
  let descriptor = name.withCString {
    Darwin.openat(directoryDescriptor, $0, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
  }
  guard descriptor >= 0 else {
    if errno == ELOOP { throw unsafeError(.symbolicLink) }
    throw unreadableError
  }
  defer { _ = Darwin.close(descriptor) }
  var actual = Darwin.stat()
  guard Darwin.fstat(descriptor, &actual) == 0,
        fileType(actual) == S_IFREG else { throw unreadableError }
  guard actual.st_dev == status.st_dev,
        actual.st_ino == status.st_ino else { throw unsafeError(.symbolicLink) }
  guard actual.st_uid == Darwin.geteuid() else {
    throw unsafeError(.notOwnedByCurrentUser)
  }
  guard actual.st_nlink == 1 else { throw unsafeError(.externalHardLinks) }
  let data = try readAll(from: descriptor, error: unreadableError)
  var final = Darwin.stat()
  guard Darwin.fstat(descriptor, &final) == 0,
        final.st_dev == status.st_dev,
        final.st_ino == status.st_ino,
        final.st_nlink == 1 else { throw unsafeError(.externalHardLinks) }
  return data
}

private func readAll(from descriptor: Int32, error: EpisodeRecordingError) throws -> Data {
  var result = Data()
  var buffer = [UInt8](repeating: 0, count: 16_384)
  while true {
    let count = buffer.withUnsafeMutableBytes {
      Darwin.read(descriptor, $0.baseAddress, $0.count)
    }
    if count > 0 {
      result.append(contentsOf: buffer[0..<Int(count)])
    } else if count == 0 {
      return result
    } else if errno != EINTR {
      throw error
    }
  }
}

private func sha256(_ data: Data) -> String {
  SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}

private func writeAll(_ data: Data, to descriptor: Int32) throws {
  try data.withUnsafeBytes { bytes in
    guard let baseAddress = bytes.baseAddress else { return }
    var offset = 0
    while offset < bytes.count {
      let written = Darwin.write(
        descriptor,
        baseAddress.advanced(by: offset),
        bytes.count - offset
      )
      if written > 0 {
        offset += written
      } else if written == -1 && errno == EINTR {
        continue
      } else {
        throw EpisodeRecordingError.temporaryFileWriteFailed(
          code: written == 0 ? EIO : errno
        )
      }
    }
  }
}

private func synchronizeFile(_ descriptor: Int32) throws {
  var result: Int32
  repeat { result = Darwin.fcntl(descriptor, F_FULLFSYNC) }
  while result == -1 && errno == EINTR
  guard result == 0 else {
    throw EpisodeRecordingError.temporaryFileSynchronizationFailed(code: errno)
  }
}

private func synchronizeDirectoryDescriptor(_ descriptor: Int32) throws {
  var result: Int32
  repeat { result = Darwin.fsync(descriptor) }
  while result == -1 && errno == EINTR
  guard result == 0 else {
    throw EpisodeRecordingError.directorySynchronizationFailed(code: errno)
  }
}

private func durablyReplaceRelativeFile(
  named destinationName: String,
  in directoryDescriptor: Int32,
  with data: Data,
  fault: ManifestCommitFault
) throws {
  let temporaryName = ".\(destinationName).\(UUID().uuidString).tmp"
  let descriptor = temporaryName.withCString {
    Darwin.openat(
      directoryDescriptor,
      $0,
      O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC,
      mode_t(S_IRUSR | S_IWUSR)
    )
  }
  guard descriptor >= 0 else {
    throw EpisodeRecordingError.temporaryFileCreationFailed(code: errno)
  }
  var descriptorIsOpen = true
  var temporaryIsNamed = true
  defer {
    if descriptorIsOpen { _ = Darwin.close(descriptor) }
    if temporaryIsNamed {
      temporaryName.withCString { _ = Darwin.unlinkat(directoryDescriptor, $0, 0) }
    }
  }
  try writeAll(data, to: descriptor)
  try synchronizeFile(descriptor)
  guard Darwin.close(descriptor) == 0 else {
    descriptorIsOpen = false
    throw EpisodeRecordingError.temporaryFileCloseFailed(code: errno)
  }
  descriptorIsOpen = false

  if case .outcomeUncertainWithoutInstall = fault {
    throw EpisodeRecordingError.postRenameDirectorySynchronizationUncertain(code: EIO)
  }
  if case .definiteFailureBeforeInstall = fault {
    throw EpisodeRecordingError.atomicReplacementFailed(code: EIO)
  }
  let renameResult = temporaryName.withCString { source in
    destinationName.withCString { destination in
      Darwin.renameat(directoryDescriptor, source, directoryDescriptor, destination)
    }
  }
  guard renameResult == 0 else {
    throw EpisodeRecordingError.atomicReplacementFailed(code: errno)
  }
  temporaryIsNamed = false
  if case .installedButDirectorySyncFailed = fault {
    throw EpisodeRecordingError.postRenameDirectorySynchronizationUncertain(code: EIO)
  }
  do {
    try synchronizeDirectoryDescriptor(directoryDescriptor)
  } catch let error as EpisodeRecordingError {
    if case let .directorySynchronizationFailed(code) = error {
      throw EpisodeRecordingError.postRenameDirectorySynchronizationUncertain(code: code)
    }
    throw error
  }
}
