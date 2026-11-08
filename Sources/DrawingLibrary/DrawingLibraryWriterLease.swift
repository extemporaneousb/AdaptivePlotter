import Darwin
import Foundation

/// The descriptor, not a pathname or process-local registry, owns the writer.
/// Never unlink this lock: another opener must contend on the same inode.
package final class DrawingLibraryWriterLease {
  private let originalRootURL: URL
  package var canonicalRootURL: URL {
    var path = [CChar](repeating: 0, count: Int(MAXPATHLEN))
    if fcntl(rootDescriptor, F_GETPATH, &path) == 0 { return URL(fileURLWithPath: String(cString: path)) }
    return originalRootURL
  }
  private let rootDescriptor: Int32
  private let lockDescriptor: Int32
  private let claimLock = NSLock()
  private var hasDatabase = false
  func claimDatabase() throws {
    claimLock.lock(); defer { claimLock.unlock() }
    guard !hasDatabase else { throw DrawingLibraryDatabaseError.database("This writer lease already owns a writable catalog connection") }
    hasDatabase = true
  }
  func releaseDatabase() { claimLock.lock(); hasDatabase = false; claimLock.unlock() }

  package init(root: URL) throws {
    let resolved = root.standardizedFileURL.resolvingSymlinksInPath()
    try FileManager.default.createDirectory(at: resolved, withIntermediateDirectories: true,
      attributes: [.posixPermissions: 0o700])
    let rootFD = Darwin.open(resolved.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
    guard rootFD >= 0 else { throw DrawingLibraryDatabaseError.database("Library root is unavailable") }
    let lockFD = openat(rootFD, "library-writer.lock", O_CREAT | O_RDWR | O_NOFOLLOW | O_CLOEXEC, 0o600)
    guard lockFD >= 0 else { Darwin.close(rootFD); throw DrawingLibraryDatabaseError.database("Library writer lock is unavailable") }
    var owned = stat(), selected = stat()
    guard fstat(lockFD, &owned) == 0, owned.st_mode & S_IFMT == S_IFREG, owned.st_nlink == 1,
      fstatat(rootFD, "library-writer.lock", &selected, AT_SYMLINK_NOFOLLOW) == 0,
      owned.st_dev == selected.st_dev, owned.st_ino == selected.st_ino else {
      Darwin.close(lockFD); Darwin.close(rootFD)
      throw DrawingLibraryDatabaseError.database("Another writer owns this library, or its lock is not a private regular file")
    }
    guard flock(lockFD,LOCK_EX | LOCK_NB)==0 else {
      let code=errno;Darwin.close(lockFD);Darwin.close(rootFD)
      if code==EWOULDBLOCK || code==EAGAIN { throw DrawingLibraryError.writerBusy }
      throw DrawingLibraryDatabaseError.database("Writer lock could not be acquired")
    }
    originalRootURL = resolved
    rootDescriptor = rootFD; lockDescriptor = lockFD
  }

  package func assertMatches(root: URL) throws {
    var owned = stat(), requested = stat(), lock = stat(), selected = stat()
    guard fstat(rootDescriptor, &owned) == 0, fstatat(AT_FDCWD, root.path, &requested, 0) == 0,
      owned.st_dev == requested.st_dev, owned.st_ino == requested.st_ino,
      fstat(lockDescriptor, &lock) == 0, lock.st_nlink == 1,
      fstatat(rootDescriptor, "library-writer.lock", &selected, AT_SYMLINK_NOFOLLOW) == 0,
      lock.st_dev == selected.st_dev, lock.st_ino == selected.st_ino else {
      throw DrawingLibraryDatabaseError.database("Writer lease does not own the selected library directory")
    }
  }

  deinit { flock(lockDescriptor, LOCK_UN); Darwin.close(lockDescriptor); Darwin.close(rootDescriptor) }
}
