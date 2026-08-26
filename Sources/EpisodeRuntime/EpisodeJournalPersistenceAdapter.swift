import Darwin
import EpisodeCore
import Foundation

/// The single typed persistence boundary used by ``EpisodeStore``.
///
/// A successful commit must durably replace `expectedJournal` with `journal`.
/// Pre-replacement failures leave the previous journal unchanged. A typed
/// post-replacement synchronization uncertainty may have installed `journal`;
/// callers must reopen before deciding what is durable. The expected value
/// prevents a second store from silently overwriting a newer journal.
public protocol EpisodeJournalPersisting: Sendable {
  associatedtype Payload: Codable & Hashable & Sendable

  var journalSchemaRevision: EpisodeRevisionIdentifier { get }

  func load() throws -> EpisodeJournal<Payload>?

  func commit(
    _ journal: EpisodeJournal<Payload>,
    replacing expectedJournal: EpisodeJournal<Payload>
  ) throws
}

public enum EpisodeJournalPersistenceError: Error, Equatable, Sendable {
  case destinationIsDirectory
  case destinationDirectoryMissing
  case destinationParentIsNotDirectory
  case readFailed
  case writeFailed
  case corruptEnvelope
  case unsupportedFormatVersion(expected: UInt64, actual: UInt64)
  case journalSchemaRevisionMismatch(
    expected: EpisodeRevisionIdentifier,
    actual: EpisodeRevisionIdentifier
  )
  case payloadChecksumMismatch
  case corruptJournal
  case invalidAppend
  case concurrentWriterConflict
  case commitLockOpenFailed
  case commitLockAcquisitionFailed
  case temporaryFileCreationFailed(code: Int32)
  case temporaryFileWriteFailed(code: Int32)
  case temporaryFileSynchronizationFailed(code: Int32)
  case temporaryFileCloseFailed(code: Int32)
  case atomicReplacementFailed(code: Int32)
  case postRenameDirectorySynchronizationUncertain(code: Int32)
}

/// A versioned, atomic file adapter for one durable ``EpisodeJournal``.
///
/// The destination's parent directory must already exist. The adapter never
/// creates directory ancestry; it writes one integrity-checked envelope by
/// crash-durable atomic replacement. It has no compatibility writer and never
/// shadows an append into another store.
public struct EpisodeJournalPersistenceAdapter<Payload>: EpisodeJournalPersisting
where Payload: Codable & Hashable & Sendable {
  public static var currentFormatVersion: UInt64 { 1 }

  public let fileURL: URL
  public let journalSchemaRevision: EpisodeRevisionIdentifier
  private let inProcessCommitLock: NSLock

  public init(
    fileURL: URL,
    journalSchemaRevision: EpisodeRevisionIdentifier
  ) {
    self.fileURL = fileURL
    self.journalSchemaRevision = journalSchemaRevision
    inProcessCommitLock = EpisodeJournalInProcessCommitLocks.lock(for: fileURL)
  }

  public func load() throws -> EpisodeJournal<Payload>? {
    let fileManager = FileManager.default
    var isDirectory: ObjCBool = false
    guard fileManager.fileExists(atPath: fileURL.path, isDirectory: &isDirectory) else {
      return nil
    }
    guard !isDirectory.boolValue else {
      throw EpisodeJournalPersistenceError.destinationIsDirectory
    }

    let encodedEnvelope: Data
    do {
      encodedEnvelope = try Data(contentsOf: fileURL)
    } catch {
      throw EpisodeJournalPersistenceError.readFailed
    }

    let envelope: PersistedEpisodeJournalEnvelope
    do {
      envelope = try JSONDecoder().decode(
        PersistedEpisodeJournalEnvelope.self,
        from: encodedEnvelope
      )
    } catch {
      throw EpisodeJournalPersistenceError.corruptEnvelope
    }

    guard envelope.formatVersion == Self.currentFormatVersion else {
      throw EpisodeJournalPersistenceError.unsupportedFormatVersion(
        expected: Self.currentFormatVersion,
        actual: envelope.formatVersion
      )
    }
    guard envelope.journalSchemaRevision == journalSchemaRevision else {
      throw EpisodeJournalPersistenceError.journalSchemaRevisionMismatch(
        expected: journalSchemaRevision,
        actual: envelope.journalSchemaRevision
      )
    }
    guard envelope.payloadChecksum == checksum(of: envelope.journalPayload) else {
      throw EpisodeJournalPersistenceError.payloadChecksumMismatch
    }

    do {
      return try JSONDecoder().decode(
        EpisodeJournal<Payload>.self,
        from: envelope.journalPayload
      )
    } catch {
      throw EpisodeJournalPersistenceError.corruptJournal
    }
  }

  public func commit(
    _ journal: EpisodeJournal<Payload>,
    replacing expectedJournal: EpisodeJournal<Payload>
  ) throws {
    guard journal.manifestID == expectedJournal.manifestID,
          journal.episodeID == expectedJournal.episodeID,
          journal.initialStateRevision == expectedJournal.initialStateRevision,
          journal.events.count == expectedJournal.events.count + 1,
          Array(journal.events.dropLast()) == expectedJournal.events else {
      throw EpisodeJournalPersistenceError.invalidAppend
    }

    let journalPayload: Data
    do {
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.sortedKeys]
      journalPayload = try encoder.encode(journal)
    } catch {
      throw EpisodeJournalPersistenceError.writeFailed
    }

    let envelope = PersistedEpisodeJournalEnvelope(
      formatVersion: Self.currentFormatVersion,
      journalSchemaRevision: journalSchemaRevision,
      journalPayload: journalPayload,
      payloadChecksum: checksum(of: journalPayload)
    )
    let encodedEnvelope: Data
    do {
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.sortedKeys]
      encodedEnvelope = try encoder.encode(envelope)
    } catch {
      throw EpisodeJournalPersistenceError.writeFailed
    }

    let fileManager = FileManager.default
    let directoryURL = fileURL.deletingLastPathComponent()
    var isDirectory: ObjCBool = false
    guard fileManager.fileExists(atPath: directoryURL.path, isDirectory: &isDirectory) else {
      throw EpisodeJournalPersistenceError.destinationDirectoryMissing
    }
    guard isDirectory.boolValue else {
      throw EpisodeJournalPersistenceError.destinationParentIsNotDirectory
    }

    // Independently initialized adapters for the same canonical path share the
    // process mutex, while the fcntl lock supplies cross-process exclusion. The
    // sidecar's existence does not encode owner or age: the kernel releases its
    // lock on close or process exit, so no stale-lock inference is needed.
    inProcessCommitLock.lock()
    defer { inProcessCommitLock.unlock() }

    let lockURL = fileURL.appendingPathExtension("lock")
    let lockDescriptor = lockURL.path.withCString { path in
      Darwin.open(
        path,
        O_CREAT | O_RDWR | O_CLOEXEC,
        mode_t(S_IRUSR | S_IWUSR)
      )
    }
    guard lockDescriptor >= 0 else {
      throw EpisodeJournalPersistenceError.commitLockOpenFailed
    }

    var kernelLock = Darwin.flock()
    kernelLock.l_start = 0
    kernelLock.l_len = 0
    kernelLock.l_pid = 0
    kernelLock.l_type = Int16(F_WRLCK)
    kernelLock.l_whence = Int16(SEEK_SET)
    guard Darwin.fcntl(lockDescriptor, F_SETLKW, &kernelLock) != -1 else {
      _ = Darwin.close(lockDescriptor)
      throw EpisodeJournalPersistenceError.commitLockAcquisitionFailed
    }
    defer {
      kernelLock.l_type = Int16(F_UNLCK)
      _ = Darwin.fcntl(lockDescriptor, F_SETLK, &kernelLock)
      _ = Darwin.close(lockDescriptor)
    }

    // The expected-value comparison and atomic replacement share one exclusive
    // region, preventing concurrent stores from both committing the same base.
    let durableJournal = try load()
    guard durableJournal == expectedJournal
            || (durableJournal == nil && expectedJournal.events.isEmpty) else {
      throw EpisodeJournalPersistenceError.concurrentWriterConflict
    }

    try durablyReplaceFile(
      at: fileURL,
      in: directoryURL,
      with: encodedEnvelope
    )
  }
}

private struct PersistedEpisodeJournalEnvelope: Codable {
  let formatVersion: UInt64
  let journalSchemaRevision: EpisodeRevisionIdentifier
  let journalPayload: Data
  let payloadChecksum: String
}

private enum EpisodeJournalInProcessCommitLocks {
  private static let registryLock = NSLock()
  nonisolated(unsafe) private static var locksByCanonicalURL: [URL: NSLock] = [:]

  static func lock(for fileURL: URL) -> NSLock {
    let canonicalURL = fileURL.standardizedFileURL.resolvingSymlinksInPath()
    registryLock.lock()
    defer { registryLock.unlock() }
    if let existing = locksByCanonicalURL[canonicalURL] {
      return existing
    }
    let lock = NSLock()
    locksByCanonicalURL[canonicalURL] = lock
    return lock
  }
}

private func durablyReplaceFile(
  at destinationURL: URL,
  in directoryURL: URL,
  with data: Data
) throws {
  let temporaryURL = directoryURL.appendingPathComponent(
    ".\(destinationURL.lastPathComponent).\(UUID().uuidString).tmp"
  )
  let descriptor = temporaryURL.path.withCString { path in
    Darwin.open(
      path,
      O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC,
      mode_t(S_IRUSR | S_IWUSR)
    )
  }
  guard descriptor >= 0 else {
    throw EpisodeJournalPersistenceError.temporaryFileCreationFailed(code: errno)
  }

  var descriptorIsOpen = true
  var temporaryFileIsNamed = true
  defer {
    if descriptorIsOpen {
      _ = Darwin.close(descriptor)
    }
    if temporaryFileIsNamed {
      temporaryURL.path.withCString { path in
        _ = Darwin.unlink(path)
      }
    }
  }

  try writeAll(data, to: descriptor)
  var fileSynchronizationResult: Int32
  repeat {
    fileSynchronizationResult = Darwin.fcntl(descriptor, F_FULLFSYNC)
  } while fileSynchronizationResult == -1 && errno == EINTR
  guard fileSynchronizationResult == 0 else {
    throw EpisodeJournalPersistenceError.temporaryFileSynchronizationFailed(code: errno)
  }
  guard Darwin.close(descriptor) == 0 else {
    descriptorIsOpen = false
    throw EpisodeJournalPersistenceError.temporaryFileCloseFailed(code: errno)
  }
  descriptorIsOpen = false

  let renameResult = temporaryURL.path.withCString { sourcePath in
    destinationURL.path.withCString { destinationPath in
      Darwin.rename(sourcePath, destinationPath)
    }
  }
  guard renameResult == 0 else {
    throw EpisodeJournalPersistenceError.atomicReplacementFailed(code: errno)
  }
  temporaryFileIsNamed = false

  let directoryDescriptor = directoryURL.path.withCString { path in
    Darwin.open(path, O_RDONLY | O_DIRECTORY | O_CLOEXEC)
  }
  guard directoryDescriptor >= 0 else {
    throw EpisodeJournalPersistenceError
      .postRenameDirectorySynchronizationUncertain(code: errno)
  }
  defer { _ = Darwin.close(directoryDescriptor) }

  var synchronizationResult: Int32
  repeat {
    synchronizationResult = Darwin.fsync(directoryDescriptor)
  } while synchronizationResult == -1 && errno == EINTR
  guard synchronizationResult == 0 else {
    throw EpisodeJournalPersistenceError
      .postRenameDirectorySynchronizationUncertain(code: errno)
  }
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
        let code = written == 0 ? EIO : errno
        throw EpisodeJournalPersistenceError.temporaryFileWriteFailed(code: code)
      }
    }
  }
}

/// Stable corruption detection for the versioned envelope. This is an adapter
/// integrity checksum, not episode-state semantic authority.
private func checksum(of data: Data) -> String {
  let offsetBasis: UInt64 = 0xcbf29ce484222325
  let prime: UInt64 = 0x100000001b3
  let value = data.reduce(offsetBasis) { partial, byte in
    (partial ^ UInt64(byte)) &* prime
  }
  return String(format: "%016llx", value)
}
