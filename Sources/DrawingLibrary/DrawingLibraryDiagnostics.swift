import Foundation

/// Process diagnostics at the Library SQL/storage seams, not a second store.
/// Counts include fixture/setup work unless the caller subtracts snapshots.
package final class DrawingLibraryDiagnostics: @unchecked Sendable {
  package static let shared = DrawingLibraryDiagnostics()
  private let lock = NSLock()
  private var values = [String: UInt64]()
  package func record(_ name: String, count: UInt64 = 1) {
    lock.lock(); defer { lock.unlock() }
    values[name, default: 0] += count
  }
  package func snapshot() -> [String: UInt64] {
    lock.lock(); defer { lock.unlock() }; return values
  }
}
