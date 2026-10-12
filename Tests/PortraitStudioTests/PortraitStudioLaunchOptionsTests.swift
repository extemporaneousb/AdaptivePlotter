import Foundation
import PlotterRuntime
import PortraitLibrary
import Testing
@testable import PortraitStudio

@Suite("Explicit disposable review-library opening")
struct PortraitStudioLaunchOptionsTests {
  @Test("Absolute existing disposable library accepted and production aliases refused")
  func pathAdmission() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let library = root.appendingPathComponent("PilotLibrary", isDirectory: true)
    try FileManager.default.createDirectory(at: library, withIntermediateDirectories: true)
    try Data().write(to: library.appendingPathComponent("library-v1.sqlite"))
    let accepted = try PortraitStudioLaunchOptions.reviewLibrary(arguments: ["Studio", "--review-library", library.path])
    #expect(accepted == library.standardizedFileURL.resolvingSymlinksInPath())
    #expect(throws: (any Error).self) {
      try PortraitStudioLaunchOptions.reviewLibrary(arguments: ["Studio", "--review-library", "relative"])
    }
    let production = AdaptivePlotterStoragePaths.production
    #expect(throws: (any Error).self) {
      try PortraitStudioLaunchOptions.reviewLibrary(arguments: ["Studio", "--review-library", production.portraitLibraryDirectory.path])
    }
    let alias = root.appendingPathComponent("alias")
    try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: production.drawingEvidenceDirectory)
    #expect(throws: (any Error).self) {
      try PortraitStudioLaunchOptions.reviewLibrary(arguments: ["Studio", "--review-library", alias.path])
    }
  }

  @Test("Another review writer is refused without changing library selection")
  func exclusiveWriter() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let lease = try PortraitStudioReviewLibraryLease(directory: root)
    withExtendedLifetime(lease) {
      #expect(throws: (any Error).self) { try PortraitStudioReviewLibraryLease(directory: root) }
    }
  }

  @Test("SQLite, WAL and SHM aliases cannot bypass the disposable-directory boundary")
  func databaseAliasesRefused() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let canonical = root.appendingPathComponent("canonical", isDirectory: true)
    let store = PortraitCandidateStore(directoryURL: canonical)
    _ = try await store.reviewLibraryIdentity()
    let original = canonical.appendingPathComponent("library-v1.sqlite")
    let library = root.appendingPathComponent("review", isDirectory: true)
    try FileManager.default.createDirectory(at: library, withIntermediateDirectories: true)
    let database = library.appendingPathComponent("library-v1.sqlite")
    for hardLink in [false, true] {
      if hardLink { try FileManager.default.linkItem(at: original, to: database) }
      else { try FileManager.default.createSymbolicLink(at: database, withDestinationURL: original) }
      #expect(throws: (any Error).self) {
        try PortraitStudioLaunchOptions.reviewLibrary(arguments: ["Studio", "--review-library", library.path])
      }
      try FileManager.default.removeItem(at: database)
    }
    try FileManager.default.copyItem(at: original, to: database)
    for name in ["library-v1.sqlite-wal", "library-v1.sqlite-shm"] {
      let alias = library.appendingPathComponent(name)
      for hardLink in [false, true] {
        if hardLink { try FileManager.default.linkItem(at: original, to: alias) }
        else { try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: original) }
        #expect(throws: (any Error).self) {
          try PortraitStudioLaunchOptions.reviewLibrary(arguments: ["Studio", "--review-library", library.path])
        }
        try FileManager.default.removeItem(at: alias)
      }
    }
    #expect(try PortraitStudioLaunchOptions.reviewLibrary(arguments: ["Studio", "--review-library", library.path]) == library)
  }
}
