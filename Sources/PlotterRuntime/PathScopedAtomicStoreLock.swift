import Darwin
import Foundation

enum PathScopedAtomicStoreLockError: Error, Equatable, Sendable {
  case openFailed(path: String, errno: Int32)
  case lockFailed(path: String, errno: Int32)
}

/// The single locking seam for checksum-envelope stores. A canonical-path
/// process lock coordinates separate store values in this process; `flock`
/// provides the matching advisory exclusion across application processes.
struct PathScopedAtomicStoreLock: @unchecked Sendable {
  private final class Registry: @unchecked Sendable {
    static let shared = Registry()
    private let registryLock = NSLock()
    private var locks: [String: NSLock] = [:]

    func lock(for canonicalPath: String) -> NSLock {
      registryLock.lock()
      defer { registryLock.unlock() }
      if let existing = locks[canonicalPath] { return existing }
      let created = NSLock()
      locks[canonicalPath] = created
      return created
    }
  }

  let lockFileURL: URL
  private let processLock: NSLock

  init(dataFileURL: URL) {
    lockFileURL = dataFileURL.appendingPathExtension("lock")
    processLock = Registry.shared.lock(
      for: lockFileURL.standardizedFileURL.path
    )
  }

  func withLock<Value>(_ body: () throws -> Value) throws -> Value {
    processLock.lock()
    defer { processLock.unlock() }
    try FileManager.default.createDirectory(
      at: lockFileURL.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    let descriptor = Darwin.open(lockFileURL.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
    guard descriptor >= 0 else {
      throw PathScopedAtomicStoreLockError.openFailed(
        path: lockFileURL.path,
        errno: errno
      )
    }
    defer { Darwin.close(descriptor) }
    var advisoryLock = flock()
    advisoryLock.l_type = Int16(F_WRLCK)
    advisoryLock.l_whence = Int16(SEEK_SET)
    var lockResult: Int32
    repeat {
      lockResult = Darwin.fcntl(descriptor, F_SETLKW, &advisoryLock)
    } while lockResult == -1 && errno == EINTR
    guard lockResult == 0 else {
      throw PathScopedAtomicStoreLockError.lockFailed(
        path: lockFileURL.path,
        errno: errno
      )
    }
    defer {
      advisoryLock.l_type = Int16(F_UNLCK)
      _ = Darwin.fcntl(descriptor, F_SETLK, &advisoryLock)
    }
    return try body()
  }
}
