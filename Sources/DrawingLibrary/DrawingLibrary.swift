import Foundation
import PortraitCore

public enum DrawingLibraryError: Error, Sendable {
  case unavailable(String), staleSelection, invalidIdentity, invalidQuery, closed
  case missing(DrawingRef), deleted(DrawingRef), writerBusy
  case referenceConflict(DrawingRef, actual: ExchangeDigest)
  case quarantinedConflict(URL)
  case unsupportedFeature(String), corruptAsset(ExchangeDigest), ownership(String)
  case recordIntentConflict(UUID, expected: ExchangeDigest, actual: ExchangeDigest)
  case retentionIntentConflict(UUID, expected: ExchangeDigest, actual: ExchangeDigest)
}
package enum DrawingLibraryDatabaseError: Error {
  case database(String)
  case retryableSQLite(code: Int32, message: String)
}
package struct DrawingLibraryGeneration: Equatable, Sendable { let revision: Int64 }
public enum DrawingLibraryDrawingScope: Hashable, Sendable {
  case all, photo(PhotoRef), input(ImageInputRef), children(DrawingRef)
}
public struct DrawingLibraryCursor: Sendable {
  package let scope: DrawingLibraryDrawingScope
  package init(generation: DrawingLibraryGeneration, date: String, issuer: String, revision: String, scope: DrawingLibraryDrawingScope = .all) {
    self.generation = generation; self.date = date; self.issuer = issuer; self.revision = revision; self.scope = scope
  }
  package let generation: DrawingLibraryGeneration
  package let date: String
  package let issuer: String
  package let revision: String
}
public struct DrawingLibraryEntry: Sendable, Identifiable {
  public var id: DrawingRef { reference }
  public let reference: DrawingRef
  public let title: String?
  public let createdAt: Date?
  public let programDigest: ExchangeDigest
  public let strokeCount: Int
  public let pointCount: Int
}
public struct DrawingLibraryPage: Sendable {
  public let entries: [DrawingLibraryEntry]
  public let next: DrawingLibraryCursor?
}
/// One concrete owner for the new Drawing Library. Callers share this actor and
/// drain their domain work before closeLibrary; a closed owner never reopens itself.
public actor DrawingLibrary {
  public nonisolated let directoryURL: URL
  package var database: DrawingLibraryDatabase?
  package var readDatabase: DrawingLibraryDatabase?
  package var cachedExchangeCatalog: LibraryExchangeCatalog?
  package let payloadValidators: ExchangePayloadValidators
  package let producerValidators: DrawingProducerValidators
  package static let selectedDrawingCacheLimit = 8
  package var selectedDrawingCache: [DrawingRef: (indexDigest: ExchangeDigest, files: VerifiedExchangeFiles, value: Drawing)] = [:]
  // Least recently used first. Eviction releases only this owner's cached value;
  // callers keep their selected Drawing, and a later miss verifies it afresh.
  package var selectedDrawingCacheRecency: [DrawingRef] = []
  var existingAssetProofs: [ExchangeDigest: VerifiedExchangeFiles] = [:]
  var existingAssetRecency: [ExchangeDigest] = []
  var existingAssetDiagnostics = DrawingLibraryAssetReuseStatistics()
  package let ownerID = UUID()
  package var pendingRetentions: [UUID: DrawingLibraryPendingRetention] = [:]
  package var committedGeneration: DrawingLibraryGeneration?
  package var committedIndexState: DrawingLibraryFileState?
  var resultRetryWaiters: [UUID: [CheckedContinuation<Void, Never>]] = [:]
  private var resultWork = 0
  private var closeWaiters: [CheckedContinuation<Void, Never>] = []
  package var closed = false
  public init(directoryURL: URL, validators: DrawingProducerValidators = .init(),
    payloadValidators: ExchangePayloadValidators = .init()) {
    self.directoryURL = directoryURL; producerValidators = validators
    self.payloadValidators = payloadValidators
  }
  public nonisolated static var defaultDirectoryURL: URL {
    FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("AdaptivePlotter/DrawingLibrary", isDirectory: true)
  }
  /// Actual app owners call this once before domain reload or preparing values.
  /// Readonly inspectors deliberately omit it and never acquire a writer lease.
  public func open() throws { _ = try commonCatalog() }
  public func recover() throws { _ = try commonCatalog(includingFailedResults: true) }
  package var commonDatabaseURL: URL { directoryURL.appendingPathComponent("drawing-library.sqlite") }
  package func libraryDatabase() throws -> DrawingLibraryDatabase {
    guard !closed else { throw DrawingLibraryError.closed }
    if let database { try database.assertSelectedFile(); return database }
    let opened = try DrawingLibraryDatabase(url: commonDatabaseURL)
    database = opened; return opened
  }
  package func commonCatalog(includingFailedResults: Bool = false) throws -> LibraryExchangeCatalog {
    let db = try libraryDatabase()
    try checkOwnership(db)
    if let cachedExchangeCatalog {
      defer { refreshOwnership() }
      try cachedExchangeCatalog.recover(includingFailedResults: includingFailedResults)
      return cachedExchangeCatalog
    }
    let value = try LibraryExchangeCatalog(database: db)
    cachedExchangeCatalog = value; refreshOwnership(); return value
  }
  func checkOwnership(_ db: DrawingLibraryDatabase) throws {
    try db.assertSelectedFile()
    if let committedGeneration, try db.generation != committedGeneration { throw DrawingLibraryError.staleSelection }
    if let committedIndexState, try DrawingLibraryFileState(db.url) != committedIndexState { throw DrawingLibraryError.staleSelection }
  }
  package func refreshOwnership() {
    guard let database else { return }
    committedGeneration=try? database.generation;committedIndexState=try? DrawingLibraryFileState(database.url)
  }
  package func touchSelectedDrawing(_ ref: DrawingRef) {
    selectedDrawingCacheRecency.removeAll { $0 == ref }
    selectedDrawingCacheRecency.append(ref)
    while selectedDrawingCacheRecency.count > Self.selectedDrawingCacheLimit {
      selectedDrawingCache.removeValue(forKey: selectedDrawingCacheRecency.removeFirst())
    }
  }
  package func evictSelectedDrawing(_ ref: DrawingRef) {
    selectedDrawingCache.removeValue(forKey: ref)
    selectedDrawingCacheRecency.removeAll { $0 == ref }
  }
  func beginResultWork() throws {
    guard !closed else { throw DrawingLibraryError.closed }
    resultWork += 1
  }
  func endResultWork() {
    resultWork -= 1
    if resultWork == 0 {
      let waiters = closeWaiters
      closeWaiters.removeAll()
      for waiter in waiters { waiter.resume() }
    }
  }
  public func closeLibrary() async {
    closed = true
    if resultWork > 0 {
      await withCheckedContinuation { closeWaiters.append($0) }
    }
    for value in pendingRetentions.values { if let root=value.temporaryRoot { try? FileManager.default.removeItem(at:root) } }
    pendingRetentions.removeAll()
    selectedDrawingCacheRecency.removeAll()
    selectedDrawingCache.removeAll(); existingAssetProofs.removeAll(); existingAssetRecency.removeAll()
    cachedExchangeCatalog = nil; readDatabase = nil; database = nil
  }
  package func assignedLibraryIdentity(_ db: DrawingLibraryDatabase) throws -> UUID? {
    guard let value = try db.scalar("SELECT value FROM state WHERE key='library_uuid'") else { return nil }
    guard let id = UUID(uuidString: value) else { throw DrawingLibraryError.invalidIdentity }
    return id
  }
}
