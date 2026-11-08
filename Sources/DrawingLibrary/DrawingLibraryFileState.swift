import Darwin
import Foundation
import PortraitCore

/// A verified file may reuse its digest only while this complete stat identity
/// is unchanged. ctime catches same-size writes even when mtime is restored.
/// This is a byte-verification cache key, never evidence or authorization.
package struct DrawingLibraryFileState: Equatable, Sendable {
  private let device: Int32
  private let inode: UInt64
  package let byteCount: Int64
  private let modifiedSeconds: Int
  private let modifiedNanoseconds: Int
  private let changedSeconds: Int
  private let changedNanoseconds: Int

  package init(_ url: URL) throws {
    var value = stat()
    guard url.withUnsafeFileSystemRepresentation({ Darwin.fstatat(AT_FDCWD, $0!, &value, 0) }) == 0 else {
      throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
    }
    device = value.st_dev; inode = value.st_ino; byteCount = value.st_size
    modifiedSeconds = value.st_mtimespec.tv_sec
    modifiedNanoseconds = value.st_mtimespec.tv_nsec
    changedSeconds = value.st_ctimespec.tv_sec
    changedNanoseconds = value.st_ctimespec.tv_nsec
  }
}
