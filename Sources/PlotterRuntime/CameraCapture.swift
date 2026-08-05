@preconcurrency import AVFoundation
import CoreMedia
import CoreVideo
import Foundation
import PlotterModel

public enum CameraAuthorizationState: String, Codable, Hashable, Sendable {
  case notDetermined
  case authorized
  case denied
  case restricted
}

public enum CameraCaptureError: Error, Codable, Hashable, Sendable {
  case permissionDenied
  case permissionRestricted
  case noDevices
  case selectionRequired(availableDeviceCount: Int)
  case unknownDevice(CameraDeviceID)
  case deviceDisconnected(CameraDeviceID)
  case configurationFailed(String)
  case captureFailed(String)

  public var actionableDescription: String {
    switch self {
    case .permissionDenied:
      return "Camera access is denied. Allow camera access in System Settings, then restart capture."
    case .permissionRestricted:
      return "Camera access is restricted for this process."
    case .noDevices:
      return "No video camera is connected. Connect one, refresh devices, and select it."
    case .selectionRequired(let count):
      return "Select one of the \(count) available cameras."
    case .unknownDevice(let id):
      return "The selected camera \(id.rawValue) is no longer available. Refresh and select a camera."
    case .deviceDisconnected:
      return "The selected camera disconnected. Reconnect it, refresh devices, and restart capture."
    case .configurationFailed(let message):
      return "Camera configuration failed: \(message)"
    case .captureFailed(let message):
      return "Camera capture failed: \(message)"
    }
  }
}

public enum CameraCaptureState: Codable, Hashable, Sendable {
  case stopped
  case discovering
  case ready
  case starting
  case running
  case interrupted(String)
  case failed(CameraCaptureError)
}

public struct CameraCaptureSnapshot: Codable, Hashable, Sendable {
  public let devices: [CameraDevice]
  public let selectedDeviceID: CameraDeviceID?
  public let state: CameraCaptureState
  public let latestFrame: DisplayedFrame?
  public let error: CameraCaptureError?

  public init(
    devices: [CameraDevice],
    selectedDeviceID: CameraDeviceID?,
    state: CameraCaptureState,
    latestFrame: DisplayedFrame?,
    error: CameraCaptureError?
  ) {
    self.devices = devices
    self.selectedDeviceID = selectedDeviceID
    self.state = state
    self.latestFrame = latestFrame
    self.error = error
  }
}

public struct CapturedBGRAFrame: Sendable {
  public let width: Int
  public let height: Int
  public let rowBytes: Int
  public let bytes: Data
  public let captureNanoseconds: UInt64

  public init(
    width: Int,
    height: Int,
    rowBytes: Int,
    bytes: Data,
    captureNanoseconds: UInt64
  ) {
    self.width = width
    self.height = height
    self.rowBytes = rowBytes
    self.bytes = bytes
    self.captureNanoseconds = captureNanoseconds
  }
}

public enum CameraDriverEvent: Sendable {
  case frame(CapturedBGRAFrame)
  case interrupted(String)
  case interruptionEnded
  case disconnected(CameraDeviceID)
  case failed(String)
}

struct CameraDriverEventMailboxDiagnostics: Equatable, Sendable {
  let pendingEventCount: Int
  let pendingFrameCount: Int
  let maximumPendingFrameCount: Int
}

/// One callback-order-preserving ingress per capture generation. Consecutive
/// frame bursts retain only their newest frame, while lifecycle/control events
/// are never coalesced or dropped.
final class CameraDriverEventMailbox: @unchecked Sendable {
  private let lock = NSLock()
  private var pending: [CameraDriverEvent] = []
  private var waiter: CheckedContinuation<CameraDriverEvent?, Never>?
  private var isFinished = false
  private var maximumPendingFrameCount = 0

  func yield(_ event: CameraDriverEvent) {
    let waiting: CheckedContinuation<CameraDriverEvent?, Never>? = lock.withLock {
      guard !isFinished else { return nil }
      if let waiter {
        self.waiter = nil
        return waiter
      }
      if event.isFrame, pending.last?.isFrame == true {
        pending[pending.count - 1] = event
      } else {
        pending.append(event)
      }
      maximumPendingFrameCount = max(
        maximumPendingFrameCount,
        pending.lazy.filter(\.isFrame).count
      )
      return nil
    }
    waiting?.resume(returning: event)
  }

  func next() async -> CameraDriverEvent? {
    await withCheckedContinuation { continuation in
      var immediate: CameraDriverEvent?
      var shouldResume = false
      lock.withLock {
        if !pending.isEmpty {
          immediate = pending.removeFirst()
          shouldResume = true
        } else if isFinished {
          shouldResume = true
        } else {
          precondition(waiter == nil, "Camera event mailbox supports one consumer.")
          waiter = continuation
        }
      }
      if shouldResume { continuation.resume(returning: immediate) }
    }
  }

  func finish() {
    let waiting: CheckedContinuation<CameraDriverEvent?, Never>? = lock.withLock {
      guard !isFinished else { return nil }
      isFinished = true
      pending.removeAll()
      let waiting = waiter
      waiter = nil
      return waiting
    }
    waiting?.resume(returning: nil)
  }

  func diagnostics() -> CameraDriverEventMailboxDiagnostics {
    lock.withLock {
      CameraDriverEventMailboxDiagnostics(
        pendingEventCount: pending.count,
        pendingFrameCount: pending.lazy.filter(\.isFrame).count,
        maximumPendingFrameCount: maximumPendingFrameCount
      )
    }
  }
}

private extension CameraDriverEvent {
  var isFrame: Bool {
    if case .frame = self { return true }
    return false
  }
}

/// Injectable at this narrow boundary so camera policy and frame ownership can
/// be tested without opening a physical device.
public protocol CameraCaptureDriver: Sendable {
  func authorizationState() async -> CameraAuthorizationState
  func requestAccess() async -> Bool
  func discoverDevices() async -> [CameraDevice]
  func start(
    deviceID: CameraDeviceID,
    eventHandler: @escaping @Sendable (CameraDriverEvent) -> Void
  ) async throws
  func stop() async
}

public actor CameraCapture {
  private struct PendingDriverStart {
    let generation: UUID
    let task: Task<Void, Error>
  }

  private let driver: any CameraCaptureDriver
  private var devices: [CameraDevice] = []
  private var selectedDeviceID: CameraDeviceID?
  private var state: CameraCaptureState = .stopped
  private var latestFrame: DisplayedFrame?
  private var error: CameraCaptureError?
  private var lifecycleGeneration = UUID()
  private var isStoppingDriver = false
  private var cameraConfigurationID: CameraConfigurationID?
  private var pendingDriverStart: PendingDriverStart?
  private var eventMailbox: CameraDriverEventMailbox?
  private var eventConsumer: Task<Void, Never>?
  private var nextSequence: UInt64 = 1
  private var lastTimestamp: UInt64 = 0
  private var frameContinuations: [UUID: AsyncStream<DisplayedFrame>.Continuation] = [:]

  public init() {
    driver = AVFoundationCameraDriver()
  }

  public init(driver: any CameraCaptureDriver) {
    self.driver = driver
  }

  public func discoverDevices() async {
    guard !isStoppingDriver, state != .starting else { return }
    let generation = lifecycleGeneration
    let preservesActiveCapture = state == .running || isInterrupted
    if !preservesActiveCapture { state = .discovering }
    let discovered = await driver.discoverDevices().sorted {
      if $0.name == $1.name { return $0.id.rawValue < $1.id.rawValue }
      return $0.name.localizedStandardCompare($1.name) == .orderedAscending
    }
    guard generation == lifecycleGeneration, !isStoppingDriver else { return }
    devices = discovered

    let selectionWasLost = selectedDeviceID.map { selected in
      !discovered.contains(where: { $0.id == selected })
    } ?? false
    if selectionWasLost || (discovered.isEmpty && preservesActiveCapture) {
      guard let stoppedGeneration = await stopDriver() else { return }
      guard stoppedGeneration == lifecycleGeneration, !isStoppingDriver else { return }
      self.selectedDeviceID = nil
      latestFrame = nil
    }
    if selectedDeviceID == nil, discovered.count == 1 {
      selectedDeviceID = discovered[0].id
    }
    if discovered.isEmpty {
      fail(.noDevices)
    } else if !preservesActiveCapture || selectionWasLost {
      state = .ready
      error = nil
    }
  }

  public func select(_ id: CameraDeviceID) async throws {
    guard !isStoppingDriver else { return }
    guard devices.contains(where: { $0.id == id }) else {
      let issue = CameraCaptureError.unknownDevice(id)
      if state == .running || state == .starting || isInterrupted {
        guard let stoppedGeneration = await stopDriver() else { throw issue }
        guard stoppedGeneration == lifecycleGeneration, !isStoppingDriver else { throw issue }
      } else {
        _ = beginLifecycleGeneration()
      }
      fail(issue)
      throw issue
    }
    if state == .running || state == .starting || isInterrupted {
      guard let stoppedGeneration = await stopDriver() else { return }
      guard stoppedGeneration == lifecycleGeneration, !isStoppingDriver else { return }
    } else {
      _ = beginLifecycleGeneration()
    }
    selectedDeviceID = id
    latestFrame = nil
    cameraConfigurationID = nil
    state = .ready
    error = nil
  }

  public func start() async {
    guard !isStoppingDriver, state != .running, state != .starting else { return }
    let generation = beginLifecycleGeneration()
    let configurationID = CameraConfigurationID()
    cameraConfigurationID = configurationID
    state = .starting
    error = nil

    let authorizationState = await driver.authorizationState()
    guard generation == lifecycleGeneration, !isStoppingDriver, state == .starting else { return }
    switch authorizationState {
    case .denied:
      fail(.permissionDenied)
      return
    case .restricted:
      fail(.permissionRestricted)
      return
    case .notDetermined:
      let granted = await driver.requestAccess()
      guard generation == lifecycleGeneration, !isStoppingDriver, state == .starting else { return }
      guard granted else {
        fail(.permissionDenied)
        return
      }
    case .authorized:
      break
    }

    if devices.isEmpty {
      let discovered = await driver.discoverDevices().sorted {
        if $0.name == $1.name { return $0.id.rawValue < $1.id.rawValue }
        return $0.name.localizedStandardCompare($1.name) == .orderedAscending
      }
      guard generation == lifecycleGeneration, !isStoppingDriver, state == .starting else { return }
      devices = discovered
      if discovered.count == 1 { selectedDeviceID = discovered[0].id }
    }
    guard !devices.isEmpty else {
      fail(.noDevices)
      return
    }
    guard let selectedDeviceID else {
      fail(.selectionRequired(availableDeviceCount: devices.count))
      return
    }
    guard devices.contains(where: { $0.id == selectedDeviceID }) else {
      fail(.unknownDevice(selectedDeviceID))
      return
    }

    latestFrame = nil
    let mailbox = CameraDriverEventMailbox()
    eventMailbox = mailbox
    let driver = self.driver
    let startTask = Task {
      try await driver.start(deviceID: selectedDeviceID) { event in
        mailbox.yield(event)
      }
    }
    pendingDriverStart = PendingDriverStart(generation: generation, task: startTask)
    do {
      try await startTask.value
      clearPendingDriverStart(generation: generation)
      guard generation == lifecycleGeneration, !isStoppingDriver, state == .starting else {
        mailbox.finish()
        return
      }
      state = .running
      eventConsumer = Task { [weak self] in
        while let event = await mailbox.next() {
          guard !Task.isCancelled, let self else { return }
          await self.receive(
            event,
            generation: generation,
            configurationID: configurationID
          )
        }
      }
    } catch let issue as CameraCaptureError {
      clearPendingDriverStart(generation: generation)
      guard generation == lifecycleGeneration, !isStoppingDriver else { return }
      await stopDriverAndFail(issue)
    } catch let startError {
      clearPendingDriverStart(generation: generation)
      guard generation == lifecycleGeneration, !isStoppingDriver else { return }
      await stopDriverAndFail(.configurationFailed(String(describing: startError)))
    }
  }

  public func stop() async {
    guard let generation = await stopDriver() else { return }
    guard generation == lifecycleGeneration, !isStoppingDriver else { return }
    state = .stopped
    error = nil
  }

  public func restart() async {
    await stop()
    await start()
  }

  public func snapshot() async -> CameraCaptureSnapshot {
    CameraCaptureSnapshot(
      devices: devices,
      selectedDeviceID: selectedDeviceID,
      state: state,
      latestFrame: latestFrame,
      error: error
    )
  }

  public func frames() -> AsyncStream<DisplayedFrame> {
    let identifier = UUID()
    let stream = AsyncStream<DisplayedFrame>(bufferingPolicy: .bufferingNewest(1)) {
      continuation in
      frameContinuations[identifier] = continuation
      if let latestFrame { continuation.yield(latestFrame) }
      continuation.onTermination = { [weak self] _ in
        guard let self else { return }
        Task { await self.removeContinuation(identifier) }
      }
    }
    return stream
  }

  private var isInterrupted: Bool {
    if case .interrupted = state { return true }
    return false
  }

  private func removeContinuation(_ identifier: UUID) {
    frameContinuations.removeValue(forKey: identifier)
  }

  private func receive(
    _ event: CameraDriverEvent,
    generation: UUID,
    configurationID: CameraConfigurationID
  ) async {
    guard generation == lifecycleGeneration, configurationID == cameraConfigurationID else {
      return
    }
    switch event {
    case .frame(let captured):
      guard state == .running else { return }
      guard nextSequence < UInt64.max, lastTimestamp < UInt64.max else {
        await stopDriverAndFail(
          .captureFailed("Frame sequence or monotonic timestamp exhausted."))
        return
      }
      let timestamp = max(captured.captureNanoseconds, lastTimestamp + 1)
      do {
        let stamped = try StampedFrame(
          sequence: nextSequence,
          captureNanoseconds: timestamp,
          cameraConfigurationID: configurationID,
          width: captured.width,
          height: captured.height,
          rowBytes: captured.rowBytes,
          pixelFormat: .bgra8,
          bytes: OwnedFrameBytes(copying: captured.bytes)
        )
        nextSequence &+= 1
        lastTimestamp = timestamp
        guard let selectedDeviceID else { return }
        let displayed = DisplayedFrame(source: .live(selectedDeviceID), frame: stamped)
        latestFrame = displayed
        for continuation in frameContinuations.values { continuation.yield(displayed) }
      } catch {
        await stopDriverAndFail(.captureFailed(String(describing: error)))
      }
    case .interrupted(let reason):
      guard state == .running || state == .starting else { return }
      state = .interrupted(reason)
      error = .captureFailed("Capture interrupted: \(reason)")
    case .interruptionEnded:
      guard case .interrupted = state else { return }
      state = .running
      error = nil
    case .disconnected(let deviceID):
      latestFrame = nil
      await stopDriverAndFail(.deviceDisconnected(deviceID))
    case .failed(let message):
      await stopDriverAndFail(.captureFailed(message))
    }
  }

  private func beginLifecycleGeneration() -> UUID {
    let generation = UUID()
    lifecycleGeneration = generation
    cameraConfigurationID = nil
    finishEventChannel()
    return generation
  }

  private func finishEventChannel() {
    eventMailbox?.finish()
    eventMailbox = nil
    eventConsumer?.cancel()
    eventConsumer = nil
  }

  private func clearPendingDriverStart(generation: UUID) {
    guard pendingDriverStart?.generation == generation else { return }
    pendingDriverStart = nil
  }

  /// Invalidates callbacks first, then waits for any in-progress start and the
  /// driver's stop before a caller publishes a non-running state.
  private func stopDriver() async -> UUID? {
    guard !isStoppingDriver else { return nil }
    let generation = beginLifecycleGeneration()
    isStoppingDriver = true
    let pendingStart = pendingDriverStart
    pendingStart?.task.cancel()
    if let pendingStart {
      _ = await pendingStart.task.result
      guard generation == lifecycleGeneration else { return nil }
    }
    await driver.stop()
    guard generation == lifecycleGeneration else { return nil }
    pendingDriverStart = nil
    isStoppingDriver = false
    return generation
  }

  private func stopDriverAndFail(_ issue: CameraCaptureError) async {
    guard let generation = await stopDriver() else { return }
    guard generation == lifecycleGeneration, !isStoppingDriver else { return }
    fail(issue)
  }

  private func fail(_ issue: CameraCaptureError) {
    cameraConfigurationID = nil
    error = issue
    state = .failed(issue)
  }
}

private final class AVFrameDelegate: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate,
  @unchecked Sendable
{
  private let eventHandler: @Sendable (CameraDriverEvent) -> Void

  init(eventHandler: @escaping @Sendable (CameraDriverEvent) -> Void) {
    self.eventHandler = eventHandler
  }

  func captureOutput(
    _ output: AVCaptureOutput,
    didOutput sampleBuffer: CMSampleBuffer,
    from connection: AVCaptureConnection
  ) {
    guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
      eventHandler(.failed("Capture delivered a sample without a pixel buffer."))
      return
    }
    guard CVPixelBufferGetPixelFormatType(pixelBuffer) == kCVPixelFormatType_32BGRA else {
      eventHandler(.failed("Capture delivered a non-BGRA pixel buffer."))
      return
    }
    CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
    defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
    guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
      eventHandler(.failed("Capture delivered a pixel buffer without readable storage."))
      return
    }
    let width = CVPixelBufferGetWidth(pixelBuffer)
    let height = CVPixelBufferGetHeight(pixelBuffer)
    let rowBytes = CVPixelBufferGetBytesPerRow(pixelBuffer)
    let owned = Data(bytes: baseAddress, count: rowBytes * height)
    eventHandler(
      .frame(
        CapturedBGRAFrame(
          width: width,
          height: height,
          rowBytes: rowBytes,
          bytes: owned,
          captureNanoseconds: DispatchTime.now().uptimeNanoseconds
        )))
  }
}

private actor AVFoundationCameraDriver: CameraCaptureDriver {
  private let session = AVCaptureSession()
  private let captureQueue = DispatchQueue(label: "AdaptivePlotter.CameraCapture.frames")
  private var output: AVCaptureVideoDataOutput?
  private var delegate: AVFrameDelegate?
  private var notificationTokens: [NSObjectProtocol] = []

  func authorizationState() async -> CameraAuthorizationState {
    switch AVCaptureDevice.authorizationStatus(for: .video) {
    case .notDetermined: .notDetermined
    case .authorized: .authorized
    case .denied: .denied
    case .restricted: .restricted
    @unknown default: .restricted
    }
  }

  func requestAccess() async -> Bool {
    await withCheckedContinuation { continuation in
      AVCaptureDevice.requestAccess(for: .video) { granted in
        continuation.resume(returning: granted)
      }
    }
  }

  func discoverDevices() async -> [CameraDevice] {
    AVCaptureDevice.DiscoverySession(
      deviceTypes: [.builtInWideAngleCamera, .external],
      mediaType: .video,
      position: .unspecified
    ).devices.map {
      CameraDevice(id: CameraDeviceID(rawValue: $0.uniqueID), name: $0.localizedName)
    }
  }

  func start(
    deviceID: CameraDeviceID,
    eventHandler: @escaping @Sendable (CameraDriverEvent) -> Void
  ) async throws {
    stopSession()
    guard let device = AVCaptureDevice(uniqueID: deviceID.rawValue) else {
      throw CameraCaptureError.unknownDevice(deviceID)
    }

    let input: AVCaptureDeviceInput
    do {
      input = try AVCaptureDeviceInput(device: device)
    } catch {
      throw CameraCaptureError.configurationFailed(String(describing: error))
    }
    let output = AVCaptureVideoDataOutput()
    output.alwaysDiscardsLateVideoFrames = true
    output.videoSettings = [
      kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)
    ]
    let delegate = AVFrameDelegate(eventHandler: eventHandler)
    output.setSampleBufferDelegate(delegate, queue: captureQueue)

    session.beginConfiguration()
    guard session.canAddInput(input), session.canAddOutput(output) else {
      session.commitConfiguration()
      throw CameraCaptureError.configurationFailed(
        "The selected camera cannot provide a BGRA video stream.")
    }
    session.addInput(input)
    session.addOutput(output)
    session.commitConfiguration()
    self.output = output
    self.delegate = delegate
    installNotifications(device: device, eventHandler: eventHandler)
    session.startRunning()
    guard session.isRunning else {
      throw CameraCaptureError.configurationFailed("The capture session did not start.")
    }
  }

  func stop() async {
    stopSession()
  }

  private func stopSession() {
    if session.isRunning { session.stopRunning() }
    for input in session.inputs { session.removeInput(input) }
    for output in session.outputs { session.removeOutput(output) }
    for token in notificationTokens { NotificationCenter.default.removeObserver(token) }
    notificationTokens.removeAll()
    output = nil
    delegate = nil
  }

  private func installNotifications(
    device: AVCaptureDevice,
    eventHandler: @escaping @Sendable (CameraDriverEvent) -> Void
  ) {
    let center = NotificationCenter.default
    notificationTokens.append(
      center.addObserver(
        forName: AVCaptureSession.wasInterruptedNotification,
        object: session,
        queue: nil
      ) { _ in eventHandler(.interrupted("capture session interrupted")) })
    notificationTokens.append(
      center.addObserver(
        forName: AVCaptureSession.interruptionEndedNotification,
        object: session,
        queue: nil
      ) { _ in eventHandler(.interruptionEnded) })
    notificationTokens.append(
      center.addObserver(
        forName: AVCaptureSession.runtimeErrorNotification,
        object: session,
        queue: nil
      ) { notification in
        let message =
          (notification.userInfo?[AVCaptureSessionErrorKey] as? NSError)?.localizedDescription
          ?? "unknown runtime error"
        eventHandler(.failed(message))
      })
    notificationTokens.append(
      center.addObserver(
        forName: AVCaptureDevice.wasDisconnectedNotification,
        object: device,
        queue: nil
      ) { _ in eventHandler(.disconnected(CameraDeviceID(rawValue: device.uniqueID))) })
  }
}
