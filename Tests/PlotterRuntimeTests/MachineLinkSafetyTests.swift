import Darwin
import Foundation
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
      try await NonblockingFileWriter.writeAll(
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
      try await task.value
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
