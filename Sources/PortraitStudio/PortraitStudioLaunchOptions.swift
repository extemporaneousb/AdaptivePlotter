import Darwin
import Foundation
import PlotterRuntime
import PortraitCore

enum PortraitStudioLaunchOptions {
  static func reviewLibrary(arguments: [String], production: AdaptivePlotterStoragePaths = .production,
    defaultLibrary: URL = PortraitStudioComposition.privateLibraryURL) throws -> URL? {
    let indices = arguments.indices.filter { arguments[$0] == "--review-library" }
    guard !indices.isEmpty else { return nil }
    guard indices.count == 1, let index = indices.first, index + 1 < arguments.count,
      arguments[index + 1].hasPrefix("/") else {
      throw DrawingTransferError.invalid("--review-library requires one absolute directory path.")
    }
    let directory = URL(fileURLWithPath: arguments[index + 1], isDirectory: true)
      .standardizedFileURL.resolvingSymlinksInPath()
    let excluded = [production.portraitLibraryDirectory, production.drawingEvidenceDirectory, defaultLibrary]
    guard !excluded.contains(where: { root in
      let path = root.standardizedFileURL.resolvingSymlinksInPath().path
      return directory.path == path || directory.path.hasPrefix(path + "/")
    }) else {
      throw DrawingTransferError.invalid("Review-library mode cannot open a production, evidence, or default Studio library.")
    }
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory), isDirectory.boolValue,
      FileManager.default.fileExists(atPath: directory.appendingPathComponent("library-v1.sqlite").path) else {
      throw DrawingTransferError.unavailable("The nominated review library must already contain its canonical SQLite store.")
    }
    for name in ["library-v1.sqlite", "library-v1.sqlite-wal", "library-v1.sqlite-shm"] {
      var attributes = stat()
      let file = directory.appendingPathComponent(name)
      if lstat(file.path, &attributes) != 0 {
        guard name != "library-v1.sqlite", errno == ENOENT else {
          throw DrawingTransferError.unavailable("The nominated review library's SQLite files cannot be inspected.")
        }
        continue
      }
      guard attributes.st_mode & S_IFMT == S_IFREG, attributes.st_nlink == 1 else {
        throw DrawingTransferError.invalid("Review-library SQLite, WAL and SHM files must be local regular files with no symbolic or hard links.")
      }
    }
    return directory
  }
}

/// Review mode is an explicit disposable-library opening, with one cooperating
/// Studio writer. A refused lease never falls back to another writable store.
final class PortraitStudioReviewLibraryLease {
  private let descriptor: Int32
  init(directory: URL) throws {
    let file = directory.appendingPathComponent("studio-review-writer.lock")
    let descriptor = Darwin.open(file.path, O_CREAT | O_RDWR | O_NOFOLLOW, S_IRUSR | S_IWUSR)
    guard descriptor >= 0 else { throw DrawingTransferError.unavailable("Review-library writer lock cannot be opened.") }
    guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
      Darwin.close(descriptor)
      throw DrawingTransferError.unavailable("Another Studio writer owns this review library. Close that app first.")
    }
    self.descriptor = descriptor
  }
  deinit { flock(descriptor, LOCK_UN); Darwin.close(descriptor) }
}
