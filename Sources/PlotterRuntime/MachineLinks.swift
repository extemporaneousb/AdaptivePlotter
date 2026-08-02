import Darwin
import Foundation
import IOKit
import IOKit.serial

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

  public init(expectedWrite: Data, reads: [ScheduledMachineRead]) {
    self.expectedWrite = Data(expectedWrite)
    self.reads = reads
  }
}

private final class ScriptEngine: @unchecked Sendable {
  private struct State {
    var isOpen = false
    var nextExchange = 0
    var queuedReads: [ScheduledMachineRead] = []
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
      guard state.queuedReads.isEmpty else {
        throw MachineLinkError.unexpectedWrite(expected: Data(), actual: bytes)
      }
      state.nextExchange += 1
      state.queuedReads = exchange.reads
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

public final class SimulatedGRBLLink: MachineLink, @unchecked Sendable {
  public let descriptor: MachineLinkDescriptor
  private let engine: ScriptEngine

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
    engine = ScriptEngine(exchanges: exchanges, clock: clock)
  }

  public func open() async throws { try engine.open() }
  public func close() async { engine.close() }
  public func write(_ bytes: Data) async throws { try engine.write(bytes) }
  public func read(maximumBytes: Int, timeoutNanoseconds: UInt64) async throws -> Data {
    try await engine.read(maximumBytes: maximumBytes, timeoutNanoseconds: timeoutNanoseconds)
  }
}

public struct TranscriptEntry: Sendable, Equatable {
  public let direction: MachineIODirection
  public let bytes: Data
  public let delayNanoseconds: UInt64

  public init(direction: MachineIODirection, bytes: Data, delayNanoseconds: UInt64 = 0) {
    self.direction = direction
    self.bytes = Data(bytes)
    self.delayNanoseconds = delayNanoseconds
  }
}

public final class TranscriptReplayLink: MachineLink, @unchecked Sendable {
  public let descriptor: MachineLinkDescriptor
  private let engine: ScriptEngine

  public init(
    identifier: String = "transcript-replay",
    entries: [TranscriptEntry],
    clock: any RuntimeClock = SystemRuntimeClock()
  ) throws {
    var exchanges: [SimulatedCommandExchange] = []
    var pendingWrite: Data?
    var reads: [ScheduledMachineRead] = []
    for entry in entries {
      switch entry.direction {
      case .transmit:
        if let pendingWrite {
          exchanges.append(SimulatedCommandExchange(expectedWrite: pendingWrite, reads: reads))
        }
        pendingWrite = entry.bytes
        reads = []
      case .receive:
        guard pendingWrite != nil else {
          throw MachineLinkError.unexpectedWrite(expected: Data(), actual: entry.bytes)
        }
        reads.append(
          ScheduledMachineRead(
            delayNanoseconds: entry.delayNanoseconds,
            outcome: .bytes(entry.bytes)
          )
        )
      }
    }
    if let pendingWrite {
      exchanges.append(SimulatedCommandExchange(expectedWrite: pendingWrite, reads: reads))
    }
    descriptor = MachineLinkDescriptor(
      identifier: identifier,
      displayName: "Controller Transcript Replay",
      bsdPath: nil,
      transport: .transcriptReplay
    )
    engine = ScriptEngine(exchanges: exchanges, clock: clock)
  }

  public func open() async throws { try engine.open() }
  public func close() async { engine.close() }
  public func write(_ bytes: Data) async throws { try engine.write(bytes) }
  public func read(maximumBytes: Int, timeoutNanoseconds: UInt64) async throws -> Data {
    try await engine.read(maximumBytes: maximumBytes, timeoutNanoseconds: timeoutNanoseconds)
  }
}

public enum SerialPortDiscovery {
  public static func discover() -> [MachineLinkDescriptor] {
    guard let matching = IOServiceMatching(kIOSerialBSDServiceValue) else { return [] }
    let typeKey = kIOSerialBSDTypeKey as CFString
    let allTypes = kIOSerialBSDAllTypes as CFString
    CFDictionarySetValue(
      matching,
      Unmanaged.passUnretained(typeKey).toOpaque(),
      Unmanaged.passUnretained(allTypes).toOpaque()
    )

    var iterator: io_iterator_t = 0
    guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS
    else {
      return []
    }
    defer { IOObjectRelease(iterator) }

    var descriptors: [MachineLinkDescriptor] = []
    while case let service = IOIteratorNext(iterator), service != 0 {
      defer { IOObjectRelease(service) }
      guard let path = property(kIOCalloutDeviceKey, service: service) else { continue }
      let name =
        property(kIOTTYDeviceKey, service: service) ?? URL(fileURLWithPath: path).lastPathComponent
      descriptors.append(
        MachineLinkDescriptor(
          identifier: path,
          displayName: name,
          bsdPath: path,
          transport: .bsdSerial
        )
      )
    }
    return descriptors.sorted { $0.identifier < $1.identifier }
  }

  private static func property(_ key: String, service: io_registry_entry_t) -> String? {
    IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?
      .takeRetainedValue() as? String
  }
}

final class BSDSerialLink: MachineLink, @unchecked Sendable {
  let descriptor: MachineLinkDescriptor
  private let baudRate: speed_t
  private let writeTimeoutNanoseconds: UInt64
  private let lock = NSLock()
  private var fileDescriptor: Int32 = -1

  init(
    descriptor: MachineLinkDescriptor,
    baudRate: speed_t = speed_t(B115200),
    writeTimeoutNanoseconds: UInt64 = 500_000_000
  ) throws {
    guard descriptor.transport == .bsdSerial, descriptor.bsdPath != nil else {
      throw MachineLinkError.invalidPath(descriptor.bsdPath ?? "")
    }
    self.descriptor = descriptor
    self.baudRate = baudRate
    self.writeTimeoutNanoseconds = writeTimeoutNanoseconds
  }

  func open() async throws {
    let path = descriptor.bsdPath ?? ""
    let descriptorFD = Darwin.open(path, O_RDWR | O_NOCTTY | O_NONBLOCK)
    guard descriptorFD >= 0 else {
      throw MachineLinkError.operatingSystem(code: errno, operation: "open")
    }
    do {
      var options = termios()
      guard tcgetattr(descriptorFD, &options) == 0 else {
        throw MachineLinkError.operatingSystem(code: errno, operation: "tcgetattr")
      }
      cfmakeraw(&options)
      guard cfsetspeed(&options, baudRate) == 0 else {
        throw MachineLinkError.operatingSystem(code: errno, operation: "cfsetspeed")
      }
      options.c_cflag |= tcflag_t(CLOCAL | CREAD)
      guard tcsetattr(descriptorFD, TCSANOW, &options) == 0 else {
        throw MachineLinkError.operatingSystem(code: errno, operation: "tcsetattr")
      }
      try lock.withLock {
        guard fileDescriptor < 0 else { throw MachineLinkError.alreadyOpen }
        fileDescriptor = descriptorFD
      }
    } catch {
      Darwin.close(descriptorFD)
      throw error
    }
  }

  func close() async {
    let descriptorFD = lock.withLock { () -> Int32 in
      let value = fileDescriptor
      fileDescriptor = -1
      return value
    }
    if descriptorFD >= 0 { Darwin.close(descriptorFD) }
  }

  func write(_ bytes: Data) async throws {
    let descriptorFD = try openFileDescriptor()
    try await NonblockingFileWriter.writeAll(
      bytes,
      to: descriptorFD,
      timeoutNanoseconds: writeTimeoutNanoseconds
    )
  }

  func read(maximumBytes: Int, timeoutNanoseconds: UInt64) async throws -> Data {
    let descriptorFD = try openFileDescriptor()
    var pollDescriptor = pollfd(fd: descriptorFD, events: Int16(POLLIN), revents: 0)
    let timeoutMilliseconds = Int32(min(timeoutNanoseconds / 1_000_000, UInt64(Int32.max)))
    let pollResult = Darwin.poll(&pollDescriptor, 1, timeoutMilliseconds)
    if pollResult == 0 { throw MachineLinkError.timedOut }
    guard pollResult > 0 else {
      if errno == EINTR { throw MachineLinkError.timedOut }
      throw MachineLinkError.operatingSystem(code: errno, operation: "poll")
    }
    if pollDescriptor.revents & Int16(POLLHUP | POLLERR) != 0 {
      throw MachineLinkError.disconnected
    }
    var bytes = [UInt8](repeating: 0, count: max(1, maximumBytes))
    let count = Darwin.read(descriptorFD, &bytes, bytes.count)
    if count == 0 { throw MachineLinkError.disconnected }
    guard count > 0 else {
      if errno == EAGAIN || errno == EINTR { throw MachineLinkError.timedOut }
      throw MachineLinkError.operatingSystem(code: errno, operation: "read")
    }
    return Data(bytes.prefix(count))
  }

  private func openFileDescriptor() throws -> Int32 {
    try lock.withLock {
      guard fileDescriptor >= 0 else { throw MachineLinkError.notOpen }
      return fileDescriptor
    }
  }
}

enum NonblockingFileWriter {
  static func writeAll(
    _ bytes: Data,
    to fileDescriptor: Int32,
    timeoutNanoseconds: UInt64
  ) async throws {
    guard !bytes.isEmpty else { return }
    let started = DispatchTime.now().uptimeNanoseconds
    let (sum, overflow) = started.addingReportingOverflow(timeoutNanoseconds)
    let deadline = overflow ? UInt64.max : sum
    var written = 0

    while written < bytes.count {
      guard !Task.isCancelled else {
        throw MachineLinkError.writeCancelled(bytesWritten: written, totalBytes: bytes.count)
      }
      guard DispatchTime.now().uptimeNanoseconds < deadline else {
        throw MachineLinkError.writeTimedOut(bytesWritten: written, totalBytes: bytes.count)
      }

      let result: Int = bytes.withUnsafeBytes { buffer in
        guard let base = buffer.baseAddress else { return 0 }
        return Darwin.write(
          fileDescriptor,
          base.advanced(by: written),
          buffer.count - written
        )
      }
      let errorCode = errno
      if result > 0 {
        written += result
        continue
      }
      if result == 0 || errorCode == EAGAIN || errorCode == EWOULDBLOCK {
        try await waitUntilWritable(
          fileDescriptor,
          deadline: deadline,
          bytesWritten: written,
          totalBytes: bytes.count
        )
        await Task.yield()
        continue
      }
      if errorCode == EINTR {
        await Task.yield()
        continue
      }
      throw MachineLinkError.operatingSystem(code: errorCode, operation: "write")
    }
  }

  private static func waitUntilWritable(
    _ fileDescriptor: Int32,
    deadline: UInt64,
    bytesWritten: Int,
    totalBytes: Int
  ) async throws {
    while true {
      guard !Task.isCancelled else {
        throw MachineLinkError.writeCancelled(
          bytesWritten: bytesWritten,
          totalBytes: totalBytes
        )
      }
      let now = DispatchTime.now().uptimeNanoseconds
      guard now < deadline else {
        throw MachineLinkError.writeTimedOut(
          bytesWritten: bytesWritten,
          totalBytes: totalBytes
        )
      }
      let remaining = deadline - now
      let wholeMilliseconds = remaining / 1_000_000
      let roundedMilliseconds = wholeMilliseconds + (remaining % 1_000_000 == 0 ? 0 : 1)
      let timeoutMilliseconds = Int32(min(roundedMilliseconds, UInt64(Int32.max)))
      var descriptor = pollfd(fd: fileDescriptor, events: Int16(POLLOUT), revents: 0)
      let pollResult = Darwin.poll(&descriptor, 1, timeoutMilliseconds)
      if pollResult > 0 {
        if descriptor.revents & Int16(POLLHUP | POLLERR | POLLNVAL) != 0 {
          throw MachineLinkError.disconnected
        }
        if descriptor.revents & Int16(POLLOUT) != 0 { return }
        await Task.yield()
        continue
      }
      if pollResult == 0 {
        throw MachineLinkError.writeTimedOut(
          bytesWritten: bytesWritten,
          totalBytes: totalBytes
        )
      }
      let errorCode = errno
      if errorCode == EINTR {
        await Task.yield()
        continue
      }
      throw MachineLinkError.operatingSystem(code: errorCode, operation: "poll write")
    }
  }
}
