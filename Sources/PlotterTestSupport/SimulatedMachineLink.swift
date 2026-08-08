import Foundation
import PlotterRuntime

public enum ScriptedReadOutcome: Sendable, Equatable {
  case bytes(Data)
  case disconnect
}

public struct ScheduledMachineRead: Sendable, Equatable {
  public let delayNanoseconds: UInt64
  public let outcome: ScriptedReadOutcome

  public init(delayNanoseconds: UInt64 = 0, outcome: ScriptedReadOutcome) {
    self.delayNanoseconds = delayNanoseconds
    self.outcome = outcome
  }
}

public struct SimulatedCommandExchange: Sendable, Equatable {
  public let expectedWrite: Data
  public let reads: [ScheduledMachineRead]
  public let writeError: MachineLinkError?

  public init(
    expectedWrite: Data,
    reads: [ScheduledMachineRead],
    writeError: MachineLinkError? = nil
  ) {
    self.expectedWrite = Data(expectedWrite)
    self.reads = reads
    self.writeError = writeError
  }
}

private final class SimulatedMachineLinkEngine: @unchecked Sendable {
  private struct State {
    var isOpen = false
    var nextExchange = 0
    var queuedReads: [ScheduledMachineRead] = []
    var discardCount = 0
    var nextDiscardError: MachineLinkError?
  }

  private let lock = NSLock()
  private var state = State()
  private let exchanges: [SimulatedCommandExchange]
  private let clock: any RuntimeClock

  init(exchanges: [SimulatedCommandExchange], clock: any RuntimeClock) {
    self.exchanges = exchanges
    self.clock = clock
  }

  func open() throws {
    try lock.withLock {
      guard !state.isOpen else { throw MachineLinkError.alreadyOpen }
      state.isOpen = true
    }
  }

  func close() {
    lock.withLock {
      state.isOpen = false
      state.queuedReads.removeAll()
    }
  }

  func completedWriteCount() -> Int {
    lock.withLock { state.nextExchange }
  }

  func discardCount() -> Int {
    lock.withLock { state.discardCount }
  }

  func preloadPendingInput(_ bytes: Data) {
    lock.withLock {
      state.queuedReads.append(ScheduledMachineRead(outcome: .bytes(bytes)))
    }
  }

  func failNextDiscard(with error: MachineLinkError) {
    lock.withLock { state.nextDiscardError = error }
  }

  func discardPendingInput() throws {
    try lock.withLock {
      guard state.isOpen else { throw MachineLinkError.notOpen }
      state.discardCount += 1
      if let error = state.nextDiscardError {
        state.nextDiscardError = nil
        throw error
      }
      state.queuedReads.removeAll()
    }
  }

  func write(_ bytes: Data) throws {
    try lock.withLock {
      guard state.isOpen else { throw MachineLinkError.notOpen }
      guard state.nextExchange < exchanges.count else {
        throw MachineLinkError.unexpectedWrite(expected: Data(), actual: bytes)
      }
      let exchange = exchanges[state.nextExchange]
      guard exchange.expectedWrite == bytes else {
        throw MachineLinkError.unexpectedWrite(expected: exchange.expectedWrite, actual: bytes)
      }
      state.nextExchange += 1
      if let writeError = exchange.writeError { throw writeError }
      state.queuedReads.append(contentsOf: exchange.reads)
    }
  }

  func read(maximumBytes: Int, timeoutNanoseconds: UInt64) async throws -> Data {
    let scheduled: ScheduledMachineRead? = try lock.withLock {
      guard state.isOpen else { throw MachineLinkError.notOpen }
      return state.queuedReads.first
    }

    guard let scheduled else {
      try await clock.sleep(nanoseconds: timeoutNanoseconds)
      throw MachineLinkError.timedOut
    }
    guard scheduled.delayNanoseconds <= timeoutNanoseconds else {
      try await clock.sleep(nanoseconds: timeoutNanoseconds)
      throw MachineLinkError.timedOut
    }
    try await clock.sleep(nanoseconds: scheduled.delayNanoseconds)

    let consumed: ScheduledMachineRead = try lock.withLock {
      guard state.isOpen else { throw MachineLinkError.disconnected }
      guard !state.queuedReads.isEmpty else { throw MachineLinkError.timedOut }
      return state.queuedReads.removeFirst()
    }
    switch consumed.outcome {
    case .bytes(let bytes):
      guard maximumBytes > 0 else { return Data() }
      if bytes.count <= maximumBytes { return bytes }
      let chunk = Data(bytes.prefix(maximumBytes))
      let suffix = Data(bytes.dropFirst(maximumBytes))
      lock.withLock {
        state.queuedReads.insert(
          ScheduledMachineRead(delayNanoseconds: 0, outcome: .bytes(suffix)),
          at: 0
        )
      }
      return chunk
    case .disconnect:
      lock.withLock { state.isOpen = false }
      throw MachineLinkError.disconnected
    }
  }
}

/// Scripted controller link for tests. It is intentionally absent from the
/// production runtime target and has no application composition entry point.
public final class SimulatedGRBLLink: MachineLink, @unchecked Sendable {
  public let descriptor: MachineLinkDescriptor
  private let engine: SimulatedMachineLinkEngine

  public init(
    identifier: String = "simulated-grbl",
    exchanges: [SimulatedCommandExchange],
    clock: any RuntimeClock = SystemRuntimeClock()
  ) {
    descriptor = MachineLinkDescriptor(
      identifier: identifier,
      displayName: "Simulated GRBL",
      bsdPath: nil,
      transport: .simulated
    )
    engine = SimulatedMachineLinkEngine(exchanges: exchanges, clock: clock)
  }

  public func open() async throws { try engine.open() }
  public func close() async { engine.close() }
  public func discardPendingInput() async throws { try engine.discardPendingInput() }
  public func write(_ bytes: Data) async throws { try engine.write(bytes) }
  public func read(maximumBytes: Int, timeoutNanoseconds: UInt64) async throws -> Data {
    try await engine.read(maximumBytes: maximumBytes, timeoutNanoseconds: timeoutNanoseconds)
  }

  public var completedWriteCount: Int { engine.completedWriteCount() }
  public var pendingInputDiscardCount: Int { engine.discardCount() }

  public func preloadPendingInput(_ bytes: Data) { engine.preloadPendingInput(bytes) }
  public func failNextPendingInputDiscard(with error: MachineLinkError) {
    engine.failNextDiscard(with: error)
  }
}
