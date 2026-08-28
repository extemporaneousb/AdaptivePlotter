import Darwin
import Foundation
import IOKit
import IOKit.serial

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

enum BSDPendingInputSnapshot: Equatable, Sendable {
  case observed(byteCount: Int)
  case failed(reason: MachineLinkTransferFailureReason)
}

enum BSDPendingInputReadAttempt: Equatable, Sendable {
  case bytes(Int)
  case interrupted
  case wouldBlock(code: Int32)
  case disconnected
  case operatingSystem(code: Int32)
}

/// Deterministic completion policy for the production BSD discard operation.
/// The syscall adapter remains in `BSDSerialLink`; this core owns the safety
/// rule that the complete observed snapshot is removed or the operation fails.
enum BSDPendingInputDiscarder {
  static let maximumReadByteCount = 4_096
  static let maximumInterruptedReadRetries = 8

  static func discard(
    snapshot: BSDPendingInputSnapshot,
    read: (Int) -> BSDPendingInputReadAttempt
  ) throws -> MachineLinkDiscardReceipt {
    let snapshotByteCount: Int
    switch snapshot {
    case .observed(let byteCount):
      guard byteCount >= 0 else {
        throw MachineLinkError.discardFailed(
          discarded: 0,
          total: nil,
          reason: .operatingSystem(
            code: EINVAL,
            operation: "ioctl FIONREAD returned a negative byte count"
          )
        )
      }
      snapshotByteCount = byteCount
    case .failed(let reason):
      throw MachineLinkError.discardFailed(
        discarded: 0,
        total: nil,
        reason: reason
      )
    }

    var discardedByteCount = 0
    var interruptedReadCount = 0
    while discardedByteCount < snapshotByteCount {
      let requestedByteCount = min(
        maximumReadByteCount,
        snapshotByteCount - discardedByteCount
      )
      switch read(requestedByteCount) {
      case .bytes(let count):
        guard count > 0, count <= requestedByteCount else {
          throw MachineLinkError.discardFailed(
            discarded: discardedByteCount,
            total: snapshotByteCount,
            reason: .operatingSystem(
              code: EOVERFLOW,
              operation: "discard input read returned an invalid byte count"
            )
          )
        }
        discardedByteCount += count
      case .interrupted:
        interruptedReadCount += 1
        guard interruptedReadCount <= maximumInterruptedReadRetries else {
          throw MachineLinkError.discardFailed(
            discarded: discardedByteCount,
            total: snapshotByteCount,
            reason: .operatingSystem(
              code: EINTR,
              operation: "discard input read exceeded interruption retry budget"
            )
          )
        }
      case .wouldBlock(let code):
        throw MachineLinkError.discardFailed(
          discarded: discardedByteCount,
          total: snapshotByteCount,
          reason: .operatingSystem(code: code, operation: "discard input read would block")
        )
      case .disconnected:
        throw MachineLinkError.discardFailed(
          discarded: discardedByteCount,
          total: snapshotByteCount,
          reason: .disconnected
        )
      case .operatingSystem(let code):
        throw MachineLinkError.discardFailed(
          discarded: discardedByteCount,
          total: snapshotByteCount,
          reason: .operatingSystem(code: code, operation: "discard input read")
        )
      }
    }
    return MachineLinkDiscardReceipt(discardedByteCount: discardedByteCount)
  }
}

final class BSDSerialLink: MachineLink, @unchecked Sendable {
  /// Darwin's `FIONREAD` is `_IOR('f', 127, int)`, but Clang cannot import
  /// that structure-valued macro into Swift. Reconstruct the request from the
  /// SDK's public `_IOC` layout: OUT | sizeof(Int32) | group "f" | command 127.
  private static let pendingInputByteCountIOCTLRequest: UInt = {
    let copyParameterOut: UInt = 0x4000_0000
    let parameterLength = UInt(MemoryLayout<Int32>.size & 0x1FFF) << 16
    let fileDescriptorGroup: UInt = 0x66 << 8
    let command: UInt = 127
    return copyParameterOut | parameterLength | fileDescriptorGroup | command
  }()

  let descriptor: MachineLinkDescriptor
  private let baudRate: speed_t
  private let writeTimeoutNanoseconds: UInt64
  private let clock: any RuntimeClock
  private let lock = NSLock()
  private var fileDescriptor: Int32 = -1

  init(
    descriptor: MachineLinkDescriptor,
    baudRate: speed_t = speed_t(B115200),
    writeTimeoutNanoseconds: UInt64 = 500_000_000,
    clock: any RuntimeClock = SystemRuntimeClock()
  ) throws {
    guard descriptor.transport == .bsdSerial, descriptor.bsdPath != nil else {
      throw MachineLinkError.invalidPath(descriptor.bsdPath ?? "")
    }
    self.descriptor = descriptor
    self.baudRate = baudRate
    self.writeTimeoutNanoseconds = writeTimeoutNanoseconds
    self.clock = clock
  }

  func open() async throws -> MachineLinkOpenReceipt {
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
      var appliedOptions = termios()
      guard tcgetattr(descriptorFD, &appliedOptions) == 0 else {
        throw MachineLinkError.operatingSystem(code: errno, operation: "tcgetattr applied")
      }
      let appliedConfiguration = try Self.appliedConfiguration(
        endpoint: path,
        options: appliedOptions
      )
      try lock.withLock {
        guard fileDescriptor < 0 else { throw MachineLinkError.alreadyOpen }
        fileDescriptor = descriptorFD
      }
      return MachineLinkOpenReceipt(appliedConfiguration: .bsdSerial(appliedConfiguration))
    } catch {
      Darwin.close(descriptorFD)
      throw error
    }
  }

  func close() async throws {
    let descriptorFD = lock.withLock { () -> Int32 in
      let value = fileDescriptor
      fileDescriptor = -1
      return value
    }
    guard descriptorFD >= 0 else { return }
    guard Darwin.close(descriptorFD) == 0 else {
      throw MachineLinkError.operatingSystem(code: errno, operation: "close")
    }
  }

  func discardPendingInput() async throws -> MachineLinkDiscardReceipt {
    let descriptorFD = try openFileDescriptor()
    var pendingByteCount: Int32 = 0
    let snapshot: BSDPendingInputSnapshot
    if ioctl(descriptorFD, Self.pendingInputByteCountIOCTLRequest, &pendingByteCount) == 0 {
      snapshot = .observed(byteCount: Int(pendingByteCount))
    } else {
      snapshot = .failed(
        reason: .operatingSystem(code: errno, operation: "ioctl FIONREAD")
      )
    }
    var buffer = [UInt8](
      repeating: 0,
      count: BSDPendingInputDiscarder.maximumReadByteCount
    )
    return try BSDPendingInputDiscarder.discard(snapshot: snapshot) { requestedByteCount in
      let count = Darwin.read(descriptorFD, &buffer, requestedByteCount)
      if count > 0 { return .bytes(count) }
      if count == 0 { return .disconnected }
      let errorCode = errno
      if errorCode == EINTR { return .interrupted }
      if errorCode == EAGAIN || errorCode == EWOULDBLOCK {
        return .wouldBlock(code: errorCode)
      }
      return .operatingSystem(code: errorCode)
    }
  }

  func write(_ bytes: Data) async throws -> MachineLinkWriteReceipt {
    let descriptorFD = try openFileDescriptor()
    let writtenByteCount = try await NonblockingFileWriter.writeAll(
      bytes,
      to: descriptorFD,
      timeoutNanoseconds: writeTimeoutNanoseconds
    )
    return MachineLinkWriteReceipt(writtenByteCount: writtenByteCount)
  }

  func read(
    maximumBytes: Int,
    timeoutNanoseconds: UInt64
  ) async throws -> MachineLinkReadReceipt {
    let descriptorFD = try openFileDescriptor()
    guard maximumBytes > 0 else {
      return MachineLinkReadReceipt(
        bytes: Data(),
        receivedAtMonotonicNanoseconds: clock.nowNanoseconds()
      )
    }
    var pollDescriptor = pollfd(fd: descriptorFD, events: Int16(POLLIN), revents: 0)
    let timeoutMilliseconds = Int32(min(timeoutNanoseconds / 1_000_000, UInt64(Int32.max)))
    let pollResult = Darwin.poll(&pollDescriptor, 1, timeoutMilliseconds)
    if pollResult == 0 {
      throw MachineLinkError.readFailed(
        partialReceipts: [],
        maximumBytes: maximumBytes,
        reason: .timedOut
      )
    }
    guard pollResult > 0 else {
      let errorCode = errno
      let reason: MachineLinkTransferFailureReason = errorCode == EINTR
        ? .timedOut
        : .operatingSystem(code: errorCode, operation: "poll read")
      throw MachineLinkError.readFailed(
        partialReceipts: [],
        maximumBytes: maximumBytes,
        reason: reason
      )
    }
    if pollDescriptor.revents & Int16(POLLNVAL) != 0 {
      throw MachineLinkError.readFailed(
        partialReceipts: [],
        maximumBytes: maximumBytes,
        reason: .operatingSystem(code: EBADF, operation: "poll read")
      )
    }
    if pollDescriptor.revents & Int16(POLLHUP | POLLERR) != 0 {
      throw MachineLinkError.readFailed(
        partialReceipts: [],
        maximumBytes: maximumBytes,
        reason: .disconnected
      )
    }
    var bytes = [UInt8](repeating: 0, count: maximumBytes)
    let count = Darwin.read(descriptorFD, &bytes, bytes.count)
    if count == 0 {
      throw MachineLinkError.readFailed(
        partialReceipts: [],
        maximumBytes: maximumBytes,
        reason: .disconnected
      )
    }
    guard count > 0 else {
      let errorCode = errno
      let reason: MachineLinkTransferFailureReason =
        errorCode == EAGAIN || errorCode == EINTR
        ? .timedOut
        : .operatingSystem(code: errorCode, operation: "read")
      throw MachineLinkError.readFailed(
        partialReceipts: [],
        maximumBytes: maximumBytes,
        reason: reason
      )
    }
    let receivedAtMonotonicNanoseconds = clock.nowNanoseconds()
    return MachineLinkReadReceipt(
      bytes: Data(bytes.prefix(count)),
      receivedAtMonotonicNanoseconds: receivedAtMonotonicNanoseconds
    )
  }

  private func openFileDescriptor() throws -> Int32 {
    try lock.withLock {
      guard fileDescriptor >= 0 else { throw MachineLinkError.notOpen }
      return fileDescriptor
    }
  }

  static func appliedConfiguration(
    endpoint: String,
    options: termios
  ) throws -> MachineLinkBSDSerialAppliedConfiguration {
    var options = options
    let size = options.c_cflag & tcflag_t(CSIZE)
    let dataBits: UInt8
    switch size {
    case tcflag_t(CS5): dataBits = 5
    case tcflag_t(CS6): dataBits = 6
    case tcflag_t(CS7): dataBits = 7
    case tcflag_t(CS8): dataBits = 8
    default:
      throw MachineLinkError.operatingSystem(code: EINVAL, operation: "decode data bits")
    }
    let parity: MachineLinkParity
    if options.c_cflag & tcflag_t(PARENB) == 0 {
      parity = .none
    } else if options.c_cflag & tcflag_t(PARODD) == 0 {
      parity = .even
    } else {
      parity = .odd
    }
    let usesHardwareFlowControl = options.c_cflag & tcflag_t(CRTSCTS) != 0
    let usesSoftwareFlowControl = options.c_iflag & tcflag_t(IXON | IXOFF) != 0
    let flowControl: MachineLinkFlowControl
    switch (usesHardwareFlowControl, usesSoftwareFlowControl) {
    case (false, false): flowControl = .none
    case (true, false): flowControl = .hardware
    case (false, true): flowControl = .software
    case (true, true): flowControl = .hardwareAndSoftware
    }
    return MachineLinkBSDSerialAppliedConfiguration(
      endpoint: endpoint,
      inputBaudRate: UInt64(cfgetispeed(&options)),
      outputBaudRate: UInt64(cfgetospeed(&options)),
      dataBits: dataBits,
      stopBits: options.c_cflag & tcflag_t(CSTOPB) == 0 ? 1 : 2,
      parity: parity,
      flowControl: flowControl,
      localModeEnabled: options.c_cflag & tcflag_t(CLOCAL) != 0,
      receiverEnabled: options.c_cflag & tcflag_t(CREAD) != 0
    )
  }
}

enum NonblockingFileWriter {
  static func writeAll(
    _ bytes: Data,
    to fileDescriptor: Int32,
    timeoutNanoseconds: UInt64
  ) async throws -> Int {
    guard !bytes.isEmpty else { return 0 }
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
      throw MachineLinkError.writeFailed(
        bytesWritten: written,
        totalBytes: bytes.count,
        reason: .operatingSystem(code: errorCode, operation: "write")
      )
    }
    return written
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
        if descriptor.revents & Int16(POLLNVAL) != 0 {
          throw MachineLinkError.writeFailed(
            bytesWritten: bytesWritten,
            totalBytes: totalBytes,
            reason: .operatingSystem(code: EBADF, operation: "poll write")
          )
        }
        if descriptor.revents & Int16(POLLHUP | POLLERR) != 0 {
          throw MachineLinkError.writeFailed(
            bytesWritten: bytesWritten,
            totalBytes: totalBytes,
            reason: .disconnected
          )
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
      throw MachineLinkError.writeFailed(
        bytesWritten: bytesWritten,
        totalBytes: totalBytes,
        reason: .operatingSystem(code: errorCode, operation: "poll write")
      )
    }
  }
}
