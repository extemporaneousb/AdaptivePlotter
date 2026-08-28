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

  func discardPendingInput() throws -> Int {
    try lock.withLock {
      guard state.isOpen else { throw MachineLinkError.notOpen }
      state.discardCount += 1
      if let error = state.nextDiscardError {
        state.nextDiscardError = nil
        throw error
      }
      let discardedByteCount = state.queuedReads.reduce(into: 0) { count, read in
        if case .bytes(let bytes) = read.outcome { count += bytes.count }
      }
      state.queuedReads.removeAll()
      return discardedByteCount
    }
  }

  func write(_ bytes: Data) throws -> Int {
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
      if let writeError = exchange.writeError {
        switch writeError {
        case .disconnected:
          throw MachineLinkError.writeFailed(
            bytesWritten: 0,
            totalBytes: bytes.count,
            reason: .disconnected
          )
        case .operatingSystem(let code, let operation):
          throw MachineLinkError.writeFailed(
            bytesWritten: 0,
            totalBytes: bytes.count,
            reason: .operatingSystem(code: code, operation: operation)
          )
        case .timedOut:
          throw MachineLinkError.writeTimedOut(bytesWritten: 0, totalBytes: bytes.count)
        default:
          throw writeError
        }
      }
      state.queuedReads.append(contentsOf: exchange.reads)
      return bytes.count
    }
  }

  func read(
    maximumBytes: Int,
    timeoutNanoseconds: UInt64
  ) async throws -> MachineLinkReadReceipt {
    guard maximumBytes > 0 else {
      return MachineLinkReadReceipt(
        bytes: Data(),
        receivedAtMonotonicNanoseconds: clock.nowNanoseconds()
      )
    }
    let scheduled: ScheduledMachineRead? = try lock.withLock {
      guard state.isOpen else { throw MachineLinkError.notOpen }
      return state.queuedReads.first
    }

    guard let scheduled else {
      do {
        try await clock.sleep(nanoseconds: timeoutNanoseconds)
      } catch is CancellationError {
        throw MachineLinkError.readFailed(
          partialReceipts: [],
          maximumBytes: maximumBytes,
          reason: .cancelled
        )
      }
      throw MachineLinkError.readFailed(
        partialReceipts: [],
        maximumBytes: maximumBytes,
        reason: .timedOut
      )
    }
    guard scheduled.delayNanoseconds <= timeoutNanoseconds else {
      do {
        try await clock.sleep(nanoseconds: timeoutNanoseconds)
      } catch is CancellationError {
        throw MachineLinkError.readFailed(
          partialReceipts: [],
          maximumBytes: maximumBytes,
          reason: .cancelled
        )
      }
      throw MachineLinkError.readFailed(
        partialReceipts: [],
        maximumBytes: maximumBytes,
        reason: .timedOut
      )
    }
    do {
      try await clock.sleep(nanoseconds: scheduled.delayNanoseconds)
    } catch is CancellationError {
      throw MachineLinkError.readFailed(
        partialReceipts: [],
        maximumBytes: maximumBytes,
        reason: .cancelled
      )
    }

    let consumed: ScheduledMachineRead = try lock.withLock {
      guard state.isOpen else {
        throw MachineLinkError.readFailed(
          partialReceipts: [],
          maximumBytes: maximumBytes,
          reason: .disconnected
        )
      }
      guard !state.queuedReads.isEmpty else {
        throw MachineLinkError.readFailed(
          partialReceipts: [],
          maximumBytes: maximumBytes,
          reason: .timedOut
        )
      }
      return state.queuedReads.removeFirst()
    }
    let receivedAtMonotonicNanoseconds = clock.nowNanoseconds()
    switch consumed.outcome {
    case .bytes(let bytes):
      if bytes.count <= maximumBytes {
        return MachineLinkReadReceipt(
          bytes: bytes,
          receivedAtMonotonicNanoseconds: receivedAtMonotonicNanoseconds
        )
      }
      let chunk = Data(bytes.prefix(maximumBytes))
      let suffix = Data(bytes.dropFirst(maximumBytes))
      lock.withLock {
        state.queuedReads.insert(
          ScheduledMachineRead(delayNanoseconds: 0, outcome: .bytes(suffix)),
          at: 0
        )
      }
      return MachineLinkReadReceipt(
        bytes: chunk,
        receivedAtMonotonicNanoseconds: receivedAtMonotonicNanoseconds
      )
    case .disconnect:
      lock.withLock { state.isOpen = false }
      throw MachineLinkError.readFailed(
        partialReceipts: [],
        maximumBytes: maximumBytes,
        reason: .disconnected
      )
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

  public func open() async throws -> MachineLinkOpenReceipt {
    try engine.open()
    return MachineLinkOpenReceipt(
      appliedConfiguration: .simulated(identifier: descriptor.identifier)
    )
  }

  public func close() async throws { engine.close() }

  public func discardPendingInput() async throws -> MachineLinkDiscardReceipt {
    MachineLinkDiscardReceipt(discardedByteCount: try engine.discardPendingInput())
  }

  public func write(_ bytes: Data) async throws -> MachineLinkWriteReceipt {
    do {
      return MachineLinkWriteReceipt(writtenByteCount: try engine.write(bytes))
    } catch let error as MachineLinkError {
      switch error {
      case .timedOut:
        throw MachineLinkError.writeTimedOut(bytesWritten: 0, totalBytes: bytes.count)
      case .disconnected:
        throw MachineLinkError.writeFailed(
          bytesWritten: 0,
          totalBytes: bytes.count,
          reason: .disconnected
        )
      case .operatingSystem(let code, let operation):
        throw MachineLinkError.writeFailed(
          bytesWritten: 0,
          totalBytes: bytes.count,
          reason: .operatingSystem(code: code, operation: operation)
        )
      default:
        throw error
      }
    }
  }

  public func read(
    maximumBytes: Int,
    timeoutNanoseconds: UInt64
  ) async throws -> MachineLinkReadReceipt {
    do {
      return try await engine.read(
        maximumBytes: maximumBytes,
        timeoutNanoseconds: timeoutNanoseconds
      )
    } catch is CancellationError {
      throw MachineLinkError.readFailed(
        partialReceipts: [],
        maximumBytes: maximumBytes,
        reason: .cancelled
      )
    } catch let error as MachineLinkError {
      switch error {
      case .timedOut:
        throw MachineLinkError.readFailed(
          partialReceipts: [],
          maximumBytes: maximumBytes,
          reason: .timedOut
        )
      case .disconnected:
        throw MachineLinkError.readFailed(
          partialReceipts: [],
          maximumBytes: maximumBytes,
          reason: .disconnected
        )
      case .operatingSystem(let code, let operation):
        throw MachineLinkError.readFailed(
          partialReceipts: [],
          maximumBytes: maximumBytes,
          reason: .operatingSystem(code: code, operation: operation)
        )
      default:
        throw error
      }
    }
  }

  public var completedWriteCount: Int { engine.completedWriteCount() }
  public var pendingInputDiscardCount: Int { engine.discardCount() }

  public func preloadPendingInput(_ bytes: Data) { engine.preloadPendingInput(bytes) }
  public func failNextPendingInputDiscard(with error: MachineLinkError) {
    engine.failNextDiscard(with: error)
  }
}
