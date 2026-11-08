import Foundation
import PortraitCore

public enum DrawingLibraryError: Error, Sendable {
  case unavailable(String), staleSelection, invalidIdentity, invalidQuery, closed
  case missing(DrawingRef), deleted(DrawingRef), writerBusy
  case referenceConflict(DrawingRef, actual: ExchangeDigest)
  case unsupportedFeature(String), corruptAsset(ExchangeDigest), ownership(String)
  case recordIntentConflict(UUID, expected: ExchangeDigest, actual: ExchangeDigest)
  case retentionIntentConflict(UUID, expected: ExchangeDigest, actual: ExchangeDigest)
}
package enum DrawingLibraryDatabaseError: Error { case database(String) }
package struct DrawingLibraryGeneration: Equatable, Sendable { let revision: Int64 }
public struct DrawingLibraryCursor: Sendable {
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
  package var cachedExchangeCatalog: LibraryExchangeCatalog?
  package let producerValidators: DrawingProducerValidators
  package static let selectedDrawingCacheLimit = 8
  package var selectedDrawingCache: [DrawingRef: (indexDigest: ExchangeDigest, files: VerifiedExchangeFiles, value: Drawing)] = [:]
  // Least recently used first. Eviction releases only this owner's cached value;
  // callers keep their selected Drawing, and a later miss verifies it afresh.
  package var selectedDrawingCacheRecency: [DrawingRef] = []
  package let ownerID = UUID()
  package var pendingRetentions: [UUID: DrawingLibraryPendingRetention] = [:]
  package var committedGeneration: DrawingLibraryGeneration?
  package var committedIndexState: DrawingLibraryFileState?
  package var closed = false
  public init(directoryURL: URL, validators: DrawingProducerValidators = .init()) {
    self.directoryURL = directoryURL; producerValidators = validators
  }
  public nonisolated static var defaultDirectoryURL: URL {
    FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("AdaptivePlotter/DrawingLibrary", isDirectory: true)
  }
  /// Actual app owners call this once before domain reload or preparing values.
  /// Readonly inspectors deliberately omit it and never acquire a writer lease.
  public func open() throws { _ = try commonCatalog() }
  public func recover() throws { _ = try commonCatalog() }
  package var commonDatabaseURL: URL { directoryURL.appendingPathComponent("drawing-library.sqlite") }
  package func libraryDatabase() throws -> DrawingLibraryDatabase {
    guard !closed else { throw DrawingLibraryError.closed }
    if let database { try database.assertSelectedFile(); return database }
    let opened = try DrawingLibraryDatabase(url: commonDatabaseURL)
    database = opened; return opened
  }
  package func commonCatalog() throws -> LibraryExchangeCatalog {
    let db = try libraryDatabase()
    if let committedGeneration,try db.generation != committedGeneration { throw DrawingLibraryError.staleSelection }
    if let committedIndexState,try DrawingLibraryFileState(db.url) != committedIndexState { throw DrawingLibraryError.staleSelection }
    if let cachedExchangeCatalog {
      defer { refreshOwnership() }
      try cachedExchangeCatalog.recover()
      return cachedExchangeCatalog
    }
    let value = try LibraryExchangeCatalog(database: db)
    cachedExchangeCatalog = value; refreshOwnership(); return value
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
  public func closeLibrary() {
    for value in pendingRetentions.values { if let root=value.temporaryRoot { try? FileManager.default.removeItem(at:root) } }
    pendingRetentions.removeAll()
    selectedDrawingCacheRecency.removeAll()
    selectedDrawingCache.removeAll(); cachedExchangeCatalog = nil; database = nil; closed = true
  }
  package func assignedLibraryIdentity(_ db: DrawingLibraryDatabase) throws -> UUID? {
    guard let value = try db.scalar("SELECT value FROM state WHERE key='library_uuid'") else { return nil }
    guard let id = UUID(uuidString: value) else { throw DrawingLibraryError.invalidIdentity }
    return id
  }
}
