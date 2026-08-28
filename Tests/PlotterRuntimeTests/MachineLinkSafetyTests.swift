import Darwin
import Foundation
import PlotterTestSupport
import Testing

@testable import PlotterRuntime

@Suite("Nonblocking machine-link writes")
struct MachineLinkSafetyTests {
  @Test("a backpressured nonblocking descriptor reaches an absolute typed timeout")
  func boundedWriteTimeout() async throws {
    var descriptors = [Int32](repeating: -1, count: 2)
    try #require(Darwin.pipe(&descriptors) == 0)
    let readDescriptor = descriptors[0]
    let writeDescriptor = descriptors[1]
    defer {
      Darwin.close(readDescriptor)
      Darwin.close(writeDescriptor)
    }
    let flags = Darwin.fcntl(writeDescriptor, F_GETFL)
    try #require(flags >= 0)
    try #require(Darwin.fcntl(writeDescriptor, F_SETFL, flags | O_NONBLOCK) == 0)
    let payload = Data(repeating: 0x41, count: 8 * 1_024 * 1_024)

    do {
      _ = try await NonblockingFileWriter.writeAll(
        payload,
        to: writeDescriptor,
        timeoutNanoseconds: 5_000_000
      )
      Issue.record("Backpressured write unexpectedly completed")
    } catch let error as MachineLinkError {
      guard case let .writeTimedOut(bytesWritten, totalBytes) = error else {
        Issue.record("Expected typed write timeout, got \(error)")
        return
      }
      #expect(bytesWritten > 0)
      #expect(bytesWritten < totalBytes)
      #expect(totalBytes == payload.count)
    }
  }

  @Test("a cancelled write reports exact progress with a typed cancellation")
  func cancelledWrite() async throws {
    var descriptors = [Int32](repeating: -1, count: 2)
    try #require(Darwin.pipe(&descriptors) == 0)
    defer {
      Darwin.close(descriptors[0])
      Darwin.close(descriptors[1])
    }
    let task = Task {
      try await NonblockingFileWriter.writeAll(
        Data(repeating: 0x42, count: 1_024),
        to: descriptors[1],
        timeoutNanoseconds: 1_000_000_000
      )
    }
    task.cancel()

    do {
      _ = try await task.value
      Issue.record("Cancelled write unexpectedly completed")
    } catch let error as MachineLinkError {
      guard case let .writeCancelled(bytesWritten, totalBytes) = error else {
        Issue.record("Expected typed write cancellation, got \(error)")
        return
      }
      #expect(bytesWritten == 0)
      #expect(totalBytes == 1_024)
    }
  }
}

@Suite("Machine-link transcript observability")
struct MachineLinkTranscriptObservabilityTests {
  @Test("BSD applied serial configuration is derived from post-apply termios readback")
  func bsdAppliedConfigurationIsReadbackDerived() throws {
    var options = termios()
    cfmakeraw(&options)
    try #require(cfsetispeed(&options, speed_t(B9600)) == 0)
    try #require(cfsetospeed(&options, speed_t(B38400)) == 0)
    options.c_cflag &= ~tcflag_t(CSIZE)
    options.c_cflag |= tcflag_t(CS7)
    options.c_cflag |= tcflag_t(CSTOPB)
    options.c_cflag |= tcflag_t(PARENB)
    options.c_cflag |= tcflag_t(PARODD)
    options.c_cflag |= tcflag_t(CLOCAL)
    options.c_cflag |= tcflag_t(CREAD)
    options.c_cflag |= tcflag_t(CRTSCTS)
    options.c_iflag |= tcflag_t(IXON)
    options.c_iflag |= tcflag_t(IXOFF)

    let applied = try BSDSerialLink.appliedConfiguration(
      endpoint: "/dev/tty.fixture",
      options: options
    )

    #expect(applied.endpoint == "/dev/tty.fixture")
    #expect(applied.inputBaudRate == UInt64(speed_t(B9600)))
    #expect(applied.outputBaudRate == UInt64(speed_t(B38400)))
    #expect(applied.dataBits == 7)
    #expect(applied.stopBits == 2)
    #expect(applied.parity == .odd)
    #expect(applied.flowControl == .hardwareAndSoftware)
    #expect(applied.localModeEnabled)
    #expect(applied.receiverEnabled)
  }

  @Test("BSD discard succeeds only after consuming the complete observed snapshot")
  func bsdDiscardRequiresCompleteSnapshot() throws {
    var attempts: [BSDPendingInputReadAttempt] = [
      .bytes(2),
      .interrupted,
      .bytes(3),
    ]
    var requestedByteCounts: [Int] = []

    let receipt = try BSDPendingInputDiscarder.discard(
      snapshot: .observed(byteCount: 5)
    ) { requestedByteCount in
      requestedByteCounts.append(requestedByteCount)
      return attempts.removeFirst()
    }

    #expect(receipt == MachineLinkDiscardReceipt(discardedByteCount: 5))
    #expect(requestedByteCounts == [5, 3, 3])
    #expect(attempts.isEmpty)
  }

  @Test("BSD discard reports zero, partial, snapshot, and bounded-retry failures exactly")
  func bsdDiscardFailuresAreExact() throws {
    do {
      _ = try BSDPendingInputDiscarder.discard(
        snapshot: .observed(byteCount: 4),
        read: { _ in .wouldBlock(code: EAGAIN) }
      )
      Issue.record("Would-block discard incorrectly reported success")
    } catch let error as MachineLinkError {
      #expect(
        error == .discardFailed(
          discarded: 0,
          total: 4,
          reason: .operatingSystem(code: EAGAIN, operation: "discard input read would block")
        )
      )
    }

    do {
      _ = try BSDPendingInputDiscarder.discard(
        snapshot: .observed(byteCount: 3),
        read: { _ in .operatingSystem(code: EIO) }
      )
      Issue.record("Zero-progress OS discard incorrectly reported success")
    } catch let error as MachineLinkError {
      #expect(
        error == .discardFailed(
          discarded: 0,
          total: 3,
          reason: .operatingSystem(code: EIO, operation: "discard input read")
        )
      )
    }

    var partialAttempts: [BSDPendingInputReadAttempt] = [.bytes(2), .disconnected]
    do {
      _ = try BSDPendingInputDiscarder.discard(
        snapshot: .observed(byteCount: 5),
        read: { _ in partialAttempts.removeFirst() }
      )
      Issue.record("Partial disconnect discard incorrectly reported success")
    } catch let error as MachineLinkError {
      #expect(
        error == .discardFailed(
          discarded: 2,
          total: 5,
          reason: .disconnected
        )
      )
    }

    do {
      _ = try BSDPendingInputDiscarder.discard(
        snapshot: .failed(
          reason: .operatingSystem(code: EIO, operation: "ioctl FIONREAD")
        ),
        read: { _ in
          Issue.record("Snapshot failure must not attempt a read")
          return .bytes(1)
        }
      )
      Issue.record("Snapshot failure incorrectly reported success")
    } catch let error as MachineLinkError {
      #expect(
        error == .discardFailed(
          discarded: 0,
          total: nil,
          reason: .operatingSystem(code: EIO, operation: "ioctl FIONREAD")
        )
      )
    }

    var interruptionCount = 0
    do {
      _ = try BSDPendingInputDiscarder.discard(
        snapshot: .observed(byteCount: 1)
      ) { _ in
        interruptionCount += 1
        return .interrupted
      }
      Issue.record("Unbounded interrupted discard incorrectly reported success")
    } catch let error as MachineLinkError {
      #expect(
        error == .discardFailed(
          discarded: 0,
          total: 1,
          reason: .operatingSystem(
            code: EINTR,
            operation: "discard input read exceeded interruption retry budget"
          )
        )
      )
      #expect(
        interruptionCount == BSDPendingInputDiscarder.maximumInterruptedReadRetries + 1
      )
    }
  }

  @Test("simulated receipts expose exact transport, counts, bytes, and link-boundary time")
  func simulatedReceiptsAreExact() async throws {
    let clock = DeterministicRuntimeClock(startNanoseconds: 100)
    let command = Data([0x3F])
    let reply = Data("ok\r\n".utf8)
    let link = SimulatedGRBLLink(
      identifier: "receipt-fixture",
      exchanges: [
        SimulatedCommandExchange(
          expectedWrite: command,
          reads: [ScheduledMachineRead(delayNanoseconds: 17, outcome: .bytes(reply))]
        )
      ],
      clock: clock
    )
    link.preloadPendingInput(Data([0x01, 0x02, 0x03]))

    let open = try await link.open()
    #expect(open.appliedConfiguration == .simulated(identifier: "receipt-fixture"))
    let discard = try await link.discardPendingInput()
    #expect(discard.discardedByteCount == 3)
    let write = try await link.write(command)
    #expect(write.writtenByteCount == command.count)
    let read = try await link.read(maximumBytes: 64, timeoutNanoseconds: 100)
    #expect(read.bytes == reply)
    #expect(read.receivedAtMonotonicNanoseconds == 117)
    try await link.close()
  }

  @Test("forwarding wrappers preserve every underlying receipt unchanged")
  func forwardingPreservesReceipts() async throws {
    let clock = DeterministicRuntimeClock(startNanoseconds: 500)
    let command = Data([0x21])
    let reply = Data([0x06])
    let base = SimulatedGRBLLink(
      identifier: "forwarded-fixture",
      exchanges: [
        SimulatedCommandExchange(
          expectedWrite: command,
          reads: [ScheduledMachineRead(delayNanoseconds: 9, outcome: .bytes(reply))]
        )
      ],
      clock: clock
    )
    base.preloadPendingInput(Data([0xAA, 0xBB]))
    let link = BlockingMachineLink(
      base: base,
      blockedWrite: Data([0xFF]),
      gate: MachineWriteGate()
    )

    let open = try await link.open()
    #expect(open == MachineLinkOpenReceipt(
      appliedConfiguration: .simulated(identifier: "forwarded-fixture")
    ))
    let discard = try await link.discardPendingInput()
    #expect(discard == MachineLinkDiscardReceipt(discardedByteCount: 2))
    let write = try await link.write(command)
    #expect(write == MachineLinkWriteReceipt(writtenByteCount: 1))
    let read = try await link.read(maximumBytes: 1, timeoutNanoseconds: 20)
    #expect(
      read == MachineLinkReadReceipt(bytes: reply, receivedAtMonotonicNanoseconds: 509)
    )
    try await link.close()
  }

  @Test("partial transfer failures retain operation, progress, and reason")
  func partialTransferFailureIsExact() async throws {
    let command = Data([0x01, 0x02, 0x03, 0x04])
    let expected = MachineLinkError.writeFailed(
      bytesWritten: 2,
      totalBytes: command.count,
      reason: .operatingSystem(code: EIO, operation: "simulated write")
    )
    let link = SimulatedGRBLLink(
      exchanges: [
        SimulatedCommandExchange(expectedWrite: command, reads: [], writeError: expected)
      ]
    )
    _ = try await link.open()
    do {
      _ = try await link.write(command)
      Issue.record("Partial write unexpectedly succeeded")
    } catch let error as MachineLinkError {
      #expect(error == expected)
    }
    try await link.close()
  }

  @Test("zero-progress failures are derived by production write and simulated read boundaries")
  func zeroProgressFailuresAreDerived() async throws {
    let payload = Data([0x01, 0x02, 0x03])
    do {
      _ = try await NonblockingFileWriter.writeAll(
        payload,
        to: -1,
        timeoutNanoseconds: 1_000_000_000
      )
      Issue.record("Invalid production descriptor unexpectedly accepted a write")
    } catch let error as MachineLinkError {
      #expect(
        error == .writeFailed(
          bytesWritten: 0,
          totalBytes: payload.count,
          reason: .operatingSystem(code: EBADF, operation: "write")
        )
      )
    }

    let maximumBytes = 17
    let timedOutLink = SimulatedGRBLLink(
      exchanges: [],
      clock: DeterministicRuntimeClock(startNanoseconds: 1_000)
    )
    _ = try await timedOutLink.open()
    do {
      _ = try await timedOutLink.read(
        maximumBytes: maximumBytes,
        timeoutNanoseconds: 25
      )
      Issue.record("Empty simulated input unexpectedly produced bytes")
    } catch let error as MachineLinkError {
      #expect(
        error == .readFailed(
          partialReceipts: [],
          maximumBytes: maximumBytes,
          reason: .timedOut
        )
      )
    }
    try await timedOutLink.close()

    let command = Data([0x3F])
    let disconnectedLink = SimulatedGRBLLink(
      exchanges: [
        SimulatedCommandExchange(
          expectedWrite: command,
          reads: [ScheduledMachineRead(outcome: .disconnect)]
        )
      ]
    )
    _ = try await disconnectedLink.open()
    _ = try await disconnectedLink.write(command)
    do {
      _ = try await disconnectedLink.read(
        maximumBytes: maximumBytes,
        timeoutNanoseconds: 1_000_000
      )
      Issue.record("Simulated disconnect unexpectedly produced bytes")
    } catch let error as MachineLinkError {
      #expect(
        error == .readFailed(
          partialReceipts: [],
          maximumBytes: maximumBytes,
          reason: .disconnected
        )
      )
    }
    try await disconnectedLink.close()
  }

  @Test("simulated writes derive zero progress from an underlying transport failure")
  func simulatedZeroProgressWriteIsDerived() async throws {
    let command = Data([0x24, 0x58, 0x0A])
    let underlying = MachineLinkError.operatingSystem(
      code: EIO,
      operation: "simulated transport write"
    )
    let link = SimulatedGRBLLink(
      exchanges: [
        SimulatedCommandExchange(
          expectedWrite: command,
          reads: [],
          writeError: underlying
        )
      ]
    )
    _ = try await link.open()
    do {
      _ = try await link.write(command)
      Issue.record("Failed simulated transport unexpectedly accepted a write")
    } catch let error as MachineLinkError {
      #expect(
        error == .writeFailed(
          bytesWritten: 0,
          totalBytes: command.count,
          reason: .operatingSystem(code: EIO, operation: "simulated transport write")
        )
      )
    }
    try await link.close()
  }

  @Test("close failures are observable through the canonical link contract")
  func closeFailureIsObservable() async throws {
    let link = CloseFailureMachineLink()
    _ = try await link.open()
    do {
      try await link.close()
      Issue.record("Close unexpectedly succeeded")
    } catch let error as MachineLinkError {
      #expect(error == .operatingSystem(code: EIO, operation: "close"))
    }
  }

  @Test("controller retains close failure as a current blocker after invalidation")
  func controllerRetainsCloseFailure() async {
    let controller = MachineController(link: CloseFailureMachineLink())

    await controller.disconnect()

    let snapshot = await controller.snapshot()
    #expect(snapshot.connection == .disconnected)
    #expect(snapshot.position == nil)
    #expect(snapshot.penState == .unknown)
    #expect(snapshot.blockers.count == 1)
    guard let blocker = snapshot.blockers.first,
      case .transport(let detail) = blocker
    else {
      Issue.record("Expected a transport blocker for close failure")
      return
    }
    #expect(detail.contains("machine link close failed"))
    #expect(detail.contains("operation: \"close\""))
  }
}

private struct CloseFailureMachineLink: MachineLink {
  let descriptor = MachineLinkDescriptor(
    identifier: "close-failure",
    displayName: "Close Failure",
    bsdPath: nil,
    transport: .simulated
  )

  func open() async throws -> MachineLinkOpenReceipt {
    MachineLinkOpenReceipt(
      appliedConfiguration: .simulated(identifier: descriptor.identifier)
    )
  }

  func close() async throws {
    throw MachineLinkError.operatingSystem(code: EIO, operation: "close")
  }

  func discardPendingInput() async throws -> MachineLinkDiscardReceipt {
    throw MachineLinkError.notOpen
  }

  func write(_: Data) async throws -> MachineLinkWriteReceipt {
    throw MachineLinkError.notOpen
  }

  func read(
    maximumBytes _: Int,
    timeoutNanoseconds _: UInt64
  ) async throws -> MachineLinkReadReceipt {
    throw MachineLinkError.notOpen
  }
}
