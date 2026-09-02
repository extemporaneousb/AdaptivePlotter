import Foundation
import PlotterModel
import Testing

@testable import PlotterRuntime

@Suite("Camera capture policy and frame delivery")
struct CameraCaptureTests {
  @Test("interactive preview caps upstream delivery at its 10 FPS materialization budget")
  func interactivePreviewCapsDriverWorkload() async throws {
    let device = CameraDevice(id: CameraDeviceID(rawValue: "camera"), name: "Camera")
    let driver = TestCameraDriver(devices: [device])
    let capture = CameraCapture(driver: driver, materializationPolicy: .interactivePreview)

    await capture.discoverDevices()
    await capture.start()

    let requested = try #require(await driver.requestedMaximumFramesPerSecond.first ?? nil)
    #expect(requested == 10)
    #expect(await capture.diagnostics().maximumDeliveredFramesPerSecond == requested)
    #expect(await capture.diagnostics().deliveryLimitOutcome == .applied(framesPerSecond: 10))
    #expect(
      LiveFrameMaterializationPolicy.interactivePreview.minimumPreviewIntervalNanoseconds
        * UInt64(requested) == 1_000_000_000
    )
  }

  @Test("an unapplied best-effort device cap remains running and reports why")
  func unappliedDeviceCapIsNonfatalAndTruthful() async throws {
    let device = CameraDevice(id: CameraDeviceID(rawValue: "camera"), name: "Camera")
    let reason = "fixture camera does not support 10 FPS"
    let driver = TestCameraDriver(
      devices: [device],
      deliveryLimitOutcome: .unapplied(
        requestedFramesPerSecond: 10,
        reason: reason
      )
    )
    let capture = CameraCapture(driver: driver, materializationPolicy: .interactivePreview)

    await capture.discoverDevices()
    await capture.start()

    #expect(await capture.snapshot().state == .running)
    #expect(await capture.snapshot().error == nil)
    #expect(await capture.diagnostics().maximumDeliveredFramesPerSecond == nil)
    #expect(
      await capture.diagnostics().deliveryLimitOutcome
        == .unapplied(requestedFramesPerSecond: 10, reason: reason)
    )
  }

  @Test("same-resolution passive preview performs no hash and exact promotion computes once")
  func previewDefersFullFrameEvidenceHash() async throws {
    let device = CameraDevice(id: CameraDeviceID(rawValue: "camera"), name: "Camera")
    let driver = TestCameraDriver(devices: [device])
    let capture = CameraCapture(driver: driver, materializationPolicy: .interactivePreview)
    let width = 1_920
    let height = 1_080
    let rowBytes = width * 4
    let bytes = Data(repeating: 127, count: rowBytes * height)

    await capture.discoverDevices()
    await capture.start()
    let start = DispatchTime.now().uptimeNanoseconds
    await driver.emit(.frame(CapturedBGRAFrame(
      width: width,
      height: height,
      rowBytes: rowBytes,
      bytes: bytes,
      captureNanoseconds: 100
    )))
    try await waitUntil { await capture.diagnostics().previewMaterializedFrameCount == 1 }
    let previewElapsed = DispatchTime.now().uptimeNanoseconds - start
    let preview = try #require(await capture.snapshot().latestFrame)

    #expect(!preview.frame.contentHashIsMaterialized)
    #expect(preview.frame.materializedContentSHA256 == nil)
    #expect(await capture.diagnostics().analysisContentHashComputationCount == 0)
    #expect(await capture.diagnostics().exactContentHashComputationCount == 0)
    #expect(await capture.diagnostics().serializationContentHashComputationCount == 0)

    let exactStart = DispatchTime.now().uptimeNanoseconds
    let exact = try #require(
      try await capture.materializeLatestFrame(policy: .returnOnly)
    )
    let exactElapsed = DispatchTime.now().uptimeNanoseconds - exactStart
    print(
      "same-resolution 1920x1080 materialization: preview=\(previewElapsed)ns exact-digest=\(exactElapsed)ns"
    )

    #expect(exact.frame.id == preview.frame.id)
    #expect(exact.frame.contentHashIsMaterialized)
    #expect(exact.frame.contentHashMaterializationPurpose == .exactEvidence)
    #expect(await capture.diagnostics().analysisContentHashComputationCount == 0)
    #expect(await capture.diagnostics().exactContentHashComputationCount == 1)
    #expect(await capture.diagnostics().serializationContentHashComputationCount == 0)

    let repeated = try #require(
      try await capture.materializeLatestFrame(policy: .returnOnly)
    )
    #expect(repeated.frame.contentSHA256 == exact.frame.contentSHA256)
    #expect(await capture.diagnostics().exactContentHashComputationCount == 1)

    let ownedBytes = OwnedFrameBytes(copying: bytes)
    func constructionDuration(eager: Bool, sequence: UInt64) throws -> UInt64 {
      let began = DispatchTime.now().uptimeNanoseconds
      let frame = try StampedFrame(
        sequence: sequence,
        captureNanoseconds: sequence,
        cameraConfigurationID: CameraConfigurationID(),
        width: width,
        height: height,
        rowBytes: rowBytes,
        pixelFormat: .bgra8,
        bytes: ownedBytes,
        eagerlyMaterializeContentHash: eager
      )
      #expect(frame.contentHashIsMaterialized == eager)
      return DispatchTime.now().uptimeNanoseconds - began
    }
    var passiveConstruction: [UInt64] = []
    var eagerConstruction: [UInt64] = []
    for index in 0..<5 {
      passiveConstruction.append(
        try constructionDuration(eager: false, sequence: UInt64(1_000 + index)))
      eagerConstruction.append(
        try constructionDuration(eager: true, sequence: UInt64(2_000 + index)))
    }
    let passiveMedian = passiveConstruction.sorted()[2]
    let eagerMedian = eagerConstruction.sorted()[2]
    print(
      "same-resolution 1920x1080 construction median: passive=\(passiveMedian)ns eager-sha=\(eagerMedian)ns"
    )
    #expect(passiveMedian < eagerMedian)
  }

  @Test("automatic analysis promotes one preview hash and exact request reuses it")
  func automaticAnalysisOwnsOneHashPromotion() async throws {
    let device = CameraDevice(id: CameraDeviceID(rawValue: "camera"), name: "Camera")
    let driver = TestCameraDriver(devices: [device])
    let capture = CameraCapture(driver: driver, materializationPolicy: .interactivePreview)
    let pipeline = PlotterSceneAnalysisPipeline()

    await capture.discoverDevices()
    await capture.start()
    await pipeline.start(cadence: .fiveFPS, requestedFeatures: [])
    await driver.emit(.frame(CapturedBGRAFrame(
      width: 16,
      height: 12,
      rowBytes: 64,
      bytes: Data(repeating: 255, count: 16 * 12 * 4),
      captureNanoseconds: 100
    )))
    try await waitUntil { await capture.diagnostics().previewMaterializedFrameCount == 1 }
    let passive = try #require(await capture.snapshot().latestFrame)
    #expect(passive.frame.materializedContentSHA256 == nil)
    #expect(await capture.diagnostics().analysisContentHashComputationCount == 0)

    await pipeline.submit(passive)
    try await waitUntil { await pipeline.diagnostics().analyzedFrameCount == 1 }
    let analyzed = try #require(await pipeline.snapshot().latestResult)
    #expect(analyzed.displayedFrame.frame.contentHashMaterializationPurpose == .analysis)
    #expect(
      analyzed.measurement.frameSHA256
        == analyzed.displayedFrame.frame.contentSHA256
    )
    #expect(await capture.diagnostics().analysisContentHashComputationCount == 1)
    #expect(await capture.diagnostics().exactContentHashComputationCount == 0)

    _ = analyzed.displayedFrame.frame.contentSHA256
    _ = analyzed.displayedFrame.frame.contentSHA256
    _ = try JSONEncoder().encode(analyzed.displayedFrame.frame)
    #expect(await capture.diagnostics().analysisContentHashComputationCount == 1)
    #expect(await capture.diagnostics().serializationContentHashComputationCount == 0)

    let exact = try #require(
      try await capture.materializeLatestFrame(policy: .returnOnly)
    )
    #expect(exact.frame.contentSHA256 == analyzed.displayedFrame.frame.contentSHA256)
    #expect(await capture.diagnostics().analysisContentHashComputationCount == 1)
    #expect(await capture.diagnostics().exactContentHashComputationCount == 0)
    await pipeline.stop()
  }

  @Test("zero, one, and multiple devices have explicit selection behavior")
  func deviceSelection() async throws {
    let none = TestCameraDriver(devices: [])
    let noCameraCapture = CameraCapture(driver: none)
    await noCameraCapture.discoverDevices()
    #expect(await noCameraCapture.snapshot().error == .noDevices)

    let only = CameraDevice(id: CameraDeviceID(rawValue: "only"), name: "Only Camera")
    let one = TestCameraDriver(devices: [only])
    let oneCameraCapture = CameraCapture(driver: one)
    await oneCameraCapture.discoverDevices()
    #expect(await oneCameraCapture.snapshot().selectedDeviceID == only.id)

    let second = CameraDevice(id: CameraDeviceID(rawValue: "second"), name: "Second Camera")
    let multiple = TestCameraDriver(devices: [second, only])
    let multiCameraCapture = CameraCapture(driver: multiple)
    await multiCameraCapture.discoverDevices()
    #expect(await multiCameraCapture.snapshot().selectedDeviceID == nil)
    await multiCameraCapture.start()
    #expect(
      await multiCameraCapture.snapshot().error == .selectionRequired(availableDeviceCount: 2))
    try await multiCameraCapture.select(second.id)
    #expect(await multiCameraCapture.snapshot().selectedDeviceID == second.id)
  }

  @Test("permission denial is direct and starts no session")
  func permissionDenied() async {
    let device = CameraDevice(id: CameraDeviceID(rawValue: "camera"), name: "Camera")
    let driver = TestCameraDriver(authorization: .denied, devices: [device])
    let capture = CameraCapture(driver: driver)
    await capture.discoverDevices()
    await capture.start()
    #expect(await capture.snapshot().state == .failed(.permissionDenied))
    #expect(await driver.startCount == 0)
  }

  @Test("interruption, disconnect, and restart remain recoverable and change configuration")
  func lifecycleAndReconfiguration() async throws {
    let device = CameraDevice(id: CameraDeviceID(rawValue: "camera"), name: "Camera")
    let otherDevice = CameraDevice(
      id: CameraDeviceID(rawValue: "other-camera"), name: "Other Camera")
    let driver = TestCameraDriver(devices: [device, otherDevice])
    let capture = CameraCapture(driver: driver)
    await capture.discoverDevices()
    try await capture.select(device.id)
    await capture.start()
    await driver.emit(sample(value: 10, time: 10))
    try await waitUntil { await capture.snapshot().latestFrame != nil }
    let firstConfiguration = try #require(
      await capture.snapshot().latestFrame?.frame.cameraConfigurationID)

    await capture.stop()
    #expect(await capture.snapshot().state == .stopped)
    await capture.restart()
    await driver.emit(sample(value: 20, time: 20))
    try await waitUntil { await capture.snapshot().latestFrame != nil }
    let restartedConfiguration = try #require(
      await capture.snapshot().latestFrame?.frame.cameraConfigurationID)
    #expect(firstConfiguration != restartedConfiguration)
    #expect(await driver.stopCount >= 1)

    await driver.emit(.interrupted("device busy"))
    try await waitUntil { await capture.snapshot().state == .interrupted("device busy") }
    await driver.emit(.interruptionEnded)
    try await waitUntil { await capture.snapshot().state == .running }
    await driver.emit(.interrupted("device busy again"))
    try await waitUntil { await capture.snapshot().state == .interrupted("device busy again") }
    await capture.restart()
    #expect(await capture.snapshot().state == .running)

    try await capture.select(otherDevice.id)
    await capture.start()
    await driver.emit(sample(value: 30, time: 30))
    try await waitUntil { await capture.snapshot().latestFrame != nil }
    let selectedConfiguration = try #require(
      await capture.snapshot().latestFrame?.frame.cameraConfigurationID)
    #expect(selectedConfiguration != restartedConfiguration)
    #expect(await capture.snapshot().latestFrame?.source == .live(otherDevice.id))

    await driver.emit(.disconnected(otherDevice.id))
    try await waitUntil { await capture.snapshot().error == .deviceDisconnected(otherDevice.id) }
    #expect(await capture.snapshot().latestFrame == nil)
    await capture.restart()
    #expect(await capture.snapshot().state == .running)
  }

  @Test("captured bytes are copied and sequence and timestamps increase")
  func ownedMonotonicFrames() async throws {
    let device = CameraDevice(id: CameraDeviceID(rawValue: "camera"), name: "Camera")
    let driver = TestCameraDriver(devices: [device])
    let capture = CameraCapture(driver: driver)
    await capture.discoverDevices()
    await capture.start()

    var bytes = Data(repeating: 7, count: 12)
    await driver.emit(
      .frame(
        CapturedBGRAFrame(
          width: 2, height: 1, rowBytes: 12, bytes: bytes, captureNanoseconds: 50)))
    try await waitUntil { await capture.snapshot().latestFrame?.frame.sequence == 1 }
    bytes[0] = 99
    let first = try #require(await capture.snapshot().latestFrame?.frame)
    #expect(first.bytes[0] == 7)
    #expect(first.rowBytes == 12)

    await driver.emit(sample(value: 8, time: 50))
    try await waitUntil { await capture.snapshot().latestFrame?.frame.sequence == 2 }
    let second = try #require(await capture.snapshot().latestFrame?.frame)
    #expect(second.sequence > first.sequence)
    #expect(second.captureNanoseconds > first.captureNanoseconds)
  }

  @Test("delayed interruption end cannot revive an explicitly stopped generation")
  func delayedInterruptionEndAfterStop() async throws {
    let device = CameraDevice(id: CameraDeviceID(rawValue: "camera"), name: "Camera")
    let driver = TestCameraDriver(devices: [device])
    let capture = CameraCapture(driver: driver)
    await capture.discoverDevices()
    await capture.start()
    await driver.emit(.interrupted("device busy"))
    try await waitUntil { await capture.snapshot().state == .interrupted("device busy") }

    await capture.stop()
    await driver.emitFromStart(0, .interruptionEnded)
    try await settleEvents()
    #expect(await capture.snapshot().state == .stopped)
  }

  @Test("delayed events cannot alter a terminally failed generation")
  func delayedEventsAfterFailure() async throws {
    let device = CameraDevice(id: CameraDeviceID(rawValue: "camera"), name: "Camera")
    let driver = TestCameraDriver(devices: [device])
    let capture = CameraCapture(driver: driver)
    await capture.discoverDevices()
    await capture.start()
    await driver.emit(.failed("capture transport failed"))
    let expected = CameraCaptureState.failed(.captureFailed("capture transport failed"))
    try await waitUntil { await capture.snapshot().state == expected }

    await driver.emitFromStart(0, sample(value: 99, time: 99))
    await driver.emitFromStart(0, .interruptionEnded)
    try await settleEvents()
    #expect(await capture.snapshot().state == expected)
    #expect(await capture.snapshot().latestFrame == nil)
  }

  @Test("a delayed discovery cannot overwrite a newer running generation")
  func delayedDiscoveryDuringStart() async throws {
    let device = CameraDevice(id: CameraDeviceID(rawValue: "camera"), name: "Camera")
    let driver = TestCameraDriver(devices: [device], delayedDiscoveryCalls: [1])
    let capture = CameraCapture(driver: driver)

    let staleDiscovery = Task { await capture.discoverDevices() }
    try await waitUntil { await driver.discoveryCount == 1 }
    let start = Task { await capture.start() }
    try await waitUntil {
      let snapshot = await capture.snapshot()
      let isActive = await driver.isActive
      return snapshot.state == .running && isActive
    }

    await driver.resumeDiscovery(call: 1)
    await staleDiscovery.value
    await start.value
    #expect(await capture.snapshot().state == .running)
    #expect(await driver.isActive)
  }

  @Test("stop waits out a delayed start and cannot later report running")
  func stopDuringDelayedStart() async throws {
    let device = CameraDevice(id: CameraDeviceID(rawValue: "camera"), name: "Camera")
    let driver = TestCameraDriver(devices: [device], delayedStartCalls: [1])
    let capture = CameraCapture(driver: driver)
    await capture.discoverDevices()

    let start = Task { await capture.start() }
    try await waitUntil { await driver.startCount == 1 }
    let stop = Task { await capture.stop() }
    try await settleEvents()
    #expect(await capture.snapshot().state == .starting)

    await driver.resumeStart(call: 1)
    await stop.value
    await start.value
    #expect(await capture.snapshot().state == .stopped)
    let isActive = await driver.isActive
    #expect(!isActive)
  }

  @Test("driver events are consumed in callback yield order")
  func orderedDriverEvents() async throws {
    let device = CameraDevice(id: CameraDeviceID(rawValue: "camera"), name: "Camera")
    let driver = TestCameraDriver(devices: [device])
    let capture = CameraCapture(driver: driver)
    await capture.discoverDevices()
    await capture.start()

    await driver.emitBatch([
      sample(value: 1, time: 1),
      .interrupted("device busy"),
      sample(value: 2, time: 2),
      .interruptionEnded,
      sample(value: 3, time: 3),
    ])
    try await waitUntil {
      let snapshot = await capture.snapshot()
      return snapshot.state == .running && snapshot.latestFrame?.frame.bytes[0] == 3
    }
    #expect(await capture.snapshot().latestFrame?.frame.sequence == 2)

    await driver.emitBatch([
      .interruptionEnded,
      .interrupted("late interruption"),
      sample(value: 4, time: 4),
    ])
    try await waitUntil {
      await capture.snapshot().state == .interrupted("late interruption")
    }
    #expect(await capture.snapshot().latestFrame?.frame.bytes[0] == 3)
    #expect(await capture.snapshot().latestFrame?.frame.sequence == 2)

    await driver.emitBatch([.interruptionEnded, sample(value: 5, time: 5)])
    try await waitUntil {
      let snapshot = await capture.snapshot()
      return snapshot.state == .running && snapshot.latestFrame?.frame.bytes[0] == 5
    }
    #expect(await capture.snapshot().latestFrame?.frame.sequence == 3)
  }

  @Test("blocked event consumption coalesces frame bursts without dropping controls")
  func boundedOrderedEventMailbox() async throws {
    let mailbox = CameraDriverEventMailbox()

    for value in UInt8(1)...UInt8(100) {
      mailbox.yield(sample(value: value, time: UInt64(value)))
    }
    mailbox.yield(.interrupted("device busy"))
    for value in UInt8(101)...UInt8(200) {
      mailbox.yield(sample(value: value, time: UInt64(value)))
    }
    mailbox.yield(.interruptionEnded)
    for value in UInt8(201)...UInt8(250) {
      mailbox.yield(sample(value: value, time: UInt64(value)))
    }
    mailbox.yield(.failed("terminal capture failure"))

    let blocked = mailbox.diagnostics()
    #expect(blocked.pendingEventCount == 6)
    #expect(blocked.pendingFrameCount == 3)
    #expect(blocked.maximumPendingFrameCount == 3)

    guard case .frame(let first)? = await mailbox.next() else {
      Issue.record("Expected newest frame from the first burst")
      return
    }
    #expect(try first.materializedBytes()[0] == 100)
    guard case .interrupted(let interruption)? = await mailbox.next() else {
      Issue.record("Expected interruption after the first frame burst")
      return
    }
    #expect(interruption == "device busy")
    guard case .frame(let second)? = await mailbox.next() else {
      Issue.record("Expected newest frame from the interrupted burst")
      return
    }
    #expect(try second.materializedBytes()[0] == 200)
    guard case .interruptionEnded? = await mailbox.next() else {
      Issue.record("Expected interruption end in callback order")
      return
    }
    guard case .frame(let third)? = await mailbox.next() else {
      Issue.record("Expected newest frame from the final burst")
      return
    }
    #expect(try third.materializedBytes()[0] == 250)
    guard case .failed(let failure)? = await mailbox.next() else {
      Issue.record("Expected terminal failure after the final frame burst")
      return
    }
    #expect(failure == "terminal capture failure")

    #expect(mailbox.diagnostics().pendingEventCount == 0)
    mailbox.finish()
    if await mailbox.next() != nil {
      Issue.record("Expected a finished mailbox to return nil")
    }
  }

  @Test("slow frame consumer receives only the newest buffered frame")
  func newestFrameBackpressure() async throws {
    let device = CameraDevice(id: CameraDeviceID(rawValue: "camera"), name: "Camera")
    let driver = TestCameraDriver(devices: [device])
    let capture = CameraCapture(driver: driver)
    await capture.discoverDevices()
    await capture.start()
    let stream = await capture.frames()

    for value in UInt8(1)...UInt8(3) {
      await driver.emit(sample(value: value, time: UInt64(value)))
      try await waitUntil {
        await capture.snapshot().latestFrame?.frame.sequence == UInt64(value)
      }
    }
    var iterator = stream.makeAsyncIterator()
    let newest = await iterator.next()
    #expect(newest?.frame.sequence == 3)
    #expect(newest?.frame.bytes[0] == 3)
  }

  @Test("return-only exact materialization stays off preview until one explicit publication")
  func boundedPreviewAndExactMaterialization() async throws {
    let device = CameraDevice(id: CameraDeviceID(rawValue: "camera"), name: "Camera")
    let driver = TestCameraDriver(devices: [device])
    let capture = CameraCapture(
      driver: driver,
      materializationPolicy: LiveFrameMaterializationPolicy(
        minimumPreviewIntervalNanoseconds: 100
      )
    )
    await capture.discoverDevices()
    await capture.start()

    await driver.emit(sample(value: 1, time: 100))
    try await waitUntil { await capture.diagnostics().receivedFrameCount == 1 }
    let firstPreview = try #require(await capture.snapshot().latestFrame)
    #expect(firstPreview.frame.sequence == 1)
    #expect(await capture.diagnostics().totalMaterializedFrameCount == 1)
    #expect(await capture.diagnostics().previewMaterializedFrameCount == 1)
    #expect(await capture.diagnostics().ordinaryPreviewPublicationCount == 1)

    await driver.emit(sample(value: 2, time: 120))
    try await waitUntil { await capture.diagnostics().receivedFrameCount == 2 }
    await driver.emit(sample(value: 3, time: 150))
    try await waitUntil { await capture.diagnostics().receivedFrameCount == 3 }
    #expect(await capture.snapshot().latestFrame?.frame.id == firstPreview.frame.id)
    #expect(await capture.diagnostics().totalMaterializedFrameCount == 1)

    let exact = try #require(
      try await capture.materializeLatestFrame(
        newerThanNanoseconds: 100,
        policy: .returnOnly
      )
    )
    #expect(exact.frame.sequence == 3)
    #expect(exact.frame.captureNanoseconds == 150)
    #expect(exact.frame.bytes[0] == 3)
    #expect(await capture.diagnostics().totalMaterializedFrameCount == 2)
    #expect(await capture.diagnostics().exactMaterializedFrameCount == 1)
    #expect(await capture.diagnostics().returnOnlyExactRequestCount == 1)
    #expect(await capture.diagnostics().ordinaryPreviewPublicationCount == 1)
    #expect(await capture.diagnostics().explicitExactPublicationCount == 0)
    #expect(await capture.snapshot().latestFrame?.frame.id == firstPreview.frame.id)

    let repeated = try #require(
      try await capture.materializeLatestFrame(policy: .returnOnly)
    )
    #expect(repeated.frame.id == exact.frame.id)
    #expect(await capture.diagnostics().totalMaterializedFrameCount == 2)
    #expect(await capture.diagnostics().returnOnlyExactRequestCount == 2)
    #expect(
      try await capture.materializeLatestFrame(
        newerThanNanoseconds: 150,
        policy: .returnOnly
      ) == nil
    )

    #expect(try await capture.publishMaterializedExactFrame(exact) == .published)
    #expect(try await capture.publishMaterializedExactFrame(exact) == .alreadyPublished)
    let published = try #require(await capture.snapshot().latestFrame)
    #expect(published == exact)
    let diagnostics = await capture.diagnostics()
    #expect(diagnostics.ordinaryPreviewPublicationCount == 1)
    #expect(diagnostics.explicitExactPublicationCount == 1)
    #expect(diagnostics.lastReturnOnlyExactFrameID == exact.frame.id)
    #expect(diagnostics.lastExplicitlyPublishedExactFrameID == exact.frame.id)
  }

  @Test("exact publication rejects a value not retained by the active camera owner")
  func exactPublicationRequiresCameraOwnedProvenance() async throws {
    let device = CameraDevice(id: CameraDeviceID(rawValue: "camera"), name: "Camera")
    let driver = TestCameraDriver(devices: [device])
    let capture = CameraCapture(
      driver: driver,
      materializationPolicy: LiveFrameMaterializationPolicy(
        minimumPreviewIntervalNanoseconds: 100
      )
    )
    await capture.discoverDevices()
    await capture.start()

    await driver.emit(sample(value: 1, time: 100))
    try await waitUntil { await capture.diagnostics().receivedFrameCount == 1 }
    await driver.emit(sample(value: 2, time: 120))
    try await waitUntil { await capture.diagnostics().receivedFrameCount == 2 }
    let exact = try #require(
      try await capture.materializeLatestFrame(
        newerThanNanoseconds: 100,
        policy: .returnOnly
      )
    )
    let forgedFrame = try StampedFrame(
      id: exact.frame.id,
      sequence: exact.frame.sequence,
      captureNanoseconds: exact.frame.captureNanoseconds,
      cameraConfigurationID: exact.frame.cameraConfigurationID,
      width: exact.frame.width,
      height: exact.frame.height,
      rowBytes: exact.frame.rowBytes,
      pixelFormat: exact.frame.pixelFormat,
      bytes: OwnedFrameBytes([9, 9, 9, 9])
    )
    let forged = DisplayedFrame(source: exact.source, frame: forgedFrame)

    do {
      _ = try await capture.publishMaterializedExactFrame(forged)
      Issue.record("Expected CameraCapture to reject noncanonical exact bytes")
    } catch let error as ExactFramePublicationError {
      #expect(error == .notMaterializedByCurrentCapture)
    }
    #expect(await capture.diagnostics().explicitExactPublicationCount == 0)

    await capture.restart()
    do {
      _ = try await capture.publishMaterializedExactFrame(exact)
      Issue.record("Expected a prior-generation exact frame to be rejected")
    } catch let error as ExactFramePublicationError {
      #expect(error == .notMaterializedByCurrentCapture)
    }
  }

  @Test("preview pause retains newest raw capture and publishes it once after all owners settle")
  func previewPauseAndResume() async throws {
    let device = CameraDevice(id: CameraDeviceID(rawValue: "camera"), name: "Camera")
    let driver = TestCameraDriver(devices: [device])
    let capture = CameraCapture(driver: driver)
    await capture.discoverDevices()
    await capture.start()

    await driver.emit(sample(value: 1, time: 100))
    try await waitUntil { await capture.snapshot().latestFrame?.frame.sequence == 1 }
    let first = try #require(await capture.snapshot().latestFrame)
    let firstPause = await capture.pausePreviewPublication()
    let nestedPause = await capture.pausePreviewPublication()
    #expect(await capture.diagnostics().previewPublicationPaused)

    await driver.emit(sample(value: 2, time: 200))
    await driver.emit(sample(value: 3, time: 300))
    try await waitUntil { await capture.diagnostics().receivedFrameCount == 3 }
    #expect(await capture.snapshot().latestFrame?.frame.id == first.frame.id)
    #expect(await capture.diagnostics().previewMaterializedFrameCount == 1)

    await capture.resumePreviewPublication(firstPause)
    #expect(await capture.diagnostics().previewPublicationPaused)
    #expect(await capture.snapshot().latestFrame?.frame.id == first.frame.id)

    await capture.resumePreviewPublication(nestedPause)
    #expect(!(await capture.diagnostics()).previewPublicationPaused)
    let resumed = try #require(await capture.snapshot().latestFrame)
    #expect(resumed.frame.sequence == 3)
    #expect(resumed.frame.bytes[0] == 3)
    #expect(await capture.diagnostics().previewMaterializedFrameCount == 2)

    await capture.resumePreviewPublication(nestedPause)
    #expect(await capture.diagnostics().previewMaterializedFrameCount == 2)
    let diagnostics = await capture.diagnostics()
    #expect(diagnostics.previewPauseAcquisitionCount == 2)
    #expect(diagnostics.previewPauseReleaseCount == 2)
  }

  @Test("only CameraCapture issues live evidence attestations")
  func liveFrameAttestation() async throws {
    let device = CameraDevice(id: CameraDeviceID(rawValue: "camera"), name: "Camera")
    let driver = TestCameraDriver(devices: [device])
    let capture = CameraCapture(driver: driver)
    await capture.discoverDevices()
    await capture.start()

    await driver.emit(capSample(time: 100))
    try await waitUntil { await capture.diagnostics().receivedFrameCount == 1 }
    let attestation = try #require(
      try await capture.materializeLatestAttestedFrame(
        newerThanNanoseconds: 99,
        policy: .returnOnly
      )
    )
    #expect(attestation.cameraDeviceID == device.id)
    #expect(attestation.frame.captureNanoseconds == 100)
    #expect(
      try await capture.materializeLatestAttestedFrame(
        newerThanNanoseconds: 100,
        policy: .returnOnly
      ) == nil
    )

  }

  @Test("live camera attestation has no replay conformance")
  func evidenceCapabilitiesAreNotCodable() {
    let attestationType: Any.Type = LiveCameraFrameAttestation.self
    #expect(!(attestationType is any Encodable.Type))
    #expect(!(attestationType is any Decodable.Type))
  }

  @Test("simulator emits the same displayed-frame contract with a known transform")
  func simulatorContract() throws {
    let transform = try AffineTransform2<FieldSpace, CameraPixelSpace>(
      m11: 2, m12: 0, m21: 0, m22: 2, tx: 1, ty: 3)
    var simulator = try SimulatedFrameSource(
      width: 20,
      height: 20,
      fieldToCamera: transform
    )
    let fieldLine = try Polyline<FieldSpace>(
      points: [try Point2(x: 1, y: 1), try Point2(x: 4, y: 1)])
    let cameraLine = try simulator.cameraPolyline(from: fieldLine)
    let displayed = try simulator.render(
      strokes: [SimulatedCameraStroke(start: cameraLine.start, end: cameraLine.end)],
      captureNanoseconds: 10
    )
    #expect(displayed.source == .simulated)
    #expect(displayed.frame.pixelFormat == .bgra8)
    #expect(cameraLine.start == (try Point2<CameraPixelSpace>(x: 3, y: 5)))
  }
}

private typealias TestCameraEventHandler = @Sendable (CameraDriverEvent) -> Void

private actor TestCameraDriver: CameraCaptureDriver {
  var authorization: CameraAuthorizationState
  var devices: [CameraDevice]
  var requestAccessResult: Bool
  private let delayedDiscoveryCalls: Set<Int>
  private let delayedStartCalls: Set<Int>
  private var discoveryContinuations: [Int: CheckedContinuation<Void, Never>] = [:]
  private var startContinuations: [Int: CheckedContinuation<Void, Never>] = [:]
  private var eventHandler: TestCameraEventHandler?
  private var startHandlers: [TestCameraEventHandler] = []
  private let deliveryLimitOutcome: CameraDeliveryLimitOutcome?
  private(set) var discoveryCount = 0
  private(set) var startCount = 0
  private(set) var requestedMaximumFramesPerSecond: [Double?] = []
  private(set) var stopCount = 0
  private(set) var isActive = false

  init(
    authorization: CameraAuthorizationState = .authorized,
    devices: [CameraDevice],
    requestAccessResult: Bool = true,
    delayedDiscoveryCalls: Set<Int> = [],
    delayedStartCalls: Set<Int> = [],
    deliveryLimitOutcome: CameraDeliveryLimitOutcome? = nil
  ) {
    self.authorization = authorization
    self.devices = devices
    self.requestAccessResult = requestAccessResult
    self.delayedDiscoveryCalls = delayedDiscoveryCalls
    self.delayedStartCalls = delayedStartCalls
    self.deliveryLimitOutcome = deliveryLimitOutcome
  }

  func authorizationState() async -> CameraAuthorizationState { authorization }
  func requestAccess() async -> Bool { requestAccessResult }
  func discoverDevices() async -> [CameraDevice] {
    discoveryCount += 1
    let call = discoveryCount
    if delayedDiscoveryCalls.contains(call) {
      await withCheckedContinuation { continuation in
        discoveryContinuations[call] = continuation
      }
    }
    return devices
  }

  func start(
    deviceID: CameraDeviceID,
    maximumFramesPerSecond: Double?,
    eventHandler: @escaping @Sendable (CameraDriverEvent) -> Void
  ) async throws -> CameraCaptureDriverStartResult {
    guard devices.contains(where: { $0.id == deviceID }) else {
      throw CameraCaptureError.unknownDevice(deviceID)
    }
    startCount += 1
    requestedMaximumFramesPerSecond.append(maximumFramesPerSecond)
    let call = startCount
    startHandlers.append(eventHandler)
    if delayedStartCalls.contains(call) {
      await withCheckedContinuation { continuation in
        startContinuations[call] = continuation
      }
    }
    self.eventHandler = eventHandler
    isActive = true
    return CameraCaptureDriverStartResult(
      deliveryLimitOutcome: deliveryLimitOutcome
        ?? maximumFramesPerSecond.map { .applied(framesPerSecond: $0) }
        ?? .notRequested
    )
  }

  func stop() async {
    stopCount += 1
    eventHandler = nil
    isActive = false
  }

  func emit(_ event: CameraDriverEvent) {
    eventHandler?(event)
  }

  func emitFromStart(_ index: Int, _ event: CameraDriverEvent) {
    guard startHandlers.indices.contains(index) else { return }
    startHandlers[index](event)
  }

  func emitBatch(_ events: [CameraDriverEvent]) {
    guard let eventHandler else { return }
    for event in events { eventHandler(event) }
  }

  func resumeDiscovery(call: Int) {
    discoveryContinuations.removeValue(forKey: call)?.resume()
  }

  func resumeStart(call: Int) {
    startContinuations.removeValue(forKey: call)?.resume()
  }
}

private func sample(value: UInt8, time: UInt64) -> CameraDriverEvent {
  .frame(
    CapturedBGRAFrame(
      width: 1,
      height: 1,
      rowBytes: 4,
      bytes: Data(repeating: value, count: 4),
      captureNanoseconds: time
    ))
}

private func capSample(time: UInt64) -> CameraDriverEvent {
  let width = 12
  let height = 12
  var bytes = Array(repeating: UInt8(0), count: width * height * 4)
  for y in 4...5 {
    for x in 4...5 {
      let offset = (y * width + x) * 4
      bytes[offset + 1] = 255
      bytes[offset + 3] = 255
    }
  }
  return .frame(
    CapturedBGRAFrame(
      width: width,
      height: height,
      rowBytes: width * 4,
      bytes: Data(bytes),
      captureNanoseconds: time
    ))
}

private func waitUntil(
  attempts: Int = 200,
  condition: @escaping @Sendable () async -> Bool
) async throws {
  for _ in 0..<attempts {
    if await condition() { return }
    try await Task.sleep(nanoseconds: 1_000_000)
  }
  Issue.record("condition was not satisfied before the test deadline")
}

private func settleEvents() async throws {
  try await Task.sleep(nanoseconds: 10_000_000)
}
