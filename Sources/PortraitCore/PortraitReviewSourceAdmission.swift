import Foundation

/// A source selection epoch may withdraw queued authoring publication synchronously.
/// Admission is a short linearization point; cancellation after it does not undo a committed result.
public final class PortraitReviewSourceAdmissionToken: @unchecked Sendable {
  private let lock = NSLock()
  private var cancelled = false

  public init() {}
  public var isCancelled: Bool { lock.withLock { cancelled } }
  public func cancel() { lock.withLock { cancelled = true } }
  public func checkCancellation() throws {
    try lock.withLock { if cancelled { throw CancellationError() } }
  }

  /// Only the serialized library commit path uses this gate, immediately before canonical import.
  public func admitCommit() throws { try checkCancellation() }
}
