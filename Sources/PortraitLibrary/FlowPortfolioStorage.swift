import Darwin
import Foundation
import PortraitCore

struct FlowPortfolioHead: Codable, Equatable {
  let schemaVersion: Int
  let portfolioID: UUID
  let revision: Int
  let recordSHA256: String
}
struct FlowPortfolioRecord: Codable {
  let schemaVersion: Int
  let sequence: Int
  let id: UUID
  let createdAt: Date
  let previousRecordSHA256: String?
  let operation: String
  let subjectID: UUID?
  let portfolioID: UUID
  let portfolioCreatedAt: Date
  let portfolioPurpose: FlowPortfolioPurpose
  let delta: FlowPortfolioDelta
}

/// Synchronous file work remains isolated behind FlowPortfolioStore's actor.
final class FlowPortfolioStorage: @unchecked Sendable {
  let directory: URL
  private let lease: Int32
  private let maximumBytes = 128 * 1024 * 1024

  init(directory: URL) throws {
    self.directory = directory.standardizedFileURL
    try FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true,
      attributes: [.posixPermissions: 0o700])
    let attributes = try FileManager.default.attributesOfItem(atPath: self.directory.path)
    guard attributes[.type] as? FileAttributeType == .typeDirectory else {
      throw FlowPortfolioError.invalid("The portfolio must be a local directory, not a symbolic link.")
    }
    let entries = try FileManager.default.contentsOfDirectory(atPath: self.directory.path)
    let hasHead = entries.contains("portfolio.json")
    guard hasHead || entries.isEmpty else {
      throw FlowPortfolioError.invalid("Choose an empty directory for a new portfolio; unrelated existing files are preserved.")
    }
    let lock = self.directory.appendingPathComponent("writer.lock")
    let descriptor = Darwin.open(lock.path, O_CREAT | O_RDWR | O_NOFOLLOW, S_IRUSR | S_IWUSR)
    guard descriptor >= 0 else { throw FlowPortfolioError.unavailable("The portfolio writer lock cannot be opened.") }
    var info = stat()
    guard fstat(descriptor, &info) == 0, info.st_mode & S_IFMT == S_IFREG, info.st_nlink == 1,
      flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
      Darwin.close(descriptor)
      throw FlowPortfolioError.conflict("Another writer owns this portfolio, or its lock is not a regular private file.")
    }
    lease = descriptor
    do {
      for name in ["objects", "records"] {
        let url = self.directory.appendingPathComponent(name, isDirectory: true)
        if !FileManager.default.fileExists(atPath: url.path) {
          try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700])
        }
        guard try FileManager.default.attributesOfItem(atPath: url.path)[.type] as? FileAttributeType == .typeDirectory else {
          throw FlowPortfolioError.invalid("Portfolio payload directories must be real directories, not symbolic links or files.")
        }
      }
    } catch { flock(descriptor, LOCK_UN); Darwin.close(descriptor); throw error }
  }
  deinit { flock(lease, LOCK_UN); Darwin.close(lease) }

  func loadOrCreate(purpose: FlowPortfolioPurpose?) throws -> (FlowPortfolioSnapshot, FlowPortfolioHead) {
    let headURL = directory.appendingPathComponent("portfolio.json")
    if !FileManager.default.fileExists(atPath: headURL.path) {
      let records = try FileManager.default.contentsOfDirectory(at: directory.appendingPathComponent("records"), includingPropertiesForKeys: nil)
      // Orphaned initial writes have no user-acknowledged head. Existing records
      // are not guessed into a new portfolio after a manifest is lost.
      guard records.isEmpty else { throw FlowPortfolioError.invalid("Portfolio head is missing; retained records are preserved for recovery.") }
      let snapshot = FlowPortfolioSnapshot.empty(purpose: purpose ?? .artist)
      let record = FlowPortfolioRecord(schemaVersion: 1, sequence: 0, id: UUID(), createdAt: Date(),
        previousRecordSHA256: nil, operation: "portfolioCreated", subjectID: nil,
        portfolioID: snapshot.id, portfolioCreatedAt: snapshot.createdAt, portfolioPurpose: snapshot.purpose,
        delta: FlowPortfolioDelta(previous: snapshot, next: snapshot))
      let head = try commit(record, expecting: nil)
      return (snapshot, head)
    }
    let head = try JSONDecoder().decode(FlowPortfolioHead.self, from: readFile(headURL, maximum: 64 * 1024))
    guard (1...2).contains(head.schemaVersion), head.revision >= 0, head.revision <= 1_000_000, Self.validHash(head.recordSHA256) else {
      throw FlowPortfolioError.invalid("Portfolio head has an unsupported schema or identity.")
    }
    var hash: String? = head.recordSHA256, expected = head.revision, seen = Set<String>()
    var records: [FlowPortfolioRecord] = []
    while let current = hash {
      guard seen.insert(current).inserted else { throw FlowPortfolioError.invalid("Portfolio record ancestry is cyclic.") }
      let bytes = try readHashed(current, folder: "records")
      let record = try JSONDecoder().decode(FlowPortfolioRecord.self, from: bytes)
      guard record.schemaVersion == 1, record.sequence == expected,
        record.portfolioID == head.portfolioID else {
        throw FlowPortfolioError.invalid("Portfolio operation ancestry is incomplete or inconsistent.")
      }
      records.append(record)
      hash = record.previousRecordSHA256; expected -= 1
    }
    guard expected == -1, let first = records.last else { throw FlowPortfolioError.invalid("Portfolio operation ancestry is incomplete.") }
    var latest = FlowPortfolioSnapshot(schemaVersion: 1, purpose: first.portfolioPurpose, id: first.portfolioID, createdAt: first.portfolioCreatedAt,
      revision: 0, sources: [], rounds: [], candidates: [], choices: [], pruneRevisions: [], presentations: [], rankings: [],
      trainingSnapshots: [], fits: [], activations: [], legacyImports: [], selectedSourceID: nil, currentRoundID: nil,
      currentCandidateID: nil, currentPruneRevisionID: nil, activeFitID: nil, currentPresentationID: nil)
    for record in records.reversed() {
      guard record.portfolioPurpose == first.portfolioPurpose, record.portfolioCreatedAt == first.portfolioCreatedAt else {
        throw FlowPortfolioError.invalid("Portfolio purpose or identity changed within its history.")
      }
      record.delta.apply(to: &latest, revision: record.sequence)
    }
    guard purpose == nil || purpose == latest.purpose else { throw FlowPortfolioError.invalid("Portfolio purpose differs from the requested artist or validation context.") }
    try FlowPortfolioValidation.validate(latest)
    for asset in FlowPortfolioValidation.blobs(latest) { _ = try read(asset) }
    return (latest, head)
  }

  func retain(_ bytes: Data, mediaType: String) throws -> FlowPortfolioBlob {
    guard !bytes.isEmpty, bytes.count <= maximumBytes, !mediaType.isEmpty else {
      throw FlowPortfolioError.invalid("Portfolio asset is empty or exceeds its size limit.")
    }
    let hash = DrawingPackageCodec.sha256(bytes)
    try writeImmutable(bytes, to: hashedURL(hash, folder: "objects"))
    return FlowPortfolioBlob(sha256: hash, byteCount: bytes.count, mediaType: mediaType)
  }
  func read(_ blob: FlowPortfolioBlob) throws -> Data {
    guard (1...maximumBytes).contains(blob.byteCount), !blob.mediaType.isEmpty else {
      throw FlowPortfolioError.invalid("Portfolio asset metadata is invalid.")
    }
    let bytes = try readHashed(blob.sha256, folder: "objects")
    guard bytes.count == blob.byteCount else { throw FlowPortfolioError.invalid("Portfolio asset length differs from its manifest.") }
    return bytes
  }
  func commit(_ record: FlowPortfolioRecord, expecting prior: FlowPortfolioHead?) throws -> FlowPortfolioHead {
    let url = directory.appendingPathComponent("portfolio.json")
    if let prior {
      let current = try JSONDecoder().decode(FlowPortfolioHead.self, from: readFile(url, maximum: 64 * 1024))
      guard current == prior else { throw FlowPortfolioError.conflict("The portfolio changed outside its writer; reopen it before continuing.") }
      guard record.previousRecordSHA256 == prior.recordSHA256, record.sequence == prior.revision + 1 else {
        throw FlowPortfolioError.invalid("The portfolio revision does not extend its durable head.")
      }
    } else {
      guard !FileManager.default.fileExists(atPath: url.path), record.sequence == 0, record.previousRecordSHA256 == nil else {
        throw FlowPortfolioError.conflict("The portfolio already has a durable head.")
      }
    }
    let bytes = try DrawingPackageCodec.encoder().encode(record)
    guard bytes.count <= maximumBytes else { throw FlowPortfolioError.invalid("Portfolio metadata exceeds its size limit.") }
    let hash = DrawingPackageCodec.sha256(bytes)
    try writeImmutable(bytes, to: hashedURL(hash, folder: "records"))
    // Head v2 is a writer-capability floor. Older applications reject it before
    // decoding optional fields they would otherwise discard on a later write.
    // Immutable operation records and frozen document envelopes remain v1.
    let head = FlowPortfolioHead(schemaVersion: 2, portfolioID: record.portfolioID, revision: record.sequence, recordSHA256: hash)
    try synchronizedAtomicWrite(DrawingPackageCodec.encoder().encode(head), to: url)
    return head
  }

  private func hashedURL(_ hash: String, folder: String) throws -> URL {
    guard Self.validHash(hash), folder == "objects" || folder == "records" else { throw FlowPortfolioError.invalid("Invalid portfolio content reference.") }
    return directory.appendingPathComponent(folder, isDirectory: true).appendingPathComponent(hash)
  }
  private func readHashed(_ hash: String, folder: String) throws -> Data {
    let bytes = try readFile(hashedURL(hash, folder: folder), maximum: maximumBytes)
    guard DrawingPackageCodec.sha256(bytes) == hash else { throw FlowPortfolioError.invalid("Portfolio content checksum mismatch: \(hash).") }
    return bytes
  }
  private func readFile(_ url: URL, maximum: Int) throws -> Data {
    let descriptor = Darwin.open(url.path, O_RDONLY | O_NOFOLLOW)
    guard descriptor >= 0 else { throw FlowPortfolioError.unavailable("Portfolio file is unavailable: \(url.lastPathComponent).") }
    let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
    defer { try? handle.close() }
    var info = stat()
    guard fstat(descriptor, &info) == 0, info.st_mode & S_IFMT == S_IFREG,
      info.st_nlink == 1, info.st_size > 0, info.st_size <= maximum else {
      throw FlowPortfolioError.invalid("Portfolio payload is not a bounded private regular file.")
    }
    var bytes = Data()
    while let chunk = try handle.read(upToCount: min(65_536, maximum + 1 - bytes.count)), !chunk.isEmpty {
      bytes.append(chunk)
      guard bytes.count <= maximum else { throw FlowPortfolioError.invalid("Portfolio payload grew beyond its limit.") }
    }
    guard bytes.count == info.st_size, bytes.count <= maximum else { throw FlowPortfolioError.invalid("Portfolio payload changed during reading.") }
    return bytes
  }
  private func writeImmutable(_ bytes: Data, to url: URL) throws {
    if FileManager.default.fileExists(atPath: url.path) {
      guard try readFile(url, maximum: maximumBytes) == bytes else { throw FlowPortfolioError.conflict("Immutable portfolio content already has different bytes.") }
      return
    }
    try synchronizedAtomicWrite(bytes, to: url)
  }
  private func synchronizedAtomicWrite(_ bytes: Data, to url: URL) throws {
    // A task-local temporary file is never a committed asset or operation.
    let temporary = url.deletingLastPathComponent().appendingPathComponent(".pending-" + UUID().uuidString)
    let fd = Darwin.open(temporary.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, S_IRUSR | S_IWUSR)
    guard fd >= 0 else { throw FlowPortfolioError.unavailable("Unable to stage the portfolio write.") }
    let file = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
    defer { try? file.close(); try? FileManager.default.removeItem(at: temporary) }
    try file.write(contentsOf: bytes); try file.synchronize(); try file.close()
    guard rename(temporary.path, url.path) == 0 else { throw FlowPortfolioError.unavailable("Unable to commit the portfolio write.") }
    let directoryFD = Darwin.open(url.deletingLastPathComponent().path, O_RDONLY)
    guard directoryFD >= 0 else { throw FlowPortfolioError.unavailable("Unable to synchronize the portfolio directory.") }
    defer { Darwin.close(directoryFD) }
    guard fsync(directoryFD) == 0 else { throw FlowPortfolioError.unavailable("Portfolio directory synchronization failed.") }
  }
  static func validHash(_ value: String) -> Bool {
    value.utf8.count == 64 && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
  }
}
