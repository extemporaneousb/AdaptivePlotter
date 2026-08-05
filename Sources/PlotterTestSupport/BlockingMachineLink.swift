import Foundation
import PlotterRuntime

/// Deterministic synchronization for operation-in-flight tests. The selected
/// write reaches the underlying scripted link, then remains suspended until the
/// test releases it. This avoids wall-clock sleeps and scheduler-dependent races.
public actor MachineWriteGate {
  private var hasReachedBlockedWrite = false
  private var isReleased = false
  private var reachedWaiters: [CheckedContinuation<Void, Never>] = []
  private var releaseWaiters: [CheckedContinuation<Void, Never>] = []

  public init() {}

  public func waitUntilBlockedWrite() async {
    guard !hasReachedBlockedWrite else { return }
    await withCheckedContinuation { reachedWaiters.append($0) }
  }

  public func release() {
    isReleased = true
    let waiters = releaseWaiters
    releaseWaiters.removeAll(keepingCapacity: false)
    for waiter in waiters { waiter.resume() }
  }

  fileprivate func suspendAfterBlockedWrite() async {
    hasReachedBlockedWrite = true
    let observers = reachedWaiters
    reachedWaiters.removeAll(keepingCapacity: false)
    for observer in observers { observer.resume() }
    guard !isReleased else { return }
    await withCheckedContinuation { releaseWaiters.append($0) }
  }
}

public final class BlockingMachineLink: MachineLink, @unchecked Sendable {
  public let descriptor: MachineLinkDescriptor

  private let base: any MachineLink
  private let blockedWrite: Data
  private let gate: MachineWriteGate

  public init(
    base: any MachineLink,
    blockedWrite: Data,
    gate: MachineWriteGate
  ) {
    self.base = base
    self.blockedWrite = Data(blockedWrite)
    self.gate = gate
    descriptor = base.descriptor
  }

  public func open() async throws { try await base.open() }
  public func close() async { await base.close() }
  public func discardPendingInput() async throws { try await base.discardPendingInput() }

  public func write(_ bytes: Data) async throws {
    try await base.write(bytes)
    if bytes == blockedWrite { await gate.suspendAfterBlockedWrite() }
  }

  public func read(maximumBytes: Int, timeoutNanoseconds: UInt64) async throws -> Data {
    try await base.read(maximumBytes: maximumBytes, timeoutNanoseconds: timeoutNanoseconds)
  }
}
