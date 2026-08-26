import CryptoKit
import Darwin
import Foundation
import Testing

@testable import PlotterEpisodeRuntime

@Suite("PlotterRecordingStoreTests")
struct PlotterRecordingStoreTests {
  @Test("controller invocations and completions retain exact ordered parameters across close and reopen")
  func controllerTranscriptOrderingAndReopen() async throws {
    let fixture = try RecordingFixture()
    defer { fixture.remove() }
    let store = try fixture.open()

    let open = invocation(1, .open(ControllerOpenParameters(
      endpoint: "/dev/cu.plotter",
      baudRate: 115_200,
      dataBits: 8,
      stopBits: 1,
      parity: .none,
      flowControl: .hardware
    )))
    let writeBytes = Data("G0 X1.250 Y-2.500\r\n".utf8)
    let write = invocation(2, .rawWrite(ControllerRawWriteParameters(bytes: writeBytes)))
    let read = invocation(
      3,
      .timedRead(ControllerTimedReadParameters(
        maximumByteCount: 64,
        timeoutNanoseconds: 250_000_000
      ))
    )

    _ = try await store.recordControllerInvocation(open, at: 10)
    _ = try await store.recordControllerCompletion(
      ControllerCompletion(invocationID: open.id, outcome: .succeeded(.open)),
      at: 11
    )
    _ = try await store.recordControllerInvocation(write, at: 12)
    _ = try await store.recordControllerCompletion(
      ControllerCompletion(
        invocationID: write.id,
        outcome: .failed(ControllerOperationFailure(
          kind: .inputOutput,
          systemCode: 5,
          diagnostic: "write interrupted",
          partialByteCount: 4
        ))
      ),
      at: 13
    )
    _ = try await store.recordControllerInvocation(read, at: 14)
    let chunks = [
      ControllerReadChunk(bytes: Data("<Idle".utf8), monotonicOffsetNanoseconds: 15),
      ControllerReadChunk(bytes: Data(">\r\n".utf8), monotonicOffsetNanoseconds: 16),
    ]
    _ = try await store.recordControllerCompletion(
      ControllerCompletion(
        invocationID: read.id,
        outcome: .succeeded(.timedRead(chunks: chunks, timedOut: false))
      ),
      at: 17
    )
    let discard = invocation(4, .discardInput(ControllerDiscardParameters()))
    _ = try await store.recordControllerInvocation(discard, at: 18)
    _ = try await store.recordControllerCompletion(
      ControllerCompletion(
        invocationID: discard.id,
        outcome: .succeeded(.discardInput(discardedByteCount: 7))
      ),
      at: 19
    )
    let close = invocation(5, .close)
    _ = try await store.recordControllerInvocation(close, at: 20)
    _ = try await store.recordControllerCompletion(
      ControllerCompletion(invocationID: close.id, outcome: .succeeded(.close)),
      at: 21
    )
    try await store.close(at: 22)

    let before = await store.snapshot()
    #expect(before.entries.map(\.sequence) == Array(0..<UInt64(before.entries.count)))
    #expect(before.isClosed)
    #expect(before.isComplete)

    let reopened = try fixture.open()
    let after = await reopened.snapshot()
    #expect(after == before)
    await #expect(throws: EpisodeRecordingError.closed) {
      try await reopened.recordControllerInvocation(
        invocation(4, .close),
        at: 23
      )
    }
  }

  @Test("operation mismatch, impossible partial counts, and time regression commit nothing")
  func invalidTranscriptIsNotAcknowledged() async throws {
    let fixture = try RecordingFixture()
    defer { fixture.remove() }
    let store = try fixture.open()
    let write = invocation(
      10,
      .rawWrite(ControllerRawWriteParameters(bytes: Data([0x3F])))
    )
    _ = try await store.recordControllerInvocation(write, at: 20)

    await #expect(throws: EpisodeRecordingError.controllerOperationMismatch(write.id)) {
      try await store.recordControllerCompletion(
        ControllerCompletion(invocationID: write.id, outcome: .succeeded(.close)),
        at: 21
      )
    }
    await #expect(throws: EpisodeRecordingError.invalidControllerPartialResult(write.id)) {
      try await store.recordControllerCompletion(
        ControllerCompletion(
          invocationID: write.id,
          outcome: .succeeded(.rawWrite(writtenByteCount: 2))
        ),
        at: 21
      )
    }
    await #expect(throws: EpisodeRecordingError.monotonicOffsetRegression(
      previous: 20,
      actual: 19
    )) {
      try await store.recordCameraLifecycle(.failed(CameraLifecycleFailure(
        operation: .start(stream(1)),
        kind: .unknown
      )), at: 19)
    }

    let snapshot = await store.snapshot()
    #expect(snapshot.entries.count == 1)
    #expect(snapshot.completenessIssues == [.controllerCompletionMissing(write.id)])
  }

  @Test("duplicate and unmatched controller records are refused without commit")
  func duplicateAndUnmatchedControllerRecords() async throws {
    let fixture = try RecordingFixture()
    defer { fixture.remove() }
    let store = try fixture.open()
    let item = invocation(11, .close)
    let other = invocation(12, .close)
    _ = try await store.recordControllerInvocation(item, at: 1)

    await #expect(throws: EpisodeRecordingError.duplicateControllerInvocation(item.id)) {
      try await store.recordControllerInvocation(item, at: 2)
    }
    await #expect(throws: EpisodeRecordingError.controllerCompletionWithoutInvocation(other.id)) {
      try await store.recordControllerCompletion(
        ControllerCompletion(invocationID: other.id, outcome: .succeeded(.close)),
        at: 2
      )
    }
    let completion = ControllerCompletion(
      invocationID: item.id,
      outcome: .succeeded(.close)
    )
    _ = try await store.recordControllerCompletion(completion, at: 2)
    await #expect(throws: EpisodeRecordingError.duplicateControllerCompletion(item.id)) {
      try await store.recordControllerCompletion(completion, at: 3)
    }

    let snapshot = await store.snapshot()
    #expect(snapshot.entries.count == 2)
    #expect(snapshot.isComplete)
  }

  @Test("camera lifecycle refuses incoherent transitions and failed stop preserves active truth")
  func cameraLifecycleValidationAndFailureAttribution() async throws {
    let fixture = try RecordingFixture()
    defer { fixture.remove() }
    let store = try fixture.open()
    let original = stream(20)
    let requested = reconfiguredStream(original, value: 21)
    let incoherent = reconfiguredStream(original, value: 22)

    await #expect(throws: EpisodeRecordingError.invalidCameraLifecycleTransition(
      .started(original)
    )) {
      try await store.recordCameraLifecycle(.started(original), at: 1)
    }
    _ = try await store.recordCameraLifecycle(.startRequested(original), at: 1)
    _ = try await store.recordCameraLifecycle(.started(original), at: 2)
    _ = try await store.recordCameraLifecycle(
      .reconfigurationRequested(previous: original, requested: requested),
      at: 3
    )
    await #expect(throws: EpisodeRecordingError.invalidCameraLifecycleTransition(
      .reconfigured(previous: original, current: incoherent)
    )) {
      try await store.recordCameraLifecycle(
        .reconfigured(previous: original, current: incoherent),
        at: 4
      )
    }
    _ = try await store.recordCameraLifecycle(.failed(CameraLifecycleFailure(
      operation: .reconfigure(previous: original, requested: requested),
      kind: .configurationRejected
    )), at: 4)
    _ = try await store.recordCameraLifecycle(.stopRequested(original), at: 5)
    _ = try await store.recordCameraLifecycle(.failed(CameraLifecycleFailure(
      operation: .stop(original),
      kind: .inputOutput
    )), at: 6)
    await #expect(throws: EpisodeRecordingError.invalidCameraLifecycleTransition(
      .stopped(original)
    )) {
      try await store.recordCameraLifecycle(.stopped(original), at: 7)
    }
    try await store.close(at: 7)

    let snapshot = await store.snapshot()
    #expect(snapshot.entries.count == 6)
    #expect(snapshot.completenessIssues == [.cameraStopIncomplete(original)])
    let reopened = try fixture.open()
    #expect(await reopened.snapshot() == snapshot)
  }

  @Test("camera lifecycle and exact frame identities bind deduplicated content-addressed bytes")
  func contentAddressedFramesAndLifecycle() async throws {
    let fixture = try RecordingFixture()
    defer { fixture.remove() }
    let store = try fixture.open()
    let stream = stream(2)
    let bytes = Data([0, 1, 2, 3, 4, 5, 6, 7])

    _ = try await store.recordCameraLifecycle(.startRequested(stream), at: 1)
    _ = try await store.recordCameraLifecycle(.started(stream), at: 2)
    let first = try await store.recordCameraFrame(
      frame(1, stream: stream),
      bytes: bytes,
      at: 3
    )
    await #expect(throws: EpisodeRecordingError.duplicateCameraFrameIdentity(
      CameraFrameIdentity(rawValue: "frame-1")
    )) {
      try await store.recordCameraFrame(
        frame(1, stream: stream),
        bytes: bytes,
        at: 4
      )
    }
    let second = try await store.recordCameraFrame(
      frame(2, stream: stream),
      bytes: bytes,
      at: 4
    )
    _ = try await store.recordCameraLifecycle(.stopRequested(stream), at: 5)
    _ = try await store.recordCameraLifecycle(.stopped(stream), at: 6)
    try await store.close(at: 7)

    let firstReference = try #require(first.frameReference)
    let secondReference = try #require(second.frameReference)
    #expect(firstReference == secondReference)
    #expect(firstReference.contentSHA256.count == 64)
    #expect(firstReference.byteCount == bytes.count)
    #expect(try await store.frameBytes(for: firstReference) == bytes)
    #expect(await store.snapshot().isComplete)

    let artifactURL = fixture.directoryURL.appendingPathComponent(firstReference.relativePath)
    #expect(FileManager.default.fileExists(atPath: artifactURL.path))
    #expect(try FileManager.default.contentsOfDirectory(
      at: artifactURL.deletingLastPathComponent(),
      includingPropertiesForKeys: nil
    ).count == 1)
  }

  @Test("oversized raw frame bytes are refused before artifact or record publication")
  func oversizedFrameIsRefused() async throws {
    let fixture = try RecordingFixture()
    defer { fixture.remove() }
    let store = try fixture.open()
    let descriptor = frame(9, stream: stream(9))

    await #expect(throws: EpisodeRecordingError.invalidCameraFrame(descriptor.frameID)) {
      try await store.recordCameraFrame(
        descriptor,
        bytes: Data(repeating: 1, count: 9),
        at: 1
      )
    }
    #expect(await store.snapshot().entries.isEmpty)
    #expect(!FileManager.default.fileExists(
      atPath: fixture.directoryURL.appendingPathComponent("frames").path
    ))
  }

  @Test("a preexisting frames symlink is refused before the store opens")
  func framesDirectorySymlinkIsRefused() throws {
    let fixture = try RecordingFixture()
    defer { fixture.remove() }
    let external = FileManager.default.temporaryDirectory.appendingPathComponent(
      "AdaptivePlotter-external-frames-\(UUID().uuidString)",
      isDirectory: true
    )
    try FileManager.default.createDirectory(at: external, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: external) }
    try FileManager.default.createSymbolicLink(
      at: fixture.directoryURL.appendingPathComponent("frames"),
      withDestinationURL: external
    )

    #expect(throws: EpisodeRecordingError.framesDirectoryUnsafe(.symbolicLink)) {
      _ = try fixture.open()
    }
  }

  @Test("symlinked, externally hard-linked, and unreadable frame artifacts remain typed")
  func unsafeAndUnreadableFrameArtifacts() async throws {
    let bytes = Data([0, 1, 2, 3, 4, 5, 6, 7])

    let symlinkFixture = try RecordingFixture()
    defer { symlinkFixture.remove() }
    let symlinkStore = try symlinkFixture.open()
    let symlinkStream = stream(30)
    try await activate(symlinkStream, in: symlinkStore)
    let symlinkEntry = try await symlinkStore.recordCameraFrame(
      frame(30, stream: symlinkStream),
      bytes: bytes,
      at: 3
    )
    try await deactivate(symlinkStream, in: symlinkStore, startingAt: 4)
    let symlinkReference = try #require(symlinkEntry.frameReference)
    let symlinkArtifact = symlinkFixture.directoryURL
      .appendingPathComponent(symlinkReference.relativePath)
    let externalFile = FileManager.default.temporaryDirectory.appendingPathComponent(
      "AdaptivePlotter-external-frame-\(UUID().uuidString)"
    )
    try bytes.write(to: externalFile)
    defer { try? FileManager.default.removeItem(at: externalFile) }
    try FileManager.default.removeItem(at: symlinkArtifact)
    try FileManager.default.createSymbolicLink(
      at: symlinkArtifact,
      withDestinationURL: externalFile
    )
    #expect(await symlinkStore.snapshot().completenessIssues == [
      .frameArtifactUnsafe(reference: symlinkReference, reason: .symbolicLink)
    ])
    await #expect(throws: EpisodeRecordingError.frameArtifactUnsafe(
      reference: symlinkReference,
      reason: .symbolicLink
    )) {
      try await symlinkStore.frameBytes(for: symlinkReference)
    }

    let hardlinkFixture = try RecordingFixture()
    defer { hardlinkFixture.remove() }
    let hardlinkStore = try hardlinkFixture.open()
    let hardlinkStream = stream(31)
    try await activate(hardlinkStream, in: hardlinkStore)
    let hardlinkEntry = try await hardlinkStore.recordCameraFrame(
      frame(31, stream: hardlinkStream),
      bytes: bytes,
      at: 3
    )
    try await deactivate(hardlinkStream, in: hardlinkStore, startingAt: 4)
    let hardlinkReference = try #require(hardlinkEntry.frameReference)
    let hardlinkArtifact = hardlinkFixture.directoryURL
      .appendingPathComponent(hardlinkReference.relativePath)
    let externalLink = FileManager.default.temporaryDirectory.appendingPathComponent(
      "AdaptivePlotter-external-link-\(UUID().uuidString)"
    )
    try FileManager.default.linkItem(at: hardlinkArtifact, to: externalLink)
    defer { try? FileManager.default.removeItem(at: externalLink) }
    #expect(await hardlinkStore.snapshot().completenessIssues == [
      .frameArtifactUnsafe(reference: hardlinkReference, reason: .externalHardLinks)
    ])
    await #expect(throws: EpisodeRecordingError.frameArtifactUnsafe(
      reference: hardlinkReference,
      reason: .externalHardLinks
    )) {
      try await hardlinkStore.frameBytes(for: hardlinkReference)
    }

    let unreadableFixture = try RecordingFixture()
    defer { unreadableFixture.remove() }
    let unreadableStore = try unreadableFixture.open()
    let unreadableStream = stream(32)
    try await activate(unreadableStream, in: unreadableStore)
    let unreadableEntry = try await unreadableStore.recordCameraFrame(
      frame(32, stream: unreadableStream),
      bytes: bytes,
      at: 3
    )
    try await deactivate(unreadableStream, in: unreadableStore, startingAt: 4)
    let unreadableReference = try #require(unreadableEntry.frameReference)
    let unreadableArtifact = unreadableFixture.directoryURL
      .appendingPathComponent(unreadableReference.relativePath)
    try FileManager.default.removeItem(at: unreadableArtifact)
    try FileManager.default.createDirectory(
      at: unreadableArtifact,
      withIntermediateDirectories: false
    )
    #expect(await unreadableStore.snapshot().completenessIssues == [
      .frameArtifactUnreadable(unreadableReference)
    ])
    await #expect(throws: EpisodeRecordingError.frameArtifactUnreadable(unreadableReference)) {
      try await unreadableStore.frameBytes(for: unreadableReference)
    }
  }

  @Test("missing exact-frame bytes remain a typed incomplete reference after reopen")
  func missingFrameBytes() async throws {
    let fixture = try RecordingFixture()
    defer { fixture.remove() }
    let store = try fixture.open()
    let activeStream = stream(3)
    try await activate(activeStream, in: store)
    let entry = try await store.recordCameraFrame(
      frame(10, stream: activeStream),
      bytes: Data([1, 2, 3, 4, 5, 6, 7, 8]),
      at: 3
    )
    try await deactivate(activeStream, in: store, startingAt: 4)
    try await store.close(at: 6)
    let reference = try #require(entry.frameReference)
    try FileManager.default.removeItem(
      at: fixture.directoryURL.appendingPathComponent(reference.relativePath)
    )

    let reopened = try fixture.open()
    #expect(await reopened.snapshot().completenessIssues == [.frameBytesMissing(reference)])
    await #expect(throws: EpisodeRecordingError.frameBytesMissing(reference)) {
      try await reopened.frameBytes(for: reference)
    }
  }

  @Test("truncated and hash-mismatched exact-frame bytes are distinguished and never repaired")
  func corruptFrameBytes() async throws {
    let truncatedFixture = try RecordingFixture()
    defer { truncatedFixture.remove() }
    let truncatedStore = try truncatedFixture.open()
    let truncatedStream = stream(4)
    try await activate(truncatedStream, in: truncatedStore)
    let original = Data([10, 11, 12, 13, 14, 15, 16, 17])
    let truncatedEntry = try await truncatedStore.recordCameraFrame(
      frame(20, stream: truncatedStream),
      bytes: original,
      at: 3
    )
    try await deactivate(truncatedStream, in: truncatedStore, startingAt: 4)
    try await truncatedStore.close(at: 6)
    let truncatedReference = try #require(truncatedEntry.frameReference)
    let truncatedURL = truncatedFixture.directoryURL
      .appendingPathComponent(truncatedReference.relativePath)
    try FileManager.default.removeItem(at: truncatedURL)
    try Data([10, 11]).write(
      to: truncatedURL
    )
    #expect(Darwin.chmod(truncatedURL.path, mode_t(S_IRUSR)) == 0)
    let reopenedTruncated = try truncatedFixture.open()
    #expect(await reopenedTruncated.snapshot().completenessIssues == [
      .frameBytesTruncated(reference: truncatedReference, actualByteCount: 2)
    ])

    let corruptFixture = try RecordingFixture()
    defer { corruptFixture.remove() }
    let corruptStore = try corruptFixture.open()
    let corruptStream = stream(5)
    try await activate(corruptStream, in: corruptStore)
    let corruptEntry = try await corruptStore.recordCameraFrame(
      frame(21, stream: corruptStream),
      bytes: original,
      at: 3
    )
    try await deactivate(corruptStream, in: corruptStore, startingAt: 4)
    try await corruptStore.close(at: 6)
    let corruptReference = try #require(corruptEntry.frameReference)
    let corruptBytes = Data([17, 16, 15, 14, 13, 12, 11, 10])
    let corruptURL = corruptFixture.directoryURL
      .appendingPathComponent(corruptReference.relativePath)
    try FileManager.default.removeItem(at: corruptURL)
    try corruptBytes.write(
      to: corruptURL
    )
    #expect(Darwin.chmod(corruptURL.path, mode_t(S_IRUSR)) == 0)
    let reopenedCorrupt = try corruptFixture.open()
    let issues = await reopenedCorrupt.snapshot().completenessIssues
    let issue = try #require(issues.first)
    guard case let .frameHashMismatch(reference, actualSHA256) = issue else {
      Issue.record("Expected a typed frame hash mismatch")
      return
    }
    #expect(reference == corruptReference)
    #expect(actualSHA256.count == 64)
    #expect(actualSHA256 != corruptReference.contentSHA256)

    let longerFixture = try RecordingFixture()
    defer { longerFixture.remove() }
    let longerStore = try longerFixture.open()
    let longerStream = stream(6)
    try await activate(longerStream, in: longerStore)
    let longerEntry = try await longerStore.recordCameraFrame(
      frame(22, stream: longerStream),
      bytes: original,
      at: 3
    )
    try await deactivate(longerStream, in: longerStore, startingAt: 4)
    try await longerStore.close(at: 6)
    let longerReference = try #require(longerEntry.frameReference)
    let longerURL = longerFixture.directoryURL
      .appendingPathComponent(longerReference.relativePath)
    try FileManager.default.removeItem(at: longerURL)
    try Data([10, 11, 12, 13, 14, 15, 16, 17, 18]).write(to: longerURL)
    #expect(Darwin.chmod(longerURL.path, mode_t(S_IRUSR)) == 0)
    let reopenedLonger = try longerFixture.open()
    #expect(await reopenedLonger.snapshot().completenessIssues == [
      .frameByteCountMismatch(reference: longerReference, actualByteCount: 9)
    ])
  }

  @Test("frame admission requires the exact active camera stream configuration")
  func frameAdmissionRequiresActiveMatchingLifecycle() async throws {
    let fixture = try RecordingFixture()
    defer { fixture.remove() }
    let store = try fixture.open()
    let bytes = Data([0, 1, 2, 3, 4, 5, 6, 7])
    let active = stream(80)
    let mismatched = reconfiguredStream(active, value: 81)

    await #expect(throws: EpisodeRecordingError.cameraFrameOutsideActiveLifecycle(
      frameID: frame(80, stream: active).frameID,
      stream: active
    )) {
      try await store.recordCameraFrame(frame(80, stream: active), bytes: bytes, at: 1)
    }
    try await activate(active, in: store)
    await #expect(throws: EpisodeRecordingError.cameraFrameOutsideActiveLifecycle(
      frameID: frame(81, stream: mismatched).frameID,
      stream: mismatched
    )) {
      try await store.recordCameraFrame(frame(81, stream: mismatched), bytes: bytes, at: 3)
    }
    try await deactivate(active, in: store, startingAt: 3)
    await #expect(throws: EpisodeRecordingError.cameraFrameOutsideActiveLifecycle(
      frameID: frame(82, stream: active).frameID,
      stream: active
    )) {
      try await store.recordCameraFrame(frame(82, stream: active), bytes: bytes, at: 5)
    }

    let failed = stream(82)
    _ = try await store.recordCameraLifecycle(.startRequested(failed), at: 5)
    _ = try await store.recordCameraLifecycle(.failed(CameraLifecycleFailure(
      operation: .start(failed),
      kind: .sourceUnavailable
    )), at: 6)
    await #expect(throws: EpisodeRecordingError.cameraFrameOutsideActiveLifecycle(
      frameID: frame(83, stream: failed).frameID,
      stream: failed
    )) {
      try await store.recordCameraFrame(frame(83, stream: failed), bytes: bytes, at: 7)
    }

    #expect(await store.snapshot().entries.count == 6)
    #expect(!FileManager.default.fileExists(
      atPath: fixture.directoryURL.appendingPathComponent("frames").path
    ))
  }

  @Test("the admitted root descriptor survives path replacement without splitting writes")
  func rootDescriptorSurvivesPathReplacement() async throws {
    let fixture = try RecordingFixture()
    let movedURL = fixture.directoryURL.deletingLastPathComponent().appendingPathComponent(
      "AdaptivePlotter-moved-recording-\(UUID().uuidString)",
      isDirectory: true
    )
    defer {
      try? FileManager.default.removeItem(at: fixture.directoryURL)
      try? FileManager.default.removeItem(at: movedURL)
    }
    let store = try fixture.open()
    try FileManager.default.moveItem(at: fixture.directoryURL, to: movedURL)
    try FileManager.default.createDirectory(
      at: fixture.directoryURL,
      withIntermediateDirectories: false
    )

    let active = stream(90)
    try await activate(active, in: store)
    let entry = try await store.recordCameraFrame(
      frame(90, stream: active),
      bytes: Data([0, 1, 2, 3, 4, 5, 6, 7]),
      at: 3
    )
    try await deactivate(active, in: store, startingAt: 4)
    try await store.close(at: 6)

    #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.directoryURL.path).isEmpty)
    let reference = try #require(entry.frameReference)
    #expect(FileManager.default.fileExists(
      atPath: movedURL.appendingPathComponent(reference.relativePath).path
    ))
    let reopened = try EpisodeRecordingStore.open(
      directoryURL: movedURL,
      recordingID: fixture.recordingID,
      schemaRevision: fixture.schemaRevision,
      frameRetentionPolicy: fixture.frameRetentionPolicy
    )
    let anchoredSnapshot = await store.snapshot()
    #expect(await reopened.snapshot() == anchoredSnapshot)
  }

  @Test("concurrent open waits for an in-progress marker and manifest transaction")
  func concurrentInitializationOpenIsSerialized() async throws {
    let fixture = try RecordingFixture()
    defer { fixture.remove() }
    let markerSignal = FileManager.default.temporaryDirectory.appendingPathComponent(
      "AdaptivePlotter-initialization-marker-signal-\(UUID().uuidString)"
    )
    let secondOpenSignal = FileManager.default.temporaryDirectory.appendingPathComponent(
      "AdaptivePlotter-second-open-signal-\(UUID().uuidString)"
    )
    let releaseSignal = FileManager.default.temporaryDirectory.appendingPathComponent(
      "AdaptivePlotter-initialization-release-\(UUID().uuidString)"
    )
    defer {
      try? FileManager.default.removeItem(at: markerSignal)
      try? FileManager.default.removeItem(at: secondOpenSignal)
      try? FileManager.default.removeItem(at: releaseSignal)
    }

    let firstOpen = Task {
      try fixture.open(fault: .initializationPauseAfterMarker(
        signalURL: markerSignal,
        releaseURL: releaseSignal
      ))
    }
    try await waitForFile(markerSignal)
    #expect(FileManager.default.fileExists(
      atPath: fixture.directoryURL.appendingPathComponent(
        ".episode-recording.initialized"
      ).path
    ))
    #expect(!FileManager.default.fileExists(
      atPath: fixture.directoryURL.appendingPathComponent("episode-recording.json").path
    ))

    let secondOpen = Task {
      try fixture.open(fault: .signalBeforeCommitLock(secondOpenSignal))
    }
    try await waitForFile(secondOpenSignal)
    try Data().write(to: releaseSignal)

    let first = try await firstOpen.value
    let second = try await secondOpen.value
    let firstSnapshot = await first.snapshot()
    #expect(firstSnapshot.entries.isEmpty)
    #expect(await second.snapshot() == firstSnapshot)
    let reopened = try fixture.open()
    #expect(await reopened.snapshot() == firstSnapshot)
  }

  @Test("deleting a durable manifest after initialization is typed recording loss")
  func deletedManifestIsNotTreatedAsFresh() throws {
    let fixture = try RecordingFixture()
    defer { fixture.remove() }
    _ = try fixture.open()
    try FileManager.default.removeItem(
      at: fixture.directoryURL.appendingPathComponent("episode-recording.json")
    )

    #expect(throws: EpisodeRecordingError.manifestMissingAfterInitialization) {
      _ = try fixture.open()
    }
  }

  @Test("optional episode provenance survives deterministic durable reopen")
  func typedOptionalProvenance() async throws {
    let fixture = try RecordingFixture()
    defer { fixture.remove() }
    let store = try fixture.open()
    let provenance = EpisodeRecordingProvenance(
      episodeID: .init(rawValue: UUID(uuidString: "00000000-0000-0000-0000-000000000101")!),
      intentRequestID: .init(
        rawValue: UUID(uuidString: "00000000-0000-0000-0000-000000000102")!
      ),
      effectID: .init(rawValue: UUID(uuidString: "00000000-0000-0000-0000-000000000103")!),
      correlationID: .init(
        rawValue: UUID(uuidString: "00000000-0000-0000-0000-000000000104")!
      ),
      environment: .simulated
    )
    let item = invocation(901, .close)
    _ = try await store.recordControllerInvocation(item, at: 1, provenance: provenance)
    _ = try await store.recordControllerCompletion(
      ControllerCompletion(invocationID: item.id, outcome: .succeeded(.close)),
      at: 2
    )

    let before = await store.snapshot()
    #expect(before.entries[0].provenance == provenance)
    #expect(before.entries[1].provenance == .unattributed)
    let reopened = try fixture.open()
    #expect(await reopened.snapshot() == before)
  }

  @Test("typed RunLedger diagnostic references retain complete and incomplete ranges")
  func typedRunLedgerDiagnosticReferences() async throws {
    let fixture = try RecordingFixture()
    defer { fixture.remove() }
    let store = try fixture.open()
    let complete = RunLedgerDiagnosticReference(
      runID: .init(UUID(uuidString: "00000000-0000-0000-0000-000000000201")!),
      recordedRange: .init(first: 0, last: 4),
      integrity: .verified,
      completeness: .complete
    )
    let incomplete = RunLedgerDiagnosticReference(
      runID: .init(UUID(uuidString: "00000000-0000-0000-0000-000000000202")!),
      recordedRange: .init(first: 0, last: 9),
      integrity: .notVerified,
      completeness: .incomplete(missingRanges: [.init(first: 5, last: 7)])
    )
    _ = try await store.recordRunLedgerDiagnosticReference(complete, at: 1)
    _ = try await store.recordRunLedgerDiagnosticReference(incomplete, at: 2)

    #expect(await store.snapshot().completenessIssues == [
      .runLedgerIntegrityIncomplete(incomplete.runID),
      .runLedgerRangeIncomplete(
        runID: incomplete.runID,
        missingRanges: [.init(first: 5, last: 7)]
      ),
    ])
    let reopened = try fixture.open()
    #expect(await reopened.snapshot().entries.map(\.record) == [
      .runLedgerDiagnostic(complete),
      .runLedgerDiagnostic(incomplete),
    ])
  }

  @Test("durable frame retention limits refuse unique bytes and permit deduplication")
  func boundedFrameRetentionAndDeduplication() async throws {
    let policy = EpisodeFrameRetentionPolicy(
      maximumUniqueFrameCount: 1,
      maximumTotalUniqueFrameBytes: 8
    )
    let fixture = try RecordingFixture(frameRetentionPolicy: policy)
    defer { fixture.remove() }
    let store = try fixture.open()
    let active = stream(95)
    try await activate(active, in: store)
    let first = try await store.recordCameraFrame(
      frame(95, stream: active),
      bytes: Data([0, 1, 2, 3, 4, 5, 6, 7]),
      at: 3
    )
    let duplicate = try await store.recordCameraFrame(
      frame(96, stream: active),
      bytes: Data([0, 1, 2, 3, 4, 5, 6, 7]),
      at: 4
    )
    #expect(first.frameReference == duplicate.frameReference)
    await #expect(throws: EpisodeRecordingError.frameRetentionLimitExceeded(
      policy: policy,
      currentUniqueFrameCount: 1,
      currentUniqueFrameBytes: 8,
      proposedUniqueFrameBytes: 8
    )) {
      try await store.recordCameraFrame(
        frame(97, stream: active),
        bytes: Data([7, 6, 5, 4, 3, 2, 1, 0]),
        at: 5
      )
    }
    #expect(try FileManager.default.contentsOfDirectory(
      at: fixture.directoryURL.appendingPathComponent("frames"),
      includingPropertiesForKeys: nil
    ).count == 1)
    let reopened = try fixture.open()
    #expect(await reopened.snapshot().frameRetentionPolicy == policy)

    let changed = EpisodeFrameRetentionPolicy(
      maximumUniqueFrameCount: 2,
      maximumTotalUniqueFrameBytes: 16
    )
    #expect(throws: EpisodeRecordingError.frameRetentionPolicyMismatch(
      expected: changed,
      actual: policy
    )) {
      _ = try EpisodeRecordingStore.open(
        directoryURL: fixture.directoryURL,
        recordingID: fixture.recordingID,
        schemaRevision: fixture.schemaRevision,
        frameRetentionPolicy: changed
      )
    }

    let invalid = EpisodeFrameRetentionPolicy(
      maximumUniqueFrameCount: 0,
      maximumTotalUniqueFrameBytes: 8
    )
    let invalidFixture = try RecordingFixture(frameRetentionPolicy: invalid)
    defer { invalidFixture.remove() }
    #expect(throws: EpisodeRecordingError.invalidFrameRetentionPolicy(invalid)) {
      _ = try invalidFixture.open()
    }
  }

  @Test("duplicate frame identity refusal installs no different durable bytes")
  func duplicateFrameIdentityInstallsNothing() async throws {
    let policy = EpisodeFrameRetentionPolicy(
      maximumUniqueFrameCount: 1,
      maximumTotalUniqueFrameBytes: 8
    )
    let fixture = try RecordingFixture(frameRetentionPolicy: policy)
    defer { fixture.remove() }
    let store = try fixture.open()
    let active = stream(110)
    let firstBytes = Data([0, 1, 2, 3, 4, 5, 6, 7])
    let refusedBytes = Data([7, 6, 5, 4, 3, 2, 1, 0])
    try await activate(active, in: store)
    let descriptor = frame(110, stream: active)
    _ = try await store.recordCameraFrame(descriptor, bytes: firstBytes, at: 3)

    await #expect(throws: EpisodeRecordingError.duplicateCameraFrameIdentity(
      descriptor.frameID
    )) {
      try await store.recordCameraFrame(descriptor, bytes: refusedBytes, at: 4)
    }
    try await deactivate(active, in: store, startingAt: 4)
    let artifacts = try frameArtifactURLs(in: fixture)
    #expect(artifacts.count == 1)
    #expect(try Data(contentsOf: artifacts[0]) == firstBytes)
    let reopened = try fixture.open()
    #expect(await reopened.snapshot().isComplete)
  }

  @Test("regressed frame time refusal installs no different durable bytes")
  func regressedFrameTimeInstallsNothing() async throws {
    let policy = EpisodeFrameRetentionPolicy(
      maximumUniqueFrameCount: 1,
      maximumTotalUniqueFrameBytes: 8
    )
    let fixture = try RecordingFixture(frameRetentionPolicy: policy)
    defer { fixture.remove() }
    let store = try fixture.open()
    let active = stream(111)
    let firstBytes = Data([1, 1, 1, 1, 1, 1, 1, 1])
    let refusedBytes = Data([2, 2, 2, 2, 2, 2, 2, 2])
    try await activate(active, in: store, startingAt: 10)
    _ = try await store.recordCameraFrame(frame(111, stream: active), bytes: firstBytes, at: 12)

    await #expect(throws: EpisodeRecordingError.monotonicOffsetRegression(
      previous: 12,
      actual: 11
    )) {
      try await store.recordCameraFrame(
        frame(112, stream: active),
        bytes: refusedBytes,
        at: 11
      )
    }
    try await deactivate(active, in: store, startingAt: 13)
    let artifacts = try frameArtifactURLs(in: fixture)
    #expect(artifacts.count == 1)
    #expect(try Data(contentsOf: artifacts[0]) == firstBytes)
    let reopened = try fixture.open()
    #expect(await reopened.snapshot().isComplete)
  }

  @Test("independent frame-store CAS loser installs no artifact")
  func independentFrameStoreConflictInstallsNothing() async throws {
    let policy = EpisodeFrameRetentionPolicy(
      maximumUniqueFrameCount: 2,
      maximumTotalUniqueFrameBytes: 16
    )
    let fixture = try RecordingFixture(frameRetentionPolicy: policy)
    defer { fixture.remove() }
    let initial = try fixture.open()
    let active = stream(112)
    try await activate(active, in: initial)
    let first = try fixture.open()
    let second = try fixture.open()

    async let firstAttempt = frameCommitAttempt(
      frame(113, stream: active),
      bytes: Data([3, 3, 3, 3, 3, 3, 3, 3]),
      to: first
    )
    async let secondAttempt = frameCommitAttempt(
      frame(114, stream: active),
      bytes: Data([4, 4, 4, 4, 4, 4, 4, 4]),
      to: second
    )
    let attempts = await [firstAttempt, secondAttempt]
    #expect(attempts.filter(\.isCommitted).count == 1)
    #expect(attempts.filter(\.isConflict).count == 1)
    #expect(try frameArtifactURLs(in: fixture).count == 1)

    let reopened = try fixture.open()
    let frameRecords = await reopened.snapshot().entries.filter { entry in
      if case .camera(.frameReference) = entry.record { return true }
      return false
    }
    #expect(frameRecords.count == 1)
    let reopenedIssues = await reopened.snapshot().completenessIssues
    #expect(!reopenedIssues.contains { issue in
      if case .unreferencedFrameArtifact = issue { return true }
      return false
    })
  }

  @Test("definite manifest failure leaves one charged visible orphan and cannot exceed quota")
  func failedManifestFrameOrphanConsumesRetention() async throws {
    let policy = EpisodeFrameRetentionPolicy(
      maximumUniqueFrameCount: 1,
      maximumTotalUniqueFrameBytes: 8
    )
    let fixture = try RecordingFixture(frameRetentionPolicy: policy)
    defer { fixture.remove() }
    let initial = try fixture.open()
    let active = stream(115)
    try await activate(active, in: initial)
    let firstBytes = Data([5, 5, 5, 5, 5, 5, 5, 5])
    let failed = try fixture.open(fault: .manifestPreRenameFailureOnce)

    await #expect(throws: EpisodeRecordingError.atomicReplacementFailed(code: EIO)) {
      try await failed.recordCameraFrame(
        frame(115, stream: active),
        bytes: firstBytes,
        at: 3
      )
    }
    let artifactsAfterFailure = try frameArtifactURLs(in: fixture)
    #expect(artifactsAfterFailure.count == 1)
    #expect(try Data(contentsOf: artifactsAfterFailure[0]) == firstBytes)
    let failedSnapshot = await failed.snapshot()
    let orphans: [ContentAddressedFrameReference] = failedSnapshot.completenessIssues.compactMap {
      issue in
      guard case let .unreferencedFrameArtifact(reference) = issue else { return nil }
      return reference
    }
    let orphan = try #require(orphans.first)
    #expect(orphan.byteCount == 8)

    for (value, byte) in [(116, UInt8(6)), (117, UInt8(7))] {
      let reopened = try fixture.open(fault: .manifestPreRenameFailureOnce)
      await #expect(throws: EpisodeRecordingError.frameRetentionLimitExceeded(
        policy: policy,
        currentUniqueFrameCount: 1,
        currentUniqueFrameBytes: 8,
        proposedUniqueFrameBytes: 8
      )) {
        try await reopened.recordCameraFrame(
          frame(UInt64(value), stream: active),
          bytes: Data(repeating: byte, count: 8),
          at: 3
        )
      }
      #expect(try frameArtifactURLs(in: fixture).count == 1)
      #expect(await reopened.snapshot().completenessIssues.contains(
        .unreferencedFrameArtifact(orphan)
      ))
    }
  }

  @Test("checked retention accounting refuses Int max plus one")
  func checkedRetentionArithmetic() {
    #expect(EpisodeFrameRetentionAccounting.checkedAdding(Int.max, 1) == nil)
    #expect(EpisodeFrameRetentionAccounting.checkedIncrement(Int.max) == nil)
    #expect(EpisodeFrameRetentionAccounting.checkedSum([Int.max, 1]) == nil)
    #expect(EpisodeFrameRetentionAccounting.checkedSum([Int.max]) == Int.max)
  }

  @Test("checksum-valid manifest retention overflow is typed corruption")
  func checksumValidManifestRetentionOverflow() throws {
    let policy = EpisodeFrameRetentionPolicy(
      maximumUniqueFrameCount: Int.max,
      maximumTotalUniqueFrameBytes: Int.max
    )
    let fixture = try RecordingFixture(frameRetentionPolicy: policy)
    defer { fixture.remove() }
    _ = try fixture.open()
    let active = stream(120)
    let descriptorA = encodedFrame(120, stream: active)
    let descriptorB = encodedFrame(121, stream: active)
    let digestA = String(repeating: "a", count: 64)
    let digestB = String(repeating: "b", count: 64)
    let document = EpisodeRecordingDocument(
      formatVersion: EpisodeRecordingStore.currentFormatVersion,
      recordingID: fixture.recordingID,
      schemaRevision: fixture.schemaRevision,
      frameRetentionPolicy: policy,
      entries: [
        EpisodeRecordingEntry(
          sequence: 0,
          monotonicOffsetNanoseconds: 1,
          record: .camera(.lifecycle(.startRequested(active)))
        ),
        EpisodeRecordingEntry(
          sequence: 1,
          monotonicOffsetNanoseconds: 2,
          record: .camera(.lifecycle(.started(active)))
        ),
        EpisodeRecordingEntry(
          sequence: 2,
          monotonicOffsetNanoseconds: 3,
          record: .camera(.frameReference(CameraFrameRecord(
            descriptor: descriptorA,
            artifact: ContentAddressedFrameReference(
              contentSHA256: digestA,
              byteCount: Int.max,
              relativePath: "frames/\(digestA).frame"
            )
          )))
        ),
        EpisodeRecordingEntry(
          sequence: 3,
          monotonicOffsetNanoseconds: 4,
          record: .camera(.frameReference(CameraFrameRecord(
            descriptor: descriptorB,
            artifact: ContentAddressedFrameReference(
              contentSHA256: digestB,
              byteCount: Int.max,
              relativePath: "frames/\(digestB).frame"
            )
          )))
        ),
      ],
      close: nil
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let payload = try encoder.encode(document)
    #expect(try JSONDecoder().decode(EpisodeRecordingDocument.self, from: payload) == document)

    let manifestURL = fixture.directoryURL.appendingPathComponent("episode-recording.json")
    let original = try Data(contentsOf: manifestURL)
    var envelope = try #require(
      JSONSerialization.jsonObject(with: original) as? [String: Any]
    )
    envelope["recordingPayload"] = payload.base64EncodedString()
    envelope["payloadSHA256"] = SHA256.hash(data: payload)
      .map { String(format: "%02x", $0) }
      .joined()
    try JSONSerialization.data(withJSONObject: envelope, options: [.sortedKeys])
      .write(to: manifestURL)

    #expect(throws: EpisodeRecordingError.corruptRecording) {
      _ = try fixture.open()
    }
    #expect(!FileManager.default.fileExists(
      atPath: fixture.directoryURL.appendingPathComponent("frames").path
    ))
  }

  @Test("sparse unrecognized artifact consumes quota without frame publication")
  func sparseUnrecognizedArtifactConsumesQuota() async throws {
    let policy = EpisodeFrameRetentionPolicy(
      maximumUniqueFrameCount: 1,
      maximumTotalUniqueFrameBytes: 4_096
    )
    let fixture = try RecordingFixture(frameRetentionPolicy: policy)
    defer { fixture.remove() }
    let store = try fixture.open()
    let active = stream(122)
    try await activate(active, in: store)
    let manifestURL = fixture.directoryURL.appendingPathComponent("episode-recording.json")
    let manifestBefore = try Data(contentsOf: manifestURL)
    let framesURL = fixture.directoryURL.appendingPathComponent("frames", isDirectory: true)
    try FileManager.default.createDirectory(at: framesURL, withIntermediateDirectories: false)
    let sparseURL = framesURL.appendingPathComponent("unrecognized.sparse")
    let descriptor = Darwin.open(
      sparseURL.path,
      O_RDWR | O_CREAT | O_EXCL | O_CLOEXEC,
      mode_t(S_IRUSR)
    )
    try #require(descriptor >= 0)
    defer { _ = Darwin.close(descriptor) }
    try #require(Darwin.ftruncate(descriptor, 4_096) == 0)

    #expect(await store.snapshot().completenessIssues.contains(
      .unrecognizedFrameArtifact(relativePath: "frames/unrecognized.sparse")
    ))
    await #expect(throws: EpisodeRecordingError.frameRetentionLimitExceeded(
      policy: policy,
      currentUniqueFrameCount: 1,
      currentUniqueFrameBytes: 4_096,
      proposedUniqueFrameBytes: 8
    )) {
      try await store.recordCameraFrame(
        frame(122, stream: active),
        bytes: Data(repeating: 8, count: 8),
        at: 3
      )
    }
    #expect(try Data(contentsOf: manifestURL) == manifestBefore)
    #expect(try frameArtifactURLs(in: fixture).isEmpty)
  }

  @Test("snapshot maps aggregate durable inventory overflow to typed incompleteness")
  func snapshotInventoryAccountingOverflowIsTyped() async throws {
    let fixture = try RecordingFixture()
    defer { fixture.remove() }
    _ = try fixture.open()
    try FileManager.default.createDirectory(
      at: fixture.directoryURL.appendingPathComponent("frames", isDirectory: true),
      withIntermediateDirectories: false
    )
    let store = try fixture.open(fault: .inventoryAccountingOverflowOnce)

    #expect(await store.snapshot().completenessIssues == [
      .frameRetentionAccountingOverflow
    ])
    #expect(await store.snapshot().completenessIssues.isEmpty)
  }

  @Test("duplicate bytes cannot bypass overflowing durable inventory accounting")
  func duplicateBytesInventoryOverflowFailsBeforeManifest() async throws {
    let fixture = try RecordingFixture()
    defer { fixture.remove() }
    let initial = try fixture.open()
    let active = stream(123)
    let bytes = Data([9, 8, 7, 6, 5, 4, 3, 2])
    try await activate(active, in: initial)
    _ = try await initial.recordCameraFrame(
      frame(123, stream: active),
      bytes: bytes,
      at: 3
    )
    let manifestURL = fixture.directoryURL.appendingPathComponent("episode-recording.json")
    let manifestBefore = try Data(contentsOf: manifestURL)
    let artifactsBefore = try frameArtifactURLs(in: fixture)
    let namesBefore = artifactsBefore.map(\.lastPathComponent).sorted()
    let contentsBefore = try artifactsBefore.map { try Data(contentsOf: $0) }

    let store = try fixture.open(fault: .inventoryAccountingOverflowOnce)
    await #expect(throws: EpisodeRecordingError.frameRetentionAccountingOverflow) {
      try await store.recordCameraFrame(
        frame(124, stream: active),
        bytes: bytes,
        at: 4
      )
    }
    #expect(try Data(contentsOf: manifestURL) == manifestBefore)
    let artifactsAfter = try frameArtifactURLs(in: fixture)
    #expect(artifactsAfter.map(\.lastPathComponent).sorted() == namesBefore)
    #expect(try artifactsAfter.map { try Data(contentsOf: $0) } == contentsBefore)
    let frameEntries = await store.snapshot().entries.filter { entry in
      if case .camera(.frameReference) = entry.record { return true }
      return false
    }
    #expect(frameEntries.count == 1)
  }

  @Test("an unobserved uncertain replacement poisons the actor without inventing a successor")
  func unobservedReplacementUncertainty() async throws {
    let fixture = try RecordingFixture()
    defer { fixture.remove() }
    let store = try fixture.open(
      fault: .manifestReplacementOutcomeUncertainWithoutInstallOnce
    )
    let pending = stream(98)

    await #expect(throws: EpisodeRecordingError.postRenameDirectorySynchronizationUncertain(
      code: EIO
    )) {
      try await store.recordCameraLifecycle(.startRequested(pending), at: 1)
    }
    let uncertain = await store.snapshot()
    #expect(uncertain.durability == .uncertain(candidateWasObserved: false))
    #expect(uncertain.entries.isEmpty)
    await #expect(throws: EpisodeRecordingError.requiresReopenAfterDurabilityUncertainty) {
      try await store.recordCameraLifecycle(.startRequested(pending), at: 1)
    }
    let reopened = try fixture.open()
    #expect(await reopened.snapshot().durability == .verified)
    #expect(await reopened.snapshot().entries.isEmpty)
  }

  @Test("actor serialization assigns a complete contiguous order under concurrent callers")
  func concurrentCallersAreSerialized() async throws {
    let fixture = try RecordingFixture()
    defer { fixture.remove() }
    let store = try fixture.open()

    try await withThrowingTaskGroup(of: Void.self) { group in
      for index in 0..<32 {
        group.addTask {
          let item = invocation(UInt64(index + 100), .close)
          _ = try await store.recordControllerInvocation(
            item,
            at: 1
          )
          _ = try await store.recordControllerCompletion(
            ControllerCompletion(invocationID: item.id, outcome: .succeeded(.close)),
            at: 1
          )
        }
      }
      try await group.waitForAll()
    }

    let snapshot = await store.snapshot()
    #expect(snapshot.entries.count == 64)
    #expect(snapshot.entries.map(\.sequence) == Array(0..<UInt64(64)))
    #expect(snapshot.isComplete)
  }

  @Test("independent stores cannot overwrite a successor committed from the same base")
  func concurrentStoreConflict() async throws {
    let fixture = try RecordingFixture()
    defer { fixture.remove() }
    let first = try fixture.open()
    let second = try fixture.open()
    let firstRecord = CameraLifecycleRecord.startRequested(stream(200))
    let secondRecord = CameraLifecycleRecord.startRequested(stream(201))

    async let firstAttempt = commitAttempt(firstRecord, to: first)
    async let secondAttempt = commitAttempt(secondRecord, to: second)
    let attempts = await [firstAttempt, secondAttempt]
    #expect(attempts.filter(\.isCommitted).count == 1)
    #expect(attempts.filter(\.isConflict).count == 1)

    let durable = try fixture.open()
    let records = await durable.snapshot().entries.map(\.record)
    #expect(records.count == 1)
    #expect(
      records == [.camera(.lifecycle(firstRecord))]
        || records == [.camera(.lifecycle(secondRecord))]
    )
  }

  @Test("a cross-process lock serializes compare-and-swap against an external successor")
  func crossProcessLockAndCompareAndSwap() async throws {
    // Broad parallel suites can delay Swift task admission for several seconds. These finite
    // watchdogs bound failure only; ready and commit-boundary files remain the ordering authority.
    let childBoundaryWatchdogSeconds = 15.0
    let parentProcessWatchdog: Duration = .seconds(20)
    let postChildCommitWatchdog: Duration = .seconds(10)
    let fixture = try RecordingFixture()
    defer { fixture.remove() }
    let competitorFixture = try RecordingFixture()
    defer { competitorFixture.remove() }
    let competitorStore = try competitorFixture.open()
    _ = try await competitorStore.recordCameraLifecycle(
      .startRequested(stream(700)),
      at: 1
    )

    let pythonURL = URL(fileURLWithPath: "/usr/bin/python3")
    try #require(FileManager.default.isExecutableFile(atPath: pythonURL.path))
    let manifestURL = fixture.directoryURL.appendingPathComponent("episode-recording.json")
    let sourceManifestURL = competitorFixture.directoryURL
      .appendingPathComponent("episode-recording.json")
    let commitBoundaryURL = fixture.directoryURL.appendingPathComponent("commit-boundary")
    let store = try fixture.open(
      fault: .signalImmediatelyBeforeCommitKernelLock(commitBoundaryURL)
    )
    let initialManifest = try Data(contentsOf: manifestURL)
    let lockURL = manifestURL.appendingPathExtension("lock")
    let readyURL = fixture.directoryURL.appendingPathComponent("child-ready")
    let script = """
      import base64, fcntl, os, sys, time
      lock_path, source_path, destination_path, ready_path, boundary_path, root_path, expected = sys.argv[1:]
      lock_fd = os.open(lock_path, os.O_CREAT | os.O_RDWR, 0o600)
      fcntl.lockf(lock_fd, fcntl.LOCK_EX)
      open(ready_path, "wb").close()
      boundary_deadline = time.monotonic() + \(childBoundaryWatchdogSeconds)
      while not os.path.exists(boundary_path):
          if time.monotonic() >= boundary_deadline:
              sys.exit(3)
          time.sleep(0.001)
      with open(destination_path, "rb") as current:
          if current.read() != base64.b64decode(expected):
              sys.exit(4)
      with open(source_path, "rb") as source:
          payload = source.read()
      temporary_path = destination_path + ".child.tmp"
      output_fd = os.open(temporary_path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
      with os.fdopen(output_fd, "wb") as output:
          output.write(payload)
          output.flush()
          os.fsync(output.fileno())
      os.replace(temporary_path, destination_path)
      root_fd = os.open(root_path, os.O_RDONLY)
      os.fsync(root_fd)
      os.close(root_fd)
      fcntl.lockf(lock_fd, fcntl.LOCK_UN)
      os.close(lock_fd)
      """
    let process = Process()
    process.executableURL = pythonURL
    process.arguments = [
      "-c", script, lockURL.path, sourceManifestURL.path, manifestURL.path,
      readyURL.path, commitBoundaryURL.path, fixture.directoryURL.path,
      initialManifest.base64EncodedString(),
    ]
    try process.run()
    defer { if process.isRunning { process.terminate() } }
    try await waitForFile(readyURL)

    let attemptTask = Task {
      await commitAttempt(.startRequested(stream(701)), to: store)
    }
    do {
      try await waitForProcessExit(process, timeout: parentProcessWatchdog)
    } catch {
      attemptTask.cancel()
      throw error
    }
    #expect(process.terminationStatus == 0)
    #expect(try await waitForCommitAttempt(
      attemptTask,
      timeout: postChildCommitWatchdog
    ).isConflict)

    let durable = try fixture.open()
    #expect(await durable.snapshot().entries.map(\.record) == [
      .camera(.lifecycle(.startRequested(stream(700))))
    ])
  }

  @Test("commit attempt timeout does not await its non-cooperative bounded loser")
  func commitAttemptTimeoutDoesNotAwaitNonCooperativeLoser() async throws {
    let release = DispatchSemaphore(value: 0)
    let delayedRelease = Task.detached {
      do {
        try await Task.sleep(for: .seconds(12))
      } catch {
        return
      }
      release.signal()
    }
    let attempt: Task<CommitAttempt, Never> = Task.detached {
      await withCheckedContinuation { continuation in
        DispatchQueue.global().async {
          release.wait()
          continuation.resume(returning: .unexpected)
        }
      }
    }
    defer {
      release.signal()
      delayedRelease.cancel()
      attempt.cancel()
    }
    let clock = ContinuousClock()
    let started = clock.now

    await #expect(throws: RecordingFixtureError.timedOut) {
      try await waitForCommitAttempt(attempt, timeout: .milliseconds(25))
    }
    #expect(started.duration(to: clock.now) < .seconds(8))
  }

  @Test("post-rename append uncertainty is visible, reconciled, and poisons mutation until reopen")
  func appendPostRenameUncertainty() async throws {
    let fixture = try RecordingFixture()
    defer { fixture.remove() }
    let store = try fixture.open(fault: .manifestDirectorySynchronizationFailureOnce)
    let pending = stream(500)

    await #expect(throws: EpisodeRecordingError.postRenameDirectorySynchronizationUncertain(
      code: EIO
    )) {
      try await store.recordCameraLifecycle(.startRequested(pending), at: 1)
    }
    let uncertain = await store.snapshot()
    #expect(uncertain.durability == .uncertain(candidateWasObserved: true))
    #expect(uncertain.entries.map(\.record) == [.camera(.lifecycle(.startRequested(pending)))])
    await #expect(throws: EpisodeRecordingError.requiresReopenAfterDurabilityUncertainty) {
      try await store.recordCameraLifecycle(.failed(CameraLifecycleFailure(
        operation: .start(pending),
        kind: .cancelled
      )), at: 2)
    }

    let reopened = try fixture.open()
    #expect(await reopened.snapshot().durability == .verified)
    #expect(await reopened.snapshot().entries == uncertain.entries)
    _ = try await reopened.recordCameraLifecycle(.failed(CameraLifecycleFailure(
      operation: .start(pending),
      kind: .cancelled
    )), at: 2)
    #expect(await reopened.snapshot().isComplete)
  }

  @Test("post-rename close uncertainty exposes the installed close and requires reopen")
  func closePostRenameUncertainty() async throws {
    let fixture = try RecordingFixture()
    defer { fixture.remove() }
    let initial = try fixture.open()
    let pending = stream(501)
    _ = try await initial.recordCameraLifecycle(.startRequested(pending), at: 1)
    _ = try await initial.recordCameraLifecycle(.failed(CameraLifecycleFailure(
      operation: .start(pending),
      kind: .sourceUnavailable
    )), at: 2)

    let store = try fixture.open(fault: .manifestDirectorySynchronizationFailureOnce)
    await #expect(throws: EpisodeRecordingError.postRenameDirectorySynchronizationUncertain(
      code: EIO
    )) {
      try await store.close(at: 3)
    }
    let uncertain = await store.snapshot()
    #expect(uncertain.isClosed)
    #expect(uncertain.durability == .uncertain(candidateWasObserved: true))
    await #expect(throws: EpisodeRecordingError.requiresReopenAfterDurabilityUncertainty) {
      try await store.close(at: 4)
    }

    let reopened = try fixture.open()
    let reconciled = await reopened.snapshot()
    #expect(reconciled.isClosed)
    #expect(reconciled.durability == .verified)
    #expect(reconciled.entries == uncertain.entries)
  }

  @Test("closed recordings expose incomplete controller and camera lifetimes without filling gaps")
  func closedIncompleteRecording() async throws {
    let fixture = try RecordingFixture()
    defer { fixture.remove() }
    let store = try fixture.open()
    let pending = invocation(300, .close)
    let activeStream = stream(300)
    _ = try await store.recordControllerInvocation(pending, at: 1)
    _ = try await store.recordCameraLifecycle(.startRequested(activeStream), at: 2)
    _ = try await store.recordCameraLifecycle(.started(activeStream), at: 3)
    try await store.close(at: 4)

    let reopened = try fixture.open()
    let snapshot = await reopened.snapshot()
    #expect(snapshot.isClosed)
    #expect(!snapshot.isComplete)
    #expect(snapshot.completenessIssues.contains(.controllerCompletionMissing(pending.id)))
    #expect(snapshot.completenessIssues.contains(.cameraStopIncomplete(activeStream)))
  }

  @Test("manifest corruption is an integrity failure, not an empty recording")
  func corruptManifestIsRefused() async throws {
    let fixture = try RecordingFixture()
    defer { fixture.remove() }
    let store = try fixture.open()
    _ = try await store.recordCameraLifecycle(
      .startRequested(stream(400)),
      at: 1
    )
    try Data("not a recording envelope".utf8).write(
      to: fixture.directoryURL.appendingPathComponent("episode-recording.json")
    )

    #expect(throws: EpisodeRecordingError.corruptEnvelope) {
      _ = try fixture.open()
    }
  }

  @Test("a decodable envelope with a changed payload checksum is refused")
  func payloadChecksumMismatchIsRefused() async throws {
    let fixture = try RecordingFixture()
    defer { fixture.remove() }
    let store = try fixture.open()
    _ = try await store.recordCameraLifecycle(.startRequested(stream(600)), at: 1)
    let manifestURL = fixture.directoryURL.appendingPathComponent("episode-recording.json")
    let encoded = try Data(contentsOf: manifestURL)
    var object = try #require(
      JSONSerialization.jsonObject(with: encoded) as? [String: Any]
    )
    object["payloadSHA256"] = String(repeating: "0", count: 64)
    let corrupted = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    try FileManager.default.removeItem(at: manifestURL)
    try corrupted.write(to: manifestURL)

    #expect(throws: EpisodeRecordingError.payloadChecksumMismatch) {
      _ = try fixture.open()
    }
  }
}

private extension EpisodeRecordingEntry {
  var frameReference: ContentAddressedFrameReference? {
    guard case let .camera(.frameReference(frame)) = record else { return nil }
    return frame.artifact
  }
}

private func invocation(
  _ value: UInt64,
  _ operation: ControllerOperationInvocation
) -> ControllerInvocation {
  let byte = UInt8(truncatingIfNeeded: value)
  return ControllerInvocation(
    id: ControllerInvocationID(rawValue: UUID(
      uuid: (byte, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, byte)
    )),
    operation: operation
  )
}

private func stream(_ value: Int) -> CameraStreamIdentity {
  let byte = UInt8(truncatingIfNeeded: value)
  return CameraStreamIdentity(
    source: CameraSourceIdentity(rawValue: "camera-\(value)"),
    configuration: CameraConfigurationIdentity(rawValue: UUID(
      uuid: (byte, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, byte)
    ))
  )
}

private func reconfiguredStream(
  _ stream: CameraStreamIdentity,
  value: UInt8
) -> CameraStreamIdentity {
  CameraStreamIdentity(
    source: stream.source,
    configuration: CameraConfigurationIdentity(rawValue: UUID(
      uuid: (value, 2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, value)
    ))
  )
}

private func frame(_ value: UInt64, stream: CameraStreamIdentity) -> CameraFrameDescriptor {
  CameraFrameDescriptor(
    stream: stream,
    frameID: CameraFrameIdentity(rawValue: "frame-\(value)"),
    sequence: value,
    captureNanoseconds: value * 1_000,
    width: 2,
    height: 1,
    rowBytes: 8,
    pixelFormat: .bgra8
  )
}

private func encodedFrame(
  _ value: UInt64,
  stream: CameraStreamIdentity
) -> CameraFrameDescriptor {
  CameraFrameDescriptor(
    stream: stream,
    frameID: CameraFrameIdentity(rawValue: "encoded-frame-\(value)"),
    sequence: value,
    captureNanoseconds: value * 1_000,
    width: 1,
    height: 1,
    rowBytes: 1,
    pixelFormat: .encoded(mediaType: "application/octet-stream")
  )
}

private func activate(
  _ stream: CameraStreamIdentity,
  in store: EpisodeRecordingStore,
  startingAt offset: UInt64 = 1
) async throws {
  _ = try await store.recordCameraLifecycle(.startRequested(stream), at: offset)
  _ = try await store.recordCameraLifecycle(.started(stream), at: offset + 1)
}

private func deactivate(
  _ stream: CameraStreamIdentity,
  in store: EpisodeRecordingStore,
  startingAt offset: UInt64
) async throws {
  _ = try await store.recordCameraLifecycle(.stopRequested(stream), at: offset)
  _ = try await store.recordCameraLifecycle(.stopped(stream), at: offset + 1)
}

private struct RecordingFixture {
  let directoryURL: URL
  let frameRetentionPolicy: EpisodeFrameRetentionPolicy
  let recordingID = EpisodeRecordingID(rawValue: UUID(
    uuid: (42, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 42)
  ))
  let schemaRevision = EpisodeRecordingSchemaRevision(rawValue: "plotter-recording-v1")

  init(
    frameRetentionPolicy: EpisodeFrameRetentionPolicy = EpisodeFrameRetentionPolicy(
      maximumUniqueFrameCount: 64,
      maximumTotalUniqueFrameBytes: 1_048_576
    )
  ) throws {
    self.frameRetentionPolicy = frameRetentionPolicy
    directoryURL = FileManager.default.temporaryDirectory.appendingPathComponent(
      "AdaptivePlotter-recording-\(UUID().uuidString)",
      isDirectory: true
    )
    try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: false)
  }

  func open() throws -> EpisodeRecordingStore {
    try EpisodeRecordingStore.open(
      directoryURL: directoryURL,
      recordingID: recordingID,
      schemaRevision: schemaRevision,
      frameRetentionPolicy: frameRetentionPolicy
    )
  }

  func open(fault: EpisodeRecordingPersistenceFault) throws -> EpisodeRecordingStore {
    try EpisodeRecordingStore.open(
      directoryURL: directoryURL,
      recordingID: recordingID,
      schemaRevision: schemaRevision,
      frameRetentionPolicy: frameRetentionPolicy,
      persistenceFault: fault
    )
  }

  func remove() {
    try? FileManager.default.removeItem(at: directoryURL)
  }

}

private enum CommitAttempt: Equatable, Sendable {
  case committed
  case conflict
  case unexpected

  var isCommitted: Bool {
    if case .committed = self { return true }
    return false
  }

  var isConflict: Bool {
    if case .conflict = self { return true }
    return false
  }
}

private enum FrameCommitAttempt: Equatable, Sendable {
  case committed
  case conflict
  case unexpected

  var isCommitted: Bool {
    if case .committed = self { return true }
    return false
  }

  var isConflict: Bool {
    if case .conflict = self { return true }
    return false
  }
}

private func frameArtifactURLs(in fixture: RecordingFixture) throws -> [URL] {
  let framesURL = fixture.directoryURL.appendingPathComponent("frames", isDirectory: true)
  guard FileManager.default.fileExists(atPath: framesURL.path) else { return [] }
  return try FileManager.default.contentsOfDirectory(
    at: framesURL,
    includingPropertiesForKeys: nil
  ).filter { $0.pathExtension == "frame" }
}

private func waitForFile(_ url: URL) async throws {
  for _ in 0..<2_000 {
    if FileManager.default.fileExists(atPath: url.path) { return }
    try await Task.sleep(for: .milliseconds(1))
  }
  throw RecordingFixtureError.timedOut
}

private func waitForProcessExit(
  _ process: Process,
  timeout: Duration
) async throws {
  let clock = ContinuousClock()
  let deadline = clock.now.advanced(by: timeout)
  while process.isRunning && clock.now < deadline {
    try await Task.sleep(for: .milliseconds(1))
  }
  guard process.isRunning else { return }

  process.terminate()
  let terminationDeadline = clock.now.advanced(by: .milliseconds(250))
  while process.isRunning && clock.now < terminationDeadline {
    try await Task.sleep(for: .milliseconds(1))
  }
  if process.isRunning {
    _ = Darwin.kill(process.processIdentifier, SIGKILL)
    let killDeadline = clock.now.advanced(by: .milliseconds(250))
    while process.isRunning && clock.now < killDeadline {
      try await Task.sleep(for: .milliseconds(1))
    }
  }
  throw RecordingFixtureError.timedOut
}

private func waitForCommitAttempt(
  _ attempt: Task<CommitAttempt, Never>,
  timeout: Duration
) async throws -> CommitAttempt {
  let race = CommitAttemptCompletionRace()
  let watcher = Task {
    await race.resolve(.completed(await attempt.value))
  }
  let deadline = Task {
    do {
      try await Task.sleep(for: timeout)
    } catch {
      return
    }
    await race.resolve(.timedOut)
  }
  let outcome = await withCheckedContinuation { continuation in
    Task { await race.install(continuation) }
  }
  watcher.cancel()
  deadline.cancel()
  switch outcome {
  case let .completed(result):
    return result
  case .timedOut:
    attempt.cancel()
    throw RecordingFixtureError.timedOut
  }
}

private enum CommitAttemptCompletionOutcome: Sendable {
  case completed(CommitAttempt)
  case timedOut
}

private actor CommitAttemptCompletionRace {
  private var continuation: CheckedContinuation<CommitAttemptCompletionOutcome, Never>?
  private var pendingOutcome: CommitAttemptCompletionOutcome?
  private var isResolved = false

  func install(
    _ continuation: CheckedContinuation<CommitAttemptCompletionOutcome, Never>
  ) {
    if let pendingOutcome {
      self.pendingOutcome = nil
      continuation.resume(returning: pendingOutcome)
    } else {
      self.continuation = continuation
    }
  }

  func resolve(_ outcome: CommitAttemptCompletionOutcome) {
    guard !isResolved else { return }
    isResolved = true
    if let continuation {
      self.continuation = nil
      continuation.resume(returning: outcome)
    } else {
      pendingOutcome = outcome
    }
  }
}

private enum RecordingFixtureError: Error {
  case timedOut
}

private func commitAttempt(
  _ record: CameraLifecycleRecord,
  to store: EpisodeRecordingStore
) async -> CommitAttempt {
  do {
    _ = try await store.recordCameraLifecycle(record, at: 1)
    return .committed
  } catch EpisodeRecordingError.concurrentWriterConflict {
    return .conflict
  } catch {
    return .unexpected
  }
}

private func frameCommitAttempt(
  _ descriptor: CameraFrameDescriptor,
  bytes: Data,
  to store: EpisodeRecordingStore
) async -> FrameCommitAttempt {
  do {
    _ = try await store.recordCameraFrame(descriptor, bytes: bytes, at: 3)
    return .committed
  } catch EpisodeRecordingError.concurrentWriterConflict {
    return .conflict
  } catch {
    return .unexpected
  }
}
